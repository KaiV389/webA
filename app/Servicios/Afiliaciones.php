<?php
declare(strict_types=1);

namespace App\Servicios;

use App\Core\Ajustes;
use App\Core\Bitacora;
use App\Core\Config;
use App\Core\Db;
use App\Core\ErrorNegocio;
use PDO;

/**
 * Reglas de afiliación y renovación.
 *
 * Flujo de una afiliación nueva:
 *   Form → Apps Script → registrar()  → queda PENDIENTE (alerta si hay veto)
 *   Kai autoriza       → aprobar()    → folio del año, tipo, vigencia y 3 documentos con QR
 *
 * Flujo de una renovación:
 *   Form → Apps Script → renovar()    → se aprueba en el acto con folio nuevo del año
 *                                        (salvo veto: queda pendiente "en revisión")
 *
 * Todas las operaciones son seguras ante reintentos: si el Apps Script
 * manda dos veces lo mismo, la segunda devuelve el resultado de la primera.
 */
final class Afiliaciones
{
    // ------------------------------------------------------------------
    //  Registro desde el Form de afiliación
    // ------------------------------------------------------------------

    public function registrar(array $d): array
    {
        $curp   = strtoupper(trim((string) ($d['curp'] ?? '')));
        $nombre = Catalogos::nombrePropio($d['nombre_completo'] ?? '');
        $correo = strtolower(trim((string) ($d['correo'] ?? '')));
        $escuelaNombre = trim((string) ($d['escuela']['nombre'] ?? ''));

        $faltan = [];
        if ($nombre === '')                                 $faltan[] = 'nombre_completo';
        if (!Catalogos::curpValida($curp))                  $faltan[] = 'curp (válida)';
        if (!filter_var($correo, FILTER_VALIDATE_EMAIL))    $faltan[] = 'correo (válido)';
        if ($escuelaNombre === '')                          $faltan[] = 'escuela.nombre';
        if ($faltan) {
            throw new ErrorNegocio('Faltan o no son válidos: ' . implode(', ', $faltan), 422, ['campos' => $faltan]);
        }

        $anio = Ajustes::anioActual();
        $fechaRegistro = $this->fecha($d['marca_temporal'] ?? null);
        $estadoId = Catalogos::estadoId($d['escuela']['estado'] ?? null, $curp);

        return Db::transaccion(function (PDO $pdo) use ($d, $curp, $nombre, $correo, $escuelaNombre, $anio, $fechaRegistro, $estadoId) {
            $personaId = $this->guardarPersona($curp, $nombre, $correo, $d, $estadoId);

            // ¿Ya tiene registro este año? (doble envío del Form o afiliado que vuelve a llenarlo)
            $existente = Db::uno(
                'SELECT id, estatus, folio FROM afiliaciones WHERE persona_id = ? AND anio = ?',
                [$personaId, $anio]
            );
            if ($existente) {
                return [
                    'resultado'     => 'ya_registrado',
                    'afiliacion_id' => (int) $existente['id'],
                    'estatus'       => $existente['estatus'],
                    'folio'         => $existente['folio'],
                ];
            }

            $veto = $this->vetoActivo($personaId, $curp);
            $escuelaId = $this->guardarEscuela($escuelaNombre, $d['escuela'] ?? [], $estadoId);
            $anterior = Db::uno(
                "SELECT id FROM afiliaciones WHERE persona_id = ? AND anio < ? AND folio IS NOT NULL ORDER BY anio DESC LIMIT 1",
                [$personaId, $anio]
            );

            Db::ejecutar(
                "INSERT INTO afiliaciones (persona_id, anio, escuela_id, estatus, motivo_estatus, origen,
                                           afiliacion_anterior_id, fecha_registro, datos_form, carta_compromiso_url)
                 VALUES (?, ?, ?, 'pendiente', ?, 'form_afiliacion', ?, ?, ?, ?)",
                [
                    $personaId, $anio, $escuelaId,
                    $veto ? 'ALERTA DE VETO: revisar antes de aprobar' : null,
                    $anterior['id'] ?? null,
                    $fechaRegistro,
                    json_encode($d['respuesta_form'] ?? null, JSON_UNESCAPED_UNICODE),
                    $this->urlCarta($d),
                ]
            );
            $id = (int) $pdo->lastInsertId();
            $nRecon = $this->guardarReconocimientos($personaId, $d['reconocimientos'] ?? []);
            Bitacora::registrar('registrar', 'afiliacion', $id, null, ['persona_id' => $personaId, 'veto' => $veto]);

            return [
                'resultado'          => 'pendiente',
                'afiliacion_id'      => $id,
                'persona_id'         => $personaId,
                'alerta_veto'        => $veto,
                'afiliado_anterior'  => (bool) $anterior,   // ya estuvo afiliado otro año
                'falta_carta'        => $this->urlCarta($d) === null,
                'reconocimientos'    => $nRecon,             // archivos de cursos recibidos, por validar
            ];
        });
    }

    // ------------------------------------------------------------------
    //  Aprobación: folio, tipo, vigencia y documentos
    // ------------------------------------------------------------------

    /**
     * @param int|null   $cursosValidos    número de cursos; si viene, manda sobre lo que hay en la base
     * @param int|null   $aprobadaPor      persona que autorizó (para la constancia de autorizaciones)
     * @param array|null $cursosValidados  cursos que Kai validó al revisar (clave o nombre): quedan
     *                                     registrados como reconocimientos válidos y cuentan para el tipo
     */
    public function aprobar(int $afiliacionId, ?int $cursosValidos = null, ?int $aprobadaPor = null,
                            ?array $cursosValidados = null): array
    {
        return Db::transaccion(function (PDO $pdo) use ($afiliacionId, $cursosValidos, $aprobadaPor, $cursosValidados) {
            return $this->aprobarEnTransaccion($pdo, $afiliacionId, $cursosValidos, $aprobadaPor, $cursosValidados);
        });
    }

    private function aprobarEnTransaccion(PDO $pdo, int $afiliacionId, ?int $cursosValidos, ?int $aprobadaPor,
                                          ?array $cursosValidados = null): array
    {
        $st = $pdo->prepare('SELECT * FROM afiliaciones WHERE id = ? FOR UPDATE');
        $st->execute([$afiliacionId]);
        $a = $st->fetch();
        if (!$a) {
            throw new ErrorNegocio('No existe esa solicitud de afiliación', 404);
        }
        if ($a['estatus'] === 'activa') {
            return $this->datosAprobada($afiliacionId);   // reintento: devuelve lo mismo
        }
        if ($a['estatus'] !== 'pendiente') {
            throw new ErrorNegocio('La solicitud está en estatus "' . $a['estatus'] . '" y no se puede aprobar', 409);
        }
        if ($this->vetoActivo((int) $a['persona_id'], null)) {
            throw new ErrorNegocio('La persona tiene un veto activo; la aprobación debe hacerse a mano', 409);
        }
        $requiereCarta = $a['origen'] === 'form_renovacion'
            ? Ajustes::get('renovacion.requiere_carta', true)
            : Ajustes::get('afiliacion.requiere_carta', true);
        if ($requiereCarta && empty($a['carta_compromiso_url'])) {
            throw new ErrorNegocio('Falta la carta de declaración de responsabilidad y compromiso firmada', 409,
                ['resultado' => 'falta_carta']);
        }

        $anio = (int) $a['anio'];
        if ($cursosValidados !== null) {
            $this->validarCursos((int) $a['persona_id'], $cursosValidados, $aprobadaPor);
        }
        $cursos = $cursosValidos ?? $this->cursosValidos((int) $a['persona_id'], $anio);
        [$tipo, $grado] = $this->tipoPorCursos($cursos);
        $vigencia = $this->vigencia($anio, $tipo);

        $num = Folios::siguiente($pdo, $anio, 'AFI');
        $folio = Folios::formatear($anio, 'AFI', $num);

        Db::ejecutar(
            "UPDATE afiliaciones
                SET serie = 'AFI', consecutivo = ?, folio = ?, tipo_credencial = ?, grado = ?, cursos_validos = ?,
                    vigencia = ?, estatus = 'activa', motivo_estatus = NULL,
                    aprobada_por = ?, aprobada_at = NOW()
              WHERE id = ?",
            [$num, $folio, $tipo, $grado, $cursos, $vigencia, $aprobadaPor, $afiliacionId]
        );
        Db::ejecutar(
            'UPDATE personas SET fecha_primera_afiliacion = COALESCE(fecha_primera_afiliacion, ?) WHERE id = ?',
            [substr($a['fecha_registro'], 0, 10), $a['persona_id']]
        );

        // Los 3 documentos comparten número; solo cambia la serie. El token
        // existe ANTES del PDF para que el QR se pueda imprimir en él.
        foreach (Folios::SERIES_DOCUMENTO as $tipoDoc => $serie) {
            Db::ejecutar(
                'INSERT INTO documentos (tipo, folio, persona_id, afiliacion_id, autorizado_por, verificacion_token)
                 VALUES (?, ?, ?, ?, ?, ?)',
                [$tipoDoc, Folios::formatear($anio, $serie, $num), $a['persona_id'], $afiliacionId, $aprobadaPor,
                 bin2hex(random_bytes(16))]
            );
        }

        if ($aprobadaPor) {
            Db::ejecutar(
                "INSERT INTO autorizaciones (entidad, entidad_id, accion, persona_id, rol_usado) VALUES ('afiliacion', ?, 'autorizar', ?, 'mesa_nacional')",
                [$afiliacionId, $aprobadaPor]
            );
        }
        Bitacora::registrar('aprobar', 'afiliacion', $afiliacionId, ['estatus' => 'pendiente'],
            ['estatus' => 'activa', 'folio' => $folio, 'tipo' => $tipo], $aprobadaPor);

        return $this->datosAprobada($afiliacionId);
    }

    // ------------------------------------------------------------------
    //  Renovación desde el Form de renovación
    // ------------------------------------------------------------------

    public function renovar(array $d): array
    {
        $interpretado = Folios::interpretar($d['folio_anterior'] ?? '');
        if (!$interpretado) {
            throw new ErrorNegocio('No se reconoce el folio capturado', 404, ['resultado' => 'folio_no_reconocido']);
        }
        $interpretado['anio'] ??= Ajustes::anioActual() - 1;
        $anterior = Db::uno(
            "SELECT a.*, p.nombre_completo
               FROM afiliaciones a JOIN personas p ON p.id = a.persona_id
              WHERE a.anio = ? AND a.serie = 'AFI' AND a.consecutivo = ?",
            [$interpretado['anio'], $interpretado['consecutivo']]
        );
        if (!$anterior) {
            throw new ErrorNegocio('No existe una afiliación con ese folio', 404, ['resultado' => 'folio_no_encontrado']);
        }

        $anio = Ajustes::anioActual();
        if ((int) $anterior['anio'] >= $anio) {
            throw new ErrorNegocio('Ese folio ya corresponde al año en curso', 409, [
                'resultado' => 'ya_afiliado_este_anio', 'folio' => $anterior['folio']]);
        }
        $personaId = (int) $anterior['persona_id'];

        // Aviso si el nombre capturado no se parece al registrado (posible folio ajeno)
        $nombreCapturado = Catalogos::normalizar($d['nombre_completo'] ?? '');
        $coincideNombre = $nombreCapturado === '' || $this->nombresParecidos($nombreCapturado, Catalogos::normalizar($anterior['nombre_completo']));

        return Db::transaccion(function (PDO $pdo) use ($d, $anterior, $anio, $personaId, $coincideNombre) {
            $existente = Db::uno('SELECT id, estatus FROM afiliaciones WHERE persona_id = ? AND anio = ?', [$personaId, $anio]);
            if ($existente) {
                if ($existente['estatus'] === 'activa') {
                    return ['resultado' => 'ya_renovado'] + $this->datosAprobada((int) $existente['id']);
                }
                return ['resultado' => 'ya_registrado', 'afiliacion_id' => (int) $existente['id'], 'estatus' => $existente['estatus']];
            }

            // Datos de contacto actualizados, si los mandó
            $tel = preg_replace('/\D/', '', (string) ($d['telefono'] ?? ''));
            $correo = strtolower(trim((string) ($d['correo'] ?? '')));
            Db::ejecutar(
                'UPDATE personas SET telefono = COALESCE(?, telefono), correo = COALESCE(?, correo) WHERE id = ?',
                [strlen($tel) === 10 ? $tel : null, filter_var($correo, FILTER_VALIDATE_EMAIL) ? $correo : null, $personaId]
            );

            $veto = $this->vetoActivo($personaId, null);
            $carta = $this->urlCarta($d);
            $faltaCarta = $carta === null && Ajustes::get('renovacion.requiere_carta', true);
            $alerta = $veto ? 'ALERTA DE VETO: revisar antes de aprobar'
                    : (!$coincideNombre ? 'El nombre capturado no coincide con el del folio: revisar'
                    : ($faltaCarta ? 'Falta la carta de compromiso firmada' : null));

            Db::ejecutar(
                "INSERT INTO afiliaciones (persona_id, anio, escuela_id, estatus, motivo_estatus, origen,
                                           afiliacion_anterior_id, fecha_registro, datos_form, carta_compromiso_url)
                 VALUES (?, ?, ?, 'pendiente', ?, 'form_renovacion', ?, ?, ?, ?)",
                [$personaId, $anio, $anterior['escuela_id'], $alerta, $anterior['id'],
                 $this->fecha($d['marca_temporal'] ?? null),
                 json_encode($d['respuesta_form'] ?? null, JSON_UNESCAPED_UNICODE), $carta]
            );
            $id = (int) $pdo->lastInsertId();
            $nRecon = $this->guardarReconocimientos($personaId, array_map(
                fn($url) => ['curso' => null, 'archivo_url' => $url],
                (array) ($d['reconocimientos_nuevos'] ?? [])
            ));
            Bitacora::registrar('renovar', 'afiliacion', $id, null, ['anterior' => (int) $anterior['id'], 'alerta' => $alerta]);

            // Sin alertas, la renovación se aprueba en el acto
            if ($alerta) {
                return ['resultado' => 'en_revision', 'afiliacion_id' => $id, 'alerta_veto' => $veto,
                        'nombre_no_coincide' => !$coincideNombre, 'falta_carta' => $faltaCarta,
                        'reconocimientos_por_revisar' => $nRecon];
            }
            // Se aprueba con los cursos ya validados en la base; si mandó reconocimientos
            // nuevos, se avisa para revisarlos y reexpedir la credencial si cambia el tipo.
            return ['resultado' => 'renovada', 'reconocimientos_por_revisar' => $nRecon]
                 + $this->aprobarEnTransaccion($pdo, $id, null, null);
        });
    }

    /** Agrega o reemplaza la carta de compromiso de una solicitud pendiente. */
    public function adjuntarCarta(int $afiliacionId, array $d): array
    {
        $url = $this->urlCarta($d);
        if ($url === null) {
            throw new ErrorNegocio('carta_compromiso_url debe ser una liga https', 422);
        }
        $a = Db::uno('SELECT estatus, motivo_estatus FROM afiliaciones WHERE id = ?', [$afiliacionId]);
        if (!$a) {
            throw new ErrorNegocio('No existe esa solicitud de afiliación', 404);
        }
        Db::ejecutar(
            "UPDATE afiliaciones
                SET carta_compromiso_url = ?,
                    motivo_estatus = IF(motivo_estatus = 'Falta la carta de compromiso firmada', NULL, motivo_estatus)
              WHERE id = ?",
            [$url, $afiliacionId]
        );
        Bitacora::registrar('adjuntar_carta', 'afiliacion', $afiliacionId, null, ['carta' => $url]);
        return ['resultado' => 'carta_guardada', 'afiliacion_id' => $afiliacionId, 'estatus' => $a['estatus']];
    }

    // ------------------------------------------------------------------
    //  Consultas
    // ------------------------------------------------------------------

    /** Bandeja de solicitudes pendientes, las más antiguas primero. */
    public function pendientes(): array
    {
        return Db::todos(
            "SELECT a.id AS afiliacion_id, a.anio, a.origen, a.fecha_registro, a.motivo_estatus AS alerta,
                    a.carta_compromiso_url,
                    p.nombre_completo, p.foto_url, e.nombre AS escuela, es.nombre AS estado,
                    ant.folio AS folio_anterior
               FROM afiliaciones a
               JOIN personas p          ON p.id = a.persona_id
               LEFT JOIN escuelas e     ON e.id = a.escuela_id
               LEFT JOIN estados es     ON es.id = e.estado_id
               LEFT JOIN afiliaciones ant ON ant.id = a.afiliacion_anterior_id
              WHERE a.estatus = 'pendiente'
              ORDER BY a.fecha_registro"
        );
    }

    /** Lo que necesita el Apps Script para generar los PDFs y mandar el correo. */
    public function datosAprobada(int $afiliacionId): array
    {
        $a = Db::uno(
            "SELECT a.id, a.anio, a.folio, a.tipo_credencial, a.grado, a.cursos_validos, a.vigencia,
                    p.id AS persona_id, p.nombre_completo, p.correo, p.foto_url,
                    e.nombre AS escuela, e.logo_url, e.municipio, es.nombre AS estado
               FROM afiliaciones a
               JOIN personas p      ON p.id = a.persona_id
               LEFT JOIN escuelas e ON e.id = a.escuela_id
               LEFT JOIN estados es ON es.id = e.estado_id
              WHERE a.id = ?",
            [$afiliacionId]
        );
        $base = rtrim((string) Config::get('url_base', ''), '/');
        $docs = array_map(fn($d) => [
            'tipo'          => $d['tipo'],
            'folio'         => $d['folio'],
            'url_verificar' => $base . '/verificar/' . $d['verificacion_token'],
            'token'         => $d['verificacion_token'],
        ], Db::todos(
            "SELECT tipo, folio, verificacion_token FROM documentos
              WHERE afiliacion_id = ? AND anulado = 0 ORDER BY FIELD(tipo,'afiliacion','constancia_afiliacion','credencial')",
            [$afiliacionId]
        ));

        return [
            'resultado'      => 'aprobada',
            'afiliacion_id'  => (int) $a['id'],
            'folio'          => $a['folio'],
            'anio'           => (int) $a['anio'],
            'tipo'           => $a['tipo_credencial'],
            'grado'          => $a['grado'],
            'cursos_validos' => (int) $a['cursos_validos'],
            'vigencia'       => $a['vigencia'],
            'persona'        => [
                'id' => (int) $a['persona_id'], 'nombre_completo' => $a['nombre_completo'],
                'correo' => $a['correo'], 'foto_url' => $a['foto_url'],
            ],
            'escuela'        => [
                'nombre' => $a['escuela'], 'logo_url' => $a['logo_url'],
                'municipio' => $a['municipio'], 'estado' => $a['estado'],
            ],
            'documentos'     => $docs,
        ];
    }

    // ------------------------------------------------------------------
    //  Auxiliares
    // ------------------------------------------------------------------

    private function guardarPersona(string $curp, string $nombre, string $correo, array $d, ?int $estadoId): int
    {
        $tel = preg_replace('/\D/', '', (string) ($d['telefono'] ?? ''));
        $tel = strlen($tel) === 10 ? $tel : null;
        $curpDatos = Catalogos::datosCurp($curp);
        $existente = Db::uno('SELECT id FROM personas WHERE curp = ?', [$curp]);

        if ($existente) {
            // Se actualiza el contacto y se completan los huecos; nunca se borra nada
            Db::ejecutar(
                'UPDATE personas
                    SET correo = ?, telefono = COALESCE(?, telefono),
                        foto_url = COALESCE(?, foto_url), estado_id = COALESCE(estado_id, ?),
                        municipio = COALESCE(municipio, ?)
                  WHERE id = ?',
                [$correo, $tel, $d['foto_url'] ?? null, $estadoId, $d['escuela']['municipio'] ?? null, $existente['id']]
            );
            return (int) $existente['id'];
        }

        Db::ejecutar(
            'INSERT INTO personas (nombre_completo, curp, correo, telefono, fecha_nacimiento, sexo, estado_id, municipio, foto_url)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [$nombre, $curp, $correo, $tel, $curpDatos['fecha_nacimiento'], $curpDatos['sexo'], $estadoId,
             $d['escuela']['municipio'] ?? null, $d['foto_url'] ?? null]
        );
        return (int) Db::pdo()->lastInsertId();
    }

    private function guardarEscuela(string $nombre, array $e, ?int $estadoId): int
    {
        $clave = Catalogos::normalizar($nombre);
        foreach (Db::todos('SELECT id, nombre FROM escuelas WHERE estado_id <=> ?', [$estadoId]) as $fila) {
            if (Catalogos::normalizar($fila['nombre']) === $clave) {
                if (!empty($e['logo_url'])) {
                    Db::ejecutar('UPDATE escuelas SET logo_url = ? WHERE id = ?', [$e['logo_url'], $fila['id']]);
                }
                return (int) $fila['id'];
            }
        }
        Db::ejecutar(
            'INSERT INTO escuelas (nombre, logo_url, domicilio, municipio, estado_id) VALUES (?, ?, ?, ?, ?)',
            [trim($nombre), $e['logo_url'] ?? null, $e['domicilio'] ?? null, $e['municipio'] ?? null, $estadoId]
        );
        return (int) Db::pdo()->lastInsertId();
    }

    /**
     * Guarda como PENDIENTES los reconocimientos que llegan del Form.
     * Cada elemento: ['curso' => clave o nombre (o null si no se sabe), 'archivo_url' => liga o ligas
     * separadas por coma, como las entrega Google Forms]. No duplica archivos ya registrados.
     * Devuelve cuántos archivos nuevos se guardaron.
     */
    private function guardarReconocimientos(int $personaId, array $lista): int
    {
        $n = 0;
        foreach ($lista as $r) {
            $cursoId = $this->cursoId($r['curso'] ?? null);
            $nombre = $cursoId
                ? Db::uno('SELECT nombre FROM cursos WHERE id = ?', [$cursoId])['nombre']
                : 'Reconocimiento por clasificar';
            foreach (preg_split('/\s*,\s*/', trim((string) ($r['archivo_url'] ?? ''))) as $url) {
                if (!preg_match('#^https://\S+$#', $url)) {
                    continue;
                }
                if (Db::uno('SELECT 1 FROM reconocimientos WHERE persona_id = ? AND archivo_url = ?', [$personaId, $url])) {
                    continue;
                }
                Db::ejecutar(
                    "INSERT INTO reconocimientos (persona_id, curso_id, nombre_curso, archivo_url, estatus)
                     VALUES (?, ?, ?, ?, 'pendiente')",
                    [$personaId, $cursoId, $nombre, $url]
                );
                $n++;
            }
        }
        return $n;
    }

    /**
     * Marca como válidos los cursos que Kai validó al aprobar. Si el curso tiene un
     * reconocimiento pendiente, ese se valida; si no (lo validó por otro medio), se
     * crea uno válido sin archivo. Así el historial de cursos queda en la base.
     */
    private function validarCursos(int $personaId, array $cursos, ?int $validadoPor): void
    {
        foreach ($cursos as $curso) {
            $cursoId = $this->cursoId($curso);
            if (!$cursoId) {
                throw new ErrorNegocio('Curso no reconocido: ' . $curso, 422);
            }
            if (Db::uno("SELECT 1 FROM reconocimientos WHERE persona_id = ? AND curso_id = ? AND estatus = 'valido'",
                        [$personaId, $cursoId])) {
                continue;
            }
            $n = Db::ejecutar(
                "UPDATE reconocimientos SET estatus = 'valido', validado_por = ?, validado_at = NOW()
                  WHERE persona_id = ? AND curso_id = ? AND estatus = 'pendiente'",
                [$validadoPor, $personaId, $cursoId]
            );
            if ($n === 0) {
                Db::ejecutar(
                    "INSERT INTO reconocimientos (persona_id, curso_id, nombre_curso, estatus, validado_por, validado_at, notas)
                     SELECT ?, id, nombre, 'valido', ?, NOW(), 'Validado al aprobar la afiliación' FROM cursos WHERE id = ?",
                    [$personaId, $validadoPor, $cursoId]
                );
            }
        }
    }

    /** Id del curso por su clave (REQ-CIENCIAS) o por su nombre ("Ciencias del deporte"). */
    private function cursoId(?string $curso): ?int
    {
        $curso = trim((string) $curso);
        if ($curso === '') {
            return null;
        }
        $clave = Catalogos::normalizar($curso);
        foreach (Db::todos('SELECT id, clave, nombre FROM cursos') as $c) {
            if (Catalogos::normalizar($c['clave']) === $clave || Catalogos::normalizar($c['nombre']) === $clave) {
                return (int) $c['id'];
            }
        }
        return null;
    }

    private function vetoActivo(int $personaId, ?string $curp): bool
    {
        $curp = $curp ?? (Db::uno('SELECT curp FROM personas WHERE id = ?', [$personaId])['curp'] ?? null);
        return (bool) Db::uno(
            'SELECT 1 FROM vetos WHERE activo = 1 AND (persona_id = ? OR (curp IS NOT NULL AND curp = ?)) LIMIT 1',
            [$personaId, $curp]
        );
    }

    /** Reconocimientos válidos de los cursos requisito de ese año. */
    private function cursosValidos(int $personaId, int $anio): int
    {
        $fila = Db::uno(
            "SELECT COUNT(DISTINCT r.curso_id) AS n
               FROM reconocimientos r
               JOIN requisitos_anuales q ON q.curso_id = r.curso_id AND q.anio = ?
              WHERE r.persona_id = ? AND r.estatus = 'valido'",
            [$anio, $personaId]
        );
        return (int) ($fila['n'] ?? 0);
    }

    /** Tipo y grado según los cursos (configuracion: afiliacion.tipos). */
    private function tipoPorCursos(int $cursos): array
    {
        $tipos = Ajustes::get('afiliacion.tipos', []);
        uasort($tipos, fn($x, $y) => $y['cursos_min'] <=> $x['cursos_min']);
        foreach ($tipos as $tipo => $t) {
            if ($cursos >= $t['cursos_min']) {
                return [$tipo, $t['grado']];
            }
        }
        throw new ErrorNegocio('La configuración afiliacion.tipos no cubre ' . $cursos . ' cursos', 500);
    }

    /** Vigencia según el tipo (configuracion: afiliacion.vigencias, formato "MM-DD"). */
    private function vigencia(int $anio, string $tipo): string
    {
        $mmdd = Ajustes::get('afiliacion.vigencias', [])[$tipo] ?? '12-31';
        return $anio . '-' . $mmdd;
    }

    private function nombresParecidos(string $a, string $b): bool
    {
        $pa = array_filter(explode(' ', $a));
        $pb = array_filter(explode(' ', $b));
        return count(array_intersect($pa, $pb)) >= min(2, count($pa), count($pb));
    }

    /**
     * Marca temporal del Form. Acepta ISO ("2027-01-03T10:15:00") o el formato
     * de Google Sheets en México, día/mes/año ("03/01/2027 10:15:00"), que
     * strtotime leería al revés como mes/día.
     */
    /** Liga https de la carta firmada, o null si no viene o no es válida. */
    private function urlCarta(array $d): ?string
    {
        $url = trim((string) ($d['carta_compromiso_url'] ?? ''));
        return preg_match('#^https://\S+$#', $url) ? $url : null;
    }

    private function fecha(?string $marca): string
    {
        $marca = trim((string) $marca);
        if (preg_match('#^(\d{1,2})/(\d{1,2})/(\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$#', $marca, $m)
            && checkdate((int) $m[2], (int) $m[1], (int) $m[3])) {
            return sprintf('%04d-%02d-%02d %02d:%02d:%02d', $m[3], $m[2], $m[1], $m[4] ?? 0, $m[5] ?? 0, $m[6] ?? 0);
        }
        $t = $marca !== '' ? strtotime($marca) : false;
        return date('Y-m-d H:i:s', $t ?: time());
    }
}

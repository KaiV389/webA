<?php
declare(strict_types=1);

namespace App\Servicios;

use App\Core\Bitacora;
use App\Core\Db;
use App\Core\ErrorNegocio;
use PDO;

/**
 * Migración de los afiliados de años anteriores (pestaña A2026 de la Sheet
 * de 2026) y de la pestaña Vetados. La manda un Apps Script desde esa Sheet,
 * en lotes; los datos nunca pasan por otro lado.
 *
 * Es idempotente: un folio que ya existe no se toca ni se duplica, así que
 * el script se puede correr las veces que haga falta.
 *
 * No genera documentos: los PDFs 2026 ya se entregaron y sus QR apuntan al
 * sistema anterior. Lo que importa es que la persona, su folio y sus cursos
 * validados existan para que pueda renovar en 2027.
 */
final class Migracion
{
    /** Llave del payload → clave del curso requisito. */
    private const CURSOS = [
        'ciencias'    => 'REQ-CIENCIAS',
        'metodologia' => 'REQ-METODOLOGIA',
        'pedagogia'   => 'REQ-PEDAGOGIA',
        'urgencias'   => 'REQ-URGENCIAS',
        'matematicas' => 'REQ-MATEMATICAS',
    ];

    private const MESES = ['enero' => 1, 'febrero' => 2, 'marzo' => 3, 'abril' => 4, 'mayo' => 5, 'junio' => 6,
        'julio' => 7, 'agosto' => 8, 'septiembre' => 9, 'octubre' => 10, 'noviembre' => 11, 'diciembre' => 12];

    /** @param array $registros lista de afiliados (máx. 50 por llamada) */
    public function afiliaciones(array $registros): array
    {
        if (count($registros) > 50) {
            throw new ErrorNegocio('Máximo 50 registros por llamada', 422);
        }
        $resultados = [];
        $maxPorAnio = [];
        foreach ($registros as $i => $r) {
            try {
                $res = Db::transaccion(fn(PDO $pdo) => $this->unaAfiliacion((array) $r));
                if (isset($res['anio'], $res['consecutivo'])) {
                    $maxPorAnio[$res['anio']] = max($maxPorAnio[$res['anio']] ?? 0, $res['consecutivo']);
                }
                $resultados[] = ['i' => $i, 'fila' => $r['fila'] ?? null] + $res;
            } catch (ErrorNegocio $e) {
                $resultados[] = ['i' => $i, 'fila' => $r['fila'] ?? null, 'resultado' => 'error', 'error' => $e->getMessage()];
            }
        }
        // Que los folios nuevos de esos años nunca choquen con los migrados
        foreach ($maxPorAnio as $anio => $max) {
            Db::ejecutar(
                "INSERT INTO folio_contadores (anio, serie, ambito, ultimo) VALUES (?, 'AFI', 'NAL', ?)
                 ON DUPLICATE KEY UPDATE ultimo = GREATEST(ultimo, VALUES(ultimo))",
                [$anio, $max]
            );
        }
        $cuenta = array_count_values(array_column($resultados, 'resultado'));
        return ['resumen' => $cuenta, 'resultados' => $resultados];
    }

    private function unaAfiliacion(array $r): array
    {
        $f = Folios::interpretar($r['folio'] ?? '');
        if (!$f || $f['anio'] === null) {
            throw new ErrorNegocio('Folio no reconocido: "' . ($r['folio'] ?? '') . '"');
        }
        $anio = $f['anio'];
        $folio = Folios::formatear($anio, 'AFI', $f['consecutivo']);

        $ya = Db::uno("SELECT id FROM afiliaciones WHERE anio = ? AND serie = 'AFI' AND consecutivo = ?",
                      [$anio, $f['consecutivo']]);
        if ($ya) {
            return ['resultado' => 'ya_existe', 'folio' => $folio, 'afiliacion_id' => (int) $ya['id']];
        }

        $nombre = Catalogos::nombrePropio($r['nombre'] ?? '');
        if ($nombre === '') {
            throw new ErrorNegocio('Sin nombre (' . $folio . ')');
        }
        $curp = strtoupper(preg_replace('/\s+/', '', (string) ($r['curp'] ?? '')));
        $curp = Catalogos::curpValida($curp) ? $curp : null;
        $escuela = (array) ($r['escuela'] ?? []);
        $estadoId = Catalogos::estadoId($escuela['estado'] ?? null, $curp);

        $personaId = $this->persona($nombre, $curp, $r, $estadoId);

        $otra = Db::uno('SELECT folio FROM afiliaciones WHERE persona_id = ? AND anio = ?', [$personaId, $anio]);
        if ($otra) {
            throw new ErrorNegocio('La misma persona ya tiene el folio ' . $otra['folio'] . ' en ' . $anio
                . ' (¿fila duplicada?). No se migró ' . $folio);
        }

        $escuelaId = trim((string) ($escuela['nombre'] ?? '')) !== '' ? $this->escuela($escuela, $estadoId) : null;

        // Cursos validados en la hoja → reconocimientos válidos (permanentes)
        $validos = 0;
        foreach (self::CURSOS as $llave => $clave) {
            if (!$this->esUno($r['cursos'][$llave] ?? null)) {
                continue;
            }
            $validos++;
            $curso = Db::uno('SELECT id, nombre FROM cursos WHERE clave = ?', [$clave]);
            if (!$curso) {
                continue;
            }
            $existe = Db::uno("SELECT 1 FROM reconocimientos WHERE persona_id = ? AND curso_id = ? AND estatus = 'valido'",
                              [$personaId, $curso['id']]);
            if (!$existe) {
                Db::ejecutar(
                    "INSERT INTO reconocimientos (persona_id, curso_id, nombre_curso, estatus, validado_at, notas)
                     VALUES (?, ?, ?, 'valido', NOW(), ?)",
                    [$personaId, $curso['id'], $curso['nombre'], 'Validado en ' . $anio . ' (migración)']
                );
            }
        }

        [$tipo, $grado] = $this->tipo($r['tipo'] ?? null, $validos);
        $vigencia = $this->vigencia($r['vigencia'] ?? null, $anio, $tipo);
        $estatus = $vigencia >= date('Y-m-d') ? 'activa' : 'vencida';
        $registro = $this->fecha($r['fecha_registro'] ?? null, $anio);

        Db::ejecutar(
            "INSERT INTO afiliaciones (persona_id, anio, serie, consecutivo, folio, escuela_id, tipo_credencial, grado,
                                       cursos_validos, vigencia, estatus, origen, fecha_registro, aprobada_at, datos_form)
             VALUES (?, ?, 'AFI', ?, ?, ?, ?, ?, ?, ?, ?, 'migracion', ?, ?, ?)",
            [$personaId, $anio, $f['consecutivo'], $folio, $escuelaId, $tipo, $grado, $validos, $vigencia, $estatus,
             $registro, $registro, json_encode(['hoja' => $r['hoja'] ?? null, 'fila' => $r['fila'] ?? null])]
        );
        $id = (int) Db::pdo()->lastInsertId();

        Db::ejecutar('UPDATE personas SET fecha_primera_afiliacion = LEAST(COALESCE(fecha_primera_afiliacion, ?), ?) WHERE id = ?',
                     [substr($registro, 0, 10), substr($registro, 0, 10), $personaId]);
        Bitacora::registrar('migrar', 'afiliacion', $id, null, ['folio' => $folio]);

        return ['resultado' => 'migrada', 'folio' => $folio, 'afiliacion_id' => $id, 'estatus' => $estatus,
                'sin_curp' => $curp === null, 'anio' => $anio, 'consecutivo' => $f['consecutivo']];
    }

    /** Vetados: se agregan los que no estén ya (por CURP o por nombre). */
    public function vetos(array $registros): array
    {
        $agregados = 0; $existentes = 0;
        foreach ($registros as $v) {
            $nombre = trim((string) ($v['nombre'] ?? ''));
            $curp = strtoupper(preg_replace('/\s+/', '', (string) ($v['curp'] ?? '')));
            $curp = Catalogos::curpValida($curp) ? $curp : null;
            if ($nombre === '' && $curp === null) {
                continue;
            }
            $ya = $curp
                ? Db::uno('SELECT id FROM vetos WHERE curp = ?', [$curp])
                : null;
            if (!$ya && $nombre !== '') {
                foreach (Db::todos('SELECT id, nombre FROM vetos WHERE nombre IS NOT NULL') as $fila) {
                    if (Catalogos::normalizar($fila['nombre']) === Catalogos::normalizar($nombre)) { $ya = $fila; break; }
                }
            }
            if ($ya) { $existentes++; continue; }

            $persona = $curp ? Db::uno('SELECT id FROM personas WHERE curp = ?', [$curp]) : null;
            Db::ejecutar(
                'INSERT INTO vetos (persona_id, curp, nombre, escuela_texto, motivo, activo) VALUES (?, ?, ?, ?, ?, ?)',
                [$persona['id'] ?? null, $curp, $nombre ?: null, trim((string) ($v['escuela'] ?? '')) ?: null,
                 trim((string) ($v['motivo'] ?? '')) ?: 'Migrado de la pestaña Vetados 2026',
                 $this->esUno($v['activo'] ?? 'SI') ? 1 : 0]
            );
            $agregados++;
        }
        return ['agregados' => $agregados, 'ya_estaban' => $existentes];
    }

    // ------------------------------------------------------------------

    private function persona(string $nombre, ?string $curp, array $r, ?int $estadoId): int
    {
        $tel = preg_replace('/\D/', '', (string) ($r['telefono'] ?? ''));
        $tel = strlen($tel) >= 10 ? substr($tel, -10) : null;
        $correo = strtolower(trim((string) ($r['correo'] ?? '')));
        $correo = filter_var($correo, FILTER_VALIDATE_EMAIL) ? $correo : null;
        $foto = $this->url($r['foto_url'] ?? null);
        $municipio = trim((string) ($r['escuela']['municipio'] ?? '')) ?: null;

        $p = $curp ? Db::uno('SELECT id FROM personas WHERE curp = ?', [$curp]) : null;
        if (!$p && $curp === null) {
            // Sin CURP: se une con alguien del mismo nombre que tampoco tenga CURP
            foreach (Db::todos('SELECT id, nombre_completo FROM personas WHERE curp IS NULL') as $fila) {
                if (Catalogos::normalizar($fila['nombre_completo']) === Catalogos::normalizar($nombre)) { $p = $fila; break; }
            }
        }
        if ($p) {
            Db::ejecutar(
                'UPDATE personas SET correo = COALESCE(correo, ?), telefono = COALESCE(telefono, ?),
                        foto_url = COALESCE(foto_url, ?), estado_id = COALESCE(estado_id, ?),
                        municipio = COALESCE(municipio, ?) WHERE id = ?',
                [$correo, $tel, $foto, $estadoId, $municipio, $p['id']]
            );
            return (int) $p['id'];
        }
        $dc = $curp ? Catalogos::datosCurp($curp) : ['fecha_nacimiento' => null, 'sexo' => null];
        Db::ejecutar(
            'INSERT INTO personas (nombre_completo, curp, correo, telefono, fecha_nacimiento, sexo, estado_id, municipio, foto_url)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [$nombre, $curp, $correo, $tel, $dc['fecha_nacimiento'], $dc['sexo'], $estadoId, $municipio, $foto]
        );
        return (int) Db::pdo()->lastInsertId();
    }

    private function escuela(array $e, ?int $estadoId): int
    {
        $nombre = trim((string) $e['nombre']);
        $clave = Catalogos::normalizar($nombre);
        foreach (Db::todos('SELECT id, nombre FROM escuelas WHERE estado_id <=> ?', [$estadoId]) as $fila) {
            if (Catalogos::normalizar($fila['nombre']) === $clave) {
                Db::ejecutar('UPDATE escuelas SET logo_url = COALESCE(logo_url, ?) WHERE id = ?',
                             [$this->url($e['logo_url'] ?? null), $fila['id']]);
                return (int) $fila['id'];
            }
        }
        Db::ejecutar('INSERT INTO escuelas (nombre, logo_url, municipio, estado_id) VALUES (?, ?, ?, ?)',
                     [$nombre, $this->url($e['logo_url'] ?? null), trim((string) ($e['municipio'] ?? '')) ?: null, $estadoId]);
        return (int) Db::pdo()->lastInsertId();
    }

    /** "Tipo A" / "A" de la hoja; si no viene, por número de cursos (regla 2026). */
    private function tipo(?string $texto, int $cursos): array
    {
        $t = strtoupper(trim(str_ireplace('tipo', '', (string) $texto)));
        if (!in_array($t, ['A', 'B', 'C'], true)) {
            $t = $cursos === 5 ? 'A' : ($cursos > 3 ? 'B' : 'C');
        }
        return [$t, ['A' => 'Entrenador Master', 'B' => 'Entrenador', 'C' => 'Instructor'][$t]];
    }

    /** "Diciembre 2026", "Junio 2026", "2026-12-31" o "31/12/2026". */
    private function vigencia(mixed $v, int $anio, string $tipo): string
    {
        $s = Catalogos::normalizar((string) $v);
        if (preg_match('/(\d{4})-(\d{2})-(\d{2})/', (string) $v, $m)) {
            return "$m[1]-$m[2]-$m[3]";
        }
        if (preg_match('#(\d{1,2})/(\d{1,2})/(\d{4})#', (string) $v, $m)) {
            return sprintf('%04d-%02d-%02d', $m[3], $m[2], $m[1]);
        }
        foreach (self::MESES as $mes => $n) {
            if (str_contains($s, $mes)) {
                $y = preg_match('/(20\d\d)/', $s, $m) ? (int) $m[1] : $anio;
                return date('Y-m-t', mktime(0, 0, 0, $n, 1, $y));
            }
        }
        return $tipo === 'A' ? "$anio-12-31" : "$anio-06-30";
    }

    private function fecha(mixed $v, int $anio): string
    {
        $s = (string) $v;
        if (preg_match('/(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}))?/', $s, $m)) {
            return sprintf('%s-%s-%s %s:%s:00', $m[1], $m[2], $m[3], $m[4] ?? '00', $m[5] ?? '00');
        }
        if (preg_match('#(\d{1,2})/(\d{1,2})/(\d{4})#', $s, $m)) {
            return sprintf('%04d-%02d-%02d 00:00:00', $m[3], $m[2], $m[1]);
        }
        return "$anio-01-01 00:00:00";
    }

    private function url(mixed $u): ?string
    {
        $u = trim(explode(',', (string) $u)[0]);
        return preg_match('#^https://#', $u) ? $u : null;
    }

    private function esUno(mixed $v): bool
    {
        if (is_bool($v)) return $v;
        $s = strtoupper(trim((string) $v));
        return in_array($s, ['1', 'SI', 'SÍ', 'TRUE', 'OK', 'X', 'VERDADERO'], true) || (is_numeric($s) && (float) $s >= 1);
    }
}

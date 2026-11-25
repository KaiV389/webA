<?php
declare(strict_types=1);

namespace App\Controladores;

use App\Core\Db;
use App\Core\Http;

/**
 * GET /verificar/{token}
 *
 * Es la dirección PERMANENTE que llevan los QR de credenciales,
 * constancias, avales y nombramientos. No cambia nunca.
 *
 * Muestra solo lo necesario para comprobar el documento: tipo, folio,
 * nombre, fecha y estado. Nunca muestra CURP, teléfono ni correo.
 */
final class VerificarController
{
    private const NOMBRES_TIPO = [
        'afiliacion'            => 'Afiliación',
        'constancia_afiliacion' => 'Constancia de afiliación',
        'credencial'            => 'Credencial',
        'nombramiento'          => 'Nombramiento',
        'aval'                  => 'Aval de evento',
        'gestion'               => 'Oficio de gestión',
        'trayectoria'           => 'Constancia de trayectoria',
    ];

    private const NIVELES_AVAL = [
        1 => 'Nivel 1 · Local o sparring',
        2 => 'Nivel 2 · Estatal',
        3 => 'Nivel 3 · Nacional',
        4 => 'Nivel 4 · Oficial AMBA',
    ];

    public function mostrar(string $token): never
    {
        // Los códigos son 32 caracteres hexadecimales; cualquier otra cosa
        // ni siquiera llega a la base de datos.
        if (!preg_match('/^[a-f0-9]{32}$/i', $token)) {
            $this->noEncontrado();
        }
        $token = strtolower($token);

        $doc = Db::uno(
            "SELECT d.tipo, d.folio, d.nivel, d.anulado, d.generado_at, d.persona_id,
                    p.nombre_completo,
                    a.vigencia, a.estatus AS estatus_afiliacion, a.anio,
                    ev.titulo AS evento, ev.inicio AS evento_fecha,
                    aut.nombre_completo AS autorizado_por
             FROM documentos d
             LEFT JOIN personas p     ON p.id = d.persona_id
             LEFT JOIN afiliaciones a ON a.id = d.afiliacion_id
             LEFT JOIN eventos ev     ON ev.id = d.evento_id
             LEFT JOIN personas aut   ON aut.id = d.autorizado_por
             WHERE d.verificacion_token = ?
             ORDER BY d.version DESC
             LIMIT 1",
            [$token]
        );

        if ($doc) {
            Http::vista('verificar', [
                'clase'       => 'documento',
                'tipo'        => self::NOMBRES_TIPO[$doc['tipo']] ?? 'Documento',
                'folio'       => $doc['folio'],
                'nombre'      => $doc['nombre_completo'],
                'etiquetaNombre' => in_array($doc['tipo'], ['aval', 'gestion'], true) ? 'Profesor a cargo' : 'Nombre',
                'fecha'       => $doc['generado_at'],
                'valido'      => !$doc['anulado'],
                'nivel'       => $doc['nivel'] ? (self::NIVELES_AVAL[(int) $doc['nivel']] ?? null) : null,
                'evento'      => $doc['evento'],
                'eventoFecha' => $doc['evento_fecha'],
                'autorizadoPor' => $doc['autorizado_por'],
                'vigencia'    => $doc['vigencia'],
                'afiliacion'  => $doc['persona_id'] ? $this->estadoAfiliacion((int) $doc['persona_id']) : null,
            ]);
        }

        $const = Db::uno(
            "SELECT c.folio, c.nombre_impreso, c.emitida_at, c.persona_id,
                    cu.nombre AS curso, cv.version
             FROM constancias c
             JOIN curso_versiones cv ON cv.id = c.curso_version_id
             JOIN cursos cu          ON cu.id = cv.curso_id
             WHERE c.verificacion_token = ?
             LIMIT 1",
            [$token]
        );

        if ($const) {
            Http::vista('verificar', [
                'clase'      => 'constancia',
                'tipo'       => 'Constancia de curso',
                'folio'      => $const['folio'],
                'nombre'     => $const['nombre_impreso'],
                'fecha'      => $const['emitida_at'],
                'valido'     => true,   // las constancias no se anulan
                'curso'      => $const['curso'],
                'afiliacion' => $this->estadoAfiliacion((int) $const['persona_id']),
            ]);
        }

        $this->noEncontrado();
    }

    /**
     * Estado de afiliación HOY de una persona, según su afiliación más reciente.
     * Devuelve ['activa' => bool, 'texto' => string].
     */
    private function estadoAfiliacion(int $personaId): array
    {
        $a = Db::uno(
            "SELECT folio, estatus, vigencia
             FROM afiliaciones
             WHERE persona_id = ? AND estatus NOT IN ('pendiente','rechazada','duplicada')
             ORDER BY anio DESC
             LIMIT 1",
            [$personaId]
        );
        $activa = $a && $a['estatus'] === 'activa' && $a['vigencia'] && $a['vigencia'] >= date('Y-m-d');
        return [
            'activa' => $activa,
            'texto'  => $activa
                ? 'Afiliado activo · Folio ' . $a['folio'] . ' · Vigente hasta ' . fecha_larga($a['vigencia'])
                : 'NO AFILIADO actualmente',
        ];
    }

    private function noEncontrado(): never
    {
        Http::vista('verificar', ['clase' => 'no_encontrado'], 404);
    }
}

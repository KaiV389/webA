<?php
declare(strict_types=1);

namespace App\Servicios;

use App\Core\Ajustes;
use PDO;

/**
 * Folios con protocolo fijo: AMBA-27NAL-AFI001
 * Cada año cambian el año y el consecutivo; series y formato se quedan.
 */
final class Folios
{
    /** Serie de cada documento de afiliación: comparten número con el folio maestro AFI. */
    public const SERIES_DOCUMENTO = [
        'afiliacion'            => 'AFL',
        'constancia_afiliacion' => 'CON',
        'credencial'            => 'CRE',
    ];

    /**
     * Siguiente consecutivo de (año, serie, ámbito).
     * DEBE llamarse dentro de una transacción: el renglón del contador queda
     * bloqueado hasta el COMMIT, así dos registros simultáneos nunca
     * reciben el mismo número ni se salta ninguno si algo falla.
     */
    public static function siguiente(PDO $pdo, int $anio, string $serie, string $ambito = 'NAL'): int
    {
        $st = $pdo->prepare(
            'INSERT INTO folio_contadores (anio, serie, ambito, ultimo) VALUES (?, ?, ?, LAST_INSERT_ID(1))
             ON DUPLICATE KEY UPDATE ultimo = LAST_INSERT_ID(ultimo + 1)'
        );
        $st->execute([$anio, $serie, $ambito]);
        return (int) $pdo->query('SELECT LAST_INSERT_ID()')->fetchColumn();
    }

    /** Arma el folio con el formato de la configuración (folio.formato). */
    public static function formatear(int $anio, string $serie, int $numero, string $ambito = 'NAL'): string
    {
        $formato = Ajustes::get('folio.formato', 'AMBA-{AA}{AMBITO}-{SERIE}{NUM3}');
        return strtr($formato, [
            '{AA}'     => substr((string) $anio, -2),
            '{AMBITO}' => $ambito,
            '{SERIE}'  => $serie,
            '{NUM3}'   => str_pad((string) $numero, 3, '0', STR_PAD_LEFT),
        ]);
    }

    /**
     * Interpreta un folio capturado a mano, tolerando los errores reales
     * que cometen los profesores:
     *   - I, L o 1 confundidos, O o 0 confundidos ("AF1001", "AFL049")
     *   - sin el cero de relleno ("AFL49")
     *   - el folio de la constancia o la credencial en lugar del maestro (CON, CRE, CRED, AFL)
     *   - sin guiones, con espacios, en minúsculas, sin "AMBA"
     * Devuelve ['anio' => 2026|null, 'consecutivo' => 49] o null si no se reconoce.
     */
    public static function interpretar(?string $texto): ?array
    {
        $t = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', (string) $texto));
        // "AMBA" opcional (con 0 en lugar de O no aplica, pero sí con espacios ya quitados)
        $t = preg_replace('/^AMBA/', '', $t);
        // Año opcional: muchos escriben solo la cola ("AFL49"); entonces anio = null
        // y quien llama decide (en renovaciones, el año anterior al de la campaña).
        if (!preg_match('/^(?:(\d{2})(?:NAL|NA1|N4L)?)?([A-Z].*)$/', $t, $m)) {
            return null;
        }
        $anio = $m[1] !== '' ? 2000 + (int) $m[1] : null;
        $resto = $m[2];

        $letra = fn(string $c) => match ($c) {
            'I', 'L' => '[IL1]',
            'O'      => '[O0]',
            default  => $c,
        };
        foreach (['CRED', 'AFI', 'AFL', 'CON', 'CRE'] as $serie) {
            $patron = implode('', array_map($letra, str_split($serie)));
            if (preg_match('/^' . $patron . '(\d{1,5})$/', $resto, $n)) {
                return ['anio' => $anio, 'consecutivo' => (int) $n[1]];
            }
        }
        return null;
    }
}

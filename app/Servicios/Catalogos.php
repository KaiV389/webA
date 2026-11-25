<?php
declare(strict_types=1);

namespace App\Servicios;

use App\Core\Db;

/** Normalización de textos, CURP y estados. */
final class Catalogos
{
    /** Mayúsculas, sin acentos y sin espacios repetidos: "Edo. de México " → "EDO. DE MEXICO" */
    public static function normalizar(?string $texto): string
    {
        $t = mb_strtoupper(trim((string) $texto), 'UTF-8');
        $t = strtr($t, ['Á' => 'A', 'É' => 'E', 'Í' => 'I', 'Ó' => 'O', 'Ú' => 'U', 'Ü' => 'U', 'Ñ' => 'N']);
        return preg_replace('/\s+/', ' ', $t);
    }

    /** Nombre propio limpio: "  juan  PÉREZ " → "Juan Pérez" */
    public static function nombrePropio(?string $texto): string
    {
        $t = preg_replace('/\s+/', ' ', trim((string) $texto));
        return mb_convert_case(mb_strtolower($t, 'UTF-8'), MB_CASE_TITLE, 'UTF-8');
    }

    public static function curpValida(?string $curp): bool
    {
        return (bool) preg_match('/^[A-Z][AEIOUX][A-Z]{2}\d{6}[HMX][A-Z]{2}[B-DF-HJ-NP-TV-Z]{3}[A-Z\d]\d$/', (string) $curp);
    }

    /** Fecha de nacimiento y sexo que trae la CURP. */
    public static function datosCurp(string $curp): array
    {
        $yy = (int) substr($curp, 4, 2);
        $siglo = ctype_digit($curp[16]) ? 1900 : 2000;   // el carácter 17 distingue el siglo
        $fecha = sprintf('%04d-%s-%s', $siglo + $yy, substr($curp, 6, 2), substr($curp, 8, 2));
        $sexo = $curp[10] === 'H' ? 'H' : ($curp[10] === 'M' ? 'M' : null);
        return [
            'fecha_nacimiento' => checkdate((int) substr($fecha, 5, 2), (int) substr($fecha, 8, 2), (int) substr($fecha, 0, 4)) ? $fecha : null,
            'sexo'             => $sexo,
            'clave_estado'     => substr($curp, 11, 2),
        ];
    }

    private const VARIANTES_ESTADO = [
        'EDO MEX' => 15, 'EDOMEX' => 15, 'EDO. MEX' => 15, 'EDO. MEX.' => 15, 'EDO DE MEX' => 15,
        'EDO. DE MEXICO' => 15, 'EDO DE MEXICO' => 15, 'ESTADO DE MEXICO' => 15, 'MEXICO' => 15, 'MEX' => 15,
        'CDMX' => 9, 'CD MX' => 9, 'CD. DE MEXICO' => 9, 'CIUDAD DE MEXICO' => 9, 'DF' => 9, 'D.F.' => 9,
        'DISTRITO FEDERAL' => 9,
    ];

    /** Id del estado a partir del texto capturado; si no se reconoce, de la CURP. */
    public static function estadoId(?string $texto, ?string $curp = null): ?int
    {
        $t = self::normalizar($texto);
        if ($t !== '') {
            if (isset(self::VARIANTES_ESTADO[$t])) {
                return self::VARIANTES_ESTADO[$t];
            }
            foreach (Db::todos('SELECT id, nombre FROM estados') as $e) {
                if (self::normalizar($e['nombre']) === $t) {
                    return (int) $e['id'];
                }
            }
        }
        if ($curp && self::curpValida($curp)) {
            $fila = Db::uno('SELECT id FROM estados WHERE clave = ?', [self::datosCurp($curp)['clave_estado']]);
            return $fila ? (int) $fila['id'] : null;
        }
        return null;
    }
}

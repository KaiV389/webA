<?php
declare(strict_types=1);

namespace App\Core;

/**
 * Configuración que vive en la tabla `configuracion` (se cambia sin tocar
 * código: año en curso, plazos, tipos de credencial, vigencias…).
 * Se lee una sola vez por solicitud.
 */
final class Ajustes
{
    private static ?array $cache = null;

    public static function get(string $clave, mixed $porDefecto = null): mixed
    {
        if (self::$cache === null) {
            self::$cache = [];
            foreach (Db::todos('SELECT clave, valor FROM configuracion') as $fila) {
                self::$cache[$fila['clave']] = json_decode($fila['valor'], true);
            }
        }
        return self::$cache[$clave] ?? $porDefecto;
    }

    /** Año de afiliación en curso (configuracion: afiliacion.anio_actual). */
    public static function anioActual(): int
    {
        return (int) self::get('afiliacion.anio_actual', (int) date('Y'));
    }
}

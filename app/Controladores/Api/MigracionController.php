<?php
declare(strict_types=1);

namespace App\Controladores\Api;

use App\Core\ApiAuth;
use App\Core\ErrorNegocio;
use App\Core\Http;
use App\Servicios\Migracion;

/**
 * Migración de años anteriores desde la Sheet de 2026 (Apps Script).
 *   POST /api/migracion/afiliaciones   {registros: [...]}  (máx. 50 por llamada)
 *   POST /api/migracion/vetos          {registros: [...]}
 * Idempotente: se puede correr varias veces sin duplicar nada.
 */
final class MigracionController
{
    public function afiliaciones(): never
    {
        ApiAuth::requerir('afiliaciones.aprobar');
        $d = Http::cuerpoJson();
        if (!isset($d['registros']) || !is_array($d['registros'])) {
            throw new ErrorNegocio('Falta registros[]', 422);
        }
        Http::json(['ok' => true] + (new Migracion())->afiliaciones($d['registros']));
    }

    public function vetos(): never
    {
        ApiAuth::requerir('afiliaciones.aprobar');
        $d = Http::cuerpoJson();
        if (!isset($d['registros']) || !is_array($d['registros'])) {
            throw new ErrorNegocio('Falta registros[]', 422);
        }
        Http::json(['ok' => true] + (new Migracion())->vetos($d['registros']));
    }
}

<?php
declare(strict_types=1);

namespace App\Controladores;

use App\Core\Db;
use App\Core\Http;

/**
 * GET /api/salud
 * Lo consulta el monitor de disponibilidad cada pocos minutos.
 * Responde 200 si la base de datos contesta, 503 si no.
 */
final class SaludController
{
    public function revisar(): never
    {
        $inicio = microtime(true);
        try {
            Db::uno('SELECT 1 AS ok');
            $db = true;
        } catch (\Throwable $e) {
            error_log('Salud: la base de datos no responde: ' . $e->getMessage());
            $db = false;
        }
        Http::json([
            'ok'          => $db,
            'base_datos'  => $db,
            'php'         => PHP_VERSION,
            'ms'          => (int) round((microtime(true) - $inicio) * 1000),
            'hora'        => date('c'),
        ], $db ? 200 : 503);
    }
}

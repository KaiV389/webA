<?php
/**
 * Todas las rutas del sitio en un solo lugar.
 */
declare(strict_types=1);

use App\Controladores\Api\AfiliacionesController;
use App\Controladores\Api\MigracionController;
use App\Controladores\SaludController;
use App\Controladores\VerificarController;
use App\Core\Http;

/** @var App\Core\Router $r */

// Páginas
$r->get('/', fn() => Http::vista('inicio'));

// Verificación por QR: dirección PERMANENTE, no se cambia nunca.
$r->get('/verificar/{token}', [VerificarController::class, 'mostrar']);

// API
$r->get('/api/salud', [SaludController::class, 'revisar']);

$r->post('/api/afiliaciones',               [AfiliacionesController::class, 'registrar']);
$r->get('/api/afiliaciones/pendientes',     [AfiliacionesController::class, 'pendientes']);
$r->post('/api/afiliaciones/{id}/aprobar',  [AfiliacionesController::class, 'aprobar']);
$r->post('/api/afiliaciones/{id}/carta',    [AfiliacionesController::class, 'adjuntarCarta']);
$r->post('/api/renovaciones',               [AfiliacionesController::class, 'renovar']);
$r->post('/api/documentos/{token}/pdf',     [AfiliacionesController::class, 'guardarPdf']);

// Migración de años anteriores (Sheet 2026 → base nueva)
$r->post('/api/migracion/afiliaciones',     [MigracionController::class, 'afiliaciones']);
$r->post('/api/migracion/vetos',            [MigracionController::class, 'vetos']);

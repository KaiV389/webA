<?php
/**
 * Todas las rutas del sitio en un solo lugar.
 */
declare(strict_types=1);

use App\Controladores\Api\AfiliacionesController;
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
$r->post('/api/renovaciones',               [AfiliacionesController::class, 'renovar']);
$r->post('/api/documentos/{token}/pdf',     [AfiliacionesController::class, 'guardarPdf']);

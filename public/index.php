<?php
/**
 * Punto de entrada único: TODAS las solicitudes pasan por aquí
 * (lo indica public/.htaccess). Lo demás vive fuera de public/
 * y no se puede abrir desde el navegador.
 */
declare(strict_types=1);

// Servidor de pruebas local (php -S): deja pasar los archivos reales (css, imágenes).
if (PHP_SAPI === 'cli-server' && is_file(__DIR__ . parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH))) {
    return false;
}

require dirname(__DIR__) . '/app/bootstrap.php';

App\Core\Http::encabezadosSeguridad();

$r = new App\Core\Router();
require RAIZ . '/app/Rutas.php';
$r->despachar($_SERVER['REQUEST_METHOD'] ?? 'GET', App\Core\Http::ruta());

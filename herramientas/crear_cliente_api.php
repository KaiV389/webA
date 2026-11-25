<?php
/**
 * Crea un cliente de la API y muestra su token UNA sola vez.
 * En la base solo queda el hash; si se pierde el token, se crea otro.
 *
 * Uso (en el servidor o en tu compu, con config/config.php apuntando a la base):
 *   php herramientas/crear_cliente_api.php "Apps Script afiliaciones" afiliaciones.registrar afiliaciones.aprobar afiliaciones.renovar documentos.registrar
 *
 * Permisos disponibles:
 *   afiliaciones.registrar   POST /api/afiliaciones
 *   afiliaciones.aprobar     GET pendientes, POST aprobar
 *   afiliaciones.renovar     POST /api/renovaciones
 *   documentos.registrar     POST /api/documentos/{token}/pdf
 */
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}
if ($argc < 3) {
    fwrite(STDERR, "Uso: php herramientas/crear_cliente_api.php \"Nombre\" permiso1 [permiso2 ...]\n");
    exit(1);
}

require dirname(__DIR__) . '/app/bootstrap.php';

$nombre = $argv[1];
$permisos = array_slice($argv, 2);
$token = bin2hex(random_bytes(32));   // 64 caracteres

App\Core\Db::ejecutar(
    'INSERT INTO api_clientes (nombre, token_hash, permisos) VALUES (?, ?, ?)',
    [$nombre, hash('sha256', $token), json_encode($permisos)]
);

echo "Cliente creado: {$nombre}\n";
echo "Permisos: " . implode(', ', $permisos) . "\n\n";
echo "TOKEN (cópialo ahora; no se vuelve a mostrar):\n{$token}\n\n";
echo "En Apps Script guárdalo en Propiedades del script, nunca en el código.\n";

<?php
/**
 * Arranque común: carga la configuración, el autoload de clases y el
 * manejo de errores. Lo incluye public/index.php en cada solicitud.
 */
declare(strict_types=1);

define('RAIZ', dirname(__DIR__));

require RAIZ . '/app/helpers.php';

// Autoload: la clase App\Core\Db vive en app/Core/Db.php
spl_autoload_register(function (string $clase): void {
    if (strncmp($clase, 'App\\', 4) !== 0) {
        return;
    }
    $ruta = RAIZ . '/app/' . str_replace('\\', '/', substr($clase, 4)) . '.php';
    if (is_file($ruta)) {
        require $ruta;
    }
});

$archivoConfig = RAIZ . '/config/config.php';
if (!is_file($archivoConfig)) {
    http_response_code(500);
    exit('Falta config/config.php (copia config.example.php y llénalo).');
}
App\Core\Config::cargar(require $archivoConfig);

date_default_timezone_set(App\Core\Config::get('zona_horaria', 'America/Mexico_City'));

// Errores: en producción nunca se muestran al público; van al log.
$enDesarrollo = App\Core\Config::get('entorno') === 'desarrollo';
error_reporting(E_ALL);
ini_set('display_errors', $enDesarrollo ? '1' : '0');
ini_set('log_errors', '1');
ini_set('error_log', RAIZ . '/storage/logs/php-' . date('Y-m') . '.log');

set_exception_handler(function (Throwable $e) use ($enDesarrollo): void {
    error_log((string) $e);
    App\Core\Http::error(500, $enDesarrollo ? $e->getMessage() : 'Ocurrió un error. Intenta de nuevo en un momento.');
});

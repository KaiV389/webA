<?php
declare(strict_types=1);

namespace App\Core;

/** Respuestas: JSON para la API, HTML para páginas. */
final class Http
{
    public static function esApi(): bool
    {
        return str_starts_with(self::ruta(), '/api/');
    }

    /** Ruta solicitada sin la cadena de consulta, sin diagonal final. */
    public static function ruta(): string
    {
        $ruta = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
        $ruta = '/' . trim($ruta, '/');
        return $ruta;
    }

    /**
     * Cuerpo JSON de la solicitud como arreglo. Si no es JSON válido
     * responde 400 de inmediato.
     */
    public static function cuerpoJson(): array
    {
        $crudo = file_get_contents('php://input') ?: '';
        if (strlen($crudo) > 1_000_000) {
            self::error(413, 'La solicitud es demasiado grande');
        }
        $datos = json_decode($crudo, true);
        if (!is_array($datos)) {
            self::error(400, 'El cuerpo debe ser JSON válido');
        }
        return $datos;
    }

    /** Lee un encabezado HTTP sin importar mayúsculas. */
    public static function encabezado(string $nombre): ?string
    {
        $clave = 'HTTP_' . strtoupper(str_replace('-', '_', $nombre));
        if (isset($_SERVER[$clave])) {
            return $_SERVER[$clave];
        }
        // Algunos hostings con PHP como CGI dejan Authorization aquí
        if (strcasecmp($nombre, 'Authorization') === 0) {
            return $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? null;
        }
        return null;
    }

    public static function json(mixed $datos, int $codigo = 200): never
    {
        http_response_code($codigo);
        header('Content-Type: application/json; charset=utf-8');
        header('Cache-Control: no-store');
        echo json_encode($datos, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }

    /** Muestra una vista de app/Vistas con las variables dadas. */
    public static function vista(string $__vista, array $vars = [], int $codigo = 200): never
    {
        http_response_code($codigo);
        header('Content-Type: text/html; charset=utf-8');
        // Variables internas con prefijo __ para que nunca choquen con los datos de la vista
        extract($vars, EXTR_SKIP);
        require RAIZ . '/app/Vistas/' . $__vista . '.php';
        exit;
    }

    public static function error(int $codigo, string $mensaje): never
    {
        if (self::esApi()) {
            self::json(['ok' => false, 'error' => $mensaje], $codigo);
        }
        self::vista('error', ['codigo' => $codigo, 'mensaje' => $mensaje], $codigo);
    }

    public static function redirigir(string $url, int $codigo = 301): never
    {
        header('Location: ' . $url, true, $codigo);
        exit;
    }

    /** Encabezados de seguridad para todas las respuestas. */
    public static function encabezadosSeguridad(): void
    {
        header('X-Content-Type-Options: nosniff');
        header('X-Frame-Options: SAMEORIGIN');
        header('Referrer-Policy: strict-origin-when-cross-origin');
        header_remove('X-Powered-By');
    }
}


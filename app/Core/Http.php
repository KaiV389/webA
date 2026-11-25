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


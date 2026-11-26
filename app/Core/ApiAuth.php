<?php
declare(strict_types=1);

namespace App\Core;

/**
 * Autenticación de clientes de la API (Apps Script, servicio de PDFs,
 * futura app). Cada cliente tiene un token largo; en la base solo se
 * guarda su hash SHA-256 y la lista de permisos que tiene.
 *
 * Encabezado esperado:  Authorization: Bearer <token>
 * Alternativo:          X-AMBA-Token: <token>
 * (algunos hostings, como IONOS, no le pasan Authorization a PHP).
 */
final class ApiAuth
{
    private static ?array $cliente = null;

    /** Exige un cliente válido con el permiso indicado; si no, responde 401/403. */
    public static function requerir(string $permiso): array
    {
        $token = null;
        $enc = trim(Http::encabezado('Authorization') ?? '');
        if (preg_match('/^Bearer\s+([A-Za-z0-9_\-]{32,128})$/', $enc, $m)) {
            $token = $m[1];
        } else {
            $alt = trim(Http::encabezado('X-AMBA-Token') ?? '');
            if (preg_match('/^[A-Za-z0-9_\-]{32,128}$/', $alt)) {
                $token = $alt;
            }
        }
        if ($token === null) {
            Http::error(401, 'Falta el token de acceso');
        }
        $cliente = Db::uno(
            'SELECT id, nombre, permisos FROM api_clientes WHERE token_hash = ? AND activo = 1',
            [hash('sha256', $token)]
        );
        if (!$cliente) {
            Http::error(401, 'Token no válido');
        }
        $permisos = json_decode($cliente['permisos'], true) ?: [];
        if (!in_array($permiso, $permisos, true) && !in_array('*', $permisos, true)) {
            Http::error(403, 'Este cliente no tiene permiso para: ' . $permiso);
        }
        Db::ejecutar('UPDATE api_clientes SET ultimo_uso = NOW() WHERE id = ?', [$cliente['id']]);
        self::$cliente = $cliente;
        return $cliente;
    }

    /** Id del cliente autenticado en esta solicitud (para la bitácora). */
    public static function clienteId(): ?int
    {
        return self::$cliente ? (int) self::$cliente['id'] : null;
    }
}

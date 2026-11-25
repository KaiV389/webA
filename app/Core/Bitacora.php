<?php
declare(strict_types=1);

namespace App\Core;

/** Registro de quién cambió qué y cuándo. Solo inserta. */
final class Bitacora
{
    public static function registrar(
        string $accion,
        string $entidad,
        ?int $entidadId,
        ?array $antes = null,
        ?array $despues = null,
        ?int $personaId = null
    ): void {
        Db::ejecutar(
            'INSERT INTO bitacora (persona_id, api_cliente_id, accion, entidad, entidad_id, antes, despues, ip)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            [
                $personaId,
                ApiAuth::clienteId(),
                $accion,
                $entidad,
                $entidadId,
                $antes === null ? null : json_encode($antes, JSON_UNESCAPED_UNICODE),
                $despues === null ? null : json_encode($despues, JSON_UNESCAPED_UNICODE),
                $_SERVER['REMOTE_ADDR'] ?? null,
            ]
        );
    }
}

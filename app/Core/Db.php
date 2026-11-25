<?php
declare(strict_types=1);

namespace App\Core;

use PDO;

/**
 * Conexión única a MySQL por solicitud.
 * Todas las consultas usan sentencias preparadas: nunca se pega texto
 * del usuario dentro del SQL.
 */
final class Db
{
    private static ?PDO $pdo = null;

    public static function pdo(): PDO
    {
        if (self::$pdo === null) {
            $c = Config::get('db');
            $dsn = sprintf('mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
                $c['host'], (int) ($c['puerto'] ?? 3306), $c['nombre']);
            self::$pdo = new PDO($dsn, $c['usuario'], $c['password'], [
                PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES   => false,
                PDO::ATTR_TIMEOUT            => 5,
            ]);
            self::$pdo->exec("SET time_zone = '" . date('P') . "'");
        }
        return self::$pdo;
    }

    /** Ejecuta una consulta preparada y devuelve todas las filas. */
    public static function todos(string $sql, array $params = []): array
    {
        $st = self::pdo()->prepare($sql);
        $st->execute($params);
        return $st->fetchAll();
    }

    /** Ejecuta una consulta preparada y devuelve la primera fila, o null. */
    public static function uno(string $sql, array $params = []): ?array
    {
        $st = self::pdo()->prepare($sql);
        $st->execute($params);
        $fila = $st->fetch();
        return $fila === false ? null : $fila;
    }

    /** INSERT/UPDATE/DELETE preparado; devuelve filas afectadas. */
    public static function ejecutar(string $sql, array $params = []): int
    {
        $st = self::pdo()->prepare($sql);
        $st->execute($params);
        return $st->rowCount();
    }

    /** Corre $fn dentro de una transacción; si algo falla, deshace todo. */
    public static function transaccion(callable $fn): mixed
    {
        $pdo = self::pdo();
        $pdo->beginTransaction();
        try {
            $resultado = $fn($pdo);
            $pdo->commit();
            return $resultado;
        } catch (\Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
    }
}

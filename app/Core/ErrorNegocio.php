<?php
declare(strict_types=1);

namespace App\Core;

/**
 * Error esperado de una regla de negocio (folio inexistente, solicitud
 * ya aprobada, dato inválido…). Lleva el código HTTP que debe responderse
 * y siempre se muestra su mensaje, a diferencia de un error inesperado.
 */
final class ErrorNegocio extends \RuntimeException
{
    public function __construct(string $mensaje, public readonly int $http = 422, public readonly array $datos = [])
    {
        parent::__construct($mensaje);
    }
}

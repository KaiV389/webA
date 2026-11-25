<?php
declare(strict_types=1);

/** Escapa texto para HTML. Usar SIEMPRE al imprimir datos en una vista. */
function e(?string $texto): string
{
    return htmlspecialchars($texto ?? '', ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

/** Fecha en español: 25 de noviembre de 2026 */
function fecha_larga(?string $fecha): string
{
    if (!$fecha) {
        return '';
    }
    $meses = ['enero','febrero','marzo','abril','mayo','junio','julio','agosto',
              'septiembre','octubre','noviembre','diciembre'];
    $t = strtotime($fecha);
    return date('j', $t) . ' de ' . $meses[(int) date('n', $t) - 1] . ' de ' . date('Y', $t);
}

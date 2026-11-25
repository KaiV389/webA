<?php
declare(strict_types=1);

namespace App\Core;

/**
 * Enrutador mínimo.
 *   $r->get('/verificar/{token}', [VerificarController::class, 'mostrar']);
 * Los {parametros} llegan al método en el mismo orden.
 */
final class Router
{
    private array $rutas = [];

    public function get(string $patron, callable|array $accion): void
    {
        $this->agregar('GET', $patron, $accion);
    }

    public function post(string $patron, callable|array $accion): void
    {
        $this->agregar('POST', $patron, $accion);
    }

    private function agregar(string $metodo, string $patron, callable|array $accion): void
    {
        $regex = '#^' . preg_replace('#\{(\w+)\}#', '([^/]+)', rtrim($patron, '/') ?: '/') . '$#';
        $this->rutas[] = [$metodo, $regex, $accion];
    }

    public function despachar(string $metodo, string $ruta): never
    {
        $rutaExiste = false;
        foreach ($this->rutas as [$m, $regex, $accion]) {
            if (!preg_match($regex, $ruta, $coincidencias)) {
                continue;
            }
            $rutaExiste = true;
            if ($m !== $metodo) {
                continue;
            }
            array_shift($coincidencias);
            $params = array_map('rawurldecode', $coincidencias);
            if (is_array($accion)) {
                [$clase, $metodoClase] = $accion;
                (new $clase())->$metodoClase(...$params);
            } else {
                $accion(...$params);
            }
            exit;
        }
        Http::error($rutaExiste ? 405 : 404, $rutaExiste ? 'Método no permitido' : 'Página no encontrada');
    }
}

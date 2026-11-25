<?php
declare(strict_types=1);

namespace App\Controladores\Api;

use App\Core\ApiAuth;
use App\Core\Db;
use App\Core\ErrorNegocio;
use App\Core\Http;
use App\Servicios\Afiliaciones;

/**
 * API de afiliaciones. La usan los Apps Script de los Forms y,
 * más adelante, el panel de administración.
 *
 *   POST /api/afiliaciones                    registrar solicitud (Form de afiliación)
 *   GET  /api/afiliaciones/pendientes         bandeja de solicitudes por aprobar
 *   POST /api/afiliaciones/{id}/aprobar       aprobar: folio, tipo, vigencia, documentos
 *   POST /api/afiliaciones/{id}/carta         agregar la carta de compromiso a una solicitud
 *   POST /api/renovaciones                    renovar con el folio del año anterior
 *   POST /api/documentos/{token}/pdf          guardar la liga del PDF ya generado
 */
final class AfiliacionesController
{
    public function registrar(): never
    {
        ApiAuth::requerir('afiliaciones.registrar');
        $r = (new Afiliaciones())->registrar(Http::cuerpoJson());
        Http::json(['ok' => true] + $r, $r['resultado'] === 'pendiente' ? 201 : 200);
    }

    public function pendientes(): never
    {
        ApiAuth::requerir('afiliaciones.aprobar');
        Http::json(['ok' => true, 'pendientes' => (new Afiliaciones())->pendientes()]);
    }

    public function aprobar(string $id): never
    {
        ApiAuth::requerir('afiliaciones.aprobar');
        if (!ctype_digit($id)) {
            throw new ErrorNegocio('Id no válido', 400);
        }
        $d = Http::cuerpoJson();
        $cursos = isset($d['cursos_validos']) ? (int) $d['cursos_validos'] : null;
        if ($cursos !== null && ($cursos < 0 || $cursos > 20)) {
            throw new ErrorNegocio('cursos_validos fuera de rango', 422);
        }
        $por = isset($d['aprobada_por_persona_id']) ? (int) $d['aprobada_por_persona_id'] : null;
        Http::json(['ok' => true] + (new Afiliaciones())->aprobar((int) $id, $cursos, $por));
    }

    public function adjuntarCarta(string $id): never
    {
        ApiAuth::requerir('afiliaciones.aprobar');
        if (!ctype_digit($id)) {
            throw new ErrorNegocio('Id no válido', 400);
        }
        Http::json(['ok' => true] + (new Afiliaciones())->adjuntarCarta((int) $id, Http::cuerpoJson()));
    }

    public function renovar(): never
    {
        ApiAuth::requerir('afiliaciones.renovar');
        Http::json(['ok' => true] + (new Afiliaciones())->renovar(Http::cuerpoJson()));
    }

    public function guardarPdf(string $token): never
    {
        ApiAuth::requerir('documentos.registrar');
        if (!preg_match('/^[a-f0-9]{32}$/', $token)) {
            throw new ErrorNegocio('Token no válido', 400);
        }
        $url = trim((string) (Http::cuerpoJson()['pdf_url'] ?? ''));
        if (!preg_match('#^https://#', $url)) {
            throw new ErrorNegocio('pdf_url debe ser una liga https', 422);
        }
        $n = Db::ejecutar('UPDATE documentos SET pdf_url = ? WHERE verificacion_token = ?', [$url, $token]);
        $existe = $n > 0 || Db::uno('SELECT 1 FROM documentos WHERE verificacion_token = ?', [$token]);
        if (!$existe) {
            throw new ErrorNegocio('No existe ese documento', 404);
        }
        Http::json(['ok' => true]);
    }
}

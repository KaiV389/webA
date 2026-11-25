#!/usr/bin/env bash
# Prueba de punta a punta de la API de afiliaciones.
# Uso: BASE=http://127.0.0.1:8081 TOKEN=... TOKEN_LIMITADO=... bash tests/prueba_api.sh
# Requiere una base de PRUEBA con afiliacion.anio_actual = 2027. Nunca correr contra producción.
set -u
BASE=${BASE:?falta BASE}; TOKEN=${TOKEN:?falta TOKEN}; TOKEN_LIMITADO=${TOKEN_LIMITADO:-}
pasa=0; falla=0
api() { # metodo ruta [json] [token]
  local tok=${4-$TOKEN}
  curl -s -X "$1" "$BASE$2" -H "Content-Type: application/json" ${tok:+-H "Authorization: Bearer $tok"} ${3:+-d "$3"} -w '\n%{http_code}'
}
verifica() { # descripcion respuesta codigo_esperado texto_esperado
  local cod=$(tail -n1 <<<"$2") cuerpo=$(sed '$d' <<<"$2")
  if [[ "$cod" == "$3" && "$cuerpo" == *"$4"* ]]; then pasa=$((pasa+1)); echo "OK    $1"
  else falla=$((falla+1)); echo "FALLA $1  (esperaba $3 con '$4', llegó $cod: ${cuerpo:0:200})"; fi
}
json() { sed '$d' <<<"$1" | python3 -c "import sys,json; d=json.load(sys.stdin); print($2)"; }

ALTA='{"marca_temporal":"03/01/2027 10:15:00","nombre_completo":"  juan  PÉREZ prueba ","curp":"PEPJ800101HMCRRN09","correo":"Juan@Ejemplo.mx","telefono":"55 1234 5678","escuela":{"nombre":"Box Teoloyucan","municipio":"Teoloyucan","estado":"Edo. Mex"},"respuesta_form":{"fila":2}}'

verifica "Sin token → 401"                 "$(api POST /api/afiliaciones "$ALTA" "")" 401 "token"
[ -n "$TOKEN_LIMITADO" ] && verifica "Token sin permiso → 403" "$(api GET /api/afiliaciones/pendientes "" "$TOKEN_LIMITADO")" 403 "permiso"
verifica "CURP inválida → 422"             "$(api POST /api/afiliaciones '{"nombre_completo":"X","curp":"MAL","correo":"x@x.mx","escuela":{"nombre":"E"}}')" 422 "curp"
verifica "JSON inválido → 400"             "$(api POST /api/afiliaciones 'no es json')" 400 "JSON"
R=$(api POST /api/afiliaciones "$ALTA");  verifica "Alta nueva → pendiente"  "$R" 201 '"resultado":"pendiente"'
ID=$(json "$R" "d['afiliacion_id']")
verifica "Doble envío → ya_registrado"     "$(api POST /api/afiliaciones "$ALTA")" 200 '"resultado":"ya_registrado"'
verifica "Bandeja de pendientes"           "$(api GET /api/afiliaciones/pendientes)" 200 'Juan Pérez Prueba'
R=$(api POST /api/afiliaciones/$ID/aprobar '{}'); verifica "Aprobar → folio 2027" "$R" 200 '"folio":"AMBA-27NAL-AFI001"'
verifica "  tipo C sin cursos, vigencia junio" "$R" 200 '"vigencia":"2027-06-30"'
verifica "  3 documentos AFL/CON/CRE"      "$R" 200 'AMBA-27NAL-CRE001'
URL=$(json "$R" "d['documentos'][2]['url_verificar']"); TOK=$(json "$R" "d['documentos'][2]['token']")
verifica "Aprobar otra vez → mismo folio"  "$(api POST /api/afiliaciones/$ID/aprobar '{}')" 200 '"folio":"AMBA-27NAL-AFI001"'
verifica "Verificar credencial nueva"      "$(curl -s "$BASE/verificar/$TOK" -w '\n%{http_code}')" 200 "DOCUMENTO VÁLIDO"
verifica "Guardar liga del PDF"            "$(api POST /api/documentos/$TOK/pdf '{"pdf_url":"https://drive.google.com/x"}')" 200 '"ok":true'
verifica "Liga no https → 422"             "$(api POST /api/documentos/$TOK/pdf '{"pdf_url":"http://x"}')" 422 "https"

# Renovaciones (la base de prueba trae afiliados 2026 sembrados por el script de pruebas)
verifica "Renovar con 'AFL49' (sin cero, serie equivocada)" "$(api POST /api/renovaciones '{"folio_anterior":"afl49 ","nombre_completo":"Ana López Master"}')" 200 '"resultado":"renovada"'
R=$(api POST /api/renovaciones '{"folio_anterior":"AMBA-26NAL-AF1049","nombre_completo":"Ana Lopez Master"}')
verifica "Renovar otra vez con 'AF1049' → ya_renovado" "$R" 200 '"resultado":"ya_renovado"'
verifica "  con 5 cursos → tipo A, vigencia diciembre" "$R" 200 '"vigencia":"2027-12-31"'
verifica "Folio irreconocible → 404"       "$(api POST /api/renovaciones '{"folio_anterior":"hola"}')" 404 "folio_no_reconocido"
verifica "Folio inexistente → 404"         "$(api POST /api/renovaciones '{"folio_anterior":"26NALAFI999"}')" 404 "folio_no_encontrado"
verifica "Nombre que no coincide → en revisión" "$(api POST /api/renovaciones '{"folio_anterior":"AMBA-26NAL-AFI050","nombre_completo":"Pedro Gómez Ruiz"}')" 200 '"resultado":"en_revision"'
verifica "Vetado que renueva → en revisión" "$(api POST /api/renovaciones '{"folio_anterior":"AMBA-26NAL-AFI051","nombre_completo":"Vetado Prueba"}')" 200 '"alerta_veto":true'
R=$(api POST /api/afiliaciones '{"nombre_completo":"Vetado Prueba","curp":"VEPV800101HMCTRT02","correo":"v@x.mx","escuela":{"nombre":"Otra","estado":"CDMX"}}')
verifica "Vetado que se afilia → alerta"   "$R" 200 '"resultado":"ya_registrado"'
VID=$(json "$(api GET /api/afiliaciones/pendientes)" "[p['afiliacion_id'] for p in d['pendientes'] if 'VETO' in (p['alerta'] or '')][0]")
verifica "Aprobar a un vetado → 409"       "$(api POST /api/afiliaciones/$VID/aprobar '{}')" 409 "veto"

echo; echo "Resultado: $pasa correctas, $falla fallidas"; [ $falla -eq 0 ]

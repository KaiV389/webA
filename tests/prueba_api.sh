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

ALTA='{"marca_temporal":"03/01/2027 10:15:00","nombre_completo":"  juan  PÉREZ prueba ","curp":"PEPJ800101HMCRRN09","correo":"Juan@Ejemplo.mx","telefono":"55 1234 5678","escuela":{"nombre":"Box Teoloyucan","municipio":"Teoloyucan","estado":"Edo. Mex"},"respuesta_form":{"fila":2},"carta_compromiso_url":"https://drive.google.com/carta"}'

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

# Reconocimientos de cursos: llegan pendientes en el alta y se validan al aprobar
R=$(api POST /api/afiliaciones '{"nombre_completo":"Con Cursos","curp":"COCU800101HMCNRS05","correo":"c@x.mx","escuela":{"nombre":"Esc C","estado":"MEXICO"},"carta_compromiso_url":"https://drive.google.com/cc","reconocimientos":[{"curso":"Ciencias del deporte","archivo_url":"https://drive.google.com/r1, https://drive.google.com/r2"},{"curso":"Metodología del Boxeo","archivo_url":"https://drive.google.com/r3"},{"curso":"Pedagogía Integral en el Deporte","archivo_url":""}]}')
verifica "Alta con reconocimientos → 3 archivos" "$R" 201 '"reconocimientos":3'
CC=$(json "$R" "d['afiliacion_id']")
verifica "Curso desconocido al aprobar → 422" "$(api POST /api/afiliaciones/$CC/aprobar '{"cursos_validados":["Curso Inventado"]}')" 422 "Curso no reconocido"
R=$(api POST /api/afiliaciones/$CC/aprobar '{"cursos_validados":["Ciencias del deporte","REQ-METODOLOGIA","Pedagogía Integral en el Deporte","Urgencias Médicas en el Boxeo"]}')
verifica "Aprobar con 4 cursos validados → tipo B" "$R" 200 '"tipo":"B"'
verifica "  cursos_validos = 4"            "$R" 200 '"cursos_validos":4'
verifica "  dice cuáles cursos son válidos" "$R" 200 '{"clave":"REQ-MATEMATICAS","nombre":"Matemáticas y Unidades de Medición para el Deporte","valido":false}'
verifica "Renovar con reconocimientos nuevos → avisa" "$(api POST /api/renovaciones '{"folio_anterior":"AMBA-26NAL-AFI053","nombre_completo":"Renueva Con Curso","carta_compromiso_url":"https://drive.google.com/c5","reconocimientos_nuevos":["https://drive.google.com/n1"]}')" 200 '"reconocimientos_por_revisar":1'

# Renovaciones (la base de prueba trae afiliados 2026 sembrados por el script de pruebas)
verifica "Renovar con 'AFL49' (sin cero, serie equivocada)" "$(api POST /api/renovaciones '{"folio_anterior":"afl49 ","nombre_completo":"Ana López Master","carta_compromiso_url":"https://drive.google.com/carta"}')" 200 '"resultado":"renovada"'
R=$(api POST /api/renovaciones '{"folio_anterior":"AMBA-26NAL-AF1049","nombre_completo":"Ana Lopez Master","carta_compromiso_url":"https://drive.google.com/carta"}')
verifica "Renovar otra vez con 'AF1049' → ya_renovado" "$R" 200 '"resultado":"ya_renovado"'
verifica "  con 5 cursos → tipo A, vigencia diciembre" "$R" 200 '"vigencia":"2027-12-31"'
R=$(api POST /api/renovaciones '{"folio_anterior":"AMBA-26NAL-AFI052","nombre_completo":"Sin Carta Prueba"}')
verifica "Renovación anual sin carta → en revisión" "$R" 200 '"falta_carta":true'
RC=$(json "$R" "d['afiliacion_id']")
verifica "  se le agrega la carta"          "$(api POST /api/afiliaciones/$RC/carta '{"carta_compromiso_url":"https://drive.google.com/c3"}')" 200 '"carta_guardada"'
verifica "  y ya se aprueba con folio 2027" "$(api POST /api/afiliaciones/$RC/aprobar '{}')" 200 '"folio":"AMBA-27NAL-AFI'
R=$(api POST /api/afiliaciones '{"nombre_completo":"Nueva Sin Carta","curp":"NUSC800101HMCVNR04","correo":"n@x.mx","escuela":{"nombre":"Esc Nueva","estado":"MEXICO"}}')
verifica "Afiliación nueva sin carta → avisa" "$R" 201 '"falta_carta":true'
SC=$(json "$R" "d['afiliacion_id']")
verifica "Aprobar sin carta → 409"         "$(api POST /api/afiliaciones/$SC/aprobar '{}')" 409 "falta_carta"
verifica "Adjuntar carta después"          "$(api POST /api/afiliaciones/$SC/carta '{"carta_compromiso_url":"https://drive.google.com/c2"}')" 200 '"carta_guardada"'
verifica "Ya con carta → se aprueba"       "$(api POST /api/afiliaciones/$SC/aprobar '{}')" 200 '"resultado":"aprobada"'
verifica "Folio irreconocible → 404"       "$(api POST /api/renovaciones '{"folio_anterior":"hola"}')" 404 "folio_no_reconocido"
verifica "Folio inexistente → 404"         "$(api POST /api/renovaciones '{"folio_anterior":"26NALAFI999"}')" 404 "folio_no_encontrado"
verifica "Nombre que no coincide → en revisión" "$(api POST /api/renovaciones '{"folio_anterior":"AMBA-26NAL-AFI050","nombre_completo":"Pedro Gómez Ruiz"}')" 200 '"resultado":"en_revision"'
verifica "Vetado que renueva → en revisión" "$(api POST /api/renovaciones '{"folio_anterior":"AMBA-26NAL-AFI051","nombre_completo":"Vetado Prueba"}')" 200 '"alerta_veto":true'
R=$(api POST /api/afiliaciones '{"nombre_completo":"Vetado Prueba","curp":"VEPV800101HMCTRT02","correo":"v@x.mx","escuela":{"nombre":"Otra","estado":"CDMX"}}')
verifica "Vetado que se afilia → alerta"   "$R" 200 '"resultado":"ya_registrado"'
VID=$(json "$(api GET /api/afiliaciones/pendientes)" "[p['afiliacion_id'] for p in d['pendientes'] if 'VETO' in (p['alerta'] or '')][0]")
verifica "Aprobar a un vetado → 409"       "$(api POST /api/afiliaciones/$VID/aprobar '{}')" 409 "veto"

echo; echo "Resultado: $pasa correctas, $falla fallidas"; [ $falla -eq 0 ]

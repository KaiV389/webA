/**
 * ══════════════════════════════════════════════════════════════════
 *  AMBA — Migración 2026 → AMBA 2.0
 *  Va en el proyecto de Apps Script de la Sheet de 2026 (la que tiene
 *  las pestañas A2026 y Vetados). Archivo nuevo: Migracion2026.gs
 *
 *  Manda cada afiliado de A2026 (con su folio, CURP, escuela y cursos
 *  validados) a la base nueva, para que pueda renovar en 2027. Los datos
 *  van directo de esta Sheet a tu servidor.
 *
 *  Se puede correr las veces que quieras: lo que ya está no se duplica.
 *  El resultado queda en la pestaña "Migración" (solo fila, folio y
 *  resultado; sin datos personales).
 *
 *  Propiedades del script que necesita (además de las que ya tiene):
 *    API_AMBA_URL     https://nuevo.ambanacional.org
 *    API_AMBA_TOKEN   el mismo token que pusiste en la Sheet 2027
 *
 *  Uso: Ejecutar → migrarTodo   (o primero migrarPrueba con 5 filas)
 * ══════════════════════════════════════════════════════════════════
 */

const MIG = {
  HOJA_BASE: 'A2026',
  HOJA_VETADOS: 'Vetados',
  HOJA_RESULTADO: 'Migración',
  LOTE: 40,
  // Encabezados de A2026 (se buscan sin importar acentos ni mayúsculas;
  // en cada campo se prueba en orden y se usa el primero que exista)
  COL: {
    folio:     ['Folio Maestro'],
    nombre:    ['Nombre'],
    curp:      ['CURP'],
    correo:    ['Correo electrónico de contacto', 'Dirección de correo electrónico'],
    telefono:  ['Teléfono de contacto', 'Telefono', 'WhatsApp'],
    escuela:   ['Nombre de la escuela'],
    municipio: ['Municipio'],
    estado:    ['Estado'],
    foto:      ['Foto_listo', 'Fotografía (para la credencial)'],
    logo:      ['Logo listo', 'Logo de la escuela'],
    tipo:      ['Tipo credencial'],
    vigencia:  ['vigencia'],
    fecha:     ['Marca temporal'],
  },
  CURSOS: {
    ciencias:    ['Curso Ciencias'],
    metodologia: ['Column Curso metodologia', 'Curso metodologia'],
    pedagogia:   ['Curso pedagogia'],
    urgencias:   ['Curso Urgencias'],
    matematicas: ['Curso Matematicas'],
  },
};

function migrarPrueba() { migrar_(5); }
function migrarTodo()   { migrar_(Infinity); migrarVetados(); }

function migrar_(limite) {
  const ss = SpreadsheetApp.getActive();
  const ws = ss.getSheetByName(MIG.HOJA_BASE);
  if (!ws) throw new Error('No existe la pestaña ' + MIG.HOJA_BASE);
  const datos = ws.getDataRange().getValues();
  const h = datos[0].map(x => normMig_(x));
  const col = (opciones) => { for (const o of opciones) { const j = h.indexOf(normMig_(o)); if (j !== -1) return j; } return -1; };

  const J = {}; Object.keys(MIG.COL).forEach(k => J[k] = col(MIG.COL[k]));
  const JC = {}; Object.keys(MIG.CURSOS).forEach(k => JC[k] = col(MIG.CURSOS[k]));
  if (J.folio === -1 || J.nombre === -1) throw new Error('No encontré las columnas "Folio Maestro" y "Nombre" en ' + MIG.HOJA_BASE);
  const faltan = Object.keys(J).filter(k => J[k] === -1).concat(Object.keys(JC).filter(k => JC[k] === -1).map(k => 'curso ' + k));
  if (faltan.length) Logger.log('⚠️ Columnas no encontradas (se mandan vacías): ' + faltan.join(', '));

  const val = (fila, j) => {
    if (j === -1) return '';
    const x = fila[j];
    if (x instanceof Date) return Utilities.formatDate(x, Session.getScriptTimeZone(), "yyyy-MM-dd'T'HH:mm:ss");
    return x === true ? '1' : x === false ? '0' : String(x == null ? '' : x).trim();
  };

  const registros = [];
  for (let i = 1; i < datos.length && registros.length < limite; i++) {
    const f = datos[i];
    if (!val(f, J.folio)) continue;            // sin folio = nunca se afilió
    const cursos = {};
    Object.keys(JC).forEach(k => cursos[k] = val(f, JC[k]));
    registros.push({
      hoja: MIG.HOJA_BASE, fila: i + 1,
      folio: val(f, J.folio), nombre: val(f, J.nombre), curp: val(f, J.curp),
      correo: val(f, J.correo), telefono: val(f, J.telefono),
      foto_url: val(f, J.foto),
      escuela: { nombre: val(f, J.escuela), municipio: val(f, J.municipio), estado: val(f, J.estado), logo_url: val(f, J.logo) },
      cursos: cursos, tipo: val(f, J.tipo), vigencia: val(f, J.vigencia), fecha_registro: val(f, J.fecha),
    });
  }

  const resultados = [];
  const resumen = {};
  for (let k = 0; k < registros.length; k += MIG.LOTE) {
    const r = apiMig_('/api/migracion/afiliaciones', { registros: registros.slice(k, k + MIG.LOTE) });
    r.resultados.forEach(x => {
      resultados.push(x);
      resumen[x.resultado] = (resumen[x.resultado] || 0) + 1;
    });
  }

  // Resultado en su pestaña (sin datos personales)
  let out = ss.getSheetByName(MIG.HOJA_RESULTADO) || ss.insertSheet(MIG.HOJA_RESULTADO);
  out.clear();
  out.appendRow(['Fila A2026', 'Folio', 'Resultado', 'Estatus', 'Sin CURP', 'Detalle']);
  const filas = resultados.map(x => [x.fila, x.folio || '', x.resultado, x.estatus || '', x.sin_curp ? 'sí' : '', x.error || '']);
  if (filas.length) out.getRange(2, 1, filas.length, 6).setValues(filas);
  out.getRange(1, 1, 1, 6).setFontWeight('bold');
  out.setFrozenRows(1);

  const msg = 'Migración de ' + registros.length + ' afiliados:\n' +
    Object.keys(resumen).map(k => '· ' + k + ': ' + resumen[k]).join('\n') +
    '\n\nDetalle en la pestaña "' + MIG.HOJA_RESULTADO + '". Puedes volver a correrlo sin duplicar nada.';
  Logger.log(msg);
  try { SpreadsheetApp.getUi().alert(msg); } catch (e) {}
}

function migrarVetados() {
  const ws = SpreadsheetApp.getActive().getSheetByName(MIG.HOJA_VETADOS);
  if (!ws || ws.getLastRow() < 2) { Logger.log('Sin pestaña Vetados o vacía'); return; }
  const datos = ws.getDataRange().getValues();
  const h = datos[0].map(x => normMig_(x));
  const idx = (n) => h.findIndex(x => x.indexOf(normMig_(n)) !== -1);
  const iN = idx('Nombre'), iE = idx('Escuela'), iC = idx('CURP'), iA = idx('Activo'), iM = idx('Motivo');
  const registros = [];
  for (let i = 1; i < datos.length; i++) {
    const g = (j) => j === -1 ? '' : String(datos[i][j] == null ? '' : datos[i][j]).trim();
    if (!g(iN) && !g(iC)) continue;
    registros.push({ nombre: g(iN), escuela: g(iE), curp: g(iC), activo: iA === -1 ? 'SI' : g(iA), motivo: g(iM) });
  }
  const r = apiMig_('/api/migracion/vetos', { registros: registros });
  const msg = 'Vetados: ' + r.agregados + ' agregados, ' + r.ya_estaban + ' ya estaban.';
  Logger.log(msg);
  try { SpreadsheetApp.getUi().alert(msg); } catch (e) {}
}

function apiMig_(ruta, cuerpo) {
  const props = PropertiesService.getScriptProperties();
  const url = (props.getProperty('API_AMBA_URL') || '').trim().replace(/\/+$/, '');
  const token = (props.getProperty('API_AMBA_TOKEN') || '').trim();
  if (!url || !token) throw new Error('Faltan las propiedades API_AMBA_URL y API_AMBA_TOKEN en este proyecto.');
  const resp = UrlFetchApp.fetch(url + ruta, {
    method: 'post', contentType: 'application/json', muteHttpExceptions: true,
    headers: { Authorization: 'Bearer ' + token, 'X-AMBA-Token': token },
    payload: JSON.stringify(cuerpo),
  });
  let json = {};
  try { json = JSON.parse(resp.getContentText()); } catch (e) {}
  if (resp.getResponseCode() !== 200 || !json.ok) {
    throw new Error('API ' + resp.getResponseCode() + ': ' + (json.error || resp.getContentText().slice(0, 200)));
  }
  return json;
}

function normMig_(s) {
  return String(s == null ? '' : s).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\s+/g, ' ').trim();
}

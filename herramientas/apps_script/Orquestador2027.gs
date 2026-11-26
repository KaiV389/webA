/**
 * ══════════════════════════════════════════════════════════════════
 *  AMBA — Orquestador de afiliaciones y renovaciones 2027
 *  Va en el proyecto de Apps Script de la Sheet de respuestas del form
 *  "AMBA — Afiliación y renovación 2027" (un solo archivo .gs).
 *
 *  Qué hace:
 *   1. Al llegar cada respuesta la manda a la API de AMBA 2.0
 *      (nuevo.ambanacional.org). La API decide folio, vetos, duplicados,
 *      carta y cursos; aquí solo se arman los documentos y los correos.
 *   2. Antes del 1 de enero solo RECIBE: avisa al profe que sus documentos
 *      llegan a partir de esa fecha. Tú puedes ir autorizando afiliaciones.
 *   3. Desde el 1 de enero, cada 10 minutos emite en orden de llegada:
 *      renovaciones en espera y afiliaciones autorizadas (folio, PDFs,
 *      Drive, correo con botón de WhatsApp).
 *
 *  Propiedades del script (Configuración del proyecto → Propiedades):
 *    API_AMBA_URL       https://nuevo.ambanacional.org
 *    API_AMBA_TOKEN     token creado con crear_token.py
 *    PDF_SERVICE_URL    servicio de PDFs en Cloud Run (el de 2026)
 *    PDF_SERVICE_TOKEN  token del servicio de PDFs (el de 2026)
 *    NOTIF_EMAIL        tu correo para avisos
 *
 *  Primera vez: menú 🥊 AMBA 2027 → Verificar configuración → Activar.
 * ══════════════════════════════════════════════════════════════════
 */

const C27 = {
  ANIO: 2027,
  TEXTO_EMISION: '1 de enero de 2027',   // solo para los correos de "recibimos tu solicitud"
  CARPETA_DRIVE: 'AMBA_Afiliaciones_2027',
  MINUTOS_POR_CORRIDA: 4.5,              // Apps Script corta a los 6 min
  GRUPO_WA: 'https://chat.whatsapp.com/K6EIlhyfz7rLXA6Tdpf8mM',

  // Preguntas del form (se buscan sin importar espacios, acentos ni mayúsculas)
  Q: {
    tramite:      '¿Qué trámite vas a realizar?',
    correoVerif:  'Dirección de correo electrónico',
    escuela:      'Nombre de la escuela',
    domicilio:    'Domicilio de la escuela',
    municipio:    'Municipio',
    estado:       'Estado',
    logo:         'Logo de la escuela',
    nombre:       'Nombre',
    curp:         'CURP',
    estudios:     'Nivel de estudios del profesor a cargo',
    licencia:     'En caso de tenerla, ingrese el numero de licencia de manager',
    telefono:     'Teléfono de contacto',
    telAlt:       'Teléfono alternativo',
    correoCont:   'Correo electrónico de contacto',
    foto:         'Fotografía (para la credencial)',
    carta:        'Sube tu hoja de Declaración de responsabilidad y Compromiso firmada',
    cartaVieja:   'Declaración de responsabilidad y compromiso',   // pregunta 2026 (por si quedó)
    folio:        'Número de afiliación (Folio)',
    nombreRenov:  'Nombre completo del profesor afiliado',
    whats:        'WhatsApp de contacto',
    cambio:       '¿Cambió algún dato desde tu última afiliación?',
    cambioDesc:   'Si cambió algo, descríbelo aquí',
    reconNuevos:  'Reconocimientos de cursos nuevos (opcional)',
  },

  // Cursos requisito: pregunta del form → clave en la API → llave del servicio de PDFs
  CURSOS: [
    { pregunta: 'Ciencias del deporte',                               clave: 'REQ-CIENCIAS',    pdf: 'ciencias',    corto: 'Ciencias' },
    { pregunta: 'Metodología del Boxeo',                              clave: 'REQ-METODOLOGIA', pdf: 'metodologia', corto: 'Metodología' },
    { pregunta: 'Pedagogía Integral en el Deporte',                   clave: 'REQ-PEDAGOGIA',   pdf: 'pedagogia',   corto: 'Pedagogía' },
    { pregunta: 'Urgencias Médicas en el Boxeo',                      clave: 'REQ-URGENCIAS',   pdf: 'urgencias',   corto: 'Urgencias' },
    { pregunta: 'Matemáticas y Unidades de Medición para el Deporte', clave: 'REQ-MATEMATICAS', pdf: 'matematicas', corto: 'Matemáticas' },
  ],

  // Columnas de control que este script agrega al final de la hoja
  COL: {
    estatus:   'Estatus',
    id:        'Afiliacion_ID',
    folio:     'Folio_2027',
    tipo:      'Tipo',
    notas:     'Notas',
    autorizado:'Autorizado',
    wa:        'Link_WhatsApp',
    carpeta:   'Carpeta_Drive',
    enviado:   'Enviado',
  },
  PREFIJO_CURSO: '✔ ',   // columnas de validación: "✔ Ciencias", "✔ Metodología"…
};

// Estatus que maneja la hoja
const E27 = {
  PENDIENTE:   'PENDIENTE',      // afiliación: espera tu autorización
  EN_ESPERA:   'EN ESPERA',      // renovación: se emite el 1 de enero
  EN_REVISION: 'EN REVISIÓN',    // veto, nombre que no coincide o falta carta
  ENTREGADO:   'ENTREGADO',
  NO_ENCONTRADO: 'FOLIO NO ENCONTRADO',
  DUPLICADO:   'DUPLICADO',
  ERROR:       'ERROR',
};
const SI27 = ['SI', 'SÍ', 'OK', '1', 'TRUE', 'AUTORIZADO'];


// ══════════════════════════════════════════════════════════════════
//  Menú y configuración
// ══════════════════════════════════════════════════════════════════

function onOpen() {
  SpreadsheetApp.getUi().createMenu('🥊 AMBA 2027')
    .addItem('Emitir ahora (autorizadas y en espera)', 'emitirPendientes')
    .addItem('Reprocesar una fila…', 'reprocesarFila')
    .addSeparator()
    .addItem('Verificar configuración', 'verificarConfig27')
    .addItem('Activar (columnas y disparadores)', 'activar27')
    .addToUi();
}

function prop27_(clave) {
  const v = PropertiesService.getScriptProperties().getProperty(clave);
  if (!v) throw new Error('Falta la propiedad del script: ' + clave);
  return v.trim().replace(/\/+$/, '');
}

function verificarConfig27() {
  const claves = ['API_AMBA_URL', 'API_AMBA_TOKEN', 'PDF_SERVICE_URL', 'PDF_SERVICE_TOKEN', 'NOTIF_EMAIL'];
  const props = PropertiesService.getScriptProperties();
  const faltan = claves.filter(k => !props.getProperty(k));
  const lineas = [];
  lineas.push(faltan.length ? '⚠️ Faltan propiedades:\n· ' + faltan.join('\n· ') : '✅ Propiedades completas');

  if (!faltan.length) {
    try {
      const r = UrlFetchApp.fetch(prop27_('API_AMBA_URL') + '/api/salud', { muteHttpExceptions: true });
      lineas.push('API AMBA: ' + (r.getResponseCode() === 200 ? '✅ ' : '❌ ') + r.getContentText().slice(0, 120));
    } catch (e) { lineas.push('API AMBA: ❌ ' + e.message); }
    try {
      const r = api27_('get', '/api/afiliaciones/pendientes');
      lineas.push('Token de la API: ' + (r.code === 200 ? '✅ válido' : '❌ ' + r.code + ' ' + (r.json.error || '')));
    } catch (e) { lineas.push('Token de la API: ❌ ' + e.message); }
    try {
      const r = UrlFetchApp.fetch(prop27_('PDF_SERVICE_URL') + '/health', { muteHttpExceptions: true });
      lineas.push('Servicio de PDFs: ' + (r.getResponseCode() === 200 ? '✅' : '❌ ' + r.getResponseCode()));
    } catch (e) { lineas.push('Servicio de PDFs: ❌ ' + e.message); }
  }
  const msg = lineas.join('\n');
  Logger.log(msg);
  try { SpreadsheetApp.getUi().alert(msg); } catch (e) {}
}

/** Crea las columnas de control y los dos disparadores. Se puede correr varias veces. */
function activar27() {
  const hoja = hojaRespuestas27_();
  const cols = [C27.COL.estatus, C27.COL.id, C27.COL.folio, C27.COL.tipo, C27.COL.autorizado]
    .concat(C27.CURSOS.map(c => C27.PREFIJO_CURSO + c.corto))
    .concat([C27.COL.notas, C27.COL.wa, C27.COL.carpeta, C27.COL.enviado]);
  const idx = cols.map(c => asegurarCol27_(hoja, c));

  const filas = Math.max(hoja.getMaxRows() - 1, 500);
  const jAut = asegurarCol27_(hoja, C27.COL.autorizado);
  hoja.getRange(2, jAut, filas, 1).setDataValidation(
    SpreadsheetApp.newDataValidation().requireValueInList(['SI', 'NO'], true).setAllowInvalid(true).build());
  for (const c of C27.CURSOS) {
    hoja.getRange(2, asegurarCol27_(hoja, C27.PREFIJO_CURSO + c.corto), filas, 1).insertCheckboxes();
  }
  idx.forEach(j => hoja.getRange(1, j).setFontWeight('bold').setBackground('#1a4d1a').setFontColor('#ffffff'));

  for (const t of ScriptApp.getProjectTriggers()) {
    if (['alEnviar27', 'emitirPendientes'].indexOf(t.getHandlerFunction()) !== -1) ScriptApp.deleteTrigger(t);
  }
  ScriptApp.newTrigger('alEnviar27').forSpreadsheet(SpreadsheetApp.getActive()).onFormSubmit().create();
  ScriptApp.newTrigger('emitirPendientes').timeBased().everyMinutes(10).create();

  const msg = '✅ Activado.\n\n· Columnas de control en "' + hoja.getName() + '"' +
              '\n· Cada respuesta se registra al instante' +
              '\n· Cada 10 minutos se emite lo pendiente (solo desde la fecha de emisión)' +
              '\n\nPara autorizar una afiliación: marca sus cursos válidos (✔) y escribe SI en "Autorizado".';
  Logger.log(msg);
  try { SpreadsheetApp.getUi().alert(msg); } catch (e) {}
}


// ══════════════════════════════════════════════════════════════════
//  1. Al llegar una respuesta
// ══════════════════════════════════════════════════════════════════

function alEnviar27(e) {
  let hoja, fila;
  try { hoja = e.range.getSheet(); fila = e.range.getRow(); } catch (err) { return; }
  try {
    procesarRespuesta27_(hoja, fila, valoresDeEvento27_(e.namedValues || {}));
  } catch (err) {
    Logger.log('❌ Fila ' + fila + ': ' + err.message + '\n' + (err.stack || ''));
    escribir27_(hoja, fila, { estatus: E27.ERROR, notas: err.message.slice(0, 300) });
    avisarKai27_('❌ Error al registrar una respuesta', 'Fila ' + fila + '\n\n' + err.message + '\n\n' + (err.stack || ''));
  }
}

function procesarRespuesta27_(hoja, fila, v) {
  const tramite = norm27_(v(C27.Q.tramite));
  if (tramite.indexOf('renov') === 0) return registrarRenovacion27_(hoja, fila, v);
  return registrarAfiliacion27_(hoja, fila, v);
}

function registrarAfiliacion27_(hoja, fila, v) {
  const correo = v(C27.Q.correoVerif) || v(C27.Q.correoCont);
  const nombre = v(C27.Q.nombre);
  const payload = {
    marca_temporal: v('Marca temporal'),
    nombre_completo: nombre,
    curp: v(C27.Q.curp).toUpperCase().replace(/\s+/g, ''),
    correo: correo,
    telefono: v(C27.Q.telefono),
    foto_url: v(C27.Q.foto),
    carta_compromiso_url: primeraLiga27_(v(C27.Q.carta) || v(C27.Q.cartaVieja)),
    escuela: {
      nombre: v(C27.Q.escuela), domicilio: v(C27.Q.domicilio),
      municipio: v(C27.Q.municipio), estado: v(C27.Q.estado), logo_url: primeraLiga27_(v(C27.Q.logo)),
    },
    reconocimientos: C27.CURSOS.map(c => ({ curso: c.clave, archivo_url: v(c.pregunta) })).filter(r => r.archivo_url),
    respuesta_form: { hoja: hoja.getName(), fila: fila },
    anio_campana: C27.ANIO,   // candado: la API rechaza si la base está en otro año
  };

  const r = api27_('post', '/api/afiliaciones', payload);
  if (r.code === 422) {
    escribir27_(hoja, fila, { estatus: E27.ERROR, notas: 'Datos inválidos: ' + r.json.error });
    avisarKai27_('⚠️ Afiliación con datos inválidos — ' + nombre, 'Fila ' + fila + ': ' + r.json.error);
    return;
  }
  exigirOk27_(r);
  const d = r.json;

  if (d.resultado === 'ya_registrado') {
    escribir27_(hoja, fila, { estatus: E27.DUPLICADO, id: d.afiliacion_id,
      notas: 'Ya había una solicitud ' + C27.ANIO + ' (estatus: ' + d.estatus + (d.folio ? ', folio ' + d.folio : '') + ')' });
    correoSimple27_(correo, 'Ya tenemos tu solicitud — AMBA Nacional',
      'Hola ' + nombre + ',\n\nYa teníamos registrada tu solicitud de afiliación ' + C27.ANIO +
      '. No necesitas enviarla de nuevo; te avisaremos por este medio.');
    return;
  }

  const alertas = [];
  if (d.alerta_veto) alertas.push('🚫 COINCIDE CON UN VETO');
  if (d.falta_carta) alertas.push('Falta la carta de compromiso');
  if (d.afiliado_anterior) alertas.push('Ya estuvo afiliado en años anteriores');
  escribir27_(hoja, fila, { estatus: d.alerta_veto ? E27.EN_REVISION : E27.PENDIENTE, id: d.afiliacion_id,
                            notas: alertas.join(' · ') + (d.reconocimientos ? (alertas.length ? ' · ' : '') + d.reconocimientos + ' archivo(s) de cursos' : '') });

  if (d.alerta_veto) correoEnRevision27_(correo, nombre);
  else correoRecibida27_(correo, nombre, 'afiliación');
  avisoNuevaAfiliacion27_(hoja, fila, v, d, alertas);
}

function registrarRenovacion27_(hoja, fila, v) {
  const correo = v(C27.Q.correoVerif);
  const nombre = v(C27.Q.nombreRenov);
  const payload = {
    marca_temporal: v('Marca temporal'),
    folio_anterior: v(C27.Q.folio),
    nombre_completo: nombre,
    telefono: v(C27.Q.whats),
    correo: correo,
    carta_compromiso_url: primeraLiga27_(v(C27.Q.carta)),
    reconocimientos_nuevos: ligas27_(v(C27.Q.reconNuevos)),
    respuesta_form: { hoja: hoja.getName(), fila: fila },
    anio_campana: C27.ANIO,
  };

  const r = api27_('post', '/api/renovaciones', payload);
  const d = r.json;

  if (r.code === 404) {
    escribir27_(hoja, fila, { estatus: E27.NO_ENCONTRADO, notas: 'Capturó: "' + payload.folio_anterior + '"' });
    correoEnRevision27_(correo, nombre);
    avisarKai27_('⚠️ Renovación con folio no encontrado — ' + nombre,
      'Fila ' + fila + '\nFolio capturado: "' + payload.folio_anterior + '"\nCorreo: ' + correo +
      '\nWhatsApp: ' + payload.telefono + '\n\nCorrige el folio en la hoja y usa "Reprocesar una fila…".');
    return;
  }
  if (r.code === 409 && d.resultado === 'ya_afiliado_este_anio') {
    escribir27_(hoja, fila, { estatus: E27.DUPLICADO, notas: 'Capturó un folio ' + C27.ANIO + ' (' + d.folio + ')' });
    return;
  }
  exigirOk27_(r);

  if (d.resultado === 'ya_renovado' || d.resultado === 'ya_registrado') {
    escribir27_(hoja, fila, { estatus: E27.DUPLICADO, id: d.afiliacion_id, notas: 'Ya había una renovación ' + C27.ANIO });
    return;
  }
  if (d.resultado === 'en_revision') {
    const motivos = [];
    if (d.alerta_veto) motivos.push('🚫 veto');
    if (d.nombre_no_coincide) motivos.push('el nombre no coincide con el del folio');
    if (d.falta_carta) motivos.push('falta la carta de compromiso');
    escribir27_(hoja, fila, { estatus: E27.EN_REVISION, id: d.afiliacion_id, notas: motivos.join(' · ') });
    correoEnRevision27_(correo, nombre);
    avisarKai27_('🔎 Renovación en revisión — ' + nombre,
      'Fila ' + fila + '\nMotivo: ' + motivos.join(', ') + '\nFolio capturado: ' + payload.folio_anterior +
      '\n\nSi todo está bien, escribe SI en "Autorizado" y se emitirá en la siguiente corrida.');
    return;
  }
  if (d.resultado === 'en_espera') {
    escribir27_(hoja, fila, { estatus: E27.EN_ESPERA, id: d.afiliacion_id,
      notas: d.reconocimientos_por_revisar ? d.reconocimientos_por_revisar + ' reconocimiento(s) nuevo(s) por revisar' : '' });
    correoRecibida27_(correo, nombre, 'renovación');
    avisosRenovacion27_(fila, nombre, v, d);
    return;
  }
  // Renovada en el acto (emisión ya abierta)
  entregar27_(hoja, fila, d, 'renovacion', v(C27.Q.whats), correo);
  avisosRenovacion27_(fila, nombre, v, d);
}

function avisosRenovacion27_(fila, nombre, v, d) {
  if (d.reconocimientos_por_revisar) {
    avisarKai27_('📎 Reconocimientos por revisar — ' + nombre,
      'Fila ' + fila + ': subió ' + d.reconocimientos_por_revisar + ' reconocimiento(s) nuevo(s).\n' + v(C27.Q.reconNuevos) +
      '\n\nSu renovación sale con los cursos ya validados. Si validas uno nuevo, márcalo con ✔ antes de que se emita.');
  }
  if (norm27_(v(C27.Q.cambio)).indexOf('si') === 0) {
    avisarKai27_('✏️ Cambio de datos — ' + nombre, 'Fila ' + fila + ': "' + (v(C27.Q.cambioDesc) || 'sin descripción') + '"');
  }
}


// ══════════════════════════════════════════════════════════════════
//  2. Emisión: renovaciones en espera y afiliaciones autorizadas
//     (disparador cada 10 min; también desde el menú)
// ══════════════════════════════════════════════════════════════════

function emitirPendientes() {
  const candado = LockService.getScriptLock();
  if (!candado.tryLock(1000)) return;          // otra corrida sigue trabajando
  const inicio = Date.now();
  const resumen = [];
  try {
    const hoja = hojaRespuestas27_();
    const datos = hoja.getDataRange().getValues();
    const h = datos[0].map(x => String(x).trim());
    const col = (n) => h.indexOf(n);
    const iEst = col(C27.COL.estatus), iId = col(C27.COL.id), iAut = col(C27.COL.autorizado);
    if (iEst === -1 || iId === -1) throw new Error('Falta activar: menú 🥊 AMBA 2027 → Activar.');

    // Filas en orden de llegada (el orden de la hoja = orden del form)
    for (let i = 1; i < datos.length; i++) {
      if ((Date.now() - inicio) / 60000 > C27.MINUTOS_POR_CORRIDA) { resumen.push('⏳ Se acabó el tiempo; sigue en la próxima corrida.'); break; }

      const est = String(datos[i][iEst] || '').trim();
      const id = String(datos[i][iId] || '').trim();
      const autorizado = iAut !== -1 && SI27.indexOf(String(datos[i][iAut] || '').trim().toUpperCase()) !== -1;
      const toca = id && (est === E27.EN_ESPERA || ((est === E27.PENDIENTE || est === E27.EN_REVISION) && autorizado));
      if (!toca) continue;

      const fila = i + 1;
      const v = valoresDeFila27_(h, datos[i]);
      const esRenov = norm27_(v(C27.Q.tramite)).indexOf('renov') === 0;
      const validados = C27.CURSOS.filter(c => datos[i][col(C27.PREFIJO_CURSO + c.corto)] === true).map(c => c.clave);
      // En renovación sin ✔ marcados se usan los cursos que ya están en la base
      const body = (esRenov && validados.length === 0) ? {} : { cursos_validados: validados };
      body.anio_campana = C27.ANIO;

      const r = api27_('post', '/api/afiliaciones/' + id + '/aprobar', body);
      if (r.code === 409 && r.json.resultado === 'en_espera') {
        resumen.push('Todavía no abre la emisión (' + r.json.emision_desde + ').');
        break;                                 // nada más que hacer hasta esa fecha
      }
      if (r.code === 409 && r.json.resultado === 'anio_no_coincide') {
        avisarKai27_('Emisión detenida: el año de la base no es ' + C27.ANIO, r.json.error);
        resumen.push('⛔ ' + r.json.error);
        break;
      }
      if (r.code !== 200) {
        escribir27_(hoja, fila, { notas: '⚠️ ' + (r.json.error || ('HTTP ' + r.code)) });
        resumen.push('❌ Fila ' + fila + ': ' + (r.json.error || r.code));
        continue;
      }
      try {
        entregar27_(hoja, fila, r.json, esRenov ? 'renovacion' : 'afiliacion',
                    esRenov ? v(C27.Q.whats) : v(C27.Q.telefono),
                    esRenov ? v(C27.Q.correoVerif) : (v(C27.Q.correoVerif) || v(C27.Q.correoCont)));
        resumen.push('✅ ' + r.json.folio + ' — ' + r.json.persona.nombre_completo);
      } catch (err) {
        escribir27_(hoja, fila, { estatus: E27.ERROR, folio: r.json.folio, notas: 'Folio asignado; falló la entrega: ' + err.message.slice(0, 200) });
        avisarKai27_('❌ Folio asignado pero falló la entrega — ' + r.json.folio,
          'Fila ' + fila + '\n' + err.message + '\n\nUsa "Reprocesar una fila…" para reintentar: el folio no cambia.');
        resumen.push('❌ ' + r.json.folio + ': ' + err.message);
      }
    }
  } finally {
    candado.releaseLock();
  }
  if (resumen.length) Logger.log(resumen.join('\n'));
  try { if (resumen.length) SpreadsheetApp.getUi().alert(resumen.join('\n')); } catch (e) {}
}


// ══════════════════════════════════════════════════════════════════
//  3. Entrega: PDFs, Drive, correo y WhatsApp
// ══════════════════════════════════════════════════════════════════

function entregar27_(hoja, fila, d, tramite, telefono, correo) {
  if (Number(d.anio) !== C27.ANIO) {
    throw new Error('La API devolvió una afiliación ' + d.anio + ' (folio ' + d.folio + '), no ' + C27.ANIO + '. No se envió nada.');
  }
  const docs = {};
  (d.documentos || []).forEach(x => { docs[x.tipo] = x; });
  const cursos = {};
  C27.CURSOS.forEach(c => {
    const enApi = (d.cursos || []).find(x => x.clave === c.clave);
    cursos[c.pdf] = enApi && enApi.valido ? 1 : 0;
  });
  const vigencia = vigenciaTexto27_(d.vigencia);

  const blobs = pdf27_({
    folio_afi: d.folio,
    folio_con: (docs.constancia_afiliacion || {}).folio || '',
    folio_cre: (docs.credencial || {}).folio || '',
    folio_nom: '',
    nombre: d.persona.nombre_completo,
    escuela: d.escuela.nombre, municipio: d.escuela.municipio, estado: d.escuela.estado,
    rol: 'Entrenador',
    tipo_cred: 'Tipo ' + d.tipo, grado_cred: d.grado,
    vigencia_label: vigencia,
    foto_url: ligaPublica27_(d.persona.foto_url),
    logo_url: ligaPublica27_(d.escuela.logo_url),
    cursos: cursos,
    // QR nuevo: liga permanente de verificación (el servicio de PDFs debe usarla)
    qr_url: (docs.credencial || {}).url_verificar || '',
    fecha_registro: Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'yyyy-MM-dd'),
  });

  // Drive
  const raizIt = DriveApp.getFoldersByName(C27.CARPETA_DRIVE);
  const raiz = raizIt.hasNext() ? raizIt.next() : DriveApp.createFolder(C27.CARPETA_DRIVE);
  const nombreSub = d.folio + ' — ' + d.persona.nombre_completo;
  const subIt = raiz.getFoldersByName(nombreSub);
  const carpeta = subIt.hasNext() ? subIt.next() : raiz.createFolder(nombreSub);
  const links = [];
  for (const b of blobs) {
    const prev = carpeta.getFilesByName(b.getName());
    while (prev.hasNext()) prev.next().setTrashed(true);
    const f = carpeta.createFile(b);
    f.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
    links.push({ nombre: b.getName(), url: f.getUrl() });
    // Liga del PDF en la base (para la página de verificación y el panel)
    const tipo = tipoDocDeArchivo27_(b.getName());
    if (tipo && docs[tipo]) {
      try { api27_('post', '/api/documentos/' + docs[tipo].token + '/pdf', { pdf_url: f.getUrl() }); } catch (e) {}
    }
  }

  correoEntrega27_(correo, d, tramite, vigencia, blobs, links, docs);
  const wa = linkWA27_(telefono, d.persona.nombre_completo, d.folio, vigencia, links, tramite);

  escribir27_(hoja, fila, {
    estatus: E27.ENTREGADO, id: d.afiliacion_id, folio: d.folio, tipo: d.tipo + ' · ' + d.grado,
    wa: wa, carpeta: carpeta.getUrl(),
    enviado: Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'yyyy-MM-dd HH:mm'),
    notas: 'Cursos: ' + d.cursos_validos + '/5',
  });
}

function pdf27_(payload) {
  const resp = UrlFetchApp.fetch(prop27_('PDF_SERVICE_URL') + '/generar', {
    method: 'post', contentType: 'application/json',
    headers: { 'X-AMBA-Token': prop27_('PDF_SERVICE_TOKEN') },
    payload: JSON.stringify(payload), muteHttpExceptions: true,
  });
  if (resp.getResponseCode() !== 200) {
    throw new Error('Servicio PDF HTTP ' + resp.getResponseCode() + ': ' + resp.getContentText().slice(0, 300));
  }
  const json = JSON.parse(resp.getContentText());
  if (!json.ok) throw new Error('Servicio PDF: ' + resp.getContentText().slice(0, 300));
  return json.pdfs.map(p => Utilities.newBlob(Utilities.base64Decode(p.base64), 'application/pdf', p.filename));
}


// ══════════════════════════════════════════════════════════════════
//  Correos
// ══════════════════════════════════════════════════════════════════

function correoRecibida27_(correo, nombre, tramite) {
  correoSimple27_(correo, 'Recibimos tu ' + tramite + ' ' + C27.ANIO + ' — AMBA Nacional',
    'Hola ' + nombre + ',\n\n¡Gracias! Recibimos tu solicitud de ' + tramite + ' ' + C27.ANIO + '. 🥊\n\n' +
    'Tus documentos (afiliación, constancia y credencial) te llegarán a este correo a partir del ' +
    C27.TEXTO_EMISION + '. Los folios se asignan en el orden en que llegaron las solicitudes.\n\n' +
    'No necesitas hacer nada más.');
}

function correoEnRevision27_(correo, nombre) {
  correoSimple27_(correo, 'Recibimos tu solicitud — AMBA Nacional',
    'Hola ' + (nombre || '') + ',\n\nRecibimos tu solicitud. Está en proceso de revisión; ' +
    'en cuanto concluya te contactaremos por este medio.\n\nGracias por tu paciencia.');
}

function correoSimple27_(correo, asunto, texto) {
  if (!correo) return;
  const cuerpo = texto + '\n\nCualquier duda, responde a este correo.\n\nAsociación Mexiquense de Boxeo Amateur\nAMBA Nacional';
  GmailApp.sendEmail(correo, asunto, cuerpo, { name: 'AMBA Nacional', htmlBody: html27_(cuerpo) });
}

function correoEntrega27_(correo, d, tramite, vigencia, blobs, links, docs) {
  if (!correo) throw new Error('La solicitud no tiene correo electrónico.');
  const nombre = d.persona.nombre_completo;
  const faltantes = (d.cursos || []).filter(c => !c.valido).map(c => c.nombre);
  const esRenov = tramite === 'renovacion';

  let cuerpo = 'Hola ' + nombre + ',\n\n' +
    (esRenov ? '¡Tu renovación de afiliación AMBA Nacional ' + C27.ANIO + ' está lista! 🥊\n\n'
             : '¡Bienvenido a la Asociación Mexiquense de Boxeo Amateur! 🥊\n\nTu afiliación quedó registrada. ') +
    'Adjuntamos tus documentos:\n\n  · Afiliación Deportiva\n  · Constancia de Afiliación\n  · Credencial\n\n' +
    'Folio: ' + d.folio + '\nVigencia: ' + vigencia + '\n\n';

  if (!faltantes.length) {
    cuerpo += '¡Felicidades! Tienes tus 5 cursos de formación completos: tu credencial refleja el grado de ' + d.grado + '.\n\n';
  } else {
    cuerpo += 'Cursos de formación completados: ' + d.cursos_validos + ' de 5.\nTe faltan:\n' +
      faltantes.map(f => '  · ' + f).join('\n') + '\n\n' +
      'Completar tu formación fortalece tu grado como entrenador y se refleja directamente en tu credencial. ' +
      'Mantente al pendiente de las próximas fechas de cursos en nuestra página y redes.\n\n';
  }

  if (links.length) {
    let msgWA = 'Mis documentos AMBA Nacional 🥊\nFolio: ' + d.folio + '\nVigencia: ' + vigencia + '\n';
    links.forEach(l => { msgWA += '\n· ' + l.nombre + ':\n' + l.url; });
    cuerpo += '📲 ¿Los quieres en tu WhatsApp? Toca este enlace y elige a quién enviártelos (puede ser a ti mismo):\n' +
              'https://wa.me/?text=' + encodeURIComponent(msgWA) + '\n\n';
  }
  if (!esRenov && C27.GRUPO_WA) {
    cuerpo += '👥 Únete al grupo de WhatsApp de afiliados AMBA, donde compartimos convocatorias, cursos, eventos y avisos:\n' +
              C27.GRUPO_WA + '\n\n(Tu solicitud pasa por aprobación; es un grupo exclusivo de afiliados.)\n\n';
  }
  const verificar = (docs.credencial || {}).url_verificar;
  if (verificar) cuerpo += 'Cualquiera puede verificar tu credencial escaneando su QR o en:\n' + verificar + '\n\n';

  cuerpo += 'Cualquier duda, responde a este correo.\n\nAsociación Mexiquense de Boxeo Amateur\nAMBA Nacional';
  GmailApp.sendEmail(correo, (esRenov ? 'Tu renovación AMBA Nacional ' : 'Tu afiliación AMBA Nacional ') + C27.ANIO + ' — ' + d.folio,
    cuerpo, { attachments: blobs, name: 'AMBA Nacional', htmlBody: html27_(cuerpo) });
}

/**
 * Versión HTML del texto del correo. En texto plano Gmail rompe los emojis
 * (salen como ������); en HTML se ven bien y las ligas quedan clicables.
 */
function html27_(texto) {
  const esc = String(texto).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const conLigas = esc.replace(/https:\/\/[^\s<]+/g, u => {
    const corta = u.length > 70 ? u.slice(0, 60) + '…' : u;
    return '<a href="' + u.replace(/"/g, '&quot;') + '">' + corta + '</a>';
  });
  return emojisHtml27_('<div style="font-family:Arial,sans-serif;font-size:14px;line-height:1.5;color:#222">' +
         conLigas.replace(/\n/g, '<br>') + '</div>');
}

/** GmailApp rompe los emojis "grandes" (🥊, 📲…); como entidad HTML (&#x1F94A;) llegan bien. */
function emojisHtml27_(html) {
  return String(html).replace(/[\uD800-\uDBFF][\uDC00-\uDFFF]/g, par => '&#x' + par.codePointAt(0).toString(16).toUpperCase() + ';');
}

function linkWA27_(tel, nombre, folio, vigencia, links, tramite) {
  const dgt = String(tel || '').replace(/\D/g, '');
  if (dgt.length < 10) return '';
  let msg = '¡Hola ' + nombre + '! 🥊 Tu ' + (tramite === 'renovacion' ? 'renovación' : 'afiliación') +
            ' AMBA Nacional ' + C27.ANIO + ' está lista.\nFolio: ' + folio + '\nVigencia: ' + vigencia + '\n\nTus documentos:\n';
  links.forEach(l => { msg += '· ' + l.nombre + ':\n' + l.url + '\n'; });
  msg += '\nTambién te los enviamos por correo.';
  return 'https://wa.me/52' + dgt.slice(-10) + '?text=' + encodeURIComponent(msg);
}

function avisoNuevaAfiliacion27_(hoja, fila, v, d, alertas) {
  const url = SpreadsheetApp.getActive().getUrl() + '#gid=' + hoja.getSheetId() + '&range=A' + fila;
  const liga = (t, u) => u ? '<b>' + t + ':</b> <a href="' + primeraLiga27_(u) + '">ver</a><br>' : '<b>' + t + ':</b> ⚠️ no subió<br>';
  const html =
    (alertas.length ? '<b style="color:#8b0000">' + alertas.join(' · ') + '</b><br><br>' : '') +
    '<b>Nueva solicitud de afiliación ' + C27.ANIO + '</b> (fila ' + fila + ')<br><br>' +
    '<b>Nombre:</b> ' + v(C27.Q.nombre) + '<br><b>Escuela:</b> ' + v(C27.Q.escuela) + '<br>' +
    '<b>Ubicación:</b> ' + v(C27.Q.municipio) + ', ' + v(C27.Q.estado) + '<br>' +
    '<b>Correo:</b> ' + (v(C27.Q.correoVerif) || v(C27.Q.correoCont)) + '<br><b>Teléfono:</b> ' + v(C27.Q.telefono) + '<br><br>' +
    liga('Foto', v(C27.Q.foto)) + liga('Logo', v(C27.Q.logo)) + liga('Carta de compromiso', v(C27.Q.carta) || v(C27.Q.cartaVieja)) +
    liga('INE', v('Ine del responsable')) +
    C27.CURSOS.map(c => v(c.pregunta) ? '<b>' + c.pregunta + ':</b> <a href="' + primeraLiga27_(v(c.pregunta)) + '">ver</a><br>' : '').join('') +
    '<br><a href="' + url + '">Abrir la fila</a><br><br>' +
    '<i>Para autorizar: marca con ✔ sus cursos válidos y escribe <b>SI</b> en "Autorizado". ' +
    'Se emitirá en orden de llegada a partir del ' + C27.TEXTO_EMISION + '.</i>';
  avisarKai27_((d.alerta_veto ? '🚫 Afiliación con veto — ' : '🆕 Nueva afiliación por autorizar — ') + v(C27.Q.nombre), null, html);
}

function avisarKai27_(asunto, texto, html) {
  try {
    // Gmail rompe en el asunto los emojis "grandes" (🆕, 🚫, 📎…): se quitan ahí
    const limpio = String(asunto).replace(/[\uD800-\uDFFF]/g, '').replace(/\s+/g, ' ').trim();
    GmailApp.sendEmail(prop27_('NOTIF_EMAIL'), '[AMBA 2027] ' + limpio, texto || asunto, html ? { htmlBody: emojisHtml27_(html) } : {});
  } catch (e) { Logger.log('No se pudo avisar: ' + e.message); }
}


// ══════════════════════════════════════════════════════════════════
//  Reprocesar una fila (folio corregido, error de red, etc.)
// ══════════════════════════════════════════════════════════════════

function reprocesarFila() {
  const ui = SpreadsheetApp.getUi();
  const r = ui.prompt('Reprocesar', 'Número de fila a reprocesar:', ui.ButtonSet.OK_CANCEL);
  if (r.getSelectedButton() !== ui.Button.OK) return;
  const fila = parseInt(r.getResponseText(), 10);
  if (!(fila >= 2)) { ui.alert('Fila no válida'); return; }

  const hoja = hojaRespuestas27_();
  const h = hoja.getRange(1, 1, 1, hoja.getLastColumn()).getValues()[0].map(x => String(x).trim());
  const datos = hoja.getRange(fila, 1, 1, hoja.getLastColumn()).getValues()[0];
  const v = valoresDeFila27_(h, datos);
  const id = String(datos[h.indexOf(C27.COL.id)] || '').trim();
  const est = String(datos[h.indexOf(C27.COL.estatus)] || '').trim();

  // Si ya tiene folio pero falló la entrega, solo se vuelve a entregar (el folio no cambia)
  if (id && (est === E27.ERROR || est === E27.ENTREGADO) && String(datos[h.indexOf(C27.COL.folio)] || '').trim()) {
    const a = api27_('post', '/api/afiliaciones/' + id + '/aprobar', { anio_campana: C27.ANIO });
    exigirOk27_(a);
    const esRenov = norm27_(v(C27.Q.tramite)).indexOf('renov') === 0;
    entregar27_(hoja, fila, a.json, esRenov ? 'renovacion' : 'afiliacion',
                esRenov ? v(C27.Q.whats) : v(C27.Q.telefono),
                esRenov ? v(C27.Q.correoVerif) : (v(C27.Q.correoVerif) || v(C27.Q.correoCont)));
  } else {
    procesarRespuesta27_(hoja, fila, v);
  }
  ui.alert('✅ Fila ' + fila + ' reprocesada. Revisa la columna Estatus.');
}


// ══════════════════════════════════════════════════════════════════
//  Utilidades
// ══════════════════════════════════════════════════════════════════

function api27_(metodo, ruta, cuerpo) {
  const opciones = {
    method: metodo, muteHttpExceptions: true,
    // Se manda en los dos encabezados: IONOS a veces no le pasa Authorization a PHP
    headers: { Authorization: 'Bearer ' + prop27_('API_AMBA_TOKEN'), 'X-AMBA-Token': prop27_('API_AMBA_TOKEN') },
  };
  if (cuerpo !== undefined) { opciones.contentType = 'application/json'; opciones.payload = JSON.stringify(cuerpo); }
  // Reintento ante fallas de red o del servidor (5xx); la API aguanta reintentos sin duplicar
  let resp, ultimoError;
  for (let intento = 0; intento < 3; intento++) {
    try {
      resp = UrlFetchApp.fetch(prop27_('API_AMBA_URL') + ruta, opciones);
      if (resp.getResponseCode() < 500) break;
    } catch (e) { ultimoError = e; }
    Utilities.sleep(2000 * (intento + 1));
  }
  if (!resp) throw new Error('No se pudo contactar la API: ' + (ultimoError ? ultimoError.message : ''));
  let json = {};
  try { json = JSON.parse(resp.getContentText()); } catch (e) { json = { error: resp.getContentText().slice(0, 200) }; }
  return { code: resp.getResponseCode(), json: json };
}

function exigirOk27_(r) {
  if (r.code >= 300 || !r.json.ok) throw new Error('API ' + r.code + ': ' + (r.json.error || JSON.stringify(r.json).slice(0, 200)));
}

function norm27_(s) {
  return String(s == null ? '' : s).normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toLowerCase().replace(/\s+/g, ' ').trim();
}

/** Acceso a respuestas por nombre de pregunta, tolerando espacios y acentos. */
function valoresDeEvento27_(nv) {
  const m = {};
  Object.keys(nv).forEach(k => { m[norm27_(k)] = (nv[k] || []).join(', '); });
  return (pregunta) => String(m[norm27_(pregunta)] || '').trim();
}

function valoresDeFila27_(headers, fila) {
  const m = {};
  headers.forEach((h, j) => {
    let x = fila[j];
    if (x instanceof Date) x = Utilities.formatDate(x, Session.getScriptTimeZone(), "yyyy-MM-dd'T'HH:mm:ss");
    m[norm27_(h)] = x == null ? '' : String(x);
  });
  return (pregunta) => String(m[norm27_(pregunta)] || '').trim();
}

function ligas27_(texto) {
  return String(texto || '').split(/\s*,\s*/).filter(u => /^https:\/\//.test(u));
}
function primeraLiga27_(texto) { return ligas27_(texto)[0] || ''; }

/**
 * Los archivos que suben en el form son privados de tu Drive. Para que el
 * servicio de PDFs pueda leer foto y logo se comparten "con el enlace"
 * (solo lectura) y se manda la liga de descarga directa.
 */
function ligaPublica27_(url) {
  const m = String(url || '').match(/[-\w]{25,}/);
  if (!m) return url || '';
  try { DriveApp.getFileById(m[0]).setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW); } catch (e) {}
  return 'https://drive.google.com/uc?export=download&id=' + m[0];
}

function vigenciaTexto27_(fecha) {
  const meses = ['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'];
  const p = String(fecha || '').split('-');
  return p.length === 3 ? meses[parseInt(p[1], 10) - 1] + ' ' + p[0] : String(fecha || '');
}

function tipoDocDeArchivo27_(nombre) {
  const n = norm27_(nombre);
  if (n.indexOf('credencial') !== -1) return 'credencial';
  if (n.indexOf('constancia') !== -1) return 'constancia_afiliacion';
  if (n.indexOf('afiliacion') !== -1) return 'afiliacion';
  return null;
}

function hojaRespuestas27_() {
  const ss = SpreadsheetApp.getActive();
  const conForm = ss.getSheets().find(s => s.getFormUrl());
  return conForm || ss.getSheets()[0];
}

function asegurarCol27_(hoja, nombre) {
  const h = hoja.getRange(1, 1, 1, Math.max(hoja.getLastColumn(), 1)).getValues()[0].map(x => String(x).trim());
  let j = h.indexOf(nombre);
  if (j === -1) { j = h.filter(x => x !== '').length; hoja.getRange(1, j + 1).setValue(nombre); }
  return j + 1;
}

function escribir27_(hoja, fila, datos) {
  const mapa = { estatus: C27.COL.estatus, id: C27.COL.id, folio: C27.COL.folio, tipo: C27.COL.tipo,
                 notas: C27.COL.notas, wa: C27.COL.wa, carpeta: C27.COL.carpeta, enviado: C27.COL.enviado };
  Object.keys(datos).forEach(k => {
    if (datos[k] === undefined || datos[k] === null || datos[k] === '' || !mapa[k]) return;
    hoja.getRange(fila, asegurarCol27_(hoja, mapa[k])).setValue(datos[k]);
  });
  SpreadsheetApp.flush();
}

-- ============================================================
--  AMBA 2.0 — Esquema de base de datos
--  Archivo: 01_esquema.sql
--  Compatible con MySQL 8.0 (IONOS) y MariaDB 10.6+
--
--  Se carga en una base de datos NUEVA y vacía, separada de la
--  que usa la web actual. La web vieja sigue funcionando intacta
--  hasta el cambio de dominio.
--
--  Reglas de diseño:
--   - Todo cuelga de la PERSONA, que existe una sola vez y nunca
--     se borra. La afiliación es un registro por año.
--   - Nada se borra: bajas, vetos y vencimientos son estados.
--   - Las constancias pertenecen a la persona, no a la afiliación.
--   - Los datos sensibles (CURP, teléfono, datos médicos) viven en
--     columnas que ninguna consulta pública debe seleccionar.
--
--  Orden de carga: 01_esquema.sql → 02_catalogos.sql
-- ============================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ============================================================
--  1. CATÁLOGOS Y CONFIGURACIÓN
-- ============================================================

CREATE TABLE estados (
  id          TINYINT UNSIGNED NOT NULL,           -- clave INEGI (1–32); 99 = extranjero
  clave       VARCHAR(3)       NOT NULL,           -- la misma de la CURP (MC, DF, HG…); se usa en folios estatales
  nombre      VARCHAR(60)      NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_estados_clave (clave)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Clave / valor para todo lo que se ajusta sin tocar código:
-- plazos de expediente, formato de folio, umbral de cursos, etc.
CREATE TABLE configuracion (
  clave        VARCHAR(60)  NOT NULL,
  valor        JSON         NOT NULL,
  descripcion  VARCHAR(255) NULL,
  solo_sistemas TINYINT(1)  NOT NULL DEFAULT 1,     -- 1 = solo el rol Sistemas puede cambiarla
  actualizado_por BIGINT UNSIGNED NULL,
  actualizado_at  DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (clave)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
--  2. PERSONAS, ESCUELAS Y CUENTAS
-- ============================================================

CREATE TABLE personas (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  nombre_completo    VARCHAR(150)     NOT NULL,
  curp               CHAR(18)         NULL,           -- PRIVADA. Une a la persona entre años y alimenta vetos
  correo             VARCHAR(150)     NULL,           -- correo de contacto dado en el Form (puede diferir del de la cuenta)
  telefono           VARCHAR(20)      NULL,           -- PRIVADO
  telefono_alt       VARCHAR(20)      NULL,           -- PRIVADO
  fecha_nacimiento   DATE             NULL,
  sexo               ENUM('H','M')    NULL,
  estado_id          TINYINT UNSIGNED NULL,
  municipio          VARCHAR(100)     NULL,
  foto_url           VARCHAR(500)     NULL,
  nivel_estudios     VARCHAR(100)     NULL,
  licencia_manager   VARCHAR(50)      NULL,
  fecha_primera_afiliacion DATE       NULL,           -- para estadísticas de antigüedad
  notas_internas     TEXT             NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_personas_curp (curp),
  KEY ix_personas_nombre (nombre_completo),
  KEY ix_personas_estado (estado_id),
  CONSTRAINT fk_personas_estado FOREIGN KEY (estado_id) REFERENCES estados (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE escuelas (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  nombre             VARCHAR(150)     NOT NULL,
  logo_url           VARCHAR(500)     NULL,
  domicilio          VARCHAR(255)     NULL,           -- PRIVADO: el del Form, solo se usa como sugerencia
  municipio          VARCHAR(100)     NULL,
  estado_id          TINYINT UNSIGNED NULL,
  -- Mapa: nada se publica hasta que el profesor lo autoriza
  lat                DECIMAL(9,6)     NULL,
  lng                DECIMAL(9,6)     NULL,
  ubicacion_publica  TINYINT(1)       NOT NULL DEFAULT 0,
  ubicacion_autorizada_por BIGINT UNSIGNED NULL,      -- persona que autorizó publicarla
  ubicacion_autorizada_at  DATETIME   NULL,
  horarios           TEXT             NULL,           -- opcional, público solo si se comparte
  descripcion        TEXT             NULL,
  redes              JSON             NULL,           -- {"facebook": "...", "instagram": "...", "whatsapp_escuela": "..."}
  activa             TINYINT(1)       NOT NULL DEFAULT 1,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_escuelas_estado (estado_id),
  KEY ix_escuelas_nombre (nombre),
  CONSTRAINT fk_escuelas_estado FOREIGN KEY (estado_id) REFERENCES estados (id),
  CONSTRAINT fk_escuelas_autoriza FOREIGN KEY (ubicacion_autorizada_por) REFERENCES personas (id),
  CONSTRAINT ck_escuelas_mapa CHECK (ubicacion_publica = 0 OR (lat IS NOT NULL AND lng IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Una sola cuenta por persona (uq_cuentas_persona).
-- Las cuentas gratuitas también tienen persona, para que sus
-- constancias le pertenezcan desde el primer curso.
CREATE TABLE cuentas (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  persona_id         BIGINT UNSIGNED  NOT NULL,
  correo             VARCHAR(150)     NOT NULL,       -- usuario de acceso
  password_hash      VARCHAR(255)     NULL,           -- NULL mientras no active la cuenta
  estatus            ENUM('pendiente','activa','bloqueada') NOT NULL DEFAULT 'pendiente',
  motivo_bloqueo     VARCHAR(255)     NULL,
  correo_verificado_at DATETIME       NULL,
  ultimo_acceso      DATETIME         NULL,
  intentos_fallidos  TINYINT UNSIGNED NOT NULL DEFAULT 0,
  bloqueada_hasta    DATETIME         NULL,           -- freno contra adivinar contraseñas
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_cuentas_persona (persona_id),
  UNIQUE KEY uq_cuentas_correo (correo),
  CONSTRAINT fk_cuentas_persona FOREIGN KEY (persona_id) REFERENCES personas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tokens de un solo uso: activar cuenta, verificar correo,
-- restablecer contraseña y el código para vincular un folio.
-- Se guarda solo el HASH del token, nunca el token en claro.
CREATE TABLE cuenta_tokens (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  cuenta_id          BIGINT UNSIGNED  NOT NULL,
  tipo               ENUM('activar','verificar_correo','restablecer','vincular_folio') NOT NULL,
  token_hash         CHAR(64)         NOT NULL,       -- SHA-256 en hexadecimal
  datos              JSON             NULL,           -- p. ej. {"afiliacion_id": 123} al vincular
  expira_at          DATETIME         NOT NULL,
  usado_at           DATETIME         NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_tokens_hash (token_hash),
  KEY ix_tokens_cuenta (cuenta_id, tipo),
  CONSTRAINT fk_tokens_cuenta FOREIGN KEY (cuenta_id) REFERENCES cuentas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Vinculaciones que no se pudieron hacer por código (ya no tiene
-- acceso al correo del Form) y caen a la bandeja para revisión.
CREATE TABLE vinculaciones_manuales (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  cuenta_id          BIGINT UNSIGNED  NOT NULL,
  folio_capturado    VARCHAR(40)      NOT NULL,
  afiliacion_id      BIGINT UNSIGNED  NULL,           -- la que se encontró con ese folio, si existe
  mensaje            TEXT             NULL,
  estatus            ENUM('pendiente','aprobada','rechazada') NOT NULL DEFAULT 'pendiente',
  resuelta_por       BIGINT UNSIGNED  NULL,
  resuelta_at        DATETIME         NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_vinc_estatus (estatus),
  CONSTRAINT fk_vinc_cuenta FOREIGN KEY (cuenta_id) REFERENCES cuentas (id),
  CONSTRAINT fk_vinc_resuelve FOREIGN KEY (resuelta_por) REFERENCES personas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Clientes de la API (Apps Script de afiliaciones, servicio de PDFs,
-- futura app). Token largo, guardado solo como hash.
CREATE TABLE api_clientes (
  id                 INT UNSIGNED     NOT NULL AUTO_INCREMENT,
  nombre             VARCHAR(80)      NOT NULL,
  token_hash         CHAR(64)         NOT NULL,
  permisos           JSON             NOT NULL,       -- ["afiliaciones.crear", "afiliaciones.renovar", ...]
  activo             TINYINT(1)       NOT NULL DEFAULT 1,
  ultimo_uso         DATETIME         NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_api_token (token_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
--  3. AFILIACIONES, FOLIOS Y ROLES
-- ============================================================

-- Contador de folios: uno por año, serie y ámbito.
-- Ámbito = 'NAL' para nacionales, o la clave del estado para
-- series estatales (delegados). Se lee con SELECT … FOR UPDATE
-- dentro de una transacción, así dos registros simultáneos
-- nunca reciben el mismo número ni se salta ninguno.
CREATE TABLE folio_contadores (
  anio               SMALLINT UNSIGNED NOT NULL,
  serie              VARCHAR(4)        NOT NULL,      -- AFI, DE, MD, CT (constancia de trayectoria), AV (aval)…
  ambito             VARCHAR(4)        NOT NULL DEFAULT 'NAL',
  ultimo             INT UNSIGNED      NOT NULL DEFAULT 0,
  PRIMARY KEY (anio, serie, ambito)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE afiliaciones (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  persona_id         BIGINT UNSIGNED  NOT NULL,
  anio               SMALLINT UNSIGNED NOT NULL,
  -- Folio del año. Se asigna al APROBAR, por eso puede ir vacío
  -- mientras la solicitud está pendiente.
  serie              VARCHAR(4)       NULL,           -- AFI normalmente
  consecutivo        INT UNSIGNED     NULL,
  folio              VARCHAR(40)      NULL,           -- p. ej. AMBA-27NAL-AFI001
  escuela_id         BIGINT UNSIGNED  NULL,
  tipo_credencial    ENUM('A','B','C') NULL,          -- A Master (5 cursos), B Entrenador (4), C Instructor (≤3)
  grado              VARCHAR(40)      NULL,           -- texto que va en la credencial
  cursos_validos     TINYINT UNSIGNED NOT NULL DEFAULT 0,
  vigencia           DATE             NULL,
  estatus            ENUM('pendiente','activa','vencida','baja','vetada','rechazada','duplicada')
                                      NOT NULL DEFAULT 'pendiente',
  motivo_estatus     VARCHAR(255)     NULL,
  estatus_cambiado_por BIGINT UNSIGNED NULL,
  estatus_cambiado_at  DATETIME       NULL,
  origen             ENUM('form_afiliacion','form_renovacion','panel_renovacion','manual','migracion')
                                      NOT NULL,
  afiliacion_anterior_id BIGINT UNSIGNED NULL,        -- la del año pasado, si es renovación
  fecha_registro     DATETIME         NOT NULL,       -- marca temporal del Form: base de las estadísticas por mes
  aprobada_por       BIGINT UNSIGNED  NULL,
  aprobada_at        DATETIME         NULL,
  datos_form         JSON             NULL,           -- respuesta original del Form, tal como llegó
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_afil_persona_anio (persona_id, anio),          -- una por persona por año
  UNIQUE KEY uq_afil_folio (folio),
  UNIQUE KEY uq_afil_consecutivo (anio, serie, consecutivo),
  KEY ix_afil_estatus (anio, estatus),
  KEY ix_afil_escuela (escuela_id),
  CONSTRAINT fk_afil_persona   FOREIGN KEY (persona_id) REFERENCES personas (id),
  CONSTRAINT fk_afil_escuela   FOREIGN KEY (escuela_id) REFERENCES escuelas (id),
  CONSTRAINT fk_afil_anterior  FOREIGN KEY (afiliacion_anterior_id) REFERENCES afiliaciones (id),
  CONSTRAINT fk_afil_aprueba   FOREIGN KEY (aprobada_por) REFERENCES personas (id),
  CONSTRAINT fk_afil_cambia    FOREIGN KEY (estatus_cambiado_por) REFERENCES personas (id),
  CONSTRAINT ck_afil_folio CHECK (estatus IN ('pendiente','rechazada','duplicada') OR folio IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Roles con periodo. El rol 'sistemas' solo puede tener UNA
-- asignación activa a la vez: lo garantiza uq_roles_sistemas.
CREATE TABLE persona_roles (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  persona_id         BIGINT UNSIGNED  NOT NULL,
  rol                ENUM('sistemas','presidente','mesa_nacional','delegado','mesa_estatal','moderador') NOT NULL,
  estado_id          TINYINT UNSIGNED NULL,           -- obligatorio para roles estatales
  cargo              VARCHAR(60)      NULL,           -- secretario, vocal, tesorero…
  folio_nombramiento VARCHAR(40)      NULL,
  inicio             DATE             NOT NULL,
  fin                DATE             NULL,           -- NULL = vigente
  activo             TINYINT(1)       NOT NULL DEFAULT 1,
  asignado_por       BIGINT UNSIGNED  NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  sistemas_unico     VARCHAR(10) GENERATED ALWAYS AS (IF(rol = 'sistemas' AND activo = 1, 'sistemas', NULL)) STORED,
  PRIMARY KEY (id),
  UNIQUE KEY uq_roles_sistemas (sistemas_unico),
  UNIQUE KEY uq_roles_folio (folio_nombramiento),
  KEY ix_roles_persona (persona_id, activo),
  KEY ix_roles_estado (estado_id, rol, activo),
  CONSTRAINT fk_roles_persona FOREIGN KEY (persona_id) REFERENCES personas (id),
  CONSTRAINT fk_roles_estado  FOREIGN KEY (estado_id) REFERENCES estados (id),
  CONSTRAINT fk_roles_asigna  FOREIGN KEY (asignado_por) REFERENCES personas (id),
  CONSTRAINT ck_roles_estatal CHECK (rol NOT IN ('delegado','mesa_estatal','moderador') OR estado_id IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE vetos (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  persona_id         BIGINT UNSIGNED  NULL,
  curp               CHAR(18)         NULL,           -- llave principal de detección
  nombre             VARCHAR(150)     NULL,
  escuela_texto      VARCHAR(150)     NULL,
  motivo             TEXT             NOT NULL,
  activo             TINYINT(1)       NOT NULL DEFAULT 1,
  registrado_por     BIGINT UNSIGNED  NULL,
  -- Contenido del vetado (fotos, eventos): pendiente de decisión de la mesa nacional
  decision_contenido ENUM('pendiente','conservar','eliminar') NOT NULL DEFAULT 'pendiente',
  decision_por       BIGINT UNSIGNED  NULL,
  decision_at        DATETIME         NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_vetos_curp (curp, activo),
  KEY ix_vetos_persona (persona_id),
  CONSTRAINT fk_vetos_persona  FOREIGN KEY (persona_id) REFERENCES personas (id),
  CONSTRAINT fk_vetos_registra FOREIGN KEY (registrado_por) REFERENCES personas (id),
  CONSTRAINT fk_vetos_decide   FOREIGN KEY (decision_por) REFERENCES personas (id),
  CONSTRAINT ck_vetos_identifica CHECK (persona_id IS NOT NULL OR curp IS NOT NULL OR nombre IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
--  4. FORMACIÓN: CURSOS, RECONOCIMIENTOS, CONSTANCIAS, PAGOS
-- ============================================================

CREATE TABLE cursos (
  id                 INT UNSIGNED     NOT NULL AUTO_INCREMENT,
  clave              VARCHAR(30)      NOT NULL,
  nombre             VARCHAR(150)     NOT NULL,
  tipo               ENUM('requisito','core_basico','core_pago','sesiones') NOT NULL,
  -- requisito   = uno de los cursos que cuentan para la credencial (se acredita con reconocimiento)
  -- core_basico = AMBA Core, gratis para afiliados activos
  -- core_pago   = AMBA Core con costo
  -- sesiones    = cursos en vivo por sesiones (los que hoy se cobran)
  descripcion        TEXT             NULL,
  costo_afiliado     DECIMAL(8,2)     NOT NULL DEFAULT 0,
  costo_externo      DECIMAL(8,2)     NULL,           -- NULL = no disponible para cuentas gratuitas
  activo             TINYINT(1)       NOT NULL DEFAULT 1,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_cursos_clave (clave)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Los 5 cursos que cuentan para la credencial de cada año.
CREATE TABLE requisitos_anuales (
  anio               SMALLINT UNSIGNED NOT NULL,
  curso_id           INT UNSIGNED      NOT NULL,
  orden              TINYINT UNSIGNED  NOT NULL,
  PRIMARY KEY (anio, curso_id),
  CONSTRAINT fk_req_curso FOREIGN KEY (curso_id) REFERENCES cursos (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Cada cambio de contenido o de examen crea una versión nueva;
-- las constancias apuntan a la versión exacta que se aprobó.
CREATE TABLE curso_versiones (
  id                 INT UNSIGNED     NOT NULL AUTO_INCREMENT,
  curso_id           INT UNSIGNED     NOT NULL,
  version            SMALLINT UNSIGNED NOT NULL,
  contenido          JSON             NULL,           -- módulos, lecturas, videos
  preguntas_examen   TINYINT UNSIGNED NOT NULL DEFAULT 12,
  umbral_aprobacion  DECIMAL(5,2)     NOT NULL DEFAULT 80.00,
  tiempo_limite_min  SMALLINT UNSIGNED NULL,
  lectura_minima_seg INT UNSIGNED     NULL,           -- tiempo mínimo de lectura antes del examen
  publicada_at       DATETIME         NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_cv_version (curso_id, version),
  CONSTRAINT fk_cv_curso FOREIGN KEY (curso_id) REFERENCES cursos (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE preguntas (
  id                 INT UNSIGNED     NOT NULL AUTO_INCREMENT,
  curso_version_id   INT UNSIGNED     NOT NULL,
  texto              TEXT             NOT NULL,
  retroalimentacion  TEXT             NULL,           -- se muestra sin revelar la respuesta correcta
  activa             TINYINT(1)       NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  KEY ix_preg_version (curso_version_id, activa),
  CONSTRAINT fk_preg_version FOREIGN KEY (curso_version_id) REFERENCES curso_versiones (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE pregunta_opciones (
  id                 INT UNSIGNED     NOT NULL AUTO_INCREMENT,
  pregunta_id        INT UNSIGNED     NOT NULL,
  texto              VARCHAR(500)     NOT NULL,
  correcta           TINYINT(1)       NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  KEY ix_opc_pregunta (pregunta_id),
  CONSTRAINT fk_opc_pregunta FOREIGN KEY (pregunta_id) REFERENCES preguntas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Pagos de cursos (y a futuro avales de externos u otros conceptos).
CREATE TABLE pagos (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  persona_id         BIGINT UNSIGNED  NOT NULL,
  concepto           VARCHAR(150)     NOT NULL,
  monto              DECIMAL(10,2)    NOT NULL,
  metodo             ENUM('mercadopago','transferencia','efectivo','cortesia') NOT NULL,
  estatus            ENUM('pendiente','en_revision','pagado','rechazado','reembolsado') NOT NULL DEFAULT 'pendiente',
  comprobante_url    VARCHAR(500)     NULL,           -- transferencia: foto del comprobante
  proveedor_ref      VARCHAR(100)     NULL,           -- id de pago de Mercado Pago
  validado_por       BIGINT UNSIGNED  NULL,
  validado_at        DATETIME         NULL,
  notas              VARCHAR(255)     NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_pagos_proveedor (proveedor_ref),
  KEY ix_pagos_estatus (estatus),
  CONSTRAINT fk_pagos_persona FOREIGN KEY (persona_id) REFERENCES personas (id),
  CONSTRAINT fk_pagos_valida  FOREIGN KEY (validado_por) REFERENCES personas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE inscripciones (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  persona_id         BIGINT UNSIGNED  NOT NULL,
  curso_version_id   INT UNSIGNED     NOT NULL,
  pago_id            BIGINT UNSIGNED  NULL,           -- NULL en cursos gratuitos
  estatus            ENUM('pendiente_pago','activa','aprobada','cancelada') NOT NULL DEFAULT 'activa',
  progreso           JSON             NULL,           -- módulos vistos y tiempo de lectura
  inicio_at          DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  aprobada_at        DATETIME         NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_insc_persona_version (persona_id, curso_version_id),
  CONSTRAINT fk_insc_persona FOREIGN KEY (persona_id) REFERENCES personas (id),
  CONSTRAINT fk_insc_version FOREIGN KEY (curso_version_id) REFERENCES curso_versiones (id),
  CONSTRAINT fk_insc_pago    FOREIGN KEY (pago_id) REFERENCES pagos (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE intentos (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  inscripcion_id     BIGINT UNSIGNED  NOT NULL,
  inicio_at          DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  fin_at             DATETIME         NULL,
  preguntas          JSON             NOT NULL,       -- ids de las preguntas barajadas que le tocaron
  respuestas         JSON             NULL,
  calificacion       DECIMAL(5,2)     NULL,
  aprobado           TINYINT(1)       NULL,
  PRIMARY KEY (id),
  KEY ix_intentos_insc (inscripcion_id),
  CONSTRAINT fk_intentos_insc FOREIGN KEY (inscripcion_id) REFERENCES inscripciones (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Constancias: NUNCA se modifican ni se borran (válidas aunque
-- haya baja o veto). El código de la API no tiene UPDATE ni DELETE
-- para esta tabla; ver también los triggers opcionales al final.
CREATE TABLE constancias (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  folio              VARCHAR(40)      NOT NULL,
  persona_id         BIGINT UNSIGNED  NOT NULL,
  curso_version_id   INT UNSIGNED     NOT NULL,
  intento_id         BIGINT UNSIGNED  NULL,
  nombre_impreso     VARCHAR(150)     NOT NULL,       -- nombre tal como salió en la constancia
  calificacion       DECIMAL(5,2)     NULL,
  emitida_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  pdf_url            VARCHAR(500)     NULL,
  verificacion_token CHAR(32)         NOT NULL,       -- lo que lleva el QR
  PRIMARY KEY (id),
  UNIQUE KEY uq_const_folio (folio),
  UNIQUE KEY uq_const_token (verificacion_token),
  KEY ix_const_persona (persona_id),
  CONSTRAINT fk_const_persona FOREIGN KEY (persona_id) REFERENCES personas (id),
  CONSTRAINT fk_const_version FOREIGN KEY (curso_version_id) REFERENCES curso_versiones (id),
  CONSTRAINT fk_const_intento FOREIGN KEY (intento_id) REFERENCES intentos (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Reconocimientos de cursos externos que se validan a mano y
-- cuentan para los requisitos del año.
CREATE TABLE reconocimientos (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  persona_id         BIGINT UNSIGNED  NOT NULL,
  curso_id           INT UNSIGNED     NULL,           -- a qué requisito corresponde, si aplica
  nombre_curso       VARCHAR(200)     NOT NULL,       -- como viene en el documento
  institucion        VARCHAR(200)     NULL,
  fecha_curso        DATE             NULL,
  archivo_url        VARCHAR(500)     NULL,
  estatus            ENUM('pendiente','valido','no_valido') NOT NULL DEFAULT 'pendiente',
  validado_por       BIGINT UNSIGNED  NULL,
  validado_at        DATETIME         NULL,
  notas              VARCHAR(255)     NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_recon_persona (persona_id, estatus),
  KEY ix_recon_pendientes (estatus, created_at),
  CONSTRAINT fk_recon_persona FOREIGN KEY (persona_id) REFERENCES personas (id),
  CONSTRAINT fk_recon_curso   FOREIGN KEY (curso_id) REFERENCES cursos (id),
  CONSTRAINT fk_recon_valida  FOREIGN KEY (validado_por) REFERENCES personas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
--  5. EVENTOS, AVALES Y EXPEDIENTES
-- ============================================================

CREATE TABLE eventos (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  titulo             VARCHAR(200)     NOT NULL,
  descripcion        TEXT             NULL,
  nivel              TINYINT UNSIGNED NOT NULL,       -- 1 local/sparring · 2 estatal · 3 nacional · 4 oficial AMBA
  tipo               ENUM('sparring','funcion','torneo','curso','premiacion','otro') NOT NULL,
  organizador_id     BIGINT UNSIGNED  NOT NULL,       -- persona responsable (profesor a cargo)
  escuela_id         BIGINT UNSIGNED  NULL,
  estado_id          TINYINT UNSIGNED NOT NULL,
  municipio          VARCHAR(100)     NULL,
  lugar              VARCHAR(255)     NULL,
  lat                DECIMAL(9,6)     NULL,
  lng                DECIMAL(9,6)     NULL,
  inicio             DATETIME         NOT NULL,
  fin                DATETIME         NULL,
  costo_ficha        DECIMAL(8,2)     NULL,
  estatus            ENUM('borrador','solicitado','autorizado','rechazado','cancelado','realizado')
                                      NOT NULL DEFAULT 'solicitado',
  certeza            ENUM('probable','confirmado') NOT NULL DEFAULT 'confirmado',
  destacado          TINYINT(1)       NOT NULL DEFAULT 0,
  es_selectivo       TINYINT(1)       NOT NULL DEFAULT 0,
  transmision_url    VARCHAR(500)     NULL,
  oculto             TINYINT(1)       NOT NULL DEFAULT 0,   -- p. ej. contenido de un vetado en revisión
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_eventos_fecha (inicio),
  KEY ix_eventos_estado (estado_id, inicio),
  KEY ix_eventos_estatus (estatus),
  CONSTRAINT fk_eventos_org     FOREIGN KEY (organizador_id) REFERENCES personas (id),
  CONSTRAINT fk_eventos_escuela FOREIGN KEY (escuela_id) REFERENCES escuelas (id),
  CONSTRAINT fk_eventos_estado  FOREIGN KEY (estado_id) REFERENCES estados (id),
  CONSTRAINT ck_eventos_nivel   CHECK (nivel BETWEEN 1 AND 4),
  CONSTRAINT ck_eventos_fechas  CHECK (fin IS NULL OR fin >= inicio)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Un expediente por evento con aval. Las fechas de recordatorio,
-- vencimiento y prórroga se calculan con los plazos de configuración.
CREATE TABLE expedientes (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  evento_id          BIGINT UNSIGNED  NOT NULL,
  etapa              ENUM('autorizacion','pre_evento','post_evento','cerrado') NOT NULL DEFAULT 'autorizacion',
  recordatorio_at    DATE             NULL,           -- día 7
  vence_at           DATE             NULL,           -- día 14
  prorroga_hasta     DATE             NULL,           -- máximo día 21, una sola vez
  prorrogado_por     BIGINT UNSIGNED  NULL,
  resumen_operativo  TEXT             NULL,
  hubo_traslado_hospital TINYINT(1)   NULL,
  incidentes         TEXT             NULL,
  cerrado_por        BIGINT UNSIGNED  NULL,
  cerrado_at         DATETIME         NULL,
  cerrado_vencido    TINYINT(1)       NOT NULL DEFAULT 0,   -- 1 = lo cerró mesa nacional/Sistemas fuera de plazo
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_exp_evento (evento_id),
  KEY ix_exp_vence (etapa, vence_at),
  CONSTRAINT fk_exp_evento   FOREIGN KEY (evento_id) REFERENCES eventos (id),
  CONSTRAINT fk_exp_prorroga FOREIGN KEY (prorrogado_por) REFERENCES personas (id),
  CONSTRAINT fk_exp_cierra   FOREIGN KEY (cerrado_por) REFERENCES personas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE expediente_archivos (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  expediente_id      BIGINT UNSIGNED  NOT NULL,
  tipo               ENUM('ambulancia','servicio_medico','jueces','seguridad','aval_firmado',
                          'resultados','responsiva','otro') NOT NULL,
  archivo_url        VARCHAR(500)     NOT NULL,
  descripcion        VARCHAR(255)     NULL,
  subido_por         BIGINT UNSIGNED  NOT NULL,
  verificado_por     BIGINT UNSIGNED  NULL,
  verificado_at      DATETIME         NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_exparch_exp (expediente_id, tipo),
  CONSTRAINT fk_exparch_exp      FOREIGN KEY (expediente_id) REFERENCES expedientes (id),
  CONSTRAINT fk_exparch_sube     FOREIGN KEY (subido_por) REFERENCES personas (id),
  CONSTRAINT fk_exparch_verifica FOREIGN KEY (verificado_por) REFERENCES personas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Todo documento generado por el servicio de PDFs: afiliación,
-- constancia de afiliación, credencial, nombramiento, aval, oficio
-- de gestión, constancia de trayectoria. Verificable por QR.
CREATE TABLE documentos (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  tipo               ENUM('afiliacion','constancia_afiliacion','credencial','nombramiento',
                          'aval','gestion','trayectoria') NOT NULL,
  folio              VARCHAR(40)      NOT NULL,
  persona_id         BIGINT UNSIGNED  NULL,           -- a quién pertenece
  afiliacion_id      BIGINT UNSIGNED  NULL,
  evento_id          BIGINT UNSIGNED  NULL,
  atleta_id          BIGINT UNSIGNED  NULL,
  nivel              TINYINT UNSIGNED NULL,           -- avales: 1 a 4
  autorizado_por     BIGINT UNSIGNED  NULL,
  firmado_por        BIGINT UNSIGNED  NULL,           -- solo nivel 4: presidente
  pdf_url            VARCHAR(500)     NULL,
  verificacion_token CHAR(32)         NOT NULL,
  version            SMALLINT UNSIGNED NOT NULL DEFAULT 1,   -- reexpediciones conservan el folio
  reemplaza_id       BIGINT UNSIGNED  NULL,
  anulado            TINYINT(1)       NOT NULL DEFAULT 0,
  generado_at        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_docs_token (verificacion_token),
  KEY ix_docs_folio (folio),
  KEY ix_docs_persona (persona_id),
  KEY ix_docs_evento (evento_id),
  CONSTRAINT fk_docs_persona  FOREIGN KEY (persona_id) REFERENCES personas (id),
  CONSTRAINT fk_docs_afil     FOREIGN KEY (afiliacion_id) REFERENCES afiliaciones (id),
  CONSTRAINT fk_docs_evento   FOREIGN KEY (evento_id) REFERENCES eventos (id),
  CONSTRAINT fk_docs_autoriza FOREIGN KEY (autorizado_por) REFERENCES personas (id),
  CONSTRAINT fk_docs_firma    FOREIGN KEY (firmado_por) REFERENCES personas (id),
  CONSTRAINT fk_docs_reemplaza FOREIGN KEY (reemplaza_id) REFERENCES documentos (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Constancia permanente de cada aprobación o rechazo: quién, cuándo
-- y con qué rol. Solo se inserta, nunca se edita.
CREATE TABLE autorizaciones (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  entidad            VARCHAR(40)      NOT NULL,       -- 'afiliacion', 'evento', 'reconocimiento', 'foto', 'pago'…
  entidad_id         BIGINT UNSIGNED  NOT NULL,
  accion             VARCHAR(40)      NOT NULL,       -- 'autorizar', 'rechazar', 'cerrar', 'prorrogar'…
  persona_id         BIGINT UNSIGNED  NOT NULL,
  rol_usado          VARCHAR(20)      NOT NULL,
  comentario         TEXT             NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_aut_entidad (entidad, entidad_id),
  KEY ix_aut_persona (persona_id, created_at),
  CONSTRAINT fk_aut_persona FOREIGN KEY (persona_id) REFERENCES personas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
--  6. GALERÍA Y MENSAJES
-- ============================================================

CREATE TABLE fotos (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  autor_id           BIGINT UNSIGNED  NOT NULL,
  evento_id          BIGINT UNSIGNED  NULL,
  estado_id          TINYINT UNSIGNED NOT NULL,       -- decide qué mesa estatal la modera
  archivo_url        VARCHAR(500)     NOT NULL,
  miniatura_url      VARCHAR(500)     NULL,
  descripcion        VARCHAR(255)     NULL,
  estatus            ENUM('pendiente','aprobada','rechazada','oculta') NOT NULL DEFAULT 'pendiente',
  moderada_por       BIGINT UNSIGNED  NULL,
  moderada_at        DATETIME         NULL,
  motivo_rechazo     VARCHAR(255)     NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_fotos_moderacion (estado_id, estatus),
  KEY ix_fotos_evento (evento_id, estatus),
  CONSTRAINT fk_fotos_autor  FOREIGN KEY (autor_id) REFERENCES personas (id),
  CONSTRAINT fk_fotos_evento FOREIGN KEY (evento_id) REFERENCES eventos (id),
  CONSTRAINT fk_fotos_estado FOREIGN KEY (estado_id) REFERENCES estados (id),
  CONSTRAINT fk_fotos_modera FOREIGN KEY (moderada_por) REFERENCES personas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Buzón: conversaciones tipo correo. Nadie ve el correo ni el
-- teléfono del otro; el visitante sin cuenta deja su correo, que
-- solo usa el servidor para avisarle de respuestas.
CREATE TABLE conversaciones (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  tipo               ENUM('visitante_escuela','delegado_profesor','profesor_mesa','interna') NOT NULL,
  escuela_id         BIGINT UNSIGNED  NULL,
  asunto             VARCHAR(200)     NOT NULL,
  visitante_nombre   VARCHAR(150)     NULL,
  visitante_correo   VARCHAR(150)     NULL,           -- PRIVADO
  estatus            ENUM('abierta','cerrada','reportada','bloqueada') NOT NULL DEFAULT 'abierta',
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_conv_escuela (escuela_id),
  CONSTRAINT fk_conv_escuela FOREIGN KEY (escuela_id) REFERENCES escuelas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE conversacion_participantes (
  conversacion_id    BIGINT UNSIGNED  NOT NULL,
  persona_id         BIGINT UNSIGNED  NOT NULL,
  ultimo_leido_at    DATETIME         NULL,
  PRIMARY KEY (conversacion_id, persona_id),
  KEY ix_part_persona (persona_id),
  CONSTRAINT fk_part_conv    FOREIGN KEY (conversacion_id) REFERENCES conversaciones (id),
  CONSTRAINT fk_part_persona FOREIGN KEY (persona_id) REFERENCES personas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE mensajes (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  conversacion_id    BIGINT UNSIGNED  NOT NULL,
  autor_id           BIGINT UNSIGNED  NULL,           -- NULL = lo escribió el visitante sin cuenta
  cuerpo             TEXT             NOT NULL,
  ip                 VARCHAR(45)      NULL,           -- para el límite de envíos y antispam
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_msg_conv (conversacion_id, created_at),
  CONSTRAINT fk_msg_conv  FOREIGN KEY (conversacion_id) REFERENCES conversaciones (id),
  CONSTRAINT fk_msg_autor FOREIGN KEY (autor_id) REFERENCES personas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE reportes_conversacion (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  conversacion_id    BIGINT UNSIGNED  NOT NULL,
  reportado_por      BIGINT UNSIGNED  NULL,
  motivo             TEXT             NOT NULL,
  estatus            ENUM('pendiente','revisado','sin_accion','bloqueo') NOT NULL DEFAULT 'pendiente',
  revisado_por       BIGINT UNSIGNED  NULL,
  revisado_at        DATETIME         NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_rep_estatus (estatus),
  CONSTRAINT fk_rep_conv     FOREIGN KEY (conversacion_id) REFERENCES conversaciones (id),
  CONSTRAINT fk_rep_reporta  FOREIGN KEY (reportado_por) REFERENCES personas (id),
  CONSTRAINT fk_rep_revisa   FOREIGN KEY (revisado_por) REFERENCES personas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE bloqueos (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  persona_id         BIGINT UNSIGNED  NULL,           -- remitente con cuenta
  correo             VARCHAR(150)     NULL,           -- visitante sin cuenta
  ip                 VARCHAR(45)      NULL,
  motivo             VARCHAR(255)     NOT NULL,
  hasta              DATETIME         NULL,           -- NULL = permanente
  bloqueado_por      BIGINT UNSIGNED  NOT NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_bloq_persona (persona_id),
  KEY ix_bloq_correo (correo),
  CONSTRAINT fk_bloq_persona FOREIGN KEY (persona_id) REFERENCES personas (id),
  CONSTRAINT fk_bloq_por     FOREIGN KEY (bloqueado_por) REFERENCES personas (id),
  CONSTRAINT ck_bloq_quien   CHECK (persona_id IS NOT NULL OR correo IS NOT NULL OR ip IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
--  7. ATLETAS (BOX FILE)
-- ============================================================

CREATE TABLE atletas (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  nombre_completo    VARCHAR(150)     NOT NULL,
  apodo              VARCHAR(60)      NULL,
  curp               CHAR(18)         NULL,           -- PRIVADA. Evita registros duplicados
  fecha_nacimiento   DATE             NOT NULL,
  sexo               ENUM('H','M')    NOT NULL,
  estado_id          TINYINT UNSIGNED NOT NULL,
  guardia            ENUM('derecha','zurda','ambidiestro') NULL,
  estatura_cm        SMALLINT UNSIGNED NULL,
  inicio_box         DATE             NULL,
  foto_url           VARCHAR(500)     NULL,           -- solo se muestra con responsiva de imagen vigente
  tutor_nombre       VARCHAR(150)     NULL,           -- PRIVADO
  tutor_telefono     VARCHAR(20)      NULL,           -- PRIVADO
  tutor_correo       VARCHAR(150)     NULL,           -- PRIVADO
  registrado_por     BIGINT UNSIGNED  NOT NULL,
  activo             TINYINT(1)       NOT NULL DEFAULT 1,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_atletas_curp (curp),
  KEY ix_atletas_estado (estado_id, activo),
  KEY ix_atletas_nombre (nombre_completo),
  CONSTRAINT fk_atletas_estado   FOREIGN KEY (estado_id) REFERENCES estados (id),
  CONSTRAINT fk_atletas_registra FOREIGN KEY (registrado_por) REFERENCES personas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Historial de formación: el registro oficial de con qué escuela y
-- entrenador estuvo el atleta en cada periodo. Solo se cierra un
-- periodo y se abre otro; nunca se edita. Un solo periodo abierto
-- por atleta (uq_periodo_abierto).
CREATE TABLE atleta_periodos (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  atleta_id          BIGINT UNSIGNED  NOT NULL,
  escuela_id         BIGINT UNSIGNED  NOT NULL,
  entrenador_id      BIGINT UNSIGNED  NOT NULL,
  inicio             DATE             NOT NULL,
  fin                DATE             NULL,
  motivo_fin         VARCHAR(255)     NULL,
  transferencia_id   BIGINT UNSIGNED  NULL,
  registrado_por     BIGINT UNSIGNED  NOT NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  periodo_abierto    BIGINT UNSIGNED GENERATED ALWAYS AS (IF(fin IS NULL, atleta_id, NULL)) STORED,
  PRIMARY KEY (id),
  UNIQUE KEY uq_periodo_abierto (periodo_abierto),
  KEY ix_periodos_atleta (atleta_id, inicio),
  KEY ix_periodos_escuela (escuela_id, fin),
  KEY ix_periodos_entrenador (entrenador_id),
  CONSTRAINT fk_per_atleta     FOREIGN KEY (atleta_id) REFERENCES atletas (id),
  CONSTRAINT fk_per_escuela    FOREIGN KEY (escuela_id) REFERENCES escuelas (id),
  CONSTRAINT fk_per_entrenador FOREIGN KEY (entrenador_id) REFERENCES personas (id),
  CONSTRAINT fk_per_registra   FOREIGN KEY (registrado_por) REFERENCES personas (id),
  CONSTRAINT ck_per_fechas     CHECK (fin IS NULL OR fin >= inicio)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE transferencias (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  atleta_id          BIGINT UNSIGNED  NOT NULL,
  periodo_origen_id  BIGINT UNSIGNED  NOT NULL,
  escuela_destino_id BIGINT UNSIGNED  NOT NULL,
  entrenador_destino_id BIGINT UNSIGNED NOT NULL,
  solicitada_por     BIGINT UNSIGNED  NOT NULL,
  responder_antes    DATE             NOT NULL,
  estatus            ENUM('pendiente','aceptada','disputada','resuelta_origen','resuelta_destino','cancelada')
                                      NOT NULL DEFAULT 'pendiente',
  respuesta_origen   TEXT             NULL,
  resuelta_por       BIGINT UNSIGNED  NULL,           -- delegado si no hubo respuesta; mesa/comisión si hubo disputa
  resolucion         TEXT             NULL,
  resuelta_at        DATETIME         NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_transf_atleta (atleta_id),
  KEY ix_transf_estatus (estatus, responder_antes),
  CONSTRAINT fk_transf_atleta   FOREIGN KEY (atleta_id) REFERENCES atletas (id),
  CONSTRAINT fk_transf_periodo  FOREIGN KEY (periodo_origen_id) REFERENCES atleta_periodos (id),
  CONSTRAINT fk_transf_escuela  FOREIGN KEY (escuela_destino_id) REFERENCES escuelas (id),
  CONSTRAINT fk_transf_entren   FOREIGN KEY (entrenador_destino_id) REFERENCES personas (id),
  CONSTRAINT fk_transf_solicita FOREIGN KEY (solicitada_por) REFERENCES personas (id),
  CONSTRAINT fk_transf_resuelve FOREIGN KEY (resuelta_por) REFERENCES personas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE atleta_periodos
  ADD CONSTRAINT fk_per_transf FOREIGN KEY (transferencia_id) REFERENCES transferencias (id);

CREATE TABLE pesajes (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  atleta_id          BIGINT UNSIGNED  NOT NULL,
  peso_kg            DECIMAL(5,2)     NOT NULL,
  fecha              DATE             NOT NULL,
  oficial            TINYINT(1)       NOT NULL DEFAULT 0,   -- 1 = pesaje de un evento avalado
  evento_id          BIGINT UNSIGNED  NULL,
  registrado_por     BIGINT UNSIGNED  NOT NULL,
  PRIMARY KEY (id),
  KEY ix_pesajes_atleta (atleta_id, fecha),
  CONSTRAINT fk_pesajes_atleta FOREIGN KEY (atleta_id) REFERENCES atletas (id),
  CONSTRAINT fk_pesajes_evento FOREIGN KEY (evento_id) REFERENCES eventos (id),
  CONSTRAINT fk_pesajes_reg    FOREIGN KEY (registrado_por) REFERENCES personas (id),
  CONSTRAINT ck_pesajes_peso   CHECK (peso_kg > 0 AND peso_kg < 250)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE responsivas (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  atleta_id          BIGINT UNSIGNED  NOT NULL,
  tipo               ENUM('participacion','imagen') NOT NULL,   -- imagen incluye foto, video y transmisión
  metodo             ENUM('papel','en_linea') NOT NULL,
  archivo_url        VARCHAR(500)     NULL,           -- papel: foto o escaneo
  firmante_nombre    VARCHAR(150)     NOT NULL,
  firmante_parentesco VARCHAR(40)     NULL,
  firma_url          VARCHAR(500)     NULL,           -- en línea: trazo de la firma
  verificada_por_canal ENUM('sms','whatsapp','correo') NULL,    -- en línea: dónde llegó el código
  ip                 VARCHAR(45)      NULL,
  firmada_at         DATETIME         NOT NULL,
  validada_por       BIGINT UNSIGNED  NULL,           -- papel: quién revisó la foto
  validada_at        DATETIME         NULL,
  vigente_hasta      DATE             NULL,
  revocada_at        DATETIME         NULL,           -- al revocar la de imagen, la foto deja de mostrarse
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_resp_atleta (atleta_id, tipo),
  CONSTRAINT fk_resp_atleta FOREIGN KEY (atleta_id) REFERENCES atletas (id),
  CONSTRAINT fk_resp_valida FOREIGN KEY (validada_por) REFERENCES personas (id),
  CONSTRAINT ck_resp_evidencia CHECK (archivo_url IS NOT NULL OR firma_url IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE certificados_medicos (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  atleta_id          BIGINT UNSIGNED  NOT NULL,
  fecha_expedicion   DATE             NOT NULL,
  vigente_hasta      DATE             NULL,
  medico             VARCHAR(150)     NULL,
  archivo_url        VARCHAR(500)     NOT NULL,
  para_levantar_suspension_id BIGINT UNSIGNED NULL,
  validado_por       BIGINT UNSIGNED  NULL,
  validado_at        DATETIME         NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_cert_atleta (atleta_id, vigente_hasta),
  CONSTRAINT fk_cert_atleta FOREIGN KEY (atleta_id) REFERENCES atletas (id),
  CONSTRAINT fk_cert_valida FOREIGN KEY (validado_por) REFERENCES personas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
--  8. GRAFICADOR, PELEAS, SUSPENSIONES Y SELECCIONES
-- ============================================================

-- Módulo reservado: estas tablas son el mínimo para que el récord,
-- las suspensiones y las selecciones funcionen. El graficador
-- completo (grupos, sorteos, carteleras) se agrega al unificar los
-- sistemas de Guantes en la Piedra y Príncipe Mazahua.
CREATE TABLE torneos (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  evento_id          BIGINT UNSIGNED  NOT NULL,
  nombre             VARCHAR(200)     NOT NULL,
  es_selectivo       TINYINT(1)       NOT NULL DEFAULT 0,
  configuracion      JSON             NULL,           -- tolerancias, divisiones, modo oficial/flexible
  estatus            ENUM('inscripciones','graficado','en_curso','terminado') NOT NULL DEFAULT 'inscripciones',
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_torneos_evento (evento_id),
  CONSTRAINT fk_torneos_evento FOREIGN KEY (evento_id) REFERENCES eventos (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE torneo_inscripciones (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  torneo_id          BIGINT UNSIGNED  NOT NULL,
  atleta_id          BIGINT UNSIGNED  NOT NULL,
  escuela_id         BIGINT UNSIGNED  NOT NULL,       -- con qué escuela se inscribió
  inscrito_por       BIGINT UNSIGNED  NOT NULL,       -- evidencia en disputas por atletas
  division           VARCHAR(60)      NULL,
  peso_kg            DECIMAL(5,2)     NULL,
  estatus            ENUM('inscrito','bloqueado_suspension','baja','pagado') NOT NULL DEFAULT 'inscrito',
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_tinsc (torneo_id, atleta_id),
  CONSTRAINT fk_tinsc_torneo  FOREIGN KEY (torneo_id) REFERENCES torneos (id),
  CONSTRAINT fk_tinsc_atleta  FOREIGN KEY (atleta_id) REFERENCES atletas (id),
  CONSTRAINT fk_tinsc_escuela FOREIGN KEY (escuela_id) REFERENCES escuelas (id),
  CONSTRAINT fk_tinsc_por     FOREIGN KEY (inscrito_por) REFERENCES personas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Peleas en eventos avalados: forman el récord VERIFICADO.
-- Guardan escuela y entrenador de cada esquina en ese momento.
CREATE TABLE peleas (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  evento_id          BIGINT UNSIGNED  NOT NULL,
  torneo_id          BIGINT UNSIGNED  NULL,
  numero             VARCHAR(10)      NULL,           -- G1, EX1… como en la cartelera
  fecha              DATE             NOT NULL,
  division           VARCHAR(60)      NULL,
  rojo_atleta_id     BIGINT UNSIGNED  NOT NULL,
  rojo_escuela_id    BIGINT UNSIGNED  NULL,
  rojo_entrenador_id BIGINT UNSIGNED  NULL,
  azul_atleta_id     BIGINT UNSIGNED  NOT NULL,
  azul_escuela_id    BIGINT UNSIGNED  NULL,
  azul_entrenador_id BIGINT UNSIGNED  NULL,
  ganador            ENUM('rojo','azul','empate','sin_decision') NULL,  -- NULL = aún no se pelea
  decision           ENUM('PTS','KO','RSC','RSC-H','DQ','WO','ABD','NC') NULL,
  round_final        TINYINT UNSIGNED NULL,
  video_inicio_seg   INT UNSIGNED     NULL,           -- marca "inicia pelea" para el clip
  capturada_por      BIGINT UNSIGNED  NULL,
  capturada_at       DATETIME         NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_peleas_rojo (rojo_atleta_id, fecha),
  KEY ix_peleas_azul (azul_atleta_id, fecha),
  KEY ix_peleas_evento (evento_id),
  CONSTRAINT fk_peleas_evento  FOREIGN KEY (evento_id) REFERENCES eventos (id),
  CONSTRAINT fk_peleas_torneo  FOREIGN KEY (torneo_id) REFERENCES torneos (id),
  CONSTRAINT fk_peleas_rojo    FOREIGN KEY (rojo_atleta_id) REFERENCES atletas (id),
  CONSTRAINT fk_peleas_azul    FOREIGN KEY (azul_atleta_id) REFERENCES atletas (id),
  CONSTRAINT fk_peleas_resc    FOREIGN KEY (rojo_escuela_id) REFERENCES escuelas (id),
  CONSTRAINT fk_peleas_aesc    FOREIGN KEY (azul_escuela_id) REFERENCES escuelas (id),
  CONSTRAINT fk_peleas_rent    FOREIGN KEY (rojo_entrenador_id) REFERENCES personas (id),
  CONSTRAINT fk_peleas_aent    FOREIGN KEY (azul_entrenador_id) REFERENCES personas (id),
  CONSTRAINT fk_peleas_captura FOREIGN KEY (capturada_por) REFERENCES personas (id),
  CONSTRAINT ck_peleas_rivales CHECK (rojo_atleta_id <> azul_atleta_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Peleas fuera de AMBA, declaradas por el profesor: récord DECLARADO.
CREATE TABLE peleas_externas (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  atleta_id          BIGINT UNSIGNED  NOT NULL,
  fecha              DATE             NULL,
  evento_texto       VARCHAR(200)     NULL,
  rival_texto        VARCHAR(150)     NULL,
  resultado          ENUM('gano','perdio','empate','sin_decision') NOT NULL,
  decision           ENUM('PTS','KO','RSC','RSC-H','DQ','WO','ABD','NC') NULL,
  evidencia_url      VARCHAR(500)     NULL,
  declarada_por      BIGINT UNSIGNED  NOT NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_pext_atleta (atleta_id, fecha),
  CONSTRAINT fk_pext_atleta  FOREIGN KEY (atleta_id) REFERENCES atletas (id),
  CONSTRAINT fk_pext_declara FOREIGN KEY (declarada_por) REFERENCES personas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Cuándo pidió el profesor por última vez actualizar el récord externo
-- (al inscribir a un torneo y cada 3 meses).
CREATE TABLE actualizaciones_record (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  atleta_id          BIGINT UNSIGNED  NOT NULL,
  confirmado_por     BIGINT UNSIGNED  NOT NULL,
  peleas_nuevas      TINYINT UNSIGNED NOT NULL DEFAULT 0,
  motivo             ENUM('inscripcion_torneo','periodica','manual') NOT NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_actrec_atleta (atleta_id, created_at),
  CONSTRAINT fk_actrec_atleta FOREIGN KEY (atleta_id) REFERENCES atletas (id),
  CONSTRAINT fk_actrec_por    FOREIGN KEY (confirmado_por) REFERENCES personas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabla que define el médico responsable: cuántos días de
-- suspensión por tipo de resultado y antecedentes recientes.
CREATE TABLE suspension_reglas (
  id                 INT UNSIGNED     NOT NULL AUTO_INCREMENT,
  decision           ENUM('KO','RSC-H','RSC') NOT NULL,
  previos_minimos    TINYINT UNSIGNED NOT NULL DEFAULT 0,  -- cuántos KO/RSC-H previos…
  ventana_dias       SMALLINT UNSIGNED NULL,               -- …dentro de esta ventana
  dias_suspension    SMALLINT UNSIGNED NOT NULL,
  descripcion        VARCHAR(255)     NULL,
  activa             TINYINT(1)       NOT NULL DEFAULT 1,
  definida_por       BIGINT UNSIGNED  NULL,
  updated_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT fk_sreg_por FOREIGN KEY (definida_por) REFERENCES personas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE suspensiones (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  atleta_id          BIGINT UNSIGNED  NOT NULL,
  pelea_id           BIGINT UNSIGNED  NULL,
  regla_id           INT UNSIGNED     NULL,
  origen             ENUM('automatica','manual') NOT NULL,
  motivo             VARCHAR(255)     NOT NULL,
  inicio             DATE             NOT NULL,
  fin                DATE             NOT NULL,
  levantada_at       DATETIME         NULL,           -- antes de tiempo, con certificado validado
  levantada_por      BIGINT UNSIGNED  NULL,
  certificado_id     BIGINT UNSIGNED  NULL,
  registrada_por     BIGINT UNSIGNED  NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_susp_atleta (atleta_id, fin),
  CONSTRAINT fk_susp_atleta  FOREIGN KEY (atleta_id) REFERENCES atletas (id),
  CONSTRAINT fk_susp_pelea   FOREIGN KEY (pelea_id) REFERENCES peleas (id),
  CONSTRAINT fk_susp_regla   FOREIGN KEY (regla_id) REFERENCES suspension_reglas (id),
  CONSTRAINT fk_susp_levanta FOREIGN KEY (levantada_por) REFERENCES personas (id),
  CONSTRAINT fk_susp_cert    FOREIGN KEY (certificado_id) REFERENCES certificados_medicos (id),
  CONSTRAINT fk_susp_registra FOREIGN KEY (registrada_por) REFERENCES personas (id),
  CONSTRAINT ck_susp_fechas  CHECK (fin >= inicio)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE certificados_medicos
  ADD CONSTRAINT fk_cert_suspension FOREIGN KEY (para_levantar_suspension_id) REFERENCES suspensiones (id);

CREATE TABLE selecciones (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  estado_id          TINYINT UNSIGNED NOT NULL,
  anio               SMALLINT UNSIGNED NOT NULL,
  nombre             VARCHAR(150)     NOT NULL,       -- "Selección Estado de México 2027 — Juvenil"
  torneo_selectivo_id BIGINT UNSIGNED NULL,
  publicada          TINYINT(1)       NOT NULL DEFAULT 0,   -- visible en la visoría
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_sel_estado (estado_id, anio),
  CONSTRAINT fk_sel_estado  FOREIGN KEY (estado_id) REFERENCES estados (id),
  CONSTRAINT fk_sel_torneo  FOREIGN KEY (torneo_selectivo_id) REFERENCES torneos (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Las filas con es_original = 1 son la foto del selectivo y NO se
-- modifican. Una sustitución agrega una fila nueva que apunta a la
-- que reemplaza, con motivo, quién y cuándo.
CREATE TABLE seleccion_miembros (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  seleccion_id       BIGINT UNSIGNED  NOT NULL,
  division           VARCHAR(60)      NOT NULL,
  atleta_id          BIGINT UNSIGNED  NOT NULL,
  origen             ENUM('selectivo','manual') NOT NULL,
  es_original        TINYINT(1)       NOT NULL DEFAULT 0,
  activo             TINYINT(1)       NOT NULL DEFAULT 1,
  sustituye_a_id     BIGINT UNSIGNED  NULL,
  motivo             VARCHAR(255)     NULL,
  registrado_por     BIGINT UNSIGNED  NOT NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_selm_sel (seleccion_id, activo),
  CONSTRAINT fk_selm_sel      FOREIGN KEY (seleccion_id) REFERENCES selecciones (id),
  CONSTRAINT fk_selm_atleta   FOREIGN KEY (atleta_id) REFERENCES atletas (id),
  CONSTRAINT fk_selm_sustituye FOREIGN KEY (sustituye_a_id) REFERENCES seleccion_miembros (id),
  CONSTRAINT fk_selm_reg      FOREIGN KEY (registrado_por) REFERENCES personas (id),
  CONSTRAINT ck_selm_motivo   CHECK (sustituye_a_id IS NULL OR motivo IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Campeones históricos (los de la página de Campeones actual) y los
-- nuevos que salgan del graficador. atleta_id puede ir vacío para
-- campeones de años anteriores que no tengan ficha.
CREATE TABLE campeonatos (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  torneo_nombre      VARCHAR(200)     NOT NULL,
  anio               SMALLINT UNSIGNED NOT NULL,
  torneo_id          BIGINT UNSIGNED  NULL,
  atleta_id          BIGINT UNSIGNED  NULL,
  nombre_texto       VARCHAR(150)     NOT NULL,
  apodo_texto        VARCHAR(60)      NULL,
  escuela_texto      VARCHAR(150)     NULL,
  municipio_texto    VARCHAR(100)     NULL,
  estado_texto       VARCHAR(60)      NULL,
  rama               VARCHAR(20)      NULL,
  categoria          VARCHAR(60)      NULL,
  division           VARCHAR(60)      NULL,
  nivel              VARCHAR(40)      NULL,
  resena             TEXT             NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_camp_torneo (anio, torneo_nombre),
  KEY ix_camp_atleta (atleta_id),
  CONSTRAINT fk_camp_torneo FOREIGN KEY (torneo_id) REFERENCES torneos (id),
  CONSTRAINT fk_camp_atleta FOREIGN KEY (atleta_id) REFERENCES atletas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
--  9. BITÁCORA
-- ============================================================

-- Quién cambió qué y cuándo. Solo se inserta.
CREATE TABLE bitacora (
  id                 BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  persona_id         BIGINT UNSIGNED  NULL,           -- NULL = proceso automático o cliente de la API
  api_cliente_id     INT UNSIGNED     NULL,
  accion             VARCHAR(60)      NOT NULL,
  entidad            VARCHAR(40)      NOT NULL,
  entidad_id         BIGINT UNSIGNED  NULL,
  antes              JSON             NULL,
  despues            JSON             NULL,
  ip                 VARCHAR(45)      NULL,
  created_at         DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_bit_entidad (entidad, entidad_id),
  KEY ix_bit_persona (persona_id, created_at),
  KEY ix_bit_fecha (created_at),
  CONSTRAINT fk_bit_persona FOREIGN KEY (persona_id) REFERENCES personas (id),
  CONSTRAINT fk_bit_api     FOREIGN KEY (api_cliente_id) REFERENCES api_clientes (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE configuracion
  ADD CONSTRAINT fk_config_por FOREIGN KEY (actualizado_por) REFERENCES personas (id);

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================
--  10. VISTAS
-- ============================================================

-- Récord VERIFICADO de cada atleta (peleas en eventos avalados).
CREATE OR REPLACE VIEW v_record_amba AS
SELECT a.id AS atleta_id,
       COUNT(p.id)                                                         AS peleas,
       SUM(CASE WHEN (p.ganador = 'rojo' AND p.rojo_atleta_id = a.id)
                  OR (p.ganador = 'azul' AND p.azul_atleta_id = a.id) THEN 1 ELSE 0 END) AS ganadas,
       SUM(CASE WHEN (p.ganador = 'azul' AND p.rojo_atleta_id = a.id)
                  OR (p.ganador = 'rojo' AND p.azul_atleta_id = a.id) THEN 1 ELSE 0 END) AS perdidas,
       SUM(CASE WHEN p.ganador = 'empate' THEN 1 ELSE 0 END)               AS empates,
       SUM(CASE WHEN p.decision IN ('KO','RSC','RSC-H')
                 AND ((p.ganador = 'rojo' AND p.rojo_atleta_id = a.id)
                   OR (p.ganador = 'azul' AND p.azul_atleta_id = a.id)) THEN 1 ELSE 0 END) AS ganadas_ko
FROM atletas a
LEFT JOIN peleas p
       ON (p.rojo_atleta_id = a.id OR p.azul_atleta_id = a.id)
      AND p.ganador IS NOT NULL
GROUP BY a.id;

-- Récord DECLARADO (fuera de AMBA).
CREATE OR REPLACE VIEW v_record_externo AS
SELECT atleta_id,
       COUNT(*)                                             AS peleas,
       SUM(resultado = 'gano')                              AS ganadas,
       SUM(resultado = 'perdio')                            AS perdidas,
       SUM(resultado = 'empate')                            AS empates
FROM peleas_externas
GROUP BY atleta_id;

-- Suspensiones que hoy impiden pelear.
CREATE OR REPLACE VIEW v_suspensiones_activas AS
SELECT s.*
FROM suspensiones s
WHERE s.levantada_at IS NULL
  AND CURRENT_DATE BETWEEN s.inicio AND s.fin;

-- Estadística base: afiliaciones por año y mes de registro.
CREATE OR REPLACE VIEW v_afiliaciones_por_mes AS
SELECT anio,
       MONTH(fecha_registro)                                AS mes,
       SUM(origen IN ('form_afiliacion','manual','migracion')) AS nuevas,
       SUM(origen IN ('form_renovacion','panel_renovacion'))   AS renovaciones,
       COUNT(*)                                             AS total
FROM afiliaciones
WHERE estatus NOT IN ('rechazada','duplicada')
GROUP BY anio, MONTH(fecha_registro);

-- Antigüedad: en cuántos años distintos ha estado afiliada cada persona.
CREATE OR REPLACE VIEW v_antiguedad AS
SELECT persona_id,
       MIN(anio)                                            AS primer_anio,
       MAX(anio)                                            AS ultimo_anio,
       COUNT(DISTINCT anio)                                 AS anios_afiliado
FROM afiliaciones
WHERE estatus NOT IN ('pendiente','rechazada','duplicada')
GROUP BY persona_id;

-- ============================================================
--  11. OPCIONAL — BLINDAJE DE CONSTANCIAS
--  Impide modificar o borrar constancias incluso desde phpMyAdmin.
--  Algunos hostings compartidos no permiten crear triggers; si
--  IONOS lo rechaza, no pasa nada: la API igual nunca las modifica.
-- ============================================================
-- DELIMITER //
-- CREATE TRIGGER tr_constancias_no_update BEFORE UPDATE ON constancias
-- FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Las constancias no se modifican';
-- //
-- CREATE TRIGGER tr_constancias_no_delete BEFORE DELETE ON constancias
-- FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Las constancias no se borran';
-- //
-- DELIMITER ;

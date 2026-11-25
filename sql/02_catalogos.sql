-- ============================================================
--  AMBA 2.0 — Catálogos y configuración inicial
--  Archivo: 02_catalogos.sql  (cargar después de 01_esquema.sql)
-- ============================================================

SET NAMES utf8mb4;

-- Estados: id = clave INEGI; clave = la de la CURP (posiciones 12–13),
-- así el estado se puede sugerir directo de la CURP.
INSERT INTO estados (id, clave, nombre) VALUES
 ( 1,'AS','Aguascalientes'),        ( 2,'BC','Baja California'),
 ( 3,'BS','Baja California Sur'),   ( 4,'CC','Campeche'),
 ( 5,'CL','Coahuila'),              ( 6,'CM','Colima'),
 ( 7,'CS','Chiapas'),               ( 8,'CH','Chihuahua'),
 ( 9,'DF','Ciudad de México'),      (10,'DG','Durango'),
 (11,'GT','Guanajuato'),            (12,'GR','Guerrero'),
 (13,'HG','Hidalgo'),               (14,'JC','Jalisco'),
 (15,'MC','Estado de México'),      (16,'MN','Michoacán'),
 (17,'MS','Morelos'),               (18,'NT','Nayarit'),
 (19,'NL','Nuevo León'),            (20,'OC','Oaxaca'),
 (21,'PL','Puebla'),                (22,'QT','Querétaro'),
 (23,'QR','Quintana Roo'),          (24,'SP','San Luis Potosí'),
 (25,'SL','Sinaloa'),               (26,'SR','Sonora'),
 (27,'TC','Tabasco'),               (28,'TS','Tamaulipas'),
 (29,'TL','Tlaxcala'),              (30,'VZ','Veracruz'),
 (31,'YN','Yucatán'),               (32,'ZS','Zacatecas'),
 (99,'NE','Extranjero');

-- Configuración ajustable sin tocar código.
INSERT INTO configuracion (clave, valor, descripcion, solo_sistemas) VALUES
 ('folio.formato',
  '"AMBA-{AA}{AMBITO}-{SERIE}{NUM3}"',
  'Formato fijo de folios. {AA}=año a 2 dígitos, {AMBITO}=NAL o estado, {NUM3}=consecutivo a 3 dígitos', 1),
 ('afiliacion.anio_actual', '2026', 'Año de afiliación en curso', 1),
 ('afiliacion.tipos',
  '{"A":{"cursos_min":5,"grado":"Entrenador Master"},"B":{"cursos_min":4,"grado":"Entrenador"},"C":{"cursos_min":0,"grado":"Instructor"}}',
  'Tipo y grado de credencial según cursos válidos', 1),
 ('expediente.plazos',
  '{"recordatorio_dias":7,"vence_dias":14,"prorroga_max_dias":21}',
  'Días después del evento: recordatorio, vencimiento y tope de prórroga', 0),
 ('expediente.candado', 'true', 'Con un expediente vencido sin cerrar no se pueden pedir avales nuevos', 0),
 ('transferencia.dias_respuesta', '7', 'Días que tiene el profesor anterior para aceptar o disputar un cambio de escuela', 0),
 ('record.actualizacion_dias', '90', 'Cada cuántos días se pide al profesor actualizar el récord externo', 0),
 ('cursos.umbral_aprobacion', '80', 'Calificación mínima por defecto para aprobar un curso de AMBA Core', 0),
 ('cuentas.intentos_max', '5', 'Intentos fallidos de contraseña antes de bloquear 15 minutos', 1);

-- Los 5 cursos requisito vigentes en 2026.
INSERT INTO cursos (clave, nombre, tipo) VALUES
 ('REQ-CIENCIAS',   'Ciencias del Deporte',                                'requisito'),
 ('REQ-METODOLOGIA','Metodología del Boxeo',                               'requisito'),
 ('REQ-PEDAGOGIA',  'Pedagogía Integral en el Deporte',                    'requisito'),
 ('REQ-URGENCIAS',  'Urgencias Médicas en el Boxeo',                       'requisito'),
 ('REQ-MATEMATICAS','Matemáticas y Unidades de Medición para el Deporte',  'requisito');

INSERT INTO requisitos_anuales (anio, curso_id, orden)
SELECT 2026, id, CASE clave
                   WHEN 'REQ-CIENCIAS'    THEN 1
                   WHEN 'REQ-METODOLOGIA' THEN 2
                   WHEN 'REQ-PEDAGOGIA'   THEN 3
                   WHEN 'REQ-URGENCIAS'   THEN 4
                   WHEN 'REQ-MATEMATICAS' THEN 5
                 END
FROM cursos WHERE tipo = 'requisito';

-- suspension_reglas se deja VACÍA a propósito: los días de cada caso
-- los define el médico responsable de AMBA.

-- ============================================================
--  AMBA 2.0 — Corrección: emisión anticipada con folio 2026
--  Archivo: 07_corregir_emision_anticipada.sql  (UNA sola vez, nov 2026)
--
--  La prueba del 25 de noviembre se emitió con folio AMBA-26NAL-AFI001 y
--  vigencia 2026 porque la campaña 2027 (sql/06) no había quedado aplicada.
--  Este archivo borra esa emisión y vuelve a aplicar la campaña 2027.
--  Los cursos validados de la persona se conservan.
--
--  ANTES de importar: en phpMyAdmin selecciona la base de AMBA 2.0 en la
--  columna izquierda (la nueva, no la de la página vieja).
-- ============================================================

-- 1. Borrar la afiliación 2026 emitida por error y sus documentos.
--    (La base nueva todavía no tiene datos 2026 reales: los de 2026 se
--    migrarán después con su propio script.)
DELETE FROM documentos
 WHERE afiliacion_id IN (SELECT id FROM afiliaciones WHERE anio = 2026);
DELETE FROM afiliaciones WHERE anio = 2026;
DELETE FROM folio_contadores WHERE anio = 2026;

-- 2. Campaña 2027 (lo mismo que sql/06).
UPDATE configuracion SET valor = '2027' WHERE clave = 'afiliacion.anio_actual';

INSERT INTO configuracion (clave, valor, descripcion, solo_sistemas) VALUES
 ('afiliacion.emision_desde', '"2027-01-01"',
  'Antes de esta fecha no se asignan folios ni se emiten documentos (AAAA-MM-DD)', 1)
ON DUPLICATE KEY UPDATE valor = VALUES(valor);

INSERT IGNORE INTO requisitos_anuales (anio, curso_id, orden)
SELECT 2027, curso_id, orden FROM requisitos_anuales WHERE anio = 2026;

-- 3. Comprobación: debe mostrar anio_actual = 2027 y emision_desde = "2027-01-01",
--    y ninguna afiliación (la fila se vuelve a registrar desde la Sheet).
SELECT clave, valor FROM configuracion WHERE clave LIKE 'afiliacion.%';
SELECT id, anio, folio, estatus FROM afiliaciones;

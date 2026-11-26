-- ============================================================
--  AMBA 2.0 — Abrir la campaña 2027 con emisión a partir del 1 de enero
--  Archivo: 06_campana_2027.sql  (cargar después de 05)
--
--  - Las solicitudes que lleguen desde hoy son de 2027.
--  - Antes del 1 de enero NO se asignan folios ni se generan documentos:
--    las renovaciones quedan "en espera" y las afiliaciones se pueden
--    autorizar, pero la API no las aprueba hasta esa fecha.
--  - Ese día se aprueban en el orden en que llegaron.
--  Para cambiar la fecha: UPDATE configuracion SET valor='"2027-01-05"'
--  WHERE clave='afiliacion.emision_desde';
-- ============================================================

UPDATE configuracion SET valor = '2027' WHERE clave = 'afiliacion.anio_actual';

INSERT INTO configuracion (clave, valor, descripcion, solo_sistemas) VALUES
 ('afiliacion.emision_desde', '"2027-01-01"',
  'Antes de esta fecha no se asignan folios ni se emiten documentos (AAAA-MM-DD)', 1)
ON DUPLICATE KEY UPDATE valor = VALUES(valor);

-- Los 5 cursos requisito de 2027: por ahora los mismos de 2026.
-- Si la mesa decide otros, cambiar ANTES del 1 de enero.
INSERT IGNORE INTO requisitos_anuales (anio, curso_id, orden)
SELECT 2027, curso_id, orden FROM requisitos_anuales WHERE anio = 2026;

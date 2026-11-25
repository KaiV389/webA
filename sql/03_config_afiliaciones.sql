-- ============================================================
--  AMBA 2.0 — Configuración de afiliaciones
--  Archivo: 03_config_afiliaciones.sql  (cargar después de 02_catalogos.sql)
--  Se puede volver a cargar sin duplicar nada.
-- ============================================================

SET NAMES utf8mb4;

-- Vigencia de la credencial por tipo, como "MM-DD" del año de afiliación.
-- Valores tomados de la regla 2026: Master (5 cursos) hasta diciembre;
-- Entrenador e Instructor hasta junio. AJUSTAR para 2027 si la mesa decide otra cosa.
INSERT INTO configuracion (clave, valor, descripcion, solo_sistemas) VALUES
 ('afiliacion.vigencias', '{"A":"12-31","B":"06-30","C":"06-30"}',
  'Vigencia de la credencial por tipo (MM-DD del año de afiliación)', 1)
ON DUPLICATE KEY UPDATE clave = clave;

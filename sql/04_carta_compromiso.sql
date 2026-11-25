-- ============================================================
--  AMBA 2.0 — Carta de declaración de responsabilidad y compromiso
--  Archivo: 04_carta_compromiso.sql  (cargar después de 03)
--  Se puede volver a cargar sin duplicar nada (MariaDB).
-- ============================================================

SET NAMES utf8mb4;

-- Liga a la carta firmada que el profesor sube en el Form
ALTER TABLE afiliaciones
  ADD COLUMN IF NOT EXISTS carta_compromiso_url VARCHAR(500) NULL AFTER datos_form;

-- Candados: sin carta no se aprueba la afiliación; en renovaciones,
-- sin carta queda "en revisión" en lugar de aprobarse en el acto.
INSERT INTO configuracion (clave, valor, descripcion, solo_sistemas) VALUES
 ('afiliacion.requiere_carta', 'true', 'Sin carta de compromiso no se aprueba una afiliación nueva', 1),
 ('renovacion.requiere_carta', 'true', 'Sin carta de compromiso la renovación queda en revisión', 1)
ON DUPLICATE KEY UPDATE clave = clave;

-- ============================================================
--  AMBA 2.0 — La renovación ANUAL también pide la carta de compromiso
--  Archivo: 05_renovacion_anual_con_carta.sql  (cargar después de 04)
--
--  Regla (nov 2026): la renovación de un año al siguiente (2026 → 2027)
--  pide la carta firmada, igual que una afiliación nueva. La renovación
--  de MEDIO AÑO (extender la vigencia dentro del mismo año, para quienes
--  no tuvieron afiliación de año completo) NO la pide; ese trámite es
--  distinto y se agregará aparte.
-- ============================================================

UPDATE configuracion
   SET valor = 'true',
       descripcion = 'Renovación anual: sin carta de compromiso queda en revisión'
 WHERE clave = 'renovacion.requiere_carta';

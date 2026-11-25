# -*- coding: utf-8 -*-
"""
Crea un token para un cliente de la API SIN necesitar SSH.

    py herramientas/crear_token.py

1. Te pregunta el nombre del cliente y qué permisos lleva.
2. Muestra el TOKEN (cópialo: no se vuelve a mostrar) y una instrucción SQL.
3. Pega la instrucción SQL en phpMyAdmin (base AMBA2.0 → pestaña SQL → Continuar).
4. Guarda el token en Apps Script: Configuración del proyecto → Propiedades del script.

En la base solo queda el hash del token; si se pierde, se crea otro y se
desactiva el anterior (UPDATE api_clientes SET activo = 0 WHERE id = …).
"""
import hashlib
import json
import secrets

PERMISOS = {
    "1": ("afiliaciones.registrar", "Registrar solicitudes del Form de afiliación"),
    "2": ("afiliaciones.aprobar",   "Ver pendientes y aprobar"),
    "3": ("afiliaciones.renovar",   "Renovaciones del Form de renovación"),
    "4": ("documentos.registrar",   "Guardar la liga de los PDF generados"),
}

nombre = input("Nombre del cliente (ej. Apps Script afiliaciones): ").strip() or "Apps Script afiliaciones"
print()
for clave, (permiso, desc) in PERMISOS.items():
    print(f"  {clave}. {permiso:<24} {desc}")
elegidos = input("\nPermisos (números separados por coma; Enter = todos): ").strip()
claves = [c.strip() for c in elegidos.split(",") if c.strip()] or list(PERMISOS)
permisos = [PERMISOS[c][0] for c in claves if c in PERMISOS]

token = secrets.token_hex(32)
huella = hashlib.sha256(token.encode()).hexdigest()
nombre_sql = nombre.replace("'", "''")

print("\n" + "=" * 70)
print("TOKEN (cópialo ahora, no se vuelve a mostrar):\n")
print(token)
print("\n" + "=" * 70)
print("SQL para phpMyAdmin (base AMBA2.0 → pestaña SQL):\n")
print(f"INSERT INTO api_clientes (nombre, token_hash, permisos) "
      f"VALUES ('{nombre_sql}', '{huella}', '{json.dumps(permisos)}');")
print("=" * 70)
input("\nEnter para cerrar…")

# AMBA 2.0 — Plataforma de la Asociación Mexiquense de Boxeo Amateur

Sitio público, cuentas, afiliaciones, galería, cursos (AMBA Core), eventos y avales,
y más adelante el graficador y el Box File. Diseño completo: documento
"AMBA 2.0 — Diseño de la plataforma".

## Estructura

```
public/          Lo ÚNICO visible desde internet (index.php, css, imágenes)
app/
  bootstrap.php  Arranque: configuración, autoload y manejo de errores
  Rutas.php      Todas las rutas del sitio
  Core/          Base de datos, enrutador, respuestas
  Controladores/ Lógica de cada página o endpoint
  Vistas/        Plantillas HTML
config/          config.php con las credenciales (NO se sube a GitHub)
sql/             Esquema y catálogos de la base de datos
storage/logs/    Errores del sitio (no se sube a GitHub)
herramientas/    Scripts auxiliares (generador de responsivas)
```

## Rutas actuales

| Ruta | Qué hace |
|---|---|
| `/` | Inicio (provisional) |
| `/verificar/{codigo}` | Verificación por QR de credenciales, constancias, avales y nombramientos. **Dirección permanente: no se cambia nunca.** |
| `/api/salud` | Estado del sitio y de la base de datos, para el monitor de disponibilidad |

## Poner en marcha en IONOS

1. **Base de datos:** crear una base nueva en el panel y cargar, en este orden,
   `sql/01_esquema.sql` y `sql/02_catalogos.sql` (phpMyAdmin → Importar).
2. **Configuración:** copiar `config/config.example.php` como `config/config.php`
   y llenar los datos de la base y del correo. Ese archivo se sube por SFTP, nunca a GitHub.
3. **Archivos:** subir todo el proyecto por SFTP (WinSCP).
4. **Carpeta del dominio:** en el panel de IONOS (Dominios → destino del dominio o
   subdominio) apuntar a la carpeta `public/` del proyecto. Si no se puede, el
   `.htaccess` de la raíz redirige todo a `public/` y bloquea las demás carpetas.
5. **Probar:** abrir `/api/salud`; debe responder `"ok": true`.

Requiere PHP 8.1 o superior y MySQL 8.

## Probar en tu computadora

Con PHP instalado y una base MySQL local:

```
copy config\config.example.php config\config.php   (y llénalo con tu base local)
php -S localhost:8080 -t public public/index.php
```

Abrir http://localhost:8080/api/salud

## Reglas del proyecto

- Toda consulta a la base usa sentencias preparadas (`Db::uno`, `Db::todos`, `Db::ejecutar`).
- Todo dato impreso en una vista pasa por `e()`.
- Las credenciales viven solo en `config/config.php`.
- No se cambia código en producción la semana de un evento.

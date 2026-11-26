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
herramientas/    Scripts auxiliares (responsivas, carta, tokens, Apps Script del Form 2027)
```

## Rutas actuales

| Ruta | Qué hace |
|---|---|
| `/` | Inicio (provisional) |
| `/verificar/{codigo}` | Verificación por QR de credenciales, constancias, avales y nombramientos. **Dirección permanente: no se cambia nunca.** |
| `/api/salud` | Estado del sitio y de la base de datos, para el monitor de disponibilidad |

## API de afiliaciones

La usan los Apps Script de los Forms. Cada cliente se autentica con
`Authorization: Bearer <token>`; los tokens se crean con
`php herramientas/crear_cliente_api.php "Nombre" permiso1 permiso2…`
y se guardan en las Propiedades del script, nunca en el código.

| Método y ruta | Permiso | Qué hace |
|---|---|---|
| `POST /api/afiliaciones` | `afiliaciones.registrar` | Registra la solicitud del Form de afiliación; queda pendiente (con alerta si hay veto). Guarda como pendientes los reconocimientos de cursos (`reconocimientos`: curso + liga). Un doble envío devuelve el registro existente. |
| `GET /api/afiliaciones/pendientes` | `afiliaciones.aprobar` | Bandeja de solicitudes por aprobar |
| `POST /api/afiliaciones/{id}/aprobar` | `afiliaciones.aprobar` | Con `cursos_validados` (los que Kai validó) los registra como válidos. Asigna el folio del año, tipo, grado y vigencia, y crea los 3 documentos (AFL, CON, CRE) con su liga de verificación para el QR. Repetirlo devuelve lo mismo. |
| `POST /api/afiliaciones/{id}/carta` | `afiliaciones.aprobar` | Agrega la carta de compromiso a una solicitud que llegó sin ella |
| `POST /api/renovaciones` | `afiliaciones.renovar` | Renueva con el folio del año anterior, tolerando errores de captura (`AF1049`, `AFL49`, folio de la credencial o constancia). Sin alertas se aprueba en el acto con folio nuevo. |
| `POST /api/documentos/{token}/pdf` | `documentos.registrar` | Guarda la liga del PDF ya generado |

**Fecha de emisión:** con `afiliacion.emision_desde` (por ejemplo `"2027-01-01"`)
las solicitudes se reciben antes, pero no se asignan folios ni se emiten
documentos hasta esa fecha: las renovaciones responden `en_espera` y aprobar
responde 409. Ese día se aprueban en el orden en que llegaron
(`sql/06_campana_2027.sql`).

**Carta de compromiso:** el Form manda `carta_compromiso_url` con la liga de la carta firmada.
Sin ella una afiliación nueva no se aprueba y una renovación anual queda en
revisión (`afiliacion.requiere_carta` y `renovacion.requiere_carta`). La
renovación de medio año (extender vigencia dentro del mismo año) no la pide.
La carta en blanco se descarga de `/docs/carta-compromiso.pdf` y se genera con
`herramientas/carta_compromiso/generar_carta.py`.

Los folios los asigna la base dentro de una transacción: dos solicitudes
simultáneas nunca reciben el mismo número ni se salta ninguno.

**Apps Script del Form 2027:** `herramientas/apps_script/Orquestador2027.gs` va
en la Sheet de respuestas. Registra cada respuesta en la API al instante, avisa
al profe que sus documentos llegan a partir de la fecha de emisión, y cada 10
minutos emite (en orden de llegada) las renovaciones en espera y las afiliaciones
que Kai autorizó: PDFs con el servicio de 2026, carpeta en Drive, correo y liga
de WhatsApp. Las claves van en Propiedades del script.

**Migración 2026:** `herramientas/apps_script/Migracion2026.gs` va en la Sheet
de 2026 y manda la pestaña A2026 (folio, persona, escuela, cursos validados) y
Vetados a `POST /api/migracion/afiliaciones` y `/api/migracion/vetos`. Es
idempotente; no genera documentos.

**Configuración** (tabla `configuracion`): `afiliacion.anio_actual` (cambiarlo a
2027 al abrir la campaña), `afiliacion.tipos` y `afiliacion.vigencias`. Los 5
cursos de cada año van en `requisitos_anuales`.

**Pruebas:** `tests/prueba_api.sh` recorre todos los casos contra una base de
PRUEBA (nunca contra producción).

## Poner en marcha en IONOS

1. **Base de datos:** crear una base nueva en el panel y cargar, en este orden,
   `sql/01_esquema.sql`, `sql/02_catalogos.sql`, `sql/03_config_afiliaciones.sql` `sql/04_carta_compromiso.sql` y
   `sql/05_renovacion_anual_con_carta.sql` y `sql/06_campana_2027.sql`
   (phpMyAdmin → Importar).
2. **Configuración:** copiar `config/config.example.php` como `config/config.php`
   y llenar los datos de la base y del correo. Ese archivo se sube por SFTP, nunca a GitHub.
3. **Archivos:** subir todo el proyecto por SFTP (WinSCP).
4. **Carpeta del dominio:** en el panel de IONOS (Dominios → destino del dominio o
   subdominio) apuntar a la carpeta `public/` del proyecto. Si no se puede, el
   `.htaccess` de la raíz redirige todo a `public/` y bloquea las demás carpetas.
5. **Probar:** abrir `/api/salud`; debe responder `"ok": true`.

Requiere PHP 8.1 o superior y MySQL 8 o MariaDB 10.6+ (producción: PHP 8.5 y MariaDB 11.8 en IONOS).

**Error 500 de Apache al subir:** casi siempre es el `.htaccess`. IONOS no acepta
`Options` y necesita `RewriteBase /`. La redirección a https se activa en el panel.

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

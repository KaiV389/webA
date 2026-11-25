<?php
/**
 * Configuración de AMBA 2.0
 *
 * 1. Copia este archivo como  config/config.php
 * 2. Llena los valores reales.
 * 3. config.php NUNCA se sube a GitHub (está en .gitignore).
 */
return [
    // 'produccion' oculta los errores al público y los manda al log.
    // 'desarrollo' los muestra en pantalla.
    'entorno' => 'produccion',

    // Dirección pública del sitio, sin diagonal final.
    'url_base' => 'https://ambanacional.org',

    'db' => [
        'host'     => 'dbXXXXXXXXXX.hosting-data.io',
        'puerto'   => 3306,
        'nombre'   => 'dbsXXXXXXXX',
        'usuario'  => 'dbuXXXXXXX',
        'password' => 'CONTRASEÑA_AQUI',
    ],

    // Correo para envíos automáticos (SMTP de IONOS).
    'correo' => [
        'host'      => 'smtp.ionos.mx',
        'puerto'    => 587,
        'usuario'   => 'no-responder@ambanacional.org',
        'password'  => 'CONTRASEÑA_AQUI',
        'remitente' => 'AMBA Nacional',
    ],

    // Zona horaria de todo el sistema.
    'zona_horaria' => 'America/Mexico_City',
];

<?php
/** Encabezado común. Variables: $titulo (string), $descripcion (string, opcional) */
$titulo = $titulo ?? 'AMBA Nacional';
$descripcion = $descripcion ?? 'Asociación Mexiquense de Boxeo Amateur: afiliaciones, eventos, cursos y verificación de documentos.';
?><!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= e($titulo) ?></title>
<meta name="description" content="<?= e($descripcion) ?>">
<meta property="og:title" content="<?= e($titulo) ?>">
<meta property="og:description" content="<?= e($descripcion) ?>">
<meta property="og:type" content="website">
<meta name="robots" content="<?= isset($noIndexar) && $noIndexar ? 'noindex' : 'index,follow' ?>">
<link rel="stylesheet" href="/assets/css/base.css">
</head>
<body>
<header class="barra">
  <a class="marca" href="/">AMBA <span>Nacional</span></a>
</header>
<main class="contenido">

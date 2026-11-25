<?php
$titulo = 'AMBA Nacional';
$noIndexar = true;
require __DIR__ . '/_layout_inicio.php';
?>
<section class="tarjeta">
  <p class="sello sello-malo"><?= (int) $codigo ?></p>
  <h1><?= e($mensaje) ?></h1>
  <p><a href="/">Volver al inicio</a></p>
</section>
<?php require __DIR__ . '/_layout_fin.php'; ?>

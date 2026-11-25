<?php
/** Página de verificación de documentos por QR. */
$titulo = 'Verificación de documentos · AMBA';
$noIndexar = true;
require __DIR__ . '/_layout_inicio.php';
?>
<section class="tarjeta verificacion">
<?php if ($clase === 'no_encontrado'): ?>
  <p class="sello sello-malo">NO ENCONTRADO</p>
  <h1>Este código no corresponde a ningún documento de AMBA</h1>
  <p>Revisa que el QR esté completo y bien escaneado. Si el problema sigue, el documento podría no ser auténtico.</p>
<?php else: ?>
  <?php if ($valido): ?>
    <p class="sello sello-bueno"><?= $clase === 'constancia' ? 'CONSTANCIA VÁLIDA' : 'DOCUMENTO VÁLIDO' ?></p>
  <?php else: ?>
    <p class="sello sello-malo">DOCUMENTO ANULADO</p>
  <?php endif; ?>

  <h1><?= e($tipo) ?></h1>
  <dl class="datos">
    <dt>Folio</dt><dd><?= e($folio) ?></dd>
    <?php if (!empty($nombre)): ?><dt><?= e($etiquetaNombre ?? 'Nombre') ?></dt><dd><?= e($nombre) ?></dd><?php endif; ?>
    <?php if (!empty($curso)): ?><dt>Curso</dt><dd><?= e($curso) ?></dd><?php endif; ?>
    <?php if (!empty($evento)): ?><dt>Evento</dt><dd><?= e($evento) ?><?= !empty($eventoFecha) ? ' · ' . e(fecha_larga($eventoFecha)) : '' ?></dd><?php endif; ?>
    <?php if (!empty($nivel)): ?><dt>Nivel</dt><dd><?= e($nivel) ?></dd><?php endif; ?>
    <?php if (!empty($autorizadoPor)): ?><dt>Autorizado por</dt><dd><?= e($autorizadoPor) ?></dd><?php endif; ?>
    <dt>Emitido</dt><dd><?= e(fecha_larga($fecha)) ?></dd>
    <?php if (!empty($vigencia)): ?><dt>Vigencia del documento</dt><dd><?= e(fecha_larga($vigencia)) ?></dd><?php endif; ?>
  </dl>

  <?php if (!empty($afiliacion)): ?>
    <p class="estado <?= $afiliacion['activa'] ? 'estado-activo' : 'estado-inactivo' ?>"><?= e($afiliacion['texto']) ?></p>
  <?php endif; ?>

  <?php if ($clase === 'constancia'): ?>
    <p class="leyenda">La validez de esta constancia no implica afiliación activa.</p>
  <?php endif; ?>
<?php endif; ?>
</section>
<?php require __DIR__ . '/_layout_fin.php'; ?>

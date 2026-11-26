# Servicio de PDFs (Cloud Run)

Copia versionada de `main.py` y `documentos.py` del servicio `amba-pdf`
(proyecto `amba-nacional`, región `us-central1`). Las imágenes (`assets/`:
logo, firma, sello, fondos) NO se suben a GitHub; viven en la carpeta `aut`
de Kai y en Cloud Shell.

Cambios 2027 (marcados `NUEVO 2027`):
- `qr_url`: el QR de la credencial apunta a `/verificar/<token>` de AMBA 2.0.
- El año de la credencial sale de la vigencia ("Diciembre 2027" → 2027).
- El QR y la foto ya no se reutilizan de una solicitud anterior.

## Desplegar (Cloud Shell)

    cd amba-pdf            # carpeta con main.py, documentos.py, Dockerfile y assets/
    gcloud run deploy amba-pdf --source . --region us-central1

Sin `--set-env-vars` se conserva el token que ya tiene el servicio.
Prueba: `curl https://<url-del-servicio>/health`

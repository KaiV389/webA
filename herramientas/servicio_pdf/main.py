"""
AMBA — main.py
==============
Servicio FastAPI para generación de documentos de afiliación.

    POST /generar   → recibe el registro en JSON, devuelve PDFs en base64
    GET  /health    → verificación de vida (para pruebas y monitoreo)

Autenticación: header  X-AMBA-Token  que debe coincidir con la variable
de entorno AMBA_SERVICE_TOKEN (se define al desplegar en Cloud Run,
NUNCA se escribe en el código).

Flujo previsto:
    Apps Script (onFormSubmit) → POST /generar → PDFs base64
    → Apps Script los guarda en Drive, los adjunta al correo
      y escribe el link wa.me en la Sheet.
"""

import base64
import os
import shutil
import tempfile
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

import documentos

app = FastAPI(title='AMBA — Generador de documentos', version='1.0.0')

SERVICE_TOKEN = os.environ.get('AMBA_SERVICE_TOKEN', '')


# ══════════════════════════════════════════════════════════════
#  Modelos del payload
# ══════════════════════════════════════════════════════════════

class Cursos(BaseModel):
    """1/True = curso validado por Kai; 0/False/ausente = no válido."""
    ciencias:    int | bool = 0
    metodologia: int | bool = 0
    pedagogia:   int | bool = 0
    urgencias:   int | bool = 0
    matematicas: int | bool = 0


class Registro(BaseModel):
    # Identidad y folios (el folio maestro se CONSERVA en renovaciones)
    folio_afi: str = Field(..., description='Folio Maestro, ej. AMBA-26NAL-AFI001')
    folio_con: str = ''
    folio_cre: str = ''
    folio_nom: str = ''

    # Datos del afiliado / escuela
    nombre:    str
    escuela:   str = ''
    municipio: str = ''
    estado:    str = ''

    # Clasificación
    rol:        str = 'Entrenador'
    cargo_mesa: str = ''
    tipo_cred:  str = 'Tipo C'
    grado_cred: str = 'Instructor'

    # Vigencia (texto que aparece en los PDFs) — PARAMETRIZADA
    vigencia_label: str = 'Diciembre 2026'

    # Imágenes
    foto_url: str = ''
    logo_url: str = ''

    # Cursos validados (celdas verdes de la credencial)
    cursos: Cursos = Cursos()

    # Fecha de registro (para nombramientos) — 'YYYY-MM-DD'
    fecha_registro: str = ''

    # NUEVO 2027 — liga del QR de la credencial: la página permanente de
    # verificación de AMBA 2.0 (https://…/verificar/<token>). Si viene vacía
    # se usa la liga vieja (/afiliados/?id=folio).
    qr_url: str = ''


class PDFGenerado(BaseModel):
    tipo:     str
    filename: str
    base64:   str


class RespuestaGeneracion(BaseModel):
    ok:     bool
    folio:  str
    nombre: str
    pdfs:   list[PDFGenerado]


# ══════════════════════════════════════════════════════════════
#  Auth
# ══════════════════════════════════════════════════════════════

def validar_token(token: Optional[str]):
    if not SERVICE_TOKEN:
        raise HTTPException(500, 'AMBA_SERVICE_TOKEN no configurado en el servidor')
    if not token or token != SERVICE_TOKEN:
        raise HTTPException(401, 'Token inválido')


# ══════════════════════════════════════════════════════════════
#  Endpoints
# ══════════════════════════════════════════════════════════════

@app.get('/health')
def health():
    return {
        'ok': True,
        'servicio': 'AMBA Generador de documentos',
        'rembg': documentos.REMBG_OK,
        'pymupdf': documentos.FITZ_OK,
        'assets_ok': (documentos.ASSETS / 'logo_amba_limpio.png').exists(),
    }


@app.post('/generar', response_model=RespuestaGeneracion)
def generar(registro: Registro, x_amba_token: Optional[str] = Header(None)):
    validar_token(x_amba_token)

    reg = registro.model_dump()
    # Aplanar cursos a dict simple para documentos.py
    reg['cursos'] = registro.cursos.model_dump()

    workdir = Path(tempfile.mkdtemp(prefix='amba_'))
    try:
        generados = documentos.procesar_registro(reg, carpeta_base=workdir)

        if not generados:
            raise HTTPException(
                422,
                f'No se generó ningún documento para rol="{registro.rol}" '
                f'(verifica folio_afi/folio_nom y el rol)'
            )

        pdfs = []
        for tipo, ruta in generados:
            data = Path(ruta).read_bytes()
            pdfs.append(PDFGenerado(
                tipo=tipo,
                filename=Path(ruta).name,
                base64=base64.b64encode(data).decode('ascii'),
            ))

        return RespuestaGeneracion(
            ok=True,
            folio=registro.folio_afi or registro.folio_nom,
            nombre=registro.nombre,
            pdfs=pdfs,
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f'Error generando documentos: {e}')
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

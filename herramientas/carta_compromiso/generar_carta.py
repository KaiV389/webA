# -*- coding: utf-8 -*-
"""
Genera la Declaración de Responsabilidad y Compromiso de AMBA en PDF (una hoja, tamaño carta).

    py generar_carta.py

Sale en  salida/Carta_Compromiso_AMBA_<año>.pdf
Requiere:  py -m pip install reportlab

Todo lo editable (año, textos, tamaños) está en CONFIGURACIÓN y TEXTO.
Las líneas marcadas con  # NUEVO 2027  son agregados a la versión 2026:
revisarlas con la mesa directiva y el área legal.
"""

import os
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_JUSTIFY, TA_CENTER
from reportlab.lib.colors import HexColor
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, ListFlowable,
                                ListItem, KeepTogether, Table, TableStyle)

AQUI = os.path.dirname(os.path.abspath(__file__))

# ============================================================
#  CONFIGURACIÓN
# ============================================================
ANIO = 2027
SALIDA = os.path.join(AQUI, "salida", f"Carta_Compromiso_AMBA_{ANIO}.pdf")
LOGO = os.path.join(AQUI, "assets", "logo_amba.png")
MARCA_AGUA = os.path.join(AQUI, "assets", "marca_agua.jpg")
SITIO = "ambanacional.org"

MARGEN_IZQ = MARGEN_DER = 62     # puntos (72 = 1 pulgada)
MARGEN_SUP = 96                  # deja lugar al encabezado con logo
MARGEN_INF = 40
TAM = 9.1                        # texto general
INTERLINEA = 11.0
TAM_SECCION = 10.6
VERDE = HexColor("#1E6B2D")

# ============================================================
#  TEXTO
# ============================================================
TITULO = "DECLARACIÓN DE RESPONSABILIDAD Y COMPROMISO"
SUBTITULO = f"Entrenadores y escuelas afiliadas a AMBA · {ANIO}"

INTRO = (
    "Yo, __________________________________________________, entrenador(a) responsable de la escuela "
    "____________________________________________, ubicada en ________________________________________ "
    "(municipio y estado), declaro que la información proporcionada para el proceso de afiliación a la "
    "Asociación Mexiquense de Boxeo Amateur (AMBA) es real, verificable y corresponde a mi identidad y "
    "actividad deportiva actual. Con mi firma, reconozco lo siguiente:"
)

SECCIONES = [
    ("1. Veracidad y transparencia", None, [
        "Proporciono datos reales y completos en mi registro.",
        "Actualizaré mi información cuando sea necesario.",
        "Entiendo la importancia de mantener claridad en la información relacionada con mi escuela y mis atletas.",
    ], None),
    ("2. Seguridad y protección del atleta", "Me comprometo a:", [
        "velar por la integridad física y emocional de los atletas bajo mi responsabilidad;",
        "evitar emparejamientos riesgosos o desiguales;",
        "no ocultar peleas, récords o historial deportivo con el fin de obtener ventaja;",
        "respetar los criterios de seguridad establecidos por AMBA, incluidas las suspensiones médicas: "
        "no inscribiré ni presentaré a un atleta suspendido.",                                     # NUEVO 2027
    ],
     "Estoy consciente de que el incumplimiento de cualquiera de estos puntos puede poner en riesgo la "
     "seguridad de los atletas. Por ello, acepto que AMBA podrá revocar mi afiliación y retirar su respaldo "
     "institucional en caso de conductas que comprometan la integridad de los participantes."),
    ("3. Ética y conducta profesional", None, [
        "Me conduzco con respeto, profesionalismo y responsabilidad dentro y fuera del ring.",
        "Promuevo un ambiente seguro, respetuoso y libre de violencia o discriminación.",
        "Reconozco la importancia del Código de Ética del Entrenador AMBA.",
    ], None),
    ("4. Participación y compromiso institucional", "Entiendo que:", [
        "la afiliación a AMBA implica responsabilidad y participación mínima;",
        "el respaldo institucional es mutuo: AMBA respalda a quienes también respaldan el crecimiento de la comunidad;",
        "la Asociación no limita mi participación en otros eventos, pero sí espera coherencia y compromiso con "
        "los procesos oficiales.",
    ], None),
    ("5. Respeto a lineamientos y procesos", None, [
        "Conozco y respeto los reglamentos, protocolos y disposiciones emitidas por AMBA.",
        "Colaboro en la construcción de un sistema transparente y seguro para todos.",
        "Entregaré en tiempo el expediente de los eventos que organice con aval de AMBA "
        "(pruebas de servicios, aval firmado, resultados y resumen).",                              # NUEVO 2027
    ], None),
    ("6. Registros, plataforma y uso de la afiliación", None, [                                    # NUEVO 2027 (título)
        "Comprendo que la afiliación representa un reconocimiento a mi labor y responsabilidad como entrenador.",
        "Registraré a mis atletas con datos verídicos y mantendré actualizado su historial de peleas, "
        "incluidas las realizadas fuera de AMBA.",                                                  # NUEVO 2027
        "Recabaré la responsiva y la autorización de imagen firmadas por padre, madre o tutor de mis "
        "atletas menores de edad.",                                                                 # NUEVO 2027
        "Mi cuenta en la plataforma de AMBA es personal e intransferible: no compartiré el acceso ni "
        "ofreceré a terceros las herramientas de la Asociación.",                                   # NUEVO 2027
    ], None),
]

CIERRE = (
    "Declaro haber leído, comprendido y aceptado el contenido de este documento, reconociendo que su "
    "propósito principal es la seguridad, integridad y bienestar de los atletas. Mis datos personales "
    f"serán tratados conforme al aviso de privacidad de AMBA, disponible en {SITIO}."             # NUEVO 2027 (privacidad)
)

NOTA_PIE = ("Imprime, firma y sube una foto o escaneo legible de esta carta en el formulario de afiliación. "
            "Sin ella no se genera la afiliación.")

# ============================================================
#  DIBUJO
# ============================================================

def fuentes():
    for normal, negrita in [
        (r"C:\Windows\Fonts\calibri.ttf", r"C:\Windows\Fonts\calibrib.ttf"),
        ("/usr/share/fonts/truetype/crosextra/Carlito-Regular.ttf",
         "/usr/share/fonts/truetype/crosextra/Carlito-Bold.ttf"),
    ]:
        if os.path.exists(normal) and os.path.exists(negrita):
            pdfmetrics.registerFont(TTFont("Texto", normal))
            pdfmetrics.registerFont(TTFont("Texto-Negrita", negrita))
            pdfmetrics.registerFontFamily("Texto", normal="Texto", bold="Texto-Negrita")
            return
    raise SystemExit("No encontré Calibri ni Carlito.")


def fondo(c, doc):
    ancho, alto = letter
    c.saveState()
    lado = 330
    c.drawImage(MARCA_AGUA, (ancho - lado) / 2, (alto - lado) / 2 - 20, lado, lado)
    c.drawImage(LOGO, MARGEN_IZQ, alto - 82, 52, 52, mask="auto")
    c.setFont("Texto", 13)
    c.drawString(MARGEN_IZQ + 64, alto - 61, "Asociación Mexiquense de Boxeo Amateur")
    c.setStrokeColor(VERDE)
    c.setLineWidth(1)
    c.line(MARGEN_IZQ, alto - 90, ancho - MARGEN_DER, alto - 90)
    c.setFont("Texto", 7.8)
    c.setFillColor(HexColor("#555555"))
    c.drawCentredString(ancho / 2, 24, NOTA_PIE)
    c.restoreState()


def generar():
    fuentes()
    os.makedirs(os.path.dirname(SALIDA), exist_ok=True)
    doc = SimpleDocTemplate(SALIDA, pagesize=letter, leftMargin=MARGEN_IZQ, rightMargin=MARGEN_DER,
                            topMargin=MARGEN_SUP, bottomMargin=MARGEN_INF,
                            title=f"{TITULO.title()} {ANIO}", author="Asociación Mexiquense de Boxeo Amateur")

    titulo = ParagraphStyle("t", fontName="Texto-Negrita", fontSize=13, leading=16, alignment=TA_CENTER)
    sub = ParagraphStyle("s", fontName="Texto", fontSize=10, leading=13, alignment=TA_CENTER, spaceAfter=6)
    cuerpo = ParagraphStyle("c", fontName="Texto", fontSize=TAM, leading=INTERLINEA, alignment=TA_JUSTIFY)
    seccion = ParagraphStyle("h", fontName="Texto-Negrita", fontSize=TAM_SECCION, leading=13,
                             textColor=VERDE, spaceBefore=4, spaceAfter=1)
    vineta = ParagraphStyle("v", parent=cuerpo, alignment=0)

    h = [Paragraph(TITULO, titulo), Paragraph(SUBTITULO, sub), Paragraph(INTRO, vineta)]  # a la izquierda: los ____ no se estiran
    for nombre, antes, puntos, despues in SECCIONES:
        bloque = [Paragraph(nombre, seccion)]
        if antes:
            bloque.append(Paragraph(antes, cuerpo))
        bloque.append(ListFlowable([ListItem(Paragraph(p, vineta), leftIndent=12) for p in puntos],
                                   bulletType="bullet", start="•", leftIndent=12, bulletFontSize=8))
        if despues:
            bloque += [Spacer(1, 2), Paragraph(f"<b>{despues}</b>", cuerpo)]
        h.append(KeepTogether(bloque))

    h += [Spacer(1, 6), Paragraph(CIERRE, cuerpo), Spacer(1, 18)]

    # Tres líneas separadas: columnas vacías de 24 pt entre ellas
    firma = Table(
        [["", "", "", "", ""],
         ["Nombre y firma", "", "Fecha", "", "Lugar"]],
        colWidths=[220, 24, 100, 24, 120], rowHeights=[22, 14],
    )
    negro = HexColor("#000000")
    firma.setStyle(TableStyle([
        ("FONTNAME", (0, 1), (-1, 1), "Texto"), ("FONTSIZE", (0, 1), (-1, 1), 9),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("LINEABOVE", (0, 1), (0, 1), 0.7, negro),
        ("LINEABOVE", (2, 1), (2, 1), 0.7, negro),
        ("LINEABOVE", (4, 1), (4, 1), 0.7, negro),
    ]))
    h.append(firma)

    paginas = []
    doc.build(h, onFirstPage=fondo, onLaterPages=fondo, canvasmaker=_contador(paginas))
    print(f"Listo: {SALIDA}  ({paginas[0]} página{'s' if paginas[0] > 1 else ''})")
    if paginas[0] > 1:
        print("  AVISO: no cupo en una hoja; baja TAM o INTERLINEA en CONFIGURACIÓN.")


def _contador(destino):
    from reportlab.pdfgen.canvas import Canvas

    class C(Canvas):
        def save(self):
            destino.append(self.getPageNumber() - 1 if self._code == [] else self.getPageNumber())
            super().save()
    return C


if __name__ == "__main__":
    generar()

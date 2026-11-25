# -*- coding: utf-8 -*-
"""
Genera las 4 cartas responsivas de AMBA con la cláusula de uso de imagen
y la línea de aviso de privacidad.

    py generar_responsivas.py

Salen en la carpeta  salida/ :
    Responsiva_menores_de_18.pdf
    Responsiva_Embarazo_menores_de_18.pdf
    Responsiva_mayores_de_18.pdf
    Responsiva_Embarazo_mayores_de_18.pdf

Requiere:  py -m pip install reportlab
Tipografía: usa Calibri de Windows si existe; si no, Carlito (idéntica en medidas).

Todo lo que se puede ajustar está en la sección CONFIGURACIÓN:
textos, márgenes, tamaños de letra y espacios (en puntos; 72 pt = 1 pulgada).
"""

import os
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_JUSTIFY, TA_LEFT
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph
from reportlab.pdfgen import canvas

AQUI = os.path.dirname(os.path.abspath(__file__))

# ============================================================
#  CONFIGURACIÓN
# ============================================================

CARPETA_SALIDA = os.path.join(AQUI, "salida")
LOGO = os.path.join(AQUI, "assets", "logo_amba.jpg")
MARCA_AGUA = os.path.join(AQUI, "assets", "marca_agua.jpg")
CORREO_REVOCACION = "coordinacion@ambanacional.org"
SITIO = "ambanacional.org"

# Página y márgenes (puntos, medidos desde arriba)
ANCHO, ALTO = A4
MARGEN_IZQ = 83
MARGEN_DER = 80
ANCHO_TEXTO = ANCHO - MARGEN_IZQ - MARGEN_DER

# Logo y marca de agua: (x, y_desde_arriba, ancho, alto)
POS_LOGO = (86, 78, 58, 58)
POS_MARCA_AGUA = (132, 235, 331, 331)

# Tipografía
TAM = 10.7                 # tamaño del texto general (igual al original)
INTERLINEA = 13            # distancia entre renglones de un párrafo
ESPACIO_CAMPOS = 16.5       # distancia entre los renglones de datos
ESPACIO_PARRAFOS = 6       # espacio extra entre párrafos
TAM_CLAUSULA = 9.4         # tamaño del texto dentro del recuadro de imagen
INTERLINEA_CLAUSULA = 11.2

# Encabezado
Y_ENCABEZADO = 92          # renglón "ASOCIACIÓN MEXIQUENSE…"
Y_CAMPOS = 160             # primer renglón de datos

# Firma principal
LARGO_LINEA_FIRMA = 200
ESPACIO_ANTES_FIRMA = 30

# ============================================================
#  TEXTOS
# ============================================================

def textos(menor: bool, mujer: bool):
    """Devuelve todos los textos de una variante."""
    comp = "la competidora" if mujer else "el competidor"
    comp_a = "a la competidora" if mujer else "al competidor"
    del_comp = "de la competidora" if mujer else "del competidor"

    if menor:
        titulo = (["CARTA RESPONSIVA Y DECLARACIÓN DE NO EMBARAZO PARA",
                   "BOXEADORAS MENORES DE 18 AÑOS"] if mujer
                  else ["CARTA RESPONSIVA PARA MENORES DE 18 AÑOS"])
        campos = [
            "Nombre completo: ",
            "Fecha de Nacimiento: ______/_______/______|Edad: ",
            "Domicilio: ",
            "Teléfono de contacto: ",
            "Nombre completo del tutor legal: ",
            "Clave de INE del tutor legal: ",
        ]
        nota = "NOTA: Acompañar de copia legible de credencial de INE del tutor legal"
        p1 = (f"A través de esta carta responsiva, en mi carácter de tutor {del_comp} de boxeo "
              "________________________________________________ y con pleno conocimiento de mis "
              "facultades mentales, declaro, en su nombre, que de forma voluntaria se presenta al evento "
              "deportivo __________________________________________ en buen estado físico y cumpliendo "
              "las características físicas y de estado de salud necesarias para la práctica de este deporte "
              "y declaro estar consciente del riesgo de lesiones, (entre ellas, aunque no exclusivas, "
              "fracturas, luxaciones, esguinces, contusiones, etc.) que puedan derivarse de su participación "
              "en el presente evento deportivo.")
        embarazo = ("Declaro también que no se encuentra en estado de embarazo, adjuntando una prueba de "
                    "laboratorio que confirma esto.")
        quien_sufre = f"que {comp} pueda sufrir"
        a_quien = comp_a
        firma = "Firma y nombre del tutor legal"
        clausula = (
            "En mi carácter de tutor legal, autorizo a la Asociación Mexiquense de Boxeo Amateur (AMBA) "
            f"a captar y publicar la imagen y la voz {del_comp} en fotografías, video y transmisiones en "
            "vivo del presente evento deportivo, así como en su difusión posterior en la página web, redes "
            "sociales y material de difusión de AMBA, incluidos carteles y flyers, con fines de difusión "
            "deportiva e institucional y sin que ello genere pago alguno. Esta autorización es independiente "
            f"de la participación: si no autorizo, {comp} participa con normalidad y AMBA no publicará su "
            "imagen ni transmitirá sus combates. Puedo revocarla en cualquier momento mediante aviso por "
            f"escrito a {CORREO_REVOCACION}; la revocación aplica desde ese momento y AMBA retirará de sus "
            "medios digitales el material ya publicado.")
        firma_clausula = "Firma del tutor legal:"
    else:
        titulo = (["CARTA RESPONSIVA Y DECLARACIÓN DE NO EMBARAZO PARA",
                   "BOXEADORAS MAYORES DE 18 AÑOS"] if mujer
                  else ["CARTA RESPONSIVA PARA MAYORES DE 18 AÑOS"])
        campos = [
            "Nombre completo: ",
            "Fecha de Nacimiento: ______/_______/______|Edad: ",
            "Domicilio: ",
            "Teléfono de contacto: ",
            "Clave de INE: ",
        ]
        nota = "NOTA: Acompañar de copia legible de credencial de INE"
        caracter = "competidora" if mujer else "competidor"
        p1 = (f"A través de esta carta responsiva, en mi carácter de {caracter} de boxeo y con pleno "
              "conocimiento de mis facultades mentales, de forma voluntaria, me presento al evento deportivo "
              "_______________________________________________________________ en buen estado físico y "
              "cumpliendo las características físicas y de estado de salud necesarias para la práctica de "
              "este deporte y declaro estar consciente del riesgo de lesiones, (entre ellas, aunque no "
              "exclusivas, fracturas, luxaciones, esguinces, contusiones, etc.) que puedan derivarse de mi "
              "participación en el presente evento deportivo.")
        embarazo = ("Declaro también no estar en estado de embarazo, para lo cual adjunto prueba de "
                    "laboratorio que lo confirma.")
        quien_sufre = "que yo pueda sufrir"
        a_quien = "a mi persona"
        firma = f"Firma y nombre de{' la competidora' if mujer else 'l competidor'}"
        clausula = (
            "Autorizo a la Asociación Mexiquense de Boxeo Amateur (AMBA) a captar y publicar mi imagen y mi "
            "voz en fotografías, video y transmisiones en vivo del presente evento deportivo, así como en su "
            "difusión posterior en la página web, redes sociales y material de difusión de AMBA, incluidos "
            "carteles y flyers, con fines de difusión deportiva e institucional y sin que ello genere pago "
            "alguno. Esta autorización es independiente de mi participación: si no autorizo, participo con "
            "normalidad y AMBA no publicará mi imagen ni transmitirá mis combates. Puedo revocarla en "
            f"cualquier momento mediante aviso por escrito a {CORREO_REVOCACION}; la revocación aplica desde "
            "ese momento y AMBA retirará de sus medios digitales el material ya publicado.")
        firma_clausula = f"Firma de{' la competidora' if mujer else 'l competidor'}:"

    parrafos = [p1]
    if mujer:
        parrafos.append(embarazo)
    parrafos += [
        "De acuerdo con lo anterior, libero al Comité Organizador, jueces, agentes, representantes, "
        "voluntarios y otros miembros, de cualquier reclamación, acciones, demandas, controversias en "
        "derecho o en equidad por cualquier asunto, razón, causa o situación alguna "
        f"{quien_sufre} como resultado de {'mi' if not menor else 'su'} participación en el presente evento deportivo.",

        "Comprendo y acepto que todas las atenciones médicas o tratamientos que se realicen "
        f"{a_quien} durante este evento deportivo por: PARAMEDICOS o SERVICIO MÉDICO asignado por AMBA, "
        "y todos los relacionados, serán de primeros auxilios y deslindo de responsabilidad por este tipo "
        "de ayuda, en el entendido que es mi responsabilidad obtener cobertura médica.",

        "Igualmente me comprometo a acatar y seguir las normas establecidas por el AMBA y el Comité Organizador.",

        "Los datos personales aquí proporcionados serán tratados conforme al aviso de privacidad de AMBA, "
        f"disponible en {SITIO}.",
    ]
    cierre = "He leído y entiendo la renuncia de responsabilidades mencionadas anteriormente."
    return dict(titulo=titulo, campos=campos, nota=nota, parrafos=parrafos,
                cierre=cierre, firma=firma, clausula=clausula, firma_clausula=firma_clausula)


VARIANTES = [
    ("Responsiva_menores_de_18.pdf",           True,  False),
    ("Responsiva_Embarazo_menores_de_18.pdf",  True,  True),
    ("Responsiva_mayores_de_18.pdf",           False, False),
    ("Responsiva_Embarazo_mayores_de_18.pdf",  False, True),
]

# ============================================================
#  DIBUJO (normalmente no hace falta tocar de aquí para abajo)
# ============================================================

def registrar_fuentes():
    candidatas = [
        (r"C:\Windows\Fonts\calibri.ttf", r"C:\Windows\Fonts\calibrib.ttf"),
        ("/usr/share/fonts/truetype/crosextra/Carlito-Regular.ttf",
         "/usr/share/fonts/truetype/crosextra/Carlito-Bold.ttf"),
    ]
    for normal, negrita in candidatas:
        if os.path.exists(normal) and os.path.exists(negrita):
            pdfmetrics.registerFont(TTFont("Texto", normal))
            pdfmetrics.registerFont(TTFont("Texto-Negrita", negrita))
            return
    raise SystemExit("No encontré Calibri ni Carlito. Instala Carlito o ajusta las rutas en registrar_fuentes().")


def y(desde_arriba):
    """Convierte 'puntos desde arriba' a la coordenada de ReportLab."""
    return ALTO - desde_arriba


def generar(nombre_archivo, menor, mujer):
    t = textos(menor, mujer)
    os.makedirs(CARPETA_SALIDA, exist_ok=True)
    c = canvas.Canvas(os.path.join(CARPETA_SALIDA, nombre_archivo), pagesize=A4)
    c.setTitle(" ".join(t["titulo"]).title())
    c.setAuthor("Asociación Mexiquense de Boxeo Amateur")

    # Marca de agua y logo
    mx, my, mw, mh = POS_MARCA_AGUA
    c.drawImage(MARCA_AGUA, mx, y(my + mh), mw, mh)
    lx, ly, lw, lh = POS_LOGO
    c.drawImage(LOGO, lx, y(ly + lh), lw, lh)

    # Encabezado centrado
    centro = ANCHO / 2
    c.setFont("Texto-Negrita", TAM)
    c.drawCentredString(centro, y(Y_ENCABEZADO), "ASOCIACIÓN MEXIQUENSE DE BOXEO AMATEUR")
    c.setFont("Texto", TAM)
    cursor = Y_ENCABEZADO + 19
    for renglon in t["titulo"]:
        c.drawCentredString(centro, y(cursor), renglon)
        cursor += 19

    # Campos de datos con línea hasta el margen derecho
    cursor = max(cursor + 12, Y_CAMPOS)
    der = ANCHO - MARGEN_DER
    for campo in t["campos"]:
        if "|" in campo:                       # Fecha de nacimiento + Edad en el mismo renglón
            izq, edad = campo.split("|")
            c.drawString(MARGEN_IZQ, y(cursor), izq)
            x_edad = 330
            c.drawString(x_edad, y(cursor), edad)
            x0 = x_edad + c.stringWidth(edad, "Texto", TAM)
        else:
            c.drawString(MARGEN_IZQ, y(cursor), campo)
            x0 = MARGEN_IZQ + c.stringWidth(campo, "Texto", TAM)
        c.setLineWidth(0.6)
        c.line(x0, y(cursor) - 1.5, der, y(cursor) - 1.5)
        cursor += ESPACIO_CAMPOS
    c.drawString(MARGEN_IZQ, y(cursor), t["nota"])
    cursor += ESPACIO_CAMPOS + 4

    # Párrafos justificados
    estilo = ParagraphStyle("p", fontName="Texto", fontSize=TAM, leading=INTERLINEA, alignment=TA_JUSTIFY)
    for texto in t["parrafos"]:
        p = Paragraph(texto, estilo)
        _, alto = p.wrap(ANCHO_TEXTO, 1000)
        p.drawOn(c, MARGEN_IZQ, y(cursor - TAM + alto))
        cursor += alto + ESPACIO_PARRAFOS

    # Recuadro: autorización de uso de imagen
    cursor += 2
    pad = 7
    estilo_cl = ParagraphStyle("cl", fontName="Texto", fontSize=TAM_CLAUSULA,
                               leading=INTERLINEA_CLAUSULA, alignment=TA_LEFT)  # izquierda: el correo largo abre huecos si se justifica
    cl = Paragraph(t["clausula"], estilo_cl)
    _, alto_cl = cl.wrap(ANCHO_TEXTO - 2 * pad, 1000)
    alto_caja = pad + 13 + 17 + alto_cl + pad
    top_caja = cursor - TAM
    c.setLineWidth(0.8)
    c.rect(MARGEN_IZQ, y(top_caja + alto_caja), ANCHO_TEXTO, alto_caja)

    fila = top_caja + pad + TAM
    c.setFont("Texto-Negrita", TAM)
    titulo_cl = "AUTORIZACIÓN DE USO DE IMAGEN"
    c.drawString(MARGEN_IZQ + pad, y(fila), titulo_cl)
    c.setFont("Texto", TAM - 1)
    c.drawString(MARGEN_IZQ + pad + c.stringWidth(titulo_cl, "Texto-Negrita", TAM) + 5, y(fila),
                 "(marque una opción)")

    # Casillas + firma de la cláusula
    fila += 17
    c.setFont("Texto", TAM)
    x = MARGEN_IZQ + pad
    for opcion in ("SÍ AUTORIZO", "NO AUTORIZO"):
        c.rect(x, y(fila) - 1, 9, 9)
        c.drawString(x + 14, y(fila), opcion)
        x += 14 + c.stringWidth(opcion, "Texto", TAM) + 22
    x_firma = x + 8
    c.drawString(x_firma, y(fila), t["firma_clausula"])
    x_linea = x_firma + c.stringWidth(t["firma_clausula"], "Texto", TAM) + 4
    c.line(x_linea, y(fila) - 1.5, ANCHO - MARGEN_DER - pad, y(fila) - 1.5)

    cl.drawOn(c, MARGEN_IZQ + pad, y(fila + 6 + alto_cl))
    cursor = top_caja + alto_caja + ESPACIO_PARRAFOS + TAM + 4

    # Cierre y firma principal
    c.setFont("Texto", TAM)
    c.drawString(MARGEN_IZQ, y(cursor), t["cierre"])
    cursor += ESPACIO_ANTES_FIRMA
    c.setLineWidth(0.6)
    c.line(centro - LARGO_LINEA_FIRMA / 2, y(cursor), centro + LARGO_LINEA_FIRMA / 2, y(cursor))
    cursor += 14
    c.drawCentredString(centro, y(cursor), t["firma"])

    if cursor > ALTO - 28:
        print(f"  AVISO: {nombre_archivo} se sale de la hoja ({cursor:.0f} pt). Reduce espacios en CONFIGURACIÓN.")
    c.showPage()
    c.save()
    return cursor


if __name__ == "__main__":
    registrar_fuentes()
    for archivo, menor, mujer in VARIANTES:
        fin = generar(archivo, menor, mujer)
        print(f"Listo: {archivo}  (termina a {fin:.0f} de {ALTO:.0f} pt)")

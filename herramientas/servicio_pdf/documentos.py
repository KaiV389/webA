"""
AMBA — documentos.py
====================
Dibujo de PDFs (afiliación, constancia, credencial, nombramientos).
Portado del generador.py original con dos cambios estructurales:

  1. Entrada: dict (JSON del payload) en lugar de fila de pandas/Excel.
  2. Vigencia parametrizada: se lee `vigencia_label` del registro
     (antes estaba hardcodeada como "Junio 2026").

Las coordenadas y estilos se conservan EXACTAMENTE igual que en el
generador original para no alterar el diseño de los documentos.
"""

import re
from pathlib import Path
from io import BytesIO
from datetime import datetime, date

import requests
import qrcode
from PIL import Image, ImageOps
from reportlab.lib import colors as rlcolors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph
from reportlab.pdfgen import canvas

try:
    import fitz  # pymupdf
    FITZ_OK = True
except ImportError:
    FITZ_OK = False

try:
    from rembg import remove as rembg_remove
    REMBG_OK = True
except ImportError:
    REMBG_OK = False
    print('⚠️  rembg no instalado — se omitirá el remove background.')

BASE   = Path(__file__).parent
ASSETS = BASE / 'assets'
OUTPUT = BASE / 'output'
CACHE  = BASE / 'output' / 'cache'
CACHE.mkdir(parents=True, exist_ok=True)

FONT_DIR = '/usr/share/fonts/truetype/liberation/'
if Path(FONT_DIR + 'LiberationSans-Regular.ttf').exists():
    pdfmetrics.registerFont(TTFont('LSans',  FONT_DIR + 'LiberationSans-Regular.ttf'))
    pdfmetrics.registerFont(TTFont('LSans-B', FONT_DIR + 'LiberationSans-Bold.ttf'))
    FR, FB = 'LSans', 'LSans-B'
else:
    FR, FB = 'Helvetica', 'Helvetica-Bold'

NEGRO = (0, 0, 0); AZUL = (0.05, 0.15, 0.40); AZUL_M = (0.18, 0.35, 0.65)
VERDE = (0.1, 0.3, 0.1); ROJO = (0.55, 0, 0)
W, H = letter
MARGEN = 45

VIGENCIA_DEFAULT = 'Diciembre 2026'


# ══════════════════════════════════════════════════════════════
#  Helpers de datos (entrada = dict del payload JSON)
# ══════════════════════════════════════════════════════════════

def g(reg, key, default=''):
    """Lee un campo del registro como texto limpio."""
    v = reg.get(key)
    if v is None:
        return default
    v = str(v).strip()
    return v if v else default


def curso_ok(reg, key):
    """True si el curso está validado (1/true/si)."""
    cursos = reg.get('cursos') or {}
    v = cursos.get(key, 0)
    if isinstance(v, bool):
        return v
    try:
        return float(v) >= 1
    except (TypeError, ValueError):
        return str(v).strip().upper() in ('1', 'TRUE', 'SI', 'SÍ')


def bb(t):
    return re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', t)


def formato_fecha(fecha_str):
    meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
             'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre']
    try:
        s = str(fecha_str).strip()
        d = None
        for fmt in ('%Y-%m-%d', '%d/%m/%Y', '%Y-%m-%dT%H:%M:%S'):
            try:
                d = datetime.strptime(s[:19] if 'T' in s else s[:10], fmt)
                break
            except ValueError:
                continue
        if d is None:
            d = datetime.now()
        return f'Coyotepec, Estado de México a {d.day} de {meses[d.month - 1]} de {d.year}'
    except Exception:
        return f'Coyotepec, Estado de México a {date.today().year}'


# ══════════════════════════════════════════════════════════════
#  Imágenes, fotos y QR  (sin cambios de lógica)
# ══════════════════════════════════════════════════════════════

def descargar_imagen(url, ruta_cache):
    if not url:
        return None
    ruta_cache = Path(ruta_cache)
    if ruta_cache.exists():
        return ruta_cache
    try:
        if 'drive.google.com' in url:
            id_match = re.search(r'id=([a-zA-Z0-9_-]+)', url)
            if id_match:
                file_id = id_match.group(1)
                url = f'https://drive.google.com/uc?export=download&id={file_id}'

        headers = {'User-Agent': 'Mozilla/5.0'}
        session = requests.Session()
        r = session.get(url, timeout=20, headers=headers)
        r.raise_for_status()

        if 'text/html' in r.headers.get('Content-Type', ''):
            token_match = re.search(r'confirm=([0-9A-Za-z_-]+)', r.text)
            if token_match:
                token = token_match.group(1)
                r = session.get(url + f'&confirm={token}', timeout=30, headers=headers)
                r.raise_for_status()
            else:
                if 'drive.google.com' in url:
                    id_match = re.search(r'id=([a-zA-Z0-9_-]+)', url)
                    if id_match:
                        file_id = id_match.group(1)
                        url2 = f'https://drive.google.com/uc?export=download&id={file_id}&confirm=t'
                        r = session.get(url2, timeout=30, headers=headers)
                        r.raise_for_status()

        content_type = r.headers.get('Content-Type', '')

        if 'pdf' in content_type.lower() or str(url).lower().endswith('.pdf'):
            if not FITZ_OK:
                print('  ⚠️  pymupdf no instalado')
                return None
            pdf = fitz.open(stream=r.content, filetype='pdf')
            pagina = pdf[0]
            mat = fitz.Matrix(2, 2)
            pix = pagina.get_pixmap(matrix=mat)
            img = Image.frombytes('RGB', [pix.width, pix.height], pix.samples)
            print('  📄 PDF convertido a imagen')
        else:
            try:
                img = Image.open(BytesIO(r.content))
                img = ImageOps.exif_transpose(img)
                img = img.convert('RGB')
            except Exception:
                if not FITZ_OK:
                    return None
                try:
                    pdf = fitz.open(stream=r.content, filetype='pdf')
                    pagina = pdf[0]
                    mat = fitz.Matrix(2, 2)
                    pix = pagina.get_pixmap(matrix=mat)
                    img = Image.frombytes('RGB', [pix.width, pix.height], pix.samples)
                    print('  📄 PDF detectado y convertido a imagen')
                except Exception as e2:
                    print(f'  ⚠️  No se pudo procesar archivo: {e2}')
                    return None

        img.save(ruta_cache)
        return ruta_cache
    except Exception as e:
        print(f'  ⚠️  No se pudo descargar imagen: {e}')
        return None


def foto_borde(ruta, w, h, cache_name, quitar_fondo=False):
    out = CACHE / cache_name
    try:
        img = Image.open(ruta).convert('RGBA')
        if quitar_fondo and REMBG_OK:
            try:
                img = rembg_remove(img)
                fondo = Image.new('RGBA', img.size, (255, 255, 255, 255))
                fondo.paste(img, mask=img.split()[3])
                img = fondo.convert('RGB')
                print('  🖼️  Fondo removido')
            except Exception as e:
                print(f'  ⚠️  No se pudo quitar fondo: {e}')
                img = img.convert('RGB')
        else:
            img = img.convert('RGB')
        img = img.resize((w, h), Image.LANCZOS)
    except Exception:
        img = Image.new('RGB', (w, h), (150, 150, 150))

    res = Image.new('RGB', (w + 6, h + 6), (212, 175, 55))
    res.paste(img, (3, 3))
    res.save(out)
    return out


def gen_qr(url, cache_name, size=300, borde_color=None):
    # NUEVO 2027: el nombre del caché incluye la liga; si la liga cambia
    # (reexpedición, liga nueva) no se reutiliza un QR viejo.
    import hashlib
    h = hashlib.sha1(url.encode('utf-8')).hexdigest()[:10]
    out = CACHE / cache_name.replace('.png', f'_{h}.png')
    if out.exists():
        return out
    qr = qrcode.QRCode(version=1, error_correction=qrcode.constants.ERROR_CORRECT_M,
                       box_size=14, border=2)
    qr.add_data(url); qr.make(fit=True)
    img = qr.make_image(fill_color='black', back_color='white').convert('RGB')
    if borde_color:
        b = 10; wq, hq = img.size
        res = Image.new('RGB', (wq + b * 2, hq + b * 2), borde_color)
        res.paste(img, (b, b)); res = res.resize((size, size), Image.LANCZOS); res.save(out)
    else:
        img.resize((size, size), Image.LANCZOS).save(out)
    return out


def pj(c, texto, x, y, ancho, font=None, size=12, leading=17, color=NEGRO, align=TA_JUSTIFY):
    font = font or FR; r, gg, b = color
    style = ParagraphStyle('p', fontName=font, fontSize=size, leading=leading,
                           alignment=align, textColor=rlcolors.Color(r, gg, b))
    p = Paragraph(texto, style); p.wrapOn(c, ancho, 9999)
    p.drawOn(c, x, y - p.height); return p.height


def header_afiliacion(c):
    c.drawImage(str(ASSETS / 'logo_amba_limpio.png'), MARGEN, H - 95, width=75, height=75,
                mask='auto', preserveAspectRatio=True)
    c.setFont(FB, 20); c.setFillColorRGB(*NEGRO)
    txt = 'Asociación Mexiquense de Boxeo Amateur'; tw = c.stringWidth(txt, FB, 20)
    xs = MARGEN + 75 + 14; sp = W - MARGEN - xs
    c.drawString(xs + (sp - tw) / 2, H - 62, txt)


def _firma_presidente(c, y, qr_path):
    y -= 20
    c.setFont(FB, 13); c.setFillColorRGB(*NEGRO)
    c.drawCentredString(W / 2, y, 'Atentamente'); y -= 55
    c.setLineWidth(0.5); c.line(W / 2 - 90, y, W / 2 + 90, y)
    c.setFont(FB, 13); c.drawCentredString(W / 2, y - 16, 'Profr. José Luis Díaz')
    c.setFont(FR, 12); c.drawCentredString(W / 2, y - 32, 'Presidente AMBA Nacional')
    c.drawImage(str(ASSETS / 'firma.png'), W / 2 - 75, y - 35, width=95, height=75,
                mask='auto', preserveAspectRatio=True)
    c.drawImage(str(ASSETS / 'sello.png'), W / 2 + 15, y - 33, width=70, height=70,
                mask='auto', preserveAspectRatio=True)
    c.drawImage(str(qr_path), MARGEN, 22, width=105, height=105)
    c.drawImage(str(ASSETS / 'logo_amba_limpio.png'), W - MARGEN - 90, 18, width=90, height=90,
                mask='auto', preserveAspectRatio=True)


# ══════════════════════════════════════════════════════════════
#  AFILIACIÓN
# ══════════════════════════════════════════════════════════════

def generar_afiliacion(reg, carpeta):
    nombre = g(reg, 'nombre'); escuela = g(reg, 'escuela')
    municipio = g(reg, 'municipio'); estado = g(reg, 'estado')
    folio_af = g(reg, 'folio_afi'); folio_ai = folio_af.replace('AFL', 'AFI')
    vigencia_label = g(reg, 'vigencia_label', VIGENCIA_DEFAULT)   # ← parametrizada
    ruta = carpeta / f'afiliacion_{nombre}.pdf'
    c = canvas.Canvas(str(ruta), pagesize=letter)

    # P1
    header_afiliacion(c)
    c.setFont(FR, 13); c.setFillColorRGB(*NEGRO)
    c.drawString(MARGEN, H - 120, 'A quien corresponda'); c.drawString(MARGEN, H - 135, 'Presente')
    c.setFont(FB, 34); c.drawCentredString(W / 2, H - 178, 'Afiliación Deportiva')
    c.setFont(FR, 13); c.setFillColorRGB(0.4, 0.4, 0.4)
    c.drawCentredString(W / 2, H - 200, f'Folio  {folio_af}')
    c.setFont(FR, 13); c.setFillColorRGB(*NEGRO)
    c.drawCentredString(W / 2, H - 228, 'La presente acredita a')
    c.setFont(FB, 20); c.drawCentredString(W / 2, H - 252, nombre)
    lbl = 'Afiliado folio  '; c.setFont(FR, 13); lw = c.stringWidth(lbl, FR, 13)
    c.setFont(FB, 13); fw = c.stringWidth(folio_ai, FB, 13); xs = (W - lw - fw) / 2
    c.setFont(FR, 13); c.drawString(xs, H - 274, lbl)
    c.setFont(FB, 13); c.drawString(xs + lw, H - 274, folio_ai)
    c.setFont(FR, 13)
    c.drawCentredString(W / 2, H - 296, f'Como representante activo de la escuela {escuela}')
    c.drawCentredString(W / 2, H - 314, 'Misma que está ubicada en:')
    c.setFont(FR, 18); c.drawCentredString(W / 2, H - 338, f'{municipio} , {estado}')

    y = H - 388
    for i, txt in enumerate([
        'La Asociación Mexiquense de Boxeo Amateur reconoce al titular como miembro activo de AMBA, acreditando su participación en el proceso de especialización y profesionalización continua que impulsa nuestra organización para fortalecer el boxeo amateur en el Estado de México.',
        'Esta afiliación provisional se otorga a entrenadores que, desde su experiencia, trayectoria y compromiso con la disciplina, han decidido formalizar y elevar sus competencias técnicas, alineándose a los estándares de calidad y ética que AMBA promueve para el desarrollo responsable del deporte.',
        'La presente constancia acredita su incorporación a AMBA durante el periodo señalado y respalda su participación en actividades oficiales mientras continúa su proceso de especialización.',
    ]):
        y -= pj(c, txt, MARGEN, y, W - MARGEN * 2, size=13, leading=18)
        if i == 1:
            c.setFont(FR, 13)
            c.drawRightString(W - MARGEN, y - 22, f'Vigencia: {vigencia_label}')   # ← parametrizada
            y -= 50
        elif i < 2:
            y -= 16

    c.showPage()

    # P2
    header_afiliacion(c)
    y = H - 108
    c.setFont(FB, 12); c.setFillColorRGB(*NEGRO); c.drawCentredString(W / 2, y, 'Declaración de Conformidad'); y -= 18
    s_dec = ParagraphStyle('d', fontName=FR, fontSize=10, leading=13, textColor=rlcolors.black, leftIndent=12)
    for item in ['Cumplir con los reglamentos y estatutos establecidos en la Ley General de Cultura Física y Deporte',
                 'Participar en programas de capacitación y actualización organizados por la AMBA.',
                 'Promover el desarrollo del boxeo amateur de manera ética y profesional.']:
        p = Paragraph(f'□  {item}', s_dec); p.wrapOn(c, W - 80, 100); p.drawOn(c, MARGEN + 8, y - p.height); y -= p.height + 3

    y -= 8
    for titulo, items in [
        ('Reglamentos y Estatutos', None), ('1. Objetivo', None),
        (None, ['Fomentar el desarrollo del deporte y la cultura física en México.', 'Promover la participación de los sectores social y privado en el deporte.']),
        ('2. Competencias', None),
        (None, ['Coordinación entre entidades federativas, municipios y sectores privado y social', 'Distribución de competencias y colaboración en materia de cultura física y deporte']),
        ('3. Derechos y Obligaciones', None), ('Derechos de los Entrenadores:', None),
        (None, ['Acceso a programas de capacitación y actualización.', 'Participación en eventos y competencias organizadas por la AMBA.',
                'No estarán condicionados ningún entrenador ni escuela a limitar su participación en eventos de AMBA, respetando su derecho de participación a cualquier evento de boxeo de otras Asociaciones, Organizaciones o Federaciones, que sean o no parte de AMBA.']),
        ('Obligaciones de los Entrenadores:', None),
        (None, ['Cumplir con los reglamentos y estatutos de la AMBA.', 'Promover el desarrollo del boxeo amateur de manera ética y profesional']),
        ('Programas y Subsidios', None),
        (None, ['Implementación de programas de activación física y deporte.', 'Incentivos para la inversión social y privada en el deporte']),
        ('Prevención y Salud', None),
        (None, ['Fomentar la activación física como medio para la preservación de la salud y prevención de enfermedades', 'Promover el deporte como herramienta para la prevención del delito y las adicciones']),
        ('Apoyos', None), (None, ['Apoyos para el desarrollo de programas deportivos']),
    ]:
        if titulo:
            y -= 4
            c.setFont(FB, 10); c.setFillColorRGB(*NEGRO); c.drawCentredString(W / 2, y, titulo); y -= 14
        if items:
            for item in items:
                p = Paragraph(f'□  {item}', s_dec); p.wrapOn(c, W - 70, 200); p.drawOn(c, MARGEN + 8, y - p.height); y -= p.height + 2

    y -= 25; c.setLineWidth(0.5); c.line(MARGEN, y, MARGEN + 180, y)
    c.setFont(FR, 10); c.drawString(MARGEN, y - 13, 'Nombre:'); c.drawString(MARGEN, y - 26, 'Firma de Aceptación')
    y_base = 85
    c.setFont(FR, 12); c.drawCentredString(W / 2, y_base + 72, 'Atentamente')
    c.setLineWidth(0.5); c.line(W / 2 - 80, y_base + 12, W / 2 + 80, y_base + 12)
    c.setFont(FB, 12); c.drawCentredString(W / 2, y_base - 2, 'Profr. José Luis Díaz')
    c.setFont(FR, 12); c.drawCentredString(W / 2, y_base - 17, 'Presidente Asociación Mexiquense de Boxeo Amateur')
    c.drawImage(str(ASSETS / 'firma.png'), W / 2 - 75, y_base + 8, width=95, height=75,
                mask='auto', preserveAspectRatio=True)
    c.drawImage(str(ASSETS / 'sello.png'), W / 2 + 15, y_base + 6, width=68, height=68,
                mask='auto', preserveAspectRatio=True)
    c.save(); print(f'  ✅ Afiliación: {ruta.name}'); return ruta


# ══════════════════════════════════════════════════════════════
#  CONSTANCIA
# ══════════════════════════════════════════════════════════════

def generar_constancia(reg, carpeta, foto_path, logo_path):
    nombre = g(reg, 'nombre')
    escuela = g(reg, 'escuela')
    folio_af = g(reg, 'folio_afi').replace('AFL', 'AFI')
    folio_con = g(reg, 'folio_con')
    vigencia_label = g(reg, 'vigencia_label', VIGENCIA_DEFAULT)   # ← parametrizada
    foto = foto_borde(foto_path, 120, 150, f'foto_con_{folio_af}.png', quitar_fondo=True) if foto_path else None

    ruta = carpeta / f'constancia_{nombre}.pdf'
    c = canvas.Canvas(str(ruta), pagesize=letter)
    c.drawImage(str(ASSETS / 'bg_constancia.png'), 0, 0, width=W, height=H)

    c.drawImage(str(ASSETS / 'logo_amba_limpio.png'), W / 2 - 45, H - 105, width=90, height=90,
                mask='auto', preserveAspectRatio=True)

    c.setFont(FB, 30); c.setFillColorRGB(*AZUL)
    c.drawCentredString(W / 2, H - 135, 'CONSTANCIA DE AFILIACIÓN')
    c.setFont(FR, 12); c.drawCentredString(W / 2, H - 157, f'Folio     {folio_con}')

    if foto:
        c.drawImage(str(foto), MARGEN + 10, H - 330, width=126, height=156)

    cx = (MARGEN + 10 + 126 + W - MARGEN) / 2
    c.setFont(FR, 13); c.setFillColorRGB(*AZUL)
    c.drawCentredString(cx, H - 183, 'Otorgada a')
    c.setFont(FB, 20); c.setFillColorRGB(*AZUL_M)
    c.drawCentredString(cx, H - 210, escuela)
    c.setFont(FR, 13); c.setFillColorRGB(*AZUL)
    c.drawCentredString(cx, H - 238, 'Responsable técnico:')
    c.setFont(FB, 19); c.setFillColorRGB(*AZUL_M)
    c.drawCentredString(cx, H - 264, nombre)
    c.setFont(FR, 13); c.setFillColorRGB(*AZUL)
    c.drawCentredString(cx, H - 284, folio_af)

    y = H - 348
    for txt in [
        'La Asociación Mexiquense de Boxeo Amateur reconoce a la escuela mencionada como gimnasio afiliado, en virtud de la labor profesional que desarrolla su entrenador responsable, quien cumple con los estándares técnicos, éticos y formativos que AMBA promueve para fortalecer el boxeo amateur.',
        'El registro del gimnasio se otorga a través del entrenador afiliado, y se mantiene vigente únicamente mientras dicho entrenador esté al frente del grupo y continúe cumpliendo con los lineamientos de AMBA.',
        'Esta política garantiza que la calidad del trabajo técnico y formativo del gimnasio esté respaldada por un profesional que comparte el compromiso de AMBA con la profesionalización, la ética y el desarrollo responsable del deporte.',
        'La validez de este registro se sustenta en la dirección técnica reconocida por AMBA que garantiza el cumplimiento de los estándares promovidos por la Asociación.',
    ]:
        y -= pj(c, txt, MARGEN, y, W - MARGEN * 2, size=12, leading=16, color=AZUL)
        y -= 8

    c.setFont(FB, 16); c.setFillColorRGB(*AZUL)
    c.drawCentredString(W / 2, y - 14, f'Vigencia: {vigencia_label}')   # ← parametrizada
    y -= 38

    h_final = pj(c, f'La presente constancia acredita el registro del gimnasio {escuela} '
                    f'durante el periodo señalado, conforme a los lineamientos establecidos por AMBA.',
                 MARGEN, y, W - MARGEN * 2, size=12, leading=16, color=AZUL)
    y -= h_final

    y_aten = y - 20
    c.setFont(FR, 12); c.setFillColorRGB(*AZUL)
    c.drawCentredString(W / 2, y_aten, 'Atentamente')

    y_linea = y_aten - 55
    c.setStrokeColorRGB(*AZUL); c.setLineWidth(0.5)
    c.line(W / 2 - 85, y_linea, W / 2 + 85, y_linea)

    c.setFont(FB, 13); c.setFillColorRGB(*AZUL)
    c.drawCentredString(W / 2, y_linea - 14, 'Jose Luis Díaz Méndez')
    c.setFont(FR, 12)
    c.drawCentredString(W / 2, y_linea - 28, 'Presidente AMBA NACIONAL')

    c.drawImage(str(ASSETS / 'firma.png'), W / 2 - 80, y_linea - 30, width=95, height=75,
                mask='auto', preserveAspectRatio=True)
    c.drawImage(str(ASSETS / 'sello.png'), W / 2 + 10, y_linea - 32, width=70, height=70,
                mask='auto', preserveAspectRatio=True)

    c.save()
    print(f'  ✅ Constancia: {ruta.name}')
    return ruta


# ══════════════════════════════════════════════════════════════
#  CREDENCIAL
# ══════════════════════════════════════════════════════════════

def generar_credencial(reg, carpeta, foto_path, logo_path):
    nombre = g(reg, 'nombre'); escuela = g(reg, 'escuela')
    municipio = g(reg, 'municipio'); estado = g(reg, 'estado')
    folio_af = g(reg, 'folio_afi').replace('AFL', 'AFI')
    folio_cre = g(reg, 'folio_cre'); tipo_cred = g(reg, 'tipo_cred', 'Tipo C')
    vigencia_label = g(reg, 'vigencia_label', VIGENCIA_DEFAULT)   # ← parametrizada
    # NUEVO 2027: el QR lleva a la verificación permanente de AMBA 2.0
    qr_url = g(reg, 'qr_url') or f'https://ambanacional.org/afiliados/?id={folio_af}'
    qr_path = gen_qr(qr_url, f'qr_cre_{folio_af}.png', size=300)
    foto_p3 = foto_borde(foto_path, 220, 245, f'foto_cre_{folio_af}.png', quitar_fondo=True) if foto_path else None
    ruta = carpeta / f'credencial_{nombre}.pdf'
    c = canvas.Canvas(str(ruta), pagesize=letter)

    # P1
    c.drawImage(str(ASSETS / 'bg_cred_p1.png'), 0, 0, width=W, height=H)
    for dx, dy in [(-1.2, 0), (1.2, 0), (0, -1.2), (0, 1.2)]:
        c.setFont(FB, 22); c.setFillColorRGB(0.05, 0.25, 0.05)
        c.drawCentredString(W / 2 + dx, H - 58 + dy, 'Asociación Mexiquense de Boxeo Amateur')
    c.setFillColorRGB(*NEGRO); c.drawCentredString(W / 2, H - 58, 'Asociación Mexiquense de Boxeo Amateur')
    s = ParagraphStyle('l', fontName=FR, fontSize=21, leading=30, alignment=TA_JUSTIFY, textColor=rlcolors.black)
    p = Paragraph('Esta credencial es una identificación deportiva expedida por la Asociación Mexiquense de Boxeo Amateur, el mal uso de ella será responsabilidad de quien la porta y de quién la usa.', s)
    p.wrapOn(c, W - MARGEN * 2, 200); p.drawOn(c, MARGEN, H - 195)
    c.setFont(FR, 17); c.drawCentredString(W / 2, H - 238, 'Quejas o sugerencias')
    lbl = 'Contacto: '; c.setFont(FB, 15); c.setFillColorRGB(*ROJO); lw = c.stringWidth(lbl, FB, 15)
    linea = '5595946900 // coordinacion@ambanacional.org'
    xs = (W - lw - c.stringWidth(linea, FR, 15)) / 2; c.drawString(xs, H - 260, lbl)
    c.setFont(FR, 15); c.setFillColorRGB(*NEGRO); c.drawString(xs + lw, H - 260, linea)
    qsz = 300; qy = H / 2 - qsz - 10; c.drawImage(str(qr_path), W / 2 - qsz / 2, qy, width=qsz, height=qsz)
    c.setFont(FB, 36); c.drawCentredString(W / 2, qy - 44, 'ESCANEA QR')
    c.setFont(FB, 18); c.drawCentredString(W / 2, qy - 70, folio_cre); c.showPage()

    # P2
    c.drawImage(str(ASSETS / 'bg_cred_p2.png'), 0, 0, width=W, height=H)
    c.setFont(FB, 52); c.setFillColorRGB(*NEGRO); c.drawCentredString(W / 2, H - 88, 'CREDENCIAL')
    c.setFont(FB, 26); c.drawCentredString(W / 2, H - 126, 'AMBA NACIONAL')
    # NUEVO 2027: el año sale de la vigencia ("Diciembre 2027" → 2027)
    anio_m = re.search(r'(20\d\d)', vigencia_label)
    c.setFont(FB, 30); c.drawCentredString(W / 2, H - 162, anio_m.group(1) if anio_m else '2026')
    c.setFont(FB, 44); c.drawCentredString(W / 2, 175, 'Entrenador')
    c.setFont(FR, 24); c.drawCentredString(W / 2, 140, 'A F I L I A D O')
    c.setFont(FB, 18); c.setFillColorRGB(0.1, 0.3, 0.1)
    fl = 'F O L I O :'; flw = c.stringWidth(fl, FB, 18); xs2 = W / 2 - 145
    c.drawString(xs2, 103, fl); c.setFont(FB, 18); c.setFillColorRGB(*ROJO)
    c.drawString(xs2 + flw + 10, 103, folio_af)
    c.setStrokeColorRGB(*NEGRO); c.setLineWidth(0.8); c.line(xs2 + flw + 7, 100, W / 2 + 145, 100); c.showPage()

    # P3
    c.drawImage(str(ASSETS / 'bg_cred_p3_final.png'), 0, 0, width=W, height=H)
    c.saveState(); c.translate(W, 0); c.rotate(90)

    if foto_p3:
        c.drawImage(str(foto_p3), 62, 285, width=220, height=245)
    if logo_path and Path(str(logo_path)).exists():
        c.drawImage(str(logo_path), 658, 169, width=101, height=100, mask='auto', preserveAspectRatio=True)

    c.setFillColorRGB(*NEGRO)
    c.setFont(FR, 18); c.drawString(480, 505, nombre)
    grado = g(reg, 'grado_cred', 'Instructor')
    c.setFont(FR, 12)
    c.drawString(455, 430, municipio); c.drawString(430, 360, escuela)
    c.drawString(455, 288, vigencia_label)   # ← parametrizada (antes 'Junio 2026' fijo)
    c.drawString(670, 430, estado)
    c.drawString(670, 360, tipo_cred); c.drawString(670, 288, grado)

    # ── Tabla de cursos (celdas verdes = curso validado) ──────
    CURSOS_TAB = [
        ('Ciencias del deporte',                                  curso_ok(reg, 'ciencias')),
        ('Pedagogía del deporte',                                 curso_ok(reg, 'pedagogia')),
        ('Matemáticas y unidades\nde medición\npara el deporte',  curso_ok(reg, 'matematicas')),
        ('Metodología del Boxeo',                                 curso_ok(reg, 'metodologia')),
        ('Urgencias médicas',                                     curso_ok(reg, 'urgencias')),
    ]

    TABLA_X = 18
    TABLA_Y = 150
    CELDA_W = 266
    CELDA_H = 63
    COL_W = (CELDA_W * 2.855) / 3
    VERDE_C = (0.13, 0.45, 0.13)

    def dibujar_celda(cx, cy, cw, ch, texto, aprobado):
        if not aprobado:
            c.setStrokeColorRGB(0, 0, 0); c.setLineWidth(0)
            c.rect(cx, cy, cw, ch, fill=0, stroke=0)
            return
        c.setFillColorRGB(*VERDE_C); c.setStrokeColorRGB(0, 0, 0); c.setLineWidth(0)
        c.rect(cx, cy, cw, ch, fill=1, stroke=0)
        c.setFillColorRGB(0, 0, 0); c.setFont(FB, 16)
        lines = texto.split('\n')
        total_h = len(lines) * 13
        y_txt = cy + ch / 2 + total_h / 2 - 13
        for line in lines:
            c.drawCentredString(cx + cw / 2, y_txt, line)
            y_txt -= 13

    y_f1 = TABLA_Y - CELDA_H
    for i, curso_idx in enumerate([3, 0, 1]):
        txt, aprobado = CURSOS_TAB[curso_idx]
        dibujar_celda(TABLA_X + i * COL_W, y_f1, COL_W, CELDA_H, txt, aprobado)

    y_f2 = TABLA_Y - CELDA_H * 2
    txt_urg, apr_urg = CURSOS_TAB[4]
    txt_mat, apr_mat = CURSOS_TAB[2]
    dibujar_celda(TABLA_X,          y_f2, COL_W,     CELDA_H, txt_urg, apr_urg)
    dibujar_celda(TABLA_X + COL_W,  y_f2, COL_W * 2, CELDA_H, txt_mat, apr_mat)

    c.restoreState(); c.showPage()

    # P4
    c.drawImage(str(ASSETS / 'bg_cred_p4.png'), 0, 0, width=W, height=H)
    c.setFont(FB, 34); c.setFillColorRGB(*NEGRO); c.drawCentredString(W / 2, H - 70, 'Beneficios')
    y = H - 118
    for b in ['Asesoría jurídica', 'Cursos y capacitación (a bajos costos o gratuitos)',
              'Respaldo legal', 'Seminarios y campamentos de preparación',
              'Apoyos (de acuerdo al recurso disponible u obtenido)',
              'Jornadas de salud a bajos costos', 'Asesorías en marketing y administración (Gratuitas)',
              'Aval (referís y jueces a bajos costos)',
              'Trámites, cartas de recomendación, constancias',
              'Cartas petitorias o apoyos en gestión', 'Bolsa de trabajo']:
        c.setFont(FB, 21); c.drawString(MARGEN + 5, y, f'*{b}'); y -= 57
    c.save(); print(f'  ✅ Credencial: {ruta.name}'); return ruta


# ══════════════════════════════════════════════════════════════
#  NOMBRAMIENTOS (delegado estatal / mesa directiva)
# ══════════════════════════════════════════════════════════════

def _nom_bloque_derecho(c, y_top, foto_w, tipo_nom, nombre, folio_nom, cargo_mesa=None):
    x_der = MARGEN + foto_w + 18; w_der = W - MARGEN - x_der; cx = x_der + w_der / 2
    y_b = y_top - 5
    c.setFont(FB, 26); c.setFillColorRGB(*NEGRO); c.drawCentredString(cx, y_b, 'NOMBRAMIENTO OFICIAL'); y_b -= 28
    c.setFont(FR, 12); c.drawCentredString(cx, y_b, 'como'); y_b -= 15
    sc = ParagraphStyle('tc', fontName=FB, fontSize=13, leading=15, alignment=TA_CENTER, textColor=rlcolors.black)
    pt = Paragraph(tipo_nom, sc); pt.wrapOn(c, w_der, 60); pt.drawOn(c, x_der, y_b - pt.height); y_b -= pt.height + 4
    c.setFont(FR, 12); c.drawCentredString(cx, y_b, 'a:'); y_b -= 14
    c.setFont(FB, 17); c.drawCentredString(cx, y_b, nombre); y_b -= 24
    if cargo_mesa:
        c.setFont(FR, 11); c.drawCentredString(cx, y_b, 'con el cargo de'); y_b -= 14
        c.setFont(FB, 14); c.drawCentredString(cx, y_b, cargo_mesa); y_b -= 18
    c.setFont(FB, 12); c.drawCentredString(cx, y_b, folio_nom)


def _nom_p2(c, bg_p2, facultad9, alcances, compromiso_titulo, compromisos, qr_path, style_fac, style_item):
    c.drawImage(str(bg_p2), 0, 0, width=W, height=H)
    y = H - 60
    p9 = Paragraph(f'9. {facultad9}', style_fac); p9.wrapOn(c, W - MARGEN * 2, 100)
    p9.drawOn(c, MARGEN, y - p9.height); y -= p9.height + 18
    c.setFont(FB, 13); c.setFillColorRGB(*NEGRO); c.drawString(MARGEN, y, 'Alcance del nombramiento'); y -= 15
    c.setFont(FR, 12); c.drawString(MARGEN, y, 'Este nombramiento:'); y -= 15
    for item in alcances:
        p = Paragraph(f'·{item}', style_item); p.wrapOn(c, W - MARGEN * 2, 200)
        p.drawOn(c, MARGEN, y - p.height); y -= p.height + 4
    y -= 10; c.setFont(FB, 13); c.drawString(MARGEN, y, 'Cláusula de revocación'); y -= 15
    y -= pj(c, 'El presente nombramiento podrá ser <b>suspendido o revocado de manera inmediata</b> en caso de:', MARGEN, y, W - MARGEN * 2, size=12, leading=16); y -= 4
    for rev in ['Incurrir en abuso de autoridad o conductas que perjudiquen a afiliados, entrenadores, atletas o público.',
                'Incumplimiento de procesos o protocolos oficiales', 'Falta de reportes o comunicación',
                'Conflictos graves o desalineación ética',
                'Usar el nombramiento para obtener beneficios indebidos o realizar cobros no autorizados.',
                'Poner en riesgo la integridad de atletas, entrenadores u oficiales']:
        p = Paragraph(f'·{rev}', style_item); p.wrapOn(c, W - MARGEN * 2, 200); p.drawOn(c, MARGEN, y - p.height); y -= p.height + 3
    y -= 6; y -= pj(c, 'La revocación será determinada por la Mesa Directiva Nacional conforme a los lineamientos vigentes.', MARGEN, y, W - MARGEN * 2, size=12, leading=16); y -= 10
    c.setFont(FB, 13); c.drawString(MARGEN, y, compromiso_titulo); y -= 15
    c.setFont(FR, 12); c.drawString(MARGEN, y, 'Al aceptar este nombramiento, se compromete a:'); y -= 15
    for comp in compromisos:
        p = Paragraph(f'·{comp}', style_item); p.wrapOn(c, W - MARGEN * 2, 200); p.drawOn(c, MARGEN, y - p.height); y -= p.height + 3
    _firma_presidente(c, y, qr_path)


def generar_nombramiento_delegado(reg, carpeta, foto_path):
    nombre = g(reg, 'nombre'); estado_nom = g(reg, 'estado')
    folio_nom = g(reg, 'folio_nom'); fecha_str = formato_fecha(g(reg, 'fecha_registro'))
    tipo_nom = f'DELEGADO ESTATAL {estado_nom.upper()}'
    foto = foto_borde(foto_path, 115, 150, f'foto_del_{folio_nom}.png', quitar_fondo=True) if foto_path else None
    qr_path = gen_qr(f'https://ambanacional.org/delegados/index.php?id={folio_nom}', f'qr_del_{folio_nom}.png', size=105, borde_color=(26, 77, 26))
    facs = ['**Ejecutar localmente** los procesos, lineamientos y protocolos establecidos por AMBA Nacional.',
            '**Coordinar y supervisar** actividades relacionadas con el boxeo amateur en su entidad.',
            '**Promover el desarrollo del boxeo**, garantizando inclusión, ética, juego limpio y seguridad.',
            '**Supervisar y gestionar avales**, siguiendo el proceso oficial de Autorización Condicionada, Acta de Verificación y Validación Final.',
            '**Asegurar el cumplimiento** de los protocolos de seguridad, protección del atleta y reglamentos vigentes.',
            '**Representar oficialmente a AMBA** en eventos, reuniones y actividades dentro de su estado.',
            '**Presentar reportes periódicos** sobre actividades, eventos, incidencias y avances del boxeo amateur en su región.',
            '**Coordinar a su mesa directiva estatal**, así como a las Coordinaciones Regionales (si aplica), previa aprobación de AMBA Nacional.',
            '**Promover capacitaciones**, afiliaciones y actividades que fortalezcan el crecimiento del boxeo en su entidad.']
    sf = ParagraphStyle('f', fontName=FR, fontSize=12, leading=16, alignment=TA_JUSTIFY, textColor=rlcolors.black, leftIndent=18, firstLineIndent=-18)
    si = ParagraphStyle('i', fontName=FR, fontSize=12, leading=15, textColor=rlcolors.black, leftIndent=12)
    ruta = carpeta / f'nombramiento_{nombre}.pdf'; c = canvas.Canvas(str(ruta), pagesize=letter)
    c.drawImage(str(ASSETS / 'bg_del_p1.png'), 0, 0, width=W, height=H)
    c.setFont(FR, 12); c.setFillColorRGB(*NEGRO); c.drawRightString(W - MARGEN, H - 108, fecha_str)
    y = H - 130
    y -= pj(c, 'Por medio del presente, la <b>Asociación Mexiquense de Boxeo Amateur (AMBA Nacional)</b>, en cumplimiento con sus estatutos, lineamientos y protocolos vigentes, tiene le honor de otorgar el siguiente:', MARGEN, y, W - MARGEN * 2, size=12, leading=17); y -= 15
    foto_w, foto_h = 115, 150
    if foto:
        c.drawImage(str(foto), MARGEN, y - foto_h, width=foto_w, height=foto_h)
    _nom_bloque_derecho(c, y, foto_w, tipo_nom, nombre, folio_nom)
    y = y - foto_h - 18
    c.setFont(FB, 13); c.drawString(MARGEN, y, 'Facultades y responsabilidades'); y -= 16
    y -= pj(c, f'El presente nombramiento otorga las facultades necesarias para representar oficialmente a AMBA en {estado_nom}, y para desempeñar las siguientes funciones bajo los principios rectores de la asociación:', MARGEN, y, W - MARGEN * 2, size=12, leading=16); y -= 6
    for i, fac in enumerate(facs[:8], 1):
        p = Paragraph(f'{i}. {bb(fac)}', sf); p.wrapOn(c, W - MARGEN * 2, 300)
        if y - p.height < 58:
            break
        p.drawOn(c, MARGEN, y - p.height); y -= p.height + 5
    c.showPage()
    _nom_p2(c, ASSETS / 'bg_del_p2.png', bb(facs[8]),
            ['Tiene validez desde la fecha de emisión y hasta <b>diciembre 2026</b>.',
             'Está sujeto al <b>cumplimiento estricto</b> del Manual de Delegados Estatales AMBA y de los protocolos nacionales.',
             'No otorga autonomía administrativa ni facultad para emitir documentos propios, cobrar avales o modificar procesos oficiales.',
             'Requiere el compromiso de mantener comunicación constante con AMBA Nacional y entregar reportes en tiempo y forma.'],
            'Compromiso del Delegado Estatal',
            ['Representar a AMBA con ética, profesionalismo y transparencia.',
             'Cumplir los protocolos de seguridad y protección del atleta.',
             'Promover el boxeo amateur sin intereses personales.',
             'Trabajar en colaboración con la Mesa Directiva Nacional.',
             'Respetar y aplicar los lineamientos del Manual de Delegados Estatales AMBA.'],
            qr_path, sf, si)
    c.save(); print(f'  ✅ Nombramiento Delegado: {ruta.name}'); return ruta


def generar_nombramiento_mesa(reg, carpeta, foto_path):
    nombre = g(reg, 'nombre'); estado_nom = g(reg, 'estado')
    cargo_mesa = g(reg, 'cargo_mesa', 'VOCAL').upper()
    folio_nom = g(reg, 'folio_nom'); fecha_str = formato_fecha(g(reg, 'fecha_registro'))
    tipo_nom = f'MIEMBRO DE LA MESA DIRECTIVA DEL ESTADO DE {estado_nom.upper()}'
    foto = foto_borde(foto_path, 115, 150, f'foto_mesa_{folio_nom}.png', quitar_fondo=True) if foto_path else None
    qr_path = gen_qr(f'https://ambanacional.org/delegados/index.php?id={folio_nom}', f'qr_mesa_{folio_nom}.png', size=105, borde_color=(26, 77, 26))
    facs = ['Apoyar al Delegado Estatal en la ejecución de los procesos, lineamientos y protocolos establecidos por AMBA Nacional.',
            'Colaborar en la organización, supervisión y desarrollo de actividades relacionadas con el boxeo amateur en la entidad.',
            'Promover la ética, el juego limpio, la inclusión y la seguridad en todas las actividades avaladas por AMBA.',
            'Participar en la gestión de avales, siguiendo el proceso oficial de Autorización Condicionada, Acta de Verificación y Validación Final.',
            'Asegurar el cumplimiento de los protocolos de seguridad y protección del atleta, conforme a los lineamientos nacionales.',
            'Apoyar en la coordinación de entrenadores, gimnasios y clubes, manteniendo comunicación clara y ordenada.',
            'Colaborar en la elaboración de reportes, informes y documentación requerida por AMBA Nacional.',
            'Promover capacitaciones, afiliaciones y actividades formativas que fortalezcan el crecimiento del boxeo amateur en su estado.',
            'Actuar con ética, profesionalismo y transparencia, representando los valores de AMBA en todo momento.']
    sf = ParagraphStyle('f', fontName=FR, fontSize=12, leading=16, alignment=TA_JUSTIFY, textColor=rlcolors.black, leftIndent=18, firstLineIndent=-18)
    si = ParagraphStyle('i', fontName=FR, fontSize=12, leading=15, textColor=rlcolors.black, leftIndent=12)
    ruta = carpeta / f'nombramiento_{nombre}.pdf'; c = canvas.Canvas(str(ruta), pagesize=letter)
    c.drawImage(str(ASSETS / 'bg_nom_p1.png'), 0, 0, width=W, height=H)
    c.setFont(FR, 12); c.setFillColorRGB(*NEGRO); c.drawRightString(W - MARGEN, H - 108, fecha_str)
    y = H - 130
    y -= pj(c, 'Por medio del presente, la <b>Asociación Mexiquense de Boxeo Amateur (AMBA Nacional)</b>, en cumplimiento con sus estatutos, lineamientos y protocolos vigentes, tiene le honor de otorgar el siguiente:', MARGEN, y, W - MARGEN * 2, size=12, leading=17); y -= 15
    foto_w, foto_h = 115, 150
    if foto:
        c.drawImage(str(foto), MARGEN, y - foto_h, width=foto_w, height=foto_h)
    _nom_bloque_derecho(c, y, foto_w, tipo_nom, nombre, folio_nom, cargo_mesa)
    y = y - foto_h - 18
    c.setFont(FB, 13); c.drawString(MARGEN, y, 'Facultades y responsabilidades'); y -= 16
    y -= pj(c, f'El presente nombramiento otorga las facultades necesarias para desempeñar funciones dentro de la Mesa Directiva Estatal de AMBA en el estado de {estado_nom}, bajo la coordinación del Delegado Estatal y en apego a los principios rectores de la asociación.', MARGEN, y, W - MARGEN * 2, size=12, leading=16); y -= 6
    for i, fac in enumerate(facs[:8], 1):
        p = Paragraph(f'{i}. {fac}', sf); p.wrapOn(c, W - MARGEN * 2, 300)
        if y - p.height < 58:
            break
        p.drawOn(c, MARGEN, y - p.height); y -= p.height + 5
    c.showPage()
    _nom_p2(c, ASSETS / 'bg_nom_p2.png', facs[8],
            ['Tiene validez desde la fecha de emisión y hasta <b>diciembre 2026</b>.',
             'Está sujeto al <b>cumplimiento estricto</b> del Manual de Delegados Estatales AMBA y de los protocolos nacionales.',
             'No otorga autonomía administrativa ni facultad para emitir documentos propios, cobrar avales o modificar procesos oficiales.',
             'Requiere el compromiso de mantener comunicación constante con el Delegado Estatal y con AMBA Nacional y de ser necesario, entregar reportes en tiempo y forma.',
             'Forma parte de la estructura estatal encabezada por el Delegado Estatal.'],
            'Compromiso del miembro de la Mesa Directiva',
            ['Representar a AMBA con ética, profesionalismo y transparencia.',
             'Cumplir los protocolos de seguridad y protección del atleta.',
             'Promover el boxeo amateur sin intereses personales.',
             'Trabajar en colaboración con el Delegado Estatal y la Mesa Directiva Nacional.',
             'Respetar y aplicar los lineamientos del Manual de Delegados Estatales AMBA.'],
            qr_path, sf, si)
    c.save(); print(f'  ✅ Nombramiento Mesa: {ruta.name}'); return ruta


# ══════════════════════════════════════════════════════════════
#  Orquestador de un registro
# ══════════════════════════════════════════════════════════════

def procesar_registro(reg, carpeta_base=None):
    """
    Genera los documentos que apliquen según el rol.
    Devuelve lista de tuplas (tipo, Path).
    """
    rol = g(reg, 'rol', 'entrenador').lower() or 'entrenador'
    nombre = g(reg, 'nombre', 'sin_nombre')
    folio_afi = g(reg, 'folio_afi')
    folio_nom = g(reg, 'folio_nom')
    folio = folio_afi or folio_nom or nombre[:20].replace(' ', '_')

    carpeta = Path(carpeta_base) if carpeta_base else (OUTPUT / nombre.replace('/', '_'))
    carpeta.mkdir(parents=True, exist_ok=True)
    print(f'\n📋 {nombre} | Rol: {rol} | Folio: {folio}')

    foto_url = g(reg, 'foto_url'); logo_url = g(reg, 'logo_url')
    # NUEVO 2027: sin caché de foto/logo entre solicitudes (una reexpedición
    # con foto corregida debe usar la foto nueva)
    foto_path = descargar_imagen(foto_url, carpeta / f'foto_{folio}.jpg') if foto_url else None
    logo_path = descargar_imagen(logo_url, carpeta / f'logo_{folio}.jpg') if logo_url else None

    es_ent = ('entrenador' in rol or 'instructor' in rol or (not rol and bool(folio_afi)))
    es_del = 'delegado' in rol
    es_mesa = 'mesa' in rol

    generados = []
    if es_ent and folio_afi:
        generados.append(('afiliacion',  generar_afiliacion(reg, carpeta)))
        generados.append(('constancia',  generar_constancia(reg, carpeta, foto_path, logo_path)))
        generados.append(('credencial',  generar_credencial(reg, carpeta, foto_path, logo_path)))
    if es_del and folio_nom:
        generados.append(('nombramiento_delegado', generar_nombramiento_delegado(reg, carpeta, foto_path)))
    if es_mesa and folio_nom:
        generados.append(('nombramiento_mesa', generar_nombramiento_mesa(reg, carpeta, foto_path)))

    print(f'  📁 {carpeta}')
    return generados

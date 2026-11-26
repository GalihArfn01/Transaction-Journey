"""Render design/logo_tj.svg -> launcher icon PNGs (Android mipmaps + Flutter asset).

Tanpa dependency eksternal (cairosvg dsb. tidak selalu tersedia): fallback
menggambar ulang geometri yang SAMA dengan SVG memakai Pillow (rounded rect +
path J via PIL). Jalankan: python design/render_logo.py
"""
from __future__ import annotations

from PIL import Image, ImageDraw
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
SIZES_MIPMAP = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
MASTER = 1024
ASSET = ROOT / "assets" / "icon" / "app_icon.png"

# Warna tema (harus sama dengan SVG & app_theme.dart)
BG_TOP = (11, 87, 164)      # #0B57A4
BG_BOT = (10, 75, 140)      # #0A4B8C
T_TOP = (255, 255, 255)     # #FFFFFF
T_BOT = (214, 231, 255)     # #D6E7FF
J_TOP = (134, 239, 172)     # #86EFAC
J_BOT = (0, 108, 73)        # #006C49


def v_gradient(size, top, bottom):
    """Gradient vertikal sederhana sebagai image RGB."""
    w, h = size
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        c = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = c
    return img


def rounded_gradient_mask(size, radius_frac):
    """Mask rounded-rect penuh (untuk latar)."""
    w, h = size
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=round(w * radius_frac), fill=255)
    return m


def draw_logo(size: int) -> Image.Image:
    """Gambar ikon utuh pada kanvas size x size (RGBA)."""
    s = size
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    # Latar: gradient squircle
    bg = v_gradient((s, s), BG_TOP, BG_BOT).convert("RGBA")
    bg.putalpha(rounded_gradient_mask((s, s), 112 / 512))
    img.alpha_composite(bg)

    # Koordinat mengikuti viewBox 512 lalu diskalakan.
    k = s / 512.0

    def R(x, y, w, h, r, top, bot):
        """Bar rounded dengan gradient vertikal di dalamnya."""
        box = (round(x * k), round(y * k), round((x + w) * k), round((y + h) * k))
        pad = 2
        big = v_gradient((box[2] - box[0] + pad * 2, box[3] - box[1] + pad * 2), top, bot).convert("RGBA")
        mask = Image.new("L", big.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [pad, pad, big.size[0] - pad - 1, big.size[1] - pad - 1],
            radius=round(r * k), fill=255)
        img.paste(big, (box[0] - pad, box[1] - pad), mask)

    # ===== J (hijau), DI BELAKANG T. Geometri viewBox-512: =====
    # batang x 300..352, y 128..330; pusat annulus (274,330) r 26..78;
    # hook kiri x 196..248 naik ke y 308.
    j = Image.new("L", (s, s), 0)
    jd = ImageDraw.Draw(j)
    cx, cy = 274 * k, 330 * k
    r_in, r_out = 26 * k, 78 * k
    x0, x1 = 300 * k, 352 * k
    y_top, y_hook = 154 * k, 308 * k  # sejajar garis singgung sudut palang
    # Batang (turun sampai pusat lengkung)
    jd.rectangle([x0, y_top, x1, cy], fill=255)
    # Annulus setengah bawah
    jd.pieslice([cx - r_out, cy - r_out, cx + r_out, cy + r_out], 0, 180, fill=255)
    jd.ellipse([cx - r_in, cy - r_in, cx + r_in, cy + r_in], fill=0)
    # Hook kiri naik (menutup lubang annulus sisi kiri)
    jd.rectangle([cx - r_out, y_hook, cx - r_in, cy], fill=255)

    j_grad = v_gradient((s, s), J_TOP, J_BOT).convert("RGBA")
    j_grad.putalpha(j)
    img.alpha_composite(j_grad)

    # ===== T (putih) DI DEPAN — palang menimpa batang J. =====
    R(88, 128, 264, 52, 26, T_TOP, T_BOT)    # palang (sampai x=352)
    R(190, 128, 52, 196, 26, T_TOP, T_BOT)   # batang
    return img


def main() -> int:
    master = draw_logo(MASTER)

    # Flutter asset (512)
    ASSET.parent.mkdir(parents=True, exist_ok=True)
    master.resize((512, 512), Image.LANCZOS).save(ASSET)
    print(f"wrote {ASSET.relative_to(ROOT)} (512x512)")

    # Android mipmaps
    res = ROOT / "android" / "app" / "src" / "main" / "res"
    for dpi, px in SIZES_MIPMAP.items():
        out = res / f"mipmap-{dpi}" / "ic_launcher.png"
        if out.parent.exists():
            master.resize((px, px), Image.LANCZOS).save(out)
            print(f"wrote {out.relative_to(ROOT)} ({px}x{px})")

    # PNG master tersimpan juga untuk dokumentasi
    (ROOT / "design" / "logo_tj_1024.png").write_bytes(b"")
    master.save(ROOT / "design" / "logo_tj_1024.png")
    print("wrote design/logo_tj_1024.png (1024x1024)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

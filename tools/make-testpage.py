#!/usr/bin/env python3
"""
make-testpage.py -- generate a printer calibration page as a PDF.

Dependency-free: writes the PDF by hand, including a correct xref table,
so it runs on a stock macOS python3 with nothing installed.

DESIGN RULE: every measurement on this page must be readable from an
ordinary phone photo of the sheet, with no ruler and no magnifier. If a
number has to be squinted at, the page is wrong, not the reader.

The primary instrument is the MARGIN LADDER. Along each edge sit bars
whose outer edge is exactly 1, 2, 3, 4, 5, 6, 8 or 10 mm from the paper
edge, each with a large number beside it. The lowest-numbered bar that
printed completely IS the margin on that edge, in millimetres. No ruler
needed -- you read the answer straight off the sheet.

Secondary instruments:
  * corner brackets   -- show clipping and squareness at a glance
  * 100 mm span       -- catches any scaling error
  * line-pair targets -- finest block still showing separate lines is the
                         real output resolution
  * black comparison  -- composite black vs pure K, side by side

Usage:
    python3 make-testpage.py -o testpage.pdf
    python3 make-testpage.py -o t.pdf --size Letter --label "600dpi Gray"
"""

import argparse
import sys

MM = 72.0 / 25.4  # points per millimetre

PAGE_SIZES_MM = {
    "A4":        (210.0, 297.0),
    "Letter":    (215.9, 279.4),
    "Legal":     (215.9, 355.6),
    "A5":        (148.0, 210.0),
    "A6":        (105.0, 148.0),
    "Executive": (184.15, 266.7),
}

# Distances from the paper edge, in mm, that the ladder measures.
LADDER_STEPS = [1, 2, 3, 4, 5, 6, 8, 10]


class Content:
    """Accumulates PDF content-stream operators."""

    def __init__(self):
        self.ops = []

    def gray(self, g):          self.ops.append(f"{g:.3f} g")
    def stroke_gray(self, g):   self.ops.append(f"{g:.3f} G")
    def rgb(self, r, g, b):     self.ops.append(f"{r:.3f} {g:.3f} {b:.3f} rg")
    def cmyk(self, c, m, y, k): self.ops.append(f"{c:.3f} {m:.3f} {y:.3f} {k:.3f} k")
    def lw(self, w):            self.ops.append(f"{w:.4f} w")
    def save(self):             self.ops.append("q")
    def restore(self):          self.ops.append("Q")

    def dash(self, pattern=None):
        self.ops.append("[] 0 d" if not pattern else f"[{pattern}] 0 d")

    def line(self, x1, y1, x2, y2):
        self.ops.append(f"{x1:.4f} {y1:.4f} m {x2:.4f} {y2:.4f} l S")

    def rect_stroke(self, x, y, w, h):
        self.ops.append(f"{x:.4f} {y:.4f} {w:.4f} {h:.4f} re S")

    def rect_fill(self, x, y, w, h):
        self.ops.append(f"{x:.4f} {y:.4f} {w:.4f} {h:.4f} re f")

    def text(self, x, y, size, s, font="F1"):
        self.ops.append(
            f"BT /{font} {size:.2f} Tf {x:.4f} {y:.4f} Td ({_esc(s)}) Tj ET")

    def text_rot90(self, x, y, size, s, font="F1"):
        self.ops.append(
            f"BT /{font} {size:.2f} Tf 0 1 -1 0 {x:.4f} {y:.4f} Tm "
            f"({_esc(s)}) Tj ET")

    def render(self):
        return "\n".join(self.ops).encode("latin-1", "replace")


def _esc(s):
    return s.replace("\\", r"\\").replace("(", r"\(").replace(")", r"\)")


# ------------------------------------------------------- margin ladders

def draw_margin_ladders(c, w, h):
    """
    Bars parallel to each edge. The bar labelled N has its OUTER edge
    exactly N mm from the paper edge. Read off the lowest number whose bar
    printed in full: that is the margin on that edge.
    """
    c.save()

    bar_len = 17 * MM     # length along the edge
    bar_thick = 1.6 * MM  # depth into the page
    num_size = 13         # big enough for a phone photo
    n = len(LADDER_STEPS)

    def slots(span_start, span_end):
        pitch = (span_end - span_start) / n
        return [span_start + i * pitch for i in range(n)]

    # ---- top and bottom: horizontal bars, spread across the width
    xs = slots(24 * MM, w - 24 * MM - bar_len)

    for i, mm_val in enumerate(LADDER_STEPS):
        d = mm_val * MM
        x = xs[i]

        # TOP: bar sits with its top edge d below the paper's top edge
        c.gray(0.0)
        c.rect_fill(x, h - d - bar_thick, bar_len, bar_thick)
        c.text(x, h - d - bar_thick - num_size - 1.5, num_size,
               str(mm_val), font="F2")

        # BOTTOM
        c.gray(0.0)
        c.rect_fill(x, d, bar_len, bar_thick)
        c.text(x, d + bar_thick + 3.0, num_size, str(mm_val), font="F2")

    # ---- left and right: vertical bars, spread down the height
    ys = slots(30 * MM, h - 40 * MM - bar_len)

    for i, mm_val in enumerate(LADDER_STEPS):
        d = mm_val * MM
        y = ys[i]

        # LEFT
        c.gray(0.0)
        c.rect_fill(d, y, bar_thick, bar_len)
        c.text_rot90(d + bar_thick + num_size + 1.5, y, num_size,
                     str(mm_val), font="F2")

        # RIGHT
        c.gray(0.0)
        c.rect_fill(w - d - bar_thick, y, bar_thick, bar_len)
        c.text_rot90(w - d - bar_thick - 3.0, y, num_size,
                     str(mm_val), font="F2")

    # ---- legend, placed safely inside
    c.gray(0.0)
    c.text(24 * MM, h - 15 * MM, 8,
           "MARGIN LADDER -- lowest number whose bar printed COMPLETE "
           "= that edge's margin in mm", font="F2")
    c.restore()


def draw_corner_brackets(c, w, h):
    """Solid L brackets hard against each paper corner."""
    c.save()
    c.gray(0.0)
    arm = 16 * MM
    t = 2.2 * MM
    # (x, y) of corner, direction signs
    for x, y, sx, sy, name in [(0, 0, 1, 1, "BL"), (w, 0, -1, 1, "BR"),
                               (0, h, 1, -1, "TL"), (w, h, -1, -1, "TR")]:
        ax = x if sx > 0 else x - arm
        ay = y if sy > 0 else y - t
        c.rect_fill(ax, ay, arm, t)                      # horizontal arm
        bx = x if sx > 0 else x - t
        by = y if sy > 0 else y - arm
        c.rect_fill(bx, by, t, arm)                      # vertical arm
        lx = x + (sx * (arm + 2 * MM)) - (0 if sx > 0 else 9)
        ly = y + (sy * 5 * MM) - (0 if sy > 0 else 5)
        c.text(lx, ly, 10, name, font="F2")
    c.restore()


def draw_scale_check(c, w, h, y):
    """A labelled 100 mm span -- catches scaling errors with any ruler."""
    c.save()
    x0 = (w - 100 * MM) / 2.0
    c.gray(0.0)
    c.lw(1.2)
    c.stroke_gray(0.0)
    c.line(x0, y, x0 + 100 * MM, y)
    for xx in (x0, x0 + 100 * MM):
        c.line(xx, y - 2.5 * MM, xx, y + 2.5 * MM)
    for i in range(1, 10):
        xx = x0 + i * 10 * MM
        c.line(xx, y - 1.2 * MM, xx, y + 1.2 * MM)
    c.text(x0, y + 4 * MM, 9,
           "this span is exactly 100 mm -- if it measures otherwise, "
           "the page was scaled", font="F2")
    c.restore()


# ----------------------------------------------------- quality targets

def draw_linepairs(c, x, y, w, h):
    """
    Line-pair blocks. Each block's period is 2 device pixels at the named
    dpi, so it is 1 px on / 1 px off there. A block finer than the real
    output resolution collapses into flat grey.
    Upper half = vertical lines (across-page resolution).
    Lower half = horizontal lines (down-page resolution).
    """
    c.save()
    c.gray(0.0)
    c.text(x, y + h + 11, 9,
           "RESOLUTION -- finest block still showing separate lines is your "
           "real output resolution", font="F2")
    c.text(x, y + h + 2, 7,
           "top half = vertical lines (across page)   "
           "bottom half = horizontal lines (down page)")

    targets = [150, 300, 600, 1200]
    gap = 8.0
    bw = (w - gap * (len(targets) - 1)) / len(targets)

    for i, dpi in enumerate(targets):
        bx = x + i * (bw + gap)
        period = 2.0 * 72.0 / dpi
        lwid = period / 2.0
        half = h / 2.0

        c.stroke_gray(0.0)
        c.lw(lwid)
        for j in range(int(bw / period)):
            lx = bx + j * period + lwid / 2.0
            c.line(lx, y + half + 1.5, lx, y + h)
        for j in range(int((half - 1.5) / period)):
            ly = y + j * period + lwid / 2.0
            c.line(bx, ly, bx + bw, ly)

        c.gray(0.0)
        c.text(bx, y - 10, 10, f"{dpi} dpi", font="F2")

    c.stroke_gray(0.55)
    c.lw(0.4)
    c.rect_stroke(x - 3, y - 3, w + 6, h + 6)
    c.restore()


def draw_black_compare(c, x, y, w, h):
    """
    The same fine detail drawn three ways. In an RGB raster all three
    collapse to the same pixels; any difference you see between this sheet
    printed in Colour mode and printed in Greyscale mode is the printer
    laying composite CMY+K down instead of pure K.
    """
    c.save()
    c.gray(0.0)
    c.text(x, y + h + 11, 9,
           "BLACK RENDERING -- fine detail in three colour spaces",
           font="F2")
    c.text(x, y + h + 2, 7,
           "colour fringing on these hairlines means composite CMY+K "
           "instead of pure K")

    blocks = [
        ("DeviceGray 0", lambda: c.gray(0.0)),
        ("DeviceRGB 0,0,0", lambda: c.rgb(0, 0, 0)),
        ("DeviceCMYK K=1", lambda: c.cmyk(0, 0, 0, 1)),
    ]
    gap = 10.0
    bw = (w - gap * (len(blocks) - 1)) / len(blocks)

    for i, (name, setcol) in enumerate(blocks):
        bx = x + i * (bw + gap)
        setcol()
        # a small hairline grid plus solid patch
        c.lw(0.24)                     # 1 px at 300 dpi
        for j in range(int(bw / 2.4)):
            lx = bx + j * 2.4
            c.line(lx, y + h * 0.45, lx, y + h)
        c.rect_fill(bx, y, bw * 0.45, h * 0.35)
        c.gray(0.0)
        c.text(bx, y - 10, 8, name, font="F2")

    c.stroke_gray(0.55)
    c.lw(0.4)
    c.rect_stroke(x - 3, y - 3, w + 6, h + 6)
    c.restore()


def draw_quality_block(c, x, y, w, h):
    """
    Banding detector. Inkjet quality modes differ mainly in pass count, and
    the artefact that exposes pass count is horizontal banding across a
    large flat mid-tone -- far more visible than anything in fine detail.
    A smooth gradient beside it shows where the transitions break up.
    """
    c.save()
    c.gray(0.0)
    c.text(x, y + h + 11, 9,
           "BANDING -- flat mid-tone and gradient; look for horizontal "
           "streaks across these", font="F2")

    flat_h = h * 0.55
    # 40% tone: the worst case for banding on most inkjets
    c.gray(0.60)
    c.rect_fill(x, y + h - flat_h, w * 0.48, flat_h)
    c.gray(0.0)
    c.text(x, y + h - flat_h - 9, 7, "flat 40% tone")

    # smooth gradient, 80 bands
    gx = x + w * 0.52
    gw = w * 0.48
    bands = 80
    for i in range(bands):
        c.gray(1.0 - i / (bands - 1.0))
        c.rect_fill(gx + i * (gw / bands), y + h - flat_h,
                    gw / bands + 0.4, flat_h)
    c.gray(0.0)
    c.text(gx, y + h - flat_h - 9, 7, "gradient 0-100%")

    # solid black bar: shows pass overlap and ink laydown
    c.gray(0.0)
    c.rect_fill(x, y, w, h * 0.22)
    c.restore()


def draw_bleed_bands(c, w, h):
    """
    Solid bands running hard against every MediaBox edge. Under borderless
    they should reach the paper edge with no white strip; otherwise the
    white strip you see is the printer's unprintable border.
    """
    c.save()
    band = 9 * MM
    c.rgb(0, 0.68, 0.94)   # top
    c.rect_fill(0, h - band, w, band)
    c.rgb(0.93, 0.11, 0.55)  # bottom
    c.rect_fill(0, 0, w, band)
    c.rgb(1.0, 0.85, 0.0)   # left
    c.rect_fill(0, 0, band, h)
    c.gray(0.0)             # right
    c.rect_fill(w - band, 0, band, h)
    c.restore()


def draw_color_bars(c, x, y, w, h):
    c.save()
    c.gray(0.0)
    c.text(x, y + h + 4, 9, "Nozzle check", font="F2")
    bars = [("C", (0, 1, 1)), ("M", (1, 0, 1)), ("Y", (1, 1, 0)),
            ("K", (0, 0, 0))]
    bw = w / len(bars)
    for i, (name, (r, g, b)) in enumerate(bars):
        c.rgb(r, g, b)
        c.rect_fill(x + i * bw, y, bw, h)
        c.gray(0.0)
        c.text(x + i * bw + bw / 2 - 3, y - 9, 8, name, font="F2")
    c.restore()


def draw_text_ladder(c, x, y):
    c.save()
    c.gray(0.0)
    c.text(x, y, 9, "Text legibility", font="F2")
    yy = y - 13
    for size in (10, 8, 6, 5, 4):
        c.gray(0.0)
        c.text(x, yy, size,
               f"{size}pt  The quick brown fox jumps over the lazy dog 0123456789")
        yy -= size + 4.5
    c.restore()


def draw_header(c, w, h, title, label):
    c.save()
    top = h - 26 * MM
    c.gray(0.0)
    c.text(24 * MM, top, 15, title, font="F2")
    if label:
        c.text(24 * MM, top - 15, 11, label, font="F2")
    c.stroke_gray(0.0)
    c.lw(0.6)
    c.line(24 * MM, top - 21, w - 24 * MM, top - 21)
    c.restore()


# ------------------------------------------------------------- assembly

def build_pdf(width_pt, height_pt, title, label, focus="margin"):
    c = Content()
    w, h = width_pt, height_pt

    # Bleed bands go down first so the ladders and brackets stay readable
    # on top of them.
    if focus == "bleed":
        draw_bleed_bands(c, w, h)

    draw_margin_ladders(c, w, h)
    draw_corner_brackets(c, w, h)
    draw_header(c, w, h, title, label)

    x = 24 * MM
    iw = w - 48 * MM

    if focus == "quality":
        # Quality modes show up in banding, not in fine detail, so the
        # banding block gets the space the line pairs would have used.
        draw_quality_block(c, x, h - 108 * MM, iw, 48 * MM)
        draw_linepairs(c, x, h - 140 * MM, iw, 22 * MM)
        draw_text_ladder(c, x, h - 152 * MM)
    elif focus == "bleed":
        # Keep the interior sparse: the answer is at the paper edges.
        draw_color_bars(c, x, h - 90 * MM, iw, 9 * MM)
        draw_scale_check(c, w, h, h - 105 * MM)
        draw_text_ladder(c, x, h - 118 * MM)
    else:
        draw_linepairs(c, x, h - 78 * MM, iw, 26 * MM)
        draw_black_compare(c, x, h - 108 * MM, iw, 20 * MM)
        draw_color_bars(c, x, h - 124 * MM, iw, 9 * MM)
        draw_scale_check(c, w, h, h - 140 * MM)
        draw_text_ladder(c, x, h - 152 * MM)

    stream = c.render()

    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (b"<< /Type /Page /Parent 2 0 R "
         + f"/MediaBox [0 0 {w:.4f} {h:.4f}] ".encode()
         + b"/Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> "
           b"/Contents 6 0 R >>"),
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica "
        b"/Encoding /WinAnsiEncoding >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold "
        b"/Encoding /WinAnsiEncoding >>",
        b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n"
        + stream + b"\nendstream",
    ]

    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for i, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + body + b"\nendobj\n"

    xref_at = len(out)
    n = len(objects) + 1
    out += f"xref\n0 {n}\n".encode() + b"0000000000 65535 f \n"
    for off in offsets:
        out += f"{off:010d} 00000 n \n".encode()
    out += (f"trailer\n<< /Size {n} /Root 1 0 R >>\nstartxref\n"
            f"{xref_at}\n".encode() + b"%%EOF\n")
    return bytes(out)


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--output", required=True)
    ap.add_argument("--size", default="A4", choices=sorted(PAGE_SIZES_MM))
    ap.add_argument("--label", default="",
                    help="settings string printed on the sheet so each "
                         "printout identifies itself")
    ap.add_argument("--title", default="Brother inkjet calibration")
    ap.add_argument("--focus", default="margin",
                    choices=["margin", "quality", "bleed"],
                    help="margin: full instrument set (default). "
                         "quality: large banding targets, for comparing "
                         "print-quality modes. "
                         "bleed: solid bands against every paper edge, for "
                         "testing borderless.")
    args = ap.parse_args()

    w_mm, h_mm = PAGE_SIZES_MM[args.size]
    pdf = build_pdf(w_mm * MM, h_mm * MM, args.title, args.label, args.focus)

    if args.output == "-":
        sys.stdout.buffer.write(pdf)
    else:
        with open(args.output, "wb") as fh:
            fh.write(pdf)
        print(f"wrote {args.output}  ({len(pdf)} bytes, {args.size} "
              f"{w_mm:.0f}x{h_mm:.0f} mm)")


if __name__ == "__main__":
    main()

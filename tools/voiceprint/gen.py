#!/usr/bin/env python3
"""Voiceprint: one long, luminous voice waveform for the Birdtown Flow Home hero.

A mirrored waveform of fine hairlines. It begins as a faint violet whisper
beneath the end of the greeting, swells across the right half in the
listening pill's 18-bar rhythm, burns cyan at its loudest and trails off in
warm gold, ending a text margin's width before the right edge.

Each hairline is a thin lens: a needle that is widest and whitest on the
centre line and tapers to a point at both tips, so its light falls off
smoothly instead of in stepped bands. A whiter, shorter lens sits inside
each one, and a white-hot sliver inside the loud ones.

Deterministic (fixed seed). Writes hero.html (the fragment) and preview.html
(the fragment twice, on white and on dark, with the mock text overlay).
"""
import math
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
SEED = 20261010

# ------------------------------------------------------------------ layout
W, H = 660, 150
YC = 78.0                       # centre line of the mirrored waveform
PITCH = 3.3                     # hairline pitch
X_FIRST, X_LAST = 199.0, 629.5  # first and last hairline (30 px right margin)

# the listening pill's 18-bar rhythm sets the large-scale envelope
RHYTHM = [5, 8, 13, 19, 11, 24, 17, 10, 21, 28, 15, 9, 19, 13, 7, 11, 6, 4]
RX0, RX1 = 324.0, 617.0         # x of the first and last rhythm sample
AMAX = 61.0                     # half-height of the loudest (28) sample, px
GAMMA = 1.25                    # >1 deepens valleys, lets the loudest peak lead
JITTER = 0.36                   # line-to-line variation (fraction of height)

# ------------------------------------------------------------------ palette
# icon orb spectrum, conic order from the top
SPECTRUM = ['#FEA964', '#F6CB4C', '#3CCB8A', '#2FB8E6',
            '#3082F8', '#6F54FB', '#B348ED', '#FB7896']
WARM_WHITE = '#FEFCF8'
ROOT_BG = ('linear-gradient(180deg, #263B6E 0%, #203569 10%, #0E183B 45%, '
           '#091231 100%)')

# colour along x, as (x, spectrum position): 0 orange, 1/8 gold, 2/8 green,
# 3/8 cyan, 4/8 blue, 5/8 indigo, 6/8 purple, 7/8 pink.  The voice rises out
# of the navy in violet, burns cyan at its loudest and ends in warm gold.
COLOUR_STOPS = [(300, 0.74), (376, 0.655), (411, 0.53), (480, 0.375),
                (531, 0.25), (583, 0.125), (626, 0.035)]

# ------------------------------------------------------------------ drawing
# every hairline is a body lens in its spectrum hue, a whiter core lens inside
# it and, on loud lines, a white-hot sliver inside that
BODY_W = (0.7, 1.85)    # body lens width on the centre line, quiet .. loud
BODY_EXP = 0.85         # how fast a line widens as it gets louder
BODY_FLOOR = (0.42, 0.55)  # body brightness of the quietest line: cool, warm
                           # (dim gold over navy turns grey, so warm stays up)
CORE = (0.6, 0.52, 0.5)  # core lens: height frac, width frac, whiten
HOT = (0.3, 0.3, 0.9)    # white-hot sliver inside loud lines
HOT_FROM = 0.4           # loudness at which the white-hot sliver appears
NCOL = 28                # colour buckets along the spectrum
LEVELS = [0.04, 0.07, 0.11, 0.16, 0.23, 0.32, 0.44, 0.58, 0.74, 0.88, 1.0]
BLOOM = dict(frac=0.62, width=2.4, opacity=0.5, whiten=0.2, blur=2.6)
END_FADE = (0.12, 26.0)  # brightness of the last line, length of the fade
HAZE = 0.28         # broad spectral haze behind the swell
WARM_CUT = (0.17, 0.27)  # hues below this get no glow (see coolness)
GLOWS = 0.5        # soft glows behind the loudest syllables


# ================================================================== colour
def _lin(c):
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _gam(c):
    c = min(1.0, max(0.0, c))
    v = 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
    return int(round(v * 255))


def hex2lab(h):
    r, g, b = (_lin(int(h[i:i + 2], 16)) for i in (1, 3, 5))
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l, m, s = (v ** (1 / 3) for v in (l, m, s))
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


def lab2hex(L, a, b):
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    bb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    return '#%02X%02X%02X' % (_gam(r), _gam(g), _gam(bb))


def mix(h1, h2, t):
    """perceptual (OKLab) mix of two hex colours."""
    a, b = hex2lab(h1), hex2lab(h2)
    return lab2hex(*(x + (y - x) * t for x, y in zip(a, b)))


def spectrum(u):
    """u: position around the orb, 0 = orange at the top, wraps at 1."""
    u = (u % 1.0) * len(SPECTRUM)
    i = int(u)
    return mix(SPECTRUM[i], SPECTRUM[(i + 1) % len(SPECTRUM)], u - i)


def rgba(h, a):
    return 'rgba(%d, %d, %d, %s)' % (int(h[1:3], 16), int(h[3:5], 16),
                                     int(h[5:7], 16), fmt(a, 2))


def coolness(u):
    """1 for the cool hues (green..violet), 0 for yellow-green, gold and
    orange: a warm glow over navy turns grey, so warm lines get none."""
    u %= 1.0
    if u >= 0.5:
        return 1.0 - smooth((u - 0.8) / 0.08)
    return smooth((u - WARM_CUT[0]) / (WARM_CUT[1] - WARM_CUT[0]))


# ================================================================== helpers
def fmt(v, nd=1):
    s = ('%.' + str(nd) + 'f') % v
    if '.' in s:
        s = s.rstrip('0').rstrip('.')
    if s in ('-0', ''):
        s = '0'
    return s


def num(v):
    """path number: one decimal, no leading zero."""
    s = fmt(round(v, 1))
    if s.startswith('0.'):
        s = s[1:]
    elif s.startswith('-0.'):
        s = '-' + s[2:]
    return s


def sep(v):
    """a path number with the separator it needs after a previous number."""
    s = num(v)
    return s if s.startswith('-') else ' ' + s


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else hi if v > hi else v


def smooth(t):
    t = clamp(t)
    return t * t * (3 - 2 * t)


def pchip(xs, ys):
    """Monotone cubic Hermite interpolation (smooth, no overshoot)."""
    n = len(xs)
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
    m = [0.0] * n
    m[0], m[-1] = d[0], d[-1]
    for i in range(1, n - 1):
        if d[i - 1] * d[i] <= 0:
            m[i] = 0.0
        else:
            w1 = 2 * h[i] + h[i - 1]
            w2 = h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])

    def f(x):
        if x <= xs[0]:
            return ys[0]
        if x >= xs[-1]:
            return ys[-1]
        k = 0
        while xs[k + 1] < x:
            k += 1
        t = (x - xs[k]) / h[k]
        t2, t3 = t * t, t * t * t
        return ((2 * t3 - 3 * t2 + 1) * ys[k] + (t3 - 2 * t2 + t) * h[k] * m[k]
                + (-2 * t3 + 3 * t2) * ys[k + 1] + (t3 - t2) * h[k] * m[k + 1])
    return f


# ================================================================== the voice
def dx():
    return (RX1 - RX0) / (len(RHYTHM) - 1)


def envelope():
    """a near-silent lead-in, the 18-bar rhythm, a short release."""
    d = dx()
    kx = [X_FIRST - 2, 262.0, RX0 - d] + [RX0 + i * d for i in range(len(RHYTHM))] \
        + [RX1 + 7.0, X_LAST + 3]
    kv = [0.2, 0.45, 2.2] + RHYTHM + [1.6, 0.5]
    return pchip(kx, kv)


def gaps():
    """short quiet gaps between "words": (centre x, half-width, depth)."""
    d = dx()
    return [(RX0 + 7.45 * d, 4.8, 0.9), (RX0 + 11.4 * d, 4.2, 0.86)]


def colour_pos(x):
    xs = [p[0] for p in COLOUR_STOPS]
    if x <= xs[0]:
        return COLOUR_STOPS[0][1]
    if x >= xs[-1]:
        return COLOUR_STOPS[-1][1]
    k = 0
    while xs[k + 1] < x:
        k += 1
    (x0, u0), (x1, u1) = COLOUR_STOPS[k], COLOUR_STOPS[k + 1]
    return u0 + (u1 - u0) * (x - x0) / (x1 - x0)


def presence(x):
    """0..1 visibility: nothing under most of the greeting, a whisper under
    its last word, full strength across the swell, easing off at the end."""
    a = smooth((x - X_FIRST + 3) / 112.0) ** 1.5
    b = 0.24 + 0.76 * smooth((x - 302.0) / 46.0)
    c = END_FADE[0] + (1 - END_FADE[0]) * smooth((X_LAST + 1 - x) / END_FADE[1])
    return a * b * c


def loudness(amp):
    """0..1: how loud a line is relative to the loudest syllable."""
    return clamp(amp / (0.72 * AMAX)) ** 0.8


def build_lines():
    rng = random.Random(SEED)
    xs = []
    x = X_FIRST
    while x <= X_LAST + 1e-6:
        xs.append(round(x, 1))
        x += PITCH
    r = [rng.random() for _ in xs]
    ph1, ph2 = rng.random() * 6.283, rng.random() * 6.283
    accent = random.Random(SEED + 1)
    acc = [accent.random() for _ in xs]
    floor = random.Random(SEED + 2)
    fl = [floor.random() for _ in xs]
    env = envelope()
    gp = gaps()
    lines = []
    for i, x in enumerate(xs):
        v = env(x)
        # speech-like detail between neighbouring lines
        jit = 1.0 - JITTER * (r[i] ** 1.5)
        jit *= 1.0 + 0.07 * math.sin(x / 9.3 * 6.283 + ph1)
        jit *= 1.0 + 0.05 * math.sin(x / 23.0 * 6.283 + ph2)
        if acc[i] < 0.07:
            jit *= 1.16          # a plosive: one line pokes above the rest
        elif acc[i] > 0.91:
            jit *= 0.72          # a momentary dip
        g = 1.0
        for gx, gw, depth in gp:
            dd = abs(x - gx) / gw
            if dd < 1:
                g *= 1.0 - depth * (0.5 + 0.5 * math.cos(math.pi * dd))
        amp = (max(v, 0.0) / 28.0) ** GAMMA * AMAX * jit * g
        pres = presence(x)
        if x < RX0:
            # the noise floor before the voice: tiny and irregular, so the
            # whisper reads as breath, not as a dotted rule
            amp += 1.7 * fl[i] ** 2 * smooth((x - X_FIRST) / 90.0)
            if x < RX0 - 30:
                pres *= 0.45 + 2.0 * fl[i] * (1 - fl[i])
        amp = max(amp, 0.5)
        lines.append((x, amp, colour_pos(x), pres, loudness(amp)))
    return lines


# ================================================================== drawing
def level(p):
    """snap a 0..1 brightness to the nearest of LEVELS (log spacing)."""
    if p < LEVELS[0] * 0.6:
        return 0.0
    lp = math.log(p)
    return min(LEVELS, key=lambda q: abs(math.log(q) - lp))


def lens_path(items):
    """[(x, half-height, width)] -> one compact relative path of thin
    vertical lenses, pointed at both tips and widest on the centre line."""
    out = []
    cx = cy = None
    for x, a, w in items:
        a = max(round(a, 1), 0.4)
        x0 = round(x, 1)
        y0 = round(YC - a, 1)
        c = max(round(w, 1), 0.2)          # control offset = lens width
        if cx is None:
            out.append('M%s %s' % (num(x0), num(y0)))
        else:
            out.append('m%s%s' % (num(x0 - cx), sep(y0 - cy)))
        out.append('q%s %s 0 %sq-%s-%s 0-%s' % (num(c), num(a), num(2 * a),
                                                num(c), num(a), num(2 * a)))
        cx, cy = x0, y0
    return ''.join(out)


def stroke_path(items, frac):
    """[(x, amp)] -> compact relative path of mirrored vertical strokes."""
    out = []
    cx = cy = None
    for x, amp in items:
        h = max(amp * frac, 0.05)
        x0 = round(x, 1)
        y0 = round(YC - h, 1)
        y1 = round(YC + h, 1)
        if cx is None:
            out.append('M%s %s' % (num(x0), num(y0)))
        else:
            out.append('m%s%s' % (num(x0 - cx), sep(y0 - cy)))
        out.append('v%s' % num(y1 - y0))
        cx, cy = x0, y1
    return ''.join(out)


def svg_open(style):
    return ('<svg width="660" height="150" viewBox="0 0 660 150" '
            'style="position: absolute; left: 0; top: 0;%s">' % style)


def body_width(loud):
    return BODY_W[0] + (BODY_W[1] - BODY_W[0]) * loud ** BODY_EXP


def svg_waveform(lines):
    layers = []
    # {brightness level: {colour bucket: [(x, half-height, width)]}} per layer
    body, core, hot = {}, {}, {}
    for x, amp, u, pres, loud in lines:
        cq = round(u * NCOL) / NCOL
        w = body_width(loud)
        floor = BODY_FLOOR[0] + (BODY_FLOOR[1] - BODY_FLOOR[0]) * (1 - coolness(u))
        pb = level(pres * (floor + (1 - floor) * loud))
        if pb > 0:
            body.setdefault(pb, {}).setdefault(cq, []).append((x, amp, w))
        pc = level(pres * (0.22 + 0.78 * loud))
        if pc > 0 and amp * CORE[0] >= 0.8:
            core.setdefault(pc, {}).setdefault(cq, []).append(
                (x, amp * CORE[0], w * CORE[1]))
        ph = level(pres * clamp((loud - HOT_FROM) / (1 - HOT_FROM)) ** 1.2)
        if ph > 0:
            hot.setdefault(ph, {}).setdefault(cq, []).append(
                (x, amp * HOT[0], w * HOT[1]))
    for buckets, whiten, op in ((body, 0.0, 0.95), (core, CORE[2], 0.9),
                                (hot, HOT[2], 0.95)):
        for pq in sorted(buckets):
            layers.append('<g fill-opacity="%s">' % fmt(op * pq, 3))
            for cq in sorted(buckets[pq]):
                col = spectrum(cq)
                if whiten:
                    col = mix(col, WARM_WHITE, whiten)
                layers.append('<path fill="%s" d="%s"></path>'
                              % (col, lens_path(buckets[pq][cq])))
            layers.append('</g>')
    return svg_open('') + ''.join(layers) + '</svg>'


def svg_bloom(lines):
    """a soft, blurred copy of the loud lines: light that follows each line."""
    b = BLOOM
    buckets = {}
    for x, amp, u, pres, loud in lines:
        if x > 300 and amp > 6:
            buckets.setdefault(round(u * 16) / 16, []).append((x, amp))
    out = []
    for cq in sorted(buckets):
        cool = coolness(cq)
        col = mix(spectrum(cq), WARM_WHITE, b['whiten'])
        out.append('<path stroke="%s" stroke-opacity="%s" d="%s"></path>'
                   % (col, fmt(0.1 + 0.9 * cool, 2),
                      stroke_path(buckets[cq], b['frac'])))
    return (svg_open(' filter: blur(%spx); opacity: %s; mix-blend-mode: screen;'
                     % (fmt(b['blur']), fmt(b['opacity'], 2)))
            + '<g fill="none" stroke-linecap="round" stroke-width="%s">%s</g></svg>'
            % (fmt(b['width']), ''.join(out)))


def haze_divs():
    """a broad, cool spectral haze behind the swell, strongest where loud."""
    if HAZE <= 0:
        return ''
    env = envelope()
    x0, x1 = 322.0, 622.0
    stops = []
    for k in range(9):
        x = x0 + k * (x1 - x0) / 8.0
        u = colour_pos(x)
        a = coolness(u) * (0.4 + 0.6 * clamp(env(x) / 24.0))
        stops.append('%s %s%%' % (rgba(spectrum(u), round(a, 2)), fmt(k * 12.5)))
    return ('<div style="position: absolute; left: %spx; top: %spx; width: %spx; '
            'height: 70px; border-radius: 50%%; background: linear-gradient(90deg, %s); '
            'filter: blur(24px); opacity: %s; mix-blend-mode: screen;"></div>'
            % (fmt(x0), fmt(YC - 35), fmt(x1 - x0), ', '.join(stops), fmt(HAZE, 2)))


def glow_divs():
    """soft light behind the loud syllables, in their own (cool) hues."""
    out = []
    d = dx()
    for i, v in enumerate(RHYTHM):
        if v < 19:
            continue
        x = RX0 + i * d
        u = colour_pos(x)
        col = mix(spectrum(u), WARM_WHITE, 0.15)
        hh = (v / 28.0) ** GAMMA * AMAX * 0.9
        w = d * 2.4
        a = GLOWS * coolness(u) * (v / 28.0) ** 1.5
        out.append(
            '<div style="position: absolute; left: %spx; top: %spx; width: %spx; '
            'height: %spx; border-radius: 50%%; background: radial-gradient(closest-side, '
            '%s, %s); filter: blur(12px); mix-blend-mode: screen;"></div>'
            % (fmt(x - w / 2), fmt(YC - hh), fmt(w), fmt(2 * hh),
               rgba(col, a), rgba(col, 0)))
    return ''.join(out)


def fragment():
    lines = build_lines()
    art = haze_divs() + glow_divs() + svg_bloom(lines) + svg_waveform(lines)
    return ('<div style="position: relative; width: 660px; height: 150px; '
            'box-sizing: border-box; overflow: hidden; border-radius: 18px; '
            'background: %s; box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.06);">\n'
            '  <div aria-hidden="true" style="position: absolute; left: 0; top: 0; '
            'width: 660px; height: 150px;">%s</div>\n</div>' % (ROOT_BG, art))


# ================================================================== preview
OVERLAY = '''<div style="position: absolute; left: 28px; top: 0; bottom: 0; display: flex; flex-direction: column; justify-content: center; gap: 8px; font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', Inter, Arial, sans-serif;">
  <h1 style="margin: 0; font-size: 28px; font-weight: 600; line-height: 34px; letter-spacing: -0.015em; color: #FFFFFF;">Good evening, Levi</h1>
  <p style="margin: 0; display: flex; align-items: center; gap: 8px; height: 20px; font-size: 14.5px; line-height: 20px; color: rgba(255, 255, 255, 0.72);">
    <span style="display: flex; align-items: center; gap: 1.5px; height: 14px;"><span style="display: block; width: 2px; border-radius: 1px; background: #FEFCF8; height: 4px;"></span><span style="display: block; width: 2px; border-radius: 1px; background: #FEFCF8; height: 8px;"></span><span style="display: block; width: 2px; border-radius: 1px; background: #FEFCF8; height: 12px;"></span><span style="display: block; width: 2px; border-radius: 1px; background: #FEFCF8; height: 8px;"></span><span style="display: block; width: 2px; border-radius: 1px; background: #FEFCF8; height: 4px;"></span></span>
    <span style="display: flex; align-items: center; gap: 5px;"><span>Hold</span><span style="display: flex; align-items: center; justify-content: center; height: 20px; box-sizing: border-box; padding: 1px 6px; border-radius: 6px; background: rgba(255, 255, 255, 0.12); border: 1px solid rgba(255, 255, 255, 0.22); font-size: 11.5px; font-weight: 500; line-height: 16px; color: #FFFFFF;">fn</span><span>anywhere to dictate.</span></span>
  </p>
</div>'''


def with_overlay(frag, text=None):
    assert frag.endswith('</div>')
    ov = OVERLAY if text is None else OVERLAY.replace('Good evening, Levi', text)
    return frag[:-len('</div>')] + ov + '\n</div>'


def preview(frag):
    shadow = '0 1px 2px rgba(9, 18, 49, 0.10), 0 10px 28px rgba(9, 18, 49, 0.14)'
    hero = with_overlay(frag)
    return ('<!doctype html>\n<html><head><meta charset="utf-8"><title>Voiceprint</title></head>'
            '<body style="margin: 0;">\n'
            '<div style="background: #FFFFFF; padding: 56px; width: 660px;">'
            '<div style="width: 660px; height: 150px; border-radius: 18px; box-shadow: %s;">'
            '%s</div></div>\n'
            '<div style="background: #1B1D24; padding: 56px; width: 660px;">%s</div>\n'
            '</body></html>\n' % (shadow, hero, hero))


def main():
    frag = fragment()
    with open(os.path.join(HERE, 'hero.html'), 'w', encoding='utf-8') as f:
        f.write(frag)
    with open(os.path.join(HERE, 'preview.html'), 'w', encoding='utf-8') as f:
        f.write(preview(frag))
    print('hero.html', len(frag.encode('utf-8')), 'bytes')


if __name__ == '__main__':
    main()

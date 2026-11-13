#!/usr/bin/env python3
"""Erzeugt Level-Dateien aus Koordinaten. Ein Hilfsmittel für den Entwurf.

Aufruf: python3 tools/make_levels.py
Die Wellen stehen unten in dieser Datei. Die erzeugten JSON-Dateien dürfen auch von Hand geändert werden,
ein erneuter Aufruf überschreibt sie aber.
"""
import json, re

W, H = 18, 10


def new_grid():
    g = [[':' for _ in range(W)] for _ in range(H)]
    for x in range(W): g[0][x] = g[H - 1][x] = '#'
    for y in range(H): g[y][0] = g[y][W - 1] = '#'
    return g


def line(g, x0, y0, x1, y1):
    for x in range(min(x0, x1), max(x0, x1) + 1):
        for y in range(min(y0, y1), max(y0, y1) + 1): g[y][x] = '.'


def place(g, ch, cells, near_tunnel=False):
    for x, y in cells:
        assert g[y][x] == ':', (ch, x, y, g[y][x])
        if near_tunnel:
            assert any(g[y + dy][x + dx] in '.EH' for dy in (-1, 0, 1) for dx in (-1, 0, 1)), ('kein Stollen bei', x, y)
        g[y][x] = ch


def group(enemy, count, interval, delay=0.0, entrance=0):
    d = {"enemy": enemy, "count": count, "interval": interval}
    if delay: d["delay"] = delay
    if entrance: d["entrance"] = entrance
    return d


def write(name, level, g):
    level["grid"] = [''.join(r) for r in g]
    s = json.dumps(level, indent=2, ensure_ascii=False)
    s = re.sub(r'\{\s*\n\s*"enemy": ([^}]*?)\n\s*\}', lambda m: '{"enemy": ' + re.sub(r'\s*\n\s*', ' ', m.group(1)) + '}', s)
    open(f'data/levels/{name}.json', 'w').write(s + "\n")
    print(name)
    print('\n'.join(level["grid"]))


MINION, WARRIOR, ROGUE, MAGE = "skeleton_minion", "skeleton_warrior", "skeleton_rogue", "skeleton_mage"

# --- Level 2: Die Erzader -------------------------------------------------
g = new_grid()
line(g, 0, 4, 9, 4); line(g, 9, 4, 9, 7); line(g, 9, 7, 16, 7)      # Hauptweg
line(g, 9, 2, 9, 4); line(g, 9, 2, 14, 2)                           # alter Seitenstollen, Sackgasse
g[4][0] = 'E'; g[7][16] = 'H'
place(g, '*', [(4, 1), (12, 4), (6, 5)])
place(g, 'o', [(2, 3), (5, 3), (7, 3), (3, 5), (8, 5), (10, 5), (8, 1), (11, 1), (10, 3), (13, 3), (11, 6), (13, 6), (15, 5), (11, 8), (14, 8), (8, 8)])
write('level_02', {
    "name_key": "LEVEL_02_NAME", "hint_key": "HINT_LEVEL_02", "start_gold": 220, "lives": 20, "wave_pause": 10.0,
    "towers": ["crossbow", "sling", "runestone"],
    "waves": [
        {"reward": 25, "groups": [group(MINION, 8, 1.0)]},
        {"reward": 30, "groups": [group(MINION, 14, 0.7)]},
        {"reward": 35, "groups": [group(WARRIOR, 6, 1.8), group(ROGUE, 5, 1.0, 4.0)]},
        {"reward": 40, "groups": [group(WARRIOR, 12, 1.2)]},
        {"reward": 45, "groups": [group(WARRIOR, 16, 0.9), group(ROGUE, 12, 0.6, 2.0)]},
        {"reward": 50, "groups": [group(WARRIOR, 30, 0.6)]},
        {"reward": 0, "groups": [group(WARRIOR, 50, 0.42), group(ROGUE, 24, 0.3, 3.0), group(MINION, 40, 0.25, 6.0)]},
    ]}, g)

# --- Level 3: Zwei Tore ---------------------------------------------------
g = new_grid()
line(g, 0, 2, 7, 2); line(g, 7, 2, 7, 5)        # oberes Tor
line(g, 0, 7, 7, 7); line(g, 7, 5, 7, 7)        # unteres Tor
line(g, 7, 5, 12, 5); line(g, 12, 5, 12, 7); line(g, 12, 7, 16, 7)
g[2][0] = 'E'; g[7][0] = 'E'; g[7][16] = 'H'
place(g, '*', [(3, 4), (10, 3), (14, 5)])
place(g, 'o', [(2, 1), (5, 1), (1, 3), (5, 3), (8, 3), (6, 4), (2, 6), (5, 6), (8, 6), (2, 8), (5, 8), (9, 4), (11, 4), (10, 6), (13, 4), (11, 6), (13, 6), (13, 8), (15, 6), (15, 8)], near_tunnel=True)
write('level_03', {
    "name_key": "LEVEL_03_NAME", "hint_key": "HINT_LEVEL_03", "start_gold": 300, "lives": 20, "wave_pause": 10.0,
    "towers": ["crossbow", "sling", "runestone", "forge"],
    "waves": [
        {"reward": 30, "groups": [group(MINION, 8, 1.0), group(MINION, 6, 1.2, 6.0, 1)]},
        {"reward": 35, "groups": [group(ROGUE, 6, 1.0), group(WARRIOR, 4, 1.8, 2.0, 1)]},
        {"reward": 40, "groups": [group(WARRIOR, 6, 1.5), group(MAGE, 1, 4.0, 3.0), group(MINION, 12, 0.7, 2.0, 1)]},
        {"reward": 45, "groups": [group(WARRIOR, 8, 1.2, 0.0, 1), group(MAGE, 2, 3.0, 2.0, 1), group(ROGUE, 10, 0.6, 5.0)]},
        {"reward": 50, "groups": [group(WARRIOR, 10, 1.0), group(WARRIOR, 10, 1.0, 0.0, 1), group(MAGE, 2, 3.0, 3.0)]},
        {"reward": 55, "groups": [group(ROGUE, 18, 0.45), group(MINION, 26, 0.4, 0.0, 1), group(MAGE, 3, 2.5, 4.0, 1)]},
        {"reward": 60, "groups": [group(WARRIOR, 16, 0.8), group(WARRIOR, 16, 0.8, 0.0, 1), group(MAGE, 3, 2.5, 3.0), group(MAGE, 3, 2.5, 3.0, 1)]},
        {"reward": 0, "groups": [group(WARRIOR, 22, 0.65), group(WARRIOR, 22, 0.65, 0.0, 1), group(ROGUE, 20, 0.35, 5.0), group(MAGE, 5, 2.0, 4.0, 1)]},
    ]}, g)

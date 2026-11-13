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


def write(name, level, g, scale=1.0):
    """scale vervielfacht die Zahl der Gegner in allen Wellen: der Regler für die Schwierigkeit eines Levels."""
    level["grid"] = [''.join(r) for r in g]
    if scale != 1.0:
        for wave in level["waves"]:
            for grp in wave["groups"]:
                if grp["enemy"] != KING:
                    grp["count"] = max(1, round(grp["count"] * scale))
    s = json.dumps(level, indent=2, ensure_ascii=False)
    s = re.sub(r'\{\s*\n\s*"enemy": ([^}]*?)\n\s*\}', lambda m: '{"enemy": ' + re.sub(r'\s*\n\s*', ' ', m.group(1)) + '}', s)
    open(f'data/levels/{name}.json', 'w').write(s + "\n")
    print(name)
    print('\n'.join(level["grid"]))


MINION, WARRIOR, ROGUE, MAGE = "skeleton_minion", "skeleton_warrior", "skeleton_rogue", "skeleton_mage"
GUARD, KING = "skeleton_guard", "bone_king"

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

# --- Level 4: Der Knochenkönig --------------------------------------------
g = new_grid()
# Ein langer Weg in drei Bahnen, mit einer Abkürzung, die sich zuschütten lässt.
line(g, 0, 1, 15, 1); line(g, 15, 1, 15, 4); line(g, 2, 4, 15, 4); line(g, 2, 4, 2, 7); line(g, 2, 7, 16, 7)
g[1][0] = 'E'; g[7][16] = 'H'
place(g, '*', [(8, 6), (12, 3), (5, 3)])
place(g, 'o', [(2, 2), (5, 2), (8, 2), (11, 2), (14, 2), (16, 3), (14, 3), (9, 3), (3, 3), (1, 5), (3, 5), (6, 5), (10, 5), (13, 5), (4, 6), (11, 6), (14, 6), (4, 8), (8, 8), (12, 8), (15, 8)], near_tunnel=True)
write('level_04', {
    "name_key": "LEVEL_04_NAME", "hint_key": "HINT_LEVEL_04", "start_gold": 320, "lives": 20, "wave_pause": 10.0,
    "towers": ["crossbow", "sling", "runestone", "forge", "bomb", "shieldwall"],
    "waves": [
        {"reward": 35, "groups": [group(MINION, 12, 0.8)]},
        {"reward": 40, "groups": [group(WARRIOR, 8, 1.3), group(ROGUE, 6, 0.8, 5.0)]},
        {"reward": 45, "groups": [group(GUARD, 5, 2.0), group(MINION, 16, 0.5, 3.0)]},
        {"reward": 50, "groups": [group(GUARD, 8, 1.5), group(MAGE, 2, 4.0, 4.0), group(ROGUE, 10, 0.6, 8.0)]},
        {"reward": 55, "groups": [group(WARRIOR, 20, 0.7), group(GUARD, 8, 1.4, 4.0), group(MAGE, 3, 3.0, 6.0)]},
        {"reward": 60, "groups": [group(GUARD, 16, 1.0), group(ROGUE, 20, 0.4, 5.0), group(MAGE, 4, 3.0, 5.0)]},
        {"reward": 0, "groups": [group(KING, 1, 1.0), group(GUARD, 10, 2.5, 5.0), group(WARRIOR, 20, 1.2, 8.0)]},
    ]}, g)

ALL = ["crossbow", "sling", "runestone", "forge", "bomb", "shieldwall"]

# --- Level 5: Die Kreuzung ------------------------------------------------
g = new_grid()
line(g, 0, 1, 8, 1); line(g, 8, 1, 8, 4)        # oberes Tor
line(g, 0, 8, 8, 8); line(g, 8, 4, 8, 8)        # unteres Tor
line(g, 8, 4, 16, 4)                            # gemeinsamer, kurzer Weg zum Herz
g[1][0] = 'E'; g[8][0] = 'E'; g[4][16] = 'H'
place(g, '*', [(4, 3), (4, 6), (12, 2), (12, 6)])
place(g, 'o', [(2, 2), (5, 2), (7, 2), (9, 2), (2, 7), (5, 7), (7, 7), (9, 7), (7, 4), (7, 5), (9, 3), (9, 5), (9, 6), (11, 3), (11, 5), (13, 3), (13, 5), (15, 3), (15, 5), (10, 3)], near_tunnel=True)
write('level_05', {
    "name_key": "LEVEL_05_NAME", "hint_key": "HINT_LEVEL_05", "start_gold": 380, "lives": 20, "wave_pause": 10.0, "towers": ALL,
    "waves": [
        {"reward": 40, "groups": [group(MINION, 10, 0.9), group(MINION, 10, 0.9, 4.0, 1)]},
        {"reward": 45, "groups": [group(WARRIOR, 6, 1.5), group(ROGUE, 8, 0.7, 3.0, 1)]},
        {"reward": 50, "groups": [group(GUARD, 4, 2.2), group(WARRIOR, 8, 1.2, 0.0, 1), group(MAGE, 1, 1.0, 6.0, 1)]},
        {"reward": 55, "groups": [group(ROGUE, 14, 0.5), group(GUARD, 6, 1.8, 2.0, 1), group(MINION, 20, 0.4, 8.0)]},
        {"reward": 60, "groups": [group(WARRIOR, 14, 0.9), group(WARRIOR, 14, 0.9, 0.0, 1), group(MAGE, 2, 4.0, 3.0), group(MAGE, 2, 4.0, 5.0, 1)]},
        {"reward": 65, "groups": [group(GUARD, 10, 1.3), group(GUARD, 10, 1.3, 0.0, 1), group(ROGUE, 16, 0.4, 6.0)]},
        {"reward": 70, "groups": [group(WARRIOR, 24, 0.6), group(MINION, 40, 0.3, 0.0, 1), group(MAGE, 4, 3.0, 4.0), group(GUARD, 8, 1.5, 8.0, 1)]},
        {"reward": 0, "groups": [group(GUARD, 16, 1.0), group(GUARD, 16, 1.0, 0.0, 1), group(MAGE, 5, 2.5, 3.0), group(ROGUE, 24, 0.35, 8.0, 1)]},
    ]}, g)

# --- Level 6: Tiefe Adern -------------------------------------------------
g = new_grid()
line(g, 0, 5, 4, 5); line(g, 4, 2, 4, 5); line(g, 4, 2, 9, 2); line(g, 9, 2, 9, 7); line(g, 9, 7, 13, 7); line(g, 13, 3, 13, 7); line(g, 13, 3, 16, 3)
g[5][0] = 'E'; g[3][16] = 'H'
place(g, '*', [(2, 3), (7, 4), (11, 5), (15, 5), (6, 7)])
place(g, 'o', [(1, 4), (3, 4), (2, 6), (5, 3), (5, 5), (3, 1), (6, 1), (8, 1), (6, 3), (8, 3), (10, 3), (8, 5), (10, 5), (8, 6), (10, 8), (12, 8), (12, 6), (14, 6), (12, 4), (14, 4), (14, 2), (12, 2)], near_tunnel=True)
write('level_06', {
    "name_key": "LEVEL_06_NAME", "hint_key": "HINT_LEVEL_06", "start_gold": 340, "lives": 20, "wave_pause": 12.0, "towers": ALL,
    "rules": {"max_digs": 7},
    "waves": [
        {"reward": 40, "groups": [group(MINION, 14, 0.8)]},
        {"reward": 45, "groups": [group(ROGUE, 10, 0.8), group(WARRIOR, 6, 1.5, 4.0)]},
        {"reward": 50, "groups": [group(ROGUE, 16, 0.5), group(GUARD, 4, 2.0, 3.0)]},
        {"reward": 55, "groups": [group(WARRIOR, 16, 0.8), group(MAGE, 3, 3.0, 4.0), group(ROGUE, 12, 0.5, 10.0)]},
        {"reward": 60, "groups": [group(GUARD, 12, 1.2), group(ROGUE, 20, 0.4, 5.0)]},
        {"reward": 65, "groups": [group(WARRIOR, 30, 0.5), group(MAGE, 5, 2.5, 5.0), group(ROGUE, 20, 0.4, 12.0)]},
        {"reward": 70, "groups": [group(GUARD, 20, 0.9), group(MAGE, 5, 2.5, 4.0), group(ROGUE, 30, 0.3, 10.0)]},
        {"reward": 0, "groups": [group(KING, 1, 1.0), group(GUARD, 14, 1.8, 6.0), group(ROGUE, 30, 0.5, 10.0)]},
    ]}, g)

# --- Level 7: Belagerung --------------------------------------------------
g = new_grid()
line(g, 0, 2, 5, 2); line(g, 5, 2, 5, 4)        # Westtor oben
line(g, 0, 7, 5, 7); line(g, 5, 4, 5, 7)        # Westtor unten
line(g, 8, 0, 8, 4)                             # Nordtor
line(g, 5, 4, 12, 4); line(g, 12, 4, 12, 6); line(g, 12, 6, 16, 6)
g[2][0] = 'E'; g[7][0] = 'E'; g[0][8] = 'E'; g[6][16] = 'H'
place(g, '*', [(2, 4), (10, 2), (14, 3), (9, 7)])
place(g, 'o', [(2, 1), (4, 1), (2, 3), (4, 3), (6, 3), (2, 6), (4, 6), (2, 8), (4, 8), (6, 5), (6, 6), (7, 2), (9, 2), (7, 3), (9, 3), (7, 5), (9, 5), (11, 3), (11, 5), (13, 3), (13, 5), (11, 7), (13, 7), (15, 5), (15, 7)], near_tunnel=True)
write('level_07', {
    "name_key": "LEVEL_07_NAME", "hint_key": "HINT_LEVEL_07", "start_gold": 480, "lives": 20, "wave_pause": 12.0, "towers": ALL,
    "waves": [
        {"reward": 45, "groups": [group(MINION, 10, 0.9), group(MINION, 10, 0.9, 3.0, 1), group(MINION, 10, 0.9, 6.0, 2)]},
        {"reward": 50, "groups": [group(WARRIOR, 8, 1.2), group(ROGUE, 8, 0.7, 2.0, 2), group(WARRIOR, 8, 1.2, 5.0, 1)]},
        {"reward": 55, "groups": [group(GUARD, 5, 2.0, 0.0, 2), group(WARRIOR, 10, 1.0), group(MAGE, 2, 4.0, 4.0, 1), group(MINION, 16, 0.5, 4.0, 1)]},
        {"reward": 60, "groups": [group(ROGUE, 14, 0.5), group(ROGUE, 14, 0.5, 0.0, 1), group(GUARD, 8, 1.5, 3.0, 2)]},
        {"reward": 65, "groups": [group(WARRIOR, 16, 0.8), group(WARRIOR, 16, 0.8, 0.0, 1), group(WARRIOR, 16, 0.8, 0.0, 2), group(MAGE, 3, 3.0, 4.0, 2)]},
        {"reward": 70, "groups": [group(GUARD, 10, 1.2), group(GUARD, 10, 1.2, 0.0, 1), group(MAGE, 4, 3.0, 3.0, 2), group(ROGUE, 20, 0.4, 8.0, 2)]},
        {"reward": 75, "groups": [group(WARRIOR, 24, 0.6), group(GUARD, 12, 1.1, 0.0, 1), group(MINION, 50, 0.25, 0.0, 2), group(MAGE, 5, 2.5, 5.0)]},
        {"reward": 0, "groups": [group(GUARD, 16, 1.0), group(GUARD, 16, 1.0, 0.0, 1), group(GUARD, 16, 1.0, 0.0, 2), group(MAGE, 4, 3.0, 4.0), group(MAGE, 4, 3.0, 6.0, 1), group(ROGUE, 30, 0.3, 10.0, 2)]},
    ]}, g)

# --- Level 8: Der Thronsaal -----------------------------------------------
g = new_grid()
# Ein großer Bogen um den Saal. Die Gegner sind hier zäher als in allen anderen Levels.
line(g, 0, 1, 16, 1); line(g, 16, 1, 16, 5); line(g, 3, 5, 16, 5)
g[1][0] = 'E'; g[5][3] = 'H'
place(g, '*', [(6, 3), (11, 3), (8, 7), (13, 7)])
place(g, 'o', [(2, 2), (4, 2), (8, 2), (10, 2), (13, 2), (15, 2), (15, 3), (15, 4), (4, 4), (6, 4), (8, 4), (10, 4), (12, 4), (14, 4), (2, 4), (2, 6), (4, 6), (6, 6), (10, 6), (12, 6), (15, 6), (16, 6)], near_tunnel=True)
write('level_08', {
    "name_key": "LEVEL_08_NAME", "hint_key": "HINT_LEVEL_08", "start_gold": 560, "enemy_hp_scale": 1.0, "lives": 20, "wave_pause": 12.0, "towers": ALL,
    "waves": [
        {"reward": 50, "groups": [group(MINION, 24, 0.5), group(WARRIOR, 8, 1.2, 6.0)]},
        {"reward": 55, "groups": [group(ROGUE, 20, 0.5), group(GUARD, 6, 1.8, 4.0)]},
        {"reward": 60, "groups": [group(WARRIOR, 24, 0.6), group(MAGE, 4, 3.0, 4.0)]},
        {"reward": 65, "groups": [group(GUARD, 16, 1.0), group(ROGUE, 24, 0.4, 6.0), group(MAGE, 4, 3.0, 8.0)]},
        {"reward": 70, "groups": [group(KING, 1, 1.0), group(WARRIOR, 30, 0.7, 4.0)]},
        {"reward": 75, "groups": [group(GUARD, 24, 0.8), group(MAGE, 8, 2.0, 4.0), group(MINION, 60, 0.2, 10.0)]},
        {"reward": 80, "groups": [group(WARRIOR, 50, 0.4), group(GUARD, 20, 0.9, 5.0), group(ROGUE, 40, 0.3, 12.0), group(MAGE, 8, 2.0, 6.0)]},
        {"reward": 0, "groups": [group(KING, 2, 14.0), group(GUARD, 30, 1.0, 4.0), group(MAGE, 10, 2.5, 6.0), group(WARRIOR, 40, 0.6, 10.0)]},
    ]}, g)

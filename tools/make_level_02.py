#!/usr/bin/env python3
"""Erzeugt data/levels/level_02.json aus Koordinaten. Nur ein Hilfsmittel für den Entwurf."""
import json, re, sys
W, H = 18, 10
g = [[':' for _ in range(W)] for _ in range(H)]
for x in range(W): g[0][x] = g[H-1][x] = '#'
for y in range(H): g[y][0] = g[y][W-1] = '#'
def line(x0, y0, x1, y1):
    for x in range(min(x0, x1), max(x0, x1)+1):
        for y in range(min(y0, y1), max(y0, y1)+1): g[y][x] = '.'
# Hauptweg: Eingang links, durch die Mitte, dann nach unten zum Herz.
line(0, 4, 9, 4); line(9, 4, 9, 7); line(9, 7, 16, 7)
# Alter Seitenstollen als Sackgasse: nach oben und rechts.
line(9, 2, 9, 4); line(9, 2, 14, 2)
g[4][0] = 'E'; g[7][16] = 'H'
for x, y in [(4, 1), (12, 4), (6, 5)]: g[y][x] = '*'
for x, y in [(2, 3), (5, 3), (7, 3), (3, 5), (8, 5), (10, 5), (8, 1), (11, 1), (10, 3), (13, 3), (11, 6), (13, 6), (15, 5), (11, 8), (14, 8), (8, 8)]:
    assert g[y][x] == ':', (x, y); g[y][x] = 'o'
rows = [''.join(r) for r in g]
level = {"name_key": "LEVEL_02_NAME", "hint_key": "HINT_LEVEL_02", "start_gold": 220, "lives": 20, "wave_pause": 10.0,
 "towers": ["crossbow", "sling"], "grid": rows, "waves": json.load(open(sys.argv[1])) if len(sys.argv) > 1 else []}
s = json.dumps(level, indent=2, ensure_ascii=False)
s = re.sub(r'\{\s*\n\s*"enemy": ([^}]*?)\n\s*\}', lambda m: '{"enemy": ' + re.sub(r'\s*\n\s*', ' ', m.group(1)) + '}', s)
open('data/levels/level_02.json', 'w').write(s + "\n")
print('\n'.join(rows))

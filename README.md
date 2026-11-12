# Durnhal: Wacht der Tiefe

3D Tower Defense für Android. Ein Zwergenclan verteidigt seine Mine.

- Plan und Meilensteine: [`PLAN.md`](PLAN.md)
- Quellen und Lizenzen der Assets: [`ASSETS.md`](ASSETS.md)

## Stand
Meilenstein 2: zwei spielbare Levels mit Platzhalter-Grafik. Türme bauen und ausbauen, Stollen graben und zuschütten, Arbeiter an Erzadern, Gold und Erz, Deutsch und Englisch.

## Bedienung
- Ein Finger ziehen: Karte verschieben. Zwei Finger: zoomen.
- Leuchtenden Bauplatz antippen: Turm bauen. Gebauten Turm antippen: ausbauen oder verkaufen.
- Fels antippen: Stollen graben. Stollen antippen: zuschütten.
- Blaue Erzader antippen: Arbeiter einsetzen.
- Oben rechts: Ansicht drehen, Tempo, Pause, Menü.

## Test-APK aufs Gerät bringen
Die neueste Test-APK liegt immer unter diesem Link, ohne Anmeldung:

https://github.com/eragonapps/tower_defense/releases/download/test-latest/durnhal-debug.apk

Datei auf dem Gerät öffnen und die Installation aus unbekannter Quelle erlauben. Neue Versionen lassen sich über die alte installieren.

## Entwicklung
Benötigt Godot 4.7.2.

Tests ausführen:

```bash
godot --headless --import
```

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gexit
```

Screenshot einer Szene erzeugen (Szene, Ausgabedatei, Sprache):

```bash
godot --resolution 2340x1080 --path . -s tools/screenshot.gd -- res://scenes/main_menu.tscn menu.png de
```

Balancing-Bericht (Bots spielen jedes Level):

```bash
godot --headless -s tools/balance_report.gd
```

Die Spielwerte stehen in `data/towers.json`, `data/enemies.json`, `data/rules.json` und `data/levels/`.

# Durnhal: Wacht der Tiefe

3D Tower Defense für Android. Ein Zwergenclan verteidigt seine Mine.

- Plan und Meilensteine: [`PLAN.md`](PLAN.md)
- Quellen und Lizenzen der Assets: [`ASSETS.md`](ASSETS.md)

## Stand
Meilenstein 0: Grundgerüst mit Hauptmenü, Sprachumschaltung Deutsch/Englisch, automatischen Tests und Test-APK.

## Test-APK aufs Gerät bringen
1. Auf GitHub den Reiter **Actions** öffnen und den neuesten grünen Lauf von „CI" wählen.
2. Unten unter **Artifacts** `durnhal-debug-apk` herunterladen und entpacken.
3. Die Datei `durnhal-debug.apk` auf dem Gerät öffnen und die Installation aus unbekannter Quelle erlauben.

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

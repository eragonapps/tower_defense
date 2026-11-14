# Umsetzungsplan: Umbau im Endlosmodus, Schemen, Durchbruch, Zielwahl

Stand: 14.11.2026 · Status: **geplant, noch nicht umgesetzt**

Entschieden mit dem Auftraggeber:
- Alle vier Umbau-Bausteine: Bauplatz anlegen, Bauplatz abreißen, Turm versetzen, Veredeln.
- Neue Bauplätze gibt es **nur im Endlosmodus**.
- Durchbruch: ja, alle 10 Endlos-Wellen.
- Der Schemen nutzt das Geist-Modell aus dem Quaternius-Paket. Die Lizenz hat der Auftraggeber geprüft.
- Zielwahl je Turm: ja.

Reihenfolge der Umsetzung: 1 → 2 → 3 → 4 → 5 → 6. Nach jedem Schritt Tests grün, dann committen.

## 1. Zielwahl je Turm
**Spielkern (`scripts/core/sim.gd`)**
- `Tower.target_mode := "first"`. Erlaubt: `first` (kürzester Restweg, wie bisher), `strong` (meiste Lebenspunkte), `weak` (wenigste Lebenspunkte).
- `_pick_target` wertet den Modus aus. Die Vorliebe der Feuertürme für nicht brennende Gegner bleibt vorrangig.
- Neuer Befehl `set_target_mode(cell, mode) -> Result`. Bei Türmen der Art `aura` und `block` gibt es keine Zielwahl (`NOT_ALLOWED`).
- Beim Versetzen (Schritt 3) bleibt der Modus erhalten.

**Oberfläche:** Im Turmmenü ein Knopf „Ziel: Vorderster", der die drei Modi durchschaltet (`id` = `target`).
**Tests:** je Modus ein Test mit zwei Gegnern unterschiedlicher Stärke. Modus überlebt Ausbau und Spezialisierung.

## 2. Veredeln
- Nur für Türme auf höchster Stufe **mit** gewählter Spezialisierung. Überall erlaubt, nicht nur im Endlosmodus, weil es erst spät erreichbar ist.
- `Tower.refine := 0`. Jeder Kauf: Schaden und Brandschaden × 1,04 (multiplikativ je Stufe), bei `aura`- und `block`-Türmen ohne Schaden stattdessen Reichweite × 1,02.
- Preis in Gold: `refine_base` (150) × `refine_growth` (1,25) hoch `refine`. Beides als Regeln in `DEFAULT_RULES`.
- `refine_cost(tower)`, `can_refine(cell)`, `refine_tower(cell)`. `_refresh_stats` rechnet die Veredelung nach Spezialisierung und vor den Gaben ein.
- Verkauf erstattet Veredelung nicht (wie Erz).
- **Oberfläche:** Knopf „Veredeln (+4 %)\n188 Gold", Titel zeigt „· veredelt ×3".
- **Tests:** Preis steigt, Werte steigen, nicht ohne Spezialisierung, überlebt Gaben.

## 3. Turm versetzen
- Befehl `move_tower(from, to) -> Result`: `to` muss ein freier Bauplatz sein. Kosten: `move_cost` (60 Gold, Regel).
- Der Turm behält Stufe, Spezialisierung, Veredelung, Zielwahl und bezahlten Preis. Vom Schildwall gehaltene Gegner werden freigegeben, `held_ids` wird geleert.
- Signal `tower_moved(tower, from)`.
- **Oberfläche:** Knopf „Versetzen (60 Gold)" im Turmmenü. Danach Modus „Zielplatz wählen": Hinweis oben, freie Bauplätze pulsieren, Antippen eines freien Bauplatzes führt aus, jedes andere Antippen bricht ab. Zustand in `LevelView` (`_moving_from`).
- **Tests:** Werte bleiben, Gold wird abgezogen, belegter oder kein Bauplatz wird abgelehnt, gehaltene Gegner laufen weiter.

## 4. Bauplatz anlegen und abreißen (nur Endlosmodus)
- `can_create_slot(cell)`: nur wenn `endless`, Zelle ist `ROCK`, kein Grabauftrag darauf, keine Fackel-/Erz-Sonderfälle nötig (Erz ist eigener Zelltyp). Obergrenze `max_slots` (30, Regel) über alle `BUILD`-Zellen.
- Preis: `slot_gold` (300) und `slot_ore` (40), jeweils × `slot_growth` (1,5) hoch Anzahl schon angelegter Plätze (`slots_created`).
- `create_slot(cell)`: `grid.set_cell(cell, BUILD)`. Bauplätze sind nicht begehbar, der Weg ändert sich nicht. Signal `grid_changed`.
- `can_remove_slot(cell)`: nur wenn `endless`, Zelle ist `BUILD`, kein Turm darauf. Kostenlos, keine Erstattung. `remove_slot(cell)` setzt `ROCK`.
- Neue `Result`-Werte: `ONLY_ENDLESS`.
- **Oberfläche:** Fels-Menü bekommt im Endlosmodus einen zweiten Knopf „Bauplatz anlegen\n300 Gold · 40 Erz". Leerer Bauplatz bekommt im Endlosmodus „Abreißen". Level 1 hat Graben abgeschaltet: Im Endlosmodus wird dort trotzdem das Fels-Menü für den Bauplatz gezeigt, Graben bleibt aus.
- Bots: nicht nötig.
- **Tests:** nur im Endlosmodus, Preisstaffel, Obergrenze, Abreißen nur ohne Turm, nach Abreißen lässt sich dort graben, Weg bleibt gültig.

## 5. Neuer Gegner: Schemen
**Daten (`data/enemies.json`)**
- `wraith`: hp 160, speed 1.25, bounty 14, lives 1, size 0.9, `resist`: `{"blunt": 0.25, "fire": 0.25}`. Bolzen und Magie treffen voll.
- Übersetzungen `ENEMY_WRAITH` (Schemen / Wraith).
- Einsatz: in Level 5 bis 8 je ein bis zwei Gruppen in den späteren Wellen (über `tools/make_levels.py`, danach Balancing-Bericht und Tests). Im Endlosmodus zusätzlich: ab Endlos-Welle 6 hängt `_make_endless_groups` eine Schemen-Gruppe an, Anzahl 4 + Welle / 3, höchstens 14, an einem zufälligen Tor. Regel `endless_wraith_from` (6).

**Modell**
- Quelle: `Flying-20261112T140708Z-1-001.zip` aus der Git-Historie von `main` (Commit `9bbfd66`), Datei `Flying/glTF/Ghost.gltf` samt `Atlas_Monsters.png`. Abrufen mit `git show 9bbfd66:Flying-20261112T140708Z-1-001.zip`.
- Ablage: `assets/quaternius_monsters/Ghost.gltf` und Textur, dazu eine `LICENSE.txt` mit dem Hinweis: CC0 laut Autor, vom Auftraggeber am 14.11.2026 geprüft, im Archiv lag keine Lizenzdatei.
- Animationen im Modell: `Flying_Idle`, `Fast_Flying`, `Death`, `HitReact`. In `scripts/view/models.gd`: `"wraith": {"model": "quaternius_monsters/Ghost", "walk": "Flying_Idle", "death": "Death"}`. Die Figur schwebt 0,4 über dem Boden. Größe am Screenshot einstellen, das Modell hat einen anderen Maßstab als die KayKit-Figuren.
- `Models.character` sucht `handslot_*`, das Geist-Modell hat keine: unkritisch, Schleife läuft leer. Prüfen, ob `Models.DIR + path + ".glb"` passt: Das Modell ist `.gltf`. `Models.has` und `Models.instance` müssen beide Endungen kennen.
- `ASSETS.md` Abschnitt 7 ergänzen.

**Tests:** Flächenschaden und Feuer wirken zu 25 %, Bolzen voll. Daten gültig, Übersetzung da, Gegner kommt in einem Level vor. Balance-Tests neu laufen lassen.

## 6. Durchbruch
- Alle `endless_breach_every` (10, Regel) Endlos-Wellen, beim Start der Welle, nach dem Fluch.
- Ablauf in `sim.gd`, Funktion `_breach()`:
  1. Kandidaten: Randzellen des Rasters (ohne Ecken), die heute `GRANITE` sind und deren innere Nachbarzelle `ROCK` oder begehbar ist.
  2. Für jeden Kandidaten per Breitensuche durch `ROCK` den kürzesten Durchstich zur nächsten begehbaren Zelle suchen (höchstens 6 Felder). `BUILD`, `ORE` und `GRANITE` werden nicht durchbrochen.
  3. Kandidaten ausschließen, deren Weg zum Herz kürzer als 8 Schritte wäre. Unter den übrigen zufällig wählen (`_rng`).
  4. Randzelle wird `ENTRANCE`, die Durchstich-Zellen werden `TUNNEL`. `grid.entrances` ergänzen. Dafür in `MineGrid` eine Methode `add_entrance(cell)`.
  5. Kein Kandidat: kein Durchbruch, kein Fehler.
- Signal `breached(entrance_cell)`. `_make_endless_groups` verteilt die Gruppen danach auch auf das neue Tor, weil es schon zufällig über `grid.entrances` wählt.
- Türme, Arbeiter und Grabaufträge auf durchbrochenen Zellen gibt es nicht, weil nur `ROCK` durchbrochen wird. Laufende Grabaufträge auf diesen Zellen werden entfernt, das Gold erstattet.
- **Darstellung:** `LevelView` baut bei `breached` das Gelände neu, setzt ein Tor-Modell an die neue Zelle (vorhandenes `_build_entrance`), zeigt eine Meldung „Durchbruch! Ein neues Tor ist entstanden." und schwenkt die Kamera kurz dorthin. Staub-Effekt und Ton `fill`.
- **Tests:** nach 10 Endlos-Wellen ein Eingang mehr, Weg von dort zum Herz existiert und ist mindestens 8 lang, gleicher Zufallswert ergibt dieselbe Stelle, Raster ohne Kandidaten bleibt unverändert, Gegner erscheinen am neuen Tor. Zufallstest über alle acht Levels mit je 5 Zufallswerten.

## Übersetzungen
Alle neuen Texte in `locale/translations.csv` (Deutsch und Englisch). Vorsilben wie bisher (`HUD_`, `REASON_`, `ENEMY_`). Die Tests in `tests/unit/test_translations.gd` prüfen Vollständigkeit.

## Abnahme
- Alle Tests grün, lokal und auf GitHub.
- `tools/balance_report.gd`: Für jedes Level gewinnt weiter mindestens eine vernünftige Spielweise mit mehr als einem Drittel der Leben.
- `tools/endless_report.gd`: Bots kommen ähnlich weit wie vorher (9 bis 19 Wellen), höchstens 90 Gegner gleichzeitig.
- Screenshots: Turmmenü mit Zielwahl und Veredeln, Versetzen-Modus, neuer Bauplatz, Schemen, Durchbruch.
- Version auf 0.9.0, `PLAN.md` und `README.md` aktualisieren, diese Datei als umgesetzt markieren.

## Offene Punkte für die Umsetzung
- Maßstab und Schwebehöhe des Geist-Modells stehen erst nach einem Screenshot fest.
- Die Preise (Bauplatz 300 Gold und 40 Erz, Veredeln ab 150 Gold, Versetzen 60 Gold) sind Startwerte und werden nach dem Gerätetest angepasst.
- Ob der Schemen die Levels 5 bis 8 für die Bots zu schwer macht, zeigt erst der Balancing-Bericht.

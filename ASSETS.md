# Assets: Quellen und Lizenzen

Stand: 12.11.2026 · Status: **Kandidatenliste, noch kein Asset im Spiel verwendet.** Drei KayKit-Pakete und fünf hochgeladene Pakete sind geprüft.

Diese Datei nennt für jedes verwendete Asset die Quelle und die Lizenz. Sie wird bei jedem neuen oder getauschten Asset aktualisiert.

## 1. Ergebnis der Lizenzprüfung

Die drei geplanten Hauptquellen veröffentlichen ihre Pakete unter **CC0 1.0 (Public Domain)**. CC0 erlaubt die Nutzung in kommerziellen Projekten, auch im Play Store. Eine Namensnennung ist nicht nötig, wird aber von den Autoren gern gesehen. Wir nennen sie trotzdem im Spiel unter „Credits".

**Grenzen dieser Prüfung:**
- Für die drei KayKit-Pakete in Abschnitt 3a wurde die Lizenzdatei im Paket selbst gelesen.
- Für die drei Kenney-Pakete in Abschnitt 3b wurde ebenfalls die Lizenzdatei im Paket gelesen.
- Für Quaternius und das Free Mine Assets Pack liegt keine Lizenzdatei in den Archiven. Dort stützt sich die Angabe nur auf die Websuche, weil die Seiten der Anbieter aus der Cloud-Sitzung gesperrt sind.
- Verbindlich ist die Lizenzdatei, die in jedem heruntergeladenen Paket liegt. Sie wird beim Import geprüft und mit ins Repo gelegt.
- Das ist keine Rechtsberatung.
- CC0 gilt je Paket, nicht automatisch für alles von einem Autor. Kostenpflichtige Zusatzpakete und Pakete auf anderen Plattformen können andere Bedingungen haben.

## 2. Geprüfte Quellen

| Quelle | Lizenz | Kommerziell | Namensnennung | Besonderheit | Beleg |
|---|---|---|---|---|---|
| Kenney | CC0 1.0 | ja | freiwillig | Das Kenney-Logo darf nicht verwendet werden. | [kenney.nl/support](https://kenney.nl/support), [Tower Defense Kit](https://kenney.nl/assets/tower-defense-kit), [itch.io](https://kenney-assets.itch.io/tower-defense-kit) |
| Quaternius | CC0 1.0 | ja | freiwillig | Der FAQ-Text der eigenen Seite wurde nicht gefunden. Belegt durch Angaben des Autors auf Sketchfab und Reddit. | [Sketchfab](https://sketchfab.com/3d-models/ultimate-monsters-pack-fd72e114d119488da71fe3a16f216c4f), [OpenGameArt](https://opengameart.org/content/lowpoly-rpg-characters), [quaternius.com](https://quaternius.com/) |
| KayKit (Kay Lousberg) | CC0 1.0 | ja | freiwillig | Der Autor bittet darum, unveränderte Kopien nicht weiterzuverkaufen. Das betrifft uns nicht. | [Adventurers](https://kaylousberg.itch.io/kaykit-adventurers), [Skeletons](https://kaylousberg.itch.io/kaykit-skeletons), [Dungeon](https://kaylousberg.itch.io/kaykit-dungeon) |

## 3. Kandidaten-Pakete

### 3a. Aus der Cloud-Sitzung abrufbar und geprüft (12.11.2026)

Diese Pakete liegen offiziell auf GitHub. Sie wurden testweise heruntergeladen, die Lizenzdatei im Paket wurde gelesen. Sie sind noch **nicht im Repo**, weil sie zusammen etwa 345 MB groß sind. Ins Repo kommen ab Meilenstein 3 nur die Dateien, die das Spiel wirklich nutzt.

| Zweck | Paket | Quelle | Stand (Commit) | Lizenz laut `LICENSE.txt` im Paket | Inhalt (geprüft) |
|---|---|---|---|---|---|
| Stollen, Wände, Böden, Fackeln, Fässer, Truhen, Münzen | KayKit Dungeon Remastered 1.0 | [GitHub](https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0) | `b0ca9bd` | CC0, „free to use in personal, educational and commercial projects" | über 200 Modelle |
| Vorlage für Zwerge, Waffen, Schilde | KayKit Adventurers 1.0 | [GitHub](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0) | `672074b` | CC0, gleicher Wortlaut | 5 Figuren (Barbar, Ritter, Magier, Schurke, Schurke mit Kapuze), je 76 Animationen, dazu Armbrust, Äxte, Schilde, Krug |
| Gegner Kapitel 1 | KayKit Skeletons 1.0 | [GitHub](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0) | `15b62b9` | CC0, gleicher Wortlaut | 4 Skelette (Scherge, Krieger, Schurke, Magier), je 95 Animationen, dazu Waffen |

Alle Figuren haben dasselbe Skelett mit 41 Gelenken. Animationen für Laufen, Angreifen, Schießen, Treffer und Sterben sind enthalten.

### 3b. Von dir hochgeladen (Branch `main`, Stand 12.11.2026)

Die Archive liegen als ZIP-Dateien im Hauptordner von `main`. Sie wurden ausgepackt und geprüft, aber noch **nicht ins Projekt übernommen**. Ins Projekt kommen ab Meilenstein 3 nur die Dateien, die das Spiel wirklich nutzt.

| Zweck | Paket | Archiv in `main` | Lizenz | Inhalt (geprüft) |
|---|---|---|---|---|
| Geräusche | Kenney Impact Sounds 1.0 | `kenney_impact-sounds.zip` | CC0, `License.txt` im Paket gelesen | 130 Geräusche (Einschläge auf Holz, Metall, Stein, Schritte) |
| Geräusche | Kenney RPG Audio | `kenney_rpg-audio.zip` | CC0, `License.txt` im Paket gelesen | 52 Geräusche (Klingen, Türen, Schritte, Münzen) |
| Türme, Wegteile | Kenney Tower Defense Kit 2.1 | `kenney_tower-defense-kit.zip` | CC0, `License.txt` im Paket gelesen | 160 Modelle: Turmteile zum Stapeln, Bodenteile, UFO-Gegner. Stil bunt, Eignung für das düstere Spiel offen. |
| Monster | Quaternius Ultimate Monsters | `Big-….zip`, `Blob-….zip`, `Flying-….zip` | **keine Lizenzdatei in den Archiven.** Laut Autor CC0 (nur über Websuche belegt). | 50 animierte Monster. Brauchbar für das Thema: Orc, Orc_Skull, Demon, Yeti, Ghost, Ghost_Skull, Dragon, Goleling. Kein Goblin, keine Spinne. |
| Schienen, Loren, Stützbalken | Free Mine Assets Pack | `free_mine_assets.zip` | **keine Lizenzdatei im Archiv.** Laut OpenGameArt-Seite CC0 (nur über Websuche belegt). | 2 Blender-Dateien und 7 Texturen. Die Modelle müssen erst mit Blender in ein Format für Godot umgewandelt werden. |

Offen zu diesen Paketen:
- **Quaternius:** Im Download-Ordner des Pakets liegt neben `Big`, `Blob` und `Flying` üblicherweise eine Lizenzdatei. Bitte diese nachreichen, damit die Lizenz im Repo belegt ist.
- **Free Mine Assets Pack:** Als Beleg dient die Paketseite. Ein Bildschirmfoto der Seite mit der Lizenzangabe im Repo wäre der sauberste Nachweis.
- **Musik und Schrift** sind weiterhin offen.

## 4. Offener Punkt: Zwergen-Modelle

Die Suche hat **kein freies, animiertes Zwergen-Modell unter CC0** gefunden. Gefundene Zwergen-Modelle sind kostenpflichtig oder haben eine unklare Lizenz.

Optionen:
1. **KayKit-Figuren anpassen:** Die Abenteurer (z. B. Barbar, Ritter) gestaucht und breiter skaliert, mit Bart und Helm als Zubehör. Kostet nichts, CC0 erlaubt Veränderungen. Das Ergebnis ist ein Kompromiss.
2. **Zwergen-Paket kaufen:** etwa 15 bis 30 Euro. Die Lizenz muss den Einsatz in einem veröffentlichten Spiel erlauben und wird vor dem Kauf geprüft.
3. **Eigene Modelle** in Blender oder von einem Künstler. Beste Wiedererkennung, höchster Aufwand.

**Entschieden am 12.11.2026:** Start mit Option 1. Ein Wechsel ist später möglich, sobald passende Modelle gefunden sind.

Umsetzung: Barbar und Ritter als Grundfiguren, in der Höhe gestaucht und in der Breite gestreckt, mit Axt, Armbrust, Schild und Krug aus demselben Paket. Bärte sind im Paket nicht enthalten und müssen als einfaches Zusatzmodell entstehen. Wie gut das aussieht, zeigt erst ein Versuch in Meilenstein 3.

## 5. Sind die Assets später austauschbar?

Ja. Jede Turm- und Gegner-Szene bindet ihr Modell an genau einer Stelle ein. Für einen Tausch wird das neue Modell importiert, in der Szene eingesetzt und diese Datei aktualisiert. Die Spiellogik bleibt unberührt.

Mehr Aufwand entsteht nur bei animierten Figuren, wenn das neue Modell andere Animationsnamen oder ein anderes Skelett hat. Dafür bekommt jede Figur eine kleine Zuordnungstabelle (z. B. „laufen", „angreifen", „sterben").

## 6. Regeln für dieses Projekt

- Nur Assets mit geklärter Lizenz kommen ins Repo. Bevorzugt CC0, sonst CC-BY oder eine gekaufte Lizenz mit Beleg.
- Nicht erlaubt: Lizenzen mit „NC" (nicht kommerziell), „ND" (keine Bearbeitung) und Assets ohne Lizenzangabe.
- Jedes Paket liegt in einem eigenen Ordner `assets/<paket>/` zusammen mit seiner Lizenzdatei.
- Jedes Asset steht in der Tabelle in Abschnitt 7.
- Der Bildschirm „Credits und Lizenzen" im Spiel wird aus dieser Datei gepflegt.

## 7. Verwendete Assets

Noch keine. Die Tabelle wird ab Meilenstein 3 gefüllt.

| Datei oder Ordner im Repo | Verwendet für | Paket | Autor | Quelle (URL) | Lizenz | Heruntergeladen am | Verändert? |
|---|---|---|---|---|---|---|---|
| – | – | – | – | – | – | – | – |

## 8. Verwendete Software von Dritten

| Ordner im Repo | Was | Autor | Quelle | Lizenz | Im fertigen Spiel enthalten? |
|---|---|---|---|---|---|
| `addons/gut/` | GUT 9.7.1, Testrahmen | Butch Wesley | [github.com/bitwes/Gut](https://github.com/bitwes/Gut) | MIT, siehe `addons/gut/LICENSE.md` | nein, nur für Tests |
| – | Godot Engine 4.7.2 | Godot-Mitwirkende | [godotengine.org](https://godotengine.org/) | MIT | ja, Lizenzhinweis im Spiel nötig (kommt mit dem Credits-Bildschirm) |

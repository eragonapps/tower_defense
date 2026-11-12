# Assets: Quellen und Lizenzen

Stand: 12.11.2026 · Status: **Kandidatenliste, noch kein Asset im Repo**

Diese Datei nennt für jedes verwendete Asset die Quelle und die Lizenz. Sie wird bei jedem neuen oder getauschten Asset aktualisiert.

## 1. Ergebnis der Lizenzprüfung

Die drei geplanten Hauptquellen veröffentlichen ihre Pakete unter **CC0 1.0 (Public Domain)**. CC0 erlaubt die Nutzung in kommerziellen Projekten, auch im Play Store. Eine Namensnennung ist nicht nötig, wird aber von den Autoren gern gesehen. Wir nennen sie trotzdem im Spiel unter „Credits".

**Grenzen dieser Prüfung:**
- Die Prüfung lief über eine Websuche. Die Seiten der Anbieter selbst konnte die Cloud-Sitzung nicht direkt öffnen, weil sie vom Netzwerk der Umgebung gesperrt sind.
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

| Zweck | Paket | Quelle | Lizenz | Geprüft |
|---|---|---|---|---|
| Türme, Projektile, Wegteile | Tower Defense Kit | [Kenney](https://kenney.nl/assets/tower-defense-kit) | CC0 | über Suche |
| Stollen, Wände, Fackeln, Fässer | KayKit Dungeon Remastered | [KayKit](https://kaylousberg.itch.io/kaykit-dungeon) | CC0 | über Suche, Inhalt der neuen Fassung noch offen |
| Skelett-Gegner, animiert | KayKit Skeletons | [KayKit](https://kaylousberg.itch.io/kaykit-skeletons) | CC0 | über Suche |
| Spielfiguren, animiert | KayKit Adventurers | [KayKit](https://kaylousberg.itch.io/kaykit-adventurers) | CC0 | über Suche |
| Animationen für KayKit-Figuren | KayKit Character Animations | [OpenGameArt](https://opengameart.org/content/kaykit-character-animations) | CC0 | über Suche |
| Monster (Goblins, Spinnen u. a.) | Ultimate Monsters | [Quaternius](https://sketchfab.com/3d-models/ultimate-monsters-pack-fd72e114d119488da71fe3a16f216c4f) | CC0 | über Suche, genaue Monsterliste noch offen |
| Schienen, Loren, Stützbalken, Lampen | Free Mine Assets Pack | [OpenGameArt](https://opengameart.org/content/free-mine-assets-pack) | CC0 | über Suche, Stil und Qualität noch offen |
| Geräusche | Kenney Audio (z. B. RPG Audio, Impact Sounds) | [Kenney](https://kenney.nl/assets) | CC0 | **noch nicht geprüft** |
| Musik | noch offen | – | – | – |
| Schrift | noch offen (geplant: Schrift unter SIL Open Font License) | – | – | – |

## 4. Offener Punkt: Zwergen-Modelle

Die Suche hat **kein freies, animiertes Zwergen-Modell unter CC0** gefunden. Gefundene Zwergen-Modelle sind kostenpflichtig oder haben eine unklare Lizenz.

Optionen:
1. **KayKit-Figuren anpassen:** Die Abenteurer (z. B. Barbar, Ritter) gestaucht und breiter skaliert, mit Bart und Helm als Zubehör. Kostet nichts, CC0 erlaubt Veränderungen. Das Ergebnis ist ein Kompromiss.
2. **Zwergen-Paket kaufen:** etwa 15 bis 30 Euro. Die Lizenz muss den Einsatz in einem veröffentlichten Spiel erlauben und wird vor dem Kauf geprüft.
3. **Eigene Modelle** in Blender oder von einem Künstler. Beste Wiedererkennung, höchster Aufwand.

Empfehlung: Mit Option 1 starten und vor der Veröffentlichung auf Option 2 oder 3 wechseln.

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

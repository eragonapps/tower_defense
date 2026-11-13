# Plan: Durnhal: Wacht der Tiefe – 3D Tower Defense für Android

Stand: 12.11.2026 · Status: **Meilensteine 0 bis 3 abgeschlossen, Meilenstein 4 umgesetzt und wartet auf den Gerätetest**

## 1. Festgelegte Entscheidungen

| Thema | Entscheidung |
|---|---|
| Engine | Godot 4.7.2 (GDScript), Version fest. Tests mit GUT 9.7.1. |
| Rollen | Claude schreibt den Großteil des Codes. Du testest auf den Geräten, entscheidest und lieferst Ideen. |
| Spielfeld | Mix: fest vorgegebene Hauptwege, dazu Stollen graben und zuschütten |
| Grafik | Low-Poly mit kostenlosen CC0-Paketen. Alle Quellen stehen in [`ASSETS.md`](ASSETS.md). Assets sind später austauschbar. |
| Ziel | Veröffentlichung im Google Play Store. Monetarisierung ist noch offen. |
| Testgeräte | Samsung Galaxy S24 und Amazon Fire HD 10 (generalüberholt, gekauft Oktober 2023, Generation noch zu bestätigen) |
| Stil | düster: dunkle Stollen, Fackellicht, gedeckte Farben |
| Format | Querformat |
| Zwerge | zunächst angepasste KayKit-Figuren, später austauschbar |
| Name | **Durnhal: Wacht der Tiefe** (englisch: *Durnhal: Watch of the Deep*) |
| Paketname | `com.eragonapps.durnhal` (bis zur ersten Veröffentlichung noch änderbar) |
| Leistungsmaßstab | Samsung Galaxy S24. Das Fire HD 10 wird mitgetestet, begrenzt aber nicht die Grafik. |
| Sprachen | Deutsch und Englisch, im Spiel umschaltbar |

## 2. Spielkonzept

Ein Zwergenclan verteidigt seine Mine. Gegner kommen in Wellen durch die Stollen und wollen zum **Herz der Mine** (Schatzkammer). Erreicht ein Gegner das Herz, verliert der Spieler Leben. Bei 0 Leben ist das Level verloren.

### Kernschleife
1. **Bauphase:** Türme setzen, Stollen graben, Arbeiter zuteilen.
2. **Welle:** Gegner laufen den kürzesten Weg zum Herz. Türme schießen automatisch.
3. **Belohnung:** Gold für besiegte Gegner, Erz von den Arbeitern. Damit werden Türme gebaut und verbessert.
4. Das wiederholt sich bis zur letzten Welle, bei manchen Levels mit Boss. Am Ende gibt es eine Wertung mit 1 bis 3 Sternen.

### Zwei Währungen
- **Gold:** kommt von besiegten Gegnern. Bezahlt Türme und Stollen.
- **Erz:** wird von Bergarbeiter-Zwergen an Erzadern abgebaut. Bezahlt Upgrades. Arbeiter können von Gegnern angegriffen werden und brauchen deshalb Schutz.

### Stollen-Mechanik
- Das Level ist ein Raster. Es gibt Fels (grabbar), Granit (nicht grabbar), Stollen (begehbar), Bauplätze und Erzadern.
- Der Spieler kann Fels sprengen und so einen neuen Weg öffnen. Er kann Stollen auch zuschütten.
- **Regel:** Es muss immer ein Weg vom Eingang zum Herz bestehen. Ein Bau, der den letzten Weg versperrt, wird abgelehnt.
- Nach jeder Änderung wird der Weg der Gegner neu berechnet (A* auf dem Raster).
- Graben kostet Gold und dauert Zeit. Die Zahl der Grabungen pro Level kann begrenzt sein.

### Türme (erste Ausbaustufe)
| Turm | Rolle |
|---|---|
| Armbrustschütze | schnell, ein Ziel, günstig |
| Steinschleuder | Flächenschaden, langsam |
| Bombenwerfer | hoher Flächenschaden, sehr langsam, teuer |
| Runenstein | verlangsamt Gegner im Umkreis |
| Schmiedefeuer | Schaden über Zeit (Brennen) |
| Schildwall | Axtkämpfer blockieren Gegner im Stollen |

Jeder Turm hat 3 Stufen und am Ende eine von zwei Spezialisierungen.

### Gegner (erste Ausbaustufe)
Kapitel 1 nutzt Untote, weil die Skelett-Modelle schon vorliegen und zum düsteren Stil passen. Goblins, Trolle und Spinnen folgen, sobald passende Modelle im Repo sind.

| Gegner | Eigenschaft |
|---|---|
| Skelett-Scherge | schwach, schnell, kommt in Gruppen |
| Skelett-Krieger | Standardgegner |
| Skelett-Schurke | sehr schnell, wenig Leben. Angriffe auf Arbeiter folgen in M4. |
| Skelett-Magier | heilt oder schützt andere Gegner |
| Goblin | schwach, schnell, kommt in Gruppen (später) |
| Ork | Standardgegner (später) |
| Troll | viel Leben, langsam |
| Höhlenspinne | sehr schnell, wenig Leben |
| Skelett-Wächter | gepanzert, widersteht Bolzen |
| Boss (z. B. Höhlentroll-König, später Drache) | Abschluss eines Kapitels |

### Meta-Fortschritt
- Levelkarte mit Kapiteln, je Level 1 bis 3 Sterne.
- **Zwergenhalle:** Sterne schalten dauerhafte Verbesserungen frei (Tech-Tree).
- Drei Schwierigkeitsgrade.

## 3. Technik

### Rendering und Geräte
- **Renderer:** „Mobile" (Vulkan). „Compatibility" (OpenGL ES 3) bleibt als Rückfallebene für ältere Geräte.
- **Ziel:** stabile 60 Bilder pro Sekunde auf dem Samsung Galaxy S24. Es ist der Maßstab für Grafik und Effekte.
- **Düsterer Stil:** dunkle Materialien, Nebel, Fackellicht mit Schatten, soweit das S24 es flüssig darstellt.
- **Fire HD 10:** Es wird mitgetestet. Eine Grafikstufe „Niedrig" (weniger Lichter, keine Schatten) soll es spielbar halten, ohne die Darstellung auf dem S24 einzuschränken. Es hat keinen Play Store, Test-APKs werden per Sideload installiert.
- **Formate:** Querformat, Seitenverhältnisse von 16:10 (Tablet) bis 19,5:9 (S24). Die Oberfläche hält Abstand zu Kamera-Aussparung und Rändern.
- **Kamera:** schräg von oben. Wischen verschiebt, zwei Finger zoomen, Drehung in festen Schritten.

### Projektstruktur
```
project.godot
scenes/        main_menu, level_select, level, hud, towers/*, enemies/*
scripts/
  core/        Simulation (sim.gd), Raster und Wegfindung (grid.gd), Daten (game_data.gd), Einstellungen
  view/        3D-Darstellung des Levels, Kamera
  ui/          HUD, Menüs, Sprachauswahl
data/          Türme, Gegner, Wellen, Levels als JSON-Dateien
assets/        Modelle, Texturen, Töne (je Paket ein Ordner mit Lizenzdatei)
locale/        Übersetzungen de/en (CSV)
tests/         automatische Tests
tools/         Bots, Balancing-Bericht, Screenshot-Werkzeug
.github/workflows/   CI: Tests und Android-Build
```

### Architektur-Grundsätze
- **Logik getrennt von Darstellung:** Raster, Wegfindung, Wirtschaft, Schaden und Wellen sind reine Skripte ohne 3D-Abhängigkeit. Dadurch laufen sie in Tests ohne Grafik.
- **Datengetrieben:** Alle Werte (Schaden, Kosten, Wellen, Level-Raster) stehen als JSON-Dateien im Ordner `data/`. Balancing braucht keine Code-Änderung.
- **Austauschbare Assets:** Jede Turm- und Gegner-Szene bindet ihr Modell über einen einzigen Knoten ein. Ein Tausch ändert nur diese Szene und den Eintrag in `ASSETS.md`.
- **Feste Zeitschritte:** Die Simulation rechnet in festen Schritten und mit festem Zufalls-Startwert. Ein Lauf ist damit exakt wiederholbar. Das ist die Grundlage für die Tests und für die Vorspul-Taste (2×, 3×).
- **Wiederverwendung:** Gegner und Projektile werden wiederverwendet statt neu erzeugt (Object Pooling).
- **Sprache:** Alle Texte laufen über Übersetzungsschlüssel. Die Sprache folgt beim ersten Start dem Gerät und ist in den Einstellungen wählbar.
- **Speichern:** Fortschritt und Einstellungen liegen lokal als Datei mit Versionsnummer, damit spätere Updates alte Spielstände lesen können.

## 4. Meilensteine

### M0 – Grundgerüst
Godot-Projekt, Ordnerstruktur, Testrahmen, CI auf GitHub Actions (Tests und Debug-APK), Sprachumschaltung als Gerüst.
**Fertig, wenn:** eine leere App auf beiden Geräten startet und die CI grün ist.
**Stand:** abgeschlossen am 12.11.2026.

### M1 – Spielbarer Prototyp (Platzhalter-Grafik)
Ein Level mit Raster, Wegfindung, 1 Gegner, 2 Türme, Gold, Leben, Wellen, Sieg und Niederlage, Touch-Kamera.
**Fertig, wenn:** das Level auf beiden Geräten von Anfang bis Ende spielbar ist.
**Stand:** abgeschlossen am 12.11.2026, auf dem S24 getestet. Enthalten sind 2 Gegner (Skelett-Scherge, Skelett-Krieger), 2 Türme (Armbrustschütze, Steinschleuder), 6 Wellen, Verkauf mit 70 % Erstattung, Tempo 1× bis 3× und Pause.
**Abweichung vom Plan:** Gegner und Geschosse werden noch neu erzeugt statt wiederverwendet. Das wird erst nachgezogen, wenn eine Messung auf dem Gerät es nötig macht.

### M2 – Stollen und Wirtschaft
Graben und Zuschütten mit Wegprüfung, Erzadern, Arbeiter, zweite Währung, Upgrades in 3 Stufen.
**Stand:** abgeschlossen am 12.11.2026, auf dem S24 getestet. Dazu ein zweites Level „Die Erzader", das ohne Mine nicht zu gewinnen ist, und eine Levelauswahl im Hauptmenü.

So ist es umgesetzt:
- **Graben:** Fels neben einem Stollen antippen. Kostet 30 Gold und dauert 3 Sekunden. Gegner nutzen einen neuen Weg sofort.
- **Zuschütten:** Stollen antippen. Kostet 20 Gold und wirkt sofort. Es wird abgelehnt, wenn ein Eingang oder ein Gegner dadurch keinen Weg mehr hätte oder ein Gegner auf dem Feld steht.
- **Arbeiter:** Erzader antippen, die an einen Stollen grenzt. Kostet 40 Gold, liefert 1 Erz pro Sekunde. Sind Gegner näher als 1,6 Felder, versteckt sich der Arbeiter und liefert nichts.
- **Ausbau:** Turm antippen. Jede Stufe kostet Erz und verbessert Schaden, Reichweite, Nachladezeit oder Fläche. Das Menü zeigt die Werte vorher und nachher.
- **Regeln als Daten:** Alle diese Werte stehen in `data/rules.json`. Ein Level kann sie überschreiben, Level 1 schaltet das Graben ab.

Abweichungen und bekannte Schwächen:
- Arbeiter können nicht sterben und nicht bestohlen werden. Sie verstecken sich nur. Der Dieb-Gegner kommt in Meilenstein 4.
- Ein Verkauf erstattet nur Gold, kein Erz.
- Zuschütten wirkt sofort. Damit könnte man Gegner durch wiederholtes Öffnen und Schließen im Kreis schicken. Das ist noch nicht begrenzt und wird beim Gerätetest beobachtet.
- Der Umweg in Level 2 lohnt sich für den Bot nicht: Er gewinnt mit Umweg knapper als ohne.

### M3 – Vertical Slice
Echte Low-Poly-Modelle, Animationen, 4 Türme, 4 Gegner, HUD, Ton, Effekte, 1 fertiges Level, Deutsch und Englisch vollständig.
**Fertig, wenn:** jemand ohne Erklärung das Level spielen kann.
**Stand:** abgeschlossen am 13.11.2026, auf dem S24 getestet (60 Bilder pro Sekunde). Ein anstrengender Armbrust-Ton wurde danach ersetzt.

Was drin ist:
- **Modelle:** Zwerge auf den Türmen und an den Erzadern, vier Skelett-Gegner, Bodenplatten, Fackeln mit Licht, Fässer und Kisten, Truhe am Herz, Tor am Eingang. Alle mit Animationen für Laufen, Schießen, Zaubern, Arbeiten und Sterben.
- **Türme:** Armbrustschütze, Steinschleuder, Runenstein (bremst alle Gegner im Umkreis), Schmiedefeuer (setzt in Brand).
- **Gegner:** Skelett-Scherge, Skelett-Krieger, Skelett-Schurke (schnell), Skelett-Magier (heilt andere Gegner).
- **Level 3 „Zwei Tore":** zwei Eingänge, alle Türme und Gegner.
- **Ton:** 17 Geräusche, im Hauptmenü abschaltbar.
- **Effekte:** Staub und Funken, Ringe für Flächenschaden, Runenstein und Heilung, Anzeigen für verlangsamte und brennende Gegner.
- **Bildrate:** In Test-Builds steht sie oben in der Mitte.

Abweichungen und offene Punkte:
- Keine Musik und keine eigene Schrift. Dafür fehlen noch Quellen mit geklärter Lizenz.
- Die Zwerge sind gestauchte Abenteurer-Figuren ohne Bart.
- Fels und Granit sind weiter einfache Blöcke, jetzt mit Steintextur. Das Minen-Paket mit Schienen und Stützbalken ist nicht verwendet, weil es nur als Blender-Datei vorliegt.
- Die Leistung mit vielen animierten Figuren ist auf dem Gerät noch nicht gemessen. Gegner-Figuren werden wiederverwendet, Geschosse und Effekte noch nicht.
- Balancing: Nur Steinschleudern gewinnen alle drei Levels. Runenstein und Schmiedefeuer bringen dem Bot weniger als Armbrust und Schleuder.

### M4 – Inhalt
Alle 6 Türme mit Spezialisierungen, alle Gegner, Boss, 8 bis 10 Levels, Levelkarte, Speichern, Schwierigkeitsgrade.
**Stand:** umgesetzt am 13.11.2026. Der erste Teil ist auf dem S24 getestet, Spezialisierungen und die Levels 5 bis 8 noch nicht.

Fertig:
- **Spielstand:** Sterne je Level und Schwierigkeit, gespeichert als Datei mit Versionsnummer. Beschädigte Dateien führen nicht zum Absturz.
- **Sterne:** 3 ohne Verlust, 2 mit mindestens der Hälfte der Leben, sonst 1.
- **Levelkarte:** Kacheln mit Nummer, Name und Sternen. Ein Level öffnet sich mit einem Sieg im Level davor.
- **Schwierigkeitsgrade:** Leicht, Normal, Schwer. Sie ändern die Lebenspunkte der Gegner und das Startgold (`data/difficulties.json`).
- **Türme:** Bombenwerfer (große Fläche, langsam) und Schildwall (hält Gegner direkt am Stollen fest). Damit sind alle 6 Türme da.
- **Schadensarten:** Bolzen, Wucht, Feuer, Magie. Gegner können einzelnen Arten widerstehen.
- **Gegner:** Skelett-Wächter (gegen Bolzen gepanzert), Knochenkönig (Boss: ruft Schergen, lässt sich kaum bremsen und nicht aufhalten). Skelett-Schurken stehlen jetzt Erz, wenn sie an einem Arbeiter vorbeikommen.
- **Level 4 „Der Knochenkönig"** mit allen Türmen und dem Boss.

- **Spezialisierungen:** Auf Stufe 3 wählt jeder Turm eine von zwei Spezialisierungen, bezahlt mit Erz. Die Wahl ist endgültig. Beispiele: Scharfschütze oder Schnellfeuer, Frostrune oder Sturmrune, Bollwerk oder Berserker.
- **Levels 5 bis 8:** Die Kreuzung (zwei Tore, kurzer gemeinsamer Weg), Tiefe Adern (viel Erz, viele Diebe, nur sieben Grabungen), Belagerung (drei Tore), Der Thronsaal (Abschluss mit zwei Knochenkönigen).
- **Nach Rückmeldung vom Gerät:** Der Bombenwerfer kostet 165 statt 130 Gold. Der Armbrustschütze hat nur noch einen Ton.

Abweichungen und bekannte Schwächen:
- Wächter und Knochenkönig haben kein eigenes Modell. Sie sind umgefärbte, anders skalierte Skelette.
- Level 8 ist für den Minen-Bot zu leicht: Er gewinnt ohne Verlust. Schon 8 % zähere Gegner lassen ihn aber am Boss scheitern. Der Boss macht das Ergebnis sprunghaft, weil er allein alle Leben kostet.
- In Level 7 lohnt sich frühes Investieren in die Mine nicht, weil drei kurze Wege zuerst gesichert werden müssen.
- Nur Steinschleudern gewinnen laut Bot weiterhin die Levels 1, 2, 3 und 5.
- Die Levels 5 bis 8 sind nur mit Bots eingestellt.
- Höchstens 79 Gegner sind laut Bot gleichzeitig unterwegs (Level 2). Ein Test hält alle Levels unter 80.

### M5 – Meta und Feinschliff
Zwergenhalle, Tutorial, Balancing, Optimierung für das Fire HD 10, Einstellungen (Ton, Sprache, Grafikqualität).

### M6 – Veröffentlichung
Signierter App-Bundle-Build, Store-Eintrag (Texte de/en, Bilder, Datenschutzerklärung, Alterseinstufung), geschlossener Test, Produktion.

## 5. Teststrategie

### Was Claude in der Cloud-Sitzung selbst testen kann
Geprüft am 12.11.2026: Godot für Linux lässt sich in der Sitzung herunterladen. Das Android-SDK ist dort nicht erreichbar, deshalb entstehen APKs in GitHub Actions.

| Ebene | Was | Wie |
|---|---|---|
| A. Unit-Tests | einzelne Regeln | Godot ohne Fenster (`--headless`) mit Testrahmen GUT oder gdUnit4 |
| B. Simulations-Tests | ganze Wellen und Levels ohne Grafik | Simulation im Schnelldurchlauf mit festem Zufalls-Startwert |
| C. Bot-Durchläufe | Balancing und Spielbarkeit | Skript-Spieler mit festen Strategien spielen jedes Level. Bericht mit `tools/balance_report.gd`. |
| D. Bild-Tests | Darstellung und Oberfläche | Godot mit virtuellem Bildschirm, Screenshots über `tools/screenshot.gd`. In M0 und M1 geprüft: funktioniert für Oberfläche und 3D-Szenen. Das Bild entsteht mit Software-Rendering, es zeigt also nicht die Leistung und nicht exakt die Darstellung des Vulkan-Renderers. |
| E. Build-Test | APK entsteht | GitHub Actions baut bei jedem Push |

### Testszenarien

**Raster und Wegfindung**
- Der Weg vom Eingang zum Herz ist der kürzeste.
- Graben eines Felsfelds öffnet eine Abkürzung, Gegner nehmen sie ab sofort.
- Zuschütten des einzigen Wegs wird abgelehnt, das Gold bleibt erhalten.
- Granit lässt sich nicht graben.
- Gegner, die schon unterwegs sind, bekommen nach einer Änderung einen gültigen neuen Weg und bleiben nie in einer Wand stecken.
- Zufallstest: 1000 zufällige Folgen von Graben und Zuschütten, danach existiert immer ein Weg.

**Türme und Kampf**
- Ein Turm schießt nur auf Gegner in Reichweite.
- Zielauswahl „am weitesten vorn" wählt den Gegner mit dem kürzesten Restweg.
- Flächenschaden trifft alle Gegner im Radius und keinen außerhalb.
- Verlangsamung wirkt für die angegebene Dauer und stapelt sich nicht über die Obergrenze.
- Brennen verursacht genau den Gesamtschaden aus den Daten.
- Panzerung senkt Pfeilschaden, aber nicht Bombenschaden.
- Schildwall hält höchstens die angegebene Zahl Gegner auf.

**Wirtschaft**
- Bau zieht die Kosten ab, zu wenig Gold verhindert den Bau.
- Verkauf erstattet den festgelegten Anteil.
- Arbeiter liefern Erz im erwarteten Takt, ein angegriffener Arbeiter liefert nichts.
- Gold und Erz werden nie negativ.

**Wellen und Spielablauf**
- Jede Welle erzeugt genau die Gegner aus den Daten, in der richtigen Reihenfolge und Zeit.
- Ein Gegner am Herz kostet die richtige Zahl Leben.
- 0 Leben führt zur Niederlage, die letzte Welle ohne überlebende Gegner zum Sieg.
- Pause hält die Simulation an. Vorspulen liefert dasselbe Ergebnis wie Normaltempo.
- Derselbe Startwert und dieselben Eingaben ergeben immer denselben Endstand.

**Balancing mit Bots**
- Bot „baut nichts" verliert jedes Level.
- Bot „baut sinnvoll" gewinnt jedes Level auf „Normal".
- Bot „nur ein Turmtyp" gewinnt nicht jedes Level, damit keine Strategie alles dominiert.
- Die Auswertung zeigt Siegquote und verbleibende Leben je Level. So fallen zu leichte und zu schwere Levels auf.

**Speichern und Sprache**
- Speichern und Laden ergibt denselben Fortschritt.
- Eine beschädigte oder alte Speicherdatei führt nicht zum Absturz.
- Jeder Übersetzungsschlüssel hat einen deutschen und einen englischen Text.
- Umschalten der Sprache ändert alle sichtbaren Texte sofort.
- Kein Text läuft in der längeren Sprache aus seinem Feld (Bild-Test).

**Leistung**
- Belastungslauf mit 300 Gegnern und 40 Türmen ohne Grafik: Rechenzeit pro Schritt bleibt unter dem Grenzwert.
- Nach 20 Wellen wächst der Speicherverbrauch nicht weiter.

### Was nur auf den Geräten geprüft werden kann (durch dich)
Zu jedem Meilenstein gibt es eine kurze Checkliste. Feste Punkte:
- Installation und Start auf S24 und Fire HD 10
- Bildrate (eingeblendete Anzeige) in der größten Welle
- Touch: Wischen, Zoomen, Turm setzen, Fehlbedienungen
- Lesbarkeit und Größe der Schaltflächen auf beiden Bildschirmen
- App in den Hintergrund und zurück, Anruf während des Spiels, Bildschirm aus
- Ton, Lautstärke, Stummschaltung
- Erwärmung und Akkuverbrauch nach 20 Minuten

## 6. Veröffentlichung im Play Store – was früh zu wissen ist

- **Entwicklerkonto:** einmalig 25 US-Dollar, mit Identitätsprüfung.
- **Geschlossener Test:** Neue private Konten müssen vor der Freigabe einen geschlossenen Test mit mindestens 12 Testern über 14 Tage durchführen. Firmenkonten sind ausgenommen. Das braucht Vorlauf.
- **Signierschlüssel:** wird einmal erzeugt und sicher aufbewahrt. Er kommt nie ins Repo. Für die CI liegt er als GitHub-Secret vor.
- **Paketname:** z. B. `com.eragonapps.zwergenminen`. Er ist nach der ersten Veröffentlichung nicht mehr änderbar.
- **Pflichtangaben:** Datenschutzerklärung, Angaben zur Datensicherheit, Alterseinstufung, Ziel-API-Level nach aktueller Google-Vorgabe. Die genaue Vorgabe wird in M6 geprüft.
- **Lizenzen:** Godot verlangt einen Lizenzhinweis im Spiel. Dafür gibt es einen Bildschirm „Credits und Lizenzen", der auch die Asset-Quellen nennt.

## 7. Risiken

| Risiko | Gegenmaßnahme |
|---|---|
| Fire HD 10 zu schwach für 3D-Effekte | Grafikstufe „Niedrig". Das Tablet ist kein Maßstab, schlechte Leistung dort blockiert nichts. |
| Kein freies Zwergen-Modell mit CC0 gefunden | siehe `ASSETS.md` Abschnitt 4, Entscheidung vor M3 |
| Stollen-Mechanik macht Levels zu leicht | Grabungen begrenzen, Granit im Leveldesign, Bot-Tests |
| Umfang wächst | Meilensteine mit festen Abnahmekriterien, M3 als erster vorzeigbarer Stand |
| Bild-Tests zeigen 3D anders als das Gerät | Screenshots von deinen Geräten als Ergänzung |

## 8. Offene Fragen

1. **Fire HD 10:** Welche Generation zeigt das Tablet in den Einstellungen an? Nur zur Einordnung, nicht dringend.
2. **Fehlende Pakete:** Vier Pakete sind aus der Cloud-Sitzung nicht erreichbar, siehe `ASSETS.md` Abschnitt 3b. Sie werden ab Meilenstein 3 gebraucht.
3. **Name:** Ob „Durnhal" im Play Store oder als Marke vergeben ist, ist noch nicht geprüft. Das steht vor Meilenstein 6 an.

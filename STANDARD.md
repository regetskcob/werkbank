# Standard für App-Repos

Gilt für alle Flutter-App-Repos (KNX Monitor, Panzergefecht, Jagdaufseher, Kalkar
kompakt und alle neuen). Ziel: Jedes Projekt läuft gleich ab und legt gleich ab. Was ein
Projekt anders macht, steht in seiner `CLAUDE.md` und in `tool/werkbank.conf`.

## Ordnerstruktur

Jede Datei hat genau einen Ort. `werkbank layout` (Teil von `werkbank verify` und der CI)
lehnt unbekannte Einträge auf oberster Ebene und Medien außerhalb ihrer Ordner ab.

| Ordner | Inhalt |
|---|---|
| `lib/` | App-Quellcode |
| `test/` | Unit-, Widget- und Golden-Tests; Goldens in einem Unterordner `goldens/` |
| `integration_test/`, `test_driver/` | Tests auf Gerät oder Simulator, Store-Aufnahmen, Driver-Einstiege |
| `assets/` | Dateien, die in die App gebündelt werden – nur die |
| `android/`, `ios/`, `macos/`, `linux/`, `windows/`, `web/`, `tvos/`, `watchos/` | Plattformprojekte (Flutter-Standard, tvOS/watchOS über die Flutter-Forks) |
| `docs/` | Doku als Markdown; Bilder in `docs/images/<thema>/`, gedruckte Dokumente in `docs/pdf/` (Quellen und `build.sh` in `docs/pdf/<dokument>/`) |
| `tool/` | Skripte des Projekts; ein Werkzeug mit mehreren Dateien bekommt einen eigenen Ordner. `tool/werkbank/` ist die Kopie der werkbank, `tool/werkbank.conf` ihre Einstellung |
| `store/` | Alles für die Stores (Aufbau unten). Eingecheckt, außer das Projekt hält es privat – dann in `.gitignore`, und die `CLAUDE.md` sagt es |
| `site/` | Landingpage (Hugo); was sie ausliefert, liegt in `site/static/` oder `site/assets/` |
| `supabase/` | Backend (Migrationen, Funktionen, Vorlagen) |
| `build/` | Alles Erzeugte, ignoriert. `flutter clean` löscht es – was bleiben soll, gehört nicht hierhin |

Wurzeldateien: `README.md`, `CLAUDE.md`, `LICENSE`, bei offenen Projekten `CONTRIBUTING.md`,
`SECURITY.md` und `TRADEMARKS.md`, `CHANGELOG.md` (ggf. `CHANGELOG.de.md`),
`pubspec.*`, `analysis_options.yaml`, `l10n.yaml`, `dart_test.yaml`, `build.yaml`, `.mcp.json`,
`Gemfile*` (fastlane) und `package*.json` (Supabase-CLI und andere Node-Werkzeuge).
Weitere Wurzelordner nur für eigenständige Produkte neben der App (z. B. `ha-addon/`,
`box/` bei KNX Monitor), eingetragen in `WB_TOP_EXTRA`.

### `store/`

```
store/
  ios/metadata/                    der fastlane-deliver-Baum: <de-DE|en-US>/ mit den Texten,
                                   dazu review_information/, copyright.txt, Kategorien
  ios/screenshots/<de-DE|en-US>/   fertige Screenshots, Präfix nach Gerät: iphone69_01_<name>.png, ipad13_…
  ios/review/                      weitere Hinweise und Bilder für die App-Prüfung (was deliver
                                   nicht hochlädt)
  android/metadata/<de-DE|en-US>/  Texte und images/ im fastlane-supply-Format
                                   (images/phoneScreenshots/, sevenInchScreenshots/, tenInchScreenshots/,
                                   featureGraphic.png, icon.png)
  macos/screenshots/<de-DE|en-US>/
  raw/<gerät>/<de|en>/             Rohaufnahmen vor dem Rahmen (gerät: iphone, ipad, android-phone,
                                   android-tablet, mac, …); Querformat als <de|en>-land
  graphics/                        Banner, OG-Bilder und andere Store-Grafiken
  social/                          Beiträge für soziale Medien (optional)
  release/<version>/               Archiv hochgeladener Builds (immer ignoriert)
  archiv/                          alte Läufe, Sicherungen, Logs (immer ignoriert)
```

Sprachen: Store-Ordner heißen wie die Stores (`de-DE`, `en-US`), Rohaufnahmen wie die
App-Sprache (`de`, `en`).

## Ablauf

Jedes Projekt hat **einen** Einstieg `tool/release.sh <befehl>` (Vorlage:
`release.sh.example` im werkbank-Repo). Die gemeinsamen Schritte
ruft es über `tool/werkbank/bin/werkbank` auf; was nur das Projekt hat (Add-on, Box,
Watch-App, Seiten-Deploy), steht als eigener Befehl daneben.

| Befehl | Was | Quelle |
|---|---|---|
| `verify` | vor jedem Push: Layout, Übersetzungen, Format, Analyse, Tests, dann die Hooks `verify_quick_extra` und `verify_extra` | `werkbank verify` |
| `android` | signiertes AAB (baut fastlane oder ein Projektskript, nimmt `werkbank collect aab <pfad> [variante]` es auf) nach `build/release/<app>-<version>.aab`, Prüfung gegen den Debug-Schlüssel, Symbole wegsichern | `werkbank android` |
| `ios` | IPA nach `build/release/<app>-<version>.ipa`, mit `--upload` zu App Store Connect | `werkbank ios` |
| `notes [--draft]` | Release-Texte des Builds vollständig? `--draft` legt Entwürfe aus den gemergten PRs an | `werkbank notes` |
| `upload-apple <xcarchive>` | Archiv (iOS, macOS) zu App Store Connect, mit dem in Xcode angemeldeten Konto | `werkbank upload-apple` |
| `upload-play [aab] [track]` | AAB mit Versionshinweisen in eine Play-Spur (Dienstkonto) | `werkbank upload-play` |
| `devicetest` | Integrationstests nacheinander auf allen angeschlossenen Geräten, Bericht in `build/devicetest/` | `werkbank devicetest` |
| `shots` | Rohaufnahmen nach `store/raw/` | Projekt (Simulator über `werkbank sim`) |
| `graphics` | aus `store/raw/` die fertigen Bilder in `store/<plattform>/…` | Projekt |
| `site` | Landingpage bauen und ausliefern | `werkbank site` (Abschnitt Landingpages) |

- **Version** nur in `pubspec.yaml` (`x.y.z+build`); Skripte lesen sie mit `werkbank version`.
- **CI** läuft auf Pull Requests (Linux) mit denselben Schritten wie `verify --quick`; teure
  Builds (macOS, Windows) nur auf Tag oder von Hand. Release-Builds entstehen lokal.
- **Ausgaben:** Erzeugtes nach `build/`, Release-Dateien nach `build/release/`, Symbole von
  `--split-debug-info` nach `~/keys/symbols/<app>/<version>/<plattform>/`.

### Release-Texte

Zu jedem Store-Build gehören Texte, die zum Upload fertig daliegen:

```
store/ios/testflight/whats_new_<build>_<de-DE|en-US>.txt   „Was testen“ für TestFlight, ≤ 4000 Zeichen, du-Ansprache
store/android/play-notes-<build>.txt                      ein Block je Sprache: <de-DE>…</de-DE>, je ≤ 500 Zeichen
```

`werkbank notes --draft` legt fehlende als Entwurf aus den seit dem letzten App-Tag
(`WB_APP_TAG_PREFIX`) gemergten PRs an, mit der Zeile `ENTWURF`. Solange sie drinsteht,
gilt der Text als fehlend: Die PR-Titel sind englisch und technisch, die Texte schreibt
Claude oder du in Nutzersprache. `werkbank notes` prüft und legt den Play-Block in die
Zwischenablage; `upload-play` nimmt ihn mit.

### Hochladen

- **Apple:** `werkbank upload-apple <archiv>` macht, was „Distribute App“ im Organizer tut,
  mit dem in Xcode angemeldeten Konto – kein API-Schlüssel nötig. Ein zweiter Versuch folgt
  von selbst, falls die Verbindung abbricht.
- **Google Play:** `werkbank upload-play` lädt mit einem Dienstkonto hoch (Play Console →
  Nutzer und Berechtigungen → Dienstkonto einladen, Rechte „Releases verwalten“), Schlüssel
  unter `WB_PLAY_KEY`. Spur `WB_PLAY_TRACK` (Standard `internal`), solange die App nicht
  veröffentlicht ist `WB_PLAY_STATUS=draft`. Nur Python und openssl, kein fastlane.

### Gerätetest

`werkbank devicetest` startet die Integrationstests mit `flutter drive --keep-app-running`
(ohne den Schalter deinstalliert Flutter die App am Ende – samt ihrer Daten) auf allen
angeschlossenen Geräten
(iPhone, iPad, Android, Mac; WLAN-Geräte zählen mit), eins nach dem anderen, und schreibt
`build/devicetest/<zeit>/report.md` mit Ergebnis, Dauer und Log je Lauf. Was ein Gerät
vorher und nachher braucht (App-Daten sichern, App beenden), stehen als Hooks
`devicetest_before`/`devicetest_after` in `werkbank.conf`. Scheitert `devicetest_before`
(etwa weil das gesperrte iPhone keine Sicherung zulässt), läuft auf dem Gerät kein Test.
Ohne Hook beendet ein Mac-Lauf die gestartete App.

## Landingpages

Jede App hat ihre Landingpage in `site/` (Hugo, Horizont als Hugo-Modul, Hugo 0.154.5 wie
in allen Workflows). Bauen und Prüfen ist überall gleich, nur das Ziel unterscheidet sich:

| Schritt | Wie |
|---|---|
| Prüfen | `werkbank verify` baut alle `WB_SITE_DIRS` (ohne `--quick`) |
| Bauen | `werkbank site site <baseURL>` → `build/site/site/` |
| Ausliefern in den Blog | `werkbank site site https://www.regetskcob.de/<app>/ blog <app> [--push]` → `regetskcob.github.io/static/<app>/` |
| Ausliefern per Workflow | GitHub Pages oder FTPS im Workflow des Projekts, mit denselben Hugo-Aufrufen |

Projekt-Befehl ist `tool/release.sh site [--push]`. Ziele heute: KNX Monitor und Jagdaufseher
im Blog (KNX zusätzlich `teaser/` auf knx-monitor.de per `gh-pages`), Panzergefecht per
GitHub-Pages-Workflow, Kalkar kompakt im eigenen Repo `landing-page` per FTPS.

## Schlüssel und Geheimnisse

Nie im Repo. Gleiche Namen in allen Projekten:

| Was | Wo |
|---|---|
| Android-Upload-Schlüssel | `~/keys/<name>-upload.jks`, verwiesen aus `android/key.properties` (ignoriert) |
| App Store Connect | `ASC_KEY_ID`, `ASC_ISSUER_ID`, Datei `ASC_KEY_PATH` (Standard `~/.appstoreconnect/private_keys/AuthKey_<id>.p8`) |
| Google Play (Upload) | Dienstkonto-JSON unter `WB_PLAY_KEY` (Standard `~/keys/<app>-play.json`) |
| Build-Werte der App (Supabase, RevenueCat, …) | `~/.config/<app>/<name>.env`, im Projekt mit `wb_env_file` geladen |

## werkbank.conf

`tool/werkbank.conf` ist eine Bash-Datei, die `werkbank` vor jedem Befehl lädt. Alles ist
optional; Vorlage: `werkbank.conf.example` im werkbank-Repo.

| Name | Standard | Wofür |
|---|---|---|
| `WB_APP` | `name` aus `pubspec.yaml` | Dateinamen der Release-Dateien, Symbolordner |
| `WB_TOP_EXTRA` | – | weitere Wurzeleinträge (Regex-Alternativen) |
| `WB_MEDIA_EXTRA` | – | weitere Medienordner (Regex, mit `/` am Ende) |
| `WB_FORMAT_PATHS` | vorhandene von `lib test integration_test test_driver` | Pfade für `dart format` |
| `WB_ANALYZE_ARGS`, `WB_TEST_ARGS` | – | zusätzliche Argumente |
| `WB_SYMBOLS_DIR` | `~/keys/symbols/<app>` | Ziel für Debug-Symbole |
| `WB_SITE_DIRS` | `site`, wenn `site/hugo.toml` da ist | Hugo-Seiten, die `verify` baut |
| `android_args`, `ios_args` | – | Funktionen, die Build-Argumente ausgeben |
| `verify_quick_extra` | – | Funktion mit weiteren Prüfungen, die auch die CI macht (läuft auch bei `--quick`) |
| `WB_APP_TAG_PREFIX` | `v` | Tag-Präfix der App-Releases (Entwürfe der Release-Texte) |
| `WB_STORE_LANGS` | `de-DE en-US` | Sprachen der Release-Texte |
| `WB_PLAY_PACKAGE`, `WB_PLAY_KEY`, `WB_PLAY_TRACK`, `WB_PLAY_STATUS` | –, `~/keys/<app>-play.json`, `internal`, `completed` | Upload zu Google Play |
| `WB_DEVICETEST_TARGETS` | alle `integration_test/*_test.dart` | Tests für `devicetest` |
| `devicetest_before`, `devicetest_after` | – | Funktionen je Gerät (`$1` Geräte-ID, `$2` Plattform) |
| `verify_extra` | – | Funktion mit langsamen Prüfungen (Web-Build, Server, Hugo; nicht bei `--quick`) |

## werkbank aktualisieren

Die werkbank liegt als Kopie in `tool/werkbank/`, damit Projekt und CI ohne Zugang zum
privaten werkbank-Repo laufen. Änderungen entstehen im werkbank-Repo, dann je Projekt:

```bash
~/dev/werkbank/install.sh ~/dev/<projekt>
```

und ein PR im Projekt. `tool/werkbank/VERSION` zeigt, welcher Stand drin ist.

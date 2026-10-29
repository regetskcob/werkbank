# werkbank

Gemeinsame Werkzeuge und Regeln aller App-Repos: Ordnerstruktur, Prüfungen vor dem Push,
Release-Builds und Simulator-Helfer für Store-Aufnahmen. Die Regeln stehen in
[STANDARD.md](STANDARD.md).

## Benutzen

Die werkbank wird in jedes Projekt kopiert (nicht als Abhängigkeit geladen), damit die CI
ohne Zugriff auf dieses private Repo läuft:

```bash
~/dev/werkbank/install.sh ~/dev/<projekt>     # legt tool/werkbank/ an oder aktualisiert es
```

Im Projekt dann:

```bash
tool/werkbank/bin/werkbank verify            # Layout, l10n, Format, Analyse, Tests, verify_extra
tool/werkbank/bin/werkbank android           # signiertes AAB nach build/release/
tool/werkbank/bin/werkbank ios --upload      # IPA nach build/release/, Upload mit API-Schlüssel
tool/werkbank/bin/werkbank sim "Store iPhone 6.9" com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max iOS
tool/werkbank/bin/werkbank doctor            # was fehlt
```

Meist ruft `tool/release.sh` des Projekts diese Befehle auf. Projekt-Einstellungen:
`tool/werkbank.conf` (Vorlage [werkbank.conf.example](werkbank.conf.example)).

## Entwickeln

```bash
test/run.sh        # Tests (temporäre Repos, kein Flutter nötig)
shellcheck -x bin/werkbank lib/common.sh install.sh test/run.sh
```

Neue Fassung: Tag `vX.Y.Z` setzen, `install.sh` je Projekt laufen lassen, je Projekt ein PR.
Schritte, die nur ein Projekt braucht, bleiben im Projekt.

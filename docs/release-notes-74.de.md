# Release Notes – linuxmuster-linbo7 7.4

## Versionsübersicht

| Version | Datum | Ziel-Repository |
|---------|-------|-----------------|
| 7.4.8 | 23.07.2026 | lmn74 |
| 7.4.7 | 21.07.2026 | lmn74 |
| 7.4.6 | 17.07.2026 | lmn74 |
| 7.4.5 | 05.07.2026 | lmn74 |
| 7.4.4 | 25.06.2026 | lmn74 |
| 7.4.3-0 | 08.06.2026 | lmn74 |
| 7.4.2-0 | 05.06.2026 | lmn74 |
| 7.4.1-0 | 28.05.2026 | lmn74 |
| 7.4.0-0 | 25.05.2026 | lmn74 |

> **Hinweis:** Die Versionsnummer wurde mit diesem Release an die linuxmuster.net-Versionierung angeglichen (bisher 4.x.x, jetzt 7.4.x).

---

## Hauptänderungen

### 1. Komplette Überarbeitung des Build-Systems (PR #151)

Der Build-Prozess wurde grundlegend umstrukturiert und verwendet nun zu 100 % Ubuntu-Pakete und -Komponenten anstelle von selbst kompilierten Binaries.

**Wesentliche Änderungen:**

- Das Verzeichnis `src/` wird jetzt vollständig im Git-Repository verwaltet (nicht mehr in `.gitignore`). Es enthält alle Quell- und Konfigurationsdateien für:
  - `src/linbofs/` – Client-seitiges Initramfs (Init-Skripte, Busybox-Konfiguration, Netzwerk, udev, udhcpc)
  - `src/linbo-splash/` – Plymouth-Bootsplash (Assets und Skripte)
  - `src/serverfs/` – Serverseitige Installationsdateien (linbo-remote, update-linbofs, Systemd-Dienste, GRUB-Themes, start.conf-Beispiele, Windows-Integrationsskripte)
- Das Verzeichnis `build/` wurde neu strukturiert:
  - `build/bin/kernel-harvester.sh` – Skript zum Einsammeln von Kernel-Modulen
  - `build/config/build.env` – zentrale Build-Umgebungsvariablen
  - `build/config/linbofs.apps` – Paketliste für die linbofs-Umgebung
  - `build/config/modules.d/` – Auswahllisten für Kernel-Module
  - `build/run.d/` – nummerierte Build-Skripte in geordneter Ausführungsreihenfolge
- `debian/rules` wurde aktualisiert: Das `src`-Verzeichnis wird nicht mehr während des Builds angelegt/bereinigt; Build-Ausgaben werden per `tee` in `build.log` mitgeschrieben.
- `update-linbofs`: `busybox dumpkmap` wird jetzt gechrootet ausgeführt.
- Veraltete Build-Abhängigkeiten und Build-Skripte wurden entfernt.
- Dateieigentümerschaften: Alle Dateien im Build-Baum, die `root` gehören, werden nach dem Build wieder dem aktuellen Nutzer zugeordnet.

**Verbesserungen am Bootsplash und Fortschrittsanzeigen:**

- `linbo-splash`: Boot-Meldungen werden jetzt zentriert dargestellt (basierend auf der tatsächlichen Textbreite jeder Zeile).
- `update-linbofs`: Fortschrittsanzeige während der Erstellung des linbofs-Archivs (cpio/xz) wurde durch `pv` ersetzt – zeigt Prozentsatz, Durchsatz und ETA.
- `pv` wurde als Laufzeit-Abhängigkeit in `debian/control` aufgenommen.
- Reduzierte xz-Blockgröße für eine flüssigere Fortschrittsanzeige beim Paketieren von linbofs.

**Verbesserungen an linbofs:**

- `init.sh`: kleinere Verbesserungen und Code-Bereinigung; Fix: Cache-Partition wurde im Offline-Modus nicht eingehängt.
- `linbo.sh`: kleinere Plymouth-Optimierungen.
- `/etc/group` in linbofs aktualisiert.
- Benötigte Kernel-Module nachgepflegt.
- Benötigte NVMe-Module hinzugefügt.
- Dateisystem-Tools in `linbofs.apps` ergänzt.
- `var/lock` als Verzeichnis in linbofs aufgenommen.
- Unterstützung für Verzeichniseinträge in `linbofs.apps` hinzugefügt.
- `fdisk` von Ubuntu wird jetzt statt einer eigenen Binary verwendet.
- Veraltete Konsolen-Tastaturdatei `german.kbd` entfernt.

**opentracker:**

- Umstieg auf den nativen Ubuntu-opentracker anstelle einer selbst kompilierten Version.
- Überbleibsel des alten opentracker-Systemd-Dienstes entfernt.
- `opentracker.conf` aktualisiert.

---

### 2. Refaktorierung der Kernel-Bereitstellung (PR #150)

Die Kernel-Bereitstellung im Client wurde grundlegend überarbeitet.

- Umstieg auf den Standard-Ubuntu-Kernel anstelle eines selbst kompilierten Kernels.
- `kernel-harvester.sh`: Skript zum automatischen Einsammeln und Archivieren der benötigten Kernel-Module.
- Kernel-Metadaten werden jetzt im `cache/`-Verzeichnis für spätere Verwendung gespeichert.
- Modul-Listen für linbofs wurden aktualisiert und ergänzt.
- Fix: Fehler bei der Verkettung von Modullisten in `kernel-harvester.sh` behoben.

---

### 3. Ersatz von ctorrent durch aria2c (PR #152)

Das BitTorrent-Download-Tool `ctorrent` wurde vollständig durch `aria2c` ersetzt.

**Client-seitig (linbofs):**

- `ctorrent` aus linbofs entfernt, `aria2` hinzugefügt.
- `aria2c` wird nun für den Download von Images über BitTorrent verwendet.
- Qdiff-Images werden nur noch heruntergeladen, wenn das Basis-Image im qcow2-Format vorliegt.

**Server-seitig:**

- `aria2c`, `btcheck` und `buildtorrent` werden jetzt für die Verwaltung von Torrent-Dateien und das Seeden von Images verwendet.
- Verarbeitung von Torrent-Hash-Dateien implementiert.
- `linbo-torrent`-Skript überarbeitet: verbesserte Image-Seeding-Logik.
- `aria2c`, `btcheck` und `buildtorrent` als Paket-Abhängigkeiten in `debian/control` aufgenommen.

---

### 4. Aufräumen und Entfernen veralteter Komponenten

- Veraltetes Konvertierungsskript `linbo-cloop2qcow2` (cloop → qcow2) entfernt.
- Veralteter Code für die Windows-Aktivierungsverwaltung entfernt.
- Beispieldatei für benutzerdefinierte Kernel (`custom_kernel`) aktualisiert.

---

### 5. Natives Windows-Treiberprofil-Management (PR #157, ab 7.4.8)

Mit `linbo_driverpostsync` hält linbofs jetzt eine eigene, stabile Laufzeitkomponente
für die Verteilung von Windows-Treibern:

- Das Skript wählt Windows-Treiberprofile anhand der DMI-Vendor-/Product-Informationen
  des jeweiligen Clients aus.
- Es lädt zunächst nur die kleinen `match.conf`-Dateien herunter, überträgt
  ausschließlich die passenden Treiber-Payloads und bereitet sie für die
  Installation per Windows PnPUtil vor.
- Bestehende LINBO-Pfade für Image-Download, Sync-Hooks, Mounts und
  Registry-Handling werden wiederverwendet; es wird kein zusätzlicher Dienst,
  Netzwerk-Port oder Abhängigkeit eingeführt.
- Die Profilzuweisung und Verwaltung der `match.conf`-Dateien bleibt weiterhin
  serverseitig in `linuxmuster-tools7` (`LinboDriverManager`); linbofs liefert
  nur die stabile Client-Laufzeit, `linuxmuster-tools7` erzeugt pro Image einen
  kleinen generierten Dispatcher.
- Treiberprofil-Metadaten wurden aus den regulären Sync-Payloads ausgeschlossen.
- Ausführliche Architektur- und Entscheidungsdokumentation:
  [`docs/linbofs-windows-driver-profiles.md`](linbofs-windows-driver-profiles.md).

Zusätzlich wurde ein erster Shell-Test-Harness für linbofs-Skripte eingeführt
(Phase 1), der u. a. die Namensvalidierung von `linbo_driverpostsync` abdeckt.

---

## Weitere Fehlerbehebungen und Verbesserungen (7.4.2 – 7.4.8)

### Partitionierung & Cache

- `linbo_partition`: Fehler beim Unmounten von `/cache` behoben (7.4.2).
- `linbo_partition`: Unmount von `/cache` wird jetzt wiederholt, um gleichzeitige
  Re-Mounts zu überstehen (#155, 7.4.5).
- `linbo_partition`: `convert_size()` ist jetzt portabel für POSIX `sh` und nicht
  mehr auf Busybox-`ash` beschränkt (7.4.8).

### update-linbofs / Firmware-Handling

- Firmware wird nur noch dann kopiert, wenn sie tatsächlich benötigt wird
  (#153, 7.4.5).
- Nicht erkannte Fehler beim Extrahieren von Kernel-Modulen werden jetzt erkannt
  (7.4.5).
- Unnötiger Download der Firmware-Liste von kernel.org entfällt (7.4.5).
- Firmware-Suche durch einmalig aufgebauten Index beschleunigt (7.4.5).
- Bricht jetzt bei kritischen Kopier-/Setup-Fehlern ab, statt stillschweigend
  ein defektes linbofs zu bauen (7.4.5).
- Variablen in Pfadausdrücken werden jetzt korrekt gequotet (7.4.5).
- Fehlende Firmware wird direkt anhand der generischen Kernel-Meldung erkannt
  (#154, 7.4.5).
- Bereits zwischengespeicherte Firmware wird wiederverwendet statt bei jedem
  Lauf erneut heruntergeladen zu werden (7.4.5).
- Symlinks bleiben beim Kopieren zwischengespeicherter Firmware jetzt erhalten
  (#156, 7.4.6).
- `busybox dumpkmap`-Fix (#151, 7.4.3).
- Locale-Fix (7.4.4).
- Fehlendes `qemu-guest-agent` in 7.4 ergänzt (#130, 7.4.8).

### 3_linbofs-apps / Kernel-Harvester

- Verzeichniseinträge werden jetzt per `rsync -a` statt per einfachem Glob
  kopiert; behebt stillschweigend fehlende `/etc/udev/{hwdb.d,rules.d}` und
  `/usr/lib/grub/x86_64-efi/monolithic` (#161, 7.4.7).
- `kernel-harvester.sh`: Modul-/Kernel-Pfade werden nach einem
  `KERNELVER`-Override jetzt neu berechnet (#162, 7.4.7).

### Torrent / aria2c

- Konsolenausgabe von `aria2c` verbessert (7.4.2).
- Optionen für `aria2c` sind jetzt konfigurierbar (#152, 7.4.4).
- Handling der `linbo-multicast`-Konfigurationsdateien verbessert (7.4.4).
- Verbessertes Handling der Torrent-Hash-Dateien im Zusammenspiel mit
  Image-Updates auf dem Client (7.4.3).
- `linbo-torrent`: `pipefail` gesetzt, damit Fehler von `btcheck` sichtbar
  werden statt verschluckt zu werden (#159, 7.4.7).
- `linbo-torrent`: Redundantes rekursives `chown` bei verschachtelten
  Selbstaufrufen entfällt (#160, 7.4.7).
- `linbo_seeder`: Usage-Text korrigiert, damit er dem tatsächlichen Verhalten
  entspricht (#163, 7.4.7).
- `linbo_initcache`: Diff-Image-Erkennung für Image-Namen mit mehreren Punkten
  korrigiert (#158, 7.4.7).

### Netzwerk / WLAN

- WLAN-Problem „key addition failed" behoben, Kernel-Modul `ccm.ko.zst` zu
  linbofs hinzugefügt (#150, 7.4.3).
- P2P-Interface-Erzeugung in `wpa_supplicant.conf.ex` deaktiviert (7.4.3).

### Sonstiges

- Boot-Ausgabe des LINBO-Clients auf 64 Zeichen Breite vergrößert (7.4.2).
- Plymouth-Boot-Ausgabe korrigiert (7.4.2).
- Veraltetes GRUB-Modul `efi_uga.mod` entfernt (7.4.3).
- Fehlende Abhängigkeit zu `logrotate` ergänzt (7.4.3).
- Fehlendes `hdparm` zu linbofs hinzugefügt (#151, 7.4.3).
- Package-Revision-Nummer aus der Version entfernt (7.4.4).

---

## Versionierung

Mit Branch 7.4 wird die LINBO-Versionsnummer an die linuxmuster.net-Versionierung angeglichen:

- **Bisher:** `4.3.x-0` (lmn73-Repository)
- **Ab jetzt:** `7.4.x-0` (lmn74-Repository)

Das Ziel-Repository für Pakete dieser Version ist `lmn74`.

---

## Bekannte Hinweise / Migrationshinweise

- Das `src/`-Verzeichnis im Repository enthält jetzt alle Build-Quellen und ist Teil des Quellpakets (`debian/rules` wurde entsprechend angepasst).
- Wer bisher eine eigene Build-Umgebung hatte, sollte die neue Struktur unter `build/` und `src/` sichten.
- Der Wechsel vom lmn73- auf das lmn74-Repository erfordert eine Anpassung der APT-Quellen gemäß der [Setup-Dokumentation](https://github.com/linuxmuster/deb/blob/main/README.md#setup).

---

Author: Thomas Schmitt
Co-Author: Claude

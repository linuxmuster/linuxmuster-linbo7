# Release Notes – linuxmuster-linbo7 7.4

## Versionsübersicht

| Version | Datum | Ziel-Repository |
|---------|-------|-----------------|
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

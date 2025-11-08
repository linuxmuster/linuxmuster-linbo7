# Changelog für linuxmuster-linbo7 Version 4.3.26-0

## Hauptfeature: Kerberos-Keytab-Verwaltung für Linux-Clients ([#142](https://github.com/linuxmuster/linuxmuster-linbo7/issues/142))

Die Version 4.3.26-0 behebt das KVNO-Problem (Key Version Number) bei der Kerberos-Client-Authentifizierung gegen Samba AD. Dies ist besonders wichtig für Linux-Clients, die sich nach einem LINBO-Sync an einer Active Directory-Domäne authentifizieren müssen.

### Implementierte Komponenten:

#### 1. Neues Python-Script: `export-keytab.py` ([61ea91e](https://github.com/linuxmuster/linuxmuster-linbo7/commit/61ea91ed37fe05b5bbfea65132071f40410a27f4))

**Funktion:**
- Exportiert Kerberos-Keytabs für Computer-Accounts aus Samba AD
- Speichert die Keytabs im `keytabs`-Unterverzeichnis des jeweiligen Image-Verzeichnisses
- Validiert automatisch, ob der Hostname in LDAP existiert
- Setzt die Berechtigungen auf 644 für HTTP-Transfer
- Verifiziert den Keytab-Inhalt mit `klist`

**Neue Paketabhängigkeiten:**
- `diceware` - für sichere Passwortgenerierung
- `linuxmuster-tools7` - für LDAP-Connector-Funktionalität

**Technische Details:**
- Verwendet `samba-tool domain exportkeytab` mit Computer-Principal (`computer$@REALM`)
- Nutzt `LMNLdapReader` zur Validierung der Computer-Accounts
- Automatische Verifikation der exportierten Keytabs

#### 2. Erweiterte `linbo_start`-Funktionalität ([cfc5ee3](https://github.com/linuxmuster/linuxmuster-linbo7/commit/cfc5ee39bd56a19eb4776e0d69123eaee877c2c9))

**Änderungen:**
- Verschiebt den `invoke_macct`-Aufruf vor den Prestart-Script-Download
- Kopiert automatisch den Host-spezifischen Keytab (`<imagebase>.keytab`) nach `/etc/krb5.keytab` beim Start eines Linux-Systems
- Erkennt automatisch Kerberos-fähige Systeme anhand von `/etc/krb5.conf`
- Löscht den SSSD-Cache (`/var/lib/sss/db/*`), um veraltete Authentifizierungsdaten zu entfernen
- Setzt korrekte Berechtigungen (600) für die Keytab-Datei

**Workflow:**
1. Machine-Account-Passwort auf Server setzen
2. Prestart-Script herunterladen und ausführen
3. Keytab in die Zielpartition kopieren (falls Kerberos konfiguriert)
4. SSSD-Cache löschen für saubere Authentifizierung

#### 3. Keytab-Bereitstellung in `rsync-pre-download.sh` ([8306c3f](https://github.com/linuxmuster/linuxmuster-linbo7/commit/8306c3f6f8457168da8255fbd1065805188344a2))

**Workflow beim Image-Download:**
1. LDIF-Datei mit Machine-Account-Daten erstellen
2. Machine-Account-Passwort in Samba AD aktualisieren
3. Keytab für den Client exportieren (falls noch nicht vorhanden)
4. Keytab via `linbo-scp` in den Client-Cache übertragen
5. Automatische Umbenennung nach Image-Basisnamen (`<imagebase>.keytab`)

**Vorteile:**
- Keytabs werden persistent im Image-Verzeichnis gespeichert
- Nur einmaliger Export pro Client notwendig
- Automatische Bereitstellung bei jedem Sync

#### 4. Keytab-Invalidierung in `rsync-post-upload.sh` ([3e44e50](https://github.com/linuxmuster/linuxmuster-linbo7/commit/3e44e50f6d36cfd4b20f889c1bb56bc3dc75bd3e))

**Sicherheitsmechanismus:**
- Entfernt automatisch alle vorhandenen Keytabs im `keytabs`-Verzeichnis nach einem Image-Upload
- Verhindert die Verwendung ungültiger Keytabs nach Passwortänderungen
- Zwingt zur Neugenerierung der Keytabs beim nächsten Sync

**Begründung:**
- Nach einem Image-Upload haben sich typischerweise die Kerberos-Passwörter geändert
- Alte Keytabs würden zu Authentifizierungsfehlern führen
- Sauberer Neustart der Keytab-Verwaltung

---

## Kernel-Updates ([#134](https://github.com/linuxmuster/linuxmuster-linbo7/issues/134))

**Commit:** [6639c8e](https://github.com/linuxmuster/linuxmuster-linbo7/commit/6639c8e)

Aktualisierung aller drei unterstützten Kernel-Linien:
- **Linux 6.1.158** (Langzeit-Support/Legacy)
- **Linux 6.12.57** (Langzeit/Longterm)
- **Linux 6.17.7** (Stabil/Stable)

---

## Bugfixes

### qemu-nbd Read-Write-Verbindung korrigiert ([635ec91](https://github.com/linuxmuster/linuxmuster-linbo7/commit/635ec91))

**Problem:**
- Fehlerhafte Read-Write-Verbindungen zu qcow2-Image-Dateien via qemu-nbd
- Führte zu Schreibproblemen beim Mounten von Images

**Lösung:**
- Korrektur der qemu-nbd-Mount-Parameter
- Zuverlässige RW-Verbindungen für Image-Operationen

---

## Verbesserungen

### Hostname in /etc/hosts beim Linux-Sync ([4b23872](https://github.com/linuxmuster/linuxmuster-linbo7/commit/4b23872))

**Funktion:**
- Automatisches Hinzufügen des Client-Hostnamens zur `/etc/hosts`-Datei beim Synchronisieren eines Linux-Systems
- Verhindert DNS-Auflösungsprobleme während des ersten Boots
- Wichtig für Systeme, die ihren eigenen Hostnamen auflösen müssen, bevor Netzwerk/DNS verfügbar sind

### Code-Refactoring in rsync-Scripts ([58528d4](https://github.com/linuxmuster/linuxmuster-linbo7/commit/58528d4))

**Änderungen:**
- Kleinere Code-Verbesserungen und Aufräumarbeiten in `rsync-pre-download.sh` und `rsync-post-upload.sh`
- Verbesserte Lesbarkeit und Wartbarkeit
- Keine funktionalen Änderungen

---

## Windows Imaging-Vorbereitung ([c9f755a](https://github.com/linuxmuster/linuxmuster-linbo7/commit/c9f755a))

### Neues Script: `prepare-for-image.cmd`

**Autor:** Blair (Community-Beitrag)
**Quelle:** [ask.linuxmuster.net Forum-Thread](https://ask.linuxmuster.net/t/skript-zur-vorbereitung-des-images/11874)

**Funktionsumfang:**

#### System-Checks
1. **Administrator-Rechte-Prüfung**
   - Stellt sicher, dass das Script mit Admin-Rechten läuft

2. **Windows Update-Aktivität**
   - Wartet, bis Windows Update-Prozesse abgeschlossen sind
   - Erkennt laufende `TiWorker.exe`-Prozesse
   - Prüft, ob ein Neustart nach Updates erforderlich ist
   - Führt automatisch Neustart aus, falls notwendig

3. **Fast Boot (Schnellstart)-Prüfung**
   - Erkennt, ob Fast Boot aktiviert ist
   - Deaktiviert automatisch die Registry-Einstellung
   - Führt Neustart durch, damit Änderung wirksam wird
   - Wichtig für saubere Image-Erstellung

4. **Systemintegritätsprüfung**
   - Überprüft Health-Status aller Volumes
   - Plant automatisch CHKDSK bei erkannten Problemen
   - Führt SFC (System File Checker) aus
   - Führt DISM Health Check durch

#### Systembereinigung

**Temporäre Dateien:**
- `%TEMP%` und `C:\Windows\Temp`
- Prefetch-Daten
- Benutzerprofil-Caches (AppData\Local\Temp, INetCache, Recent)

**System-Caches:**
- Windows Update Download-Cache
- DISM Component Store Cleanup
- Storage Sense

**Logs und Historien:**
- Alle Windows Event Logs
- Papierkorb für alle Benutzer

**Windows-Installationsreste:**
- `C:\$WINDOWS.~BT`
- `C:\$WINDOWS.~WS`
- `C:\$GetCurrent`

**Finale Aktionen:**
- Filesystem-Flush für alle Volumes
- Automatisches Herunterfahren nach Abschluss

**Besonderheiten:**
- Vollständig ins Englische übersetzt für internationale Verwendung
- Modernes PowerShell-basiertes Script
- Automatische Neustarts bei kritischen Änderungen
- Umfassende Ausgaben für Transparenz

---

## Aufräumarbeiten

### Entfernung veralteter mokconfig.cnf ([1269da6](https://github.com/linuxmuster/linuxmuster-linbo7/commit/1269da6))

**Grund:**
- Template für MOK (Machine Owner Key) Konfiguration wird nicht mehr benötigt
- Modernere Secure Boot-Handhabung in neueren LINBO-Versionen

---

## Sonstige Änderungen

### CLAUDE.md Konfiguration ([2f0c31b](https://github.com/linuxmuster/linuxmuster-linbo7/commit/2f0c31b))

- Hinzufügen der Claude Code AI-Konfigurationsdatei
- Dokumentiert Projekt-Struktur und Build-Prozesse für AI-gestützte Entwicklung

---

## Zusammenfassung

Version 4.3.26-0 bringt eine wichtige Verbesserung für Linux-Clients in Active Directory-Umgebungen durch die automatische Kerberos-Keytab-Verwaltung. Dies löst das langjährige KVNO-Problem und ermöglicht zuverlässige Kerberos-Authentifizierung nach LINBO-Syncs.

Zusätzlich wurden die Kernel aktualisiert, mehrere Bugfixes implementiert und mit dem Windows Imaging Preparation Script ein wertvolles Tool aus der Community integriert.

**Getestet mit:**
- linuxmuster.net 7.2/7.3
- Ubuntu 22.04 Server
- Debian-basierte Linux-Clients mit SSSD/Kerberos

**Migration:**
- Keine besonderen Migrationsschritte erforderlich
- Keytabs werden automatisch beim nächsten Sync generiert
- Bestehende Images funktionieren weiterhin

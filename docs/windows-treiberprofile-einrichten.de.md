# Windows-Treiberprofile einrichten

Seit linuxmuster.net 7.4 kann Linbo hardwarespezifische Windows-Treiber
automatisch verteilen. Ein Client lädt beim Synchronisieren nur die Treiber,
die zu seiner eigenen Hardware passen – ein Windows-Image kann damit viele
Gerätemodelle bedienen, ohne alle Treiber zu enthalten.

Dieses Dokument beschreibt die Einrichtung, wie sie in 7.4 tatsächlich
möglich ist. Bitte vorher den Abschnitt [Was 7.4 noch nicht
kann](#was-74-noch-nicht-kann) lesen.

Stand: Die Angaben sind gegen den ausgelieferten Code geprüft und vom Autor
der Funktion durchgesehen
([Issue #175](https://github.com/linuxmuster/linuxmuster-linbo7/issues/175)).
Eine überarbeitete Fassung von seiner Hand ist angekündigt.

## Wie es funktioniert

Auf dem Server liegt pro Gerätemodell ein *Treiberprofil* unter
`/srv/linbo/drivers/<profil>/`. Es besteht aus einer kleinen Kennung
(`match.conf`) mit Hersteller und Modell sowie den eigentlichen Treibern.
Wird ein Profil einem Image zugewiesen, erzeugt der Server dazu automatisch
ein kleines Hilfsskript im Imageverzeichnis.

Beim Synchronisieren lädt der Client zunächst nur die Kennungen aller
zugewiesenen Profile, vergleicht sie mit seinen eigenen DMI-Werten und
überträgt ausschließlich die Treiber der passenden Profile. Installiert
werden sie anschließend von Windows selbst über PnPUtil – entweder
unbeaufsichtigt beim Systemstart oder, ohne die dafür nötige Vorbereitung,
erst bei der nächsten Anmeldung eines Administrators. Siehe
[Vorbereitung am Muster-Client](#vorbereitung-am-muster-client).

Wichtig zur Einordnung: Ein Treiberprofil hat nichts mit der
linuxmuster-Hardwareklasse zu tun, also nicht mit der LINBO-Gruppe aus
`devices.csv` beziehungsweise `start.conf.<gruppe>`. Die Zuordnung eines
Clients zu einem Profil erfolgt ausschließlich über seine DMI-Werte. Der
Name des Profilverzeichnisses ist frei wählbar und dient nur als
Bezeichnung; erlaubt sind Buchstaben, Ziffern, Punkt, Unterstrich und
Bindestrich, beginnend mit einem alphanumerischen Zeichen. Eine sprechende
Bezeichnung wie `lenovo-21l4` hat sich bewährt.

## Vorbereitung am Muster-Client

Dieser Schritt ist einmalig und entscheidet darüber, wann die Treiber
installiert werden.

Der Client erkennt eine unbeaufsichtigte Installation an zwei Dateien im
Windows-System, die **beide** vorhanden sein müssen:

| Datei | Inhalt |
|---|---|
| `C:\Windows\System32\Tasks\LINBO-Driver-Install` | geplante Aufgabe, läuft beim Systemstart als SYSTEM und ruft `C:\Drivers\LINBO\pnputil-install.cmd` auf |
| `C:\ProgramData\LINBO\Drivers\startup-task-ready` | genau die Zeichenkette `LINBO SYSTEM driver startup task v1` |

Sind beide vorhanden, entfernt `linbo_driverpostsync` vorhandene
RunOnce-Einträge und überlässt die Installation der Aufgabe. Fehlt eines von
beiden, trägt es stattdessen einen RunOnce-Eintrag ein – die Treiber werden
dann erst installiert, wenn sich das nächste Mal ein Administrator anmeldet.

Beide Dateien müssen in der Windows-Installation liegen, die das LINBO-Image
enthält. In der Praxis heißt das: in Windows auf dem Muster-Client anlegen
und danach das Image neu erstellen. Ein bereits vorhandenes Image genügt
nicht, solange es die Dateien nicht enthält. **Kein linuxmuster-Paket liefert
sie mit**, siehe [Was 7.4 noch nicht kann](#was-74-noch-nicht-kann).

Bestandsimages aus dem früheren eigenständigen Projekt „LINBO Patchless"
funktionieren weiter: Dort werden `LINBO-Patchless-Driver-Install` und
`C:\ProgramData\LINBO-Patchless\startup-task-ready` mit der Zeichenkette
`LINBO-Patchless SYSTEM startup task v1` ebenfalls akzeptiert.

## Schritt 1: Hersteller- und Modellkennung ermitteln

Die Zuordnung erfolgt über die DMI-Werte des Clients. Am besten liest man
sie aus derselben Quelle, die auch `linbo_driverpostsync` beim Vergleich
verwendet – etwa in der LINBO-Shell des betreffenden Clients:

```sh
cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name
```

Die API zeigt zusätzlich die von den Clients hochgeladenen
Hardwareinventare:

```sh
curl -H "X-API-Key: <schlüssel>" https://<server>/v1/linbo/drivers/inventory
```

Das Inventar dient nur dem Nachschlagen. Profile entstehen daraus nicht
automatisch, sie werden im nächsten Schritt von Hand oder über die API
angelegt.

## Schritt 2: Profil anlegen

Ein Profil ist ein Verzeichnis mit einer `match.conf`:

```sh
mkdir -p /srv/linbo/drivers/lenovo-21l4
cat > /srv/linbo/drivers/lenovo-21l4/match.conf <<'EOF'
[match]
vendor = LENOVO
product = 21L4
EOF
```

Zur Schreibweise: `vendor` muss exakt übereinstimmen, Groß- und
Kleinschreibung zählt. `product` muss lediglich im Produktnamen des Clients
enthalten sein – ein kurzer Wert wie `21L4` deckt deshalb mehrere Varianten
derselben Baureihe ab. Ein `*` wirkt als Platzhalter.

Dasselbe über die API:

```sh
curl -X POST -H "X-API-Key: <schlüssel>" -H "Content-Type: application/json" \
  -d '{"name": "lenovo-21l4", "vendor": "LENOVO", "product": "21L4"}' \
  https://<server>/v1/linbo/drivers/profiles
```

## Schritt 3: Treiber ablegen

Die entpackten Treiber kommen direkt in das Profilverzeichnis, mindestens
eine `.inf`-Datei muss dabei sein:

```text
/srv/linbo/drivers/lenovo-21l4/
├── match.conf
├── netzwerk/… .inf
└── chipsatz/… .inf
```

Die Treiberdateien selbst verwaltet der Server nicht – Beschaffung,
Entpacken und Prüfen liegen bei der Administration.

## Schritt 4: Profil einem Image zuweisen

```sh
curl -X PUT -H "X-API-Key: <schlüssel>" -H "Content-Type: application/json" \
  -d '{"image": "win11"}' \
  https://<server>/v1/linbo/drivers/profiles/lenovo-21l4/image
```

Oder direkt über die Python-Bibliothek auf dem Server:

```python
from linuxmusterTools.linbo import LinboDriverManager, LinboImageManager

images = LinboImageManager(driver_manager=LinboDriverManager())
images.assign_driver_profile("lenovo-21l4", "win11")
```

Dabei passiert zweierlei automatisch: Im Profilverzeichnis entsteht eine
`image.conf` mit der Imagezuordnung, und im Imageverzeichnis wird
`/srv/linbo/images/win11/win11.driverpostsync` geschrieben – das Hilfsskript,
das der Client später ausführt.

Diese Datei darf **weder von Hand angelegt noch bearbeitet werden**. Der
Server erkennt seine eigenen Dateien an der Kopfzeile
`# Managed-By: linuxmusterTools.linbo.driver_hooks v1`. Fehlt sie, gilt die
Datei als fremd und wird nicht überschrieben – jede weitere Zuweisung für
dieses Image schlägt dann fehl, bis die Datei entfernt wurde.

Ein Image kann beliebig viele Profile haben. Ein Profil gehört dagegen zu
genau einem Image.

## Schritt 5: Ergebnis prüfen

Nach dem nächsten Synchronisieren eines Clients:

| Ort | Inhalt |
|---|---|
| `/cache/linbo-driverpostsync.log` | Protokoll des Treiberlaufs auf dem Client |
| `/cache/linbo-driverprofiles/<image>/` | zuletzt übertragene Treiber |
| `/mnt/Drivers/LINBO/`, aus Windows `C:\Drivers\LINBO` | bereitgelegte Treiber samt `pnputil-install.cmd` |

Das Protokoll sagt auch, welcher Weg gewählt wurde: „SYSTEM startup task
detected" bedeutet unbeaufsichtigte Installation, „RunOnce fallback
registered … administrator logon required" die Rückfallebene.

Installiert werden die Treiber danach durch Windows selbst mit
`pnputil /add-driver C:\Drivers\LINBO\*.inf /subdirs /install`. Das Ergebnis
steht auf der Windows-Seite in `C:\ProgramData\LINBO\Drivers\driver-install.log`.

## Profile ändern und entfernen

Eine Zuweisung wird mit `DELETE` auf denselben Endpunkt wieder aufgehoben.
Ein Profil lässt sich erst löschen, wenn es keinem Image mehr zugewiesen ist –
sonst bliebe ein Imageverweis auf ein Profil zurück, das es nicht mehr gibt.

Wird einem Image das letzte Profil entzogen, verschwindet das Hilfsskript
nicht, sondern wird durch eine leere Fassung ersetzt. Das ist Absicht: Nur so
räumen die Clients bereits übertragene Treiber aus ihrem Cache wieder ab.

## Was 7.4 noch nicht kann

- **Der Windows-Teil fehlt im Lieferumfang.** Die geplante Aufgabe
  `LINBO-Driver-Install` und ihre Markerdatei legt kein linuxmuster-Paket an.
  Ohne sie funktioniert die Verteilung zwar, die Installation wartet aber auf
  die nächste Administratoranmeldung. Wer sie unbeaufsichtigt haben will,
  muss beides selbst am Muster-Client einrichten und das Image neu erstellen.
- **Keine Oberfläche.** Weder die WebUI noch `lmncli` haben Kommandos für
  Treiberprofile. Die Einrichtung läuft über die API oder direkt im
  Dateisystem.
- **Keine Treiberverwaltung.** Der Server nimmt Treiberdateien nicht
  entgegen, entpackt sie nicht und prüft sie nicht. Er verwaltet nur die
  Zuordnung.
- **Nicht nach Schulen getrennt.** `/srv/linbo/drivers` gilt serverweit. Wer
  ein Profil anlegt oder ändert, ändert es für alle Schulen.
- **Fehler fallen spät auf.** Eine falsche DMI-Kennung zeigt sich erst beim
  nächsten Synchronisieren eines Clients.

## Quellen

- [Architektur und Entwurfsentscheidungen](linbofs-windows-driver-profiles.md)
  im Repository linuxmuster-linbo7
- Abschnitte „Windows driver profiles" und „Image assignments" im
  [README von linuxmusterTools.linbo](https://github.com/linuxmuster/linuxmuster-tools/blob/lmn74/usr/lib/python3/dist-packages/linuxmusterTools/linbo/README.md)
- [PR #149](https://github.com/linuxmuster/linuxmuster-linbo7/pull/149) und
  [PR #157](https://github.com/linuxmuster/linuxmuster-linbo7/pull/157)

Signed-off by: thomas@linuxmuster.net
Assisted by  : Claude

# Windows-Treiberprofile einrichten

Seit linuxmuster.net 7.4 kann Linbo hardwarespezifische Windows-Treiber
automatisch verteilen. Ein Client lädt beim Synchronisieren nur die Treiber,
die zu seiner eigenen Hardware passen – ein Windows-Image kann damit viele
Gerätemodelle bedienen, ohne alle Treiber zu enthalten.

Dieses Dokument beschreibt die Einrichtung, wie sie in 7.4 tatsächlich
möglich ist. Bitte vorher den Abschnitt [Was 7.4 noch nicht
kann](#was-74-noch-nicht-kann) lesen.

## Wie es funktioniert

Auf dem Server liegt pro Gerätemodell ein *Treiberprofil* unter
`/srv/linbo/drivers/<profil>/`. Es besteht aus einer kleinen Kennung
(`match.conf`) mit Hersteller und Modell sowie den eigentlichen Treibern.
Wird ein Profil einem Image zugewiesen, erzeugt der Server dazu automatisch
ein kleines Hilfsskript im Imageverzeichnis.

Beim Synchronisieren lädt der Client zunächst nur die Kennungen aller
zugewiesenen Profile, vergleicht sie mit seinen eigenen DMI-Werten und
überträgt ausschließlich die Treiber der passenden Profile. Windows
installiert sie beim nächsten Start selbst über PnPUtil.

Wichtig zur Einordnung: Ein Treiberprofil hat nichts mit der
linuxmuster-Hardwareklasse zu tun, also nicht mit der LINBO-Gruppe aus
`devices.csv` beziehungsweise `start.conf.<gruppe>`. Die Zuordnung eines
Clients zu einem Profil erfolgt ausschließlich über seine DMI-Werte. Der
Name des Profilverzeichnisses ist frei wählbar und dient nur als
Bezeichnung; erlaubt sind Buchstaben, Ziffern, Punkt, Unterstrich und
Bindestrich, beginnend mit einem alphanumerischen Zeichen. Eine sprechende
Bezeichnung wie `lenovo-21l4` hat sich bewährt.

## Schritt 1: Hersteller- und Modellkennung ermitteln

Die Zuordnung erfolgt über die DMI-Werte des Clients. Auf einem laufenden
Client:

```sh
dmidecode -s system-manufacturer
dmidecode -s system-product-name
```

Alternativ liefert die API die von den Clients hochgeladenen
Hardwareinventare:

```sh
curl -H "X-API-Key: <schlüssel>" https://<server>/v1/linbo/drivers/inventory
```

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
das der Client später ausführt. Ein Eingriff von Hand ist dort nicht nötig
und auch nicht vorgesehen: Der Server erkennt fremde Dateien an einer
fehlenden Kopfzeile und überschreibt sie nicht.

Ein Image kann beliebig viele Profile haben. Ein Profil gehört dagegen zu
genau einem Image.

## Schritt 5: Ergebnis prüfen

Nach dem nächsten Synchronisieren eines Clients:

| Ort | Inhalt |
|---|---|
| `/cache/linbo-driverpostsync.log` | Protokoll des Treiberlaufs auf dem Client |
| `/cache/linbo-driverprofiles/<image>/` | zuletzt übertragene Treiber |
| `/mnt/Drivers/LINBO/` | für Windows bereitgelegte Treiber samt `pnputil-install.cmd` |

Installiert werden die Treiber beim darauffolgenden Windows-Start über einen
RunOnce-Eintrag.

## Profile ändern und entfernen

Eine Zuweisung wird mit `DELETE` auf denselben Endpunkt wieder aufgehoben.
Ein Profil lässt sich erst löschen, wenn es keinem Image mehr zugewiesen ist –
sonst bliebe ein Imageverweis auf ein Profil zurück, das es nicht mehr gibt.

Wird einem Image das letzte Profil entzogen, verschwindet das Hilfsskript
nicht, sondern wird durch eine leere Fassung ersetzt. Das ist Absicht: Nur so
räumen die Clients bereits übertragene Treiber aus ihrem Cache wieder ab.

## Was 7.4 noch nicht kann

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

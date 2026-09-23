# Windows-Treiberprofile einrichten

Seit linuxmuster.net 7.4 verteilt LINBO Windows-Treiber passend zum
Gerätemodell. Ein Windows-Image reicht damit für viele Modelle: Jeder Client
bekommt beim Synchronisieren nur die Treiber, die zu seiner Hardware passen.

## So funktioniert es

```text
/srv/linbo/drivers/<profil>/   Treiberprofil: match.conf + Treiber
            │
            │  Profil einem Image zuweisen
            ▼
/srv/linbo/images/<image>/<image>.driverpostsync   (wird automatisch erzeugt)
            │
            │  Sync am Client: Hersteller/Modell vergleichen,
            │  nur passende Treiber übertragen
            ▼
C:\Drivers\LINBO   →   Windows installiert beim nächsten Start mit pnputil
```

Ein Profil ist ein Ordner pro Gerätemodell. Der Ordnername ist frei wählbar
(Buchstaben, Ziffern, `.`, `_`, `-`), z. B. `lenovo-21l4`. Mit der
LINBO-Gruppe aus `devices.csv` hat er nichts zu tun.

## Einmalig: Windows-Image vorbereiten

Damit Windows die Treiber ohne Anmeldung installiert, braucht das
Golden Image einen Autostart-Task. Dazu im laufenden Windows als
Administrator
[`Install-LinboDriverTask.ps1`](https://github.com/amolani/linbo-patchless/blob/80bc474bd23ca19a1396f3e8e425ec1489ee1c7a/windows/Install-LinboDriverTask.ps1)
ausführen und danach das Image neu erstellen.

Ohne diesen Task installiert Windows die Treiber erst, wenn sich ein
Administrator anmeldet (RunOnce).

## Pro Gerätemodell

### 1. Hersteller und Modell ermitteln

Am Client in der LINBO-Shell:

```sh
cat /sys/class/dmi/id/sys_vendor
cat /sys/class/dmi/id/product_name
```

### 2. Profil mit `match.conf` anlegen

```sh
mkdir -p /srv/linbo/drivers/lenovo-21l4
cat > /srv/linbo/drivers/lenovo-21l4/match.conf <<'EOF'
[match]
vendor = LENOVO
product = 21L4
EOF
```

- `vendor` muss genau stimmen, Groß- und Kleinschreibung zählt.
- `product` muss im Modellnamen nur *enthalten* sein: `21L4` passt auch auf
  `21L4S00P00`.
- `product = *` passt auf alle Modelle des Herstellers.
- Genau eine `vendor`- und eine `product`-Zeile.

### 3. Treiber ablegen

Entpackte Treiber mit `.inf`-Dateien in denselben Ordner kopieren,
Unterordner sind erlaubt:

```text
/srv/linbo/drivers/lenovo-21l4/
├── match.conf
├── netzwerk/…inf
└── grafik/…inf
```

EXE-Installer oder ZIP-Archive werden nicht verarbeitet, sie müssen vorher
entpackt werden.

### 4. Profil einem Image zuweisen

Auf dem Server als root:

```sh
python3 -c 'from linuxmusterTools.linbo import LinboDriverManager, LinboImageManager
LinboImageManager(driver_manager=LinboDriverManager()).assign_driver_profile("lenovo-21l4", "win11")'
```

Dabei entstehen automatisch:

- `/srv/linbo/drivers/lenovo-21l4/image.conf`
- `/srv/linbo/images/win11/win11.driverpostsync`

Die `.driverpostsync` **nicht selbst anlegen oder bearbeiten.** Eine
selbst geschriebene Datei betrachtet der Server als fremd und überschreibt
sie nicht mehr; weitere Zuweisungen schlagen dann fehl.

Ein Image kann beliebig viele Profile haben, ein Profil gehört zu genau
einem Image.

### 5. Client synchronisieren

`Sync + Start` am Client ausführen. Der Rest passiert automatisch.

## Prüfen

| Wo | Was |
|---|---|
| `/cache/linbo-driverpostsync.log` (LINBO) | welches Profil gepasst hat und was übertragen wurde |
| `C:\Drivers\LINBO\` (Windows) | bereitgelegte Treiber und `pnputil-install.cmd` |
| `C:\ProgramData\LINBO\Drivers\driver-install.log` (Windows) | Ergebnis der Installation |

## Zuweisung aufheben und Profil löschen

```sh
python3 -c 'from linuxmusterTools.linbo import LinboDriverManager, LinboImageManager
LinboImageManager(driver_manager=LinboDriverManager()).unassign_driver_profile("lenovo-21l4")'

python3 -c 'from linuxmusterTools.linbo import LinboDriverManager
LinboDriverManager().delete_profile("lenovo-21l4")'
```

Ein zugewiesenes Profil kann nicht gelöscht werden, erst die Zuweisung
aufheben. Hat ein Image danach kein Profil mehr, bleibt eine leere
`.driverpostsync` stehen. Das ist gewollt: So räumen die Clients ihre alten
Treiber beim nächsten Sync auf.

## Alternativ: über die API

Alle Schritte gehen auch über `linuxmuster-api` unter
`/v1/linbo/drivers/...`, zum Beispiel die Zuweisung:

```sh
curl -X PUT -H "X-API-Key: <JWT>" -H "Content-Type: application/json" \
  -d '{"image": "win11"}' \
  https://<server>/v1/linbo/drivers/profiles/lenovo-21l4/image
```

Das JWT liefert `GET /v1/auth/` mit Benutzername und Passwort.

## Was 7.4 noch nicht kann

- Keine Oberfläche in der WebUI und keine `lmncli`-Befehle.
- Kein Hochladen oder Entpacken von Treibern über den Server.
- Profile gelten für den ganzen Server, nicht pro Schule.
- Der Windows-Autostart-Task ist noch nicht Teil eines Pakets.
- Treiber, die Windows schon zum Starten braucht (z. B. Storage), müssen
  bereits im Image sein.

## Weiterführend

- [Architektur und Entwurfsentscheidungen](linbofs-windows-driver-profiles.md)
- [README von linuxmusterTools.linbo](https://github.com/linuxmuster/linuxmuster-tools/blob/lmn74/usr/lib/python3/dist-packages/linuxmusterTools/linbo/README.md)
- [PR #149](https://github.com/linuxmuster/linuxmuster-linbo7/pull/149),
  [PR #157](https://github.com/linuxmuster/linuxmuster-linbo7/pull/157)

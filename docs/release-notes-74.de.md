# linuxmuster-linbo7 7.4.17

LINBO ist die Netzwerk-Boot- und Imaging-Umgebung von linuxmuster.net, über die
Clients gestartet, Festplattenabbilder verteilt und Windows- und
Linux-Systeme eingerichtet werden.

## Modernisierte Bauumgebung

Mit 7.4.0 wurde der Build-Prozess auf reguläre Ubuntu-Pakete und -Komponenten
umgestellt: Der Client startet jetzt mit dem Standard-Ubuntu-Kernel statt
einem selbst kompilierten, und für die Imageverteilung per Torrent kommt statt
des bisherigen `ctorrent` das etablierte `aria2c` zum Einsatz. Das macht
Wartung und Absicherung deutlich einfacher.

## Windows-Treiberprofile

LINBO kann Windows-Treiber jetzt eigenständig anhand der Hardware-Kennung
jedes Clients automatisch zuordnen und verteilen – ohne zusätzlichen Dienst
oder Netzwerk-Port.

## linbo-remote überarbeitet

`linbo-remote` wurde neu in Python geschrieben und um die Option `--dry-run`
erweitert, die anzeigt, was ein Befehl auf dem Client bewirken würde, ohne ihn
tatsächlich auszuführen. Zwei dabei gefundene, ältere Fehler – abgeschnittene
mehrwortige Bildkommentare und ein falscher Rückgabewert bei `-h` – wurden
gleich mit behoben.

## Zuverlässigkeit im laufenden Betrieb

Zahlreiche kleinere Fehler wurden behoben: fehlende WLAN-Firmware beim
Booten, brüchige Skripte auf manchen USB-Netzwerkadaptern und älteren
Systemen, Aussetzer bei der Torrent-basierten Imageverteilung, sich
gegenseitig überschreibende Status-Uploads mehrerer gleichzeitig laufender
Clients, nicht ankommende Wake-on-LAN-Pakete über Router/Firewall hinweg
sowie verlorene Einträge in der Status-Historie bei Rechnern mit mehreren
Images.

## Versionsschema angeglichen

Mit diesem Zweig wechselt LINBO von seiner bisherigen eigenen Versionsnummer
(zuletzt 4.3.x) auf die linuxmuster.net-Versionierung 7.4.x; das
Paket-Repository wechselt entsprechend von lmn73 nach lmn74.

Signed-off by: thomas@linuxmuster.net
Assisted by  : Claude

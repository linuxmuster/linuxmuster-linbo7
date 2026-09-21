# linuxmuster-linbo7 Release Notes 7.4

## Modernisierte Bauumgebung

Mit 7.4.0 wurde der Build-Prozess auf reguläre Ubuntu-Pakete und -Komponenten
umgestellt: Der Client startet jetzt mit dem Standard-Ubuntu-Kernel statt
einem selbst kompilierten, und für die Imageverteilung per Torrent kommt statt
des bisherigen `ctorrent` das etablierte `aria2c` zum Einsatz. Das macht
Wartung und Absicherung deutlich einfacher.

## Windows-Treiberprofile

Linbo kann Windows-Treiber jetzt eigenständig anhand der Hardware-Kennung
jedes Clients automatisch zuordnen und verteilen – ohne zusätzlichen Dienst
oder Netzwerk-Port.

## Linbo-Fernsteuerung überarbeitet

`linbo-remote` wurde neu in Python geschrieben und um die Option `--dry-run`
erweitert, die anzeigt, was ein Befehl auf dem Client bewirken würde, ohne ihn
tatsächlich auszuführen.

## Zuverlässigkeit im laufenden Betrieb

Zahlreiche Korrekturen und Verbesserungen wurden umgesetzt in den Bereichen Integration von WLAN-Firmware, Unterstützung von USB-Netzwerkadaptern, Imageverteilung, Logging, Wake-on-LAN und Linbo-Fernsteuerung.

## Versionsschema angeglichen

Mit diesem Zweig wechselt Linbo von seiner bisherigen eigenen Versionsnummer
(zuletzt 4.3.x) auf die linuxmuster.net-Versionierung 7.4.x.

Wer es genau wissen möchte: Alle Änderungen im Detail gibt es
[hier](https://github.com/linuxmuster/linuxmuster-linbo7/compare/v7.4.0...main).

Signed-off by: thomas@linuxmuster.net
Assisted by  : Claude

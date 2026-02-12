# ChunkMiner - CC:Tweaked Mining System

Ein vollautomatisches Chunk-Mining-System für 16 Turtles mit zentralem Server und Touchscreen-Monitor.

## Features

- **16 Mining Turtles** im 4x4-Raster, jede Turtle baut einen 4x4 Bereich ab
- **Zentraler Server** mit Touchscreen-Monitor zur Steuerung
- **Automatisches Fuel-Management** - Turtles tanken sich selbst
- **Zentrale Chest** für alle geminten Items
- **Echtzeit-Status** auf dem Monitor (Fuel, Fortschritt, Position)
- **Touch-GUI** - Start/Stop/Recall per Touchscreen
- **Terminal-Befehle** als Alternative zum Touchscreen
- **Blacklist** für wertlose Blöcke (Stein, Erde, etc.)
- **Automatische Rückkehr** bei vollem Inventar

## Dateien

| Datei | Beschreibung |
|-------|-------------|
| `config.lua` | Konfiguration (Y-Levels, Fuel, Blacklist, etc.) |
| `server.lua` | Server-Programm mit GUI für den Hub-Computer |
| `turtle.lua` | Mining-Client für jede Turtle |
| `install.lua` | Installer-Script |

## Benötigte Materialien

### Server / Hub
- 1x Advanced Computer
- 1x Wireless Modem (auf dem Computer)
- 1x Advanced Monitor (mindestens 4x3 Blöcke, empfohlen)

### Pro Turtle (x16)
- 1x Mining Turtle (Turtle + Diamond Pickaxe)
- 1x Wireless Modem (auf der Turtle)

### Infrastruktur
- 1x Chest (unter der Home-Position für Fuel)
- 1x Chest (vor der Home-Position für Item-Ablage)
- 1x Floppy Disk + Disk Drive (zum Kopieren der Dateien)

## Setup-Anleitung

### Schritt 1: Dateien auf Floppy Disk kopieren
1. Alle 4 Dateien auf eine Floppy Disk kopieren
2. Oder per `pastebin` direkt herunterladen

### Schritt 2: Server einrichten
1. Advanced Computer platzieren
2. Wireless Modem an den Computer setzen
3. Advanced Monitor daneben/darüber platzieren (min. 4x3)
4. Floppy Disk einlegen
5. `install server` ausführen
6. `reboot`

### Schritt 3: config.lua anpassen
Bearbeite `config.lua` auf dem Server:
- `START_Y` = Oberstes Y-Level in der Mining Dimension
- `MIN_Y` = Unterstes Y-Level (Bedrock)
- `MODEM_SIDE` = Seite des Modems
- `MONITOR_SIDE` = Seite des Monitors

### Schritt 4: Turtles einrichten
Für jede der 16 Turtles:
1. Mining Turtle platzieren
2. Wireless Modem auf die Turtle setzen
3. Floppy Disk in Disk Drive neben der Turtle
4. `install turtle` ausführen
5. `reboot`

Die Turtles verbinden sich automatisch mit dem Server.

### Schritt 5: Chunk-Position setzen
Am Server-Terminal oder per Touchscreen:
```
chunk <X> <Z>
```
Wobei X und Z die Koordinaten der nordwestlichen Ecke des zu minenden Chunks sind.

### Schritt 6: Mining starten
- Touchscreen: "START ALL" drücken
- Terminal: `start` eingeben

## Server-Befehle (Terminal)

| Befehl | Beschreibung |
|--------|-------------|
| `start` | Alle Turtles starten |
| `stop` | Alle Turtles stoppen |
| `recall` | Alle Turtles zurückrufen |
| `resume` | Gestoppte Turtles fortsetzen |
| `ping` | Status aller Turtles abfragen |
| `status` | Status im Terminal anzeigen |
| `chunk X Z` | Chunk-Origin setzen |
| `start N` | Turtle #N starten |
| `stop N` | Turtle #N stoppen |
| `recall N` | Turtle #N zurückrufen |
| `help` | Hilfe anzeigen |
| `quit` | Server herunterfahren |

## Monitor-GUI

### Hauptseite
- **4x4 Raster**: Zeigt alle 16 Turtles mit Farbcode
  - Grau = Offline
  - Hellgrau = Idle
  - Grün = Mining
  - Gelb = Zurückkehrend
  - Orange = Tanken
  - Cyan = Items abladen
  - Rot = Fehler
  - Magenta = Gestoppt
  - Dunkelgrün = Fertig
- **Buttons**: START ALL, STOP ALL, RECALL, SET CHUNK
- Klick auf eine Turtle = Detailansicht

### Detailseite
- Position, Fuel, Fortschritt, Blöcke geminet
- Fortschrittsbalken
- Einzelsteuerung (Start/Stop)

## config.lua Anpassen

### Für ATM10 Mining Dimension
```lua
config.MIN_Y = -64    -- oder tiefste Ebene der Mining Dim
config.START_Y = 320   -- höchste Ebene
```

### Blacklist erweitern
Füge Blöcke hinzu, die nicht aufgehoben werden sollen:
```lua
config.BLACKLIST = {
    "minecraft:stone",
    "minecraft:cobblestone",
    -- ... weitere Blöcke
    "modname:blockname",
}
```

## Troubleshooting

**Turtle verbindet nicht:**
- Wireless Modem auf beiden Seiten? (Server + Turtle)
- Gleicher `PROTOCOL`-Name in config.lua?
- Sind Server und Turtle in Rednet-Reichweite?

**Turtle bleibt stecken:**
- Nutze `recall N` um Turtle #N zurückzurufen
- Prüfe Fuel-Level (`status` im Terminal)

**Monitor zeigt nichts:**
- Ist der Monitor "advanced"? (Gold-Monitor)
- Richtige Seite in config.lua eingestellt?
- Mindestens 4x3 Blöcke groß?

**Fuel reicht nicht:**
- Lege Kohle/Lava-Eimer in die Fuel-Chest unter der Home-Position
- Erhöhe `FUEL_THRESHOLD` in config.lua

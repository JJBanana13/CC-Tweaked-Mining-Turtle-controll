# ATM10 Mining Fleet - CC:Tweaked Turtle Mining System

Ein zentrales Steuerungssystem fuer 16 Mining Turtles in ATM 10 (All The Mods 10).
Ein Controller mit Monitor steuert die Flotte per Rednet - komplett automatisch, Chunk fuer Chunk.

## Features

- **16 Mining Turtles** gleichzeitig steuern
- **Komplette Chunks abbauen** (16x16, Y:319 bis Y:-64)
- **Zickzack-Pattern** - geradeaus und rechts, kein Kreis
- **Touch-Monitor-UI** mit Chunk-Map und Turtle-Status
- **GPS-basierte Navigation** fuer exakte Positionierung
- **Auto-Resume** nach Server-Restart
- **Automatische Fuel & Inventar Verwaltung**
- **Ein-Klick-Installer** per `wget`

## Hardware-Anforderungen

### Controller-Station
- 1x Advanced Computer
- 1x Wireless Modem (Ender Modem empfohlen)
- 1x Advanced Monitor (min. 4x3 Bloecke)

### GPS-Netzwerk
- 4x Computer mit Wireless Modem
- Platziert auf Y=256+ mit min. 3 Bloecke Abstand

### Pro Mining Turtle (x16)
- 1x Advanced Mining Turtle
- 1x Diamond Pickaxe (oder besser)
- Fuel (Kohle, Lava-Eimer, etc.)

### Base-Station
- 1x Chest fuer Items (vor der Turtle)
- 1x Chest fuer Fuel (neben der Turtle)

## Installation

### 1. GPS einrichten

Fuehre `gps_setup.lua` auf einem Computer aus um die 4 GPS-Satelliten einzurichten:

```
wget https://raw.githubusercontent.com/JJBanana13/CC-Tweaked-Mining-Turtle-controll/main/gps_setup.lua
gps_setup
```

### 2. Controller installieren

Auf dem Advanced Computer:

```
wget https://raw.githubusercontent.com/JJBanana13/CC-Tweaked-Mining-Turtle-controll/main/installer.lua
installer
```

### 3. Turtles installieren

Auf jeder Mining Turtle:

```
wget https://raw.githubusercontent.com/JJBanana13/CC-Tweaked-Mining-Turtle-controll/main/installer.lua
installer
```

Der Installer erkennt automatisch ob es ein Computer oder eine Turtle ist.

## Steuerung

### Monitor (Touch)
- Chunk auf Karte antippen = auswaehlen
- **START/PAUSE** Button = Mining starten/pausieren
- **RECALL** Button = Alle Turtles zurueckrufen
- **+CHUNKS** Button = Neue Chunks zur Queue hinzufuegen

### Tastatur (am Controller-Computer)
| Taste | Funktion |
|-------|----------|
| Pfeiltasten | Cursor auf Chunk-Map bewegen |
| Enter | Chunk zur Queue hinzufuegen |
| P | Pause/Resume |
| R | Recall alle Turtles |
| G | Neue Chunks generieren |
| O | Cursor als neuen Startpunkt setzen |
| Q | Controller beenden |

## Mining-Pattern

Die Chunks werden im Zickzack abgebaut (geradeaus + rechts):

```
Start -> [1] [2] [3] [4] [5] [6] [7] [8]    Reihe 1: ->
         [16][15][14][13][12][11][10][ 9]    Reihe 2: <-
         [17][18][19][20][21][22][23][24]    Reihe 3: ->
         ...
```

Innerhalb jedes Chunks wird schichtweise im Serpentinen-Muster abgebaut:
- Von Y:319 bis Y:-64
- 2 Ebenen pro Durchgang (Block vor sich + Block unter sich)
- Automatische Heim-Fahrten bei vollem Inventar oder niedrigem Fuel

## Monitor-Anzeige

```
 ATM10 MINING FLEET          [16/16 Online]
 ============================================
 CHUNK MAP:            TURTLE STATUS:
 # # # # . . . .      T01 Mining  Y:45  F:8420
 # # # > . . . .      T02 Mining  Y:32  F:6100
 # # . . . . . .      T03 Travel  Y:64  F:3200
 . . . . . . . .      T04 Idle    ---   F:9999
                       T05 Refuel  Home  F:500
 #=Fertig >=Aktiv
 ~=Queue  .=Offen

 [PAUSE] [RECALL] [+CHUNKS]
 Chunks: 24/128 fertig | Zeit: 02:45:30
```

### Farben
| Farbe | Bedeutung |
|-------|-----------|
| Gruen (#) | Chunk fertig |
| Cyan (>) | Chunk wird abgebaut |
| Gelb (~) | Chunk in Queue |
| Grau (.) | Chunk offen |
| Weiss (X) | Cursor |

## Konfiguration

### Controller
```
controller config
```
- Monitor-Seite
- Start-Chunk-Koordinaten (Chunk-Koordinaten, nicht Block!)
- Reihenbreite (Standard: 8)
- Gesamtanzahl Chunks
- Min/Max Y-Level

### Turtle
```
miner config
```
- Home-Position (GPS oder manuell)
- Blickrichtung an Home
- Fuel-Chest Richtung
- Item-Chest Richtung
- Minimaler Fuel-Level

## Dateistruktur

```
shared/
  protocol.lua        - Gemeinsame Protokoll-Konstanten
controller/
  controller.lua      - Hauptprogramm Controller
  startup.lua         - Auto-Start
turtle/
  miner.lua           - Hauptprogramm Turtle
  startup.lua         - Auto-Start mit Resume
installer.lua         - Ein-Klick-Installer
gps_setup.lua         - GPS-Helfer
```

## Troubleshooting

**Turtles verbinden sich nicht:**
- Pruefen ob Ender Modem/Wireless Modem angeschlossen
- Pruefen ob GPS-Satelliten laufen: `gps locate`
- Reichweite pruefen (Ender Modem = unbegrenzt)

**Turtle bleibt stecken:**
- Turtle neustartet automatisch und setzt fort (State-Persistenz)
- Controller erkennt offline Turtles nach 120s und gibt Chunk frei

**Monitor zeigt nichts:**
- `controller config` ausfuehren und Monitor-Seite pruefen
- Monitor muss min. 4x3 Bloecke gross sein

**Fuel-Probleme:**
- Fuel-Chest muss auf der konfigurierten Seite stehen
- Turtle braucht genug Fuel fuer Hin- und Rueckweg + Mining

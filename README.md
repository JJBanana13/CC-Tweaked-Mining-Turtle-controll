# CC-Tweaked Mining Turtle Control System

Ein automatisiertes Chunk-Mining-System fuer Minecraft ATM10 mit CC:Tweaked.
Steuert bis zu 16 Mining Turtles, die systematisch Chunks von oben bis unten abbauen.

## Features

- **16 Mining Turtles** die parallel Chunks abbauen
- **Zentraler Server** mit Monitor-UI zur Ueberwachung und Steuerung
- **Automatische Chunk-Zuweisung** - Spiralfoermig um den Startpunkt
- **Fuel Management** - Turtles tanken automatisch an der Fuel Chest
- **Inventar Management** - Automatisches Abladen an der Output Chest
- **Auto-Recovery** - Turtles starten nach Server-Neustart neu
- **Persistenter Zustand** - Server speichert Fortschritt automatisch
- **Dead-Turtle Detection** - Erkennt nicht erreichbare Turtles

## Aufbau

```
Projekt/
├── shared/
│   ├── config.lua       -- Konfiguration (Positionen, Settings)
│   └── protocol.lua     -- Rednet Kommunikationsprotokoll
├── turtle/
│   ├── chunk_miner.lua  -- Mining-Programm fuer die Turtles
│   └── startup.lua      -- Startup-Script fuer Turtles
├── server/
│   ├── server.lua       -- Server/Controller-Programm
│   └── startup.lua      -- Startup-Script fuer Server
└── installer.lua        -- Automatischer Installer (wget)
```

## Voraussetzungen

### Hardware (In-Game)

- **1x Advanced Computer** (Server) + Wireless Modem
- **1x Monitor** (mindestens 4x3 Bloecke empfohlen) am Server
- **16x Mining Turtles** (jeweils mit Wireless Modem + Diamond/Netherite Pickaxe)
- **1x Chest** fuer Fuel (Kohle, Lava Eimer, etc.)
- **1x Chest** fuer Output (geminete Items)
- **4x GPS Satelliten** (Computer mit Wireless Modem auf hohen Positionen)

### GPS Setup

Du brauchst mindestens 4 GPS-Hosts damit die Turtles ihre Position kennen.
Platziere 4 Computer mit Wireless Modem auf hohen Positionen und starte:

```lua
shell.run("gps", "host", X, Y, Z)
```

(Ersetze X, Y, Z mit den tatsaechlichen Koordinaten des Computers)

## Setup-Anleitung

### 1. Basis aufbauen

```
[Fuel Chest] [Output Chest]
             [Server Computer]
             [Monitor]
```

- Notiere die Koordinaten der Fuel Chest (das wird `BASE_X`, `BASE_Y`, `BASE_Z`)
- Die Output Chest ist 1 Block daneben (Ost/+X Richtung)

### 2. Automatische Installation (empfohlen)

Fuehre auf dem **Server-Computer** aus:
```
wget run https://raw.githubusercontent.com/JJBanana13/CC-Tweaked-Mining-Turtle-controll/main/installer.lua
```
Waehle `1` (Server). Dann auf jeder **Turtle** denselben Befehl ausfuehren und `2` (Turtle) waehlen.

Oder direkt mit Argument:
```
wget run https://raw.githubusercontent.com/JJBanana13/CC-Tweaked-Mining-Turtle-controll/main/installer.lua server
wget run https://raw.githubusercontent.com/JJBanana13/CC-Tweaked-Mining-Turtle-controll/main/installer.lua turtle
```

### 3. Konfiguration anpassen

Bearbeite `shared/config.lua` (auf Server UND allen Turtles):

```lua
-- Setze die Position deiner Fuel Chest
config.BASE_X = 100      -- X-Koordinate
config.BASE_Y = 200      -- Y-Koordinate
config.BASE_Z = 100      -- Z-Koordinate

-- Mining Dimension Hoehe (Standard fuer ATM10)
config.MAX_Y = 319       -- Oberste Ebene
config.MIN_Y = -64        -- Unterste Ebene

-- Erster Chunk der abgebaut wird
config.START_CHUNK_X = 0  -- Chunk-X (Block-X / 16)
config.START_CHUNK_Z = 0  -- Chunk-Z (Block-Z / 16)
```

### 4. Starten

1. Zuerst den **Server** starten (Computer rebooten)
2. Dann die **Turtles** starten (jeweils rebooten)
3. Die Turtles registrieren sich automatisch beim Server
4. Der Server weist jedem Turtle einen Chunk zu

## Server-Befehle

| Befehl | Beschreibung |
|--------|-------------|
| `help` | Zeigt alle Befehle |
| `status` | Zeigt Status aller Turtles |
| `stats` | Zeigt Statistiken (Bloecke, Chunks, Laufzeit) |
| `pause` | Pausiert alle Turtles |
| `resume` | Setzt alle Turtles fort |
| `stop` | Stoppt alle Turtles (fahren zur Basis) |
| `home` | Alle Turtles zur Basis rufen |
| `add <n>` | N neue Chunks zur Warteschlange |
| `queue` | Zeigt Chunk-Warteschlange |
| `quit` | Server beenden |

## Monitor-Anzeige

Der Monitor zeigt:
- Server-Status (Aktiv/Pausiert)
- Laufzeit und Statistiken
- Alle Turtles mit:
  - Name und Status (farbcodiert)
  - Fuel-Level (rot wenn niedrig)
  - Aktueller Chunk
  - Aktuelle Y-Ebene

### Farbcodes
- **Gruen** = Mining
- **Cyan** = Unterwegs
- **Orange** = Tankt
- **Magenta** = Laedt ab
- **Gelb** = Pausiert
- **Rot** = Fehler

## Mining-Muster

Jeder Chunk (16x16 Bloecke) wird schichtweise von oben nach unten abgebaut:
- Serpentinen-Muster pro Ebene (wie ein Drucker)
- 2 Ebenen pro Durchgang (grabung nach unten)
- Automatischer Rueckflug bei vollem Inventar oder niedrigem Fuel
- Chunks werden spiralfoermig um den Startpunkt zugewiesen

## Troubleshooting

**Turtle bewegt sich nicht:**
- Pruefe ob Fuel vorhanden ist (Kohle/Lava in Fuel Chest)
- Pruefe ob Wireless Modem angebracht ist
- Pruefe GPS Signal

**Server findet keine Turtles:**
- Beide muessen das gleiche Protokoll nutzen (selbe config.lua)
- Wireless Modem muss auf beiden Seiten aktiv sein
- Reichweite pruefen (Standard: 64 Bloecke, mit Ender Modem: unbegrenzt)

**Turtle bleibt stecken:**
- Die Turtle versucht 30x ein Hindernis zu entfernen
- Bei Bedrock oder geschuetzten Bloecken bleibt sie stecken
- Server erkennt "tote" Turtles nach 120 Sekunden und weist den Chunk neu zu

## Lizenz

CC0 1.0 Universal - Public Domain

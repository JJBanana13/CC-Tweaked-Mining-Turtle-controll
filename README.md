# CC-Tweaked Mining Turtle Control System

Ein automatisiertes Chunk-Mining-System fuer Minecraft ATM10 mit CC:Tweaked.
Steuert bis zu 16 Mining Turtles, die systematisch Chunks von oben bis unten abbauen.

## Features

- **16 Mining Turtles** die parallel Chunks abbauen
- **Zentraler Server** mit Monitor-UI zur Ueberwachung und Steuerung
- **Touch-Monitor-UI** - Mastermine-Style Oberflaeche mit Touch-Buttons (Start/Stop/Pause/Home/Resume)
- **Manueller Start** - Turtles registrieren sich, bleiben aber idle bis man START drueckt
- **Block-Schutz** - Turtles bauen KEINE CC-Bloecke ab (Computer, Turtles, Modems etc.)
- **Chunk-Schutz** - Basis-Chunk automatisch geschuetzt, weitere Chunks per Config ausschliessbar (z.B. GPS Server)
- **Automatische Chunk-Zuweisung** - Spiralfoermig um den Startpunkt
- **Fuel Management** - Turtles tanken automatisch an der Fuel Chest
- **Inventar Management** - Automatisches Abladen an der Output Chest
- **Auto-Recovery** - Turtles starten nach Server-Neustart neu
- **Persistenter Zustand** - Server speichert Fortschritt automatisch
- **Dead-Turtle Detection** - Erkennt nicht erreichbare Turtles
- **Home-Position** - Turtles merken sich wo sie aufgebaut wurden und kehren bei Pause/Stop dorthin zurueck
- **Zentrale Config** - Config nur auf dem Server, Turtles empfangen sie automatisch per Rednet

## Aufbau

```
Projekt/
├── shared/
│   ├── config.lua       -- Konfiguration (NUR auf Server!)
│   └── protocol.lua     -- Rednet Kommunikationsprotokoll
├── turtle/
│   ├── chunk_miner.lua  -- Mining-Programm (bekommt Config vom Server)
│   └── startup.lua      -- Startup-Script fuer Turtles
├── server/
│   ├── server.lua       -- Server/Controller-Programm
│   ├── monitor_ui.lua   -- Touch-Monitor-UI (Mastermine-Style)
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

### 3. Konfiguration anpassen (NUR auf dem Server!)

Bearbeite `shared/config.lua` auf dem **Server-Computer**. Turtles brauchen KEINE Config - sie empfangen alles automatisch vom Server:

```lua
-- Setze die Position deiner Fuel Chest (Block-Koordinaten aus F3-Screen)
config.BASE_X = 100      -- X-Koordinate
config.BASE_Y = 200      -- Y-Koordinate
config.BASE_Z = 100      -- Z-Koordinate

-- Mining Dimension Hoehe (Standard fuer ATM10)
config.MAX_Y = 319       -- Oberste Ebene
config.MIN_Y = -64        -- Unterste Ebene
```

Das Mining startet automatisch im Chunk wo die Basis steht und arbeitet sich spiralfoermig nach aussen vor.
Der Basis-Chunk selbst wird automatisch uebersprungen (Schutz fuer Server/Chests).

#### Chunks schuetzen (optional)

Falls du bestimmte Chunks vom Mining ausschliessen willst (z.B. GPS Server):

```lua
-- Chunk-Koordinaten = Block-Koordinaten / 16 (abgerundet)
-- Beispiel: Block X=256, Z=-300 -> Chunk 16, -19
config.EXCLUDE_CHUNKS = {
    { cx = 15, cz = -19 },   -- GPS Server Chunk
    { cx = 16, cz = -19 },   -- Weiterer geschuetzter Chunk
}
```

**Tipp:** Chunk-Koordinaten findest du mit F3+G (Chunk Borders) oder durch Block-Koordinate / 16.

### 4. Starten

1. Zuerst den **Server** starten (Computer rebooten)
2. Dann die **Turtles** starten (jeweils rebooten)
3. Die Turtles registrieren sich automatisch beim Server
4. **Wichtig:** Turtles bleiben nach dem Registrieren im Idle-Modus!
5. Druecke **START** auf dem Monitor oder tippe `start` in der Konsole um das Mining zu starten

## Server-Befehle

| Befehl | Beschreibung |
|--------|-------------|
| `help` | Zeigt alle Befehle |
| `status` | Zeigt Status aller Turtles |
| `stats` | Zeigt Statistiken (Bloecke, Chunks, Laufzeit) |
| `start` | Startet das Mining (hebt Pause auf) |
| `pause` | Pausiert alle Turtles (kehren zu Home zurueck) |
| `resume` | Setzt alle Turtles fort |
| `stop` | Stoppt alle Turtles (kehren zu Home zurueck) |
| `home` | Alle Turtles nach Home schicken |
| `add <n>` | N neue Chunks zur Warteschlange |
| `queue` | Zeigt Chunk-Warteschlange |
| `quit` | Server beenden |

## Monitor-Anzeige (Touch-UI)

Der Monitor zeigt eine Touch-bedienbare Oberflaeche im Mastermine-Style:

### Layout
- **Titelleiste** - "MINING CONTROL" (oben)
- **Statistiken** - Chunks fertig/in Queue, Laufzeit, Bloecke abgebaut
- **START/STOP Button** - Grosser Touch-Button oben rechts (gruen/rot)
- **Turtle-Liste** - Alle Turtles mit ID, Name, Status, Fuel, Chunk, Y-Level
- **Control-Buttons** - START ALL, PAUSE ALL, HOME ALL, RESUME ALL (unten)

### Touch-Buttons
| Button | Funktion |
|--------|----------|
| **START** (gruen) | Startet das Mining, weist Chunks zu |
| **STOP** (rot) | Pausiert alle Turtles, kehren zu Home zurueck |
| **START ALL** | Startet alle Turtles |
| **PAUSE ALL** | Pausiert alle Turtles |
| **HOME ALL** | Schickt alle Turtles nach Home |
| **RESUME ALL** | Setzt alle Turtles fort |

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
- Wireless Modem muss auf beiden Seiten aktiv sein
- Reichweite pruefen (Standard: 64 Bloecke, mit Ender Modem: unbegrenzt)
- Config muss nur auf dem Server vorhanden sein (wird automatisch gesendet)

**Turtle bleibt stecken:**
- Die Turtle versucht 30x ein Hindernis zu entfernen
- Bei Bedrock oder geschuetzten Bloecken bleibt sie stecken
- Server erkennt "tote" Turtles nach 120 Sekunden und weist den Chunk neu zu

**Block-Schutz:**
- Turtles erkennen CC-Bloecke (Computer, Turtles, Modems) automatisch per `turtle.inspect()`
- CC-Bloecke werden NICHT abgebaut sondern uebersprungen
- Geschuetzt sind alle Bloecke mit Prefix `computercraft:` oder `cc:`

**Chunk-Schutz:**
- Der Basis-Chunk (wo Server/Chests stehen) wird automatisch uebersprungen
- Weitere Chunks koennen in `config.EXCLUDE_CHUNKS` geschuetzt werden (z.B. GPS Server)
- Beim Start zeigt der Server an wieviele Chunks geschuetzt sind

## Lizenz

CC0 1.0 Universal - Public Domain

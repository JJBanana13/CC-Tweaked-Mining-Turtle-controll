# ATM 10 - Mining Turtle Fleet System (16 Turtles, Chunk Mining)

## Übersicht

Ein zentraler Controller-Computer mit Monitor steuert 16 Mining Turtles per Rednet.
Die Turtles bauen komplette Chunks (16x16, von oben bis Bedrock) ab und arbeiten sich
in einem **Geradeaus-Rechts-Muster** (Zickzack) durch die Welt - kein Kreis/Spiral-Pattern.

```
Chunk-Zuweisungs-Muster (Geradeaus + Rechts):

Start → [1] [2] [3] [4] ...  (Reihe 1: nach rechts)
                               ↓
  ... [8] [7] [6] [5]         (Reihe 2: nach links)
  ↓
  [9] [10] [11] [12] ...      (Reihe 3: nach rechts)
```

## Hardware-Setup

### Controller-Station
- 1x Advanced Computer
- 1x Wireless Modem (ender modem für große Reichweite empfohlen)
- 1x Advanced Monitor (min. 4x3 Blöcke für gute Übersicht)
- 4x GPS-Satelliten-Computer (für GPS-Netzwerk)

### Pro Mining Turtle (x16)
- 1x Advanced Mining Turtle (Wireless Modem eingebaut)
- 1x Diamond Pickaxe (oder besser)
- Fuel (Kohle/Lava-Eimer)

### Base-Station
- 1x Chest für Item-Ablage (pro Turtle oder gemeinsam)
- 1x Chest für Fuel-Nachschub

---

## Datei-Struktur

```
/
├── controller/
│   ├── startup.lua          -- Auto-Start für Controller
│   ├── controller.lua       -- Hauptprogramm: UI + Fleet-Management
│   └── gps_setup.lua        -- Helfer-Script für GPS-Satelliten-Setup
├── turtle/
│   ├── startup.lua          -- Auto-Start für Turtles
│   └── miner.lua            -- Mining-Logik + Navigation + Kommunikation
├── shared/
│   └── protocol.lua         -- Gemeinsame Nachrichtentypen & Protokoll-Konstanten
└── installer.lua            -- Ein-Klick-Installer (wget von GitHub)
```

---

## Implementierungs-Plan

### Phase 1: Shared Protocol (`shared/protocol.lua`)

Gemeinsame Konstanten und Message-Typen für Controller ↔ Turtle Kommunikation.

```lua
-- Protokoll-Name für Rednet
PROTOCOL = "atm10_fleet"

-- Nachrichtentypen
MSG = {
  -- Turtle → Controller
  REGISTER    = "register",     -- Turtle meldet sich an {id, fuel, pos}
  STATUS      = "status",       -- Status-Update {id, state, fuel, pos, chunk, y_level}
  CHUNK_DONE  = "chunk_done",   -- Chunk fertig abgebaut {id, chunk}
  NEED_FUEL   = "need_fuel",    -- Fuel niedrig {id, fuel}
  ERROR       = "error",        -- Fehler {id, message}

  -- Controller → Turtle
  ASSIGN      = "assign",       -- Chunk zuweisen {chunk={x,z}, home={x,y,z}}
  RECALL      = "recall",       -- Zurück zur Base
  PAUSE       = "pause",        -- Mining pausieren
  RESUME      = "resume",       -- Mining fortsetzen
  ACK         = "ack",          -- Registrierung bestätigt {turtle_id}
}

-- Turtle-Zustände
STATE = {
  IDLE       = "idle",
  MINING     = "mining",
  TRAVELING  = "traveling",
  REFUELING  = "refueling",
  DEPOSITING = "depositing",
  RETURNING  = "returning",
  PAUSED     = "paused",
  ERROR      = "error",
}
```

---

### Phase 2: Turtle Miner (`turtle/miner.lua`)

#### 2.1 GPS & Navigation
- **GPS-Lokalisierung**: `gps.locate()` beim Start für exakte Position
- **Richtungs-Erkennung**: 1 Block vorwärts fahren, GPS-Differenz = Blickrichtung
- **Koordinaten-Tracking**: Jede Bewegung aktualisiert interne x/y/z Position
- **`moveTo(x, y, z)`**: Pathfinding zu absoluten Koordinaten (Y zuerst hoch, dann X/Z, dann Y runter)
- **`face(direction)`**: Turtle dreht sich in gewünschte Himmelsrichtung (0=Nord, 1=Ost, 2=Süd, 3=West)

#### 2.2 Chunk-Mining-Algorithmus
```
Für jeden Chunk (16x16 Blöcke):
1. Zur Chunk-Startecke navigieren (höchster Y-Level, z.B. Y=319)
2. Schicht für Schicht abbauen (2 Ebenen pro Durchgang):
   - Serpentinen-Muster (Schlange):
     Reihe 1: →→→→→→→→→→→→→→→→ (16 Blöcke)
     Reihe 2: ←←←←←←←←←←←←←←←←
     Reihe 3: →→→→→→→→→→→→→→→→
     ... (16 Reihen)
   - Dabei: Block vor sich abbauen + Block unter sich abbauen
3. 2 Blöcke runter → nächste Doppelschicht
4. Wiederholen bis Bedrock (Y=-64 in ATM10)
```

#### 2.3 Inventar-Management
- **Alle 16 Blöcke**: Inventar-Check (14/16 Slots belegt = fast voll)
- **Wenn voll**: Zur Home-Base navigieren → Items in Chest ablegen → zurück zur Mining-Position
- **Mining-Position merken**: Vor dem Heimflug aktuelle Position + Fortschritt speichern

#### 2.4 Fuel-Management
- **Fuel-Schwellwert**: 2000 Fuel Minimum
- **Refuel-Logik**: Bei niedrigem Fuel → Home-Base → Fuel-Chest → tanken → zurück
- **Notfall**: Wenn Fuel für Heimweg nicht reicht → Controller benachrichtigen + stoppen

#### 2.5 Kommunikation
- **Beim Start**: `REGISTER` an Controller senden
- **Alle 30 Sekunden**: `STATUS`-Update (State, Fuel, Position, Y-Level)
- **Chunk fertig**: `CHUNK_DONE` senden → auf neuen `ASSIGN` warten
- **Befehle empfangen**: ASSIGN, RECALL, PAUSE, RESUME im Hintergrund-Thread

#### 2.6 State-Persistenz
- Aktuellen Zustand in Datei speichern (Position, Chunk, Y-Level, Fortschritt)
- Nach Server-Restart: Zustand laden und Mining fortsetzen
- Startup.lua prüft ob gespeicherter State existiert

---

### Phase 3: Controller (`controller/controller.lua`)

#### 3.1 Chunk-Zuweisung (Geradeaus-Rechts-Muster)

```lua
-- Zickzack-Pattern Generator:
-- Reihenbreite = konfigurierbar (z.B. 8 Chunks breit)
--
-- getNextChunk(index, rowWidth):
--   row = floor(index / rowWidth)
--   col = index % rowWidth
--   if row is gerade:  -- links nach rechts
--     chunkX = startX + col
--   else:              -- rechts nach links
--     chunkX = startX + (rowWidth - 1 - col)
--   chunkZ = startZ + row
--   return chunkX, chunkZ
```

Kein Kreis/Spiral - strikt geradeaus und dann eine Reihe nach rechts versetzt.

#### 3.2 Fleet-Management
- **Turtle-Registry**: Tabelle aller registrierten Turtles (max 16)
  - ID, State, Fuel, Position, zugewiesener Chunk, letzter Kontakt
- **Job-Queue**: Liste der nächsten abzubauenden Chunks
- **Auto-Assign**: Wenn Turtle IDLE → nächsten Chunk aus Queue zuweisen
- **Dead-Detection**: Kein Heartbeat seit 120s → als offline markieren
- **Chunk-Tracking**: Welche Chunks fertig, welche in Arbeit, welche noch offen

#### 3.3 Monitor-UI (Touch-fähig)

```
┌──────────────────────────────────────────────────┐
│  ATM10 MINING FLEET          [16/16 Online]      │
│══════════════════════════════════════════════════│
│                                                  │
│  CHUNK MAP:            TURTLE STATUS:            │
│  ■ ■ ■ ■ □ □ □ □      T01 Mining  Y:45  F:8420  │
│  ■ ■ ■ ▶ □ □ □ □      T02 Mining  Y:32  F:6100  │
│  ■ ■ □ □ □ □ □ □      T03 Travel  Y:64  F:3200  │
│  □ □ □ □ □ □ □ □      T04 Idle    ---   F:9999  │
│                        T05 Refuel  Home  F:500   │
│  ■ = Fertig (grün)     T06 Mining  Y:12  F:7800  │
│  ▶ = Aktiv  (cyan)     T07 Mining  Y:58  F:5400  │
│  □ = Offen  (grau)     T08 Error!  Y:30  F:200   │
│  ◉ = Selected (gelb)   ...                       │
│                                                  │
│  [START] [PAUSE] [RECALL ALL] [+CHUNKS]          │
│  Chunks: 24/128 fertig | Laufzeit: 02:45:30      │
├──────────────────────────────────────────────────┤
│  > Nächster Chunk: X:48 Z:32                     │
│  > Fehler: T08 - Fuel zu niedrig!                │
└──────────────────────────────────────────────────┘
```

**Touch-Aktionen auf dem Monitor:**
- Chunk auf Karte antippen → als nächstes zuweisen / Info anzeigen
- Turtle in Liste antippen → Detail-Ansicht (Fuel, Position, Chunk-Fortschritt)
- Buttons: START, PAUSE ALL, RECALL ALL, Chunks hinzufügen

#### 3.4 Tastatur-Steuerung (am Computer)
- Pfeiltasten: Cursor auf Chunk-Karte bewegen
- Enter: Ausgewählten Chunk zur Queue hinzufügen
- R: Alle Turtles zurückrufen
- P: Pause/Resume toggle
- O: Neuen Ursprung setzen
- +/-: Reihenbreite anpassen
- S: Statistiken anzeigen

#### 3.5 State-Persistenz
- Alle 30 Sekunden automatisch speichern:
  - Fertige Chunks
  - Aktive Zuweisungen
  - Turtle-Registry
  - Queue
  - Statistiken (Laufzeit, Chunks/Stunde, etc.)
- Beim Start: State laden und fortsetzen

---

### Phase 4: Startup & Installer

#### 4.1 `turtle/startup.lua`
```lua
-- Prüft ob miner.lua existiert
-- Prüft ob gespeicherter State existiert → Resume
-- Startet miner.lua automatisch
```

#### 4.2 `controller/startup.lua`
```lua
-- Startet controller.lua automatisch
-- Öffnet Rednet auf Wireless Modem
```

#### 4.3 `installer.lua`
```lua
-- Erkennt ob Computer oder Turtle
-- Lädt passende Dateien von GitHub (wget)
-- Erstellt startup.lua
-- Interaktive Konfiguration:
--   Controller: Monitor-Seite, Start-Koordinaten, Reihenbreite
--   Turtle: Fuel-Chest-Seite, Item-Chest-Seite, Home-Position
```

#### 4.4 `gps_setup.lua`
```lua
-- Helfer-Script für GPS-Satelliten
-- Fragt nach Koordinaten der 4 GPS-Computer
-- Generiert startup.lua für jeden GPS-Satelliten
```

---

### Phase 5: Fortgeschrittene Features

#### 5.1 Automatische Chunk-Reihenfolge
- Controller berechnet automatisch den nächsten Chunk basierend auf dem Zickzack-Pattern
- Konfigurierbare Reihenbreite (Standard: 8 Chunks)
- Konfigurierbare Startposition (Chunk-Koordinaten)

#### 5.2 Smarte Fuel-Berechnung
- Entfernung zum Chunk × 2 (hin + zurück) + 16×16×(319+64)/2 Blöcke Mining
- Turtle bekommt nur Chunks die sie mit aktuellem Fuel schaffen kann
- Oder: Turtle refuelt automatisch vor jedem neuen Chunk

#### 5.3 Fehler-Recovery
- Turtle startet nach Crash neu → liest State-File → setzt Mining fort
- Controller erkennt offline Turtles → weist deren Chunks neu zu nach Timeout
- Unvollständige Chunks werden neu in die Queue aufgenommen

#### 5.4 Statistiken
- Chunks pro Stunde
- Durchschnittlicher Fuel-Verbrauch pro Chunk
- Geschätzte Restzeit
- Items pro Chunk (wenn trackbar)

---

## Implementierungs-Reihenfolge

| Schritt | Datei | Beschreibung | Abhängig von |
|---------|-------|--------------|--------------|
| 1 | `shared/protocol.lua` | Protokoll-Konstanten | - |
| 2 | `turtle/miner.lua` | GPS, Navigation, Mining-Core | Step 1 |
| 3 | `turtle/miner.lua` | Inventar, Fuel, Kommunikation | Step 2 |
| 4 | `turtle/miner.lua` | State-Persistenz, Resume | Step 3 |
| 5 | `controller/controller.lua` | Fleet-Management, Chunk-Queue | Step 1 |
| 6 | `controller/controller.lua` | Monitor-UI mit Chunk-Map | Step 5 |
| 7 | `controller/controller.lua` | Touch-Input, Tastatur-Steuerung | Step 6 |
| 8 | `controller/controller.lua` | State-Persistenz | Step 7 |
| 9 | `turtle/startup.lua` | Auto-Start + Resume | Step 4 |
| 10 | `controller/startup.lua` | Auto-Start | Step 8 |
| 11 | `installer.lua` | GitHub-basierter Installer | Step 9, 10 |
| 12 | `gps_setup.lua` | GPS-Helfer-Script | - |
| 13 | Testing & Bugfixes | Gesamtsystem testen | Alle |

---

## Konfiguration (wird beim Install abgefragt)

### Controller-Config
```lua
{
  monitorSide = "top",          -- Wo ist der Monitor?
  startChunkX = 0,              -- Erster Chunk X
  startChunkZ = 0,              -- Erster Chunk Z
  rowWidth = 8,                 -- Chunks pro Reihe
  totalChunks = 128,            -- Wie viele Chunks insgesamt
  minY = -64,                   -- Tiefste Mining-Ebene
  maxY = 319,                   -- Höchste Mining-Ebene
}
```

### Turtle-Config
```lua
{
  homeX = 0, homeY = 64, homeZ = 0,  -- Home-Base GPS-Koordinaten
  fuelChestDir = "left",              -- Wo ist die Fuel-Chest?
  itemChestDir = "front",             -- Wo ist die Item-Chest?
  minFuel = 2000,                     -- Fuel-Schwellwert
}
```

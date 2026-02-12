# ATM10 ChunkFleet (MasterMine-Style Chunk Mining)

Dieses Projekt liefert ein **MasterMine-ähnliches System für Chunk-Mining** statt Strip-Mining:

- Zentrale Controller-UI mit Karte
- 16+ Advanced Mining Turtles
- Chunk auswählen -> Turtle mined den ganzen Chunk nach unten
- Auto-Entladen in General Chest + Auto-Refuel aus Fuel Chest

## Enthaltene Dateien

- `controller/mastermine.lua` - Controller mit Karte, Job-Queue, Mined-Tracking
- `turtles/miner.lua` - Turtle-Worker für Chunk-Mining
- `install.lua` - Installer (installiert Controller/Turtle als `startup`)

## Installer (wie bei MasterMine-Workflow)

1. Dateien auf Computer/Turtle verfügbar machen.
2. `install` ausführen.
3. Typ wählen:
   - `1` Controller
   - `2` Turtle
4. Ziel meist `startup`.

## Controller Features

- **Richtige Chunk-Karte** mit:
  - Cursor-Position
  - Home-Chunk (Origin)
  - aktive/queued Chunks
  - bereits geminte Chunks
  - Turtle-Position/Status
- Persistente World-State Datei `controller_state`
- Queueing und automatische Neuvergabe bei freien Turtles

### Controller Controls

- `Arrow Keys` Cursor bewegen
- `Enter` Chunk queue
- `W A S D` Karte pannen
- `- / +` Zoom ändern
- `O` Cursor als Home/Origin setzen
- `M` Chunk manuell als gemined markieren
- `R` Recall alle Turtles

## Turtle Features

- Meldet sich beim Controller an (inkl. Position/Fuel)
- Nimmt Chunk-Job an und mined 16x16 Layer für Layer nach unten
- Bei Inventar/Fuel-Bedarf: Home-Service (unload + refuel) und zurück zur Mine
- `recall` unterstützt
- Lokale Konfiguration via:

```lua
startup config
```

Konfigurierbar:
- `unloadSide`
- `fuelSide`
- `minFuel`
- `reserveFuel`

## Aufbau im Spiel

### Controller
- Advanced Computer + Wireless Modem
- Optional Monitor (Touch-Auswahl auf Karte)
- `startup` läuft Controller

### Pro Turtle
- Advanced Mining Turtle + Wireless Modem
- General Chest an `unloadSide`
- Fuel Chest an `fuelSide`
- `startup` läuft Miner

## Hinweis

Für präzise Positionsanzeige ist ein GPS-Setup empfohlen. Ohne GPS arbeitet die Turtle trotzdem über interne Positionsfortschreibung.

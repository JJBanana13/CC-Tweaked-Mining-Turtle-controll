# ATM10 Mining Fleet (MasterMine-Style) for CC:Tweaked

Dieses Repository enthält ein **Controller + Turtle-System** für **16 Advanced Mining Turtles** in ATM10.

## Features

- Chunk-basierte Jobvergabe über ein zentrales UI (ähnlich MasterMine-Stil).
- 16 Turtles können sich gleichzeitig beim Controller anmelden.
- Chunk-Auswahl per Tastatur (Pfeile + Enter) oder per Monitor-Touch.
- Turtles:
  - fahren vom Homepunkt zum ausgewählten Chunk,
  - minen den kompletten Chunk schichtweise nach unten,
  - leeren Inventar in die General Chest,
  - holen Fuel aus der Fuel Chest,
  - kehren automatisch zum Homepunkt zurück.

## Dateien

- `controller/mastermine.lua` → Steuerrechner UI + Dispatching
- `turtles/miner.lua` → Turtle-Programm (als `startup` auf jede Turtle)

## Aufbau im Spiel

### Controller (Advanced Computer)

1. Stelle einen Advanced Computer mit **Wireless Modem** auf.
2. Optional: Monitor an eine Seite (Touch-Chunk-Auswahl).
3. Kopiere `controller/mastermine.lua` auf den Computer und starte es.

### Turtles (16x Advanced Mining Turtle)

1. Alle 16 Turtles starten am Homepunkt (`0,0,0`) bzw. derselben Dock-Position relativ zu ihren Chests.
2. Jede Turtle braucht ein Wireless Modem.
3. Lege `turtles/miner.lua` als `startup` auf jede Turtle.
4. Stelle pro Turtle sicher:
   - **General Chest** liegt an `unloadSide`
   - **Fuel Chest** liegt an `fuelSide`

Konfiguration je Turtle:

```lua
miner config
```

Danach Side-Konfiguration und Mindestfuel setzen.

## Controller Bedienung

- **Pfeiltasten**: Chunk-Cursor bewegen
- **Enter**: Chunk als Mining-Job senden
- **R**: Recall an alle Turtles (alle fahren nach Hause)
- **O**: Aktuelle Cursor-Position als neue Origin speichern

## Hinweise

- Für exakte Weltkoordinaten ist ein GPS-Netzwerk empfohlen.
- Das Beispiel nutzt Chunkgröße 16x16 und schichtweises Mining bis kein `down()` mehr möglich ist.
- Bei komplexen Basen ggf. `moveTo(0,0,0)`-Home-Logik pro Turtle anpassen.


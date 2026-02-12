-- ============================================
-- Konfiguration fuer das Mining Turtle System
-- ============================================

local config = {}

-- Rednet Protokoll
config.PROTOCOL = "chunk_mining"
config.CHANNEL = 100

-- Chunk Groesse
config.CHUNK_SIZE = 16

-- Mining Dimension Hoehe (ATM10 Mining Dim)
config.MAX_Y = 319
config.MIN_Y = -64

-- Fuel Settings
config.FUEL_THRESHOLD = 1000      -- Ab wann tanken
config.FUEL_SLOT = 1              -- Slot fuer Fuel in der Turtle

-- Anzahl Turtles
config.MAX_TURTLES = 16

-- Basis-Position (wo Fuel/Output Chest stehen)
-- Muss beim Setup angepasst werden!
config.BASE_X = 0
config.BASE_Y = 200
config.BASE_Z = 0

-- Chest Positionen (relativ zur Basis)
config.FUEL_CHEST = { x = 0, y = 0, z = 0 }      -- Fuel Chest = Basis
config.OUTPUT_CHEST = { x = 1, y = 0, z = 0 }     -- Output Chest = 1 Block daneben

-- Chunk-Zuweisung Start (erster Chunk der abgebaut wird)
config.START_CHUNK_X = 0
config.START_CHUNK_Z = 0

-- Nachrichten-Typen
config.MSG = {
    -- Turtle -> Server
    REGISTER = "register",
    STATUS = "status",
    CHUNK_DONE = "chunk_done",
    NEED_FUEL = "need_fuel",
    INVENTORY_FULL = "inv_full",
    ERROR = "error",
    HEARTBEAT = "heartbeat",

    -- Server -> Turtle
    ASSIGN_CHUNK = "assign_chunk",
    GO_REFUEL = "go_refuel",
    GO_DEPOSIT = "go_deposit",
    PAUSE = "pause",
    RESUME = "resume",
    STOP = "stop",
    COME_HOME = "come_home",
}

-- Turtle Status
config.STATE = {
    IDLE = "idle",
    MINING = "mining",
    TRAVELING = "traveling",
    REFUELING = "refueling",
    DEPOSITING = "depositing",
    PAUSED = "paused",
    ERROR = "error",
    DONE = "done",
}

return config

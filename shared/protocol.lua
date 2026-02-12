-- ============================================================
-- ATM10 Mining Fleet - Shared Protocol
-- Gemeinsame Konstanten fuer Controller <-> Turtle Kommunikation
-- ============================================================

local protocol = {}

-- Rednet Protokoll-Name
protocol.PROTOCOL = "atm10_fleet"

-- Rednet Channel (falls ohne Rednet API)
protocol.CHANNEL = 4210

-- Nachrichtentypen: Turtle -> Controller
protocol.MSG = {
    REGISTER    = "register",       -- {id, fuel, pos, label}
    STATUS      = "status",         -- {id, state, fuel, pos, chunk, y_level, progress}
    CHUNK_DONE  = "chunk_done",     -- {id, chunk}
    NEED_FUEL   = "need_fuel",      -- {id, fuel}
    ERROR       = "error",          -- {id, message}
    HEARTBEAT   = "heartbeat",      -- {id, fuel, state}

    -- Controller -> Turtle
    ASSIGN      = "assign",         -- {chunk={x,z}, minY, maxY}
    RECALL      = "recall",         -- Zurueck zur Base
    PAUSE       = "pause",          -- Mining pausieren
    RESUME      = "resume",         -- Mining fortsetzen
    ACK         = "ack",            -- Registrierung bestaetigt {id}
}

-- Turtle-Zustaende
protocol.STATE = {
    IDLE        = "idle",
    MINING      = "mining",
    TRAVELING   = "traveling",
    REFUELING   = "refueling",
    DEPOSITING  = "depositing",
    RETURNING   = "returning",
    PAUSED      = "paused",
    ERROR       = "error",
    OFFLINE     = "offline",
}

-- Farben fuer Zustaende (Monitor-UI)
protocol.STATE_COLORS = {
    idle        = colors.white,
    mining      = colors.lime,
    traveling   = colors.cyan,
    refueling   = colors.orange,
    depositing  = colors.magenta,
    returning   = colors.yellow,
    paused      = colors.lightGray,
    error       = colors.red,
    offline     = colors.gray,
}

-- Chunk-Map Farben
protocol.MAP_COLORS = {
    done        = colors.green,
    active      = colors.cyan,
    queued      = colors.yellow,
    open        = colors.gray,
    selected    = colors.white,
}

-- Standard-Konfiguration
protocol.DEFAULTS = {
    minY        = -64,
    maxY        = 319,
    chunkSize   = 16,
    minFuel     = 2000,
    rowWidth    = 8,
    heartbeatInterval = 30,     -- Sekunden
    deadTimeout = 120,          -- Sekunden ohne Heartbeat = offline
    saveInterval = 30,          -- Sekunden zwischen Auto-Saves
    maxTurtles  = 16,
}

-- Hilfsfunktion: Nachricht erstellen
function protocol.makeMessage(msgType, data)
    data = data or {}
    data.type = msgType
    data.sender = os.getComputerID()
    data.timestamp = os.clock()
    return data
end

-- Hilfsfunktion: Nachricht senden
function protocol.send(targetId, msgType, data)
    local msg = protocol.makeMessage(msgType, data)
    rednet.send(targetId, msg, protocol.PROTOCOL)
end

-- Hilfsfunktion: Broadcast
function protocol.broadcast(msgType, data)
    local msg = protocol.makeMessage(msgType, data)
    rednet.broadcast(msg, protocol.PROTOCOL)
end

-- Hilfsfunktion: Empfangen mit Timeout
function protocol.receive(timeout)
    local senderId, msg = rednet.receive(protocol.PROTOCOL, timeout)
    if senderId and type(msg) == "table" and msg.type then
        return senderId, msg
    end
    return nil, nil
end

return protocol

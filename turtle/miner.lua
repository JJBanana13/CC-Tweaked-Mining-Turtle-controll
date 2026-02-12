-- ============================================================
-- ATM10 Mining Fleet - Turtle Miner
-- Autonomes Chunk-Mining mit GPS, Rednet & State-Persistenz
-- ============================================================

-- Lade Protocol (wird vom Installer neben miner.lua gelegt)
local protocol = require("protocol")
local MSG = protocol.MSG
local STATE = protocol.STATE

-- ============================================================
-- KONFIGURATION
-- ============================================================

local CONFIG_FILE = "miner_config"
local STATE_FILE = "miner_state"

local config = {
    homeX = 0,
    homeY = 64,
    homeZ = 0,
    fuelChestDir = "left",      -- Richtung der Fuel-Chest (von Home aus)
    itemChestDir = "front",     -- Richtung der Item-Chest (von Home aus)
    minFuel = 2000,
    homeFacing = 0,             -- Blickrichtung an Home (0=Nord)
}

-- ============================================================
-- STATE
-- ============================================================

local state = {
    pos = { x = 0, y = 0, z = 0 },
    facing = 0,                 -- 0=Nord(-Z), 1=Ost(+X), 2=Sued(+Z), 3=West(-X)
    status = STATE.IDLE,
    activeChunk = nil,          -- {x, z}
    miningState = nil,          -- {layer, row, col, direction, minY, maxY}
    controllerId = nil,
    paused = false,
}

-- Richtungs-Vektoren: dx, dz fuer facing 0-3
local DIRS = {
    [0] = { dx = 0,  dz = -1 },    -- Nord
    [1] = { dx = 1,  dz = 0 },     -- Ost
    [2] = { dx = 0,  dz = 1 },     -- Sued
    [3] = { dx = -1, dz = 0 },     -- West
}

-- ============================================================
-- PERSISTENZ
-- ============================================================

local function saveConfig()
    local f = fs.open(CONFIG_FILE, "w")
    f.write(textutils.serialise(config))
    f.close()
end

local function loadConfig()
    if fs.exists(CONFIG_FILE) then
        local f = fs.open(CONFIG_FILE, "r")
        local data = textutils.unserialise(f.readAll())
        f.close()
        if data then
            for k, v in pairs(data) do config[k] = v end
        end
        return true
    end
    return false
end

local function saveState()
    local f = fs.open(STATE_FILE, "w")
    f.write(textutils.serialise(state))
    f.close()
end

local function loadState()
    if fs.exists(STATE_FILE) then
        local f = fs.open(STATE_FILE, "r")
        local data = textutils.unserialise(f.readAll())
        f.close()
        if data then
            for k, v in pairs(data) do state[k] = v end
            return true
        end
    end
    return false
end

local function clearState()
    state.activeChunk = nil
    state.miningState = nil
    state.status = STATE.IDLE
    saveState()
end

-- ============================================================
-- KONFIGURATIONSMODUS
-- ============================================================

local function runConfigMode()
    print("=== Turtle Miner Konfiguration ===")
    print()

    -- GPS Position als Home?
    print("GPS-Position als Home nutzen? (j/n)")
    local useGps = read()
    if useGps == "j" or useGps == "J" then
        print("Ermittle GPS-Position...")
        local x, y, z = gps.locate(5)
        if x then
            config.homeX = math.floor(x)
            config.homeY = math.floor(y)
            config.homeZ = math.floor(z)
            print("Home: " .. config.homeX .. ", " .. config.homeY .. ", " .. config.homeZ)
        else
            print("GPS nicht verfuegbar! Manuell eingeben:")
            print("Home X:") config.homeX = tonumber(read()) or 0
            print("Home Y:") config.homeY = tonumber(read()) or 64
            print("Home Z:") config.homeZ = tonumber(read()) or 0
        end
    else
        print("Home X:") config.homeX = tonumber(read()) or 0
        print("Home Y:") config.homeY = tonumber(read()) or 64
        print("Home Z:") config.homeZ = tonumber(read()) or 0
    end

    print()
    print("Blickrichtung an Home-Position?")
    print("  0 = Nord (-Z)")
    print("  1 = Ost  (+X)")
    print("  2 = Sued (+Z)")
    print("  3 = West (-X)")
    config.homeFacing = tonumber(read()) or 0

    print()
    print("Fuel-Chest Richtung (von Home aus gesehen)?")
    print("  front / back / left / right")
    local fd = read()
    if fd == "front" or fd == "back" or fd == "left" or fd == "right" then
        config.fuelChestDir = fd
    end

    print()
    print("Item-Chest Richtung (von Home aus gesehen)?")
    print("  front / back / left / right")
    local id = read()
    if id == "front" or id == "back" or id == "left" or id == "right" then
        config.itemChestDir = id
    end

    print()
    print("Minimaler Fuel-Level (Standard: 2000):")
    config.minFuel = tonumber(read()) or 2000

    saveConfig()
    print()
    print("Konfiguration gespeichert!")
    print("Starte Turtle mit: miner")
end

-- ============================================================
-- GPS & NAVIGATION
-- ============================================================

local function detectFacing()
    -- Versuche 1 Block vorwaerts zu fahren und GPS-Differenz zu messen
    local x1, _, z1 = gps.locate(5)
    if not x1 then return false end

    -- Versuche vorwaerts
    local moved = false
    for attempt = 1, 5 do
        if turtle.forward() then
            moved = true
            break
        end
        turtle.dig()
        turtle.attack()
    end

    if not moved then
        -- Versuche andere Richtung
        turtle.turnRight()
        for attempt = 1, 5 do
            if turtle.forward() then
                moved = true
                break
            end
            turtle.dig()
            turtle.attack()
        end
        if not moved then
            turtle.turnLeft()  -- Zurueckdrehen
            return false
        end
        local x2, _, z2 = gps.locate(5)
        if not x2 then
            turtle.back()
            turtle.turnLeft()
            return false
        end
        turtle.back()
        turtle.turnLeft()
        -- Wir sind nach rechts gefahren, also +1 Drehung
        local dx = math.floor(x2) - math.floor(x1)
        local dz = math.floor(z2) - math.floor(z1)
        local detectedFacing = -1
        for f = 0, 3 do
            if DIRS[f].dx == dx and DIRS[f].dz == dz then
                detectedFacing = f
                break
            end
        end
        if detectedFacing >= 0 then
            -- Die erkannte Richtung war nach rechts, also actual facing = detected - 1
            state.facing = (detectedFacing - 1) % 4
            return true
        end
        return false
    end

    local x2, _, z2 = gps.locate(5)
    turtle.back()  -- Zurueck zur Ausgangsposition
    if not x2 then return false end

    local dx = math.floor(x2) - math.floor(x1)
    local dz = math.floor(z2) - math.floor(z1)

    for f = 0, 3 do
        if DIRS[f].dx == dx and DIRS[f].dz == dz then
            state.facing = f
            return true
        end
    end
    return false
end

local function gpsLocate()
    local x, y, z = gps.locate(5)
    if x then
        state.pos.x = math.floor(x)
        state.pos.y = math.floor(y)
        state.pos.z = math.floor(z)
        return true
    end
    return false
end

local function initGPS()
    print("GPS-Position ermitteln...")
    if not gpsLocate() then
        print("FEHLER: GPS nicht verfuegbar!")
        print("Stelle sicher, dass GPS-Satelliten laufen.")
        return false
    end
    print("Position: " .. state.pos.x .. ", " .. state.pos.y .. ", " .. state.pos.z)

    print("Blickrichtung ermitteln...")
    if not detectFacing() then
        print("WARNUNG: Richtung konnte nicht erkannt werden.")
        print("Nutze konfigurierte Home-Richtung: " .. config.homeFacing)
        state.facing = config.homeFacing
    end
    print("Facing: " .. state.facing .. " (" .. ({"Nord","Ost","Sued","West"})[state.facing + 1] .. ")")
    return true
end

-- ============================================================
-- BEWEGUNG
-- ============================================================

local function turnRight()
    turtle.turnRight()
    state.facing = (state.facing + 1) % 4
end

local function turnLeft()
    turtle.turnLeft()
    state.facing = (state.facing - 1) % 4
end

local function face(targetFacing)
    targetFacing = targetFacing % 4
    if state.facing == targetFacing then return end
    local diff = (targetFacing - state.facing) % 4
    if diff == 1 then
        turnRight()
    elseif diff == 2 then
        turnRight()
        turnRight()
    elseif diff == 3 then
        turnLeft()
    end
end

local function digForward()
    while turtle.detect() do
        turtle.dig()
        sleep(0.1)  -- Fallende Bloecke
    end
end

local function digUp()
    while turtle.detectUp() do
        turtle.digUp()
        sleep(0.1)
    end
end

local function digDown()
    turtle.digDown()
end

local function moveForward()
    digForward()
    local tries = 0
    while not turtle.forward() do
        tries = tries + 1
        if tries > 30 then return false end
        turtle.dig()
        turtle.attack()
        sleep(0.2)
    end
    local dir = DIRS[state.facing]
    state.pos.x = state.pos.x + dir.dx
    state.pos.z = state.pos.z + dir.dz
    return true
end

local function moveUp()
    digUp()
    local tries = 0
    while not turtle.up() do
        tries = tries + 1
        if tries > 30 then return false end
        turtle.digUp()
        turtle.attackUp()
        sleep(0.2)
    end
    state.pos.y = state.pos.y + 1
    return true
end

local function moveDown()
    digDown()
    local tries = 0
    while not turtle.down() do
        tries = tries + 1
        if tries > 30 then return false end
        turtle.digDown()
        turtle.attackDown()
        sleep(0.2)
    end
    state.pos.y = state.pos.y - 1
    return true
end

local function moveTo(tx, ty, tz)
    -- Erst Y hoch (damit wir ueber Hindernisse kommen)
    if ty > state.pos.y then
        while state.pos.y < ty do
            if not moveUp() then return false end
        end
    end

    -- Dann X
    if tx ~= state.pos.x then
        if tx > state.pos.x then
            face(1)  -- Ost (+X)
        else
            face(3)  -- West (-X)
        end
        while state.pos.x ~= tx do
            if not moveForward() then return false end
        end
    end

    -- Dann Z
    if tz ~= state.pos.z then
        if tz > state.pos.z then
            face(2)  -- Sued (+Z)
        else
            face(0)  -- Nord (-Z)
        end
        while state.pos.z ~= tz do
            if not moveForward() then return false end
        end
    end

    -- Dann Y runter
    if ty < state.pos.y then
        while state.pos.y > ty do
            if not moveDown() then return false end
        end
    end

    return true
end

-- ============================================================
-- INVENTAR & FUEL
-- ============================================================

local function inventoryFull()
    local usedSlots = 0
    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then
            usedSlots = usedSlots + 1
        end
    end
    return usedSlots >= 14
end

local function fuelLow()
    return turtle.getFuelLevel() < config.minFuel
end

local function fuelCritical()
    -- Genug Fuel um nach Hause zu kommen?
    local dist = math.abs(state.pos.x - config.homeX)
                + math.abs(state.pos.y - config.homeY)
                + math.abs(state.pos.z - config.homeZ)
    return turtle.getFuelLevel() < (dist + 100)
end

local function faceSide(side)
    -- Dreht zur angegebenen Seite (relativ zu homeFacing)
    local targetFacing = config.homeFacing
    if side == "front" then
        targetFacing = config.homeFacing
    elseif side == "right" then
        targetFacing = (config.homeFacing + 1) % 4
    elseif side == "back" then
        targetFacing = (config.homeFacing + 2) % 4
    elseif side == "left" then
        targetFacing = (config.homeFacing + 3) % 4
    end
    face(targetFacing)
end

local function unloadInventory()
    faceSide(config.itemChestDir)
    for i = 1, 16 do
        turtle.select(i)
        turtle.drop()
    end
    turtle.select(1)
end

local function refuel()
    faceSide(config.fuelChestDir)
    -- Fuel aus Chest saugen und verbrauchen
    for i = 1, 16 do
        turtle.select(i)
        turtle.suck(64)
        turtle.refuel()
    end
    -- Uebrige Items zurueck in Chest
    for i = 1, 16 do
        turtle.select(i)
        turtle.drop()
    end
    turtle.select(1)
end

local function goHomeAndService()
    local prevStatus = state.status
    local prevPos = { x = state.pos.x, y = state.pos.y, z = state.pos.z }
    local prevFacing = state.facing

    -- Zur Home-Base
    state.status = STATE.RETURNING
    sendStatus()
    moveTo(config.homeX, config.homeY, config.homeZ)

    -- Items abladen
    state.status = STATE.DEPOSITING
    sendStatus()
    unloadInventory()

    -- Fuel tanken wenn noetig
    if turtle.getFuelLevel() < config.minFuel * 2 then
        state.status = STATE.REFUELING
        sendStatus()
        refuel()
    end

    -- Status wiederherstellen
    state.status = prevStatus
    return prevPos, prevFacing
end

-- ============================================================
-- KOMMUNIKATION
-- ============================================================

function sendStatus()
    local data = {
        id = os.getComputerID(),
        label = os.getComputerLabel() or ("T" .. os.getComputerID()),
        state = state.status,
        fuel = turtle.getFuelLevel(),
        pos = { x = state.pos.x, y = state.pos.y, z = state.pos.z },
        chunk = state.activeChunk,
        y_level = state.pos.y,
    }
    if state.miningState then
        data.progress = state.miningState.layer
    end
    protocol.broadcast(MSG.STATUS, data)
end

local function sendRegister()
    local data = {
        id = os.getComputerID(),
        label = os.getComputerLabel() or ("T" .. os.getComputerID()),
        fuel = turtle.getFuelLevel(),
        pos = { x = state.pos.x, y = state.pos.y, z = state.pos.z },
    }
    protocol.broadcast(MSG.REGISTER, data)
end

local function sendChunkDone()
    local data = {
        id = os.getComputerID(),
        chunk = state.activeChunk,
    }
    protocol.broadcast(MSG.CHUNK_DONE, data)
end

local function sendError(message)
    local data = {
        id = os.getComputerID(),
        message = message,
    }
    protocol.broadcast(MSG.ERROR, data)
end

-- ============================================================
-- CHUNK MINING
-- ============================================================

local function mineLayer(startX, startZ, minY, maxY)
    -- Serpentinen-Muster: 16x16 Flaeche
    -- Graebt den Block vor sich und unter sich (2 Ebenen pro Durchgang)
    local chunkSize = protocol.DEFAULTS.chunkSize

    for row = 0, chunkSize - 1 do
        for col = 1, chunkSize - 1 do
            -- Block unter uns abbauen
            digDown()

            -- Block vor uns abbauen und vorwaerts
            if not moveForward() then
                sendError("Kann nicht vorwaerts bei Row=" .. row .. " Col=" .. col)
                return false
            end

            -- Alle 16 Bloecke: Check Inventar & Fuel
            if col % 16 == 0 then
                if inventoryFull() or fuelCritical() then
                    local prevPos, prevFacing = goHomeAndService()
                    moveTo(prevPos.x, prevPos.y, prevPos.z)
                    face(prevFacing)
                end
            end
        end

        -- Block unter uns am Ende der Reihe
        digDown()

        -- Am Ende der Reihe: zur naechsten Reihe wechseln
        if row < chunkSize - 1 then
            -- Abwechselnd links/rechts drehen fuer Serpentine
            if row % 2 == 0 then
                turnRight()
                if not moveForward() then return false end
                turnRight()
            else
                turnLeft()
                if not moveForward() then return false end
                turnLeft()
            end
        end

        -- State speichern nach jeder Reihe
        if state.miningState then
            state.miningState.row = row
            saveState()
        end

        -- Pause-Check
        while state.paused do
            sleep(1)
        end
    end

    return true
end

local function mineChunk(chunk, minY, maxY)
    state.activeChunk = chunk
    state.status = STATE.TRAVELING
    sendStatus()
    saveState()

    local chunkSize = protocol.DEFAULTS.chunkSize

    -- Chunk-Weltkoordinaten berechnen
    local chunkStartX = chunk.x * chunkSize
    local chunkStartZ = chunk.z * chunkSize

    -- Zum Start des Chunks fliegen (oben)
    local startY = maxY
    if not moveTo(chunkStartX, startY, chunkStartZ) then
        sendError("Kann Chunk nicht erreichen: " .. chunk.x .. "," .. chunk.z)
        return false
    end

    state.status = STATE.MINING
    sendStatus()

    -- Schicht fuer Schicht von oben nach unten
    local y = startY
    local layerCount = 0

    while y > minY do
        -- Mining-State tracken
        state.miningState = {
            layer = layerCount,
            y = y,
            minY = minY,
            maxY = maxY,
        }
        saveState()

        -- Zur Startposition dieser Schicht
        local layerX = chunkStartX
        local layerZ = chunkStartZ

        -- Gerade Schichten starten oben-links, ungerade unten-rechts (Serpentine)
        if layerCount % 2 == 1 then
            layerX = chunkStartX + chunkSize - 1
            layerZ = chunkStartZ + chunkSize - 1
        end

        moveTo(layerX, y, layerZ)

        -- Richtige Richtung fuer Serpentine
        if layerCount % 2 == 0 then
            face(1)  -- Ost (Reihen von links nach rechts starten)
        else
            face(3)  -- West (Reihen von rechts nach links starten)
        end

        -- Schicht abbauen
        if not mineLayer(chunkStartX, chunkStartZ, minY, maxY) then
            sendError("Mining-Fehler in Schicht Y=" .. y)
            return false
        end

        -- 2 Ebenen runter (wir haben diese + die darunter abgebaut)
        y = y - 2
        if y > minY then
            moveDown()
            moveDown()
        end

        layerCount = layerCount + 1

        -- Status-Update nach jeder Schicht
        sendStatus()

        -- Inventar-Check
        if inventoryFull() or fuelCritical() then
            local prevPos, prevFacing = goHomeAndService()
            moveTo(prevPos.x, prevPos.y, prevPos.z)
            face(prevFacing)
        end
    end

    -- Chunk fertig!
    state.miningState = nil
    sendChunkDone()

    -- Zurueck zur Home-Base
    state.status = STATE.RETURNING
    sendStatus()
    moveTo(config.homeX, config.homeY, config.homeZ)
    face(config.homeFacing)

    -- Items abladen
    state.status = STATE.DEPOSITING
    sendStatus()
    unloadInventory()

    -- Refuel fuer naechsten Job
    if turtle.getFuelLevel() < config.minFuel then
        state.status = STATE.REFUELING
        sendStatus()
        refuel()
    end

    -- Fertig
    state.activeChunk = nil
    state.status = STATE.IDLE
    sendStatus()
    saveState()

    return true
end

-- ============================================================
-- NACHRICHTEN-HANDLER (Hintergrund-Thread)
-- ============================================================

local function messageHandler()
    while true do
        local senderId, msg = protocol.receive(2)
        if msg then
            if msg.type == MSG.ACK then
                state.controllerId = senderId
                print("Controller verbunden: " .. senderId)
            elseif msg.type == MSG.ASSIGN then
                if state.status == STATE.IDLE then
                    print("Chunk zugewiesen: " .. msg.chunk.x .. ", " .. msg.chunk.z)
                    local minY = msg.minY or protocol.DEFAULTS.minY
                    local maxY = msg.maxY or protocol.DEFAULTS.maxY
                    os.queueEvent("chunk_assigned", msg.chunk, minY, maxY)
                end
            elseif msg.type == MSG.RECALL then
                print("RECALL empfangen - fahre nach Hause")
                state.paused = false
                os.queueEvent("recall")
            elseif msg.type == MSG.PAUSE then
                print("PAUSE empfangen")
                state.paused = true
                state.status = STATE.PAUSED
                sendStatus()
            elseif msg.type == MSG.RESUME then
                print("RESUME empfangen")
                state.paused = false
                if state.activeChunk then
                    state.status = STATE.MINING
                else
                    state.status = STATE.IDLE
                end
                sendStatus()
            end
        end
    end
end

-- ============================================================
-- HEARTBEAT-THREAD
-- ============================================================

local function heartbeatLoop()
    while true do
        sendStatus()
        sleep(protocol.DEFAULTS.heartbeatInterval)
    end
end

-- ============================================================
-- HAUPT-MINING-LOOP
-- ============================================================

local function miningLoop()
    -- Registrierung beim Controller
    sendRegister()

    -- Auf ACK warten (max 10 Versuche)
    local registered = false
    for i = 1, 10 do
        print("Warte auf Controller... (" .. i .. "/10)")
        sleep(3)
        sendRegister()
        if state.controllerId then
            registered = true
            break
        end
    end

    if not registered then
        print("WARNUNG: Kein Controller gefunden.")
        print("Warte auf Zuweisung...")
    end

    -- Haupt-Loop: Auf Jobs warten
    while true do
        state.status = STATE.IDLE
        sendStatus()
        saveState()

        print("Warte auf Chunk-Zuweisung...")

        -- Auf chunk_assigned oder recall Event warten
        while true do
            local event, p1, p2, p3 = os.pullEvent()
            if event == "chunk_assigned" then
                local chunk = p1
                local minY = p2
                local maxY = p3
                print("Starte Mining: Chunk " .. chunk.x .. ", " .. chunk.z)
                mineChunk(chunk, minY, maxY)
                break
            elseif event == "recall" then
                state.status = STATE.RETURNING
                sendStatus()
                moveTo(config.homeX, config.homeY, config.homeZ)
                face(config.homeFacing)
                unloadInventory()
                state.status = STATE.IDLE
                sendStatus()
                break
            end
        end
    end
end

-- ============================================================
-- RESUME: Fortsetzen nach Neustart
-- ============================================================

local function resumeMining()
    print("Lade gespeicherten State...")
    if state.activeChunk and state.miningState then
        print("Fortsetzen: Chunk " .. state.activeChunk.x .. ", " .. state.activeChunk.z)
        print("Y-Level: " .. (state.miningState.y or "?"))

        -- GPS-Position aktualisieren
        if not gpsLocate() then
            print("FEHLER: GPS nicht verfuegbar fuer Resume!")
            clearState()
            return false
        end
        detectFacing()

        -- Mining fortsetzen
        local minY = state.miningState.minY or protocol.DEFAULTS.minY
        local maxY = state.miningState.maxY or protocol.DEFAULTS.maxY
        mineChunk(state.activeChunk, minY, maxY)
        return true
    end
    return false
end

-- ============================================================
-- MODEM SETUP
-- ============================================================

local function openModem()
    local modemSide = nil
    for _, side in ipairs({"left", "right", "top", "bottom", "front", "back"}) do
        if peripheral.getType(side) == "modem" and peripheral.call(side, "isWireless") then
            modemSide = side
            break
        end
    end

    if not modemSide then
        -- Advanced Mining Turtle hat eingebautes Modem
        local modem = peripheral.find("modem", function(name, m) return m.isWireless() end)
        if modem then
            modemSide = peripheral.getName(modem)
        end
    end

    if modemSide then
        rednet.open(modemSide)
        print("Modem geoeffnet: " .. modemSide)
        return true
    end

    print("FEHLER: Kein Wireless Modem gefunden!")
    return false
end

-- ============================================================
-- HAUPTPROGRAMM
-- ============================================================

local args = { ... }

-- Config-Modus?
if args[1] == "config" then
    runConfigMode()
    return
end

-- Banner
print("================================")
print("  ATM10 Mining Fleet - Turtle")
print("  ID: " .. os.getComputerID())
print("================================")

-- Config laden
if not loadConfig() then
    print("Keine Konfiguration gefunden!")
    print("Bitte zuerst ausfuehren: miner config")
    return
end

-- State laden
local hasState = loadState()

-- Modem oeffnen
if not openModem() then return end

-- GPS initialisieren
if not initGPS() then return end

-- Label setzen falls nicht vorhanden
if not os.getComputerLabel() then
    os.setComputerLabel("Miner-" .. os.getComputerID())
end

print("Home: " .. config.homeX .. ", " .. config.homeY .. ", " .. config.homeZ)
print("Fuel: " .. turtle.getFuelLevel())
print()

-- Parallel: Mining-Loop + Message-Handler + Heartbeat
if hasState and state.activeChunk then
    -- Resume-Modus
    parallel.waitForAny(
        function()
            resumeMining()
            miningLoop()
        end,
        messageHandler,
        heartbeatLoop
    )
else
    -- Normaler Start
    parallel.waitForAny(
        miningLoop,
        messageHandler,
        heartbeatLoop
    )
end

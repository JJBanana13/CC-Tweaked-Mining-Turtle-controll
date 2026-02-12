-- ============================================
-- Chunk Miner - Mining Turtle Programm
-- Baut einen kompletten Chunk (16x16) ab
-- von oben (Y=319) bis unten (Y=-64)
-- ============================================

local config = require("shared.config")
local protocol = require("shared.protocol")

local miner = {}

-- Turtle State
local state = {
    id = os.getComputerID(),
    label = os.getComputerLabel() or ("Turtle_" .. os.getComputerID()),
    status = config.STATE.IDLE,
    serverId = nil,

    -- Aktuelle Position (wird beim Start gesetzt)
    x = 0,
    y = 0,
    z = 0,
    facing = 0, -- 0=Nord(-Z), 1=Ost(+X), 2=Sued(+Z), 3=West(-X)

    -- Aktueller Chunk-Auftrag
    chunk = nil,     -- {cx, cz} Chunk-Koordinaten
    layer = 0,       -- Aktuelle Y-Ebene
    row = 0,         -- Aktuelle Reihe in der Ebene
    blocksMinedTotal = 0,
    chunksCompleted = 0,
}

-- GPS Position holen
local function getGPSPosition()
    local x, y, z = gps.locate(5)
    if x then
        state.x = math.floor(x)
        state.y = math.floor(y)
        state.z = math.floor(z)
        return true
    end
    return false
end

-- Richtung ermitteln (bewege dich 1 Block und vergleiche GPS)
local function detectFacing()
    local ox, oy, oz = state.x, state.y, state.z
    -- Versuche vorwaerts zu gehen
    if turtle.forward() then
        if getGPSPosition() then
            local dx = state.x - ox
            local dz = state.z - oz
            -- Zurueck gehen
            turtle.back()
            state.x = ox
            state.y = oy
            state.z = oz

            if dz == -1 then state.facing = 0      -- Nord
            elseif dx == 1 then state.facing = 1    -- Ost
            elseif dz == 1 then state.facing = 2    -- Sued
            elseif dx == -1 then state.facing = 3   -- West
            end
            return true
        end
        turtle.back()
    end
    return false
end

-- ============================================
-- Bewegungsfunktionen mit Positionstracking
-- ============================================

local function turnLeft()
    turtle.turnLeft()
    state.facing = (state.facing - 1) % 4
end

local function turnRight()
    turtle.turnRight()
    state.facing = (state.facing + 1) % 4
end

local function faceTo(dir)
    while state.facing ~= dir do
        turnRight()
    end
end

local function forward()
    local tries = 0
    while not turtle.forward() do
        if turtle.detect() then
            turtle.dig()
        end
        if turtle.attack() then
            -- Mob im Weg
        end
        tries = tries + 1
        if tries > 30 then return false end
    end
    -- Position updaten
    if state.facing == 0 then state.z = state.z - 1
    elseif state.facing == 1 then state.x = state.x + 1
    elseif state.facing == 2 then state.z = state.z + 1
    elseif state.facing == 3 then state.x = state.x - 1
    end
    return true
end

local function up()
    local tries = 0
    while not turtle.up() do
        if turtle.detectUp() then
            turtle.digUp()
        end
        if turtle.attackUp() then end
        tries = tries + 1
        if tries > 30 then return false end
    end
    state.y = state.y + 1
    return true
end

local function down()
    local tries = 0
    while not turtle.down() do
        if turtle.detectDown() then
            turtle.digDown()
        end
        if turtle.attackDown() then end
        tries = tries + 1
        if tries > 30 then return false end
    end
    state.y = state.y - 1
    return true
end

-- ============================================
-- Navigation
-- ============================================

-- Bewege zu einer bestimmten Y-Hoehe
local function goToY(targetY)
    while state.y < targetY do
        if not up() then return false end
    end
    while state.y > targetY do
        if not down() then return false end
    end
    return true
end

-- Bewege zu XZ Koordinaten (auf aktueller Hoehe)
local function goToXZ(targetX, targetZ)
    -- Erst X
    if targetX > state.x then
        faceTo(1) -- Ost
    elseif targetX < state.x then
        faceTo(3) -- West
    end
    while state.x ~= targetX do
        if not forward() then return false end
    end

    -- Dann Z
    if targetZ > state.z then
        faceTo(2) -- Sued
    elseif targetZ < state.z then
        faceTo(0) -- Nord
    end
    while state.z ~= targetZ do
        if not forward() then return false end
    end
    return true
end

-- Bewege zur Basis (Fuel/Output Chest)
local function goToBase()
    state.status = config.STATE.TRAVELING
    sendStatus()
    -- Erst hoch auf sichere Hoehe
    goToY(config.BASE_Y + 5)
    -- Dann zur Basis
    goToXZ(config.BASE_X, config.BASE_Z)
    goToY(config.BASE_Y)
    return true
end

-- Bewege zum Chunk-Startpunkt
local function goToChunkStart(cx, cz, targetY)
    state.status = config.STATE.TRAVELING
    sendStatus()
    local startX = cx * config.CHUNK_SIZE
    local startZ = cz * config.CHUNK_SIZE
    -- Hoch auf sichere Hoehe
    goToY(config.BASE_Y + 5)
    -- Zum Chunk
    goToXZ(startX, startZ)
    -- Runter auf Ziel-Y
    goToY(targetY)
    return true
end

-- ============================================
-- Inventar Management
-- ============================================

local function isInventoryFull()
    for i = 1, 16 do
        if turtle.getItemCount(i) == 0 then
            return false
        end
    end
    return true
end

local function getInventoryCount()
    local count = 0
    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then
            count = count + 1
        end
    end
    return count
end

-- Items in die Output Chest abladen
local function depositItems()
    local prevStatus = state.status
    state.status = config.STATE.DEPOSITING
    sendStatus()

    -- Zur Output Chest navigieren
    local chestX = config.BASE_X + config.OUTPUT_CHEST.x
    local chestZ = config.BASE_Z + config.OUTPUT_CHEST.z
    local chestY = config.BASE_Y + config.OUTPUT_CHEST.y

    goToXZ(chestX, chestZ)
    goToY(chestY)

    -- Chest sollte unten sein - nach unten droppen
    -- Alternativ: vor der Turtle
    faceTo(0) -- Nord schauen
    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then
            turtle.select(i)
            turtle.drop()
        end
    end
    turtle.select(1)

    return true
end

-- ============================================
-- Fuel Management
-- ============================================

local function getFuelLevel()
    return turtle.getFuelLevel()
end

local function needsFuel()
    return getFuelLevel() < config.FUEL_THRESHOLD
end

local function refuel()
    local prevStatus = state.status
    state.status = config.STATE.REFUELING
    sendStatus()

    -- Zur Fuel Chest navigieren
    local chestX = config.BASE_X + config.FUEL_CHEST.x
    local chestZ = config.BASE_Z + config.FUEL_CHEST.z
    local chestY = config.BASE_Y + config.FUEL_CHEST.y

    goToXZ(chestX, chestZ)
    goToY(chestY)

    -- Fuel aus Chest saugen (Chest ist vor der Turtle)
    faceTo(2) -- Sued schauen (Fuel Chest)
    turtle.select(1)
    turtle.suck(64)
    turtle.refuel()

    -- Genug Fuel?
    if getFuelLevel() < config.FUEL_THRESHOLD then
        -- Nochmal versuchen
        turtle.suck(64)
        turtle.refuel()
    end

    return getFuelLevel() >= config.FUEL_THRESHOLD
end

-- ============================================
-- Status an Server senden
-- ============================================

function sendStatus()
    if not state.serverId then return end
    protocol.send(state.serverId, config.MSG.STATUS, {
        id = state.id,
        label = state.label,
        status = state.status,
        x = state.x,
        y = state.y,
        z = state.z,
        fuel = getFuelLevel(),
        inventory = getInventoryCount(),
        chunk = state.chunk,
        layer = state.layer,
        blocksMinedTotal = state.blocksMinedTotal,
        chunksCompleted = state.chunksCompleted,
    })
end

-- ============================================
-- Chunk Mining Logik
-- ============================================

-- Eine Ebene (16x16) abbauen mit Serpentinen-Muster
local function mineLayer()
    faceTo(0) -- Start: nach Nord schauen

    for row = 0, config.CHUNK_SIZE - 1 do
        state.row = row
        -- Eine Reihe abbauen (15 Bloecke vorwaerts = 16 Positionen)
        for col = 1, config.CHUNK_SIZE - 1 do
            -- Block davor abbauen und vorwaerts
            if turtle.detect() then
                turtle.dig()
                state.blocksMinedTotal = state.blocksMinedTotal + 1
            end
            forward()

            -- Block darunter auch abbauen (2 Ebenen pro Durchgang)
            if turtle.detectDown() then
                turtle.digDown()
                state.blocksMinedTotal = state.blocksMinedTotal + 1
            end

            -- Pruefe Inventar und Fuel alle 16 Bloecke
            if col % 16 == 0 then
                if isInventoryFull() then
                    local retX, retY, retZ = state.x, state.y, state.z
                    local retFacing = state.facing
                    goToBase()
                    depositItems()
                    if needsFuel() then refuel() end
                    goToY(config.BASE_Y + 5)
                    goToXZ(retX, retZ)
                    goToY(retY)
                    faceTo(retFacing)
                    state.status = config.STATE.MINING
                    sendStatus()
                end
            end
        end

        -- Block darunter auch am Ende der Reihe
        if turtle.detectDown() then
            turtle.digDown()
            state.blocksMinedTotal = state.blocksMinedTotal + 1
        end

        -- Am Ende der Reihe: naechste Reihe (wenn nicht letzte)
        if row < config.CHUNK_SIZE - 1 then
            if row % 2 == 0 then
                -- Rechts abbiegen zur naechsten Reihe
                turnRight()
                if turtle.detect() then
                    turtle.dig()
                    state.blocksMinedTotal = state.blocksMinedTotal + 1
                end
                forward()
                if turtle.detectDown() then
                    turtle.digDown()
                    state.blocksMinedTotal = state.blocksMinedTotal + 1
                end
                turnRight()
            else
                -- Links abbiegen zur naechsten Reihe
                turnLeft()
                if turtle.detect() then
                    turtle.dig()
                    state.blocksMinedTotal = state.blocksMinedTotal + 1
                end
                forward()
                if turtle.detectDown() then
                    turtle.digDown()
                    state.blocksMinedTotal = state.blocksMinedTotal + 1
                end
                turnLeft()
            end
        end

        -- Status Update alle paar Reihen
        if row % 4 == 0 then
            sendStatus()
        end
    end
end

-- Kompletten Chunk abbauen
local function mineChunk(cx, cz)
    state.chunk = { cx = cx, cz = cz }
    state.status = config.STATE.MINING

    local startX = cx * config.CHUNK_SIZE
    local startZ = cz * config.CHUNK_SIZE

    print("Starte Chunk (" .. cx .. ", " .. cz .. ")")
    print("Block-Position: (" .. startX .. ", " .. startZ .. ")")

    -- Von oben nach unten abbauen (je 2 Ebenen)
    local currentY = config.MAX_Y

    while currentY >= config.MIN_Y do
        state.layer = currentY

        -- Pruefe Fuel vor jeder Ebene
        if needsFuel() then
            local retX, retZ = state.x, state.z
            goToBase()
            if not refuel() then
                protocol.send(state.serverId, config.MSG.NEED_FUEL, {
                    id = state.id,
                    fuel = getFuelLevel(),
                })
                -- Warte auf Fuel
                print("WARNUNG: Zu wenig Fuel! Warte...")
                while needsFuel() do
                    sleep(10)
                    turtle.suck(64)
                    turtle.refuel()
                end
            end
            depositItems()
            -- Zurueck zum Chunk
            goToChunkStart(cx, cz, currentY)
            goToXZ(startX, startZ)
            state.status = config.STATE.MINING
        end

        -- Zum Startpunkt dieser Ebene
        goToXZ(startX, startZ)
        goToY(currentY)

        -- Ebene abbauen
        print("Mining Ebene Y=" .. currentY)
        sendStatus()
        mineLayer()

        -- 2 Ebenen runter (wir graben auch runter)
        currentY = currentY - 2
    end

    -- Chunk fertig!
    state.chunksCompleted = state.chunksCompleted + 1
    print("Chunk (" .. cx .. ", " .. cz .. ") fertig!")

    -- Items abladen
    goToBase()
    depositItems()
    if needsFuel() then refuel() end

    -- Server benachrichtigen
    protocol.send(state.serverId, config.MSG.CHUNK_DONE, {
        id = state.id,
        chunk = state.chunk,
        blocksMinedTotal = state.blocksMinedTotal,
    })

    state.chunk = nil
    state.status = config.STATE.IDLE
    sendStatus()
end

-- ============================================
-- Server-Nachrichten verarbeiten
-- ============================================

local function handleServerMessage(senderId, msg)
    if msg.type == config.MSG.ASSIGN_CHUNK then
        local cx = msg.data.cx
        local cz = msg.data.cz
        print("Neuer Auftrag: Chunk (" .. cx .. ", " .. cz .. ")")
        mineChunk(cx, cz)
        return true

    elseif msg.type == config.MSG.PAUSE then
        print("PAUSE vom Server")
        state.status = config.STATE.PAUSED
        sendStatus()
        return false

    elseif msg.type == config.MSG.RESUME then
        print("RESUME vom Server")
        state.status = config.STATE.IDLE
        sendStatus()
        return true

    elseif msg.type == config.MSG.STOP then
        print("STOP vom Server - fahre zur Basis")
        goToBase()
        depositItems()
        state.status = config.STATE.IDLE
        sendStatus()
        return false

    elseif msg.type == config.MSG.COME_HOME then
        print("Kehre zur Basis zurueck")
        goToBase()
        depositItems()
        if needsFuel() then refuel() end
        state.status = config.STATE.IDLE
        sendStatus()
        return false
    end
    return false
end

-- ============================================
-- Heartbeat senden
-- ============================================

local function heartbeatLoop()
    while true do
        sleep(10)
        if state.serverId then
            sendStatus()
        end
    end
end

-- ============================================
-- Nachrichten-Empfang Loop
-- ============================================

local function messageLoop()
    while true do
        local senderId, msg = protocol.receive(1)
        if senderId and msg then
            handleServerMessage(senderId, msg)
        end
    end
end

-- ============================================
-- Hauptprogramm
-- ============================================

function miner.run()
    print("=== Chunk Miner v1.0 ===")
    print("Turtle ID: " .. state.id)

    -- Modem initialisieren
    protocol.init()
    print("Modem initialisiert")

    -- GPS Position holen
    print("Suche GPS Signal...")
    if getGPSPosition() then
        print("Position: " .. state.x .. ", " .. state.y .. ", " .. state.z)
        detectFacing()
        print("Richtung: " .. state.facing)
    else
        print("WARNUNG: Kein GPS! Verwende Basis als Position.")
        state.x = config.BASE_X
        state.y = config.BASE_Y
        state.z = config.BASE_Z
    end

    -- Beim Server registrieren
    print("Suche Server...")
    local registered = false
    while not registered do
        protocol.broadcast(config.MSG.REGISTER, {
            id = state.id,
            label = state.label,
            x = state.x,
            y = state.y,
            z = state.z,
            fuel = getFuelLevel(),
        })

        -- Auf Antwort warten
        local senderId, msg = protocol.receive(5)
        if senderId and msg then
            if msg.type == config.MSG.ASSIGN_CHUNK or msg.type == config.MSG.PAUSE then
                state.serverId = senderId
                registered = true
                print("Server gefunden! ID: " .. senderId)

                if msg.type == config.MSG.ASSIGN_CHUNK then
                    handleServerMessage(senderId, msg)
                end
            end
        else
            print("Kein Server gefunden, versuche erneut...")
            sleep(3)
        end
    end

    -- Haupt-Loop: Auf Auftraege warten
    parallel.waitForAny(
        function()
            while true do
                if state.status == config.STATE.IDLE then
                    -- Server fragen ob es Arbeit gibt
                    protocol.send(state.serverId, config.MSG.STATUS, {
                        id = state.id,
                        label = state.label,
                        status = state.status,
                        fuel = getFuelLevel(),
                    })
                end

                local senderId, msg = protocol.receive(5)
                if senderId and msg then
                    state.serverId = senderId
                    handleServerMessage(senderId, msg)
                end
            end
        end,
        heartbeatLoop
    )
end

return miner

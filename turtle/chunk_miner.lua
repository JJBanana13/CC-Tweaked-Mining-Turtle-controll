-- ============================================
-- Chunk Miner - Mining Turtle Programm
-- Baut einen kompletten Chunk (16x16) ab
-- von oben (Y=319) bis unten (Y=-64)
--
-- Config wird vom Server per Rednet empfangen!
-- ============================================

local protocol = require("shared.protocol")

local miner = {}

-- Nachrichten-Typen (Protokoll-Konstanten)
local MSG = {
    REGISTER = "register",
    STATUS = "status",
    CHUNK_DONE = "chunk_done",
    NEED_FUEL = "need_fuel",
    INVENTORY_FULL = "inv_full",
    ERROR = "error",
    HEARTBEAT = "heartbeat",
    ASSIGN_CHUNK = "assign_chunk",
    GO_REFUEL = "go_refuel",
    GO_DEPOSIT = "go_deposit",
    PAUSE = "pause",
    RESUME = "resume",
    STOP = "stop",
    COME_HOME = "come_home",
}

-- Status-Typen
local STATE = {
    IDLE = "idle",
    MINING = "mining",
    TRAVELING = "traveling",
    REFUELING = "refueling",
    DEPOSITING = "depositing",
    PAUSED = "paused",
    ERROR = "error",
    DONE = "done",
}

-- Config vom Server (wird bei Registration empfangen)
local cfg = nil

-- Turtle State
local state = {
    id = os.getComputerID(),
    label = os.getComputerLabel() or ("Turtle_" .. os.getComputerID()),
    status = STATE.IDLE,
    serverId = nil,

    -- Home-Position (wo die Turtle aufgebaut wurde)
    home = nil, -- {x, y, z}

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
    state.status = STATE.TRAVELING
    sendStatus()
    -- Erst hoch auf sichere Hoehe
    goToY(cfg.BASE_Y + 5)
    -- Dann zur Basis
    goToXZ(cfg.BASE_X, cfg.BASE_Z)
    goToY(cfg.BASE_Y)
    return true
end

-- Bewege zur Home-Position
local function goToHome()
    state.status = STATE.TRAVELING
    sendStatus()
    goToY(state.home.y + 5)
    goToXZ(state.home.x, state.home.z)
    goToY(state.home.y)
    return true
end

-- Bewege zum Chunk-Startpunkt
local function goToChunkStart(cx, cz, targetY)
    state.status = STATE.TRAVELING
    sendStatus()
    local startX = cx * cfg.CHUNK_SIZE
    local startZ = cz * cfg.CHUNK_SIZE
    -- Hoch auf sichere Hoehe
    goToY(cfg.BASE_Y + 5)
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
    state.status = STATE.DEPOSITING
    sendStatus()

    -- Zur Output Chest navigieren
    local chestX = cfg.BASE_X + cfg.OUTPUT_CHEST.x
    local chestZ = cfg.BASE_Z + cfg.OUTPUT_CHEST.z
    local chestY = cfg.BASE_Y + cfg.OUTPUT_CHEST.y

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
    return getFuelLevel() < cfg.FUEL_THRESHOLD
end

local function refuel()
    local prevStatus = state.status
    state.status = STATE.REFUELING
    sendStatus()

    -- Zur Fuel Chest navigieren
    local chestX = cfg.BASE_X + cfg.FUEL_CHEST.x
    local chestZ = cfg.BASE_Z + cfg.FUEL_CHEST.z
    local chestY = cfg.BASE_Y + cfg.FUEL_CHEST.y

    goToXZ(chestX, chestZ)
    goToY(chestY)

    -- Fuel aus Chest saugen (Chest ist vor der Turtle)
    faceTo(2) -- Sued schauen (Fuel Chest)
    turtle.select(1)
    turtle.suck(64)
    turtle.refuel()

    -- Genug Fuel?
    if getFuelLevel() < cfg.FUEL_THRESHOLD then
        -- Nochmal versuchen
        turtle.suck(64)
        turtle.refuel()
    end

    return getFuelLevel() >= cfg.FUEL_THRESHOLD
end

-- ============================================
-- Status an Server senden
-- ============================================

function sendStatus()
    if not state.serverId then return end
    protocol.send(state.serverId, MSG.STATUS, {
        id = state.id,
        label = state.label,
        status = state.status,
        x = state.x,
        y = state.y,
        z = state.z,
        home = state.home,
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

    for row = 0, cfg.CHUNK_SIZE - 1 do
        state.row = row
        -- Eine Reihe abbauen (15 Bloecke vorwaerts = 16 Positionen)
        for col = 1, cfg.CHUNK_SIZE - 1 do
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
                    goToY(cfg.BASE_Y + 5)
                    goToXZ(retX, retZ)
                    goToY(retY)
                    faceTo(retFacing)
                    state.status = STATE.MINING
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
        if row < cfg.CHUNK_SIZE - 1 then
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
    state.status = STATE.MINING

    local startX = cx * cfg.CHUNK_SIZE
    local startZ = cz * cfg.CHUNK_SIZE

    print("Starte Chunk (" .. cx .. ", " .. cz .. ")")
    print("Block-Position: (" .. startX .. ", " .. startZ .. ")")

    -- Von oben nach unten abbauen (je 2 Ebenen)
    local currentY = cfg.MAX_Y

    while currentY >= cfg.MIN_Y do
        state.layer = currentY

        -- Pruefe Fuel vor jeder Ebene
        if needsFuel() then
            local retX, retZ = state.x, state.z
            goToBase()
            if not refuel() then
                protocol.send(state.serverId, MSG.NEED_FUEL, {
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
            state.status = STATE.MINING
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
    protocol.send(state.serverId, MSG.CHUNK_DONE, {
        id = state.id,
        chunk = state.chunk,
        blocksMinedTotal = state.blocksMinedTotal,
    })

    state.chunk = nil
    state.status = STATE.IDLE
    sendStatus()
end

-- ============================================
-- Config vom Server speichern
-- ============================================

local function applyConfig(serverConfig)
    if not serverConfig then return false end
    cfg = serverConfig
    print("Config vom Server empfangen:")
    print("  Basis: (" .. cfg.BASE_X .. ", " .. cfg.BASE_Y .. ", " .. cfg.BASE_Z .. ")")
    print("  Mining Y: " .. cfg.MAX_Y .. " bis " .. cfg.MIN_Y)
    print("  Chunk Size: " .. cfg.CHUNK_SIZE)
    return true
end

-- ============================================
-- Server-Nachrichten verarbeiten
-- ============================================

local function handleServerMessage(senderId, msg)
    -- Config aus der Nachricht extrahieren (kommt bei Registration)
    if msg.data and msg.data.config then
        applyConfig(msg.data.config)
    end

    if msg.type == MSG.ASSIGN_CHUNK then
        local cx = msg.data.cx
        local cz = msg.data.cz
        print("Neuer Auftrag: Chunk (" .. cx .. ", " .. cz .. ")")
        mineChunk(cx, cz)
        return true

    elseif msg.type == MSG.PAUSE then
        print("PAUSE vom Server - kehre nach Home zurueck")
        state.status = STATE.PAUSED
        sendStatus()
        if state.home then
            goToHome()
            state.status = STATE.PAUSED
            sendStatus()
        end
        return false

    elseif msg.type == MSG.RESUME then
        print("RESUME vom Server")
        state.status = STATE.IDLE
        sendStatus()
        return true

    elseif msg.type == MSG.STOP then
        print("STOP vom Server - kehre nach Home zurueck")
        if state.home then
            goToHome()
        else
            goToBase()
            depositItems()
        end
        state.status = STATE.IDLE
        sendStatus()
        return false

    elseif msg.type == MSG.COME_HOME then
        print("Kehre nach Home zurueck")
        if state.home then
            goToHome()
        else
            goToBase()
        end
        state.status = STATE.IDLE
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
-- Hauptprogramm
-- ============================================

function miner.run()
    print("=== Chunk Miner v2.0 ===")
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
        print("WARNUNG: Kein GPS Signal!")
        print("Bitte GPS aufsetzen oder Turtle an GPS-Position platzieren.")
    end

    -- Home-Position setzen (wo die Turtle aufgebaut wurde)
    state.home = { x = state.x, y = state.y, z = state.z }
    print("Home-Position: (" .. state.home.x .. ", " .. state.home.y .. ", " .. state.home.z .. ")")

    -- Beim Server registrieren (und Config empfangen)
    print("Suche Server...")
    local registered = false
    while not registered do
        protocol.broadcast(MSG.REGISTER, {
            id = state.id,
            label = state.label,
            x = state.x,
            y = state.y,
            z = state.z,
            home = state.home,
            fuel = getFuelLevel(),
        })

        -- Auf Antwort warten
        local senderId, msg = protocol.receive(5)
        if senderId and msg then
            if msg.type == MSG.ASSIGN_CHUNK or msg.type == MSG.PAUSE then
                state.serverId = senderId
                registered = true
                print("Server gefunden! ID: " .. senderId)

                -- Config aus der Antwort extrahieren
                if msg.data and msg.data.config then
                    applyConfig(msg.data.config)
                end

                if not cfg then
                    print("FEHLER: Keine Config vom Server erhalten!")
                    print("Versuche erneut...")
                    registered = false
                elseif msg.type == MSG.ASSIGN_CHUNK then
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
                if state.status == STATE.IDLE then
                    -- Server fragen ob es Arbeit gibt
                    protocol.send(state.serverId, MSG.STATUS, {
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

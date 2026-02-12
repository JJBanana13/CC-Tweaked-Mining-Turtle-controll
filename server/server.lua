-- ============================================
-- Mining Server - Steuert alle 16 Turtles
-- Weist Chunks zu, ueberwacht Status
-- Touch-Monitor-UI fuer Steuerung
-- ============================================

local config = require("shared.config")
local protocol = require("shared.protocol")
local monitorUI = require("server.monitor_ui")

local server = {}

-- ============================================
-- Server State (shared mit Monitor-UI)
-- ============================================

local turtles = {}           -- Registrierte Turtles {[id] = turtleData}
local chunkQueue = {}        -- Warteschlange der zu minenden Chunks
local completedChunks = {}   -- Bereits abgeschlossene Chunks
local activeChunks = {}      -- Gerade in Bearbeitung {[turtleId] = {cx, cz}}
local running = true

-- Statistiken
local stats = {
    totalBlocksMined = 0,
    totalChunksCompleted = 0,
    startTime = os.clock(),
}

-- Shared State fuer Monitor-UI (Tabelle damit paused per Referenz geteilt wird)
local serverState = {
    turtles = turtles,
    chunkQueue = chunkQueue,
    stats = stats,
    paused = true,  -- DEFAULT: Pausiert! Muss manuell gestartet werden.
}

-- ============================================
-- Config-Payload fuer Turtles
-- ============================================

local function buildTurtleConfig()
    return {
        BASE_X = config.BASE_X,
        BASE_Y = config.BASE_Y,
        BASE_Z = config.BASE_Z,
        FUEL_CHEST = config.FUEL_CHEST,
        OUTPUT_CHEST = config.OUTPUT_CHEST,
        CHUNK_SIZE = config.CHUNK_SIZE,
        MAX_Y = config.MAX_Y,
        MIN_Y = config.MIN_Y,
        FUEL_THRESHOLD = config.FUEL_THRESHOLD,
    }
end

-- ============================================
-- Chunk-Verwaltung
-- ============================================

local function generateChunkSpiral(centerX, centerZ, count)
    local chunks = {}
    local x, z = centerX, centerZ
    local dx, dz = 1, 0
    local segmentLength = 1
    local segmentPassed = 0
    local segmentsDone = 0

    for i = 1, count do
        table.insert(chunks, { cx = x, cz = z })
        x = x + dx
        z = z + dz
        segmentPassed = segmentPassed + 1

        if segmentPassed == segmentLength then
            segmentPassed = 0
            local temp = dx
            dx = -dz
            dz = temp
            segmentsDone = segmentsDone + 1
            if segmentsDone == 2 then
                segmentsDone = 0
                segmentLength = segmentLength + 1
            end
        end
    end
    return chunks
end

local function initChunkQueue(numChunks)
    -- Block-Koordinaten aus Config automatisch in Chunk-Koordinaten umrechnen
    local startCX = math.floor(config.START_X / config.CHUNK_SIZE)
    local startCZ = math.floor(config.START_Z / config.CHUNK_SIZE)
    chunkQueue = generateChunkSpiral(
        startCX,
        startCZ,
        numChunks
    )
    local filtered = {}
    for _, chunk in ipairs(chunkQueue) do
        local key = chunk.cx .. "," .. chunk.cz
        if not completedChunks[key] then
            table.insert(filtered, chunk)
        end
    end
    chunkQueue = filtered
    -- Shared State aktualisieren (Referenz)
    serverState.chunkQueue = chunkQueue
    print("Chunk-Queue: " .. #chunkQueue .. " Chunks")
end

local function getNextChunk()
    if #chunkQueue == 0 then
        return nil
    end
    return table.remove(chunkQueue, 1)
end

local function markChunkDone(cx, cz)
    local key = cx .. "," .. cz
    completedChunks[key] = true
    stats.totalChunksCompleted = stats.totalChunksCompleted + 1
end

-- ============================================
-- Turtle Verwaltung
-- ============================================

local function registerTurtle(senderId, data)
    turtles[senderId] = {
        id = data.id or senderId,
        label = data.label or ("Turtle_" .. senderId),
        status = config.STATE.IDLE,
        x = data.x or 0,
        y = data.y or 0,
        z = data.z or 0,
        home = data.home,
        fuel = data.fuel or 0,
        inventory = 0,
        chunk = nil,
        layer = 0,
        blocksMinedTotal = 0,
        chunksCompleted = 0,
        lastSeen = os.clock(),
    }
    print("Turtle registriert: " .. (data.label or senderId))
    if data.home then
        print("  Home: (" .. data.home.x .. ", " .. data.home.y .. ", " .. data.home.z .. ")")
    end

    -- Chunk zuweisen wenn nicht pausiert, sonst PAUSE senden
    if not serverState.paused then
        assignChunkToTurtle(senderId)
    else
        protocol.send(senderId, config.MSG.PAUSE, {
            config = buildTurtleConfig(),
        })
    end
end

function assignChunkToTurtle(turtleId)
    local chunk = getNextChunk()
    if chunk then
        activeChunks[turtleId] = chunk
        turtles[turtleId].chunk = chunk
        turtles[turtleId].status = config.STATE.MINING
        protocol.send(turtleId, config.MSG.ASSIGN_CHUNK, {
            cx = chunk.cx,
            cz = chunk.cz,
            config = buildTurtleConfig(),
        })
        print("Chunk (" .. chunk.cx .. ", " .. chunk.cz .. ") -> Turtle " .. turtleId)
    else
        print("Keine Chunks mehr in der Queue!")
        turtles[turtleId].status = config.STATE.IDLE
    end
end

local function updateTurtleStatus(senderId, data)
    if not turtles[senderId] then
        registerTurtle(senderId, data)
        return
    end

    local t = turtles[senderId]
    t.status = data.status or t.status
    t.x = data.x or t.x
    t.y = data.y or t.y
    t.z = data.z or t.z
    t.home = data.home or t.home
    t.fuel = data.fuel or t.fuel
    t.inventory = data.inventory or t.inventory
    t.chunk = data.chunk or t.chunk
    t.layer = data.layer or t.layer
    t.blocksMinedTotal = data.blocksMinedTotal or t.blocksMinedTotal
    t.chunksCompleted = data.chunksCompleted or t.chunksCompleted
    t.lastSeen = os.clock()

    if data.status == config.STATE.IDLE and not serverState.paused then
        assignChunkToTurtle(senderId)
    end
end

local function handleChunkDone(senderId, data)
    if activeChunks[senderId] then
        local chunk = activeChunks[senderId]
        markChunkDone(chunk.cx, chunk.cz)
        activeChunks[senderId] = nil
        print("Chunk fertig: (" .. chunk.cx .. ", " .. chunk.cz .. ") von Turtle " .. senderId)
    end
    stats.totalBlocksMined = stats.totalBlocksMined + (data.blocksMinedTotal or 0)

    if not serverState.paused then
        assignChunkToTurtle(senderId)
    end
end

-- ============================================
-- Nachrichten verarbeiten
-- ============================================

local function handleMessage(senderId, msg)
    if msg.type == config.MSG.REGISTER then
        registerTurtle(senderId, msg.data)

    elseif msg.type == config.MSG.STATUS then
        updateTurtleStatus(senderId, msg.data)

    elseif msg.type == config.MSG.CHUNK_DONE then
        handleChunkDone(senderId, msg.data)

    elseif msg.type == config.MSG.NEED_FUEL then
        print("WARNUNG: Turtle " .. senderId .. " braucht Fuel!")
        if turtles[senderId] then
            turtles[senderId].status = config.STATE.REFUELING
        end

    elseif msg.type == config.MSG.INVENTORY_FULL then
        print("Turtle " .. senderId .. " Inventar voll")
        protocol.send(senderId, config.MSG.GO_DEPOSIT, {})

    elseif msg.type == config.MSG.ERROR then
        print("FEHLER von Turtle " .. senderId .. ": " .. tostring(msg.data.error))
        if turtles[senderId] then
            turtles[senderId].status = config.STATE.ERROR
        end

    elseif msg.type == config.MSG.HEARTBEAT then
        if turtles[senderId] then
            turtles[senderId].lastSeen = os.clock()
        end
    end
end

-- ============================================
-- Monitor Touch-Actions ausfuehren
-- ============================================

local function executeAction(action)
    if action == "start" or action == "start_all" or action == "resume_all" then
        serverState.paused = false
        protocol.broadcast(config.MSG.RESUME, {})
        print("[Monitor] START - Alle Turtles fortgesetzt")
        for id, t in pairs(turtles) do
            if t.status == config.STATE.IDLE or t.status == config.STATE.PAUSED then
                assignChunkToTurtle(id)
            end
        end

    elseif action == "stop" or action == "pause_all" then
        serverState.paused = true
        protocol.broadcast(config.MSG.PAUSE, {})
        print("[Monitor] PAUSE - Alle Turtles pausiert")

    elseif action == "home_all" then
        protocol.broadcast(config.MSG.COME_HOME, {})
        print("[Monitor] HOME - Alle Turtles nach Home")
    end
end

-- ============================================
-- Server Befehle (Terminal Input)
-- ============================================

local function processCommand(input)
    local parts = {}
    for word in input:gmatch("%S+") do
        table.insert(parts, word)
    end
    local cmd = parts[1]

    if cmd == "help" then
        print("=== Befehle ===")
        print("status    - Zeige alle Turtles")
        print("stats     - Statistiken anzeigen")
        print("start     - Alle Turtles starten")
        print("pause     - Alle Turtles pausieren")
        print("resume    - Alle Turtles fortsetzen")
        print("stop      - Alle Turtles stoppen")
        print("home      - Alle Turtles nach Home")
        print("add <n>   - N neue Chunks zur Queue")
        print("queue     - Chunk-Queue anzeigen")
        print("quit      - Server beenden")

    elseif cmd == "status" then
        print("=== Turtle Status ===")
        local count = 0
        for id, t in pairs(turtles) do
            count = count + 1
            local chunkStr = "---"
            if t.chunk then
                chunkStr = "(" .. t.chunk.cx .. "," .. t.chunk.cz .. ")"
            end
            local homeStr = "---"
            if t.home then
                homeStr = "(" .. t.home.x .. "," .. t.home.y .. "," .. t.home.z .. ")"
            end
            print(string.format(
                "#%d %-12s %-10s Fuel:%-5d Chunk:%s Y:%d",
                id, t.label, t.status, t.fuel,
                chunkStr, t.layer or 0
            ))
            print(string.format(
                "   Pos:(%d,%d,%d) Home:%s",
                t.x, t.y, t.z, homeStr
            ))
        end
        if count == 0 then
            print("Keine Turtles registriert.")
        end
        print(count .. "/" .. config.MAX_TURTLES .. " Turtles aktiv")

    elseif cmd == "stats" then
        local elapsed = os.clock() - stats.startTime
        print("=== Statistiken ===")
        print("Laufzeit: " .. math.floor(elapsed) .. "s")
        print("Chunks fertig: " .. stats.totalChunksCompleted)
        print("Chunks in Queue: " .. #chunkQueue)
        print("Bloecke abgebaut: " .. stats.totalBlocksMined)

    elseif cmd == "start" or cmd == "resume" then
        executeAction("start")

    elseif cmd == "pause" then
        executeAction("pause_all")

    elseif cmd == "stop" then
        protocol.broadcast(config.MSG.STOP, {})
        print("Alle Turtles gestoppt! (kehren zu Home zurueck)")

    elseif cmd == "home" then
        executeAction("home_all")

    elseif cmd == "add" then
        local n = tonumber(parts[2]) or 64
        local before = #chunkQueue
        initChunkQueue(before + n)
        print((#chunkQueue - before) .. " neue Chunks hinzugefuegt")

    elseif cmd == "queue" then
        print("=== Chunk Queue (" .. #chunkQueue .. " Chunks) ===")
        for i = 1, math.min(10, #chunkQueue) do
            local c = chunkQueue[i]
            print("  " .. i .. ". (" .. c.cx .. ", " .. c.cz .. ")")
        end
        if #chunkQueue > 10 then
            print("  ... und " .. (#chunkQueue - 10) .. " weitere")
        end

    elseif cmd == "quit" then
        print("Server wird beendet...")
        protocol.broadcast(config.MSG.COME_HOME, {})
        running = false

    else
        print("Unbekannter Befehl. 'help' fuer Hilfe.")
    end
end

-- ============================================
-- Speichern / Laden
-- ============================================

local SAVE_FILE = "server_state.json"

local function saveState()
    local data = {
        completedChunks = completedChunks,
        chunkQueue = chunkQueue,
        activeChunks = activeChunks,
        stats = stats,
        paused = serverState.paused,
    }
    local f = fs.open(SAVE_FILE, "w")
    if f then
        f.write(textutils.serialiseJSON(data))
        f.close()
    end
end

local function loadState()
    if fs.exists(SAVE_FILE) then
        local f = fs.open(SAVE_FILE, "r")
        if f then
            local content = f.readAll()
            f.close()
            local data = textutils.unserialiseJSON(content)
            if data then
                completedChunks = data.completedChunks or {}
                chunkQueue = data.chunkQueue or {}
                serverState.chunkQueue = chunkQueue
                activeChunks = data.activeChunks or {}
                stats = data.stats or stats
                serverState.stats = stats
                -- Pause-Status laden (default: true wenn nicht vorhanden)
                if data.paused ~= nil then
                    serverState.paused = data.paused
                else
                    serverState.paused = true
                end
                print("Gespeicherter Zustand geladen!")
                print("  Fertige Chunks: " .. stats.totalChunksCompleted)
                print("  Queue: " .. #chunkQueue .. " Chunks")
                print("  Pausiert: " .. tostring(serverState.paused))
                return true
            end
        end
    end
    return false
end

-- ============================================
-- Monitor initialisieren
-- ============================================

local function initMonitor()
    local mon = peripheral.find("monitor")
    if mon then
        monitorUI.init(mon, serverState, config)
        print("Monitor gefunden! Touch-UI aktiv.")
        return true
    end
    print("Kein Monitor gefunden. Nur Terminal-Steuerung.")
    return false
end

-- ============================================
-- Hauptprogramm
-- ============================================

function server.run()
    print("=================================")
    print("  Mining Control Server v3.0")
    print("  Server ID: " .. os.getComputerID())
    print("=================================")

    -- Modem init
    protocol.init()
    print("Modem initialisiert")

    -- Monitor init
    local hasMonitor = initMonitor()

    -- Gespeicherten Zustand laden
    if not loadState() then
        initChunkQueue(256)
    end

    print("")
    print("Config: Basis=(" .. config.BASE_X .. "," .. config.BASE_Y .. "," .. config.BASE_Z .. ")")
    print("Status: " .. (serverState.paused and "PAUSIERT" or "AKTIV"))
    print("Druecke START auf dem Monitor oder tippe 'start' zum Starten.")
    print("")
    print("'help' fuer alle Befehle.")
    print("")

    -- Parallel: Nachrichten + Terminal + Monitor Draw + Monitor Touch + Auto-Save + Dead-Turtle
    parallel.waitForAny(
        -- Nachrichten empfangen
        function()
            while running do
                local senderId, msg = protocol.receive(1)
                if senderId and msg then
                    handleMessage(senderId, msg)
                end
            end
        end,

        -- Terminal Input
        function()
            while running do
                local input = read()
                if input and input ~= "" then
                    processCommand(input:lower())
                end
            end
        end,

        -- Monitor zeichnen
        function()
            while running do
                monitorUI.draw()
                sleep(2)
            end
        end,

        -- Monitor Touch Events
        function()
            if not hasMonitor then
                while running do sleep(60) end
                return
            end
            while running do
                local event, side, x, y = os.pullEvent("monitor_touch")
                local action = monitorUI.handleTouch(x, y)
                if action then
                    executeAction(action)
                    monitorUI.draw()
                end
            end
        end,

        -- Auto-Save alle 60 Sekunden
        function()
            while running do
                sleep(60)
                saveState()
            end
        end,

        -- Dead-Turtle Detection
        function()
            while running do
                sleep(30)
                local now = os.clock()
                for id, t in pairs(turtles) do
                    if now - t.lastSeen > 120 then
                        print("WARNUNG: Turtle " .. id .. " nicht erreichbar seit " ..
                            math.floor(now - t.lastSeen) .. "s")
                        if activeChunks[id] then
                            table.insert(chunkQueue, 1, activeChunks[id])
                            activeChunks[id] = nil
                            t.chunk = nil
                            t.status = config.STATE.ERROR
                        end
                    end
                end
            end
        end
    )

    -- Beim Beenden speichern
    saveState()
    print("Server beendet. Zustand gespeichert.")
end

return server

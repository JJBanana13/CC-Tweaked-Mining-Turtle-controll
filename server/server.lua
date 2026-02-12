-- ============================================
-- Mining Server - Steuert alle 16 Turtles
-- Weist Chunks zu, ueberwacht Status
-- ============================================

local config = require("shared.config")
local protocol = require("shared.protocol")

local server = {}

-- ============================================
-- Server State
-- ============================================

local turtles = {}           -- Registrierte Turtles {[id] = turtleData}
local chunkQueue = {}        -- Warteschlange der zu minenden Chunks
local completedChunks = {}   -- Bereits abgeschlossene Chunks
local activeChunks = {}      -- Gerade in Bearbeitung {[turtleId] = {cx, cz}}
local running = true
local paused = false

-- Statistiken
local stats = {
    totalBlocksMined = 0,
    totalChunksCompleted = 0,
    startTime = os.clock(),
}

-- ============================================
-- Config-Payload fuer Turtles
-- ============================================

-- Baut die Config die an Turtles gesendet wird
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

-- Chunks in einer Spirale um den Startpunkt generieren
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
            -- Richtung drehen
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

-- Chunk-Queue initialisieren
local function initChunkQueue(numChunks)
    chunkQueue = generateChunkSpiral(
        config.START_CHUNK_X,
        config.START_CHUNK_Z,
        numChunks
    )
    -- Bereits abgeschlossene Chunks entfernen
    local filtered = {}
    for _, chunk in ipairs(chunkQueue) do
        local key = chunk.cx .. "," .. chunk.cz
        if not completedChunks[key] then
            table.insert(filtered, chunk)
        end
    end
    chunkQueue = filtered
    print("Chunk-Queue: " .. #chunkQueue .. " Chunks")
end

-- Naechsten Chunk aus der Queue holen
local function getNextChunk()
    if #chunkQueue == 0 then
        return nil
    end
    return table.remove(chunkQueue, 1)
end

-- Chunk als erledigt markieren
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

    -- Sofort einen Chunk zuweisen wenn nicht pausiert
    if not paused then
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
        -- Unbekannte Turtle - registrieren
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

    -- Wenn idle und nicht pausiert, neuen Chunk zuweisen
    if data.status == config.STATE.IDLE and not paused then
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

    -- Neuen Chunk zuweisen
    if not paused then
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

    elseif cmd == "pause" then
        paused = true
        protocol.broadcast(config.MSG.PAUSE, {})
        print("Alle Turtles pausiert! (kehren zu Home zurueck)")

    elseif cmd == "resume" then
        paused = false
        protocol.broadcast(config.MSG.RESUME, {})
        print("Alle Turtles fortgesetzt!")
        -- Idle Turtles neue Chunks zuweisen
        for id, t in pairs(turtles) do
            if t.status == config.STATE.IDLE or t.status == config.STATE.PAUSED then
                assignChunkToTurtle(id)
            end
        end

    elseif cmd == "stop" then
        protocol.broadcast(config.MSG.STOP, {})
        print("Alle Turtles gestoppt! (kehren zu Home zurueck)")

    elseif cmd == "home" then
        protocol.broadcast(config.MSG.COME_HOME, {})
        print("Alle Turtles kehren nach Home zurueck!")

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
        paused = paused,
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
                activeChunks = data.activeChunks or {}
                stats = data.stats or stats
                paused = data.paused or false
                print("Gespeicherter Zustand geladen!")
                print("  Fertige Chunks: " .. stats.totalChunksCompleted)
                print("  Queue: " .. #chunkQueue .. " Chunks")
                return true
            end
        end
    end
    return false
end

-- ============================================
-- Monitor UI (separater Thread)
-- ============================================

local monitor = nil

local function findMonitor()
    monitor = peripheral.find("monitor")
    if monitor then
        monitor.setTextScale(0.5)
        monitor.clear()
        print("Monitor gefunden!")
        return true
    end
    return false
end

local function drawMonitor()
    if not monitor then return end

    monitor.clear()
    local w, h = monitor.getSize()

    -- Titel
    monitor.setCursorPos(1, 1)
    monitor.setTextColor(colors.yellow)
    monitor.write("=== Mining Control Server ===")

    -- Statistiken
    monitor.setCursorPos(1, 3)
    monitor.setTextColor(colors.white)
    local elapsed = os.clock() - stats.startTime
    monitor.write("Laufzeit: " .. math.floor(elapsed) .. "s")

    monitor.setCursorPos(1, 4)
    monitor.setTextColor(colors.lime)
    monitor.write("Chunks fertig: " .. stats.totalChunksCompleted)

    monitor.setCursorPos(1, 5)
    monitor.setTextColor(colors.cyan)
    monitor.write("Queue: " .. #chunkQueue .. " Chunks")

    monitor.setCursorPos(1, 6)
    monitor.setTextColor(paused and colors.red or colors.lime)
    monitor.write("Status: " .. (paused and "PAUSIERT" or "AKTIV"))

    -- Turtle-Liste
    monitor.setCursorPos(1, 8)
    monitor.setTextColor(colors.yellow)
    monitor.write("--- Turtles ---")

    local line = 9
    for id, t in pairs(turtles) do
        if line >= h then break end

        -- Status-Farbe
        if t.status == config.STATE.MINING then
            monitor.setTextColor(colors.lime)
        elseif t.status == config.STATE.TRAVELING then
            monitor.setTextColor(colors.cyan)
        elseif t.status == config.STATE.REFUELING then
            monitor.setTextColor(colors.orange)
        elseif t.status == config.STATE.DEPOSITING then
            monitor.setTextColor(colors.magenta)
        elseif t.status == config.STATE.PAUSED then
            monitor.setTextColor(colors.yellow)
        elseif t.status == config.STATE.ERROR then
            monitor.setTextColor(colors.red)
        else
            monitor.setTextColor(colors.white)
        end

        local chunkStr = "---"
        if t.chunk then
            chunkStr = t.chunk.cx .. "," .. t.chunk.cz
        end

        monitor.setCursorPos(1, line)
        monitor.write(string.format("%-10s", t.label:sub(1, 10)))

        monitor.setCursorPos(12, line)
        monitor.write(string.format("%-9s", t.status:sub(1, 9)))

        monitor.setCursorPos(22, line)
        monitor.setTextColor(t.fuel < config.FUEL_THRESHOLD and colors.red or colors.white)
        monitor.write("F:" .. t.fuel)

        monitor.setCursorPos(32, line)
        monitor.setTextColor(colors.white)
        monitor.write("C:" .. chunkStr)

        monitor.setCursorPos(42, line)
        monitor.write("Y:" .. (t.layer or "?"))

        line = line + 1
    end

    -- Keine Turtles
    if line == 9 then
        monitor.setCursorPos(1, line)
        monitor.setTextColor(colors.gray)
        monitor.write("Warte auf Turtles...")
    end
end

-- ============================================
-- Hauptprogramm
-- ============================================

function server.run()
    print("=================================")
    print("  Mining Control Server v2.0")
    print("  Server ID: " .. os.getComputerID())
    print("=================================")

    -- Modem init
    protocol.init()
    print("Modem initialisiert")

    -- Monitor suchen
    findMonitor()

    -- Gespeicherten Zustand laden
    if not loadState() then
        -- Neue Queue generieren (256 Chunks = 16x16 Chunk-Bereich)
        initChunkQueue(256)
    end

    print("")
    print("Config: Basis=(" .. config.BASE_X .. "," .. config.BASE_Y .. "," .. config.BASE_Z .. ")")
    print("Config wird automatisch an Turtles gesendet.")
    print("")
    print("Bereit! 'help' fuer Befehle.")
    print("")

    -- Parallel: Nachrichten empfangen + Terminal Input + Monitor + Auto-Save
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

        -- Monitor aktualisieren
        function()
            while running do
                drawMonitor()
                sleep(2)
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
                        -- Chunk zurueck in die Queue
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

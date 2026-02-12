-- ============================================================
-- ATM10 Mining Fleet - Controller
-- Fleet-Management mit Monitor-UI & Touch-Support
-- Steuert bis zu 16 Mining Turtles im Zickzack-Pattern
-- ============================================================

local protocol = require("protocol")
local MSG = protocol.MSG
local STATE = protocol.STATE

-- ============================================================
-- KONFIGURATION
-- ============================================================

local CONFIG_FILE = "controller_config"
local STATE_FILE = "controller_state"

local config = {
    monitorSide = "top",
    startChunkX = 0,
    startChunkZ = 0,
    rowWidth = 8,
    totalChunks = 128,
    minY = -64,
    maxY = 319,
}

-- ============================================================
-- STATE
-- ============================================================

local turtles = {}          -- [id] = {id, label, state, fuel, pos, chunk, y_level, lastSeen, progress}
local chunksDone = {}       -- [chunkKey] = true
local chunksActive = {}     -- [chunkKey] = turtleId
local chunkQueue = {}       -- Liste von {x, z} - noch zuzuweisende Chunks
local nextChunkIndex = 0    -- Naechster zu generierender Chunk-Index
local stats = {
    startTime = os.clock(),
    chunksCompleted = 0,
    totalFuelUsed = 0,
}

local monitor = nil
local monW, monH = 0, 0
local running = true
local paused = false

-- UI State
local cursor = { x = 0, z = 0 }    -- Cursor auf Chunk-Map
local mapOffset = { x = 0, z = 0 }  -- Scroll-Offset
local selectedTurtle = nil           -- Ausgewaehlte Turtle-ID fuer Details
local statusLog = {}                 -- Letzte Log-Nachrichten

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

local function saveControllerState()
    local data = {
        chunksDone = chunksDone,
        chunksActive = chunksActive,
        chunkQueue = chunkQueue,
        nextChunkIndex = nextChunkIndex,
        stats = stats,
        paused = paused,
        turtles = {},
    }
    -- Turtle-Daten speichern (ohne Funktionen)
    for id, t in pairs(turtles) do
        data.turtles[id] = {
            id = t.id,
            label = t.label,
            state = t.state,
            fuel = t.fuel,
            pos = t.pos,
            chunk = t.chunk,
            y_level = t.y_level,
            lastSeen = t.lastSeen,
        }
    end
    local f = fs.open(STATE_FILE, "w")
    f.write(textutils.serialise(data))
    f.close()
end

local function loadControllerState()
    if fs.exists(STATE_FILE) then
        local f = fs.open(STATE_FILE, "r")
        local data = textutils.unserialise(f.readAll())
        f.close()
        if data then
            chunksDone = data.chunksDone or {}
            chunksActive = data.chunksActive or {}
            chunkQueue = data.chunkQueue or {}
            nextChunkIndex = data.nextChunkIndex or 0
            if data.stats then
                stats = data.stats
                stats.startTime = os.clock()
            end
            paused = data.paused or false
            if data.turtles then
                for id, t in pairs(data.turtles) do
                    turtles[tonumber(id) or id] = t
                    turtles[tonumber(id) or id].state = STATE.OFFLINE
                end
            end
            return true
        end
    end
    return false
end

-- ============================================================
-- LOG
-- ============================================================

local function log(msg)
    local timeStr = string.format("[%s]", textutils.formatTime(os.time(), true))
    local entry = timeStr .. " " .. msg
    table.insert(statusLog, entry)
    if #statusLog > 50 then table.remove(statusLog, 1) end
    print(entry)
end

-- ============================================================
-- CHUNK-ZUWEISUNG (Zickzack-Pattern)
-- ============================================================

local function chunkKey(x, z)
    return x .. "," .. z
end

local function getChunkAt(index)
    -- Zickzack-Pattern: Reihen gehen abwechselnd rechts/links
    local row = math.floor(index / config.rowWidth)
    local col = index % config.rowWidth
    local cx, cz

    if row % 2 == 0 then
        -- Gerade Reihe: links nach rechts
        cx = config.startChunkX + col
    else
        -- Ungerade Reihe: rechts nach links
        cx = config.startChunkX + (config.rowWidth - 1 - col)
    end
    cz = config.startChunkZ + row

    return { x = cx, z = cz }
end

local function generateChunks(count)
    local generated = 0
    while generated < count and nextChunkIndex < config.totalChunks do
        local chunk = getChunkAt(nextChunkIndex)
        local key = chunkKey(chunk.x, chunk.z)
        if not chunksDone[key] and not chunksActive[key] then
            table.insert(chunkQueue, chunk)
            generated = generated + 1
        end
        nextChunkIndex = nextChunkIndex + 1
    end
    return generated
end

local function assignNextChunk(turtleId)
    if #chunkQueue == 0 then
        generateChunks(config.rowWidth)
    end
    if #chunkQueue == 0 then
        return false
    end

    local chunk = table.remove(chunkQueue, 1)
    local key = chunkKey(chunk.x, chunk.z)
    chunksActive[key] = turtleId

    protocol.send(turtleId, MSG.ASSIGN, {
        chunk = chunk,
        minY = config.minY,
        maxY = config.maxY,
    })

    if turtles[turtleId] then
        turtles[turtleId].chunk = chunk
        turtles[turtleId].state = STATE.TRAVELING
    end

    log("Chunk " .. chunk.x .. "," .. chunk.z .. " -> Turtle " .. turtleId)
    saveControllerState()
    return true
end

-- ============================================================
-- TURTLE MANAGEMENT
-- ============================================================

local function registerTurtle(senderId, data)
    turtles[senderId] = {
        id = senderId,
        label = data.label or ("T" .. senderId),
        state = STATE.IDLE,
        fuel = data.fuel or 0,
        pos = data.pos or { x = 0, y = 0, z = 0 },
        chunk = nil,
        y_level = data.pos and data.pos.y or 0,
        lastSeen = os.clock(),
    }
    protocol.send(senderId, MSG.ACK, { id = senderId })
    log("Turtle registriert: " .. (data.label or senderId))

    -- Sofort Chunk zuweisen wenn nicht pausiert
    if not paused then
        assignNextChunk(senderId)
    end
end

local function updateTurtle(senderId, data)
    if not turtles[senderId] then
        -- Unbekannte Turtle -> Registrierung anfordern
        registerTurtle(senderId, data)
        return
    end

    local t = turtles[senderId]
    t.state = data.state or t.state
    t.fuel = data.fuel or t.fuel
    t.pos = data.pos or t.pos
    t.chunk = data.chunk or t.chunk
    t.y_level = data.y_level or (data.pos and data.pos.y) or t.y_level
    t.lastSeen = os.clock()
    t.label = data.label or t.label
    if data.progress then
        t.progress = data.progress
    end
end

local function handleChunkDone(senderId, data)
    if data.chunk then
        local key = chunkKey(data.chunk.x, data.chunk.z)
        chunksDone[key] = true
        chunksActive[key] = nil
        stats.chunksCompleted = stats.chunksCompleted + 1
        log("Chunk fertig: " .. data.chunk.x .. "," .. data.chunk.z .. " (Turtle " .. senderId .. ")")
    end

    if turtles[senderId] then
        turtles[senderId].state = STATE.IDLE
        turtles[senderId].chunk = nil
        turtles[senderId].lastSeen = os.clock()
    end

    -- Naechsten Chunk zuweisen
    if not paused then
        sleep(1)  -- Kurz warten bis Turtle bereit
        assignNextChunk(senderId)
    end

    saveControllerState()
end

local function checkDeadTurtles()
    local now = os.clock()
    for id, t in pairs(turtles) do
        if t.state ~= STATE.OFFLINE and (now - t.lastSeen) > protocol.DEFAULTS.deadTimeout then
            log("Turtle OFFLINE: " .. (t.label or id))
            -- Chunk zurueck in Queue
            if t.chunk then
                local key = chunkKey(t.chunk.x, t.chunk.z)
                chunksActive[key] = nil
                table.insert(chunkQueue, 1, t.chunk)
                log("Chunk " .. t.chunk.x .. "," .. t.chunk.z .. " zurueck in Queue")
            end
            t.state = STATE.OFFLINE
            t.chunk = nil
            saveControllerState()
        end
    end
end

-- ============================================================
-- MONITOR UI
-- ============================================================

local function findMonitor()
    -- Versuche konfigurierte Seite
    if peripheral.getType(config.monitorSide) == "monitor" then
        return peripheral.wrap(config.monitorSide)
    end
    -- Suche auf allen Seiten
    local mon = peripheral.find("monitor")
    if mon then
        return mon
    end
    return nil
end

local function countTurtles()
    local online, total = 0, 0
    for _, t in pairs(turtles) do
        total = total + 1
        if t.state ~= STATE.OFFLINE then
            online = online + 1
        end
    end
    return online, total
end

local function countChunksDone()
    local count = 0
    for _ in pairs(chunksDone) do count = count + 1 end
    return count
end

local function formatTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function drawUI()
    if not monitor then return end

    monitor.setTextScale(0.5)
    monW, monH = monitor.getSize()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    -- ---- HEADER ----
    monitor.setCursorPos(1, 1)
    monitor.setBackgroundColor(colors.blue)
    monitor.setTextColor(colors.white)
    local online, total = countTurtles()
    local header = " ATM10 MINING FLEET"
    local headerRight = "[" .. online .. "/" .. total .. " Online] "
    monitor.write(header .. string.rep(" ", math.max(0, monW - #header - #headerRight)) .. headerRight)

    -- Pause-Anzeige
    if paused then
        monitor.setCursorPos(1, 2)
        monitor.setBackgroundColor(colors.red)
        monitor.setTextColor(colors.white)
        monitor.write(string.rep(" ", monW))
        monitor.setCursorPos(math.floor(monW / 2) - 4, 2)
        monitor.write(" PAUSED ")
    end

    monitor.setBackgroundColor(colors.black)

    -- ---- CHUNK MAP (linke Seite) ----
    local mapStartY = paused and 4 or 3
    local mapW = math.min(math.floor(monW * 0.5), config.rowWidth + 2)
    local mapH = math.min(monH - mapStartY - 6, 16)

    monitor.setCursorPos(1, mapStartY)
    monitor.setTextColor(colors.yellow)
    monitor.write(" CHUNK MAP:")

    for row = 0, mapH - 1 do
        for col = 0, math.min(config.rowWidth - 1, mapW - 3) do
            local cx = config.startChunkX + col + mapOffset.x
            local cz = config.startChunkZ + row + mapOffset.z
            local key = chunkKey(cx, cz)

            local screenX = col + 2
            local screenY = mapStartY + 1 + row

            monitor.setCursorPos(screenX, screenY)

            -- Farbe bestimmen
            if cursor.x == cx and cursor.z == cz then
                monitor.setBackgroundColor(protocol.MAP_COLORS.selected)
                monitor.setTextColor(colors.black)
                monitor.write("X")
            elseif chunksDone[key] then
                monitor.setBackgroundColor(protocol.MAP_COLORS.done)
                monitor.setTextColor(colors.black)
                monitor.write("#")
            elseif chunksActive[key] then
                monitor.setBackgroundColor(protocol.MAP_COLORS.active)
                monitor.setTextColor(colors.black)
                monitor.write(">")
            else
                -- In Queue?
                local inQueue = false
                for _, q in ipairs(chunkQueue) do
                    if q.x == cx and q.z == cz then
                        inQueue = true
                        break
                    end
                end
                if inQueue then
                    monitor.setBackgroundColor(protocol.MAP_COLORS.queued)
                    monitor.setTextColor(colors.black)
                    monitor.write("~")
                else
                    monitor.setBackgroundColor(protocol.MAP_COLORS.open)
                    monitor.setTextColor(colors.lightGray)
                    monitor.write(".")
                end
            end
            monitor.setBackgroundColor(colors.black)
        end
    end

    -- Legende
    local legendY = mapStartY + mapH + 2
    monitor.setTextColor(colors.white)
    monitor.setCursorPos(1, legendY)
    monitor.setBackgroundColor(protocol.MAP_COLORS.done)
    monitor.write("#")
    monitor.setBackgroundColor(colors.black)
    monitor.write("=Fertig ")
    monitor.setBackgroundColor(protocol.MAP_COLORS.active)
    monitor.write(">")
    monitor.setBackgroundColor(colors.black)
    monitor.write("=Aktiv ")
    monitor.setBackgroundColor(protocol.MAP_COLORS.queued)
    monitor.write("~")
    monitor.setBackgroundColor(colors.black)
    monitor.write("=Queue")

    -- ---- TURTLE STATUS (rechte Seite) ----
    local listX = mapW + 2
    local listY = mapStartY

    monitor.setCursorPos(listX, listY)
    monitor.setTextColor(colors.yellow)
    monitor.write("TURTLE STATUS:")

    local row = 0
    for id, t in pairs(turtles) do
        if row >= monH - listY - 6 then break end
        local y = listY + 1 + row

        monitor.setCursorPos(listX, y)

        -- Status-Farbe
        local stateColor = protocol.STATE_COLORS[t.state] or colors.white
        monitor.setTextColor(stateColor)

        -- Label/ID
        local label = t.label or ("T" .. id)
        if #label > 6 then label = string.sub(label, 1, 6) end
        monitor.write(label)

        -- State
        monitor.setCursorPos(listX + 7, y)
        local stateStr = string.sub(t.state or "?", 1, 7)
        monitor.write(stateStr)

        -- Y-Level
        monitor.setCursorPos(listX + 15, y)
        monitor.setTextColor(colors.white)
        if t.state == STATE.MINING and t.y_level then
            monitor.write("Y:" .. string.format("%4d", t.y_level))
        elseif t.state == STATE.IDLE then
            monitor.write("  ---")
        else
            monitor.write("     ")
        end

        -- Fuel
        monitor.setCursorPos(listX + 21, y)
        local fuelLevel = t.fuel or 0
        if fuelLevel < 1000 then
            monitor.setTextColor(colors.red)
        elseif fuelLevel < 3000 then
            monitor.setTextColor(colors.orange)
        else
            monitor.setTextColor(colors.lime)
        end
        monitor.write("F:" .. string.format("%5d", fuelLevel))

        row = row + 1
    end

    -- ---- BUTTONS ----
    local btnY = monH - 3
    monitor.setCursorPos(1, btnY)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.gray)
    monitor.write(string.rep("-", monW))

    -- Buttons zeichnen
    local buttons = {}

    btnY = btnY + 1
    monitor.setCursorPos(2, btnY)

    if paused then
        monitor.setBackgroundColor(colors.green)
        monitor.setTextColor(colors.white)
        monitor.write(" START ")
        table.insert(buttons, { x1 = 2, x2 = 8, y = btnY, action = "resume" })
    else
        monitor.setBackgroundColor(colors.orange)
        monitor.setTextColor(colors.white)
        monitor.write(" PAUSE ")
        table.insert(buttons, { x1 = 2, x2 = 8, y = btnY, action = "pause" })
    end

    monitor.setBackgroundColor(colors.black)
    monitor.write(" ")

    monitor.setBackgroundColor(colors.red)
    monitor.write(" RECALL ")
    local recallX = 11
    table.insert(buttons, { x1 = recallX, x2 = recallX + 7, y = btnY, action = "recall" })

    monitor.setBackgroundColor(colors.black)
    monitor.write(" ")

    local addX = recallX + 10
    monitor.setCursorPos(addX, btnY)
    monitor.setBackgroundColor(colors.cyan)
    monitor.write(" +CHUNKS ")
    table.insert(buttons, { x1 = addX, x2 = addX + 8, y = btnY, action = "addchunks" })

    monitor.setBackgroundColor(colors.black)

    -- ---- STATISTIK-ZEILE ----
    local statY = monH - 1
    monitor.setCursorPos(1, statY)
    monitor.setTextColor(colors.lightGray)
    local done = countChunksDone()
    local elapsed = formatTime(os.clock() - stats.startTime)
    local statLine = " Chunks: " .. done .. "/" .. config.totalChunks
        .. " | Zeit: " .. elapsed
    if done > 0 then
        local rate = (os.clock() - stats.startTime) / done
        local remaining = (config.totalChunks - done) * rate
        statLine = statLine .. " | Rest: ~" .. formatTime(remaining)
    end
    monitor.write(statLine)

    -- ---- CURSOR INFO ----
    monitor.setCursorPos(1, monH)
    monitor.setTextColor(colors.white)
    local cursorKey = chunkKey(cursor.x, cursor.z)
    local cursorInfo = " Cursor: " .. cursor.x .. "," .. cursor.z
    if chunksDone[cursorKey] then
        cursorInfo = cursorInfo .. " [FERTIG]"
    elseif chunksActive[cursorKey] then
        cursorInfo = cursorInfo .. " [AKTIV: T" .. chunksActive[cursorKey] .. "]"
    else
        cursorInfo = cursorInfo .. " [FREI]"
    end
    monitor.write(cursorInfo)

    return buttons
end

-- ============================================================
-- KONFIGURATIONS-MODUS
-- ============================================================

local function runConfigMode()
    print("=== Controller Konfiguration ===")
    print()
    print("Monitor-Seite (top/bottom/left/right/back/front):")
    local side = read()
    if side and #side > 0 then config.monitorSide = side end

    print()
    print("Start-Chunk X (Chunk-Koordinate, nicht Block):")
    config.startChunkX = tonumber(read()) or 0
    print("Start-Chunk Z:")
    config.startChunkZ = tonumber(read()) or 0

    print()
    print("Reihenbreite (Chunks pro Reihe, Standard: 8):")
    config.rowWidth = tonumber(read()) or 8

    print()
    print("Gesamtanzahl Chunks (Standard: 128):")
    config.totalChunks = tonumber(read()) or 128

    print()
    print("Min Y (Standard: -64):")
    config.minY = tonumber(read()) or -64
    print("Max Y (Standard: 319):")
    config.maxY = tonumber(read()) or 319

    saveConfig()
    print()
    print("Konfiguration gespeichert!")
end

-- ============================================================
-- NACHRICHTEN-EMPFANG
-- ============================================================

local function messageLoop()
    while running do
        local senderId, msg = protocol.receive(2)
        if msg then
            if msg.type == MSG.REGISTER then
                registerTurtle(senderId, msg)
            elseif msg.type == MSG.STATUS then
                updateTurtle(senderId, msg)
            elseif msg.type == MSG.CHUNK_DONE then
                handleChunkDone(senderId, msg)
            elseif msg.type == MSG.NEED_FUEL then
                log("Turtle " .. senderId .. ": FUEL NIEDRIG (" .. (msg.fuel or "?") .. ")")
                if turtles[senderId] then
                    turtles[senderId].lastSeen = os.clock()
                end
            elseif msg.type == MSG.ERROR then
                log("FEHLER Turtle " .. senderId .. ": " .. (msg.message or "unbekannt"))
                if turtles[senderId] then
                    turtles[senderId].state = STATE.ERROR
                    turtles[senderId].lastSeen = os.clock()
                end
            elseif msg.type == MSG.HEARTBEAT then
                if turtles[senderId] then
                    turtles[senderId].fuel = msg.fuel or turtles[senderId].fuel
                    turtles[senderId].state = msg.state or turtles[senderId].state
                    turtles[senderId].lastSeen = os.clock()
                end
            end
        end
    end
end

-- ============================================================
-- TASTATUR-STEUERUNG
-- ============================================================

local function inputLoop()
    while running do
        local event, key = os.pullEvent("key")

        if key == keys.up then
            cursor.z = cursor.z - 1
        elseif key == keys.down then
            cursor.z = cursor.z + 1
        elseif key == keys.left then
            cursor.x = cursor.x - 1
        elseif key == keys.right then
            cursor.x = cursor.x + 1
        elseif key == keys.enter then
            -- Chunk manuell zur Queue hinzufuegen
            local k = chunkKey(cursor.x, cursor.z)
            if not chunksDone[k] and not chunksActive[k] then
                table.insert(chunkQueue, { x = cursor.x, z = cursor.z })
                log("Chunk " .. cursor.x .. "," .. cursor.z .. " zur Queue hinzugefuegt")
                -- Sofort zuweisen wenn Turtle idle
                for id, t in pairs(turtles) do
                    if t.state == STATE.IDLE then
                        assignNextChunk(id)
                        break
                    end
                end
            end
        elseif key == keys.p then
            -- Pause/Resume Toggle
            paused = not paused
            if paused then
                log("PAUSE - Alle Turtles pausiert")
                protocol.broadcast(MSG.PAUSE, {})
            else
                log("RESUME - Mining fortgesetzt")
                protocol.broadcast(MSG.RESUME, {})
                -- Idle Turtles Chunks zuweisen
                for id, t in pairs(turtles) do
                    if t.state == STATE.IDLE then
                        assignNextChunk(id)
                    end
                end
            end
        elseif key == keys.r then
            -- Recall alle Turtles
            log("RECALL - Alle Turtles zurueckgerufen")
            protocol.broadcast(MSG.RECALL, {})
        elseif key == keys.g then
            -- Chunks generieren
            local n = generateChunks(config.rowWidth)
            log(n .. " Chunks generiert")
        elseif key == keys.o then
            -- Cursor als neuen Startpunkt setzen
            config.startChunkX = cursor.x
            config.startChunkZ = cursor.z
            nextChunkIndex = 0
            saveConfig()
            log("Neuer Start: " .. cursor.x .. "," .. cursor.z)
        elseif key == keys.q then
            -- Beenden
            log("Controller beendet")
            running = false
        end
    end
end

-- ============================================================
-- MONITOR TOUCH
-- ============================================================

local function touchLoop()
    local buttons = {}
    while running do
        local event, side, tx, ty = os.pullEvent()

        if event == "monitor_touch" then
            -- Button-Check
            for _, btn in ipairs(buttons or {}) do
                if tx >= btn.x1 and tx <= btn.x2 and ty == btn.y then
                    if btn.action == "pause" then
                        paused = true
                        log("PAUSE (Touch)")
                        protocol.broadcast(MSG.PAUSE, {})
                    elseif btn.action == "resume" then
                        paused = false
                        log("RESUME (Touch)")
                        protocol.broadcast(MSG.RESUME, {})
                        for id, t in pairs(turtles) do
                            if t.state == STATE.IDLE then
                                assignNextChunk(id)
                            end
                        end
                    elseif btn.action == "recall" then
                        log("RECALL ALL (Touch)")
                        protocol.broadcast(MSG.RECALL, {})
                    elseif btn.action == "addchunks" then
                        local n = generateChunks(config.rowWidth)
                        log(n .. " Chunks hinzugefuegt (Touch)")
                    end
                    break
                end
            end

            -- Chunk-Map Touch
            local mapStartY = paused and 4 or 3
            if ty > mapStartY and ty <= mapStartY + 16 and tx >= 2 and tx <= config.rowWidth + 1 then
                local col = tx - 2
                local row = ty - mapStartY - 1
                cursor.x = config.startChunkX + col + mapOffset.x
                cursor.z = config.startChunkZ + row + mapOffset.z
            end
        end

        -- UI neu zeichnen (egal welches Event)
        buttons = drawUI()
    end
end

-- ============================================================
-- UI REFRESH
-- ============================================================

local function uiLoop()
    while running do
        drawUI()
        sleep(1)
    end
end

-- ============================================================
-- AUTO-SAVE & DEAD-DETECTION
-- ============================================================

local function maintenanceLoop()
    while running do
        sleep(protocol.DEFAULTS.saveInterval)
        saveControllerState()
        checkDeadTurtles()
    end
end

-- ============================================================
-- AUTO-ASSIGN IDLE TURTLES
-- ============================================================

local function autoAssignLoop()
    while running do
        sleep(5)
        if not paused then
            for id, t in pairs(turtles) do
                if t.state == STATE.IDLE and t.state ~= STATE.OFFLINE then
                    assignNextChunk(id)
                end
            end
        end
    end
end

-- ============================================================
-- MODEM SETUP
-- ============================================================

local function openModem()
    local sides = {"left", "right", "top", "bottom", "front", "back"}
    for _, side in ipairs(sides) do
        if peripheral.getType(side) == "modem" then
            rednet.open(side)
            print("Modem geoeffnet: " .. side)
            return true
        end
    end
    -- Peripherals suchen
    local modem = peripheral.find("modem")
    if modem then
        local name = peripheral.getName(modem)
        rednet.open(name)
        print("Modem geoeffnet: " .. name)
        return true
    end
    print("FEHLER: Kein Modem gefunden!")
    return false
end

-- ============================================================
-- HAUPTPROGRAMM
-- ============================================================

local args = { ... }

-- Config-Modus
if args[1] == "config" then
    runConfigMode()
    return
end

-- Banner
term.clear()
term.setCursorPos(1, 1)
print("========================================")
print("  ATM10 Mining Fleet - Controller")
print("  Computer ID: " .. os.getComputerID())
print("========================================")

-- Config laden
if not loadConfig() then
    print("Keine Konfiguration gefunden!")
    print("Starte Konfiguration...")
    runConfigMode()
end

-- State laden
local hasState = loadControllerState()
if hasState then
    print("Gespeicherter State geladen:")
    print("  Chunks fertig: " .. countChunksDone())
    print("  Chunks in Queue: " .. #chunkQueue)
    print("  Turtles bekannt: " .. select(2, countTurtles()))
end

-- Modem oeffnen
if not openModem() then return end

-- Monitor suchen
monitor = findMonitor()
if monitor then
    print("Monitor gefunden!")
    monitor.setTextScale(0.5)
    monW, monH = monitor.getSize()
    print("Monitor-Groesse: " .. monW .. "x" .. monH)
else
    print("WARNUNG: Kein Monitor gefunden!")
    print("Nur Terminal-Ausgabe verfuegbar.")
end

-- Initiale Chunks generieren falls Queue leer
if #chunkQueue == 0 then
    generateChunks(config.rowWidth * 2)
end

-- Cursor auf Start setzen
cursor.x = config.startChunkX
cursor.z = config.startChunkZ

print()
print("Steuerung:")
print("  Pfeiltasten = Cursor bewegen")
print("  Enter = Chunk zur Queue")
print("  P = Pause/Resume")
print("  R = Recall alle Turtles")
print("  G = Chunks generieren")
print("  O = Neuer Startpunkt")
print("  Q = Beenden")
print()
log("Controller gestartet")

-- Parallel ausfuehren
parallel.waitForAny(
    messageLoop,
    inputLoop,
    touchLoop,
    uiLoop,
    maintenanceLoop,
    autoAssignLoop
)

-- Aufraemen
log("Speichere State...")
saveControllerState()
if monitor then
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    monitor.setCursorPos(1, 1)
    monitor.setTextColor(colors.red)
    monitor.write("Controller offline")
end
print("Controller beendet.")

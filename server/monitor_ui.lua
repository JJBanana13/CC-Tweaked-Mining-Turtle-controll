-- ============================================
-- Monitor UI - Touch-basierte Oberflaeche
-- Mastermine-Style Interface fuer den
-- Mining Control Server
-- ============================================

local ui = {}

local monitor = nil
local serverState = nil
local config = nil
local buttons = {}

-- ============================================
-- Button System
-- ============================================

local function clearButtons()
    buttons = {}
end

local function addButton(x, y, width, height, label, action, bgColor, fgColor)
    table.insert(buttons, {
        x1 = x, y1 = y,
        x2 = x + width - 1, y2 = y + height - 1,
        label = label,
        action = action,
        bgColor = bgColor or colors.gray,
        fgColor = fgColor or colors.white,
    })
end

local function drawButton(btn)
    for row = btn.y1, btn.y2 do
        monitor.setCursorPos(btn.x1, row)
        monitor.setBackgroundColor(btn.bgColor)
        monitor.setTextColor(btn.fgColor)
        monitor.write(string.rep(" ", btn.x2 - btn.x1 + 1))
    end
    -- Label zentrieren
    local labelY = math.floor((btn.y1 + btn.y2) / 2)
    local labelX = math.floor(btn.x1 + (btn.x2 - btn.x1 + 1 - #btn.label) / 2)
    monitor.setCursorPos(labelX, labelY)
    monitor.setBackgroundColor(btn.bgColor)
    monitor.setTextColor(btn.fgColor)
    monitor.write(btn.label)
end

local function findButton(x, y)
    for _, btn in ipairs(buttons) do
        if x >= btn.x1 and x <= btn.x2 and y >= btn.y1 and y <= btn.y2 then
            return btn
        end
    end
    return nil
end

-- ============================================
-- Hilfsfunktionen
-- ============================================

local function drawLine(y, char, color)
    monitor.setCursorPos(1, y)
    monitor.setTextColor(color or colors.gray)
    monitor.setBackgroundColor(colors.black)
    local w, _ = monitor.getSize()
    monitor.write(string.rep(char or "-", w))
end

local function centerText(y, text, fgColor, bgColor)
    local w, _ = monitor.getSize()
    local x = math.floor((w - #text) / 2) + 1
    monitor.setCursorPos(x, y)
    monitor.setTextColor(fgColor or colors.white)
    monitor.setBackgroundColor(bgColor or colors.black)
    monitor.write(text)
end

local function getStatusColor(status)
    if status == "mining" then return colors.lime
    elseif status == "traveling" then return colors.cyan
    elseif status == "refueling" then return colors.orange
    elseif status == "depositing" then return colors.magenta
    elseif status == "paused" then return colors.yellow
    elseif status == "error" then return colors.red
    elseif status == "idle" then return colors.lightGray
    else return colors.white
    end
end

local function getTurtleCount()
    local count = 0
    for _ in pairs(serverState.turtles) do count = count + 1 end
    return count
end

local function getSortedTurtleIds()
    local ids = {}
    for id in pairs(serverState.turtles) do table.insert(ids, id) end
    table.sort(ids)
    return ids
end

-- ============================================
-- Haupt-Zeichenfunktion
-- ============================================

function ui.draw()
    if not monitor then return end

    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    clearButtons()

    local w, h = monitor.getSize()

    -- ==========================================
    -- TITEL-LEISTE (Zeile 1)
    -- ==========================================
    monitor.setCursorPos(1, 1)
    monitor.setBackgroundColor(colors.gray)
    monitor.setTextColor(colors.yellow)
    local title = " MINING CONTROL "
    local pad = string.rep(" ", w)
    monitor.write(pad)
    local titleX = math.floor((w - #title) / 2) + 1
    monitor.setCursorPos(titleX, 1)
    monitor.write(title)
    monitor.setBackgroundColor(colors.black)

    -- ==========================================
    -- STATUS + START/STOP BUTTON (Zeile 2-4)
    -- ==========================================

    -- Grosser Start/Stop Button rechts
    local toggleW = 14
    local toggleH = 3
    local toggleX = w - toggleW
    local toggleY = 2

    if serverState.paused then
        addButton(toggleX, toggleY, toggleW, toggleH, ">> START <<", "start", colors.green, colors.white)
    else
        addButton(toggleX, toggleY, toggleW, toggleH, "|| STOP ||", "stop", colors.red, colors.white)
    end

    -- Statistiken links
    local statsW = toggleX - 2

    monitor.setCursorPos(2, 2)
    monitor.setTextColor(colors.white)
    monitor.setBackgroundColor(colors.black)
    local chunksDone = serverState.stats.totalChunksCompleted
    local chunksQueue = #serverState.chunkQueue
    monitor.write("Chunks: " .. chunksDone .. " fertig | " .. chunksQueue .. " in Queue")

    monitor.setCursorPos(2, 3)
    local elapsed = os.clock() - serverState.stats.startTime
    local mins = math.floor(elapsed / 60)
    local secs = math.floor(elapsed % 60)
    monitor.write("Laufzeit: " .. mins .. "m " .. secs .. "s")

    monitor.setCursorPos(2, 4)
    monitor.write("Bloecke: " .. serverState.stats.totalBlocksMined)

    -- Status-Anzeige
    local statusX = math.floor(statsW / 2) + 1
    monitor.setCursorPos(statusX, 4)
    if serverState.paused then
        monitor.setTextColor(colors.red)
        monitor.write("  PAUSIERT")
    else
        monitor.setTextColor(colors.lime)
        monitor.write("  AKTIV")
    end

    -- ==========================================
    -- TRENNLINIE (Zeile 5)
    -- ==========================================
    drawLine(5, "-", colors.gray)

    -- ==========================================
    -- TURTLE-LISTE (Zeile 6 bis h-4)
    -- ==========================================

    local turtleCount = getTurtleCount()
    monitor.setCursorPos(2, 6)
    monitor.setTextColor(colors.yellow)
    monitor.setBackgroundColor(colors.black)
    monitor.write("Turtles (" .. turtleCount .. "/" .. config.MAX_TURTLES .. ")")

    local listStartY = 7
    local listEndY = h - 4
    local maxLines = listEndY - listStartY + 1

    if turtleCount == 0 then
        monitor.setCursorPos(2, listStartY)
        monitor.setTextColor(colors.gray)
        monitor.write("Warte auf Turtles...")
    else
        local sortedIds = getSortedTurtleIds()
        local line = listStartY

        for _, id in ipairs(sortedIds) do
            if line > listEndY then break end
            local t = serverState.turtles[id]
            local statusColor = getStatusColor(t.status)

            -- Hintergrund fuer gerade/ungerade Zeilen
            local bgColor = colors.black
            if (line - listStartY) % 2 == 1 then
                bgColor = colors.black
            end

            -- Zeile loeschen
            monitor.setCursorPos(1, line)
            monitor.setBackgroundColor(bgColor)
            monitor.write(string.rep(" ", w))

            -- ID
            monitor.setCursorPos(2, line)
            monitor.setTextColor(colors.lightGray)
            monitor.setBackgroundColor(bgColor)
            monitor.write(string.format("#%-3d", id))

            -- Label
            monitor.setCursorPos(6, line)
            monitor.setTextColor(colors.white)
            local label = (t.label or "?"):sub(1, 10)
            monitor.write(string.format("%-10s", label))

            -- Status (farbcodiert)
            monitor.setCursorPos(17, line)
            monitor.setTextColor(statusColor)
            local status = (t.status or "?"):sub(1, 9)
            monitor.write(string.format("%-9s", status))

            -- Fuel
            monitor.setCursorPos(27, line)
            local fuelColor = colors.white
            if t.fuel and t.fuel < (config.FUEL_THRESHOLD or 1000) then
                fuelColor = colors.red
            end
            monitor.setTextColor(fuelColor)
            monitor.write("F:" .. (t.fuel or "?"))

            -- Chunk
            if w > 45 then
                monitor.setCursorPos(37, line)
                monitor.setTextColor(colors.white)
                local chunkStr = "---"
                if t.chunk then
                    chunkStr = t.chunk.cx .. "," .. t.chunk.cz
                end
                monitor.write("C:" .. chunkStr)
            end

            -- Y-Level
            if w > 55 then
                monitor.setCursorPos(48, line)
                monitor.setTextColor(colors.white)
                monitor.write("Y:" .. (t.layer or "?"))
            end

            line = line + 1
        end
    end

    -- ==========================================
    -- TRENNLINIE (h-3)
    -- ==========================================
    drawLine(h - 3, "-", colors.gray)

    -- ==========================================
    -- CONTROL BUTTONS (letzte 2 Zeilen)
    -- ==========================================

    local btnH = 2
    local btnY = h - 1
    local gap = 1
    local numBtns = 4
    local totalGaps = (numBtns - 1) * gap + 2  -- +2 fuer Rand links/rechts
    local btnW = math.floor((w - totalGaps) / numBtns)
    local startX = 2

    addButton(startX, btnY, btnW, btnH,
        "START ALL", "start_all", colors.green, colors.white)

    addButton(startX + btnW + gap, btnY, btnW, btnH,
        "PAUSE ALL", "pause_all", colors.orange, colors.white)

    addButton(startX + 2 * (btnW + gap), btnY, btnW, btnH,
        "HOME ALL", "home_all", colors.cyan, colors.gray)

    addButton(startX + 3 * (btnW + gap), btnY, btnW, btnH,
        "RESUME ALL", "resume_all", colors.blue, colors.white)

    -- Alle Buttons zeichnen
    for _, btn in ipairs(buttons) do
        drawButton(btn)
    end

    -- Hintergrund zuruecksetzen
    monitor.setBackgroundColor(colors.black)
end

-- ============================================
-- Initialisierung
-- ============================================

function ui.init(mon, state, cfg)
    monitor = mon
    serverState = state
    config = cfg
    if monitor then
        monitor.setTextScale(0.5)
        monitor.clear()
    end
end

-- ============================================
-- Touch-Event verarbeiten
-- ============================================

function ui.handleTouch(x, y)
    local btn = findButton(x, y)
    if btn then
        return btn.action
    end
    return nil
end

return ui

-- ============================================
-- ChunkMiner - Server / Hub
-- ============================================
-- Central server that manages 16 mining turtles
-- Provides touchscreen monitor GUI for control

local config = require("config")

-- ============================================
-- State
-- ============================================
local turtles = {}       -- [slot] = turtle data
local turtlesByID = {}   -- [computerID] = slot
local nextSlot = 1
local miningActive = false
local chunkOrigin = { x = 0, z = 0 }  -- Set via GUI
local serverRunning = true

-- ============================================
-- Modem Setup
-- ============================================
local modem = peripheral.find("modem")
if not modem then
    error("No modem found! Attach a wireless modem.")
end
rednet.open(peripheral.getName(modem))

-- ============================================
-- Monitor Setup
-- ============================================
local monitor = peripheral.find("monitor")
if not monitor then
    print("WARNING: No monitor found. Running in headless mode.")
    print("Attach a monitor for the GUI.")
end

-- ============================================
-- Turtle Slot Assignment
-- ============================================
local function getSlotPosition(slot)
    -- Convert slot (1-16) to grid position
    -- Slot 1 = top-left (0,0), Slot 16 = bottom-right (3,3)
    local row = math.floor((slot - 1) / config.GRID_SIZE)
    local col = (slot - 1) % config.GRID_SIZE
    return row, col
end

local function getMineStart(slot)
    local row, col = getSlotPosition(slot)
    return {
        x = chunkOrigin.x + (col * config.SECTION_WIDTH),
        z = chunkOrigin.z + (row * config.SECTION_DEPTH),
    }
end

local function getHomePos(slot)
    -- Home positions: turtles line up along x-axis above the chunk
    return {
        x = chunkOrigin.x + ((slot - 1) % 16),
        y = config.START_Y + 2,
        z = chunkOrigin.z - 2,
    }
end

local function assignTurtle(turtleID, turtleData)
    if turtlesByID[turtleID] then
        -- Already assigned, resend assignment
        local slot = turtlesByID[turtleID]
        return slot
    end

    if nextSlot > config.TURTLE_COUNT then
        print("All slots full! Cannot assign turtle " .. turtleID)
        return nil
    end

    local slot = nextSlot
    nextSlot = nextSlot + 1

    turtles[slot] = {
        id = turtleID,
        label = turtleData.label or ("Turtle-" .. turtleID),
        slot = slot,
        status = "idle",
        position = { x = 0, y = 0, z = 0 },
        fuel = turtleData.fuel or 0,
        blocksMinied = 0,
        layersDone = 0,
        totalLayers = 0,
        currentLayer = 0,
        inventoryUsed = 0,
        errorMsg = "",
        lastSeen = os.clock(),
    }
    turtlesByID[turtleID] = slot

    print("Assigned turtle " .. turtleID .. " to slot " .. slot)
    return slot
end

-- ============================================
-- Communication
-- ============================================
local function sendToTurtle(slot, msg)
    if turtles[slot] then
        rednet.send(turtles[slot].id, msg, config.PROTOCOL)
    end
end

local function sendToAll(msg)
    for slot = 1, config.TURTLE_COUNT do
        if turtles[slot] then
            sendToTurtle(slot, msg)
        end
    end
end

local function handleRegistration(senderID, msg)
    local slot = assignTurtle(senderID, msg)
    if slot then
        local reply = {
            type = "assign",
            slot = slot,
            homePos = getHomePos(slot),
            mineStart = getMineStart(slot),
            startPos = getHomePos(slot),
            facing = 0,
        }
        rednet.send(senderID, reply, config.PROTOCOL)
    end
end

local function handleStatus(senderID, msg)
    local slot = turtlesByID[senderID]
    if slot and turtles[slot] then
        turtles[slot].status = msg.status or "unknown"
        turtles[slot].position = msg.position or turtles[slot].position
        turtles[slot].fuel = msg.fuel or 0
        turtles[slot].blocksMinied = msg.blocksMinied or 0
        turtles[slot].layersDone = msg.layersDone or 0
        turtles[slot].totalLayers = msg.totalLayers or 0
        turtles[slot].currentLayer = msg.currentLayer or 0
        turtles[slot].inventoryUsed = msg.inventoryUsed or 0
        turtles[slot].errorMsg = msg.errorMsg or ""
        turtles[slot].lastSeen = os.clock()
    end
end

-- ============================================
-- Commands
-- ============================================
local function startMining()
    miningActive = true
    sendToAll({ type = "start" })
    print("Mining started!")
end

local function stopMining()
    miningActive = false
    sendToAll({ type = "stop" })
    print("Mining stopped!")
end

local function recallAll()
    miningActive = false
    sendToAll({ type = "recall" })
    print("Recalling all turtles!")
end

local function resumeAll()
    miningActive = true
    sendToAll({ type = "resume" })
    print("Resuming all turtles!")
end

local function pingAll()
    sendToAll({ type = "ping" })
end

local function startSingle(slot)
    if turtles[slot] then
        sendToTurtle(slot, { type = "start" })
    end
end

local function stopSingle(slot)
    if turtles[slot] then
        sendToTurtle(slot, { type = "stop" })
    end
end

local function recallSingle(slot)
    if turtles[slot] then
        sendToTurtle(slot, { type = "recall" })
    end
end

-- ============================================
-- Monitor GUI
-- ============================================
local gui = {}
gui.buttons = {}
gui.page = "main"  -- main, detail
gui.selectedTurtle = nil
gui.inputMode = nil
gui.inputBuffer = ""

local function getStatusChar(status)
    local chars = {
        idle = ".",
        mining = "#",
        returning = "<",
        refueling = "F",
        dumping = "D",
        error = "!",
        offline = "X",
        done = "O",
        halted = "H",
    }
    return chars[status] or "?"
end

local function getStatusColor(status)
    return config.COLORS[status] or colors.white
end

local function addButton(x, y, w, h, text, color, action)
    table.insert(gui.buttons, {
        x = x, y = y, w = w, h = h,
        text = text, color = color, action = action,
    })
end

local function clearButtons()
    gui.buttons = {}
end

local function drawButton(mon, btn)
    mon.setBackgroundColor(btn.color)
    mon.setTextColor(colors.white)
    for row = btn.y, btn.y + btn.h - 1 do
        mon.setCursorPos(btn.x, row)
        mon.write(string.rep(" ", btn.w))
    end
    -- Center text
    local textY = btn.y + math.floor(btn.h / 2)
    local textX = btn.x + math.floor((btn.w - #btn.text) / 2)
    mon.setCursorPos(textX, textY)
    mon.write(btn.text)
end

local function drawMainPage(mon)
    clearButtons()

    local w, h = mon.getSize()
    mon.setBackgroundColor(colors.black)
    mon.clear()

    -- Title bar
    mon.setBackgroundColor(colors.blue)
    mon.setCursorPos(1, 1)
    mon.write(string.rep(" ", w))
    mon.setCursorPos(2, 1)
    mon.setTextColor(colors.white)
    mon.write("ChunkMiner v1.0")

    local statusText = miningActive and " [ACTIVE]" or " [STOPPED]"
    local statusColor = miningActive and colors.lime or colors.red
    mon.setTextColor(statusColor)
    mon.write(statusText)

    -- Connected count
    local connected = 0
    local mining = 0
    local done = 0
    for slot = 1, config.TURTLE_COUNT do
        if turtles[slot] then
            connected = connected + 1
            if turtles[slot].status == "mining" then mining = mining + 1 end
            if turtles[slot].status == "done" then done = done + 1 end
        end
    end

    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.lightGray)
    mon.setCursorPos(2, 3)
    mon.write("Turtles: " .. connected .. "/" .. config.TURTLE_COUNT)
    mon.setCursorPos(2, 4)
    mon.write("Mining: " .. mining .. "  Done: " .. done)

    -- Chunk origin display
    mon.setCursorPos(w - 20, 3)
    mon.setTextColor(colors.yellow)
    mon.write("Chunk: " .. chunkOrigin.x .. ", " .. chunkOrigin.z)

    -- 4x4 Turtle Grid
    local gridStartX = 3
    local gridStartY = 6
    local cellW = math.max(6, math.floor((w - 6) / 4))
    local cellH = math.max(3, math.floor((h - 14) / 4))

    for slot = 1, 16 do
        local row, col = getSlotPosition(slot)
        local cx = gridStartX + (col * cellW)
        local cy = gridStartY + (row * cellH)

        local t = turtles[slot]
        local status = t and t.status or "offline"
        local bgColor = getStatusColor(status)

        -- Draw cell background
        for r = cy, cy + cellH - 2 do
            mon.setCursorPos(cx, r)
            mon.setBackgroundColor(bgColor)
            mon.write(string.rep(" ", cellW - 1))
        end

        -- Slot number
        mon.setCursorPos(cx + 1, cy)
        mon.setTextColor(colors.white)
        mon.setBackgroundColor(bgColor)
        mon.write("#" .. string.format("%02d", slot))

        -- Fuel bar or status
        if t then
            mon.setCursorPos(cx + 1, cy + 1)
            mon.setTextColor(colors.black)

            -- Show fuel level as bar
            local fuelPct = 0
            if t.fuel > 0 then
                fuelPct = math.min(100, math.floor(t.fuel / 200))
            end
            mon.write("F:" .. fuelPct .. "%")

            if cellH >= 4 then
                mon.setCursorPos(cx + 1, cy + 2)
                -- Progress
                if t.totalLayers > 0 then
                    local pct = math.floor((t.layersDone / t.totalLayers) * 100)
                    mon.write(pct .. "%")
                else
                    mon.write(status:sub(1, cellW - 3))
                end
            end
        else
            mon.setCursorPos(cx + 1, cy + 1)
            mon.setTextColor(colors.black)
            mon.write("---")
        end

        -- Make the cell clickable
        addButton(cx, cy, cellW - 1, cellH - 1, "", colors.black, function()
            if turtles[slot] then
                gui.selectedTurtle = slot
                gui.page = "detail"
            end
        end)
    end

    -- Control buttons at bottom
    local btnY = h - 3
    local btnW = math.floor((w - 8) / 4)

    addButton(2, btnY, btnW, 2, "START ALL", colors.green, function()
        startMining()
    end)

    addButton(3 + btnW, btnY, btnW, 2, "STOP ALL", colors.red, function()
        stopMining()
    end)

    addButton(4 + btnW * 2, btnY, btnW, 2, "RECALL", colors.orange, function()
        recallAll()
    end)

    addButton(5 + btnW * 3, btnY, btnW, 2, "SET CHUNK", colors.purple, function()
        gui.inputMode = "chunk_x"
        gui.inputBuffer = ""
    end)

    -- Draw buttons
    for _, btn in ipairs(gui.buttons) do
        if btn.text ~= "" then
            drawButton(mon, btn)
        end
    end

    -- Input mode overlay
    if gui.inputMode then
        mon.setBackgroundColor(colors.gray)
        local inputY = math.floor(h / 2)
        for r = inputY - 1, inputY + 1 do
            mon.setCursorPos(4, r)
            mon.write(string.rep(" ", w - 6))
        end
        mon.setCursorPos(5, inputY)
        mon.setTextColor(colors.white)
        if gui.inputMode == "chunk_x" then
            mon.write("Chunk X: " .. gui.inputBuffer .. "_")
        elseif gui.inputMode == "chunk_z" then
            mon.write("Chunk Z: " .. gui.inputBuffer .. "_")
        end
    end
end

local function drawDetailPage(mon)
    clearButtons()

    local w, h = mon.getSize()
    local slot = gui.selectedTurtle
    local t = turtles[slot]

    mon.setBackgroundColor(colors.black)
    mon.clear()

    -- Title
    mon.setBackgroundColor(colors.blue)
    mon.setCursorPos(1, 1)
    mon.write(string.rep(" ", w))
    mon.setCursorPos(2, 1)
    mon.setTextColor(colors.white)
    mon.write("Turtle #" .. string.format("%02d", slot))

    if not t then
        mon.setBackgroundColor(colors.black)
        mon.setCursorPos(2, 4)
        mon.setTextColor(colors.red)
        mon.write("NOT CONNECTED")
    else
        mon.setBackgroundColor(colors.black)

        -- Status
        mon.setCursorPos(2, 3)
        mon.setTextColor(colors.lightGray)
        mon.write("Status: ")
        mon.setTextColor(getStatusColor(t.status))
        mon.write(t.status:upper())

        -- Position
        mon.setCursorPos(2, 5)
        mon.setTextColor(colors.lightGray)
        mon.write("Position: ")
        mon.setTextColor(colors.white)
        mon.write(t.position.x .. ", " .. t.position.y .. ", " .. t.position.z)

        -- Fuel
        mon.setCursorPos(2, 7)
        mon.setTextColor(colors.lightGray)
        mon.write("Fuel: ")
        local fuelColor = colors.lime
        if t.fuel < config.FUEL_THRESHOLD then fuelColor = colors.red
        elseif t.fuel < config.FUEL_THRESHOLD * 3 then fuelColor = colors.yellow end
        mon.setTextColor(fuelColor)
        mon.write(tostring(t.fuel))

        -- Mining progress
        mon.setCursorPos(2, 9)
        mon.setTextColor(colors.lightGray)
        mon.write("Layer: ")
        mon.setTextColor(colors.white)
        mon.write(tostring(t.currentLayer))

        mon.setCursorPos(2, 10)
        mon.setTextColor(colors.lightGray)
        mon.write("Progress: ")
        mon.setTextColor(colors.white)
        if t.totalLayers > 0 then
            local pct = math.floor((t.layersDone / t.totalLayers) * 100)
            mon.write(pct .. "% (" .. t.layersDone .. "/" .. t.totalLayers .. " layers)")
        else
            mon.write("N/A")
        end

        -- Blocks mined
        mon.setCursorPos(2, 12)
        mon.setTextColor(colors.lightGray)
        mon.write("Blocks: ")
        mon.setTextColor(colors.white)
        mon.write(tostring(t.blocksMinied))

        -- Inventory
        mon.setCursorPos(2, 13)
        mon.setTextColor(colors.lightGray)
        mon.write("Inventory: ")
        mon.setTextColor(colors.white)
        mon.write(t.inventoryUsed .. "/16 slots")

        -- Error
        if t.errorMsg and t.errorMsg ~= "" then
            mon.setCursorPos(2, 15)
            mon.setTextColor(colors.red)
            mon.write("Error: " .. t.errorMsg)
        end

        -- Progress bar
        mon.setCursorPos(2, h - 5)
        mon.setTextColor(colors.lightGray)
        mon.write("Mining Progress:")
        local barW = w - 4
        local barY = h - 4
        mon.setCursorPos(2, barY)
        mon.setBackgroundColor(colors.gray)
        mon.write(string.rep(" ", barW))
        if t.totalLayers > 0 then
            local filled = math.floor((t.layersDone / t.totalLayers) * barW)
            mon.setCursorPos(2, barY)
            mon.setBackgroundColor(colors.lime)
            mon.write(string.rep(" ", filled))
        end
    end

    -- Bottom buttons
    mon.setBackgroundColor(colors.black)
    local btnY = h - 1
    local btnW = math.floor((w - 6) / 3)

    addButton(2, btnY, btnW, 1, "< BACK", colors.gray, function()
        gui.page = "main"
        gui.selectedTurtle = nil
    end)

    addButton(3 + btnW, btnY, btnW, 1, "START", colors.green, function()
        if slot then startSingle(slot) end
    end)

    addButton(4 + btnW * 2, btnY, btnW, 1, "STOP", colors.red, function()
        if slot then stopSingle(slot) end
    end)

    for _, btn in ipairs(gui.buttons) do
        drawButton(mon, btn)
    end
end

local function drawGUI()
    if not monitor then return end

    monitor.setTextScale(0.5)

    if gui.page == "main" then
        drawMainPage(monitor)
    elseif gui.page == "detail" then
        drawDetailPage(monitor)
    end
end

-- ============================================
-- Touch Handling
-- ============================================
local function handleTouch(x, y)
    -- Handle input mode first
    if gui.inputMode then
        -- Not a touch-keyboard, use terminal input instead
        return
    end

    -- Check buttons (reverse order for overlay priority)
    for i = #gui.buttons, 1, -1 do
        local btn = gui.buttons[i]
        if x >= btn.x and x < btn.x + btn.w and
           y >= btn.y and y < btn.y + btn.h then
            if btn.action then
                btn.action()
            end
            drawGUI()
            return
        end
    end
end

-- ============================================
-- Terminal Commands
-- ============================================
local function printHelp()
    print("=== ChunkMiner Server Commands ===")
    print("start         - Start all turtles")
    print("stop          - Stop all turtles")
    print("recall        - Recall all turtles home")
    print("resume        - Resume halted turtles")
    print("ping          - Ping all turtles")
    print("status        - Show all turtle status")
    print("chunk <x> <z> - Set chunk origin")
    print("start <n>     - Start turtle #n")
    print("stop <n>      - Stop turtle #n")
    print("recall <n>    - Recall turtle #n")
    print("help          - Show this help")
    print("quit          - Shutdown server")
end

local function printStatus()
    print("=== Turtle Status ===")
    for slot = 1, config.TURTLE_COUNT do
        local t = turtles[slot]
        if t then
            local age = math.floor(os.clock() - t.lastSeen)
            print(string.format("#%02d [%s] Fuel:%d Blocks:%d %s",
                slot, t.status, t.fuel, t.blocksMinied,
                age > 10 and "(stale " .. age .. "s)" or ""))
        else
            print(string.format("#%02d [offline]", slot))
        end
    end
end

local function handleCommand(input)
    local parts = {}
    for word in input:gmatch("%S+") do
        table.insert(parts, word)
    end

    local cmd = parts[1]
    if not cmd then return end
    cmd = cmd:lower()

    if cmd == "start" then
        if parts[2] then
            startSingle(tonumber(parts[2]))
        else
            startMining()
        end
    elseif cmd == "stop" then
        if parts[2] then
            stopSingle(tonumber(parts[2]))
        else
            stopMining()
        end
    elseif cmd == "recall" then
        if parts[2] then
            recallSingle(tonumber(parts[2]))
        else
            recallAll()
        end
    elseif cmd == "resume" then
        resumeAll()
    elseif cmd == "ping" then
        pingAll()
    elseif cmd == "status" then
        printStatus()
    elseif cmd == "chunk" and parts[2] and parts[3] then
        chunkOrigin.x = tonumber(parts[2]) or 0
        chunkOrigin.z = tonumber(parts[3]) or 0
        print("Chunk origin set to " .. chunkOrigin.x .. ", " .. chunkOrigin.z)
        -- Re-assign mine areas
        for slot = 1, config.TURTLE_COUNT do
            if turtles[slot] then
                sendToTurtle(slot, {
                    type = "assign",
                    slot = slot,
                    homePos = getHomePos(slot),
                    mineStart = getMineStart(slot),
                })
            end
        end
    elseif cmd == "help" then
        printHelp()
    elseif cmd == "quit" or cmd == "exit" then
        serverRunning = false
    else
        print("Unknown command. Type 'help' for commands.")
    end

    drawGUI()
end

-- ============================================
-- Main Loops
-- ============================================
local function networkLoop()
    while serverRunning do
        local senderID, msg = rednet.receive(config.PROTOCOL, 1)
        if senderID and type(msg) == "table" then
            if msg.type == "register" then
                handleRegistration(senderID, msg)
            elseif msg.type == "status" then
                handleStatus(senderID, msg)
            end
        end
    end
end

local function guiLoop()
    while serverRunning do
        drawGUI()
        sleep(1)
    end
end

local function touchLoop()
    if not monitor then return end
    while serverRunning do
        local event, side, x, y = os.pullEvent("monitor_touch")
        handleTouch(x, y)
    end
end

local function terminalLoop()
    while serverRunning do
        write("> ")
        local input = read()
        if input then
            handleCommand(input)
        end
    end
end

local function staleCheckLoop()
    while serverRunning do
        sleep(15)
        -- Mark turtles as offline if not heard from in 30 seconds
        local now = os.clock()
        for slot = 1, config.TURTLE_COUNT do
            if turtles[slot] and (now - turtles[slot].lastSeen) > 30 then
                if turtles[slot].status ~= "offline" and turtles[slot].status ~= "done" then
                    turtles[slot].status = "offline"
                end
            end
        end
    end
end

-- ============================================
-- Entry Point
-- ============================================
print("========================================")
print("  ChunkMiner Server v1.0")
print("  Waiting for turtles to connect...")
print("  Type 'help' for commands.")
print("========================================")
print("")

if monitor then
    print("Monitor detected. GUI active.")
else
    print("No monitor. Terminal-only mode.")
end

drawGUI()

parallel.waitForAny(
    networkLoop,
    guiLoop,
    touchLoop,
    terminalLoop,
    staleCheckLoop
)

print("Server shutdown.")
rednet.close()

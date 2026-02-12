-- ============================================
-- ChunkMiner - Turtle Client
-- ============================================
-- Each turtle mines a 4x4 section of a chunk
-- Communicates with the central server via Rednet

local config = require("config")

-- ============================================
-- State
-- ============================================
local state = {
    id = os.getComputerID(),
    label = os.getComputerLabel() or ("Turtle-" .. os.getComputerID()),
    assignedSlot = nil,   -- 1-16, assigned by server
    status = "idle",      -- idle, mining, returning, refueling, dumping, error, done, halted
    position = { x = 0, y = 0, z = 0 },
    facing = 0,           -- 0=north(-z), 1=east(+x), 2=south(+z), 3=west(-x)
    fuel = turtle.getFuelLevel(),
    blocksMinied = 0,
    layersDone = 0,
    totalLayers = 0,
    inventoryUsed = 0,
    errorMsg = "",
    serverID = nil,
    homePos = nil,
    mineStart = nil,      -- Starting position for this turtle's section
    currentLayer = 0,
    running = false,
}

-- ============================================
-- Blacklist lookup table
-- ============================================
local blacklist = {}
for _, name in ipairs(config.BLACKLIST) do
    blacklist[name] = true
end

-- ============================================
-- Modem Setup
-- ============================================
local modem = peripheral.find("modem")
if not modem then
    error("No modem found! Attach a wireless modem.")
end
rednet.open(peripheral.getName(modem))

-- ============================================
-- Movement (tracked)
-- ============================================
local function forward()
    local tries = 0
    while not turtle.forward() do
        turtle.dig()
        turtle.attack()
        tries = tries + 1
        if tries > 30 then return false end
    end
    local dx = ({ [0] = 0, [1] = 1, [2] = 0, [3] = -1 })[state.facing]
    local dz = ({ [0] = -1, [1] = 0, [2] = 1, [3] = 0 })[state.facing]
    state.position.x = state.position.x + dx
    state.position.z = state.position.z + dz
    return true
end

local function back()
    if turtle.back() then
        local dx = ({ [0] = 0, [1] = -1, [2] = 0, [3] = 1 })[state.facing]
        local dz = ({ [0] = 1, [1] = 0, [2] = -1, [3] = 0 })[state.facing]
        state.position.x = state.position.x + dx
        state.position.z = state.position.z + dz
        return true
    end
    return false
end

local function up()
    local tries = 0
    while not turtle.up() do
        turtle.digUp()
        turtle.attackUp()
        tries = tries + 1
        if tries > 30 then return false end
    end
    state.position.y = state.position.y + 1
    return true
end

local function down()
    local tries = 0
    while not turtle.down() do
        turtle.digDown()
        turtle.attackDown()
        tries = tries + 1
        if tries > 30 then return false end
    end
    state.position.y = state.position.y - 1
    return true
end

local function turnLeft()
    turtle.turnLeft()
    state.facing = (state.facing - 1) % 4
end

local function turnRight()
    turtle.turnRight()
    state.facing = (state.facing + 1) % 4
end

local function turnTo(dir)
    while state.facing ~= dir do
        turnRight()
    end
end

-- ============================================
-- Navigation
-- ============================================
local function goToY(targetY)
    while state.position.y < targetY do
        if not up() then return false end
    end
    while state.position.y > targetY do
        if not down() then return false end
    end
    return true
end

local function goToXZ(targetX, targetZ)
    -- Move X first
    if state.position.x < targetX then
        turnTo(1) -- east (+x)
        while state.position.x < targetX do
            if not forward() then return false end
        end
    elseif state.position.x > targetX then
        turnTo(3) -- west (-x)
        while state.position.x > targetX do
            if not forward() then return false end
        end
    end
    -- Then Z
    if state.position.z < targetZ then
        turnTo(2) -- south (+z)
        while state.position.z < targetZ do
            if not forward() then return false end
        end
    elseif state.position.z > targetZ then
        turnTo(0) -- north (-z)
        while state.position.z > targetZ do
            if not forward() then return false end
        end
    end
    return true
end

local function goTo(x, y, z)
    -- Go up first to avoid obstacles, then XZ, then Y
    if y > state.position.y then
        goToY(y)
        goToXZ(x, z)
    else
        goToXZ(x, z)
        goToY(y)
    end
end

local function goHome()
    if state.homePos then
        goTo(state.homePos.x, state.homePos.y + 1, state.homePos.z)
        goToY(state.homePos.y)
    end
end

-- ============================================
-- Fuel Management
-- ============================================
local function checkFuel()
    state.fuel = turtle.getFuelLevel()
    return state.fuel
end

local function refuel()
    state.status = "refueling"
    sendStatus()

    -- Try to refuel from any slot
    for slot = 1, 16 do
        turtle.select(slot)
        if turtle.refuel(0) then  -- test if item is fuel
            turtle.refuel()       -- refuel all of it
        end
    end
    turtle.select(1)
    checkFuel()

    -- If still low, go home to refuel from chest
    if state.fuel < config.FUEL_THRESHOLD then
        local prevPos = { x = state.position.x, y = state.position.y, z = state.position.z }
        goHome()
        -- Try to suck fuel from chest below
        turnTo(0)
        for slot = 1, 16 do
            if turtle.getItemCount(slot) == 0 then
                turtle.select(slot)
                turtle.suckDown(64)
                if turtle.refuel(0) then
                    turtle.refuel()
                end
            end
        end
        turtle.select(1)
        checkFuel()
    end
end

local function needsFuel()
    checkFuel()
    return state.fuel < config.FUEL_THRESHOLD
end

-- ============================================
-- Inventory Management
-- ============================================
local function getInventoryUsed()
    local count = 0
    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            count = count + 1
        end
    end
    state.inventoryUsed = count
    return count
end

local function isInventoryFull()
    return getInventoryUsed() >= config.INVENTORY_THRESHOLD
end

local function dropBlacklisted()
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail and blacklist[detail.name] then
            turtle.select(slot)
            turtle.drop()
        end
    end
    turtle.select(1)
end

local function dumpInventory()
    state.status = "dumping"
    sendStatus()

    local prevPos = { x = state.position.x, y = state.position.y, z = state.position.z }
    local prevLayer = state.currentLayer

    goHome()

    -- Face the chest (assume chest is in front at home facing north)
    turnTo(0)

    -- Drop all items except fuel
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail then
            turtle.select(slot)
            -- Keep fuel items
            if not turtle.refuel(0) then
                turtle.drop()
            end
        end
    end
    turtle.select(1)
    getInventoryUsed()

    -- Return to mining position
    goTo(prevPos.x, prevPos.y, prevPos.z)
    state.currentLayer = prevLayer
end

-- ============================================
-- Mining Logic
-- ============================================
local function shouldKeep(inspectResult)
    if not inspectResult then return false end
    return not blacklist[inspectResult.name]
end

local function mineForward()
    local success, data = turtle.inspect()
    if success then
        if shouldKeep(data) then
            turtle.dig()
            state.blocksMinied = state.blocksMinied + 1
        else
            turtle.dig()  -- Dig anyway to move, but don't count
        end
    end
end

local function mineUp()
    local success, data = turtle.inspectUp()
    if success then
        turtle.digUp()
        state.blocksMinied = state.blocksMinied + 1
    end
end

local function mineDown()
    local success, data = turtle.inspectDown()
    if success then
        turtle.digDown()
        state.blocksMinied = state.blocksMinied + 1
    end
end

local function mineLayer(y)
    -- Mine a 4x4 area at height y
    -- Serpentine/zigzag pattern
    state.currentLayer = y

    local startX = state.mineStart.x
    local startZ = state.mineStart.z

    -- Go to the starting corner of this layer
    goTo(startX, y, startZ)

    -- Face east (+x) to start
    turnTo(1)

    for row = 0, config.SECTION_DEPTH - 1 do
        local z = startZ + row

        if row > 0 then
            -- Move to next row
            turnTo(2) -- south
            forward()
            -- Alternate direction
            if row % 2 == 0 then
                turnTo(1) -- east
            else
                turnTo(3) -- west
            end
        end

        -- Mine along the row
        for col = 1, config.SECTION_WIDTH - 1 do
            -- Dig above and below as we go
            mineUp()
            mineDown()

            -- Check fuel and inventory
            if needsFuel() then refuel() end
            if isInventoryFull() then
                dropBlacklisted()
                if isInventoryFull() then
                    dumpInventory()
                    -- Return to position in this layer
                    goTo(state.position.x, y, state.position.z)
                end
            end

            mineForward()
            forward()

            -- Pause check
            if not state.running then return false end
        end

        -- Mine above and below at end of row
        mineUp()
        mineDown()
    end

    state.layersDone = state.layersDone + 1
    return true
end

local function mineSection()
    state.status = "mining"
    state.blocksMinied = 0
    state.layersDone = 0

    local startY = config.START_Y
    local endY = config.MIN_Y
    state.totalLayers = math.abs(startY - endY)

    -- Mine layer by layer going down
    -- We mine 3 layers at a time (dig, digUp, digDown covers 3 blocks)
    local y = startY
    while y >= endY do
        if not state.running then
            state.status = "halted"
            sendStatus()
            return
        end

        sendStatus()

        if not mineLayer(y) then
            if not state.running then
                state.status = "halted"
                sendStatus()
                return
            end
        end

        y = y - 3  -- Move down 3 blocks (we mine up/down too)
    end

    -- Done mining, dump remaining inventory
    state.status = "returning"
    sendStatus()
    dumpInventory()

    state.status = "done"
    sendStatus()
end

-- ============================================
-- Server Communication
-- ============================================
function sendStatus()
    checkFuel()
    getInventoryUsed()

    local msg = {
        type = "status",
        id = state.id,
        label = state.label,
        slot = state.assignedSlot,
        status = state.status,
        position = state.position,
        facing = state.facing,
        fuel = state.fuel,
        blocksMinied = state.blocksMinied,
        layersDone = state.layersDone,
        totalLayers = state.totalLayers,
        currentLayer = state.currentLayer,
        inventoryUsed = state.inventoryUsed,
        errorMsg = state.errorMsg,
    }

    if state.serverID then
        rednet.send(state.serverID, msg, config.PROTOCOL)
    end
end

local function handleMessage(senderID, msg)
    if type(msg) ~= "table" then return end

    if msg.type == "assign" then
        -- Server assigns us a slot and mining area
        state.serverID = senderID
        state.assignedSlot = msg.slot
        state.homePos = msg.homePos
        state.mineStart = msg.mineStart
        state.position = msg.startPos or state.position
        state.facing = msg.facing or 0
        os.setComputerLabel("Miner-" .. msg.slot)
        state.label = "Miner-" .. msg.slot
        print("Assigned slot " .. msg.slot)
        print("Mining area: " .. state.mineStart.x .. "," .. state.mineStart.z)
        sendStatus()

    elseif msg.type == "start" then
        if state.assignedSlot then
            state.running = true
            print("Starting mining!")
            mineSection()
        end

    elseif msg.type == "stop" then
        state.running = false
        state.status = "halted"
        print("Stopped by server.")
        sendStatus()

    elseif msg.type == "recall" then
        state.running = false
        state.status = "returning"
        sendStatus()
        dumpInventory()
        goHome()
        state.status = "idle"
        sendStatus()

    elseif msg.type == "ping" then
        sendStatus()

    elseif msg.type == "config_update" then
        -- Update config values from server
        if msg.blacklist then
            blacklist = {}
            for _, name in ipairs(msg.blacklist) do
                blacklist[name] = true
            end
        end
        if msg.min_y then config.MIN_Y = msg.min_y end
        if msg.start_y then config.START_Y = msg.start_y end
        sendStatus()

    elseif msg.type == "resume" then
        if state.assignedSlot and state.status == "halted" then
            state.running = true
            state.status = "mining"
            print("Resuming mining!")
            mineSection()
        end
    end
end

-- ============================================
-- Main Loop
-- ============================================
local function registerWithServer()
    print("ChunkMiner Turtle Client v1.0")
    print("ID: " .. state.id)
    print("Searching for server...")

    -- Broadcast registration
    local msg = {
        type = "register",
        id = state.id,
        label = state.label,
        fuel = turtle.getFuelLevel(),
    }

    -- Try to find server
    while not state.serverID do
        rednet.broadcast(msg, config.PROTOCOL)
        local senderID, reply = rednet.receive(config.PROTOCOL, 5)
        if senderID and type(reply) == "table" and reply.type == "assign" then
            handleMessage(senderID, reply)
        end
    end

    print("Connected to server " .. state.serverID)
end

local function statusLoop()
    while true do
        sendStatus()
        sleep(config.STATUS_INTERVAL)
    end
end

local function listenLoop()
    while true do
        local senderID, msg = rednet.receive(config.PROTOCOL)
        if senderID == state.serverID then
            handleMessage(senderID, msg)
        end
    end
end

-- Entry point
registerWithServer()
parallel.waitForAny(listenLoop, statusLoop)

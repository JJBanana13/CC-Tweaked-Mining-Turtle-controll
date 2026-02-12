-- ATM10 turtle miner for chunk jobs, unloading to general chest and fueling from fuel chest.
-- Place as startup on each Advanced Mining Turtle.

local PROTOCOL = "atm10_minefleet"
local CFG_PATH = "miner_config"

local cfg = {
  unloadSide = "front", -- side of general chest when at home
  fuelSide = "left",    -- side of fuel chest when at home
  minFuel = 2000,
  fuelItemName = nil,    -- optional exact item name
}

local direction = 0 -- 0 north, 1 east, 2 south, 3 west
local position = { x = 0, y = 0, z = 0 }
local activeChunk = nil

local function loadConfig()
  if not fs.exists(CFG_PATH) then return end
  local f = fs.open(CFG_PATH, "r")
  local raw = f.readAll()
  f.close()
  local loaded = textutils.unserialize(raw)
  if loaded then
    for k, v in pairs(loaded) do cfg[k] = v end
  end
end

local function saveConfig()
  local f = fs.open(CFG_PATH, "w")
  f.write(textutils.serialize(cfg))
  f.close()
end

local function findModem()
  for _, side in ipairs(rs.getSides()) do
    if peripheral.getType(side) == "modem" and peripheral.call(side, "isWireless") then
      return side
    end
  end
end

local function digForwardSafe()
  while turtle.detect() do
    turtle.dig()
    sleep(0.2)
  end
end

local function digDownSafe()
  while turtle.detectDown() do
    turtle.digDown()
    sleep(0.2)
  end
end

local function forward()
  digForwardSafe()
  while not turtle.forward() do
    turtle.attack()
    sleep(0.2)
    digForwardSafe()
  end
  if direction == 0 then position.z = position.z - 1
  elseif direction == 1 then position.x = position.x + 1
  elseif direction == 2 then position.z = position.z + 1
  else position.x = position.x - 1 end
end

local function up()
  while turtle.detectUp() do turtle.digUp() sleep(0.2) end
  while not turtle.up() do turtle.attackUp() sleep(0.2) end
  position.y = position.y + 1
end

local function down()
  digDownSafe()
  local attempts = 0
  while not turtle.down() do
    attempts = attempts + 1
    turtle.attackDown()
    sleep(0.2)
    digDownSafe()
    if attempts > 15 then return false end
  end
  position.y = position.y - 1
  return true
end

local function turnLeft()
  turtle.turnLeft()
  direction = (direction + 3) % 4
end

local function turnRight()
  turtle.turnRight()
  direction = (direction + 1) % 4
end

local function face(target)
  while direction ~= target do
    local diff = (target - direction) % 4
    if diff == 1 then turnRight() else turnLeft() end
  end
end

local function moveTo(x, y, z)
  while position.y < y do up() end
  while position.y > y do if not down() then break end end

  if position.x < x then face(1) while position.x < x do forward() end
  elseif position.x > x then face(3) while position.x > x do forward() end end

  if position.z < z then face(2) while position.z < z do forward() end
  elseif position.z > z then face(0) while position.z > z do forward() end end
end

local function selectFuelSlot()
  for i = 1, 16 do
    local detail = turtle.getItemDetail(i)
    if detail then
      if not cfg.fuelItemName or detail.name == cfg.fuelItemName then
        turtle.select(i)
        return true
      end
    end
  end
  return false
end

local function turnToSide(side)
  if side == "front" then return
  elseif side == "back" then turnRight() turnRight()
  elseif side == "left" then turnLeft()
  elseif side == "right" then turnRight() end
end

local function interactSide(side, fn)
  local before = direction
  turnToSide(side)
  fn()
  face(before)
end

local function unloadInventory()
  for i = 1, 16 do
    turtle.select(i)
    turtle.drop()
  end
end

local function refuelAtHome()
  if turtle.getFuelLevel() >= cfg.minFuel then return end
  interactSide(cfg.fuelSide, function()
    for i = 1, 16 do
      turtle.select(i)
      turtle.suck(64)
      turtle.refuel()
      if turtle.getFuelLevel() >= cfg.minFuel then break end
    end
  end)

  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and cfg.fuelItemName and d.name == cfg.fuelItemName then
      interactSide(cfg.fuelSide, function()
        turtle.select(i)
        turtle.drop()
      end)
    end
  end
end

local function homeService()
  interactSide(cfg.unloadSide, unloadInventory)
  refuelAtHome()
end

local function inventoryNearlyFull()
  local used = 0
  for i = 1, 16 do
    if turtle.getItemCount(i) > 0 then used = used + 1 end
  end
  return used >= 14
end

local function mineLayer()
  for row = 1, 16 do
    for col = 1, 15 do forward() end
    if row < 16 then
      if row % 2 == 1 then
        turnRight(); forward(); turnRight()
      else
        turnLeft(); forward(); turnLeft()
      end
    end
  end
end

local function resetLayerStart()
  if direction == 1 then
    turnRight(); turnRight(); for _ = 1, 15 do forward() end
  elseif direction == 3 then
    turnRight(); turnRight(); for _ = 1, 15 do forward() end
  end

  if direction == 2 then turnRight() end
  if direction == 1 then turnLeft() end
  if direction == 3 then turnRight(); turnRight() end
end

local function mineChunk(chunk)
  local sx, sz = chunk.x * 16, chunk.z * 16
  moveTo(sx, position.y, sz)
  face(1)

  while true do
    mineLayer()
    resetLayerStart()

    if inventoryNearlyFull() then
      local rx, ry, rz = position.x, position.y, position.z
      local rdir = direction
      moveTo(0, 0, 0)
      homeService()
      moveTo(rx, ry, rz)
      face(rdir)
    end

    if not down() then break end
  end
end

local function sendStatus(status, chunk)
  rednet.broadcast({
    type = "status",
    status = status,
    chunk = chunk,
    fuel = turtle.getFuelLevel(),
  }, PROTOCOL)
end

local function setup()
  loadConfig()
  local modem = findModem()
  if not modem then error("Kein Wireless Modem an Turtle gefunden") end
  if not rednet.isOpen(modem) then rednet.open(modem) end

  if gps then
    local x, y, z = gps.locate(2)
    if x then
      position = { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) }
    end
  end

  rednet.broadcast({ type = "hello", fuel = turtle.getFuelLevel(), label = os.getComputerLabel() }, PROTOCOL)
end

local function processJob(msg)
  activeChunk = msg.chunk
  sendStatus("working", activeChunk)

  local ok, err = pcall(function()
    mineChunk(activeChunk)
    moveTo(0, 0, 0)
    homeService()
  end)

  if ok then
    sendStatus("done", activeChunk)
  else
    sendStatus("error", activeChunk)
    print("Mining Error: " .. tostring(err))
  end

  activeChunk = nil
end

local function run()
  setup()
  while true do
    local sender, msg, protocol = rednet.receive(PROTOCOL, 2)
    if sender and type(msg) == "table" then
      if msg.type == "job" and msg.chunk then
        processJob(msg)
      elseif msg.type == "recall" then
        moveTo(0, 0, 0)
        homeService()
        sendStatus("idle", nil)
      end
    else
      sendStatus(activeChunk and "working" or "idle", activeChunk)
    end
  end
end

if ... == "config" then
  print("Konfiguration Miner Turtle")
  write("Unload side (front/back/left/right) [" .. cfg.unloadSide .. "]: ")
  local a = read()
  if a ~= "" then cfg.unloadSide = a end
  write("Fuel side (front/back/left/right) [" .. cfg.fuelSide .. "]: ")
  local b = read()
  if b ~= "" then cfg.fuelSide = b end
  write("Mindestfuel [" .. cfg.minFuel .. "]: ")
  local c = tonumber(read())
  if c then cfg.minFuel = c end
  write("Fuel item name (leer = alles) [" .. tostring(cfg.fuelItemName) .. "]: ")
  local d = read()
  cfg.fuelItemName = (d ~= "" and d or nil)
  saveConfig()
  print("Gespeichert in " .. CFG_PATH)
else
  run()
end

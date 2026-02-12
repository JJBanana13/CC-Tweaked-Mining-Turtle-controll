-- ATM10 Chunk Miner Turtle
-- Home coordinate is 0,0,0. Turtle returns home to unload/refuel.

local PROTOCOL = "atm10_chunkfleet"
local CFG_FILE = "miner_config"

local cfg = {
  unloadSide = "front",
  fuelSide = "left",
  minFuel = 3000,
  reserveFuel = 1000,
}

local pos = { x = 0, y = 0, z = 0 }
local dir = 0 -- 0=N,1=E,2=S,3=W
local activeChunk = nil

local function loadCfg()
  if not fs.exists(CFG_FILE) then return end
  local f = fs.open(CFG_FILE, "r")
  local raw = f.readAll()
  f.close()
  local t = textutils.unserialize(raw)
  if type(t) == "table" then
    for k, v in pairs(t) do cfg[k] = v end
  end
end

local function saveCfg()
  local f = fs.open(CFG_FILE, "w")
  f.write(textutils.serialize(cfg))
  f.close()
end

local function findWirelessModem()
  for _, side in ipairs(rs.getSides()) do
    if peripheral.getType(side) == "modem" and peripheral.call(side, "isWireless") then
      return side
    end
  end
end

local function tryGps()
  if gps then
    local x, y, z = gps.locate(2)
    if x then
      pos.x = math.floor(x + 0.5)
      pos.y = math.floor(y + 0.5)
      pos.z = math.floor(z + 0.5)
    end
  end
end

local function turnLeft()
  turtle.turnLeft()
  dir = (dir + 3) % 4
end
local function turnRight()
  turtle.turnRight()
  dir = (dir + 1) % 4
end
local function face(d)
  while dir ~= d do
    local diff = (d - dir) % 4
    if diff == 1 then turnRight() else turnLeft() end
  end
end

local function digForward()
  while turtle.detect() do turtle.dig(); sleep(0.15) end
end
local function digDown()
  while turtle.detectDown() do turtle.digDown(); sleep(0.15) end
end
local function digUp()
  while turtle.detectUp() do turtle.digUp(); sleep(0.15) end
end

local function forward()
  digForward()
  while not turtle.forward() do
    turtle.attack(); digForward(); sleep(0.15)
  end

  if dir == 0 then pos.z = pos.z - 1
  elseif dir == 1 then pos.x = pos.x + 1
  elseif dir == 2 then pos.z = pos.z + 1
  else pos.x = pos.x - 1 end
end

local function up()
  digUp()
  while not turtle.up() do turtle.attackUp(); digUp(); sleep(0.15) end
  pos.y = pos.y + 1
end

local function down(maxAttempts)
  maxAttempts = maxAttempts or 20
  digDown()
  local tries = 0
  while not turtle.down() do
    tries = tries + 1
    if tries >= maxAttempts then return false end
    turtle.attackDown(); digDown(); sleep(0.15)
  end
  pos.y = pos.y - 1
  return true
end

local function moveTo(x, y, z)
  while pos.y < y do up() end
  while pos.y > y do if not down() then return false end end

  if pos.x < x then face(1); while pos.x < x do forward() end
  elseif pos.x > x then face(3); while pos.x > x do forward() end end

  if pos.z < z then face(2); while pos.z < z do forward() end
  elseif pos.z > z then face(0); while pos.z > z do forward() end end

  return true
end

local function withSide(side, fn)
  local old = dir
  if side == "left" then turnLeft()
  elseif side == "right" then turnRight()
  elseif side == "back" then turnRight(); turnRight() end
  fn()
  face(old)
end

local function unloadAll()
  withSide(cfg.unloadSide, function()
    for i = 1, 16 do
      turtle.select(i)
      turtle.drop()
    end
  end)
end

local function fuelLevel()
  local f = turtle.getFuelLevel()
  if f == "unlimited" then return 9999999 end
  return f
end

local function refuelFromChest()
  if fuelLevel() >= cfg.minFuel then return end
  withSide(cfg.fuelSide, function()
    for _ = 1, 8 do
      for i = 1, 16 do
        turtle.select(i)
        turtle.suck(64)
        turtle.refuel()
        if fuelLevel() >= cfg.minFuel then return end
      end
    end
  end)
end

local function usedSlots()
  local n = 0
  for i = 1, 16 do if turtle.getItemCount(i) > 0 then n = n + 1 end end
  return n
end

local function sendStatus(state)
  rednet.broadcast({
    type = "status",
    status = state,
    fuel = fuelLevel(),
    chunk = activeChunk,
    pos = { x = pos.x, y = pos.y, z = pos.z },
  }, PROTOCOL)
end

local function serviceHome()
  unloadAll()
  refuelFromChest()
end

local function ensureFuelForTrip()
  if fuelLevel() > cfg.reserveFuel then return true end
  local ok = moveTo(0, 0, 0)
  if not ok then return false end
  serviceHome()
  return fuelLevel() > cfg.reserveFuel
end

local function mineOneLayer16()
  for row = 1, 16 do
    for _ = 1, 15 do forward() end
    if row < 16 then
      if row % 2 == 1 then
        turnRight(); forward(); turnRight()
      else
        turnLeft(); forward(); turnLeft()
      end
    end
  end
end

local function returnToLayerStart()
  turnRight(); turnRight()
  for _ = 1, 15 do forward() end
  if dir == 0 then
    turnRight(); for _ = 1, 15 do forward() end; turnRight()
  elseif dir == 2 then
    turnLeft(); for _ = 1, 15 do forward() end; turnLeft()
  end
  face(1)
end

local function mineChunk(cx, cz)
  activeChunk = { x = cx, z = cz }
  sendStatus("travel")

  local sx, sz = cx * 16, cz * 16
  if not ensureFuelForTrip() then error("Nicht genug Fuel") end
  if not moveTo(sx, pos.y, sz) then error("Kann Startchunk nicht erreichen") end
  face(1)

  sendStatus("working")
  while true do
    mineOneLayer16()
    returnToLayerStart()

    if usedSlots() >= 14 or fuelLevel() <= cfg.reserveFuel then
      local rx, ry, rz, rd = pos.x, pos.y, pos.z, dir
      sendStatus("service")
      if not moveTo(0, 0, 0) then error("Rueckkehr zu Home fehlgeschlagen") end
      serviceHome()
      if not moveTo(rx, ry, rz) then error("Rueckkehr zur Mine fehlgeschlagen") end
      face(rd)
      sendStatus("working")
    end

    if not down(25) then break end
  end

  sendStatus("return")
  if not moveTo(0, 0, 0) then error("Rueckkehr Home fehlgeschlagen") end
  serviceHome()
  sendStatus("done")
  activeChunk = nil
end

local function configure()
  print("=== Turtle Config ===")
  write("Unload side [" .. cfg.unloadSide .. "]: ")
  local a = read(); if a ~= "" then cfg.unloadSide = a end
  write("Fuel side [" .. cfg.fuelSide .. "]: ")
  local b = read(); if b ~= "" then cfg.fuelSide = b end
  write("Min Fuel [" .. cfg.minFuel .. "]: ")
  local c = tonumber(read()); if c then cfg.minFuel = c end
  write("Reserve Fuel [" .. cfg.reserveFuel .. "]: ")
  local d = tonumber(read()); if d then cfg.reserveFuel = d end
  saveCfg()
  print("Gespeichert: " .. CFG_FILE)
end

local function setup()
  loadCfg()
  local modem = findWirelessModem()
  if not modem then error("Wireless modem fehlt") end
  if not rednet.isOpen(modem) then rednet.open(modem) end
  tryGps()
  rednet.broadcast({ type = "hello", fuel = fuelLevel(), label = os.getComputerLabel(), pos = pos }, PROTOCOL)
end

local function run()
  setup()
  while true do
    local sender, msg, protocol = rednet.receive(PROTOCOL, 2)
    if sender and type(msg) == "table" then
      if msg.type == "job" and msg.chunk then
        local ok, err = pcall(function() mineChunk(msg.chunk.x, msg.chunk.z) end)
        if not ok then
          print("ERROR: " .. tostring(err))
          sendStatus("error")
          activeChunk = nil
        end
      elseif msg.type == "recall" then
        moveTo(0, 0, 0)
        serviceHome()
        activeChunk = nil
        sendStatus("idle")
      end
    else
      sendStatus(activeChunk and "working" or "idle")
    end
  end
end

if ... == "config" then
  configure()
else
  run()
end

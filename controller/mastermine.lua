-- MasterMine-inspired dispatcher for 16 advanced mining turtles (CC:Tweaked / ATM10)
-- Run on an Advanced Computer with a wireless modem (and optional monitor).

local PROTOCOL = "atm10_minefleet"
local CONFIG_PATH = "mastermine_config"

local state = {
  turtles = {},
  jobs = {},
  selected = { x = 0, z = 0 },
  origin = { x = 0, z = 0 },
  scale = 16,
  range = 6,
  cursor = 1,
  screen = term.current(),
}

local function saveConfig()
  local f = fs.open(CONFIG_PATH, "w")
  f.write(textutils.serialize({ origin = state.origin, range = state.range, scale = state.scale }))
  f.close()
end

local function loadConfig()
  if not fs.exists(CONFIG_PATH) then return end
  local f = fs.open(CONFIG_PATH, "r")
  local raw = f.readAll()
  f.close()
  local cfg = textutils.unserialize(raw)
  if cfg then
    state.origin = cfg.origin or state.origin
    state.range = cfg.range or state.range
    state.scale = cfg.scale or state.scale
  end
end

local function findModem()
  for _, side in ipairs(rs.getSides()) do
    if peripheral.getType(side) == "modem" and peripheral.call(side, "isWireless") then
      return side
    end
  end
end

local function setupComms()
  local modemSide = findModem()
  if not modemSide then
    error("Kein Wireless Modem gefunden")
  end
  if not rednet.isOpen(modemSide) then rednet.open(modemSide) end
end

local function tryAttachMonitor()
  for _, side in ipairs(rs.getSides()) do
    if peripheral.getType(side) == "monitor" then
      state.screen = peripheral.wrap(side)
      state.screen.setTextScale(0.5)
      return
    end
  end
end

local function drawLine(y, txt, fg, bg)
  local w = select(1, state.screen.getSize())
  state.screen.setCursorPos(1, y)
  state.screen.setTextColor(fg or colors.white)
  state.screen.setBackgroundColor(bg or colors.black)
  state.screen.clearLine()
  state.screen.write(txt:sub(1, w))
end

local function chunkKey(x, z)
  return x .. ":" .. z
end

local function countIdleTurtles()
  local count = 0
  for _, t in pairs(state.turtles) do
    if t.status == "idle" then count = count + 1 end
  end
  return count
end

local function drawUI()
  local w, h = state.screen.getSize()
  state.screen.setBackgroundColor(colors.black)
  state.screen.setTextColor(colors.white)
  state.screen.clear()

  drawLine(1, " MasterMine ATM10 - 16 Turtle Fleet", colors.black, colors.orange)
  drawLine(2, (" Origin Chunk: %d, %d | Idle: %d | Jobs: %d"):format(state.origin.x, state.origin.z, countIdleTurtles(), #state.jobs), colors.lightGray)
  drawLine(3, " Pfeile: Chunk waehlen | Enter: Job | R: Recall all | O: Set Origin", colors.gray)

  local mapTop = 5
  local sideInfoX = math.min(w - 22, state.range * 2 + 4)

  for dz = -state.range, state.range do
    local y = mapTop + dz + state.range
    local row = {}
    for dx = -state.range, state.range do
      local cx = state.origin.x + dx
      local cz = state.origin.z + dz
      local key = chunkKey(cx, cz)
      local symbol = "."
      local col = colors.gray

      if state.selected.x == cx and state.selected.z == cz then
        symbol = "[]"
        col = colors.yellow
      elseif state.jobs[key] then
        symbol = "##"
        col = colors.lime
      else
        for _, t in pairs(state.turtles) do
          if t.chunk and t.chunk.x == cx and t.chunk.z == cz and t.status ~= "idle" then
            symbol = "<>"
            col = colors.cyan
            break
          end
        end
      end

      table.insert(row, { symbol = symbol, color = col })
    end

    local xPos = 2
    for _, cell in ipairs(row) do
      state.screen.setCursorPos(xPos, y)
      state.screen.setTextColor(cell.color)
      state.screen.write(cell.symbol)
      xPos = xPos + 2
    end
  end

  drawLine(mapTop + state.range * 2 + 2, " Turtles:", colors.white)
  local i = 0
  for id, t in pairs(state.turtles) do
    i = i + 1
    if mapTop + state.range * 2 + 2 + i > h then break end
    local chunkTxt = t.chunk and (" @%d,%d"):format(t.chunk.x, t.chunk.z) or ""
    drawLine(mapTop + state.range * 2 + 2 + i, ("  #%d %-8s fuel:%d%s"):format(id, t.status or "unknown", t.fuel or 0, chunkTxt), colors.lightGray)
  end

  if sideInfoX > 1 then
    state.screen.setCursorPos(sideInfoX, 5)
    state.screen.setTextColor(colors.yellow)
    state.screen.write(("Selection: %d,%d"):format(state.selected.x, state.selected.z))
  end
end

local function sendJob(id, cx, cz)
  local msg = { type = "job", chunk = { x = cx, z = cz }, scale = state.scale }
  rednet.send(id, msg, PROTOCOL)
  local key = chunkKey(cx, cz)
  state.jobs[key] = { assignedTo = id, startedAt = os.epoch("utc") }
  state.turtles[id].status = "assigned"
  state.turtles[id].chunk = { x = cx, z = cz }
end

local function findIdleTurtle()
  for id, t in pairs(state.turtles) do
    if t.status == "idle" then return id end
  end
end

local function queueSelectedChunk()
  local id = findIdleTurtle()
  local cx, cz = state.selected.x, state.selected.z
  local key = chunkKey(cx, cz)
  if state.jobs[key] then return end
  if not id then
    state.jobs[key] = { queued = true }
    return
  end
  sendJob(id, cx, cz)
end

local function assignQueued()
  for key, job in pairs(state.jobs) do
    if job.queued then
      local id = findIdleTurtle()
      if not id then return end
      local x, z = key:match("(-?%d+):(-?%d+)")
      state.jobs[key] = nil
      sendJob(id, tonumber(x), tonumber(z))
    end
  end
end

local function handleMessage(sender, msg)
  if type(msg) ~= "table" or not msg.type then return end

  if msg.type == "hello" then
    state.turtles[sender] = state.turtles[sender] or {}
    state.turtles[sender].status = "idle"
    state.turtles[sender].fuel = msg.fuel or 0
    state.turtles[sender].label = msg.label
    rednet.send(sender, { type = "hello_ack" }, PROTOCOL)
  elseif msg.type == "status" then
    state.turtles[sender] = state.turtles[sender] or {}
    local t = state.turtles[sender]
    t.status = msg.status or t.status
    t.fuel = msg.fuel or t.fuel
    t.chunk = msg.chunk or t.chunk

    if msg.status == "done" and msg.chunk then
      local key = chunkKey(msg.chunk.x, msg.chunk.z)
      state.jobs[key] = nil
      t.status = "idle"
      t.chunk = nil
      assignQueued()
    elseif msg.status == "error" then
      t.status = "error"
    end
  end
end

local function recallAll()
  for id in pairs(state.turtles) do
    rednet.send(id, { type = "recall" }, PROTOCOL)
  end
end

local function onKey(code)
  if code == keys.left then
    state.selected.x = state.selected.x - 1
  elseif code == keys.right then
    state.selected.x = state.selected.x + 1
  elseif code == keys.up then
    state.selected.z = state.selected.z - 1
  elseif code == keys.down then
    state.selected.z = state.selected.z + 1
  elseif code == keys.enter then
    queueSelectedChunk()
  elseif code == keys.r then
    recallAll()
  elseif code == keys.o then
    state.origin.x = state.selected.x
    state.origin.z = state.selected.z
    saveConfig()
  end
end

local function onMonitorTouch(x, y)
  local mapTop = 5
  local relY = y - mapTop
  local relX = math.floor((x - 2) / 2)

  if relY >= 0 and relY <= state.range * 2 and relX >= 0 and relX <= state.range * 2 then
    local dx = relX - state.range
    local dz = relY - state.range
    state.selected.x = state.origin.x + dx
    state.selected.z = state.origin.z + dz
    queueSelectedChunk()
  end
end

local function main()
  loadConfig()
  setupComms()
  tryAttachMonitor()

  while true do
    drawUI()
    local e, p1, p2, p3 = os.pullEvent()
    if e == "rednet_message" then
      local sender, msg, protocol = p1, p2, p3
      if protocol == PROTOCOL then handleMessage(sender, msg) end
    elseif e == "key" then
      onKey(p1)
    elseif e == "monitor_touch" then
      onMonitorTouch(p2, p3)
    end
  end
end

main()

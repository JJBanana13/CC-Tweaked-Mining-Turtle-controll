-- ATM10 Chunk Mining Controller (MasterMine-style)
-- Features:
--   * Chunk map with pan/zoom
--   * mined/queued/active visualization
--   * turtle positions and status panel
--   * persistent world state (origin, mined chunks, jobs)

local PROTOCOL = "atm10_chunkfleet"
local STATE_FILE = "controller_state"
local HEARTBEAT_TIMEOUT = 20
local JOB_TIMEOUT = 15 * 60

local app = {
  screen = term.current(),
  world = {
    origin = { x = 0, z = 0 },
    mined = {},      -- ["x:z"] = true
    jobs = {},       -- ["x:z"] = {queued=true} or {assignedTo=id,start=...}
  },
  turtles = {},      -- [id] = {status,fuel,chunk={x,z},pos={x,y,z},label,lastSeen}
  ui = {
    cursor = { x = 0, z = 0 },
    center = { x = 0, z = 0 },
    zoom = 1,        -- 1 = 1 chunk/cell, 2 = 2x2 chunks/cell
    mapRadius = 9,
    selectedPanelIndex = 1,
  },
}

local function keyFor(x, z)
  return tostring(x) .. ":" .. tostring(z)
end

local function parseKey(k)
  local sx, sz = k:match("(-?%d+):(-?%d+)")
  return tonumber(sx), tonumber(sz)
end

local function saveState()
  local f = fs.open(STATE_FILE, "w")
  f.write(textutils.serialize(app.world))
  f.close()
end

local function loadState()
  if not fs.exists(STATE_FILE) then return end
  local f = fs.open(STATE_FILE, "r")
  local raw = f.readAll()
  f.close()
  local data = textutils.unserialize(raw)
  if type(data) == "table" then
    app.world.origin = data.origin or app.world.origin
    app.world.mined = data.mined or {}
    app.world.jobs = data.jobs or {}
    app.ui.cursor.x = app.world.origin.x
    app.ui.cursor.z = app.world.origin.z
    app.ui.center.x = app.world.origin.x
    app.ui.center.z = app.world.origin.z
  end
end

local function findWirelessModem()
  for _, side in ipairs(rs.getSides()) do
    if peripheral.getType(side) == "modem" and peripheral.call(side, "isWireless") then
      return side
    end
  end
end

local function setupNetwork()
  local side = findWirelessModem()
  if not side then error("Wireless Modem nicht gefunden") end
  if not rednet.isOpen(side) then rednet.open(side) end
end

local function attachMonitorIfPresent()
  for _, side in ipairs(rs.getSides()) do
    if peripheral.getType(side) == "monitor" then
      app.screen = peripheral.wrap(side)
      app.screen.setTextScale(0.5)
      return true
    end
  end
  return false
end

local function clear()
  app.screen.setBackgroundColor(colors.black)
  app.screen.setTextColor(colors.white)
  app.screen.clear()
  app.screen.setCursorPos(1, 1)
end

local function line(y, text, fg, bg)
  local w = select(1, app.screen.getSize())
  app.screen.setCursorPos(1, y)
  app.screen.setTextColor(fg or colors.white)
  app.screen.setBackgroundColor(bg or colors.black)
  app.screen.clearLine()
  app.screen.write(text:sub(1, w))
end

local function countJobs()
  local n = 0
  for _ in pairs(app.world.jobs) do n = n + 1 end
  return n
end

local function countMined()
  local n = 0
  for _ in pairs(app.world.mined) do n = n + 1 end
  return n
end

local function countIdle()
  local n = 0
  for _, t in pairs(app.turtles) do
    if t.status == "idle" then n = n + 1 end
  end
  return n
end

local function turtleByChunk(cx, cz)
  for id, t in pairs(app.turtles) do
    local tcx, tcz
    if t.pos then
      tcx = math.floor(t.pos.x / 16)
      tcz = math.floor(t.pos.z / 16)
    elseif t.chunk then
      tcx = t.chunk.x
      tcz = t.chunk.z
    end

    if tcx == cx and tcz == cz then
      return id, t
    end
  end
end

local function drawMap(startY, mapW, mapH)
  local radiusX = math.floor(mapW / 2)
  local radiusZ = math.floor(mapH / 2)
  local step = app.ui.zoom

  for row = -radiusZ, radiusZ do
    for col = -radiusX, radiusX do
      local cx = app.ui.center.x + col * step
      local cz = app.ui.center.z + row * step
      local key = keyFor(cx, cz)

      local ch = "."
      local colr = colors.gray
      local bgr = colors.black

      if app.world.mined[key] then
        ch = "M"
        colr = colors.lime
      end

      if app.world.jobs[key] then
        ch = "Q"
        colr = colors.orange
      end

      local tid = turtleByChunk(cx, cz)
      if tid then
        ch = "T"
        colr = colors.cyan
      end

      if cx == app.world.origin.x and cz == app.world.origin.z then
        bgr = colors.brown
      end

      if cx == app.ui.cursor.x and cz == app.ui.cursor.z then
        bgr = colors.yellow
        if ch == "." then colr = colors.black end
      end

      local x = 2 + col + radiusX
      local y = startY + row + radiusZ
      if x >= 1 and y >= 1 then
        app.screen.setCursorPos(x, y)
        app.screen.setTextColor(colr)
        app.screen.setBackgroundColor(bgr)
        app.screen.write(ch)
      end
    end
  end

  app.screen.setBackgroundColor(colors.black)
end

local function drawTurtlePanel(x, y, h)
  local ids = {}
  for id in pairs(app.turtles) do table.insert(ids, id) end
  table.sort(ids)

  app.screen.setCursorPos(x, y)
  app.screen.setTextColor(colors.white)
  app.screen.write("Turtles")

  local lineNo = 1
  for _, id in ipairs(ids) do
    if lineNo >= h then break end
    local t = app.turtles[id]
    local txt = ("#%d %-7s F:%d"):format(id, t.status or "?", t.fuel or 0)
    if t.chunk then txt = txt .. (" C:%d,%d"):format(t.chunk.x, t.chunk.z) end
    if t.pos then txt = txt .. (" P:%d,%d,%d"):format(t.pos.x, t.pos.y, t.pos.z) end
    app.screen.setCursorPos(x, y + lineNo)
    app.screen.setTextColor(colors.lightGray)
    app.screen.write(txt)
    lineNo = lineNo + 1
  end
end

local function drawUI()
  clear()
  local w, h = app.screen.getSize()

  line(1, " ATM10 ChunkFleet | MasterMine-Style", colors.black, colors.orange)
  line(2, (" Origin %d,%d | Cursor %d,%d | Zoom x%d | Idle %d | Jobs %d | Mined %d")
    :format(app.world.origin.x, app.world.origin.z, app.ui.cursor.x, app.ui.cursor.z, app.ui.zoom, countIdle(), countJobs(), countMined()), colors.lightGray)
  line(3, " Arrows: Cursor | Enter: Queue | WASD: Pan | +/-: Zoom | M: mark mined | O: set origin | R: recall")

  local panelW = math.max(26, math.floor(w * 0.35))
  local mapW = w - panelW - 3
  local mapH = h - 6

  drawMap(5, mapW, mapH)
  drawTurtlePanel(mapW + 4, 5, h - 5)

  line(h, " Legende: . unbekannt  M mined  Q queued/aktiv  T turtle  braun=home  gelb=cursor", colors.gray)
end

local function idleTurtleId()
  for id, t in pairs(app.turtles) do
    if t.status == "idle" then return id end
  end
end

local function sendJob(tid, cx, cz)
  rednet.send(tid, { type = "job", chunk = { x = cx, z = cz } }, PROTOCOL)
  app.world.jobs[keyFor(cx, cz)] = { assignedTo = tid, startedAt = os.epoch("utc") }
  app.turtles[tid].status = "assigned"
  app.turtles[tid].chunk = { x = cx, z = cz }
  saveState()
end

local function queueChunk(cx, cz)
  local k = keyFor(cx, cz)
  if app.world.mined[k] or app.world.jobs[k] then return end

  local tid = idleTurtleId()
  if tid then
    sendJob(tid, cx, cz)
  else
    app.world.jobs[k] = { queued = true }
    saveState()
  end
end

local function assignQueuedJobs()
  for k, v in pairs(app.world.jobs) do
    if v.queued then
      local tid = idleTurtleId()
      if not tid then return end
      local x, z = parseKey(k)
      app.world.jobs[k] = nil
      sendJob(tid, x, z)
    end
  end
end

local function recallAll()
  for id in pairs(app.turtles) do
    rednet.send(id, { type = "recall" }, PROTOCOL)
  end
end

local function handleNet(sender, msg)
  if type(msg) ~= "table" or type(msg.type) ~= "string" then return end

  if msg.type == "hello" then
    app.turtles[sender] = app.turtles[sender] or {}
    local t = app.turtles[sender]
    t.status = "idle"
    t.fuel = msg.fuel or t.fuel or 0
    t.label = msg.label or t.label
    t.pos = msg.pos or t.pos
    t.lastSeen = os.clock()
    rednet.send(sender, { type = "hello_ack" }, PROTOCOL)
    return
  end

  if msg.type == "status" then
    app.turtles[sender] = app.turtles[sender] or {}
    local t = app.turtles[sender]
    t.status = msg.status or t.status
    t.fuel = msg.fuel or t.fuel
    t.chunk = msg.chunk
    t.pos = msg.pos or t.pos
    t.lastSeen = os.clock()

    if msg.status == "done" and msg.chunk then
      local k = keyFor(msg.chunk.x, msg.chunk.z)
      app.world.jobs[k] = nil
      app.world.mined[k] = true
      t.status = "idle"
      t.chunk = nil
      saveState()
      assignQueuedJobs()
    elseif msg.status == "error" and msg.chunk then
      local k = keyFor(msg.chunk.x, msg.chunk.z)
      app.world.jobs[k] = { queued = true }
      t.status = "idle"
      t.chunk = nil
      saveState()
      assignQueuedJobs()
    elseif msg.status == "idle" then
      t.chunk = nil
      assignQueuedJobs()
    end
  end
end

local function queueChunkByKey(k)
  local x, z = parseKey(k)
  if x and z then
    app.world.jobs[k] = { queued = true }
  end
end

local function recoverStaleTurtlesAndJobs(now)
  now = now or os.clock()
  local dirty = false

  for id, t in pairs(app.turtles) do
    if t.lastSeen and (now - t.lastSeen) > HEARTBEAT_TIMEOUT then
      if t.chunk then
        local k = keyFor(t.chunk.x, t.chunk.z)
        if app.world.jobs[k] then
          queueChunkByKey(k)
          dirty = true
        end
      end
      t.status = "offline"
      t.chunk = nil
    end
  end

  for k, job in pairs(app.world.jobs) do
    if job.assignedTo and job.startedAt then
      local age = (os.epoch("utc") - job.startedAt) / 1000
      if age > JOB_TIMEOUT then
        app.world.jobs[k] = { queued = true }
        dirty = true
      end
    end
  end

  if dirty then
    saveState()
  end
end

local function moveCursor(dx, dz)
  app.ui.cursor.x = app.ui.cursor.x + dx * app.ui.zoom
  app.ui.cursor.z = app.ui.cursor.z + dz * app.ui.zoom
end

local function pan(dx, dz)
  app.ui.center.x = app.ui.center.x + dx * app.ui.zoom
  app.ui.center.z = app.ui.center.z + dz * app.ui.zoom
end

local function onKey(k)
  if k == keys.left then moveCursor(-1, 0)
  elseif k == keys.right then moveCursor(1, 0)
  elseif k == keys.up then moveCursor(0, -1)
  elseif k == keys.down then moveCursor(0, 1)
  elseif k == keys.enter then queueChunk(app.ui.cursor.x, app.ui.cursor.z)
  elseif k == keys.w then pan(0, -1)
  elseif k == keys.s then pan(0, 1)
  elseif k == keys.a then pan(-1, 0)
  elseif k == keys.d then pan(1, 0)
  elseif k == keys.r then recallAll()
  elseif k == keys.o then
    app.world.origin.x = app.ui.cursor.x
    app.world.origin.z = app.ui.cursor.z
    saveState()
  elseif k == keys.m then
    app.world.mined[keyFor(app.ui.cursor.x, app.ui.cursor.z)] = true
    saveState()
  elseif k == keys.minus then
    app.ui.zoom = math.min(8, app.ui.zoom + 1)
  elseif k == keys.equals then
    app.ui.zoom = math.max(1, app.ui.zoom - 1)
  end
end

local function onMonitorTouch(x, y)
  local w, h = app.screen.getSize()
  local panelW = math.max(26, math.floor(w * 0.35))
  local mapW = w - panelW - 3
  local mapH = h - 6
  if y < 5 or y >= (5 + mapH) then return end
  if x < 2 or x >= (2 + mapW) then return end

  local radiusX = math.floor(mapW / 2)
  local radiusZ = math.floor(mapH / 2)
  local col = x - 2 - radiusX
  local row = y - 5 - radiusZ
  app.ui.cursor.x = app.ui.center.x + col * app.ui.zoom
  app.ui.cursor.z = app.ui.center.z + row * app.ui.zoom
  queueChunk(app.ui.cursor.x, app.ui.cursor.z)
end

local function boot()
  loadState()
  setupNetwork()
  attachMonitorIfPresent()

  while true do
    recoverStaleTurtlesAndJobs(os.clock())
    assignQueuedJobs()
    drawUI()
    local ev, p1, p2, p3 = os.pullEvent()
    if ev == "rednet_message" then
      local sender, msg, protocol = p1, p2, p3
      if protocol == PROTOCOL then
        handleNet(sender, msg)
      end
    elseif ev == "key" then
      onKey(p1)
    elseif ev == "monitor_touch" then
      onMonitorTouch(p2, p3)
    end
  end
end

boot()

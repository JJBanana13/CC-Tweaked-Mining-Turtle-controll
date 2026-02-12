-- Simple installer for ATM10 ChunkFleet (controller + turtle)
-- Usage:
--   paste this file and run: install
-- It copies local files into startup scripts.

local function copyFile(src, dst)
  if not fs.exists(src) then
    return false, "Missing source: " .. src
  end
  local inF = fs.open(src, "r")
  local data = inF.readAll()
  inF.close()

  local outF = fs.open(dst, "w")
  outF.write(data)
  outF.close()
  return true
end

local function ask(prompt, default)
  write(prompt .. (default and (" [" .. default .. "]") or "") .. ": ")
  local v = read()
  if v == "" then return default end
  return v
end

print("=== ATM10 ChunkFleet Installer ===")
print("1) Controller installieren")
print("2) Turtle installieren")
local choice = ask("Auswahl", "1")

if choice == "1" then
  local src = ask("Controller Datei", "controller/mastermine.lua")
  local dst = ask("Ziel", "startup")
  local ok, err = copyFile(src, dst)
  if not ok then error(err) end
  print("Controller installiert -> " .. dst)
  print("Bitte Wireless Modem anschliessen und startup starten.")
elseif choice == "2" then
  local src = ask("Turtle Datei", "turtles/miner.lua")
  local dst = ask("Ziel", "startup")
  local ok, err = copyFile(src, dst)
  if not ok then error(err) end
  print("Turtle Miner installiert -> " .. dst)
  print("Danach: startup config")
else
  error("Ungueltige Auswahl")
end

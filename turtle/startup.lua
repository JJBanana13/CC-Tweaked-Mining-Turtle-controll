-- ============================================
-- Startup Script fuer Mining Turtles
-- Auf jede Turtle kopieren als "startup.lua"
-- ============================================

-- Pfad fuer require setzen
package.path = package.path .. ";/?.lua;/?/init.lua"

print("Mining Turtle startet...")
print("")

-- Turtle benennen falls noch nicht geschehen
if not os.getComputerLabel() then
    os.setComputerLabel("Miner_" .. os.getComputerID())
end

-- Miner laden und starten
local ok, err = pcall(function()
    local miner = require("turtle.chunk_miner")
    miner.run()
end)

if not ok then
    print("FEHLER: " .. tostring(err))
    print("Neustart in 10 Sekunden...")
    sleep(10)
    os.reboot()
end

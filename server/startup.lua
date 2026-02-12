-- ============================================
-- Startup Script fuer den Mining Server
-- Auf den Server-Computer kopieren als "startup.lua"
-- ============================================

-- Pfad fuer require setzen
package.path = package.path .. ";/?.lua;/?/init.lua"

print("Mining Control Server startet...")
print("")

-- Server laden und starten
local ok, err = pcall(function()
    local server = require("server.server")
    server.run()
end)

if not ok then
    print("FEHLER: " .. tostring(err))
    print("Neustart in 10 Sekunden...")
    sleep(10)
    os.reboot()
end

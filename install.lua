-- ============================================
-- Installer Script
-- Kopiert die Dateien auf Turtle oder Server
-- ============================================

local args = { ... }
local mode = args[1]

if not mode or (mode ~= "turtle" and mode ~= "server") then
    print("=== Mining System Installer ===")
    print("")
    print("Verwendung:")
    print("  install turtle   - Installiert auf einer Mining Turtle")
    print("  install server   - Installiert auf dem Server Computer")
    print("")
    print("Dateien werden von GitHub/Pastebin heruntergeladen.")
    return
end

-- Verzeichnisse erstellen
fs.makeDir("shared")
if mode == "turtle" then
    fs.makeDir("turtle")
elseif mode == "server" then
    fs.makeDir("server")
end

print("Installation als " .. mode .. " abgeschlossen!")
print("Bitte shared/config.lua anpassen (Basis-Position etc.)")
print("Dann: reboot")

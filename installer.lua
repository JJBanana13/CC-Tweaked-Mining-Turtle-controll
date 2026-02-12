-- ============================================
-- Mining Turtle System - Installer
--
-- Verwendung in Minecraft:
--   wget run https://raw.githubusercontent.com/JJBanana13/CC-Tweaked-Mining-Turtle-controll/main/installer.lua
--
-- Dann "server" oder "turtle" waehlen.
-- ============================================

local REPO = "https://raw.githubusercontent.com/JJBanana13/CC-Tweaked-Mining-Turtle-controll/main/"

-- Dateien pro Modus
local files = {
    server = {
        { remote = "shared/config.lua",    localPath = "shared/config.lua" },
        { remote = "shared/protocol.lua",  localPath = "shared/protocol.lua" },
        { remote = "server/server.lua",    localPath = "server/server.lua" },
        { remote = "server/startup.lua",   localPath = "startup.lua" },
    },
    turtle = {
        { remote = "shared/protocol.lua",  localPath = "shared/protocol.lua" },
        { remote = "turtle/chunk_miner.lua", localPath = "turtle/chunk_miner.lua" },
        { remote = "turtle/startup.lua",   localPath = "startup.lua" },
    },
}

-- Hilfsfunktion: Datei herunterladen
local function download(url, path)
    -- Verzeichnis erstellen falls noetig
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end

    -- Alte Datei loeschen
    if fs.exists(path) then
        fs.delete(path)
    end

    -- Herunterladen
    local response = http.get(url)
    if not response then
        return false, "Download fehlgeschlagen"
    end

    local content = response.readAll()
    response.close()

    local f = fs.open(path, "w")
    if not f then
        return false, "Kann Datei nicht schreiben: " .. path
    end
    f.write(content)
    f.close()
    return true
end

-- ============================================
-- Hauptprogramm
-- ============================================

term.clear()
term.setCursorPos(1, 1)

print("========================================")
print("  Mining Turtle System - Installer")
print("========================================")
print("")

-- Modus waehlen
local args = { ... }
local mode = args[1]

if not mode then
    print("Was soll installiert werden?")
    print("")
    print("  1) server  - Mining Control Server")
    print("  2) turtle  - Mining Turtle")
    print("")
    write("Auswahl (1/2): ")
    local input = read()
    if input == "1" or input == "server" then
        mode = "server"
    elseif input == "2" or input == "turtle" then
        mode = "turtle"
    else
        print("Ungueltige Auswahl!")
        return
    end
end

if not files[mode] then
    print("Unbekannter Modus: " .. tostring(mode))
    print("Verwende: installer server  ODER  installer turtle")
    return
end

print("")
print("Installiere als: " .. mode:upper())
print("")

-- HTTP pruefen
if not http then
    print("FEHLER: HTTP API nicht verfuegbar!")
    print("Aktiviere HTTP in der CC:Tweaked Config:")
    print("  computercraft-server.toml -> http.enabled = true")
    return
end

-- Dateien herunterladen
local fileList = files[mode]
local success = 0
local failed = 0

for i, file in ipairs(fileList) do
    local url = REPO .. file.remote
    write("  [" .. i .. "/" .. #fileList .. "] " .. file.localPath .. " ... ")
    local ok, err = download(url, file.localPath)
    if ok then
        print("OK")
        success = success + 1
    else
        print("FEHLER")
        print("       " .. tostring(err))
        failed = failed + 1
    end
end

print("")
print("========================================")
print("  Ergebnis: " .. success .. " OK, " .. failed .. " Fehler")
print("========================================")

if failed > 0 then
    print("")
    print("WARNUNG: Nicht alle Dateien konnten")
    print("installiert werden!")
    print("Pruefe die HTTP-Einstellungen.")
    return
end

print("")
print("Installation erfolgreich!")
print("")

if mode == "server" then
    print("Naechste Schritte:")
    print("  1) Bearbeite shared/config.lua")
    print("     -> Setze BASE_X, BASE_Y, BASE_Z")
    print("        (Position deiner Fuel Chest)")
    print("  2) Starte mit: reboot")
elseif mode == "turtle" then
    print("Naechste Schritte:")
    print("  1) Starte mit: reboot")
    print("  (Config wird automatisch vom Server")
    print("   empfangen - keine Einrichtung noetig!)")
end

print("")
print("Anleitung: github.com/JJBanana13/")
print("  CC-Tweaked-Mining-Turtle-controll")

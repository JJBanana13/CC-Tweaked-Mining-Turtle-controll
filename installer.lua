-- ============================================================
-- ATM10 Mining Fleet - Installer
-- Automatischer Installer fuer Controller und Turtles
-- ============================================================

-- GitHub Raw URL - HIER ANPASSEN nach Fork/Upload
local GITHUB_USER = "JJBanana13"
local GITHUB_REPO = "CC-Tweaked-Mining-Turtle-controll"
local GITHUB_BRANCH = "main"
local BASE_URL = "https://raw.githubusercontent.com/"
    .. GITHUB_USER .. "/" .. GITHUB_REPO .. "/" .. GITHUB_BRANCH .. "/"

-- ============================================================
-- HILFSFUNKTIONEN
-- ============================================================

local function download(remotePath, localPath)
    local url = BASE_URL .. remotePath
    print("  Lade: " .. remotePath)
    local response = http.get(url)
    if response then
        local content = response.readAll()
        response.close()
        local f = fs.open(localPath, "w")
        f.write(content)
        f.close()
        return true
    else
        print("  FEHLER: Download fehlgeschlagen!")
        print("  URL: " .. url)
        return false
    end
end

local function isTurtle()
    return turtle ~= nil
end

-- ============================================================
-- HAUPTPROGRAMM
-- ============================================================

term.clear()
term.setCursorPos(1, 1)

print("========================================")
print("  ATM10 Mining Fleet - Installer")
print("========================================")
print()

-- Erkennen ob Turtle oder Computer
if isTurtle() then
    print("Erkannt: Mining Turtle")
    print("Installiere Turtle-Software...")
    print()

    -- Alte Dateien loeschen
    if fs.exists("startup.lua") then
        fs.delete("startup.lua")
    end
    if fs.exists("miner.lua") then
        fs.delete("miner.lua")
    end
    if fs.exists("protocol.lua") then
        fs.delete("protocol.lua")
    end

    -- Dateien herunterladen
    local ok = true
    ok = download("shared/protocol.lua", "protocol.lua") and ok
    ok = download("turtle/miner.lua", "miner.lua") and ok
    ok = download("turtle/startup.lua", "startup.lua") and ok

    if ok then
        print()
        print("Installation erfolgreich!")
        print()
        print("Naechste Schritte:")
        print("  1. Konfiguration: miner config")
        print("  2. Oder einfach neustarten (reboot)")
        print("     -> Konfig wird automatisch abgefragt")
        print()

        -- Direkt konfigurieren?
        print("Jetzt konfigurieren? (j/n)")
        local ans = read()
        if ans == "j" or ans == "J" then
            shell.run("miner.lua", "config")
            print()
            print("Neustart in 3 Sekunden...")
            sleep(3)
            os.reboot()
        end
    else
        print()
        print("FEHLER bei der Installation!")
        print("Pruefen: Internet/HTTP aktiviert in Server-Config?")
    end

else
    print("Erkannt: Computer (Controller)")
    print("Installiere Controller-Software...")
    print()

    -- Alte Dateien loeschen
    if fs.exists("startup.lua") then
        fs.delete("startup.lua")
    end
    if fs.exists("controller.lua") then
        fs.delete("controller.lua")
    end
    if fs.exists("protocol.lua") then
        fs.delete("protocol.lua")
    end

    -- Dateien herunterladen
    local ok = true
    ok = download("shared/protocol.lua", "protocol.lua") and ok
    ok = download("controller/controller.lua", "controller.lua") and ok
    ok = download("controller/startup.lua", "startup.lua") and ok

    if ok then
        print()
        print("Installation erfolgreich!")
        print()
        print("Naechste Schritte:")
        print("  1. Konfiguration: controller config")
        print("  2. Oder einfach neustarten (reboot)")
        print("     -> Konfig wird automatisch abgefragt")
        print()

        -- Direkt konfigurieren?
        print("Jetzt konfigurieren? (j/n)")
        local ans = read()
        if ans == "j" or ans == "J" then
            shell.run("controller.lua", "config")
            print()
            print("Neustart in 3 Sekunden...")
            sleep(3)
            os.reboot()
        end
    else
        print()
        print("FEHLER bei der Installation!")
        print("Pruefen: Internet/HTTP aktiviert in Server-Config?")
    end
end

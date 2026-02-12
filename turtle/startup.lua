-- ============================================================
-- ATM10 Mining Fleet - Turtle Startup
-- Startet den Miner automatisch mit Resume-Support
-- ============================================================

-- Warte kurz damit Welt vollstaendig geladen ist
sleep(2)

-- Pruefen ob miner.lua existiert
if not fs.exists("miner.lua") then
    print("FEHLER: miner.lua nicht gefunden!")
    print("Bitte Installer ausfuehren.")
    return
end

-- Pruefen ob Konfiguration existiert
if not fs.exists("miner_config") then
    print("Keine Konfiguration gefunden!")
    print("Starte Konfigurations-Modus...")
    sleep(1)
    shell.run("miner.lua", "config")
    print()
    print("Neustart in 3 Sekunden...")
    sleep(3)
    os.reboot()
    return
end

-- Miner starten
print("Starte ATM10 Mining Fleet Turtle...")
shell.run("miner.lua")

-- ============================================================
-- ATM10 Mining Fleet - Controller Startup
-- Startet den Controller automatisch
-- ============================================================

sleep(2)

if not fs.exists("controller.lua") then
    print("FEHLER: controller.lua nicht gefunden!")
    print("Bitte Installer ausfuehren.")
    return
end

if not fs.exists("controller_config") then
    print("Keine Konfiguration gefunden!")
    print("Starte Konfigurations-Modus...")
    sleep(1)
    shell.run("controller.lua", "config")
    print()
    print("Neustart in 3 Sekunden...")
    sleep(3)
    os.reboot()
    return
end

print("Starte ATM10 Mining Fleet Controller...")
shell.run("controller.lua")

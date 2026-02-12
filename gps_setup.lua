-- ============================================================
-- ATM10 Mining Fleet - GPS Satelliten Setup
-- Hilft beim Einrichten der 4 GPS-Satelliten
-- ============================================================

print("========================================")
print("  ATM10 GPS Satelliten Setup")
print("========================================")
print()
print("Du brauchst 4 Computer mit Wireless Modem")
print("auf Y=256+ in folgendem Muster:")
print()
print("       [GPS2]")
print("         |")
print("  [GPS3]-+-[GPS1]")
print("         |")
print("       [GPS4]")
print()
print("Mindestabstand: 3 Bloecke voneinander")
print("Alle auf gleicher Hoehe (z.B. Y=260)")
print()
print("Die Computer muessen als startup.lua folgendes haben:")
print()

-- Koordinaten abfragen
print("Gib die Koordinaten jedes GPS-Computers ein:")
print()

local satellites = {}
for i = 1, 4 do
    print("--- GPS Satellit " .. i .. " ---")
    print("X-Koordinate:")
    local x = tonumber(read()) or 0
    print("Y-Koordinate:")
    local y = tonumber(read()) or 260
    print("Z-Koordinate:")
    local z = tonumber(read()) or 0
    satellites[i] = { x = x, y = y, z = z }
    print()
end

-- Startup-Dateien generieren
print("========================================")
print("Kopiere diese startup.lua auf jeden GPS-Computer:")
print("========================================")
print()

for i, sat in ipairs(satellites) do
    print("--- GPS Satellit " .. i .. " (X:" .. sat.x .. " Y:" .. sat.y .. " Z:" .. sat.z .. ") ---")
    print()
    print('  -- startup.lua fuer GPS Satellit ' .. i)
    print('  local modemSide = "top"  -- Anpassen!')
    print('  rednet.open(modemSide)')
    print('  print("GPS Satellit ' .. i .. ' aktiv")')
    print('  print("Position: ' .. sat.x .. ', ' .. sat.y .. ', ' .. sat.z .. '")')
    print('  shell.run("gps", "host", ' .. sat.x .. ', ' .. sat.y .. ', ' .. sat.z .. ')')
    print()
end

-- Optional: Dateien direkt auf Disketten schreiben
print("========================================")
print("Sollen die startup.lua-Dateien auf Disketten")
print("geschrieben werden? (j/n)")
local writeDisk = read()

if writeDisk == "j" or writeDisk == "J" then
    for i, sat in ipairs(satellites) do
        print()
        print("Lege Diskette fuer Satellit " .. i .. " in ein Laufwerk ein.")
        print("Auf welcher Seite ist das Laufwerk? (top/bottom/left/right/front/back)")
        local side = read()

        if peripheral.getType(side) == "drive" then
            local path = disk.getMountPath(side)
            if path then
                local f = fs.open(path .. "/startup.lua", "w")
                f.writeLine('-- GPS Satellit ' .. i .. ' - Auto-generiert')
                f.writeLine('local modemSide = nil')
                f.writeLine('for _, s in ipairs({"top","bottom","left","right","front","back"}) do')
                f.writeLine('    if peripheral.getType(s) == "modem" then')
                f.writeLine('        modemSide = s')
                f.writeLine('        break')
                f.writeLine('    end')
                f.writeLine('end')
                f.writeLine('if modemSide then')
                f.writeLine('    rednet.open(modemSide)')
                f.writeLine('    print("GPS Satellit ' .. i .. ' aktiv")')
                f.writeLine('    print("Position: ' .. sat.x .. ', ' .. sat.y .. ', ' .. sat.z .. '")')
                f.writeLine('    shell.run("gps", "host", ' .. sat.x .. ', ' .. sat.y .. ', ' .. sat.z .. ')')
                f.writeLine('else')
                f.writeLine('    print("FEHLER: Kein Modem gefunden!")')
                f.writeLine('end')
                f.close()
                print("startup.lua auf Diskette geschrieben!")
            else
                print("FEHLER: Keine Diskette im Laufwerk!")
            end
        else
            print("FEHLER: Kein Laufwerk auf Seite '" .. side .. "'!")
        end
    end
end

print()
print("========================================")
print("GPS Setup abgeschlossen!")
print("Stelle die 4 Computer auf und starte sie.")
print("Teste mit: gps locate")
print("========================================")

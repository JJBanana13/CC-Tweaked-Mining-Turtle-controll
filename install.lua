-- ============================================
-- ChunkMiner - Installer
-- ============================================
-- Run this on a turtle or server computer to install
-- Usage: install <server|turtle>

local args = { ... }
local mode = args[1]

if not mode or (mode ~= "server" and mode ~= "turtle") then
    print("========================================")
    print("  ChunkMiner Installer v1.0")
    print("========================================")
    print("")
    print("Usage: install <server|turtle>")
    print("")
    print("  server  - Install server/hub program")
    print("            (on advanced computer with")
    print("             monitor + wireless modem)")
    print("")
    print("  turtle  - Install turtle mining client")
    print("            (on mining turtle with")
    print("             wireless modem)")
    print("")
    print("Make sure all files are on the same")
    print("floppy disk or use pastebin.")
    return
end

-- Check for modem
local modem = peripheral.find("modem")
if not modem then
    print("ERROR: No wireless modem found!")
    print("Attach a wireless modem and try again.")
    return
end

if mode == "server" then
    print("Installing ChunkMiner Server...")

    -- Check for monitor
    local monitor = peripheral.find("monitor")
    if not monitor then
        print("WARNING: No monitor detected!")
        print("The server will work but without GUI.")
        print("Attach a 4x3 or bigger advanced monitor")
        print("for the best experience.")
        print("")
    end

    -- Copy files
    if fs.exists("disk/config.lua") then
        fs.copy("disk/config.lua", "config.lua")
        fs.copy("disk/server.lua", "startup.lua")
        print("Installed from floppy disk.")
    elseif fs.exists("config.lua") and fs.exists("server.lua") then
        fs.copy("server.lua", "startup.lua")
        print("Server set as startup program.")
    else
        print("Files already in place or using pastebin.")
        print("Make sure config.lua and server.lua")
        print("are in the root directory.")
    end

    -- Set label
    os.setComputerLabel("ChunkMiner-Hub")

    print("")
    print("Server installed!")
    print("Reboot to start: reboot")

elseif mode == "turtle" then
    if not turtle then
        print("ERROR: This is not a turtle!")
        print("Run this on a mining turtle.")
        return
    end

    print("Installing ChunkMiner Turtle Client...")

    -- Check for pickaxe
    -- (Can't easily check in CC:T, just warn)
    print("Make sure this is a MINING turtle")
    print("(crafted with a diamond pickaxe).")
    print("")

    -- Copy files
    if fs.exists("disk/config.lua") then
        fs.copy("disk/config.lua", "config.lua")
        fs.copy("disk/turtle.lua", "startup.lua")
        print("Installed from floppy disk.")
    elseif fs.exists("config.lua") and fs.exists("turtle.lua") then
        fs.copy("turtle.lua", "startup.lua")
        print("Turtle set as startup program.")
    else
        print("Files already in place or using pastebin.")
        print("Make sure config.lua and turtle.lua")
        print("are in the root directory.")
    end

    print("")
    print("Turtle client installed!")
    print("Reboot to start: reboot")
end

print("")
print("========================================")
print("  Setup Complete!")
print("========================================")

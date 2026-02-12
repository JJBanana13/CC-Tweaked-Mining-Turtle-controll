-- ============================================
-- Kommunikationsprotokoll
-- Rednet-basierte Kommunikation zwischen
-- Server und Turtles
-- ============================================

local PROTOCOL = "chunk_mining"
local protocol = {}

-- Modem finden und oeffnen
function protocol.init()
    local modem = peripheral.find("modem")
    if not modem then
        error("Kein Modem gefunden! Bitte Wireless Modem anbringen.")
    end
    local modemSide = peripheral.getName(modem)
    if not rednet.isOpen(modemSide) then
        rednet.open(modemSide)
    end
    return modemSide
end

-- Nachricht senden
function protocol.send(targetId, msgType, data)
    local message = {
        type = msgType,
        data = data or {},
        sender = os.getComputerID(),
        timestamp = os.clock(),
    }
    rednet.send(targetId, message, PROTOCOL)
end

-- Broadcast senden
function protocol.broadcast(msgType, data)
    local message = {
        type = msgType,
        data = data or {},
        sender = os.getComputerID(),
        timestamp = os.clock(),
    }
    rednet.broadcast(message, PROTOCOL)
end

-- Nachricht empfangen (mit Timeout)
function protocol.receive(timeout)
    local senderId, message = rednet.receive(PROTOCOL, timeout)
    if senderId and type(message) == "table" and message.type then
        return senderId, message
    end
    return nil, nil
end

return protocol

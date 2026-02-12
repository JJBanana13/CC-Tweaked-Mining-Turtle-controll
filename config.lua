-- ============================================
-- ChunkMiner Configuration
-- ============================================
-- Edit these values to match your setup!

local config = {}

-- Rednet channel/protocol
config.PROTOCOL = "chunkminer"
config.SERVER_ID = nil  -- Will be set automatically

-- Mining dimensions (1 chunk = 16x16)
config.CHUNK_WIDTH = 16
config.CHUNK_DEPTH = 16
config.MIN_Y = -64        -- Bedrock level (ATM10 mining dim, adjust if needed)
config.START_Y = 320      -- Starting Y level (top of mining dim, adjust!)

-- Turtle grid: 16 turtles in a 4x4 grid
-- Each turtle mines a 4x4 column from START_Y down to MIN_Y
config.GRID_SIZE = 4      -- 4x4 = 16 turtles
config.SECTION_WIDTH = 4  -- Each turtle: 4 blocks wide
config.SECTION_DEPTH = 4  -- Each turtle: 4 blocks deep

-- Number of turtles
config.TURTLE_COUNT = 16

-- Fuel settings
config.FUEL_THRESHOLD = 500       -- Refuel when below this
config.FUEL_SLOT = 1              -- Slot for fuel items
config.FUEL_CHEST_SLOT = 16      -- Slot for fuel chest (if using ender chest)

-- Inventory
config.CHEST_DIRECTION = "front"  -- Direction to drop items (relative to turtle at home)
config.INVENTORY_THRESHOLD = 14   -- Return to dump when this many slots are full

-- Blacklist: blocks to skip (saves inventory space)
config.BLACKLIST = {
    "minecraft:stone",
    "minecraft:cobblestone",
    "minecraft:dirt",
    "minecraft:gravel",
    "minecraft:sand",
    "minecraft:netherrack",
    "minecraft:deepslate",
    "minecraft:cobbled_deepslate",
    "minecraft:tuff",
    "minecraft:granite",
    "minecraft:diorite",
    "minecraft:andesite",
    "minecraft:calcite",
}

-- Home position (where the server/chests are)
-- Turtles will be placed relative to this
config.HOME = { x = 0, y = 0, z = 0 }

-- Modem side (which side the wireless modem is on)
config.MODEM_SIDE = "right"

-- Monitor size (for the server)
config.MONITOR_SIDE = "top"  -- or "left", "right", "back", etc.

-- Update interval (seconds)
config.STATUS_INTERVAL = 2

-- Colors for status display
config.COLORS = {
    idle      = colors.lightGray,
    mining    = colors.lime,
    returning = colors.yellow,
    refueling = colors.orange,
    dumping   = colors.cyan,
    error     = colors.red,
    offline   = colors.gray,
    done      = colors.green,
    halted    = colors.magenta,
}

return config

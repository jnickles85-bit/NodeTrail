local failed = 0
local function check(cond, msg)
  if not cond then
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
    failed = failed + 1
  end
end

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}

local function deepCopy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = deepCopy(v) end
  return r
end
CopyTable = deepCopy

local now = 0
GetTime = function() return now end
time = function() return 1700000000 end

local frames = {}
CreateFrame = function()
  local f = { scripts = {}, events = {} }
  f.SetScript = function(self, name, fn) self.scripts[name] = fn end
  f.GetScript = function(self, name) return self.scripts[name] end
  f.RegisterEvent = function(self, name) self.events[name] = true end
  f.UnregisterEvent = function(self, name) self.events[name] = nil end
  frames[#frames + 1] = f
  return f
end

local spellNames = { [2366] = "Herb Gathering", [2575] = "Mining", [99999] = "Herb Gathering" }
GetSpellInfo = function(id) return spellNames[id] end

local playerMap = 1429
local playerPos = { 0.123456, 0.654321 }
C_Map = {
  GetBestMapForUnit = function() return playerMap end,
  GetPlayerMapPosition = function(m)
    if not playerPos then return nil end
    return { GetXY = function() return playerPos[1], playerPos[2] end }
  end
}

local loot = {}
GetNumLootItems = function() return #loot end
GetLootSlotLink = function(i) return loot[i] and loot[i].link end
GetLootSlotInfo = function(i)
  local s = loot[i]
  if s then return "icon", s.name, s.qty end
end
GetLootSourceInfo = function(i) return loot[i] and loot[i].guid end

local fishing = false
IsFishingLoot = function() return fishing end

local pkg = {}
local function loadFile(path)
  local chunk = assert(loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. path))
  chunk("MightiePack", pkg)
end
loadFile("locale/enUS.lua")
loadFile("Config.lua")
loadFile("Data/ItemNames.lua")
loadFile("Data/Recorder.lua")
local ns = pkg.NodeTrail

local function fire(event, ...)
  local frame = ns.Recorder.frame
  local fn = frame:GetScript("OnEvent")
  fn(frame, event, ...)
end

-- 1. Before Enable
check(#frames == 0, "no frames before Enable")
check(ns.Recorder.frame == nil, "frame nil before Enable")

-- 2. Preexisting SV preserved
NodeTrailDB = { profile = { pathWidth = 5, custom = "keep" }, other = 7 }
ns.Recorder:Enable()
check(NodeTrailDB.profile.pathWidth == 5, "profile.pathWidth preserved")
check(NodeTrailDB.profile.custom == "keep", "profile.custom preserved")
check(NodeTrailDB.other == 7, "other preserved")
check(NodeTrailDB.herbs.schema == 2, "herbs.schema == 2")
check(NodeTrailDB.herbs.total == 0, "herbs.total == 0")
check(type(NodeTrailDB.herbs.maps) == "table", "herbs.maps is table")
check(type(NodeTrailDB.herbs.mapTotals) == "table", "herbs.mapTotals is table")
check(type(NodeTrailDB.herbs.stats) == "table", "herbs.stats is table")
check(ns.Recorder.frame.events.UNIT_SPELLCAST_SUCCEEDED == true, "registered UNIT_SPELLCAST_SUCCEEDED")
check(ns.Recorder.frame.events.LOOT_OPENED == true, "registered LOOT_OPENED")
local frameCount = #frames
ns.Recorder:Enable()
check(#frames == frameCount, "Enable idempotent")

-- 3. Herb gather
now = 100
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", 2366)
loot = {
  { link = "|cffffffff|Hitem:2447::::::::1:::::::|h[Peacebloom]|h|r", name = "Peacebloom", qty = 2, guid = "GameObject-0-4170-0-12345-1617-0000435B12" },
  { link = "|cff1eff00|Hitem:765::::::::1:::::::|h[Silverleaf]|h|r", name = "Silverleaf", qty = 1, guid = "GameObject-0-4170-0-12345-1617-0000435B12" }
}
now = 101
fire("LOOT_READY")
fire("LOOT_OPENED")
local herbs = NodeTrailDB.herbs
check(herbs.total == 1, "total == 1")
local list = herbs.maps[1429]
check(#list == 1, "list length 1")
check(list[1].x == 0.1235, "x rounded")
check(list[1].y == 0.6543, "y rounded")
check(list[1].t == 1700000000, "t == 1700000000")
check(list[1].node == 1617, "node == 1617")
check(#list[1].items == 2, "2 items")
check(list[1].items[1].id == 2447, "item1 id 2447")
check(list[1].items[1].name == "Peacebloom", "item1 name")
check(list[1].items[1].count == 2, "item1 count 2")
check(list[1].items[2].id == 765, "item2 id 765")
check(list[1].items[2].count == 1, "item2 count 1")
check(ns.Recorder._error == nil, "no error")

-- 4. Localized/custom spell id
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 99999)
fire("LOOT_OPENED")
check(herbs.total == 2, "total == 2 after custom spell")

-- 5. Non-herb spell
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 2575)
fire("LOOT_OPENED")
check(herbs.total == 2, "total still 2 after non-herb")

-- 6. Other unit
fire("UNIT_SPELLCAST_SUCCEEDED", "target", "g", 2366)
fire("LOOT_OPENED")
check(herbs.total == 2, "total still 2 after other unit")

-- 7. Too late
now = 200
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 2366)
now = 206
fire("LOOT_OPENED")
check(herbs.total == 2, "total still 2 after too late")

-- 8. Fishing loot
fishing = true
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 2366)
fire("LOOT_OPENED")
check(herbs.total == 2, "total still 2 after fishing")
fishing = false

-- 9. No position
playerPos = nil
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 2366)
fire("LOOT_OPENED")
check(herbs.total == 2, "total still 2 after no position")
playerPos = { 0, 0 }
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 2366)
fire("LOOT_OPENED")
check(herbs.total == 2, "total still 2 after 0,0 position")
playerPos = { 0.5, 0.25 }

-- 10. Loot without prior cast
fire("LOOT_OPENED")
check(herbs.total == 2, "total still 2 after loot without cast")

-- 11. Empty loot still records
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 2366)
loot = {}
fire("LOOT_OPENED")
check(herbs.total == 3, "total == 3 after empty loot")
local list2 = herbs.maps[1429]
check(#list2[#list2].items == 0, "empty items")
check(list2[#list2].node == nil, "no node")

-- 12. Direct RecordHerb
ns.RecordHerb(1430, 0.5, 0.5, { { id = 2449, count = 1 } })
check(herbs.maps[1430][1].items[1].id == 2449, "direct record id")
check(herbs.total == 4, "total == 4")

-- 13. Fresh NodeTrailDB
NodeTrailDB = nil
local db = ns.GetHerbDB()
check(NodeTrailDB.profile.pathWidth == 2, "fresh profile pathWidth")
check(type(db) == "table", "fresh herbs table")

if failed == 0 then
  print("recorder_spec: ok")
else
  os.exit(1)
end

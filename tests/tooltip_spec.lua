local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. msg .. "\n")
  end
end

local pkg = {}
local function loadFile(path)
  local f = assert(loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. path))
  f("MightiePack", pkg)
end

loadFile("locale/enUS.lua")
loadFile("Config.lua")
loadFile("Data/Recorder.lua")
loadFile("Data/HerbData.lua")
loadFile("Data/Recipes.lua")
loadFile("UI/Tooltip.lua")

local ns = pkg.NodeTrail

time = time or os.time
CopyTable = function(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == table and CopyTable(v) or v end return c end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
local frames = {}
CreateFrame = function()
  local f = { scripts = {}, events = {} }
  f.SetScript = function(self, name, fn) self.scripts[name] = fn end
  f.RegisterEvent = function(self, name) self.events[name] = true end
  table.insert(frames, f)
  return f
end
GetSpellInfo = function(id)
  local map = { [2366] = "Herb Gathering", [2259] = "Alchemy" }
  return map[id]
end
local mouseoverUnit = false
UnitExists = function(u) return u == "mouseover" and mouseoverUnit end
UIParent = {}
WorldFrame = {}

GameTooltip = {
  lines = {},
  hooks = {},
  owner = UIParent,
  shows = 0,
}
GameTooltip.HookScript = function(self, name, fn)
  self.hooks[name] = self.hooks[name] or {}
  table.insert(self.hooks[name], fn)
end
GameTooltip.NumLines = function(self) return #self.lines end
GameTooltip.GetOwner = function(self) return self.owner end
GameTooltip.AddLine = function(self, t) table.insert(self.lines, t) end
GameTooltip.AddDoubleLine = function(self, l, r) table.insert(self.lines, l .. " | " .. r) end
GameTooltip.Show = function(self)
  self.shows = self.shows + 1
  if self.hooks.OnShow then
    for _, fn in ipairs(self.hooks.OnShow) do
      fn(self)
    end
  end
end

local function hover(name)
  GameTooltip.lines = { name, "Herbalism" }
  _G["GameTooltipTextLeft1"] = { GetText = function() return GameTooltip.lines[1] end }
  if GameTooltip.hooks.OnTooltipCleared then
    for _, fn in ipairs(GameTooltip.hooks.OnTooltipCleared) do
      fn()
    end
  end
  GameTooltip:Show()
end

local trade = { line = nil, rows = {} }
GetTradeSkillLine = function() return trade.line, 1, 300 end
GetNumTradeSkills = function() return #trade.rows end
GetTradeSkillInfo = function(i) return trade.rows[i].name, trade.rows[i].type end
GetTradeSkillNumReagents = function(i) return #(trade.rows[i].reagents or {}) end
GetTradeSkillReagentItemLink = function(i, r)
  return "|cffffffff|Hitem:" .. trade.rows[i].reagents[r] .. "::::::::1:::::::|h[x]|h|r"
end

-- Test 1
check(#frames == 0, "Test 1: no frames created at load")
check(GameTooltip.hooks.OnShow == nil or #GameTooltip.hooks.OnShow == 0, "Test 1: no OnShow hooks at load")

-- Test 2
NodeTrailDB = nil
ns.Recipes:Enable()
ns.Tooltip:Enable()
ns.Recipes:Enable()
ns.Tooltip:Enable()
check(GameTooltip.hooks.OnShow and #GameTooltip.hooks.OnShow == 1, "Test 2: OnShow hooks count == 1")

-- Test 3
hover("Copper Vein")
check(#GameTooltip.lines == 2, "Test 3: unknown object adds no lines")

-- Test 4
mouseoverUnit = true
hover("Peacebloom")
check(#GameTooltip.lines == 2, "Test 4: unit tooltip ignored")
mouseoverUnit = false

-- Test 5
hover("Peacebloom")
local lines = GameTooltip.lines
local found = { NodeTrail = false, Peacebloom = false, Picks = false, Alchemy = false }
for _, l in ipairs(lines) do
  if l == "NodeTrail" then found.NodeTrail = true end
  if l == "Peacebloom | 100% (base)" then found.Peacebloom = true end
  if l == "Your picks: none yet" then found.Picks = true end
  if l == "Open Alchemy once to list recipe uses" then found.Alchemy = true end
end
check(found.NodeTrail, "Test 5: header present")
check(found.Peacebloom, "Test 5: Peacebloom line present")
check(found.Picks, "Test 5: picks line present")
check(found.Alchemy, "Test 5: alchemy hint present")
local count = 0
for _, l in ipairs(lines) do if l == "NodeTrail" then count = count + 1 end end
check(count == 1, "Test 5: header appears exactly once")

-- Test 6
hover("Mageroyal")
local mLines = GameTooltip.lines
local idxM, idxS = nil, nil
for i, l in ipairs(mLines) do
  if l == "Mageroyal | 100% (base)" then idxM = i end
  if l == "Swiftthistle | 10% (base)" then idxS = i end
end
check(idxM ~= nil, "Test 6: Mageroyal line present")
check(idxS ~= nil, "Test 6: Swiftthistle line present")
if idxM and idxS then check(idxM < idxS, "Test 6: Mageroyal before Swiftthistle") end

-- Test 7
ns.RecordHerb(1429, 0.5, 0.5, { { id = 2447, count = 2 } })
ns.RecordHerb(1429, 0.5, 0.5, { { id = 2447, count = 2 } })
ns.RecordHerb(1429, 0.5, 0.5, { { id = 2447, count = 2 } })
hover("Peacebloom")
local pLines = GameTooltip.lines
local foundPicks3 = false
for _, l in ipairs(pLines) do
  if l == "Your picks: 3" then foundPicks3 = true end
end
check(foundPicks3, "Test 7: picks 3 present")
local foundBase = false
for _, l in ipairs(pLines) do
  if l == "Peacebloom | 100% (base)" then foundBase = true end
end
check(foundBase, "Test 7: base line present")

-- Test 8
for i = 1, 7 do
  local items = { { id = 2447, count = 2 } }
  if i <= 4 then
    table.insert(items, { id = 2452, count = 1 })
  end
  ns.RecordHerb(1429, 0.5, 0.5, items)
end
hover("Peacebloom")
local pLines8 = GameTooltip.lines
local found100, found40, found10 = false, false, false
for _, l in ipairs(pLines8) do
  if l == "Peacebloom | 100%" then found100 = true end
  if l == "Swiftthistle | 40%" then found40 = true end
  if l == "Your picks: 10" then found10 = true end
end
check(found100, "Test 8: Peacebloom 100% present")
check(found40, "Test 8: Swiftthistle 40% present")
check(found10, "Test 8: picks 10 present")

-- Test 9
trade = { line = "Cooking", rows = { { name = "Spiced Wolf Meat", type = "easy", reagents = { 2672 } } } }
local scanResult = ns.Recipes:Scan()
check(scanResult == false, "Test 9: scan returns false for non-alchemy")
check(NodeTrailDB.recipes.alchemyScanned == nil, "Test 9: alchemyScanned nil")

-- Test 10
trade = {
  line = "Alchemy",
  rows = {
    { name = "Potions", type = "header" },
    { name = "Minor Healing Potion", type = "easy", reagents = { 2447, 765, 3371 } },
    { name = "Elixir of Lion's Strength", type = "trivial", reagents = { 2449, 765, 3371 } },
    { name = "Swiftness Potion", type = "medium", reagents = { 2452, 2450, 3371 } },
  }
}
local recipesFrame = frames[#frames]
if recipesFrame and recipesFrame.scripts.OnEvent then
  recipesFrame.scripts.OnEvent(recipesFrame, "TRADE_SKILL_SHOW")
end
local alch = NodeTrailDB.recipes.alchemy
check(alch[765] ~= nil, "Test 10: 765 in alchemy")
if alch[765] then
  local hasElixir, hasMinor = false, false
  for _, n in ipairs(alch[765]) do
    if n == "Elixir of Lion's Strength" then hasElixir = true end
    if n == "Minor Healing Potion" then hasMinor = true end
  end
  check(hasElixir, "Test 10: Elixir present")
  check(hasMinor, "Test 10: Minor present")
  check(alch[765][1] == "Elixir of Lion's Strength", "Test 10: sorted")
end
hover("Peacebloom")
local foundAlch = false
for _, l in ipairs(GameTooltip.lines) do
  if l == "Alchemy: Minor Healing Potion" then foundAlch = true end
end
check(foundAlch, "Test 10: Peacebloom alchemy line")
hover("Silverleaf")
local foundAlch2 = false
for _, l in ipairs(GameTooltip.lines) do
  if l == "Alchemy: Elixir of Lion's Strength, Minor Healing Potion" then foundAlch2 = true end
end
check(foundAlch2, "Test 10: Silverleaf alchemy line")
local foundHint = false
for _, l in ipairs(GameTooltip.lines) do
  if l == "Open Alchemy once to list recipe uses" then foundHint = true end
end
check(not foundHint, "Test 10: hint gone")

-- Test 11
trade.rows = { { name = "Minor Healing Potion", type = "easy", reagents = { 2447 } } }
ns.Recipes:Scan()
check(NodeTrailDB.recipes.alchemy[765] == nil, "Test 11: 765 removed")

-- Test 12
check(type(NodeTrailDB.profile) == "table", "Test 12: profile table")
check(NodeTrailDB.herbs.total == 10, "Test 12: herbs total 10")

-- Test 13
check(ns.Tooltip._error == nil, "Test 13: Tooltip no error")
check(ns.Recipes._error == nil, "Test 13: Recipes no error")

if failed > 0 then
  os.exit(1)
else
  print("tooltip_spec: ok")
end

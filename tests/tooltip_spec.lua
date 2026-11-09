local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. msg .. "\n")
  end
end

local F = dofile(root .. "/tests/support/fakeui.lua")
local SCREEN_W, SCREEN_H = F.install({ width = 1920, height = 1080 })

local pkg = {}
local function loadFile(path)
  local f = assert(loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. path))
  f("MightiePack", pkg)
end

loadFile("locale/enUS.lua")
loadFile("Config.lua")
loadFile("Data/ItemNames.lua")
loadFile("Data/Recorder.lua")
loadFile("Data/HerbData.lua")
loadFile("Data/Profession.lua")
loadFile("Data/Recipes.lua")
loadFile("UI/TooltipPanel.lua")
loadFile("UI/Tooltip.lua")
loadFile("Core.lua")

local ns = pkg.NodeTrail

time = time or os.time
CopyTable = function(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == table and CopyTable(v) or v end return c end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
-- Frames come from the shared client model (tests/support/fakeui.lua): they
-- have real textures, font strings and geometry, which is what the herb panel
-- needs. The event gate stays here — validity is never asked of C_EventUtils
-- (restricted, see event_gate_spec); the client answers by raising on
-- RegisterEvent.
local unknownEvents = {}
local baseCreateFrame = CreateFrame
CreateFrame = function(kind, name, parent)
  local f = baseCreateFrame(kind, name, parent)
  f.events = {}
  f.RegisterEvent = function(self, event)
    if unknownEvents[event] then
      error('Attempt to register unknown event "' .. tostring(event) .. '"', 2)
    end
    self.events[event] = true
  end
  return f
end
local frames = F.frames
GetSpellInfo = function(id)
  local map = { [2366] = "Herb Gathering", [2259] = "Alchemy" }
  return map[id]
end
local mouseoverUnit = false
UnitExists = function(u) return u == "mouseover" and mouseoverUnit end
UIParent = {}
WorldFrame = {}

-- t_d4848ce0: the herb block is gated on THIS character's profession. This
-- spec's character is an herbalist — the client's own skill lines say so — so
-- the block is expected to show here; the picks row then reads account-wide
-- because NodeTrailDB.herbs.maps is one table for every character.
local skillLines = {
  { name = "Herbalism", rank = 300 },
  { name = "Alchemy", rank = 300 },
}
GetNumSkillLines = function() return #skillLines end
GetSkillLineInfo = function(i)
  local row = skillLines[i]
  if not row then return nil end
  return row.name, false, true, row.rank
end


GameTooltip = F.newTooltip({
  lines = {},
  owner = UIParent,
  left = 400,
  bottom = 800,
  width = 180,
  height = 60,
})
GameTooltip.hooks = {}
GameTooltip.HookScript = function(self, name, fn)
  self.hooks[name] = self.hooks[name] or {}
  table.insert(self.hooks[name], fn)
end
_G.GameTooltip = GameTooltip

-- What the PANEL renders, in the same "name | value" shape the tooltip's own
-- double lines use. This replaces the old `GameTooltip.lines` read: the block
-- no longer lives in the tooltip.
local function panelLines()
  return ns.TooltipPanel:TextLines()
end

-- The recipe-uses line is parked OFF in the product (Config.showAlchemyUses =
-- false). These specs cover the code behind it, so every render switches it on
-- unless a test is specifically asserting the parked default (PARKED_ALCHEMY).
local PARKED_ALCHEMY = false
local function hover(name)
  NodeTrailDB = NodeTrailDB or {}
  NodeTrailDB.profile = NodeTrailDB.profile or {}
  NodeTrailDB.profile.showAlchemyUses = not PARKED_ALCHEMY
  GameTooltip.lines = { name, "Herbalism" }
  GameTooltip:SyncFirstLine()
  GameTooltip.shown = true
  -- The poller is the only thing that drives the panel (there is no OnShow hook
  -- any more); this is one tick of it.
  ns.Tooltip:Poll(GameTooltip)
end

local trade = { line = nil, rows = {} }
GetTradeSkillLine = function() return trade.line, 1, 300 end
GetNumTradeSkills = function() return #trade.rows end
GetTradeSkillInfo = function(i) return trade.rows[i].name, trade.rows[i].type end
-- t_4ab7c230: the legacy client model carries the availability count, so the
-- scan can gate this fixture's Alchemy line (a client without it would have
-- the line HIDDEN — see tests/alchemy_skill_gate_spec.lua §6).
GetTradeSkillNumAvailable = function(i) return trade.rows[i].numAvailable or 1 end
GetTradeSkillNumReagents = function(i) return #(trade.rows[i].reagents or {}) end
GetTradeSkillReagentItemLink = function(i, r)
  return "|cffffffff|Hitem:" .. trade.rows[i].reagents[r] .. "::::::::1:::::::|h[x]|h|r"
end

-- Test 1
check(#frames == 0, "Test 1: no frames created at load")
check(GameTooltip.hooks.OnShow == nil or #GameTooltip.hooks.OnShow == 0, "Test 1: no OnShow hooks at load")
check(ns.TooltipPanel.frame == nil, "Test 1: the herb panel is created lazily, not at load")

-- Test 2
NodeTrailDB = nil
ns.Recipes:Enable()
ns.Tooltip:Enable()
ns.Recipes:Enable()
ns.Tooltip:Enable()
-- t_f4ff9ea6: the tooltip is not hooked any more. Enable is idempotent and the
-- only thing it creates is the private poll clock.
local hookTotal = 0
for _, list in pairs(GameTooltip.hooks) do hookTotal = hookTotal + #list end
check(hookTotal == 0, "Test 2: Enable installs no GameTooltip script (got " .. hookTotal .. ")")
check(ns.Tooltip.poller ~= nil, "Test 2: Enable created the private poll clock")
check(ns.Tooltip.poller == frames[#frames],
  "Test 2: the poll clock was the last frame created (it is Tooltip's own)")
local framesAfterEnable = #frames
ns.Tooltip:Enable()
check(#frames == framesAfterEnable, "Test 2: Enable is idempotent (no second clock)")

-- Test 3
hover("Copper Vein")
check(#GameTooltip.lines == 2, "Test 3: unknown object adds no lines to the tooltip")
check(#panelLines() == 0 and ns.TooltipPanel:IsShown() == false,
  "Test 3: unknown object shows no panel")

-- Test 4
mouseoverUnit = true
hover("Peacebloom")
check(#GameTooltip.lines == 2, "Test 4: unit tooltip ignored (no lines appended)")
check(ns.TooltipPanel:IsShown() == false, "Test 4: unit tooltip shows no panel")
mouseoverUnit = false

-- Test 5 — the PARKED default, asserted on purpose: with showAlchemyUses off
-- (the shipped value) a herb tooltip carries the node, the drop rates and the
-- picks line, and nothing about recipes — not the list, not the "open Alchemy
-- once" hint. Mightie, 2026-11-09: "lets just take that part out of the tooltip
-- info for now… the % of drops is fine for now."
PARKED_ALCHEMY = true
hover("Peacebloom")
local lines = panelLines()
local found = { Peacebloom = false, Picks = false, Alchemy = false }
local addonNameLines, firstBlockIndex = 0, nil
for i, l in ipairs(lines) do
  if l == "NodeTrail" then addonNameLines = addonNameLines + 1 end
  if l == "Peacebloom | 100% (base)" then
    found.Peacebloom = true
    firstBlockIndex = firstBlockIndex or i
  end
  if l == "Picks: none yet (all characters)" then found.Picks = true end
  if l == "Open Alchemy once to list recipe uses" then found.Alchemy = true end
end
check(addonNameLines == 0, "Test 5: no line reads the addon's name (got " .. addonNameLines .. ")")
check(firstBlockIndex == 1,
  "Test 5: the panel's block OPENS with the node name (index "
    .. tostring(firstBlockIndex) .. ")")
check(#GameTooltip.lines == 2,
  "Test 5: the client's tooltip still holds only its own two lines (got " .. #GameTooltip.lines .. ")")
check(found.Peacebloom, "Test 5: Peacebloom line present")
check(found.Picks, "Test 5: picks line present")
-- Parked (Mightie 2026-11-09): the recipe-uses line is off by default, and a
-- parked feature must not advertise itself — so the "Open Alchemy once" hint is
-- now required to be ABSENT. The gate itself stays covered by
-- recipe_diag_spec / alchemy_skill_gate_spec, which switch the flag back on.
check(not found.Alchemy, "Test 5: the parked alchemy line and its hint are absent")
PARKED_ALCHEMY = false

-- Test 6
hover("Mageroyal")
local mLines = panelLines()
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
local pLines = panelLines()
local foundPicks3 = false
for _, l in ipairs(pLines) do
  if l == "Picks: 3 (all characters)" then foundPicks3 = true end
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
local pLines8 = panelLines()
local found100, found40, found10 = false, false, false
for _, l in ipairs(pLines8) do
  if l == "Peacebloom | 100%" then found100 = true end
  if l == "Swiftthistle | 40%" then found40 = true end
  if l == "Picks: 10 (all characters)" then found10 = true end
end
check(found100, "Test 8: Peacebloom 100% present")
check(found40, "Test 8: Swiftthistle 40% present")
check(found10, "Test 8: picks 10 present")

-- Test 9
trade = { line = "Cooking", rows = { { name = "Spiced Wolf Meat", type = "easy", reagents = { 2672 } } } }
local scanResult = ns.Recipes:Scan()
check(scanResult == false, "Test 9: scan returns false for non-alchemy")
-- The DB may be absent entirely here (Test 2 cleared it and a gated scan does
-- not create one) — either way the intent is that nothing was persisted.
check(type(NodeTrailDB) ~= "table"
  or type(NodeTrailDB.recipes) ~= "table"
  or NodeTrailDB.recipes.alchemyScanned == nil,
  "Test 9: alchemyScanned nil")

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
-- The recipes event frame is Tooltip-independent; the poll clock is created
-- after it, so find it by its OnEvent script rather than by position.
local recipesFrame
for i = #frames, 1, -1 do
  if frames[i].scripts and frames[i].scripts.OnEvent then
    recipesFrame = frames[i]
    break
  end
end
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
for _, l in ipairs(panelLines()) do
  if l == "Alchemy: Minor Healing Potion" then foundAlch = true end
end
check(foundAlch, "Test 10: Peacebloom alchemy line")
hover("Silverleaf")
local foundAlch2 = false
for _, l in ipairs(panelLines()) do
  if l == "Alchemy: Elixir of Lion's Strength, Minor Healing Potion" then foundAlch2 = true end
end
check(foundAlch2, "Test 10: Silverleaf alchemy line")
local foundHint = false
for _, l in ipairs(panelLines()) do
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

-- ── Tests 14–16 (t_0d5badc3): C_TradeSkillUI port + impossible-instruction guard ──
-- A mainline client (Forever 16001) does not have the pre-Dragonflight
-- trade-skill globals, so the scan must run through the client's live
-- C_TradeSkillUI API when it exists — with every call pcall'd and
-- unexpected shapes skipped — and when NO trade-skill API exists at all,
-- the tooltip must not promise a step that can never succeed.
-- Tests 14 and 16 MUST fail on the parent commit.

local origAdd = DEFAULT_CHAT_FRAME.AddMessage
local function captureStatus()
  local cap = {}
  DEFAULT_CHAT_FRAME.AddMessage = function(_, m) cap[#cap + 1] = tostring(m) end
  local ok, err = pcall(ns.PrintStatus)
  DEFAULT_CHAT_FRAME.AddMessage = origAdd
  return ok, table.concat(cap, "\n"), err
end

-- Test 14 (part a): the "open Alchemy once" status line stays while a
-- usable API exists and the scan has not run (the step IS possible).
NodeTrailDB.recipes.alchemy = {}
NodeTrailDB.recipes.alchemyScanned = nil
local okStA, stOutA = captureStatus()
check(okStA, "Test 14a: PrintStatus runs (API available, unscanned)")
check(stOutA:find("open your Alchemy window once", 1, true) ~= nil,
  "Test 14a: usable API present → the instruction stays (it is possible)")

-- Test 14 (part b): a modern client stubs C_TradeSkillUI and loses the
-- legacy globals; the same two recipes through that API must produce the
-- same NodeTrailDB.recipes.alchemy map and tooltip lines as Test 10 did
-- through the legacy stub.
GetTradeSkillLine = nil
GetNumTradeSkills = nil
GetTradeSkillInfo = nil
GetTradeSkillNumAvailable = nil
GetTradeSkillNumReagents = nil
GetTradeSkillReagentItemLink = nil

C_TradeSkillUI = {
  GetNumRecipeIDs = function() return 2 end,
  GetRecipeID = function(i) return i == 1 and 101 or 102 end,
  GetRecipeInfo = function(id)
    if id == 101 then
      return {
        name = "Minor Healing Potion",
        reagents = {
          { itemID = 2447, quantity = 1 },
          { itemID = 765, quantity = 2 },
          { itemID = 3371, quantity = 1 },
        },
      }
    end
    if id == 102 then
      return {
        name = "Elixir of Lion's Strength",
        reagents = {
          { itemID = 2449, quantity = 1 },
          { itemID = 765, quantity = 2 },
          { itemID = 3371, quantity = 1 },
        },
      }
    end
    return nil
  end,
  GetOpenTradeSkillLine = function() return "Alchemy" end,
  -- t_4ab7c230: every recipe in this fixture is known, so the gated line keeps
  -- the same expected content as before the availability gate existed.
  IsRecipeProfessionLearned = function() return true end,
}

NodeTrailDB.recipes.alchemy = {}
NodeTrailDB.recipes.alchemyScanned = nil

local recipesFrame = frames[1]
local okEv, evErr = pcall(recipesFrame.scripts.OnEvent, recipesFrame, "TRADE_SKILLS_SHOW")
check(okEv, "Test 14: modern trade-skill event handler ran: " .. tostring(evErr))

local alch = NodeTrailDB.recipes.alchemy
check(alch[2447] ~= nil, "Test 14: Peacebloom (2447) in modern map")
if alch[2447] then
  check(#alch[2447] == 1 and alch[2447][1] == "Minor Healing Potion",
    "Test 14: 2447 → Minor Healing Potion only")
end
check(alch[765] ~= nil, "Test 14: Silverleaf (765) in modern map")
if alch[765] then
  local hasElixir, hasMinor = false, false
  for _, n in ipairs(alch[765]) do
    if n == "Elixir of Lion's Strength" then hasElixir = true end
    if n == "Minor Healing Potion" then hasMinor = true end
  end
  check(hasElixir and hasMinor, "Test 14: 765 → both recipes (same map as legacy stub)")
  check(alch[765][1] == "Elixir of Lion's Strength", "Test 14: 765 sorted")
end
check(alch[2449] ~= nil and alch[2449][1] == "Elixir of Lion's Strength", "Test 14: 2449 → Elixir")
check(alch[3371] ~= nil, "Test 14: 3371 present")
check(alch[2452] == nil, "Test 14: stale legacy entries are replaced")
local nk = 0
for _ in pairs(alch) do nk = nk + 1 end
check(nk == 4, "Test 14: map has exactly the modern reagent set (got " .. nk .. ")")
check(NodeTrailDB.recipes.alchemyScanned ~= nil, "Test 14: alchemyScanned set")

local okAp14, ap14 = pcall(function() return ns.Recipes:APIInfo() end)
check(okAp14 and ap14.modern.exists == true, "Test 14: APIInfo sees C_TradeSkillUI")
check(okAp14 and ap14.available == true, "Test 14: APIInfo reports available (modern path)")
local okD14, d14 = pcall(function()
  local d = ns.Recipes._diag
  return d and d.path == "modern" and (d.recipeCount or 0) == 2
end)
check(okD14 and d14 == true, "Test 14: scan diag records the modern path + 2 recipes")
check(ns.Recipes._error == nil, "Test 14: Recipes no error")

hover("Peacebloom")
local foundP14 = false
for _, l in ipairs(panelLines()) do
  if l == "Alchemy: Minor Healing Potion" then foundP14 = true end
end
check(foundP14, "Test 14: Peacebloom tooltip line (same as legacy stub)")
hover("Silverleaf")
local foundS14 = false
local foundHint14 = false
for _, l in ipairs(panelLines()) do
  if l == "Alchemy: Elixir of Lion's Strength, Minor Healing Potion" then foundS14 = true end
  if l == "Open Alchemy once to list recipe uses" then foundHint14 = true end
end
check(foundS14, "Test 14: Silverleaf tooltip line (same as legacy stub)")
check(not foundHint14, "Test 14: hint gone after modern scan")
local okStB, stOutB = captureStatus()
check(okStB and stOutB:find("Alchemy recipes: scanned", 1, true) ~= nil,
  "Test 14: status reports the scan (modern)")

-- Test 15: malformed modern returns (nil info, table without a name,
-- junk reagent slots, recipe without reagents) are skipped without an
-- error, and the valid pieces still land in the map.
C_TradeSkillUI = {
  GetNumRecipeIDs = function() return 4 end,
  GetRecipeID = function(i) return i end,
  GetRecipeInfo = function(id)
    if id == 1 then return nil end
    if id == 2 then return { reagents = { { itemID = 2447 } } } end
    if id == 3 then
      return {
        name = "Solid Extract",
        reagents = { 1337, "junk", { itemID = 77 }, { name = "no id field" } },
      }
    end
    if id == 4 then return { name = "Sparse Tincture" } end
    return nil
  end,
  GetOpenTradeSkillLine = function() return "Alchemy" end,
}
NodeTrailDB.recipes.alchemy = {}
NodeTrailDB.recipes.alchemyScanned = nil
local okScan15, r15 = pcall(ns.Recipes.Scan, ns.Recipes)
check(okScan15, "Test 15: scan does not error on malformed returns")
check(r15 == true, "Test 15: scan reports success on partial data")
local alch15 = NodeTrailDB.recipes.alchemy
check(alch15[1337] ~= nil and alch15[1337][1] == "Solid Extract", "Test 15: number reagent kept")
check(alch15[77] ~= nil and alch15[77][1] == "Solid Extract", "Test 15: itemID-table reagent kept")
check(alch15[2447] == nil, "Test 15: nameless recipe skipped (its reagent not mapped)")
local nk15 = 0
for _ in pairs(alch15) do nk15 = nk15 + 1 end
check(nk15 == 2, "Test 15: exactly two valid reagent slots (got " .. nk15 .. ")")
check(NodeTrailDB.recipes.alchemyScanned ~= nil, "Test 15: alchemyScanned set")
check(ns.Recipes._error == nil, "Test 15: Recipes no error field")

-- Test 16: a client with NEITHER API — the scan must fail cleanly, the
-- tooltip must drop the impossible instruction, and /nt status must say
-- why. (Must fail on the parent commit.)
C_TradeSkillUI = nil
NodeTrailDB.recipes.alchemy = {}
NodeTrailDB.recipes.alchemyScanned = nil
local okScan16, r16 = pcall(ns.Recipes.Scan, ns.Recipes)
check(okScan16, "Test 16: scan on an API-less client does not error")
check(r16 == false, "Test 16: scan returns false (nothing to scan)")
check(ns.Recipes._error == nil, "Test 16: no module error")
local okAp16, ap16 = pcall(function() return ns.Recipes:APIInfo() end)
check(okAp16 and ap16.available == false, "Test 16: APIInfo reports unavailable (truthful field)")
check(okAp16 and ap16.modern.exists == false and #ap16.legacy.calls == 0,
  "Test 16: APIInfo sees no modern module and no legacy globals")
local d16 = ns.Recipes._diag
check(d16 ~= nil and d16.path == "none", "Test 16: scan diag records path=none")
hover("Peacebloom")
local foundHint16 = false
local foundBlock16 = false
for _, l in ipairs(panelLines()) do
  if l == "Open Alchemy once to list recipe uses" then foundHint16 = true end
  if type(l) == "string" and l:find("^Picks: ") then foundBlock16 = true end
end
check(not foundHint16, "Test 16: tooltip drops the impossible instruction without an API")
check(foundBlock16, "Test 16: the rest of the block is still there")
local okSt16, stOut16 = captureStatus()
check(okSt16, "Test 16: status runs on an API-less client")
check(stOut16:find("unavailable", 1, true) ~= nil, "Test 16: status says the feature is unavailable")
check(stOut16:find("no trade skill API", 1, true) ~= nil, "Test 16: status says why")
check(stOut16:find("open your Alchemy window once", 1, true) == nil,
  "Test 16: status does not promise an impossible step")

-- ── Tests 17–19 (t_217033d4): never persist the recipe map without a
-- POSITIVE Alchemy identification ───────────────────────────────────────
-- The C_TradeSkillUI port (f5030c5) only refused to write when the open
-- profession was identifiable as a NON-alchemy name. When the live client
-- reports NO profession name at all — its probed calls all miss — the gate
-- was quietly skipped and whatever window was open (Cooking, Enchanting, …)
-- got written straight into the alchemy map, so every herb tooltip then
-- claimed "Alchemy: <a recipe that is not Alchemy>". Silent wrong data is
-- worse than a missing feature.
--   Test 17 and Test 18 MUST fail on f5030c5 (they pin the hole).
--   Test 19 is the positive path and must keep working (and passes because
--   the old code happened to write on a nil prof — the fix must not regress it).

local function countAlchKeys(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

-- COOKING. The scan must NOT write the map (it is not alchemy), must record
-- gated=profession, and the tooltip must keep the honest "open Alchemy" hint
-- — not claim a Cooking recipe as an Alchemy one.
C_TradeSkillUI = {
  GetAllRecipeIDs = function() return { 501, 502 } end,
  GetRecipeInfo = function(id)
    if id == 501 then
      return { name = "Spiced Wolf Meat", reagents = { { itemID = 765 } } }
    end
    if id == 502 then
      return { name = "Bread", reagents = { { itemID = 2447 } } }
    end
    return nil
  end,
  GetChildProfessionInfo = function() return { skillLineName = "Cooking" } end,
}
NodeTrailDB.recipes.alchemy = {}
NodeTrailDB.recipes.alchemyScanned = nil
local okScan17, r17 = pcall(ns.Recipes.Scan, ns.Recipes)
check(okScan17, "Test 17: scan does not error (Cooking open)")
check(r17 == false, "Test 17: scan reports nothing (not alchemy)")
check(countAlchKeys(NodeTrailDB.recipes.alchemy) == 0,
  "Test 17: NO alchemy map written for a Cooking window")
check(NodeTrailDB.recipes.alchemyScanned == nil, "Test 17: alchemyScanned stays nil")
local d17 = ns.Recipes._diag
check(d17 ~= nil and d17.gated == "profession", "Test 17: _diag.gated == 'profession'")
check(d17 ~= nil and d17.profession == "Cooking", "Test 17: _diag.profession == 'Cooking'")
hover("Silverleaf")
local hint17, wrong17 = false, false
for _, l in ipairs(panelLines()) do
  if l == "Open Alchemy once to list recipe uses" then
    hint17 = true
  end
  if type(l) == "string" and l:find("Alchemy: ", 1, true) ~= nil then
    wrong17 = true
  end
end
check(hint17, "Test 17: tooltip keeps the honest 'open Alchemy' hint")
check(not wrong17, "Test 17: tooltip does NOT claim a Cooking recipe as Alchemy")

-- Test 18: modern client where the open window CANNOT be identified at all —
-- no profession-naming call exists, but the recipe enumeration works. Must
-- NOT write, must record gated=unknown-profession, and /nt status must say
-- the profession could not be verified — not "open Alchemy once" forever and
-- not a false "API absent".
C_TradeSkillUI = {
  GetAllRecipeIDs = function() return { 601 } end,
  GetRecipeInfo = function(id)
    if id == 601 then
      return { name = "Mystery Brew", reagents = { { itemID = 765 } } }
    end
    return nil
  end,
  -- deliberately NO GetChildProfessionInfo / GetBaseProfessionInfo /
  -- GetOpenTradeSkillLine / any other profession-naming call.
}
NodeTrailDB.recipes.alchemy = {}
NodeTrailDB.recipes.alchemyScanned = nil
local okScan18, r18 = pcall(ns.Recipes.Scan, ns.Recipes)
check(okScan18, "Test 18: scan does not error (unknown profession)")
check(r18 == false, "Test 18: scan reports nothing (unverified)")
check(countAlchKeys(NodeTrailDB.recipes.alchemy) == 0,
  "Test 18: NO alchemy map written when the profession is unidentifiable")
check(NodeTrailDB.recipes.alchemyScanned == nil, "Test 18: alchemyScanned stays nil")
local d18 = ns.Recipes._diag
check(d18 ~= nil and d18.gated == "unknown-profession", "Test 18: _diag.gated == 'unknown-profession'")
check(d18 ~= nil and d18.path == "modern", "Test 18: _diag.path == 'modern'")
check(d18 ~= nil and (d18.recipeCount or 0) == 1,
  "Test 18: _diag records the recipe count it refused to persist")
local okSt18, stOut18 = captureStatus()
check(okSt18, "Test 18: status runs")
check(stOut18:find("could not be verified as Alchemy", 1, true) ~= nil,
  "Test 18: status says the profession could not be verified as Alchemy")
check(stOut18:find("reports no profession name", 1, true) ~= nil,
  "Test 18: status says the client reports no profession name")
check(stOut18:find("open your Alchemy window once", 1, true) == nil,
  "Test 18: status does NOT promise a step that no longer applies")
check(stOut18:find("unavailable on this client", 1, true) == nil,
  "Test 18: status does NOT falsely report the API as absent")

-- ALCHEMY. The scan must write the map — EXACTLY as the legacy stub's same
-- two recipes do (Test 10/Test 14) — set alchemyScanned, and leave no gated
-- diag. This is the fallback-prof vs primary-prof parity check.
C_TradeSkillUI = {
  GetAllRecipeIDs = function() return { 101, 102 } end,
  GetRecipeInfo = function(id)
    if id == 101 then
      return {
        name = "Minor Healing Potion",
        reagents = {
          { itemID = 2447 },
          { itemID = 765 },
          { itemID = 3371 },
        },
      }
    end
    if id == 102 then
      return {
        name = "Elixir of Lion's Strength",
        reagents = {
          { itemID = 2449 },
          { itemID = 765 },
          { itemID = 3371 },
        },
      }
    end
    return nil
  end,
  GetChildProfessionInfo = function() return { skillLineName = "Alchemy" } end,
  -- t_4ab7c230: these fixtures model recipes the character knows, so the
  -- gated Alchemy line keeps the content the pre-gate spec expected.
  IsRecipeProfessionLearned = function() return true end,
}
NodeTrailDB.recipes.alchemy = {}
NodeTrailDB.recipes.alchemyScanned = nil
local okScan19, r19 = pcall(ns.Recipes.Scan, ns.Recipes)
check(okScan19, "Test 19: scan does not error (Alchemy identified)")
check(r19 == true, "Test 19: scan reports success (positive Alchemy identification)")
local alch19 = NodeTrailDB.recipes.alchemy
check(alch19[2447] ~= nil and alch19[2447][1] == "Minor Healing Potion" and #alch19[2447] == 1,
  "Test 19: 2447 (Peacebloom) → Minor Healing Potion only")
check(alch19[765] ~= nil and #alch19[765] == 2
  and alch19[765][1] == "Elixir of Lion's Strength"
  and alch19[765][2] == "Minor Healing Potion",
  "Test 19: 765 (Silverleaf) → both recipes, sorted (same map as the legacy stub)")
check(alch19[2449] ~= nil and alch19[2449][1] == "Elixir of Lion's Strength",
  "Test 19: 2449 (Earthroot) → Elixir")
check(alch19[3371] ~= nil and #alch19[3371] == 2, "Test 19: 3371 → both recipes")
check(countAlchKeys(alch19) == 4, "Test 19: map has exactly the 4 reagents (same as the legacy stub)")
check(NodeTrailDB.recipes.alchemyScanned ~= nil, "Test 19: alchemyScanned set")
local d19 = ns.Recipes._diag
check(d19 ~= nil and d19.gated == nil and d19.profession == "Alchemy",
  "Test 19: diag records the positive Alchemy identification, not a gate")
hover("Peacebloom")
local line19 = false
for _, l in ipairs(panelLines()) do
  if l == "Alchemy: Minor Healing Potion" then
    line19 = true
  end
end
check(line19, "Test 19: tooltip shows the correct Alchemy line")

-- ── Tests 20–22 (t_81da8886): the live client just named the three
-- remaining defects ──────────────────────────────────────────────────
-- `/nt ttdiag` on Forever 16001: modern API present, Alchemy identified,
-- 196 recipes enumerated, nothing persisted.
--   * GetRecipeSchematic REQUIRES (recipeSpellID, isRecraft [,
--     recipeLevel]) — a one-arg call raises "bad argument #2 to '?'";
--   * the schematic carries reagents under
--     reagentSlotSchematics[i].reagents[j], not the flat keys the old
--     code read;
--   * HookScript on a script the client doesn't carry raises the usage
--     error and masked itself into T._error;
--   * only TRADE_SKILL_SHOW is a valid event on this client;
--   * a zero-reagent scan wrote an empty map and set alchemyScanned —
--     the feature silently empty with the hint gone.
--   Test 20 MUST fail on 91e2867 (it pins the arity + reagent-shape
--   hole). Test 21 and Test 22 pin the remaining two.

-- Test 20: the live contract, verbatim. The GetRecipeSchematic stub
-- RAISES unless called with exactly two arguments (the client's own
-- usage error), and returns a reagentSlotSchematics table. The scan
-- must produce the same itemID -> recipes map the legacy stub built in
-- Test 10/14.
local schemCalls = {}
C_TradeSkillUI = {
  GetAllRecipeIDs = function() return { 101, 102 } end,
  -- No reagents, no name: forces every recipe through the schematic.
  GetRecipeInfo = function() return nil end,
  GetRecipeSchematic = function(...)
    local n = select("#", ...)
    assert(n == 2, ("GetRecipeSchematic called with %d argument(s); client contract: GetRecipeSchematic(recipeSpellID, isRecraft [, recipeLevel])"):format(n))
    local id, second = select(1, ...), select(2, ...)
    schemCalls[#schemCalls + 1] = { id = id, second = second }
    if id == 101 then
      return {
        name = "Minor Healing Potion",
        reagentSlotSchematics = {
          { reagents = { { itemID = 2447, quantity = 2 } } },
          { reagents = { { itemID = 765, quantity = 2 } } },
          { reagents = { { itemID = 3371, quantity = 1 } } },
        },
      }
    end
    if id == 102 then
      return {
        name = "Elixir of Lion's Strength",
        reagentSlotSchematics = {
          { reagents = { { itemID = 2449, quantity = 1 } } },
          { reagents = { { itemID = 765, quantity = 2 } } },
          { reagents = { { itemID = 3371, quantity = 1 } } },
        },
      }
    end
    return nil
  end,
  GetChildProfessionInfo = function() return { skillLineName = "Alchemy" } end,
  -- t_4ab7c230: these fixtures model recipes the character knows, so the
  -- gated Alchemy line keeps the content the pre-gate spec expected.
  IsRecipeProfessionLearned = function() return true end,
}
NodeTrailDB.recipes.alchemy = {}
NodeTrailDB.recipes.alchemyScanned = nil
local okScan20, r20 = pcall(ns.Recipes.Scan, ns.Recipes)
check(okScan20, "Test 20: scan does not error (schematic shape)")
check(r20 == true, "Test 20: scan reports success (reagents found)")
local alch20 = NodeTrailDB.recipes.alchemy
check(alch20[2447] ~= nil and #alch20[2447] == 1 and alch20[2447][1] == "Minor Healing Potion",
  "Test 20: 2447 → Minor Healing Potion (reagentSlotSchematics walked)")
check(alch20[765] ~= nil and #alch20[765] == 2 and alch20[765][1] == "Elixir of Lion's Strength",
  "Test 20: 765 → both recipes, sorted (same map as the legacy stub)")
check(alch20[2449] ~= nil and alch20[2449][1] == "Elixir of Lion's Strength",
  "Test 20: 2449 → Elixir")
check(countAlchKeys(alch20) == 4, "Test 20: exactly 4 reagent keys (got " .. countAlchKeys(alch20) .. ")")
check(NodeTrailDB.recipes.alchemyScanned ~= nil, "Test 20: alchemyScanned set (a complete scan)")
local d20 = ns.Recipes._diag
check(d20 ~= nil and d20.gated == nil, "Test 20: no gate recorded on a complete scan")
check(d20 ~= nil and (d20.reagentSlots or 0) == 6, "Test 20: _diag.reagentSlots == 6")
check(d20 ~= nil and d20.error == nil, "Test 20: _diag.error is nil (no schematic call failed)")
check(#schemCalls == 2, "Test 20: GetRecipeSchematic called once per recipe (got " .. #schemCalls .. ")")
local args20ok = true
for _, c in ipairs(schemCalls) do
  if c.second ~= false then args20ok = false end
end
check(args20ok, "Test 20: every GetRecipeSchematic call carried isRecraft=false (the live contract)")
check(ns.Recipes._error == nil, "Test 20: Recipes no error")
hover("Peacebloom")
local f20a = false
for _, l in ipairs(panelLines()) do
  if l == "Alchemy: Minor Healing Potion" then f20a = true end
end
check(f20a, "Test 20: Peacebloom tooltip line (schematic reagents)")
hover("Silverleaf")
local f20b, f20c = false, false
for _, l in ipairs(panelLines()) do
  if l == "Alchemy: Elixir of Lion's Strength, Minor Healing Potion" then f20b = true end
  if l == "Open Alchemy once to list recipe uses" then f20c = true end
end
check(f20b, "Test 20: Silverleaf tooltip line (schematic reagents)")
check(not f20c, "Test 20: hint gone after a complete modern scan")

-- Test 21 (t_f4ff9ea6): a client whose HookScript REJECTS everything — the
-- live client raised a usage error on OnTooltipSetItem. Enable must not care:
-- it installs NO script on the tooltip at all, so a rejected hook can neither
-- break it nor leave a "skipped script" to explain. _error stays nil.
local origHook = GameTooltip.HookScript
GameTooltip.hooks = {}
GameTooltip.HookScript = function()
  error("bad argument #2 to '?' (Usage: local success = self:HookScript(scriptTypeName, script[, bindingType]))")
end
ns.Tooltip._enabled = false
ns.Tooltip._error = nil
local okEn21, enErr21 = pcall(ns.Tooltip.Enable, ns.Tooltip)
check(okEn21, "Test 21: Enable succeeds on a hook-hostile client: " .. tostring(enErr21))
local hooks21 = 0
for _, list in pairs(GameTooltip.hooks) do hooks21 = hooks21 + #list end
check(hooks21 == 0, "Test 21: no script was installed on the tooltip (got " .. hooks21 .. ")")
check(ns.Tooltip._error == nil, "Test 21: Enable wrote no T._error")
local diagCap = {}
DEFAULT_CHAT_FRAME.AddMessage = function(_, m) diagCap[#diagCap + 1] = tostring(m) end
local okDiag21, dErr21 = pcall(ns.Tooltip.Diag, ns.Tooltip)
DEFAULT_CHAT_FRAME.AddMessage = origAdd
check(okDiag21, "Test 21: Tooltip:Diag runs: " .. tostring(dErr21))
local diagText = table.concat(diagCap, "\n")
check(diagText:find("skipped scripts", 1, true) == nil,
  "Test 21: the diag claims no skipped script (there is none to skip)")
-- Events: the live client only knows TRADE_SKILL_SHOW; everything else is
-- refused at registration time.
unknownEvents = {
  TRADE_SKILL_UPDATE = true,
  TRADE_SKILLS_SHOW = true,
  TRADE_SKILLS_UPDATE = true,
}
ns.Recipes._enabled = false
local okRe21, reErr21 = pcall(ns.Recipes.Enable, ns.Recipes)
check(okRe21, "Test 21: Recipes:Enable does not error: " .. tostring(reErr21))
local ev21 = ns.Recipes._events
check(ev21 and ev21.TRADE_SKILL_SHOW == true, "Test 21: TRADE_SKILL_SHOW registered (valid)")
check(ev21 and ev21.TRADE_SKILL_UPDATE == "invalid event",
  "Test 21: TRADE_SKILL_UPDATE recorded as 'invalid event' (not registered, not an error string)")
check(ev21 and ev21.TRADE_SKILLS_SHOW == "invalid event",
  "Test 21: TRADE_SKILLS_SHOW recorded as 'invalid event'")
check(ev21 and ev21.TRADE_SKILLS_UPDATE == "invalid event",
  "Test 21: TRADE_SKILLS_UPDATE recorded as 'invalid event'")
unknownEvents = {}
GameTooltip.HookScript = origHook

-- Test 22: the zero-reagent scan on the live client — 196 recipes read,
-- no reagent slot answered. Must NOT write the map, must NOT set
-- alchemyScanned, and status must say what happened instead of claiming
-- success (or re-promising a step that already ran).
C_TradeSkillUI = {
  GetAllRecipeIDs = function() return { 201, 202, 203 } end,
  GetRecipeInfo = function() return nil end,
  GetRecipeSchematic = function(...)
    return {
      name = "Recipe " .. tostring(select(1, ...)),
      -- Slots exist but are EMPTY — the shape matched, the data did
      -- not arrive.
      reagentSlotSchematics = { { reagents = {} } },
    }
  end,
  GetChildProfessionInfo = function() return { skillLineName = "Alchemy" } end,
  -- t_4ab7c230: these fixtures model recipes the character knows, so the
  -- gated Alchemy line keeps the content the pre-gate spec expected.
  IsRecipeProfessionLearned = function() return true end,
}
NodeTrailDB.recipes.alchemy = {}
NodeTrailDB.recipes.alchemyScanned = nil
local okScan22, r22 = pcall(ns.Recipes.Scan, ns.Recipes)
check(okScan22, "Test 22: scan does not error")
check(r22 == false, "Test 22: zero-reagent scan is NOT reported as complete")
check(countAlchKeys(NodeTrailDB.recipes.alchemy) == 0, "Test 22: no alchemy map persisted")
check(NodeTrailDB.recipes.alchemyScanned == nil, "Test 22: alchemyScanned stays nil")
local d22 = ns.Recipes._diag
check(d22 ~= nil and d22.gated == "no-reagents", "Test 22: _diag.gated == 'no-reagents'")
check(d22 ~= nil and d22.path == "modern", "Test 22: _diag.path == 'modern'")
check(d22 ~= nil and (d22.recipesRead or 0) == 3, "Test 22: _diag records recipesRead == 3")
check(d22 ~= nil and (d22.reagentSlots or 0) == 0, "Test 22: _diag.reagentSlots == 0")
check(d22 ~= nil and d22.error ~= nil, "Test 22: _diag.records the reason")
check(ns.Recipes._error == nil, "Test 22: no module error (it is a recorded state, not a failure)")
local okSt22, stOut22 = captureStatus()
check(okSt22, "Test 22: status runs")
check(stOut22:find("no reagents", 1, true) ~= nil,
  "Test 22: status says the scan found no reagents")
check(stOut22:find("scanned", 1, true) == nil,
  "Test 22: status does NOT claim the scan succeeded")
check(stOut22:find("open your Alchemy window once", 1, true) == nil,
  "Test 22: status does NOT re-promise a step that already ran")
hover("Peacebloom")
local hint22, alt22 = false, false
for _, l in ipairs(panelLines()) do
  if l == "Open Alchemy once to list recipe uses" then hint22 = true end
  if type(l) == "string" and l:find("no reagents", 1, true) ~= nil then alt22 = true end
end
check(not hint22, "Test 22: tooltip does NOT re-promise 'Open Alchemy once'")
check(alt22, "Test 22: tooltip says the scan found no reagents")

if failed > 0 then
  os.exit(1)
else
  print("tooltip_spec: ok")
end

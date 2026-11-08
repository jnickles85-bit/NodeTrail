-- t_04c983cc — the Alchemy line must list only what THIS character can craft,
-- and a drop the client cannot name must not print as a bare item id.
--
-- Mightie, hovering Briarthorn on the herbalist:
--
--     Briarthorn            100%
--     Swiftthistle           56%
--     item 249399             4%
--     Picks: 25 (all characters)
--     Alchemy: Elixir of Wisdom, Frenzy Potion, Lesser Discolored Healing
--              Potion, Lesser Frenzy Potion, +3 more
--
-- "alchemy tooltip is giving info for crafts i cant do yet." Two separate
-- lies, both pinned here:
--
--   1. every recipe the client enumerated was listed as available, whatever
--      its numAvailable / requiredSkill said;
--   2. a drop id with no name in our table printed `item 249399` — a raw
--      number standing where a name belongs.
--
-- Every check reads the PANEL's own rendered rows (the block is NodeTrail's
-- frame; nothing is written into GameTooltip), so these are behavioural:
-- on the parent commit the uncraftable names simply ARE in the line and the
-- tail/label rows are absent.
--
-- The availability is captured by the scan (Data/Recipes.lua) and only
-- FILTERED by the panel — this spec also proves a re-scan refreshes it, which
-- is what stops a level-up from keeping yesterday's gate until a restart.

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
F.install({ width = 1920, height = 1080 })

local pkg = {}
local function loadFile(path)
  local f = assert(loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. path))
  f("MightiePack", pkg)
end

loadFile("locale/enUS.lua")
loadFile("Config.lua")
loadFile("Data/Recorder.lua")
loadFile("Data/HerbData.lua")
loadFile("Data/Profession.lua")
loadFile("Data/Recipes.lua")
loadFile("UI/TooltipPanel.lua")
loadFile("UI/Tooltip.lua")
loadFile("Core.lua")

local ns = pkg.NodeTrail

time = time or os.time
CopyTable = function(t)
  local c = {}
  for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end
  return c
end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
GetSpellInfo = function(id)
  local map = { [2366] = "Herb Gathering", [2259] = "Alchemy" }
  return map[id]
end
UnitExists = function() return false end
UIParent = {}
WorldFrame = {}

-- ── the item client ───────────────────────────────────────────────────────
-- Our own herb table names the classic ids; 249399 is the id from the report
-- and this client knows NOTHING about it (GetItemInfo answers nil), which is
-- exactly the case the panel has to label honestly.
local ITEM_NAMES = {
  [2450] = "Briarthorn",
  [2452] = "Swiftthistle",
  [2447] = "Peacebloom",
  [765] = "Silverleaf",
}
GetItemInfo = function(id)
  return ITEM_NAMES[id]
end

-- ── the character ─────────────────────────────────────────────────────────
-- An herbalist/alchemist at Alchemy 75. The rank is what the requiredSkill
-- fallback compares against.
local skillLines = {
  { name = "Herbalism", rank = 300 },
  { name = "Alchemy", rank = 75 },
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
_G.GameTooltip = GameTooltip

local function panelLines()
  return ns.TooltipPanel:TextLines()
end

local function hover(name)
  GameTooltip.lines = { name, "Herbalism" }
  GameTooltip:SyncFirstLine()
  GameTooltip.shown = true
  ns.Tooltip:Poll(GameTooltip)
end

local function findLine(predicate)
  for _, l in ipairs(panelLines()) do
    if predicate(l) then return l end
  end
  return nil
end

local function alchemyLine()
  return findLine(function(l)
    return type(l) == "string" and l:sub(1, 9) == "Alchemy: "
  end)
end

-- The Alchemy group is the line that opens with the label plus every
-- continuation row the panel wrapped it into; a check for "absent" has to
-- look at the whole group, never just its first row. Continuations are joined
-- back with a single space, so the group reads as the one sentence it is.
local function alchemyText()
  local out, started = {}, false
  for _, l in ipairs(panelLines()) do
    if not started and type(l) == "string" and l:sub(1, 9) == "Alchemy: " then
      started = true
      out[#out + 1] = l
    elseif started and type(l) == "string" and l:sub(1, 2) == "  " then
      out[#out + 1] = (l:gsub("^%s+", ""))
    elseif started then
      break
    end
  end
  return table.concat(out, " ")
end

-- ── the fixture: one herb, five recipes, only some craftable ──────────────
-- Briarthorn (2450) is the herb from the report. Its recipe set is the one in
-- the screenshot; numAvailable is the client's own "can be made now" count.
local recipes = {
  { name = "Elixir of Wisdom", numAvailable = 3 },
  { name = "Frenzy Potion", numAvailable = 0 },
  { name = "Lesser Discolored Healing Potion", numAvailable = 2 },
  { name = "Lesser Frenzy Potion", numAvailable = 0 },
  { name = "Swiftness Potion", numAvailable = 0 },
}
local mode = "numAvailable" -- "numAvailable" | "requiredSkill" | "none"

local function installClient()
  C_TradeSkillUI = {
    GetAllRecipeIDs = function()
      local ids = {}
      for i = 1, #recipes do ids[i] = i end
      return ids
    end,
    GetRecipeInfo = function(id)
      local r = recipes[id]
      if not r then return nil end
      local info = {
        name = r.name,
        reagents = { { itemID = 2450 }, { itemID = 3371 } },
      }
      if mode == "numAvailable" and r.numAvailable ~= nil then
        info.numAvailable = r.numAvailable
      elseif mode == "requiredSkill" and r.requiredSkill ~= nil then
        info.requiredSkill = r.requiredSkill
      end
      return info
    end,
    GetChildProfessionInfo = function() return { skillLineName = "Alchemy" } end,
  }
end

local function rescan()
  NodeTrailDB.recipes.alchemy = {}
  NodeTrailDB.recipes.alchemyScanned = nil
  local ok, r = pcall(ns.Recipes.Scan, ns.Recipes)
  check(ok, "scan does not raise (" .. tostring(r) .. ")")
  return r
end

local function captureDiag()
  local cap = {}
  local orig = DEFAULT_CHAT_FRAME.AddMessage
  DEFAULT_CHAT_FRAME.AddMessage = function(_, m) cap[#cap + 1] = tostring(m) end
  local ok = pcall(ns.Tooltip.Diag, ns.Tooltip)
  DEFAULT_CHAT_FRAME.AddMessage = orig
  return ok, table.concat(cap, "\n")
end

local function captureRecipeDiag()
  local cap = {}
  local orig = DEFAULT_CHAT_FRAME.AddMessage
  DEFAULT_CHAT_FRAME.AddMessage = function(_, m) cap[#cap + 1] = tostring(m) end
  local ok = pcall(ns.Recipes.Diag, ns.Recipes)
  DEFAULT_CHAT_FRAME.AddMessage = orig
  return ok, table.concat(cap, "\n")
end

-- ═══ 1. the list is gated on what he can craft NOW ════════════════════════
installClient()
local okScan1, r1 = pcall(ns.Recipes.Scan, ns.Recipes)
check(okScan1, "1: scan does not raise (" .. tostring(r1) .. ")")
check(r1 == true, "1: the modern scan saved the map")

local alch1 = NodeTrailDB.recipes.alchemy
check(alch1[2450] ~= nil, "1: Briarthorn is a reagent of the scanned recipes")
check(NodeTrailDB.recipes.alchemyFilterable == true,
  "1: the scan recorded that the client DID answer availability")
check(NodeTrailDB.recipes.alchemyAvailability == "numAvailable",
  "1: the field that answered is recorded (numAvailable)")

hover("Briarthorn")
local line1 = alchemyLine() or ""
check(line1:find("Elixir of Wisdom", 1, true) ~= nil,
  "1: a craftable recipe IS listed (" .. line1 .. ")")
check(line1:find("Lesser Discolored Healing Potion", 1, true) ~= nil,
  "1: the second craftable recipe IS listed (" .. line1 .. ")")
check(alchemyText():find("Frenzy Potion", 1, true) == nil,
  "1: an UNCRAFTABLE recipe is not listed as available (" .. alchemyText() .. ")")
check(alchemyText():find("Swiftness Potion", 1, true) == nil,
  "1: every uncraftable recipe is withheld, not just the first (" .. alchemyText() .. ")")

-- ═══ 2. the withheld ones are COUNTED, never silently dropped ═════════════
check(alchemyText():find("+3 more you can't make yet", 1, true) ~= nil,
  "2: the excluded count is the tail (" .. alchemyText() .. ")")
check(alchemyText() == "Alchemy: Elixir of Wisdom, Lesser Discolored Healing Potion, "
  .. "+3 more you can't make yet",
  "2: the line is exactly the craftable recipes + the tail (" .. alchemyText() .. ")")
-- The tail is its own rendered row when the panel wraps (the group reads as
-- one sentence after the join above), so it is on screen either way.
check(findLine(function(l) return type(l) == "string" and l:find("+3 more you can't make yet", 1, true) ~= nil end) ~= nil,
  "2: the tail is rendered (on its own row if the line wrapped)")

-- ═══ 3. a re-scan refreshes the gate (the level-up case) ══════════════════
-- The same herb, the same client, one recipe now craftable: nothing may be
-- cached from scan 1 — "a character who levels up must not keep the old gate
-- until a restart".
recipes[2].numAvailable = 1 -- Frenzy Potion
local okScan3, r3 = pcall(ns.Recipes.Scan, ns.Recipes)
check(okScan3 and r3 == true, "3: the second scan succeeds")
hover("Briarthorn")
local text3 = alchemyText()
check(text3:find("Frenzy Potion", 1, true) ~= nil,
  "3: a recipe that became craftable appears after the re-scan (" .. text3 .. ")")
check(text3:find("+2 more you can't make yet", 1, true) ~= nil,
  "3: the excluded tail is recomputed, not stale (" .. text3 .. ")")
check(text3 == "Alchemy: Elixir of Wisdom, Frenzy Potion, Lesser Discolored Healing Potion, "
  .. "+2 more you can't make yet",
  "3: exactly the new craftable set (" .. text3 .. ")")

-- ═══ 4. all withheld → say none, do not invent a list ═════════════════════
for _, r in ipairs(recipes) do r.numAvailable = 0 end
installClient()
local okScan4, r4 = pcall(ns.Recipes.Scan, ns.Recipes)
check(okScan4 and r4 == true, "4: the scan succeeds with nothing craftable")
hover("Briarthorn")
local line4 = alchemyLine() or ""
check(line4:find("none you can make yet", 1, true) ~= nil,
  "4: with nothing craftable the line says so (" .. line4 .. ")")
check(line4:find("Elixir of Wisdom", 1, true) == nil,
  "4: no recipe is advertised as craftable (" .. line4 .. ")")

-- ═══ 5. requiredSkill against the character's rank (the numAvailable-less
--         client) ═════════════════════════════════════════════════════════
mode = "requiredSkill"
recipes = {
  { name = "Elixir of Wisdom", requiredSkill = 50 },
  { name = "Frenzy Potion", requiredSkill = 150 },
  { name = "Lesser Discolored Healing Potion", requiredSkill = 75 },
  { name = "Lesser Frenzy Potion", requiredSkill = 76 },
}
installClient()
local okScan5, r5 = pcall(ns.Recipes.Scan, ns.Recipes)
check(okScan5 and r5 == true, "5: the requiredSkill client scans (" .. tostring(r5) .. ")")
check(NodeTrailDB.recipes.alchemyAvailability == "requiredSkill",
  "5: the diag records requiredSkill as the answering field")
hover("Briarthorn")
local text5 = alchemyText()
check(text5:find("Elixir of Wisdom", 1, true) ~= nil,
  "5: requiredSkill 50 <= rank 75 is craftable (" .. text5 .. ")")
check(text5:find("Lesser Discolored Healing Potion", 1, true) ~= nil,
  "5: requiredSkill 75 == rank 75 is craftable (" .. text5 .. ")")
check(text5:find("Frenzy Potion", 1, true) == nil,
  "5: requiredSkill 150 > rank 75 is withheld (" .. text5 .. ")")
check(text5:find("Lesser Frenzy Potion", 1, true) == nil,
  "5: requiredSkill 76 > rank 75 is withheld (" .. text5 .. ")")
check(text5:find("+2 more you can't make yet", 1, true) ~= nil,
  "5: the excluded count is the requiredSkill misses (" .. text5 .. ")")

-- A level-up (rank 200) must release them on the next scan.
skillLines[2].rank = 200
local okScan5b, r5b = pcall(ns.Recipes.Scan, ns.Recipes)
check(okScan5b and r5b == true, "5b: the scan after the level-up succeeds")
hover("Briarthorn")
local text5b = alchemyText()
check(text5b:find("Frenzy Potion", 1, true) ~= nil,
  "5b: rank 200 releases the requiredSkill-150 recipe (" .. text5b .. ")")
check(text5b:find("Lesser Frenzy Potion", 1, true) ~= nil,
  "5b: rank 200 releases the requiredSkill-76 recipe (" .. text5b .. ")")
check(text5b:find("can't make yet", 1, true) == nil,
  "5b: nothing excluded → no tail (" .. text5b .. ")")
skillLines[2].rank = 75

-- ═══ 6. the client exposes NO availability signal: draw NOTHING, explain once
--         in the options panel (t_4ab7c230) ═════════════════════════════════
mode = "none"
recipes = {
  { name = "Elixir of Wisdom" },
  { name = "Frenzy Potion" },
}
installClient()
local okScan6, r6 = pcall(ns.Recipes.Scan, ns.Recipes)
check(okScan6 and r6 == true, "6: the no-availability client scans (" .. tostring(r6) .. ")")
check(NodeTrailDB.recipes.alchemyFilterable == false,
  "6: nothing filterable is claimed")
check(NodeTrailDB.recipes.alchemyAvailability == "none",
  "6: the scan records that availability was not available")
hover("Briarthorn")
check(alchemyLine() == nil,
  "6: no Alchemy line is drawn when no signal answered (got " .. tostring(alchemyLine()) .. ")")
check(findLine(function(l) return l == "recipes (not filtered by skill)" end) == nil,
  "6: the unfiltered list is not printed with a caveat either")
check(findLine(function(l)
    return type(l) == "string" and l:find("Alchemy:", 1, true) ~= nil
  end) == nil,
  "6: nothing in the block advertises an Alchemy craft")
local okHint6, hint6, why6 = pcall(function() return ns.Recipes:HiddenHint() end)
check(okHint6, "6: the options panel reason exists (" .. tostring(hint6) .. ")")
check(type(hint6) == "string" and hint6:find("hidden", 1, true) ~= nil,
  "6: the options panel has the one short reason (got " .. tostring(hint6) .. ")")
check(type(hint6) == "string" and hint6:find("no recipe-availability API", 1, true) ~= nil,
  "6: the reason names the client API this version lacks (got " .. tostring(hint6) .. ")")

-- The diag says it once, and says which signal was missing.
local okRD6, rd6 = captureRecipeDiag()
check(okRD6, "6: /nt ttdiag (recipes half) runs")
check(rd6:find("availability: none", 1, true) ~= nil,
  "6: the diag carries an availability line (got " .. rd6 .. ")")
check(rd6:find("no recipe-availability signal answered", 1, true) ~= nil,
  "6: the diag names the missing signal")
check(rd6:find("Alchemy line is hidden", 1, true) ~= nil,
  "6: the diag says the line is hidden, not labelled")
check(rd6:find("not filtered by skill", 1, true) == nil,
  "6: the old unfiltered caveat is gone")

-- ═══ 7. `item 249399` — the client's name, or an honest label ═════════════
-- 25 gathers of Briarthorn, one of which also dropped the unknown 249399:
-- that is the 4% row from the report.
for i = 1, 25 do
  local items = { { id = 2450, count = 1 } }
  if i == 1 then
    table.insert(items, { id = 249399, count = 1 })
  end
  ns.RecordHerb(100, 0.5, 0.5, items)
end
hover("Briarthorn")
local unknownRow = findLine(function(l)
  return type(l) == "string" and l:find("249399", 1, true) ~= nil
end)
check(unknownRow ~= nil, "7: the 249399 drop row is rendered at all")
check(unknownRow == "unknown item 249399 | 4%",
  "7: an id the client cannot name prints as `unknown item <id>`, not a bare id ("
    .. tostring(unknownRow) .. ")")
local bareRow = findLine(function(l)
  return type(l) == "string" and l:match("^item %d+") ~= nil
end)
check(bareRow == nil, "7: no row prints a bare `item <id>` (" .. tostring(bareRow) .. ")")

-- And the diag asks the client the same question.
local okTd7, td7 = captureDiag()
check(okTd7, "7: /nt ttdiag runs")
check(td7:find("herb item: item id: 249399 -> GetItemInfo answered nothing", 1, true) ~= nil,
  "7: the diag resolves the unknown id and records what the client answered ("
    .. td7 .. ")")

-- A client that DOES know the id must be used instead of the label.
ITEM_NAMES[249399] = "Pinecone of Doom"
hover("Briarthorn")
local namedRow = findLine(function(l)
  return type(l) == "string" and l:find("Pinecone of Doom", 1, true) ~= nil
end)
check(namedRow == "Pinecone of Doom | 4%",
  "7b: the client's own name is used when it has one (" .. tostring(namedRow) .. ")")
local okTd7b, td7b = captureDiag()
check(okTd7b, "7b: /nt ttdiag runs")
check(td7b:find('herb item: item id: 249399 -> "Pinecone of Doom" (GetItemInfo)', 1, true) ~= nil,
  "7b: the diag quotes the name the client answered")
ITEM_NAMES[249399] = nil

-- ═══ 8. one source of truth: the panel asks Recipes, it does not compute ══
-- The panel's gate must be the persisted scan state. Flip the stored flag and
-- the panel follows with NO new scan: that is only possible if nothing in
-- UI/Tooltip.lua recomputes availability from the client.
mode = "numAvailable"
recipes = {
  { name = "Elixir of Wisdom", numAvailable = 1 },
  { name = "Frenzy Potion", numAvailable = 0 },
}
installClient()
local okScan8, r8 = pcall(ns.Recipes.Scan, ns.Recipes)
check(okScan8 and r8 == true, "8: the scan succeeds")
hover("Briarthorn")
check((alchemyLine() or ""):find("+1 more you can't make yet", 1, true) ~= nil,
  "8: the scanned gate is applied (" .. tostring(alchemyLine()) .. ")")
local craft8 = NodeTrailDB.recipes.alchemyCraft
if type(craft8) == "table" then
  craft8["Frenzy Potion"] = true
  hover("Briarthorn")
  local line8 = alchemyLine() or ""
  check(line8:find("Frenzy Potion", 1, true) ~= nil,
    "8: the panel reads the persisted gate — no second availability calculation ("
      .. line8 .. ")")
else
  check(false, "8: the scan persisted no availability map (alchemyCraft), so the panel cannot be reading one")
end

if failed > 0 then
  io.stderr:write(failed .. " alchemy skill-gate check(s) failed\n")
  os.exit(1)
end
print("alchemy_skill_gate_spec: ok")

-- t_4ab7c230 — the Alchemy line must be gated on a REAL signal, and when the
-- client has none, it must be ABSENT (not an unfiltered list with a caveat).
--
-- Mightie, hovering Briarthorn:
--
--     Alchemy: Elixir of Wisdom, Frenzy Potion, Lesser Discolored Healing
--              Potion, Lesser Frenzy Potion, +3 more
--     recipes (not filtered by skill)
--
-- The fallback was honest but useless: eight crafts he cannot make. Forever
-- 16001's client carries the signals the first pass never asked for —
--
--   C_TradeSkillUI.GetCraftableCount(recipeSpellID [, recipeLevel]) -> numAvailable
--   C_TradeSkillUI.IsRecipeProfessionLearned(recipeID)              -> boolean
--   recipeInfo.requiredSkillRank
--
-- (all three usage/field strings are in Wow.exe build 16001) — so this spec
-- pins each of them as a gate, in the order Data/Recipes.lua resolves them,
-- pins the HIDE path for a client that answers none of them, and pins the raw
-- `/nt recipediag` output the card asks for (one craftable + one not).
--
-- Every panel assertion reads the PANEL's own rendered rows (NodeTrail's
-- frame; nothing is written into GameTooltip). On the parent commit the line
-- lists all four recipes and there is no hidden-list note, so the new checks
-- fail behaviourally (no traceback).

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

SlashCmdList = {}

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
CopyTable = function(t)
  local c = {}
  for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end
  return c
end
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end }
GetSpellInfo = function(id)
  local map = { [2366] = "Herb Gathering", [2259] = "Alchemy" }
  return map[id]
end
UnitExists = function() return false end
UIParent = {}
WorldFrame = {}

local ITEM_NAMES = {
  [2450] = "Briarthorn",
  [2452] = "Swiftthistle",
  [2447] = "Peacebloom",
  [765] = "Silverleaf",
}
GetItemInfo = function(id) return ITEM_NAMES[id] end

-- The character: an herbalist at Alchemy 75. Rank 75 is what the
-- requiredSkillRank comparison reads (Elixir of Wisdom requires 50 and is
-- still not craftable in the fixture — it is UNLEARNED, which is exactly the
-- live case the card describes).
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

-- The module boot path registers /nt (Core.lua does it in ns.Enable). It needs
-- the client globals above (time(), DEFAULT_CHAT_FRAME), exactly like login.
local okEnable, enableErr = true, nil
if type(ns.Enable) == "function" then
  okEnable, enableErr = pcall(ns.Enable)
end

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

local function clearChat()
  for i = #chat, 1, -1 do chat[i] = nil end
end

local function capture(fn, ...)
  clearChat()
  local ok, err = pcall(fn, ...)
  return ok, table.concat(chat, "\n"), err
end

-- ── the fixture ───────────────────────────────────────────────────────────
-- All four are Briarthorn recipes. 101 and 102 are UNLEARNED; 103 is learned
-- and at the character's rank; 104 is learned but above it (90 > 75).
local recipes = {
  { id = 101, name = "Elixir of Wisdom", requiredSkillRank = 50, learned = false, count = 0, ability = 9001 },
  { id = 102, name = "Frenzy Potion", requiredSkillRank = 150, learned = false, count = 0, ability = 9002 },
  { id = 103, name = "Lesser Discolored Healing Potion", requiredSkillRank = 75, learned = true, count = 3, ability = 9003 },
  { id = 104, name = "Swiftness Potion", requiredSkillRank = 90, learned = true, count = 0, ability = 9004 },
}
local scanCalls = 0

-- mode: "count" | "learned" | "skill" | "none" | "hostile"
--   count   — only GetCraftableCount answers
--   learned — only IsRecipeProfessionLearned + requiredSkillRank answer
--   skill   — only requiredSkillRank answers (no learned flag, no count)
--   none    — no availability signal at all
--   hostile — every recipe call raises (the diag must still print)
local mode = "learned"

local function installClient()
  local client = {
    GetAllRecipeIDs = function()
      scanCalls = scanCalls + 1
      local ids = {}
      for _, r in ipairs(recipes) do ids[#ids + 1] = r.id end
      return ids
    end,
    GetChildProfessionInfo = function() return { skillLineName = "Alchemy" } end,
    GetRecipeSchematic = function(id, isRecraft)
      for _, r in ipairs(recipes) do
        if r.id == id then
          return {
            recipeID = id,
            name = r.name,
            requiredSkillRank = r.requiredSkillRank,
            skillLineAbilityID = r.ability,
            reagentSlotSchematics = {
              { reagents = { { itemID = 2450, quantity = 1 } } },
            },
          }
        end
      end
      return nil
    end,
  }
  if mode == "hostile" then
    client.GetRecipeInfo = function() error("boom: GetRecipeInfo") end
    client.GetRecipeSchematic = function() error("boom: GetRecipeSchematic") end
    C_TradeSkillUI = client
    return
  end
  client.GetRecipeInfo = function(id)
    for _, r in ipairs(recipes) do
      if r.id == id then
        local info = {
          name = r.name,
          reagents = { { itemID = 2450 }, { itemID = 3371 } },
          skillLineAbilityID = r.ability,
        }
        if mode == "learned" or mode == "skill" or mode == "live" then
          info.requiredSkillRank = r.requiredSkillRank
        end
        return info
      end
    end
    return nil
  end
  if mode == "count" or mode == "live" then
    client.GetCraftableCount = function(id)
      for _, r in ipairs(recipes) do
        if r.id == id then return r.count end
      end
      return 0
    end
  end
  if mode == "learned" or mode == "live" then
    client.IsRecipeProfessionLearned = function(id)
      for _, r in ipairs(recipes) do
        if r.id == id then return r.learned end
      end
      return false
    end
  end
  C_TradeSkillUI = client
end

local function scan()
  local ok, r = pcall(ns.Recipes.Scan, ns.Recipes)
  check(ok, "scan does not raise (" .. tostring(r) .. ")")
  return ok and r == true
end

local function resetDB()
  NodeTrailDB = { recipes = { alchemy = {} } }
  -- The recipe-uses line is parked OFF in the product (Config.showAlchemyUses =
  -- false). These specs exercise the gate behind it, so they switch it back on:
  -- parked is a default, not a deletion, and the gate must stay covered.
  NodeTrailDB.profile = { showAlchemyUses = true }
end

-- ═══ 1. GetCraftableCount is a gate (the client's own "can I make it") ═════
check(okEnable, "module boot (ns.Enable) does not raise: " .. tostring(enableErr))
mode = "count"
installClient()
resetDB()
check(scan(), "1: the GetCraftableCount client scans")
check(NodeTrailDB.recipes.alchemyFilterable == true,
  "1: the count answered, so the list is filterable")
check(NodeTrailDB.recipes.alchemyAvailability == "GetCraftableCount",
  "1: the answering signal is recorded (got " .. tostring(NodeTrailDB.recipes.alchemyAvailability) .. ")")
hover("Briarthorn")
local text1 = alchemyText()
check(text1 == "Alchemy: Lesser Discolored Healing Potion, +3 more you can't make yet",
  "1: only the craftable recipe is listed + the withheld tail (got " .. text1 .. ")")
check(text1:find("Elixir of Wisdom", 1, true) == nil,
  "1: a recipe with count 0 is not advertised")
check(text1:find("recipes (not filtered by skill)", 1, true) == nil,
  "1: the old caveat is gone")

-- ═══ 2. IsRecipeProfessionLearned is a gate — the live client's decisive
--         signal, because GetAllRecipeIDs enumerates UNLEARNED recipes too ══
mode = "learned"
installClient()
resetDB()
check(scan(), "2: the learned-flag client scans")
check(NodeTrailDB.recipes.alchemyAvailability == "IsRecipeProfessionLearned",
  "2: the learned flag is the recorded signal (got "
    .. tostring(NodeTrailDB.recipes.alchemyAvailability) .. ")")
local craft2 = NodeTrailDB.recipes.alchemyCraft
check(type(craft2) == "table" and craft2["Elixir of Wisdom"] == false,
  "2: a known-skill-but-unlearned recipe is marked NOT craftable")
check(type(craft2) == "table" and craft2["Lesser Discolored Healing Potion"] == true,
  "2: a learned recipe at the character's rank is craftable")
check(type(craft2) == "table" and craft2["Swiftness Potion"] == false,
  "2: a learned recipe ABOVE the rank is not craftable")
hover("Briarthorn")
local text2 = alchemyText()
check(text2 == "Alchemy: Lesser Discolored Healing Potion, +3 more you can't make yet",
  "2: only the learned, in-rank recipe is listed (got " .. text2 .. ")")
if os.getenv("RECIPE_DIAG_SHOW") then
  io.write("ALCHEMY_LINE=", text2, "\n")
end

-- ═══ 3. requiredSkillRank is the fallback when no learned/count call exists ═
mode = "skill"
installClient()
resetDB()
check(scan(), "3: the requiredSkillRank client scans")
check(NodeTrailDB.recipes.alchemyAvailability == "requiredSkillRank",
  "3: the skill comparison is the recorded signal")
hover("Briarthorn")
local text3 = alchemyText()
check(text3 == "Alchemy: Elixir of Wisdom, Lesser Discolored Healing Potion, "
  .. "+2 more you can't make yet",
  "3: requiredSkillRank 50 and 75 pass, 90 and 150 are withheld (got " .. text3 .. ")")
check(text3:find("Frenzy Potion", 1, true) == nil,
  "3: the 150 recipe is not advertised")
check(text3:find("Swiftness Potion", 1, true) == nil,
  "3: the 90 recipe is not advertised")

-- ═══ 4. NO signal at all: the line is ABSENT, the panel explains once ══════
mode = "none"
installClient()
resetDB()
check(scan(), "4: the no-signal client still scans the map")
check(NodeTrailDB.recipes.alchemyFilterable == false,
  "4: nothing is claimed filterable")
check(NodeTrailDB.recipes.alchemyAvailability == "none",
  "4: availability is recorded as none")
hover("Briarthorn")
check(alchemyLine() == nil,
  "4: NO Alchemy line is drawn (got " .. tostring(alchemyLine()) .. ")")
check(findLine(function(l) return l == "recipes (not filtered by skill)" end) == nil,
  "4: no unfiltered caveat is printed")
check(findLine(function(l)
    return type(l) == "string" and l:find("Alchemy:", 1, true) ~= nil
  end) == nil,
  "4: nothing advertises a craft the character cannot make")
local okHint, hint, hintWhy = pcall(function() return ns.Recipes:HiddenHint() end)
check(okHint, "4: Rc:HiddenHint exists (" .. tostring(hint) .. ")")
check(type(hint) == "string" and hint:find("alchemy uses hidden", 1, true) ~= nil,
  "4: the options panel gets the one short reason (got " .. tostring(hint) .. ")")
check(type(hint) == "string" and hint:find("recipe-availability API", 1, true) ~= nil,
  "4: the reason names the missing client API (" .. tostring(hint) .. ")")

-- The hidden state survives a reload: saved recipes with no gate keys must not
-- error, cannot be filtered, and must keep the explanation.
NodeTrailDB = {
  recipes = {
    alchemy = { [2450] = { "Lesser Discolored Healing Potion", "Frenzy Potion" } },
    alchemyScanned = time(),
  },
}
local uses = ns.Recipes:Uses(2450)
check(uses ~= nil and uses.filtered == false and #uses.names == 2,
  "4b: an older saved map stays readable and unfiltered")
local oldHint
local okOldHint, oldHintValue = pcall(function() return ns.Recipes:HiddenHint() end)
if okOldHint then oldHint = oldHintValue end
check(okOldHint and type(oldHint) == "string" and oldHint:find("open Alchemy once", 1, true) ~= nil,
  "4b: old saved data says to rescan, it does not pretend (" .. tostring(oldHint) .. ")")

-- ═══ 5. /nt recipediag prints the raw values, one craftable + one not ═══════
-- The "live" client is the surface Wow.exe documents for build 16001:
-- GetRecipeInfo (requiredSkillRank / skillLineAbilityID), GetCraftableCount and
-- IsRecipeProfessionLearned all present.
mode = "live"
installClient()
resetDB()
check(scan(), "5: scan for the diag fixture")
check(NodeTrailDB.recipes.alchemyAvailability == "GetCraftableCount",
  "5: the live-surface scan records the count signal")
local okDiag, diagText = capture(ns.PrintRecipeDiag, ns)
check(okDiag, "5: /nt recipediag runs (" .. tostring(diagText) .. ")")
if os.getenv("RECIPE_DIAG_SHOW") then
  io.write(diagText, "\n")
end
for _, needle in ipairs({
  "modern calls: GetRecipeInfo=present",
  "GetCraftableCount=present",
  "IsRecipeProfessionLearned=present",
  "legacy calls:",
  "GetTradeSkillNumAvailable=absent",
  "character Alchemy rank: 75",
  "recipe ids: 4 enumerated via GetAllRecipeIDs",
  'GetRecipeInfo(103) -> {',
  'name="Lesser Discolored Healing Potion" (string)',
  "requiredSkillRank=75 (number)",
  "skillLineAbilityID=9003 (number)",
  "GetRecipeSchematic(103, false) -> {",
  "reagentSlotSchematics=",
  "GetCraftableCount(103) -> 3 (number)",
  "GetCraftableCount(101) -> 0 (number)",
  "IsRecipeProfessionLearned(103) -> true (boolean)",
  "IsRecipeProfessionLearned(101) -> false (boolean)",
  "GetRecipeRequirements(103) -> absent",
  '--- target 1 (craftable per stored gate): "Lesser Discolored Healing Potion" (recipe id 103)',
  '--- target 2 (not craftable per stored gate): "Elixir of Wisdom" (recipe id 101)',
  "signal: GetCraftableCount",
}) do
  check(diagText:find(needle, 1, true) ~= nil,
    "5: recipediag prints " .. needle .. "\n--- output ---\n" .. diagText)
end
-- numAvailable is absent from this recipeInfo — the card asked for every field,
-- not a field that merely exists in some clients.
check(diagText:find("numAvailable=", 1, true) == nil,
  "5: an absent field is not printed as if it answered")
-- And the command is reachable from the slash handler, not just the function.
check(type(SlashCmdList) == "table" and type(SlashCmdList.NODETRAIL) == "function",
  "5b: /nt is registered")
local okSlash, slashText = capture(SlashCmdList.NODETRAIL, "recipediag")
check(okSlash and slashText:find("NodeTrail recipediag:", 1, true) ~= nil,
  "5b: /nt recipediag is dispatched (" .. tostring(slashText) .. ")")

-- 5c. a hostile client: every recipe call raises. The diag must still print
-- and must never raise into the player's chat.
mode = "hostile"
installClient()
resetDB()
ns.Recipes:Scan()
local okHostile, hostileText = capture(ns.PrintRecipeDiag, ns)
check(okHostile, "5c: recipediag does not raise on a hostile client")
check(hostileText:find("GetRecipeInfo(101) -> no table", 1, true) ~= nil,
  "5c: an unreadable recipeInfo is reported as no table")
check(hostileText:find("boom: GetRecipeSchematic", 1, true) ~= nil,
  "5c: a raising schematic is reported, not thrown")
check(hostileText:find("signal: not measured yet", 1, true) ~= nil,
  "5c: with no completed scan the diag says it is not measured yet")

-- ═══ 6. one source of truth: the panel reads the persisted gate ════════════
mode = "learned"
installClient()
resetDB()
check(scan(), "6: scan for the persisted-gate check")
hover("Briarthorn")
check((alchemyLine() or ""):find("Elixir of Wisdom", 1, true) == nil,
  "6: the unlocked recipe is not listed before the gate changes")
local craft6 = NodeTrailDB.recipes.alchemyCraft
check(type(craft6) == "table", "6: the scan persisted the gate")
craft6["Elixir of Wisdom"] = true
local before = scanCalls
hover("Briarthorn")
local text6 = alchemyText()
check(text6:find("Elixir of Wisdom", 1, true) ~= nil,
  "6: flipping the persisted gate moves the line with NO new scan (" .. text6 .. ")")
check(scanCalls == before, "6: the panel did not run a scan to do it")

-- A re-scan keeps the saved shape: alchemy[reagent] is still a name array.
check(scan(), "6b: re-scan succeeds")
local alch6 = NodeTrailDB.recipes.alchemy
check(type(alch6[2450]) == "table" and type(alch6[2450][1]) == "string",
  "6b: a re-scan does not invalidate the saved alchemy entries")
check(ns.Recipes:Uses(2450) ~= nil, "6b: the reagent still has its uses")

if failed > 0 then
  io.stderr:write(failed .. " recipe-diag/availability check(s) failed\n")
  os.exit(1)
end
print("recipe_diag_spec: ok")

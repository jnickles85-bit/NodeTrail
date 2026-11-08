-- t_5ba9b43c — the BEAST panel obeys the Skinning profession gate.
--
-- The herb block was gated on Herbalism in t_d4848ce0; the beast block was
-- written with the same gate but only half of it. `BuildBeastLines` hid the
-- block when the client answered a definitive NO (`answer == false`) and let an
-- UNREADABLE answer (`nil` — no profession API on this client, a read that
-- raised, or a partial list) fall straight through to the renderer.
--
-- Live: on a character without Skinning, hovering a Mottled Boar printed
--
--   Tough Jerky x3    20% (yours)
--   ...
--   kills seen: 10 · skinned: 0
--
-- `skinned: 0` beside `(yours)` percentages was the tell. A definitive "no"
-- cannot produce that block — the gate would have hidden it — so the live
-- client answered UNKNOWN and the panel rendered anyway.
--
-- The contract this spec pins:
--
--   A. a definitive NO      (readable skills, no Skinning row)  -> no panel
--   B. UNREADABLE           (no profession API at all)          -> no panel
--   B2. UNREADABLE          (a skill row raises / partial list)  -> no panel
--   B3. UNREADABLE          (the Profession module is not loaded) -> no panel
--   C. a confirmed SKINNER  (yes)                                -> unchanged
--   D. a character whose own skinned count is 0 gets counts only, never a
--      percentage and never "(yours)"
--   E. /nt ttdiag names the profession API consulted and the result for THIS
--      character, and says the beast block is hidden when it is
--   F. one gate implementation: the beast path consults ns.Profession:Skinning
--      and never a private second check
--
-- Why UNREADABLE abstains for the beast where it shows node knowledge for an
-- herb: an herb node has a researched drop table (HerbData), which is not
-- personal, so the block still has something true to say without the picks
-- line. The beast block has no such table — every row in it is an aggregate of
-- OUR OWN recorded corpses (Data/SkinHints.lua, "this file never invents one").
-- With no confirmation that this character can skin at all, there is nothing
-- left that is both true and useful, so the panel abstains. The GATE is shared;
-- only what each consumer does with "unknown" differs, and each site says why.
--
-- The records below are built by driving the REAL recorder (Modules/Skinning/
-- Record.lua) through the real event entry points — the spec never hand-writes
-- a record shape.
--
-- Not loaded by the addon TOC.
local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local F = dofile(root .. "/tests/support/fakeui.lua")
F.install({ width = 1920, height = 1080 })

time = time or os.time
CopyTable = function(t)
  local c = {}
  for k, v in pairs(t) do
    c[k] = type(v) == "table" and CopyTable(v) or v
  end
  return c
end
GetSpellInfo = function(id)
  local map = { [2366] = "Herb Gathering", [2259] = "Alchemy", [8613] = "Skinning" }
  return map[id]
end
SlashCmdList = {}
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end }

local ITEM_NAMES = {
  [2319] = "Medium Leather",
  [2934] = "Ruined Leather Scrappings",
}
GetItemInfo = function(id) return ITEM_NAMES[id] end

-- ── the character's professions, behind one switchable stub ───────────────
local skillLines = { { name = "Skinning", rank = 300 } }
local skillRaises = false
local skillRaiseRows = nil
GetNumSkillLines = function() return #skillLines end
GetSkillLineInfo = function(i)
  if skillRaises then error("boom: GetSkillLineInfo") end
  if skillRaiseRows and skillRaiseRows[i] then
    error("boom: GetSkillLineInfo row " .. i)
  end
  local row = skillLines[i]
  if not row then return nil end
  return row.name, false, true, row.rank
end

-- ── the hovered unit ──────────────────────────────────────────────────────
local unit = { exists = false, guid = nil, ctype = "Beast", name = "Mottled Boar" }
UnitExists = function(u) return u == "mouseover" and unit.exists == true end
UnitGUID = function(u) return (u == "mouseover") and unit.guid or nil end
UnitCreatureType = function(u) return (u == "mouseover") and unit.ctype or nil end
UnitName = function(u) return (u == "mouseover") and unit.name or nil end

local pkg = {}
local function loadFile(path)
  local f = assert(loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. path))
  f("MightiePack", pkg)
end
local function loadAddon(path)
  local f = assert(loadfile(root .. "/MightiePack/" .. path))
  f("MightiePack", pkg)
end

loadFile("locale/enUS.lua")
loadFile("Config.lua")
loadFile("Data/Recorder.lua")
loadFile("Data/HerbData.lua")
loadFile("Data/Profession.lua")
loadFile("Data/SkinHints.lua")
loadFile("Data/Recipes.lua")
loadFile("UI/TooltipPanel.lua")
loadFile("UI/Tooltip.lua")
loadFile("Core.lua")
loadAddon("Modules/Skinning/Record.lua")

local ns = pkg.NodeTrail
local T = ns.Tooltip
local P = ns.TooltipPanel
local Pr = ns.Profession
local H = ns.SkinHints
local R = pkg.Skinning.Recorder

check(type(Pr) == "table" and type(Pr.Skinning) == "function",
  "0: Data/Profession.lua is loaded and answers for Skinning")
check(type(H) == "table" and type(T.BuildBeastLines) == "function",
  "0: the beast data build exists")
check(type(R) == "table" and type(R.CreatureID) == "function",
  "0: the skinning recorder is loaded (this spec drives the real one)")

-- The recorder keys records per character: Name-Realm.
GetUnitName = function(u) if u == "player" then return "NonSkinner" end return nil end
GetRealmName = function() return "TestRealm" end

NodeTrailDB = {
  recipes = {}, profile = {},
  herbs = { schema = 1, total = 0, maps = {} },
  skinning = { enabled = true },
}

local function reset()
  Pr:Forget()
end

-- ── records, built by calling the real recorder ────────────────────────────
local CID = 3125 -- Mottled Boar
local seq = 0
local function guidOf(cid, n)
  return ("Creature-0-7072-1-48-%d-%012X"):format(cid, n)
end

local CORPSE = { { id = 2934, name = "Ruined Leather Scrappings", qty = 2 } }
local SKIN = { { id = 2319, name = "Medium Leather", qty = 1 } }

--- One observed corpse: death, corpse loot, a successful 8613 cast, skin loot.
local function observe(cid, corpseItems, skinItems)
  seq = seq + 1
  local g = guidOf(cid, seq)
  R:OnKill({ guid = g, t = 1000 + seq, name = "Mottled Boar" })
  if corpseItems then
    R:OnCorpseLoot({ guid = g, t = 1001 + seq, items = corpseItems })
  end
  if skinItems then
    R:OnSkinCast({ guid = g, t = 1002 + seq, spellID = 8613 })
    R:OnSkinLoot({ guid = g, t = 1003 + seq, items = skinItems })
  end
  return g
end

-- Ten corpses of the boar, every one of them skinned: enough evidence for the
-- percentage rows (HerbData.PERSONAL_MIN is 10).
for _ = 1, 10 do observe(CID, CORPSE, SKIN) end

-- ── hover ─────────────────────────────────────────────────────────────────
local function hoverBeast(opts)
  opts = opts or {}
  unit.exists = true
  unit.guid = opts.guid or guidOf(CID, 1)
  unit.ctype = opts.ctype or "Beast"
  unit.name = opts.name or "Mottled Boar"
  local gt = F.newTooltip({
    lines = { unit.name, "Beast" },
    owner = UIParent,
    left = 300, bottom = 700, width = 180, height = 60,
  })
  _G.GameTooltip = gt
  gt.shown = true
  pcall(T.Poll, T, gt)
  return gt
end

local function rows() return P:TextLines() end
local function joined() return table.concat(rows(), "\n") end
local function lastRing()
  local r = T.RingEntries()
  return r[#r]
end
local function diagText()
  chat = {}
  local ok, err = pcall(T.Diag, T)
  return ok, err, table.concat(chat, "\n")
end

--- The one diag LINE carrying `needle`. A substring check over the whole dump
--- would match the refresh ring's last skips (which quote reasons from earlier
--- hovers), so the gate's own line is what these checks read.
local function diagLine(out, needle)
  for line in (out .. "\n"):gmatch("([^\n]*)\n") do
    if line:find(needle, 1, true) ~= nil then
      return line
    end
  end
  return nil
end

--- The data build is the contract: whatever the panel happens to hold from a
--- previous hover, the hover path must be handed NO lines and a reason.
local function buildBeast()
  unit.exists = true
  unit.guid = guidOf(CID, 1)
  unit.ctype = "Beast"
  unit.name = "Mottled Boar"
  return T.BuildBeastLines("mouseover")
end

--- Assert one "the panel must not be drawn" case end to end: the data build
--- returns no lines with a reason naming Skinning, the panel is hidden, and the
--- refresh ring records why.
local function checkHidden(prefix)
  local lines, why = buildBeast()
  check(lines == nil, prefix .. ": the data build returns no lines (got a table of "
    .. tostring(type(lines) == "table" and #lines or lines) .. ")")
  check(type(why) == "string" and why:find("Skinning", 1, true) ~= nil,
    prefix .. ": the reason names Skinning (got " .. tostring(why) .. ")")
  reset()
  hoverBeast()
  check(P:IsShown() == false, prefix .. ": nothing is drawn")
  local e = lastRing()
  check(e and e.kind == "beast", prefix .. ": the ring says this hover was a beast")
  check(e and e.panelShown == false, prefix .. ": the ring records panel=false")
  check(e and type(e.skip) == "string" and e.skip:find("Skinning", 1, true) ~= nil,
    prefix .. ": the ring names Skinning as the reason (got " .. tostring(e and e.skip) .. ")")
end

-- ═══ A. A DEFINITIVE "NO" ══════════════════════════════════════════════════
-- The skill list is readable and carries no Skinning row. That is a definite
-- answer, not a guess: this character cannot skin, so the block is meaningless.
skillLines = {
  { name = "Herbalism", rank = 300 },
  { name = "Cooking", rank = 75 },
}
skillRaises, skillRaiseRows = false, nil
reset()
local aAnswer, aInfo = Pr:Skinning()
check(aAnswer == false,
  "A: the gate answers a definitive 'no' (got " .. tostring(aAnswer) .. ")")
check(type(aInfo) == "table" and aInfo.api == "skill-lines",
  "A: the skill-lines tier answered (got " .. tostring(type(aInfo) == "table" and aInfo.api) .. ")")
checkHidden("A non-skinner")

-- ═══ B. UNREADABLE: no profession API at all ═══════════════════════════════
-- This is the live shape: nothing on the client can name the character's
-- professions, so the gate answers nil. The old code rendered the panel on nil,
-- which is how a non-skinner came to be shown account records as "(yours)".
local savedNum, savedInfo = GetNumSkillLines, GetSkillLineInfo
local savedProf, savedProfInfo = GetProfessions, GetProfessionInfo
local savedTrade = GetTradeSkillLine
GetNumSkillLines, GetSkillLineInfo = nil, nil
GetProfessions, GetProfessionInfo = nil, nil
GetTradeSkillLine = nil
C_TradeSkillUI = nil
reset()
local bAnswer, bInfo = Pr:Skinning()
check(bAnswer == nil,
  "B: the gate answers 'unknown' (got " .. tostring(bAnswer) .. ")")
check(type(bInfo) == "table" and bInfo.api == nil,
  "B: no tier claimed the answer")
checkHidden("B unreadable")

local okB, errB, outB = diagText()
check(okB, "B: ttdiag does not raise with no profession API (" .. tostring(errB) .. ")")
check(outB:find("api probed:", 1, true) ~= nil,
  "B: ttdiag lists the calls it probed (got:\n" .. outB .. ")")
check(outB:find("skinning=unknown", 1, true) ~= nil,
  "B: ttdiag reports the skinning read as unknown (got:\n" .. outB .. ")")
check(outB:find("from no API", 1, true) ~= nil,
  "B: ttdiag says no API answered (got:\n" .. outB .. ")")
local bGate = diagLine(outB, "gate: skinning")
check(bGate ~= nil,
  "B: ttdiag has a beast-gate line (got:\n" .. outB .. ")")
check(bGate ~= nil
  and (bGate:find("hidden", 1, true) ~= nil or bGate:find("abstains", 1, true) ~= nil)
  and bGate:find("shows", 1, true) == nil,
  "B: ttdiag says the beast block is NOT shown when the profession is unreadable (got:\n"
    .. tostring(bGate) .. ")")

-- ═══ B2. UNREADABLE: a partially readable skill list ═══════════════════════
-- One row raises, the readable rows carry no Skinning. A "no" here would be a
-- guess about the row that raised, so the gate abstains — and the beast block
-- follows the abstention instead of rendering.
GetNumSkillLines, GetSkillLineInfo = savedNum, savedInfo
skillLines = {
  { name = "Herbalism", rank = 300 },
  { name = "Cooking", rank = 75 },
}
skillRaises = false
skillRaiseRows = { [1] = true }
reset()
local b2Answer = Pr:Skinning()
check(b2Answer == nil,
  "B2: a partial skill read abstains (got " .. tostring(b2Answer) .. ")")
checkHidden("B2 partial read")
skillRaiseRows = nil

-- A read that raises outright is the same abstention.
skillRaises = true
reset()
local b2bAnswer = Pr:Skinning()
check(b2bAnswer == nil, "B2: a raising read abstains (got " .. tostring(b2bAnswer) .. ")")
checkHidden("B2 raising read")
skillRaises = false

-- ═══ B3. UNREADABLE: the Profession module is not loaded ═══════════════════
-- A partial load (or a tree where Data/Profession.lua is missing) must not be a
-- licence to render personal records: there is no gate to consult, so abstain.
local savedModule = ns.Profession
ns.Profession = nil
checkHidden("B3 no Profession module")
ns.Profession = savedModule

-- ═══ C. THE CONFIRMED SKINNER IS UNCHANGED ═════════════════════════════════
skillLines = { { name = "Skinning", rank = 300 }, { name = "Cooking", rank = 75 } }
reset()
local cAnswer, cInfo = Pr:Skinning()
check(cAnswer == true, "C: the gate answers 'yes' (got " .. tostring(cAnswer) .. ")")
check(type(cInfo) == "table" and cInfo.api == "skill-lines",
  "C: ttdiag has the tier that answered")
hoverBeast()
check(P:IsShown() == true, "C: the skinner still sees the beast panel")
local r = rows()
local EXPECTED = {
  "Mottled Boar",
  "skinnable · skin windows recorded: 10",
  "skinned",
  "Medium Leather x10 | 100% (yours)",
  "kills seen: 10 · skinned: 10",
}
local blockOK = #r == #EXPECTED
if blockOK then
  for i = 1, #EXPECTED do
    if r[i] ~= EXPECTED[i] then blockOK = false end
  end
end
check(blockOK, "C: the skinner's block is line for line what it was (got:\n" .. joined() .. ")")

local okC, errC, outC = diagText()
check(okC, "C: ttdiag runs for the skinner (" .. tostring(errC) .. ")")
check(outC:find("skinning=yes (from skill-lines)", 1, true) ~= nil,
  "C: ttdiag names the API that answered and the result (got:\n" .. outC .. ")")
check(outC:find("Skinning rank 300", 1, true) ~= nil,
  "C: ttdiag reports what the skill line returned (got:\n" .. outC .. ")")
local cGate = diagLine(outC, "gate: the beast block")
check(cGate ~= nil and cGate:find("beast block shows", 1, true) ~= nil,
  "C: ttdiag says the beast block shows (got:\n" .. tostring(cGate) .. ")")

-- The seven profession slots are the other API the same gate can answer from:
-- a skinner confirmed there keeps the panel, and the diag names THAT tier.
GetNumSkillLines, GetSkillLineInfo = nil, nil
GetProfessions = function() return 1, 4, nil, nil, nil, nil, nil end
GetProfessionInfo = function(index)
  if index == 1 then return "Skinning", "icon", 300, 300 end
  if index == 4 then return "Cooking", "icon", 75, 75 end
  return nil
end
reset()
hoverBeast()
check(P:IsShown() == true, "C: a skinner confirmed by the profession slots keeps the panel")
local okC2, _, outC2 = diagText()
check(okC2 and outC2:find("skinning=yes (from professions)", 1, true) ~= nil,
  "C: ttdiag names the professions tier (got:\n" .. tostring(outC2) .. ")")

-- ...and the same tier naming only a NON-skinner still hides it.
GetProfessions = function() return 1, 4, nil, nil, nil, nil, nil end
GetProfessionInfo = function(index)
  if index == 1 then return "Herbalism", "icon", 300, 300 end
  if index == 4 then return "Cooking", "icon", 75, 75 end
  return nil
end
reset()
checkHidden("C professions say no")
GetNumSkillLines, GetSkillLineInfo = savedNum, savedInfo
GetProfessions, GetProfessionInfo = savedProf, savedProfInfo
GetTradeSkillLine = savedTrade
skillLines = { { name = "Skinning", rank = 300 } }
reset()

-- ═══ D. THE WORDING RULE: own skinned count 0 -> counts only ══════════════
-- t_5ba9b43c: "(yours) must not be printed from account-wide records for a
-- character that has never skinned ... for any character whose own count is
-- zero: counts only, no percentage." The gate makes the live shape impossible,
-- and this pins the renderer's own rule so a future path that reaches it without
-- a gate still cannot claim a percentage from a sample of zero.
local ZERO = 3126
for _ = 1, 5 do
  seq = seq + 1
  local g = guidOf(ZERO, seq)
  R:OnKill({ guid = g, t = 4000 + seq, name = "Mottled Boar" })
  R:OnSkinLoot({ guid = g, t = 4001 + seq, items = SKIN }) -- a window, no cast
end
reset()
local dRows = H.Rows(ZERO, "Mottled Boar")
check(type(dRows) == "table" and #dRows > 0, "D: the rows are built")
local aggSeen = 0
for _, row in ipairs(dRows) do
  if row.right ~= nil then
    aggSeen = aggSeen + 1
  end
end
check(aggSeen == 0, "D: a character with 0 skinned corpses gets no percentage column (got "
  .. aggSeen .. " row(s) with a right-hand value)")
local dText = {}
for _, row in ipairs(dRows) do
  dText[#dText + 1] = row.left or "-"
end
local dJoined = table.concat(dText, "\n")
check(dJoined:find("Medium Leather x5", 1, true) ~= nil,
  "D: the count is still printed (got:\n" .. dJoined .. ")")
check(dJoined:find("(yours)", 1, true) == nil,
  "D: '(yours)' is never printed from a sample of zero (got:\n" .. dJoined .. ")")
check(dJoined:find("%", 1, true) == nil,
  "D: no percentage is printed from a sample of zero (got:\n" .. dJoined .. ")")

-- ═══ F. ONE GATE IMPLEMENTATION ════════════════════════════════════════════
-- The beast path must ask the SHARED gate (ns.Profession:Skinning), not a
-- private second check that could drift from the herb block's. Both paths are
-- instrumented: a beast hover consults Skinning and never Herbalism.
local calls = { skin = 0, herb = 0 }
local realSkin, realHerb = Pr.Skinning, Pr.Herbalism
Pr.Skinning = function(self) calls.skin = calls.skin + 1; return realSkin(self) end
Pr.Herbalism = function(self) calls.herb = calls.herb + 1; return realHerb(self) end
skillLines = { { name = "Skinning", rank = 300 } }
reset()
hoverBeast()
check(calls.skin >= 1, "F: a beast hover consults ns.Profession:Skinning (got "
  .. calls.skin .. " call(s))")
check(calls.herb == 0, "F: a beast hover does not consult the Herbalism gate (got "
  .. calls.herb .. " call(s))")

-- Hovering an herb node still goes through the herb gate, and the two answers
-- come from the same probe: one implementation, two contexts.
unit.exists = false -- a herb node is not a unit hover
local gtHerb = F.newTooltip({
  lines = { "Peacebloom", "Herbalism" },
  owner = UIParent,
  left = 300, bottom = 700, width = 180, height = 60,
})
_G.GameTooltip = gtHerb
gtHerb.shown = true
pcall(T.Poll, T, gtHerb)
check(calls.herb >= 1, "F: a herb hover still consults the Herbalism gate (got "
  .. calls.herb .. " call(s))")
Pr.Skinning, Pr.Herbalism = realSkin, realHerb
reset()

-- ═══ Nothing raised, and no forbidden client surface was touched ══════════
check(T._error == nil, "G: ns.Tooltip recorded no error (" .. tostring(T._error) .. ")")
check(P._error == nil, "G: the panel recorded no error (" .. tostring(P._error) .. ")")
check(R._error == nil, "G: the recorder recorded no error (" .. tostring(R._error) .. ")")

-- The gate lives in files this card edits: neither may ask C_EventUtils for
-- validity, mention the combat log event, or write into a tooltip.
local function sourceOf(rel)
  local f = assert(io.open(root .. "/MightiePack/Modules/NodeTrail/" .. rel, "r"))
  local s = f:read("*a")
  f:close()
  return s
end
for _, rel in ipairs({ "Data/Profession.lua", "UI/Tooltip.lua" }) do
  local s = sourceOf(rel)
  check(s:find("C_EventUtils%s*[%.:(]") == nil, "G: " .. rel .. " never calls C_EventUtils")
  check(s:find("COMBAT_LOG_EVENT_UNFILTERED", 1, true) == nil,
    "G: " .. rel .. " never mentions COMBAT_LOG_EVENT_UNFILTERED")
  check(s:find("RegisterEvent", 1, true) == nil, "G: " .. rel .. " registers no event")
end

if failed > 0 then
  io.stderr:write(failed .. " beast-profession-gate check(s) failed\n")
  os.exit(1)
end
print("beast_profession_gate_spec: ok")

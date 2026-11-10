-- The Retribution verdict's SECOND TIER: Agility is a damage stat, and Stamina /
-- Armor are RANKED TIEBREAKERS that decide only when the damage total is zero
-- (card t_c4911603, gated on the research card t_f758a377).
--
-- Two live misreads this pins:
--
--   1. `melee = { Strength = 4, Intellect = 1 }` had no Agility at all, so a
--      gloves comparison (Dagmire Gauntlets vs Gloves of the Fang) came out far
--      closer than it should have;
--   2. Stamina and Armor scored 0, so `51 Armor / +4 Str` leather boots against
--      `115 Armor / +4 Str / +2 Sta` mail boots read "Not an upgrade — weighted
--      0 [Retribution] — no change" instead of a survivability gain.
--
-- The rule (Mightie's): damage decides first — Strength and Agility, Agility at
-- 0.64 x Strength, carried as the researched 2.5 (t_f758a377). Stamina and Armor
-- are consulted ONLY when the damage difference is exactly zero, they can never
-- outweigh one damage point, and when they decide the answer is FLAGGED as a
-- tiebreaker so a survivability gain is never read as damage. They are ordered,
-- not weighted: Armor outranks Stamina in the research, so a huge Stamina number
-- cannot beat a one-point Armor gain.
--
-- The item numbers are the client's own (WoW: Forever), and the two named live
-- cases are real:
--
--   Gloves of the Fang    id 10413  hands, LEATHER, 52 Armor, +4 Str, +6 Agi
--                         (Forever changed it from +3/+2 in Classic)
--   Dagmire Gauntlets     id  6481  hands, MAIL,   110 Armor, +5 Str, +2 Agi
--   Feral Shoes of Strength id 15305 + "of Strength"  feet, LEATHER, 51 Armor, +4 Str
--   Safety Boots          id 270009 feet, MAIL,   115 Armor, +4 Str, +2 Sta
--
-- The paladin is level 20 (< 40), so mail is the best armor type it can wear and
-- a mail candidate is never vetoed for its material; that level also makes the
-- leather FANG the equipped piece, not the candidate, in the gloves pair.
--
-- Fails on the parent commit e2d1db1 for every assertion that needs the second
-- tier or the Agility weight: there `judge` returns "weighted 0 ... no change"
-- for the boots pair (total 0, no `tiebreak` field, no flag), the boots line
-- renders "No change", the gloves pair totals +4 instead of -6, and one point of
-- Agility weighs 0 instead of 2.5. The -16 cloak assertion passes on the parent
-- (that is the point — it must not change).
--
-- Run from the repo root:  lua5.1 tests/touchstone_tiebreak_spec.lua

local here = (arg and arg[0] or "tests/touchstone_tiebreak_spec.lua"):match("^(.*)[/\\][^/\\]*$") or "."
local root = here:gsub("[/\\]tests$", "")
if root == "tests" then root = "." end
local TOUCH = root .. "/MightiePack/Modules/Touchstone/"

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local function fileExists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

if not fileExists(TOUCH .. "ChestAdvisor/Verdict.lua") then
  io.stderr:write("FAIL: the vendored Touchstone is absent — nothing to check\n")
  os.exit(1)
end

-- ---- The two live pairs, as the client's tooltips render them ----------------
local FANG_NAME = "Gloves of the Fang"
local FANG_LINES = {
  FANG_NAME, "Binds when equipped", "Hands Leather",
  "52 Armor", "+4 Strength", "+6 Agility", "Requires Level 14",
}
local DAG_NAME = "Dagmire Gauntlets"
local DAG_LINES = {
  DAG_NAME, "Binds when picked up", "Hands Mail",
  "110 Armor", "+5 Strength", "+2 Agility",
}
local FERAL_NAME = "Feral Shoes of Strength"
local FERAL_LINES = {
  FERAL_NAME, "Feet Leather", "51 Armor", "+4 Strength", "Requires Level 13",
}
local SAFETY_NAME = "Safety Boots"
local SAFETY_LINES = {
  SAFETY_NAME, "Binds when picked up", "Feet Mail",
  "115 Armor", "+4 Strength", "+2 Stamina",
}
local CLOAK_WORN = {
  "Lambent Scale Cloak", "Binds when equipped", "Back",
  "19 Armor", "+4 Strength", "+2 Spirit", "Requires Level 21",
}
local CLOAK_CAND = { "Barkeeper's Cloak", "Back", "16 Armor", "+3 Stamina", "Requires Level 18" }

local function link(id, name)
  return "|cff1eff00|Hitem:" .. id .. ":0:0:0:0:0:0:0|h[" .. name .. "]|h|r"
end
local FANG_LINK = link(10413, FANG_NAME)
local SAFETY_LINK = link(270009, SAFETY_NAME)
local FERAL_LINK = link(15305, FERAL_NAME)
local CLOAK_WORN_LINK = link(5341, "Lambent Scale Cloak")

-- ===========================================================================
-- 1. The comparator, on its own
-- ===========================================================================
local loadVerdict = assert(loadfile(TOUCH .. "ChestAdvisor/Verdict.lua"))
local V = loadVerdict()
check(type(V) == "table", "Verdict.lua loads and returns the module")

local function judge(cand, worn, spec)
  return V.evaluate({ canUse = true, line = cand }, { line = worn }, spec, nil)
end

-- The Retribution profile as buildSpec resolves it. Level 20, not 70: below 40
-- the paladin's best armor type is mail, so the armor-material veto (a real rule,
-- unchanged by this card) does not fire on either live pair. At 70 mail is below
-- plate and BOTH pairs would be vetoed before the comparator — a different
-- behaviour, correctly, and not what this card is about.
local RET_SPEC = {
  class = "PALADIN", role = "melee", clientRole = "DAMAGER",
  order = V.classRoleOrder("PALADIN", "melee"), level = 20,
}

-- ---- 1a. The researched table is the shipped table ---------------------------
local prof = V.profileFor(RET_SPEC)
check(type(prof) == "table", "the Retribution profile resolves")
if type(prof) == "table" then
  local w = prof.w or {}
  check(w.Strength == 4, "Ret Strength weight is 4 (got " .. tostring(w.Strength) .. ")")
  check(w.SpellPower == 4, "Ret Spell Power weight is 4 (got " .. tostring(w.SpellPower) .. ")")
  check(w.Agility == 2.5, "Ret Agility weight is the researched 2.5 (got " .. tostring(w.Agility) .. ")")
  check(w.Intellect == 2, "Ret Intellect weight is 2 (got " .. tostring(w.Intellect) .. ")")
  check(w.Stamina == nil and w.Armor == nil,
    "Stamina and Armor are NOT damage weights (they are tiebreakers)")
  check(type(prof.tiebreak) == "table" and prof.tiebreak[1] == "Armor"
    and prof.tiebreak[2] == "Stamina",
    "the ranked tiebreakers are Armor then Stamina, in that order")
end
check(type(V.WEIGHT_EPSILON) == "number" and V.WEIGHT_EPSILON > 0
  and V.WEIGHT_EPSILON <= 0.25,
  "epsilon is <= 0.25 so a 2.5-weight half-step is never swallowed (got "
    .. tostring(V.WEIGHT_EPSILON) .. ")")

-- ---- 1b. Equal damage + more armor/stamina -> TIEBREAKER UPGRADE ------------
-- Safety Boots (115 Armor / +4 Str / +2 Sta, mail) against the equipped Feral
-- Shoes of Strength (51 Armor / +4 Str, leather). Damage is +0 exactly, so the
-- ranked tiebreakers speak: +64 Armor and +2 Stamina, both for the candidate.
local vb, rb, wb = judge(SAFETY_LINES, FERAL_LINES, RET_SPEC)
check(vb == "UPGRADE", "the boots pair is an upgrade, got " .. tostring(vb))
check(type(wb) == "table" and wb.total == 0,
  "the boots pair's DAMAGE total is exactly 0 (got " .. tostring(wb and wb.total) .. ")")
check(type(wb) == "table" and wb.profile == "Retribution",
  "the tiebreaker quotes its profile (got " .. tostring(wb and wb.profile) .. ")")
check(type(wb) == "table" and wb.tiebreak == "+64 Armor, +2 Stamina",
  "the tiebreaker carries the signed deltas (got " .. tostring(wb and wb.tiebreak) .. ")")
check(type(wb) == "table" and wb.tiebreakDir == 1,
  "and the direction says the candidate won it")
check(type(rb) == "string" and rb == "weighted 0 [Retribution] — tiebreaker (+64 Armor, +2 Stamina)",
  "the reason flags a tiebreaker, not a weighted number (got " .. tostring(rb) .. ")")

-- ---- 1c. Equal damage + less armor/stamina -> TIEBREAKER DOWNGRADE ----------
-- The same pair the other way round: the equipped boots win the tiebreak, so the
-- answer is NOT_UPGRADE with the flag — never a damage "Downgrade".
local vr, rr, wr = judge(FERAL_LINES, SAFETY_LINES, RET_SPEC)
check(vr == "NOT_UPGRADE", "the reversed boots pair is not an upgrade, got " .. tostring(vr))
check(type(wr) == "table" and wr.total == 0 and wr.tiebreakDir == -1,
  "the reversed tiebreaker is a zero-damage loss (got " .. tostring(wr and wr.total)
    .. ", dir " .. tostring(wr and wr.tiebreakDir) .. ")")
check(type(wr) == "table" and wr.tiebreak == "-64 Armor, -2 Stamina",
  "the deltas are signed from the candidate's side (got " .. tostring(wr and wr.tiebreak) .. ")")
check(type(rr) == "string" and rr == "weighted 0 [Retribution] — tiebreaker (-64 Armor, -2 Stamina)",
  "the reason carries the negative flag (got " .. tostring(rr) .. ")")

-- ---- 1d. ONE point of Strength beats any armor/stamina swing ----------------
-- The invariant that protects the cloak case: whatever the survivability deltas
-- say, a non-zero damage total decides and the tiebreakers are never consulted.
local ONE_STR_CAND = { "X", "Back", "500 Armor", "+5 Strength", "+10 Stamina" }
local ONE_STR_WORN = { "Y", "Back", "10 Armor", "+4 Strength" }
local v1, r1, w1 = judge(ONE_STR_CAND, ONE_STR_WORN, RET_SPEC)
check(v1 == "UPGRADE", "one more Strength is an upgrade, got " .. tostring(v1))
check(type(w1) == "table" and w1.total == 4,
  "one point of Strength is worth 4, whatever the armor says (got "
    .. tostring(w1 and w1.total) .. ")")
check(type(r1) == "string" and r1:find("tiebreaker", 1, true) == nil,
  "a damage verdict is never dressed as a tiebreaker (got " .. tostring(r1) .. ")")
local v1b = judge(ONE_STR_WORN, ONE_STR_CAND, RET_SPEC)
check(v1b == "NOT_UPGRADE",
  "one point of Strength LESS is a downgrade, however much armor comes with it (got "
    .. tostring(v1b) .. ")")

-- ---- 1e. ONE point of Agility beats any armor/stamina swing -----------------
-- Agility now carries 2.5, so a single point is a real damage difference: it must
-- beat losing 490 Armor (the exact shape of the Dagmire pair's armor gap).
local ONE_AGI_CAND = { "X", "Back", "10 Armor", "+1 Agility" }
local ONE_AGI_WORN = { "Y", "Back", "500 Armor", "+10 Stamina" }
local v2, r2, w2 = judge(ONE_AGI_CAND, ONE_AGI_WORN, RET_SPEC)
check(v2 == "UPGRADE", "one more Agility is an upgrade, got " .. tostring(v2))
check(type(w2) == "table" and w2.total == 2.5,
  "one point of Agility is worth 2.5 (got " .. tostring(w2 and w2.total) .. ")")
check(type(r2) == "string" and r2:find("tiebreaker", 1, true) == nil,
  "and it is a damage verdict, not a tiebreaker (got " .. tostring(r2) .. ")")
local v2b = judge(ONE_AGI_WORN, ONE_AGI_CAND, RET_SPEC)
check(v2b == "NOT_UPGRADE",
  "one point of Agility LESS loses to 490 Armor (got " .. tostring(v2b) .. ")")

-- ---- 1f. The tiebreakers are ORDERED, not weighted --------------------------
-- Armor outranks Stamina in the research, so +10 Armor beats -50 Stamina. A
-- weighted model would lose this pair (-50 Sta is the larger number); the ranked
-- model must win it. Then the reverse: +50 Stamina still loses to -10 Armor.
local ARM_CAND = { "X", "Back", "20 Armor" }
local ARM_WORN = { "Y", "Back", "10 Armor", "+50 Stamina" }
local v3, r3, w3 = judge(ARM_CAND, ARM_WORN, RET_SPEC)
check(v3 == "UPGRADE", "+10 Armor beats -50 Stamina because Armor ranks first, got "
  .. tostring(v3))
check(type(w3) == "table" and w3.tiebreak == "+10 Armor, -50 Stamina",
  "the ranked deltas are reported in rank order (got " .. tostring(w3 and w3.tiebreak) .. ")")
check(type(w3) == "table" and w3.tiebreakDir == 1,
  "and the FIRST ranked difference decides the direction")
local v3b = judge(ARM_WORN, ARM_CAND, RET_SPEC)
check(v3b == "NOT_UPGRADE",
  "+50 Stamina still loses to -10 Armor (got " .. tostring(v3b) .. ")")

-- ---- 1g. The cloak case is untouched ---------------------------------------
-- -4 Str x 4 = -16 exactly; neither cloak carries Agility, Spell Power or
-- Intellect and Stamina/Spirit are not tiebreakers on the Ret table. The research
-- card predicted this number, and it is the proof the second tier did not leak
-- into the damage path.
local vc, rc, wc = judge(CLOAK_CAND, CLOAK_WORN, RET_SPEC)
check(vc == "NOT_UPGRADE", "the cloak case is still a downgrade, got " .. tostring(vc))
check(type(wc) == "table" and wc.total == -16,
  "the cloak case is still exactly -16 (got " .. tostring(wc and wc.total) .. ")")
check(type(wc) == "table" and wc.tiebreak == nil,
  "and no tiebreaker is involved (the damage total is not zero)")
check(rc == "weighted -16 [Retribution]",
  "the cloak case's reason is byte-identical to before (got " .. tostring(rc) .. ")")

-- ---- 1h. Agility moves the gloves pair by the researched weight -------------
-- Equipped Gloves of the Fang (52 Armor, +4 Str, +6 Agi, leather); hovering
-- Dagmire Gauntlets (110 Armor, +5 Str, +2 Agi, mail). Damage deltas: +1 Str
-- (+4) and -4 Agi. The old table scored -4 Agi at 0 and called this a +4
-- upgrade; the researched 2.5 makes -4 Agi worth -10, so the pair totals -6.
-- The move is exactly 4 x 2.5 = -10.
local vg, rg, wg = judge(DAG_LINES, FANG_LINES, RET_SPEC)
check(vg == "NOT_UPGRADE", "the gloves pair is not an upgrade, got " .. tostring(vg))
check(type(wg) == "table" and wg.total == -6,
  "Dagmire vs Fang totals -6 under the researched table (got "
    .. tostring(wg and wg.total) .. ")")
local candStats = V.statTable(DAG_LINES, "candidate")
local wornStats = V.statTable(FANG_LINES, "worn")
check(type(candStats) == "table" and candStats.Agility == 2 and candStats.Strength == 5,
  "the Dagmire parse is the client's (5 Str, 2 Agi)")
check(type(wornStats) == "table" and wornStats.Agility == 6 and wornStats.Strength == 4,
  "the Fang parse is the client's (4 Str, 6 Agi)")
local OLD_RET = { name = "Retribution (pre-card table)", w = { Strength = 4, Intellect = 1 } }
local oldW = V.weightedTotal(candStats, wornStats, OLD_RET)
check(type(oldW) == "table" and oldW.total == 4,
  "the old table scored this pair +4 (an 'upgrade'), got "
    .. tostring(oldW and oldW.total))
check(type(wg) == "table" and type(oldW) == "table"
  and wg.total - oldW.total == -10,
  "Agility moves the pair by exactly 4 x 2.5 = -10 (got "
    .. tostring(wg and wg.total) .. " vs " .. tostring(oldW and oldW.total) .. ")")
check(type(rg) == "string" and rg:find("no change", 1, true) == nil,
  "and it is a real downgrade word, not 'no change' (got " .. tostring(rg) .. ")")

-- ---- 1i. Holy and Protection are untouched ---------------------------------
-- The research card says those rows need their own evidence (routed to
-- t_7eb0fee4). This pins that this card did not quietly borrow the Ret numbers.
local PAL = V.WEIGHTS.PALADIN
check(PAL.spell.w.Intellect == 4 and PAL.spell.w.Stamina == 1
  and PAL.spell.w.Agility == nil and PAL.spell.tiebreak == nil,
  "the Holy table is unchanged")
check(PAL.tank.w.Stamina == 4 and PAL.tank.w.Armor == 2 and PAL.tank.w.Intellect == 1
  and PAL.tank.w.Strength == 1 and PAL.tank.w.Block == 1 and PAL.tank.w.Agility == nil
  and PAL.tank.tiebreak == nil,
  "the Protection table is unchanged")
-- And no OTHER class gained a tiebreaker list: the tier is Ret-only.
for class, roles in pairs(V.WEIGHTS) do
  if class ~= "PALADIN" then
    for _, row in pairs(roles) do
      check(row.tiebreak == nil, "no tiebreaker list outside Retribution (" .. class .. ")")
    end
  end
end

-- ===========================================================================
-- 2. The line the player reads (ChestAdvisor.tooltipLines)
-- ===========================================================================
-- WoW stub: the same shapes tests/touchstone_weights_spec.lua proves.
local chat, frames = {}, {}

local function makeTexture()
  local t = {}
  for _, m in ipairs({ "SetPoint", "SetAllPoints", "SetTexture", "SetColorTexture",
    "SetTexCoord", "SetSize", "Hide", "Show", "SetBlendMode", "SetDesaturated" }) do
    t[m] = function() end
  end
  return t
end

local function makeFontString()
  local fs = { text = "" }
  fs.SetPoint = function() end
  fs.SetAllPoints = function() end
  fs.SetText = function(_, v) fs.text = v end
  fs.GetText = function() return fs.text end
  fs.SetTextColor = function() end
  fs.Hide = function() end
  fs.Show = function() end
  return fs
end

local function makeFrame(kind, name)
  local f = { kind = kind, name = name, events = {}, scripts = {} }
  f.RegisterEvent = function(_, e) f.events[e] = true end
  f.UnregisterEvent = function(_, e) f.events[e] = nil end
  f.IsEventRegistered = function(_, e) return f.events[e] == true end
  f.SetScript = function(_, k, fn) f.scripts[k] = fn end
  f.GetScript = function(_, k) return f.scripts[k] end
  f.HookScript = function() end
  f.CreateTexture = function() return makeTexture() end
  f.CreateFontString = function() return makeFontString() end
  frames[#frames + 1] = f
  if name then _G[name] = f end
  setmetatable(f, { __index = function() return function() end end })
  return f
end

chat, frames = {}, {}
SlashCmdList = setmetatable({}, { __newindex = function(t, k, v) rawset(t, k, v) end })
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
CreateFrame = makeFrame
UIParent = makeFrame("Frame", "UIParent")
MightiePackTouchstoneSkip = nil
StatForge, StatForgeDB, ChestAdvisor, ChestAdvisorDB = nil, nil, nil, nil
MightiePackDB = nil
C_AddOns = { DoesAddOnExist = function() return false end }
GetAddOnInfo, IsAddOnLoaded = nil, nil
_G.ChestAdvisor_Frame = nil
hooksecurefunc = function() end
TooltipDataProcessor = { AddTooltipPostCall = function() end }
Enum = { TooltipDataType = { Item = 0 } }

local function loaded(path, ...)
  local chunk, err = loadfile(path)
  check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
  if not chunk then return false end
  local ok, runErr = pcall(chunk, ...)
  check(ok, "load " .. path .. ": " .. tostring(runErr))
  return ok
end

local VENDORED = {
  "Constants.lua", "UI.lua", "OptionsTab.lua", "UpgradesTab.lua", "LogTab.lua",
  "Diagnostics.lua", "Probe.lua", "ChestAdvisor/Verdict.lua",
  "ChestAdvisor/ChestAdvisor.lua", "Integration.lua", "Core.lua",
}

local pkg = { Print = function(_, msg) chat[#chat + 1] = tostring(msg) end }
loaded(TOUCH .. "Bootstrap.lua", "MightiePack", pkg)
for _, name in ipairs(VENDORED) do
  loaded(TOUCH .. name, "MightiePack", pkg)
end
check(type(ChestAdvisor) == "table", "the vendored ChestAdvisor loaded")

ChestAdvisorDB = { role = {} }
pcall(ChestAdvisor.Enable, ChestAdvisor)
check(type(ChestAdvisor.tooltipLines) == "function",
  "ChestAdvisor.tooltipLines is the renderer's public surface")

-- The row the bag walk assembles: the comparator's own (verdict, reason,
-- weighted) plus the two line lists, the worn link and the class/role.
local function rowFor(cand, worn, wornLink, spec)
  local verdict, reason, wd = judge(cand, worn, spec)
  local row = {
    id = 1, bag = 0, slot = 1,
    verdict = verdict, reason = reason, role = spec.role, class = spec.class,
    lines = cand, chestWornLines = worn, wornLink = wornLink,
    invSlot = 8, slotWord = "feet",
  }
  if type(wd) == "table" then
    row.weighted = wd.total
    row.profile = wd.profile
    row.tiebreak = wd.tiebreak
  end
  return row
end

local function plain(text)
  return (tostring(text or ""):gsub("^%|c%x%x%x%x%x%x%x%x", ""):gsub("%|r$", ""))
end

-- ---- 2a. The boots pair reads as a flagged TIEBREAKER upgrade ---------------
local bootLines = ChestAdvisor.tooltipLines(rowFor(SAFETY_LINES, FERAL_LINES, FERAL_LINK, RET_SPEC))
local bootHead = plain(bootLines and bootLines[1] and bootLines[1].text)
print("rendered: " .. bootHead)
check(bootHead == "Upgrade — tiebreaker (+64 Armor, +2 Stamina) vs "
    .. FERAL_NAME .. " [Retribution]",
  "the boots headline is the flagged tiebreaker with its deltas (got " .. bootHead .. ")")
check(bootLines and bootLines[1] and bootLines[1].colour == "green",
  "a tiebreaker upgrade keeps the upgrade's green (got "
    .. tostring(bootLines and bootLines[1] and bootLines[1].colour) .. ")")
check(bootHead:find("weighted", 1, true) == nil,
  "and it does not claim a damage number it does not have (got " .. bootHead .. ")")

-- ---- 2b. The other direction reads "Not an upgrade — tiebreaker" ------------
local rbootLines = ChestAdvisor.tooltipLines(rowFor(FERAL_LINES, SAFETY_LINES, SAFETY_LINK, RET_SPEC))
local rbootHead = plain(rbootLines and rbootLines[1] and rbootLines[1].text)
print("rendered: " .. rbootHead)
check(rbootHead == "Not an upgrade — tiebreaker (-64 Armor, -2 Stamina) vs "
    .. SAFETY_NAME .. " [Retribution]",
  "the losing tiebreak is flagged, never 'Downgrade' (got " .. rbootHead .. ")")
check(rbootLines and rbootLines[1] and rbootLines[1].colour == "grey",
  "and it keeps the not-an-upgrade grey (got "
    .. tostring(rbootLines and rbootLines[1] and rbootLines[1].colour) .. ")")

-- ---- 2c. The cloak line is byte-identical to before -------------------------
local cloakRow = rowFor(CLOAK_CAND, CLOAK_WORN, CLOAK_WORN_LINK, RET_SPEC)
local cloakLines = ChestAdvisor.tooltipLines(cloakRow)
local cloakHead = plain(cloakLines and cloakLines[1] and cloakLines[1].text)
print("rendered: " .. cloakHead)
check(cloakHead == "Downgrade — weighted -16 vs Lambent Scale Cloak [Retribution]",
  "the cloak headline is unchanged (got " .. cloakHead .. ")")
check(cloakRow.tiebreak == nil, "and the cloak row carries no tiebreaker flag")

-- ---- 2d. An ordinary upgrade is still a weighted upgrade --------------------
-- +2 Strength, no survivability change: the plain sentence must survive, so the
-- new flag is visibly a different verdict from a damage upgrade.
local PLAIN_CAND = { "X", "Back", "19 Armor", "+6 Strength" }
local PLAIN_WORN = { "Y", "Back", "19 Armor", "+4 Strength" }
local plainLines = ChestAdvisor.tooltipLines(rowFor(PLAIN_CAND, PLAIN_WORN, CLOAK_WORN_LINK, RET_SPEC))
local plainHead = plain(plainLines and plainLines[1] and plainLines[1].text)
print("rendered: " .. plainHead)
check(plainHead == "Upgrade — weighted +8 vs Lambent Scale Cloak [Retribution]",
  "a damage upgrade keeps the weighted sentence (got " .. plainHead .. ")")

if failed > 0 then
  io.stderr:write(("touchstone_tiebreak_spec: %d failure(s)\n"):format(failed))
  os.exit(1)
end
print("touchstone_tiebreak_spec: ok")

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

-- ---- 1a. Retribution is the Wowhead order-only profile -------------------
local prof = V.profileFor(RET_SPEC)
check(type(prof) == "table", "the Retribution profile resolves")
if type(prof) == "table" then
  check(prof.kind == "order" and type(prof.tiers) == "table" and #prof.tiers >= 9,
    "Retribution is an order-only profile with the published tiers")
  check(prof.w == nil, "Retribution does not invent numeric weights")
  check(prof.tiebreak == nil, "Retribution has no tiebreak list")
  check(type(prof.source) == "string" and prof.source:find("wowhead.com", 1, true),
    "Retribution cites the Wowhead stat-priority page")
  local names = {}
  for _, tier in ipairs(prof.tiers) do names[#names + 1] = tier.name end
  check(names[1] == "Weapon Skill" and names[2] == "Weapon DPS & Speed"
      and names[3] == "Hit" and names[4] == "Expertise"
      and names[5] == "Spell Damage" and names[6] == "Intellect"
      and names[7] == "Strength & Attack Power"
      and names[8] == "Agility & Critical Strike Chance"
      and names[9] == "Stamina",
    "the published Wowhead order is the shipped tier list")
  check(prof.tiers[3].capPercent == 9 and prof.tiers[4].capPercent == 6.5,
    "Hit is capped at 9% and Expertise at 6.5%")
end
check(type(V.WEIGHT_EPSILON) == "number" and V.WEIGHT_EPSILON > 0,
  "epsilon is still a named constant (used by numeric fixture packs)")

-- ---- 1b. Equal Strength, more Stamina -> UPGRADE decided by Stamina -------
-- Safety Boots (115 Armor / +4 Str / +2 Sta) against Feral Shoes of Strength
-- (51 Armor / +4 Str). Armor is not on the Wowhead list, so Stamina (tier 9)
-- is the first (and only) ranked difference.
local vb, rb, wb = judge(SAFETY_LINES, FERAL_LINES, RET_SPEC)
check(vb == "UPGRADE", "the boots pair is an upgrade, got " .. tostring(vb))
check(type(wb) == "table" and wb.profile == "Retribution",
  "the boots verdict quotes its profile (got " .. tostring(wb and wb.profile) .. ")")
check(type(wb) == "table" and wb.decidedBy == "Stamina",
  "the boots pair is decided by Stamina (got " .. tostring(wb and wb.decidedBy) .. ")")
check(type(wb) == "table" and wb.tiebreak == nil,
  "there is no tiebreak flag on an order-only verdict")
check(type(rb) == "string" and rb == "decided by Stamina [Retribution]",
  "the reason names the deciding tier (got " .. tostring(rb) .. ")")

-- ---- 1c. The same pair reversed is a Stamina downgrade --------------------
local vr, rr, wr = judge(FERAL_LINES, SAFETY_LINES, RET_SPEC)
check(vr == "NOT_UPGRADE", "the reversed boots pair is not an upgrade, got " .. tostring(vr))
check(type(wr) == "table" and wr.decidedBy == "Stamina",
  "the reverse is also decided by Stamina (got " .. tostring(wr and wr.decidedBy) .. ")")
check(type(rr) == "string" and rr == "decided by Stamina [Retribution]",
  "the reason names the deciding tier (got " .. tostring(rr) .. ")")

-- ---- 1d. Strength (tier 7) beats any Stamina / unlisted Armor swing --------
local ONE_STR_CAND = { "X", "Back", "500 Armor", "+5 Strength", "+10 Stamina" }
local ONE_STR_WORN = { "Y", "Back", "10 Armor", "+4 Strength" }
local v1, r1, w1 = judge(ONE_STR_CAND, ONE_STR_WORN, RET_SPEC)
check(v1 == "UPGRADE", "one more Strength is an upgrade, got " .. tostring(v1))
check(type(r1) == "string" and r1:find("decided by Strength & Attack Power", 1, true),
  "Strength decides before Stamina (got " .. tostring(r1) .. ")")
local v1b = judge(ONE_STR_WORN, ONE_STR_CAND, RET_SPEC)
check(v1b == "NOT_UPGRADE",
  "one point of Strength LESS is a downgrade, however much stamina comes with it (got "
    .. tostring(v1b) .. ")")

-- ---- 1e. Agility (tier 8) vs a Stamina-only swing is a Trade-off -----------
-- Agility is ranked above Stamina, and Armor is unlisted, so +1 Agi against
-- 500 Armor / +10 Sta is a Trade-off — a later ranked loss is not ignored.
local ONE_AGI_CAND = { "X", "Back", "10 Armor", "+1 Agility" }
local ONE_AGI_WORN = { "Y", "Back", "500 Armor", "+10 Stamina" }
local v2, r2, w2 = judge(ONE_AGI_CAND, ONE_AGI_WORN, RET_SPEC)
check(v2 == "TRADE_OFF", "one more Agility vs more Stamina is a Trade-off, got " .. tostring(v2))
check(type(r2) == "string" and r2:find("decided by Agility & Critical Strike Chance", 1, true)
    and r2:find("Trade-off: +Agility vs −Stamina", 1, true),
  "Agility vs Stamina names both sides (got " .. tostring(r2) .. ")")
local v2b, r2b = judge(ONE_AGI_WORN, ONE_AGI_CAND, RET_SPEC)
check(v2b == "NOT_UPGRADE",
  "one point of Agility LESS is still a downgrade, even with more Stamina (got "
    .. tostring(v2b) .. " " .. tostring(r2b) .. ")")

-- ---- 1f. Unlisted Armor cannot beat a Stamina difference -------------------
-- The old Ret tiebreak ranked Armor above Stamina. The Wowhead list does not
-- name Armor at all, so +10 Armor against +50 Stamina is a Stamina loss.
local ARM_CAND = { "X", "Back", "20 Armor" }
local ARM_WORN = { "Y", "Back", "10 Armor", "+50 Stamina" }
local v3, r3, w3 = judge(ARM_CAND, ARM_WORN, RET_SPEC)
check(v3 == "NOT_UPGRADE", "unlisted Armor cannot beat a Stamina loss, got " .. tostring(v3))
check(type(w3) == "table" and w3.decidedBy == "Stamina",
  "Stamina is the deciding tier (got " .. tostring(w3 and w3.decidedBy) .. ")")
local v3b = judge(ARM_WORN, ARM_CAND, RET_SPEC)
check(v3b == "UPGRADE",
  "the Stamina gain (with less unlisted Armor) is an upgrade (got " .. tostring(v3b) .. ")")

-- ---- 1g. The cloak case is still a downgrade, now by Strength --------------
-- Worn: +4 Strength, +2 Spirit, 19 Armor. Candidate: +3 Stamina, 16 Armor.
-- Strength is the first ranked difference.
local vc, rc, wc = judge(CLOAK_CAND, CLOAK_WORN, RET_SPEC)
check(vc == "NOT_UPGRADE", "the cloak case is still a downgrade, got " .. tostring(vc))
check(type(wc) == "table" and wc.decidedBy == "Strength & Attack Power",
  "the cloak case is decided by Strength (got " .. tostring(wc and wc.decidedBy) .. ")")
check(type(wc) == "table" and wc.tiebreak == nil, "and no tiebreaker is involved")
check(rc == "decided by Strength & Attack Power [Retribution]",
  "the cloak reason names the deciding tier (got " .. tostring(rc) .. ")")

-- ---- 1h. Gloves: +1 Strength vs an Agility loss is a Trade-off -------------
-- Equipped Gloves of the Fang (52 Armor, +4 Str, +6 Agi); hovering Dagmire
-- Gauntlets (110 Armor, +5 Str, +2 Agi). Strength is tier 7 and Agility is
-- tier 8, so this is a Trade-off, not an Upgrade.
local vg, rg, wg = judge(DAG_LINES, FANG_LINES, RET_SPEC)
check(vg == "TRADE_OFF", "the gloves pair is a Trade-off, got " .. tostring(vg))
check(type(rg) == "string" and rg:find("decided by Strength & Attack Power", 1, true)
    and rg:find("Trade-off: +Strength vs −Agility", 1, true),
  "Dagmire vs Fang names both sides (got " .. tostring(rg) .. ")")
local candStats = V.statTable(DAG_LINES, "candidate")
local wornStats = V.statTable(FANG_LINES, "worn")
check(type(candStats) == "table" and candStats.Agility == 2 and candStats.Strength == 5,
  "the Dagmire parse is the client's (5 Str, 2 Agi)")
check(type(wornStats) == "table" and wornStats.Agility == 6 and wornStats.Strength == 4,
  "the Fang parse is the client's (4 Str, 6 Agi)")

-- ---- 1j. Trophy Belt vs Stormbringer Belt is a Trade-off (live Ret case) --
-- Worn: Stormbringer Belt, Mail, 104 Armor, +5 Str, +2 Sta.
-- Candidate: Trophy Belt, Mail, 101 Armor, +5 Int, +3 Spi.
-- Intellect is first, but Strength and Stamina are later ranked losses.
-- Unranked Spirit and Armor must not appear in the Trade-off clause.
local STORM_NAME = "Stormbringer Belt"
local STORM_LINES = {
  STORM_NAME, "Binds when equipped", "Waist Mail",
  "104 Armor", "+5 Strength", "+2 Stamina",
}
local TROPHY_NAME = "Trophy Belt"
local TROPHY_LINES = {
  TROPHY_NAME, "Binds when equipped", "Waist Mail",
  "101 Armor", "+5 Intellect", "+3 Spirit",
}
local STORM_LINK = link(14783, STORM_NAME)
local vt, rt, wt = judge(TROPHY_LINES, STORM_LINES, RET_SPEC)
check(vt == "TRADE_OFF", "Trophy Belt vs Stormbringer Belt is a Trade-off, got " .. tostring(vt))
check(type(wt) == "table" and wt.decidedBy == "Intellect",
  "the belt pair is decided by Intellect (got " .. tostring(wt and wt.decidedBy) .. ")")
check(type(rt) == "string" and rt:find("decided by Intellect", 1, true)
    and rt:find("Trade-off: +Intellect vs −Strength, −Stamina", 1, true),
  "the belt reason names both sides (got " .. tostring(rt) .. ")")
check(type(rt) == "string" and rt:find("Spirit", 1, true) == nil
    and rt:find("Armor", 1, true) == nil,
  "unranked Spirit and Armor do not decide the belt pair (got " .. tostring(rt) .. ")")
check(type(wt) == "table" and wt.tradeOffText == "Trade-off: +Intellect vs −Strength, −Stamina",
  "detail.tradeOffText is the both-sides clause (got " .. tostring(wt and wt.tradeOffText) .. ")")

-- ---- 1k. Ranked equality uses WEIGHT_EPSILON, not exact signedDelta ~= 0 --
-- A crumb smaller than the named floor on the first ranked stat must
-- not become an Upgrade. Without the floor, 5 + 0.1*eps ~= 5 and the
-- pair would be decided by Strength.
local noise = V.WEIGHT_EPSILON * 0.1
local vN, rN, wN = V.orderVerdict(
  { Strength = 5 + noise, Stamina = 2, Armor = 100 },
  { Strength = 5, Stamina = 2, Armor = 100 },
  RET_SPEC)
check(vN == "NOT_UPGRADE",
  "a ranked delta inside WEIGHT_EPSILON is not an Upgrade (got " .. tostring(vN) .. ")")
check(type(rN) == "string" and rN:find("no change", 1, true),
  "float noise is treated as no change (got " .. tostring(rN) .. ")")
-- The same crumb must also be ignored when a later ranked stat really
-- differs, so the first real difference (Stamina) still decides.
local vN2, rN2, wN2 = V.orderVerdict(
  { Strength = 5 + noise, Stamina = 3, Armor = 100 },
  { Strength = 5, Stamina = 2, Armor = 100 },
  RET_SPEC)
check(vN2 == "UPGRADE",
  "a real Stamina gain still upgrades when Strength only has noise (got " .. tostring(vN2) .. ")")
check(type(wN2) == "table" and wN2.decidedBy == "Stamina",
  "the pair is decided by Stamina, not the Strength crumb (got " .. tostring(wN2 and wN2.decidedBy) .. ")")
-- The same floor applies to a capped-window rating (Hit, line ~5022).
-- A crumb inside WEIGHT_EPSILON must not become an Upgrade.
local vH, rH = V.orderVerdict(
  { Hit = 10 + noise, Strength = 5, Stamina = 2, Armor = 100 },
  { Hit = 10, Strength = 5, Stamina = 2, Armor = 100 },
  RET_SPEC)
check(vH == "NOT_UPGRADE",
  "a capped Hit crumb inside WEIGHT_EPSILON is not an Upgrade (got " .. tostring(vH) .. ")")
check(type(rH) == "string" and rH:find("no change", 1, true),
  "a capped Hit crumb is treated as no change (got " .. tostring(rH) .. ")")

-- tiebreakTotal uses the same WEIGHT_EPSILON floor, not exact ~= 0.
-- Shipped profiles have no tiebreak list, so this uses a fixture.
local TB_PROFILE = { name = "TiebreakFixture", tiebreak = { "Armor", "Stamina" } }
local tbNil = V.tiebreakTotal(
  { Armor = 100 + noise, Stamina = 10 },
  { Armor = 100, Stamina = 10 },
  TB_PROFILE)
check(tbNil == nil,
  "a tiebreak Armor crumb inside WEIGHT_EPSILON is not a decision (got "
    .. tostring(tbNil) .. ")")
local tbHit = V.tiebreakTotal(
  { Armor = 101, Stamina = 10 },
  { Armor = 100, Stamina = 10 },
  TB_PROFILE)
check(type(tbHit) == "table" and tbHit.stat == "Armor" and tbHit.dir == 1,
  "a real Armor gain still decides the tiebreak (got "
    .. tostring(tbHit and tbHit.stat) .. ")")
local tbStam = V.tiebreakTotal(
  { Armor = 100 + noise, Stamina = 11 },
  { Armor = 100, Stamina = 10 },
  TB_PROFILE)
check(type(tbStam) == "table" and tbStam.stat == "Stamina" and tbStam.dir == 1,
  "a real Stamina gain still decides when Armor only has noise (got "
    .. tostring(tbStam and tbStam.stat) .. ")")

-- ---- 1i. Holy and Protection are their own Wowhead order-only profiles ----
local PAL = V.WEIGHTS.PALADIN
check(PAL.holy and PAL.holy.kind == "order" and PAL.holy.w == nil
    and PAL.holy.tiers and PAL.holy.tiers[1] and PAL.holy.tiers[1].name == "Healing Power",
  "Holy is its own Wowhead order-only profile, not the Ret order")
check(PAL.prot and PAL.prot.kind == "order" and PAL.prot.w == nil
    and PAL.prot.variant == "Balanced",
  "Protection is Wowhead's Balanced order-only profile, not the Ret order")
-- No shipped profile carries a Ret-style numeric tiebreak list.
for class, roles in pairs(V.WEIGHTS) do
  for _, row in pairs(roles) do
    check(row.tiebreak == nil, "no tiebreaker list on " .. class)
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
    row.decidedBy = wd.decidedBy
    row.orderOutcome = wd.orderOutcome
    row.tradeOffText = wd.tradeOffText
  end
  return row
end

local function plain(text)
  return (tostring(text or ""):gsub("^%|c%x%x%x%x%x%x%x%x", ""):gsub("%|r$", ""))
end

-- ---- 2a. The boots pair reads as a Stamina-decided upgrade ------------------
local bootLines = ChestAdvisor.tooltipLines(rowFor(SAFETY_LINES, FERAL_LINES, FERAL_LINK, RET_SPEC))
local bootHead = plain(bootLines and bootLines[1] and bootLines[1].text)
print("rendered: " .. bootHead)
check(bootHead == "Upgrade — decided by Stamina vs " .. FERAL_NAME .. " [Retribution]",
  "the boots headline names the deciding tier (got " .. bootHead .. ")")
check(bootLines and bootLines[1] and bootLines[1].colour == "green",
  "an order-only upgrade keeps the upgrade's green (got "
    .. tostring(bootLines and bootLines[1] and bootLines[1].colour) .. ")")
check(bootHead:find("weighted", 1, true) == nil,
  "and it does not invent a weighted number (got " .. bootHead .. ")")

-- ---- 2b. The other direction is a Stamina downgrade -------------------------
local rbootLines = ChestAdvisor.tooltipLines(rowFor(FERAL_LINES, SAFETY_LINES, SAFETY_LINK, RET_SPEC))
local rbootHead = plain(rbootLines and rbootLines[1] and rbootLines[1].text)
print("rendered: " .. rbootHead)
check(rbootHead == "Downgrade — decided by Stamina vs " .. SAFETY_NAME .. " [Retribution]",
  "the reverse boots headline is a downgrade decided by Stamina (got " .. rbootHead .. ")")
check(rbootLines and rbootLines[1] and rbootLines[1].colour == "grey",
  "and it keeps the not-an-upgrade grey (got "
    .. tostring(rbootLines and rbootLines[1] and rbootLines[1].colour) .. ")")

-- ---- 2c. The cloak line names Strength --------------------------------------
local cloakRow = rowFor(CLOAK_CAND, CLOAK_WORN, CLOAK_WORN_LINK, RET_SPEC)
local cloakLines = ChestAdvisor.tooltipLines(cloakRow)
local cloakHead = plain(cloakLines and cloakLines[1] and cloakLines[1].text)
print("rendered: " .. cloakHead)
check(cloakHead == "Downgrade — decided by Strength & Attack Power vs Lambent Scale Cloak [Retribution]",
  "the cloak headline names the deciding tier (got " .. cloakHead .. ")")
check(cloakRow.tiebreak == nil, "and the cloak row carries no tiebreaker flag")

-- ---- 2d. An ordinary Strength upgrade also uses the decided-by sentence -----
local PLAIN_CAND = { "X", "Back", "19 Armor", "+6 Strength" }
local PLAIN_WORN = { "Y", "Back", "19 Armor", "+4 Strength" }
local plainLines = ChestAdvisor.tooltipLines(rowFor(PLAIN_CAND, PLAIN_WORN, CLOAK_WORN_LINK, RET_SPEC))
local plainHead = plain(plainLines and plainLines[1] and plainLines[1].text)
print("rendered: " .. plainHead)
check(plainHead == "Upgrade — decided by Strength & Attack Power vs Lambent Scale Cloak [Retribution]",
  "a Strength upgrade uses the decided-by sentence (got " .. plainHead .. ")")

-- ---- 2e. Trophy Belt tooltip keeps decided-by and names both sides ---------
local beltLines = ChestAdvisor.tooltipLines(rowFor(TROPHY_LINES, STORM_LINES, STORM_LINK, RET_SPEC))
local beltHead = plain(beltLines and beltLines[1] and beltLines[1].text)
print("rendered: " .. beltHead)
check(beltHead == "Trade-off: +Intellect vs −Strength, −Stamina — decided by Intellect vs " .. STORM_NAME .. " [Retribution]",
  "the belt headline names both sides and keeps decided-by (got " .. beltHead .. ")")
check(beltLines and beltLines[1] and beltLines[1].colour == "amber",
  "a Trade-off keeps the amber chip colour (got "
    .. tostring(beltLines and beltLines[1] and beltLines[1].colour) .. ")")

if failed > 0 then
  io.stderr:write(("touchstone_tiebreak_spec: %d failure(s)\n"):format(failed))
  os.exit(1)
end
print("touchstone_tiebreak_spec: ok")

-- The verdict follows the active profile's WEIGHTS, not the sign of any change
-- (card t_3a744b4a).
--
-- Live defect this pins. Mightie, Retribution paladin:
--
--     equipped  Lambent Scale Cloak   19 Armor  +4 Str  +2 Spi
--     hovered   Barkeeper's Cloak     16 Armor  +3 Sta
--     printed   "Trade-off — better on some stats, worse on others"
--
-- The old comparator counted DIRECTIONS: one stat up and one stat down was a
-- trade-off however lopsided the pair. The owner's ruling: "It should say
-- downgrade for the active Ret damage profile. A gain in any secondary stat must
-- not automatically trigger 'trade-off'; evaluate the weighted result and show
-- the stamina gain only as supporting detail."
--
-- Three halves, all driven through the real vendored files:
--
--   1. the COMPARATOR (Verdict.lua, loaded on its own): the weighted total
--      decides, epsilon is a named constant, a zero-weight stat cannot move the
--      verdict, a missing profile is "unavailable" and never a trade-off, and the
--      same item pair flips to UPGRADE under a stamina-heavy tank profile —
--      which is what proves the WEIGHTS are driving it;
--   2. the ROW the scan builds (Verdict.evaluate's third return) and
--   3. the LINE the player reads (ChestAdvisor.tooltipLines), which must lead
--      with "Downgrade — weighted -16 vs Lambent Scale Cloak [Retribution]" and
--      keep the stamina delta in the supporting detail underneath.
--
-- Fails on 8828350: there the comparator answers TRADE_OFF for the live pair
-- (proved below, first assertion of section 1) and no line carries a weight.
--
-- Run from the repo root:  lua5.1 tests/touchstone_weights_spec.lua

local here = (arg and arg[0] or "tests/touchstone_weights_spec.lua"):match("^(.*)[/\\][^/\\]*$") or "."
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

-- ---- The live pair, as the client's tooltip renders it ----------------------
local WORN_NAME = "Lambent Scale Cloak"
local CAND_NAME = "Barkeeper's Cloak"
local WORN_LINES = {
  WORN_NAME, "Binds when equipped", "Back",
  "19 Armor", "+4 Strength", "+2 Spirit", "Requires Level 21",
}
local CAND_LINES = {
  CAND_NAME, "Back", "16 Armor", "+3 Stamina", "Requires Level 18",
}
local WORN_LINK = "|cff1eff00|Hitem:5341:0:0:0:0:0:0:0|h[" .. WORN_NAME .. "]|h|r"
local CAND_LINK = "|cff1eff00|Hitem:5342:0:0:0:0:0:0:0|h[" .. CAND_NAME .. "]|h|r"

-- ===========================================================================
-- 1. The comparator, on its own
-- ===========================================================================
local loadVerdict = assert(loadfile(TOUCH .. "ChestAdvisor/Verdict.lua"))
local V = loadVerdict()
check(type(V) == "table", "Verdict.lua loads and returns the module")

local function judge(cand, worn, spec)
  return V.evaluate({ canUse = true, line = cand }, { line = worn }, spec, nil)
end

-- The Retribution profile as buildSpec resolves it: the class token, the role
-- word its order came from, and the CLIENT's own role word.
local RET_SPEC = {
  class = "PALADIN", role = "melee", clientRole = "DAMAGER",
  order = V.classRoleOrder("PALADIN", "melee"), level = 70,
}
local PROT_SPEC = {
  class = "PALADIN", role = "spell", clientRole = "TANK",
  order = V.classRoleOrder("PALADIN", "spell"), level = 70,
}

-- ---- 1a. The live case is a DOWNGRADE with a negative weighted total -------
local v, reason, weighted = judge(CAND_LINES, WORN_LINES, RET_SPEC)
check(v == "NOT_UPGRADE",
  "live case: the verdict is a downgrade (NOT_UPGRADE), got " .. tostring(v))
check(type(weighted) == "table" and type(weighted.total) == "number",
  "live case: the comparator returns the weighted total it decided on")
if type(weighted) == "table" then
  check(weighted.total < 0,
    "live case: the weighted total is negative, got " .. tostring(weighted.total))
  -- -4 Str x 4 + 3 Sta x 0 + -3 Armor x 0 + -2 Spi x 0
  check(weighted.total == -16,
    "live case: -4 Str at weight 4 and three zero-weight stats = -16, got "
      .. tostring(weighted.total))
  check(weighted.profile == "Retribution",
    "live case: the profile is named, got " .. tostring(weighted.profile))
end
check(type(reason) == "string" and reason:find("Retribution", 1, true) ~= nil,
  "live case: the reason quotes the profile (got " .. tostring(reason) .. ")")
check(type(reason) == "string" and reason:find("-16", 1, true) ~= nil,
  "live case: the reason quotes the weighted total (got " .. tostring(reason) .. ")")

-- ---- 1b. The SAME pair is an UPGRADE for a stamina-heavy tank profile -------
-- This is the acceptance's proof that the weights, not the direction of the
-- deltas, decide: identical numbers, opposite verdict.
local vp, rp, wp = judge(CAND_LINES, WORN_LINES, PROT_SPEC)
check(vp == "UPGRADE",
  "the same pair is an upgrade for Protection, got " .. tostring(vp))
check(type(wp) == "table" and wp.total > 0,
  "Protection's weighted total is positive, got " .. tostring(wp and wp.total))
-- +3 Sta x 4 + -3 Armor x 2 + -4 Str x 1 = +2
check(type(wp) == "table" and wp.total == 2,
  "Protection: 3 Sta x4, -3 Armor x2, -4 Str x1 = +2, got " .. tostring(wp and wp.total))
check(type(wp) == "table" and wp.profile == "Protection",
  "Protection names its profile, got " .. tostring(wp and wp.profile))

-- ---- 1c. epsilon is a named constant, not a number in the branch ----------
check(type(V.WEIGHT_EPSILON) == "number" and V.WEIGHT_EPSILON > 0,
  "epsilon is an explicit named constant (Verdict.WEIGHT_EPSILON)")

-- ---- 1d. A genuine sidegrade still says trade-off --------------------------
-- +1 Str (+4) and -2 Int (-4) under the Ret profile: equal weighted total, one
-- stat up, one stat down. That is the one shape a trade-off describes.
-- (Card t_c4911603 moved Intellect 1 -> 2 on the researched Ret table, so this
-- fixture's Intellect swing is -2, not -4: the arithmetic it pins is "equal
-- damage on both sides", not the old weight.)
local SIDE_WORN = { "X", "+11 Strength", "+12 Intellect" }
local SIDE_CAND = { "Y", "+12 Strength", "+10 Intellect" }
local vs_, rs, ws = judge(SIDE_CAND, SIDE_WORN, RET_SPEC)
check(vs_ == "TRADE_OFF", "a genuine sidegrade is a trade-off, got " .. tostring(vs_))
check(type(ws) == "table" and ws.total == 0,
  "the sidegrade's weighted total is 0, got " .. tostring(ws and ws.total))

-- ---- 1e. A zero-weight stat that rises, with nothing else moving ----------
-- +3 Spirit is weight 0 on the Retribution damage profile — and, unlike Stamina
-- since card t_c4911603, it is not a tiebreaker either. It must not move the
-- verdict: the same pair without it is also NOT_UPGRADE, and this one is not a
-- trade-off either. (The fixture used Stamina before the tiebreaker tier
-- existed; Stamina now legitimately decides a damage tie, so Spirit is the stat
-- that still proves the zero-weight point.)
local ZERO_BASE = { "X", "+10 Strength" }
local ZERO_STAM = { "Y", "+10 Strength", "+3 Spirit" }
local vz, rz, wz = judge(ZERO_STAM, ZERO_BASE, RET_SPEC)
check(vz == "NOT_UPGRADE",
  "a zero-weight stat cannot move the verdict, got " .. tostring(vz))
check(vz ~= "TRADE_OFF",
  "a zero-weight gain is never a trade-off (got the trade-off token)")
check(type(wz) == "table" and wz.total == 0,
  "the zero-weight gain weighs 0, got " .. tostring(wz and wz.total))
local same = judge(ZERO_BASE, ZERO_BASE, RET_SPEC)
check(same == vz, "the verdict is unchanged by the zero-weight stat")
check(type(rz) == "string" and rz:find("no change", 1, true) ~= nil,
  "the zero-weight outcome reads as no change (got " .. tostring(rz) .. ")")

-- ---- 1f. The legacy switch really switches --------------------------------
-- LEGACY_DOMINANCE_DECIDES is test instrumentation (it lets a fixture run through
-- both comparators in one VM). A switch that the new path returns before reaching
-- is a lie, so this pins both ends: set -> the pre-card direction count, unset ->
-- the weighted verdict.
V.LEGACY_DOMINANCE_DECIDES = true
local legacy, legacyReason = judge(CAND_LINES, WORN_LINES, RET_SPEC)
check(legacy == "TRADE_OFF",
  "LEGACY_DOMINANCE_DECIDES reproduces the pre-card direction count, got "
    .. tostring(legacy) .. " (" .. tostring(legacyReason) .. ")")
V.LEGACY_DOMINANCE_DECIDES = false
local shipped = judge(CAND_LINES, WORN_LINES, RET_SPEC)
check(shipped == "NOT_UPGRADE",
  "and the shipped default is the weighted verdict, got " .. tostring(shipped))

-- ---- 1g. No profile weights is "unavailable", never a trade-off ------------
local vu, ru = judge(CAND_LINES, WORN_LINES, { order = V.classRoleOrder("PALADIN", "melee") })
check(vu ~= "TRADE_OFF", "no profile weights is never a trade-off, got " .. tostring(vu))
check(vu == "UNKNOWN", "no profile weights is an unavailable verdict, got " .. tostring(vu))
check(type(ru) == "string" and ru:find("verdict unavailable", 1, true) ~= nil,
  "and it says so, with the reason (got " .. tostring(ru) .. ")")
check(type(ru) == "string" and ru:find("no stat weights", 1, true) ~= nil,
  "the reason names the missing weights (got " .. tostring(ru) .. ")")
-- A feral Druid is the same story: no documented order, so no weights, no guess.
-- A pure class ignores the role word (it has one documented order, so one default
-- profile). Both go through the one resolver, so neither can invent a profile.
local profileFor = V.profileFor
check(type(profileFor) == "function",
  "Verdict.profileFor resolves the active profile")
if type(profileFor) == "function" then
  check(profileFor({ class = "DRUID", role = "melee" }) == nil,
    "a feral Druid has no weight profile (no documented order)")
  check(type(profileFor({ class = "WARRIOR", role = "WARRIOR" })) == "table",
    "a pure class resolves its one profile with no role word")
end

-- ===========================================================================
-- 2. The row the scan builds and 3. the line the player reads
-- ===========================================================================
-- WoW stub: the same shapes tests/touchstone_tooltip_line_spec.lua proves.
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

-- The scan's row, assembled exactly the way the bag walk assembles it: the
-- comparator's own (verdict, reason, weighted) on the row, the two line lists it
-- was decided on, the worn link, and the class/role the delta order comes from.
local function rowFor(spec)
  local verdict, reason, wd = judge(CAND_LINES, WORN_LINES, spec)
  local row = {
    id = 5342, bag = 0, slot = 1,
    verdict = verdict, reason = reason, role = spec.role, class = spec.class,
    lines = CAND_LINES, chestWornLines = WORN_LINES, wornLink = WORN_LINK,
    invSlot = 6, slotWord = "back",
  }
  if type(wd) == "table" then
    row.weighted = wd.total
    row.profile = wd.profile
  end
  return row
end

local function plain(text)
  return (tostring(text or ""):gsub("^%|c%x%x%x%x%x%x%x%x", ""):gsub("%|r$", ""))
end

-- ---- 3a. The live case, as the player reads it ------------------------------
local lines = ChestAdvisor.tooltipLines(rowFor(RET_SPEC))
check(type(lines) == "table" and #lines >= 2,
  "the live case renders a headline AND a detail line (got "
    .. tostring(lines and #lines) .. ")")
local headline = plain(lines and lines[1] and lines[1].text)
print("rendered: " .. headline)
if type(lines) == "table" and lines[2] then print("detail:   " .. plain(lines[2].text)) end

check(headline:sub(1, #"Downgrade") == "Downgrade",
  "the headline word is Downgrade (got " .. headline .. ")")
check(headline:find("weighted -16", 1, true) ~= nil,
  "the headline quotes the weighted total (got " .. headline .. ")")
check(headline:find("vs " .. WORN_NAME, 1, true) ~= nil,
  "the headline names the item it was compared against (got " .. headline .. ")")
check(headline:find("[" .. "Retribution" .. "]", 1, true) ~= nil,
  "the headline names the active profile (got " .. headline .. ")")
check(lines and lines[1] and lines[1].colour == "grey",
  "a downgrade is neither green nor amber (got "
    .. tostring(lines and lines[1] and lines[1].colour) .. ")")

local detail = plain(lines and lines[2] and lines[2].text)
check(detail == "-4 Str, +3 Sta, -3 Armor, -2 Spi",
  "the detail is the read arithmetic in the profile's own stat order (got " .. detail .. ")")

-- The detail is arithmetic, not a second verdict: the profile and the word
-- belong to the headline only.
check(detail:find("Retribution", 1, true) == nil,
  "the profile is named once, in the headline (got " .. detail .. ")")

-- ---- 3b. The same pair under Protection reads as an upgrade -----------------
local protLines = ChestAdvisor.tooltipLines(rowFor(PROT_SPEC))
local protHead = plain(protLines and protLines[1] and protLines[1].text)
check(protHead:sub(1, #"Upgrade") == "Upgrade",
  "Protection sees an Upgrade for the same pair (got " .. protHead .. ")")
check(protHead:find("weighted +2", 1, true) ~= nil,
  "and it quotes Protection's total (got " .. protHead .. ")")
check(protHead:find("[Protection]", 1, true) ~= nil,
  "and names Protection (got " .. protHead .. ")")
check(protLines and protLines[1] and protLines[1].colour == "green",
  "an upgrade keeps the green the arrow uses (got "
    .. tostring(protLines and protLines[1] and protLines[1].colour) .. ")")

-- ---- 3c. A genuine sidegrade is still an amber Trade-off --------------------
local sideRow = {
  id = 5343, verdict = "TRADE_OFF",
  reason = "weighted 0 [Retribution] — better on some stats, worse on others",
  weighted = 0, profile = "Retribution",
  lines = { "Y", "+12 Strength", "+8 Intellect" },
  chestWornLines = { "X", "+11 Strength", "+12 Intellect" },
  wornLink = "|cff1eff00|Hitem:9001:0:0:0:0:0:0:0|h[Old Shoulders]|h|r",
}
local sideLines = ChestAdvisor.tooltipLines(sideRow)
local sideHead = plain(sideLines and sideLines[1] and sideLines[1].text)
check(sideHead:sub(1, #"Trade-off") == "Trade-off",
  "a sidegrade still reads Trade-off (got " .. sideHead .. ")")
check(sideLines and sideLines[1] and sideLines[1].colour == "amber",
  "and keeps the amber the chip uses (got "
    .. tostring(sideLines and sideLines[1] and sideLines[1].colour) .. ")")

-- ---- 3d. A zero-weight gain alone does not become a line that says change --
local zeroRow = {
  id = 5344, verdict = "NOT_UPGRADE", reason = "weighted 0 [Retribution] — no change",
  weighted = 0, profile = "Retribution",
  lines = { "Y", "+10 Strength", "+3 Stamina" },
  chestWornLines = { "X", "+10 Strength" },
  wornLink = "|cff1eff00|Hitem:9002:0:0:0:0:0:0:0|h[Old Bracers]|h|r",
}
local zeroHead = plain(ChestAdvisor.tooltipLines(zeroRow)[1].text)
check(zeroHead:sub(1, #"No change") == "No change",
  "a weighted zero with one gain reads No change (got " .. zeroHead .. ")")
check(zeroHead:find("weighted 0", 1, true) ~= nil,
  "and still quotes the total (got " .. zeroHead .. ")")

-- ---- 3e. A row with no weighted total renders the old way ------------------
-- Weapon rows, empty slots and rows persisted before this card carry no number;
-- they must be byte-identical to the pre-card rendering.
local legacyRow = {
  id = 5345, verdict = "NOT_UPGRADE", reason = "less Armor (16 vs 19) on an otherwise equal item",
  lines = CAND_LINES, chestWornLines = WORN_LINES, wornLink = WORN_LINK,
}
local legacyHead = plain(ChestAdvisor.tooltipLines(legacyRow)[1].text)
check(legacyHead:sub(1, #"Not an upgrade") == "Not an upgrade",
  "a row with no weighted total keeps the old word (got " .. legacyHead .. ")")
check(legacyHead:find("weighted", 1, true) == nil,
  "and does not claim a number it does not have (got " .. legacyHead .. ")")

if failed > 0 then
  io.stderr:write(("touchstone_weights_spec: %d failure(s)\n"):format(failed))
  os.exit(1)
end
print("touchstone_weights_spec: ok")

-- Card t_6f0c7eaf — the tooltip carries the engine's disclosure clause on BOTH
-- renderers (the weighted line and the ordinal one).
--
-- THE OWNER'S REPORT (v0.3.9-beta, the installed bytes, one weapon pair, two
-- hover directions), reproduced here on the VENDORED file:
--
--   ZweiHander hovered (enchant + proc on the EQUIPPED Wolfsbane)
--     "Trade-off — decided by Healing Power [Holy] — Trade-off: +Healing vs
--      −Intellect"                                        ← clause MISSING
--   Wolfsbane hovered (enchant + proc on the HOVERED item)
--     "Not an upgrade — decided by Healing Power [Holy] (judged, with an
--      unpriced on-hit effect and an unpriced enchant on the hovered item)"
--                                                          ← clause present
--
-- The ENGINE is right in both: Verdict.compareWeapon appends the clause to
-- `reason` for every judged weapon verdict (asserted here FIRST, on the shipped
-- bytes). The clause was lost by TOOLTIP_UI.weighted, which builds its own
-- "decided by …" sentence out of row.decidedBy / tradeOffText / caveat and never
-- read row.reason. The ordinal renderer prints row.reason, which is why one
-- direction looked correct and the other did not.
--
-- THE RULE (landed upstream in StatForge, carried by the fold):
-- `disclosureClause(row.reason)` splits the engine's clause off the reason — it
-- is never re-spelled from row fields — and BOTH renderers append what it
-- returns. This spec pins that by rendering the SAME engine reason twice, once
-- as a weighted row and once as an ordinal row, and demanding BYTE-IDENTICAL
-- clause bytes, with each direction naming the side that carries the facts.
--
-- Run from the repo root:  lua5.1 tests/touchstone_disclosure_spec.lua
-- TS_ADVISOR_SRC=<path> renders through a different ChestAdvisor.lua (the
-- pre-card copy, or a mutated one) — that is how the non-vacuity run points the
-- SAME assertions at the old renderer.

local here = (arg and arg[0] or "tests/touchstone_disclosure_spec.lua")
  :match("^(.*)[/\\][^/\\]*$") or "."
local root = here:gsub("[/\\]tests$", "")
if root == "tests" then root = "." end
local TOUCH = root .. "/MightiePack/Modules/Touchstone/"
local ADVISOR = os.getenv("TS_ADVISOR_SRC") or (TOUCH .. "ChestAdvisor/ChestAdvisor.lua")

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
if not fileExists(ADVISOR) then
  io.stderr:write("FAIL: TS_ADVISOR_SRC names a file that does not exist: " .. ADVISOR .. "\n")
  os.exit(1)
end

-- ---- WoW stub (the shapes tests/touchstone_tooltip_line_spec.lua proves) ----
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
  fs.SetWidth = function() end
  fs.SetJustifyH = function() end
  fs.SetWordWrap = function() end
  fs.SetNonSpaceWrap = function() end
  fs.Hide = function() end
  fs.Show = function() end
  return fs
end

local function makeFrame(kind, name)
  local f = { kind = kind, name = name, events = {}, scripts = {}, children = {} }
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

local function resetEnv()
  chat, frames = {}, {}
  SlashCmdList = setmetatable({}, { __newindex = function(t, k, v) rawset(t, k, v) end })
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
  CreateFrame = makeFrame
  UIParent = makeFrame("Frame", "UIParent")
  frames = {}
  MightiePackTouchstoneSkip = nil
  StatForge, StatForgeDB, ChestAdvisor, ChestAdvisorDB = nil, nil, nil, nil
  MightiePackDB = nil
  C_AddOns = { DoesAddOnExist = function() return false end }
  GetAddOnInfo, IsAddOnLoaded = nil, nil
  _G.ChestAdvisor_Frame = nil
  hooksecurefunc = function() end
  UnitClass = function() return "Paladin", "PALADIN" end
  UnitLevel = function() return 40 end
  C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 1, "Holy", "", 0, "HEALER" end,
  }
  TooltipDataProcessor = {
    AddTooltipPreCall = function() end,
    AddTooltipPostCall = function() end,
  }
  Enum = { TooltipDataType = { Item = 0 } }
  CreateColor = function(r, g, b) return { GetRGB = function() return r, g, b end } end
end

local function loaded(path, ...)
  local chunk, err = loadfile(path)
  check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
  if not chunk then return false end
  local ok, runErr = pcall(chunk, ...)
  check(ok, "load " .. path .. ": " .. tostring(runErr))
  return ok
end

-- ---- Load the module the way the pack does ---------------------------------
resetEnv()
local pkg = { Print = function(_, msg) chat[#chat + 1] = tostring(msg) end }
loaded(TOUCH .. "Bootstrap.lua", "MightiePack", pkg)
for _, name in ipairs({ "Constants.lua", "Weights.lua", "UI.lua", "OptionsTab.lua",
  "UpgradesTab.lua", "LogTab.lua", "Diagnostics.lua", "Probe.lua",
  "ChestAdvisor/Verdict.lua" }) do
  loaded(TOUCH .. name, "MightiePack", pkg)
end
loaded(ADVISOR, "MightiePack", pkg)
for _, name in ipairs({ "Integration.lua", "Core.lua" }) do
  loaded(TOUCH .. name, "MightiePack", pkg)
end
check(type(Verdict) == "table", "the vendored Verdict loaded")
check(type(ChestAdvisor) == "table", "the vendored ChestAdvisor loaded")
ChestAdvisorDB = { role = {} }
local okEnable, enableErr = pcall(ChestAdvisor.Enable)
check(okEnable, "ChestAdvisor.Enable runs: " .. tostring(enableErr))
check(type(ChestAdvisor.tooltipLines) == "function",
  "the renderer is published as ChestAdvisor.tooltipLines (the surface this spec drives)")

-- ---- Fixtures: the owner's pair --------------------------------------------
local PROC = "Chance on hit: Sear the target with a vortex of blazing wind,"
  .. " dealing 39 to 59 Holystorm damage. Deals 3 times as much damage to Wolves and Worgen."
local ENCHANT = "Enchanted: Weapon Damage +5"
local HEALING = "Equip: Increases healing done by up to 34 and damage done by up to 11"
  .. " for all magical spells and effects"

local ZWEI = { "Polished ZweiHander of Healing", "Two-Hand  Sword",
  "20 - 37 Damage  Speed 3.00", "(9.5 damage per second)", HEALING }
local WOLF_DISCLOSED = { "Wolfsbane", "Two-Hand  Sword", "69 - 105 Damage  Speed 3.40",
  "+9 Stamina", "+10 Intellect", PROC, ENCHANT }
local WOLF_BARE = { "Wolfsbane", "Two-Hand  Sword", "69 - 105 Damage  Speed 3.40",
  "+9 Stamina", "+10 Intellect" }

local SPEC = { class = "PALADIN", role = "spell", clientRole = "HEALER", level = 40 }
local ZWEI_LINK = "|cff9d9d9d|Hitem:31141|h[Polished ZweiHander of Healing]|h|r"
local WOLF_LINK = "|cff9d9d9d|Hitem:267369|h[Wolfsbane]|h|r"

-- The engine's clause as an INDEPENDENT oracle: the trailing parenthetical that
-- opens with the engine's own lead, with no nested paren inside it.
local function engineClause(reason)
  if type(reason) ~= "string" then return "" end
  local start
  local pos = 1
  while true do
    local i = reason:find(" (judged, with ", pos, true)
    if i == nil then break end
    start = i
    pos = i + 1
  end
  if start == nil then return "" end
  local clause = reason:sub(start)
  if clause:sub(-1) ~= ")" then return "" end
  if clause:sub(1, -2):find(")", 1, true) then return "" end
  return clause
end

local EQUIPPED = " (judged, with an unpriced on-hit effect and an unpriced enchant on the equipped weapon)"
local HOVERED = " (judged, with an unpriced on-hit effect and an unpriced enchant on the hovered item)"

-- The row the fold's weapon emitter writes: the ENGINE's verdict and reason
-- (which carry the clause), plus the detail the order layer produced — the words
-- the owner saw on screen ("Healing Power", "Trade-off: +Healing vs −Intellect").
local function weaponRow(candLines, wornLines, candLink, wornLink)
  local v, r = Verdict.compareWeapon(candLines, wornLines, true, SPEC, true, nil)
  local cand = Verdict.statTable(candLines, "candidate", nil)
  local eq = Verdict.statTable(wornLines, "worn", nil)
  local detail = select(3, Verdict.orderVerdict(cand, eq, SPEC, nil, nil)) or {}
  return {
    id = tonumber(candLink:match("item:(%d+)")),
    lines = candLines,
    chestWornLines = wornLines,
    wornLink = wornLink,
    class = SPEC.class,
    role = SPEC.role,
    verdict = v,
    reason = r,
    decidedBy = detail.decidedBy,
    orderOutcome = detail.orderOutcome,
    tradeOffText = detail.tradeOffText,
    caveat = detail.caveat,
    profile = detail.profile,
  }
end

-- Render a row through the SHIPPED renderer and return its headline as plain
-- text (colour escapes stripped — exactly what the player reads).
--
-- (fk/tooltip-shift-details) The clause is the FULL disclosure, shown while Shift
-- is held; `render` holds Shift. `renderDefault` is the same line with Shift up,
-- where the clause folds to one short marker (asserted after the clause checks).
local function renderWith(row, shift)
  local saved = IsShiftKeyDown
  IsShiftKeyDown = function() return shift end
  local lines = ChestAdvisor.tooltipLines(row)
  IsShiftKeyDown = saved
  if type(lines) ~= "table" or lines[1] == nil then return "" end
  return (tostring(lines[1].text):gsub("^|c%x%x%x%x%x%x%x%x", ""):gsub("|r$", ""))
end
local function render(row) return renderWith(row, true) end
local function renderDefault(row) return renderWith(row, false) end

local rowFwd = weaponRow(ZWEI, WOLF_DISCLOSED, ZWEI_LINK, WOLF_LINK)
local rowRev = weaponRow(WOLF_DISCLOSED, ZWEI, WOLF_LINK, ZWEI_LINK)

-- 1. THE ENGINE IS RIGHT IN BOTH DIRECTIONS. This is what makes the display the
--    defect, and it is asserted on the shipped bytes rather than assumed.
check(rowFwd.verdict == "TRADE_OFF",
  "the ZweiHander-hovered direction is a trade-off (got " .. tostring(rowFwd.verdict) .. ")")
check(engineClause(rowFwd.reason) == EQUIPPED,
  "the engine discloses the EQUIPPED weapon's enchant and proc (got: " .. tostring(rowFwd.reason) .. ")")
check(engineClause(rowRev.reason) == HOVERED,
  "the engine discloses the HOVERED item's enchant and proc (got: " .. tostring(rowRev.reason) .. ")")
check(rowFwd.decidedBy == "Healing Power",
  "the fold's order layer names the decider (got " .. tostring(rowFwd.decidedBy) .. ")")

-- 2. THE OWNER'S MISSING-CLAUSE CASE: the WEIGHTED renderer (row.decidedBy set,
--    so TOOLTIP_UI.weighted builds the sentence from the row's fields).
local weightedFwd = render(rowFwd)
print("weighted (ZweiHander hovered): " .. weightedFwd)
check(weightedFwd:find("decided by Healing Power", 1, true) ~= nil,
  "the weighted line names the decider (got: " .. weightedFwd .. ")")
check(weightedFwd:find("Trade-off: +Healing", 1, true) ~= nil,
  "the weighted line keeps the trade-off word (got: " .. weightedFwd .. ")")
check(weightedFwd:sub(-#EQUIPPED) == EQUIPPED,
  "the WEIGHTED line carries the engine's clause, verbatim (got: " .. weightedFwd .. ")")
check(select(2, weightedFwd:gsub("%(judged", "")) == 1,
  "exactly one disclosure parenthetical, not two (got: " .. weightedFwd .. ")")

-- 3. THE OTHER DIRECTION, same renderer, naming its own side.
local weightedRev = render(rowRev)
print("weighted (Wolfsbane hovered):  " .. weightedRev)
check(weightedRev:sub(-#HOVERED) == HOVERED,
  "the other direction carries ITS OWN clause (got: " .. weightedRev .. ")")

-- 4. ONE HELPER, TWO RENDERERS: the same engine reason, rendered by the ORDINAL
--    path (no decidedBy ⇒ the weighted renderer declines and the line is built
--    from row.reason). The clause must be byte-identical, and the two sentences
--    must differ (or the equality above would be vacuous).
local function ordinal(row)
  local copy = {}
  for k, v in pairs(row) do copy[k] = v end
  copy.decidedBy, copy.tradeOffText, copy.caveat, copy.profile = nil, nil, nil, nil
  copy.orderOutcome = nil
  return copy
end

local lineOrdinalFwd = render(ordinal(rowFwd))
local lineOrdinalRev = render(ordinal(rowRev))
print("ordinal  (ZweiHander hovered): " .. lineOrdinalFwd)
print("ordinal  (Wolfsbane hovered):  " .. lineOrdinalRev)
check(lineOrdinalFwd:sub(-#EQUIPPED) == EQUIPPED,
  "the ORDINAL line carries the same clause (got: " .. lineOrdinalFwd .. ")")
check(lineOrdinalRev:sub(-#HOVERED) == HOVERED,
  "the ordinal line of the other direction carries its own (got: " .. lineOrdinalRev .. ")")
check(weightedFwd:sub(-#EQUIPPED) == lineOrdinalFwd:sub(-#EQUIPPED),
  "the two renderers disagree on the clause bytes:\n    weighted: " .. weightedFwd
    .. "\n    ordinal : " .. lineOrdinalFwd)
check(lineOrdinalFwd ~= weightedFwd,
  "the ordinal path produced the weighted sentence — the equality above is then vacuous")

-- 5. CONTROL: a pair with no enchant and no proc keeps the pre-card bytes (the
--    clause is "" so nothing is appended on either path).
local rowBare = weaponRow(ZWEI, WOLF_BARE, ZWEI_LINK, WOLF_LINK)
check(engineClause(rowBare.reason) == "",
  "the bare pair carries no clause (got: " .. tostring(rowBare.reason) .. ")")
local weightedBare = render(rowBare)
print("weighted (no enchant/proc):    " .. weightedBare)
check(weightedBare:find("(judged", 1, true) == nil,
  "a pair with no disclosure gains none (got: " .. weightedBare .. ")")
check(weightedBare == "Trade-off: +Healing vs −Intellect — decided by Healing Power vs Wolfsbane [Holy]",
  "the no-clause weighted line is the pre-card bytes (got: " .. weightedBare .. ")")
local ordinalBare = render(ordinal(rowBare))
print("ordinal  (no enchant/proc):    " .. ordinalBare)
check(ordinalBare == "Trade-off — decided by Healing Power [Holy] — Trade-off: +Healing vs −Intellect",
  "the no-clause ordinal line is the pre-card bytes (got: " .. ordinalBare .. ")")

-- 6. REFUSAL: nothing on a refused row may carry a disclosure (the t_fc11dd1c
--    rule). The engine's own refusals never carry one (pinned in StatForge's
--    battery, whose comparator this is); here the DISPLAY must not add one.
local refusalRow = ordinal(rowFwd)
refusalRow.verdict = "UNKNOWN"
refusalRow.reason = "cannot equip — requires level 60"
local lineRefusal = render(refusalRow)
check(lineRefusal:find("(judged", 1, true) == nil,
  "no refusal line carries a disclosure (got: " .. lineRefusal .. ")")

-- (fk/tooltip-shift-details) Shift UP: the same lines carry one short marker in
-- place of the clause, and the rest of the headline is unchanged.
do
  local HINT = " (Shift: details)"
  for _, r in ipairs({ rowFwd, rowRev }) do
    local full, short = render(r), renderDefault(r)
    check(short:sub(-#"|cff9d9d9d(Shift: details)") == "|cff9d9d9d(Shift: details)",
      "Shift up: the marker is grey and ends the line (got: " .. short .. ")")
    short = short:gsub("|c%x%x%x%x%x%x%x%x", "")
    local sentence, clause = ChestAdvisor._disclosureClause(full)
    check(clause ~= "" and short == sentence .. HINT,
      "Shift up folds the clause to the short marker, nothing else changes (got: " .. short .. ")")
    check(short:find("judged, with", 1, true) == nil, "Shift up: no clause text on the line")
  end
end

print("")
if failed > 0 then
  io.stderr:write(failed .. " check(s) failed\n")
  os.exit(1)
end
print("all checks passed — the weighted and ordinal lines carry the engine's own clause")

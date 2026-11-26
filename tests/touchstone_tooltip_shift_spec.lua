-- SHORT BY DEFAULT, FULL ON SHIFT (fk/tooltip-shift-details).
--
-- The owner tested ca8804f and asked (Nov 26): the verdict's long disclosure —
-- the healer model's paragraph, the engine's "(judged, with …)" clause, the
-- "throughput not judged" decline — should not sit under every hover. By
-- default the tooltip shows the headline plus a small grey "(Shift: details)"
-- marker (his follow-up: "the less info for the tooltip the better"); the full
-- current text shows only while Shift is held, and the line swaps when Shift goes
-- down or up without moving the mouse.
--
-- This spec drives the REAL vendored renderer and the REAL pre-call:
--   1. ARBITRATED rows: Shift up gives the headline alone plus the grey marker
--      (no paragraph, no "low confidence", no survival line); Shift down gives
--      the paragraph whole plus the Details line.
--   2. ORDINAL / WEIGHTED / UPGRADE rows: the disclosure tail folds to
--      " (Shift: details)"; Shift down restores it byte for byte.
--   3. THE DETAIL SETTING is unchanged: Full always shows the numbers, Compact
--      shows them on Shift, Upgrades only drops the two non-answers.
--   4. NOTHING TO DISCLOSE: such a row is byte-identical in both Shift states.
--   5. THE SWAP: MODIFIER_STATE_CHANGED is registered; Shift on one of our item
--      tooltips asks the client to rebuild it (RefreshDataNextUpdate); any other
--      key, a hidden tooltip or someone else's tooltip does nothing; and a cached
--      rebuild through the pre-call swaps the line instead of keeping the old one.
--   6. MUTATIONS: the unmutated file is run through the leg command first and
--      must report 0 failed; each mutant must report "N check(s), K failed" with
--      K > 0. Skipped inside a leg (TS_ADVISOR_SRC set).
--
-- Run from the repo root:  lua5.1 tests/touchstone_tooltip_shift_spec.lua

local here = (arg and arg[0] or "tests/touchstone_tooltip_shift_spec.lua")
  :match("^(.*)[/\\][^/\\]*$") or "."
local root = here:gsub("[/\\]tests$", "")
if root == "tests" then root = "." end
local TOUCH = root .. "/MightiePack/Modules/Touchstone/"

local failed, checks = 0, 0
local function check(cond, msg)
  checks = checks + 1
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

-- TS_ADVISOR_SRC points the same assertions at another copy of the vendored
-- ChestAdvisor.lua (the mutation legs below use it).
local ADVISOR_SRC = os.getenv("TS_ADVISOR_SRC")

local function fileExists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

if not fileExists(TOUCH .. "ChestAdvisor/ChestAdvisor.lua") then
  io.stderr:write("FAIL: the vendored Touchstone is absent — nothing to check\n")
  os.exit(1)
end

-- ---- WoW stub (the same shapes tests/touchstone_fold_spec.lua proves) ------
local chat, frames = {}, {}
-- The captured item-tooltip hook functions (the client's own registration
-- surface). `postCall` is the FALLBACK surface, `preCall` the shipping one —
-- a client registers exactly one of them, never both.
local postCall, preCall

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
  -- A method the stub does not model must not explode a load: it is a no-op.
  setmetatable(f, { __index = function() return function() end end })
  return f
end

local function resetEnv(hasPreCall)
  chat, frames = {}, {}
  SlashCmdList = setmetatable({}, {
    __newindex = function(t, k, v) rawset(t, k, v) end,
  })
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
  -- The tooltip hook surfaces this client exposes. Captured here so the spec
  -- can call them exactly the way the client does. `hasPreCall` models a client
  -- whose TooltipDataProcessor has the item PRE-call (the shipping path since
  -- StatForge PR #95); without it the module must fall back to the post-call.
  postCall, preCall = nil, nil
  local processor = {
    AddTooltipPostCall = function(kind, fn)
      check(kind == 0, "post-call registered for TooltipDataType.Item")
      postCall = fn
    end,
  }
  if hasPreCall then
    processor.AddTooltipPreCall = function(kind, fn)
      check(kind == 0, "pre-call registered for TooltipDataType.Item")
      preCall = fn
    end
  end
  TooltipDataProcessor = processor
  Enum = { TooltipDataType = { Item = 0 } }
  -- The pre-call gives every line a colour OBJECT (AddLineDataText calls
  -- leftColor:GetRGB()); the client supplies CreateColor, so model it.
  CreateColor = function(r, g, b)
    return { GetRGB = function() return r, g, b end }
  end
end

postCall = nil

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

-- Load the vendored module against a fresh client. Called once for the
-- post-call (fallback) client and again for the pre-call (shipping) one: the
-- module installs its hook once per load, so a second scenario needs a second
-- load, exactly like a /reload.
local pkg
local function loadModule(hasPreCall)
  resetEnv(hasPreCall)
  pkg = { Print = function(_, msg) chat[#chat + 1] = tostring(msg) end }
  loaded(TOUCH .. "Bootstrap.lua", "MightiePack", pkg)
  for _, name in ipairs(VENDORED) do
    local path = TOUCH .. name
    if name == "ChestAdvisor/ChestAdvisor.lua" and ADVISOR_SRC then path = ADVISOR_SRC end
    loaded(path, "MightiePack", pkg)
  end
  check(type(ChestAdvisor) == "table", "the vendored ChestAdvisor loaded")
  ChestAdvisorDB = { role = {} }
  local okEnable, enableErr = pcall(ChestAdvisor.Enable, ChestAdvisor)
  check(okEnable, "ChestAdvisor.Enable runs: " .. tostring(enableErr))
  return okEnable
end


loadModule(true)
check(type(preCall) == "function", "the item-tooltip pre-call was registered")
local UI = ChestAdvisor._tooltipUI
check(type(UI) == "table" and type(UI.foldTail) == "function" and type(UI.shiftHint) == "function"
  and type(UI.onModifierChanged) == "function", "the Shift helpers are published on the tooltip UI table")

local function onMod(...)
  if type(UI) == "table" and type(UI.onModifierChanged) == "function" then return UI.onModifierChanged(...) end
  return nil
end
local shift = false
IsShiftKeyDown = function() return shift end
local function plain(t) return (tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function render(row, mode, held)
  ChestAdvisorDB.tooltip = { detail = mode }
  shift = held
  local out = {}
  for _, l in ipairs(ChestAdvisor.tooltipLines(row) or {}) do out[#out + 1] = plain(l.text) end
  shift = false
  return out
end
local function renderRaw(row, mode, held)
  ChestAdvisorDB.tooltip = { detail = mode }
  shift = held
  local out = {}
  for _, l in ipairs(ChestAdvisor.tooltipLines(row) or {}) do out[#out + 1] = l.text end
  shift = false
  return out
end
local MODES = { "full", "compact", "upgrades" }
local HINT = " (Shift: details)"

-- ── 1. arbitrated rows ──────────────────────────────────────────────────────
local CLAUSE = " (judged, with Spell Damage, Weapon DPS, an on-hit effect and an enchant not counted"
  .. " for healing; you'd lose Wolfsbane's on-hit effect and its Weapon Damage +5 enchant)"
local RAID_REASON = "Raid healing: an upgrade — the extra healing per cast outruns the smaller pool, and you"
  .. " would run dry after about 20 casts either way. (confidence low: crit multiplier unmeasured)" .. CLAUSE
local ARB = { state = "UPGRADE", context = "raid", driving = "healing", margin = 0.045, band = 0.009,
  confidence = "low", lowWhy = { "crit multiplier unmeasured" } }
local arbRow = { id = 1, verdict = "UPGRADE", reason = RAID_REASON, arbitration = ARB }
for _, mode in ipairs(MODES) do
  local up, down = render(arbRow, mode, false), render(arbRow, mode, true)
  if mode == "full" then
    print("1. Shift up:   " .. table.concat(up, " / "))
    print("1. Shift down: " .. table.concat(down, " / "))
  end
  check(type(down[1]) == "string" and down[1]:find("^Upgrade — raid") ~= nil
    and down[1]:find("decided by the healing per cast", 1, true) ~= nil,
    "1/" .. mode .. ": the headline (got " .. tostring(down[1]) .. ")")
  check(#up == 1 and up[1] == down[1] .. HINT,
    "1/" .. mode .. ": Shift up: the headline and the marker, one line (got " .. table.concat(up, " / ") .. ")")
  check(table.concat(up, " "):find("confidence", 1, true) == nil,
    "1/" .. mode .. ": Shift up: no confidence wording (it is in the Shift view)")
  check(down[2] == RAID_REASON, "1/" .. mode .. ": Shift down: the paragraph, whole and unchanged")
  check(type(down[3]) == "string" and down[3]:sub(1, 9) == "Details: ",
    "1/" .. mode .. ": Shift down: the model's Details line (got " .. tostring(down[3]) .. ")")
  check(table.concat(down, " "):find("Shift: details", 1, true) == nil,
    "1/" .. mode .. ": Shift down: no marker")
end
do
  -- The marker is grey and closes the line.
  local raw = renderRaw(arbRow, "full", false)[1] or ""
  check(raw:sub(-#("|cff9d9d9d(Shift: details)|r")) == "|cff9d9d9d(Shift: details)|r",
    "1: the marker is grey and ends the line (got " .. raw .. ")")
  -- High confidence: the same single line.
  local sure = { state = "UPGRADE", context = "dungeon", driving = "healing", confidence = "high" }
  local r1 = render({ id = 1, verdict = "UPGRADE", reason = "Dungeon healing: an upgrade — more per cast.",
    arbitration = sure }, "full", false)
  check(#r1 == 1 and r1[1]:sub(-#HINT) == HINT,
    "1: high confidence: the headline and the marker (got " .. table.concat(r1, " / ") .. ")")
  -- A sidegrade's survival line is detail too.
  local side = { state = "SIDEGRADE", context = "raid", driving = "healing", confidence = "high",
    survival = { dHP = 40, dMitigation = 0 }, survivalVerdict = "candidate" }
  local srow = { id = 1, verdict = "TRADE_OFF", reason = "Raid healing: a sidegrade — inside the band.", arbitration = side }
  local su, sd = render(srow, "full", false), render(srow, "full", true)
  check(#su == 1 and su[1]:sub(-#HINT) == HINT, "1: Shift up: a sidegrade is one line (got " .. table.concat(su, " / ") .. ")")
  local hasSurv = false
  for _, l in ipairs(sd) do if l:find("^Survival: ") then hasSurv = true end end
  check(hasSurv, "1: Shift down: the survival line is back (got " .. table.concat(sd, " / ") .. ")")
end

-- ── 2. ordinal / weighted / upgrade rows ────────────────────────────────────
local PRE_CLAUSE = " (judged, with an unpriced on-hit effect and an unpriced enchant on the equipped weapon)"
local HEAD = "Trade-off: +Healing vs −Intellect — decided by Healing Power [Holy (chosen)]"
local orderRow = { id = 2, verdict = "TRADE_OFF",
  reason = "decided by Healing Power [Holy (chosen)] — Trade-off: +Healing vs −Intellect."
    .. " Set Role to Spell (/up role spell) to judge this as a healer" .. PRE_CLAUSE,
  decidedBy = "Healing Power", profile = "Holy (chosen)", tradeOffText = "Trade-off: +Healing vs −Intellect" }
local declinedRow = {}
for k, x in pairs(orderRow) do declinedRow[k] = x end
declinedRow.arbitration = { declined = true, cause = "secret_totals" }
for _, mode in ipairs(MODES) do
  check(render(orderRow, mode, false)[1] == HEAD .. HINT,
    "2/" .. mode .. ": an order-only Trade-off folds its clause (got " .. tostring(render(orderRow, mode, false)[1]) .. ")")
  check(render(orderRow, mode, true)[1] == HEAD .. PRE_CLAUSE,
    "2/" .. mode .. ": Shift down: the clause, byte for byte")
  check(render(declinedRow, mode, false)[1] == HEAD .. HINT,
    "2/" .. mode .. ": a declined Trade-off folds the clause AND the decline into one marker (got "
      .. tostring(render(declinedRow, mode, false)[1]) .. ")")
  check(render(declinedRow, mode, true)[1] == HEAD .. PRE_CLAUSE
    .. " (throughput not judged: the client did not give your mana numbers)",
    "2/" .. mode .. ": Shift down: the clause and the decline (got " .. tostring(render(declinedRow, mode, true)[1]) .. ")")
end
do
  -- The ordinal UPGRADE branch (no worn lines, so the clause rides the headline).
  local up = { id = 3, verdict = "UPGRADE",
    reason = "upgrade: better on Healing (judged, with an unpriced on-hit effect on the equipped weapon)" }
  check(render(up, "full", false)[1] == "Upgrade — better on Healing" .. HINT,
    "2: the ordinal Upgrade folds its clause (got " .. tostring(render(up, "full", false)[1]) .. ")")
  check(render(up, "full", true)[1]
    == "Upgrade — better on Healing (judged, with an unpriced on-hit effect on the equipped weapon)",
    "2: Shift down: the ordinal Upgrade's clause, whole")
  -- The ordinal TRADE-OFF branch (no decidedBy: the comparator's own sentence).
  local to = { id = 4, verdict = "TRADE_OFF",
    reason = "trade-off: better on Intellect, worse on Stamina (judged, with an unpriced enchant on the hovered item)" }
  check(render(to, "full", false)[1] == "Trade-off — better on Intellect, worse on Stamina" .. HINT,
    "2: the ordinal Trade-off folds its clause (got " .. tostring(render(to, "full", false)[1]) .. ")")
  check(render(to, "full", true)[1]
    == "Trade-off — better on Intellect, worse on Stamina (judged, with an unpriced enchant on the hovered item)",
    "2: Shift down: the ordinal Trade-off's clause, whole (got " .. tostring(render(to, "full", true)[1]) .. ")")
end

-- ── 3. the detail setting is unchanged (the read-arithmetic numbers line) ───
do
  local NUM = "-1 Int"
  local row = { id = 5, verdict = "TRADE_OFF", reason = orderRow.reason, decidedBy = "Healing Power",
    profile = "Holy (chosen)", tradeOffText = "Trade-off: +Healing vs −Intellect",
    lines = { "Polished ZweiHander of Healing", "+9 Intellect", "Equip: Increases healing done by up to 34." },
    chestWornLines = { "Wolfsbane", "+10 Intellect" }, class = "PALADIN", role = "spell" }
  local function hasNum(t) for _, l in ipairs(t) do if l:find(NUM, 1, true) then return true end end return false end
  check(hasNum(render(row, "full", false)) and hasNum(render(row, "full", true)),
    "3: Full always shows the numbers, Shift up or down")
  check(not hasNum(render(row, "compact", false)) and hasNum(render(row, "compact", true)),
    "3: Compact shows the numbers only while Shift is held")
  check(hasNum(render(row, "upgrades", false)), "3: Upgrades only keeps the numbers like Full")
  check(#render({ id = 6, verdict = "NOT_UPGRADE", reason = "worse" .. PRE_CLAUSE }, "upgrades", false) == 0,
    "3: Upgrades only still drops a not-upgrade line")
end

-- ── 4. nothing to disclose: byte-identical in both states ───────────────────
do
  for _, row in ipairs({
    { id = 7, verdict = "UPGRADE", weighted = 12 },
    { id = 8, verdict = "UPGRADE", reason = "upgrade: Strength +4" },
    { id = 9, verdict = "UNKNOWN", reason = "cannot classify: Enchanted: Weapon Damage +5" },
  }) do
    local a, b = render(row, "full", false), render(row, "full", true)
    check(table.concat(a, "\n") == table.concat(b, "\n") and table.concat(a, "\n"):find("Shift: details", 1, true) == nil,
      "4: a row with no disclosure is the same with Shift up or down (" .. tostring(row.reason or row.weighted) .. ")")
  end
end

-- ── 5. the swap ─────────────────────────────────────────────────────────────
local modFrame
for _, f in ipairs(frames) do
  if type(f.events) == "table" and f.events.MODIFIER_STATE_CHANGED then modFrame = f end
end
check(modFrame ~= nil and type(modFrame.scripts.OnEvent) == "function",
  "5: a frame listens for MODIFIER_STATE_CHANGED")
local LINK = "|cff1eff00|Hitem:31141:0:0:0:0:0:0:0|h[Polished ZweiHander of Healing]|h|r"
ChestAdvisor.__verdicts = { [LINK] = arbRow }
ChestAdvisorDB.tooltip = { detail = "full" }
local data = { hyperlink = LINK, lines = { { leftText = "Polished ZweiHander of Healing" }, { leftText = "+9 Intellect" } } }
shift = false
pcall(preCall, { }, data)
check(#data.lines == 3 and plain(data.lines[3].leftText):sub(-#HINT) == HINT
  and plain(data.lines[3].leftText):find("^Upgrade — raid") ~= nil,
  "5: the pre-call lands the short form with Shift up (got " .. tostring(data.lines[3] and plain(data.lines[3].leftText)) .. ")")
-- A cached rebuild (the same data table) with Shift held swaps to the full form.
shift = true
pcall(preCall, { }, data)
check(#data.lines == 5 and plain(data.lines[4].leftText) == RAID_REASON
  and plain(data.lines[5].leftText):sub(1, 9) == "Details: ",
  "5: a cached rebuild with Shift held swaps to the full form, one set of lines (got " .. #data.lines .. " lines)")
shift = false
pcall(preCall, { }, data)
check(#data.lines == 3 and data.lines[1].leftText == "Polished ZweiHander of Healing"
  and data.lines[2].leftText == "+9 Intellect",
  "5: and back on release; the item's own lines untouched (got " .. #data.lines .. " lines)")
-- The event: a fake GameTooltip that is showing that data.
local refreshes = 0
local tipShown = true
local fakeTip = {
  IsShown = function() return tipShown end,
  GetPrimaryTooltipData = function() return data end,
  RefreshDataNextUpdate = function() refreshes = refreshes + 1 end,
}
GameTooltip = fakeTip
if modFrame then modFrame.scripts.OnEvent(modFrame, "MODIFIER_STATE_CHANGED", "LSHIFT", 1) end
check(refreshes == 1, "5: Shift on our tooltip asks the client to rebuild it (refreshes " .. refreshes .. ")")
check(onMod("RSHIFT", fakeTip) == true and refreshes == 2, "5: right Shift too")
check(onMod("LCTRL", fakeTip) == false and refreshes == 2, "5: another key does nothing")
tipShown = false
check(onMod("LSHIFT", fakeTip) == false and refreshes == 2, "5: a hidden tooltip does nothing")
tipShown = true
local foreign = { IsShown = function() return true end,
  GetPrimaryTooltipData = function() return { lines = { { leftText = "Someone else's item" } } } end,
  RefreshDataNextUpdate = function() refreshes = refreshes + 1 end }
check(onMod("LSHIFT", foreign) == false and refreshes == 2,
  "5: a tooltip without our line is left alone")
check(onMod("LSHIFT", { IsShown = function() return true end,
  GetPrimaryTooltipData = function() return data end }) == false,
  "5: a client without RefreshDataNextUpdate: nothing, and no error")
GameTooltip = nil

-- ── 6. mutations ────────────────────────────────────────────────────────────
local function readAll(path)
  local f = io.open(path, "rb"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
local function runLeg(path)
  local lua = (arg and arg[-1]) or "lua5.1"
  local cmd = ("cd %q && TS_ADVISOR_SRC=%q %s tests/touchstone_tooltip_shift_spec.lua 2>&1"):format(root, path, lua)
  local p = io.popen(cmd)
  local out = p and p:read("*a") or ""
  if p then p:close() end
  local n, k
  for a, b in out:gmatch("(%d+) check%(s%), (%d+) failed") do n, k = tonumber(a), tonumber(b) end
  return n, k, out
end
if ADVISOR_SRC == nil then
  local shipped = readAll(TOUCH .. "ChestAdvisor/ChestAdvisor.lua") or ""
  local function legFile(text)
    local path = os.tmpname()
    local f = io.open(path, "w"); f:write(text); f:close()
    return path
  end
  local base = legFile(shipped)
  local bn, bk, bout = runLeg(base)
  os.remove(base)
  print(("6. baseline (unmutated, same command): %s check(s), %s failed"):format(tostring(bn), tostring(bk)))
  check(bn ~= nil and bn > 0 and bk == 0,
    "6: the unmutated file must run through the leg command and report 0 failed. Output:\n" .. bout:sub(-400))
  local MUTANTS = {
    { "the fold ignores Shift", "\tif TOOLTIP_UI.shiftHeld() then return tail end\n", "" },
    { "the fold never folds", "\treturn TOOLTIP_UI.shiftHint()\nend", "\treturn tail\nend" },
    { "the marker not grey", "return \" \" .. TOOLTIP_GREY .. \"(\" .. TOOLTIP_UI.SHIFT_HINT .. \")\"",
      "return \" (\" .. TOOLTIP_UI.SHIFT_HINT .. \")\"" },
    { "the arbitrated row ignores Shift", "\tif not TOOLTIP_UI.shiftHeld() then\n\t\tout[1].text", "\tif false then\n\t\tout[1].text" },
    { "the arbitrated row always short", "\tif not TOOLTIP_UI.shiftHeld() then\n\t\tout[1].text", "\tif true then\n\t\tout[1].text" },
    { "the arbitrated marker dropped", "out[1].text = out[1].text .. TOOLTIP_UI.shiftHint() .. ", "out[1].text = out[1].text .. " },
    { "the upgrade branch not folded", "head = sentence .. TOOLTIP_UI.foldTail(clause)", "head = sentence .. clause" },
    { "the trade-off branch not folded", ".. \" — \" .. reason .. TOOLTIP_UI.foldTail(clause .. decline),",
      ".. \" — \" .. reason .. clause .. decline," },
    { "the weighted branch not folded", "\t\t\t\t.. TOOLTIP_UI.foldTail(clause .. decline),\n\t\t\tcolour = colour,",
      "\t\t\t\t.. clause .. decline,\n\t\t\tcolour = colour," },
    { "Full hides the numbers without Shift", "local showDetail = (setting ~= \"compact\") or TOOLTIP_UI.shiftHeld()",
      "local showDetail = TOOLTIP_UI.shiftHeld()" },
    { "any key swaps", "\tif key ~= \"LSHIFT\" and key ~= \"RSHIFT\" then return false end\n", "" },
    { "any tooltip swaps", "\tif not ours then return false end\n", "" },
    { "the cached rebuild keeps the old lines",
      "\twhile #lines > 0 and type(lines[#lines]) == \"table\" and lines[#lines][TOOLTIP_LINE_MARK] do\n\t\tlines[#lines] = nil\n\tend\n", "" },
    { "the event not registered", "\t\tpcall(f.RegisterEvent, f, \"MODIFIER_STATE_CHANGED\")\n", "" },
    { "the swap never installed", "\t\t\tinstallShiftSwap()\n", "" },
  }
  for _, m in ipairs(MUTANTS) do
    local s, e = shipped:find(m[2], 1, true)
    check(s ~= nil, "6: mutation anchor present: " .. m[1])
    check(s == nil or shipped:find(m[2], e + 1, true) == nil, "6: mutation anchor is unique: " .. m[1])
    if s ~= nil and bk == 0 then
      local path = legFile(shipped:sub(1, s - 1) .. m[3] .. shipped:sub(e + 1))
      local n, k, out = runLeg(path)
      os.remove(path)
      print(("6. mutant %-40s %s"):format(m[1],
        (n == nil) and "NO RESULT LINE" or (k > 0 and ("killed (" .. k .. "/" .. n .. ")") or "SURVIVED")))
      check(n ~= nil, "6: the mutant leg printed its result line: " .. m[1] .. ". Output:\n" .. out:sub(-400))
      check(n ~= nil and k > 0, "6: the spec fails on the mutant: " .. m[1])
    end
  end
end

print(("%d check(s), %d failed"):format(checks, failed))
if failed > 0 then os.exit(1) end

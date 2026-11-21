-- touchstone_repin_bb03d13_spec.lua — the pack's half of the StatForge bb03d13
-- re-pin (#128 A9+A11, #129 Part C PR 2, #130 Part C PR 3).
--
-- Run from the repo root:  lua5.1 tests/touchstone_repin_bb03d13_spec.lua
--
-- --verify-shipped proves the vendored bytes are the pin plus the named patches.
-- It cannot say what the re-cut patches DO with the new upstream code, so this
-- file asks, against the shipped bytes:
--   R  the one-time ready line is for characters that never ENABLED Touchstone
--      (the pack ships the module off by default, so upstream's table-identity
--      test would call almost every character a veteran); it runs from
--      SF.Enable(), Core.lua still creates no frame, and it is add-only;
--   G  the + / ^ glyphs default ON, an explicit off is kept, /up reset turns
--      them on and still clears the chosen Gear-for spec;
--   L  One Ledger: the tooltip line, the advisor's fallback and the pack's
--      ledger all draw #22C55E (upgrade) and #F59E0B (trade-off);
--   S  the third ledger column is SLOT, one font string, shown only over drawn
--      rows, and an empty list or an Upgrades-only list with no upgrade does
--      not crash;
--   V  GearAPI is v2 and the arrow clock is the throttled one (pristine files).

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local TOUCH = root .. "/MightiePack/Modules/Touchstone/"
local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local core = read(TOUCH .. "Core.lua") or ""
local advisor = read(TOUCH .. "ChestAdvisor/ChestAdvisor.lua") or ""

-- ── R. the ready line ───────────────────────────────────────────────────────
check(not core:find('CreateFrame("Frame")', 1, true), "R: Core.lua creates no event frame")
local enableBody = core:match("function SF%.Enable%(%)(.-)\nend")
check(enableBody ~= nil and enableBody:find("SF.MaybeAnnounceReady()", 1, true) ~= nil,
  "R: SF.Enable() calls SF.MaybeAnnounceReady()")

local startAt = core:find("local function advisorDBLooksUsed", 1, true)
local fnAt = core:find("function SF.MaybeAnnounceReady()", 1, true)
local fnEnd = fnAt and core:find("\nend\n", fnAt, true)
check(startAt ~= nil and fnAt ~= nil and fnEnd ~= nil, "R: the ready-line code is in the shipped Core.lua")

local printed = {}
local SF = { Print = function(msg) printed[#printed + 1] = msg end }
local function ready(db)
  _G.ChestAdvisorDB = db
  SF.MaybeAnnounceReady()
end
if startAt and fnEnd then
  local chunk, err = loadstring("local SF = ...\n" .. core:sub(startAt, fnEnd + 4))
  check(chunk ~= nil, "R: the ready-line code compiles: " .. tostring(err))
  if chunk then chunk(SF) end
end

if type(SF.MaybeAnnounceReady) == "function" then
  -- A brand-new character: exactly ChestAdvisor.lua's first-run default.
  local fresh = { role = {} }
  ready(fresh)
  check(#printed == 1 and printed[1]:find("ready", 1, true) ~= nil, "R: a new character gets the line")
  check(fresh.readyAnnounced == true, "R: the line is recorded")
  ready(fresh)
  check(#printed == 1, "R: the line prints once, also across a second enable / relog")

  -- A character that logged in with the module OFF has only the default table
  -- saved: it never enabled Touchstone, so it still gets the line once.
  printed = {}
  local savedButNeverEnabled = { role = {} }
  ready(savedButNeverEnabled)
  check(#printed == 1, "R: a saved-but-never-enabled character still gets the line")

  -- Veterans: anything an enabled Touchstone writes.
  local veterans = {
    { name = "toast settings", db = { role = {}, toast = { lifetime = 5 } } },
    { name = "a log", db = { role = {}, log = { { verdict = "UPGRADE" } } } },
    { name = "a recorded role", db = { role = { PALADIN = "melee" } } },
    { name = "a chosen spec", db = { role = {}, gearFor = "PALADIN_RET" } },
    { name = "glyphs explicitly off", db = { role = {}, markers = { glyphs = false } } },
  }
  for _, v in ipairs(veterans) do
    printed = {}
    local before = {}
    for k, val in pairs(v.db) do before[k] = val end
    ready(v.db)
    check(#printed == 0, "R: a veteran with " .. v.name .. " stays quiet")
    check(v.db.readyAnnounced == true, "R: a veteran with " .. v.name .. " is marked announced")
    for k, val in pairs(before) do
      check(v.db[k] == val, "R: add-only, " .. v.name .. " keeps " .. tostring(k))
    end
  end

  printed = {}
  local announced = { role = {}, readyAnnounced = true }
  ready(announced)
  check(#printed == 0, "R: an announced character stays quiet")
  local ok = pcall(ready, nil)
  check(ok and #printed == 0, "R: no ChestAdvisorDB is not an error and prints nothing")
end

-- ── G. glyphs ───────────────────────────────────────────────────────────────
local gStart = advisor:find("function ChestAdvisor._glyphsOn()", 1, true)
local gEnd = gStart and advisor:find("\nend\n", gStart, true)
check(gStart ~= nil and gEnd ~= nil, "G: ChestAdvisor._glyphsOn is shipped")
if gStart and gEnd then
  local CA = {}
  local chunk = loadstring("local ChestAdvisor = ...\n" .. advisor:sub(gStart, gEnd + 4))
  if chunk then chunk(CA) end
  if type(CA._glyphsOn) == "function" then
    _G.ChestAdvisorDB = { role = {} }
    check(CA._glyphsOn() == true, "G: a character that never set glyphs gets them ON")
    _G.ChestAdvisorDB = { markers = { glyphs = false } }
    check(CA._glyphsOn() == false, "G: an explicit off is kept")
    _G.ChestAdvisorDB = { markers = { glyphs = true } }
    check(CA._glyphsOn() == true, "G: an explicit on is on")
  end
end
local resetBody = advisor:match("local function cmdReset%(%)(.-)\nend")
check(resetBody ~= nil and resetBody:find('cmdGlyphs("glyphs on")', 1, true) ~= nil,
  "G: /up reset turns the glyphs on")
check(resetBody ~= nil and resetBody:find("ChestAdvisor.setGearFor(nil)", 1, true) ~= nil,
  "G: /up reset still clears the chosen Gear-for spec (pack)")
check(resetBody ~= nil and resetBody:find("marker glyphs on; chosen Gear-for spec cleared", 1, true) ~= nil,
  "G: /up reset says both")
check(advisor:find("colorblind-safe marker glyphs (persisted; default on)", 1, true) ~= nil,
  "G: the help line says default on")

-- ── L. One Ledger ───────────────────────────────────────────────────────────
check(advisor:find('local TOOLTIP_PREFIX = ""', 1, true) ~= nil,
  "L: the tooltip line still carries no addon name (pack fold)")
check(advisor:find('local TOOLTIP_GREEN  = ChestAdvisor._verdictCode("upgrade")', 1, true) ~= nil,
  "L: the tooltip upgrade colour is the palette's")
check(advisor:find('local TOOLTIP_AMBER  = ChestAdvisor._verdictCode("tradeoff")', 1, true) ~= nil,
  "L: the tooltip trade-off colour is the palette's")
check(advisor:find('TOOLTIP_GREEN  = "|cff00ff00"', 1, true) == nil, "L: the old pure green is gone")

local function hex(c)
  return string.format("%02x%02x%02x", math.floor(c[1] * 255 + 0.5),
    math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
local fbUp = advisor:match("upgrade  = { ([%d%.]+), ([%d%.]+), ([%d%.]+) }, %-%- #22C55E")
check(fbUp ~= nil, "L: the advisor's host-less fallback upgrade colour is #22C55E")

local T = {}
_G.MightiePack = T
local themeChunk = loadfile(root .. "/MightiePack/Theme.lua")
check(themeChunk ~= nil, "L: Theme.lua loads")
if themeChunk then
  local ok, e = pcall(themeChunk, "MightiePack", T)
  check(ok, "L: Theme.lua runs: " .. tostring(e))
end
local theme = T.Theme or T
local lp = theme.ledgerPalette
if type(lp) ~= "table" then
  for _, v in pairs(T) do
    if type(v) == "table" and type(v.ledgerPalette) == "table" then lp = v.ledgerPalette end
  end
end
check(type(lp) == "table", "L: the theme publishes the ledger palette")
if type(lp) == "table" then
  check(lp.upgrade and hex(lp.upgrade) == "22c55e", "L: the ledger's upgrade is #22C55E")
  check(lp.tradeoff and hex(lp.tradeoff) == "f59e0b", "L: the ledger's trade-off is #F59E0B")
end

local constants = read(TOUCH .. "Constants.lua") or ""
check(constants:find("success     = { 0.133, 0.773, 0.369 }, -- #22C55E", 1, true) ~= nil
  and constants:find("warning     = { 0.961, 0.620, 0.043 }, -- #F59E0B", 1, true) ~= nil,
  "L: Constants.lua (pristine) defines the One Ledger pair")
check(constants:find("function SF.VerdictColour(kind)", 1, true) ~= nil, "L: SF.VerdictColour is shipped")

-- ── S. the SLOT header ──────────────────────────────────────────────────────
local upgrades = read(TOUCH .. "UpgradesTab.lua") or ""
local _, slotLabels = upgrades:gsub('"SLOT"', "")
check(slotLabels == 1, "S: exactly one SLOT label is created (got " .. slotLabels .. ")")
check(upgrades:find('columnLabel("CHANGE"', 1, true) == nil, "S: the CHANGE label is gone")
check(upgrades:find("host.colSlot = host.colChange", 1, true) ~= nil,
  "S: colSlot is the column label itself, not a second font string")

local C = dofile(root .. "/tests/support/wowclient.lua")
C.Install({ width = 1920, height = 1080 })
local pkg = { PackVersion = function() return "0.5.0" end }
_G.MightiePack = pkg
StatForgeDB = { ui = { scale = 1 }, firstUse = false }
tinsert = table.insert
tremove = table.remove
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local VERDICTS = {}
ChestAdvisor = {
  getVerdicts = function()
    local out = {}
    for _, row in ipairs(VERDICTS) do
      out[row.link] = { verdict = row.verdict, id = row.id, slotWord = row.slotWord, reason = row.reason }
    end
    return out
  end,
  getLog = function() return {} end,
}
local function loadTouch(path)
  local chunk, err = loadfile(TOUCH .. path)
  check(chunk ~= nil, "S: loadfile " .. path .. ": " .. tostring(err))
  if not chunk then return end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "S: load " .. path .. ": " .. tostring(e))
end
loadTouch("Constants.lua")
loadTouch("UI.lua")
loadTouch("UpgradesTab.lua")
loadTouch("LogTab.lua")
local TS = _G.StatForge
check(type(TS) == "table" and type(TS.UpgradesTabState) == "function", "S: the Upgrades tab loads")

if type(TS) == "table" and type(TS.ShowMain) == "function" then
  -- 1. An EMPTY list: no crash, no header.
  local ok, e = pcall(TS.ShowMain, "upgrades")
  check(ok, "S: an empty list renders without error: " .. tostring(e))
  local st = TS.UpgradesTabState()
  check(st.total == 0, "S: precondition, the list is empty")
  check(st.slotHeader == "SLOT", "S: the header is built and reads SLOT (got " .. tostring(st.slotHeader) .. ")")
  check(st.slotHeaderShown == false, "S: no header over an empty list")

  -- 2. Rows drawn: the header shows.
  VERDICTS = {
    { link = "[Mystic Robe]", id = 1, verdict = "UPGRADE", slotWord = "Chest", reason = "more spell power" },
    { link = "[Ragged Gloves]", id = 2, verdict = "NOT_UPGRADE", slotWord = "Hands", reason = "less armour" },
  }
  ok, e = pcall(TS.RefreshActiveTab)
  check(ok, "S: a populated list renders: " .. tostring(e))
  st = TS.UpgradesTabState()
  check(st.total == 2 and st.shown > 0, "S: precondition, rows are drawn (" .. tostring(st.shown) .. ")")
  check(st.slotHeaderShown == true, "S: the SLOT header shows over drawn rows")

  -- 3. Upgrades only, with no upgrade in the list: nothing drawn, no header.
  VERDICTS = {
    { link = "[Ragged Gloves]", id = 2, verdict = "NOT_UPGRADE", slotWord = "Hands", reason = "less armour" },
  }
  ok, e = pcall(TS.UpgradesTabSetShowAll, false)
  check(ok, "S: Upgrades-only renders: " .. tostring(e))
  pcall(TS.RefreshActiveTab)
  st = TS.UpgradesTabState()
  check(st.total == 1 and st.admitted == 0, "S: precondition, nothing is admitted ("
    .. tostring(st.total) .. "/" .. tostring(st.admitted) .. ")")
  check(st.slotHeaderShown == false, "S: no header when no row is drawn")
end

-- ── V. pristine upstream pieces ────────────────────────────────────────────
local gear = read(TOUCH .. "GearAPI.lua") or ""
check(gear:find("VERSION = 2", 1, true) ~= nil or gear:find("VERSION  = 2", 1, true) ~= nil,
  "V: GearAPI is version 2")
local marks = read(TOUCH .. "ChestAdvisor/Marks.lua") or ""
check(marks:find("SetAnimated", 1, true) ~= nil, "V: Marks.SetAnimated ships (C6)")
check(marks:find("1 / 30", 1, true) ~= nil or marks:find("1/30", 1, true) ~= nil,
  "V: the arrow clock is throttled to 30 placements a second (B5)")

if failed > 0 then
  io.stderr:write("touchstone_repin_bb03d13_spec: " .. failed .. " failure(s)\n")
  os.exit(1)
end
print("touchstone_repin_bb03d13_spec: ok")

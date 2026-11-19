-- touchstone_shipped_seam_spec.lua — card t_58762500.
--
-- THE SEAM, MEASURED ON THE BYTES THE OWNER PLAYS.
--
-- The re-pin to StatForge ff64bc5 (PR #123) brought `Arbitration.ENABLED = true`
-- by itself: Arbitration.lua is one of the eight COPY-lane files, so a plain
-- re-pin hands the addon a flag that is ON. The CALL lives in Verdict.lua, which
-- this pack replaces wholesale with its weighted layer, so the call arrives only
-- if the re-cut patch carries it. Upstream-green is not shipped-green: StatForge's
-- own battery proves its copy calls the seam, and proves nothing at all about the
-- vendored one. Until this card the shipped file had `Verdict.arbitrate`'s
-- DEFINITION and no caller — a patch that applies, a digest that matches, a suite
-- that passes, and a model nothing asks.
--
-- So this spec drives the SHIPPED tree, through the pack's own loader, and asks
-- three questions in order:
--
--   A. SOURCE. `Verdict.arbitrate(` occurs exactly twice in the shipped
--      Verdict.lua — the definition and the call — and `A.ENABLED = true` is in
--      the shipped Arbitration.lua. A definition is not a call.
--   B. THE ROW. A real `ChestAdvisor.scan()` over a healer pair the weighted
--      engine calls TRADE_OFF comes out ARBITRATED: `row.arbitration.state` is a
--      string, the token is the arbitration's, and `row.reason` is the model's
--      own sentence (not the weighted layer's).
--   C. THE FLAG. With `Arbitration.ENABLED` flipped to false in the same VM and
--      the judgement memo dropped, the same scan is NOT arbitrated — so B is
--      reading the flag, not a coincidence.
--
-- The item tooltip and the window's ledger row are then read off the SAME row
-- (leg D): one pair, one word, on both surfaces.
--
-- WHAT IS STUBBED, and why that is not cheating: the harness has no game client.
-- The stubs are the client's own reads (UnitClass/UnitLevel, the worn-link read,
-- the bag containers, the structured tooltip reader) plus `_totals`, which in the
-- client is a Spellcraft/paper-doll read the harness cannot invent. Everything
-- between those inputs and the row — the bag walk, the spec build, the weighted
-- comparator, the SEAM, the row builder, both renderers — is the vendored code.
--
-- Run from the repo root:  lua5.1 tests/touchstone_shipped_seam_spec.lua

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local function readFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

local TOUCH = root .. "/MightiePack/Modules/Touchstone/"

-- ── A. SOURCE: the call exists, in call position ────────────────────────────
do
  local verdictSrc = readFile(TOUCH .. "ChestAdvisor/Verdict.lua")
  check(verdictSrc ~= nil, "the shipped Verdict.lua is present")
  if verdictSrc then
    local defLine, callLine, count = nil, nil, 0
    local lines = {}
    for line in (verdictSrc:gsub("\r\n", "\n") .. "\n"):gmatch("(.-)\n") do
      lines[#lines + 1] = line
    end
    for n, line in ipairs(lines) do
      if line:find("Verdict.arbitrate(", 1, true) then
        count = count + 1
        if line:sub(1, 27) == "function Verdict.arbitrate(" then
          defLine = n
        else
          callLine = n
        end
      end
    end
    print(("A. shipped Verdict.lua: %d occurrence(s) — definition :%s, call :%s")
      :format(count, tostring(defLine), tostring(callLine)))
    check(count == 2, "the shipped Verdict.lua calls the seam exactly once and defines it once (got "
      .. count .. " occurrence(s))")
    check(defLine ~= nil, "the definition is in the shipped file")
    check(callLine ~= nil, "THE CALL IS IN THE SHIPPED FILE (a definition is not a call) — "
      .. "re-cut ChestAdvisor__Verdict.lua.patch: its replacement region dropped it once")
  end
  local arbSrc = readFile(TOUCH .. "ChestAdvisor/Arbitration.lua")
  check(arbSrc ~= nil, "the shipped Arbitration.lua is present")
  if arbSrc then
    local enabled = arbSrc:gsub("\r\n", "\n"):match("\nA%.ENABLED = (%a+)")
    print("A. shipped Arbitration.lua: A.ENABLED = " .. tostring(enabled))
    check(enabled == "true", "the flag is on in the shipped bytes (got " .. tostring(enabled) .. ")")
  end
end

-- ── the client the harness does not have ────────────────────────────────────
local C = dofile(root .. "/tests/support/wowclient.lua")
C.Install({ width = 1920, height = 1080 })

tinsert = table.insert
tremove = table.remove
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
MightiePackDB = { modules = {} }
StatForgeDB = { ui = { scale = 1 }, firstUse = false }
-- The product surface, not a back door: `/up gearfor holy` and `/up context raid`
-- are what a Holy paladin in a raid sets, and buildSpec reads them.
ChestAdvisorDB = { gearFor = "holy", context = "raid" }

local pkg = { PackVersion = function() return "0.5.0" end }
_G.MightiePack = pkg

local WORN_LINK = "|cnIQ3:|Hitem:9100::::::::70:1::::::|h[Worn Chest of the Parish]|h|r"
local CAND_LINK = "|cnIQ3:|Hitem:9001::::::::70:1::::::|h[Parity Chest of the Trade]|h|r"

-- The pair: more Intellect on the worn side, more Healing on the hovered one —
-- a wash the weighted engine calls TRADE_OFF and the model answers inside the
-- band. (Measured through the shipped engine; see leg B's print.)
local LINES = {
  [CAND_LINK] = { "Parity Chest of the Trade", "Chest", "16 Armor", "+6 Intellect", "+20 Healing" },
  [WORN_LINK] = { "Worn Chest of the Parish", "Chest", "14 Armor", "+9 Intellect", "+8 Healing" },
}

function GetInventoryItemLink(unit, slot)
  if unit == "player" and slot == 5 then return WORN_LINK end
  return nil
end
function UnitClass(unit) if unit == "player" then return "Paladin", "PALADIN", 2 end end
function UnitLevel(unit) if unit == "player" then return 70 end end
function UnitName(unit) if unit == "player" then return "Testpally" end end
C_Item = {
  GetItemInfoInstant = function(id)
    return id, "Item " .. tostring(id), nil, "INVTYPE_CHEST", 0, 4, 1
  end,
  GetItemInfo = function(link)
    local lines = LINES[link]
    return lines and lines[1] or nil, link, 3, 70, 1, "Armor", "Mail",
      1, "INVTYPE_CHEST", nil, 500
  end,
}
C_PlayerInfo = { CanUseItem = function() return true end }
C_Container = {
  GetContainerNumSlots = function(bag) if bag == 0 then return 1 end return 0 end,
  GetContainerItemInfo = function(bag, slot)
    if bag == 0 and slot == 1 then return { hyperlink = CAND_LINK, itemID = 9001 } end
    return nil
  end,
}
C_TooltipInfo = {
  GetHyperlink = function(link)
    local lines = LINES[link]
    if lines == nil then return nil end
    return { lines = lines }
  end,
}

-- ── the pack's own loader ──────────────────────────────────────────────────
local function loadFile(name)
  local chunk, err = loadfile(TOUCH .. name)
  check(chunk ~= nil, "loadfile " .. name .. ": " .. tostring(err))
  if not chunk then return end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. name .. ": " .. tostring(e))
end

for _, name in ipairs({
  "Bootstrap.lua", "Constants.lua", "Weights.lua", "UI.lua",
  "UpgradesTab.lua", "LogTab.lua",
  "ChestAdvisor/Marks.lua", "ChestAdvisor/Verdict.lua", "ChestAdvisor/StatOrders.lua",
  "ChestAdvisor/Arbitration.lua", "ChestAdvisor/ChestAdvisor.lua",
}) do
  loadFile(name)
end

local SF   = _G.StatForge
local CA   = _G.ChestAdvisor
local V    = _G.Verdict
local ARB  = _G.Arbitration
check(type(SF) == "table", "the module loads")
check(type(CA) == "table", "the advisor loads")
check(type(V) == "table", "the engine loads")
check(type(ARB) == "table", "the arbitration module loads")
if type(CA) ~= "table" or type(V) ~= "table" or type(ARB) ~= "table" then
  io.stderr:write("cannot continue without the vendored tree\n")
  os.exit(1)
end

local okEnable, enableErr = pcall(CA.Enable)
check(okEnable, "ChestAdvisor.Enable: " .. tostring(enableErr))

-- The saved per-character store, set the way a previous session left it: the
-- module's own first-run default REPLACES the global at load time (ChestAdvisor
-- :102), so these two keys are written after the files load, exactly as a save
-- restore would land on the global.
ChestAdvisorDB.gearFor = "holy"
ChestAdvisorDB.context = "raid"
check(CA.gearForKey() == "holy", "the chosen spec resolves off the store (got "
  .. tostring(CA.gearForKey()) .. ")")

-- The character's own measurements: the healer reading the parity battery uses
-- (§5a measured, MID). In the client this is a Spellcraft/paper-doll read; the
-- harness supplies the numbers and nothing else.
local SPELL = { id = 19939, name = "Holy Light", rank = 5, cost = 190, castTimeMs = 2500 }
local MID = {
  pool = 2060, regenCasting = 5.5885, crit = 6.38, bonusHealing = 36, level = 34,
  regenMeasured = true, spell = SPELL,
  stats = { Intellect = 101, Spirit = 80 },
}
check(type(CA._totals) == "function", "the advisor publishes _totals")
CA._totals = function() return MID end

-- ── B. THE ROW: a real scan, through the vendored tree ─────────────────────
local function scanFor(link)
  CA._invalidateJudgements("seam spec: fresh scan")
  local rows = CA.scan()
  if type(rows) ~= "table" then return nil, nil end
  return rows[link], rows
end

local row, allRows = scanFor(CAND_LINK)
local rowCount = 0
for _ in pairs(allRows or {}) do rowCount = rowCount + 1 end
print(("B. scan: %d row(s), one bag item judged against the worn chest"):format(rowCount))
check(row ~= nil, "the scan judged the hovered chest (found no row for " .. CAND_LINK .. ")")

if type(row) == "table" then
  print(("B. row.verdict              %q"):format(tostring(row.verdict)))
  print(("B. row.reason               %q"):format(tostring(row.reason)))
  print(("B. row.arbitration          %s"):format(
    type(row.arbitration) == "table"
      and ("{ state=" .. tostring(row.arbitration.state)
        .. ", context=" .. tostring(row.arbitration.context)
        .. ", margin=" .. tostring(row.arbitration.margin)
        .. ", band=" .. tostring(row.arbitration.band)
        .. ", driving=" .. tostring(row.arbitration.driving) .. " }")
      or tostring(row.arbitration)))

  check(row.verdict == "TRADE_OFF",
    "the weighted engine calls this pair a trade-off (got " .. tostring(row.verdict)
      .. ") — the seam only offers TRADE_OFF, like upstream's")
  check(type(row.arbitration) == "table",
    "THE ROW IS ARBITRATED: row.arbitration is a table (got "
      .. type(row.arbitration) .. ")")
  if type(row.arbitration) == "table" then
    check(type(row.arbitration.state) == "string",
      "row.arbitration.state is a string (got " .. type(row.arbitration.state) .. ")")
    check(row.arbitration.state == "SIDEGRADE",
      "the token matches the model's answer (got " .. tostring(row.arbitration.state) .. ")")
    check(row.arbitration.context == "raid",
      "the model priced the pair for the CONTEXT the player set (got "
        .. tostring(row.arbitration.context) .. ")")
    check(type(row.arbitration.reason) == "string"
      and row.arbitration.reason:find("under the band", 1, true) ~= nil,
      "the arbitration carries its own sentence (got "
        .. tostring(row.arbitration.reason) .. ")")
    check(row.reason == row.arbitration.reason,
      "row.reason IS the model's sentence, not the weighted layer's — got "
        .. tostring(row.reason) .. " vs " .. tostring(row.arbitration.reason))
  end
end

-- ── C. THE FLAG: off means off, on the same scan ───────────────────────────
do
  local wasEnabled = ARB.ENABLED
  ARB.ENABLED = false
  local offRow = scanFor(CAND_LINK)
  print(("C. with A.ENABLED = false: row.arbitration = %s"):format(
    offRow and tostring(offRow.arbitration) or "no row"))
  check(offRow ~= nil, "the scan still judges the pair with the flag off")
  if offRow then
    check(offRow.arbitration == nil,
      "the flag is what silences the seam (row.arbitration was "
        .. tostring(offRow.arbitration) .. " with the flag off)")
    check(offRow.verdict == "TRADE_OFF",
      "the flag off restores the pre-seam answer exactly (got "
        .. tostring(offRow.verdict) .. ")")
  end
  ARB.ENABLED = wasEnabled
end

-- ── D. ONE PAIR, ONE WORD: the tooltip and the window ──────────────────────
local function stripEscapes(text)
  text = tostring(text or "")
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return text
end

local function tooltipHeadline(r)
  local lines = CA.tooltipLines(r)
  if type(lines) ~= "table" or type(lines[1]) ~= "table" then return nil, nil end
  local text = stripEscapes(lines[1].text)
  local word = text:match("^([^—]+)") or text
  return text, (word:gsub("%s+$", ""))
end

local function windowWord(link, r)
  local seen, stack = {}, { UIParent }
  while #stack > 0 do
    local frame = table.remove(stack)
    if type(frame) == "table" and not seen[frame] then
      seen[frame] = true
      if (frame.__link == link or frame.__link == r) and type(frame.verdictWord) == "table" then
        local text = frame.verdictWord:GetText()
        if text ~= nil then return stripEscapes(text) end
      end
      for _, child in ipairs(frame:GetChildren() or {}) do stack[#stack + 1] = child end
    end
  end
  return nil
end

do
  -- Scan again with the flag restored: leg C left the store holding the
  -- UNARBITRATED rows (that is what the flag-off leg proves), and the surfaces
  -- must be read from a scan the seam answered.
  row = scanFor(CAND_LINK)
  check(type(row) == "table" and type(row.arbitration) == "table",
    "the flag restored: the same scan is arbitrated again")

  check(type(SF.ShowMain) == "function", "SF.ShowMain exists")
  local okShow, showErr = pcall(SF.ShowMain, "upgrades")
  check(okShow, 'SF.ShowMain("upgrades"): ' .. tostring(showErr))

  local tipText, tipWord = tooltipHeadline(row)
  local winWord = windowWord(CAND_LINK, row)
  print(("D. tooltip headline          %q"):format(tostring(tipText)))
  print(("D. window ledger row word    %q"):format(tostring(winWord)))

  check(tipWord ~= nil, "the tooltip produced a headline for the arbitrated row")
  check(winWord ~= nil, "the window drew a ledger row for the arbitrated pair")
  check(tipWord == winWord,
    "the tooltip (" .. tostring(tipWord) .. ") and the window row ("
      .. tostring(winWord) .. ") name the same pair the same way")
  check(tipWord == CA.tooltipUI.words.SIDEGRADE,
    "both say the model's word for inside the band (expected "
      .. string.format("%q", tostring(CA.tooltipUI.words.SIDEGRADE))
      .. ", got " .. tostring(tipWord) .. ")")
  -- NON-VACUITY: the pre-arbitration word really is a different string, so the
  -- two legs above are not comparing a word to itself.
  local tokenWord = CA.tooltipUI.word(row and row.verdict or "TRADE_OFF")
  print(("D. pre-arbitration token word %q"):format(tostring(tokenWord)))
  check(tokenWord ~= tipWord,
    "the token map's word (" .. tostring(tokenWord) .. ") differs from the "
      .. "arbitrated word — the surfaces are not printing the token")
end

if failed == 0 then
  print("touchstone_shipped_seam_spec: ok")
else
  print(("touchstone_shipped_seam_spec: %d failure(s)"):format(failed))
  os.exit(1)
end

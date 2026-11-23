-- touchstone_decline_clause_spec.lua — card t_18eb91e6 (A8, carried into the client)
--
-- THE REFUSAL CLAUSE, MEASURED ON THE BYTES THE OWNER PLAYS.
--
-- StatForge 1992240 ships A8: a pair the model was ASKED and turned away is no
-- longer a silence. The ladder answers `nil, why, cause`, Verdict.arbitrate hands
-- that up marked `declined = true`, and ChestAdvisor's clause map turns the stable
-- CAUSE KEY into player words. The pack vendors all three files, but two of them
-- are PATCH-lane: ChestAdvisor__Verdict.lua.patch REPLACES the very region upstream
-- edited, and ChestAdvisor__ChestAdvisor.lua.patch replaces that file whole. A
-- re-pin that moves the pin but drops the map is the shape that produced
-- 0.3.10/0.3.11 — --verify-shipped stays green because it compares the vendored
-- copy to the pin and never asks whether the overlay took. This spec asks.
--
-- WHAT IS ASSERTED, in order:
--
--   A. SHIPPED BYTES. `DECLINE_CLAUSE` and the two distinct sentences exist, the
--      renderer `TOOLTIP_UI.declineClause` exists, and it is CALLED from the
--      shipped renderer twice — the weighted headline and the ordinal tail — with
--      line numbers printed, because "the map exists" and "the map is asked" are
--      different facts. The Verdict seam's declined passthrough is asserted on the
--      same bytes.
--   B. THE LADDER'S KEY. Through the shipped Arbitration, a non-table totals
--      answers `no_totals` — the recoverable state — while a secret totals answers
--      `secret_totals`, the permanent one. Upstream's own A8 battery asserts the
--      same two keys.
--   C. THE TWO CLAUSES, SIDE BY SIDE, through the shipped renderer: the
--      "not yet" sentence for `no_totals` and "the client did not give your mana
--      numbers" for the permanent causes. They must DIFFER — that distinction is
--      the point of the card, not a wording preference.
--   D. END TO END, through the vendored tree: a real scan whose totals the client
--      refuses comes out DECLINED (`row.arbitration.declined`), and the tooltip
--      line for that row carries the permanent clause. `no_totals` cannot reach a
--      row this way — Verdict.arbitrate refuses a non-table totals before asking
--      the judge, and upstream's own battery says so — so C is where that state is
--      measured, on the renderer that would speak it the moment it arrives.
--   E. THE DEFAULT IS SILENCE. A judged pair carries the model's sentence and NO
--      clause; a clear upgrade carries none; a row the model was never asked
--      carries none; a cause the map does not name falls back to the plain clause
--      rather than blanking the line.
--
-- Run from the repo root:  lua5.1 tests/touchstone_decline_clause_spec.lua

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed, checks = 0, 0
local function check(cond, msg)
  checks = checks + 1
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

local function stripEscapes(text)
  text = tostring(text or "")
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- A. SHIPPED BYTES: the map, the renderer, and the CALL
-- ═══════════════════════════════════════════════════════════════════════════════
local advisorSrc = readFile(TOUCH .. "ChestAdvisor/ChestAdvisor.lua")
local verdictSrc = readFile(TOUCH .. "ChestAdvisor/Verdict.lua")
local arbSrc = readFile(TOUCH .. "ChestAdvisor/Arbitration.lua")
check(advisorSrc ~= nil, "the shipped ChestAdvisor.lua is present")
check(verdictSrc ~= nil, "the shipped Verdict.lua is present")
check(arbSrc ~= nil, "the shipped Arbitration.lua is present")

local function numbered(text, needle)
  local hits = {}
  local n = 0
  for line in (text:gsub("\r\n", "\n") .. "\n"):gmatch("(.-)\n") do
    n = n + 1
    if line:find(needle, 1, true) then hits[#hits + 1] = { n = n, line = line } end
  end
  return hits
end

do
  local mapLine = numbered(advisorSrc, "local DECLINE_CLAUSE = {")
  local yetLine = numbered(advisorSrc, "local DECLINE_MANA_YET = ")
  local manaLine = numbered(advisorSrc, "local DECLINE_MANA = ")
  local renderer = numbered(advisorSrc, "function TOOLTIP_UI.declineClause(row)")
  local calls = {}
  for _, hit in ipairs(numbered(advisorSrc, "TOOLTIP_UI.declineClause(row)")) do
    if not hit.line:find("function TOOLTIP_UI.declineClause", 1, true) then
      calls[#calls + 1] = hit
    end
  end

  print(("A. declined-clause map :%s  MANA :%s  MANA_YET :%s  renderer :%s")
    :format(tostring(mapLine[1] and mapLine[1].n), tostring(manaLine[1] and manaLine[1].n),
      tostring(yetLine[1] and yetLine[1].n), tostring(renderer[1] and renderer[1].n)))
  for _, hit in ipairs(calls) do
    print(("A. call :%d  %s"):format(hit.n, hit.line:gsub("^%s+", "")))
  end

  check(#mapLine == 1, "THE CLAUSE MAP IS IN THE SHIPPED FILE (DECLINE_CLAUSE)")
  check(#renderer == 1, "THE RENDERER IS IN THE SHIPPED FILE (TOOLTIP_UI.declineClause)")
  -- Two call sites are required: the weighted headline (where a declined trade-off
  -- lands in THIS pack) and upstream's ordinal tail. A definition is not a call.
  check(#calls == 2,
    "the renderer is CALLED from the shipped verdict lines twice (found "
      .. #calls .. " call site(s), expected 2)")

  check(#manaLine == 1 and manaLine[1].line:find(
    "the client did not give your mana numbers", 1, true) ~= nil,
    "the permanent cause's sentence is the shipped wording")
  check(#yetLine == 1 and yetLine[1].line:find(
    "no mana reading yet", 1, true) ~= nil,
    "the recoverable cause's sentence is the shipped wording")

  local noTotalsEntry = numbered(advisorSrc, "no_totals = DECLINE_MANA_YET,")
  local secretEntry = numbered(advisorSrc, "secret_totals = DECLINE_MANA,")
  check(#noTotalsEntry == 1 and #secretEntry == 1,
    "the map keys the two states to DIFFERENT clauses (no_totals -> MANA_YET, secret_totals -> MANA)")

  -- The Verdict seam: the refusal is handed up, not dropped.
  local pass = numbered(verdictSrc, 'if type(aDetail) == "table" and aDetail.declined == true then')
  local arbitrate = numbered(verdictSrc, "Verdict.arbitrate(")
  print(("A. seam passthrough :%s   Verdict.arbitrate( occurrences: %d")
    :format(tostring(pass[1] and pass[1].n), #arbitrate))
  check(#pass == 1, "THE SEAM PASSES THE DECLINE THROUGH in the shipped Verdict.lua")
  -- Definition + armour seam + healer weapon seam (fk/healer-weapon-verdict).
  check(#arbitrate == 3, "the seam is defined once and called twice (armour, healer weapon) in the shipped bytes")
  check(verdictSrc:find("return nil, why, { declined = true, why = why, cause = cause }", 1, true) ~= nil,
    "the shipped arbitrate returns the refusal with its cause key")
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- B/C/D/E. The vendored tree, loaded and asked
-- ═══════════════════════════════════════════════════════════════════════════════
local C = dofile(root .. "/tests/support/wowclient.lua")
C.Install({ width = 1920, height = 1080 })

tinsert = table.insert
tremove = table.remove
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
MightiePackDB = { modules = {} }
StatForgeDB = { ui = { scale = 1 }, firstUse = false }
ChestAdvisorDB = { gearFor = "holy", context = "raid" }

local pkg = { PackVersion = function() return "0.5.0" end }
_G.MightiePack = pkg

local WORN_LINK = "|cnIQ3:|Hitem:9100::::::::70:1::::::|h[Worn Chest of the Parish]|h|r"
local CAND_LINK = "|cnIQ3:|Hitem:9001::::::::70:1::::::|h[Parity Chest of the Trade]|h|r"
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

local CA = _G.ChestAdvisor
local V = _G.Verdict
local ARB = _G.Arbitration
check(type(CA) == "table" and type(V) == "table" and type(ARB) == "table",
  "the vendored tree loads (ChestAdvisor + Verdict + Arbitration)")
if type(CA) ~= "table" then
  io.stderr:write("cannot continue without the vendored tree\n")
  os.exit(1)
end
local okEnable, enableErr = pcall(CA.Enable)
check(okEnable, "ChestAdvisor.Enable: " .. tostring(enableErr))
ChestAdvisorDB.gearFor = "holy"
ChestAdvisorDB.context = "raid"

local SPELL = { id = 19939, name = "Holy Light", rank = 5, cost = 190, castTimeMs = 2500 }
local MID = {
  pool = 2060, regenCasting = 5.5885, crit = 6.38, bonusHealing = 36, level = 34,
  regenMeasured = true, spell = SPELL,
  stats = { Intellect = 101, Spirit = 80 },
}
local SPEC = { role = "spell", class = "PALADIN", context = "raid" }
local TRADE_C = { Intellect = 6, Healing = 38 }
local TRADE_E = { Intellect = 12, Healing = 15 }

-- ── B. the ladder's keys, through the shipped module ────────────────────────
do
  local whyN, causeN = ARB.why(TRADE_C, TRADE_E, SPEC, nil)
  local whyS, causeS = ARB.why(TRADE_C, TRADE_E, SPEC, { secret = true })
  print(("B. judge(nil totals)   cause %s   %q"):format(tostring(causeN), tostring(whyN)))
  print(("B. judge(secret)       cause %s   %q"):format(tostring(causeS), tostring(whyS)))
  check(causeN == "no_totals", "the recoverable state's key is no_totals (got "
    .. tostring(causeN) .. ")")
  check(causeS == "secret_totals", "the permanent state's key is secret_totals (got "
    .. tostring(causeS) .. ")")
  check(whyN ~= whyS, "the ladder's two sentences are distinct")
end

-- ── C. the two clauses, side by side, through the shipped renderer ──────────
local function clauseFor(cause, why)
  local row = {
    verdict = "TRADE_OFF",
    arbitration = { declined = true, cause = cause, why = why or "" },
  }
  return CA._tooltipUI.declineClause(row)
end

do
  local yet = clauseFor("no_totals")
  local permanent = clauseFor("secret_totals")
  print("C. no_totals  -> " .. yet)
  print("C. secret     -> " .. permanent)
  check(yet:find("no mana reading yet", 1, true) ~= nil
    and yet:find("it is read out of combat", 1, true) ~= nil,
    "no_totals renders the RECOVERABLE clause (got " .. yet .. ")")
  check(permanent:find("the client did not give your mana numbers", 1, true) ~= nil,
    "a permanent cause renders the REFUSAL clause (got " .. permanent .. ")")
  check(yet ~= permanent,
    "THE TWO STATES READ DIFFERENTLY — that distinction is the card's purpose")
  check(clauseFor("incomplete_totals") == permanent
    and clauseFor("pool_not_positive") == permanent,
    "the whole permanent family shares the refusal clause")
  -- A key the map does not name still says something: the plain clause, never "".
  local unknown = clauseFor("a_key_from_a_later_pin")
  print("C. unknown key -> " .. unknown)
  check(unknown ~= "" and unknown:find("the numbers do not price this trade", 1, true) ~= nil,
    "an unknown cause falls back to the plain clause rather than blanking the line")
end

-- ── D. end to end: a real declined pair, through the vendored tree ──────────
local function scanFor(link)
  CA._invalidateJudgements("decline clause spec: fresh scan")
  local rows = CA.scan()
  if type(rows) ~= "table" then return nil end
  return rows[link]
end

do
  CA._totals = function() return { secret = true } end
  local row = scanFor(CAND_LINK)
  check(type(row) == "table", "the scan judged the pair with a refused totals read")
  if type(row) == "table" then
    local arb = row.arbitration
    print(("D. row.verdict %q   arbitration = %s"):format(tostring(row.verdict),
      type(arb) == "table"
        and ("{ declined=" .. tostring(arb.declined) .. ", cause=" .. tostring(arb.cause) .. " }")
        or tostring(arb)))
    check(row.verdict == "TRADE_OFF",
      "the declined pair keeps its own TRADE_OFF answer (got " .. tostring(row.verdict) .. ")")
    check(type(arb) == "table" and arb.declined == true,
      "THE ROW IS DECLINED: row.arbitration.declined is true (got "
        .. (type(arb) == "table" and tostring(arb.declined) or type(arb)) .. ")")
    check(type(arb) == "table" and arb.cause == "secret_totals",
      "the row carries the ladder's cause key (got "
        .. (type(arb) == "table" and tostring(arb.cause) or type(arb)) .. ")")

    local lines = CA.tooltipLines(row)
    local head = type(lines) == "table" and lines[1] and stripEscapes(lines[1].text) or nil
    print("D. tooltip line  " .. tostring(head))
    check(head ~= nil and head:find("the client did not give your mana numbers", 1, true) ~= nil,
      "THE TOOLTIP LINE CARRIES THE CLAUSE (got " .. tostring(head) .. ")")
    check(head ~= nil and head:find("throughput not judged", 1, true) ~= nil,
      "the clause names what did not get judged, in player words")
  end
end

-- ── E. the default is silence ──────────────────────────────────────────────
do
  -- The same pair with the reading in hand: the model judges it, so the row is
  -- arbitrated and must carry the model's sentence with NO clause.
  CA._totals = function() local t = {} for k, v in pairs(MID) do t[k] = v end return t end
  local row = scanFor(CAND_LINK)
  check(type(row) == "table", "the scan judged the pair with the reading in hand")
  if type(row) == "table" then
    local arb = row.arbitration
    check(type(arb) == "table" and arb.state == "SIDEGRADE",
      "the same pair is ARBITRATED once the numbers are in hand (got "
        .. (type(arb) == "table" and tostring(arb.state) or type(arb)) .. ")")
    print(("E. arbitrated row.reason  %q"):format(tostring(row.reason)))
    local lines = CA.tooltipLines(row)
    local head = type(lines) == "table" and lines[1] and stripEscapes(lines[1].text) or nil
    print("E. arbitrated tooltip line  " .. tostring(head))
    -- The arbitrated surface words a sidegrade with the model's WORD and its own
    -- short sentence (pack rendering, unchanged by this card); what matters here is
    -- that the row is answered rather than declined, and that no clause follows.
    check(head ~= nil and head:find("Sidegrade", 1, true) == 1,
      "the arbitrated row leads with the model's word (got " .. tostring(head) .. ")")
    check(head ~= nil and head:find("throughput not judged", 1, true) == nil,
      "and NO decline clause (got " .. tostring(head) .. ")")
  end
end

-- Never asked: an ordinary weighted row renders byte-identically to before.
do
  local row = { verdict = "UPGRADE", weighted = 12 }
  local lines = CA.tooltipLines(row)
  local head = type(lines) == "table" and lines[1] and stripEscapes(lines[1].text) or nil
  print("E. clear-upgrade line  " .. tostring(head))
  check(head ~= nil, "a clear upgrade renders a line")
  check(head ~= nil and head:find("throughput not judged", 1, true) == nil,
    "a clear upgrade carries NO decline clause (got " .. tostring(head) .. ")")
  check(CA._tooltipUI.declineClause(row) == "",
    "a row with no arbitration asks the renderer for nothing")
  check(CA._tooltipUI.declineClause({ arbitration = { state = "SIDEGRADE" } }) == "",
    "an answered pair is never worded as a decline")
  check(CA._tooltipUI.declineClause(nil) == "",
    "the renderer answers \"\" for a row that is not a table")
end

print("")
if failed > 0 then
  print(("%d check(s) failed"):format(failed))
  os.exit(1)
end
print(("%d check(s) passed: the clause map is in the shipped bytes, called, and correct for both states")
  :format(checks))

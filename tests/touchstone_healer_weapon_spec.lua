-- tests/touchstone_healer_weapon_spec.lua — the healer weapon seam
-- (fk/healer-weapon-verdict; advisor ruling (e)+(a), Mightie's go 2026-11-22).
--
-- THE OWNER'S PAIR, at his character's level (34, not the item's 21):
--   hovered  Polished ZweiHander of Healing — 2H sword, 37-57, speed 3.60,
--            +9 Intellect, Equip: +34 healing / +11 spell damage
--   equipped Wolfsbane — 2H sword, 69-105, speed 3.40, +9 Stamina, +10 Intellect,
--            Chance on hit: 39-59 Holystorm, Enchanted: Weapon Damage +5
--
-- Before the seam, Holy's order-only weapon branch returned straight out of
-- Verdict.orderVerdict: Conservative Pareto read +34 Healing against -1 Intellect
-- as TRADE_OFF and the healer model was never asked (Verdict.arbitrate: 0 calls).
--
-- What this spec pins, on the SHIPPED bytes:
--   A. HEALING EVALUATION. Gear-for Holy with Role clear in Dungeon and Raid, and
--      with Role Spell in Leveling: the pair is not amber. The model is asked once, on the healing view (Weapon DPS,
--      Weapon Speed and Spell Damage left out, Stamina kept as survival data),
--      and the answer names what it did not count — "not counted for healing",
--      never "worthless" — and what the swap gives up.
--   B. THE SURFACE. The same row through ChestAdvisor.tooltipLines: the word is
--      Upgrade and the engine's clause survives the renderer whole.
--   C. A DECLINE STAYS AMBER AND SAYS WHY: sizes ("+34 Healing Power vs −1
--      Intellect") and the model's own cause sentence.
--   L. LEVELING WITH ROLE CLEAR (Review round 1): the pre-seam Trade-off stands,
--      the model is not asked, and the reason gains only the role hint.
--   S. SPELL POWER heals and the model does not price it: a pair that moves it is
--      not sent and stays amber with a printed cause; an unmoved one still is, and
--      no answer ever calls Spell Power "not counted for healing".
--   N. ENCHANTS (Review round 2): an enchant on either side that may change
--      healing (healing, spell power, mana, Intellect, Spirit, or text it cannot
--      place) keeps the pair out of the model with the sizes and the cause; a
--      melee-only enchant is still excluded and disclosed; never priced. The
--      Leveling hint appears only where the model really would be asked.
--   D. NOT HEALING: a recorded Melee role (nothing zeroed, pre-seam bytes),
--      Retribution, Protection (TANK + "spell") and a HEALER spec whose order
--      word is melee never reach the model.
--   T. THE TALENTS PATH carries the Context switch (Raid reads Raid); THE
--      FALLBACK PATH carries the recorded role (`/up role spell`, no gear-for).
--   M. MODEL OFF: Arbitration.ENABLED = false gives the pre-seam bytes.
--   E. No totals: the model is not asked and the bytes are the pre-seam ones.
--   F. SavedVariables (context, role and gearFor included, and any table, even an
--      empty one) are snapshotted around EVERY judgement and must come out unchanged.
--   G. MUTATIONS: the unmutated file is run through the same command first and
--      must report 0 failed; then each mutated copy of the shipped Verdict.lua
--      must report "N check(s), K failed" with K > 0. Anything else fails loudly.
--      Legs mutate Verdict.lua or ChestAdvisor.lua; every leg (the baseline too)
--      sets both TS_VERDICT_SRC and TS_ADVISOR_SRC. Skipped inside a leg.
--
-- The totals are the harness's, labelled as such: the level-34 paladin record the
-- decline-clause spec already uses (pool 2060, Int 101, Holy Light rank 5).
--
-- Run from the repo root:  lua5.1 tests/touchstone_healer_weapon_spec.lua
-- TS_VERDICT_SRC / TS_ADVISOR_SRC point the same assertions at other copies
-- (the pre-seam files, or a mutation).

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."
local TOUCH = root .. "/MightiePack/Modules/Touchstone/"
local VERDICT_SRC = os.getenv("TS_VERDICT_SRC") or (TOUCH .. "ChestAdvisor/Verdict.lua")
local ADVISOR_SRC = os.getenv("TS_ADVISOR_SRC") or (TOUCH .. "ChestAdvisor/ChestAdvisor.lua")

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

local C = dofile(root .. "/tests/support/wowclient.lua")
C.Install({ width = 1920, height = 1080 })
tinsert = table.insert
tremove = table.remove
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
MightiePackDB = { modules = {} }
StatForgeDB = { ui = { scale = 1 }, firstUse = false }
ChestAdvisorDB = { gearFor = "holy", context = "leveling", role = {} }
local pkg = { PackVersion = function() return "0.5.0" end }
_G.MightiePack = pkg

function UnitClass(unit) if unit == "player" then return "Paladin", "PALADIN", 2 end end
function UnitLevel(unit) if unit == "player" then return 34 end end
function UnitName(unit) if unit == "player" then return "Stank" end end
function GetInventoryItemLink() return nil end

local function loadPath(path, label)
  local chunk, err = loadfile(path)
  check(chunk ~= nil, "loadfile " .. label .. ": " .. tostring(err))
  if not chunk then return end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. label .. ": " .. tostring(e))
end
for _, name in ipairs({ "Bootstrap.lua", "Constants.lua", "Weights.lua", "UI.lua",
  "UpgradesTab.lua", "LogTab.lua", "ChestAdvisor/Marks.lua" }) do
  loadPath(TOUCH .. name, name)
end
loadPath(VERDICT_SRC, "Verdict.lua")
loadPath(TOUCH .. "ChestAdvisor/StatOrders.lua", "StatOrders.lua")
loadPath(TOUCH .. "ChestAdvisor/Arbitration.lua", "Arbitration.lua")
loadPath(ADVISOR_SRC, "ChestAdvisor.lua")

local CA, V, ARB = _G.ChestAdvisor, _G.Verdict, _G.Arbitration
if type(CA) ~= "table" or type(V) ~= "table" or type(ARB) ~= "table" then
  io.stderr:write("FAIL: the vendored tree did not load\n")
  os.exit(1)
end
pcall(CA.Enable)
ChestAdvisorDB.gearFor, ChestAdvisorDB.context, ChestAdvisorDB.role = "holy", "leveling", {}

-- ── the pair ─────────────────────────────────────────────────────────────────
local PROC = "Chance on hit: Sear the target with a vortex of blazing wind,"
  .. " dealing 39 to 59 Holystorm damage. Deals 3 times as much damage to Wolves and Worgen."
local ZWEI = { "Polished ZweiHander of Healing", "Two-Hand  Sword",
  "37 - 57 Damage  Speed 3.60", "(13.1 damage per second)", "+9 Intellect",
  "Equip: Increases healing done by up to 34 and damage done by up to 11"
    .. " for all magical spells and effects" }
local WOLF = { "Wolfsbane", "Two-Hand  Sword", "69 - 105 Damage  Speed 3.40",
  "(25.6 damage per second)", "+9 Stamina", "+10 Intellect", PROC,
  "Enchanted: Weapon Damage +5" }

local TOTALS = {
  pool = 2060, regenCasting = 5.5885, crit = 6.38, bonusHealing = 36, level = 34,
  regenMeasured = true,
  spell = { id = 19939, name = "Holy Light", rank = 5, cost = 190, castTimeMs = 2500 },
  stats = { Intellect = 101, Spirit = 80 },
}

-- The pre-seam reason, byte for byte (what the owner's tooltip printed).
local PRE_SEAM_HEAD = "decided by Healing Power [Holy (chosen)] — Trade-off: +Healing vs −Intellect"
local PRE_CLAUSE = " (judged, with an unpriced on-hit effect and an unpriced enchant on the equipped weapon)"
local PRE_SEAM = PRE_SEAM_HEAD .. PRE_CLAUSE
local HINT = ". Set Role to Spell (/up role spell) to judge this as a healer"
local HEALER_CLAUSE = " (judged, with Spell Damage, Weapon DPS, an on-hit effect and an enchant"
  .. " not counted for healing; you'd lose Wolfsbane's on-hit effect and its Weapon Damage +5 enchant)"

-- Count the model's calls without changing what it answers.
local arbCalls = 0
do
  local orig = V.arbitrate
  V.arbitrate = function(...) arbCalls = arbCalls + 1; return orig(...) end
end

local function snapshot(t, prefix, out)
  out = out or {}
  for k, x in pairs(t) do
    local key = (prefix or "") .. tostring(k)
    if type(x) == "table" then
      out[key] = "table"  -- the table itself, so a new EMPTY table is a new key
      snapshot(x, key .. ".", out)
    else
      out[key] = tostring(x)
    end
  end
  return out
end

-- Every judgement is bracketed by a SavedVariables snapshot (section F): the
-- seam may READ context, role and gearFor, and must write nothing.
local judgements = 0
local function judge(totals, cand, worn, spec)
  arbCalls = 0
  judgements = judgements + 1
  local before = snapshot(ChestAdvisorDB)
  spec = spec or CA.buildSpec()
  local v, r, d = V.compareWeapon(cand or ZWEI, worn or WOLF, true, spec, true, nil, nil, totals)
  local after = snapshot(ChestAdvisorDB)
  for k, x in pairs(before) do
    check(after[k] == x, "F: judgement " .. judgements .. " left ChestAdvisorDB." .. k .. " unchanged")
  end
  for k in pairs(after) do
    check(before[k] ~= nil, "F: judgement " .. judgements .. " added no key (" .. k .. ")")
  end
  return v, r, d, spec
end
do
  -- The snapshot itself can see a new EMPTY table and a changed scalar.
  local a, b = snapshot({ role = {} }), snapshot({ role = { PALADIN = {} } })
  check(b["role.PALADIN"] == "table" and a["role.PALADIN"] == nil,
    "F: the snapshot sees a newly created empty table")
end
local function setDB(gearFor, context, role)
  ChestAdvisorDB.gearFor, ChestAdvisorDB.context = gearFor, context
  ChestAdvisorDB.role = role and { PALADIN = role } or {}
end

-- (fk/talent-auto-role) the same spec with no profileSource: a spec that names
-- no healer itself, the only kind the round-1 Leveling rule and its hint still
-- cover.
local function bareOf(spec)
  local b = {}
  for k, x in pairs(spec) do b[k] = x end
  b.profileSource = nil
  return b
end

local function decided(label, ctx, v, r, d)
  local arb = type(d) == "table" and d.arbitration or nil
  local declinedWithCause = type(arb) == "table" and arb.declined == true
    and type(r) == "string" and r:find("Healer model: ", 1, true) ~= nil
  check(arbCalls == 1, label .. ": the healer model is asked exactly once (asked " .. arbCalls .. ")")
  check(v ~= "TRADE_OFF" or declinedWithCause,
    label .. ": not amber unless the model declines with a printed cause (got " .. tostring(v) .. ")")
  check(v == "UPGRADE", label .. ": with the harness totals the model decides UPGRADE (got " .. tostring(v) .. ")")
  check(type(arb) == "table" and arb.state == "UPGRADE" and arb.context == ctx,
    label .. ": the model's table rides the detail, for " .. ctx
      .. " (got " .. tostring(type(arb) == "table" and arb.context) .. ")")
  check(type(r) == "string" and r:sub(-#HEALER_CLAUSE) == HEALER_CLAUSE,
    label .. ": the answer says what was not counted and what the swap gives up (got " .. tostring(r) .. ")")
  check(type(r) == "string" and not r:lower():find("worthless", 1, true)
    and not r:find("unpriced", 1, true),
    label .. ": the disclosure says not counted, never worthless or unpriced")
end

-- ── A. healing evaluations ──────────────────────────────────────────────────
for _, ctx in ipairs({ "dungeon", "raid" }) do
  setDB("holy", ctx, nil)
  local v, r, d, spec = judge(TOTALS)
  print(("A. %-8s Role clear  %s  %s"):format(ctx, tostring(v), tostring(r)))
  check(spec.level == 34 and spec.weightsKey == "holy", "the spec is a level-34 chosen Holy paladin")
  check(V.healingContext and V.healingContext(spec) == true,
    ctx .. ": Gear-for Holy with Role clear is a healing evaluation")
  decided(ctx .. " / Role clear", ctx, v, r, d)
end
do
  setDB("holy", "leveling", "spell")
  local v, r, d, spec = judge(TOTALS)
  print("A. leveling Role spell  " .. tostring(v) .. "  " .. tostring(r))
  check(spec.recordedRole == "spell", "A: the recorded spell role reaches the spec")
  check(V.healingContext and V.healingContext(spec) == true, "A: Leveling with Role Spell is healing")
  decided("leveling / Role spell", "leveling", v, r, d)
end

-- ── L. Leveling with Role clear ─────────────────────────────────────────────
-- (fk/talent-auto-role) TALENTS DECIDE, the owner's call (Nov 26). This reverses
-- the round-1 Leveling rule for a spec that itself names the healer — a Gear-for
-- pick (here) or the talent tree Auto read (section AU): Leveling is a healing
-- evaluation and the pair goes to the model. A spec that names no healer itself
-- (the client-role fallback, modelled by dropping profileSource) keeps the old
-- verdict plus the hint.
do
  setDB("holy", "leveling", nil)
  local v, r, d, spec = judge(TOTALS)
  print("L. leveling Role clear  " .. tostring(v) .. "  " .. tostring(r))
  check(V.healingContext and V.healingContext(spec) == true,
    "L: Leveling with Role clear and Gear-for Holy is healing (round-1 rule reversed)")
  decided("leveling / Role clear / Gear-for Holy", "leveling", v, r, d)
  check(type(r) == "string" and r:find("/up role spell", 1, true) == nil, "L: no hint when the spec names the healer")
  check(V.healerRoleHint(spec) == false, "L: the hint rule itself says no for a spec that names the healer")
  check(V.healerRoleHint(bareOf(spec)) == true, "L: and yes for the same spec naming no healer")
  local bare = {}
  for k, x in pairs(spec) do bare[k] = x end
  bare.profileSource = nil
  local v2, r2, d2 = judge(TOTALS, nil, nil, bare)
  check(V.healingContext(bare) == false, "L: a spec that names no healer itself is not healing in Leveling")
  check(arbCalls == 0, "L: the model is not asked for it (asked " .. arbCalls .. ")")
  -- (no profileSource, so the profile label drops its "(chosen)")
  local BARE = (PRE_SEAM_HEAD .. HINT .. PRE_CLAUSE):gsub("%[Holy %(chosen%)%]", "[Holy]")
  check(v2 == "TRADE_OFF" and r2 == BARE,
    "L: the pre-seam verdict and reason, plus only the role hint (got " .. tostring(r2) .. ")")
  check(not (type(d2) == "table" and d2.arbitration), "L: no model table")
end

-- The healing view itself.
do
  local cand = { Healing = 34, Intellect = 9, SpellDamage = 11, WeaponDps = 13.1, WeaponSpeed = 3.6 }
  local eq = { Intellect = 10, Stamina = 9, WeaponDps = 25.6, WeaponSpeed = 3.4, SpellPower = 18 }
  check(type(V.healerView) == "function", "Verdict.healerView is published")
  local hc, he, excluded
  if type(V.healerView) == "function" then
    setDB("holy", "raid", nil)
    hc, he, excluded = V.healerView(cand, eq, V.profileFor(CA.buildSpec()))
  end
  check(table.concat(excluded or {}, ",") == "SpellDamage,WeaponDps,WeaponSpeed",
    "the healing view leaves out exactly Spell Damage, Weapon DPS and Weapon Speed (got "
      .. table.concat(excluded or {}, ",") .. ")")
  check(he and he.Stamina == 9 and hc and hc.Healing == 34 and he.Intellect == 10,
    "ranked words and the survival word stay in the view")
  check(he and he.SpellPower == 18, "Spell Power (it heals) is never left out of the healing view")
end

-- ── B. the surface ──────────────────────────────────────────────────────────
do
  setDB("holy", "raid", nil)
  local v, r, d = judge(TOTALS)
  local row = { id = 31141, lines = ZWEI, chestWornLines = WOLF, class = "PALADIN",
    role = "spell", verdict = v, reason = r, arbitration = d and d.arbitration or nil }
  -- The full disclosure is the Shift view (fk/tooltip-shift-details).
  local savedShift = IsShiftKeyDown
  IsShiftKeyDown = function() return true end
  local lines = CA.tooltipLines(row)
  IsShiftKeyDown = savedShift
  local function plain(t) return (tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  local all = {}
  for _, l in ipairs(type(lines) == "table" and lines or {}) do all[#all + 1] = plain(l.text) end
  print("B. tooltip: " .. table.concat(all, " / "))
  check(all[1] ~= nil and all[1]:find("Upgrade", 1, true) ~= nil,
    "the tooltip's word is Upgrade (got " .. tostring(all[1]) .. ")")
  check(table.concat(all, "\n"):find(HEALER_CLAUSE, 1, true) ~= nil,
    "the engine's clause reaches the tooltip whole")
  local _, clause = CA._disclosureClause(r)
  check(clause == HEALER_CLAUSE, "ChestAdvisor's splitter takes the clause off as one parenthetical")
  -- Shift UP (the default): the headline alone with the grey Shift marker
  -- (fk/tooltip-shift-details); the paragraph and its confidence are Shift-only.
  IsShiftKeyDown = function() return false end
  local short = {}
  for _, l in ipairs(CA.tooltipLines(row) or {}) do short[#short + 1] = plain(l.text) end
  IsShiftKeyDown = savedShift
  print("B. tooltip, Shift up: " .. table.concat(short, " / "))
  check(short[1] == all[1] .. " (Shift: details)" and #short == 1,
    "B: Shift up: the headline and the marker, one line (got " .. table.concat(short, " / ") .. ")")
end

-- ── C. a decline stays amber and says why ───────────────────────────────────
do
  setDB("holy", "raid", nil)
  local v, r, d = judge({ secret = true })
  print("C. declined: " .. tostring(v) .. "  " .. tostring(r))
  check(arbCalls == 1, "C: the model was asked")
  check(v == "TRADE_OFF", "C: a decline keeps the Trade-off word (got " .. tostring(v) .. ")")
  check(type(d) == "table" and type(d.arbitration) == "table" and d.arbitration.declined == true
    and d.arbitration.cause == "secret_totals", "C: the decline and its cause ride the detail")
  check(r == "decided by Healing Power [Holy (chosen)] — Trade-off: +34 Healing Power vs −1 Intellect."
    .. " Healer model: totals are secret: the client would not hand them over" .. PRE_CLAUSE,
    "C: the reason prints the sizes and the model's cause (got " .. tostring(r) .. ")")
end

-- ── S. Spell Power heals ────────────────────────────────────────────────────
local SP_EQ = { "Staff of Bright Words", "Two-Hand  Sword", "69 - 105 Damage  Speed 3.40",
  "(25.6 damage per second)", "+10 Intellect",
  "Equip: Increases damage and healing done by magical spells and effects by up to 18." }
local SP_CAND = { "Mender's Greatsword", "Two-Hand  Sword", "37 - 57 Damage  Speed 3.60",
  "(13.1 damage per second)", "+9 Intellect",
  "Equip: Increases healing done by up to 10 and damage done by up to 4"
    .. " for all magical spells and effects" }
do
  check(V.statTable(SP_EQ, "worn", nil).SpellPower == 18, "S: the heals-too line reads as SpellPower")
  check(V.statTable(ZWEI, "candidate", nil).SpellPower == nil,
    "S: the ZweiHander's '+11 damage' is damage-only Spell Damage, not Spell Power")
  setDB("holy", "raid", nil)
  local v, r, d = judge(TOTALS, SP_CAND, SP_EQ)
  print("S. moves SP: " .. tostring(v) .. "  " .. tostring(r))
  check(arbCalls == 0, "S: a pair that moves Spell Power is not sent to the model (asked " .. arbCalls .. ")")
  check(v == "TRADE_OFF", "S: it stays Trade-off (got " .. tostring(v) .. ")")
  check(type(r) == "string" and r:find("Trade-off: +10 Healing Power vs −1 Intellect.", 1, true) ~= nil
    and r:find("Healer model: not asked — the pair moves Spell Power, which heals, and the model does not price it yet", 1, true) ~= nil,
    "S: the reason prints the sizes and the cause (got " .. tostring(r) .. ")")
  check(type(r) == "string" and r:find("not counted", 1, true) == nil,
    "S: nothing is called not counted on that pair")
  check(not (type(d) == "table" and d.arbitration), "S: no model table on a pair it was not asked about")
  -- Equal Spell Power on both sides moves nothing, so the pair is still judged,
  -- and the disclosure does not name Spell Power.
  local zweiSP, wolfSP = {}, {}
  for i, l in ipairs(ZWEI) do zweiSP[i] = l end
  for i, l in ipairs(WOLF) do wolfSP[i] = l end
  table.insert(zweiSP, 6, "Equip: Increases damage and healing done by magical spells and effects by up to 7.")
  table.insert(wolfSP, 7, "Equip: Increases damage and healing done by magical spells and effects by up to 7.")
  local v2, r2 = judge(TOTALS, zweiSP, wolfSP)
  print("S. equal SP: " .. tostring(v2) .. "  " .. tostring(r2))
  check(arbCalls == 1 and v2 == "UPGRADE", "S: equal Spell Power still reaches the model (got "
    .. tostring(v2) .. ", asked " .. arbCalls .. ")")
  check(type(r2) == "string" and r2:find("Spell Power", 1, true) == nil,
    "S: the disclosure never names Spell Power as not counted")
end

-- ── N. enchants that may change healing ─────────────────────────────────────
local function sword(name, extra)
  local t = { name, "Two-Hand  Sword", "69 - 105 Damage  Speed 3.40", "(25.6 damage per second)" }
  for _, l in ipairs(extra) do t[#t + 1] = l end
  return t
end
local HEAL20 = sword("Mender's Greatsword", { "+9 Intellect",
  "Equip: Increases healing done by up to 20 and damage done by up to 7 for all magical spells and effects" })
local function enchantCase(label, cand, worn, cause)
  setDB("holy", "raid", nil)
  local v, r, d = judge(TOTALS, cand, worn)
  print(("N. %-22s %s  %s"):format(label, tostring(v), tostring(r)))
  check(arbCalls == 0, "N: " .. label .. ": the model is not asked (asked " .. arbCalls .. ")")
  check(v == "TRADE_OFF", "N: " .. label .. ": it stays Trade-off (got " .. tostring(v) .. ")")
  check(type(r) == "string" and r:find("Trade-off: +20 Healing Power vs −1 Intellect. Healer model: "
      .. cause, 1, true) ~= nil,
    "N: " .. label .. ": the reason prints the sizes and the cause (got " .. tostring(r) .. ")")
  check(type(r) == "string" and r:find("not counted for healing", 1, true) == nil,
    "N: " .. label .. ": nothing is called not counted for healing")
  check(not (type(d) == "table" and d.arbitration), "N: " .. label .. ": no model table")
end
enchantCase("worn Healing Power", HEAL20, sword("Worn Mace", { "+10 Intellect", "Enchanted: Healing Power +30" }),
  "not asked — the equipped weapon's enchant, Healing Power +30, may change healing, and enchants are never priced")
enchantCase("worn Spell Power", HEAL20, sword("Worn Mace", { "+10 Intellect", "Enchanted: Spell Power +30" }),
  "not asked — the equipped weapon's enchant, Spell Power +30, may change healing, and enchants are never priced")
do
  local cand = {}
  for i, l in ipairs(HEAL20) do cand[i] = l end
  cand[#cand + 1] = "|cff00ff00Enchanted: Spell Damage and Healing +12|r"
  enchantCase("hovered dmg+healing", cand, sword("Worn Mace", { "+10 Intellect" }),
    "not asked — the hovered weapon's enchant, Spell Damage and Healing +12, may change healing,"
      .. " and enchants are never priced")
end
enchantCase("worn Spell Damage", HEAL20, sword("Worn Mace", { "+10 Intellect", "Enchanted: Spell Damage +40" }),
  "not asked — the equipped weapon's enchant, Spell Damage +40, may change healing, and enchants are never priced")
enchantCase("worn unknown text", HEAL20, sword("Worn Mace", { "+10 Intellect", "Enchanted: Crusader" }),
  "not asked — the equipped weapon's enchant, Crusader, may change healing, and enchants are never priced")
do
  -- A melee-only enchant keeps the earlier behaviour: judged, excluded, disclosed,
  -- and the possessive reads once ("Worn Mace's Weapon Damage +5 enchant").
  setDB("holy", "raid", nil)
  local v, r = judge(TOTALS, HEAL20, sword("Worn Mace", { "+10 Intellect", "Enchanted: Weapon Damage +5" }))
  print("N. melee-only enchant    " .. tostring(v) .. "  " .. tostring(r))
  check(arbCalls == 1, "N: a melee-only enchant still lets the model judge (asked " .. arbCalls .. ")")
  check(type(r) == "string" and r:sub(-#"; you'd lose Worn Mace's Weapon Damage +5 enchant)")
      == "; you'd lose Worn Mace's Weapon Damage +5 enchant)" and r:find("'s its", 1, true) == nil,
    "N: the swap's loss reads as one possessive (got " .. tostring(r) .. ")")
  check(type(V.enchantMayHeal) == "function", "N: Verdict.enchantMayHeal is published")
  local mayHeal = type(V.enchantMayHeal) == "function" and V.enchantMayHeal or function() return nil end
  check(mayHeal("Weapon Damage +5") == false and mayHeal("+15 Strength") == false
    and mayHeal("Healing Power +55") == true and mayHeal("+22 Intellect") == true
    and mayHeal("Spell Damage +40") == true and mayHeal("Spell Power +30") == true
    and mayHeal("Brilliant Mana Oil") == true and mayHeal("") == true,
    "N: the enchant read is conservative: melee-only is out, anything that could heal is in")
end
do
  -- The hint promises a judgement, so it is absent where Role Spell would still
  -- not ask the model (a healing enchant, a Spell Power difference).
  setDB("holy", "leveling", nil)
  local bare = bareOf(CA.buildSpec())
  local _, r1 = judge(TOTALS, HEAL20, sword("Worn Mace", { "+10 Intellect", "Enchanted: Healing Power +30" }), bare)
  check(arbCalls == 0 and type(r1) == "string" and r1:find("/up role spell", 1, true) == nil,
    "N: Leveling, Role clear, healing enchant: no hint (got " .. tostring(r1) .. ")")
  local _, r2 = judge(TOTALS, SP_CAND, SP_EQ, bare)
  check(arbCalls == 0 and type(r2) == "string" and r2:find("/up role spell", 1, true) == nil,
    "N: Leveling, Role clear, Spell Power moves: no hint (got " .. tostring(r2) .. ")")
end

-- ── L2. the hint needs NO recorded role, and a spec with no context is Leveling
do
  setDB("holy", "leveling", "melee")
  local v, r = judge(TOTALS)
  print("L. leveling Role melee  " .. tostring(v) .. "  " .. tostring(r))
  local _, rb = judge(TOTALS, nil, nil, bareOf(CA.buildSpec()))
  check(arbCalls == 0 and type(rb) == "string" and rb:find("/up role spell", 1, true) == nil,
    "L: a recorded Melee role: no hint on a spec naming no healer either (got " .. tostring(rb) .. ")")
  check(arbCalls == 0 and v == "TRADE_OFF" and r == PRE_SEAM,
    "L: Leveling with a recorded Melee role: the pre-seam bytes, no hint (got " .. tostring(r) .. ")")
  setDB("holy", "raid", nil)
  local spec = CA.buildSpec()
  local noCtx = {}
  for k, x in pairs(spec) do noCtx[k] = x end
  noCtx.context = nil
  check(V.healingContext(noCtx) == true, "L: a Gear-for Holy spec with no context is healing")
  noCtx.profileSource = nil
  local v2, r2 = judge(TOTALS, nil, nil, noCtx)
  local BARE = (PRE_SEAM_HEAD .. HINT .. PRE_CLAUSE):gsub("%[Holy %(chosen%)%]", "[Holy]")
  check(arbCalls == 0 and v2 == "TRADE_OFF" and r2 == BARE,
    "L: a spec with no context reads as Leveling: not asked, the hint (got " .. tostring(r2) .. ")")
end

-- ── D. not a healing evaluation: nothing zeroed ─────────────────────────────
do
  setDB("holy", "raid", "melee")
  local v, r, d, spec = judge(TOTALS)
  print("D. melee:    " .. tostring(v) .. "  " .. tostring(r))
  check(spec.recordedRole == "melee", "D: the recorded role reaches the spec")
  check(V.healingContext and V.healingContext(spec) == false, "D: a recorded Melee role is not a healing evaluation")
  check(arbCalls == 0, "D: the healer model is NOT asked under a Melee role (asked " .. arbCalls .. ")")
  check(v == "TRADE_OFF" and r == PRE_SEAM,
    "D: Weapon DPS and the proc stay in play — the pre-seam verdict and bytes (got " .. tostring(r) .. ")")
  check(not (type(d) == "table" and d.arbitration), "D: no model table on a melee row")
end
for _, key in ipairs({ "ret", "prot" }) do
  setDB(key, "raid", nil)
  local v, r, d, spec = judge(TOTALS)
  print(("D. %-5s     %s  %s"):format(key, tostring(v), tostring(r)))
  check(V.healingContext and V.healingContext(spec) == false, "D: " .. key .. " is not a healing evaluation")
  check(arbCalls == 0 and not (type(d) == "table" and d.arbitration),
    "D: " .. key .. "'s weapon verdict never reaches the healer model (asked " .. arbCalls .. ")")
  check(type(r) == "string" and r:find("not counted for healing", 1, true) == nil
    and r:find("/up role spell", 1, true) == nil, "D: " .. key .. " gets no healer clause and no hint")
end
do
  -- Protection (TANK + the "spell" order word) on a pair its own order calls a
  -- Trade-off: the seam's gate is reached, and it is not a healing evaluation.
  local PROT_CAND = { "Guard's Greatsword", "Two-Hand  Sword", "69 - 105 Damage  Speed 3.40",
    "(25.6 damage per second)", "+12 Stamina" }
  local PROT_EQ = { "Old Greatsword", "Two-Hand  Sword", "69 - 105 Damage  Speed 3.40",
    "(25.6 damage per second)", "+9 Stamina", "+10 Intellect" }
  setDB("prot", "raid", nil)
  local v, r, d, spec = judge(TOTALS, PROT_CAND, PROT_EQ)
  print("D. prot T-O: " .. tostring(v) .. "  " .. tostring(r))
  check(spec.clientRole == "TANK" and spec.role == "spell", "D: the Protection case is TANK with the 'spell' order word")
  check(v == "TRADE_OFF", "D: Protection's own order calls the pair a Trade-off (got " .. tostring(v) .. ")")
  check(arbCalls == 0 and not (type(d) == "table" and d.arbitration),
    "D: Protection's Trade-off never reaches the healer model (asked " .. arbCalls .. ")")
  check(type(r) == "string" and r:find("/up role spell", 1, true) == nil
    and r:find("Healer model", 1, true) == nil, "D: Protection gets no healer cause and no hint")
end
do
  -- A HEALER spec whose order word is melee (hand-built; no registry entry has one).
  setDB("holy", "raid", nil)
  local spec = CA.buildSpec()
  local melee = {}
  for k, x in pairs(spec) do melee[k] = x end
  melee.role = "melee"
  local v, r, d = judge(TOTALS, nil, nil, melee)
  check(arbCalls == 0 and not (type(d) == "table" and d.arbitration),
    "D: a HEALER spec with the melee order word never reaches the model (asked " .. arbCalls .. ")")
end

-- ── T. the talents path carries Context ─────────────────────────────────────
do
  C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 1, "Holy", "", 0, "HEALER" end,
  }
  setDB(nil, "raid", nil)
  local v, r, d, spec = judge(TOTALS)
  print("T. talents:  " .. tostring(v) .. "  " .. tostring(r))
  check(spec.profileSource == "talents" and spec.weightsKey == "holy", "T: the talents path resolved Holy")
  check(spec.context == "raid", "T: the talents-path spec carries the Context switch (got "
    .. tostring(spec.context) .. ")")
  check(arbCalls == 1 and type(d) == "table" and type(d.arbitration) == "table"
    and d.arbitration.context == "raid",
    "T: the model judges the talents-path pair for Raid (got "
      .. tostring(type(d) == "table" and type(d.arbitration) == "table" and d.arbitration.context) .. ")")
  -- THE FALLBACK PATH: no gear-for and a recorded `/up role spell`, so the
  -- talents path is skipped; the recorded role must still reach the seam.
  setDB(nil, "leveling", "spell")
  local fv, fr, fd, fspec = judge(TOTALS)
  print("T. fallback: " .. tostring(fv) .. "  " .. tostring(fr))
  check(fspec.weightsKey == nil and fspec.clientRole == "HEALER" and fspec.role == "spell",
    "T: the fallback path was taken (HEALER, spell, no weights key)")
  check(fspec.recordedRole == "spell", "T: the fallback-path spec carries the recorded role")
  check(arbCalls == 1 and type(fd) == "table" and type(fd.arbitration) == "table"
    and fd.arbitration.context == "leveling",
    "T: Leveling with /up role spell on the fallback path is judged by the model (asked " .. arbCalls .. ")")
  C_SpecializationInfo = nil
end

-- ── AU. Auto: the talent points decide (fk/talent-auto-role) ─────────────────
-- The Forever client's shape: one class-wide spec ("Paladin", DAMAGER, id 1486),
-- and the three classic trees as trait groups with points spent.
local function talentClient(points, names)
  names = names or { "Holy", "Protection", "Retribution" }
  C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 1486, "Paladin", "", 0, "DAMAGER" end,
  }
  C_ClassTalents = {
    GetActiveConfigID = function() return 7 end,
    GetTraitTreeForSpec = function(id) return id == 1486 and 860 or nil end,
  }
  C_Traits = {
    GetGroupDisplayInfoByTreeID = function(t)
      local out = {}
      for i, n in ipairs(names) do out[i] = { groupID = 100 + i, treeID = t, orderIndex = i - 1, displayName = n } end
      return out
    end,
    GetGroupCurrencyInfo = function(_, ids)
      local out = {}
      for i, id in ipairs(ids) do out[i] = { traitNodeGroupID = id, currencyInfos = { { spent = points[id - 100] } } } end
      return out
    end,
  }
  CA._onTalentsChanged("spec")
end
do
  talentClient({ 21, 5, 0 })
  setDB(nil, "leveling", nil)
  local v, r, d, spec = judge(TOTALS)
  print("AU. Auto Holy, Leveling, Role Auto: " .. tostring(v) .. "  " .. tostring(r))
  check(spec.profileSource == "talents" and spec.weightsKey == "holy" and spec.clientRole == "HEALER"
    and spec.role == "spell" and spec.recordedRole == nil,
    "AU: Auto read Holy from the talent points (got " .. tostring(spec.weightsKey) .. "/" .. tostring(spec.clientRole) .. ")")
  check(v == "UPGRADE", "AU: Leveling + Auto Holy: the Zweihander is an Upgrade without touching Role (got " .. tostring(v) .. ")")
  decided("leveling / Auto Holy", "leveling", v, r, d)
  -- A recorded Melee role still wins: the questing healer who melees.
  setDB(nil, "leveling", "melee")
  local mv, _, md, mspec = judge(TOTALS)
  check(mspec.recordedRole == "melee" and mspec.weightsKey ~= "holy" and arbCalls == 0
    and not (type(md) == "table" and md.arbitration) and mv ~= "UPGRADE",
    "AU: a recorded Melee role overrides Auto (got " .. tostring(mv) .. ")")
  -- A recorded Spell role that agrees with the tree takes the tree's spec.
  setDB(nil, "leveling", "spell")
  local _, _, _, sspec = judge(TOTALS)
  check(sspec.weightsKey == "holy" and sspec.recordedRole == "spell" and sspec.clientRole == "HEALER",
    "AU: Spell agrees with Holy: the tree's spec, carrying the recorded word")
  -- A Gear-for pick still wins over Auto.
  setDB("ret", "leveling", nil)
  check(CA.buildSpec().weightsKey == "ret", "AU: a Gear-for pick overrides Auto")
  -- Retribution points: melee, no healing evaluation.
  talentClient({ 0, 5, 21 })
  setDB(nil, "leveling", nil)
  local rv, _, rd, rspec = judge(TOTALS)
  check(rspec.weightsKey == "ret" and arbCalls == 0 and not (type(rd) == "table" and rd.arbitration),
    "AU: Auto Retribution is not a healing evaluation (got " .. tostring(rspec.weightsKey) .. ", " .. tostring(rv) .. ")")
  -- No API: today's behaviour (the fallback path, no Auto).
  C_ClassTalents, C_Traits, C_SpecializationInfo = nil, nil, nil
  CA._onTalentsChanged("spec")
  local nspec = CA.buildSpec()
  check(nspec.weightsKey == nil and CA.autoTalentPick("PALADIN") == nil,
    "AU: no talent API: Auto picks nothing, the old fallback path (got " .. tostring(nspec.weightsKey) .. ")")
end

-- ── M. model off ────────────────────────────────────────────────────────────
do
  setDB("holy", "raid", nil)
  ARB.ENABLED = false
  local v, r, d = judge(TOTALS)
  ARB.ENABLED = true
  print("M. model off: " .. tostring(v) .. "  " .. tostring(r))
  check(arbCalls == 0 and v == "TRADE_OFF" and r == PRE_SEAM and not (type(d) == "table" and d.arbitration),
    "M: with the model off the bytes are the pre-seam ones (got " .. tostring(r) .. ", asked " .. arbCalls .. ")")
end

-- ── E. no totals: the model is not asked ────────────────────────────────────
do
  setDB("holy", "raid", nil)
  local v, r = judge(nil)
  check(arbCalls == 0 and v == "TRADE_OFF" and r == PRE_SEAM,
    "E: with no totals the bytes are the pre-seam ones (got " .. tostring(r) .. ")")
end

-- ── G. mutations ────────────────────────────────────────────────────────────
-- One runner for the baseline and every mutant, and one reading of its result:
-- the LAST "N check(s), K failed" line. No such line is a failure, never a kill.
local function runLeg(vpath, apath)
  local lua = (arg and arg[-1]) or "lua5.1"
  local cmd = ("cd %q && TS_VERDICT_SRC=%q TS_ADVISOR_SRC=%q %s tests/touchstone_healer_weapon_spec.lua 2>&1")
    :format(root, vpath, apath, lua)
  local p = io.popen(cmd)
  local out = p and p:read("*a") or ""
  if p then p:close() end
  local n, k
  for a, b in out:gmatch("(%d+) check%(s%), (%d+) failed") do n, k = tonumber(a), tonumber(b) end
  return n, k, out
end
if os.getenv("TS_VERDICT_SRC") == nil and os.getenv("TS_ADVISOR_SRC") == nil then
  local shipped = readFile(TOUCH .. "ChestAdvisor/Verdict.lua") or ""
  local shippedCA = readFile(TOUCH .. "ChestAdvisor/ChestAdvisor.lua") or ""
  local function legFile(text)
    local path = os.tmpname()
    local f = io.open(path, "w"); f:write(text); f:close()
    return path
  end
  local basePath, baseCA = legFile(shipped), legFile(shippedCA)
  local bn, bk, bout = runLeg(basePath, baseCA)
  os.remove(basePath); os.remove(baseCA)
  print(("G. baseline (unmutated, same command): %s check(s), %s failed"):format(tostring(bn), tostring(bk)))
  check(bn ~= nil and bn > 0 and bk == 0,
    "G: the unmutated file must run through the leg command and report 0 failed — the mutation"
      .. " legs below prove nothing otherwise. Output:\n" .. bout:sub(-400))
  local MUTANTS = {
    { "the healing gate dropped", "\t\t\t\tif Verdict.healingContext(spec) then\n", "\t\t\t\tif true then\n" },
    { "the healing view keeps every word", "\t\t\t\tif keep[w] then\n", "\t\t\t\tif true then\n" },
    { "the recorded melee role ignored", "\tif spec.recordedRole == \"melee\" then return false end\n", "" },
    { "the decline sizes not printed",
      "\t\t\t\t\tif sized ~= nil and plain ~= nil and type(tr) == \"string\" then\n", "\t\t\t\t\tif false then\n" },
    { "the HEALER role check dropped", "spec.clientRole == \"HEALER\" and ", "" },
    { "the 'spell' order-word check dropped", " and spec.role == \"spell\"", "" },
    { "the model-on check dropped", "\t\t\tif type(Arb) == \"table\" and Arb.ENABLED == true then\n\t\t\t\ttd =",
      "\t\t\tif type(Arb) == \"table\" then\n\t\t\t\ttd =" },
    { "the Spell Power guard dropped", "\t\t\t\tif Verdict.ranksAsDifferent(spDelta) then\n",
      "\t\t\t\tif false then\n" },
    { "the enchant guard dropped", "\t\t\t\t\tif eSide ~= nil then\n", "\t\t\t\t\tif false then\n" },
    { "the enchant scan finds nothing",
      "if Verdict.enchantMayHeal(payload) then return side[2], payload end", "" },
    { "the healing-words check dropped",
      "\t\tif low:find(w, 1, true) then return true end\n", "" },
    { "unknown enchant text read as melee-only",
      "\t\tif low:find(w, 1, true) then return false end\n\tend\n\treturn true\n",
      "\t\tif low:find(w, 1, true) then return false end\n\tend\n\treturn false\n" },
    { "the hovered side's enchant not read", "{ { wornLines, \"worn\" }, { candLines, \"candidate\" } }",
      "{ { wornLines, \"worn\" } }" },
    { "the hint not gated on the blind checks", "elseif blind == nil and Verdict.healerRoleHint(spec) then",
      "elseif Verdict.healerRoleHint(spec) then" },
    { "the hint ignores the recorded role", "return spec.recordedRole == nil and levelingContext(spec)",
      "return levelingContext(spec)" },
    { "a nil context not read as Leveling", "return c == nil or c == \"leveling\"",
      "return c == \"leveling\"" },
    { "the possessive reads twice", "lose[#lose + 1] = (enchant.worn ~= \"\") and (enchant.worn .. \" enchant\") or \"enchant\"",
      "lose[#lose + 1] = (enchant.worn ~= \"\") and (\"its \" .. enchant.worn .. \" enchant\") or \"its enchant\"" },
    { "the spec-names-healer rule dropped", "\tif Verdict.specNamesHealer(spec) then return true end\n", "" },
    { "the hint shown where the spec names the healer", " and not Verdict.specNamesHealer(spec)", "" },
    { "Gear-for no longer names the healer", " or spec.profileSource == \"chosen\"", "" },
    { "the Leveling/no-role gate dropped",
      "\tif spec.recordedRole ~= \"spell\" and levelingContext(spec) then return false end\n", "" },
  }
  -- ChestAdvisor.lua mutants (the spec's own buildSpec paths).
  local ADVISOR_MUTANTS = {
    { "the fallback path's recordedRole removed",
      "\t         context = contextWord(),\n\t         -- the recorded `/up role` word, read only (healer weapon seam)\n"
        .. "\t         recordedRole = playerRole(token) }",
      "\t         context = contextWord() }" },
    { "the talents path's context removed",
      "\t\t\t\tcontext = contextWord(),\n\t\t\t\t-- No role is recorded on this path", "\t\t\t\t-- No role is recorded on this path" },
    { "the chosen path's recordedRole removed", "\t\t\trecordedRole = playerRole(token),\n", "" },
    { "Auto's tree never consulted", "\t\tif talent == nil and auto ~= nil then talent = auto.entry end\n", "" },
    { "an agreeing role not carried", "\t\t\t\trecordedRole = recorded,\n", "\t\t\t\trecordedRole = nil,\n" },
    { "a recorded Melee role ignored by Auto", "local agrees = recorded ~= nil and auto ~= nil and auto.entry.orderWord == recorded",
      "local agrees = recorded ~= nil and auto ~= nil" },
  }
  for _, m in ipairs(MUTANTS) do m.ca = false end
  for _, m in ipairs(ADVISOR_MUTANTS) do m.ca = true; MUTANTS[#MUTANTS + 1] = m end
  for _, m in ipairs(MUTANTS) do
    local src = m.ca and shippedCA or shipped
    local s, e = src:find(m[2], 1, true)
    check(s ~= nil, "G: mutation anchor present: " .. m[1])
    check(s == nil or src:find(m[2], e + 1, true) == nil, "G: mutation anchor is unique: " .. m[1])
    if s ~= nil and bk == 0 then
      local mutated = src:sub(1, s - 1) .. m[3] .. src:sub(e + 1)
      local vpath = legFile(m.ca and shipped or mutated)
      local apath = legFile(m.ca and mutated or shippedCA)
      local n, k, out = runLeg(vpath, apath)
      os.remove(vpath); os.remove(apath)
      print(("G. mutant %-38s %s"):format(m[1],
        (n == nil) and "NO RESULT LINE" or (k > 0 and ("killed (" .. k .. "/" .. n .. ")") or "SURVIVED")))
      check(n ~= nil, "G: the mutant leg printed its result line: " .. m[1] .. ". Output:\n" .. out:sub(-400))
      check(n ~= nil and k > 0, "G: the spec fails on the mutant: " .. m[1])
    end
  end
end

print(("%d check(s), %d failed"):format(checks, failed))
if failed > 0 then os.exit(1) end

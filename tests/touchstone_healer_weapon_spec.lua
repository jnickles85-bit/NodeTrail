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
--   A. HEALING EVALUATION. Gear-for Holy, Role clear, every Context: the pair is
--      not amber. The model is asked once, on the healing view (Weapon DPS,
--      Weapon Speed and Spell Damage left out, Stamina kept as survival data),
--      and the answer names what it did not count — "not counted for healing",
--      never "worthless" — and what the swap gives up.
--   B. THE SURFACE. The same row through ChestAdvisor.tooltipLines: the word is
--      Upgrade and the engine's clause survives the renderer whole.
--   C. A DECLINE STAYS AMBER AND SAYS WHY: sizes ("+34 Healing Power vs −1
--      Intellect") and the model's own cause sentence.
--   D. MELEE ROLE. With `/up role melee` recorded, nothing is zeroed: the model
--      is not asked and the reason is the pre-seam bytes, proc clause included.
--   E. No totals: the model is not asked and the bytes are the pre-seam ones.
--   F. SavedVariables are read, never written, by the seam.
--   G. MUTATIONS (cheap): four mutated copies of the shipped Verdict.lua must each
--      fail this spec (skipped when TS_VERDICT_SRC is set, i.e. inside a leg).
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
local PRE_SEAM = "decided by Healing Power [Holy (chosen)] — Trade-off: +Healing vs −Intellect"
  .. " (judged, with an unpriced on-hit effect and an unpriced enchant on the equipped weapon)"
local HEALER_CLAUSE = " (judged, with Spell Damage, Weapon DPS, an on-hit effect and an enchant"
  .. " not counted for healing; you'd lose Wolfsbane's on-hit effect and its Weapon Damage +5 enchant)"

-- Count the model's calls without changing what it answers.
local arbCalls = 0
do
  local orig = V.arbitrate
  V.arbitrate = function(...) arbCalls = arbCalls + 1; return orig(...) end
end
local function judge(totals)
  arbCalls = 0
  local spec = CA.buildSpec()
  local v, r, d = V.compareWeapon(ZWEI, WOLF, true, spec, true, nil, nil, totals)
  return v, r, d, spec
end

local function snapshot(t, prefix, out)
  out = out or {}
  for k, x in pairs(t) do
    local key = (prefix or "") .. tostring(k)
    if type(x) == "table" then snapshot(x, key .. ".", out) else out[key] = tostring(x) end
  end
  return out
end
local svBefore = snapshot(ChestAdvisorDB)

-- ── A. healing evaluation: every context ────────────────────────────────────
for _, ctx in ipairs({ "leveling", "dungeon", "raid" }) do
  ChestAdvisorDB.context = ctx
  local v, r, d, spec = judge(TOTALS)
  print(("A. %-8s  %s  %s"):format(ctx, tostring(v), tostring(r)))
  check(spec.level == 34 and spec.weightsKey == "holy", "the spec is a level-34 chosen Holy paladin")
  check(V.healingContext and V.healingContext(spec) == true,
    ctx .. ": Gear-for Holy with Role clear is a healing evaluation")
  check(arbCalls == 1, ctx .. ": the healer model is asked exactly once (asked " .. arbCalls .. ")")
  local arb = type(d) == "table" and d.arbitration or nil
  local declinedWithCause = type(arb) == "table" and arb.declined == true
    and type(r) == "string" and r:find("Healer model: ", 1, true) ~= nil
  check(v ~= "TRADE_OFF" or declinedWithCause,
    ctx .. ": the pair is not amber unless the model declines with a printed cause (got "
      .. tostring(v) .. ")")
  check(v == "UPGRADE", ctx .. ": with the harness totals the model decides UPGRADE (got " .. tostring(v) .. ")")
  check(type(arb) == "table" and arb.state == "UPGRADE" and arb.context == ctx,
    ctx .. ": the model's table rides the detail, for this context")
  check(type(r) == "string" and r:sub(-#HEALER_CLAUSE) == HEALER_CLAUSE,
    ctx .. ": the answer says what was not counted and what the swap gives up (got " .. tostring(r) .. ")")
  check(type(r) == "string" and not r:lower():find("worthless", 1, true)
    and not r:find("unpriced", 1, true),
    ctx .. ": the disclosure says not counted, never worthless or unpriced")
end
ChestAdvisorDB.context = "leveling"

-- The healing view itself.
do
  local cand = { Healing = 34, Intellect = 9, SpellDamage = 11, WeaponDps = 13.1, WeaponSpeed = 3.6 }
  local eq = { Intellect = 10, Stamina = 9, WeaponDps = 25.6, WeaponSpeed = 3.4 }
  check(type(V.healerView) == "function", "Verdict.healerView is published")
  local hc, he, excluded
  if type(V.healerView) == "function" then
    hc, he, excluded = V.healerView(cand, eq, V.profileFor(CA.buildSpec()))
  end
  check(table.concat(excluded or {}, ",") == "SpellDamage,WeaponDps,WeaponSpeed",
    "the healing view leaves out exactly Spell Damage, Weapon DPS and Weapon Speed (got "
      .. table.concat(excluded or {}, ",") .. ")")
  check(he and he.Stamina == 9 and hc and hc.Healing == 34 and he.Intellect == 10,
    "ranked words and the survival word stay in the view")
end

-- ── B. the surface ──────────────────────────────────────────────────────────
do
  local v, r, d = judge(TOTALS)
  local row = { id = 31141, lines = ZWEI, chestWornLines = WOLF, class = "PALADIN",
    role = "spell", verdict = v, reason = r, arbitration = d and d.arbitration or nil }
  local lines = CA.tooltipLines(row)
  local function plain(t) return (tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  local all = {}
  for _, l in ipairs(type(lines) == "table" and lines or {}) do all[#all + 1] = plain(l.text) end
  print("B. tooltip: " .. table.concat(all, " / "))
  check(all[1] ~= nil and all[1]:find("Upgrade", 1, true) ~= nil,
    "the tooltip's word is Upgrade (got " .. tostring(all[1]) .. ")")
  local joined = table.concat(all, "\n")
  check(joined:find(HEALER_CLAUSE, 1, true) ~= nil,
    "the engine's clause reaches the tooltip whole")
  local _, clause = CA._disclosureClause(r)
  check(clause == HEALER_CLAUSE, "ChestAdvisor's splitter takes the clause off as one parenthetical")
end

-- ── C. a decline stays amber and says why ───────────────────────────────────
do
  local v, r, d = judge({ secret = true })
  print("C. declined: " .. tostring(v) .. "  " .. tostring(r))
  check(arbCalls == 1, "C: the model was asked")
  check(v == "TRADE_OFF", "C: a decline keeps the Trade-off word (got " .. tostring(v) .. ")")
  check(type(d) == "table" and type(d.arbitration) == "table" and d.arbitration.declined == true
    and d.arbitration.cause == "secret_totals", "C: the decline and its cause ride the detail")
  check(r == "decided by Healing Power [Holy (chosen)] — Trade-off: +34 Healing Power vs −1 Intellect."
    .. " Healer model: totals are secret: the client would not hand them over"
    .. " (judged, with an unpriced on-hit effect and an unpriced enchant on the equipped weapon)",
    "C: the reason prints the sizes and the model's cause (got " .. tostring(r) .. ")")
end

-- ── D. melee role: nothing zeroed ───────────────────────────────────────────
do
  ChestAdvisorDB.role = { PALADIN = "melee" }
  local v, r, d, spec = judge(TOTALS)
  print("D. melee:    " .. tostring(v) .. "  " .. tostring(r))
  check(spec.recordedRole == "melee", "D: the recorded role reaches the spec")
  check(V.healingContext and V.healingContext(spec) == false, "D: a recorded Melee role is not a healing evaluation")
  check(arbCalls == 0, "D: the healer model is NOT asked under a Melee role (asked " .. arbCalls .. ")")
  check(v == "TRADE_OFF" and r == PRE_SEAM,
    "D: Weapon DPS and the proc stay in play — the pre-seam verdict and bytes (got " .. tostring(r) .. ")")
  check(not (type(d) == "table" and d.arbitration), "D: no model table on a melee row")
  check(type(r) == "string" and r:find("not counted for healing", 1, true) == nil,
    "D: nothing is called not-counted under a Melee role")
  ChestAdvisorDB.role = {}
end
do
  ChestAdvisorDB.gearFor = "ret"
  local v, r, d, spec = judge(TOTALS)
  print("D. ret:      " .. tostring(v) .. "  " .. tostring(r))
  check(V.healingContext and V.healingContext(spec) == false, "D: Retribution is not a healing evaluation")
  check(arbCalls == 0 and not (type(d) == "table" and d.arbitration),
    "D: Retribution's weapon verdict never reaches the healer model")
  ChestAdvisorDB.gearFor = "holy"
end

-- ── E. no totals: the model is not asked ────────────────────────────────────
do
  local v, r = judge(nil)
  check(arbCalls == 0 and v == "TRADE_OFF" and r == PRE_SEAM,
    "E: with no totals the bytes are the pre-seam ones (got " .. tostring(r) .. ")")
end

-- ── F. SavedVariables: read, never written ──────────────────────────────────
do
  ChestAdvisorDB.context, ChestAdvisorDB.role, ChestAdvisorDB.gearFor = "leveling", {}, "holy"
  local after = snapshot(ChestAdvisorDB)
  local added = {}
  for k in pairs(after) do if svBefore[k] == nil then added[#added + 1] = k end end
  for k, x in pairs(svBefore) do
    check(after[k] == x, "F: ChestAdvisorDB." .. k .. " is unchanged")
  end
  check(#added == 0, "F: the seam adds no SavedVariables key (added: " .. table.concat(added, ", ") .. ")")
end

-- ── G. mutations ────────────────────────────────────────────────────────────
if os.getenv("TS_VERDICT_SRC") == nil then
  local lua = (arg and arg[-1]) or "lua5.1"
  local shipped = readFile(TOUCH .. "ChestAdvisor/Verdict.lua") or ""
  local MUTANTS = {
    { "the healing gate dropped",
      "and type(totals) == \"table\" and Verdict.healingContext(spec) then",
      "and type(totals) == \"table\" then" },
    { "the healing view keeps every word",
      "\t\t\t\tif keep[w] then\n", "\t\t\t\tif true then\n" },
    { "the recorded melee role ignored",
      "\tif spec.recordedRole == \"melee\" then return false end\n", "" },
    { "the decline sizes not printed",
      "\t\t\t\t\tif sized ~= nil and plain ~= nil and type(tr) == \"string\" then\n",
      "\t\t\t\t\tif false then\n" },
  }
  for _, m in ipairs(MUTANTS) do
    local s, e = shipped:find(m[2], 1, true)
    check(s ~= nil, "G: mutation anchor present: " .. m[1])
    if s ~= nil then
      local mutated = shipped:sub(1, s - 1) .. m[3] .. shipped:sub(e + 1)
      local path = os.tmpname()
      local f = io.open(path, "w"); f:write(mutated); f:close()
      local cmd = ("cd %q && TS_VERDICT_SRC=%q %s tests/touchstone_healer_weapon_spec.lua >/dev/null 2>&1")
        :format(root, path, lua)
      local rc = os.execute(cmd)
      os.remove(path)
      local passed = (rc == 0 or rc == true)
      print(("G. mutant %-36s %s"):format(m[1], passed and "SURVIVED" or "killed"))
      check(not passed, "G: the spec fails on the mutant: " .. m[1])
    end
  end
end

print(("%d check(s), %d failed"):format(checks, failed))
if failed > 0 then os.exit(1) end

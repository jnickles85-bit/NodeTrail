-- The reader the pack SHIPS must be the reader the pin names (card t_24a4c8ea).
--
-- WHY THIS SPEC EXISTS. NodeTrail vendors StatForge at a pin and carries the
-- reader through tools/sync_touchstone.py. Every other spec in this repo drives
-- what the vendored copy HAPPENS to contain: a stale pin therefore reads green
-- as long as the pack is only compared with itself. This one measures the
-- behaviours the re-vendor to 30f3d32 exists for, on the PACK'S OWN tree, so a
-- pin that silently stops moving fails here:
--
--   * a SCHOOLED damage range reads (the operator's wand pair, +7.3 dps and
--     +1 spell power): the line used to suppress the whole pair as
--     "cannot classify: 12 - 22 Arcane Damage  Speed 1.50";
--   * an ON-HIT PROC no longer silences the weapon — the pair is judged and the
--     answer carries " (judged, with an unpriced on-hit effect)";
--   * an "of Healing" pair is PRICED — before card t_33dd248c (DD-2's re-cut)
--     two weapons that tied on damage per second were called "equal weapon
--     damage per second" while one of them carried +34 Healing. The word is
--     priced out of the vendored Weights.lua, so this leg also proves the pack
--     actually ships that file: a reader with no weights source parses the
--     stats and still calls the pair equal (measured in leg 4).
--
-- The three verdict tokens the ledger's summary strip buckets on
-- (UPGRADE / TRADE_OFF / NOT_UPGRADE) are unchanged by all of this, and leg 5
-- proves the reader still emits all three.
--
-- Run from the repo root:  lua5.1 tests/touchstone_reader_pin_spec.lua

local here = (arg and arg[0] or "tests/touchstone_reader_pin_spec.lua"):match("^(.*)[/\\][^/\\]*$") or "."
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

-- ---- 1. The pin the pack claims to carry ------------------------------------
local syncPath = root .. "/tools/sync_touchstone.py"
local sf = io.open(syncPath, "r")
check(sf ~= nil, "tools/sync_touchstone.py is readable")
local PIN = "30f3d3263c1ce1556122c107beb9c10a9d2db6b7"  -- StatForge "Merge pull request #94"
if sf then
  local src = sf:read("*a")
  sf:close()
  local ref = src:match('SOURCE_REF%s*=%s*"([^"]+)"')
  check(ref == PIN,
    ("SOURCE_REF is the 30f3d32 pin this spec measured (%s), got %s")
      :format(PIN, tostring(ref)))
  check(src:find('"Weights.lua"', 1, true) ~= nil,
    "Weights.lua is in LUA_FILES — the weights the priced legs below need are vendored, not assumed")
end

local toc = io.open(root .. "/MightiePack/MightiePack.toc", "r")
check(toc ~= nil, "MightiePack.toc is readable")
if toc then
  local body = toc:read("*a")
  toc:close()
  check(body:find("Modules/Touchstone/Weights.lua", 1, true) ~= nil,
    "the TOC loads Weights.lua")
end

-- ---- 2. The reader, loaded the way the client loads it ---------------------
-- Constants.lua creates `StatForge`, Weights.lua writes `StatForge.Weights`,
-- Verdict.lua probes that table at CALL time. Same order as the TOC block.
local files = { "Constants.lua", "Weights.lua", "ChestAdvisor/Verdict.lua" }
for _, name in ipairs(files) do
  local chunk, err = loadfile(TOUCH .. name)
  check(chunk ~= nil, "loadfile " .. name .. ": " .. tostring(err))
  if chunk then
    local ok, runErr = pcall(chunk, "MightiePack", { Print = function() end })
    check(ok, "load " .. name .. ": " .. tostring(runErr))
  end
end
local V = rawget(_G, "Verdict")
check(type(V) == "table", "Verdict.lua loads and returns the module")
local SF = rawget(_G, "StatForge")
check(type(SF) == "table" and type(SF.Weights) == "table",
  "StatForge.Weights is installed by the vendored Weights.lua")
if type(V) ~= "table" then
  io.stderr:write("FAIL: the vendored reader did not load; nothing further can be measured\n")
  os.exit(1)
end

local function judge(cand, worn, spec)
  return V.compareWeapon(cand, worn, true, spec, true)
end

local function statsOf(lines)
  local t = V.statTable(lines, "candidate") or {}
  local keys = {}
  for k, v in pairs(t) do keys[#keys + 1] = k .. "=" .. tostring(v) end
  table.sort(keys)
  return table.concat(keys, ",")
end

-- Specs as the advisor builds them. PRIEST_HEAL is the owner's healer reading;
-- PRIEST is the class's own role word (the wand is judged for it).
local PRIEST = { class = "PRIEST", role = "PRIEST", order = { "Intellect", "Spirit", "Stamina" } }
local PRIEST_HEAL = { class = "PRIEST", role = "spell", clientRole = "HEALER",
  order = { "Intellect", "Spirit", "Stamina" } }
local WARRIOR = { class = "WARRIOR", role = "WARRIOR", order = { "Strength", "Stamina", "Agility" } }

-- ---- fixtures, line for line as the cards quote them -----------------------
local LESSER_WAND = { "Lesser Magic Wand", "Binds when equipped", "Ranged  Wand",
  "12 - 22 Arcane Damage  Speed 1.50", "(11.3 damage per second)",
  "Equip: Increases damage and healing done by magical spells and effects by up to 1.",
  "Durability 35 / 35", "Requires Level 5", "Sell Price: 1s 10c" }
local NOVICE_WAND = { "Novice's Practice Wand", "Binds when equipped", "Ranged  Wand",
  "3 - 9 Arcane Damage  Speed 1.50", "(4.0 damage per second)",
  "Durability 20 / 20", "Requires Level 3" }

local PROC = "Chance on hit: Sear the target with a vortex of blazing wind, dealing 39 to 59 Holystorm damage."
local POLE = { "Fishing Pole", "Two-Hand  Fishing Pole", "17 - 32 Damage  Speed 3.00",
  "(8.2 damage per second)", PROC }
local PLAIN_POLE = { "Plain Pole", "Two-Hand  Fishing Pole", "10 - 19 Damage  Speed 3.00",
  "(4.8 damage per second)" }

local HEAL_TWO = "Equip: Increases healing done by up to 34 and damage done by up to 11 for all magical spells and effects"
local ZWEI = { "Polished ZweiHander of Healing", "Two-Hand  Sword",
  "20 - 37 Damage  Speed 3.00", "(9.5 damage per second)", HEAL_TWO }
local PLAIN_ZWEI = { "Plain ZweiHander", "Two-Hand  Sword",
  "20 - 37 Damage  Speed 3.00", "(9.5 damage per second)" }

-- ---- 3. A schooled damage range READS -------------------------------------
local wv, wr = judge(LESSER_WAND, NOVICE_WAND, PRIEST)
check(wv == "UPGRADE",
  "the wand pair is a clean caster upgrade; got " .. tostring(wv) .. " | " .. tostring(wr))
check(wr == "upgrade: more weapon damage per second (11.30 vs 4.00)",
  "the reason names the printed damage per second on both sides; got " .. tostring(wr))
check(statsOf(LESSER_WAND):find("SpellPower=1", 1, true) ~= nil,
  "the wand's own \"+1 spell power\" sentence is READ, not suppressed: " .. statsOf(LESSER_WAND))

-- ---- 4. An on-hit proc is NAMED, not fatal --------------------------------
local pv, pr = judge(POLE, PLAIN_POLE, WARRIOR)
check(pv == "UPGRADE", "the proc weapon is still judged; got " .. tostring(pv) .. " | " .. tostring(pr))
check(type(pr) == "string" and pr:find(" (judged, with an unpriced on-hit effect)", 1, true) ~= nil,
  "the answer carries the on-hit clause; got " .. tostring(pr))
check(type(pr) == "string" and pr:find("^upgrade: more weapon damage per second", 1) ~= nil,
  "and it is still the dps reason underneath; got " .. tostring(pr))
-- The control: no proc, no clause. The clause must mean something.
local NO_PROC = { "Fishing Pole", "Two-Hand  Fishing Pole", "17 - 32 Damage  Speed 3.00",
  "(8.2 damage per second)" }
local _, npReason = judge(NO_PROC, PLAIN_POLE, WARRIOR)
check(type(npReason) == "string" and npReason:find("on-hit", 1, true) == nil,
  "without a proc line the clause is absent; got " .. tostring(npReason))
check(pr == tostring(npReason) .. " (judged, with an unpriced on-hit effect)",
  "the proc line changes nothing but the clause (got " .. tostring(pr)
    .. " vs " .. tostring(npReason) .. ")")

-- ---- 5. The "of Healing" pair is PARSED as two words, then PRICED ---------
local two = statsOf(ZWEI)
check(two:find("Healing=34", 1, true) ~= nil and two:find("SpellDamage=11", 1, true) ~= nil,
  "the combined sentence is two words with their own numbers, never averaged or summed: " .. two)
check(two:find("Healing=45", 1, true) == nil and two:find("SpellDamage=34", 1, true) == nil,
  "neither number is summed or moved to the other word: " .. two)

-- The pack's weights are what make this a PRICED verdict, so this leg is also
-- the anti-rot leg: with the table removed the same pair reads "equal".
local hv, hr = judge(ZWEI, PLAIN_ZWEI, PRIEST_HEAL)
check(hv == "UPGRADE",
  "a +34 Healing weapon is an upgrade for a healer, not level; got "
    .. tostring(hv) .. " | " .. tostring(hr))
check(hr == "upgrade: better on Healing",
  "the reason names the word the pack priced; got " .. tostring(hr))

local rv, rr = judge(PLAIN_ZWEI, ZWEI, PRIEST_HEAL)
check(rv == "NOT_UPGRADE", "the reverse is the mirror; got " .. tostring(rv) .. " | " .. tostring(rr))
check(rr == "worse on Healing than what's equipped",
  "and it names the same priced word; got " .. tostring(rr))

-- The delta line the player reads: both numbers, attributed.
local dcand = V.statTable(ZWEI, "candidate")
local dworn = V.statTable(PLAIN_ZWEI, "worn")
local deltaText = V.deltaText(V.statDeltas(dcand, dworn, PRIEST_HEAL.order), 4)
check(deltaText:find("+34 Healing", 1, true) ~= nil and deltaText:find("+11 Spell Damage", 1, true) ~= nil,
  "the pair's deltas are shown separately and attributed; got " .. tostring(deltaText))

-- THE PARITY LEG. Remove the weights source and the SAME pair loses its
-- verdict — which is exactly what a pack that ships the reader without
-- Weights.lua looks like from the client's chair.
local saved = SF.Weights
SF.Weights = nil
local ov, orr = judge(ZWEI, PLAIN_ZWEI, PRIEST_HEAL)
SF.Weights = saved
check(ov == "NOT_UPGRADE" and type(orr) == "string" and orr:find("equal weapon damage per second", 1, true) ~= nil,
  "without a weights table the pair falls back to the DPS tie (the defect this pin closes); got "
    .. tostring(ov) .. " | " .. tostring(orr))
local backv, backr = judge(ZWEI, PLAIN_ZWEI, PRIEST_HEAL)
check(backv == "UPGRADE" and backr == "upgrade: better on Healing",
  "restoring the table restores the priced verdict; got " .. tostring(backv) .. " | " .. tostring(backr))

-- ---- 6. The order-only pack's weapon judgement survives the re-pin --------
-- A profile that publishes a TIER LIST (Retribution) judges a weapon on it:
-- Weapon Skill first. The DPS comparator alone would call the pair below
-- "equal weapon damage per second (10.00)" across a +12 Weapon Skill gain —
-- measured on the 30f3d32 tree before the patch branch was re-anchored, which
-- is why this leg exists: the re-cut must carry that branch, not drop it.
local RET_SPEC = { class = "PALADIN", role = "melee", clientRole = "DAMAGER",
  order = V.classRoleOrder("PALADIN", "melee"), level = 60 }
local SKILL_CAND = { "Axe A", "Two-Hand  Sword", "20 - 40 Damage  Speed 3.00",
  "(10.0 damage per second)", "12 Weapon Skill" }
local SKILL_WORN = { "Axe B", "Two-Hand  Sword", "20 - 40 Damage  Speed 3.00",
  "(10.0 damage per second)" }
local kv, kr = V.compareWeapon(SKILL_CAND, SKILL_WORN, true, RET_SPEC, true)
check(kv == "UPGRADE",
  "a +12 Weapon Skill weapon at equal dps is an upgrade for Retribution; got "
    .. tostring(kv) .. " | " .. tostring(kr))
check(type(kr) == "string" and kr:find("Weapon Skill", 1, true) ~= nil,
  "and the reason names the tier that decided; got " .. tostring(kr))
-- The same branch must still carry #93's procurement doctrine: a proc weapon is
-- judged, with the clause — and an unplaceable line still refuses by name.
local kv2, kr2 = V.compareWeapon(
  { "Axe C", "Two-Hand  Sword", "30 - 60 Damage  Speed 3.00", "(15.0 damage per second)", PROC },
  SKILL_WORN, true, RET_SPEC, true)
check(kv2 == "UPGRADE" and type(kr2) == "string"
  and kr2:find(" (judged, with an unpriced on-hit effect)", 1, true) ~= nil,
  "an order-profile proc weapon is judged and carries the clause; got "
    .. tostring(kv2) .. " | " .. tostring(kr2))
local kv3, kr3 = V.compareWeapon(
  { "Axe D", "Two-Hand  Sword", "30 - 60 Damage  Speed 3.00", "(15.0 damage per second)", "+7 Bananas" },
  SKILL_WORN, true, RET_SPEC, true)
check(kv3 == "UNKNOWN" and kr3 == "cannot classify: Bananas",
  "an order-profile pair still fails closed BY NAME on an unplaceable line; got "
    .. tostring(kv3) .. " | " .. tostring(kr3))

-- ---- 7. The tokens the summary strip counts are unchanged -----------------
-- window_summary_strip_spec buckets on these three strings. All three still
-- come out of the reader at this pin:
local tv, tr = V.evaluate({ canUse = true, line = { "X", "Back", "10 Armor", "+1 Agility" } },
  { line = { "Y", "Back", "500 Armor", "+10 Stamina" } }, RET_SPEC, nil)
check(tv == "TRADE_OFF",
  "a one-sided Agility gain against a Stamina loss is still a TRADE_OFF; got "
    .. tostring(tv) .. " | " .. tostring(tr))
check(wv == "UPGRADE", "UPGRADE is still emitted (the wand pair above)")
check(rv == "NOT_UPGRADE", "NOT_UPGRADE is still emitted (the reverse healing pair above)")

if failed > 0 then
  io.stderr:write(("%d check(s) failed\n"):format(failed))
  os.exit(1)
end
print("ok")

-- herb_fold_idempotent_spec.lua — t_a5de2f16, review items 1 and 2.
--
-- Two folds that both over-count a lifetime map total. Each case below is RED
-- on e9aaeb1d and green after the fix; the pair is written so the fix cannot
-- pass by simply refusing to count appends (11m of herb_history_cap_spec still
-- requires a genuinely new clock-rollback pick to reach mapTotals).
--
--   1. An UNTIMED record carrying a crash stamp (aggFolded) must not trip
--      anyAggFolded. A record with no `t` says nothing about the cap, so it
--      must not disable the pre-#29 backfill — today it does, and the two
--      picks sharing the newest second are applied a second time: mapTotals
--      3 becomes 5.
--
--   2. Appending an ALREADY-COUNTED older pick after the watermark (a
--      downgrade that re-attaches its copies at the end instead of the front)
--      over-counts the same way: 3 becomes 5. The front re-attach is
--      idempotent because the watermark skips it; the append must be
--      idempotent because the pick is already in the counted prefix. A
--      genuinely NEW older pick (distinct second or position) must still be
--      applied — herb_history_cap_spec 11m pins that.
--
-- Every number is read from the real ns.GetHerbDB() -> ns.UpgradeHerbDB fold,
-- never from a copy of its arithmetic.

local failed = 0
local function check(cond, msg)
  if not cond then
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
    failed = failed + 1
  end
end

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

CopyTable = function(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = CopyTable(v) end
  return r
end

time = function() return 1700000000 end
GetTime = function() return 0 end
CreateFrame = function()
  return { SetScript = function() end, RegisterEvent = function() end }
end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}

local function loadFile(pkg, path)
  local chunk = assert(loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. path))
  chunk("MightiePack", pkg)
end

local pkg = {}
for _, f in ipairs({
  "locale/enUS.lua",
  "Config.lua",
  "Data/ItemNames.lua",
  "Data/HerbData.lua",
  "Data/Recorder.lua",
  "Data/Density.lua",
}) do
  loadFile(pkg, f)
end
local ns = pkg.NodeTrail
assert(type(ns) == "table" and type(ns.GetHerbDB) == "function", "Recorder loaded")

local PEACE = 2447
local MAP_A = 1429
-- Two picks can share a second; they must differ in position, because the
-- append fix reads identity off (t, x, y). These are exactly the coordinates
-- herb_history_cap_spec builds.
local X1, X2, X3 = 0.10, 0.11, 0.12

local function pick(t, x)
  return {
    x = x or X1, y = 0.10, t = t,
    items = { { id = PEACE, name = "Peacebloom", count = 1 } },
  }
end

-- The aggregate fixtures start from a counted save and are then loaded by the
-- real upgrade path.
local function base(list, mapTotals, folded)
  return {
    schema = 2,
    total = mapTotals,
    maps = { [MAP_A] = list },
    mapTotals = { [MAP_A] = mapTotals },
    stats = { gathers = { [PEACE] = mapTotals }, co = {}, names = { [PEACE] = "Peacebloom" } },
    hotspots = {},
    folded = { [MAP_A] = folded },
  }
end

local function load(db)
  NodeTrailDB = { herbs = db }
  ns.GetHerbDB()
  return db
end

-- ── 1. an untimed crash stamp must not disable the backfill ───────────────
-- A pre-#29 schema-2 save: aggT set, no aggTN, no marks. Two of the three
-- picks share the newest second. Appending one UNTIMED stamped record (the
-- shape a mid-loop crash leaves on an untimed list) must change nothing.
local untimed = base(
  { pick(1000), pick(2000, X1), pick(2000, X2), pick(nil, X3) },
  3,
  { aggT = 2000, hsT = 0, n = 0 }
)
untimed.maps[MAP_A][4].aggFolded = true
load(untimed)
check(untimed.mapTotals[MAP_A] == 3,
  "1: an untimed mark does not disable the backfill (mapTotals " ..
  tostring(untimed.mapTotals[MAP_A]) .. ", expected 3)")
check(untimed.total == 3,
  "1: lifetime total stays 3 (got " .. tostring(untimed.total) .. ")")
check(untimed.folded[MAP_A].aggTN == 2,
  "1: the backfill still counts the two picks at aggT (aggTN " ..
  tostring(untimed.folded[MAP_A].aggTN) .. ", expected 2)")
check(untimed.stats.gathers[PEACE] == 3,
  "1: drop-rate stats are not double-applied (gathers " ..
  tostring(untimed.stats.gathers[PEACE]) .. ", expected 3)")

-- A timed mark AT the cap is still evidence the fold already ran: the
-- sibling at the same second must apply exactly once (herb_history_cap_spec
-- 11j/11l), so the fix must not simply ignore every mark.
local timedMark = base(
  { pick(1000), pick(2000, X1), pick(2000, X2) },
  2,
  { aggT = 2000, aggTN = 1, hsT = 0, n = 0 }
)
timedMark.maps[MAP_A][2].aggFolded = true
load(timedMark)
check(timedMark.mapTotals[MAP_A] == 3,
  "1: a mark at the cap still gates the backfill and the sibling applies once (mapTotals " ..
  tostring(timedMark.mapTotals[MAP_A]) .. ", expected 3)")

-- ── 2. an appended already-counted older pick is idempotent ───────────────
-- Three distinct counted picks, then the trimmed copies re-attached at the
-- END of the list. mapTotals already covers them; applying them again is the
-- 3 -> 5 over-count.
--
-- The copies are strictly OLDER than the watermark. A copy sitting AT the
-- watermark second is indistinguishable from a same-second sibling, and
-- herb_history_cap_spec 11l requires that sibling to count — so the fix
-- cannot and must not claim that case.
local reattach = base(
  { pick(500, 0.20), pick(900, 0.30), pick(2000, X1), pick(500, 0.20), pick(900, 0.30) },
  3,
  { aggT = 2000, aggTN = 1, hsT = 0, n = 0 }
)
load(reattach)
check(reattach.mapTotals[MAP_A] == 3,
  "2: re-appended counted picks do not over-count (mapTotals " ..
  tostring(reattach.mapTotals[MAP_A]) .. ", expected 3)")
check(reattach.total == 3,
  "2: lifetime total stays 3 (got " .. tostring(reattach.total) .. ")")
check(reattach.stats.gathers[PEACE] == 3,
  "2: drop-rate stats stay at 3 (got " ..
  tostring(reattach.stats.gathers[PEACE]) .. ")")

-- A second load must not change anything either: the append fix is a skip,
-- not a stamp that vanishes into a later re-count.
local before = reattach.mapTotals[MAP_A]
load(reattach)
check(reattach.mapTotals[MAP_A] == before,
  "2: a second load is idempotent (mapTotals " ..
  tostring(reattach.mapTotals[MAP_A]) .. ", expected " .. tostring(before) .. ")")

-- A genuinely NEW older pick (the clock went backwards after the watermark)
-- must still reach mapTotals — herb_history_cap_spec 11m. Two of them, at
-- distinct positions, are two picks.
local rollback = base(
  { pick(1000), pick(2000, X1), pick(2000, X2), pick(500, X3), pick(400, 0.30) },
  3,
  { aggT = 2000, aggTN = 2, hsT = 0, n = 0 }
)
load(rollback)
check(rollback.mapTotals[MAP_A] == 5,
  "2: two genuinely new rollback picks still count (mapTotals " ..
  tostring(rollback.mapTotals[MAP_A]) .. ", expected 5)")
local rollbackAgain = rollback.mapTotals[MAP_A]
load(rollback)
check(rollback.mapTotals[MAP_A] == rollbackAgain,
  "2: the rollback picks are not re-applied on a second load (mapTotals " ..
  tostring(rollback.mapTotals[MAP_A]) .. ", expected " .. tostring(rollbackAgain) .. ")")

if failed == 0 then
  print("herb_fold_idempotent_spec: ok")
else
  os.exit(1)
end

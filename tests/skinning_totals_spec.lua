-- skinning_totals_spec.lua — t_e3ea3698 (per-creature totals that never evict).
--
-- The defect, measured on Mightie's own desktop bucket: kills = 1125,
-- corpse windows = 641, records = 100. The recorder keeps a ring of the newest
-- R.MAX_RECORDS = 100 corpses per character, and every user-facing number used
-- to be aggregated by walking that ring (Data/SkinHints.lua), so 541 corpses'
-- worth of history was gone and a beast skinned dozens of times printed
-- "no observations here yet".
--
-- This spec measures that defect through the REAL entry points, with no
-- hand-written store shape and no re-implementation of the aggregation:
--
--   1. a creature's history survives 200 later corpses of another creature:
--      its own record set is fully evicted, its TOTALS are not;
--   2. 300 recorded kills of one creature still show its totals and its
--      skinned count while the ring holds at most 100;
--   3. the item counts are quantities and corpse counts, not read counts: a
--      loot window re-read three times, and a late read that grows a stack
--      from 1 to 3, leaves count = 3 and seen = 1;
--   4. the ring is still ROUTE data — every field Route/SkinRoute reads is
--      still on the newest 100 records, and the circle it builds from them is
--      the same closed circuit;
--   5. corpse loot never enters the skinning numbers;
--   6. a creature we genuinely have no observation for still says
--      "no observations here yet";
--   7. the store declares schema 2 and carries the totals table.
--
-- RED before the change: the totals table does not exist, so section 1 reports
-- `records == 0`, section 2 reports the ring's 100 instead of 300, and the
-- item counts are the newest 100 corpses' worth. Every check below is written
-- to report that as a FAILED check rather than a traceback.
local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

-- ── the client ──────────────────────────────────────────────────────────
local clock = 100
GetTime = function() return clock end
GetUnitName = function(u) if u == "player" then return "Mightie" end return nil end
GetRealmName = function() return "Forever" end

-- The sub-toggle ON, so the recorder persists into the character bucket the
-- beast panel reads (NodeTrail owns that key; this spec sets it directly).
NodeTrailDB = { skinning = { enabled = true } }

-- ── load (the addon's own order: NodeTrail first, Skinning after) ────────
local pkg = {}
local function loadFile(path)
  local chunk, err = loadfile(root .. "/MightiePack/" .. path)
  check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
  if not chunk then return false end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. path .. ": " .. tostring(e))
  return ok
end

loadFile("Modules/NodeTrail/Route/Cluster.lua")
loadFile("Modules/NodeTrail/Route/Build.lua")
loadFile("Modules/NodeTrail/Route/SkinRoute.lua")
loadFile("Modules/NodeTrail/Data/SkinHints.lua")
loadFile("Modules/Skinning/Record.lua")

local ns = type(pkg.NodeTrail) == "table" and pkg.NodeTrail or {}
local H = ns.SkinHints
local S = ns.SkinRoute
local R = type(pkg.Skinning) == "table" and pkg.Skinning.Recorder or nil

check(type(H) == "table" and type(H.Aggregate) == "function",
  "0: Data/SkinHints.lua loaded (the beast panel's aggregator)")
check(type(S) == "table" and type(ns.BuildSkinRouteForMap) == "function",
  "0: Route/SkinRoute.lua loaded (the circle's generator)")
check(type(R) == "table" and type(R.OnKill) == "function",
  "0: the skinning recorder is loaded (this spec drives the real one)")

-- ── records, built by calling the real recorder ─────────────────────────
-- Each corpse: a unique GUID (the creature entry is the second-to-last field,
-- which is what R.CreatureID parses), a death with a map position, an optional
-- corpse window, a successful 8613 cast and an optional skin window.
local seq = 0
local CLUSTERS = { { 0.18, 0.22 }, { 0.62, 0.20 }, { 0.58, 0.66 }, { 0.16, 0.68 } }

local function position(i)
  local c = CLUSTERS[(i - 1) % #CLUSTERS + 1]
  return c[1] + ((i - 1) % 3) * 0.004, c[2] + ((i - 1) % 2) * 0.003
end

local function observe(cid, skinItems, corpseItems)
  seq = seq + 1
  local guid = ("Creature-0-7072-1-48-%d-%012X"):format(cid, seq)
  local x, y = position(seq)
  local t = 1000 + seq
  R:OnKill({ guid = guid, t = t, map = 1411, x = x, y = y, zone = "Desolace" })
  if corpseItems then
    R:OnCorpseLoot({ guid = guid, t = t + 0.1, items = corpseItems })
  end
  if skinItems then
    R:OnSkinCast({ guid = guid, t = t + 0.2, spellID = 8613 })
    R:OnSkinLoot({ guid = guid, t = t + 0.3, items = skinItems })
  end
  return guid, x, y
end

local function ringSize(store)
  local n = 0
  for _ in pairs(store.records or {}) do n = n + 1 end
  return n
end

local function rowHas(rows, text)
  for _, r in ipairs(rows or {}) do
    if r.left == text then return true end
  end
  return false
end

local function rowLeftStarts(rows, text)
  for _, r in ipairs(rows or {}) do
    if type(r.left) == "string" and r.left:sub(1, #text) == text then return r end
  end
  return nil
end

local function anyRight(rows)
  local out = {}
  for _, r in ipairs(rows or {}) do
    if r.right then out[#out + 1] = r.right end
  end
  return out
end

local function skinItem(agg, id)
  for _, it in ipairs((type(agg) == "table" and agg.skin) or {}) do
    if it.itemID == id then return it end
  end
  return nil
end

local A_CID = 3124   -- the creature whose history is about to be evicted
local B_CID = 3125   -- the crowd that evicts it
local C_CID = 3126   -- the 300-kill creature
local A_SKIN = { { id = 2934, name = "Ruined Leather Scraps", qty = 1 } }
local A_CORPSE = { { id = 7100, name = "Scorpid Blood", qty = 1 } }
local B_SKIN = { { id = 2319, name = "Medium Leather", qty = 1 } }
local C_SKIN = { { id = 4306, name = "Silk Cloth", qty = 1 } }

local store = select(1, R:Store())
check(type(store) == "table", "0: the recorder has an active store")

-- ════════════════════════════════════════════════════════════════════════
-- 1. History survives the ring: 5 corpses, then 200 corpses behind them
-- ════════════════════════════════════════════════════════════════════════
local aFirst
for i = 1, 5 do
  local guid = observe(A_CID, A_SKIN, A_CORPSE)
  if i == 1 then aFirst = guid end
end
for _ = 1, 200 do
  observe(B_CID, B_SKIN, A_CORPSE)
end

check(#store.order <= R.MAX_RECORDS,
  "1: the ring holds at most " .. tostring(R.MAX_RECORDS) .. " records (got "
  .. tostring(#store.order) .. ")")
check(store.records[aFirst] == nil,
  "1: the creature's first corpse IS evicted from the ring (the defect's cause)")

local aggA = H.Aggregate(A_CID)
check(type(aggA) == "table", "1: the aggregate still answers for an evicted creature")
if type(aggA) == "table" then
  check(aggA.records == 5,
    "1: all 5 of its corpses are still counted (got " .. tostring(aggA.records) .. ")")
  check(aggA.kills == 5, "1: kills are still counted (got " .. tostring(aggA.kills) .. ")")
  check(aggA.skinned == 5, "1: skinned is still counted (got " .. tostring(aggA.skinned) .. ")")
  check(aggA.skinWindows == 5,
    "1: its skin windows are still counted (got " .. tostring(aggA.skinWindows) .. ")")
  local hides = skinItem(aggA, 2934) or {}
  check(hides.count == 5,
    "1: its skin item count survives the eviction (got " .. tostring(hides.count) .. ")")
  check(hides.seen == 5,
    "1: its corpse count for the item survives too (got " .. tostring(hides.seen) .. ")")
end

local rowsA = H.Rows(A_CID, "Scorched Beast")
check(rowHas(rowsA, "skinned: 5"),
  "1: the panel still states its totals (rows: " .. tostring(table.concat(anyRight(rowsA), "/")) .. ")")
check(rowLeftStarts(rowsA, "Ruined Leather Scraps x5") ~= nil,
  "1: the panel still lists what skinning gave")
check(#anyRight(rowsA) == 0,
  "1: 5 corpses are below the evidence floor, so no percentage is printed (got "
  .. tostring(table.concat(anyRight(rowsA), "/")) .. ")")

-- ════════════════════════════════════════════════════════════════════════
-- 2. 300 recorded kills of ONE creature: totals stay, the ring does not
-- ════════════════════════════════════════════════════════════════════════
for _ = 1, 300 do
  observe(C_CID, C_SKIN, nil)
end

check(ringSize(store) <= R.MAX_RECORDS,
  "2: the ring still holds at most " .. tostring(R.MAX_RECORDS) .. " records (got "
  .. tostring(ringSize(store)) .. ")")
check(#store.order <= R.MAX_RECORDS,
  "2: the ring's own order list is capped too (got " .. tostring(#store.order) .. ")")

local aggC = H.Aggregate(C_CID)
check(type(aggC) == "table", "2: the aggregate answers after 300 kills")
if type(aggC) == "table" then
  check(aggC.records == 300,
    "2: 300 corpses are counted, not the 100 the ring can hold (got "
    .. tostring(aggC.records) .. ")")
  check(aggC.kills == 300,
    "2: 300 kills are counted (got " .. tostring(aggC.kills) .. ")")
  check(aggC.skinned == 300,
    "2: 300 skinned corpses are counted (got " .. tostring(aggC.skinned) .. ")")
  check(aggC.skinWindows == 300,
    "2: 300 skin windows are counted (got " .. tostring(aggC.skinWindows) .. ")")
  local silk = skinItem(aggC, 4306) or {}
  check(silk.count == 300,
    "2: the item count is every corpse's yield (got " .. tostring(silk.count) .. ")")
  check(silk.seen == 300,
    "2: the denominator is every corpse that carried it (got " .. tostring(silk.seen) .. ")")
end

local rowsC = H.Rows(C_CID, "Dustwallow Beast")
check(rowHas(rowsC, "skinned: 300"),
  "2: hovering the creature still shows its totals (got: "
  .. tostring(table.concat(anyRight(rowsC), "/")) .. ")")
local silkRow = rowLeftStarts(rowsC, "Silk Cloth x300")
check(silkRow ~= nil, "2: hovering it still shows what skinning gave")
check(silkRow and silkRow.right == "100% (yours)",
  "2: 300 corpses clear the evidence floor, so the row carries a percentage (got "
  .. tostring(silkRow and silkRow.right) .. ")")

-- and the creature from section 1 is STILL intact, 500 corpses later
local aggA2 = H.Aggregate(A_CID)
check(type(aggA2) == "table" and aggA2.kills == 5 and aggA2.skinned == 5,
  "2: a creature 500 corpses back still reports its totals (got kills="
  .. tostring(type(aggA2) == "table" and aggA2.kills) .. ")")

-- ════════════════════════════════════════════════════════════════════════
-- 3. Counts are quantities and corpses, never reads
-- ════════════════════════════════════════════════════════════════════════
local D_CID = 3127
local dGuid = observe(D_CID, { { id = 8170, name = "Rugged Leather", qty = 1 } })
-- The client fills a loot window late: every re-read REPLACES that window's
-- snapshot, and a late read can only grow it (live: LOOT_OPENED "i=-").
R:SetWindowItems(dGuid, "skin", { { id = 8170, name = "Rugged Leather", qty = 3 } }, nil, 2000)
R:SetWindowItems(dGuid, "skin", { { id = 8170, name = "Rugged Leather", qty = 3 } }, nil, 2001)
local aggD = H.Aggregate(D_CID)
local rugged = skinItem(aggD, 8170) or {}
check(rugged.count == 3,
  "3: a re-read window is not counted three times (count, got " .. tostring(rugged.count) .. ")")
check(rugged.seen == 1,
  "3: one corpse carried it, however often the window was read (seen, got "
  .. tostring(rugged.seen) .. ")")

-- ════════════════════════════════════════════════════════════════════════
-- 4. The ring is ROUTE data: SkinRoute reads the same loop it always did
-- ════════════════════════════════════════════════════════════════════════
local stripped = 0
for _, rec in pairs(store.records) do
  if rec.skinned == true
    and (rec.map == nil or type(rec.x) ~= "number" or type(rec.y) ~= "number") then
    stripped = stripped + 1
  end
end
check(stripped == 0,
  "4: every skinned ring record still carries map + x + y (" .. stripped .. " missing them)")

local expectedPoints = 0
for _, rec in pairs(store.records) do
  if rec.skinned == true and rec.map == 1411
    and type(rec.x) == "number" and rec.x >= 0 and rec.x <= 1
    and type(rec.y) == "number" and rec.y >= 0 and rec.y <= 1 then
    expectedPoints = expectedPoints + 1
  end
end
local points = S:SkinnedPoints(1411)
check(#points == expectedPoints,
  "4: the circle takes exactly the ring's skinned positions (got " .. #points
  .. ", the ring holds " .. expectedPoints .. ")")
check(#points >= S.MIN_SKINS,
  "4: the ring still holds enough skinned corpses for a circle (got " .. #points .. ")")

local route, routeErr = ns.BuildSkinRouteForMap(1411)
check(route ~= nil, "4: the circle still builds from the ring (err="
  .. tostring(routeErr) .. ")")
if route then
  check(route.source == "skinning", "4: it is still the skinning route")
  check(#route.path >= 4, "4: it is still a closed loop (got " .. #route.path .. " points)")
  local first, last = route.path[1], route.path[#route.path]
  check(first and last and first.x == last.x and first.y == last.y,
    "4: the loop is still CLOSED")
  -- Every stop is a centroid of a live ring record's cell: the positions the
  -- circle draws are the ring's own, not invented.
  local onRing = 0
  for i = 1, #route.path do
    local p = route.path[i]
    for _, rec in pairs(store.records) do
      if math.abs((rec.x or -9) - p.x) < 0.02 and math.abs((rec.y or -9) - p.y) < 0.02 then
        onRing = onRing + 1
        break
      end
    end
  end
  check(onRing == #route.path,
    "4: every stop sits on a recorded position (" .. onRing .. "/" .. #route.path .. ")")
end

-- ════════════════════════════════════════════════════════════════════════
-- 5. Corpse loot never enters the skinning numbers
-- ════════════════════════════════════════════════════════════════════════
for _, cid in ipairs({ A_CID, B_CID, C_CID, D_CID }) do
  local agg = H.Aggregate(cid)
  check(skinItem(agg, 7100) == nil,
    "5: the corpse item 7100 is not in cid " .. cid .. "'s skinning totals")
end

-- ════════════════════════════════════════════════════════════════════════
-- 6. A creature we never saw still says so
-- ════════════════════════════════════════════════════════════════════════
local rowsU = H.Rows(9999, "Young Stranglethorn Tiger")
check(rowHas(rowsU, "no observations here yet"),
  "6: a creature with no observation still says so")
local aggU = H.Aggregate(9999)
check(type(aggU) == "table" and aggU.records == 0 and #aggU.skin == 0,
  "6: and its aggregate carries no invented numbers")

-- ════════════════════════════════════════════════════════════════════════
-- 7. The store says which schema it is
-- ════════════════════════════════════════════════════════════════════════
local key = "Mightie-Forever"
local bucket = NodeTrailDB.skinning and NodeTrailDB.skinning.chars
  and NodeTrailDB.skinning.chars[key]
check(type(bucket) == "table", "7: the character bucket exists at chars[" .. key .. "]")
check(R.SCHEMA == 2, "7: the recorder declares schema 2 (got " .. tostring(R.SCHEMA) .. ")")
check(bucket and bucket.schema == 2,
  "7: the bucket is stamped schema 2 (got " .. tostring(bucket and bucket.schema) .. ")")
check(bucket and type(bucket.creatures) == "table",
  "7: the bucket carries the per-creature totals table")
check(bucket and type(bucket.creatures) == "table"
  and type(bucket.creatures[C_CID]) == "table",
  "7: the 300-kill creature has its own totals row")

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("skinning_totals_spec: ok")

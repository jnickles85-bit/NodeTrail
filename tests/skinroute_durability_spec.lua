-- skinroute_durability_spec.lua — skinned positions survive ring turnover.
--
-- The 100-corpse ring used to be the only input to the farming circle.
-- Unskinned kills evicted older skins, and a route disappeared while the
-- per-creature totals were still intact. This file pins the fix:
--
--   1. evicting a skinned, positioned record folds it into the durable
--      per-map hotspot store (idempotent on guid);
--   2. unskinned records are evicted first, so a skinned position is
--      kept in the ring while unskinned kills are coming in;
--   3. a circle built from 12 spread-out skins still builds after 100
--      later unskinned kills (the skins stay in the ring); a full ring
--      of skins evicted by a later camp of 100 skins still builds from
--      the durable store;
--   4. a one-time migration folds the current ring's skinned positions
--      into the store without discarding the ring or double-counting;
--   5. more than 32 unique folds in one cell cap only the position
--      samples: a re-fold of #33 does not increment n, and
--      SkinnedPoints yields at most 32 points from that cell;
--   6. a crash after the fold but before the ring removal retries
--      without double-counting (fold first, then drop);
--   7. a skinned record evicted with no map position is counted per
--      map in unpositionedEvicted and is not folded;
--   8. a pre-seen save (hotspotsSeeded, pts present, seen missing) is
--      backfilled on load so a re-fold of those guids does not
--      increment n.
--
-- Not loaded by the addon TOC.
local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

GetTime = function() return 100 end
GetUnitName = function(u) if u == "player" then return "Mightie" end return nil end
GetRealmName = function() return "Forever" end

NodeTrailDB = { skinning = { enabled = true } }

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
loadFile("Modules/Skinning/Record.lua")

local ns = pkg.NodeTrail
local S = ns and ns.SkinRoute
local R = pkg.Skinning and pkg.Skinning.Recorder

check(type(R) == "table" and type(R.OnKill) == "function", "0: recorder loaded")
check(type(S) == "table" and type(ns.BuildSkinRouteForMap) == "function", "0: SkinRoute loaded")
check(type(R.HOTSPOT_CELL) == "number" and R.HOTSPOT_CELL == 0.02,
  "0: skin hotspots reuse the 2% cell size (got " .. tostring(R and R.HOTSPOT_CELL) .. ")")

local MAP = 1412
local seq = 0
-- Four camps so MIN_CLUSTERS (3) is satisfied.
local CAMPS = { { 0.20, 0.22 }, { 0.60, 0.24 }, { 0.62, 0.68 }, { 0.22, 0.70 } }

local function guid(cid, n)
  return ("Creature-0-7072-1-48-%d-%012X"):format(cid, n)
end

local function kill(cid, x, y, skin)
  seq = seq + 1
  local g = guid(cid, seq)
  local t = 2000 + seq
  R:OnKill({ guid = g, t = t, map = MAP, x = x, y = y, zone = "Mulgore" })
  if skin then
    R:OnSkinCast({ guid = g, t = t + 0.2, spellID = 8613 })
  end
  return g
end

local function store()
  return R:GetDB()
end

local function ringSkinned(st, mapID)
  local n = 0
  for _, rec in pairs(st.records or {}) do
    if rec.skinned == true and rec.map == mapID then n = n + 1 end
  end
  return n
end

local function hotspotPts(st, mapID)
  local n, cells = 0, 0
  local grid = st.hotspots and st.hotspots[mapID]
  if type(grid) ~= "table" then return 0, 0 end
  for _, cell in pairs(grid) do
    if type(cell) == "table" then
      cells = cells + 1
      n = n + (cell.n or 0)
    end
  end
  return n, cells
end

-- ── 1. eviction folds a skinned, positioned record ────────────────────
-- Fill the ring with 100 unskinned kills, then add one skinned one so
-- something must be evicted? Better: 100 skins, then unskinned will be
-- tested in 2. Here: add MAX_RECORDS skins, then one more skin at a new
-- guid, evicting the oldest skin into the grid.
local firstGuids = {}
for i = 1, R.MAX_RECORDS do
  local c = CAMPS[(i - 1) % #CAMPS + 1]
  firstGuids[i] = kill(2955, c[1], c[2], true)
end
local st = store()
check(#st.order == R.MAX_RECORDS, "1: ring is full after " .. R.MAX_RECORDS .. " skins")
-- GetDB stamps the migration on first open (an empty ring). Later skins
-- enter the durable store when they are evicted, not before.
check(st.hotspotsSeeded == true, "1: GetDB stamps the hotspot migration")
local seededN = hotspotPts(st, MAP)
check(seededN == 0, "1: nothing has been evicted yet, so the grid is still empty (n="
  .. tostring(seededN) .. ")")

-- One more skin evicts the oldest. That evicted record must be folded.
local extra = kill(2955, 0.21, 0.23, true)
st = store()
check(#st.order == R.MAX_RECORDS, "1: ring stays at the cap after another skin")
check(st.records[firstGuids[1]] == nil,
  "1: the oldest skinned record left the ring")
local afterN = hotspotPts(st, MAP)
check(afterN == 1,
  "1: the evicted skin was folded into the durable store (n=" .. tostring(afterN) .. ")")
-- Folding the same guid again is a no-op.
local evictedRec = { guid = firstGuids[1], skinned = true, map = MAP, x = 0.20, y = 0.22, creatureID = 2955 }
R.FoldSkinIntoHotspots(st, evictedRec)
check(hotspotPts(st, MAP) == afterN, "1: folding the same guid is idempotent")

local pts = S:SkinnedPoints(MAP)
check(#pts == R.MAX_RECORDS + 1,
  "1: SkinnedPoints unions the remaining ring and the folded skin, deduped (got "
    .. #pts .. ")")

-- ── 2. unskinned records are evicted first ────────────────────────────
-- Reset to a known store: 8 skins then 92 unskinned, ring is full of mixed.
NodeTrailDB = { skinning = { enabled = true } }
seq = 0
local keep = {}
for i = 1, 8 do
  local c = CAMPS[(i - 1) % #CAMPS + 1]
  keep[i] = kill(2966, c[1] + i * 0.001, c[2], true)
end
for i = 1, 92 do
  kill(2952, 0.40, 0.40, false)
end
st = store()
check(#st.order == R.MAX_RECORDS, "2: mixed ring is full")
for i = 1, 8 do
  check(st.records[keep[i]] ~= nil,
    "2: a skinned record is still in the ring while unskinned fills occupy the rest")
end
-- 10 more unskinned kills must evict unskinned, not the 8 skins.
for i = 1, 10 do
  kill(2952, 0.41, 0.41, false)
end
st = store()
check(#st.order == R.MAX_RECORDS, "2: ring stays at the cap")
local still = 0
for i = 1, 8 do
  if st.records[keep[i]] then still = still + 1 end
end
check(still == 8, "2: all 8 skins stayed in the ring after 10 more unskinned kills (kept "
  .. still .. ")")
check(ringSkinned(st, MAP) == 8, "2: the ring still reports 8 skinned on the map")

-- ── 3a. a short sample plus 100 unskinned kills (the in-game test) ────
-- Unskinned-first eviction keeps the skins in the ring; the circle must
-- still build. This is the case the original FIFO ring lost.
NodeTrailDB = { skinning = { enabled = true } }
seq = 0
-- 12 skins across 4 camps (3 per camp) — enough for MIN_SKINS and MIN_CLUSTERS.
for i = 1, 12 do
  local c = CAMPS[(i - 1) % #CAMPS + 1]
  kill(2966, c[1] + math.floor((i - 1) / 4) * 0.004, c[2], true)
end
st = store()
local route, err = ns.BuildSkinRouteForMap(MAP)
check(route ~= nil, "3a: the circle builds from 12 skins (err=" .. tostring(err) .. ")")
for i = 1, 100 do
  kill(2952, 0.50, 0.50, false)
end
st = store()
check(#st.order == R.MAX_RECORDS, "3a: the ring is still capped")
check(ringSkinned(st, MAP) == 12,
  "3a: unskinned-first eviction kept all 12 skins in the ring (got "
    .. ringSkinned(st, MAP) .. ")")
local pts3a = S:SkinnedPoints(MAP)
check(#pts3a >= 12, "3a: SkinnedPoints still sees the 12 skins (got " .. #pts3a .. ")")
local route2, err2 = ns.BuildSkinRouteForMap(MAP)
check(route2 ~= nil,
  "3a: the circle still builds after 100 unskinned kills (err=" .. tostring(err2) .. ")")
if route2 then
  check(route2.source == "skinning", "3a: it is still the skinning route")
  check(#route2.path >= 4, "3a: it is still a closed loop")
  local first, last = route2.path[1], route2.path[#route2.path]
  check(first and last and first.x == last.x and first.y == last.y, "3a: the loop is closed")
end

-- ── 3b. evicted skins still feed the circle from the durable store ────
-- Unskinned kills will not push a short sample out of the ring (3a).
-- A later cluster of 100 skins in a new camp will, once the ring is full.
-- Without the store, only the new camp would remain (one cluster) and
-- the circle would refuse MIN_CLUSTERS. With the store, the original
-- four camps still count.
NodeTrailDB = { skinning = { enabled = true } }
seq = 0
local original = {}
for i = 1, 12 do
  local c = CAMPS[(i - 1) % #CAMPS + 1]
  original[i] = { x = c[1] + math.floor((i - 1) / 4) * 0.004, y = c[2] }
  kill(2966, original[i].x, original[i].y, true)
end
st = store()
local routeFull, errFull = ns.BuildSkinRouteForMap(MAP)
check(routeFull ~= nil, "3b: the circle builds from the original 12 skins (err="
  .. tostring(errFull) .. ")")
local CAMP5X, CAMP5Y = 0.40, 0.45
for i = 1, 100 do
  kill(2966, CAMP5X, CAMP5Y, true)
end
st = store()
check(#st.order == R.MAX_RECORDS, "3b: the ring is still capped")
check(ringSkinned(st, MAP) == R.MAX_RECORDS,
  "3b: the ring is now the 100 skins at the new camp (got "
    .. ringSkinned(st, MAP) .. ")")
local durable, cells = hotspotPts(st, MAP)
check(durable == 12, "3b: the original 12 skins were folded into the store (n="
  .. tostring(durable) .. ", cells=" .. tostring(cells) .. ")")
local pts3b = S:SkinnedPoints(MAP)
check(#pts3b == 112, "3b: SkinnedPoints unions the store and the new ring (got "
  .. #pts3b .. ")")
-- Every original camp still has at least one point, so this is not just
-- the new camp.
local function nearCamp(px, py, camp)
  return math.abs(px - camp[1]) < 0.03 and math.abs(py - camp[2]) < 0.03
end
local seenCamp = { false, false, false, false }
for _, p in ipairs(pts3b) do
  for ci, c in ipairs(CAMPS) do
    if nearCamp(p.x, p.y, c) then seenCamp[ci] = true end
  end
end
local campsKept = 0
for i = 1, 4 do if seenCamp[i] then campsKept = campsKept + 1 end end
check(campsKept == 4, "3b: all four original camps are still in SkinnedPoints (kept "
  .. campsKept .. ")")
local route3, err3 = ns.BuildSkinRouteForMap(MAP)
check(route3 ~= nil,
  "3b: the circle still builds from the store plus the new camp (err="
    .. tostring(err3) .. ")")
if route3 then
  check(route3.source == "skinning", "3b: it is still the skinning route")
  check(#route3.path >= 4, "3b: it is still a closed loop")
  local first, last = route3.path[1], route3.path[#route3.path]
  check(first and last and first.x == last.x and first.y == last.y, "3b: the loop is closed")
end

-- ── 4. one-time migration folds the current ring, never discards ──────
-- Build a schema-2 bucket that looks like a pre-hotspot save: a ring of
-- skins, no hotspots, no seeded flag.
local saved = {
  schema = 2,
  records = {},
  order = {},
  unclassified = {},
  creatures = {},
  counts = { kills = 0, corpseWindows = 0, skinWindows = 0, skinCasts = 0, unattributedWindows = 0 },
}
for i = 1, 9 do
  local c = CAMPS[(i - 1) % #CAMPS + 1]
  local g = "Creature-0-1-1-1-2961-" .. string.format("%012X", i)
  saved.order[i] = g
  saved.records[g] = {
    guid = g, creatureID = 2961, skinned = true,
    map = MAP, x = c[1], y = c[2],
  }
end
-- One unskinned record stays in the ring and must not be folded.
local bare = "Creature-0-1-1-1-2952-000000000099"
saved.order[10] = bare
saved.records[bare] = { guid = bare, creatureID = 2952, skinned = false, map = MAP, x = 0.5, y = 0.5 }

local migrated = R:Upgrade(saved)
check(migrated.hotspotsSeeded == true, "4: Upgrade stamps the hotspot migration")
check(migrated.schema == 2, "4: schema is not rewritten away from 2")
check(#migrated.order == 10, "4: the ring is not discarded")
check(migrated.records[saved.order[1]] ~= nil, "4: ring records are still present")
local mn, mc = hotspotPts(migrated, MAP)
check(mn == 9, "4: all 9 skinned ring positions were folded (n=" .. tostring(mn) .. ")")
check(migrated.records[bare] ~= nil and migrated.records[bare].skinned ~= true,
  "4: the unskinned ring record is left in the ring, not invented as a skin")
-- A second Upgrade must not double-count.
R:Upgrade(saved)
check(hotspotPts(migrated, MAP) == 9, "4: a second Upgrade does not double-fold")

-- Upgrade of this bucket is what GetDB would do for a live save.
NodeTrailDB = { skinning = { enabled = true, chars = { ["Mightie-Forever"] = saved } } }
-- CharKey in this harness is Mightie-Forever.
local viaGet = R:GetDB()
check(viaGet.hotspotsSeeded == true, "4: GetDB is the migration entry point")
check(hotspotPts(viaGet, MAP) == 9, "4: GetDB does not fold a second time")
local pts4 = S:SkinnedPoints(MAP)
-- 9 skins from store + ring, deduped.
check(#pts4 == 9, "4: SkinnedPoints is 9 unique skins after migration (got " .. #pts4 .. ")")

-- ── 5. pts cap does not break guid idempotency ────────────────────────
local overflow = {
  schema = 2, records = {}, order = {}, unclassified = {},
  creatures = {}, counts = {}, hotspots = {}, hotspotsSeeded = true,
}
local overflowGuids = {}
for i = 1, 37 do
  overflowGuids[i] = "Creature-0-1-1-1-2966-" .. string.format("%012X", 200 + i)
  R.FoldSkinIntoHotspots(overflow, {
    guid = overflowGuids[i], creatureID = 2966, skinned = true,
    map = MAP, x = 0.30, y = 0.30,
  })
end
local oKey = R.SkinCellKey(0.30, 0.30)
local oCell = overflow.hotspots[MAP][oKey]
check(oCell and oCell.n == 37,
  "5: n counts every unique fold past the pts cap (n=" .. tostring(oCell and oCell.n) .. ")")
check(oCell and #oCell.pts == R.HOTSPOT_MAX_PTS,
  "5: pts is capped at " .. R.HOTSPOT_MAX_PTS .. " (got " .. tostring(oCell and #oCell.pts) .. ")")
check(oCell and oCell.seen and oCell.seen[overflowGuids[33]] == true,
  "5: guid 33 is in seen even though it missed the pts cap")
local nBefore, ptsBefore = oCell.n, #oCell.pts
R.FoldSkinIntoHotspots(overflow, {
  guid = overflowGuids[33], creatureID = 2966, skinned = true,
  map = MAP, x = 0.30, y = 0.30,
})
check(oCell.n == nBefore, "5: a re-fold of #33 does not increment n (got " .. tostring(oCell.n) .. ")")
check(#oCell.pts == ptsBefore, "5: a re-fold of #33 does not grow pts")
NodeTrailDB = { skinning = { enabled = true, chars = { ["Mightie-Forever"] = overflow } } }
local pts5 = S:SkinnedPoints(MAP)
check(#pts5 == R.HOTSPOT_MAX_PTS,
  "5: SkinnedPoints yields at most 32 points from one overfull cell (got " .. #pts5 .. ")")
local late = 0
for _, p in ipairs(pts5) do
  for i = 33, 37 do
    if p.guid == overflowGuids[i] then late = late + 1 end
  end
end
check(late == 0, "5: skins past the pts cap are not extra path points (got " .. late .. ")")

-- ── 6. crash after fold, before ring removal ─────────────────────────
local crashStore = {
  schema = 2, records = {}, order = {}, unclassified = {},
  creatures = {}, counts = {}, hotspots = {}, hotspotsSeeded = true,
}
for i = 1, R.MAX_RECORDS + 1 do
  local g = "Creature-0-9-1-1-2966-" .. string.format("%012X", i)
  crashStore.order[i] = g
  crashStore.records[g] = {
    guid = g, creatureID = 2966, skinned = true,
    map = MAP, x = 0.11, y = 0.12,
  }
end
local first = crashStore.order[1]
R.FoldSkinIntoHotspots(crashStore, crashStore.records[first])
check(hotspotPts(crashStore, MAP) == 1, "6: the pre-crash fold stored the first skin")
check(crashStore.records[first] ~= nil and #crashStore.order == R.MAX_RECORDS + 1,
  "6: the crash leftover still has the record in the ring")
R.EvictRing(crashStore)
check(#crashStore.order == R.MAX_RECORDS, "6: EvictRing trims the ring")
check(crashStore.records[first] == nil, "6: the already-folded record then leaves the ring")
check(hotspotPts(crashStore, MAP) == 1,
  "6: retry does not increment n (got " .. tostring(hotspotPts(crashStore, MAP)) .. ")")

-- ── 7. unpositioned skinned evictions are counted, not folded ─────────
local up = {
  schema = 2, records = {}, order = {}, unclassified = {},
  creatures = {}, counts = {}, hotspots = {}, hotspotsSeeded = true,
}
for i = 1, 99 do
  local g = "Creature-0-8-1-1-2966-" .. string.format("%012X", i)
  up.order[i] = g
  up.records[g] = { guid = g, skinned = true, map = MAP, x = 0.2, y = 0.2 }
end
local upg = "Creature-0-8-1-1-2966-00000000DEAD"
up.order[100] = upg
up.records[upg] = { guid = upg, skinned = true, map = MAP } -- no x, y
local extra = "Creature-0-8-1-1-2952-00000000NEW1"
up.order[101] = extra
up.records[extra] = { guid = extra, skinned = false, map = MAP, x = 0.4, y = 0.4 }
R.EvictRing(up)
check(up.records[upg] == nil, "7: the unpositioned skin left the ring")
check(#up.order == R.MAX_RECORDS, "7: the ring stays at the cap")
check(up.unpositionedEvicted and up.unpositionedEvicted[MAP] == 1,
  "7: unpositionedEvicted[map] is 1 (got "
    .. tostring(up.unpositionedEvicted and up.unpositionedEvicted[MAP]) .. ")")
check(hotspotPts(up, MAP) == 0, "7: the unpositioned skin was not folded into the grid")
R.CountUnpositionedEviction(up, { guid = upg, skinned = true, map = MAP })
check(up.unpositionedEvicted[MAP] == 1, "7: recounting the same guid does not increment")
R.CountUnpositionedEviction(up, { guid = "Creature-0-8-1-1-2966-00000000NONE", skinned = true })
check(up.unpositionedEvicted["_"] == 1, "7: a missing map is counted under _")

-- ── 8. backfill seen from pts on an already-seeded pre-seen save ─────
-- Shape of a 398752f save: the grid has pts and n, hotspotsSeeded is
-- set, but seen is missing. A re-fold of those guids must not grow n.
local legacy = {
  schema = 2, records = {}, order = {}, unclassified = {},
  creatures = {}, counts = {}, hotspots = {}, hotspotsSeeded = true,
}
local legacyGuids = {}
local lKey = nil
legacy.hotspots[MAP] = {}
for i = 1, 5 do
  legacyGuids[i] = "Creature-0-7-1-1-2966-" .. string.format("%012X", 50 + i)
end
-- Build the cell as 398752f would have written it: pts and n, no seen.
lKey = select(1, R.SkinCellKey(0.33, 0.34))
legacy.hotspots[MAP][lKey] = {
  n = 5, last = 100, nodes = { [2966] = 5 },
  pts = {
    { x = 0.33, y = 0.34, guid = legacyGuids[1] },
    { x = 0.33, y = 0.34, guid = legacyGuids[2] },
    { x = 0.33, y = 0.34, guid = legacyGuids[3] },
    { x = 0.33, y = 0.34, guid = legacyGuids[4] },
    { x = 0.33, y = 0.34, guid = legacyGuids[5] },
  },
}
-- No seen key at all.
check(legacy.hotspots[MAP][lKey].seen == nil, "8: the legacy cell has no seen table")
R.SeedSkinHotspots(legacy)
local lCell = legacy.hotspots[MAP][lKey]
check(type(lCell.seen) == "table", "8: load backfills a seen table")
for i = 1, 5 do
  check(lCell.seen[legacyGuids[i]] == true,
    "8: guid " .. i .. " was copied from pts into seen")
end
check(lCell.n == 5, "8: backfill does not change n (got " .. tostring(lCell.n) .. ")")
R.FoldSkinIntoHotspots(legacy, {
  guid = legacyGuids[3], creatureID = 2966, skinned = true,
  map = MAP, x = 0.33, y = 0.34,
})
check(lCell.n == 5,
  "8: a re-fold of a backfilled guid does not increment n (got " .. tostring(lCell.n) .. ")")
-- GetDB / Upgrade is the live entry point.
NodeTrailDB = { skinning = { enabled = true, chars = { ["Mightie-Forever"] = legacy } } }
local via = R:GetDB()
check(via.hotspots[MAP][lKey].n == 5, "8: GetDB does not double-count a pre-seen save")

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("skinroute_durability_spec: ok")

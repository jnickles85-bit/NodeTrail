-- herb_history_cap_spec.lua — cap NodeTrailDB.herbs without wiping history.
--
-- A schema 1 save is an unbounded per-map array of raw picks. Schema 2 keeps
-- the same array shape (newest MAX_SAMPLES_PER_MAP per map) and moves
-- lifetime counts / personal drop stats into aggregates so an upgrade never
-- forgets what the player gathered.
--
-- What this pins:
--   1. upgrading a large schema 1 store preserves db.total, per-map lifetime
--      counts, and GetPersonalStats; the raw lists keep only the newest cap
--      entries, in order;
--   2. the migration is idempotent: a second GetHerbDB does not change
--      aggregates or re-trim already-capped lists;
--   3. a crash before the schema stamp (wrong/partial stats, schema still 1,
--      raw intact) retries from the raw records and lands on the same
--      aggregates — and a schema 2 store is NOT re-seeded from the trimmed
--      list (that would drop history);
--   4. RecordHerb past the cap grows lifetime totals and stats but does not
--      grow the raw list;
--   5. a density route can still be built from a few thousand synthetic
--      gathers after the cap has trimmed the raw list (it sees only the
--      newest 2,000 raw picks, not the hotspot cells);
--   6. trimmed picks seed the per-map hotspot grid at migration, and
--      NT.Hotspots can query it;
--   7. a live trim (RecordHerb past the cap) folds the evicted pick into
--      hotspots without double-counting aggregates;
--   8. a downgrade/upgrade round-trip that re-attaches trimmed raw picks
--      does not double-count aggregates or hotspots, and new picks made
--      on the older build are folded in;
--   9. a non-numeric schema is left alone;
--  10. the hotspot grid stays within its cell and per-cell node bounds;
--  11. a crash-matrix for mid-loop folding: rec.hsFolded on a still-
--      untrimmed list does not re-fold on retry; NT.Hotspots returns
--      a copy of cell.nodes; HerbCellKey survives a SECRET coordinate
--      and a tonumber that raises; a second live trim folds newly
--      evicted untimed picks; same-second siblings both fold and a
--      downgrade re-attach of them does not double-count. Same-second
--      siblings also both count in aggregates (rec.aggFolded). A
--      downgrade that re-attaches unmarked picks skips t < hsT0, and
--      at t == hsT0 skips only the stored hsTN count, so an extra
--      same-second sibling still folds once. A mid-loop aggregate
--      crash still applies the unmarked same-second sibling. A
--      pre-#29 schema-2 save (aggT set, no aggTN or marks; or a
--      noTN-only marker with aggT=0) is backfilled without
--      re-counting totals, and kept records do not retain aggFolded.
--      A partial-clear mix (unmarked t < aggT0 plus a marked
--      same-second neighbour) skips the older pick and still
--      applies the unmarked sibling and any newer pick.
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

local function boot()
  local pkg = {}
  loadFile(pkg, "locale/enUS.lua")
  loadFile(pkg, "Config.lua")
  loadFile(pkg, "Data/ItemNames.lua")
  loadFile(pkg, "Data/HerbData.lua")
  loadFile(pkg, "Data/Recorder.lua")
  loadFile(pkg, "Data/Density.lua")
  return pkg, pkg.NodeTrail
end

local PEACE, SWIFT, EARTH = 2447, 2452, 2449
local MAP_A, MAP_B = 1429, 1430
local BIG = 2500
-- A second map stays under the cap so we can see it is left alone.
local SMALL = 80

-- Schema 1 fixture: BIG picks on map A, SMALL on map B. Every 10th Peacebloom
-- pick also carried Swiftthistle; map B is Earthroot only. Timestamps and
-- positions are monotone so "newest N" is unambiguous.
local function schema1Store()
  local maps = { [MAP_A] = {}, [MAP_B] = {} }
  for i = 1, BIG do
    local items = { { id = PEACE, name = "Peacebloom", count = 1 } }
    if i % 10 == 0 then
      items[#items + 1] = { id = SWIFT, name = "Swiftthistle", count = 1 }
    end
    maps[MAP_A][i] = {
      x = 0.10 + (i % 80) * 0.01,
      y = 0.10 + (math.floor((i - 1) / 80) % 80) * 0.01,
      t = 1700000000 + i,
      items = items,
    }
  end
  for i = 1, SMALL do
    maps[MAP_B][i] = {
      x = 0.2, y = 0.3, t = 1700000000 + i,
      items = { { id = EARTH, name = "Earthroot", count = 1 } },
    }
  end
  return {
    schema = 1,
    total = BIG + SMALL,
    maps = maps,
  }
end

-- Hand-derived from the generator, not by walking the migrated store.
local EXPECT_PEACE_GATHERS = BIG
local EXPECT_SWIFT_WITH_PEACE = math.floor(BIG / 10) -- 250
local EXPECT_EARTH_GATHERS = SMALL

local pkg, ns = boot()
local R = ns.Recorder
check(type(R) == "table", "recorder loaded")
check(type(R.MAX_SAMPLES_PER_MAP) == "number" and R.MAX_SAMPLES_PER_MAP == 2000,
  "MAX_SAMPLES_PER_MAP is the audit bound of 2000 (got " .. tostring(R and R.MAX_SAMPLES_PER_MAP) .. ")")
local CAP = R.MAX_SAMPLES_PER_MAP

-- ── 1. upgrade a large schema 1 store ────────────────────────────────
NodeTrailDB = { herbs = schema1Store() }
local herbs = ns.GetHerbDB()
check(herbs.schema == 2, "1: schema stamped 2 (got " .. tostring(herbs.schema) .. ")")
check(herbs.total == BIG + SMALL,
  "1: lifetime total is preserved (got " .. tostring(herbs.total) .. ")")
check(herbs.mapTotals[MAP_A] == BIG,
  "1: map A lifetime is " .. BIG .. " (got " .. tostring(herbs.mapTotals and herbs.mapTotals[MAP_A]) .. ")")
check(herbs.mapTotals[MAP_B] == SMALL,
  "1: map B lifetime is " .. SMALL .. " (got " .. tostring(herbs.mapTotals and herbs.mapTotals[MAP_B]) .. ")")
check(#herbs.maps[MAP_A] == CAP,
  "1: map A raw list is capped at " .. CAP .. " (got " .. tostring(#herbs.maps[MAP_A]) .. ")")
check(#herbs.maps[MAP_B] == SMALL,
  "1: map B is under the cap and kept whole (got " .. tostring(#herbs.maps[MAP_B]) .. ")")
-- Newest CAP on map A are original indices (BIG-CAP+1) .. BIG, i.e. 501..2500.
check(herbs.maps[MAP_A][1].t == 1700000000 + (BIG - CAP + 1),
  "1: first kept sample is the oldest of the newest " .. CAP
    .. " (t=" .. tostring(herbs.maps[MAP_A][1] and herbs.maps[MAP_A][1].t) .. ")")
check(herbs.maps[MAP_A][CAP].t == 1700000000 + BIG,
  "1: last kept sample is the newest pick (t="
    .. tostring(herbs.maps[MAP_A][CAP] and herbs.maps[MAP_A][CAP].t) .. ")")
check(ns.HerbMapTotal(MAP_A, herbs) == BIG,
  "1: HerbMapTotal reports lifetime on map A, not the trimmed length")

local H = ns.HerbData
local gPeace, coPeace, namesPeace = H.GetPersonalStats(PEACE)
check(gPeace == EXPECT_PEACE_GATHERS,
  "1: Peacebloom gathers preserved (" .. tostring(gPeace) .. ")")
check(coPeace[PEACE] == EXPECT_PEACE_GATHERS, "1: Peacebloom co-count with itself")
check(coPeace[SWIFT] == EXPECT_SWIFT_WITH_PEACE,
  "1: Swiftthistle co-count on Peacebloom gathers preserved (got "
    .. tostring(coPeace[SWIFT]) .. ")")
check(namesPeace[PEACE] == "Peacebloom", "1: stored Peacebloom name kept")
check(namesPeace[SWIFT] == "Swiftthistle", "1: stored Swiftthistle name kept")
local gEarth, coEarth, namesEarth = H.GetPersonalStats(EARTH)
check(gEarth == EXPECT_EARTH_GATHERS,
  "1: Earthroot gathers preserved (" .. tostring(gEarth) .. ")")
check(coEarth[EARTH] == EXPECT_EARTH_GATHERS, "1: Earthroot co-count")
check(namesEarth[EARTH] == "Earthroot", "1: stored Earthroot name kept")
-- A cap that only walked the newest 2000 Peacebloom picks would lose the
-- Swiftthistle counts from the trimmed prefix (50 of the 250). Prove we did not.
local swiftIfTrimmedOnly = 0
for i = 1, #herbs.maps[MAP_A] do
  local rec = herbs.maps[MAP_A][i]
  for _, it in ipairs(rec.items or {}) do
    if it.id == SWIFT then swiftIfTrimmedOnly = swiftIfTrimmedOnly + 1 end
  end
end
check(swiftIfTrimmedOnly == EXPECT_SWIFT_WITH_PEACE - math.floor((BIG - CAP) / 10),
  "1: sanity: the trimmed prefix really did hold Swiftthistle picks")
check(coPeace[SWIFT] > swiftIfTrimmedOnly,
  "1: aggregates include Swiftthistle picks from trimmed records, not only the raw tail")

-- ── 2. idempotent ────────────────────────────────────────────────────
local snapTotal = herbs.total
local snapA, snapB = herbs.mapTotals[MAP_A], herbs.mapTotals[MAP_B]
local snapLenA, snapLenB = #herbs.maps[MAP_A], #herbs.maps[MAP_B]
local snapFirstT = herbs.maps[MAP_A][1].t
local snapG, snapCo = gPeace, coPeace[SWIFT]
ns.GetHerbDB()
ns.UpgradeHerbDB(herbs)
check(herbs.schema == 2, "2: schema stays 2")
check(herbs.total == snapTotal, "2: total unchanged on second load")
check(herbs.mapTotals[MAP_A] == snapA and herbs.mapTotals[MAP_B] == snapB,
  "2: mapTotals unchanged on second load")
check(#herbs.maps[MAP_A] == snapLenA and #herbs.maps[MAP_B] == snapLenB,
  "2: raw lengths unchanged on second load")
check(herbs.maps[MAP_A][1].t == snapFirstT, "2: kept samples are the same objects/order")
local g2, co2 = H.GetPersonalStats(PEACE)
check(g2 == snapG and co2[SWIFT] == snapCo, "2: personal stats unchanged on second load")

-- ── 3. crash-before-stamp retries; schema 2 is not re-seeded ─────────
local rawAgain = schema1Store()
-- Simulate a mid-migration write: partial/wrong stats, schema still 1, raw intact.
rawAgain.stats = { gathers = { [PEACE] = 1 }, co = {}, names = {} }
rawAgain.mapTotals = { [MAP_A] = 3 }
NodeTrailDB = { herbs = rawAgain }
local retried = ns.GetHerbDB()
check(retried.schema == 2, "3: retry stamps schema 2")
check(retried.total == BIG + SMALL, "3: retry preserves lifetime total")
check(retried.mapTotals[MAP_A] == BIG, "3: retry recomputes map A from the intact raw list")
local g3, co3 = H.GetPersonalStats(PEACE)
check(g3 == EXPECT_PEACE_GATHERS and co3[SWIFT] == EXPECT_SWIFT_WITH_PEACE,
  "3: retry recomputes personal stats from the intact raw list (got gathers="
    .. tostring(g3) .. " swift=" .. tostring(co3 and co3[SWIFT]) .. ")")

-- After a successful stamp, corrupting stats and calling GetHerbDB again
-- must not rebuild them from the trimmed raw tail.
retried.stats.gathers[PEACE] = 123
retried.stats.co[PEACE][SWIFT] = 4
ns.GetHerbDB()
local g4, co4 = H.GetPersonalStats(PEACE)
check(g4 == 123, "3: a schema 2 store is not re-seeded from the trimmed list (gathers stayed at the written value)")
check(co4[SWIFT] == 4, "3: a schema 2 store is not re-seeded from the trimmed list (co-count stayed)")

-- ── 4. RecordHerb past the cap ───────────────────────────────────────
NodeTrailDB = { herbs = schema1Store() }
local live = ns.GetHerbDB()
local beforeTotal = live.total
local beforeA = live.mapTotals[MAP_A]
local beforeG = H.GetPersonalStats(PEACE)
-- The next pick is newer than the cap window.
ns.RecordHerb(MAP_A, 0.91, 0.92, { { id = PEACE, name = "Peacebloom", count = 1 } })
check(live.total == beforeTotal + 1, "4: lifetime total still grows after the cap")
check(live.mapTotals[MAP_A] == beforeA + 1, "4: map lifetime still grows after the cap")
check(#live.maps[MAP_A] == CAP, "4: raw list stays at the cap after a new pick")
check(live.maps[MAP_A][CAP].x == 0.91, "4: the new pick is the newest raw sample")
-- The previous first-kept sample (original index 501) must have been pushed out.
check(live.maps[MAP_A][1].t == 1700000000 + (BIG - CAP + 2),
  "4: the oldest kept sample advanced by one")
local g5 = H.GetPersonalStats(PEACE)
check(g5 == beforeG + 1, "4: personal gathers include the new pick (got " .. tostring(g5) .. ")")

-- A newer-than-this-build schema is left alone (not trimmed, not downgraded).
local future = {
  schema = 99,
  total = 3,
  maps = { [MAP_A] = {} },
  mapTotals = { [MAP_A] = 3 },
  stats = { gathers = {}, co = {}, names = {} },
}
for i = 1, CAP + 5 do
  future.maps[MAP_A][i] = { x = 0.1, y = 0.1, t = i, items = {} }
end
NodeTrailDB = { herbs = future }
ns.GetHerbDB()
check(future.schema == 99, "4: a newer schema is never downgraded")
check(#future.maps[MAP_A] == CAP + 5,
  "4: a newer schema is not trimmed by this build (got " .. tostring(#future.maps[MAP_A]) .. ")")

-- ── 5. route-building from a few thousand synthetic gathers ───────────
NodeTrailDB = { herbs = schema1Store() }
-- Config defaults via GetDB; BuildDensityRouteForMap reads density settings.
ns.GetDB()
ns.GetHerbDB()
local route, err = ns.BuildDensityRouteForMap(MAP_A)
check(route ~= nil,
  "5: density route builds from " .. BIG .. " synthetic gathers after the cap (err="
    .. tostring(err) .. ")")
if route then
  check(route.picks == CAP,
    "5: the route is built from the capped raw list (picks=" .. tostring(route.picks) .. ")")
  check(type(route.stops) == "number" and route.stops >= 2,
    "5: the route has at least two stops (got " .. tostring(route.stops) .. ")")
end
-- Density does not yet mix in hotspot cells.
check(type(ns.Hotspots) == "function", "5: Hotspots read API exists")

-- ── 6. hotspot seeding at migration ──────────────────────────────────
NodeTrailDB = { herbs = schema1Store() }
local seeded = ns.GetHerbDB()
check(R.HOTSPOT_CELL == 0.02, "6: cell size is 2% of map width")
check(R.HOTSPOT_MAX_CELLS == 2500, "6: the grid is bounded to 50x50 cells")
local trimmed = BIG - CAP -- 500
local gridA = seeded.hotspots and seeded.hotspots[MAP_A]
check(type(gridA) == "table", "6: map A has a hotspot grid after migration")
local cellN, nodeN, lastMax = 0, 0, 0
if type(gridA) == "table" then
  for _, cell in pairs(gridA) do
    if type(cell) == "table" then
      cellN = cellN + (cell.n or 0)
      if type(cell.last) == "number" and cell.last > lastMax then
        lastMax = cell.last
      end
      if type(cell.nodes) == "table" then
        for _ in pairs(cell.nodes) do
          nodeN = nodeN + 1
        end
      end
    end
  end
end
check(cellN == trimmed,
  "6: every trimmed map A pick is in the grid (n=" .. tostring(cellN) .. " want " .. trimmed .. ")")
check(type(seeded.folded) == "table" and type(seeded.folded[MAP_A]) == "table",
  "6: a folded marker is stored for map A")
local foldA = seeded.folded and seeded.folded[MAP_A]
check(foldA and foldA.n == trimmed,
  "6: folded.n is the trimmed count (got " .. tostring(foldA and foldA.n) .. ")")
check(foldA and foldA.hsT == 1700000000 + trimmed,
  "6: hsT is the last trimmed timestamp (got " .. tostring(foldA and foldA.hsT) .. ")")
check(foldA and foldA.aggT == 1700000000 + BIG,
  "6: aggT is the newest raw timestamp (got " .. tostring(foldA and foldA.aggT) .. ")")
-- Map B was under the cap: nothing to fold.
local gridB = seeded.hotspots and seeded.hotspots[MAP_B]
local cellB = 0
if type(gridB) == "table" then
  for _, cell in pairs(gridB) do
    if type(cell) == "table" then cellB = cellB + (cell.n or 0) end
  end
end
check(cellB == 0, "6: an under-cap map does not mint hotspots (got " .. tostring(cellB) .. ")")
local hs = ns.Hotspots(MAP_A)
local hsN = 0
for i = 1, #hs do hsN = hsN + (hs[i].n or 0) end
check(hsN == trimmed, "6: NT.Hotspots(mapA) sums to the trimmed count (got " .. tostring(hsN) .. ")")
check(#hs >= 1 and type(hs[1].x) == "number" and type(hs[1].y) == "number",
  "6: each hotspot has a cell-centre position")
local swiftHS = ns.Hotspots(MAP_A, SWIFT)
local swiftN = 0
for i = 1, #swiftHS do swiftN = swiftN + (swiftHS[i].n or 0) end
-- Trimmed prefix is i=1..500; every 10th pick carried Swiftthistle -> 50.
check(swiftN == 50,
  "6: a node filter returns only that node's folded picks (got " .. tostring(swiftN) .. ")")

-- ── 7. folding on a live trim ────────────────────────────────────────
local beforeHN = foldA.n
local beforeG = H.GetPersonalStats(PEACE)
local beforeTotal = seeded.total
ns.RecordHerb(MAP_A, 0.91, 0.92, { { id = PEACE, name = "Peacebloom", count = 1 } })
check(#seeded.maps[MAP_A] == CAP, "7: raw list stays at the cap")
check(seeded.folded[MAP_A].n == beforeHN + 1,
  "7: the evicted pick is folded into hotspots (n=" .. tostring(seeded.folded[MAP_A].n) .. ")")
local hs2 = ns.Hotspots(MAP_A)
local hs2N = 0
for i = 1, #hs2 do hs2N = hs2N + (hs2[i].n or 0) end
check(hs2N == trimmed + 1, "7: Hotspots includes the newly evicted pick (got " .. tostring(hs2N) .. ")")
local g7 = H.GetPersonalStats(PEACE)
check(g7 == beforeG + 1, "7: aggregates grow by the new pick only, not the evicted one again")
check(seeded.total == beforeTotal + 1, "7: lifetime total grows by one")

-- ── 8. downgrade / upgrade round-trip ────────────────────────────────
NodeTrailDB = { herbs = schema1Store() }
local rt = ns.GetHerbDB()
local snapTotal, snapA = rt.total, rt.mapTotals[MAP_A]
local snapG, snapCo = H.GetPersonalStats(PEACE)
local snapHN = rt.folded[MAP_A].n
local snapHS, snapAgg = rt.folded[MAP_A].hsT, rt.folded[MAP_A].aggT
-- An older build resets the schema stamp and re-attaches the trimmed prefix.
local prefix = {}
for i = 1, trimmed do
  prefix[i] = {
    x = 0.10 + (i % 80) * 0.01,
    y = 0.10 + (math.floor((i - 1) / 80) % 80) * 0.01,
    t = 1700000000 + i,
    items = { { id = PEACE, name = "Peacebloom", count = 1 } },
  }
  if i % 10 == 0 then
    prefix[i].items[#prefix[i].items + 1] = { id = SWIFT, name = "Swiftthistle", count = 1 }
  end
end
local restored = {}
for i = 1, trimmed do restored[i] = prefix[i] end
for i = 1, #rt.maps[MAP_A] do
  restored[trimmed + i] = rt.maps[MAP_A][i]
end
rt.maps[MAP_A] = restored
rt.schema = 1
ns.GetHerbDB()
check(rt.schema == 2, "8: schema is re-stamped 2 after the downgrade")
check(rt.total == snapTotal, "8: lifetime total is not double-counted (got " .. tostring(rt.total) .. ")")
check(rt.mapTotals[MAP_A] == snapA, "8: map lifetime is not double-counted")
check(#rt.maps[MAP_A] == CAP, "8: the restored prefix is trimmed again")
local g8, co8 = H.GetPersonalStats(PEACE)
check(g8 == snapG and co8[SWIFT] == snapCo[SWIFT], "8: personal stats are not double-counted (gathers=" .. tostring(g8) .. " swift=" .. tostring(co8 and co8[SWIFT]) .. ")")
check(rt.folded[MAP_A].n == snapHN, "8: hotspots are not folded a second time (n=" .. tostring(rt.folded[MAP_A].n) .. ")")
check(rt.folded[MAP_A].hsT == snapHS and rt.folded[MAP_A].aggT == snapAgg, "8: folded watermarks are unchanged")

-- The older build also appended 10 new picks (updating total, not mapTotals/stats).
local extra = 10
for i = 1, extra do
  rt.maps[MAP_A][#rt.maps[MAP_A] + 1] = {
    x = 0.93, y = 0.94, t = snapAgg + i,
    items = { { id = PEACE, name = "Peacebloom", count = 1 } },
  }
end
rt.total = rt.total + extra
rt.schema = 1
ns.GetHerbDB()
check(rt.mapTotals[MAP_A] == snapA + extra,
  "8: picks recorded on the older build are folded into mapTotals (got "
    .. tostring(rt.mapTotals[MAP_A]) .. ")")
check(rt.total == snapTotal + extra, "8: total is raised to the new lifetime, not added twice")
local g8b = H.GetPersonalStats(PEACE)
check(g8b == snapG + extra, "8: personal gathers include the older-build picks once")
check(#rt.maps[MAP_A] == CAP, "8: the list is trimmed back to the cap")
-- The 10 new picks evict 10 previously-kept samples into hotspots.
check(rt.folded[MAP_A].n == snapHN + extra,
  "8: newly evicted kept-window picks are folded into hotspots (n="
    .. tostring(rt.folded[MAP_A].n) .. ")")

-- ── 9. a non-numeric schema is left alone ────────────────────────────
local odd = {
  schema = "unknown",
  total = 3,
  maps = { [MAP_A] = {} },
}
for i = 1, CAP + 5 do
  odd.maps[MAP_A][i] = { x = 0.1, y = 0.1, t = i, items = {} }
end
NodeTrailDB = { herbs = odd }
ns.GetHerbDB()
check(odd.schema == "unknown", "9: a non-numeric schema is not rewritten (got " .. tostring(odd.schema) .. ")")
check(#odd.maps[MAP_A] == CAP + 5,
  "9: a non-numeric schema is not trimmed (got " .. tostring(#odd.maps[MAP_A]) .. ")")
check(odd.hotspots == nil, "9: a non-numeric schema does not grow a hotspot table")
check(odd.folded == nil, "9: a non-numeric schema does not grow a folded marker")

-- ── 10. hotspots stay within bounds ──────────────────────────────────
NodeTrailDB = { herbs = schema1Store() }
local bounded = ns.GetHerbDB()
local cells = 0
if type(bounded.hotspots) == "table" and type(bounded.hotspots[MAP_A]) == "table" then
  for _ in pairs(bounded.hotspots[MAP_A]) do cells = cells + 1 end
end
check(cells <= R.HOTSPOT_MAX_CELLS,
  "10: migration cannot mint more than " .. R.HOTSPOT_MAX_CELLS .. " cells (got " .. cells .. ")")
-- 40 distinct node ids in one cell: n grows, but nodes is capped.
local oneCell = { schema = 2, total = 0, maps = { [MAP_A] = {} }, mapTotals = { [MAP_A] = 0 },
  stats = { gathers = {}, co = {}, names = {} }, hotspots = {}, folded = {} }
for i = 1, 40 do
  R.FoldHerbIntoHotspots(oneCell, MAP_A, {
    x = 0.5, y = 0.5, t = 100 + i, items = { { id = 1000 + i, name = "N" .. i, count = 1 } },
  })
end
local key = R.HerbCellKey(0.5, 0.5)
local cell = oneCell.hotspots[MAP_A][key]
local nKeys = 0
if type(cell) == "table" and type(cell.nodes) == "table" then
  for _ in pairs(cell.nodes) do nKeys = nKeys + 1 end
end
check(cell and cell.n == 40, "10: n still counts every pick in an overfull cell (got " .. tostring(cell and cell.n) .. ")")
check(nKeys == R.HOTSPOT_MAX_NODES,
  "10: a cell keeps at most " .. R.HOTSPOT_MAX_NODES .. " node keys (got " .. tostring(nKeys) .. ")")
local k1 = R.HerbCellKey(1, 1)
local k0 = R.HerbCellKey(0, 0)
local kOob = R.HerbCellKey(1.5, -0.2)
check(k0 == "0:0", "10: the origin cell is 0:0 (got " .. tostring(k0) .. ")")
check(k1 == "49:49", "10: x=y=1 clamps to the last bin, not a 50th (got " .. tostring(k1) .. ")")
check(kOob == k1 or kOob == "49:0", "10: out-of-range positions clamp into the 50x50 grid (got " .. tostring(kOob) .. ")")
-- -0.2, 1.5 -> x clamps to 1 -> 49, y clamps to 0 -> 0, so 49:0
check(R.HerbCellKey(1.5, -0.2) == "49:0", "10: clamped oob key is 49:0")

-- ── 11. crash matrix, Hotspots copies, HerbCellKey secrets ──────────
local function gridN(db, mapID)
  local n = 0
  local grid = db.hotspots and db.hotspots[mapID]
  if type(grid) ~= "table" then return 0 end
  for _, cell in pairs(grid) do
    if type(cell) == "table" then n = n + (cell.n or 0) end
  end
  return n
end

local function listOf(n, t0, opts)
  opts = opts or {}
  local list = {}
  for i = 1, n do
    local rec = {
      x = 0.25, y = 0.25,
      items = { { id = PEACE, name = "Peacebloom", count = 1 } },
    }
    if opts.noT and i <= (opts.noT or 0) then
      rec.t = nil
    else
      rec.t = t0 + i
    end
    list[i] = rec
  end
  return list
end

-- 11a. Mid-loop crash after some timed picks: those records are marked
-- hsFolded, the list is still over the cap, schema already 2.
local crashN = CAP + 20
local crashDB = {
  schema = 2, total = crashN,
  maps = { [MAP_A] = listOf(crashN, 1700000000) },
  mapTotals = { [MAP_A] = crashN },
  stats = { gathers = {}, co = {}, names = {} },
  hotspots = {}, folded = {},
}
-- Simulate 8 successful folds, then a crash before the rest and before trim.
local partial = 8
for i = 1, partial do
  local rec = crashDB.maps[MAP_A][i]
  R.FoldHerbIntoHotspots(crashDB, MAP_A, rec)
  rec.hsFolded = true
end
crashDB.folded[MAP_A] = { aggT = 1700000000 + crashN, hsT = 1700000000 + partial, n = partial }
check(gridN(crashDB, MAP_A) == partial, "11a: pre-retry grid holds the 8 already-folded picks")
check(#crashDB.maps[MAP_A] == crashN, "11a: the raw list is still untrimmed after the crash")
NodeTrailDB = { herbs = crashDB }
ns.GetHerbDB()
check(#crashDB.maps[MAP_A] == CAP, "11a: retry trims the list to the cap")
check(crashDB.folded[MAP_A].n == 20,
  "11a: retry folds only the remaining 12 (n=" .. tostring(crashDB.folded[MAP_A].n) .. ")")
check(crashDB.folded[MAP_A].hsT == 1700000000 + 20,
  "11a: hsT advances to the last evicted timestamp (got "
    .. tostring(crashDB.folded[MAP_A].hsT) .. ")")
check(gridN(crashDB, MAP_A) == 20,
  "11a: the grid is not double-counted (n=" .. tostring(gridN(crashDB, MAP_A)) .. ")")

-- 11b. Mid-loop crash after some no-t folds: those records are marked.
local noT = 5
local crashNoT = {
  schema = 2, total = crashN,
  maps = { [MAP_A] = listOf(crashN, 1700000000, { noT = noT }) },
  mapTotals = { [MAP_A] = crashN },
  stats = { gathers = {}, co = {}, names = {} },
  hotspots = {}, folded = {},
}
-- First 5 evicted picks have no t (listOf puts them at the front).
local partialNoT = 3
for i = 1, partialNoT do
  R.FoldHerbIntoHotspots(crashNoT, MAP_A, crashNoT.maps[MAP_A][i])
  crashNoT.maps[MAP_A][i].hsFolded = true
end
crashNoT.folded[MAP_A] = { aggT = 1700000000 + crashN, hsT = 0, n = partialNoT }
NodeTrailDB = { herbs = crashNoT }
ns.GetHerbDB()
check(#crashNoT.maps[MAP_A] == CAP, "11b: retry trims the no-t store to the cap")
check(crashNoT.folded[MAP_A].n == 20,
  "11b: n is 5 no-t + 15 timed, not re-folded (n="
    .. tostring(crashNoT.folded[MAP_A].n) .. ")")
check(gridN(crashNoT, MAP_A) == 20,
  "11b: the grid is not double-counted for no-t picks (n="
    .. tostring(gridN(crashNoT, MAP_A)) .. ")")

-- 11c. Crash after every fold, before trim: retry must not re-fold.
local done = {
  schema = 2, total = crashN,
  maps = { [MAP_A] = listOf(crashN, 1700000000) },
  mapTotals = { [MAP_A] = crashN },
  stats = { gathers = {}, co = {}, names = {} },
  hotspots = {}, folded = {},
}
for i = 1, 20 do
  R.FoldHerbIntoHotspots(done, MAP_A, done.maps[MAP_A][i])
  done.maps[MAP_A][i].hsFolded = true
end
done.folded[MAP_A] = { aggT = 1700000000 + crashN, hsT = 1700000000 + 20, n = 20 }
NodeTrailDB = { herbs = done }
ns.GetHerbDB()
check(#done.maps[MAP_A] == CAP, "11c: retry after a pre-trim crash still trims")
check(done.folded[MAP_A].n == 20 and gridN(done, MAP_A) == 20,
  "11c: a completed fold is not replayed (n=" .. tostring(done.folded[MAP_A].n)
    .. " grid=" .. tostring(gridN(done, MAP_A)) .. ")")

-- 11d. NT.Hotspots returns a copy of cell.nodes.
NodeTrailDB = { herbs = schema1Store() }
local copyDB = ns.GetHerbDB()
local hsCopy = ns.Hotspots(MAP_A)
check(#hsCopy >= 1 and type(hsCopy[1].nodes) == "table",
  "11d: Hotspots returns a nodes table")
local liveCell = copyDB.hotspots[MAP_A][hsCopy[1].key]
check(type(liveCell) == "table" and type(liveCell.nodes) == "table",
  "11d: the store cell is reachable by the returned key")
check(hsCopy[1].nodes ~= liveCell.nodes,
  "11d: the returned nodes table is not the live cell.nodes")
hsCopy[1].nodes.__mutated = true
check(liveCell.nodes.__mutated == nil,
  "11d: mutating the returned nodes does not change the store")

-- 11e. HerbCellKey: SECRET coordinates and a raising tonumber.
local realTonumber, realSecret = tonumber, issecretvalue
issecretvalue = function(v) return v == "SECRET" end
tonumber = function(v)
  if v == "SECRET" or v == "BOOM" then
    error("secret-or-bad tonumber")
  end
  return realTonumber(v)
end
local okSecret, kSecret = pcall(R.HerbCellKey, "SECRET", 0.5)
check(okSecret, "11e: HerbCellKey does not raise on a SECRET coordinate")
check(kSecret == R.HerbCellKey(0, 0.5),
  "11e: a SECRET x is treated as 0 (got " .. tostring(kSecret) .. ")")
local okBoom, kBoom = pcall(R.HerbCellKey, "BOOM", 0)
check(okBoom, "11e: HerbCellKey does not raise when tonumber raises")
check(kBoom == "0:0", "11e: a failed tonumber falls back to 0 (got " .. tostring(kBoom) .. ")")
local okNum, kNum = pcall(R.HerbCellKey, "0.5", "0.5")
check(okNum and kNum == R.HerbCellKey(0.5, 0.5),
  "11e: a numeric string still keys the same cell as a number")
tonumber, issecretvalue = realTonumber, realSecret

-- 11f. A second live trim must fold newly evicted untimed picks.
-- First trim drops 3 untimed (n=3). The next two oldest kept picks
-- are also untimed and unmarked; appending two new records evicts
-- them, and they must be folded (n=5). A lifetime noTN count would
-- skip them.
local live2 = {
  schema = 2, total = CAP + 3,
  maps = { [MAP_A] = listOf(CAP + 3, 1700000000, { noT = 5 }) },
  mapTotals = { [MAP_A] = CAP + 3 },
  stats = { gathers = {}, co = {}, names = {} },
  hotspots = {}, folded = {},
}
NodeTrailDB = { herbs = live2 }
ns.GetHerbDB()
check(#live2.maps[MAP_A] == CAP, "11f: the first trim brings the list to the cap")
check(live2.folded[MAP_A].n == 3,
  "11f: the first trim folded the 3 evicted untimed picks (n="
    .. tostring(live2.folded[MAP_A].n) .. ")")
check(gridN(live2, MAP_A) == 3, "11f: the grid holds those 3")
check(live2.maps[MAP_A][1].t == nil and live2.maps[MAP_A][2].t == nil,
  "11f: the new oldest kept picks are the remaining untimed ones")
check(live2.maps[MAP_A][1].hsFolded ~= true and live2.maps[MAP_A][2].hsFolded ~= true,
  "11f: those kept untimed picks are not marked yet")
for i = 1, 2 do
  live2.maps[MAP_A][#live2.maps[MAP_A] + 1] = {
    x = 0.91, y = 0.92, t = 1800000000 + i,
    items = { { id = PEACE, name = "Peacebloom", count = 1 } },
  }
end
live2.total = live2.total + 2
ns.GetHerbDB()
check(#live2.maps[MAP_A] == CAP, "11f: the second trim stays at the cap")
check(live2.folded[MAP_A].n == 5,
  "11f: the second trim folded the 2 newly evicted untimed picks (n="
    .. tostring(live2.folded[MAP_A].n) .. ")")
check(gridN(live2, MAP_A) == 5,
  "11f: the grid holds all 5 untimed evictions (n="
    .. tostring(gridN(live2, MAP_A)) .. ")")

-- 11g. Two evicted picks that share a timestamp both fold.
local sib = {
  schema = 2, total = CAP + 2,
  maps = { [MAP_A] = {} },
  mapTotals = { [MAP_A] = CAP + 2 },
  stats = { gathers = {}, co = {}, names = {} },
  hotspots = {}, folded = {},
}
for i = 1, CAP + 2 do
  sib.maps[MAP_A][i] = {
    x = 0.10 + (i == 2 and 0.04 or 0), y = 0.10,
    t = (i <= 2) and 5000 or (6000 + i),
    items = { { id = PEACE, name = "Peacebloom", count = 1 } },
  }
end
NodeTrailDB = { herbs = sib }
ns.GetHerbDB()
check(#sib.maps[MAP_A] == CAP, "11g: same-second evictions are trimmed to the cap")
check(sib.folded[MAP_A].n == 2,
  "11g: both picks at t=5000 were folded (n=" .. tostring(sib.folded[MAP_A].n) .. ")")
check(gridN(sib, MAP_A) == 2,
  "11g: the grid holds both same-second picks (n=" .. tostring(gridN(sib, MAP_A)) .. ")")
check(sib.folded[MAP_A].hsT == 5000,
  "11g: hsT is the shared second (got " .. tostring(sib.folded[MAP_A].hsT) .. ")")
check(sib.folded[MAP_A].hsTN == 2,
  "11g: hsTN counts both picks at that second (got " .. tostring(sib.folded[MAP_A].hsTN) .. ")")
-- Downgrade re-attaches unmarked copies of those two picks.
local restored = {
  { x = 0.10, y = 0.10, t = 5000,
    items = { { id = PEACE, name = "Peacebloom", count = 1 } } },
  { x = 0.14, y = 0.10, t = 5000,
    items = { { id = PEACE, name = "Peacebloom", count = 1 } } },
}
for i = 1, #sib.maps[MAP_A] do
  restored[#restored + 1] = sib.maps[MAP_A][i]
end
local snapN, snapGrid = sib.folded[MAP_A].n, gridN(sib, MAP_A)
sib.maps[MAP_A] = restored
sib.schema = 1
ns.GetHerbDB()
check(#sib.maps[MAP_A] == CAP, "11g: the re-attached prefix is trimmed again")
check(sib.folded[MAP_A].n == snapN,
  "11g: re-attaching unmarked same-second picks does not double-fold (n="
    .. tostring(sib.folded[MAP_A].n) .. ")")
check(gridN(sib, MAP_A) == snapGrid,
  "11g: the grid is unchanged after the re-attach (n="
    .. tostring(gridN(sib, MAP_A)) .. ")")


-- 11h. Two unmarked picks that share a second both count in aggregates.
-- A downgrade re-attach of those unmarked copies skips t < aggT and
-- only aggTN picks at t == aggT, so an extra same-second sibling
-- is counted once.
local sameAgg = {
  schema = 2, total = 0,
  maps = { [MAP_A] = {
    { x = 0.10, y = 0.10, t = 1000,
      items = { { id = PEACE, name = "Peacebloom", count = 1 } } },
    { x = 0.11, y = 0.10, t = 2000,
      items = { { id = PEACE, name = "Peacebloom", count = 1 } } },
    { x = 0.12, y = 0.10, t = 2000,
      items = { { id = PEACE, name = "Peacebloom", count = 1 } } },
  } },
  mapTotals = { [MAP_A] = 0 },
  stats = { gathers = {}, co = {}, names = {} },
  hotspots = {}, folded = { [MAP_A] = { aggT = 0, aggTN = 0, hsT = 0, hsTN = 0, n = 0 } },
}
NodeTrailDB = { herbs = sameAgg }
ns.GetHerbDB()
check(sameAgg.mapTotals[MAP_A] == 3,
  "11h: both picks at t=2000 count in mapTotals (got " .. tostring(sameAgg.mapTotals[MAP_A]) .. ")")
check(sameAgg.total == 3, "11h: lifetime total includes both same-second picks")
check(sameAgg.folded[MAP_A].aggT == 2000,
  "11h: aggT is the shared second (got " .. tostring(sameAgg.folded[MAP_A].aggT) .. ")")
check(sameAgg.folded[MAP_A].aggTN == 2,
  "11h: aggTN counts both picks at that second (got " .. tostring(sameAgg.folded[MAP_A].aggTN) .. ")")
check(sameAgg.maps[MAP_A][1].aggFolded == nil
    and sameAgg.maps[MAP_A][2].aggFolded == nil
    and sameAgg.maps[MAP_A][3].aggFolded == nil,
  "11h: kept records do not keep aggFolded after the pass")

local aggRestored = {
  { x = 0.10, y = 0.10, t = 1000,
    items = { { id = PEACE, name = "Peacebloom", count = 1 } } },
  { x = 0.11, y = 0.10, t = 2000,
    items = { { id = PEACE, name = "Peacebloom", count = 1 } } },
  { x = 0.12, y = 0.10, t = 2000,
    items = { { id = PEACE, name = "Peacebloom", count = 1 } } },
  { x = 0.13, y = 0.10, t = 2000,
    items = { { id = PEACE, name = "Peacebloom", count = 1 } } },
}
sameAgg.maps[MAP_A] = aggRestored
sameAgg.schema = 1
ns.GetHerbDB()
check(sameAgg.mapTotals[MAP_A] == 4,
  "11h: only the extra same-second sibling is added (got " .. tostring(sameAgg.mapTotals[MAP_A]) .. ")")
check(sameAgg.total == 4, "11h: lifetime total grows by the extra sibling only")
check(sameAgg.folded[MAP_A].aggTN == 3,
  "11h: aggTN includes the new sibling (got " .. tostring(sameAgg.folded[MAP_A].aggTN) .. ")")
check(aggRestored[4].aggFolded == nil, "11h: the new sibling does not keep aggFolded")

-- 11i. Unmarked re-attach fallback skips t < hsT0, and at t == hsT0
-- skips only the stored hsTN count, so an extra same-second pick folds.
local hsSib = {
  schema = 2, total = CAP + 2,
  maps = { [MAP_A] = {} },
  mapTotals = { [MAP_A] = CAP + 2 },
  stats = { gathers = {}, co = {}, names = {} },
  hotspots = {}, folded = {},
}
for i = 1, CAP + 2 do
  hsSib.maps[MAP_A][i] = {
    x = 0.10 + (i == 2 and 0.04 or 0), y = 0.10,
    t = (i <= 2) and 5000 or (6000 + i),
    items = { { id = PEACE, name = "Peacebloom", count = 1 } },
  }
end
NodeTrailDB = { herbs = hsSib }
ns.GetHerbDB()
check(hsSib.folded[MAP_A].hsT == 5000 and hsSib.folded[MAP_A].hsTN == 2,
  "11i: first trim records hsTN=2 at t=5000 (hsTN="
    .. tostring(hsSib.folded[MAP_A].hsTN) .. ")")
local hsRestored = {
  { x = 0.20, y = 0.10, t = 4000,
    items = { { id = PEACE, name = "Peacebloom", count = 1 } } },
  { x = 0.10, y = 0.10, t = 5000,
    items = { { id = PEACE, name = "Peacebloom", count = 1 } } },
  { x = 0.14, y = 0.10, t = 5000,
    items = { { id = PEACE, name = "Peacebloom", count = 1 } } },
  { x = 0.18, y = 0.10, t = 5000,
    items = { { id = PEACE, name = "Peacebloom", count = 1 } } },
}
for i = 1, #hsSib.maps[MAP_A] do
  hsRestored[#hsRestored + 1] = hsSib.maps[MAP_A][i]
end
local snapNi, snapGridi = hsSib.folded[MAP_A].n, gridN(hsSib, MAP_A)
hsSib.maps[MAP_A] = hsRestored
hsSib.schema = 1
ns.GetHerbDB()
check(#hsSib.maps[MAP_A] == CAP, "11i: the re-attached prefix is trimmed again")
check(hsSib.folded[MAP_A].n == snapNi + 1,
  "11i: t<hsT0 is skipped and only the extra t==hsT0 sibling folds (n="
    .. tostring(hsSib.folded[MAP_A].n) .. ")")
check(gridN(hsSib, MAP_A) == snapGridi + 1,
  "11i: the grid grows by the extra sibling only (n="
    .. tostring(gridN(hsSib, MAP_A)) .. ")")
check(hsSib.folded[MAP_A].hsTN == 3,
  "11i: hsTN includes the new sibling (got " .. tostring(hsSib.folded[MAP_A].hsTN) .. ")")


-- 11j. Mid-loop crash: the first same-second pick is already marked
-- and counted in aggTN. The unmarked sibling must still apply; it
-- must not be swallowed because the marked neighbour was not counted
-- toward skippedAt.
local crashAgg = {
  schema = 2, total = 1,
  maps = { [MAP_A] = {
    { x = 0.10, y = 0.10, t = 2000, aggFolded = true,
      items = { { id = PEACE, name = "Peacebloom", count = 1 } } },
    { x = 0.11, y = 0.10, t = 2000,
      items = { { id = PEACE, name = "Peacebloom", count = 1 } } },
  } },
  mapTotals = { [MAP_A] = 1 },
  stats = { gathers = { [PEACE] = 1 }, co = {}, names = { [PEACE] = "Peacebloom" } },
  hotspots = {}, folded = { [MAP_A] = { aggT = 2000, aggTN = 1, hsT = 0, hsTN = 0, n = 0 } },
}
NodeTrailDB = { herbs = crashAgg }
ns.GetHerbDB()
check(crashAgg.mapTotals[MAP_A] == 2,
  "11j: the unmarked same-second sibling is applied after a crash (got "
    .. tostring(crashAgg.mapTotals[MAP_A]) .. ")")
check(crashAgg.total == 2, "11j: lifetime total includes the sibling")
check(crashAgg.folded[MAP_A].aggTN == 2,
  "11j: aggTN includes both picks at t=2000 (got " .. tostring(crashAgg.folded[MAP_A].aggTN) .. ")")
check(crashAgg.maps[MAP_A][1].aggFolded == nil
    and crashAgg.maps[MAP_A][2].aggFolded == nil,
  "11j: crash stamps are cleared once the pass finishes")

-- 11k. A real f2f4da2-shaped schema-2 save: aggT set, no aggTN, no
-- per-record marks. Two of the three picks share the newest second,
-- so a t==aggT re-apply would bump mapTotals from 3 to 5. Also a
-- noTN-only marker with aggT still 0 must not re-count the kept
-- timed picks (mapTotals 50 to 60).
local peace = function(t)
  return {
    x = 0.10, y = 0.10, t = t,
    items = { { id = PEACE, name = "Peacebloom", count = 1 } },
  }
end
local legacy = {
  schema = 2, total = 3,
  maps = { [MAP_A] = { peace(1000), peace(2000), peace(2000) } },
  mapTotals = { [MAP_A] = 3 },
  stats = { gathers = { [PEACE] = 3 }, co = {}, names = { [PEACE] = "Peacebloom" } },
  hotspots = {},
  -- f2f4da2 folded marker: aggT / hsT / n only.
  folded = { [MAP_A] = { aggT = 2000, hsT = 0, n = 0 } },
}
NodeTrailDB = { herbs = legacy }
ns.GetHerbDB()
check(legacy.mapTotals[MAP_A] == 3,
  "11k: a pre-#29 schema-2 save does not double-count t==aggT (got "
    .. tostring(legacy.mapTotals[MAP_A]) .. ")")
check(legacy.total == 3, "11k: lifetime total stays 3")
check(legacy.folded[MAP_A].aggTN == 2,
  "11k: aggTN is backfilled for the two picks at aggT (got "
    .. tostring(legacy.folded[MAP_A].aggTN) .. ")")
check(legacy.maps[MAP_A][1].aggFolded == nil
    and legacy.maps[MAP_A][2].aggFolded == nil
    and legacy.maps[MAP_A][3].aggFolded == nil,
  "11k: the backfill does not leave aggFolded on kept records")

local notn = {
  schema = 2, total = 50,
  maps = { [MAP_A] = {} },
  mapTotals = { [MAP_A] = 50 },
  stats = { gathers = { [PEACE] = 50 }, co = {}, names = { [PEACE] = "Peacebloom" } },
  hotspots = {},
  folded = { [MAP_A] = { aggT = 0, hsT = 0, n = 0, noTN = 40 } },
}
for i = 1, 10 do
  notn.maps[MAP_A][i] = peace(1000 + i)
end
NodeTrailDB = { herbs = notn }
ns.GetHerbDB()
check(notn.mapTotals[MAP_A] == 50,
  "11k: a noTN-only marker with aggT=0 does not re-count the kept list (got "
    .. tostring(notn.mapTotals[MAP_A]) .. ")")
check(notn.total == 50, "11k: lifetime total stays 50")
check(notn.folded[MAP_A].aggT == 1010,
  "11k: the watermark is lifted to the kept list's max time (got "
    .. tostring(notn.folded[MAP_A].aggT) .. ")")
check(notn.folded[MAP_A].aggTN == 1,
  "11k: aggTN counts the single pick at that max time (got "
    .. tostring(notn.folded[MAP_A].aggTN) .. ")")

-- 11l. A partial-clear mix: an unmarked pick below the watermark
-- plus a mid-loop mark on the first of two same-second picks.
-- t < aggT0 must still be skipped when anyMarked is true; the
-- unmarked sibling at t == aggT0 must still apply.
local mix = {
  schema = 2, total = 2,
  maps = { [MAP_A] = {
    peace(1000),
    (function()
      local rec = peace(2000)
      rec.aggFolded = true
      return rec
    end)(),
    peace(2000),
  } },
  mapTotals = { [MAP_A] = 2 },
  stats = { gathers = { [PEACE] = 2 }, co = {}, names = { [PEACE] = "Peacebloom" } },
  hotspots = {},
  folded = { [MAP_A] = { aggT = 2000, aggTN = 1, hsT = 0, hsTN = 0, n = 0 } },
}
NodeTrailDB = { herbs = mix }
ns.GetHerbDB()
check(mix.mapTotals[MAP_A] == 3,
  "11l: partial-clear mix applies the unmarked sibling only (got "
    .. tostring(mix.mapTotals[MAP_A]) .. ")")
check(mix.total == 3, "11l: lifetime total grows by the sibling only")
check(mix.folded[MAP_A].aggTN == 2,
  "11l: aggTN includes the unmarked sibling (got " .. tostring(mix.folded[MAP_A].aggTN) .. ")")

local mixNew = {
  schema = 2, total = 2,
  maps = { [MAP_A] = {
    peace(1000),
    (function()
      local rec = peace(2000)
      rec.aggFolded = true
      return rec
    end)(),
    peace(2000),
    peace(4000),
  } },
  mapTotals = { [MAP_A] = 2 },
  stats = { gathers = { [PEACE] = 2 }, co = {}, names = { [PEACE] = "Peacebloom" } },
  hotspots = {},
  folded = { [MAP_A] = { aggT = 2000, aggTN = 1, hsT = 0, hsTN = 0, n = 0 } },
}
NodeTrailDB = { herbs = mixNew }
ns.GetHerbDB()
check(mixNew.mapTotals[MAP_A] == 4,
  "11l: the same mix plus a new t=4000 pick counts both new ones (got "
    .. tostring(mixNew.mapTotals[MAP_A]) .. ")")
check(mixNew.total == 4, "11l: lifetime total grows by the sibling and the new pick")
check(mixNew.folded[MAP_A].aggT == 4000 and mixNew.folded[MAP_A].aggTN == 1,
  "11l: the watermark advances to the new pick (aggT="
    .. tostring(mixNew.folded[MAP_A].aggT) .. ", aggTN="
    .. tostring(mixNew.folded[MAP_A].aggTN) .. ")")

-- 11m. A pick appended after a clock rollback (t < aggT) still reaches
-- mapTotals, without re-counting historical picks below the watermark
-- or double-counting on a second load. hsFolded / aggFolded marks are
-- not left on kept records.
local rollback = {
  schema = 2, total = 2,
  maps = { [MAP_A] = {
    peace(1000),
    peace(2000),
    peace(500),
  } },
  mapTotals = { [MAP_A] = 2 },
  stats = { gathers = { [PEACE] = 2 }, co = {}, names = { [PEACE] = "Peacebloom" } },
  hotspots = {},
  folded = { [MAP_A] = { aggT = 2000, aggTN = 1, hsT = 0, hsTN = 0, n = 0 } },
}
NodeTrailDB = { herbs = rollback }
ns.GetHerbDB()
check(rollback.mapTotals[MAP_A] == 3,
  "11m: a t < aggT append after a clock rollback reaches mapTotals (got "
    .. tostring(rollback.mapTotals[MAP_A]) .. ")")
check(rollback.total == 3, "11m: lifetime total grows by the rollback pick only")
check(rollback.folded[MAP_A].aggT == 2000 and rollback.folded[MAP_A].aggTN == 1,
  "11m: the watermark stays at the earlier max time (aggT="
    .. tostring(rollback.folded[MAP_A].aggT) .. ", aggTN="
    .. tostring(rollback.folded[MAP_A].aggTN) .. ")")
check(rollback.stats.gathers[PEACE] == 3,
  "11m: drop-rate stats include the rollback pick (got "
    .. tostring(rollback.stats.gathers[PEACE]) .. ")")
check(rollback.maps[MAP_A][1].aggFolded == nil
    and rollback.maps[MAP_A][2].aggFolded == nil
    and rollback.maps[MAP_A][3].aggFolded == nil,
  "11m: the fold does not leave aggFolded on kept records")
ns.GetHerbDB()
check(rollback.mapTotals[MAP_A] == 3 and rollback.total == 3,
  "11m: a second load does not double-count the rollback pick (got mapT="
    .. tostring(rollback.mapTotals[MAP_A]) .. ")")

-- RecordHerb already counted the rollback pick in this session: fold
-- must not add it again.
local liveTime = 500
local savedTime = time
time = function() return liveTime end
local live = {
  schema = 2, total = 2,
  maps = { [MAP_A] = { peace(1000), peace(2000) } },
  mapTotals = { [MAP_A] = 2 },
  stats = { gathers = { [PEACE] = 2 }, co = {}, names = { [PEACE] = "Peacebloom" } },
  hotspots = {},
  folded = { [MAP_A] = { aggT = 2000, aggTN = 1, hsT = 0, hsTN = 0, n = 0 } },
}
NodeTrailDB = { herbs = live }
ns.GetHerbDB()
ns.RecordHerb(MAP_A, 0.2, 0.3, { { id = PEACE, name = "Peacebloom", count = 1 } })
time = savedTime
check(live.mapTotals[MAP_A] == 3,
  "11m: RecordHerb counts a rollback pick in the session (got "
    .. tostring(live.mapTotals[MAP_A]) .. ")")
check(live.maps[MAP_A][#live.maps[MAP_A]].t == 500,
  "11m: the recorded pick stored the rolled-back time")
ns.GetHerbDB()
check(live.mapTotals[MAP_A] == 3 and live.total == 3,
  "11m: fold does not double-count a rollback pick RecordHerb already applied (got mapT="
    .. tostring(live.mapTotals[MAP_A]) .. ")")
check(live.maps[MAP_A][1].hsFolded == nil
    and live.maps[MAP_A][2].hsFolded == nil
    and live.maps[MAP_A][3].hsFolded == nil,
  "11m: RecordHerb plus fold do not leave hsFolded on kept records")

-- 11n. An aggFolded mark left only on a trailing t < aggT0 rollback
-- pick must not disable the t == aggT0 / aggTN skip. The list is
-- t=1000, t=2000, t=500 (marked and already in totals), then an
-- unmarked t=400; start mapT=3, aggT=2000, aggTN=1. The unmarked
-- append should reach mapTotals once (mapT 4), without re-counting
-- the watermark pick (which would give mapT 5).
local markedTrail = peace(500)
markedTrail.aggFolded = true
local markedRollback = {
  schema = 2, total = 3,
  maps = { [MAP_A] = {
    peace(1000),
    peace(2000),
    markedTrail,
    peace(400),
  } },
  mapTotals = { [MAP_A] = 3 },
  stats = { gathers = { [PEACE] = 3 }, co = {}, names = { [PEACE] = "Peacebloom" } },
  hotspots = {},
  folded = { [MAP_A] = { aggT = 2000, aggTN = 1, hsT = 0, hsTN = 0, n = 0 } },
}
NodeTrailDB = { herbs = markedRollback }
ns.GetHerbDB()
check(markedRollback.mapTotals[MAP_A] == 4,
  "11n: a mark only on a trailing t < aggT rollback pick does not disable the aggTN skip (got mapT="
    .. tostring(markedRollback.mapTotals[MAP_A]) .. ")")
check(markedRollback.total == 4,
  "11n: lifetime total grows by the unmarked append only")
check(markedRollback.folded[MAP_A].aggT == 2000 and markedRollback.folded[MAP_A].aggTN == 1,
  "11n: the watermark stays at the earlier max time (aggT="
    .. tostring(markedRollback.folded[MAP_A].aggT) .. ", aggTN="
    .. tostring(markedRollback.folded[MAP_A].aggTN) .. ")")
check(markedRollback.maps[MAP_A][1].aggFolded == nil
    and markedRollback.maps[MAP_A][2].aggFolded == nil
    and markedRollback.maps[MAP_A][3].aggFolded == nil
    and markedRollback.maps[MAP_A][4].aggFolded == nil,
  "11n: the fold does not leave aggFolded on kept records")
ns.GetHerbDB()
check(markedRollback.mapTotals[MAP_A] == 4 and markedRollback.total == 4,
  "11n: a second load does not double-count (got mapT="
    .. tostring(markedRollback.mapTotals[MAP_A]) .. ")")

-- 11o. stampAtOrBelow and the noTN max-time lift use the same
-- reachedWM rule, so a trailing uncounted t < aggT pick is not
-- stamped on a pre-#29 or noTN-only save and still reaches mapTotals.
local preStamp = {
  schema = 2, total = 2,
  maps = { [MAP_A] = {
    peace(1000),
    peace(2000),
    peace(500),
  } },
  mapTotals = { [MAP_A] = 2 },
  stats = { gathers = { [PEACE] = 2 }, co = {}, names = { [PEACE] = "Peacebloom" } },
  hotspots = {},
  folded = { [MAP_A] = { aggT = 2000, hsT = 0, hsTN = 0, n = 0 } },
}
NodeTrailDB = { herbs = preStamp }
ns.GetHerbDB()
check(preStamp.mapTotals[MAP_A] == 3,
  "11o: a pre-#29 save still folds a trailing uncounted t < aggT pick (got mapT="
    .. tostring(preStamp.mapTotals[MAP_A]) .. ")")
check(preStamp.total == 3, "11o: lifetime total grows by the trailing pick only")
check(preStamp.folded[MAP_A].aggT == 2000 and preStamp.folded[MAP_A].aggTN == 1,
  "11o: the pre-#29 backfill records aggTN at the watermark, not the trailing pick (aggT="
    .. tostring(preStamp.folded[MAP_A].aggT) .. ", aggTN="
    .. tostring(preStamp.folded[MAP_A].aggTN) .. ")")
ns.GetHerbDB()
check(preStamp.mapTotals[MAP_A] == 3 and preStamp.total == 3,
  "11o: a second load does not double-count the pre-#29 trailing pick (got mapT="
    .. tostring(preStamp.mapTotals[MAP_A]) .. ")")

local notnTrail = {
  schema = 2, total = 50,
  maps = { [MAP_A] = {} },
  mapTotals = { [MAP_A] = 50 },
  stats = { gathers = { [PEACE] = 50 }, co = {}, names = { [PEACE] = "Peacebloom" } },
  hotspots = {},
  folded = { [MAP_A] = { aggT = 0, hsT = 0, n = 0, noTN = 40 } },
}
for i = 1, 10 do
  notnTrail.maps[MAP_A][i] = peace(1000 + i)
end
notnTrail.maps[MAP_A][11] = peace(400)
NodeTrailDB = { herbs = notnTrail }
ns.GetHerbDB()
check(notnTrail.mapTotals[MAP_A] == 51,
  "11o: a noTN-only save still folds a trailing uncounted t < max-time pick (got mapT="
    .. tostring(notnTrail.mapTotals[MAP_A]) .. ")")
check(notnTrail.total == 51, "11o: lifetime total grows by the trailing noTN pick only")
check(notnTrail.folded[MAP_A].aggT == 1010,
  "11o: the noTN lift uses the kept list's max time, not the trailing rollback (got "
    .. tostring(notnTrail.folded[MAP_A].aggT) .. ")")
check(notnTrail.folded[MAP_A].aggTN == 1,
  "11o: aggTN counts the single pick at that max time (got "
    .. tostring(notnTrail.folded[MAP_A].aggTN) .. ")")
ns.GetHerbDB()
check(notnTrail.mapTotals[MAP_A] == 51 and notnTrail.total == 51,
  "11o: a second load does not double-count the noTN trailing pick (got mapT="
    .. tostring(notnTrail.mapTotals[MAP_A]) .. ")")

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("herb_history_cap_spec: ok")

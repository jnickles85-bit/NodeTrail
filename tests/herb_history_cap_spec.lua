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
--  10. the hotspot grid stays within its cell and per-cell node bounds.
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

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("herb_history_cap_spec: ok")

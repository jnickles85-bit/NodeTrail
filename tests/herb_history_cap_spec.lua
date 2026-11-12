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
--      gathers after the cap has trimmed the raw list.
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

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("herb_history_cap_spec: ok")

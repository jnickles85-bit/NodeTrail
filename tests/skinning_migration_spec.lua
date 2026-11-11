-- skinning_migration_spec.lua — t_e3ea3698 (store schema 1 → 2, in place).
--
-- Totals that never evict have to be born from what a schema 1 bucket already
-- holds, and the upgrade has to be invisible to the player: every corpse record
-- he had is still there, and the totals are exactly what those records
-- aggregated to at upgrade time.
--
-- The fixture below is a SCHEMA 1 bucket — the shape a build before this card
-- actually wrote into SavedVariables (records keyed by corpse GUID, an `order`
-- ring, a store-wide `counts`, no per-creature table at all). Nothing here
-- hand-writes a schema 2 shape: the upgrade is the thing under test.
--
-- What this pins:
--   1. the READ path upgrades too (a player who only hovers a beast, never
--      records another corpse, still gets his history back);
--   2. the upgrade keeps every record and stamps schema 2;
--   3. the seeded totals equal the hand-derived aggregation of those records —
--      and NOT the store-wide `counts`, which cover corpses the ring already
--      dropped (kills = 1125 vs 6 records is the live shape);
--   4. seeding runs EXACTLY once: a second load of the same saved table does
--      not double-count (this is what the schema marker is for);
--   5. a bucket with no records gains no phantom totals, is not discarded, and
--      keeps its own store-wide counts untouched.
--
-- RED before the change: a schema 1 bucket is left at schema 1 with no totals
-- table, so sections 1-4 report every missing total and the marker checks fail.
local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end
local function onlyIf(cond, why, fn)
  if not cond then
    check(false, why)
    return
  end
  fn()
end

-- ── the client ──────────────────────────────────────────────────────────
GetTime = function() return 500 end
GetUnitName = function(u) if u == "player" then return "Mightie" end return nil end
GetRealmName = function() return "Forever" end
local KEY = "Mightie-Forever"

-- ── load (a fresh package per boot, exactly like /reload) ───────────────
local FILES = {
  "Modules/NodeTrail/Data/SkinHints.lua",
  "Modules/Skinning/Record.lua",   -- the TOC loads NodeTrail's files first
}

local function boot()
  local pkg = {}
  for _, f in ipairs(FILES) do
    local path = root .. "/MightiePack/" .. f
    local chunk, err = loadfile(path)
    check(chunk ~= nil, "loadfile " .. f .. ": " .. tostring(err))
    if chunk then
      local ok, e = pcall(chunk, "MightiePack", pkg)
      check(ok, "load " .. f .. ": " .. tostring(e))
    end
  end
  local ns = type(pkg.NodeTrail) == "table" and pkg.NodeTrail or {}
  local sk = type(pkg.Skinning) == "table" and pkg.Skinning or {}
  return pkg, ns.SkinHints, sk.Recorder
end

-- ════════════════════════════════════════════════════════════════════════
-- The fixture: what a schema 1 build stored
-- ════════════════════════════════════════════════════════════════════════
--   3124  Scorpid Worker   4 corpses: 3 killed+skinned (2934 x1, x2, x1),
--                          1 killed but never skinned (corpse item 7100)
--   3125  Clattering Scorpid 2 corpses: 1 killed+skinned (2319 x2, one window),
--                          1 window with NO successful cast behind it and NO
--                          window counter (an older record: its items are the
--                          only evidence of the window, which the old
--                          aggregate counted — the "110% on a 10-corpse
--                          sample" shape the panel has to keep guarding)
--
-- Hand-derived, and that is the point — a spec that re-implemented the
-- aggregation would agree with the code however wrong both were:
--   3124: corpses 4, kills 4, skinned 3, skinWindows 3, 2934 count 4 seen 3
--   3125: corpses 2, kills 1, skinned 1, skinWindows 2, 2319 count 3 seen 2
local function item(id, qty, name)
  return { itemID = id, quantity = qty, name = name, quality = 1,
    itemLink = "|cff1eff00|Hitem:" .. id .. "|h[" .. name .. "]|h|r" }
end

local GUIDS = {
  w1 = "Creature-0-7072-1-48-3124-0000000000A1",
  w2 = "Creature-0-7072-1-48-3124-0000000000A2",
  w3 = "Creature-0-7072-1-48-3124-0000000000A3",
  w4 = "Creature-0-7072-1-48-3124-0000000000A4",
  s1 = "Creature-0-7072-1-48-3125-0000000000B1",
  s2 = "Creature-0-7072-1-48-3125-0000000000B2",
}

local function fixture()
  return {
    schema = 1,
    order = { GUIDS.w1, GUIDS.w2, GUIDS.w3, GUIDS.w4, GUIDS.s1, GUIDS.s2 },
    unclassified = {},
    counts = {
      kills = 1125, corpseWindows = 641, skinWindows = 9, skinCasts = 9,
      unattributedWindows = 0,
    },
    records = {
      [GUIDS.w1] = {
        guid = GUIDS.w1, creatureID = 3124, name = "Scorpid Worker",
        killObserved = true, diedAt = 10, map = 1411, x = 0.4, y = 0.5,
        zone = "Desolace", skinned = true, skinSpellID = 8613,
        skinLootOpens = 1, skinItems = { item(2934, 1, "Ruined Leather Scraps") },
        corpseItems = {}, corpseLootOpens = 0,
      },
      [GUIDS.w2] = {
        guid = GUIDS.w2, creatureID = 3124, name = "Scorpid Worker",
        killObserved = true, diedAt = 20, map = 1411, x = 0.41, y = 0.51,
        zone = "Desolace", skinned = true, skinSpellID = 8613,
        skinLootOpens = 1, skinItems = { item(2934, 2, "Ruined Leather Scraps") },
        corpseItems = {}, corpseLootOpens = 0,
      },
      [GUIDS.w3] = {
        guid = GUIDS.w3, creatureID = 3124, name = "Scorpid Worker",
        killObserved = true, diedAt = 30, map = 1411, x = 0.42, y = 0.52,
        zone = "Desolace", skinned = true, skinSpellID = 8613,
        skinLootOpens = 1, skinItems = { item(2934, 1, "Ruined Leather Scraps") },
        corpseItems = {}, corpseLootOpens = 0,
      },
      [GUIDS.w4] = {
        guid = GUIDS.w4, creatureID = 3124, name = "Scorpid Worker",
        killObserved = true, diedAt = 40, map = 1411, x = 0.43, y = 0.53,
        zone = "Desolace", skinned = false,
        skinItems = {}, corpseLootOpens = 1,
        corpseItems = { item(7100, 1, "Scorpid Blood") },
      },
      [GUIDS.s1] = {
        guid = GUIDS.s1, creatureID = 3125, name = "Clattering Scorpid",
        killObserved = true, diedAt = 50, map = 1411, x = 0.5, y = 0.6,
        zone = "Desolace", skinned = true, skinSpellID = 8613,
        skinLootOpens = 1, skinItems = { item(2319, 2, "Medium Leather") },
        corpseItems = {}, corpseLootOpens = 0,
      },
      [GUIDS.s2] = {
        guid = GUIDS.s2, creatureID = 3125, name = "Clattering Scorpid",
        killObserved = false, firstSeenAt = 60, map = 1411, x = 0.51, y = 0.61,
        zone = "Desolace", skinned = false,
        skinItems = { item(2319, 1, "Medium Leather") },
        corpseItems = {}, corpseLootOpens = 0,
      },
    },
  }
end

local function recordCount(bucket)
  local n = 0
  for _ in pairs(bucket.records or {}) do n = n + 1 end
  return n
end

-- A stable signature of every record, so "no record was lost or rewritten"
-- is one comparison instead of six field checks per record.
local function recordSignature(bucket)
  local out = {}
  for guid, rec in pairs(bucket.records or {}) do
    local skins = {}
    for _, it in ipairs(rec.skinItems or {}) do
      skins[#skins + 1] = tostring(it.itemID) .. "x" .. tostring(it.quantity)
    end
    table.sort(skins)
    out[#out + 1] = table.concat({
      guid, tostring(rec.creatureID), tostring(rec.killObserved),
      tostring(rec.skinned), tostring(rec.skinLootOpens),
      tostring(rec.diedAt), tostring(rec.map), tostring(rec.x), tostring(rec.y),
      tostring(rec.name), table.concat(skins, "+"),
    }, "|")
  end
  table.sort(out)
  return table.concat(out, ";")
end

local function totalsSignature(bucket)
  local rows = {}
  for cid, row in pairs(type(bucket.creatures) == "table" and bucket.creatures or {}) do
    local items = {}
    for id, cell in pairs(row.skin or {}) do
      items[#items + 1] = ("%d:%d:%d"):format(id, cell.count or 0, cell.seen or 0)
    end
    table.sort(items)
    rows[#rows + 1] = ("%d|c%d|k%d|s%d|w%d|%s"):format(cid, row.corpses or 0,
      row.kills or 0, row.skinned or 0, row.skinWindows or 0, table.concat(items, ","))
  end
  table.sort(rows)
  return table.concat(rows, " ")
end

local function skinItem(agg, id)
  for _, it in ipairs((type(agg) == "table" and agg.skin) or {}) do
    if it.itemID == id then return it end
  end
  return nil
end

local function rowHas(rows, text)
  for _, r in ipairs(rows or {}) do
    if r.left == text then return true end
  end
  return false
end

-- ════════════════════════════════════════════════════════════════════════
-- 1. The READ path upgrades: a hover on a schema 1 save gets the history back
-- ════════════════════════════════════════════════════════════════════════
local bucket = fixture()
local sigBefore = recordSignature(bucket)
local countBefore = recordCount(bucket)

NodeTrailDB = { skinning = { enabled = true, schema = 1, chars = { [KEY] = bucket } } }
local pkg1, H1, R1 = boot()

onlyIf(type(R1) == "table" and type(H1) == "table",
  "1: the recorder or the panel did not load — the whole upgrade section is skipped",
  function()
    check(countBefore == 6, "1: the fixture holds 6 corpse records (got "
      .. countBefore .. ")")

    local agg = H1.Aggregate(3124)   -- the beast panel's own entry point
    check(type(agg) == "table", "1: the aggregate answers on a schema 1 save")
    check(bucket.schema == 2,
      "1: hovering upgraded the bucket to schema 2 (got " .. tostring(bucket.schema) .. ")")
    check(recordCount(bucket) == countBefore,
      "1: no record was lost by the upgrade (" .. recordCount(bucket) .. " after, "
      .. countBefore .. " before)")
    check(recordSignature(bucket) == sigBefore,
      "1: no record was rewritten by the upgrade (skin items, cast, position kept)")
    check(type(bucket.creatures) == "table",
      "1: the bucket now carries the per-creature totals table")

    if type(agg) == "table" then
      check(agg.records == 4, "1: corpus 3124 has 4 corpses (got "
        .. tostring(agg.records) .. ")")
      check(agg.kills == 4, "1: 4 observed deaths (got " .. tostring(agg.kills) .. ")")
      check(agg.skinned == 3, "1: 3 skinned corpses (got " .. tostring(agg.skinned) .. ")")
      check(agg.skinWindows == 3, "1: 3 skin windows (got "
        .. tostring(agg.skinWindows) .. ")")
      local hides = skinItem(agg, 2934) or {}
      check(hides.count == 4, "1: 2934 total quantity 1+2+1 = 4 (got "
        .. tostring(hides.count) .. ")")
      check(hides.seen == 3, "1: 2934 seen on 3 corpses (got " .. tostring(hides.seen) .. ")")
      check(skinItem(agg, 7100) == nil, "1: the corpse item never enters the skin totals")
    end

    local agg2 = H1.Aggregate(3125)
    if type(agg2) == "table" then
      check(agg2.records == 2, "1: 3125 has 2 corpses (got " .. tostring(agg2.records) .. ")")
      check(agg2.kills == 1, "1: only one of them was a death we observed (got "
        .. tostring(agg2.kills) .. ")")
      check(agg2.skinned == 1, "1: one successful cast (got " .. tostring(agg2.skinned) .. ")")
      check(agg2.skinWindows == 2,
        "1: a window with no counter still counts as a window (got "
        .. tostring(agg2.skinWindows) .. ")")
      local leather = skinItem(agg2, 2319) or {}
      check(leather.count == 3, "1: 2319 total 2+1 = 3 (got " .. tostring(leather.count) .. ")")
      check(leather.seen == 2, "1: 2319 seen on 2 corpses (got " .. tostring(leather.seen) .. ")")
    end

    -- The player-facing line, from the upgraded totals.
    local rows = H1.Rows(3124, "Scorpid Worker")
    check(rowHas(rows, "kills seen: 4 · skinned: 3"),
      "1: the panel states the upgraded totals")

    -- The store-wide counts cover corpses the ring already dropped; they are
    -- NOT a source of per-creature totals and must not have been used as one.
    check(bucket.counts and bucket.counts.kills == 1125,
      "1: the store-wide counts are left as the player's save had them (got "
      .. tostring(bucket.counts and bucket.counts.kills) .. ")")
  end)

-- ════════════════════════════════════════════════════════════════════════
-- 2. Seeding runs exactly once (the marker is what guarantees it)
-- ════════════════════════════════════════════════════════════════════════
onlyIf(type(R1) == "table" and type(R1.Upgrade) == "function",
  "2: R:Upgrade is absent — this commit cannot upgrade a schema 1 bucket at all",
  function()
    local afterFirst = totalsSignature(bucket)
    check(afterFirst ~= "", "2: the upgrade produced at least one totals row")

    -- The write path, twice more in the same session.
    R1:GetDB()
    R1:GetDB()
    check(totalsSignature(bucket) == afterFirst,
      "2: a second load in the same session does not double-count ("
      .. totalsSignature(bucket) .. " vs " .. afterFirst .. ")")
    check(recordCount(bucket) == countBefore, "2: and still no record was lost")

    -- A /reload: a brand new package reading the SAME saved table.
    local _, H2, R2 = boot()
    check(type(R2) == "table", "2: the second boot loaded the recorder")
    local agg = H2.Aggregate(3124)
    check(type(agg) == "table" and agg.records == 4,
      "2: after a reload the totals are still 4 corpses (got "
      .. tostring(type(agg) == "table" and agg.records) .. ")")
    check(totalsSignature(bucket) == afterFirst,
      "2: a reload does not double-count (" .. totalsSignature(bucket) .. " vs "
      .. afterFirst .. ")")
    check(bucket.schema == 2, "2: the marker survives the reload")
  end)

-- ════════════════════════════════════════════════════════════════════════
-- 3. A bucket with no records gains no phantom totals and is not discarded
-- ════════════════════════════════════════════════════════════════════════
local empty = {
  schema = 1, records = {}, order = {}, unclassified = {},
  counts = { kills = 1125, corpseWindows = 641, skinWindows = 0, skinCasts = 0,
    unattributedWindows = 0 },
}
NodeTrailDB = { skinning = { enabled = true, schema = 1, chars = { [KEY] = empty } } }
local _, H3, R3 = boot()

onlyIf(type(R3) == "table",
  "3: the recorder did not load — the empty-bucket section is skipped",
  function()
    local agg = H3.Aggregate(3124)
    check(type(agg) == "table" and agg.records == 0,
      "3: an empty schema 1 bucket seeds no observation (got "
      .. tostring(type(agg) == "table" and agg.records) .. ")")
    check(empty.schema == 2,
      "3: the empty bucket is still upgraded (got " .. tostring(empty.schema) .. ")")
    check(type(NodeTrailDB.skinning.chars[KEY]) == "table",
      "3: the bucket itself was never discarded")
    local rows = {}
    for cid in pairs(type(empty.creatures) == "table" and empty.creatures or {}) do
      rows[#rows + 1] = tostring(cid)
    end
    check(#rows == 0,
      "3: no phantom totals row was invented (" .. #rows .. " row(s): "
      .. table.concat(rows, ",") .. ")")
    check(empty.counts and empty.counts.kills == 1125,
      "3: the store-wide counts were not turned into per-creature totals (got "
      .. tostring(empty.counts and empty.counts.kills) .. ")")
    local lines = H3.Rows(3124, "Scorpid Worker")
    check(rowHas(lines, "no observations here yet"),
      "3: the panel says there is nothing yet, instead of zeros dressed as data")
  end)

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("skinning_migration_spec: ok")

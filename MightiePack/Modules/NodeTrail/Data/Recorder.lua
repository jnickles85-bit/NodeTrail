local _, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

local R = {}
ns.Recorder = R

R.HERB_SPELL_IDS = { [2366] = true, [2368] = true, [3570] = true, [11993] = true }
R.PENDING_WINDOW = 5
R.SCHEMA = 2

function ns.GetHerbDB()
  if type(NodeTrailDB) ~= "table" then
    ns.GetDB()
  end
  if type(NodeTrailDB.herbs) ~= "table" then
    NodeTrailDB.herbs = {
      schema = R.SCHEMA,
      total = 0,
      maps = {},
      mapTotals = {},
      stats = { gathers = {}, co = {}, names = {} },
      hotspots = {},
      folded = {},
    }
  end
  if type(NodeTrailDB.herbs.maps) ~= "table" then
    NodeTrailDB.herbs.maps = {}
  end
  if type(NodeTrailDB.herbs.total) ~= "number" then
    NodeTrailDB.herbs.total = 0
  end
  ns.UpgradeHerbDB(NodeTrailDB.herbs)
  return NodeTrailDB.herbs
end


-- ── schema 2: bounded raw samples, unbounded aggregates ───────────────
-- NodeTrailDB.herbs.maps[mapID] stays an array of raw picks (x, y, t,
-- items, optional node) so route/density and an open herb PR that does
-- not touch this store can keep reading the same shape. What changes is
-- how far back the array reaches.
--
-- MAX_SAMPLES_PER_MAP is the per-map cap on those raw picks. Newest
-- samples are kept; older ones leave the array and are folded into a
-- compact per-map hotspot grid (db.hotspots). The number is 2,000
-- because that is the bound the audit recommended for this list
-- (~2,000 newest per map). Density routes are built from that newest
-- raw window only; they do not yet read hotspot cells (that is left
-- for a later "Find a resource" / density improvement). The cap is
-- well above the 40 stops a density route already uses. It is not a
-- claim about node spawn counts or respawn timers.
--
-- Lifetime history is not wiped. db.total, db.mapTotals[mapID], and
-- db.stats (the personal drop-rate numbers the tooltip walks) grow
-- with every pick and are never evicted. The hotspot grid is never
-- evicted either, like those aggregates; only its shape is bounded
-- (a fixed cell size, a hard cap on cells per map and node keys per
-- cell). A schema 1 save is migrated in place: aggregates are
-- recomputed from every raw record that is still in the file, trimmed
-- picks are folded into hotspots, a per-map folded marker is written,
-- the schema marker is stamped last, and only then are oversized lists
-- replaced. A crash before the stamp leaves schema < 2 and the raw
-- lists intact, so a retry recomputes from the same records (replace,
-- not increment — no per-record contribution stamp). A second load
-- after the stamp does not re-seed from the (now shorter) raw lists.
-- A newer (numeric) schema is never downgraded and is not trimmed by
-- this build, which cannot know that shape. A non-numeric schema is
-- treated as unknown and left alone.
--
-- The per-map folded marker (db.folded[mapID] = {aggT, aggTN, hsT,
-- hsTN, n}) is the downgrade round-trip guard. An older build may
-- reset the schema stamp, re-attach previously trimmed raw picks,
-- or append new ones without updating mapTotals/stats. Aggregates
-- use a watermark plus count (aggT / aggTN) for kept records, so
-- SavedVariables do not grow a mark on every raw pick. Mid-loop
-- crash stamps (rec.aggFolded) are only a first-pass retry aid:
-- historical picks with t < aggT are skipped, and anyMarked only
-- gates the t == aggT aggTN skip, so an unmarked older pick is not
-- re-counted when a same-second neighbour is still marked. A pick
-- appended after a clock rollback (t < aggT, at the end of the list)
-- is still folded into mapTotals when the list is longer than the
-- already-counted kept records; a second pass does not double-count.
-- After a pass finishes, the stamps are cleared. Fold
-- idempotency for hotspots is a
-- per-record mark (rec.hsFolded = true), set as soon as a pick is
-- folded, so a crash mid-loop, a second live trim, or two picks
-- that share a timestamp cannot skip or double-count. When a
-- downgrade re-attaches the trimmed prefix without the mark, the
-- evicted prefix has no hsFolded stamps: unmarked picks with t <
-- hsT were already folded, and at t == hsT only the first hsTN of
-- them are treated as already folded (further same-second siblings
-- are new). A mid-loop retry has at least one mark, so remaining
-- same-second siblings are still folded. Nothing is double-counted
-- or dropped from lifetime totals.
R.MAX_SAMPLES_PER_MAP = 2000
-- 2% of normalized map width (0..1). A map is at most 50×50 cells,
-- so HOTSPOT_MAX_CELLS is the natural bound of the grid, not a trim.
R.HOTSPOT_CELL = 0.02
R.HOTSPOT_BINS = 50
R.HOTSPOT_MAX_CELLS = 50 * 50
R.HOTSPOT_MAX_NODES = 32

local function emptyHerbStats()
  return { gathers = {}, co = {}, names = {} }
end

-- Fold one raw pick into the tooltip aggregates. Mirrors GetPersonalStats'
-- walk of a single record: a gather of primary P is a record that carried
-- P, and each unique item id on that record increments the co-count for P.
-- The first stored name for an id wins. Items without a numeric id are
-- skipped, matching the existing walk.
function R.ApplyRecordToHerbStats(stats, rec)
  if type(stats) ~= "table" or type(rec) ~= "table" then return end
  if type(stats.gathers) ~= "table" then stats.gathers = {} end
  if type(stats.co) ~= "table" then stats.co = {} end
  if type(stats.names) ~= "table" then stats.names = {} end
  local items = rec.items
  if type(items) ~= "table" then return end
  local ids, seen = {}, {}
  for i = 1, #items do
    local it = items[i]
    if type(it) == "table" and type(it.id) == "number" then
      local id = it.id
      if not seen[id] then
        seen[id] = true
        ids[#ids + 1] = id
      end
      if stats.names[id] == nil and type(it.name) == "string" and it.name ~= "" then
        stats.names[id] = it.name
      end
    end
  end
  for i = 1, #ids do
    local p = ids[i]
    stats.gathers[p] = (stats.gathers[p] or 0) + 1
    local co = stats.co[p]
    if type(co) ~= "table" then
      co = {}
      stats.co[p] = co
    end
    for j = 1, #ids do
      local q = ids[j]
      co[q] = (co[q] or 0) + 1
    end
  end
end

local function sortedMapIDs(maps)
  local keys = {}
  if type(maps) ~= "table" then return keys end
  for id in pairs(maps) do
    keys[#keys + 1] = id
  end
  table.sort(keys, function(a, b)
    local ta, tb = type(a), type(b)
    if ta == tb then
      return a < b
    end
    return ta < tb
  end)
  return keys
end

local function seedHerbStats(maps)
  local stats = emptyHerbStats()
  for _, mapID in ipairs(sortedMapIDs(maps)) do
    local list = maps[mapID]
    if type(list) == "table" then
      for i = 1, #list do
        R.ApplyRecordToHerbStats(stats, list[i])
      end
    end
  end
  return stats
end

local function seedMapTotals(maps)
  local totals = {}
  for _, mapID in ipairs(sortedMapIDs(maps)) do
    local list = maps[mapID]
    if type(list) == "table" then
      totals[mapID] = #list
    end
  end
  return totals
end

local function rawPickCount(maps)
  local n = 0
  if type(maps) ~= "table" then return n end
  for _, list in pairs(maps) do
    if type(list) == "table" then
      n = n + #list
    end
  end
  return n
end

-- Keep the newest maxN entries; older ones are dropped from the array only.
-- Built as a new array and assigned by the caller so a mid-loop
-- table.remove cannot leave a half-trimmed list if a crash hits.
function R.TrimHerbList(list, maxN)
  if type(list) ~= "table" then return list end
  if type(maxN) ~= "number" or maxN < 0 then return list end
  local n = #list
  if n <= maxN then return list end
  local start = n - maxN + 1
  local kept = {}
  for i = start, n do
    kept[#kept + 1] = list[i]
  end
  return kept
end

local function recTime(rec)
  if type(rec) ~= "table" then return nil end
  return tonumber(rec.t)
end

local function maxListTime(list)
  local m = 0
  if type(list) ~= "table" then return m end
  for i = 1, #list do
    local t = recTime(list[i])
    if t and t > m then
      m = t
    end
  end
  return m
end

local function sumMapTotals(db)
  local n = 0
  if type(db) ~= "table" or type(db.mapTotals) ~= "table" then return n end
  for _, v in pairs(db.mapTotals) do
    if type(v) == "number" then
      n = n + v
    end
  end
  return n
end

local function foldedOf(db, mapID)
  if type(db.folded) ~= "table" then
    db.folded = {}
  end
  local f = db.folded[mapID]
  if type(f) ~= "table" then
    f = { aggT = 0, aggTN = 0, hsT = 0, hsTN = 0, n = 0 }
    db.folded[mapID] = f
  end
  if type(f.aggT) ~= "number" then f.aggT = 0 end
  if type(f.aggTN) ~= "number" then f.aggTN = 0 end
  if type(f.hsT) ~= "number" then f.hsT = 0 end
  if type(f.hsTN) ~= "number" then f.hsTN = 0 end
  if type(f.n) ~= "number" then f.n = 0 end
  return f
end

local function hasFoldedMarkers(db)
  if type(db) ~= "table" or type(db.folded) ~= "table" then
    return false
  end
  for _, f in pairs(db.folded) do
    if type(f) == "table" and ((type(f.n) == "number" and f.n > 0)
      or (type(f.aggT) == "number" and f.aggT > 0)
      or (type(f.hsT) == "number" and f.hsT > 0)
      or (type(f.noTN) == "number" and f.noTN > 0)) then
      return true
    end
  end
  return false
end

-- Re-seed only when aggregates cannot already be the lifetime totals
-- (first migration, or a crash before the stamp with a partial write).
-- If mapTotals already cover every current raw list and stats exist,
-- or a folded marker is present, an older build likely just reset the
-- schema stamp: replacing aggregates from the (possibly short) raw
-- lists would drop history.
local function shouldReseedAggregates(db)
  if hasFoldedMarkers(db) then
    return false
  end
  if type(db.mapTotals) ~= "table" or type(db.stats) ~= "table"
    or type(db.stats.gathers) ~= "table" then
    return true
  end
  local any = false
  if type(db.maps) == "table" then
    for mapID, list in pairs(db.maps) do
      if type(list) == "table" then
        local mt = db.mapTotals[mapID]
        if type(mt) ~= "number" or mt < #list then
          return true
        end
        any = true
      end
    end
  end
  if not any then
    return true
  end
  if next(db.stats.gathers) == nil then
    return true
  end
  return false
end

--- Cell key for a normalized map position. Positions are clamped to
--- [0, 1] so a pick cannot mint a cell outside the 50×50 bound.
--- Coordinates may be client SECRET values; those must be recognised
--- before any conversion, and tonumber is reached only through pcall.
local function safeTonumber(v)
  if type(issecretvalue) == "function" then
    local ok, secret = pcall(issecretvalue, v)
    if ok and secret == true then
      return nil
    end
  end
  local ok, n = pcall(tonumber, v)
  if ok and type(n) == "number" then
    return n
  end
  return nil
end

function R.HerbCellKey(x, y)
  x = safeTonumber(x) or 0
  y = safeTonumber(y) or 0
  if x < 0 then x = 0 elseif x > 1 then x = 1 end
  if y < 0 then y = 0 elseif y > 1 then y = 1 end
  local bins = R.HOTSPOT_BINS
  local cell = R.HOTSPOT_CELL
  local cx = math.floor(x / cell)
  local cy = math.floor(y / cell)
  if cx >= bins then cx = bins - 1 end
  if cy >= bins then cy = bins - 1 end
  if cx < 0 then cx = 0 end
  if cy < 0 then cy = 0 end
  return cx .. ":" .. cy, cx, cy
end

function R.HerbCellCenter(cx, cy)
  local cell = R.HOTSPOT_CELL
  return (cx + 0.5) * cell, (cy + 0.5) * cell
end

-- Keys a later "Find a resource" query can use: the GameObject node id
-- (when present) and every item id (or name, if there is no id) on the
-- pick, so a co-loot like Swiftthistle is findable in the same cell.
local function hotspotNodeKeys(rec)
  local keys, seen = {}, {}
  local function add(k)
    if k == nil or seen[k] then
      return
    end
    seen[k] = true
    keys[#keys + 1] = k
  end
  if type(rec) ~= "table" then
    return keys
  end
  if type(rec.node) == "number" then
    add(rec.node)
  elseif type(rec.node) == "string" and rec.node ~= "" then
    add(rec.node)
  end
  local items = rec.items
  if type(items) == "table" then
    for i = 1, #items do
      local it = items[i]
      if type(it) == "table" then
        if type(it.id) == "number" then
          add(it.id)
        elseif type(it.name) == "string" and it.name ~= "" then
          add(it.name)
        end
      end
    end
  end
  return keys
end

local function gridCellCount(grid)
  local n = 0
  if type(grid) ~= "table" then return n end
  for _ in pairs(grid) do
    n = n + 1
  end
  return n
end

--- Fold one evicted raw pick into the per-map hotspot grid. The grid
--- itself is never evicted; only new cells / node keys are refused
--- once the bounds are hit (n and last still grow).
function R.FoldHerbIntoHotspots(db, mapID, rec)
  if type(db) ~= "table" or mapID == nil or type(rec) ~= "table" then
    return
  end
  if type(db.hotspots) ~= "table" then
    db.hotspots = {}
  end
  local grid = db.hotspots[mapID]
  if type(grid) ~= "table" then
    grid = {}
    db.hotspots[mapID] = grid
  end
  local key = R.HerbCellKey(rec.x, rec.y)
  local cell = grid[key]
  if type(cell) ~= "table" then
    if gridCellCount(grid) >= R.HOTSPOT_MAX_CELLS then
      key = "_"
      cell = grid[key]
      if type(cell) ~= "table" then
        cell = { n = 0, nodes = {}, last = 0 }
        grid[key] = cell
      end
    else
      cell = { n = 0, nodes = {}, last = 0 }
      grid[key] = cell
    end
  end
  cell.n = (cell.n or 0) + 1
  local ts = recTime(rec)
  if ts and ts > (tonumber(cell.last) or 0) then
    cell.last = ts
  end
  if type(cell.nodes) ~= "table" then
    cell.nodes = {}
  end
  local nks = hotspotNodeKeys(rec)
  for i = 1, #nks do
    local nk = nks[i]
    if cell.nodes[nk] ~= nil then
      cell.nodes[nk] = cell.nodes[nk] + 1
    else
      local nKeys = 0
      for _ in pairs(cell.nodes) do
        nKeys = nKeys + 1
      end
      if nKeys < R.HOTSPOT_MAX_NODES then
        cell.nodes[nk] = 1
      end
    end
  end
end

-- Apply raw picks that have not yet been counted into lifetime
-- aggregates. The first-pass and keep-list rule is the watermark
-- plus count (aggT / aggTN): two picks that share a second both
-- count, and a later load does not need a mark on every kept
-- record. rec.aggFolded is only a mid-loop crash stamp. Historical
-- picks with t < aggT0 are skipped; anyMarked only gates the
-- t == aggT0 aggTN branch, so a same-second sibling is still applied
-- after a crash and an unmarked older pick is not re-counted. A
-- trailing pick with t < aggT0 that is not yet in mapTotals (a
-- clock-rollback append) is still applied. After the pass finishes,
-- stamps are cleared. A
-- pre-#29 schema-2 save has aggT but no aggTN and no marks; that
-- is backfilled by treating t <= aggT as already counted. A
-- noTN-only marker with aggT still 0 is the same idea: the kept
-- list is already in the totals, and the watermark is lifted to
-- the list's max time. An older build may already have incremented
-- db.total for the same picks, so total is raised only when it
-- falls behind the sum of mapTotals.
local function anyAggFolded(list)
  for i = 1, #list do
    local rec = list[i]
    if type(rec) == "table" and rec.aggFolded == true then
      return true
    end
  end
  return false
end

local function clearAggFolded(list)
  for i = 1, #list do
    local rec = list[i]
    if type(rec) == "table" then
      rec.aggFolded = nil
    end
  end
end

local function hasLegacyAggMarker(f)
  return (type(f.noTN) == "number" and f.noTN > 0)
    or (type(f.n) == "number" and f.n > 0)
    or (type(f.hsT) == "number" and f.hsT > 0)
end

local function stampAtOrBelow(list, capT)
  local nAt = 0
  for i = 1, #list do
    local rec = list[i]
    if type(rec) == "table" then
      local t = recTime(rec)
      if t and t <= capT then
        rec.aggFolded = true
        if t == capT then
          nAt = nAt + 1
        end
      elseif capT == 0 then
        -- Untimed-only list, or a noTN-only marker with no times:
        -- every kept record was already counted.
        rec.aggFolded = true
      end
    end
  end
  return nAt
end

local function foldNewRawIntoAggregates(db, mapID, list)
  if type(list) ~= "table" then return end
  if type(db.stats) ~= "table" then db.stats = emptyHerbStats() end
  if type(db.mapTotals) ~= "table" then db.mapTotals = {} end
  local f = foldedOf(db, mapID)
  local anyMarked = anyAggFolded(list)
  local aggT0 = f.aggT
  local alreadyAt = f.aggTN or 0
  local skippedAt = 0
  local added = 0

  -- Backfill a main / pre-#29 schema-2 save. Do this only when no
  -- record is marked. A mid-loop crash still skips t < aggT0;
  -- anyMarked only gates the t == aggT0 aggTN skip.
  if not anyMarked then
    if aggT0 > 0 and alreadyAt == 0 then
      alreadyAt = stampAtOrBelow(list, aggT0)
      f.aggTN = alreadyAt
    elseif aggT0 == 0 and hasLegacyAggMarker(f) then
      local maxT = maxListTime(list)
      f.aggT = maxT
      aggT0 = maxT
      alreadyAt = stampAtOrBelow(list, maxT)
      f.aggTN = alreadyAt
    end
  end

  -- mapTotals already includes evicted picks (f.n) and every kept pick
  -- that was counted. A trailing t < aggT0 pick is a clock-rollback
  -- append when it appears after the watermark in list order; a
  -- downgrade that re-attaches the trimmed prefix puts those older
  -- copies back at the front, so the watermark still skips them.
  -- uncounted caps how many of those trailing picks are applied, so
  -- a pick RecordHerb already added to mapTotals is not counted twice.
  local evicted = f.n or 0
  if type(evicted) ~= "number" or evicted < 0 then evicted = 0 end
  local counted = db.mapTotals[mapID] or 0
  if type(counted) ~= "number" then counted = 0 end
  local uncounted = #list + evicted - counted
  if uncounted < 0 then uncounted = 0 end
  local reachedWM = false
  local rollbackApplied = 0

  for i = 1, #list do
    local rec = list[i]
    if type(rec) == "table" and rec.aggFolded ~= true then
      local t = recTime(rec)
      if t and t >= aggT0 then
        reachedWM = true
      end
      if t and t < aggT0 and not reachedWM then
        rec.aggFolded = true
      elseif (not anyMarked) and t and t == aggT0 and skippedAt < alreadyAt then
        skippedAt = skippedAt + 1
        rec.aggFolded = true
      elseif t and t < aggT0 then
        if rollbackApplied < uncounted then
          R.ApplyRecordToHerbStats(db.stats, rec)
          db.mapTotals[mapID] = (db.mapTotals[mapID] or 0) + 1
          added = added + 1
          rec.aggFolded = true
          rollbackApplied = rollbackApplied + 1
        else
          rec.aggFolded = true
        end
      elseif t then
        R.ApplyRecordToHerbStats(db.stats, rec)
        db.mapTotals[mapID] = (db.mapTotals[mapID] or 0) + 1
        added = added + 1
        rec.aggFolded = true
        if t > f.aggT then
          f.aggT = t
          f.aggTN = 1
        elseif t == f.aggT then
          f.aggTN = (f.aggTN or 0) + 1
        end
      end
    end
  end
  if added > 0 then
    local sum = sumMapTotals(db)
    if type(db.total) ~= "number" or db.total < sum then
      db.total = sum
    end
  end
  -- Kept raw records do not need the stamp once the watermark is
  -- current; leaving it would cost ~30 KB per full map (about
  -- 15 bytes per record for 2,000 records).
  clearAggFolded(list)
end

-- Fold evicted picks into hotspots, then replace the list. Returns
-- the (possibly new) list. Idempotency is rec.hsFolded, set as soon
-- as a pick is folded, so a crash mid-loop cannot re-fold it. The
-- raw list is only replaced after the loop. hsT is a downgrade
-- fallback for unmarked re-attached picks, not the first-pass rule.
local function foldEvictedAndTrim(db, mapID, list)
  if type(list) ~= "table" then return list end
  local maxN = R.MAX_SAMPLES_PER_MAP
  if #list <= maxN then
    return list
  end
  local f = foldedOf(db, mapID)
  local drop = #list - maxN
  -- hsT / hsTN are a downgrade fallback only when this prefix has
  -- no marks (re-attached copies). Skip t < hsT0 outright; at
  -- t == hsT0 skip only the first hsTN. A mid-loop crash leaves at
  -- least one hsFolded record, so remaining same-second siblings
  -- are folded instead of being treated as already done.
  local anyMarked = false
  local hsT0 = f.hsT
  local alreadyAt = f.hsTN or 0
  local skippedAt = 0
  for i = 1, drop do
    local rec = list[i]
    if type(rec) == "table" and rec.hsFolded == true then
      anyMarked = true
      break
    end
  end
  for i = 1, drop do
    local rec = list[i]
    -- Already-folded records (a mid-loop crash left the mark on this
    -- still-untrimmed record, or a re-attached pick kept it) are skipped.
    if type(rec) == "table" and rec.hsFolded ~= true then
      local t = recTime(rec)
      if (not anyMarked) and t and t < hsT0 then
        rec.hsFolded = true
      elseif (not anyMarked) and t and t == hsT0 and skippedAt < alreadyAt then
        skippedAt = skippedAt + 1
        rec.hsFolded = true
      else
        R.FoldHerbIntoHotspots(db, mapID, rec)
        rec.hsFolded = true
        f.n = f.n + 1
        if t and t > f.hsT then
          f.hsT = t
          f.hsTN = 1
        elseif t and t == f.hsT then
          f.hsTN = (f.hsTN or 0) + 1
        end
      end
    end
  end
  return R.TrimHerbList(list, maxN)
end

local function foldAndPruneHerbMaps(db)
  local maps = db.maps
  if type(maps) ~= "table" then return end
  for _, mapID in ipairs(sortedMapIDs(maps)) do
    local list = maps[mapID]
    if type(list) == "table" then
      foldNewRawIntoAggregates(db, mapID, list)
      maps[mapID] = foldEvictedAndTrim(db, mapID, list)
    end
  end
end

function ns.UpgradeHerbDB(db)
  if type(db) ~= "table" then return db end
  local prior = db.schema
  -- A non-numeric (and present) schema is an unknown shape. Do not
  -- migrate, trim, or stamp it.
  if prior ~= nil and type(prior) ~= "number" then
    return db
  end
  if type(prior) == "number" and prior > R.SCHEMA then
    return db
  end
  if type(db.stats) ~= "table" then
    db.stats = emptyHerbStats()
  end
  if type(db.mapTotals) ~= "table" then
    db.mapTotals = {}
  end
  if type(db.hotspots) ~= "table" then
    db.hotspots = {}
  end
  if type(db.folded) ~= "table" then
    db.folded = {}
  end
  if type(prior) ~= "number" or prior < 2 then
    if shouldReseedAggregates(db) then
      db.stats = seedHerbStats(db.maps)
      db.mapTotals = seedMapTotals(db.maps)
      local raw = rawPickCount(db.maps)
      if type(db.total) ~= "number" or db.total < raw then
        db.total = raw
      end
      if type(db.maps) == "table" then
        for _, mapID in ipairs(sortedMapIDs(db.maps)) do
          local f = foldedOf(db, mapID)
          local list = db.maps[mapID]
          f.aggT = maxListTime(list)
          local nAt = 0
          if type(list) == "table" then
            for i = 1, #list do
              local rec = list[i]
              if type(rec) == "table" and recTime(rec) == f.aggT then
                nAt = nAt + 1
              end
            end
          end
          f.aggTN = nAt
        end
      end
    end
    -- Stamp last, after folds and markers are written, so a crash
    -- retries from the intact raw lists.
    foldAndPruneHerbMaps(db)
    db.schema = 2
    return db
  end
  foldAndPruneHerbMaps(db)
  return db
end

-- Lifetime picks on one map. Falls back to the raw list length when
-- mapTotals is missing (a schema 1 table that has not been upgraded).
function ns.HerbMapTotal(mapID, db)
  db = db or (type(NodeTrailDB) == "table" and NodeTrailDB.herbs) or nil
  if mapID == nil or type(db) ~= "table" then return 0 end
  if type(db.mapTotals) == "table" and type(db.mapTotals[mapID]) == "number" then
    return db.mapTotals[mapID]
  end
  local list = db.maps and db.maps[mapID]
  if type(list) == "table" then return #list end
  return 0
end

local function nodeFilterMatch(nodes, nodeFilter)
  if nodeFilter == nil then
    return true, nil
  end
  if type(nodes) ~= "table" then
    return false, 0
  end
  local n = nodes[nodeFilter]
  if type(n) == "number" and n > 0 then
    return true, n
  end
  -- A string filter also matches tostring(id) so a caller can query
  -- "2452" the same way as 2452.
  if type(nodeFilter) == "string" or type(nodeFilter) == "number" then
    local alt = nodes[tonumber(nodeFilter) or nodeFilter] or nodes[tostring(nodeFilter)]
    if type(alt) == "number" and alt > 0 then
      return true, alt
    end
  end
  return false, 0
end

--- Read API for a later "Find a resource" feature. Returns cells on
--- mapID as {x, y, n, last, nodes, key}, sorted by count (highest
--- first). `nodes` is a shallow copy of the cell's node table, so a
--- caller cannot mutate the store. When nodeFilter (a node id, item
--- id, or name) is given, only cells that recorded that node are
--- returned and `n` is that node's count in the cell. Density routes
--- do not use this yet.
function ns.Hotspots(mapID, nodeFilter)
  local db = ns.GetHerbDB()
  local out = {}
  if mapID == nil or type(db) ~= "table" or type(db.hotspots) ~= "table" then
    return out
  end
  local grid = db.hotspots[mapID]
  if type(grid) ~= "table" then
    return out
  end
  for key, cell in pairs(grid) do
    if type(cell) == "table" then
      local ok, filtered = nodeFilterMatch(cell.nodes, nodeFilter)
      if ok then
        local cx, cy = tostring(key):match("^(%d+):(%d+)$")
        local x, y
        if cx then
          x, y = R.HerbCellCenter(tonumber(cx), tonumber(cy))
        end
        local n = cell.n or 0
        if filtered ~= nil then
          n = filtered
        end
        local nodesCopy = {}
        if type(cell.nodes) == "table" then
          for nk, nv in pairs(cell.nodes) do
            nodesCopy[nk] = nv
          end
        end
        out[#out + 1] = {
          x = x, y = y, n = n,
          last = cell.last, nodes = nodesCopy, key = key,
        }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.n == b.n then
      return tostring(a.key) < tostring(b.key)
    end
    return a.n > b.n
  end)
  return out
end

local function round4(v)
  return math.floor(v * 10000 + 0.5) / 10000
end

-- ── SECRET strings (audit for t_1ed3b421) ─────────────────────────────
-- Loot APIs can answer with a SECRET value (the skinning dump died on one).
-- A secret may be shown but not measured, matched, sliced or converted, and
-- it must never be written into SavedVariables — a secret in the herb DB
-- would be an unreadable key for every later reader. So: recognise it first,
-- and read only through pcall.
local function isSecret(v)
  if type(issecretvalue) ~= "function" then return false end
  local ok, s = pcall(issecretvalue, v)
  return ok and s == true
end

-- A value the client marked secret is dropped from the DB (nil), never
-- stored: the count and the position are what the herb record is for.
local function storable(v)
  if isSecret(v) then return nil end
  if type(v) == "string" then return v end
  return nil
end

function R:IsHerbSpell(spellID)
  if R.HERB_SPELL_IDS[spellID] then
    return true
  end
  if type(GetSpellInfo) == "function" and spellID then
    local herbName = GetSpellInfo(2366)
    local name = GetSpellInfo(spellID)
    if type(herbName) ~= "string" or type(name) ~= "string" or isSecret(herbName) or isSecret(name) then
      return false -- an unreadable name is not a match; nothing is invented
    end
    local ok, same = pcall(function() return name == herbName end)
    return ok and same == true
  end
  return false
end

function R:GetPlayerPosition()
  if type(C_Map) ~= "table" then return nil end
  if type(C_Map.GetBestMapForUnit) ~= "function" then return nil end
  if type(C_Map.GetPlayerMapPosition) ~= "function" then return nil end
  local mapID = C_Map.GetBestMapForUnit("player")
  if not mapID then return nil end
  local pos = C_Map.GetPlayerMapPosition(mapID, "player")
  if not pos then return nil end
  if type(pos.GetXY) ~= "function" then return nil end
  local x, y = pos:GetXY()
  if type(x) ~= "number" or type(y) ~= "number" then return nil end
  if x == 0 and y == 0 then return nil end
  if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  return mapID, x, y
end

function R:OnSpellSucceeded(unit, castGUID, spellID)
  if unit ~= "player" then return end
  if not self:IsHerbSpell(spellID) then return end
  local mapID, x, y = self:GetPlayerPosition()
  if not mapID then
    self.pending = nil
    return
  end
  self.pending = { mapID = mapID, x = x, y = y, at = GetTime(), spellID = spellID }
end

-- The NAME a looted slot carries (t_e27da774). The item link is the copy that
-- survives to draw time: `|cnIQ2:|Hitem:249399:...|h[Frilled Lichen]|h|r`, the
-- real name of a real reagent this client's GetItemInfo cannot answer for. The
-- slot's own name field is the fallback, and a secret one is dropped by
-- `storable` (a secret must never reach SavedVariables).
-- Data/ItemNames.lua owns the parse; this is only the call, and a harness that
-- loads the recorder alone still stores the slot's name.
local function lootedName(link, slotName)
  local IN = ns.ItemNames
  if type(IN) == "table" and type(IN.Capture) == "function" then
    local ok, name = pcall(IN.Capture, link, slotName)
    if ok and name ~= nil then
      return name
    end
  end
  return slotName
end

function R:ReadLoot()
  local items = {}
  local nodeID = nil
  local n = 0
  if type(GetNumLootItems) == "function" then
    n = GetNumLootItems()
  end
  for i = 1, n do
    local link = nil
    if type(GetLootSlotLink) == "function" then
      link = GetLootSlotLink(i)
    end
    local slotName = nil
    local qty = 1
    if type(GetLootSlotInfo) == "function" then
      local _, nm, q = GetLootSlotInfo(i)
      slotName = storable(nm)
      if type(q) == "number" then qty = q end
    end
    -- The id stays the key; the name is stored WITH it, so the panel never has
    -- to ask GetItemInfo for an id this client does not cache.
    local name = lootedName(link, slotName)
    if link or name then
      local id = nil
      if type(link) == "string" and not isSecret(link) then
        local ok, m = pcall(function() return link:match("item:(%d+)") end)
        if ok and type(m) == "string" then id = tonumber(m) end
      end
      items[#items + 1] = { id = id, name = name, count = qty }
    end
    if nodeID == nil and type(GetLootSourceInfo) == "function" then
      local guid = GetLootSourceInfo(i)
      if type(guid) == "string" and not isSecret(guid) then
        local ok, m = pcall(function()
          if not guid:match("^GameObject%-") then return nil end
          return guid:match("^GameObject%-[^%-]*%-[^%-]*%-[^%-]*%-[^%-]*%-(%d+)")
        end)
        if ok and type(m) == "string" then nodeID = tonumber(m) end
      end
    end
  end
  return items, nodeID
end

function ns.RecordHerb(mapID, x, y, items, nodeID)
  local db = ns.GetHerbDB()
  local list = db.maps[mapID]
  if not list then
    list = {}
    db.maps[mapID] = list
  end
  local entry = { x = round4(x), y = round4(y), t = time(), items = items or {} }
  if nodeID then
    entry.node = nodeID
  end
  list[#list + 1] = entry
  db.total = db.total + 1
  if type(db.mapTotals) ~= "table" then db.mapTotals = {} end
  db.mapTotals[mapID] = (db.mapTotals[mapID] or 0) + 1
  if type(db.stats) ~= "table" then
    db.stats = { gathers = {}, co = {}, names = {} }
  end
  R.ApplyRecordToHerbStats(db.stats, entry)
  local f = foldedOf(db, mapID)
  local ts = recTime(entry)
  if ts and ts > f.aggT then
    f.aggT = ts
    f.aggTN = 1
  elseif ts and ts == f.aggT then
    f.aggTN = (f.aggTN or 0) + 1
  end
  if #list > R.MAX_SAMPLES_PER_MAP then
    db.maps[mapID] = foldEvictedAndTrim(db, mapID, list)
  end
  -- t_2bc15917: a pick on the active route's map makes the line stale. This
  -- only moves a due time — the rebuild happens later, on the frame's
  -- OnUpdate, never synchronously inside the loot/gather event.
  if type(ns.RouteAuto) == "table" and type(ns.RouteAuto.SchedulePick) == "function" then
    pcall(ns.RouteAuto.SchedulePick, ns.RouteAuto, mapID)
  end
  return entry
end

function R:OnLoot()
  local p = self.pending
  if not p then return end
  self.pending = nil
  if GetTime() - p.at > self.PENDING_WINDOW then return end
  if type(IsFishingLoot) == "function" and IsFishingLoot() then return end
  local items, nodeID = self:ReadLoot()
  self.lastRecord = ns.RecordHerb(p.mapID, p.x, p.y, items, nodeID)
  return self.lastRecord
end

function R:Enable()
  if self.enabled then return end
  self.enabled = true
  ns.GetHerbDB()
  local frame = CreateFrame("Frame")
  self.frame = frame
  local function dispatch(event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
      R:OnSpellSucceeded(...)
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
      R:OnLoot()
    end
  end
  frame:SetScript("OnEvent", function(_, event, ...)
    local ok, err = pcall(dispatch, event, ...)
    if not ok then
      R._error = tostring(err)
    end
  end)
  pcall(frame.RegisterEvent, frame, "UNIT_SPELLCAST_SUCCEEDED")
  pcall(frame.RegisterEvent, frame, "LOOT_OPENED")
  pcall(frame.RegisterEvent, frame, "LOOT_READY")
end

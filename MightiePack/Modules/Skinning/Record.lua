-- Record.lua — t_80ffe952 (Skinning 2/3: the recorder).
--
-- The probe (Probe.lua) is the evidence channel; this file is the model it
-- feeds. The shape follows SKINNING-DATA-MODEL.md, with the parts that were
-- HYPOTHESIS in that document settled by the real in-client dump from build
-- 5455eea (49 steps, /mp skindiag dump, map 1411):
--
--   * UNIT_DIED fires for ordinary mobs and its ARGUMENT is the creature GUID
--     ("sk 12 UNIT_DIED k=death unit=Creature-0-7072-1-48-3124-F090F29C6F").
--     It is the kill signal; COMBAT_LOG_EVENT_UNFILTERED is a protected
--     event on this client and is never registered.
--   * Skinning is spell 8613, cast by the player (START -> SUCCEEDED -> STOP).
--   * The skin loot window is a SECOND LOOT_OPENED on the SAME corpse GUID
--     ("sk 23 LOOT_OPENED ... g=..F29C6F i=2934x1" after "sk 14 ... i=7100x1").
--     That is the documented hypothesis, now confirmed live.
--
-- One record per corpse, keyed by the corpse GUID, with the ordinary corpse
-- loot and the skinning loot as SEPARATE fields on the same record — never
-- merged, because comparing them is the whole point.
--
-- Personal observations only: counts of what was actually seen. No rate is
-- computed here and none may be rendered from this sample (see
-- ns.PersonalRate + ns.MIN_KILLS for the only formatter allowed to produce a
-- percentage, and its n>=10 floor).
--
-- Storage: skinning is NodeTrail's sub-feature, so records live under
-- NodeTrailDB.skinning (toggle: NodeTrailDB.skinning.enabled). While the
-- toggle is OFF nothing is persisted — the recorder still builds the same
-- records in a session buffer, which is exactly what /mp skindiag dump shows
-- ("diagnostics run, nothing recorded").
--
-- TWO KINDS OF MEMORY (schema 2, t_e3ea3698):
--
--   * the RING — `records`/`order`, the newest R.MAX_RECORDS corpses. It
--     evicts, by design. Unskinned kills are evicted first. A skinned
--     record with a map position is folded into the durable per-map
--     hotspot grid (store.hotspots) before it leaves the ring, so a
--     farming circle cannot be wiped by a hundred unskinnable kills.
--     Route/SkinRoute draws from the grid plus the ring.
--   * the TOTALS — `creatures[creatureID]`, every number a player is shown.
--     They accumulate for as long as the character exists and are NEVER
--     evicted. Before them every aggregate was a ring-walk, so a beast skinned
--     dozens of times printed "no observations here yet" once 100 corpses had
--     landed behind it (live desktop bucket: kills 1125, corpse windows 641,
--     records 100 — 541 corpses of history gone).
--
-- A schema 1 bucket (ring only, no totals) is upgraded IN PLACE by R:Upgrade,
-- once, guarded by the schema marker; its records are kept untouched.

local _, pkg = ...
pkg.Skinning = pkg.Skinning or {}
local ns = pkg.Skinning
local R = {}
ns.Recorder = R

-- Store schema. 1 = a ring of records and nothing else (every user-facing
-- number was aggregated from it, so a creature's history evaporated once
-- MAX_RECORDS corpses landed behind it). 2 = the same ring PLUS the
-- per-creature totals that never evict (see the totals section below); a
-- schema 1 bucket is upgraded in place, exactly once, by R:Upgrade.
R.SCHEMA = 2
R.MAX_RECORDS = 100       -- ring: the newest 100 corpses are kept
R.MAX_UNCLASSIFIED = 20   -- ring: windows we could not honestly classify
-- Durable skinning hotspots (same cell size as the herb-history grid):
-- 2% of normalized map width, a 50x50 bound, never evicted by unskinned
-- kills. Exact positions are kept per cell so the farming circle can be
-- rebuilt after the ring turns over.
R.HOTSPOT_CELL = 0.02
R.HOTSPOT_BINS = 50
R.HOTSPOT_MAX_CELLS = 50 * 50
R.HOTSPOT_MAX_NODES = 32
R.HOTSPOT_MAX_PTS = 32
R.SKIN_WINDOW = 60        -- a successful cast attributes a window within this
R.SKIN_SPELL_ID = 8613    -- live-confirmed on this client (dump sk 20)

-- ── small helpers (self-contained: this file loads without Probe/NodeTrail) ──
local function nowT()
  if type(GetTime) == "function" then return GetTime() end
  return os.clock()
end

-- ── SECRET strings (live, build c220ec7) ──────────────────────────────
-- The client hands back SECRET strings for creature names (UnitName and
-- friends) and can do so for a GUID. A secret may be SHOWN but not measured
-- (#), sliced (:sub), formatted, searched or converted — so this file never
-- does any of that to a client value: names travel to the printer in their
-- own slot (see Describe) and a value that cannot be measured is left whole.
-- Same rule as Modules/Touchstone/Probe.lua's describe().
local function isSecret(v)
  if type(issecretvalue) ~= "function" then return false end
  local ok, s = pcall(issecretvalue, v)
  return ok and s == true
end

local function safeLen(v)
  if type(v) ~= "string" then return nil end
  if isSecret(v) then return nil end
  local ok, n = pcall(function() return #v end)
  if ok and type(n) == "number" then return n end
  return nil
end

-- nil means "not measurable" (a secret): the caller omits the field instead
-- of folding a value this file would later have to measure.
local function cut(s, n)
  if s == nil or isSecret(s) then return nil end
  if type(s) ~= "string" then s = tostring(s) end
  local len = safeLen(s)
  if len == nil then return nil end
  if len <= n then return s end
  local ok, out = pcall(function() return s:sub(1, n - 2) .. ".." end)
  if ok then return out end
  return nil
end

local function round2(v)
  return math.floor(v * 100 + 0.5) / 100
end

local function round4(v)
  return math.floor(v * 10000 + 0.5) / 10000
end

local function pct3(v)
  local s = string.format("%.3f", v)
  return (s:gsub("^0", ""))
end

-- nil for a GUID that cannot be measured: the caller then shows the value
-- whole through the display channel rather than slicing it.
local function guidSuffix(g)
  if type(g) ~= "string" or isSecret(g) then return nil end
  local ok, out = pcall(function()
    local len = #g
    if len == 0 then return nil end
    if len <= 8 then return g end
    return ".." .. g:sub(len - 5)
  end)
  if ok and type(out) == "string" then return out end
  return nil
end

-- The creature (npc) entry is the SECOND-TO-LAST field of a creature GUID:
--   Creature-0-4384-618-00712-00612-0000411A2B -> 612   (the model's example)
--   Creature-0-7072-1-48-3124-F090F29C6F       -> 3124  (live, map 1411)
-- Keying on position rather than a fixed index keeps both shapes right. A
-- GUID with too few fields (a test stub, or a source the client did not
-- build) yields nil: no id is better than an invented one. A secret GUID is
-- never parsed at all.
function R.CreatureID(guid)
  if type(guid) ~= "string" or isSecret(guid) then return nil end
  local ok, id = pcall(function()
    local body = guid:match("^Creature%-(.+)$")
    if not body then return nil end
    local parts = {}
    for p in body:gmatch("[^%-]+") do parts[#parts + 1] = p end
    if #parts < 5 then return nil end
    return tonumber(parts[#parts - 1])
  end)
  if ok then return id end
  return nil
end

-- The probe's item tuples are { id, name, qty, quality, link }; the model's
-- are { itemID, name, quantity, quality, itemLink }. Convert once, here, so
-- nothing downstream has to remember two spellings.
--
-- An entry with no itemID is NOT an item: on this client the coin slot
-- arrives that way and the c220ec7 dump printed it as "?x0". It is dropped
-- here too, so neither the record nor its rendering can carry it.
local function mapItems(items)
  local out = {}
  if type(items) ~= "table" then return out end
  for i = 1, #items do
    local it = items[i]
    if type(it) == "table" then
      local itemID = it.id or it.itemID
      if type(itemID) == "number" and itemID > 0 then
        out[#out + 1] = {
          itemID = itemID,
          name = it.name,
          quantity = it.qty or it.quantity or 1,
          quality = it.quality,
          itemLink = it.link or it.itemLink,
        }
      end
    end
  end
  return out
end

-- ── SECRET-safe NAME field ────────────────────────────────────────────
-- A name field carries a name or says `unknown`. It never carries a GUID:
-- live, `record ?` and `last kill: <guid> g=..EF7D0D` both put the GUID where
-- the name belongs, because this client can answer UnitName with the GUID.
-- A secret name is returned untouched (it may be shown, never measured), so it
-- is never compared, matched or sliced here.
local GUID_PREFIXES = { "Creature", "Player", "Pet", "Vehicle", "GameObject" }

local function usableName(name, guid)
  if name == nil then return nil end
  if isSecret(name) then return name end
  if type(name) ~= "string" or name == "" then return nil end
  local ok, isGuid = pcall(function()
    if type(guid) == "string" and not isSecret(guid) and name == guid then
      return true
    end
    for _, p in ipairs(GUID_PREFIXES) do
      if name:match("^" .. p .. "%-%d") then return true end
    end
    return false
  end)
  if ok and isGuid == true then return nil end
  return name
end
R.usableName = usableName

-- The name the RECORD may print, or nil when the record has none.
function R.DisplayName(rec)
  if type(rec) ~= "table" then return nil end
  return usableName(rec.name, rec.guid)
end

local function itemList(items, cap)
  local bits = {}
  local n = type(items) == "table" and #items or 0
  if n == 0 then return "none seen" end
  local shown = math.min(n, cap or 3)
  for i = 1, shown do
    local it = items[i]
    local id = it and it.itemID
    if type(id) == "number" and id > 0 then
      bits[#bits + 1] = tostring(id) .. "x" .. tostring(it.quantity or 1)
    end
  end
  if #bits == 0 then return "none seen" end
  return table.concat(bits, ",") .. (n > shown and ("+" .. (n - shown)) or "")
end

-- ── per-window item snapshots ──────────────────────────────────────────
-- Items are stored per OPEN of the loot window, then merged, because the
-- client can report an empty window and fill the slots a moment later
-- (live: "LOOT_OPENED i=-" followed by LOOT_SLOT_CLEARED). A re-read of the
-- SAME window REPLACES that window's snapshot, so a late read can never
-- double a quantity; a genuinely re-opened corpse is a new window and adds.
R.MAX_WINDOWS = 10

local function mergeWindows(log)
  local out, byID = {}, {}
  local n = type(log) == "table" and #log or 0
  for i = 1, n do
    local w = log[i]
    local items = type(w) == "table" and w.items or nil
    for _, it in ipairs(type(items) == "table" and items or {}) do
      local have = byID[it.itemID]
      if have then
        have.quantity = (have.quantity or 1) + (it.quantity or 1)
      else
        local copy = {
          itemID = it.itemID, name = it.name, quantity = it.quantity or 1,
          quality = it.quality, itemLink = it.itemLink,
        }
        byID[it.itemID] = copy
        out[#out + 1] = copy
      end
    end
  end
  return out
end

local function windowLog(rec, kind)
  local key = (kind == "skin") and "skinWindowLog" or "corpseWindowLog"
  local log = rec[key]
  if type(log) ~= "table" then
    log = {}
    rec[key] = log
  end
  return log
end

local function pushWindow(rec, kind, items, money, t)
  local log = windowLog(rec, kind)
  log[#log + 1] = {
    at = t, items = mapItems(items), money = money, rereads = 0,
  }
  while #log > R.MAX_WINDOWS do table.remove(log, 1) end
  return log[#log]
end

-- ── per-creature totals: the numbers a player is shown (schema 2) ──────
-- THE RING IS ROUTE DATA (see the header). Nothing that answers "what does
-- this beast give ME" may be read from it any more: R.MAX_RECORDS is a window,
-- not a history. Every per-creature number accumulates HERE, keyed by
-- creatureID, and is never evicted:
--
--   store.creatures[cid] = {
--     corpses     = records this id ever produced (any evidence),
--     kills       = records whose death we observed (killObserved),
--     skinned     = records this id was observed skinned (either path, ONCE),
--     skinWindows = skin loot windows filed for this id,
--     skin        = { [itemID] = { itemID, count, seen, name } },
--   }
--
-- `count` is a total QUANTITY and `seen` is the number of CORPSES that carried
-- the item — the only denominator a percentage may use, because two hides from
-- one corpse must not read as two kills.
--
-- The ring and the totals are written by the SAME events, so they cannot
-- disagree about an observation the player made; they differ only in how far
-- back they reach.
local CREATURE_NUMBERS = { "corpses", "kills", "skinned", "skinWindows" }

local function newCreature()
  return { corpses = 0, kills = 0, skinned = 0, skinWindows = 0, skin = {} }
end

--- The totals row for one creature id, created on first use.
--- A schema 1 store has no `creatures` table at all until R:Upgrade has run.
--- @param store table  the session buffer or the character bucket
--- @param cid number   the creature entry (R.CreatureID)
--- @param create boolean|nil  create the table/row when absent
function R:CreatureRow(store, cid, create)
  if type(store) ~= "table" or type(cid) ~= "number" then return nil end
  if type(store.creatures) ~= "table" then
    if not create then return nil end
    store.creatures = {}
  end
  local row = store.creatures[cid]
  if type(row) ~= "table" then
    if not create then return nil end
    row = newCreature()
    store.creatures[cid] = row
  end
  for i = 1, #CREATURE_NUMBERS do
    local k = CREATURE_NUMBERS[i]
    if type(row[k]) ~= "number" then row[k] = 0 end
  end
  if type(row.skin) ~= "table" then row.skin = {} end
  return row
end

-- Fold ONE record's current skin item list into its creature's totals.
--
-- The list is RE-RENDERED from the window log on every read (a loot window can
-- be reported empty and be filled a moment later, and a late read REPLACES that
-- window's snapshot), so a record is not added once — its CONTRIBUTION is
-- diffed. `rec.skinContribution` is what this record has already added to the
-- totals; only the delta goes in. That keeps one corpse carrying a 3-hide
-- stack at count=3, seen=1 however many times the window is read, and it
-- survives a /reload because the snapshot travels with the record.
local function applySkinItems(row, rec)
  if type(row) ~= "table" or type(rec) ~= "table" then return end
  local list = type(rec.skinItems) == "table" and rec.skinItems or {}
  local before = type(rec.skinContribution) == "table" and rec.skinContribution or {}
  local now = {}
  for i = 1, #list do
    local it = list[i]
    local id = type(it) == "table" and it.itemID or nil
    if type(id) == "number" and id > 0 then
      local e = now[id]
      if not e then e = { count = 0, seen = 0, name = nil }; now[id] = e end
      local qty = tonumber(it.quantity) or 1
      if qty < 1 then qty = 1 end
      e.count = e.count + qty
      e.seen = e.seen + 1
      -- a SECRET name may be shown but never stored-and-measured here: the
      -- panel would have to format it (see addItems in Data/SkinHints.lua)
      if e.name == nil and type(it.name) == "string" and it.name ~= ""
        and not isSecret(it.name) then
        e.name = it.name
      end
    end
  end
  local function cell(id)
    local c = row.skin[id]
    if type(c) ~= "table" then
      c = { itemID = id, count = 0, seen = 0, name = nil }
      row.skin[id] = c
    end
    return c
  end
  local function apply(id, oldCell, newCell)
    local c = cell(id)
    local oldCount = (oldCell and oldCell.count) or 0
    local newCount = (newCell and newCell.count) or 0
    local oldSeen = (oldCell and oldCell.seen) or 0
    local newSeen = (newCell and newCell.seen) or 0
    c.count = math.max(0, (c.count or 0) + newCount - oldCount)
    c.seen = math.max(0, (c.seen or 0) + newSeen - oldSeen)
    if c.name == nil then
      c.name = (newCell and newCell.name) or (oldCell and oldCell.name)
    end
  end
  for id, e in pairs(now) do
    local was = before[id]
    if not was or was.count ~= e.count or was.seen ~= e.seen then
      apply(id, was, e)
    end
  end
  -- An id the record no longer carries is subtracted. mergeWindows only ever
  -- grows a list, so this cannot happen for a live window; it can for a
  -- hand-written or future store, and a delta is a delta.
  for id, was in pairs(before) do
    if not now[id] then apply(id, was, nil) end
  end
  rec.skinContribution = now
end

-- ── schema 1 → 2: seed the totals from the records a bucket already holds ──
-- Runs ONCE per bucket, guarded by the schema marker (R:Upgrade). The records
-- are kept EXACTLY as they are — they are the ring, and the ring is route data
-- now — and a bucket with no records gets no rows at all: no phantom totals.
-- The store-wide `counts` are deliberately NOT a source here: they cover
-- corpses the ring already dropped (kills = 1125 beside 6 records is the live
-- shape), so seeding from them would invent history for creatures we cannot
-- name. What the records prove is what the totals get.
local function seedTotals(b)
  b.creatures = {}
  for guid, rec in pairs(b.records) do
    if type(rec) == "table" then
      if type(rec.guid) ~= "string" then rec.guid = guid end
      local cid = rec.creatureID
      if type(cid) == "number" then
        local row = R:CreatureRow(b, cid, true)
        row.corpses = row.corpses + 1
        if rec.killObserved == true then row.kills = row.kills + 1 end
        if rec.skinned == true then row.skinned = row.skinned + 1 end
        local opens = tonumber(rec.skinLootOpens) or 0
        if opens < 0 then opens = 0 end
        if opens > 0 then
          row.skinWindows = row.skinWindows + opens
        elseif type(rec.skinItems) == "table" and #rec.skinItems > 0 then
          -- items with no window counter (an older record): the window existed
          row.skinWindows = row.skinWindows + 1
        end
        -- also stamps rec.skinContribution, so a corpse still in the ring that
        -- gains a late skin read after the upgrade is never counted twice
        applySkinItems(row, rec)
      end
    end
  end
  return b
end

-- The window that is currently open produced a fresh read (LOOT_SLOT_CLEARED,
-- or the read just before LOOT_CLOSED). MERGE it into ITS snapshot — never
-- replace it: a live loot window can only shrink as the player takes the items
-- out, so a later read is a subset of the earlier one. Replacing is what made
-- a corpse whose window carried 5466x1,4867x1 store "none seen" once the window
-- emptied (live, ..10B81C). An item once seen in this window stays, and its
-- quantity only grows; only OUR numbers are compared (itemID, quantity).
-- With no window on the log (the recorder joined late) the read is appended.
function R:SetWindowItems(guid, kind, items, money, t)
  local rec = self:Find(guid)
  if not rec then return nil end
  local log = windowLog(rec, kind)
  local win = log[#log]
  if not win then
    pushWindow(rec, kind, items, money, t)
  else
    local fresh = mapItems(items)
    local known, byID = {}, {}
    for _, it in ipairs(type(win.items) == "table" and win.items or {}) do
      local copy = {
        itemID = it.itemID, name = it.name, quantity = it.quantity or 1,
        quality = it.quality, itemLink = it.itemLink,
      }
      known[#known + 1] = copy
      byID[copy.itemID] = copy
    end
    for _, it in ipairs(fresh) do
      local have = byID[it.itemID]
      if have then
        if (it.quantity or 1) > (have.quantity or 1) then
          have.quantity = it.quantity or 1
        end
      else
        known[#known + 1] = it
        byID[it.itemID] = it
      end
    end
    win.items = known
    if type(money) == "number" and money > (tonumber(win.money) or 0) then
      win.money = money
    end
    win.rereads = (win.rereads or 0) + 1
    win.readAt = t
  end
  local field = (kind == "skin") and "skinItems" or "corpseItems"
  -- re-rendered from the window log on EVERY write, so the record always shows
  -- what the window has been seen to hold (this is what LOOT_CLOSED triggers
  -- one last time before the window goes away)
  rec[field] = mergeWindows(log)
  -- the SKIN totals follow the list the record now shows; the corpse side never
  -- enters them (the panel's subject is what skinning yields). A re-read only
  -- ever adds, and applySkinItems diffs, so a late read cannot double a count.
  if kind == "skin" then
    applySkinItems(R:CreatureRow(self:Store(), rec.creatureID, true), rec)
  end
  return rec
end

-- ── stores ───────────────────────────────────────────────────────────
-- Both stores share one shape: { schema, records, order, unclassified,
-- creatures, counts }. The session store is what /mp skindiag dump reads; the
-- DB store is where a real run lands when NodeTrailDB.skinning.enabled is on.
function R:NewStore()
  return {
    schema = R.SCHEMA,
    records = {},
    order = {},          -- creation order, newest last
    unclassified = {},
    creatures = {},      -- per creatureID totals: never evicted
    counts = {
      kills = 0, corpseWindows = 0, skinWindows = 0, skinCasts = 0,
      unattributedWindows = 0,
    },
  }
end

function R:Reset()
  self.session = self:NewStore()
  self._open = nil
  self._error = nil
  return self.session
end

-- The persist target. Records are scoped PER CHARACTER, exactly as the data
-- model's section 6 requires: mixing an alt's three kills into this
-- character's sample would silently change every count. The bucket key is
-- Name-Realm inside NodeTrailDB.skinning (WoW saved variables are account
-- wide, so "per character" means a bucket, not a new variable).
--
-- Bootstrap is lazy and additive: a NodeTrailDB written before this file
-- existed keeps every key it already has, and `.enabled` (NodeTrail's
-- sub-toggle) is never written here — NodeTrail owns it.
function R.CharKey()
  local name, realm = nil, nil
  if type(GetUnitName) == "function" then
    local ok, n = pcall(GetUnitName, "player", true)
    -- the secret check comes FIRST: comparing or measuring a secret raises
    if ok and type(n) == "string" and not isSecret(n) and n ~= "" then name = n end
  end
  if type(GetRealmName) == "function" then
    local ok, r = pcall(GetRealmName)
    if ok and type(r) == "string" and not isSecret(r) and r ~= "" then realm = r end
  end
  if name and realm then return name .. "-" .. realm end
  return name or "player"
end

-- The bucket's basic shape, filled in key by key: a NodeTrailDB written before
-- this file existed keeps every key it already has, and a key of the wrong type
-- is repaired rather than trusted.
local STORE_COUNTS = { "kills", "corpseWindows", "skinWindows", "skinCasts",
  "unattributedWindows" }

local function shapeStore(b)
  if type(b.records) ~= "table" then b.records = {} end
  if type(b.order) ~= "table" then b.order = {} end
  if type(b.unclassified) ~= "table" then b.unclassified = {} end
  if type(b.hotspots) ~= "table" then b.hotspots = {} end
  if type(b.unpositionedEvicted) ~= "table" then b.unpositionedEvicted = {} end
  if type(b.counts) ~= "table" then b.counts = {} end
  for i = 1, #STORE_COUNTS do
    if type(b.counts[STORE_COUNTS[i]]) ~= "number" then b.counts[STORE_COUNTS[i]] = 0 end
  end
  return b
end

--- Bring a character bucket up to R.SCHEMA, IN PLACE.
---
--- Schema 1 stored a ring and nothing else, so a schema 1 bucket's per-creature
--- totals are seeded from the records it still holds (seedTotals) — and only
--- from those. The marker is stamped LAST: if seeding ever raised, the bucket
--- would still be schema 1 and be seeded again on the next load, instead of
--- looking upgraded while holding nothing.
---
--- Seeding runs exactly ONCE per bucket; the marker is the guard. A second load
--- (a /reload, or the panel and the recorder both reaching the store) can never
--- double-count. A bucket stamped by a NEWER build is never rewritten and never
--- discarded: this file cannot know how to read it.
--- @param b table  a character bucket as it came out of SavedVariables
--- @return table the same bucket, upgraded
function R:Upgrade(b)
  if type(b) ~= "table" then return nil end
  local prior = b.schema
  shapeStore(b)
  if type(prior) == "number" and prior > R.SCHEMA then
    return b
  end
  if prior ~= R.SCHEMA then
    seedTotals(b)
    b.schema = R.SCHEMA
  end
  if type(b.creatures) ~= "table" then b.creatures = {} end
  -- Fold the current ring's skinned positions into the durable grid
  -- once. The ring and the totals are kept; this never discards data.
  R.SeedSkinHotspots(b)
  return b
end

function R:GetDB()
  if type(NodeTrailDB) ~= "table" then NodeTrailDB = {} end
  local s = NodeTrailDB.skinning
  if type(s) ~= "table" then
    s = {}
    NodeTrailDB.skinning = s
  end
  if type(s.chars) ~= "table" then s.chars = {} end
  -- the store-wide marker follows the newest bucket shape this build knows
  if type(s.schema) ~= "number" or s.schema < R.SCHEMA then s.schema = R.SCHEMA end
  local key = R.CharKey()
  if type(s.chars[key]) ~= "table" then s.chars[key] = {} end
  return self:Upgrade(s.chars[key])
end

function R:IsEnabled()
  if type(NodeTrailDB) ~= "table" then return false end
  local s = NodeTrailDB.skinning
  return type(s) == "table" and s.enabled == true
end

-- Returns store, persisting. Callers use both values: the record goes to the
-- store that is active RIGHT NOW, and the dump always reads the session
-- buffer so it can show what a real run would have stored.
function R:Store()
  if self:IsEnabled() then
    return self:GetDB(), true
  end
  if type(self.session) ~= "table" then self:Reset() end
  return self.session, false
end

function R:Enable()
  self:Reset()
  return true
end

function R:Disable()
  self:Reset()
  return true
end


local function isValidFraction(v)
  return type(v) == "number" and v == v and v >= 0 and v <= 1
end

--- A record the farming circle can use: confirmed skin, with a map position.
function R.HasSkinPosition(rec)
  return type(rec) == "table"
    and rec.skinned == true
    and type(rec.map) == "number"
    and isValidFraction(rec.x)
    and isValidFraction(rec.y)
end

--- Cell key for a normalized map position. Clamped to the 50x50 grid.
function R.SkinCellKey(x, y)
  x = tonumber(x) or 0
  y = tonumber(y) or 0
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

function R.SkinCellCenter(cx, cy)
  local cell = R.HOTSPOT_CELL
  return (cx + 0.5) * cell, (cy + 0.5) * cell
end

local function gridCellCount(grid)
  local n = 0
  if type(grid) ~= "table" then return n end
  for _ in pairs(grid) do
    n = n + 1
  end
  return n
end

--- Fold one skinned, positioned record into the per-map hotspot grid.
--- Idempotent on guid: a record already in the cell is not counted twice.
function R.FoldSkinIntoHotspots(store, rec)
  if type(store) ~= "table" or not R.HasSkinPosition(rec) then
    return false
  end
  if type(store.hotspots) ~= "table" then
    store.hotspots = {}
  end
  local grid = store.hotspots[rec.map]
  if type(grid) ~= "table" then
    grid = {}
    store.hotspots[rec.map] = grid
  end
  local key = R.SkinCellKey(rec.x, rec.y)
  local cell = grid[key]
  if type(cell) ~= "table" then
    if gridCellCount(grid) >= R.HOTSPOT_MAX_CELLS then
      key = "_"
      cell = grid[key]
      if type(cell) ~= "table" then
        cell = { n = 0, nodes = {}, last = 0, pts = {} }
        grid[key] = cell
      end
    else
      cell = { n = 0, nodes = {}, last = 0, pts = {} }
      grid[key] = cell
    end
  end
  if type(cell.pts) ~= "table" then cell.pts = {} end
  if type(cell.nodes) ~= "table" then cell.nodes = {} end
  if type(cell.seen) ~= "table" then cell.seen = {} end
  -- Idempotency lives in seen, not in the capped pts list. seen grows
  -- with cell.n (one guid per counted fold) and is never trimmed by
  -- HOTSPOT_MAX_PTS, so a re-fold of a guid that missed the pts cap
  -- cannot increment n. Only the position samples are capped.
  if type(rec.guid) == "string" and rec.guid ~= "" then
    if cell.seen[rec.guid] then
      return false
    end
    cell.seen[rec.guid] = true
  end
  cell.n = (cell.n or 0) + 1
  local ts = tonumber(rec.skinCastAt) or tonumber(rec.diedAt) or tonumber(rec.firstSeenAt)
  if ts and ts > (tonumber(cell.last) or 0) then
    cell.last = ts
  end
  local nk = rec.creatureID or rec.name
  if nk ~= nil then
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
  if #cell.pts < R.HOTSPOT_MAX_PTS then
    cell.pts[#cell.pts + 1] = { x = rec.x, y = rec.y, guid = rec.guid }
  end
  return true
end

--- One-time migration: fold every skinned, positioned record still in the
--- ring into the durable grid. Never discards the ring or the totals.
--- Guarded by store.hotspotsSeeded so a second load cannot double-count.
function R.SeedSkinHotspots(store)
  if type(store) ~= "table" then
    return store
  end
  if type(store.hotspots) ~= "table" then
    store.hotspots = {}
  end
  if store.hotspotsSeeded == true then
    return store
  end
  local records = type(store.records) == "table" and store.records or {}
  local order = type(store.order) == "table" and store.order or {}
  for i = 1, #order do
    R.FoldSkinIntoHotspots(store, records[order[i]])
  end
  -- Also walk records not in order, so nothing skinned is left behind.
  local inOrder = {}
  for i = 1, #order do
    inOrder[order[i]] = true
  end
  for guid, rec in pairs(records) do
    if not inOrder[guid] then
      R.FoldSkinIntoHotspots(store, rec)
    end
  end
  store.hotspotsSeeded = true
  return store
end

--- Count a skinned record that left the ring without a map position
--- (it cannot be folded). Per-map (`unpositionedEvicted[mapID]`; a
--- missing map uses the key `"_"`). Idempotent on guid so a crash
--- retry cannot increment the same record twice.
function R.CountUnpositionedEviction(store, rec)
  if type(store) ~= "table" or type(rec) ~= "table" or rec.skinned ~= true then
    return false
  end
  if R.HasSkinPosition(rec) then
    return false
  end
  if type(store.unpositionedEvictedGuids) ~= "table" then
    store.unpositionedEvictedGuids = {}
  end
  if type(store.unpositionedEvicted) ~= "table" then
    store.unpositionedEvicted = {}
  end
  local g = rec.guid
  if type(g) == "string" and g ~= "" then
    if store.unpositionedEvictedGuids[g] then
      return false
    end
    store.unpositionedEvictedGuids[g] = true
  end
  local mk = rec.map
  if type(mk) ~= "number" then
    mk = "_"
  end
  store.unpositionedEvicted[mk] = (store.unpositionedEvicted[mk] or 0) + 1
  return true
end

--- Evict until the ring is at MAX_RECORDS. Unskinned records (and
--- skinned records with no map position) go first. A skinned, positioned
--- record is folded into the hotspot grid before it is dropped.
function R.EvictRing(store, keepGuid)
  if type(store) ~= "table" or type(store.order) ~= "table" then
    return
  end
  if type(store.records) ~= "table" then store.records = {} end
  while #store.order > R.MAX_RECORDS do
    local evictAt = nil
    local last = #store.order
    for i = 1, last do
      local guid = store.order[i]
      if guid ~= keepGuid then
        local rec = store.records[guid]
        if not R.HasSkinPosition(rec) then
          evictAt = i
          break
        end
      end
    end
    if evictAt == nil then
      -- The ring is all durable skins; evict the oldest that is not the
      -- record we just wrote.
      for i = 1, last do
        if store.order[i] ~= keepGuid then
          evictAt = i
          break
        end
      end
    end
    if evictAt == nil then
      break
    end
    local old = store.order[evictAt]
    if not old then
      break
    end
    local rec = store.records[old]
    -- Fold (or count) first, then drop the ring entry, so a crash
    -- after the fold still leaves the record in order/records for a
    -- retry. The fold is idempotent on guid.
    if R.HasSkinPosition(rec) then
      R.FoldSkinIntoHotspots(store, rec)
    elseif type(rec) == "table" and rec.skinned == true then
      R.CountUnpositionedEviction(store, rec)
    end
    table.remove(store.order, evictAt)
    if old ~= keepGuid then
      store.records[old] = nil
    end
  end
end

-- ── the record ───────────────────────────────────────────────────────
local function place(rec, ev)
  -- position at DEATH is what the model wants; a record created from a loot
  -- window (no UNIT_DIED seen) records where the window was instead, and says
  -- so through killObserved=false.
  if ev.map then rec.map = ev.map end
  if ev.zone then rec.zone = ev.zone end
  if ev.sub then rec.sub = ev.sub end
  if type(ev.x) == "number" then rec.x = round4(ev.x) end
  if type(ev.y) == "number" then rec.y = round4(ev.y) end
end

function R:RecordFor(guid, t)
  if type(guid) ~= "string" or guid == "" then return nil end
  local store = self:Store()
  local rec = store.records[guid]
  if rec then return rec end
  rec = {
    guid = guid,
    creatureID = R.CreatureID(guid),
    firstSeenAt = t or nowT(),
    killObserved = false,
    corpseItems = {},
    skinItems = {},
    corpseLootOpens = 0,
  }
  store.records[guid] = rec
  store.order[#store.order + 1] = guid
  -- one more corpse of this creature, counted where it can never be evicted
  local row = R:CreatureRow(store, rec.creatureID, true)
  if row then row.corpses = row.corpses + 1 end
  -- Eviction drops the RECORD only. Totals stay. Skinned positions are
  -- folded into the durable hotspot grid first; unskinned kills go first.
  R.EvictRing(store, guid)
  return rec
end

function R:Find(guid)
  if type(guid) ~= "string" then return nil end
  local store = self:Store()
  return store.records[guid]
end

-- A kill: UNIT_DIED with the creature GUID as its argument, or (only as a
-- fallback for a death UNIT_DIED never reported) a dead target whose GUID is
-- not on the recorder yet. The probe suppresses the duplicate, so one GUID
-- is counted once.
function R:OnKill(ev)
  ev = ev or {}
  local rec = self:RecordFor(ev.guid, ev.t)
  if not rec then return nil end
  local store = self:Store()
  if not rec.killObserved then
    store.counts.kills = store.counts.kills + 1
    rec.killObserved = true
    local row = R:CreatureRow(store, rec.creatureID, true)
    if row then row.kills = row.kills + 1 end
  end
  rec.diedAt = ev.t
  if ev.name and rec.name == nil then rec.name = usableName(ev.name, ev.guid) end
  if rec.map == nil then place(rec, ev) end
  return rec
end

-- The target-changed fallback fires again for a corpse UNIT_DIED already
-- reported ("sk 13 TARGET_DEAD target n=Scorpid Worker g=..F29C6F" after
-- "sk 12 UNIT_DIED ... F090F29C6F"). It must not create a second death — but
-- it IS the only place this client gives the mob's NAME, so the name is
-- filled in and nothing else happens.
function R:EnrichName(guid, name)
  if name == nil then return nil end
  if not isSecret(name) and (type(name) ~= "string" or name == "") then return nil end
  local rec = self:Find(guid)
  if not rec then return nil end
  local clean = usableName(name, guid)
  if clean ~= nil and rec.name == nil then rec.name = clean end
  return rec
end

-- Ordinary corpse loot. Each OPEN is its own snapshot (see R.MAX_WINDOWS):
-- a re-opened corpse (close, re-open to take the slot you left) adds a new
-- window, while a LATE read of the same window replaces that window's list —
-- so no observed item is lost and no duplicate row or doubled quantity is
-- invented.
function R:OnCorpseLoot(ev)
  ev = ev or {}
  local rec = self:RecordFor(ev.guid, ev.t)
  if not rec then return nil end
  local store = self:Store()
  pushWindow(rec, "corpse", ev.items, ev.money, ev.t)
  rec.corpseLootOpens = (rec.corpseLootOpens or 0) + 1
  rec.corpseItems = mergeWindows(windowLog(rec, "corpse"))
  rec.corpseLootAt = ev.t
  if ev.name and rec.name == nil then rec.name = usableName(ev.name, ev.guid) end
  if rec.map == nil then place(rec, ev) end
  store.counts.corpseWindows = store.counts.corpseWindows + 1
  self._open = { guid = ev.guid, kind = "corpse", at = ev.t }
  return rec
end

-- A successful Skinning cast. The cast event carries no GUID, so the probe
-- pins it to a corpse ONLY when a real (non-empty) corpse window preceded it
-- and passes that in (t_a2f44fb2: an empty corpse window pins nothing).
--
-- With NO pin nothing is marked here, and nothing is guessed: the old code
-- fell back to "the newest corpse whose death is still inside SKIN_WINDOW",
-- which is how the empty ..0CC9AE was marked skinned with no items while the
-- corpse the player actually skinned got its window filed as corpse loot. The
-- cast is COUNTED, and the skin window that follows names its own corpse and
-- marks it (R:OnSkinLoot). A cast no window claims stays visible as a lost
-- cast in the accounting line — which is honest, and is the signal that made
-- this defect visible in the first place.
function R:OnSkinCast(ev)
  ev = ev or {}
  local store = self:Store()
  local at = ev.t or nowT()
  store.counts.skinCasts = store.counts.skinCasts + 1
  if type(ev.guid) ~= "string" or ev.guid == "" then
    return nil
  end
  local rec = self:RecordFor(ev.guid, at)
  if not rec then return nil end
  if not rec.skinned then
    local row = R:CreatureRow(store, rec.creatureID, true)
    if row then row.skinned = row.skinned + 1 end
  end
  rec.skinned = true
  rec.skinSpellID = ev.spellID or R.SKIN_SPELL_ID
  rec.skinCastAt = at
  return rec
end

-- The skin loot window: a window the probe classified as SKIN (a successful
-- 8613 cast inside the window, and no other corpse it could belong to). Each
-- open is its own snapshot for the same reason as the corpse side: the client
-- may fill the slots after LOOT_OPENED and the late read must replace, not add.
--
-- t_a2f44fb2: the WINDOW'S OWN GUID is the authority for whether the skin was
-- observed. When the probe says a successful cast claimed this window
-- (`ev.cast`), the corpse WAS skinned — loot is irrelevant to that ("it should
-- still count the skin even if i dont get loot from the kill"), so an empty
-- skin window still sets skinned = true. A window filed as skin with no cast
-- behind it (a direct caller, or a window that only looks like skin) marks
-- nothing: the cast is what makes a corpse skinned.
--
-- t_6976540d: the window ALSO increments the corpse's totals row when it marks
-- it. It used to set rec.skinned and nothing else, so a skin the probe reported
-- the normal way (unpinned cast, then this window) reached skinWindows and the
-- record but never totals.skinned — and the beast panel undercounted (live:
-- 5 Plainstriders skinned, panel said 3). The `rec.skinned` flag guards the
-- increment, so a corpse the cast path or a previous window already counted is
-- never counted twice.
function R:OnSkinLoot(ev)
  ev = ev or {}
  local rec = self:RecordFor(ev.guid, ev.t)
  if not rec then return nil end
  local store = self:Store()
  pushWindow(rec, "skin", ev.items, ev.money, ev.t)
  rec.skinItems = mergeWindows(windowLog(rec, "skin"))
  rec.skinWindowAt = ev.t
  rec.skinLootOpens = (rec.skinLootOpens or 0) + 1
  local row = R:CreatureRow(store, rec.creatureID, true)
  if ev.cast == true then
    -- A skin is counted exactly ONCE, by whichever path observed it first.
    -- After #18 the probe sends an UNPINNED cast on the normal path, and
    -- R:OnSkinCast returns early on one — so the window is the only place this
    -- corpse's skin reaches the totals. `rec.skinned` is the flag both paths
    -- agree on (and the one seedTotals sets from a schema 1 store): a corpse
    -- the cast path already counted, or a seeded one, is never counted twice.
    if not rec.skinned and row then row.skinned = row.skinned + 1 end
    rec.skinned = true
    rec.skinSpellID = ev.spellID or R.SKIN_SPELL_ID
    rec.skinCastAt = ev.castAt or ev.t
  end
  if rec.corpseClosedAt then
    rec.corpseToSkinGap = round2(ev.t - rec.corpseClosedAt)
  end
  if ev.name and rec.name == nil then rec.name = usableName(ev.name, ev.guid) end
  store.counts.skinWindows = store.counts.skinWindows + 1
  if row then
    row.skinWindows = row.skinWindows + 1
    applySkinItems(row, rec)
  end
  self._open = { guid = ev.guid, kind = "skin", at = ev.t }
  return rec
end

-- A window the probe could not honestly attribute: no loot-source GUID and no
-- death inside the fallback window, or a cast pending with nothing at all to
-- hang the window on. It is kept as unclassified and never filed into either
-- item list — and it is COUNTED, so the accounting line can say how many
-- windows went unattributed instead of losing them.
function R:OnUnclassified(ev)
  ev = ev or {}
  local store = self:Store()
  store.unclassified[#store.unclassified + 1] = {
    guid = ev.guid,
    t = ev.t,
    items = mapItems(ev.items),
    reason = ev.reason or "a cast was pending but this corpse was never seen",
  }
  store.counts.unattributedWindows = (store.counts.unattributedWindows or 0) + 1
  while #store.unclassified > R.MAX_UNCLASSIFIED do
    table.remove(store.unclassified, 1)
  end
  return store.unclassified[#store.unclassified]
end

-- A LOOT_CLOSED that survived the probe's de-duplication. Only the window it
-- actually closes is touched, which is why the duplicate close ("sk 16/sk 17")
-- can never move the gap's start point.
function R:OnLootClosed(t)
  t = t or nowT()
  local open = self._open
  self._open = nil
  if type(open) ~= "table" then return nil end
  local rec = self:Find(open.guid)
  if not rec then return nil end
  if open.kind == "corpse" then
    rec.corpseClosedAt = t
  elseif open.kind == "skin" then
    rec.skinClosedAt = t
  end
  return rec
end

-- ── rendering for /mp skindiag dump ──────────────────────────────────
function R:Last(store)
  store = store or self:Store()
  local order = store.order
  if type(order) ~= "table" then return nil end
  for i = #order, 1, -1 do
    local rec = store.records[order[i]]
    if rec then return rec end
  end
  return nil
end

-- ── which records the dump shows (t_11fc0755) ────────────────────────
-- The dump used to render R:Last(store) — ONE record — and the newest record
-- is by definition the corpse that died most recently. The live run showed
-- exactly the cost of that:
--
--   record unknown g=..BF2A02 cid=3125 kill=UNIT_DIED
--     corpse items: none seen
--     skinning cast: none
--     skin items: none seen
--     gap corpse-close->skin-open: n/a (no skin window)
--
-- on a mob that died at the LAST step of the buffer. `none seen` was true and
-- useless: the dump always showcased the one record that cannot be complete
-- yet. It now renders a small SET: the newest complete cycles first, and the
-- corpse still in flight last, where it can be seen to be in flight.
R.DUMP_RECORDS = 3
-- The horizon. A record can only still gain a window while it is the newest
-- one, and a corpse left this long without its skin window is never skinned
-- (the probe attributes a skin window to a cast; the player loots and skins
-- the mob within seconds of the kill). Past it the record is SETTLED: it is
-- shown, and it is not called `in progress`.
R.DUMP_HORIZON = 120

-- A complete cycle: the ordinary corpse window AND the skin window that
-- follows it, on this record's own GUID (the probe files a window under the
-- GUID it opened on, so one record carrying both windows IS the same corpse
-- on both). Counted from the windows actually filed, never inferred.
function R:IsComplete(rec)
  if type(rec) ~= "table" then return false end
  return (rec.corpseLootOpens or 0) > 0 and (rec.skinLootOpens or 0) > 0
end

-- The last moment this record was touched, for the horizon.
local ACTIVITY = { "firstSeenAt", "diedAt", "corpseLootAt", "corpseClosedAt",
  "skinCastAt", "skinWindowAt", "skinClosedAt" }

local function lastActivity(rec)
  local last = nil
  for _, k in ipairs(ACTIVITY) do
    local v = rec[k]
    if type(v) == "number" and (last == nil or v > last) then last = v end
  end
  return last
end

-- The set the dump renders, newest first, as { rec = <record>, state = ... }.
-- States:
--   complete        corpse window + skin window — the cycle this file records
--   in progress     the newest record, still inside the horizon: its loot
--                   windows are ahead of it, so `none seen` means `not yet`
--   no skin window  the newest record, past the horizon, never skinned: the
--                   cycle is over and no window is coming. Deliberately NOT
--                   `complete` — calling a skinless record complete would be
--                   the same false claim the newest-record dump made.
--
-- Selection: the newest incomplete record is always kept (printed last); the
-- remaining slots go to the newest complete records, scanning past incomplete
-- older ones so a run of unlooted kills cannot hide a finished cycle.
function R:DumpSet(store, limit, t)
  store = store or self:Store()
  limit = limit or R.DUMP_RECORDS
  if type(limit) ~= "number" or limit < 1 then limit = 1 end
  local order = type(store.order) == "table" and store.order or {}
  local recs = {}
  for i = #order, 1, -1 do                       -- newest first
    local rec = store.records[order[i]]
    if type(rec) == "table" then recs[#recs + 1] = rec end
  end
  if #recs == 0 then return {} end
  local at = t or nowT()
  local pending = nil
  local newest = recs[1]
  if not self:IsComplete(newest) then
    local last = lastActivity(newest)
    local state = "in progress"
    if last ~= nil and (at - last) > R.DUMP_HORIZON then
      state = "no skin window"
    end
    pending = { rec = newest, state = state }
  end
  local out = {}
  local room = limit - (pending and 1 or 0)
  for i = 1, #recs do
    local rec = recs[i]
    if rec ~= (pending and pending.rec) and self:IsComplete(rec) then
      if #out < room then out[#out + 1] = { rec = rec, state = "complete" } end
    end
  end
  if pending then out[#out + 1] = pending end
  return out
end

-- ── accounting ───────────────────────────────────────────────────────
-- A run must be able to say where its kills went. The old counts line said
-- "kills=15 corpse-windows=4" and nothing else, so 11 corpses were simply
-- missing with no statement that they were (live, Razor Hill). This is the
-- arithmetic behind that line, in one place, so the dump and any future
-- renderer cannot disagree about it.
--
--   kills         deaths observed (UNIT_DIED, or a dead target UNIT_DIED missed)
--   corpseWindows windows filed as ordinary corpse loot
--   skinWindows   windows filed as skinning loot
--   casts         successful Skinning casts
--   unattributed  windows that produced neither a corpse nor a skin record
--   killsNoWindow kills with no corpse window at all   = kills - (records with one)
--   castsNoWindow casts that never produced a skin window = casts - skinWindows
--
-- t_e3ea3698 note: this reconciliation is STORE-WIDE and deliberately still
-- ring-derived — it is a diagnostic for one run ("where did my kills go?"), not
-- a player-facing number, and it is unchanged by the schema 2 totals. What the
-- beast panel prints comes from store.creatures (see the totals section above),
-- so a corpse the ring has evicted can never move a number the player is shown.
function R:Accounting(store)
  store = store or self:Store()
  local c = store.counts or {}
  local kills = c.kills or 0
  local skinWindows = c.skinWindows or 0
  local casts = c.skinCasts or 0
  local withWindow = 0
  local records = type(store.records) == "table" and store.records or {}
  for _, rec in pairs(records) do
    if type(rec) == "table" and rec.killObserved == true
      and (rec.corpseLootOpens or 0) > 0 then
      withWindow = withWindow + 1
    end
  end
  local killsNoWindow = kills - withWindow
  if killsNoWindow < 0 then killsNoWindow = 0 end
  local castsNoWindow = casts - skinWindows
  if castsNoWindow < 0 then castsNoWindow = 0 end
  return {
    kills = kills,
    corpseWindows = c.corpseWindows or 0,
    skinWindows = skinWindows,
    casts = casts,
    unattributedWindows = c.unattributedWindows or 0,
    killsNoWindow = killsNoWindow,
    castsNoWindow = castsNoWindow,
  }
end

-- The accounting LINE. It has to survive the probe's print site, which
-- prefixes "Skinning skindiag: " (19 chars) before applying the 120-char cap,
-- so the line itself must stay under 101 — hence "lost" rather than a second
-- full sentence. It still reconciles: every kill is either a corpse window or
-- counted as one without, and every cast is either a skin window or counted as
-- one that produced none.
function R:AccountingLine(store)
  local a = self:Accounting(store)
  return "accounting: kills=" .. tostring(a.kills)
    .. " corpse-windows=" .. tostring(a.corpseWindows)
    .. " skin-windows=" .. tostring(a.skinWindows)
    .. " casts=" .. tostring(a.casts)
    .. " | lost kills=" .. tostring(a.killsNoWindow)
    .. " windows=" .. tostring(a.unattributedWindows)
    .. " casts=" .. tostring(a.castsNoWindow)
end

-- The lines the dump prints for the last corpse: what the RECORDER would
-- store, so the next in-game run verifies the model without a second probe.
-- Every line is kept short enough for the probe's 120-char chat cap.
--
-- CONTRACT (t_1ed3b421): a line that carries client text — the creature's
-- name, a GUID — is returned as
--     { pre = <text this file built>, name = <client text>, post = <text> }
-- and NOT as one string. The client may mark a creature name SECRET, and a
-- secret may be shown but never measured, sliced or formatted; joining it
-- into a string here is what killed the c220ec7 dump at Probe.lua:908. The
-- printer appends `name` and never measures the result. Lines with no client
-- text are plain strings.
-- One record's block. Every line is kept short enough for the probe's
-- 120-char chat cap, and the header reads its position in the set:
--   record 1 of 3 (complete) Scorpid Worker g=..B4A5F9 cid=3125 kill=UNIT_DIED
-- Lines carrying client text come back as { pre, name, post } (see Describe).
function R:RenderRecord(out, rec, i, n, state)
  -- The NAME slot says `unknown` when there is no name, and never shows the
  -- GUID: live, a GUID that arrived where a name belongs printed the corpse as
  -- "record ? g=..30C716" and, once, as the GUID twice.
  local label = "record " .. tostring(i) .. " of " .. tostring(n)
    .. " (" .. tostring(state) .. ") "
  local headPre, headName = label .. "unknown", nil
  local shownName = R.DisplayName(rec)
  if shownName ~= nil then headPre, headName = label, shownName end
  local post = ""
  local gs = guidSuffix(rec.guid)
  -- A GUID this client marks secret cannot be sliced, so it is not shortened
  -- here and not invented either: "g=unknown" says the value could not be read
  -- as text (a SECRET GUID). The name keeps the client slot (it is what a reader
  -- needs most).
  if gs then post = post .. " g=" .. gs
  elseif rec.guid ~= nil then post = post .. " g=unknown" end
  if rec.creatureID then post = post .. " cid=" .. tostring(rec.creatureID) end
  post = post .. " kill=" .. (rec.killObserved and "UNIT_DIED" or "loot-only")
  if headName ~= nil then
    out[#out + 1] = { pre = headPre, name = headName, post = post }
  else
    out[#out + 1] = headPre .. post
  end
  -- Where: on its own line. The header has to hold the position label, the
  -- creature's name (client text, never measured) and the identity fields, and
  -- all four on one line pushes a long name past the probe's 120-char cap —
  -- which truncated the label itself (live spec run: "record 2 of 3 (complete"
  -- with no closing paren). The position is not dropped, it moves one line down.
  local z = cut(rec.zone, 14)
  local where = ""
  if z then where = "z=" .. z end
  if rec.map and type(rec.x) == "number" and type(rec.y) == "number" then
    if where ~= "" then where = where .. " " end
    where = where .. tostring(rec.map) .. "@" .. pct3(rec.x) .. "," .. pct3(rec.y)
  end
  if where ~= "" then out[#out + 1] = "  where: " .. where end

  local lateRead = 0
  for _, w in ipairs(type(rec.corpseWindowLog) == "table" and rec.corpseWindowLog or {}) do
    if type(w) == "table" and (w.rereads or 0) > 0 then lateRead = lateRead + 1 end
  end
  out[#out + 1] = "  corpse items: " .. itemList(rec.corpseItems)
    .. (rec.corpseLootOpens and rec.corpseLootOpens > 1
      and (" (" .. rec.corpseLootOpens .. " windows)") or "")
    .. (lateRead > 0 and " (late read)" or "")
  local cast = "  skinning cast: "
  if rec.skinned then
    cast = cast .. "8613 ok"
  else
    cast = cast .. "none"
  end
  out[#out + 1] = cast
  out[#out + 1] = "  skin items: " .. itemList(rec.skinItems)
  if rec.corpseToSkinGap then
    out[#out + 1] = "  gap corpse-close->skin-open: "
      .. string.format("%.2fs", rec.corpseToSkinGap)
  elseif rec.skinWindowAt then
    out[#out + 1] = "  gap corpse-close->skin-open: n/a (close not seen)"
  else
    out[#out + 1] = "  gap corpse-close->skin-open: n/a (no skin window)"
  end
  return out
end

function R:Describe(store)
  store = store or self:Store()
  local out = {}
  local set = self:DumpSet(store)
  local n = #set
  if n == 0 then
    out[#out + 1] = "record: none yet (kill a skinnable, loot it, cast Skinning, loot again)"
    return out
  end
  -- "none seen" is only useful next to a record that CAN be complete. When no
  -- cycle has closed yet the dump says which one is still open, instead of
  -- letting the reader decode four `none seen` lines.
  local complete = 0
  for i = 1, n do
    if set[i].state == "complete" then complete = complete + 1 end
  end
  if complete == 0 then
    out[#out + 1] = "no complete corpse->skin cycle captured yet — kill, loot, skin one more mob"
  end
  for i = 1, n do
    R:RenderRecord(out, set[i].rec, i, n, set[i].state)
  end
  -- The counts belong to the STORE, not to a record: they print once, under
  -- the records, however many records the dump shows.
  local c = store.counts or {}
  out[#out + 1] = "counts kills=" .. tostring(c.kills or 0)
    .. " corpse-windows=" .. tostring(c.corpseWindows or 0)
    .. " skin-windows=" .. tostring(c.skinWindows or 0)
    .. " skin-casts=" .. tostring(c.skinCasts or 0)
  -- the line that makes a broken run visible: 15 kills with 4 windows is
  -- stated as 11 kills that produced none, not silently dropped.
  local acct = nil
  if type(R.AccountingLine) == "function" then acct = R.AccountingLine(self, store) end
  out[#out + 1] = acct or "accounting: unavailable"
  out[#out + 1] = "  (your own observations only - no rate is computed)"
  return out
end

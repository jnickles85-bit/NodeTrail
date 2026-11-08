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

local addonName, pkg = ...
pkg.Skinning = pkg.Skinning or {}
local ns = pkg.Skinning
local R = {}
ns.Recorder = R

R.SCHEMA = 1
R.MAX_RECORDS = 100       -- ring: the newest 100 corpses are kept
R.MAX_UNCLASSIFIED = 20   -- ring: windows we could not honestly classify
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

-- ── stores ───────────────────────────────────────────────────────────
-- Both stores share one shape: { schema, records, order, unclassified,
-- counts }. The session store is what /mp skindiag dump reads; the DB store
-- is where a real run lands when NodeTrailDB.skinning.enabled is on.
function R:NewStore()
  return {
    schema = R.SCHEMA,
    records = {},
    order = {},          -- creation order, newest last
    unclassified = {},
    counts = { kills = 0, corpseWindows = 0, skinWindows = 0, skinCasts = 0 },
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

local function shapeBucket(b)
  if type(b.schema) ~= "number" then b.schema = R.SCHEMA end
  if type(b.records) ~= "table" then b.records = {} end
  if type(b.order) ~= "table" then b.order = {} end
  if type(b.unclassified) ~= "table" then b.unclassified = {} end
  if type(b.counts) ~= "table" then
    b.counts = { kills = 0, corpseWindows = 0, skinWindows = 0, skinCasts = 0 }
  end
  for _, k in ipairs({ "kills", "corpseWindows", "skinWindows", "skinCasts" }) do
    if type(b.counts[k]) ~= "number" then b.counts[k] = 0 end
  end
  return b
end

function R:GetDB()
  if type(NodeTrailDB) ~= "table" then NodeTrailDB = {} end
  local s = NodeTrailDB.skinning
  if type(s) ~= "table" then
    s = {}
    NodeTrailDB.skinning = s
  end
  if type(s.schema) ~= "number" then s.schema = R.SCHEMA end
  if type(s.chars) ~= "table" then s.chars = {} end
  local key = R.CharKey()
  if type(s.chars[key]) ~= "table" then s.chars[key] = {} end
  return shapeBucket(s.chars[key])
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
  while #store.order > R.MAX_RECORDS do
    local old = table.remove(store.order, 1)
    if old and old ~= guid then store.records[old] = nil end
  end
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
  end
  rec.diedAt = ev.t
  if ev.name and rec.name == nil then rec.name = ev.name end
  if rec.map == nil then place(rec, ev) end
  return rec
end

-- The target-changed fallback fires again for a corpse UNIT_DIED already
-- reported ("sk 13 TARGET_DEAD target n=Scorpid Worker g=..F29C6F" after
-- "sk 12 UNIT_DIED ... F090F29C6F"). It must not create a second death — but
-- it IS the only place this client gives the mob's NAME, so the name is
-- filled in and nothing else happens.
function R:EnrichName(guid, name)
  if type(name) ~= "string" or name == "" then return nil end
  local rec = self:Find(guid)
  if not rec then return nil end
  if rec.name == nil then rec.name = name end
  return rec
end

-- Ordinary corpse loot. A re-opened corpse window (close, re-open to take the
-- slot you left) merges by itemID instead of overwriting, so no observed item
-- is ever lost and no duplicate rows are invented.
function R:OnCorpseLoot(ev)
  ev = ev or {}
  local rec = self:RecordFor(ev.guid, ev.t)
  if not rec then return nil end
  local store = self:Store()
  rec.corpseLootOpens = (rec.corpseLootOpens or 0) + 1
  local fresh = mapItems(ev.items)
  if #rec.corpseItems == 0 then
    rec.corpseItems = fresh
  else
    local byID = {}
    for _, it in ipairs(rec.corpseItems) do
      if it.itemID then byID[it.itemID] = it end
    end
    for _, it in ipairs(fresh) do
      local have = it.itemID and byID[it.itemID]
      if have then
        have.quantity = (have.quantity or 1) + (it.quantity or 1)
      else
        rec.corpseItems[#rec.corpseItems + 1] = it
      end
    end
  end
  rec.corpseLootAt = ev.t
  if ev.name and rec.name == nil then rec.name = ev.name end
  if rec.map == nil then place(rec, ev) end
  store.counts.corpseWindows = store.counts.corpseWindows + 1
  self._open = { guid = ev.guid, kind = "corpse", at = ev.t }
  return rec
end

-- A successful Skinning cast. The cast event carries no GUID, so the probe
-- pins it to the corpse the player just looted (lastSkin.guid) and passes that
-- in. With no pin (a cast before any window was seen) it falls back to the
-- newest corpse record whose death is still inside SKIN_WINDOW — and to
-- nothing at all when there is none. Never guessed.
function R:OnSkinCast(ev)
  ev = ev or {}
  local store = self:Store()
  local at = ev.t or nowT()
  local rec = nil
  if type(ev.guid) == "string" and ev.guid ~= "" then
    rec = self:RecordFor(ev.guid, at)
  else
    for i = #store.order, 1, -1 do
      local cand = store.records[store.order[i]]
      if cand and cand.diedAt and (at - cand.diedAt) <= R.SKIN_WINDOW then
        rec = cand
        break
      end
    end
  end
  store.counts.skinCasts = store.counts.skinCasts + 1
  if not rec then return nil end
  rec.skinned = true
  rec.skinSpellID = ev.spellID or R.SKIN_SPELL_ID
  rec.skinCastAt = at
  return rec
end

-- The skin loot window: SAME corpse GUID, after a successful 8613 cast. The
-- gap the card asks for is corpse-loot-CLOSED -> skin-window-OPEN, so it is
-- only computed when the corpse window's close was actually observed.
function R:OnSkinLoot(ev)
  ev = ev or {}
  local rec = self:RecordFor(ev.guid, ev.t)
  if not rec then return nil end
  local store = self:Store()
  rec.skinItems = mapItems(ev.items)
  rec.skinWindowAt = ev.t
  rec.skinLootOpens = (rec.skinLootOpens or 0) + 1
  if rec.corpseClosedAt then
    rec.corpseToSkinGap = round2(ev.t - rec.corpseClosedAt)
  end
  if ev.name and rec.name == nil then rec.name = ev.name end
  store.counts.skinWindows = store.counts.skinWindows + 1
  self._open = { guid = ev.guid, kind = "skin", at = ev.t }
  return rec
end

-- A window the probe could not honestly classify (a cast was pending but this
-- corpse's own window was never seen). It is recorded as unclassified and
-- never filed into either item list.
function R:OnUnclassified(ev)
  ev = ev or {}
  local store = self:Store()
  store.unclassified[#store.unclassified + 1] = {
    guid = ev.guid,
    t = ev.t,
    items = mapItems(ev.items),
    reason = ev.reason or "a cast was pending but this corpse was never seen",
  }
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
function R:Describe(store)
  store = store or self:Store()
  local rec = self:Last(store)
  local out = {}
  if not rec then
    out[#out + 1] = "record: none yet (kill a skinnable, loot it, cast Skinning, loot again)"
    return out
  end
  local headPre, headName = "record ?", nil
  if type(rec.name) == "string" or isSecret(rec.name) then
    headPre, headName = "record ", rec.name
  end
  local post = ""
  local gs = guidSuffix(rec.guid)
  -- A GUID this client marks secret cannot be sliced, so it is not shortened
  -- here and not invented either: "g=?" says the value could not be read as
  -- text. The name keeps the client slot (it is what a reader needs most).
  if gs then post = post .. " g=" .. gs
  elseif rec.guid ~= nil then post = post .. " g=?" end
  if rec.creatureID then post = post .. " cid=" .. tostring(rec.creatureID) end
  post = post .. " kill=" .. (rec.killObserved and "UNIT_DIED" or "loot-only")
  local z = cut(rec.zone, 14)
  if z then post = post .. " z=" .. z end
  if rec.map and type(rec.x) == "number" and type(rec.y) == "number" then
    post = post .. " " .. tostring(rec.map) .. "@" .. pct3(rec.x) .. "," .. pct3(rec.y)
  end
  if headName ~= nil then
    out[#out + 1] = { pre = headPre, name = headName, post = post }
  else
    out[#out + 1] = headPre .. post
  end
  out[#out + 1] = "  corpse items: " .. itemList(rec.corpseItems)
    .. (rec.corpseLootOpens and rec.corpseLootOpens > 1
      and (" (" .. rec.corpseLootOpens .. " windows)") or "")
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
  local c = store.counts or {}
  out[#out + 1] = "counts kills=" .. tostring(c.kills or 0)
    .. " corpse-windows=" .. tostring(c.corpseWindows or 0)
    .. " skin-windows=" .. tostring(c.skinWindows or 0)
    .. " skin-casts=" .. tostring(c.skinCasts or 0)
  out[#out + 1] = "  (your own observations only - no rate is computed)"
  return out
end

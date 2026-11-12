-- Probe.lua — t_a5f41944 (Skinning 1/3: in-client event probe)
--                 extended by t_80ffe952 (2/3: the recorder, Record.lua)
--
-- The in-client evidence channel for the
--   kill -> corpse loot -> Skinning cast -> skin loot
-- chain on Forever 16001. The card's constraints, honored here:
--
--   * capture only while toggled on (/mp skindiag); nothing is recorded
--     otherwise, so the event registration itself is the only cost
--   * /mp skindiag dump prints one line per step, hard-capped at 120
--     chars — Forever has no /run or /dump, so chat lines are the ONLY
--     evidence channel that reaches Mightie
--   * every event is registered by TRYING it — never by asking a restricted
--     namespace whether it exists; an unknown one is caught and recorded as
--     "invalid event" in the diag, never raised as an error (the same gate
--     Recipes.lua uses, t_81da8886)
--
-- SETTLED BY THE LIVE DUMP (build 5455eea, /mp skindiag dump, map 1411).
-- What was hypothesis in SKINNING-DATA-MODEL.md is now what the client does:
--
--   * UNIT_DIED fires for ordinary mobs and its argument IS the creature
--     GUID ("UNIT_DIED k=death unit=Creature-0-7072-1-48-3124-F090F29C6F").
--     COMBAT_LOG_EVENT_UNFILTERED stays unregistered: the client treats it
--     as a protected event and answers ADDON_ACTION_FORBIDDEN, isolated by
--     per-step tracing on 2026-11-07.
--   * Skinning is spell 8613 (START -> SUCCEEDED -> STOP), cast by the
--     player. On this client the 4th UNIT_SPELLCAST_* argument is the cast
--     bar name ("n=CastBar-1B595C.."), NOT the spell name, so the old
--     name-matching detector never fired and the skin window was dumped as
--     k=corpse. 8613 is therefore a CONFIRMED spell ID (P.SKIN_SPELL_IDS);
--     the name heuristic stays as a fallback for other builds.
--   * The skin loot window is a SECOND LOOT_OPENED on the SAME corpse GUID
--     ("sk 23 LOOT_OPENED ... g=..F29C6F i=2934x1" after "sk 14 ... i=7100x1"
--     on ..F29C6F) — the model's hypothesis, confirmed.
--   * LOOT_CLOSED fires twice per close (sk 16/sk 17) and
--     LOOT_SLOT_CLEARED can repeat for the same slot in the same instant
--     (sk 35/sk 36) — both are de-duplicated here, before any recorder sees
--     them, so no corpse is double counted.
--   * TARGET_DEAD (the fallback this build used while COMBAT_LOG was off the
--     table) repeats a GUID UNIT_DIED already reported (sk 13/sk 18/sk 41).
--     It is kept STRICTLY as a fallback now: a GUID already recorded as dead
--     produces no step, it only fills in the mob's name.
--
-- The classification rule the recorder codes against: a window is SKIN loot
-- when it opens on the same corpse GUID within SKIN_WINDOW seconds of a
-- successful Skinning cast. A window with a pending cast that cannot be tied
-- to a corpse we have seen is recorded as UNCLASSIFIED, never guessed into
-- either list.
--
-- t_a2f44fb2 — A SKIN COUNTS ON ITS OWN. Two things this file used to do are
-- wrong and are fixed here:
--
--   * A corpse with nothing in it still gets a LOOT_OPENED/LOOT_CLOSED pair.
--     That empty window was taken as "the corpse the player just looted" and
--     PINNED the cast to a corpse that was never skinned, which marked it
--     skinned with no items and filed the REAL skin window as corpse loot
--     (live: sk 34 empty ..0CC9AE -> cast -> sk 41 ..475CDA i=2934x1 read as
--     k=corpse). A window with NO items is never a pin.
--   * The cast was never claimed by the window that identified its corpse, so
--     nothing could correct the pin. A successful cast is now remembered until
--     a loot window CLAIMS it: an unpinned cast files no skin at cast time and
--     the window that follows -- whose own GUID is the authority -- is that
--     corpse's skin loot. Loot is irrelevant to whether the skin is recorded
--     ("it should still count the skin even if i dont get loot from the kill"),
--     and a skin window on a corpse whose death was never observed still counts.
--
-- The pin is still used, and only used, for the case where it is the only
-- evidence there will ever be: a real (non-empty) corpse window followed by a
-- successful cast and NO skin window at all.
--
-- NO SavedVariables here: the step buffer is in-memory state on this table.
-- The record shape lives in Record.lua, which persists to
-- NodeTrailDB.skinning only while NodeTrail's sub-toggle is on.

local _, pkg = ...
pkg.Skinning = pkg.Skinning or {}
local ns = pkg.Skinning
local P = {}
ns.Probe = P

-- The card's minimum event set, in the order the card lists them.
P.EVENTS = {
  "UNIT_SPELLCAST_SUCCEEDED",
  "UNIT_SPELLCAST_START",
  "UNIT_SPELLCAST_STOP",
  "LOOT_OPENED",
  "LOOT_SLOT_CLEARED",
  "LOOT_CLOSED",
  "UNIT_DIED",
  -- COMBAT_LOG_EVENT_UNFILTERED is NOT registered: the client treats it as a
  -- protected call and answers ADDON_ACTION_FORBIDDEN ("blocked from an action
  -- only available to the Blizzard UI", function=UNKNOWN) the moment it is
  -- registered, even though the registration itself reports success. Live
  -- 2026-11-07, isolated by per-step tracing. Deaths are picked up from
  -- UNIT_DIED and from the target going dead instead.
  "PLAYER_TARGET_CHANGED",
  "SKILL_LINES_CHANGED",
  "PLAYER_ENTERING_WORLD",
}

P.MAX_STEPS = 120     -- ring buffer: the dump stays short and screenshot-able
P.SKIN_WINDOW = 60    -- a Skinning cast attributes a second loot window within this many seconds
-- A GUID-less window may be attributed to the dead target only this long
-- after UNIT_SPELLCAST_SUCCEEDED. Starting bound is 3 seconds; it should
-- be live-measured on a real skin (the SUCCEEDED -> LOOT_OPENED gap). It
-- must stay much shorter than SKIN_WINDOW so a later herb, chest, or
-- fishing window cannot steal the pending cast.
P.TARGET_ATTRIB_WINDOW = 3
-- A loot window with NO source GUID is not the end of the chain: the client
-- opens the corpse window a second or two after UNIT_DIED and hands back no
-- GUID at all (live at Razor Hill, 759876.51 UNIT_DIED ..EF7D0D -> 759878.38
-- LOOT_OPENED with no GUID). The most recent death inside this many seconds
-- is that corpse. The bound is what keeps the rule from inventing a corpse out
-- of a death from a minute ago; the live gap was 1.87s.
P.DEATH_FALLBACK_WINDOW = 10
P.MAX_DEATHS = 30     -- ring buffer of recent deaths the fallback may use
-- t_a2f44fb2: successful Skinning casts awaiting the window that identifies
-- their corpse. Bounded like the death ring: a cast that no window claimed
-- inside SKIN_WINDOW simply ages out.
P.MAX_CASTS = 8
P.LINE_CAP = 120      -- hard cap on every printed line (the card says ~120)
P.MAX_ITEMS_SHOWN = 3 -- per step line (the full list stays in the step record)
-- Two copies of one event land in the same frame on this client, so GetTime()
-- is equal or one frame apart. Anything inside this many seconds is the same
-- instant for de-duplication purposes.
P.DUP_TICK = 0.1

-- CONFIRMED LIVE, not guessed: build 5455eea dumped
--   sk 19/20/21 UNIT_SPELLCAST_START/SUCCEEDED/STOP s=8613 who=player
-- for the Skinning cast. The 4th argument on this client is the cast bar name
-- ("n=CastBar-1B595C.."), so the old name-only detector could not see it —
-- which is why sk 23 was dumped as k=corpse. The ID is the primary detector;
-- the name heuristic below stays for builds that do send the name.
-- Classic ranks (1–4) plus the Forever 1.60.1.70532 IDs (foreverdiff).
-- Detection is by ID: the 4th UNIT_SPELLCAST_* argument on this client is
-- a CastBar frame name and must not be required to contain "skin".
P.SKIN_SPELL_IDS = {
  [8613] = true,    -- Skinning
  [8617] = true,    -- Skinning
  [8618] = true,    -- Skinning
  [10768] = true,   -- Skinning
  [1240952] = true, -- Forever
  [1240963] = true, -- Forever
  [1240974] = true, -- Forever
  [1240987] = true, -- Forever
}

-- state (session-only; never written to any SavedVariable)
P.capturing = false
P.steps = {}          -- ring buffer of step records (full detail, uncut)
P._seq = 0
P._events = {}        -- event -> true | "invalid event" | error string
P.lastSkin = nil      -- { spellID=, name=, at=, guid= } — guid is nil when nothing pinned it
P.lastLoot = nil      -- { src=, at=, kind=, rule=, count= } — count = items seen in that window
P.lastKill = nil      -- { guid=, name=, at= }
P._skinSpells = {}    -- spellID -> name, confirmed by name match
P._deadGuids = {}     -- guid -> t: a death already reported (TARGET_DEAD fallback gate)
P._deaths = {}        -- ring of { guid=, at=, source=, usedAt= } — the GUID-less-window fallback
P._casts = {}         -- ring of { at=, guid=, spellID=, name=, taken= } — see P:PendingCast
P._win = nil          -- the loot window that is currently OPEN: { guid=, kind=, at=, items=, money=, rereads= }
P._suppressed = {}    -- event -> count of duplicates dropped before recording
P._pendingClose = nil -- t of the LOOT_CLOSED step this window already emitted
P._slotTicks = {}     -- slot -> t of the last LOOT_SLOT_CLEARED (same-instant repeat)
P._error = nil
P.enabled = false

-- ── Data-model formatters ────────────────────────────────────────────
-- The design (SKINNING-DATA-MODEL.md) proposes that researched baselines
-- are rendered visibly distinct from personal counts, and that a
-- baseline WITHOUT a source is never displayed. These two functions ARE
-- that proposal; tests/skindiag_spec pins them so the implementation
-- card cannot drift silently.
ns.MIN_KILLS = 10     -- minimum kills before a personal rate may be shown

-- Baseline entry: { rate = 0..1 fraction, source = string (REQUIRED),
-- date = "YYYY-MM-DD" }. Returns the rendered line, or nil when it must
-- not be rendered (no source, no rate).
function ns.FormatBaseline(entry)
  if type(entry) ~= "table" then return nil end
  local rate = tonumber(entry.rate)
  if rate == nil or rate < 0 or rate > 1 then return nil end
  local source = entry.source
  if type(source) ~= "string" or source == "" then return nil end
  local out = "research: " .. math.floor(rate * 100 + 0.5) .. "% (" .. source
  if type(entry.date) == "string" and entry.date ~= "" then
    out = out .. ", " .. entry.date
  end
  return out .. ")"
end

-- Personal rate: percentage, or nil when the sample is too small to
-- show a rate at all (the design's minimum-sample rule).
function ns.PersonalRate(skins, kills)
  if type(skins) ~= "number" or type(kills) ~= "number" then return nil end
  if kills <= 0 or kills < ns.MIN_KILLS or skins < 0 or skins > kills then
    return nil
  end
  return skins / kills * 100
end

-- ── small guarded helpers (no client API is assumed to exist) ─────────
local function nowT()
  if type(GetTime) == "function" then return GetTime() end
  return os.clock()
end

-- ── SECRET strings: what this file may do with client text ────────────
-- Live, build c220ec7: the client hands back SECRET strings for creature
-- names (UnitName and friends), and the dump died on one AFTER the run had
-- already collected its data:
--   "Modules/Skinning/Probe.lua:908: attempt to get length of local 'line'
--    (a secret string value, while execution tainted by 'MightiePack')"
-- A secret may be SHOWN. It may not be measured (#), sliced (:sub),
-- formatted (string.format or :format), searched (:find), substituted
-- (:gsub) or converted (tostring) — every one of those raises, and every one
-- of them was reachable from a mob name on this path.
--
-- The rule this file now follows: OUR text is the only text we measure.
-- Literals, numbers and separators built here are measurable, so the
-- 120-char cap is applied to them; a value that came from the client is
-- carried beside our text (a step's `name` field, or the `name` slot of a
-- rendered line) and appended at the print site, where the finished line
-- goes straight to AddMessage and is never measured again. Same rule
-- Modules/Touchstone/Probe.lua's describe() already follows.
local function isSecret(v)
  if type(issecretvalue) ~= "function" then return false end
  local ok, s = pcall(issecretvalue, v)
  return ok and s == true
end

-- A value the client answered with: an ordinary string, or a secret. Only
-- membership is decided here; never the contents.
local function isClientText(v)
  return type(v) == "string" or isSecret(v)
end

-- Length of a value we are allowed to measure, or nil when we are not (a
-- secret, or an operation the client refused). Callers must read nil as
-- "leave it alone", never as "length 0".
local function safeLen(v)
  if type(v) ~= "string" then return nil end
  if isSecret(v) then return nil end
  local ok, n = pcall(function() return #v end)
  if ok and type(n) == "number" then return n end
  return nil
end

-- Trim OUR OWN text. nil means "this value is a secret" (or would not
-- measure), so the caller must route it to the display channel instead of
-- folding it into a line this file will later measure.
local function cut(s, n)
  if s == nil then return nil end
  if isSecret(s) then return nil end
  if type(s) ~= "string" then s = tostring(s) end
  local len = safeLen(s)
  if len == nil then return nil end
  if len <= n then return s end
  local ok, out = pcall(function() return s:sub(1, n - 2) .. ".." end)
  if ok then return out end
  return nil
end

local function round4(v)
  return math.floor(v * 10000 + 0.5) / 10000
end

-- UNIT_DIED's argument is the creature GUID on this client, not a unit token
-- ("sk 12 UNIT_DIED k=death unit=Creature-0-7072-1-48-3124-F090F29C6F").
-- Both shapes are accepted: a GUID argument is used directly, a token
-- ("target", "party1") is resolved through GetUnitGUID.
--
-- Lua patterns have NO alternation: "^(Creature|Player)%-%d" would compare
-- against the literal text "Creature|Player". One test per prefix.
local GUID_PREFIXES = { "Creature", "Player", "Pet", "Vehicle", "GameObject" }
local function looksLikeGuid(s)
  if type(s) ~= "string" then return false end
  if isSecret(s) then return false end   -- a secret cannot be matched against
  local ok, hit = pcall(function()
    for _, p in ipairs(GUID_PREFIXES) do
      if s:match("^" .. p .. "%-%d") then return true end
    end
    return false
  end)
  return ok and hit == true
end

-- A NAME field must carry a name — or say `unknown`. It must never show a GUID
-- twice (live: "last kill: <guid> g=..EF7D0D" and "record ? g=..30C716"). On
-- this client UnitName can hand back the GUID itself for a dead creature, so
-- every path that stores or prints a name goes through here.
--
-- A SECRET name is returned untouched: it may be shown, never measured, so it
-- cannot be compared or matched here either — the compare is guarded and a
-- secret is never read at all.
local function usableName(name, guid)
  if name == nil then return nil end
  if isSecret(name) then return name end        -- carried, never read
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
P.usableName = usableName

-- ── the recent-death ring (the GUID-less-window fallback) ──────────────
-- One entry per death this session observed, so a loot window that reports no
-- source GUID can still be attributed to the corpse that just died. Prefers
-- the newest death no window has claimed yet; falls back to the newest inside
-- the window (a corpse re-opened after a later kill must still resolve).
function P:RememberDeath(guid, t, source)
  if type(guid) ~= "string" or guid == "" then return nil end
  local d = { guid = guid, at = t, source = source or "UNIT_DIED" }
  self._deaths[#self._deaths + 1] = d
  while #self._deaths > self.MAX_DEATHS do table.remove(self._deaths, 1) end
  return d
end

function P:RecentDeath(t)
  t = t or nowT()
  local newest, unclaimed = nil, nil
  for i = #self._deaths, 1, -1 do
    local d = self._deaths[i]
    if type(d) == "table" and d.guid ~= nil and (t - d.at) <= self.DEATH_FALLBACK_WINDOW then
      if newest == nil then newest = d end
      if d.usedAt == nil then
        unclaimed = d
        break
      end
    end
  end
  return unclaimed or newest
end

-- " z=<zone> <mapID>@x,y" — the card requires zone/subzone and the
-- player map position at every step; every lookup is guarded so a
-- missing API degrades to the field being omitted, never to an error.
-- The step RECORD keeps zone, subzone, map, x and y separately; the
-- printed line carries the compact form (the 120-char cap is real).
local function whereAmI()
  local zone, sub = nil, nil
  if type(GetZone) == "function" then
    local ok, z = pcall(GetZone)
    if ok and type(z) == "string" and z ~= "" then zone = z end
  end
  if type(GetSubzone) == "function" then
    local ok, s = pcall(GetSubzone)
    if ok and type(s) == "string" and s ~= "" then sub = s end
  end
  local mapID, x, y = nil, nil, nil
  if type(C_Map) == "table"
    and type(C_Map.GetBestMapForUnit) == "function"
    and type(C_Map.GetPlayerMapPosition) == "function" then
    local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
    if ok and m then
      mapID = m
      local ok2, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
      if ok2 and type(pos) == "table" and type(pos.GetXY) == "function" then
        local ok3, px, py = pcall(pos.GetXY, pos)
        if ok3 and type(px) == "number" and type(py) == "number" then
          x, y = round4(px), round4(py)
        end
      end
    end
  end
  return { zone = zone, sub = sub, map = mapID, x = x, y = y }
end

local function pct3(v)
  -- 0.4871 -> ".487" (drops the leading zero; the map position is 0..1)
  local s = string.format("%.3f", v)
  return (s:gsub("^0", ""))
end

local function locLine(w)
  local out = ""
  -- zone/subzone are client strings too: cut() answers nil when the client
  -- marks them secret, and the field is then omitted rather than folded into
  -- a line that would be measured later.
  local z = w.zone and cut(w.zone, 14)
  if z then out = out .. " z=" .. z end
  if w.map and w.x and w.y then
    out = out .. " " .. tostring(w.map) .. "@" .. pct3(w.x) .. "," .. pct3(w.y)
  elseif w.map then
    out = out .. " " .. tostring(w.map)
  end
  return out
end

-- a GUID is "Creature-0-4384-618-00712-00612-0000411A2B"; the last field
-- is the instance-unique spawn, enough to pair a corpse loot window with
-- its skin window on the printed line. The full GUID stays in the record.
-- nil means the GUID could not be measured (a secret GUID): the caller then
-- shows the value whole through the display channel instead of slicing it.
local function guidSuffix(g)
  if type(g) ~= "string" then return nil end
  if isSecret(g) then return nil end
  local ok, out = pcall(function()
    local len = #g
    if len == 0 then return nil end
    if len <= 8 then return g end
    return ".." .. g:sub(len - 5)
  end)
  if ok and type(out) == "string" then return out end
  return nil
end

-- ── step recording ────────────────────────────────────────────────────
-- `detail` is OUR text only: literals and numbers this file assembled. Client
-- text (a mob's name, a GUID, a zone the client marks secret) travels in
-- `extra.name` / `extra.nameLabel` and is appended to the printed line by
-- Diag, which never measures the result. Nothing in the record is cut or
-- formatted, so the buffer stays honest for a later reader as well.
function P:Step(event, detail, extra)
  self._seq = self._seq + 1
  local s = { n = self._seq, t = nowT(), event = event, detail = detail or "" }
  if type(extra) == "table" then
    for k, v in pairs(extra) do
      s[k] = v
    end
  end
  self.steps[#self.steps + 1] = s
  while #self.steps > self.MAX_STEPS do
    table.remove(self.steps, 1)
  end
  return s
end

-- ── loot reading (classic contract, every call pcall'd) ───────────────
-- Returns items, src, money. `money` is the coin slot, which is NOT an item:
-- the live c220ec7 dump printed it as "?x0" (no itemID, no quantity) and the
-- card is right that an unnamed, id-less slot must never be recorded as an
-- item. It is dropped from the item list; when the client reports an amount
-- the amount is kept as money instead.
function P:ReadLoot()
  local items = {}
  local money = nil
  local n = 0
  if type(GetNumLootItems) == "function" then
    local ok, v = pcall(GetNumLootItems)
    if ok and type(v) == "number" then n = v end
  end
  local src = nil
  if type(GetLootSourceInfo) == "function" and n > 0 then
    local ok, g = pcall(GetLootSourceInfo, 1)
    if ok and isClientText(g) then src = g end
  end
  for i = 1, n do
    local link = nil
    if type(GetLootSlotLink) == "function" then
      local ok, l = pcall(GetLootSlotLink, i)
      if ok and isClientText(l) then link = l end
    end
    local name, qty, qual = nil, 1, nil
    if type(GetLootSlotInfo) == "function" then
      -- classic contract: icon, name, count[, quality] (same read the
      -- NodeTrail recorder uses; itemID is recovered from the link)
      local ok, _, b, c, d = pcall(GetLootSlotInfo, i)
      if ok then
        if isClientText(b) then name = b end
        if type(c) == "number" then qty = c end
        if type(d) == "number" then qual = d end
      end
    end
    -- t_e27da774: the link's own bracketed name wins over the slot's name
    -- field. GetItemInfo cannot answer for an id this client has not cached
    -- (249399 -> "Frilled Lichen"), and the link always carries the real name;
    -- storing it here is what lets the panel print a name instead of an id.
    -- Data/ItemNames.lua owns the parse (a secret link is never searched).
    local nodeTrail = pkg.NodeTrail
    local names = type(nodeTrail) == "table" and nodeTrail.ItemNames or nil
    if link and type(names) == "table" and type(names.FromLink) == "function" then
      local okName, fromLink = pcall(names.FromLink, link)
      if okName and type(fromLink) == "string" then
        name = fromLink
      end
    end
    local id = nil
    if link then
      -- the link is client text: matching it is a read, so it is attempted
      -- and never assumed
      local ok, m = pcall(function() return link:match("item:(%d+)") end)
      if ok and type(m) == "string" then id = tonumber(m) end
    end
    if id ~= nil and id > 0 then
      items[#items + 1] = {
        id = id, name = name, qty = qty, quality = qual, link = link,
      }
    elseif type(qty) == "number" and qty > 0 then
      -- no itemID at all: the coin slot, never an item. Only a coin the client
      -- actually counted is kept; the "?x0" shape (no id, no amount) is not a
      -- money amount either and must not appear anywhere.
      money = (money or 0) + qty
    end
  end
  return items, src, money
end

-- ── attribution (t_a2f44fb2: the window's own GUID is the truth) ──────
-- Returns kind, guid, rule, cast — four values. `rule` names the evidence the
-- GUID came from ("loot-source" | "UNIT_DIED" | "TARGET_DEAD" | "none") so the
-- dump can print WHICH rule fired instead of presenting a fallback as a fact;
-- `cast` is the successful 8613 cast this window claimed (or nil), so the
-- recorder can date the skin from the cast that produced it.
--
-- Two rules, in this order:
--   1. A window with NO source GUID is NOT a dead end. It is attributed to the
--      most recent death inside DEATH_FALLBACK_WINDOW (live: UNIT_DIED at
--      759876.51, GUID-less LOOT_OPENED at 759878.38 on the same corpse).
--   2. Skin classification needs a CAST, and the CAST needs a corpse. The cast
--      is pinned only by a real, non-empty corpse window (P:OnCast). When it
--      has no pin it files nothing at cast time and the next window CLAIMS it:
--      that window's GUID is the authority, whatever was looted last. An empty
--      corpse window can therefore never steal the cast (live, t_a2f44fb2:
--      sk 34 empty ..0CC9AE, sk 39 cast, sk 41 ..475CDA i=2934x1 is the SKIN
--      window). A corpse already skinned by an earlier cast is not skinned a
--      second time.
-- A pinned cast still wins for its own corpse, and a window on a DIFFERENT
-- corpse while a pinned cast is pending stays ordinary corpse loot.
-- The corpse the player is pointing at. Used only as a short-lived fill
-- for a GUID-less skin window (see TARGET_ATTRIB_WINDOW in P:Classify),
-- never as a 60s hang off a pending pin.
function P:DeadTargetGuid()
  if type(UnitExists) ~= "function" or type(UnitIsDead) ~= "function"
    or type(UnitGUID) ~= "function" then
    return nil
  end
  local okE, exists = pcall(UnitExists, "target")
  if not okE or not exists then return nil end
  local okD, dead = pcall(UnitIsDead, "target")
  if not okD or not dead then return nil end
  local ok, g = pcall(UnitGUID, "target")
  if not ok or g == nil then return nil end
  if isSecret(g) then return g end
  if isClientText(g) then return g end
  return nil
end

function P:Classify(src, t)
  local guid, rule = nil, "none"
  if type(src) == "string" and src ~= "" then
    guid, rule = src, "loot-source"
  end
  local cast = self:PendingCast(t)
  -- Death fallback is for a GUID-less window that is still on the corpse
  -- (live: UNIT_DIED then a source-less LOOT_OPENED). After the player
  -- retargets, that fallback must not name a herb or chest as the corpse
  -- a pending Skinning cast is waiting on.
  if guid == nil and not (type(cast) == "table" and cast.targetAttribExpired) then
    local d = self:RecentDeath(t)
    if d then
      guid, rule = d.guid, (d.source == "TARGET_DEAD" and "TARGET_DEAD" or "UNIT_DIED")
      d.usedAt = t
    end
  end
  -- A GUID-less window is never named from cast.guid (that filed herb and
  -- chest loot under a pinned corpse). The dead target may name it only
  -- inside TARGET_ATTRIB_WINDOW after SUCCEEDED, only if target-attribution
  -- has not been cleared (retarget / an unclaimed LOOT_CLOSED), and only
  -- when the current dead target is still the cast's corpse if we know it
  -- (the pin, or the target snapshotted at SUCCEEDED).
  if guid == nil and type(cast) == "table" and not cast.targetAttribExpired
    and type(cast.at) == "number"
    and (t - cast.at) <= (self.TARGET_ATTRIB_WINDOW or 3) then
    local tgt = self:DeadTargetGuid()
    local expected = nil
    if type(cast.guid) == "string" then
      expected = cast.guid
    elseif type(cast.targetGuid) == "string" then
      expected = cast.targetGuid
    end
    if tgt and (expected == nil or expected == tgt) then
      guid, rule = tgt, "target"
    end
  end
  if cast then
    if guid == nil then
      -- a cast is pending and nothing at all identifies this window: saying
      -- "skin" would file items under a corpse we do not have, and saying
      -- "corpse" would be the guess the old code made. Unclassified, and the
      -- cast stays open for the window that does identify its corpse.
      return "unclassified", nil, rule, nil
    end
    if cast.guid ~= nil and cast.guid ~= guid then
      -- the cast was pinned to a corpse whose window carried loot; this window
      -- opened on a different corpse, so it is that corpse's ordinary loot.
      return "corpse", guid, rule, nil
    end
    if cast.guid == nil and self:IsSkinned(guid) then
      -- already skinned by an earlier cast: a window on it is not a second skin
      return "corpse", guid, rule, nil
    end
    cast.taken = true
    return "skin", guid, rule, cast
  end
  if guid ~= nil then return "corpse", guid, rule, nil end
  return "unattributed", nil, rule, nil
end

-- The recorder is optional: this file must load and work when Record.lua is
-- absent (tests that load only the probe, or a client where the file was not
-- copied). Nothing below depends on it existing.
function P:Recorder()
  local sk = pkg.Skinning
  local r = type(sk) == "table" and sk.Recorder or nil
  if type(r) ~= "table" then return nil end
  return r
end

-- De-duplication counters. The dump prints them, so the next in-game run can
-- verify that the duplicates named on the card really were dropped instead of
-- silently vanishing.
function P:Suppressed(which)
  local s = self._suppressed
  s[which] = (s[which] or 0) + 1
  return s[which]
end

-- ── the casts awaiting a corpse (t_a2f44fb2) ─────────────────────────
-- A successful Skinning cast carries NO GUID: the only thing that can say
-- WHICH corpse it was applied to is a loot window. So the cast is remembered
-- here until a window CLAIMS it, and a cast nothing claims inside SKIN_WINDOW
-- is a cast that produced no skin window — which the accounting line reports
-- as a lost cast instead of being guessed onto somebody else's corpse.
-- Drop target-based attribution for any unclaimed pending cast. A later
-- loot window that carries its own source GUID can still claim the cast;
-- only the GUID-less DeadTargetGuid fill is revoked (retarget, or a
-- loot window that closed without claiming the skin).
function P:ExpireTargetAttrib()
  local casts = self._casts
  if type(casts) ~= "table" then return end
  for i = 1, #casts do
    local c = casts[i]
    if type(c) == "table" and not c.taken then
      c.targetAttribExpired = true
    end
  end
end

function P:RememberCast(cast)
  if type(cast) ~= "table" then return nil end
  self._casts[#self._casts + 1] = cast
  while #self._casts > self.MAX_CASTS do table.remove(self._casts, 1) end
  return cast
end

-- The newest successful cast that is still inside SKIN_WINDOW and has not been
-- claimed by a loot window, or nil. This is the cast a window opens "under".
function P:PendingCast(t)
  for i = #self._casts, 1, -1 do
    local c = self._casts[i]
    if type(c) == "table" and not c.taken and type(c.at) == "number"
      and (t - c.at) <= self.SKIN_WINDOW then
      return c
    end
  end
  return nil
end

-- Is this corpse already recorded as skinned? Asked of the recorder, which owns
-- the records (the probe can be loaded without it). With no recorder, or no
-- record yet, the answer is "no": a skin on a corpse whose kill was never
-- observed still counts, so a missing record is not a reason to refuse.
function P:IsSkinned(guid)
  local R = self:Recorder()
  if type(R) == "table" and type(R.Find) == "function" then
    local ok, rec = pcall(R.Find, R, guid)
    if ok and type(rec) == "table" then return rec.skinned == true end
  end
  return false
end

-- ── spell / skinning detection ────────────────────────────────────────
local function nameSkinny(name)
  if type(name) ~= "string" or isSecret(name) then return false end
  local ok, hit = pcall(function() return name:lower():find("skin", 1, true) ~= nil end)
  return ok and hit == true
end

function P:IsSkinningSpell(spellID, spellName)
  -- the confirmed ID first: on this client the name argument is the cast bar
  -- ("n=CastBar-1B595C.."), so the name test can never match a real cast.
  if type(spellID) == "number" and self.SKIN_SPELL_IDS[spellID] then
    return true
  end
  if nameSkinny(spellName) then return true end
  if spellID == nil then return false end
  if self._skinSpells[spellID] then return true end
  if type(GetSpellInfo) == "function" then
    -- the event already carries the name on modern clients; GetSpellInfo
    -- is only the fallback for a client that passes an unnamed cast
    local ok, nm = pcall(GetSpellInfo, spellID)
    if ok and nameSkinny(nm) then
      self._skinSpells[spellID] = nm
      return true
    end
  end
  return false
end

-- ── a cast's name is a spell name, never a frame name ─────────────────
-- On this client the 4th UNIT_SPELLCAST_* argument is the CAST BAR's frame
-- name ("CastBar-80CD3B37C39E3787"), not the spell's name, and the dump used
-- to print it in the spell field: "last skin cast: spell=8613
-- name=CastBar-80CD3B37C39E3787". A widget is not a spell. The name now comes
-- from the spell ID (GetSpellInfo) and a client string is only used when it is
-- a plain name — never measured, never sliced: the test runs behind a pcall,
-- and a SECRET is never read at all.
local FRAME_NAME_HINTS = { "CastBar", "StatusBar", "Frame", "Button" }
local function looksLikeFrameName(v)
  if type(v) ~= "string" then return false end
  if isSecret(v) then return false end
  local ok, hit = pcall(function()
    for _, h in ipairs(FRAME_NAME_HINTS) do
      if v:find(h, 1, true) then return true end
    end
    -- "CastBar-80CD3B37C39E3787", "Thing-1A2B3C4D": <word>-<hex tail>, no space
    if not v:find(" ", 1, true) and v:match("^[%a_]+%-%x+$") then return true end
    return false
  end)
  return ok and hit == true
end
P.looksLikeFrameName = looksLikeFrameName

-- The spell name this file is allowed to show, or nil. Prefers the client's own
-- answer for the ID; the event's 4th argument is only a fallback for builds
-- that really send a name.
function P:SpellDisplayName(spellID, clientName)
  if type(GetSpellInfo) == "function" and type(spellID) == "number" then
    local ok, nm = pcall(GetSpellInfo, spellID)
    if ok and nm ~= nil and (isSecret(nm) or (safeLen(nm) or 0) > 0) then
      return nm
    end
  end
  if clientName == nil or isSecret(clientName) then return nil end
  if looksLikeFrameName(clientName) then return nil end
  return clientName
end

-- ── event handlers (each is a no-op until capture is toggled on) ─────
function P:OnCast(event, unit, castGUID, spellID, spellName)
  if not self.capturing then return end
  local t = nowT()
  local w = whereAmI()
  -- the unit argument is a token ("player", "target"): our own vocabulary, and
  -- it is only read when the client did not mark it secret. A missing name is
  -- `unknown` — it used to print `?`, which reads like a broken field rather
  -- than a value the client did not give (live: "k=cast s=75 who=?").
  local isPlayer = type(unit) == "string" and not isSecret(unit) and unit == "player"
  local who = isPlayer and "player" or "unknown"
  local id = type(spellID) == "number" and spellID or nil
  local clientName = isClientText(spellName) and spellName or nil
  local name = self:SpellDisplayName(id, clientName)
  local isSkin = isPlayer
    and event == "UNIT_SPELLCAST_SUCCEEDED"
    -- detection reads the CLIENT's argument (unchanged); display uses the
    -- resolved spell name, so a cast bar can never be mistaken for a name
    and self:IsSkinningSpell(id, clientName)
  if isSkin then
    -- Pin the cast to the corpse the player just looted — but ONLY when that
    -- window is real evidence: a corpse window the client showed items in.
    --
    -- t_a2f44fb2: a corpse with nothing in it still gets a LOOT_OPENED /
    -- LOOT_CLOSED pair. Taking that empty window as the pin is what stole the
    -- cast from the corpse the player actually skinned and marked the empty
    -- corpse skinned with no items (live: sk 34 i=- on ..0CC9AE, cast, real
    -- skin window sk 41 on ..475CDA filed as corpse loot). An empty window
    -- pins nothing; the cast is then claimed by the window that follows it
    -- (P:Classify), which carries the corpse's own GUID.
    --
    -- BOUNDED by SKIN_WINDOW: a window looted minutes ago says nothing about
    -- what this cast is being applied to.
    local guid = nil
    local prev = self.lastLoot
    if type(prev) == "table" and type(prev.src) == "string" and prev.at ~= nil
      and (t - prev.at) <= self.SKIN_WINDOW
      and prev.kind == "corpse"
      and type(prev.count) == "number" and prev.count > 0 then
      guid = prev.src
    end
    self.lastSkin = { spellID = id, name = name, at = t, guid = guid }
    -- the cast is remembered either way: a pinned one for its own corpse, an
    -- unpinned one for the window that names its corpse
    self:RememberCast({
      at = t, guid = guid, spellID = id, name = name, taken = false,
      targetGuid = self:DeadTargetGuid(),
    })
    if id and not self._skinSpells[id] then
      self._skinSpells[id] = name or tostring(id)
    end
  end
  local d = "k=" .. (isSkin and "skin-cast" or "cast")
  if id then d = d .. " s=" .. tostring(id) end
  d = d .. " who=" .. who
  d = d .. locLine(w)
  -- `name` is the resolved SPELL name (see P:SpellDisplayName): a cast-bar
  -- frame name never travels to the line, and the raw client argument stays in
  -- the record's own field for a later reader.
  self:Step(event, d, {
    who = who, spellID = id, name = name, nameLabel = " n=", skin = isSkin,
    clientName = clientName,
    zone = w.zone, sub = w.sub, map = w.map, x = w.x, y = w.y,
  })
  local R = self:Recorder()
  if R and isSkin and type(R.OnSkinCast) == "function" and self.lastSkin then
    pcall(R.OnSkinCast, R, {
      spellID = id, name = name, t = t, guid = self.lastSkin.guid,
    })
  end
end

-- Compact item text for a printed line: "2934x1,7100x2" plus a "+N" overflow.
-- MONEY IS NOT AN ITEM (t_67f26739): the coin slot used to be appended to this
-- list as ",money", which put a word in an item list where only items belong.
-- It is counted BESIDE the list (see P:CoinText) and never inside it.
function P:ItemText(items)
  items = type(items) == "table" and items or {}
  local shown = math.min(#items, self.MAX_ITEMS_SHOWN)
  local bits = {}
  for i = 1, shown do
    local it = items[i]
    if it and it.id then
      bits[i] = tostring(it.id) .. "x" .. tostring(it.qty)
        .. (type(it.quality) == "number" and ("q" .. tostring(it.quality)) or "")
    end
  end
  local list = #bits > 0 and table.concat(bits, ",") or nil
  return (list or "-") .. (#items > shown and ("+" .. (#items - shown)) or "")
end

-- The coin the client counted in this window, as its own field. Empty when the
-- client reported no amount — nothing is invented for an empty coin slot.
function P:CoinText(money)
  if type(money) ~= "number" or money <= 0 then return "" end
  return " coin=" .. tostring(money)
end

-- A re-read of a LIVE loot window can only ever show FEWER items than it did
-- before: the player is taking them out, so the later read is a subset of the
-- earlier one. REPLACING the window's list with that later read is what made
-- the recorder store "none seen" for a corpse whose window had carried two
-- items (live at Razor Hill):
--
--   sk 220 LOOT_OPENED k=corpse g=..10B81C i=5466x1,4867x1
--   record  corpse items: none seen (late read)
--
-- A window therefore ACCUMULATES. An item once seen in this window is never
-- un-seen by a read of the same window, and its quantity only grows (the client
-- can report one stack twice). Only OUR converted values are compared (itemID
-- and quantity are numbers), never a client name or link.
-- Returns true when this read showed something the window had not seen yet.
local function absorbItems(win, items, money)
  local known = type(win.items) == "table" and win.items or {}
  local seen = {}
  for i = 1, #known do
    local it = known[i]
    if type(it) == "table" and it.id then seen[it.id] = it end
  end
  local added = false
  local fresh = type(items) == "table" and items or {}
  for i = 1, #fresh do
    local it = fresh[i]
    if type(it) == "table" and it.id then
      local have = seen[it.id]
      if not have then
        known[#known + 1] = it
        seen[it.id] = it
        added = true
      elseif type(it.qty) == "number" and it.qty > (tonumber(have.qty) or 0) then
        have.qty = it.qty
        added = true
      end
    end
  end
  if type(money) == "number" and money > (tonumber(win.money) or 0) then
    win.money, added = money, true
  end
  win.items = known
  return added
end

-- The client can fill the loot slots AFTER LOOT_OPENED: the live run printed
-- "i=-" at the open and the items only showed up once the slots were being
-- taken. So the open window is re-read (a) on every LOOT_SLOT_CLEARED and
-- (b) once more just before LOOT_CLOSED, and EVERY one of those reads is
-- written into the corpse's record — not just onto the step line. A read that
-- only reaches the log is a read the player cannot see afterwards, which is
-- exactly the blocker this card names.
--
-- The record is written with what the WINDOW has seen (the accumulated list),
-- so an emptied window can never erase a populated one. Nothing is re-read
-- after the window closed: there is nothing to read.
--
-- Returns the window's list and money when this read added something, nil when
-- it did not (the step line then says nothing).
function P:RereadWindow(why)
  local win = self._win
  if type(win) ~= "table" then return nil end
  local t = nowT()
  local items, _, money = self:ReadLoot()
  local added = absorbItems(win, items, money)
  win.rereads = (win.rereads or 0) + 1
  win.lastRead = why
  local R = self:Recorder()
  if R and win.guid and type(R.SetWindowItems) == "function" then
    pcall(R.SetWindowItems, R, win.guid, win.kind, win.items, win.money, t)
  end
  -- `count` is how many items this window has been SEEN to carry. It is what
  -- makes a window a valid cast pin (t_a2f44fb2: an empty window pins nothing),
  -- so it follows the window's accumulated list, not just the first read —
  -- the client can fill the slots after LOOT_OPENED.
  if type(win) == "table" and type(self.lastLoot) == "table"
    and self.lastLoot.at == win.at then
    self.lastLoot.count = type(win.items) == "table" and #win.items or 0
    self.lastLoot.kind = win.kind
  end
  if not added then return nil end
  return win.items, win.money
end

function P:OnLootOpened()
  if not self.capturing then return end
  local t = nowT()
  local w = whereAmI()
  -- a new window: the previous close (and its duplicate) is finished, and
  -- slot-cleared de-duplication restarts from this window
  self._pendingClose = nil
  self._slotTicks = {}
  local items, src, money = self:ReadLoot()
  local srcName = nil
  if type(GetLootSourceName) == "function" then
    local ok, nm = pcall(GetLootSourceName)
    if ok and isClientText(nm) then srcName = nm end
  end
  local kind, guid, rule, claimed = self:Classify(src, t)
  self.lastLoot = { src = guid, raw = src, at = t, kind = kind, rule = rule,
    count = #items }
  -- the window that is open RIGHT NOW: slot-cleared and the close both re-read
  -- it, which is how a late-populated window is still recorded correctly
  self._win = {
    guid = guid, kind = kind, at = t, items = items, money = money,
    rereads = 0, rule = rule,
  }
  local d = "k=" .. kind
  local suffix = guidSuffix(guid)
  if suffix then
    d = d .. " g=" .. suffix
    -- say WHICH rule produced the GUID: a GUID read off the loot source and
    -- one carried over from the death are different evidence.
    if rule == "UNIT_DIED" or rule == "TARGET_DEAD" then
      d = d .. " (from " .. rule .. ")"
    end
  end
  d = d .. " i=" .. self:ItemText(items) .. self:CoinText(money)
  d = d .. locLine(w)
  -- the loot source's name is client text: carried beside our text
  local shownName = nil
  if srcName ~= nil then shownName = usableName(srcName, guid) end
  self:Step("LOOT_OPENED", d, {
    kind = kind, src = guid, rawSrc = src, srcName = srcName,
    name = shownName, nameLabel = " n=",
    items = items, money = money, rule = rule,
    zone = w.zone, sub = w.sub, map = w.map, x = w.x, y = w.y,
  })
  local R = self:Recorder()
  if R then
    local ev = {
      guid = guid, name = srcName, items = items, money = money, t = t,
      kind = kind, rule = rule,
      -- the successful 8613 cast this window claimed, if any: the recorder
      -- dates the skin from the cast and marks the corpse skinned on THIS
      -- window's authority (t_a2f44fb2). A window filed as skin with no cast
      -- behind it carries no claim and marks nothing.
      cast = claimed ~= nil,
      castAt = claimed and claimed.at or nil,
      spellID = claimed and claimed.spellID or nil,
      zone = w.zone, sub = w.sub, map = w.map, x = w.x, y = w.y,
    }
    if kind == "corpse" and type(R.OnCorpseLoot) == "function" then
      pcall(R.OnCorpseLoot, R, ev)
    elseif kind == "skin" and type(R.OnSkinLoot) == "function" then
      pcall(R.OnSkinLoot, R, ev)
    elseif type(R.OnUnclassified) == "function" then
      -- "unattributed" (no GUID and no death to fall back to) and
      -- "unclassified" (a cast is pending but nothing identifies the window)
      -- both land here: the recorder keeps them apart from both item lists.
      ev.reason = (kind == "unattributed")
        and "no loot-source GUID and no recent death to fall back to"
        or "a cast was pending but nothing identified this window"
      pcall(R.OnUnclassified, R, ev)
    end
  end
end

function P:OnSlotCleared(...)
  if not self.capturing then return end
  local a1 = select(1, ...)
  local t = nowT()
  local w = whereAmI()
  -- sk 35/sk 36: the same slot can be reported twice in the same instant.
  -- Same-or-next-tick is dropped before it reaches the recorder.
  if type(a1) == "number" then
    local last = self._slotTicks[a1]
    if last and (t - last) <= self.DUP_TICK then
      self:Suppressed("LOOT_SLOT_CLEARED")
      return
    end
    self._slotTicks[a1] = t
  end
  -- the slots are being taken: this is the moment the client reveals what the
  -- window actually holds (live: LOOT_OPENED said "i=-" and the items appeared
  -- here), so the open window is re-read before it is closed.
  local late = self:RereadWindow("slot-cleared")
  local d = "k=slot-cleared slot=" .. (type(a1) == "number" and tostring(a1) or "-")
  if late then
    d = d .. " items+=" .. self:ItemText(late)
      .. self:CoinText(self._win and self._win.money)
  end
  d = d .. locLine(w)
  self:Step("LOOT_SLOT_CLEARED", d, {
    slot = a1, lateItems = late and true or nil,
    zone = w.zone, sub = w.sub, map = w.map, x = w.x, y = w.y,
  })
end

function P:OnLootClosed()
  if not self.capturing then return end
  local t = nowT()
  local w = whereAmI()
  -- sk 16/sk 17 (and sk 25/sk 26): LOOT_CLOSED fires twice for ONE close.
  -- Nothing reopened a window in between, so the second is the same close;
  -- emitting it would also move the recorder's gap start point.
  if self._pendingClose then
    self:Suppressed("LOOT_CLOSED")
    return
  end
  self._pendingClose = t
  -- one last read of the window that is about to go away: a window the client
  -- filled but the player closed with nothing taken still has to be recorded
  -- with what it showed. This read WRITES THE RECORD (RereadWindow does), so
  -- the record is re-rendered from what the window carried once the close is
  -- over — the close is the last chance to store it.
  local late = self:RereadWindow("close")
  local d = "k=loot-closed prev=" .. (self.lastLoot and self.lastLoot.kind or "-")
  if late then
    d = d .. " items-final=" .. self:ItemText(late)
      .. self:CoinText(self._win and self._win.money)
  end
  d = d .. locLine(w)
  self:Step("LOOT_CLOSED", d, {
    lateItems = late and true or nil,
    zone = w.zone, sub = w.sub, map = w.map, x = w.x, y = w.y,
  })
  self._win = nil
  -- A window that did not claim the pending skin must not leave target
  -- attribution armed for the next GUID-less herb/chest/fishing open.
  -- A skin window already set taken=true, so ExpireTargetAttrib skips it.
  if not (self.lastLoot and self.lastLoot.kind == "skin") then
    self:ExpireTargetAttrib()
  end
  local R = self:Recorder()
  if R and type(R.OnLootClosed) == "function" then
    pcall(R.OnLootClosed, R, t)
  end
end

function P:OnUnitDied(unit)
  if not self.capturing then return end
  local t = nowT()
  local w = whereAmI()
  local name, guid = nil, nil
  local isPlayerDeath = type(unit) == "string" and not isSecret(unit) and unit == "player"
  if isPlayerDeath then -- luacheck: ignore 542
    -- the player's own death: nothing to attribute to a corpse
  elseif looksLikeGuid(unit) then
    -- the live shape: the argument IS the corpse GUID. A GUID is not a unit
    -- token, so nothing here asks the client for a name it cannot give — the
    -- mob's name arrives from the target enrichment below or the loot source.
    guid = unit
    if type(self.lastKill) == "table" and self.lastKill.guid == guid then
      name = self.lastKill.name
    end
  elseif isClientText(unit) then
    if type(unit) == "string" and not isSecret(unit) then
      -- a unit token ("target", "party1"): resolvable
      if type(GetUnitName) == "function" then
        local ok, nm = pcall(GetUnitName, unit)
        if ok and isClientText(nm) then name = nm end
      end
      if type(GetUnitGUID) == "function" then
        local ok, g = pcall(GetUnitGUID, unit)
        if ok and isClientText(g) then guid = g end
      end
    else
      -- a GUID the client marked secret: still the death's identity, it just
      -- cannot be parsed or sliced here. It is shown whole at the print site.
      guid = unit
    end
  end
  if guid or name then
    -- the NAME field carries a name or nothing — never the GUID twice
    name = usableName(name, guid)
    self.lastKill = { guid = guid, name = name, at = t }
  end
  if guid then
    self._deadGuids[guid] = t
    -- remembered for the GUID-less loot window that follows a death on this
    -- client (live: UNIT_DIED ..EF7D0D -> LOOT_OPENED with no GUID at all)
    self:RememberDeath(guid, t, "UNIT_DIED")
  end
  -- our own description of the argument; the value itself is never measured
  local argText = "unknown"
  if isPlayerDeath then
    argText = "player"
  elseif looksLikeGuid(unit) then
    argText = "creature"
  elseif type(unit) == "string" and not isSecret(unit) then
    argText = unit
  end
  local d = "k=death unit=" .. argText
  local suffix = guidSuffix(guid)
  if suffix then d = d .. " g=" .. suffix end
  if isPlayerDeath then d = d .. " [YOU DIED]" end
  d = d .. locLine(w)
  -- the mob's name is client text: carried beside our text and printed at the
  -- end of the line. When the GUID itself is a secret that cannot be
  -- shortened, the GUID is shown whole instead of a suffix.
  local display, label = name, " n="
  if display == nil and guid ~= nil and suffix == nil then
    display, label = guid, " g="
  end
  self:Step("UNIT_DIED", d, {
    unit = unit, guid = guid, name = display, nameLabel = label,
    zone = w.zone, sub = w.sub, map = w.map, x = w.x, y = w.y,
  })
  local R = self:Recorder()
  if R and guid and type(R.OnKill) == "function" then
    pcall(R.OnKill, R, {
      guid = guid, name = name, t = t,
      zone = w.zone, sub = w.sub, map = w.map, x = w.x, y = w.y,
    })
  end
end

-- The combat-log replacement (see P.EVENTS): when the target changes, note a
-- dead target as a kill. This is the only death signal available once
-- COMBAT_LOG_EVENT_UNFILTERED is off the table, and it fires exactly when the
-- player moves from a corpse to the next mob.
--
-- STRICTLY A FALLBACK now: the live dump repeats a GUID UNIT_DIED already
-- reported (sk 13 after sk 12, sk 18, sk 41). Such a GUID produces no step —
-- it only fills in the mob's NAME, which is the one thing UNIT_DIED's GUID
-- argument cannot provide on this client.
function P:OnTargetChanged()
  if not self.capturing then return end
  -- Any target change (including clearing the target, or selecting a herb
  -- node) revokes GUID-less target attribution for unclaimed casts. The
  -- existing dead-target kill fallback still runs below when the new
  -- target is a corpse.
  self:ExpireTargetAttrib()
  if type(UnitExists) ~= "function" or type(UnitIsDead) ~= "function" then return end
  local okE, exists = pcall(UnitExists, "target")
  if not okE or not exists then return end
  local okD, dead = pcall(UnitIsDead, "target")
  if not okD or not dead then return end
  local name, guid
  if type(UnitName) == "function" then
    local ok, nm = pcall(UnitName, "target")
    if ok and isClientText(nm) then name = nm end
  end
  if type(UnitGUID) == "function" then
    local ok, g = pcall(UnitGUID, "target")
    if ok and isClientText(g) then guid = g end
  end
  if not name and not guid then return end
  -- a name that is really the GUID has no business in a NAME field (live:
  -- "last kill: <guid> g=..EF7D0D"). usableName answers nil for it.
  local displayName = usableName(name, guid)
  local t = nowT()
  if guid and self._deadGuids[guid] then
    -- already recorded as dead: enrich, never re-report
    self:Suppressed("TARGET_DEAD")
    if displayName ~= nil then
      if type(self.lastKill) == "table" and self.lastKill.guid == guid then
        self.lastKill.name = self.lastKill.name or displayName
      end
      local R = self:Recorder()
      if R and type(R.EnrichName) == "function" then
        pcall(R.EnrichName, R, guid, displayName)
      end
    end
    return
  end
  if guid then
    self._deadGuids[guid] = t
    self:RememberDeath(guid, t, "TARGET_DEAD")
  end
  self.lastKill = { guid = guid, name = displayName, at = t }
  local w = whereAmI()
  local d = "k=death target"
  local suffix = guidSuffix(guid)
  if suffix then d = d .. " g=" .. suffix end
  d = d .. locLine(w)
  -- the target's name is client text: carried beside our text, printed last
  local display, label = displayName, " n="
  if display == nil and guid ~= nil and suffix == nil then
    display, label = guid, " g="
  end
  self:Step("TARGET_DEAD", d, {
    unit = "target", guid = guid, name = display, nameLabel = label,
    zone = w.zone, sub = w.sub, map = w.map, x = w.x, y = w.y,
  })
  local R = self:Recorder()
  if R and guid and type(R.OnKill) == "function" then
    pcall(R.OnKill, R, {
      guid = guid, name = displayName, t = t,
      zone = w.zone, sub = w.sub, map = w.map, x = w.x, y = w.y,
    })
  end
end

-- Kept, but never registered: COMBAT_LOG_EVENT_UNFILTERED is a protected event
-- on this client (ADDON_ACTION_FORBIDDEN on registration). The unit-tooltip-era
-- varargs are preserved here so the shape is not lost if a future client
-- permits it again.
function P:OnCombat(...)
  if not self.capturing then return end
  local args = { ... }
  local ev = args[2]
  local srcFlags = args[5]
  local destGUID, destName, destFlags = args[6], args[7], args[8]
  local died = false
  local spellID, spellName
  for i = 9, #args do
    local v = args[i]
    if v == "targetDead" or v == "sourceDead" then
      died = true
    elseif v == "SpellId" or v == "spellID" then
      spellID = args[i + 1]
    elseif v == "SpellName" or v == "spellName" then
      spellName = args[i + 1]
    end
  end
  if not died then return end
  local function playerFlag(f)
    if type(f) ~= "number" then return false end
    return (f - math.floor(f / 2) * 2) == 1
  end
  local mine = (playerFlag(srcFlags) or playerFlag(destFlags)) and "yes" or "no"
  if isClientText(destGUID) and isClientText(destName) then
    self.lastKill = { guid = destGUID, name = destName, at = nowT() }
  end
  local w = whereAmI()
  local d = "k=death cl=" .. tostring(ev or "unknown") .. " mine=" .. mine
  if spellID then d = d .. " s=" .. tostring(spellID) end
  local suffix = guidSuffix(destGUID)
  if suffix then d = d .. " g=" .. suffix end
  d = d .. locLine(w)
  -- names are client text: kept beside our own text and printed at the end
  -- (this handler is never registered — see P.EVENTS — but it is audited
  -- with the rest: no read of a name is performed here)
  local display, label = destName, " dest="
  if display == nil then display, label = spellName, " n=" end
  self:Step("COMBAT_LOG_EVENT_UNFILTERED", d, {
    destGUID = destGUID, destName = display, name = display, nameLabel = label,
    spellID = spellID, spellName = spellName,
    zone = w.zone, sub = w.sub, map = w.map, x = w.x, y = w.y,
  })
end

-- ── identical consecutive events ──────────────────────────────────────
-- One skill update can land the SAME event 18 times on one timestamp (live:
-- "sk 181..200 765670.55 SKILL_LINES_CHANGED k=skill-lines arg=-"). Each copy
-- cost a ring slot and pushed real loot events out of the 120-slot window.
-- This is the rule the card names — the one LOOT_CLOSED, LOOT_SLOT_CLEARED and
-- TARGET_DEAD already get — applied to a run of identical events: same name,
-- same argument, same or next tick collapses into the step already recorded,
-- which counts how many events it stands for. Returns the step it folded into,
-- or nil when this event is a new one.
function P:CollapseIntoLast(event, argKey, t)
  local last = self.steps[#self.steps]
  if type(last) ~= "table" or last.event ~= event then return nil end
  if (last.argKey or "-") ~= argKey then return nil end
  if type(last.t) ~= "number" or type(t) ~= "number" then return nil end
  if (t - last.t) > self.DUP_TICK then return nil end
  if not self.capturing then return nil end
  last.repeats = (last.repeats or 1) + 1
  self:Suppressed(event)
  return last
end

function P:OnSkillLines(...)
  if not self.capturing then return end
  local a1 = select(1, ...)
  local t = nowT()
  local argKey = (type(a1) == "number") and tostring(a1) or "-"
  -- a burst of identical skill updates must not eat the ring buffer
  if self:CollapseIntoLast("SKILL_LINES_CHANGED", argKey, t) then return end
  local w = whereAmI()
  local d = "k=skill-lines arg=" .. (type(a1) == "number" and tostring(a1) or "-")
  -- SKILL_LINES_CHANGED arrives with no usable argument on this client
  -- ("arg=-"), so the value is read from the skill lines instead — and when
  -- that read fails too, nothing is printed. A value is NEVER invented.
  local skill = self:ReadSkinningSkill()
  if skill then
    d = d .. " v=" .. tostring(skill.rank) .. (skill.max and ("/" .. tostring(skill.max)) or "")
  end
  d = d .. locLine(w)
  self:Step("SKILL_LINES_CHANGED", d, {
    arg = a1, argKey = argKey, skill = skill and skill.rank or nil,
    zone = w.zone, sub = w.sub, map = w.map, x = w.x, y = w.y,
  })
end

-- Best-effort Skinning skill value. Every lookup is guarded and the return is
-- nil when the client gives nothing — the dump then shows no value at all.
function P:ReadSkinningSkill()
  if type(GetNumSkillLines) ~= "function" or type(GetSkillLineInfo) ~= "function" then
    return nil
  end
  local okN, n = pcall(GetNumSkillLines)
  if not okN or type(n) ~= "number" then return nil end
  for i = 1, n do
    local ok, name, rank, maxRank = pcall(GetSkillLineInfo, i)
    if ok and type(name) == "string" and not isSecret(name) then
      local isSkin, errS = pcall(function()
        return name:lower():find("skinn", 1, true) ~= nil
      end)
      if isSkin and errS == true then
        if type(rank) == "number" then
          return { rank = rank, max = (type(maxRank) == "number" and maxRank or nil) }
        end
        return nil
      end
    end
  end
  return nil
end

function P:OnEnterWorld(...)
  if not self.capturing then return end
  local a1 = select(1, ...)
  local w = whereAmI()
  local d = "k=entering-world " .. (type(a1) == "boolean" and ("first=" .. tostring(a1)) or "")
  d = d .. locLine(w)
  self:Step("PLAYER_ENTERING_WORLD", d, {
    zone = w.zone, sub = w.sub, map = w.map, x = w.x, y = w.y,
  })
end

-- ── control ───────────────────────────────────────────────────────────
function P:Toggle()
  self.capturing = not self.capturing
  return self.capturing
end

-- t_5507a0ba: turning NodeTrail's skinning sub-option off must be
-- immediate, so the probe can be switched off without a UI reload: stop
-- capturing, drop the buffered steps of this session, and unregister every
-- event. Idempotent — calling it while off does nothing.
function P:Disable()
  local was = self.enabled
  self.enabled = false
  self.capturing = false
  self.steps = {}
  self._seq = 0
  self.lastSkin = nil
  self.lastLoot = nil
  self.lastKill = nil
  self._deadGuids = {}
  self._deaths = {}
  self._casts = {}
  self._win = nil
  self._suppressed = {}
  self._pendingClose = nil
  self._slotTicks = {}
  local R = self:Recorder()
  if R and type(R.Disable) == "function" then
    pcall(R.Disable, R)
  end
  local frame = self.frame
  if type(frame) ~= "table" then
    return was
  end
  for _, e in ipairs(self.EVENTS) do
    local ok = pcall(frame.UnregisterEvent, frame, e)
    if ok then
      self._events[e] = nil
    end
  end
  self.frame = nil
  return was
end

function P:Enable()
  if self.enabled then return end
  self.enabled = true
  self._deadGuids = {}
  self._deaths = {}
  self._casts = {}
  self._win = nil
  self._suppressed = {}
  self._pendingClose = nil
  self._slotTicks = {}
  local Rx = self:Recorder()
  if Rx and type(Rx.Enable) == "function" then
    pcall(Rx.Enable, Rx)
  end
  local function note(m)
    if type(pkg.Print) == "function" then pkg.Print("skindiag: " .. m) end
  end
  note("step: creating the event frame")
  local frame = CreateFrame("Frame")
  self.frame = frame
  note("step: frame created")
  local function dispatch(event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
      self:OnCast("UNIT_SPELLCAST_SUCCEEDED", ...)
    elseif event == "UNIT_SPELLCAST_START" then
      self:OnCast("UNIT_SPELLCAST_START", ...)
    elseif event == "UNIT_SPELLCAST_STOP" then
      self:OnCast("UNIT_SPELLCAST_STOP", ...)
    elseif event == "LOOT_OPENED" then
      self:OnLootOpened()
    elseif event == "LOOT_SLOT_CLEARED" then
      self:OnSlotCleared(...)
    elseif event == "LOOT_CLOSED" then
      self:OnLootClosed()
    elseif event == "UNIT_DIED" then
      self:OnUnitDied(...)
    elseif event == "PLAYER_TARGET_CHANGED" then
      self:OnTargetChanged(...)
    elseif event == "SKILL_LINES_CHANGED" then
      self:OnSkillLines(...)
    elseif event == "PLAYER_ENTERING_WORLD" then
      self:OnEnterWorld(...)
    end
  end
  note("step: installing OnEvent")
  frame:SetScript("OnEvent", function(_, event, ...)
    local ok, err = pcall(dispatch, event, ...)
    if not ok then
      -- An error object need not be a string, and on this client an error
      -- raised while handling a secret can carry the secret itself —
      -- tostring() on that is another read. Reporting a failure must never
      -- raise a second one.
      if type(err) == "string" then
        self._error = err
      elseif isSecret(err) then
        self._error = "a secret value (not read)"
      else
        local okS, txt = pcall(tostring, err)
        self._error = (okS and type(txt) == "string" and txt) or "unprintable error"
      end
    end
  end)
  note("step: OnEvent installed")
  for _, e in ipairs(self.EVENTS) do
    -- Register only what THIS client knows, by TRYING it. Never ask
    -- C_EventUtils.IsEventValid: that namespace is restricted to Blizzard's
    -- own code, and calling it from an addon is refused at the secure-call
    -- boundary — the client answers with the modal
    --   "MightiePack has been blocked from an action only available to the
    --    Blizzard UI"
    -- instead of a catchable Lua error, so pcall does not help (live:
    -- 2026-11-07, the block fired on the exact frame /mp skindiag ran).
    -- A failed RegisterEvent is an ordinary error we can catch, and an
    -- unknown event is recorded as "invalid event" so the dump stays
    -- truthful (t_81da8886).
    local ok, err = pcall(frame.RegisterEvent, frame, e)
    if ok then
      self._events[e] = true
      note("reg ok: " .. e)
    else
      local msg = tostring(err)
      if msg:find("unknown event", 1, true) then
        self._events[e] = "invalid event"
        note("reg refused (unknown): " .. e)
      else
        self._events[e] = msg
        note("reg refused (" .. msg .. "): " .. e)
      end
    end
  end
  note("step: registration finished")
end

-- /mp skindiag dump — the in-client evidence channel. One line per step,
-- in capture order. The cap applies to text THIS FILE built; a client value
-- (a mob's name) is appended to the finished line and never measured, so a
-- SECRET name can be shown without killing the dump (t_1ed3b421).
function P:Diag()
  local RESERVE = 20 -- room kept for a client value we are NOT allowed to measure
  -- The ONE printer for the whole dump.
  --   pre  our text (measurable, therefore capped)
  --   value  client text that may be a SECRET: appended, never measured
  --   post  our text after it
  -- Nothing measures the concatenation, and the result goes straight to
  -- AddMessage: a secret may be shown, not measured. Room for the value is
  -- computed exactly when the client lets us measure it, and reserved
  -- conservatively when it does not.
  local function add(pre, value, post)
    pre = pre or ""
    local room = self.LINE_CAP
    if value ~= nil then
      room = self.LINE_CAP - (safeLen(post) or 0) - (safeLen(value) or RESERVE)
    elseif post then
      room = self.LINE_CAP - (safeLen(post) or 0)
    end
    local len = safeLen(pre)
    if len and len > room then pre = pre:sub(1, room) end
    local out = pre
    if value ~= nil then out = out .. value end
    if post then out = out .. post end
    DEFAULT_CHAT_FRAME:AddMessage(out)
  end
  local function say(m) add("Skinning skindiag: " .. m, nil, nil) end

  -- First line: what is recording, whether the sub-option is on, and WHERE
  -- the records went. The old first line only said "capture on"; the line the
  -- card caught said "nothing recorded" while 9 kills were in the buffer
  -- (live, c220ec7). Both are replaced by this one statement of fact.
  local R = self:Recorder()
  local db = false
  if type(R) == "table" and type(R.IsEnabled) == "function" then
    local okE, on = pcall(R.IsEnabled, R)
    db = okE and on == true
  end
  say("capture " .. (self.capturing and "on" or "off")
    .. "; sub-option " .. (db and "ON" or "off") .. " (NodeTrail)"
    .. "; records: " .. (db
      and "NodeTrailDB.skinning, saved"
      or "session buffer only, nothing saved")
    .. "; steps=" .. #self.steps .. "/" .. self.MAX_STEPS)

  local valid, skipped = 0, {}
  for _, e in ipairs(self.EVENTS) do
    local r = self._events[e]
    if r == true then
      valid = valid + 1
    elseif r == "invalid event" then
      skipped[#skipped + 1] = e .. "=invalid event"
    else
      skipped[#skipped + 1] = e .. "=" .. tostring(r)
    end
  end
  say("events: " .. valid .. "/" .. #self.EVENTS .. " valid"
    .. (skipped[1] and ("; " .. table.concat(skipped, "; ")) or "; none invalid"))
  if self._error then
    local errText = cut(self._error, 60)
    say("last error: " .. (errText or "(a secret value - not read)"))
  end
  if self.lastSkin then
    -- the spell's ID, and its NAME only when one was resolved from the ID. A
    -- cast-bar frame name is never a spell field (live: "name=CastBar-80CD..").
    local pre = "last skin cast: spell=" .. tostring(self.lastSkin.spellID or "unknown")
    local nm = self.lastSkin.name
    if nm ~= nil then
      add("Skinning skindiag: " .. pre .. " name=", nm, nil)
    else
      say(pre)
    end
  end
  if self.lastKill then
    local k = self.lastKill
    -- a GUID we can shorten is printed as ..XXXXXX; one the client marks
    -- secret is printed whole, because slicing it is exactly what is refused
    local post = ""
    if k.guid ~= nil then post = " g=" .. (guidSuffix(k.guid) or k.guid) end
    -- the NAME slot never repeats the GUID (live: "last kill: <guid> g=..EF7D0D")
    -- and says `unknown` when the client never gave a name at all.
    local shown = usableName(k.name, k.guid)
    if shown ~= nil then
      add("Skinning skindiag: last kill: ", shown, post)
    else
      add("Skinning skindiag: last kill: unknown", nil, post)
    end
  end
  -- Duplicates named by the card are dropped before the recorder sees them;
  -- printing the counts is how the next in-game run proves the drop happened
  -- instead of having to trust that it did.
  local sup = self._suppressed or {}
  local supBits = {}
  for _, k in ipairs({ "LOOT_CLOSED", "LOOT_SLOT_CLEARED", "SKILL_LINES_CHANGED",
    "TARGET_DEAD" }) do
    if (sup[k] or 0) > 0 then
      supBits[#supBits + 1] = k .. "x" .. tostring(sup[k])
    end
  end
  if #supBits > 0 then
    say("suppressed duplicates: " .. table.concat(supBits, " "))
  end
  -- What the RECORDER would store for the last corpse. This is the model the
  -- next in-game run verifies, without needing a second probe session.
  -- A line that carries client text comes back as
  --   { pre = <ours>, name = <client text>, post = <ours> }
  -- (see R.Describe) so the name is appended here instead of into a string
  -- this file would then measure — the c220ec7 crash was exactly that.
  if type(R) == "table" and type(R.Describe) == "function" then
    local okR, lines = pcall(R.Describe, R)
    if okR and type(lines) == "table" then
      for _, l in ipairs(lines) do
        if type(l) == "table" then
          add("Skinning skindiag: " .. tostring(l.pre or ""), l.name, l.post)
        elseif type(l) == "string" and safeLen(l) ~= nil then
          say(l)
        else
          say("record: a line could not be read (a secret value)")
        end
      end
    else
      local why = (type(lines) == "string" and cut(lines, 60)) or "a secret value"
      say("record: describe failed: " .. why)
    end
  else
    say("record: the recorder (Record.lua) did not load — nothing stored")
  end
  local n = #self.steps
  if n == 0 then
    say("captured: none (kill a skinnable, loot it, cast Skinning, loot it again, then /mp skindiag dump)")
    return
  end
  local cap = 60 -- the dump shows at most the last 60 steps
  local from = math.max(1, n - cap + 1)
  if from > 1 then
    say("... " .. (from - 1) .. " older step(s) held in the ring buffer")
  end
  -- Step lines use a short "sk " tag instead of the full prefix so the
  -- required fields (kind, creature, items, zone, position) fit inside
  -- the 120-char cap; the header lines above already name the channel.
  -- ONE bad line must not take the dump down: the card's failure was a whole
  -- dump lost to the last line, after every step had already been collected.
  for i = from, n do
    local s = self.steps[i]
    local okLine, lineErr = pcall(function()
      -- a collapsed run says how many events it stands for (our own text:
      -- measurable, so the cap below applies to it)
      local detail = s.detail or ""
      if type(s.repeats) == "number" and s.repeats > 1 then
        detail = detail .. " (x" .. tostring(s.repeats) .. ")"
      end
      local pre = string.format("sk %3d %.2f %s %s", s.n, s.t, s.event, detail)
      local room = self.LINE_CAP
      if s.name ~= nil then
        local label = s.nameLabel or " n="
        room = self.LINE_CAP - (safeLen(label) or 0)
          - (safeLen(s.name) or RESERVE)     -- nil for a SECRET: reserve instead
      end
      local len = safeLen(pre)          -- our own text: safe to measure
      if len and len > room then pre = pre:sub(1, room) end
      if s.name ~= nil then
        pre = pre .. (s.nameLabel or " n=") .. s.name   -- never measured after
      end
      DEFAULT_CHAT_FRAME:AddMessage(pre)
    end)
    if not okLine then
      say("step " .. tostring(s.n) .. " not printable: "
        .. (cut(tostring(lineErr), 50) or "a secret value"))
    end
  end
end


-- Compact, copyable dump for the options button and `/mp skindiag copy`.
-- Same facts as P:Diag (header, counts/accounting, last steps) but joined
-- into one string for the bug-report EditBox, trimmed to the last ~20 steps
-- so a paste usually fits Discord's 2000-character message limit. Nothing
-- is printed to chat. No account name or filesystem paths.
P.COMPACT_STEPS = 20
P.DISCORD_CAP = 2000

function P:DumpText(opts)
  opts = type(opts) == "table" and opts or {}
  local maxSteps = tonumber(opts.maxSteps) or self.COMPACT_STEPS or 20
  if maxSteps < 1 then maxSteps = 1 end
  local lines = {}
  local function say(m)
    if type(m) == "string" then lines[#lines + 1] = m end
  end

  local R = self:Recorder()
  local db = false
  if type(R) == "table" and type(R.IsEnabled) == "function" then
    local okE, on = pcall(R.IsEnabled, R)
    db = okE and on == true
  end
  say("capture " .. (self.capturing and "on" or "off")
    .. "; sub-option " .. (db and "ON" or "off") .. " (NodeTrail)"
    .. "; records: " .. (db
      and "NodeTrailDB.skinning, saved"
      or "session buffer only, nothing saved")
    .. "; steps=" .. tostring(#self.steps) .. "/" .. tostring(self.MAX_STEPS))
  if self._error then
    local errText = cut(self._error, 60)
    say("last error: " .. (errText or "(a secret value - not read)"))
  end

  if type(R) == "table" and type(R.Store) == "function" then
    local okS, store = pcall(R.Store, R)
    if okS and type(store) == "table" then
      local c = store.counts or {}
      say("counts kills=" .. tostring(c.kills or 0)
        .. " corpse-windows=" .. tostring(c.corpseWindows or 0)
        .. " skin-windows=" .. tostring(c.skinWindows or 0)
        .. " skin-casts=" .. tostring(c.skinCasts or 0))
      if type(R.AccountingLine) == "function" then
        local okA, line = pcall(R.AccountingLine, R, store)
        if okA and type(line) == "string" then
          say(line)
        end
      end
      local creatures = store.creatures
      if type(creatures) == "table" then
        local ids = {}
        for cid in pairs(creatures) do
          if type(cid) == "number" then ids[#ids + 1] = cid end
        end
        table.sort(ids)
        local capC = 12
        local shown = math.min(#ids, capC)
        for i = 1, shown do
          local row = creatures[ids[i]]
          if type(row) == "table" then
            say("cid " .. tostring(ids[i])
              .. " corpses=" .. tostring(row.corpses or 0)
              .. " kills=" .. tostring(row.kills or 0)
              .. " skinned=" .. tostring(row.skinned or 0)
              .. " skinWindows=" .. tostring(row.skinWindows or 0))
          end
        end
        if #ids > capC then
          say("... " .. tostring(#ids - capC) .. " more creature id(s)")
        end
      end
    elseif not okS then
      say("record: store failed: " .. (cut(tostring(store), 60) or "a secret value"))
    end
  else
    say("record: the recorder (Record.lua) did not load — nothing stored")
  end

  local n = #self.steps
  if n == 0 then
    say("captured: none (kill a skinnable, loot it, cast Skinning, loot it again)")
  else
    local from = math.max(1, n - maxSteps + 1)
    if from > 1 then
      say("... " .. tostring(from - 1) .. " older step(s) held in the ring buffer")
    end
    say("steps: last " .. tostring(n - from + 1) .. " of " .. tostring(n))
    for i = from, n do
      local s = self.steps[i]
      local okLine, lineOrErr = pcall(function()
        local detail = s.detail or ""
        if type(s.repeats) == "number" and s.repeats > 1 then
          detail = detail .. " (x" .. tostring(s.repeats) .. ")"
        end
        local pre = string.format("sk %3d %.2f %s %s", s.n, s.t, s.event, detail)
        if s.name ~= nil then
          pre = pre .. (s.nameLabel or " n=") .. s.name
        end
        return pre
      end)
      if okLine and type(lineOrErr) == "string" then
        say(lineOrErr)
      else
        say("step " .. tostring(s and s.n) .. " not printable")
      end
    end
  end

  local text = table.concat(lines, "\n")
  if type(text) == "string" and #text > (self.DISCORD_CAP or 2000) then
    text = "Note: this text is over Discord's 2000-character limit and may need splitting.\n"
      .. text
  end
  return text
end

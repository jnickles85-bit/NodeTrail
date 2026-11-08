-- Probe.lua — t_a5f41944 (Skinning 1/3: in-client event probe)
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
--   * NO SavedVariables: the buffer is in-memory state on this table.
--     The DB shape lives in SKINNING-DATA-MODEL.md (design only) and in
--     the implementation card — recording into a DB is NOT this card
--
-- The attribution rule implemented below is the card's HYPOTHESIS, made
-- explicit: skinning is the second loot window on the SAME corpse GUID,
-- arriving within SKIN_WINDOW seconds of a Skinning-cast. Until the probe
-- confirms that in-client, every classification it prints is a
-- hypothesis, not a fact. The dump shows the raw chain so a different
-- story (e.g. a distinct loot source for the skin window) can be read
-- straight off the evidence.

local addonName, pkg = ...
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
  "COMBAT_LOG_EVENT_UNFILTERED", -- death-only, filtered in the handler
  "SKILL_LINES_CHANGED",
  "PLAYER_ENTERING_WORLD",
}

P.MAX_STEPS = 120     -- ring buffer: the dump stays short and screenshot-able
P.SKIN_WINDOW = 60    -- a Skinning cast attributes a second loot window within this many seconds
P.LINE_CAP = 120      -- hard cap on every printed line (the card says ~120)
P.MAX_ITEMS_SHOWN = 3 -- per step line (the full list stays in the step record)

-- state (session-only; never written to any SavedVariable)
P.capturing = false
P.steps = {}          -- ring buffer of step records (full detail, uncut)
P._seq = 0
P._events = {}        -- event -> true | "invalid event" | error string
P.lastSkin = nil      -- { spellID=, name=, at= }
P.lastLoot = nil      -- { src=, at=, kind= }
P.lastKill = nil      -- { guid=, name=, at= }
P._skinSpells = {}    -- spellID -> name, confirmed by name match
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

local function cut(s, n)
  if type(s) ~= "string" then s = tostring(s) end
  if #s <= n then return s end
  return s:sub(1, n - 2) .. ".."
end

local function round4(v)
  return math.floor(v * 10000 + 0.5) / 10000
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
  if w.zone then out = out .. " z=" .. cut(w.zone, 14) end
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
local function guidSuffix(g)
  if type(g) ~= "string" or g == "" then return "-" end
  if #g <= 8 then return g end
  return ".." .. g:sub(#g - 5)
end

-- ── step recording ────────────────────────────────────────────────────
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
function P:ReadLoot()
  local items = {}
  local n = 0
  if type(GetNumLootItems) == "function" then
    local ok, v = pcall(GetNumLootItems)
    if ok and type(v) == "number" then n = v end
  end
  local src = nil
  if type(GetLootSourceInfo) == "function" and n > 0 then
    local ok, g = pcall(GetLootSourceInfo, 1)
    if ok and type(g) == "string" then src = g end
  end
  for i = 1, n do
    local link = nil
    if type(GetLootSlotLink) == "function" then
      local ok, l = pcall(GetLootSlotLink, i)
      if ok and type(l) == "string" then link = l end
    end
    local name, qty, qual = nil, 1, nil
    if type(GetLootSlotInfo) == "function" then
      -- classic contract: icon, name, count[, quality] (same read the
      -- NodeTrail recorder uses; itemID is recovered from the link)
      local ok, a, b, c, d = pcall(GetLootSlotInfo, i)
      if ok then
        if type(b) == "string" then name = b end
        if type(c) == "number" then qty = c end
        if type(d) == "number" then qual = d end
      end
    end
    local id = nil
    if link then
      local m = link:match("item:(%d+)")
      if m then id = tonumber(m) end
    end
    if id or name then
      items[#items + 1] = {
        id = id, name = name, qty = qty, quality = qual, link = link,
      }
    end
  end
  return items, src
end

-- ── the hypothesis (see the header): skin = the SECOND loot window on
-- the SAME corpse GUID, shortly after a Skinning cast ─────────────────
function P:Classify(src, t)
  if src == nil or type(src) ~= "string" then
    return "unattributed"
  end
  local prev = self.lastLoot
  if self.lastSkin
    and (t - self.lastSkin.at) <= self.SKIN_WINDOW
    and type(prev) == "table" and type(prev.src) == "string" and prev.src == src then
    return "skin"
  end
  return "corpse"
end

-- ── spell / skinning detection ────────────────────────────────────────
local function nameSkinny(name)
  if type(name) ~= "string" then return false end
  return name:lower():find("skin", 1, true) ~= nil
end

function P:IsSkinningSpell(spellID, spellName)
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

-- ── event handlers (each is a no-op until capture is toggled on) ─────
function P:OnCast(event, unit, castGUID, spellID, spellName)
  if not self.capturing then return end
  local t = nowT()
  local w = whereAmI()
  local who = (unit == "player") and "player" or tostring(unit or "?")
  local id = type(spellID) == "number" and spellID or nil
  local name = type(spellName) == "string" and spellName or nil
  local isSkin = (who == "player")
    and event == "UNIT_SPELLCAST_SUCCEEDED"
    and self:IsSkinningSpell(id, name)
  if isSkin then
    self.lastSkin = { spellID = id, name = name, at = t }
    if id and not self._skinSpells[id] then
      self._skinSpells[id] = name or tostring(id)
    end
  end
  local d = "k=" .. (isSkin and "skin-cast" or "cast")
  if id then d = d .. " s=" .. tostring(id) end
  if name then d = d .. " n=" .. cut(name, 16) end
  d = d .. " who=" .. who
  d = d .. locLine(w)
  self:Step(event, d, {
    who = who, spellID = id, name = name, skin = isSkin,
    zone = w.zone, sub = w.sub, map = w.map, x = w.x, y = w.y,
  })
end

function P:OnLootOpened()
  if not self.capturing then return end
  local t = nowT()
  local w = whereAmI()
  local items, src = self:ReadLoot()
  local srcName = nil
  if type(GetLootSourceName) == "function" then
    local ok, nm = pcall(GetLootSourceName)
    if ok and type(nm) == "string" and nm ~= "" then srcName = nm end
  end
  local kind = self:Classify(src, t)
  self.lastLoot = { src = src, at = t, kind = kind }
  local d = "k=" .. kind
  if src then d = d .. " g=" .. guidSuffix(src) end
  if srcName then d = d .. " n=" .. cut(srcName, 12) end
  local shown = math.min(#items, self.MAX_ITEMS_SHOWN)
  local bits = {}
  for i = 1, shown do
    local it = items[i]
    bits[i] = tostring(it.id or "?") .. "x" .. tostring(it.qty)
    .. (type(it.quality) == "number" and ("q" .. tostring(it.quality)) or "")
  end
  d = d .. " i=" .. (table.concat(bits, ",") ~= "" and table.concat(bits, ",") or "-")
    .. (#items > shown and ("+" .. (#items - shown)) or "")
  d = d .. locLine(w)
  self:Step("LOOT_OPENED", d, {
    kind = kind, src = src, srcName = srcName, items = items,
    zone = w.zone, sub = w.sub, map = w.map, x = w.x, y = w.y,
  })
end

function P:OnSlotCleared(...)
  if not self.capturing then return end
  local a1 = select(1, ...)
  local w = whereAmI()
  local d = "k=slot-cleared slot=" .. (type(a1) == "number" and tostring(a1) or "-")
  d = d .. locLine(w)
  self:Step("LOOT_SLOT_CLEARED", d, {
    slot = a1, zone = w.zone, sub = w.sub, map = w.map, x = w.x, y = w.y,
  })
end

function P:OnLootClosed()
  if not self.capturing then return end
  local w = whereAmI()
  local d = "k=loot-closed prev=" .. (self.lastLoot and self.lastLoot.kind or "-")
  d = d .. locLine(w)
  self:Step("LOOT_CLOSED", d, {
    zone = w.zone, sub = w.sub, map = w.map, x = w.x, y = w.y,
  })
end

function P:OnUnitDied(unit)
  if not self.capturing then return end
  local t = nowT()
  local w = whereAmI()
  local name, guid = nil, nil
  if type(unit) == "string" and unit ~= "player" then
    if type(GetUnitName) == "function" then
      local ok, nm = pcall(GetUnitName, unit)
      if ok and type(nm) == "string" and nm ~= "" then name = nm end
    end
    if type(GetUnitGUID) == "function" then
      local ok, g = pcall(GetUnitGUID, unit)
      if ok and type(g) == "string" then guid = g end
    end
    self.lastKill = { guid = guid, name = name, at = t }
  end
  local d = "k=death unit=" .. tostring(unit or "?")
  if name then d = d .. " n=" .. cut(name, 16) end
  if guid then d = d .. " g=" .. guidSuffix(guid) end
  if unit == "player" then d = d .. " [YOU DIED]" end
  d = d .. locLine(w)
  self:Step("UNIT_DIED", d, {
    unit = unit, guid = guid, name = name,
    zone = w.zone, sub = w.sub, map = w.map, x = w.x, y = w.y,
  })
end

-- COMBAT_LOG_EVENT_UNFILTERED — deaths only (the card says so: the
-- unfiltered feed is voluminous and only the death marker matters for
-- the kill step). Classic varargs: time, event, sourceGUID,
-- sourceName, sourceFlags, destGUID, destName, destFlags, then key/value
-- cl strings ("SpellId", "SpellName", "targetDead", ...).
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
  if type(destGUID) == "string" and type(destName) == "string" then
    self.lastKill = { guid = destGUID, name = destName, at = nowT() }
  end
  local w = whereAmI()
  local d = "k=death cl=" .. tostring(ev or "?") .. " mine=" .. mine
  if spellID then d = d .. " s=" .. tostring(spellID) end
  if spellName then d = d .. " n=" .. cut(tostring(spellName), 14) end
  if destName then d = d .. " dest=" .. cut(destName, 14) end
  if destGUID then d = d .. " g=" .. guidSuffix(destGUID) end
  d = d .. locLine(w)
  self:Step("COMBAT_LOG_EVENT_UNFILTERED", d, {
    destGUID = destGUID, destName = destName, spellID = spellID,
    zone = w.zone, sub = w.sub, map = w.map, x = w.x, y = w.y,
  })
end

function P:OnSkillLines(...)
  if not self.capturing then return end
  local a1 = select(1, ...)
  local w = whereAmI()
  local d = "k=skill-lines arg=" .. (type(a1) == "number" and tostring(a1) or "-")
  d = d .. locLine(w)
  self:Step("SKILL_LINES_CHANGED", d, {
    arg = a1, zone = w.zone, sub = w.sub, map = w.map, x = w.x, y = w.y,
  })
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
  local frame = CreateFrame("Frame")
  self.frame = frame
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
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
      self:OnCombat(...)
    elseif event == "SKILL_LINES_CHANGED" then
      self:OnSkillLines(...)
    elseif event == "PLAYER_ENTERING_WORLD" then
      self:OnEnterWorld(...)
    end
  end
  frame:SetScript("OnEvent", function(_, event, ...)
    local ok, err = pcall(dispatch, event, ...)
    if not ok then
      self._error = tostring(err)
    end
  end)
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
    else
      local msg = tostring(err)
      if msg:find("unknown event", 1, true) then
        self._events[e] = "invalid event"
      else
        self._events[e] = msg
      end
    end
  end
end

-- /mp skindiag dump — the in-client evidence channel. One line per step,
-- in capture order, every line hard-capped at LINE_CAP chars (the chat
-- line is the only evidence Forever 16001 gives us).
function P:Diag()
  local function say(m)
    local line = "Skinning skindiag: " .. m
    if #line > self.LINE_CAP then
      line = line:sub(1, self.LINE_CAP)
    end
    DEFAULT_CHAT_FRAME:AddMessage(line)
  end
  say("capture " .. (self.capturing and "on" or "off")
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
    say("last error: " .. cut(self._error, 60))
  end
  if self.lastSkin then
    say("last skin cast: spell=" .. tostring(self.lastSkin.spellID or "?")
      .. " name=" .. tostring(self.lastSkin.name or "?"))
  end
  if self.lastKill then
    say("last kill: " .. tostring(self.lastKill.name or self.lastKill.guid or "?")
      .. " " .. tostring(self.lastKill.guid or ""))
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
  for i = from, n do
    local s = self.steps[i]
    local line = string.format("sk %3d %.2f %s %s", s.n, s.t, s.event, s.detail or "")
    if #line > self.LINE_CAP then
      line = line:sub(1, self.LINE_CAP)
    end
    DEFAULT_CHAT_FRAME:AddMessage(line)
  end
end

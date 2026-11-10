-- ItemNames.lua — ONE item id -> name resolver (t_e27da774).
--
-- Mightie's panel printed `item 249399  4%` under Briarthorn, and the card that
-- followed dressed it up as `unknown item 249399`. Neither is a name. 249399 is
-- **Frilled Lichen**, a real reagent his alchemy uses, and the name was sitting
-- in the loot window the moment he gathered it:
--
--   |cnIQ2:|Hitem:249399::::::::21:1486:::::::::|h[Frilled Lichen]|h|r
--   (his own SavedVariables, NodeTrailDB.herbs, record t=1794159424)
--
-- The old path stored the id and asked GetItemInfo at DRAW time. GetItemInfo
-- answers nil for an id this client has not cached — normal for a custom item —
-- so a name that had been available at capture time was simply gone.
--
-- The rule this file implements, once, for herbs, skinned items and corpse
-- drops alike:
--
--   CAPTURE  the name rides with the id, copied verbatim out of the loot slot's
--            own link (N.FromLink). The id stays the key; the record gains a
--            `name` field. A record that has no name (anything written before
--            this change) still works.
--   DRAW     stored name -> a name our own data ships (HerbData's researched
--            table) -> GetItemInfo -> the marker
--            `item <id> (name unavailable)`. Never a bare number printed as if
--            it were a name.
--   RETRY    an id GetItemInfo could not name is asked again when the client
--            announces item data (ITEM_DATA_LOAD_RESULT / GET_ITEM_INFO_RECEIVED
--            when the client registers them, otherwise on the next loot/bag
--            event), and the panel is re-polled so the row can change.
--   REPORT   /nt ttdiag prints, per id, what the record stored, what the client
--            answered and what the panel prints; ids that ended up with the
--            marker are listed with the lookups that failed.
--
-- SECRET strings: a client value may be SHOWN but never measured, sliced or
-- formatted. A name is therefore only ever copied — out of the link for a
-- record, or straight through to the panel — and a value `issecretvalue` calls
-- secret is not stored, not compared and not measured (the link itself is
-- checked first: a secret link is never searched with a pattern).
--
-- Load order: this file loads before Data/HerbData.lua (see MightiePack.toc)
-- and long before Modules/Skinning (which resolves it at CALL time, because a
-- tooltip must also work on a client that has no skinning module loaded).
local _, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

local N = {}
ns.ItemNames = N

-- The one marker a nameless id may be printed with. Never a bare id: a number
-- where a name belongs is exactly the bug this card is about.
N.MARKER = "name unavailable"

-- Item-data announcements, tried in this order. A client that has neither gets
-- the loot/bag events instead — the retry then rides the next thing that makes
-- the client fetch item data anyway.
N.ITEM_EVENTS = { "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }
N.FALLBACK_EVENTS = { "LOOT_OPENED", "BAG_UPDATE_DELAYED" }

N._diag = {
  asks = {},      -- id -> how many times GetItemInfo was asked this session
  missing = {},   -- id -> true while the panel has to print the marker
  itemData = 0,   -- item-data events seen
  retried = 0,    -- ids re-asked because of them
}

local function isSecret(v)
  if type(issecretvalue) ~= "function" then
    return false
  end
  local ok, s = pcall(issecretvalue, v)
  return ok and s == true
end
N.isSecret = isSecret

-- ── capture: the name the loot slot itself carries ────────────────────────
-- "|cnIQ2:|Hitem:249399:...|h[Frilled Lichen]|h|r" -> "Frilled Lichen".
-- Returns name, why — `why` always says which lookup failed, so a nil name is
-- never mistaken for a name. The NAME is copied out of the link verbatim: this
-- function searches the link (a client string, guarded below), and nothing
-- downstream measures, slices or formats the name it returns.
function N.FromLink(link)
  if link == nil then
    return nil, "the loot slot had no item link"
  end
  if isSecret(link) then
    -- A secret may be shown but not searched: a pattern match on one is a
    -- measure, and the client raises on it.
    return nil, "the loot slot's link is a secret string (not searched)"
  end
  if type(link) ~= "string" or link == "" then
    return nil, "the loot slot had no usable item link"
  end
  local ok, name = pcall(function() return link:match("|h%[(.-)%]|h") end)
  if not ok then
    return nil, "reading the item link raised"
  end
  if type(name) ~= "string" or name == "" then
    -- A link without the |h[..]|h wrapper (some custom clients) still brackets
    -- the name; take it whole rather than give up on a name that is right there.
    ok, name = pcall(function() return link:match("%[([^%]]*)%]") end)
  end
  if not ok or type(name) ~= "string" or name == "" then
    return nil, "the item link carries no bracketed name"
  end
  if isSecret(name) then
    return nil, "the item link's name is a secret string (not stored)"
  end
  return name, nil
end

-- What a record should store for a looted slot: the link's name, else the
-- slot's own name field when the client gives one we may store. nil means the
-- record keeps the id only — that is a legal, backward-compatible record.
function N.Capture(link, slotName)
  local name, why = N.FromLink(link)
  if name then
    return name, nil
  end
  if slotName ~= nil and not isSecret(slotName)
    and type(slotName) == "string" and slotName ~= "" then
    return slotName, nil
  end
  return nil, why or "the loot slot reported no name"
end

-- The usable form of a STORED name, and why when it is not usable.
function N.StoredName(v)
  if v == nil then
    return nil, "absent"
  end
  if isSecret(v) then
    return nil, "secret"
  end
  if type(v) ~= "string" or v == "" then
    return nil, "absent"
  end
  return v, "ok"
end

-- ── draw: the client's own answer ─────────────────────────────────────────
-- GetItemInfo first (the name this client caches), C_Item.GetItemInfo when the
-- legacy global is gone. Asked through pcall: a client that refuses answers
-- with an error, and a refusal is a report, not a name.
local function askClient(id)
  local fn, label
  if type(GetItemInfo) == "function" then
    fn, label = GetItemInfo, "GetItemInfo"
  elseif type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function" then
    fn, label = C_Item.GetItemInfo, "C_Item.GetItemInfo"
  else
    return nil, "neither GetItemInfo nor C_Item.GetItemInfo exists on this client"
  end
  local ok, n = pcall(fn, id)
  if not ok then
    return nil, label .. " raised"
  end
  if isSecret(n) then
    return nil, label .. " answered a secret string"
  end
  if type(n) ~= "string" or n == "" then
    return nil, label .. " answered nothing"
  end
  return n, nil
end

-- Ask, and count the ask: "asked 3 times, still nothing" is the evidence an
-- operator needs in /nt ttdiag, and it is what proves the item-data retry ran.
function N.ClientName(id)
  id = tonumber(id)
  if id == nil then
    return nil, "no item id to ask about"
  end
  N._diag.asks[id] = (N._diag.asks[id] or 0) + 1
  return askClient(id)
end

function N.Asks(id)
  return N._diag.asks[tonumber(id) or -1] or 0
end

-- ── the one resolution order ──────────────────────────────────────────────
-- The two name sources that need NO lookup: what the record captured, then a
-- name our own data ships (staticTable — HerbData's researched herb table).
local function pickStored(id, storedName, staticTable)
  local stored = N.StoredName(storedName)
  if stored then
    return stored, "stored"
  end
  if id ~= nil and type(staticTable) == "table" then
    local own = staticTable[id]
    if type(own) == "string" and own ~= "" and not isSecret(own) then
      return own, "table"
    end
  end
  return nil, "none"
end

-- stored name -> our own shipped names -> GetItemInfo -> nil.
-- Returns name, how — `how` names the source so a caller never mistakes a
-- fallback for a hit. GetItemInfo is only asked when nothing above answered.
function N.Resolve(id, storedName, staticTable)
  id = tonumber(id)
  local name, how = pickStored(id, storedName, staticTable)
  if name then
    return name, how
  end
  if id ~= nil then
    local clientName = N.ClientName(id)
    if clientName then
      return clientName, "client"
    end
  end
  return nil, "none"
end

-- The string the panel prints, and how it got it.
function N.Label(id, storedName, staticTable)
  id = tonumber(id)
  local name, how = N.Resolve(id, storedName, staticTable)
  if name then
    if id ~= nil then
      N._diag.missing[id] = nil
    end
    return name, how
  end
  if id ~= nil then
    N._diag.missing[id] = true
    return ("item %d (%s)"):format(id, N.MARKER), "none"
  end
  return "item ? (" .. N.MARKER .. ")", "none"
end

-- ── /nt ttdiag: what was stored, what the client said, what is printed ────
-- One line per id, in ONE format for herbs and for beast drops:
--
--   item id: 249399 -> stored "Frilled Lichen" · GetItemInfo answered nothing
--                      · corpse · the panel prints "Frilled Lichen"
--
-- The client is asked even when a stored name already answers, because the
-- operator's question is "did this client know the id" and a disagreement is
-- the signal that the RECORD's keying is wrong. `sides` is the caller's own
-- word for where the id was recorded ("corpse", "skin", "gather"), or nil.
function N.Describe(id, storedName, staticTable, sides)
  id = tonumber(id)
  local line = ("item id: %s -> "):format(tostring(id))
  local stored, storedState = N.StoredName(storedName)
  if stored then
    line = line .. 'stored "' .. stored .. '"'
  elseif storedState == "secret" then
    line = line .. "a stored name is a secret string (not used)"
  else
    line = line .. "no stored name"
  end
  local clientName, why = nil, nil
  if id ~= nil then
    clientName, why = N.ClientName(id)
  end
  if clientName then
    line = line .. ' · GetItemInfo answered "' .. clientName .. '"'
    if stored and stored ~= clientName then
      line = line .. " (the client and the stored name disagree; the stored one is printed)"
    end
  else
    line = line .. " · " .. tostring(why or "no item id to ask about")
    local asks = N.Asks(id)
    if asks > 1 then
      line = line .. (" (asked %d times)"):format(asks)
    end
  end
  if type(sides) == "string" and sides ~= "" then
    line = line .. " · " .. sides
  end
  local printed = stored
  if printed == nil then
    printed = pickStored(id, nil, staticTable)
  end
  if printed == nil then
    printed = clientName
  end
  if printed == nil then
    if id ~= nil then
      printed = ("item %d (%s)"):format(id, N.MARKER)
    else
      printed = "item ? (" .. N.MARKER .. ")"
    end
  end
  line = line .. ' · the panel prints "' .. printed .. '"'
  return line
end

-- ── retry when the client announces item data ─────────────────────────────
-- Re-poll the panel so a row that was showing the marker can become a name
-- without a re-hover. Safe on a client with no tooltip module.
function N.Refresh()
  local T = ns.Tooltip
  if type(T) ~= "table" or type(T.Poll) ~= "function" then
    return false
  end
  if type(GameTooltip) ~= "table" then
    return false
  end
  local ok = pcall(T.Poll, T, GameTooltip)
  N._diag.refreshed = (N._diag.refreshed or 0) + 1
  return ok
end

function N.OnItemData(event)
  N._diag.itemData = (N._diag.itemData or 0) + 1
  N._diag.lastItemData = tostring(event or "?")
  N._diag.retried = 0
  -- Ask again for every id that is currently printing the marker: this is the
  -- moment the client may have learned it.
  for id in pairs(N._diag.missing) do
    N.ClientName(id)
    N._diag.retried = (N._diag.retried or 0) + 1
  end
  return N.Refresh()
end

-- Register the retry clock. Item-data events when THIS client has them (the
-- registration is tried and its failure classified, never assumed); otherwise
-- the next loot/bag event is the retry, because that is when the client fetches
-- item data anyway. Nothing here touches the client's restricted event-validity
-- namespace — it is Blizzard-only and the client answers it with a UI-block
-- modal rather than a Lua error (see tests/event_gate_spec.lua).
function N.Watch()
  if N._watcher ~= nil then
    return true
  end
  if type(CreateFrame) ~= "function" then
    N._diag.watch = "CreateFrame is not on this client — no item-data retry clock"
    return false
  end
  local ok, frame = pcall(CreateFrame, "Frame", "NodeTrailItemNameWatch")
  if not ok or type(frame) ~= "table" or type(frame.RegisterEvent) ~= "function" then
    N._diag.watch = "CreateFrame refused the item-data watch frame"
    return false
  end
  local registered = {}
  for _, ev in ipairs(N.ITEM_EVENTS) do
    if pcall(frame.RegisterEvent, frame, ev) then
      registered[#registered + 1] = ev
    end
  end
  local fallback = false
  if #registered == 0 then
    for _, ev in ipairs(N.FALLBACK_EVENTS) do
      if pcall(frame.RegisterEvent, frame, ev) then
        registered[#registered + 1] = ev
        fallback = true
      end
    end
  end
  if type(frame.SetScript) ~= "function" then
    N._diag.watch = "the watch frame has no SetScript"
    return false
  end
  frame:SetScript("OnEvent", function(_, event)
    N.OnItemData(event)
  end)
  N._watcher = frame
  N._diag.watch = table.concat(registered, ", ")
  if fallback then
    N._diag.watch = N._diag.watch
      .. " (this client announces no item data; the retry rides the loot/bag events)"
  end
  return true
end

-- ── the report block ─────────────────────────────────────────────────────
-- Ids that ended up with the marker, and the lookups that failed for them.
function N.UnnamedLines(prefix)
  prefix = prefix or "item names: "
  local ids = {}
  for id in pairs(N._diag.missing) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  local out = {}
  for _, id in ipairs(ids) do
    local line = prefix .. ("id %s could not be named — lookups attempted: "
      .. "the record's stored name (absent), GetItemInfo (%d ask(s)"):format(
      tostring(id), N.Asks(id))
    if (N._diag.itemData or 0) > 0 then
      line = line .. ("; %d item-data event(s) seen, %d id(s) re-asked")
        :format(N._diag.itemData, N._diag.retried or 0)
    end
    out[#out + 1] = line .. ")"
  end
  return out
end

-- What the retry clock is doing, for /nt ttdiag.
function N.RetryLine()
  local watch = N._diag.watch or "not started"
  if (N._diag.itemData or 0) == 0 then
    return "item names: retry clock " .. watch .. " · no item-data event seen yet"
  end
  return ("item names: retry clock %s · %d item-data event(s), last %s · %d id(s) re-asked")
    :format(watch, N._diag.itemData, tostring(N._diag.lastItemData or "?"), N._diag.retried or 0)
end

return N

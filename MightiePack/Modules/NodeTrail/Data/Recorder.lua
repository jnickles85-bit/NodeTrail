local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

local R = {}
ns.Recorder = R

R.HERB_SPELL_IDS = { [2366] = true, [2368] = true, [3570] = true, [11993] = true }
R.PENDING_WINDOW = 5
R.SCHEMA = 1

function ns.GetHerbDB()
  if type(NodeTrailDB) ~= "table" then
    ns.GetDB()
  end
  if type(NodeTrailDB.herbs) ~= "table" then
    NodeTrailDB.herbs = { schema = R.SCHEMA, total = 0, maps = {} }
  end
  if type(NodeTrailDB.herbs.maps) ~= "table" then
    NodeTrailDB.herbs.maps = {}
  end
  if type(NodeTrailDB.herbs.total) ~= "number" then
    NodeTrailDB.herbs.total = 0
  end
  return NodeTrailDB.herbs
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
      local icon, nm, q = GetLootSlotInfo(i)
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

-- skinning_pending_attrib_spec.lua
--
-- Review NO-GO on PR #21 (8b83195): a GUID-less loot window under a pending
-- Skinning SUCCEEDED was filled from cast.guid or DeadTargetGuid() for the
-- full 60s SKIN_WINDOW, with no loot-kind check, and TARGET_CHANGED /
-- LOOT_CLOSED did not clear that attribution. Reproduced:
--   A. GUID-less Peacebloom after 8613 stored as skinItems 2447, skinned=true
--   B. pinned cast + retarget + GUID-less herb filed under the pinned corpse
--   H. GUID-less chest while targeting another dead mob skins the wrong
--      corpse and steals taken
-- Herb, chest, and fishing GUID-less windows under a pending cast must not
-- be classified as skin. The friend pack-skin repro (kill, wait 15s, skin
-- a targeted corpse with a GUID-less leather window) still has to pass.
--
-- RED on 8b83195.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end }
SlashCmdList = {}
StaticPopupDialogs = {}
StaticPopup_Show = function() end
OKAY = "Okay"
CANCEL = "Cancel"
ReloadUI = function() end
GameTooltip = {
  SetOwner = function() end, SetText = function() end,
  AddLine = function() end, Show = function() end, Hide = function() end,
}
CopyTable = function(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = CopyTable(v) end
  return r
end

local now = 1000
GetTime = function() return now end
GetZone = function() return "The Barrens" end
GetSubzone = function() return "The Crossroads" end
GetRealmName = function() return "Forever" end
GetUnitName = function(u) if u == "player" then return "Mightie" end end
-- Do not resolve 8613 (or any skin ID) to a name containing "skin": the
-- 4th cast argument is a CastBar frame, and GetSpellInfo must not paper
-- over a missing ID via nameSkinny.
GetSpellInfo = function() return nil end
C_Map = {
  GetBestMapForUnit = function() return 1413 end,
  GetPlayerMapPosition = function()
    return { GetXY = function() return 0.51, 0.33 end }
  end,
}

local targetName, targetGuid, targetDead = nil, nil, false
UnitExists = function(u) return u == "target" and targetGuid ~= nil end
UnitIsDead = function(u) return u == "target" and targetDead == true end
UnitName = function(u) if u == "target" then return targetName end end
UnitGUID = function(u) if u == "target" then return targetGuid end end

local loot, lootSource, lootSourceName = {}, nil, nil
GetNumLootItems = function() return #loot end
GetLootSlotLink = function(i) return loot[i] and loot[i].link end
GetLootSlotInfo = function(i)
  local s = loot[i]
  if s then return "icon", s.name, s.qty, s.quality end
end
GetLootSourceInfo = function() return lootSource end
GetLootSourceName = function() return lootSourceName end

local frames = {}
CreateFrame = function()
  local f = { scripts = {}, events = {} }
  f.SetScript = function(self, n, fn) self.scripts[n] = fn end
  f.GetScript = function(self, n) return self.scripts[n] end
  f.RegisterEvent = function(self, n) self.events[n] = true end
  f.UnregisterEvent = function(self, n) self.events[n] = nil end
  frames[#frames + 1] = f
  return f
end

local files = {
  "Core.lua",
  "Modules.lua",
  "Modules/NodeTrail/Config.lua",
  "Modules/Skinning/Probe.lua",
  "Modules/Skinning/Record.lua",
  "Modules/Skinning/Core.lua",
}
local pkg = {}
for _, f in ipairs(files) do
  local chunk, err = loadfile(root .. "/MightiePack/" .. f)
  check(chunk ~= nil, "loadfile " .. f .. ": " .. tostring(err))
  if chunk then
    local ok, e = pcall(chunk, "MightiePack", pkg)
    check(ok, "load " .. f .. ": " .. tostring(e))
  end
end
for i = #frames, 1, -1 do
  local f = frames[i]
  if f.events and f.events.ADDON_LOADED and f.scripts and f.scripts.OnEvent then
    pcall(f.scripts.OnEvent, f, "ADDON_LOADED", "MightiePack")
    break
  end
end

local P = pkg.Skinning and pkg.Skinning.Probe
local R = pkg.Skinning and pkg.Skinning.Recorder
check(type(P) == "table" and type(R) == "table", "probe and recorder loaded")

-- Realistic client 4th argument: a CastBar frame name that does NOT
-- contain "skin", so IsSkinningSpell must succeed on the ID path alone.
local CASTBAR = "CastBar-1B595C80CD3B37"

local function guidFor(n)
  return ("Creature-0-7072-1-48-2956-%012X"):format(n)
end

local PEACEBLOOM = { link = "|cffffffff|Hitem:2447::::::::1:::::::|h[Peacebloom]|h|r",
  name = "Peacebloom", qty = 1, quality = 1 }
local CHEST_ITEM = { link = "|cffffffff|Hitem:117::::::::1:::::::|h[Tough Jerky]|h|r",
  name = "Tough Jerky", qty = 1, quality = 1 }
local FISH = { link = "|cffffffff|Hitem:6291::::::::1:::::::|h[Raw Brilliant Smallfish]|h|r",
  name = "Raw Brilliant Smallfish", qty = 1, quality = 1 }
local LEATHER = { link = "|cffffffff|Hitem:2318::::::::1:::::::|h[Light Leather]|h|r",
  name = "Light Leather", qty = 1, quality = 1 }

if type(P) == "table" and type(R) == "table" then
  pkg.NodeTrail.SetSkinningEnabled(true)
  pkg.Skinning.Enable()
  local frame = P.frame
  local onEvent = frame and frame.GetScript and frame:GetScript("OnEvent")
  check(type(onEvent) == "function", "OnEvent installed")
  local function fire(event, ...) onEvent(frame, event, ...) end

  local function succeedSkin(spellID)
    fire("UNIT_SPELLCAST_START", "player", CASTBAR, spellID, CASTBAR)
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", CASTBAR, spellID, CASTBAR)
    fire("UNIT_SPELLCAST_STOP", "player", CASTBAR, spellID, CASTBAR)
  end

  local function openWindow(items, src)
    loot = items or {}
    lootSource, lootSourceName = src, nil
    fire("LOOT_OPENED")
    local kind = P.lastLoot and P.lastLoot.kind
    loot = {}
    fire("LOOT_CLOSED")
    return kind
  end

  local function hasItem(list, id)
    if type(list) ~= "table" then return false end
    for _, it in ipairs(list) do
      if type(it) == "table" and it.itemID == id then return true end
    end
    return false
  end

  -- ══════════════════════════════════════════════════════════════════
  -- 0. Spell IDs: ranks + Forever IDs are detected with a CastBar name
  --    that does not contain "skin".
  -- ══════════════════════════════════════════════════════════════════
  do
    local ids = { 8613, 8617, 8618, 10768, 1240952, 1240963, 1240974, 1240987 }
    check(type(P.SKIN_SPELL_IDS) == "table", "SKIN_SPELL_IDS is a table")
    for _, id in ipairs(ids) do
      check(P.SKIN_SPELL_IDS[id] == true,
        "SKIN_SPELL_IDS contains " .. tostring(id))
      check(P:IsSkinningSpell(id, CASTBAR) == true,
        "IsSkinningSpell(" .. id .. ", " .. CASTBAR .. ") is true on the ID path")
    end
    check(P:IsSkinningSpell(12345, CASTBAR) ~= true,
      "an unknown ID with a CastBar name is not a skinning spell")
  end

  -- ══════════════════════════════════════════════════════════════════
  -- Friend repro still works: kill, wait 15s, SUCCEEDED, GUID-less
  -- leather window while targeting that corpse. rec.skinned = true.
  -- ══════════════════════════════════════════════════════════════════
  do
    local g = guidFor(1)
    now = 3000
    fire("UNIT_DIED", g)
    now = 3015
    targetGuid, targetName, targetDead = g, "Plainstrider", true
    succeedSkin(8613)
    now = 3015.5
    local kind = openWindow({ LEATHER }, nil)
    local rec = R:Find(g)
    check(kind == "skin",
      "friend: the GUID-less leather window just after SUCCEEDED is skin (got "
      .. tostring(kind) .. ")")
    check(type(rec) == "table" and rec.skinned == true,
      "friend: the targeted corpse is marked skinned")
    check(type(rec) == "table" and hasItem(rec.skinItems, 2318),
      "friend: Light Leather is in skinItems")
  end

  -- ══════════════════════════════════════════════════════════════════
  -- A. GUID-less Peacebloom after 8613 must not become skin loot.
  --    Opens well after TARGET_ATTRIB_WINDOW (still inside SKIN_WINDOW).
  -- ══════════════════════════════════════════════════════════════════
  do
    local g = guidFor(2)
    now = 4000
    fire("UNIT_DIED", g)
    now = 4011
    targetGuid, targetName, targetDead = g, "Plainstrider", true
    succeedSkin(8613)
    now = 4020 -- 9s later: inside 60s, outside a few-second attrib bound
    local kind = openWindow({ PEACEBLOOM }, nil)
    local rec = R:Find(g)
    check(kind ~= "skin",
      "A: GUID-less Peacebloom well after SUCCEEDED is not skin (got "
      .. tostring(kind) .. ")")
    check(not (type(rec) == "table" and rec.skinned == true),
      "A: the corpse is not marked skinned by a Peacebloom window")
    check(not (type(rec) == "table" and hasItem(rec.skinItems, 2447)),
      "A: Peacebloom 2447 is not in skinItems")
  end

  -- ══════════════════════════════════════════════════════════════════
  -- B. Pinned cast + retarget + GUID-less herb must not file under
  --    the pinned corpse or consume the pending cast.
  -- ══════════════════════════════════════════════════════════════════
  do
    local g = guidFor(3)
    now = 5000
    fire("UNIT_DIED", g)
    targetGuid, targetName, targetDead = g, "Plainstrider", true
    now = 5001
    -- a real, non-empty corpse window pins the following cast
    openWindow({
      { link = "|cffffffff|Hitem:7100::::::::1:::::::|h[Scorpid Blood]|h|r",
        name = "Scorpid Blood", qty = 1, quality = 1 },
    }, g)
    now = 5002
    succeedSkin(8613)
    check(P.lastSkin and P.lastSkin.guid == g,
      "B: the cast is pinned to the looted corpse")
    -- retarget off the corpse (a herb node is not a dead unit)
    targetGuid, targetName, targetDead = "GameObject-0-1-1-1-1618-00000001", "Peacebloom", false
    fire("PLAYER_TARGET_CHANGED")
    now = 5002.4
    local kind = openWindow({ PEACEBLOOM }, nil)
    local rec = R:Find(g)
    check(kind ~= "skin",
      "B: GUID-less herb after retarget is not skin (got " .. tostring(kind) .. ")")
    check(not (type(rec) == "table" and hasItem(rec.skinItems, 2447)),
      "B: Peacebloom is not filed under the pinned corpse")
    -- the pin must still be claimable by the real skin window on g
    targetGuid, targetName, targetDead = g, "Plainstrider", true
    now = 5003
    local skinKind = openWindow({ LEATHER }, g)
    rec = R:Find(g)
    check(skinKind == "skin",
      "B: the later skin window on the pinned corpse still claims the cast (got "
      .. tostring(skinKind) .. ")")
    check(type(rec) == "table" and rec.skinned == true,
      "B: the pinned corpse is marked skinned by its own skin window")
    check(type(rec) == "table" and hasItem(rec.skinItems, 2318),
      "B: Light Leather is on the pinned corpse, not the herb")
  end

  -- ══════════════════════════════════════════════════════════════════
  -- H. GUID-less chest while targeting another dead mob must not skin
  --    the wrong corpse or steal taken.
  -- ══════════════════════════════════════════════════════════════════
  do
    local a = guidFor(4)
    local b = guidFor(5)
    now = 6000
    fire("UNIT_DIED", a)
    fire("UNIT_DIED", b)
    now = 6012
    targetGuid, targetName, targetDead = a, "Plainstrider", true
    succeedSkin(8613)
    -- retarget to a different dead mob, then open a GUID-less chest
    targetGuid, targetName, targetDead = b, "Plainstrider", true
    fire("PLAYER_TARGET_CHANGED")
    now = 6012.5
    local kind = openWindow({ CHEST_ITEM }, nil)
    local recA, recB = R:Find(a), R:Find(b)
    check(kind ~= "skin",
      "H: GUID-less chest while targeting another corpse is not skin (got "
      .. tostring(kind) .. ")")
    check(not (type(recB) == "table" and recB.skinned == true),
      "H: the other dead mob is not marked skinned")
    check(not (type(recB) == "table" and hasItem(recB.skinItems, 117)),
      "H: chest loot is not in the other corpse's skinItems")
    check(not (type(recA) == "table" and hasItem(recA.skinItems, 117)),
      "H: chest loot is not in the skinned-at corpse's skinItems either")
    -- the pending cast must still be claimable by A's real skin window
    targetGuid, targetName, targetDead = a, "Plainstrider", true
    now = 6013
    local skinKind = openWindow({ LEATHER }, a)
    recA = R:Find(a)
    check(skinKind == "skin",
      "H: the real skin window on the cast's corpse still claims it (got "
      .. tostring(skinKind) .. ")")
    check(type(recA) == "table" and recA.skinned == true,
      "H: corpse A is marked skinned by its own window, taken was not stolen")
  end

  -- ══════════════════════════════════════════════════════════════════
  -- Herb / chest / fishing GUID-less windows under a pending cast
  -- (retarget away from the corpse) are not skin.
  -- ══════════════════════════════════════════════════════════════════
  do
    local function notSkinAfterRetarget(label, item, newTarget, newName, newDead)
      local g = guidFor(10 + #label)
      now = now + 70
      fire("UNIT_DIED", g)
      now = now + 12
      targetGuid, targetName, targetDead = g, "Plainstrider", true
      succeedSkin(8613)
      targetGuid, targetName, targetDead = newTarget, newName, newDead
      fire("PLAYER_TARGET_CHANGED")
      now = now + 0.3
      local kind = openWindow({ item }, nil)
      local rec = R:Find(g)
      check(kind ~= "skin",
        label .. ": GUID-less window is not skin (got " .. tostring(kind) .. ")")
      check(not (type(rec) == "table" and rec.skinned == true),
        label .. ": corpse is not marked skinned")
    end
    notSkinAfterRetarget("herb", PEACEBLOOM, "GameObject-0-1-1-1-1618-00000002", "Peacebloom", false)
    notSkinAfterRetarget("chest", CHEST_ITEM, "GameObject-0-1-1-1-2852-00000003", "Battered Chest", false)
    notSkinAfterRetarget("fishing", FISH, nil, nil, false)
  end
end

if failed > 0 then
  io.stderr:write(failed .. " failed\n")
  os.exit(1)
end
print("ok")

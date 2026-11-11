-- skin_tooltip_skinned_spec.lua
--
-- Friend report on v0.3.4-beta (8e2a95a):
--   * the beast tooltip lists skins as kills, not as skinned
--   * it does not show the skinning materials he received
--   * /nt skinroute says "0 of 8 skinned corpses" on a map where he killed
--     and skinned 11 — SkinRoute only counts ring records with
--     rec.skinned == true, so records are not getting skinned=true at all
--
-- Root cause this spec pins through the REAL Probe entry points (UNIT_DIED,
-- UNIT_SPELLCAST_SUCCEEDED, LOOT_OPENED/CLOSED), not a direct R:OnSkinLoot
-- call: a typical farm is "kill a pack, then come back and skin". Skin
-- windows on this client often have no loot-source GUID (the live empty
-- corpse window already printed "(from UNIT_DIED)"), and P.DEATH_FALLBACK
-- _WINDOW is only 10 seconds. Once that window has closed, Classify has
-- neither a source nor a death, returns "unclassified" even when a
-- successful 8613 cast is pending, and never sets rec.skinned or claims
-- the items as skin loot. The player is targeting the corpse they are
-- skinning; that GUID is the authority the recorder is missing.
--
-- This spec also pins the tooltip contract for the same run:
--   * "skinned: N" only (no "kills seen")
--   * per-creature materials as "Name xN", top 4 by count, fallback "item <id>"
--   * SkinRoute:SkinnedPoints count moves with rec.skinned
--
-- RED on 8e2a95a.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

-- ── client stub ──────────────────────────────────────────────────────
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
local function deepCopy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = deepCopy(v) end
  return r
end
CopyTable = deepCopy

local now = 1000
GetTime = function() return now end
GetZone = function() return "The Barrens" end
GetSubzone = function() return "The Crossroads" end
GetRealmName = function() return "Forever" end
GetUnitName = function(u)
  if u == "player" then return "Mightie" end
  return nil
end
GetSpellInfo = function(id) return ({ [2366] = "Herb Gathering" })[id] end
C_Map = {
  GetBestMapForUnit = function() return 1413 end,
  GetPlayerMapPosition = function()
    return { GetXY = function() return 0.5120, 0.3340 end }
  end,
}

local targetName, targetGuid, targetDead = "Plainstrider", nil, true
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
  "Modules/NodeTrail/Route/Cluster.lua",
  "Modules/NodeTrail/Route/Build.lua",
  "Modules/NodeTrail/Route/SkinRoute.lua",
  "Modules/NodeTrail/Data/ItemNames.lua",
  "Modules/NodeTrail/Data/SkinHints.lua",
  "Modules/Skinning/Probe.lua",
  "Modules/Skinning/Record.lua",
  "Modules/Skinning/Core.lua",
}

local function loadPackage(pkg, addonName)
  for _, f in ipairs(files) do
    local p = root .. "/MightiePack/" .. f
    local chunk, err = loadfile(p)
    check(chunk ~= nil, "loadfile " .. f .. ": " .. tostring(err))
    if chunk then
      local ok, e2 = pcall(chunk, addonName or "MightiePack", pkg)
      check(ok, "load " .. f .. ": " .. tostring(e2))
    end
  end
end

local function boot(pkg, addonName)
  for i = #frames, 1, -1 do
    local f = frames[i]
    if f.events and f.events.ADDON_LOADED and f.scripts and f.scripts.OnEvent then
      local ok, e = pcall(f.scripts.OnEvent, f, "ADDON_LOADED", addonName or "MightiePack")
      check(ok, "ADDON_LOADED: " .. tostring(e))
      return
    end
  end
  check(false, "no ADDON_LOADED frame found")
end

MightiePackDB = nil
NodeTrailDB = nil
local pkg = {}
loadPackage(pkg, "MightiePack")
boot(pkg, "MightiePack")

local ns = pkg.Skinning
local P = type(ns) == "table" and ns.Probe or nil
local R = type(ns) == "table" and ns.Recorder or nil
local H = type(pkg.NodeTrail) == "table" and pkg.NodeTrail.SkinHints or nil
local S = type(pkg.NodeTrail) == "table" and pkg.NodeTrail.SkinRoute or nil

check(type(P) == "table", "probe loaded")
check(type(R) == "table", "recorder loaded")
check(type(H) == "table" and type(H.Rows) == "function", "SkinHints loaded")
check(type(S) == "table" and type(S.SkinnedPoints) == "function", "SkinRoute loaded")

local CID = 2956 -- Plainstrider
local MAP = 1413
local LEATHER = "|cffffffff|Hitem:2318::::::::1:::::::|h[Light Leather]|h|r"
local SCRAPS = "|cff1eff00|Hitem:2934::::::::1:::::::|h[Ruined Leather Scraps]|h|r"

local function guidFor(n)
  return ("Creature-0-7072-1-48-%d-%012X"):format(CID, n)
end

local function panelLeft(cid, name)
  local bits = {}
  for _, r in ipairs(H.Rows(cid, name) or {}) do
    if type(r.left) == "string" then bits[#bits + 1] = r.left end
  end
  return table.concat(bits, "\n")
end

local function totalsRow(cid)
  local store = select(1, R:Store())
  local row = type(store.creatures) == "table" and store.creatures[cid] or nil
  return type(row) == "table" and row or {}
end

if type(P) == "table" and type(R) == "table" and type(H) == "table" and type(S) == "table" then
  pkg.NodeTrail.SetSkinningEnabled(true)
  pkg.Skinning.Enable()
  check(P.capturing == true, "capture on")
  local frame = P.frame
  local onEvent = frame and frame.GetScript and frame:GetScript("OnEvent")
  check(type(onEvent) == "function", "probe OnEvent is installed")
  local function fire(event, ...) onEvent(frame, event, ...) end

  local function succeedSkin()
    fire("UNIT_SPELLCAST_START", "player", "CastBar-SKIN", 8613, "CastBar-SKIN")
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "CastBar-SKIN", 8613, "CastBar-SKIN")
    fire("UNIT_SPELLCAST_STOP", "player", "CastBar-SKIN", 8613, "CastBar-SKIN")
  end

  local function openSkinWindow(items, src)
    loot = items or {}
    lootSource, lootSourceName = src, (src and "Plainstrider" or nil)
    fire("LOOT_OPENED")
    loot = {}
    fire("LOOT_CLOSED")
  end

  -- ══════════════════════════════════════════════════════════════════
  -- 1. The friend's farm: kill a pack, wait past the 10s death
  --    fallback, then skin each corpse. The skin window has items but
  --    no loot-source GUID (this client often hands none back).
  --    Each corpse is targeted at cast time.
  -- ══════════════════════════════════════════════════════════════════
  do
    local N = 11
    local guids = {}
    now = 2000
    for i = 1, N do
      guids[i] = guidFor(100 + i)
      now = 2000 + i
      fire("UNIT_DIED", guids[i])
    end
    -- well past DEATH_FALLBACK_WINDOW (10s) after the last kill
    now = 2000 + N + 15
    for i = 1, N do
      targetGuid, targetName, targetDead = guids[i], "Plainstrider", true
      now = now + 1
      succeedSkin()
      now = now + 0.5
      -- no loot-source GUID, but the window holds skin
      openSkinWindow({
        { link = LEATHER, name = "Light Leather", qty = 1, quality = 1 },
      }, nil)
    end

    local skinnedRecs = 0
    for i = 1, N do
      local rec = R:Find(guids[i])
      if type(rec) == "table" and rec.skinned == true then
        skinnedRecs = skinnedRecs + 1
      end
    end
    check(skinnedRecs == N,
      "1: every packed corpse the player targeted and skinned is marked skinned=true (got "
      .. tostring(skinnedRecs) .. " of " .. N .. ")")

    local row = totalsRow(CID)
    check(row.skinned == N,
      "1: the per-creature totals.skinned counts the pack (got "
      .. tostring(row.skinned) .. ")")

    local points = S:SkinnedPoints(MAP)
    check(#points == N,
      "1: SkinRoute counts the pack as skinned corpses on the map (got "
      .. tostring(#points) .. "; friend saw 0 of 8 after 11 skins)")

    local text = panelLeft(CID, "Plainstrider")
    check(text:find("kills seen:", 1, true) == nil,
      "1: the tooltip no longer prints 'kills seen' (got:\n" .. text .. ")")
    check(text:find("skinned: " .. N, 1, true) ~= nil,
      "1: the tooltip prints 'skinned: " .. N .. "' (got:\n" .. text .. ")")
    check(text:find("Light Leather x" .. N, 1, true) ~= nil,
      "1: the tooltip lists the skin materials (got:\n" .. text .. ")")
  end

  -- ══════════════════════════════════════════════════════════════════
  -- 2. Immediate well-behaved path (SUCCEEDED, then a window WITH a
  --    loot-source GUID, no prior corpse window) still marks skinned.
  -- ══════════════════════════════════════════════════════════════════
  do
    local g = guidFor(200)
    now = 4000
    fire("UNIT_DIED", g)
    targetGuid, targetName, targetDead = g, "Plainstrider", true
    now = 4001
    succeedSkin()
    now = 4001.5
    openSkinWindow({
      { link = SCRAPS, name = "Ruined Leather Scraps", qty = 2, quality = 1 },
    }, g)
    local rec = R:Find(g)
    check(type(rec) == "table" and rec.skinned == true,
      "2: the well-behaved unpinned-cast-then-window path still marks skinned")
  end

  -- ══════════════════════════════════════════════════════════════════
  -- 3. An empty corpse window on a DIFFERENT guid must not steal the
  --    next skin (regression for t_a2f44fb2 / PR #18).
  -- ══════════════════════════════════════════════════════════════════
  do
    local emptyG = guidFor(301)
    local realG = guidFor(302)
    now = 5000
    fire("UNIT_DIED", emptyG)
    fire("UNIT_DIED", realG)
    now = 5001
    loot, lootSource, lootSourceName = {}, nil, "Plainstrider"
    fire("LOOT_OPENED")
    fire("LOOT_CLOSED")
    targetGuid, targetName, targetDead = realG, "Plainstrider", true
    now = 5003
    succeedSkin()
    now = 5004
    openSkinWindow({
      { link = LEATHER, name = "Light Leather", qty = 1, quality = 1 },
    }, realG)
    local emptyRec = R:Find(emptyG)
    local realRec = R:Find(realG)
    check(not (type(emptyRec) == "table" and emptyRec.skinned == true),
      "3: the empty corpse window is not marked skinned")
    check(type(realRec) == "table" and realRec.skinned == true,
      "3: the corpse that was actually skinned is marked skinned")
  end

  -- ══════════════════════════════════════════════════════════════════
  -- 4. Skin window opens (with items, no pending cast yet) BEFORE
  --    UNIT_SPELLCAST_SUCCEEDED. The player is targeting the corpse.
  --    rec.skinned must still become true and the items must be skin
  --    materials, not silent corpse loot.
  -- ══════════════════════════════════════════════════════════════════
  do
    local g = guidFor(400)
    now = 6000
    fire("UNIT_DIED", g)
    targetGuid, targetName, targetDead = g, "Plainstrider", true
    now = 6001
    -- window first, then the succeeded event (auto-loot / client order)
    openSkinWindow({
      { link = LEATHER, name = "Light Leather", qty = 3, quality = 1 },
    }, g)
    now = 6001.2
    succeedSkin()
    local rec = R:Find(g)
    check(type(rec) == "table" and rec.skinned == true,
      "4: a skin window that opens before SUCCEEDED still marks skinned=true (got "
      .. tostring(type(rec) == "table" and rec.skinned) .. ")")
  end

  -- ══════════════════════════════════════════════════════════════════
  -- 5. Tooltip materials: cap at the top 4 by count; a nameless item
  --    is printed as "item <id>".
  -- ══════════════════════════════════════════════════════════════════
  do
    -- Drive the recorder directly so the item mix is exact, then read H.Rows.
    local g = guidFor(500)
    now = 7000
    R:OnKill({ guid = g, t = now, map = MAP, x = 0.5, y = 0.5, zone = "The Barrens" })
    R:OnSkinCast({ guid = g, t = now + 1, spellID = 8613 })
    R:OnSkinLoot({
      guid = g, t = now + 1.5, cast = true, spellID = 8613, castAt = now + 1,
      items = {
        { id = 2318, name = "Light Leather", qty = 12 },
        { id = 4234, name = "Heavy Leather", qty = 7 },
        { id = 4304, name = "Thick Leather", qty = 5 },
        { id = 2319, name = "Medium Leather", qty = 3 },
        { id = 8170, name = "Rugged Leather", qty = 1 },
        { id = 42431, qty = 4 }, -- no name: fallback "item 42431"
      },
    })
    local text = panelLeft(CID, "Plainstrider")
    -- the pack in section 1 already added Light Leather; this corpse adds 12
    -- plus the other hides. We only assert presence, cap, and fallback on
    -- THIS row-set: Rugged Leather (count 1) must be the one dropped by the
    -- cap once four larger stacks plus Light Leather (already stacked) are
    -- considered. Safer: count how many " x" material rows appear under
    -- this cid — top 4 only, plus maybe an "and N more".
    local materialLines = 0
    local hasFallback = false
    local hasRugged = false
    local hasKills = false
    for _, r in ipairs(H.Rows(CID, "Plainstrider") or {}) do
      local left = r.left
      if type(left) == "string" then
        if left:find("kills seen:", 1, true) then hasKills = true end
        if left:find("Rugged Leather", 1, true) then hasRugged = true end
        if left:find("item 42431 x", 1, true) and not left:find("unavailable", 1, true) then
          hasFallback = true
        end
        if left:find(" x", 1, true) or left:match("^item %d+") then
          if left ~= "skinned" then materialLines = materialLines + 1 end
        end
      end
    end
    check(hasKills == false, "5: tooltip does not mention kills seen")
    check(materialLines <= 4,
      "5: tooltip caps skin materials at 4 lines (got " .. materialLines .. ")")
    check(hasRugged == false,
      "5: the lowest-count hide (Rugged Leather x1) is dropped by the top-4 cap")
    check(hasFallback == true,
      "5: a nameless item is printed as 'item <id>' (got:\n" .. text .. ")")
  end
end

if failed > 0 then
  io.stderr:write(failed .. " failed\n")
  os.exit(1)
end
print("ok")

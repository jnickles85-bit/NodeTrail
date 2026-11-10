local _, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

-- Where the number of YARDS between the player and a route point comes from.
--
-- This is a measurement, not a dependency decision. On this client there are
-- three possible sources and the addon takes the first one that answers:
--
--   1. HereBeDragons (if RXPGuides or GatherMate2 is loaded — NOT required):
--      HBD:GetZoneSize(mapID) is the zone size in yards. It is what RXPGuides
--      itself uses for its arrow.
--   2. C_Map.GetMapWorldSize(mapID) — the same numbers, straight from the
--      client, and the exact call HBD makes when it exists.
--   3. Nothing. Then there is NO yard scale and no arrow is drawn: a distance
--      guessed from a hard-coded zone table would count down wrong, which is
--      worse than not counting down at all.
--
-- The scale is per-axis (yards east per map-fraction east, yards north per
-- map-fraction north), so it converts a map-fraction delta into a real
-- distance without inventing anything.

ns.Nav = ns.Nav or {}
local N = ns.Nav
N.Source = N.Source or {}
local S = N.Source

local function finite(v)
  return type(v) == "number" and v == v and v > -1e300 and v < 1e300
end

local function present(fn)
  return type(fn) == "function" and "present" or "absent"
end

--- The HereBeDragons library as an EXISTING lib, if anything loaded it.
--- Deliberately not a dependency: a friend without RXPGuides gets the native
--- C_Map path instead, and a client with neither gets a visible message.
function S.HBD()
  if type(LibStub) == "table" and type(LibStub.GetLibrary) == "function" then
    local ok, lib = pcall(LibStub.GetLibrary, LibStub, "HereBeDragons-2.0", true)
    if ok and type(lib) == "table" then
      return lib, "LibStub"
    end
  end
  -- GatherMate2 re-exports the same instance; the recorder already prefers it.
  if type(ns.GetGatherMate2) == "function" then
    local ok, gm = pcall(ns.GetGatherMate2)
    if ok and type(gm) == "table" and type(gm.HBD) == "table" then
      return gm.HBD, "GatherMate2"
    end
  end
  return nil
end

local zoneCache = {}

--- Zone size in yards for a uiMapID.
--- @return width, height, how — how is the source that answered, or a reason
function S.ZoneSize(mapID)
  if not finite(mapID) then
    return nil, nil, "no map id"
  end
  local cached = zoneCache[mapID]
  if cached then
    if cached.width then
      return cached.width, cached.height, cached.how
    end
    return nil, nil, cached.why
  end

  local HBD = S.HBD()
  if HBD and type(HBD.GetZoneSize) == "function" then
    local ok, w, h = pcall(HBD.GetZoneSize, HBD, mapID)
    if ok and finite(w) and finite(h) and w > 0 and h > 0 then
      zoneCache[mapID] = { width = w, height = h, how = "HereBeDragons:GetZoneSize" }
      return w, h, "HereBeDragons:GetZoneSize"
    end
  end

  if type(C_Map) == "table" and type(C_Map.GetMapWorldSize) == "function" then
    local ok, w, h = pcall(C_Map.GetMapWorldSize, mapID)
    if ok and finite(w) and finite(h) and w > 0 and h > 0 then
      zoneCache[mapID] = { width = w, height = h, how = "C_Map.GetMapWorldSize" }
      return w, h, "C_Map.GetMapWorldSize"
    end
  end

  local why
  if HBD then
    why = "HereBeDragons answered no zone size for this map"
  elseif type(C_Map) == "table" then
    why = "no yard scale: neither HereBeDragons nor C_Map.GetMapWorldSize answered"
  else
    why = "no yard scale: this client has no C_Map and no HereBeDragons"
  end
  zoneCache[mapID] = { why = why }
  return nil, nil, why
end

function S.ForgetCache()
  zoneCache = {}
end

--- The player's position on a map, as 0..1 fractions.
--- @return fx, fy, how
function S.PlayerFrac(mapID)
  if type(C_Map) == "table" and type(C_Map.GetPlayerMapPosition) == "function" then
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if ok and type(pos) == "table" then
      if type(pos.GetXY) == "function" then
        local okXY, x, y = pcall(pos.GetXY, pos)
        if okXY and finite(x) and finite(y) then
          return x, y, "C_Map.GetPlayerMapPosition"
        end
      elseif finite(pos.x) and finite(pos.y) then
        return pos.x, pos.y, "C_Map.GetPlayerMapPosition"
      end
    end
  end
  local HBD = S.HBD()
  if HBD and type(HBD.GetPlayerZonePosition) == "function" then
    local ok, x, y, zone = pcall(HBD.GetPlayerZonePosition, HBD, true)
    if ok and finite(x) and finite(y) and (not zone or zone == mapID) then
      return x, y, "HereBeDragons:GetPlayerZonePosition"
    end
  end
  return nil, nil, "the client reports no player position on this map"
end

--- The minimap's radius in yards — the only unit that makes a screen offset
--- meaningful. Uses the same value the minimap line projects with.
function S.ViewRadiusYards()
  if type(ns.MinimapPath) == "table" and type(ns.MinimapPath.ViewRadiusYards) == "function" then
    local ok, radius = pcall(ns.MinimapPath.ViewRadiusYards, ns.MinimapPath)
    if ok and finite(radius) and radius > 1 then
      return radius, "MinimapPath"
    end
  end
  if type(C_Minimap) == "table" and type(C_Minimap.GetViewRadius) == "function" then
    local ok, radius = pcall(C_Minimap.GetViewRadius)
    if ok and finite(radius) and radius > 1 then
      return radius, "C_Minimap.GetViewRadius"
    end
  end
  return nil, "the client reports no minimap view radius"
end

--- Is the minimap turned with the player? Returns the CVar as a number too,
--- because "0" vs nil is the difference between a north-up map and one that
--- cannot be read at all.
function S.RotateMinimap()
  if type(GetCVar) ~= "function" then
    return false, "absent"
  end
  local ok, value = pcall(GetCVar, "rotateMinimap")
  if not ok then
    return false, "unreadable"
  end
  return value == "1" or value == 1, tostring(value)
end

function S.Facing()
  if type(GetPlayerFacing) ~= "function" then
    return nil, "absent"
  end
  local ok, value = pcall(GetPlayerFacing)
  if not ok or not finite(value) then
    return nil, "unreadable"
  end
  return value, nil
end

-- ── /nt navdiag: the Step-1 measurement, as plain numbers ───────────────────
-- One line per fact, every line built inside pcall, so a client missing an API
-- prints "absent" instead of erroring. This is the block that decides whether
-- an arrow is even possible on this client: if it says there is no yard scale,
-- the arrow is not drawn and this is why.

local function fmt(v, decimals)
  if not finite(v) then
    return "absent"
  end
  if decimals then
    return string.format("%." .. decimals .. "f", v)
  end
  if v == math.floor(v) then
    return string.format("%d", v)
  end
  return string.format("%.3f", v)
end
S.Fmt = fmt

--- Route points as world-yard positions is deliberately NOT how this works:
--- the arrow converts map fractions with the zone size, so the only thing the
--- diag needs the route for is the cross-check against HereBeDragons.
function S.Describe(mapID, route)
  local lines = {}
  local function add(build)
    local ok, text = pcall(build)
    if not ok then
      text = "error: " .. tostring(text)
    end
    lines[#lines + 1] = text
  end

  add(function()
    if type(C_Map) ~= "table" then
      return "C_Map: absent"
    end
    return string.format(
      "C_Map: present; GetBestMapForUnit=%s GetMapInfo=%s GetWorldPosFromMapPos=%s GetMapWorldSize=%s GetPlayerMapPosition=%s",
      present(C_Map.GetBestMapForUnit), present(C_Map.GetMapInfo),
      present(C_Map.GetWorldPosFromMapPos), present(C_Map.GetMapWorldSize),
      present(C_Map.GetPlayerMapPosition))
  end)

  add(function()
    local HBD, via = S.HBD()
    if not HBD then
      local libStub = type(LibStub) == "table" and "present" or "absent"
      return "LibStub: " .. libStub .. "; HereBeDragons-2.0: not reachable"
    end
    local major = rawget(HBD, "MAJOR")
    local minor = rawget(HBD, "MINOR")
    return string.format(
      "LibStub: present; HereBeDragons-2.0: reachable via %s (version %s, API %s)",
      tostring(via), tostring(major or "?"), tostring(minor or "?"))
  end)

  add(function()
    local HBD = S.HBD()
    if not HBD or type(HBD.GetPlayerWorldPosition) ~= "function" then
      return "HBD:GetPlayerWorldPosition(): absent"
    end
    local ok, x, y, inst = pcall(HBD.GetPlayerWorldPosition, HBD)
    if not ok or not finite(x) or not finite(y) then
      return "HBD:GetPlayerWorldPosition(): returns nothing on this client"
    end
    return string.format("HBD:GetPlayerWorldPosition(): x=%s y=%s instance=%s",
      fmt(x, 2), fmt(y, 2), tostring(inst))
  end)

  add(function()
    local w, h, how = S.ZoneSize(mapID)
    if not w then
      return string.format("zone size for map %s: %s", tostring(mapID), tostring(how))
    end
    return string.format("zone size for map %s: %s x %s yd (via %s)",
      tostring(mapID), fmt(w, 1), fmt(h, 1), tostring(how))
  end)

  add(function()
    if type(C_Map) ~= "table" or type(C_Map.GetMapWorldSize) ~= "function" then
      return "C_Map.GetMapWorldSize(" .. tostring(mapID) .. "): absent"
    end
    local ok, w, h = pcall(C_Map.GetMapWorldSize, mapID)
    if not ok or not finite(w) or not finite(h) then
      return "C_Map.GetMapWorldSize(" .. tostring(mapID) .. "): returns nothing"
    end
    return string.format("C_Map.GetMapWorldSize(%s): %s x %s yd",
      tostring(mapID), fmt(w, 1), fmt(h, 1))
  end)

  add(function()
    local fx, fy, how = S.PlayerFrac(mapID)
    if not fx then
      return "player fraction on map " .. tostring(mapID) .. ": " .. tostring(how)
    end
    return string.format("player fraction on map %s: (%s, %s) via %s",
      tostring(mapID), fmt(fx, 4), fmt(fy, 4), tostring(how))
  end)

  add(function()
    if type(UnitPosition) ~= "function" then
      return "UnitPosition: absent"
    end
    local ok, x, y, z, inst = pcall(UnitPosition, "player")
    if not ok or not finite(x) then
      return "UnitPosition: present but returns nothing for the player (normal in instances)"
    end
    return string.format("UnitPosition(\"player\"): x=%s y=%s z=%s instance=%s",
      fmt(x, 2), fmt(y, 2), fmt(z, 2), tostring(inst))
  end)

  add(function()
    local facing, whyFacing = S.Facing()
    local rotate, cvar = S.RotateMinimap()
    return string.format("GetPlayerFacing(): %s; rotateMinimap=%s -> minimap is %s",
      facing and (fmt(facing, 4) .. " rad") or ("absent (" .. tostring(whyFacing) .. ")"),
      tostring(cvar), rotate and "turned with the player" or "north up")
  end)

  add(function()
    local radius, why = S.ViewRadiusYards()
    if not radius then
      return "minimap view radius: " .. tostring(why)
    end
    local zoom = "absent"
    if type(Minimap) == "table" and type(Minimap.GetZoom) == "function" then
      local ok, z = pcall(Minimap.GetZoom, Minimap)
      if ok then
        zoom = fmt(z)
      end
    end
    return string.format("minimap view radius: %s yd (via %s), zoom=%s",
      fmt(radius, 2), tostring(why), zoom)
  end)

  -- ── HereBeDragons' own answer, for the two route endpoints ────────────────
  -- The card asks for these numbers by name: they are the yard distance the
  -- working reference on this machine uses, so the arrow's distance can be
  -- checked against the one RXPGuides would have printed.
  add(function()
    local HBD = S.HBD()
    if not HBD then
      return "HBD:GetWorldVector to the route ends: no HereBeDragons to ask"
    end
    if type(route) ~= "table" or type(route.path) ~= "table" or #route.path < 1 then
      return "HBD:GetWorldVector to the route ends: no active route"
    end
    if type(HBD.GetPlayerWorldPosition) ~= "function" or type(HBD.GetWorldCoordinatesFromZone) ~= "function"
      or type(HBD.GetWorldVector) ~= "function" then
      return "HBD:GetWorldVector to the route ends: this HereBeDragons lacks the calls"
    end
    local okP, px, py, pinst = pcall(HBD.GetPlayerWorldPosition, HBD)
    if not okP or not finite(px) or not finite(py) then
      return "HBD:GetWorldVector to the route ends: no player world position"
    end
    local out = {}
    local function one(label, index)
      local p = route.path[index]
      if type(p) ~= "table" or not finite(p.x) or not finite(p.y) then
        out[#out + 1] = label .. "=no point"
        return
      end
      local okW, wx, wy, winst = pcall(HBD.GetWorldCoordinatesFromZone, HBD, p.x, p.y, route.mapID)
      if not okW or not finite(wx) or not finite(wy) then
        out[#out + 1] = label .. "=no world coordinates"
        return
      end
      local okV, angle, dist = pcall(HBD.GetWorldVector, HBD, pinst, px, py, wx, wy)
      if not okV or not finite(angle) or not finite(dist) then
        out[#out + 1] = string.format("%s=no vector (instance %s vs %s)",
          label, tostring(pinst), tostring(winst))
        return
      end
      out[#out + 1] = string.format("%s angle=%s rad dist=%s yd",
        label, fmt(angle, 4), fmt(dist, 1))
    end
    one("first", 1)
    one("last", #route.path)
    return "HBD:GetWorldVector from the player to the route ends: " .. table.concat(out, "; ")
  end)

  return lines
end

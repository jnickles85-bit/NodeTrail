local _, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

-- Minimap white polyline for the part of the active route near the player.
-- Yard offsets match HereBeDragons-Pins (GatherMate2.HBD) when that library
-- is loaded, so the line sits on the same projection as GatherMate2 nodes.
-- Updates are throttled; movement, zoom, and zone events redraw immediately.

ns.MinimapPath = ns.MinimapPath or {}
local M = ns.MinimapPath

local UPDATE_INTERVAL = 0.08
-- Used only when the client cannot report a yard radius. About one outdoor
-- minimap on a typical zone, so nearby nodes still show up.
local FALLBACK_VIEW_FRACTION = 0.075
local ROUND_INSET = 0.96
local SQUARE_INSET = 0.99

-- Diameters in yards from HereBeDragons-Pins. Radius is half of these.
-- C_Minimap.GetViewRadius() is preferred and already returns the radius.
local MINIMAP_DIAMETER = {
  indoor = {
    [0] = 300,
    [1] = 240,
    [2] = 180,
    [3] = 120,
    [4] = 80,
    [5] = 50,
  },
  outdoor = {
    [0] = 466 + 2 / 3,
    [1] = 400,
    [2] = 333 + 1 / 3,
    [3] = 266 + 2 / 6,
    [4] = 200,
    [5] = 133 + 1 / 3,
  },
}

local IMMEDIATE = {
  PLAYER_STARTED_MOVING = true,
  PLAYER_ENTERING_WORLD = true,
  ZONE_CHANGED = true,
  ZONE_CHANGED_INDOORS = true,
  ZONE_CHANGED_NEW_AREA = true,
  MINIMAP_UPDATE_ZOOM = true,
  PLAYER_LOGIN = true,
}

--- HereBeDragons, from whichever addon on this client provides it — and the
--- NAME of that source, because "no HBD" and "looked in one place only" are
--- different answers and the diag has to tell them apart.
---
--- GatherMate2 embeds the library and exposes it as `GatherMate2.HBD`; RXPGuides
--- ships the same library as a LibStub library (this client has it at
--- RXPGuides/libs/HereBeDragons). The projection only needs the table, so any
--- copy is usable — which is what makes the 0.075 fraction fallback avoidable
--- on a client where RXPGuides is loaded.
local function getHBDSourced()
  if type(ns.GetGatherMate2) == "function" then
    local ok, gm = pcall(ns.GetGatherMate2)
    if ok and type(gm) == "table" and type(gm.HBD) == "table" then
      return gm.HBD, "GatherMate2.HBD"
    end
  end
  -- LibStub is a TABLE with a __call metamethod on the live client, so it is
  -- callable but not `type(...) == "function"` — checking only for a function
  -- is how a library that is right there reads as missing.
  if type(LibStub) == "function" or type(LibStub) == "table" then
    local names = { "HereBeDragons-2.0", "HereBeDragons-1.0" }
    for i = 1, #names do
      local ok, lib = pcall(LibStub, names[i], true)
      if ok and type(lib) == "table" then
        return lib, "LibStub:" .. names[i]
      end
    end
  end
  return nil, nil
end

local function getHBD()
  -- Parenthesised so the two-value helper truncates to the library alone.
  return (getHBDSourced())
end

--- Which library answered, and the version it reports: printed by the diag so
--- a report of "the scale could not be measured" names what was missing.
local function hbdSourceText()
  local lib, source = getHBDSourced()
  if type(lib) ~= "table" then
    return "absent (no GatherMate2.HBD and no LibStub HereBeDragons)"
  end
  local version = "?"
  if type(lib.GetVersion) == "function" then
    local ok, v = pcall(lib.GetVersion, lib)
    if ok and v ~= nil then
      version = tostring(v)
    end
  end
  return string.format("%s version=%s", tostring(source), version)
end

local function viewRadiusYards()
  if C_Minimap and type(C_Minimap.GetViewRadius) == "function" then
    local ok, radius = pcall(C_Minimap.GetViewRadius)
    if ok and type(radius) == "number" and radius > 1 then
      return radius
    end
  end
  if not Minimap or type(Minimap.GetZoom) ~= "function" then
    return nil
  end
  local okZoom, zoom = pcall(Minimap.GetZoom, Minimap)
  if not okZoom or type(zoom) ~= "number" then
    return nil
  end
  local where = "outdoor"
  if type(GetCVar) == "function" then
    local okC, value = pcall(GetCVar, "minimapZoom")
    local n = okC and tonumber(value)
    if n and n ~= zoom then
      where = "indoor"
    end
  end
  local row = MINIMAP_DIAMETER[where] or MINIMAP_DIAMETER.outdoor
  local diameter = row[zoom] or row[0]
  if type(diameter) ~= "number" or diameter <= 0 then
    return nil
  end
  return diameter / 2
end

-- Returns sin, cos, ok. North-up minimap uses the identity (0, 1).
local function minimapRotation()
  local rotate = false
  if type(GetCVar) == "function" then
    local ok, value = pcall(GetCVar, "rotateMinimap")
    rotate = ok and value == "1"
  end
  if not rotate then
    return 0, 1, true
  end
  if type(GetPlayerFacing) ~= "function" then
    return nil, nil, false
  end
  local okFacing, facing = pcall(GetPlayerFacing)
  if not okFacing or type(facing) ~= "number" then
    return nil, nil, false
  end
  local okSin, s = pcall(math.sin, facing)
  local okCos, c = pcall(math.cos, facing)
  if not okSin or not okCos or type(s) ~= "number" or type(c) ~= "number" then
    return nil, nil, false
  end
  return s, c, true
end

local function minimapHalf()
  if not Minimap or type(Minimap.GetWidth) ~= "function" then
    return nil
  end
  local okW, w = pcall(Minimap.GetWidth, Minimap)
  local okH, h = pcall(Minimap.GetHeight, Minimap)
  if not okW or not okH or type(w) ~= "number" or type(h) ~= "number" then
    return nil
  end
  if w < 8 or h < 8 then
    return nil
  end
  return w * 0.5, h * 0.5
end

--- Zoom-aware fallback view radius, in MAP FRACTIONS.
--- The fallback only runs when the client cannot report a yard radius or a
--- zone size, and the minimap zoom still has to matter: the yard view radius
--- shrinks with zoom, so a fixed fraction draws the same route the same size at
--- every zoom step (which is how a route that is on screen at zoom 0 silently
--- disappears at zoom 5). The fraction therefore scales with the same diameter
--- table the yard radius uses.
local function fallbackViewFraction()
  local zoom
  if Minimap and type(Minimap.GetZoom) == "function" then
    local ok, z = pcall(Minimap.GetZoom, Minimap)
    if ok and type(z) == "number" then
      zoom = z
    end
  end
  if not zoom then
    return FALLBACK_VIEW_FRACTION
  end
  local where = "outdoor"
  if type(GetCVar) == "function" then
    local okC, value = pcall(GetCVar, "minimapZoom")
    local n = okC and tonumber(value)
    if n and n ~= zoom then
      where = "indoor"
    end
  end
  local row = MINIMAP_DIAMETER[where] or MINIMAP_DIAMETER.outdoor
  local max = row[0]
  local at = row[zoom] or max
  if type(max) ~= "number" or max <= 0 or type(at) ~= "number" then
    return FALLBACK_VIEW_FRACTION
  end
  return FALLBACK_VIEW_FRACTION * (at / max)
end

local function playerMapPosition(mapID, HBD)
  if C_Map and type(C_Map.GetPlayerMapPosition) == "function" and mapID then
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if ok and type(pos) == "table" then
      if type(pos.GetXY) == "function" then
        local okXY, x, y = pcall(pos.GetXY, pos)
        if okXY and type(x) == "number" and type(y) == "number" and x == x and y == y then
          return x, y
        end
      elseif type(pos.x) == "number" and type(pos.y) == "number" then
        return pos.x, pos.y
      end
    end
  end
  if HBD and type(HBD.GetPlayerZonePosition) == "function" then
    local ok, x, y, zone = pcall(HBD.GetPlayerZonePosition, HBD, true)
    if ok and type(x) == "number" and type(y) == "number" then
      if not zone or zone == mapID then
        return x, y
      end
      if mapID and type(HBD.TranslateZoneCoordinates) == "function" then
        local okT, tx, ty = pcall(HBD.TranslateZoneCoordinates, HBD, x, y, zone, mapID, true)
        if okT and type(tx) == "number" and type(ty) == "number" then
          return tx, ty
        end
      end
    end
  end
  if type(GetPlayerMapPosition) == "function" then
    local current
    if type(ns.GetPlayerMapID) == "function" then
      local okID, id = pcall(ns.GetPlayerMapID)
      if okID then
        current = id
      end
    end
    if not current or current == mapID then
      local ok, x, y = pcall(GetPlayerMapPosition, "player")
      if ok and type(x) == "number" and type(y) == "number" and not (x == 0 and y == 0) then
        return x, y
      end
    end
  end
  return nil
end

-- ── t_86583cf2: what was ACTUALLY drawn, captured at draw time ─────────────
-- The card's complaint about the earlier check was that it was circular: the
-- diag recomputed the player's map fraction at print time and compared it with
-- the previous recomputation. That proves the maths is live; it says nothing
-- about the objects on screen. So the values the draw used are STAMPED onto the
-- drawer when the draw happens (`lastApplied`), and the diag prints them back
-- verbatim, plus the anchors the client reports for the dots that draw placed.
local function nowTime()
  if type(GetTime) == "function" then
    local ok, t = pcall(GetTime)
    if ok and type(t) == "number" then
      return t
    end
  end
  return nil
end

--- The 5-value point contract of a region, as the client reports it.
--- @return array of { point, relativeTo, relativePoint, x, y }
local function readPoints(obj)
  local out = {}
  if type(obj) ~= "table" or type(obj.GetPoint) ~= "function" then
    return out
  end
  local count = 4
  if type(obj.GetNumPoints) == "function" then
    local ok, n = pcall(obj.GetNumPoints, obj)
    if ok and type(n) == "number" and n >= 1 then
      count = math.min(n, 4)
    end
  end
  for i = 1, count do
    local ok, point, rel, relPoint, x, y = pcall(obj.GetPoint, obj, i)
    if ok and type(point) == "string" then
      out[i] = { point = point, relativeTo = rel, relativePoint = relPoint, x = x, y = y }
    end
  end
  return out
end

--- The CENTRE a two-corner-anchored dot was given, from its real anchors.
--- "yup" dots anchor BOTTOMLEFT/TOPRIGHT to the host's CENTER (+y up), so the
--- centre is the mean of the two offsets. "ydown" dots anchor to the host's
--- TOPLEFT (+y down), so the mean y is negated. Nil when the client kept no
--- numeric geometry — "absent" must not read as (0,0), which is the centre of
--- the minimap and would look like a perfectly anchored dot.
local function anchorCentre(points)
  local a, b = points and points[1], points and points[2]
  if type(a) ~= "table" or type(b) ~= "table" then
    return nil
  end
  if type(a.x) ~= "number" or type(a.y) ~= "number"
    or type(b.x) ~= "number" or type(b.y) ~= "number" then
    return nil
  end
  local cx = (a.x + b.x) * 0.5
  local cy = (a.y + b.y) * 0.5
  if a.relativePoint ~= nil and a.relativePoint ~= "CENTER" then
    cy = -cy
  end
  return cx, cy
end

--- Nearest segment of a projected polyline to a pixel, with the parameter.
--- The dots are interpolated ALONG these segments, so this recovers the route
--- index a dot belongs to from the dot's own anchor — no bookkeeping inside the
--- drawing primitive (which this card must not change).
local function nearestSegmentPx(points, cx, cy)
  local bestI, bestT, bestD
  for i = 1, #points - 1 do
    local a, b = points[i], points[i + 1]
    if a and b and type(a.x) == "number" and type(b.x) == "number" then
      local dx, dy = b.x - a.x, b.y - a.y
      local len2 = dx * dx + dy * dy
      local t = 0
      if len2 > 1e-9 then
        t = ((cx - a.x) * dx + (cy - a.y) * dy) / len2
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
      end
      local qx, qy = a.x + dx * t, a.y + dy * t
      local d = math.sqrt((cx - qx) * (cx - qx) + (cy - qy) * (cy - qy))
      if bestD == nil or d < bestD then
        bestI, bestT, bestD = i, t, d
      end
    end
  end
  return bestI, bestT, bestD
end

--- Distance from a point to one specific segment, clamped to the segment.
--- The walk test is about the PLAYER's distance to the route, so the number has
--- to come from the player (the minimap centre), not from the dot.
local function segmentDistance(px, py, ax, ay, bx, by)
  local dx, dy = bx - ax, by - ay
  local len2 = dx * dx + dy * dy
  local t = 0
  if len2 > 1e-9 then
    t = ((px - ax) * dx + (py - ay) * dy) / len2
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
  end
  local qx, qy = ax + dx * t, ay + dy * t
  return math.sqrt((px - qx) * (px - qx) + (py - qy) * (py - qy)), qx, qy, t
end

--- Pixels from the minimap centre -> the projection's own distance unit.
--- frac mode: map fractions. zone/world mode: yards (with map fractions too,
--- when the zone size is known, so the number is comparable across surfaces).
local function pxToUnits(sample, cx, cy)
  if not sample or not sample.halfW or sample.halfW <= 0 or not sample.radius then
    return nil
  end
  local ux = cx * sample.radius / sample.halfW
  local uy = -cy * sample.radius / (sample.halfH or sample.halfW)
  local dist = math.sqrt(ux * ux + uy * uy)
  local frac
  if sample.mode == "frac" then
    frac = dist
  elseif sample.zoneW and sample.zoneW > 0 and sample.zoneH and sample.zoneH > 0 then
    local fx, fy = ux / sample.zoneW, uy / sample.zoneH
    frac = math.sqrt(fx * fx + fy * fy)
  end
  return dist, frac, ux, uy
end

local function fmtNum(value, decimals)
  if type(value) ~= "number" or value ~= value then
    return "absent"
  end
  if value == 0 then
    value = 0 -- never print "-0"
  end
  if decimals then
    return string.format("%." .. decimals .. "f", value)
  end
  if value == math.floor(value) then
    return string.format("%d", value)
  end
  return string.format("%.2f", value)
end

local function pointDelta(sample, point)
  if sample.mode == "world" then
    if type(point.wx) ~= "number" or type(point.wy) ~= "number" then
      return nil
    end
    if sample.pinst and point.inst and point.inst ~= sample.pinst then
      return nil
    end
    -- Same sign as HereBeDragons-Pins: positive xDist is east of the player,
    -- positive yDist is south. Screen Y flips that so north is up.
    --
    -- Player MINUS point, not the other way round: HBD world coordinates run
    -- backwards from UI map fractions (`x = left - width * x` in
    -- HereBeDragons-2.0.lua, GetWorldCoordinatesFromZone), so world x grows
    -- WEST and world y grows NORTH. Subtracting the point from the player is
    -- what turns that back into "east is +x, south is +y", which is the same
    -- frame `pointDelta`'s fraction branch below uses — the two branches must
    -- agree or the minimap mirrors the route the moment HBD loads.
    return sample.px - point.wx, sample.py - point.wy
  end
  if type(point.x) ~= "number" or type(point.y) ~= "number" then
    return nil
  end
  local dx = point.x - sample.mx
  local dy = point.y - sample.my
  if sample.mode == "zone" then
    return dx * sample.zoneW, dy * sample.zoneH
  end
  return dx, dy
end

local function toPixel(xDist, yDist, sample)
  local dx = xDist * sample.cosF - yDist * sample.sinF
  local dy = xDist * sample.sinF + yDist * sample.cosF
  local px = (dx / sample.radius) * sample.halfW
  local py = -(dy / sample.radius) * sample.halfH
  return px, py
end

local function clipToMinimap(x1, y1, x2, y2, halfW, halfH)
  local shape = "ROUND"
  if type(GetMinimapShape) == "function" then
    local ok, value = pcall(GetMinimapShape)
    if ok and type(value) == "string" then
      shape = value
    end
  end
  if shape == "ROUND" then
    return ns.PathGeom.ClipCircle(x1, y1, x2, y2, math.min(halfW, halfH) * ROUND_INSET)
  end
  local inset = SQUARE_INSET
  return ns.PathGeom.ClipRect(
    x1, y1, x2, y2,
    -halfW * inset, -halfH * inset,
    halfW * inset, halfH * inset
  )
end

--- The minimap's radius in YARDS. Exported because the waypoint arrow has to
--- use the same scale as the line it sits on top of — two projections of the
--- same minimap that disagree by a few percent would put the arrow on the
--- wrong bearing (t_d17939c1).
function M:ViewRadiusYards()
  return viewRadiusYards()
end

function M:ReleaseVisuals()
  if self.drawer then
    ns.LineDraw.Clear(self.drawer)
  end
  if self.host then
    pcall(self.host.Hide, self.host)
  end
end

function M:StopUpdates()
  if self._driver then
    self._driver:SetScript("OnUpdate", nil)
  end
  self._acc = 0
end

function M:Clear()
  self.path = nil
  self.points = nil
  self.mapID = nil
  self.useWorld = nil
  self.zoneW, self.zoneH = nil, nil
  self._proj = nil
  self._dotMetrics = nil
  self._why = nil
  self._sampleWhy = nil
  -- t_86583cf2: the stamp and the drawn-dot audit describe a drawing that no
  -- longer exists once the route is cleared; keeping them would let the diag
  -- report anchors of a route that is gone.
  self._stamp = nil
  self._drawn = nil
  self._drawnStamp = nil
  self._lastSample = nil
  -- The circle is its own layer: clearing the herb line must not stop its
  -- ticker, so updates stop only when there is no circle either.
  if not self.skinPoints then
    self:StopUpdates()
  end
  self:ReleaseVisuals()
end

function M:EnsureHost()
  if self.host then
    return self.host
  end
  if not Minimap or type(CreateFrame) ~= "function" then
    return nil
  end
  local ok, host = pcall(CreateFrame, "Frame", nil, Minimap)
  if not ok or not host then
    return nil
  end
  ns.LineDraw.BindOverlay(host, Minimap)
  self.host = host
  self.drawer = ns.LineDraw.Create()
  return host
end

--- The skinning circle's own host: a second frame on the minimap, so clearing
--- the herb line can never clear the circle (ReleaseVisuals hides self.host).
function M:EnsureSkinHost()
  if self.skinHost then
    return self.skinHost
  end
  if not Minimap or type(CreateFrame) ~= "function" then
    return nil
  end
  local ok, host = pcall(CreateFrame, "Frame", nil, Minimap)
  if not ok or not host then
    return nil
  end
  ns.LineDraw.BindOverlay(host, Minimap)
  self.skinHost = host
  self.skinDrawer = ns.LineDraw.Create()
  return host
end

--- Drop the circle's visuals only; the herb route's drawer and host stay.
function M:ReleaseSkinVisuals(why)
  if self.skinDrawer then
    if why then
      ns.LineDraw.MarkIdle(self.skinDrawer, why)
    else
      ns.LineDraw.Clear(self.skinDrawer)
    end
  end
  if self.skinHost then
    pcall(self.skinHost.Hide, self.skinHost)
  end
end

--- Index one route's points for the minimap projection. Pure: returns the
--- bookkeeping instead of writing it, so the herb route and the skinning circle
--- can each be indexed without sharing state.
local function indexRoute(route)
  local HBD = getHBD()
  local pts = {}
  local anyWorld, worldPoints = false, 0
  for i = 1, #route.path do
    local p = route.path[i]
    local entry = {}
    if ns.PathGeom.IsMapPoint(p) then
      entry.x, entry.y = p.x, p.y
      if HBD and type(HBD.GetWorldCoordinatesFromZone) == "function" and route.mapID then
        local ok, wx, wy, inst = pcall(HBD.GetWorldCoordinatesFromZone, HBD, p.x, p.y, route.mapID)
        if ok and type(wx) == "number" and type(wy) == "number" then
          entry.wx, entry.wy, entry.inst = wx, wy, inst
          anyWorld = true
          worldPoints = worldPoints + 1
        end
      end
    end
    pts[i] = entry
  end
  local out = {
    points = pts,
    worldPoints = worldPoints,
    -- ALL points, or the projection is not a world projection. `anyWorld` used
    -- to be enough, and a point without world coordinates then produced no
    -- delta and was silently dropped from the minimap while the diag claimed a
    -- world projection for the whole route (review round 3: "useWorld=true but
    -- the points carry the wrong space"). A partial world set now falls back to
    -- the frac/zone projection, where every point has a fraction, and says why.
    useWorld = anyWorld and worldPoints == #route.path,
    worldWhy = nil,
    zoneW = nil,
    zoneH = nil,
  }
  if anyWorld and worldPoints < #route.path then
    out.worldWhy = (("HereBeDragons converted %d of %d point(s); %d have no world position, so the world projection would drop them")
      :format(worldPoints, #route.path, #route.path - worldPoints))
  elseif not anyWorld then
    out.worldWhy = "no HereBeDragons world position for any route point"
  end
  if HBD and type(HBD.GetZoneSize) == "function" and route.mapID then
    local ok, w, h = pcall(HBD.GetZoneSize, HBD, route.mapID)
    if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
      out.zoneW, out.zoneH = w, h
      out.zoneWhy = "HereBeDragons:GetZoneSize"
    end
  end
  -- The client's own zone size (the same call Nav/Source.lua uses) is the next
  -- best source, and it is what makes the yard radius convertible to a fraction
  -- without guessing. HereBeDragons is optional; without this a player who has
  -- not installed it fell all the way to FALLBACK_VIEW_FRACTION and drew the
  -- route ~3x too coarse.
  if (not out.zoneW or not out.zoneH) and route.mapID
    and type(C_Map) == "table" and type(C_Map.GetMapWorldSize) == "function" then
    local ok, w, h = pcall(C_Map.GetMapWorldSize, route.mapID)
    if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
      out.zoneW, out.zoneH = w, h
      out.zoneWhy = "C_Map.GetMapWorldSize"
    end
  end
  return out
end

function M:_indexPoints(route)
  local r = indexRoute(route)
  self.points = r.points
  self.useWorld = r.useWorld
  self._worldPoints = r.worldPoints
  self._worldWhy = r.worldWhy
  self.zoneW, self.zoneH = r.zoneW, r.zoneH
end

--- The same indexing for the skinning circle, kept in its own fields so neither
--- layer can overwrite the other's projection.
function M:_indexSkinPoints(route)
  local r = indexRoute(route)
  self.skinPoints = r.points
  self.skinUseWorld = r.useWorld
  self._skinWorldPoints = r.worldPoints
  self._skinWorldWhy = r.worldWhy
  self.skinZoneW, self.skinZoneH = r.zoneW, r.zoneH
end

--- One projection sample for one route. The herb route calls it through
--- `_sample` (which records the reason on self._sampleWhy); the skinning circle
--- passes its own map/space so the two can be on different maps at once.
local function sampleFor(self, mapID, useWorld, zoneW, zoneH)
  local halfW, halfH = minimapHalf()
  if not halfW then
    return nil, "the minimap has no measurable size"
  end
  local sinF, cosF, faceOK = minimapRotation()
  if not faceOK then
    return nil, "no player facing (rotateMinimap is on and GetPlayerFacing is absent)"
  end
  local radiusYards = viewRadiusYards()
  local HBD = getHBD()

  if useWorld and HBD and type(HBD.GetPlayerWorldPosition) == "function" and radiusYards then
    local ok, x, y, inst = pcall(HBD.GetPlayerWorldPosition, HBD)
    if ok and type(x) == "number" and type(y) == "number" then
      -- The fraction is not used by the world projection — but the stamp has to
      -- carry it, because the card's four-stop table compares "player fraction"
      -- with "the fraction the draw was built from", and in world mode that
      -- stamp read `frac=(absent,absent)` (review round 3).
      local mx, my = playerMapPosition(mapID, HBD)
      return {
        mode = "world",
        px = x, py = y, pinst = inst,
        mx = mx, my = my,
        radius = radiusYards,
        radiusUnit = "yards",
        sinF = sinF, cosF = cosF,
        halfW = halfW, halfH = halfH,
      }, nil
    end
  end

  local mx, my = playerMapPosition(mapID, HBD)
  if not mx then
    return nil, ("no player position on map %s"):format(tostring(mapID))
  end
  if zoneW and zoneH and radiusYards then
    return {
      mode = "zone",
      mx = mx, my = my,
      zoneW = zoneW, zoneH = zoneH,
      radius = radiusYards,
      radiusUnit = "yards",
      sinF = sinF, cosF = cosF,
      halfW = halfW, halfH = halfH,
    }, nil
  end
  local fraction = fallbackViewFraction()
  return {
    mode = "frac",
    mx = mx, my = my,
    radius = fraction,
    radiusUnit = "map fractions (fallback: no yard radius for this zone)",
    sinF = sinF, cosF = cosF,
    halfW = halfW, halfH = halfH,
  }, nil
end

function M:_sample()
  local sample, why = sampleFor(self, self.mapID, self.useWorld, self.zoneW, self.zoneH)
  self._sampleWhy = why
  return sample
end

function M:_redraw()
  self._lastQueued = 0
  self._why = nil
  self._proj = nil
  if not self.points or #self.points < 2 then
    self._why = "no route"
    self:ReleaseVisuals()
    return
  end
  if not ns.GetDB().showMinimap then
    self._why = "showMinimap is off"
    self:ReleaseVisuals()
    return
  end
  if Minimap and type(Minimap.IsVisible) == "function" then
    local ok, visible = pcall(Minimap.IsVisible, Minimap)
    if ok and not visible then
      self._why = "the minimap is hidden"
      self:ReleaseVisuals()
      return
    end
  end

  local sample = self:_sample()
  if not sample or not sample.radius or sample.radius <= 0 then
    self._why = "no projection: " .. tostring(self._sampleWhy or "the sample is unusable")
    self:ReleaseVisuals()
    return
  end
  local host = self:EnsureHost()
  if not host or not self.drawer then
    self._why = "no overlay host (CreateFrame failed)"
    self:ReleaseVisuals()
    return
  end

  local buf = self._segBuf or {}
  self._segBuf = buf
  local count = 0
  local pts = self.points
  -- Recorded for /nt mapdiag: the same numbers the draw used, so "0 segments"
  -- can be attributed to the projection, to the clip, or to the route being
  -- outside the minimap's view instead of guessed at.
  local proj = {
    mode = sample.mode,
    radius = sample.radius,
    radiusUnit = sample.radiusUnit,
    halfW = sample.halfW,
    halfH = sample.halfH,
    player = { x = sample.mx, y = sample.my, px = sample.px, py = sample.py },
    points = {},
    segs = {},
  }
  for i = 1, #pts do
    local ax, ay = pointDelta(sample, pts[i])
    if ax ~= nil then
      local x1, y1 = toPixel(ax, ay, sample)
      local dist = math.sqrt((x1 or 0) * (x1 or 0) + (y1 or 0) * (y1 or 0))
      local radiusPx = math.min(sample.halfW, sample.halfH) * ROUND_INSET
      proj.points[i] = {
        x = x1, y = y1,
        dx = ax, dy = ay,
        dist = dist,
        ratio = (radiusPx > 0) and (dist / radiusPx) or nil,
        inside = radiusPx > 0 and dist <= radiusPx,
      }
    else
      proj.points[i] = { why = "no delta (point lacks the coordinate this mode needs)" }
    end
  end
  for i = 1, #pts - 1 do
    local a, b = proj.points[i], proj.points[i + 1]
    local entry = { index = i }
    if a and b and a.x and b.x then
      local cx1, cy1, cx2, cy2 = clipToMinimap(a.x, a.y, b.x, b.y, sample.halfW, sample.halfH)
      local raw = math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y))
      if cx1 then
        count = count + 1
        local seg = buf[count]
        if not seg then
          seg = {}
          buf[count] = seg
        end
        seg[1], seg[2], seg[3], seg[4] = cx1, cy1, cx2, cy2
        entry.queued = true
        entry.len = math.sqrt((cx2 - cx1) * (cx2 - cx1) + (cy2 - cy1) * (cy2 - cy1))
        entry.clip = { cx1, cy1, cx2, cy2 }
        -- A queued segment can still be a no-op: two points that project to the
        -- same pixel are "drawn" and invisible. Name that instead of counting
        -- it as a success.
        if entry.len < 0.5 then
          entry.reason = "degenerate"
          entry.why = ("queued as a %spx segment (draws nothing)"):format(fmtNum(entry.len, 1))
        else
          entry.reason = "queued"
        end
      else
        -- Every dropped segment gets ONE named reason, out of the same four
        -- words the card asks for, so nothing disappears unexplained.
        if raw < 0.5 then
          entry.reason = "degenerate"
          entry.why = "clipped away: the projected pair is shorter than half a pixel"
        elseif a.inside == false and b.inside == false then
          entry.reason = "outside-radius"
          entry.why = "clipped away: both endpoints outside the minimap circle"
        else
          entry.reason = "culled"
          entry.why = "clipped away: the clip returned nothing with at least one endpoint inside"
        end
      end
    else
      entry.reason = "culled"
      entry.why = "not drawn: a point has no projection"
    end
    proj.segs[i] = entry
  end

  local r, g, bCol, a, thickness = ns.LineDraw.ColorWidth()
  -- Same treatment as the world map: the dot is a screen measurement, divided
  -- by whatever scale this host is drawn at, so both surfaces agree in px.
  local hostScale = 1
  if host and type(host.GetScale) == "function" then
    local okS, s = pcall(host.GetScale, host)
    if okS and type(s) == "number" and s > 0 then
      hostScale = s
    end
  end
  local metrics = ns.LineDraw.DotMetrics(thickness, hostScale)
  self._dotMetrics = metrics
  ns.LineDraw.Draw(self.drawer, host, buf, count, thickness, r, g, bCol, a, "yup", metrics)
  self._lastQueued = count
  self._proj = proj

  -- ── t_86583cf2: THE STAMP. Captured here, once, at draw time ──────────────
  -- Every value below is what THIS draw used. The diag prints the stamp back
  -- instead of recomputing it, so "the line slid while I walked" can be checked
  -- against the player fraction the drawing was actually built from — the
  -- player's own map fraction at print time is a different number by design.
  local stamp = {
    time = nowTime(),
    mapID = self.mapID,
    projMode = sample.mode,
    radius = sample.radius,
    radiusUnit = sample.radiusUnit,
    halfW = sample.halfW,
    halfH = sample.halfH,
    segs = count,
    plannedPoints = #pts,
    scale = hostScale,
    playerFrac = sample.mx and { x = sample.mx, y = sample.my } or nil,
    playerWorld = (sample.px and sample.py) and { x = sample.px, y = sample.py, inst = sample.pinst } or nil,
  }
  self._stamp = stamp
  if type(self.drawer.lastApplied) == "table" then
    local applied = self.drawer.lastApplied
    applied.time = stamp.time
    applied.mapID = stamp.mapID
    applied.projMode = stamp.projMode
    applied.radius = stamp.radius
    applied.radiusUnit = stamp.radiusUnit
    applied.halfW, applied.halfH = stamp.halfW, stamp.halfH
    applied.playerFrac = stamp.playerFrac
    applied.playerWorld = stamp.playerWorld
    applied.plannedPoints = stamp.plannedPoints
    applied.sampleTime = stamp.time
  end
  -- The anchors are read LAZILY (`M:DrawnAudit`), from these same objects and
  -- this same sample: reading them on every redraw would cost ~1200 GetPoint
  -- calls at 12.5Hz for a number only the diag and the walk recorder ever ask
  -- for, and the pool still holds exactly this draw's objects when they do.
  self._lastSample = sample
  self._drawn = nil
  self._drawnStamp = nil

  if count > 0 then
    pcall(host.Show, host)
  else
    local outside = 0
    local nearest, nearestIndex
    for i = 1, #proj.points do
      local p = proj.points[i]
      if p and p.inside == false then
        outside = outside + 1
      end
      if p and type(p.dist) == "number" and (not nearest or p.dist < nearest) then
        nearest, nearestIndex = p.dist, i
      end
    end
    -- "Nothing drawn" must say WHY with the quantity that decides it: the
    -- distance from the player to the nearest route point, in the projection's
    -- own units and in minimap radii. A player 5.6 radii from the line is not a
    -- broken projection, and the diag has to tell them apart (review round 3:
    -- the verdict named the clipped fraction but never the nearest distance).
    local extra = ""
    if nearest and nearestIndex then
      local yards = nearest / sample.halfW * sample.radius
      extra = ("; nearest point #%d is %spx = %s%s = %sx-radius (the minimap covers %s%s)")
        :format(nearestIndex, fmtNum(nearest, 1), fmtNum(yards, 1),
          sample.mode == "world" and " yd" or "",
          fmtNum(sample.halfW > 0 and (nearest / (math.min(sample.halfW, sample.halfH) * ROUND_INSET)) or nil, 2),
          fmtNum(sample.radius, 1), sample.mode == "world" and " yd" or "")
    end
    self._why = (("none of the %d segment(s) reach the minimap: %d of %d point(s) project outside the %.0fpx circle%s")
      :format(#proj.segs, outside, #proj.points, math.min(sample.halfW, sample.halfH) * ROUND_INSET, extra))
    pcall(host.Hide, host)
  end
end

--- Read every drawn dot's REAL anchors off the pool objects, and recover the
--- route index each one belongs to from where its anchor puts it. This is the
--- measurement the earlier (circular) check never made: the anchors are the
--- client's answer about the objects on screen, not the projection's opinion.
--- @return { painted, planned, dots = { { dot, pool, cx, cy, dist, seg, t, ... } }, nearest }
function M:_auditDrawn(proj, sample)
  local drawer = self.drawer
  local applied = drawer and drawer.lastApplied
  local painted = tonumber(type(applied) == "table" and applied.paintedDots) or 0
  local audit = {
    painted = painted,
    planned = tonumber(type(applied) == "table" and applied.plannedDots) or 0,
    dots = {},
    anchored = 0,
    unmeasured = 0,
  }
  if not drawer or drawer.mode ~= "dots" then
    return audit
  end
  for d = 1, painted do
    -- Even pool indices are the white dot of each pair (odd is its rim).
    local obj = drawer.pool and drawer.pool[2 * d]
    if obj then
      local points = readPoints(obj)
      local cx, cy = anchorCentre(points)
      if cx then
        local rec = {
          dot = d, pool = 2 * d, cx = cx, cy = cy, points = points,
          dist = math.sqrt(cx * cx + cy * cy),
        }
        rec.unitDist, rec.fracDist = pxToUnits(sample, cx, cy)
        rec.seg, rec.t, rec.segDist = nearestSegmentPx(proj.points, cx, cy)
        if rec.seg then
          rec.index = (rec.t and rec.t >= 0.5) and (rec.seg + 1) or rec.seg
          -- Distance from the minimap centre (the player) to the segment the
          -- dot sits on: the quantity the four-stop walk has to see shrink. It
          -- is measured from the PLAYER, so it is not the dot's own distance
          -- (which is ~0 by construction of the dot chain).
          local a, b = proj.points[rec.seg], proj.points[rec.seg + 1]
          if a and b then
            local dist, qx, qy = segmentDistance(0, 0, a.x, a.y, b.x, b.y)
            rec.playerSegPx = dist
            rec.playerSegX, rec.playerSegY = qx, qy
            rec.playerSegUnit, rec.playerSegFrac = pxToUnits(sample, qx, qy)
          end
        end
        audit.dots[#audit.dots + 1] = rec
        audit.anchored = audit.anchored + 1
        if not audit.nearest or rec.dist < audit.nearest.dist then
          audit.nearest = rec
        end
      else
        audit.unmeasured = audit.unmeasured + 1
      end
    end
  end
  return audit
end

--- The drawn-dot audit for the LAST draw, computed once and cached against that
--- draw's stamp. Both halves come from the same draw, so a diag printed between
--- two redraws cannot mix one draw's stamp with another draw's anchors.
function M:DrawnAudit()
  if self._drawn and self._drawnStamp == self._stamp then
    return self._drawn
  end
  if type(self._stamp) ~= "table" or type(self._lastSample) ~= "table" then
    return nil
  end
  self._drawn = self:_auditDrawn(self._proj, self._lastSample)
  self._drawnStamp = self._stamp
  return self._drawn
end

--- Draw the skinning farming circle on the minimap. Same sample, same clip and
--- the same dot machinery as the herb pass; its own drawer, host, colour and
--- stamps, so neither layer can blank the other.
function M:_redrawSkin()
  self._skinQueued = 0
  self._skinWhy = nil
  self._skinProj = nil
  if not self.skinPoints or #self.skinPoints < 2 then
    self._skinWhy = "no skinning circle"
    self:ReleaseSkinVisuals()
    return
  end
  if not ns.GetDB().showMinimap then
    self._skinWhy = "showMinimap is off"
    self:ReleaseSkinVisuals(self._skinWhy)
    return
  end
  if Minimap and type(Minimap.IsVisible) == "function" then
    local ok, visible = pcall(Minimap.IsVisible, Minimap)
    if ok and not visible then
      self._skinWhy = "the minimap is hidden"
      self:ReleaseSkinVisuals(self._skinWhy)
      return
    end
  end

  local sample, why = sampleFor(self, self.skinMapID, self.skinUseWorld, self.skinZoneW, self.skinZoneH)
  if not sample or not sample.radius or sample.radius <= 0 then
    self._skinWhy = "no projection: " .. tostring(why or "the sample is unusable")
    self:ReleaseSkinVisuals(self._skinWhy)
    return
  end
  local host = self:EnsureSkinHost()
  if not host or not self.skinDrawer then
    self._skinWhy = "no skinning overlay host (CreateFrame failed)"
    self:ReleaseSkinVisuals(self._skinWhy)
    return
  end

  local buf = self._skinBuf or {}
  self._skinBuf = buf
  local count = 0
  local pts = self.skinPoints
  local proj = { mode = sample.mode, points = {}, segs = {} }
  for i = 1, #pts do
    local ax, ay = pointDelta(sample, pts[i])
    if ax ~= nil then
      local x1, y1 = toPixel(ax, ay, sample)
      local dist = math.sqrt((x1 or 0) * (x1 or 0) + (y1 or 0) * (y1 or 0))
      local radiusPx = math.min(sample.halfW, sample.halfH) * ROUND_INSET
      proj.points[i] = {
        x = x1, y = y1, dx = ax, dy = ay, dist = dist,
        ratio = (radiusPx > 0) and (dist / radiusPx) or nil,
        inside = radiusPx > 0 and dist <= radiusPx,
      }
    else
      proj.points[i] = { why = "no delta (point lacks the coordinate this mode needs)" }
    end
  end
  for i = 1, #pts - 1 do
    local a, b = proj.points[i], proj.points[i + 1]
    local entry = { index = i }
    if a and b and a.x and b.x then
      local cx1, cy1, cx2, cy2 = clipToMinimap(a.x, a.y, b.x, b.y, sample.halfW, sample.halfH)
      if cx1 then
        count = count + 1
        local seg = buf[count]
        if not seg then
          seg = {}
          buf[count] = seg
        end
        seg[1], seg[2], seg[3], seg[4] = cx1, cy1, cx2, cy2
        entry.queued = true
      end
    end
    proj.segs[i] = entry
  end

  local c = self.skinColor or (ns.SkinRoute and ns.SkinRoute.COLOR) or { 0.1, 0.85, 0.35, 0.95 }
  local r = tonumber(c[1]) or 0.1
  local g = tonumber(c[2]) or 0.85
  local bCol = tonumber(c[3]) or 0.35
  local a = tonumber(c[4]) or 0.95
  local thickness = tonumber((self.skinRoute and self.skinRoute.width)
    or (ns.SkinRoute and ns.SkinRoute.WIDTH)) or 2
  if thickness <= 0 then thickness = 2 end
  local hostScale = 1
  if host and type(host.GetScale) == "function" then
    local okS, s = pcall(host.GetScale, host)
    if okS and type(s) == "number" and s > 0 then
      hostScale = s
    end
  end
  local metrics = ns.LineDraw.DotMetrics(thickness, hostScale)
  self._skinDotMetrics = metrics
  ns.LineDraw.Draw(self.skinDrawer, host, buf, count, thickness, r, g, bCol, a, "yup", metrics)
  self._skinQueued = count
  self._skinProj = proj
  self._skinSample = sample
  if type(self.skinDrawer.lastApplied) == "table" then
    self.skinDrawer.lastApplied.time = nowTime()
  end
  if count > 0 then
    pcall(host.Show, host)
  else
    self._skinWhy = "none of the circle's segments landed inside the minimap view"
    pcall(host.Hide, host)
  end
end

function M:Redraw()
  if self._busy then
    return
  end
  self._busy = true
  local ok, err = pcall(self._redraw, self)
  -- The skinning circle is drawn by a second, independent pass: the herb pass
  -- may refuse (no route, off) without that decision touching the circle.
  local okS, errS = pcall(self._redrawSkin, self)
  self._busy = false
  if not ok then
    self._drawError = tostring(err)
    pcall(self.ReleaseVisuals, self)
  else
    self._drawError = nil
  end
  if not okS then
    self._skinError = tostring(errS)
    pcall(self.ReleaseSkinVisuals, self)
  else
    self._skinError = nil
  end
end

function M:StartUpdates()
  local driver = self._driver
  if not driver then
    return
  end
  self._acc = 0
  driver:SetScript("OnUpdate", function(_, elapsed)
    if not M.path and not M.skinPoints then
      M:StopUpdates()
      return
    end
    M._acc = (M._acc or 0) + (elapsed or 0)
    if M._acc < UPDATE_INTERVAL then
      return
    end
    M._acc = 0
    -- t_86583cf2: how many redraws the TICKER drove, and how many of them came
    -- after the last player move. A frozen ticker and a ticker that keeps
    -- redrawing a stationary player look identical in a screenshot.
    M._ticks = (M._ticks or 0) + 1
    M:Redraw()
  end)
end

function M:SetRoute(route)
  if not route or not route.path or #route.path < 2 or not ns.GetDB().showMinimap then
    self:Clear()
    -- Say WHY nothing is on the minimap: "cleared" and "the switch is off" look
    -- identical in the diag otherwise (t_86583cf2 re-scope added the switch).
    if route and route.path and #route.path >= 2 and not ns.GetDB().showMinimap then
      self._why = "showMinimap is off (/nt minimap on turns the minimap route back on)"
    end
    return
  end
  self.mapID = route.mapID
  self.path = route.path
  self:_indexPoints(route)
  self:StartUpdates()
  self:Redraw()
end

-- ── the skinning farming circle (t_b46e5e87) ────────────────────────────────
-- Second layer, second drawer, second host. Set and cleared independently of the
-- herb route: /nt stop leaves the circle alone and /nt skinroute off leaves the
-- herb line alone and its fractions untouched.
function M:SetSkinRoute(route)
  if not route or not route.path or #route.path < 2 or not ns.GetDB().showMinimap then
    self:ClearSkinRoute()
    return
  end
  self.skinMapID = route.mapID
  self.skinPath = route.path
  self.skinColor = route.color
  self.skinRoute = route
  self:_indexSkinPoints(route)
  self:StartUpdates()
  self:Redraw()
end

function M:ClearSkinRoute()
  self.skinPath = nil
  self.skinMapID = nil
  self.skinColor = nil
  self.skinRoute = nil
  self.skinPoints = nil
  self.skinUseWorld = nil
  self.skinZoneW, self.skinZoneH = nil, nil
  self._skinProj = nil
  self._skinSample = nil
  self._skinQueued = 0
  self._skinWhy = nil
  self:ReleaseSkinVisuals()
  if not self.path then
    self:StopUpdates()
  end
end

local driver = CreateFrame("Frame")
M._driver = driver
local function onEvent(_, event, arg1)
  if not M.path and not M.skinPoints then
    return
  end
  if event == "CVAR_UPDATE" then
    if arg1 == "rotateMinimap" or arg1 == "ROTATE_MINIMAP" then
      M._acc = 0
      M:Redraw()
    end
    return
  end
  if IMMEDIATE[event] then
    if event == "PLAYER_STARTED_MOVING" then
      M._moves = (M._moves or 0) + 1
      M._moveTick = M._ticks or 0
      M._moveTime = nowTime()
    end
    M._acc = 0
    M:Redraw()
  end
end
driver:SetScript("OnEvent", function(frame, event, ...)
  local ok, err = pcall(onEvent, frame, event, ...)
  if not ok then
    M._drawError = tostring(err)
  end
end)
for event in pairs(IMMEDIATE) do
  pcall(driver.RegisterEvent, driver, event)
end
pcall(driver.RegisterEvent, driver, "CVAR_UPDATE")

-- ── /nt mapdiag, minimap half ───────────────────────────────────────────────
-- Same shape as MapOverlay:Diag: one labelled line per fact, built inside
-- pcall, so a client missing these APIs prints "absent" instead of erroring.
local function say(text)
  local line = "NodeTrail mapdiag: " .. tostring(text)
  if type(DEFAULT_CHAT_FRAME) == "table" and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
    local ok = pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, line)
    if ok then
      return
    end
  end
  pcall(print, line)
end

local function fact(build)
  local ok, text = pcall(build)
  if not ok then
    text = "error: " .. tostring(text)
  end
  say(text)
end

--- The player's map fraction, through the same chain the drawer uses.
--- Exposed for the walk recorder, so "player coordinates from the client" at a
--- stop and "the fraction the draw was built from" are measured the same way.
function M:PlayerFrac()
  return playerMapPosition(self.mapID, getHBD())
end

-- ── /nt navwalk (t_86583cf2) ───────────────────────────────────────────────
-- Mightie's walk test, recorded at the moment of each stop: the player's own
-- coordinates, the DRAW-TIME stamp, the nearest drawn dot's real anchors, the
-- route point that dot belongs to, its world-map anchor, and the distance from
-- the player to that segment. Four commands and a /reload turn the test into a
-- table that survives the session (NodeTrailDB.navwalk) instead of a screenshot
-- somebody has to transcribe.
ns.NavWalk = ns.NavWalk or {}
local NW = ns.NavWalk
local NAVWALK_MAX = 12

local function fmtStop(rec)
  local function n(v, d)
    if type(v) ~= "number" then return "absent" end
    return string.format("%." .. (d or 0) .. "f", v)
  end
  local parts = { string.format("stop %s %s", n(rec.n), tostring(rec.label or "")) }
  parts[#parts + 1] = string.format("player=(%s,%s)", n(rec.playerX, 4), n(rec.playerY, 4))
  parts[#parts + 1] = string.format("stamp=(%s,%s)/t=%s", n(rec.stampX, 4), n(rec.stampY, 4), n(rec.drawTime, 2))
  parts[#parts + 1] = string.format("dot=(%s,%s)px dist=%spx=%sfrac",
    n(rec.dotX, 1), n(rec.dotY, 1), n(rec.dotDist, 1), n(rec.dotFrac, 5))
  parts[#parts + 1] = string.format("seg=%s pt=#%s world=%s player->seg=%spx=%sfrac",
    n(rec.seg), n(rec.index), tostring(rec.world), n(rec.playerSegPx, 1), n(rec.playerSegFrac, 5))
  if rec.mapID ~= nil then
    parts[#parts + 1] = "mapID=" .. n(rec.mapID)
  end
  return table.concat(parts, " ")
end

function NW:_save()
  if type(NodeTrailDB) == "table" then
    NodeTrailDB.navwalk = {
      savedAt = nowTime(),
      startedAt = self.startedAt,
      mapID = self.mapID,
      why = self.why,
      stops = self.stops or {},
    }
  end
end

function NW:Begin()
  self.stops = {}
  self.startedAt = nowTime()
  self.why = nil
  self:_save()
  return #self.stops
end

function NW:Mark(label, note)
  self.stops = self.stops or {}
  local m = ns.MinimapPath
  if type(m) ~= "table" or type(m._stamp) ~= "table" then
    self.why = "no minimap drawing yet (start a route with /nt start)"
    return nil, self.why
  end
  if #self.stops >= NAVWALK_MAX then
    return nil, ("already %d stops; /nt navwalk clear first"):format(#self.stops)
  end
  -- Redraw first: the stamp must belong to this stop, not the previous one.
  if type(m.Redraw) == "function" then
    pcall(m.Redraw, m)
  end
  local stamp = m._stamp or {}
  local drawn = (type(m.DrawnAudit) == "function" and m:DrawnAudit()) or {}
  local dot = drawn.nearest
  local px, py = m:PlayerFrac()
  local rec = {
    n = #self.stops + 1,
    label = tostring(label or ""),
    note = note and tostring(note) or nil,
    time = nowTime(),
    mapID = stamp.mapID or m.mapID,
    drawTime = stamp.time,
    stampX = stamp.playerFrac and stamp.playerFrac.x or nil,
    stampY = stamp.playerFrac and stamp.playerFrac.y or nil,
    playerX = px, playerY = py,
    painted = drawn.painted, planned = drawn.planned,
  }
  if dot then
    rec.dotX, rec.dotY = dot.cx, dot.cy
    rec.dotDist = dot.dist
    rec.dotFrac = dot.fracDist
    rec.seg, rec.t, rec.index = dot.seg, dot.t, dot.index
    rec.playerSegPx, rec.playerSegFrac = dot.playerSegPx, dot.playerSegFrac
    rec.anchors = dot.points
    local overlay = ns.MapOverlay
    local wpx = type(overlay) == "table" and overlay._px or nil
    if type(wpx) == "table" and type(wpx[rec.index or -1]) == "table" then
      rec.world = string.format("(%s,%s)", fmtNum(wpx[rec.index].x, 1), fmtNum(wpx[rec.index].y, 1))
      rec.worldX, rec.worldY = wpx[rec.index].x, wpx[rec.index].y
    end
  end
  if px and rec.stampX and math.abs(px - rec.stampX) > 1e-6 then
    -- The draw is older than the player's current position: this stop's stamp is
    -- not a still frame, and the table must say so rather than look clean.
    rec.stale = true
  end
  self.stops[#self.stops + 1] = rec
  self.mapID = rec.mapID
  self:_save()
  return rec
end

function NW:Lines()
  self.stops = self.stops or {}
  local out = {}
  out[#out + 1] = ("navwalk: %d stop(s)%s; saved to NodeTrailDB.navwalk (written on /reload or logout)")
    :format(#self.stops, self.why and (" — " .. self.why) or "")
  for i = 1, #self.stops do
    out[#out + 1] = fmtStop(self.stops[i])
  end
  return out
end

function NW:Clear()
  self.stops = {}
  self.why = "cleared"
  self:_save()
  return true
end

function M:Diag()
  fact(function()
    if not Minimap then
      return "Minimap: absent"
    end
    local okW, w = pcall(Minimap.GetWidth, Minimap)
    local okH, h = pcall(Minimap.GetHeight, Minimap)
    local visible = "absent"
    if type(Minimap.IsVisible) == "function" then
      local okV, v = pcall(Minimap.IsVisible, Minimap)
      visible = okV and tostring(v) or "error"
    end
    return string.format("Minimap: present, size=%sx%s visible=%s zoom=%s",
      okW and fmtNum(w) or "absent", okH and fmtNum(h) or "absent", visible,
      (type(Minimap.GetZoom) == "function") and fmtNum(select(2, pcall(Minimap.GetZoom, Minimap))) or "absent")
  end)
  fact(function()
    local host = self.host
    if not host then
      return "minimap host: absent"
    end
    local okW, w = pcall(host.GetWidth, host)
    local okH, h = pcall(host.GetHeight, host)
    local name = "<unnamed>"
    if type(host.GetName) == "function" then
      local okN, value = pcall(host.GetName, host)
      if okN and type(value) == "string" and value ~= "" then
        name = value
      end
    end
    return string.format("minimap host: parent=%s size=%sx%s",
      name, okW and fmtNum(w) or "absent", okH and fmtNum(h) or "absent")
  end)
  fact(function()
    local mode = self.drawer and self.drawer.mode or "absent"
    local held = (self.drawer and self.drawer.pool and #self.drawer.pool) or 0
    local ticker = "off"
    if self._driver and type(self._driver.GetScript) == "function" then
      local ok, fn = pcall(self._driver.GetScript, self._driver, "OnUpdate")
      ticker = (ok and type(fn) == "function") and "on" or "off"
    end
    return string.format("minimap redraw: queued=%s segment(s); LineDraw mode=%s; objects held=%s; ticker=%s",
      fmtNum(self._lastQueued or 0), tostring(mode), fmtNum(held), ticker)
  end)
  fact(function()
    -- Which HereBeDragons answered, so "the scale is a guess" always names the
    -- library it could not find rather than leaving the reader to assume.
    return "minimap hereBeDragons: " .. hbdSourceText()
  end)
  fact(function()
    local why = ""
    if self._worldWhy and not self.useWorld then
      why = ("; world projection OFF: %s"):format(tostring(self._worldWhy))
    elseif self._worldWhy and self.useWorld then
      why = ("; HereBeDragons converted all %s point(s)"):format(fmtNum(self._worldPoints))
    end
    return string.format("minimap projection: points=%s useWorld=%s worldPoints=%s/%s zone=%sx%s radius=%s%s",
      fmtNum(self.points and #self.points or 0), tostring(self.useWorld),
      fmtNum(self._worldPoints or 0), fmtNum(self.points and #self.points or 0),
      fmtNum(self.zoneW), fmtNum(self.zoneH), fmtNum(viewRadiusYards()), why)
  end)
  fact(function()
    local p = self._proj
    if type(p) ~= "table" then
      return "minimap projection used: not measured yet (no redraw with a usable sample)"
    end
    return string.format("minimap projection used: mode=%s radius=%s [%s] half=%sx%s",
      tostring(p.mode), fmtNum(p.radius, 4), tostring(p.radiusUnit),
      fmtNum(p.halfW, 1), fmtNum(p.halfH, 1))
  end)
  fact(function()
    local p = self._proj
    if type(p) ~= "table" then
      return "minimap why: " .. tostring(self._why or "no redraw yet")
    end
    if p.player and (p.player.x or p.player.px) then
      return string.format("minimap player: frac=(%s,%s) world=(%s,%s)",
        fmtNum(p.player.x, 3), fmtNum(p.player.y, 3),
        fmtNum(p.player.px, 1), fmtNum(p.player.py, 1))
    end
    return "minimap player: absent (no position this projection can use)"
  end)
  fact(function()
    local p = self._proj
    if type(p) ~= "table" or type(p.points) ~= "table" then
      return "minimap points: not projected yet"
    end
    local out = {}
    for i = 1, #p.points do
      local pt = p.points[i]
      if pt and pt.x then
        out[#out + 1] = string.format("#%d px=(%s,%s) dist=%sx-radius%s",
          i, fmtNum(pt.x, 1), fmtNum(pt.y, 1), fmtNum(pt.ratio, 2),
          pt.inside and " inside" or " OUTSIDE")
      else
        out[#out + 1] = string.format("#%d %s", i, tostring(pt and pt.why or "absent"))
      end
    end
    return "minimap points: " .. table.concat(out, "; ")
  end)
  fact(function()
    local p = self._proj
    if type(p) ~= "table" or type(p.segs) ~= "table" then
      return "minimap segments: not projected yet"
    end
    local out = {}
    for i = 1, #p.segs do
      local s = p.segs[i]
      if s.queued then
        out[#out + 1] = string.format("seg%d queued (%spx)", i, fmtNum(s.len, 1))
      else
        out[#out + 1] = string.format("seg%d skipped: %s", i, tostring(s.why))
      end
    end
    if #out == 0 then
      return "minimap segments: none in the route"
    end
    return "minimap segments: " .. table.concat(out, "; ")
  end)
  fact(function()
    -- Requirement: no segment may disappear without a NAME. One line per
    -- consecutive pair, with both projected coordinates, both radius tests and
    -- the reason word (outside-radius / degenerate / culled / queued).
    local p = self._proj
    if type(p) ~= "table" or type(p.segs) ~= "table" then
      return "minimap pairs: not projected yet"
    end
    local out = {}
    for i = 1, #p.segs do
      local s = p.segs[i]
      local a, b = p.points[i], p.points[i + 1]
      local function pt(v)
        if v and type(v.x) == "number" then
          return string.format("(%s,%s)", fmtNum(v.x, 1), fmtNum(v.y, 1))
        end
        return "no-projection"
      end
      local function test(v)
        if v and type(v.inside) == "boolean" then
          return string.format("%sx-radius %s", fmtNum(v.ratio, 2), v.inside and "inside" or "OUTSIDE")
        end
        return "radius n/a"
      end
      local reason = s.reason or (s.queued and "queued" or "culled")
      out[#out + 1] = string.format("%d->%d %s %s, %s %s, => %s",
        i, i + 1, pt(a), pt(b), test(a), test(b), reason)
    end
    if #out == 0 then
      return "minimap pairs: none (the route has a single point)"
    end
    return "minimap pairs: " .. table.concat(out, " | ")
  end)
  fact(function()
    -- "drew segments" is a claim about a redraw; with no redraw recorded there
    -- is nothing to claim. `_proj` is only set by a redraw that reached the
    -- measurement stage, so it is the honest indicator.
    if self._why then
      return "minimap verdict: " .. tostring(self._why)
    end
    if type(self._proj) ~= "table" then
      return "minimap verdict: no redraw on a usable minimap sample yet"
    end
    return "minimap verdict: drew segments"
  end)
  fact(function()
    local applied = self.drawer and ns.LineDraw.Applied(self.drawer) or nil
    local m = self._dotMetrics or (type(applied) == "table" and applied.mode == "dots" and applied)
    if type(m) ~= "table" then
      return "minimap dots: not measured yet (no redraw)"
    end
    local function pair(canvas, screen)
      return string.format("%s canvas px = %s screen px", fmtNum(canvas, 2), fmtNum(screen, 2))
    end
    if type(applied) == "table" and type(applied.dotSize) == "number" then
      return string.format("minimap dots: host scale=%s -> dot=%s; outline=%s; dots=%s",
        fmtNum(applied.dotScale, 3), pair(applied.dotSize, applied.dotScreenSize),
        pair(applied.dotOutline, applied.dotScreenOutline), fmtNum(applied.dots))
    end
    return string.format("minimap dots: host scale=%s -> dot=%s; outline=%s (nothing drawn yet)",
      fmtNum(m.scale, 3), pair(m.size, m.screenSize), pair(m.outline, m.screenOutline))
  end)
  -- ── t_86583cf2: what was DRAWN, from the drawing's own numbers ────────────
  fact(function()
    -- THE STAMP. Read off the drawer, printed verbatim — never recomputed. This
    -- is the player map fraction the objects on screen were built around; the
    -- player's fraction at print time is a different number whenever the player
    -- has moved since the last draw, which is exactly the point.
    local a = self.drawer and ns.LineDraw.Applied(self.drawer)
    local s = self._stamp
    if type(s) ~= "table" then
      if type(a) == "table" then
        return "minimap stamp: absent (the drawer has no draw-time stamp; nothing on screen to attribute)"
      end
      return "minimap stamp: absent (no draw yet)"
    end
    local frac = "absent"
    if type(s.playerFrac) == "table" then
      frac = string.format("(%.4f,%.4f)", s.playerFrac.x, s.playerFrac.y)
    end
    local world = "absent"
    if type(s.playerWorld) == "table" then
      world = string.format("(%.1f,%.1f inst=%s)",
        s.playerWorld.x, s.playerWorld.y, tostring(s.playerWorld.inst))
    end
    return string.format(
      "minimap stamp: mapID=%s playerFrac=%s world=%s at t=%s; mode=%s radius=%s [%s] half=%sx%s segs=%s/%s (captured at draw time, not recomputed)",
      fmtNum(s.mapID), frac, world, fmtNum(s.time, 3), tostring(s.projMode),
      fmtNum(s.radius, 4), tostring(s.radiusUnit),
      fmtNum(s.halfW, 1), fmtNum(s.halfH, 1), fmtNum(s.segs), fmtNum(s.plannedPoints))
  end)
  fact(function()
    -- The drawn dots' REAL anchors: the client's answer about the objects, not
    -- the projection's opinion — GetPoint(1)/GetPoint(2) as the region reports
    -- them, the centre they imply, and its distance from the minimap centre.
    local a = self:DrawnAudit()
    if type(a) ~= "table" then
      return "minimap drawn dot: absent (no draw yet)"
    end
    if a.painted == 0 then
      return "minimap drawn dot: none (painted=0 of planned " .. fmtNum(a.planned) .. ")"
    end
    local n = a.nearest
    if not n then
      return string.format(
        "minimap drawn dot: %s painted, none carries a numeric anchor (%s unmeasured) — the client accepted the draws and kept no geometry",
        fmtNum(a.painted), fmtNum(a.unmeasured))
    end
    local function pt(p, tag)
      if type(p) ~= "table" then
        return tag .. "=absent"
      end
      return string.format("%s=%s/%s(%s,%s)", tag, tostring(p.point), tostring(p.relativePoint),
        fmtNum(p.x, 2), fmtNum(p.y, 2))
    end
    local fracText = "absent"
    if type(n.fracDist) == "number" then
      fracText = fmtNum(n.fracDist, 5) .. " map-frac"
    elseif type(n.unitDist) == "number" then
      fracText = fmtNum(n.unitDist, 1) .. " yd"
    end
    local radiusPx = nil
    if type(self._stamp) == "table" and type(self._stamp.halfW) == "number" then
      radiusPx = math.min(self._stamp.halfW, self._stamp.halfH) * ROUND_INSET
    end
    local ratio = (radiusPx and radiusPx > 0) and fmtNum(n.dist / radiusPx, 3) or "absent"
    return string.format(
      "minimap drawn dot: nearest of %s painted (planned %s, anchored %s) pool #%s centre=(%s,%s)px dist=%spx = %sx-radius = %s; %s %s",
      fmtNum(a.painted), fmtNum(a.planned), fmtNum(a.anchored), fmtNum(n.pool),
      fmtNum(n.cx, 2), fmtNum(n.cy, 2), fmtNum(n.dist, 2),
      ratio, fracText, pt(n.points[1], "GetPoint(1)"), pt(n.points[2], "GetPoint(2)"))
  end)
  fact(function()
    -- Which route point the nearest drawn dot belongs to, and where the WORLD
    -- MAP puts that same index — the pair that lets one line say whether the two
    -- surfaces are showing the same route.
    local a = self:DrawnAudit()
    local n = type(a) == "table" and a.nearest or nil
    if not n or not n.seg then
      return "minimap drawn dot route: absent (no drawn dot with an anchor on a route segment)"
    end
    local idx = n.index or n.seg
    local world = "absent"
    local overlay = ns.MapOverlay
    local px = type(overlay) == "table" and overlay._px or nil
    if type(px) == "table" and type(px[idx]) == "table" then
      world = string.format("(%s,%s) canvas", fmtNum(px[idx].x, 1), fmtNum(px[idx].y, 1))
    end
    local segUnit = "absent"
    if type(n.playerSegFrac) == "number" then
      segUnit = fmtNum(n.playerSegFrac, 5) .. " map-frac"
    elseif type(n.playerSegUnit) == "number" then
      segUnit = fmtNum(n.playerSegUnit, 1) .. " yd"
    end
    return string.format(
      "minimap drawn dot route: segment %s->%s at t=%s -> route point #%s; player->that segment = %spx = %s; world-map anchor for #%s = %s",
      fmtNum(n.seg), fmtNum(n.seg + 1), fmtNum(n.t, 2), fmtNum(idx),
      fmtNum(n.playerSegPx, 2), segUnit, fmtNum(idx), world)
  end)
  fact(function()
    -- Drawn vs planned, and whether the ticker has fired since the player last
    -- moved: a route that is frozen while the player walks and a route that is
    -- redrawn on every frame are different bugs, and a screenshot cannot say.
    local a = self:DrawnAudit()
    local drawer = self.drawer
    local applied = drawer and ns.LineDraw.Applied(drawer) or {}
    local planned = tonumber(applied.plannedDots) or 0
    local painted = tonumber(applied.paintedDots) or 0
    local hidden = planned - painted
    if hidden < 0 then hidden = 0 end
    local outside = 0
    if type(self._proj) == "table" and type(self._proj.points) == "table" then
      for i = 1, #self._proj.points do
        local p = self._proj.points[i]
        if p and p.inside == false then
          outside = outside + 1
        end
      end
    end
    local ticker = "off"
    if self._driver and type(self._driver.GetScript) == "function" then
      local ok, fn = pcall(self._driver.GetScript, self._driver, "OnUpdate")
      ticker = (ok and type(fn) == "function") and "on" or "off"
    end
    local ticks = tonumber(self._ticks) or 0
    local since = ticks - (tonumber(self._moveTick) or 0)
    local anchored = type(a) == "table" and tonumber(a.anchored) or 0
    return string.format(
      "minimap drawn vs planned: drawn=%s planned=%s missing=%s (of %s route point(s), %s outside the radius); anchors read=%s; ticker=%s redraws=%s playerMoves=%s since-last-move=%s",
      fmtNum(painted), fmtNum(planned), fmtNum(hidden), fmtNum(self._stamp and self._stamp.plannedPoints),
      fmtNum(outside), fmtNum(anchored), ticker, fmtNum(ticks), fmtNum(self._moves or 0), fmtNum(since))
  end)
  fact(function()
    -- Point-by-point: the world map's canvas anchor, the minimap's pixel, and
    -- whether that point is actually drawn on the minimap (with the reason when
    -- it is not). "Hidden for being outside the minimap radius" is legitimate;
    -- a point missing from the WORLD map is not, so both are counted.
    local proj = self._proj
    local overlay = ns.MapOverlay
    local wpx = type(overlay) == "table" and overlay._px or nil
    local path = self.path
    if type(proj) ~= "table" or type(path) ~= "table" then
      return "minimap crosscheck: absent (no minimap projection on this route)"
    end
    local worldShown, worldMissing = 0, 0
    local miniDrawn, miniHidden = 0, 0
    local parts = {}
    for i = 1, #path do
      local w = type(wpx) == "table" and wpx[i] or nil
      local p = proj.points[i]
      local pt = type(self.points) == "table" and self.points[i] or nil
      local wText
      if type(w) == "table" then
        worldShown = worldShown + 1
        wText = string.format("(%s,%s)", fmtNum(w.x, 1), fmtNum(w.y, 1))
      else
        worldMissing = worldMissing + 1
        wText = "MISSING"
      end
      -- The three spaces, side by side and each labelled: the route's own map
      -- fraction, the world map's canvas pixel for it, and its HereBeDragons
      -- world yards. Review round 3 read `world=(429.8,89.5)` as a world
      -- position when it was the canvas anchor — one label, two spaces. Nothing
      -- in this line may be mistaken for another space again.
      local fracText, ydText = "absent", "absent"
      if type(pt) == "table" and type(pt.x) == "number" then
        fracText = string.format("(%s,%s)", fmtNum(pt.x, 3), fmtNum(pt.y, 3))
      end
      if type(pt) == "table" and type(pt.wx) == "number" then
        ydText = string.format("(%s,%s)", fmtNum(pt.wx, 1), fmtNum(pt.wy, 1))
      end
      local mText, state
      if type(p) == "table" and type(p.x) == "number" then
        local queued = (proj.segs[i] and proj.segs[i].queued) or (proj.segs[i - 1] and proj.segs[i - 1].queued)
        if p.inside and queued then
          miniDrawn = miniDrawn + 1
          state = "drawn"
        else
          miniHidden = miniHidden + 1
          state = p.inside and "hidden: on no queued segment" or "hidden: outside radius"
        end
        mText = string.format("(%s,%s)%s", fmtNum(p.x, 1), fmtNum(p.y, 1), p.inside and "" or "[out]")
      else
        miniHidden = miniHidden + 1
        state = "hidden: no projection"
        mText = "absent"
      end
      parts[#parts + 1] = string.format("#%s frac=%s canvas=%s worldYd=%s mini=%s %s",
        fmtNum(i), fracText, wText, ydText, mText, state)
    end
    local ids = "mapIDs differ"
    local mine, theirs = self.mapID, type(overlay) == "table" and overlay.mapID or nil
    if mine ~= nil and theirs ~= nil and mine == theirs then
      ids = "mapID equal"
    end
    return string.format(
      "minimap crosscheck: %s route point(s); world-map canvas %s on this map, %s missing; minimap %s drawn, %s hidden (outside radius or clipped); %s (%s vs %s): %s",
      fmtNum(#path), fmtNum(worldShown), fmtNum(worldMissing),
      fmtNum(miniDrawn), fmtNum(miniHidden), ids,
      fmtNum(mine), fmtNum(theirs), table.concat(parts, " | "))
  end)
  fact(function()
    -- Measure the SCALE instead of assuming it (ara, t_86583cf2). The fraction
    -- fallback draws a fixed 7.5% of the zone; if HereBeDragons is loaded the
    -- same points have real yard distances, so the ratio yards/px IS the scale
    -- and the radius it implies can be compared with the one the draw used.
    -- Absent HBD is reported as absent — this line never invents a measurement.
    local HBD = getHBD()
    local proj = self._proj
    local s = self._stamp
    if type(HBD) ~= "table" then
      return "minimap scale audit: absent (no HereBeDragons loaded: the radius stays the fraction fallback and cannot be cross-checked against yards)"
    end
    if type(proj) ~= "table" or type(s) ~= "table" or type(s.playerWorld) ~= "table" then
      return "minimap scale audit: absent (the last draw has no world position to measure from)"
    end
    local points = self.points or {}
    local samples = {}
    for i = 1, #points do
      local p, q = points[i], proj.points[i]
      if type(p) == "table" and type(q) == "table" and type(q.dist) == "number" and q.dist > 0.5
        and type(p.wx) == "number" then
        samples[#samples + 1] = { index = i, wx = p.wx, wy = p.wy, inst = p.inst, px = q.dist }
      end
    end
    if #samples == 0 then
      return "minimap scale audit: absent (no route point has both a world position and a drawn pixel)"
    end
    local function yardOf(rec)
      if type(HBD.GetWorldDistance) ~= "function" then
        return nil
      end
      local ok, yards = pcall(HBD.GetWorldDistance, HBD, s.playerWorld.inst or rec.inst,
        s.playerWorld.x, s.playerWorld.y, rec.wx, rec.wy)
      if ok and type(yards) == "number" then
        return yards
      end
      return nil
    end
    local parts = {}
    local firstScale
    local picks = { 1, math.max(1, math.floor(#samples / 2)), #samples }
    local seen = {}
    for k = 1, #picks do
      local rec = samples[picks[k]]
      if rec and not seen[rec.index] then
        seen[rec.index] = true
        local yards = yardOf(rec)
        if yards then
          local scale = yards / rec.px
          firstScale = firstScale or scale
          parts[#parts + 1] = string.format("#%s %syd / %spx = %s yd/px",
            fmtNum(rec.index), fmtNum(yards, 1), fmtNum(rec.px, 2), fmtNum(scale, 3))
        else
          parts[#parts + 1] = string.format("#%s no yard distance", fmtNum(rec.index))
        end
      end
    end
    local out = "minimap scale audit: " .. table.concat(parts, "; ")
    if firstScale and type(s.halfW) == "number" then
      local implied = firstScale * math.min(s.halfW, s.halfH)
      out = out .. string.format("; implied view radius=%s yd vs drawn radius=%s [%s]",
        fmtNum(implied, 1), fmtNum(s.radius, 4), tostring(s.radiusUnit))
      if s.projMode == "frac" then
        out = out .. string.format("; the draw is using the FALLBACK fraction (%s), so the implied radius above is what THIS projection should have used",
          fmtNum(s.radius, 4))
      end
    end
    return out
  end)
  fact(function()
    return "minimap drawError=" .. tostring(self._drawError or "none")
  end)
  fact(function()
    -- The skinning circle is a second layer: its own line, never mixed with the
    -- herb route's dots. `segs` is what the last circle draw queued; the colour
    -- is what the code passed to the draw (LineDraw records it, GetVertexColor
    -- cannot be trusted on this client).
    if not self.skinPath then
      return "skinning circle on the minimap: none (no circle for this map)"
    end
    local applied = (self.skinDrawer and ns.LineDraw.Applied(self.skinDrawer)) or {}
    local c = self.skinColor or {}
    return string.format(
      "skinning circle on the minimap: segs queued=%s painted=%s planned=%s colour=%.2f,%.2f,%.2f,%.2f map=%s mode=%s why=%s",
      fmtNum(self._skinQueued or 0), fmtNum(applied.paintedDots or 0), fmtNum(applied.plannedDots or 0),
      tonumber(c[1]) or 0, tonumber(c[2]) or 0, tonumber(c[3]) or 0, tonumber(c[4]) or 0,
      fmtNum(self.skinMapID), tostring(self._skinProj and self._skinProj.mode or "none"),
      tostring(self._skinWhy or self._skinError or "none"))
  end)
end


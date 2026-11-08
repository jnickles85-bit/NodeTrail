local addonName, pkg = ...
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

local function getHBD()
  if type(ns.GetGatherMate2) ~= "function" then
    return nil
  end
  local ok, gm = pcall(ns.GetGatherMate2)
  if ok and type(gm) == "table" and type(gm.HBD) == "table" then
    return gm.HBD
  end
  return nil
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
  self:StopUpdates()
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

function M:_indexPoints(route)
  local HBD = getHBD()
  local pts = {}
  local anyWorld = false
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
        end
      end
    end
    pts[i] = entry
  end
  self.points = pts
  self.useWorld = anyWorld
  self.zoneW, self.zoneH = nil, nil
  if HBD and type(HBD.GetZoneSize) == "function" and route.mapID then
    local ok, w, h = pcall(HBD.GetZoneSize, HBD, route.mapID)
    if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
      self.zoneW, self.zoneH = w, h
    end
  end
end

function M:_sample()
  local halfW, halfH = minimapHalf()
  if not halfW then
    return nil
  end
  local sinF, cosF, faceOK = minimapRotation()
  if not faceOK then
    return nil
  end
  local radiusYards = viewRadiusYards()
  local HBD = getHBD()

  if self.useWorld and HBD and type(HBD.GetPlayerWorldPosition) == "function" and radiusYards then
    local ok, x, y, inst = pcall(HBD.GetPlayerWorldPosition, HBD)
    if ok and type(x) == "number" and type(y) == "number" then
      return {
        mode = "world",
        px = x, py = y, pinst = inst,
        radius = radiusYards,
        sinF = sinF, cosF = cosF,
        halfW = halfW, halfH = halfH,
      }
    end
  end

  local mx, my = playerMapPosition(self.mapID, HBD)
  if not mx then
    return nil
  end
  if self.zoneW and self.zoneH and radiusYards then
    return {
      mode = "zone",
      mx = mx, my = my,
      zoneW = self.zoneW, zoneH = self.zoneH,
      radius = radiusYards,
      sinF = sinF, cosF = cosF,
      halfW = halfW, halfH = halfH,
    }
  end
  return {
    mode = "frac",
    mx = mx, my = my,
    radius = FALLBACK_VIEW_FRACTION,
    sinF = sinF, cosF = cosF,
    halfW = halfW, halfH = halfH,
  }
end

function M:_redraw()
  if not self.points or #self.points < 2 then
    self:ReleaseVisuals()
    return
  end
  if not ns.GetDB().showMinimap then
    self:ReleaseVisuals()
    return
  end
  if Minimap and type(Minimap.IsVisible) == "function" then
    local ok, visible = pcall(Minimap.IsVisible, Minimap)
    if ok and not visible then
      self:ReleaseVisuals()
      return
    end
  end

  local sample = self:_sample()
  if not sample or not sample.radius or sample.radius <= 0 then
    self:ReleaseVisuals()
    return
  end
  local host = self:EnsureHost()
  if not host or not self.drawer then
    self:ReleaseVisuals()
    return
  end

  local buf = self._segBuf or {}
  self._segBuf = buf
  local count = 0
  local pts = self.points
  for i = 1, #pts - 1 do
    local ax, ay = pointDelta(sample, pts[i])
    local bx, by = pointDelta(sample, pts[i + 1])
    if ax ~= nil and bx ~= nil then
      local x1, y1 = toPixel(ax, ay, sample)
      local x2, y2 = toPixel(bx, by, sample)
      local cx1, cy1, cx2, cy2 = clipToMinimap(x1, y1, x2, y2, sample.halfW, sample.halfH)
      if cx1 then
        count = count + 1
        local seg = buf[count]
        if not seg then
          seg = {}
          buf[count] = seg
        end
        seg[1], seg[2], seg[3], seg[4] = cx1, cy1, cx2, cy2
      end
    end
  end

  local r, g, bCol, a, thickness = ns.LineDraw.ColorWidth()
  ns.LineDraw.Draw(self.drawer, host, buf, count, thickness, r, g, bCol, a, "yup")
  self._lastQueued = count
  if count > 0 then
    pcall(host.Show, host)
  else
    pcall(host.Hide, host)
  end
end

function M:Redraw()
  if self._busy then
    return
  end
  self._busy = true
  local ok, err = pcall(self._redraw, self)
  self._busy = false
  if not ok then
    self._drawError = tostring(err)
    pcall(self.ReleaseVisuals, self)
  else
    self._drawError = nil
  end
end

function M:StartUpdates()
  local driver = self._driver
  if not driver then
    return
  end
  self._acc = 0
  driver:SetScript("OnUpdate", function(_, elapsed)
    if not M.path then
      M:StopUpdates()
      return
    end
    M._acc = (M._acc or 0) + (elapsed or 0)
    if M._acc < UPDATE_INTERVAL then
      return
    end
    M._acc = 0
    M:Redraw()
  end)
end

function M:SetRoute(route)
  if not route or not route.path or #route.path < 2 or not ns.GetDB().showMinimap then
    self:Clear()
    return
  end
  self.mapID = route.mapID
  self.path = route.path
  self:_indexPoints(route)
  self:StartUpdates()
  self:Redraw()
end

local driver = CreateFrame("Frame")
M._driver = driver
local function onEvent(_, event, arg1)
  if not M.path then
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

local function fmtNum(value)
  if type(value) ~= "number" or value ~= value then
    return "absent"
  end
  if value == math.floor(value) then
    return string.format("%d", value)
  end
  return string.format("%.2f", value)
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
    local name = select(2, pcall(host.GetName, host))
    return string.format("minimap host: parent=%s size=%sx%s",
      type(name) == "string" and name or "<unnamed>",
      okW and fmtNum(w) or "absent", okH and fmtNum(h) or "absent")
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
    return string.format("minimap projection: points=%s useWorld=%s zone=%sx%s radius=%s",
      fmtNum(self.points and #self.points or 0), tostring(self.useWorld),
      fmtNum(self.zoneW), fmtNum(self.zoneH), fmtNum(viewRadiusYards()))
  end)
  fact(function()
    return "minimap drawError=" .. tostring(self._drawError or "none")
  end)
end


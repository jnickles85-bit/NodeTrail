local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

-- World-map white polyline for the active herb route.
-- Points are map fractions (0..1). The line is parented to the map canvas so
-- it pans and zooms with that zone, and it is hidden when the open map is a
-- different mapID or the route is cleared.

ns.MapOverlay = ns.MapOverlay or {}
local M = ns.MapOverlay

local RETRY_LIMIT = 8

local function displayedMapID(mapFrame)
  if mapFrame and type(mapFrame.GetMapID) == "function" then
    local ok, id = pcall(mapFrame.GetMapID, mapFrame)
    if ok and type(id) == "number" and id > 0 then
      return id
    end
  end
  if type(GetCurrentMapAreaID) == "function" then
    local ok, id = pcall(GetCurrentMapAreaID)
    if ok and type(id) == "number" and id > 0 then
      return id
    end
  end
  if mapFrame and type(mapFrame.mapID) == "number" and mapFrame.mapID > 0 then
    return mapFrame.mapID
  end
  return nil
end

local function mapZoom(mapFrame)
  if mapFrame and type(mapFrame.GetCanvasScale) == "function" then
    local ok, scale = pcall(mapFrame.GetCanvasScale, mapFrame)
    if ok and type(scale) == "number" and scale > 0.05 and scale < 100 then
      return scale
    end
  end
  return 1
end

local function getCanvas(mapFrame)
  if not mapFrame or type(mapFrame.GetCanvas) ~= "function" then
    return nil
  end
  local ok, canvas = pcall(mapFrame.GetCanvas, mapFrame)
  if ok and canvas then
    return canvas
  end
  return nil
end

local function legacyParent()
  return _G.WorldMapButton or _G.WorldMapDetailFrame
end

function M:ReleaseVisuals()
  if self.drawer then
    ns.LineDraw.Clear(self.drawer)
  end
  if self.host then
    pcall(self.host.Hide, self.host)
  end
end

function M:Clear()
  self.path = nil
  self.mapID = nil
  self._retries = 0
  self:ReleaseVisuals()
end

function M:EnsureHost(parent)
  if not parent or type(CreateFrame) ~= "function" then
    return nil
  end
  if self.host and self._hostParent ~= parent then
    ns.LineDraw.BindOverlay(self.host, parent)
    self._hostParent = parent
    if self.drawer then
      ns.LineDraw.Invalidate(self.drawer)
    end
  end
  if not self.host then
    local ok, host = pcall(CreateFrame, "Frame", nil, parent)
    if not ok or not host then
      return nil
    end
    ns.LineDraw.BindOverlay(host, parent)
    self.host = host
    self._hostParent = parent
    self.drawer = ns.LineDraw.Create()
  end
  return self.host
end

function M:RequestRetry()
  if (self._retries or 0) >= RETRY_LIMIT or self._retryScheduled or not self.path then
    return
  end
  self._retries = (self._retries or 0) + 1
  self._retryScheduled = true
  local function fire()
    self._retryScheduled = false
    if self.path then
      self:Redraw()
    end
  end
  if C_Timer and type(C_Timer.After) == "function" then
    local ok = pcall(C_Timer.After, 0.05, fire)
    if ok then
      return
    end
  end
  local driver = self._events
  if not driver then
    self._retryScheduled = false
    return
  end
  local acc = 0
  driver:SetScript("OnUpdate", function(frame, elapsed)
    acc = acc + (elapsed or 0)
    if acc < 0.05 then
      return
    end
    frame:SetScript("OnUpdate", nil)
    fire()
  end)
end

function M:_redraw()
  if not self.path or #self.path < 2 then
    self:ReleaseVisuals()
    return
  end
  if not ns.GetDB().showWorldMap then
    self:ReleaseVisuals()
    return
  end

  local mapFrame = _G.WorldMapFrame
  local canvas = getCanvas(mapFrame)
  local parent = canvas or legacyParent()
  if not parent then
    self:ReleaseVisuals()
    self:RequestRetry()
    return
  end

  if canvas and self._sizedCanvas ~= canvas and type(canvas.HookScript) == "function" then
    local hooked = pcall(canvas.HookScript, canvas, "OnSizeChanged", function()
      M:Redraw()
    end)
    if hooked then
      self._sizedCanvas = canvas
    end
  end

  local shown = displayedMapID(mapFrame)
  if shown and self.mapID and shown ~= self.mapID then
    self:ReleaseVisuals()
    return
  end

  local host = self:EnsureHost(parent)
  if not host or not self.drawer then
    self:ReleaseVisuals()
    return
  end

  local okW, width = pcall(host.GetWidth, host)
  local okH, height = pcall(host.GetHeight, host)
  if not okW or not okH or type(width) ~= "number" or type(height) ~= "number" or width < 2 or height < 2 then
    self:ReleaseVisuals()
    self:RequestRetry()
    return
  end
  self._retries = 0

  local buf = self._segBuf or {}
  self._segBuf = buf
  local count = 0
  local geom = ns.PathGeom
  for i = 1, #self.path - 1 do
    local a, b = self.path[i], self.path[i + 1]
    if geom.IsMapPoint(a) and geom.IsMapPoint(b) then
      local x1, y1 = a.x * width, a.y * height
      local x2, y2 = b.x * width, b.y * height
      local dx, dy = x2 - x1, y2 - y1
      if dx * dx + dy * dy >= 0.25 then
        count = count + 1
        local seg = buf[count]
        if not seg then
          seg = {}
          buf[count] = seg
        end
        seg[1], seg[2], seg[3], seg[4] = x1, y1, x2, y2
      end
    end
  end

  local r, g, b, a, stroke = ns.LineDraw.ColorWidth()
  local thickness = stroke / mapZoom(mapFrame)
  ns.LineDraw.Draw(self.drawer, host, buf, count, thickness, r, g, b, a, "ydown")
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

function M:TryHookMap()
  local mapFrame = _G.WorldMapFrame
  if not mapFrame then
    return
  end
  if not self._providerHooked
    and MapCanvasDataProviderMixin
    and type(CreateFromMixins) == "function"
    and type(mapFrame.AddDataProvider) == "function"
  then
    local ok = pcall(function()
      local provider = CreateFromMixins(MapCanvasDataProviderMixin)
      function provider:RefreshAllData()
        M:Redraw()
      end
      function provider:RemoveAllData()
        M:ReleaseVisuals()
      end
      function provider:OnShow()
        M._retries = 0
        M:Redraw()
      end
      function provider:OnHide()
      end
      function provider:OnMapChanged()
        M._retries = 0
        M:Redraw()
      end
      function provider:OnCanvasSizeChanged()
        M:Redraw()
      end
      function provider:OnCanvasScaleChanged()
        M:Redraw()
      end
      mapFrame:AddDataProvider(provider)
      M._provider = provider
    end)
    if ok then
      self._providerHooked = true
    end
  end

  if self._providerHooked or self._legacyHooked then
    return
  end
  self._legacyHooked = true
  if type(mapFrame.HookScript) == "function" then
    pcall(mapFrame.HookScript, mapFrame, "OnShow", function()
      M._retries = 0
      M:Redraw()
    end)
  end
  local events = self._events
  if events and type(events.RegisterEvent) == "function" then
    pcall(events.RegisterEvent, events, "WORLD_MAP_UPDATE")
  end
end

function M:SetRoute(route)
  if not route or not route.path or #route.path < 2 or not ns.GetDB().showWorldMap then
    self:Clear()
    return
  end
  self.mapID = route.mapID
  self.path = route.path
  self._retries = 0
  self:TryHookMap()
  self:Redraw()
end

local events = CreateFrame("Frame")
M._events = events
local function onEvent(frame, event, name)
  if event == "ADDON_LOADED" and name ~= "Blizzard_WorldMap" and name ~= addonName then
    return
  end
  if event == "WORLD_MAP_UPDATE" and M._providerHooked then
    return
  end
  M:TryHookMap()
  if M.path then
    M._retries = 0
    M:Redraw()
  end
end
events:SetScript("OnEvent", function(frame, event, ...)
  local ok, err = pcall(onEvent, frame, event, ...)
  if not ok then
    M._drawError = tostring(err)
  end
end)
pcall(events.RegisterEvent, events, "ADDON_LOADED")
pcall(events.RegisterEvent, events, "PLAYER_LOGIN")
M:TryHookMap()

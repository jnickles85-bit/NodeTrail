local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

-- World-map white polyline for the active herb route.
-- Points are map fractions (0..1). The line is parented to whatever frame the
-- client actually pans and zooms with (modern: WorldMapFrame:GetCanvas(),
-- Classic: WorldMapDetailFrame / WorldMapButton), measured at draw time, and
-- converted through the measured map rectangle inside that host — see
-- PathGeom.MapRect / FractionToPixel. Hidden when the displayed mapID is not
-- the route's mapID, or when showWorldMap is off.

ns.MapOverlay = ns.MapOverlay or {}
local M = ns.MapOverlay

local RETRY_LIMIT = 8

local function isFn(value)
  return type(value) == "function"
end

local function call(obj, method, ...)
  if not obj or not isFn(obj[method]) then
    return nil
  end
  local ok, result = pcall(obj[method], obj, ...)
  if ok then
    return result
  end
  return nil
end

local function callGlobal(name, ...)
  local fn = _G[name]
  if not isFn(fn) then
    return nil
  end
  local ok, result = pcall(fn, ...)
  if ok then
    return result
  end
  return nil
end

local function frameSize(frame)
  if not frame then
    return nil
  end
  local w = call(frame, "GetWidth")
  local h = call(frame, "GetHeight")
  if type(w) ~= "number" or type(h) ~= "number" then
    return nil
  end
  return w, h
end

local function frameName(frame)
  local name = call(frame, "GetName")
  if type(name) == "string" and name ~= "" then
    return name
  end
  return "<unnamed>"
end

--- Strata draw order. A frame level only orders frames INSIDE one strata, so a
--- frame on a higher strata wins regardless of level; that is why the overlay
--- adopts the art's strata when the art orders above it.
local STRATA_RANK = {
  BACKGROUND = 1,
  LOW = 2,
  MEDIUM = 3,
  HIGH = 4,
  DIALOG = 5,
  FULLSCREEN = 6,
  FULLSCREEN_DIALOG = 7,
  TOOLTIP = 8,
}

local function strataRank(strata)
  if type(strata) ~= "string" then
    return nil
  end
  return STRATA_RANK[strata:upper()]
end

local function frameLevel(frame)
  local level = call(frame, "GetFrameLevel")
  if type(level) == "number" then
    return level
  end
  return nil
end

local function shownState(frame)
  local shown = call(frame, "IsShown")
  if type(shown) == "boolean" then
    return shown
  end
  shown = call(frame, "IsVisible")
  if type(shown) == "boolean" then
    return shown
  end
  return nil
end

local function fmtNum(value, decimals)
  if type(value) ~= "number" then
    return "absent"
  end
  if value ~= value then
    return "nan"
  end
  if decimals then
    return string.format("%." .. decimals .. "f", value)
  end
  if value == math.floor(value) then
    return string.format("%d", value)
  end
  return string.format("%.2f", value)
end

--- One frame as a diag fact: name, level, strata, shown, size.
local function frameFact(frame)
  if not frame then
    return "absent"
  end
  local w, h = frameSize(frame)
  return string.format("%s(lvl=%s strata=%s shown=%s %sx%s)",
    frameName(frame),
    tostring(frameLevel(frame) or "?"),
    tostring(call(frame, "GetFrameStrata") or "?"),
    tostring(shownState(frame)),
    fmtNum(w), fmtNum(h))
end

--- The frames a map draws its ART with, as far as this client exposes them.
--- On a client with the canvas system the art is a pool of detail-layer frames
--- parented to the canvas (MapCanvasDetailLayerTemplate, useParentLevel), so a
--- sibling overlay only wins by frame level. On the 1.12-derived clients the
--- 1.12 art frames are the ones that cover the map — and they are reparented
--- INTO the canvas, which is exactly why a host parented to the canvas can sit
--- under them. Both are measured, never assumed: a candidate only counts when
--- it is shown and covers at least half the canvas.
local function artCandidates(parent, width, height, exclude)
  local out = {}
  local seen = {}
  local function add(frame, label)
    if not frame or frame == parent or frame == exclude or seen[frame] then
      return
    end
    seen[frame] = true
    local w, h = frameSize(frame)
    local covers = true
    if type(width) == "number" and type(height) == "number" and w and h then
      covers = w >= width * 0.5 and h >= height * 0.5
    end
    if covers and shownState(frame) ~= false then
      out[#out + 1] = { frame = frame, label = label }
    end
  end
  add(_G.WorldMapDetailFrame, "WorldMapDetailFrame")
  add(_G.WorldMapButton, "WorldMapButton")
  local kids = call(parent, "GetChildren")
  if type(kids) == "table" then
    for i = 1, #kids do
      add(kids[i], "child " .. i)
    end
  end
  return out
end

local function parentChainText(frame, limit)
  local parts = {}
  local node = frame
  local depth = 0
  while node and depth < (limit or 6) do
    depth = depth + 1
    parts[#parts + 1] = frameFact(node)
    local up = call(node, "GetParent")
    if up == node then
      break
    end
    node = up
  end
  if #parts == 0 then
    return "absent"
  end
  return table.concat(parts, " <- ")
end

local function displayedMapID(mapFrame)
  if mapFrame and isFn(mapFrame.GetMapID) then
    local ok, id = pcall(mapFrame.GetMapID, mapFrame)
    if ok and type(id) == "number" and id > 0 then
      return id
    end
  end
  local current = callGlobal("GetCurrentMapAreaID")
  if type(current) == "number" and current > 0 then
    return current
  end
  if mapFrame then
    local ok, id = pcall(function()
      return mapFrame.mapID
    end)
    if ok and type(id) == "number" and id > 0 then
      return id
    end
  end
  return nil
end

local function mapZoom(mapFrame)
  if mapFrame and isFn(mapFrame.GetCanvasScale) then
    local ok, scale = pcall(mapFrame.GetCanvasScale, mapFrame)
    if ok and type(scale) == "number" and scale > 0.05 and scale < 100 then
      return scale
    end
  end
  return 1
end

local function getCanvas(mapFrame)
  if not mapFrame or not isFn(mapFrame.GetCanvas) then
    return nil
  end
  local ok, canvas = pcall(mapFrame.GetCanvas, mapFrame)
  if ok and canvas then
    return canvas
  end
  return nil
end

-- Ordered by "what actually pans and zooms with the displayed map".
-- Modern clients expose GetCanvas; Classic-era clients only have the legacy
-- globals, and the overlay has to draw on those instead.
local function parentCandidates()
  return {
    { label = "WorldMapFrame:GetCanvas()", frame = getCanvas(_G.WorldMapFrame) },
    { label = "WorldMapDetailFrame", frame = _G.WorldMapDetailFrame },
    { label = "WorldMapButton", frame = _G.WorldMapButton },
  }
end

--- First parent that can be measured; otherwise the first one present, so
--- the host can still be bound and a later OnSizeChanged redraws it.
--- @return frame, label, width|nil, height|nil, isCanvas
local function selectParent()
  local candidates = parentCandidates()
  local firstPresent
  for i = 1, #candidates do
    local entry = candidates[i]
    if entry.frame then
      if not firstPresent then
        firstPresent = entry
      end
      local w, h = frameSize(entry.frame)
      if w and h and w >= 2 and h >= 2 then
        return entry.frame, entry.label, w, h, i == 1
      end
    end
  end
  if firstPresent then
    return firstPresent.frame, firstPresent.label, nil, nil, firstPresent == candidates[1]
  end
  return nil
end

--- The map texture area inside a LEGACY host, when the client insets the map
--- inside a border (Classic: WorldMapButton inside WorldMapDetailFrame).
--- Measured, never assumed: an equal or larger frame contributes nothing.
--- A modern canvas already is the map texture area, so it never gets one.
local function innerMapFrame(host)
  local list = { _G.WorldMapButton, _G.WorldMapDetailFrame }
  for i = 1, #list do
    local frame = list[i]
    if frame and frame ~= host then
      local w, h = frameSize(frame)
      if w and h and w > 0 and h > 0 then
        return frame, w, h
      end
    end
  end
  return nil
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
  self._lastQueued = 0
  self._rect = nil
  self._hostSize = nil
  self._px = nil
  self._segLens = nil
  self._skipped = nil
  self._measured = false
  self._drew = false
  self._zorder = nil
  self._raisedInfo = nil
  self._why = nil
  self:ClearProbe()
  self:ReleaseVisuals()
end

function M:HookParentSize(parent)
  if not parent or self._sizedParent == parent or not isFn(parent.HookScript) then
    return
  end
  local ok = pcall(parent.HookScript, parent, "OnSizeChanged", function()
    M:Redraw()
  end)
  if ok then
    self._sizedParent = parent
  end
end

function M:EnsureHost(parent, label)
  if not parent or not isFn(CreateFrame) then
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
    self.host = host
    self.drawer = ns.LineDraw.Create()
    ns.LineDraw.BindOverlay(host, parent)
    self._hostParent = parent
  end
  self._parentLabel = label
  self:HookParentSize(parent)
  -- Put the overlay on the map's own strata, above the map texture. Frame
  -- level +3 (LineDraw.BindOverlay) can land behind map art on clients whose
  -- canvas children sit at a low level.
  local host = self.host
  local strata = call(parent, "GetFrameStrata")
  if type(strata) == "string" and isFn(host.SetFrameStrata) then
    -- Only ever raise here, never reset — the same rule as the level below.
    -- This used to set the host back to the PARENT's strata on every redraw,
    -- which dropped a host AuditAndRaise had lifted to the art's (higher)
    -- strata back to the map's MEDIUM, putting the line under the art again.
    local currentStrata = call(host, "GetFrameStrata")
    local currentRank = strataRank(currentStrata)
    local wantedRank = strataRank(strata)
    if not currentRank or not wantedRank or currentRank < wantedRank then
      pcall(host.SetFrameStrata, host, strata)
    end
  end
  local level = call(parent, "GetFrameLevel")
  if type(level) == "number" and isFn(host.SetFrameLevel) then
    -- Only ever raise here, never reset: a host already placed above the map
    -- art by AuditAndRaise must not be dropped back to canvas+10 on the next
    -- redraw (that made every redraw "raise" again and made the diag's verdict
    -- claim draw order forever).
    local current = frameLevel(host)
    if type(current) ~= "number" or current < level + 10 then
      pcall(host.SetFrameLevel, host, level + 10)
    end
  end
  return host
end

--- Measure the draw order this client actually gives the map art, and raise
--- the host above it. The old code raised the host to `parent level + 10` and
--- stopped there — a guess: on a client whose art frames are siblings of the
--- host inside the canvas (the 1.12 detail frame reparented into the canvas,
--- or the canvas detail-layer pool), the art wins whenever its level is higher,
--- and a line drawn underneath the map art is invisible with no error.
--- Nothing here is hardcoded: the art's own level is read, every candidate is
--- recorded for /nt mapdiag, and the raise only happens when it is needed.
function M:AuditAndRaise(host, parent, width, height)
  local canvasLevel = frameLevel(parent)
  local parentStrata = call(parent, "GetFrameStrata")
  local audit = {
    canvasLevel = canvasLevel,
    canvasStrata = parentStrata,
    candidates = {},
  }
  local topLevel = canvasLevel or 0
  local topStrata = parentStrata
  local topLabel = "canvas"
  local list = artCandidates(parent, width, height, host)
  for i = 1, #list do
    local entry = list[i]
    local level = frameLevel(entry.frame)
    local strata = call(entry.frame, "GetFrameStrata")
    audit.candidates[#audit.candidates + 1] = {
      label = entry.label,
      name = frameName(entry.frame),
      level = level,
      strata = strata,
      shown = shownState(entry.frame),
    }
    if type(level) == "number" and level > topLevel then
      topLevel = level
      topStrata = strata
      topLabel = entry.label
    end
  end
  audit.topLevel = topLevel
  audit.topLabel = topLabel
  audit.topStrata = topStrata

  -- Inside one strata, level wins; across strata, the strata wins.
  local wantedLevel = topLevel + 5
  local baseLevel = (canvasLevel or 0) + 3
  if wantedLevel < baseLevel then
    wantedLevel = baseLevel
  end
  local currentLevel = frameLevel(host)
  -- Never lower the frame: EnsureHost already placed it at canvas level + 10,
  -- and a lower level than that is a regression on clients with no measurable
  -- art frame.
  if type(currentLevel) == "number" and currentLevel > wantedLevel then
    wantedLevel = currentLevel
  end
  local levelBefore = currentLevel
  local setLevelWanted = isFn(host.SetFrameLevel)
    and (type(currentLevel) ~= "number" or currentLevel < wantedLevel)
  if setLevelWanted then
    pcall(host.SetFrameLevel, host, wantedLevel)
  end
  -- Measure the frame again. A raise is a fact about the FRAME, not about the
  -- call we attempted: on clients where SetFrameLevel exists but does not take
  -- effect (pcall succeeds, the level never moves) recording the attempt made
  -- the diag report the invisible-line state as fixed ("RAISED from 45 to 45",
  -- "-> above the art" with art on a higher strata). Only what the frame
  -- reads back after the call may be reported as a raise.
  local levelAfter = frameLevel(host)
  local levelRose = type(levelBefore) == "number" and type(levelAfter) == "number"
    and levelAfter > levelBefore

  local strataBefore = call(host, "GetFrameStrata")
  local strataRankBefore = strataRank(strataBefore)
  local wantStrata
  local topRank = strataRank(topStrata)
  if type(topStrata) == "string" and topRank and (not strataRankBefore or topRank > strataRankBefore) then
    wantStrata = topStrata
  elseif type(parentStrata) == "string" and strataBefore ~= parentStrata then
    -- Adopt the parent's strata only when there is nothing above it to hold:
    -- never LOWER a host that a previous redraw already raised (that dropped a
    -- HIGH host back to the map's MEDIUM on the next redraw and put the line
    -- under the art again).
    local parentRank = strataRank(parentStrata)
    if not strataRankBefore or not parentRank or strataRankBefore < parentRank then
      wantStrata = parentStrata
    end
  end
  if wantStrata and isFn(host.SetFrameStrata) then
    pcall(host.SetFrameStrata, host, wantStrata)
  end
  -- Same rule for strata: read it back, never assume the setter took effect
  -- (the diag used to print the strata it ASKED for, so a refused
  -- SetFrameStrata reported "strata=HIGH -> above the art" on a MEDIUM frame).
  local hostStrata = call(host, "GetFrameStrata")
  if type(hostStrata) ~= "string" then
    hostStrata = strataBefore -- unmeasurable: report the last measured value
  end
  local strataRose = type(hostStrata) == "string" and type(strataBefore) == "string"
    and strataRank(hostStrata) and strataRank(strataBefore)
    and strataRank(hostStrata) > strataRank(strataBefore)

  local raisedNow = levelRose or strataRose
  if raisedNow then
    -- Sticky, but recorded as HISTORY: `raisedInfo` says a raise happened,
    -- `raisedNow` says it happened on THIS redraw. The verdict must not keep
    -- claiming draw order on a redraw where the host is already on top —
    -- otherwise the geometry/colour/unknown verdicts are unreachable.
    self._raisedInfo = {
      label = topLabel,
      levelFrom = levelRose and levelBefore or nil,
      levelTo = frameLevel(host),
      strataFrom = strataRose and strataBefore or nil,
      strataTo = strataRose and hostStrata or nil,
    }
  end
  local info = self._raisedInfo
  -- `raised` stays sticky: the raise is evidence that must survive later
  -- redraws (nothing needs raising any more, but it did happen). `raisedNow`
  -- and `raisedEarlier` say WHEN, so the verdict can fall through to the next
  -- candidate instead of repeating "draw order" forever.
  local raisedEarlier = false
  if not raisedNow and type(info) == "table" then
    raisedEarlier = info.label == topLabel
      and ((info.levelTo == wantedLevel) or (info.strataTo ~= nil and info.strataTo == topStrata))
  end
  audit.hostLevel = frameLevel(host)
  audit.hostStrata = hostStrata
  audit.raised = raisedNow or raisedEarlier
  audit.raisedNow = raisedNow
  audit.raisedEarlier = raisedEarlier
  -- `and … or` would silently fall back to levelBefore when the history has no
  -- level (a strata-only raise): keep nil so the verdict picks the strata text.
  audit.raisedFrom = (type(info) == "table") and info.levelFrom or nil
  audit.raisedStrataFrom = (type(info) == "table") and info.strataFrom or nil
  audit.wantedLevel = wantedLevel
  audit.wantedStrata = wantStrata
  audit.levelRose = levelRose
  audit.strataRose = strataRose
  audit.stillBelow = nil
  if type(audit.hostLevel) == "number" and type(topLevel) == "number" then
    local hostRankNow = strataRank(hostStrata)
    local artRank = strataRank(topStrata)
    if hostRankNow and artRank and hostRankNow ~= artRank then
      -- Across strata the strata wins, whatever the level says.
      audit.stillBelow = hostRankNow < artRank
    else
      audit.stillBelow = audit.hostLevel <= topLevel
    end
  end
  self._zorder = audit
  return audit
end

function M:RequestRetry()
  if (self._retries or 0) >= RETRY_LIMIT or self._retryScheduled or not self.path then
    return
  end
  self._retries = (self._retries or 0) + 1
  if not (C_Timer and isFn(C_Timer.After)) then
    -- No timer surface: the map's own hooks (OnShow / OnMapChanged /
    -- OnSizeChanged) still fire the redraw. Nothing polls while idle.
    return
  end
  self._retryScheduled = true
  local ok = pcall(C_Timer.After, 0.05, function()
    self._retryScheduled = false
    if self.path then
      self:Redraw()
    end
  end)
  if not ok then
    self._retryScheduled = false
  end
end

function M:_redraw()
  -- Everything the diag prints about THIS redraw starts cleared: a redraw that
  -- returns early (wrong map, no host, no measurable size) must not leave the
  -- previous route's points/segments/colour looking like the current ones.
  self._lastQueued = 0
  self._why = nil
  self._px = nil
  self._segLens = nil
  self._skipped = nil
  self._measured = false
  self._drew = false
  if not self.path or #self.path < 2 then
    self._why = "no route"
    self:ReleaseVisuals()
    return
  end
  if not ns.GetDB().showWorldMap then
    self._why = "showWorldMap is off"
    self:ReleaseVisuals()
    return
  end

  local mapFrame = _G.WorldMapFrame
  local shown = displayedMapID(mapFrame)
  if shown and self.mapID and shown ~= self.mapID then
    self._why = ("the open map is %s, the route is on %s"):format(tostring(shown), tostring(self.mapID))
    self:ReleaseVisuals()
    return
  end

  local parent, label, _, _, isCanvas = selectParent()
  if not parent then
    self._why = "no map frame (canvas and legacy frames all absent)"
    self._parentLabel = nil
    self._hostSize = nil
    self:ReleaseVisuals()
    self:RequestRetry()
    return
  end

  local host = self:EnsureHost(parent, label)
  if not host or not self.drawer then
    self._why = "no overlay host (CreateFrame failed)"
    self:ReleaseVisuals()
    return
  end

  local width, height = frameSize(parent)
  if not width or not height or width < 2 or height < 2 then
    self._why = "the map frame has no measurable size"
    self._hostSize = nil
    self._rect = nil
    self._innerLabel = nil
    self:ReleaseVisuals()
    self:RequestRetry()
    return
  end
  self._retries = 0
  self._hostSize = { width = width, height = height }

  local inner, innerW, innerH
  if not isCanvas then
    inner, innerW, innerH = innerMapFrame(parent)
  end
  local rect = ns.PathGeom.MapRect(width, height, innerW, innerH)
  self._rect = rect
  self._innerLabel = inner and frameName(inner) or nil
  if not rect then
    self:ReleaseVisuals()
    return
  end

  local buf = self._segBuf or {}
  self._segBuf = buf
  local count = 0
  local geom = ns.PathGeom
  -- Measured per draw, printed by /nt mapdiag: every projected point and every
  -- decision, so "no line" can be told apart from "a 3-pixel line" and from
  -- "points that never projected".
  local px = {}
  local segLens = {}
  local skipped = {}
  for i = 1, #self.path do
    local p = self.path[i]
    if geom.IsMapPoint(p) then
      local x, y = geom.FractionToPixel(p.x, p.y, rect)
      px[i] = { x = x, y = y, fx = p.x, fy = p.y }
    else
      skipped[#skipped + 1] = "point " .. i .. " not a map point"
    end
  end
  for i = 1, #self.path - 1 do
    local a, b = self.path[i], self.path[i + 1]
    if geom.IsMapPoint(a) and geom.IsMapPoint(b) then
      local x1, y1 = geom.FractionToPixel(a.x, a.y, rect)
      local x2, y2 = geom.FractionToPixel(b.x, b.y, rect)
      if x1 and x2 then
        local dx, dy = x2 - x1, y2 - y1
        if dx * dx + dy * dy >= 0.25 then
          count = count + 1
          local seg = buf[count]
          if not seg then
            seg = {}
            buf[count] = seg
          end
          seg[1], seg[2], seg[3], seg[4] = x1, y1, x2, y2
          segLens[count] = math.sqrt(dx * dx + dy * dy)
        else
          skipped[#skipped + 1] = ("segment %d shorter than 0.5px"):format(i)
        end
      else
        skipped[#skipped + 1] = ("segment %d did not project"):format(i)
      end
    else
      skipped[#skipped + 1] = ("segment %d has a non-map point"):format(i)
    end
  end
  self._px = px
  self._segLens = segLens
  self._skipped = skipped
  self._measured = true

  -- Draw order is measured on every redraw, not assumed once: the art frames
  -- can be created (or raised) after the first draw.
  self:AuditAndRaise(host, parent, width, height)

  local r, g, b, a, stroke = ns.LineDraw.ColorWidth()
  local thickness = stroke / mapZoom(mapFrame)
  ns.LineDraw.Draw(self.drawer, host, buf, count, thickness, r, g, b, a, "ydown")
  self._drew = true
  self._lastQueued = count
  if count > 0 then
    pcall(host.Show, host)
  else
    self._why = ("none of the %d segments survived projection (%s)")
      :format(#self.path - 1, #skipped > 0 and table.concat(skipped, "; ") or "no segments in the path")
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

  -- Modern clients: a map-canvas data provider is told when to refresh.
  if not self._providerHooked
    and MapCanvasDataProviderMixin
    and isFn(CreateFromMixins)
    and isFn(mapFrame.AddDataProvider)
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

  -- Script hooks are installed whether or not a provider exists. A provider
  -- is not guaranteed to be the only thing that tells us the map opened or
  -- changed, and the map can open long after the route was set.
  if not self._scriptsHooked then
    self._scriptsHooked = true
    if isFn(mapFrame.HookScript) then
      pcall(mapFrame.HookScript, mapFrame, "OnShow", function()
        M._retries = 0
        M:Redraw()
      end)
    end
    -- Proven on this client's map frame by RXPGuides (which draws its own
    -- guide lines on WorldMapFrame:GetCanvas()).
    if isFn(hooksecurefunc) then
      pcall(hooksecurefunc, mapFrame, "OnMapChanged", function()
        M._retries = 0
        M:Redraw()
      end)
      pcall(hooksecurefunc, mapFrame, "OnCanvasScaleChanged", function()
        M._retries = 0
        M:Redraw()
      end)
    end
  end

  local events = self._events
  if events and isFn(events.RegisterEvent) then
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

-- ── /nt mapdiag ─────────────────────────────────────────────────────────────
-- One labelled line per fact; every line is built inside pcall, so a client
-- missing any of these APIs prints "absent" (or "error: ..." for that one
-- line) and never aborts the rest of the block.

local function say(text)
  local line = "NodeTrail mapdiag: " .. tostring(text)
  if type(DEFAULT_CHAT_FRAME) == "table" and isFn(DEFAULT_CHAT_FRAME.AddMessage) then
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

local function fmtMethod(frame, method)
  if not frame or not isFn(frame[method]) then
    return "absent"
  end
  return "present"
end

local function fmtFrame(frame)
  if not frame then
    return "absent"
  end
  local w, h = frameSize(frame)
  return string.format("present (%s, %sx%s)", frameName(frame), fmtNum(w), fmtNum(h))
end

--- The held objects, measured. What makes an object drawable is the geometry
--- the draw ASKED for having been recorded — not a size. A Line region's extent
--- comes from its two endpoints, so `size=0x0` on a line is a SYMPTOM, not a
--- cause: the live client printed exactly that for 12 queued segments while the
--- real defect was SetStartPoint/SetEndPoint leaving no offsets behind
--- (start=TOPLEFT(0.0,absent)). Reporting "zero-size" there sent four rounds
--- after the wrong thing, so each primitive is judged by its own contract:
---   line  : the endpoints read back where the draw put them
---   dots  : the region carries two corner anchors (its size IS the anchors)
---   other : SetWidth/SetHeight actually sized it
--- Returns human-readable defects; empty when the held objects look drawable.
local function objectDefects(self)
  local defects = {}
  local drawer = self.drawer
  local pool = drawer and drawer.pool
  if type(pool) ~= "table" or not self._drew then
    return defects
  end
  local mode = drawer.mode or "?"
  local applied = ns.LineDraw.Applied(drawer) or {}
  local used = (mode == "dots") and (applied.dots or 0) or (self._lastQueued or 0)
  if used < 1 then
    return defects
  end
  local z = self._zorder
  local label = (mode == "dots") and "dot" or "line"
  for i = 1, used do
    local d = ns.LineDraw.Describe(pool[i])
    if not d.present then
      defects[#defects + 1] = ("%s %d is absent from the pool"):format(label, i)
    else
      if d.shown == false then
        defects[#defects + 1] = ("%s %d is hidden"):format(label, i)
      end
      if type(d.alpha) == "number" and d.alpha <= 0 then
        defects[#defects + 1] = ("%s %d alpha=%s: fully transparent")
          :format(label, i, fmtNum(d.alpha, 2))
      end
      if mode == "line" then
        local hasEnds = type(d.startPoint) == "table" and type(d.stopPoint) == "table"
          and type(d.startPoint.x) == "number" and type(d.startPoint.y) == "number"
          and type(d.stopPoint.x) == "number" and type(d.stopPoint.y) == "number"
        if not hasEnds then
          defects[#defects + 1] = ("line %d did not keep its endpoints (reads start=%s end=%s after the draw): this client drops SetStartPoint/SetEndPoint")
            :format(i, ns.LineDraw.PointText(d.startPoint), ns.LineDraw.PointText(d.stopPoint))
        elseif d.startPoint.x == d.stopPoint.x and d.startPoint.y == d.stopPoint.y then
          defects[#defects + 1] = ("line %d recorded a zero-length segment (start == end)"):format(i)
        end
      elseif mode == "dots" then
        -- A dot has no meaningful width/height of its own: its area comes from
        -- the two corner anchors, so the anchors are what gets judged.
        if type(d.numPoints) == "number" then
          if d.numPoints < 2 then
            defects[#defects + 1] = ("dot %d carries %d anchor(s); a dot needs two corners to have area")
              :format(i, d.numPoints)
          end
        elseif type(d.width) == "number" and type(d.height) == "number"
          and d.width <= 0 and d.height <= 0 then
          defects[#defects + 1] = ("dot %d has no readable anchors and measures %sx%s")
            :format(i, fmtNum(d.width), fmtNum(d.height))
        end
      elseif type(d.width) == "number" and type(d.height) == "number"
        and d.width <= 0 and d.height <= 0 then
        defects[#defects + 1] = ("%s %d measures %sx%s (zero-size): the texture has no area to draw")
          :format(label, i, fmtNum(d.width), fmtNum(d.height))
      end
      -- The object's OWN draw order, only when the client exposes it. A region
      -- that inherits the host's z-order is covered by the host branches above.
      if type(d.level) == "number" and type(z) == "table" and type(z.topLevel) == "number" then
        local objRank = strataRank(d.strata)
        local artRank = strataRank(z.topStrata)
        local below
        if objRank and artRank and objRank ~= artRank then
          below = objRank < artRank
        else
          below = d.level <= z.topLevel
        end
        if below then
          defects[#defects + 1] = ("%s %d sits at level=%s strata=%s, below the art %s (level=%s strata=%s)")
            :format(label, i, fmtNum(d.level), tostring(d.strata or "absent"), tostring(z.topLabel),
              fmtNum(z.topLevel), tostring(z.topStrata or "absent"))
        end
      end
    end
  end
  return defects
end

function M:Diag()
  local mapFrame = _G.WorldMapFrame

  say("frame environment")
  fact(function()
    return string.format("WorldMapFrame: %s; type=%s; GetCanvas=%s",
      fmtFrame(mapFrame), type(mapFrame), fmtMethod(mapFrame, "GetCanvas"))
  end)
  fact(function()
    local canvas = getCanvas(mapFrame)
    if not canvas then
      return "canvas: absent (WorldMapFrame:GetCanvas() returned nothing)"
    end
    local w, h = frameSize(canvas)
    return string.format(
      "canvas: name=%s size=%sx%s scale=%s EnableMouse=%s SetClipsChildren=%s",
      frameName(canvas), fmtNum(w), fmtNum(h), fmtNum(call(canvas, "GetScale"), 3),
      fmtMethod(canvas, "EnableMouse"), fmtMethod(canvas, "SetClipsChildren"))
  end)
  fact(function()
    local shown = call(mapFrame, "GetMapID")
    local current = callGlobal("GetCurrentMapAreaID")
    local displayed = displayedMapID(mapFrame)
    local match = "n/a"
    if type(displayed) == "number" and type(self.mapID) == "number" then
      match = (displayed == self.mapID) and "yes" or "NO"
    end
    return string.format(
      "mapID: GetMapID()=%s GetCurrentMapAreaID()=%s displayed=%s route=%s match=%s",
      fmtNum(shown), fmtNum(current), fmtNum(displayed), fmtNum(self.mapID), match)
  end)

  say("legacy frames")
  fact(function()
    return "WorldMapButton: " .. fmtFrame(_G.WorldMapButton)
  end)
  fact(function()
    return "WorldMapDetailFrame: " .. fmtFrame(_G.WorldMapDetailFrame)
  end)
  fact(function()
    return "WorldMapFrame.ScrollContainer: " .. fmtFrame(mapFrame and mapFrame.ScrollContainer)
  end)
  fact(function()
    return "WorldMapFrame.BorderFrame: " .. fmtFrame(mapFrame and mapFrame.BorderFrame)
  end)

  say("overlay")
  fact(function()
    local hostW, hostH = frameSize(self.host)
    local parentW, parentH = frameSize(self._hostParent)
    return string.format(
      "MapOverlay: parent=%s host=%s host_size=%sx%s parent_size=%sx%s strata=%s level=%s",
      tostring(self._parentLabel or "none"),
      self.host and frameName(self.host) or "absent",
      fmtNum(hostW), fmtNum(hostH), fmtNum(parentW), fmtNum(parentH),
      tostring(call(self.host, "GetFrameStrata") or "absent"),
      fmtNum(call(self.host, "GetFrameLevel")))
  end)
  fact(function()
    local rect = self._rect
    if type(rect) ~= "table" then
      return "map rect: absent (not measured yet)"
    end
    return string.format("map rect: left=%s top=%s map=%sx%s (measured frame %sx%s, inset from %s)",
      fmtNum(rect.left), fmtNum(rect.top), fmtNum(rect.width), fmtNum(rect.height),
      fmtNum(self._hostSize and self._hostSize.width), fmtNum(self._hostSize and self._hostSize.height),
      tostring(self._innerLabel or "none"))
  end)
  fact(function()
    return string.format("MapOverlay: retries=%s drawError=%s",
      fmtNum(self._retries), tostring(self._drawError or "none"))
  end)
  fact(function()
    local mode = self.drawer and self.drawer.mode or "absent"
    local held = (self.drawer and self.drawer.pool and #self.drawer.pool) or 0
    return string.format("redraw: queued=%s segment(s); LineDraw mode=%s; objects held=%s",
      fmtNum(self._lastQueued or 0), tostring(mode), fmtNum(held))
  end)
  fact(function()
    -- WHY this mode was chosen, measured at detection time. The old code chose
    -- "line" on the existence of Frame:CreateLine alone.
    local drawer = self.drawer
    local cap = drawer and drawer.capability
    if type(drawer) ~= "table" then
      return "primitive: not measured yet (no drawer)"
    end
    if type(cap) ~= "table" then
      return "primitive: not measured yet (no redraw on a measurable map frame)"
    end
    return string.format("primitive: chose mode=%s; line proof: %s; texture proof: %s",
      tostring(drawer.mode or "none"),
      ns.LineDraw.LineProofText(cap.line), ns.LineDraw.TextureProofText(cap.dots))
  end)
  fact(function()
    -- The operator's measurement, repeated live: create a region exactly like
    -- the drawer's own and force its size with two corner anchors, printing
    -- GetWidth/GetHeight before and after.
    local host = self.host
    if not host then
      return "anchor probe: absent (no host frame)"
    end
    local tex = self:_probeTexture(host)
    if not tex then
      return "anchor probe: absent (the host exposes no CreateTexture)"
    end
    return "anchor probe (texture created like the route's objects): "
      .. ns.LineDraw.TextureProofText(ns.LineDraw.TextureProof(tex, host))
  end)
  fact(function()
    if self._why then
      return "last redraw decided: " .. tostring(self._why)
    end
    return "last redraw decided: drew " .. fmtNum(self._lastQueued or 0) .. " segment(s)"
  end)

  say("draw order and colour (the line is drawn, but is it visible?)")
  fact(function()
    local w, h = frameSize(self.host)
    return string.format("host: name=%s level=%s strata=%s shown=%s size=%sx%s alpha=%s",
      self.host and frameName(self.host) or "absent",
      fmtNum(frameLevel(self.host)), tostring(call(self.host, "GetFrameStrata") or "absent"),
      tostring(shownState(self.host)), fmtNum(w), fmtNum(h),
      fmtNum(call(self.host, "GetAlpha"), 2))
  end)
  fact(function()
    return "parent chain: " .. parentChainText(self.host and self._hostParent or nil)
  end)
  fact(function()
    local z = self._zorder
    if type(z) ~= "table" then
      return "z-order: not measured yet (no redraw on a measurable map frame)"
    end
    local names = {}
    for i = 1, #z.candidates do
      local c = z.candidates[i]
      names[#names + 1] = string.format("%s=%s/%s%s", c.label, tostring(c.level), tostring(c.strata),
        c.shown == false and "(hidden)" or "")
    end
    local verdict = "below the art"
    if type(z.hostLevel) == "number" and type(z.topLevel) == "number" then
      -- Same comparison that produces stillBelow: across strata the strata
      -- wins, so a level above the art on a lower strata is still "NOT above".
      local hostRankNow = strataRank(z.hostStrata)
      local artRank = strataRank(z.topStrata)
      local above
      if hostRankNow and artRank and hostRankNow ~= artRank then
        above = hostRankNow > artRank
      else
        above = z.hostLevel > z.topLevel
      end
      verdict = above and "above the art" or "NOT above the art"
    end
    local suffix = ""
    if z.stillBelow then
      -- Measured, not attempted: the setter ran (or is absent) and the frame
      -- still reads below the art. Never print "RAISED" here — the numbers
      -- come from GetFrameLevel/GetFrameStrata after the call.
      suffix = (" (raise attempted; the frame still reads level=%s strata=%s)")
        :format(fmtNum(z.hostLevel), tostring(z.hostStrata or "absent"))
    elseif z.raisedNow and type(z.raisedFrom) == "number" then
      suffix = (" (RAISED from %s to %s on this redraw)")
        :format(fmtNum(z.raisedFrom), fmtNum(z.hostLevel))
    elseif z.raisedNow then
      suffix = (" (RAISED to strata %s on this redraw)"):format(tostring(z.hostStrata or "absent"))
    elseif z.raised then
      if type(z.raisedFrom) == "number" then
        suffix = (" (RAISED from %s to %s on an earlier redraw; nothing left to raise)")
          :format(fmtNum(z.raisedFrom), fmtNum(z.hostLevel))
      else
        suffix = (" (RAISED to strata %s on an earlier redraw; nothing left to raise)")
          :format(tostring(z.hostStrata or "absent"))
      end
    end
    return string.format(
      "z-order: canvas_level=%s canvas_strata=%s candidates=%s [%s] top=%s(lvl=%s) host_level=%s strata=%s -> %s%s",
      fmtNum(z.canvasLevel), tostring(z.canvasStrata or "absent"), fmtNum(#z.candidates),
      table.concat(names, ", "), tostring(z.topLabel), fmtNum(z.topLevel),
      fmtNum(z.hostLevel), tostring(z.hostStrata or "absent"), verdict, suffix)
  end)
  fact(function()
    if not self._drew then
      return "colour: not measured on the last redraw (" .. (self._why or "no redraw has run yet") .. ")"
    end
    local applied = self.drawer and ns.LineDraw.Applied(self.drawer) or nil
    if type(applied) ~= "table" then
      return "colour: no draw recorded yet"
    end
    return string.format(
      "colour applied by the last draw: r=%s g=%s b=%s a=%s thickness=%s mode=%s segments=%s space=%s%s",
      fmtNum(applied.r, 2), fmtNum(applied.g, 2), fmtNum(applied.b, 2), fmtNum(applied.a, 2),
      fmtNum(applied.thickness, 2), tostring(applied.mode), fmtNum(applied.count), tostring(applied.space),
      type(applied.dots) == "number"
        and (" dots=%d size=%s spacing=%s"):format(applied.dots,
          fmtNum(applied.dotSize, 2), fmtNum(applied.dotSpacing, 2))
        or "")
  end)
  for i = 1, 2 do
    fact(function()
      local obj = self.drawer and self.drawer.pool and self.drawer.pool[i]
      local d = ns.LineDraw.Describe(obj)
      if not d.present then
        return ("line %d: absent (no line object held)"):format(i)
      end
      local len = "absent"
      local startText = "absent"
      local stopText = "absent"
      if not self._measured then
        -- The objects keep the endpoints of an EARLIER draw after a redraw that
        -- never reached the measurement stage (wrong map open, no host, ...).
        -- Printing those pixels next to "not measured on the last redraw"
        -- reads as if they were this redraw's geometry.
        local why = "not from the last redraw (" .. tostring(self._why or "no redraw has run yet") .. ")"
        len, startText, stopText = why, why, why
      else
        if type(d.start) == "table" and type(d.stop) == "table"
          and type(d.start[3]) == "number" and type(d.stop[3]) == "number" then
          local dx = (d.stop[3] or 0) - (d.start[3] or 0)
          local dy = (d.stop[4] or 0) - (d.start[4] or 0)
          len = fmtNum(math.sqrt(dx * dx + dy * dy), 1) .. "px"
        end
        local function pt(p)
          if type(p) ~= "table" then
            return "absent"
          end
          return string.format("%s(%s,%s)", tostring(p[1]), fmtNum(p[3], 1), fmtNum(p[4], 1))
        end
        startText, stopText = pt(d.start), pt(d.stop)
      end
      -- Measured, not assumed: an absent getter means the region has no
      -- independent size/z-order (a bare texture draws inside its parent), so
      -- that is reported as such instead of as a zero size or level 0.
      local size = "absent"
      if type(d.width) == "number" or type(d.height) == "number" then
        size = fmtNum(d.width) .. "x" .. fmtNum(d.height)
      end
      local level = "inherits the host"
      if type(d.level) == "number" then
        level = fmtNum(d.level)
      end
      local strata = "inherits the host"
      if type(d.strata) == "string" and d.strata ~= "" then
        strata = d.strata
      end
      local parent = "absent"
      local chain = "absent"
      if d.parent ~= nil then
        parent = frameName(d.parent)
        chain = parentChainText(d.parent)
      end
      local vertex = "absent"
      if type(d.vertex) == "table" then
        vertex = string.format("%s,%s,%s,%s", fmtNum(d.vertex[1], 2), fmtNum(d.vertex[2], 2),
          fmtNum(d.vertex[3], 2), fmtNum(d.vertex[4], 2))
      end
      -- The region's own contract, so the next run can say WHAT this client is
      -- holding instead of inferring it from a size of 0.
      local pointText = "absent"
      if type(d.points) == "table" then
        local parts = {}
        for k = 1, #d.points do
          parts[#parts + 1] = k .. ":" .. ns.LineDraw.PointText(d.points[k])
        end
        pointText = table.concat(parts, " ")
      end
      local methodText = "absent"
      if type(d.methods) == "table" then
        local parts = {}
        local order = { "SetPoint", "GetPoint", "SetWidth", "SetHeight", "SetSize",
          "SetRotation", "SetStartPoint", "SetEndPoint" }
        for k = 1, #order do
          local name = order[k]
          parts[#parts + 1] = name .. "=" .. (d.methods[name] and "present" or "absent")
        end
        methodText = table.concat(parts, " ")
      end
      return string.format("line %d: kind=%s shown=%s alpha=%s vertex=%s thickness=%s size=%s level=%s strata=%s parent=%s chain=%s len=%s start=%s end=%s object=%s numpoints=%s points=[%s] methods=[%s]",
        i, tostring(d.kind or "?"), tostring(d.shown), fmtNum(d.alpha, 2), vertex,
        fmtNum(d.thickness, 2), size, level, strata, parent, chain, len, startText, stopText,
        tostring(d.objectType or "absent"),
        type(d.numPoints) == "number" and fmtNum(d.numPoints) or "absent",
        pointText, methodText)
    end)
  end
  fact(function()
    local px = self._px
    if type(px) ~= "table" then
      if not self._measured then
        return "points: not measured on the last redraw (" .. (self._why or "no redraw has run yet") .. ")"
      end
      return "points: none on the last redraw"
    end
    local out = {}
    local shown = 0
    for i = 1, #px do
      local p = px[i]
      if p then
        shown = shown + 1
        if shown <= 48 then
          out[#out + 1] = string.format("#%d (%s,%s)->(%s,%s)",
            i, fmtNum(p.fx, 3), fmtNum(p.fy, 3), fmtNum(p.x, 1), fmtNum(p.y, 1))
        end
      end
    end
    local text = string.format("points: %s of %s projected", fmtNum(shown), fmtNum(#self.path or 0))
    if shown > 48 then
      text = text .. " (first 48 shown, " .. fmtNum(shown - 48) .. " more not printed)"
    end
    if #out > 0 then
      text = text .. "; " .. table.concat(out, " ")
    end
    return text
  end)
  fact(function()
    if not self._measured then
      return "segments: not measured on the last redraw (" .. (self._why or "no redraw has run yet") .. ")"
    end
    local lens = self._segLens or {}
    local names = {}
    for i = 1, #lens do
      names[#names + 1] = fmtNum(lens[i], 1)
    end
    local total = 0
    for i = 1, #lens do
      total = total + lens[i]
    end
    local text = string.format("segments: queued=%s total=%spx lengths=[%s] skipped=%s",
      fmtNum(#lens), fmtNum(total, 1), table.concat(names, ", "),
      fmtNum(#(self._skipped or {})))
    if self._skipped and #self._skipped > 0 then
      text = text .. ": " .. table.concat(self._skipped, "; ")
    end
    return text
  end)
  fact(function()
    -- The one line that names the NEXT candidate from what THIS redraw
    -- measured. A raise that already happened is history, not a verdict: once
    -- the host is above the art the verdict has to fall through to the
    -- geometry/colour/unknown candidates below.
    if not self.host then
      return "verdict: no host frame yet — nothing has been drawn on this client"
    end
    local z = self._zorder
    local history = ""
    if type(z) == "table" and z.raised then
      if type(z.raisedFrom) == "number" then
        history = (" (draw order was raised earlier: %s -> %s)")
          :format(fmtNum(z.raisedFrom), fmtNum(z.hostLevel))
      elseif type(z.raisedStrataFrom) == "string" then
        history = (" (draw order was raised earlier: strata %s -> %s)")
          :format(tostring(z.raisedStrataFrom), tostring(z.hostStrata or "absent"))
      end
    end
    if shownState(self.host) == false then
      return "verdict: the host is hidden — " .. tostring(self._why or "no reason recorded") .. history
    end
    -- MEASURED state wins over intent: this branch is checked BEFORE the
    -- "raised" one, so a client whose SetFrameLevel/SetFrameStrata exist but
    -- do nothing is reported as still broken instead of as fixed. The old
    -- order made this branch dead code whenever the setter existed.
    if type(z) == "table" and z.stillBelow then
      local whyBelow
      if not isFn(self.host.SetFrameLevel) then
        whyBelow = "this client exposes no SetFrameLevel"
      elseif z.wantedStrata and not z.strataRose then
        whyBelow = "the client did not accept a higher strata"
      else
        whyBelow = "the client did not accept a higher level"
      end
      return string.format(
        "verdict: DRAW ORDER (still below after the raise attempt) — host is measured at level=%s strata=%s, the art is %s level=%s strata=%s; %s. Next measurement: /nt mapdiag on this map, then report the two levels",
        fmtNum(z.hostLevel), tostring(z.hostStrata or "absent"), tostring(z.topLabel),
        fmtNum(z.topLevel), tostring(z.topStrata or "absent"), whyBelow)
    end
    if type(z) == "table" and z.raisedNow then
      if type(z.raisedFrom) == "number" then
        return string.format(
          "verdict: DRAW ORDER — the host sat at level %s, below %s (level %s); it was raised to %s on this redraw. Re-run /nt mapdiag on the same map to confirm host_level > top and look for the line",
          fmtNum(z.raisedFrom), tostring(z.topLabel), fmtNum(z.topLevel), fmtNum(z.hostLevel))
      end
      return string.format(
        "verdict: DRAW ORDER — %s is on strata %s while the host was on %s; the host was raised to strata %s on this redraw. Re-run /nt mapdiag on the same map to confirm host strata > art strata and look for the line",
        tostring(z.topLabel), tostring(z.topStrata or "absent"),
        tostring(z.raisedStrataFrom or "absent"), tostring(z.hostStrata or "absent"))
    end
    local total = 0
    for i = 1, #(self._segLens or {}) do
      total = total + self._segLens[i]
    end
    if (self._lastQueued or 0) < 1 then
      return "verdict: nothing queued — " .. tostring(self._why or "no reason recorded") .. history
    end
    -- The objects the segments were drawn into are measured too: a queued
    -- segment that lands in a 0x0 texture, a transparent one, or one that sits
    -- under the art is the card's other candidate, and it must be NAMED here
    -- instead of the diag falling through to "no cause found".
    local defects = objectDefects(self)
    if #defects > 0 then
      return string.format(
        "verdict: LINE OBJECT — %s queued but invisible because %s. Next measurement: /nt mapdiag again on this map and report the line 1/line 2 lines%s",
        fmtNum(self._lastQueued), table.concat(defects, "; "), history)
    end
    if total < 8 then
      return string.format(
        "verdict: GEOMETRY — the %s queued segment(s) total %spx on a %sx%s map: a dot, not a missing line. Next measurement: zoom in on the route's coordinates and screenshot%s",
        fmtNum(self._lastQueued), fmtNum(total, 1),
        fmtNum(self._rect and self._rect.width), fmtNum(self._rect and self._rect.height), history)
    end
    local applied = self.drawer and ns.LineDraw.Applied(self.drawer) or nil
    if type(applied) == "table" and type(applied.a) == "number" and applied.a <= 0 then
      return "verdict: COLOUR — the draw applied alpha " .. fmtNum(applied.a, 2)
        .. " (pathColor[4]); the line is fully transparent" .. history
    end
    -- The primitive itself, when the client DROPPED the line endpoints: that is
    -- the measured cause of "queued but nothing drawn", and it is why the route
    -- is no longer drawn with SetStartPoint/SetEndPoint.
    local capLine = self.drawer and self.drawer.capability and self.drawer.capability.line
    if type(capLine) == "table" and capLine.hasCreateLine and not capLine.took
      and type(applied) == "table" and applied.mode == "dots" then
      return string.format(
        "verdict: PRIMITIVE — this client accepted SetStartPoint/SetEndPoint and kept no geometry (reads start=%s end=%s), so mode=line could not draw anything; the route is now drawn as %s anchored dots (size=%s spacing=%s). If that is still not visible, the cause is the frame/strata/alpha path and not the line maths — run /nt mapdiag probe%s",
        ns.LineDraw.PointText(capLine.start), ns.LineDraw.PointText(capLine.stop),
        fmtNum(applied.dots), fmtNum(applied.dotSize, 2), fmtNum(applied.dotSpacing, 2), history)
    end
    return string.format(
      "verdict: no draw-order, colour or geometry cause found — %s segment(s) totalling %spx queued on a shown host at level %s. Next measurement: /nt mapdiag probe (draws a marker, a border and one diagonal into this same overlay)%s",
      fmtNum(self._lastQueued), fmtNum(total, 1), fmtNum(frameLevel(self.host)), history)
  end)

  say("route")
  fact(function()
    if not self.path or #self.path < 2 then
      return "route: none"
    end
    return string.format("route: mapID=%s points=%s",
      fmtNum(self.mapID), fmtNum(#self.path))
  end)
  fact(function()
    local ok, db = pcall(ns.GetDB)
    if not ok or type(db) ~= "table" then
      return "settings: NodeTrailDB absent"
    end
    return string.format("settings: showWorldMap=%s showMinimap=%s pathWidth=%s",
      tostring(db.showWorldMap), tostring(db.showMinimap), fmtNum(db.pathWidth))
  end)
  fact(function()
    local fn = _G.GetCVar
    if not isFn(fn) then
      return "GetCVar: absent"
    end
    local value = callGlobal("GetCVar", "lockedWindowScale")
    return "lockedWindowScale=" .. tostring(value)
  end)

  -- Minimap half, so one command covers both overlay paths.
  local minimap = ns.MinimapPath
  if type(minimap) == "table" and isFn(minimap.Diag) then
    local ok, err = pcall(minimap.Diag, minimap)
    if not ok then
      say("minimap: diag failed: " .. tostring(err))
    end
  else
    say("MinimapPath: absent (minimap overlay not loaded)")
  end
end

--- /nt mapdiag primitive <auto|line|dots|rotate> — pin the drawing primitive for
--- one redraw. This is how the next in-game run can A/B the primitives without a
--- code change: the request is only a REQUEST, and the diag prints the mode the
--- client's own measurement ended up choosing (a client that refuses the line
--- endpoints lands on dots again and says so).
function M:SetPrimitive(word)
  if not self.drawer then
    say("primitive: no drawer yet — open the map with a route first")
    return
  end
  local want = tostring(word or ""):lower():match("^%s*(.-)%s*$") or ""
  if want == "" then
    want = "auto"
  end
  if want == "auto" then
    self.drawer.disableLine = false
    self.drawer.disableDots = false
  elseif want == "line" then
    self.drawer.disableLine = false
    self.drawer.disableDots = true
  elseif want == "dots" then
    self.drawer.disableLine = true
    self.drawer.disableDots = false
  elseif want == "rotate" or want == "texcoord" then
    self.drawer.disableLine = true
    self.drawer.disableDots = true
  else
    say(("primitive: unknown '%s' (auto | line | dots | rotate)"):format(want))
    return
  end
  ns.LineDraw.Invalidate(self.drawer)
  say(("primitive: requested %s; redrawing"):format(want))
  self:Redraw()
  say(("primitive: chose mode=%s after the request; the measurement that decided it is on the 'primitive:' line of /nt mapdiag")
    :format(tostring(self.drawer and self.drawer.mode or "?")))
end

-- ── /nt mapdiag probe ───────────────────────────────────────────────────────
-- Prove the overlay is VISIBLE AT ALL before touching any line maths. Three
-- things are drawn into the SAME host with the SAME texture path the route
-- uses, and the numbers are printed so the report is checkable:
--   * a solid 40x40 marker at the first route point,
--   * a 4px border around the full canvas,
--   * one diagonal (0,0)->(width,height) through ns.LineDraw.Draw itself.
-- Which of the three you can see in game separates three different bugs that
-- look identical from outside:
--   nothing            -> frame/strata/alpha/parent (or textures draw nothing)
--   marker+border only -> the line geometry is the bug
--   all three          -> the route's own geometry is empty/degenerate
-- Off by default; `/nt mapdiag probe off` removes them.

local PROBE_MARKER = 40
local PROBE_BORDER = 4

--- One scratch texture reused by every diag run: the anchor measurement needs
--- a region created exactly like the drawer's own, and re-creating it on every
--- `/nt mapdiag` would leak one region per command.
function M:_probeTexture(host)
  if self._scratchTex and self._scratchParent == host then
    return self._scratchTex
  end
  if not host or not isFn(host.CreateTexture) then
    return nil
  end
  local ok, tex = pcall(host.CreateTexture, host, nil, "OVERLAY")
  if not ok or not tex then
    return nil
  end
  pcall(tex.Hide, tex)
  self._scratchTex = tex
  self._scratchParent = host
  return tex
end

function M:ClearProbe()
  local probe = self._probe
  self._probe = nil
  self._probeOn = false
  if type(probe) ~= "table" then
    return false
  end
  if probe.drawer then
    ns.LineDraw.Invalidate(probe.drawer)
  end
  for i = 1, #(probe.textures or {}) do
    pcall(probe.textures[i].Hide, probe.textures[i])
  end
  return true
end

function M:Probe(arg)
  local want = tostring(arg or ""):lower():match("^%s*(.-)%s*$") or ""
  -- `/nt mapdiag probe off` reaches here as "probe off": the sub-command word is
  -- part of the argument, so strip it before reading the switch.
  want = want:gsub("^probe%s*", "")
  if want == "off" or want == "hide" or want == "0" then
    if self:ClearProbe() then
      say("probe: off (marker, border and diagonal removed)")
    else
      say("probe: off (nothing was drawn)")
    end
    return
  end

  local host = self.host
  if not host then
    local parent, label = selectParent()
    if not parent then
      say("probe: no map frame to draw on (canvas and legacy frames all absent)")
      return
    end
    host = self:EnsureHost(parent, label)
  end
  if not host then
    say("probe: no overlay host (CreateFrame failed)")
    return
  end
  local width, height = frameSize(host)
  if not width or not height or width < 2 or height < 2 then
    say(("probe: the host has no measurable size (%sx%s) — nothing can be placed")
      :format(fmtNum(width), fmtNum(height)))
    return
  end

  -- Where the marker goes: the first route point, projected exactly the way
  -- the route is projected; the canvas centre when there is no route yet.
  local mx, my, where
  if self.path and #self.path >= 2 and ns.PathGeom.IsMapPoint(self.path[1]) then
    local rect = self._rect or ns.PathGeom.MapRect(width, height)
    if rect then
      mx, my = ns.PathGeom.FractionToPixel(self.path[1].x, self.path[1].y, rect)
      where = ("the first route point (%s,%s)")
        :format(fmtNum(self.path[1].x, 3), fmtNum(self.path[1].y, 3))
    end
  end
  if not mx then
    mx, my = width * 0.5, height * 0.5
    where = "the canvas centre (no route points)"
  end

  self:ClearProbe()
  local probe = { textures = {}, drawer = ns.LineDraw.Create() }
  self._probe = probe
  self._probeOn = true

  local function quad(x1, y1, x2, y2)
    if not isFn(host.CreateTexture) then
      return nil
    end
    local ok, tex = pcall(host.CreateTexture, host, nil, "OVERLAY")
    if not ok or not tex then
      return nil
    end
    probe.textures[#probe.textures + 1] = tex
    ns.LineDraw.ApplyColor(tex, 1, 1, 1, 1)
    if tex.SetDrawLayer then
      pcall(tex.SetDrawLayer, tex, "OVERLAY", 7)
    end
    pcall(tex.ClearAllPoints, tex)
    pcall(tex.SetPoint, tex, "BOTTOMLEFT", host, "TOPLEFT", x1, -y2)
    pcall(tex.SetPoint, tex, "TOPRIGHT", host, "TOPLEFT", x2, -y1)
    pcall(tex.Show, tex)
    return tex
  end

  say(("probe: host=%s %sx%s level=%s strata=%s; LineDraw mode=%s")
    :format(frameName(host), fmtNum(width), fmtNum(height),
      fmtNum(frameLevel(host)), tostring(call(host, "GetFrameStrata") or "absent"),
      tostring(self.drawer and self.drawer.mode or "absent")))
  -- A hidden host would make every element invisible for a reason that has
  -- nothing to do with the primitives, so say so and show it: the probe is an
  -- explicit diagnostic, not the route.
  if shownState(host) == false then
    pcall(host.Show, host)
    say("probe: the host was hidden — shown it for the probe")
  end

  -- 1. solid 40x40 marker at the first route point
  local half = PROBE_MARKER * 0.5
  local marker = quad(mx - half, my - half, mx + half, my + half)
  if marker then
    local mw, mh = frameSize(marker)
    say(("probe: marker %dx%d at %s -> canvas (%s,%s); BOTTOMLEFT(%s,%s) TOPRIGHT(%s,%s); measured %sx%s")
      :format(PROBE_MARKER, PROBE_MARKER, where, fmtNum(mx, 1), fmtNum(my, 1),
        fmtNum(mx - half, 1), fmtNum(-(my + half), 1),
        fmtNum(mx + half, 1), fmtNum(-(my - half), 1),
        fmtNum(mw), fmtNum(mh)))
  else
    say("probe: marker absent (the host exposes no CreateTexture)")
  end

  -- 2. 4px border around the full canvas
  local edges = {
    { "top", 0, 0, width, PROBE_BORDER },
    { "bottom", 0, height - PROBE_BORDER, width, height },
    { "left", 0, 0, PROBE_BORDER, height },
    { "right", width - PROBE_BORDER, 0, width, height },
  }
  local borderText = {}
  for i = 1, #edges do
    local e = edges[i]
    local tex = quad(e[2], e[3], e[4], e[5])
    -- NOT `tex and frameSize(tex)`: an `and` expression yields ONE value, so the
    -- height would silently read "absent" (Lua 5.1 multi-return truncation).
    local ew, eh
    if tex then
      ew, eh = frameSize(tex)
    end
    borderText[#borderText + 1] = ("%s(%s,%s)-(%s,%s)=%sx%s")
      :format(e[1], fmtNum(e[2], 1), fmtNum(e[3], 1), fmtNum(e[4], 1), fmtNum(e[5], 1),
        fmtNum(ew), fmtNum(eh))
  end
  say(("probe: border %dpx around (0,0)-(%s,%s): %s")
    :format(PROBE_BORDER, fmtNum(width, 1), fmtNum(height, 1), table.concat(borderText, " ")))

  -- 3. one diagonal through the SAME helper the route uses
  local r, g, b, a, stroke = ns.LineDraw.ColorWidth()
  local diagonal = { { 0, 0, width, height } }
  ns.LineDraw.Draw(probe.drawer, host, diagonal, 1, stroke, r, g, b, a, "ydown")
  local obj = probe.drawer.pool and probe.drawer.pool[1]
  local d = ns.LineDraw.Describe(obj)
  local applied = ns.LineDraw.Applied(probe.drawer) or {}
  say(("probe: diagonal (0,0)->(%s,%s) via LineDraw mode=%s objects=%s dots=%s; measured size=%sx%s shown=%s start=%s end=%s")
    :format(fmtNum(width, 1), fmtNum(height, 1), tostring(probe.drawer.mode),
      fmtNum(probe.drawer.pool and #probe.drawer.pool or 0),
      fmtNum(applied.dots or 0),
      type(d.width) == "number" and fmtNum(d.width) or "absent",
      type(d.height) == "number" and fmtNum(d.height) or "absent",
      tostring(d.shown), ns.LineDraw.PointText(d.start), ns.LineDraw.PointText(d.stop)))
  say("probe: report which you can SEE: marker / border / diagonal (or none); '/nt mapdiag probe off' removes them")
end

local events = CreateFrame("Frame")
M._events = events
local function onEvent(frame, event, name)
  if event == "ADDON_LOADED" and name ~= "Blizzard_WorldMap" and name ~= addonName then
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

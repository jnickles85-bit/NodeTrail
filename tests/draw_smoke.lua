-- Stubbed WoW client for the path overlays. Not loaded by the addon TOC.
local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. msg .. "\n")
  end
end

local function near(a, b, msg)
  check(type(a) == "number" and math.abs(a - b) < 0.05, (msg or "near") .. " got " .. tostring(a) .. " expected " .. tostring(b))
end

local function makeRegion()
  local r = {
    points = {},
    shown = true,
    children = {},
    color = {},
    width = 0,
    height = 0,
  }
  function r:SetParent(p) self.parent = p end
  function r:ClearAllPoints() self.points = {} end
  function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
  function r:SetStartPoint(...) self.startPoint = { ... } end
  function r:SetEndPoint(...) self.endPoint = { ... } end
  -- The real region contract: LineDraw tests the round-trip before choosing the
  -- line primitive.
  function r:GetStartPoint()
    local p = self.startPoint
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
  end
  function r:GetEndPoint()
    local p = self.endPoint
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
  end
  function r:SetTexture(path) self.texture = path end
  function r:SetVertexColor(cr, cg, cb, ca) self.vertexColor = { cr, cg, cb, ca } end
  function r:SetColorTexture(cr, cg, cb, ca) self.colorTexture = { cr, cg, cb, ca } end
  function r:SetDrawLayer() end
  function r:SetBlendMode() end
  function r:SetWidth(w) self.width = w end
  function r:SetHeight(h) self.height = h end
  function r:SetThickness(t) self.thickness = t end
  function r:SetTexCoord(...) self.texcoord = { ... } end
  function r:SetAlpha() end
  function r:SetSnapToPixelGrid() end
  function r:SetTexelSnappingBias() end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:IsShown() return self.shown end
  function r:IsVisible() return self.shown end
  function r:GetWidth()
    if self._allPoints and self._allPoints.GetWidth then
      return self._allPoints:GetWidth()
    end
    return self.width or 0
  end
  function r:GetHeight()
    if self._allPoints and self._allPoints.GetHeight then
      return self._allPoints:GetHeight()
    end
    return self.height or 0
  end
  function r:SetAllPoints(rel)
    self._allPoints = rel or self.parent
  end
  function r:SetSize(w, h) self.width, self.height = w, h end
  function r:GetScale() return self.scale or 1 end
  function r:GetFrameLevel() return self.level or 1 end
  function r:SetFrameLevel(level) self.level = level end
  function r:GetFrameStrata() return "MEDIUM" end
  function r:EnableMouse() end
  function r:EnableMouseWheel() end
  function r:SetMouseClickEnabled() end
  function r:EnableMouseMotion() end
  function r:SetPassThroughButtons() end
  function r:SetScript(name, fn) self.scripts[name] = fn end
  function r:HookScript(name, fn) self.scripts[name] = fn end
  function r:RegisterEvent(ev) self.events[ev] = true end
  function r:UnregisterAllEvents() self.events = {} end
  r.scripts = {}
  r.events = {}
  if not _G.WOW_NO_ROTATION then
    function r:SetRotation(angle) self.rotation = angle end
  end
  return r
end

local function makeFrame(parent)
  local f = makeRegion()
  f.kind = "frame"
  f.parent = parent
  f.shown = true
  function f:CreateTexture()
    local t = makeRegion()
    t.kind = "texture"
    t.parent = self
    self.children[#self.children + 1] = t
    return t
  end
  function f:CreateLine()
    if _G.WOW_NO_CREATELINE then
      error("CreateLine missing")
    end
    local line = makeRegion()
    line.kind = "line"
    line.parent = self
    self.children[#self.children + 1] = line
    return line
  end
  return f
end

function CreateFrame(kind, name, parent)
  local f = makeFrame(parent)
  f._kind = kind
  f._name = name
  if type(name) == "string" then
    _G[name] = f
  end
  return f
end

function CopyTable(t)
  local out = {}
  for k, v in pairs(t) do
    if type(v) == "table" then
      out[k] = CopyTable(v)
    else
      out[k] = v
    end
  end
  return out
end

local chat = {}
SlashCmdList = {}
DEFAULT_CHAT_FRAME = {
  AddMessage = function(_, msg) chat[#chat + 1] = msg end,
}

function CreateFromMixins(mixin)
  local obj = {}
  if type(mixin) == "table" then
    for k, v in pairs(mixin) do
      obj[k] = v
    end
  end
  return obj
end
MapCanvasDataProviderMixin = {}

local canvas = makeFrame(nil)
canvas.kind = "frame"
canvas.width = 800
canvas.height = 600

WorldMapButton = makeFrame(nil)
WorldMapButton.kind = "frame"
WorldMapButton.width = 400
WorldMapButton.height = 400

WorldMapFrame = makeFrame(nil)
WorldMapFrame.kind = "frame"
WorldMapFrame.mapID = 12
function WorldMapFrame:GetMapID()
  if self._getMapIDError then
    error("GetMapID missing")
  end
  return self.mapID
end
function WorldMapFrame:GetCanvas()
  if self._canvasError then
    error("GetCanvas missing")
  end
  return canvas
end
function WorldMapFrame:GetCanvasScale()
  return self.canvasScale or 1
end
function WorldMapFrame:AddDataProvider(provider)
  self.provider = provider
  if provider.RefreshAllData then
    provider:RefreshAllData()
  end
end
WorldMapFrame.canvasScale = 2

Minimap = makeFrame(nil)
Minimap.kind = "frame"
Minimap.width = 140
Minimap.height = 140
Minimap.shown = true
function Minimap:GetZoom() return 0 end

C_Minimap = {
  GetViewRadius = function() return 233.333 end,
}
C_Map = {
  GetBestMapForUnit = function() return 12 end,
  GetPlayerMapPosition = function()
    return {
      GetXY = function() return 0.5, 0.5 end,
    }
  end,
}
local cvars = {
  rotateMinimap = "0",
  minimapZoom = "0",
  minimapInsideZoom = "0",
}
function GetCVar(name) return cvars[name] end
function GetPlayerFacing()
  if _G.FACING_ERROR then
    error("facing secret")
  end
  return _G.PLAYER_FACING or 0
end
function GetMinimapShape() return _G.MINIMAP_SHAPE or "ROUND" end

local function worldOf(x, y)
  local width, height, left, top = 2000, 2000, 2000, 2000
  return left - width * x, top - height * y, 0
end

GatherMate2 = {
  HBD = {
    GetWorldCoordinatesFromZone = function(_, x, y) return worldOf(x, y) end,
    GetPlayerWorldPosition = function() return worldOf(0.5, 0.5) end,
    GetZoneSize = function() return 2000, 2000 end,
    GetPlayerZone = function() return 12 end,
  },
}

local function loadAddon(path)
  local chunk, err = loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. path)
  assert(chunk, err)
  chunk("MightiePack", { NodeTrail = ns })
end

local ns = {}
-- Files share one namespace, matching the WoW addon loader.
local function loadAll()
  local saved = ns
  local pkg = { NodeTrail = saved }
  loadAddon = function(path)
    local chunk, err = loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. path)
    assert(chunk, err)
    chunk("MightiePack", pkg)
  end
  loadAddon("locale/enUS.lua")
  loadAddon("Config.lua")
  loadAddon("Data/GM2.lua")
  loadAddon("Data/Recorder.lua")
  loadAddon("Data/Density.lua")
  loadAddon("Route/Cluster.lua")
  loadAddon("Route/Build.lua")
  loadAddon("UI/PathGeom.lua")
  loadAddon("UI/LineDraw.lua")
  loadAddon("UI/MapOverlay.lua")
  loadAddon("UI/MinimapPath.lua")
  loadAddon("Core.lua")
  return saved
end

ns = loadAll()
-- Slash commands are registered when the umbrella enables the module.
ns.Enable()

local function shown(frame, kind)
  local list = {}
  for _, child in ipairs(frame.children or {}) do
    if child.shown and (not kind or child.kind == kind) then
      list[#list + 1] = child
    end
  end
  return list
end

local function pointXY(point)
  -- SetStartPoint("CENTER"/"TOPLEFT", parent, rel, x, y)
  return point[4], point[5]
end

check(SlashCmdList and SlashCmdList.NODETRAIL, "slash registered")
check(SLASH_NODETRAIL2 == "/nt", "nt slash")

local route = {
  mapID = 12,
  path = {
    { x = 0.25, y = 0.5 },
    { x = 0.75, y = 0.5 },
  },
}

ns.MapOverlay:SetRoute(route)
check(ns.MapOverlay._drawError == nil, "world draw error " .. tostring(ns.MapOverlay._drawError))
check(ns.MapOverlay._providerHooked, "data provider hooked")
check(ns.MapOverlay.drawer.mode == "line", "world uses CreateLine")
check(ns.MapOverlay.host and ns.MapOverlay.host.shown, "world host shown")
local worldLines = shown(ns.MapOverlay.host, "line")
check(#worldLines == 1, "one world segment, got " .. #worldLines)
if worldLines[1] then
  local x1, y1 = pointXY(worldLines[1].startPoint)
  local x2, y2 = pointXY(worldLines[1].endPoint)
  near(x1, 200, "world x1")
  near(y1, -300, "world y1")
  near(x2, 600, "world x2")
  near(y2, -300, "world y2")
  near(worldLines[1].thickness, 1, "thickness divided by canvas scale")
  local color = worldLines[1].colorTexture
  check(color and color[1] == 1 and color[2] == 1 and color[3] == 1, "white line")
  near(color and color[4] or -1, 0.9, "alpha")
end

WorldMapFrame.mapID = 99
ns.MapOverlay:Redraw()
check(not ns.MapOverlay.host.shown, "hidden on a different map")
check(#shown(ns.MapOverlay.host, "line") == 0, "no segments on a different map")

WorldMapFrame.mapID = 12
ns.MapOverlay:Redraw()
check(#shown(ns.MapOverlay.host, "line") == 1, "restored on the route map")

ns.GetDB().showWorldMap = false
ns.MapOverlay:SetRoute(route)
check(ns.MapOverlay.path == nil, "showWorldMap false clears")
check(#shown(ns.MapOverlay.host, "line") == 0, "no world lines when disabled")
ns.GetDB().showWorldMap = true
ns.MapOverlay:SetRoute(route)
check(#shown(ns.MapOverlay.host, "line") == 1, "world lines return")

-- Texture fallbacks on the same host. The ladder is now
--   line (endpoints proven) -> dots (two-corner anchors) -> rotate -> texcoord,
-- because a client can accept SetStartPoint/EndPoint (or SetWidth) and do
-- nothing with them; the chain of anchored quads is the primitive that leaves
-- the fewest setters able to be a silent no-op.
ns.MapOverlay.drawer.disableLine = true
ns.LineDraw.Invalidate(ns.MapOverlay.drawer)
ns.MapOverlay:Redraw()
check(ns.MapOverlay.drawer.mode == "dots", "anchored-dots fallback, got "
  .. tostring(ns.MapOverlay.drawer.mode))
local dots = shown(ns.MapOverlay.host, "texture")
check(#dots > 50, "a chain of dots covers the segment, got " .. #dots)
-- t_7f6fdae4: the dot is sized in SCREEN px (3px floor) and divided by the
-- surface scale, and every dot is drawn twice (outline, then white). On this
-- canvas (scale 2) the white dot is 1.5 canvas px wide = 3 screen px.
local function isWhite(o)
  local c = o and (o.colorTexture or o.color)
  return type(c) == "table" and c[1] == 1 and c[2] == 1 and c[3] == 1
end
local whites = {}
for i = 1, #dots do
  if isWhite(dots[i]) then
    whites[#whites + 1] = dots[i]
  end
end
check(#whites > 20, "a chain of white dots covers the segment, got " .. #whites)
check(#dots == 2 * #whites, "each dot is drawn twice (outline + white), got "
  .. #dots .. " objects for " .. #whites .. " dots")
local firstDot, lastDot = whites[1], whites[#whites]
if firstDot and lastDot and type(firstDot.points) == "table"
  and #firstDot.points >= 2 and #lastDot.points >= 2 then
  -- 800x600 canvas shown at scale 2, segment (200,300) -> (600,300): the white
  -- dot is 1.5 canvas px (3 screen px) every 1.5 canvas px (3 screen px), so the
  -- first spans [199.25,200.75] and the last [599.25,600.75].
  near(firstDot.points[1][4], 199.25, "the first dot's left edge sits on the first point")
  near(firstDot.points[2][4], 200.75, "the first dot's right edge")
  near(lastDot.points[1][4], 599.25, "the last dot's left edge sits on the segment end")
  near(lastDot.points[2][4], 600.75, "the last dot's right edge")
  check(firstDot.width == 0 and firstDot.height == 0,
    "dots never call SetWidth/SetHeight — the anchors force the size")
  check(firstDot.rotation == nil, "dots never call SetRotation")
else
  check(false, "the fallback objects carry no two-corner anchors (a SetWidth/SetRotation "
    .. "texture was used instead)")
end

-- Legacy primitives stay reachable (diagnostic switches, like disableLine).
ns.MapOverlay.drawer.disableDots = true
ns.LineDraw.Invalidate(ns.MapOverlay.drawer)
ns.MapOverlay:Redraw()
check(ns.MapOverlay.drawer.mode == "rotate", "SetRotation fallback")
check(#shown(ns.MapOverlay.host, "texture") == 1, "rotated texture segment")
local rot = shown(ns.MapOverlay.host, "texture")[1]
check(rot and rot.texture == "Interface\\Buttons\\WHITE8X8", "solid white texture")
check(rot and rot.rotation == 0, "horizontal segment rotation")

WOW_NO_ROTATION = true
ns.MapOverlay.drawer.disableLine = true
ns.LineDraw.Invalidate(ns.MapOverlay.drawer)
ns.MapOverlay:Redraw()
check(ns.MapOverlay.drawer.mode == "texcoord", "SetTexCoord fallback")
local taxi = shown(ns.MapOverlay.host, "texture")
check(#taxi >= 1, "texcoord segment visible")
check(taxi[1] and taxi[1].texture == "Interface\\TaxiFrame\\UI-Taxi-Line", "taxi line texture")
check(taxi[1] and taxi[1].texcoord and #taxi[1].texcoord == 8, "eight texcoords")
WOW_NO_ROTATION = false
ns.MapOverlay.drawer.disableDots = false

-- Minimap, back on CreateLine.
local nearRoute = {
  mapID = 12,
  path = {
    { x = 0.5, y = 0.5 },
    { x = 0.52, y = 0.5 },
  },
}
ns.MinimapPath:SetRoute(nearRoute)
check(ns.MinimapPath._drawError == nil, "minimap error " .. tostring(ns.MinimapPath._drawError))
check(ns.MinimapPath.host and ns.MinimapPath.host.shown, "minimap host shown")
local mini = shown(ns.MinimapPath.host, "line")
check(#mini == 1, "nearby minimap segment, got " .. #mini)
if mini[1] then
  near(mini[1].thickness, 2, "minimap stroke uses pathWidth")
  local x1, y1 = pointXY(mini[1].startPoint)
  local x2, y2 = pointXY(mini[1].endPoint)
  near(x1, 0, "player end x")
  near(y1, 0, "player end y")
  near(y2, 0, "east end y")
  check(x2 > 5, "east end is to the right, got " .. tostring(x2))
end

local farRoute = {
  mapID = 12,
  path = {
    { x = 0.1, y = 0.1 },
    { x = 0.12, y = 0.1 },
  },
}
ns.MinimapPath:SetRoute(farRoute)
check(not ns.MinimapPath.host.shown, "far route hidden on minimap")
check(#shown(ns.MinimapPath.host, "line") == 0, "no far segments")

local crossRoute = {
  mapID = 12,
  path = {
    { x = 0.1, y = 0.5 },
    { x = 0.9, y = 0.5 },
  },
}
ns.MinimapPath:SetRoute(crossRoute)
local crossed = shown(ns.MinimapPath.host, "line")
check(#crossed == 1, "crossing segment is clipped onto the minimap")
if crossed[1] then
  local x1 = pointXY(crossed[1].startPoint)
  local x2 = pointXY(crossed[1].endPoint)
  local limit = 70 * 0.96 + 0.05
  check(math.abs(x1) <= limit and math.abs(x2) <= limit, "clipped inside the round minimap")
  check(x1 * x2 < 0, "clipped segment spans the player")
end

MINIMAP_SHAPE = "SQUARE"
local squareRoute = {
  mapID = 12,
  path = {
    { x = 0.5, y = 0.5 },
    { x = 0.614166, y = 0.5 },
  },
}
ns.MinimapPath:SetRoute(squareRoute)
local squareLine = shown(ns.MinimapPath.host, "line")[1]
check(squareLine ~= nil, "square minimap draws the segment")
if squareLine then
  local x2 = squareLine.endPoint[4]
  check(math.abs(x2) > 70 * 0.96, "square clip keeps the corner the circle would cut, got " .. tostring(x2))
end
MINIMAP_SHAPE = "ROUND"

cvars.rotateMinimap = "1"
PLAYER_FACING = math.pi / 2
ns.MinimapPath:SetRoute(nearRoute)
local turned = shown(ns.MinimapPath.host, "line")[1]
check(turned ~= nil, "rotated minimap still draws")
if turned then
  near(turned.endPoint[4], 0, "facing west puts east behind, x")
  check(turned.endPoint[5] < -5, "facing west puts east down, y " .. tostring(turned.endPoint[5]))
end
cvars.rotateMinimap = "0"
PLAYER_FACING = 0

-- Throttle: a short elapsed does not redraw; a later tick does.
local redraws = 0
local orig = ns.MinimapPath._redraw
ns.MinimapPath._redraw = function(self)
  redraws = redraws + 1
  return orig(self)
end
ns.MinimapPath:SetRoute(nearRoute)
redraws = 0
local update = ns.MinimapPath._driver.scripts.OnUpdate
check(type(update) == "function", "OnUpdate installed")
update(ns.MinimapPath._driver, 0.01)
check(redraws == 0, "short tick is throttled")
update(ns.MinimapPath._driver, 0.1)
check(redraws == 1, "throttled tick redraws")
ns.MinimapPath._driver.scripts.OnEvent(ns.MinimapPath._driver, "PLAYER_STARTED_MOVING")
check(redraws == 2, "movement redraws immediately")
ns.MinimapPath._driver.scripts.OnEvent(ns.MinimapPath._driver, "ZONE_CHANGED_NEW_AREA")
check(redraws == 3, "zone change redraws immediately")
ns.MinimapPath._redraw = orig

-- Zone-size fallback when HBD cannot convert to world yards.
local savedWorld = GatherMate2.HBD.GetWorldCoordinatesFromZone
local savedPlayer = GatherMate2.HBD.GetPlayerWorldPosition
GatherMate2.HBD.GetWorldCoordinatesFromZone = nil
GatherMate2.HBD.GetPlayerWorldPosition = nil
ns.MinimapPath:SetRoute(nearRoute)
check(ns.MinimapPath._drawError == nil, "zone fallback error " .. tostring(ns.MinimapPath._drawError))
check(#shown(ns.MinimapPath.host, "line") == 1, "zone-size fallback draws")
check(not ns.MinimapPath.useWorld, "fallback is not world mode")

GatherMate2.HBD.GetZoneSize = nil
ns.MinimapPath:SetRoute(nearRoute)
check(#shown(ns.MinimapPath.host, "line") == 1, "fraction fallback draws")
GatherMate2.HBD.GetZoneSize = function() return 2000, 2000 end
GatherMate2.HBD.GetWorldCoordinatesFromZone = savedWorld
GatherMate2.HBD.GetPlayerWorldPosition = savedPlayer

-- Missing canvas API falls back to the legacy map button and does not throw.
WorldMapFrame._canvasError = true
local okCanvas = pcall(function() ns.MapOverlay:Redraw() end)
check(okCanvas, "GetCanvas error does not escape")
check(ns.MapOverlay._hostParent == WorldMapButton, "legacy WorldMapButton parent")
check(#shown(ns.MapOverlay.host, "line") >= 1 or #shown(ns.MapOverlay.host, "texture") >= 1, "legacy map still draws")
WorldMapFrame._canvasError = false

WorldMapFrame._getMapIDError = true
local okMap = pcall(function() ns.MapOverlay:SetRoute(route) end)
check(okMap, "GetMapID error does not escape")
WorldMapFrame._getMapIDError = false
WorldMapFrame.mapID = 12
ns.MapOverlay:SetRoute(route)

FACING_ERROR = true
cvars.rotateMinimap = "1"
local okFace = pcall(function() ns.MinimapPath:SetRoute(nearRoute) end)
check(okFace, "facing error does not escape")
check(ns.MinimapPath._drawError == nil, "facing failure is handled inside redraw")
check(not ns.MinimapPath.host.shown, "unreadable facing hides the minimap path")
FACING_ERROR = false
cvars.rotateMinimap = "0"
ns.MinimapPath:SetRoute(nearRoute)
check(ns.MinimapPath.host.shown, "minimap path returns after facing works")

local savedContinent = GatherMate2.HBD.GetWorldCoordinatesFromZone
local savedContinentPlayer = GatherMate2.HBD.GetPlayerWorldPosition
GatherMate2.HBD.GetWorldCoordinatesFromZone = function(_, x, y)
  local wx, wy = worldOf(x, y)
  return wx, wy, 9
end
GatherMate2.HBD.GetPlayerWorldPosition = function()
  local wx, wy = worldOf(0.5, 0.5)
  return wx, wy, 0
end
ns.MinimapPath:SetRoute(nearRoute)
check(#shown(ns.MinimapPath.host, "line") == 0, "different continent hides minimap segments")
GatherMate2.HBD.GetWorldCoordinatesFromZone = savedContinent
GatherMate2.HBD.GetPlayerWorldPosition = savedContinentPlayer

chat = {}
SlashCmdList.NODETRAIL("help")
SlashCmdList.NODETRAIL("start")
SlashCmdList.NODETRAIL("stop")
SlashCmdList.NODETRAIL("reload")
local joined = table.concat(chat, "\n")
check(joined:find("start", 1, true) ~= nil, "help mentions start")
check(joined:find("no herbs recorded", 1, true) ~= nil, "start without recorded herbs explains how to record")
check(joined:find("route cleared", 1, true) ~= nil, "stop clears")
check(ns.MapOverlay.path == nil and ns.MinimapPath.path == nil, "stop releases both overlays")
check(not ns.MapOverlay.host.shown and not ns.MinimapPath.host.shown, "stop hides both hosts")
check(ns.MinimapPath._driver.scripts.OnUpdate == nil, "stop removes the minimap ticker")

ns.MapOverlay:Clear()
ns.MinimapPath:Clear()
check(true, "clear is repeatable")
-- Base C: /nt start draws the density path from recorded herbs (no GatherMate2 nodes needed).
time = time or os.time -- WoW global used by ns.RecordHerb
WorldMapFrame.mapID = 12
for i = 0, 11 do
  ns.RecordHerb(12, 0.3 + (i % 3) * 0.005, 0.3 + math.floor(i / 3) * 0.005, {})
  ns.RecordHerb(12, 0.7 + (i % 3) * 0.005, 0.6 + math.floor(i / 3) * 0.005, {})
end
chat = {}
SlashCmdList.NODETRAIL("start")
check(table.concat(chat, "\n"):find("route started", 1, true) ~= nil, "density start announces route")
check(ns.activeRoute and ns.activeRoute.source == "density", "default route source is density")
check(ns.MapOverlay.path ~= nil and #ns.MapOverlay.path >= 3, "density path handed to world map")
check(#shown(ns.MapOverlay.host) >= 2, "density path drawn on world map")
check(ns.MinimapPath.path ~= nil, "density path handed to minimap")
SlashCmdList.NODETRAIL("reload")
check(ns.activeRoute and ns.activeRoute.source == "density", "reload rebuilds density route")
SlashCmdList.NODETRAIL("stop")
check(ns.MapOverlay.path == nil and ns.MinimapPath.path == nil, "stop clears density route")

if failed > 0 then
  io.stderr:write(failed .. " draw smoke check(s) failed\n")
  os.exit(1)
end
print("draw_smoke: ok")

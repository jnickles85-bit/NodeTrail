-- t_7f6fdae4 — the world-map route is drawn AT the player but reads as
-- "somewhere else, across the zone", because 2.88px white dots at 0.9 alpha are
-- under 2 SCREEN pixels on a canvas shown at 0.696 scale and vanish over the
-- Barrens' tan terrain. Where the route crosses dark ground (the north edge) it
-- reads as a line — hence "there's a line up there, not here".
--
-- What this spec pins:
--   A. dot geometry is measured in SCREEN px and divided by the canvas scale
--      (the floor is at least 3 screen px, whatever the surface);
--   B. a fake canvas at scale 0.696 produces dots whose screen size is at or
--      above that floor, and the chain still spans the segment;
--   C. EVERY dot is drawn twice: a dark, larger outline object first, then the
--      white dot on top — so the route survives bright terrain, not just the
--      dark ground the map art happens to have;
--   D. /nt mapdiag prints the canvas scale, the dot size in canvas px and in
--      screen px, and the outline size;
--   E. the minimap uses the same screen floor (the two surfaces agree in
--      screen px, which is the only unit the player's eyes use).
--
-- The client here is the one measured live (Barrens, mapID 1413, c220ec7):
-- Frame:CreateLine exists and keeps no geometry, and a texture is sized only by
-- two corner anchors. Not loaded by the addon TOC.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. (msg or "check") .. "\n")
  end
end

local function near(a, b, msg, tol)
  tol = tol or 0.05
  check(type(a) == "number" and type(b) == "number" and math.abs(a - b) < tol,
    (msg or "near") .. " got " .. tostring(a) .. " expected " .. tostring(b))
end

-- ── the client: a line that lies, textures sized only by their anchors ──────
local function makeRegion(frame, kind)
  local r = {
    kind = kind,
    parent = frame,
    shown = false,
    points = {},
    w = 0,
    h = 0,
  }
  function r:SetParent(p) self.parent = p end
  function r:GetParent() return self.parent end
  function r:ClearAllPoints() self.points = {} end
  function r:SetPoint(point, rel, relPoint, x, y)
    self.points[#self.points + 1] = { point, rel, relPoint, x, y }
    if #self.points >= 2 then
      local a, b = self.points[1], self.points[2]
      self.w = math.abs((b[4] or 0) - (a[4] or 0))
      self.h = math.abs((b[5] or 0) - (a[5] or 0))
    end
  end
  function r:GetNumPoints() return #self.points end
  function r:GetPoint(i)
    local p = self.points[i]
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
  end
  function r:GetWidth() return self.w or 0 end
  function r:GetHeight() return self.h or 0 end
  function r:GetObjectType() return self.kind == "line" and "Line" or "Texture" end
  function r:SetTexture(path) self.texture = path end
  function r:SetColorTexture(cr, cg, cb, ca) self.color = { cr, cg, cb, ca } end
  function r:SetVertexColor(cr, cg, cb, ca) self.vertex = { cr, cg, cb, ca } end
  function r:SetDrawLayer(layer, sub) self.layer, self.sublevel = layer, sub end
  function r:SetBlendMode() end
  function r:SetTexCoord() end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:IsShown() return self.shown end
  function r:IsVisible() return self.shown end
  function r:GetAlpha() return 1 end
  -- NOTE: no SetWidth/SetHeight/SetSize/SetRotation — this client sizes a
  -- texture from two corner anchors only, and calling a size setter would raise.
  return r
end

local function makeFrame(name, parent)
  local f = makeRegion(nil, "frame")
  f.name = name
  f.parent = parent
  f.children = {}
  f.lines = {}
  f.level = 0
  f.strata = "MEDIUM"
  f.shown = true
  f.w, f.h = 0, 0
  function f:SetParent(p) self.parent = p end
  function f:GetParent() return self.parent end
  function f:GetName() return self.name end
  function f:GetFrameLevel() return self.level end
  function f:SetFrameLevel(l) self.level = l end
  function f:GetFrameStrata() return self.strata end
  function f:SetFrameStrata(s) self.strata = s end
  function f:GetScale() return self.scale or 1 end
  function f:IsShown() return self.shown end
  function f:IsVisible() return self.shown end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:GetAlpha() return 1 end
  function f:GetWidth() return self.w end
  function f:GetHeight() return self.h end
  function f:GetChildren() return self.children end
  function f:GetChildCount() return #self.children end
  function f:SetAllPoints(rel)
    local r = rel or self.parent
    self.allPoints = r
    if r and r.GetWidth then
      self.w = r:GetWidth()
      self.h = r:GetHeight()
    end
  end
  function f:SetScript(n, fn) self.scripts = self.scripts or {}; self.scripts[n] = fn end
  function f:GetScript(n) return (self.scripts or {})[n] end
  function f:HookScript(n, fn)
    self.hooks = self.hooks or {}
    self.hooks[n] = self.hooks[n] or {}
    table.insert(self.hooks[n], fn)
  end
  function f:RegisterEvent() end
  function f:EnableMouse() end
  function f:EnableMouseWheel() end
  function f:SetMouseClickEnabled() end
  function f:EnableMouseMotion() end
  function f:SetPassThroughButtons() end
  function f:CreateTexture()
    local t = makeRegion(self, "texture")
    table.insert(self.children, t)
    return t
  end
  function f:CreateLine(_, layer)
    -- The live client: the setters return, the getters never move.
    local line = makeRegion(self, "line")
    line.layer = layer
    line.thickness = 0
    function line:SetStartPoint(point, rel, relPoint, x, y)
      self.asked = { point, rel, relPoint, x, y }
    end
    function line:SetEndPoint(point, rel, relPoint, x, y)
      self.askedEnd = { point, rel, relPoint, x, y }
    end
    function line:GetStartPoint() return "TOPLEFT", nil, nil, 0, nil end
    function line:GetEndPoint() return "TOPLEFT", nil, nil, 0, nil end
    function line:GetWidth() return 0 end
    function line:GetHeight() return 0 end
    function line:SetThickness(t) self.thickness = t end
    function line:GetThickness() return self.thickness end
    table.insert(self.lines, line)
    table.insert(self.children, line)
    return line
  end
  if parent then
    table.insert(parent.children, f)
  end
  return f
end

function CreateFrame(kind, name, parent)
  return makeFrame(name, parent)
end

function CopyTable(t)
  local out = {}
  for k, v in pairs(t) do
    out[k] = type(v) == "table" and CopyTable(v) or v
  end
  return out
end

local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) chat[#chat + 1] = msg end }
SlashCmdList = {}

local UIParent = makeFrame("UIParent", nil)
UIParent.w, UIParent.h = 1920, 1080

-- The world map exactly as /nt mapdiag measured it: a 1002x668 canvas shown at
-- 0.696 scale (the canvas itself reports 1, the WorldMapFrame reports the zoom).
local CANVAS_SCALE = 0.696
local WorldMapFrame = makeFrame("WorldMapFrame", UIParent)
WorldMapFrame.w, WorldMapFrame.h = 1002, 668
WorldMapFrame.level = 2
_G.WorldMapFrame = WorldMapFrame

local canvas = makeFrame(nil, WorldMapFrame)
canvas.w, canvas.h = 1002, 668
canvas.level = 3
function WorldMapFrame:GetCanvas() return canvas end
function WorldMapFrame:GetMapID() return 1413 end
function WorldMapFrame:GetCanvasScale() return CANVAS_SCALE end
function GetCurrentMapAreaID() return 1413 end

-- The minimap, so section E can check the two surfaces agree in screen px.
local Minimap = makeFrame("Minimap", UIParent)
Minimap.w, Minimap.h = 140, 140
Minimap.shown = true
function Minimap:GetZoom() return 0 end
_G.Minimap = Minimap
C_Minimap = { GetViewRadius = function() return 233.333 end }
C_Map = {
  GetPlayerMapPosition = function()
    return { GetXY = function() return 0.5, 0.5 end }
  end,
}
local cvars = { rotateMinimap = "0", minimapZoom = "0" }
function GetCVar(name) return cvars[name] end
function GetPlayerFacing() return 0 end
function GetMinimapShape() return "ROUND" end

local pkg = {}
local function loadAddon(path)
  local chunk, err = loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. path)
  assert(chunk, err)
  chunk("MightiePack", pkg)
end
loadAddon("locale/enUS.lua")
loadAddon("Config.lua")
loadAddon("UI/PathGeom.lua")
loadAddon("UI/LineDraw.lua")
loadAddon("UI/MapOverlay.lua")
loadAddon("UI/MinimapPath.lua")
loadAddon("Core.lua")

local ns = pkg.NodeTrail
local LD = ns.LineDraw
local M = ns.MapOverlay
ns.Enable()
ns.GetDB().pathColor = { 1, 1, 1, 0.9 }

local function lines()
  return table.concat(chat, "\n")
end

local function lineStartingWith(text, prefix)
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local body = line:gsub("^NodeTrail mapdiag: ", "")
    if body:sub(1, #prefix) == prefix then
      return body
    end
  end
  return nil
end

-- The live route, in canvas pixels -> map fractions of the 1002x668 canvas:
-- (403.6,108.2) -> (581.6,224.5), 476.3 canvas px. 476.3 * 0.696 = 331 screen
-- px of route across the bright centre of the Barrens.
local route = {
  mapID = 1413,
  path = {
    { x = 403.6 / 1002, y = 108.2 / 668 },
    { x = 581.6 / 1002, y = 224.5 / 668 },
  },
}

-- ═══ A. dot geometry is SCREEN px, divided by the canvas scale ═════════════
local METRIC_TOL = 1e-6
if type(LD.DotMetrics) ~= "function" then
  check(false, "A: LineDraw.DotMetrics is missing — dot size is still a fixed canvas px")
else
  local m = LD.DotMetrics(2, CANVAS_SCALE)
  check(type(m) == "table", "A: DotMetrics returns a table")
  near(m.scale, CANVAS_SCALE, "A: the scale it was given is reported back", METRIC_TOL)
  near(m.pathWidth, 2, "A: pathWidth is reported", METRIC_TOL)
  check(m.screenSize >= 4 - METRIC_TOL,
    "A: the dot is at least 4 SCREEN px (got " .. tostring(m.screenSize) .. ")")
  near(m.size, m.screenSize / CANVAS_SCALE, "A: canvas px = screen px / canvas scale", 1e-9)
  check(m.outline > m.size,
    "A: the outline dot is larger than the white dot (" .. tostring(m.outline)
      .. " vs " .. tostring(m.size) .. ")")
  near(m.screenOutline - m.screenSize, 2,
    "A: the outline adds 2 screen px (a 1px rim on each side)", 1e-9)
  near(m.screenSpacing, m.screenSize * 0.4,
    "A: cores overlap by more than half their width so a diagonal of squares blends", METRIC_TOL)

  -- The floor holds on any surface: a zoomed-in canvas (scale > 1) still gets 4
  -- screen px, which means a SMALLER canvas dot.
  local zoomed = LD.DotMetrics(2, 2)
  near(zoomed.size, 2, "A: at scale 2 the canvas dot is half the screen dot", 1e-9)
  near(zoomed.screenSize, 4, "A: and still 4 screen px", 1e-9)

  -- A pathWidth above the floor is honoured in screen px, not overridden.
  local wide = LD.DotMetrics(8, 1)
  near(wide.size, 8, "A: a wide stroke is not shrunk to the floor", 1e-9)
  near(wide.screenSpacing, 8 * 0.4, "A: a wide 8px stroke spaces at 40% of the core (heavy overlap)", 1e-9)

  -- Unusable scales degrade to 1 (and never divide by zero).
  near(LD.DotMetrics(2, nil).size, 4, "A: no scale reads as 1", 1e-9)
  near(LD.DotMetrics(2, 0).size, 4, "A: scale 0 reads as 1", 1e-9)
  near(LD.DotMetrics(nil, CANVAS_SCALE).screenSize, 4,
    "A: a missing pathWidth falls back to the floor", 1e-9)
  -- The ladder's floor override, used in game to A/B the core without a deploy.
  near(LD.DotMetrics(2, CANVAS_SCALE, 6).screenSize, 6,
    "A: an explicit screen floor is honoured", 1e-9)
  near(LD.DotMetrics(2, CANVAS_SCALE, 3).screenSize, 3,
    "A: the ladder can ask for a SMALLER floor too (the old 3px, for the A/B)", 1e-9)
  near(LD.DotMetrics(4, CANVAS_SCALE, 3).screenSize, 4,
    "A: a stroke above the floor is never shrunk by it", 1e-9)
end

-- ═══ B. a real draw on a 0.696 canvas ═════════════════════════════════════
M:SetRoute(route)
check(M._drawError == nil, "B: draw error: " .. tostring(M._drawError))
check(M.drawer and M.drawer.mode == "dots",
  "B: this client draws the anchored-dot chain (mode=" .. tostring(M.drawer and M.drawer.mode) .. ")")

local pool = (M.drawer and M.drawer.pool) or {}
local applied = M.drawer and M.drawer.lastApplied or {}

-- Classify the pool: every dot is TWO objects, outline first, white second.
local function isWhite(o)
  local c = o and o.color
  return c and c[1] == 1 and c[2] == 1 and c[3] == 1
end
local function isDark(o)
  local c = o and o.color
  return c and c[1] <= 0.1 and c[2] <= 0.1 and c[3] <= 0.1 and (c[4] or 0) >= 0.9
end

local whites, outlines = {}, {}
for i = 1, #pool do
  local o = pool[i]
  if o and o.shown then
    if isWhite(o) then
      whites[#whites + 1] = i
    elseif isDark(o) then
      outlines[#outlines + 1] = i
    end
  end
end

check(#whites > 20, "B: a chain of white dots covers the segment, got " .. #whites)
check(applied.dots == #whites,
  "B: the draw recorded " .. tostring(applied.dots) .. " dots, the pool shows " .. #whites)
near(applied.dotSize, 4 / CANVAS_SCALE, "B: the recorded canvas dot size", 1e-6)
near(applied.dotScale, CANVAS_SCALE, "B: the draw recorded the scale it divided by", 1e-6)
near(applied.dotScreenSize, 4, "B: the recorded screen dot size", 1e-6)
near(applied.dotScreenOutline, 6, "B: the recorded screen outline size", 1e-6)

-- B1. every white dot renders at least 4 SCREEN px wide.
local worst = nil
for i = 1, #whites do
  local o = pool[whites[i]]
  local screen = o:GetWidth() * CANVAS_SCALE
  if not worst or screen < worst then
    worst = screen
  end
end
check(worst ~= nil and worst >= 4 - 0.01,
  "B: the narrowest white dot is still >= 4 screen px (got " .. tostring(worst) .. ")")

-- B2. the chain starts and ends on the projected points (nothing moved).
local firstDot, lastDot = pool[whites[1]], pool[whites[#whites]]
local HALF = (4 / CANVAS_SCALE) * 0.5
if firstDot and lastDot and #firstDot.points == 2 and #lastDot.points == 2 then
  near(firstDot.points[1][4], 403.6 - HALF, "B: the first dot's left edge sits on the first point", 0.05)
  near(lastDot.points[1][4], 581.6 - HALF, "B: the last dot's left edge sits on the segment end", 0.05)
  near(firstDot:GetWidth(), 2 * HALF, "B: the anchors force the white dot's width", 0.01)
else
  check(false, "B: the first and last dot do not carry two corner anchors")
end

-- ═══ C. a dark outline object is drawn before every white dot ══════════════
check(#outlines == #whites,
  "C: one outline object per white dot (outlines=" .. #outlines .. " whites=" .. #whites .. ")")
local missing, notLarger, notUnder, wrongSide = 0, 0, 0, 0
for k = 1, #whites do
  local wi = whites[k]
  local w, u = pool[wi], pool[wi - 1]
  if not isDark(u) then
    missing = missing + 1
  else
    if not (u:GetWidth() > w:GetWidth() + 0.01) then
      notLarger = notLarger + 1
    end
    -- Draw order: the outline must come FIRST. It is created first in the pool,
    -- and it carries the lower draw sublevel so a client that paints by sublevel
    -- agrees with one that paints by creation order.
    local us = u.sublevel or 7
    local ws = w.sublevel or 7
    if not (us < ws) then
      notUnder = notUnder + 1
    end
    local ucx = u.points[1] and (u.points[1][4] + u.points[2][4]) * 0.5
    local wcx = w.points[1] and (w.points[1][4] + w.points[2][4]) * 0.5
    if not (ucx and wcx and math.abs(ucx - wcx) < 0.01) then
      wrongSide = wrongSide + 1
    end
  end
end
check(missing == 0, "C: every white dot has a dark outline directly beneath it (" .. missing .. " missing)")
check(notLarger == 0, "C: every outline is larger than the dot it backs (" .. notLarger .. " not larger)")
check(notUnder == 0, "C: the outline never draws over the white dot (" .. notUnder .. " on top)")
check(wrongSide == 0, "C: the outline is centred on the same pixel as its dot (" .. wrongSide .. " off-centre)")

local whiteDot = pool[whites[1]]
check(whiteDot and whiteDot.color and math.abs(whiteDot.color[4] - 1) < 1e-9,
  "C: the white dot is painted OPAQUE (1.0), not at pathColor's 0.9 alpha (got "
    .. tostring(whiteDot and whiteDot.color and whiteDot.color[4]) .. ")")
check(applied.alphaRequested ~= nil and math.abs(applied.alphaRequested - 0.9) < 1e-9,
  "C: the alpha the settings asked for is still recorded (got "
    .. tostring(applied.alphaRequested) .. ")")
local outlineDot = pool[whites[1] - 1]
check(outlineDot and outlineDot.color and outlineDot.color[4] >= 0.9,
  "C: the outline is near-opaque so it wins over any terrain colour")

-- ═══ D. /nt mapdiag reports the scale and both sizes ═══════════════════════
chat = {}
M:Diag()
local joined = lines()
check(joined:find("error:", 1, true) == nil, "D: the diag printed no error line")
local dotsLine = lineStartingWith(joined, "dots:")
check(dotsLine ~= nil, "D: /nt mapdiag prints a dots: line (got "
  .. tostring(joined:match("dots:[^\n]*")) .. ")")
if dotsLine then
  check(dotsLine:find("canvas scale=0.696", 1, true) ~= nil,
    "D: the canvas scale it read is printed (got " .. dotsLine .. ")")
  check(dotsLine:find("canvas px", 1, true) ~= nil,
    "D: the dot size in canvas px is printed (got " .. dotsLine .. ")")
  check(dotsLine:find("4.00 screen px", 1, true) ~= nil,
    "D: the computed dot size in screen px is printed (got " .. dotsLine .. ")")
  check(dotsLine:find("outline=", 1, true) ~= nil,
    "D: the outline size is printed (got " .. dotsLine .. ")")
  check(dotsLine:find("6.00 screen px", 1, true) ~= nil,
    "D: the outline's screen size is printed (got " .. dotsLine .. ")")
end

-- ═══ E. the minimap agrees in screen px ════════════════════════════════════
local nearRoute = {
  mapID = 1413,
  path = {
    { x = 0.5, y = 0.5 },
    { x = 0.52, y = 0.5 },
  },
}
ns.MinimapPath:SetRoute(nearRoute)
check(ns.MinimapPath._drawError == nil, "E: minimap draw error: " .. tostring(ns.MinimapPath._drawError))
local miniApplied = ns.MinimapPath.drawer and ns.MinimapPath.drawer.lastApplied or {}
local miniPool = (ns.MinimapPath.drawer and ns.MinimapPath.drawer.pool) or {}
local miniWhites, miniOutlines = {}, 0
for i = 1, #miniPool do
  local o = miniPool[i]
  if o and o.shown then
    if isWhite(o) then
      miniWhites[#miniWhites + 1] = i
    elseif isDark(o) then
      miniOutlines = miniOutlines + 1
    end
  end
end
check(#miniWhites > 0, "E: the minimap draws the stretch of route that crosses it")
local miniWorst = nil
for i = 1, #miniWhites do
  local w = miniPool[miniWhites[i]]:GetWidth()
  if not miniWorst or w < miniWorst then
    miniWorst = w
  end
end
check(miniWorst ~= nil and miniWorst >= 4 - 0.01,
  "E: the minimap dot is at least 4 screen px too (got " .. tostring(miniWorst) .. ")")
check(miniOutlines == #miniWhites,
  "E: the minimap dots carry the same outline (outlines=" .. miniOutlines
    .. " whites=" .. #miniWhites .. ")")
near(miniApplied.dotScreenSize, 4, "E: and reports the same screen size", 1e-6)

if failed > 0 then
  io.stderr:write(failed .. " map dot scale check(s) failed\n")
  os.exit(1)
end
print("mapdot_scale_spec: ok")

-- t_1330d05c — THE WORLD-MAP ROUTE IS DRAWN ON A FRAME THIS CLIENT ACTUALLY
-- COMPOSITES, and its fractions are projected onto that frame's measured rect.
--
-- A controlled parent ladder on the live client proved the root cause: six
-- identical 120 px opaque red squares, differing only in parent frame and
-- texture call. The two parented to `WorldMapFrame:GetCanvas()` were invisible
-- while the same square on `WorldMapFrame` was visible. This client does not
-- composite children of the canvas, so the host has to live on WorldMapFrame
-- and the route's canvas fractions must be MAPPED onto that frame's rect.
--
-- This spec is the arithmetic behind that mapping, on a client stub with real
-- screen coordinates (y-up, bottom-left origin, like GetLeft/GetTop):
--   * PathGeom.ProjectRect — the fraction space -> host space transform, with
--     a zoomed rect and a scrolled rect, and scale mismatches;
--   * PathGeom.IntersectRect — the measured visible window;
--   * the module: host parented to WorldMapFrame, points landing on the ground
--     at two zoom levels and after a scroll, the fallback when the
--     ScrollContainer cannot be measured, and the route's fractions untouched.
--
-- Not loaded by the addon TOC.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. (msg or "check") .. "\n")
  end
end

local function near(a, b, msg)
  check(type(a) == "number" and math.abs(a - b) < 0.01,
    (msg or "near") .. " got " .. tostring(a) .. " expected " .. tostring(b))
end

-- ── client stub: frames with real screen boxes, regions with real contracts ─
local function makeRegion()
  local r = { points = {}, shown = true, color = {}, width = 0, height = 0, level = 1 }
  function r:SetParent(p) self.parent = p end
  function r:GetParent() return self.parent end
  function r:ClearAllPoints() self.points = {} end
  function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
  function r:SetStartPoint(...) self.startPoint = { ... } end
  function r:SetEndPoint(...) self.endPoint = { ... } end
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
  function r:SetTexture(p) self.texture = p end
  function r:SetVertexColor(cr, cg, cb, ca) self.vertexColor = { cr, cg, cb, ca } end
  function r:SetColorTexture(cr, cg, cb, ca) self.colorTexture = { cr, cg, cb, ca } end
  function r:SetDrawLayer() end
  function r:SetThickness(t) self.thickness = t end
  function r:SetWidth(w) self.width = w end
  function r:SetHeight(h) self.height = h end
  function r:SetSize(w, h) self.width, self.height = w, h end
  -- A frame measures the size in its box (its own units); a region measures
  -- whatever the draw sized it to. Both are real numbers, never a default.
  function r:GetWidth()
    if self.box then return self.box.width end
    return self.width or 0
  end
  function r:GetHeight()
    if self.box then return self.box.height end
    return self.height or 0
  end
  function r:GetName() return self.name end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:IsShown() return self.shown end
  function r:IsVisible() return self.shown end
  function r:GetFrameLevel() return self.level or 1 end
  function r:SetFrameLevel(l) self.level = l end
  function r:GetFrameStrata() return self.strata or "MEDIUM" end
  function r:SetFrameStrata(s) self.strata = s end
  function r:GetAlpha() return self.alpha or 1 end
  function r:EnableMouse() end
  function r:EnableMouseWheel() end
  function r:SetClipsChildren() end
  function r:SetScript(n, fn) self.scripts[n] = fn end
  function r:GetScript(n) return (self.scripts or {})[n] end
  function r:SetAllPoints(rel)
    self._allPoints = rel or self.parent
    -- A real client sizes the frame from the relative frame.
    if self._allPoints and self._allPoints.GetWidth then
      self.box = {
        left = self._allPoints.GetLeft(self._allPoints),
        top = self._allPoints.GetTop(self._allPoints),
        width = self._allPoints.GetWidth(self._allPoints),
        height = self._allPoints.GetHeight(self._allPoints),
        scale = self._allPoints.GetEffectiveScale
          and self._allPoints.GetEffectiveScale(self._allPoints) or 1,
      }
    end
  end
  function r:GetLeft() return (self.box and self.box.left) or 0 end
  function r:GetTop() return (self.box and self.box.top) or 0 end
  function r:GetEffectiveScale() return (self.box and self.box.scale) or 1 end
  function r:GetScale() return (self.box and self.box.scale) or 1 end
  function r:GetChildren() return self.children or {} end
  -- A REGION has no frame level and no strata of its own — it inherits its
  -- host's draw order and answers no GetFrameLevel. Modelling that (instead of
  -- handing a texture a level of 1) keeps the diag's verdict honest here.
  local function asRegion(kind)
    local r2 = makeRegion()
    r2.kind = kind
    r2.parent = self
    r2.GetFrameLevel, r2.SetFrameLevel = nil, nil
    r2.GetFrameStrata, r2.SetFrameStrata = nil, nil
    return r2
  end
  function r:CreateTexture()
    return asRegion("texture")
  end
  function r:CreateLine()
    return asRegion("line")
  end
  r.scripts = {}
  r.children = {}
  return r
end

function CreateFrame(kind, name, parent)
  local f = makeRegion()
  f.kind = kind
  f.name = name
  f.parent = parent
  if parent then
    table.insert(parent.children, f)
  end
  return f
end

local chat = {}
DEFAULT_CHAT_FRAME = {
  AddMessage = function(_, msg) chat[#chat + 1] = msg end,
}
SlashCmdList = {}

function CopyTable(t)
  local out = {}
  for k, v in pairs(t) do
    out[k] = type(v) == "table" and CopyTable(v) or v
  end
  return out
end

-- ── the client's map hierarchy, in SCREEN coordinates ──────────────────────
-- UIParent's bottom-left is the origin, y is up, exactly like GetLeft/GetTop.
local WMF_LEFT, WMF_TOP = 300, 900     -- WorldMapFrame's screen box
local WMF_W, WMF_H = 1002, 668
local CANVAS_W, CANVAS_H = 1002, 668   -- the map texture, in canvas px
local SCALE = 1                       -- the window scale in this model

local UIParent = makeRegion()
UIParent.name = "UIParent"
UIParent.box = { left = 0, top = 1080, width = 1920, height = 1080, scale = 1 }
_G.UIParent = UIParent

local WorldMapFrame = makeRegion()
WorldMapFrame.name = "WorldMapFrame"
WorldMapFrame.box = { left = WMF_LEFT, top = WMF_TOP, width = WMF_W, height = WMF_H, scale = SCALE }
WorldMapFrame.level = 2
_G.WorldMapFrame = WorldMapFrame

local scroll = makeRegion()
scroll.name = "WorldMapScrollContainer"
scroll.box = { left = WMF_LEFT, top = WMF_TOP, width = WMF_W, height = WMF_H, scale = SCALE }
scroll.level = 2
WorldMapFrame.ScrollContainer = scroll

local canvas = makeRegion()
canvas.name = "MapCanvas"
canvas.level = 3
WorldMapFrame.canvas = canvas

function WorldMapFrame:GetCanvas() return canvas end
function WorldMapFrame:GetMapID() return 1413 end
function WorldMapFrame:GetCanvasScale() return 1 end

--- Put the canvas where the client would put it for a zoom about the scroll
--- container's centre, plus a scroll offset. `z` scales the canvas; `shx`/`shy`
--- move it in screen px (positive shy moves the canvas UP).
local function setView(z, shx, shy)
  shx, shy = shx or 0, shy or 0
  local centreX = scroll.box.left + scroll.box.width * 0.5
  local centreTop = scroll.box.top - scroll.box.height * 0.5
  local cw, ch = CANVAS_W * z, CANVAS_H * z
  local leftScreen = centreX - cw * 0.5 + shx
  local topScreen = centreTop + ch * 0.5 + shy
  -- The canvas reports in its OWN scaled units, like the client: screen = v * z.
  canvas.box = {
    left = leftScreen / z,
    top = topScreen / z,
    width = CANVAS_W,
    height = CANVAS_H,
    scale = z,
  }
  return leftScreen, topScreen, cw, ch
end
setView(1)

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

local ns = pkg.NodeTrail
local G = ns.PathGeom
local M = ns.MapOverlay

--- Call a geometry entry point that HEAD does not have. A missing function is a
--- FAILED check, not a traceback: the spec has to report the work that was not
--- done, not crash on it.
local function geom(name, ...)
  local fn = G[name]
  if type(fn) ~= "function" then
    check(false, "PathGeom." .. name .. " is absent (the mapping it implements is missing)")
    return nil
  end
  local ok, res, why = pcall(fn, ...)
  if not ok then
    check(false, "PathGeom." .. name .. " raised: " .. tostring(res))
    return nil
  end
  return res, why
end

local function box(left, top, width, height, scale)
  return { left = left, top = top, width = width, height = height, scale = scale or 1 }
end

-- ═══ 1. ProjectRect: fraction space -> host space ═══════════════════════════
do
  -- The plain case: the host IS the map frame, so the rect starts at 0,0.
  local rect = geom("ProjectRect",
    box(300, 900, 1002, 668, 1), box(300, 900, 1002, 668, 1))
  check(type(rect) == "table", "identical boxes project to a rect")
  if type(rect) == "table" then
    near(rect.left, 0, "same box: left is 0")
    near(rect.top, 0, "same box: top is 0")
    near(rect.width, 1002, "same box: width")
    near(rect.height, 668, "same box: height")
  end

  -- A ZOOMED rect: the canvas is drawn 1.4x and centred on the same point, so
  -- its screen box is 1402.8x935.2 starting 200.4 px left of and 133.6 px above
  -- the host's own box. (Boxes here are screen rects: scale 1.)
  local zoomed = geom("ProjectRect",
    box(300, 900, 1002, 668, 1), box(99.6, 1033.6, 1402.8, 935.2, 1))
  check(type(zoomed) == "table", "a zoomed map projects to a rect")
  if type(zoomed) == "table" then
    near(zoomed.left, -200.4, "zoomed: left is off the host's left edge")
    near(zoomed.top, -133.6, "zoomed: top is above the host's top edge")
    near(zoomed.width, 1402.8, "zoomed: width grows with the canvas scale")
    near(zoomed.height, 935.2, "zoomed: height grows with the canvas scale")
  end

  -- A SCROLLED rect: same zoom, the map moved 60 px right and 40 px down.
  local scrolled = geom("ProjectRect",
    box(300, 900, 1002, 668, 1), box(159.6, 993.6, 1402.8, 935.2, 1))
  check(type(scrolled) == "table", "a scrolled map projects to a rect")
  if type(scrolled) == "table" then
    near(scrolled.left, -140.4, "scrolled: left follows the canvas")
    near(scrolled.top, -93.6, "scrolled: top follows the canvas")
    near(scrolled.width, 1402.8, "scrolled: width unchanged by scrolling")
  end

  -- The same zoom, reported the way the CLIENT reports it — in the canvas' own
  -- scaled units — must give the same rect. This is the conversion a naive
  -- implementation gets wrong: GetLeft is not a screen coordinate.
  local ownUnits = geom("ProjectRect",
    box(300, 900, 1002, 668, 1), box(159.6 / 1.4, 993.6 / 1.4, 1002, 668, 1.4))
  check(type(ownUnits) == "table", "a canvas measured in its own units projects")
  if type(ownUnits) == "table" then
    near(ownUnits.left, -140.4, "own units: left is the same rect")
    near(ownUnits.top, -93.6, "own units: top is the same rect")
    near(ownUnits.width, 1402.8, "own units: width is the same rect")
    near(ownUnits.height, 935.2, "own units: height is the same rect")
  end

  -- Scale mismatch: the host is drawn at 2x, the map at 1x. One host unit is
  -- two screen px, so a 1000 px map is 500 host units.
  local mixed = geom("ProjectRect",
    box(0, 1000, 500, 300, 2), box(100, 900, 1000, 600, 1))
  check(type(mixed) == "table", "a host at a different scale projects")
  if type(mixed) == "table" then
    near(mixed.left, 50, "mixed scale: left")
    near(mixed.top, 550, "mixed scale: top")
    near(mixed.width, 500, "mixed scale: width")
    near(mixed.height, 300, "mixed scale: height")
  end

  -- Degenerate input is refused, never divided by zero.
  check(geom("ProjectRect", box(0, 0, 100, 100, 0), box(0, 0, 100, 100, 1)) == nil,
    "a host with scale 0 is refused")
  check(geom("ProjectRect", box(0, 0, 100, 100, 1), box(0, 0, 0, 100, 1)) == nil,
    "a map with no width is refused")
  check(geom("ProjectRect", nil, box(0, 0, 100, 100, 1)) == nil,
    "a missing host box is refused")
end

-- ═══ 2. IntersectRect: the measured visible window ══════════════════════════
do
  local window = geom("IntersectRect", box(0, 0, 100, 100, 1), box(0, 0, 100, 100, 1))
  check(type(window) == "table", "identical rects intersect")
  if type(window) == "table" then
    near(window.width, 100, "identical: width")
  end

  local clipped = geom("IntersectRect", box(-140, -93, 1402.8, 935.2, 1), box(0, 0, 1002, 668, 1))
  check(type(clipped) == "table", "a zoomed map intersects the viewport")
  if type(clipped) == "table" then
    near(clipped.left, 0, "window: left is the viewport's")
    near(clipped.top, 0, "window: top is the viewport's")
    near(clipped.width, 1002, "window: width is the viewport's")
    near(clipped.height, 668, "window: height is the viewport's")
  end

  check(geom("IntersectRect", box(0, 0, 10, 10, 1), box(50, 50, 10, 10, 1)) == nil,
    "disjoint rects do not intersect")
  check(geom("IntersectRect", box(0, 0, 0, 10, 1), box(0, 0, 10, 10, 1)) == nil,
    "an empty rect does not intersect")
end

-- ═══ 3. The module: host on WorldMapFrame, fractions on the ground ════════
local ROUTE = {
  { x = 0.720, y = 0.350 },
  { x = 0.450, y = 0.430 },
}
local frozen = { { x = ROUTE[1].x, y = ROUTE[1].y }, { x = ROUTE[2].x, y = ROUTE[2].y } }

local function diag()
  chat = {}
  M:Diag()
  return table.concat(chat, "\n")
end

local function fractionsUnchanged(tag)
  check(M.path and #M.path == #frozen, tag .. ": the route still has its points")
  if not (M.path and #M.path == #frozen) then
    return
  end
  for i = 1, #frozen do
    check(M.path[i].x == frozen[i].x and M.path[i].y == frozen[i].y,
      (tag .. ": fraction %d is untouched (got %s,%s)"):format(
        i, tostring(M.path[i].x), tostring(M.path[i].y)))
  end
end

M:SetRoute({ mapID = 1413, path = ROUTE })

check(M._drawError == nil, "draw error: " .. tostring(M._drawError))
check(M.host ~= nil, "an overlay host exists")
check(M._hostParent == WorldMapFrame, "host parented to WorldMapFrame, got tostring "
  .. tostring(M._hostParent))
check(M._parentLabel == "WorldMapFrame", "parent label, got " .. tostring(M._parentLabel))
check(M._hostParent ~= canvas, "host is NOT parented to the canvas")
check(M._lastQueued == 1, "one segment queued, got " .. tostring(M._lastQueued))

do
  local m = M._mappingInfo
  check(type(m) == "table", "the mapping was recorded for the diag")
  check(type(m) == "table" and m.mode == "frame", "mapping mode is frame, got "
    .. tostring(type(m) == "table" and m.mode) .. " reason="
    .. tostring(type(m) == "table" and m.reason))
  check(type(m) == "table" and m.ground == "canvas", "fractions measured in the canvas, got "
    .. tostring(type(m) == "table" and m.ground))
  check(M._window == nil, "at default zoom the whole map rect is visible, so nothing is clipped")
end

-- Default zoom: the canvas fills the frame exactly, so the frame pixel of a
-- fraction is the canvas pixel.
do
  local px = M._px or {}
  check(type(px[1]) == "table" and type(px[2]) == "table", "both points were projected")
  if type(px[1]) == "table" and type(px[2]) == "table" then
    -- Independently computed: fraction * the map's screen rect (1002x668 at
    -- the frame's own origin), which at z=1 is fraction * 1002 / 668.
    near(px[1].cx, 0.720 * 1002, "point 1 canvas x")
    near(px[1].cy, 0.350 * 668, "point 1 canvas y")
    near(px[1].x, 0.720 * 1002, "point 1 frame x (z=1)")
    near(px[1].y, 0.350 * 668, "point 1 frame y (z=1)")
    near(px[2].x, 0.450 * 1002, "point 2 frame x (z=1)")
    near(px[2].y, 0.430 * 668, "point 2 frame y (z=1)")
    check(px[1].visible == true and px[2].visible == true,
      "both points are inside the visible map at default zoom")
  end
  local line = M.drawer and M.drawer.pool and M.drawer.pool[1]
  check(line ~= nil, "a line object exists")
  if line and line.startPoint and line.endPoint then
    near(line.startPoint[4], 0.720 * 1002, "the drawn line starts at the frame pixel (x)")
    near(line.startPoint[5], -0.350 * 668, "the drawn line starts at the frame pixel (y, from TOPLEFT)")
    near(line.endPoint[4], 0.450 * 1002, "the drawn line ends at the frame pixel (x)")
    near(line.endPoint[5], -0.430 * 668, "the drawn line ends at the frame pixel (y)")
  else
    check(false, "the line carries start/end points")
  end
end
fractionsUnchanged("default zoom")

-- ═══ 4. Zoom: the route stays on the SAME GROUND ════════════════════════════
-- The map centre is the scroll container's centre, so its frame pixel cannot
-- move whatever the zoom is. A projection that stretched the route to the
-- viewport instead of the map would move it — that is the check.
do
  local centreX = 0.5 * WMF_W            -- 501
  local centreY = 0.5 * WMF_H            -- 334
  for _, z in ipairs({ 0.7, 1, 1.4, 2 }) do
    setView(z)
    M:Redraw()
    local px = M._px or {}
    check(type(px[1]) == "table", "zoom " .. z .. ": points projected")
    if type(px[1]) == "table" then
      -- Independently computed: the canvas is centred on the scroll container,
      -- so fraction (0.5,0.5) sits at the centre at every zoom.
      near(px[1].x, centreX + (0.720 - 0.5) * 1002 * z,
        "zoom " .. z .. ": point 1 frame x")
      near(px[1].y, centreY + (0.350 - 0.5) * 668 * z,
        "zoom " .. z .. ": point 1 frame y")
      check(px[1].cx == 0.720 * 1002 and px[1].cy == 0.350 * 668,
        "zoom " .. z .. ": the CANVAS pixel of the fraction never changes")
    end
    fractionsUnchanged("zoom " .. z)
  end
end

-- A landmark at the map centre lands on the same pixel at every zoom level.
do
  local seen = {}
  for _, z in ipairs({ 0.7, 1, 1.4, 2 }) do
    setView(z)
    M:Redraw()
    local px = M._px and M._px[1]
    if type(px) == "table" then
      local c = { x = px.x + (0.5 - 0.720) * 1002 * z, y = px.y + (0.5 - 0.350) * 668 * z }
      seen[#seen + 1] = c
    end
  end
  check(#seen == 4, "the centre landmark is measurable at every zoom")
  for i = 2, #seen do
    near(seen[i].x, seen[1].x, "the map centre does not move when zoomed (x)")
    near(seen[i].y, seen[1].y, "the map centre does not move when zoomed (y)")
  end
end

-- ═══ 5. Scrolled: the same ground, moved by the scroll ═════════════════════
do
  local leftScreen, topScreen = setView(1.4, 60, -40)
  M:Redraw()
  local px = M._px and M._px[1]
  check(type(px) == "table", "scrolled: the point projected")
  if type(px) == "table" then
    -- Independently computed from the canvas' own screen rect, never from the
    -- projection under test: screen px minus the frame's own left/top edge.
    local expectX = (leftScreen + 0.720 * 1002 * 1.4) - WMF_LEFT
    local expectY = WMF_TOP - (topScreen - 0.350 * 668 * 1.4)
    near(px.x, expectX, "scrolled: frame x is the ground's frame x")
    near(px.y, expectY, "scrolled: frame y is the ground's frame y")
  end
  local m = M._mappingInfo
  check(type(m) == "table" and type(M._window) == "table",
    "a zoomed map is clipped to the measured visible window")
  if type(M._window) == "table" then
    near(M._window.left, 0, "window: left is the viewport's left edge")
    near(M._window.top, 0, "window: top is the viewport's top edge")
    near(M._window.width, 1002, "window: the viewport's width")
    near(M._window.height, 668, "window: the viewport's height")
  end
  fractionsUnchanged("scrolled")
end

-- ═══ 6. A point outside the viewport is CROPPED, not moved ══════════════════
do
  setView(2, 0, 0)
  M:SetRoute({
    mapID = 1413,
    path = { { x = 0.05, y = 0.05 }, { x = 0.95, y = 0.95 } },
  })
  local px = M._px or {}
  check(type(px[1]) == "table" and px[1].visible == false,
    "point 1 is reported out of the visible window at 2x")
  check(type(px[2]) == "table" and px[2].visible == false,
    "point 2 is reported out of the visible window at 2x")
  -- The segment still exists: it was cropped to the window, not dropped.
  check((M._lastQueued or 0) == 1, "the segment is cropped, not dropped, got "
    .. tostring(M._lastQueued))
  local lens = M._segLens or {}
  local unclipped = math.sqrt((0.9 * 1002 * 2) ^ 2 + (0.9 * 668 * 2) ^ 2)
  check(type(lens[1]) == "number" and lens[1] < unclipped,
    "the cropped segment is shorter than the unclipped one (got "
      .. tostring(lens[1]) .. ", unclipped " .. tostring(unclipped) .. ")")
  local line = M.drawer and M.drawer.pool and M.drawer.pool[1]
  if line and line.startPoint and line.endPoint then
    check(line.startPoint[4] >= -0.01 and line.startPoint[5] <= 0.01,
      "the cropped segment starts on the window's top-left corner")
  end
  setView(1)
  M:SetRoute({ mapID = 1413, path = { { x = 0.720, y = 0.350 }, { x = 0.450, y = 0.430 } } })
end

-- ═══ 7. /nt mapdiag prints the mapping it used ══════════════════════════════
do
  setView(1.4, 60, -40)
  M:Redraw()
  local joined = diag()
  for _, needle in ipairs({
    "world-map host: parent=WorldMapFrame",
    "children of the canvas are not composited on this client",
    "fractions measured in the canvas rect",
    "visible rect [left=",
  }) do
    check(joined:find(needle, 1, true) ~= nil, "mapdiag missing: " .. needle)
  end
  -- Per sampled dot: fraction, canvas pixel, frame pixel, and whether it is in
  -- the measured window. The numbers are printed, not asserted.
  check(joined:find("#1 (0.720,0.350)->(", 1, true) ~= nil,
    "mapdiag prints the fraction and the frame pixel per point")
  check(joined:find(" canvas=(", 1, true) ~= nil,
    "mapdiag prints the canvas pixel per point")
  check(joined:find(" visible=", 1, true) ~= nil,
    "mapdiag prints whether each point is inside the measured window")
  check(joined:find("clipping=yes (window left=", 1, true) ~= nil,
    "mapdiag prints the window it clips to")
  -- Which ruler GetLeft/GetTop answer on, in both readings: the in-game landmark
  -- check is read against these numbers.
  check(joined:find("ruler check: ground left=", 1, true) ~= nil,
    "mapdiag prints the two readings of the measured boxes")
  check(joined:find("read as own units: screen (", 1, true) ~= nil,
    "mapdiag names the convention the projection uses")
  check(joined:find("error:", 1, true) == nil, "mapdiag printed an error line")
  setView(1)
end

-- ═══ 8. Fallback: an unmeasurable ScrollContainer ══════════════════════════
-- The old canvas host is used and the diag SAYS SO, instead of drawing nothing.
do
  local savedGetLeft, savedGetTop = scroll.GetLeft, scroll.GetTop
  scroll.GetLeft, scroll.GetTop = nil, nil
  M:SetRoute({ mapID = 1413, path = { { x = 0.720, y = 0.350 }, { x = 0.450, y = 0.430 } } })
  check(M._drawError == nil, "fallback: no draw error: " .. tostring(M._drawError))
  check(M._hostParent == canvas, "fallback: the host goes back to the canvas, got "
    .. tostring(M._hostParent))
  local m = M._mappingInfo
  check(type(m) == "table" and m.mode == "fallback", "fallback: the mode is recorded as fallback")
  local joined = diag()
  check(joined:find("world-map host: FALLBACK to", 1, true) ~= nil,
    "fallback: the diag says the mapping fell back")
  check(joined:find("ScrollContainer rect cannot be measured", 1, true) ~= nil,
    "fallback: the diag names what could not be measured")
  check(joined:find("error:", 1, true) == nil, "fallback: the diag printed an error line")
  -- The route is still attempted on the old host rather than nothing at all.
  check((M._lastQueued or 0) == 1, "fallback: the route is still drawn, got "
    .. tostring(M._lastQueued))

  -- ...and one more pass is requested (bounded), so the route moves to
  -- WorldMapFrame the moment the map becomes measurable. Without C_Timer the
  -- map's own hooks do that, so a bounded request is all this may be.
  local scheduled = {}
  local savedAfter = C_Timer
  C_Timer = { After = function(delay, fn) scheduled[#scheduled + 1] = { delay, fn } end }
  M._mapRetries = 0
  M._mapRetryScheduled = false
  setView(1)
  M:Redraw()
  check(#scheduled == 1, "fallback: one re-measure was scheduled, got " .. #scheduled)
  local passes = 0
  while passes < 10 do
    local item = table.remove(scheduled, 1)
    if not item then
      break
    end
    passes = passes + 1
    item[2]()
  end
  check(passes == 3, "fallback: the re-measure is capped at 3 passes, ran " .. passes)
  C_Timer = savedAfter
  scroll.GetLeft, scroll.GetTop = savedGetLeft, savedGetTop
end

-- ═══ 9. Back to the frame host once the rect is measurable again ════════════
do
  setView(1)
  M:SetRoute({ mapID = 1413, path = { { x = 0.720, y = 0.350 }, { x = 0.450, y = 0.430 } } })
  check(M._hostParent == WorldMapFrame, "the host returns to WorldMapFrame, got "
    .. tostring(M._hostParent))
  check(M.host and M.host:IsShown(), "the host is shown")
  fractionsUnchanged("after the fallback round trip")
end

-- ═══ 10. A canvas zoom or pan must invalidate the drawn projection ══════════
-- The host lives on WorldMapFrame, so the route is in window pixels. A
-- zoom or pan that is not followed by a redraw leaves the circle stuck to
-- the frame while the map moves under it.
do
  check(type(M.SameCanvasView) == "function", "10: SameCanvasView is exported")
  check(M.SameCanvasView({ scale = 1, hs = 0, vs = 0, mapID = 1 },
      { scale = 1, hs = 0, vs = 0, mapID = 1 }),
    "10: identical views match")
  check(not M.SameCanvasView({ scale = 1, hs = 0 }, { scale = 1.25, hs = 0 }),
    "10: a scale change is a new view")
  check(not M.SameCanvasView({ scale = 1, hs = 0 }, { scale = 1, hs = 40 }),
    "10: a pan change is a new view")
  check(not M.SameCanvasView({ scale = 1, mapID = 1 }, { scale = 1, mapID = 2 }),
    "10: a map change is a new view")
  check(not M.SameCanvasView(nil, { scale = 1 }),
    "10: a missing sample is not the same view")

  setView(1)
  M:SetRoute({ mapID = 1413, path = { { x = 0.720, y = 0.350 }, { x = 0.450, y = 0.430 } } })
  local n = M._drawNum or 0
  M:PollCanvasView()
  check((M._drawNum or 0) == n, "10: polling an unchanged canvas does not redraw (drawNum="
    .. tostring(M._drawNum) .. ")")
  setView(2)
  M:PollCanvasView()
  check((M._drawNum or 0) > n, "10: a canvas scale/position change forces a redraw (drawNum="
    .. tostring(M._drawNum) .. " after " .. tostring(n) .. ")")
  n = M._drawNum or 0
  setView(2, 80, 0)
  M:PollCanvasView()
  check((M._drawNum or 0) > n, "10: a canvas pan forces a redraw (drawNum="
    .. tostring(M._drawNum) .. " after " .. tostring(n) .. ")")
end

-- ═══ 11. _viewHooked waits until ScrollContainer hooks are installed ══════
do
  M._viewHooked = false
  M._viewAuxHooked = false
  local saved = WorldMapFrame.ScrollContainer
  WorldMapFrame.ScrollContainer = nil
  M:TryHookMap()
  check(M._viewHooked ~= true,
    "11: _viewHooked stays unset when ScrollContainer is missing")
  local hooks = 0
  function saved:HookScript(ev, fn)
    hooks = hooks + 1
    self.scripts = self.scripts or {}
    self.scripts[ev] = fn
  end
  WorldMapFrame.ScrollContainer = saved
  M:TryHookMap()
  check(M._viewHooked == true,
    "11: _viewHooked is set only after the ScrollContainer hooks are installed")
  check(hooks >= 1, "11: ScrollContainer HookScript was called (got " .. tostring(hooks) .. ")")
end

if failed > 0 then
  io.stderr:write(failed .. " map frame projection check(s) failed\n")
  os.exit(1)
end
print("mapframe_projection_spec: ok")

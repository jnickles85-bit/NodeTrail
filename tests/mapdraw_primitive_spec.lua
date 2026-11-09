-- t_a08cb3e0 — the world-map route was "queued" and invisible, with NO error, on
-- a client whose Line primitive accepts the calls and keeps no geometry.
--
-- This stub is the live client's measured shape (Barrens, mapID 1413, build
-- c220ec7, `/nt mapdiag`), not a guess:
--
--   segments: queued=12 total=326.1px ... skipped=0
--   line 1: kind=? shown=true alpha=1.00 vertex=1.00,1.00,1.00,1.00
--           thickness=2.88 size=0x0 ... len=0.0px
--           start=TOPLEFT(0.0,absent) end=TOPLEFT(0.0,absent)
--   z-order: ... host_level=13 strata=MEDIUM -> above the art
--   colour applied by the last draw: r=1.00 g=1.00 b=1.00 a=0.90 mode=line
--
-- So the frame, z-order, alpha, colour and thickness were all correct; the
-- REGION had no geometry. The Line setters returned and the getters never
-- changed: SetStartPoint/SetEndPoint are silent no-ops on this client, and
-- LineDraw used to choose "line" on the mere existence of Frame:CreateLine.
--
-- What this spec pins:
--   1. the primitive is chosen by MEASUREMENT (endpoint round-trip), and this
--      client therefore falls back to the anchored-dot chain;
--   2. the dots are two-corner-anchored quads (no SetWidth/SetHeight/SetRotation
--      at all — this stub's textures do not even have them) that cover the
--      segment end to end;
--   3. /nt mapdiag prints the primitive proof, the region contract (type,
--      method presence, GetNumPoints, every GetPoint) and the anchor probe
--      (size before -> after two corner anchors);
--   4. /nt mapdiag probe draws a 40x40 marker at the first route point, a 4px
--      border around the canvas and one diagonal through the SAME LineDraw
--      helper, prints the numbers it drew, and is off by default.
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
  check(type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.05,
    (msg or "near") .. " got " .. tostring(a) .. " expected " .. tostring(b))
end

-- ── the client: a line that lies, a texture sized only by its anchors ──────
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
    -- A real client sizes a region from two corner anchors. This is the ONLY
    -- way this stub's textures get a size: there is no SetWidth/SetHeight.
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
  -- NOTE: no SetWidth, no SetHeight, no SetSize, no SetRotation. Calling any of
  -- them would raise, and the draw is inside a pcall — that is exactly the
  -- silent-failure shape this card is about.
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
    line.asked = nil
    line.askedEnd = nil
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

local WorldMapFrame = makeFrame("WorldMapFrame", UIParent)
WorldMapFrame.w, WorldMapFrame.h = 1002, 668
WorldMapFrame.level = 2
_G.WorldMapFrame = WorldMapFrame

local canvas = makeFrame(nil, WorldMapFrame)
canvas.w, canvas.h = 1002, 668
canvas.level = 3
function WorldMapFrame:GetCanvas() return canvas end
function WorldMapFrame:GetMapID() return 1413 end
function WorldMapFrame:GetCanvasScale() return 1 end
function GetCurrentMapAreaID() return 1413 end

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
loadAddon("Core.lua")

local ns = pkg.NodeTrail
local M = ns.MapOverlay
ns.Enable()

local function lineStartingWith(text, prefix)
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local body = line:gsub("^NodeTrail mapdiag: ", "")
    if body:sub(1, #prefix) == prefix then
      return body
    end
  end
  return nil
end

-- The route whose 12 segments were queued and invisible. Three points is
-- enough to produce two segments with different lengths and directions.
local route = {
  mapID = 1413,
  path = {
    { x = 0.2, y = 0.2 },
    { x = 0.4, y = 0.2 },
    { x = 0.4, y = 0.4 },
  },
}

-- ═══ 0. the probe is OFF by default ════════════════════════════════════════
check(M._probe == nil and M._probeOn == nil, "0: no probe exists before it is asked for")
M:Diag()
check(M._probe == nil, "0: /nt mapdiag alone does not draw the probe")

-- ═══ 0b. the pure planner: coverage, endpoints, and the allocation cap ════
local LD = ns.LineDraw
if type(LD.DotPlan) ~= "function" or type(LD.PlanDots) ~= "function"
  or type(LD.DotMetrics) ~= "function" then
  -- Older builds have no anchored-dot planner at all; report it instead of
  -- aborting the whole spec so the FAIL count stays meaningful.
  check(false, "0b: LineDraw.DotMetrics/DotPlan/PlanDots are missing")
else
  -- t_7f6fdae4 / t_60e6e825: the dot is sized in SCREEN px (a 4px floor) and
  -- divided by the surface scale. At scale 1 that is a 4px dot, spaced by its
  -- own width.
  local m = LD.DotMetrics(2, 1)
  local cover = LD.DotPlan(400, m.size, m.spacing)
  check(cover.count == cover.steps + 1, "0b: both endpoints of the segment are drawn")
  near(cover.spacing, 6, "0b: a 2px stroke is spaced 6px — the rim width, one px clear of the next core")
  near(cover.size, 4, "0b: the dot is 4 screen px, so the spacing leaves no hole")
  check(cover.steps * cover.spacing >= 400, "0b: the chain spans the segment")
  check((cover.steps - 1) * cover.spacing < 400, "0b: no more dots than the length needs")
  local zero = LD.DotPlan(0, m.size, m.spacing)
  check(zero.count == 0 and zero.steps == 0, "0b: a zero-length segment plans no dots")

  local big = {}
  for i = 1, 20 do
    big[i] = { 0, 0, 1000, 0 }
  end
  local plans, total = LD.PlanDots(big, 20, m)
  check(total <= 1200 * 1.05, "0b: the plan respects the allocation cap (got " .. tostring(total) .. ")")
  check(plans[1].spacing > 3, "0b: the cap widens the spacing instead of dropping segments")
  near(plans[1].size / plans[1].spacing, m.size / m.spacing,
    "0b: size and spacing scale together, so the stroke stays continuous")
end

-- ═══ A. the primitive is chosen by measurement, not by existence ══════════
M:SetRoute(route)
check(M._drawError == nil, "A: draw error: " .. tostring(M._drawError))
check(M.host ~= nil, "A: an overlay host was created")
check(M._hostParent == canvas, "A: host parented to WorldMapFrame:GetCanvas()")
check(#M.host.lines >= 1,
  "A: Frame:CreateLine exists on this client, so the line primitive was tried")
check(M.drawer.mode ~= "line",
  "A: the line primitive must not be chosen when the endpoints do not round-trip (mode="
    .. tostring(M.drawer.mode) .. ")")
check(M.drawer.mode == "dots",
  "A: falls back to the anchored-dot chain (mode=" .. tostring(M.drawer.mode) .. ")")
check(M.drawer.capability and M.drawer.capability.line
  and M.drawer.capability.line.took == false,
  "A: the failed line proof is recorded for the diag")
check(M._lastQueued == 2, "A: two segments queued, got " .. tostring(M._lastQueued))
check(M.host:IsShown(), "A: the host is shown")

-- ═══ B. the dots are two-corner-anchored quads that cover the segment ═════
local function isWhiteDot(o)
  local c = o and o.color
  return c ~= nil and c[1] == 1 and c[2] == 1 and c[3] == 1
end
local textures = {}
local whiteDots = {}
for i = 1, #M.host.children do
  local child = M.host.children[i]
  if child.kind == "texture" and child.shown then
    textures[#textures + 1] = child
    if isWhiteDot(child) then
      whiteDots[#whiteDots + 1] = child
    end
  end
end
-- t_7f6fdae4: every dot is two regions — a dark outline under a white dot — so
-- the chain is half as many WHITE dots as objects.
check(#whiteDots > 20, "B: a chain of white dots was created, got " .. #whiteDots)
check(#textures == 2 * #whiteDots,
  "B: each dot is drawn twice (outline + white), objects=" .. #textures
    .. " dots=" .. #whiteDots)

-- Segment 1: (0.2,0.2) -> (0.4,0.2) on a 1002x668 canvas = (200.4,133.6) ->
-- (400.8,133.6). At scale 1 the dot is the 4px screen floor, so the first dot
-- spans [198.4,202.4] x [131.6,135.6] and the last one sits on the second point.
local HALF = 2
local first = whiteDots[1]
check(first ~= nil, "B: the first dot exists")
if first then
  check(#first.points == 2, "B: a dot carries exactly two corner anchors, got "
    .. tostring(#first.points))
  near(first.points[1][4], 200.4 - HALF, "B: first dot BOTTOMLEFT x (left edge of the first point)")
  near(first.points[1][5], -(133.6 + HALF), "B: first dot BOTTOMLEFT y (canvas y flips for TOPLEFT)")
  near(first.points[2][4], 200.4 + HALF, "B: first dot TOPRIGHT x")
  near(first.points[2][5], -(133.6 - HALF), "B: first dot TOPRIGHT y")
  near(first:GetWidth(), 2 * HALF, "B: the anchors force the dot's width")
  near(first:GetHeight(), 2 * HALF, "B: the anchors force the dot's height")
  check(first.color and first.color[1] == 1 and first.color[2] == 1 and first.color[3] == 1,
    "B: the dot is solid white through the route's colour path")
  near(first.color and first.color[4] or -1, 1, "B: the dot is painted opaque (t_60e6e825: 4 screen px at alpha 1, not 0.9)")
  check(first.rotation == nil, "B: no SetRotation on a dot")
  near(first.sublevel, 7, "B: the white dot is drawn on the top sublevel")
  -- The dark outline underneath it: larger, and drawn first.
  local under
  for i = 1, #M.host.children do
    if M.host.children[i] == first then
      under = M.host.children[i - 1]
      break
    end
  end
  check(under ~= nil and under.color and under.color[1] <= 0.1,
    "B: the object drawn directly before the first white dot is the dark outline")
  check(under ~= nil and under:GetWidth() > first:GetWidth(),
    "B: the outline is larger than the white dot it backs")
  check(under ~= nil and (under.sublevel or 7) < 7,
    "B: the outline sits on a lower sublevel than the white dot")
end

-- Every white dot sits on its segment, spaced ~6px apart (the rim width), and the
-- chain reaches
-- the second point.
local seg1 = {}
for i = 1, #whiteDots do
  local t = whiteDots[i]
  if t.points[1] and math.abs(t.points[1][5] + (133.6 + HALF)) <= 0.05 then
    seg1[#seg1 + 1] = t
  end
end
check(#seg1 > 20, "B: segment 1 has a dot chain, got " .. #seg1)
local last = seg1[#seg1]
if last then
  near(last.points[1][4], 400.8 - HALF, "B: the chain ends on the segment's second point")
end
if #seg1 >= 2 then
  local gap = seg1[2].points[1][4] - seg1[1].points[1][4]
  -- The gap is the segment's length divided into whole steps, so it lands just
  -- under the 6px pitch; what matters is that it stays at or above the rim
  -- width's clearance (5 = rim 6 minus the 1px a rim reaches short of a core).
  check(gap > 5.5 and gap <= 6.05,
    "B: dots are spaced by the rim width, ~6px (one px clear of the next core), got " .. tostring(gap))
end

-- A dot is drawn without any size setter: the stub only has anchors.
local probeObj = M.drawer.pool[1]
check(probeObj ~= nil and type(probeObj.SetWidth) == "nil",
  "B: the draw object has no SetWidth — the size comes from the anchors alone")

-- ═══ C. the diag prints the primitive proof and the region contract ═══════
chat = {}
M:Diag()
local joined = table.concat(chat, "\n")
check(joined:find("primitive: chose mode=dots", 1, true) ~= nil,
  "C: the diag names the chosen primitive (got " .. tostring(joined:match("primitive:[^\n]*")) .. ")")
check(joined:find("line proof: object=Line", 1, true) ~= nil,
  "C: the diag names GetObjectType of the object CreateLine returned (got "
    .. tostring(joined:match("primitive:[^\n]*")) .. ")")
check(joined:find("start=TOPLEFT(0.0,absent) end=TOPLEFT(0.0,absent)", 1, true) ~= nil,
  "C: the diag prints the endpoint round-trip the client failed "
    .. "(got " .. tostring(joined:match("primitive:[^\n]*")) .. ")")
check(joined:find("DROPPED", 1, true) ~= nil,
  "C: the failed line proof is labelled")
check(joined:find("anchor probe (texture created like the route's objects):", 1, true) ~= nil,
  "C: the diag runs the two-corner anchor probe")
check(joined:find("two corner anchors -> 64x8 points=2", 1, true) ~= nil,
  "C: the anchor probe prints the size AFTER two corner anchors (got "
    .. tostring(joined:match("anchor probe[^\n]*")) .. ")")
check(joined:find("SetWidth=absent SetHeight=absent", 1, true) ~= nil,
  "C: the anchor probe lists which setters the texture has (got "
    .. tostring(joined:match("anchor probe[^\n]*")) .. ")")
check(joined:find("redraw: queued=2 segment(s); LineDraw mode=dots", 1, true) ~= nil,
  "C: the redraw line counts SEGMENTS and names the primitive")
check(joined:find("object=Texture", 1, true) ~= nil,
  "C: the held object's GetObjectType is printed")
check(joined:find("numpoints=2 points=[1:BOTTOMLEFT(", 1, true) ~= nil,
  "C: every anchor of the held object is printed (got "
    .. tostring(joined:match("line 1:[^\n]*")) .. ")")
check(joined:find("points=[1:BOTTOMLEFT(", 1, true) ~= nil,
  "C: the anchors are printed with their point names")
check(joined:find("methods=[SetPoint=present GetPoint=present SetWidth=absent", 1, true) ~= nil,
  "C: the setters the region implements are printed")
-- A dot with two anchors is drawable; it must not be reported as the cause.
local verdict = lineStartingWith(joined, "verdict:")
check(verdict and verdict:find("LINE OBJECT", 1, true) == nil,
  "C: two-anchored dots are not blamed (got " .. tostring(verdict) .. ")")
-- What IS named: the primitive the client dropped, with the numbers it read.
check(verdict and verdict:find("verdict: PRIMITIVE", 1, true) ~= nil,
  "C: the verdict names the dropped line primitive as the measured cause (got "
    .. tostring(verdict) .. ")")
check(verdict and verdict:find("kept no geometry (reads start=TOPLEFT(0.0,absent) end=TOPLEFT(0.0,absent))", 1, true) ~= nil,
  "C: the verdict quotes the endpoint read-back (got " .. tostring(verdict) .. ")")
check(verdict and verdict:find("anchored dots (size=4.00 spacing=6.00)", 1, true) ~= nil,
  "C: the verdict says how the route is drawn instead (got " .. tostring(verdict) .. ")")
check(joined:find("error:", 1, true) == nil, "C: the diag printed no error line")

-- ═══ D. /nt mapdiag probe draws the three elements and prints the numbers ═
chat = {}
SlashCmdList.NODETRAIL("mapdiag probe")
local probeText = table.concat(chat, "\n")
check(M._probe ~= nil and M._probeOn == true, "D: the probe is drawn when asked")
check(probeText:find("probe: host=<unnamed> 1002x668", 1, true) ~= nil,
  "D: the probe names the host it drew on (got "
    .. tostring(probeText:match("probe: host[^\n]*")) .. ")")
check(probeText:find("probe: marker 40x40 at the first route point (0.200,0.200)", 1, true) ~= nil,
  "D: the marker is placed at the first route point (got "
    .. tostring(probeText:match("probe: marker[^\n]*")) .. ")")
check(probeText:find("canvas (200.4,133.6)", 1, true) ~= nil,
  "D: the marker prints the canvas pixels it used")
check(probeText:find("measured 40x40", 1, true) ~= nil,
  "D: the marker prints its measured size")
check(probeText:find("probe: border 4px around (0,0)-(1002.0,668.0)", 1, true) ~= nil,
  "D: the border covers the whole canvas (got "
    .. tostring(probeText:match("probe: border[^\n]*")) .. ")")
check(probeText:find("top(0.0,0.0)-(1002.0,4.0)=1002x4", 1, true) ~= nil,
  "D: the top border is 1002x4 and measured")
check(probeText:find("left(0.0,0.0)-(4.0,668.0)=4x668", 1, true) ~= nil,
  "D: the left border is 4x668 and measured")
check(probeText:find("probe: diagonal (0,0)->(1002.0,668.0) via LineDraw mode=dots", 1, true) ~= nil,
  "D: the diagonal uses the same line helper as the route (got "
    .. tostring(probeText:match("probe: diagonal[^\n]*")) .. ")")
check(probeText:find("report which you can SEE", 1, true) ~= nil,
  "D: the probe tells the reader what to report")

-- The probe's own objects are on the same host, and its diagonal is a dot chain.
local probeHostTextures = 0
for i = 1, #M.host.children do
  if M.host.children[i].kind == "texture" and M.host.children[i].shown then
    probeHostTextures = probeHostTextures + 1
  end
end
check(probeHostTextures > #textures + 4,
  "D: the probe added its marker, border and diagonal to the host (got "
    .. probeHostTextures .. " shown textures, route had " .. #textures .. ")")

-- ═══ E. probe off removes them, and the route survives ═════════════════════
chat = {}
SlashCmdList.NODETRAIL("mapdiag probe off")
local offText = table.concat(chat, "\n")
check(offText:find("probe: off (marker, border and diagonal removed)", 1, true) ~= nil,
  "E: probe off says what it removed (got " .. tostring(offText:match("probe:[^\n]*")) .. ")")
check(M._probe == nil, "E: the probe state is cleared")
check(M._lastQueued == 2, "E: the route is untouched by the probe (got "
  .. tostring(M._lastQueued) .. ")")

-- ═══ E2. the primitive can be pinned in game; the request is not a promise ══
chat = {}
SlashCmdList.NODETRAIL("mapdiag primitive dots")
local primText = table.concat(chat, "\n")
check(primText:find("primitive: requested dots; redrawing", 1, true) ~= nil,
  "E2: the pin is announced (got " .. tostring(primText:match("primitive:[^\n]*")) .. ")")
check(primText:find("primitive: chose mode=dots after the request", 1, true) ~= nil,
  "E2: the measured mode is reported back (got "
    .. tostring(primText:match("primitive: chose[^\n]*")) .. ")")

-- Asking for the line on a client that drops its endpoints must NOT produce a
-- line: the measurement wins over the request, and the diag says which mode won.
chat = {}
SlashCmdList.NODETRAIL("mapdiag primitive line")
local linePinText = table.concat(chat, "\n")
check(linePinText:find("primitive: requested line; redrawing", 1, true) ~= nil,
  "E2: the line pin is announced")
check(linePinText:find("primitive: chose mode=line", 1, true) == nil,
  "E2: a line the client cannot draw is not reported as chosen (got "
    .. tostring(linePinText:match("primitive: chose[^\n]*")) .. ")")
check(M.drawer.mode ~= "line",
  "E2: the drawer stays off the line primitive (mode=" .. tostring(M.drawer.mode) .. ")")

SlashCmdList.NODETRAIL("mapdiag primitive auto")
check(M.drawer.mode == "dots", "E2: auto returns to the measured primitive (mode="
  .. tostring(M.drawer.mode) .. ")")
check(M._drawError == nil, "E2: draw error: " .. tostring(M._drawError))

-- ═══ F. a client whose line primitive WORKS still uses it ══════════════════
-- The fallback must not be the only path: give this client's overlay host a
-- line region that keeps its endpoints and the primitive is chosen again.
-- (The drawer parents its objects to the HOST, so that is the frame whose
-- CreateLine is used.)
M.host.CreateLine = function(frame, _, layer)
  local line = makeRegion(frame, "line")
  line.layer = layer
  function line:SetStartPoint(point, rel, relPoint, x, y) self.start = { point, rel, relPoint, x, y } end
  function line:SetEndPoint(point, rel, relPoint, x, y) self.stop = { point, rel, relPoint, x, y } end
  function line:GetStartPoint()
    local p = self.start
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
  end
  function line:GetEndPoint()
    local p = self.stop
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
  end
  function line:SetThickness(t) self.thickness = t end
  function line:GetThickness() return self.thickness end
  table.insert(frame.lines, line)
  return line
end
ns.LineDraw.Invalidate(M.drawer)
M.drawer.disableLine = false
M:Redraw()
check(M._drawError == nil, "F: draw error: " .. tostring(M._drawError))
check(M.drawer.mode == "line", "F: a working line primitive is used again (mode="
  .. tostring(M.drawer.mode) .. ")")
if type(M.drawer.capability) ~= "table" then
  check(false, "F: the drawer recorded no capability proof")
else
  check(M.drawer.capability.line and M.drawer.capability.line.took == true,
    "F: the proof records that this client kept the endpoints")
end

if failed > 0 then
  io.stderr:write(failed .. " map draw primitive check(s) failed\n")
  os.exit(1)
end
print("mapdraw_primitive_spec: ok")

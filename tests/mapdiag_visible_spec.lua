-- t_86583cf2 — the world-map diag must report WHERE the dots are on the screen,
-- and must never report a draw it did not make.
--
-- Two failures this spec exists to prevent, both observed on the live client:
--
--   1. "painted=288 missing=0 outside=0" printed while the route was nowhere on
--      the screenshot. `outside` was measured against the dots' own host, which
--      they are parented to and therefore always fit inside — a check that
--      cannot fail. The spec requires the count to be taken in SCREEN space
--      against the rect the player can actually see (the scroll container that
--      clips the canvas), and requires a verdict when nothing lands there.
--
--   2. A redraw that bails (open map != route map) used to leave the previous
--      draw's `paintedDots` standing, so the diag described a route that was not
--      drawn at all. The spec draws, then bails, and requires the diag to say
--      "no draw on this map (<why>)".
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

-- ── A client that reports geometry, not agreement ─────────────────────────
-- Every region answers GetLeft/GetTop from the anchors it was GIVEN, at the
-- scale chain it lives in — the same contract the live client honours. That is
-- what makes "the dot is off the visible map" a measurement here.
local function newRegion(kind)
  local r = { kind = kind, points = {}, shown = false, parent = nil, scale = 1 }
  local function origin(relPoint, rel)
    local l, t = 0, 0
    if type(rel) == "table" and rel.GetLeft then
      l, t = rel:GetLeft() or 0, rel:GetTop() or 0
      local w, h = rel:GetWidth() or 0, rel:GetHeight() or 0
      if relPoint == "CENTER" then
        local s = rel:GetScale() or 1
        l, t = l + w * s * 0.5, t - h * s * 0.5
      end
    end
    return l, t
  end
  function r:SetPoint(point, rel, relPoint, x, y)
    self.points[#self.points + 1] = { point, rel, relPoint, x or 0, y or 0 }
  end
  function r:ClearAllPoints() self.points = {}; self.allPoints = nil end
  function r:GetNumPoints() return #self.points end
  function r:GetPoint(i)
    local p = self.points[i]
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
  end
  function r:SetParent(p) self.parent = p end
  function r:GetParent() return self.parent end
  function r:SetScale(s) self.scale = s end
  function r:GetScale() return self.scale end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:IsShown() return self.shown end
  function r:IsVisible() return self.shown end
  function r:SetDrawLayer() end
  function r:SetBlendMode() end
  function r:SetTexCoord() end
  function r:SetColorTexture() end
  function r:SetTexture() end
  function r:SetVertexColor() end
  function r:GetObjectType() return self.kind end
  function r:GetWidth()
    if self.allPoints and self.allPoints.GetWidth then return self.allPoints:GetWidth() end
    return self.width or 0
  end
  function r:GetHeight()
    if self.allPoints and self.allPoints.GetHeight then return self.allPoints:GetHeight() end
    return self.height or 0
  end
  -- A frame with SetAllPoints(parent) is exactly the parent's rect; a texture
  -- is where its own first anchor puts it, through the anchor's scale.
  function r:GetLeft()
    if self.allPoints then return self.allPoints:GetLeft() end
    local p = self.points[1]
    if not p then return self.fixedLeft or 0 end
    local l = origin(p[3], p[2])
    return l + (p[4] or 0) * (p[2] and p[2].GetScale and p[2]:GetScale() or 1)
  end
  function r:GetTop()
    if self.allPoints then return self.allPoints:GetTop() end
    local p = self.points[1]
    if not p then return self.fixedTop or 0 end
    local _, t = origin(p[3], p[2])
    return t + (p[5] or 0) * (p[2] and p[2].GetScale and p[2]:GetScale() or 1)
  end
  return r
end

local function newFrame(name, parent)
  local f = newRegion("Frame")
  f.name = name
  f.scripts = {}
  f.level, f.strata = 1, "MEDIUM"
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:GetScript(n) return self.scripts[n] end
  function f:HookScript(n, fn) self.scripts[n] = fn end
  function f:RegisterEvent() end
  function f:UnregisterEvent() end
  function f:GetName() return self.name end
  function f:SetSize(w, h) self.width, self.height = w, h end
  function f:SetAllPoints(p) self.allPoints = p or self.parent end
  function f:SetClipsChildren() end
  function f:EnableMouse() end
  function f:EnableMouseWheel() end
  function f:SetFrameLevel(l) self.level = l end
  function f:GetFrameLevel() return self.level end
  function f:SetFrameStrata(s) self.strata = s end
  function f:GetFrameStrata() return self.strata end
  function f:CreateTexture() local t = newRegion("Texture"); t.parent = self; return t end
  function f:CreateFontString() local t = newRegion("FontString"); t.parent = self; return t end
  function f:GetChildren() return {} end
  return f
end

function CreateFrame(kind, name, parent)
  local f = newFrame(name, parent)
  f.parent = parent
  return f
end

local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
SlashCmdList = {}
local clock = 10
function GetTime() return clock end
function CopyTable(t)
  local out = {}
  for k, v in pairs(t) do out[k] = type(v) == "table" and CopyTable(v) or v end
  return out
end

-- ── The client's map geometry (numbers the live client reported) ──────────
-- 2133x1200 UIParent; a 697x465 scroll container at (717,1080); the 1002x668
-- canvas drawn into it at 0.696, so the canvas is exactly the visible rect.
UIParent = newFrame("UIParent")
UIParent.width, UIParent.height = 2133, 1200
UIParent.fixedLeft, UIParent.fixedTop = 0, 1200

local scroll = newFrame("ScrollContainer")
scroll.parent = UIParent
scroll.width, scroll.height = 697, 465
scroll.fixedLeft, scroll.fixedTop = 717, 1080
-- The scroll frame's window, in CANVAS units. A client that reports it is the
-- only way to know which part of the canvas the player can see (the canvas'
-- GetLeft/GetTop are in the scroll child's space and cannot be compared with
-- this rect — the live client reported canvas top 699.4 against a map frame at
-- 1084, which is what made the old screen-space check read 0/319).
local scrollH, scrollV = 0, 0
local windowW, windowH = 1002, 668

local canvas = newFrame("WorldMapFrameCanvas")
canvas.parent = scroll
canvas.width, canvas.height = 1002, 668
canvas.scale = 0.696
-- GetLeft/GetTop are in the frame's OWN scaled units, so the canvas' screen box
-- is left*scale: these values put the 1002x668 canvas at screen 717,1080 — the
-- same box as the scroll container, which is what the client reports.
canvas.fixedLeft, canvas.fixedTop = 717 / canvas.scale, 1080 / canvas.scale

function scroll:GetScrollChild() return canvas end
function scroll:GetHorizontalScroll() return scrollH end
function scroll:GetVerticalScroll() return scrollV end
-- SetWindow takes CANVAS units (what the map maths needs) and stores the
-- scroll frame's own units (screen px at the canvas' 0.696 scale), which is
-- what the client reports.
function scroll:SetWindow(w, h)
  windowW, windowH = w or 1002, h or 668
  self.width, self.height = windowW * canvas.scale, windowH * canvas.scale
end
function scroll:SetScroll(h, v) scrollH, scrollV = h or 0, v or 0 end

local mapFrame = newFrame("WorldMapFrame")
mapFrame.parent = UIParent
mapFrame.width, mapFrame.height = 697, 465
mapFrame.fixedLeft, mapFrame.fixedTop = 717, 1080
mapFrame.ScrollContainer = scroll
local shownMapID = 1413
function mapFrame:GetCanvas() return canvas end
function mapFrame:GetCanvasScale() return 0.696 end
function mapFrame:GetMapID() return shownMapID end
WorldMapFrame = mapFrame

local MAPID = 1413
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
local W = ns.MapOverlay
ns.GetPlayerMapID = function() return MAPID end

local ROUTE = {
  mapID = MAPID,
  path = {
    { x = 0.400, y = 0.150 },
    { x = 0.630, y = 0.450 },
  },
}

local function diag()
  chat = {}
  W:Diag()
  return table.concat(chat, "\n")
end

local function line(out, prefix)
  for l in (out .. "\n"):gmatch("(.-)\n") do
    if l:find(prefix, 1, true) then return l end
  end
  return nil
end

-- ── 1. every rect on the way from the screen to the dots, in one line ──────
W:SetRoute(ROUTE)
local out = diag()
local rects = line(out, "map on screen:")
check(rects ~= nil, "1: the diag prints one line with every rect (got no 'map on screen:' line)")
if rects then
  check(rects:find("WorldMapFrame=717.0,1080.0", 1, true) ~= nil,
    "1: WorldMapFrame's own screen rect is printed: " .. rects)
  check(rects:find("ScrollContainer=717.0,1080.0 697.0x465.0", 1, true) ~= nil,
    "1: the scroll container's rect (the part the player can see) is printed: " .. rects)
  check(rects:find("canvas=717.0,1080.0 697.4x464.9", 1, true) ~= nil,
    "1: the canvas rect is printed in SCREEN px (1002 canvas px at 0.696 = 697): " .. rects)
  check(rects:find("host=", 1, true) ~= nil and rects:find("UIParent=0.0,1200.0 2133.0x1200.0", 1, true) ~= nil,
    "1: both the host and UIParent rects are printed: " .. rects)
end

-- ── 2. a healthy draw: every dot measured inside the VISIBLE rect ──────────
local painted = tonumber((ns.LineDraw.Applied(W.drawer) or {}).paintedDots) or 0
check(painted > 0, "2: the route painted dots on this map")
local visible = line(out, "route dots on the visible map:")
check(visible ~= nil, "2: the diag measures the dots against the map's visible rect")
if visible then
  local inside, total = visible:match("visible map: (%d+)/(%d+)")
  check(tonumber(inside) == painted and tonumber(total) == painted,
    "2: all " .. painted .. " painted dots land inside the visible map, measured in screen space (got " .. visible .. ")")
  check(visible:find("NO dot is inside", 1, true) == nil,
    "2: a healthy draw carries no 'off the map' verdict (" .. visible .. ")")
end

-- ── 3. a host moved off the VISIBLE RECT must be caught, per axis ─────────
-- t_c2ce2c49: the host is WorldMapFrame now and the rect it must sit on is the
-- ScrollContainer's rect relative to WorldMapFrame — the visible map rect. The
-- old canvas-parent expectation was the previous contract and now asserts the
-- bug. The per-axis numbers are what make a misplaced host fail loudly.
local onVisible = line(out, "host on the visible rect:")
check(onVisible ~= nil and onVisible:find("host on the visible rect: yes", 1, true) ~= nil,
  "3: a healthy draw asserts the host covers the visible rect (got " .. tostring(onVisible) .. ")")
check(onVisible ~= nil and onVisible:find("mode=frame", 1, true) ~= nil,
  "3: and state the mapping mode, so an old canvas-host build is identifiable from a paste (got "
    .. tostring(onVisible) .. ")")
W.host:ClearAllPoints()
W.host:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 0, 1200)
W.host.width, W.host.height = 100, 100
out = diag()
local offHost = line(out, "host on the visible rect:")
check(offHost ~= nil and offHost:find("host on the visible rect: NO", 1, true) ~= nil,
  "3: a host placed away from the visible rect reads NO — not a pass (got " .. tostring(offHost) .. ")")
check(offHost ~= nil and offHost:find("host x=", 1, true) ~= nil
    and offHost:find("visible x=", 1, true) ~= nil,
  "3: and gives the host and visible rects per axis (got " .. tostring(offHost) .. ")")

-- ── 4. a redraw that bails must not report the previous draw ──────────────
-- Put the host back, redraw on the route's map (14 dots painted), then open
-- another map and redraw. The overlay is hidden; the diag must say so.
W.host:ClearAllPoints()
W.host:SetAllPoints(WorldMapFrame)
clock = clock + 1
W:Redraw()
local applied = ns.LineDraw.Applied(W.drawer)
check(tonumber(applied.paintedDots) == painted, "4: the draw painted " .. painted .. " dots (got "
  .. tostring(applied.paintedDots) .. ")")

shownMapID = 1414
W:Redraw()
local afterSwitch = diag()
local pool = line(afterSwitch, "dots pool:")
check(pool ~= nil and pool:find("no draw on this map", 1, true) ~= nil,
  "4: after bailing on another map the diag says no draw (got " .. tostring(pool) .. ")")
check(pool ~= nil and pool:find("the open map is 1414, the route is on 1413", 1, true) ~= nil,
  "4: and names why (got " .. tostring(pool) .. ")")
check(afterSwitch:find("painted=" .. painted, 1, true) == nil,
  "4: the previous draw's count is NOT reported as this draw's")
local idleVisible = line(afterSwitch, "route dots on the visible map:")
check(idleVisible ~= nil and idleVisible:find("0/0", 1, true) ~= nil,
  "4: the visible-map line reports 0/0, not dots that are not drawn (got "
    .. tostring(idleVisible) .. ")")

-- ── 5. back on the route's map, the draw reports itself again ─────────────
shownMapID = 1413
clock = clock + 1
W:Redraw()
local back = line(diag(), "route dots on the visible map:")
check(back ~= nil and back:find("visible map: " .. painted .. "/" .. painted, 1, true) ~= nil,
  "5: returning to the route's map reports the dots again (got " .. tostring(back) .. ")")

-- ── 6. the same measurement is written where the next run can read it ─────
-- The evidence for this card has to be readable off
-- WTF/.../SavedVariables/MightiePack.lua (NodeTrailDB.mapProbe) instead of a
-- pasted chat line, so the draw records its own placement numbers.
local probe = ns.GetDB().mapProbe
check(type(probe) == "table", "6: the draw records a placement probe in the DB")
if type(probe) == "table" then
  check(probe.mapID == MAPID, "6: the probe names the map it measured (" .. tostring(probe.mapID) .. ")")
  check(probe.painted == painted, "6: it records the painted dot count (" .. tostring(probe.painted) .. ")")
  check(probe.inside == painted, "6: and how many of them are inside the visible map ("
    .. tostring(probe.inside) .. ")")
  check(type(probe.window) == "table" and probe.window.left == 0 and math.abs(probe.window.width - 697.4) < 2,
    "6: with the visible rect in frame px — the ruler the count uses ("
      .. tostring(probe.window and (probe.window.left .. ".." .. probe.window.width)) .. ")")
  check(type(probe.windowUnits) == "string" and probe.windowUnits:find("frame px", 1, true) ~= nil,
    "6: and the units named (" .. tostring(probe.windowUnits) .. ")")
  check(type(probe.windowCanvas) == "table" and math.abs(probe.windowCanvas.width - 1002) < 2,
    "6: with the same window in canvas units kept alongside it ("
      .. tostring(probe.windowCanvas and probe.windowCanvas.width) .. ")")
  check(type(probe.windowCanvas) == "table" and type(probe.windowCanvas.method) == "string",
    "6: and the measurement that canvas reading came from ("
      .. tostring(probe.windowCanvas and probe.windowCanvas.method) .. ")")
  check(type(probe.host) == "table" and probe.host.top == 1080,
    "6: and the host rect (" .. tostring(probe.host and probe.host.top) .. ")")
  check(type(probe.canvas) == "table" and math.abs((probe.canvas.width or 0) - 697.4) < 0.2,
    "6: and the canvas rect in screen px (" .. tostring(probe.canvas and probe.canvas.width) .. ")")
  check(probe.canvasScale ~= nil, "6: and the canvas scale the client reports")
  check(probe.idle ~= true, "6: a real draw is not recorded as idle")
end

-- After a bail, the probe must say so too — a zero-painted record that looks
-- like an empty route is exactly the confusion this card exists to end.
shownMapID = 1414
clock = clock + 1
W:Redraw()
probe = ns.GetDB().mapProbe
check(type(probe) == "table" and probe.idle == true,
  "6: a bailed redraw is recorded as idle (" .. tostring(probe and probe.idle) .. ")")
check(type(probe) == "table" and type(probe.why) == "string"
  and probe.why:find("the open map is 1414", 1, true) ~= nil,
  "6: with the reason recorded (" .. tostring(probe and probe.why) .. ")")
shownMapID = 1413

-- ── 8. the "inside" count follows the VISIBLE RECT in the frame mapping ────
-- t_c2ce2c49: the host is WorldMapFrame and the dots are anchored in its pixel
-- space, so the subset must be measured in the SAME space — the ScrollContainer
-- rect relative to WorldMapFrame — not in canvas units (that ruler read 0/37
-- for a route that was on screen).
--
-- A partial subset is impossible BY CONSTRUCTION in this mapping: the draw
-- clips every segment to the visible rect before it places a dot, so every
-- painted dot lands inside. The fixture therefore asserts the invariant that
-- replaces `inside < total`: every painted dot is inside AND the smaller
-- visible rect really cropped the route (fewer dots than the full-map draw).
-- The discriminator against a false pass is the sliver window below: too small
-- to be treated as a viewport, it is NOT clipped for, and the audit must then
-- read 0/<painted> with the "NO dot is inside" verdict instead of a pass.
shownMapID = 1413
scroll:SetWindow(1002, 668)
scroll:SetScroll(0, 0)
clock = clock + 1
W:Redraw()
local fullPainted = tonumber((ns.LineDraw.Applied(W.drawer) or {}).paintedDots) or 0
check(fullPainted > 2, "8: the full-map draw painted dots (" .. fullPainted .. ")")

-- A 500x350 canvas-unit window at the map's top-left: the route crosses its
-- right edge, so part of it has to be cropped away. Its size in the host's
-- space is the scroll frame's own (500 x 0.696 by 350 x 0.696).
scroll:SetWindow(500, 350)
scroll:SetScroll(300, 200)
local visW, visH = scroll.width, scroll.height
clock = clock + 1
W:Redraw()
local zoomOut = line(diag(), "route dots on the visible map:")
check(zoomOut ~= nil, "8: the visible-map line is printed for a cropped map")
check(zoomOut ~= nil and zoomOut:find("mode=frame", 1, true) ~= nil,
  "8: and it names the frame mapping mode (got " .. tostring(zoomOut) .. ")")
do
  local wl, wt, ww, wh
  if zoomOut then
    wl, wt, ww, wh = zoomOut:match("window=([%-%d%.]+),([%-%d%.]+) ([%-%d%.]+)x([%-%d%.]+) in frame px")
  end
  check(tonumber(ww) ~= nil and math.abs(tonumber(ww) - visW) < 0.6
      and math.abs(tonumber(wh) - visH) < 0.6,
    ("8: the window is the ScrollContainer rect in frame px (%sx%s, expected %sx%s)")
      :format(tostring(ww), tostring(wh), tostring(visW), tostring(visH)))
  local drawer = W.drawer
  local appliedNow = ns.LineDraw.Applied(drawer) or {}
  local tot = tonumber(appliedNow.paintedDots) or 0
  local expect = 0
  for d = 1, tot do
    local obj = drawer and drawer.pool and drawer.pool[2 * d]
    if obj and obj.GetPoint and obj:GetNumPoints() >= 2 then
      local _, _, _, x1, y1 = obj:GetPoint(1)
      local _, _, _, x2, y2 = obj:GetPoint(2)
      if type(x1) == "number" and type(x2) == "number" then
        local cx, cy = (x1 + x2) * 0.5, -(y1 + y2) * 0.5
        if cx >= -0.5 and cx <= visW + 0.5 and cy >= -0.5 and cy <= visH + 0.5 then
          expect = expect + 1
        end
      end
    end
  end
  local insideN, denom
  if zoomOut then
    insideN, denom = zoomOut:match("visible map: (%d+)/(%d+)")
  end
  check(tonumber(denom) == tot, "8: the denominator is the painted count ("
    .. tostring(denom) .. " of " .. tot .. ")")
  check(tonumber(insideN) == expect,
    ("8: exactly the dots inside the visible rect count (%s, expected %d of %d)")
      :format(tostring(insideN), expect, tot))
  check(tot > 0, "8: the cropped route still paints dots (" .. tot .. ")")
  check(expect == tot,
    ("8: every painted dot is inside the visible rect — the draw clips before it paints (%d of %d)")
      :format(expect, tot))
  check(tot < fullPainted,
    ("8: the smaller visible rect really cropped the route (%d of %d dots)"):format(tot, fullPainted))
end
-- A sliver window is not treated as a viewport (measured accident), so the draw
-- is not clipped for it. The audit must then say every dot is outside it — the
-- count has to catch a false pass, not rubber-stamp the last draw.
scroll:SetWindow(10, 10)
scroll:SetScroll(0, 0)
clock = clock + 1
W:Redraw()
local empty = line(diag(), "route dots on the visible map:")
check(empty ~= nil and empty:find("visible map: 0/", 1, true) ~= nil,
  "8: a sliver window reads 0 inside (got " .. tostring(empty) .. ")")
check(empty ~= nil and empty:find("NO dot is inside the visible window", 1, true) ~= nil,
  "8: and carries the verdict, so a dot outside the visible rect cannot read as a pass (got "
    .. tostring(empty) .. ")")
check(empty ~= nil and empty:find("mode=frame", 1, true) ~= nil,
  "8: with the mapping mode named (got " .. tostring(empty) .. ")")
-- Back to the whole canvas for the remaining sections.
scroll:SetWindow(1002, 668)
scroll:SetScroll(0, 0)
clock = clock + 1
W:Redraw()

-- ── 7. a partly-unreadable draw must not read as a pass ────────────────────
-- Review round 1: with 36 of 72 painted dots dragged off the visible map and
-- made unreadable, the line printed `36/36 inside` with no verdict — because
-- the denominator was `measured`. Half the route was unexamined and the line
-- still read as a pass, which is the same defect class as the `outside=0`
-- check this spec exists to end. The denominator is PAINTED, and a remainder
-- that could not be measured is named in the verdict.
clock = clock + 1
W:Redraw()
local total = tonumber((ns.LineDraw.Applied(W.drawer) or {}).paintedDots) or 0
check(total > 2, "7: the redraw painted dots to mix (" .. total .. " dot(s))")
local sabotaged = 0
do
  local drawer = W.drawer
  for d = 2, total, 2 do -- every second dot: measurable and unmeasurable mixed
    local obj = drawer and drawer.pool and drawer.pool[2 * d]
    if obj and obj.GetPoint and obj:GetNumPoints() >= 2 then
      local _, _, _, x1, y1 = obj:GetPoint(1)
      local _, _, _, x2, y2 = obj:GetPoint(2)
      obj:ClearAllPoints()
      obj:SetPoint("BOTTOMLEFT", W.host, "TOPLEFT", x1, y1)
      -- the second corner is anchored to a DIFFERENT frame: the client still
      -- draws it, but no screen rect can be computed from these anchors
      obj:SetPoint("TOPRIGHT", canvas, "TOPLEFT", x2, y2)
      sabotaged = sabotaged + 1
    end
  end
end
check(sabotaged > 0 and sabotaged < total,
  "7: some but not all dots are unreadable (" .. sabotaged .. " of " .. total .. ")")
local mixedOut = diag()
local mixed = line(mixedOut, "route dots on the visible map:")
check(mixed ~= nil, "7: the line is printed for a mixed draw")
if mixed and os.getenv("NODETRAIL_VERBOSE") then io.write("mixed draw: " .. mixed .. "\n") end
if mixed then
  local insideN, denom = mixed:match("visible map: (%d+)/(%d+)")
  check(tonumber(denom) == total,
    "7: the denominator is the PAINTED count (" .. tostring(denom) .. " of " .. total .. ")")
  check(tonumber(insideN) ~= tonumber(denom),
    "7: half the dots are unexamined, so the line cannot read as all-inside (" .. mixed .. ")")
  local measuredN = tonumber((mixed:match("measured (%d+) of %d+ painted")))
  check(measuredN == total - sabotaged,
    "7: it says how many dots were actually measured (" .. tostring(measuredN) .. " of " .. total .. ")")
  check(mixed:find("report no map anchors — not measured", 1, true) ~= nil,
    "7: and names the unreadable remainder in the verdict (" .. mixed .. ")")
  local namedN = tonumber(mixed:match("(%d+) of %d+ painted dot%(s%) report no map anchors"))
  check(namedN == sabotaged,
    "7: the remainder count matches the sabotage (" .. tostring(namedN) .. " of " .. sabotaged .. ")")
end
-- The saved copy must keep the two counts apart: a reader who sees
-- painted=14 has to be able to see that only some of them were measured.
if type(W.RecordProbe) == "function" then
  W:RecordProbe(true)
else
  check(false, "7: the draw records its placement in the DB (no RecordProbe method)")
end
local mixedProbe = ns.GetDB().mapProbe
check(type(mixedProbe) == "table" and mixedProbe.painted == total,
  "7: the probe records painted (" .. tostring(mixedProbe and mixedProbe.painted) .. ")")
check(type(mixedProbe) == "table" and mixedProbe.measured == total - sabotaged,
  "7: and measured separately (" .. tostring(mixedProbe and mixedProbe.measured) .. ")")
check(type(mixedProbe) == "table" and mixedProbe.unmeasured == sabotaged,
  "7: and the unmeasured remainder (" .. tostring(mixedProbe and mixedProbe.unmeasured) .. ")")
check(type(mixedProbe) == "table" and (mixedProbe.inside or 0) <= (mixedProbe.measured or 0),
  "7: never more dots inside than it measured")

if failed > 0 then
  io.stderr:write(("mapdiag_visible_spec: %d failure(s)\n"):format(failed))
  os.exit(1)
end
print("mapdiag_visible_spec: ok")

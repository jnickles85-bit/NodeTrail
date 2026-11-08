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
function GetTime() return 10 end
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

local canvas = newFrame("WorldMapFrameCanvas")
canvas.parent = scroll
canvas.width, canvas.height = 1002, 668
canvas.scale = 0.696
canvas.fixedLeft, canvas.fixedTop = 717, 1080

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

-- ── 3. the defect ara photographed: the host is somewhere else ────────────
-- Move the overlay host off the map (this is what "the route is not anywhere
-- in the picture" looks like to the client) and re-ask the diag. The count must
-- be taken against the visible rect, so it must read 0/14 with a verdict.
W.host:ClearAllPoints()
W.host:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 0, 1200)
out = diag()
local off = line(out, "route dots on the visible map:")
check(off ~= nil and off:find("visible map: 0/" .. painted, 1, true) ~= nil,
  "3: a host placed away from the map reads 0/" .. painted .. " inside — not all inside (got " .. tostring(off) .. ")")
check(off ~= nil and off:find("NO dot is inside the visible map", 1, true) ~= nil,
  "3: and the line carries the verdict instead of a pass (got " .. tostring(off) .. ")")

-- ── 4. a redraw that bails must not report the previous draw ──────────────
-- Put the host back, redraw on the route's map (14 dots painted), then open
-- another map and redraw. The overlay is hidden; the diag must say so.
W.host:ClearAllPoints()
W.host:SetAllPoints(canvas)
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
  check(type(probe.visible) == "table" and probe.visible.left == 717,
    "6: with the visible rect, measured (" .. tostring(probe.visible and probe.visible.left) .. ")")
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
W:Redraw()
probe = ns.GetDB().mapProbe
check(type(probe) == "table" and probe.idle == true,
  "6: a bailed redraw is recorded as idle (" .. tostring(probe and probe.idle) .. ")")
check(type(probe) == "table" and type(probe.why) == "string"
  and probe.why:find("the open map is 1414", 1, true) ~= nil,
  "6: with the reason recorded (" .. tostring(probe and probe.why) .. ")")
shownMapID = 1413

if failed > 0 then
  io.stderr:write(("mapdiag_visible_spec: %d failure(s)\n"):format(failed))
  os.exit(1)
end
print("mapdiag_visible_spec: ok")

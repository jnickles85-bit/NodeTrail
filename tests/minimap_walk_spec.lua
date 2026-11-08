-- t_86583cf2 — Mightie's walk test, replayed against the REAL drawers.
--
-- The requirement: "choose a route segment beside a recognizable landmark, walk
-- toward it, past it, and back. It must remain beside that landmark, and my
-- distance to the segment must decrease as I approach."
--
-- The earlier check was circular: it compared the diag's fresh recalculation of
-- the player's map fraction with the previous recalculation. That proves the
-- maths is live, not that the OBJECTS track the ground. So this spec never asks
-- the projection what it thinks: after each redraw it reads the ANCHORS the
-- client reports for the nearest drawn dot (`GetPoint(1)`/`GetPoint(2)`), turns
-- them back into a centre, and asserts four things across four stops:
--
--   1. the dot's centre is where the STAMPED player fraction puts that ground
--      position (so the drawn object follows the stamp, not print time);
--   2. between stops the anchor moves OPPOSITE the player in map space, by the
--      same number of pixels per map fraction;
--   3. the dot keeps a CONSTANT offset from a landmark beside the route — the
--      "stays beside the landmark" half of the requirement;
--   4. the player's distance to the segment shrinks to ~0 as they walk onto it
--      and grows again after they pass it and walk back.
--
-- Section B proves the stamp is a DRAW-TIME stamp: moving the player without a
-- redraw changes nothing the diag prints. Section C is the two-surface check:
-- every route point on the world map, the same index set addressed on the
-- minimap, and one comparison line that names any point the world map lost.
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

local function near(a, b, tol, msg)
  tol = tol or 0.5
  check(type(a) == "number" and type(b) == "number" and math.abs(a - b) <= tol,
    (msg or "near") .. " got " .. tostring(a) .. " expected " .. tostring(b))
end

-- ── A client that measures, not one that says yes ──────────────────────────
-- Every region records the anchors it is given and reports them back through
-- the same 5-value contract the real client uses. That is what makes the
-- assertions below statements about drawn geometry instead of about our maths.
local function newRegion(kind)
  local r = { kind = kind, points = {}, shown = false, parent = nil }
  function r:SetPoint(point, rel, relPoint, x, y)
    self.points[#self.points + 1] = { point, rel, relPoint, x or 0, y or 0 }
  end
  function r:ClearAllPoints() self.points = {} end
  function r:GetNumPoints() return #self.points end
  function r:GetPoint(i)
    local p = self.points[i]
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
  end
  function r:GetWidth() return 0 end
  function r:GetHeight() return 0 end
  function r:SetParent(p) self.parent = p end
  function r:GetParent() return self.parent end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:IsShown() return self.shown end
  function r:GetLeft() return 0 end
  function r:GetTop() return 0 end
  function r:GetScale() return 1 end
  function r:SetDrawLayer() end
  function r:SetBlendMode() end
  function r:SetTexCoord() end
  function r:SetColorTexture() end
  function r:SetTexture() end
  function r:SetVertexColor() end
  function r:SetText(t) self.text = t end
  function r:GetText() return self.text end
  function r:SetFont() end
  function r:SetFontObject() end
  function r:GetObjectType() return self.kind end
  return r
end

local function newFrame(kind, name, parent)
  local f = newRegion(kind)
  f.name = name
  f.scripts = {}
  f.width, f.height = 0, 0
  f.level, f.strata = 1, "MEDIUM"
  f.kind = kind or "Frame"
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:GetScript(n) return self.scripts[n] end
  function f:HookScript(n, fn) self.scripts[n] = fn end
  function f:RegisterEvent() end
  function f:UnregisterEvent() end
  function f:GetName() return self.name end
  function f:GetWidth() return self.width end
  function f:GetHeight() return self.height end
  function f:SetSize(w, h) self.width, self.height = w, h end
  function f:SetAllPoints() end
  function f:SetClipsChildren() end
  function f:EnableMouse() end
  function f:EnableMouseWheel() end
  function f:SetFrameLevel(l) self.level = l end
  function f:GetFrameLevel() return self.level end
  function f:SetFrameStrata(s) self.strata = s end
  function f:GetFrameStrata() return self.strata end
  function f:IsVisible() return self.shown end
  function f:CreateTexture() return newRegion("Texture") end
  function f:CreateFontString() return newRegion("FontString") end
  return f
end

function CreateFrame(kind, name, parent)
  return newFrame(kind, name, parent)
end

function CopyTable(t)
  local out = {}
  for k, v in pairs(t) do
    out[k] = type(v) == "table" and CopyTable(v) or v
  end
  return out
end

local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
SlashCmdList = {}

local clock = 0
function GetTime() return clock end

-- The player's map fraction is the ONE input the walk moves. Everything else
-- (the route, the landmark) stays put, which is the whole test.
local playerX, playerY = 0.480, 0.300
function GetPlayerMapPosition(unit)
  if unit == "player" then
    return playerX, playerY
  end
  return 0, 0
end

local zoom = 0
Minimap = newFrame("Frame", "Minimap")
Minimap.width, Minimap.height = 140, 140
function Minimap:GetZoom() return zoom end
function Minimap:IsVisible() return true end

function GetCVar(name)
  if name == "rotateMinimap" then return "0" end
  if name == "minimapZoom" then return tostring(zoom) end
  return nil
end
function GetMinimapShape() return "ROUND" end

-- The world map: a canvas whose size and scale are the client's (1002x668 shown
-- at 0.696), so the two surfaces are drawn through the same numbers the live
-- diag prints.
local canvas = newFrame("Frame", "WorldMapFrameCanvas")
canvas.width, canvas.height = 1002, 668
local mapFrame = newFrame("Frame", "WorldMapFrame")
mapFrame.width, mapFrame.height = 1002, 668
function mapFrame:GetCanvas() return canvas end
function mapFrame:GetCanvasScale() return 0.696 end
function mapFrame:GetMapID() return 1413 end
function mapFrame:GetLeft() return 0 end
function mapFrame:GetTop() return 668 end
WorldMapFrame = mapFrame
UIParent = newFrame("Frame", "UIParent")
UIParent.width, UIParent.height = 2133, 1200

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
loadAddon("UI/MinimapPath.lua")

local ns = pkg.NodeTrail
local M = ns.MinimapPath
local W = ns.MapOverlay
ns.GetPlayerMapID = function() return MAPID end

-- ── The ground under test ──────────────────────────────────────────────────
-- A landmark (think Crossroads' label) at (0.500, 0.300), and a route segment
-- one fifth of a map-width EAST of it, running north-south. The player walks
-- EAST along y = 0.300: toward the segment, onto it, past it, and back.
local LANDMARK = { x = 0.500, y = 0.300 }
local SEG_X = 0.520
local ROUTE = {
  mapID = MAPID,
  path = {
    { x = SEG_X, y = 0.280 },
    { x = SEG_X, y = 0.320 },
  },
}

local HALF = 70                 -- Minimap 140x140
local RADIUS = 0.075            -- the fraction fallback the live diag prints
local PX_PER_FRAC = HALF / RADIUS

local function sayMinimap()
  chat = {}
  M:Diag()
  return table.concat(chat, "\n")
end

-- The nearest DRAWN dot, read from the objects: anchors -> centre.
local function drawnDotCentre()
  local drawer = M.drawer
  local applied = drawer and ns.LineDraw.Applied(drawer)
  local painted = tonumber(applied and applied.paintedDots) or 0
  local best
  for d = 1, painted do
    local obj = drawer.pool and drawer.pool[2 * d]
    if obj and obj.GetPoint and obj:GetNumPoints() >= 2 then
      local _, _, rp1, x1, y1 = obj:GetPoint(1)
      local _, _, rp2, x2, y2 = obj:GetPoint(2)
      if type(x1) == "number" and type(x2) == "number" then
        local cx = (x1 + x2) * 0.5
        local cy = (y1 + y2) * 0.5
        if rp1 and rp1 ~= "CENTER" then
          cy = -cy
        end
        local dist = math.sqrt(cx * cx + cy * cy)
        if not best or dist < best.dist then
          best = { dot = d, cx = cx, cy = cy, dist = dist, rp1 = rp1 }
        end
      end
    end
  end
  return best, painted
end

-- ── 0. with nothing drawn the stamp must say so ────────────────────────────
do
  local out = sayMinimap()
  check(out:find("minimap stamp: absent", 1, true) ~= nil,
    "0: with no draw the stamp reports absent (got "
      .. tostring(out:match("minimap stamp:[^\n]*")) .. ")")
end

-- ── A. the four-stop walk ──────────────────────────────────────────────────
M:SetRoute(ROUTE)
W:SetRoute(ROUTE)
check(M._drawError == nil, "A: minimap draw error: " .. tostring(M._drawError))
check(W._drawError == nil, "A: world-map draw error: " .. tostring(W._drawError))
check(M._stamp ~= nil, "A: the drawer carries a draw-time stamp")
check(type(M.drawer.lastApplied) == "table" and type(M.drawer.lastApplied.playerFrac) == "table",
  "A: lastApplied.playerFrac is on the drawer (the stamp lives with the drawing)")

local STOPS = {
  { name = "1 start",     x = 0.480, y = 0.300 },
  { name = "2 toward",    x = 0.510, y = 0.300 },
  { name = "3 past it",   x = 0.522, y = 0.300 },
  { name = "4 walked back", x = 0.505, y = 0.300 },
}

local rows = {}
local previous
for i = 1, #STOPS do
  local stop = STOPS[i]
  playerX, playerY = stop.x, stop.y
  clock = clock + 1.5
  M:Redraw()
  W:Redraw()

  local applied = M.drawer.lastApplied
  check(applied.playerFrac and math.abs(applied.playerFrac.x - playerX) < 1e-9
    and math.abs(applied.playerFrac.y - playerY) < 1e-9,
    ("A%s: the stamp is this redraw's player fraction (got %s, player %s)")
      :format(i, tostring(applied.playerFrac and applied.playerFrac.x), tostring(playerX)))
  check(applied.time == clock, "A" .. i .. ": the stamp carries the draw time")
  check(applied.mapID == MAPID, "A" .. i .. ": the stamp carries the mapID")

  local dot, painted = drawnDotCentre()
  -- The diag's own record for the same draw: it must name the SAME dot the
  -- objects do, and it is where the player->segment distance comes from.
  local audit = (type(M.DrawnAudit) == "function") and M:DrawnAudit() or nil
  local an = audit and audit.nearest
  check(an ~= nil and dot ~= nil and an.dot == dot.dot,
    ("A%s: the diag's nearest drawn dot is the object the anchors came from"):format(i))
  check(dot ~= nil, "A" .. i .. ": a drawn dot carries numeric anchors (" .. painted .. " painted)")
  check(dot and dot.rp1 == "CENTER",
    "A" .. i .. ": the dot anchors from the minimap CENTRE (got " .. tostring(dot and dot.rp1) .. ")")

  -- Where the ground position should land, from the STAMP (not from a fresh
  -- position read): the segment's foot is directly east of the player.
  local expectX = (SEG_X - playerX) * PX_PER_FRAC
  local expectLandmarkX = (LANDMARK.x - playerX) * PX_PER_FRAC
  rows[i] = {
    name = stop.name, playerX = playerX, playerY = playerY,
    stampX = type(applied.playerFrac) == "table" and applied.playerFrac.x or nil,
    stampT = applied.time,
    cx = dot and dot.cx, cy = dot and dot.cy, dist = dot and dot.dist,
    expectX = expectX, expectLandmarkX = expectLandmarkX,
    toSegment = an and an.playerSegPx,
    segmentFrac = an and an.playerSegFrac,
    painted = painted,
  }

  near(dot and dot.cx, expectX, 0.75,
    ("A%s: the drawn dot sits on the ground the STAMP puts it on"):format(i))
  check(dot and math.abs(dot.cy) <= 2.0,
    ("A%s: the nearest dot is the perpendicular foot of the segment (cy=%s)")
      :format(i, tostring(dot and dot.cy)))
  -- The player's distance to that segment, from the diag's own record…
  near(an and an.playerSegPx, math.abs(SEG_X - playerX) * PX_PER_FRAC, 0.75,
    ("A%s: the recorded player->segment distance is the real one"):format(i))
  -- The landmark invariant: the dot keeps a CONSTANT offset from the landmark
  -- in map space, at every stop. This is "stays beside the same landmark".
  near((dot and dot.cx or 0) - expectLandmarkX, (SEG_X - LANDMARK.x) * PX_PER_FRAC, 0.75,
    ("A%s: the dot is the same distance from the landmark as the ground is"):format(i))

  -- …and between stops the anchor moves OPPOSITE the player, px for px.
  if previous then
    local dPlayer = playerX - previous.playerX
    local dAnchor = (dot and dot.cx or 0) - previous.cx
    near(dAnchor, -dPlayer * PX_PER_FRAC, 0.75,
      ("A%s: the drawn anchor moves opposite the player in map space"):format(i))
  end
  previous = rows[i]
end

-- 4. the distance to the segment: shrinking onto it, then growing again.
-- (Every comparison is guarded: a client that records no distance must FAIL
-- these, not raise and take the rest of the spec with it.)
local function isNum(v) return type(v) == "number" end
check(isNum(rows[1].toSegment) and isNum(rows[2].toSegment)
  and rows[2].toSegment < rows[1].toSegment - 5,
  ("A: walking toward the segment shrinks the drawn distance (%s -> %s)")
    :format(tostring(rows[1].toSegment), tostring(rows[2].toSegment)))
check(isNum(rows[2].toSegment) and isNum(rows[3].toSegment)
  and rows[3].toSegment < rows[2].toSegment,
  ("A: standing on the segment is closer than approaching it (%s -> %s)")
    :format(tostring(rows[2].toSegment), tostring(rows[3].toSegment)))
check(isNum(rows[3].toSegment) and rows[3].toSegment <= 2.5,
  ("A: the segment is right under the player when passed (dist=%s)"):format(tostring(rows[3].toSegment)))
check(isNum(rows[3].toSegment) and isNum(rows[4].toSegment)
  and rows[4].toSegment > rows[3].toSegment,
  ("A: walking back recedes from the segment (%s -> %s)")
    :format(tostring(rows[3].toSegment), tostring(rows[4].toSegment)))

-- The four-stop table, printed from the numbers the assertions above used, so a
-- handoff can carry the measurements instead of a description of them.
do
  local function f(v, d)
    if type(v) ~= "number" then return "absent" end
    return string.format("%." .. (d or 2) .. "f", v)
  end
  io.write("\nstop              player(frac)     stamp(frac)/t   anchor cx,cy px   dist px  dist map-frac  to-segment px\n")
  for i = 1, #rows do
    local r = rows[i]
    io.write(string.format("%-16s (%s,%s)  (%s, t=%s)  (%s, %s)  %s  %s  %s\n",
      r.name, f(r.playerX, 4), f(r.playerY, 4), f(r.stampX, 4), f(r.stampT, 1),
      f(r.cx), f(r.cy), f(r.dist),
      f(type(r.dist) == "number" and r.dist / PX_PER_FRAC or nil, 4), f(r.toSegment)))
  end
  io.write(string.format("landmark at (%s,%s); route segment x=%s, y 0.280..0.320; radius=%s frac = %s px/fraction; dots painted at stop 4: %s\n\n",
    f(LANDMARK.x, 3), f(LANDMARK.y, 3), f(SEG_X, 3), f(RADIUS, 4), f(PX_PER_FRAC, 1), tostring(rows[#rows].painted)))
end

-- ── B. the stamp is a DRAW-TIME value, not a print-time recomputation ──────
do
  playerX = 0.490          -- the player moved; nothing has been redrawn
  local applied = M.drawer.lastApplied or {}
  local stamped = type(applied.playerFrac) == "table" and applied.playerFrac.x or nil
  check(type(stamped) == "number" and math.abs(stamped - 0.505) < 1e-9,
    ("B: the drawer still reports the fraction the LAST DRAW used (%s), not the player's new one")
      :format(tostring(stamped)))
  local out = sayMinimap()
  check(out:find("playerFrac=(0.5050,0.3000)", 1, true) ~= nil,
    "B: /nt mapdiag prints the draw-time fraction verbatim (got "
      .. tostring(out:match("minimap stamp:[^\n]*")) .. ")")
  check(out:find("captured at draw time, not recomputed", 1, true) ~= nil,
    "B: the stamp line says what it is")
end

-- ── C. the diag reports the drawn objects, not the intent ──────────────────
do
  playerX, playerY = 0.505, 0.300
  clock = clock + 1
  M:Redraw()
  W:Redraw()
  local out = sayMinimap()
  for _, needle in ipairs({
    "minimap drawn dot: nearest of",
    "GetPoint(1)=",
    "GetPoint(2)=",
    "centre=",
    "px = ",
    "x-radius = ",
    "minimap drawn dot route: segment 1->2",
    "route point #1",
    "world-map anchor for #1 =",
    "minimap drawn vs planned: drawn=",
    "ticker=",
    "since-last-move=",
  }) do
    check(out:find(needle, 1, true) ~= nil, "C: diag missing: " .. needle)
  end
  check(out:find("minimap drawn dot route:", 1, true) ~= nil
    and out:find("player->that segment =", 1, true) ~= nil,
    "C: the diag prints the player's distance to the drawn dot's segment")
  check(out:find("minimap drawError=none", 1, true) ~= nil, "C: no minimap draw error")
  check(out:find("error: ", 1, true) == nil, "C: no diag line errored")
  -- The lines themselves, so a handoff can quote what the diag says instead of
  -- describing it. Only the ones this card added.
  local wanted = {
    "minimap stamp:", "minimap drawn dot:", "minimap drawn dot route:",
    "minimap drawn vs planned:", "minimap crosscheck:",
  }
  for line in (out .. "\n"):gmatch("([^\n]*)\n") do
    for k = 1, #wanted do
      if line:find("mapdiag: " .. wanted[k], 1, true) then
        io.write(line:gsub("^NodeTrail mapdiag: ", "") .. "\n")
        break
      end
    end
  end
end

-- ── D. both surfaces show the same route (the t_ec00e4f3 fix, verified) ────
do
  local out = sayMinimap()
  local cross = out:match("minimap crosscheck:[^\n]*")
  check(cross ~= nil, "D: the diag prints a point-by-point crosscheck")
  check(cross and cross:find("world-map canvas 2 on this map, 0 missing", 1, true) ~= nil,
    "D: every route point is on the world map (got " .. tostring(cross) .. ")")
  check(cross and cross:find("mapID equal", 1, true) ~= nil,
    "D: both surfaces are on the same mapID")
  check(cross and cross:find("#1 frac=", 1, true) ~= nil
    and cross:find(" canvas=", 1, true) ~= nil
    and cross:find(" worldYd=", 1, true) ~= nil
    and cross:find("#2 frac=", 1, true) ~= nil,
    "D: the crosscheck names each index with its fraction, canvas anchor and world yards (" .. tostring(cross) .. ")")
  check(cross and cross:find(" minimap 2 drawn", 1, true) ~= nil,
    "D: both route points are drawn on the minimap at this range")
  check(W._px and W._px[1] and W._px[2], "D: the world map projected both points")
  check(W.drawer and W.drawer.lastApplied
    and (W.drawer.lastApplied.missingDots or 0) == 0,
    "D: the world map painted every planned dot (missingDots=0)")
end

-- ── E. the minimap switch is its own switch (re-scope item 4) ──────────────
do
  ns.GetDB().showMinimap = false
  M:SetRoute(ROUTE)
  local out = sayMinimap()
  check(out:find("minimap verdict: showMinimap is off", 1, true) ~= nil,
    "E: with showMinimap off the minimap says so instead of drawing")
  check(ns.GetDB().showWorldMap == true, "E: turning the minimap off leaves the world map on")
  ns.GetDB().showMinimap = true
  M:SetRoute(ROUTE)
  check(M._stamp ~= nil, "E: turning it back on redraws the same route")
end

-- ── F. the walk recorder captures the same numbers, and survives a /reload ──
do
  local NW = ns.NavWalk
  check(type(NW) == "table", "F: the navwalk recorder is loaded with the minimap module")
  if type(NW) ~= "table" then
    io.stderr:write("FAIL: F: no recorder to drive; the remaining F checks cannot run\n")
    failed = failed + 1
  else
  NW:Begin()
  playerX, playerY = 0.480, 0.300
  M:Redraw()
  local rec = NW:Mark("start")
  check(rec ~= nil, "F: a stop is recorded while a route is drawn")
  check(rec and math.abs(rec.stampX - 0.480) < 1e-9,
    "F: the stop carries the DRAW-TIME fraction, not a later read")
  check(rec and math.abs(rec.playerX - 0.480) < 1e-9,
    "F: the stop carries the client's player coordinates")
  check(rec and type(rec.dotX) == "number" and type(rec.playerSegPx) == "number",
    "F: the stop carries the drawn dot's anchor and the player's distance to its segment")
  check(rec and rec.seg == 1 and rec.index == 1,
    "F: the stop names the route segment and point the dot belongs to")
  playerX = 0.510
  NW:Mark("toward")
  playerX = 0.522
  NW:Mark("past")
  playerX = 0.505
  NW:Mark("back")
  local lines = type(NW.Lines) == "function" and NW:Lines() or {}
  check(#lines == 5, "F: the table has a header plus one line per stop (got " .. #lines .. ")")
  check(lines[1]:find("navwalk: 4 stop(s)", 1, true) ~= nil,
    "F: the header counts the stops (got " .. tostring(lines[1]) .. ")")
  check(lines[5]:find("stop 4", 1, true) ~= nil and lines[5]:find("player=(0.5050,0.3000)", 1, true) ~= nil,
    "F: the last line is the fourth stop with its coordinates (got " .. tostring(lines[5]) .. ")")
  -- The point of the recorder: the numbers leave the session. A /reload writes
  -- NodeTrailDB, and the client's save is what the next run reads.
  check(type(NodeTrailDB) == "table" and type(NodeTrailDB.navwalk) == "table",
    "F: the stops are written into NodeTrailDB.navwalk")
  local saved = NodeTrailDB and NodeTrailDB.navwalk and NodeTrailDB.navwalk.stops or {}
  check(#saved == 4, "F: all four stops are in the saved copy (got " .. tostring(#saved) .. ")")
  check(saved[4] and math.abs((saved[4].playerX or -1) - 0.505) < 1e-9,
    "F: the saved copy keeps the fourth stop's coordinates")
  NW:Clear()
  check(#(NodeTrailDB.navwalk.stops or {}) == 0, "F: clear empties the saved copy too")
  end
end

-- ── G. the SHIPPED projection: the same walk in WORLD mode (yards) ─────────
-- Review round 1: the four-stop table was produced by the pre-HBD build
-- (`mode=frac radius=0.0750 [fallback]`), and the replay above covers only that
-- fallback path. On this client HereBeDragons resolves through LibStub (RXPGuides
-- ships it), so the shipped minimap draws `mode=world radius=C_Minimap.GetViewRadius()`
-- yards — a projection that had never been walked. Same route, same segment, same
-- landmark, same four stops: the scale becomes halfW/radius px per YARD instead
-- of px per map fraction, so every number changes and every invariant must not.
-- This is the fake HereBeDragons that tests/minimap_hbd_spec.lua uses.
do
  local ZONE_W = 1000          -- yd across the zone, one map fraction wide
  local ZONE_H = 800
  local VIEW_RADIUS_YARDS = 233 + 1 / 3
  local HBD = { version = "2.18" }
  function HBD.GetVersion() return HBD.version end
  function HBD.GetZoneSize() return ZONE_W, ZONE_H end
  -- HBD world x grows WEST, y NORTH (`left - width * x`), so the fake does the
  -- same or it would "prove" a mirrored projection.
  function HBD.GetWorldCoordinatesFromZone(_, fx, fy) return -fx * ZONE_W, -fy * ZONE_H, 0 end
  function HBD.GetPlayerWorldPosition() return -playerX * ZONE_W, -playerY * ZONE_H, 0 end
  function HBD.GetPlayerZonePosition() return playerX, playerY, MAPID end
  function HBD.GetWorldDistance(_, inst, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx * dx + dy * dy)
  end
  local library = { ["HereBeDragons-2.0"] = HBD }
  LibStub = setmetatable({}, {
    __call = function(_, name, silent)
      local lib = library[name]
      if lib then return lib end
      if silent then return nil end
      error("LibStub: no library named " .. tostring(name))
    end,
  })
  function LibStub:GetLibrary(name, silent) return LibStub(name, silent) end
  C_Minimap = { GetViewRadius = function() return VIEW_RADIUS_YARDS end }

  playerX, playerY = 0.480, 0.300
  clock = clock + 1
  M:SetRoute(ROUTE)            -- re-indexes the route WITH world coordinates
  W:SetRoute(ROUTE)
  check(M._drawError == nil, "G: world-mode minimap draw error: " .. tostring(M._drawError))
  check(M._proj and M._proj.mode == "world",
    "G: the drawer now projects in world mode (got " .. tostring(M._proj and M._proj.mode) .. ")")
  near(M._proj and M._proj.radius, VIEW_RADIUS_YARDS, 0.01,
    "G: the radius is the client's view radius in yards")
  check(M._proj and M._proj.radiusUnit == "yards",
    "G: and it is labelled yards (got " .. tostring(M._proj and M._proj.radiusUnit) .. ")")
  local out = sayMinimap()
  check(out:find("mode=world", 1, true) ~= nil,
    "G: the diag prints the world mode this build ships (got "
      .. tostring(out:match("minimap projection used:[^\n]*")) .. ")")
  check(out:find("fallback", 1, true) == nil,
    "G: the world-mode draw is not dressing up the fraction fallback")

  local PX_PER_YD = HALF / VIEW_RADIUS_YARDS
  local PX_PER_FRAC_WORLD = ZONE_W * PX_PER_YD   -- 300 px per map fraction east
  local rowsW = {}
  local previousW
  local WORLDMODE_STOPS = {
    { name = "1 start",       x = 0.480, y = 0.300 },
    { name = "2 toward",      x = 0.510, y = 0.300 },
    { name = "3 past it",     x = 0.522, y = 0.300 },
    { name = "4 walked back", x = 0.505, y = 0.300 },
  }
  for i = 1, #WORLDMODE_STOPS do
    local stop = WORLDMODE_STOPS[i]
    playerX, playerY = stop.x, stop.y
    clock = clock + 1.5
    M:Redraw()
    local applied = M.drawer.lastApplied or {}
    -- In world mode the stamp carries the WORLD position the draw used (there is
    -- no map fraction in this projection), so that is the draw-time value to
    -- check — and `playerFrac` being absent is honest, not a missing stamp.
    check(applied.projMode == "world", "G" .. i .. ": the stamp names the projection it used")
    check(type(applied.playerWorld) == "table"
      and math.abs(applied.playerWorld.x - (-playerX * ZONE_W)) < 1e-6,
      ("G%s: the world-mode stamp is this redraw's player position (got %s, player %s)")
        :format(i, tostring(applied.playerWorld and applied.playerWorld.x),
          tostring(-playerX * ZONE_W)))
    -- Review round 3: the world-mode stamp also carries the player's map
    -- fraction now, because the card's four-stop table compares "player
    -- fraction" with "the fraction the draw was built from" on both surfaces.
    -- The projection still uses yards; the fraction is recorded, not used.
    check(type(applied.playerFrac) == "table"
      and math.abs(applied.playerFrac.x - playerX) < 1e-6
      and math.abs(applied.playerFrac.y - playerY) < 1e-6,
      ("G%s: the world-mode stamp carries the player fraction this redraw was at (got %s, player %s,%s)")
        :format(i, tostring(applied.playerFrac and applied.playerFrac.x),
          tostring(playerX), tostring(playerY)))
    local dot, painted = drawnDotCentre()
    check(dot ~= nil and painted > 0, "G" .. i .. ": a dot is drawn in world mode")
    local expectX = (SEG_X - playerX) * ZONE_W * PX_PER_YD
    local expectLandmarkX = (LANDMARK.x - playerX) * ZONE_W * PX_PER_YD
    local audit = (type(M.DrawnAudit) == "function") and M:DrawnAudit() or nil
    local an = audit and audit.nearest
    rowsW[i] = {
      name = stop.name, playerX = playerX, cx = dot and dot.cx, cy = dot and dot.cy,
      dist = dot and dot.dist, toSegment = an and an.playerSegPx, painted = painted,
    }
    near(dot and dot.cx, expectX, 0.75,
      ("G%s: in world mode the dot sits where the yards put it (%.3f yd = %s px)")
        :format(i, (SEG_X - playerX) * ZONE_W, tostring(expectX)))
    check(dot and math.abs(dot.cy) <= 2.0,
      ("G%s: the nearest dot is the perpendicular foot (cy=%s)")
        :format(i, tostring(dot and dot.cy)))
    -- "stays beside the same landmark": a constant west-of-the-landmark offset.
    near((dot and dot.cx or 0) - expectLandmarkX, (SEG_X - LANDMARK.x) * ZONE_W * PX_PER_YD, 0.75,
      ("G%s: the dot keeps the ground's offset from the landmark"):format(i))
    if previousW then
      near((dot and dot.cx or 0) - previousW.cx, -(playerX - previousW.playerX) * PX_PER_FRAC_WORLD, 0.75,
        ("G%s: in world mode the drawn anchor moves opposite the player"):format(i))
    end
    previousW = rowsW[i]
  end
  local function wn(v) return type(v) == "number" and v or nil end
  check(wn(rowsW[2].toSegment) and wn(rowsW[2].toSegment) < wn(rowsW[1].toSegment),
    "G: walking toward the segment shrinks the world-mode distance")
  check(wn(rowsW[3].toSegment) and wn(rowsW[3].toSegment) < wn(rowsW[2].toSegment),
    "G: standing on it is closer than approaching it")
  check(wn(rowsW[4].toSegment) and wn(rowsW[4].toSegment) > wn(rowsW[3].toSegment),
    "G: walking back recedes from it")

  io.write("\nworld mode (radius=" .. string.format("%.3f", VIEW_RADIUS_YARDS) .. " yd, "
    .. string.format("%.2f", PX_PER_YD) .. " px/yd):\n")
  io.write("stop              playerX   anchor cx,cy px   to-segment px   painted\n")
  for i = 1, #rowsW do
    local r = rowsW[i]
    io.write(string.format("%-16s %-8.4f  (%s, %s)      %s            %s\n", r.name, r.playerX,
      r.cx and string.format("%.2f", r.cx) or "absent",
      r.cy and string.format("%.2f", r.cy) or "absent",
      r.toSegment and string.format("%.2f", r.toSegment) or "absent", tostring(r.painted)))
  end
  io.write("\n")
end

if failed > 0 then
  io.stderr:write(failed .. " minimap walk check(s) failed\n")
  os.exit(1)
end
print("minimap_walk_spec: ok")

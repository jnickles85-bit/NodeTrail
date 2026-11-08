-- t_d17939c1 — the arrow itself, against a client model built from what this
-- client has been MEASURED to have:
--
--   * a texture is sized and placed by two corner anchors (LineDraw.TextureProof
--     proved SetStartPoint/SetEndPoint are accepted and keep no geometry);
--   * the minimap reports a view radius in YARDS (233.33 at zoom 0 outdoors, the
--     number the live /nt mapdiag printed);
--   * C_Map.GetPlayerMapPosition answers with 0..1 fractions;
--   * zone size in yards may come from C_Map.GetMapWorldSize, from an installed
--     HereBeDragons, or from neither.
--
-- What this spec pins:
--   A. a target east of the player is drawn east of the minimap centre, at the
--      angle/px the yard scale and the view radius give;
--   B. the label is the whole-yard countdown and it counts DOWN as the player
--      walks, flipping to the next waypoint on arrival;
--   C. a turned minimap rotates the marker the way HereBeDragons-Pins and the
--      minimap line already rotate theirs;
--   D. the yard scale ladder: C_Map.GetMapWorldSize, then HereBeDragons, and
--      when neither answers the arrow hides and SAYS so instead of inventing a
--      scale (a wrong countdown is worse than none);
--   E. hidden when out of range, when switched off, when there is no route;
--   F. /nt navdiag quotes the Step-1 facts as numbers.
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

local function near(a, b, msg, tol)
  tol = tol or 0.05
  check(type(a) == "number" and type(b) == "number" and math.abs(a - b) <= tol,
    (msg or "near") .. " got " .. tostring(a) .. " expected " .. tostring(b))
end

-- ── a minimap client that keeps the geometry it is given ────────────────────
local function newRegion(kind, parent)
  local r = {
    kind = kind,
    parent = parent,
    shown = false,
    points = {},
    textures = {},
    fontStrings = {},
  }
  function r:SetParent(p) self.parent = p end
  function r:GetParent() return self.parent end
  function r:ClearAllPoints() self.points = {} end
  function r:SetPoint(point, rel, relPoint, x, y)
    self.points[#self.points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
  end
  function r:GetNumPoints() return #self.points end
  function r:GetPoint(i)
    local p = self.points[i]
    if not p then return nil end
    return p.point, p.rel, p.relPoint, p.x, p.y
  end
  function r:SetColorTexture(cr, cg, cb, ca) self.color = { cr, cg, cb, ca } end
  function r:SetTexture(path) self.texture = path end
  function r:GetTexture() return self.texture end
  function r:SetVertexColor(cr, cg, cb, ca) self.vertex = { cr, cg, cb, ca } end
  function r:SetDrawLayer(layer, sub) self.layer, self.sub = layer, sub end
  function r:SetBlendMode(mode) self.blend = mode end
  function r:SetTexCoord() end
  function r:SetRotation(rad) self.rotation = rad end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:IsShown() return self.shown end
  function r:IsVisible() return self.shown end
  function r:GetScale() return self.scale or 1 end
  function r:GetAlpha() return 1 end
  function r:CreateTexture()
    local t = newRegion("texture", self)
    table.insert(self.textures, t)
    return t
  end
  function r:CreateFontString(_, _, template)
    local fs = newRegion("fontstring", self)
    fs.template = template
    fs.text = ""
    function fs:SetText(v) self.text = tostring(v or "") end
    function fs:GetText() return self.text end
    function fs:SetFont(path, size, flags) self.font = { path, size, flags } end
    function fs:SetFontObject(obj) self.fontObject = obj end
    function fs:SetTextColor(cr, cg, cb, ca) self.textColor = { cr, cg, cb, ca } end
    function fs:SetJustifyH() end
    function fs:SetJustifyV() end
    table.insert(self.fontStrings, fs)
    return fs
  end
  function r:GetWidth() return self.w or 0 end
  function r:GetHeight() return self.h or 0 end
  return r
end

local UIParent = newRegion("frame", nil)
UIParent.w, UIParent.h = 1920, 1080
UIParent.scale = 1

local Minimap = newRegion("frame", UIParent)
Minimap.w, Minimap.h = 140, 140
Minimap.level = 2
Minimap.scale = 1
Minimap.shown = true
function Minimap:GetZoom() return 0 end
function Minimap:GetFrameLevel() return self.level end
function Minimap:SetFrameLevel(level) self.level = level end
_G.Minimap = Minimap
_G.UIParent = UIParent

function CreateFrame(kind, name, parent)
  local f = newRegion(kind == nil and "frame" or kind, parent or UIParent)
  f.name = name
  f.w, f.h = (parent and parent.w) or 0, (parent and parent.h) or 0
  f.scale = 1
  function f:SetFrameLevel(level) self.level = level end
  function f:GetFrameLevel() return self.level or 0 end
  function f:GetFrameStrata() return "MEDIUM" end
  function f:SetFrameStrata() end
  function f:SetAllPoints(rel)
    local r = rel or self.parent
    if r and r.GetWidth then self.w, self.h = r:GetWidth(), r:GetHeight() end
  end
  function f:SetScript(name_, fn) self.scripts = self.scripts or {}; self.scripts[name_] = fn end
  function f:GetScript(name_) return (self.scripts or {})[name_] end
  function f:RegisterEvent() end
  function f:EnableMouse() end
  function f:EnableMouseWheel() end
  function f:SetMouseClickEnabled() end
  function f:EnableMouseMotion() end
  function f:SetPassThroughButtons() end
  return f
end

_G.GameFontNormalSmall = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 10, "" end }

function CopyTable(t)
  local out = {}
  for k, v in pairs(t) do
    out[k] = type(v) == "table" and CopyTable(v) or v
  end
  return out
end

local chat = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) chat[#chat + 1] = msg end }

-- ── the environment switches this spec flips ─────────────────────────────────
local env = {
  mapID = 1413,
  zoneW = 1000,       -- C_Map.GetMapWorldSize
  zoneH = 1000,
  hasWorldSize = true,
  viewRadius = 233.333,
  playerFrac = { 0.5, 0.5 },
  facing = 0,
  rotate = "0",
  hbd = nil,
}

_G.C_Map = {
  GetBestMapForUnit = function() return env.mapID end,
  GetMapInfo = function() return { name = "The Barrens" } end,
  GetMapWorldSize = function(id)
    if not env.hasWorldSize then return nil end
    if id ~= env.mapID then return nil end
    return env.zoneW, env.zoneH
  end,
  GetPlayerMapPosition = function(id)
    if id ~= env.mapID or not env.playerFrac then return nil end
    local fx, fy = env.playerFrac[1], env.playerFrac[2]
    return { GetXY = function() return fx, fy end }
  end,
}
_G.C_Minimap = { GetViewRadius = function() return env.viewRadius end }
_G.GetCVar = function(name)
  if name == "rotateMinimap" then return env.rotate end
  return nil
end
_G.GetPlayerFacing = function() return env.facing end
_G.LibStub = nil

-- ── load the addon's nav modules exactly as the TOC orders them ─────────────
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
loadAddon("Nav/Target.lua")
loadAddon("Nav/Source.lua")
loadAddon("Nav/Arrow.lua")

local ns = pkg.NodeTrail
local Target = ns.Nav.Target
local Source = ns.Nav.Source
local Arrow = ns.Nav.Arrow
ns.Enable = ns.Enable or function() end

local function core(app, index)
  return app.dots[index]
end

local function centreOf(tex)
  local pts = tex and tex.points or {}
  local a, b = pts[1], pts[2]
  if not a or not b then return nil end
  return (a.x + b.x) * 0.5, (a.y + b.y) * 0.5
end

local function sizeOf(tex)
  local pts = tex and tex.points or {}
  local a, b = pts[1], pts[2]
  if not a or not b then return nil end
  return math.abs((b.x or 0) - (a.x or 0))
end

-- A route with three points, all on one map and all within a sane range.
local function makeRoute(points, mapID)
  return { mapID = mapID or env.mapID, path = points }
end

-- ═══ A. the target east of the player is drawn east of centre ══════════════
-- Player at (0.5,0.5) of a 1000x1000yd zone. Point 1 is 0.1 east (100yd), which
-- with a 233.333yd view radius and a 140px minimap is 100/233.333*70 = 30px.
env.rotate = "0"
env.playerFrac = { 0.5, 0.5 }
local east = makeRoute({
  { x = 0.6, y = 0.5 },
  { x = 0.7, y = 0.5 },
})
Arrow:SetRoute(east)
local head = core(Arrow, 2)   -- 1 = rim, 2 = the arrowhead core
check(head ~= nil, "A: the arrowhead texture exists")
local hx, hy = centreOf(head)
near(hx, 30.0, "A: 100yd east of the player is 30px right of centre", 0.6)
near(hy, 0, "A: and on the centre line", 0.6)
check(Arrow.why == nil, "A: the arrow is drawn (why=" .. tostring(Arrow.why) .. ")")
check(Arrow.last and Arrow.last.index == 1, "A: the first waypoint is named")
check(Arrow.label and Arrow.label.text == "100 yd",
  "A: the label is the yard distance (got " .. tostring(Arrow.label and Arrow.label.text) .. ")")

-- Two dots per marker point: a dark rim under a bright core. The rim is larger.
local rim = core(Arrow, 1)
check(sizeOf(rim) > sizeOf(head), "A: the rim is larger than the core it sits under")
check(rim.sub and head.sub and rim.sub < head.sub, "A: the rim is painted before the core")

-- ═══ B. the countdown, and the flip on arrival ══════════════════════════════
env.playerFrac = { 0.52, 0.5 }
Arrow:Redraw()
near(centreOf(core(Arrow, 2)), 24.0, "B: 20yd closer moves the marker 6px closer", 0.6)
check(Arrow.label.text == "80 yd", "B: the label counts down (got "
  .. tostring(Arrow.label.text) .. ")")

env.playerFrac = { 0.59, 0.5 }   -- 10yd from waypoint 1: inside the 12yd arrival radius
Arrow:Redraw()
check(Arrow.last.index == 2, "B: arriving at waypoint 1 flips the arrow to waypoint 2")
check(Arrow.label.text == "110 yd", "B: and the label restarts for the next leg (got "
  .. tostring(Arrow.label.text) .. ")")

-- Walking BACK over the point just reached must not point back at it.
env.playerFrac = { 0.55, 0.5 }
Arrow:Redraw()
check(Arrow.last.index == 2, "B: walking back keeps the arrow forward (named #"
  .. tostring(Arrow.last.index) .. ")")

-- ═══ C. a turned minimap rotates the marker like the minimap line does ══════
env.rotate = "1"
env.facing = math.pi / 2
env.playerFrac = { 0.5, 0.5 }
Arrow:SetRoute(east)
local rx, ry = centreOf(core(Arrow, 2))
-- Same transform HereBeDragons-Pins applies: x' = x cos f + y sin f,
-- y' = y cos f - x sin f, applied to the projected (30, 0) offset.
near(rx, 30 * math.cos(env.facing) + 0 * math.sin(env.facing),
  "C: a turned minimap rotates the marker's x", 0.6)
near(ry, 0 * math.cos(env.facing) - 30 * math.sin(env.facing),
  "C: a turned minimap rotates the marker's y", 0.6)
env.rotate = "0"
env.facing = 0

-- A turned minimap with no GetPlayerFacing() hides instead of guessing north.
env.rotate = "1"
local realFacing = _G.GetPlayerFacing
_G.GetPlayerFacing = nil
Arrow:Redraw()
check(Arrow.why and Arrow.why:find("GetPlayerFacing"), "C: no facing on a turned minimap is named ("
  .. tostring(Arrow.why) .. ")")
_G.GetPlayerFacing = realFacing
env.rotate = "0"

-- ═══ D. the yard-scale ladder ═══════════════════════════════════════════════
env.playerFrac = { 0.5, 0.5 }
-- (1) GetMapWorldSize is absent but HereBeDragons is installed: its zone size
--     answers, and the same 100yd leg is still 100yd.
env.hasWorldSize = false
Source.ForgetCache()
local hbdCalls = 0
_G.LibStub = {
  GetLibrary = function(_, major)
    if major ~= "HereBeDragons-2.0" then return nil end
    return {
      MAJOR = "HereBeDragons-2.0",
      MINOR = 35,
      GetZoneSize = function(_, id)
        hbdCalls = hbdCalls + 1
        if id ~= env.mapID then return 0, 0 end
        return 1000, 1000
      end,
      GetPlayerWorldPosition = function() return 12.5, -7.5, 0 end,
      GetWorldCoordinatesFromZone = function(_, fx, fy)
        return (0.5 - fx) * 1000, (0.5 - fy) * 1000, 0
      end,
      GetWorldVector = function(_, instance, ox, oy, dx, dy)
        local ddx, ddy = dx - ox, dy - oy
        return math.atan2(ddx, ddy), math.sqrt(ddx * ddx + ddy * ddy)
      end,
    }
  end,
}
Arrow:SetRoute(east)
check(Arrow.why == nil, "D1: HereBeDragons' zone size is used when the client has none ("
  .. tostring(Arrow.why) .. ")")
near(centreOf(core(Arrow, 2)), 30.0, "D1: the same 100yd leg is still 30px", 0.6)
check(hbdCalls > 0, "D1: HBD:GetZoneSize was actually asked")
check(Source.ZoneSize(env.mapID) == 1000, "D1: the zone size is reported as 1000yd")

-- (2) neither answers: no arrow, and a message that says why.
_G.LibStub = nil
env.hasWorldSize = false
Source.ForgetCache()
chat = {}
Arrow:SetRoute(east)
check(Arrow.why ~= nil, "D2: with no yard scale the arrow is hidden")
check(Arrow.why:find("yard scale"), "D2: and the reason names the missing scale ("
  .. tostring(Arrow.why) .. ")")
local said = table.concat(chat, "\n")
check(said:find("waypoint arrow is off") ~= nil,
  "D2: the player is told, once, that there is no yard scale")
Arrow:Redraw()
check(select(2, table.concat(chat, "\n"):gsub("waypoint arrow is off", "")) == 1,
  "D2: the message is said once, not on every refresh")

-- ═══ E. hidden when out of range, off, or with no route ═════════════════════
env.hasWorldSize = true
Source.ForgetCache()
ns.GetDB().showNavArrow = true
Arrow:SetRoute(makeRoute({ { x = 0.5, y = 0.05 }, { x = 0.5, y = 0.08 } }))
-- 0.45 of a 1000yd tall zone = 450yd away: still inside 1200.
check(Arrow.why == nil, "E: 450yd away is inside the default range")
Arrow:SetRoute(makeRoute({ { x = 0.5, y = -2.5 }, { x = 0.5, y = -2.0 } }))
-- The nearest point of this route is 0.5 - (-2.5) = 3 zones = 3000yd away.
check(Arrow.why ~= nil and Arrow.why:find("range"), "E: 3000yd away is past the range ("
  .. tostring(Arrow.why) .. ")")
check(Arrow.host and Arrow.host.shown == false, "E: and nothing is left on screen")

Arrow:SetRoute(east)
ns.GetDB().showNavArrow = false
Arrow:Redraw()
check(Arrow.why and Arrow.why:find("showNavArrow"), "E: the switch hides it ("
  .. tostring(Arrow.why) .. ")")
check(Arrow.last == nil,
  "E: a hidden arrow reports no measurement instead of the previous draw's")
ns.GetDB().showNavArrow = true

Arrow:Clear()
check(Arrow.why == "no active route", "E: no route hides it")
check(Arrow.host.shown == false, "E: no route leaves nothing on screen")

-- ═══ F. /nt navdiag quotes the numbers ══════════════════════════════════════
chat = {}
_G.LibStub = {
  GetLibrary = function(_, major)
    if major ~= "HereBeDragons-2.0" then return nil end
    return {
      MAJOR = "HereBeDragons-2.0",
      MINOR = 35,
      GetZoneSize = function() return 1000, 1000 end,
      GetPlayerWorldPosition = function() return 12.5, -7.5, 0 end,
      GetWorldCoordinatesFromZone = function(_, fx, fy)
        return (0.5 - fx) * 1000, (0.5 - fy) * 1000, 0
      end,
      GetWorldVector = function(_, instance, ox, oy, dx, dy)
        local ddx, ddy = dx - ox, dy - oy
        return math.atan2(ddx, ddy), math.sqrt(ddx * ddx + ddy * ddy)
      end,
    }
  end,
}
Source.ForgetCache()
Arrow:SetRoute(east)
chat = {}
local lines = Arrow.Diag(Arrow)
local body = table.concat(lines, "\n")
check(type(lines) == "table" and #lines > 5, "F: navdiag prints a block of facts")
check(body:find("C_Map: present") ~= nil, "F: navdiag starts with the C_Map surface")
check(body:find("GetWorldPosFromMapPos=absent") ~= nil,
  "F: navdiag names each C_Map call it did not find")
check(body:find("HereBeDragons%-2.0: reachable") ~= nil,
  "F: navdiag says whether HereBeDragons is reachable")
check(body:find("zone size for map 1413: 1000%.0 x 1000%.0 yd") ~= nil,
  "F: navdiag quotes the zone size in yards (" .. tostring(body:match("zone size[^\n]*")) .. ")")
check(body:find("HBD:GetPlayerWorldPosition%(%)") ~= nil,
  "F: navdiag quotes the raw world position")
check(body:find("GetWorldVector from the player to the route ends") ~= nil,
  "F: navdiag quotes the world vector to the route's first and last points")
check(body:find("first angle=") ~= nil, "F: with the first point's angle and distance")
check(body:find("last angle=") ~= nil, "F: and the last point's")
check(body:find("GetPlayerFacing%(%)") ~= nil, "F: navdiag quotes GetPlayerFacing")
check(body:find("minimap view radius: 233%.33 yd") ~= nil,
  "F: navdiag quotes the minimap's yard radius")
check(body:find("arrow target: next=point #1") ~= nil,
  "F: navdiag says which point the arrow is aiming at (" ..
    tostring(body:match("arrow target:[^\n]*")) .. ")")

-- The Step-1 verdict when nothing is reachable must be equally plain.
_G.LibStub = nil
_G.C_Map.GetMapWorldSize = nil
Source.ForgetCache()
chat = {}
lines = Arrow.Diag(Arrow)
body = table.concat(lines, "\n")
check(body:find("HereBeDragons%-2.0: not reachable") ~= nil,
  "F: a client without HereBeDragons says so")
check(body:find("no yard scale") ~= nil,
  "F: and that there is no yard scale at all")

if failed > 0 then
  io.stderr:write(failed .. " check(s) failed\n")
  os.exit(1)
end
print("nav_arrow_spec: ok")

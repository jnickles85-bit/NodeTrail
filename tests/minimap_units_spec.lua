-- t_86583cf2 — the minimap must never mix coordinate SPACES, and "nothing
-- drawn" must name the distance that decided it.
--
-- Review round 3 read one diag line and found two problems:
--
--   `minimap crosscheck: ... #1 world=(429.8,89.5)` printed the WORLD MAP'S
--   CANVAS PIXEL under the label "world", so a reader reasonably concluded the
--   yards projection was being fed canvas pixels. One label, two spaces. The
--   crosscheck now prints frac=, canvas= and worldYd= side by side, each
--   labelled, and nothing may be mistaken for another space.
--
--   `minimap projection: points=37 useWorld=true` was set when ANY point had
--   world coordinates; the rest were then silently dropped by the projection
--   because they had no delta. A partial world set now falls back to the
--   zone/fraction projection (where every point has a fraction) and the diag
--   says how many points failed to convert and why.
--
--   `minimap verdict: none of the 36 segment(s) reach the minimap: 37 of 37
--   point(s) project outside the 95px circle` never said HOW far the nearest
--   route point was. Five radii away is a player off the route; a wrong
--   projection looks the same in that line. The verdict now carries the nearest
--   point, its distance in the projection's units, and the radius it is
--   compared with.
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
  function r:GetWidth() return self.width or 0 end
  function r:GetHeight() return self.height or 0 end
  function r:SetParent(p) self.parent = p end
  function r:GetParent() return self.parent end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:IsShown() return self.shown end
  function r:IsVisible() return self.shown end
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

local function newFrame(name, parent)
  local f = newRegion("Frame")
  f.name = name
  f.parent = parent
  f.scripts = {}
  f.level, f.strata = 1, "MEDIUM"
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:GetScript(n) return self.scripts[n] end
  function f:HookScript(n, fn) self.scripts[n] = fn end
  function f:RegisterEvent() end
  function f:UnregisterEvent() end
  function f:GetName() return self.name end
  function f:SetSize(w, h) self.width, self.height = w, h end
  function f:SetAllPoints() end
  function f:SetClipsChildren() end
  function f:EnableMouse() end
  function f:EnableMouseWheel() end
  function f:SetFrameLevel(l) self.level = l end
  function f:GetFrameLevel() return self.level end
  function f:SetFrameStrata(s) self.strata = s end
  function f:GetFrameStrata() return self.strata end
  function f:CreateTexture() return newRegion("Texture") end
  function f:CreateFontString() return newRegion("FontString") end
  return f
end

function CreateFrame(kind, name, parent)
  return newFrame(name, parent)
end

function CopyTable(t)
  local out = {}
  for k, v in pairs(t) do out[k] = type(v) == "table" and CopyTable(v) or v end
  return out
end

local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
SlashCmdList = {}
local clock = 0
function GetTime() return clock end

local MAPID = 1413
local playerX, playerY = 0.4800, 0.3000
function GetPlayerMapPosition(unit)
  if unit == "player" then return playerX, playerY end
  return 0, 0
end

local zoom = 0
Minimap = newFrame("Minimap")
Minimap.width, Minimap.height = 140, 140
function Minimap:GetZoom() return zoom end
function Minimap:IsVisible() return true end
function GetCVar(name)
  if name == "rotateMinimap" then return "0" end
  if name == "minimapZoom" then return tostring(zoom) end
  return nil
end
function GetMinimapShape() return "ROUND" end

local VIEW_RADIUS_YARDS = 233 + 1 / 3
C_Minimap = { GetViewRadius = function() return VIEW_RADIUS_YARDS end }

-- ── HereBeDragons with a converter that can REFUSE a point ─────────────────
-- `convertAll = false` makes the second half of the zone fail to convert, the
-- way a real map lookup can come back nil for a point on a sub-map the library
-- does not know. That is the case the old `anyWorld` flag turned into a world
-- projection that silently dropped the unconvertible points.
local ZONE_W, ZONE_H = 1000, 800
local convertAll = true
local HBD = { version = "2.18" }
function HBD.GetVersion() return HBD.version end
function HBD.GetZoneSize() return ZONE_W, ZONE_H end
function HBD.GetWorldCoordinatesFromZone(_, fx, fy)
  if not convertAll and fx > 0.6 then
    return nil, nil, nil
  end
  return -fx * ZONE_W, -fy * ZONE_H, 0
end
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

local canvas = newFrame("WorldMapFrameCanvas")
canvas.width, canvas.height = 1002, 668
local mapFrame = newFrame("WorldMapFrame")
mapFrame.width, mapFrame.height = 1002, 668
function mapFrame:GetCanvas() return canvas end
function mapFrame:GetCanvasScale() return 0.696 end
function mapFrame:GetMapID() return MAPID end
WorldMapFrame = mapFrame
UIParent = newFrame("UIParent")
UIParent.width, UIParent.height = 2133, 1200

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
ns.GetPlayerMapID = function() return MAPID end

local function diag()
  chat = {}
  M:Diag()
  return table.concat(chat, "\n")
end

local function line(out, prefix)
  for l in (out .. "\n"):gmatch("(.-)\n") do
    if l:find(prefix, 1, true) then return l end
  end
  return nil
end

-- A route that crosses the "does not convert" line: point 1 converts, point 2
-- does not, and both are within the minimap radius of the player.
local MIXED_ROUTE = {
  mapID = MAPID,
  path = {
    { x = 0.500, y = 0.290 },
    { x = 0.680, y = 0.310 },
  },
}

-- ── 1. a partial world conversion must NOT be called a world projection ────
convertAll = false
clock = clock + 1
M:SetRoute(MIXED_ROUTE)
local out = diag()
local proj = line(out, "minimap projection:")
check(proj ~= nil, "1: the diag prints the projection header")
check(proj ~= nil and proj:find("useWorld=false", 1, true) ~= nil,
  "1: one unconvertible point turns the world projection OFF (got " .. tostring(proj) .. ")")
check(proj ~= nil and proj:find("worldPoints=1/2", 1, true) ~= nil,
  "1: and the header says how many points converted (got " .. tostring(proj) .. ")")
check(proj ~= nil and proj:find("world projection OFF: HereBeDragons converted 1 of 2 point(s)", 1, true) ~= nil,
  "1: naming the reason instead of dropping the point silently (got " .. tostring(proj) .. ")")
local used = line(out, "minimap projection used:")
check(used ~= nil and used:find("mode=world", 1, true) == nil,
  "1: the draw does not use world mode with an incomplete world set (got " .. tostring(used) .. ")")
local points = line(out, "minimap points:")
check(points ~= nil and points:find("no delta", 1, true) == nil,
  "1: every point still projects (no point dropped for lacking world coordinates) (got "
    .. tostring(points) .. ")")
local applied = ns.LineDraw.Applied(M.drawer) or {}
check((tonumber(applied.paintedDots) or 0) > 0,
  "1: and the minimap still draws the route (painted=" .. tostring(applied.paintedDots) .. ")")

-- ── 2. the three spaces, each labelled, in one crosscheck line ─────────────
convertAll = true
clock = clock + 1
M:SetRoute(MIXED_ROUTE)
out = diag()
local cross = out:match("minimap crosscheck:[^\n]*")
check(cross ~= nil, "2: the point-by-point crosscheck is printed")
check(cross ~= nil and cross:find("#1 frac=", 1, true) ~= nil,
  "2: it labels the route point's map fraction as `frac` (got " .. tostring(cross) .. ")")
check(cross ~= nil and cross:find(" canvas=", 1, true) ~= nil,
  "2: it labels the world map's pixel as `canvas`, not `world` (got " .. tostring(cross) .. ")")
check(cross ~= nil and cross:find(" worldYd=", 1, true) ~= nil,
  "2: and prints the HereBeDragons yards as `worldYd` (got " .. tostring(cross) .. ")")
check(cross ~= nil and cross:find("#1 world=", 1, true) == nil,
  "2: the ambiguous `world=` label is gone (got " .. tostring(cross) .. ")")
-- The numbers themselves: fraction 0.500 of a 1000-yd zone is -500 world yd.
check(cross ~= nil and cross:find("worldYd=(-500.0,", 1, true) ~= nil,
  "2: the printed yards are the library's world coordinates (got " .. tostring(cross) .. ")")

-- ── 3. nothing drawn must name the distance that decided it ────────────────
-- Move the player far from the route in the same zone: the nearest route point
-- is ~600 yd away against a 233-yd radius, so the draw is correct to show
-- nothing — and the verdict has to say that with numbers.
playerX, playerY = 0.05, 0.05
clock = clock + 1
M:Redraw()
local verdict = line(diag(), "minimap verdict:")
check(verdict ~= nil and verdict:find("nearest point #1 is", 1, true) ~= nil,
  "3: the verdict names the nearest route point (got " .. tostring(verdict) .. ")")
check(verdict ~= nil and verdict:find("yd", 1, true) ~= nil,
  "3: and its distance in yards (got " .. tostring(verdict) .. ")")
check(verdict ~= nil and verdict:find("x-radius", 1, true) ~= nil,
  "3: and the radius multiple the reader compares it with (got " .. tostring(verdict) .. ")")
check(verdict ~= nil and verdict:find("the minimap covers 233.3 yd", 1, true) ~= nil,
  "3: and the radius it was compared against (got " .. tostring(verdict) .. ")")
local nearestPx = verdict and tonumber(verdict:match("nearest point #%d+ is ([%d%.]+)px"))
local nearestYd = verdict and tonumber(verdict:match("= ([%d%.]+) yd"))
check(nearestPx ~= nil and nearestYd ~= nil and nearestYd > VIEW_RADIUS_YARDS,
  "3: the nearest point really is outside the radius (" .. tostring(nearestYd) .. " yd)")
if nearestPx and nearestYd then
  near(nearestYd, nearestPx * VIEW_RADIUS_YARDS / 70, 2,
    "3: and the yards are the pixels through the measured scale")
end

if failed > 0 then
  io.stderr:write(("minimap_units_spec: %d failure(s)\n"):format(failed))
  os.exit(1)
end
print("minimap_units_spec: ok")

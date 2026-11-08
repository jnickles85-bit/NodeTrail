-- t_86583cf2 — the minimap projection must be a MEASUREMENT, not the 0.075 guess.
--
-- The live diag printed `radius=0.0750 [map fractions (fallback: no yard radius
-- for this zone)]` on a client that has HereBeDragons loaded — because the only
-- place this addon looked for the library was `GatherMate2.HBD`, and GatherMate2
-- is not installed there. RXPGuides ships the same library as a LibStub library
-- (`RXPGuides/libs/HereBeDragons`), so the yards are available on this client.
--
-- This spec gives the addon a LibStub HereBeDragons and requires:
--   1. the diag names the source it used (and the version);
--   2. the draw switches to world/yard mode with the client's view radius — the
--      fallback fraction must NOT be used when a yard radius exists;
--   3. the dots land at the pixel offset the yards imply (so the scale is the
--      measured one, not a constant that happens to look plausible);
--   4. with the library gone the draw falls back, says so, and says the scale
--      could not be measured — honest degradation, not a silent guess.
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

-- The client's OWN minimap view radius, in yards. When this answers, the
-- projection has no business using a fraction constant.
local VIEW_RADIUS_YARDS = 233 + 1 / 3
C_Minimap = { GetViewRadius = function() return VIEW_RADIUS_YARDS end }

-- ── HereBeDragons, as RXPGuides ships it: a LibStub library ────────────────
-- One map fraction is 1000 yd wide and 800 yd tall in this zone, so a point
-- 0.02 east of the player is 20 yd away — a number the spec can check against
-- the pixels the drawer asked for.
local ZONE_W, ZONE_H = 1000, 800
local HBD = { version = "2.18" }
function HBD.GetVersion() return HBD.version end
function HBD.GetZoneSize(_, mapID) return ZONE_W, ZONE_H end
-- HereBeDragons' world coordinates run the OTHER way from UI map fractions:
-- `left - width * x` (HereBeDragons-2.0.lua, GetWorldCoordinatesFromZone), so
-- world x increases WEST and world y increases NORTH. The fake has to use the
-- same convention or it would "prove" a mirrored projection.
function HBD.GetWorldCoordinatesFromZone(_, fx, fy, mapID) return -fx * ZONE_W, -fy * ZONE_H, 0 end
function HBD.GetPlayerWorldPosition(_) return -playerX * ZONE_W, -playerY * ZONE_H, 0 end
function HBD.GetPlayerZonePosition(_) return playerX, playerY, MAPID end
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

-- ── The world map exists (the minimap module shares PathGeom with it) ──────
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

-- A route segment 0.02 map-fractions east of the player, running north-south.
local ROUTE = {
  mapID = MAPID,
  path = {
    { x = playerX + 0.020, y = 0.290 },
    { x = playerX + 0.020, y = 0.310 },
  },
}

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

-- ── 1. the library is found where it actually lives ───────────────────────
clock = clock + 1
M:SetRoute(ROUTE)
local out = diag()
local source = line(out, "minimap hereBeDragons:")
check(source ~= nil, "1: the diag names the HereBeDragons source it used")
check(source ~= nil and source:find("LibStub:HereBeDragons-2.0", 1, true) ~= nil,
  "1: it found the library through LibStub, not only through GatherMate2 (got "
    .. tostring(source) .. ")")
check(source ~= nil and source:find("version=2.18", 1, true) ~= nil,
  "1: and reports the version the library answered (got " .. tostring(source) .. ")")

-- ── 2. the draw uses the MEASURED radius, not the fraction fallback ───────
local p = M._proj
check(type(p) == "table", "2: the redraw measured a projection")
check(p and p.mode == "world",
  "2: with world coordinates available the draw uses world mode (got " .. tostring(p and p.mode) .. ")")
near(p and p.radius, VIEW_RADIUS_YARDS, 0.01,
  "2: the radius is the client's view radius in yards")
check(p and p.radiusUnit == "yards",
  "2: and the unit says yards (got " .. tostring(p and p.radiusUnit) .. ")")
local used = line(out, "minimap projection used:")
check(used ~= nil and used:find("mode=world", 1, true) ~= nil
  and used:find("radius=" .. string.format("%.4f", VIEW_RADIUS_YARDS), 1, true) ~= nil,
  "2: the diag prints the measured mode and radius (got " .. tostring(used) .. ")")
check(used ~= nil and used:find("fallback", 1, true) == nil,
  "2: the fallback is not what this draw used (got " .. tostring(used) .. ")")

-- ── 3. the dots sit at the pixel offset the YARDS imply ──────────────────
-- 20 yd east of the player at a 233.33 yd half-width of 70 px = 6.00 px east.
local HALF = 70
local expected = HALF * (0.020 * ZONE_W) / VIEW_RADIUS_YARDS
local audit = M:DrawnAudit()
check(type(audit) == "table" and audit.nearest ~= nil, "3: a dot was drawn")
if audit and audit.nearest then
  near(audit.nearest.cx, expected, 1.0,
    "3: the drawn dot's x offset is the yard distance over the measured radius")
end

-- ── 4. the scale audit cross-checks yards against the drawn pixels ───────
local auditLine = line(out, "minimap scale audit:")
check(auditLine ~= nil and auditLine:find("yd /", 1, true) ~= nil,
  "4: the scale audit measures yards per drawn pixel (got " .. tostring(auditLine) .. ")")
check(auditLine ~= nil and auditLine:find("FALLBACK", 1, true) == nil,
  "4: and does not report that the draw used the fallback (got " .. tostring(auditLine) .. ")")
if auditLine then
  local implied = tonumber(auditLine:match("implied view radius=([%d%.]+) yd"))
  near(implied, VIEW_RADIUS_YARDS, 2.0,
    "4: the radius implied by the drawn pixels matches the client's view radius")
end

-- ── 5. no library: fall back, and SAY the scale was not measured ─────────
library["HereBeDragons-2.0"] = nil
playerX = playerX + 0.001
clock = clock + 1
M:SetRoute(ROUTE)
out = diag()
local absent = line(out, "minimap hereBeDragons:")
check(absent ~= nil and absent:find("absent", 1, true) ~= nil,
  "5: with the library gone the diag says it is absent (got " .. tostring(absent) .. ")")
local fallbackUsed = line(out, "minimap projection used:")
check(fallbackUsed ~= nil and fallbackUsed:find("fallback", 1, true) ~= nil,
  "5: and the projection says it fell back (got " .. tostring(fallbackUsed) .. ")")
local fallbackAudit = line(out, "minimap scale audit:")
check(fallbackAudit ~= nil and fallbackAudit:find("absent", 1, true) ~= nil,
  "5: and the scale audit says the scale could not be measured (got "
    .. tostring(fallbackAudit) .. ")")
check(M._proj and M._proj.radiusUnit ~= "yards",
  "5: the fallback draw is not dressed up as a measured one")

if failed > 0 then
  io.stderr:write(("minimap_hbd_spec: %d failure(s)\n"):format(failed))
  os.exit(1)
end
print("minimap_hbd_spec: ok")

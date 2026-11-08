-- t_c0a68ed2 — the minimap half of /nt mapdiag. The live report was
-- `points=3 useWorld=false radius=233.33` with `queued=0 segments`: three
-- projected points and nothing drawn. That number cannot tell "the route is
-- outside the minimap's view" apart from "the projection never ran", so the
-- diag now records the sample it actually used (mode, radius, unit), every
-- point's pixel position and distance in radii, and every segment's clip
-- decision — and the fraction fallback scales with the minimap zoom instead of
-- drawing the same size at every zoom step.
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
  check(type(a) == "number" and math.abs(a - b) < 0.3,
    (msg or "near") .. " got " .. tostring(a) .. " expected " .. tostring(b))
end

function CreateFrame(kind, name, parent)
  local f = { kind = kind, name = name, parent = parent, scripts = {}, shown = false }
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:GetScript(n) return self.scripts[n] end
  function f:HookScript(n, fn) self.scripts[n] = fn end
  function f:RegisterEvent() end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:IsShown() return self.shown end
  function f:GetWidth() return 0 end
  function f:GetHeight() return 0 end
  return f
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

-- Zoom is the variable under test: the client reports it through Minimap and
-- through the minimapZoom cvar, exactly as the draw code reads it.
local zoom = 0
Minimap = { width = 140, height = 140 }
function Minimap:GetWidth() return self.width end
function Minimap:GetHeight() return self.height end
function Minimap:GetZoom() return zoom end
function Minimap:IsVisible() return true end
function Minimap:GetName() return "Minimap" end

function GetCVar(name)
  if name == "rotateMinimap" then
    return "0"
  end
  if name == "minimapZoom" then
    return tostring(zoom)
  end
  return nil
end

function GetMinimapShape() return "ROUND" end

-- No C_Minimap / C_Map vector API: the legacy position call is what this client
-- exposes, and the yard radius falls back to the diameter table.
local playerX, playerY = 0.5, 0.5
function GetPlayerMapPosition(unit)
  if unit == "player" then
    return playerX, playerY
  end
  return 0, 0
end

local mapID = 1413
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
ns.GetPlayerMapID = function() return mapID end

local function say()
  chat = {}
  M:Diag()
  return table.concat(chat, "\n")
end

-- ── 0. nothing redrawn yet: the verdict must not claim a draw ─────────────
-- `_why` is nil both after a redraw that queued segments and before any redraw
-- at all, so "drew segments" used to be printed for a state that never drew.
local freshOut = say()
check(freshOut:find("minimap verdict: no redraw on a usable minimap sample yet", 1, true) ~= nil,
  "0: with no redraw at all the verdict says so (got "
    .. tostring(freshOut:match("minimap verdict:[^\n]*")) .. ")")
check(freshOut:find("minimap verdict: drew segments", 1, true) == nil,
  "0: the verdict does not claim a draw that never happened")

-- ── A. a route point inside the minimap view is drawn ─────────────────────
M:SetRoute({ mapID = mapID, path = { { x = 0.50, y = 0.50 }, { x = 0.52, y = 0.50 } } })
check(M._drawError == nil, "A: draw error: " .. tostring(M._drawError))
check(M._lastQueued == 1, "A: one segment queued (got " .. tostring(M._lastQueued) .. ")")
check(M._proj ~= nil, "A: the projection is recorded for the diag")
check(M._proj and M._proj.mode == "frac", "A: the sample mode is recorded")
check(M._proj and type(M._proj.radiusUnit) == "string", "A: the radius unit is recorded")
near(M._proj and M._proj.points[2] and M._proj.points[2].x, 0.02 / 0.075 * 70,
  "A: the second point projects with the fraction fallback")

local out = say()
for _, needle in ipairs({
  "minimap projection used: mode=frac radius=0.0750",
  "minimap points: #1 px=(0.0,0.0)",
  "#2 px=(18.7,0.0) dist=0.28x-radius inside",
  "minimap segments: seg1 queued",
  -- Requirement: one line per consecutive pair, with both projected
  -- coordinates, both radius tests and one named reason.
  "minimap pairs: 1->2 (0.0,0.0) (18.7,0.0), 0.00x-radius inside 0.28x-radius inside, => queued",
  "minimap verdict: drew segments",
}) do
  check(out:find(needle, 1, true) ~= nil, "A: minimap diag missing: " .. needle)
end
check(out:find("minimap drawError=none", 1, true) ~= nil, "A: no draw error")

-- ── B. a route entirely outside the view says WHY, per point and per segment ─
M:SetRoute({ mapID = mapID, path = { { x = 0.90, y = 0.90 }, { x = 0.95, y = 0.95 } } })
check(M._lastQueued == 0, "B: nothing queued for a route 0.4 map away (got " .. tostring(M._lastQueued) .. ")")
check(M._why ~= nil, "B: the diag records a reason")
check(M._why and M._why:find("outside", 1, true) ~= nil,
  "B: the reason names the out-of-view points (got " .. tostring(M._why) .. ")")
out = say()
for _, needle in ipairs({
  "OUTSIDE",
  "minimap segments: seg1 skipped: clipped away",
  -- The dropped segment must carry ONE of the four named reasons, with both
  -- projected coordinates and both radius tests in the same line.
  "minimap pairs: 1->2 (373.3,-373.3) (420.0,-420.0), 7.86x-radius OUTSIDE 8.84x-radius OUTSIDE, => outside-radius",
  "minimap verdict: none of the 1 segment(s) reach the minimap",
}) do
  check(out:find(needle, 1, true) ~= nil, "B: minimap diag missing: " .. needle)
end

-- ── C. the fraction fallback follows the minimap zoom ─────────────────────
-- Before the fix the fallback radius was a constant, so the same route drew at
-- the same pixel size at every zoom step — a route that is visible at zoom 0
-- stayed "visible" at zoom 5 and vice versa, with no way to tell from the diag.
M:SetRoute({ mapID = mapID, path = { { x = 0.50, y = 0.50 }, { x = 0.52, y = 0.50 } } })
zoom = 0
M:Redraw()
local wideRadius = M._proj and M._proj.radius
local wideX = M._proj and M._proj.points[2] and M._proj.points[2].x
zoom = 5
M:Redraw()
local tightRadius = M._proj and M._proj.radius
local tightX = M._proj and M._proj.points[2] and M._proj.points[2].x
check(type(wideRadius) == "number" and type(tightRadius) == "number",
  "C: both zoom steps produce a fraction radius")
check(tightRadius < wideRadius,
  "C: zooming in shrinks the fallback view radius (got " .. tostring(tightRadius)
    .. " vs " .. tostring(wideRadius) .. ")")
check(type(tightX) == "number" and type(wideX) == "number" and tightX > wideX,
  "C: the same point moves further out on the minimap when zoomed in (got "
    .. tostring(tightX) .. " vs " .. tostring(wideX) .. ")")
near(tightRadius, 0.075 * (133.333333333333 / (466 + 2 / 3)), "C: the radius follows the diameter table")
check(M._lastQueued == 1, "C: the near route is still drawn when zoomed in")

-- ── D. /nt mapdiag prints the minimap half through MapOverlay:Diag ────────
zoom = 0
M:Redraw()
chat = {}
ns.MapOverlay:Diag()
local joined = table.concat(chat, "\n")
check(joined:find("minimap projection used: mode=frac", 1, true) ~= nil,
  "D: /nt mapdiag carries the minimap projection")
check(joined:find("minimap segments:", 1, true) ~= nil, "D: /nt mapdiag carries the segment decisions")
check(joined:find("WorldMapFrame: absent", 1, true) ~= nil,
  "D: the world-map half still reports its own absence without erroring")
check(joined:find("error:", 1, true) == nil, "D: /nt mapdiag printed no error line")

if failed > 0 then
  io.stderr:write(failed .. " minimap diag check(s) failed\n")
  os.exit(1)
end
print("minimap_diag_spec: ok")

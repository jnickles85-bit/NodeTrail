-- t_c0a68ed2 — the world-map line is QUEUED but INVISIBLE. This spec pins the
-- two things the in-game diag has to prove, on a client shaped like the one that
-- failed: a map canvas whose ART is a frame SIBLING of the overlay, at a HIGHER
-- frame level than the overlay used to pick (`canvas level + 10`).
--
-- Why that shape: the canvas system draws its map art with detail-layer frames
-- parented to the canvas (MapCanvasDetailLayerTemplate, useParentLevel), and the
-- 1.12-derived clients reparent WorldMapDetailFrame INTO the canvas. Either way
-- the art and the overlay are siblings, so the overlay only wins by MEASURED
-- frame level — a host at canvas+10 lands under art at, say, level 40 and the
-- line is drawn with no error and nothing on screen.
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
  check(type(a) == "number" and math.abs(a - b) < 0.15,
    (msg or "near") .. " got " .. tostring(a) .. " expected " .. tostring(b))
end

-- ── client stub: frames with real levels, children, parents, regions ────────
local function makeFrame(name, parent)
  local f = {
    name = name,
    parent = parent,
    children = {},

    level = 0,
    strata = "MEDIUM",
    shown = true,
    width = 0,
    height = 0,
    scripts = {},
    pool = {},
  }
  function f:GetName() return self.name end
  function f:GetParent() return self.parent end
  function f:SetParent(p) self.parent = p end
  function f:GetFrameLevel() return self.level end
  function f:SetFrameLevel(l) self.level = l end
  function f:GetFrameStrata() return self.strata end
  function f:SetFrameStrata(s) self.strata = s end
  function f:IsShown() return self.shown end
  function f:IsVisible() return self.shown end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:GetAlpha() return self.alpha or 1 end
  function f:GetWidth() return self.width end
  function f:GetHeight() return self.height end
  function f:SetWidth(w) self.width = w end
  function f:SetHeight(h) self.height = h end
  function f:SetSize(w, h) self.width, self.height = w, h end
  function f:GetChildren() return self.children end
  function f:ClearAllPoints() self.points = {} end
  function f:SetAllPoints(rel)
    self.allPoints = rel or self.parent
    -- A real client sizes the frame from the relative frame; mirror that so a
    -- diag reading GetWidth cannot be fooled by a test-only zero size.
    if self.allPoints and self.allPoints.GetWidth then
      self.width = self.allPoints.GetWidth(self.allPoints)
      self.height = self.allPoints.GetHeight(self.allPoints)
    end
  end
  function f:SetPoint(...) self.points = { ... } end
  function f:GetPoint() return nil end
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:GetScript(n) return self.scripts[n] end
  function f:HookScript(n, fn)
    self.hooks = self.hooks or {}
    self.hooks[n] = self.hooks[n] or {}
    table.insert(self.hooks[n], fn)
  end
  function f:RegisterEvent() end
  function f:EnableMouse() end
  function f:EnableMouseWheel() end
  function f:CreateLine(_, layer)
    local line = {
      kind = "line",
      layer = layer,
      shown = false,
      level = self.level,
      thickness = 0,
      color = {},
    }
    function line:SetParent(p) self.parent = p end
    function line:SetStartPoint(p, rel, rp, x, y)
      self.start = { p, rel, rp, x, y }
    end
    function line:SetEndPoint(p, rel, rp, x, y)
      self.stop = { p, rel, rp, x, y }
    end
    function line:GetStartPoint()
      if not self.start then return nil end
      return self.start[1], self.start[2], self.start[3], self.start[4], self.start[5]
    end
    function line:GetEndPoint()
      if not self.stop then return nil end
      return self.stop[1], self.stop[2], self.stop[3], self.stop[4], self.stop[5]
    end
    function line:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function line:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
    function line:SetThickness(t) self.thickness = t end
    function line:GetThickness() return self.thickness end
    function line:GetAlpha() return self.color and self.color[4] or nil end
    function line:Hide() self.shown = false end
    function line:Show() self.shown = true end
    function line:IsShown() return self.shown end
    function line:ClearAllPoints() end
    table.insert(self.pool, line)
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
DEFAULT_CHAT_FRAME = {
  AddMessage = function(_, msg) chat[#chat + 1] = msg end,
}
SlashCmdList = {}

-- ── the client's map hierarchy ─────────────────────────────────────────────
-- UIParent -> WorldMapFrame -> ScrollContainer -> canvas -> art. The art is a
-- SIBLING of the overlay inside the canvas and sits at a HIGH frame level:
-- this is the frame that covers a line drawn at canvas level + 10.
local UIParent = makeFrame("UIParent", nil)
UIParent.width, UIParent.height = 1920, 1080
UIParent.level = 0

local WorldMapFrame = makeFrame("WorldMapFrame", UIParent)
WorldMapFrame.width, WorldMapFrame.height = 1002, 668
WorldMapFrame.level = 2
_G.WorldMapFrame = WorldMapFrame

local scroll = makeFrame("WorldMapScrollContainer", WorldMapFrame)
scroll.width, scroll.height = 1002, 668
scroll.level = 2

local canvas = makeFrame(nil, scroll)
canvas.width, canvas.height = 1002, 668
canvas.level = 3

local art = makeFrame("WorldMapDetailFrame", canvas)
art.width, art.height = 1002, 668
art.level = 40
WorldMapDetailFrame = art

function WorldMapFrame:GetCanvas() return canvas end
function WorldMapFrame:GetMapID() return 1413 end
function WorldMapFrame:GetCanvasScale() return 1 end
WorldMapFrame.ScrollContainer = scroll

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
local M = ns.MapOverlay

-- ── the route that reported "2 segments queued" and drew nothing ────────────
M:SetRoute({
  mapID = 1413,
  path = {
    { x = 0.720, y = 0.350 },
    { x = 0.450, y = 0.430 },
  },
})

check(M._drawError == nil, "draw error: " .. tostring(M._drawError))
check(M.host ~= nil, "overlay host created under the canvas")
check(M._hostParent == canvas, "host parented to the canvas")
check(M._lastQueued == 1, "one segment queued, got " .. tostring(M._lastQueued))

-- THE FIX: the art's own level was measured, so the host is ABOVE it.
check(M._zorder ~= nil, "z-order was measured")
check(M._zorder and M._zorder.topLevel == 40,
  "the art's level was measured (got " .. tostring(M._zorder and M._zorder.topLevel) .. ")")
check(M._zorder and M._zorder.topLabel == "WorldMapDetailFrame",
  "the measured top frame is named (got " .. tostring(M._zorder and M._zorder.topLabel) .. ")")
check(M.host and M.host:GetFrameLevel() > art:GetFrameLevel(),
  "host level " .. tostring(M.host and M.host:GetFrameLevel())
    .. " must be above the art's level " .. tostring(art:GetFrameLevel()))
check(M._zorder and M._zorder.raised == true, "the raise is recorded as a raise")
check(M.host and M.host:GetFrameStrata() == "MEDIUM",
  "host stays on the map's strata (got " .. tostring(M.host and M.host:GetFrameStrata()) .. ")")
check(M._zorder and M._zorder.candidates and #M._zorder.candidates >= 1,
  "the art candidates are recorded for the diag")

-- The overlay is itself a child of the canvas, so a naive "highest child wins"
-- audit ratchets its own level upward on every redraw. Three redraws must keep
-- the level put, and the raise must stay reported.
local levelAfterFirst = M.host:GetFrameLevel()
for _ = 1, 3 do
  M:Redraw()
end
check(M.host:GetFrameLevel() == levelAfterFirst,
  "the host level is stable across redraws (got " .. tostring(M.host:GetFrameLevel())
    .. ", first " .. tostring(levelAfterFirst) .. ")")
check(M._zorder and M._zorder.raised == true,
  "the raise is still reported after later redraws (nothing left to raise)")
check(M._drawError == nil, "no draw error after repeated redraws: " .. tostring(M._drawError))

-- The line itself: real region contract, real pixels.
local line = M.drawer and M.drawer.pool and M.drawer.pool[1]
check(line ~= nil, "a line object exists")
check(line and line:IsShown(), "the line object is shown")
check(line and line.color and line.color[4] == 0.9,
  "the line carries pathColor's alpha (got " .. tostring(line and line.color and line.color[4]) .. ")")
if line and line.start and line.stop then
  near(line.start[4], 0.720 * 1002, "first point x lands at the projected pixel")
  near(line.start[5], -0.350 * 668, "first point y lands at the projected pixel (from TOPLEFT)")
  near(line.stop[4], 0.450 * 1002, "second point x")
  near(line.stop[5], -0.430 * 668, "second point y")
else
  check(false, "the line carries start/end points")
end

-- ── /nt mapdiag must print the evidence, not the guess ─────────────────────
chat = {}
M:Diag()
local joined = table.concat(chat, "\n")
for _, needle in ipairs({
  -- host facts: level, strata, shown, size, alpha
  "host: name=<unnamed> level=",
  "strata=MEDIUM shown=true size=1002x668",
  -- the parent chain by name
  "parent chain: <unnamed>(lvl=3 strata=MEDIUM",
  "WorldMapFrame(lvl=2",
  "UIParent(lvl=0",
  -- the measured draw order and the raise
  "z-order: canvas_level=3 canvas_strata=MEDIUM",
  "top=WorldMapDetailFrame(lvl=40)",
  "above the art",
  "RAISED from",
  -- what the draw applied (alpha / colour / thickness)
  "colour applied by the last draw: r=1.00 g=1.00 b=1.00 a=0.90",
  -- the first two line objects, live state
  "line 1: kind=line shown=true",
  "line 2: absent",
  -- every projected point, with pixels
  "points: 2 of 2 projected",
  "#1 (0.720,0.350)->(721.4,233.8)",
  "#2 (0.450,0.430)->(450.9,287.2)",
  -- the segment decision
  "segments: queued=1 total=",
  -- and the verdict names the cause from those numbers
  "verdict: DRAW ORDER",
}) do
  check(joined:find(needle, 1, true) ~= nil, "mapdiag missing: " .. needle)
end
check(joined:find("error:", 1, true) == nil, "mapdiag printed an error line")

if failed > 0 then
  io.stderr:write(failed .. " map z-order check(s) failed\n")
  os.exit(1)
end
print("mapdiag_zorder_spec: ok")

-- t_ec00e4f3 — the world map drew only the OPENING LEG of a 17-point route
-- while the minimap was correct.
--
-- Evidence, from two live screenshots of the same route (player at 58.8, 41.0):
-- the world map showed one short dash stroke near Orgrimmar and nothing else —
-- not the leg past the player's own arrow, not the eastern side of the loop.
-- The minimap, drawing the same path, showed both legs. A pixel scan of the
-- screenshot found exactly ONE cluster of white route pixels (24x18px, about
-- one segment of dots) and no other dot or rim anywhere on the map.
--
-- The route below is the addon's OWN output for the live Barrens herb data
-- (`Density.Build`, cell 0.02, warm 0.4, anchorCell 0.06, smooth 2, maxStops 4):
-- 17 points, 16 segments, starting at canvas px (407.6, 98.0). The diag that was
-- quoted on the card maps the visible cluster to `0.4068..0.4454, 0.1448..0.1594`
-- — points #1..#3 of exactly this path.
--
-- What this spec pins, and why each part is RED on 62c26b4:
--   A. the plan FITS the regions the client actually hands out: a client that
--      stops creating regions after a ceiling must still get a route painted
--      end to end (fewer, wider dots) — on 62c26b4 the chain simply stopped at
--      the ceiling and the rest of the route was never drawn;
--   B. painted is MEASURED: `paintedDots` counts dots whose own region exists,
--      so `planned == painted` is a fact, not the loop counter talking about
--      itself — 62c26b4 derives it from the index and reports a truncated route
--      as complete;
--   C. when even the minimum plan cannot fit, the shortfall is REPORTED
--      (`missing`, and the `dots pool:` diag line) instead of silently becoming
--      a shorter line;
--   D. /nt mapdiag measures the MIDDLE of the route (`dot 8`, `dot 9`) in the
--      same shape as `line 1`/`line 2`, so "only the first leg paints" can be
--      told apart from "the objects are hidden";
--   E. /nt mapdiag measures CLIPPING on the host and the canvas, and the overlay
--      turns child-clipping OFF on its own host — a host that clips crops the
--      route at its edge, which is indistinguishable from a truncated paint;
--   F. every draw pass is recorded, so a later pass that rewrites the pool with
--      a shorter buffer is visible, and the stale tail it leaves behind is
--      actually hidden.
--
-- The client modelled here is the one measured live (c220ec7 / 62c26b4):
-- Frame:CreateLine exists and keeps no geometry, and a texture is sized only by
-- two corner anchors (no SetWidth/SetHeight/SetRotation). Not loaded by the TOC.

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

local CANVAS_SCALE = 0.696
local CANVAS_W, CANVAS_H = 1002, 668

-- ── the live route: 17 points, 16 segments, closed back onto point #1 ───────
local ROUTE = {
  { x = 0.4068, y = 0.1467 }, --  407.6,  98.0
  { x = 0.4250, y = 0.1448 }, --  425.8,  96.8
  { x = 0.4454, y = 0.1594 }, --  446.3, 106.5
  { x = 0.4681, y = 0.1903 }, --  469.0, 127.1
  { x = 0.4930, y = 0.2375 }, --  494.0, 158.7
  { x = 0.5202, y = 0.3011 }, --  521.2, 201.2
  { x = 0.5388, y = 0.3473 }, --  539.9, 232.0
  { x = 0.5489, y = 0.3760 }, --  550.0, 251.2
  { x = 0.5504, y = 0.3872 }, --  551.5, 258.7
  { x = 0.5434, y = 0.3810 }, --  544.5, 254.5
  { x = 0.5286, y = 0.3625 }, --  529.6, 242.1
  { x = 0.5059, y = 0.3316 }, --  506.9, 221.5
  { x = 0.4754, y = 0.2883 }, --  476.4, 192.6
  { x = 0.4371, y = 0.2328 }, --  437.9, 155.5
  { x = 0.4129, y = 0.1906 }, --  413.7, 127.3
  { x = 0.4028, y = 0.1619 }, --  403.6, 108.2
  { x = 0.4068, y = 0.1467 }, --  407.6,  98.0 (closing point)
}

-- ── a client stub with a REGION CEILING ────────────────────────────────────
-- `ceiling` is the number of regions the frame hands out before CreateTexture
-- returns nothing. The addon already treats that as a real possibility (every
-- create is pcall'd and checked), so a client that stops is not a fiction: it
-- is the case the drawer must survive.
local function boot(ceiling)
  local chat = {}
  local created = 0
  local clipCalls = {}
  -- Mutable on purpose: a client whose CreateTexture starts working again is
  -- the case that proves a recorded ceiling must be re-measured, not latched.
  local limit = ceiling

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
    -- NOTE: no SetWidth/SetHeight/SetSize/SetRotation — this client sizes a
    -- texture from two corner anchors only.
    return r
  end

  local function makeFrame(name, parent)
    local f = makeRegion(nil, "frame")
    f.name = name
    f.parent = parent
    f.children = {}
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
    function f:GetScale() return self.scale or 1 end
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
    function f:GetLeft() return self.left end
    function f:GetTop() return self.top end
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
    -- Child clipping: ON by default here, so a host that never turns it off is
    -- caught. The overlay must not clip its own dots.
    f.clips = true
    function f:SetClipsChildren(v)
      self.clips = v and true or false
      clipCalls[#clipCalls + 1] = { name = self.name, value = self.clips }
    end
    function f:DoesClipChildren() return self.clips end
    function f:CreateTexture()
      if created >= limit then
        return nil
      end
      created = created + 1
      local t = makeRegion(self, "texture")
      table.insert(self.children, t)
      return t
    end
    function f:CreateLine()
      -- The live client: the setters return, the getters never move.
      local line = makeRegion(self, "line")
      function line:SetStartPoint(point, rel, relPoint, x, y) self.asked = { point, rel, relPoint, x, y } end
      function line:SetEndPoint(point, rel, relPoint, x, y) self.askedEnd = { point, rel, relPoint, x, y } end
      function line:GetStartPoint() return "TOPLEFT", nil, nil, 0, nil end
      function line:GetEndPoint() return "TOPLEFT", nil, nil, 0, nil end
      function line:GetWidth() return 0 end
      function line:GetHeight() return 0 end
      function line:SetThickness(t) self.thickness = t end
      function line:GetThickness() return self.thickness end
      table.insert(self.children, line)
      return line
    end
    if parent then
      table.insert(parent.children, f)
    end
    return f
  end

  _G.CreateFrame = function(kind, name, parent) return makeFrame(name, parent) end
  _G.CopyTable = function(t)
    local out = {}
    for k, v in pairs(t) do
      out[k] = type(v) == "table" and _G.CopyTable(v) or v
    end
    return out
  end
  _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) chat[#chat + 1] = msg end }
  _G.SlashCmdList = {}

  local uiParent = makeFrame("UIParent", nil)
  uiParent.w, uiParent.h = 1920, 1080

  local worldMapFrame = makeFrame("WorldMapFrame", uiParent)
  worldMapFrame.w, worldMapFrame.h = CANVAS_W, CANVAS_H
  worldMapFrame.level = 2
  _G.WorldMapFrame = worldMapFrame

  local canvas = makeFrame(nil, worldMapFrame)
  canvas.w, canvas.h = CANVAS_W, CANVAS_H
  canvas.level = 3
  canvas.left, canvas.top = 0, 0
  function worldMapFrame:GetCanvas() return canvas end
  function worldMapFrame:GetMapID() return 1413 end
  function worldMapFrame:GetCanvasScale() return CANVAS_SCALE end
  _G.GetCurrentMapAreaID = function() return 1413 end

  local minimap = makeFrame("Minimap", uiParent)
  minimap.w, minimap.h = 140, 140
  function minimap:GetZoom() return 0 end
  _G.Minimap = minimap
  _G.C_Minimap = { GetViewRadius = function() return 233.333 end }
  _G.C_Map = {
    GetPlayerMapPosition = function()
      return { GetXY = function() return 0.5, 0.5 end }
    end,
  }
  local cvars = { rotateMinimap = "0", minimapZoom = "0" }
  _G.GetCVar = function(name) return cvars[name] end
  _G.GetPlayerFacing = function() return 0 end
  _G.GetMinimapShape = function() return "ROUND" end

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
  loadAddon("Core.lua")

  local ns = pkg.NodeTrail
  ns.Enable()
  local ctx = {
    ns = ns,
    M = ns.MapOverlay,
    chat = chat,
    created = function() return created end,
    clipCalls = clipCalls,
    canvas = canvas,
  }
  -- The chat frame is a global; a later boot() replaces it, so the diag of an
  -- earlier client must be routed back to that client's own chat table.
  function ctx.diag()
    local previous = _G.DEFAULT_CHAT_FRAME
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) chat[#chat + 1] = msg end }
    ns.MapOverlay:Diag()
    _G.DEFAULT_CHAT_FRAME = previous
    return table.concat(chat, "\n")
  end
  --- Raise (or lower) the region ceiling between draws.
  function ctx.setCeiling(n)
    limit = n
  end
  return ctx
end

local function lineStartingWith(text, prefix)
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local body = line:gsub("^NodeTrail mapdiag: ", "")
    if body:sub(1, #prefix) == prefix then
      return body
    end
  end
  return nil
end

--- Centre of a painted dot, in the host's y-down pixel space.
local function dotCentre(obj)
  if not obj or type(obj.points) ~= "table" or #obj.points < 2 then
    return nil
  end
  local a, b = obj.points[1], obj.points[2]
  return ((a[4] or 0) + (b[4] or 0)) * 0.5, -((a[5] or 0) + (b[5] or 0)) * 0.5
end

local function isWhite(obj)
  local c = obj and obj.color
  return c and c[1] == 1 and c[2] == 1 and c[3] == 1
end

local function route(x)
  local path = {}
  for i = 1, #ROUTE do
    path[i] = { x = ROUTE[i].x, y = ROUTE[i].y }
  end
  return { mapID = 1413, path = path }
end

-- ═══ A. a region ceiling must not cut the route short ══════════════════════
-- 150 regions is 75 dots: more than the 32-dot minimum this 16-segment route
-- needs, so every planned dot can be painted — but far below the ~130 dots a
-- 0.696 canvas asks for at 3 screen px, so the plan HAS to be re-fitted.
local A = boot(150)
A.M:SetRoute(route("A"))
check(A.M._drawError == nil, "A: draw error: " .. tostring(A.M._drawError))
check(A.M.drawer and A.M.drawer.mode == "dots",
  "A: this client draws the anchored-dot chain (mode=" .. tostring(A.M.drawer and A.M.drawer.mode) .. ")")

local applied = (A.M.drawer and A.M.drawer.lastApplied) or {}
check(type(applied.plannedDots) == "number" and applied.plannedDots > 0,
  "A: the draw records how many dots it PLANNED (got " .. tostring(applied.plannedDots) .. ")")
check(type(applied.paintedDots) == "number",
  "A: the draw records how many dots it PAINTED from the objects, not from the loop index (got "
    .. tostring(applied.paintedDots) .. ")")
check(applied.paintedDots == applied.plannedDots,
  "A: painted == planned on a client with a region ceiling (painted=" .. tostring(applied.paintedDots)
    .. " planned=" .. tostring(applied.plannedDots) .. ")")
check((applied.missingDots or 0) == 0,
  "A: no planned dot was left without a region (missing=" .. tostring(applied.missingDots) .. ")")
check((applied.replans or 0) >= 1,
  "A: the plan was re-fitted to the measured ceiling (replans=" .. tostring(applied.replans) .. ")")
check(type(applied.capacity) == "number" and applied.capacity > 0,
  "A: the ceiling this client actually has is recorded (capacity=" .. tostring(applied.capacity) .. ")")
check(applied.plannedDots < 100,
  "A: the plan was widened to fit, not left at the 3px-per-dot plan (planned="
    .. tostring(applied.plannedDots) .. ")")

-- every planned dot exists, is shown, and the counted number matches the pool
local pool = A.M.drawer.pool
local poolHigh = A.M.drawer.poolHigh or #pool
local whites, shownDots = 0, 0
for i = 1, poolHigh do
  local o = pool[i]
  if o then
    if isWhite(o) then
      whites = whites + 1
      if o.shown then shownDots = shownDots + 1 end
    end
  end
end
check(shownDots == applied.paintedDots,
  "A: the pool holds one SHOWN white dot per painted dot (shown=" .. shownDots
    .. " painted=" .. tostring(applied.paintedDots) .. ")")
check(shownDots == applied.paintedDots,
  "A: every painted dot is shown (shown=" .. shownDots .. " painted=" .. tostring(applied.paintedDots) .. ")")

-- the chain still spans the route: the last dot sits on the closing point
local lastWhite, firstWhite
for i = 1, poolHigh do
  local o = pool[i]
  if isWhite(o) and o.shown then
    firstWhite = firstWhite or o
    lastWhite = o
  end
end
local lx, ly = dotCentre(lastWhite)
local sx, sy = dotCentre(firstWhite)
near(sx, ROUTE[1].x * CANVAS_W, "A: the chain starts on route point #1 (x)", 0.6)
near(sy, ROUTE[1].y * CANVAS_H, "A: the chain starts on route point #1 (y)", 0.6)
near(lx, ROUTE[#ROUTE].x * CANVAS_W, "A: the chain reaches the closing point (x)", 0.6)
near(ly, ROUTE[#ROUTE].y * CANVAS_H, "A: the chain reaches the closing point (y)", 0.6)

-- ═══ B. the ceiling is never exceeded ══════════════════════════════════════
check(A.created() <= 150,
  "A: the drawer asks for no more regions than the client hands out (asked="
    .. A.created() .. ")")

-- ═══ C. a ceiling below the minimum plan is REPORTED, not silently shorter ═
-- 16 segments cannot be drawn with fewer than 32 dots (both endpoints of every
-- segment are drawn), so 40 regions (20 dots) is genuinely impossible. The draw
-- must say so — on 62c26b4 this case was indistinguishable from success.
local C = boot(40)
C.M:SetRoute(route("C"))
local cApplied = (C.M.drawer and C.M.drawer.lastApplied) or {}
check(type(cApplied.missingDots) == "number" and cApplied.missingDots > 0,
  "C: the shortfall is counted (missing=" .. tostring(cApplied.missingDots) .. ")")
check(type(cApplied.paintedDots) == "number" and type(cApplied.plannedDots) == "number"
    and cApplied.paintedDots < cApplied.plannedDots,
  "C: painted < planned when the client cannot fit the minimum plan (painted="
    .. tostring(cApplied.paintedDots) .. " planned=" .. tostring(cApplied.plannedDots) .. ")")
local cDiag = C.diag()
local cPool = lineStartingWith(cDiag, "dots pool:")
check(cPool ~= nil, "C: /nt mapdiag prints the dots pool line (got " .. tostring(cPool) .. ")")
check(cPool and cPool:find("missing=", 1, true) ~= nil,
  "C: the dots pool line names the missing dots (got " .. tostring(cPool) .. ")")
check(cPool and cPool:find("painted=" .. tostring(cApplied.paintedDots), 1, true) ~= nil,
  "C: the dots pool line quotes the measured painted count (got " .. tostring(cPool) .. ")")
check(cPool and cPool:find("planned=" .. tostring(cApplied.plannedDots), 1, true) ~= nil,
  "C: the dots pool line quotes the plan it measured against (got " .. tostring(cPool) .. ")")

-- ═══ D. the diag measures the MIDDLE of the route ══════════════════════════
-- "only the first leg paints" is a claim about the middle, so dot 8 and dot 9
-- must be printed in the same shape as line 1/line 2 — shown, alpha, size,
-- parent and both anchors.
local midDiag = A.diag()
for _, tag in ipairs({ "line 1:", "dot 8:", "dot 9:" }) do
  local line = lineStartingWith(midDiag, tag)
  check(line ~= nil, "D: /nt mapdiag prints a " .. tag:gsub(":$", "") .. " line (got " .. tostring(line) .. ")")
  if line then
    check(line:find("shown=", 1, true) ~= nil, "D: " .. tag .. " states shown (" .. line .. ")")
    check(line:find("alpha=", 1, true) ~= nil, "D: " .. tag .. " states alpha (" .. line .. ")")
    check(line:find("size=", 1, true) ~= nil, "D: " .. tag .. " states size (" .. line .. ")")
    check(line:find("parent=", 1, true) ~= nil, "D: " .. tag .. " states the parent (" .. line .. ")")
    check(line:find("points=[", 1, true) ~= nil,
      "D: " .. tag .. " states the two anchors (" .. line .. ")")
  end
end
-- A dot in the middle of the route must be a real, shown, anchored region: the
-- two-anchor contract with a non-zero size is what makes it paint at all.
local midWhite = pool[18]
check(midWhite ~= nil and midWhite.shown == true,
  "D: dot 9 of the chain is held and shown")
check(midWhite and midWhite:GetNumPoints() == 2,
  "D: dot 9 carries two corner anchors (got " .. tostring(midWhite and midWhite:GetNumPoints()) .. ")")
check(midWhite and midWhite:GetWidth() > 0 and midWhite:GetHeight() > 0,
  "D: dot 9 measures a positive size (" .. tostring(midWhite and midWhite:GetWidth()) .. "x"
    .. tostring(midWhite and midWhite:GetHeight()) .. ")")
check(midWhite and midWhite.parent == A.M.host,
  "D: dot 9 is parented to the overlay host, not to something else")

-- The two ends of what was actually painted, in the same shape: a route that
-- stops on screen after its opening leg must show WHERE the paint stopped.
for _, tag in ipairs({ "dot mid", "dot last" }) do
  local line = lineStartingWith(midDiag, tag)
  check(line ~= nil, "D: /nt mapdiag prints a " .. tag .. " line (got " .. tostring(line) .. ")")
  if line then
    check(line:find("shown=true", 1, true) ~= nil, "D: " .. tag .. " is shown (" .. line .. ")")
    check(line:find("size=", 1, true) ~= nil and line:find("size=0x0", 1, true) == nil,
      "D: " .. tag .. " measures a real size (" .. line .. ")")
    check(line:find("planned=", 1, true) ~= nil, "D: " .. tag .. " prints its planned size (" .. line .. ")")
  end
end

-- ═══ E. clipping is measured, and the overlay does not clip its own dots ═══
local clipLine = lineStartingWith(midDiag, "clips:")
check(clipLine ~= nil, "E: /nt mapdiag prints a clips: line (got " .. tostring(clipLine) .. ")")
check(clipLine and clipLine:find("host", 1, true) ~= nil,
  "E: the clips line names the host (" .. tostring(clipLine) .. ")")
check(clipLine and clipLine:find("canvas", 1, true) ~= nil,
  "E: the clips line names the canvas (" .. tostring(clipLine) .. ")")
check(clipLine and clipLine:find("rect=", 1, true) ~= nil,
  "E: the clips line prints the measured rect (" .. tostring(clipLine) .. ")")
check(A.M.host and A.M.host.clips == false,
  "E: the overlay host does not clip its own dots (clips=" .. tostring(A.M.host and A.M.host.clips) .. ")")
local turnedOff = false
for i = 1, #A.clipCalls do
  if A.clipCalls[i].value == false then turnedOff = true end
end
check(turnedOff, "E: SetClipsChildren(false) is called on the host, so a client that clips by default cannot crop the route")
check(A.canvas.clips == true,
  "E: the overlay leaves Blizzard's canvas clipping alone (canvas clips=" .. tostring(A.canvas.clips) .. ")")

-- ═══ F. every pass is recorded, and a shorter pass hides the stale tail ════
-- Two draws into the same drawer: the full route, then only its first 3 points.
-- The second pass must say so, and must hide every dot the first pass left
-- behind — otherwise the map shows two overlapping routes.
local F = boot(400)
F.M:SetRoute(route("F"))
local full = (F.M.drawer or {}).lastApplied or {}
check(type(full.paintedDots) == "number" and full.paintedDots == full.plannedDots
    and full.paintedDots > 20,
  "F: the uncapped client paints the whole plan (painted=" .. tostring(full.paintedDots)
    .. " planned=" .. tostring(full.plannedDots) .. ")")
local short = { mapID = 1413, path = { { x = ROUTE[1].x, y = ROUTE[1].y },
  { x = ROUTE[2].x, y = ROUTE[2].y }, { x = ROUTE[3].x, y = ROUTE[3].y } } }
F.M:SetRoute(short)
local shortApplied = (F.M.drawer or {}).lastApplied or {}
check(F.M._lastQueued == 2,
  "F: the second draw queues the shorter buffer (queued=" .. tostring(F.M._lastQueued) .. ")")
check((shortApplied.hideFromIndex or 0) > 0,
  "F: the shorter draw records where it started hiding (hideFrom="
    .. tostring(shortApplied.hideFromIndex) .. ")")
local visible = 0
local fHigh = F.M.drawer.poolHigh or #F.M.drawer.pool
for i = 1, fHigh do
  local o = F.M.drawer.pool[i]
  if o and o.shown then visible = visible + 1 end
end
check(type(shortApplied.paintedDots) == "number" and visible == shortApplied.paintedDots * 2,
  "F: nothing from the longer route is left on screen (visible=" .. visible
    .. " expected=" .. tostring((shortApplied.paintedDots or 0) * 2) .. ")")
local fDiag = F.diag()
local drawsLine = lineStartingWith(fDiag, "draws:")
check(drawsLine ~= nil, "F: /nt mapdiag prints the draw history (got " .. tostring(drawsLine) .. ")")
check(drawsLine and drawsLine:find("count=16", 1, true) ~= nil,
  "F: the history keeps the earlier 16-segment pass (" .. tostring(drawsLine) .. ")")
check(drawsLine and drawsLine:find("count=2", 1, true) ~= nil,
  "F: the history shows the later 2-segment pass (" .. tostring(drawsLine) .. ")")

-- ═══ G. a retry the client cannot fit is never painted ══════════════════════
-- The 40-region client cannot hold the 32-dot floor of this route. Painting a
-- wider retry anyway put 1034x1034 px dots in the pool while the diag reported
-- the normal 4-5 px plan, so the map showed something the numbers denied. The
-- pool must hold exactly the plan the numbers describe: normal-size dots.
do
  local dw = C.M.drawer
  local reported = tonumber(cApplied.dotSize)
  local maxSeen, whites, oversized = 0, 0, 0
  for i = 1, (dw.poolHigh or #dw.pool) do
    local o = dw.pool[i]
    if o and isWhite(o) and o.shown then
      whites = whites + 1
      local w = o:GetWidth()
      if w > maxSeen then maxSeen = w end
      if reported and w > reported * 1.5 then oversized = oversized + 1 end
    end
  end
  check(reported ~= nil, "G: the draw reports the dot size it planned (" .. tostring(reported) .. ")")
  check(cApplied.reverted ~= true, "G: no painted-then-abandoned retry was needed on a client whose floor cannot fit")
  check(oversized == 0, "G: every painted dot keeps the planned dot size (oversized=" .. oversized
    .. " max=" .. tostring(maxSeen) .. " planned=" .. tostring(reported) .. ")")
  check(whites == cApplied.paintedDots, "G: the pool holds exactly the reported painted dots (whites="
    .. whites .. " painted=" .. tostring(cApplied.paintedDots) .. ")")
  near(maxSeen, reported, "G: the widest painted dot is the planned dot, not a 1000px block", 0.01)
end

-- ═══ H. a latched ceiling is re-measured upward ═════════════════════════════
-- CreateTexture returning nil once is a refusal, not a verdict. With the ceiling
-- latched, every later draw stayed widened and shortened for the session, with
-- no way back. A create that succeeds past the recorded ceiling must clear it.
do
  local H = boot(40)
  H.M:SetRoute(route("H"))
  local narrow = (H.M.drawer or {}).lastApplied or {}
  check((narrow.missingDots or 0) > 0,
    "H: the narrow client reports the shortfall first (missing=" .. tostring(narrow.missingDots) .. ")")
  check(type(narrow.capacity) == "number", "H: the ceiling is recorded (capacity=" .. tostring(narrow.capacity) .. ")")
  H.setCeiling(400)
  H.M:SetRoute(route("H2"))
  local wide = (H.M.drawer or {}).lastApplied or {}
  check(wide.paintedDots == wide.plannedDots,
    "H: once regions can be created again the whole plan is painted (painted="
      .. tostring(wide.paintedDots) .. " planned=" .. tostring(wide.plannedDots) .. ")")
  check((wide.missingDots or 0) == 0, "H: and nothing is reported missing (missing="
    .. tostring(wide.missingDots) .. ")")
  check((wide.widen or 1) == 1, "H: the widen the stale ceiling forced is dropped (widen="
    .. tostring(wide.widen) .. ")")
  check(wide.capacity == nil and wide.capacityStale == true,
    "H: the stale ceiling is cleared and the diag says so (capacity=" .. tostring(wide.capacity)
      .. " stale=" .. tostring(wide.capacityStale) .. ")")
  check(H.created() <= 400, "H: the wider plan still respects the new ceiling (asked=" .. H.created() .. ")")
end

-- ═══ I. the middle-dot diag prints MEASURED size next to the planned size ══
-- Measured alone cannot tell "the object exists but the client kept no geometry"
-- from "the object is the size the draw asked for".
for _, tag in ipairs({ "dot 8:", "dot 9:" }) do
  local line = lineStartingWith(midDiag, tag)
  check(line ~= nil and line:find("planned=", 1, true) ~= nil,
    "I: " .. tag .. " prints the planned size next to the measured one (got " .. tostring(line) .. ")")
end

-- ═══ J. the pool line measures the objects, and says where they land ═══════
do
  local poolLine = lineStartingWith(A.diag(), "dots pool:")
  check(poolLine and poolLine:find("sized=", 1, true) ~= nil,
    "J: the dots pool line measures how many dots have real geometry (got " .. tostring(poolLine) .. ")")
  check(poolLine and poolLine:find("anchored=", 1, true) ~= nil,
    "J: the dots pool line counts the dots that carry both anchors (got " .. tostring(poolLine) .. ")")
  check(poolLine and poolLine:find("sized=" .. tostring((A.M.drawer.lastApplied or {}).paintedDots) .. "/",
      1, true) ~= nil,
    "J: on this client every painted dot measures a positive size (got " .. tostring(poolLine) .. ")")
  local boxLine = lineStartingWith(A.diag(), "dots box:")
  check(boxLine ~= nil, "J: /nt mapdiag prints where the painted dots land (got " .. tostring(boxLine) .. ")")
  check(boxLine and boxLine:find("outside=0/", 1, true) ~= nil,
    "J: no painted dot lands outside the overlay host (got " .. tostring(boxLine) .. ")")
  check(boxLine and boxLine:find("bbox=", 1, true) ~= nil,
    "J: the painted bbox is printed so a translation can be seen (got " .. tostring(boxLine) .. ")")
end

-- ═══ K. the two-corner anchor probe is not upside down ══════════════════════
-- The probe read "two corner anchors -> 64x0" on the live client because the
-- BOTTOM anchor was given the SMALLER y-down offset than the TOP one: the top
-- edge sat above the bottom edge, so the height was 0. That reading sent three
-- rounds of work after a geometry bug that was only in the probe.
do
  local K = boot(400)
  K.M:SetRoute(route("K"))
  local probeTex = K.M:_probeTexture(K.M.host)
  check(probeTex ~= nil, "K: the probe texture is created on the host")
  if probeTex then
    -- What /nt mapdiag's "anchor probe" line runs on that same texture.
    local proof = K.ns.LineDraw.TextureProof(probeTex, K.M.host)
    local _, _, _, _, bottomY = probeTex:GetPoint(1)
    local _, _, _, _, topY = probeTex:GetPoint(2)
    check(type(proof.anchorHeight) == "number" and proof.anchorHeight > 0,
      "K: the probe measures a positive height (" .. tostring(proof.anchorHeight) .. ")")
    check(type(bottomY) == "number" and type(topY) == "number",
      "K: the probe anchors both corners (bottom=" .. tostring(bottomY) .. " top=" .. tostring(topY) .. ")")
    check(type(bottomY) == "number" and type(topY) == "number" and bottomY < topY,
      "K: the probe's BOTTOM anchor is below its TOP anchor in y-down space (bottom="
        .. tostring(bottomY) .. " top=" .. tostring(topY) .. ")")
    check(probeTex:GetHeight() > 0,
      "K: the probe therefore measures a positive height (" .. tostring(probeTex:GetHeight()) .. ")")
  end
end

-- ═══ L. the card's own number: 17 points at canvas scale 0.696, every dot ══
-- "a 17-point route at canvas scale 0.696 must paint every planned dot, and a
-- spec asserts the painted count equals the plan". On a client with enough
-- regions nothing may be dropped and nothing may be widened.
do
  local L = boot(4000)
  L.M:SetRoute(route("L"))
  local a = (L.M.drawer or {}).lastApplied or {}
  near(a.dotScale, CANVAS_SCALE, "L: the canvas scale is the live one", 0.001)
  check(a.plannedDots == 130,
    "L: the 17-point route plans 130 dots at 3 screen px (planned=" .. tostring(a.plannedDots) .. ")")
  check(a.paintedDots == a.plannedDots,
    "L: every planned dot is painted (painted=" .. tostring(a.paintedDots) .. " planned="
      .. tostring(a.plannedDots) .. ")")
  check((a.missingDots or 0) == 0, "L: nothing is missing (missing=" .. tostring(a.missingDots) .. ")")
  check((a.widen or 1) == 1, "L: the plan was not widened on a client that can hold it (widen="
    .. tostring(a.widen) .. ")")
  check((a.replans or 0) == 0, "L: and no re-fit was needed (replans=" .. tostring(a.replans) .. ")")
end

if failed > 0 then
  io.stderr:write(("mapdot_capacity_spec: %d FAIL(s)\n"):format(failed))
  os.exit(1)
end
print("mapdot_capacity_spec: ok")

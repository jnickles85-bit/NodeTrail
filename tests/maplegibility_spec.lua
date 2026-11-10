-- t_60e6e825 — the route is DRAWN in the right place and renders as a GHOST.
-- Mightie: "The path is being drawn on the map it is just extremely transparent."
-- Placement/projection are correct and closed; the only variables in scope are
-- opacity, thickness (screen px), inherited parent alpha and draw order.
--
-- What this spec pins, section by section:
--   A. the dot core is a 4 SCREEN px floor at any canvas scale (0.6, 1.0, 1.5),
--      spaced by the RIM width (core + 2), with the dark rim 2 screen px larger
--      (1px a side) so no dot's rim can reach a neighbour's core;
--   B. the drawn white dots are OPAQUE (vertex alpha 1.0) even though the
--      settings ask for pathColor's 0.9 — and the 0.9 is still recorded as the
--      requested alpha, so overriding it is visible, not silent;
--   C. every white dot still has its dark rim underneath it, larger, at a lower
--      draw sublevel (the contrast half of the fix);
--   D. the host is pinned opaque and asks the client to IGNORE the alpha it
--      inherits (`SetIgnoreParentAlpha`), because a frame's drawn alpha is its
--      own times every ancestor's — a faded map parent makes a ghost whatever
--      the vertex colour says;
--   E. /nt mapdiag prints the alpha CHAIN and its effective product, naming the
--      ancestor that dims it when the client cannot be asked to ignore it;
--   F. /nt mapdiag prints ONE sampled dot, read back: requested colour,
--      GetVertexColor() as the client reports it, the layer/blend it landed in,
--      its measured size next to the plan, the screen px it works out to, its
--      frame level and strata;
--   G. /nt mapdiag prints the frames that could cover the route (a faded or
--      higher-level child over the map) — the "what is above the host" question;
--   H. the legibility contract measured off the DRAWN regions at 0.6 / 1.0 /
--      1.5 canvas scales: drawn width x scale is never below 4 screen px.
--
-- RED on 7e3a329 (the reported state): the floor is 3 screen px, the dots carry
-- alpha 0.9, nothing reads the parent chain, and none of E/F/G is printed.
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

local CANVAS_W, CANVAS_H = 1002, 668

-- The live route from the last in-game run (map 1413, the Barrens), in map
-- fractions of the 1002x668 canvas. Coordinates are NOT this card's business —
-- they are here so the draw is the real one.
local ROUTE = {
  { x = 0.4068, y = 0.1467 },
  { x = 0.4250, y = 0.1448 },
  { x = 0.4454, y = 0.1594 },
  { x = 0.4681, y = 0.1903 },
  { x = 0.4930, y = 0.2375 },
  { x = 0.5202, y = 0.3011 },
  { x = 0.5388, y = 0.3473 },
  { x = 0.5489, y = 0.3760 },
  { x = 0.5504, y = 0.3872 },
  { x = 0.5434, y = 0.3810 },
  { x = 0.5286, y = 0.3625 },
  { x = 0.5059, y = 0.3316 },
  { x = 0.4754, y = 0.2883 },
  { x = 0.4371, y = 0.2328 },
  { x = 0.4129, y = 0.1906 },
  { x = 0.4028, y = 0.1619 },
  { x = 0.4068, y = 0.1467 },
}

--- A client that has the shape the live one showed, with the knobs this card
--- needs: the canvas scale, the alpha the settings ask for, an ancestor that is
--- faded, whether the client can ignore parent alpha, and a GetVertexColor that
--- may lie about what it was given.
--- @param cfg table { scale, pathColorAlpha, fadedParent, noIgnoreAlpha,
---                     lieAlpha, coverFrame }
local function boot(cfg)
  cfg = cfg or {}
  local scale = cfg.scale or 0.696
  local chat = {}

  local function makeRegion(frame, kind)
    local r = {
      kind = kind,
      parent = frame,
      shown = false,
      points = {},
      w = 0,
      h = 0,
      alpha = 1,
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
    function r:GetLeft() return self.left end
    function r:GetTop() return self.top end
    function r:GetObjectType() return self.kind == "line" and "Line" or "Texture" end
    function r:SetTexture(path) self.texture = path end
    -- The live client is a MODERN one: `SetColorTexture` exists and wins over
    -- the vertex colour (LineDraw.applyColor prefers it), so a fake without it
    -- would not be the client this card is about. `cfg.noColorTexture` is the
    -- other shape, used to prove the vertex path is read too.
    if not cfg.noColorTexture then
      function r:SetColorTexture(cr, cg, cb, ca) self.color = { cr, cg, cb, ca } end
    end
    function r:SetVertexColor(cr, cg, cb, ca)
      self.askedVertex = { cr, cg, cb, ca }
      -- `lieAlpha`: the client accepts the call and reports something else.
      -- That is the "the alpha never reaches the texture" case the diag has to
      -- be able to print.
      if cfg.lieAlpha then
        self.vertex = { cr, cg, cb, cfg.lieAlpha }
      else
        self.vertex = { cr, cg, cb, ca }
      end
    end
    function r:GetVertexColor()
      local v = self.vertex
      if not v then return nil end
      return v[1], v[2], v[3], v[4]
    end
    if not cfg.noDrawLayer then
      -- The 1.12-derived client has no SetDrawLayer at all: within one frame a
      -- region is painted in CREATION order, which is why the paint order is a
      -- real variable on the live client and a geometry invariant has to hold.
      function r:SetDrawLayer(layer, sub) self.layer, self.sublevel = layer, sub end
    end
    function r:GetDrawLayer() return self.layer, self.sublevel end
    function r:SetBlendMode(mode) self.blend = mode end
    function r:GetBlendMode() return self.blend end
    function r:SetTexCoord() end
    function r:SetAlpha(a) self.alpha = a end
    function r:GetAlpha() return self.alpha end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:IsShown() return self.shown end
    function r:IsVisible() return self.shown end
    -- NOTE: no SetWidth/SetHeight/SetSize/SetRotation — this client sizes a
    -- texture from two corner anchors only, and calling a size setter raises.
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
    f.alpha = 1
    function f:GetName() return self.name end
    function f:GetFrameLevel() return self.level end
    function f:SetFrameLevel(l) self.level = l end
    function f:GetFrameStrata() return self.strata end
    function f:SetFrameStrata(s) self.strata = s end
    function f:GetScale() return self.scale or 1 end
    function f:SetAlpha(a) self.alpha = a end
    function f:GetAlpha() return self.alpha end
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
    function f:SetClipsChildren(v) self.clips = v and true or false end
    function f:DoesClipChildren() return self.clips end
    if not cfg.noIgnoreAlpha then
      -- The API the fix needs. A client that has it must be asked to ignore the
      -- inherited alpha; a client without it must be REPORTED, not assumed.
      function f:SetIgnoreParentAlpha(v) self.ignoreParentAlpha = v and true or false end
      function f:GetIgnoreParentAlpha() return self.ignoreParentAlpha end
    end
    function f:CreateTexture()
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
  function worldMapFrame:GetCanvasScale() return scale end
  _G.GetCurrentMapAreaID = function() return 1413 end

  -- The faded ancestor: the world map fades itself in and out, and while it is
  -- below 1 the route can only ever paint at that alpha.
  if cfg.fadedParent then
    worldMapFrame.alpha = cfg.fadedParent
  end

  -- A frame over the map that outranks the host, or is faded: the "what is
  -- above the route" case.
  if cfg.coverFrame then
    local cover = makeFrame("WorldMapOverlay", canvas)
    cover.w, cover.h = CANVAS_W, CANVAS_H
    cover.level = cfg.coverFrame.level or 900
    cover.alpha = cfg.coverFrame.alpha or 1
  end

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
  _G.GetTime = function() return 1000 end

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
  -- The alpha the settings ask for is the operator's live 0.9.
  local db = ns.GetDB()
  db.pathColor = { 1, 1, 1, cfg.pathColorAlpha or 0.9 }
  db.pathWidth = 2

  local ctx = { ns = ns, M = ns.MapOverlay, LD = ns.LineDraw, chat = chat,
    canvas = canvas, worldMapFrame = worldMapFrame }
  function ctx.route()
    local path = {}
    for i = 1, #ROUTE do
      path[i] = { x = ROUTE[i].x, y = ROUTE[i].y }
    end
    return { mapID = 1413, path = path }
  end
  function ctx.draw()
    ctx.M:SetRoute(ctx.route())
    return ctx.M.drawer and ctx.M.drawer.lastApplied or {}
  end
  function ctx.diag()
    local previous = _G.DEFAULT_CHAT_FRAME
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) chat[#chat + 1] = msg end }
    ctx.M:Diag()
    _G.DEFAULT_CHAT_FRAME = previous
    return table.concat(chat, "\n")
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

--- The colour a region ENDED UP carrying, whichever call the client took.
local function paintedColour(o)
  if not o then return nil end
  return o.color or o.vertex
end

local function isWhite(o)
  local c = paintedColour(o)
  return c and c[1] == 1 and c[2] == 1 and c[3] == 1
end

local function isDark(o)
  local c = paintedColour(o)
  return c and c[1] <= 0.1 and c[2] <= 0.1 and c[3] <= 0.1 and (c[4] or 0) >= 0.9
end

--- The drawn white dots of a client's last draw, as { index, obj }.
local function whiteDots(ctx)
  local out = {}
  local pool = (ctx.M.drawer and ctx.M.drawer.pool) or {}
  for i = 1, #pool do
    local o = pool[i]
    if o and o.shown and isWhite(o) then
      out[#out + 1] = { i, o }
    end
  end
  return out
end

-- ═══ A. the core is a 4 SCREEN px floor at any canvas scale ════════════════
do
  local LD = boot({ scale = 0.696 }).LD
  check(type(LD.DotMetrics) == "function", "A: LineDraw.DotMetrics exists")
  local scales = { 0.6, 1.0, 1.5 }
  for i = 1, #scales do
    local s = scales[i]
    local m = LD.DotMetrics(2, s)
    near(m.screenSize, 4, ("A: at canvas scale %s the dot is 4 SCREEN px"):format(s), 1e-6)
    near(m.size, 4 / s, ("A: ... which is 4/%s canvas px"):format(s), 1e-6)
    near(m.screenSpacing, m.screenSize + 2,
      ("A: at canvas scale %s the spacing is the RIM width, not the core"):format(s), 1e-6)
    check(m.screenSpacing - m.screenOutline >= 0,
      ("A: at canvas scale %s the next dot's rim stops short of this core (clearance %s px)")
        :format(s, tostring(m.screenSpacing - m.screenOutline)))
    near(m.screenOutline, 6,
      ("A: at canvas scale %s the dark rim is 2 screen px larger (1px a side)"):format(s), 1e-6)
    near(m.outline, 6 / s, ("A: ... in canvas px at scale %s"):format(s), 1e-6)
    check(m.outline > m.size, ("A: at canvas scale %s the rim is larger than the core"):format(s))
  end
  -- A wider stroke setting is honoured rather than shrunk to the floor.
  local wide = LD.DotMetrics(9, 1)
  near(wide.screenSize, 9, "A: a 9px stroke is 9 screen px, not the floor", 1e-6)
end

-- ═══ B/C. a real draw: opaque core, dark rim under every dot ═══════════════
local base = boot({ scale = 0.696, pathColorAlpha = 0.9 })
local applied = base.draw()
check(base.M._drawError == nil, "B: draw error: " .. tostring(base.M._drawError))
check(base.M.drawer and base.M.drawer.mode == "dots",
  "B: this client draws the anchored-dot chain (mode=" .. tostring(base.M.drawer and base.M.drawer.mode) .. ")")
do
  local dots = whiteDots(base)
  check(#dots > 20, "B: a chain of white dots covers the route, got " .. #dots)
  check(applied.dots == #dots,
    "B: the draw recorded " .. tostring(applied.dots) .. " dots, the pool shows " .. #dots)
  -- B1. the vertex alpha the CLIENT holds is opaque, not the 0.9 asked for.
  local notOpaque = 0
  local worstScreen = nil
  for i = 1, #dots do
    local o = dots[i][2]
    local v = paintedColour(o) or {}
    if not (v[4] and math.abs(v[4] - 1) < 1e-6) then
      notOpaque = notOpaque + 1
    end
    local screen = o:GetWidth() * 0.696
    if not worstScreen or screen < worstScreen then
      worstScreen = screen
    end
  end
  check(notOpaque == 0,
    "B: every white dot is painted at alpha 1.0 (" .. notOpaque .. " are not)")
  near(applied.alphaRequested, 0.9,
    "B: the alpha the settings asked for is still recorded", 1e-9)
  near(applied.a, 1, "B: and the alpha the draw applied is the opaque one", 1e-9)
  check(worstScreen ~= nil and worstScreen >= 4 - 0.01,
    "B: the narrowest drawn dot is >= 4 screen px (got " .. tostring(worstScreen) .. ")")

  -- C. the dark rim is still there, under, and larger.
  local missing, notLarger, notUnder, wrongCentre = 0, 0, 0, 0
  for i = 1, #dots do
    local wi, w = dots[i][1], dots[i][2]
    local u = base.M.drawer.pool[wi - 1]
    if not isDark(u) then
      missing = missing + 1
    else
      if not (u:GetWidth() > w:GetWidth() + 0.01) then
        notLarger = notLarger + 1
      end
      if not ((u.sublevel or 7) < (w.sublevel or 7)) then
        notUnder = notUnder + 1
      end
      local ucx = u.points[1] and (u.points[1][4] + u.points[2][4]) * 0.5
      local wcx = w.points[1] and (w.points[1][4] + w.points[2][4]) * 0.5
      if not (ucx and wcx and math.abs(ucx - wcx) < 0.01) then
        wrongCentre = wrongCentre + 1
      end
    end
  end
  check(missing == 0, "C: every white dot has a dark rim beneath it (" .. missing .. " missing)")
  check(notLarger == 0, "C: every rim is larger than its dot (" .. notLarger .. " not larger)")
  check(notUnder == 0, "C: the rim never paints over the white dot (" .. notUnder .. " on top)")
  check(wrongCentre == 0, "C: the rim is centred on its dot (" .. wrongCentre .. " off-centre)")
  -- The rim's own screen size: 4 + 2 = 6.
  local u = base.M.drawer.pool[dots[1][1] - 1]
  near(u:GetWidth() * 0.696, 6, "C: the rim measures 6 screen px", 0.05)
end

-- ═══ D. the host is opaque and ignores the alpha it inherits ═══════════════
do
  local ctx = boot({ scale = 0.696, fadedParent = 0.4 })
  ctx.draw()
  local host = ctx.M.host
  check(host ~= nil, "D: the overlay host exists")
  if host then
    near(host:GetAlpha(), 1, "D: the host's own alpha is pinned to 1", 1e-9)
    check(host.ignoreParentAlpha == true,
      "D: the host asked the client to ignore the parent chain's alpha (got "
        .. tostring(host.ignoreParentAlpha) .. ")")
  end
  check(ctx.M._ignoreParentAlpha == true,
    "D: and the read-back says the client accepted it (got "
      .. tostring(ctx.M._ignoreParentAlpha) .. ")")
end

-- ═══ E. the diag prints the alpha CHAIN, and names the ancestor that dims ══
do
  -- A client WITHOUT SetIgnoreParentAlpha: the route can only paint at the
  -- chain's product, and the diag has to say so instead of reading 1.00.
  local weak = boot({ scale = 0.696, fadedParent = 0.4, noIgnoreAlpha = true })
  weak.draw()
  local text = weak.diag()
  local line = lineStartingWith(text, "alpha chain:")
  check(line ~= nil, "E: the diag prints an alpha chain line (got "
    .. tostring(text:match("alpha chain:[^\n]*")) .. ")")
  if line then
    check(line:find("WorldMapFrame=0.40", 1, true) ~= nil,
      "E: the chain shows the faded ancestor's own alpha (got " .. line .. ")")
    check(line:find("effective=0.40", 1, true) ~= nil,
      "E: the chain multiplies down to 0.40 (got " .. line .. ")")
    check(line:find("ignore%-parent%-alpha=absent") ~= nil,
      "E: a client that cannot ignore it says so (got " .. line .. ")")
    check(line:find("EFFECTIVE < 1", 1, true) ~= nil,
      "E: and the effective-alpha warning names the culprit (got " .. line .. ")")
  end
  -- The same chain on a client that CAN ignore it: effective 1, accepted.
  local strong = boot({ scale = 0.696, fadedParent = 0.4 })
  strong.draw()
  local line2 = lineStartingWith(strong.diag(), "alpha chain:")
  check(line2 ~= nil, "E: the strong client prints the chain too")
  if line2 then
    check(line2:find("effective=1.00", 1, true) ~= nil,
      "E: with the ignore flag the effective alpha is 1.00 (got " .. line2 .. ")")
    check(line2:find("ignore%-parent%-alpha=true") ~= nil,
      "E: and the accepted flag is printed (got " .. line2 .. ")")
    check(line2:find("EFFECTIVE < 1", 1, true) == nil,
      "E: no warning when the client can ignore the chain (got " .. line2 .. ")")
  end
end

-- ═══ F. ONE sampled dot, read back from the client ═════════════════════════
do
  local ctx = boot({ scale = 0.696, pathColorAlpha = 0.9 })
  ctx.draw()
  local text = ctx.diag()
  local line = lineStartingWith(text, "sample dot:")
  check(line ~= nil, "F: the diag prints a sampled dot (got "
    .. tostring(text:match("sample dot:[^\n]*")) .. ")")
  if line then
    check(line:find("requested=(1.00,1.00,1.00,1.00)", 1, true) ~= nil,
      "F: the colour the draw applied is printed (got " .. line .. ")")
    check(line:find("alpha asked=0.90", 1, true) ~= nil,
      "F: the alpha the settings asked for is printed beside it (got " .. line .. ")")
    -- This client takes SetColorTexture, so the vertex colour is NOT evidence
    -- about the dot and must not be reported as if it were.
    check(line:find("applied via=SetColorTexture", 1, true) ~= nil,
      "F: the call the client actually took is printed (got " .. line .. ")")
    check(line:find("alpha landed=n/a", 1, true) ~= nil,
      "F: and the vertex colour is not passed off as the dot's colour (got " .. line .. ")")
    check(line:find("layer=OVERLAY", 1, true) ~= nil,
      "F: the draw layer it landed in is printed (got " .. line .. ")")
    check(line:find("blend=BLEND", 1, true) ~= nil,
      "F: the blend mode is printed (got " .. line .. ")")
    check(line:find("4.00 screen px", 1, true) ~= nil,
      "F: the dot's size in screen px is printed (got " .. line .. ")")
    check(line:find("strata=MEDIUM", 1, true) ~= nil,
      "F: its frame strata is printed (got " .. line .. ")")
    check(line:find("level=", 1, true) ~= nil,
      "F: its frame level is printed (got " .. line .. ")")
    check(line:find("shown=true", 1, true) ~= nil,
      "F: whether the client shows it is printed (got " .. line .. ")")
  end
  -- A client WITHOUT SetColorTexture: the colour goes through the vertex colour,
  -- and it is read back from the region.
  local vertexClient = boot({ scale = 0.696, pathColorAlpha = 0.9, noColorTexture = true })
  vertexClient.draw()
  local vLine = lineStartingWith(vertexClient.diag(), "sample dot:")
  check(vLine ~= nil, "F: the vertex-colour client prints a sampled dot")
  if vLine then
    check(vLine:find("applied via=SetVertexColor", 1, true) ~= nil,
      "F: the vertex path is named (got " .. vLine .. ")")
    check(vLine:find("GetVertexColor=(1.00,1.00,1.00,1.00)", 1, true) ~= nil,
      "F: GetVertexColor is READ BACK, not assumed (got " .. vLine .. ")")
    check(vLine:find("alpha landed=yes", 1, true) ~= nil,
      "F: and it agrees with what was asked (got " .. vLine .. ")")
  end
  -- ... and one whose GetVertexColor reports a lower alpha than it was given:
  -- the diag must print the disagreement, not the request again.
  local liar = boot({ scale = 0.696, pathColorAlpha = 0.9, noColorTexture = true, lieAlpha = 0.2 })
  liar.draw()
  local lieLine = lineStartingWith(liar.diag(), "sample dot:")
  check(lieLine ~= nil, "F: the lying client still prints a sampled dot")
  if lieLine then
    check(lieLine:find("GetVertexColor=(1.00,1.00,1.00,0.20)", 1, true) ~= nil,
      "F: the client's own answer is printed (got " .. lieLine .. ")")
    check(lieLine:find("alpha landed=NO", 1, true) ~= nil,
      "F: and the disagreement is reported (got " .. lieLine .. ")")
  end
end

-- ═══ G. what is ABOVE the host over the map ════════════════════════════════
do
  local clean = boot({ scale = 0.696 })
  clean.draw()
  local line = lineStartingWith(clean.diag(), "cover:")
  check(line ~= nil, "G: the diag prints a cover: line")
  if line then
    check(line:find("cover: none", 1, true) ~= nil,
      "G: on a clean map it says nothing covers the route (got " .. line .. ")")
  end
  -- A frame over the map that outranks the host: the z-order audit raises the
  -- host above it (that is what it is for), so afterwards nothing covers the
  -- route and the diag says so — measured off the host's own level.
  local covered = boot({ scale = 0.696, coverFrame = { level = 900, alpha = 1 } })
  covered.draw()
  local cText = covered.diag()
  check(covered.M.host ~= nil, "G: the covered client drew a host")
  if covered.M.host then
    check((covered.M.host:GetFrameLevel() or 0) > 900,
      "G: the host was raised above the frame that outranks it over the map (level="
        .. tostring(covered.M.host:GetFrameLevel()) .. ")")
  end
  local cLine = lineStartingWith(cText, "cover:")
  check(cLine ~= nil, "G: the covered client prints a cover: line")
  if cLine then
    check(cLine:find("cover: none", 1, true) ~= nil,
      "G: and nothing is left covering the raised host (got " .. cLine .. ")")
  end
  local zLine = lineStartingWith(cText, "z-order:")
  check(zLine ~= nil and zLine:find("above the art", 1, true) ~= nil,
    "G: the z-order line reports the host above it (got " .. tostring(zLine) .. ")")
  -- A faded frame over the map is the ghost's other half: named as faded.
  local faded = boot({ scale = 0.696, coverFrame = { level = 1, alpha = 0.3 } })
  faded.draw()
  local fLine = lineStartingWith(faded.diag(), "cover:")
  check(fLine ~= nil, "G: the faded-overlay client prints a cover: line")
  if fLine then
    check(fLine:find("alpha=0.30", 1, true) ~= nil,
      "G: the faded frame's alpha is printed (got " .. fLine .. ")")
    check(fLine:find("faded", 1, true) ~= nil,
      "G: and it is named as faded (got " .. fLine .. ")")
  end
end

-- ═══ H. the legibility contract measured off the DRAWN regions ════════════
do
  local scales = { 0.6, 1.0, 1.5 }
  for i = 1, #scales do
    local s = scales[i]
    local ctx = boot({ scale = s })
    local a = ctx.draw()
    local dots = whiteDots(ctx)
    check(#dots > 0, ("H: the route draws at canvas scale %s"):format(s))
    local worst, worstRim = nil, nil
    for k = 1, #dots do
      local w = dots[k][2]:GetWidth() * s
      if not worst or w < worst then worst = w end
      local rim = ctx.M.drawer.pool[dots[k][1] - 1]
      if rim then
        local rw = rim:GetWidth() * s
        if not worstRim or rw < worstRim then worstRim = rw end
      end
    end
    check(worst ~= nil and worst >= 4 - 0.01,
      ("H: at canvas scale %s every drawn dot is >= 4 screen px (got %s)")
        :format(s, tostring(worst)))
    check(worstRim ~= nil and worstRim >= 6 - 0.01,
      ("H: at canvas scale %s every rim is >= 6 screen px (got %s)")
        :format(s, tostring(worstRim)))
    near(a.dotScreenSize, 4, ("H: and the draw records 4 screen px at scale %s"):format(s), 1e-6)
  end
end


-- ═══ I. how much of the white line SURVIVES the rims ══════════════════════
-- The ghost, measured instead of argued. Every dot is a dark rim painted before
-- its white core, and on the reported draw the rim (3.36 canvas px) was WIDER
-- than the pitch between dots (2.02 canvas px): the next dot's rim crossed into
-- every white core. On the live client there is no SetDrawLayer, so creation
-- order IS draw order and the paint order cannot rescue that geometry — the
-- pitch has to be the RIM width, with the dark band still continuous because
-- the rims touch edge to edge.
--
-- This section measures the PIXELS: for every distinct dot position it takes
-- the core that is visible there (the last one painted at that position) and
-- subtracts every rim painted after it. On 7e3a329 that leaves 44-55% of the
-- white paint, which is exactly "the path is drawn, it is just extremely
-- transparent"; here it has to be worth looking at.
do
  --- The rect a dot occupies in the host, read off its two corner anchors
  --- (y grows downwards from the host's TOPLEFT, so the anchors' y is negated).
  local function dotRect(o)
    local p1, p2 = o.points and o.points[1], o.points and o.points[2]
    if not p1 or not p2 then
      return nil
    end
    local left, right = p1[4] or 0, p2[4] or 0
    if left > right then left, right = right, left end
    local top, bottom = -(p1[5] or 0), -(p2[5] or 0)
    if top > bottom then top, bottom = bottom, top end
    return left, top, right, bottom
  end

  --- { mean white kept, fraction of positions keeping >= half their core }
  local function survivingWhite(ctx)
    local pool = (ctx.M.drawer and ctx.M.drawer.pool) or {}
    local cores, lastCoreAt = {}, {}
    for i = 1, #pool do
      local o = pool[i]
      if o and o.shown and isWhite(o) then
        local l, t, r, b = dotRect(o)
        if l then
          local key = string.format("%.2f,%.2f", (l + r) * 0.5, (t + b) * 0.5)
          if not lastCoreAt[key] then
            cores[#cores + 1] = { l = l, t = t, r = r, b = b, key = key }
          end
          -- The LAST core painted at a position is the one you see there: two
          -- segments share their corner point, so a corner dot is drawn twice.
          lastCoreAt[key] = i
        end
      end
    end
    local total, half = 0, 0
    for a = 1, #cores do
      local c = cores[a]
      local area = (c.r - c.l) * (c.b - c.t)
      local covered = 0
      for j = (lastCoreAt[c.key] or 1) + 1, #pool do
        local rim = pool[j]
        if rim and rim.shown and isDark(rim) then
          local rl, rt, rr, rb = dotRect(rim)
          if rl then
            local w = math.min(c.r, rr) - math.max(c.l, rl)
            local h = math.min(c.b, rb) - math.max(c.t, rt)
            if w > 0 and h > 0 then
              covered = covered + math.min(w * h, area)
            end
          end
        end
      end
      local keep = math.max(0, 1 - covered / area)
      total = total + keep
      if keep >= 0.5 then
        half = half + 1
      end
    end
    if #cores == 0 then
      return 0, 0
    end
    return total / #cores, half / #cores
  end

  for _, shape in ipairs({ { name = "sublevels", cfg = {} },
                           { name = "creation order (no SetDrawLayer)", cfg = { noDrawLayer = true } } }) do
    for _, s in ipairs({ 0.6, 1.0, 1.5 }) do
      local cfg = { scale = s }
      for k, v in pairs(shape.cfg) do
        cfg[k] = v
      end
      local ctx = boot(cfg)
      local a = ctx.draw()
      check(#whiteDots(ctx) > 0, ("I: %s at canvas scale %s draws a dot chain"):format(shape.name, s))
      -- The geometry the draw states, in screen px: the pitch is the rim width,
      -- so a neighbour's rim stops at or before this core's edge.
      check(type(a.dotSpacing) == "number" and type(a.dotOutline) == "number"
          and a.dotScreenSpacing >= a.dotScreenOutline,
        ("I: %s at canvas scale %s pitches the dots by the rim width (pitch=%s rim=%s screen px)")
          :format(shape.name, s, tostring(a.dotScreenSpacing), tostring(a.dotScreenOutline)))
      check(type(a.dotClearance) == "number" and a.dotClearance >= -1e-6,
        ("I: %s at canvas scale %s records a non-negative rim-to-core clearance (got %s px)")
          :format(shape.name, s, tostring(a.dotClearance)))
      -- ... and the pixels that survive the whole chain.
      local mean, half = survivingWhite(ctx)
      check(mean >= 0.75,
        ("I: %s at canvas scale %s keeps %.0f%% of the white paint (needs >= 75%%)")
          :format(shape.name, s, mean * 100))
      check(half >= 0.95,
        ("I: %s at canvas scale %s — %.0f%% of the dot positions keep at least half a core (needs >= 95%%)")
          :format(shape.name, s, half * 100))
    end
  end
end

if failed > 0 then
  io.stderr:write(failed .. " map legibility check(s) failed\n")
  os.exit(1)
end
print("maplegibility_spec: ok")

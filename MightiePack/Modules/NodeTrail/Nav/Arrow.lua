local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

-- The followable element: a next-waypoint arrow on the minimap with the
-- distance to it in yards counting down.
--
-- Why this exists: a world-anchored line on a player-centred minimap slides
-- under the player — "visually the lines move across the minimap as i walk, i
-- cant follow a route if it continues to move". The arrow does not slide: it
-- names ONE point, points at it, and counts the yards down.
--
-- The pointer is drawn from the primitive this client has PROVED it honours —
-- a texture sized by two corner anchors (see LineDraw.TextureProof: every
-- SetStartPoint/SetEndPoint pair was accepted and kept no geometry, while
-- two-anchor textures do render). It is built out of dots along the bearing
-- rather than one rotated texture, so its direction comes from arithmetic the
-- specs can check, not from a rotation whose sign nobody has verified by eye.

ns.Nav = ns.Nav or {}
local N = ns.Nav
N.Arrow = N.Arrow or {}
local A = N.Arrow

local T = N.Target
local S = N.Source

local UPDATE_INTERVAL = 0.2   -- 5 Hz; the distance counts down in whole yards
local RING_INSET = 0.84       -- where the marker sits when the target is off-view
local HEAD_SCREEN = 5.0       -- screen px of the arrowhead dot
local FLANK_SCREEN = 3.6
local SHAFT_SCREEN = 2.8
local RIM_GROW = 2.0          -- screen px the dark rim adds
local HEAD_LEN = 9.0          -- screen px from the base to the tip
local FLANK_WIDE = 3.6
local SHAFT_LEN = 3.0
local LABEL_GAP = 9.0
local DEFAULT_RANGE = 1200    -- yards; beyond this the arrow is hidden
local CORE_R, CORE_G, CORE_B, CORE_A = 0.25, 1, 0.4, 1
local RIM_R, RIM_G, RIM_B, RIM_A = 0, 0, 0, 1

local function finite(v)
  return type(v) == "number" and v == v and v > -1e300 and v < 1e300
end

local function say(text, once)
  if once then
    A._said = A._said or {}
    if A._said[text] then
      return
    end
    A._said[text] = true
  end
  local line = "NodeTrail nav: " .. tostring(text)
  if type(DEFAULT_CHAT_FRAME) == "table" and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
    local ok = pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, line)
    if ok then
      return
    end
  end
  pcall(print, line)
end

local function db()
  local profile = ns.GetDB()
  local range = tonumber(profile.navRange)
  if not finite(range) or range <= 0 then
    range = DEFAULT_RANGE
  end
  local arrive = tonumber(profile.navArriveYards)
  if not finite(arrive) or arrive <= 0 then
    arrive = T.ARRIVE_YARDS
  end
  return profile, range, arrive
end

-- ── the frame ───────────────────────────────────────────────────────────────
function A:EnsureFrames()
  if self.host then
    return self.host
  end
  if type(Minimap) ~= "table" or type(CreateFrame) ~= "function" then
    return nil
  end
  local ok, host = pcall(CreateFrame, "Frame", nil, Minimap)
  if not ok or not host then
    return nil
  end
  ns.LineDraw.BindOverlay(host, Minimap)
  -- Above the minimap line, so the arrow is never buried under the dots.
  if host.SetFrameLevel and type(Minimap.GetFrameLevel) == "function" then
    local okL, level = pcall(Minimap.GetFrameLevel, Minimap)
    if okL and finite(level) then
      pcall(host.SetFrameLevel, host, level + 6)
    end
  end
  pcall(host.Hide, host)
  self.host = host
  self.dots = self.dots or {}
  return host
end

local function ensureLabel(app, host)
  if app.label or not host or type(host.CreateFontString) ~= "function" then
    return app.label
  end
  local ok, label = pcall(host.CreateFontString, host, nil, "OVERLAY", "GameFontNormalSmall")
  if not ok or not label then
    return nil
  end
  -- An outline is what makes the number readable over any map art; if the
  -- client refuses SetFont, the plain font object is still usable.
  if type(label.SetFont) == "function" and type(GameFontNormalSmall) == "table"
    and type(GameFontNormalSmall.GetFont) == "function" then
    local okG, path, size, flags = pcall(GameFontNormalSmall.GetFont, GameFontNormalSmall)
    if okG and type(path) == "string" then
      pcall(label.SetFont, label, path, size, ((flags or "") .. "OUTLINE"))
    end
  end
  pcall(label.SetTextColor, label, CORE_R, CORE_G, CORE_B)
  if label.SetJustifyH then
    pcall(label.SetJustifyH, label, "CENTER")
  end
  if label.SetJustifyV then
    pcall(label.SetJustifyV, label, "MIDDLE")
  end
  pcall(label.Hide, label)
  app.label = label
  return label
end

local function acquire(app, index, host)
  local tex = app.dots[index]
  if tex then
    return tex
  end
  if type(host.CreateTexture) ~= "function" then
    return nil
  end
  local ok, created = pcall(host.CreateTexture, host, nil, "OVERLAY")
  if not ok or not created then
    return nil
  end
  app.dots[index] = created
  return created
end

--- One square, sized by two corner anchors in "pixels from the minimap centre,
--- +y up". This is the primitive the live client proved it keeps.
local function paintSquare(tex, host, cx, cy, size, r, g, b, a, sublevel)
  local half = (size or 2) * 0.5
  pcall(tex.SetParent, tex, host)
  if tex.SetColorTexture then
    pcall(tex.SetColorTexture, tex, r, g, b, a)
  elseif tex.SetTexture then
    pcall(tex.SetTexture, tex, "Interface\\Buttons\\WHITE8X8")
    if tex.SetVertexColor then
      pcall(tex.SetVertexColor, tex, r, g, b, a)
    end
  end
  if tex.SetDrawLayer then
    pcall(tex.SetDrawLayer, tex, "OVERLAY", sublevel or 7)
  end
  if tex.SetBlendMode then
    pcall(tex.SetBlendMode, tex, "BLEND")
  end
  if tex.SetTexCoord then
    pcall(tex.SetTexCoord, tex, 0, 1, 0, 1)
  end
  pcall(tex.ClearAllPoints, tex)
  pcall(tex.SetPoint, tex, "BOTTOMLEFT", host, "CENTER", cx - half, cy - half)
  pcall(tex.SetPoint, tex, "TOPRIGHT", host, "CENTER", cx + half, cy + half)
  pcall(tex.SetRotation, tex, 0)
  pcall(tex.Show, tex)
end

local function hideAll(app)
  for i = 1, #(app.dots or {}) do
    pcall(app.dots[i].Hide, app.dots[i])
  end
  if app.label then
    pcall(app.label.Hide, app.label)
  end
  if app.host then
    pcall(app.host.Hide, app.host)
  end
end

-- ── the update ─────────────────────────────────────────────────────────────
--- Where the marker goes, in pixels from the minimap centre (+y up).
--- Pure enough to spec: it is the same transform HereBeDragons-Pins applies,
--- so the arrow sits on the projection the minimap line already uses.
--- @param east, north yards from the player to the target
--- @param viewRadius yards the minimap covers from centre to edge
--- @param halfW, halfH minimap half-size in pixels
--- @param facing GetPlayerFacing() when the minimap is turned with the player
function A.ProjectOffset(east, north, viewRadius, halfW, halfH, facing)
  if not (finite(east) and finite(north) and finite(viewRadius) and finite(halfW)
    and finite(halfH)) then
    return nil
  end
  if viewRadius <= 0 then
    return nil
  end
  local px = (east / viewRadius) * halfW
  local py = (north / viewRadius) * halfH
  if finite(facing) then
    local cosF, sinF = math.cos(facing), math.sin(facing)
    px, py = px * cosF + py * sinF, py * cosF - px * sinF
  end
  return px, py
end

--- The five dots that make the pointer, in the same pixel space.
--- The arrowhead's TIP is the waypoint: a target inside the view is marked
--- exactly where it is, and a target outside it is clamped to the ring so the
--- tip sits on the edge instead of off the minimap.
--- @return array of { x, y, size } — head first, then flanks, then the shaft
function A.MarkerPose(px, py, ringRadius, dirX, dirY)
  local len = math.sqrt((dirX or 0) * (dirX or 0) + (dirY or 0) * (dirY or 0))
  if not finite(len) or len < 1e-9 then
    dirX, dirY = 0, 1
  else
    dirX, dirY = dirX / len, dirY / len
  end
  local tipX, tipY, clamped = T.RingClamp(px, py, ringRadius)
  if not tipX then
    return {}
  end
  local baseX, baseY = tipX - dirX * HEAD_LEN, tipY - dirY * HEAD_LEN
  local perpX, perpY = -dirY, dirX
  local out = {
    { x = tipX, y = tipY, size = HEAD_SCREEN },
    { x = baseX + perpX * FLANK_WIDE, y = baseY + perpY * FLANK_WIDE, size = FLANK_SCREEN },
    { x = baseX - perpX * FLANK_WIDE, y = baseY - perpY * FLANK_WIDE, size = FLANK_SCREEN },
    { x = baseX, y = baseY, size = SHAFT_SCREEN },
    { x = baseX - dirX * SHAFT_LEN, y = baseY - dirY * SHAFT_LEN, size = SHAFT_SCREEN },
  }
  out.clamped = clamped
  out.baseX, out.baseY = baseX, baseY
  out.tipX, out.tipY = tipX, tipY
  out.dirX, out.dirY = dirX, dirY
  return out
end

function A:Clear()
  self.route = nil
  self.mapID = nil
  self.points = nil
  self.prev = nil
  self.why = "no active route"
  self.last = nil
  self:StopUpdates()
  hideAll(self)
end

function A:StopUpdates()
  if self._driver and type(self._driver.SetScript) == "function" then
    pcall(self._driver.SetScript, self._driver, "OnUpdate", nil)
  end
  self._acc = 0
end

function A:StartUpdates()
  local driver = self._driver
  if not driver or type(driver.SetScript) ~= "function" then
    return
  end
  self._acc = 0
  pcall(driver.SetScript, driver, "OnUpdate", function(_, elapsed)
    A._acc = (A._acc or 0) + (elapsed or 0)
    if A._acc < UPDATE_INTERVAL then
      return
    end
    A._acc = 0
    A:Redraw()
  end)
end

function A:SetRoute(route)
  if type(route) ~= "table" or type(route.path) ~= "table" or #route.path < 2 then
    self:Clear()
    return
  end
  self.route = route
  self.mapID = route.mapID
  -- Keep only the points that are real map fractions; a route point without
  -- x/y cannot be converted to yards and must not shift the indices of the
  -- ones that can.
  local points = {}
  for i = 1, #route.path do
    local p = route.path[i]
    if ns.PathGeom.IsMapPoint(p) then
      points[#points + 1] = { x = p.x, y = p.y }
    end
  end
  self.points = points
  self.prev = nil
  self.why = nil
  self:StartUpdates()
  self:Redraw()
end

local function targetYards(points, fx, fy, zoneW, zoneH)
  local out = {}
  for i = 1, #points do
    local p = points[i]
    out[i] = {
      -- +x east, +y north, both in yards: the plane Nav.Target expects.
      x = (p.x - fx) * zoneW,
      y = (fy - p.y) * zoneH,
    }
  end
  return out
end

function A:_redraw()
  local profile, range, arrive = db()
  local host = self:EnsureFrames()
  if not host then
    self.why = "no overlay host (CreateFrame failed on the minimap)"
    hideAll(self)
    return
  end
  if not self.route or not self.points or #self.points < 2 then
    self.why = "no active route"
    hideAll(self)
    return
  end
  if profile.showNavArrow == false then
    self.why = "the waypoint arrow is off (db.showNavArrow = false)"
    hideAll(self)
    return
  end
  if type(Minimap) == "table" and type(Minimap.IsVisible) == "function" then
    local okV, visible = pcall(Minimap.IsVisible, Minimap)
    if okV and not visible then
      self.why = "the minimap is hidden"
      hideAll(self)
      return
    end
  end

  local zoneW, zoneH, howScale = S.ZoneSize(self.mapID)
  if not zoneW then
    self.why = tostring(howScale)
    hideAll(self)
    say("the waypoint arrow is off: " .. tostring(howScale)
      .. ". No distance is shown rather than a guessed one.", true)
    return
  end
  local fx, fy, howPlayer = S.PlayerFrac(self.mapID)
  if not fx then
    self.why = "no player position on the route's map: " .. tostring(howPlayer)
    hideAll(self)
    return
  end
  local viewRadius, howRadius = S.ViewRadiusYards()
  if not viewRadius then
    self.why = tostring(howRadius)
    hideAll(self)
    return
  end
  local okW, halfW = pcall(Minimap.GetWidth, Minimap)
  local okH, halfH = pcall(Minimap.GetHeight, Minimap)
  if not okW or not okH or not finite(halfW) or not finite(halfH) or halfW < 8 or halfH < 8 then
    self.why = "the minimap has no measurable size"
    hideAll(self)
    return
  end
  halfW, halfH = halfW * 0.5, halfH * 0.5

  local pts = targetYards(self.points, fx, fy, zoneW, zoneH)
  local sel, whySel = T.Next(pts, 0, 0, { prev = self.prev, radius = arrive })
  if not sel then
    self.why = tostring(whySel)
    hideAll(self)
    return
  end
  -- Store the target so the NEXT update can only advance: a player who walks
  -- back over a waypoint cannot make the arrow point behind the route.
  self.prev = sel.index

  if sel.complete then
    self.why = "the route is complete"
    self.last = { index = sel.index, dist = sel.dist, complete = true }
    hideAll(self)
    return
  end
  if not finite(sel.dist) or sel.dist > range then
    self.why = string.format("the next waypoint is %s away, past the %d yd arrow range",
      sel.dist and T.YardText(sel.dist) or "?", math.floor(range))
    self.last = { index = sel.index, dist = sel.dist, outOfRange = true }
    hideAll(self)
    return
  end

  local rotate = S.RotateMinimap()
  local facing
  if rotate then
    local value, whyFacing = S.Facing()
    if not finite(value) then
      self.why = "the minimap turns with the player and GetPlayerFacing() is unavailable: "
        .. tostring(whyFacing)
      hideAll(self)
      return
    end
    facing = value
  end

  local px, py = A.ProjectOffset(sel.east, sel.north, viewRadius, halfW, halfH, facing)
  if not px then
    self.why = "no projectable offset (a zone size or view radius of 0)"
    hideAll(self)
    return
  end
  local ringRadius = math.min(halfW, halfH) * RING_INSET
  local pose = A.MarkerPose(px, py, ringRadius, px, py)
  if #pose == 0 then
    self.why = "no placeable marker on the minimap ring"
    hideAll(self)
    return
  end

  -- Screen px -> canvas px for this host, the same measurement the route dots
  -- use, so a 4px arrow is 4px on the screen at any UI scale.
  local hostScale = 1
  if type(host.GetScale) == "function" then
    local okS, s = pcall(host.GetScale, host)
    if okS and finite(s) and s > 0 then
      hostScale = s
    end
  end
  local rimGrow = RIM_GROW / hostScale

  local index = 1
  for i = 1, #pose do
    local dot = pose[i]
    local size = dot.size / hostScale
    local under = acquire(self, index, host)
    if under then
      -- The dark rim goes under the core, 2 screen px larger: a bright marker
      -- over bright terrain is the same failure as an invisible line.
      paintSquare(under, host, dot.x, dot.y, size + rimGrow,
        RIM_R, RIM_G, RIM_B, RIM_A, 6)
    end
    index = index + 1
    local core = acquire(self, index, host)
    if core then
      paintSquare(core, host, dot.x, dot.y, size, CORE_R, CORE_G, CORE_B, CORE_A, 7)
    end
    index = index + 1
  end
  for i = index, #self.dots do
    pcall(self.dots[i].Hide, self.dots[i])
  end

  local label = ensureLabel(self, host)
  if label then
    -- Inside the ring when the marker is clamped to it (a label hanging off the
    -- minimap would sit over unrelated UI), beyond the tip when it is not.
    local offset = pose.clamped and -(HEAD_LEN + LABEL_GAP) or LABEL_GAP
    local lx = pose[1].x + pose.dirX * offset
    local ly = pose[1].y + pose.dirY * offset
    pcall(label.SetText, label, T.YardText(sel.dist))
    pcall(label.ClearAllPoints, label)
    pcall(label.SetPoint, label, "CENTER", host, "CENTER", lx, ly)
    pcall(label.Show, label)
  end

  pcall(host.Show, host)
  self.why = nil
  self.last = {
    index = sel.index,
    dist = sel.dist,
    bearing = T.Bearing(sel.east, sel.north),
    east = sel.east,
    north = sel.north,
    px = pose[1].x,
    py = pose[1].y,
    projectedX = px,
    projectedY = py,
    clamped = pose.clamped and true or false,
    segment = sel.segment,
    advanced = sel.advanced,
    zoneW = zoneW,
    zoneH = zoneH,
    viewRadius = viewRadius,
    facing = facing,
    rotate = rotate and true or false,
    dots = #pose,
    zoneHow = howScale,
    hostScale = hostScale,
    radiusHow = howRadius,
    playerHow = howPlayer,
  }
end

function A:Redraw()
  if self._busy then
    return
  end
  self._busy = true
  local ok, err = pcall(self._redraw, self)
  self._busy = false
  if not ok then
    self._drawError = tostring(err)
    hideAll(self)
  else
    self._drawError = nil
  end
end

local driver = CreateFrame("Frame")
A._driver = driver

-- ── /nt navdiag ─────────────────────────────────────────────────────────────
function A.Diag(app)
  app = app or A
  local out = {}
  local function put(text)
    out[#out + 1] = text
  end
  local okDesc, lines = pcall(S.Describe, app.mapID, app.route)
  if okDesc and type(lines) == "table" then
    for i = 1, #lines do
      put(lines[i])
    end
  else
    put("environment probe failed: " .. tostring(lines))
  end

  local profile, range, arrive = db()
  put(string.format("arrow: %s; range=%d yd; arrival radius=%d yd; refresh=%d Hz",
    (profile.showNavArrow ~= false) and "on" or "off", math.floor(range),
    math.floor(arrive), math.floor(1 / UPDATE_INTERVAL + 0.5)))
  put(string.format("arrow target: %s", (function()
    local last = app.last
    if type(last) ~= "table" then
      return "not measured yet (" .. tostring(app.why or "no redraw") .. ")"
    end
    if last.complete then
      return "route complete"
    end
    if last.outOfRange then
      return string.format("next is point #%d at %s — past the arrow range",
        last.index, T.YardText(last.dist))
    end
    return string.format(
      "next=point #%d of %d; dist=%s; bearing=%s rad (%s); player->target east=%s yd north=%s yd",
      last.index, app.points and #app.points or 0, T.YardText(last.dist),
      S.Fmt(last.bearing, 4), tostring(T.CompassWord(last.bearing)),
      S.Fmt(last.east, 1), S.Fmt(last.north, 1))
  end)()))
  put(string.format("arrow scale: zone=%s x %s yd (%s); minimap view radius=%s yd (%s); player (%s)",
    S.Fmt((app.last or {}).zoneW, 1), S.Fmt((app.last or {}).zoneH, 1),
    tostring((app.last or {}).zoneHow or "not used yet"),
    S.Fmt((app.last or {}).viewRadius, 2),
    tostring((app.last or {}).radiusHow or "not used yet"),
    tostring((app.last or {}).playerHow or "not used yet")))
  put(string.format("arrow marker: projected=(%s,%s) px; drawn=(%s,%s) px; %s; %s",
    S.Fmt((app.last or {}).projectedX, 1), S.Fmt((app.last or {}).projectedY, 1),
    S.Fmt((app.last or {}).px, 1), S.Fmt((app.last or {}).py, 1),
    ((app.last or {}).clamped and "clamped to the ring" or "inside the ring"),
    ((app.last or {}).rotate and "minimap turned with the player" or "minimap north up")))
  put(string.format("arrow draw: %s dot(s) in %d texture object(s); host scale=%s; drawError=%s",
    tostring((app.last or {}).dots or 0),
    #(app.dots or {}), S.Fmt(hostScale and hostScale or nil, 3),
    tostring(app._drawError or "none")))
  if app.why then
    put("arrow verdict: hidden — " .. tostring(app.why))
  else
    put("arrow verdict: drawn")
  end
  return out
end

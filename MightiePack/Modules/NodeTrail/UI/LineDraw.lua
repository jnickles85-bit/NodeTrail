local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

-- White polyline segments.
-- Prefer Frame:CreateLine (Classic canvas clients and Forever).
-- Otherwise a rotated WHITE8X8 texture (SetRotation, 3.1+).
-- Otherwise the taxi-route SetTexCoord quad (UI-Taxi-Line), which is the
-- Classic technique that does not need SetRotation.

ns.LineDraw = ns.LineDraw or {}
local D = ns.LineDraw

local WHITE = "Interface\\Buttons\\WHITE8X8"
local TAXI = "Interface\\TaxiFrame\\UI-Taxi-Line"
local LINEFACTOR = 128 / 126
local LINEFACTOR_2 = LINEFACTOR / 2

function D.ColorWidth()
  local db = ns.GetDB()
  local c = db.pathColor
  local r, g, b, a = 1, 1, 1, 0.9
  if type(c) == "table" then
    r = tonumber(c[1]) or r
    g = tonumber(c[2]) or g
    b = tonumber(c[3]) or b
    a = tonumber(c[4]) or a
  end
  local width = tonumber(db.pathWidth) or 2
  if width <= 0 then
    width = 2
  end
  return r, g, b, a, width
end

function D.BindOverlay(host, parent)
  if not host or not parent then
    return
  end
  pcall(host.SetParent, host, parent)
  pcall(host.ClearAllPoints, host)
  pcall(host.SetAllPoints, host, parent)
  if host.EnableMouse then
    pcall(host.EnableMouse, host, false)
  end
  if host.EnableMouseWheel then
    pcall(host.EnableMouseWheel, host, false)
  end
  if host.SetMouseClickEnabled then
    pcall(host.SetMouseClickEnabled, host, false)
  end
  if host.EnableMouseMotion then
    pcall(host.EnableMouseMotion, host, false)
  end
  if host.SetPassThroughButtons then
    pcall(host.SetPassThroughButtons, host, "LeftButton", "RightButton", "MiddleButton")
  end
  if parent.GetFrameLevel and host.SetFrameLevel then
    local ok, level = pcall(parent.GetFrameLevel, parent)
    if ok and type(level) == "number" then
      pcall(host.SetFrameLevel, host, level + 3)
    end
  end
end

function D.Create()
  return {
    pool = {},
    mode = nil,
    disableLine = false,
  }
end

--- Live state of one pool object, for /nt mapdiag. Every read is guarded, so a
--- region missing a getter reports nil ("absent") instead of erroring. The
--- point fields are the real 5-value region contract
--- (point, relativeTo, relativePoint, offsetX, offsetY).
function D.Describe(obj)
  if type(obj) ~= "table" then
    return { present = false }
  end
  local function read(method, ...)
    local fn = obj[method]
    if type(fn) ~= "function" then
      return nil
    end
    local ok, a, b, c, d, e = pcall(fn, obj, ...)
    if not ok then
      return nil
    end
    return a, b, c, d, e
  end
  local d = { present = true, kind = obj.kind }
  local shown = read("IsShown")
  if shown == nil then
    shown = read("IsVisible")
  end
  d.shown = shown
  d.alpha = read("GetAlpha")
  d.thickness = read("GetThickness")
  local p1, _, rp1, x1, y1 = read("GetStartPoint")
  if type(p1) == "string" then
    d.start = { p1, rp1, x1, y1 }
  end
  local p2, _, rp2, x2, y2 = read("GetEndPoint")
  if type(p2) == "string" then
    d.stop = { p2, rp2, x2, y2 }
  end
  d.width = read("GetWidth")
  d.height = read("GetHeight")
  local tex = read("GetTexture")
  if type(tex) == "string" then
    d.texture = tex
  end
  return d
end

--- What the last Draw actually applied. The client cannot be asked "what colour
--- is this line", so the drawer records the values it passed: a diag that only
--- re-reads pathColor reports the setting, not the draw.
function D.Applied(drawer)
  return drawer and drawer.lastApplied or nil
end

local function applyColor(obj, r, g, b, a, texturePath)
  if obj.SetColorTexture then
    local ok = pcall(obj.SetColorTexture, obj, r, g, b, a)
    if ok then
      return
    end
  end
  if obj.SetTexture then
    pcall(obj.SetTexture, obj, texturePath or WHITE)
  end
  if obj.SetVertexColor then
    pcall(obj.SetVertexColor, obj, r, g, b, a)
  end
end

local function hideObj(obj)
  if not obj then
    return
  end
  pcall(obj.Hide, obj)
  if obj.ClearAllPoints then
    pcall(obj.ClearAllPoints, obj)
  end
  if obj.SetRotation then
    pcall(obj.SetRotation, obj, 0)
  end
  if obj.SetTexCoord then
    pcall(obj.SetTexCoord, obj, 0, 1, 0, 1)
  end
end

function D.Clear(drawer)
  if not drawer or not drawer.pool then
    return
  end
  for i = 1, #drawer.pool do
    hideObj(drawer.pool[i])
  end
end

function D.Invalidate(drawer)
  D.Clear(drawer)
  if drawer then
    drawer.pool = {}
    drawer.mode = nil
  end
end

local function detect(drawer, parent)
  drawer.pool = drawer.pool or {}
  if not drawer.disableLine and type(parent.CreateLine) == "function" then
    local ok, line = pcall(function()
      local created = parent:CreateLine(nil, "OVERLAY")
      created:SetThickness(2)
      created:SetStartPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
      created:SetEndPoint("TOPLEFT", parent, "TOPLEFT", 1, 0)
      created:Hide()
      return created
    end)
    if ok and line then
      drawer.mode = "line"
      drawer.pool[1] = line
      return
    end
    drawer.disableLine = true
  end
  if type(parent.CreateTexture) ~= "function" then
    drawer.mode = "none"
    return
  end
  local ok, tex = pcall(parent.CreateTexture, parent, nil, "OVERLAY")
  if not ok or not tex then
    drawer.mode = "none"
    return
  end
  tex:Hide()
  drawer.pool[1] = tex
  if tex.SetRotation then
    drawer.mode = "rotate"
  else
    drawer.mode = "texcoord"
  end
end

local function acquire(drawer, index, parent)
  local obj = drawer.pool[index]
  if obj then
    return obj
  end
  local created
  if drawer.mode == "line" and type(parent.CreateLine) == "function" then
    local ok, line = pcall(parent.CreateLine, parent, nil, "OVERLAY")
    if ok then
      created = line
    end
  end
  if not created and type(parent.CreateTexture) == "function" then
    local ok, tex = pcall(parent.CreateTexture, parent, nil, "OVERLAY")
    if ok then
      created = tex
    end
  end
  drawer.pool[index] = created
  return created
end

local function hideFrom(drawer, index)
  for i = index, #drawer.pool do
    hideObj(drawer.pool[i])
  end
end

local function paintLine(obj, parent, x1, y1, x2, y2, thickness, r, g, b, a, space)
  obj:SetParent(parent)
  applyColor(obj, r, g, b, a, WHITE)
  if obj.SetThickness then
    obj:SetThickness(thickness)
  end
  obj:ClearAllPoints()
  if space == "yup" then
    obj:SetStartPoint("CENTER", parent, "CENTER", x1, y1)
    obj:SetEndPoint("CENTER", parent, "CENTER", x2, y2)
  else
    obj:SetStartPoint("TOPLEFT", parent, "TOPLEFT", x1, -y1)
    obj:SetEndPoint("TOPLEFT", parent, "TOPLEFT", x2, -y2)
  end
  obj:Show()
end

local function paintRotate(obj, parent, x1, y1, x2, y2, thickness, r, g, b, a, space)
  local dx, dy = x2 - x1, y2 - y1
  local length = math.sqrt(dx * dx + dy * dy)
  if length < 0.75 then
    obj:Hide()
    return
  end
  obj:SetParent(parent)
  obj:ClearAllPoints()
  if obj.SetTexture then
    obj:SetTexture(WHITE)
  end
  if obj.SetVertexColor then
    obj:SetVertexColor(r, g, b, a)
  end
  if obj.SetTexCoord then
    obj:SetTexCoord(0, 1, 0, 1)
  end
  if obj.SetDrawLayer then
    pcall(obj.SetDrawLayer, obj, "OVERLAY", 7)
  end
  if obj.SetBlendMode then
    pcall(obj.SetBlendMode, obj, "BLEND")
  end
  -- Extra width is centered, so joins overlap by half the stroke.
  if obj.SetWidth then
    obj:SetWidth(length + thickness)
  end
  if obj.SetHeight then
    obj:SetHeight(thickness)
  end
  local cx = (x1 + x2) * 0.5
  local cy = (y1 + y2) * 0.5
  if space == "yup" then
    obj:SetPoint("CENTER", parent, "CENTER", cx, cy)
    obj:SetRotation(math.atan2(dy, dx))
  else
    obj:SetPoint("CENTER", parent, "TOPLEFT", cx, -cy)
    obj:SetRotation(math.atan2(-dy, dx))
  end
  obj:Show()
end

local function clampTex(v)
  if v > 10000 then return 10000 end
  if v < -10000 then return -10000 end
  return v
end

-- Blizzard TaxiFrame / LibGraph line. `sx,sy` are parent BOTTOMLEFT, +y up.
local function paintTexCoord(obj, parent, sx, sy, ex, ey, w, r, g, b, a)
  local dx, dy = ex - sx, ey - sy
  local len = (dx * dx + dy * dy) ^ 0.5
  if not len or len < 0.75 or not w or w <= 0 then
    obj:Hide()
    return
  end
  local ext = w * 0.5
  local ux, uy = dx / len, dy / len
  sx = sx - ux * ext
  sy = sy - uy * ext
  ex = ex + ux * ext
  ey = ey + uy * ext
  dx, dy = ex - sx, ey - sy
  len = (dx * dx + dy * dy) ^ 0.5
  if dx < 0 then
    dx, dy = -dx, -dy
  end
  local s = -dy / len
  local c = dx / len
  local sc = s * c
  local Bwid, Bhgt, BLx, BLy, TLx, TLy, TRx, TRy, BRx, BRy
  if dy >= 0 then
    Bwid = ((len * c) - (w * s)) * LINEFACTOR_2
    Bhgt = ((w * c) - (len * s)) * LINEFACTOR_2
    BLx, BLy, BRy = (w / len) * sc, s * s, (len / w) * sc
    BRx, TLx, TLy, TRx = 1 - BLy, BLy, 1 - BRy, 1 - BLx
    TRy = BRx
  else
    Bwid = ((len * c) + (w * s)) * LINEFACTOR_2
    Bhgt = ((w * c) + (len * s)) * LINEFACTOR_2
    BLx, BLy, BRx = s * s, -(len / w) * sc, 1 + (w / len) * sc
    BRy, TLx, TLy, TRy = BLx, 1 - BRx, 1 - BLx, 1 - BLy
    TRx = TLy
  end
  local cx = (sx + ex) * 0.5
  local cy = (sy + ey) * 0.5
  obj:SetParent(parent)
  obj:ClearAllPoints()
  if obj.SetTexture then
    obj:SetTexture(TAXI)
  end
  if obj.SetVertexColor then
    obj:SetVertexColor(r, g, b, a)
  end
  if obj.SetDrawLayer then
    pcall(obj.SetDrawLayer, obj, "OVERLAY", 7)
  end
  if obj.SetTexCoord then
    obj:SetTexCoord(
      clampTex(TLx), clampTex(TLy),
      clampTex(BLx), clampTex(BLy),
      clampTex(TRx), clampTex(TRy),
      clampTex(BRx), clampTex(BRy)
    )
  end
  obj:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", cx - Bwid, cy - Bhgt)
  obj:SetPoint("TOPRIGHT", parent, "BOTTOMLEFT", cx + Bwid, cy + Bhgt)
  obj:Show()
end

local function toBottomLeft(parent, x1, y1, x2, y2, space)
  local w = parent:GetWidth() or 0
  local h = parent:GetHeight() or 0
  if space == "yup" then
    return w * 0.5 + x1, h * 0.5 + y1, w * 0.5 + x2, h * 0.5 + y2
  end
  return x1, h - y1, x2, h - y2
end

--- Draw `count` segments from `buf[i] = {x1,y1,x2,y2}`.
--- space "ydown": pixels from parent TOPLEFT, +y down.
--- space "yup": pixels from parent CENTER, +y up.
function D.Draw(drawer, parent, buf, count, thickness, r, g, b, a, space)
  if not drawer or not parent then
    return
  end
  if drawer.parent ~= parent then
    D.Invalidate(drawer)
    drawer.parent = parent
  end
  if not drawer.mode then
    detect(drawer, parent)
  end
  count = count or 0
  -- Record what this draw applies: the in-client diag can read the pool
  -- objects' geometry but not their colour, so the values the code actually
  -- passed are the only truthful answer to "is alpha 0 / did pathColor apply".
  drawer.lastApplied = {
    mode = drawer.mode,
    count = count,
    thickness = thickness,
    r = r, g = g, b = b, a = a,
    space = space,
  }
  if drawer.mode == "none" or count < 1 then
    D.Clear(drawer)
    return
  end
  for i = 1, count do
    local seg = buf[i]
    local obj = acquire(drawer, i, parent)
    if obj and seg then
      local x1, y1, x2, y2 = seg[1], seg[2], seg[3], seg[4]
      if drawer.mode == "line" then
        paintLine(obj, parent, x1, y1, x2, y2, thickness, r, g, b, a, space)
      elseif drawer.mode == "rotate" then
        paintRotate(obj, parent, x1, y1, x2, y2, thickness, r, g, b, a, space)
      else
        local sx, sy, ex, ey = toBottomLeft(parent, x1, y1, x2, y2, space)
        paintTexCoord(obj, parent, sx, sy, ex, ey, thickness, r, g, b, a)
      end
    end
  end
  hideFrom(drawer, count + 1)
end

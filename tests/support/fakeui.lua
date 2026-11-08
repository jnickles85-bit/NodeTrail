-- A small, MEASURABLE client model for the tooltip-panel specs
-- (tests/tooltip_panel_spec.lua, tests/tooltip_refresh_spec.lua).
--
-- It is deliberately not a mock that says "yes" to everything: text widths are
-- real arithmetic on the glyph count and the font size, frames compute their
-- screen rect from the anchor they were given, and a font change really does
-- change every width. That is what makes "the panel's width is always >= its
-- widest line" a fact the spec can prove rather than restate.
--
-- Not a spec itself: it lives in tests/support/ so the `tests/*.lua` runner
-- never executes it as one.

local F = {}

-- Glyph metrics. One character at font size N is `charWidth * N` wide, one line
-- is `lineHeight * N` tall — the same relationship the client's fonts have, so
-- a bigger font is a wider and taller block.
F.charWidth = 0.55
F.lineHeight = 1.35
F.defaultFontSize = 12
F.defaultScale = 1

-- A switch for the client class this card exists for: one whose
-- `GetStringWidth` returns nothing usable, so every glyph measures 0 even
-- though the font string carries a font. With this on, a panel that reports
-- "the width covers my text" is reporting on numbers it never measured, and
-- the specs require the verdict to say NO instead.
F.blindMeasure = false

-- A font string is only MEASURABLE once it has a font, exactly like the client:
-- `CreateFontString(nil, "ARTWORK")` with no template and no SetFont reports no
-- width and no height. `CreateFontString(nil, "ARTWORK", "GameFontNormal")` is
-- born with that font object. This is what makes a panel that lays rows out
-- before adopting the tooltip's font fail a spec instead of failing in game.
local function newFontString(font)
  local fs = {
    kind = "fontstring",
    text = "",
    fontPath = nil,
    size = nil,
    fontFlags = nil,
    shown = true,
    justify = "LEFT",
    points = {},
  }
  if type(font) == "table" and type(font.path) == "string" then
    fs.fontPath, fs.size, fs.fontFlags =
      font.path, font.size or F.defaultFontSize, font.flags
  end
  function fs:SetText(t) self.text = tostring(t or "") end
  function fs:GetText() return self.text end
  function fs:SetFont(path, sz, flags)
    self.fontPath, self.fontFlags = path, flags
    if type(sz) == "number" then self.size = sz end
  end
  function fs:GetFont()
    if not self.fontPath then return nil end
    return self.fontPath, self.size, self.fontFlags or ""
  end
  function fs:SetFontObject(obj)
    if type(obj) == "table" and type(obj.size) == "number" then
      self.fontPath, self.size = obj.path or "FontObject", obj.size
    end
  end
  function fs:GetStringWidth()
    if F.blindMeasure then return 0 end
    if not self.fontPath or type(self.size) ~= "number" then return 0 end
    return #self.text * self.size * F.charWidth
  end
  function fs:GetHeight()
    if F.blindMeasure then return 0 end
    if not self.fontPath or type(self.size) ~= "number" then return 0 end
    return self.size * F.lineHeight
  end
  function fs:SetJustifyH(j) self.justify = j end
  function fs:SetPoint(p, rel, rp, x, y)
    self.points = { { point = p, relativeTo = rel, relativePoint = rp, x = x or 0, y = y or 0 } }
  end
  function fs:ClearAllPoints() self.points = {} end
  function fs:SetWidth(w) self.width = w end
  function fs:GetWidth() return self.width or self:GetStringWidth() end
  function fs:Show() self.shown = true end
  function fs:Hide() self.shown = false end
  function fs:IsShown() return self.shown end
  return fs
end
F.newFontString = newFontString

local function newTexture()
  local t = { kind = "texture", shown = true, points = {}, width = 0, height = 0 }
  function t:SetAllPoints() self.allPoints = true end
  function t:SetPoint(p, rel, rp, x, y)
    self.points[#self.points + 1] = { point = p, relativeTo = rel, relativePoint = rp, x = x or 0, y = y or 0 }
  end
  function t:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
  function t:SetTexture(r, g, b, a) self.color = { r, g, b, a } end
  function t:GetColor() return self.color end
  function t:SetWidth(w) self.width = w end
  function t:SetHeight(h) self.height = h end
  function t:GetWidth() return self.width end
  function t:GetHeight() return self.height end
  function t:Show() self.shown = true end
  function t:Hide() self.shown = false end
  function t:IsShown() return self.shown end
  return t
end
F.newTexture = newTexture

-- ── frames ────────────────────────────────────────────────────────────────
-- Screen coordinates are y-up with a bottom-left origin, like the client's own
-- GetLeft/GetBottom/GetRight/GetTop. A frame anchored at (x, y) to its parent's
-- BOTTOMLEFT computes its four edges from that anchor and its size — the panel's
-- placement assertions read exactly these numbers.
function F.newFrame(name, parent, sizeW, sizeH)
  local f = {
    kind = "frame",
    name = name,
    parent = parent,
    width = sizeW or 0,
    height = sizeH or 0,
    shown = true,
    scale = 1,
    points = {},
    textures = {},
    fontStrings = {},
    scripts = {},
    hooks = {},
  }
  function f:GetName() return self.name end
  function f:GetParent() return self.parent end
  function f:SetPoint(p, rel, rp, x, y)
    self.points = { { point = p, relativeTo = rel, relativePoint = rp, x = x or 0, y = y or 0 } }
  end
  function f:GetPoint(i)
    local pt = self.points[i or 1]
    if not pt then return nil end
    return pt.point, pt.relativeTo, pt.relativePoint, pt.x, pt.y
  end
  function f:GetNumPoints() return #self.points end
  function f:ClearAllPoints() self.points = {} end
  function f:SetSize(w, h) self.width, self.height = w, h end
  function f:SetWidth(w) self.width = w end
  function f:SetHeight(h) self.height = h end
  function f:GetWidth() return self.width end
  function f:GetHeight() return self.height end
  function f:GetScale() return self.scale end
  function f:SetScale(s) self.scale = s end
  function f:GetEffectiveScale() return self.scale end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:IsShown() return self.shown end
  function f:IsVisible() return self.shown end
  function f:SetFrameStrata(s) self.strata = s end
  function f:GetFrameStrata() return self.strata end
  function f:SetFrameLevel(l) self.level = l end
  function f:GetFrameLevel() return self.level or 0 end
  function f:EnableMouse(e) self.mouse = e end
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:GetScript(n) return self.scripts[n] end
  function f:HookScript(n, fn)
    self.hooks[n] = self.hooks[n] or {}
    table.insert(self.hooks[n], fn)
  end
  function f:CreateTexture(_, layer)
    local t = newTexture()
    t.layer = layer
    self.textures[#self.textures + 1] = t
    return t
  end
  function f:CreateFontString(_, layer, template)
    local fs
    if type(template) == "string" and template ~= "" then
      -- A named font object: the string is born with that font, so it reports a
      -- width immediately.
      fs = newFontString({ path = "Fonts\\FRIZQT__.TTF", size = F.defaultFontSize, flags = "" })
      fs.fontObject = template
    else
      -- No template, no font: 0 width / 0 height until SetFont, like the client.
      fs = newFontString()
    end
    fs.layer = layer
    self.fontStrings[#self.fontStrings + 1] = fs
    return fs
  end
  -- Geometry, derived from the anchor. The parent's own bottom-left is the
  -- origin of a UIParent-sized screen frame.
  local function originOf(frame)
    if type(frame) == "table" and frame.kind == "frame" then
      return frame:GetLeft(), frame:GetBottom()
    end
    return 0, 0
  end
  function f:GetLeft()
    local pt = self.points[1]
    local ox, oy = 0, 0
    local relW, relH = 0, 0
    if pt and pt.relativeTo then
      ox, oy = originOf(pt.relativeTo)
      if pt.relativeTo.GetWidth then
        relW, relH = pt.relativeTo:GetWidth(), pt.relativeTo:GetHeight()
      end
    end
    local rp = pt and pt.relativePoint or ""
    local x = pt and pt.x or 0
    local baseX = ox + (rp:find("RIGHT") and relW or (rp:find("CENTER") and relW * 0.5 or 0)) + x
    local anchor = pt and pt.point or ""
    return baseX - (anchor:find("RIGHT") and self.width * self.scale
      or (anchor:find("CENTER") and self.width * self.scale * 0.5 or 0))
  end
  function f:GetBottom()
    local pt = self.points[1]
    local ox, oy = 0, 0
    local relW, relH = 0, 0
    if pt and pt.relativeTo then
      ox, oy = originOf(pt.relativeTo)
      if pt.relativeTo.GetWidth then
        relW, relH = pt.relativeTo:GetWidth(), pt.relativeTo:GetHeight()
      end
    end
    local rp = pt and pt.relativePoint or ""
    local y = pt and pt.y or 0
    local baseY = oy + (rp:find("TOP") and relH or (rp:find("CENTER") and relH * 0.5 or 0)) + y
    local anchor = pt and pt.point or ""
    return baseY - (anchor:find("TOP") and self.height * self.scale
      or (anchor:find("CENTER") and self.height * self.scale * 0.5 or 0))
  end
  function f:GetRight() return self:GetLeft() + self.width * self.scale end
  function f:GetTop() return self:GetBottom() + self.height * self.scale end
  -- A frame with an explicit rect (used for the tooltip model) overrides the
  -- anchor maths above.
  function f:SetRect(l, b, w, h)
    self.rect = { left = l, bottom = b, right = l + w, top = b + h }
    self.width, self.height = w, h
    function f:GetLeft() return self.rect.left end
    function f:GetRight() return self.rect.right end
    function f:GetBottom() return self.rect.bottom end
    function f:GetTop() return self.rect.top end
  end
  return f
end

-- ── the client's tooltip ───────────────────────────────────────────────────
-- `lines` is what the CLIENT put there (a title, a profession, …). Nothing the
-- addon does may change this table: the specs assert exactly that.
function F.newTooltip(opts)
  opts = opts or {}
  local gt = F.newFrame("GameTooltip", nil, opts.width or 180, opts.height or 60)
  gt.lines = opts.lines or {}
  gt.owner = opts.owner
  gt.shown = opts.shown ~= false
  gt.hooks = {}
  gt.lineFont = { path = "Fonts\\FRIZQT__.TTF", size = opts.fontSize or F.defaultFontSize, flags = "" }
  if opts.left or opts.bottom then
    gt:SetRect(opts.left or 100, opts.bottom or 400, opts.width or 180, opts.height or 60)
  end
  function gt:GetOwner() return self.owner end
  function gt:NumLines() return #self.lines end
  function gt:GetLine(i) return self.lines[i] end
  -- The client's first line, as a font string the addon may only read.
  function gt:SyncFirstLine()
    if self.lines[1] == nil then return nil end
    local fs = newFontString({ path = self.lineFont.path, size = self.lineFont.size,
      flags = self.lineFont.flags })
    fs:SetText(self.lines[1])
    _G["GameTooltipTextLeft1"] = fs
    return fs
  end
  function gt:Show()
    self.shown = true
    for _, fn in ipairs(self.hooks.OnShow or {}) do fn(self) end
  end
  function gt:Hide() self.shown = false end
  gt:SyncFirstLine()
  return gt
end

-- A tooltip that RAISES on any field write. Reading is untouched; every method
-- the addon legitimately needs is served from the backing frame. Any write the
-- addon attempts — a replaced method, a stray field, a flag — fails loudly.
function F.readOnly(source, label)
  local writes = {}
  local proxy = setmetatable({}, {
    __index = function(_, k)
      local v = source[k]
      if type(v) == "function" then
        return function(_, ...) return v(source, ...) end
      end
      return v
    end,
    __newindex = function(_, k, v)
      writes[#writes + 1] = tostring(k)
      error("write to " .. tostring(label or "the tooltip") .. "." .. tostring(k), 2)
    end,
  })
  return proxy, writes
end

-- ── client install ────────────────────────────────────────────────────────
-- Installs the frame factory and UIParent globally and returns the screen.
function F.install(opts)
  opts = opts or {}
  local screenW, screenH = opts.width or 1920, opts.height or 1080
  local ui = F.newFrame("UIParent", nil, screenW, screenH)
  F.screen = ui
  _G.UIParent = ui
  _G.WorldFrame = F.newFrame("WorldFrame", nil, screenW, screenH)
  F.frames = {}
  _G.CreateFrame = function(kind, name, parent)
    local f = F.newFrame(name, parent)
    F.frames[#F.frames + 1] = f
    return f
  end
  return screenW, screenH
end

return F

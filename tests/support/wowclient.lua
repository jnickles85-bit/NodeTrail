-- tests/support/wowclient.lua — a client model that can answer questions about
-- GEOMETRY and MOUSE, which the old per-spec mocks could not.
--
-- Why this file exists (card t_ea66cd84): the four outer tab buttons were dead
-- in the live client while every spec stayed green. `window_tabs_spec` could not
-- see the bug because its mock answered three questions badly:
--
--   * frames had NO RECT (GetLeft/GetTop returned nil unless a spec typed a
--     number in) — so "does anything cover the tab row?" was unanswerable;
--   * `EnableMouse` was accepted and forgotten — so "is this control clickable?"
--     was unanswerable;
--   * `Show`/`Hide` flipped a flag and fired nothing — so the Pack Settings
--     build hook (`panel:SetScript("OnShow", …)`, the only caller that can build
--     the rows from cold) could never run, and a panel that never builds in the
--     client kept a green suite.
--
-- This model answers all three, using WoW's own rules, and it is deliberately
-- measurable rather than agreeable:
--
--   1. A frame's rect is computed from its anchors (one or two points, relative
--      to any region, with offsets), not from numbers a spec typed in.
--   2. A frame is BORN shown. `Show()` on an already-shown frame is a no-op that
--      fires nothing; `OnShow` fires only on a false -> true transition of the
--      frame's OWN visible flag, and `OnHide` on true -> false. A hidden
--      ancestor makes a descendant invisible without touching its own flag,
--      exactly like the client (so a child re-shown under a hidden parent does
--      not fire OnShow).
--   3. A new frame's level is its parent's level + 1; a frame is never drawn
--      below its parent's strata. Mouse hit-testing picks the topmost VISIBLE,
--      MOUSE-ENABLED frame under the point, ordered by strata then level then
--      creation order — the same ordering the client uses to decide which frame
--      gets the click.
--   4. `Button` is mouse-enabled from birth (the client's default); a plain
--      `Frame` is not. `EnableMouse(false)` really disables it.
--
-- It is not a Blizzard emulator: it models the API surface this pack calls.
-- Anything it does not model is absent rather than silently benign, so a spec
-- that depends on it fails loudly.

local C = {}

C.charWidth = 0.55   -- one glyph at font size N is charWidth * N wide
C.lineHeight = 1.35  -- one line at font size N is lineHeight * N tall
C.defaultFontSize = 12

-- Every frame ever created, in creation order (the client's tie-break).
C.allFrames = {}
C.createCount = 0

-- UIParent taint trap: specs that assert "we never touch UIParent" turn this on.
C.trackUIParent = false
C.uiParentCalls = {}

C.STRATA = {
  BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4,
  DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}

local function strataRank(name)
  return C.STRATA[name] or C.STRATA.MEDIUM
end
C.StrataRank = strataRank

-- ── Chat ────────────────────────────────────────────────────────────────────
C.chat = {}
local function say(msg) C.chat[#C.chat + 1] = tostring(msg) end
C.Say = say
function C.ClearChat() for i = #C.chat, 1, -1 do C.chat[i] = nil end end
function C.ChatHas(needle)
  for _, m in ipairs(C.chat) do
    if m:find(needle, 1, true) then return true end
  end
  return false
end

-- ── Region geometry ─────────────────────────────────────────────────────────
-- Points name a place on a frame: which edge/centre it fixes on X and on Y.
local POINT = {
  TOPLEFT     = { x = "left",   y = "top" },
  TOP         = { x = "center", y = "top" },
  TOPRIGHT    = { x = "right",  y = "top" },
  LEFT        = { x = "left",   y = "center" },
  CENTER      = { x = "center", y = "center" },
  RIGHT       = { x = "right",  y = "center" },
  BOTTOMLEFT  = { x = "left",   y = "bottom" },
  BOTTOM      = { x = "center", y = "bottom" },
  BOTTOMRIGHT = { x = "right",  y = "bottom" },
}

local function parentOf(f)
  if type(f.parent) == "table" then return f.parent end
  return nil
end

local function parentScale(f)
  local p = parentOf(f)
  if not p then return 1 end
  return C.Scale(p)
end

--- Effective scale: the frame's own scale times every ancestor's (the client
--- scales a child by its parent's scale).
function C.Scale(f)
  if type(f) ~= "table" then return 1 end
  local own = f.scale
  if type(own) ~= "number" then return parentScale(f) end
  local cache = f._scaleCache
  if type(cache) == "number" then return cache end
  local s = own * parentScale(f)
  f._scaleCache = s
  return s
end

local function invalidateScale(f)
  f._scaleCache = nil
  for _, c in ipairs(f.children or {}) do invalidateScale(c) end
end

--- The rect of a REGION in screen coordinates: left, bottom, right, top, where
--- UIParent's top-left is (0,0) and y grows downward (a frame at the screen top
--- has top = 0 and bottom = -height), matching the client's GetTop/GetBottom.
function C.Rect(f)
  if type(f) ~= "table" then return { left = 0, right = 0, top = 0, bottom = 0, width = 0, height = 0 } end
  if f._rectCache then return f._rectCache end
  local s = C.Scale(f)
  local w = (type(f.width) == "number") and f.width or 0
  local h = (type(f.height) == "number") and f.height or 0
  local left, right, top, bottom

  if type(f._allPoints) == "table" or f._allPoints == true then
    local rel = (type(f._allPoints) == "table") and f._allPoints or parentOf(f)
    if type(rel) == "table" then
      local r = C.Rect(rel)
      left, right, top, bottom = r.left, r.right, r.top, r.bottom
    end
  end

  if not left then
    local points = f.points or {}
    local xLeft, xRight, xCenter, yTop, yBottom, yCenter
    for _, p in ipairs(points) do
      local name, rel, relPoint, ox, oy = p[1], p[2], p[3], p[4], p[5]
      local spec = POINT[name]
      if spec then
        -- `SetPoint("LEFT", strip, "LEFT", x, 0)` — the two-argument form in the
        -- real API is SetPoint(point, x, y): relative to the parent.
        if type(rel) == "number" then rel, relPoint, ox, oy = parentOf(f), name, rel, relPoint
        elseif type(rel) == "string" then rel, relPoint, ox, oy = parentOf(f), rel, relPoint, ox
        end
        if type(rel) ~= "table" then rel = parentOf(f) end
        relPoint = relPoint or name
        ox, oy = tonumber(ox) or 0, tonumber(oy) or 0
        ox, oy = ox * s, oy * s
        local rrel
        if type(rel) == "table" then rrel = C.Rect(rel)
        else rrel = { left = 0, right = 0, top = 0, bottom = 0 } end
        local rspec = POINT[relPoint] or POINT.CENTER
        local ax, ay
        if rspec.x == "left" then ax = rrel.left
        elseif rspec.x == "right" then ax = rrel.right
        else ax = (rrel.left + rrel.right) / 2 end
        if rspec.y == "top" then ay = rrel.top
        elseif rspec.y == "bottom" then ay = rrel.bottom
        else ay = (rrel.top + rrel.bottom) / 2 end
        local px, py = ax + ox, ay + oy
        if spec.x == "left" then xLeft = px
        elseif spec.x == "right" then xRight = px
        else xCenter = px end
        if spec.y == "top" then yTop = py
        elseif spec.y == "bottom" then yBottom = py
        else yCenter = py end
      end
    end
    -- Solve the axis constraints: an explicit size is honoured where fewer than
    -- two anchors fix the axis (the client's rule).
    if xLeft and xRight then
      left, right = xLeft, xRight
    elseif xLeft and xCenter then
      left = xLeft; right = 2 * xCenter - xLeft
    elseif xRight and xCenter then
      right = xRight; left = 2 * xCenter - xRight
    elseif xLeft then
      left = xLeft; right = xLeft + w * s
    elseif xRight then
      right = xRight; left = xRight - w * s
    elseif xCenter then
      left = xCenter - (w * s) / 2; right = xCenter + (w * s) / 2
    else
      local p = parentOf(f)
      left = p and C.Rect(p).left + 0 or 0
      right = left + w * s
    end
    if yTop and yBottom then
      top, bottom = yTop, yBottom
    elseif yTop and yCenter then
      top = yTop; bottom = 2 * yCenter - yTop
    elseif yBottom and yCenter then
      bottom = yBottom; top = 2 * yCenter - yBottom
    elseif yTop then
      top = yTop; bottom = yTop - h * s
    elseif yBottom then
      bottom = yBottom; top = yBottom + h * s
    elseif yCenter then
      top = yCenter + (h * s) / 2; bottom = yCenter - (h * s) / 2
    else
      local p = parentOf(f)
      top = p and C.Rect(p).top or 0
      bottom = top - h * s
    end
  end

  local r = {
    left = left, right = right, top = top, bottom = bottom,
    width = right - left, height = top - bottom,
  }
  f._rectCache = r
  return r
end

local function invalidateRect(f)
  f._rectCache = nil
  for _, c in ipairs(f.children or {}) do invalidateRect(c) end
end

--- Do two rects share any interior area? Touching edges do not count (a control
--- flush against another one does not steal its clicks).
function C.Overlaps(a, b)
  local ra, rb = C.Rect(a), C.Rect(b)
  local w = math.min(ra.right, rb.right) - math.max(ra.left, rb.left)
  local h = math.min(ra.top, rb.top) - math.max(ra.bottom, rb.bottom)
  return w > 0.01 and h > 0.01, w, h
end

--- Is the point inside the rect?
function C.Contains(region, x, y)
  local r = C.Rect(region)
  return x >= r.left and x <= r.right and y <= r.top and y >= r.bottom
end

-- ── Visibility ──────────────────────────────────────────────────────────────
--- Own flag only: does this frame's own `shown` say it is shown?
function C.SelfShown(f)
  if type(f) ~= "table" then return false end
  return f.shown == true
end

--- Shown AND every ancestor shown: what the player can see and click.
function C.Visible(f)
  if type(f) ~= "table" or f.shown ~= true then return false end
  local p = parentOf(f)
  if not p then return true end
  return C.Visible(p)
end

local function fire(f, script)
  local fn = type(f.scripts) == "table" and f.scripts[script]
  if type(fn) ~= "function" then return false end
  local ok, err = pcall(fn, f, script)
  if not ok then C.lastScriptError = tostring(err) end
  return ok
end
C.FireScript = fire

-- ── Frame construction ──────────────────────────────────────────────────────
local function newFrame(kind, name, parent, template)
  C.createCount = C.createCount + 1
  local f = {
    kind = kind or "Frame",
    Name = name,
    template = template,
    children = {},
    scripts = {},
    points = {},
    shown = true,          -- frames are BORN shown
    width = 0,
    height = 0,
    parent = nil,
    mouse = (kind == "Button"),
    level = nil,           -- nil -> parent level + 1
    strata = nil,          -- nil -> inherit the parent's
    _order = C.createCount,
  }
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:GetScript(n) return self.scripts[n] end
  function f:HasScript(n) return self.scripts[n] ~= nil end
  function f:SetPoint(...) self.points[#self.points + 1] = { ... }; invalidateRect(self) end
  function f:ClearAllPoints() self.points = {}; self._allPoints = nil; invalidateRect(self) end
  function f:GetNumPoints() return #self.points end
  function f:GetPoint(i)
    local p = self.points[i or 1]
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
  end
  function f:SetAllPoints(rel) self._allPoints = rel or true; self.points = {}; invalidateRect(self) end
  function f:GetAllPoints() return self._allPoints end
  function f:SetSize(w, h) self.width, self.height = w, h; invalidateRect(self) end
  function f:SetWidth(w) self.width = w; invalidateRect(self) end
  function f:SetHeight(h) self.height = h; invalidateRect(self) end
  function f:GetWidth() return C.Rect(self).width end
  function f:GetHeight() return C.Rect(self).height end
  function f:SetScale(sc) self.scale = sc; invalidateScale(self); invalidateRect(self) end
  function f:GetScale() return C.Scale(self) end
  function f:Show()
    if self.shown == true then return end   -- already shown: no event fires
    self.shown = true
    fire(self, "OnShow")
  end
  function f:Hide()
    if self.shown ~= true then return end   -- already hidden: no event fires
    self.shown = false
    fire(self, "OnHide")
  end
  function f:IsShown() return self.shown == true end
  function f:IsVisible() return C.Visible(self) end
  function f:EnableMouse(flag)
    if flag == nil then flag = true end
    self.mouse = flag and true or false
  end
  function f:IsMouseEnabled() return self.mouse == true end
  function f:EnableMouseWheel() end
  function f:SetMouseClickEnabled() end
  function f:SetFrameStrata(s) self.strata = s end
  function f:GetFrameStrata()
    if self.strata then return self.strata end
    local p = parentOf(self)
    if p then return p:GetFrameStrata() end
    return "MEDIUM"
  end
  function f:SetFrameLevel(l) self.level = l end
  function f:GetFrameLevel()
    -- Frozen at birth, exactly like the client: a frame's level is set once
    -- (parent level + 1) and a later SetParent does NOT re-level it. Deriving
    -- the level from the CURRENT parent would silently repair every reparent,
    -- which is the class of bug this model must be able to see (a body moved
    -- into a window keeps the level it was born with, so it can end up level
    -- with -- or below -- the frame whose backdrop fills that window).
    if type(self.level) == "number" then return self.level end
    return self._bornLevel or 1
  end
  function f:Raise() end
  function f:Lower() end
  function f:SetToplevel() end
  function f:SetClampedToScreen() end
  function f:SetMovable() end
  function f:RegisterForDrag() end
  function f:StartMoving() end
  function f:StopMovingOrSizing() end
  function f:SetDontSavePosition() end
  function f:GetLeft() return type(self.left) == "number" and self.left or C.Rect(self).left end
  function f:GetRight() return type(self.right) == "number" and self.right or C.Rect(self).right end
  function f:GetTop() return type(self.top) == "number" and self.top or C.Rect(self).top end
  function f:GetBottom() return type(self.bottom) == "number" and self.bottom or C.Rect(self).bottom end
  function f:GetCenter()
    local r = C.Rect(self)
    return (r.left + r.right) / 2, (r.top + r.bottom) / 2
  end
  function f:SetBackdrop(bd) self.backdrop = bd; self.hasBackdrop = true end
  function f:SetBackdropColor(r, g, b, a) self.backdropColor = { r, g, b, a } end
  function f:GetBackdropColor() local c = self.backdropColor or {}; return c[1], c[2], c[3], c[4] end
  function f:SetBackdropBorderColor(r, g, b, a) self.backdropBorderColor = { r, g, b, a } end
  function f:GetBackdrop() return self.backdrop end
  function f:SetScrollChild(child) self.scrollChild = child end
  function f:GetVerticalScroll() return self.vscroll or 0 end
  function f:SetVerticalScroll(v) self.vscroll = v end
  function f:SetButtonState(state, lock) self.buttonState = state; self.buttonStateLock = lock end
  function f:GetButtonState() return self.buttonState end
  function f:RegisterEvent() end
  function f:UnregisterEvent() end
  function f:RegisterUnitEvent() end
  function f:IsEventRegistered() return false end
  function f:SetText(t) self.text = tostring(t or "") end
  function f:GetText() return self.text end
  function f:SetNormalTexture(tex) self.normalTexture = tex or true end
  function f:GetNormalTexture() return self.normalTexture end
  function f:SetPushedTexture(tex) self.pushedTexture = tex or true end
  function f:GetPushedTexture() return self.pushedTexture end
  function f:SetHighlightTexture(tex)
    -- The client makes a highlight REGION and returns it from
    -- GetHighlightTexture; a boolean would crash any code that colours it
    -- (Touchstone's button helper does: `ht:SetVertexColor(...)`).
    if type(self._highlight) ~= "table" and type(self.CreateTexture) == "function" then
      self._highlight = self:CreateTexture(nil, "HIGHLIGHT")
    end
    if type(self._highlight) == "table" and type(self._highlight.SetTexture) == "function" then
      self._highlight:SetTexture(tex)
    end
    self.highlightTexture = self._highlight or true
  end
  function f:GetHighlightTexture() return self.highlightTexture end
  function f:SetDisabledTexture(tex) self.disabledTexture = tex or true end
  function f:GetChildren()
    local out = {}
    for i, c in ipairs(self.children) do out[i] = c end
    return out
  end
  function f:GetNumChildren() return #self.children end
  function f:GetParent() return self.parent end
  function f:SetParent(p)
    if type(self.parent) == "table" then
      local kids = self.parent.children
      for i = #kids, 1, -1 do
        if kids[i] == self then table.remove(kids, i) end
      end
    end
    self.parent = p
    if type(p) == "table" and type(p.children) == "table" then
      p.children[#p.children + 1] = self
    end
    invalidateScale(self)
    invalidateRect(self)
  end
  function f:CreateFontString(_, _, fontTemplate)
    local fs = newFrame("FontString", nil, f)
    fs.text = ""
    fs.mouse = false
    if type(fontTemplate) == "string" then
      fs.fontPath, fs.size, fs.fontFlags = fontTemplate, C.defaultFontSize, ""
    end
    function fs:SetText(t) self.text = tostring(t or "") end
    function fs:GetText() return self.text end
    function fs:SetTextColor(...) self.color = { ... } end
    function fs:GetTextColor() local c = self.color or {}; return c[1], c[2], c[3], c[4] end
    function fs:SetJustifyH(j) self.justify = j end
    function fs:SetJustifyV(j) self.justifyV = j end
    function fs:SetWordWrap(v) self.wordWrap = v end
    function fs:SetFont(path, size, flags)
      self.fontPath, self.size, self.fontFlags = path, size, flags
    end
    function fs:GetFont() return self.fontPath, self.size, self.fontFlags end
    function fs:SetFontObject(obj)
      if type(obj) == "table" then
        self.fontPath, self.size = obj.path or "FontObject", obj.size or C.defaultFontSize
      end
    end
    function fs:GetStringWidth()
      if not self.fontPath then return 0 end
      return #self.text * (self.size or C.defaultFontSize) * C.charWidth
    end
    function fs:GetHeight()
      if not self.fontPath then return 0 end
      return (self.size or C.defaultFontSize) * C.lineHeight
    end
    f.children[#f.children + 1] = fs
    return fs
  end
  function f:CreateTexture(_, _, layer)
    local t = newFrame("Texture", nil, f)
    t.layer = layer
    t.mouse = false
    function t:SetTexture(v) self.texture = v end
    function t:GetTexture() return self.texture end
    function t:SetColorTexture(...) self.colorTexture = { ... } end
    function t:SetVertexColor(...) self.vertexColor = { ... } end
    function t:SetTexCoord() end
    function t:SetDrawLayer(l) self.layer = l end
    function t:SetBlendMode() end
    function t:SetAlpha(a) self.alpha = a end
    function t:GetAlpha() return self.alpha or 1 end
    return t
  end
  function f:SetAlpha(a) self.alpha = a end
  function f:GetAlpha() return self.alpha or 1 end

  -- Template surface: what the client's template would have given the frame.
  local tmpl = tostring(template or ""):lower()
  if tmpl:find("backdroptemplate", 1, true) then f.hasBackdrop = true end
  if tmpl:find("uipanelclosbutton", 1, true) or tmpl:find("uipanelclosebutton", 1, true) then
    f.width, f.height = 32, 32
    f.normalTexture = true
    f.points[#f.points + 1] = { "TOPRIGHT", -5, -5 }
  end
  if tmpl:find("uipanelbuttontemplate", 1, true) then
    f.width, f.height = 100, 22
    f.normalTexture = true
  end
  if tmpl:find("uicheckbuttontemplate", 1, true) then
    f.width, f.height = 24, 24
    f.normalTexture = true
    function f:SetChecked(v) self.checked = v and true or false end
    function f:GetChecked() return self.checked == true end
  end
  if tmpl:find("scrollframe", 1, true) then
    -- The scroll template ships a scrollbar: two children, so the caller's
    -- "leave room for the bar" branch is exercised.
    local bar = newFrame("Slider", nil, f)
    bar.width, bar.height = 16, 100
    f.children[#f.children + 1] = bar
    f.scrollBar = bar
  end

  if type(parent) == "table" then
    f.parent = parent
    if type(parent.children) == "table" then parent.children[#parent.children + 1] = f end
  end
  -- The client's birth level: parent + 1, and it sticks for the frame's life.
  f._bornLevel = (type(parent) == "table" and parent:GetFrameLevel() or 0) + 1
  -- The client publishes a NAMED frame as a global. Without this the model
  -- cannot see a module that reaches its own frame through `_G["StatForgeMainFrame"]`
  -- (MightiePack's attach path does exactly that).
  if type(name) == "string" and name ~= "" then rawset(_G, name, f) end
  C.allFrames[#C.allFrames + 1] = f
  return f
end

C.NewFrame = newFrame

-- ── Mouse hit-testing ───────────────────────────────────────────────────────
local function effStrata(f)
  local p = parentOf(f)
  local own = (type(f.strata) == "string") and strataRank(f.strata) or 0
  if not p then
    if own > 0 then return own end
    return strataRank("MEDIUM")
  end
  return math.max(own, effStrata(p))
end

--- Draw/mouse order key: strata, then level, then creation order. A frame drawn
--- later is on top and gets the click.
function C.DrawKey(f)
  return effStrata(f), f:GetFrameLevel(), f._order or 0
end

local function better(a, b)
  local as, al, ao = C.DrawKey(a)
  local bs, bl, bo = C.DrawKey(b)
  if as ~= bs then return as > bs end
  if al ~= bl then return al > bl end
  return ao > bo
end
C.DrawsAbove = better

--- Every visible, mouse-enabled frame whose rect contains the point, topmost
--- first. This is the list the client walks to decide who owns a click.
function C.MouseStack(x, y)
  local out = {}
  for _, f in ipairs(C.allFrames) do
    if f.mouse == true and C.Visible(f) and C.Contains(f, x, y) then
      out[#out + 1] = f
    end
  end
  table.sort(out, function(a, b) return better(a, b) end)
  return out
end

--- `GetMouseFocus()` at a point, or nil when the world would get the click.
function C.MouseOwnerAt(x, y)
  return C.MouseStack(x, y)[1]
end

local function label(f)
  return (f.Name or "?") .. "/" .. tostring(f.kind)
end

--- The chain Jeremy's `/run` prints: the mouse owner and its ancestors, each
--- with its frame level. This is the evidence that names a click-eater.
function C.MouseChain(x, y)
  local owner = C.MouseOwnerAt(x, y)
  local parts = {}
  local p = owner
  for _ = 1, 8 do
    if type(p) ~= "table" then break end
    parts[#parts + 1] = label(p) .. "/L" .. tostring(p:GetFrameLevel())
    p = p:GetParent()
  end
  return owner, table.concat(parts, " <- ")
end

--- The centre of a region's rect — where a player's click lands.
function C.Centre(f)
  local r = C.Rect(f)
  return (r.left + r.right) / 2, (r.top + r.bottom) / 2
end

-- ── Installing the client into _G ───────────────────────────────────────────
function C.Install(opts)
  opts = opts or {}
  local screenW = opts.width or 1920
  local screenH = opts.height or 1080
  C.allFrames = {}
  C.createCount = 0
  C.chat = {}

  CreateFrame = function(kind, name, parent, template)
    return newFrame(kind, name, parent, template)
  end

  UIParent = newFrame("Frame", "UIParent")
  UIParent.width, UIParent.height = screenW, screenH
  UIParent.left, UIParent.top = 0, 0
  UIParent.shown = true
  if C.trackUIParent then
    local function trap(what)
      return function() C.uiParentCalls[#C.uiParentCalls + 1] = what end
    end
    UIParent.Show = trap("Show")
    UIParent.Hide = trap("Hide")
    UIParent.SetPoint = trap("SetPoint")
    UIParent.SetSize = trap("SetSize")
  end

  WorldFrame = newFrame("Frame", "WorldFrame")
  UISpecialFrames = { "GameMenuFrame", "WorldMapFrame" }
  SlashCmdList = {}
  StaticPopupDialogs = {}
  GameTooltip = newFrame("Frame", "GameTooltip")
  GameTooltip.SetOwner = function() end
  GameTooltip.SetText = function() end
  GameTooltip.AddLine = function() end
  GameTooltip.ClearLines = function() end
  GameTooltip.GetName = function() return "GameTooltip" end

  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) say(m) end, GetName = function() return "ChatFrame1" end }
  C.ClearChat()

  CopyTable = function(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = CopyTable(v) end
    return r
  end

  time = function() return 1700000000 end
  GetTime = function() return 0 end
  GetLocale = function() return "enUS" end
  GetUnitName = function() return "Testchar" end
  GetRealmName = function() return "Testrealm" end
  GetBuildInfo = function() return "1", "15", "0", "16001", "x" end
  IsAddOnLoaded = function() return false end
  UnitExists = function() return false end
  UnitAffectingCombat = function() return false end
  InCombatLockdown = function() return false end
  GetSpellInfo = function(id)
    if id == 2259 then return "Alchemy" end
    if id == 2366 then return "Herb Gathering" end
    if id == 8613 then return "Skinning" end
    return nil
  end
  C_Map = { GetBestMapForUnit = function() return 1429 end }
  C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end }
  ReloadUI = function() end
  OKAY, CANCEL = "OKAY", "CANCEL"
  IsShiftKeyDown = function() return false end
  issecurevariable = function() return true end
  hooksecurefunc = function() end

  return C
end

return C

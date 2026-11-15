-- MightiePack — the pack's ONE design vocabulary (card t_2d2c37b0).
--
-- Before this file, the window had three palettes in play at once: the
-- window's own gold/brown chrome (Window.lua's COLOR table), the vendored
-- Touchstone body's cyan-on-near-black brand (StatForge.Colors), and the
-- options panel's grey. Three palettes inside one frame is what "a panel of
-- panels" looks like, and no amount of per-widget tidying fixes it — the
-- values themselves disagree.
--
-- This file is the single place the pack states a design value:
--
--   colour     T.Brand() (the body's own table) + T.pack (our four-component
--              tokens, DERIVED from the brand at load, never re-typed)
--   fonts      T.font   — the client's font objects, by name
--   spacing    T.space  — one 8px grid, named
--   sizes      T.size   — window, bands, rows, insets
--   textures   T.tex    — the two or three the window may draw with
--   insets     T.inset  — backdrop insets and hairline width
--   list       T.list   — the item list's metrics (the vendored UpgradesTab
--              reads these, so the list's spacing is the window's spacing)
--
-- Consumption rule: `T.R(name, alpha)` for colour, `T.font` for a font object,
-- `T.space`/`T.size` for every offset. A colour triple written inline in a
-- window file is a second palette; tests/theme_tokens_spec.lua fails on one.
--
-- WHAT THIS IS NOT: it is not a copy of another addon's skin. The values below
-- are Touchstone's own brand (the pack's product), which the vendored body
-- already shipped; the window adopts them so the frame and its content are one
-- voice. No icon, string or palette is borrowed from any other addon.

local _, pkg = ...

local T = {}
pkg.Theme = T

-- ── Colour ────────────────────────────────────────────────────────────────
-- The one colour table in play is the vendored body's, looked up live: if the
-- body loads AFTER the window (a spec's order, or a client where the module
-- arrives late), the window still paints with the body's real values rather
-- than with a snapshot that has already drifted.
T.fallback = {
  accent = { 0.400, 0.988, 0.945 },
  accentDim = { 0.271, 0.635, 0.620 },
  bg = { 0.043, 0.047, 0.063 },
  surface = { 0.075, 0.082, 0.110 },
  surfaceHover = { 0.102, 0.114, 0.153 },
  border = { 0.137, 0.149, 0.200 },
  text = { 0.886, 0.894, 0.918 },
  textMuted = { 0.482, 0.506, 0.588 },
  textDim = { 0.290, 0.314, 0.400 },
  success = { 0.133, 0.773, 0.369 },
  warning = { 0.961, 0.620, 0.043 },
  danger = { 0.937, 0.267, 0.267 },
  white = { 1, 1, 1 },
  black = { 0, 0, 0 },
}

--- The brand table the whole pack paints from: the body's, when it is loaded.
--- tests/theme_tokens_spec.lua asserts this returns StatForge.Colors itself, so
--- "the window matches the body" is one table rather than two matching copies.
function T.Brand()
  local sf = rawget(_G, "StatForge")
  if type(sf) == "table" and type(sf.Colors) == "table" then return sf.Colors end
  return nil
end

function T.Dim(name)
  local brand = T.Brand()
  local c = type(brand) == "table" and brand[name] or nil
  return c or T.fallback[name] or T.fallback.white
end

-- Pack-only tokens, written as DERIVATIONS (a brand colour + an alpha), not as
-- copies: `windowBg` is "the body's bg at our alpha", resolved on every read.
-- That is what makes this file's numbers follow the brand instead of freezing
-- a snapshot of it — and it means the theme can load before the body does
-- (it does: the TOC puts this file before the vendored block, so the item list
-- can read T.list at load).
T.pack = {
  -- The window's own near-black, a shade deeper than the body's so the body
  -- reads as content ON the frame rather than as a second frame.
  windowBg = { base = "bg", alpha = 0.97 },
  -- The title band: the body's surface, opaque, so the band is a plane.
  titleBand = { base = "surface", alpha = 0.98 },
  -- One hairline, used for the band's underline and every section rule.
  hairline = { base = "border", alpha = 0.85 },
  -- Tab plates: nothing at rest, a surface tint on hover, the recessed bg on
  -- the current tab. The accent underline is the only saturated element.
  tabOff = { base = "black", alpha = 0.0 },
  tabHover = { base = "surfaceHover", alpha = 0.70 },
  tabActive = { base = "bg", alpha = 0.90 },
  tabUnder = { base = "accent", alpha = 1 },
  -- The status dot, one colour per real state (see Window.Status).
  dotOff = { base = "textDim", alpha = 1 },
  dotMissing = { base = "danger", alpha = 1 },
  dotWaiting = { base = "warning", alpha = 1 },
  dotEmpty = { base = "textMuted", alpha = 1 },
  dotScored = { base = "accentDim", alpha = 1 },
  dotVerdict = { base = "success", alpha = 1 },
  -- Pack Settings: a card surface for the sections, and its rule.
  panelBg = { base = "bg", alpha = 0.55 },
  sectionRule = { base = "border", alpha = 0.55 },
}

--- r, g, b, a for a token name. A pack token is resolved against the brand on
--- every read; a brand name resolves to the body's own value. An unknown name
--- is white, never nil: a nil in SetTextColor raises in the client, and a
--- design pass must not turn a typo into a broken window.
function T.R(name, alpha)
  local spec = T.pack[name]
  if type(spec) == "table" and type(spec.base) == "string" then
    local c = T.Dim(spec.base)
    local a = alpha
    if a == nil then a = spec.alpha or 1 end
    return c[1], c[2], c[3], a
  end
  local c = T.Dim(name)
  if type(c) ~= "table" then return 1, 1, 1, (alpha ~= nil) and alpha or 1 end
  local a = alpha
  if a == nil then a = c[4] or 1 end
  return c[1], c[2], c[3], a
end

-- The vendored body reads this global (through UpgradesTab's patch) to take the
-- item list's metrics from here instead of carrying a second set of numbers.
-- A plain addon-scoped global, published at load, so it does not depend on the
-- body having created StatForge yet — this file loads BEFORE the vendored block.
MightiePackTheme = T
pkg.ThemeGlobalName = "MightiePackTheme"

-- ── Fonts: the client's font objects, by name ─────────────────────────────
T.font = {
  display = "GameFontNormalLarge",   -- the pack's name
  heading = "GameFontNormal",        -- a section heading, a tab label
  body = "GameFontNormal",           -- a row's name
  small = "GameFontNormalSmall",     -- the status line, a row's reason
  hint = "GameFontHighlightSmall",   -- a sentence under a heading
  quiet = "GameFontDisableSmall",    -- "off", "not installed"
}

-- ── Spacing: one grid, named ──────────────────────────────────────────────
-- Every offset in the window is one of these. A number that is not (0 or) a
-- multiple of `grid` is how layouts drift: the chrome spec checks alignment.
T.space = {
  grid = 8,
  hair = 1,
  xs = 4,
  sm = 8,
  md = 16,
  lg = 24,
  xl = 32,
}

-- ── Sizes ─────────────────────────────────────────────────────────────────
T.size = {
  windowW = 960,
  windowH = 640,
  titleBand = 48,     -- name, status and the close button, one plane
  tabStrip = 40,      -- the text tabs and their underline
  tabH = 32,
  tabPadX = 16,       -- a tab's own padding, left and right of its label
  tabGutter = 24,     -- between two tabs
  underline = 2,      -- the current tab's accent rule
  statusDot = 6,
  contentPad = 16,    -- the body's distance from the frame's edges
  rowPitch = 32,      -- one settings row (a 24px control, 8px of air)
  checkSize = 20,
  subIndent = 24,     -- a sub-option under its module
  sectionGap = 24,
  windowEdge = 1,     -- the frame's hairline border
}

-- ── Textures: the only paths the window may name ──────────────────────────
T.tex = {
  solid = "Interface\\Buttons\\WHITE8X8",
  edge = "Interface\\Buttons\\WHITE8X8",
  check = "Interface\\Buttons\\UI-CheckBox-Check",
  close = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
}

-- ── Insets ────────────────────────────────────────────────────────────────
T.inset = {
  edge = { left = 1, right = 1, top = 1, bottom = 1 },
  panel = { left = 8, right = 8, top = 8, bottom = 8 },
}

-- ── The item list's metrics ───────────────────────────────────────────────
-- Read by the vendored UpgradesTab (through its patch), so the list's spacing
-- IS the window's spacing instead of a second set of numbers inside a file we
-- do not own. rowMin is a FLOOR: the row model measures the wrapped reason and
-- grows (card t_4e5ad8a4); rowMin is what a one-line row keeps.
T.list = {
  rowMin = 34,
  rowPad = 4,
  icon = 22,
  mark = 14,
  inset = 6,
  nameGap = 1,     -- between a row's name and its reason
}

-- ── The kit: the three primitives every surface is built from ─────────────
-- These live here, beside the tokens, for one reason: a helper that names a
-- token is part of the vocabulary. When they lived in the window's own file,
-- Options.lua could not reach them before the window loaded and grew its own
-- copies — which is how "one panel" became three. Nothing here states a value;
-- every number and colour comes from the tables above.
local function call(obj, name, ...)
  local f = type(obj) == "table" and obj[name]
  if type(f) ~= "function" then return false end
  local ok, r = pcall(f, obj, ...)
  if not ok then return false end
  return true, r
end
T.call = call

--- CreateFrame with the template guarded: a client (or a spec's fake client)
--- without BackdropTemplate must still get a usable frame.
function T.NewFrame(kind, name, parent, template)
  if type(CreateFrame) ~= "function" then return nil end
  if template ~= nil then
    local ok, f = pcall(CreateFrame, kind, name, parent, template)
    if ok and type(f) == "table" then return f end
  end
  local ok, f = pcall(CreateFrame, kind, name, parent)
  if ok and type(f) == "table" then return f end
  return nil
end

--- A FontString. `fontToken` is a T.font key (or a raw client font-object name,
--- for the vendored body's own callers).
function T.Label(parent, fontToken, text)
  if type(parent) ~= "table" or type(parent.CreateFontString) ~= "function" then
    return nil
  end
  local font = T.font[fontToken] or fontToken
  local ok, fs = pcall(parent.CreateFontString, parent, nil, "OVERLAY", font)
  if not ok or type(fs) ~= "table" then return nil end
  call(fs, "SetText", text or "")
  return fs
end

--- A label coloured from the theme in one call.
function T.Text(parent, fontToken, colorToken, text, alpha)
  local fs = T.Label(parent, fontToken, text)
  if type(fs) ~= "table" then return nil end
  local r, g, b, a = T.R(colorToken, alpha)
  call(fs, "SetTextColor", r, g, b, a)
  return fs
end

--- A panel: solid fill, optional hairline border, both from tokens.
--- opts: { bg = <colour token>, edge = <colour token> | false }
function T.Panel(parent, opts)
  opts = opts or {}
  local f = T.NewFrame(opts.kind or "Frame", opts.name, parent or nil, "BackdropTemplate")
    or T.NewFrame(opts.kind or "Frame", opts.name, parent or nil)
  if not f then return nil end
  if type(f.SetBackdrop) == "function" then
    local bd = { bgFile = T.tex.solid, tile = false, insets = T.inset.panel }
    local edged = opts.edge ~= false
    if edged then
      bd.edgeFile = T.tex.edge
      bd.edgeSize = T.size.windowEdge
      bd.insets = T.inset.edge
    end
    pcall(f.SetBackdrop, f, bd)
    local r, g, b, a = T.R(opts.bg or "panelBg")
    call(f, "SetBackdropColor", r, g, b, a)
    if edged then
      local er, eg, eb, ea = T.R(type(opts.edge) == "string" and opts.edge or "hairline")
      call(f, "SetBackdropBorderColor", er, eg, eb, ea)
    end
  end
  return f
end

--- A solid rule in a token colour, `height` tall (one hairline by default).
--- The caller anchors it; the kit owns the colour and the thickness.
function T.Rule(parent, colorToken, height)
  if type(parent) ~= "table" or type(parent.CreateTexture) ~= "function" then
    return nil
  end
  local ok, tex = pcall(parent.CreateTexture, parent, nil, "ARTWORK")
  if not ok or type(tex) ~= "table" then return nil end
  local r, g, b, a = T.R(colorToken or "hairline")
  call(tex, "SetColorTexture", r, g, b, a)
  call(tex, "SetHeight", height or T.space.hair)
  return tex
end

--- A token-coloured solid rectangle of a given size (a dot, an underline).
function T.Swatch(parent, colorToken, w, h)
  local tex = T.Rule(parent, colorToken, h)
  if type(tex) == "table" then call(tex, "SetWidth", w) end
  return tex
end

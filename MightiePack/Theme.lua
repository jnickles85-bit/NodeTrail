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
  tabUnder = { base = "text", alpha = 1 },   -- the render draws it WHITE, not the body's teal
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

  -- ── The ledger's surfaces (card t_07f778ca, PART B) ─────────────────────
  -- The drawing the owner picked from the pictures is the pack's OWN sheet, not
  -- the body's brand, so these resolve from T.ledgerPalette (absolute values)
  -- rather than from the brand. They are named here, once, so every primitive
  -- (T.Fill, T.Rule, T.Swatch, T.Text) reaches them through the one accessor
  -- T.R — no second colour lookup and no literal at a call site.
  ledgerBg        = { ledger = "bg" },
  ledgerBand      = { ledger = "band" },
  ledgerSurface   = { ledger = "surface" },
  ledgerRaised    = { ledger = "raised" },
  ledgerLine      = { ledger = "line" },
  ledgerLine2     = { ledger = "line2" },
  ledgerText      = { ledger = "text" },
  ledgerMuted     = { ledger = "muted" },
  ledgerDim       = { ledger = "dim" },
  ledgerUpgrade   = { ledger = "upgrade" },
  ledgerTradeoff  = { ledger = "tradeoff" },
  ledgerNoUpgrade = { ledger = "noupgrade" },
}

--- r, g, b, a for a token name. A pack token is resolved against the brand on
--- every read; a brand name resolves to the body's own value. An unknown name
--- is white, never nil: a nil in SetTextColor raises in the client, and a
--- design pass must not turn a typo into a broken window.
function T.R(name, alpha)
  local spec = T.pack[name]
  if type(spec) == "table" and type(spec.ledger) == "string" then
    -- A ledger token: absolute, from the pack's own palette (PART B).
    return T.Ledger(spec.ledger, alpha)
  end
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

-- ── The ledger's palette (card t_07f778ca, PART B) ────────────────────────
-- The drawing the owner picked from the pictures (V1 · Ledger, with V4's
-- summary line as the strip under the tab bar) is a FLAT, RULED sheet: one dark
-- language, no border art, no icons, no corner radius, no shadow.
--
-- These colours are stated as ABSOLUTE values because they are the pack's own
-- drawing, not the body's brand. T.Brand() still returns StatForge.Colors for
-- the body's own widgets (tests/theme_tokens_spec.lua holds that line); the
-- ledger tokens are ours and are read through `T.Ledger(name)`, a separate
-- accessor, so the two palettes cannot silently shadow each other.
--
-- The client cannot express three things in the mock, and nothing here pretends
-- otherwise: FontStrings have no letter-spacing (uppercase at 9.5px is the
-- substitute), no text shadow, and no corner radius. See T.SetFont.
T.ledgerPalette = {
  bg        = { 0.078, 0.086, 0.102 },        -- #14161a  the sheet
  band      = { 0.098, 0.110, 0.133 },        -- #191c22  a section band
  surface   = { 0.106, 0.122, 0.149 },        -- #1b1f26  a raised row
  raised    = { 0.125, 0.141, 0.173 },        -- #20242c  an open / hovered surface
  line      = { 1.000, 1.000, 1.000, 0.075 }, -- white @ 7.5%: the row rule
  line2     = { 1.000, 1.000, 1.000, 0.120 }, -- white @ 12%: a section rule
  text      = { 0.933, 0.945, 0.961 },        -- #eef1f5
  muted     = { 0.659, 0.698, 0.753 },        -- #a8b2c0
  dim       = { 0.486, 0.525, 0.584 },        -- #7c8695
  upgrade   = { 0.435, 0.812, 0.592 },        -- #6fcf97
  tradeoff  = { 0.902, 0.663, 0.298 },        -- #e6a94c
  noupgrade = { 0.545, 0.584, 0.647 },        -- #8b95a5
}

--- r, g, b, a for a ledger token. Unknown is white, never nil, for the same
--- reason T.R is: a nil colour raises in SetTextColor.
function T.Ledger(name, alpha)
  local c = T.ledgerPalette[name]
  if type(c) ~= "table" then return 1, 1, 1, (alpha ~= nil) and alpha or 1 end
  local a = alpha
  if a == nil then a = c[4] or 1 end
  return c[1], c[2], c[3], a
end

--- Set a FontString's size, keeping the client's own font file and flags.
--- `size` is a number of pixels (T.list.nameSize and friends).
---
--- WoW's font surface is SetFont(path, size, flags) and NOTHING else: there is
--- no weight axis ("semibold" is not selectable), no letter-spacing, and no
--- shadow. The drawing's weight therefore comes from SIZE and COLOUR — the
--- verdict word carries the colour, the name carries the size — which is the
--- information design the owner stated. The path is read from the client's own
--- font object, so the pack never ships or names a font file.
function T.SetFont(fs, size, flags)
  if type(fs) ~= "table" or type(size) ~= "number" then return false end
  local ok, path, _, baseFlags = T.call(fs, "GetFont")
  if not ok or type(path) ~= "string" or path == "" then return false end
  return T.call(fs, "SetFont", path, size, flags or baseFlags or "")
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
  bodyPad = 20,       -- the ledger's body inset (card t_07f778ca, PART B)
  rowPitch = 32,      -- one settings row (a 24px control, 8px of air)
  checkSize = 20,
  subIndent = 24,     -- a sub-option under its module
  sectionGap = 24,
  windowEdge = 1,     -- the frame's hairline border
  -- The ledger's columns and rows, from the approved drawing (V1 · Ledger).
  verdictGutter = 88, -- the marker above the verdict word, both in its colour
  changeCol = 110,    -- the right-aligned change column
  rowPadTop = 11,
  rowPadBottom = 12,
  rowRule = 1,        -- one hairline between rows
  summaryStrip = 32,  -- the V4 summary line + meter, under the tab strip (on the grid)
  meter = 3,          -- the summary meter's thickness
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
  -- NOTHING between a flat fill and its frame (card t_07f778ca, the outline
  -- defect). `panel` (8px) is still published because it is the inset a
  -- border-art backdrop would need, but a flat WHITE8X8 fill with it paints an
  -- 8px transparent ring around the window.
  panel = { left = 8, right = 8, top = 8, bottom = 8 },
  zero = { left = 0, right = 0, top = 0, bottom = 0 },
}

-- ── The item list's metrics ───────────────────────────────────────────────
-- Read by the vendored UpgradesTab (through its patch), so the list's spacing
-- IS the window's spacing instead of a second set of numbers inside a file we
-- do not own. rowMin is a FLOOR: the row model measures the wrapped reason and
-- grows (card t_4e5ad8a4); rowMin is what a one-line row keeps.
--
-- The ledger keys (gutter, change, padTop, padBottom, rule, nameSize,
-- reasonSize, labelSize, nameGapX) are the V1 drawing's own metrics (card
-- t_07f778ca, PART B). They point at T.size / T.fontSize rather than restating
-- the numbers, so a column width is stated once.
T.list = {
  rowMin = 34,
  mark = 14,
  inset = 6,
  nameGap = 1,     -- between a row's name and its reason
  gutter = T.size.verdictGutter,
  change = T.size.changeCol,
  padTop = T.size.rowPadTop,
  padBottom = T.size.rowPadBottom,
  rule = T.size.rowRule,
  nameGapX = 12,   -- the verdict gutter's own air, before the name
  nameSize = 14.5,
  reasonSize = 12,
  labelSize = 9.5,
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

--- Paint an EXISTING frame as a flat fill, from tokens. This is the one place
--- the inset rule lives (card t_07f778ca):
---
---   * a backdrop with a bgFile and no edgeFile is a FLAT FILL. Its inset band
---     is empty, so `insets` is {0,0,0,0}. An 8px inset there paints the fill
---     8px inside the frame and leaves a transparent ring around it — the
---     owner's "box outline larger than the window", widest above the title bar;
---   * a backdrop with BOTH a bgFile and an edgeFile reserves that band for the
---     hairline, so `insets` is the hairline width: the fill starts exactly
---     where the border art ends.
---
--- opts: { edge = <colour token or false>, alpha = <0..1> }
function T.FillBackdrop(f, colourToken, opts)
  if type(f) ~= "table" or type(f.SetBackdrop) ~= "function" then return f end
  opts = opts or {}
  local edge = type(opts.edge) == "string" and opts.edge or nil
  local bd = { bgFile = T.tex.solid, tile = false, insets = T.inset.zero }
  if edge then
    bd.edgeFile = T.tex.edge
    bd.edgeSize = T.size.windowEdge
    bd.insets = T.inset.edge
  end
  pcall(f.SetBackdrop, f, bd)
  local r, g, b, a = T.R(colourToken or "windowBg", opts.alpha)
  call(f, "SetBackdropColor", r, g, b, a)
  if edge then
    local er, eg, eb, ea = T.R(edge)
    call(f, "SetBackdropBorderColor", er, eg, eb, ea)
  end
  return f
end

--- A flat fill: no border art, so NO INSETS. Insets would shrink the fill
--- inside its frame and leave a transparent ring between fill and border —
--- the 2026-11-14 outline defect.
---
--- Use it for every flat-filled surface (the window fill, the title band, a
--- section plate, a summary strip). Add `opts.edge` only when the surface also
--- draws a 1px border, and then the fill and the border coincide by
--- construction.
---
--- opts: { name, kind, edge = <colour token>, alpha }
function T.Fill(parent, colourToken, opts)
  opts = opts or {}
  local kind = opts.kind or "Frame"
  local f = T.NewFrame(kind, opts.name, parent or nil, "BackdropTemplate")
    or T.NewFrame(kind, opts.name, parent or nil)
  if not f then return nil end
  return T.FillBackdrop(f, colourToken, opts)
end

--- A panel: solid fill, optional hairline border, both from tokens.
--- opts: { bg = <colour token>, edge = <colour token> | false }
---
--- Kept as the name the tab files already use; the WORK is T.Fill's, so a
--- panel can never re-introduce the 8px inset ring (card t_07f778ca).
function T.Panel(parent, opts)
  opts = opts or {}
  local edge = opts.edge
  if edge ~= false then edge = (type(edge) == "string") and edge or "hairline" end
  return T.Fill(parent, opts.bg or "panelBg", {
    name = opts.name,
    kind = opts.kind,
    alpha = opts.alpha,
    edge = edge,
  })
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

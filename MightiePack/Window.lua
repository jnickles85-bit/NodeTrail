-- MightiePack — the ONE window (card t_a5de2f16; reshaped by card t_2d2c37b0).
--
-- The window is the pack's house, and the pack's product is Touchstone:
--
--   Touchstone     the vendored window's content, its inner strip intact
--   Pack Settings  the options panel (Options.lua)
--
-- Herbs and Skinning were this window's other two tabs until NodeTrail left the
-- pack (card t_75309c97). They are gone, not hidden: there is no placeholder, no
-- "coming soon" panel and no link. The window simply has two tabs.
--
-- ── The design pass (card t_2d2c37b0) ────────────────────────────────────
-- The chrome is built from MightiePack/Theme.lua and nothing else. Three
-- palettes used to meet inside this frame — the gold/brown window, the cyan
-- Touchstone body, the grey options panel — which is what "a panel of panels"
-- reads as. Now every colour, font, offset and texture in this file is a token
-- from that one file, and the palette itself is the body's own table, so the
-- frame and its content cannot drift apart. tests/theme_tokens_spec.lua holds
-- the line: a colour literal written inline here fails the suite.
--
-- The hierarchy is three bands and one body:
--
--   title band   the pack's name, its version, the status line, the close
--                button — one plane, one hairline under it
--   status line  what Touchstone knows right now (off / waiting / no data /
--                scored / verdicts present). Jeremy's promise is "see yes, and
--                trust it", so the frame states the real state at a glance and
--                never a state the data does not support.
--   tab strip    two text tabs; the current one carries an accent underline
--   content      one host per tab, inset from the frame on the grid
--
-- What this file owns:
--   * the frame, its title band, its drag, its close and its ESC entry;
--   * the two outer tab buttons and the two content hosts;
--   * the status line and the state it reads;
--   * where the window was last put — ONE SavedVariables key with a default,
--     never an existing position key (hard rule 1);
--   * open / close / toggle / select, which the slashes call.
--
-- What it does NOT own: any module's own state, or any of NodeTrail's surfaces
-- (those live in the NodeTrail addon).
--
-- COMBAT (hard rule 4, Interface 16001): no frame this file creates is
-- protected, and no protected frame is touched anywhere here. Opening,
-- closing, dragging and tab switching only Show/Hide/SetPoint our own frames
-- and reparent two unprotected addon frames (the options panel and the
-- Touchstone content frame) — the same operations a player's click already
-- performs on them today. There is no combat-time layout churn beyond that
-- single reparent, which happens once per session per surface and is a no-op
-- afterwards. The status line reads public addon state only; it changes no
-- protected value and calls no protected function.

local _, pkg = ...

local W = {}
pkg.Window = W
-- The window's widget kit IS the theme (MightiePack/Theme.lua): one file owns
-- the tokens and the three primitives that name them. `W.UI` stays as the name
-- the tab files already use.
W.UI = pkg.Theme

local T = pkg.Theme
if type(T) ~= "table" then
  -- The TOC lists Theme.lua before this file. A build without it has no
  -- palette at all, and guessing one here is how the second palette came back
  -- the first time, so this fails loudly rather than quietly.
  error("MightiePack/Window.lua needs MightiePack/Theme.lua loaded first", 0)
end

W.NAME = "MightiePackWindow"
W.WIDTH = T.size.windowW
W.HEIGHT = T.size.windowH
W.TITLE_HEIGHT = T.size.titleBand
W.TABS_HEIGHT = T.size.tabStrip
W.DEFAULT_TAB = "settings"
W.TABS = { "touchstone", "settings" }
W.TAB_LABELS = {
  touchstone = "Touchstone",
  settings = "Pack Settings",
}
-- The new key. Hard rule 1: add-only, defaulted, and it never reads or writes
-- StatForgeDB.ui.* or any other existing position/scale key.
W.POS_KEY = "windowPos"

-- The vendored body's own chrome (a 40px title bar, a close button, a bordered
-- content frame) is not recognised from here any more (card t_07f778ca, review
-- 2). The pack tells the body it is hosted — SF.SetHostedChrome(true) — and the
-- body's own creation path skips that chrome. Matching the title bar by its
-- measured height was the defect: the harness and the live client disagreed,
-- and the client kept drawing the title bar and its close button.

local function call(obj, name, ...)
  local f = type(obj) == "table" and obj[name]
  if type(f) ~= "function" then return false end
  local ok, r = pcall(f, obj, ...)
  if not ok then return false end
  return true, r
end

local function num(obj, name)
  local ok, v = call(obj, name)
  if ok and type(v) == "number" then return v end
  return nil
end

-- Frame, font and rectangle creation come from the theme's kit (Theme.lua): one
-- guarded implementation for the window, the options panel and the tab seam, so
-- a client that refuses a template fails the same way everywhere.
local newFrame = T.NewFrame
local function newFontString(parent, template)
  return T.Label(parent, template, "")
end
local swatch = T.Swatch

-- The label beside the name. The TOC's Version line is the git TAG as the
-- packager wrote it -- "v0.3.12-beta", its own leading v included -- so the
-- prefix is added only when the string does not already carry one.
local function versionText(ver)
  if type(ver) ~= "string" then return nil end
  local s = ver:gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then return nil end
  -- Neither shape of a source checkout is a version to put a v in front of:
  -- the legacy metadata path answers the raw token, the modern one "dev".
  if s == "dev" or s:find("@project-version@", 1, true) then return "dev" end
  s = s:gsub("^[vV]", "")
  if s == "" then return nil end
  return "v" .. s
end

local function settings()
  if type(pkg.GetSettings) == "function" then
    local ok, s = pcall(pkg.GetSettings)
    if ok and type(s) == "table" then return s end
  end
  return nil
end

-- ── Position: one new key, with a default ─────────────────────────────────
--- The saved top-left, or nil when the player has never moved the window.
--- A saved pair is only honoured when both numbers are real: a half-written
--- table falls back to the default instead of parking the window at 0,0.
function W.SavedPosition()
  local s = settings()
  local row = type(s) == "table" and s[W.POS_KEY] or nil
  if type(row) ~= "table" then return nil end
  local left, top = tonumber(row.left), tonumber(row.top)
  if left == nil or top == nil then return nil end
  return left, top
end

--- Write the window's current top-left. Called on drag stop only, so a tab
--- switch or a scale change never writes SavedVariables.
function W.SavePosition()
  local f = W.frame
  if type(f) ~= "table" then return false end
  local left, top = num(f, "GetLeft"), num(f, "GetTop")
  if left == nil or top == nil then return false end
  local s = settings()
  if type(s) ~= "table" then return false end
  s[W.POS_KEY] = { left = left, top = top }
  return true
end

-- ── Status: what Touchstone knows, in one line ────────────────────────────
-- Five states, every one of them read from real state — never invented:
--
--   missing   the body's module table is absent            (danger)
--   off       the player turned Touchstone off             (dim)
--   waiting   a scan was deferred because of combat         (warning)
--   empty     no verdicts in hand                          (muted)
--   scored    verdicts in hand, none of them a change      (accent dim)
--   verdict   at least one upgrade or trade-off            (success)
--
-- There is no separate "scanning" flag in the advisor: a scan either runs to
-- completion inside the call or is deferred by combat (ChestAdvisor._scanDeferred,
-- B17). "waiting" is that deferral — the only honest in-flight state there is,
-- and it says exactly what it is, so the band cannot claim a scan is running
-- when nothing is.
local TRADE_OFF_FALLBACK = "TRADE_OFF"

local function verdictRows()
  local CA = rawget(_G, "ChestAdvisor")
  if type(CA) ~= "table" or type(CA.getVerdicts) ~= "function" then return nil, CA end
  local ok, rows = pcall(CA.getVerdicts)
  if not ok or type(rows) ~= "table" then return nil, CA end
  return rows, CA
end

local function tradeOffWord()
  local V = rawget(_G, "Verdict")
  if type(V) == "table" and type(V.TRADE_OFF) == "string" then return V.TRADE_OFF end
  return TRADE_OFF_FALLBACK
end

local function plural(n, one, many)
  return tostring(n) .. " " .. (n == 1 and one or many)
end

--- The status table: { state = <key>, dot = <colour token>, text = <line> }.
function W.Status()
  local state = W.TouchstoneState()
  if state == "missing" then
    return { state = "missing", dot = "dotMissing", text = "Touchstone did not load" }
  end
  if state == "off" then
    return { state = "off", dot = "dotOff", text = "Touchstone off — see Pack Settings" }
  end

  local rows, CA = verdictRows()
  if type(CA) == "table" and CA._scanDeferred == true then
    return { state = "waiting", dot = "dotWaiting", text = "Scan waits for combat to end" }
  end
  if not rows then
    return { state = "empty", dot = "dotEmpty", text = "No verdicts yet — open your bags" }
  end

  local trade = tradeOffWord()
  local total, upgrades, trades = 0, 0, 0
  for _, row in pairs(rows) do
    if type(row) == "table" then
      total = total + 1
      if row.verdict == "UPGRADE" then
        upgrades = upgrades + 1
      elseif row.verdict == trade then
        trades = trades + 1
      end
    end
  end
  if total == 0 then
    return { state = "empty", dot = "dotEmpty", text = "No verdicts yet — open your bags" }
  end
  if upgrades == 0 and trades == 0 then
    return {
      state = "scored",
      dot = "dotScored",
      text = plural(total, "item scored", "items scored") .. " · no change",
    }
  end
  local parts = {}
  if upgrades > 0 then parts[#parts + 1] = plural(upgrades, "upgrade", "upgrades") end
  if trades > 0 then parts[#parts + 1] = plural(trades, "trade-off", "trade-offs") end
  parts[#parts + 1] = plural(total, "item scored", "items scored")
  return { state = "verdict", dot = "dotVerdict", text = table.concat(parts, " · ") }
end

--- Paint the status line. Cheap (a dot colour and a string) and called on every
--- open, every tab switch and every vendored refresh, so the line cannot go
--- stale while the window is up.
function W.PaintStatus()
  local s = W.Status()
  W.status = s
  local dot, fs = W.statusDot, W.statusText
  if type(dot) == "table" and type(dot.SetColorTexture) == "function" then
    local r, g, b, a = T.R(s.dot)
    pcall(dot.SetColorTexture, dot, r, g, b, a)
  end
  if type(fs) == "table" then
    local r, g, b, a = T.R(s.state == "verdict" and "text" or "textMuted")
    call(fs, "SetTextColor", r, g, b, a)
    call(fs, "SetText", s.text)
  end
  -- The summary strip is the same kind of readout as this line — it says what
  -- the advisor found, from the advisor's own list — so it repaints wherever the
  -- status does, and it cannot go stale either (card t_07f778ca, PART B3).
  W.PaintSummary()
  return s
end

-- ── The summary strip (card t_07f778ca, PART B3) ───────────────────────────
-- "2 of 5 are worth taking" · "1 trade-off · 2 refused" over a 3px meter.
--
-- The counts come from the verdict LIST, every time: no cached total, no number
-- typed in. An empty list is a real answer (0 of 0, an empty meter) and must not
-- divide by zero.
--
-- THE SHAPE MATTERS: ChestAdvisor.getVerdicts() returns a table KEYED BY LINK
-- (`verdicts[link] = { verdict = … }`), not an array — so this walks it with
-- pairs(). Walking it with ipairs() reads an empty list and prints "0 of 0" over
-- a full one, which is the exact class of lie this strip must never tell.
local function tradeOffToken()
  local V = rawget(_G, "Verdict")
  if type(V) == "table" and type(V.TRADE_OFF) == "string" then return V.TRADE_OFF end
  return "TRADE_OFF"
end

W.WORD_REFUSED = "refused"

--- Count the advisor's own verdict list: how many rows, how many are worth
--- taking (an UPGRADE — the verdict that means "equip it"), how many are
--- trade-offs, and how many were refused. The three parts add up to the total.
function W.Summary()
  local rows = {}
  local ca = rawget(_G, "ChestAdvisor")
  if type(ca) == "table" and type(ca.getVerdicts) == "function" then
    local ok, list = pcall(ca.getVerdicts)
    if ok and type(list) == "table" then rows = list end
  end
  local trade = tradeOffToken()
  local out = { total = 0, upgrade = 0, tradeoff = 0, refused = 0, worth = 0 }
  -- pairs(), not ipairs(): the list is keyed by item link (see above).
  for _, r in pairs(rows) do
    if type(r) == "table" then
      out.total = out.total + 1
      local v = r.verdict
      if v == "UPGRADE" then
        out.upgrade = out.upgrade + 1
      elseif v == trade or v == "TRADE_OFF" then
        out.tradeoff = out.tradeoff + 1
      else
        out.refused = out.refused + 1
      end
    end
  end
  out.worth = out.upgrade
  return out
end

--- The three strings the strip draws: the count (its own label, in the upgrade
--- colour), the rest of the line, and the right-hand pair. Pure, so a spec can
--- ask for the words without a frame.
function W.SummaryText(s)
  s = s or W.Summary()
  local total = tonumber(s.total) or 0
  local worth = tonumber(s.worth) or 0
  local trade = tonumber(s.tradeoff) or 0
  local refused = tonumber(s.refused) or 0
  local count = tostring(worth)
  local rest = " of " .. tostring(total) .. (total == 1 and " is worth taking" or " are worth taking")
  local right = tostring(trade) .. " trade-off" .. (trade == 1 and "" or "s")
    .. " · " .. tostring(refused) .. " " .. W.WORD_REFUSED
  return count, rest, right
end

--- The meter's segment widths for a given strip width. Proportional to the row
--- count; the last segment takes the rounding remainder so the three segments
--- always fill the meter exactly (and an empty list is all zeroes, not NaN).
function W.SummaryMeter(s, width)
  local total = math.max(0, tonumber(s and s.total) or 0)
  local w = math.max(0, tonumber(width) or 0)
  if total == 0 or w == 0 then
    return { upgrade = 0, tradeoff = 0, noupgrade = 0 }
  end
  local up = (math.max(0, tonumber(s.upgrade) or 0) / total) * w
  local tr = (math.max(0, tonumber(s.tradeoff) or 0) / total) * w
  local no = w - up - tr
  if no < 0 then no = 0 end
  return { upgrade = up, tradeoff = tr, noupgrade = no }
end

--- Repaint the strip from the live list.
function W.PaintSummary()
  local meter, seg = W.summaryMeter, W.summarySegments
  if type(meter) ~= "table" or type(seg) ~= "table" then return false end
  local s = W.Summary()
  W.summary = s
  local count, rest, right = W.SummaryText(s)
  if type(W.summaryCount) == "table" then call(W.summaryCount, "SetText", count) end
  if type(W.summaryLine) == "table" then call(W.summaryLine, "SetText", rest) end
  if type(W.summaryDetail) == "table" then call(W.summaryDetail, "SetText", right) end
  local width = 0
  local okW, w = call(meter, "GetWidth")
  if okW and type(w) == "number" then width = w end
  local widths = W.SummaryMeter(s, width)
  local x = 0
  for _, key in ipairs({ "upgrade", "tradeoff", "noupgrade" }) do
    local tex = seg[key]
    if type(tex) == "table" then
      local sw = widths[key] or 0
      call(tex, "SetWidth", sw)
      call(tex, "ClearAllPoints")
      call(tex, "SetPoint", "BOTTOMLEFT", meter, "BOTTOMLEFT", x, 0)
      if sw > 0 then call(tex, "Show") else call(tex, "Hide") end
      x = x + sw
    end
  end
  return s
end

-- ── Frame ─────────────────────────────────────────────────────────────────
--- Paint one tab: its label colour, its plate, its underline and its button
--- state. One helper, so the hover script and the state repaint cannot
--- disagree.
function W.PaintTab(id)
  local btn = W.tabButtons and W.tabButtons[id]
  if type(btn) ~= "table" then return false end
  local current = (id == W.current)
  local hovered = btn._hover == true
  if type(btn.label) == "table" then
    local token = current and "accent" or (hovered and "text" or "textMuted")
    local r, g, b, a = T.R(token)
    call(btn.label, "SetTextColor", r, g, b, a)
  end
  if type(btn.SetBackdropColor) == "function" then
    local token = current and "tabActive" or (hovered and "tabHover" or "tabOff")
    local r, g, b, a = T.R(token)
    call(btn, "SetBackdropColor", r, g, b, a)
    local er, eg, eb, ea = T.R("hairline", current and 0.85 or 0.35)
    call(btn, "SetBackdropBorderColor", er, eg, eb, ea)
  end
  if type(btn.underline) == "table" then
    if current then call(btn.underline, "Show") else call(btn.underline, "Hide") end
  end
  if type(btn.SetButtonState) == "function" then
    -- No lock. `SetButtonState(state, true)` was passed here once, which locks
    -- the button's state on EVERY tab — the current one to PUSHED and the other
    -- three to NORMAL. A locked button ignores mouse-driven state changes, and
    -- this was the one thing in the code that applied to all buttons at once,
    -- i.e. consistent with the whole row being dead rather than one tab.
    -- The plate and the underline are what distinguish current from the rest,
    -- so the lock bought nothing.
    pcall(btn.SetButtonState, btn, current and "PUSHED" or "NORMAL")
  end
  return true
end

function W._Ensure()
  if type(W.frame) == "table" then return W.frame end
  if type(CreateFrame) ~= "function" then
    W._error = "CreateFrame is not available on this client"
    return nil
  end
  local parent = (type(UIParent) == "table") and UIParent or nil
  local f = newFrame("Frame", W.NAME, parent, "BackdropTemplate")
  if not f then
    W._error = "CreateFrame refused the window frame"
    return nil
  end
  W.frame = f
  call(f, "SetSize", W.WIDTH, W.HEIGHT)
  call(f, "SetFrameStrata", "DIALOG")
  -- ── The window frame does NOT take clicks (card t_cdee6bb6) ─────────────
  -- It used to: `EnableMouse(true)` here, while the window sits in DIALOG and
  -- the hosted Touchstone body sits in MEDIUM. Mouse hit-testing follows the
  -- same order as painting — strata first, then level — so this frame was ABOVE
  -- the body for input as well and took every click over it. The body's own
  -- controls (its Upgrades / Log / Settings strip, its panel buttons) were
  -- present, wired and correct, and never reached; the OUTER tabs worked
  -- because they are children of this frame, in the same DIALOG strata.
  --
  -- Nothing is lost by turning it off: dragging lives on the title band
  -- (`band:EnableMouse(true)` + RegisterForDrag, below), the tab row and the
  -- close button are their own buttons, and the "do not click through to the
  -- world" duty moves DOWN to the fill, which is the only frame that should
  -- own empty window space. See W.bg, below.
  call(f, "EnableMouse", false)
  call(f, "SetClampedToScreen", true)
  call(f, "SetMovable", true)
  call(f, "SetToplevel", true)
  -- ── The fill has its own frame, UNDER everything (card t_5d0cc41a) ───────
  -- This window frame used to carry the opaque backdrop itself, in DIALOG. A
  -- body reparented into the window keeps its OWN strata (StatForgeMainFrame is
  -- MEDIUM, see AttachTouchstone), and strata beats frame level outright, so
  -- the fill drew OVER the entire Touchstone body. No covering-frame detector
  -- could see it: the culprit is an ancestor, and an ancestor is excluded from
  -- "what draws over me" by definition.
  --
  -- So the fill moves here and the ordering becomes STRUCTURE, not a per-tab
  -- fix:   fill (BACKGROUND) < content (MEDIUM) < chrome (DIALOG).
  -- Any future reparented body at MEDIUM is correct without its own strata
  -- hack, which is the point of fixing the class instead of the instance.
  --
  -- The three properties that make it safe:
  --   * SetAllPoints(window): exactly the window's area, nothing more;
  --   * EnableMouse(true): the fill is where the "do not click through to the
  --     world" duty now lives. It is the LOWEST layer, so content (MEDIUM) and
  --     chrome (DIALOG) still win the hit test over it;
  --   * a level at or below the window's, so on a client that also orders by
  --     level inside a strata the fill still loses.
  --
  -- The colour is the theme's windowBg (the body's brand bg, ours for alpha):
  -- one palette, and the fill is still opaque so the interior never goes
  -- see-through over live terrain (AC-N7).
  local bg = T.Fill(f, "windowBg", { name = W.NAME .. "Background" })
    or newFrame("Frame", W.NAME .. "Background", f)
  if type(bg) == "table" then
    W.bg = bg
    call(bg, "SetAllPoints", f)
    call(bg, "SetFrameStrata", "BACKGROUND")
    call(bg, "EnableMouse", true)
    local okLevel, winLevel = call(f, "GetFrameLevel")
    if okLevel and type(winLevel) == "number" then
      call(bg, "SetFrameLevel", math.max(1, winLevel - 1))
    end
  end

  -- The chrome frame keeps a border and no fill: a hairline edge, not the old
  -- 32px dialog frame. The fill is W.bg above; a bgFile here would sit in
  -- DIALOG, above every hosted body, which is exactly the defect t_5d0cc41a
  -- fixed.
  if type(f.SetBackdrop) == "function" then
    call(f, "SetBackdrop", {
      edgeFile = T.tex.edge,
      tile = false, edgeSize = T.size.windowEdge,
      insets = T.inset.edge,
    })
    local r, g, b, a = T.R("hairline")
    call(f, "SetBackdropBorderColor", r, g, b, a)
  end
  local left, top = W.SavedPosition()
  if left and top then
    call(f, "SetPoint", "TOPLEFT", parent or nil, "TOPLEFT", left, top)
  elseif type(parent) == "table" then
    call(f, "SetPoint", "CENTER", parent, "CENTER", 0, 0)
  else
    call(f, "SetPoint", "CENTER", nil, "CENTER", 0, 0)
  end
  call(f, "SetScript", "OnHide", function()
    if type(W.onHide) == "table" then
      for _, fn in ipairs(W.onHide) do pcall(fn) end
    end
  end)

  -- ── The title band ───────────────────────────────────────────────────────
  -- One plane across the top: the pack's name, its version, the status line,
  -- and the close button. It is also the drag handle — a band that looks like a
  -- header should behave like one.
  local band = T.Fill(f, "titleBand") or newFrame("Frame", nil, f, "BackdropTemplate")
    or newFrame("Frame", nil, f)
  W.titleBar = band
  call(band, "SetPoint", "TOPLEFT", f, "TOPLEFT", 0, 0)
  call(band, "SetPoint", "TOPRIGHT", f, "TOPRIGHT", 0, 0)
  call(band, "SetHeight", T.size.titleBand)
  call(band, "EnableMouse", true)
  if type(band.RegisterForDrag) == "function" then
    pcall(band.RegisterForDrag, band, "LeftButton")
    pcall(band.SetScript, band, "OnDragStart", function()
      if type(f.StartMoving) == "function" then pcall(f.StartMoving, f) end
    end)
    pcall(band.SetScript, band, "OnDragStop", function()
      -- Save the position ONLY here: a drag is the one event that moves it.
      if type(f.StopMovingOrSizing) == "function" then
        pcall(f.StopMovingOrSizing, f)
      end
      W.SavePosition()
    end)
  end
  -- The hairline that separates the band from the tab strip.
  local rule = type(band.CreateTexture) == "function" and band:CreateTexture(nil, "ARTWORK") or nil
  if type(rule) == "table" then
    local r, g, b, a = T.R("hairline")
    if type(rule.SetColorTexture) == "function" then
      pcall(rule.SetColorTexture, rule, r, g, b, a)
    end
    call(rule, "SetHeight", T.space.hair)
    call(rule, "SetPoint", "BOTTOMLEFT", band, "BOTTOMLEFT", 0, 0)
    call(rule, "SetPoint", "BOTTOMRIGHT", band, "BOTTOMRIGHT", 0, 0)
  end

  local title = newFontString(band, T.font.display)
  W.title = title
  if type(title) == "table" then
    call(title, "SetPoint", "TOPLEFT", band, "TOPLEFT", T.space.md, -T.space.sm)
    local r, g, b, a = T.R("text")
    call(title, "SetTextColor", r, g, b, a)
    call(title, "SetText", "MightiePack")
  end

  -- The version is secondary: dim, small, beside the name rather than in it, so
  -- the name reads as a name.
  local label = nil
  if type(pkg.PackVersion) == "function" then
    local okV, v = pcall(pkg.PackVersion)
    if okV then label = versionText(v) end
  end
  if type(title) == "table" and label then
    local version = newFontString(band, T.font.small)
    W.version = version
    if type(version) == "table" then
      call(version, "SetPoint", "LEFT", title, "RIGHT", T.space.sm, 0)
      local r, g, b, a = T.R("textDim")
      call(version, "SetTextColor", r, g, b, a)
      call(version, "SetText", label)
    end
  end

  -- The status line: a dot and a sentence. It is the window's promise that what
  -- the player sees is what Touchstone actually knows.
  local dot = swatch(band, "dotOff", T.size.statusDot, T.size.statusDot)
  if type(dot) == "table" then
    W.statusDot = dot
    call(dot, "SetPoint", "TOPLEFT", band, "TOPLEFT", T.space.md, -(T.space.lg + T.space.xs))
    local fs = newFontString(band, T.font.small)
    W.statusText = fs
    if type(fs) == "table" then
      call(fs, "SetPoint", "LEFT", dot, "RIGHT", T.space.sm, 0)
      -- Left of the close button, so a long line cannot run under it.
      call(fs, "SetPoint", "RIGHT", band, "RIGHT", -(T.space.xl + T.space.md), 0)
      call(fs, "SetJustifyH", "LEFT")
      local r, g, b, a = T.R("textMuted")
      call(fs, "SetTextColor", r, g, b, a)
    end
  end

  local close = newFrame("Button", nil, band, "UIPanelCloseButton") or newFrame("Button", nil, band)
  if type(close) == "table" then
    call(close, "ClearAllPoints")
    call(close, "SetPoint", "TOPRIGHT", band, "TOPRIGHT", -T.space.sm, -T.space.sm)
    -- The template brings its own art. Only a client that refused the template
    -- needs the fallback, and even that draws from the theme's texture list.
    if type(close.GetNormalTexture) ~= "function" and type(close.SetNormalTexture) == "function" then
      call(close, "SetNormalTexture", T.tex.close)
    end
    call(close, "SetScript", "OnClick", function() W.Close() end)
    W.close = close
  end

  -- ── The tab strip ────────────────────────────────────────────────────────
  -- Text tabs on the grid: no boxes, no plates at rest. The current tab is the
  -- one with the accent underline; hover lifts only the label. The plate
  -- backdrop still exists (transparent at rest) because it is what the click
  -- affordance is drawn on and what the hover tint uses.
  local strip = newFrame("Frame", nil, f)
  W.tabStrip = strip
  call(strip, "SetPoint", "TOPLEFT", band, "BOTTOMLEFT", T.space.md, 0)
  call(strip, "SetPoint", "TOPRIGHT", band, "BOTTOMRIGHT", -T.space.md, 0)
  call(strip, "SetHeight", T.size.tabStrip)
  W.tabButtons = {}
  local x = 0
  for _, id in ipairs(W.TABS) do
    local btn = newFrame("Button", nil, strip, "BackdropTemplate") or newFrame("Button", nil, strip)
    call(btn, "SetHeight", T.size.tabH)
    call(btn, "SetPoint", "TOPLEFT", strip, "TOPLEFT", x, 0)
    call(btn, "EnableMouse", true)
    -- A tab plate: a fill PLUS the hairline it is judged by, so T.Fill takes
    -- the edge — the fill then starts exactly where the border ends and the
    -- plate has no transparent ring of its own (card t_07f778ca).
    T.FillBackdrop(btn, "tabOff", { edge = "hairline" })
    -- Above every sibling the window creates, so nothing added later can draw
    -- over the row and take its clicks (card t_ea66cd84).
    local okLevel, stripLevel = call(strip, "GetFrameLevel")
    if okLevel and type(stripLevel) == "number" then
      call(btn, "SetFrameLevel", stripLevel + 5)
    end
    local fs = newFontString(btn, T.font.heading)
    if type(fs) == "table" then
      call(fs, "SetText", W.TAB_LABELS[id])
      call(fs, "SetPoint", "CENTER", btn, "CENTER", 0, 0)
    end
    btn.label = fs
    -- The tab's width is its own label plus the theme's padding: a text tab is
    -- as wide as its word, which is the point of not using plates at rest.
    local labelW = 0
    if type(fs) == "table" and type(fs.GetStringWidth) == "function" then
      local okW, w = pcall(fs.GetStringWidth, fs)
      if okW and type(w) == "number" then labelW = w end
    end
    if labelW <= 0 then labelW = T.space.xl * 3 end
    local width = math.floor(labelW + T.size.tabPadX * 2)
    call(btn, "SetWidth", width)
    -- The current tab's accent underline, inside the plate's bottom edge.
    local under = swatch(btn, "tabUnder", width, T.size.underline)
    if type(under) == "table" then
      btn.underline = under
      call(under, "SetPoint", "BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 1)
      call(under, "SetPoint", "BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 1)
      call(under, "Hide")
    end
    btn._hover = false
    call(btn, "SetScript", "OnEnter", function()
      btn._hover = true
      W.PaintTab(id)
    end)
    call(btn, "SetScript", "OnLeave", function()
      btn._hover = false
      W.PaintTab(id)
    end)
    call(btn, "SetScript", "OnClick", function() W.SelectTab(id) end)
    W.tabButtons[id] = btn
    x = x + width + T.size.tabGutter
  end

  -- ── The summary strip (card t_07f778ca, PART B3) ─────────────────────────
  -- V4's line, under V1's tab bar: what the advisor actually found, in one
  -- line — "2 of 5 are worth taking", the count in the upgrade colour, and
  -- "1 trade-off · 2 refused" on the right — over a 3px meter segmented in the
  -- three verdict colours by proportion.
  --
  -- It RECOMPUTES from the verdict list on every activation and every vendored
  -- refresh (W.PaintSummary); nothing here is cached or hardcoded, and an empty
  -- list renders as "0 of 0" with an empty meter rather than dividing by zero.
  local summary = T.Fill(f, "ledgerBand", { name = W.NAME .. "Summary" })
  W.summaryFrame = summary
  if type(summary) == "table" then
    call(summary, "SetPoint", "TOPLEFT", strip, "BOTTOMLEFT", 0, 0)
    call(summary, "SetPoint", "TOPRIGHT", strip, "BOTTOMRIGHT", 0, 0)
    call(summary, "SetHeight", T.size.summaryStrip)
    W.summaryCount = T.Text(summary, "heading", "ledgerUpgrade", "0")
    W.summaryLine = T.Text(summary, "heading", "ledgerMuted", "")
    W.summaryDetail = T.Text(summary, "heading", "ledgerDim", "")
    if type(W.summaryCount) == "table" then
      call(W.summaryCount, "SetPoint", "BOTTOMLEFT", summary, "BOTTOMLEFT", 0, T.space.xs + T.size.meter + 2)
    end
    if type(W.summaryLine) == "table" then
      call(W.summaryLine, "SetPoint", "BOTTOMLEFT", W.summaryCount, "BOTTOMRIGHT", 0, 0)
    end
    if type(W.summaryDetail) == "table" then
      call(W.summaryDetail, "SetPoint", "BOTTOMRIGHT", summary, "BOTTOMRIGHT", 0, T.space.xs + T.size.meter + 2)
      call(W.summaryDetail, "SetJustifyH", "RIGHT")
    end
    -- The meter: three segments, laid out left to right by PaintSummary. It sits
    -- on the strip's hairline (below), so the band's own bottom edge is never
    -- the thing the meter is drawn over.
    local meter = newFrame("Frame", nil, summary)
    W.summaryMeter = meter
    if type(meter) == "table" then
      call(meter, "SetPoint", "BOTTOMLEFT", summary, "BOTTOMLEFT", 0, T.space.hair)
      call(meter, "SetPoint", "BOTTOMRIGHT", summary, "BOTTOMRIGHT", 0, T.space.hair)
      call(meter, "SetHeight", T.size.meter)
      W.summarySegments = {
        upgrade = swatch(meter, "ledgerUpgrade", 0, T.size.meter),
        tradeoff = swatch(meter, "ledgerTradeoff", 0, T.size.meter),
        noupgrade = swatch(meter, "ledgerNoUpgrade", 0, T.size.meter),
      }
      for _, key in ipairs({ "upgrade", "tradeoff", "noupgrade" }) do
        local seg = W.summarySegments[key]
        if type(seg) == "table" then call(seg, "SetPoint", "BOTTOMLEFT", meter, "BOTTOMLEFT", 0, 0) end
      end
    end
    -- A hairline under the strip, so it reads as a band rather than floating.
    local under = T.Rule(summary, "ledgerLine2", T.space.hair)
    if type(under) == "table" then
      call(under, "SetPoint", "BOTTOMLEFT", summary, "BOTTOMLEFT", 0, 0)
      call(under, "SetPoint", "BOTTOMRIGHT", summary, "BOTTOMRIGHT", 0, 0)
    end
  end

  -- One content host per tab, inset from the frame on the grid. They are always
  -- created, so switching tabs is a Show/Hide of frames we own, never a frame
  -- creation mid-fight.
  W.hosts = {}
  for _, id in ipairs(W.TABS) do
    local host = newFrame("Frame", nil, f)
    -- Under the summary strip when it exists; the strip is chrome, the host is
    -- the tab's own content (card t_07f778ca, PART B3).
    local topAnchor = type(W.summaryFrame) == "table" and W.summaryFrame or strip
    call(host, "SetPoint", "TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -T.space.sm)
    call(host, "SetPoint", "BOTTOMRIGHT", f, "BOTTOMRIGHT", -T.space.md, T.space.md)
    call(host, "Hide")
    W.hosts[id] = host
  end

  -- ESC closes the ONE window. StatForgeMainFrame is dropped from the list at
  -- attach time because hiding the content frame would leave this window open
  -- on an empty tab.
  if type(UISpecialFrames) == "table" then
    local found = false
    for _, name in ipairs(UISpecialFrames) do
      if name == W.NAME then found = true end
    end
    if not found then table.insert(UISpecialFrames, W.NAME) end
  end
  W.SelectTab(W.current or W.DEFAULT_TAB)
  call(f, "Hide")
  return f
end

function W.Frame()
  return W._Ensure()
end

-- ── Tabs ──────────────────────────────────────────────────────────────────
--- Register the renderer a tab runs every time it becomes active. The tab
--- files call this at load; a tab with no renderer still opens (it just shows
--- its host's static content).
function W.OnSelect(id, fn)
  W.renderers = W.renderers or {}
  W.renderers[id] = fn
end

function W.Current()
  return W.current
end

local function paintTabs()
  for _, id in ipairs(W.TABS) do
    W.PaintTab(id)
  end
end

--- Make a tab the visible one. Safe at any time, including in combat: it only
--- shows/hides our own unprotected frames and runs the tab's renderer.
function W.SelectTab(id)
  local f = W._Ensure()
  if not f then return false end
  if type(id) ~= "string" or W.TAB_LABELS[id] == nil then id = W.DEFAULT_TAB end
  W.current = id
  for _, t in ipairs(W.TABS) do
    local host = W.hosts and W.hosts[t]
    if type(host) == "table" then
      if t == id then call(host, "Show") else call(host, "Hide") end
    end
  end
  paintTabs()
  -- The Pack Settings body is Options.lua's panel. Claim it on every
  -- activation: the Settings canvas can take it (a player opening
  -- AddOns > MightiePack), and the next visit to this tab must get it back.
  if id == "settings" and type(W.AttachSettings) == "function" then
    W.AttachSettings()
  elseif type(W.HideSettingsPanel) == "function" then
    -- PART A3 (card t_07f778ca): leaving the tab hides the panel. Before this,
    -- a shown panel stayed shown over whatever tab was active — invisible, and
    -- therefore never reported, but a frame above the content all the same.
    W.HideSettingsPanel()
  end
  local fn = W.renderers and W.renderers[id]
  if type(fn) == "function" then
    local ok, err = pcall(fn, id)
    if not ok then W._renderError = tostring(err) end
  end
  -- After the renderer: a renderer may have just changed what the body knows
  -- (the Touchstone attach is what creates the frame the verdicts live in).
  W.PaintStatus()
  return true
end

-- ── Open / close ──────────────────────────────────────────────────────────
--- Open the window on a tab. No argument re-opens the last tab the player was
--- on (the window's own memory, not a new saved key).
function W.Open(tab)
  local f = W._Ensure()
  if not f then return false end
  call(f, "Show")
  return W.SelectTab(tab or W.current or W.DEFAULT_TAB)
end

function W.Close()
  local f = W.frame
  if type(f) ~= "table" then return false end
  call(f, "Hide")
  return true
end

function W.Toggle(tab)
  if W.IsShown() then return W.Close() end
  return W.Open(tab)
end

function W.IsShown()
  local f = W.frame
  if type(f) ~= "table" then return false end
  local ok, shown = call(f, "IsShown")
  return ok and shown == true
end

--- Shown AND on a given tab.
function W.IsOn(tab)
  return W.IsShown() and W.current == tab
end

-- ── The options panel becomes the Pack Settings tab ───────────────────────
--- Build the Pack Settings rows. One named path, called from the tab's own
--- activation AND from the panel's OnShow (card t_ea66cd84, AC-N3).
---
--- Why activation has to do it: a frame created by CreateFrame is BORN SHOWN,
--- so the birth OnShow is already spent before this tab can ever be opened, and
--- `panel:Show()` on an already-shown frame fires nothing. On its own, OnShow
--- can therefore never build the rows — which is why the client showed the
--- load-time widgets and none of the module rows.
local function buildSettings()
  if type(pkg.SyncOptionsRows) ~= "function" then return false end
  local ok, err = pcall(pkg.SyncOptionsRows)
  W._settingsBuildError = ok and nil or tostring(err)
  return ok
end
W.BuildSettings = buildSettings

--- Reparent Options.lua's panel into the settings host. Idempotent: the
--- Settings canvas can reparent it (a player opening AddOns > MightiePack
--- still gets the same panel), and every open of this window claims it back.
function W.AttachSettings()
  local host = W.hosts and W.hosts.settings
  local panel = pkg.optionsPanel
  if type(host) ~= "table" or type(panel) ~= "table" then return false end
  local okParent, parent = call(panel, "GetParent")
  local hosted = okParent and parent == host and W._settingsHosted
  if not hosted then
    call(panel, "SetParent", host)
    call(panel, "ClearAllPoints")
    call(panel, "SetAllPoints", host)
    W._settingsHosted = true
  end
  -- Show on EVERY activation, not only on the reparent. The Settings canvas
  -- hides the panel when the player leaves AddOns; returning early left it
  -- hidden inside a shown host, so the tab stayed blank for the rest of the
  -- session (AC-N2).
  call(panel, "Show")
  buildSettings()
  return true
end

--- Hide Options.lua's panel — but ONLY when this window owns it. While the
--- Settings canvas holds the panel, its visibility is Blizzard's business (a
--- player reading AddOns > MightiePack must keep the page they are looking at);
--- the moment the window hosts it, the window is the owner and the tab decides
--- (card t_07f778ca, PART A3).
function W.HideSettingsPanel()
  local panel = pkg.optionsPanel
  if type(panel) ~= "table" then return false end
  local host = W.hosts and W.hosts.settings
  local okParent, parent = call(panel, "GetParent")
  if not (okParent and type(host) == "table" and parent == host) then return false end
  call(panel, "Hide")
  return true
end

-- ── The vendored Touchstone frame becomes the Touchstone tab ──────────────
--- Move StatForgeMainFrame in whole. Its inner strip (Upgrades / Log /
--- Settings) stays as navigation: the frame keeps its own tab renderers, its
--- own scale memory (StatForgeDB.ui.scale, applied to this frame) and its own
--- first-use splash.
---
--- HOSTED, THE BODY DRAWS NO CHROME OF ITS OWN (card t_07f778ca, review 2).
--- The window owns the only title, the only close button and the only frame, so
--- the body is told that BEFORE it is created — SF.SetHostedChrome(true), which
--- the vendored UI reads in its own creation path — and told again on the live
--- frame, for a body a /ts session had already built. This file no longer hides
--- a title bar, guesses at the strip or strips the content frame's border: the
--- body does that itself, from a flag it was given, in the file that owns it.
--- Matching chrome by measuring a child's height is the defect this replaces —
--- on the live client the measurement did not hide the bar, and nothing asserted
--- the rendered result.
function W.AttachTouchstone()
  local host = W.hosts and W.hosts.touchstone
  if type(host) ~= "table" then return false end
  local SF = rawget(_G, "StatForge")
  if type(SF) ~= "table" then return false end
  -- Before anything is created: the body's creation path must know it is hosted
  -- (otherwise it builds a title bar and a close button we would have to find
  -- and hide afterwards, which is the mistake).
  local hostedHook = type(SF.SetHostedChrome) == "function" and SF.SetHostedChrome or nil
  if hostedHook then pcall(hostedHook, true) end
  local main = rawget(_G, "StatForgeMainFrame")
  if type(main) ~= "table" then
    -- Not created yet: the vendored entry point creates it, selects a tab and
    -- may show the splash.
    if type(W._sfShowMain) == "function" then
      pcall(W._sfShowMain, "upgrades")
      main = rawget(_G, "StatForgeMainFrame")
    end
  end
  if type(main) ~= "table" then return false end
  if W._touchstoneHosted and select(2, call(main, "GetParent")) == host then
    call(main, "Show")
    if hostedHook then pcall(hostedHook, true) end
    return true
  end
  call(main, "SetParent", host)
  call(main, "ClearAllPoints")
  call(main, "SetAllPoints", host)
  -- Card t_5d0cc41a. The invariant, not a workaround:
  --     fill (W.bg, BACKGROUND)  <  content (this frame, MEDIUM)  <  chrome (DIALOG)
  -- The body stays on MEDIUM so it can never climb into the chrome and cover the
  -- title band, the tab row or the close button. What made it fatal inside the
  -- window was the window painting its own opaque fill in DIALOG: strata beats
  -- frame level, so the fill drew over this whole body. The fill now lives on a
  -- BACKGROUND-strata frame (W.bg), and this line keeps the body above it.
  call(main, "SetFrameStrata", "MEDIUM")
  call(main, "Show")
  -- ONE WINDOW, ONE FRAME (card t_07f778ca, PART A2). The body's own backdrop
  -- is claimed here as well: it keeps its backdrop TABLE (the rows still paint
  -- on it) but paints no border and no fill. This is Part A's approved
  -- statement of "the window is the only frame"; the body's own hosted mode
  -- handles its chrome, its content frame and its palette.
  if type(main.SetBackdrop) == "function" then
    call(main, "SetBackdrop", {
      bgFile = T.tex.solid, tile = false, insets = T.inset.zero,
    })
    call(main, "SetBackdropColor", 0, 0, 0, 0)
  end
  -- Hosted mode, on the live frame: a body created before the flag existed (a
  -- /ts session, or a client that loaded the window late) loses its title bar,
  -- its close button, its border, its fill and its vendored accent here.
  if hostedHook then pcall(hostedHook, true) end
  if type(UISpecialFrames) == "table" then
    for i = #UISpecialFrames, 1, -1 do
      if UISpecialFrames[i] == "StatForgeMainFrame" then
        table.remove(UISpecialFrames, i)
      end
    end
  end
  W._touchstoneHosted = true
  return true
end

--- Is the Touchstone module usable right now? The tab says so plainly when it
--- is not, instead of showing an empty body.
function W.TouchstoneState()
  local SF = rawget(_G, "StatForge")
  if type(SF) ~= "table" then return "missing" end
  if type(pkg.IsModuleEnabled) == "function" then
    local ok, on = pcall(pkg.IsModuleEnabled, "Touchstone")
    if ok and not on then return "off" end
  end
  return "ready"
end

--- The label a tab's body shows when its module is off. Kept here so every
--- tab module and every spec says the same words.
W.MODULE_OFF_TEXT = {
  touchstone = "Touchstone is off. Turn it on in Pack Settings.",
}

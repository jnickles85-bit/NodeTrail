-- MightiePack — the ONE window (card t_a5de2f16, audit group 4).
--
-- Before this file the pack had two outer frames: MightiePackOptionsPanel (a
-- Settings canvas and a standalone frame) and StatForgeMainFrame (Touchstone's
-- 920x620 window). They become four tabs of one movable 960x640 window:
--
--   Herbs          browse/history of the herb records (Window/Herbs.lua)
--   Skinning       what each beast yields (Window/Skinning.lua)
--   Touchstone     the vendored window's content, its inner strip intact
--   Pack Settings  the options panel (Options.lua), skindiag copy moved out
--
-- What this file owns:
--   * the frame, its title bar, its drag, its close and its ESC entry;
--   * the four outer tab buttons and the four content hosts;
--   * where the window was last put — ONE new SavedVariables key with a
--     default, never an existing position key (hard rule 2);
--   * open / close / toggle / select, which the slashes call.
--
-- What it does NOT own: the hover herb panel (NodeTrailHerbPanel stays exactly
-- as it is — it is the in-the-moment surface, this is the browse surface), the
-- route overlay, or any module's own state.
--
-- COMBAT (hard rule 6, Interface 16001): no frame this file creates is
-- protected, and no protected frame is touched anywhere here. Opening,
-- closing, dragging and tab switching only Show/Hide/SetPoint our own frames
-- and reparent two unprotected addon frames (the options panel and the
-- Touchstone content frame) — the same operations a player's click already
-- performs on them today. There is no combat-time layout churn beyond that
-- single reparent, which happens once per session per surface and is a no-op
-- afterwards.

local _, pkg = ...

local W = {}
pkg.Window = W

W.NAME = "MightiePackWindow"
W.WIDTH = 960
W.HEIGHT = 640
W.TITLE_HEIGHT = 40
W.TABS_HEIGHT = 34
W.DEFAULT_TAB = "herbs"
W.TABS = { "herbs", "skinning", "touchstone", "settings" }
W.TAB_LABELS = {
  herbs = "Herbs",
  skinning = "Skinning",
  touchstone = "Touchstone",
  settings = "Pack Settings",
}
-- The new key. Hard rule 1/2: add-only, defaulted, and it never reads or
-- writes StatForgeDB.ui.* or any other existing position/scale key.
W.POS_KEY = "windowPos"

local COLOR = {
  bg = { 0.06, 0.06, 0.07, 0.96 },
  border = { 0.35, 0.30, 0.18, 0.9 },
  title = { 0.95, 0.85, 0.55 },
  text = { 0.88, 0.88, 0.88 },
  muted = { 0.60, 0.60, 0.60 },
  tabOn = { 0.95, 0.85, 0.55 },
  -- Minimal tab affordance (card t_ea66cd84, AC-N4). The strip's real design
  -- belongs to the reshape card; this is only enough that the row reads as
  -- clickable: a faint plate, a brighter plate on hover, and the current tab's
  -- plate picked out. Values are deliberately close to the pack's own surfaces.
  tabOff = { 0.10, 0.10, 0.12, 0.85 },
  tabHover = { 0.17, 0.17, 0.21, 0.95 },
  tabActive = { 0.20, 0.18, 0.12, 0.95 },
  tabEdge = { 0.35, 0.30, 0.18, 0.55 },
  tabEdgeHover = { 0.95, 0.85, 0.55, 0.85 },
}

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

-- Frame creation with the template guarded: a client (or a spec's fake client)
-- without BackdropTemplate/UIPanelCloseButton must still get a usable frame.
local function newFrame(kind, name, parent, template)
  if type(CreateFrame) ~= "function" then return nil end
  if template ~= nil then
    local ok, f = pcall(CreateFrame, kind, name, parent, template)
    if ok and type(f) == "table" then return f end
  end
  local ok, f = pcall(CreateFrame, kind, name, parent)
  if ok and type(f) == "table" then return f end
  return nil
end

local function newFontString(parent, template)
  if type(parent) ~= "table" or type(parent.CreateFontString) ~= "function" then
    return nil
  end
  local ok, fs = pcall(parent.CreateFontString, parent, nil, "OVERLAY", template)
  if ok and type(fs) == "table" then return fs end
  return nil
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

-- ── Frame ─────────────────────────────────────────────────────────────────
-- What a tab's plate looks like: hovered, current, or neither. One helper so
-- the hover script and the state repaint can never disagree (AC-N4).
local function tabColors(id, hover)
  if hover then return COLOR.tabHover, COLOR.tabEdgeHover end
  if id == W.current then return COLOR.tabActive, COLOR.tabEdge end
  return COLOR.tabOff, COLOR.tabEdge
end

--- Paint one tab: its label colour, its plate, and its button state.
function W.PaintTab(id)
  local btn = W.tabButtons and W.tabButtons[id]
  if type(btn) ~= "table" then return false end
  if type(btn.label) == "table" then
    local c = (id == W.current) and COLOR.tabOn or COLOR.muted
    call(btn.label, "SetTextColor", c[1], c[2], c[3])
  end
  if type(btn.SetBackdropColor) == "function" then
    local bg, edge = tabColors(id, btn._hover == true)
    call(btn, "SetBackdropColor", bg[1], bg[2], bg[3], bg[4])
    call(btn, "SetBackdropBorderColor", edge[1], edge[2], edge[3], edge[4])
  end
  if type(btn.SetButtonState) == "function" then
    -- No lock. `SetButtonState(state, true)` was passed here, which locks the
    -- button's state on EVERY tab — the current one to PUSHED and the other
    -- three to NORMAL. A locked button ignores mouse-driven state changes, and
    -- this was the one thing in the code that applied to all four buttons at
    -- once, i.e. consistent with the whole row being dead rather than one tab.
    -- The plate colour (painted above) is what distinguishes current from the
    -- rest, so the lock bought nothing.
    pcall(btn.SetButtonState, btn, (id == W.current) and "PUSHED" or "NORMAL")
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
  call(f, "EnableMouse", true)
  call(f, "SetClampedToScreen", true)
  call(f, "SetMovable", true)
  call(f, "SetToplevel", true)
  if type(f.SetBackdrop) == "function" then
    call(f, "SetBackdrop", {
      -- AC-N7 (card t_ea66cd84): the classic path
      -- `Interface\DialogFrame\UI-DialogBox-Background` does NOT resolve on the
      -- owner's client — the fill painted nothing while the border still drew,
      -- so the window interior was see-through over live terrain. The owner
      -- proved `Interface\Buttons\WHITE8X8` resolves there and goes opaque, and
      -- SetBackdropColor tints it, so COLOR.bg still decides the colour.
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    call(f, "SetBackdropColor", COLOR.bg[1], COLOR.bg[2], COLOR.bg[3], COLOR.bg[4])
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

  -- Title bar: our drag handle, our title, our close button. The Touchstone
  -- frame's own title bar is hidden when its content is moved in, so there is
  -- exactly one.
  local bar = newFrame("Frame", nil, f, "BackdropTemplate") or newFrame("Frame", nil, f)
  W.titleBar = bar
  call(bar, "SetPoint", "TOPLEFT", f, "TOPLEFT", 8, -8)
  call(bar, "SetPoint", "TOPRIGHT", f, "TOPRIGHT", -8, -8)
  call(bar, "SetHeight", W.TITLE_HEIGHT - 8)
  call(bar, "EnableMouse", true)
  if type(bar.RegisterForDrag) == "function" then
    pcall(bar.RegisterForDrag, bar, "LeftButton")
    pcall(bar.SetScript, bar, "OnDragStart", function()
      if type(f.StartMoving) == "function" then pcall(f.StartMoving, f) end
    end)
    pcall(bar.SetScript, bar, "OnDragStop", function()
      -- Save the position ONLY here: a drag is the one event that moves it.
      if type(f.StopMovingOrSizing) == "function" then
        pcall(f.StopMovingOrSizing, f)
      end
      W.SavePosition()
    end)
  end
  local title = newFontString(bar, "GameFontNormalLarge")
  W.title = title
  if type(title) == "table" then
    call(title, "SetPoint", "LEFT", bar, "LEFT", 4, 0)
    local ver = nil
    if type(pkg.PackVersion) == "function" then
      local okV, v = pcall(pkg.PackVersion)
      if okV and type(v) == "string" and v ~= "" then ver = v end
    end
    call(title, "SetText", "MightiePack" .. (ver and ("  v" .. ver) or ""))
    call(title, "SetTextColor", COLOR.title[1], COLOR.title[2], COLOR.title[3])
  end
  local close = newFrame("Button", nil, bar, "UIPanelCloseButton") or newFrame("Button", nil, bar)
  if type(close) == "table" then
    call(close, "SetPoint", "RIGHT", bar, "RIGHT", 2, 0)
    if type(close.SetText) == "function" and type(close.GetNormalTexture) ~= "function" then
      call(close, "SetText", "X")
    elseif type(close.SetNormalTexture) == "function" then
      call(close, "SetNormalTexture", "Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    end
    call(close, "SetScript", "OnClick", function() W.Close() end)
    W.close = close
  end

  -- Outer tab strip.
  local strip = newFrame("Frame", nil, f)
  W.tabStrip = strip
  call(strip, "SetPoint", "TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
  call(strip, "SetPoint", "TOPRIGHT", bar, "BOTTOMRIGHT", 0, -6)
  call(strip, "SetHeight", W.TABS_HEIGHT)
  W.tabButtons = {}
  local x = 0
  for _, id in ipairs(W.TABS) do
    -- Card t_ea66cd84. Two changes to the row, both minimal on purpose:
    --   * `BackdropTemplate` + a plate and a hover tint, so the row reads as
    --     clickable instead of as plain text (AC-N4). The real strip design
    --     belongs to the reshape card t_2d2c37b0;
    --   * a frame level above every sibling in this window, so nothing the
    --     window creates — the hosts, the title bar, anything added later —
    --     can draw over the row and take its clicks. A sibling created after
    --     the strip sits at the same level as the strip and would otherwise be
    --     able to cover the row if any of those rects ever moved up.
    local btn = newFrame("Button", nil, strip, "BackdropTemplate") or newFrame("Button", nil, strip)
    call(btn, "SetSize", 150, W.TABS_HEIGHT - 4)
    call(btn, "SetPoint", "LEFT", strip, "LEFT", x, 0)
    x = x + 156
    call(btn, "EnableMouse", true)
    if type(btn.SetBackdrop) == "function" then
      call(btn, "SetBackdrop", {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
      })
    end
    local okLevel, stripLevel = call(strip, "GetFrameLevel")
    if okLevel and type(stripLevel) == "number" then
      call(btn, "SetFrameLevel", stripLevel + 5)
    end
    local fs = newFontString(btn, "GameFontNormal")
    if type(fs) == "table" then
      call(fs, "SetPoint", "CENTER", btn, "CENTER", 0, 0)
      call(fs, "SetText", W.TAB_LABELS[id])
    end
    btn.label = fs
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
  end

  -- One content host per tab. They are always created, so switching tabs is a
  -- Show/Hide of frames we own, never a frame creation mid-fight.
  W.hosts = {}
  for _, id in ipairs(W.TABS) do
    local host = newFrame("Frame", nil, f)
    call(host, "SetPoint", "TOPLEFT", strip, "BOTTOMLEFT", 8, -6)
    call(host, "SetPoint", "BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
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
  end
  local fn = W.renderers and W.renderers[id]
  if type(fn) == "function" then
    local ok, err = pcall(fn, id)
    if not ok then W._renderError = tostring(err) end
  end
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

-- ── The vendored Touchstone frame becomes the Touchstone tab ──────────────
--- Move StatForgeMainFrame in whole. Its inner strip (Upgrades / Log /
--- Settings) is untouched: the frame keeps its own tab renderers, its own
--- scale memory (StatForgeDB.ui.scale, applied to this frame) and its own
--- first-use splash. Only its outer chrome goes: the title bar is hidden
--- (the unified window has the only title and the only close button) and the
--- strip is re-anchored to the top of the frame so the hidden band is not a
--- gap.
function W.AttachTouchstone()
  local host = W.hosts and W.hosts.touchstone
  if type(host) ~= "table" then return false end
  local SF = rawget(_G, "StatForge")
  if type(SF) ~= "table" then return false end
  local main = rawget(_G, "StatForgeMainFrame")
  if type(main) ~= "table" then
    -- Not created yet: the module was enabled but nobody has opened it. The
    -- vendored entry point creates it, selects a tab and may show the splash.
    if type(W._sfShowMain) == "function" then
      pcall(W._sfShowMain, "upgrades")
      main = rawget(_G, "StatForgeMainFrame")
    end
  end
  if type(main) ~= "table" then return false end
  if W._touchstoneHosted and select(2, call(main, "GetParent")) == host then
    call(main, "Show")
    return true
  end
  call(main, "SetParent", host)
  call(main, "ClearAllPoints")
  call(main, "SetAllPoints", host)
  call(main, "SetFrameStrata", "MEDIUM")
  call(main, "Show")
  -- Hide the title bar. The frame's children in creation order are titleBar
  -- (height 40), tabStrip (height 32), contentFrame and, on a first use, the
  -- splash cover (which fills the frame). Matching on the 40px height picks
  -- the title bar and nothing else; if the vendored layout ever changes, the
  -- worst case is a second title bar drawn inside the tab, never a broken tab.
  local okKids, kids = call(main, "GetChildren")
  if okKids and type(kids) == "table" then
    for _, child in ipairs(kids) do
      if type(child) == "table" and num(child, "GetHeight") == 40 then
        call(child, "Hide")
        W._hiddenTitleBar = child
      end
    end
  end
  -- Re-anchor the inner strip to the top so the hidden title band is not a
  -- 40px hole. contentFrame hangs off the strip, so it follows.
  local strip = nil
  if okKids and type(kids) == "table" then
    for _, child in ipairs(kids) do
      if type(child) == "table" and child ~= W._hiddenTitleBar and num(child, "GetHeight") == 32 then
        strip = child
      end
    end
  end
  if type(strip) == "table" then
    call(strip, "ClearAllPoints")
    call(strip, "SetPoint", "TOPLEFT", main, "TOPLEFT", 12, -8)
    call(strip, "SetPoint", "TOPRIGHT", main, "TOPRIGHT", -12, -8)
  end
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
--  is not, instead of showing an empty body.
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
  herbs = "NodeTrail is off. Turn it on in Pack Settings.",
  skinning = "NodeTrail's skinning recorder is off. Turn it on in Pack Settings.",
}

if MightiePackTouchstoneSkip then return end
--- StatForge main window: chrome, tabs, content host.
--- Pure frames (no Ace) — Classic Era compatible.
---
--- Card t_adf556d6 retired the export half, so the Export and Gear tabs are
--- gone with ExportTab.lua / GearTab.lua.
---
--- Card t_b7b5f60c (audit U1 + B8) then made the window show the ADVISOR:
---   * the default tab is "upgrades" — the advisor's own answer list — because
---     the window IS the advisor's home (the owner's ruling: the addon gives
---     in-game advice, so the window opens on that advice, not on a settings
---     page and not on the retired desktop surfaces);
---   * each tab gets ONE persistent host frame, created on first show and
---     reused forever. The old code hid + SetParent(nil)'d the host and made a
---     new one on every switch — and WoW never frees a frame, so every tab
---     click, bank open/close and setup-button click orphaned a whole frame
---     tree (audit B8). Repopulation is now the tabs' own job: a tab builds its
---     widgets once and re-binds data on refresh.

StatForge = StatForge or {}
local SF = StatForge

local C = SF.Colors

local mainFrame
local tabButtons = {}
local contentFrame
local contentHost
-- The tab ids the window can show. "upgrades" is the default (audit U1): it is
-- the advisor's own verdict list, it exists after the export retirement, and it
-- is the product. "log" is the disagreement log; "options" is the settings
-- surface (role / toast / tooltip / minimap / diagnostics).
local TAB_ORDER = { "upgrades", "log", "options" }
local TAB_LABELS = { upgrades = "Upgrades", log = "Log", options = "Settings" }
-- A tab id that is not registered (a caller asked for a tab that does not
-- exist, or the registry loaded late) falls back to the default rather than
-- rendering an empty host.
local FALLBACK_TAB = "upgrades"
local activeTab = "upgrades"
-- The tab whose renderer last ran, so a releaser fires on a real switch only.
local renderedTab
local tabRenderers = {}
local tabReleasers = {}
-- One host frame per tab id, created lazily on first show and NEVER unparented.
-- This table is the B8 fix: it replaces the per-switch CreateFrame.
local tabHosts = {}

-- ── Hosted mode (card t_07f778ca) ─────────────────────────────────────────
-- MightiePack can host this frame inside its own window. There the pack owns
-- the only title, the only close button, the only frame and the only palette,
-- so this file must draw NONE of them. The host says so explicitly —
-- SF.SetHostedChrome(true) BEFORE the frame is created skips the chrome
-- entirely, and the same call on a frame created earlier (a /ts session before
-- the window opened) removes what is already there. Every creation and paint
-- path below reads that flag.
--
-- Nothing here recognises a piece of chrome by its height, its child order or
-- its name. `chrome` holds direct references to the parts hosting removes, and
-- it is empty when they were never built. Matching the title bar by measuring
-- it is the defect this replaces: the harness and the client disagreed about
-- the measurement, and the live client drew the title bar anyway.
local hostedChrome = false
local chrome = {}   -- titleBar / close / title / subtitle / strip, when built
-- Every button SF.UI_CreateButton makes, so the hosted palette can be applied to
-- buttons that were painted BEFORE the body was hosted (a /ts session). Buttons
-- created hosted resolve the palette at creation and need nothing here.
local uiButtons = {}
-- Repaint callbacks for accent-coloured things built before hosting (a Settings
-- tab rendered by a /ts session). Hosted mode runs them, so adoption repaints
-- instead of leaving the module's teal behind in already-built widgets.
local accentPainters = {}

-- A flat fill: no border art, so NO insets. A WHITE8X8 fill with insets paints
-- its colour inside them, leaving a transparent ring between the fill and the
-- frame's edge — the 2026-11-14 outline defect. Backdrop insets belong to
-- border art; a flat colour never needs them.
local FLAT_BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8x8",
  tile = false, tileSize = 0,
  insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

local BACKDROP = {
  bgFile   = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Buttons\\WHITE8x8",
  tile = false, tileSize = 0, edgeSize = 1,
  insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

local function applyBackdrop(frame, bg, border, bgA, borderA)
  frame:SetBackdrop(BACKDROP)
  frame:SetBackdropColor(bg[1], bg[2], bg[3], bgA or 0.97)
  frame:SetBackdropBorderColor(border[1], border[2], border[3], borderA or 1)
end

-- ── The accent in play (card t_07f778ca) ──────────────────────────────────
-- Standalone, this body's accent is its own brand (SF.Colors.accent) and stays
-- that way. Hosted, the pack's theme owns the palette: the body's teal is its
-- own chrome, and the window has none of it (the owner's retest: "the module's
-- teal chrome — title, tab highlights, Settings headings"). The pack publishes
-- MightiePackTheme at load, before this file, so the lookup needs no ordering
-- promise beyond the TOC's.
--- The accent colour table a heading, a tab or a primary button paints with.
function SF.UI_Accent()
  if hostedChrome then
    local T = rawget(_G, "MightiePackTheme")
    if type(T) == "table" and type(T.Ledger) == "function" then
      local r, g, b = T.Ledger("text")
      return { r, g, b }
    end
  end
  return C.accent
end

--- Set a FontString's colour to the accent in play, and remember it so a body
--- adopted LATER is repainted rather than left in the module's teal.
function SF.UI_SetAccent(fs)
  if type(fs) ~= "table" then return false end
  local ac = SF.UI_Accent()
  fs:SetTextColor(ac[1], ac[2], ac[3])
  if not fs.__accentRegistered then
    fs.__accentRegistered = true
    accentPainters[#accentPainters + 1] = function()
      local c = SF.UI_Accent()
      fs:SetTextColor(c[1], c[2], c[3])
    end
  end
  return true
end

--- Register a repaint for accent-coloured content that is not a plain FontString
--- colour (the Settings About block carries its accent as a colour CODE inside a
--- string). Hosted mode calls every registered painter (card t_07f778ca).
function SF.OnAccentRepaint(fn)
  if type(fn) == "function" then accentPainters[#accentPainters + 1] = fn end
end

--- `text` wrapped in a colour code for the accent in play. The body has its own
--- SF.Accent(), which writes a FIXED "|cff66fcf1" code into a string — hosted,
--- that re-paints the module's teal inside a paragraph (the About block) where
--- no SetTextColor call can be seen (card t_07f778ca, review 2).
function SF.UI_AccentText(text)
  local ac = SF.UI_Accent()
  return string.format("|cff%02x%02x%02x%s|r",
    math.floor(ac[1] * 255 + 0.5), math.floor(ac[2] * 255 + 0.5),
    math.floor(ac[3] * 255 + 0.5), tostring(text))
end

--- A button's plate and label colour. Hosted, a button is a FLAT plate from the
--- pack's ledger palette: the drawing has no bordered boxes, and a vendored
--- WHITE8x8 edge on every control is the same "bordered box" language the owner
--- rejected (card t_07f778ca, review 2). Standalone, nothing changes.
local function paintButtonPlate(btn, state)
  if type(btn) ~= "table" then return false end
  local hosted = hostedChrome
  local T = hosted and rawget(_G, "MightiePackTheme") or nil
  if type(T) == "table" and type(T.Ledger) == "function" then
    local fillToken = (state == "hover" or state == "primary") and "raised" or "surface"
    local r, g, b, a = T.Ledger(fillToken)
    btn:SetBackdrop(FLAT_BACKDROP)
    btn:SetBackdropColor(r, g, b, a or 1)
    if state == "success" then
      local sr, sg, sb = T.Ledger("upgrade")
      btn.label:SetTextColor(sr, sg, sb)
    elseif state == "rest" then
      local tr, tg, tb = T.Ledger("text")
      btn.label:SetTextColor(tr, tg, tb)
    else
      SF.UI_SetAccent(btn.label)
    end
    return true
  end
  if state == "hover" then
    applyBackdrop(btn, C.surfaceHover, C.accent, 1, 0.8)
    SF.UI_SetAccent(btn.label)
  elseif state == "primary" then
    applyBackdrop(btn, C.accentDim, C.accent, 0.35, 1)
    SF.UI_SetAccent(btn.label)
  elseif state == "success" then
    applyBackdrop(btn, { 0.08, 0.35, 0.18 }, C.success, 1, 0.9)
    btn.label:SetTextColor(C.success[1], C.success[2], C.success[3])
  else
    applyBackdrop(btn, C.surfaceHover, C.border, 1, 1)
    btn.label:SetTextColor(C.text[1], C.text[2], C.text[3])
  end
  return true
end

function SF.UI_CreateButton(parent, text, width, height)
  local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
  btn:SetSize(width or 120, height or 28)
  btn:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
  local ht = btn:GetHighlightTexture()
  if ht then
    local ac = SF.UI_Accent()
    ht:SetVertexColor(ac[1], ac[2], ac[3], 0.12)
  end

  local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("CENTER")
  fs:SetText(text or "")
  btn.label = fs
  paintButtonPlate(btn, "rest")

  btn:SetScript("OnEnter", function(self)
    paintButtonPlate(self, "hover")
  end)
  btn:SetScript("OnLeave", function(self)
    if self._primary then
      paintButtonPlate(self, "primary")
    elseif self._success then
      paintButtonPlate(self, "success")
    else
      paintButtonPlate(self, "rest")
    end
  end)

  function btn:SetPrimary(on)
    self._primary = on
    self._success = false
    if on then
      paintButtonPlate(self, "primary")
    end
  end

  function btn:SetSuccess(on)
    self._success = on
    self._primary = false
    if on then
      paintButtonPlate(self, "success")
    end
  end

  function btn:SetLabel(t)
    self.label:SetText(t)
  end

  uiButtons[#uiButtons + 1] = btn
  return btn
end

function SF.UI_CreateLabel(parent, text, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
  fs:SetText(text or "")
  fs:SetTextColor(C.text[1], C.text[2], C.text[3])
  fs:SetJustifyH("LEFT")
  return fs
end

-- Clear a frame's children for REUSE (card t_b7b5f60c, B8). This used to
-- `SetParent(nil)` each child — and WoW NEVER frees a frame, so an unparented
-- child is a permanent orphan: not drawn, not reachable, still resident. Every
-- caller leaked its whole child list per call. Now the children are HIDDEN and
-- LEFT in place; a caller that wants a fresh list either reuses the pooled
-- children or keeps its own frame table and hides the ones it no longer needs.
-- (This is the same defect shape the Audit found in selectTab; both are fixed.)
function SF.UI_ClearChildren(frame)
  if type(frame) ~= "table" or type(frame.GetChildren) ~= "function" then return end
  local kids = { frame:GetChildren() }
  for _, child in ipairs(kids) do
    child:Hide()
  end
  -- FontStrings created directly on the frame: hide them and blank the text.
  -- They are named children of the frame, so the loop above already hid them;
  -- this only clears stale text so a reused label cannot show old content.
  local regions = { frame:GetRegions() }
  for _, r in ipairs(regions) do
    if r.GetObjectType and r:GetObjectType() == "FontString" and r ~= frame.title then
      r:Hide()
      r:SetText("")
    end
  end
end

function SF.RegisterTab(id, renderer, releaser)
  tabRenderers[id] = renderer
  tabReleasers[id] = releaser
end

-- The tabs the window can show, in tab-strip order. Live ids only: a tab whose
-- renderer never registered is dropped, so the strip and the registry can never
-- disagree.
local function liveTabIds()
  local out = {}
  for _, id in ipairs(TAB_ORDER) do
    if type(tabRenderers[id]) == "function" then
      out[#out + 1] = id
    end
  end
  return out
end

-- The id a requested tab resolves to. An unknown id (a retired tab, a typo)
-- falls back to the default so the window can never open on nothing.
local function resolveTabId(id)
  if type(id) == "string" and type(tabRenderers[id]) == "function" then
    return id
  end
  if type(tabRenderers[FALLBACK_TAB]) == "function" then
    return FALLBACK_TAB
  end
  local live = liveTabIds()
  return live[1]
end

-- The ONE host frame for a tab id. Created on first use; never reparented and
-- never recreated (B8). Each tab owns its own host, so switching tabs cannot
-- disturb the other tab's frame tree.
local function hostFor(id)
  if type(id) ~= "string" then return nil end
  local h = tabHosts[id]
  if not h then
    if not contentFrame then return nil end
    h = CreateFrame("Frame", nil, contentFrame)
    h:SetAllPoints(contentFrame)
    h:Hide()
    tabHosts[id] = h
  end
  return h
end

-- ── The inner strip's plates (card t_07f778ca) ────────────────────────────
-- The inner strip (Upgrades / Log / Settings) stays NAVIGATION when the pack
-- hosts the body: the tabs still exist, still switch, still render. What goes
-- is the module's chrome — the vendored teal highlight and the bordered plate.
-- Hosted, a plate is flat (zero insets, no border art): the active tab is a
-- raised surface with its label in the reading colour, the rest are bare.
local function paintTabPlate(btn, active)
  if type(btn) ~= "table" then return false end
  if hostedChrome then
    local T = rawget(_G, "MightiePackTheme")
    if type(T) == "table" and type(T.Ledger) == "function" then
      btn:SetBackdrop(FLAT_BACKDROP)
      if active then
        local r, g, b, a = T.Ledger("raised")
        btn:SetBackdropColor(r, g, b, a or 1)
        r, g, b = T.Ledger("text")
        btn.label:SetTextColor(r, g, b)
      else
        btn:SetBackdropColor(0, 0, 0, 0)
        local r, g, b = T.Ledger("muted")
        btn.label:SetTextColor(r, g, b)
      end
      return true
    end
  end
  if active then
    applyBackdrop(btn, C.surfaceHover, C.accent, 1, 0.9)
    btn.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
  else
    applyBackdrop(btn, C.bg, C.border, 0.6, 0.7)
    btn.label:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  end
  return true
end

local function selectTab(id)
  id = resolveTabId(id)
  if id == nil then return end

  -- Leaving a tab: run its releaser (release the OLD tab's state), but only if
  -- its renderer actually ran — never release a tab that never built anything.
  if renderedTab and renderedTab ~= id and tabReleasers[renderedTab] then
    pcall(tabReleasers[renderedTab])
  end

  activeTab = id
  -- U6 (card t_6696b35a): remember the tab across sessions. The id written
  -- here is the resolved one, so a retired name cannot be what we restore.
  if StatForgeDB and type(id) == "string" then
    StatForgeDB.ui = StatForgeDB.ui or {}
    StatForgeDB.ui.lastTab = id
  end

  for tid, btn in pairs(tabButtons) do
    paintTabPlate(btn, tid == id)
  end

  -- Create the host BEFORE the show/hide loop. hostFor builds the first
  -- frame hidden; doing that after the loop left the first open of every
  -- tab painted into a frame nothing had shown (blank until the next open).
  contentHost = hostFor(id)
  -- Show THIS tab's persistent host; hide every other. No CreateFrame, no
  -- SetParent(nil) — the hosts are made once and live for the session.
  for tid, h in pairs(tabHosts) do
    if tid == id then h:Show() else h:Hide() end
  end

  if tabRenderers[id] and contentHost then
    tabRenderers[id](contentHost)
    renderedTab = id
  end
end

function SF.SelectTab(id)
  if not mainFrame then
    SF.ShowMain()
  end
  selectTab(id)
end

local function savePosition()
  if not mainFrame or not StatForgeDB then return end
  StatForgeDB.ui = StatForgeDB.ui or {}
  local p = StatForgeDB.ui
  -- store only numbers — GetPoint's relTo is a Frame userdata, which
  -- SavedVariables can't serialize
  local left = mainFrame:GetLeft()
  local top = mainFrame:GetTop()
  if left and top then
    p.left = left
    p.top = top
  end
end

local function restorePosition(frame)
  local p = StatForgeDB and StatForgeDB.ui
  if p and p.left and p.top then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.left, p.top)
  else
    frame:SetPoint("CENTER")
  end
end

-- U6 (card t_6696b35a): window scale, only because the frame already exists
-- and SetScale is one call. The Settings slider and `/ts scale <0.5-1.5>` are
-- the two controls, and the value is clamped so a stray number cannot make the
-- window unreadably small or huge. The number is the same StatForgeDB.ui table
-- the position already uses — no new variable.
--
-- Card t_75261b9a: there is deliberately NO mouse wheel on this window. The
-- wheel is this client's camera zoom, and the panel covers a large part of the
-- screen, so a window-level OnMouseWheel took the zoom away for as long as the
-- window was open and silently wrote every stray scroll into
-- StatForgeDB.ui.scale, where it survived /reload. Do not put a wheel handler
-- or EnableMouseWheel(true) back on `f`; the slider (OptionsTab.lua) and
-- `/ts scale` are the scale surface.
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.5, 1.5, 0.1

function SF.SetWindowScale(scale)
  if type(scale) ~= "number" then return nil end
  if scale < SCALE_MIN then scale = SCALE_MIN end
  if scale > SCALE_MAX then scale = SCALE_MAX end
  scale = math.floor(scale * 100 + 0.5) / 100
  if mainFrame and type(mainFrame.SetScale) == "function" then
    mainFrame:SetScale(scale)
  end
  if StatForgeDB then
    StatForgeDB.ui = StatForgeDB.ui or {}
    StatForgeDB.ui.scale = scale
  end
  return scale
end

function SF.GetWindowScale()
  if mainFrame and type(mainFrame.GetScale) == "function" then
    local s = mainFrame:GetScale()
    if type(s) == "number" then return s end
  end
  local saved = StatForgeDB and StatForgeDB.ui and StatForgeDB.ui.scale
  if type(saved) == "number" then return saved end
  return 1
end

function SF.WindowScaleBounds()
  return SCALE_MIN, SCALE_MAX, SCALE_STEP
end

function SF.ActiveTab()
  return activeTab
end

local function createMainFrame()
  if mainFrame then return mainFrame end

  local f = CreateFrame("Frame", "StatForgeMainFrame", UIParent, "BackdropTemplate")
  f:SetSize(920, 620)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  if hostedChrome then
    -- Hosted: the pack window is the only frame. No border, no fill of ours —
    -- one window, one frame (card t_07f778ca).
    f:SetBackdrop(FLAT_BACKDROP)
    f:SetBackdropColor(0, 0, 0, 0)
  else
    applyBackdrop(f, C.bg, C.accentDim, 0.97, 0.85)
  end
  restorePosition(f)

  -- title bar (drag handle) — NOT built when the pack hosts this frame. The
  -- window owns the only title and the only close button; a second title bar
  -- (and its close) inside the tab is the "two frames" the owner saw. The
  -- decision is made HERE, at creation, from the flag the host set — not later
  -- by measuring children (card t_07f778ca).
  if not hostedChrome then
    local titleBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(40)
    applyBackdrop(titleBar, C.surface, C.border, 1, 0.5)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
      f:StopMovingOrSizing()
      savePosition()
    end)
    chrome.titleBar = titleBar

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", 16, 0)
    title:SetText(SF.UI_AccentText("Touchstone"))
    title:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    chrome.title = title

    local subtitle = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("LEFT", title, "RIGHT", 10, 0)
    -- B12 (card t_4412b04b): this used to read "Classic Hardcore · v…", which named
    -- a product scope the addon never had (it is not Hardcore-only). The ruling
    -- makes the scope plain: in-game Classic-era gear advice.
    -- Pack audit: the header showed Touchstone's upstream module version (SF.VERSION,
    -- e.g. 0.8.3) while the pack was 0.3.x. Show the pack TOC version here; the
    -- module version stays on the Settings About line and in diagnostics.
    local packVer
    do
      local pkg = rawget(_G, "MightiePack")
      if type(pkg) == "table" and type(pkg.PackVersion) == "function" then
        local ok, v = pcall(pkg.PackVersion)
        if ok and type(v) == "string" and v ~= "" then
          packVer = v
        end
      end
    end
    if packVer then
      subtitle:SetText("Classic-era item advisor  ·  v" .. packVer)
    else
      subtitle:SetText("Classic-era item advisor")
    end
    subtitle:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
    chrome.subtitle = subtitle

    local close = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    close:SetPoint("RIGHT", -4, 0)
    close:SetScript("OnClick", function() f:Hide() end)
    chrome.close = close
  end

  -- tab strip
  local tabStrip = CreateFrame("Frame", nil, f)
  if hostedChrome then
    -- No title band to hang under: the strip is the body's own top edge.
    tabStrip:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -8)
    tabStrip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -8)
  else
    tabStrip:SetPoint("TOPLEFT", chrome.titleBar, "BOTTOMLEFT", 12, -8)
    tabStrip:SetPoint("TOPRIGHT", chrome.titleBar, "BOTTOMRIGHT", -12, -8)
  end
  tabStrip:SetHeight(32)
  chrome.strip = tabStrip

  -- Tab strip. The buttons come from the LIVE registry (card t_b7b5f60c): a tab
  -- appears iff a module registered it, so a retired tab cannot leave a dead
  -- button behind and a new tab cannot be invisible. The order and labels are
  -- the window's own (TAB_ORDER / TAB_LABELS); the Upgrades tab leads.
  local tabs = {}
  for _, id in ipairs(liveTabIds()) do
    tabs[#tabs + 1] = { id = id, label = TAB_LABELS[id] or id }
  end

  local x = 0
  for _, t in ipairs(tabs) do
    local btn = CreateFrame("Button", nil, tabStrip, "BackdropTemplate")
    btn:SetSize(100, 30)
    btn:SetPoint("LEFT", x, 0)
    x = x + 108

    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER")
    fs:SetText(t.label)
    btn.label = fs
    paintTabPlate(btn, false)

    btn:SetScript("OnClick", function() selectTab(t.id) end)
    tabButtons[t.id] = btn
  end

  -- content area
  contentFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
  contentFrame:SetPoint("TOPLEFT", tabStrip, "BOTTOMLEFT", 0, -8)
  contentFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
  if hostedChrome then
    -- ONE FLAT PLANE. The content frame used to paint a WHITE8X8 border and a
    -- surface fill; hosted inside the window that is the bordered box the owner
    -- saw around the ledger (card t_07f778ca, A2). No border, no fill: the
    -- window's own plane is the only one.
    contentFrame:SetBackdrop(FLAT_BACKDROP)
    contentFrame:SetBackdropColor(0, 0, 0, 0)
  else
    applyBackdrop(contentFrame, C.surface, C.border, 0.6, 0.5)
  end

  -- ESC close
  tinsert(UISpecialFrames, "StatForgeMainFrame")

  -- Card t_75261b9a: this is where `f:EnableMouseWheel(true)` +
  -- OnMouseWheel used to live, rescaling the window on any scroll over it.
  -- They are gone on purpose — see the note on SCALE_STEP above. A wheel over
  -- the panel belongs to the camera; the slider and `/ts scale` are the scale
  -- controls. Nothing here reads the wheel, so nothing here can persist a
  -- stray scroll into StatForgeDB.ui.scale.

  f:SetScript("OnHide", function()
    -- The tab hosts are children of the window, so hiding the window hides them
    -- too; this only lets the active tab release per-session state (tooltips).
    if renderedTab and tabReleasers[renderedTab] then
      pcall(tabReleasers[renderedTab])
    end
    if GameTooltip then GameTooltip:Hide() end
  end)

  f:Hide()
  mainFrame = f
  local savedScale = StatForgeDB and StatForgeDB.ui and StatForgeDB.ui.scale
  if type(savedScale) == "number" then
    SF.SetWindowScale(savedScale)
  end
  return f
end

-- ── Hosted mode: the host's one call (card t_07f778ca) ────────────────────
--- Tell this frame whether the pack is hosting it.
---
--- `true` means: draw no chrome of our own. No title bar, no close button, no
--- border, no fill, no vendored accent — and the inner strip stays as plain
--- navigation in the pack's tokens. The host calls this BEFORE the frame exists
--- (so the chrome is never built) and again on the live frame (so a body that a
--- /ts session already created loses what it has). Idempotent.
---
--- The three things it changes are all things this file OWNS: its own chrome,
--- its own backdrops and its own palette. It never guesses which child is the
--- title bar — `chrome` holds the references, and is empty when hosting was on
--- before creation, which is the normal path.
function SF.SetHostedChrome(on)
  hostedChrome = on and true or false
  if not hostedChrome then return false end
  -- Repaint the strip even when the frame does not exist yet: tabButtons is
  -- empty then, so this is a no-op rather than a special case.
  for tid, btn in pairs(tabButtons) do
    paintTabPlate(btn, tid == activeTab)
  end
  -- Buttons created before the body was hosted (a Settings tab rendered by a
  -- /ts session) still carry the vendored plate; repaint them in the pack's.
  for _, btn in ipairs(uiButtons) do
    if btn._primary then
      paintButtonPlate(btn, "primary")
    elseif btn._success then
      paintButtonPlate(btn, "success")
    else
      paintButtonPlate(btn, "rest")
    end
  end
  -- Accent-coloured text built before hosting (the Settings headings and the
  -- About block): repaint it in the pack's palette.
  for _, paint in ipairs(accentPainters) do
    pcall(paint)
  end
  if not mainFrame then return true end
  local f = mainFrame
  if type(f.SetBackdrop) == "function" then
    f:SetBackdrop(FLAT_BACKDROP)
    f:SetBackdropColor(0, 0, 0, 0)
  end
  if type(contentFrame) == "table" and type(contentFrame.SetBackdrop) == "function" then
    contentFrame:SetBackdrop(FLAT_BACKDROP)
    contentFrame:SetBackdropColor(0, 0, 0, 0)
  end
  -- The parts hosting removes, by reference. A frame created in hosted mode has
  -- none of them (the creation path skipped them).
  if type(chrome.titleBar) == "table" then chrome.titleBar:Hide() end
  if type(chrome.close) == "table" then chrome.close:Hide() end
  if type(chrome.title) == "table" then chrome.title:Hide() end
  if type(chrome.subtitle) == "table" then chrome.subtitle:Hide() end
  -- No hidden 40px band at the top: the strip moves to the frame's own top edge.
  if type(chrome.strip) == "table" then
    chrome.strip:ClearAllPoints()
    chrome.strip:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -8)
    chrome.strip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -8)
  end
  return true
end

--- The frame the inner tabs render into. A handle for the specs, so "the box
--- under the body" is a reference rather than a measured height or a name.
function SF.ContentFrame()
  return contentFrame
end

--- The chrome hosting removes, by reference (titleBar / close / title /
--- subtitle / strip). Empty when the frame was created in hosted mode.
function SF.Chrome()
  return chrome
end

function SF.ShowMain(tabId)
  createMainFrame()
  mainFrame:Show()
  mainFrame:Raise()
  -- U6: an explicit tab wins; otherwise the tab saved last session. The
  -- file-local default ("upgrades") is only the first-ever open.
  local picked = tabId
  if picked == nil and StatForgeDB and StatForgeDB.ui
      and type(StatForgeDB.ui.lastTab) == "string" then
    picked = StatForgeDB.ui.lastTab
  end
  selectTab(picked or activeTab or FALLBACK_TAB)

  -- first-use splash (once)
  if StatForgeDB and StatForgeDB.firstUse ~= false then
    SF.ShowFirstUseSplash()
  end
end

function SF.HideMain()
  if mainFrame then mainFrame:Hide() end
end

function SF.ToggleMain()
  if mainFrame and mainFrame:IsShown() then
    SF.HideMain()
  else
    SF.ShowMain()
  end
end

function SF.IsMainShown()
  return mainFrame and mainFrame:IsShown()
end

function SF.GetContentFrame()
  return contentFrame
end

function SF.RefreshActiveTab()
  if mainFrame and mainFrame:IsShown() then
    selectTab(activeTab)
  end
end

-- ---------------------------------------------------------------------------
-- First-use splash overlay
-- ---------------------------------------------------------------------------
local splashFrame

function SF.ShowFirstUseSplash()
  if not mainFrame then return end
  if splashFrame then
    splashFrame:Show()
    return
  end

  local cover = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
  cover:SetAllPoints(mainFrame)
  cover:SetFrameLevel(mainFrame:GetFrameLevel() + 50)
  applyBackdrop(cover, C.black, C.border, 0.78, 0)
  cover:EnableMouse(true)

  local panel = CreateFrame("Frame", nil, cover, "BackdropTemplate")
  panel:SetSize(520, 360)
  panel:SetPoint("CENTER")
  applyBackdrop(panel, C.surface, SF.UI_Accent(), 1, 0.6)

  local h = SF.UI_CreateLabel(panel, SF.UI_AccentText("Welcome to Touchstone"), "GameFontNormalLarge")
  h:SetPoint("TOP", 0, -24)
  h:SetJustifyH("CENTER")

  local body = SF.UI_CreateLabel(panel, "", "GameFontHighlight")
  body:SetPoint("TOP", h, "BOTTOM", 0, -20)
  body:SetWidth(460)
  body:SetJustifyH("LEFT")
  -- The numbered marks were fixed teal codes; hosted they resolve like every
  -- other accent (card t_07f778ca, review 2).
  body:SetText(
    "Touchstone reads the gear you are holding and tells you, in the game, whether it beats what you wear.\n\n" ..
    SF.UI_AccentText("1.") .. "  Hover a chest, weapon or armour piece in your bags to see the call.\n\n" ..
    SF.UI_AccentText("2.") .. "  A green |cffffffffarrow|r marks an upgrade. An amber |cffffffffsquare|r marks a trade-off: better on some stats, worse on others.\n\n" ..
    SF.UI_AccentText("3.") .. "  |cffffffff/ts|r opens this window; |cffffffff/ts help|r lists the commands."
  )
  body:SetTextColor(C.text[1], C.text[2], C.text[3])

  local ok = SF.UI_CreateButton(panel, "Got it", 140, 32)
  ok:SetPoint("BOTTOM", 0, 24)
  ok:SetPrimary(true)
  ok:SetScript("OnClick", function()
    if StatForgeDB then StatForgeDB.firstUse = false end
    cover:Hide()
  end)

  splashFrame = cover
end

-- ---------------------------------------------------------------------------
-- Minimap button
-- ---------------------------------------------------------------------------
local minimapBtn

function SF.UpdateMinimapButton()
  local hide = StatForgeDB and StatForgeDB.minimapHide
  if hide then
    if minimapBtn then minimapBtn:Hide() end
    return
  end
  if not minimapBtn then
    SF.CreateMinimapButton()
  end
  if minimapBtn then minimapBtn:Show() end
end

function SF.CreateMinimapButton()
  if minimapBtn then return minimapBtn end
  if not Minimap then return nil end

  local btn = CreateFrame("Button", "StatForgeMinimapButton", Minimap)
  btn:SetSize(32, 32)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local overlay = btn:CreateTexture(nil, "OVERLAY")
  overlay:SetSize(54, 54)
  overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  overlay:SetPoint("TOPLEFT")

  local icon = btn:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", 0, 1)
  -- sword-ish bag icon fallback — classic interface texture
  icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
  btn.icon = icon

  local angle = (StatForgeDB and StatForgeDB.minimapAngle) or 220
  local function updatePos()
    local rad = math.rad(angle)
    local x = math.cos(rad) * 80
    local y = math.sin(rad) * 80
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
  end
  updatePos()

  btn:RegisterForDrag("LeftButton")
  btn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      cx, cy = cx / scale, cy / scale
      angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
      if StatForgeDB then StatForgeDB.minimapAngle = angle end
      updatePos()
    end)
  end)
  btn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)

  -- B13 (card t_4412b04b): RightButtonUp was registered while OnClick acted only
  -- on LeftButton — a control the player can click that does nothing, which reads
  -- as "the button is broken." Route taken: right-click now ACTS, opening the
  -- settings (Options) surface rather than leaving a second dead registration.
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      -- Options is the one live tab (UI.lua activeTab); this is not a menu build.
      SF.ShowMain("options")
      return
    end
    SF.ToggleMain()
  end)

  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Touchstone", C.accent[1], C.accent[2], C.accent[3])
    GameTooltip:AddLine("Left-click: open window", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: settings", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Drag: move button", 0.5, 0.5, 0.5)
    -- B12 (card t_4412b04b): this list named /sf and /statforge but omitted the
    -- canonical /touchstone and the /ts the player actually types.
    GameTooltip:AddLine("/touchstone  ·  /ts  ·  /up  ·  /sf", 0.5, 0.5, 0.5)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  minimapBtn = btn
  return btn
end

-- ---------------------------------------------------------------------------
-- The row model the two list tabs share (card t_4e5ad8a4).
--
-- A row's height is its own CONTENT's height, measured after the text is set,
-- and the next row starts at the previous row's BOTTOM. There is no fixed pitch,
-- because a verdict reason is a sentence rather than a label: "eligibility
-- unconfirmed (fail-closed): client returned false …" wraps to two or three
-- lines, and a pitch chosen for one line printed the third line over the next
-- item's name.
--
-- The page is the run of rows that FITS the viewport, measured the same way.
-- "12 rows" (Upgrades) and "13 rows" (Log) were only true while every row was
-- the same height; once a row grows, a fixed count either clips the last row or
-- draws the extra rows outside the panel, and nothing in this window clips a
-- child to its parent.
-- ---------------------------------------------------------------------------

--- How many rows from `offset` fit in `avail` units, and their stacked height.
--- `heights[i]` is row i's measured height; nil ends the list. The first row of
--- a page is always admitted, so one row taller than the viewport is still shown
--- (and readable by scrolling) instead of producing an empty page.
function SF.PageRows(heights, offset, avail)
  local first = math.max(1, (tonumber(offset) or 0) + 1)
  local count, used = 0, 0
  local limit = tonumber(avail) or 0
  local i = first
  while type(heights[i]) == "number" do
    local h = heights[i]
    if count > 0 and used + h > limit then break end
    used = used + h
    count = count + 1
    i = i + 1
  end
  return first, count, used
end

--- Place one stacked row `y` units below its parent's top, and return the y the
--- NEXT row starts at (this row's bottom).
function SF.StackRow(row, parent, y)
  y = y or 0
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
  row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -y)
  return y + (row:GetHeight() or 0)
end

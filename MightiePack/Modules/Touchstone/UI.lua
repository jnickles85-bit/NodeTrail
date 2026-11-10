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

function SF.UI_CreateButton(parent, text, width, height)
  local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
  btn:SetSize(width or 120, height or 28)
  applyBackdrop(btn, C.surfaceHover, C.border, 1, 1)
  btn:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
  local ht = btn:GetHighlightTexture()
  if ht then ht:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.12) end

  local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("CENTER")
  fs:SetText(text or "")
  fs:SetTextColor(C.text[1], C.text[2], C.text[3])
  btn.label = fs

  btn:SetScript("OnEnter", function(self)
    applyBackdrop(self, C.surfaceHover, C.accent, 1, 0.8)
    self.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
  end)
  btn:SetScript("OnLeave", function(self)
    if self._primary then
      applyBackdrop(self, C.accentDim, C.accent, 0.35, 1)
      self.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    elseif self._success then
      applyBackdrop(self, { 0.08, 0.35, 0.18 }, C.success, 1, 0.9)
      self.label:SetTextColor(C.success[1], C.success[2], C.success[3])
    else
      applyBackdrop(self, C.surfaceHover, C.border, 1, 1)
      self.label:SetTextColor(C.text[1], C.text[2], C.text[3])
    end
  end)

  function btn:SetPrimary(on)
    self._primary = on
    self._success = false
    if on then
      applyBackdrop(self, C.accentDim, C.accent, 0.35, 1)
      self.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    end
  end

  function btn:SetSuccess(on)
    self._success = on
    self._primary = false
    if on then
      applyBackdrop(self, { 0.08, 0.35, 0.18 }, C.success, 1, 0.9)
      self.label:SetTextColor(C.success[1], C.success[2], C.success[3])
    end
  end

  function btn:SetLabel(t)
    self.label:SetText(t)
  end

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
    if tid == id then
      applyBackdrop(btn, C.surfaceHover, C.accent, 1, 0.9)
      btn.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    else
      applyBackdrop(btn, C.bg, C.border, 0.6, 0.7)
      btn.label:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
    end
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
  applyBackdrop(f, C.bg, C.accentDim, 0.97, 0.85)
  restorePosition(f)

  -- title bar (drag handle)
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

  local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("LEFT", 16, 0)
  title:SetText(SF.Accent("Touchstone"))
  title:SetTextColor(C.accent[1], C.accent[2], C.accent[3])

  local subtitle = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  subtitle:SetPoint("LEFT", title, "RIGHT", 10, 0)
  -- B12 (card t_4412b04b): this used to read "Classic Hardcore · v…", which named
  -- a product scope the addon never had (it is not Hardcore-only). The ruling
  -- makes the scope plain: in-game Classic-era gear advice.
  subtitle:SetText("Classic-era item advisor  ·  v" .. SF.VERSION)
  subtitle:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])

  local close = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
  close:SetPoint("RIGHT", -4, 0)
  close:SetScript("OnClick", function() f:Hide() end)

  -- tab strip
  local tabStrip = CreateFrame("Frame", nil, f)
  tabStrip:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 12, -8)
  tabStrip:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", -12, -8)
  tabStrip:SetHeight(32)

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
    applyBackdrop(btn, C.bg, C.border, 0.6, 0.7)

    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER")
    fs:SetText(t.label)
    fs:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
    btn.label = fs

    btn:SetScript("OnClick", function() selectTab(t.id) end)
    tabButtons[t.id] = btn
  end

  -- content area
  contentFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
  contentFrame:SetPoint("TOPLEFT", tabStrip, "BOTTOMLEFT", 0, -8)
  contentFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
  applyBackdrop(contentFrame, C.surface, C.border, 0.6, 0.5)

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
  applyBackdrop(panel, C.surface, C.accent, 1, 0.6)

  local h = SF.UI_CreateLabel(panel, SF.Accent("Welcome to Touchstone"), "GameFontNormalLarge")
  h:SetPoint("TOP", 0, -24)
  h:SetJustifyH("CENTER")

  local body = SF.UI_CreateLabel(panel, "", "GameFontHighlight")
  body:SetPoint("TOP", h, "BOTTOM", 0, -20)
  body:SetWidth(460)
  body:SetJustifyH("LEFT")
  body:SetText(
    "Touchstone reads the gear you are holding and tells you, in the game, whether it beats what you wear.\n\n" ..
    "|cff66fcf11.|r  Hover a chest, weapon or armour piece in your bags to see the call.\n\n" ..
    "|cff66fcf12.|r  A green |cffffffffarrow|r marks an upgrade. An amber |cffffffffsquare|r marks a trade-off: better on some stats, worse on others.\n\n" ..
    "|cff66fcf13.|r  |cffffffff/ts|r opens this window; |cffffffff/ts help|r lists the commands."
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

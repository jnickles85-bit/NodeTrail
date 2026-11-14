if MightiePackTouchstoneSkip then return end
--- StatForge Options (Settings) tab.
---
--- Card t_adf556d6: the "Auto-export on logout" control is retired with the
--- logout auto-export itself. A checkbox that toggles a feature that no longer
--- exists is the same class of lie the card's AC-E is about, so it is removed
--- rather than left dangling. The minimap-button control stays -- it still does
--- something.
---
--- Card t_b7b5f60c (audit U1 §4 + B8). Two changes:
---   * Diagnostics gets a BUTTON here. The panel and the `/sf diag` / `/up diag`
---     chat commands are untouched — a tab is an ADDITIONAL surface, never the
---     removal of a working one;
---   * the tab BUILDS ONCE and re-binds. Previously every render made a fresh
---     title, checkbox, labels and About block; WoW never frees a frame, so the
---     Settings tab leaked its whole tree on every tab switch and bank
---     open/close (audit B8). The widgets now live on the persistent host and
---     the render only refreshes their state.

StatForge = StatForge or {}
local SF = StatForge
local C = SF.Colors

-- The host the tab last rendered into. Nothing reads it for behaviour; the layout
-- snapshot (SF.OptionsTabLayout) needs it because the regions live ON the host.
local currentHost

-- The slash handler is the writer. The checkboxes call it and then re-read,
-- so a click and `/up detail` cannot store two different shapes.
local function advisorSlash(msg)
  local list = rawget(_G, "SlashCmdList")
  local fn = type(list) == "table" and list.CHESTADVISOR or nil
  if type(fn) == "function" then fn(msg) end
end

local function classIdentity()
  local name, token = nil, nil
  if type(UnitClass) == "function" then
    name, token = UnitClass("player")
  end
  if type(name) ~= "string" or name == "" then name = "Unknown" end
  if type(token) ~= "string" then token = nil end
  local hybrid = false
  local verdict = rawget(_G, "Verdict")
  local orders = (type(verdict) == "table" and type(verdict.ORDERS) == "table" and token)
    and verdict.ORDERS[token] or nil
  if type(orders) == "table" then
    local n = 0
    for _ in pairs(orders) do n = n + 1 end
    hybrid = n > 1
  end
  return name, token, hybrid
end

local function recordedRole(token)
  local advisor = rawget(_G, "ChestAdvisor")
  if type(token) ~= "string" then return nil end
  if type(advisor) ~= "table" or type(advisor.roleFor) ~= "function" then return nil end
  local role = advisor.roleFor(token)
  if role == "melee" or role == "spell" then return role end
  return nil
end

local function currentDetail()
  local advisor = rawget(_G, "ChestAdvisor")
  local ui = type(advisor) == "table" and advisor.tooltipUI or nil
  if type(ui) == "table" and type(ui.detail) == "function" then
    local d = ui.detail()
    if d == "full" or d == "compact" or d == "upgrades" then return d end
  end
  return "full"
end

local function tooltipLineOn()
  local advisor = rawget(_G, "ChestAdvisor")
  local ui = type(advisor) == "table" and advisor.tooltipUI or nil
  if type(ui) == "table" and type(ui.enabled) == "function" then
    return ui.enabled() ~= false
  end
  return true
end

local function toastOn()
  local advisor = rawget(_G, "ChestAdvisor")
  if type(advisor) == "table" and type(advisor.toastState) == "function" then
    local state = advisor.toastState()
    if type(state) == "table" then return state.enabled ~= false end
  end
  return true
end

local function glyphsOn()
  local advisor = rawget(_G, "ChestAdvisor")
  if type(advisor) == "table" and type(advisor._glyphsOn) == "function" then
    return advisor._glyphsOn() == true
  end
  return false
end

local function syncShown(host)
  if not host then return end
  local detail = currentDetail()
  if host.detailFull then host.detailFull:SetChecked(detail == "full") end
  if host.detailCompact then host.detailCompact:SetChecked(detail == "compact") end
  if host.detailUpgrades then host.detailUpgrades:SetChecked(detail == "upgrades") end
  if host.tooltipCheck then host.tooltipCheck:SetChecked(tooltipLineOn()) end
  if host.toastCheck then host.toastCheck:SetChecked(toastOn()) end
  if host.glyphCheck then host.glyphCheck:SetChecked(glyphsOn()) end

  local name, token, hybrid = classIdentity()
  if host.classLabel then
    host.classLabel:SetText("Class: " .. name)
  end
  if host.roleNote then
    if hybrid then
      host.roleNote:SetText("Role selects the stat order. Leave it clear to use the spec.")
    else
      host.roleNote:SetText("This class has one stat order.")
    end
  end
  if host.roleRow then
    if hybrid then host.roleRow:Show() else host.roleRow:Hide() end
  end
  local role = recordedRole(token)
  if host.roleMelee then host.roleMelee:SetChecked(role == "melee") end
  if host.roleSpell then host.roleSpell:SetChecked(role == "spell") end
  if host.roleClear then host.roleClear:SetChecked(role == nil) end
end

local function labelledCheck(parent, name, text)
  -- Anchoring is the caller's: a checkbox in a FLOWED stack is placed by the
  -- block's position (card t_4e5ad8a4), and a checkbox beside another control is
  -- anchored to that control. A y baked in here is exactly the kind of fixed
  -- offset that put two controls on the same line.
  local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
  local label = SF.UI_CreateLabel(parent, text, "GameFontHighlight")
  label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cb.label = label
  return cb
end

-- Assigned below build(); build() calls it at the end, so the widgets exist by
-- the time it runs. A forward local keeps the flow ONE function that both the
-- build and every render go through.
local relayout

local function build(host)
  -- ---------------------------------------------------------------------
  -- Card t_4e5ad8a4 (defect 2): THE STACK FLOWS, and it scrolls.
  --
  -- The offsets this replaces (-24/-60/-94/-135/-152/-203/-258/-293/-309) were
  -- tuned to a 515-unit content area while the About block hung off the BOTTOM
  -- edge. Inside the unified window the body is smaller (441 units, measured on
  -- the owner's 2026-11-14 screenshot at window scale 1.00: the panel's interior
  -- spans 661 px at 1.5 px per unit), so the bottom-anchored block climbed into
  -- the fixed stack and printed the About paragraph over Role/Class/roleNote.
  -- The body's height is the WINDOW's business and has already changed twice, so
  -- nothing below is a y position: every block is anchored under the block above
  -- it, at that block's measured height (relayout()).
  --
  -- The content is taller than the body at every size this window has had (the
  -- stack above alone ends at ~369 and About needs 132; 501 > 441). A flow that
  -- simply grew would then draw its tail outside the panel, and nothing clips a
  -- child to its parent, so the flow lives on a scrolled content frame. The wheel
  -- moves the whole stack; the tab still opens at the top.
  local viewport = CreateFrame("Frame", "TouchstoneOptionsViewport", host)
  viewport:SetAllPoints(host)
  viewport:EnableMouseWheel(true)
  -- The content is TALLER than the body, so it has to be CLIPPED to it: nothing
  -- in this window clips a child to its parent by default, and without this the
  -- stack's tail would paint over the panel's border and the window around it —
  -- the very defect this card is about, moved from "over the text" to "over the
  -- chrome". Guarded because the API is not in every client this pack targets;
  -- on a client without it the content still scrolls, and the tail is drawn
  -- outside the panel while the stack is at the top (recorded, not hidden).
  if type(viewport.SetClipsChildren) == "function" then
    viewport:SetClipsChildren(true)
  end
  local content = CreateFrame("Frame", nil, viewport)
  content:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, 0)
  content:SetPoint("TOPRIGHT", viewport, "TOPRIGHT", 0, 0)
  host.viewport = viewport
  host.content = content
  host.scroll = 0

  local title = SF.UI_CreateLabel(content, "Options", "GameFontNormalLarge")
  title:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
  host.title = title

  local hideMini = StatForgeDB and StatForgeDB.minimapHide
  local cb1 = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
  cb1:SetChecked(not hideMini)
  local l1 = SF.UI_CreateLabel(content, "Show minimap button", "GameFontHighlight")
  l1:SetPoint("LEFT", cb1, "RIGHT", 4, 0)
  cb1:SetScript("OnClick", function(self)
    if not StatForgeDB then return end
    StatForgeDB.minimapHide = not self:GetChecked()
    SF.UpdateMinimapButton()
  end)
  host.minimapCheck = cb1

  -- Card t_b7b5f60c (audit U1 §4): diagnostics behind a BUTTON. The panel and
  -- the `/sf diag` / `/up diag` chat commands are unchanged — this is an
  -- additional surface, not a replacement, so the command path keeps working.
  local diagBtn = SF.UI_CreateButton(content, "Diagnostics", 160, 28)
  diagBtn:SetScript("OnClick", function() SF.ShowDiagnosticsPanel() end)
  local l2 = SF.UI_CreateLabel(content, "Copy this client's API report when a verdict looks wrong",
    "GameFontHighlight")
  l2:SetPoint("LEFT", diagBtn, "RIGHT", 10, 0)
  l2:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  host.diagButton = diagBtn

  -- Window scale. This slider and `/ts scale <0.5-1.5>` are the two controls;
  -- the number lives in the same StatForgeDB.ui.scale the window position uses.
  -- Card t_75261b9a: the mouse wheel is NOT one of them any more. The wheel is
  -- this client's camera zoom, and a window-level handler took it away whenever
  -- the panel was open, storing each stray scroll in StatForgeDB.ui.scale.
  -- The slider steps by 0.05. Applying the scale while the mouse is still down
  -- rescales the window under the cursor, so a small drag runs the value to the
  -- end of the track. A drag updates the label only; the scale is applied on
  -- mouse-up. A SetValue that is not a drag still applies immediately.
  local scaleLabel = SF.UI_CreateLabel(content, "Window scale", "GameFontHighlight")
  host.scaleLabel = scaleLabel

  local lo, hi = 0.5, 1.5
  if type(SF.WindowScaleBounds) == "function" then
    lo, hi = SF.WindowScaleBounds()
  end
  local SLIDER_STEP = 0.05
  local slider = CreateFrame("Slider", nil, content)
  slider:SetOrientation("HORIZONTAL")
  slider:SetSize(360, 20)
  slider:SetPoint("TOPLEFT", scaleLabel, "BOTTOMLEFT", 0, -3)
  slider:SetMinMaxValues(lo, hi)
  slider:SetValueStep(SLIDER_STEP)
  if type(slider.SetObeyStepOnDrag) == "function" then
    slider:SetObeyStepOnDrag(true)
  end
  local track = slider:CreateTexture(nil, "BACKGROUND")
  if type(track.SetColorTexture) == "function" then
    track:SetColorTexture(0.28, 0.24, 0.16, 0.95)
  end
  track:SetPoint("LEFT", slider, "LEFT", 0, 0)
  track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
  track:SetHeight(6)
  local thumb = slider:CreateTexture(nil, "OVERLAY")
  thumb:SetSize(20, 20)
  local painted = false
  if type(thumb.SetTexture) == "function" then
    painted = thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  end
  if not painted and type(thumb.SetColorTexture) == "function" then
    thumb:SetColorTexture(0.9, 0.78, 0.35, 1)
  end
  if type(slider.SetThumbTexture) == "function" then
    slider:SetThumbTexture(thumb)
  end
  local scaleValue = SF.UI_CreateLabel(content, "", "GameFontHighlight")
  scaleValue:SetPoint("LEFT", slider, "RIGHT", 12, 0)
  host.scaleValue = scaleValue
  host.scaleSlider = slider

  local function showScale(n)
    scaleValue:SetText(string.format("%.2f", n))
  end
  -- Snap to the slider step in hundredths so 0.05 stays exact.
  local function snapScale(value)
    if type(value) ~= "number" then return nil end
    local hundredths = math.floor(value * 100 + 0.5)
    return math.floor(hundredths / 5 + 0.5) * 5 / 100
  end
  local function applyScale(value)
    local stepped = snapScale(value)
    if type(stepped) ~= "number" then return end
    local applied = SF.SetWindowScale(stepped)
    local shown = type(applied) == "number" and applied or stepped
    showScale(shown)
  end
  local function dragInProgress(self)
    if self._dragging then return true end
    local mouseDown = rawget(_G, "IsMouseButtonDown")
    if type(mouseDown) ~= "function" then return false end
    local ok, down = pcall(mouseDown, "LeftButton")
    return ok and down or false
  end

  slider:SetScript("OnMouseDown", function(self)
    self._dragging = true
  end)
  slider:SetScript("OnMouseUp", function(self)
    self._dragging = false
    if type(self._pending) == "number" then
      local pending = self._pending
      self._pending = nil
      applyScale(pending)
    end
  end)
  slider:SetScript("OnValueChanged", function(self, value)
    if self._silent then return end
    if dragInProgress(self) then
      self._pending = snapScale(value) or value
      showScale(self._pending)
      return
    end
    applyScale(value)
  end)

  -- "What Touchstone shows". Every control writes through the slash handler
  -- that already owns the ChestAdvisorDB key, then syncShown re-reads it.
  local shows = SF.UI_CreateLabel(content, "What Touchstone shows", "GameFontNormal")
  shows:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
  host.showsHeader = shows

  local detailLabel = SF.UI_CreateLabel(content, "Tooltip detail", "GameFontHighlight")
  host.detailLabel = detailLabel

  local detailFull = labelledCheck(content, "TouchstoneOptDetailFull", "Full")
  local detailCompact = labelledCheck(content, "TouchstoneOptDetailCompact", "Compact")
  local detailUpgrades = labelledCheck(content, "TouchstoneOptDetailUpgrades", "Upgrades only")
  -- One line of three: the row's first control is the block the flow places, and
  -- its neighbours hang off it, so they cannot separate when the stack moves.
  detailCompact:SetPoint("TOPLEFT", detailFull, "TOPLEFT", 134, 0)
  detailUpgrades:SetPoint("TOPLEFT", detailFull, "TOPLEFT", 304, 0)
  detailFull:SetScript("OnClick", function()
    advisorSlash("detail full")
    syncShown(host)
  end)
  detailCompact:SetScript("OnClick", function()
    advisorSlash("detail compact")
    syncShown(host)
  end)
  detailUpgrades:SetScript("OnClick", function()
    advisorSlash("detail upgrades")
    syncShown(host)
  end)
  host.detailFull = detailFull
  host.detailCompact = detailCompact
  host.detailUpgrades = detailUpgrades

  local detailHint = SF.UI_CreateLabel(content,
    "Full always includes the numbers. Compact shows them while Shift is held. Upgrades only hides not-an-upgrade lines.",
    "GameFontHighlight")
  detailHint:SetWidth(820)
  detailHint:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  host.detailHint = detailHint

  local tooltipCheck = labelledCheck(content, "TouchstoneOptTooltip", "Tooltip line")
  tooltipCheck:SetScript("OnClick", function(self)
    advisorSlash(self:GetChecked() and "tooltip on" or "tooltip off")
    syncShown(host)
  end)
  host.tooltipCheck = tooltipCheck

  local toastCheck = labelledCheck(content, "TouchstoneOptToast", "Upgrade toast")
  toastCheck:SetPoint("TOPLEFT", tooltipCheck, "TOPLEFT", 204, 0)
  toastCheck:SetScript("OnClick", function(self)
    advisorSlash(self:GetChecked() and "toast on" or "toast off")
    syncShown(host)
  end)
  host.toastCheck = toastCheck

  local glyphCheck = labelledCheck(content, "TouchstoneOptGlyphs",
    "Colorblind-safe markers (+ upgrade, ^ trade-off)")
  glyphCheck:SetPoint("TOPLEFT", tooltipCheck, "TOPLEFT", 404, 0)
  glyphCheck:SetScript("OnClick", function(self)
    advisorSlash(self:GetChecked() and "glyphs on" or "glyphs off")
    syncShown(host)
  end)
  host.glyphCheck = glyphCheck

  local resetBtn = SF.UI_CreateButton(content, "Reset to defaults", 180, 28)
  -- Card t_4ddeae90 (defect 2): ONE command, ONE chat line. This used to fire
  -- the four settings subcommands in a row, and the success echo prints once
  -- per call, so a single click produced four lines ("tooltip detail full",
  -- "tooltip on", "toast on", "marker glyphs off") where a hand-toggled setting
  -- prints one. `/up reset` restores the same four defaults through the SAME
  -- four writers (so each key still has exactly one owner) and echoes a single
  -- summary. No echo-suppression flag on the shared path: a quiet mode that
  -- leaked would silently kill the confirmation on the individual toggles,
  -- which is the regression this fix most invites.
  resetBtn:SetScript("OnClick", function()
    advisorSlash("reset")
    syncShown(host)
  end)
  local resetHint = SF.UI_CreateLabel(content, "Tooltip, toast, and marker glyphs. Also clears a chosen Gear-for spec (back to Auto). Does not clear /up role or the log.",
    "GameFontHighlight")
  resetHint:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)
  resetHint:SetPoint("RIGHT", content, "RIGHT", -16, 0)
  resetHint:SetJustifyH("LEFT")
  if type(resetHint.SetJustifyV) == "function" then
    resetHint:SetJustifyV("MIDDLE")
  end
  if type(resetHint.SetWordWrap) == "function" then
    resetHint:SetWordWrap(true)
  end
  resetHint:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  host.resetButton = resetBtn

  local roleHeader = SF.UI_CreateLabel(content, "Role", "GameFontNormal")
  roleHeader:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
  host.roleHeader = roleHeader

  local classLabel = SF.UI_CreateLabel(content, "Class:", "GameFontHighlight")
  host.classLabel = classLabel
  -- The reset control and class label are unnamed, so tests reach them here.
  -- Named checkboxes and the role row register themselves in CreateFrame.
  SF.optionControls = {
    reset = resetBtn,
    classLabel = classLabel,
  }

  local roleNote = SF.UI_CreateLabel(content, "", "GameFontHighlight")
  roleNote:SetWidth(820)
  roleNote:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  host.roleNote = roleNote

  local roleRow = CreateFrame("Frame", "TouchstoneOptRoleRow", content)
  roleRow:SetSize(640, 28)
  local roleMelee = labelledCheck(roleRow, "TouchstoneOptRoleMelee", "Melee")
  roleMelee:SetPoint("TOPLEFT", roleRow, "TOPLEFT", 0, 0)
  local roleSpell = labelledCheck(roleRow, "TouchstoneOptRoleSpell", "Spell")
  roleSpell:SetPoint("TOPLEFT", roleMelee, "TOPLEFT", 160, 0)
  local roleClear = labelledCheck(roleRow, "TouchstoneOptRoleClear", "Clear")
  roleClear:SetPoint("TOPLEFT", roleMelee, "TOPLEFT", 320, 0)
  roleMelee:SetScript("OnClick", function()
    advisorSlash("role melee")
    syncShown(host)
  end)
  roleSpell:SetScript("OnClick", function()
    advisorSlash("role spell")
    syncShown(host)
  end)
  roleClear:SetScript("OnClick", function()
    advisorSlash("role clear")
    syncShown(host)
  end)
  host.roleRow = roleRow
  host.roleMelee = roleMelee
  host.roleSpell = roleSpell
  host.roleClear = roleClear

  -- Card t_4e5ad8a4 (defect 2): the About block FLOWS under the role row. It used
  -- to be anchored to the content frame's BOTTOM edge (t_4ddeae90 did that
  -- because nobody could measure the client's rendered line height), which is a
  -- bet on the body's height: at 515 units it cleared the role row by 10, and in
  -- the unified window's 441-unit body it climbed 74 units into Role/Class.
  -- The measured metrics on the owner's screenshot are 12 units per
  -- GameFontHighlight line, so the block is 11 lines = 132 and it needs the
  -- bottom of whatever is above it, not the bottom of the panel.
  local about = SF.UI_CreateLabel(content, "", "GameFontHighlight")
  about:SetWidth(840)
  about:SetJustifyH("LEFT")
  about:SetText(
    SF.Accent("About") .. "\n\n" ..
    (function()
      local packVer
      local pkg = rawget(_G, "MightiePack")
      if type(pkg) == "table" and type(pkg.PackVersion) == "function" then
        local ok, v = pcall(pkg.PackVersion)
        if ok and type(v) == "string" and v ~= "" then packVer = v end
      end
      local pack = packVer and ("MightiePack v" .. packVer) or "MightiePack"
      return pack .. "  ·  Touchstone module v" .. SF.VERSION .. "  ·  Classic Era item advisor\n"
    end)() ..
    "Hover a piece of gear in your bags. A green arrow marks an upgrade;\n" ..
    "an amber square marks a trade-off (better on some stats, worse on others).\n" ..
    "On the character sheet, the green arrow means a bag item is an upgrade for that slot.\n" ..
    "The Upgrades tab lists every item the advisor has judged; the Log tab\n" ..
    "shows the times you equipped an item it called not an upgrade.\n" ..
    -- B12 (card t_4412b04b): the command list named /sf and the retired
    -- /statforge but omitted the canonical /touchstone and the /ts the player
    -- types. Both command surfaces (here and the minimap tooltip) now agree.
    "Commands:  |cffffffff/touchstone|r  ·  |cffffffff/ts|r  ·  |cffffffff/sf|r" ..
    "  ·  |cffffffff/up|r  ·  |cffffffff/ts help|r  ·  |cffffffff/up role|r  ·  |cffffffff/up log|r  ·  |cffffffff/up diag|r\n\n" ..
    "Tip: run |cffffffff/sf diag|r when a verdict looks wrong; it reports this client's API surface."
  )
  about:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  host.about = about

  -- The stack, in draw order. Each entry is { region, x, gap, h }:
  --   region — the block's top-left owner (a composite block owns its first row);
  --   x      — the block's left edge, in content units (a COLUMN, not a layout);
  --   gap    — the space above it;
  --   h      — optional, the block's height when it is more than one region tall.
  -- There is no y anywhere: relayout() derives it as the sum of the gaps and the
  -- measured heights above. Adding a control means adding a line here.
  host.blocks = {
    { region = title,       x = 20, gap = 4 },
    { region = cb1,         x = 16, gap = 8 },
    { region = diagBtn,     x = 16, gap = 10 },
    { region = scaleLabel,  x = 20, gap = 10,
      h = function() return (scaleLabel:GetHeight() or 0) + 3 + (slider:GetHeight() or 0) end },
    { region = shows,       x = 20, gap = 10 },
    { region = detailLabel, x = 20, gap = 6 },
    { region = detailFull,  x = 16, gap = 4 },
    { region = detailHint,  x = 20, gap = 4 },
    { region = tooltipCheck, x = 16, gap = 6 },
    { region = resetBtn,    x = 16, gap = 10,
      h = function() return math.max(resetBtn:GetHeight() or 0, resetHint:GetHeight() or 0) end },
    { region = roleHeader,  x = 20, gap = 10 },
    { region = classLabel,  x = 20, gap = 4 },
    { region = roleNote,    x = 20, gap = 4 },
    { region = roleRow,     x = 16, gap = 4 },
    { region = about,       x = 20, gap = 8 },
  }

  -- The wheel moves the stack. It reads nothing else and stores nothing: the
  -- scale slider and `/ts scale` remain the only scale controls (card
  -- t_75261b9a), and this handler exists because the content is taller than the
  -- body, not because the wheel has a new meaning.
  viewport:SetScript("OnMouseWheel", function(_, delta)
    -- Wheel down (the client's -1) moves the stack UP: same sign convention as
    -- the two list tabs' scrollBy(-(delta or 0)).
    host.scroll = (host.scroll or 0) - (delta or 0) * 24
    relayout(host)
  end)

  host.__optionsBuilt = true
  relayout(host)
end

-- Card t_4e5ad8a4: the flow. Every block is placed under the block above it, at
-- that block's MEASURED height, so:
--   * no absolute y offset exists to be wrong when the body changes size;
--   * a label that grows a line (a two-line class name, a wrapped hint) pushes
--     everything under it down instead of being overprinted;
--   * the About block starts where the role row ends, so it can never climb into
--     Role/Class -- the defect this card is about.
-- The content frame's height is the flow's own total; the wheel scrolls it.
relayout = function(host)
  local content = type(host) == "table" and host.content or nil
  if type(content) ~= "table" or type(host.blocks) ~= "table" then return end
  local y = 0
  for _, b in ipairs(host.blocks) do
    local r = b.region
    -- A hidden block takes no room at all: the role row is hidden for a class
    -- with one stat order, and a 28-unit hole where a control used to be is the
    -- same class of bug as a fixed offset.
    local shown = (type(r) ~= "table") or (type(r.IsShown) ~= "function") or r:IsShown()
    if type(r) == "table" and shown then
      y = y + (b.gap or 0)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", content, "TOPLEFT", b.x or 20, -y)
      local h
      if type(b.h) == "function" then h = b.h() else h = r:GetHeight() end
      if type(h) ~= "number" then h = 0 end
      y = y + h
    end
  end
  content:SetHeight(math.max(y, 1))

  -- Clamp the scroll to what the stack actually needs: a short body scrolls, a
  -- tall one does not, and neither can be scrolled into blank space.
  local viewport = host.viewport
  local overflow = 0
  if type(viewport) == "table" then
    overflow = math.max(0, (content:GetHeight() or 0) - (viewport:GetHeight() or 0))
  end
  local v = host.scroll or 0
  if v < 0 then v = 0 end
  if v > overflow then v = overflow end
  host.scroll = v
  host.scrollMax = overflow
  -- Re-anchor the content: it hangs off the viewport's top, moved UP by v.
  content:ClearAllPoints()
  content:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, v)
  content:SetPoint("TOPRIGHT", viewport, "TOPRIGHT", 0, v)
end

-- Read-only snapshot for the layout spec, the same convention the list tabs use
-- (SF.UpgradesTabState / SF.LogTabState): the tab reports the very regions it
-- placed, and re-derives nothing.
function SF.OptionsTabLayout()
  local host = currentHost
  if type(host) ~= "table" then return nil end
  return {
    host = host,
    content = host.content,
    viewport = host.viewport,
    blocks = host.blocks,
    scroll = host.scroll or 0,
    scrollMax = host.scrollMax or 0,
  }
end

-- Repopulate: refresh the one control whose state can change while the window
-- has been closed. Nothing is created here on a revisit (B8).
local function render(host)
  if not host.__optionsBuilt then build(host) end
  currentHost = host
  local hideMini = StatForgeDB and StatForgeDB.minimapHide
  if host.minimapCheck then host.minimapCheck:SetChecked(not hideMini) end
  if host.scaleSlider and type(SF.GetWindowScale) == "function" then
    host.scaleSlider._silent = true
    host.scaleSlider:SetValue(SF.GetWindowScale())
    host.scaleSlider._silent = false
    if host.scaleValue then
      host.scaleValue:SetText(string.format("%.2f", SF.GetWindowScale()))
    end
  end
  syncShown(host)
  -- syncShown rewrites the class line and the role note, and either can wrap to a
  -- different number of lines. Re-flow AFTER the text, every time (card
  -- t_4e5ad8a4): a stack laid out before the text is a stack laid out for the
  -- wrong text.
  relayout(host)
end

local function release()
end

SF.RegisterTab("options", render, release)

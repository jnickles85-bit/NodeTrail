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

local function labelledCheck(parent, name, text, x, y)
  local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", x, y)
  local label = SF.UI_CreateLabel(parent, text, "GameFontHighlight")
  label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cb.label = label
  return cb
end

local function build(host)
  -- ---------------------------------------------------------------------
  -- Card t_4ddeae90 (defect 1): the vertical rhythm below is COMPRESSED.
  -- The old offsets (18/56/96/140/200/226/248/278/304/344/392/416, gaps of
  -- 8-24) put the About block at y -494 in a 515-unit content area, and its
  -- 11 rendered lines (11 x 12 -- GameFontHighlight is FRIZQT__.TTF height 12
  -- with spacing 0 in this client) need 132, so the block ended at 626: 111
  -- units past the frame and nothing clips it. Every control is still here,
  -- in the same order and at the same x; only the y offsets and the gaps
  -- moved. Budget: 432 of the 515 units are widget height (About included),
  -- which leaves 83 for the whole stack's spacing -- so the gaps run 3-7
  -- instead of 8-24.
  local title = SF.UI_CreateLabel(host, "Options", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 20, -4)
  title:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
  host.title = title

  local hideMini = StatForgeDB and StatForgeDB.minimapHide
  local cb1 = CreateFrame("CheckButton", nil, host, "UICheckButtonTemplate")
  cb1:SetPoint("TOPLEFT", 16, -24)
  cb1:SetChecked(not hideMini)
  local l1 = SF.UI_CreateLabel(host, "Show minimap button", "GameFontHighlight")
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
  local diagBtn = SF.UI_CreateButton(host, "Diagnostics", 160, 28)
  diagBtn:SetPoint("TOPLEFT", 16, -60)
  diagBtn:SetScript("OnClick", function() SF.ShowDiagnosticsPanel() end)
  local l2 = SF.UI_CreateLabel(host, "Copy this client's API report when a verdict looks wrong",
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
  local scaleLabel = SF.UI_CreateLabel(host, "Window scale", "GameFontHighlight")
  scaleLabel:SetPoint("TOPLEFT", 20, -94)
  host.scaleLabel = scaleLabel

  local lo, hi = 0.5, 1.5
  if type(SF.WindowScaleBounds) == "function" then
    lo, hi = SF.WindowScaleBounds()
  end
  local SLIDER_STEP = 0.05
  local slider = CreateFrame("Slider", nil, host)
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
  local scaleValue = SF.UI_CreateLabel(host, "", "GameFontHighlight")
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
  local shows = SF.UI_CreateLabel(host, "What Touchstone shows", "GameFontNormal")
  shows:SetPoint("TOPLEFT", 20, -135)
  shows:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
  host.showsHeader = shows

  local detailLabel = SF.UI_CreateLabel(host, "Tooltip detail", "GameFontHighlight")
  detailLabel:SetPoint("TOPLEFT", 20, -152)
  host.detailLabel = detailLabel

  local detailFull = labelledCheck(host, "TouchstoneOptDetailFull", "Full", 16, -167)
  local detailCompact = labelledCheck(host, "TouchstoneOptDetailCompact", "Compact", 150, -167)
  local detailUpgrades = labelledCheck(host, "TouchstoneOptDetailUpgrades", "Upgrades only", 320, -167)
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

  local detailHint = SF.UI_CreateLabel(host,
    "Full always includes the numbers. Compact shows them while Shift is held. Upgrades only hides not-an-upgrade lines.",
    "GameFontHighlight")
  detailHint:SetPoint("TOPLEFT", 20, -203)
  detailHint:SetWidth(820)
  detailHint:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  host.detailHint = detailHint

  local tooltipCheck = labelledCheck(host, "TouchstoneOptTooltip", "Tooltip line", 16, -220)
  tooltipCheck:SetScript("OnClick", function(self)
    advisorSlash(self:GetChecked() and "tooltip on" or "tooltip off")
    syncShown(host)
  end)
  host.tooltipCheck = tooltipCheck

  local toastCheck = labelledCheck(host, "TouchstoneOptToast", "Upgrade toast", 220, -220)
  toastCheck:SetScript("OnClick", function(self)
    advisorSlash(self:GetChecked() and "toast on" or "toast off")
    syncShown(host)
  end)
  host.toastCheck = toastCheck

  local glyphCheck = labelledCheck(host, "TouchstoneOptGlyphs",
    "Colorblind-safe markers (+ upgrade, ^ trade-off)", 420, -220)
  glyphCheck:SetScript("OnClick", function(self)
    advisorSlash(self:GetChecked() and "glyphs on" or "glyphs off")
    syncShown(host)
  end)
  host.glyphCheck = glyphCheck

  local resetBtn = SF.UI_CreateButton(host, "Reset to defaults", 180, 28)
  resetBtn:SetPoint("TOPLEFT", 16, -258)
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
  local resetHint = SF.UI_CreateLabel(host, "Tooltip, toast, and marker glyphs. Does not clear role or the log.",
    "GameFontHighlight")
  resetHint:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)
  resetHint:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  host.resetButton = resetBtn

  local roleHeader = SF.UI_CreateLabel(host, "Role", "GameFontNormal")
  roleHeader:SetPoint("TOPLEFT", 20, -293)
  roleHeader:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
  host.roleHeader = roleHeader

  local classLabel = SF.UI_CreateLabel(host, "Class:", "GameFontHighlight")
  classLabel:SetPoint("TOPLEFT", 20, -309)
  host.classLabel = classLabel
  -- The reset control and class label are unnamed, so tests reach them here.
  -- Named checkboxes and the role row register themselves in CreateFrame.
  SF.optionControls = {
    reset = resetBtn,
    classLabel = classLabel,
  }

  local roleNote = SF.UI_CreateLabel(host, "", "GameFontHighlight")
  roleNote:SetPoint("TOPLEFT", classLabel, "BOTTOMLEFT", 0, -4)
  roleNote:SetWidth(820)
  roleNote:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  host.roleNote = roleNote

  local roleRow = CreateFrame("Frame", "TouchstoneOptRoleRow", host)
  roleRow:SetSize(640, 28)
  roleRow:SetPoint("TOPLEFT", roleNote, "BOTTOMLEFT", -4, -4)
  local roleMelee = labelledCheck(roleRow, "TouchstoneOptRoleMelee", "Melee", 0, 0)
  local roleSpell = labelledCheck(roleRow, "TouchstoneOptRoleSpell", "Spell", 160, 0)
  local roleClear = labelledCheck(roleRow, "TouchstoneOptRoleClear", "Clear", 320, 0)
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

  -- Card t_4ddeae90 (defect 1): the About block is anchored to the content
  -- frame's BOTTOM edge, not to the role row above it. It used to chain off
  -- roleRow's BOTTOM (-18, y -494); its 11 rendered lines need 132 units, so
  -- it ended 111 units below the 515-unit content frame and -- with no clip and
  -- no scroll anywhere in this tab -- the tail (/up diag and the Tip line) was
  -- drawn over the panel's border in open space.
  --
  -- Two things fix it. The stack above is compressed (see build()'s header),
  -- which is where the room came from; and the block's own bottom is now
  -- DECLARED (515 - 4 = 511) instead of "wherever the stack above happens to
  -- end". The audit could not measure the client's rendered line height, so a
  -- top-anchored fix would be only as safe as that guess -- a bottom anchor
  -- cannot fall outside the panel at any line height. With the evidence-based
  -- metrics (GameFontHighlight = FRIZQT__.TTF height 12, spacing 0) the stack
  -- above ends at 369, leaving 10 units of clearance to the role row and 6 to
  -- the bottom of its 32-tall checkboxes.
  local about = SF.UI_CreateLabel(host, "", "GameFontHighlight")
  about:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 20, 4)
  about:SetWidth(840)
  about:SetJustifyH("LEFT")
  about:SetText(
    SF.Accent("About") .. "\n\n" ..
    "Touchstone v" .. SF.VERSION .. "  ·  Classic Era item advisor\n" ..
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

  host.__optionsBuilt = true
end

-- Repopulate: refresh the one control whose state can change while the window
-- has been closed. Nothing is created here on a revisit (B8).
local function render(host)
  if not host.__optionsBuilt then build(host) end
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
end

local function release()
end

SF.RegisterTab("options", render, release)

-- MightiePack — Pack Settings (card t_2d2c37b0, the reshape and design pass).
--
-- This panel is the window's second tab and, in the client, the AddOns >
-- MightiePack canvas. It used to answer for three modules: Touchstone, and
-- NodeTrail's skinning / auto-refresh / farming-circle sub-options, plus the
-- Alchemy recipe scan. NodeTrail is its own addon again (card t_75309c97), and
-- the rows that answered for it were left in place — unreachable, because no
-- module builds them — until this card. They are gone now, with their helpers
-- (ntRecipes, applySkinning, applySkinRoute, skinRouteNote, lastModuleWidget,
-- lastAlchemyWidget, syncRecipesBlock): dead code that still reads a store the
-- pack no longer owns is a trap for the next reader, not "leftover polish".
--
-- What is left is the pack's own surface, in the pack's own voice:
--
--   a one-line subtitle      what this tab is for
--   MODULES card             one row per module (data-driven from pkg.modules),
--                            a status word per row, and Touchstone's "Gear for"
--                            as an indented sub-option of its own row
--   FEEDBACK                 the two popups the pack already had (no upload;
--                            the player copies and pastes)
--   footer                   version, interface, and the one command that
--                            prints a diagnostic paste
--
-- Every colour, font, offset and texture here is a token from
-- MightiePack/Theme.lua (tests/theme_tokens_spec.lua holds that line).

local _, pkg = ...

local T = pkg.Theme
if type(T) ~= "table" then
  error("MightiePack/Options.lua needs MightiePack/Theme.lua loaded first", 0)
end
local C = T

local panel = CreateFrame("Frame", "MightiePackOptionsPanel")
panel.name = "MightiePack"
pkg.optionsPanel = panel

-- BORN HIDDEN (card t_07f778ca, PART A3). The client makes every CreateFrame
-- frame shown, and this one used to stay that way: a DIALOG frame over the
-- UIParent for the whole session, painting nothing until it was built — which is
-- why it was never seen, and why it was still there, over whatever tab was
-- active, when the strata and input defects were born.
--
-- Three surfaces own it, and each says so explicitly: the Settings canvas
-- (Blizzard shows a canvas category's frame when the category is opened), the
-- window's Pack Settings tab (Window.AttachSettings shows it on every
-- activation), and nothing else. An unowned panel must not paint.
if type(panel.Hide) == "function" then pcall(panel.Hide, panel) end

local boxes = {}
pkg.optionsBoxes = boxes

-- ── Reading the client ────────────────────────────────────────────────────
local function call(obj, name, ...)
  local f = type(obj) == "table" and obj[name]
  if type(f) ~= "function" then return false end
  local ok, r = pcall(f, obj, ...)
  if not ok then return false end
  return true, r
end

local function playerClassToken()
  if type(UnitClass) ~= "function" then return nil end
  local ok, _, tok = pcall(UnitClass, "player")
  if ok and type(tok) == "string" then return tok end
  return nil
end

local function talentSpecName()
  if not (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
      and C_SpecializationInfo.GetSpecializationInfo) then
    return nil
  end
  local ok, idx = pcall(C_SpecializationInfo.GetSpecialization)
  if not ok or type(idx) ~= "number" or idx == 0 then return nil end
  local ok2, _, name = pcall(C_SpecializationInfo.GetSpecializationInfo, idx)
  if ok2 and type(name) == "string" and name ~= "" then return name end
  return nil
end

-- ── "Gear for": the one sub-option the pack still has ─────────────────────
local function gearForChoices()
  local talent = talentSpecName()
  local autoLabel = talent and ("Auto (talents: " .. talent .. ")") or "Auto (talents)"
  local out = { { key = nil, label = autoLabel } }
  if type(ChestAdvisor) == "table" and type(ChestAdvisor.specsFor) == "function" then
    local list = ChestAdvisor.specsFor(playerClassToken())
    if type(list) == "table" then
      for _, e in ipairs(list) do
        out[#out + 1] = { key = e.key, label = e.name }
      end
    end
  end
  return out
end

local function currentGearForKey()
  if type(ChestAdvisor) == "table" and type(ChestAdvisor.gearForKey) == "function" then
    local ok, key = pcall(ChestAdvisor.gearForKey)
    if ok then return key end
  end
  return nil
end

local function applyGearFor(key)
  if type(ChestAdvisor) == "table" and type(ChestAdvisor.setGearFor) == "function" then
    pcall(ChestAdvisor.setGearFor, key)
  end
end

local function gearForLabelFor(key)
  for _, c in ipairs(gearForChoices()) do
    if (c.key == nil and key == nil) or (c.key ~= nil and c.key == key) then
      return c.label
    end
  end
  return "Auto (talents)"
end

local function refreshGearForButton()
  local btn = boxes.GearFor
  if not btn or type(btn.SetText) ~= "function" then return end
  btn:SetText(gearForLabelFor(currentGearForKey()))
end

local function cycleGearFor()
  local choices = gearForChoices()
  if #choices == 0 then return end
  local want = currentGearForKey()
  local idx = 1
  for i, c in ipairs(choices) do
    if (c.key == nil and want == nil) or (c.key ~= nil and c.key == want) then
      idx = i
      break
    end
  end
  local nxt = choices[(idx % #choices) + 1]
  applyGearFor(nxt and nxt.key or nil)
  refreshGearForButton()
end

local function touchstoneOn()
  if boxes.Touchstone and type(boxes.Touchstone.GetChecked) == "function" then
    return boxes.Touchstone:GetChecked() and true or false
  end
  if type(pkg.IsModuleEnabled) == "function" then
    local ok, on = pcall(pkg.IsModuleEnabled, "Touchstone")
    if ok then return on == true end
  end
  return false
end

-- ── The panel's own furniture, built once ─────────────────────────────────
local function label(parent, fontToken, colorToken, text)
  if type(C) ~= "table" or type(C.Text) ~= "function" then return nil end
  return C.Text(parent, fontToken, colorToken, text)
end

local function rule(parent, anchor)
  if type(C) ~= "table" or type(C.Rule) ~= "function" then return nil end
  local r = C.Rule(parent)
  if type(r) == "table" then
    call(r, "SetPoint", "TOPLEFT", anchor, "BOTTOMLEFT", 0, -T.space.sm)
    call(r, "SetPoint", "TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -T.space.sm)
  end
  return r
end

-- The panel is hosted by the window's settings tab (SetAllPoints) and by the
-- Settings canvas; both give it its size, so the furniture anchors to the panel
-- rather than to a fixed width.
local subtitle = label(panel, "hint", "textMuted",
  "Touchstone is the pack's product. Turn a module on or off here.")
if type(subtitle) == "table" then
  call(subtitle, "SetPoint", "TOPLEFT", panel, "TOPLEFT", 0, 0)
  call(subtitle, "SetPoint", "RIGHT", panel, "RIGHT", 0, 0)
  call(subtitle, "SetJustifyH", "LEFT")
end

-- ── MODULES: one card, one row per module ─────────────────────────────────
local function moduleList()
  local out = {}
  for _, name in ipairs(pkg.moduleOrder or {}) do
    if pkg.modules and pkg.modules[name] then out[#out + 1] = name end
  end
  return out
end

local moduleCard, moduleHeading
local stateWords = {}

--- Lay the card out for the rows it has right now. Called from the build, so a
--- module turned on/off (which adds or removes the "Gear for" sub-row) resizes
--- the card instead of leaving a hole.
local function layoutModuleCard()
  if type(moduleCard) ~= "table" then return end
  local defs = moduleList()
  local subRows = touchstoneOn() and 1 or 0
  local pad = T.space.md
  local headingH = T.size.rowPitch
  local height = pad + headingH + (#defs + subRows) * T.size.rowPitch + pad
  call(moduleCard, "SetHeight", height)
  if type(moduleHeading) == "table" then
    call(moduleHeading, "SetPoint", "TOPLEFT", moduleCard, "TOPLEFT", pad, -pad)
  end
end

local function buildModuleCard()
  if type(moduleCard) ~= "table" then
    moduleCard = C.Panel(panel, { bg = "panelBg", edge = "hairline" })
    if type(moduleCard) ~= "table" then return end
    call(moduleCard, "SetPoint", "TOPLEFT", subtitle, "BOTTOMLEFT", 0, -T.space.md)
    call(moduleCard, "SetPoint", "TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    moduleHeading = label(moduleCard, "small", "textDim", "MODULES")
  end
  call(moduleCard, "Show")
  layoutModuleCard()
end

local function buildModuleRows()
  if type(moduleCard) ~= "table" then return end
  local pad = T.space.md
  local y = pad + T.size.rowPitch
  for _, name in ipairs(moduleList()) do
    local def = pkg.modules and pkg.modules[name]
    local cb = boxes[name]
    if not cb then
      cb = CreateFrame("CheckButton", nil, moduleCard, "UICheckButtonTemplate")
      if type(cb) == "table" then
        local text
        if cb.Text or cb.text then
          text = cb.Text or cb.text
        else
          text = label(moduleCard, "body", "text")
          if type(text) == "table" then call(text, "SetPoint", "LEFT", cb, "RIGHT", T.space.xs, 0) end
        end
        local labelText = (def and def.title) or name
        if def and def.stub then labelText = labelText .. " (coming soon)" end
        if type(text) == "table" then call(text, "SetText", labelText) end

        -- The state word: the row says what it does RIGHT NOW, in words, not
        -- only by the box being ticked. "off" is dim, "on" is the pack's text
        -- colour — no green/red here, because a module being off is a choice,
        -- not a warning.
        local word = label(moduleCard, "small", "textDim", "")
        if type(word) == "table" then
          call(word, "SetPoint", "RIGHT", moduleCard, "RIGHT", -pad, 0)
          stateWords[name] = word
        end

        if not (def and def.stub) then
          call(cb, "SetScript", "OnClick", function(self)
            local on = self:GetChecked() and true or false
            if on then
              pkg.SetModuleEnabled(name, true)
              pkg.EnableModules()
              -- A module can refuse to run (Touchstone while the standalone
              -- addon folder is installed). Its Enable() has already printed
              -- why; "enabled." here would be a lie.
              if not (def and def.inert) then
                pkg.Print(((def and def.title) or name) .. " enabled.")
              end
              pkg.SyncOptionsRows()
            else
              StaticPopup_Show("MIGHTIEPACK_DISABLE_MODULE", (def and def.title) or name, nil,
                { name = name, checkbox = self })
            end
          end)
        else
          call(cb, "Disable")
        end

        call(cb, "SetScript", "OnEnter", function(self)
          if not GameTooltip then return end
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:SetText((def and def.title) or name)
          if def and def.notes then GameTooltip:AddLine(def.notes, 1, 1, 1, true) end
          GameTooltip:Show()
        end)
        call(cb, "SetScript", "OnLeave", function()
          if GameTooltip then GameTooltip:Hide() end
        end)
        boxes[name] = cb
      end
    end

    if type(cb) == "table" then
      call(cb, "ClearAllPoints")
      call(cb, "SetPoint", "TOPLEFT", moduleCard, "TOPLEFT", pad, -y)
      if def and def.stub then
        call(cb, "SetChecked", false)
      else
        call(cb, "SetChecked", pkg.IsModuleEnabled(name))
      end

      local on = type(pkg.IsModuleEnabled) == "function" and pkg.IsModuleEnabled(name) or false
      local word = stateWords[name]
      if type(word) == "table" then
        call(word, "SetText", on and "on" or "off")
        local r, g, b, a = T.R(on and "text" or "textDim")
        call(word, "SetTextColor", r, g, b, a)
      end
      y = y + T.size.rowPitch

      -- Touchstone's own sub-option, indented under its row: which spec the
      -- scoring is for. It exists only while Touchstone is on, because there is
      -- nothing it could mean otherwise.
      if name == "Touchstone" then
        local showGear = on
        -- The sub-option gets its own ROW frame, height = one row pitch. The
        -- label and the button are then centred in that row, which is why a
        -- 16px label and a 24px button sit on one line instead of drifting:
        -- anchoring a font string to the card and adding "half a row" only
        -- works if you already know the string's height.
        if not boxes.GearForRow then
          local row = T.NewFrame("Frame", nil, moduleCard)
          if type(row) == "table" then
            call(row, "SetHeight", T.size.rowPitch)
            boxes.GearForRow = row
          end
        end
        if not boxes.GearForLabel and type(boxes.GearForRow) == "table" then
          boxes.GearForLabel = label(boxes.GearForRow, "body", "textMuted", "Gear for")
        end
        if not boxes.GearFor then
          local btn = type(boxes.GearForRow) == "table"
            and CreateFrame("Button", nil, boxes.GearForRow, "UIPanelButtonTemplate") or nil
          if type(btn) == "table" then
            call(btn, "SetSize", 220, T.space.lg)
            call(btn, "SetScript", "OnClick", function() cycleGearFor() end)
            call(btn, "SetScript", "OnEnter", function(self)
              if not GameTooltip then return end
              GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
              GameTooltip:SetText("Gear for")
              GameTooltip:AddLine("Which spec Touchstone scores and gates gear for, using that spec's Wowhead stat priority. Auto follows your current talents. A chosen spec wins over talents and over /up role. Tanks default to Wowhead's Balanced list (or Defensive for Feral Bear); other variants are in this list.", 1, 1, 1, true)
              GameTooltip:Show()
            end)
            call(btn, "SetScript", "OnLeave", function()
              if GameTooltip then GameTooltip:Hide() end
            end)
            boxes.GearFor = btn
          end
        end
        local lab, btn, row = boxes.GearForLabel, boxes.GearFor, boxes.GearForRow
        if type(row) == "table" then
          call(row, "ClearAllPoints")
          call(row, "SetPoint", "TOPLEFT", moduleCard, "TOPLEFT",
            pad + T.size.subIndent, -y)
          if showGear then call(row, "Show") else call(row, "Hide") end
        end
        if type(lab) == "table" then
          call(lab, "ClearAllPoints")
          call(lab, "SetPoint", "LEFT", row or moduleCard, "LEFT", 0, 0)
          if showGear then call(lab, "Show") else call(lab, "Hide") end
        end
        if type(btn) == "table" then
          call(btn, "ClearAllPoints")
          call(btn, "SetPoint", "LEFT", lab or row or moduleCard, "RIGHT", T.space.sm, 0)
          if showGear then
            call(btn, "Show")
            refreshGearForButton()
          else
            call(btn, "Hide")
          end
        end
        if showGear then y = y + T.size.rowPitch end
      end
    end
  end
  layoutModuleCard()
end

-- ── FEEDBACK: the two popups the pack already had ─────────────────────────
local feedbackHeading, bugButton, ideaButton

local function buildFeedback()
  if type(feedbackHeading) ~= "table" then
    feedbackHeading = label(panel, "small", "textDim", "FEEDBACK")
    if type(feedbackHeading) == "table" then
      call(feedbackHeading, "SetPoint", "TOPLEFT", moduleCard or subtitle, "BOTTOMLEFT", 0, -T.size.sectionGap)
    end
    rule(panel, feedbackHeading)
  end

  if type(bugButton) ~= "table" then
    bugButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    if type(bugButton) == "table" then
      call(bugButton, "SetSize", T.space.xl * 4, T.space.lg)
      call(bugButton, "SetPoint", "TOPLEFT", feedbackHeading, "BOTTOMLEFT", 0, -T.space.md)
      call(bugButton, "SetText", "Report a bug")
      call(bugButton, "SetScript", "OnClick", function()
        if type(pkg.OpenBugReport) == "function" then
          pkg.OpenBugReport()
        else
          DEFAULT_CHAT_FRAME:AddMessage(
            "MightiePack: bug report form unavailable (BugReport module did not load)")
        end
      end)
      call(bugButton, "SetScript", "OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Open a pre-filled bug report — press Ctrl+C to copy, then paste it in #mightiepack-bugs on Discord")
        GameTooltip:AddLine("Nothing is uploaded: copy the report and paste it into the #mightiepack-bugs Discord channel.", 1, 1, 1, true)
        GameTooltip:Show()
      end)
      call(bugButton, "SetScript", "OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
      end)
    end
  end

  if type(ideaButton) ~= "table" then
    ideaButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    if type(ideaButton) == "table" then
      call(ideaButton, "SetSize", T.space.xl * 4 + T.space.md, T.space.lg)
      call(ideaButton, "SetPoint", "LEFT", bugButton or feedbackHeading, "RIGHT", T.space.sm, 0)
      call(ideaButton, "SetText", "Suggest an idea")
      call(ideaButton, "SetScript", "OnClick", function()
        if type(pkg.OpenIdeaReport) == "function" then
          pkg.OpenIdeaReport()
        else
          DEFAULT_CHAT_FRAME:AddMessage(
            "MightiePack: idea form unavailable (BugReport module did not load)")
        end
      end)
      call(ideaButton, "SetScript", "OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Open a pre-filled idea form — press Ctrl+C to copy, then paste it into #mightiepack-ideas")
        GameTooltip:AddLine("Nothing is uploaded: copy the idea and paste it into the #mightiepack-ideas Discord channel.", 1, 1, 1, true)
        GameTooltip:Show()
      end)
      call(ideaButton, "SetScript", "OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
      end)
    end
  end
end

--- The footer: what build this is, and the one command that prints a paste-able
--- diagnostic. It is the bottom line of a tab the player reads once and trusts;
--- it should say which version said it.
local footer
local function buildFooter()
  if type(footer) == "table" then return end
  local ver = nil
  if type(pkg.PackVersion) == "function" then
    local ok, v = pcall(pkg.PackVersion)
    if ok and type(v) == "string" and v ~= "" then ver = v end
  end
  local interface = nil
  if type(pkg.GetAddOnMeta) == "function" then
    local ok, v = pcall(pkg.GetAddOnMeta, "MightiePack", "Interface")
    if ok and type(v) == "string" and v ~= "" then interface = v end
  end
  local parts = { "MightiePack" .. (ver and (" v" .. ver) or "") }
  if interface then parts[#parts + 1] = "Interface " .. interface end
  parts[#parts + 1] = "/mp status prints a diagnostic you can paste"
  footer = label(panel, "quiet", "textDim", table.concat(parts, " · "))
  if type(footer) == "table" then
    call(footer, "SetPoint", "BOTTOMLEFT", panel, "BOTTOMLEFT", 0, T.space.sm)
    call(footer, "SetPoint", "RIGHT", panel, "RIGHT", 0, 0)
    call(footer, "SetJustifyH", "LEFT")
  end
end

--- The Pack Settings build: the one named path (card t_ea66cd84, AC-N3).
--- Called from this panel's own OnShow AND from the window's tab activation.
--- The activation call is the one that matters: a frame is BORN SHOWN, so the
--- birth OnShow is spent before the tab can ever be opened, and `Show()` on an
--- already-shown frame fires nothing. OnShow alone could never build these rows.
function pkg.SyncOptionsRows()
  buildModuleCard()
  buildModuleRows()
  buildFeedback()
  buildFooter()
end

--- Re-lay the panel after something outside it changed (a module was turned on
--- or off, a spec override changed). Same path as the build, deliberately: one
--- layout code path is what stops the rows disagreeing with the panel.
function pkg.relayoutOptions()
  pkg.SyncOptionsRows()
end

panel:SetScript("OnShow", function()
  pkg.SyncOptionsRows()
end)

pkg.SyncOptionsRows()

StaticPopupDialogs["MIGHTIEPACK_DISABLE_MODULE"] = {
  text = "Turn off %s?\nThis needs a UI reload. OK reloads now; Cancel keeps it on.",
  button1 = OKAY,
  button2 = CANCEL,
  OnAccept = function(_, data)
    if data and data.name then
      pkg.SetModuleEnabled(data.name, false)
    end
    ReloadUI()
  end,
  OnCancel = function(_, data)
    if data and data.checkbox then
      data.checkbox:SetChecked(pkg.IsModuleEnabled(data.name))
    end
  end,
  OnHide = function(self)
    local data = self.data
    if data and data.checkbox then
      data.checkbox:SetChecked(pkg.IsModuleEnabled(data.name))
    end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

pcall(function()
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    pkg.settingsCategory = category
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end)

--- /mp, /mpack, /mightiepack and the module toggles all land here.
-- Card t_a5de2f16: this is no longer the Settings canvas — it opens the ONE
-- window on the Pack Settings tab. The Settings category above still exists
-- (a player who goes looking in AddOns finds the same panel), and the window
-- claims the panel back when it opens; the content is one frame either way.
-- The old canvas path remains as the fallback for a client where the window
-- could not be created at all, so /mp is never dead.
function pkg.OpenOptions()
  local W = pkg.Window
  if type(W) == "table" and type(W.Open) == "function" then
    local ok = W.Open("settings")
    if ok then return true end
  end
  if pkg.settingsCategory and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(pkg.settingsCategory:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
  elseif type(panel.Show) == "function" then
    panel:Show()
  end
  return false
end

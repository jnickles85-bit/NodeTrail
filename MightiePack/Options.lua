local addonName, pkg = ...

local panel = CreateFrame("Frame", "MightiePackOptionsPanel")
panel.name = "MightiePack"

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
title:SetText("MightiePack")

local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
subtitle:SetText("Tick a module to turn it on. Turning one off needs a UI reload.")

local boxes = {}
pkg.optionsBoxes = boxes

-- ── Row layout ──────────────────────────────────────────────────────
-- Modules are 32px apart. NodeTrail — the only gathering module — also
-- owns 22px indented sub-rows for its own sub-options: the skinning probe
-- (t_5507a0ba) and, under it, "Auto-refresh route" (t_2bc15917). Each is a
-- user-facing capability of NodeTrail, so each has a visible control here;
-- NodeTrail + its sub-options occupy one and a half rows and the recipe /
-- bug-report blocks below start after that, not after a fixed module count.
-- moduleOrder is complete by the time this file loads (the TOC lists every
-- module before Options.lua).
local ROW_H = 32
local SUB_ROW_H = 22
local SUB_INDENT = 36
local FIRST_ROW_Y = -48

local moduleY, skinY, autoY, lastRowY = {}, nil, nil, FIRST_ROW_Y
do
  local y = FIRST_ROW_Y
  for _, name in ipairs(pkg.moduleOrder or {}) do
    moduleY[name] = y
    lastRowY = y
    y = y - ROW_H
    if name == "NodeTrail" then
      skinY = y + (ROW_H - SUB_ROW_H)
      autoY = skinY - SUB_ROW_H
      lastRowY = autoY
      y = autoY - ROW_H
    end
  end
end

-- ── Skinning sub-option helpers (t_5507a0ba) ────────────────────────
-- The probe is NodeTrail's, so the toggle is NodeTrail's too: it lives at
-- NodeTrailDB.skinning.enabled (not MightiePackDB.modules.Skinning) and is
-- owned by the NodeTrail namespace. Every lookup is guarded so the panel
-- still renders when NodeTrail (or the probe files) did not load.
local function ntModule()
  local nt = pkg.NodeTrail
  if type(nt) == "table" then
    return nt
  end
  return nil
end

local function nodeTrailOn()
  if type(pkg.IsModuleEnabled) ~= "function" then
    return false
  end
  local ok, on = pcall(pkg.IsModuleEnabled, "NodeTrail")
  return ok and on == true
end

local function skinningOn()
  local nt = ntModule()
  if nt and type(nt.IsSkinningEnabled) == "function" then
    local ok, on = pcall(nt.IsSkinningEnabled)
    if ok then
      return on == true
    end
  end
  return false
end

-- t_2bc15917: ON by default — that is the whole point of the sub-option.
-- When NodeTrail (or an older copy of it) cannot answer, the box shows on,
-- matching the persisted default.
local function autoRefreshOn()
  local nt = ntModule()
  if nt and type(nt.IsAutoRefreshRoute) == "function" then
    local ok, on = pcall(nt.IsAutoRefreshRoute)
    if ok then
      return on == true
    end
  end
  return true
end

-- Apply the sub-toggle: persist it, then start/stop the probe immediately.
-- No reload is needed — switching off unregisters the probe's events and
-- drops its session buffer (P:Disable) — so this deliberately does NOT
-- raise MIGHTIEPACK_DISABLE_MODULE. That popup exists to warn about a
-- reload; there is nothing to warn about here, and the chat line says so.
local function applySkinning(on)
  local nt = ntModule()
  if not nt then
    pkg.Print("skinning: NodeTrail is not loaded — the sub-option was not saved")
    return false
  end
  if type(nt.SetSkinningEnabled) ~= "function" then
    pkg.Print("skinning: NodeTrail has no sub-option setter — the sub-option was not saved")
    return false
  end
  local okS, errS = pcall(nt.SetSkinningEnabled, on)
  if not okS then
    pkg.Print("skinning: could not save the sub-option: " .. tostring(errS))
    return false
  end
  if on then
    if type(nt.EnableSkinning) == "function" then
      local okE, errE = nt.EnableSkinning()
      if okE == false then
        pkg.Print("skinning: probe did not start: " .. tostring(errE))
        return false
      end
    end
    pkg.Print("Skinning (experimental) on — recording corpses into NodeTrailDB; /mp skindiag dump shows what was stored.")
  else
    if type(nt.DisableSkinning) == "function" then
      nt.DisableSkinning()
    end
    pkg.Print("Skinning (experimental) off — the probe stopped now; no UI reload needed.")
  end
  return true
end

local function syncCheckboxes()
  for index, name in ipairs(pkg.moduleOrder or {}) do
    local def = pkg.modules and pkg.modules[name]
    if def then
      local y = moduleY[name] or (FIRST_ROW_Y - (index - 1) * ROW_H)
      local cb = boxes[name]
      if not cb then
        cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)

        local label
        if cb.Text or cb.text then
          label = cb.Text or cb.text
        else
          label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
          label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        end
        local labelText = def.title or name
        if def.stub then
          labelText = labelText .. " (coming soon)"
        end
        label:SetText(labelText)

        if def.stub then
          cb:Disable()
        else
          cb:SetScript("OnClick", function(self)
            local on = self:GetChecked() and true or false
            if on then
              pkg.SetModuleEnabled(name, true)
              pkg.EnableModules()
              -- A module can refuse to run (Touchstone while the standalone
              -- addon folder is installed). Its Enable() has already printed
              -- why; "enabled." here would be a lie.
              if not def.inert then
                pkg.Print((def.title or name) .. " enabled.")
              end
              -- The skinning sub-option is greyed out while NodeTrail is
              -- off; re-sync so it becomes usable the moment it is on.
              syncCheckboxes()
            else
              StaticPopup_Show("MIGHTIEPACK_DISABLE_MODULE", def.title or name, nil, { name = name, checkbox = self })
            end
          end)
        end

        cb:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:SetText(def.title or name)
          if def.notes then
            GameTooltip:AddLine(def.notes, 1, 1, 1, true)
          end
          GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function()
          GameTooltip:Hide()
        end)

        boxes[name] = cb
      end

      if def.stub then
        cb:SetChecked(false)
      else
        cb:SetChecked(pkg.IsModuleEnabled(name))
      end
    end
  end

  -- ── Skinning sub-option (t_5507a0ba) ──────────────────────────────
  -- Indented under the NodeTrail checkbox, its own checkbox, and NOT a
  -- module row: Mightie's "Skinning should be inside NodeTrail." Greyed out
  -- and inert while NodeTrail is off (the probe is NodeTrail's), persisted
  -- in NodeTrailDB.skinning.enabled, applied immediately in both
  -- directions — no reload, so no MIGHTIEPACK_DISABLE_MODULE popup here.
  if skinY then
    local sb = boxes.Skinning
    if not sb then
      sb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
      sb:SetPoint("TOPLEFT", panel, "TOPLEFT", SUB_INDENT, skinY)

      local skinLabel
      if sb.Text or sb.text then
        skinLabel = sb.Text or sb.text
      else
        skinLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        skinLabel:SetPoint("LEFT", sb, "RIGHT", 4, 0)
      end
      skinLabel:SetText("Skinning (experimental)")

      sb:SetScript("OnClick", function(self)
        if not nodeTrailOn() then
          -- inert: NodeTrail owns the probe, so it cannot be on without it
          self:SetChecked(skinningOn())
          return
        end
        applySkinning(self:GetChecked() and true or false)
        syncCheckboxes()
      end)
      sb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Skinning (experimental)")
        GameTooltip:AddLine("NodeTrail's skinning probe: kill -> loot -> skin -> skin-loot capture for "
          .. "/mp skindiag and /mp skindiag dump. Off by default while this client's event surface "
          .. "is still unverified. Turn it off at any time — no UI reload needed.", 1, 1, 1, true)
        GameTooltip:Show()
      end)
      sb:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)

      boxes.Skinning = sb
    end

    sb:SetChecked(skinningOn())
    if nodeTrailOn() then
      sb:Enable()
    else
      sb:Disable()
    end
  end

  -- ── Auto-refresh route sub-option (t_2bc15917) ────────────────────
  -- Mightie: "yes it needs to be automated for sure, at least on /reloads".
  -- The automatic behaviour has to be visible and switchable, so it is a
  -- checkbox beside the skinning one, persisted in
  -- NodeTrailDB.route.autoRefresh and ON by default. It applies
  -- immediately in both directions: switching it off keeps the line that
  -- is drawn and stops pick-triggered rebuilds; switching it on lets the
  -- next pick schedule one.
  if autoY then
    local ab = boxes.AutoRefresh
    if not ab then
      ab = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
      ab:SetPoint("TOPLEFT", panel, "TOPLEFT", SUB_INDENT, autoY)

      local autoLabel
      if ab.Text or ab.text then
        autoLabel = ab.Text or ab.text
      else
        autoLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        autoLabel:SetPoint("LEFT", ab, "RIGHT", 4, 0)
      end
      autoLabel:SetText("Auto-refresh route")

      ab:SetScript("OnClick", function(self)
        local nt = ntModule()
        if not nodeTrailOn() or not nt or type(nt.SetAutoRefreshRoute) ~= "function" then
          self:SetChecked(autoRefreshOn())
          return
        end
        local okS, value = pcall(nt.SetAutoRefreshRoute, self:GetChecked() and true or false)
        if not okS then
          pkg.Print("auto-refresh: could not save the sub-option: " .. tostring(value))
        elseif value then
          pkg.Print("Auto-refresh route on — the line follows your newest picks, a few seconds after each gather.")
        else
          pkg.Print("Auto-refresh route off — the route stays as it is until /nt start or /nt reload.")
        end
        syncCheckboxes()
      end)
      ab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Auto-refresh route")
        GameTooltip:AddLine("When on, a route you started is rebuilt and drawn again after a /reload or a login " ..
          "(if it is younger than the saved-route limit and you are on its map), and the line follows the " ..
          "herbs you gather — once, a few seconds after the last pick. Off keeps the line as it is.",
          1, 1, 1, true)
        GameTooltip:Show()
      end)
      ab:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)

      boxes.AutoRefresh = ab
    end

    ab:SetChecked(autoRefreshOn())
    if nodeTrailOn() then
      ab:Enable()
    else
      ab:Disable()
    end
  end
end

-- ── Recipes block (NodeTrail's Alchemy recipe scan) ─────────────────
-- The scan used to be invisible unless you knew /nt status, and
-- learning a recipe never refreshed it (t_36412359). This block
-- surfaces the SAME truth the panel/slash share (Rc:StatusLine —
-- four states: scanned / not scanned yet / cannot list / no reagents)
-- plus a "Scan now" button (Rc:TryScanNow). Every lookup is pcall'd,
-- so the panel still renders when the NodeTrail module is off.
local function ntRecipes()
  if pkg and pkg.NodeTrail and type(pkg.NodeTrail.Recipes) == "table" then
    return pkg.NodeTrail.Recipes
  end
  return nil
end

-- The recipe block starts under the last module/sub-option row.
local recHeaderY = lastRowY - 36
local recStatusY = recHeaderY - 18
local recErrorY = recStatusY - 16
local recButtonY = recErrorY - 22

local recHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
recHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, recHeaderY)
recHeader:SetText("Alchemy Recipes")

local recStatus = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
recStatus:SetPoint("LEFT", recHeader, "LEFT", 0, recStatusY - recHeaderY)
recStatus:SetText("")

local recError = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
recError:SetPoint("LEFT", recHeader, "LEFT", 0, recErrorY - recHeaderY)
recError:SetText("")
recError:Hide()

local function syncRecipesBlock()
  local rec = ntRecipes()
  if rec and type(rec.StatusLine) == "function" then
    local ok, line = pcall(rec.StatusLine, rec)
    if ok and type(line) == "string" then
      recStatus:SetText(line)
    else
      recStatus:SetText("recipes: status unavailable (" .. tostring(line) .. ")")
    end
    recStatus:Show()
  else
    recStatus:SetText("recipe module not loaded — turn NodeTrail on")
    recStatus:Show()
  end
  local err
  if rec and type(rec.LastError) == "function" then
    local okE, e = pcall(rec.LastError, rec)
    if okE and type(e) == "string" and e ~= "" then
      err = e
    end
  end
  if err then
    recError:SetText("last error: " .. err)
    recError:Show()
  else
    recError:SetText("")
    recError:Hide()
  end
end

local recButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
recButton:SetPoint("TOPLEFT", recHeader, "LEFT", 0, recButtonY - recHeaderY)
recButton:SetSize(96, 24)
recButton:SetText("Scan now")
recButton:SetScript("OnClick", function()
  local rec = ntRecipes()
  if rec and type(rec.TryScanNow) == "function" then
    local ok, done, msg = pcall(rec.TryScanNow, rec)
    if not ok then
      DEFAULT_CHAT_FRAME:AddMessage("NodeTrail recipes: scan failed: " .. tostring(done))
    else
      DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
  else
    DEFAULT_CHAT_FRAME:AddMessage("NodeTrail recipes: module not loaded (turn NodeTrail on)")
  end
  syncRecipesBlock()
end)
recButton:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText("Rescan your learned Alchemy recipes now")
  GameTooltip:AddLine("Needs the Alchemy window open. A learned recipe also refreshes automatically the next time you open Alchemy.", 1, 1, 1, true)
  GameTooltip:Show()
end)
recButton:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)

-- ── Bug report entry point ──────────────────────────────────────────
-- t_ed1e009e: one button into the report form. The form auto-fills
-- version/build/locale/character/zone/module state/diagnostics; the
-- player writes only the description. No upload: the client has no
-- HTTP, so the form's job ends at a copyable, pre-selected box.
local bugHeaderY = recButtonY - 40
local bugButtonY = bugHeaderY - 26

local bugHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
bugHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, bugHeaderY)
bugHeader:SetText("Bug reports")

local bugButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
bugButton:SetPoint("TOPLEFT", bugHeader, "LEFT", 0, bugButtonY - bugHeaderY)
bugButton:SetSize(128, 24)
bugButton:SetText("Report a bug")
bugButton:SetScript("OnClick", function()
  if type(pkg.OpenBugReport) == "function" then
    -- opened from the options panel: no module argument, so the form
    -- preselects NodeTrail (its default target)
    pkg.OpenBugReport()
  else
    DEFAULT_CHAT_FRAME:AddMessage("MightiePack: bug report form unavailable (BugReport module did not load)")
  end
end)
bugButton:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText("Open the bug report form — version, build, locale, character, zone and module diagnostics are filled in for you")
  GameTooltip:AddLine("Nothing is uploaded: copy the report and paste it into the #mightiepack-bugs Discord channel.", 1, 1, 1, true)
  GameTooltip:Show()
end)
bugButton:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)

panel:SetScript("OnShow", function()
  syncCheckboxes()
  syncRecipesBlock()
end)

StaticPopupDialogs["MIGHTIEPACK_DISABLE_MODULE"] = {
  text = "Turn off %s?\nThis needs a UI reload. OK reloads now; Cancel keeps it on.",
  button1 = OKAY,
  button2 = CANCEL,
  OnAccept = function(self, data)
    if data and data.name then
      pkg.SetModuleEnabled(data.name, false)
    end
    ReloadUI()
  end,
  OnCancel = function(self, data)
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

function pkg.OpenOptions()
  if pkg.settingsCategory and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(pkg.settingsCategory:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
  else
    panel:Show()
  end
end

pkg.optionsPanel = panel

local addonName, pkg = ...

local panel = CreateFrame("Frame", "MightiePackOptionsPanel")
panel.name = "MightiePack"

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
title:SetText("MightiePack")

local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
subtitle:SetText("Tick a module to turn it on. Turning one off needs a UI reload.")

local function syncCheckboxes()
  local y = -48
  for _, name in ipairs(pkg.moduleOrder or {}) do
    local def = pkg.modules and pkg.modules[name]
    if def then
      local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
      cb:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
      y = y - 32

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
        cb:SetChecked(false)
        cb:Disable()
      else
        cb:SetChecked(pkg.IsModuleEnabled(name))
        cb:SetScript("OnClick", function(self)
          local on = self:GetChecked() and true or false
          if on then
            pkg.SetModuleEnabled(name, true)
            pkg.EnableModules()
            pkg.Print((def.title or name) .. " enabled.")
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
    end
  end
end

panel:SetScript("OnShow", function()
  syncCheckboxes()
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

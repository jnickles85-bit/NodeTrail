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

local function syncCheckboxes()
  for index, name in ipairs(pkg.moduleOrder or {}) do
    local def = pkg.modules and pkg.modules[name]
    if def then
      local y = -48 - (index - 1) * 32
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

        boxes[name] = cb
      end

      if def.stub then
        cb:SetChecked(false)
      else
        cb:SetChecked(pkg.IsModuleEnabled(name))
      end
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

local moduleCount = 0
for _ in pairs(pkg.moduleOrder or {}) do
  moduleCount = moduleCount + 1
end
if moduleCount < 1 then
  moduleCount = 1
end
local lastBoxY = -48 - (moduleCount - 1) * 32
local recHeaderY = lastBoxY - 36
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

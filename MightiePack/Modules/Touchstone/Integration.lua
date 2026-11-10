if MightiePackTouchstoneSkip then return end
--- U6 (card t_6696b35a): the surfaces Blizzard draws for us.
---
--- Two of them, each a no-op when this client does not offer the API:
---   * the AddOns settings panel (Settings.RegisterCanvasLayoutCategory on
---     the clients that have the modern settings UI, otherwise the legacy
---     InterfaceOptions_AddCategory list);
---   * an AddonCompartmentFrame entry, when that frame exists.
---
--- A keybind is out of scope. This file does not create Bindings.xml and
--- does not call SetBinding.
---
--- Loaded after the window (UI.lua defines ShowMain / ToggleMain) and before
--- Core.lua. Registration runs at load. A missing API returns without
--- touching anything; a present API that errors is caught, so a signature
--- this client does not actually match cannot break login.

StatForge = StatForge or {}
local SF = StatForge

local function openWindow()
  if type(SF.ToggleMain) == "function" then
    SF.ToggleMain()
  end
end

-- Returns true when a panel was registered, false when this client has
-- neither API (or the call raised). Never errors.
function SF.RegisterBlizzardSettings()
  if Settings and type(Settings.RegisterCanvasLayoutCategory) == "function"
      and type(Settings.RegisterAddOnCategory) == "function" then
    SF._settingsTried = "canvas"
    local ok = pcall(function()
      local panel = CreateFrame("Frame")
      panel.name = "Touchstone"
      pcall(function()
        local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        if title and title.SetPoint then
          title:SetPoint("TOPLEFT", 16, -16)
          title:SetText("Touchstone")
        end
        local body = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        if body and body.SetPoint and title then
          body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
          body:SetText("In-game item advisor. Open it with /ts.")
        end
      end)
      local category = Settings.RegisterCanvasLayoutCategory(panel, "Touchstone")
      if category ~= nil then
        Settings.RegisterAddOnCategory(category)
      end
    end)
    if ok then
      SF._settingsRegistered = "canvas"
      return true
    end
  end
  if type(InterfaceOptions_AddCategory) == "function" then
    SF._settingsTried = "legacy"
    local ok = pcall(function()
      local panel = CreateFrame("Frame")
      panel.name = "Touchstone"
      InterfaceOptions_AddCategory(panel)
    end)
    if ok then
      SF._settingsRegistered = "legacy"
      return true
    end
  end
  SF._settingsRegistered = false
  return false
end

-- Returns true when an entry was added, false when the frame is absent.
-- Never errors.
function SF.RegisterCompartment()
  local frame = AddonCompartmentFrame
  if type(frame) ~= "table" or type(frame.RegisterAddon) ~= "function" then
    SF._compartmentRegistered = false
    return false
  end
  SF._compartmentTried = true
  local ok = pcall(function()
    frame:RegisterAddon({
      text = "Touchstone",
      icon = "Interface\\Icons\\INV_Misc_Gear_01",
      notCheckable = true,
      func = openWindow,
      funcOnEnter = function(btn)
        if not GameTooltip or type(GameTooltip.SetOwner) ~= "function" then return end
        GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
        if GameTooltip.AddLine then
          GameTooltip:AddLine("Touchstone")
          GameTooltip:AddLine("/ts", 0.7, 0.7, 0.7)
        end
        if GameTooltip.Show then GameTooltip:Show() end
      end,
      funcOnLeave = function()
        if GameTooltip and type(GameTooltip.Hide) == "function" then
          GameTooltip:Hide()
        end
      end,
    })
  end)
  SF._compartmentRegistered = ok and true or false
  return SF._compartmentRegistered
end

-- Fold (MightiePack Touchstone module): registration is deferred to
-- SF.Enable() in Core.lua, so a disabled module adds no Blizzard settings
-- category and no addon-compartment entry. Both functions above are
-- unchanged; only the two calls moved.
function SF.EnableIntegrations()
  SF.RegisterBlizzardSettings()
  SF.RegisterCompartment()
end

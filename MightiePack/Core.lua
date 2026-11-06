local addonName, pkg = ...

MightiePack = pkg
pkg.addonName = addonName
pkg.version = "0.3.0"

function pkg.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MightiePack|r: " .. tostring(msg or ""))
end

pkg.moduleDefaults = {
  NodeTrail = true,
  Touchstone = false,
}

function pkg.GetSettings()
  if type(MightiePackDB) ~= "table" then
    MightiePackDB = {}
  end
  if type(MightiePackDB.modules) ~= "table" then
    MightiePackDB.modules = {}
  end
  for name, def in pairs(pkg.moduleDefaults or {}) do
    if MightiePackDB.modules[name] == nil then
      MightiePackDB.modules[name] = def
    end
  end
  return MightiePackDB
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    pkg.GetSettings()
    if type(pkg.EnableModules) == "function" then
      pkg.EnableModules()
    end
    f:UnregisterEvent("ADDON_LOADED")
  end
end)

SLASH_MIGHTIEPACK1 = "/mightiepack"
SLASH_MIGHTIEPACK2 = "/mpack"
SlashCmdList.MIGHTIEPACK = function(msg)
  msg = (msg or ""):match("^%s*(.-)%s*$") or ""
  msg = msg:lower()
  if msg == "" or msg == "options" or msg == "config" then
    if type(pkg.OpenOptions) == "function" then
      pkg.OpenOptions()
    end
  elseif msg == "status" then
    for _, name in ipairs(pkg.moduleOrder or {}) do
      local def = pkg.modules and pkg.modules[name]
      if def then
        local state = pkg.IsModuleEnabled(name) and "on" or "off"
        local line = (def.title or name) .. ": " .. state
        if def.stub then
          line = line .. " (coming soon)"
        end
        if def.loaded then
          line = line .. " (loaded)"
        end
        pkg.Print(line)
      end
    end
  else
    pkg.Print("/mpack [options|status]")
    if pkg.IsModuleEnabled("NodeTrail") then
      pkg.Print("NodeTrail: /nt help")
    end
  end
end

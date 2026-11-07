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
    -- t_e9996745: identity header so `/mpack status` output is a
    -- self-describing bug report: addon version + Interface (both from the
    -- TOC via GetAddOnMetadata("MightiePack", ...)), client build number
    -- (select(4, GetBuildInfo())) plus the full GetBuildInfo() version
    -- string, current locale, and whether GatherMate2 is loaded.
    -- Every API is guarded against a missing function AND a nil/empty
    -- return: this file must print "unknown" and never error in an
    -- environment where the stub does not define the globals at all
    -- (umbrella_spec defines none of them).
    local function tocMeta(what)
      if type(GetAddOnMetadata) ~= "function" then
        return nil
      end
      local ok, val = pcall(GetAddOnMetadata, addonName, what)
      if ok and type(val) == "string" and val ~= "" then
        return val
      end
      return nil
    end
    pkg.Print("version " .. (tocMeta("Version") or "unknown"))

    local iface = tocMeta("Interface") or "unknown"

    local build, clientVersion = "unknown", "unknown"
    if type(GetBuildInfo) == "function" then
      -- real contract: major, minor, patch, build, platform, locale, serverName
      local ok, major, minor, patch, buildNum = pcall(GetBuildInfo)
      if ok and type(buildNum) == "string" and buildNum ~= "" then
        build = buildNum
        if type(major) == "string" and type(minor) == "string" and type(patch) == "string" then
          clientVersion = major .. "." .. minor .. "." .. patch .. "." .. buildNum
        end
      end
    end

    local loc = "unknown"
    if type(GetLocale) == "function" then
      local ok, l = pcall(GetLocale)
      if ok and type(l) == "string" and l ~= "" then
        loc = l
      end
    end

    local gm2 = "unknown"
    if type(IsAddOnLoaded) == "function" then
      local ok, loaded = pcall(IsAddOnLoaded, "GatherMate2")
      if ok then
        gm2 = loaded and "loaded" or "not loaded"
      end
    end

    pkg.Print(("interface %s, build %s, client %s, locale %s, GatherMate2: %s")
      :format(iface, build, clientVersion, loc, gm2))

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

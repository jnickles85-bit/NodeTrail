local addonName, pkg = ...

MightiePack = pkg
pkg.addonName = addonName
pkg.version = "0.3.0"

function pkg.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MightiePack|r: " .. tostring(msg or ""))
end

pkg.moduleDefaults = {
  NodeTrail = true,
  -- t_a5f41944: OFF until the probe has verified the event surface on
  -- this client (the card's first rule: do not guess it). The options
  -- checkbox turns it on immediately — no reload needed to enable.
  Skinning = false,
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
-- t_a5f41944: the card's evidence channel is literally "/mp skindiag".
-- The card's own wording, honored: /mp works, and /mpack skindiag works
-- too (the client matches the longest registered slash first, so /mpack
-- is never shadowed by /mp).
SLASH_MIGHTIEPACK3 = "/mp"
SlashCmdList.MIGHTIEPACK = function(msg)
  local raw = (msg or ""):match("^%s*(.-)%s*$") or ""
  -- `rest` is the SECOND capture: `local x = s:match(...)` takes only
  -- the first capture back, which would be the command word itself.
  local first, rest = raw:match("^(%S+)%s*(.*)$")
  first = (first or ""):lower()
  rest = (rest or ""):match("^%s*(.-)%s*$") or ""
  if first == "" or first == "options" or first == "config" then
    if type(pkg.OpenOptions) == "function" then
      pkg.OpenOptions()
    end
  elseif first == "status" then
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
  elseif first == "bug" then
    -- t_ed1e009e: the in-game bug report form — the same one the
    -- options panel button opens. Optional module argument preselects
    -- that module (/mpack bug skinning); case-insensitive.
    if type(pkg.OpenBugReport) == "function" then
      pkg.OpenBugReport(rest ~= "" and rest or nil)
    else
      pkg.Print("bug report form unavailable (BugReport module did not load)")
    end
  elseif first == "skindiag" then
    -- t_a5f41944: the Skinning event probe (/mp skindiag, /mp skindiag
    -- dump). Module-gated like /nt ttdiag: the command answers honestly
    -- when the module is off or failed to load, and delegates to
    -- pkg.Skinning.Probe when it is live.
    local restL = (rest or ""):lower()
    local def = pkg.modules and pkg.modules.Skinning
    if type(def) ~= "table" or not def.loaded then
      pkg.Print("skindiag: the Skinning module is off or did not load — tick Skinning in /mpack options (turning it on is immediate)")
      pkg.Print("/mp skindiag - toggle event capture (kill, loot, skin, skin-loot chain)")
      pkg.Print("/mp skindiag dump - print what was captured (one line per step, screenshot-able)")
    else
      local S = pkg.Skinning
      local P = S and S.Probe
      if type(P) ~= "table" then
        pkg.Print("skindiag: probe did not load"
          .. (S and S._error and (" (" .. S._error .. ")") or ""))
      elseif restL == "" then
        local okT, on = pcall(P.Toggle, P)
        if okT then
          if on then
            pkg.Print("skindiag: capture ON — kill + loot, cast Skinning, then loot again and dump")
          else
            pkg.Print("skindiag: capture off")
          end
        else
          pkg.Print("skindiag: toggle failed: " .. tostring(on))
        end
      elseif restL == "dump" then
        local okD, errD = pcall(P.Diag, P)
        if not okD then
          pkg.Print("skindiag: dump failed: " .. tostring(errD))
        end
      else
        pkg.Print("/mp skindiag - toggle event capture (kill, loot, skin, skin-loot chain)")
        pkg.Print("/mp skindiag dump - print what was captured (one line per step, screenshot-able)")
      end
    end
  else
    -- keep the historical usage line verbatim (existing callers/tests
    -- rely on it); the new subcommand gets its own line.
    pkg.Print("/mpack [options|status]")
    pkg.Print("/mpack bug [module] — open the bug report form (no upload — copy and paste into Discord)")
    pkg.Print("/mp skindiag (toggle) | /mp skindiag dump (skinning event probe)")
    if pkg.IsModuleEnabled("NodeTrail") then
      pkg.Print("NodeTrail: /nt help")
    end
  end
end

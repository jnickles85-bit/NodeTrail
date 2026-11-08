local addonName, pkg = ...

MightiePack = pkg
pkg.addonName = addonName
pkg.version = "0.3.0"

function pkg.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MightiePack|r: " .. tostring(msg or ""))
end

-- TOC metadata, provider chain (t_5507a0ba).
--
-- On the Forever 16001 client the global GetAddOnMetadata does not exist,
-- so /mpack status printed "version unknown / interface unknown" for a
-- perfectly good TOC. The modern surface is C_AddOns.GetAddOnMetadata;
-- the legacy global is the fallback. Both are pcall'd and both must
-- return a non-empty string, and the provider is resolved at CALL time —
-- a client (or a test stub) that adds or removes either one after load
-- must be honoured, never cached.
function pkg.GetAddOnMeta(addon, field)
  if type(C_AddOns) == "table" and type(C_AddOns.GetAddOnMetadata) == "function" then
    local ok, val = pcall(C_AddOns.GetAddOnMetadata, addon, field)
    if ok and type(val) == "string" and val ~= "" then
      return val
    end
  end
  if type(GetAddOnMetadata) == "function" then
    local ok, val = pcall(GetAddOnMetadata, addon, field)
    if ok and type(val) == "string" and val ~= "" then
      return val
    end
  end
  return nil
end

-- NodeTrail is the only gathering module. The skinning probe lives under
-- Modules/Skinning/ but it is NodeTrail's sub-feature (sub-toggle:
-- NodeTrailDB.skinning.enabled), NOT a peer module — three sibling
-- checkboxes read as three separate addons (t_5507a0ba).
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

-- Protected-action reporter.
--
-- When the client refuses an addon call, it fires ADDON_ACTION_BLOCKED (or
-- _FORBIDDEN) with (addonName, functionName) and raises the modal
--   "<addon> has been blocked from an action only available to the Blizzard UI"
-- The modal never says WHICH function, and the taint log only flushes on a
-- clean exit — so without this the only way to identify the call is to guess.
-- The event arguments are public, so printing them answers it in one line.
local guard = CreateFrame("Frame")
for _, ev in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
  if type(guard.RegisterEvent) == "function" then
    pcall(guard.RegisterEvent, guard, ev)
  end
end
if type(guard.SetScript) == "function" then
  guard:SetScript("OnEvent", function(_, event, who, what)
    pkg.Print(("%s: the client refused a protected call — addon=%s function=%s")
      :format(tostring(event), tostring(who), tostring(what)))
  end)
end

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
    -- t_5507a0ba: the provider chain (C_AddOns.GetAddOnMetadata, then the
    -- legacy global, then "unknown") lives in pkg.GetAddOnMeta because the
    -- Forever client has no global GetAddOnMetadata at all.
    local function tocMeta(what)
      if type(pkg.GetAddOnMeta) ~= "function" then
        return nil
      end
      local ok, val = pcall(pkg.GetAddOnMeta, addonName, what)
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

    -- t_5507a0ba: the skinning probe is NodeTrail's sub-feature, so its
    -- state belongs on the NodeTrail line — there is no "Skinning:" module
    -- line any more.
    local function skinningWord()
      local nt = pkg.NodeTrail
      if type(nt) == "table" and type(nt.IsSkinningEnabled) == "function" then
        local okS, on = pcall(nt.IsSkinningEnabled)
        if okS then
          return on and "on" or "off"
        end
      end
      return "off"
    end

    for _, name in ipairs(pkg.moduleOrder or {}) do
      local def = pkg.modules and pkg.modules[name]
      if def then
        local state = pkg.IsModuleEnabled(name) and "on" or "off"
        local line = (def.title or name) .. ": " .. state
        if def.stub then
          line = line .. " (coming soon)"
        end
        if def.inert then
          -- EnableModules marks a refusing module as loaded; without this the
          -- status line would claim a module is running while it is inert.
          line = line .. " (inert - standalone Touchstone installed)"
        elseif def.loaded then
          line = line .. " (loaded)"
        end
        if name == "NodeTrail" then
          line = line .. " - skinning " .. skinningWord()
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
    -- t_a5f41944 probe, re-homed by t_5507a0ba: the probe is NodeTrail's
    -- sub-feature (sub-toggle NodeTrailDB.skinning.enabled), not a module.
    -- CHOICE: a diagnostic is allowed to run while the sub-toggle is off —
    -- the toggle governs recording, and /mp skindiag is the evidence
    -- channel used to decide whether recording is worth having. The first
    -- line says which state it is in, so a pasted dump is never ambiguous.
    local restL = (rest or ""):lower()
    local sk = pkg.Skinning
    local P = type(sk) == "table" and sk.Probe or nil
    if type(P) ~= "table" then
      pkg.Print("skindiag: the skinning probe did not load"
        .. (type(sk) == "table" and sk._error and (" (" .. tostring(sk._error) .. ")") or ""))
      pkg.Print("/mp skindiag - toggle event capture (kill, loot, skin, skin-loot chain)")
      pkg.Print("/mp skindiag dump - print what was captured (one line per step, screenshot-able)")
      return
    end
    local nt = pkg.NodeTrail
    local skinOn = false
    if type(nt) == "table" and type(nt.IsSkinningEnabled) == "function" then
      local okS, on = pcall(nt.IsSkinningEnabled)
      skinOn = okS and on == true
    end
    if not skinOn then
      pkg.Print("skindiag: skinning is off (NodeTrail sub-option) — diagnostics run, nothing recorded")
    end
    if not P.enabled and type(P.Enable) == "function" then
      local okE, errE = pcall(P.Enable, P)
      if not okE then
        pkg.Print("skindiag: could not start the probe: " .. tostring(errE))
        return
      end
    end
    if restL == "" then
      local okT, on = pcall(P.Toggle, P)
      if okT then
        if on then
          pkg.Print("skindiag: capture ON — kill + loot, cast Skinning, then loot again and dump")
        elseif skinOn then
          -- t_80ffe952: with the sub-option on, capture IS recording. Turning
          -- the diagnostic off pauses recording too, and the line says so
          -- rather than letting the player think it still records.
          pkg.Print("skindiag: capture off — recording is paused too; /mp skindiag resumes it")
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

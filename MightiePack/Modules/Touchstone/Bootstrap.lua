-- Duplicate-load guard for the vendored Touchstone module.
--
-- The vendored files are the pin's own blobs, byte for byte: upstream ships the
-- host opt-out itself (StatForge card t_4e61b67f), so every one of them opens
-- with `if TouchstoneSkip then return end`. This file MUST load first (the toc
-- lists it first in the Touchstone block); it is the only Touchstone code that
-- runs when the module is inert.
--
-- `TouchstoneSkip` is set from the detection below, in this one place. A file
-- vendored without it would run its body with the module off — which is why the
-- sync's copy check hashes every vendored file against the pin's blob and its
-- patch check re-applies every patch to that same blob.
--
-- Why folder existence and not load state: `MightiePack` sorts before
-- `Touchstone`, so at our load time `IsAddOnLoaded("Touchstone")` is false even
-- when the player has the standalone installed and the client will load it a
-- moment later. That check alone would silently double-load and two copies
-- would write StatForgeDB. `GetAddOnInfo` answers "does this folder exist"
-- regardless of load order, so it is consulted BEFORE the load-state check.
--
-- If no detector exists at all the answer is `unknown`, never "absent": an
-- unknown answer must not silently double-load, so the module stays inert and
-- says so. The detection path is recorded on the package table for the toggle
-- message (Modules.lua) to name.

local addonName, pkg = ...

pkg = pkg or {}

local TOUCHSTONE = "Touchstone"

local function viaCAddOns()
  local api = rawget(_G, "C_AddOns")
  if type(api) ~= "table" or type(api.DoesAddOnExist) ~= "function" then
    return nil
  end
  local ok, exists = pcall(api.DoesAddOnExist, TOUCHSTONE)
  if not ok then
    return nil
  end
  return exists and true or false
end

local function viaGetAddOnInfo()
  local api = rawget(_G, "GetAddOnInfo")
  if type(api) ~= "function" then
    return nil
  end
  local ok, name = pcall(api, TOUCHSTONE)
  if not ok then
    return nil
  end
  -- GetAddOnInfo returns nil for a folder that is not installed.
  return name ~= nil
end

local function viaIsAddOnLoaded()
  local api = rawget(_G, "IsAddOnLoaded")
  if type(api) ~= "function" then
    return nil
  end
  local ok, loaded = pcall(api, TOUCHSTONE)
  if not ok then
    return nil
  end
  return loaded and true or false
end

local function detect()
  local path, present = "C_AddOns.DoesAddOnExist", viaCAddOns()
  if present == nil then
    path, present = "GetAddOnInfo", viaGetAddOnInfo()
  end
  if present == nil then
    path, present = "IsAddOnLoaded", viaIsAddOnLoaded()
  end
  if present == nil then
    -- No detector: record unknown. Do NOT coerce this to false.
    return "unknown", nil
  end
  return path, present
end

local path, present = detect()

pkg.TouchstoneDetection = {
  path = path,
  present = present,
  -- unknown means "we could not tell", and the module must stay inert.
  skip = (present ~= false),
}

MightiePackTouchstoneSkip = pkg.TouchstoneDetection.skip
-- The pin's own opt-out flag (upstream card t_4e61b67f). Every vendored file
-- checks THIS name on its first statement, so setting it here is what makes the
-- module inert without editing a single vendored byte. It is the same answer as
-- the pack's flag: the module is off when the standalone is present or when the
-- client cannot tell.
TouchstoneSkip = pkg.TouchstoneDetection.skip

-- Exposed for the toggle message and for tests; returns the same table.
function pkg.GetTouchstoneDetection()
  return pkg.TouchstoneDetection
end

return nil

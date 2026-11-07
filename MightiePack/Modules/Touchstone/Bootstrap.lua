-- Duplicate-load guard for the vendored Touchstone module.
--
-- The vendored files each begin with `if MightiePackTouchstoneSkip then return
-- end`, so this file MUST load first (MightiePack.toc lists it first in the
-- Touchstone block). It is the only Touchstone code that runs when the module
-- is inert.
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

-- Exposed for the toggle message and for tests; returns the same table.
function pkg.GetTouchstoneDetection()
  return pkg.TouchstoneDetection
end

return nil

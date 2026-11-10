-- Core.lua — the skinning probe's namespace (t_a5f41944, re-homed by
-- t_5507a0ba).
--
-- Skinning is NOT a module of its own any more: it is NodeTrail's
-- sub-feature. There is no pkg.RegisterModule here, so it never appears in
-- pkg.moduleOrder / pkg.moduleDefaults and the options panel shows it as
-- an indented sub-option under NodeTrail instead of a sibling module.
-- The files stay where they are on disk (Modules/Skinning/, still listed in
-- the TOC) and are loaded by the addon; NodeTrail's Enable() (and the
-- /mp skindiag diagnostic) drive this namespace:
--
--   * pkg.Skinning        the namespace (this table) — not a module
--   * pkg.Skinning.Probe  the in-client event capture (/mp skindiag)
--
-- The sub-toggle is persisted by NodeTrail in NodeTrailDB.skinning.enabled
-- (default false: the event surface is still unverified on this client).
-- Nothing in this file reads that toggle — NodeTrail owns the policy, this
-- file owns the probe — so /mp skindiag can run the diagnostic while the
-- toggle is off.

local _, pkg = ...
pkg.Skinning = pkg.Skinning or {}
local ns = pkg.Skinning
ns.version = "0.3.0"

function ns.Enable()
  if ns.enabled then return end
  ns.enabled = true
  local P = ns.Probe
  if type(P) == "table" and type(P.Enable) == "function" then
    local ok, err = pcall(P.Enable, P)
    if not ok then
      -- the namespace stays loaded and honestly reports its error in the
      -- diag instead of half-enabling
      ns._error = tostring(err)
    else
      -- t_80ffe952: recording is what the sub-option means. ns.Enable is
      -- reached only when NodeTrailDB.skinning.enabled is on (NodeTrail's
      -- Enable at login, the options checkbox, both via EnableSkinning), so
      -- capture starts here — the player must not have to run /mp skindiag
      -- to have a kill recorded. /mp skindiag still toggles it by hand for a
      -- manual evidence run.
      P.capturing = true
    end
  end
end

-- Turning the sub-option off takes effect immediately: the probe stops
-- capturing and unregisters its events. No UI reload is required, which is
-- why the options panel does not raise MIGHTIEPACK_DISABLE_MODULE for it.
function ns.Disable()
  ns.enabled = false
  local P = ns.Probe
  if type(P) == "table" and type(P.Disable) == "function" then
    local ok, err = pcall(P.Disable, P)
    if not ok then
      ns._error = tostring(err)
    end
  end
end

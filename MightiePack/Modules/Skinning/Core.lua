-- Core.lua — t_a5f41944 (Skinning 1/3)
--
-- The Skinning module for the umbrella. Two things and nothing else at
-- this stage (the implementation card builds on the probe's evidence):
--
--   * registers the module with the umbrella (Options gets its checkbox
--     automatically; /mpack status lists it)
--   * runs the probe — the in-client event capture with /mp skindiag
--     and /mp skindiag dump. The slash dispatch itself lives in the
--     umbrella Core.lua (the /mpack + /mp handler), which calls back in
--     here through pkg.modules.Skinning / pkg.Skinning.Probe
--
-- The module is OFF by default: on this client the event surface is
-- unverified, and the card is explicit — do not guess it. Turning it on
-- is immediate (no UI reload); turning it off needs the standard reload
-- the umbrella already documents.

local addonName, pkg = ...
pkg.Skinning = pkg.Skinning or {}
local ns = pkg.Skinning
Skinning = ns
ns.version = "0.1.0"

function ns.Enable()
  if ns.enabled then return end
  ns.enabled = true
  local P = ns.Probe
  if type(P) == "table" and type(P.Enable) == "function" then
    local ok, err = pcall(P.Enable, P)
    if not ok then
      -- the module stays registered and honestly reports its error in
      -- the diag instead of half-enabling
      ns._error = tostring(err)
    end
  end
end

if type(pkg.RegisterModule) == "function" then
  pkg.RegisterModule("Skinning", {
    title = "Skinning",
    notes = "Kill -> loot -> skin -> skin-loot event probe (the data model is SKINNING-DATA-MODEL.md). "
      .. "/mp skindiag toggles capture; /mp skindiag dump prints the captured chain — "
      .. "Forever has no /run or /dump, so the chat lines are the only evidence channel.",
    Enable = function() ns.Enable() end,
  })
end

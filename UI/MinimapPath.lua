local addonName, ns = ...

-- Minimap white path stub. Will project route segments into minimap space
-- (HBD world coords or angle/radius), Classic-safe — no Retail-only APIs.

ns.MinimapPath = ns.MinimapPath or {}
local M = ns.MinimapPath

function M:Clear()
  self.path = nil
  -- TODO: hide minimap line textures
end

function M:SetRoute(route)
  if not route or not ns.GetDB().showMinimap then
    self:Clear()
    return
  end
  self.path = route.path
  -- TODO: draw white segments for nearby path edges
end

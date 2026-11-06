local addonName, ns = ...

-- World-map white path overlay (Zygor-style). Skeleton: holds route points;
-- draw implementation will use MapCanvas pin/line frames safe on Classic/Forever.

ns.MapOverlay = ns.MapOverlay or {}
local M = ns.MapOverlay

function M:Clear()
  self.path = nil
  self.mapID = nil
  -- TODO: hide/release line textures on WorldMapFrame
end

function M:SetRoute(route)
  if not route or not ns.GetDB().showWorldMap then
    self:Clear()
    return
  end
  self.mapID = route.mapID
  self.path = route.path
  -- TODO: create white polyline through path[].x/y (0..1) on the zone map canvas
end

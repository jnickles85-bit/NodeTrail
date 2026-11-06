local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

ns.defaults = {
  profile = {
    enabled = true,
    -- Herbalism-only MVP; mining later
    gatherType = "Herb Gathering",
    -- nil / empty = all herb nodeIDs in zone
    nodeFilter = {},
    clusterCell = 0.03,      -- ~3% of map → merge nearby nodes
    maxStops = 40,           -- cap loop size in dense zones
    pathColor = { 1, 1, 1, 0.9 }, -- Zygor-style white
    pathWidth = 2,
    showWorldMap = true,
    showMinimap = true,
  },
}

function ns.GetDB()
  if type(NodeTrailDB) ~= "table" then
    NodeTrailDB = CopyTable(ns.defaults)
  end
  if type(NodeTrailDB.profile) ~= "table" then
    NodeTrailDB.profile = CopyTable(ns.defaults.profile)
  end
  return NodeTrailDB.profile
end

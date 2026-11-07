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
    routeSource = "density", -- "density" (our recorded herbs) or "gm2" (GatherMate2 nodes, optional fallback)
    densityCell = 0.02,
    densityWarm = 0.4,
    densityAnchorCell = 0.06,
    densitySmooth = 2,
  },
  -- t_5507a0ba: the skinning probe is NodeTrail's sub-feature, so its
  -- sub-toggle lives in NodeTrail's own saved variable (top level, NOT
  -- inside profile and NOT in MightiePackDB.modules). OFF by default: the
  -- event surface is still unverified on this client.
  skinning = {
    enabled = false,
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

-- ── Skinning sub-toggle (t_5507a0ba) ────────────────────────────────
-- Persisted at NodeTrailDB.skinning.enabled, default false. Filled in
-- lazily so a NodeTrailDB written before this key existed keeps every
-- other key it already has (a saved profile is never replaced).
function ns.GetSkinDB()
  if type(NodeTrailDB) ~= "table" then
    NodeTrailDB = CopyTable(ns.defaults)
  end
  if type(NodeTrailDB.skinning) ~= "table" then
    NodeTrailDB.skinning = { enabled = false }
  end
  if type(NodeTrailDB.skinning.enabled) ~= "boolean" then
    NodeTrailDB.skinning.enabled = false
  end
  return NodeTrailDB.skinning
end

function ns.IsSkinningEnabled()
  return ns.GetSkinDB().enabled == true
end

function ns.SetSkinningEnabled(on)
  ns.GetSkinDB().enabled = on and true or false
  return NodeTrailDB.skinning.enabled
end

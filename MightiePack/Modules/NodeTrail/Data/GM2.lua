local _, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

-- Soft-dep GatherMate2. Public API (Nevcairiel/GatherMate2):
--   GetNodesForZone(uiMapID, "Herb Gathering", ignoreFilter) → (coord, nodeID)
--   DecodeLoc(coord) → x, y in 0..1
--   GetNameForNode(dbType, nodeID)
-- Live storage: GatherMate2HerbDB[uiMapID][coord] = nodeID (do not read SV directly).

local GATHER_TYPE = "Herb Gathering"

function ns.GetGatherMate2()
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    if not C_AddOns.IsAddOnLoaded("GatherMate2") then
      return nil
    end
  elseif IsAddOnLoaded and not IsAddOnLoaded("GatherMate2") then
    return nil
  end
  if _G.GatherMate2 then
    return _G.GatherMate2
  end
  if LibStub then
    local ok, addon = pcall(function()
      return LibStub("AceAddon-3.0"):GetAddon("GatherMate2", true)
    end)
    if ok then
      return addon
    end
  end
  return nil
end

function ns.GetPlayerMapID()
  local GM = ns.GetGatherMate2()
  if GM and GM.HBD and GM.HBD.GetPlayerZone then
    local id = GM.HBD:GetPlayerZone()
    if id and id > 0 then
      return id
    end
  end
  if C_Map and C_Map.GetBestMapForUnit then
    return C_Map.GetBestMapForUnit("player")
  end
  return nil
end

--- Snapshot herb nodes for a uiMapID.
--- @return nodes { {x=, y=, nodeID=, name=} } | nil, errKey ("NEED_GM2"|"NO_MAP")
function ns.CollectHerbNodes(mapID, nodeFilter)
  local GM = ns.GetGatherMate2()
  if not GM or type(GM.GetNodesForZone) ~= "function" or type(GM.DecodeLoc) ~= "function" then
    return nil, "NEED_GM2"
  end
  mapID = mapID or ns.GetPlayerMapID()
  if not mapID then
    return nil, "NO_MAP"
  end

  local filterSet
  if type(nodeFilter) == "table" and next(nodeFilter) then
    filterSet = {}
    for _, id in pairs(nodeFilter) do
      filterSet[id] = true
    end
  end

  local out = {}
  for coord, nodeID in GM:GetNodesForZone(mapID, GATHER_TYPE, true) do
    if not filterSet or filterSet[nodeID] then
      local x, y = GM:DecodeLoc(coord)
      if x and y then
        local name
        if type(GM.GetNameForNode) == "function" then
          name = GM:GetNameForNode(GATHER_TYPE, nodeID)
        end
        out[#out + 1] = { x = x, y = y, nodeID = nodeID, name = name, coord = coord }
      end
    end
  end
  return out
end

local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

local function dist2(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return dx * dx + dy * dy
end

--- Greedy nearest-neighbor closed loop over clusters (MVP — not full TSP).
--- @param clusters from ns.ClusterNodes
--- @param start {x,y}|nil  prefer nearest cluster to this point (player)
--- @param maxStops number|nil
--- @return path { {x,y,count} } including return-to-start duplicate at end when #path>=2
function ns.BuildGreedyLoop(clusters, start, maxStops)
  if not clusters or #clusters == 0 then
    return {}
  end
  maxStops = maxStops or 40

  -- Optional: keep densest clusters if over cap
  local pool = {}
  for i, c in ipairs(clusters) do
    pool[i] = c
  end
  if #pool > maxStops then
    table.sort(pool, function(a, b) return a.count > b.count end)
    while #pool > maxStops do
      table.remove(pool)
    end
  end

  local remaining = {}
  for i, c in ipairs(pool) do
    remaining[i] = c
  end

  local function takeNearest(from)
    local bestI, bestD
    for i, c in ipairs(remaining) do
      local d = dist2(from, c)
      if not bestD or d < bestD then
        bestI, bestD = i, d
      end
    end
    return table.remove(remaining, bestI)
  end

  local origin = start or { x = 0.5, y = 0.5 }
  local path = {}
  local current = takeNearest(origin)
  path[1] = current

  while #remaining > 0 do
    current = takeNearest(current)
    path[#path + 1] = current
  end

  if #path >= 2 then
    path[#path + 1] = { x = path[1].x, y = path[1].y, count = path[1].count, close = true }
  end
  return path
end

function ns.BuildHerbRouteForMap(mapID)
  local db = ns.GetDB()
  local nodes, err = ns.CollectHerbNodes(mapID, db.nodeFilter)
  if not nodes then
    return nil, err
  end
  if #nodes == 0 then
    return nil, "NO_NODES"
  end
  local clusters = ns.ClusterNodes(nodes, db.clusterCell)
  if #clusters < 2 then
    return nil, "ROUTE_EMPTY"
  end

  local start
  if GetPlayerMapPosition then
    -- Classic-safe attempt; may be nil indoors / no map
    local ok, px, py = pcall(function()
      if C_Map and C_Map.GetPlayerMapPosition and mapID then
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then
          return pos:GetXY()
        end
      end
    end)
    if ok and px and py then
      start = { x = px, y = py }
    end
  end

  local path = ns.BuildGreedyLoop(clusters, start, db.maxStops)
  return {
    mapID = mapID,
    nodes = nodes,
    clusters = clusters,
    path = path,
  }
end

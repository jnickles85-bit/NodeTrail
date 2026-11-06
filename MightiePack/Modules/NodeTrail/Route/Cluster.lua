local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

--- Bucket nodes into grid cells, return centroids.
--- @param nodes { {x,y,...} }
--- @param cell number  fraction of map (e.g. 0.03)
--- @return clusters { {x=, y=, count=, members=} }
function ns.ClusterNodes(nodes, cell)
  cell = cell or 0.03
  if cell <= 0 then cell = 0.03 end
  local buckets = {}
  for _, n in ipairs(nodes) do
    local cx = math.floor(n.x / cell)
    local cy = math.floor(n.y / cell)
    local key = cx .. ":" .. cy
    local b = buckets[key]
    if not b then
      b = { sx = 0, sy = 0, count = 0, members = {} }
      buckets[key] = b
    end
    b.sx = b.sx + n.x
    b.sy = b.sy + n.y
    b.count = b.count + 1
    b.members[#b.members + 1] = n
  end
  local clusters = {}
  for _, b in pairs(buckets) do
    clusters[#clusters + 1] = {
      x = b.sx / b.count,
      y = b.sy / b.count,
      count = b.count,
      members = b.members,
    }
  end
  return clusters
end

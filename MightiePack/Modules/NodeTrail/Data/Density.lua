local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

local D = {}
ns.Density = D

D.CELL = 0.02
D.WARM = 0.4
D.ANCHOR_CELL = 0.06
D.SMOOTH = 2
D.MAX_STOPS = 40

local function dist(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

function D.Build(points, opts)
  if not points or #points == 0 then
    return nil, "NO_HERB_DATA"
  end

  opts = opts or {}
  local cell = opts.cell or D.CELL
  local warm = opts.warm or D.WARM
  local anchorCell = opts.anchorCell or D.ANCHOR_CELL
  local smooth = opts.smooth or D.SMOOTH
  local maxStops = opts.maxStops or D.MAX_STOPS

  local heat = {}
  local maxHeat = 0

  for _, p in ipairs(points) do
    local cx = math.floor(p.x / cell)
    local cy = math.floor(p.y / cell)
    local function addHeat(nx, ny, val)
      local key = nx .. ":" .. ny
      heat[key] = (heat[key] or 0) + val
      if heat[key] > maxHeat then
        maxHeat = heat[key]
      end
    end
    addHeat(cx, cy, 1.0)
    addHeat(cx + 1, cy, 0.5)
    addHeat(cx - 1, cy, 0.5)
    addHeat(cx, cy + 1, 0.5)
    addHeat(cx, cy - 1, 0.5)
    addHeat(cx + 1, cy + 1, 0.25)
    addHeat(cx + 1, cy - 1, 0.25)
    addHeat(cx - 1, cy + 1, 0.25)
    addHeat(cx - 1, cy - 1, 0.25)
  end

  local thr = warm * maxHeat
  local groups = {}
  local used = 0

  for _, p in ipairs(points) do
    local cx = math.floor(p.x / cell)
    local cy = math.floor(p.y / cell)
    local h = heat[cx .. ":" .. cy] or 0
    if h >= thr then
      used = used + 1
      local ax = math.floor(p.x / anchorCell)
      local ay = math.floor(p.y / anchorCell)
      local key = ax .. ":" .. ay
      local g = groups[key]
      if not g then
        g = { sx = 0, sy = 0, sw = 0, n = 0 }
        groups[key] = g
      end
      g.sx = g.sx + p.x * h
      g.sy = g.sy + p.y * h
      g.sw = g.sw + h
      g.n = g.n + 1
    end
  end

  local anchors = {}
  for _, g in pairs(groups) do
    anchors[#anchors + 1] = {
      x = g.sx / g.sw,
      y = g.sy / g.sw,
      weight = g.sw,
      count = g.n
    }
  end

  table.sort(anchors, function(a, b)
    if a.weight ~= b.weight then
      return a.weight > b.weight
    end
    if a.x ~= b.x then
      return a.x < b.x
    end
    return a.y < b.y
  end)

  if #anchors > maxStops then
    for i = #anchors, maxStops + 1, -1 do
      anchors[i] = nil
    end
  end

  if #anchors < 2 then
    return nil, "ROUTE_EMPTY"
  end

  local tour = { anchors[1] }
  local remaining = {}
  for i = 2, #anchors do
    remaining[i - 1] = anchors[i]
  end

  while #remaining > 0 do
    local bestI, bestD
    local current = tour[#tour]
    for i, c in ipairs(remaining) do
      local d = dist(current, c)
      if not bestD or d < bestD then
        bestI, bestD = i, d
      end
    end
    tour[#tour + 1] = table.remove(remaining, bestI)
  end

  local n = #tour
  if n >= 4 then
    local improved = true
    while improved do
      improved = false
      for i = 1, n - 2 do
        for j = i + 2, n do
          if not (i == 1 and j == n) then
            local a = tour[i]
            local b = tour[i + 1]
            local c = tour[j]
            local e = tour[j % n + 1]
            if dist(a, c) + dist(b, e) < dist(a, b) + dist(c, e) - 1e-9 then
              local lo, hi = i + 1, j
              while lo < hi do
                tour[lo], tour[hi] = tour[hi], tour[lo]
                lo = lo + 1
                hi = hi - 1
              end
              improved = true
            end
          end
        end
      end
    end
  end

  local pts = {}
  for i, a in ipairs(tour) do
    pts[i] = { x = a.x, y = a.y }
  end

  if #pts >= 3 then
    for _ = 1, smooth do
      local newPts = {}
      for i = 1, #pts do
        local a = pts[i]
        local b = pts[i % #pts + 1]
        newPts[#newPts + 1] = { x = 0.75 * a.x + 0.25 * b.x, y = 0.75 * a.y + 0.25 * b.y }
        newPts[#newPts + 1] = { x = 0.25 * a.x + 0.75 * b.x, y = 0.25 * a.y + 0.75 * b.y }
      end
      pts = newPts
    end
  end

  pts[#pts + 1] = { x = pts[1].x, y = pts[1].y, close = true }

  return {
    path = pts,
    anchors = tour,
    maxHeat = maxHeat,
    threshold = thr,
    used = used,
    total = #points
  }
end

function ns.BuildDensityRouteForMap(mapID)
  if not mapID then
    return nil, "NO_MAP"
  end
  local db = ns.GetDB()
  local herbs = ns.GetHerbDB()
  local list = herbs.maps[mapID]
  if not list or #list == 0 then
    return nil, "NO_HERB_DATA"
  end

  local r, err = D.Build(list, {
    cell = db.densityCell,
    warm = db.densityWarm,
    anchorCell = db.densityAnchorCell,
    smooth = db.densitySmooth,
    maxStops = db.maxStops
  })
  if not r then
    return nil, err
  end

  return {
    mapID = mapID,
    path = r.path,
    anchors = r.anchors,
    stops = #r.anchors,
    picks = #list,
    source = "density"
  }
end

function ns.BuildRouteForMap(mapID)
  local db = ns.GetDB()
  if db.routeSource == "gm2" then
    local route, err = ns.BuildHerbRouteForMap(mapID)
    if route then
      route.source = "gm2"
      route.stops = math.max(0, #route.path - 1)
    end
    return route, err
  end
  return ns.BuildDensityRouteForMap(mapID)
end

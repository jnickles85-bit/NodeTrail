local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."
local pkg = {}
local function loadAddon(path)
  local chunk, loadErr = loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. path)
  assert(chunk, loadErr)
  chunk("MightiePack", pkg)
  return pkg.NodeTrail
end
time = time or os.time -- WoW global used by ns.RecordHerb

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. msg .. "\n")
  end
end

local frameCreated = false
function CreateFrame() frameCreated = true end
function CopyTable(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = CopyTable(v) end
  return r
end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

local ns = loadAddon("locale/enUS.lua")
ns = loadAddon("Config.lua")
ns = loadAddon("Data/Recorder.lua")
ns = loadAddon("Data/Density.lua")

local seed = 12345
local function rnd()
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed / 2147483648
end

local function ringPoints(n)
  local pts = {}
  for i = 0, n - 1 do
    local angle = i * 2 * math.pi / n
    local x = 0.5 + 0.3 * math.cos(angle) + (rnd() - 0.5) * 0.02
    local y = 0.5 + 0.3 * math.sin(angle) + (rnd() - 0.5) * 0.02
    pts[i + 1] = { x = x, y = y }
  end
  return pts
end

local function distToRing(p)
  return math.abs(math.sqrt((p.x - 0.5)^2 + (p.y - 0.5)^2) - 0.3)
end

-- 1. Empty
local r, err = ns.Density.Build({})
check(r == nil and err == "NO_HERB_DATA", "empty points")
r, err = ns.Density.Build(nil)
check(r == nil and err == "NO_HERB_DATA", "nil points")

-- 2. One pick
r, err = ns.Density.Build({ {x=0.2, y=0.2} })
check(r == nil and err == "ROUTE_EMPTY", "one pick")

-- 3. Sparse
r, err = ns.Density.Build({ {x=0.2, y=0.2}, {x=0.6, y=0.6} })
check(r ~= nil, "two far picks")
if r then
  check(#r.path == 3, "two far picks path length")
  check(r.path[1].x == r.path[3].x and r.path[1].y == r.path[3].y and r.path[3].close == true, "two far picks closed")
  check(#r.anchors == 2, "two far picks anchors")
  check(r.used == 2, "two far picks used")
end

r, err = ns.Density.Build({ {x=0.2, y=0.2}, {x=0.6, y=0.6}, {x=0.8, y=0.8} })
check(r ~= nil, "three far picks")
if r then
  check(#r.anchors == 3, "three far picks anchors")
  check(r.used == 3, "three far picks used")
  check(#r.path == 13, "three far picks path length")
end

-- 4. Dense belt
local pts = ringPoints(120)
pts[#pts + 1] = { x = 0.05, y = 0.05 }
pts[#pts + 1] = { x = 0.95, y = 0.1 }
pts[#pts + 1] = { x = 0.1, y = 0.92 }
r, err = ns.Density.Build(pts)
check(r ~= nil, "dense belt")
if r then
  check(r.used <= 120, "dense belt used")
  local ok = true
  for _, p in ipairs(r.path) do
    if distToRing(p) >= 0.03 then ok = false break end
  end
  check(ok, "dense belt corridor")
  check(#r.anchors < 120 and #r.anchors <= 40, "dense belt anchors")
  check(r.path[#r.path].close == true, "dense belt closed")
end

-- 5. No self-crossing
if r and #r.anchors >= 4 then
  local tour = r.anchors
  local n = #tour
  local function orient(a, b, c)
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
  end
  local function onSegment(a, b, c)
    return math.min(a.x, b.x) <= c.x and c.x <= math.max(a.x, b.x) and
           math.min(a.y, b.y) <= c.y and c.y <= math.max(a.y, b.y)
  end
  local function intersect(a, b, c, d)
    local o1 = orient(a, b, c)
    local o2 = orient(a, b, d)
    local o3 = orient(c, d, a)
    local o4 = orient(c, d, b)
    if o1 * o2 < 0 and o3 * o4 < 0 then return true end
    if o1 == 0 and onSegment(a, c, b) then return true end
    if o2 == 0 and onSegment(a, d, b) then return true end
    if o3 == 0 and onSegment(c, a, d) then return true end
    if o4 == 0 and onSegment(c, b, d) then return true end
    return false
  end
  local crossed = false
  for i = 1, n do
    for j = i + 1, n do
      if not (j == i or j == i % n + 1 or i == j % n + 1) then
        if intersect(tour[i], tour[i % n + 1], tour[j], tour[j % n + 1]) then
          crossed = true
        end
      end
    end
  end
  check(not crossed, "no self-crossing")
end

-- 5b. 2-opt removes a crossing that the nearest-neighbour tour would make on these 5 picks
do
  local t = ns.Density.Build({ {x=0.29,y=0.54}, {x=0.4,y=0.58}, {x=0.6,y=0.15}, {x=0.11,y=0.77}, {x=0.31,y=0.29} })
  local function orient(a, b, c) return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) end
  local function cross(a, b, c, d) return orient(a, b, c) * orient(a, b, d) < 0 and orient(c, d, a) * orient(c, d, b) < 0 end
  local crossed = false
  local n = t and #t.anchors or 0
  for i = 1, n do
    for j = i + 2, n do
      if not (i == 1 and j == n) and cross(t.anchors[i], t.anchors[i % n + 1], t.anchors[j], t.anchors[j % n + 1]) then
        crossed = true
      end
    end
  end
  check(n == 5 and not crossed, "2-opt untangles the 5-pick tour")
end

-- 6. Denser data
local pts20 = {}
for i = 1, 20 do pts20[i] = ringPoints(120)[i] end
local r20 = ns.Density.Build(pts20)
local r120 = ns.Density.Build(ringPoints(120))
check(r120.anchors and r20.anchors and #r120.anchors >= #r20.anchors, "denser data grows path")

-- 7. maxStops
r = ns.Density.Build(ringPoints(200), { maxStops = 10 })
check(r and #r.anchors == 10, "maxStops respected")

-- 8. Deterministic
local input = ringPoints(50)
local r1 = ns.Density.Build(input)
local r2 = ns.Density.Build(input)
check(#r1.path == #r2.path and r1.path[1].x == r2.path[1].x and r1.path[1].y == r2.path[1].y, "deterministic")

-- 9. Map wiring
NodeTrailDB = nil
local route, err = ns.BuildDensityRouteForMap(1429)
check(route == nil and err == "NO_HERB_DATA", "map wiring no data")
route, err = ns.BuildDensityRouteForMap(nil)
check(route == nil and err == "NO_MAP", "map wiring no map")

local ring = ringPoints(60)
for _, p in ipairs(ring) do
  ns.RecordHerb(1429, p.x, p.y, {})
end
route, err = ns.BuildDensityRouteForMap(1429)
check(route ~= nil, "map wiring route")
if route then
  check(route.mapID == 1429, "map wiring mapID")
  check(route.source == "density", "map wiring source")
  check(route.picks == 60, "map wiring picks")
  check(#route.path >= 3, "map wiring path")
  check(route.stops == #route.anchors, "map wiring stops")
end

-- 10. Source switch
check(ns.BuildRouteForMap(1429).source == "density", "source switch default")
ns.GetDB().routeSource = "gm2"
ns.BuildHerbRouteForMap = function(m) return { mapID = m, path = { {x=0, y=0}, {x=1, y=1}, {x=0, y=0} } } end
local gm2route = ns.BuildRouteForMap(1429)
check(gm2route.source == "gm2" and gm2route.stops == 2, "source switch gm2")
ns.GetDB().routeSource = "density"

-- 11. Old profile
NodeTrailDB = { profile = { maxStops = 40 } }
local ring7 = ringPoints(30)
for _, p in ipairs(ring7) do
  ns.RecordHerb(7, p.x, p.y, {})
end
local oldRoute = ns.BuildDensityRouteForMap(7)
check(oldRoute ~= nil, "old profile works")
check(NodeTrailDB.profile.routeSource == nil, "old profile no routeSource")

-- 12. frameCreated
check(frameCreated == false, "frameCreated false")

if failed > 0 then
  os.exit(1)
else
  print("density_spec: ok")
end

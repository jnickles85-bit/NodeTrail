-- route_auto_spec.lua — t_2bc15917
--
-- Mightie: "yes it needs to be automated for sure, at least on /reloads".
--
-- Before this change ns.StartRoute() ran ONLY from /nt start and /nt reload,
-- so a route he started was gone after a /reload and never reflected the
-- herbs gathered since. This spec drives the real files (Config, Recorder,
-- Density, Cluster, Build, Route/Auto, Core) through the real paths:
--
--   (1) Enable() with a saved intent builds AND draws the route, with no
--       slash command at all;
--   (2) /nt stop, then a simulated reload (same SavedVariables, fresh
--       package) builds nothing;
--   (3) picks only SCHEDULE a rebuild; advancing the controller frame's
--       OnUpdate past the debounce rebuilds exactly once, trigger "pick";
--   (4) a rebuild with zero anchors / an empty path keeps the drawn route;
--   (5) a route saved for another mapID draws nothing until the map changes;
--   (6) an intent older than routeMaxAgeHours is not resurrected, and says why;
--   (7) /nt status reports active / map / auto-refresh / last rebuild+trigger
--       / points;
--   (8) auto-refresh off means picks never schedule anything.
--
-- Every assertion reads the real namespace state (ns.activeRoute, the
-- controller's state, NodeTrailDB) or the chat lines the real code printed.
-- Nothing re-implements BuildRouteForMap: the route in these assertions is
-- the one Data/Density.lua actually produced from the seeded picks.
--
-- RED on 6254920: NodeTrailDB.route does not exist there, Enable() never
-- builds, RecordHerb never schedules, and /nt status has no state line.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

-- ── chat capture ─────────────────────────────────────────────────────
local chat = {}
DEFAULT_CHAT_FRAME = {
  AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end,
}
local function clearChat()
  for i = #chat, 1, -1 do chat[i] = nil end
end
local function chatText()
  return table.concat(chat, "\n")
end
local function chatHas(needle)
  return chatText():find(needle, 1, true) ~= nil
end

function CopyTable(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = CopyTable(v) end
  return r
end

-- ── the fake client ──────────────────────────────────────────────────
-- Only the surfaces these files touch. CreateFrame records scripts and
-- events so the spec can fire the controller's real OnUpdate/OnEvent.
local frames = {}
CreateFrame = function(kind, name, parent, template)
  local f = {
    kind = kind or "Frame",
    Name = name,
    template = template,
    scripts = {},
    events = {},
  }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:GetScript(n) return self.scripts[n] end
  frames[#frames + 1] = f
  return f
end

SlashCmdList = {}
StaticPopupDialogs = {}
StaticPopup_Show = function() end
ReloadUI = function() end
GetSpellInfo = function() return nil end

-- Two clocks, exactly like the client: GetTime is the monotonic game clock
-- the debounce runs on, time() is the calendar clock startedAt is written in.
local clock = 1000
local wall = 1762600000 -- 2026-11-08, roughly
GetTime = function() return clock end
time = function() return wall end
date = function() return "12:00:00" end

local mapID = 1429
C_Map = {
  GetBestMapForUnit = function() return mapID end,
  GetPlayerMapPosition = function() return nil end,
}

-- ── loading (TOC order for the files a route needs) ─────────────────
local FILES = {
  "locale/enUS.lua",
  "Config.lua",
  "Data/GM2.lua",
  "Data/ItemNames.lua",
  "Data/Recorder.lua",
  "Data/Density.lua",
  "Route/Cluster.lua",
  "Route/Build.lua",
  "Route/Auto.lua",
  "Core.lua",
}

-- The two draw sinks. In game they are the real world-map overlay and the
-- minimap drawer; here they record what the production code asked them to
-- draw, which is the only thing "drawn" can mean without a client.
local function loadClient(saved)
  NodeTrailDB = saved
  frames = {}
  local pkg = { modState = { NodeTrail = true } }
  pkg.IsModuleEnabled = function(n) return pkg.modState[n] end
  pkg.RegisterModule = function(name, def) pkg.registered = def end
  for _, f in ipairs(FILES) do
    -- A file the commit under test does not have (Route/Auto.lua is new in
    -- this card) is skipped, so the run reaches the behavioural checks and
    -- fails there instead of dying in the loader.
    local chunk = loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. f)
    if chunk then
      chunk("MightiePack", pkg)
    end
  end
  local ns = pkg.NodeTrail

  -- Same reason: a client with no controller gets an inert shape, so every
  -- assertion below reports FAIL rather than raising on a nil index.
  if type(ns.RouteAuto) ~= "table" then
    ns.RouteAuto = {
      state = {},
      Rebuild = function() return nil, "no route controller" end,
      SchedulePick = function() return false end,
      Cancel = function() end,
      OnEnable = function() return false end,
      OnEvent = function() end,
    }
  end

  local draw = { world = 0, minimap = 0, cleared = 0, last = nil }
  ns.MapOverlay = {
    SetRoute = function(self, route) draw.world = draw.world + 1; draw.last = route end,
    Clear = function(self) draw.cleared = draw.cleared + 1 end,
  }
  ns.MinimapPath = {
    SetRoute = function(self, route) draw.minimap = draw.minimap + 1 end,
    Clear = function(self) draw.cleared = draw.cleared + 1 end,
  }
  ns.Tooltip = { _enabled = false, Enable = function(self) self._enabled = true end }
  return pkg, ns, draw
end

local function controllerFrame()
  for i = #frames, 1, -1 do
    local f = frames[i]
    if f.Name == "MightiePackNodeTrailRouteAuto" then
      return f
    end
  end
  return nil
end

-- Twelve picks in two tight clusters: the same shape Data/Density.lua
-- groups into two anchors (verified by the assertions on path length).
local function seedHerbs(picksByMap)
  local herbs = { schema = 1, total = 0, maps = {} }
  for map, _ in pairs(picksByMap) do
    local list = {}
    for i = 1, 6 do
      list[#list + 1] = { x = 0.300 + i * 0.004, y = 0.300 + i * 0.004, t = wall, items = {} }
    end
    for i = 1, 6 do
      list[#list + 1] = { x = 0.700 + i * 0.004, y = 0.600 + i * 0.004, t = wall, items = {} }
    end
    herbs.maps[map] = list
    herbs.total = herbs.total + #list
  end
  return { herbs = herbs }
end

local function savedWithIntent(map, opts)
  opts = opts or {}
  local db = seedHerbs({ [1429] = true, [1414] = true })
  db.route = {
    active = true,
    mapID = map,
    startedAt = opts.startedAt or (wall - 60),
    -- t_57550700: ON by default (Mightie's final call); a case that wants it
    -- off says so.
    autoRefresh = opts.autoRefresh ~= false,
  }
  if opts.maxAgeHours then
    db.profile = { routeMaxAgeHours = opts.maxAgeHours }
  end
  return db
end

-- ════════════════════════════════════════════════════════════════════
-- (1) Enable() restores a saved route and draws it — no command.
-- ════════════════════════════════════════════════════════════════════
mapID = 1429
local pkg, ns, draw = loadClient(savedWithIntent(1429))
clearChat()
local okE, errE = pcall(ns.Enable)
check(okE, "(1) Enable() does not error: " .. tostring(errE))
check(ns.activeRoute ~= nil, "(1) a route is built at Enable with no slash command")
if ns.activeRoute then
  check(ns.activeRoute.mapID == 1429, "(1) the route is for the saved mapID")
  check(type(ns.activeRoute.path) == "table" and #ns.activeRoute.path >= 4,
    "(1) the restored route has real geometry (got " .. tostring(#(ns.activeRoute.path or {})) .. " points)")
  check(ns.activeRoute.source == "density", "(1) the route came from the recorded picks (density)")
end
check(draw.world == 1, "(1) the route is drawn on the world map (SetRoute calls: " .. draw.world .. ")")
check(draw.minimap == 1, "(1) the route is drawn on the minimap (SetRoute calls: " .. draw.minimap .. ")")
check(ns.RouteAuto.state.lastTrigger == "login", "(1) the trigger reads login")
check(ns.RouteAuto.state.lastRebuildAt ~= nil, "(1) the rebuild time is recorded")
check(chatHas("route restored"), "(1) the restore is announced in chat (got: " .. chatText():gsub("\n", " | ") .. ")")

-- ════════════════════════════════════════════════════════════════════
-- (7) /nt status says what the controller will do. Driven through the
--     real slash dispatcher on the client that just restored.
-- ════════════════════════════════════════════════════════════════════
local function status()
  clearChat()
  check(type(SlashCmdList.NODETRAIL) == "function", "the real /nt dispatcher is registered")
  local ok, err = pcall(SlashCmdList.NODETRAIL, "status")
  check(ok, "/nt status does not error: " .. tostring(err))
  return chatText()
end

local st = status()
check(st:find("Route state: active yes", 1, true) ~= nil,
  "(7) status shows active yes (got: " .. st:gsub("\n", " | ") .. ")")
check(st:find("map 1429", 1, true) ~= nil, "(7) status shows the stored mapID")
check(st:find("auto-refresh on", 1, true) ~= nil, "(7) status shows auto-refresh on (the default)")
check(st:find("Last rebuild: 12:00:00", 1, true) ~= nil, "(7) status shows the last rebuild time")
check(st:find("trigger login", 1, true) ~= nil, "(7) status shows the rebuild trigger")
check(st:find("points", 1, true) ~= nil, "(7) status shows the point count")
check(st:find("Active route: ", 1, true) ~= nil, "(7) the old 'Active route' line is still there")

-- ════════════════════════════════════════════════════════════════════
-- (2) /nt stop clears the live route AND the intent; the next reload is
--     silent. "Reload" = the same SavedVariables with a fresh package.
-- ════════════════════════════════════════════════════════════════════
clearChat()
pcall(SlashCmdList.NODETRAIL, "stop")
check(ns.activeRoute == nil, "(2) /nt stop clears the live route")
check(type(NodeTrailDB.route) == "table" and NodeTrailDB.route.active == false,
  "(2) /nt stop clears the persisted intent")
check(type(NodeTrailDB.route) == "table" and NodeTrailDB.route.mapID == nil,
  "(2) /nt stop forgets the mapID")
check(chatHas("route cleared"), "(2) /nt stop still says the route is cleared")

local pkg2, ns2, draw2 = loadClient(NodeTrailDB) -- simulated /reload
clearChat()
clock = clock + 100
local ok2 = pcall(ns2.Enable)
check(ok2, "(2) Enable after a stop does not error")
check(ns2.activeRoute == nil, "(2) nothing is built after a reload that followed /nt stop")
check(draw2.world == 0 and draw2.minimap == 0, "(2) nothing is drawn either")
check(ns2.RouteAuto.state.rebuilds == 0, "(2) no rebuild ran")
st = status()
check(st:find("Route state: active no", 1, true) ~= nil, "(2) status says active no after the stop")

-- ════════════════════════════════════════════════════════════════════
-- (3) Picks schedule ONE debounced rebuild — never one per pick, and
--     never synchronously inside the gather event.
-- ════════════════════════════════════════════════════════════════════
mapID = 1429
local pkg3, ns3, draw3 = loadClient(savedWithIntent(1429, { autoRefresh = true }))
pcall(ns3.Enable)
check(ns3.RouteAuto.state.rebuilds == 1, "(3) the login rebuild ran once")
local buildsAfterLogin = ns3.RouteAuto.state.rebuilds
local picksBefore = ns3.activeRoute and ns3.activeRoute.picks or 0
check(picksBefore == 12, "(3) the restored route was built from the 12 seeded picks (got " .. tostring(picksBefore) .. ")")

clock = 200
-- t_57550700: an automatic re-plan needs a tranche of `autoRefreshPicks` (5)
-- new picks, so this section gathers five — the number the counter requires
-- before a window is armed. The wall clock moves past the 30-second floor so
-- the frame's gate lets it through.
wall = wall + 40
for i = 1, 5 do
  clock = clock + 1
  ns3.RecordHerb(1429, 0.1 + i * 0.01, 0.1 + i * 0.01, {})
  check(ns3.RouteAuto.state.rebuilds == buildsAfterLogin,
    "(3) pick " .. i .. " did not rebuild synchronously inside the gather event")
end
check(ns3.RouteAuto.state.dueAt ~= nil, "(3) the picks scheduled a rebuild")
local due = ns3.RouteAuto.state.dueAt

local cf = controllerFrame()
check(cf ~= nil, "(3) the controller created its frame")
check(cf and type(cf.scripts.OnUpdate) == "function", "(3) the controller frame has an OnUpdate")
if cf and cf.scripts.OnUpdate then
  clock = due - 1
  cf.scripts.OnUpdate(cf, 0.1)
  check(ns3.RouteAuto.state.rebuilds == buildsAfterLogin,
    "(3) nothing is rebuilt before the debounce expires")

  clock = due
  cf.scripts.OnUpdate(cf, 0.1)
  check(ns3.RouteAuto.state.rebuilds == buildsAfterLogin + 1,
    "(3) exactly one rebuild after five picks (got "
      .. (ns3.RouteAuto.state.rebuilds - buildsAfterLogin) .. " for five picks)")
  check(ns3.RouteAuto.state.lastTrigger == "pick", "(3) the trigger reads pick")

  -- the rebuild used the picks that landed since the login build
  check(ns3.activeRoute and ns3.activeRoute.picks == picksBefore + 5,
    "(3) the refreshed route is built from the new picks (got "
      .. tostring(ns3.activeRoute and ns3.activeRoute.picks) .. ", expected " .. (picksBefore + 5) .. ")")
  check(draw3.world == 2, "(3) the refreshed route was drawn (SetRoute calls: " .. draw3.world .. ")")

  -- the due time is consumed: the same OnUpdate does not rebuild again
  clock = due + 100
  cf.scripts.OnUpdate(cf, 0.1)
  check(ns3.RouteAuto.state.rebuilds == buildsAfterLogin + 1,
    "(3) the debounce fires once, not on every frame")
end
st = status()
check(st:find("trigger pick", 1, true) ~= nil, "(3) /nt status reports the pick trigger")

-- ════════════════════════════════════════════════════════════════════
-- (4) A rebuild that produces nothing must NOT clear the drawn route.
-- ════════════════════════════════════════════════════════════════════
local kept = ns3.activeRoute
local drawsBefore = draw3.world
local clearsBefore = draw3.cleared
local realBuild = ns3.BuildRouteForMap

ns3.BuildRouteForMap = function(map)
  return { mapID = map, path = {}, anchors = {}, source = "density" }
end
local route4, err4 = ns3.RouteAuto:Rebuild("pick", 1429)
check(route4 == nil, "(4) an empty route is refused")
check(ns3.activeRoute == kept, "(4) the previous route is still the active one")
check(draw3.world == drawsBefore, "(4) nothing was re-drawn over the good route")
check(draw3.cleared == clearsBefore, "(4) the good route was not cleared")
check(type(err4) == "string" and err4 ~= "", "(4) the refusal comes with a reason")

ns3.BuildRouteForMap = function(map)
  return {
    mapID = map,
    path = { { x = 0.1, y = 0.1 }, { x = 0.2, y = 0.2 }, { x = 0.1, y = 0.1 } },
    anchors = { { x = 0.1, y = 0.1 } },
    source = "density",
  }
end
route4, err4 = ns3.RouteAuto:Rebuild("pick", 1429)
check(route4 == nil, "(4) a route with fewer than two anchors is refused")
check(ns3.activeRoute == kept, "(4) the good route survives a one-anchor rebuild")
check(draw3.cleared == clearsBefore, "(4) still nothing cleared")

ns3.BuildRouteForMap = realBuild
route4 = ns3.RouteAuto:Rebuild("manual", 1429)
check(route4 ~= nil and ns3.activeRoute == route4,
  "(4) a usable rebuild still replaces the route")

-- ════════════════════════════════════════════════════════════════════
-- (5) A route saved for another mapID draws nothing until the map changes.
-- ════════════════════════════════════════════════════════════════════
mapID = 1429
local pkg5, ns5, draw5 = loadClient(savedWithIntent(1414))
clearChat()
pcall(ns5.Enable)
check(ns5.activeRoute == nil, "(5) nothing is drawn for a route saved on another map")
check(draw5.world == 0 and draw5.minimap == 0, "(5) the draw sinks were never called")
check(type(NodeTrailDB.route) == "table" and NodeTrailDB.route.active == true,
  "(5) the intent is kept")
check(type(NodeTrailDB.route) == "table" and NodeTrailDB.route.mapID == 1414,
  "(5) the saved mapID is kept")
check(chatHas("nothing is drawn"), "(5) the log says why nothing is drawn (got: "
  .. chatText():gsub("\n", " | ") .. ")")

local cf5 = controllerFrame()
check(cf5 and type(cf5.scripts.OnEvent) == "function", "(5) the controller listens for the map change")
if cf5 and cf5.scripts.OnEvent then
  cf5.scripts.OnEvent(cf5, "PLAYER_ENTERING_WORLD") -- still on 1429
  check(ns5.activeRoute == nil, "(5) an event on the wrong map still draws nothing")

  mapID = 1414 -- the player travels to the route's map
  cf5.scripts.OnEvent(cf5, "PLAYER_ENTERING_WORLD")
  check(ns5.activeRoute ~= nil, "(5) the route is built once the player is on its map")
  check(ns5.activeRoute and ns5.activeRoute.mapID == 1414,
    "(5) it is the route for the saved map, not the current one")
  check(draw5.world == 1, "(5) and it is drawn (SetRoute calls: " .. draw5.world .. ")")
  check(ns5.RouteAuto.state.lastTrigger == "login", "(5) the map-change rebuild is a login-trigger rebuild")

  -- a second arrival re-draws, it does not rebuild
  local rebuilds5 = ns5.RouteAuto.state.rebuilds
  cf5.scripts.OnEvent(cf5, "PLAYER_ENTERING_WORLD")
  check(ns5.RouteAuto.state.rebuilds == rebuilds5,
    "(5) arriving again with the route in memory redraws instead of rebuilding")
  check(draw5.world == 2, "(5) ...and it does redraw (SetRoute calls: " .. draw5.world .. ")")
end

-- ════════════════════════════════════════════════════════════════════
-- (6) A startedAt older than the configured age is not resurrected, and
--     the log says why. Raising the limit makes it come back.
-- ════════════════════════════════════════════════════════════════════
mapID = 1429
local staleDB = savedWithIntent(1429, { startedAt = wall - 25 * 3600 })
local pkg6, ns6, draw6 = loadClient(staleDB)
clearChat()
pcall(ns6.Enable)
check(ns6.activeRoute == nil, "(6) a 25h-old route is not resurrected")
check(draw6.world == 0, "(6) nothing is drawn")
check(chatHas("not rebuilt"), "(6) the log says the route was not rebuilt (got: "
  .. chatText():gsub("\n", " | ") .. ")")
check(chatHas("24h"), "(6) the log names the 24h limit")
check(type(NodeTrailDB.route) == "table" and NodeTrailDB.route.active == true,
  "(6) the intent is kept so /nt start still works")

-- The age is configurable (profile.routeMaxAgeHours): at 48h it is fresh
-- again, and the very same saved intent restores.
NodeTrailDB.profile = { routeMaxAgeHours = 48 }
local pkg6b, ns6b, draw6b = loadClient(NodeTrailDB)
clearChat()
pcall(ns6b.Enable)
check(ns6b.activeRoute ~= nil, "(6) raising routeMaxAgeHours to 48 lets the 25h-old route restore")
check(draw6b.world == 1, "(6) ...and draw it")

-- ════════════════════════════════════════════════════════════════════
-- (8) Auto-refresh off: the route still comes back, but picks never
--     schedule a rebuild; the sub-option is visible and persisted.
-- ════════════════════════════════════════════════════════════════════
mapID = 1429
local pkg8, ns8, draw8 = loadClient(savedWithIntent(1429, { autoRefresh = false }))
pcall(ns8.Enable)
check(ns8.activeRoute ~= nil, "(8) the route still restores with auto-refresh off")
local builds8 = ns8.RouteAuto.state.rebuilds
clock = clock + 10
ns8.RecordHerb(1429, 0.5, 0.5, {})
check(ns8.RouteAuto.state.dueAt == nil, "(8) no rebuild is scheduled while auto-refresh is off")
local cf8 = controllerFrame()
clock = clock + 600
if cf8 and cf8.scripts.OnUpdate then
  cf8.scripts.OnUpdate(cf8, 0.1)
end
check(ns8.RouteAuto.state.rebuilds == builds8, "(8) no rebuild runs while auto-refresh is off")
st = status()
check(st:find("auto-refresh off", 1, true) ~= nil, "(8) status shows auto-refresh off")

check(type(ns8.SetAutoRefreshRoute) == "function", "(8) NodeTrail exposes the sub-option setter")
local isAuto = (type(ns8.IsAutoRefreshRoute) == "function") and ns8.IsAutoRefreshRoute()
check(isAuto == false, "(8) the off state is persisted")
if type(ns8.SetAutoRefreshRoute) == "function" then
  ns8.SetAutoRefreshRoute(true)
end
check(type(NodeTrailDB.route) == "table" and NodeTrailDB.route.autoRefresh == true,
  "(8) turning it on persists at NodeTrailDB.route.autoRefresh")
-- t_57550700: a re-plan is triggered by a TRANCHE of picks — five by default —
-- so it takes five gathers to arm one, not one. The pick recorded above while
-- the switch was off already counts (a pick is a pick).
while (ns8.RouteAuto.state.pendingPicks or 0) < 4 do
  clock = clock + 1
  local n = ns8.RouteAuto.state.pendingPicks or 0
  ns8.RecordHerb(1429, 0.52 + n * 0.001, 0.52, {})
end
check(ns8.RouteAuto.state.dueAt == nil, "(8) four gathers are one short of the tranche")
clock = clock + 1
ns8.RecordHerb(1429, 0.53, 0.53, {})
check(ns8.RouteAuto.state.dueAt ~= nil, "(8) with it on again, five gathers schedule a rebuild")

-- ════════════════════════════════════════════════════════════════════
-- (9) /nt start SETS the intent (and a start that builds nothing leaves
--     no false intent behind), so what /nt start does is what a reload
--     does later.
-- ════════════════════════════════════════════════════════════════════
mapID = 1429
local pkg9, ns9, draw9 = loadClient({ herbs = { schema = 1, total = 0, maps = {} } })
pcall(ns9.Enable) -- registers this package's own /nt dispatcher
clearChat()
pcall(SlashCmdList.NODETRAIL, "start")
check(ns9.activeRoute == nil, "(9) /nt start with no picks builds nothing")
check(type(NodeTrailDB.route) == "table" and NodeTrailDB.route.active == false,
  "(9) a start that built nothing leaves no false intent behind")
check(chatHas("no herbs recorded"), "(9) the refusal says why (got: "
  .. chatText():gsub("\n", " | ") .. ")")

NodeTrailDB.herbs.maps[1429] = seedHerbs({ [1429] = true }).herbs.maps[1429]
clearChat()
pcall(SlashCmdList.NODETRAIL, "start")
check(ns9.activeRoute ~= nil, "(9) /nt start builds a route once there are picks")
check(type(NodeTrailDB.route) == "table" and NodeTrailDB.route.active == true,
  "(9) /nt start sets the persisted intent")
check(type(NodeTrailDB.route) == "table" and NodeTrailDB.route.mapID == 1429,
  "(9) the intent records the mapID")
check(type(NodeTrailDB.route) == "table"
  and type(NodeTrailDB.route.startedAt) == "number" and NodeTrailDB.route.startedAt > 0,
  "(9) the intent records startedAt")
check(ns9.RouteAuto.state.lastTrigger == "manual", "(9) /nt start is a manual rebuild")

local pkg9b, ns9b, draw9b = loadClient(NodeTrailDB)
clearChat()
pcall(ns9b.Enable)
check(ns9b.activeRoute ~= nil, "(9) a route started with /nt start comes back after a reload")
check(chatHas("route restored"), "(9) ...and says so")

-- ════════════════════════════════════════════════════════════════════
-- The intent is intent-only: no geometry is written to SavedVariables.
-- ════════════════════════════════════════════════════════════════════
local r = (type(NodeTrailDB.route) == "table" and NodeTrailDB.route) or {}
check(r.path == nil, "the persisted route carries no path (intent, not geometry)")
check(r.anchors == nil, "the persisted route carries no anchors")
check(r.points == nil, "the persisted route carries no points")

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("route_auto_spec: ok")

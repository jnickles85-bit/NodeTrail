local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

-- ── Route automation (t_2bc15917) ───────────────────────────────────────
-- Mightie: "yes it needs to be automated for sure, at least on /reloads".
--
-- Before this file, ns.StartRoute() ran only from /nt start and /nt reload,
-- so a route he started was gone after a /reload and never reflected the
-- herbs gathered since. This module owns the three automatic paths and the
-- persistence that drives them:
--
--   * Enable()  → a saved route intent, on the map the player is standing
--                 on and younger than the configured ceiling, is rebuilt
--                 and drawn with no command at all            (trigger "login")
--   * a pick    → SchedulePick() only sets a due time; Pump() (the frame's
--                 OnUpdate) rebuilds once, a few seconds after the LAST
--                 pick                                     (trigger "pick")
--   * /nt start, /nt reload                                (trigger "manual")
--
-- Two rules the card makes non-negotiable:
--   1. the persisted state is the INTENT (active/mapID/startedAt/autoRefresh),
--      never the points — the geometry is rebuilt from the picks every time;
--   2. a rebuild that cannot produce a usable route never clears the route
--      that is already drawn. Losing the line because one pick landed in a
--      new zone, or because the debounce fired with no data on the map, is
--      worse than keeping a slightly stale line.

local A = {}
ns.RouteAuto = A

-- Seconds after the last pick before the line is rebuilt. Long enough that
-- a herbing spree is one rebuild, not one per node.
A.DEBOUNCE = 5
A.DEFAULT_MAX_AGE_HOURS = 24

-- Read by /nt status and by the specs. lastRebuildAt/lastTrigger describe the
-- last SUCCESSFUL rebuild; lastSkip describes the last rebuild that refused
-- to replace the drawn route (so the reason is answerable after the fact).
A.state = {
  dueAt = nil,
  lastRebuildAt = nil,
  lastTrigger = nil,
  lastSkip = nil,
  rebuilds = 0,
}

-- ── clocks ────────────────────────────────────────────────────────────
-- GetTime is the game clock the debounce runs on (monotonic, wall-clock
-- seconds). time() is the calendar clock startedAt is written in. Both are
-- resolved at call time and never cached: a client (or a spec) that defines
-- only one of them still works.
local function clock()
  if type(GetTime) == "function" then
    local ok, t = pcall(GetTime)
    if ok and type(t) == "number" then
      return t
    end
  end
  if type(time) == "function" then
    local ok, t = pcall(time)
    if ok and type(t) == "number" then
      return t
    end
  end
  return 0
end

local function wallClock()
  if type(time) == "function" then
    local ok, t = pcall(time)
    if ok and type(t) == "number" then
      return t
    end
  end
  return clock()
end

-- ── chat ──────────────────────────────────────────────────────────────
-- Every line is built and printed inside pcall: a route message must never
-- be the reason the restore path dies. The key is looked up lazily so this
-- file works with the real locale table and with a test stub.
local function say(key, ...)
  local msg = (type(ns.L) == "table" and ns.L[key]) or key
  if type(msg) == "string" and select("#", ...) > 0 then
    local okF, formatted = pcall(string.format, msg, ...)
    if okF then msg = formatted end
  end
  msg = tostring(msg)
  if type(DEFAULT_CHAT_FRAME) == "table" and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
    local ok = pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, msg)
    if ok then
      return msg
    end
  end
  pcall(print, msg)
  return msg
end

local function durationText(seconds)
  local s = math.floor(tonumber(seconds) or 0)
  if s >= 3600 then
    return ("%dh"):format(math.floor(s / 3600 + 0.5))
  end
  if s >= 60 then
    return ("%dm"):format(math.floor(s / 60 + 0.5))
  end
  return ("%ds"):format(s)
end
A.DurationText = durationText

-- ── usable-route guard ─────────────────────────────────────────────────
-- A route is only allowed to replace the drawn one when it has geometry:
-- at least two points in the path, and — when the builder reports anchors
-- at all — at least two anchors. A gm2 route carries clusters instead of
-- anchors, so a missing `anchors` table is not a failure on its own.
function A:IsUsable(route)
  if type(route) ~= "table" then
    return false, "the rebuild produced no route"
  end
  local path = route.path
  if type(path) ~= "table" or #path < 2 then
    return false, "the rebuild produced an empty route"
  end
  local anchors = route.anchors
  if type(anchors) == "table" and #anchors < 2 then
    return false, "the rebuild produced fewer than two anchors"
  end
  return true
end

-- ── drawing ───────────────────────────────────────────────────────────
-- The two sinks are the only places a route becomes visible. Both are
-- pcall'd: a client without a drawable world map must not cost the minimap
-- line (or the reverse).
function A:Draw(route)
  if type(route) ~= "table" then
    return false
  end
  local drew = false
  if type(ns.MapOverlay) == "table" and type(ns.MapOverlay.SetRoute) == "function" then
    local ok = pcall(ns.MapOverlay.SetRoute, ns.MapOverlay, route)
    if ok then drew = true end
  end
  if type(ns.MinimapPath) == "table" and type(ns.MinimapPath.SetRoute) == "function" then
    local ok = pcall(ns.MinimapPath.SetRoute, ns.MinimapPath, route)
    if ok then drew = true end
  end
  -- t_d17939c1: the arrow is the followable element, so it is a third sink. A
  -- client without a usable yard scale hides it and says so; it must not cost
  -- the route line (or the reverse).
  local arrow = type(ns.Nav) == "table" and ns.Nav.Arrow or nil
  if type(arrow) == "table" and type(arrow.SetRoute) == "function" then
    local ok = pcall(arrow.SetRoute, arrow, route)
    if ok then drew = true end
  end
  return drew
end

-- ── rebuild ───────────────────────────────────────────────────────────
-- Build the route for mapID from the recorded picks and draw it. Returns
-- (route) on success, (nil, reason) otherwise. On failure NOTHING is
-- cleared: ns.activeRoute and whatever the overlay has on screen stay.
function A:Rebuild(trigger, mapID, opts)
  opts = opts or {}
  local intent = ns.GetRouteDB()
  mapID = tonumber(mapID) or tonumber(intent.mapID)
  if not mapID then
    return nil, "no map is saved with the route"
  end

  if not opts.force then
    local here
    if type(ns.GetPlayerMapID) == "function" then
      local okH, h = pcall(ns.GetPlayerMapID)
      if okH then here = h end
    end
    if here ~= mapID then
      return nil, ("you are on map %s, the route is for map %s"):format(
        tostring(here or "unknown"), tostring(mapID))
    end
  end

  -- Route generation is untouched (heat cells, threshold, anchors, greedy
  -- NN, 2-opt, maxStops all live in Data/Density.lua). This only decides
  -- whether the result may replace what is already drawn.
  local okB, route, err = pcall(ns.BuildRouteForMap, mapID)
  if not okB then
    return nil, "the route builder failed: " .. tostring(route)
  end
  local usable, why = self:IsUsable(route)
  if not usable then
    self.state.lastSkip = {
      at = wallClock(),
      trigger = trigger,
      reason = (type(err) == "string" and err) or why,
    }
    return nil, (type(err) == "string" and err) or why
  end

  ns.activeRoute = route
  self:Draw(route)
  self.state.lastRebuildAt = wallClock()
  self.state.lastTrigger = trigger
  self.state.rebuilds = (self.state.rebuilds or 0) + 1
  self.state.lastSkip = nil
  return route
end

-- ── debounced refresh on picks ─────────────────────────────────────────
-- Called from ns.RecordHerb AFTER the pick is stored. It never builds
-- synchronously inside the loot/gather event — it only moves the due time.
-- Each pick pushes the due time out, so a run of picks is one rebuild.
function A:SchedulePick(mapID)
  local intent = ns.GetRouteDB()
  if intent.active ~= true then
    return false, "no route is running"
  end
  if intent.autoRefresh ~= true then
    return false, "auto-refresh is off"
  end
  if not mapID or tonumber(mapID) ~= tonumber(intent.mapID) then
    return false, "the pick is on another map"
  end
  self.state.dueAt = clock() + (tonumber(self.DEBOUNCE) or 5)
  return true
end

-- The frame's OnUpdate. One rebuild at most per due window.
function A:Pump(t)
  local due = self.state.dueAt
  if not due then
    return false
  end
  t = tonumber(t) or clock()
  if t < due then
    return false
  end
  self.state.dueAt = nil
  local route, err = self:Rebuild("pick")
  if route then
    say("ROUTE_REFRESHED", #(route.path or {}), route.picks or 0)
    return true
  end
  say("ROUTE_KEPT", tostring(err or "the rebuild produced nothing"))
  return false
end

function A:Cancel()
  self.state.dueAt = nil
end

-- ── frame ──────────────────────────────────────────────────────────────
-- One frame, created at Enable: OnUpdate carries the debounce, OnEvent the
-- map-return redraw. Every call is pcall'd because CreateFrame/SetScript
-- surfaces differ between clients (and between test stubs).
function A:EnsureFrame()
  if type(self.frame) == "table" then
    return self.frame
  end
  if type(CreateFrame) ~= "function" then
    return nil
  end
  local ok, frame = pcall(CreateFrame, "Frame", "MightiePackNodeTrailRouteAuto")
  if not ok or type(frame) ~= "table" then
    return nil
  end
  self.frame = frame
  pcall(frame.SetScript, frame, "OnUpdate", function()
    A:OnUpdate()
  end)
  pcall(frame.SetScript, frame, "OnEvent", function(_, event)
    A:OnEvent(event)
  end)
  pcall(frame.RegisterEvent, frame, "PLAYER_ENTERING_WORLD")
  return frame
end

function A:OnUpdate()
  if not self.state.dueAt then
    return
  end
  self:Pump(clock())
end

-- ── restore at enable (a login and a /reload both run this) ────────────
function A:OnEnable()
  self:EnsureFrame()
  self:Cancel()

  local intent = ns.GetRouteDB()
  if intent.active ~= true then
    return false
  end

  local mapID = tonumber(intent.mapID)
  if not mapID then
    say("ROUTE_KEPT", "the saved route has no map")
    return false
  end

  -- Age ceiling: a route started more than routeMaxAgeHours ago is not the
  -- route that was running. Say so instead of resurrecting it silently.
  local startedAt = tonumber(intent.startedAt) or 0
  local now = wallClock()
  if startedAt > 0 and now > 0 then
    local age = now - startedAt
    local hours = A.DEFAULT_MAX_AGE_HOURS
    if type(ns.GetRouteMaxAgeHours) == "function" then
      local okM, h = pcall(ns.GetRouteMaxAgeHours)
      if okM and tonumber(h) then
        hours = tonumber(h)
      end
    end
    local maxAge = hours * 3600
    if age > maxAge then
      say("ROUTE_STALE", durationText(age), durationText(maxAge))
      return false
    end
  end

  local here
  if type(ns.GetPlayerMapID) == "function" then
    local okH, h = pcall(ns.GetPlayerMapID)
    if okH then here = h end
  end
  if here ~= mapID then
    -- Keep the intent: the overlay stays empty until the player is back on
    -- the route's map, and PLAYER_ENTERING_WORLD rebuilds it there.
    -- A nil/unknown map is not "another map" — at ADDON_LOADED the unit
    -- position can still be unavailable, and the world event right after
    -- login is the answer. Only a real, different map is worth a line.
    if type(here) == "number" then
      say("ROUTE_OTHER_MAP", tostring(mapID), tostring(here))
    end
    return false
  end

  local route, err = self:Rebuild("login", mapID)
  if not route then
    say("ROUTE_KEPT", tostring(err or "the rebuild produced nothing"))
    return false
  end
  say("ROUTE_RESTORED", #(route.path or {}), route.picks or 0, tostring(mapID))
  return true
end

function A:OnEvent(event)
  if event ~= "PLAYER_ENTERING_WORLD" then
    return
  end
  local intent = ns.GetRouteDB()
  if intent.active ~= true then
    return
  end
  local mapID = tonumber(intent.mapID)
  if not mapID then
    return
  end
  local here
  if type(ns.GetPlayerMapID) == "function" then
    local okH, h = pcall(ns.GetPlayerMapID)
    if okH then here = h end
  end
  if here ~= mapID then
    return -- another map: the intent is kept, nothing is drawn
  end

  local live = ns.activeRoute
  if type(live) == "table" and live.mapID == mapID
    and type(live.path) == "table" and #live.path >= 2 then
    -- Back on the route's map with the route still in memory: redraw it
    -- (the overlay hid it while the other map was open). Not a rebuild.
    self:Draw(live)
    return
  end

  local route, err = self:Rebuild("login", mapID)
  if route then
    say("ROUTE_RESTORED", #(route.path or {}), route.picks or 0, tostring(mapID))
  elseif err then
    say("ROUTE_KEPT", tostring(err))
  end
end

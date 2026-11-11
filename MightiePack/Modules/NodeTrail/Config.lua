local _, pkg = ...
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
    -- t_d17939c1: the followable element. A world-anchored line on a
    -- player-centred minimap slides under the player, so the NEXT waypoint is
    -- named by an arrow with the yards counting down. navRange is how far away
    -- a waypoint may be before the arrow hides instead of drawing a marker on
    -- the ring for something in another zone.
    -- OFF by default (Mightie, 2026-11-08: "Please don't replace this requirement
    -- with a waypoint arrow ... an arrow is optional and comes later."). The
    -- route line on both maps is the product; this arrow is opt-in via
    -- /nt arrow on and must never appear uninvited.
    showNavArrow = false,
    navRange = 1200,
    navArriveYards = 12,
    routeSource = "density", -- "density" (our recorded herbs) or "gm2" (GatherMate2 nodes, optional fallback)
    densityCell = 0.02,
    densityWarm = 0.4,
    densityAnchorCell = 0.06,
    densitySmooth = 2,
    -- t_2bc15917: how old a saved route intent may be before a login
    -- refuses to resurrect it (hours). A route started three days ago is
    -- not "the route you were running" any more.
    routeMaxAgeHours = 24,
    -- Recipe-uses line in the herb tooltip: parked off (Mightie, 2026-11-09).
    -- The scan and the gate keep running; this only hides the line. It lives on
    -- the PROFILE because that is where Tooltip.lua reads it from — inside
    -- `route` it was written but never read, so the parked feature could not have
    -- been switched back on.
    showAlchemyUses = false,
  },
  -- t_5507a0ba: the skinning probe is NodeTrail's sub-feature, so its
  -- sub-toggle lives in NodeTrail's own saved variable (top level, NOT
  -- inside profile and NOT in MightiePackDB.modules).
  -- t_ba64b076: ON by default. The recorder shipped off while the event
  -- surface was unverified; recording is the product now, so a fresh install
  -- records from the first corpse with no setup. The old default is carried
  -- over by the one-time migration in ns.GetSkinDB, and an explicit off
  -- (Options box or /nt skin off) is remembered through skinUserSet.
  skinning = {
    enabled = true,
  },
  -- t_b46e5e87: the skinning farming circle. Its own switch, separate from the
  -- probe (NodeTrailDB.skinning.enabled) and from the herb route: the circle is
  -- an overlay layer, not a recording mode. ON by default because the circle is
  -- a feature Mightie asked for and it cannot draw anything until this map has
  -- recorded SKINNED corpses (Route/SkinRoute.lua refuses below the sample
  -- floor) and the character answers the Skinning gate.
  skinroute = {
    enabled = true,
  },
  -- t_2bc15917 / t_57550700: the route INTENT, never its geometry. The points
  -- are rebuilt from the recorded picks at every enable; only "was a route
  -- running, on which map, since when, and does it follow new picks" is
  -- written to SavedVariables.
  --
  -- Mightie, gathering south of Crossroads, watched a second line start to fill
  -- in with no reload: every pick used to move a debounced re-plan of the WHOLE
  -- zone route, so the ground he was walking changed under his feet.
  --
  -- His final decision (2026-11-08): "change from minutes to every 5 gathers.
  -- doesnt need to come off by default." So:
  --   * autoRefresh stays ON by default (it is the feature he asked for);
  --   * a re-plan is triggered by PICKS, not by a clock: autoRefreshPicks (=5)
  --     new picks since the plan on screen was built;
  --   * at most one re-plan per tranche of five — the counter resets with the
  --     plan, so a burst of gathers is one re-plan, not one per herb;
  --   * never in combat, never with a loot window open, never inside the
  --     30-second floor after the previous plan.
  -- /nt autorefresh on|off|<picks>.
  route = {
    active = false,
    mapID = nil,
    startedAt = 0,
    autoRefresh = true,
    autoRefreshPicks = 5,
  },
}

-- Fill in keys a saved profile is missing, recursively, without touching a value
-- the player already has. Adding a setting in a later build used to leave existing
-- profiles without the key: every read then returned nil and the setting behaved as
-- "off" for exactly the people who had already used the addon. That is how the
-- arrow's old default outlived the new one.
local function fillMissing(target, defaults)
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      if type(target[k]) ~= "table" then target[k] = {} end
      fillMissing(target[k], v)
    elseif target[k] == nil then
      target[k] = v
    end
  end
end

function ns.GetDB()
  if type(NodeTrailDB) ~= "table" then
    NodeTrailDB = CopyTable(ns.defaults)
  end
  if type(NodeTrailDB.profile) ~= "table" then
    NodeTrailDB.profile = CopyTable(ns.defaults.profile)
  end
  fillMissing(NodeTrailDB, ns.defaults)
  -- The waypoint arrow shipped default-ON by mistake before it was parked, so a
  -- profile written by that build stored `showNavArrow = true`. Changing the
  -- default cannot undo a stored value, and that is exactly what happened: the
  -- arrow came back on a build whose default is false. Only an explicit
  -- /nt arrow switch counts as the player's choice, so anything else is forced
  -- off once. Turning it on by hand sets the flag and sticks from then on.
  if NodeTrailDB.profile.navArrowMigration ~= 2 then
    if NodeTrailDB.profile.navArrowUserSet ~= true then
      NodeTrailDB.profile.showNavArrow = false
    end
    NodeTrailDB.profile.navArrowMigration = 2
  end
  return NodeTrailDB.profile
end

-- ── Skinning sub-toggle (t_5507a0ba) ────────────────────────────────
-- Persisted at NodeTrailDB.skinning.enabled, default true (t_ba64b076).
-- Filled in lazily so a NodeTrailDB written before this key existed keeps
-- every other key it already has (a saved profile is never replaced).
function ns.GetSkinDB()
  if type(NodeTrailDB) ~= "table" then
    NodeTrailDB = CopyTable(ns.defaults)
  end
  if type(NodeTrailDB.skinning) ~= "table" then
    NodeTrailDB.skinning = { enabled = true }
  end
  if type(NodeTrailDB.skinning.enabled) ~= "boolean" then
    NodeTrailDB.skinning.enabled = true
  end
  -- t_ba64b076: the same shape as the arrow's migration in ns.GetDB, on the
  -- value it owns. The recorder shipped default-OFF, so a bucket written by
  -- that build stored `false`. Changing the default cannot undo a stored
  -- value, so an install that carries the old default is flipped ON once.
  -- Only an explicit switch (the Options checkbox or /nt skin, both of which
  -- go through ns.SetSkinningEnabled) sets skinUserSet, so a player's own
  -- "off" is never overridden — not by this migration, by a later one, or by
  -- a /reload. The marker is written either way, so this runs exactly once.
  local db = NodeTrailDB.skinning
  if db.skinMigration ~= 1 then
    if db.skinUserSet ~= true then
      db.enabled = true
    end
    db.skinMigration = 1
  end
  return db
end

function ns.IsSkinningEnabled()
  return ns.GetSkinDB().enabled == true
end

function ns.SetSkinningEnabled(on)
  local db = ns.GetSkinDB()
  db.enabled = on and true or false
  -- This is the player asking, not a default: it must outlive the migration
  -- above and every future one. Writes from the Options checkbox and from
  -- /nt skin both land here, so there is one flag and one meaning.
  db.skinUserSet = true
  return db.enabled
end

-- ── Skinning farming circle switch (t_b46e5e87) ─────────────────────
-- Persisted at NodeTrailDB.skinroute.enabled, filled in lazily like the
-- other keys: a NodeTrailDB written before this key existed keeps every
-- other key it already has. Default ON — the circle is drawn only when the
-- character is a skinner AND this map has enough of his own skinned
-- corpses, so an untouched zone stays empty either way.
function ns.GetSkinRouteDB()
  if type(NodeTrailDB) ~= "table" then
    NodeTrailDB = CopyTable(ns.defaults)
  end
  if type(NodeTrailDB.skinroute) ~= "table" then
    NodeTrailDB.skinroute = { enabled = true }
  end
  if type(NodeTrailDB.skinroute.enabled) ~= "boolean" then
    NodeTrailDB.skinroute.enabled = true
  end
  return NodeTrailDB.skinroute
end

function ns.IsSkinRouteEnabled()
  return ns.GetSkinRouteDB().enabled == true
end

function ns.SetSkinRouteEnabled(on)
  ns.GetSkinRouteDB().enabled = on and true or false
  return NodeTrailDB.skinroute.enabled
end

-- ── Route intent (t_2bc15917) ────────────────────────────────────────
-- NodeTrailDB.route records only what the player asked for: a route is
-- running, on which mapID, since when (wall clock, seconds), and whether
-- it should follow new picks. The computed points are deliberately NOT
-- persisted — they are rebuilt from the recorded herbs at every enable,
-- so the line always matches the picks that actually exist.
--
-- Filled in lazily, key by key, exactly like GetSkinDB: a NodeTrailDB
-- written before this key existed keeps every other key it already has.
function ns.GetRouteDB()
  if type(NodeTrailDB) ~= "table" then
    NodeTrailDB = CopyTable(ns.defaults)
  end
  if type(NodeTrailDB.route) ~= "table" then
    NodeTrailDB.route = {}
  end
  local r = NodeTrailDB.route
  if type(r.active) ~= "boolean" then r.active = false end
  if type(r.startedAt) ~= "number" then r.startedAt = 0 end
  if type(r.autoRefresh) ~= "boolean" then r.autoRefresh = true end
  -- The tranche size: how many new picks make a re-plan due. Clamped and
  -- written back, so what /nt status prints is what is in force. 1 would be
  -- "one re-plan per pick" again, which is the bug; the floor is 2.
  local n = tonumber(r.autoRefreshPicks)
  if not n or n ~= n then n = 5 end
  n = math.floor(n + 0.5)
  if n < 2 then n = 2 end
  if n > 100 then n = 100 end
  r.autoRefreshPicks = n
  return r
end

function ns.GetAutoRefreshPicks()
  return tonumber(ns.GetRouteDB().autoRefreshPicks) or 5
end

function ns.SetAutoRefreshPicks(count)
  local r = ns.GetRouteDB()
  local n = tonumber(count)
  if not n or n ~= n then
    return r.autoRefreshPicks
  end
  n = math.floor(n + 0.5)
  if n < 2 then n = 2 end
  if n > 100 then n = 100 end
  r.autoRefreshPicks = n
  return n
end

function ns.IsAutoRefreshRoute()
  return ns.GetRouteDB().autoRefresh == true
end

function ns.SetAutoRefreshRoute(on)
  local r = ns.GetRouteDB()
  r.autoRefresh = on and true or false
  return r.autoRefresh
end

-- The configurable age ceiling for a resurrected route (hours, profile).
function ns.GetRouteMaxAgeHours()
  local db = ns.GetDB()
  local hours = tonumber(db.routeMaxAgeHours)
  if not hours or hours <= 0 then
    hours = 24
  end
  return hours
end

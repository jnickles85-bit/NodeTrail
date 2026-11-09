-- SkinRoute.lua — t_b46e5e87 (skinning farming circles).
--
-- Mightie, 2026-11-09: "I think we should test and add in the skinning farming
-- circles before pushing to curseforge."
--
-- The skinning recorder (Modules/Skinning/Record.lua) already stores, per
-- corpse, the map and the position it was recorded at: record.map, record.x,
-- record.y. Those positions have never been used for routing. This file turns
-- them into a FARMING CIRCLE per zone: a closed loop through the places this
-- character actually killed and skinned, built from his own database only.
--
-- Rules this file keeps (they are the feature, not decoration):
--
--   * OWN DATABASE ONLY. The only input is pkg.Skinning.Recorder's per-character
--     store. No researched spawn data, no GatherMate2, no drop rates, no
--     percentages — this file counts positions and nothing else.
--   * SKINNED FIRST. The operator's rule: "no need to draw something until its
--     been skinned in that area." A record only counts when a successful
--     Skinning cast was attributed to that corpse (record.skinned == true). A
--     recorded kill the player never skinned is not a farming stop.
--   * PER MAP. Records are filtered by record.map == the map being drawn. A
--     busy map must never light up a zone with no data of its own.
--   * HONEST SAMPLE. Below MIN_SKINS skinned corpses, or with fewer than
--     MIN_CLUSTERS occupied cells, NO route is returned and the caller is told
--     how many more are needed. Three corpses in one camp is a dot, not a
--     circle.
--   * READ, NEVER WRITE. Nothing here writes into the skinning store or into
--     NodeTrailDB.herbs. Skinning data never feeds the herb route (they are
--     separate namespaces and separate generators).
--
-- Minimum sample, and why 8: the herb route grids the map at 0.03 (3% of the
-- map per cell) and ns.ClusterNodes keeps one centroid per occupied cell. A
-- CLOSED loop needs at least three distinct clusters (two clusters give a
-- there-and-back line, one gives a point). With 3-4 corpses the sample is
-- almost always one camp -> one or two cells, and the "circle" degenerates to a
-- dot or a line. 8 skinned corpses on one map is the smallest floor that, in
-- practice, spans the 3+ cells a farming patch has (a pull camp plus the mobs
-- walked between two camps), while still being reachable in a single session
-- of real play (~10 minutes of killing and skinning). It is deliberately a
-- count of SKINNED corpses, not kills: the circle is for where skinning
-- happened.

local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

ns.SkinRoute = ns.SkinRoute or {}
local S = ns.SkinRoute

-- Below this many SKINNED corpses on one map, nothing is drawn and the status
-- says how many more are needed. See the header for the reasoning.
S.MIN_SKINS = 8
-- A closed circuit needs three distinct cluster centroids; two make a line.
S.MIN_CLUSTERS = 3
-- The same 3%-of-map grid the herb route uses (Config.clusterCell), so both
-- surfaces group nearby positions the same way. Deliberately NOT read from the
-- herb profile: the skinning circle must not change when the player edits the
-- herb cluster cell.
S.CELL = 0.03
S.MAX_STOPS = 40
-- Green. The herb route is white (Config.pathColor = {1,1,1,0.9}), so a
-- screenshot cannot confuse the two lines; the colour is passed to the draw,
-- never read back from the herb profile.
S.COLOR = { 0.10, 0.85, 0.35, 0.95 }
S.WIDTH = 2

local function recorder()
  local sk = pkg.Skinning
  if type(sk) ~= "table" then
    return nil
  end
  local R = sk.Recorder
  if type(R) ~= "table" or type(R.GetDB) ~= "function" then
    return nil
  end
  return R
end
S.Recorder = recorder

local function isValidFraction(v)
  return type(v) == "number" and v == v and v >= 0 and v <= 1
end

--- The skinned positions this character recorded on ONE map.
--- Only records with a confirmed Skinning cast (rec.skinned == true) and a
--- stored map position count. The store is READ; no bucket is created here.
--- @param mapID number|nil
--- @return { {x=,y=,guid=} }, why|nil
function S:SkinnedPoints(mapID)
  local pts = {}
  if type(mapID) ~= "number" then
    return pts, "NO_MAP"
  end
  local R = recorder()
  if not R then
    return pts, "NO_RECORDER"
  end
  -- GetDB() bootstraps the bucket for THIS character; it is the same store the
  -- beast panel reads, so the circle can never see another character's kills.
  local ok, store = pcall(R.GetDB, R)
  if not ok or type(store) ~= "table" then
    return pts, "NO_STORE"
  end
  local records = type(store.records) == "table" and store.records or {}
  local order = type(store.order) == "table" and store.order or {}
  for i = 1, #order do
    local rec = records[order[i]]
    if type(rec) == "table"
      and rec.skinned == true
      and rec.map == mapID
      and isValidFraction(rec.x)
      and isValidFraction(rec.y) then
      pts[#pts + 1] = { x = rec.x, y = rec.y, guid = rec.guid }
    end
  end
  return pts
end

--- What the circle would use on this map, and whether that is enough.
--- Never returns a route: the caller decides what to do with a refusal, and
--- the maps stay clean (operator rule: nothing is drawn until the area has
--- been skinned).
--- @return status { mapID, count, min, needed, clusters, clustersNeeded,
---                   ok, why }, clusters, points
function S:Status(mapID)
  if type(mapID) ~= "number" and type(ns.GetPlayerMapID) == "function" then
    local ok, here = pcall(ns.GetPlayerMapID)
    if ok then mapID = here end
  end
  local points, ptsWhy = self:SkinnedPoints(mapID)
  local clusters = {}
  if type(ns.ClusterNodes) == "function" and #points > 0 then
    clusters = ns.ClusterNodes(points, self.CELL)
  end
  local st = {
    mapID = mapID,
    count = #points,
    min = self.MIN_SKINS,
    needed = math.max(0, self.MIN_SKINS - #points),
    clusters = #clusters,
    minClusters = self.MIN_CLUSTERS,
    clustersNeeded = math.max(0, self.MIN_CLUSTERS - #clusters),
    pointsWhy = ptsWhy,
  }
  if type(mapID) ~= "number" then
    st.why = "NO_MAP"
  elseif #points == 0 then
    st.why = "NO_SKINNING"
  elseif #points < self.MIN_SKINS then
    st.why = "TOO_FEW"
  elseif #clusters < self.MIN_CLUSTERS then
    st.why = "TOO_SPREAD"
  else
    st.ok = true
  end
  return st, clusters, points
end

--- The one human sentence the panel and /nt skinroute share. It ALWAYS states
--- the count needed when nothing can be drawn, and it is never printed by the
--- map layers themselves.
function S:StatusText(mapID)
  local st = self:Status(mapID)
  local map = tostring(st.mapID or "?")
  if st.ok then
    return ("skinning circle: %d skinned corpses on map %s over %d clusters — drawn"):format(
      st.count, map, st.clusters)
  end
  if st.why == "NO_MAP" then
    return "skinning circle: no current map — nothing can be drawn"
  end
  local line = ("skinning circle: %d of %d skinned corpses on map %s — %d more needed"):format(
    st.count, st.min, map, st.needed)
  if st.why == "NO_SKINNING" then
    return line .. " (kill, loot and skin a mob to start)"
  end
  if st.why == "TOO_SPREAD" then
    return line .. (" (only %d cluster(s) of %d: %d more cell(s) must be used)"):format(
      st.clusters, st.minClusters, st.clustersNeeded)
  end
  return line .. " before a circle is drawn"
end

local function playerStart()
  if type(GetPlayerMapPosition) ~= "function" and type(C_Map) ~= "table" then
    return nil
  end
  local ok, px, py = pcall(function()
    if C_Map and C_Map.GetPlayerMapPosition and type(ns.GetPlayerMapID) == "function" then
      local mapID = ns.GetPlayerMapID()
      if not mapID then return nil end
      local pos = C_Map.GetPlayerMapPosition(mapID, "player")
      if pos and type(pos.GetXY) == "function" then
        return pos:GetXY()
      end
    end
  end)
  if ok and isValidFraction(px) and isValidFraction(py) then
    return { x = px, y = py }
  end
  return nil
end

--- Build the closed farming circle for ONE map from this character's own
--- recorded skins. Returns nil + a reason when there is not enough honest data;
--- the overlays are never asked to draw a guess.
--- @return route|nil, reason|nil, status
function ns.BuildSkinRouteForMap(mapID)
  local S = ns.SkinRoute
  if type(S) ~= "table" then
    return nil, "NO_GENERATOR"
  end
  local st, clusters, points = S:Status(mapID)
  if not st.ok then
    return nil, st.why or "NO_DATA", st
  end
  mapID = st.mapID
  -- The same greedy nearest-neighbour loop the herb route uses, so the shape
  -- and the "densest clusters" ordering are one implementation, not two.
  local path = ns.BuildGreedyLoop(clusters, playerStart(), S.MAX_STOPS)
  if not path or #path < 4 then
    -- Fewer than three stops cannot close a circuit: refuse rather than draw a
    -- line that pretends to be a circle.
    st.ok = false
    st.why = "ROUTE_EMPTY"
    return nil, st.why, st
  end
  return {
    mapID = mapID,
    path = path,
    clusters = clusters,
    points = points,
    source = "skinning",       -- never "density": different data, different generator
    color = S.COLOR,
    width = S.WIDTH,
    stops = #path - 1,         -- the closing duplicate is not a stop
  }, nil, st
end

-- ── the layer refresh (gate + build + draw) ─────────────────────────────────
-- One entry point for every caller (the slash command, the options checkbox,
-- the zone-change driver and NodeTrail's Enable), so the gate cannot be
-- skipped on one path and honoured on another.
--
-- The profession gate is the SAME shared helper the beast panel uses
-- (ns.Profession:Skinning, t_c0221fd7): true = skinner, false = not, nil =
-- unreadable. Only a definitive true draws; a non-skinner and an unreadable
-- client both leave the maps clean and print nothing (a hidden circle on a
-- real skinner is diagnosed through /nt ttdiag).
function ns.RefreshSkinRoute()
  local overlay = ns.MapOverlay
  local minimap = ns.MinimapPath
  local function clearBoth()
    if type(overlay) == "table" and type(overlay.ClearSkinRoute) == "function" then
      pcall(overlay.ClearSkinRoute, overlay)
    end
    if type(minimap) == "table" and type(minimap.ClearSkinRoute) == "function" then
      pcall(minimap.ClearSkinRoute, minimap)
    end
  end
  if not ns.IsSkinRouteEnabled() then
    clearBoth()
    return nil, "OFF"
  end
  local Pr = ns.Profession
  if type(Pr) ~= "table" or type(Pr.Skinning) ~= "function" then
    clearBoth()
    return nil, "NO_GATE"
  end
  local okG, answer = pcall(Pr.Skinning, Pr)
  if not okG then
    clearBoth()
    return nil, "GATE_ERROR"
  end
  if answer ~= true then
    clearBoth()
    return nil, (answer == false) and "NOT_SKINNER" or "GATE_UNREADABLE"
  end
  local route, err = ns.BuildSkinRouteForMap(nil)
  if not route then
    clearBoth()
    return nil, err
  end
  if type(overlay) == "table" and type(overlay.SetSkinRoute) == "function" then
    pcall(overlay.SetSkinRoute, overlay, route)
  end
  if type(minimap) == "table" and type(minimap.SetSkinRoute) == "function" then
    pcall(minimap.SetSkinRoute, minimap, route)
  end
  return route
end

--- /nt skinroute [on|off|status]
function ns.SkinRouteCommand(arg)
  arg = tostring(arg or ""):lower():match("^%s*(.-)%s*$") or ""
  local function say(text)
    if type(DEFAULT_CHAT_FRAME) == "table" and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
      pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, text)
    else
      pcall(print, text)
    end
  end
  if arg == "on" or arg == "off" then
    local on = (arg == "on")
    ns.SetSkinRouteEnabled(on)
    local route, why = ns.RefreshSkinRoute()
    if not on then
      say("NodeTrail skinroute: off — the skinning circle is cleared; the herb route is untouched.")
    elseif route then
      say(("NodeTrail skinroute: on — %d-point circle over %d clusters on map %s."):format(
        #route.path, #route.clusters, tostring(route.mapID)))
    elseif why == "NOT_SKINNER" then
      say("NodeTrail skinroute: on, but this character has no Skinning — nothing is drawn.")
    elseif why == "GATE_UNREADABLE" or why == "NO_GATE" then
      say("NodeTrail skinroute: on, but this client cannot read the character's professions — nothing is drawn.")
    else
      -- No circle yet: say exactly how many more skinned corpses are needed.
      say("NodeTrail skinroute: on, but " .. ns.SkinRoute:StatusText())
    end
    return route
  end
  say("NodeTrail " .. ns.SkinRoute:StatusText())
  return nil
end

-- ── the zone-change driver ──────────────────────────────────────────────────
-- The circle is PER ZONE: walking into another zone must re-evaluate it (build
-- for the new map, or clear because that map has no skinned data of its own).
-- Every call is pcall'd; a driver that raises must never break the addon, and a
-- client that rejects an event name must still get the other ones.
if type(CreateFrame) == "function" then
  local driver = CreateFrame("Frame")
  S._driver = driver
  local function refresh()
    local ok, err = pcall(ns.RefreshSkinRoute)
    if not ok then
      S._error = tostring(err)
    end
  end
  if type(driver.SetScript) == "function" then
    pcall(driver.SetScript, driver, "OnEvent", function(_, event)
      if event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA"
        or event == "PLAYER_ENTERING_WORLD" then
        refresh()
      end
    end)
  end
  if type(driver.RegisterEvent) == "function" then
    local events = { "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }
    for i = 1, #events do
      pcall(driver.RegisterEvent, driver, events[i])
    end
  end
end


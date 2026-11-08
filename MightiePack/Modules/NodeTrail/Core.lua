local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

NodeTrail = ns
ns.version = "0.2.0"
ns.activeRoute = nil

local L = ns.L

local function printL(key, ...)
  local msg = L[key] or key
  if select("#", ...) > 0 then
    msg = msg:format(...)
  end
  DEFAULT_CHAT_FRAME:AddMessage(msg)
end

local function printHelp()
  printL("HELP")
  printL("HELP_START")
  printL("HELP_STOP")
  printL("HELP_RELOAD")
  printL("HELP_STATUS")
  -- t_36412359. Inline like the ttdiag lines below: the new command is
  -- documented without a new locale entry.
  DEFAULT_CHAT_FRAME:AddMessage(
    "  /nt scanrecipes (alias: /nt recipes) - recipe-scan status; scans now if your Alchemy window is open")
  -- t_0f65b0b9: the world-map overlay diagnostic. Inline like the line above,
  -- so the new command is documented without a new locale entry.
  DEFAULT_CHAT_FRAME:AddMessage(
    "  /nt mapdiag - world-map/minimap frame environment; run this if the route does not appear on the map")
  DEFAULT_CHAT_FRAME:AddMessage(
    "  /nt mapdiag probe [off] - draw a marker, a border and one diagonal line on the map overlay to prove it is visible at all")
  DEFAULT_CHAT_FRAME:AddMessage(
    "  /nt navdiag - what this client can tell us about yards: C_Map, HereBeDragons, zone size, world vector, and the arrow's next waypoint")
  DEFAULT_CHAT_FRAME:AddMessage(
    "  /nt arrow [on|off] - the next-waypoint arrow with the distance counting down")
  printL("HELP_NOTES")
end

local function printReason(reason)
  if type(reason) ~= "string" or reason == "" then
    reason = "ROUTE_EMPTY"
  end
  if L[reason] then
    printL(reason)
  else
    DEFAULT_CHAT_FRAME:AddMessage("NodeTrail: " .. reason)
  end
end

-- /nt stop — clears BOTH the drawn route and the persisted intent, so the
-- next login or /reload stays quiet (t_2bc15917).
function ns.StopRoute()
  ns.activeRoute = nil
  if type(ns.RouteAuto) == "table" and type(ns.RouteAuto.Cancel) == "function" then
    pcall(ns.RouteAuto.Cancel, ns.RouteAuto)
  end
  local intent = ns.GetRouteDB()
  intent.active = false
  intent.mapID = nil
  intent.startedAt = 0
  if ns.MapOverlay then ns.MapOverlay:Clear() end
  if ns.MinimapPath then ns.MinimapPath:Clear() end
  if ns.Nav and ns.Nav.Arrow then
    pcall(ns.Nav.Arrow.Clear, ns.Nav.Arrow)
  end
  printL("ROUTE_STOPPED")
end

-- StartRoute / /nt reload — records the intent first, then rebuilds. The
-- rebuild itself (and the "never replace a good route with nothing" guard)
-- lives in Route/Auto.lua, so the manual, login and pick paths cannot drift
-- apart.
function ns.StartRoute(trigger)
  local mapID = ns.GetPlayerMapID()
  local intent = ns.GetRouteDB()
  intent.active = true
  intent.mapID = mapID
  intent.startedAt = (type(time) == "function" and time() or 0)
  if type(intent.autoRefresh) ~= "boolean" then
    intent.autoRefresh = true
  end

  local route, err
  if type(ns.RouteAuto) == "table" and type(ns.RouteAuto.Rebuild) == "function" then
    route, err = ns.RouteAuto:Rebuild(trigger or "manual", mapID)
  else
    -- The controller did not load: keep the old direct path working.
    route, err = ns.BuildRouteForMap(mapID)
    if route then
      ns.activeRoute = route
      if ns.MapOverlay then ns.MapOverlay:SetRoute(route) end
      if ns.MinimapPath then ns.MinimapPath:SetRoute(route) end
      if ns.Nav and ns.Nav.Arrow then
        pcall(ns.Nav.Arrow.SetRoute, ns.Nav.Arrow, route)
      end
    end
  end

  if not route then
    -- No route is running, so nothing may claim otherwise on the next load.
    intent.active = false
    intent.mapID = nil
    intent.startedAt = 0
    printReason(err)
    return
  end
  local stops = route.stops or math.max(0, #route.path - 1)
  printL("ROUTE_STARTED", stops, route.picks or stops)
end

function ns.PrintStatus()
  printL("STATUS_HEADER")
  local source = (ns.GetDB().routeSource or "density")
  printL("STATUS_SOURCE", source == "gm2" and "gm2 (GatherMate2 nodes)" or "density (your recorded herbs)")
  local mapID = ns.GetPlayerMapID and ns.GetPlayerMapID()
  local herbs = ns.GetHerbDB and ns.GetHerbDB()
  local here = (mapID and herbs and herbs.maps and herbs.maps[mapID]) and #herbs.maps[mapID] or 0
  printL("STATUS_HERBS", mapID and tostring(mapID) or "unknown", here, (herbs and herbs.total) or 0)
  printL("STATUS_ROUTE", ns.activeRoute and (#(ns.activeRoute.path or {}) .. " points, " .. (ns.activeRoute.source or "?")) or "none")
  -- t_2bc15917: the persisted intent and the last rebuild, so /nt status
  -- answers "will my route come back?" without a reload to find out.
  local intent = ns.GetRouteDB()
  printL("STATUS_ROUTE_STATE", intent.active and "yes" or "no",
    intent.mapID and tostring(intent.mapID) or "none",
    (intent.autoRefresh == true) and "on" or "off")
  local rstate = (type(ns.RouteAuto) == "table" and type(ns.RouteAuto.state) == "table")
    and ns.RouteAuto.state or nil
  local when = "never"
  local at = rstate and tonumber(rstate.lastRebuildAt)
  if at then
    local okD, stamp = pcall(date, "%H:%M:%S", at)
    when = (okD and type(stamp) == "string") and stamp or tostring(at)
  end
  printL("STATUS_ROUTE_REBUILD", when, (rstate and rstate.lastTrigger) or "none",
    type(ns.activeRoute) == "table" and #(ns.activeRoute.path or {}) or 0)
  printL("STATUS_TOOLTIP", (ns.Tooltip and ns.Tooltip._enabled) and "on" or "off")
  local scanned = type(NodeTrailDB) == "table" and type(NodeTrailDB.recipes) == "table" and NodeTrailDB.recipes.alchemyScanned
  if scanned then
    local detail = ""
    if ns.Recipes and type(ns.Recipes._diag) == "table" then
      local d = ns.Recipes._diag
      detail = (" (%d recipes, via %s)"):format(
        tonumber(d.recipeCount) or 0,
        tostring(d.path or "unknown"))
    end
    printL("STATUS_ALCHEMY", "scanned" .. detail)
  else
    -- A scan that DID run on this client but could not positively confirm
    -- the open window is Alchemy must not be reported as "open your
    -- Alchemy window once" (a step that was already taken and yielded
    -- nothing verifiable) and not as a success — it says what actually
    -- happened: the client reported no profession name (t_217033d4).
    local gated = nil
    if ns.Recipes and type(ns.Recipes._diag) == "table" then
      gated = ns.Recipes._diag.gated
    end
    if gated == "unknown-profession" then
      printL("STATUS_ALCHEMY",
        "a scan ran, but this client reports no profession name — the open window could not be verified as Alchemy, so its recipes were not saved")
    elseif gated == "no-reagents" then
      -- The Alchemy window WAS open and its recipes were read, but the
      -- client returned no usable reagents (e.g. its schematic call
      -- surface does not match this client). That is an INCOMPLETE scan
      -- — not a success, and not a step the player still has to take;
      -- it retries on the next TRADE_SKILL_SHOW (t_81da8886).
      printL("STATUS_ALCHEMY",
        "a scan ran with the Alchemy window open, but it found no reagents — nothing was saved (the client returned no usable recipe reagents)")
    else
      -- "Open Alchemy once" is only offered while a scan can actually run.
      -- A client with neither the legacy trade-skill globals nor
      -- C_TradeSkillUI can never complete that step — saying why is the
      -- truthful status (t_0d5badc3).
      local avail = false
      if ns.Recipes and type(ns.Recipes.APIInfo) == "function" then
        local okA, a = pcall(ns.Recipes.APIInfo, ns.Recipes)
        if okA and type(a) == "table" then
          avail = a.available == true
        end
      end
      if avail then
        printL("STATUS_ALCHEMY", "open your Alchemy window once")
      elseif ns.Recipes then
        printL("STATUS_ALCHEMY",
          "unavailable on this client (no trade skill API found: C_TradeSkillUI and the legacy trade-skill globals are both absent)")
      else
        printL("STATUS_ALCHEMY", "recipe module not loaded")
      end
    end
  end
  local on = true
  if pkg and type(pkg.IsModuleEnabled) == "function" then
    on = pkg.IsModuleEnabled("NodeTrail") and true or false
  end
  printL("STATUS_MODULE", on and "on" or "off")
end

local function handleSlash(msg)
  msg = (msg or ""):match("^%s*(.-)%s*$") or ""
  msg = msg:lower()
  if msg == "" or msg == "help" then
    printHelp()
  elseif msg == "start" then
    ns.StartRoute()
  elseif msg == "stop" then
    ns.StopRoute()
  elseif msg == "reload" then
    if ns.activeRoute then
      ns.StartRoute("manual")
    else
      printL("NO_ROUTE")
    end
  elseif msg == "status" then
    ns.PrintStatus()
  elseif msg == "scanrecipes" or msg == "recipes" then
    ns.ScanRecipes()
  elseif msg == "mapdiag" or msg:match("^mapdiag%s") then
    -- /nt mapdiag probe [on|off] — the visibility bisect (off by default)
    ns.PrintMapDiag(msg:match("^mapdiag%s+(.*)$"))
  elseif msg == "navdiag" then
    ns.PrintNavDiag()
  elseif msg == "arrow" or msg:match("^arrow%s") then
    ns.ToggleNavArrow(msg:match("^arrow%s+(.*)$"))
  elseif msg == "ttdiag" then
    if type(ns.Tooltip) == "table" and type(ns.Tooltip.Diag) == "function" then
      ns.Tooltip:Diag()
    else
      DEFAULT_CHAT_FRAME:AddMessage("NodeTrail: ttdiag unavailable (tooltip module not loaded)")
    end
    -- Recipes half: which trade-skill API exists and what the last scan
    -- saw (t_0d5badc3) — printed after the tooltip half so its lines
    -- don't split the block.
    if type(ns.Recipes) == "table" and type(ns.Recipes.Diag) == "function" then
      local okR, errR = pcall(ns.Recipes.Diag, ns.Recipes)
      if not okR then
        DEFAULT_CHAT_FRAME:AddMessage("NodeTrail: recipes diag failed: " .. tostring(errR))
      end
    end
  else
    printHelp()
  end
end

-- /nt scanrecipes (alias /nt recipes) — the same line the options
-- panel shows, plus a live scan when the Alchemy window is open
-- (t_36412359). The status is read AFTER the attempt, so it is the
-- current truth; a result message that only repeats the status line
-- is dropped instead of printed twice.
function ns.ScanRecipes()
  local rec = ns.Recipes
  if type(rec) ~= "table" or type(rec.StatusLine) ~= "function" or type(rec.TryScanNow) ~= "function" then
    DEFAULT_CHAT_FRAME:AddMessage("NodeTrail recipes: module not loaded (turn NodeTrail on)")
    return
  end
  local ok, done, msg = pcall(rec.TryScanNow, rec)
  if not ok then
    msg = "NodeTrail recipes: scan failed: " .. tostring(done)
  end
  local okS, line = pcall(rec.StatusLine, rec)
  if okS and type(line) == "string" then
    DEFAULT_CHAT_FRAME:AddMessage("NodeTrail recipes: " .. line)
    if msg == "NodeTrail recipes: " .. line then
      msg = nil
    end
  end
  if msg then
    DEFAULT_CHAT_FRAME:AddMessage(msg)
  end
  return ok and done or false
end

-- /nt mapdiag (t_0f65b0b9) — the world-map overlay has never been confirmed
-- drawing on the Forever client. This prints the frame environment the
-- overlay actually found (canvas or legacy frames, measured sizes, the
-- displayed vs route mapID, what the last redraw queued) so the next in-game
-- run says WHY nothing is visible instead of guessing.
function ns.PrintMapDiag(arg)
  local function say(text)
    local line = "NodeTrail mapdiag: " .. tostring(text)
    if type(DEFAULT_CHAT_FRAME) == "table" and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
      local ok = pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, line)
      if ok then
        return
      end
    end
    pcall(print, line)
  end
  local overlay = ns.MapOverlay
  if type(overlay) ~= "table" or type(overlay.Diag) ~= "function" then
    say("unavailable (map overlay module not loaded)")
    return
  end
  local mode = tostring(arg or ""):lower():match("^%s*(.-)%s*$") or ""
  if mode:match("^probe") then
    if type(overlay.Probe) ~= "function" then
      say("probe unavailable (this MapOverlay has no Probe)")
      return
    end
    local okP, errP = pcall(overlay.Probe, overlay, mode)
    if not okP then
      say("probe failed: " .. tostring(errP))
    end
    -- The probe answers "is the overlay visible at all"; the diag that follows
    -- says what the primitive measurement found, in the same run.
  elseif mode:match("^primitive") then
    if type(overlay.SetPrimitive) ~= "function" then
      say("primitive switch unavailable (this MapOverlay has no SetPrimitive)")
      return
    end
    local want = mode:match("^primitive%s+(.*)$")
    local okS, errS = pcall(overlay.SetPrimitive, overlay, want)
    if not okS then
      say("primitive failed: " .. tostring(errS))
    end
  elseif mode ~= "" then
    say(("unknown option '%s' (try: probe | probe off | primitive <auto|line|dots|rotate>)"):format(mode))
    return
  end
  local ok, err = pcall(overlay.Diag, overlay)
  if not ok then
    say("failed: " .. tostring(err))
  end
end

-- ── /nt navdiag (t_d17939c1) ────────────────────────────────────────────────
-- The Step-1 measurement for the waypoint arrow, printed as plain numbers:
-- which map/world APIs this client has, whether HereBeDragons is reachable as
-- an EXISTING library, and — when it is — the raw world position, the zone size
-- in yards and HBD:GetWorldVector's angle/distance to the first and last route
-- points. Then what the arrow's own chooser picked, so a wrong arrow is
-- attributable to the chooser or to the projection instead of guessed at.
function ns.PrintNavDiag()
  local nav = ns.Nav
  local arrow = type(nav) == "table" and nav.Arrow or nil
  if type(arrow) ~= "table" or type(arrow.Diag) ~= "function" then
    DEFAULT_CHAT_FRAME:AddMessage(
      "NodeTrail navdiag: unavailable (the nav modules did not load)")
    return
  end
  local ok, lines = pcall(arrow.Diag, arrow)
  if not ok then
    DEFAULT_CHAT_FRAME:AddMessage("NodeTrail navdiag: failed: " .. tostring(lines))
    return
  end
  for i = 1, #lines do
    DEFAULT_CHAT_FRAME:AddMessage("NodeTrail navdiag: " .. tostring(lines[i]))
  end
end

-- /nt arrow [on|off] — the waypoint arrow's own switch, kept separate from
-- showMinimap so the followable element can be turned off without losing the
-- nearby-legs hint of the line.
function ns.ToggleNavArrow(arg)
  local profile = ns.GetDB()
  local want = tostring(arg or ""):lower():match("^%s*(.-)%s*$") or ""
  local on
  if want == "on" or want == "1" or want == "true" then
    on = true
  elseif want == "off" or want == "0" or want == "false" then
    on = false
  elseif want == "" then
    on = (profile.showNavArrow == false)
  else
    DEFAULT_CHAT_FRAME:AddMessage("NodeTrail: /nt arrow [on|off]")
    return
  end
  profile.showNavArrow = on
  -- Redraw, never Clear: the arrow keeps the route it was given, so turning it
  -- back on does not need a rebuild.
  local arrow = type(ns.Nav) == "table" and ns.Nav.Arrow or nil
  if type(arrow) == "table" and type(arrow.Redraw) == "function" then
    pcall(arrow.Redraw, arrow)
  end
  DEFAULT_CHAT_FRAME:AddMessage("NodeTrail: waypoint arrow " .. (on and "on" or "off"))
  return on
end

-- ── Skinning probe ownership (t_5507a0ba) ───────────────────────────
-- The probe files stay where they are on disk (Modules/Skinning/, loaded
-- by the TOC) but NodeTrail owns them: nothing starts the probe except
-- NodeTrail's Enable (when the sub-toggle is on) or an explicit
-- /mp skindiag diagnostic. This is why they are no longer a peer module:
-- pkg.Skinning is a namespace here, not an entry in pkg.moduleOrder.
function ns.EnableSkinning()
  local sk = pkg.Skinning
  if type(sk) ~= "table" or type(sk.Enable) ~= "function" then
    return false, "the skinning probe files did not load"
  end
  local ok, err = pcall(sk.Enable)
  if not ok then
    return false, tostring(err)
  end
  return true
end

function ns.DisableSkinning()
  local sk = pkg.Skinning
  if type(sk) ~= "table" or type(sk.Disable) ~= "function" then
    return true
  end
  local ok, err = pcall(sk.Disable)
  if not ok then
    return false, tostring(err)
  end
  return true
end

function ns.Enable()
  if ns.enabled then
    return
  end
  ns.enabled = true
  ns.GetDB()
  if ns.Recorder then
    ns.Recorder:Enable()
  end
  if ns.Recipes then
    ns.Recipes:Enable()
  end
  if ns.Tooltip then
    ns.Tooltip:Enable()
  end
  -- Sub-feature first, module last: a probe that fails must not stop the
  -- herb route from starting (it reports through /mp skindiag instead).
  if ns.IsSkinningEnabled() then
    ns.EnableSkinning()
  end
  -- t_2bc15917: a route the player started earlier comes back by itself —
  -- Enable() is what a login and a /reload both run. The restore never
  -- speaks for a route that was stopped, is on another map, or is older
  -- than routeMaxAgeHours; /nt status says which case it is in.
  if type(ns.RouteAuto) == "table" and type(ns.RouteAuto.OnEnable) == "function" then
    local okR, errR = pcall(ns.RouteAuto.OnEnable, ns.RouteAuto)
    if not okR then
      DEFAULT_CHAT_FRAME:AddMessage("NodeTrail: route restore failed: " .. tostring(errR))
    end
  end
  SLASH_NODETRAIL1 = "/nodetrail"
  SLASH_NODETRAIL2 = "/nt"
  SlashCmdList.NODETRAIL = handleSlash
end

if type(pkg.RegisterModule) == "function" then
  pkg.RegisterModule("NodeTrail", {
    title = "NodeTrail",
    notes = "Herb routes from your own gathers (white path on world map + minimap), herb tooltip. /nt start | stop | reload | status",
    Enable = function() ns.Enable() end,
  })
end

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
  -- t_57550700: the route-stability switch, documented inline like the lines
  -- below so a new command needs no new locale entry.
  DEFAULT_CHAT_FRAME:AddMessage(
    "  /nt autorefresh [on|off|<picks>] - on by default: one re-plan every <picks> gathers (default 5), never in combat or with a loot window open; off keeps the drawn route exactly as it is")
  printL("HELP_MINIMAP",
    "  /nt minimap [on|off] - the minimap line on its own; off clears it immediately, the world map route is unaffected")
  -- t_36412359. Inline like the ttdiag lines below: the new command is
  -- documented without a new locale entry.
  DEFAULT_CHAT_FRAME:AddMessage(
    "  /nt scanrecipes (alias: /nt recipes) - recipe-scan status; scans now if your Alchemy window is open")
  -- t_4ab7c230: the raw per-recipe signal measurement.
  DEFAULT_CHAT_FRAME:AddMessage(
    "  /nt recipediag [id|name] - raw trade-skill values for one craftable and one non-craftable recipe (what this client can actually answer)")
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
  DEFAULT_CHAT_FRAME:AddMessage(
    "  /nt minimap [on|off] - the route drawn on the minimap only (the world map is unaffected)")
  DEFAULT_CHAT_FRAME:AddMessage(
    "  /nt navwalk [start|mark <label>] - record a walk: player coords, the draw-time stamp and the drawn dot's anchors at each stop (saved on /reload)")
  -- t_b46e5e87: the skinning farming circle.
  DEFAULT_CHAT_FRAME:AddMessage(
    "  /nt skinroute [on|off|status] - the green closed loop through where you have skinned on THIS zone's map; off clears it, the herb route is unaffected")
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
  -- t_57550700: both gate values, so "why has my line not moved" is answerable
  -- without a reload: the switch and "3 of 5 picks since the last plan".
  local need = ns.GetAutoRefreshPicks()
  printL("STATUS_ROUTE_GAP", (intent.autoRefresh == true) and "on" or "off",
    need, (rstate and tonumber(rstate.pendingPicks)) or 0, need)
  local when = "never"
  local at = rstate and tonumber(rstate.lastRebuildAt)
  if at then
    local okD, stamp = pcall(date, "%H:%M:%S", at)
    when = (okD and type(stamp) == "string") and stamp or tostring(at)
  end
  printL("STATUS_ROUTE_REBUILD", when, (rstate and rstate.lastTrigger) or "none",
    type(ns.activeRoute) == "table" and #(ns.activeRoute.path or {}) or 0)
  -- t_57550700: with the debounce off, picks pile up instead of re-planning, so
  -- say how many are waiting instead of leaving it silent.
  local waiting = (rstate and tonumber(rstate.pendingPicks)) or 0
  if waiting > 0 then
    printL("STATUS_ROUTE_PENDING", waiting)
  end
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
  elseif msg == "autorefresh" or msg:match("^autorefresh%s") then
    ns.SetAutoRefresh(msg:match("^autorefresh%s+(.*)$"))
  elseif msg == "scanrecipes" or msg == "recipes" then
    ns.ScanRecipes()
  elseif msg == "recipediag" or msg:match("^recipediag%s") then
    ns.PrintRecipeDiag(msg:match("^recipediag%s+(.*)$"))
  elseif msg == "mapdiag" or msg:match("^mapdiag%s") then
    -- /nt mapdiag probe [on|off] — the visibility bisect (off by default)
    ns.PrintMapDiag(msg:match("^mapdiag%s+(.*)$"))
  elseif msg == "navdiag" then
    ns.PrintNavDiag()
  elseif msg == "arrow" or msg:match("^arrow%s") then
    ns.ToggleNavArrow(msg:match("^arrow%s+(.*)$"))
  elseif msg == "minimap" or msg:match("^minimap%s") then
    -- t_86583cf2 (re-scope): the minimap line's own switch, so it can be turned
    -- off without touching the world map route.
    ns.SetMinimapVisible(msg:match("^minimap%s+(.*)$"))
  elseif msg == "navwalk" or msg:match("^navwalk%s") then
    -- t_86583cf2: record Mightie's four-stop walk in his own client.
    ns.NavWalkCommand(msg:match("^navwalk%s+(.*)$"))
  elseif msg == "skinroute" or msg:match("^skinroute%s") then
    -- t_b46e5e87: the skinning farming circle's own switch/status. The circle
    -- is gated on Skinning and on this map's own skinned sample, so the command
    -- can honestly say how many more are needed when it draws nothing.
    ns.SkinRouteCommand(msg:match("^skinroute%s+(.*)$"))
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

-- /nt recipediag [id|name] (t_4ab7c230) — the raw signal measurement, inside
-- the client. The work lives in Data/Recipes.lua (one source of truth for
-- recipe state); this is the guarded entry point the slash handler calls.
function ns.PrintRecipeDiag(arg)
  local rec = ns.Recipes
  if type(rec) ~= "table" or type(rec.RecipeDiag) ~= "function" then
    DEFAULT_CHAT_FRAME:AddMessage("NodeTrail: recipediag unavailable (recipe module not loaded)")
    return
  end
  local ok, err = pcall(rec.RecipeDiag, rec, arg)
  if not ok then
    DEFAULT_CHAT_FRAME:AddMessage("NodeTrail: recipediag failed: " .. tostring(err))
  end
end

-- /nt mapdiag (t_0f65b0b9) — the world-map overlay has never been confirmed
-- drawing on the Forever client. This prints the frame environment the
-- overlay actually found (canvas or legacy frames, measured sizes, the
-- displayed vs route mapID, what the last redraw queued) so the next in-game
-- run says WHY nothing is visible instead of guessing.
-- ── /nt mapdiag parents ───────────────────────────────────────────────────
-- The swatch test proved that even a 40 px OPAQUE texture on the map overlay's
-- own host is invisible on this client, so the question is no longer colour or
-- alpha: it is whether anything parented to that host is composited at all.
-- This paints six large red squares that differ in exactly two variables —
-- which frame they hang from, and whether the colour went in through
-- SetColorTexture or SetTexture+SetVertexColor — and numbers them on screen.
-- Nothing here touches the route, its coordinates or its persistence.
function ns.PrintParentLadder()
  local function say(text)
    local line = "NodeTrail parents: " .. tostring(text)
    if type(DEFAULT_CHAT_FRAME) == "table" and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
      local ok = pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, line)
      if ok then return end
    end
    pcall(print, line)
  end
  if type(CreateFrame) ~= "function" or type(UIParent) ~= "table" then
    say("unavailable (no CreateFrame or UIParent)")
    return
  end
  ns._parentLadder = ns._parentLadder or {}
  for i = 1, #ns._parentLadder do
    pcall(ns._parentLadder[i].Hide, ns._parentLadder[i])
  end
  ns._parentLadder = {}

  local wmf = _G.WorldMapFrame
  local canvas = nil
  if type(wmf) == "table" then
    if type(wmf.GetCanvas) == "function" then
      local ok, c = pcall(wmf.GetCanvas, wmf)
      if ok and type(c) == "table" then canvas = c end
    end
    if not canvas and type(wmf.ScrollContainer) == "table" then
      canvas = wmf.ScrollContainer
    end
  end

  -- 1 UIParent+SetColorTexture  2 UIParent+SetTexture  3 WorldMapFrame+SetColorTexture
  -- 4 canvas+SetColorTexture    5 canvas+SetTexture     6 UIParent 200px (size control)
  local specs = {
    { label = "1", parent = UIParent, tex = "color",  size = 120, dx = -320, dy = 120 },
    { label = "2", parent = UIParent, tex = "vertex", size = 120, dx = -160, dy = 120 },
    { label = "3", parent = wmf,      tex = "color",  size = 120, dx =    0, dy = 120 },
    { label = "4", parent = canvas,   tex = "color",  size = 120, dx =  160, dy = 120 },
    { label = "5", parent = canvas,   tex = "vertex", size = 120, dx =  320, dy = 120 },
    { label = "6", parent = UIParent, tex = "color",  size = 200, dx =    0, dy = -140 },
  }
  for i = 1, #specs do
    local spec = specs[i]
    if type(spec.parent) ~= "table" then
      say(("#%s skipped: that parent frame does not exist on this client"):format(spec.label))
    else
      local ok, frame = pcall(CreateFrame, "Frame", nil, spec.parent)
      if not ok or type(frame) ~= "table" then
        say(("#%s skipped: CreateFrame failed"):format(spec.label))
      else
        pcall(frame.SetFrameStrata, frame, "DIALOG")
        pcall(frame.SetFrameLevel, frame, 900)
        pcall(frame.ClearAllPoints, frame)
        pcall(frame.SetPoint, frame, "CENTER", UIParent, "CENTER", spec.dx, spec.dy)
        pcall(frame.SetSize, frame, spec.size, spec.size)
        local okT, tex = pcall(frame.CreateTexture, frame, nil, "OVERLAY")
        if okT and type(tex) == "table" then
          pcall(tex.SetAllPoints, tex, frame)
          if spec.tex == "color" and type(tex.SetColorTexture) == "function" then
            pcall(tex.SetColorTexture, tex, 1, 0, 0, 1)
          else
            pcall(tex.SetTexture, tex, "Interface\\Buttons\\WHITE8X8")
            pcall(tex.SetVertexColor, tex, 1, 0, 0, 1)
            spec.tex = "vertex"
          end
          pcall(tex.SetDrawLayer, tex, "OVERLAY", 7)
        end
        pcall(frame.Show, frame)
        ns._parentLadder[#ns._parentLadder + 1] = frame
        say(("#%s %dx%d on %s via %s: level=%s strata=%s shown=%s")
          :format(spec.label, spec.size, spec.size,
            tostring(spec.parent == UIParent and "UIParent"
              or (spec.parent == wmf and "WorldMapFrame")
              or (spec.parent == canvas and "map canvas") or "?"),
            tostring(spec.tex), tostring(frame.GetFrameLevel and frame:GetFrameLevel() or "absent"),
            tostring(frame.GetFrameStrata and frame:GetFrameStrata() or "absent"),
            tostring(frame.IsShown and frame:IsShown() or "absent")))
      end
    end
  end
  say("tell me which red squares you can SEE (#1-#6); '/nt mapdiag parents off' removes them")
end

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
  if mode:match("^parents") then
    -- Must not require the overlay to be loaded: the whole point is to test
    -- frames that are NOT the overlay's host.
    local rest = mode:match("^parents%s*(.*)$") or ""
    if rest == "off" or rest == "hide" then
      for i = 1, #(ns._parentLadder or {}) do
        pcall(ns._parentLadder[i].Hide, ns._parentLadder[i])
      end
      ns._parentLadder = {}
      say("parents: off (squares removed)")
    else
      local okP, errP = pcall(ns.PrintParentLadder)
      if not okP then
        say("parents failed: " .. tostring(errP))
      end
    end
    return
  end
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
  elseif mode:match("^compare") then
    if type(overlay.Compare) ~= "function" then
      say("compare unavailable (this MapOverlay has no Compare)")
      return
    end
    local okC, errC = pcall(overlay.Compare, overlay)
    if not okC then
      say("compare failed: " .. tostring(errC))
    end
  elseif mode:match("^floor") then
    -- The visibility ladder's rung 3, without a redeploy: same route, same
    -- coordinates, only the dot's SCREEN size changes.
    if type(overlay.SetDotFloor) ~= "function" then
      say("floor switch unavailable (this MapOverlay has no SetDotFloor)")
      return
    end
    local okF, errF = pcall(overlay.SetDotFloor, overlay, mode:match("^floor%s*(.*)$"))
    if not okF then
      say("floor failed: " .. tostring(errF))
    end
  elseif mode:match("^strata") then
    -- Rung 2: raise the host above whatever is over the map, or prove it is
    -- already above it.
    if type(overlay.SetStrata) ~= "function" then
      say("strata switch unavailable (this MapOverlay has no SetStrata)")
      return
    end
    local okT, errT = pcall(overlay.SetStrata, overlay, mode:match("^strata%s*(.*)$"))
    if not okT then
      say("strata failed: " .. tostring(errT))
    end
  elseif mode ~= "" then
    say(("unknown option '%s' (try: probe | probe off | compare | primitive <auto|line|dots|rotate> | floor <px|auto> | strata <MEDIUM|HIGH|DIALOG|auto>)"):format(mode))
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
  -- An explicit switch: from here on the stored value wins over the opt-in
  -- migration in ns.GetDB, because this is the player asking, not a default.
  profile.navArrowUserSet = true
  -- Redraw, never Clear: the arrow keeps the route it was given, so turning it
  -- back on does not need a rebuild.
  local arrow = type(ns.Nav) == "table" and ns.Nav.Arrow or nil
  if type(arrow) == "table" and type(arrow.Redraw) == "function" then
    pcall(arrow.Redraw, arrow)
  end
  DEFAULT_CHAT_FRAME:AddMessage("NodeTrail: waypoint arrow " .. (on and "on" or "off"))
  return on
end

-- ── /nt minimap [on|off] (t_86583cf2, re-scope) ────────────────────────────
-- Mightie: "Im not sold on the minimap working as I intend. we might abandon the
-- minimap feature for the routing. Having the actual map working 100% is the
-- goal currently." So the minimap line gets its OWN switch: `db.showMinimap`
-- already gates the minimap drawer, and this reaches it from chat without
-- touching showWorldMap — the world map stays exactly as it is.
-- Turning it off CLEARS the minimap drawer (the dots are removed from screen,
-- not merely stopped) and leaves the route object untouched, so turning it back
-- on redraws the same route rather than needing a rebuild.
function ns.SetMinimapVisible(arg)
  local profile = ns.GetDB()  local want = tostring(arg or ""):lower():match("^%s*(.-)%s*$") or ""
  local on
  if want == "on" or want == "1" or want == "true" then
    on = true
  elseif want == "off" or want == "0" or want == "false" then
    on = false
  elseif want == "" then
    on = (profile.showMinimap == false)
  else
    DEFAULT_CHAT_FRAME:AddMessage("NodeTrail: /nt minimap [on|off]")
    return
  end
  profile.showMinimap = on
  local minimap = type(ns.MinimapPath) == "table" and ns.MinimapPath or nil
  if type(minimap) == "table" then
    if on then
      if type(ns.activeRoute) == "table" and type(minimap.SetRoute) == "function" then
        pcall(minimap.SetRoute, minimap, ns.activeRoute)
      end
    elseif type(minimap.Clear) == "function" then
      pcall(minimap.Clear, minimap)
    end
  end
  DEFAULT_CHAT_FRAME:AddMessage("NodeTrail: minimap route " .. (on and "on" or "off")
    .. (on and "" or " (the world map route is unchanged)")
    .. (type(ns.activeRoute) ~= "table" and on and " — no active route to draw" or ""))
  return on
end

-- ── /nt navwalk [start|mark <label>|clear] (t_86583cf2) ───────────────────
-- Mightie's walk test, made recordable: `start` clears the buffer, `mark` records
-- a stop from the drawing on screen, bare `/nt navwalk` prints what was recorded.
-- Everything is also written to NodeTrailDB.navwalk, which the client saves on
-- /reload — so the four-stop table can be read off disk instead of transcribed.
function ns.NavWalkCommand(arg)
  local walk = ns.NavWalk
  if type(walk) ~= "table" then
    DEFAULT_CHAT_FRAME:AddMessage("NodeTrail: navwalk unavailable (minimap module not loaded)")
    return
  end
  local word = tostring(arg or ""):lower():match("^%s*(.-)%s*$") or ""
  local sub, rest = word:match("^(%a+)%s*(.-)$")
  if word == "" then
    local lines = walk:Lines()
    for i = 1, #lines do
      DEFAULT_CHAT_FRAME:AddMessage("NodeTrail " .. tostring(lines[i]))
    end
    return
  end
  if sub == "start" or sub == "begin" then
    walk:Begin()
    DEFAULT_CHAT_FRAME:AddMessage("NodeTrail navwalk: cleared. Stand still at the start and use '/nt navwalk mark start'.")
    return
  end
  if sub == "clear" then
    walk:Clear()
    DEFAULT_CHAT_FRAME:AddMessage("NodeTrail navwalk: cleared (the saved copy is overwritten on /reload).")
    return
  end
  if sub == "mark" then
    local rec, why = walk:Mark(rest == "" and nil or rest)
    if not rec then
      DEFAULT_CHAT_FRAME:AddMessage("NodeTrail navwalk: not recorded — " .. tostring(why))
      return
    end
    local line = walk:Lines()
    DEFAULT_CHAT_FRAME:AddMessage("NodeTrail " .. tostring(line[#line]))
    DEFAULT_CHAT_FRAME:AddMessage("NodeTrail navwalk: stop recorded. Walk on, then '/nt navwalk mark <label>'; '/reload' saves it to disk.")
    return
  end
  DEFAULT_CHAT_FRAME:AddMessage("NodeTrail: /nt navwalk [start|mark <label>|clear] — bare /nt navwalk prints the stops")
end
-- ── /nt autorefresh [on|off|<picks>] (t_57550700) ─────────────────────
-- The switch that decides whether a route keeps following your picks, and how
-- many gathers make a re-plan due. Mightie's final decision: "change from
-- minutes to every 5 gathers. doesnt need to come off by default." So the
-- trigger is a COUNT of picks, and the switch ships on.
--
-- Asking by hand (/nt reload, /nt start) is never gated: the player's own click
-- is always permission.
function ns.SetAutoRefresh(arg)
  local want = tostring(arg or ""):lower():match("^%s*(.-)%s*$") or ""
  if want:match("^%d+$") then
    local picks = ns.SetAutoRefreshPicks(tonumber(want))
    DEFAULT_CHAT_FRAME:AddMessage(("NodeTrail: re-plan gate set to every %d gather%s. The switch is %s.")
      :format(picks, (picks == 1) and "" or "s", ns.IsAutoRefreshRoute() and "on" or "off"))
    if not ns.IsAutoRefreshRoute() then
      DEFAULT_CHAT_FRAME:AddMessage("NodeTrail: /nt autorefresh on to enable it.")
    end
    return nil
  end
  local on
  if want == "on" or want == "true" then
    on = true
  elseif want == "off" or want == "false" then
    on = false
  elseif want == "" then
    on = not ns.IsAutoRefreshRoute()
  else
    DEFAULT_CHAT_FRAME:AddMessage(
      "NodeTrail: /nt autorefresh [on|off|<picks>]  (e.g. /nt autorefresh 5)")
    return nil
  end
  ns.SetAutoRefreshRoute(on)
  if not on then
    -- A pending debounce belongs to a setting that is no longer on. Dropping it
    -- is what keeps the line still.
    if type(ns.RouteAuto) == "table" and type(ns.RouteAuto.Cancel) == "function" then
      pcall(ns.RouteAuto.Cancel, ns.RouteAuto)
    end
    DEFAULT_CHAT_FRAME:AddMessage(
      "NodeTrail: auto-refresh off — the route stays exactly as drawn until /nt reload.")
    return false
  end
  -- No rebuild here: switching it on does not make a tranche due. The counter
  -- since the last plan does.
  local rstate = (type(ns.RouteAuto) == "table" and type(ns.RouteAuto.state) == "table")
    and ns.RouteAuto.state or nil
  local waiting = (rstate and tonumber(rstate.pendingPicks)) or 0
  local need = ns.GetAutoRefreshPicks()
  DEFAULT_CHAT_FRAME:AddMessage(("NodeTrail: auto-refresh on — one re-plan every %d gathers, never in combat or with a loot window open.")
    :format(need))
  if waiting > 0 then
    DEFAULT_CHAT_FRAME:AddMessage(("NodeTrail: %d of %d picks since the last plan%s.")
      :format(waiting, need, (waiting < need) and "" or " — the next one is due"))
  end
  return true
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
  -- t_e27da774: the item-name retry clock. Item names are stored with the id at
  -- loot time; GetItemInfo is only the fallback, and an id the client has not
  -- cached yet gets asked again when the client announces item data (or, on a
  -- client without such an event, on the next loot/bag event) so the panel row
  -- can move from `item <id> (name unavailable)` to the real name.
  if ns.ItemNames and type(ns.ItemNames.Watch) == "function" then
    pcall(ns.ItemNames.Watch, ns.ItemNames)
  end
  -- Sub-feature first, module last: a probe that fails must not stop the
  -- herb route from starting (it reports through /mp skindiag instead).
  if ns.IsSkinningEnabled() then
    ns.EnableSkinning()
  end
  -- t_b46e5e87: the skinning farming circle is a DRAW layer, not the probe, so
  -- it is evaluated at login whether or not the probe is recording. Nothing is
  -- drawn until this map has enough of the character's own skinned corpses and
  -- the shared Skinning gate answers yes, so this is silent by construction.
  if type(ns.RefreshSkinRoute) == "function" then
    local okC, errC = pcall(ns.RefreshSkinRoute)
    if not okC then
      ns._skinRouteError = tostring(errC)
    end
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

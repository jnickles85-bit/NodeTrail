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
  printL("HELP_NOTES")
end

function ns.StopRoute()
  ns.activeRoute = nil
  if ns.MapOverlay then ns.MapOverlay:Clear() end
  if ns.MinimapPath then ns.MinimapPath:Clear() end
  printL("ROUTE_STOPPED")
end

function ns.StartRoute()
  local mapID = ns.GetPlayerMapID()
  local route, err = ns.BuildRouteForMap(mapID)
  if not route then
    printL(err or "ROUTE_EMPTY")
    return
  end
  ns.activeRoute = route
  if ns.MapOverlay then ns.MapOverlay:SetRoute(route) end
  if ns.MinimapPath then ns.MinimapPath:SetRoute(route) end
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
      ns.StartRoute()
    else
      printL("NO_ROUTE")
    end
  elseif msg == "status" then
    ns.PrintStatus()
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

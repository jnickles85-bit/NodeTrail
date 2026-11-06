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
  printL("STATUS_ALCHEMY", scanned and "scanned" or "open your Alchemy window once")
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

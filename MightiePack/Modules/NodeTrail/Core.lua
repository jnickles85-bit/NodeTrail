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

function ns.StopRoute()
  ns.activeRoute = nil
  if ns.MapOverlay then ns.MapOverlay:Clear() end
  if ns.MinimapPath then ns.MinimapPath:Clear() end
  printL("ROUTE_STOPPED")
end

function ns.StartRoute()
  local mapID = ns.GetPlayerMapID()
  local route, err = ns.BuildHerbRouteForMap(mapID)
  if not route then
    printL(err or "ROUTE_EMPTY")
    return
  end
  ns.activeRoute = route
  if ns.MapOverlay then ns.MapOverlay:SetRoute(route) end
  if ns.MinimapPath then ns.MinimapPath:SetRoute(route) end
  local stops = math.max(0, #route.path - 1) -- exclude close duplicate
  printL("ROUTE_STARTED", stops)
end

local function handleSlash(msg)
  msg = (msg or ""):match("^%s*(.-)%s*$") or ""
  msg = msg:lower()
  if msg == "" or msg == "help" then
    printL("HELP")
  elseif msg == "start" then
    ns.StartRoute()
  elseif msg == "stop" then
    ns.StopRoute()
  elseif msg == "reload" then
    if ns.activeRoute then
      ns.StartRoute()
    else
      printL("HELP")
    end
  else
    printL("HELP")
  end
end

function ns.Enable()
  if ns.enabled then
    return
  end
  ns.enabled = true
  ns.GetDB()
  SLASH_NODETRAIL1 = "/nodetrail"
  SLASH_NODETRAIL2 = "/nt"
  SlashCmdList.NODETRAIL = handleSlash
end

if type(pkg.RegisterModule) == "function" then
  pkg.RegisterModule("NodeTrail", {
    title = "NodeTrail",
    notes = "Herb routes: white path on the world map and minimap (/nt start | stop | reload).",
    Enable = function() ns.Enable() end,
  })
end

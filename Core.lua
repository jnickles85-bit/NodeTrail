local addonName, ns = ...

NodeTrail = ns
ns.version = "0.1.0-mvp"
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

SLASH_NODETRAIL1 = "/nodetrail"
SLASH_NODETRAIL2 = "/nt"
SlashCmdList.NODETRAIL = function(msg)
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

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    ns.GetDB()
  elseif event == "PLAYER_LOGIN" then
    if not ns.GetGatherMate2() then
      -- Soft notice once; do not error
      -- printL("NEED_GM2")  -- uncomment if we want a login nag
    end
  end
end)

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
      ns.StartRoute()
    else
      printL("NO_ROUTE")
    end
  elseif msg == "status" then
    ns.PrintStatus()
  elseif msg == "scanrecipes" or msg == "recipes" then
    ns.ScanRecipes()
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

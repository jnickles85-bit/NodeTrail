local _, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail
ns.L = ns.L or {}
local L = ns.L

L["ADDON_NAME"] = "NodeTrail"
L["NEED_GM2"] = "NodeTrail: install GatherMate2 (and gather or import herbs) so routes have nodes."
L["NO_NODES"] = "NodeTrail: no herb nodes recorded for this zone yet."
L["ROUTE_STARTED"] = "NodeTrail: route started (%d belt points from %d herb picks)."
L["ROUTE_STOPPED"] = "NodeTrail: route cleared."
L["ROUTE_EMPTY"] = "NodeTrail: not enough herb nodes to build a loop."
L["HELP"] = "NodeTrail commands:"
L["HELP_START"] = "  /nt start - draw a white route from the herbs you have gathered in this zone (density path)"
L["HELP_STOP"] = "  /nt stop - clear the route"
L["HELP_RELOAD"] = "  /nt reload - rebuild the active route with your newest picks"
L["HELP_STATUS"] = "  /nt status - route source, herbs recorded here, tooltip and module state"
L["HELP_NOTES"] = "  Herbs are recorded automatically when you gather. Hover a herb to see drop % and Alchemy uses. Module on/off: /mpack."
L["NO_ROUTE"] = "NodeTrail: no active route. Use /nt start first."
L["STATUS_HEADER"] = "NodeTrail status:"
L["STATUS_SOURCE"] = "  Route source: %s"
L["STATUS_HERBS"] = "  Herbs recorded on this map (%s): %d (all maps: %d)"
L["STATUS_ROUTE"] = "  Active route: %s"
L["STATUS_TOOLTIP"] = "  Herb tooltip: %s"
L["STATUS_ALCHEMY"] = "  Alchemy recipes: %s"
L["STATUS_MODULE"] = "  Module: %s"
L["NO_HERB_DATA"] = "NodeTrail: no herbs recorded in this zone yet. Gather a few herbs here, then /nt start."
L["NO_MAP"] = "NodeTrail: can't tell which map you are on."

-- t_2bc15917: the route comes back by itself. These are the lines that say
-- what happened, so an automatic rebuild is never a silent one.
L["ROUTE_RESTORED"] = "NodeTrail: route restored (%d points from %d herb picks on map %s)."
L["ROUTE_REFRESHED"] = "NodeTrail: route refreshed with your newest picks (%d points from %d herb picks)."
L["ROUTE_KEPT"] = "NodeTrail: route not rebuilt (%s) — the previous route stays."
L["ROUTE_STALE"] = "NodeTrail: route not rebuilt — it was started %s ago, older than the %s limit. Use /nt start."
L["ROUTE_OTHER_MAP"] = "NodeTrail: route kept for map %s; nothing is drawn until you are back there (you are on %s)."
L["STATUS_ROUTE_STATE"] = "  Route state: active %s, map %s, auto-refresh %s"
L["STATUS_ROUTE_REBUILD"] = "  Last rebuild: %s, trigger %s, %d points"
L["STATUS_ROUTE_PENDING"] = "  New picks since that rebuild: %d (/nt reload to include them)"
L["STATUS_ROUTE_GAP"] = "  Auto re-plan: switch %s, every %d gathers — %d of %d picks since the last plan"
L["ROUTE_NEW_PICKS"] = "NodeTrail: %d new pick%s since this route was built — /nt reload to include them."

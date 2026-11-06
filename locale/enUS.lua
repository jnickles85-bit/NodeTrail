local addonName, ns = ...
ns.L = ns.L or {}
local L = ns.L

L["ADDON_NAME"] = "NodeTrail"
L["NEED_GM2"] = "NodeTrail: install GatherMate2 (and gather or import herbs) so routes have nodes."
L["NO_NODES"] = "NodeTrail: no herb nodes recorded for this zone yet."
L["ROUTE_STARTED"] = "NodeTrail: route started (%d stops)."
L["ROUTE_STOPPED"] = "NodeTrail: route cleared."
L["ROUTE_EMPTY"] = "NodeTrail: not enough herb nodes to build a loop."
L["HELP"] = "NodeTrail: /nt start | stop | reload"

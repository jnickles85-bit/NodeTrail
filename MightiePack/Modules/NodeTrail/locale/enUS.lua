local addonName, pkg = ...
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
L["HELP"] = "NodeTrail: /nt start | stop | reload"
L["NO_HERB_DATA"] = "NodeTrail: no herbs recorded in this zone yet. Gather a few herbs here, then /nt start."
L["NO_MAP"] = "NodeTrail: can't tell which map you are on."

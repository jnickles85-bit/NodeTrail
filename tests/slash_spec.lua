local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
function CopyTable(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = CopyTable(v) end
  return r
end
SlashCmdList = {}
CreateFrame = function() return { SetScript = function() end, RegisterEvent = function() end } end
local mapID = 1429
C_Map = { GetBestMapForUnit = function() return mapID end }
GetSpellInfo = function() return nil end
time = os.time

local pkg = { modState = { NodeTrail = true } }
pkg.IsModuleEnabled = function(n) return pkg.modState[n] end
pkg.RegisterModule = function(name, def) pkg.registered = def end

local files = { "locale/enUS.lua", "Config.lua", "Data/GM2.lua", "Data/Recorder.lua", "Data/Density.lua", "Data/HerbData.lua", "Data/Recipes.lua", "Core.lua" }
for _, f in ipairs(files) do
  assert(loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. f))("MightiePack", pkg)
end
local ns = pkg.NodeTrail
ns.MapOverlay = nil
ns.MinimapPath = nil
ns.Tooltip = { _enabled = false, Enable = function(self) self._enabled = true end }

local function run(cmd)
  for i = #chat, 1, -1 do chat[i] = nil end
  SlashCmdList.NODETRAIL(cmd)
  return table.concat(chat, "\n")
end

check(SlashCmdList.NODETRAIL == nil, "module gating before Enable")
check(pkg.registered and pkg.registered.notes:find("status", 1, true) ~= nil, "notes contains status")

NodeTrailDB = nil
ns.Enable()
check(type(SlashCmdList.NODETRAIL) == "function", "slash registered")
check(SLASH_NODETRAIL1 == "/nodetrail", "slash1")
check(SLASH_NODETRAIL2 == "/nt", "slash2")
check(ns.Tooltip._enabled == true, "tooltip enabled")

local help = run("help")
for _, needle in ipairs({ "/nt start", "/nt stop", "/nt reload", "/nt status", "density", "Hover a herb", "/mpack" }) do
  check(help:find(needle, 1, true) ~= nil, "help contains " .. needle)
end
check(run("") == help, "empty equals help")
check(run("bogus") == help, "bogus equals help")

local r = run("reload")
check(r:find("no active route", 1, true) ~= nil, "reload no route")
check(r:find("route started", 1, true) == nil, "reload no route started")

local s = run("status")
for _, needle in ipairs({ "Route source: density", "on this map (1429): 0 (all maps: 0)", "Active route: none", "Herb tooltip: on", "open your Alchemy window once", "Module: on" }) do
  check(s:find(needle, 1, true) ~= nil, "status contains " .. needle)
end

for i = 1, 3 do ns.RecordHerb(1429, i * 0.1, i * 0.1, {}) end
for i = 1, 2 do ns.RecordHerb(1411, i * 0.1, i * 0.1, {}) end
s = run("status")
check(s:find("(1429): 3 (all maps: 5)", 1, true) ~= nil, "herb counts")

ns.GetDB().routeSource = "gm2"
s = run("status")
check(s:find("gm2 (GatherMate2", 1, true) ~= nil, "gm2 source")
ns.GetDB().routeSource = "density"

NodeTrailDB.recipes = { alchemy = {}, alchemyScanned = 123 }
s = run("status")
check(s:find("Alchemy recipes: scanned", 1, true) ~= nil, "alchemy scanned")

mapID = nil
s = run("status")
check(s:find("(unknown): 0", 1, true) ~= nil, "unknown map")
mapID = 1429

for i = 1, 6 do ns.RecordHerb(1429, 0.3 + i * 0.004, 0.3 + i * 0.004, {}) end
for i = 1, 6 do ns.RecordHerb(1429, 0.7 + i * 0.004, 0.6 + i * 0.004, {}) end
r = run("start")
check(r:find("route started", 1, true) ~= nil, "start route")
check(ns.activeRoute and ns.activeRoute.source == "density", "route source density")
s = run("status")
check(s:find("Active route: ", 1, true) ~= nil, "active route present")
check(s:find([[points, density]], 1, true) ~= nil, [[active route density]])
check(s:find("Active route: none", 1, true) == nil, "not none")
r = run("reload")
check(r:find("route started", 1, true) ~= nil, "reload route")
r = run("stop")
check(r:find("route cleared", 1, true) ~= nil, "stop route")
check(ns.activeRoute == nil, "activeRoute nil")

pkg.modState.NodeTrail = false
s = run("status")
check(s:find("Module: off", 1, true) ~= nil, "module off")

s = run("  STATUS  ")
check(s:find("NodeTrail status:", 1, true) ~= nil, "case whitespace status")

if failed == 0 then
  print("slash_spec: ok")
else
  os.exit(1)
end

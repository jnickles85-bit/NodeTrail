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
-- This spec's client stubs no trade-skill API at all (neither the legacy
-- globals nor C_TradeSkillUI), so the alchemy line must not promise the
-- "open your Alchemy window once" step — it must say the feature is
-- unavailable (t_0d5badc3).
for _, needle in ipairs({ "Route source: density", "on this map (1429): 0 (all maps: 0)", "Active route: none", "Herb tooltip: on", "Alchemy recipes: unavailable on this client (no trade skill API found", "Module: on" }) do
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

-- /nt ttdiag: layout diagnostic. The slash spec's Tooltip stub has no
-- Diag implementation, so the branch must fall back cleanly (the branch
-- is only reachable after Enable — module gating already proven above).
local d = run("ttdiag")
check(d:find("ttdiag", 1, true) ~= nil, "ttdiag prints")
check(d:find("unavailable", 1, true) ~= nil, "ttdiag falls back when the tooltip stub has no Diag")

-- ── /mpack status identity header (t_e9996745) ──────────────────────────
-- The card: `/mpack status` must print, BEFORE the module lines, an addon
-- version line, an interface/client-build line (build number via
-- select(4, GetBuildInfo()) plus the full GetBuildInfo() version string),
-- the current locale, and whether GatherMate2 is loaded — so a paste of
-- the output is a self-describing bug report. We drive the REAL top-level
-- Core.lua status branch (SlashCmdList.MIGHTIEPACK from the loaded file)
-- on a fresh umbrella package built from the real Core.lua + Modules.lua
-- (real RegisterModule / IsModuleEnabled / module loop), with the client
-- metadata APIs stubbed.
MightiePackDB = nil
local mpkg = {}
assert(loadfile(root .. "/MightiePack/Core.lua"))("MightiePack", mpkg)
assert(loadfile(root .. "/MightiePack/Modules.lua"))("MightiePack", mpkg)
mpkg.RegisterModule("NodeTrail", {
  title = "NodeTrail",
  notes = "Herb routes from your own gathers (white path on world map + minimap), herb tooltip. /nt start | stop | reload | status",
  Enable = function() end, -- not called here (no EnableModules in this spec)
})
local mpOpened = false
mpkg.OpenOptions = function() mpOpened = true end

GetAddOnMetadata = function(name, what)
  if name ~= "MightiePack" then return nil end
  if what == "Version" then return "0.3.0" end
  if what == "Interface" then return "16001" end
  return nil
end
GetBuildInfo = function() return "16", "0", "0", "16001" end
GetLocale = function() return "enUS" end
IsAddOnLoaded = function(name) return name == "GatherMate2" and true or false end

check(SlashCmdList.MIGHTIEPACK ~= nil, "MIGHTIEPACK slash registered by real Core.lua")
local function runMp(cmd)
  for i = #chat, 1, -1 do chat[i] = nil end
  SlashCmdList.MIGHTIEPACK(cmd)
  return table.concat(chat, "\n")
end

local st = runMp("status")
check(st:find("version 0.3.0", 1, true) ~= nil, "mpack status: version line from GetAddOnMetadata")
check(st:find("interface 16001", 1, true) ~= nil, "mpack status: interface from TOC metadata")
check(st:find("build 16001", 1, true) ~= nil, "mpack status: client build number (select 4)")
check(st:find("client 16.0.0.16001", 1, true) ~= nil, "mpack status: full GetBuildInfo version string")
check(st:find("locale enUS", 1, true) ~= nil, "mpack status: current locale")
check(st:find("GatherMate2: loaded", 1, true) ~= nil, "mpack status: GatherMate2 loaded")
check(st:find("NodeTrail: on", 1, true) ~= nil, "mpack status: NodeTrail module line still on")
check(st:find("Touchstone: off", 1, true) ~= nil, "mpack status: Touchstone module line still off")
local vPos, ntPos = st:find("version 0.3.0", 1, true), st:find("NodeTrail: on", 1, true)
check(vPos ~= nil and ntPos ~= nil and vPos < ntPos, "mpack status: header lines come before module lines")

IsAddOnLoaded = function() return false end
local stGm = runMp("status")
check(stGm:find("GatherMate2: not loaded", 1, true) ~= nil, "mpack status: GatherMate2 not loaded when absent")
IsAddOnLoaded = function(name) return name == "GatherMate2" and true or false end

mpOpened = false
runMp("")
check(mpOpened == true, "mpack: no argument still opens options")
check(#chat == 0, "mpack: no argument prints nothing")
mpOpened = false
runMp("options")
check(mpOpened == true, "mpack: 'options' still opens options")
check(runMp("bogus"):find("/mpack [options|status]", 1, true) ~= nil, "mpack: bogus command prints usage")

-- A nil GetAddOnMetadata (function missing AND nil return) must print
-- "version unknown", not error — both variants the card calls out.
GetAddOnMetadata = nil
local okE, stE = pcall(runMp, "status")
check(okE, "mpack status: nil GetAddOnMetadata does not error (missing function)")
if okE then
  check(stE:find("version unknown", 1, true) ~= nil, "mpack status: nil GetAddOnMetadata prints version unknown")
  check(stE:find("interface unknown", 1, true) ~= nil, "mpack status: nil GetAddOnMetadata prints interface unknown")
  check(stE:find("NodeTrail: on", 1, true) ~= nil, "mpack status: module lines survive the nil metadata")
end
GetAddOnMetadata = function() return nil end
local okR, stR = pcall(runMp, "status")
check(okR, "mpack status: GetAddOnMetadata returning nil does not error")
if okR then
  check(stR:find("version unknown", 1, true) ~= nil, "mpack status: nil return prints version unknown")
end

-- The umbrella_spec environment: NONE of the metadata globals exist at all.
GetAddOnMetadata = nil
GetBuildInfo = nil
GetLocale = nil
IsAddOnLoaded = nil
local okN, stN = pcall(runMp, "status")
check(okN, "mpack status: all metadata globals absent does not error (umbrella_spec environment)")
if okN then
  check(stN:find("version unknown", 1, true) ~= nil, "all absent: version unknown")
  check(stN:find("interface unknown", 1, true) ~= nil, "all absent: interface unknown")
  check(stN:find("build unknown", 1, true) ~= nil, "all absent: build unknown")
  check(stN:find("locale unknown", 1, true) ~= nil, "all absent: locale unknown")
  check(stN:find("GatherMate2: unknown", 1, true) ~= nil, "all absent: GatherMate2 unknown")
  check(stN:find("NodeTrail: on", 1, true) ~= nil, "all absent: module lines still printed")
end

-- A module that refused to run (Touchstone while the standalone folder exists)
-- is marked loaded by EnableModules; the status line must not claim it is
-- running. It has to say it is inert, next to the reason.
mpkg.RegisterModule("TouchTest", { title = "TouchTest", Enable = function() end })
mpkg.GetSettings().modules.TouchTest = true
mpkg.modules.TouchTest.inert = true
mpkg.modules.TouchTest.loaded = true
local stI = runMp("status")
check(stI:find("TouchTest: on (inert", 1, true) ~= nil,
  "mpack status: an inert module says inert, not loaded")
check(stI:find("TouchTest: on (loaded)", 1, true) == nil,
  "mpack status: an inert module never claims to be loaded")

if failed == 0 then
  print("slash_spec: ok")
else
  os.exit(1)
end

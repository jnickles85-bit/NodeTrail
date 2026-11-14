-- slash_spec.lua — the pack's own slash surface.
--
-- Card t_75309c97: NodeTrail is its own addon now. Its commands (/nt start,
-- /nt status, /nt linetest, the module gating, the skinning diagnostics) moved
-- with the module and are covered by the standalone addon's specs. What is left
-- here is /mp: its aliases, its help, its identity header, and the fact that it
-- no longer answers for NodeTrail or for skindiag.

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
check(st:find("NodeTrail: a separate addon", 1, true) ~= nil, "mpack status: the NodeTrail line says it is a separate addon")
check(st:find("Touchstone: off", 1, true) ~= nil, "mpack status: Touchstone module line still off")
local vPos, ntPos = st:find("version 0.3.0", 1, true), st:find("Touchstone: off", 1, true)
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
  check(stE:find("Touchstone: off", 1, true) ~= nil, "mpack status: module lines survive the nil metadata")
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
  check(stN:find("Touchstone: off", 1, true) ~= nil, "all absent: module lines still printed")
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

-- ── t_86583cf2: the two new commands are wired, and they never raise ────────
-- `/nt minimap on|off` is the minimap line's own switch (the world map route is
-- untouched); `/nt navwalk` records the four-stop walk and must degrade to a
-- message — not an error — when the minimap module is not loaded.

if failed == 0 then
  print("slash_spec: ok")
else
  os.exit(1)
end

-- window_settings_build_spec.lua — card t_ea66cd84, AC-N1 / AC-N2 / AC-N3.
--
-- The defect: Pack Settings rendered differently on different opens — one open
-- showed every module checkbox row and the Gear-for dropdown, a later open
-- showed only the load-time widgets (section headers, Scan/Feedback). The rows
-- exist only after the build (`syncCheckboxes()` + `syncRecipesBlock()` +
-- `relayoutLowerSections()`), and the build was attached to the panel's
-- OnShow — which cannot fire from opening the tab:
--
--   * a frame created by CreateFrame is BORN SHOWN, so the birth OnShow is
--     already spent before any tab can be opened, and `panel:Show()` on an
--     already-shown frame fires nothing (the harness now models both rules);
--   * so with OnShow as the only hook the build ran ZERO times in a session.
--
-- What this file pins:
--   AC-N1  three activations of the settings tab run the build three times.
--   AC-N2  a hidden panel comes back: Hide() then open the tab -> IsShown().
--   AC-N3  the build is reachable from TAB ACTIVATION, not only from OnShow:
--          here OnShow never fires at all, and the build still runs.
--
-- It also asserts the build's OUTPUT (the module rows exist), so a build that
-- is called but does nothing cannot pass. Nothing here invokes the panel's
-- OnShow script by hand to simulate a build — that is the pattern that kept
-- this defect invisible (AC-N5).

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local C = dofile(root .. "/tests/support/wowclient.lua")
C.Install({ width = 1920, height = 1080 })

local pkg = {}
local function loadFile(path)
  local chunk, err = loadfile(root .. "/MightiePack/" .. path)
  check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
  if not chunk then return end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. path .. ": " .. tostring(e))
end

MightiePackDB = { modules = { NodeTrail = true, Touchstone = true }, seen = { firstRun = true }, bugCount = 0 }
NodeTrailDB = {
  schema = 2,
  herbs = {
    schema = 2, total = 0, maps = {}, mapTotals = {},
    stats = { gathers = {}, co = {}, names = {} }, hotspots = {}, folded = {},
  },
  skinning = { enabled = true, schema = 2, chars = {} },
  route = {},
}
StatForgeDB = { ui = { scale = 1 } }

loadFile("Core.lua")
loadFile("Modules.lua")
for _, f in ipairs({
  "Modules/NodeTrail/locale/enUS.lua",
  "Modules/NodeTrail/Config.lua",
  "Modules/NodeTrail/Data/ItemNames.lua",
  "Modules/NodeTrail/Data/HerbData.lua",
  "Modules/NodeTrail/Data/Recorder.lua",
  "Modules/NodeTrail/Data/Density.lua",
  "Modules/NodeTrail/Data/Recipes.lua",
  "Modules/NodeTrail/Data/Profession.lua",
  "Modules/NodeTrail/Data/SkinHints.lua",
  "Modules/NodeTrail/UI/TooltipPanel.lua",
  "Modules/NodeTrail/UI/Tooltip.lua",
  "Modules/NodeTrail/Core.lua",
}) do loadFile(f) end
loadFile("Modules/Skinning/Core.lua")
loadFile("Modules/Skinning/Record.lua")
loadFile("BugReport.lua")
loadFile("Options.lua")
loadFile("Window.lua")
loadFile("Window/Common.lua")
loadFile("Window/Herbs.lua")
loadFile("Window/Skinning.lua")

StatForge = {
  ShowMain = function() end, HideMain = function() end, ToggleMain = function() end,
  IsMainShown = function() return false end, RefreshActiveTab = function() end,
  SelectTab = function() end,
}
loadFile("Window/TouchstoneTab.lua")
check(pcall(pkg.EnableModules), "the enabled modules start (as they do at login)")

local W = pkg.Window
local panel = pkg.optionsPanel
check(type(W) == "table" and type(panel) == "table", "the window and the options panel exist")

-- The premise the whole defect turns on, asserted rather than assumed: a
-- freshly created frame is shown, so its birth OnShow is spent.
check(panel:IsShown() == true,
  "precondition: the options panel is BORN SHOWN, so its birth OnShow is spent")

-- Observe the build path without replacing it: count and delegate.
local builds = 0
if type(pkg.SyncOptionsRows) == "function" then
  local inner = pkg.SyncOptionsRows
  pkg.SyncOptionsRows = function(...)
    builds = builds + 1
    return inner(...)
  end
end
-- Observe the panel's own OnShow the same way (never firing it by hand).
local onShowFired = 0
local innerOnShow = panel:GetScript("OnShow")
if type(innerOnShow) == "function" then
  panel:SetScript("OnShow", function(self, ...)
    onShowFired = onShowFired + 1
    return innerOnShow(self, ...)
  end)
end

local f = W.Frame()
check(type(f) == "table", "the window frame is created")

-- ── AC-N1: three activations, three builds ────────────────────────────────
builds, onShowFired = 0, 0
W.Open("herbs")
for i = 1, 3 do
  local before = builds
  W.SelectTab("settings")
  check(W.Current() == "settings", "activation #" .. i .. " selects the settings tab")
  check(builds == before + 1,
    "activation #" .. i .. " runs the Pack Settings build exactly once (ran "
      .. tostring(builds - before) .. ")")
end
check(builds == 3, "three activations of the Pack Settings tab build the rows three times (got "
  .. tostring(builds) .. ")")

-- AC-N3: that build came from the ACTIVATION, not from OnShow — with this
-- client the panel was never hidden, so OnShow could not have fired.
check(onShowFired == 0,
  "the build fired without OnShow: the panel's OnShow ran " .. tostring(onShowFired) .. " time(s)")

-- The build's OUTPUT: the module rows exist. A build that is called but builds
-- nothing must not pass.
check(type(pkg.optionsBoxes) == "table" and pkg.optionsBoxes.NodeTrail ~= nil,
  "after activation the module checkbox rows exist (rows are the build's output)")
check(pkg.optionsBoxes.NodeTrail ~= nil and pkg.optionsBoxes.Touchstone ~= nil,
  "both enabled modules have a row")

-- ── AC-N2: a hidden panel comes back ─────────────────────────────────────
-- The AddOns > MightiePack canvas hides the panel when the player leaves it.
-- The old attach path returned early once the panel was parented into the
-- host, BEFORE the Show, so the tab stayed blank for the rest of the session.
panel:Hide()
check(panel:IsShown() == false, "the panel can be hidden (as the Settings canvas does)")
W.Open("settings")
check(panel:IsShown() == true,
  "opening the Pack Settings tab shows a hidden panel again (IsShown is still false)")
check(W.hosts.settings:IsShown() == true, "and its host is the visible one")

-- Same again through the window's close/open cycle, which is the player's path.
W.Close()
W.Open("settings")
check(panel:IsShown() == true, "close then reopen still shows the panel")

-- And when the canvas has taken the panel back entirely, the tab claims it.
do
  local canvas = CreateFrame("Frame", "SpecSettingsCanvas", UIParent)
  panel:SetParent(canvas)
  panel:Hide()
  W.SelectTab("herbs")
  W.SelectTab("settings")
  check(panel:GetParent() == W.hosts.settings,
    "activating the tab claims the panel back from the Settings canvas")
  check(panel:IsShown() == true, "and shows it")
end

if failed == 0 then
  print("window_settings_build_spec: ok")
else
  print(("window_settings_build_spec: %d failure(s)"):format(failed))
  os.exit(1)
end

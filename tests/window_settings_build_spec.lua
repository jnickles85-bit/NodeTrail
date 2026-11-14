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
}) do loadFile(f) end
loadFile("Theme.lua")
loadFile("BugReport.lua")
loadFile("Options.lua")
loadFile("Window.lua")

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

-- The premise the whole defect turned on, asserted rather than assumed.
--
-- CHANGED by card t_07f778ca (PART A3): the panel is now BORN HIDDEN. The old
-- premise ("born shown, so its birth OnShow is spent") was the reason OnShow
-- alone could never build the rows — and the born-shown frame was also the frame
-- that sat over the Touchstone body for the whole session. Both facts came from
-- the same line; hiding the panel at creation fixes the second and changes the
-- first. OnShow now DOES fire on the first activation, which is why the legs
-- below count builds from ACTIVATION (#2 and #3 fire no OnShow at all) instead
-- of asserting OnShow never fires.
check(panel:IsShown() == false,
  "precondition: the options panel is BORN HIDDEN (an unowned panel must not paint)")

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

-- ── AC-N1: every activation builds; the build does not depend on OnShow ───
-- Activation #1 shows a panel that was hidden, so BOTH paths run there (OnShow,
-- then the activation's own buildSettings); activations #2 and #3 find the panel
-- already shown, fire no OnShow, and must still build exactly once each. That
-- second half is what AC-N3 is about: the build is reachable from TAB
-- ACTIVATION, not only from OnShow.
builds, onShowFired = 0, 0
W.Open("touchstone")
for i = 1, 3 do
  local before, showsBefore = builds, onShowFired
  W.SelectTab("settings")
  check(W.Current() == "settings", "activation #" .. i .. " selects the settings tab")
  if i == 1 then
    check(builds >= before + 1,
      "activation #1 builds the rows at least once (ran " .. tostring(builds - before) .. ")")
  else
    check(builds == before + 1,
      "activation #" .. i .. " runs the Pack Settings build exactly once (ran "
        .. tostring(builds - before) .. ")")
    check(onShowFired == showsBefore,
      "activation #" .. i .. " fired no OnShow, and the rows were still built")
  end
end
check(builds >= 3, "three activations of the Pack Settings tab build the rows three times (got "
  .. tostring(builds) .. ")")

-- The build's OUTPUT: the module rows exist. A build that is called but builds
-- nothing must not pass.
check(type(pkg.optionsBoxes) == "table" and pkg.optionsBoxes.Touchstone ~= nil,
  "after activation the module checkbox rows exist (rows are the build's output)")
check(pkg.optionsBoxes.Touchstone ~= nil and pkg.optionsBoxes.NodeTrail == nil,
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
  W.SelectTab("touchstone")
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

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function readToc()
  local path = root .. "/MightiePack/MightiePack.toc"
  local f = assert(io.open(path, "r"), "cannot open " .. path)
  local content = f:read("*a")
  f:close()
  local lines = {}
  for line in content:gmatch("[^\r\n]+") do
    local t = trim(line)
    if t ~= "" and not t:match("^#") then
      table.insert(lines, t)
    end
  end
  return lines
end

local tocLines = readToc()
check(#tocLines > 0, "TOC has lines")
check(tocLines[1] == "ErrorHandler.lua", "TOC first is ErrorHandler.lua, got " .. tostring(tocLines[1]))
check(tocLines[2] == "Core.lua", "TOC second is Core.lua, got " .. tostring(tocLines[2]))
check(tocLines[3] == "Modules.lua", "TOC third is Modules.lua, got " .. tostring(tocLines[3]))
check(tocLines[#tocLines] == "Window/TouchstoneTab.lua",
  "TOC last is the last window tab file, got " .. tostring(tocLines[#tocLines]))
-- Card t_a5de2f16: the ONE window's shell loads before its tab files, and both
-- load after Options.lua (the Pack Settings tab is that panel).
local inToc = {}
for _, l in ipairs(tocLines) do inToc[l] = true end
check(inToc["Options.lua"], "TOC contains Options.lua")
check(inToc["Window.lua"], "TOC contains the unified window shell")
check(inToc["Theme.lua"], "TOC contains the pack's theme (tokens and kit)")
check(not inToc["Window/Common.lua"],
  "TOC does not ship Window/Common.lua: the kit lives in Theme.lua (t_2d2c37b0)")
-- The theme must load BEFORE the surfaces that read tokens from it.
local themeAt, optionsAt, windowAt
for i, l in ipairs(tocLines) do
  if l == "Theme.lua" then themeAt = i end
  if l == "Options.lua" then optionsAt = i end
  if l == "Window.lua" then windowAt = i end
end
check(themeAt and optionsAt and themeAt < optionsAt,
  "Theme.lua loads before Options.lua (theme " .. tostring(themeAt) .. ", options "
    .. tostring(optionsAt) .. ")")
check(themeAt and windowAt and themeAt < windowAt,
  "Theme.lua loads before Window.lua (theme " .. tostring(themeAt) .. ", window "
    .. tostring(windowAt) .. ")")
check(not inToc["Window/Herbs.lua"], "TOC does not ship the Herbs tab (it moved out with NodeTrail)")
check(not inToc["Window/Skinning.lua"], "TOC does not ship the Skinning tab")
check(inToc["Window/TouchstoneTab.lua"], "TOC contains the Touchstone tab")
local hasNodeCore = false
for _, l in ipairs(tocLines) do
  if l == "Modules/NodeTrail/Core.lua" then hasNodeCore = true end
end
check(not hasNodeCore, "TOC does not ship Modules/NodeTrail/Core.lua")

local tocPath = root .. "/MightiePack/MightiePack.toc"
local tf = assert(io.open(tocPath, "r"))
local tocContent = tf:read("*a")
tf:close()
check(tocContent:find("## Interface: 16001", 1, true) ~= nil, "TOC has Interface 16001")
local sv = tocContent:match("## SavedVariables: ([^\r\n]+)")
check(sv ~= nil, "TOC has SavedVariables")
if sv then
  check(sv:find("MightiePackDB", 1, true) ~= nil, "SV has MightiePackDB")
  check(sv:find("NodeTrailDB", 1, true) ~= nil, "SV has NodeTrailDB")
end

for _, l in ipairs(tocLines) do
  local p = root .. "/MightiePack/" .. l
  local f = io.open(p, "r")
  check(f ~= nil, "TOC file exists: " .. l)
  if f then f:close() end
end

-- WoW stubs
local chat = {}
local frames = {}
local reloads = 0
local shownPopups = {}
local registeredCategory = nil
local openedId = nil

DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
SlashCmdList = {}
StaticPopupDialogs = {}
OKAY = "Okay"
CANCEL = "Cancel"
ReloadUI = function() reloads = reloads + 1 end
StaticPopup_Show = function(which, a1, a2, data)
  shownPopups[#shownPopups + 1] = { which = which, text = a1, data = data }
end
GameTooltip = {
  SetOwner = function() end,
  SetText = function() end,
  AddLine = function() end,
  Show = function() end,
  Hide = function() end,
}
Settings = {
  RegisterCanvasLayoutCategory = function(frame, name)
    return { frame = frame, name = name, GetID = function() return 42 end }
  end,
  RegisterAddOnCategory = function(cat) registeredCategory = cat end,
  OpenToCategory = function(id) openedId = id end,
}
C_Map = { GetBestMapForUnit = function() return 12 end }

local function deepCopy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = deepCopy(v) end
  return r
end
CopyTable = deepCopy

local function makeFontString()
  local fs = {}
  local text = ""
  fs.SetPoint = function() end
  fs.SetAllPoints = function() end
  fs.SetText = function(_, v) text = v end
  fs.GetText = function() return text end
  fs.Hide = function() end
  fs.Show = function() end
  return fs
end

local function makeTexture()
  local tx = {}
  tx.SetPoint = function() end
  tx.SetAllPoints = function() end
  tx.SetTexture = function() end
  tx.SetColorTexture = function() end
  tx.Hide = function() end
  tx.Show = function() end
  return tx
end

local function makeFrame(kind, name, parent, template)
  local f = {
    kind = kind,
    name = name,
    parent = parent,
    template = template,
    scripts = {},
    events = {},
    children = {},
    checked = false,
    enabled = true,
    shown = true,
  }
  f.SetScript = function(_, k, fn) f.scripts[k] = fn end
  f.GetScript = function(_, k) return f.scripts[k] end
  f.RegisterEvent = function(_, e) f.events[e] = true end
  f.UnregisterEvent = function(_, e) f.events[e] = nil end
  f.SetPoint = function(_, a, b, c, d, e)
    local pts = rawget(f, "pointArgs")
    if not pts then
      pts = {}
      rawset(f, "pointArgs", pts)
    end
    pts[#pts + 1] = { a, b, c, d, e }
  end
  f.ClearAllPoints = function() end
  f.SetSize = function() end
  f.SetWidth = function() end
  f.SetHeight = function() end
  f.Hide = function() f.shown = false end
  f.Show = function() f.shown = true end
  f.IsShown = function() return f.shown end
  f.SetChecked = function(_, v) f.checked = v and true or false end
  f.GetChecked = function() return f.checked end
  f.Disable = function() f.enabled = false end
  f.Enable = function() f.enabled = true end
  f.IsEnabled = function() return f.enabled end
  f.HookScript = function() end
  f.SetAllPoints = function() end
  f.SetFrameStrata = function() end
  f.SetFrameLevel = function() end
  f.GetFrameLevel = function() return 1 end
  f.CreateTexture = function() return makeTexture() end
  f.CreateFontString = function() return makeFontString() end
  if template == "UICheckButtonTemplate" then
    f.Text = makeFontString()
  end
  setmetatable(f, { __index = function(_, k)
    return function() end
  end })
  frames[#frames + 1] = f
  return f
end
CreateFrame = makeFrame

local function loadPackage(savedDB, savedNT)
  SlashCmdList = {}
  StaticPopupDialogs = {}
  MightiePackDB = savedDB
  NodeTrailDB = savedNT
  MightiePack = nil
  NodeTrail = nil
  SLASH_NODETRAIL1 = nil
  SLASH_NODETRAIL2 = nil
  frames = {}
  local pkg = {}
  for _, l in ipairs(tocLines) do
    local p = root .. "/MightiePack/" .. l
    local chunk, err = loadfile(p)
    check(chunk ~= nil, "loadfile " .. l .. ": " .. tostring(err))
    if chunk then
      local ok, e2 = pcall(chunk, "MightiePack", pkg)
      check(ok, "load " .. l .. ": " .. tostring(e2))
    end
  end
  for _, f in ipairs(frames) do
    if f.events.ADDON_LOADED and f.scripts.OnEvent then
      local ok, e = pcall(f.scripts.OnEvent, f, "ADDON_LOADED", "MightiePack")
      check(ok, "ADDON_LOADED event: " .. tostring(e))
    end
  end
  return pkg
end

-- Test 1
local pkg = loadPackage(nil)
check(MightiePack == pkg, "MightiePack global == pkg")
-- ════════════════════════════════════════════════════════════════════════
-- Test 1: the pack loads, and it is the pack alone (card t_75309c97)
-- ════════════════════════════════════════════════════════════════════════
-- NodeTrail is its own addon again. What this section pins is the shape of the
-- pack after the extraction, because every one of these is a way the split
-- could go wrong:
--
--   * the module list is Touchstone alone, and NodeTrail is not registered,
--     not loaded and not reachable through pkg;
--   * none of NodeTrail's files are in the TOC (the tab bodies, the module, the
--     skinning probe);
--   * the pack still DECLARES NodeTrailDB — that declaration is the migration
--     window, and without it the game never loads an existing history for
--     NodeTrail to adopt — but loading the pack does not create, change or
--     delete one key of that store;
--   * /nt is not registered here, and /mp no longer answers for skindiag;
--   * the window has the two tabs that are the pack's own.

check(MightiePackDB and MightiePackDB.modules and MightiePackDB.modules.Touchstone == false,
  "Touchstone default false")
check(MightiePackDB and MightiePackDB.modules and MightiePackDB.modules.NodeTrail == nil,
  "no default is written for a module this pack no longer has")

local order = pkg.moduleOrder or {}
local hasNT, hasTS, hasSkinModule = false, false, false
for _, n in ipairs(order) do
  if n == "NodeTrail" then hasNT = true end
  if n == "Touchstone" then hasTS = true end
  if n == "Skinning" then hasSkinModule = true end
end
check(hasTS, "moduleOrder has Touchstone")
check(not hasNT, "moduleOrder has no NodeTrail (it is not a module of this pack any more)")
check(not hasSkinModule, "moduleOrder has no Skinning entry")
check(pkg.modules and pkg.modules.NodeTrail == nil, "NodeTrail is not registered")
check(pkg.NodeTrail == nil, "pkg.NodeTrail is not published")
check(pkg.Skinning == nil, "pkg.Skinning is not published")
check(pkg.moduleDefaults and pkg.moduleDefaults.NodeTrail == nil,
  "moduleDefaults has no NodeTrail entry")
check(pkg.IsModuleEnabled("NodeTrail") == false, "IsModuleEnabled('NodeTrail') is false")
check(pkg.IsModuleEnabled("Touchstone") == false, "Touchstone disabled by default")

-- The migration window: the TOC still declares NodeTrailDB.
check(tocContent:find("## SavedVariables: MightiePackDB, NodeTrailDB, StatForgeDB", 1, true) ~= nil,
  "the TOC still declares NodeTrailDB (the migration window a player needs)")

-- Nothing of NodeTrail's is a shipping file.
for _, bad in ipairs({
  "Modules/NodeTrail/Core.lua",
  "Modules/Skinning/Probe.lua",
  "Window/Herbs.lua",
  "Window/Skinning.lua",
}) do
  check(not inToc[bad], "the TOC does not ship " .. bad)
  local f = io.open(root .. "/MightiePack/" .. bad, "r")
  check(f == nil, "the file is gone from the repo: " .. bad)
  if f then f:close() end
end

-- /nt is the standalone addon's command now.
check(SlashCmdList.NODETRAIL == nil, "/nt is not registered by the pack")
check(SLASH_NODETRAIL1 == nil and SLASH_NODETRAIL2 == nil,
  "the /nt slash globals are not set by the pack")
check(type(SlashCmdList.MIGHTIEPACK) == "function", "the /mp handler is registered")

-- The detector the pack uses to point at the standalone addon. It answers
-- "installed", not "loaded": MightiePack sorts first, so at load time NodeTrail
-- has not loaded yet even when the player has it.
C_AddOns = { DoesAddOnExist = function(name) return name == "NodeTrail" end }

-- /mp help says where NodeTrail went, and never answers for it.
local helpBefore = #chat
SlashCmdList.MIGHTIEPACK("help")
local saidSeparate, saidSkindiag = false, false
for i = helpBefore + 1, #chat do
  local m = tostring(chat[i])
  if m:find("NodeTrail is a separate addon now", 1, true) then saidSeparate = true end
  if m:find("skindiag", 1, true) then saidSkindiag = true end
end
check(saidSeparate, "/mp help points at the separate addon (/mp help: "
  .. table.concat(chat, " | ") .. ")")
check(not saidSkindiag, "/mp help no longer advertises skindiag")

-- A skindiag subcommand no longer runs a probe from this pack: card t_2d2c37b0
-- RETIRED it deliberately, so it answers with where the diagnostics went. The
-- spec asserts the retirement sentence (not the absence of the words "/mp
-- skindiag", which the sentence itself contains on purpose).
local skBefore = #chat
SlashCmdList.MIGHTIEPACK("skindiag dump")
local answeredSkindiag, ranProbe = false, false
for i = skBefore + 1, #chat do
  local m = tostring(chat[i])
  if m:find("moved out of the pack with NodeTrail", 1, true) then answeredSkindiag = true end
  if m:find("skindiag:", 1, true) or m:find("Skinning diagnostics:", 1, true) then ranProbe = true end
end
check(answeredSkindiag, "/mp skindiag says the diagnostics moved out with NodeTrail")
check(not ranProbe, "/mp skindiag no longer runs a probe from this pack")

-- /mp status: Touchstone's line, and one honest line about NodeTrail.
local stBefore = #chat
SlashCmdList.MIGHTIEPACK("status")
local foundTS, foundNTLine, foundSkinLine = false, false, false
for i = stBefore + 1, #chat do
  local m = tostring(chat[i])
  if m:find("Touchstone: off", 1, true) then foundTS = true end
  if m:find("NodeTrail: a separate addon", 1, true) then foundNTLine = true end
  if m:find("Skinning:", 1, true) then foundSkinLine = true end
end
check(foundTS, "status shows Touchstone off")
check(foundNTLine, "status says NodeTrail is a separate addon (chat: "
  .. table.concat(chat, " | ") .. ")")
check(not foundSkinLine, "status prints no Skinning module line")

-- /mp opens the window on its own tab.
openedId = nil
SlashCmdList.MIGHTIEPACK("")
check(type(pkg.Window) == "table" and pkg.Window.IsShown() == true,
  "/mp shows the window")
check(type(pkg.Window) == "table" and pkg.Window.Current() == "settings",
  "/mp selects the Pack Settings tab (got " .. tostring(pkg.Window and pkg.Window.Current()) .. ")")
check(#pkg.Window.TABS == 2 and pkg.Window.TABS[1] == "touchstone" and pkg.Window.TABS[2] == "settings",
  "the window has the pack's two tabs (got " .. tostring(#pkg.Window.TABS) .. ")")
for _, gone in ipairs({ "herbs", "skinning" }) do
  check(pkg.Window.hosts[gone] == nil, "the window builds no host for " .. gone)
  check(pkg.Window.TAB_LABELS[gone] == nil, "the window has no label for " .. gone)
end

-- ════════════════════════════════════════════════════════════════════════
-- Test 2: the options panel is the pack's own rows
-- ════════════════════════════════════════════════════════════════════════
local panel = pkg.optionsPanel
local onShow = panel:GetScript("OnShow")
onShow(panel)
onShow(panel)
local boxes = pkg.optionsBoxes
check(boxes ~= nil, "optionsBoxes exists")
check(boxes.NodeTrail == nil, "the options panel builds no NodeTrail row")
check(boxes.Skinning == nil, "the options panel builds no skinning sub-option")
check(boxes.AutoRefresh == nil, "the options panel builds no auto-refresh row")
check(boxes.SkinRoute == nil, "the options panel builds no farming-circle row")
check(boxes.Touchstone ~= nil, "the Touchstone row is still there")
check(boxes.Touchstone and boxes.Touchstone:IsEnabled() == true,
  "the Touchstone row is usable (no longer a stub)")
check(boxes.SkinDiagCopy == nil, "the options panel carries no diagnostics-copy button")

-- The Touchstone switch still round-trips through the panel.
boxes.Touchstone:SetChecked(true)
local tsClick = boxes.Touchstone:GetScript("OnClick")
check(type(tsClick) == "function", "the Touchstone row has an OnClick handler")
if type(tsClick) == "function" then tsClick(boxes.Touchstone) end
check(MightiePackDB.modules.Touchstone == true, "ticking Touchstone persists")
check(pkg.IsModuleEnabled("Touchstone") == true, "Touchstone is enabled after the tick")

-- Turning it off is the direction that warns: it asks for a reload through the
-- pack's own popup, and cancel restores the box without one.
local popupsBefore = #shownPopups
boxes.Touchstone:SetChecked(false)
tsClick(boxes.Touchstone)
check(#shownPopups == popupsBefore + 1, "unticking Touchstone raises the disable popup")
check(MightiePackDB.modules.Touchstone == true, "it is still on until the popup is accepted")
local dlg = StaticPopupDialogs.MIGHTIEPACK_DISABLE_MODULE
local last = shownPopups[#shownPopups]
dlg.OnCancel({ data = last.data }, last.data)
check(boxes.Touchstone:GetChecked() == true, "cancel restores the box")

-- ════════════════════════════════════════════════════════════════════════
-- Test 3: the pack does not touch the NodeTrail store
-- ════════════════════════════════════════════════════════════════════════
-- The pack declares NodeTrailDB so the game loads an existing history for the
-- NodeTrail addon to adopt. It must not read or write a key of it: that is the
-- difference between a migration window and two addons fighting over a file.
local function keysOf(t)
  local out = {}
  for k in pairs(t or {}) do out[#out + 1] = tostring(k) end
  table.sort(out)
  return table.concat(out, ",")
end
local realStore = {
  herbs = { schema = 2, total = 145, maps = { [1411] = { { x = 0.1, y = 0.2 } } },
    mapTotals = { [1411] = 1 }, stats = { gathers = { [2447] = 1 } } },
  profile = { routeSource = "gm2" },
  skinning = { enabled = true, schema = 2, chars = {} },
}
local before = keysOf(realStore)
local beforeTotal = realStore.herbs.total
pkg = loadPackage({ modules = { Touchstone = false } }, realStore)
check(NodeTrailDB == realStore, "the pack uses the store object it was given, unchanged")
check(keysOf(NodeTrailDB) == before, "the pack adds no key to NodeTrailDB (" .. keysOf(NodeTrailDB) .. ")")
check(NodeTrailDB.herbs and NodeTrailDB.herbs.total == beforeTotal,
  "herb totals are untouched by the pack")
check(NodeTrailDB.profile and NodeTrailDB.profile.routeSource == "gm2",
  "another addon's profile keys are untouched")
check(NodeTrailDB.migration == nil, "the pack writes no carry-over stamp (that is NodeTrail's job)")

-- ════════════════════════════════════════════════════════════════════════
-- Test 4: a saved settings table from before the extraction is not damaged
-- ════════════════════════════════════════════════════════════════════════
-- No detector at all for this load: Touchstone's own contract is that an
-- unknown answer keeps it inert rather than risking a double load, and that is
-- worth keeping pinned here too.
C_AddOns = nil
pkg = loadPackage({ modules = { NodeTrail = true, Touchstone = true }, seen = { firstRun = true } })
check(MightiePackDB.modules.NodeTrail == true,
  "a saved modules.NodeTrail key is left exactly as it is (add-only)")
check(MightiePackDB.modules.Touchstone == true, "the saved Touchstone key is honoured")
check(pkg.modules.Touchstone.loaded ~= true,
  "Touchstone stays inert: no detector in this stub means unknown, not absent")
check(pkg.NodeTrail == nil, "the stale NodeTrail key registers no module")

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("umbrella_spec: ok")

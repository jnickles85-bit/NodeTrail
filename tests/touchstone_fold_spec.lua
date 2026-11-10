-- Touchstone fold: the vendored module's load-time gates and Enable() path.
--
-- Run from the repo root:  lua5.1 tests/touchstone_fold_spec.lua
--
-- Parent commit (before the fold) has no Modules/Touchstone/, so every check
-- here fails there: the file is deliberately written to report failures rather
-- than crash when the directory is absent.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local TOUCH = root .. "/MightiePack/Modules/Touchstone/"

-- The 11 generated files, in TOC order. Bootstrap.lua is hand-written and is
-- loaded first in every scenario.
local VENDORED = {
  "Constants.lua",
  "UI.lua",
  "OptionsTab.lua",
  "UpgradesTab.lua",
  "LogTab.lua",
  "Diagnostics.lua",
  "Probe.lua",
  "ChestAdvisor/Verdict.lua",
  "ChestAdvisor/ChestAdvisor.lua",
  "Integration.lua",
  "Core.lua",
}

local function fileExists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

local hasFold = fileExists(TOUCH .. "Bootstrap.lua")

-- ---- WoW stub ---------------------------------------------------------------
local chat, frames, slashCount

local function makeTexture()
  local t = {}
  t.SetPoint = function() end
  t.SetAllPoints = function() end
  t.SetTexture = function() end
  t.SetColorTexture = function() end
  t.SetTexCoord = function() end
  t.SetSize = function() end
  t.Hide = function() end
  t.Show = function() end
  return t
end

local function makeFontString()
  local fs = { text = "" }
  fs.SetPoint = function() end
  fs.SetAllPoints = function() end
  fs.SetText = function(_, v) fs.text = v end
  fs.GetText = function() return fs.text end
  fs.SetTextColor = function() end
  fs.Hide = function() end
  fs.Show = function() end
  return fs
end

local function makeFrame(kind, name, parent, template)
  local f = {
    kind = kind,
    name = name,
    parent = parent,
    template = template,
    events = {},
    scripts = {},
    children = {},
  }
  f.RegisterEvent = function(_, e) f.events[e] = true end
  f.UnregisterEvent = function(_, e) f.events[e] = nil end
  f.IsEventRegistered = function(_, e) return f.events[e] == true end
  f.SetScript = function(_, k, fn) f.scripts[k] = fn end
  f.GetScript = function(_, k) return f.scripts[k] end
  f.HookScript = function() end
  f.SetPoint = function() end
  f.SetAllPoints = function() end
  f.ClearAllPoints = function() end
  f.SetSize = function() end
  f.SetWidth = function() end
  f.SetHeight = function() end
  f.SetScale = function() end
  f.SetFrameStrata = function() end
  f.SetFrameLevel = function() end
  f.GetFrameLevel = function() return 1 end
  f.SetParent = function() end
  f.Hide = function() end
  f.Show = function() end
  f.IsShown = function() return false end
  f.SetAlpha = function() end
  f.SetText = function() end
  f.CreateTexture = function() return makeTexture() end
  f.CreateFontString = function() return makeFontString() end
  frames[#frames + 1] = f
  if name then _G[name] = f end
  setmetatable(f, { __index = function() return function() end end })
  return f
end

local function resetEnv()
  chat = {}
  frames = {}
  slashCount = 0
  SlashCmdList = setmetatable({}, {
    __newindex = function(t, k, v) slashCount = slashCount + 1; rawset(t, k, v) end,
  })
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
  CreateFrame = makeFrame
  UIParent = makeFrame("Frame", "UIParent")
  frames = {} -- UIParent is scaffolding, not module output
  MightiePackTouchstoneSkip = nil
  StatForge = nil
  StatForgeDB = nil
  ChestAdvisor = nil
  ChestAdvisorDB = nil
  MightiePackDB = nil
  C_AddOns = nil
  GetAddOnInfo = nil
  IsAddOnLoaded = nil
  SLASH_TOUCHSTONE1, SLASH_TOUCHSTONE2, SLASH_TOUCHSTONE3 = nil, nil, nil
  SLASH_CHESTADVISOR1, SLASH_CHESTADVISOR2 = nil, nil
  SLASH_CHESTADVISOR3, SLASH_CHESTADVISOR4 = nil, nil
  _G.ChestAdvisor_Frame = nil
end

local function loaded(path, ...)
  local chunk, err = loadfile(path)
  check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
  if not chunk then return false end
  local ok, runErr = pcall(chunk, ...)
  check(ok, "load " .. path .. ": " .. tostring(runErr))
  return ok
end

local function loadVendored(pkg)
  for _, name in ipairs(VENDORED) do
    loaded(TOUCH .. name, "MightiePack", pkg)
  end
end

local function newPkg()
  local pkg = {}
  pkg.Print = function(_, msg) chat[#chat + 1] = tostring(msg) end
  return pkg
end

local function chatContains(needle)
  for _, m in ipairs(chat) do
    if tostring(m):find(needle, 1, true) then return true end
  end
  return false
end

-- ---- TOC and generated-file audit ------------------------------------------
do
  local tocPath = root .. "/MightiePack/MightiePack.toc"
  local f = io.open(tocPath, "r")
  if f then
    local content = f:read("*a")
    f:close()
    local body = {}
    for line in content:gmatch("[^\r\n]+") do
      local t = line:match("^%s*(.-)%s*$")
      if t ~= "" and not t:match("^#") then body[#body + 1] = t end
    end
    local start
    for i, entry in ipairs(body) do
      if entry == "Modules/Touchstone/Bootstrap.lua" then start = i break end
    end
    check(start ~= nil, "TOC lists Modules/Touchstone/Bootstrap.lua")
    if start then
      check(body[start + 1] == "Modules/Touchstone/Constants.lua", "TOC: Constants after Bootstrap")
      check(body[start + 8] == "Modules/Touchstone/ChestAdvisor/Verdict.lua", "TOC: Verdict before ChestAdvisor")
      check(body[start + 9] == "Modules/Touchstone/ChestAdvisor/ChestAdvisor.lua", "TOC: ChestAdvisor after Verdict")
      check(body[start + 10] == "Modules/Touchstone/Integration.lua", "TOC: Integration after ChestAdvisor")
      check(body[start + 11] == "Modules/Touchstone/Core.lua", "TOC: Core last in the block")
    end
    for _, entry in ipairs(body) do
      check(entry:find("marker.tga", 1, true) == nil, "marker.tga is not a TOC body entry")
    end
    local sv = content:match("## SavedVariables: ([^\r\n]+)")
    check(sv ~= nil and sv:find("StatForgeDB", 1, true) ~= nil,
      "## SavedVariables names StatForgeDB (account-wide)")
    local svpc = content:match("## SavedVariablesPerCharacter: ([^\r\n]+)")
    check(svpc ~= nil and svpc:find("ChestAdvisorDB", 1, true) ~= nil,
      "## SavedVariablesPerCharacter names ChestAdvisorDB")
    local assets = content:match("## Assets: ([^\r\n]+)")
    check(assets ~= nil and assets:find("Modules/Touchstone/ChestAdvisor/marker.tga", 1, true) ~= nil,
      "## Assets names the vendored marker.tga")
  else
    check(false, "MightiePack.toc is readable")
  end
end

-- Every generated .lua must start with the skip guard (Bootstrap runs first and
-- sets the flag; a missing guard means the body runs with the module off).
for _, name in ipairs(VENDORED) do
  local f = io.open(TOUCH .. name, "r")
  if f then
    local first = f:read("*l") or ""
    f:close()
    check(first == "if MightiePackTouchstoneSkip then return end",
      name .. " starts with the skip guard, got " .. first)
  else
    check(false, "generated file exists: " .. name)
  end
end

-- ---- 1. Module disabled: no slash, no frame, no minimap --------------------
if hasFold then
  resetEnv()
  C_AddOns = { DoesAddOnExist = function() return false end }
  local pkg = newPkg()
  loaded(TOUCH .. "Bootstrap.lua", "MightiePack", pkg)
  check(MightiePackTouchstoneSkip == false, "standalone absent -> skip is false")
  check(type(pkg.TouchstoneDetection) == "table", "detection recorded on the package")
  check(pkg.TouchstoneDetection.path == "C_AddOns.DoesAddOnExist",
    "detection path is C_AddOns.DoesAddOnExist, got " .. tostring(pkg.TouchstoneDetection.path))

  loadVendored(pkg)

  check(type(StatForge) == "table", "vendored files load (StatForge defined)")
  check(type(StatForge.Enable) == "function", "SF.Enable is defined")
  check(type(ChestAdvisor) == "table" and type(ChestAdvisor.Enable) == "function",
    "ChestAdvisor.Enable is defined")
  check(slashCount == 0, "disabled: no slash is registered (got " .. slashCount .. ")")
  check(SlashCmdList.TOUCHSTONE == nil, "disabled: /touchstone not registered")
  check(SlashCmdList.CHESTADVISOR == nil, "disabled: /up,/upgrade,/chestadvice,/ts not registered")
  check(SLASH_TOUCHSTONE1 == nil and SLASH_TOUCHSTONE2 == nil and SLASH_TOUCHSTONE3 == nil,
    "disabled: no TOUCHSTONE slash strings")
  check(SLASH_CHESTADVISOR1 == nil and SLASH_CHESTADVISOR4 == nil,
    "disabled: no CHESTADVISOR slash strings")
  check(#frames == 0, "disabled: no frame created at load (got " .. #frames .. ")")
  check(_G.ChestAdvisor_Frame == nil, "disabled: no ChestAdvisor_Frame")
  check(StatForge._settingsRegistered == nil and StatForge._compartmentTried == nil,
    "disabled: Integration surfaces not registered")

  -- The seven commands the card names must all be absent by name.
  for _, word in ipairs({ "TOUCHSTONE", "CHESTADVISOR" }) do
    check(SlashCmdList[word] == nil, "disabled: SlashCmdList." .. word .. " is nil")
  end
  for _, global in ipairs({
    "SLASH_TOUCHSTONE1", "SLASH_TOUCHSTONE2", "SLASH_TOUCHSTONE3",
    "SLASH_CHESTADVISOR1", "SLASH_CHESTADVISOR2", "SLASH_CHESTADVISOR3",
    "SLASH_CHESTADVISOR4",
  }) do
    check(_G[global] == nil, "disabled: " .. global .. " is nil")
  end
else
  check(false, "Modules/Touchstone/Bootstrap.lua exists (the fold is absent on this commit)")
end

-- ---- 2. Enable(): SF.Enable once, StatForgeDB preserved --------------------
if hasFold then
  resetEnv()
  C_AddOns = { DoesAddOnExist = function() return false end }
  local pkg = newPkg()
  loaded(TOUCH .. "Bootstrap.lua", "MightiePack", pkg)
  loaded(root .. "/MightiePack/Core.lua", "MightiePack", pkg)
  loaded(root .. "/MightiePack/Modules.lua", "MightiePack", pkg)
  loaded(TOUCH .. "Core.lua", "MightiePack", pkg)

  check(type(StatForge) == "table" and type(StatForge.Enable) == "function",
    "vendored Core.lua defines SF.Enable")

  local minimapCalls = 0
  StatForge.CreateMinimapButton = function() minimapCalls = minimapCalls + 1 end
  StatForge.UpdateMinimapButton = function() end

  local sfEnableCalls = 0
  local realEnable = StatForge.Enable
  StatForge.Enable = function()
    sfEnableCalls = sfEnableCalls + 1
    return realEnable()
  end

  StatForgeDB = { ui = { x = 12, y = -34 }, firstUse = false, keep = "untouched" }
  MightiePackDB = { modules = { NodeTrail = false, Touchstone = true } }

  pkg.EnableModules()
  pkg.EnableModules() -- second call must not re-run Enable

  check(sfEnableCalls == 1, "Enable calls SF.Enable exactly once (got " .. sfEnableCalls .. ")")
  check(type(StatForgeDB) == "table", "StatForgeDB is a table after Enable")
  check(StatForgeDB.ui and StatForgeDB.ui.x == 12 and StatForgeDB.ui.y == -34,
    "Enable does not wipe an existing StatForgeDB.ui")
  check(StatForgeDB.firstUse == false and StatForgeDB.keep == "untouched",
    "Enable does not wipe other StatForgeDB keys")
  check(minimapCalls == 1, "Enable creates the minimap button once")
  check(SlashCmdList.TOUCHSTONE ~= nil, "Enable registers the Touchstone slash")
  check(SLASH_TOUCHSTONE1 == "/touchstone", "SLASH_TOUCHSTONE1 is /touchstone")
  check(SLASH_TOUCHSTONE2 == "/sf", "SLASH_TOUCHSTONE2 is /sf")
  check(SLASH_TOUCHSTONE3 == "/statforge", "SLASH_TOUCHSTONE3 is /statforge")
  check(pkg.modules.Touchstone.loaded == true, "Touchstone is marked loaded after Enable")
end

-- ---- 3. Standalone detected: no body runs, message names the folder -------
if hasFold then
  resetEnv()
  C_AddOns = { DoesAddOnExist = function(name) return name == "Touchstone" end }
  local pkg = newPkg()
  loaded(TOUCH .. "Bootstrap.lua", "MightiePack", pkg)
  check(MightiePackTouchstoneSkip == true, "standalone detected -> skip is true")
  check(pkg.TouchstoneDetection.present == true, "detection records present=true")

  loadVendored(pkg)
  check(StatForge == nil, "standalone detected: no vendored body runs (StatForge untouched)")
  check(ChestAdvisor == nil, "standalone detected: ChestAdvisor untouched")
  check(#frames == 0, "standalone detected: no frame created")
  check(slashCount == 0, "standalone detected: no slash registered")

  loaded(root .. "/MightiePack/Core.lua", "MightiePack", pkg)
  loaded(root .. "/MightiePack/Modules.lua", "MightiePack", pkg)
  check(type(pkg.GetTouchstoneDetection) == "function", "Bootstrap exposes the detection record")
  MightiePackDB = { modules = { Touchstone = true } }
  pkg.EnableModules()
  check(StatForge == nil, "standalone detected: Enable does not run a vendored body")
  check(chatContains("standalone"), "toggle message says the standalone addon is installed")
  check(chatContains("C_AddOns.DoesAddOnExist"), "toggle message names the detection path")
  check(not chatContains("enabled."), "toggle message does not pretend the module is enabled")
end

-- ---- 4. Fallback detection: GetAddOnInfo, then unknown ---------------------
if hasFold then
  resetEnv()
  GetAddOnInfo = function(name) return name == "Touchstone" and "Touchstone" or nil end
  local pkg = newPkg()
  loaded(TOUCH .. "Bootstrap.lua", "MightiePack", pkg)
  check(pkg.TouchstoneDetection.path == "GetAddOnInfo",
    "no C_AddOns: fallback to GetAddOnInfo, got " .. tostring(pkg.TouchstoneDetection.path))
  check(pkg.TouchstoneDetection.present == true and MightiePackTouchstoneSkip == true,
    "no C_AddOns: GetAddOnInfo reports the folder present -> inert")

  loaded(root .. "/MightiePack/Core.lua", "MightiePack", pkg)
  loaded(root .. "/MightiePack/Modules.lua", "MightiePack", pkg)
  MightiePackDB = { modules = { Touchstone = true } }
  pkg.EnableModules()
  check(chatContains("GetAddOnInfo"), "toggle message reports the fallback path")

  -- No detector at all: unknown, not "absent".
  resetEnv()
  local pkg2 = newPkg()
  loaded(TOUCH .. "Bootstrap.lua", "MightiePack", pkg2)
  check(pkg2.TouchstoneDetection.path == "unknown",
    "no detector: path is unknown, got " .. tostring(pkg2.TouchstoneDetection.path))
  check(pkg2.TouchstoneDetection.present == nil,
    "no detector: present is nil (not false/absent)")
  check(MightiePackTouchstoneSkip == true,
    "no detector: module stays inert rather than risking a double load")

  loaded(root .. "/MightiePack/Core.lua", "MightiePack", pkg2)
  loaded(root .. "/MightiePack/Modules.lua", "MightiePack", pkg2)
  MightiePackDB = { modules = { Touchstone = true } }
  pkg2.EnableModules()
  check(chatContains("unknown"), "toggle message reports unknown detection")
  check(not chatContains("not installed"), "unknown is never reported as absent")
  check(not chatContains("enabled."), "unknown does not pretend the module is enabled")
end

-- ---- 6. Full enable: the real vendored surfaces come up --------------------
if hasFold then
  resetEnv()
  C_AddOns = { DoesAddOnExist = function() return false end }
  Minimap = makeFrame("Frame", "Minimap")
  local scaffolding = #frames -- Minimap itself, not module output
  hooksecurefunc = function() end
  local pkg = newPkg()
  loaded(TOUCH .. "Bootstrap.lua", "MightiePack", pkg)
  loadVendored(pkg)
  loaded(root .. "/MightiePack/Modules.lua", "MightiePack", pkg)

  check(#frames == scaffolding, "full enable: still nothing created before Enable")
  check(slashCount == 0, "full enable: no slash before Enable")

  StatForgeDB = { ui = { x = 3 }, firstUse = false }
  ChestAdvisorDB = { role = {} }
  local def = pkg.modules.Touchstone
  local before = #frames
  local ok, err = pcall(def.Enable, def)
  check(ok, "Touchstone Enable runs against the vendored files: " .. tostring(err))

  check(SlashCmdList.TOUCHSTONE ~= nil, "full enable: /touchstone,/sf,/statforge registered")
  check(SlashCmdList.CHESTADVISOR ~= nil, "full enable: /up,/upgrade,/chestadvice,/ts registered")
  check(SLASH_CHESTADVISOR4 == "/ts", "full enable: /ts is the advisor's fourth string")
  check(_G.ChestAdvisor_Frame ~= nil, "full enable: ChestAdvisor_Frame created")
  check(_G.ChestAdvisor_Frame and _G.ChestAdvisor_Frame.events.PLAYER_LOGIN == true,
    "full enable: scan frame registers PLAYER_LOGIN")
  check(_G.ChestAdvisor_Frame and _G.ChestAdvisor_Frame.events.MERCHANT_SHOW == true,
    "full enable: scan frame registers MERCHANT_SHOW")
  check(#frames > before, "full enable: frames created")
  check(type(StatForgeDB) == "table" and StatForgeDB.ui and StatForgeDB.ui.x == 3,
    "full enable: existing StatForgeDB preserved")

  local framesAfterEnable = #frames
  local ok2 = pcall(def.Enable, def)
  check(ok2 and #frames == framesAfterEnable, "full enable: Enable is idempotent")
end

-- ---- 5. Sync script exists and is reproducible -----------------------------
do
  local script = root .. "/tools/sync_touchstone.py"
  check(fileExists(script), "tools/sync_touchstone.py exists")
end

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("touchstone_fold_spec: ok")

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
check(tocLines[1] == "Core.lua", "TOC first is Core.lua, got " .. tostring(tocLines[1]))
check(tocLines[2] == "Modules.lua", "TOC second is Modules.lua, got " .. tostring(tocLines[2]))
check(tocLines[#tocLines] == "Options.lua", "TOC last is Options.lua, got " .. tostring(tocLines[#tocLines]))
local hasNodeCore = false
for _, l in ipairs(tocLines) do
  if l == "Modules/NodeTrail/Core.lua" then hasNodeCore = true end
end
check(hasNodeCore, "TOC contains Modules/NodeTrail/Core.lua")

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
  f.SetPoint = function() end
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

local function loadPackage(savedDB)
  SlashCmdList = {}
  StaticPopupDialogs = {}
  MightiePackDB = savedDB
  NodeTrailDB = nil
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
check(MightiePackDB and MightiePackDB.modules and MightiePackDB.modules.NodeTrail == true, "NodeTrail default true")
check(MightiePackDB and MightiePackDB.modules and MightiePackDB.modules.Touchstone == false, "Touchstone default false")
local order = pkg.moduleOrder or {}
local hasNT, hasTS = false, false
for _, n in ipairs(order) do
  if n == "NodeTrail" then hasNT = true end
  if n == "Touchstone" then hasTS = true end
end
check(hasNT, "moduleOrder has NodeTrail")
check(hasTS, "moduleOrder has Touchstone")
check(pkg.IsModuleEnabled("NodeTrail") == true, "NodeTrail enabled")
check(pkg.IsModuleEnabled("Touchstone") == false, "Touchstone disabled")
check(pkg.modules and pkg.modules.NodeTrail and pkg.modules.NodeTrail.loaded == true, "NodeTrail loaded")
check(type(SlashCmdList.NODETRAIL) == "function", "NODETRAIL slash registered")
check(SLASH_NODETRAIL2 == "/nt", "SLASH_NODETRAIL2 is /nt")
check(type(SlashCmdList.MIGHTIEPACK) == "function", "MIGHTIEPACK slash registered")
check(registeredCategory ~= nil, "settings category registered")
check(registeredCategory and registeredCategory.frame == pkg.optionsPanel, "category frame is optionsPanel")
check(type(NodeTrailDB) == "table", "NodeTrailDB is table")

local before = #chat
SlashCmdList.NODETRAIL("help")
local found = false
for i = before + 1, #chat do
  if tostring(chat[i]):find("/nt start", 1, true) then found = true end
end
check(found, "help mentions /nt start")

before = #chat
SlashCmdList.MIGHTIEPACK("status")
local foundOn, foundOff = false, false
for i = before + 1, #chat do
  local m = tostring(chat[i])
  if m:find("NodeTrail: on", 1, true) then foundOn = true end
  if m:find("Touchstone: off (coming soon)", 1, true) then foundOff = true end
end
check(foundOn, "status shows NodeTrail on")
check(foundOff, "status shows Touchstone off (coming soon)")

openedId = nil
SlashCmdList.MIGHTIEPACK("")
check(openedId == 42, "open options sets openedId 42")

-- Test 2
local panel = pkg.optionsPanel
local onShow = panel:GetScript("OnShow")
onShow(panel)
onShow(panel)
local cbCount = 0
for _, f in ipairs(frames) do
  if f.template == "UICheckButtonTemplate" then cbCount = cbCount + 1 end
end
check(cbCount == #pkg.moduleOrder, "checkbox count matches moduleOrder, got " .. cbCount .. " expected " .. #pkg.moduleOrder)
local boxes = pkg.optionsBoxes
check(boxes ~= nil, "optionsBoxes exists")
check(boxes.NodeTrail and boxes.NodeTrail:GetChecked() == true, "NodeTrail box checked")
check(boxes.Touchstone and boxes.Touchstone:GetChecked() == false, "Touchstone box unchecked")
check(boxes.Touchstone and boxes.Touchstone:IsEnabled() == false, "Touchstone box disabled")

local popup
boxes.NodeTrail:SetChecked(false)
local onClick = boxes.NodeTrail:GetScript("OnClick")
onClick(boxes.NodeTrail)
check(#shownPopups == 1, "one popup shown")
if #shownPopups >= 1 then
  popup = shownPopups[1]
  check(popup.which == "MIGHTIEPACK_DISABLE_MODULE", "popup which")
  check(popup.data and popup.data.name == "NodeTrail", "popup data.name")
end
check(MightiePackDB.modules.NodeTrail == true, "NodeTrail still true before confirm")

local dlg = StaticPopupDialogs.MIGHTIEPACK_DISABLE_MODULE
dlg.OnCancel({ data = popup.data }, popup.data)
check(boxes.NodeTrail:GetChecked() == true, "cancel restores checked")
check(reloads == 0, "no reload on cancel")

boxes.NodeTrail:SetChecked(false)
dlg.OnHide({ data = popup.data })
check(boxes.NodeTrail:GetChecked() == true, "hide restores checked")

dlg.OnAccept({ data = popup.data }, popup.data)
check(MightiePackDB.modules.NodeTrail == false, "accept disables NodeTrail")
check(reloads == 1, "reload on accept")

-- Test 3
local saved = MightiePackDB
pkg = loadPackage(saved)
check(SlashCmdList.NODETRAIL == nil, "NodeTrail slash not registered when disabled")
check(pkg.modules and pkg.modules.NodeTrail and pkg.modules.NodeTrail.loaded ~= true, "NodeTrail not loaded")
check(pkg.IsModuleEnabled("NodeTrail") == false, "NodeTrail disabled")

local panel3 = pkg.optionsPanel
local onShow3 = panel3:GetScript("OnShow")
onShow3(panel3)
local boxes3 = pkg.optionsBoxes
check(boxes3.NodeTrail:GetChecked() == false, "NodeTrail box unchecked after disable")
boxes3.NodeTrail:SetChecked(true)
local onClick3 = boxes3.NodeTrail:GetScript("OnClick")
onClick3(boxes3.NodeTrail)
check(MightiePackDB.modules.NodeTrail == true, "re-tick enables NodeTrail")
check(pkg.modules.NodeTrail.loaded == true, "NodeTrail loaded after re-tick")
check(type(SlashCmdList.NODETRAIL) == "function", "NodeTrail slash registered after re-tick")
check(reloads == 1, "no extra reload on re-tick")
check(#shownPopups == 1, "no new popup on re-tick")

-- Test 4
pkg = loadPackage({ modules = { NodeTrail = false, Touchstone = true } })
check(MightiePackDB.modules.NodeTrail == false, "saved NodeTrail false preserved")
check(pkg.IsModuleEnabled("Touchstone") == false, "Touchstone stub never enabled")

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("umbrella_spec: ok")

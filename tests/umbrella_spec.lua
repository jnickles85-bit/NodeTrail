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
check(MightiePackDB and MightiePackDB.modules and MightiePackDB.modules.NodeTrail == true, "NodeTrail default true")
check(MightiePackDB and MightiePackDB.modules and MightiePackDB.modules.Touchstone == false, "Touchstone default false")
local order = pkg.moduleOrder or {}
local hasNT, hasTS, hasSkinModule = false, false, false
for _, n in ipairs(order) do
  if n == "NodeTrail" then hasNT = true end
  if n == "Touchstone" then hasTS = true end
  if n == "Skinning" then hasSkinModule = true end
end
check(hasNT, "moduleOrder has NodeTrail")
check(hasTS, "moduleOrder has Touchstone")
check(not hasSkinModule, "moduleOrder has NO Skinning entry (nested under NodeTrail, t_5507a0ba)")
check(pkg.modules.Skinning == nil, "Skinning is not a registered module")
check(pkg.moduleDefaults.Skinning == nil, "moduleDefaults has no Skinning entry")
check(MightiePackDB.modules.Skinning == nil, "no MightiePackDB.modules.Skinning key is written")
check(type(pkg.Skinning) == "table" and type(pkg.Skinning.Probe) == "table",
  "the skinning probe still loads (owned by NodeTrail)")
check(pkg.IsModuleEnabled("NodeTrail") == true, "NodeTrail enabled")
check(pkg.IsModuleEnabled("Touchstone") == false, "Touchstone disabled")
check(pkg.modules and pkg.modules.NodeTrail and pkg.modules.NodeTrail.loaded == true, "NodeTrail loaded")
check(type(SlashCmdList.NODETRAIL) == "function", "NODETRAIL slash registered")
check(SLASH_NODETRAIL2 == "/nt", "SLASH_NODETRAIL2 is /nt")
check(type(SlashCmdList.MIGHTIEPACK) == "function", "MIGHTIEPACK slash registered")
check(registeredCategory ~= nil, "settings category registered")
check(registeredCategory and registeredCategory.frame == pkg.optionsPanel, "category frame is optionsPanel")
check(type(NodeTrailDB) == "table", "NodeTrailDB is table")
check(type(pkg.NodeTrail) == "table" and type(pkg.NodeTrail.GetSkinDB) == "function",
  "NodeTrail owns the skinning sub-toggle accessors")
-- t_ba64b076: the recorder is ON by default, so a first login arms the probe
-- with no setup. The migration marker is written here too (there is nothing to
-- migrate on a fresh install) and no user-set flag is invented: a default is
-- not a choice.
check(type(pkg.NodeTrail.IsSkinningEnabled) == "function"
  and pkg.NodeTrail.IsSkinningEnabled() == true,
  "skinning sub-toggle defaults ON (t_ba64b076)")
check(NodeTrailDB.skinning ~= nil and NodeTrailDB.skinning.enabled == true,
  "sub-toggle persisted at NodeTrailDB.skinning.enabled (default true)")
check(NodeTrailDB.skinning ~= nil and NodeTrailDB.skinning.skinMigration == 1,
  "the one-time skinning migration is marked as run on a fresh install")
check(NodeTrailDB.skinning ~= nil and NodeTrailDB.skinning.skinUserSet ~= true,
  "no skinUserSet flag on a fresh install (the default is not a player choice)")
check(pkg.Skinning.Probe.enabled == true, "the probe is armed at first login (default ON)")

-- t_ba64b076, the card's own observable: "/mp skindiag reports the sub-option
-- on" for a fresh install. The real dump command, first line only.
local skBefore = #chat
SlashCmdList.MIGHTIEPACK("skindiag dump")
local skFirst = nil
for i = skBefore + 1, #chat do
  local m = tostring(chat[i])
  if m:find("capture ", 1, true) then skFirst = m break end
end
check(skFirst ~= nil and skFirst:find("sub-option ON", 1, true) ~= nil,
  "/mp skindiag dump reports the sub-option ON for a fresh install (got: " .. tostring(skFirst) .. ")")
check(skFirst ~= nil and skFirst:find("NodeTrailDB.skinning", 1, true) ~= nil,
  "/mp skindiag dump says the records are saved to NodeTrailDB.skinning")

local before = #chat
SlashCmdList.NODETRAIL("help")
local found = false
for i = before + 1, #chat do
  if tostring(chat[i]):find("/nt start", 1, true) then found = true end
end
check(found, "help mentions /nt start")

before = #chat
SlashCmdList.MIGHTIEPACK("status")
local foundOn, foundOff, foundSkinLine, foundSkinOnNT = false, false, false, false
for i = before + 1, #chat do
  local m = tostring(chat[i])
  if m:find("NodeTrail: on", 1, true) then foundOn = true end
  if m:find("Touchstone: off", 1, true) then foundOff = true end
  if m:find("Skinning:", 1, true) then foundSkinLine = true end
  if m:find("NodeTrail: on (loaded) - skinning on", 1, true) then foundSkinOnNT = true end
end
check(foundOn, "status shows NodeTrail on")
check(foundOff, "status shows Touchstone off")
check(not foundSkinLine, "status prints NO separate 'Skinning:' module line")
check(foundSkinOnNT, "status reports skinning on the NodeTrail line: 'NodeTrail: on (loaded) - skinning on'")

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
check(cbCount == #pkg.moduleOrder + 3,
  "checkbox count = moduleOrder + 3 NodeTrail sub-options (skinning, auto-refresh, skinning circle), got " .. cbCount
  .. " expected " .. (#pkg.moduleOrder + 3))
local boxes = pkg.optionsBoxes
check(boxes ~= nil, "optionsBoxes exists")
check(boxes.NodeTrail and boxes.NodeTrail:GetChecked() == true, "NodeTrail box checked")
check(boxes.Touchstone and boxes.Touchstone:GetChecked() == false, "Touchstone box unchecked")
check(boxes.Touchstone and boxes.Touchstone:IsEnabled() == true, "Touchstone box enabled (no longer a stub)")

-- The skinning sub-option is a row of its own under NodeTrail, indented and
-- not a sibling module (t_5507a0ba).
local skinBox = boxes.Skinning
check(skinBox ~= nil, "a skinning sub-option checkbox exists")
check(skinBox and skinBox.template == "UICheckButtonTemplate",
  "the sub-option is a real checkbutton")
if skinBox then
  check(skinBox:GetChecked() == true, "skinning sub-option checked (default ON, t_ba64b076)")
  check(skinBox:IsEnabled() == true, "skinning sub-option is usable while NodeTrail is on")
  local function point1(box)
    return box and rawget(box, "pointArgs") and rawget(box, "pointArgs")[1] or nil
  end
  local ntPt, skPt = point1(boxes.NodeTrail), point1(skinBox)
  check(skPt ~= nil, "the sub-option was positioned")
  if ntPt and skPt then
    -- Skinning is anchored under the NodeTrail checkbox and indented.
    check(skPt[2] == boxes.NodeTrail, "skinning sub-option is anchored to the NodeTrail checkbox")
    check(skPt[3] == "BOTTOMLEFT", "skinning sub-option sits under NodeTrail (rel=" .. tostring(skPt[3]) .. ")")
    check((skPt[4] or 0) > 0, "skinning sub-option is indented relative to NodeTrail (x=" .. tostring(skPt[4]) .. ")")
  end
  local touchPt = point1(boxes.Touchstone)
  check(touchPt ~= nil, "Touchstone row was positioned")
  check(ntPt ~= nil and ntPt[2] == boxes.Touchstone,
    "NodeTrail is anchored under Touchstone (vertical module flow)")
  check(ntPt and ntPt[3] == "BOTTOMLEFT", "NodeTrail sits below Touchstone")
  check(skPt ~= nil and skPt[2] == boxes.NodeTrail,
    "the skinning sub-option sits under the NodeTrail row")
end

-- t_2bc15917 / t_57550700: "Auto-refresh route" is the second indented NodeTrail
-- row — the visible control for the pick-triggered rebuild. It is ON by default
-- (Mightie's final call); what changed is that a re-plan now needs a tranche of
-- gathers, not one per herb. (The /reload restore is not this switch.)
local autoBox = boxes.AutoRefresh
check(autoBox ~= nil, "an auto-refresh route sub-option checkbox exists")
check(autoBox and autoBox.template == "UICheckButtonTemplate",
  "the auto-refresh sub-option is a real checkbutton")
if autoBox then
  check(autoBox:GetChecked() == true, "auto-refresh sub-option is ON by default (Mightie's final call)")
  check(autoBox:IsEnabled() == true, "auto-refresh sub-option is usable while NodeTrail is on")
  local function point1b(box)
    return box and rawget(box, "pointArgs") and rawget(box, "pointArgs")[1] or nil
  end
  local copyBtn = boxes.SkinDiagCopy
  check(copyBtn ~= nil, "a Copy skinning diagnostics button sits under the skinning row")
  local function pointRel(box)
    return box and rawget(box, "pointArgs") and rawget(box, "pointArgs")[1] or nil
  end
  local cp = pointRel(copyBtn)
  if cp and skinBox then
    check(cp[2] == skinBox, "diagnostics button is anchored under the skinning row")
    check(cp[3] == "BOTTOMLEFT", "diagnostics button sits under the skinning row")
  end
  local ap, sp = point1b(autoBox), point1b(skinBox)
  check(ap ~= nil, "the auto-refresh row was positioned")
  if ap and copyBtn then
    check(ap[2] == copyBtn, "auto-refresh row is anchored under the diagnostics button")
    check(ap[3] == "BOTTOMLEFT", "auto-refresh row sits under the diagnostics button")
  elseif ap and sp then
    check(ap[2] == skinBox, "auto-refresh row is anchored under the skinning row")
    check(ap[3] == "BOTTOMLEFT", "auto-refresh row sits under the skinning row")
  end
  check(type(autoBox:GetScript("OnClick")) == "function", "auto-refresh row has an OnClick handler")
end

-- t_b46e5e87: "Skinning farming circle" is the third indented NodeTrail row —
-- its own switch, persisted at NodeTrailDB.skinroute.enabled and independent of
-- the probe and of the herb route. ON by default; the circle itself stays
-- hidden until the map has enough skinned corpses and the character is a
-- skinner, so the default cannot draw anything by itself.
local skinRouteBox = boxes.SkinRoute
check(skinRouteBox ~= nil, "a skinning farming circle sub-option checkbox exists")
check(skinRouteBox and skinRouteBox.template == "UICheckButtonTemplate",
  "the skinning circle sub-option is a real checkbutton")
if skinRouteBox then
  check(skinRouteBox:GetChecked() == true, "skinning circle sub-option is ON by default")
  check(skinRouteBox:IsEnabled() == true, "skinning circle sub-option is usable while NodeTrail is on")
  local function point1c(box)
    return box and rawget(box, "pointArgs") and rawget(box, "pointArgs")[1] or nil
  end
  local rp, ap = point1c(skinRouteBox), point1c(autoBox)
  check(rp ~= nil, "the skinning circle row was positioned")
  if rp and ap then
    check(rp[2] == autoBox, "skinning circle row is anchored under the auto-refresh row")
    check(rp[3] == "BOTTOMLEFT", "skinning circle row sits under the auto-refresh row")
  end
  check(type(skinRouteBox:GetScript("OnClick")) == "function", "skinning circle row has an OnClick handler")
end

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

-- The skinning sub-option is greyed out / inert while NodeTrail is off.
local skin3 = boxes3.Skinning
check(skin3 ~= nil, "the skinning sub-option exists when NodeTrail is off")
check(skin3 and skin3:IsEnabled() == false, "sub-option is greyed out (disabled) while NodeTrail is off")
if skin3 then
  skin3:SetChecked(true)
  local skinClick = skin3:GetScript("OnClick")
  check(type(skinClick) == "function", "the sub-option has an OnClick handler")
  if type(skinClick) == "function" then skinClick(skin3) end
  -- t_ba64b076: the greyed row is inert, so it must not record a CHOICE. What
  -- it snaps back to is the stored value (the default, ON); no user-set flag
  -- may appear from a click that could not be honoured.
  local greyDB = type(pkg.NodeTrail.GetSkinDB) == "function" and pkg.NodeTrail.GetSkinDB() or nil
  check(type(greyDB) == "table" and greyDB.skinUserSet ~= true,
    "clicking the greyed sub-option records no player choice (no skinUserSet)")
  check(skin3:GetChecked() == true,
    "clicking the greyed sub-option snaps back to the stored value (ON)")
  check(pkg.Skinning.Probe.enabled ~= true, "probe stays off while NodeTrail is off")
end
check(#shownPopups == 1, "the inert sub-option raises no popup")

boxes3.NodeTrail:SetChecked(true)
local onClick3 = boxes3.NodeTrail:GetScript("OnClick")
onClick3(boxes3.NodeTrail)
check(MightiePackDB.modules.NodeTrail == true, "re-tick enables NodeTrail")
check(pkg.modules.NodeTrail.loaded == true, "NodeTrail loaded after re-tick")
check(type(SlashCmdList.NODETRAIL) == "function", "NodeTrail slash registered after re-tick")
check(reloads == 1, "no extra reload on re-tick")
check(#shownPopups == 1, "no new popup on re-tick")
check(boxes3.Skinning:IsEnabled() == true, "sub-option becomes usable when NodeTrail is re-ticked")

-- t_ba64b076: the sub-option is ON by default, so BOTH directions are
-- exercised here. An untick is the player's explicit opt-out and must be
-- written as such (skinUserSet); a tick is the explicit opt-in. Neither needs a
-- reload, and neither raises a popup.
check(boxes3.Skinning:GetChecked() == true,
  "sub-option is checked once NodeTrail is on (default ON, t_ba64b076)")
check(pkg.Skinning.Probe.enabled == true, "the probe is armed by the default, with no setup")

boxes3.Skinning:SetChecked(false)
boxes3.Skinning:GetScript("OnClick")(boxes3.Skinning)
check(NodeTrailDB.skinning ~= nil and NodeTrailDB.skinning.enabled == false,
  "unticking persists enabled = false")
check(NodeTrailDB.skinning ~= nil and NodeTrailDB.skinning.skinUserSet == true,
  "unticking writes skinUserSet (an explicit off, not a default)")
check(pkg.Skinning.Probe.enabled == false, "unticking stops the probe immediately (no reload)")
check(#shownPopups == 1, "no popup when the sub-option is turned off")
check(reloads == 1, "no reload when the sub-option is turned off")

local stOff = #chat
SlashCmdList.MIGHTIEPACK("status")
local foundSkinOff = false
for i = stOff + 1, #chat do
  if tostring(chat[i]):find("NodeTrail: on (loaded) - skinning off", 1, true) then foundSkinOff = true end
end
check(foundSkinOff, "status shows 'NodeTrail: on (loaded) - skinning off' after the opt-out")

-- Turning it back ON: persisted at NodeTrailDB.skinning.enabled,
-- probe armed immediately, no reload popup (a reload is NOT required).
boxes3.Skinning:SetChecked(true)
boxes3.Skinning:GetScript("OnClick")(boxes3.Skinning)
check(type(NodeTrailDB.skinning) == "table" and NodeTrailDB.skinning.enabled == true,
  "sub-option persists in NodeTrailDB.skinning.enabled")
check(NodeTrailDB.skinning ~= nil and NodeTrailDB.skinning.skinUserSet == true,
  "the opt-in keeps the user-set flag (both directions are choices)")
check(MightiePackDB.modules.Skinning == nil, "the sub-toggle is NOT written to MightiePackDB.modules")
check(pkg.Skinning.Probe.enabled == true, "ticking the sub-option arms the probe immediately")
check(#shownPopups == 1, "no reload popup for the sub-option")
check(reloads == 1, "no reload for the sub-option")

local stBefore = #chat
SlashCmdList.MIGHTIEPACK("status")
local foundSkinOn = false
for i = stBefore + 1, #chat do
  if tostring(chat[i]):find("NodeTrail: on (loaded) - skinning on", 1, true) then foundSkinOn = true end
end
check(foundSkinOn, "status shows 'NodeTrail: on (loaded) - skinning on'")

-- Test 4
pkg = loadPackage({ modules = { NodeTrail = false, Touchstone = true } })
check(MightiePackDB.modules.NodeTrail == false, "saved NodeTrail false preserved")
check(pkg.IsModuleEnabled("Touchstone") == true, "saved Touchstone true preserved")
check(pkg.modules.Touchstone.loaded ~= true,
  "Touchstone stays inert: no detector in this stub means unknown, not absent")

-- Test 5: a stale MightiePackDB.modules.Skinning (written by the previous
-- build) is kept but inert — the sub-toggle lives in NodeTrailDB.
pkg = loadPackage({ modules = { NodeTrail = true, Skinning = true } })
check(MightiePackDB.modules.Skinning == true, "the stale modules.Skinning key is not lost")
-- t_ba64b076: the stale key has no say over the persisted value either way;
-- what the probe follows now is the DEFAULT (ON), and the stale key must not
-- be mistaken for a player choice.
check(type(pkg.NodeTrail.IsSkinningEnabled) == "function"
  and pkg.NodeTrail.IsSkinningEnabled() == true,
  "the stale modules.Skinning key does not decide the sub-option: the default (ON) applies")
check(NodeTrailDB.skinning ~= nil and NodeTrailDB.skinning.skinUserSet ~= true,
  "the stale key is not copied in as a player choice (no skinUserSet)")
check(pkg.Skinning.Probe.enabled == true, "the probe is armed by the default, not by the stale key")

-- Test 6: the sub-toggle round-trips through NodeTrailDB and arms the probe
-- at boot, without losing the keys that were already there.
pkg = loadPackage({ modules = { NodeTrail = true } },
  { profile = { routeSource = "gm2" }, skinning = { enabled = true } })
check(NodeTrailDB.skinning ~= nil and NodeTrailDB.skinning.enabled == true,
  "saved sub-toggle survives the reload")
check(NodeTrailDB.profile.routeSource == "gm2", "existing NodeTrailDB keys are not lost")
check(type(pkg.NodeTrail.IsSkinningEnabled) == "function"
  and pkg.NodeTrail.IsSkinningEnabled() == true,
  "NodeTrail reads the saved sub-toggle")
check(pkg.Skinning.Probe.enabled == true, "the probe is armed at boot when the sub-toggle is on")
check(NodeTrailDB.skinning ~= nil and NodeTrailDB.skinning.enabled == true,
  "and the saved value is not rewritten to false")

-- Test 7: a pre-t_5507a0ba NodeTrailDB (no skinning table) gains the key
-- without losing anything — and, since t_ba64b076, gains it with the new
-- default (ON) and the migration marker already written.
pkg = loadPackage({ modules = { NodeTrail = true } }, { profile = { routeSource = "gm2" } })
check(type(pkg.NodeTrail.IsSkinningEnabled) == "function"
  and pkg.NodeTrail.IsSkinningEnabled() == true,
  "an old NodeTrailDB gets the new default (ON)")
check(NodeTrailDB.profile.routeSource == "gm2", "the old profile is untouched")
check(type(NodeTrailDB.skinning) == "table", "the sub-toggle key is added lazily")
check(NodeTrailDB.skinning ~= nil and NodeTrailDB.skinning.skinMigration == 1,
  "and the one-time migration is marked as run with it")

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("umbrella_spec: ok")

-- bugreport_spec.lua
-- Builds the /mp bug report text against stubbed client APIs.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. msg .. "\n")
  end
end

local chat = {}
DEFAULT_CHAT_FRAME = {
  AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end,
}

SlashCmdList = {}
StaticPopupDialogs = {}
StaticPopup_Show = function() end
OKAY = "Okay"
CANCEL = "Cancel"
ReloadUI = function() end
UIParent = {}
UISpecialFrames = {}
GameTooltip = {
  SetOwner = function() end,
  SetText = function() end,
  AddLine = function() end,
  Show = function() end,
  Hide = function() end,
}

local currentHandler
function geterrorhandler()
  return currentHandler
end
function seterrorhandler(fn)
  local prev = currentHandler
  currentHandler = fn
  return prev
end

-- Privacy canaries: the builder must never read these into the report.
GetUnitName = function() return "SecretPlayer" end
UnitName = function() return "SecretPlayer" end
GetRealmName = function() return "SecretRealm" end
GetPlayerInfoByGUID = function() return "SecretPlayer", "SecretRealm", "Priest" end
GetUnitGUID = function() return "Player-00-SECRET" end

GetAddOnMetadata = function(name, what)
  if name == "MightiePack" and what == "Version" then return "0.3.0-beta" end
  if name == "MightiePack" and what == "Interface" then return "16001" end
  return nil
end
C_AddOns = {
  GetAddOnMetadata = function(name, what)
    if name == "MightiePack" and what == "Version" then return "0.3.0-from-caddons" end
    if name == "MightiePack" and what == "Interface" then return "16001" end
    return nil
  end,
}
GetBuildInfo = function()
  return "1.60.1", "54321", "Nov 10 2026", 16001
end
UnitClass = function() return "Priest", "PRIEST" end
UnitLevel = function() return 18 end
GetRealZoneText = function() return "Tirisfal Glades" end
C_Map = { GetBestMapForUnit = function(unit)
  if unit == "player" then return 1420 end
  return nil
end }

local frames, editboxes, buttons = {}, {}, {}
local callLog = { focus = 0, highlight = 0 }

local function mkBase(kind)
  local o = {
    Kind = kind, Name = nil, Template = nil,
    scripts = {}, events = {}, text = nil, shown = false,
  }
  o.SetScript = function(self, n, f) self.scripts[n] = f end
  o.GetScript = function(self, n) return self.scripts[n] end
  o.SetPoint = function() end
  o.SetSize = function(self, w, h) self.size = { w, h } end
  o.SetWidth = function(self, w) self.width = w end
  o.SetText = function(self, t) self.text = tostring(t) end
  o.GetText = function(self) return self.text end
  o.Show = function(self) self.shown = true end
  o.Hide = function(self) self.shown = false end
  o.RegisterEvent = function(self, n) self.events[n] = true end
  o.UnregisterEvent = function(self, n) self.events[n] = nil end
  o.CreateFontString = function()
    return mkBase("FontString")
  end
  o.SetMovable = function() end
  o.EnableMouse = function() end
  o.RegisterForDrag = function() end
  o.SetFrameStrata = function() end
  o.SetBackdrop = function() end
  o.SetMultiLine = function() end
  o.SetAutoFocus = function() end
  o.SetTextInsets = function() end
  o.SetFocus = function(self)
    callLog.focus = callLog.focus + 1
    self.hasFocus = true
  end
  o.HighlightText = function(self)
    callLog.highlight = callLog.highlight + 1
    self.highlighted = true
  end
  return o
end

CreateFrame = function(kind, name, parent, template)
  local o = mkBase(kind or "Frame")
  o.Name = name
  o.Template = template
  if kind == "Button" then buttons[#buttons + 1] = o end
  if kind == "EditBox" then editboxes[#editboxes + 1] = o end
  frames[#frames + 1] = o
  return o
end

local function loadfile_into(path, addon, pkg)
  local chunk = assert(loadfile(path), "loadfile " .. path)
  local ok, err = pcall(chunk, addon, pkg)
  check(ok, "load " .. path .. ": " .. tostring(err))
end

MightiePackDB = nil
local pkg = {}
loadfile_into(root .. "/MightiePack/Core.lua", "MightiePack", pkg)
loadfile_into(root .. "/MightiePack/Modules.lua", "MightiePack", pkg)
loadfile_into(root .. "/MightiePack/BugReport.lua", "MightiePack", pkg)

check(type(pkg.BuildBugReport) == "function", "BuildBugReport exported")
check(type(pkg.OpenBugReport) == "function", "OpenBugReport exported")
check(pkg.BUG_DISCORD_INVITE == nil, "BUG_DISCORD_INVITE starts nil")
check(type(currentHandler) == "function", "seterrorhandler chained at load")

pkg.RegisterModule("NodeTrail", {
  title = "NodeTrail",
  Enable = function() return true end,
})

for _, f in ipairs(frames) do
  if f.events.ADDON_LOADED and f.scripts.OnEvent then
    local ok, e = pcall(f.scripts.OnEvent, f, "ADDON_LOADED", "MightiePack")
    check(ok, "ADDON_LOADED: " .. tostring(e))
  end
end

local function has(text, needle, label)
  check(type(text) == "string" and text:find(needle, 1, true) ~= nil,
    label .. " (missing '" .. needle .. "')")
end
local function lacks(text, needle, label)
  check(type(text) == "string" and text:find(needle, 1, true) == nil,
    label .. " (should not contain '" .. needle .. "')")
end

-- ── sample report (C_AddOns metadata wins over the legacy global) ──
local report = pkg.BuildBugReport()
check(type(report) == "string", "BuildBugReport returns a string")
has(report, "MightiePack bug report", "title")
has(report, "Addon version: 0.3.0-from-caddons", "C_AddOns.GetAddOnMetadata version")
has(report, "Client version: 1.60.1 (build 54321, interface 16001)", "GetBuildInfo version/build/interface")
has(report, "Module(s): NodeTrail", "enabled modules")
lacks(report, "Touchstone", "disabled module omitted")
has(report, "Character: Priest 18", "class and level")
has(report, "Zone/map: Tirisfal Glades (1420)", "zone and map id")
has(report, "Steps to reproduce:\n\nExpected:\n\nActual:\n\n", "blank repro fields")
has(report, "Lua error: none", "no captured error yet")
has(report, "Screenshot: (attach in Discord)", "screenshot reminder")
lacks(report, "SecretPlayer", "no character name")
lacks(report, "SecretRealm", "no realm name")
lacks(report, "Player-00-SECRET", "no GUID")

print("── sample report ─────────────────────────")
print(report)
print("──────────────────────────────────────────")

-- ── legacy GetAddOnMetadata only ──
local savedCAddOns = C_AddOns
C_AddOns = nil
local legacy = pkg.BuildBugReport()
has(legacy, "Addon version: 0.3.0-beta", "legacy GetAddOnMetadata version")
C_AddOns = savedCAddOns

-- ── C_AddOns only (no legacy global) ──
local savedLegacy = GetAddOnMetadata
GetAddOnMetadata = nil
local modern = pkg.BuildBugReport()
has(modern, "Addon version: 0.3.0-from-caddons", "C_AddOns-only version")
GetAddOnMetadata = savedLegacy

-- ── missing C_Map degrades, does not error ──
local savedMap = C_Map
C_Map = nil
local noMap, noMapErr = pcall(pkg.BuildBugReport)
check(noMap, "missing C_Map does not error: " .. tostring(noMapErr))
if noMap then
  has(noMapErr, "Zone/map: Tirisfal Glades", "zone name without map id")
  lacks(noMapErr, "(1420)", "no fabricated map id")
end
C_Map = savedMap

-- ── error not mentioning MightiePack is ignored ──
pkg.ObserveLuaError("Interface\\AddOns\\SomeOtherAddon\\Foo.lua:12: boom")
local stillNone = pkg.BuildBugReport()
has(stillNone, "Lua error: none", "unrelated error ignored")

-- ── captured MightiePack error, paths sanitized ──
pkg.ObserveLuaError("/home/someone/Interface/AddOns/MightiePack/Core.lua:42: something broke")
local withErr = pkg.BuildBugReport()
has(withErr, "Lua error:", "captured error section")
has(withErr, "Interface\\AddOns\\MightiePack\\Core.lua:42: something broke", "pack error kept, AddOns-relative")
lacks(withErr, "/home/someone", "user path stripped")
lacks(withErr, "/workspace", "no box/workspace paths")
lacks(withErr, "Lua error: none", "error replaces 'none'")

-- ── handler itself filters the same way ──
currentHandler("Interface\\AddOns\\Other\\x.lua:1: nope")
local afterOther = pkg.BuildBugReport()
has(afterOther, "something broke", "unrelated handler error does not replace ours")

currentHandler("Interface\\AddOns\\MightiePack\\Options.lua:9: newer boom")
local afterOurs = pkg.BuildBugReport()
has(afterOurs, "Options.lua:9: newer boom", "handler stores a newer pack error")
lacks(afterOurs, "something broke", "only the most recent error is kept")

-- ── BugGrabber, when present, wins ──
BugGrabber = {
  GetDB = function()
    return {
      { message = "older MightiePack issue", stack = "stack1" },
      { message = "latest MightiePack explosion", stack = "Interface\\AddOns\\MightiePack\\X.lua:1" },
    }
  end,
}
local grabbed = pkg.BuildBugReport()
has(grabbed, "latest MightiePack explosion", "BugGrabber latest pack error preferred")
lacks(grabbed, "newer boom", "BugGrabber preferred over the chained handler")
BugGrabber = nil

-- ── UI + slash + hint ──
check(pkg.CopyHint() == "Press Ctrl+C to copy, then paste in #mightiepack-bugs on Discord",
  "hint names the channel when invite is nil")
SlashCmdList.MIGHTIEPACK("bug")
local form, edit
for _, f in ipairs(frames) do
  if f.Name == "MightiePackBugReportFrame" then form = f end
end
for _, e in ipairs(editboxes) do
  if e.Name == "MightiePackBugReportEdit" then edit = e end
end
check(form ~= nil and form.shown == true, "/mp bug shows the popup")
check(edit ~= nil and type(edit.text) == "string" and edit.text:find("MightiePack bug report", 1, true),
  "popup EditBox is pre-filled")
check(edit and edit.hasFocus == true, "EditBox SetFocus on open")
check(edit and edit.highlighted == true, "EditBox HighlightText on open")

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("bugreport_spec: ok")

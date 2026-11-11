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
ChatFontNormal = { name = "ChatFontNormal" }
GameFontHighlight = { name = "GameFontHighlight" }
UISpecialFrames = {}
GameTooltip = {
  SetOwner = function() end,
  SetText = function() end,
  AddLine = function() end,
  Show = function() end,
  Hide = function() end,
}

local currentHandler
local prevCalls = {}
local function originalPrev(...)
  prevCalls[#prevCalls + 1] = { n = select("#", ...), ... }
  return "prev-ok", 42
end
currentHandler = originalPrev
function geterrorhandler()
  return currentHandler
end
function seterrorhandler(fn)
  currentHandler = fn
  return currentHandler
end

-- Privacy canaries: the builder must never read these into the report.
GetUnitName = function() return "SecretPlayer" end
UnitName = function() return "SecretPlayer" end
GetRealmName = function() return "SecretRealm" end
GetPlayerInfoByGUID = function() return "SecretPlayer", "SecretRealm", "Priest" end
GetUnitGUID = function() return "Player-1234-ABCDEF" end

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
local callLog = { focus = 0, highlight = 0, clearFocus = 0 }

local function mkBase(kind)
  local o = {
    Kind = kind, Name = nil, Template = nil,
    scripts = {}, events = {}, text = nil, shown = false,
  }
  o.SetScript = function(self, n, f) self.scripts[n] = f end
  o.GetScript = function(self, n) return self.scripts[n] end
  o.points = {}
  o.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
  o.ClearAllPoints = function(self) self.points = {} end
  o.SetSize = function(self, w, h) self.size = { w, h }; self.width, self.height = w, h end
  o.SetWidth = function(self, w) self.width = w end
  o.SetHeight = function(self, h) self.height = h end
  o.SetFontObject = function(self, f) self.fontObject = f end
  o.SetFont = function(self, ...) self.font = { ... } end
  o.SetTextColor = function(self, r, g, b, a) self.textColor = { r, g, b, a } end
  o.EnableKeyboard = function(self, v) self.keyboardEnabled = v ~= false end
  o.EnableMouse = function(self, v) self.mouseEnabled = (v ~= false) end
  o.SetToplevel = function(self, v) self.toplevel = v and true or false end
  o.SetFrameLevel = function(self, n) self.frameLevel = n end
  o.Raise = function(self) self.raised = true end
  o.SetText = function(self, t) self.text = tostring(t) end
  o.GetText = function(self) return self.text end
  o.Show = function(self) self.shown = true end
  o.Hide = function(self)
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
  end
  o.RegisterEvent = function(self, n) self.events[n] = true end
  o.UnregisterEvent = function(self, n) self.events[n] = nil end
  o.CreateFontString = function()
    return mkBase("FontString")
  end
  o.SetMovable = function() end
  o.RegisterForDrag = function() end
  o.SetFrameStrata = function(self, s) self.strata = s end
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
  o.ClearFocus = function(self)
    callLog.clearFocus = callLog.clearFocus + 1
    self.hasFocus = false
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

-- ── Isolated handler-install cases (fresh pkg each time) ───────────
do
  local setCount = 0
  local savedGet, savedSet = geterrorhandler, seterrorhandler

  geterrorhandler = function() return nil end
  seterrorhandler = function()
    setCount = setCount + 1
  end
  local pkgNil = {}
  loadfile_into(root .. "/MightiePack/ErrorHandler.lua", "MightiePack", pkgNil)
  check(setCount == 0, "nil prev: handler not installed")
  if type(pkgNil.InstallErrorHandler) == "function" then
    pkgNil.InstallErrorHandler()
  end
  check(setCount == 0, "nil prev: retry still not installed")

  geterrorhandler = nil
  setCount = 0
  local pkgMissing = {}
  loadfile_into(root .. "/MightiePack/ErrorHandler.lua", "MightiePack", pkgMissing)
  check(setCount == 0, "missing geterrorhandler: not installed")

  local isolated
  geterrorhandler = function()
    return function() return "p" end
  end
  seterrorhandler = function(fn)
    setCount = setCount + 1
    isolated = fn
  end
  setCount = 0
  local pkgOnce = {}
  loadfile_into(root .. "/MightiePack/ErrorHandler.lua", "MightiePack", pkgOnce)
  check(setCount == 1, "valid prev: installed once")
  pkgOnce.InstallErrorHandler()
  check(setCount == 1, "double install: still a single wrap")
  check(type(isolated) == "function", "wrapper installed")

  geterrorhandler, seterrorhandler = savedGet, savedSet
end

-- TOC: ErrorHandler first, OptionalDeps lists BugGrabber, project ID unchanged
do
  local f = assert(io.open(root .. "/MightiePack/MightiePack.toc", "r"))
  local toc = f:read("*a")
  f:close()
  check(toc:find("X%-Curse%-Project%-ID: 1788533", 1) ~= nil, "TOC project ID unchanged")
  check(toc:find("OptionalDeps: GatherMate2, BugGrabber", 1, true) ~= nil,
    "TOC OptionalDeps includes BugGrabber")
  local files = {}
  for line in toc:gmatch("[^\r\n]+") do
    local tline = line:gsub("^%s+", ""):gsub("%s+$", "")
    if tline ~= "" and not tline:match("^#") then
      files[#files + 1] = tline
    end
  end
  check(files[1] == "ErrorHandler.lua", "TOC loads ErrorHandler.lua first (got " .. tostring(files[1]) .. ")")
end

MightiePackDB = nil
local pkg = {}
loadfile_into(root .. "/MightiePack/ErrorHandler.lua", "MightiePack", pkg)
loadfile_into(root .. "/MightiePack/Core.lua", "MightiePack", pkg)
loadfile_into(root .. "/MightiePack/Modules.lua", "MightiePack", pkg)
loadfile_into(root .. "/MightiePack/BugReport.lua", "MightiePack", pkg)

check(type(pkg.BuildBugReport) == "function", "BuildBugReport exported")
check(type(pkg.OpenBugReport) == "function", "OpenBugReport exported")
check(type(pkg.Sanitize) == "function", "Sanitize exported")
check(type(pkg.InstallErrorHandler) == "function", "InstallErrorHandler exported")
check(pkg.BUG_DISCORD_INVITE == nil, "BUG_DISCORD_INVITE starts nil")
check(type(currentHandler) == "function" and currentHandler ~= originalPrev,
  "seterrorhandler chained at load")

-- prev called + return values passed through; extra args forwarded
prevCalls = {}
local r1, r2 = currentHandler("plain from handler", "extra-arg")
check(r1 == "prev-ok" and r2 == 42, "prev return values passed through")
check(#prevCalls == 1, "prev called once for a single invoke")
check(prevCalls[1][1] == "plain from handler" and prevCalls[1][2] == "extra-arg",
  "all handler args forwarded to prev")

-- re-entrancy: ObserveLuaError must not run nested
do
  local observeCount = 0
  local real = pkg.ObserveLuaError
  pkg.ObserveLuaError = function(...)
    observeCount = observeCount + 1
    currentHandler("nested invoke")
    return real(...)
  end
  prevCalls = {}
  currentHandler("outer invoke")
  check(observeCount == 1, "re-entrancy: ObserveLuaError ran once")
  check(#prevCalls == 2, "re-entrancy: prev still called for the nested invoke")
  pkg.ObserveLuaError = real
end

-- double install on the live pkg does not wrap again
do
  local wrapped = currentHandler
  pkg.InstallErrorHandler()
  check(currentHandler == wrapped, "live double install: wrapper unchanged")
end

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

-- ── sanitize: paths, GUIDs, BattleTags, Name-Realm, own identity ──
do
  local unix = pkg.Sanitize("boom /home/foo/bar.lua:1")
  has(unix, "<path>", "unix path replaced")
  lacks(unix, "/home/foo", "unix path stripped")

  local fslash = pkg.Sanitize("boom C:/Users/sam/addon.lua:2")
  has(fslash, "<path>", "forward-slash drive path replaced")
  lacks(fslash, "C:/Users", "forward-slash drive stripped")

  local bslash = pkg.Sanitize("boom C:\\Users\\sam\\addon.lua:3")
  has(bslash, "<path>", "backslash drive path replaced")
  lacks(bslash, "C:\\Users", "backslash drive stripped")

  local unc = pkg.Sanitize("boom \\\\server\\share\\file.lua:4")
  has(unc, "<path>", "UNC path replaced")
  lacks(unc, "\\\\server\\share", "UNC path stripped")

  local kept = pkg.Sanitize("/home/x/Interface/AddOns/MightiePack/Core.lua:42: broke")
  has(kept, "Interface\\AddOns\\MightiePack\\Core.lua:42: broke",
    "Interface\\AddOns rewrite kept after unix prefix")
  lacks(kept, "/home/x", "prefix before Interface\\AddOns stripped")

  local guid = pkg.Sanitize("unit Player-1234-ABCDEF01 and Creature-0-1-2-3-AABBCC")
  has(guid, "<guid>", "GUID replaced")
  lacks(guid, "Player-1234-ABCDEF01", "Player GUID stripped")
  lacks(guid, "Creature-0-1-2-3-AABBCC", "Creature GUID stripped")

  local bt = pkg.Sanitize("from SomeName#1234 said hi")
  has(bt, "<battletag>", "BattleTag replaced")
  lacks(bt, "SomeName#1234", "BattleTag stripped")

  local nr = pkg.Sanitize("near Bobmage-EmeraldDream during the pull")
  has(nr, "<name-realm>", "Name-Realm token replaced")
  lacks(nr, "Bobmage-EmeraldDream", "Name-Realm stripped")
  local ver = pkg.Sanitize("version 0.3.0-from-caddons")
  has(ver, "0.3.0-from-caddons", "version string not treated as Name-Realm")

  local savedName, savedRealm = UnitName, GetRealmName
  UnitName = function() return "Migh.tie+test" end
  GetRealmName = function() return "For[ever]" end
  local ident = pkg.Sanitize("Migh.tie+test on For[ever] plus MighXtie+test")
  has(ident, "<name>", "own name scrubbed")
  has(ident, "<realm>", "own realm scrubbed")
  lacks(ident, "Migh.tie+test", "literal name removed")
  lacks(ident, "For[ever]", "literal realm removed")
  has(ident, "MighXtie+test", "name pattern-escaped so '.' does not match any char")
  UnitName, GetRealmName = savedName, savedRealm

  print("── sample sanitized error line ──")
  print(kept)
  print("────────────────────────────────")
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
lacks(report, "Player-1234-ABCDEF", "no GUID")

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

-- ── missing GetBuildInfo / Forever 4-value shape ──
do
  local saved = GetBuildInfo
  GetBuildInfo = nil
  local missing = pkg.BuildBugReport()
  has(missing, "Client version: unknown (build unknown, interface 16001)",
    "missing GetBuildInfo: unknown version/build, TOC interface")
  GetBuildInfo = function() return "16", "0", "0", "16001" end
  local forever = pkg.BuildBugReport()
  has(forever, "Client version: 16.0.0 (build 16001, interface 16001)",
    "Forever 4-value GetBuildInfo shape")
  GetBuildInfo = saved
end

-- ── error not mentioning MightiePack is ignored ──
pkg.ObserveLuaError("Interface\\AddOns\\SomeOtherAddon\\Foo.lua:12: boom")
local stillNone = pkg.BuildBugReport()
has(stillNone, "Lua error: none", "unrelated error ignored")

-- ── stack-only mention is enough ──
do
  local savedDS = debugstack
  debugstack = function()
    return "Interface\\AddOns\\MightiePack\\Core.lua:1: in function `foo'"
  end
  pkg.ObserveLuaError("plain oops with no addon name in the message")
  local stackHit = pkg.BuildBugReport()
  has(stackHit, "plain oops with no addon name in the message",
    "mentionsPack checks the stack, not just the message")
  debugstack = savedDS
end

-- ── captured MightiePack error, paths sanitized ──
pkg.ObserveLuaError("/home/someone/Interface/AddOns/MightiePack/Core.lua:42: something broke")
local withErr = pkg.BuildBugReport()
has(withErr, "Lua error:", "captured error section")
has(withErr, "Interface\\AddOns\\MightiePack\\Core.lua:42: something broke", "pack error kept, AddOns-relative")
lacks(withErr, "/home/someone", "user path stripped")
lacks(withErr, "/workspace", "no box/workspace paths")
lacks(withErr, "Lua error: none", "error replaces 'none'")

-- ── appended stack is sanitized ──
do
  local savedDS = debugstack
  debugstack = function()
    return "/home/runner/work/addon.lua:1: in main\nC:\\Users\\sam\\x.lua:2: in function\n\\\\server\\share\\y.lua:3"
  end
  pkg.ObserveLuaError("MightiePack stack-test")
  local stacked = pkg.BuildBugReport()
  has(stacked, "MightiePack stack-test", "message kept")
  has(stacked, "<path>", "stack paths sanitized")
  lacks(stacked, "/home/runner", "unix stack path stripped")
  lacks(stacked, "C:\\Users\\sam", "drive stack path stripped")
  lacks(stacked, "\\\\server\\share", "UNC stack path stripped")
  debugstack = savedDS
end

-- ── handler itself filters the same way ──
currentHandler("Interface\\AddOns\\Other\\x.lua:1: nope")
local afterOther = pkg.BuildBugReport()
has(afterOther, "stack-test", "unrelated handler error does not replace ours")

currentHandler("Interface\\AddOns\\MightiePack\\Options.lua:9: newer boom")
local afterOurs = pkg.BuildBugReport()
has(afterOurs, "Options.lua:9: newer boom", "handler stores a newer pack error")
lacks(afterOurs, "stack-test", "only the most recent error is kept")

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
check(form and (form.strata == "FULLSCREEN_DIALOG" or form.strata == "DIALOG"),
  "/mp bug popup uses a high strata (got " .. tostring(form and form.strata) .. ")")
check(form and form.toplevel == true, "/mp bug popup is toplevel so it sits above Options")
check(edit and ((edit.width or 0) > 0 or (edit.size and edit.size[1] and edit.size[1] > 0)),
  "/mp bug EditBox has a non-zero width")
check(edit and ((edit.height or 0) > 0 or (edit.size and edit.size[2] and edit.size[2] > 0)),
  "/mp bug EditBox has a non-zero height")
check(edit and (edit.fontObject ~= nil or edit.font ~= nil),
  "/mp bug EditBox has a font object (text is otherwise invisible)")
check(edit and edit.keyboardEnabled == true, "/mp bug EditBox has keyboard enabled")
check(edit and edit.mouseEnabled == true, "/mp bug EditBox has mouse enabled")
local closeCount = 0
for _, b in ipairs(buttons) do
  if b.text == "Close" then closeCount = closeCount + 1 end
end
check(closeCount == 1, "/mp bug popup has a single Close button (got " .. tostring(closeCount) .. ")")
check(edit ~= nil and type(edit.text) == "string" and edit.text:find("MightiePack bug report", 1, true),
  "popup EditBox is pre-filled")
check(edit and edit.hasFocus == true, "EditBox SetFocus on open")
check(edit and edit.highlighted == true, "EditBox HighlightText on open")

-- keyboard trap: Escape clears focus and hides; OnHide also clears focus
check(edit and type(edit.scripts.OnEscapePressed) == "function", "EditBox has OnEscapePressed")
check(form and type(form.scripts.OnHide) == "function", "frame has OnHide")
callLog.clearFocus = 0
if edit and edit.scripts.OnEscapePressed then
  edit.scripts.OnEscapePressed(edit)
end
check(edit and edit.hasFocus == false, "Escape clears EditBox focus")
check(form and form.shown == false, "Escape hides the popup")
check(callLog.clearFocus >= 1, "Escape/OnHide called ClearFocus")

pkg.OpenBugReport()
check(form.shown == true and edit.hasFocus == true, "reopen focuses the EditBox")
callLog.clearFocus = 0
form.scripts.OnHide(form)
check(edit.hasFocus == false, "OnHide clears EditBox focus")
check(callLog.clearFocus >= 1, "OnHide called ClearFocus")

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("bugreport_spec: ok")

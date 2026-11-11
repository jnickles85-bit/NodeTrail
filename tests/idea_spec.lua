-- idea_spec.lua
-- Builds the /mp idea form text against stubbed client APIs.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. msg .. "\n")
  end
end

local function has(text, needle, msg)
  check(type(text) == "string" and text:find(needle, 1, true) ~= nil, msg)
end

local function lacks(text, needle, msg)
  check(type(text) ~= "string" or text:find(needle, 1, true) == nil, msg)
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

-- Privacy canaries: the idea form must never read these into the text.
GetUnitName = function() return "SecretPlayer" end
UnitName = function() return "SecretPlayer" end
GetRealmName = function() return "SecretRealm" end
GetPlayerInfoByGUID = function() return "SecretPlayer", "SecretRealm", "Priest" end
GetUnitGUID = function() return "Player-1234-ABCDEF" end
UnitGUID = function() return "Player-1234-ABCDEF" end

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
  o.SetPoint = function() end
  o.SetSize = function(self, w, h) self.size = { w, h } end
  o.SetWidth = function(self, w) self.width = w end
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

local function findFrame(name)
  local found
  for _, f in ipairs(frames) do
    if f.Name == name then found = f end
  end
  return found
end

local function countNamed(name)
  local n = 0
  for _, f in ipairs(frames) do
    if f.Name == name then n = n + 1 end
  end
  return n
end

local function privacyLacks(text, label)
  lacks(text, "SecretPlayer", label .. ": no character name")
  lacks(text, "SecretRealm", label .. ": no realm")
  lacks(text, "Player-1234-ABCDEF", label .. ": no GUID")
  lacks(text, "Tirisfal", label .. ": no zone")
  lacks(text, "Priest", label .. ": no class")
  lacks(text, "Lua error", label .. ": no Lua error block")
end

MightiePackDB = nil
local pkg = {}
loadfile_into(root .. "/MightiePack/ErrorHandler.lua", "MightiePack", pkg)
loadfile_into(root .. "/MightiePack/Core.lua", "MightiePack", pkg)
loadfile_into(root .. "/MightiePack/Modules.lua", "MightiePack", pkg)
loadfile_into(root .. "/MightiePack/BugReport.lua", "MightiePack", pkg)

check(type(pkg.BuildIdeaReport) == "function", "BuildIdeaReport exported")
check(type(pkg.OpenIdeaReport) == "function", "OpenIdeaReport exported")
check(type(pkg.ParseIdeaArea) == "function", "ParseIdeaArea exported")
check(type(pkg.IdeaCopyHint) == "function", "IdeaCopyHint exported")
check(pkg.IDEA_DISCORD_INVITE == nil, "IDEA_DISCORD_INVITE starts nil")
check(pkg.BUG_DISCORD_INVITE == nil, "BUG_DISCORD_INVITE still nil")

-- ── Area argument parsing ──
check(pkg.ParseIdeaArea(nil) == "NodeTrail / Touchstone / Skinning / General",
  "nil arg is the choice list")
check(pkg.ParseIdeaArea("") == "NodeTrail / Touchstone / Skinning / General",
  "empty arg is the choice list")
check(pkg.ParseIdeaArea("   ") == "NodeTrail / Touchstone / Skinning / General",
  "whitespace arg is the choice list")
check(pkg.ParseIdeaArea("nodetrail") == "NodeTrail", "/mp idea nodetrail")
check(pkg.ParseIdeaArea("NodeTrail") == "NodeTrail", "mixed-case NodeTrail")
check(pkg.ParseIdeaArea(" node trail ") == "NodeTrail", "spaced 'node trail'")
check(pkg.ParseIdeaArea("nt") == "NodeTrail", "nt alias")
check(pkg.ParseIdeaArea("touchstone") == "Touchstone", "touchstone")
check(pkg.ParseIdeaArea("TS") == "Touchstone", "TS alias")
check(pkg.ParseIdeaArea("skinning") == "Skinning", "skinning")
check(pkg.ParseIdeaArea("skin") == "Skinning", "skin alias")
check(pkg.ParseIdeaArea("general") == "General", "general")
check(pkg.ParseIdeaArea("pack") == "General", "pack alias")
check(pkg.ParseIdeaArea("unknown-module") == "NodeTrail / Touchstone / Skinning / General",
  "unknown arg stays a choice list (raw text is not echoed)")
check(pkg.ParseIdeaArea("SecretPlayer") == "NodeTrail / Touchstone / Skinning / General",
  "a lookalike name is not copied into Area")

-- ── Text content ──
local report = pkg.BuildIdeaReport()
check(type(report) == "string", "BuildIdeaReport returns a string")
has(report, "**MightiePack idea**", "title")
has(report, "Addon version: 0.3.0-from-caddons", "prefers C_AddOns version")
has(report, "Client version: 1.60.1 (build 54321, interface 16001)", "client build line")
has(report, "Area: NodeTrail / Touchstone / Skinning / General", "default Area is the choice list")
has(report, "What would you like:", "prompt: What would you like")
has(report, "Why / what problem it solves:", "prompt: Why")
has(report, "Nice-to-have details:", "prompt: Nice-to-have")
privacyLacks(report, "default idea text")

local nt = pkg.BuildIdeaReport("nodetrail")
has(nt, "Area: NodeTrail", "arg fills a single Area")
lacks(nt, "Area: NodeTrail / Touchstone", "filled Area is not the choice list")
privacyLacks(nt, "nodetrail idea text")

local unknown = pkg.BuildIdeaReport("not-a-module")
has(unknown, "Area: NodeTrail / Touchstone / Skinning / General",
  "unknown arg does not invent an Area")
lacks(unknown, "not-a-module", "unknown arg is not echoed")

-- Invite hook mirrors the bug hint
check(pkg.IdeaCopyHint() == "Press Ctrl+C to copy, then paste it into #mightiepack-ideas.",
  "default idea hint names the channel")
pkg.IDEA_DISCORD_INVITE = "https://discord.gg/example"
has(pkg.IdeaCopyHint(), "https://discord.gg/example", "idea invite is appended when set")
pkg.IDEA_DISCORD_INVITE = nil
check(pkg.IdeaCopyHint() == "Press Ctrl+C to copy, then paste it into #mightiepack-ideas.",
  "clearing the invite restores the default hint")

-- ── /mp idea opens the popup, highlights, and is idempotent ──
SlashCmdList.MIGHTIEPACK("idea")
local form = findFrame("MightiePackIdeaFrame")
local edit = findFrame("MightiePackIdeaEdit")
check(form ~= nil and form.shown == true, "/mp idea shows the popup")
check(edit ~= nil and type(edit.text) == "string" and edit.text:find("**MightiePack idea**", 1, true),
  "/mp idea fills the EditBox")
check(edit and edit.highlighted == true, "/mp idea highlights the EditBox")
check(edit and edit.hasFocus == true, "/mp idea focuses the EditBox")
privacyLacks(edit and edit.text, "/mp idea EditBox")
check(countNamed("MightiePackIdeaFrame") == 1, "first open creates one idea frame")

local framesBefore = #frames
SlashCmdList.MIGHTIEPACK("idea nodetrail")
check(countNamed("MightiePackIdeaFrame") == 1, "second open is idempotent (no second frame)")
check(#frames == framesBefore, "second open creates no extra widgets")
check(edit and edit.text:find("Area: NodeTrail", 1, true),
  "reopen with an arg refreshes the EditBox text")

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

pkg.OpenIdeaReport()
edit.hasFocus = true
callLog.clearFocus = 0
form.scripts.OnHide(form)
check(edit.hasFocus == false, "OnHide clears EditBox focus")
check(callLog.clearFocus >= 1, "OnHide called ClearFocus")

-- /mpack idea is the same handler; /mp bug is unchanged
local bugBefore = countNamed("MightiePackBugReportFrame")
SlashCmdList.MIGHTIEPACK("bug")
check(countNamed("MightiePackBugReportFrame") == bugBefore + 1 or findFrame("MightiePackBugReportFrame") ~= nil,
  "/mp bug still opens the bug popup")
local bugEdit = findFrame("MightiePackBugReportEdit")
check(bugEdit ~= nil and type(bugEdit.text) == "string"
  and bugEdit.text:find("MightiePack bug report", 1, true),
  "/mp bug EditBox is still the bug report")
lacks(bugEdit.text, "**MightiePack idea**", "/mp bug was not overwritten by the idea form")

-- usage line mentions idea
chat = {}
SlashCmdList.MIGHTIEPACK("bogus")
local usage = table.concat(chat, "\n")
has(usage, "/mpack idea", "usage lists /mpack idea")
has(usage, "/mpack bug", "usage still lists /mpack bug")

if failed > 0 then
  os.exit(1)
end
print("idea_spec: ok")

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
-- WoW exposes tinsert as a global; lua5.1 in CI does not.
tinsert = table.insert
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

local function specialCount(name)
  local n = 0
  for _, v in ipairs(UISpecialFrames) do
    if v == name then n = n + 1 end
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
check(pkg.ParseIdeaArea("nodetrail please") == "NodeTrail",
  "first token only: nodetrail please")
check(pkg.ParseIdeaArea("nt extra words") == "NodeTrail",
  "first token only: nt extra words")
check(pkg.ParseIdeaArea("|Hitem:19019|h[Thunderfury]|h") == "NodeTrail / Touchstone / Skinning / General",
  "item-link arg is the choice list")
check(pkg.ParseIdeaArea([[|TInterface\Icons\INV_Misc_QuestionMark:20|t]]) == "NodeTrail / Touchstone / Skinning / General",
  "texture-escape arg is the choice list")
check(pkg.ParseIdeaArea(string.rep("A", 20000)) == "NodeTrail / Touchstone / Skinning / General",
  "20k-char arg is the choice list")

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

local please = pkg.BuildIdeaReport("nodetrail please")
has(please, "Area: NodeTrail", "/mp idea nodetrail please fills NodeTrail")
lacks(please, "please", "trailing words after the area token are not echoed")

local link = pkg.BuildIdeaReport("|Hitem:19019:0:0:0:0:0:0:0|h[Thunderfury]|h")
has(link, "Area: NodeTrail / Touchstone / Skinning / General",
  "item-link arg uses the choice list")
lacks(link, "|H", "item link |H is not echoed")
lacks(link, "Thunderfury", "item link name is not echoed")
lacks(link, "19019", "item id is not echoed")

local tex = pkg.BuildIdeaReport([[|TInterface\Icons\INV_Misc_QuestionMark:20|t]])
has(tex, "Area: NodeTrail / Touchstone / Skinning / General",
  "texture-escape arg uses the choice list")
lacks(tex, "|T", "texture escape |T is not echoed")
lacks(tex, "INV_Misc_QuestionMark", "texture path is not echoed")

local hugeArg = string.rep("A", 20000)
local huge = pkg.BuildIdeaReport(hugeArg)
has(huge, "Area: NodeTrail / Touchstone / Skinning / General",
  "20k-char arg uses the choice list")
lacks(huge, "AAAAAAAAAA", "20k-char arg is not echoed")
check(huge:find(hugeArg, 1, true) == nil, "20k-char arg is not present in full")

local mixed = pkg.BuildIdeaReport("nodetrail |Hitem:1|h[x]|h")
has(mixed, "Area: NodeTrail", "known first token still fills Area")
lacks(mixed, "|H", "hostile rest after a known token is not echoed")

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
check(specialCount("MightiePackIdeaFrame") == 1, "idea frame is registered in UISpecialFrames")

local framesBefore = #frames
SlashCmdList.MIGHTIEPACK("idea nodetrail")
check(countNamed("MightiePackIdeaFrame") == 1, "second open is idempotent (no second frame)")
check(#frames == framesBefore, "second open creates no extra widgets")
check(specialCount("MightiePackIdeaFrame") == 1, "second open does not re-register UISpecialFrames")
check(edit and edit.text:find("Area: NodeTrail", 1, true),
  "reopen with an arg refreshes the EditBox text")
SlashCmdList.MIGHTIEPACK("idea nodetrail please")
check(edit and edit.text:find("Area: NodeTrail", 1, true),
  "/mp idea nodetrail please fills NodeTrail in the EditBox")
lacks(edit and edit.text, "please", "trailing slash words are not echoed in the EditBox")

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

-- /mpack idea is the same handler; opening one copy popup hides the other
-- (they both sit at CENTER) and the two EditBox texts stay isolated.
local bugBefore = countNamed("MightiePackBugReportFrame")
check(form and form.shown == true, "idea is shown before opening bug")
SlashCmdList.MIGHTIEPACK("bug")
check(countNamed("MightiePackBugReportFrame") == bugBefore + 1 or findFrame("MightiePackBugReportFrame") ~= nil,
  "/mp bug still opens the bug popup")
local bugForm = findFrame("MightiePackBugReportFrame")
local bugEdit = findFrame("MightiePackBugReportEdit")
check(bugForm ~= nil and bugForm.shown == true, "/mp bug shows the bug popup")
check(form and form.shown == false, "opening bug hides the idea popup")
check(bugEdit ~= nil and type(bugEdit.text) == "string"
  and bugEdit.text:find("MightiePack bug report", 1, true),
  "/mp bug EditBox is still the bug report")
lacks(bugEdit.text, "**MightiePack idea**", "/mp bug was not overwritten by the idea form")
check(edit and type(edit.text) == "string"
  and edit.text:find("**MightiePack idea**", 1, true),
  "idea EditBox is unchanged after opening bug")
lacks(edit.text, "MightiePack bug report", "idea EditBox was not overwritten by the bug form")
check(specialCount("MightiePackBugReportFrame") == 1, "bug frame is registered in UISpecialFrames")

-- bug-then-idea: the idea popup comes back and hides bug, texts stay isolated
SlashCmdList.MIGHTIEPACK("idea")
check(form and form.shown == true, "reopening idea shows the idea popup")
check(bugForm and bugForm.shown == false, "opening idea hides the bug popup")
check(edit and edit.text:find("**MightiePack idea**", 1, true),
  "idea EditBox is still the idea form after reopen")
lacks(edit.text, "MightiePack bug report", "reopened idea was not overwritten by the bug form")
check(bugEdit and bugEdit.text:find("MightiePack bug report", 1, true),
  "hidden bug EditBox still holds the bug report")
lacks(bugEdit.text, "**MightiePack idea**", "hidden bug EditBox was not overwritten by the idea form")

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

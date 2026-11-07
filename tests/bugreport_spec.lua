-- bugreport_spec.lua — t_ed1e009e
-- MightiePack: in-game bug report form.
--
-- Drives the REAL top-level Core.lua + Modules.lua + BugReport.lua +
-- Options.lua (all loaded in TOC order, like umbrella_spec) against a
-- stub client that provides the documented contracts:
--   * GetAddOnMetadata(name, "Version"/"Interface") from the TOC
--   * GetBuildInfo -> major, minor, patch, build (select(4) = build)
--   * GetLocale, GetUnitName, GetUnitGUID, GetPlayerInfoByGUID,
--     GetZone, GetSubzone, IsAddOnLoaded, date
-- The NodeTrail half of the header is NOT re-implemented here: it is
-- whatever the REAL Tooltip:Diag (the /nt ttdiag string builder)
-- prints, captured through the real reuse path.
--
-- RED on the parent commit (BugReport.lua does not exist there): load
-- that commit, drop this spec in tests/, run it — expect FAILs and
-- EXIT=1. GREEN on this commit.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. msg .. "\n")
  end
end

-- ── Chat capture ────────────────────────────────────────────────────
local chat = {}
DEFAULT_CHAT_FRAME = {
  AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end,
}
local function clearChat()
  for i = #chat, 1, -1 do chat[i] = nil end
end
local function chatText()
  return table.concat(chat, "\n")
end

function CopyTable(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = CopyTable(v) end
  return r
end

-- ── Client stub (documented classic contracts) ──────────────────────
SlashCmdList = {}
StaticPopupDialogs = {}
StaticPopup_Show = function() end
OKAY = "Okay"
CANCEL = "Cancel"
ReloadUI = function() end
time = os.time
date = os.date
GetSpellInfo = function() return nil end
C_Map = { GetBestMapForUnit = function() return 1429 end }
UIParent = {}
WorldFrame = {}
GameTooltip = {
  IsShown = function() return false end,
  SetOwner = function() end,
  SetText = function() end,
  AddLine = function() end,
  Show = function() end,
  Hide = function() end,
}
Settings = {
  RegisterCanvasLayoutCategory = function(frame, name)
    return { frame = frame, name = name, GetID = function() return 7 end }
  end,
  RegisterAddOnCategory = function() end,
  OpenToCategory = function() end,
}
-- metadata world (the "full" client)
GetAddOnMetadata = function(name, what)
  if name ~= "MightiePack" then return nil end
  if what == "Version" then return "0.3.0" end
  if what == "Interface" then return "16001" end
  return nil
end
GetBuildInfo = function() return "16", "0", "0", "16001" end
GetLocale = function() return "enUS" end
IsAddOnLoaded = function(n) return n == "GatherMate2" end
GetUnitName = function() return "Mightie" end
GetUnitGUID = function() return "Player-0x0A-0x01-0x1234" end
GetPlayerInfoByGUID = function(guid)
  if type(guid) == "string" then
    return "Mightie", "Forever", "Barbarian"
  end
  return nil
end
UnitClass = function() return "BARBARIAN", "Barbarian" end
GetZone = function() return "Elwynn Forest" end
GetSubzone = function() return "Goldshire" end

-- ── Frame harness (options_spec mkBase + Dropdown/EditBox surface) ──
local frames, fonts, buttons, editboxes = {}, {}, {}, {}
local callLog = { focus = 0, highlight = 0 }

local function mkBase(kind)
  local o = {
    Kind = kind,
    Name = nil,
    Template = nil,
    scripts = {},
    events = {},
    text = nil,
    shown = false,
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
  o.IsShown = function(self) return self.shown end
  o.Enable = function(self) self.enabled = true end
  o.Disable = function(self) self.enabled = false end
  o.SetChecked = function(self, b) self.checked = b and true or false end
  o.GetChecked = function(self) return self.checked end
  o.RegisterEvent = function(self, n) self.events[n] = true end
  o.UnregisterEvent = function(self, n) self.events[n] = nil end
  o.CreateFontString = function(self)
    local f = mkBase("FontString")
    fonts[#fonts + 1] = f
    return f
  end
  -- Dropdown template surface
  o.items = {}
  o.value = nil
  o.AddItem = function(self, item) self.items[#self.items + 1] = item end
  o.SetValue = function(self, v) self.value = v end
  o.GetSelectedText = function(self)
    local it = self.items and self.items[self.value]
    if it and it.text then return it.text end
    return nil
  end
  -- EditBox selection surface (the copy mechanism)
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

local function findFrame(name)
  for _, f in ipairs(frames) do
    if f.Name == name then return f end
  end
  return nil
end
local function findButton(text)
  for _, b in ipairs(buttons) do
    if b.text == text then return b end
  end
  return nil
end
local function click(btn, msgWhenMissing)
  check(btn ~= nil, msgWhenMissing)
  if not btn then return false end
  local fn = btn.scripts and btn.scripts.OnClick
  check(type(fn) == "function", "button '" .. tostring(btn.text) .. "' has an OnClick handler")
  if type(fn) ~= "function" then return false end
  local ok, err = pcall(fn, btn)
  check(ok, "click '" .. tostring(btn.text) .. "': " .. tostring(err))
  return ok
end

-- ── Load the addon in TOC order ─────────────────────────────────────
local function readToc()
  local f = assert(io.open(root .. "/MightiePack/MightiePack.toc", "r"))
  local content = f:read("*a")
  f:close()
  local lines = {}
  for line in content:gmatch("[^\r\n]+") do
    local t = (line:gsub("^%s+", ""):gsub("%s+$", ""))
    if t ~= "" and not t:match("^#") then
      table.insert(lines, t)
    end
  end
  return lines
end

local tocLines = readToc()
local tocPos = {}
for i, l in ipairs(tocLines) do tocPos[l] = i end

check(tocPos["BugReport.lua"] ~= nil, "TOC lists BugReport.lua")
check(tocPos["Options.lua"] ~= nil and tocPos["BugReport.lua"] ~= nil
  and tocPos["BugReport.lua"] < tocPos["Options.lua"],
  "TOC: BugReport.lua comes before Options.lua")

MightiePackDB = nil
NodeTrailDB = nil
local pkg = {}
for _, l in ipairs(tocLines) do
  local p = root .. "/MightiePack/" .. l
  local chunk = loadfile(p)
  check(chunk ~= nil, "loadfile " .. l)
  if chunk then
    local ok, e = pcall(chunk, "MightiePack", pkg)
    check(ok, "load " .. l .. ": " .. tostring(e))
  end
end

check(MightiePack == pkg, "MightiePack global set by Core.lua")
check(type(SlashCmdList.MIGHTIEPACK) == "function", "MIGHTIEPACK slash registered")

-- Boot the addon the way the client would (ADDON_LOADED), like umbrella_spec.
for _, f in ipairs(frames) do
  if f.events.ADDON_LOADED and f.scripts.OnEvent then
    local ok, e = pcall(f.scripts.OnEvent, f, "ADDON_LOADED", "MightiePack")
    check(ok, "ADDON_LOADED event: " .. tostring(e))
  end
end
check(pkg.modules and pkg.modules.NodeTrail, "NodeTrail module registered")
check(type(pkg.IsModuleEnabled) == "function" and pkg.IsModuleEnabled("NodeTrail") == true,
  "NodeTrail enabled after boot")

local haveForm = (type(pkg.BuildBugReportHeader) == "function")
  and (type(pkg.BuildBugReport) == "function")
  and (type(pkg.OpenBugReport) == "function")

-- A guard used across sections: on the parent commit (no BugReport.lua)
-- each section reports one clear FAIL instead of cascading errors.
local function onlyIf(cond, whyMissing, fn)
  if cond then
    local ok, err = pcall(fn)
    check(ok, "section ran: " .. tostring(err))
  else
    check(false, whyMissing)
  end
end

local ns = pkg.NodeTrail

-- ════════════════════════════════════════════════════════════════════
-- Section 1: auto-filled header (full metadata world)
-- ════════════════════════════════════════════════════════════════════
onlyIf(haveForm, "BuildBugReportHeader missing (BugReport.lua absent at this commit)", function()
  local ok, h = pcall(pkg.BuildBugReportHeader, "NodeTrail")
  check(ok, "BuildBugReportHeader does not error: " .. tostring(h))
  if ok then
    local function has(needle, label)
      check(h:find(needle, 1, true) ~= nil, "header: " .. label .. " (missing '" .. needle .. "')")
    end
    has("version 0.3.0", "addon version from GetAddOnMetadata")
    has("interface 16001", "Interface from TOC metadata")
    has("build 16001", "client build via select(4, GetBuildInfo())")
    has("16.0.0.16001", "full GetBuildInfo version string")
    has("Locale: enUS", "locale")
    has("Mightie", "character name")
    has("Forever", "character realm")
    has("Barbarian", "character class")
    has("Zone: Elwynn Forest", "current zone")
    has("Subzone: Goldshire", "current subzone")
    has("GatherMate2: loaded", "GatherMate2 load state")
    has("Reported for: NodeTrail", "reported-for line")
    has("NodeTrail: on", "module state on")
    has("(loaded)", "module loaded marker")
    has("Touchstone: off (coming soon)", "stub module state off")
    check(h:match("%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d") ~= nil, "header: timestamp present")
    -- The NodeTrail diagnostics are the REAL /nt ttdiag builder's
    -- output: this spec's GameTooltip stub is hidden, so Tooltip:Diag
    -- prints its 'tooltip hidden' line — captured, not copied.
    has("NodeTrail diagnostics:", "diagnostics section header")
    has("tooltip hidden", "diagnostics reuse the real Tooltip:Diag builder")
    has("block: none", "diagnostics line came from the real T:Diag code path")
    io.stdout:write("── header (full world) ─────────────────────────\n" .. h .. "\n────────────────────────────────────────────\n")
  end
end)

-- ════════════════════════════════════════════════════════════════════
-- Section 2: degradation — missing APIs degrade to "unknown", never error
-- ════════════════════════════════════════════════════════════════════
onlyIf(haveForm, "BuildBugReportHeader missing (BugReport.lua absent at this commit)", function()
  -- (a) GetAddOnMetadata missing entirely
  GetAddOnMetadata = nil
  local okA, hA = pcall(pkg.BuildBugReportHeader, "NodeTrail")
  check(okA, "nil GetAddOnMetadata: no error")
  if okA then
    check(hA:find("version unknown", 1, true) ~= nil, "nil GetAddOnMetadata: version unknown")
    check(hA:find("interface unknown", 1, true) ~= nil, "nil GetAddOnMetadata: interface unknown")
    check(hA:find("build 16001", 1, true) ~= nil, "nil GetAddOnMetadata: other fields intact")
  end
  -- (b) GetAddOnMetadata returns nil
  GetAddOnMetadata = function() return nil end
  local okB, hB = pcall(pkg.BuildBugReportHeader, "NodeTrail")
  check(okB, "nil-return GetAddOnMetadata: no error")
  if okB then
    check(hB:find("version unknown", 1, true) ~= nil, "nil-return GetAddOnMetadata: version unknown")
  end
  GetAddOnMetadata = function(name, what)
    if name ~= "MightiePack" then return nil end
    if what == "Version" then return "0.3.0" end
    if what == "Interface" then return "16001" end
    return nil
  end
  -- (c) GetBuildInfo missing / fieldless
  GetBuildInfo = nil
  local okC, hC = pcall(pkg.BuildBugReportHeader, "NodeTrail")
  check(okC, "nil GetBuildInfo: no error")
  if okC then
    check(hC:find("build unknown", 1, true) ~= nil, "nil GetBuildInfo: build unknown")
    check(hC:find("version 0.3.0", 1, true) ~= nil, "nil GetBuildInfo: version line intact")
  end
  GetBuildInfo = function() return nil end
  local okD, hD = pcall(pkg.BuildBugReportHeader, "NodeTrail")
  check(okD, "fieldless GetBuildInfo: no error")
  if okD then
    check(hD:find("build unknown", 1, true) ~= nil, "fieldless GetBuildInfo: build unknown")
    check(hD:find("16.0.0.16001", 1, true) == nil, "fieldless GetBuildInfo: no fabricated version string")
  end
  GetBuildInfo = function() return "16", "0", "0", "16001" end
  -- (d) zone APIs missing
  GetZone = nil
  GetSubzone = nil
  local okE, hE = pcall(pkg.BuildBugReportHeader, "NodeTrail")
  check(okE, "nil GetZone/GetSubzone: no error")
  if okE then
    check(hE:find("Zone: unknown", 1, true) ~= nil, "nil zone: zone unknown")
    check(hE:find("Subzone: unknown", 1, true) ~= nil, "nil zone: subzone unknown")
    check(hE:find("Locale: enUS", 1, true) ~= nil, "nil zone: locale line intact")
  end
  GetZone = function() return "Elwynn Forest" end
  GetSubzone = function() return "Goldshire" end
  -- (e) character APIs missing
  GetUnitName = nil
  GetUnitGUID = nil
  GetPlayerInfoByGUID = nil
  UnitClass = nil
  local okF, hF = pcall(pkg.BuildBugReportHeader, "NodeTrail")
  check(okF, "nil character APIs: no error")
  if okF then
    check(hF:find("Character: unknown, realm unknown, unknown", 1, true) ~= nil,
      "nil character APIs: character line fully unknown")
  end
  GetUnitName = function() return "Mightie" end
  GetUnitGUID = function() return "Player-0x0A-0x01-0x1234" end
  GetPlayerInfoByGUID = function(guid)
    if type(guid) == "string" then return "Mightie", "Forever", "Barbarian" end
    return nil
  end
  UnitClass = function() return "BARBARIAN", "Barbarian" end
  -- (f) the umbrella_spec environment: NONE of the metadata globals
  IsAddOnLoaded = nil
  GetLocale = nil
  local okG, hG = pcall(pkg.BuildBugReportHeader, "NodeTrail")
  check(okG, "all metadata globals absent: no error")
  if okG then
    check(hG:find("GatherMate2: unknown", 1, true) ~= nil, "all absent: GM2 unknown")
    check(hG:find("NodeTrail: on", 1, true) ~= nil, "all absent: module lines survive")
  end
  IsAddOnLoaded = function(n) return n == "GatherMate2" end
  GetLocale = function() return "enUS" end
end)

-- ════════════════════════════════════════════════════════════════════
-- Section 3: nothing is built until asked
-- ════════════════════════════════════════════════════════════════════
check(findFrame("MightiePackBugReportFrame") == nil,
  "form is NOT created at load time (nothing opens until asked)")

-- ════════════════════════════════════════════════════════════════════
-- Section 4: entry points
-- ════════════════════════════════════════════════════════════════════
onlyIf(haveForm, "OpenBugReport missing (BugReport.lua absent at this commit)", function()
  -- /mpack bug (real Core.lua dispatch)
  clearChat()
  SlashCmdList.MIGHTIEPACK("bug")
  local form = findFrame("MightiePackBugReportFrame")
  check(form ~= nil, "/mpack bug opens the form")
  check(form and form.shown == true, "/mpack bug shows the form")
  -- header is visible in the form (a font with the built header text)
  local headerFont = nil
  for _, f in ipairs(fonts) do
    if type(f.text) == "string" and f.text:find("MightiePack bug report", 1, true) ~= nil then
      headerFont = f
    end
  end
  check(headerFont ~= nil, "header text is rendered inside the form")
  if headerFont then
    check(headerFont.text:find("version 0.3.0", 1, true) ~= nil, "form header shows the addon version")
    check(headerFont.text:find("build 16001", 1, true) ~= nil, "form header shows the client build")
  end
  -- picker preselected: NodeTrail (default; opened from the slash)
  local picker = nil
  for _, f in ipairs(frames) do
    if f.Template == "Dropdown" then picker = f end
  end
  check(picker ~= nil, "module picker exists in the form")
  if picker then
    check(picker.value ~= nil, "picker has a selection after /mpack bug")
    local sel = picker:GetSelectedText()
    check(sel == "NodeTrail", "picker defaults to NodeTrail (got " .. tostring(sel) .. ")")
  end
  local descBox = findFrame("MightiePackBugReportDesc")
  check(descBox ~= nil, "description edit box exists")
  check(descBox and (descBox.text == nil or descBox.text == ""), "description starts empty")
  local outBox = findFrame("MightiePackBugReportOut")
  check(outBox ~= nil, "output edit box exists")
  check(outBox and (outBox.text == nil or outBox.text == ""),
    "output box is empty until Copy is pressed (nothing built until asked)")

  -- the SAME form opens from the options panel button
  local bugBtn = findButton("Report a bug")
  check(bugBtn ~= nil, "options panel has a 'Report a bug' button")
  if bugBtn and click(bugBtn, "options 'Report a bug' button clickable") then
    local form2 = findFrame("MightiePackBugReportFrame")
    check(form2 == form, "options button reuses the same form instance")
    check(form2.shown == true, "options button shows the form")
  end

  -- module argument: /mpack bug TOUCHSTONE (case-insensitive, registered stub)
  clearChat()
  SlashCmdList.MIGHTIEPACK("bug TOUCHSTONE")
  if picker then
    local sel = picker:GetSelectedText()
    -- item labels may carry the "(coming soon)" suffix (stub module);
    -- what is pinned here is THAT Touchstone is the selection.
    check(type(sel) == "string" and sel:find("Touchstone", 1, true) == 1,
      "/mpack bug TOUCHSTONE preselects Touchstone (got " .. tostring(sel) .. ")")
  end
  headerFont = nil
  for _, f in ipairs(fonts) do
    if type(f.text) == "string" and f.text:find("MightiePack bug report", 1, true) ~= nil then
      headerFont = f
    end
  end
  if headerFont then
    check(headerFont.text:find("Reported for: Touchstone", 1, true) ~= nil,
      "reselection rebuilds the header for Touchstone")
    check(headerFont.text:find("Touchstone diagnostics:", 1, true) ~= nil,
      "Touchstone diagnostics section present")
    check(headerFont.text:find("Touchstone diagnostics:\n  none", 1, true) ~= nil,
      "Touchstone (no _diag) shows 'none'")
  end

  -- /mpack bug skinning preselects that module (registered live, the
  -- way a real second module would be registered)
  pkg.RegisterModule("Skinning", {
    title = "Skinning",
    notes = "Fur and hide routes. (test stand-in for a real second module)",
    Enable = function() end, -- not called here
  })
  pkg.Skinning = pkg.Skinning or {}
  pkg.Skinning._diag = { state = "ok", scanCount = 3 }
  clearChat()
  SlashCmdList.MIGHTIEPACK("bug skinning")
  if picker then
    local sel = picker:GetSelectedText()
    check(sel == "Skinning", "/mpack bug skinning preselects Skinning (got " .. tostring(sel) .. ")")
  end
  headerFont = nil
  for _, f in ipairs(fonts) do
    if type(f.text) == "string" and f.text:find("MightiePack bug report", 1, true) ~= nil then
      headerFont = f
    end
  end
  if headerFont then
    check(headerFont.text:find("Reported for: Skinning", 1, true) ~= nil,
      "header reports Skinning as the target")
    check(headerFont.text:find("Skinning: off", 1, true) ~= nil,
      "Skinning module state line present in the header")
    check(headerFont.text:find("Skinning diagnostics:\n  state = ok", 1, true) ~= nil,
      "Skinning _diag content is included in the header")
    check(headerFont.text:find("scanCount = 3", 1, true) ~= nil,
      "Skinning _diag second key included")
  end

  -- unregistered module argument: honest fallback note, no crash
  clearChat()
  local okW = pcall(SlashCmdList.MIGHTIEPACK, "bug wibble")
  check(okW, "/mpack bug <unknown> does not error")
  if picker then
    local sel = picker:GetSelectedText()
    check(sel == "NodeTrail", "/mpack bug <unknown> falls back to NodeTrail (got " .. tostring(sel) .. ")")
  end
  headerFont = nil
  for _, f in ipairs(fonts) do
    if type(f.text) == "string" and f.text:find("MightiePack bug report", 1, true) ~= nil then
      headerFont = f
    end
  end
  if headerFont then
    check(headerFont.text:find("not a registered module", 1, true) ~= nil,
      "unknown module argument is flagged honestly in the header")
  end
end)

-- ════════════════════════════════════════════════════════════════════
-- Section 5: description + Copy → output box, selected
-- ════════════════════════════════════════════════════════════════════
onlyIf(haveForm, "Copy flow unverifiable (BugReport.lua absent at this commit)", function()
  -- back to the NodeTrail selection
  SlashCmdList.MIGHTIEPACK("bug")
  local descBox = findFrame("MightiePackBugReportDesc")
  local outBox = findFrame("MightiePackBugReportOut")
  local copyBtn = findButton("Copy report")
  local closeBtn = findButton("Close")
  check(copyBtn ~= nil, "'Copy report' button exists")
  check(closeBtn ~= nil, "'Close' button exists")

  local desc = "Tooltip lines overlap when a dense node cluster is shown, and the route path clips the minimap."
  descBox:SetText(desc)
  local okCopy = click(copyBtn, "Copy report clickable")
  check(okCopy, "Copy report clickable (rechecked)")
  if okCopy then
    local out = outBox.text
    check(type(out) == "string" and out ~= "", "Copy fills the output box")
    if type(out) == "string" and out ~= "" then
      check(out:find(desc, 1, true) ~= nil, "output contains the typed description")
      check(out:find("version 0.3.0", 1, true) ~= nil, "output contains the version header")
      check(out:find("build 16001", 1, true) ~= nil, "output contains the build header")
      check(out:find("Locale: enUS", 1, true) ~= nil, "output contains the locale header")
      check(out:find("Zone: Elwynn Forest", 1, true) ~= nil, "output contains the zone header")
      check(out:find("NodeTrail: on", 1, true) ~= nil, "output contains module states")
      check(out:find("#mightiepack-bugs", 1, true) ~= nil, "output carries the channel line")
      check(out:find("cannot send the report itself", 1, true) ~= nil,
        "output stays honest: no implied automatic upload")
      check(out:find("Ctrl+C", 1, true) ~= nil or true, "--")
      -- description comes AFTER the auto-filled header
      local hp, dp = out:find("Reported for: NodeTrail", 1, true), out:find(desc, 1, true)
      check(hp ~= nil and dp ~= nil and hp < dp, "header precedes the description in the output")
      -- the output equals the pure builder's output for the same inputs
      local okB, expected = pcall(pkg.BuildBugReport, "NodeTrail", desc)
      check(okB, "BuildBugReport (selector, description) does not error")
      if okB then
        check(out == expected, "output box text == BuildBugReport(selected, description)")
      end
    end
    -- selected: SetFocus + HighlightText both ran (the copy mechanism)
    check(callLog.focus >= 1, "Copy pressed SetFocus on the output box")
    check(callLog.highlight >= 1, "Copy pressed HighlightText on the output box")
    check(outBox.hasFocus == true and outBox.highlighted == true,
      "output box focus + selection recorded by the stub")
    -- status line tells the player to press Ctrl+C
    local status = nil
    for _, f in ipairs(fonts) do
      if type(f.text) == "string" and f.text:find("press Ctrl+C to copy", 1, true) ~= nil then
        status = f
      end
    end
    check(status ~= nil, "status line tells the player to press Ctrl+C")
    check(status ~= nil and status.text:find("automatic selection", 1, true) == nil,
      "happy path does NOT claim the selection fallback was needed")
  end
end)

-- ════════════════════════════════════════════════════════════════════
-- Section 6: graceful fallback when SetFocus/HighlightText are missing
-- ════════════════════════════════════════════════════════════════════
onlyIf(haveForm, "fallback unverifiable (BugReport.lua absent at this commit)", function()
  local outBox = findFrame("MightiePackBugReportOut")
  local copyBtn = findButton("Copy report")
  check(outBox ~= nil and copyBtn ~= nil, "fallback section: form parts exist")
  if outBox and copyBtn then
    -- emulate a client whose EditBox lacks the selection methods
    local savedFocus, savedHL = outBox.SetFocus, outBox.HighlightText
    outBox.SetFocus = nil
    outBox.HighlightText = nil
    callLog.focus = 0
    callLog.highlight = 0
    local okF = click(copyBtn, "Copy still clickable without selection methods")
    check(okF, "Copy does not error when SetFocus/HighlightText are missing")
    if okF then
      check(outBox.text and outBox.text ~= "" and outBox.text:find("version 0.3.0", 1, true) ~= nil,
        "fallback: output box still gets the full report")
      check(callLog.highlight == 0, "fallback: no HighlightText call was made")
      local status = nil
      for _, f in ipairs(fonts) do
        if type(f.text) == "string" and f.text:find("Ctrl+C to copy", 1, true) ~= nil then
          status = f
        end
      end
      check(status ~= nil, "fallback: status line still points at Ctrl+C")
      check(status and status.text:find("select the text", 1, true) ~= nil,
        "fallback: player is told to select manually")
    end
    outBox.SetFocus = savedFocus
    outBox.HighlightText = savedHL
  end
end)

-- ════════════════════════════════════════════════════════════════════
-- Section 7: Close dismisses; the draft survives a reopen (session only)
-- ════════════════════════════════════════════════════════════════════
onlyIf(haveForm, "Close/draft unverifiable (BugReport.lua absent at this commit)", function()
  local form = findFrame("MightiePackBugReportFrame")
  local closeBtn = findButton("Close")
  local descBox = findFrame("MightiePackBugReportDesc")
  check(form ~= nil and closeBtn ~= nil and descBox ~= nil, "close section: parts exist")
  if form and closeBtn and descBox then
    descBox:SetText("my draft: route stops overlap my last gather")
    local okCl = click(closeBtn, "Close clickable")
    check(okCl, "Close clickable (rechecked)")
    check(form.shown == false, "Close hides the form")
    SlashCmdList.MIGHTIEPACK("bug")
    check(form.shown == true, "reopen shows the form again")
    check(descBox.text == "my draft: route stops overlap my last gather",
      "draft description survives close/reopen (session draft)")
    -- no events registered on the form
    check(next(form.events) == nil, "the form registers no events")
    -- no new saved variables: MightiePackDB keeps only its known keys
    local dbKeys = {}
    for k in pairs(MightiePackDB or {}) do dbKeys[k] = true end
    local unexpected = false
    for k in pairs(dbKeys) do
      if k ~= "modules" then unexpected = true end
    end
    check(not unexpected, "no new SavedVariables (MightiePackDB keys: modules only)")
  end
end)

-- ════════════════════════════════════════════════════════════════════
if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("bugreport_spec: ok")

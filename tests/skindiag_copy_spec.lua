-- skindiag_copy_spec.lua
--
-- /mp skindiag copy and the options-panel "Copy skinning diagnostics"
-- button open the same compact dump in the shared bug-report copy popup
-- (multiline EditBox, Ctrl+A / Ctrl+C, Escape hides and clears focus).
-- The popup path does not spam chat. Collector-off still opens the popup
-- and says so in the text. No account name or file paths.
--
-- RED before the command, the button, and pkg.OpenSkinDiagCopy exist.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end }
local function clearChat()
  for i = #chat, 1, -1 do chat[i] = nil end
end
local function chatText()
  return table.concat(chat, "\n")
end

SlashCmdList = {}
StaticPopupDialogs = {}
StaticPopup_Show = function() end
OKAY = "Okay"
CANCEL = "Cancel"
ReloadUI = function() end
UIParent = {}
UISpecialFrames = {}
tinsert = table.insert
InterfaceOptions_AddCategory = function() end
GameTooltip = {
  SetOwner = function() end, SetText = function() end,
  AddLine = function() end, Show = function() end, Hide = function() end,
}
CopyTable = function(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = CopyTable(v) end
  return r
end

GetTime = function() return 1000 end
GetZone = function() return "The Barrens" end
GetSubzone = function() return "The Crossroads" end
GetRealmName = function() return "Forever" end
GetUnitName = function(u) if u == "player" then return "Mightie" end end
GetSpellInfo = function() return nil end
C_Map = {
  GetBestMapForUnit = function() return 1413 end,
  GetPlayerMapPosition = function()
    return { GetXY = function() return 0.5, 0.5 end }
  end,
}
UnitExists = function() return false end
UnitIsDead = function() return false end
UnitName = function() return nil end
UnitGUID = function() return nil end
GetNumLootItems = function() return 0 end
GetLootSlotLink = function() return nil end
GetLootSlotInfo = function() return nil end
GetLootSourceInfo = function() return nil end

local frames, editboxes, buttons, fonts = {}, {}, {}, {}
local function mkBase(kind)
  local o = {
    Kind = kind, Name = nil, scripts = {}, events = {},
    text = nil, shown = false, points = {},
  }
  o.SetScript = function(self, n, f) self.scripts[n] = f end
  o.GetScript = function(self, n) return self.scripts[n] end
  o.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
  o.ClearAllPoints = function(self) self.points = {} end
  o.SetSize = function(self, w, h) self.size = { w, h } end
  o.SetWidth = function(self, w) self.width = w end
  o.SetHeight = function(self, h) self.height = h end
  o.SetFontObject = function(self, f) self.fontObject = f end
  o.SetFont = function(self, ...) self.font = { ... } end
  o.SetTextColor = function(self, ...) self.textColor = { ... } end
  o.SetJustifyH = function(self, j) self.justifyH = j end
  o.SetWordWrap = function() end
  o.SetNonSpaceWrap = function() end
  o.EnableKeyboard = function(self, v) self.keyboardEnabled = v ~= false end
  o.EnableMouse = function(self, v) self.mouseEnabled = v ~= false end
  o.SetToplevel = function(self, v) self.toplevel = v and true or false end
  o.SetFrameLevel = function(self, n) self.frameLevel = n end
  o.Raise = function(self) self.raised = true end
  o.SetMovable = function() end
  o.RegisterForDrag = function() end
  o.SetFrameStrata = function(self, s) self.strata = s end
  o.SetBackdrop = function() end
  o.SetMultiLine = function() end
  o.SetAutoFocus = function() end
  o.SetTextInsets = function() end
  o.SetText = function(self, t) self.text = t ~= nil and tostring(t) or nil end
  o.GetText = function(self) return self.text end
  o.Show = function(self) self.shown = true end
  o.Hide = function(self)
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
  end
  o.IsShown = function(self) return self.shown == true end
  o.Enable = function(self) self.enabled = true end
  o.Disable = function(self) self.enabled = false end
  o.SetChecked = function(self, b) self.checked = b and true or false end
  o.GetChecked = function(self) return self.checked end
  o.RegisterEvent = function(self, n) self.events[n] = true end
  o.UnregisterEvent = function(self, n) self.events[n] = nil end
  o.SetFocus = function(self) self.hasFocus = true end
  o.HighlightText = function(self) self.highlighted = true end
  o.ClearFocus = function(self) self.hasFocus = false end
  o.CreateFontString = function(self)
    local f = mkBase("FontString")
    fonts[#fonts + 1] = f
    return f
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

local files = {
  "Core.lua",
  "Modules.lua",
  "Modules/NodeTrail/Config.lua",
  "Modules/Skinning/Probe.lua",
  "Modules/Skinning/Record.lua",
  "Modules/Skinning/Core.lua",
  "BugReport.lua",
}

local pkg = {}
-- Options.lua decides at load time whether NodeTrail's sub-options appear.
pkg.moduleOrder = { "NodeTrail" }
pkg.modules = { NodeTrail = { title = "NodeTrail" } }
pkg.IsModuleEnabled = function() return true end

local function loadFile(path)
  local chunk, err = loadfile(root .. "/MightiePack/" .. path)
  check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
  if chunk then
    local ok, e = pcall(chunk, "MightiePack", pkg)
    check(ok, "load " .. path .. ": " .. tostring(e))
  end
end

MightiePackDB = nil
NodeTrailDB = { skinning = { enabled = true } }
for _, f in ipairs(files) do loadFile(f) end
loadFile("Options.lua")

local function boot()
  for i = #frames, 1, -1 do
    local f = frames[i]
    if f.events and f.events.ADDON_LOADED and f.scripts and f.scripts.OnEvent then
      pcall(f.scripts.OnEvent, f, "ADDON_LOADED", "MightiePack")
      return
    end
  end
end
boot()

check(type(pkg.OpenSkinDiagCopy) == "function",
  "pkg.OpenSkinDiagCopy is exported (reuse of the bug-report popup)")
check(type(SlashCmdList.MIGHTIEPACK) == "function", "slash handler installed")

local P = pkg.Skinning and pkg.Skinning.Probe
check(type(P) == "table", "probe loaded")

-- Arm capture and plant a long step ring so compact mode can be measured.
if type(pkg.Skinning.Enable) == "function" then
  pcall(pkg.Skinning.Enable)
end
if P and P.capturing ~= true and type(P.Toggle) == "function" then
  P:Toggle()
end
if P and type(P.Step) == "function" then
  for i = 1, 25 do
    P:Step("UNIT_DIED", "k=death unit=creature g=..TEST" .. string.format("%02d", i), {})
  end
end

local function findEdit(name)
  for _, e in ipairs(editboxes) do
    if e.Name == name then return e end
  end
  return nil
end

local function findButton(label)
  for _, b in ipairs(buttons) do
    if b.text == label then return b end
  end
  return nil
end

-- ════════════════════════════════════════════════════════════════════
-- 1. /mp skindiag copy opens the popup with compact dump text, no chat
--    spam of the dump body, last ~20 steps, header + counts.
-- ════════════════════════════════════════════════════════════════════
do
  clearChat()
  local ok = pcall(SlashCmdList.MIGHTIEPACK, "skindiag copy")
  check(ok, "/mp skindiag copy does not error: " .. tostring(ok))

  local edit = findEdit("MightiePackSkinDiagEdit")
  check(edit ~= nil, "copy popup EditBox was created")
  local frame
  for _, f in ipairs(frames) do
    if f.Name == "MightiePackSkinDiagFrame" then frame = f end
  end
  check(frame ~= nil and frame.shown == true, "copy popup frame is shown")
  check(edit and edit.hasFocus == true, "EditBox SetFocus on open (same as bug popup)")
  check(edit and edit.highlighted == true, "EditBox HighlightText on open (Ctrl+A ready)")
  check(edit and type(edit.scripts.OnEscapePressed) == "function",
    "EditBox has OnEscapePressed")

  local text = edit and edit.text or ""
  check(type(text) == "string" and #text > 0, "popup has dump text")
  check(text:find("capture", 1, true) ~= nil or text:find("sub-option", 1, true) ~= nil,
    "popup includes the dump header (capture / sub-option) (got prefix: "
    .. text:sub(1, 200) .. ")")
  check(text:find("counts", 1, true) ~= nil or text:find("accounting:", 1, true) ~= nil,
    "popup includes counts or accounting")

  -- compact: last ~20 steps, not the first ones
  check(text:find("TEST01", 1, true) == nil,
    "compact dump omits early steps (step 1 of 25 should be dropped)")
  check(text:find("TEST25", 1, true) ~= nil or text:find("TEST24", 1, true) ~= nil,
    "compact dump keeps the last steps")

  -- Discord 2000-char budget: compact stays at or under the limit, or the
  -- popup tells the player the paste may need splitting.
  if #text > 2000 then
    check(text:lower():find("split", 1, true) ~= nil
      or (editboxes and false),
      "text over 2000 chars notes that it may need splitting for Discord")
  end

  -- no chat spam of the dump body (the existing dump prefix)
  local dumped = chatText():find("Skinning skindiag:", 1, true)
  check(dumped == nil,
    "the copy path does not print the dump to chat (got:\n" .. chatText() .. ")")

  -- no account name or filesystem paths (do not search the word "account":
  -- the dump's "accounting:" line is not personal data)
  check(not text:find("Account") and not text:lower():find("account name", 1, true),
    "dump does not include an account name")
  check(not text:find("C:\\") and not text:find("/home/") and not text:find("\\Account\\"),
    "dump does not include filesystem paths")

  -- Escape hides and clears focus, same as the bug popup
  if edit and edit.scripts.OnEscapePressed and frame then
    edit.scripts.OnEscapePressed(edit)
    check(frame.shown == false, "Escape hides the copy popup")
    check(edit.hasFocus == false, "Escape clears EditBox focus")
  end
end

-- ════════════════════════════════════════════════════════════════════
-- 2. Collector off: the popup still opens and says so. No chat spam.
-- ════════════════════════════════════════════════════════════════════
do
  if type(pkg.NodeTrail) == "table" and type(pkg.NodeTrail.SetSkinningEnabled) == "function" then
    pkg.NodeTrail.SetSkinningEnabled(false)
  else
    NodeTrailDB.skinning.enabled = false
  end
  clearChat()
  local ok = pcall(SlashCmdList.MIGHTIEPACK, "skindiag copy")
  check(ok, "/mp skindiag copy with collector off does not error")
  local edit = findEdit("MightiePackSkinDiagEdit")
  local text = edit and edit.text or ""
  check(edit ~= nil and type(text) == "string" and #text > 0,
    "popup still opens with collector off")
  local lower = text:lower()
  check(lower:find("off", 1, true) ~= nil or lower:find("session buffer", 1, true) ~= nil,
    "popup text says the collector / sub-option is off (got:\n" .. text:sub(1, 300) .. ")")
  check(chatText():find("Skinning skindiag:", 1, true) == nil,
    "collector-off copy path still does not dump to chat")
  -- restore
  if type(pkg.NodeTrail) == "table" and type(pkg.NodeTrail.SetSkinningEnabled) == "function" then
    pkg.NodeTrail.SetSkinningEnabled(true)
  else
    NodeTrailDB.skinning.enabled = true
  end
end

-- ════════════════════════════════════════════════════════════════════
-- 3. The button that opened this popup moved to the Skinning tab.
-- ════════════════════════════════════════════════════════════════════
-- Card t_a5de2f16: the "Copy skinning diagnostics" button is no longer in the
-- options panel — it lives in the unified window's Skinning tab, beside the
-- data it summarises, and calls the same pkg.ShowSkinDiagCopy this spec has
-- just proved (through the /mp skindiag copy path, above). The button's new
-- home and its OnClick are asserted in tests/window_tabs_spec.lua, which boots
-- the whole addon; here the panel must simply not keep a second copy.
do
  local panel
  for _, f in ipairs(frames) do
    if f.Name == "MightiePackOptionsPanel" then panel = f end
  end
  check(panel ~= nil, "options panel exists")
  if panel and type(panel.scripts.OnShow) == "function" then
    local ok, err = pcall(panel.scripts.OnShow, panel)
    check(ok, "panel OnShow: " .. tostring(err))
  end
  local btn = findButton("Copy skinning diagnostics")
  check(btn == nil,
    "the options panel no longer carries a 'Copy skinning diagnostics' button (it moved to the Skinning tab)")
end

if failed > 0 then
  io.stderr:write(failed .. " failed\n")
  os.exit(1)
end
print("ok")

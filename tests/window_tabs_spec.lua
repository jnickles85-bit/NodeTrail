-- window_tabs_spec.lua — t_a5de2f16 (audit group 4), after t_75309c97: ONE
-- window, the pack's two tabs.
--
-- What this pins, and why each is a fact rather than a restatement:
--
--   1. ONE outer frame: MightiePackWindow, 960x640, movable, with TWO tab
--      buttons in order — Touchstone / Pack Settings. Herbs and Skinning moved
--      out with NodeTrail, which is its own addon again.
--   2. Tab switching: exactly one host visible at a time, Current() follows.
--   3. Slash retargeting: /mp -> Pack Settings, and every Touchstone alias
--      reaches the ONE window because the vendored entry points are rerouted to
--      it (SF.ShowMain is the single route the seven aliases already used). /nt
--      belongs to the NodeTrail addon and is not registered here.
--   4. The position key is ADD-ONLY: the default is a centred window, a save
--      writes MightiePackDB.windowPos and nothing else, and a v0.3.6-beta
--      save (no windowPos) loads without an error and without gaining or
--      losing a key.
--   5. Pack Settings hosts Options.lua's panel (not a second frame).
--   6. Combat: opening, closing and switching tabs never show, hide or point
--      Blizzard's UIParent (the taint-relevant surface). The spec traps those
--      three calls on UIParent and fails if any happens.
--
-- Not a screenshot: this is harness geometry/draw evidence. A true in-game
-- capture needs the live client (see the card's OWNER-RUN note).

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

-- ── Chat ────────────────────────────────────────────────────────────────
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end }
local function clearChat() for i = #chat, 1, -1 do chat[i] = nil end end
local function chatHas(needle)
  for _, m in ipairs(chat) do
    if m:find(needle, 1, true) then return true end
  end
  return false
end

-- ── A small, measurable client ──────────────────────────────────────────
local allFrames = {}
local uiParentCalls = {}

local function newFrame(kind, name, parent, template)
  local f = {
    kind = kind or "Frame",
    Name = name,
    template = template,
    children = {},
    scripts = {},
    points = {},
    shown = true,
    width = 0, height = 0,
    parent = nil,
  }
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:GetScript(n) return self.scripts[n] end
  function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
  function f:ClearAllPoints() self.points = {} end
  function f:GetNumPoints() return #self.points end
  function f:SetSize(w, h) self.width, self.height = w, h end
  function f:SetWidth(w) self.width = w end
  function f:SetHeight(h) self.height = h end
  function f:GetWidth() return self.width end
  function f:GetHeight() return self.height end
  function f:SetAllPoints(rel) self._allPoints = rel or self.parent end
  function f:Show()
    -- Card t_ea66cd84 (AC-N5): the client's own rule. A frame is BORN shown, so
    -- Show() on an already-shown frame is a no-op that fires nothing; OnShow
    -- fires only on a false -> true transition of THIS frame's own flag.
    if self.shown == true then return end
    self.shown = true
    local fn = self.scripts and self.scripts.OnShow
    if type(fn) == "function" then pcall(fn, self) end
  end
  function f:Hide()
    if self.shown ~= true then return end
    self.shown = false
    local fn = self.scripts and self.scripts.OnHide
    if type(fn) == "function" then pcall(fn, self) end
  end
  function f:IsShown() return self.shown == true end
  function f:IsVisible() return self.shown == true end
  function f:EnableMouse() end
  function f:EnableMouseWheel() end
  function f:SetFrameStrata() end
  function f:SetFrameLevel() end
  function f:SetToplevel() end
  function f:SetClampedToScreen() end
  function f:SetMovable() end
  function f:RegisterForDrag() end
  function f:StartMoving() end
  function f:StopMovingOrSizing() end
  function f:GetLeft() return self.left end
  function f:GetTop() return self.top end
  function f:SetBackdrop() end
  function f:SetBackdropColor() end
  function f:SetBackdropBorderColor() end
  function f:Raise() end
  function f:SetScrollChild(child) self.scrollChild = child end
  function f:GetVerticalScroll() return self.vscroll or 0 end
  function f:SetVerticalScroll(v) self.vscroll = v end
  function f:SetButtonState() end
  function f:RegisterEvent() end
  function f:UnregisterEvent() end
  function f:RegisterUnitEvent() end
  function f:IsEventRegistered() return false end
  function f:SetText(t) self.text = t end
  function f:GetText() return self.text end
  function f:SetNormalTexture() end
  function f:GetChildren()
    local out = {}
    for i, c in ipairs(self.children) do out[i] = c end
    return out
  end
  function f:SetParent(p)
    if self.parent then
      local kids = self.parent.children
      for i = #kids, 1, -1 do
        if kids[i] == self then table.remove(kids, i) end
      end
    end
    self.parent = p
    if type(p) == "table" and type(p.children) == "table" then
      p.children[#p.children + 1] = self
    end
  end
  function f:GetParent() return self.parent end
  function f:CreateFontString()
    local fs = newFrame("FontString", nil, f)
    fs.text = ""
    fs.points = {}
    function fs:SetText(t) self.text = tostring(t or "") end
    function fs:GetText() return self.text end
    function fs:SetTextColor(...) self.color = { ... } end
    function fs:SetJustifyH(j) self.justify = j end
    function fs:SetJustifyV(j) self.justifyV = j end
    function fs:SetWordWrap(v) self.wordWrap = v end
    function fs:SetFont() end
    function fs:SetFontObject() end
    function fs:GetStringWidth() return #self.text * 6 end
    function fs:GetHeight() return 12 end
    f.children[#f.children + 1] = fs
    return fs
  end
  function f:CreateTexture()
    local t = newFrame("Texture", nil, f)
    function t:SetTexture() end
    function t:SetColorTexture() end
    function t:SetVertexColor() end
    function t:SetTexCoord() end
    function t:SetDrawLayer() end
    function t:SetBlendMode() end
    return t
  end
  if type(parent) == "table" then
    f.parent = parent
    if type(parent.children) == "table" then parent.children[#parent.children + 1] = f end
  end
  allFrames[#allFrames + 1] = f
  return f
end

CreateFrame = function(kind, name, parent, template)
  return newFrame(kind, name, parent, template)
end

UIParent = newFrame("Frame", "UIParent")
UIParent.width, UIParent.height = 1920, 1080
UIParent.left, UIParent.top = 0, 1080
-- The taint-relevant surface: opening/closing/switching must never touch it.
UIParent.Show = function() uiParentCalls[#uiParentCalls + 1] = "Show" end
UIParent.Hide = function() uiParentCalls[#uiParentCalls + 1] = "Hide" end
UIParent.SetPoint = function() uiParentCalls[#uiParentCalls + 1] = "SetPoint" end
UIParent.SetSize = function() uiParentCalls[#uiParentCalls + 1] = "SetSize" end

WorldFrame = newFrame("Frame", "WorldFrame")
UISpecialFrames = {}
SlashCmdList = {}
StaticPopupDialogs = {}
GameTooltip = newFrame("Frame", "GameTooltip")
GameTooltip.SetOwner = function() end
GameTooltip.SetText = function() end
GameTooltip.AddLine = function() end
GameTooltip.ClearLines = function() end
GameTooltip.GetName = function() return "GameTooltip" end

CopyTable = function(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = CopyTable(v) end
  return r
end

time = function() return 1700000000 end
GetTime = function() return 0 end
GetLocale = function() return "enUS" end
GetUnitName = function() return "Testchar" end
GetRealmName = function() return "Testrealm" end
GetBuildInfo = function() return "1", "15", "0", "16001", "x" end
IsAddOnLoaded = function() return false end
UnitExists = function() return false end
UnitAffectingCombat = function() return false end
InCombatLockdown = function() return false end
GetSpellInfo = function(id)
  if id == 2259 then return "Alchemy" end
  if id == 2366 then return "Herb Gathering" end
  if id == 8613 then return "Skinning" end
  return nil
end
C_Map = { GetBestMapForUnit = function() return 1429 end }
C_Timer = { After = function() end }
ReloadUI = function() end
OKAY, CANCEL = "OKAY", "CANCEL"
IsShiftKeyDown = function() return false end

-- ── Load the addon in TOC order (the files this spec needs) ─────────────
local pkg = {}
local function loadFile(path)
  local chunk, err = loadfile(root .. "/MightiePack/" .. path)
  check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
  if not chunk then return end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. path .. ": " .. tostring(e))
end

-- A v0.3.6-beta-shaped save: the four SavedVariables with keys a real player
-- has, and NO windowPos. The window must default and must not rewrite them.
MightiePackDB = {
  modules = { NodeTrail = true, Touchstone = true },
  seen = { firstRun = true },
  bugCount = 3,
}
NodeTrailDB = {
  schema = 2,
  herbs = {
    schema = 2, total = 2,
    maps = { [1429] = {} },
    mapTotals = { [1429] = 2 },
    stats = { gathers = { [2447] = 2 }, co = {}, names = { [2447] = "Peacebloom" } },
    hotspots = {}, folded = {},
  },
  skinning = { enabled = true, schema = 2, chars = {
    ["Testchar-Testrealm"] = {
      schema = 2, records = {}, order = {}, unclassified = {}, hotspots = {},
      unpositionedEvicted = {},
      creatures = { [1234] = {
        corpses = 3, kills = 4, skinned = 3, skinWindows = 3,
        skin = { [2934] = { itemID = 2934, count = 6, seen = 3, name = "Ruined Leather Scraps" } },
      } },
      counts = { kills = 4, corpseWindows = 3, skinWindows = 3, skinCasts = 3, unattributedWindows = 1 },
    },
  } },
  route = { autoRefresh = true },
}
StatForgeDB = { ui = { scale = 1 } }

loadFile("Core.lua")
loadFile("Modules.lua")
for _, f in ipairs({
}) do loadFile(f) end
loadFile("BugReport.lua")
loadFile("Options.lua")
loadFile("Window.lua")
loadFile("Window/Common.lua")

local W = pkg.Window
check(type(W) == "table", "pkg.Window exists")

-- The Touchstone seam needs a StatForge to reroute. This is the vendored
-- module's public shape, not its body: the seven aliases reach ShowMain.
local sfCalls = { show = 0, select = nil, refresh = 0 }
StatForge = {
  ShowMain = function() sfCalls.show = sfCalls.show + 1 end,
  HideMain = function() end,
  ToggleMain = function() end,
  IsMainShown = function() return false end,
  RefreshActiveTab = function() sfCalls.refresh = sfCalls.refresh + 1 end,
  SelectTab = function(id) sfCalls.select = id end,
}
loadFile("Window/TouchstoneTab.lua")

-- The slashes a module registers appear when the module is enabled (a login
-- does this): NodeTrail owns /nt, Touchstone owns its three aliases.
local okEnable = pcall(pkg.EnableModules)
check(okEnable, "the enabled modules start (as they do at login)")

-- ── 1. one frame, four tabs ─────────────────────────────────────────────
local f = W.Frame()
check(type(f) == "table", "the window frame is created")
check(f and f.Name == "MightiePackWindow", "the frame is MightiePackWindow (got " .. tostring(f and f.Name) .. ")")
check(f and f.width == 960 and f.height == 640,
  "the window is 960x640 (got " .. tostring(f and f.width) .. "x" .. tostring(f and f.height) .. ")")
check(type(f.points[1]) == "table" and f.points[1][1] == "CENTER",
  "with no saved position the window opens centred (got " .. tostring(f.points[1] and f.points[1][1]) .. ")")

local order = W.TABS
check(#order == 2, "two tabs (got " .. tostring(#order) .. ")")
check(order[1] == "touchstone" and order[2] == "settings",
  "tab order is Touchstone / Pack Settings (the pack's own two tabs)")
check(W.TAB_LABELS.touchstone == "Touchstone" and W.TAB_LABELS.settings == "Pack Settings",
  "tab labels are the pack's own two")
check(W.TAB_LABELS.herbs == nil and W.TAB_LABELS.skinning == nil,
  "Herbs and Skinning moved out with NodeTrail, which is its own addon now")
local seenButtons = 0
for _, id in ipairs(order) do
  if W.tabButtons[id] then seenButtons = seenButtons + 1 end
end
check(seenButtons == 2, "two tab buttons exist (got " .. tostring(seenButtons) .. ")")
check(W.titleBar ~= nil and type(W.titleBar.RegisterForDrag) == "function",
  "the window has a drag handle")

-- One outer frame: the window is the only frame with a 960x640 size.
local sized = 0
for _, fr in ipairs(allFrames) do
  if fr.width == 960 and fr.height == 640 then sized = sized + 1 end
end
check(sized == 1, "exactly one 960x640 outer frame (got " .. tostring(sized) .. ")")

-- ── 2. tab switching shows exactly one host ─────────────────────────────
function W.SelectTab_check(id)
  local visible = {}
  for _, t in ipairs(order) do
    local host = W.hosts[t]
    if host and host:IsShown() then visible[#visible + 1] = t end
  end
  return visible
end

for _, id in ipairs(order) do
  W.SelectTab(id)
  local visible = W.SelectTab_check(id)
  check(#visible == 1, "only one tab body is visible on " .. id .. " (got " .. tostring(#visible) .. ")")
  check(visible[1] == id, "the visible body is " .. id .. " (got " .. tostring(visible[1]) .. ")")
  check(W.Current() == id, "Current() is " .. id)
end

-- ── 3. slash retargeting ────────────────────────────────────────────────
W.Close()
check(W.IsShown() == false, "Close hides the window")
SlashCmdList.MIGHTIEPACK("")
check(W.IsShown() == true, "/mp opens the window")
check(W.Current() == "settings", "/mp opens the Pack Settings tab (got " .. tostring(W.Current()) .. ")")

W.Close()
-- Card t_75309c97: /nt answers in the NodeTrail addon now. The pack must not
-- register it, and must not open its own window for it either.
check(SlashCmdList.NODETRAIL == nil, "/nt is not the pack's command any more")

-- The Touchstone aliases: the vendored handlers all call SF.ShowMain, and the
-- seam reroutes that to the ONE window. Proving the seam covers the aliases is
-- a source fact (the vendored bare-open branch) plus the behaviour below.
local function fileText(p)
  local fh = io.open(root .. "/MightiePack/" .. p, "r")
  if not fh then return nil end
  local t = fh:read("*a")
  fh:close()
  return t
end
local ca = fileText("Modules/Touchstone/ChestAdvisor/ChestAdvisor.lua") or ""
check(ca:find("SLASH_CHESTADVISOR1 = \"/up\"", 1, true) ~= nil
  and ca:find("SLASH_CHESTADVISOR2 = \"/upgrade\"", 1, true) ~= nil
  and ca:find("SLASH_CHESTADVISOR3 = \"/chestadvice\"", 1, true) ~= nil
  and ca:find("SLASH_CHESTADVISOR4 = \"/ts\"", 1, true) ~= nil,
  "the four ChestAdvisor aliases are still registered")
check(ca:find("host.ShowMain()", 1, true) ~= nil,
  "the bare alias branch calls SF.ShowMain (the seam's single route)")
local tc = fileText("Modules/Touchstone/Core.lua") or ""
check(tc:find("SLASH_TOUCHSTONE1 = \"/touchstone\"", 1, true) ~= nil
  and tc:find("SLASH_TOUCHSTONE2 = \"/sf\"", 1, true) ~= nil
  and tc:find("SLASH_TOUCHSTONE3 = \"/statforge\"", 1, true) ~= nil,
  "the three Touchstone aliases are still registered")

W.Close()
StatForge.ShowMain()
check(W.IsShown() == true and W.Current() == "touchstone",
  "SF.ShowMain opens the ONE window on Touchstone (got " .. tostring(W.Current()) .. ")")
check(StatForge.IsMainShown() == true, "SF.IsMainShown follows the window")
StatForge.ShowMain("log")
check(sfCalls.select == "log", "an explicit inner tab is still selected (got " .. tostring(sfCalls.select) .. ")")
StatForge.ToggleMain()
check(W.IsShown() == false, "SF.ToggleMain closes the window")

-- ── 4. the position key is add-only ─────────────────────────────────────
check(W.SavedPosition() == nil, "a v0.3.6-beta save has no saved window position")
check(MightiePackDB.windowPos == nil, "reading the position does not create the key")
-- ...and the rest of that save is untouched.
check(MightiePackDB.modules and MightiePackDB.modules.NodeTrail == true,
  "the modules table survives a window open")
check(MightiePackDB.bugCount == 3, "an unrelated MightiePackDB key survives")
check(StatForgeDB.ui.scale == 1, "StatForgeDB.ui.scale is not touched by the window")

-- A drag writes the new key and ONLY the new key.
f.left, f.top = 120, 900
local keysBefore = {}
for k in pairs(MightiePackDB) do keysBefore[k] = true end
check(W.SavePosition() == true, "a drag stop can save the position")
check(type(MightiePackDB.windowPos) == "table"
  and MightiePackDB.windowPos.left == 120 and MightiePackDB.windowPos.top == 900,
  "the position is saved as { left, top } (got "
    .. tostring(MightiePackDB.windowPos and MightiePackDB.windowPos.left) .. ")")
for k in pairs(MightiePackDB) do
  check(k == "windowPos" or keysBefore[k] == true, "the save added only windowPos (found " .. tostring(k) .. ")")
end
local added = 0
for k in pairs(MightiePackDB) do
  if not keysBefore[k] then added = added + 1 end
end
check(added == 1, "exactly one new key was written (got " .. tostring(added) .. ")")

-- ── 5. Pack Settings hosts the options panel ──
W.Open("settings")
local panel = pkg.optionsPanel
check(type(panel) == "table", "pkg.optionsPanel still exists")
check(panel and panel:GetParent() == W.hosts.settings,
  "the Pack Settings tab hosts the options panel (its content moved in whole)")
-- ── 6. the combat rule: UIParent is never touched ───────────────────────
check(#uiParentCalls == 0,
  "opening, closing and switching tabs never Show/Hide/SetPoint/SetSize UIParent (got "
    .. table.concat(uiParentCalls, ",") .. ")")
-- ...and the same again with the client reporting combat.
UnitAffectingCombat = function() return true end
InCombatLockdown = function() return true end
local okCombat = pcall(function()
  W.Open("settings")
  W.SelectTab("touchstone")
  W.SelectTab("touchstone")
  W.SelectTab("settings")
  W.Close()
end)
check(okCombat, "open/switch/close does not raise while in combat")
check(#uiParentCalls == 0, "in combat too, UIParent is untouched (got "
  .. table.concat(uiParentCalls, ",") .. ")")
UnitAffectingCombat = function() return false end
InCombatLockdown = function() return false end

if failed == 0 then
  print("window_tabs_spec: ok")
else
  print(("window_tabs_spec: %d failure(s)"):format(failed))
  os.exit(1)
end

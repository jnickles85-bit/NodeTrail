-- options_spec.lua — t_36412359
-- NodeTrail: recipe scan in the options panel, /nt scanrecipes (alias
-- /nt recipes), and auto-rescan on every Alchemy open (+ NEW_RECIPE_LEARNED
-- when the client knows it).
--
-- These tests are RED on c0ed9cd (the panel block, StatusLine/TryScanNow,
-- and the slash command do not exist there) — run that commit once to show
-- it, then green on this commit.
--
-- The client model speaks the live C_TradeSkillUI contract pinned in
-- c0ed9cd (t_81da8886): GetRecipeSchematic(recipeSpellID, isRecraft) with
-- reagents under reagentSlotSchematics[i].reagents[j], plus a
-- profession-naming call. Scan internals are NOT re-implemented here —
-- every assertion goes through the real Scan path.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. msg .. "\n")
  end
end

-- ── Chat capture ─────────────────────────────────────────────────────
local chat = {}
-- Events this harness's fake client refuses to register. Validity is never
-- asked of C_EventUtils (restricted namespace — see event_gate_spec); the
-- client decides by raising on RegisterEvent.
local unknownEvents = {}
DEFAULT_CHAT_FRAME = {
  AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end,
}
local function clearChat()
  for i = #chat, 1, -1 do chat[i] = nil end
end
local function chatText()
  return table.concat(chat, "\n")
end
local function chatContains(needle)
  for _, m in ipairs(chat) do
    if m and m:find(needle, 1, true) ~= nil then return true end
  end
  return false
end
local function chatLineContaining(needle)
  for _, m in ipairs(chat) do
    if m and m:find(needle, 1, true) ~= nil then return m end
  end
  return nil
end

function CopyTable(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = CopyTable(v) end
  return r
end

SlashCmdList = {}
StaticPopupDialogs = {}
StaticPopup_Show = function() end
OKAY = "OKAY"
CANCEL = "CANCEL"
ReloadUI = function() end
time = os.time
GetSpellInfo = function(id)
  if id == 2259 then return "Alchemy" end
  if id == 2366 then return "Herb Gathering" end
  return nil
end
C_Map = { GetBestMapForUnit = function() return 1429 end }
UnitExists = function() return false end
UIParent = {}
WorldFrame = {}
GameTooltip = {
  SetOwner = function() end,
  SetText = function() end,
  AddLine = function() end,
  Show = function() end,
  Hide = function() end,
}

-- ── Frame / font / button harness (mirrors the checkbox + button
-- surfaces Options.lua actually uses) ────────────────────────────────
local frames, fonts, buttons = {}, {}, {}
local function mkBase(kind)
  local o = {
    Kind = kind,
    Name = nil,
    scripts = {},
    events = {},
    text = nil,
    shown = true,
    size = nil,
    checked = false,
  }
  o.SetScript = function(self, n, f) self.scripts[n] = f end
  o.SetPoint = function(self) end
  o.SetText = function(self, t) self.text = t end
  o.GetText = function(self) return self.text end
  o.Show = function(self) self.shown = true end
  o.Hide = function(self) self.shown = false end
  o.SetSize = function(self, w, h) self.size = { w, h } end
  o.Enable = function(self) self.enabled = true end
  o.Disable = function(self) self.enabled = false end
  o.SetChecked = function(self, b) self.checked = b and true or false end
  o.GetChecked = function(self) return self.checked end
  o.RegisterEvent = function(self, n)
    if unknownEvents[n] then
      error('Attempt to register unknown event "' .. tostring(n) .. '"', 2)
    end
    self.events[n] = true
  end
  o.UnregisterEvent = function(self, n) self.events[n] = nil end
  return o
end
CreateFrame = function(kind, name, parent, template)
  local o = mkBase(kind or "Frame")
  o.Name = name
  o.CreateFontString = function(self)
    local f = mkBase("FontString")
    table.insert(fonts, f)
    return f
  end
  if kind == "Button" then
    table.insert(buttons, o)
  end
  table.insert(frames, o)
  return o
end

-- ── Load the addon in TOC order ─────────────────────────────────────
local pkg = {}
local function loadFile(path)
  local f = assert(loadfile(root .. "/" .. path))
  f("MightiePack", pkg)
end
loadFile("MightiePack/Core.lua")
loadFile("MightiePack/Modules.lua")
for _, f in ipairs({
  "locale/enUS.lua",
  "Config.lua",
  "Data/GM2.lua",
  "Data/Recorder.lua",
  "Data/Density.lua",
  "Data/HerbData.lua",
  "Data/Recipes.lua",
  "Core.lua",
}) do
  local lf = assert(loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. f))
  lf("MightiePack", pkg)
end
loadFile("MightiePack/Options.lua")

local ns = pkg.NodeTrail
local Rec = ns.Recipes
check(type(ns) == "table" and type(Rec) == "table", "NodeTrail + Recipes namespace loaded")

-- ── Live-contract C_TradeSkillUI stub (c0ed9cd contract: (id, false),
-- reagentSlotSchematics) with a scan-call counter ───────────────────
local api = { scanCalls = 0, prof = nil }
local recipes = {}
local function addRecipe(id, name, reagentIds)
  recipes[id] = { name = name, reagents = reagentIds }
end
local modernStub = {
  GetAllRecipeIDs = function()
    api.scanCalls = api.scanCalls + 1
    local ids = {}
    for id in pairs(recipes) do table.insert(ids, id) end
    table.sort(ids)
    return ids
  end,
  -- nil on purpose: every recipe goes through the schematic, exactly
  -- like the live client.
  GetRecipeInfo = function() return nil end,
  GetRecipeSchematic = function(id, isRecraft)
    assert(isRecraft == false,
      "GetRecipeSchematic(recipeSpellID, isRecraft, ...): bad argument #2")
    local r = recipes[id]
    if not r then return nil end
    local slots = {}
    for _, rid in ipairs(r.reagents) do
      table.insert(slots, { reagents = { { itemID = rid, quantity = 1 } } })
    end
    return { name = r.name, reagentSlotSchematics = slots }
  end,
  GetChildProfessionInfo = function()
    if api.prof then return { skillLineName = api.prof } end
    return nil -- no profession window open
  end,
}
C_TradeSkillUI = modernStub

-- ── Addon boot (the ADDON_LOADED path, driven directly) ─────────────
local okBoot, bootErr = pcall(function()
  pkg.GetSettings()
  pkg.EnableModules()
end)
check(okBoot, "addon boot (EnableModules): " .. tostring(bootErr))
check(type(SlashCmdList.NODETRAIL) == "function", "/nt registered after boot")

local function latestEventFrame()
  -- the Recipes event frame: the most recent frame with an OnEvent
  -- handler that carries TRADE_SKILL_SHOW
  for i = #frames, 1, -1 do
    local f = frames[i]
    if type(f.scripts.OnEvent) == "function" and f.events.TRADE_SKILL_SHOW == true then
      return f
    end
  end
  return nil
end

local function fire(ev)
  local f = latestEventFrame()
  check(f ~= nil and type(f.scripts.OnEvent) == "function",
    "an event frame is wired for " .. ev)
  if not f then return end
  local ok, err = pcall(f.scripts.OnEvent, f, ev)
  check(ok, "firing " .. ev .. ": " .. tostring(err))
end

local function fsText(f)
  if not f then return nil end
  return f.text
end

local function openPanel()
  clearChat()
  local panel = nil
  for _, f in ipairs(frames) do
    if f.Name == "MightiePackOptionsPanel" then panel = f end
  end
  check(panel ~= nil, "options panel frame exists")
  if panel and type(panel.scripts.OnShow) == "function" then
    local ok, err = pcall(panel.scripts.OnShow, panel)
    check(ok, "panel OnShow: " .. tostring(err))
  end
  return panel
end

local function freshDB()
  NodeTrailDB = nil
  ns.GetDB()
  Rec._diag = nil
  Rec._error = nil
  Rec._pendingRescan = nil
end

local function runSlash(cmd)
  clearChat()
  check(type(SlashCmdList.NODETRAIL) == "function", "/nt present for " .. cmd)
  if type(SlashCmdList.NODETRAIL) ~= "function" then return "" end
  SlashCmdList.NODETRAIL(cmd)
  return chatText()
end

-- panel block handles (found by the text Options.lua sets)
local panelFsHeader, panelFsStatus, panelFsError, panelFsNote, recButton = nil, nil, nil, nil, nil
do
  for i, f in ipairs(fonts) do
    if f.text == "Alchemy Recipes" then
      panelFsHeader = f
      panelFsStatus = fonts[i + 1]
      panelFsError = fonts[i + 2]
      -- t_4ab7c230: the hidden-list note sits under the error line.
      panelFsNote = fonts[i + 3]
      break
    end
  end
  for _, b in ipairs(buttons) do
    if b.text == "Scan now" then recButton = b end
  end
end

local alch = function()
  return (NodeTrailDB and NodeTrailDB.recipes) and NodeTrailDB.recipes.alchemy or nil
end
local function scannedSet()
  return NodeTrailDB ~= nil
    and NodeTrailDB.recipes ~= nil
    and NodeTrailDB.recipes.alchemyScanned ~= nil
end
local function namesFor(id)
  local m = alch()
  return m and m[id] or nil
end
local function mapHas(id, name)
  local list = namesFor(id)
  if not list then return false end
  for _, n in ipairs(list) do
    if n == name then return true end
  end
  return false
end

-- ════════════════════════════════════════════════════════════════════
-- Panel structure (RED on c0ed9cd: none of this exists there)
-- ════════════════════════════════════════════════════════════════════
check(panelFsHeader ~= nil, "panel has an 'Alchemy Recipes' header")
check(panelFsStatus ~= nil, "panel has a recipes status line")
check(panelFsError ~= nil, "panel has a recipes error line")
check(recButton ~= nil, "panel has a 'Scan now' button")
if recButton then
  check(type(recButton.scripts.OnClick) == "function", "'Scan now' has an OnClick handler")
end

-- ════════════════════════════════════════════════════════════════════
-- State 2: "not scanned yet" (API present, no scan has run)
-- ════════════════════════════════════════════════════════════════════
local savedClick = recButton and recButton.scripts.OnClick
check(type(savedClick) == "function", "button handler exists for the closed-window test")
if type(Rec.StatusLine) == "function" then
  local okSL, sl = pcall(Rec.StatusLine, Rec)
  check(okSL and sl == "not scanned yet",
    "StatusLine (fresh state) says 'not scanned yet' (got " .. tostring(sl) .. ")")
  local okLS, ls = pcall(function()
    local okT, t = pcall(Rec.TryScanNow, Rec)
    local okA, a = pcall(Rec.AlchemyOpen, Rec)
    return okT and t == true and okA and a == true
  end)
  check(okLS, "StatusLine/TryScanNow/AlchemyOpen call cleanly")
end

freshDB()
openPanel()
check(fsText(panelFsStatus) == "not scanned yet",
  "panel status line (fresh state): 'not scanned yet' (got " .. tostring(fsText(panelFsStatus)) .. ")")

-- ════════════════════════════════════════════════════════════════════
-- 'Scan now' with NO Alchemy window: the instruction, nothing else,
-- and NO alchemyScanned write (RED on c0ed9cd: no button)
-- ════════════════════════════════════════════════════════════════════
api.prof = nil -- no profession window open
if type(savedClick) == "function" then
  clearChat()
  local okCl, clErr = pcall(savedClick)
  check(okCl, "button click does not error: " .. tostring(clErr))
  check(chatContains("open your Alchemy window, then press this again"),
    "closed window → instruction line printed")
  check(#chat == 1,
    "closed window → ONLY the instruction is printed (got " .. #chat .. " line(s))")
  check(api.scanCalls == 0, "closed window → the scan did NOT run (scanCalls=" .. api.scanCalls .. ")")
  check(alch() == nil or (next(alch()) == nil), "closed window → no recipe map written")
  check(NodeTrailDB == nil or NodeTrailDB.recipes == nil
    or NodeTrailDB.recipes.alchemyScanned == nil,
    "closed window → alchemyScanned NOT set")
  openPanel()
  check(fsText(panelFsStatus) == "not scanned yet",
    "panel still 'not scanned yet' after the refused button press")
else
  check(false, "closed-window button behavior (no handler on the button)")
end

-- ════════════════════════════════════════════════════════════════════
-- /nt scanrecipes + /nt recipes: same status as the panel; scans only
-- while the Alchemy window is open (RED on c0ed9cd: unknown command)
-- ════════════════════════════════════════════════════════════════════
api.prof = nil
local outSR = runSlash("scanrecipes")
check(outSR:find("NodeTrail recipes: not scanned yet", 1, true) ~= nil,
  "/nt scanrecipes prints the panel's status line (got: " .. outSR:gsub("\n", " | ") .. ")")
check(chat[1] == "NodeTrail recipes: not scanned yet",
  "/nt scanrecipes (closed) status line is exactly the panel's state (got " .. tostring(chat[1]) .. ")")
check(outSR:find("open your Alchemy window, then press this again", 1, true) ~= nil,
  "/nt scanrecipes (window closed) prints the instruction too")
check(api.scanCalls == 0, "/nt scanrecipes (closed) did not run a scan")
local outR = runSlash("recipes")
check(outR == outSR, "/nt recipes (alias) output matches /nt scanrecipes")
check(NodeTrailDB == nil or NodeTrailDB.recipes == nil
  or NodeTrailDB.recipes.alchemyScanned == nil,
  "aliases do not set alchemyScanned either")

local helpOut = runSlash("help")
check(helpOut:find("scanrecipes", 1, true) ~= nil, "help documents /nt scanrecipes")
check(helpOut:find("/nt recipes", 1, true) ~= nil, "help documents the /nt recipes alias")

-- /nt status regression: old line format still there
local stOut = runSlash("status")
check(stOut:find("Alchemy recipes:", 1, true) ~= nil, "/nt status keeps the Alchemy recipes line")

-- ════════════════════════════════════════════════════════════════════
-- State 3: "this client cannot list recipes (<reason>)" — no API at
-- all (RED on c0ed9cd: StatusLine does not exist)
-- ════════════════════════════════════════════════════════════════════
C_TradeSkillUI = nil
Rec._diag = nil
freshDB()
openPanel()
local lineNoAPI = fsText(panelFsStatus)
check(type(lineNoAPI) == "string" and lineNoAPI:find("this client cannot list recipes (", 1, true) ~= nil,
  "panel state (no API): 'this client cannot list recipes (…)’ (got " .. tostring(lineNoAPI) .. ")")

-- reason variant: the real error string from a previous no-API scan
local longNoneErr = "no usable trade-skill API on this client (C_TradeSkillUI and the legacy trade-skill globals are both absent)"
Rec._diag = { path = "none", recipeCount = 0, error = longNoneErr }
openPanel()
local lineNoAPI2 = fsText(panelFsStatus)
check(type(lineNoAPI2) == "string"
  and lineNoAPI2:find("this client cannot list recipes (" , 1, true) ~= nil
  and lineNoAPI2:find("no usable trade-skill API on this client", 1, true) ~= nil,
  "no-API state uses the reason from Recipes._diag")
if type(lineNoAPI2) == "string" then
  check(#lineNoAPI2 < #(longNoneErr .. "this client cannot list recipes (x)"),
    "no-API reason is truncated for the panel")
end

if type(savedClick) == "function" then
  api.prof = nil
  clearChat()
  pcall(savedClick)
  check(chatContains("this client cannot list recipes ("),
    "button (no API) reports the client limitation honestly")
  check(not chatContains("open your Alchemy window, then press this again"),
    "button (no API) does NOT promise the open-window step")
end

-- back to the modern client
C_TradeSkillUI = modernStub
freshDB()

-- ════════════════════════════════════════════════════════════════════
-- State 1: "scanned: N recipes (modern, <when>)" — first open auto-
-- scans, the panel refreshes, and a RE-OPEN runs a second scan that
-- picks up a newly learned recipe (RED on c0ed9cd: no panel line)
-- ════════════════════════════════════════════════════════════════════
addRecipe(101, "Minor Healing Potion", { 2447, 765, 3371 })
addRecipe(102, "Elixir of Lion's Strength", { 2449, 765, 3371 })
freshDB()
api.prof = "Alchemy"
fire("TRADE_SKILL_SHOW")
check(api.scanCalls == 1, "first Alchemy open runs a scan (scanCalls=" .. api.scanCalls .. ")")
check(scannedSet(), "first scan sets alchemyScanned")
check(namesFor(2447) and namesFor(2447)[1] == "Minor Healing Potion" and #namesFor(2447) == 1,
  "2447 → Minor Healing Potion only")
check(namesFor(765) and #namesFor(765) == 2 and namesFor(765)[1] == "Elixir of Lion's Strength",
  "765 → both recipes, sorted (live schematic contract walked)")
openPanel()
local lineScanned = fsText(panelFsStatus)
check(type(lineScanned) == "string" and lineScanned:find("scanned: 2 recipes %(modern, ") == 1,
  "panel state (scanned): 'scanned: 2 recipes (modern, <when>)' (got " .. tostring(lineScanned) .. ")")
check(type(lineScanned) == "string" and lineScanned:find("ago", 1, true) ~= nil,
  "scanned line carries the 'when'")

local stOut2 = runSlash("status")
check(stOut2:find("Alchemy recipes: scanned", 1, true) ~= nil, "/nt status still reports the scan (regression)")

-- second open: a newly learned recipe must appear without any button
addRecipe(103, "New Brew", { 765 })
api.prof = nil -- window closed
api.prof = "Alchemy" -- reopened
fire("TRADE_SKILL_SHOW")
check(api.scanCalls == 2, "REOPEN runs a SECOND scan (scanCalls=" .. api.scanCalls .. ")")
check(mapHas(765, "New Brew"), "newly learned recipe picked up by the reopen scan")
check(namesFor(765) and #namesFor(765) == 3, "reopen scan rebuilt the map (3 names for 765)")
openPanel()
lineScanned = fsText(panelFsStatus)
check(type(lineScanned) == "string" and lineScanned:find("scanned: 3 recipes %(modern, ") == 1,
  "panel refreshes to the new recipe count (got " .. tostring(lineScanned) .. ")")

-- '/'nt scanrecipes while the window is open runs the scan AND prints
-- the panel's status line — the POST-scan truth, so a panel refreshed
-- right after shows the identical line
api.prof = "Alchemy"
local callsBefore = api.scanCalls
addRecipe(104, "Potion of Learning", { 2447 })
local outScan = runSlash("scanrecipes")
check(api.scanCalls == callsBefore + 1, "/nt scanrecipes (window open) performs the scan")
check(mapHas(2447, "Potion of Learning"),
  "/nt scanrecipes scan picked up the new recipe")
local slashStatus = chat[1]
openPanel()
local panelLineAfter = fsText(panelFsStatus)
local function normWhen(s)
  return (tostring(s or ""):gsub("%d+[smh] ago", "<when>"))
end
check(slashStatus == "NodeTrail recipes: " .. tostring(panelLineAfter),
  "panel status line == /nt scanrecipes status line (panel=" .. tostring(panelLineAfter)
    .. " slash=" .. tostring(slashStatus) .. ")")
check(normWhen(slashStatus) == "NodeTrail recipes: scanned: 4 recipes (modern, <when>)",
  "/nt scanrecipes status is the post-scan truth (got " .. tostring(slashStatus) .. ")")
check(type(outScan) == "string" and outScan:find("scanned successfully", 1, true) ~= nil,
  "/nt scanrecipes reports the scan result too")

-- ════════════════════════════════════════════════════════════════════
-- NEW_RECIPE_LEARNED: never register what the client rejects
-- (RED on c0ed9cd: the event is never considered)
-- ════════════════════════════════════════════════════════════════════
unknownEvents = { NEW_RECIPE_LEARNED = true }
Rec._enabled = false
local okEn, enErr = pcall(Rec.Enable, Rec)
check(okEn, "Recipes:Enable with NEW_RECIPE_LEARNED invalid: " .. tostring(enErr))
check(Rec._error == nil, "invalid NEW_RECIPE_LEARNED leaves no module error")
check(Rec._events and Rec._events.NEW_RECIPE_LEARNED == "invalid event",
  "NEW_RECIPE_LEARNED recorded as 'invalid event' (got " .. tostring(Rec._events and Rec._events.NEW_RECIPE_LEARNED) .. ")")
check(Rec._events and Rec._events.TRADE_SKILL_SHOW == true,
  "TRADE_SKILL_SHOW still registered (regression)")
-- the frame carrying this Enable must NOT have it in its event table
local wiredLearned = false
for i = #frames, 1, -1 do
  local f = frames[i]
  if type(f.scripts.OnEvent) == "function" and f.events.TRADE_SKILL_SHOW == true then
    wiredLearned = (f.events.NEW_RECIPE_LEARNED == true)
    break
  end
end
check(not wiredLearned, "NEW_RECIPE_LEARNED NOT registered on the event frame")

-- ════════════════════════════════════════════════════════════════════
-- NEW_RECIPE_LEARNED valid: rescan when Alchemy is open, pending flag
-- otherwise, flush on the next open
-- ════════════════════════════════════════════════════════════════════
unknownEvents = {}
Rec._enabled = false
okEn, enErr = pcall(Rec.Enable, Rec)
check(okEn, "Recipes:Enable with NEW_RECIPE_LEARNED valid: " .. tostring(enErr))
check(Rec._events and Rec._events.NEW_RECIPE_LEARNED == true,
  "valid NEW_RECIPE_LEARNED is registered")
check(Rec._error == nil, "no error from learning-event registration")

-- (a) Alchemy open → immediate rescan
addRecipe(105, "Solid Extract of Will", { 2447 })
api.prof = "Alchemy"
callsBefore = api.scanCalls
fire("NEW_RECIPE_LEARNED")
check(api.scanCalls == callsBefore + 1,
  "learned event with Alchemy open → immediate rescan (scanCalls=" .. api.scanCalls .. ")")
check(mapHas(2447, "Solid Extract of Will"),
  "immediate rescan picked up the learned recipe")
check(Rec._pendingRescan == false or Rec._pendingRescan == nil,
  "no stale pending flag after an immediate rescan")

-- (b) Alchemy closed → pending flag, no scan, no write
addRecipe(106, "Mystery Extract", { 3371 })
api.prof = nil
callsBefore = api.scanCalls
fire("NEW_RECIPE_LEARNED")
check(api.scanCalls == callsBefore,
  "learned event with window closed → NO scan (scanCalls=" .. api.scanCalls .. ")")
check(Rec._pendingRescan == true, "pending flag set while the window is closed")
check(not mapHas(3371, "Mystery Extract"),
  "closed-window learn wrote nothing")

-- (c) next open rescans and the new recipe lands
api.prof = "Alchemy"
fire("TRADE_SKILL_SHOW")
check(api.scanCalls == callsBefore + 1, "next Alchemy open runs the flush scan")
check(Rec._pendingRescan == false, "pending flag cleared by the flush scan")
check(mapHas(3371, "Mystery Extract"), "the learned recipe appears on the next open")
unknownEvents = {}

-- ════════════════════════════════════════════════════════════════════
-- State 4: "last scan found no reagents" + the real (truncated) error
-- from Recipes._diag on the panel AND from the button
-- ════════════════════════════════════════════════════════════════════
local bigErr = "schematic surface mismatch on this client: " .. string.rep("x", 120)
C_TradeSkillUI = {
  GetAllRecipeIDs = function()
    api.scanCalls = api.scanCalls + 1
    return { 201, 202, 203 }
  end,
  -- named, reagent-LESS: forces recipesRead>0 with a zero-reagent gate
  GetRecipeInfo = function(id) return { name = "Recipe " .. tostring(id) } end,
  GetRecipeSchematic = function()
    error(bigErr)
  end,
  GetChildProfessionInfo = function() return { skillLineName = "Alchemy" } end,
}
freshDB()
api.prof = "Alchemy"
fire("TRADE_SKILL_SHOW")
check(api.scanCalls > 0, "zero-reagent scan attempt ran")
check(not scannedSet(), "zero-reagents scan did NOT set alchemyScanned")
check(Rec._diag and Rec._diag.gated == "no-reagents",
  "zero-reagents scan recorded gated='no-reagents'")
check(type(Rec._diag and Rec._diag.error) == "string" and #(Rec._diag.error) > 100,
  "the recorded error is the long real string")

openPanel()
local lineNoReag = fsText(panelFsStatus)
check(lineNoReag == "last scan found no reagents",
  "panel state: 'last scan found no reagents' (got " .. tostring(lineNoReag) .. ")")
local errLine = fsText(panelFsError)
check(type(errLine) == "string" and errLine:sub(1, 12) == "last error: ",
  "panel error line present (got " .. tostring(errLine) .. ")")
check(type(errLine) == "string" and errLine:find("schematic surface mismatch", 1, true) ~= nil,
  "panel error line carries the real _diag error string")
if type(errLine) == "string" then
  check(#errLine < #bigErr, "panel error line is truncated (panel=" .. #errLine .. " raw=" .. #bigErr .. ")")
  check(errLine:find("...", 1, true) ~= nil, "truncation marked with '...'")
end
check(panelFsError and panelFsError.shown == true, "error line is visible")

if type(savedClick) == "function" then
  clearChat()
  pcall(savedClick)
  local clickedLine = chatLineContaining("schematic surface mismatch")
  check(clickedLine ~= nil, "button (open window, failed scan) prints the real error")
  check(type(clickedLine) == "string" and #clickedLine < #bigErr,
    "button error line is truncated too")
  check(not chatContains("scanned successfully"),
    "button does NOT claim a successful scan it did not get")
end

-- ════════════════════════════════════════════════════════════════════
-- State 5 (t_4ab7c230): the client answers NO availability at all. The herb
-- tooltip draws no Alchemy line; the options panel carries the one short
-- reason — and hides it again on a client that CAN answer.
-- ════════════════════════════════════════════════════════════════════
C_TradeSkillUI = {
  GetAllRecipeIDs = function() return { 301 } end,
  GetRecipeInfo = function(id)
    return { name = "Mystery Elixir " .. tostring(id), reagents = { { itemID = 2450 } } }
  end,
  GetChildProfessionInfo = function() return { skillLineName = "Alchemy" } end,
}
freshDB()
api.prof = "Alchemy"
fire("TRADE_SKILL_SHOW")
check(scannedSet(), "no-availability client: scan completed")
check(NodeTrailDB.recipes.alchemyFilterable == false,
  "no-availability client: nothing filterable")
check(NodeTrailDB.recipes.alchemyAvailability == "none",
  "no-availability client: availability recorded as none")

openPanel()
check(panelFsNote ~= nil, "panel has the hidden-list note line")
local noteText = fsText(panelFsNote)
check(type(noteText) == "string" and noteText:find("alchemy uses hidden", 1, true) ~= nil,
  "panel note says the alchemy uses are hidden (got " .. tostring(noteText) .. ")")
check(type(noteText) == "string" and noteText:find("recipe-availability API", 1, true) ~= nil,
  "panel note names the client API this version lacks")
check(type(noteText) == "string" and noteText:find("GetCraftableCount", 1, true) ~= nil,
  "panel note names GetCraftableCount")
check(panelFsNote.shown == true, "panel note is visible when the list is hidden")

-- Same saved recipes, a client that CAN answer: the note must disappear.
C_TradeSkillUI.IsRecipeProfessionLearned = function() return true end
fire("TRADE_SKILL_SHOW")
check(NodeTrailDB.recipes.alchemyFilterable == true,
  "filterable client: the gate is recorded")
openPanel()
check(fsText(panelFsNote) == "" and panelFsNote.shown == false,
  "panel note is hidden when the client answers availability")

-- ════════════════════════════════════════════════════════════════════
if failed > 0 then
  os.exit(1)
else
  print("options_spec: ok")
end

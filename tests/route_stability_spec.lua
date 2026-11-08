-- route_stability_spec.lua — t_57550700
--
-- Mightie, gathering south of Crossroads: "while i gather south of crossroads
-- another line as started to fill in?" — a second line on the world map, with
-- no reload. `NodeTrailDB.route.autoRefresh` defaulted to TRUE, so every pick
-- moved a debounced re-plan of the WHOLE zone route. A route that re-plans while
-- it is being followed cannot be followed.
--
-- What he asked for was "automated ... at least on /reloads": restore the route
-- on login, do not re-solve it on every herb. This spec drives the real files
-- through the real paths — Config, Data/Recorder, Data/Density, Route/Cluster,
-- Route/Build, Route/Auto, Core, UI/PathGeom, UI/LineDraw, UI/MapOverlay — and
-- asserts:
--
--   A. the persisted default is OFF, and a `true` written by the build that
--      shipped it as a default is migrated off exactly once;
--   B. gathering N herbs leaves the drawn route BYTE-IDENTICAL (same painted
--      dot count, same painted bbox) and prints exactly one short notice —
--      which is never printed while a loot window is open;
--   C. a /reload (same SavedVariables, fresh package) still restores the route
--      with no command at all, with the debounce off;
--   D. /nt autorefresh on rebuilds at once, re-arms the debounce, and a shrink
--      re-plan hides EVERY surplus object: `hidden` equals the drop in painted
--      dots, the pool holds exactly two objects per painted dot, `replans=`
--      increments, and `stale=false`;
--   E. `stale=true` is what the diag says when the pool ever holds more than
--      two objects per painted dot — the tripwire, not a flag that never fires.
--
-- The client modelled here is the live one: a canvas the dots are anchored in,
-- a texture sized only by two corner anchors, no Frame:CreateLine.
--
-- RED on 5ecc88f: autoRefresh defaults to true (no migration, no notice, no
-- /nt autorefresh), the surplus objects are hidden but kept (a one-way pool
-- ratchet), `hidden` counts objects instead of the drop in painted dots, and
-- `stale` prints the capacity flag, which reads false through all of it.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

-- ── chat capture ─────────────────────────────────────────────────────
local chat = {}
local function clearChat()
  for i = #chat, 1, -1 do chat[i] = nil end
end
local function chatText()
  return table.concat(chat, "\n")
end
local function chatCount(needle)
  local n, from = 0, 1
  local text = chatText()
  while true do
    local at = text:find(needle, from, true)
    if not at then break end
    n, from = n + 1, at + #needle
  end
  return n
end

local function clearGlobals()
  _G.CreateFrame = nil
  _G.WorldMapFrame = nil
  _G.Minimap = nil
  _G_CLEANUP_DONE = true
end

local clock, wall, wallText = 1000, 1762600000, "12:00:00"
GetTime = function() return clock end
time = function() return wall end
date = function() return wallText end
GetSpellInfo = function() return nil end
ReloadUI = function() end
StaticPopupDialogs = {}
StaticPopup_Show = function() end
function CopyTable(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = CopyTable(v) end
  return out
end

SlashCmdList = {}
DEFAULT_CHAT_FRAME = {
  AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end,
}

-- ── the client model ────────────────────────────────────────────────────
local CANVAS_W, CANVAS_H = 1002, 668
local CANVAS_SCALE = 0.696
local frames = {}

local function makeRegion(frame, kind)
  local r = { kind = kind, parent = frame, shown = false, points = {}, w = 0, h = 0 }
  function r:SetParent(p) self.parent = p end
  function r:GetParent() return self.parent end
  function r:ClearAllPoints() self.points = {} end
  function r:SetPoint(point, rel, relPoint, x, y)
    self.points[#self.points + 1] = { point, rel, relPoint, x, y }
    if #self.points >= 2 then
      local a, b = self.points[1], self.points[2]
      self.w = math.abs((b[4] or 0) - (a[4] or 0))
      self.h = math.abs((b[5] or 0) - (a[5] or 0))
    end
  end
  function r:GetNumPoints() return #self.points end
  function r:GetPoint(i)
    local p = self.points[i]
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
  end
  function r:GetWidth() return self.w or 0 end
  function r:GetHeight() return self.h or 0 end
  function r:GetObjectType() return self.kind == "line" and "Line" or "Texture" end
  function r:SetTexture(path) self.texture = path end
  function r:SetColorTexture(cr, cg, cb, ca) self.color = { cr, cg, cb, ca } end
  function r:SetVertexColor(cr, cg, cb, ca) self.vertex = { cr, cg, cb, ca } end
  function r:SetDrawLayer(layer, sub) self.layer, self.sublevel = layer, sub end
  function r:SetBlendMode() end
  function r:SetTexCoord() end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:IsShown() return self.shown end
  function r:IsVisible() return self.shown end
  -- No SetWidth/SetHeight/SetRotation: this client sizes a texture from two
  -- corner anchors only, which is why the dot chain is the primitive.
  return r
end

local function makeFrame(name, parent)
  local f = makeRegion(nil, "frame")
  f.name = name
  f.children = {}
  f.level = 0
  f.strata = "MEDIUM"
  f.shown = true
  f.w, f.h = 0, 0
  function f:SetParent(p) self.parent = p end
  function f:GetParent() return self.parent end
  function f:GetName() return self.name end
  function f:GetFrameLevel() return self.level end
  function f:SetFrameLevel(l) self.level = l end
  function f:GetFrameStrata() return self.strata end
  function f:SetFrameStrata(s) self.strata = s end
  function f:GetScale() return 1 end
  function f:GetWidth() return self.w end
  function f:GetHeight() return self.h end
  function f:GetLeft() return self.left end
  function f:GetTop() return self.top end
  function f:GetChildren() return self.children end
  function f:GetChildCount() return #self.children end
  function f:SetAllPoints(rel)
    local r = rel or self.parent
    if r and r.GetWidth then self.w, self.h = r:GetWidth(), r:GetHeight() end
  end
  function f:SetScript(n, fn) self.scripts = self.scripts or {}; self.scripts[n] = fn end
  function f:GetScript(n) return (self.scripts or {})[n] end
  function f:HookScript(n, fn)
    self.hooks = self.hooks or {}
    self.hooks[n] = self.hooks[n] or {}
    table.insert(self.hooks[n], fn)
  end
  function f:RegisterEvent() end
  function f:EnableMouse() end
  function f:EnableMouseWheel() end
  function f:SetMouseClickEnabled() end
  function f:EnableMouseMotion() end
  function f:SetPassThroughButtons() end
  f.clips = true
  function f:SetClipsChildren(v) self.clips = v and true or false end
  function f:DoesClipChildren() return self.clips end
  function f:CreateTexture()
    local t = makeRegion(self, "texture")
    table.insert(self.children, t)
    return t
  end
  if parent then table.insert(parent.children, f) end
  frames[#frames + 1] = f
  return f
end

_G.CreateFrame = function(kind, name, parent) return makeFrame(name, parent) end

local mapID = 1413
local FILES = {
  "locale/enUS.lua",
  "Config.lua",
  "UI/PathGeom.lua",
  "UI/LineDraw.lua",
  "UI/MapOverlay.lua",
  "UI/MinimapPath.lua",
  "Data/GM2.lua",
  "Data/ItemNames.lua",
  "Data/Recorder.lua",
  "Data/Density.lua",
  "Route/Cluster.lua",
  "Route/Build.lua",
  "Route/Auto.lua",
  "Core.lua",
}

--- Twelve picks in two tight clusters: the same shape Data/Density.lua groups
--- into anchors, with fewer dots than a whole-zone sweep so the numbers stay
--- readable in a failure message.
local function seedPicks()
  local list = {}
  for i = 1, 6 do
    list[#list + 1] = { x = 0.300 + i * 0.004, y = 0.300 + i * 0.004, t = wall, items = {} }
  end
  for i = 1, 6 do
    list[#list + 1] = { x = 0.400 + i * 0.004, y = 0.380 + i * 0.004, t = wall, items = {} }
  end
  return { herbs = { schema = 1, total = #list, maps = { [mapID] = list } } }
end

local function boot(saved)
  NodeTrailDB = saved
  frames = {}
  clearChat()
  local uiParent = makeFrame("UIParent", nil)
  uiParent.w, uiParent.h = 1920, 1080
  local worldMapFrame = makeFrame("WorldMapFrame", uiParent)
  worldMapFrame.w, worldMapFrame.h = CANVAS_W, CANVAS_H
  worldMapFrame.level = 2
  _G.WorldMapFrame = worldMapFrame
  local canvas = makeFrame(nil, worldMapFrame)
  canvas.w, canvas.h = CANVAS_W, CANVAS_H
  canvas.level = 3
  canvas.left, canvas.top = 0, 0
  function worldMapFrame:GetCanvas() return canvas end
  function worldMapFrame:GetMapID() return mapID end
  function worldMapFrame:GetCanvasScale() return CANVAS_SCALE end
  _G.GetCurrentMapAreaID = function() return mapID end
  _G.C_Minimap = { GetViewRadius = function() return 233.333 end }
  _G.C_Map = {
    GetBestMapForUnit = function() return mapID end,
    GetPlayerMapPosition = function()
      return { GetXY = function() return 0.5, 0.5 end }
    end,
  }
  _G.GetCVar = function() return nil end
  _G.GetPlayerFacing = function() return 0 end

  local pkg = { modState = { NodeTrail = true } }
  pkg.IsModuleEnabled = function(n) return pkg.modState[n] end
  pkg.RegisterModule = function(name, def) pkg.registered = def end
  for _, f in ipairs(FILES) do
    local chunk, err = loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. f)
    assert(chunk, (f .. ": " .. tostring(err)))
    chunk("MightiePack", pkg)
  end
  local ns = pkg.NodeTrail
  ns.Enable()
  return {
    ns = ns,
    M = ns.MapOverlay,
    canvas = canvas,
    worldMapFrame = worldMapFrame,
    diag = function()
      local out = {}
      local previous = _G.DEFAULT_CHAT_FRAME
      _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) out[#out + 1] = tostring(m) end }
      ns.MapOverlay:Diag()
      _G.DEFAULT_CHAT_FRAME = previous
      return table.concat(out, "\n")
    end,
  }
end

local function controllerFrame()
  for i = #frames, 1, -1 do
    if frames[i].name == "MightiePackNodeTrailRouteAuto" then return frames[i] end
  end
  return nil
end

local function lineStartingWith(text, prefix)
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local body = line:gsub("^NodeTrail mapdiag: ", "")
    if body:sub(1, #prefix) == prefix then return body end
  end
  return nil
end

--- The value of `name=` on a diag line, as a string.
local function fieldOf(line, name)
  if type(line) ~= "string" then return nil end
  return line:match(name .. "=(%S+)")
end

local function paintedObjects(drawer)
  local shown = 0
  for i = 1, (drawer.poolHigh or 0) do
    local o = drawer.pool[i]
    if o and o.shown then shown = shown + 1 end
  end
  return shown
end

-- ═══ A. ON by default, and a re-plan needs a TRANCHE OF GATHERS ══════════════
-- The saved database here is what an older build wrote: a route intent with no
-- auto-refresh keys at all. It must come up with the shipped defaults — on, and
-- five gathers — not with "one re-plan per herb".
local legacy = seedPicks()
legacy.route = { active = true, mapID = mapID, startedAt = wall - 60 }
local A = boot(legacy)
check(A.ns.activeRoute ~= nil, "A: the saved route still restores")
check(NodeTrailDB.route.autoRefresh == true,
  "A: auto-refresh is ON by default (Mightie: \"doesnt need to come off by default\")")
check(NodeTrailDB.route.autoRefreshPicks == 5,
  "A: five gathers make a re-plan due (got " .. tostring(NodeTrailDB.route.autoRefreshPicks) .. ")")
check(A.ns.IsAutoRefreshRoute() == true, "A: the live setting reads on")
check(A.ns.RouteAuto.state.rebuilds == 1,
  "A: the restore is ONE rebuild — not a session of them")

-- A player who turned it off keeps it off.
NodeTrailDB.route.autoRefresh = false
A.ns.GetRouteDB()
check(NodeTrailDB.route.autoRefresh == false,
  "A: an explicit off on disk is respected")

-- A database with no route table at all gets the shipped defaults.
local A2 = boot(seedPicks())
check(NodeTrailDB.route and NodeTrailDB.route.autoRefresh == true,
  "A: a fresh database defaults auto-refresh to on")
check(NodeTrailDB.route and NodeTrailDB.route.autoRefreshPicks == 5,
  "A: ...and the tranche to five gathers")

-- The tranche is clamped: 1 would be "one re-plan per herb" again.
if type(A2.ns.SetAutoRefreshPicks) ~= "function" then
  check(false, "A: NodeTrail exposes SetAutoRefreshPicks")
else
  check(A2.ns.SetAutoRefreshPicks(1) == 2,
    "A: a one-pick tranche is clamped to two (got " .. tostring(A2.ns.SetAutoRefreshPicks(1)) .. ")")
  check(A2.ns.SetAutoRefreshPicks(999) == 100, "A: and an absurd tranche is clamped down")
  check(A2.ns.SetAutoRefreshPicks(5) == 5, "A: a sane tranche is kept as given")
end

-- ═══ B. gathering leaves the drawn route alone, and says so once ═════════════
local B = boot(seedPicks())
B.ns.GetRouteDB().active = true
B.ns.GetRouteDB().mapID = mapID
B.ns.GetRouteDB().startedAt = wall
B.ns.GetRouteDB().autoRefresh = false
pcall(B.ns.RouteAuto.OnEnable, B.ns.RouteAuto)
check(B.ns.activeRoute ~= nil, "B: a route is drawn to gather against")
local firstDiag = B.diag()
local firstPool = lineStartingWith(firstDiag, "dots pool:")
local firstBox = lineStartingWith(firstDiag, "dots box:")
local firstDots = tonumber(fieldOf(firstPool, "painted")) or 0
check(firstDots > 4, "B: the drawn route has real dots (painted=" .. tostring(firstDots) .. ")")
check(firstBox ~= nil, "B: the diag measures where the painted dots land (got " .. tostring(firstBox) .. ")")
local rebuildsB = B.ns.RouteAuto.state.rebuilds

-- A loot window is up when a gather lands: the notice must not be printed then.
_G.LootFrame = { IsShown = function() return true end }
local cf = controllerFrame()
check(cf ~= nil and type(cf.scripts.OnUpdate) == "function", "B: the controller frame exists")
clock = clock + 5
for i = 1, 3 do
  B.ns.RecordHerb(mapID, 0.5 + i * 0.001, 0.5 + i * 0.001, {})
  if cf and cf.scripts.OnUpdate then cf.scripts.OnUpdate(cf, 0.1) end
end
check(chatCount("/nt reload") == 0,
  "B: no notice while the loot window is open (got: " .. chatText():gsub("\n", " | ") .. ")")
check(B.ns.RouteAuto.state.pendingPicks == 3,
  "B: the three picks are counted while the debounce is off (got "
    .. tostring(B.ns.RouteAuto.state.pendingPicks) .. ")")

-- The window closes; the next frame prints ONE line and never again.
_G.LootFrame = { IsShown = function() return false end }
if cf and cf.scripts.OnUpdate then cf.scripts.OnUpdate(cf, 0.1) end
check(chatCount("3 new picks since this route was built") == 1,
  "B: one short notice, naming how many picks are waiting (got: "
    .. chatText():gsub("\n", " | ") .. ")")
check(chatCount("/nt reload") == 1, "B: the notice says what to do about it")
for i = 1, 4 do
  clock = clock + 1
  B.ns.RecordHerb(mapID, 0.52 + i * 0.001, 0.5, {})
  if cf and cf.scripts.OnUpdate then cf.scripts.OnUpdate(cf, 0.1) end
end
check(chatCount("since this route was built") == 1,
  "B: the notice is printed ONCE per route, not once per pick (got "
    .. chatCount("since this route was built") .. ")")

-- ...and the route on the map did not move: same dot count, same bbox.
local secondDiag = B.diag()
local secondPool = lineStartingWith(secondDiag, "dots pool:")
local secondBox = lineStartingWith(secondDiag, "dots box:")
check(B.ns.RouteAuto.state.rebuilds == rebuildsB,
  "B: gathering rebuilt nothing (rebuilds " .. tostring(B.ns.RouteAuto.state.rebuilds)
    .. " vs " .. tostring(rebuildsB) .. ")")
check(fieldOf(secondPool, "painted") == fieldOf(firstPool, "painted"),
  "B: the same number of dots is painted after 7 picks (before=" .. tostring(fieldOf(firstPool, "painted"))
    .. " after=" .. tostring(fieldOf(secondPool, "painted")) .. ")")
check(fieldOf(secondPool, "planned") == fieldOf(firstPool, "planned"),
  "B: and the same number was planned")
check(secondBox == firstBox,
  "B: the painted bbox is byte-identical (before: " .. tostring(firstBox)
    .. " after: " .. tostring(secondBox) .. ")")
check(fieldOf(secondPool, "replans") == fieldOf(firstPool, "replans"),
  "B: no re-plan happened (replans before=" .. tostring(fieldOf(firstPool, "replans"))
    .. " after=" .. tostring(fieldOf(secondPool, "replans")) .. ")")

-- ═══ C. /reload still restores the route, with no command ═══════════════════
-- Same SavedVariables, fresh package: what a /reload does. The debounce is OFF
-- in that database and the route must still come back.
check(NodeTrailDB.route.autoRefresh == false, "C: the saved setting is off going into the reload")
local C = boot(NodeTrailDB)
check(C.ns.activeRoute ~= nil, "C: the route is restored after a reload with no command")
check(chatText():find("route restored", 1, true) ~= nil,
  "C: and it says so (got: " .. chatText():gsub("\n", " | ") .. ")")
local cDiag = C.diag()
local cPool = lineStartingWith(cDiag, "dots pool:")
check(tonumber(fieldOf(cPool, "painted")) > 4,
  "C: the restored route paints a real plan (painted=" .. tostring(fieldOf(cPool, "painted")) .. ")")
check(tonumber(fieldOf(cPool, "painted")) == tonumber(fieldOf(cPool, "planned")),
  "C: painted == planned on the restored plan (got " .. tostring(cPool) .. ")")

-- ═══ D. the switch: a tranche re-plans ONCE, and a shrink leaves nothing ════
-- The commands are driven through the real dispatcher, on the restored client.
clearChat()
check(type(SlashCmdList.NODETRAIL) == "function", "D: the real /nt dispatcher is registered")
local rstate = C.ns.RouteAuto.state
local rebuildsD = rstate.rebuilds

-- ── D1. switching it on is not permission to re-plan ───────────────────────
local okCmd, errCmd = pcall(SlashCmdList.NODETRAIL, "autorefresh on")
check(okCmd, "D: /nt autorefresh on does not error: " .. tostring(errCmd))
check(NodeTrailDB.route.autoRefresh == true, "D: it persists on")
check(rstate.rebuilds == rebuildsD,
  "D: turning it on does NOT re-plan by itself — the counter decides (rebuilds "
    .. tostring(rstate.rebuilds - rebuildsD) .. ")")
check(chatText():find("one re-plan every 5 gathers", 1, true) ~= nil,
  "D: it says what the trigger is (got: " .. chatText():gsub("\n", " | ") .. ")")
clearChat()
pcall(SlashCmdList.NODETRAIL, "status")
check(chatText():find("0 of 5 picks since the last plan", 1, true) ~= nil,
  "D: /nt status prints the pending count (got: " .. chatText():gsub("\n", " | ") .. ")")

-- ── D2. four gathers arm nothing: one short of the tranche ─────────────────
rstate.lastRebuildAt = wall - 60
for i = 1, 4 do
  wall = wall + 2
  clock = clock + 2
  C.ns.RecordHerb(mapID, 0.40 + i * 0.002, 0.42 + i * 0.002, {})
end
check(rstate.pendingPicks == 4, "D: the four picks are counted (got "
  .. tostring(rstate.pendingPicks) .. ")")
check(rstate.dueAt == nil, "D: four gathers arm nothing (dueAt=" .. tostring(rstate.dueAt) .. ")")
check(rstate.rebuilds == rebuildsD, "D: and nothing rebuilt")
clearChat()
pcall(SlashCmdList.NODETRAIL, "status")
check(chatText():find("4 of 5 picks since the last plan", 1, true) ~= nil,
  "D: status says 4 of 5 (got: " .. chatText():gsub("\n", " | ") .. ")")

-- ── D3. the fifth gather arms ONE window, and it re-plans once ─────────────
wall = wall + 40          -- past the 30-second floor since the last plan
local replansBefore = tonumber(((C.M.drawer or {}).lastApplied or {}).planReplans) or 0
clock = clock + 2
C.ns.RecordHerb(mapID, 0.47, 0.47, {})
check(rstate.dueAt ~= nil, "D: the fifth gather arms the debounce")
local cfD = controllerFrame()
clock = rstate.dueAt or clock
if cfD and cfD.scripts.OnUpdate then cfD.scripts.OnUpdate(cfD, 0.1) end
check(rstate.rebuilds == rebuildsD + 1,
  "D: five gathers produced exactly ONE re-plan (got "
    .. tostring(rstate.rebuilds - rebuildsD) .. ")")
check((rstate.lastTrigger or "") == "pick", "D: the automatic trigger reads pick")
check(rstate.pendingPicks == 0, "D: the plan now includes every pick (pending="
  .. tostring(rstate.pendingPicks) .. ")")
local dApplied = (C.M.drawer or {}).lastApplied or {}
check((tonumber(dApplied.planReplans) or 0) > replansBefore,
  "D: the drawn plan changed and `replans` counted it (before="
    .. tostring(replansBefore) .. " after=" .. tostring(dApplied.planReplans) .. ")")
local replansAfterPick = tonumber(dApplied.planReplans) or 0

-- ── D4. the next tranche starts from zero: four gathers, then the fifth ───
local rebuildsD4 = rstate.rebuilds
for i = 1, 4 do
  wall = wall + 5
  clock = clock + 5
  C.ns.RecordHerb(mapID, 0.44 + i * 0.002, 0.46, {})
end
check(rstate.dueAt == nil, "D: the next tranche needs five gathers, not one")
check(rstate.rebuilds == rebuildsD4, "D: nothing rebuilt on four")
wall = wall + 40
clock = clock + 5
C.ns.RecordHerb(mapID, 0.455, 0.46, {})
check(rstate.dueAt ~= nil, "D: the fifth of the tranche arms it")
clock = rstate.dueAt or clock
if cfD and cfD.scripts.OnUpdate then cfD.scripts.OnUpdate(cfD, 0.1) end
check(rstate.rebuilds == rebuildsD4 + 1,
  "D: and it re-plans once (got " .. tostring(rstate.rebuilds - rebuildsD4) .. ")")

-- ── D5. a loot window and combat each hold the plan still ──────────────────
local rebuildsD5 = rstate.rebuilds
rstate.lastRebuildAt = wall - 60
_G.LootFrame = { IsShown = function() return true end }
for i = 1, 5 do
  wall = wall + 1
  C.ns.RecordHerb(mapID, 0.45, 0.45 + i * 0.001, {})
end
check(rstate.dueAt ~= nil, "D: the tranche is due with a loot window open")
clock = rstate.dueAt or clock
if cfD and cfD.scripts.OnUpdate then cfD.scripts.OnUpdate(cfD, 0.1) end
check(rstate.rebuilds == rebuildsD5, "D: but nothing re-planned under a loot window")
check(tostring(rstate.lastHold or ""):find("loot", 1, true) ~= nil,
  "D: and the reason says so (lastHold=" .. tostring(rstate.lastHold) .. ")")
_G.LootFrame = { IsShown = function() return false end }
clock = rstate.dueAt or clock
if cfD and cfD.scripts.OnUpdate then cfD.scripts.OnUpdate(cfD, 0.1) end
check(rstate.rebuilds == rebuildsD5 + 1,
  "D: it catches up as soon as the window closes (rebuilds +"
    .. tostring(rstate.rebuilds - rebuildsD5) .. ")")

local rebuildsD6 = rstate.rebuilds
rstate.lastRebuildAt = wall - 60
_G.UnitAffectingCombat = function() return true end
for i = 1, 5 do
  wall = wall + 1
  C.ns.RecordHerb(mapID, 0.46, 0.46 + i * 0.001, {})
end
clock = rstate.dueAt or clock
if cfD and cfD.scripts.OnUpdate then cfD.scripts.OnUpdate(cfD, 0.1) end
check(rstate.rebuilds == rebuildsD6, "D: nothing re-planned in combat")
check(tostring(rstate.lastHold or ""):find("combat", 1, true) ~= nil,
  "D: and the reason says so (lastHold=" .. tostring(rstate.lastHold) .. ")")
_G.UnitAffectingCombat = function() return false end
clock = rstate.dueAt or clock
if cfD and cfD.scripts.OnUpdate then cfD.scripts.OnUpdate(cfD, 0.1) end
check(rstate.rebuilds == rebuildsD6 + 1, "D: combat ends and it catches up")

-- ── D6. the 30-second floor is a floor, whatever the tranche is ───────────
rstate.lastRebuildAt = wall - 20
rstate.pendingPicks = 50
if type(C.ns.RouteAuto.Gate) ~= "function" then
  check(false, "D: the controller exposes its gate")
else
  local whyFloor = C.ns.RouteAuto:Gate(wall)
  check(type(whyFloor) == "string" and whyFloor:find("20s", 1, true) ~= nil,
    "D: 20 seconds after a plan the gate refuses it (got " .. tostring(whyFloor) .. ")")
end
rstate.pendingPicks = 0
rstate.dueAt = nil

-- ── D7. /nt autorefresh <picks> sets the tranche, and status prints it ────
clearChat()
local okGap = pcall(SlashCmdList.NODETRAIL, "autorefresh 3")
check(okGap, "D: /nt autorefresh 3 does not error")
check(NodeTrailDB.route.autoRefreshPicks == 3,
  "D: the tranche persisted (got " .. tostring(NodeTrailDB.route.autoRefreshPicks) .. ")")
check(NodeTrailDB.route.autoRefresh == true,
  "D: setting the tranche does not silently flip the switch")
clearChat()
pcall(SlashCmdList.NODETRAIL, "status")
check(chatText():find("every 3 gathers", 1, true) ~= nil,
  "D: status prints the new tranche (got: " .. chatText():gsub("\n", " | ") .. ")")
if type(C.ns.SetAutoRefreshPicks) == "function" then C.ns.SetAutoRefreshPicks(5) end

-- ── D8. a SHRINK re-plan leaves no dot of the old geometry behind ──────────
-- The same drawer is asked to draw a much shorter plan. Every dot of the old
-- geometry must be gone, and the diag must account for each one.
local before = (C.M.drawer or {}).lastApplied or {}
local beforePainted = tonumber(before.paintedDots) or 0
check(beforePainted > 20, "D: the long plan is on screen first (painted=" .. tostring(beforePainted) .. ")")
C.M:SetRoute({ mapID = mapID, path = {
  { x = 0.30, y = 0.30 }, { x = 0.31, y = 0.305 }, { x = 0.32, y = 0.31 },
} })
local after = (C.M.drawer or {}).lastApplied or {}
local afterPainted = tonumber(after.paintedDots) or 0
local drop = beforePainted - afterPainted
check(afterPainted > 0 and drop > 0,
  "D: the shorter plan paints fewer dots (before=" .. tostring(beforePainted)
    .. " after=" .. tostring(afterPainted) .. ")")
check(tonumber(after.hiddenDots) == drop,
  "D: `hidden` is the DROP in painted dots, not an object count (hidden="
    .. tostring(after.hiddenDots) .. " drop=" .. tostring(drop) .. ")")
check(tonumber(after.prevPainted) == beforePainted,
  "D: the draw records the plan it replaced (prevPainted=" .. tostring(after.prevPainted) .. ")")
check(tonumber(after.hiddenByHide) == 2 * drop,
  "D: every surplus object was hidden, two per dropped dot (hiddenObjects="
    .. tostring(after.hiddenByHide) .. " expected " .. tostring(2 * drop) .. ")")
check((C.M.drawer.poolHigh or 0) == 2 * afterPainted,
  "D: the pool holds exactly two objects per painted dot (highest="
    .. tostring(C.M.drawer.poolHigh) .. " painted=" .. tostring(afterPainted) .. ")")
check(paintedObjects(C.M.drawer) == 2 * afterPainted,
  "D: nothing from the old geometry is still shown (shown="
    .. tostring(paintedObjects(C.M.drawer)) .. " expected " .. tostring(2 * afterPainted) .. ")")
check((tonumber(after.planReplans) or 0) > replansAfterPick,
  "D: `replans` counts the shrink too (replans=" .. tostring(after.planReplans) .. ")")
local dPool = lineStartingWith(C.diag(), "dots pool:")
check(fieldOf(dPool, "hidden") == tostring(drop),
  "D: the diag prints that drop as hidden= (got " .. tostring(dPool) .. ")")
check(fieldOf(dPool, "hiddenObjects") == tostring(2 * drop),
  "D: and the objects behind it as hiddenObjects= (got " .. tostring(dPool) .. ")")
check(fieldOf(dPool, "replans") == tostring(after.planReplans),
  "D: replans= on the diag is the drawer's re-plan count (got " .. tostring(dPool) .. ")")
check(fieldOf(dPool, "stale") == "false",
  "D: the pool is not stale after a shrink (got " .. tostring(dPool) .. ")")

-- A second shrink, from the now-short plan to an even shorter one: the ratchet
-- must not come back, and the numbers must stay exact.
local second = (C.M.drawer or {}).lastApplied or {}
C.M:SetRoute({ mapID = mapID, path = { { x = 0.30, y = 0.30 }, { x = 0.305, y = 0.30 } } })
local third = (C.M.drawer or {}).lastApplied or {}
check(tonumber(third.hiddenDots) == (tonumber(second.paintedDots) or 0) - (tonumber(third.paintedDots) or 0),
  "D: the second shrink accounts for its own drop (hidden=" .. tostring(third.hiddenDots) .. ")")
check((C.M.drawer.poolHigh or 0) == 2 * (tonumber(third.paintedDots) or 0),
  "D: and the pool still holds exactly its own plan (highest=" .. tostring(C.M.drawer.poolHigh) .. ")")

-- Growing again allocates only what the new plan needs.
C.M:SetRoute({ mapID = mapID, path = {
  { x = 0.30, y = 0.30 }, { x = 0.33, y = 0.33 }, { x = 0.36, y = 0.30 }, { x = 0.30, y = 0.30 },
} })
local grown = (C.M.drawer or {}).lastApplied or {}
check((C.M.drawer.poolHigh or 0) == 2 * (tonumber(grown.paintedDots) or 0),
  "D: a grow leaves the pool at two objects per painted dot again (highest="
    .. tostring(C.M.drawer.poolHigh) .. " painted=" .. tostring(grown.paintedDots) .. ")")

-- ── D9. switching it off drops any pending window: the line stays put ─────
rstate.lastRebuildAt = wall - 60
rstate.pendingPicks = 4     -- one short of the tranche
wall = wall + 1
C.ns.RecordHerb(mapID, 0.62, 0.62, {})
check(rstate.dueAt ~= nil, "D: a gather armed a window while it was on")
local okOff = pcall(SlashCmdList.NODETRAIL, "autorefresh off")
check(okOff, "D: /nt autorefresh off does not error")
check(NodeTrailDB.route.autoRefresh == false, "D: it persists off")
check(rstate.dueAt == nil, "D: switching it off drops the pending rebuild")

-- ═══ E. the stale tripwire fires when the pool holds more than the plan ═════
-- The live run that started this card reported `highest=908` for a plan of 480.
-- Reproduce that shape by hand: the diag must say stale=true, not false.
local drawer = C.M.drawer
local paintedNow = tonumber(((drawer.lastApplied or {}).paintedDots)) or 0
drawer.poolHigh = paintedNow * 4
local tripDiag = C.diag()
local tripPool = lineStartingWith(tripDiag, "dots pool:")
check(fieldOf(tripPool, "stale") == "true",
  "E: highest > 2*painted reads stale=true (got " .. tostring(tripPool) .. ")")
drawer.poolHigh = paintedNow * 2
check(fieldOf(lineStartingWith(C.diag(), "dots pool:"), "stale") == "false",
  "E: and reads false again once the pool matches the plan")

-- ═══ F. the command is documented ═══════════════════════════════════════════
clearChat()
pcall(SlashCmdList.NODETRAIL, "help")
check(chatText():find("/nt autorefresh", 1, true) ~= nil,
  "F: /nt help documents the command (got: " .. chatText():gsub("\n", " | ") .. ")")
clearChat()
local okBad = pcall(SlashCmdList.NODETRAIL, "autorefresh maybe")
check(okBad, "F: an unknown argument does not error")
check(chatText():find("/nt autorefresh [on|off|<picks>]", 1, true) ~= nil,
  "F: it prints the usage instead of guessing (got: " .. chatText():gsub("\n", " | ") .. ")")

if failed > 0 then
  io.stderr:write(("route_stability_spec: %d FAIL(s)\n"):format(failed))
  os.exit(1)
end
print("route_stability_spec: ok")

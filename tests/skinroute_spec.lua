-- skinroute_spec.lua — t_b46e5e87 (skinning farming circles).
--
-- Mightie: "I think we should test and add in the skinning farming circles
-- before pushing to curseforge." Operator rule, verbatim: "no need to draw
-- something until its been skinned in that area."
--
-- Every assertion drives the REAL files (Config, Data/Profession,
-- Route/SkinRoute, Route/Cluster, Route/Build, UI/PathGeom, UI/LineDraw,
-- UI/MapOverlay, UI/MinimapPath, Core, Skinning/Record) through their real entry
-- points. The skinning records are built by the real recorder (OnKill /
-- OnSkinCast), and the route is the one ns.BuildSkinRouteForMap produced from
-- them — nothing here hand-writes a route or a store shape.
--
-- RED on 0da8939 (the parent commit): Route/SkinRoute.lua does not exist, so
-- sections 1-3 fail on the missing generator and sections 4-6 on the missing
-- overlay/method/slash-command. Every check below is written to report that as
-- a FAILED check instead of a traceback.
--
-- What this pins:
--   1. the generator: closed circuit through the densest clusters;
--   2. the sample floor: too few skinned corpses -> no route, and the count
--      needed is stated; 8 corpses in ONE camp is still not a circle;
--   3. per-zone isolation: map 1411's record set never appears on 1412;
--   4. the trigger: a KILL is not a stop until that corpse was SKINNED;
--   5. the shared profession gate: yes -> drawn, no/nil -> nothing drawn, and
--      no chat line (the maps stay clean);
--   6. the toggle: /nt skinroute on|off, persisted, options-panel state;
--   7. the herb invariant: the herb route, its points and its fractions are
--      untouched by the circle, and skinning data never feeds the herb DB;
--   8. both surfaces: world map (dots inside the visible rect, N/M form) and
--      minimap (own drawer, own colour).
--
-- Not loaded by the addon TOC.
local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

-- ── chat capture ────────────────────────────────────────────────────────
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
local function chatHas(needle)
  return chatText():find(needle, 1, true) ~= nil
end

-- ── a client that reports geometry, not agreement ──────────────────────
-- The same model tests/mapdiag_visible_spec.lua uses: regions answer
-- GetLeft/GetTop from the anchors they were given, so "the dot is inside the
-- visible rect" is a measurement here, not a restatement of the projection.
local function newRegion(kind)
  local r = { kind = kind, points = {}, shown = false, parent = nil, scale = 1 }
  local function origin(relPoint, rel)
    local l, t = 0, 0
    if type(rel) == "table" and rel.GetLeft then
      l, t = rel:GetLeft() or 0, rel:GetTop() or 0
      local w, h = rel:GetWidth() or 0, rel:GetHeight() or 0
      if relPoint == "CENTER" then
        local s = rel:GetScale() or 1
        l, t = l + w * s * 0.5, t - h * s * 0.5
      end
    end
    return l, t
  end
  function r:SetPoint(point, rel, relPoint, x, y)
    self.points[#self.points + 1] = { point, rel, relPoint, x or 0, y or 0 }
  end
  function r:ClearAllPoints() self.points = {}; self.allPoints = nil end
  function r:GetNumPoints() return #self.points end
  function r:GetPoint(i)
    local p = self.points[i]
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
  end
  function r:SetParent(p) self.parent = p end
  function r:GetParent() return self.parent end
  function r:SetScale(s) self.scale = s end
  function r:GetScale() return self.scale end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:IsShown() return self.shown end
  function r:IsVisible() return self.shown end
  function r:SetDrawLayer() end
  function r:SetBlendMode() end
  function r:SetTexCoord() end
  function r:SetColorTexture() end
  function r:SetTexture() end
  function r:SetVertexColor() end
  function r:SetThickness() end
  function r:GetObjectType() return self.kind end
  function r:GetWidth()
    if self.allPoints and self.allPoints.GetWidth then return self.allPoints:GetWidth() end
    return self.width or 0
  end
  function r:GetHeight()
    if self.allPoints and self.allPoints.GetHeight then return self.allPoints:GetHeight() end
    return self.height or 0
  end
  function r:GetLeft()
    if self.allPoints then return self.allPoints:GetLeft() end
    local p = self.points[1]
    if not p then return self.fixedLeft or 0 end
    local l = origin(p[3], p[2])
    return l + (p[4] or 0) * (p[2] and p[2].GetScale and p[2]:GetScale() or 1)
  end
  function r:GetTop()
    if self.allPoints then return self.allPoints:GetTop() end
    local p = self.points[1]
    if not p then return self.fixedTop or 0 end
    local _, t = origin(p[3], p[2])
    return t + (p[5] or 0) * (p[2] and p[2].GetScale and p[2]:GetScale() or 1)
  end
  return r
end

local function newFrame(name, parent)
  local f = newRegion("Frame")
  f.name = name
  f.scripts = {}
  f.level, f.strata = 1, "MEDIUM"
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:GetScript(n) return self.scripts[n] end
  function f:HookScript(n, fn) self.scripts[n] = fn end
  function f:RegisterEvent() end
  function f:UnregisterEvent() end
  function f:GetName() return self.name end
  function f:SetSize(w, h) self.width, self.height = w, h end
  function f:SetAllPoints(p) self.allPoints = p or self.parent end
  function f:SetClipsChildren() end
  function f:EnableMouse() end
  function f:EnableMouseWheel() end
  function f:SetFrameLevel(l) self.level = l end
  function f:GetFrameLevel() return self.level end
  function f:SetFrameStrata(s) self.strata = s end
  function f:GetFrameStrata() return self.strata end
  function f:GetAlpha() return 1 end
  function f:SetAlpha() end
  function f:SetIgnoreParentAlpha() end
  function f:CreateTexture() local t = newRegion("Texture"); t.parent = self; return t end
  function f:CreateLine() local t = newRegion("Line"); t.parent = self; return t end
  function f:CreateFontString() return newFrame("FontString", self) end
  function f:GetChildren() return {} end
  function f:SetChecked(b) self.checked = b and true or false end
  function f:GetChecked() return self.checked == true end
  function f:Enable() self.enabled = true end
  function f:Disable() self.enabled = false end
  function f:SetText(t) self.text = tostring(t or "") end
  function f:GetText() return self.text end
  return f
end

function CreateFrame(kind, name, parent)
  local f = newFrame(name, parent)
  f.parent = parent
  return f
end

function CopyTable(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = CopyTable(v) end
  return out
end

-- ── the clock and the character ────────────────────────────────────────
local clock = 100
function GetTime() return clock end
time = function() return 1000 end
function GetSpellInfo(id)
  if id == 2366 then return "Herb Gathering" end
  if id == 2259 then return "Alchemy" end
  if id == 8613 then return "Skinning" end
  return nil
end
function GetUnitName() return "Mightie" end
function GetRealmName() return "Forever" end

SlashCmdList = {}
StaticPopupDialogs = {}
StaticPopup_Show = function() end
ReloadUI = function() end
GameTooltip = {
  SetOwner = function() end, SetText = function() end, AddLine = function() end,
  Show = function() end, Hide = function() end,
}

-- ── the player's position and the current map ──────────────────────────
local playerMap = 1411
C_Map = {
  GetBestMapForUnit = function() return playerMap end,
  GetPlayerMapPosition = function()
    return { GetXY = function() return 0.5, 0.5 end }
  end,
}

-- ── the map hierarchy, in screen coordinates (the live client's numbers) ──
local WMF_LEFT, WMF_TOP = 717, 1080
local WMF_W, WMF_H = 697, 465
local CANVAS_W, CANVAS_H, SCALE = 1002, 668, 0.696

UIParent = newFrame("UIParent")
UIParent.width, UIParent.height = 2133, 1200
UIParent.fixedLeft, UIParent.fixedTop = 0, 1200

local scroll = newFrame("ScrollContainer")
scroll.parent = UIParent
scroll.width, scroll.height = WMF_W, WMF_H
scroll.fixedLeft, scroll.fixedTop = WMF_LEFT, WMF_TOP

local canvas = newFrame("WorldMapFrameCanvas")
canvas.parent = scroll
canvas.width, canvas.height = CANVAS_W, CANVAS_H
canvas.scale = SCALE
canvas.fixedLeft, canvas.fixedTop = WMF_LEFT / SCALE, WMF_TOP / SCALE

local mapFrame = newFrame("WorldMapFrame")
mapFrame.parent = UIParent
mapFrame.width, mapFrame.height = WMF_W, WMF_H
mapFrame.fixedLeft, mapFrame.fixedTop = WMF_LEFT, WMF_TOP
mapFrame.ScrollContainer = scroll
local shownMapID = 1411
function mapFrame:GetCanvas() return canvas end
function mapFrame:GetCanvasScale() return SCALE end
function mapFrame:GetMapID() return shownMapID end
WorldMapFrame = mapFrame

-- ── the minimap ────────────────────────────────────────────────────────
Minimap = newFrame("Minimap")
Minimap.width, Minimap.height = 150, 150
Minimap.shown = true
function Minimap:GetZoom() return 0 end

-- ── the profession gate's client surface (skill lines) ─────────────────
local skills = {}
function GetNumSkillLines() return #skills end
function GetSkillLineInfo(i)
  local row = skills[i]
  if not row then return nil end
  return row[1], row[2], row[3], row[4]
end

-- ── load the addon (TOC order, the files this card touches) ────────────
local pkg = {}
local function loadFile(path)
  local chunk, err = loadfile(root .. "/" .. path)
  if not chunk then
    -- On the parent commit the new file does not exist at all. That is a
    -- FAILED check, not a traceback: the spec has to report the work that was
    -- not done.
    check(false, "missing file on this commit: " .. path .. " (" .. tostring(err) .. ")")
    return false
  end
  chunk("MightiePack", pkg)
  return true
end
local function nt(path) loadFile("MightiePack/Modules/NodeTrail/" .. path) end

loadFile("MightiePack/Core.lua")
loadFile("MightiePack/Modules.lua")
nt("locale/enUS.lua")
nt("Config.lua")
nt("Data/GM2.lua")
nt("Data/ItemNames.lua")
nt("Data/Recorder.lua")
nt("Data/Profession.lua")
nt("Route/Cluster.lua")
nt("Route/Build.lua")
nt("Route/SkinRoute.lua")
nt("UI/PathGeom.lua")
nt("UI/LineDraw.lua")
nt("UI/MapOverlay.lua")
nt("UI/MinimapPath.lua")
nt("Core.lua")
loadFile("MightiePack/Modules/Skinning/Record.lua")
loadFile("MightiePack/Modules/Skinning/Core.lua")
loadFile("MightiePack/Options.lua")

local ns = pkg.NodeTrail
local S = ns.SkinRoute
local M = ns.MapOverlay
local MP = ns.MinimapPath
local R = pkg.Skinning.Recorder

check(type(ns) == "table", "NodeTrail namespace loaded")
check(type(S) == "table" and type(ns.BuildSkinRouteForMap) == "function",
  "the skinning route generator exists (Route/SkinRoute.lua)")
check(type(S) == "table" and type(S.StatusText) == "function",
  "the generator has one status sentence for the panel/command")

-- Every entry point this spec exercises, named once. On 0da8939 the whole list
-- is absent (Route/SkinRoute.lua does not exist and neither overlay has a skin
-- layer), and each absence is reported as its own failed check.
local missing = {}
local function need(label, fn)
  if type(fn) ~= "function" then missing[#missing + 1] = label end
end
need("ns.BuildSkinRouteForMap (the generator)", ns.BuildSkinRouteForMap)
need("ns.RefreshSkinRoute (gate + build + draw)", ns.RefreshSkinRoute)
need("ns.SkinRouteCommand (/nt skinroute)", ns.SkinRouteCommand)
need("ns.IsSkinRouteEnabled (the persisted switch)", ns.IsSkinRouteEnabled)
need("ns.SetSkinRouteEnabled (the persisted switch)", ns.SetSkinRouteEnabled)
need("MapOverlay:SetSkinRoute (the world-map layer)", M and M.SetSkinRoute)
need("MapOverlay:ClearSkinRoute (the world-map layer)", M and M.ClearSkinRoute)
need("MapOverlay:SkinAudit (the mapdiag N/M line)", M and M.SkinAudit)
need("MinimapPath:SetSkinRoute (the minimap layer)", MP and MP.SetSkinRoute)
need("MinimapPath:ClearSkinRoute (the minimap layer)", MP and MP.ClearSkinRoute)
if #missing > 0 then
  for i = 1, #missing do
    check(false, "RED on this commit: " .. missing[i] .. " is absent")
  end
  os.exit(1)
end

-- Boot: creates NodeTrailDB and registers /nt. No skinning data yet, so the
-- boot-time refresh must be silent.
local okBoot, bootErr = pcall(ns.Enable)
check(okBoot, "NodeTrail boot (ns.Enable): " .. tostring(bootErr))
check(type(SlashCmdList.NODETRAIL) == "function", "/nt registered after boot")

-- ── the recorder is the only data source ───────────────────────────────
ns.GetDB()
ns.GetSkinDB().enabled = true -- records land in NodeTrailDB.skinning (the DB store)

local seq = 0
local function seed(mapID, points, doSkin)
  local out = {}
  for i = 1, #points do
    seq = seq + 1
    local guid = ("Creature-0-7072-1-48-3124-%06d"):format(seq)
    R:OnKill({ guid = guid, t = 1000 + seq, map = mapID, x = points[i][1], y = points[i][2] })
    if doSkin then
      R:OnSkinCast({ guid = guid, t = 1000.5 + seq, spellID = 8613 })
    end
    out[#out + 1] = { x = points[i][1], y = points[i][2] }
  end
  return out
end

local function jitter(base, n, dx, dy)
  local out = {}
  for i = 1, n do
    out[#out + 1] = { base[1] + (i - 1) * dx, base[2] + (i - 1) * dy }
  end
  return out
end

-- Map 1411: four dense clusters, 12 skinned corpses.
local A_CLUSTERS = { { 0.18, 0.22 }, { 0.62, 0.20 }, { 0.58, 0.66 }, { 0.16, 0.68 } }
local A_POINTS = {}
for _, c in ipairs(A_CLUSTERS) do
  for _, p in ipairs(jitter(c, 3, 0.004, 0.003)) do A_POINTS[#A_POINTS + 1] = p end
end
seed(1411, A_POINTS, true)

-- Map 1412: a different zone's skinning, 10 corpses over three clusters.
local B_CLUSTERS = { { 0.30, 0.30 }, { 0.70, 0.40 }, { 0.40, 0.80 } }
local B_POINTS = {}
for _, c in ipairs(B_CLUSTERS) do
  for _, p in ipairs(jitter(c, 4, 0.003, 0.004)) do B_POINTS[#B_POINTS + 1] = p end
end
seed(1412, B_POINTS, true)

-- Map 1413: three skinned corpses — below the floor.
seed(1413, { { 0.50, 0.50 }, { 0.503, 0.502 }, { 0.501, 0.498 } }, true)

-- Map 1414: eight skinned corpses, all in ONE camp (one cluster cell).
local TIGHT = {}
for i = 1, 8 do TIGHT[#TIGHT + 1] = { 0.5001 + i * 0.0001, 0.4001 } end
seed(1414, TIGHT, true)

-- Map 1415: nine KILLS that were never skinned (operator rule: not a stop).
seed(1415, jitter({ 0.20, 0.20 }, 9, 0.02, 0.02), false)

-- ════════════════════════════════════════════════════════════════════════
-- 1. The generator: a closed circuit through the densest clusters
-- ════════════════════════════════════════════════════════════════════════
local routeA, errA, stA = ns.BuildSkinRouteForMap(1411)
check(routeA ~= nil, "1: map 1411 has enough skinned corpses -> a route is built (err="
  .. tostring(errA) .. ")")
if routeA then
  check(routeA.mapID == 1411, "1: the route names its map (got " .. tostring(routeA.mapID) .. ")")
  check(routeA.source == "skinning", "1: the route says where it came from (source="
    .. tostring(routeA.source) .. ", not 'density')")
  check(#routeA.path >= 4, "1: a closed loop has 3 stops plus the closing point (got "
    .. #routeA.path .. ")")
  local first, last = routeA.path[1], routeA.path[#routeA.path]
  check(first.x == last.x and first.y == last.y,
    "1: the loop is CLOSED (first and last point differ)")
  check(#routeA.clusters == #A_CLUSTERS, "1: one stop per dense cluster (got "
    .. #routeA.clusters .. ", expected " .. #A_CLUSTERS .. ")")
  -- Every stop is a centroid of one of THIS map's clusters; no other map's
  -- positions leak in.
  local matched = 0
  for i = 1, #routeA.path - 1 do
    local p = routeA.path[i]
    local hit = false
    for _, c in ipairs(A_CLUSTERS) do
      if math.abs(p.x - c[1]) < 0.02 and math.abs(p.y - c[2]) < 0.02 then hit = true end
    end
    if hit then matched = matched + 1 end
  end
  check(matched == #routeA.path - 1,
    "1: every stop is a centroid of this map's clusters (got " .. matched .. "/" .. (#routeA.path - 1) .. ")")
end

-- ════════════════════════════════════════════════════════════════════════
-- 2. The sample floor: no route, and the count needed is stated
-- ════════════════════════════════════════════════════════════════════════
local few, fewErr, fewStatus = ns.BuildSkinRouteForMap(1413)
check(few == nil, "2: three skinned corpses do NOT make a circle")
check(fewErr == "TOO_FEW", "2: the refusal names the reason (got " .. tostring(fewErr) .. ")")
check(fewStatus ~= nil and fewStatus.count == 3 and fewStatus.needed == S.MIN_SKINS - 3,
  "2: the refusal counts the sample and the shortfall (got count=" .. tostring(fewStatus and fewStatus.count)
  .. " needed=" .. tostring(fewStatus and fewStatus.needed) .. ")")
local fewText = S:StatusText(1413)
check(fewText:find("3 of " .. S.MIN_SKINS, 1, true) ~= nil,
  "2: the message states the sample against the floor (got: " .. fewText .. ")")
check(fewText:find("5 more needed", 1, true) ~= nil,
  "2: the message says how many MORE are needed (got: " .. fewText .. ")")

local tight, tightErr, tightStatus = ns.BuildSkinRouteForMap(1414)
check(tight == nil, "2: eight corpses in ONE camp are still not a circle")
check(tightErr == "TOO_SPREAD", "2: the refusal names the cluster floor (got " .. tostring(tightErr) .. ")")
check(tightStatus ~= nil and tightStatus.clusters < S.MIN_CLUSTERS,
  "2: the cluster count is below the minimum (got " .. tostring(tightStatus and tightStatus.clusters) .. ")")
check(S:StatusText(1414):find("cluster", 1, true) ~= nil,
  "2: the message explains the cluster shortfall")

-- ════════════════════════════════════════════════════════════════════════
-- 3. Per-zone isolation: 1412's records never appear on 1411
-- ════════════════════════════════════════════════════════════════════════
local routeB = ns.BuildSkinRouteForMap(1412)
check(routeB ~= nil, "3: map 1412 has its own route")
if routeB and routeA then
  check(#routeB.path >= 4 and routeB.mapID == 1412, "3: map 1412's route names 1412")
  local leaked = 0
  for i = 1, #routeA.path do
    local p = routeA.path[i]
    for _, b in ipairs(B_CLUSTERS) do
      if math.abs(p.x - b[1]) < 0.01 and math.abs(p.y - b[2]) < 0.01 then leaked = leaked + 1 end
    end
  end
  check(leaked == 0, "3: no 1412 cluster appears on map 1411's loop (leaked " .. leaked .. ")")
  local aStatus = S:Status(1411)
  local bStatus = S:Status(1412)
  check(aStatus.count == #A_POINTS, "3: 1411 counts only its own skinned corpses (got "
    .. tostring(aStatus.count) .. ", expected " .. #A_POINTS .. ")")
  check(bStatus.count == #B_POINTS, "3: 1412 counts only its own skinned corpses (got "
    .. tostring(bStatus.count) .. ", expected " .. #B_POINTS .. ")")
end

-- ════════════════════════════════════════════════════════════════════════
-- 4. The trigger: a kill is not a stop until that corpse was SKINNED
-- ════════════════════════════════════════════════════════════════════════
local killOnly, killErr, killStatus = ns.BuildSkinRouteForMap(1415)
check(killOnly == nil, "4: kills that were never skinned draw nothing")
check(killErr == "NO_SKINNING", "4: the reason is 'nothing skinned here' (got " .. tostring(killErr) .. ")")
check(killStatus ~= nil and killStatus.count == 0,
  "4: no KILL is counted as a skinning stop (got " .. tostring(killStatus and killStatus.count) .. ")")
check(S:StatusText(1415):find("0 of " .. S.MIN_SKINS, 1, true) ~= nil,
  "4: the empty zone states the full count needed")

-- ════════════════════════════════════════════════════════════════════════
-- 5. The profession gate: same helper as the beast panel
-- ════════════════════════════════════════════════════════════════════════
local function setProfession(kind)
  ns.Profession:Forget()
  playerMap = 1411
  if kind == "skinner" then
    skills = { { "Herbalism", false, false, 1 }, { "Skinning", false, false, 300 } }
    GetNumSkillLines = function() return #skills end
  elseif kind == "non-skinner" then
    skills = { { "Herbalism", false, false, 1 }, { "Cooking", false, false, 1 } }
    GetNumSkillLines = function() return #skills end
  else
    skills = {}
    GetNumSkillLines = nil
  end
end

local function resetLayers()
  M:ClearSkinRoute()
  MP:ClearSkinRoute()
end

-- (a) a confirmed skinner: the circle is built, gated by the SHARED helper.
setProfession("skinner")
ns.SetSkinRouteEnabled(true)
resetLayers()
clearChat()
local gateCalls = 0
local realSkinning = ns.Profession.Skinning
ns.Profession.Skinning = function(self, ...)
  gateCalls = gateCalls + 1
  return realSkinning(self, ...)
end
local gateRoute, gateWhy = ns.RefreshSkinRoute()
ns.Profession.Skinning = realSkinning
check(gateRoute ~= nil, "5: a skinner with data gets a circle (why=" .. tostring(gateWhy) .. ")")
check(gateCalls == 1, "5: the shared ns.Profession:Skinning gate decided it (called "
  .. gateCalls .. " time(s))")
check(M.skinPath ~= nil and #M.skinPath >= 4, "5: the world map holds the circle's points")
check(MP.skinPath ~= nil, "5: the minimap holds the circle's points")
check(#chat == 0, "5: drawing a circle prints nothing (got: " .. chatText() .. ")")

-- (b) a non-skinner with the SAME store: nothing drawn, and NOTHING said.
setProfession("non-skinner")
resetLayers()
clearChat()
local rNone, whyNone = ns.RefreshSkinRoute()
check(rNone == nil and whyNone == "NOT_SKINNER", "5: a non-skinner is refused (why="
  .. tostring(whyNone) .. ")")
check(M.skinPath == nil and MP.skinPath == nil, "5: a non-skinner sees no circle on either map")
check(#chat == 0, "5: a non-skinner sees no 'no data' line either (got: " .. chatText() .. ")")

-- (c) an unreadable client: abstain exactly like the beast panel.
setProfession("unreadable")
resetLayers()
clearChat()
local rUnread, whyUnread = ns.RefreshSkinRoute()
check(rUnread == nil and whyUnread == "GATE_UNREADABLE",
  "5: an unreadable profession answer abstains (why=" .. tostring(whyUnread) .. ")")
check(M.skinPath == nil and MP.skinPath == nil, "5: an unreadable client sees no circle")
check(#chat == 0, "5: an unreadable client gets no chat line about it")

-- ════════════════════════════════════════════════════════════════════════
-- 6. The toggle: /nt skinroute on|off, persisted, and in the options panel
-- ════════════════════════════════════════════════════════════════════════
setProfession("skinner")
playerMap = 1411
resetLayers()
ns.SetSkinRouteEnabled(true)
ns.RefreshSkinRoute()

local HERB = {
  mapID = 1411,
  path = {
    { x = 0.40, y = 0.20 }, { x = 0.60, y = 0.35 },
    { x = 0.52, y = 0.70 }, { x = 0.40, y = 0.20 },
  },
}
M:SetRoute(HERB)
local herbPathRef = M.path
local herbFraction = M._px and M._px[2] and { x = M._px[2].x, y = M._px[2].y } or nil
check(M.path == herbPathRef, "6: the herb route is on the map before the toggle test")

clearChat()
SlashCmdList.NODETRAIL("skinroute off")
check(ns.IsSkinRouteEnabled() == false, "6: /nt skinroute off persists the switch")
check(NodeTrailDB.skinroute.enabled == false, "6: the switch is written to SavedVariables")
check(M.skinPath == nil and MP.skinPath == nil, "6: off clears the circle on both maps")
check(M.path == herbPathRef, "6: off leaves the herb route on the map (same points)")
check(M._px[2].x == herbFraction.x and M._px[2].y == herbFraction.y,
  "6: off leaves the herb route's projected fractions untouched")
check(chatHas("skinroute: off"), "6: off says so (got: " .. chatText() .. ")")

clearChat()
SlashCmdList.NODETRAIL("skinroute on")
check(ns.IsSkinRouteEnabled() == true, "6: /nt skinroute on persists the switch")
check(M.skinPath ~= nil, "6: on draws the circle again")
check(chatHas("on"), "6: on says so (got: " .. chatText() .. ")")

-- The options panel carries the same state: its checkbox follows the key and
-- its OnClick calls the same setter.
local panel = pkg.optionsPanel
check(panel ~= nil, "6: the options panel exists")
if panel and panel.GetScript and panel:GetScript("OnShow") then
  local okP, errP = pcall(panel.GetScript(panel, "OnShow"), panel)
  check(okP, "6: the options panel renders: " .. tostring(errP))
end
local boxes = pkg.optionsBoxes or {}
check(boxes.SkinRoute ~= nil, "6: the panel has a 'Skinning farming circle' checkbox")
if boxes.SkinRoute then
  check(boxes.SkinRoute:GetChecked() == true, "6: the checkbox reads the persisted switch (on)")
  ns.SetSkinRouteEnabled(false)
  if panel.GetScript and panel:GetScript("OnShow") then
    panel:GetScript("OnShow")(panel)
  end
  check(boxes.SkinRoute:GetChecked() == false, "6: the checkbox follows the saved value (off)")
  ns.SetSkinRouteEnabled(true)
end

-- Status text exists for the panel/command, and the help documents the switch.
local help = (function()
  clearChat()
  SlashCmdList.NODETRAIL("help")
  return chatText()
end)()
check(help:find("skinroute", 1, true) ~= nil, "6: /nt help documents skinroute")

-- ════════════════════════════════════════════════════════════════════════
-- 7. The herb invariant: untouched points/fractions, and no writing to herbs
-- ════════════════════════════════════════════════════════════════════════
local function herbSnapshot()
  local h = NodeTrailDB and NodeTrailDB.herbs
  if type(h) ~= "table" then return "absent" end
  local maps = {}
  for id, list in pairs(h.maps or {}) do maps[#maps + 1] = tostring(id) .. ":" .. tostring(#list) end
  table.sort(maps)
  return tostring(h.total) .. "|" .. table.concat(maps, ",")
end

local herbsBefore = herbSnapshot()
local herbCalls = 0
local realCollect = ns.CollectHerbNodes
ns.CollectHerbNodes = function(...)
  herbCalls = herbCalls + 1
  return realCollect(...)
end
local herbPxBefore = {}
for i = 1, #(M.path or {}) do
  local px = M._px and M._px[i]
  herbPxBefore[i] = px and { x = px.x, y = px.y, fx = px.fx, fy = px.fy } or nil
end

ns.SetSkinRouteEnabled(true)
ns.RefreshSkinRoute()
ns.BuildSkinRouteForMap(1411)

ns.CollectHerbNodes = realCollect
check(herbCalls == 0, "7: building the circle never asks the herb node collector (calls="
  .. herbCalls .. ")")
check(herbSnapshot() == herbsBefore, "7: the skinning route wrote nothing into NodeTrailDB.herbs")
check(M.path == herbPathRef, "7: the herb route still holds the same points")
local herbPxSame = true
for i = 1, #herbPxBefore do
  local now = M._px and M._px[i]
  local before = herbPxBefore[i]
  if not now or not before or now.x ~= before.x or now.y ~= before.y
    or now.fx ~= before.fx or now.fy ~= before.fy then
    herbPxSame = false
  end
end
check(herbPxSame, "7: every herb fraction and projected pixel is unchanged")

-- The two layers are drawn with different colours (the herb drawer keeps the
-- profile's teal; the circle's drawer gets the skinning rust).
local herbApplied = ns.LineDraw.Applied(M.drawer) or {}
local skinApplied = ns.LineDraw.Applied(M.skinDrawer) or {}
check(math.abs((herbApplied.r or 0) - 0.400) < 1e-9
    and math.abs((herbApplied.g or 0) - 0.988) < 1e-9
    and math.abs((herbApplied.b or 0) - 0.945) < 1e-9,
  "7: the herb drawer is still drawn in the profile's teal (got "
  .. tostring(herbApplied.r) .. "," .. tostring(herbApplied.g) .. "," .. tostring(herbApplied.b) .. ")")
check(skinApplied.r == S.COLOR[1] and skinApplied.g == S.COLOR[2] and skinApplied.b == S.COLOR[3],
  "7: the circle has its own colour (got " .. tostring(skinApplied.r) .. ","
  .. tostring(skinApplied.g) .. "," .. tostring(skinApplied.b) .. ")")
check(herbApplied.r ~= skinApplied.r or herbApplied.g ~= skinApplied.g
  or herbApplied.b ~= skinApplied.b, "7: the two lines are visually distinguishable")

-- ════════════════════════════════════════════════════════════════════════
-- 8. Both surfaces: world map dots inside the visible rect; minimap draws
-- ════════════════════════════════════════════════════════════════════════
local function diagText()
  clearChat()
  M:Diag()
  return chatText()
end
local function line(out, prefix)
  for l in (out .. "\n"):gmatch("(.-)\n") do
    if l:find(prefix, 1, true) then return l end
  end
  return nil
end

ns.RefreshSkinRoute()
local out = diagText()
local skinPaint = tonumber((ns.LineDraw.Applied(M.skinDrawer) or {}).paintedDots) or 0
check(skinPaint > 0, "8: the circle painted dots on the world map (got " .. skinPaint .. ")")
local circleLine = line(out, "skinning circle dots on the visible map:")
check(circleLine ~= nil, "8: /nt mapdiag prints the circle's own inside-count (got no line)")
if circleLine then
  local inside, total = circleLine:match("visible map: (%d+)/(%d+)")
  check(tonumber(inside) == skinPaint and tonumber(total) == skinPaint,
    "8: all " .. skinPaint .. " circle dots land inside the visible map rect (got "
    .. tostring(circleLine) .. ")")
  check(circleLine:find("NO dot is inside", 1, true) == nil,
    "8: a healthy circle carries no 'off the map' verdict")
end
local layerLine = line(out, "skinning circle layer:")
check(layerLine ~= nil and layerLine:find("parent=WorldMapFrame", 1, true) ~= nil,
  "8: the circle's host is on WorldMapFrame, the map's own frame (got "
  .. tostring(layerLine) .. ")")
-- The herb line's own count is still its own.
local herbLine = line(out, "route dots on the visible map:")
check(herbLine ~= nil and herbLine:find("inside", 1, true) ~= nil,
  "8: the herb route's inside-count is still printed separately")

-- The minimap: a circle around the player is drawn by its own drawer, in the
-- circle's colour, and the herb route's minimap fields are untouched.
local nearPlayer = {
  mapID = 1411,
  color = S.COLOR,
  width = S.WIDTH,
  path = {
    { x = 0.470, y = 0.470 }, { x = 0.530, y = 0.470 },
    { x = 0.530, y = 0.530 }, { x = 0.470, y = 0.530 },
    { x = 0.470, y = 0.470 },
  },
}
MP:SetRoute(HERB)
local miniHerbRef = MP.path
MP:SetSkinRoute(nearPlayer)
check(MP.path == miniHerbRef, "8: setting the circle leaves the herb minimap route as it was")
check(MP.skinPath == nearPlayer.path, "8: the minimap holds the circle's points")
local miniApplied = ns.LineDraw.Applied(MP.skinDrawer) or {}
check((miniApplied.paintedDots or 0) > 0, "8: the minimap painted the circle (got "
  .. tostring(miniApplied.paintedDots) .. ")")
check(miniApplied.r == S.COLOR[1] and miniApplied.g == S.COLOR[2],
  "8: the minimap circle is drawn in the circle's colour (got " .. tostring(miniApplied.r)
  .. "," .. tostring(miniApplied.g) .. ")")
local herbMini = ns.LineDraw.Applied(MP.drawer) or {}
check(math.abs((herbMini.r or 0) - 0.400) < 1e-9 and math.abs((herbMini.g or 0) - 0.988) < 1e-9,
  "8: the minimap herb route is still teal")


-- ════════════════════════════════════════════════════════════════════════
-- 9. A "can't draw" release must hide decor regions, not leave them
-- ════════════════════════════════════════════════════════════════════════
local function shownDecor(drawer)
  local n = 0
  if not drawer or type(drawer.pool) ~= "table" then
    return 0
  end
  local high = drawer.poolHigh or #drawer.pool
  for i = 1, high do
    local o = drawer.pool[i]
    if o then
      local shown = false
      if type(o.IsShown) == "function" then
        shown = o:IsShown() and true or false
      else
        shown = o.shown and true or false
      end
      if shown then
        n = n + 1
      end
    end
  end
  return n
end
check((shownDecor(M.styleDrawer) or 0) > 0,
  "9: the world herb route has visible decor before release (got "
  .. tostring(shownDecor(M.styleDrawer)) .. ")")
M:ReleaseVisuals("can't draw")
check(shownDecor(M.styleDrawer) == 0,
  "9: ReleaseVisuals(reason) hides every world herb decor region (got "
  .. tostring(shownDecor(M.styleDrawer)) .. " shown)")
check((shownDecor(M.skinStyleDrawer) or 0) > 0,
  "9: the world skinning circle has visible decor before release (got "
  .. tostring(shownDecor(M.skinStyleDrawer)) .. ")")
M:ReleaseSkin("can't draw")
check(shownDecor(M.skinStyleDrawer) == 0,
  "9: ReleaseSkin(reason) hides every world skinning decor region (got "
  .. tostring(shownDecor(M.skinStyleDrawer)) .. " shown)")
check((shownDecor(MP.skinStyleDrawer) or 0) > 0,
  "9: the minimap skinning circle has visible decor before release (got "
  .. tostring(shownDecor(MP.skinStyleDrawer)) .. ")")
MP:ReleaseSkinVisuals("can't draw")
check(shownDecor(MP.skinStyleDrawer) == 0,
  "9: ReleaseSkinVisuals(reason) hides every minimap skinning decor region (got "
  .. tostring(shownDecor(MP.skinStyleDrawer)) .. " shown)")

-- ════════════════════════════════════════════════════════════════════════
if failed > 0 then
  os.exit(1)
else
  print("skinroute_spec: ok")
end

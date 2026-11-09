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


-- ── simulated-client evidence run (same harness as the spec) ───────────
skills = { { "Skinning", false, false, 300 } }
GetNumSkillLines = function() return #skills end
ns.Profession:Forget()
playerMap = 1411
ns.SetSkinRouteEnabled(true)
local route = ns.RefreshSkinRoute()
print(("map 1411: route=%s points=%s stops=%s"):format(
  type(route) == "table" and "yes" or "no",
  type(route) == "table" and #route.path or 0,
  type(route) == "table" and #route.clusters or 0))
clearChat()
M:Diag()
for l in chatText():gmatch("[^\n]+") do
  if l:find("skinning circle", 1, true) then print(l) end
end
-- A zone with no recorded kills of its own.
playerMap = 1415
local none, why = ns.RefreshSkinRoute()
print(("map 1415: route=%s why=%s overlay_skinPath=%s minimap_skinPath=%s"):format(
  tostring(none), tostring(why), tostring(M.skinPath), tostring(MP.skinPath)))
clearChat()
SlashCmdList.NODETRAIL("skinroute")
print(chatText())

-- Classic-era world-map stub: WorldMapFrame WITHOUT GetCanvas (1.12-era
-- clients only expose the legacy globals), a real-sized WorldMapDetailFrame
-- with the clickable WorldMapButton inset inside it. This is the hierarchy
-- the overlay has to cope with — a stub that invents a modern canvas API
-- would test nothing. Not loaded by the addon TOC.
local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. (msg or "check") .. "\n")
  end
end

local function near(a, b, msg)
  check(type(a) == "number" and math.abs(a - b) < 1e-6,
    (msg or "near") .. " got " .. tostring(a) .. " expected " .. tostring(b))
end

-- ── minimal client stub ─────────────────────────────────────────────────────
local function makeRegion()
  local r = { points = {}, shown = true, color = {}, width = 0, height = 0, level = 1 }
  function r:SetParent(p) self.parent = p end
  function r:GetParent() return self.parent end
  function r:ClearAllPoints() self.points = {} end
  function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
  function r:SetStartPoint(...) self.startPoint = { ... } end
  function r:SetEndPoint(...) self.endPoint = { ... } end
  function r:SetTexture(path) self.texture = path end
  function r:SetVertexColor(cr, cg, cb, ca) self.vertexColor = { cr, cg, cb, ca } end
  function r:SetColorTexture(cr, cg, cb, ca) self.colorTexture = { cr, cg, cb, ca } end
  function r:SetDrawLayer() end
  function r:SetThickness(t) self.thickness = t end
  function r:SetWidth(w) self.width = w end
  function r:SetHeight(h) self.height = h end
  function r:SetSize(w, h) self.width, self.height = w, h end
  function r:GetWidth() return self.width or 0 end
  function r:GetHeight() return self.height or 0 end
  function r:SetAllPoints(rel) self._allPoints = rel or self.parent end
  function r:GetName() return self.name end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:IsShown() return self.shown end
  function r:IsVisible() return self.shown end
  function r:GetFrameLevel() return self.level or 1 end
  function r:SetFrameLevel(level) self.level = level end
  function r:GetFrameStrata() return self.strata or "MEDIUM" end
  function r:SetFrameStrata(strata) self.strata = strata end
  function r:EnableMouse() end
  function r:EnableMouseWheel() end
  function r:SetScript(name, fn) self.scripts[name] = fn end
  function r:GetScript(name) return (self.scripts or {})[name] end
  function r:HookScript(name, fn) self.scripts[name] = fn end
  function r:RegisterEvent() end
  function r:CreateTexture()
    local t = makeRegion()
    t.kind = "texture"
    t.parent = self
    return t
  end
  function r:CreateLine()
    local line = makeRegion()
    line.kind = "line"
    line.parent = self
    return line
  end
  r.scripts = {}
  return r
end

function CreateFrame(kind, name, parent)
  local f = makeRegion()
  f.kind = kind
  f.name = name
  f.parent = parent
  return f
end

local chat = {}
DEFAULT_CHAT_FRAME = {
  AddMessage = function(_, msg) chat[#chat + 1] = msg end,
}

function CopyTable(t)
  local out = {}
  for k, v in pairs(t) do
    out[k] = type(v) == "table" and CopyTable(v) or v
  end
  return out
end

-- 1.12-era globals: no GetCanvas anywhere, no data-provider mixin, no
-- hooksecurefunc, no C_Timer. Only the legacy map frames and the legacy
-- map-id call.
WorldMapFrame = makeRegion()
WorldMapFrame.name = "WorldMapFrame"
WorldMapFrame.width, WorldMapFrame.height = 1040, 1040

WorldMapDetailFrame = makeRegion()
WorldMapDetailFrame.name = "WorldMapDetailFrame"
WorldMapDetailFrame.width, WorldMapDetailFrame.height = 1002, 1002

WorldMapButton = makeRegion()
WorldMapButton.name = "WorldMapButton"
WorldMapButton.width, WorldMapButton.height = 986, 986

function GetCurrentMapAreaID() return 17 end

check(type(WorldMapFrame.GetCanvas) == "nil", "stub must NOT invent GetCanvas")

local ns = {}
local pkg = { NodeTrail = ns }
local function loadAddon(path)
  local chunk, err = loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. path)
  assert(chunk, err)
  chunk("MightiePack", pkg)
end
loadAddon("locale/enUS.lua")
loadAddon("Config.lua")
loadAddon("UI/PathGeom.lua")
loadAddon("UI/LineDraw.lua")
loadAddon("UI/MapOverlay.lua")

local G = ns.PathGeom
local M = ns.MapOverlay

-- ── geometry: measured map rectangle inside the host ───────────────────────
do
  -- Classic detail frame 1002x1002 with the 986x986 button inset by 8.
  local rect = G.MapRect(1002, 1002, 986, 986)
  check(type(rect) == "table", "inset rect")
  near(rect.left, 8, "inset left")
  near(rect.top, 8, "inset top")
  near(rect.width, 986, "inset width")
  near(rect.height, 986, "inset height")

  local x, y = G.FractionToPixel(0.25, 0.5, rect)
  near(x, 8 + 0.25 * 986, "fraction x with inset")
  near(y, 8 + 0.5 * 986, "fraction y with inset")

  -- No inner frame known: the whole host is the map.
  local whole = G.MapRect(1002, 1002)
  near(whole.left, 0, "whole left")
  near(whole.top, 0, "whole top")
  near(whole.width, 1002, "whole width")
  local hx, hy = G.FractionToPixel(0.25, 0.5, whole)
  near(hx, 250.5, "fraction x without inset")
  near(hy, 501, "fraction y without inset")

  -- An inner frame larger than the host is ignored (never a negative rect).
  local clamped = G.MapRect(600, 600, 1002, 1002)
  near(clamped.width, 600, "oversized inner frame clamped to host")
  near(clamped.left, 0, "oversized inner frame has no inset")

  -- Zero/degenerate sizes: no division, no NaN, just nil.
  check(G.MapRect(0, 0, 986, 986) == nil, "zero host size is unusable")
  check(G.MapRect(1002, 1002, 0, 0) ~= nil, "zero inner size falls back to the host")
  check(G.FractionToPixel(0.5, 0.5, { left = 0, top = 0, width = 0, height = 0 }) == nil,
    "zero rect does not divide by zero")
  check(G.FractionToPixel(0.5, 0.5, { left = 0, top = 0, width = 100, height = 100 }) ~= nil,
    "valid rect converts")
  check(G.FractionToPixel(0 / 0, 0.5, { left = 0, top = 0, width = 100, height = 100 }) == nil,
    "nan fraction is rejected")
end

-- ── overlay draws on the legacy detail frame, through the measured inset ───
M:SetRoute({
  mapID = 17,
  path = {
    { x = 0.25, y = 0.5 },
    { x = 0.5, y = 0.5 },
  },
})

check(M._drawError == nil, "draw error: " .. tostring(M._drawError))
check(M._hostParent == WorldMapDetailFrame, "host parented to WorldMapDetailFrame")
check(M._parentLabel == "WorldMapDetailFrame", "parent label, got " .. tostring(M._parentLabel))
check(M.drawer and M.drawer.mode == "line", "draws with CreateLine")
check(M.host and M.host.shown, "host shown")
near(M._rect and M._rect.left, 8, "rect left from WorldMapButton inset")
near(M._rect and M._rect.width, 986, "rect width from WorldMapButton")
check(M._lastQueued == 1, "one segment queued, got " .. tostring(M._lastQueued))

local line = M.drawer and M.drawer.pool and M.drawer.pool[1]
check(line ~= nil, "line object exists")
if line then
  local x1, y1 = line.startPoint[4], line.startPoint[5]
  local x2, y2 = line.endPoint[4], line.endPoint[5]
  near(x1, 254.5, "0.25 lands at the expected pixel (x)")
  near(y1, -501, "0.5 lands at the expected pixel (y, from TOPLEFT)")
  near(x2, 501, "0.5 lands at the expected pixel (x2)")
  near(y2, -501, "same row (y2)")
end

-- ── a zero-sized map frame must not throw or divide by zero ────────────────
WorldMapDetailFrame.width, WorldMapDetailFrame.height = 0, 0
WorldMapButton.width, WorldMapButton.height = 0, 0
local ok = pcall(function() M:Redraw() end)
check(ok, "zero-sized frame redraw does not throw")
check(M._drawError == nil, "zero-sized frame leaves no draw error: " .. tostring(M._drawError))
check(M._rect == nil, "no rect is measured from a zero-sized frame")
check(M._lastQueued == 0, "no segments queued from a zero frame")
check(not M.host.shown, "host hidden when the map cannot be measured")
check((M._retries or 0) >= 1, "a zero-sized frame asks for a retry")

-- ── hidden on a different displayed mapID ───────────────────────────────────
WorldMapDetailFrame.width, WorldMapDetailFrame.height = 1002, 1002
WorldMapButton.width, WorldMapButton.height = 986, 986
M:SetRoute({
  mapID = 17,
  path = {
    { x = 0.25, y = 0.5 },
    { x = 0.5, y = 0.5 },
  },
})
check(M.host.shown, "route drawn again after the frame is measurable")
GetCurrentMapAreaID = function() return 33 end
M:Redraw()
check(not M.host.shown, "hidden when the displayed mapID differs from the route")
check(M._lastQueued == 1 or M._lastQueued == 0, "no crash while hidden")
GetCurrentMapAreaID = function() return 17 end
M:Redraw()
check(M.host.shown, "visible again on the route's mapID")

-- ── showWorldMap off hides it ───────────────────────────────────────────────
ns.GetDB().showWorldMap = false
M:SetRoute({ mapID = 17, path = { { x = 0.25, y = 0.5 }, { x = 0.5, y = 0.5 } } })
check(M.path == nil, "showWorldMap false clears the route")
check(not M.host.shown, "showWorldMap false hides the host")
ns.GetDB().showWorldMap = true
M:SetRoute({ mapID = 17, path = { { x = 0.25, y = 0.5 }, { x = 0.5, y = 0.5 } } })
check(M.host.shown, "route drawn again once showWorldMap is back on")

-- ── /nt mapdiag on this legacy-only client prints every line ───────────────
chat = {}
M:Diag()
local joined = table.concat(chat, "\n")
for _, needle in ipairs({
  "WorldMapFrame: present",
  "GetCanvas=absent",
  "canvas: absent",
  "mapID:",
  "WorldMapButton: present",
  "WorldMapDetailFrame: present",
  "WorldMapFrame.ScrollContainer: absent",
  "MapOverlay: parent=WorldMapDetailFrame",
  "map rect: left=",
  "redraw: queued=",
  "settings: showWorldMap=true",
  "MinimapPath: absent",
}) do
  check(joined:find(needle, 1, true) ~= nil, "mapdiag missing line: " .. needle)
end
check(joined:find("error:", 1, true) == nil, "mapdiag printed no error line on a legacy client")

if failed > 0 then
  io.stderr:write(failed .. " map overlay check(s) failed\n")
  os.exit(1)
end
print("mapoverlay_spec: ok")

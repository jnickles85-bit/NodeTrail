-- t_c0a68ed2 rework round 2 — /nt mapdiag's summary lines must describe the
-- LAST redraw, and must name the NEXT candidate once the draw-order raise is
-- history. Two ways the old diag lied, both reproduced here on a realistic
-- client (real frame levels, 5-tuple GetPoint on every line region):
--
--   A. After the host has been raised above the art, the verdict kept saying
--      "DRAW ORDER — the host sat at level 13" forever, because EnsureHost
--      reset the host to canvas+10 on every redraw and `audit.raised` was
--      re-asserted. The geometry/colour/unknown verdicts were unreachable.
--      Now: `raisedNow` vs `raisedEarlier`, and a host that stays below the art
--      is reported as such instead of being hidden behind the old text.
--
--   B. `_redraw` reset `_lastQueued`/`_why` on entry but not `_px`/`_segLens`/
--      `_skipped`, so a redraw that returned early (wrong map open) printed
--      "redraw: queued=0" next to the PREVIOUS route's points, segments and
--      colour as if they were current. Now they are cleared on entry and the
--      diag says "not measured on the last redraw (<why>)".
--
-- Not loaded by the addon TOC.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. (msg or "check") .. "\n")
  end
end

-- ── client stub: frames with real levels/children, regions with 5-tuples ───
local function makeFrame(name, parent)
  local f = {
    name = name,
    parent = parent,
    children = {},
    level = 0,
    strata = "MEDIUM",
    shown = true,
    width = 0,
    height = 0,
    scripts = {},
    pool = {},
  }
  function f:GetName() return self.name end
  function f:GetParent() return self.parent end
  function f:SetParent(p) self.parent = p end
  function f:GetFrameLevel() return self.level end
  function f:SetFrameLevel(l) self.level = l end
  function f:GetFrameStrata() return self.strata end
  function f:SetFrameStrata(s) self.strata = s end
  function f:IsShown() return self.shown end
  function f:IsVisible() return self.shown end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:GetAlpha() return self.alpha or 1 end
  function f:GetWidth() return self.width end
  function f:GetHeight() return self.height end
  function f:SetWidth(w) self.width = w end
  function f:SetHeight(h) self.height = h end
  function f:SetSize(w, h) self.width, self.height = w, h end
  function f:GetChildren() return self.children end
  function f:ClearAllPoints() self.points = {} end
  function f:SetAllPoints(rel)
    self.allPoints = rel or self.parent
    if self.allPoints and self.allPoints.GetWidth then
      self.width = self.allPoints:GetWidth()
      self.height = self.allPoints:GetHeight()
    end
  end
  function f:SetPoint(...) self.points = { ... } end
  function f:GetPoint() return nil end
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:GetScript(n) return self.scripts[n] end
  function f:HookScript(n, fn)
    self.hooks = self.hooks or {}
    self.hooks[n] = self.hooks[n] or {}
    table.insert(self.hooks[n], fn)
  end
  function f:RegisterEvent() end
  function f:EnableMouse() end
  function f:EnableMouseWheel() end
  function f:CreateLine(_, layer)
    local line = {
      kind = "line",
      layer = layer,
      shown = false,
      level = self.level,
      thickness = 0,
      color = {},
    }
    function line:SetParent(p) self.parent = p end
    function line:SetStartPoint(p, rel, rp, x, y)
      self.start = { p, rel, rp, x, y }
    end
    function line:SetEndPoint(p, rel, rp, x, y)
      self.stop = { p, rel, rp, x, y }
    end
    function line:GetStartPoint()
      if not self.start then return nil end
      return self.start[1], self.start[2], self.start[3], self.start[4], self.start[5]
    end
    function line:GetEndPoint()
      if not self.stop then return nil end
      return self.stop[1], self.stop[2], self.stop[3], self.stop[4], self.stop[5]
    end
    function line:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function line:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
    function line:SetThickness(t) self.thickness = t end
    function line:GetThickness() return self.thickness end
    function line:GetAlpha() return self.color and self.color[4] or nil end
    function line:Hide() self.shown = false end
    function line:Show() self.shown = true end
    function line:IsShown() return self.shown end
    function line:ClearAllPoints() end
    table.insert(self.pool, line)
    return line
  end
  if parent then
    table.insert(parent.children, f)
  end
  return f
end

function CreateFrame(kind, name, parent)
  return makeFrame(name, parent)
end

function CopyTable(t)
  local out = {}
  for k, v in pairs(t) do
    out[k] = type(v) == "table" and CopyTable(v) or v
  end
  return out
end

local chat = {}
DEFAULT_CHAT_FRAME = {
  AddMessage = function(_, msg) chat[#chat + 1] = msg end,
}
SlashCmdList = {}

-- ── the client's map hierarchy (canvas art as a high-level sibling) ────────
local UIParent = makeFrame("UIParent", nil)
UIParent.width, UIParent.height = 1920, 1080
UIParent.level = 0

local displayedID = 1413
local WorldMapFrame = makeFrame("WorldMapFrame", UIParent)
WorldMapFrame.width, WorldMapFrame.height = 1002, 668
WorldMapFrame.level = 2
_G.WorldMapFrame = WorldMapFrame

local scroll = makeFrame("WorldMapScrollContainer", WorldMapFrame)
scroll.width, scroll.height = 1002, 668
scroll.level = 2

local canvas = makeFrame(nil, scroll)
canvas.width, canvas.height = 1002, 668
canvas.level = 3

local art = makeFrame("WorldMapDetailFrame", canvas)
art.width, art.height = 1002, 668
art.level = 40
_G.WorldMapDetailFrame = art

function WorldMapFrame:GetCanvas() return canvas end
function WorldMapFrame:GetMapID() return displayedID end
function WorldMapFrame:GetCanvasScale() return 1 end
WorldMapFrame.ScrollContainer = scroll

local pkg = {}
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

local ns = pkg.NodeTrail
local M = ns.MapOverlay

local function diag()
  chat = {}
  M:Diag()
  return table.concat(chat, "\n")
end

local function lineStartingWith(text, prefix)
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local body = line:gsub("^NodeTrail mapdiag: ", "")
    if body:sub(1, #prefix) == prefix then
      return body
    end
  end
  return nil
end

-- ═══ A. the raise is history, not a permanent verdict ═════════════════════
M:SetRoute({
  mapID = 1413,
  path = {
    { x = 0.720, y = 0.350 },
    { x = 0.450, y = 0.430 },
  },
})
check(M._drawError == nil, "A: draw error: " .. tostring(M._drawError))
check(M.host and M.host:GetFrameLevel() == 45,
  "A: the host was raised to 45 (got " .. tostring(M.host and M.host:GetFrameLevel()) .. ")")
check(M._zorder and M._zorder.raisedNow == true, "A: the first redraw raised the host")
local firstVerdict = lineStartingWith(diag(), "verdict:")
check(firstVerdict and firstVerdict:find("verdict: DRAW ORDER", 1, true) ~= nil,
  "A: the raising redraw names draw order (got " .. tostring(firstVerdict) .. ")")

M:Redraw()
M:Redraw()
check(M._zorder and M._zorder.raisedNow == false,
  "A: a later redraw does not raise again (the host was not reset to canvas+10)")
check(M._zorder and M._zorder.raisedEarlier == true, "A: the raise is kept as history")
check(M.host and M.host:GetFrameLevel() == 45,
  "A: the host level stays put across redraws (got "
    .. tostring(M.host and M.host:GetFrameLevel()) .. ")")

local settledVerdict = lineStartingWith(diag(), "verdict:")
check(settledVerdict and settledVerdict:find("verdict: DRAW ORDER", 1, true) == nil,
  "A: the verdict stops claiming draw order once the host is above the art (got "
    .. tostring(settledVerdict) .. ")")
check(settledVerdict and settledVerdict:find("no draw-order, colour or geometry cause found", 1, true) ~= nil,
  "A: the verdict falls through to the next candidate (got " .. tostring(settledVerdict) .. ")")
check(settledVerdict and settledVerdict:find("(draw order was raised earlier: 13 -> 45)", 1, true) ~= nil,
  "A: the earlier raise is carried as history in the verdict (got "
    .. tostring(settledVerdict) .. ")")

-- ═══ B. a host that could not be raised says so ══════════════════════════
-- Same client, but the frame exposes no SetFrameLevel (a real shape: some
-- frames in the UI are not settable) and the art moves higher. The verdict
-- must name draw order as STILL BROKEN, not as already fixed.
M.host.SetFrameLevel = nil
art.level = 60
M:Redraw()
check(M._drawError == nil, "B: draw error: " .. tostring(M._drawError))
check(M._zorder and M._zorder.stillBelow == true,
  "B: the audit records that the host is still below the art")
local belowVerdict = lineStartingWith(diag(), "verdict:")
check(belowVerdict and belowVerdict:find("DRAW ORDER (still below after the raise attempt)", 1, true) ~= nil,
  "B: the verdict names draw order as still unfixed (got " .. tostring(belowVerdict) .. ")")
check(belowVerdict and belowVerdict:find("this client exposes no SetFrameLevel", 1, true) ~= nil,
  "B: the verdict says why the raise could not happen (got " .. tostring(belowVerdict) .. ")")

-- ═══ C. measurements belong to the redraw that made them ═════════════════
-- Open another map: the next redraw returns early, and nothing from the old
-- route may be printed as if the last redraw measured it.
check(M._px ~= nil and M._segLens ~= nil, "C: the successful redraw measured points")
local stalePoints = lineStartingWith(diag(), "points:")
check(stalePoints and stalePoints:find("not measured", 1, true) == nil,
  "C: the measured redraw prints its own points (got " .. tostring(stalePoints) .. ")")

displayedID = 9999
M:Redraw()
check(M._drawError == nil, "C: draw error after the map switch: " .. tostring(M._drawError))
check(M._why == "the open map is 9999, the route is on 1413",
  "C: the early return records why (got " .. tostring(M._why) .. ")")
check(M._px == nil and M._segLens == nil,
  "C: the stale points/segments are cleared on entry to the next redraw")

local afterSwitch = diag()
local why = "the open map is 9999, the route is on 1413"
for _, prefix in ipairs({ "points: ", "segments: ", "colour: " }) do
  local text = lineStartingWith(afterSwitch, prefix)
  check(text ~= nil, "C: the diag prints a " .. prefix:gsub("%s+$", "") .. " line")
  check(text and text:find("not measured on the last redraw", 1, true) ~= nil,
    "C: " .. prefix .. "says it was not measured on the last redraw (got " .. tostring(text) .. ")")
  check(text and text:find(why, 1, true) ~= nil,
    "C: " .. prefix .. "names the reason (got " .. tostring(text) .. ")")
end
check(afterSwitch:find("points: 2 of 2 projected", 1, true) == nil,
  "C: the previous route's projected points are not printed as current")
check(afterSwitch:find("segments: queued=1 total=", 1, true) == nil,
  "C: the previous route's segment totals are not printed as current")
check(afterSwitch:find("colour applied by the last draw", 1, true) == nil,
  "C: the previous draw's colour is not printed as current")
local switchVerdict = lineStartingWith(afterSwitch, "verdict:")
check(switchVerdict and switchVerdict:find("the host is hidden", 1, true) ~= nil,
  "C: the verdict reports the hidden host (got " .. tostring(switchVerdict) .. ")")
check(afterSwitch:find("error:", 1, true) == nil, "C: the diag printed no error line")

-- ═══ D. a raise the client REFUSES is not reported as a raise ══════════════
-- A real client shape: SetFrameLevel exists, the pcall succeeds, and the frame
-- stays where it was. The audit used to record the ATTEMPT, so mapdiag printed
-- "RAISED from 45 to 45" / "it was raised to 45 on this redraw" while the same
-- block said "-> NOT above the art" — claiming the invisible-line state fixed.
displayedID = 1413
M.host.SetFrameLevel = function(self) return end -- present, silently ignored
art.level = 80
M:Redraw()
check(M._drawError == nil, "D: draw error: " .. tostring(M._drawError))
check(M.host:GetFrameLevel() == 45,
  "D: the client kept the frame at 45 (got " .. tostring(M.host:GetFrameLevel()) .. ")")
check(M._zorder and M._zorder.raisedNow == false,
  "D: a refused SetFrameLevel is not recorded as a raise")
check(M._zorder and M._zorder.stillBelow == true,
  "D: the audit records that the host is still below the art")
local refusedDiag = diag()
local refusedVerdict = lineStartingWith(refusedDiag, "verdict:")
check(refusedVerdict and refusedVerdict:find("DRAW ORDER (still below after the raise attempt)", 1, true) ~= nil,
  "D: the verdict reports draw order as still unfixed (got " .. tostring(refusedVerdict) .. ")")
check(refusedVerdict and refusedVerdict:find("the client did not accept a higher level", 1, true) ~= nil,
  "D: the verdict says the client refused the level (got " .. tostring(refusedVerdict) .. ")")
check(refusedVerdict and refusedVerdict:find("it was raised to", 1, true) == nil,
  "D: the verdict does not claim a raise that did not happen (got " .. tostring(refusedVerdict) .. ")")
check(refusedDiag:find("RAISED from 45 to 45", 1, true) == nil,
  "D: the z-order line does not print a raise from 45 to 45")
check(refusedDiag:find("raise attempted; the frame still reads level=45", 1, true) ~= nil,
  "D: the z-order line reports the MEASURED frame after the attempt")

-- ═══ E. a refused SetFrameStrata must not be reported as the strata we asked for
-- Art one strata up (HIGH at level 40 — the sharpest shape: the host's LEVEL is
-- already above the art, so only the strata decides). SetFrameStrata is present
-- but ignored: the audit used to overwrite hostStrata with topStrata and report
-- "strata=HIGH -> above the art" on a frame that really is MEDIUM — the exact
-- invisible-line state this card exists for, reported as fixed.
art.level = 40
art.strata = "HIGH"
M.host.SetFrameLevel = function(self, l) self.level = l end -- working again
M.host.SetFrameStrata = function(self) return end -- present, silently ignored
M:Redraw()
check(M._drawError == nil, "E: draw error: " .. tostring(M._drawError))
check(M.host:GetFrameStrata() == "MEDIUM",
  "E: the client kept the frame on MEDIUM (got " .. tostring(M.host:GetFrameStrata()) .. ")")
check(M._zorder and M._zorder.hostStrata == "MEDIUM",
  "E: the audit reports the MEASURED strata, not the one it asked for (got "
    .. tostring(M._zorder and M._zorder.hostStrata) .. ")")
check(M._zorder and M._zorder.stillBelow == true,
  "E: MEDIUM under HIGH art is still below, whatever the levels say")
local strataDiag = diag()
check(strataDiag:find("host_level=45 strata=MEDIUM -> NOT above the art", 1, true) ~= nil,
  "E: the z-order line says NOT above the art (diag: "
    .. tostring(strataDiag:match("z%-order:[^\n]*")) .. ")")
local strataVerdict = lineStartingWith(strataDiag, "verdict:")
check(strataVerdict and strataVerdict:find("DRAW ORDER (still below after the raise attempt)", 1, true) ~= nil,
  "E: the verdict names draw order as still unfixed (got " .. tostring(strataVerdict) .. ")")
check(strataVerdict and strataVerdict:find("the client did not accept a higher strata", 1, true) ~= nil,
  "E: the verdict says the client refused the strata (got " .. tostring(strataVerdict) .. ")")

-- ═══ F. a strata raise that DID take is sticky across redraws ══════════════
-- Same art (HIGH / level 40), but now SetFrameStrata works. The first redraw
-- raises the host to HIGH; the next one must not "adopt the parent's strata"
-- and drop it back to MEDIUM — that put the line under the art again and made
-- mapdiag report a still-below host the overlay itself had just lowered.
M.host.SetFrameStrata = function(self, s) self.strata = s end -- working again
M:Redraw()
check(M._drawError == nil, "F: draw error: " .. tostring(M._drawError))
check(M.host:GetFrameStrata() == "HIGH",
  "F: the host adopted the art's strata (got " .. tostring(M.host:GetFrameStrata()) .. ")")
check(M._zorder and M._zorder.raisedNow == true and M._zorder.strataRose == true,
  "F: the strata raise is recorded as measured")
check(M._zorder and M._zorder.stillBelow == false, "F: the host is above the HIGH art now")
M:Redraw()
check(M.host:GetFrameStrata() == "HIGH",
  "F: the strata raise survives the next redraw (got " .. tostring(M.host:GetFrameStrata()) .. ")")
check(M._zorder and M._zorder.stillBelow == false,
  "F: still above the art on the next redraw")
local stickyVerdict = lineStartingWith(diag(), "verdict:")
check(stickyVerdict and stickyVerdict:find("DRAW ORDER", 1, true) == nil,
  "F: no draw-order claim once the host is above the art (got " .. tostring(stickyVerdict) .. ")")

if failed > 0 then
  io.stderr:write(failed .. " diag truthfulness check(s) failed\n")
  os.exit(1)
end
print("diag_truthful_spec: ok")

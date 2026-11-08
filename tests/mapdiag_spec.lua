-- /nt mapdiag on a client that is missing most of the API it reports on.
-- The command must print one labelled line per fact and never error: this
-- stub has no WorldMapFrame, no legacy map frames, no Minimap, no GetCVar,
-- no GetCurrentMapAreaID, no C_Timer, no hooksecurefunc and no canvas mixin.
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

local function makeFrame()
  local f = { scripts = {} }
  function f:SetScript(name, fn) self.scripts[name] = fn end
  function f:GetScript(name) return self.scripts[name] end
  function f:HookScript(name, fn) self.scripts[name] = fn end
  function f:RegisterEvent() end
  function f:SetParent() end
  function f:SetAllPoints() end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  return f
end

function CreateFrame()
  return makeFrame()
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
loadAddon("UI/MinimapPath.lua")
loadAddon("Core.lua")
ns.Enable()

local function diag()
  chat = {}
  SlashCmdList.NODETRAIL("mapdiag")
  return table.concat(chat, "\n"), #chat
end

-- ── A: a client missing every frame this command reports on ────────────────
do
  local text, count = diag()
  check(SlashCmdList.NODETRAIL ~= nil, "/nt registered")
  check(count >= 14, "mapdiag prints one line per fact, got " .. count)
  for _, needle in ipairs({
    "NodeTrail mapdiag: frame environment",
    "WorldMapFrame: absent",
    "GetCanvas=absent",
    "canvas: absent",
    "mapID: GetMapID()=absent",
    "GetCurrentMapAreaID()=absent",
    "WorldMapButton: absent",
    "WorldMapDetailFrame: absent",
    "WorldMapFrame.ScrollContainer: absent",
    "WorldMapFrame.BorderFrame: absent",
    "MapOverlay: parent=none",
    "map rect: absent",
    "route: none",
    "GetCVar: absent",
    "Minimap: absent",
    "minimap host: absent",
  }) do
    check(text:find(needle, 1, true) ~= nil, "missing line: " .. needle)
  end
  check(text:find("error:", 1, true) == nil, "no line errored on a bare client")
end

-- ── B: frames present but every accessor throws, plus an active route ──────
do
  WorldMapFrame = makeFrame()
  function WorldMapFrame:GetCanvas()
    error("GetCanvas is not a function here")
  end
  function WorldMapFrame:GetMapID()
    error("no map id")
  end

  Minimap = makeFrame()
  function Minimap:GetWidth() error("no width") end

  function GetCVar(name) return name == "lockedWindowScale" and "0" or nil end
  C_Timer = { After = function() end }

  ns.GetDB().showWorldMap = true
  ns.MapOverlay:SetRoute({
    mapID = 17,
    path = { { x = 0.2, y = 0.2 }, { x = 0.6, y = 0.6 } },
  })
  check(ns.MapOverlay._drawError == nil, "route set without a draw error: " .. tostring(ns.MapOverlay._drawError))

  local text, count = diag()
  check(count >= 14, "still prints every line, got " .. count)
  check(text:find("WorldMapFrame: present", 1, true) ~= nil, "WorldMapFrame reported present")
  check(text:find("GetCanvas=present", 1, true) ~= nil, "GetCanvas reported present")
  check(text:find("canvas: absent", 1, true) ~= nil, "throwing GetCanvas prints absent")
  check(text:find("mapID: GetMapID()=absent", 1, true) ~= nil, "throwing GetMapID prints absent")
  check(text:find("route: mapID=17 points=2", 1, true) ~= nil, "route facts printed")
  check(text:find("Minimap: present", 1, true) ~= nil, "Minimap reported present")
  check(text:find("lockedWindowScale=0", 1, true) ~= nil, "cvar printed when GetCVar exists")
  check(text:find("error:", 1, true) == nil, "no line errored with throwing accessors")
end

-- ── C: no chat frame at all: falls back to print, still no error ───────────
do
  local captured = {}
  local realPrint = print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[#parts + 1] = tostring((select(i, ...)))
    end
    captured[#captured + 1] = table.concat(parts, " ")
  end
  DEFAULT_CHAT_FRAME = nil
  local ok = pcall(function() ns.PrintMapDiag() end)
  print = realPrint
  check(ok, "mapdiag survives a client with no chat frame")
  check(#captured >= 14, "printed lines without a chat frame, got " .. #captured)
  local joined = table.concat(captured, "\n")
  check(joined:find("NodeTrail mapdiag:", 1, true) ~= nil, "print fallback keeps the prefix")
  check(joined:find("error:", 1, true) == nil, "print fallback printed no error")
end

-- ── D: /nt status is untouched by the new command ──────────────────────────
do
  DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, msg) chat[#chat + 1] = msg end,
  }
  chat = {}
  SlashCmdList.NODETRAIL("status")
  local text = table.concat(chat, "\n")
  check(text:find("NodeTrail", 1, true) ~= nil, "status still prints")
  check(text:find("mapdiag", 1, true) == nil, "status does not mention mapdiag")
end

if failed > 0 then
  io.stderr:write(failed .. " mapdiag check(s) failed\n")
  os.exit(1)
end
print("mapdiag_spec: ok")

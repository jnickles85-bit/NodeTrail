-- window_hosted_adoption_spec.lua — card t_07f778ca, review 2 (the OTHER path).
--
-- The live path is covered by window_hosted_body_spec.lua: the pack opens, tells
-- the body it is hosted BEFORE the body is created, and the chrome is never
-- built. This spec covers the path that survives a flag set too late:
--
--   a player types /ts (or /up) FIRST, which builds the standalone Touchstone
--   window with its own title bar, its close button, its bordered content frame
--   and its teal — and only THEN opens the pack's window, which adopts the
--   frame that already exists.
--
-- Adoption is not cosmetic: SF.SetHostedChrome(true) has to REMOVE chrome that
-- is already built, on the live frame. If it only worked for frames created
-- after the flag, the first player to use the old command would see exactly the
-- defect the owner retested — so the pre-state is asserted too: this spec first
-- proves the chrome IS there (otherwise "it is gone afterwards" is vacuous),
-- then adopts, then re-runs the same audits used on the live path.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local C = dofile(root .. "/tests/support/wowclient.lua")
C.Install({ width = 1920, height = 1080 })
tinsert, tremove, tsort = table.insert, table.remove, table.sort
format = string.format
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local pkg = {}
local function loadFile(path)
  local chunk, err = loadfile(root .. "/MightiePack/" .. path)
  check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
  if not chunk then return end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. path .. ": " .. tostring(e))
end

MightiePackDB = { modules = { Touchstone = true }, seen = { firstRun = true }, bugCount = 0 }
StatForgeDB = { ui = { scale = 1 }, firstUse = false }

local toc = assert(io.open(root .. "/MightiePack/MightiePack.toc", "r"))
local tocText = toc:read("*a")
toc:close()
for line in tocText:gmatch("[^\r\n]+") do
  local t = line:gsub("^%s+", ""):gsub("%s+$", "")
  if t ~= "" and not t:match("^##") then loadFile(t) end
end
pcall(pkg.EnableModules)

local W, T = pkg.Window, pkg.Theme
local SF = rawget(_G, "StatForge")

-- ── The checker (same rule as the live-path spec) ─────────────────────────
local function walk(rootFrame)
  local out, seen = {}, {}
  local function visit(f)
    if type(f) ~= "table" or seen[f] then return end
    seen[f] = true
    out[#out + 1] = f
    local ok, kids = pcall(f.GetChildren, f)
    if ok and type(kids) == "table" then
      for _, kid in ipairs(kids) do visit(kid) end
    end
  end
  visit(rootFrame)
  return out
end

local function shownEdges(rootFrame)
  local out = {}
  for _, f in ipairs(walk(rootFrame)) do
    if C.Visible(f) then
      local bd = f.backdrop
      if type(bd) == "table" and type(bd.edgeFile) == "string" and bd.edgeFile ~= "" then
        out[#out + 1] = tostring(f.Name or f.kind) .. " edge=" .. bd.edgeFile
      end
    end
  end
  return out
end

local ACCENT = SF.Colors.accent
local function nearAccent(r, g, b)
  return type(r) == "number" and math.abs(r - ACCENT[1]) < 0.02
    and math.abs(g - ACCENT[2]) < 0.02 and math.abs(b - ACCENT[3]) < 0.02
end

local function shownAccent(rootFrame)
  local out = {}
  for _, f in ipairs(walk(rootFrame)) do
    if C.Visible(f) and f.kind == "FontString" then
      local r, g, b = f:GetTextColor()
      if nearAccent(r, g, b) then out[#out + 1] = tostring(f.text) end
      if tostring(f.text or ""):lower():find("|cff66fcf1", 1, true) then
        out[#out + 1] = "code:" .. tostring(f.text)
      end
    end
  end
  return out
end

-- ── 1. THE PRE-STATE: /ts first ───────────────────────────────────────────
-- W._sfShowMain is the VENDORED entry point, captured before the seam replaced
-- SF.ShowMain. Calling it is exactly what /ts did before the pack existed.
check(type(W._sfShowMain) == "function", "the vendored show path is captured")
local okShow = pcall(W._sfShowMain, "upgrades")
check(okShow, "the vendored show path runs")
local body = rawget(_G, "StatForgeMainFrame")
check(type(body) == "table", "the standalone body exists")
if type(body) ~= "table" then
  print("window_hosted_adoption_spec: " .. failed .. " failure(s)")
  os.exit(1)
end
-- Render Settings too, so the buttons that exist before adoption are in the
-- tree (the Diagnostics control is a SF.UI_CreateButton with a vendored edge).
pcall(SF.SelectTab, "options")

local chrome = SF.Chrome and SF.Chrome() or {}
check(type(chrome.titleBar) == "table" and C.Visible(chrome.titleBar),
  "PRE-STATE: the standalone body draws its own title bar")
check(type(chrome.close) == "table" and C.Visible(chrome.close),
  "PRE-STATE: the standalone body draws its own close button")
local contentFrame = SF.ContentFrame and SF.ContentFrame() or nil
check(type(contentFrame) == "table", "the content frame exists")
local preContentEdge = type(contentFrame) == "table" and type(contentFrame.backdrop) == "table"
  and type(contentFrame.backdrop.edgeFile) == "string"
check(preContentEdge, "PRE-STATE: the standalone content frame paints its own border")
local preEdges = shownEdges(contentFrame or body)
check(#preEdges > 0, "PRE-STATE: at least one bordered frame is on screen (" .. #preEdges .. ")")
local preAccent = shownAccent(body)
check(#preAccent > 0, "PRE-STATE: the standalone body shows the vendored accent ("
  .. #preAccent .. " string(s))")

-- ── 2. ADOPT: the pack opens on Touchstone ────────────────────────────────
W.Open("touchstone")
check(body:GetParent() == W.hosts.touchstone, "the body is re-parented into the window")
check(body:GetParent() ~= nil and C.Visible(body), "the body is visible inside the window")

local postEdges = shownEdges(body)
check(#postEdges == 0,
  "after adoption no shown frame under the body paints a border (" .. #postEdges .. "):\n    "
    .. table.concat(postEdges, "\n    "))
local postAccent = shownAccent(body)
check(#postAccent == 0,
  "after adoption no shown string under the body carries the vendored accent ("
    .. #postAccent .. "):\n    " .. table.concat(postAccent, "\n    "))
check(type(contentFrame) == "table" and type(contentFrame.backdrop) == "table"
  and not contentFrame.backdrop.edgeFile,
  "after adoption the content frame has no border")
check(type(chrome.titleBar) == "table" and C.Visible(chrome.titleBar) == false,
  "after adoption the title bar it already had is hidden")
check(type(chrome.close) == "table" and C.Visible(chrome.close) == false,
  "after adoption the close button it already had is hidden")
check(type(chrome.title) == "table" and C.Visible(chrome.title) == false,
  "after adoption the title fontstring it already had is hidden")

-- Navigation is still there, and still switches.
local function findTabButton(label)
  for _, f in ipairs(walk(body)) do
    if C.Visible(f) and f.kind == "Button" and type(f.label) == "table"
      and tostring(f.label.text) == label then
      return f
    end
  end
  return nil
end
local logBtn = findTabButton("Log")
check(logBtn ~= nil, "the inner strip survives adoption")
if logBtn then
  C.FireScript(logBtn, "OnClick")
  check(SF.ActiveTab() == "log", "the inner strip still switches tabs after adoption (got "
    .. tostring(SF.ActiveTab()) .. ")")
end

if failed == 0 then
  print("window_hosted_adoption_spec: ok")
else
  print(("window_hosted_adoption_spec: %d failure(s)"):format(failed))
  os.exit(1)
end

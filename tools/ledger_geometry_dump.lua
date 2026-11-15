-- tools/ledger_geometry_dump.lua — card t_07f778ca (the ledger + the outline fix).
--
-- Prints the geometry and the tokens the window RESOLVES to inside the harness
-- client (tests/support/wowclient.lua): the chrome bands, the window fill's
-- backdrop insets, the hosted body's backdrop, the summary strip's words and
-- meter, and one block per ledger row with its measured columns. Its output is
-- filed at evidence/t_07f778ca-geometry.txt.
--
-- This file ASSERTS NOTHING. The assertions are tests/window_fill_inset_spec.lua,
-- tests/window_ledger_spec.lua, tests/window_summary_strip_spec.lua and
-- tests/window_tabs_spec.lua; this is the readable record for a human.
--
--     lua5.1 tools/ledger_geometry_dump.lua
--
-- It is HARNESS evidence, labelled as such. A real in-game capture is the
-- owner's, and is not faked anywhere in this repo.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tools/[^/]+$") or "."
local C = dofile(root .. "/tests/support/wowclient.lua")
C.Install({ width = 1920, height = 1080 })
tinsert, tremove, tsort = table.insert, table.remove, table.sort
format = string.format
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local pkg = {}
local function loadFile(path)
  local chunk = loadfile(root .. "/MightiePack/" .. path)
  if not chunk then error("load " .. path) end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  if not ok then error("load " .. path .. ": " .. tostring(e)) end
end

MightiePackDB = { modules = { Touchstone = true }, seen = { firstRun = true }, bugCount = 0 }
StatForgeDB = { ui = { scale = 1 }, firstUse = false }
local toc = assert(io.open(root .. "/MightiePack/MightiePack.toc", "r"))
local text = toc:read("*a")
toc:close()
for line in text:gmatch("[^\r\n]+") do
  local t = line:gsub("^%s+", ""):gsub("%s+$", "")
  if t ~= "" and not t:match("^##") then loadFile(t) end
end
pcall(pkg.EnableModules)

local W, T = pkg.Window, pkg.Theme
local SF = rawget(_G, "StatForge")
local CA = rawget(_G, "ChestAdvisor")

-- The verdict list is the advisor's own return shape: a table keyed by link.
local LONG = "eligibility unconfirmed (fail-closed): the client returned false for this link, "
  .. "so no stat order was read for the slot and the item was left unjudged."
local FIXTURE = {
  { link = "[Amber Chain Vest]", id = 1001, verdict = "UPGRADE", slotWord = "Chest", reason = LONG },
  { link = "[Kelpweave Vest]", id = 1002, verdict = "UPGRADE", slotWord = "Chest",
    reason = "more spell power than the equipped robe" },
  { link = "[Mystic Robe]", id = 1003, verdict = "TRADE_OFF", slotWord = "Chest",
    reason = "trade-off: +12 Spell Power, -8 Stamina" },
  { link = "[Ragged Gloves]", id = 1004, verdict = "NOT_UPGRADE", slotWord = "Hands",
    reason = "less armour than the equipped gloves" },
  { link = "[Truesteel Pants]", id = 1005, verdict = "NOT_UPGRADE", slotWord = "Legs",
    reason = "no stat is better" },
}
CA.getVerdicts = function()
  local out = {}
  for _, r in ipairs(FIXTURE) do
    out[r.link] = { verdict = r.verdict, id = r.id, slotWord = r.slotWord, reason = r.reason }
  end
  return out
end

local function hex(c)
  if type(c) ~= "table" then return "none" end
  return string.format("#%02x%02x%02x", math.floor((c[1] or 0) * 255 + 0.5),
    math.floor((c[2] or 0) * 255 + 0.5), math.floor((c[3] or 0) * 255 + 0.5))
end

local function rect(f)
  if type(f) ~= "table" then return "(missing)" end
  local r = C.Rect(f)
  return string.format("x %6.1f .. %6.1f   y %7.1f .. %7.1f   %6.1f x %5.1f  %s",
    r.left, r.right, r.top, r.bottom, r.width, r.height,
    (f.shown == false) and "hidden" or "shown")
end

local function findNamed(frame, name, seen)
  if type(frame) ~= "table" then return nil end
  if frame.Name == name then return frame end
  seen = seen or {}
  if seen[frame] then return nil end
  seen[frame] = true
  local ok, kids = pcall(frame.GetChildren, frame)
  if not ok or type(kids) ~= "table" then return nil end
  for _, k in ipairs(kids) do
    local hit = findNamed(k, name, seen)
    if hit then return hit end
  end
  return nil
end

local function textOf(f)
  if type(f) ~= "table" or type(f.GetText) ~= "function" then return "" end
  return tostring(f:GetText() or "")
end

local function insets(bd)
  local i = type(bd) == "table" and bd.insets or nil
  if type(i) ~= "table" then return "none" end
  return string.format("%s,%s,%s,%s", tostring(i.left), tostring(i.top),
    tostring(i.right), tostring(i.bottom))
end

W.Frame()
W.Open("touchstone")
if type(SF.SelectTab) == "function" then pcall(SF.SelectTab, "upgrades") end

print("== MightiePack — card t_07f778ca: the outline fix and the V1 ledger")
print("== Evidence record. Harness/source evidence ONLY: no in-game screenshot.")
print("== harness: tests/support/wowclient.lua, 1920x1080, scale 1.0")
print("")
print("== 1. CHROME (window open on Touchstone)")
print("  window                 " .. rect(W.frame))
print("  fill (BACKGROUND)      " .. rect(W.bg))
print("  title band             " .. rect(W.titleBar))
print("  tab strip              " .. rect(W.tabStrip))
print("  summary strip          " .. rect(W.summaryFrame))
print("  host touchstone        " .. rect(W.hosts.touchstone))
print("  host settings          " .. rect(W.hosts.settings))
local bd = (W.bg and W.bg.backdrop) or {}
print(string.format("  window fill backdrop   bgFile=%s  insets=%s  edgeFile=%s",
  tostring(bd.bgFile), insets(bd), tostring(bd.edgeFile)))
local bandBd = (W.titleBar and W.titleBar.backdrop) or {}
print(string.format("  band backdrop          bgFile=%s  insets=%s  edgeFile=%s",
  tostring(bandBd.bgFile), insets(bandBd), tostring(bandBd.edgeFile)))
local body = rawget(_G, "StatForgeMainFrame")
if type(body) == "table" then
  local bbd = body.backdrop or {}
  print(string.format("  hosted body backdrop   bgFile=%s  insets=%s  edgeFile=%s  fillAlpha=%s",
    tostring(bbd.bgFile), insets(bbd), tostring(bbd.edgeFile),
    tostring(body.backdropColor and body.backdropColor[4])))
end
print(string.format("  options panel          shown=%s  parent-is-settings-host=%s",
  tostring(pkg.optionsPanel and pkg.optionsPanel:IsShown()),
  tostring(pkg.optionsPanel and W.hosts.settings and pkg.optionsPanel:GetParent() == W.hosts.settings)))
print("")
print("== 2. SUMMARY STRIP (V4's line, V1's drawing)")
print("  line   : " .. textOf(W.summaryCount) .. textOf(W.summaryLine))
print("  right  : " .. textOf(W.summaryDetail))
print(string.format("  meter  : width %.1f  upgrade %.1f  trade-off %.1f  refused %.1f  (%s px tall)",
  C.Rect(W.summaryMeter).width, C.Rect(W.summarySegments.upgrade).width,
  C.Rect(W.summarySegments.tradeoff).width, C.Rect(W.summarySegments.noupgrade).width,
  tostring(T.size.meter)))
print("")
print("== 3. THE LEDGER (Upgrades, five fixture rows)")
local columns = findNamed(W.hosts.touchstone, "TouchstoneUpgradesColumns", {})
if type(columns) == "table" then
  local seen, parts = {}, {}
  for _, kid in ipairs(columns:GetChildren()) do
    if type(kid.GetText) == "function" and not seen[kid] and kid:GetText() ~= "" then
      seen[kid] = true
      parts[#parts + 1] = string.format("%q at x %.1f w %.1f (token)",
        kid:GetText(), C.Rect(kid).left, C.Rect(kid).width)
    end
  end
  print("  column labels: " .. table.concat(parts, " | "))
end
for i = 1, #FIXTURE do
  local row = findNamed(W.hosts.touchstone, "TouchstoneUpgradeRow" .. i, {})
  if type(row) == "table" then
    local r = C.Rect(row)
    print(string.format("  row %d  %s  (%.1f tall)", i, rect(row), r.height))
    print(string.format("      gutter  x %.1f .. %.1f  (token %s)", C.Rect(row.gutter).left,
      C.Rect(row.gutter).right, tostring(T.list.gutter)))
    print(string.format("      verdict %-16s colour %s  marker %s",
      string.format("%q", textOf(row.verdictWord)), hex(row.verdictWord.color),
      hex(row.mark.vertexColor or row.mark.colorTexture)))
    print(string.format("      name    %q  %s", textOf(row.itemName), hex(row.itemName.color)))
    print(string.format("      reason  %q", textOf(row.reason)))
    print(string.format("              %s  top y %.1f, name bottom y %.1f (below, own column)",
      hex(row.reason.color), C.Rect(row.reason).top, C.Rect(row.itemName).bottom))
    print(string.format("      change  %q  %s  x %.1f .. %.1f (token %s)",
      textOf(row.change), hex(row.change.color), C.Rect(row.change).left,
      C.Rect(row.change).right, tostring(T.list.change)))
  end
end
print("")
print("== 4. WHAT THE CLIENT CANNOT EXPRESS (reported, not approximated)")
print("  letter-spacing : none in a FontString — uppercase 9.5px labels are the substitute")
print("  text shadow    : none — the hierarchy is size + colour")
print("  corner radius  : none — the drawing is flat and ruled for exactly that reason")
print("  font weight    : SetFont(path, size, flags) only; 'semibold' is not selectable,")
print("                   so the verdict's colour and the name's size carry the weight")

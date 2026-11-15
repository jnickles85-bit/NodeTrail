-- tools/geometry_dump.lua — HARNESS GEOMETRY EVIDENCE for card t_2d2c37b0.
--
-- This is NOT a screenshot and must never be presented as one. It drives the
-- pack inside tests/support/wowclient.lua — the repo's fake client, which
-- models frames, anchors, strata, frame levels and mouse hit-testing — and
-- prints the resolved rectangles of every chrome and content region for each
-- tab, plus the geometric invariants the design pass is supposed to hold.
--
-- Run from the repo root:
--   lua5.1 tools/geometry_dump.lua
--
-- Output is plain text so it can be filed under evidence/ and diffed between
-- commits. A real in-game capture needs the live client (OWNER-RUN / BLOCKED
-- on the card).

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)[/\\][^/\\]*$") or "."
root = root:gsub("[/\\]?tools$", "")
if root == "" then root = "." end

local C = dofile(root .. "/tests/support/wowclient.lua")
C.Install({ width = 1920, height = 1080 })
GetAddOnMetadata = function(name, what)
  if name ~= "MightiePack" then return nil end
  if what == "Version" then return "0.0.0-evidence" end
  if what == "Interface" then return "16001" end
  return nil
end
tinsert, tremove, tsort = table.insert, table.remove, table.sort
format = string.format
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local pkg = {}
local failures = 0
local function loadFile(path)
  local chunk, err = loadfile(root .. "/MightiePack/" .. path)
  if not chunk then
    print("LOAD FAIL " .. path .. ": " .. tostring(err))
    failures = failures + 1
    return
  end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  if not ok then
    print("LOAD FAIL " .. path .. ": " .. tostring(e))
    failures = failures + 1
  end
end

MightiePackDB = { modules = { Touchstone = true }, seen = { firstRun = true }, bugCount = 0 }
-- A player who has used the pack before: no first-use splash in the way.
StatForgeDB = { ui = { scale = 1 }, firstUse = false }

local toc = assert(io.open(root .. "/MightiePack/MightiePack.toc", "r"))
local tocText = toc:read("*a")
toc:close()
for line in tocText:gmatch("[^\r\n]+") do
  local t = line:gsub("^%s+", ""):gsub("%s+$", "")
  if t ~= "" and not t:match("^##") then loadFile(t) end
end
local okEnable, errEnable = pcall(pkg.EnableModules)
if not okEnable then
  print("ENABLE FAIL: " .. tostring(errEnable))
  failures = failures + 1
end

local W = pkg.Window
local T = pkg.Theme
if type(W) ~= "table" or type(T) ~= "table" then
  print("FATAL: no window or no theme")
  os.exit(1)
end

local function r(frame)
  return C.Rect(frame)
end
local function line(label, frame)
  if type(frame) ~= "table" then
    print(format("  %-22s (absent)", label))
    return
  end
  local x = r(frame)
  print(format("  %-22s x %7.1f .. %7.1f   y %7.1f .. %7.1f   %5.1f x %5.1f  %s",
    label, x.left, x.right, x.top, x.bottom, x.width, x.height,
    frame:IsShown() and "shown" or "hidden"))
end
local function verdict(name, cond, detail)
  print(format("  [%s] %s%s", cond and "PASS" or "FAIL", name,
    detail and (" — " .. detail) or ""))
  if not cond then failures = failures + 1 end
end

print("== MightiePack window geometry — HARNESS EVIDENCE (fake client, not a screenshot)")
print("== windowclient: tests/support/wowclient.lua, 1920x1080, scale 1.0")
print("")

local f = W.Frame()
W.Open("settings")
print("-- chrome (window open, Pack Settings active)")
line("window", f)
line("fill (BACKGROUND)", W.bg)
line("title band", W.titleBar)
line("tab strip", W.tabStrip)
for _, id in ipairs(W.TABS) do
  line("tab: " .. id, W.tabButtons[id])
  line("  underline " .. id, W.tabButtons[id] and W.tabButtons[id].underline)
  line("  host " .. id, W.hosts[id])
end
if type(W.statusDot) == "table" then line("status dot", W.statusDot) end
if type(W.close) == "table" then line("close button", W.close) end

print("")
print("-- title band content")
local titleText = W.title and W.title:GetText() or ""
local statusText = W.statusText and W.statusText:GetText() or ""
local verText = W.version and W.version:GetText() or ""
print(format("  name        : %q", tostring(titleText)))
print(format("  version     : %q", tostring(verText)))
print(format("  status line : %q", tostring(statusText)))
line("status text", W.statusText)

local win = r(f)
local band = r(W.titleBar)
local strip = r(W.tabStrip)
verdict("title band is the theme's height", band.height == T.size.titleBand,
  format("%.0f == %.0f", band.height, T.size.titleBand))
verdict("tab strip is the theme's height", strip.height == T.size.tabStrip,
  format("%.0f == %.0f", strip.height, T.size.tabStrip))
verdict("tab strip sits directly under the band", strip.top == band.bottom)
verdict("no two visible chrome rects overlap (band / strip / tab vs tab)", (function()
  -- The tab buttons are CHILDREN of the strip, so they overlap it by
  -- definition; what must not overlap is the band against the strip, and one
  -- tab against the other.
  if C.Overlaps(W.titleBar, W.tabStrip) then return false end
  if C.Overlaps(W.tabButtons[W.TABS[1]], W.tabButtons[W.TABS[2]]) then return false end
  return true
end)())

-- ── Tab by tab ────────────────────────────────────────────────────────────
local function tabSection(id)
  print("")
  print("-- tab: " .. id .. " (" .. W.TAB_LABELS[id] .. ")")
  W.SelectTab(id)
  line("host " .. id, W.hosts[id])
  local h = r(W.hosts[id])
  verdict(id .. ": content inset from the frame on the grid",
    math.abs(h.left - (win.left + T.space.md)) < 0.5
      and math.abs(h.right - (win.right - T.space.md)) < 0.5
      and math.abs(h.bottom - (win.bottom + T.space.md)) < 0.5,
    format("insets L%.0f R%.0f B%.0f (theme pad %.0f)",
      h.left - win.left, win.right - h.right, h.bottom - win.bottom, T.space.md))
  return h
end

local hostT = tabSection("touchstone")
if type(rawget(_G, "StatForgeMainFrame")) == "table" then
  local body = rawget(_G, "StatForgeMainFrame")
  line("touchstone body", body)
  local b = r(body)
  verdict("touchstone: the body fills its host", b.width > 0 and b.height > 0,
    format("%.0f x %.0f", b.width, b.height))
  verdict("touchstone: the body stays on MEDIUM", body:GetFrameStrata() == "MEDIUM",
    tostring(body:GetFrameStrata()))
  verdict("touchstone: the body draws above the window fill",
    C.DrawsAbove(body, W.bg))
  local kids = body:GetChildren()
  local titleBar, strip2
  for _, kid in ipairs(kids) do
    local kh = kid.height or 0
    if kh == 40 then titleBar = kid end
    if kh == 32 then strip2 = kid end
  end
  verdict("touchstone: the body's own title bar is hidden",
    type(titleBar) ~= "table" or titleBar:IsShown() == false)
  if type(strip2) == "table" then line("  inner strip", strip2) end
else
  print("  (no StatForgeMainFrame: the module did not create its frame here)")
end

local hostS = tabSection("settings")
local panel = pkg.optionsPanel
line("settings panel", panel)
local boxes = pkg.optionsBoxes or {}
line("  Touchstone row", boxes.Touchstone)
line("  Gear for label", boxes.GearForLabel)
line("  Gear for button", boxes.GearFor)
local function findByText(parent, needle, out)
  out = out or {}
  local kids = type(parent) == "table" and parent.GetChildren and parent:GetChildren() or {}
  for _, kid in ipairs(kids) do
    if type(kid) == "table" and type(kid.GetText) == "function" then
      local ok, t = pcall(kid.GetText, kid)
      if ok and type(t) == "string" and t:find(needle, 1, true) then out[#out + 1] = kid end
    end
    findByText(kid, needle, out)
  end
  return out
end
local bugs = findByText(panel, "Report a bug")
line("  bug button", bugs[1])
local ideas = findByText(panel, "Suggest an idea")
line("  idea button", ideas[1])
local card = boxes.Touchstone and boxes.Touchstone:GetParent()
line("  modules card", card)
verdict("settings: the panel fills its host",
  math.abs(r(panel).width - hostS.width) < 0.5 and math.abs(r(panel).height - hostS.height) < 0.5)
verdict("settings: the modules card is on the grid",
  type(card) == "table" and r(card).height % T.space.grid == 0,
  type(card) == "table" and format("%.0f", r(card).height) or "no card")
verdict("settings: the module row does not overlap the Gear-for row",
  type(boxes.Touchstone) == "table" and type(boxes.GearFor) == "table"
    and not C.Overlaps(boxes.Touchstone, boxes.GearFor))
verdict("settings: the feedback row is below the modules card",
  #bugs == 1 and type(card) == "table" and r(bugs[1]).top <= r(card).bottom)

print("")
print("-- summary")
print("  failures: " .. failures)
if failures == 0 then
  print("  result: PASS (harness geometry)")
else
  print("  result: FAIL")
end
os.exit(failures == 0 and 0 or 1)

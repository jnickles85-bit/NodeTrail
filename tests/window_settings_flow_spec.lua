-- window_settings_flow_spec.lua — card t_4e5ad8a4, item B.
--
-- The defect (owner retest of 7e300c3, 2026-11-14): the Settings tab placed its
-- stack by hardcoded y offsets from the top (-24, -60, -94, -135, -152, -203,
-- -258, -293, -309) and anchored the About/help block to the content frame's
-- BOTTOM edge. The offsets were tuned for a 515-unit body; inside the unified
-- window the body is 441 units (measured on the owner's screenshot: the panel's
-- interior spans 661 px at 1.5 px per unit), so the bottom-anchored block climbed
-- 74 units up into the stack and printed the About paragraph over Role, Class and
-- the role note. Role and Class themselves sit 16 units apart, which is a
-- line-height assumption, not a layout.
--
-- What this file pins:
--   S1 no two blocks overlap — asserted as a rule over every pair, not spot checks;
--   S2 Role and Class: do not overlap, and Class is BELOW Role;
--   S3 the About block does not overlap anything above it, and its last line
--      (the Tip line) is inside the content and collides with nothing;
--   S4 the same numbers at 441 and at 515: every block's offset from the top is
--      independent of the body height (this is what "flowing layout" buys);
--   S5 the content is taller than the body, so it is reached by SCROLLING, and
--      the scroll ends exactly at the content's bottom (no lost tail);
--   S6 the scroll clamps at the top: no blank band above the title.
--
-- The layout snapshot (SF.OptionsTabLayout) reports the very regions the tab
-- placed, so nothing here re-derives the positions it is checking.

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

local EPS = 0.05

local pkg = { PackVersion = function() return "0.5.0" end }
_G.MightiePack = pkg

local function loadFile(path)
  local chunk, err = loadfile(root .. "/MightiePack/Modules/Touchstone/" .. path)
  check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
  if not chunk then return end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. path .. ": " .. tostring(e))
end

StatForgeDB = { ui = { scale = 1 }, firstUse = false }

-- The client's global aliases, which the module uses (UI.lua calls tinsert).
tinsert = table.insert
tremove = table.remove
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

-- Just enough of the advisor for the tab's own reads (detail/tooltip/toast/role).
ChestAdvisor = {
  getVerdicts = function() return {} end,
  getLog = function() return {} end,
  tooltipUI = { detail = function() return "full" end, enabled = function() return true end },
  toastState = function() return { enabled = true } end,
}

loadFile("Constants.lua")
loadFile("UI.lua")
loadFile("OptionsTab.lua")

local SF = _G.StatForge
check(type(SF) == "table", "the module loads")
check(type(SF.OptionsTabLayout) == "function", "the tab exposes its layout for this spec")

SF.ShowMain("options")

local content = SF.GetContentFrame()
check(type(content) == "table", "the window built its content frame")
local main = content and content:GetParent()

local function setBody(width, height)
  if type(main) ~= "table" then return end
  main:SetSize(width, height)
  for _, child in ipairs(main:GetChildren()) do
    if child ~= content and child:GetHeight() == 32 then
      child:ClearAllPoints()
      child:SetPoint("TOPLEFT", main, "TOPLEFT", 12, -8)
      child:SetPoint("TOPRIGHT", main, "TOPRIGHT", -12, -8)
    end
  end
end

local function layoutAt(width, height)
  setBody(width, height)
  SF.SelectTab("options")
  if type(SF.OptionsTabLayout) ~= "function" then return nil end
  local l = SF.OptionsTabLayout()
  check(type(l) == "table", "the layout snapshot exists")
  return l
end

local function overlaps(a, b)
  return C.Overlaps(a, b)
end

local function rectOverlapsRect(a, b)
  local w = math.min(a.right, b.right) - math.max(a.left, b.left)
  local h = math.min(a.top, b.top) - math.max(a.bottom, b.bottom)
  return w > EPS and h > EPS
end

--- A block's own words, for the failure messages: a FontString has GetText, a
--- frame only has a name.
local function labelOf(region)
  if type(region) ~= "table" then return "?" end
  if type(region.GetText) == "function" then
    local text = region:GetText()
    if type(text) == "string" and text ~= "" then return text end
  end
  return tostring(region:GetName() or "unnamed")
end

-- ── The body the unified window actually gives the tab ──────────────────────
local L = layoutAt(936, 505)
check(L ~= nil, "the Settings tab rendered")
if not L then
  io.stderr:write(tostring(failed) .. " check(s) failed\n")
  os.exit(1)
end

local body = C.Rect(content)
check(math.abs(body.height - 441) < 0.5,
  "precondition: the modelled body is 441 units (got " .. string.format("%.1f", body.height) .. ")")

local host = L.host
local blocks = {}
for _, b in ipairs(L.blocks) do
  if type(b.region) == "table" and C.Visible(b.region) then
    blocks[#blocks + 1] = b
  end
end
check(#blocks >= 14, "the stack has its blocks (" .. tostring(#blocks) .. ")")

-- S1 — no two blocks overlap.
for i = 1, #blocks do
  for j = i + 1, #blocks do
    local a, b = blocks[i].region, blocks[j].region
    local hit = overlaps(a, b)
    check(not hit, "S1 blocks " .. i .. " and " .. j .. " do not overlap ("
      .. labelOf(a) .. " vs " .. labelOf(b) .. ")")
  end
end

-- S2 — Role and Class, the pair the owner saw mashed together.
check(host.roleHeader ~= nil and host.classLabel ~= nil, "S2 Role and Class exist")
if host.roleHeader and host.classLabel then
  check(not overlaps(host.roleHeader, host.classLabel),
    "S2 'Role' and 'Class:' do not overlap (role bottom "
      .. string.format("%.1f", C.Rect(host.roleHeader).bottom) .. ", class top "
      .. string.format("%.1f", C.Rect(host.classLabel).top) .. ")")
  check(C.Rect(host.classLabel).top <= C.Rect(host.roleHeader).bottom + EPS,
    "S2 the class line sits BELOW the Role heading")
end

-- S3 — the About block, and its Tip line, collide with nothing.
local about = host.about
check(type(about) == "table", "S3 the About block exists")
if type(about) == "table" then
  for _, b in ipairs(blocks) do
    if b.region ~= about then
      check(not overlaps(about, b.region),
        "S3 the About block does not overlap the block above it (" .. labelOf(b.region) .. ")")
    end
  end

  local text = about:GetText() or ""
  check(text:find("Tip: run", 1, true) ~= nil, "S3 premise: the block's last line is the Tip line")

  local lineH = C.defaultFontSize * C.lineHeight
  local ar = C.Rect(about)
  local lines = math.floor((ar.height + 0.01) / lineH)
  check(lines >= 10, "S3 premise: the About block is " .. tostring(lines) .. " lines")
  -- The Tip line is the LAST rendered line of the block.
  local tipTop = ar.top - (lines - 1) * lineH
  local tip = { left = ar.left, right = ar.right, top = tipTop, bottom = tipTop - lineH }
  for _, b in ipairs(blocks) do
    if b.region ~= about then
      check(not rectOverlapsRect(tip, C.Rect(b.region)),
        "S3 the Tip line collides with no other block")
    end
  end
  local cr = C.Rect(L.content)
  check(tip.bottom >= cr.bottom - EPS and tip.top <= cr.top + EPS,
    "S3 the Tip line is inside the scrolled content (tip bottom "
      .. string.format("%.1f", tip.bottom) .. ", content bottom "
      .. string.format("%.1f", cr.bottom) .. ")")
end

-- S4 — the flow does not depend on the body height.
local tops441 = {}
for i, b in ipairs(blocks) do
  tops441[i] = C.Rect(b.region).top - C.Rect(L.content).top
end

local L2 = layoutAt(920, 579)   -- standalone: 920x620 window, content 515
check(L2 ~= nil, "the tab renders again at the standalone body height")
local body2 = C.Rect(content)
check(math.abs(body2.height - 515) < 0.5,
  "precondition: the standalone body is 515 units (got " .. string.format("%.1f", body2.height) .. ")")

local blocks2 = {}
for _, b in ipairs(L2.blocks) do
  if type(b.region) == "table" and C.Visible(b.region) then
    blocks2[#blocks2 + 1] = b
  end
end
check(#blocks2 == #blocks, "S4 the same blocks are placed at both heights ("
  .. tostring(#blocks2) .. " vs " .. tostring(#blocks) .. ")")

if #blocks2 == #blocks then
  for i = 1, #blocks do
    local off2 = C.Rect(blocks2[i].region).top - C.Rect(L2.content).top
    check(math.abs(off2 - tops441[i]) < EPS,
      "S4 block " .. i .. " is at the same offset from the top at 441 and 515 ("
        .. string.format("%.2f", tops441[i]) .. " vs " .. string.format("%.2f", off2) .. ")")
  end
end

-- S2/S3 again at the standalone height: the same rules, a different body.
if host.roleHeader and host.classLabel then
  check(not overlaps(host.roleHeader, host.classLabel),
    "S4 Role and Class do not overlap at 515 either")
end

-- ── S5/S6 — the content is reached by scrolling, and the scroll is exact ────
L = layoutAt(936, 505)
body = C.Rect(content)
local viewport = L.viewport
check(type(viewport) == "table", "the tab has a viewport")
local vprect = C.Rect(viewport)

check(L.scrollMax > 0,
  "S5 the stack is taller than the 441-unit body, so it scrolls (overflow "
    .. string.format("%.1f", L.scrollMax) .. ")")
check(math.abs(L.scrollMax - (C.Rect(L.content).height - vprect.height)) < EPS,
  "S5 the scroll range is exactly the content over the viewport")
check(L.scroll == 0, "S5 the tab opens at the top")

-- Wheel down until the end: the content's bottom must land on the viewport's.
for _ = 1, 60 do
  C.FireScript(viewport, "OnMouseWheel", -1)
end
local after = SF.OptionsTabLayout()
local contentRect = C.Rect(after.content)
check(math.abs(after.scroll - after.scrollMax) < EPS,
  "S5 the wheel reaches the end of the stack (" .. string.format("%.1f", after.scroll)
    .. " of " .. string.format("%.1f", after.scrollMax) .. ")")
check(math.abs(contentRect.bottom - vprect.bottom) < EPS,
  "S5 at the end of the scroll the content's bottom sits on the viewport's ("
    .. string.format("%.1f", contentRect.bottom) .. " vs " .. string.format("%.1f", vprect.bottom) .. ")")

-- The About block is then fully on screen.
local aboutAfter = C.Rect(host.about)
check(aboutAfter.bottom >= vprect.bottom - EPS,
  "S5 scrolled to the end, the Tip line is on screen")

-- The viewport CLIPS: without it the stack's tail paints over the panel border
-- and the window, which is the same defect one layer out.
check(viewport:GetClipsChildren() == true,
  "S5 the viewport clips its children (SetClipsChildren(true))")

-- Wheel up past the top: clamps at 0, no blank band.
for _ = 1, 80 do
  C.FireScript(viewport, "OnMouseWheel", 1)
end
local top = SF.OptionsTabLayout()
check(top.scroll == 0, "S6 the scroll clamps at the top (got " .. string.format("%.1f", top.scroll) .. ")")
check(math.abs(C.Rect(top.content).top - vprect.top) < EPS,
  "S6 at the top of the scroll the content's top sits on the viewport's")

if failed > 0 then
  io.stderr:write(tostring(failed) .. " check(s) failed\n")
  os.exit(1)
end
print("window_settings_flow_spec: ok")

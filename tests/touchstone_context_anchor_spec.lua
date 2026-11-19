-- touchstone_context_anchor_spec.lua — card t_ce1c4a4f, part 4 (the pack half).
--
-- THE DEFECT. Card t_4e5ad8a4 moved placement out of `labelledCheck` (it takes
-- three arguments now, not five) and updated its call sites — except the Context
-- loop, which still passes `(host, name, label, contextX, -309)`. Lua discards
-- the two extra arguments, and nothing in that loop anchored `cb`, so all three
-- Context checkboxes (A.CONTEXTS: leveling, dungeon, raid) were created at the
-- parent's origin, stacked on top of each other, with their labels anchored to
-- the box.
--
-- WHAT THIS FILE PINS, on the SHIPPED file:
--   C1  three Context checkboxes exist, one per context the advisor offers.
--   C2  EVERY one of them carries exactly one anchor (GetNumPoints() == 1).
--   C3  the three anchors are distinct points, and the geometry the harness
--       measures puts them side by side: no two rects overlap.
--
-- AND ITS OWN NON-VACUITY: the same spec runs a SECOND copy of the shipped
-- source with the anchor block removed (the pre-card shape). On that copy a box
-- must have NO anchor, which is the state the defect produced. A mutation whose
-- source text is not found FAILS rather than passing, so a rewritten line cannot
-- turn this proof into decoration.

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

local COLOR = { accent = { 0.4, 0.9, 0.95 }, textMuted = { 0.6, 0.6, 0.6 } }

-- The smallest StatForge a standalone load of the tab needs. Nothing here
-- implements the tab's behaviour: it is the host surface the file reads.
local function makeSF()
  local SF = {}
  SF.Colors = COLOR
  SF.optionControls = {}
  SF.VERSION = "spec"
  SF.RegisterTab = function(name, render) SF._tab = { name = name, render = render } end
  function SF.UI_CreateLabel(parent, text)
    local fs = parent:CreateFontString()
    fs:SetText(text or "")
    return fs
  end
  function SF.UI_CreateButton(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 100, h or 24)
    b:SetText(text or "")
    return b
  end
  function SF.UI_SetAccent() end
  function SF.UI_AccentText(s) return s end
  -- The accent wrapper the About block interpolates as a colour CODE.
  function SF.Accent(s) return "|cff66e6f2" .. tostring(s) .. "|r" end
  function SF.RepaintAccent() end
  function SF.SetTheme() end
  function SF.LogTabState() return {} end
  function SF.UpgradesTabState() return {} end
  function SF.ThemeAccent() return COLOR.accent end
  function SF.OnAccentRepaint() end
  function SF.GetWindowScale() return 1 end
  function SF.SetWindowScale() end
  function SF.WindowScaleBounds() return 0.5, 1.5 end
  function SF.ShowDiagnosticsPanel() end
  function SF.UpdateMinimapButton() end
  return SF
end

-- The advisor surface the tab reads for its Context row. These ARE the three
-- contexts Arbitration.CONTEXTS defines (leveling, dungeon, raid), in that order.
local CONTEXTS = {
  { word = "leveling", label = "Leveling", meaning = "Questing and solo play." },
  { word = "dungeon",  label = "Dungeon",  meaning = "Five-player instances." },
  { word = "raid",     label = "Raid",     meaning = "Group content with many players." },
}

ChestAdvisorDB = {}
local ADV = {
  contextOptions = CONTEXTS,
  context = function() return "leveling" end,
}
-- The tab reads the advisor at CALL time (the Context loop asks it what the
-- contexts are when the tab renders), so the global has to be in place for the
-- whole render, not only for the chunk's own evaluation.
ChestAdvisor = ADV

local function loadTab(source, sf)
  local savedSF = StatForge
  StatForge = sf
  -- Lua 5.1 spells it loadstring; 5.2+ spells the string form `load`.
  local loader = loadstring or load
  local chunk, err = loader(source, "OptionsTab")
  local ok, e = false, err
  if chunk then ok, e = pcall(chunk) end
  StatForge = savedSF
  check(ok, "the shipped OptionsTab.lua loads: " .. tostring(e))
  return sf._tab
end

local function rendered(tab)
  local host = CreateFrame("Frame", "TouchstoneOptionsHost", UIParent)
  host:SetSize(900, 441)
  tab.render(host)
  return host
end

local function boxOf(host, word)
  return host.contextChecks and host.contextChecks[word] or nil
end

local PATH = root .. "/MightiePack/Modules/Touchstone/OptionsTab.lua"
local fh = assert(io.open(PATH, "rb"))
local SOURCE = fh:read("*a"):gsub("\r\n", "\n")
fh:close()

-- ── the shipped file ───────────────────────────────────────────────────────
local sf = makeSF()
local tab = loadTab(SOURCE, sf)
check(type(tab) == "table" and type(tab.render) == "function",
  "the tab registers its render with SF.RegisterTab")

local host = rendered(tab)
local boxes = { boxOf(host, "leveling"), boxOf(host, "dungeon"), boxOf(host, "raid") }
-- C1
check(boxes[1] ~= nil and boxes[2] ~= nil and boxes[3] ~= nil,
  "C1: three Context checkboxes exist (leveling, dungeon, raid)")

-- C2 + the anchors and geometry, printed so the report can quote them.
local rects, anchors = {}, {}
for i, cb in ipairs(boxes) do
  if cb then
    local n = cb:GetNumPoints()
    check(n == 1, "C2: the " .. CONTEXTS[i].word .. " box has exactly ONE anchor (has "
      .. tostring(n) .. ")")
    local point, rel, relPoint, x, y = cb:GetPoint(1)
    local relName = "?"
    if rel == host.contextHeader then relName = "contextHeader"
    elseif i > 1 and rel == boxes[i - 1] then relName = "the previous box"
    elseif rel == host then relName = "host"
    end
    anchors[i] = tostring(point) .. " " .. relName .. "." .. tostring(relPoint)
      .. " (" .. tostring(x) .. "," .. tostring(y) .. ")"
    local r = C.Rect(cb)
    rects[i] = r
    io.write(string.format("  %-9s anchor %-58s rect left=%.1f right=%.1f top=%.1f bottom=%.1f\n",
      CONTEXTS[i].word, anchors[i], r.left, r.right, r.top, r.bottom))
  end
end

-- C3: three anchored points resolve to three distinct POSITIONS. The literal
-- anchor text is not the claim — two boxes may both say "110 right of the one
-- before it" — so the check is on the resolved geometry below, and on each box
-- being anchored to a DIFFERENT thing (which is what makes the row a row).
local rels = {}
for i, cb in ipairs(boxes) do
  if cb then
    local _, rel = cb:GetPoint(1)
    check(rels[rel] == nil,
      "C3: the " .. CONTEXTS[i].word .. " box is anchored to a different frame than "
        .. "the boxes before it")
    rels[rel] = true
  end
end
local function overlaps(a, b)
  if not (a and b) then return false end
  return a.left < b.right and b.left < a.right and a.top > b.bottom and b.top > a.bottom
end
for i = 1, 3 do
  for j = i + 1, 3 do
    check(not overlaps(rects[i], rects[j]),
      "C3: the " .. CONTEXTS[i].word .. " and " .. CONTEXTS[j].word
        .. " boxes do not overlap")
  end
end
if rects[1] and rects[2] and rects[3] then
  check(rects[1].left < rects[2].left and rects[2].left < rects[3].left,
    "C3: the three boxes run left to right in the contexts' own order")
end

-- ── non-vacuity: the pre-card shape, in a second copy ──────────────────────
-- The anchor block, exactly as the patch carries it. Removing it restores the
-- defect: `labelledCheck` does not anchor, so the box keeps NO point at all.
local FROM = '    if contextRow == nil then\n'
  .. '      cb:SetPoint("TOPLEFT", contextHeader, "BOTTOMLEFT", 0, -4)\n'
  .. '    else\n'
  .. '      cb:SetPoint("TOPLEFT", contextRow, "TOPLEFT", 110, 0)\n'
  .. '    end\n'
local at = SOURCE:find(FROM, 1, true)
check(at ~= nil, "the anchor block this spec reverts is present in the shipped source")
if at then
  local mutated = SOURCE:sub(1, at - 1) .. SOURCE:sub(at + #FROM)
  local sf2 = makeSF()
  local tab2 = loadTab(mutated, sf2)
  local host2 = rendered(tab2)
  local cb = boxOf(host2, "leveling")
  check(cb ~= nil, "mutation: the Context boxes still exist without the anchor block")
  if cb then
    io.write("  mutated  leveling  anchor points=" .. tostring(cb:GetNumPoints())
      .. "  (the defected state: NO anchor)\n")
    check(cb:GetNumPoints() == 0,
      "NON-VACUITY: with the anchor block removed, the box has NO anchor — the defect "
        .. "this spec exists for")
  end
end

if failed > 0 then
  io.stderr:write(tostring(failed) .. " check(s) failed\n")
  os.exit(1)
end
io.write("PASS: three Context checkboxes, each anchored, distinct, none overlapping — "
  .. "and the unanchored shape is measured red.\n")

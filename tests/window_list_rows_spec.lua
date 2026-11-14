-- window_list_rows_spec.lua — card t_4e5ad8a4, item A.
--
-- The defect (owner retest of 7e300c3, 2026-11-14): a verdict reason that wraps
-- to three lines is ~36 units of type inside a 34-unit row, and the next row
-- started at a fixed 34-unit pitch -- so the third line printed over the next
-- item's name. UpgradesTab.lua had ROW_H = 34 and LogTab.lua ROW_H = 30 with the
-- same shape, and the reason is a sentence ("eligibility unconfirmed
-- (fail-closed): client returned false ..."), so shortening a label is not an
-- option.
--
-- The card's decision, stated once and applied to BOTH lists: a row GROWS to fit
-- its wrapped reason (variable height), rather than clamping the reason to N
-- lines. The reason is the product -- clamping it hides the sentence the advisor
-- exists to say. Both tabs therefore run the same two helpers, SF.PageRows and
-- SF.StackRow (UI.lua), so they cannot drift apart.
--
-- What this file pins, for Upgrades and for Log:
--   A1 the premise: the fixture reason really is THREE lines at the row's width,
--      so the assertions below are about a wrapped reason, not a short one;
--   A2 the row CONTAINS its own reason: the row's bottom is at or below the
--      reason's bottom, and its top at or above the reason's top;
--   A3 the next row does not overlap the reason, and the two rows do not overlap
--      each other (the next row's top is at or below the row above's bottom);
--   A4 a three-line row is TALLER than a one-line row — variable height, not a
--      clamp with a taller box;
--   A5 the page is what FITS: every shown row is inside the viewport, and the
--      next admitted row would not fit (so nothing is pushed outside the panel);
--   A6 the same holds at the unified window's body height (441 units) as at the
--      standalone 515: the stacking rule depends on the text, not the body.
--
-- The heights come from tests/support/wowclient.lua, which now measures a
-- FontString the way the client does (wrapped lines included). Before this card
-- the model answered ONE line for every string, which is the same assumption the
-- tabs were making — the reason a green suite could not see the overprint.

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

-- ── The module under test ───────────────────────────────────────────────────
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

-- Three lines at 400 units (a font string wraps at ~60 glyphs there in this
-- model), and the same in the Log's 360-unit reason column: 152 characters is
-- between two and three lines at both widths, and the spec asserts the premise.
local LONG_REASON =
  "eligibility unconfirmed (fail-closed): the client returned false for this link, " ..
  "so no stat order was read for the slot and the item was left unjudged."

local SHORT_REASON = "more spell power than the equipped robe"

local UPGRADE_LINKS = {
  -- Sorted by rank then name, so "Amber Chain Vest" is row 1 -- and it is the
  -- only row carrying the long reason ("Amber" sorts before every other name).
  { link = "[Amber Chain Vest]", id = 1001, slotWord = "Chest", reason = LONG_REASON },
  { link = "[Mystic Robe]", id = 1002, slotWord = "Chest", reason = SHORT_REASON },
  { link = "[Ragged Leather Gloves]", id = 1003, slotWord = "Hands", reason = SHORT_REASON },
  { link = "[Truesteel Leather Pants]", id = 1004, slotWord = "Legs", reason = SHORT_REASON },
  { link = "[Bristlebane Belt]", id = 1005, slotWord = "Waist", reason = SHORT_REASON },
  { link = "[Crustacean Boots]", id = 1006, slotWord = "Feet", reason = SHORT_REASON },
  { link = "[Driftwood Bracers]", id = 1007, slotWord = "Wrist", reason = SHORT_REASON },
  { link = "[Emberstone Ring]", id = 1008, slotWord = "Finger", reason = SHORT_REASON },
  { link = "[Frostwind Cape]", id = 1009, slotWord = "Back", reason = SHORT_REASON },
  { link = "[Granite Shield]", id = 1010, slotWord = "Off Hand", reason = SHORT_REASON },
  { link = "[Harbor Amulet]", id = 1011, slotWord = "Neck", reason = SHORT_REASON },
  { link = "[Inkwood Staff]", id = 1012, slotWord = "Main Hand", reason = SHORT_REASON },
  { link = "[Jasper Headpiece]", id = 1013, slotWord = "Head", reason = SHORT_REASON },
  { link = "[Kelpweave Vest]", id = 1014, slotWord = "Chest", reason = SHORT_REASON },
}

local LOG_ENTRIES = {
  { at = 1700000000, slotName = "Chest", link = "[Amber Chain Vest]", verdict = "UPGRADE", reason = LONG_REASON },
}
-- Enough entries that one page cannot hold them all: the page is measured, not
-- counted off at 13.
for i = 2, 20 do
  LOG_ENTRIES[i] = {
    at = 1700000000 + i * 60,
    slotName = "Slot " .. i,
    link = "[Logged Item " .. i .. "]",
    verdict = "UPGRADE",
    reason = SHORT_REASON,
  }
end

ChestAdvisor = {
  getVerdicts = function()
    local out = {}
    for _, row in ipairs(UPGRADE_LINKS) do
      out[row.link] = { verdict = "UPGRADE", id = row.id, slotWord = row.slotWord, reason = row.reason }
    end
    return out
  end,
  getLog = function() return LOG_ENTRIES end,
}

loadFile("Constants.lua")
loadFile("UI.lua")
loadFile("UpgradesTab.lua")
loadFile("LogTab.lua")

local SF = _G.StatForge
check(type(SF) == "table", "the module loads")
check(type(SF.PageRows) == "function" and type(SF.StackRow) == "function",
  "the two lists share one stacking rule (SF.PageRows / SF.StackRow)")

local function findNamed(frame, name, seen)
  if type(frame) ~= "table" then return nil end
  if frame.Name == name then return frame end
  seen = seen or {}
  if seen[frame] then return nil end
  seen[frame] = true
  for _, child in ipairs(frame:GetChildren()) do
    local hit = findNamed(child, name, seen)
    if hit then return hit end
  end
  return nil
end

SF.ShowMain("upgrades")

local content = SF.GetContentFrame()
check(type(content) == "table", "the window built its content frame")
local main = content and content:GetParent()

--- Model the body the tab actually gets inside the unified window: the vendored
--- frame is SetAllPoints(host), the inner strip is re-anchored to the frame's top
--- (Window.AttachTouchstone) and the content frame hangs 48 below it and 16 above
--- the bottom. 441 is the height measured on the owner's screenshot.
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

local function lineHeight()
  return C.defaultFontSize * C.lineHeight
end

--- Assert the whole row model for one list.
local function checkList(label, firstRowName, reasonOf, viewportOf, rowsOf, admitted)
  local row1 = findNamed(main, firstRowName)
  check(type(row1) == "table", label .. ": row 1 exists (" .. firstRowName .. ")")
  if type(row1) ~= "table" then return end

  local viewport = viewportOf(row1)
  local rows = rowsOf(row1)
  check(type(viewport) == "table", label .. ": the list has a viewport")
  check(viewport:GetClipsChildren() == true,
    label .. ": the viewport clips its children, so a row can never paint outside the panel")
  check(#rows > 1, label .. ": the list has more than one row")
  if #rows < 2 then return end

  -- A1 — the premise.
  local reason = reasonOf(row1)
  local h = reason:GetHeight()
  check(math.abs(h - 3 * lineHeight()) < 0.01,
    label .. ": A1 the fixture reason renders THREE lines (got " .. tostring(h)
      .. ", one line is " .. tostring(lineHeight()) .. ")")

  -- A2 — the row contains its own reason.
  local row1Rect, reasonRect = C.Rect(row1), C.Rect(reason)
  check(row1Rect.bottom <= reasonRect.bottom + EPS,
    label .. ": A2 the row's bottom (" .. string.format("%.1f", row1Rect.bottom)
      .. ") is at or below the reason's bottom (" .. string.format("%.1f", reasonRect.bottom) .. ")")
  check(row1Rect.top >= reasonRect.top - EPS,
    label .. ": A2 the row's top (" .. string.format("%.1f", row1Rect.top)
      .. ") is at or above the reason's top (" .. string.format("%.1f", reasonRect.top) .. ")")

  -- A3 — the next row starts below the row above it, and the reason does not
  -- reach into it.
  local row2 = rows[2]
  local row2Rect = C.Rect(row2)
  local overlaps = C.Overlaps(row1, row2)
  check(not overlaps,
    label .. ": A3 row 1 and row 2 do not overlap (row 1 bottom "
      .. string.format("%.1f", row1Rect.bottom) .. ", row 2 top "
      .. string.format("%.1f", row2Rect.top) .. ")")
  check(row2Rect.top <= row1Rect.bottom + EPS,
    label .. ": A3 the next row's top (" .. string.format("%.1f", row2Rect.top)
      .. ") is at or below row 1's bottom (" .. string.format("%.1f", row1Rect.bottom) .. ")")
  check(not C.Overlaps(reason, row2),
    label .. ": A3 the wrapped reason does not overlap the next row's name/row")

  -- A4 — variable height, not a clamp.
  local oneLine = rows[#rows]
  check(row1:GetHeight() > oneLine:GetHeight() + EPS,
    label .. ": A4 the three-line row (" .. string.format("%.1f", row1:GetHeight())
      .. ") is taller than a one-line row (" .. string.format("%.1f", oneLine:GetHeight()) .. ")")

  -- A5 — the page is what fits, and it is maximal.
  local shownCount, stacked = 0, 0
  for i, row in ipairs(rows) do
    if C.Visible(row) then
      shownCount = shownCount + 1
      stacked = stacked + row:GetHeight()
      local r = C.Rect(row)
      local vp = C.Rect(viewport)
      check(r.bottom >= vp.bottom - EPS,
        label .. ": A5 row " .. i .. " is inside the viewport (row bottom "
          .. string.format("%.1f", r.bottom) .. ", viewport bottom "
          .. string.format("%.1f", vp.bottom) .. ")")
    end
  end
  check(shownCount > 0, label .. ": A5 at least one row is on the page")
  check(stacked <= C.Rect(viewport).height + EPS,
    label .. ": A5 the page's stacked height (" .. string.format("%.1f", stacked)
      .. ") fits the viewport (" .. string.format("%.1f", C.Rect(viewport).height) .. ")")
  local nextRow = rows[shownCount + 1]
  if nextRow then
    check(stacked + nextRow:GetHeight() > C.Rect(viewport).height,
      label .. ": A5 the page is MAXIMAL (the next row would not fit)")
  end
  if admitted then
    check(shownCount < admitted,
      label .. ": A5 the fixture overflows one page (" .. shownCount .. " of " .. admitted .. ")")
  end
end

-- ── Standalone body (515 units) ─────────────────────────────────────────────
SF.SelectTab("upgrades")

local upgradeState = SF.UpgradesTabState()
check(upgradeState.total == #UPGRADE_LINKS,
  "the fixture's verdicts reach the tab (" .. tostring(upgradeState.total) .. ")")
check(upgradeState.admitted == #UPGRADE_LINKS,
  "every verdict is admitted (Show all is the default)")

checkList("Upgrades@515", "TouchstoneUpgradeRow1",
  function(row) return row.reason end,
  function(row) return row:GetParent():GetParent() end,
  function(row) return row:GetParent():GetChildren() end,
  upgradeState.admitted)

SF.SelectTab("log")

local logState = SF.LogTabState()
check(logState.total == #LOG_ENTRIES,
  "the fixture's log entries reach the tab (" .. tostring(logState.total) .. ")")

checkList("Log@515", "TouchstoneLogRow1",
  function(row) return row.reason end,
  function(row) return row:GetParent():GetParent() end,
  function(row) return row:GetParent():GetChildren() end,
  logState.total)

-- ── The unified window's body (441 units) ───────────────────────────────────
-- A6: the same rule at the height the tab actually has inside MightiePack.
setBody(936, 505)
local bodyHeight = C.Rect(content).height
check(math.abs(bodyHeight - 441) < 0.5,
  "precondition: the modelled body is 441 units (got " .. string.format("%.1f", bodyHeight) .. ")")

SF.SelectTab("upgrades")
checkList("Upgrades@441", "TouchstoneUpgradeRow1",
  function(row) return row.reason end,
  function(row) return row:GetParent():GetParent() end,
  function(row) return row:GetParent():GetChildren() end,
  SF.UpgradesTabState().admitted)

SF.SelectTab("log")
checkList("Log@441", "TouchstoneLogRow1",
  function(row) return row.reason end,
  function(row) return row:GetParent():GetParent() end,
  function(row) return row:GetParent():GetChildren() end,
  SF.LogTabState().total)

-- The row count on a page is MEASURED, not the fixed 12/13 the tabs shipped:
-- at the shorter body fewer rows fit, and the tab says so in its own state.
local shortBody = SF.UpgradesTabState()
check(shortBody.shown > 0 and shortBody.shown < shortBody.admitted,
  "A6 the page count is measured from the rows that fit ("
    .. tostring(shortBody.shown) .. " of " .. tostring(shortBody.admitted) .. ")")

if failed > 0 then
  io.stderr:write(tostring(failed) .. " check(s) failed\n")
  os.exit(1)
end
print("window_list_rows_spec: ok")

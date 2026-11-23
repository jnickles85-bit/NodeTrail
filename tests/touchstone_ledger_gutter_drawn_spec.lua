-- touchstone_ledger_gutter_drawn_spec.lua — the verdict gutter must PAINT.
--
-- WHAT WENT WRONG. On 7439f02 the owner's live client (WoW: Forever, 16001)
-- drew the Upgrades row for Hunter's Boomstick with its name, its reason and its
-- slot word, and drew NOTHING in the VERDICT column: no green marker.tga arrow
-- and no "Upgrade" word. The Log tab's VERDICT column was empty the same way.
-- The tooltip, reading the very same word helper (TOOLTIP_UI.wordFor), said
-- "Upgrade", and the header summary used the same colour tokens — so the word,
-- the colour and the font were all fine.
--
-- The one thing the missing pieces share: they are the only regions owned by
-- the row's `gutter` frame, and that frame was built with ONE anchor
-- (TOPLEFT) and SetWidth(GUTTER) — no height, no second vertical anchor. Its
-- rect is 88 x 0, and the client does not paint the regions of a frame with no
-- area. Every sibling the player COULD see (name, reason, slot) is owned by the
-- row itself, which has a height.
--
-- WHY THE SUITE STAYED GREEN. Every existing ledger spec asked IsVisible()
-- (all flags true), read the text back (SetText worked), and measured the
-- gutter's WIDTH (88, correct). None asked whether the gutter had a height, and
-- the client model had no notion of "drawn" beyond "shown". The model now has
-- `C.Drawn` (tests/support/wowclient.lua), and this spec asks it of the real
-- rows both tabs build inside the real window.
--
-- TEETH. The checker is first run on a hand-built zero-height gutter, which it
-- must call undrawn, and on the same gutter given a height, which it must call
-- drawn — so a green pass is a statement about the shipped rows, not a checker
-- that agrees with everything.
--
-- PINNING THE GEOMETRY. On 7439f02 the gutter had no height at all; PR #60
-- (#5e10486) gave it one with a second anchor, and the checks above catch a
-- gutter that paints nothing. Review's gate noted four mutations that those
-- checks still let through, because none of them blanks the VERDICT column —
-- the gutter keeps an area and the word keeps painting, and only the INVISIBLE
-- frame lands in the wrong place:
--
--   1. the bottom anchor's offset with its sign flipped   -(PAD_BOTTOM + RULE_H)
--   2. the offset without RULE_H                           PAD_BOTTOM
--   3. the offset zeroed                                   0
--   4. the bottom anchor relative to the LIST, not the row  parent
--
-- So the gutter is measured against the ledger's own edges as well: its bottom
-- edge must be at or above the rule's top edge, it must clear that edge by
-- exactly the row's bottom pad (that number is what mutation 2 changes, and it
-- still ends ABOVE the rule — 1px, not a flip), and its whole rect must sit
-- inside the row's rect (mutations 1 and 4 hang it below the row). Each of the
-- four shapes is built by hand below and must be REJECTED before the real rows
-- are asked; the shipped shape must be accepted. Mutation 4 also teaches the
-- reason the check runs on EVERY row: in the list, the last row's bottom edge
-- coincides with the list's, so that one row measures the same under the
-- mutation. A check that stopped at one row would pass a broken tab.
--
-- Run from the repo root:  lua5.1 tests/touchstone_ledger_gutter_drawn_spec.lua

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

-- Report a list of complaints (see geometryComplaints) as failures, each with
-- its own measured numbers, rather than one opaque "geometry" line.
local function checkProblems(list)
  for _, msg in ipairs(list) do
    failed = failed + 1
    io.stderr:write("FAIL: " .. msg .. "\n")
  end
end

local C = dofile(root .. "/tests/support/wowclient.lua")
C.Install({ width = 1920, height = 1080 })

-- ── 0. The checker has teeth ───────────────────────────────────────────────
do
  local row = CreateFrame("Frame", nil, UIParent)
  row:SetSize(780, 60)
  row:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10)
  local gutter = CreateFrame("Frame", nil, row)
  gutter:SetWidth(88)                       -- the 7439f02 shape: width, no height
  gutter:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -11)
  local mark = gutter:CreateTexture(nil, "OVERLAY")
  mark:SetSize(14, 14)
  mark:SetPoint("TOPLEFT", gutter, "TOPLEFT", 0, 0)
  local word = gutter:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  word:SetPoint("TOPLEFT", gutter, "TOPLEFT", 0, -18)
  word:SetWidth(88)
  word:SetText("Upgrade")
  check(mark:IsVisible() and word:IsVisible(),
    "teeth: the zero-height gutter's regions report IsVisible() true (the blind spot)")
  check(not C.Drawn(mark), "teeth: a texture in a zero-height frame is NOT drawn")
  check(not C.Drawn(word), "teeth: a font string in a zero-height frame is NOT drawn")
  gutter:SetHeight(40)
  check(C.Drawn(mark), "teeth: the same texture IS drawn once its frame has a height")
  check(C.Drawn(word), "teeth: the same word IS drawn once its frame has a height")
  local blank = gutter:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  blank:SetPoint("TOPLEFT", gutter, "TOPLEFT")
  blank:SetWidth(88)
  check(not C.Drawn(blank), "teeth: an empty string draws nothing")
  row:Hide()
end

-- ── The real pack, the real window ─────────────────────────────────────────
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
check(pcall(pkg.EnableModules), "the enabled modules start (as they do at login)")

local W = pkg.Window
local SF = rawget(_G, "StatForge")
local CA = rawget(_G, "ChestAdvisor")
check(type(W) == "table" and type(SF) == "table" and type(CA) == "table",
  "the window, the vendored module and the advisor loaded")
if failed > 0 then os.exit(1) end

-- ── 0b. The GEOMETRY checker, and its teeth ────────────────────────────────
-- The tokens the two tabs read (MightiePackTheme.list — Theme.lua publishes it),
-- with the same literal fallbacks the tabs carry, so this spec states the
-- ledger's numbers rather than numbers of its own.
local THEME = rawget(_G, "MightiePackTheme")
local LIST = (type(THEME) == "table" and type(THEME.list) == "table") and THEME.list or {}
local PAD_TOP    = LIST.padTop or 11
local PAD_BOTTOM = LIST.padBottom or 12
local RULE_H     = LIST.rule or 1
local ROW_INSET  = LIST.inset or 6
local GUTTER     = LIST.gutter or 88
check(type(THEME) == "table" and type(THEME.list) == "table",
  "the pack's theme publishes its list tokens (the ledger's metrics)")

-- Where the ledger says the gutter must sit, as a list of complaints (empty =
-- it sits there). Each complaint carries the numbers it measured, so a failure
-- reads as a measurement and not as an opinion.
local function geometryComplaints(label, row, gutter, rule)
  local out = {}
  local rur, gr, rr = C.Rect(row), C.Rect(gutter), C.Rect(rule)

  -- (a) The gutter's bottom edge is at or above the rule's top edge. The gutter
  -- is invisible; the rule is the ledger's one visible line, so a gutter that
  -- reaches past the rule's top has a region overlapping a drawn edge.
  if gr.bottom < rr.top - 0.05 then
    out[#out + 1] = ("%s: the gutter's bottom (%.1f) is BELOW the rule's top (%.1f)")
      :format(label, gr.bottom, rr.top)
  end

  -- (b) ... and it clears that edge by exactly the row's bottom pad. The second
  -- anchor is PAD_BOTTOM + RULE_H up from the row's bottom and the rule's top
  -- is RULE_H up, so the gap between them IS PAD_BOTTOM. This is the check that
  -- catches an offset that dropped RULE_H: the gutter still ends above the rule
  -- (so (a) holds), one pixel short of where the row's own padding puts it.
  local gap = gr.bottom - rr.top
  if math.abs(gap - PAD_BOTTOM) > 0.05 then
    out[#out + 1] = ("%s: the gutter's bottom clears the rule's top by %.1f, not by the row's bottom pad (%.1f)")
      :format(label, gap, PAD_BOTTOM)
  end

  -- (c) The gutter rect sits INSIDE the row rect. A flipped sign or an anchor
  -- pointed at the list instead of the row hangs the frame below the row (and
  -- past the next one) while still painting its word.
  if gr.left < rur.left - 0.05 or gr.right > rur.right + 0.05
    or gr.top > rur.top + 0.05 or gr.bottom < rur.bottom - 0.05 then
    out[#out + 1] = ("%s: the gutter rect (x %.1f..%.1f, y %.1f..%.1f) is NOT inside the row rect (x %.1f..%.1f, y %.1f..%.1f)")
      :format(label, gr.left, gr.right, gr.top, gr.bottom,
        rur.left, rur.right, rur.top, rur.bottom)
  end

  return out
end

-- A row shaped exactly as the ledger builds one, with the bottom anchor's
-- offset and relative frame as parameters — that is what the four mutations
-- change. `host` stands in for the list the row is stacked in.
local host = CreateFrame("Frame", nil, UIParent)
host:SetSize(780, 400)
host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -20)
local function shapeRow(bottomOffset, bottomRel)
  local row = CreateFrame("Frame", nil, host)
  row:SetSize(780, 60)
  row:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
  local gutter = CreateFrame("Frame", nil, row)
  gutter:SetWidth(GUTTER)
  gutter:SetPoint("TOPLEFT", row, "TOPLEFT", ROW_INSET, -PAD_TOP)
  gutter:SetPoint("BOTTOMLEFT", bottomRel or row, "BOTTOMLEFT", ROW_INSET, bottomOffset)
  local rule = row:CreateTexture(nil, "ARTWORK")
  rule:SetHeight(RULE_H)
  rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", ROW_INSET, 0)
  rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -ROW_INSET, 0)
  rule:SetColorTexture(1, 1, 1, 1)
  return row, gutter, rule
end

-- The shipped shape passes: a checker that rejected everything would prove
-- nothing about the shipped rows.
do
  local row, gutter, rule = shapeRow(PAD_BOTTOM + RULE_H)
  local complaints = geometryComplaints("teeth/shipped", row, gutter, rule)
  check(#complaints == 0,
    ("teeth: the shipped gutter shape passes the geometry checker (%d complaint(s): %s)")
      :format(#complaints, table.concat(complaints, " | ")))
end

-- ... and each of the four mutations Review named is REJECTED, by hand and by
-- name, before any real row is measured.
local MUTANTS = {
  { name = "the offset's sign flipped", offset = -(PAD_BOTTOM + RULE_H) },
  { name = "the offset without RULE_H", offset = PAD_BOTTOM },
  { name = "the offset zeroed", offset = 0 },
  -- The fourth: the same offset, but relative to the LIST (the row's parent)
  -- instead of the row.
  { name = "the bottom anchor on the list instead of the row",
    offset = PAD_BOTTOM + RULE_H, rel = host },
}
for i, m in ipairs(MUTANTS) do
  local row, gutter, rule = shapeRow(m.offset, m.rel)
  local label = ("teeth/mutation %d"):format(i)
  local complaints = geometryComplaints(label, row, gutter, rule)
  check(#complaints > 0,
    ("teeth: mutation %d — %s — is REJECTED (%d complaint(s))"):format(i, m.name, #complaints))
  for _, c in ipairs(complaints) do print("  mutation " .. i .. " rejected: " .. c) end
end

-- The owner's own rows: the Boomstick upgrade from the 7439f02 screenshot, plus
-- one of each other verdict so every mark branch is exercised.
local FIXTURE = {
  ["[Hunter's Boomstick]"] = { verdict = "UPGRADE", id = 2511, slotWord = "ranged",
    reason = "upgrade: more weapon damage per second (5.00 vs 3.00)" },
  ["[Mystic Robe]"] = { verdict = "TRADE_OFF", id = 1003, slotWord = "chest",
    reason = "better on some stats, worse on others" },
  ["[Ragged Gloves]"] = { verdict = "NOT_UPGRADE", id = 1004, slotWord = "hands",
    reason = "not an upgrade" },
}
CA.getVerdicts = function() return FIXTURE end
CA.getLog = function()
  return {
    { at = 1700000000, slot = 16, slotName = "main hand", link = "[Worn Axe]",
      verdict = "NOT_UPGRADE", reason = "you equipped it anyway" },
    { at = 1700000060, slot = 5, slotName = "chest", link = "[Mystic Robe]",
      verdict = "TRADE_OFF", reason = "you equipped it anyway" },
  }
end

check(W.Frame() ~= nil, "the window frame is created")
W.Open("touchstone")

local function rowsOf(prefix)
  local out = {}
  for i = 1, 20 do
    local r = rawget(_G, prefix .. i)
    if type(r) ~= "table" then break end
    out[#out + 1] = r
  end
  return out
end

-- How many rows of each tab the geometry checks actually measured. A tab whose
-- rows were all skipped must not read as a tab that passed.
local geoChecked = { upgrades = 0, log = 0 }

local function checkGutter(tab, label, row, wantMark)
  local g = row.gutter
  check(type(g) == "table", label .. ": the row has a verdict gutter")
  check(type(row.rule) == "table", label .. ": the row has its ledger rule")
  if type(g) ~= "table" or type(row.rule) ~= "table" then return end
  local gr = C.Rect(g)
  check(gr.height > 0, ("%s: the verdict gutter has a height (got %.1f)"):format(label, gr.height))
  local word = row.verdictWord
  local text = word and word:GetText() or ""
  check(text ~= "", label .. ": the verdict word has text")
  local ok, why = C.Drawn(word)
  check(ok, ("%s: the verdict word %q is DRAWN (%s)"):format(label, text, tostring(why)))
  if wantMark then
    local mok, mwhy = C.Drawn(row.mark)
    check(mok, ("%s: the verdict mark is DRAWN (%s)"):format(label, tostring(mwhy)))
  end
  -- The gutter's content must sit inside the gutter's own rect: a gutter that is
  -- tall enough on paper but shorter than the word it holds is the same defect
  -- by a smaller margin.
  local wr = C.Rect(word)
  check(wr.bottom >= gr.bottom - 0.05,
    ("%s: the verdict word ends inside the gutter (word bottom %.1f, gutter bottom %.1f)")
      :format(label, wr.bottom, gr.bottom))
  -- Where the gutter's own rect must sit in the ledger: above the row's rule, its
  -- bottom edge clearing that rule by the row's bottom pad, and the whole rect
  -- inside the row it belongs to. See "PINNING THE GEOMETRY" at the top: the four
  -- mutations Review named keep the word painting and only move this frame.
  checkProblems(geometryComplaints(label, row, g, row.rule))
  geoChecked[tab] = geoChecked[tab] + 1
end

-- ── 1. Upgrades: every drawn row paints its verdict ────────────────────────
if type(SF.SelectTab) == "function" then pcall(SF.SelectTab, "upgrades") end
local up = rowsOf("TouchstoneUpgradeRow")
check(#up == 3, "the Upgrades tab built one row per verdict (got " .. #up .. ")")
local sawBoomstick = false
for i, row in ipairs(up) do
  if row:IsVisible() then
    local name = row.itemName and row.itemName:GetText() or ("row " .. i)
    if name == "Hunter's Boomstick" then
      sawBoomstick = true
      check(row.verdictWord:GetText() == "Upgrade",
        "the Boomstick row's word is Upgrade (got " .. tostring(row.verdictWord:GetText()) .. ")")
      check(row.mark:GetTexture() ~= nil, "the Boomstick row's mark is the marker texture")
    end
    local wantMark = (name == "Hunter's Boomstick" or name == "Mystic Robe")
    checkGutter("upgrades", "Upgrades/" .. name, row, wantMark)
  end
end
check(sawBoomstick, "the Boomstick row is on the page")
-- Every row, not just a sample: mutation 4 measures identically on the list's
-- LAST row (its bottom edge is the list's), so a check that stopped early would
-- pass a tab whose other rows are all hung below their rules.
check(geoChecked.upgrades == #up,
  ("every Upgrades row was geometry-checked (%d of %d)"):format(geoChecked.upgrades, #up))

-- ── 2. Log: the word is the statement, so it must paint ────────────────────
-- LogTab.lua's own note: "most rows have no marker glyph — the verdict word
-- alone is the statement". An empty VERDICT column on a log row is therefore
-- not by design: it is this same defect.
if type(SF.SelectTab) == "function" then pcall(SF.SelectTab, "log") end
local log = rowsOf("TouchstoneLogRow")
check(#log == 2, "the Log tab built one row per entry (got " .. #log .. ")")
for i, row in ipairs(log) do
  if row:IsVisible() then
    local name = row.itemName and row.itemName:GetText() or ("row " .. i)
    checkGutter("log", "Log/" .. name, row, name == "Mystic Robe")
  end
end
check(geoChecked.log == #log,
  ("every Log row was geometry-checked (%d of %d)"):format(geoChecked.log, #log))
check(geoChecked.upgrades > 0 and geoChecked.log > 0,
  ("both tabs were geometry-checked (upgrades %d, log %d)")
    :format(geoChecked.upgrades, geoChecked.log))

if failed > 0 then
  io.stderr:write(("touchstone_ledger_gutter_drawn_spec: %d failure(s)\n"):format(failed))
  os.exit(1)
end
print("touchstone_ledger_gutter_drawn_spec: ok")

-- t_f4ff9ea6 — the herb block lives in a panel of NodeTrail's OWN, not inside
-- Blizzard's tooltip.
--
-- Three in-tooltip attempts failed the same way on the live client: the tooltip
-- sizes its backdrop at SHOW time and re-derives it on every show, so lines
-- added afterwards end up on no background at all (or clipped mid-word), and
-- nothing the addon writes survives. This spec pins the replacement:
--
--   * the panel is built and positioned from a fake tooltip's rect;
--   * six hovers of the SAME herb, plus a font change and a scale change, and
--     the panel's width is ALWAYS at least as wide as its widest line;
--   * the block is rebuilt from scratch, so six hovers produce six identical
--     blocks, never a duplicate;
--   * nothing is written into the tooltip (a proxy that raises on any write
--     drives the whole run);
--   * a long line wraps at `, ` under the ~45%-of-screen cap, while a drop row's
--     "100% (base)" stays whole and stays with its item name.
--
-- Not loaded by the addon TOC.
local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. msg .. "\n")
  end
end

local F = dofile(root .. "/tests/support/fakeui.lua")
local SCREEN_W, SCREEN_H = F.install({ width = 1920, height = 1080 })

-- ── client stubs the module graph expects ─────────────────────────────────
time = time or os.time
CopyTable = function(t)
  local c = {}
  for k, v in pairs(t) do
    c[k] = type(v) == "table" and CopyTable(v) or v
  end
  return c
end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
GetSpellInfo = function(id)
  local map = { [2366] = "Herb Gathering", [2259] = "Alchemy" }
  return map[id]
end
UnitExists = function() return false end
SlashCmdList = {}

-- t_d4848ce0: the herb block is gated on the character's profession, so the
-- fixture character has to BE an herbalist — the client's skill lines say so.
-- (Documented GetSkillLineInfo shape: name, isHeader, isExpanded, skillRank.)
local skillLines = {
  { name = "Herbalism", rank = 300 },
  { name = "Alchemy", rank = 300 },
}
GetNumSkillLines = function() return #skillLines end
GetSkillLineInfo = function(i)
  local row = skillLines[i]
  if not row then return nil end
  return row.name, false, true, row.rank
end

local pkg = {}
local function loadFile(path)
  local f = assert(loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. path))
  f("MightiePack", pkg)
end

loadFile("locale/enUS.lua")
loadFile("Config.lua")
loadFile("Data/ItemNames.lua")
loadFile("Data/Recorder.lua")
loadFile("Data/HerbData.lua")
loadFile("Data/Profession.lua")
loadFile("Data/Recipes.lua")
loadFile("UI/TooltipPanel.lua")
loadFile("UI/Tooltip.lua")
loadFile("Core.lua")

local ns = pkg.NodeTrail
local P = ns.TooltipPanel
local T = ns.Tooltip

NodeTrailDB = { recipes = {}, profile = {}, herbs = { schema = 1, total = 0, maps = {} } }

-- The width the fake client gives a string at the tooltip's font size.
local function textWidth(s, size)
  return #tostring(s) * (size or F.defaultFontSize) * F.charWidth
end

-- ── T1: the panel is ours, created lazily, drawn with plain textures ──────
check(P ~= nil, "T1: UI/TooltipPanel.lua defines ns.TooltipPanel")
check(P.frame == nil, "T1: no frame exists before the first herb hover")
local tip = F.newTooltip({ lines = { "Peacebloom", "Herbalism" }, owner = UIParent,
  left = 100, bottom = 400, width = 180, height = 60 })
local info = P:Update({ { left = "Peacebloom", right = "100% (base)" },
  { left = "Your picks: none yet" } }, tip)
check(P.frame ~= nil, "T1: the first update creates the panel frame")
check(P.frame and P.frame.name == "NodeTrailHerbPanel", "T1: the frame carries our own name")
check(P.frame and P.frame.parent == UIParent, "T1: the frame is parented to UIParent, not the tooltip")
check(P.frame and P.frame.strata == "TOOLTIP", "T1: the panel sits in the TOOLTIP strata")
local texCount = P.frame and #P.frame.textures or 0
check(P.frame and texCount == 5,
  "T1: one background + four 1px border textures (got " .. texCount .. ")")
local bg = P.frame and P.frame.textures[1]
check(bg and bg.color and bg.color[4] and bg.color[4] > 0.5, "T1: the background is a filled dark texture")
check(P.backdropAPI and P.backdropAPI:find("absent", 1, true) ~= nil,
  "T1: SetBackdrop is measured as absent on this client and never used (got " .. tostring(P.backdropAPI) .. ")")
check(info.shown == true, "T1: the panel is shown for a herb block")

-- ── T2: below the tooltip, left edge aligned, width from OUR lines ────────
local widest = math.max(textWidth("Peacebloom") + P.COL_GAP + textWidth("100% (base)"),
  textWidth("Your picks: none yet"))
check(P.width >= widest, ("T2: panel width %.1f >= widest line %.1f"):format(P.width, widest))
check(P.rect and math.abs(P.rect.left - 100) < 0.01,
  ("T2: left edge tracks the tooltip's left (got %.1f)"):format(P.rect and P.rect.left or -1))
check(P.rect and math.abs(P.rect.top - (400 - P.TOOLTIP_GAP)) < 0.01,
  ("T2: top edge sits just below the tooltip's bottom (got %.1f)"):format(P.rect and P.rect.top or -1))
check(P.placement == "below", "T2: placement is below the tooltip while there is room")
-- Every rendered row is ANCHORED: an unanchored font string lands at the frame
-- centre on this client, which is an unreadable pile, not a block.
local anchoredRows, rightRows = 0, 0
for i, row in ipairs(P._pool) do
  if row.left and row.left.points and #row.left.points == 1 then
    anchoredRows = anchoredRows + 1
  end
  if row.right and row.right.points and #row.right.points == 1
    and row.right.points[1].relativePoint == "TOPRIGHT" then
    rightRows = rightRows + 1
  end
end
check(anchoredRows >= 1 and anchoredRows == #P:TextLines(),
  ("T2: every row's left column is anchored (got %d of %d)"):format(anchoredRows, #P:TextLines()))
check(rightRows >= 1, "T2: the percentage column is anchored to the panel's right edge")

-- ── T2b: the font the panel MEASURES with is the font it DRAWS with ───────
-- A font string created with no font object reports no width and no height on
-- the client, so a panel that creates its rows after adopting the tooltip font
-- sizes itself from zeros on the very first hover and the text then grows
-- outside its own background. Every row must carry a font in the very update
-- that set P.width, and the width must cover an INDEPENDENT measurement.
local fontless = 0
for _, row in ipairs(P._pool) do
  for _, fs in ipairs({ row.left, row.right }) do
    if type(fs) == "table" then
      local okF, path, size = pcall(fs.GetFont, fs)
      if not okF or type(path) ~= "string" or type(size) ~= "number" then
        fontless = fontless + 1
      end
    end
  end
end
check(fontless == 0, "T2b: every row carries a font in the update that sized the panel (got "
  .. fontless .. " fontless)")
check(type(P.widestMeasured) == "number",
  "T2b: the panel records an independent (meter) measurement for /nt ttdiag")
check(P.covers == true, "T2b: the panel reports that it covers its widest line")
-- The floor the width was raised by is part of that report: a herb block has
-- no raw (client-text) row, so the floor is 0 and /nt ttdiag must be able to
-- say so — an absent figure would be indistinguishable from an unapplied one.
local dT2 = P:Diag()
check(type(dT2.rawFloor) == "number" and dT2.rawFloor == 0,
  "T2b: no client-text row means no width floor, reported as 0 (got "
  .. tostring(dT2.rawFloor) .. ")")

-- ── T3: no room underneath -> the panel goes ABOVE the tooltip ────────────
local lowTip = F.newTooltip({ lines = { "Peacebloom", "Herbalism" }, owner = UIParent,
  left = 100, bottom = 20, width = 180, height = 60 })
P:Update({ { left = "Peacebloom", right = "100% (base)" } }, lowTip)
check(P.placement == "above", "T3: placement flips above when the bottom edge is near")
check(P.rect and math.abs(P.rect.bottom - (80 + P.TOOLTIP_GAP)) < 0.01,
  ("T3: the panel's bottom sits just above the tooltip's top (got %.1f)"):format(P.rect and P.rect.bottom or -1))

-- ── T4: near the right edge -> clamped into the screen ───────────────────
local rightTip = F.newTooltip({ lines = { "Peacebloom", "Herbalism" }, owner = UIParent,
  left = SCREEN_W - 40, bottom = 700, width = 180, height = 60 })
P:Update({ { left = "Peacebloom", right = "100% (base)" } }, rightTip)
check(P.clamped and P.clamped.x == true, "T4: a panel past the right edge is reported as clamped")
check(P.rect and P.rect.right <= SCREEN_W - P.SCREEN_MARGIN + 0.01,
  ("T4: the panel's right edge stays inside the margin (R=%.1f, screen=%d)"):format(
    P.rect and P.rect.right or -1, SCREEN_W))
local leftTip = F.newTooltip({ lines = { "Peacebloom", "Herbalism" }, owner = UIParent,
  left = -50, bottom = 400, width = 180, height = 60 })
P:Update({ { left = "Peacebloom", right = "100% (base)" } }, leftTip)
check(P.rect and P.rect.left >= P.SCREEN_MARGIN - 0.01,
  ("T4: a panel past the left edge is pulled inside (L=%.1f)"):format(P.rect and P.rect.left or -1))

-- ── T5: SIX hovers of the same herb — identical block, width never short ──
local herbTip = F.newTooltip({ lines = { "Mageroyal", "Herbalism" }, owner = UIParent,
  left = 320, bottom = 720, width = 180, height = 60 })
local frameBefore = P.frame
local firstLines, counts, worstWidth, worstGap = nil, {}, 1 / 0, 0
for i = 1, 6 do
  T:Refresh(herbTip, "poll")
  local lines = P:TextLines()
  if i == 1 then
    firstLines = lines
  else
    local same = #lines == #firstLines
    if same then
      for k = 1, #lines do
        if lines[k] ~= firstLines[k] then same = false end
      end
    end
    check(same, ("T5: hover %d renders exactly the same rows as the first (no duplicates)"):format(i))
  end
  counts[i] = #lines
  local w = P.widest or 0
  if P.width < w then worstWidth = P.width end
  worstGap = math.max(worstGap, w - P.width)
  check(P.width >= w - 0.01, ("T5: hover %d width %.1f >= widest %.1f"):format(i, P.width, w))
  check(type(P.widestMeasured) == "number"
    and P.width + 0.01 >= P.widestMeasured + 2 * P.PAD_X,
    ("T5: hover %d panel %.1f covers the independent measurement %.1f + padding"):format(
      i, P.width, P.widestMeasured or -1))
end
check(P.frame == frameBefore, "T5: six hovers reuse the one panel frame (no second frame was created)")
check(#P.frame.textures == 5 and #P.frame.fontStrings >= 2,
  "T5: six hovers do not multiply the panel's regions")
check(#firstLines >= 3, "T5: the block has at least three rows (got " .. #firstLines .. ")")
local joined = table.concat(firstLines, "\n")
check(joined:find("Mageroyal | 100% (base)", 1, true) ~= nil,
  "T5: the drop row keeps its complete percentage (got " .. joined:gsub("\n", " / ") .. ")")
check(joined:find("Swiftthistle | 10% (base)", 1, true) ~= nil,
  "T5: the second drop row is complete too (got " .. joined:gsub("\n", " / ") .. ")")
check(#P:TextLines() == #firstLines, "T5: the row count after six hovers equals the first hover's")

-- ── T6: a font change re-measures every line ──────────────────────────────
local wideBefore = P.width
herbTip.fontSize = 20
herbTip.lineFont.size = 20
herbTip:SyncFirstLine()
T:Refresh(herbTip, "poll")
local wideSize = herbTip.lineFont.size
local widestAt20 = 0
for _, l in ipairs(P:TextLines()) do
  local w = textWidth(l)
  if w > widestAt20 then widestAt20 = w end
end
check(P.fontSig and P.fontSig:find("20", 1, true) ~= nil,
  "T6: the panel adopted the tooltip's new font size (sig=" .. tostring(P.fontSig) .. ")")
local widthAt20 = P.width
check(P.width > wideBefore, ("T6: a bigger font widens the panel (%.1f -> %.1f)"):format(wideBefore, P.width))
check(P.width + 0.01 >= widestAt20,
  ("T6: width %.1f still covers the widest line at font %s (%.1f)"):format(P.width, tostring(wideSize), widestAt20))

-- ── T7: a scale change is accounted for in the cap, not ignored ───────────
herbTip:SetScale(0.75)
T:Refresh(herbTip, "poll")
check(P.frame and math.abs(P.frame.scale - 0.75) < 0.001,
  "T7: the panel adopts the tooltip's scale")
check(P.capScreen and math.abs(P.capScreen - SCREEN_W * P.CAP_FRACTION) < 0.01,
  ("T7: the width budget is 45%% of the screen (%.1f)"):format(P.capScreen or -1))
check(P.width + 0.01 >= (P.widest or 0), "T7: width still covers the widest line after the scale change")
herbTip:SetScale(1)

-- ── T7b: a SCALED UI must not double the scale ───────────────────────────
-- The panel is parented to UIParent, so it already inherits UIParent's scale.
-- Copying the tooltip's ABSOLUTE scale onto it would square the UI scale and the
-- panel's text would be a different size from the tooltip's.
F.screen:SetScale(0.75)
herbTip:SetScale(0.75)
P:Update({ { left = "Mageroyal", right = "100% (base)" } }, herbTip)
check(P.frame and math.abs(P.frame.scale - 1) < 0.001,
  ("T7b: on a UI scaled to 0.75 the panel's LOCAL scale is 1, not 0.75 (got %.3f)")
    :format(P.frame and P.frame.scale or -1))
check(P.rect and math.abs((P.rect.right - P.rect.left) - P.width) < 0.01,
  "T7b: the panel's screen width equals its local width at that scale")
F.screen:SetScale(1)
herbTip:SetScale(1)

-- ── T8: a long alchemy line wraps at `, ` under the cap ───────────────────
herbTip.fontSize = 12
herbTip.lineFont.size = 12
herbTip:SyncFirstLine()
local longLine = "Alchemy: Elixir of Lion's Strength, Minor Healing Potion, Swiftness Potion, "
  .. "Elixir of Minor Defense, Lesser Mana Potion, Elixir of Fortitude, "
  .. "Potion of Lesser Agility, +2 more"
local cap = SCREEN_W * P.CAP_FRACTION
check(textWidth(longLine) > cap * 1.05,
  ("T8: the fixture line is longer than the cap (%.1f > %.1f), else the test proves nothing"):format(
    textWidth(longLine), cap))
P:Update({
  { left = "Mageroyal", right = "100% (base)" },
  { left = "Swiftthistle", right = "10% (base)" },
  { left = "Your picks: 5" },
  { left = longLine },
}, herbTip)
local rows = P:TextLines()
check(#rows > 4, "T8: the long line became more than one row (got " .. #rows .. " rows)")
-- The alchemy group: the first row that opens with the label, then every
-- indented row after it until a row that is not indented.
local alchemyStart, alchemyRows = nil, 0
for i, l in ipairs(rows) do
  if alchemyStart == nil and l:find("^Alchemy: ", 1) then
    alchemyStart = i
  elseif alchemyStart ~= nil and l:find("^  ") then
    alchemyRows = alchemyRows + 1
  end
end
check(alchemyStart ~= nil, "T8: the alchemy row is present")
check(alchemyRows >= 1,
  "T8: the long alchemy line is continued on indented rows (got " .. alchemyRows .. " continuation row(s))")
check(rows[1] == "Mageroyal | 100% (base)",
  "T8: \"100% (base)\" is never split from its item name (row 1 is \"" .. tostring(rows[1]) .. "\")")
check(rows[2] == "Swiftthistle | 10% (base)", "T8: the second drop row is intact")
-- Every row of the alchemy group fits the cap; the drop rows are atomic rows
-- and are covered by the panel width instead.
for i = alchemyStart, #rows do
  local w = textWidth(rows[i])
  check(w <= cap + 0.01, ("T8: alchemy row %d fits the cap (%.1f <= %.1f): %s"):format(i, w, cap, rows[i]))
end
check(rows[alchemyStart]:sub(-1) == ",", "T8: the first chunk ends on a `, ` boundary (row ends with \""
  .. tostring(rows[alchemyStart]:sub(-1)) .. "\")")
check(rows[alchemyStart]:sub(1, 9) == "Alchemy: ",
  "T8: the continuation does not repeat the label (row is \"" .. tostring(rows[alchemyStart]) .. "\")")
check(P.width + 0.01 >= (P.widest or 0),
  ("T8: width %.1f covers the widest row after wrapping (%.1f)"):format(P.width, P.widest or 0))

-- ── T8b: a client that measures NOTHING must make the verdict say NO ─────
-- The card exists because this client's geometry does not follow our writes,
-- and the same client can report 0 for every string. A verdict built from the
-- row width would then say "text 12, covered" — 12 px being only the column
-- gap — with no glyph measured, and the live six-hover report would prove
-- nothing. `covers` is built from measured TEXT and refuses to say yes when a
-- text-bearing row measured 0.
local measureTip = F.newTooltip({ lines = { "Mageroyal", "Herbalism" }, owner = UIParent,
  left = 320, bottom = 720, width = 180, height = 60 })
F.blindMeasure = true
local blindInfo = P:Update({
  { left = "Mageroyal", right = "100% (base)" },
  { left = "Your picks: 5" },
}, measureTip)
check(blindInfo.covers == false,
  "T8b: an update that measured no text reports covers=false (got "
    .. tostring(blindInfo.covers) .. ")")
check(P.covers == false,
  "T8b: the panel's own verdict is false when a text-bearing row measured 0")
check(blindInfo.widestTextPx == 0,
  "T8b: the measured text width is 0 on a blind client (got "
    .. tostring(blindInfo.widestTextPx) .. ")")
local blindChat = {}
local savedChat = DEFAULT_CHAT_FRAME
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) blindChat[#blindChat + 1] = msg end }
local okBlindDiag, errBlindDiag = pcall(T.Diag, T)
DEFAULT_CHAT_FRAME = savedChat
local blindOut = table.concat(blindChat, "\n")
check(okBlindDiag, "T8b: ttdiag does not raise on a blind client (" .. tostring(errBlindDiag) .. ")")
check(blindOut:find("covers its widest line=NO", 1, true) ~= nil,
  "T8b: ttdiag says the panel does NOT cover its widest line (got:\n" .. blindOut .. ")")
check(blindOut:find("text 0", 1, true) ~= nil,
  "T8b: ttdiag prints the measured-text figure (0) next to the panel width (got:\n" .. blindOut .. ")")
check(blindOut:find("measured 0", 1, true) ~= nil,
  "T8b: ttdiag names the row that measured 0 (got:\n" .. blindOut .. ")")
-- The same block, on a client that can measure again, must still cover: the
-- verdict is a measurement, not a hard-coded NO.
F.blindMeasure = false
P:Update({
  { left = "Mageroyal", right = "100% (base)" },
  { left = "Your picks: 5" },
}, measureTip)
check(P.covers == true, "T8b: the same block covers once the client measures again")

-- ── T9: NOTHING is written into the tooltip ───────────────────────────────
local guardTip, writes = F.readOnly(F.newTooltip({
  lines = { "Peacebloom", "Herbalism" }, owner = UIParent,
  left = 200, bottom = 500, width = 180, height = 60,
}), "GameTooltip")
local okWrite, errWrite = pcall(T.Refresh, T, guardTip, "poll")
check(okWrite, "T9: a refresh against a write-hostile tooltip does not raise (" .. tostring(errWrite) .. ")")
check(#writes == 0,
  "T9: zero field writes to the tooltip (got " .. #writes .. ": " .. table.concat(writes, ", ") .. ")")

-- ── T10: not ours -> the panel hides, and nothing lingers ────────────────
local veinTip = F.newTooltip({ lines = { "Copper Vein", "Mining" }, owner = UIParent,
  left = 200, bottom = 500, width = 180, height = 60 })
T:Refresh(veinTip, "poll")
check(P:IsShown() == false, "T10: the panel hides for a node that is not ours")

-- ── T11: unreadable tooltip geometry -> built, but never placed blind ────
local blindTip = F.newTooltip({ lines = { "Peacebloom", "Herbalism" }, owner = UIParent })
blindTip.GetLeft, blindTip.GetRight = nil, nil
blindTip.GetTop, blindTip.GetBottom = nil, nil
blindTip.GetWidth, blindTip.GetHeight = nil, nil
local blindInfo = P:Update({ { left = "Peacebloom", right = "100% (base)" } }, blindTip)
check(blindInfo.shown == false and type(blindInfo.skip) == "string"
  and blindInfo.skip:find("unreadable", 1, true) ~= nil,
  "T11: with no readable rect the panel is NOT shown, and says why ("
    .. tostring(blindInfo.skip) .. ")")

-- ── T12: no module error anywhere ─────────────────────────────────────────
check(T._error == nil, "T12: ns.Tooltip recorded no error (" .. tostring(T._error) .. ")")
check(P._error == nil, "T12: the panel recorded no error (" .. tostring(P._error) .. ")")

if failed > 0 then
  io.stderr:write(failed .. " tooltip-panel check(s) failed\n")
  os.exit(1)
end
print(("tooltip_panel_spec: ok (width after six hovers %.1fpx, at font 20 %.1fpx, cap %.1fpx)"):format(
  wideBefore, widthAt20, SCREEN_W * P.CAP_FRACTION))

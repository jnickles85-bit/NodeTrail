-- window_summary_strip_spec.lua — card t_07f778ca, PART B3.
--
-- The strip under the tab bar is V4's line drawn in V1's language: ONE line
--   "2 of 5 are worth taking     1 trade-off · 2 refused"
-- with the count in the upgrade colour, over a 3px meter segmented in the three
-- verdict colours by proportion.
--
-- Its whole value is that it is TRUE: the counts must come from the advisor's
-- own verdict list, on every activation and every refresh, or the strip is
-- decoration that will one day contradict the list under it.
--
-- Legs:
--   1. THREE FIXTURES — all upgrades, none, mixed — with the counts, the words
--      and the meter segments checked against the list itself.
--   2. THE METER'S SEGMENTS sum to the row count (and to the meter's width),
--      segment by segment, in the three verdict colours.
--   3. THE EMPTY LIST renders without error: "0 of 0 are worth taking", an
--      empty meter, and no divide-by-zero (checked by the strip rendering at
--      all — a NaN would come back as a width of nan and land below).
--   4. IT IS LIVE, not painted once: changing the list and repainting changes
--      the words. A hardcoded strip passes every fixture in leg 1 only if the
--      fixtures happen to be in order; this leg makes the order irrelevant.
--
-- Harness: tests/support/wowclient.lua, the real pack, and a stubbed verdict
-- list (the advisor's own return shape: { verdict = "UPGRADE" | "TRADE_OFF" |
-- "NOT_UPGRADE" }).

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
check(pcall(pkg.EnableModules), "the enabled modules start (as they do at login)")

local W, T = pkg.Window, pkg.Theme
check(type(W) == "table" and type(T) == "table", "the window and the theme exist")
check(type(W.Frame()) == "table", "the window frame is created")

local CA = rawget(_G, "ChestAdvisor")
check(type(CA) == "table", "the advisor is loaded (its verdict list is the source)")
local realGet = CA and CA.getVerdicts

-- ── Fixtures ───────────────────────────────────────────────────────────────
-- THE SHAPE IS THE ADVISOR'S, not a convenience: ChestAdvisor.getVerdicts()
-- returns a table KEYED BY ITEM LINK. A fixture in array form would let a strip
-- that walks the list with ipairs() pass every leg here and print "0 of 0" in
-- the client over a full list — which is exactly what the first draft of this
-- strip did. So the fixtures are keyed, and leg 4 re-checks the keyed shape.
local fixtureLinks = 0
local function listOf(upgrade, tradeoff, refused)
  local out = {}
  fixtureLinks = 0
  local function put(row)
    fixtureLinks = fixtureLinks + 1
    out["[Fixture Item " .. fixtureLinks .. "]"] = row
  end
  for i = 1, (upgrade or 0) do put({ verdict = "UPGRADE", reason = "u" .. i }) end
  for i = 1, (tradeoff or 0) do put({ verdict = "TRADE_OFF", reason = "t" .. i }) end
  for i = 1, (refused or 0) do put({ verdict = "NOT_UPGRADE", reason = "n" .. i }) end
  return out
end

local function useList(list)
  CA.getVerdicts = function() return list end
  return W.PaintStatus() and W.summary
end

local function textOf(fs)
  local ok, t = pcall(fs.GetText, fs)
  return ok and t or nil
end

--- The colour the count is drawn in must be the upgrade token, not "some green".
local function countColourIsToken()
  local ok, r, g, b, a = pcall(W.summaryCount.GetTextColor, W.summaryCount)
  if not ok or type(r) ~= "number" then return false, "no colour recorded" end
  local tr, tg, tb, ta = T.R("ledgerUpgrade")
  return (math.abs(r - tr) < 1e-6 and math.abs(g - tg) < 1e-6 and math.abs(b - tb) < 1e-6),
    ("(%.3f %.3f %.3f) vs token (%.3f %.3f %.3f)"):format(r, g, b, tr, tg, tb)
end

local function meterWidth()
  return C.Rect(W.summaryMeter).width
end

-- ── 1 + 2. Three fixtures: counts, words, and the meter's proportions ──────
local fixtures = {
  { name = "all upgrades", list = listOf(3, 0, 0), worth = 3, total = 3, trade = 0, refused = 0,
    count = "3", rest = " of 3 are worth taking", right = "0 trade-offs · 0 refused" },
  { name = "none", list = {}, worth = 0, total = 0, trade = 0, refused = 0,
    count = "0", rest = " of 0 are worth taking", right = "0 trade-offs · 0 refused" },
  { name = "mixed", list = listOf(2, 1, 2), worth = 2, total = 5, trade = 1, refused = 2,
    count = "2", rest = " of 5 are worth taking", right = "1 trade-off · 2 refused" },
}

local width = meterWidth()
check(width > 0, "the meter has a width to segment (" .. tostring(width) .. ")")

for _, fx in ipairs(fixtures) do
  local s = useList(fx.list)
  check(type(s) == "table", fx.name .. ": the strip painted a summary")
  if type(s) == "table" then
    check(s.total == fx.total, ("%s: total is the list's length (%d, expected %d)")
      :format(fx.name, s.total, fx.total))
    check(s.worth == fx.worth, ("%s: worth taking (%d, expected %d)"):format(fx.name, s.worth, fx.worth))
    check(s.tradeoff == fx.trade, ("%s: trade-offs (%d, expected %d)"):format(fx.name, s.tradeoff, fx.trade))
    check(s.refused == fx.refused, ("%s: refused (%d, expected %d)"):format(fx.name, s.refused, fx.refused))
    check(s.upgrade + s.tradeoff + s.refused == s.total,
      fx.name .. ": the three parts add up to the whole (" ..
        s.upgrade .. "+" .. s.tradeoff .. "+" .. s.refused .. " vs " .. s.total .. ")")
  end

  check(textOf(W.summaryCount) == fx.count,
    ("%s: the count reads %q (got %q)"):format(fx.name, fx.count, tostring(textOf(W.summaryCount))))
  check(textOf(W.summaryLine) == fx.rest,
    ("%s: the line reads %q (got %q)"):format(fx.name, fx.rest, tostring(textOf(W.summaryLine))))
  check(textOf(W.summaryDetail) == fx.right,
    ("%s: the right-hand pair reads %q (got %q)"):format(fx.name, fx.right, tostring(textOf(W.summaryDetail))))

  -- The meter: one segment per verdict colour, proportional, summing to the
  -- meter's own width.
  local segs = W.summarySegments
  local got = {
    upgrade = C.Rect(segs.upgrade).width,
    tradeoff = C.Rect(segs.tradeoff).width,
    noupgrade = C.Rect(segs.noupgrade).width,
  }
  local sum = got.upgrade + got.tradeoff + got.noupgrade
  if fx.total == 0 then
    -- An empty list draws an EMPTY meter; leg 3 checks that directly.
    check(sum == 0, fx.name .. ": the empty meter draws nothing (got " .. tostring(sum) .. ")")
  else
    check(math.abs(sum - width) < 0.01,
      ("%s: the three segments fill the meter (%.2f of %.2f)"):format(fx.name, sum, width))
  end
  if fx.total > 0 then
    check(math.abs(got.upgrade - (fx.worth / fx.total) * width) < 0.01,
      ("%s: the upgrade segment is its share of the rows (%.2f, expected %.2f)")
        :format(fx.name, got.upgrade, (fx.worth / fx.total) * width))
    check(math.abs(got.tradeoff - (fx.trade / fx.total) * width) < 0.01,
      ("%s: the trade-off segment is its share (%.2f, expected %.2f)")
        :format(fx.name, got.tradeoff, (fx.trade / fx.total) * width))
    check(math.abs(got.noupgrade - (fx.refused / fx.total) * width) < 0.01,
      ("%s: the no-upgrade segment is its share (%.2f, expected %.2f)")
        :format(fx.name, got.noupgrade, (fx.refused / fx.total) * width))
  end
  -- A segment is in its own verdict colour.
  local function segIs(token, tex)
    local got2 = tex.colorTexture
    if type(got2) ~= "table" then return false end
    local r, g, b = T.R(token)
    return got2[1] == r and got2[2] == g and got2[3] == b
  end
  check(segIs("ledgerUpgrade", segs.upgrade), fx.name .. ": the upgrade segment is the upgrade token")
  check(segIs("ledgerTradeoff", segs.tradeoff), fx.name .. ": the trade-off segment is the trade-off token")
  check(segIs("ledgerNoUpgrade", segs.noupgrade), fx.name .. ": the refused segment is the no-upgrade token")
end

-- ── 3. The empty list: 0 of 0, an empty meter, no divide-by-zero ───────────
local emptyOk, emptySummary = pcall(function() return useList({}) end)
check(emptyOk, "an empty list renders without error: " .. tostring(emptySummary))
if emptyOk and type(emptySummary) == "table" then
  check(emptySummary.worth == 0 and emptySummary.total == 0,
    "the empty list is 0 of 0")
  local up = C.Rect(W.summarySegments.upgrade).width
  local tr = C.Rect(W.summarySegments.tradeoff).width
  local no = C.Rect(W.summarySegments.noupgrade).width
  check(up == 0 and tr == 0 and no == 0,
    ("the empty meter is empty (%.2f %.2f %.2f)"):format(up, tr, no))
  -- A NaN width is not 0 and would have failed the line above; this names it.
  check(up == up and tr == tr and no == no, "no segment width is NaN")
end
-- And the pure function, called with a zero denominator directly.
local w0 = W.SummaryMeter({ total = 0, upgrade = 0, tradeoff = 0, refused = 0 }, 400)
check(w0.upgrade == 0 and w0.tradeoff == 0 and w0.noupgrade == 0,
  "SummaryMeter({total=0}, width) is all zeroes, not NaN")
local w1 = W.SummaryMeter({ total = 4, upgrade = 1, tradeoff = 1, refused = 2 }, 400)
check(math.abs((w1.upgrade + w1.tradeoff + w1.noupgrade) - 400) < 0.001,
  "SummaryMeter's segments always sum to the width (got "
    .. tostring(w1.upgrade + w1.tradeoff + w1.noupgrade) .. ")")

-- ── 4. LIVE, not painted once ─────────────────────────────────────────────
useList(listOf(1, 0, 0))
local before = textOf(W.summaryCount) .. "|" .. textOf(W.summaryDetail)
useList(listOf(0, 0, 7))
local after = textOf(W.summaryCount) .. "|" .. textOf(W.summaryDetail)
check(before ~= after,
  ("the strip follows the list (%s -> %s)"):format(before, after))
check(textOf(W.summaryCount) == "0" and (textOf(W.summaryDetail) or ""):find("7 refused", 1, true) ~= nil,
  "the second list's own numbers are on the strip (got "
    .. tostring(textOf(W.summaryDetail)) .. ")")

-- The KEYED shape is the one the client hands over. A list with no array part
-- (only link keys) must count, or the strip lies on every real login.
local keyed = { ["[A]"] = { verdict = "UPGRADE" }, ["[B]"] = { verdict = "UPGRADE" },
                ["[C]"] = { verdict = "NOT_UPGRADE" } }
check(#keyed == 0, "precondition: the fixture has no array part (the advisor's own shape)")
local s = useList(keyed)
check(type(s) == "table" and s.total == 3 and s.worth == 2,
  ("a link-keyed verdict table is counted (%s of %s)")
    :format(tostring(s and s.worth), tostring(s and s.total)))

-- The count carries the colour: that is what makes the number the eye lands on.
local sameColour, detail = countColourIsToken()
check(sameColour, "the count is drawn in the upgrade token " .. tostring(detail))

if type(CA) == "table" and realGet then CA.getVerdicts = realGet end

if failed == 0 then
  print("window_summary_strip_spec: ok")
else
  print(("window_summary_strip_spec: %d failure(s)"):format(failed))
  os.exit(1)
end

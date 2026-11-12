-- route_style_spec.lua — audit §2.2 geometry: segments, stop-preserving
-- smoothing, chevron spacing, and decor pool reuse counts.
--
-- Pure Lua, no WoW calls. The live client draws with two-corner-anchored
-- textures; these helpers are what the drawers ask for before they paint.
local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."
local ns = {}
local chunk, err = loadfile(root .. "/MightiePack/Modules/NodeTrail/UI/PathGeom.lua")
assert(chunk, err)
chunk("MightiePack", { NodeTrail = ns })
local G = ns.PathGeom

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. msg .. "\n")
  end
end
local function near(a, b, msg, tol)
  tol = tol or 1e-6
  check(type(a) == "number" and math.abs(a - b) <= tol,
    msg .. " got " .. tostring(a) .. " expected " .. tostring(b))
end

-- ── 1. Segments ──────────────────────────────────────────────────────
local segs, n = G.Segments({ { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 1, y = 1 } })
check(n == 2, "1: two non-degenerate spans (got " .. tostring(n) .. ")")
near(segs[1][1], 0, "1: first x1")
near(segs[1][3], 1, "1: first x2")
near(segs[2][2], 0, "1: second y1")
near(segs[2][4], 1, "1: second y2")
local reused = segs
local _, n2 = G.Segments({ { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 2, y = 0 } }, reused)
check(n2 == 1, "1: zero-length span is skipped (got " .. tostring(n2) .. ")")
check(reused == segs, "1: Segments reuses the out array")
check(reused[2] == nil, "1: leftover slots are cleared")

-- ── 2. SmoothPreserve keeps stops exact ──────────────────────────────
local stops = {
  { x = 0, y = 0, stop = true },
  { x = 1, y = 0, stop = true },
  { x = 1, y = 1, stop = true },
}
local smo = G.SmoothPreserve(stops, 1)
check(#smo > #stops, "2: a pass inserts cut-points (got " .. tostring(#smo) .. ")")
-- Every original stop is still present at the same coordinate.
local function findStop(pts, x, y)
  for i = 1, #pts do
    if pts[i].stop and math.abs(pts[i].x - x) < 1e-9 and math.abs(pts[i].y - y) < 1e-9 then
      return i
    end
  end
end
check(findStop(smo, 0, 0) == 1, "2: the first stop is still the first point")
check(findStop(smo, 1, 0) ~= nil, "2: the corner stop is preserved exactly")
check(findStop(smo, 1, 1) == #smo, "2: the last stop is still the last point")
local mid
for i = 2, #smo - 1 do
  if not smo[i].stop then mid = smo[i] break end
end
check(mid ~= nil, "2: a mid-span sample was inserted")
check(math.abs(mid.y) > 1e-9, "2: the mid-span sample leaves the first chord (actual smoothing)")
check(math.abs(mid.y) <= 0.08 + 1e-9, "2: deviation stays within 8% of the span")
local two = G.SmoothPreserve({ { x = 0, y = 0 }, { x = 3, y = 0 } }, 1)
check(#two == 2 and two[1].x == 0 and two[2].x == 3,
  "2: a two-point path is not moved or padded")

-- ── 3. Decimate drops only low-value midpoints, never stops ──────────
local wavy = {
  { x = 0, y = 0, stop = true },
  { x = 1, y = 0.0001 }, -- almost on the line, should drop at eps=0.01
  { x = 2, y = 0, stop = true },
  { x = 3, y = 1, stop = true }, -- a real corner, kept because it is a stop
}
local dec = G.Decimate(wavy, 0.01)
check(#dec == 3, "3: the near-collinear midpoint is dropped (got " .. tostring(#dec) .. ")")
check(dec[1].x == 0 and dec[2].x == 2 and dec[3].x == 3, "3: both stops and the far stop remain")
local decKeep = G.Decimate(wavy, 0)
check(#decKeep == 4, "3: eps 0 drops nothing")

-- ── 4. Chevron spacing ───────────────────────────────────────────────
-- A 100-unit line with spacing 20: first chevron at 10, then 30,50,70,90.
-- Margin is 8, so 10 and 90 are kept. That is 5 chevrons.
local line = { { x = 0, y = 0 }, { x = 100, y = 0 } }
local chev, cn = G.PlaceChevrons(line, 20)
check(cn == 5, "4: five chevrons on a 100-unit line at spacing 20 (got " .. tostring(cn) .. ")")
near(chev[1].x, 10, "4: first chevron at spacing/2")
near(chev[5].x, 90, "4: last chevron stays off the end marker")
near(chev[1].dx, 1, "4: direction is unit +x")
near(chev[1].dy, 0, "4: no stray y component")
-- Too short for a chevron.
local _, cn0 = G.PlaceChevrons({ { x = 0, y = 0 }, { x = 10, y = 0 } }, 20)
check(cn0 == 0, "4: a path shorter than spacing+margins gets no chevron")
-- Snapshot the 5-chevron plan before the reuse test overwrites the array.
local chevFive = {}
for i = 1, cn do
  chevFive[i] = { kind = chev[i].kind, x = chev[i].x, y = chev[i].y, dx = chev[i].dx, dy = chev[i].dy }
end
local cnFive = cn
-- Reuse.
local same = chev
local _, cnR = G.PlaceChevrons({ { x = 0, y = 0 }, { x = 40, y = 0 } }, 20, same)
check(same == chev, "4: PlaceChevrons reuses the out array")
check(same[cnR + 1] == nil, "4: leftover chevrons are cleared")

-- ── 5. Markers and decor region counts ───────────────────────────────
local marks, mn = G.PlaceMarkers({ { x = 0, y = 0 }, { x = 5, y = 0 } })
check(mn == 2 and marks[1].kind == "start" and marks[2].kind == "end",
  "5: an open path gets start and end markers")
near(marks[2].x, 5, "5: the end marker sits on the last point")
local loopPts = { { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 0, y = 0, close = true } }
local lm, ln = G.PlaceMarkers(loopPts)
check(ln == 2 and lm[1].kind == "start" and lm[2].kind == "loop",
  "5: a closed path gets a start and a loop marker at the first point")
near(lm[2].x, 0, "5: the loop marker sits on the first point")
-- 2 markers + 5 chevrons = 2*1 + 5*1 = 7 cores.
local items = {}
for i = 1, cnFive do items[#items + 1] = chevFive[i] end
items[#items + 1] = marks[1]
items[#items + 1] = marks[2]
check(G.DecorRegionCount(items) == 7,
  "5: pool use is 1 region per chevron plus 1 per marker (got "
    .. tostring(G.DecorRegionCount(items)) .. ")")

-- ── 6. BuildDrawPath + pool reuse across two plans ───────────────────
local route = {
  anchors = {
    { x = 0.1, y = 0.1 }, { x = 0.2, y = 0.1 }, { x = 0.2, y = 0.3 },
  },
  path = {
    { x = 0.11, y = 0.12 }, { x = 0.19, y = 0.11 }, { x = 0.21, y = 0.29, close = false },
  },
}
local drawn = G.BuildDrawPath(route)
check(drawn and #drawn > 3, "6: BuildDrawPath smooths the anchors (got " .. tostring(drawn and #drawn) .. ")")
near(drawn[1].x, 0.1, "6: the first stop is exactly the first anchor")
near(drawn[#drawn].y, 0.3, "6: the last stop is exactly the last anchor")
-- The pre-smoothed path points (0.11, 0.12) must not replace the anchors.
check(math.abs(drawn[1].x - 0.11) > 1e-6, "6: the drawn path is not the already-shifted Density path")

local closedRoute = {
  anchors = { { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 0, y = 1 } },
  path = { { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 0, y = 1 }, { x = 0, y = 0, close = true } },
}
local loop = G.BuildDrawPath(closedRoute)
check(G.IsClosed(loop), "6: a close=true path stays closed")
near(loop[1].x, loop[#loop].x, "6: the loop returns to the first stop")
near(loop[1].y, loop[#loop].y, "6: the loop's last point matches the first")

-- Pool reuse: the same plan asks for the same region count; a shorter plan
-- asks for fewer, never a growing high-water on its own.
local bufA, cA = G.PlaceChevrons(drawn, 0.05)
local mA, mAn = G.PlaceMarkers(drawn)
local regionsA = G.DecorRegionCount(bufA, cA) + G.DecorRegionCount(mA, mAn)
local bufB, cB = G.PlaceChevrons(drawn, 0.05, bufA)
local mB, mBn = G.PlaceMarkers(drawn, mA)
local regionsB = G.DecorRegionCount(bufB, cB) + G.DecorRegionCount(mB, mBn)
check(regionsA == regionsB and regionsA > 0,
  "6: redrawing the same plan asks for the same region count ("
    .. tostring(regionsA) .. " vs " .. tostring(regionsB) .. ")")
local short = { { x = 0, y = 0 }, { x = 0.01, y = 0 } }
local bufC, cC = G.PlaceChevrons(short, 0.05, bufA)
local mC, mCn = G.PlaceMarkers(short, mA)
local regionsC = G.DecorRegionCount(bufC, cC) + G.DecorRegionCount(mC, mCn)
check(regionsC < regionsA,
  "6: a shorter plan asks for fewer regions (" .. tostring(regionsC)
    .. " vs " .. tostring(regionsA) .. "), so a reuse-and-hide high-water does not grow")
check(G.DecorRegionCount(bufC, cC) == 0, "6: a short path contributes no chevron regions")


-- ── 7. PackProjected keeps gaps so chevrons cannot shortcut ─────────
local src = {
  { x = 0, y = 0 },
  { why = "no projection" },
  { x = 100, y = 0 },
}
local packed, pn = G.PackProjected(src)
check(pn == 3, "7: PackProjected keeps the source length (got " .. tostring(pn) .. ")")
check(packed[2] and packed[2].gap, "7: the unprojected vertex becomes a gap sentinel")
check(packed[1].x == 0 and packed[3].x == 100, "7: projected points stay in their slots")
local reused = packed
local _, pn2 = G.PackProjected({ { x = 1, y = 1 }, { x = 2, y = 2 } }, reused)
check(reused == packed, "7: PackProjected reuses the out array")
check(reused[3] == nil, "7: leftover slots are cleared")
-- A 100-unit line with a hole in the middle must not grow a chevron on
-- the 0-to-100 shortcut. Spacing 20 would place five chevrons on a solid
-- 100-unit line; a gapped 0 / hole / 100 path has no usable span.
local gapped = G.PackProjected({
  { x = 0, y = 0 },
  { why = "missing" },
  { x = 100, y = 0 },
})
local _, gn = G.PlaceChevrons(gapped, 20)
check(gn == 0, "7: no chevron is placed across an unprojected gap (got " .. tostring(gn) .. ")")
-- Two real runs still get chevrons on each run, never on the hole.
local runs = G.PackProjected({
  { x = 0, y = 0 }, { x = 100, y = 0 },
  { why = "missing" },
  { x = 0, y = 50 }, { x = 100, y = 50 },
})
local ch, cnR = G.PlaceChevrons(runs, 20)
check(cnR > 0, "7: each projected run can still carry chevrons (got " .. tostring(cnR) .. ")")
local shortcut = false
for i = 1, cnR do
  local y = ch[i].y
  if y > 1 and y < 49 then
    shortcut = true
  end
end
check(not shortcut, "7: no chevron sits on the line between the two runs")

-- A gap at the first or last vertex must not crash PlaceMarkers / IsClosed,
-- must never count as a closed loop, and must take markers from the first
-- and last usable vertices. Chevrons still run on the visible span.
local firstGap = G.PackProjected({
  { why = "unprojected start" },
  { x = 0, y = 0 },
  { x = 100, y = 0 },
})
check(firstGap[1] and firstGap[1].gap, "7: a missing start becomes a gap sentinel")
check(G.IsClosed(firstGap) == false, "7: a first-gap path is not a closed loop")
firstGap[#firstGap].close = true
check(G.IsClosed(firstGap) == false, "7: a first-gap path is not a loop even with close=true")
firstGap[#firstGap].close = nil
local mk, mn = G.PlaceMarkers(firstGap)
check(mn == 2, "7: first-gap PlaceMarkers still writes start and end (got " .. tostring(mn) .. ")")
check(mk[1].kind == "start" and mk[1].x == 0 and mk[1].y == 0,
  "7: start marker sits on the first usable vertex")
check(mk[2].kind == "end" and mk[2].x == 100 and mk[2].y == 0,
  "7: end marker sits on the last usable vertex")
local _, cnFirst = G.PlaceChevrons(firstGap, 20)
check(cnFirst == 5, "7: first-gap chevrons follow the 0-to-100 run (got " .. tostring(cnFirst) .. ")")

local lastGap = G.PackProjected({
  { x = 0, y = 0 },
  { x = 100, y = 0 },
  { why = "unprojected end" },
})
check(lastGap[#lastGap] and lastGap[#lastGap].gap, "7: a missing end becomes a gap sentinel")
check(G.IsClosed(lastGap) == false, "7: a last-gap path is not a closed loop")
lastGap[#lastGap].close = true
check(G.IsClosed(lastGap) == false, "7: a last-gap path is not a loop even with close=true")
lastGap[#lastGap].close = nil
mk, mn = G.PlaceMarkers(lastGap)
check(mn == 2, "7: last-gap PlaceMarkers still writes start and end (got " .. tostring(mn) .. ")")
check(mk[1].kind == "start" and mk[1].x == 0 and mk[1].y == 0,
  "7: last-gap start marker sits on the first usable vertex")
check(mk[2].kind == "end" and mk[2].x == 100 and mk[2].y == 0,
  "7: last-gap end marker sits on the last usable vertex")
local _, cnLast = G.PlaceChevrons(lastGap, 20)
check(cnLast == 5, "7: last-gap chevrons follow the 0-to-100 run (got " .. tostring(cnLast) .. ")")

if failed > 0 then
  io.stderr:write(failed .. " route-style check(s) failed\n")
  os.exit(1)
end
print("route_style_spec: ok")

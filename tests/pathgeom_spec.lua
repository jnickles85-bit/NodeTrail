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

local function near(a, b, msg)
  check(type(a) == "number" and math.abs(a - b) < 1e-4, msg .. " got " .. tostring(a) .. " expected " .. tostring(b))
end

do
  local x1, y1, x2, y2 = G.ClipCircle(-1, 0, 1, 0, 5)
  near(x1, -1, "inside x1")
  near(y1, 0, "inside y1")
  near(x2, 1, "inside x2")
  near(y2, 0, "inside y2")
end

do
  local x1, y1, x2, y2 = G.ClipCircle(-10, 0, 10, 0, 5)
  near(x1, -5, "span x1")
  near(y1, 0, "span y1")
  near(x2, 5, "span x2")
  near(y2, 0, "span y2")
end

do
  local x1 = G.ClipCircle(10, 0, 12, 0, 5)
  check(x1 == nil, "segment outside circle")
end

do
  local x1 = G.ClipCircle(10, 10, 12, 12, 5)
  check(x1 == nil, "miss circle")
end

do
  local x1, y1, x2, y2 = G.ClipCircle(0, 0, 10, 0, 5)
  near(x1, 0, "one-in x1")
  near(y1, 0, "one-in y1")
  near(x2, 5, "one-in x2")
  near(y2, 0, "one-in y2")
end

do
  local s = 5 / math.sqrt(2)
  local x1, y1, x2, y2 = G.ClipCircle(-10, -10, 10, 10, 5)
  near(x1, -s, "diag x1")
  near(y1, -s, "diag y1")
  near(x2, s, "diag x2")
  near(y2, s, "diag y2")
end

do
  check(G.ClipCircle(0, 0, 1, 0, 0) == nil, "zero radius")
  check(G.ClipCircle(0, 0, 1, 0, nil) == nil, "nil radius")
end

do
  local x1, y1, x2, y2 = G.ClipRect(-10, 0, 10, 0, -5, -5, 5, 5)
  near(x1, -5, "rect x1")
  near(y1, 0, "rect y1")
  near(x2, 5, "rect x2")
  near(y2, 0, "rect y2")
end

do
  local x1, y1, x2, y2 = G.ClipRect(0, 0, 10, 0, -5, -5, 5, 5)
  near(x1, 0, "rect partial x1")
  near(x2, 5, "rect partial x2")
  near(y1, 0, "rect partial y1")
  near(y2, 0, "rect partial y2")
end

do
  local x1, y1, x2, y2 = G.ClipRect(-10, -10, 10, 10, -5, -5, 5, 5)
  near(x1, -5, "rect diag x1")
  near(y1, -5, "rect diag y1")
  near(x2, 5, "rect diag x2")
  near(y2, 5, "rect diag y2")
end

do
  check(G.ClipRect(-10, -10, -8, -8, -5, -5, 5, 5) == nil, "rect outside")
end

do
  check(G.IsMapPoint({ x = 0.2, y = 0.3 }), "valid point")
  check(not G.IsMapPoint({ x = 0.2 }), "missing y")
  check(not G.IsMapPoint({ x = 0 / 0, y = 0.2 }), "nan x")
  check(not G.IsMapPoint(nil), "nil point")
end

-- Decor containment: every kept item sits inside the clip region.
do
  check(G.InCircle(0, 0, 0, 0, 5), "origin is inside a radius-5 circle")
  check(G.InCircle(3, 4, 0, 0, 5), "a point on the circle is inside")
  check(not G.InCircle(3, 4.1, 0, 0, 5), "a point just outside is rejected")
  check(not G.InCircle(nil, 0, 0, 0, 5), "a missing coordinate is outside")
  check(G.InRect(1, 1, 0, 0, 10, 10), "a point inside a y-down rect")
  check(G.InRect(0, 5, -10, 10, 10, -10), "min/max swap still contains the point")
  check(not G.InRect(11, 1, 0, 0, 10, 10), "a point past the right edge is outside")
  check(G.InsideClip(0, 0, nil), "a missing clip admits a usable point")
  check(not G.InsideClip(nil, 0, nil), "a missing clip still rejects a bad point")
  check(G.InsideClip(0, 0, { shape = "circle", x = 0, y = 0, r = 5 }), "circle clip admits the origin")
  check(not G.InsideClip(20, 0, { shape = "circle", x = 0, y = 0, r = 5 }), "circle clip rejects a far point")

  local items = {
    { kind = "start", x = 0, y = 0 },
    { kind = "chevron", x = 2, y = 0 },
    { kind = "chevron", x = 20, y = 0 },
    { kind = "end", x = 40, y = 0 },
  }
  local clip = { shape = "circle", x = 0, y = 0, r = 5 }
  local kept, kn = G.ClipItems(items, #items, clip)
  check(kn == 2, "7: only the items inside the circle are kept (got " .. tostring(kn) .. ")")
  for i = 1, kn do
    check(G.InsideClip(kept[i].x, kept[i].y, clip),
      "7: kept decor item " .. i .. " is inside the circle")
  end
  check(kept[1].kind == "start" and kept[2].kind == "chevron" and kept[2].x == 2,
    "7: the in-circle start and chevron stay, in order")

  local rect = { shape = "rect", left = -1, top = -1, right = 3, bottom = 1 }
  kept, kn = G.ClipItems(items, #items, rect)
  check(kn == 2, "7: a rect clip also drops the far chevron and the end (got " .. tostring(kn) .. ")")
  for i = 1, kn do
    check(G.InsideClip(kept[i].x, kept[i].y, rect),
      "7: kept decor item " .. i .. " is inside the rect")
  end
end

if failed > 0 then
  io.stderr:write(failed .. " geometry check(s) failed\n")
  os.exit(1)
end
print("pathgeom_spec: ok")

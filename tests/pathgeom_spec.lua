local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."
local ns = {}
local chunk, err = loadfile(root .. "/UI/PathGeom.lua")
assert(chunk, err)
chunk("NodeTrail", ns)
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

if failed > 0 then
  io.stderr:write(failed .. " geometry check(s) failed\n")
  os.exit(1)
end
print("pathgeom_spec: ok")

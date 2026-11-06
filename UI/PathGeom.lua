local addonName, ns = ...

-- Pure map geometry. No WoW calls, so the clipping rules can be checked
-- outside the client. Coordinates are in the same pixel space the caller
-- already projected (y-up or y-down does not matter here).

ns.PathGeom = ns.PathGeom or {}
local G = ns.PathGeom

function G.IsMapPoint(p)
  return type(p) == "table"
    and type(p.x) == "number" and type(p.y) == "number"
    and p.x == p.x and p.y == p.y
end

--- Clip a segment to a circle centered at the origin.
--- @return x1, y1, x2, y2 or nil
function G.ClipCircle(x1, y1, x2, y2, radius)
  if type(x1) ~= "number" or type(y1) ~= "number" or type(x2) ~= "number" or type(y2) ~= "number" then
    return nil
  end
  if type(radius) ~= "number" or radius <= 0 then
    return nil
  end
  local dx, dy = x2 - x1, y2 - y1
  local a = dx * dx + dy * dy
  local b = 2 * (x1 * dx + y1 * dy)
  local c = x1 * x1 + y1 * y1 - radius * radius
  if a < 1e-8 then
    if c <= 0 then
      return x1, y1, x2, y2
    end
    return nil
  end
  local disc = b * b - 4 * a * c
  if disc < 0 then
    return nil
  end
  local root = math.sqrt(disc)
  local inv = 0.5 / a
  local tA = (-b - root) * inv
  local tB = (-b + root) * inv
  if tA > tB then
    tA, tB = tB, tA
  end
  local t0 = tA < 0 and 0 or tA
  local t1 = tB > 1 and 1 or tB
  if t0 > t1 then
    return nil
  end
  return x1 + dx * t0, y1 + dy * t0, x1 + dx * t1, y1 + dy * t1
end

--- Liang–Barsky clip to an axis-aligned rectangle.
--- @return x1, y1, x2, y2 or nil
function G.ClipRect(x1, y1, x2, y2, minX, minY, maxX, maxY)
  if type(x1) ~= "number" or type(y1) ~= "number" or type(x2) ~= "number" or type(y2) ~= "number" then
    return nil
  end
  local dx, dy = x2 - x1, y2 - y1
  local u1, u2 = 0, 1
  local p = { -dx, dx, -dy, dy }
  local q = { x1 - minX, maxX - x1, y1 - minY, maxY - y1 }
  for i = 1, 4 do
    local pi, qi = p[i], q[i]
    if pi == 0 then
      if qi < 0 then
        return nil
      end
    else
      local t = qi / pi
      if pi < 0 then
        if t > u2 then
          return nil
        end
        if t > u1 then
          u1 = t
        end
      else
        if t < u1 then
          return nil
        end
        if t < u2 then
          u2 = t
        end
      end
    end
  end
  if u1 > u2 then
    return nil
  end
  return x1 + dx * u1, y1 + dy * u1, x1 + dx * u2, y1 + dy * u2
end

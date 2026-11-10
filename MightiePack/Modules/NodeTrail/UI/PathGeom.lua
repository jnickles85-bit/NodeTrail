local _, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

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

local function finite(v)
  return type(v) == "number" and v == v and v > -1e9 and v < 1e9
end

--- Measured map rectangle inside a host frame.
--- The host is whatever frame the client pans/zooms with; the client may
--- inset the map texture inside it (Classic: WorldMapButton sits inside
--- WorldMapDetailFrame). Both sizes are MEASURED — nothing is assumed; when
--- the inner frame is unknown or larger, the whole host is the map.
--- @return { left, top, width, height } or nil when a size is unusable
function G.MapRect(hostWidth, hostHeight, mapWidth, mapHeight)
  if not finite(hostWidth) or not finite(hostHeight) then
    return nil
  end
  if hostWidth <= 0 or hostHeight <= 0 then
    return nil
  end
  local w, h = hostWidth, hostHeight
  if finite(mapWidth) and finite(mapHeight) and mapWidth > 0 and mapHeight > 0
    and mapWidth <= hostWidth and mapHeight <= hostHeight then
    w, h = mapWidth, mapHeight
  end
  return {
    left = (hostWidth - w) * 0.5,
    top = (hostHeight - h) * 0.5,
    width = w,
    height = h,
  }
end

--- A measured frame box, as every projection below takes it.
--- `left`/`top` are GetLeft()/GetTop() — the client reports them in the frame's
--- OWN scaled units, so screen px = left * scale. `scale` is GetEffectiveScale()
--- when the client answers it, GetScale() otherwise, 1 as the last resort.
--- @return true when every field is a usable finite number
local function boxOk(box)
  if type(box) ~= "table" then
    return false
  end
  if not finite(box.left) or not finite(box.top) then
    return false
  end
  if not finite(box.scale) or box.scale <= 0 then
    return false
  end
  return true
end

--- The rect of `map` — the frame whose PIXEL space the route's fractions are
--- measured in — expressed in `host`'s own pixel space, +y down from the host's
--- TOP. That is the space a child of `host` is anchored in, so a point at
--- (rect.left + f * rect.width, rect.top + g * rect.height) is drawn exactly on
--- the map feature the fraction names, whatever the host is.
---
--- This is the mapping a host that is NOT the map frame needs: the world map is
--- drawn by a frame the client composites (WorldMapFrame) while the fractions
--- live on a different frame (the canvas, which this client does not composite
--- children of). Both boxes are measured on screen at draw time, so zoom and
--- scroll are already inside them — a zoomed map is simply a wider box and a
--- scrolled map a shifted one. Nothing here is scaled by a guessed constant.
--- @param host table { left, top, scale }
--- @param map table { left, top, width, height, scale }
--- @return { left, top, width, height } in host units, or nil + reason
function G.ProjectRect(host, map)
  if not boxOk(host) then
    return nil, "the host frame has no measurable screen rect"
  end
  if not boxOk(map) then
    return nil, "the map frame has no measurable screen rect"
  end
  if not finite(map.width) or not finite(map.height) or map.width <= 0 or map.height <= 0 then
    return nil, "the map frame has no measurable size"
  end
  local hs, ms = host.scale, map.scale
  local rect = {
    left = (map.left * ms - host.left * hs) / hs,
    top = (host.top * hs - map.top * ms) / hs,
    width = map.width * ms / hs,
    height = map.height * ms / hs,
  }
  if not finite(rect.width) or not finite(rect.height) or rect.width <= 0 or rect.height <= 0 then
    return nil, "the projected map rect is empty"
  end
  return rect
end

--- The part of `a` that `b` covers. nil when they do not overlap at all.
--- Used to turn the measured ScrollContainer rect into the window the map is
--- actually visible through, so the route can be cropped instead of painted
--- over the frame's border.
function G.IntersectRect(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return nil
  end
  if not finite(a.left) or not finite(a.top) or not finite(a.width) or not finite(a.height) then
    return nil
  end
  if not finite(b.left) or not finite(b.top) or not finite(b.width) or not finite(b.height) then
    return nil
  end
  if a.width <= 0 or a.height <= 0 or b.width <= 0 or b.height <= 0 then
    return nil
  end
  local left = math.max(a.left, b.left)
  local top = math.max(a.top, b.top)
  local right = math.min(a.left + a.width, b.left + b.width)
  local bottom = math.min(a.top + a.height, b.top + b.height)
  if right <= left or bottom <= top then
    return nil
  end
  return { left = left, top = top, width = right - left, height = bottom - top }
end

--- Map fraction (0..1) -> pixels from the rectangle's left/top, +y down.
--- @return x, y or nil when the point or the rectangle is unusable
function G.FractionToPixel(fx, fy, rect)
  if type(rect) ~= "table" then
    return nil
  end
  local width, height = rect.width, rect.height
  if not finite(width) or not finite(height) or width <= 0 or height <= 0 then
    return nil
  end
  if not finite(fx) or not finite(fy) then
    return nil
  end
  return (rect.left or 0) + fx * width, (rect.top or 0) + fy * height
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

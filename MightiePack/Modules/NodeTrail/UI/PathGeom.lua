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

-- ── Route style geometry (audit §2.2): pure, no WoW calls ────────────────
-- These helpers feed the world-map and minimap drawers. Stops (the node
-- points a route is built from) are never moved; smoothing only inserts
-- light cut-points between them so the stroke can round a corner without
-- drifting off the node.

local function copyPoint(p, stop)
  return { x = p.x, y = p.y, stop = stop and true or p.stop, close = p.close }
end

local function hasXY(p)
  return type(p) == "table" and type(p.x) == "number" and type(p.y) == "number"
end

local function almostSame(a, b, eps)
  if not hasXY(a) or not hasXY(b) then
    return false
  end
  eps = eps or 1e-6
  return math.abs(a.x - b.x) <= eps and math.abs(a.y - b.y) <= eps
end

function G.IsClosed(pts)
  if type(pts) ~= "table" or #pts < 2 then
    return false
  end
  -- A gap at either end means the visible path is not a closed loop.
  if not hasXY(pts[1]) or not hasXY(pts[#pts]) then
    return false
  end
  if pts[#pts].close == true then
    return true
  end
  return almostSame(pts[1], pts[#pts])
end

--- Light Chaikin-style cuts BETWEEN preserved vertices. Original points
--- (and any flagged `.stop`) stay at their exact coordinates. `passes`
--- defaults to 1 — enough to take the stair off a corner without pulling
--- the line off the node. A two-point path is returned unchanged (already
--- a straight segment).
-- Max a mid-span sample may leave its chord, as a fraction of the
-- span length. Keeps the smoothed line close enough to the nodes that
-- it cannot be mistaken for a different route.
local SMOOTH_MAX_DEV = 0.08

local function reflectPoint(keep, other)
  return {
    x = 2 * keep.x - other.x,
    y = 2 * keep.y - other.y,
  }
end

local function catmull(p0, p1, p2, p3, t)
  local t2, t3 = t * t, t * t * t
  local function comp(a, b, c, d)
    return 0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2
      + (-a + 3 * b - 3 * c + d) * t3)
  end
  return comp(p0.x, p1.x, p2.x, p3.x), comp(p0.y, p1.y, p2.y, p3.y)
end

local function clampToChord(x, y, a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  local len2 = dx * dx + dy * dy
  if len2 < 1e-16 then
    return a.x, a.y
  end
  local len = math.sqrt(len2)
  local t = ((x - a.x) * dx + (y - a.y) * dy) / len2
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  local qx, qy = a.x + t * dx, a.y + t * dy
  local ox, oy = x - qx, y - qy
  local od = math.sqrt(ox * ox + oy * oy)
  local maxd = SMOOTH_MAX_DEV * len
  if od > maxd and od > 1e-12 then
    local s = maxd / od
    return qx + ox * s, qy + oy * s
  end
  return x, y
end

--- Sample a neighbour of `cur[i]`, wrapping a closed ring and reflecting
--- at the ends of an open path so the first and last spans still have a
--- tangent.
local function neighbour(cur, i, closed)
  local n = #cur
  if closed and n >= 3 then
    local u = n - 1
    local j = ((i - 1) % u)
    if j < 0 then j = j + u end
    return cur[j + 1]
  end
  if i < 1 then
    return reflectPoint(cur[1], cur[2])
  end
  if i > n then
    return reflectPoint(cur[n], cur[n - 1])
  end
  return cur[i]
end

function G.SmoothPreserve(pts, passes)
  if type(pts) ~= "table" or #pts < 3 then
    if type(pts) ~= "table" then return pts end
    local out = {}
    for i = 1, #pts do
      out[i] = copyPoint(pts[i], pts[i].stop)
    end
    return out
  end
  local nPass = tonumber(passes)
  if not nPass or nPass < 1 then
    nPass = 1
  end
  if nPass > 3 then
    nPass = 3
  end
  local cur = {}
  for i = 1, #pts do
    cur[i] = copyPoint(pts[i], true)
  end
  local closed = G.IsClosed(cur)
  for _ = 1, nPass do
    local nxt = { copyPoint(cur[1], true) }
    for i = 1, #cur - 1 do
      local a, b = cur[i], cur[i + 1]
      -- One mid-span sample is enough for a light pass and keeps the
      -- coarsest draw plan from tripling its minimum region count.
      local p0 = neighbour(cur, i - 1, closed)
      local p3 = neighbour(cur, i + 2, closed)
      local x, y = catmull(p0, a, b, p3, 0.5)
      x, y = clampToChord(x, y, a, b)
      nxt[#nxt + 1] = { x = x, y = y }
      nxt[#nxt + 1] = copyPoint(b, b.stop or i + 1 == #cur)
    end
    cur = nxt
    closed = G.IsClosed(cur)
  end
  return cur
end

--- Drop points that sit within `eps` of the line between kept neighbours.
--- Endpoints and `.stop` points are never dropped, so a stop always stays
--- on the node it names.
function G.Decimate(pts, eps)
  if type(pts) ~= "table" or #pts <= 2 then
    return pts
  end
  eps = tonumber(eps) or 0
  if eps < 0 then eps = 0 end
  local eps2 = eps * eps
  local kept = { pts[1] }
  local anchor = 1
  for i = 2, #pts - 1 do
    local p = pts[i]
    if p.stop then
      kept[#kept + 1] = p
      anchor = i
    else
      -- furthest-ahead look: drop only if p is close to the segment
      -- between the last kept point and the next MUST-keep point.
      local nextKeep = #pts
      for j = i + 1, #pts do
        if pts[j].stop or j == #pts then
          nextKeep = j
          break
        end
      end
      local a, b = pts[anchor], pts[nextKeep]
      local dx, dy = b.x - a.x, b.y - a.y
      local len2 = dx * dx + dy * dy
      local dist2
      if len2 < 1e-16 then
        local ex, ey = p.x - a.x, p.y - a.y
        dist2 = ex * ex + ey * ey
      else
        local t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
        local qx, qy = a.x + t * dx, a.y + t * dy
        local ex, ey = p.x - qx, p.y - qy
        dist2 = ex * ex + ey * ey
      end
      if dist2 > eps2 then
        kept[#kept + 1] = p
        anchor = i
      end
    end
  end
  kept[#kept + 1] = pts[#pts]
  return kept
end

--- Fill `out` with `{x1,y1,x2,y2}` segments. Reuses slot tables already in
--- `out` so a redraw can avoid allocating a new array. Degenerate
--- (zero-length) spans are skipped.
function G.Segments(pts, out)
  out = out or {}
  local n = 0
  if type(pts) == "table" then
    for i = 1, #pts - 1 do
      local a, b = pts[i], pts[i + 1]
      if type(a) == "table" and type(b) == "table"
        and type(a.x) == "number" and type(b.x) == "number"
        and type(a.y) == "number" and type(b.y) == "number" then
        local dx, dy = b.x - a.x, b.y - a.y
        if dx * dx + dy * dy >= 1e-12 then
          n = n + 1
          local seg = out[n]
          if type(seg) ~= "table" then
            seg = {}
            out[n] = seg
          end
          seg[1], seg[2], seg[3], seg[4] = a.x, a.y, b.x, b.y
        end
      end
    end
  end
  for i = #out, n + 1, -1 do
    out[i] = nil
  end
  return out, n
end

function G.PolylineLength(pts)
  local len = 0
  if type(pts) ~= "table" then
    return 0
  end
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    if type(a) == "table" and type(b) == "table"
      and type(a.x) == "number" and type(b.x) == "number" then
      local dx, dy = b.x - a.x, b.y - a.y
      len = len + math.sqrt(dx * dx + dy * dy)
    end
  end
  return len
end

--- Direction chevrons, evenly spaced along the polyline. `spacing` is in
--- the same units as the points. Chevrons are not placed within
--- `spacing * 0.4` of either end, so they cannot sit on the start/end
--- markers. Each entry is `{x, y, dx, dy}` with a unit direction.
--- Copy a projected-point list into `out`, keeping a gap sentinel at
--- every unprojected vertex so decorations do not shortcut across a hole.
--- Reuses `out` slots; a gap is a table with `.gap = true` and no x/y.
function G.PackProjected(src, out)
  out = out or {}
  local n = 0
  if type(src) == "table" then
    for i = 1, #src do
      n = i
      local p = src[i]
      if p and type(p.x) == "number" and type(p.y) == "number" then
        out[i] = p
      else
        local gap = out[i]
        if type(gap) ~= "table" or not gap.gap then
          gap = { gap = true }
          out[i] = gap
        else
          gap.x, gap.y = nil, nil
          gap.gap = true
        end
      end
    end
  end
  for i = #out, n + 1, -1 do
    out[i] = nil
  end
  return out, n
end

function G.PlaceChevrons(pts, spacing, out)
  out = out or {}
  local n = 0
  spacing = tonumber(spacing) or 0
  if type(pts) == "table" and #pts >= 2 and spacing > 0 then
    local total = G.PolylineLength(pts)
    local margin = spacing * 0.4
    if total > spacing + 2 * margin then
      local first = spacing * 0.5
      if first < margin then
        first = margin
      end
      local target = first
      local walked = 0
      for i = 1, #pts - 1 do
        local a, b = pts[i], pts[i + 1]
        if type(a) == "table" and type(b) == "table"
          and type(a.x) == "number" and type(b.x) == "number" then
          local dx, dy = b.x - a.x, b.y - a.y
          local segLen = math.sqrt(dx * dx + dy * dy)
          if segLen >= 1e-8 then
            local ux, uy = dx / segLen, dy / segLen
            while target <= walked + segLen + 1e-9 and target <= total - margin + 1e-9 do
              if target >= margin then
                n = n + 1
                local item = out[n]
                if type(item) ~= "table" then
                  item = {}
                  out[n] = item
                end
                item.kind = "chevron"
                item.x = a.x + ux * (target - walked)
                item.y = a.y + uy * (target - walked)
                item.dx = ux
                item.dy = uy
              end
              target = target + spacing
            end
            walked = walked + segLen
          end
        end
      end
    end
  end
  for i = #out, n + 1, -1 do
    out[i] = nil
  end
  return out, n
end

--- Start / end / loop markers. A closed path gets a start marker and a
--- loop marker at the first point (the line already returns there). An
--- open path gets a start marker on the first point and an end marker on
--- the last. Entries reuse `out` slots.
local function firstUsable(pts)
  for i = 1, #pts do
    if hasXY(pts[i]) then
      return pts[i]
    end
  end
end

local function lastUsable(pts)
  for i = #pts, 1, -1 do
    if hasXY(pts[i]) then
      return pts[i]
    end
  end
end

function G.PlaceMarkers(pts, out)
  out = out or {}
  local n = 0
  local first = type(pts) == "table" and firstUsable(pts) or nil
  local last = first and lastUsable(pts) or nil
  if first and last then
    local start = out[1]
    if type(start) ~= "table" then start = {}; out[1] = start end
    start.kind = "start"
    start.x, start.y = first.x, first.y
    start.dx, start.dy = 0, 0
    -- IsClosed is false when either end of the array is a gap, so a
    -- path that is missing a projected endpoint is never a loop.
    local closed = G.IsClosed(pts)
    n = 2
    local mark = out[2]
    if type(mark) ~= "table" then mark = {}; out[2] = mark end
    if closed then
      mark.kind = "loop"
      mark.x, mark.y = first.x, first.y
    else
      mark.kind = "end"
      mark.x, mark.y = last.x, last.y
    end
    mark.dx, mark.dy = 0, 0
  end
  for i = #out, n + 1, -1 do
    out[i] = nil
  end
  return out, n
end

--- How many decoration cores a plan consumes. A chevron is two rotated
--- bars forming a V (or one small tick when rotation is unavailable;
--- the count stays at two so a pool sized for the V is enough). Start,
--- end, and loop markers are one filled square each. Marker rims are
--- acquired beside these cores and are not counted here.
function G.DecorRegionCount(items, n)
  n = n or (type(items) == "table" and #items) or 0
  local r = 0
  for i = 1, n do
    local it = items[i]
    local kind = type(it) == "table" and it.kind or nil
    if kind == "chevron" then
      r = r + 2
    elseif kind == "start" or kind == "end" or kind == "loop" then
      r = r + 1
    end
  end
  return r
end

--- Build the polyline that is actually drawn: exact stops (anchors when
--- the route has them, otherwise the path points), lightly smoothed
--- between those stops, never moving them. Computed once when a route is
--- set, not per frame.
function G.BuildDrawPath(route)
  if type(route) ~= "table" then
    return nil
  end
  local src = route.anchors
  if type(src) ~= "table" or #src < 2 then
    src = route.path
  end
  if type(src) ~= "table" or #src < 2 then
    return nil
  end
  local pts = {}
  for i = 1, #src do
    local p = src[i]
    if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then
      pts[#pts + 1] = { x = p.x, y = p.y, stop = true, close = p.close }
    end
  end
  if #pts < 2 then
    return nil
  end
  local closed = G.IsClosed(pts)
  if not closed and type(route.path) == "table" and #route.path > 0 then
    local last = route.path[#route.path]
    if type(last) == "table" and last.close == true then
      closed = true
    end
  end
  if closed then
    if not almostSame(pts[1], pts[#pts]) then
      pts[#pts + 1] = { x = pts[1].x, y = pts[1].y, stop = true, close = true }
    else
      pts[#pts].close = true
    end
  end
  -- Drop mid-span samples that still sit on (or almost on) the chord,
  -- so a straight run does not spend extra segments. Stops stay.
  return G.Decimate(G.SmoothPreserve(pts, 1), 0.0005)
end

function G.InCircle(x, y, cx, cy, radius)
  if type(x) ~= "number" or type(y) ~= "number" or type(radius) ~= "number" or radius < 0 then
    return false
  end
  local dx = x - (tonumber(cx) or 0)
  local dy = y - (tonumber(cy) or 0)
  return dx * dx + dy * dy <= radius * radius
end

function G.InRect(x, y, left, top, right, bottom)
  if type(x) ~= "number" or type(y) ~= "number" then
    return false
  end
  left, top, right, bottom = tonumber(left), tonumber(top), tonumber(right), tonumber(bottom)
  if not left or not top or not right or not bottom then
    return false
  end
  local x0, x1 = math.min(left, right), math.max(left, right)
  local y0, y1 = math.min(top, bottom), math.max(top, bottom)
  return x >= x0 and x <= x1 and y >= y0 and y <= y1
end

--- clip = { shape = "circle", x, y, r } or { shape = "rect", left, top, right, bottom }.
--- A missing or unknown clip admits every point, so a caller that has no
--- viewport does not silently drop decorations.
--- `pad` is an optional extent around (x, y) in the same units, so a
--- chevron is tested by its arm reach, not only its centre.
--- `clip.contain` true: the whole extent must sit inside (world-map
--- window, which does not clip its children). Otherwise the extent
--- only has to intersect the clip (minimap, which SetClipsChildren
--- when the client has it).
function G.InsideClip(x, y, clip, pad)
  if type(clip) ~= "table" then
    return type(x) == "number" and type(y) == "number"
  end
  pad = tonumber(pad)
  if not pad then
    pad = tonumber(clip.pad) or 0
  end
  if pad < 0 then
    pad = 0
  end
  local contain = clip.contain and true or false
  if clip.shape == "circle" then
    local r = tonumber(clip.r) or 0
    if contain then
      r = r - pad
      if r < 0 then
        r = 0
      end
    else
      r = r + pad
    end
    return G.InCircle(x, y, clip.x, clip.y, r)
  end
  local left, top = tonumber(clip.left), tonumber(clip.top)
  local right, bottom = tonumber(clip.right), tonumber(clip.bottom)
  if not left or not top or not right or not bottom then
    return false
  end
  local x0, x1 = math.min(left, right), math.max(left, right)
  local y0, y1 = math.min(top, bottom), math.max(top, bottom)
  if contain then
    return G.InRect(x, y, x0 + pad, y0 + pad, x1 - pad, y1 - pad)
  end
  return G.InRect(x, y, x0 - pad, y0 - pad, x1 + pad, y1 + pad)
end

--- Keep items whose extent is inside (or intersects) the clip. Reuses `out`.
function G.ClipItems(items, n, clip, out)
  out = out or {}
  n = n or (type(items) == "table" and #items or 0)
  local kept = 0
  if type(items) ~= "table" then
    for i = #out, 1, -1 do
      out[i] = nil
    end
    return out, 0
  end
  local pad = type(clip) == "table" and tonumber(clip.pad) or 0
  for i = 1, n do
    local it = items[i]
    if type(it) == "table" and type(it.x) == "number" and type(it.y) == "number"
      and G.InsideClip(it.x, it.y, clip, pad) then
      kept = kept + 1
      out[kept] = it
    end
  end
  for i = #out, kept + 1, -1 do
    out[i] = nil
  end
  return out, kept
end


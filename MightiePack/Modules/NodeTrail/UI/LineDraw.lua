local _, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

-- White polyline segments.
-- Prefer Frame:CreateLine (Classic canvas clients and Forever).
-- Otherwise a rotated WHITE8X8 texture (SetRotation, 3.1+).
-- Otherwise the taxi-route SetTexCoord quad (UI-Taxi-Line), which is the
-- Classic technique that does not need SetRotation.

ns.LineDraw = ns.LineDraw or {}
local D = ns.LineDraw

local WHITE = "Interface\\Buttons\\WHITE8X8"
local TAXI = "Interface\\TaxiFrame\\UI-Taxi-Line"
local LINEFACTOR = 128 / 126
local LINEFACTOR_2 = LINEFACTOR / 2

function D.ColorWidth()
  local db = ns.GetDB()
  local c = db.pathColor
  local r, g, b, a = 1, 1, 1, 0.9
  if type(c) == "table" then
    r = tonumber(c[1]) or r
    g = tonumber(c[2]) or g
    b = tonumber(c[3]) or b
    a = tonumber(c[4]) or a
  end
  local width = tonumber(db.pathWidth) or 2
  if width <= 0 then
    width = 2
  end
  return r, g, b, a, width
end

function D.BindOverlay(host, parent, clipChildren)
  if not host or not parent then
    return
  end
  pcall(host.SetParent, host, parent)
  pcall(host.ClearAllPoints, host)
  pcall(host.SetAllPoints, host, parent)
  if host.EnableMouse then
    pcall(host.EnableMouse, host, false)
  end
  if host.EnableMouseWheel then
    pcall(host.EnableMouseWheel, host, false)
  end
  if host.SetMouseClickEnabled then
    pcall(host.SetMouseClickEnabled, host, false)
  end
  if host.EnableMouseMotion then
    pcall(host.EnableMouseMotion, host, false)
  end
  if host.SetPassThroughButtons then
    pcall(host.SetPassThroughButtons, host, "LeftButton", "RightButton", "MiddleButton")
  end
  -- The world-map host must not clip its own dots: a host that clips would
  -- cut the route at its own edge, which looks exactly like "only the opening
  -- leg painted". The minimap host is the opposite: anything that escapes
  -- the square is drawn over the rest of the UI, so that overlay asks to clip.
  -- The client default is off; the flag is set explicitly so a client that
  -- defaults it on cannot silently crop the world-map route.
  if host.SetClipsChildren then
    pcall(host.SetClipsChildren, host, clipChildren and true or false)
  end
  if parent.GetFrameLevel and host.SetFrameLevel then
    local ok, level = pcall(parent.GetFrameLevel, parent)
    if ok and type(level) == "number" then
      pcall(host.SetFrameLevel, host, level + 3)
    end
  end
end

function D.Create()
  return {
    pool = {},
    mode = nil,
    disableLine = false,
    capability = {},
  }
end

--- What one drawn object ACTUALLY carries, read back from the client after the
--- draw — not what the draw asked for. `requested` is the colour the code
--- passed, `vertex`/`alpha` are `GetVertexColor`/`GetAlpha` read from the
--- region, so "the alpha never reached the texture" is a printed fact instead
--- of a guess. `planned`/`screen` are the sizes the plan asked for.
function D.ReadBack(obj, extra)
  local d = D.Describe(obj)
  local out = extra or {}
  out.present = d.present
  out.kind = d.kind
  out.shown = d.shown
  out.alpha = d.alpha
  out.vertex = d.vertex
  out.width = d.width
  out.height = d.height
  out.level = d.level
  out.strata = d.strata
  out.layer = d.layer
  out.blend = d.blend
  out.parent = d.parent
  return out
end

--- Live state of one pool object, for /nt mapdiag. Every read is guarded, so a
--- region missing a getter reports nil ("absent") instead of erroring. The
--- point fields are the real 5-value region contract
--- (point, relativeTo, relativePoint, offsetX, offsetY).
function D.Describe(obj)
  if type(obj) ~= "table" then
    return { present = false }
  end
  local function read(method, ...)
    local fn = obj[method]
    if type(fn) ~= "function" then
      return nil
    end
    local ok, a, b, c, d, e = pcall(fn, obj, ...)
    if not ok then
      return nil
    end
    return a, b, c, d, e
  end
  local d = { present = true, kind = obj.kind }
  local shown = read("IsShown")
  if shown == nil then
    shown = read("IsVisible")
  end
  d.shown = shown
  d.alpha = read("GetAlpha")
  d.thickness = read("GetThickness")
  local p1, _, rp1, x1, y1 = read("GetStartPoint")
  if type(p1) == "string" then
    d.start = { p1, rp1, x1, y1 }
    -- Structured form for the truthfulness checks: the array above is the
    -- positional contract the diag already prints, this one names the fields.
    d.startPoint = { point = p1, relativePoint = rp1, x = x1, y = y1 }
  end
  local p2, _, rp2, x2, y2 = read("GetEndPoint")
  if type(p2) == "string" then
    d.stop = { p2, rp2, x2, y2 }
    d.stopPoint = { point = p2, relativePoint = rp2, x = x2, y = y2 }
  end
  d.width = read("GetWidth")
  d.height = read("GetHeight")
  -- Where the region ACTUALLY is on screen. The anchors say where it was asked
  -- to be; GetLeft/GetTop say where the client put it. A dot that is anchored
  -- inside the canvas but whose GetLeft is off the map is a placement bug, and a
  -- dot whose GetLeft is on the map but invisible is a draw-order/clipping bug —
  -- only the client's own answer separates those two, which is why the diag
  -- prints it next to the anchors.
  d.left = read("GetLeft")
  d.top = read("GetTop")
  d.visible = read("IsVisible")
  -- A line REGION may or may not have its own z-order: a bare Texture/Line
  -- region draws inside its parent frame and a client that does not expose
  -- GetFrameLevel/GetFrameStrata for it must read as "inherits the host"
  -- (nil), not as level 0 — those two are very different draw orders.
  d.level = read("GetFrameLevel")
  d.strata = read("GetFrameStrata")
  -- Which LAYER the region ended up in, and how it blends. A dot at the right
  -- colour and size is still a ghost when it lands on a layer under the map art
  -- or blends in a way the client does not honour.
  d.layer = read("GetDrawLayer")
  d.blend = read("GetBlendMode")
  d.parent = read("GetParent")
  local vr, vg, vb, va = read("GetVertexColor")
  if type(vr) == "number" then
    d.vertex = { vr, vg, vb, va }
  end
  local tex = read("GetTexture")
  if type(tex) == "string" then
    d.texture = tex
  end
  -- The region's own contract, so the diag can name what the client actually
  -- implements instead of guessing from a size of 0.
  d.objectType = read("GetObjectType")
  d.luaType = type(obj)
  local count = read("GetNumPoints")
  if type(count) == "number" then
    d.numPoints = count
    local points = {}
    if type(obj.GetPoint) == "function" then
      for i = 1, math.min(count, 4) do
        local okP, p, rel, relPoint, x, y = pcall(obj.GetPoint, obj, i)
        if okP and type(p) == "string" then
          points[i] = { point = p, relativeTo = rel, relativePoint = relPoint, x = x, y = y }
        end
      end
    end
    d.points = points
  end
  local methods = {}
  local names = {
    "SetPoint", "GetPoint", "SetWidth", "SetHeight", "SetSize", "SetRotation",
    "SetStartPoint", "SetEndPoint", "GetStartPoint", "GetEndPoint",
    "SetThickness", "SetTexCoord", "SetColorTexture", "SetVertexColor",
  }
  for i = 1, #names do
    methods[names[i]] = type(obj[names[i]]) == "function"
  end
  d.methods = methods
  return d
end

--- What the last Draw actually applied. The client cannot be asked "what colour
--- is this line", so the drawer records the values it passed: a diag that only
--- re-reads pathColor reports the setting, not the draw.
function D.Applied(drawer)
  return drawer and drawer.lastApplied or nil
end

-- ── Does the client actually APPLY the geometry a draw asks for? ───────────
-- A setter that returned is not a state change. The live client answered every
-- SetStartPoint/SetEndPoint call and then reported
--   start=TOPLEFT(0.0,absent) end=TOPLEFT(0.0,absent) size=0x0 thickness=2.88
-- for all 12 queued segments: the line object existed, was shown, carried the
-- right colour — and had no geometry at all, so nothing appeared and no error
-- was raised. `mode = "line"` used to be chosen on the mere EXISTENCE of
-- Frame:CreateLine; it is now chosen only on a measured round-trip.
local PROBE_SPAN = 64
local PROBE_TOL = 0.75

local function numberMethod(obj, method)
  local fn = obj and obj[method]
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, obj)
  if not ok or type(value) ~= "number" or value ~= value then
    return nil
  end
  return value
end

--- Read a 5-value point region contract: point, relativeTo, relativePoint, x, y.
--- Returns nil when the getter is absent or the client answers with no point
--- name, and keeps nil offsets as nil — "absent" must not read as 0.
local function readPoint(obj, method)
  local fn = obj and obj[method]
  if type(fn) ~= "function" then
    return nil
  end
  local ok, point, rel, relPoint, x, y = pcall(fn, obj)
  if not ok or type(point) ~= "string" then
    return nil
  end
  return { point = point, relativeTo = rel, relativePoint = relPoint, x = x, y = y }
end

--- One point as text, for the diag: "TOPLEFT(0.0,absent)".
function D.PointText(p)
  if type(p) ~= "table" then
    return "absent"
  end
  local function num(v)
    if type(v) ~= "number" then
      return "absent"
    end
    return string.format("%.1f", v)
  end
  return string.format("%s(%s,%s)", tostring(p.point), num(p.x), num(p.y))
end

--- Measure whether a Line region keeps the endpoints it is given. Sets a
--- known 64px diagonal on `obj` when supplied (the caller reuses it), or on a
--- throwaway region created the same way. Reads back the endpoint tuple and
--- the size, and reports which of them took effect.
function D.LineProof(parent, obj)
  local out = { span = PROBE_SPAN }
  local created = false
  if not obj then
    if type(parent) ~= "table" or type(parent.CreateLine) ~= "function" then
      out.why = "the client exposes no Frame:CreateLine"
      return out
    end
    local ok, line = pcall(parent.CreateLine, parent, nil, "OVERLAY")
    if not ok or not line then
      out.why = "CreateLine raised or returned nothing"
      return out
    end
    obj = line
    created = true
  end
  out.hasCreateLine = true
  out.objectType = (function()
    local fn = obj.GetObjectType
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, obj)
    if ok and type(value) == "string" then return value end
    return nil
  end)()
  out.luaType = type(obj)
  out.getNumPoints = type(obj.GetNumPoints) == "function"
  out.setPoint = type(obj.SetPoint) == "function"
  out.getPoint = type(obj.GetPoint) == "function"
  out.numPoints = numberMethod(obj, "GetNumPoints")
  if obj.SetThickness then
    pcall(obj.SetThickness, obj, 2)
  end
  pcall(obj.ClearAllPoints, obj)
  pcall(obj.SetStartPoint, obj, "TOPLEFT", parent, "TOPLEFT", 0, 0)
  pcall(obj.SetEndPoint, obj, "TOPLEFT", parent, "TOPLEFT", PROBE_SPAN, -PROBE_SPAN)
  out.start = readPoint(obj, "GetStartPoint")
  out.stop = readPoint(obj, "GetEndPoint")
  out.width = numberMethod(obj, "GetWidth")
  out.height = numberMethod(obj, "GetHeight")
  local took = type(out.start) == "table" and type(out.stop) == "table"
    and type(out.start.x) == "number" and type(out.start.y) == "number"
    and type(out.stop.x) == "number" and type(out.stop.y) == "number"
    and math.abs(out.start.x) <= PROBE_TOL and math.abs(out.start.y) <= PROBE_TOL
    and math.abs(out.stop.x - PROBE_SPAN) <= PROBE_TOL
    and math.abs(out.stop.y + PROBE_SPAN) <= PROBE_TOL
  -- A client that does not implement GetStartPoint at all still proves the
  -- region by sizing it from the endpoints it was given.
  local sized = type(out.width) == "number" and type(out.height) == "number"
    and out.width > 0 and out.height > 0
  out.took = took or sized
  out.why = out.took and "the endpoints were kept"
    or "the client accepted SetStartPoint/SetEndPoint and kept no geometry"
  if created then
    pcall(obj.Hide, obj)
  end
  return out
end

--- The primitive the dots fallback needs: two corner anchors on a texture.
--- Measures the setter path (SetWidth/SetHeight/SetSize) BEFORE anchoring, so
--- the diag can say which of them this client honours.
function D.TextureProof(tex, parent)
  local out = {
    setWidth = type(tex.SetWidth) == "function",
    setHeight = type(tex.SetHeight) == "function",
    setSize = type(tex.SetSize) == "function",
    setRotation = type(tex.SetRotation) == "function",
    setPoint = type(tex.SetPoint) == "function",
    setTexCoord = type(tex.SetTexCoord) == "function",
    getNumPoints = type(tex.GetNumPoints) == "function",
  }
  if not out.setPoint then
    out.canAnchor = false
    out.why = "the region exposes no SetPoint: no texture primitive can be placed"
    return out
  end
  out.canAnchor = true
  pcall(tex.ClearAllPoints, tex)
  if tex.SetWidth then
    pcall(tex.SetWidth, tex, 64)
  end
  if tex.SetHeight then
    pcall(tex.SetHeight, tex, 8)
  end
  out.sizedWidth = numberMethod(tex, "GetWidth")
  out.sizedHeight = numberMethod(tex, "GetHeight")
  out.sizedBySetters = type(out.sizedWidth) == "number" and type(out.sizedHeight) == "number"
    and math.abs(out.sizedWidth - 64) <= 0.5 and math.abs(out.sizedHeight - 8) <= 0.5
  -- Then force the size the only way this fallback does: two corner anchors.
  -- y-down offsets from TOPLEFT, so the BOTTOM anchor needs the LARGER offset:
  -- with the two swapped (bottom -8, top -16) the top edge sits above the
  -- bottom edge, the client answers height 0, and the diag read "two corner
  -- anchors -> 64x0" — which said the anchors failed when only the probe was
  -- upside down.
  pcall(tex.ClearAllPoints, tex)
  pcall(tex.SetPoint, tex, "BOTTOMLEFT", parent, "TOPLEFT", 10, -16)
  pcall(tex.SetPoint, tex, "TOPRIGHT", parent, "TOPLEFT", 74, -8)
  out.anchorWidth = numberMethod(tex, "GetWidth")
  out.anchorHeight = numberMethod(tex, "GetHeight")
  out.numPoints = numberMethod(tex, "GetNumPoints")
  out.sizedByAnchors = (type(out.numPoints) == "number" and out.numPoints >= 2)
    or (type(out.anchorWidth) == "number" and type(out.anchorHeight) == "number"
      and math.abs(out.anchorWidth - 64) <= 0.5 and math.abs(out.anchorHeight - 8) <= 0.5)
  return out
end

function D.LineProofText(p)
  if type(p) ~= "table" then
    return "not measured"
  end
  if p.why and not p.hasCreateLine then
    return tostring(p.why)
  end
  return string.format(
    "object=%s luatype=%s GetNumPoints=%s GetPoint=%s SetPoint=%s points=%s; start=%s end=%s size=%sx%s -> %s",
    tostring(p.objectType or "absent"), tostring(p.luaType or "?"),
    p.getNumPoints and "present" or "absent", p.getPoint and "present" or "absent",
    p.setPoint and "present" or "absent",
    type(p.numPoints) == "number" and string.format("%d", p.numPoints) or "absent",
    D.PointText(p.start), D.PointText(p.stop),
    type(p.width) == "number" and string.format("%.0f", p.width) or "absent",
    type(p.height) == "number" and string.format("%.0f", p.height) or "absent",
    p.took and "KEPT" or "DROPPED")
end

function D.TextureProofText(p)
  if type(p) ~= "table" then
    return "not measured"
  end
  local function has(v)
    return v and "present" or "absent"
  end
  if not p.canAnchor then
    return tostring(p.why or "not measurable")
  end
  return string.format(
    "SetPoint=%s SetWidth=%s SetHeight=%s SetSize=%s SetRotation=%s SetTexCoord=%s; size setters -> %sx%s; two corner anchors -> %sx%s points=%s",
    has(p.setPoint), has(p.setWidth), has(p.setHeight), has(p.setSize),
    has(p.setRotation), has(p.setTexCoord),
    type(p.sizedWidth) == "number" and string.format("%.0f", p.sizedWidth) or "absent",
    type(p.sizedHeight) == "number" and string.format("%.0f", p.sizedHeight) or "absent",
    type(p.anchorWidth) == "number" and string.format("%.0f", p.anchorWidth) or "absent",
    type(p.anchorHeight) == "number" and string.format("%.0f", p.anchorHeight) or "absent",
    type(p.numPoints) == "number" and string.format("%d", p.numPoints) or "absent")
end

--- SetRotation + size, read back. CreateLine taught us that a call that
--- succeeds and keeps no geometry is an invisible draw, so this is only
--- "took" when GetRotation and the size setters both keep what they were given.
function D.RotateProof(tex)
  local out = {
    setRotation = type(tex) == "table" and type(tex.SetRotation) == "function",
    getRotation = type(tex) == "table" and type(tex.GetRotation) == "function",
  }
  if not out.setRotation then
    out.took = false
    out.why = "the region exposes no SetRotation"
    return out
  end
  if tex.ClearAllPoints then
    pcall(tex.ClearAllPoints, tex)
  end
  if tex.SetWidth then
    pcall(tex.SetWidth, tex, 64)
  end
  if tex.SetHeight then
    pcall(tex.SetHeight, tex, 8)
  end
  local angle = 0.35
  pcall(tex.SetRotation, tex, angle)
  out.width = numberMethod(tex, "GetWidth")
  out.height = numberMethod(tex, "GetHeight")
  out.rotation = numberMethod(tex, "GetRotation")
  out.sized = type(out.width) == "number" and type(out.height) == "number"
    and math.abs(out.width - 64) <= 0.5 and math.abs(out.height - 8) <= 0.5
  if not out.getRotation then
    out.took = false
    out.why = "SetRotation is present but GetRotation is not, so the angle cannot be proved"
    return out
  end
  out.took = out.sized and type(out.rotation) == "number" and math.abs(out.rotation - angle) <= 0.02
  out.why = out.took and "the size and rotation were kept"
    or "SetRotation did not keep the size or the angle"
  return out
end

--- SetTexCoord, read back with GetTexCoord. Same rule as LineProof: a
--- setter that cannot be confirmed is not treated as a working stroke.
function D.TexCoordProof(tex)
  local out = {
    setTexCoord = type(tex) == "table" and type(tex.SetTexCoord) == "function",
    getTexCoord = type(tex) == "table" and type(tex.GetTexCoord) == "function",
  }
  if not out.setTexCoord then
    out.took = false
    out.why = "the region exposes no SetTexCoord"
    return out
  end
  -- Four-value form (left, right, top, bottom). Clients that only accept the
  -- eight-corner form still typically answer GetTexCoord with four or eight
  -- numbers we can compare.
  pcall(tex.SetTexCoord, tex, 0.125, 0.875, 0.25, 0.75)
  if not out.getTexCoord then
    out.took = false
    out.why = "SetTexCoord is present but GetTexCoord is not, so the coords cannot be proved"
    return out
  end
  local ok, a, b, c, d = pcall(tex.GetTexCoord, tex)
  if not ok then
    out.took = false
    out.why = "GetTexCoord raised"
    return out
  end
  out.u0, out.u1, out.v0, out.v1 = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
  local function close(got, want)
    return type(got) == "number" and math.abs(got - want) <= 0.02
  end
  out.took = close(out.u0, 0.125) and close(out.u1, 0.875)
    and close(out.v0, 0.25) and close(out.v1, 0.75)
  out.why = out.took and "the tex coords were kept"
    or "SetTexCoord did not keep the coordinates"
  return out
end

--- Pick the best STROKE primitive from measured proofs. A session pin from
--- `/nt linetest use ...` wins, otherwise a rotation that kept its angle
--- and size is the confirmed default, then a CreateLine that kept its
--- endpoints, then the two-corner-anchor dots (the last resort). Texcoord
--- is never chosen automatically: it dropped on Forever, and the only way
--- to use it is `/nt linetest use texcoord`.
function D.PickStrokeMode(capability, pin)
  if type(pin) == "string" and pin ~= "" and pin ~= "auto" then
    return pin
  end
  capability = capability or {}
  local rot = capability.rotate
  if type(rot) == "table" and rot.took then
    return "rotate"
  end
  local line = capability.line
  if type(line) == "table" and line.took then
    return "line"
  end
  return "dots"
end

--- Paint one object with the route colour, and report WHICH call the client
--- actually took. Modern clients accept `SetColorTexture` and it wins over
--- `SetVertexColor` — so `GetVertexColor` reads back 1,1,1,1 no matter what
--- colour the dot is. "Which call carried the colour" is therefore part of the
--- measurement: a diag that only reads the vertex colour is blind on exactly
--- the clients this addon runs on.
--- @return "SetColorTexture"|"SetVertexColor"|"none"
local function applyColor(obj, r, g, b, a, texturePath)
  if obj.SetColorTexture then
    local ok = pcall(obj.SetColorTexture, obj, r, g, b, a)
    if ok then
      return "SetColorTexture"
    end
  end
  if obj.SetTexture then
    pcall(obj.SetTexture, obj, texturePath or WHITE)
  end
  if obj.SetVertexColor then
    pcall(obj.SetVertexColor, obj, r, g, b, a)
    return "SetVertexColor"
  end
  return "none"
end

-- The probe in MapOverlay paints its marker/border with the SAME path the
-- route uses, so it must not carry a second copy of it.
D.ApplyColor = applyColor

local function hideObj(obj)
  if not obj then
    return
  end
  pcall(obj.Hide, obj)
  if obj.ClearAllPoints then
    pcall(obj.ClearAllPoints, obj)
  end
  if obj.SetRotation then
    pcall(obj.SetRotation, obj, 0)
  end
  if obj.SetTexCoord then
    pcall(obj.SetTexCoord, obj, 0, 1, 0, 1)
  end
end

function D.Clear(drawer)
  if not drawer or not drawer.pool then
    return
  end
  -- t_57550700: iterate to the HIGH-WATER index, never `#pool`. A pool that ever
  -- failed to create an object has a nil slot in it, and `#` on such a table is
  -- unspecified — the old loop could stop before the tail and leave the
  -- previous route's dots on the map. hideFrom below had the same bug and was
  -- fixed; this is the same fix applied to Clear.
  local high = drawer.poolHigh or #drawer.pool
  for i = 1, high do
    hideObj(drawer.pool[i])
  end
end

--- Record that the last redraw painted NOTHING, and why. `lastApplied` is what
--- /nt mapdiag reports as "the draw", so an overlay that was hidden (wrong map,
--- showWorldMap off, no host) must not leave the previous draw's painted count
--- standing: that is how a route that is nowhere on the screenshot still reads
--- as "painted=288 missing=0 outside=0".
function D.MarkIdle(drawer, why)
  if not drawer then
    return
  end
  local prev = drawer.lastApplied
  local prevPainted = (type(prev) == "table" and tonumber(prev.paintedDots)) or 0
  D.Clear(drawer)
  drawer.lastApplied = {
    mode = drawer.mode,
    count = 0,
    plannedDots = 0,
    paintedDots = 0,
    missingDots = 0,
    hiddenDots = 0,
    hiddenByHide = 0,
    dotOutside = 0,
    prevPainted = prevPainted,
    planReplans = drawer.planReplans or 0,
    replans = 0,
    idle = true,
    why = tostring(why or "not drawing"),
    poolHigh = drawer.poolHigh or 0,
  }
end

function D.Invalidate(drawer)
  D.Clear(drawer)
  if drawer then
    drawer.pool = {}
    drawer.mode = nil
    -- The proof belonged to the previous parent; a new parent must be measured
    -- again rather than inherit the old evidence.
    drawer.capability = {}
    -- The region ceiling and the width it forced belong to the old host too.
    drawer.poolHigh = nil
    drawer.capacity = nil
    drawer.createFailed = nil
    drawer.widenHint = nil
    drawer.hideFromIndex = nil
    drawer.hiddenCount = nil
    drawer.hiddenDots = nil
    drawer.dotOutside = nil
    drawer.dotBox = nil
    -- The plan fingerprint belonged to the previous parent: a draw onto a new
    -- surface is not a re-plan, it is the first plan there.
    drawer.planSig = nil
  end
end

local function detect(drawer, parent)
  drawer.pool = drawer.pool or {}
  drawer.capability = drawer.capability or {}
  if not drawer.disableLine and type(parent.CreateLine) == "function" then
    local ok, line = pcall(parent.CreateLine, parent, nil, "OVERLAY")
    if not ok or not line then
      drawer.capability.line = { why = "CreateLine raised or returned nothing" }
      drawer.disableLine = true
    else
      -- Measured, not assumed: choose the line primitive only when the region
      -- KEEPS the endpoints it is given. The live client answers the calls and
      -- reads back no geometry at all, which is a "drawn, no error, invisible"
      -- line — exactly the bug that took four rounds to find.
      local proof = D.LineProof(parent, line)
      drawer.capability.line = proof
      if proof.took then
        drawer.mode = "line"
        drawer.pool[1] = line
        pcall(line.Hide, line)
        return
      end
      pcall(line.Hide, line)
      drawer.disableLine = true
    end
  end
  if type(parent.CreateTexture) ~= "function" then
    drawer.mode = "none"
    drawer.capability.dots = { canAnchor = false, why = "the host exposes no CreateTexture" }
    return
  end
  local ok, tex = pcall(parent.CreateTexture, parent, nil, "OVERLAY")
  if not ok or not tex then
    drawer.mode = "none"
    drawer.capability.dots = { canAnchor = false, why = "CreateTexture raised or returned nothing" }
    return
  end
  pcall(tex.Hide, tex)
  local proof = D.TextureProof(tex, parent)
  drawer.capability.dots = proof
  drawer.capability.rotate = D.RotateProof(tex)
  drawer.capability.texcoord = D.TexCoordProof(tex)
  pcall(tex.Hide, tex)
  if tex.SetRotation then
    pcall(tex.SetRotation, tex, 0)
  end
  if tex.SetTexCoord then
    pcall(tex.SetTexCoord, tex, 0, 1, 0, 1)
  end
  -- `disableDots` is the diagnostic/spec switch that reaches the legacy
  -- texture primitives below (the same role `disableLine` has above).
  -- When a proof actually KEPT its geometry, prefer that stroke over the
  -- axis-aligned dot chain (which still stairs on a diagonal). When no
  -- proof can be confirmed, keep the two-corner-anchor dots: they are the
  -- only primitive this client has already shown it paints.
  if proof.canAnchor and not drawer.disableDots then
    local pick = D.PickStrokeMode(drawer.capability, D._forceMode)
    if pick == "rotate" or pick == "texcoord" or pick == "line" then
      -- Line was already considered above; a forced line with a failed
      -- proof still falls through to dots rather than drawing invisible
      -- segments. rotate/texcoord reuse the proof texture as pool[1].
      if pick ~= "line" then
        drawer.pool[1] = tex
        drawer.mode = pick
        return
      end
    end
    drawer.mode = "dots"
    return
  end
  drawer.pool[1] = tex
  if tex.SetRotation then
    drawer.mode = "rotate"
  elseif tex.SetTexCoord then
    drawer.mode = "texcoord"
  else
    drawer.mode = "none"
  end
end

--- One dot of the chain: a square forced to its size by two corner anchors.
--- `space` "ydown" anchors from the host's TOPLEFT (+y down, the world map);
--- "yup" anchors from its CENTER (+y up, the minimap).
local function paintDot(obj, parent, cx, cy, size, r, g, b, a, space, sublevel)
  local half = (size or 2) * 0.5
  obj:SetParent(parent)
  local via = applyColor(obj, r, g, b, a, WHITE)
  -- Forever: SetColorTexture can succeed the call and still leave an
  -- untextured black square. The rotate stroke already proved WHITE8X8
  -- + SetVertexColor keeps colour, so re-apply that path after the
  -- colour probe. Decorations and any leftover dots must never render
  -- as black blocks.
  if obj.SetTexture then
    pcall(obj.SetTexture, obj, WHITE)
  end
  if obj.SetVertexColor then
    pcall(obj.SetVertexColor, obj, r, g, b, a)
  end
  -- A pooled region can still carry an alpha from an earlier use, and an
  -- inherited parent alpha multiplies whatever we set. The vertex colour is the
  -- only alpha this draw means, so the region's own alpha is pinned to 1 (the
  -- host asks the client to ignore the parent's — see MapOverlay.EnsureHost).
  if obj.SetAlpha then
    pcall(obj.SetAlpha, obj, 1)
  end
  if obj.SetDrawLayer then
    -- The outline is drawn one sublevel BELOW the white dot, so a client that
    -- paints by sublevel agrees with the creation order the pool already has.
    pcall(obj.SetDrawLayer, obj, "OVERLAY", sublevel or 7)
  end
  if obj.SetBlendMode then
    pcall(obj.SetBlendMode, obj, "BLEND")
  end
  if obj.SetTexCoord then
    pcall(obj.SetTexCoord, obj, 0, 1, 0, 1)
  end
  obj:ClearAllPoints()
  if space == "yup" then
    obj:SetPoint("BOTTOMLEFT", parent, "CENTER", cx - half, cy - half)
    obj:SetPoint("TOPRIGHT", parent, "CENTER", cx + half, cy + half)
  else
    obj:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", cx - half, -(cy + half))
    obj:SetPoint("TOPRIGHT", parent, "TOPLEFT", cx + half, -(cy - half))
  end
  obj:Show()
  return via
end

-- ── Dot sizing is a SCREEN measurement, not a canvas one ───────────────────
-- The world map draws into a 1002x668 canvas that the client shows at ~0.696
-- scale, so a 2.88 canvas px dot was 2.0 screen px of white at 0.9 alpha — and
-- over the Barrens' tan terrain that is invisible. The operator read that as
-- "the line is somewhere else, across the zone". Dot geometry is therefore
-- computed in screen px and divided by the surface scale.
local DOT_MIN_SCREEN = 4     -- the white dot never renders narrower than this
local DOT_OUTLINE_GROW = 2   -- screen px the dark outline adds (1px rim on each side)
local DOT_SPACING_MIN = 6    -- screen px between dots (screen units, like the size)
-- The white dot is OPAQUE. pathColor's 0.9 alpha was measured as a ghost: 3
-- screen px of white at 90 % over the Barrens' tan blends to a pale smear that
-- is only legible if you are already looking at it, and the dark rim behind it
-- is 1 px wide, so it dilutes too. A route that has to be followed is a solid
-- stroke; the requested alpha is still recorded (`alphaRequested`) and printed
-- by /nt mapdiag, so nothing is hidden — it is overridden, on purpose.
local DOT_MIN_ALPHA = 1
-- The dark dot behind the white one. Contrast, not brightness: white at 0.9
-- over tan is ~invisible, and the map art's colour changes per zone, so a fixed
-- light stroke cannot survive every zone. An opaque near-black rim does.
local DOT_OUTLINE_R, DOT_OUTLINE_G, DOT_OUTLINE_B, DOT_OUTLINE_A = 0, 0, 0, 1
local DOT_SCALE_MIN, DOT_SCALE_MAX = 0.05, 100
-- A long route on a big canvas must not allocate thousands of regions. This is
-- the number of DOTS; each dot holds two regions (outline + white).
local DOT_MAX_TOTAL = 1200

--- Pure: how big a dot has to be, in BOTH units.
--- `canvasScale` is canvas px -> screen px (WorldMapFrame:GetCanvasScale()).
--- `screenFloor` (optional) overrides DOT_MIN_SCREEN — the visibility ladder in
--- /nt mapdiag drives it so one build can A/B a 3/4/5 px core without a deploy.
--- @return { scale, pathWidth, screenSize, screenSpacing, screenOutline,
---           size, spacing, outline } — screen* in screen px, the rest in canvas px
function D.DotMetrics(pathWidth, canvasScale, screenFloor)
  local scale = tonumber(canvasScale) or 1
  if scale ~= scale or scale <= 0 then
    scale = 1
  end
  if scale < DOT_SCALE_MIN then
    scale = DOT_SCALE_MIN
  end
  if scale > DOT_SCALE_MAX then
    scale = DOT_SCALE_MAX
  end
  local floor = tonumber(screenFloor)
  if not floor or floor ~= floor or floor < 1 then
    floor = DOT_MIN_SCREEN
  end
  local width = tonumber(pathWidth) or 0
  if width ~= width or width < 0 then
    width = 0
  end
  local screenSize = width
  if screenSize < floor then
    screenSize = floor
  end
  -- ── The pitch is well inside the CORE, so a diagonal of squares blends ─
  -- A 1 screen-px overlap still reads as a staircase of axis-aligned
  -- squares on a diagonal. Overlapping by more than half the core turns
  -- that chain into a stroke even when SetRotation cannot be proved.
  -- Neighbouring rims overlap the next core geometrically; that is safe
  -- because every rim is painted first, then every core (see D.Draw).
  local screenSpacing = screenSize * 0.4
  if screenSpacing < 1 then
    screenSpacing = 1
  end
  local screenOutline = screenSize + DOT_OUTLINE_GROW
  return {
    scale = scale,
    pathWidth = width,
    screenFloor = floor,
    screenSize = screenSize,
    screenSpacing = screenSpacing,
    screenOutline = screenOutline,
    size = screenSize / scale,
    spacing = screenSpacing / scale,
    outline = screenOutline / scale,
  }
end

--- Pure: how many dots of `size` px, `spacing` px apart, cover `length` px.
--- `capScale` widens both together, so a capped route keeps the same
--- dot-to-gap ratio (a continuous stroke) instead of turning into dashes.
--- @return { length, size, spacing, steps, count }
function D.DotPlan(length, size, spacing, capScale)
  local k = tonumber(capScale) or 1
  if k ~= k or k < 1 then
    k = 1
  end
  local plan = {
    length = tonumber(length) or 0,
    size = (tonumber(size) or DOT_MIN_SCREEN) * k,
    spacing = (tonumber(spacing) or DOT_SPACING_MIN) * k,
    steps = 0,
    count = 0,
  }
  if plan.spacing <= 0.0001 then
    -- A degenerate spacing would ask for an infinite number of dots.
    plan.spacing = 0.0001
  end
  if plan.length <= 0 then
    return plan
  end
  plan.steps = math.ceil(plan.length / plan.spacing)
  if plan.steps < 1 then
    plan.steps = 1
  end
  plan.count = plan.steps + 1
  return plan
end

--- Pure: a dot plan per segment, with one global scale so the whole route
--- stays inside DOT_MAX_TOTAL. Both endpoints are always drawn.
--- `widen` (>= 1) multiplies both the dot and the spacing again, so a caller
--- that measured a smaller region budget can re-plan the same route onto the
--- objects it can actually create — the chain still covers the segment, with
--- fewer, larger dots.
function D.PlanDots(buf, count, metrics, widen)
  local m = metrics
  if type(m) ~= "table" then
    m = D.DotMetrics(nil, 1)
  end
  local extra = tonumber(widen) or 1
  if extra ~= extra or extra < 1 then
    extra = 1
  end
  local function build(scale)
    local plans, total = {}, 0
    for i = 1, count do
      local seg = buf and buf[i]
      local len = 0
      if seg then
        local dx, dy = seg[3] - seg[1], seg[4] - seg[2]
        len = math.sqrt(dx * dx + dy * dy)
      end
      plans[i] = D.DotPlan(len, m.size, m.spacing, scale * extra)
      total = total + plans[i].count
    end
    return plans, total
  end
  local plans, total = build(1)
  if total > DOT_MAX_TOTAL and total > 0 then
    plans, total = build(total / DOT_MAX_TOTAL)
  end
  return plans, total
end

local function acquire(drawer, index, parent)
  local obj = drawer.pool[index]
  if obj then
    return obj
  end
  local created
  if drawer.mode == "line" and type(parent.CreateLine) == "function" then
    local ok, line = pcall(parent.CreateLine, parent, nil, "OVERLAY")
    if ok then
      created = line
    end
  end
  if not created and type(parent.CreateTexture) == "function" then
    local ok, tex = pcall(parent.CreateTexture, parent, nil, "OVERLAY")
    if ok then
      created = tex
    end
  end
  if not created then
    -- The client refused another region. That is a MEASURED ceiling, not an
    -- error: remember it, so the draw can re-plan onto what it can create
    -- instead of silently losing every dot past this index. It is kept per
    -- surface (cleared by Invalidate), because it is a property of the host.
    drawer.createFailed = (drawer.createFailed or 0) + 1
    if not drawer.capacity or (index - 1) < drawer.capacity then
      drawer.capacity = index - 1
    end
    return nil
  end
  drawer.pool[index] = created
  if not drawer.poolHigh or index > drawer.poolHigh then
    drawer.poolHigh = index
  end
  return created
end

--- The frame surplus regions are moved onto once they are no longer part of a
--- plan. It is created once and left hidden: a region cannot be destroyed on
--- this client, so "released" means "off the map surface and out of the pool",
--- not "gone".
local function retireHolder(drawer)
  if type(drawer.retireTo) == "table" then
    return drawer.retireTo
  end
  if type(CreateFrame) ~= "function" then
    return nil
  end
  local ok, frame = pcall(CreateFrame, "Frame", "MightiePackNodeTrailRetiredDots")
  if not ok or type(frame) ~= "table" then
    return nil
  end
  pcall(frame.Hide, frame)
  drawer.retireTo = frame
  return frame
end

--- Hide every held object from `index` on AND take it out of the pool.
---
--- Iterating to the HIGH-WATER index rather than `#drawer.pool`: a pool that ever
--- failed to create an object has a nil slot in it, and `#` on such a table is
--- unspecified — the old loop could stop early and leave the previous route's
--- dots on screen.
---
--- t_57550700: this used to hide the surplus but KEEP it. The pool was a one-way
--- ratchet — two live plans in one session reported `objects held=908` for a
--- 480-object plan, and `highest=908` with `hideFrom=481 hidden=0` could not be
--- reconciled with `shown=480`. A hidden object stays parented to the map host,
--- is counted as "held", and is silently re-shown by the next grow at the
--- position it was left at. Released objects cannot do any of that: the pool
--- after every draw is exactly `painted * 2`, and `stale` (highest > 2*painted)
--- says so if it ever is not.
---
--- @param paired true for the dot chain, where a dot is two objects (rim, dot)
--- @return hidden objects, hidden dots
local function hideFrom(drawer, index, paired)
  local high = drawer.poolHigh or #drawer.pool
  local hidden, dots = 0, 0
  local holder
  for i = index, high do
    local obj = drawer.pool[i]
    if obj then
      local shown = (not obj.IsShown) or (obj:IsShown() ~= false)
      if shown then
        hidden = hidden + 1
        -- Even pool indices are the white dot of each pair (odd = its rim), so
        -- the dots that disappear are the EVEN objects in the surplus range.
        -- That is the drop in `painted`, in painted's own unit.
        if not paired or (i % 2 == 0) then
          dots = dots + 1
        end
      end
      hideObj(obj)
      -- The holder is only created when there is something to release.
      if holder == nil then
        holder = retireHolder(drawer) or false
      end
      if holder and type(obj.SetParent) == "function" then
        pcall(obj.SetParent, obj, holder)
      end
      drawer.pool[i] = nil
    end
  end
  drawer.poolHigh = (index > 1) and (index - 1) or 0
  drawer.hideFromIndex = index
  drawer.hiddenCount = hidden
  drawer.hiddenDots = dots
  return hidden, dots
end

local function paintLine(obj, parent, x1, y1, x2, y2, thickness, r, g, b, a, space)
  obj:SetParent(parent)
  applyColor(obj, r, g, b, a, WHITE)
  if obj.SetThickness then
    obj:SetThickness(thickness)
  end
  obj:ClearAllPoints()
  if space == "yup" then
    obj:SetStartPoint("CENTER", parent, "CENTER", x1, y1)
    obj:SetEndPoint("CENTER", parent, "CENTER", x2, y2)
  else
    obj:SetStartPoint("TOPLEFT", parent, "TOPLEFT", x1, -y1)
    obj:SetEndPoint("TOPLEFT", parent, "TOPLEFT", x2, -y2)
  end
  obj:Show()
end

local function paintRotate(obj, parent, x1, y1, x2, y2, thickness, r, g, b, a, space, sublevel)
  local dx, dy = x2 - x1, y2 - y1
  local length = math.sqrt(dx * dx + dy * dy)
  if length < 0.75 then
    obj:Hide()
    return
  end
  obj:SetParent(parent)
  obj:ClearAllPoints()
  if obj.SetTexture then
    obj:SetTexture(WHITE)
  end
  if obj.SetVertexColor then
    obj:SetVertexColor(r, g, b, a)
  end
  if obj.SetAlpha then
    pcall(obj.SetAlpha, obj, 1)
  end
  if obj.SetTexCoord then
    obj:SetTexCoord(0, 1, 0, 1)
  end
  if obj.SetDrawLayer then
    pcall(obj.SetDrawLayer, obj, "OVERLAY", sublevel or 7)
  end
  if obj.SetBlendMode then
    pcall(obj.SetBlendMode, obj, "BLEND")
  end
  -- Extra width is centered, so joins overlap by half the stroke.
  if obj.SetWidth then
    obj:SetWidth(length + thickness)
  end
  if obj.SetHeight then
    obj:SetHeight(thickness)
  end
  local cx = (x1 + x2) * 0.5
  local cy = (y1 + y2) * 0.5
  if space == "yup" then
    obj:SetPoint("CENTER", parent, "CENTER", cx, cy)
    obj:SetRotation(math.atan2(dy, dx))
  else
    obj:SetPoint("CENTER", parent, "TOPLEFT", cx, -cy)
    obj:SetRotation(math.atan2(-dy, dx))
  end
  obj:Show()
end

local function clampTex(v)
  if v > 10000 then return 10000 end
  if v < -10000 then return -10000 end
  return v
end

-- Blizzard TaxiFrame / LibGraph line. `sx,sy` are parent BOTTOMLEFT, +y up.
local function paintTexCoord(obj, parent, sx, sy, ex, ey, w, r, g, b, a)
  local dx, dy = ex - sx, ey - sy
  local len = (dx * dx + dy * dy) ^ 0.5
  if not len or len < 0.75 or not w or w <= 0 then
    obj:Hide()
    return
  end
  local ext = w * 0.5
  local ux, uy = dx / len, dy / len
  sx = sx - ux * ext
  sy = sy - uy * ext
  ex = ex + ux * ext
  ey = ey + uy * ext
  dx, dy = ex - sx, ey - sy
  len = (dx * dx + dy * dy) ^ 0.5
  if dx < 0 then
    dx, dy = -dx, -dy
  end
  local s = -dy / len
  local c = dx / len
  local sc = s * c
  local Bwid, Bhgt, BLx, BLy, TLx, TLy, TRx, TRy, BRx, BRy
  if dy >= 0 then
    Bwid = ((len * c) - (w * s)) * LINEFACTOR_2
    Bhgt = ((w * c) - (len * s)) * LINEFACTOR_2
    BLx, BLy, BRy = (w / len) * sc, s * s, (len / w) * sc
    BRx, TLx, TLy, TRx = 1 - BLy, BLy, 1 - BRy, 1 - BLx
    TRy = BRx
  else
    Bwid = ((len * c) + (w * s)) * LINEFACTOR_2
    Bhgt = ((w * c) + (len * s)) * LINEFACTOR_2
    BLx, BLy, BRx = s * s, -(len / w) * sc, 1 + (w / len) * sc
    BRy, TLx, TLy, TRy = BLx, 1 - BRx, 1 - BLx, 1 - BLy
    TRx = TLy
  end
  local cx = (sx + ex) * 0.5
  local cy = (sy + ey) * 0.5
  obj:SetParent(parent)
  obj:ClearAllPoints()
  if obj.SetTexture then
    obj:SetTexture(TAXI)
  end
  if obj.SetVertexColor then
    obj:SetVertexColor(r, g, b, a)
  end
  if obj.SetDrawLayer then
    pcall(obj.SetDrawLayer, obj, "OVERLAY", 7)
  end
  if obj.SetTexCoord then
    obj:SetTexCoord(
      clampTex(TLx), clampTex(TLy),
      clampTex(BLx), clampTex(BLy),
      clampTex(TRx), clampTex(TRy),
      clampTex(BRx), clampTex(BRy)
    )
  end
  obj:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", cx - Bwid, cy - Bhgt)
  obj:SetPoint("TOPRIGHT", parent, "BOTTOMLEFT", cx + Bwid, cy + Bhgt)
  obj:Show()
end

local function toBottomLeft(parent, x1, y1, x2, y2, space)
  local w = parent:GetWidth() or 0
  local h = parent:GetHeight() or 0
  if space == "yup" then
    return w * 0.5 + x1, h * 0.5 + y1, w * 0.5 + x2, h * 0.5 + y2
  end
  return x1, h - y1, x2, h - y2
end

--- A cheap, exact fingerprint of the plan a draw is about to paint, in the
--- pixels it will paint them at. `replans=` in /nt mapdiag must count drawings
--- that REPLACED A DIFFERENT DRAWING — it read 0 through a live session in which
--- the route visibly went from 33 points (208 dots) to 37 points (240 dots),
--- because the only counter on that line counted capacity re-fits instead.
--- Integers only, so the same plan always fingerprints the same.
local function planSignature(buf, count)
  local h = 7
  h = (h * 1000003 + (count or 0)) % 2147483647
  for i = 1, (count or 0) do
    local s = buf[i]
    if type(s) == "table" then
      for k = 1, 4 do
        local v = tonumber(s[k]) or 0
        h = (h * 1000003 + math.floor(v * 100 + 0.5)) % 2147483647
      end
    end
  end
  return h
end

--- Draw `count` segments from `buf[i] = {x1,y1,x2,y2}`.
--- space "ydown": pixels from parent TOPLEFT, +y down.
--- space "yup": pixels from parent CENTER, +y up.
--- `metrics` (optional) is the DotMetrics table for THIS surface: the dot chain
--- is sized in screen px and divided by the surface scale. Without it the
--- thickness is treated as already being in screen px.
function D.Draw(drawer, parent, buf, count, thickness, r, g, b, a, space, metrics)
  if not drawer or not parent then
    return
  end
  if drawer.parent ~= parent then
    D.Invalidate(drawer)
    drawer.parent = parent
  end
  if not drawer.mode then
    detect(drawer, parent)
  end
  count = count or 0
  -- t_57550700: what the previous draw reported, captured BEFORE this one
  -- overwrites it. Together with `hidden` it is the shrink proof:
  -- hidden + painted == prevPainted, or a dot of the old plan is unaccounted for.
  local prevApplied = drawer.lastApplied
  local prevSig, prevPainted = drawer.planSig, 0
  if type(prevApplied) == "table" and prevSig ~= nil then
    prevPainted = tonumber(prevApplied.paintedDots) or 0
  end
  local sig = (count > 0) and planSignature(buf, count) or nil
  local replanned = (sig ~= nil) and (prevSig ~= nil) and (sig ~= prevSig)
  if replanned then
    drawer.planReplans = (drawer.planReplans or 0) + 1
  end
  drawer.planSig = sig
  -- Record what this draw applies: the in-client diag can read the pool
  -- objects' geometry but not their colour, so the values the code actually
  -- passed are the only truthful answer to "is alpha 0 / did pathColor apply".
  drawer.lastApplied = {
    mode = drawer.mode,
    count = count,
    thickness = thickness,
    r = r, g = g, b = b, a = a,
    space = space,
    prevPainted = prevPainted,
    planReplans = drawer.planReplans or 0,
    replanned = replanned,
  }
  if drawer.mode == "none" or count < 1 then
    -- No plan on screen. Hiding (not releasing) keeps the pool as a cache: the
    -- minimap redraws with count 0 every time the player leaves its radius, and
    -- releasing there would re-create hundreds of regions each time.
    D.Clear(drawer)
    drawer.lastApplied.plannedDots = 0
    drawer.lastApplied.paintedDots = 0
    drawer.lastApplied.missingDots = 0
    drawer.lastApplied.poolHigh = drawer.poolHigh or 0
    drawer.lastApplied.hideFromIndex = nil
    drawer.lastApplied.hiddenByHide = 0
    drawer.lastApplied.hiddenDots = 0
    drawer.lastApplied.replans = 0
    drawer.lastApplied.stale = false
    return
  end
  if drawer.mode == "dots" then
    -- Chain of small two-corner-anchored quads. No SetWidth, no SetHeight, no
    -- SetRotation: the size is forced by the anchors alone, which is the only
    -- primitive the live client proved it accepts.
    local m = metrics
    if type(m) ~= "table" then
      m = D.DotMetrics(thickness, 1)
    end
    -- What the caller ASKED for vs what the white dot is painted with. The
    -- requested alpha is kept so /nt mapdiag can print both; the core is
    -- opaque (DOT_MIN_ALPHA) because 0.9-over-tan is the ghost this card is.
    local dotRequested = tonumber(a) or 1
    local dotAlpha = dotRequested
    if dotAlpha < DOT_MIN_ALPHA then
      dotAlpha = DOT_MIN_ALPHA
    end
    drawer.lastApplied.alphaRequested = dotRequested
    drawer.lastApplied.a = dotAlpha
    -- When the allocation cap widened the dots, the rim widens with them, so
    -- the outlined stroke keeps the same weight-to-rim ratio everywhere.
    local rimRatio = (m.size > 0) and (m.outline / m.size) or 1

    --- Paint `plans` over `buf`. Returns the next free pool index, and how many
    --- dots were ACTUALLY painted (both of their objects existed) versus
    --- planned — the loop index alone cannot tell those apart, which is how a
    --- truncated route used to report itself as complete.
    --- Also records where the painted dots land relative to the host, because
    --- "painted outside the host" is indistinguishable from "not painted" on a
    --- screenshot and is a different bug.
    local hostW = numberMethod(parent, "GetWidth")
    local hostH = numberMethod(parent, "GetHeight")
    local outside, box = 0, {}
    local function measured(cx, cy)
      if not box[1] or cx < box[1] then box[1] = cx end
      if not box[2] or cy < box[2] then box[2] = cy end
      if not box[3] or cx > box[3] then box[3] = cx end
      if not box[4] or cy > box[4] then box[4] = cy end
      if hostW and hostH and (cx < 0 or cy < 0 or cx > hostW or cy > hostH) then
        outside = outside + 1
      end
    end
    drawer.dotOutside, drawer.dotBox = nil, nil
    local function paint(plans)
      local index
      local painted, missing = 0, 0
      local first
      -- A retry repaints the pool, so the sample must describe the LAST paint:
      -- keeping the first paint's read-back would print a plan that is no longer
      -- on screen.
      drawer.lastApplied.sampleDot, drawer.lastApplied.sampleRim = nil, nil
      outside, box = 0, {}
      -- Two passes over the same plan: every rim first (sublevel 6), then
      -- every core (sublevel 7). Pool layout is unchanged (odd = rim, even
      -- = core) so existing diag pairing still holds. Cores may overlap
      -- neighbouring rims geometrically; because every core is painted
      -- after every rim, those rims cannot bury the stroke.
      local function eachDot(fn)
        for i = 1, count do
          local seg, plan = buf[i], plans[i]
          if seg and plan and plan.steps > 0 then
            first = first or plan
            local dx, dy = seg[3] - seg[1], seg[4] - seg[2]
            for k = 0, plan.steps do
              local tt = k / plan.steps
              fn(seg[1] + dx * tt, seg[2] + dy * tt, plan)
            end
          end
        end
      end
      -- Acquire rim+core interleaved so a region ceiling is spent on
      -- complete dots, not on a first pass of rims only. Then paint
      -- every rim, then every core, so the stroke sits on top even
      -- when the client has no SetDrawLayer.
      local n = 0
      eachDot(function()
        n = n + 1
        acquire(drawer, n * 2 - 1, parent)
        acquire(drawer, n * 2, parent)
      end)
      n = 0
      eachDot(function(cx, cy, plan)
        n = n + 1
        local under = acquire(drawer, n * 2 - 1, parent)
        if under then
          local rimVia = paintDot(under, parent, cx, cy, plan.size * rimRatio,
            DOT_OUTLINE_R, DOT_OUTLINE_G, DOT_OUTLINE_B, DOT_OUTLINE_A, space, 6)
          if not drawer.lastApplied.sampleRim then
            drawer.lastApplied.sampleRim = D.ReadBack(under, {
              requested = { DOT_OUTLINE_R, DOT_OUTLINE_G, DOT_OUTLINE_B, DOT_OUTLINE_A },
              via = rimVia,
              planned = plan.size * rimRatio,
              screen = (plan.size * rimRatio) * (m.scale > 0 and m.scale or 1),
            })
          end
        end
      end)
      n = 0
      eachDot(function(cx, cy, plan)
        n = n + 1
        local obj = acquire(drawer, n * 2, parent)
        if obj then
          local dotVia = paintDot(obj, parent, cx, cy, plan.size, r, g, b, dotAlpha, space, 7)
          painted = painted + 1
          measured(cx, cy)
          if not drawer.lastApplied.sampleDot then
            drawer.lastApplied.sampleDot = D.ReadBack(obj, {
              requested = { r, g, b, dotAlpha },
              via = dotVia,
              requestedAlpha = dotRequested,
              planned = plan.size,
              screen = plan.size * (m.scale > 0 and m.scale or 1),
            })
          end
        else
          missing = missing + 1
        end
      end)
      index = n * 2 + 1
      return index, painted, missing, first
    end

    -- ── The plan must fit the regions this client actually hands out ────────
    -- A client that stops creating regions used to lose every dot past the
    -- ceiling, silently: the route painted its opening leg and nothing else
    -- while the diag still read `dots=<the whole plan>`. The paint now counts
    -- what it really painted, and the plan is re-fitted onto the objects that
    -- exist, so the chain still spans the route end to end.
    --
    -- Two rules keep that re-fit honest, both measured rather than assumed:
    --   * a plan is only ever PAINTED when its dot count already fits.
    --     paint() writes the pool from index 1, so painting a plan that does
    --     not fit leaves enormous dots in the pool for numbers that describe a
    --     different plan (19 dots measuring 1034 px while the diag claimed the
    --     normal 4.31 px, which is what "painted anyway, then abandoned" does);
    --   * widening stops at the coarsest plan (one step per segment, both
    --     endpoints). Past that point PlanDots cannot get smaller, so widening
    --     again only inflates the dots and still drops the tail.
    --- Dots `paint` would paint for `plans` — the count that costs regions.
    local function plannedDots(plans)
      local n = 0
      for i = 1, count do
        local plan = plans[i]
        if buf[i] and plan and plan.steps > 0 then
          n = n + plan.steps + 1
        end
      end
      return n
    end

    --- Widest plan that fits `maxDots`, by planning only (no painting).
    --- @return plans|nil, dots, widen — nil when even the coarsest plan is too
    ---   big: widening cannot fit it, so the caller keeps the normal plan and
    ---   reports the shortfall instead of painting 1000px squares.
    local function planFitting(maxDots)
      if type(maxDots) ~= "number" or maxDots < 2 then
        return nil
      end
      local plain, plainTotal = D.PlanDots(buf, count, m, 1)
      if plainTotal <= maxDots then
        return plain, plainTotal, 1
      end
      -- The floor: one step per segment. Both endpoints are always drawn.
      local _, coarse = D.PlanDots(buf, count, m, 1024)
      if coarse > maxDots then
        return nil
      end
      local lo, hi = 1, 2
      local bestP, bestT
      for _ = 1, 12 do
        local p, t = D.PlanDots(buf, count, m, hi)
        if t <= maxDots then
          bestP, bestT = p, t
          break
        end
        lo, hi = hi, hi * 2
      end
      if not bestP then
        return nil
      end
      for _ = 1, 10 do
        local mid = (lo + hi) * 0.5
        local pm, tm = D.PlanDots(buf, count, m, mid)
        if tm <= maxDots then
          hi, bestP, bestT = mid, pm, tm
        else
          lo = mid
        end
      end
      return bestP, bestT, hi
    end

    drawer.createFailed = 0
    -- A recorded ceiling is a MEASURED LOWER BOUND, not a verdict on the client:
    -- one transient CreateTexture refusal used to latch a small ceiling (and the
    -- widen it forced) for the rest of the session, so every later draw stayed
    -- shortened with no way back. Probe one region past it: a create that
    -- succeeds there proves the old number was a refusal, and the next plan may
    -- be the full one again.
    local capacityStale = false
    if drawer.capacity and drawer.capacity > 0 then
      if acquire(drawer, drawer.capacity + 1, parent) then
        drawer.capacity, drawer.widenHint = nil, nil
        drawer.createFailed = 0
        capacityStale = true
      end
    end

    local maxDots = drawer.capacity and math.floor(drawer.capacity / 2) or nil
    local plans, total, widen, fitted
    if maxDots and maxDots >= 2 then
      plans, total, widen = planFitting(maxDots)
      fitted = plans ~= nil
    end
    if not plans then
      widen = drawer.widenHint or 1
      plans, total = D.PlanDots(buf, count, m, widen)
    end
    local index, painted, missing, first = paint(plans)
    local replans, reverted = 0, false
    while missing > 0 and drawer.capacity and replans < 4 do
      local capDots = math.floor(drawer.capacity / 2)
      if capDots < 2 then
        break
      end
      local p2, t2, w2 = planFitting(capDots)
      if not p2 or plannedDots(p2) > capDots then
        -- Nothing wider fits (or the arithmetic disagrees with the plan):
        -- painting it would leave oversized dots and still lose the tail.
        break
      end
      local i2, painted2, missing2, first2 = paint(p2)
      if missing2 ~= 0 then
        -- The plan fitted on paper but the client refused regions anyway.
        -- Put the chain the reported numbers describe back in the pool: a
        -- half-painted retry under the first plan's numbers is the incoherent
        -- state this whole block exists to prevent.
        index, painted, missing, first = paint(plans)
        reverted = true
        break
      end
      widen, plans, total = w2, p2, t2
      index, painted, missing, first = i2, painted2, missing2, first2
      replans = replans + 1
    end
    -- Start the next draw at the width this client actually needed, so a route
    -- on a capped surface does not re-discover the ceiling on every redraw.
    -- A reverted retry proves nothing about the width, so it teaches nothing.
    if (replans > 0 or fitted) and not reverted then
      drawer.widenHint = (widen and widen > 1) and widen or nil
    end
    hideFrom(drawer, index, true)
    painted = (total > 0) and painted or 0
    drawer.lastApplied.dots = painted
    drawer.lastApplied.paintedDots = painted
    drawer.lastApplied.dotObjects = (total > 0) and (index - 1) or 0
    drawer.lastApplied.plannedDots = total
    drawer.lastApplied.missingDots = missing
    drawer.lastApplied.poolHigh = drawer.poolHigh or 0
    -- t_57550700: the tripwire. After every draw the pool holds exactly the
    -- objects of the plan on screen (two per dot). A `highest` above that is the
    -- one-way ratchet that left 428 objects of earlier plans parented to the
    -- map — say so instead of hiding it behind a flag that never fired.
    drawer.lastApplied.stale = (tonumber(drawer.poolHigh) or 0) > (2 * painted)
    drawer.lastApplied.capacity = drawer.capacity
    drawer.lastApplied.replans = replans
    drawer.lastApplied.hiddenDots = drawer.hiddenDots
    drawer.lastApplied.reverted = reverted
    drawer.lastApplied.capacityStale = capacityStale
    drawer.lastApplied.createFailed = drawer.createFailed
    drawer.lastApplied.dotOutside = outside
    drawer.lastApplied.dotBox = box[1] and box or nil
    drawer.lastApplied.hostSize = (hostW and hostH) and { width = hostW, height = hostH } or nil
    drawer.lastApplied.widen = widen
    drawer.lastApplied.hideFromIndex = drawer.hideFromIndex
    drawer.lastApplied.hiddenByHide = drawer.hiddenCount
    drawer.lastApplied.dotSize = first and first.size or nil
    drawer.lastApplied.dotSpacing = first and first.spacing or nil
    drawer.lastApplied.dotOutline = first and (first.size * rimRatio) or nil
    drawer.lastApplied.dotScale = m.scale
    drawer.lastApplied.dotScreenSize = m.screenSize
    drawer.lastApplied.dotScreenSpacing = m.screenSpacing
    drawer.lastApplied.dotScreenOutline = m.screenOutline
    -- Geometric clearance between a neighbouring rim and this core. With
    -- overlapping cores this is negative; the two-pass paint (rims, then
    -- cores) is what keeps the stroke from being buried, not the gap.
    drawer.lastApplied.dotClearance =
      m.screenSpacing - (m.screenOutline + m.screenSize) * 0.5
    drawer.lastApplied.dotCoreOverlap = m.screenSize - m.screenSpacing
    drawer.lastApplied.dotFloor = m.screenFloor
    drawer.lastApplied.dotPathWidth = m.pathWidth
    return
  end
  -- A dark under-stroke, then the coloured stroke, two regions per segment.
  local outlineW = (tonumber(thickness) or 2) + 2
  if outlineW < 3 then outlineW = 3 end
  local function paintSeg(obj, x1, y1, x2, y2, w, cr, cg, cb, ca)
    if drawer.mode == "line" then
      paintLine(obj, parent, x1, y1, x2, y2, w, cr, cg, cb, ca, space)
    elseif drawer.mode == "rotate" then
      paintRotate(obj, parent, x1, y1, x2, y2, w, cr, cg, cb, ca, space)
    else
      local sx, sy, ex, ey = toBottomLeft(parent, x1, y1, x2, y2, space)
      paintTexCoord(obj, parent, sx, sy, ex, ey, w, cr, cg, cb, ca)
    end
  end
  for i = 1, count do
    local seg = buf[i]
    if seg then
      local x1, y1, x2, y2 = seg[1], seg[2], seg[3], seg[4]
      local under = acquire(drawer, i * 2 - 1, parent)
      if under then
        paintSeg(under, x1, y1, x2, y2, outlineW, DOT_OUTLINE_R, DOT_OUTLINE_G, DOT_OUTLINE_B, DOT_OUTLINE_A)
      end
      local obj = acquire(drawer, i * 2, parent)
      if obj then
        paintSeg(obj, x1, y1, x2, y2, thickness, r, g, b, a)
      end
    end
  end
  hideFrom(drawer, count * 2 + 1, false)
end


-- ── Direction chevrons and start/end/loop markers ─────────────────────
-- Drawn from a SEPARATE drawer so the stroke pool's rim/core pairing
-- (and every mapdiag / capacity spec that reads it) stays unchanged.
-- On Forever, SetRotation is proved and SetColorTexture can succeed
-- while painting an untextured black square. Decorations therefore
-- use the same WHITE8X8 + SetVertexColor path as the rotate stroke.
-- A chevron is a short rotated bar along the path; start/end/loop
-- markers are small filled squares with a thin dark rim. If rotation
-- is unavailable, a chevron falls back to one small coloured square
-- (never a black block, and never a cluster of three squares).

local DECOR_CHEV_LEN = 8    -- screen px length of a chevron bar
local DECOR_CHEV_THICK = 3  -- screen px thickness of a chevron bar
local DECOR_MARK = 7        -- screen px of a start/end/loop marker
local DECOR_LOOP_GROW = 2
local DECOR_RIM = 1         -- screen px the dark rim adds (subtle)

local function decorSize(screen, scale)
  scale = (tonumber(scale) and scale > 0) and scale or 1
  return screen / scale
end

--- A filled square painted with WHITE8X8 + vertex colour (never
--- SetColorTexture). Size setters + a centre point when the client
--- kept them; two-corner anchors otherwise.
local function paintSolid(obj, parent, cx, cy, size, r, g, b, a, space, sub)
  obj:SetParent(parent)
  if obj.SetTexture then
    pcall(obj.SetTexture, obj, WHITE)
  end
  if obj.SetVertexColor then
    pcall(obj.SetVertexColor, obj, r, g, b, a)
  end
  if obj.SetAlpha then
    pcall(obj.SetAlpha, obj, 1)
  end
  if obj.SetDrawLayer then
    pcall(obj.SetDrawLayer, obj, "OVERLAY", sub or 8)
  end
  if obj.SetBlendMode then
    pcall(obj.SetBlendMode, obj, "BLEND")
  end
  if obj.SetTexCoord then
    pcall(obj.SetTexCoord, obj, 0, 1, 0, 1)
  end
  obj:ClearAllPoints()
  if obj.SetWidth and obj.SetHeight then
    pcall(obj.SetWidth, obj, size)
    pcall(obj.SetHeight, obj, size)
    if space == "yup" then
      obj:SetPoint("CENTER", parent, "CENTER", cx, cy)
    else
      obj:SetPoint("CENTER", parent, "TOPLEFT", cx, -cy)
    end
    if obj.SetRotation then
      pcall(obj.SetRotation, obj, 0)
    end
  else
    local half = (size or 2) * 0.5
    if space == "yup" then
      obj:SetPoint("BOTTOMLEFT", parent, "CENTER", cx - half, cy - half)
      obj:SetPoint("TOPRIGHT", parent, "CENTER", cx + half, cy + half)
    else
      obj:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", cx - half, -(cy + half))
      obj:SetPoint("TOPRIGHT", parent, "TOPLEFT", cx + half, -(cy - half))
    end
  end
  obj:Show()
end

function D.DrawDecor(drawer, parent, items, count, r, g, b, a, space, metrics)
  if not drawer or not parent then
    return
  end
  if drawer.parent ~= parent then
    D.Invalidate(drawer)
    drawer.parent = parent
  end
  if not drawer.mode then
    -- Prefer the proved rotate path for decorations too. Texcoord stays
    -- non-default unless `/nt linetest` pinned it.
    drawer.disableLine = true
    detect(drawer, parent)
    if drawer.mode == "texcoord" and D._forceMode ~= "texcoord" then
      local rot = drawer.capability and drawer.capability.rotate
      if type(rot) == "table" and rot.took then
        drawer.mode = "rotate"
      elseif type(parent.CreateTexture) == "function" then
        drawer.mode = "dots"
      end
    end
  end
  count = count or 0
  if drawer.mode == "none" or count < 1 then
    D.Clear(drawer)
    drawer.lastApplied = drawer.lastApplied or {}
    drawer.lastApplied.paintedDots = 0
    drawer.lastApplied.plannedDots = 0
    drawer.lastApplied.poolHigh = drawer.poolHigh or 0
    return
  end
  local scale = 1
  if type(metrics) == "table" and tonumber(metrics.scale) and metrics.scale > 0 then
    scale = metrics.scale
  end
  local chevLen = math.max(0.75, decorSize(DECOR_CHEV_LEN, scale))
  local chevThick = math.max(0.75, decorSize(DECOR_CHEV_THICK, scale))
  local mark = decorSize(DECOR_MARK, scale)
  local loop = decorSize(DECOR_MARK + DECOR_LOOP_GROW, scale)
  local rimGrow = decorSize(DECOR_RIM, scale)
  local useRotate = drawer.mode == "rotate"
  local index, painted = 1, 0
  -- A same-colour mark on a same-colour stroke disappears, so every
  -- decoration gets a thin dark rim. The rim is 1 screen px, not the
  -- 2 px stroke outline, so it stays a hairline and not a black block.
  local function paintMark(cx, cy, size, cr, cg, cb, ca, sub, rim)
    if rim ~= false then
      local under = acquire(drawer, index, parent)
      index = index + 1
      if under then
        paintSolid(under, parent, cx, cy, size + rimGrow,
          DOT_OUTLINE_R, DOT_OUTLINE_G, DOT_OUTLINE_B, DOT_OUTLINE_A, space, (sub or 8) - 1)
      end
    end
    local obj = acquire(drawer, index, parent)
    index = index + 1
    if obj then
      paintSolid(obj, parent, cx, cy, size, cr, cg, cb, ca, space, sub or 8)
      painted = painted + 1
    end
  end
  local function paintBar(cx, cy, dx, dy, length, thickness, cr, cg, cb, ca, sub, rim)
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1e-8 then
      dx, dy, len = 1, 0, 1
    end
    dx, dy = dx / len, dy / len
    local hx, hy = dx * length * 0.5, dy * length * 0.5
    local x1, y1, x2, y2 = cx - hx, cy - hy, cx + hx, cy + hy
    if rim ~= false then
      local under = acquire(drawer, index, parent)
      index = index + 1
      if under then
        paintRotate(under, parent, x1, y1, x2, y2, thickness + rimGrow,
          DOT_OUTLINE_R, DOT_OUTLINE_G, DOT_OUTLINE_B, DOT_OUTLINE_A, space, (sub or 8) - 1)
      end
    end
    local obj = acquire(drawer, index, parent)
    index = index + 1
    if obj then
      paintRotate(obj, parent, x1, y1, x2, y2, thickness, cr, cg, cb, ca, space, sub or 8)
      painted = painted + 1
    end
  end
  -- A closed path plans both a start and a loop at the first vertex.
  -- Drawing both would stack two marks; keep the slightly larger loop.
  local hasLoop = false
  for i = 1, count do
    local it = items[i]
    if type(it) == "table" and it.kind == "loop" then
      hasLoop = true
      break
    end
  end
  for i = 1, count do
    local it = items[i]
    if type(it) == "table" and type(it.x) == "number" and type(it.y) == "number" then
      if it.kind == "chevron" then
        if useRotate then
          paintBar(it.x, it.y, tonumber(it.dx) or 0, tonumber(it.dy) or 0,
            chevLen, chevThick, r, g, b, a, 8)
        else
          -- One small coloured square, not three overlapping ones.
          paintMark(it.x, it.y, chevThick, r, g, b, a, 8)
        end
      elseif it.kind == "loop" then
        -- Rust core with a thin dark rim — never a solid black square.
        paintMark(it.x, it.y, loop, r, g, b, a, 8)
      elseif it.kind == "end" then
        paintMark(it.x, it.y, mark, r, g, b, a, 8)
      elseif it.kind == "start" or it.kind == nil then
        if not hasLoop then
          paintMark(it.x, it.y, mark, r, g, b, a, 8)
        end
      end
    end
  end
  hideFrom(drawer, index, false)
  drawer.lastApplied = drawer.lastApplied or {}
  drawer.lastApplied.paintedDots = painted
  drawer.lastApplied.plannedDots = painted
  drawer.lastApplied.poolHigh = drawer.poolHigh or 0
  drawer.lastApplied.mode = drawer.mode
end


--- Plan and paint decorations onto a holder-owned drawer (`field`).
--- `pts` is a list of already-projected {x,y} points (host units).
--- Scratch arrays live on the holder so a redraw allocates nothing new.
function D.ApplyDecor(holder, field, host, pts, r, g, b, a, space, metrics, clip)
  if type(holder) ~= "table" or type(ns.PathGeom) ~= "table" then
    return
  end
  local G = ns.PathGeom
  local drawer = holder[field]
  if not drawer then
    drawer = D.Create()
    holder[field] = drawer
  end
  if type(pts) ~= "table" or #pts < 1 or not host then
    D.Clear(drawer)
    return
  end
  local scale = 1
  if type(metrics) == "table" and tonumber(metrics.scale) and metrics.scale > 0 then
    scale = metrics.scale
  end
  -- About 48 screen px between chevrons, in this surface's units.
  local spacing = 48 / scale
  holder._chevBuf = holder._chevBuf or {}
  holder._markBuf = holder._markBuf or {}
  holder._decorBuf = holder._decorBuf or {}
  holder._clipBuf = holder._clipBuf or {}
  local chevs, cn = G.PlaceChevrons(pts, spacing, holder._chevBuf)
  local marks, mn = G.PlaceMarkers(pts, holder._markBuf)
  local buf, n = holder._decorBuf, 0
  for i = 1, mn do
    n = n + 1
    buf[n] = marks[i]
  end
  for i = 1, cn do
    n = n + 1
    buf[n] = chevs[i]
  end
  for i = #buf, n + 1, -1 do
    buf[i] = nil
  end
  -- Drop decorations whose centre sits outside the surface's clip (the
  -- minimap circle, or the visible world-map window). Stroke segments are
  -- already clipped; without this, a chevron or marker on an unprojected
  -- or off-screen vertex paints into the rest of the UI.
  if clip then
    buf, n = G.ClipItems(buf, n, clip, holder._clipBuf)
  end
  D.DrawDecor(drawer, host, buf, n, r, g, b, a, space, metrics)
end

--- Run every stroke proof on `parent` and return a report. `/nt linetest`
--- prints this and, when a method is proved, pins it for the rest of the
--- session so the next redraw uses it.
function D.RunLineTest(parent)
  local report = {
    recommended = "dots",
    line = { took = false, why = "no parent" },
    dots = { canAnchor = false, why = "no parent" },
    rotate = { took = false, why = "no parent" },
    texcoord = { took = false, why = "no parent" },
  }
  if not parent then
    return report
  end
  if type(parent.CreateLine) == "function" then
    report.line = D.LineProof(parent)
  else
    report.line = { took = false, why = "the client exposes no Frame:CreateLine" }
  end
  if type(parent.CreateTexture) == "function" then
    local ok, tex = pcall(parent.CreateTexture, parent, nil, "OVERLAY")
    if ok and tex then
      report.dots = D.TextureProof(tex, parent)
      report.rotate = D.RotateProof(tex)
      report.texcoord = D.TexCoordProof(tex)
      pcall(tex.Hide, tex)
    else
      report.dots = { canAnchor = false, why = "CreateTexture raised or returned nothing" }
    end
  else
    report.dots = { canAnchor = false, why = "the host exposes no CreateTexture" }
  end
  local cap = { line = report.line, rotate = report.rotate, texcoord = report.texcoord, dots = report.dots }
  report.recommended = D.PickStrokeMode(cap, nil)
  if report.recommended == "dots" and report.dots and report.dots.canAnchor == false then
    report.recommended = "none"
  end
  return report
end

-- Host opt-out: a host that vendors these files sets TouchstoneSkip = true before
-- loading them, and every shipped file returns at this line. Unset -- the normal
-- case -- nothing changes. See README.md, "Embedding Touchstone in a host addon".
if TouchstoneSkip then return end
-- Marks.lua — the green-up arrow, its art, and its ONE clock.
--
-- Card t_ee6dec52 ("Slice 1"): bag arrows, quest-reward marks and GearAPI ride
-- the verdict that already exists. This file draws the MARK ONLY. It computes
-- no verdict, reads no tooltip, opens no container and knows nothing about
-- items: a caller that has already decided "this cell is an UPGRADE" (through
-- ChestAdvisor._markKind, the one decision every surface asks) attaches an
-- arrow here, and detaches it when the cell is no longer an upgrade.
--
-- WHY A FRAME AND NOT A TEXTURE ON THE BUTTON (the previous shape was
-- button:CreateTexture, 18x18, TOPRIGHT +1,+1). The card's §10 table puts the
-- arrow at FrameLevel(button) + 2, and a texture created on the button shares
-- the button's own frame level — the cooldown swipe and the stack count are
-- children of the button and are drawn over a same-level texture. A frame
-- parented to the button, raised two levels, is the only way to guarantee the
-- arrow is never overdrawn. It also gives the mark its own three textures
-- (glow / darkened copy / arrow), which is what the art direction needs.
--
-- ONE CLOCK. Every arrow registers with the single driver frame below. The
-- driver reads GetTime() ONCE per frame and stamps `t` on the clock it owns;
-- each arrow's bob offset and glow alpha are computed from that one stamped
-- value, so two arrows can never be a frame apart. The driver's OnUpdate is
-- installed when the first arrow registers and REMOVED when the last one
-- detaches — an idle bag costs no per-frame work at all.
--
-- The motion is the card's formula, in one place:
--
--     up(t)   = 0.5 - 0.5 * cos(2*pi*t/PERIOD)      -- 0 .. 1, period 1.6s
--     posY    = baseY - up(t) * BOB                 -- 2 px of travel
--     glow    = GLOW_LOW + (GLOW_HIGH - GLOW_LOW) * up(t)
--
-- NO NEW ART. The arrow is the addon's already-shipped marker.tga (the game's
-- up-arrow, loaded by path and named in the toc's ## Assets line); the
-- "darkened copy of itself" is the same texture drawn at DARKEN vertex colour
-- behind the bright one, and the glow is an additive green SetColorTexture —
-- a colour, not an asset. The toc grows no asset line for this card.
--
-- Published on the host table when one exists (the in-game loader creates
-- StatForge in Constants.lua); the global below is the load-order-independent
-- handle ChestAdvisor resolves at CALL time, so a harness that loads this file
-- alone or in either order still finds it.

-- §10 GREEN, now the One Ledger upgrade colour (audit C2): read from the host
-- palette (StatForge.VerdictColour, Constants.lua) when the arrow is BUILT, so the
-- glow is the same green as the tooltip line and the ledger. The copy below is the
-- fallback for a harness with no host core; it must equal Constants.lua's
-- `success` (#22C55E), and the PR 3 test leg fails if it drifts. Was 0.2, 1, 0.6.
local GREEN_FALLBACK = { 0.133, 0.773, 0.369 }
local function green()
	local sf = rawget(_G, "StatForge")
	if type(sf) == "table" and type(sf.VerdictColour) == "function" then
		local ok, c = pcall(sf.VerdictColour, "upgrade")
		if ok and type(c) == "table" and type(c[1]) == "number"
			and type(c[2]) == "number" and type(c[3]) == "number" then
			return c[1], c[2], c[3]
		end
	end
	return GREEN_FALLBACK[1], GREEN_FALLBACK[2], GREEN_FALLBACK[3]
end
local INSET  = 2                                 -- §10 INSET
local SIZE   = 15                                -- §10 SIZE
local BOB    = 2                                 -- §10 BOB (px)
local PERIOD = 1.6                               -- §10 PERIOD (s)
local GLOW_LOW, GLOW_HIGH = 0.1, 0.35            -- §10 GLOW_LOW / GLOW_HIGH
local GLOW_OUT = 5                               -- §10 GLOW_OUT (px each side)
-- Audit B5 / C6: the bob is a 1.6 s cycle, so placing every arrow on every
-- rendered frame (60+ fps, two pcalls per arrow) buys nothing a 30 fps update
-- does not show. The driver still runs every frame, but it re-places the arrows
-- at most MAX_FPS times a second; a frame inside the interval returns at once.
local MAX_FPS = 30
local MIN_STEP = 1 / MAX_FPS
-- Half a millisecond of slack for float rounding: two 60 Hz frames add up to
-- 1/30 s give or take an ulp. The accumulator below subtracts the full MIN_STEP
-- on every placement, so the slack never raises the long-run rate above 30.
local STEP_SLACK = 0.0005

--- The marker texture path, resolved at the point of use.
---
--- The host core publishes the base (SF.AssetPath) because a host that vendors
--- these files keeps the art under its own folder. This file reads it when it is
--- there and falls back to its own installed folder when it is not: in game
--- Constants.lua loads first, but the advisor suite loads Verdict + ChestAdvisor
--- alone, with no host core at all, and that case must not throw.
local function assetPath(name)
  local sf = rawget(_G, "StatForge")
  if type(sf) == "table" and type(sf.AssetPath) == "function" then
    return sf.AssetPath(name)
  end
  return "Interface\\AddOns\\Touchstone\\ChestAdvisor\\" .. tostring(name)
end
-- The arrow path comes from SF.AssetPath where the texture is SET, not from a
-- load-time copy: a host that vendors this file keeps the art under its own
-- folder and sets the base once.
-- The darkened copy behind the bright arrow. Multiplicative on the same
-- texture: dark enough to read as a contrast edge, light enough that the
-- arrow's own shape still registers.
local DARKEN = 0.25

local GLOW_SIZE = SIZE + 2 * GLOW_OUT

local Marks = {}
Marks.name = "TouchstoneMarks"
Marks.VERSION = 1

TouchstoneMarks = Marks
local host = rawget(_G, "StatForge")
if type(host) == "table" then host.Marks = Marks end

-- ---- the clock -------------------------------------------------------------
-- `driverFrame` is created lazily (a bag that never shows an upgrade never
-- creates it), `running` is the honest record of whether OnUpdate is
-- installed, and `clock` is the last `t` the driver stamped — the value every
-- arrow in that frame read. Tests and /up diag read it through State().
local driverFrame = nil
local running = false
local clock = 0
-- B5 throttle state: an accumulator of elapsed time. `lastTick` is the GetTime()
-- of the previous tick (nil until the first one, so the first tick after a start
-- always places); `acc` is the time banked since the last placement. Each
-- placement spends one MIN_STEP and carries the remainder, so the rate holds ~30
-- at any refresh rate (60, 75, 144 Hz) instead of rounding down to a divisor of
-- it. placedTicks / skippedTicks count the work — the observable the leg reads.
local lastTick = nil
local acc = 0
local placedTicks, skippedTicks = 0, 0
-- C6: the parked-animation seam. While false the driver never installs and each
-- arrow is placed once, at rest, when it attaches (no bob, steady glow). Default
-- true: the arrows animate as they do today.
local animated = true

-- The live arrows, in registration order. Entries are plain tables:
--   { frame = <Frame>, button = <Frame>, glow = <Texture> }
-- A registry (not a pairs() walk over frames) so the per-frame loop is an
-- array walk and detach cannot mutate what it is iterating.
local arrows = {}
local arrowCount = 0

local function now()
	if type(GetTime) == "function" then
		local ok, t = pcall(GetTime)
		if ok and type(t) == "number" then return t end
	end
	return 0
end

--- The card's motion, as three pure functions. Exposed so a test can assert
--- the formula itself rather than only the frame state it produced.
function Marks.up(t)
	if type(t) ~= "number" then return 0 end
	return 0.5 - 0.5 * math.cos(2 * math.pi * t / PERIOD)
end

function Marks.offset(t)
	return Marks.up(t) * BOB
end

function Marks.glow(t)
	return GLOW_LOW + (GLOW_HIGH - GLOW_LOW) * Marks.up(t)
end

-- Reposition one arrow for the stamped time. The anchor is re-set every frame
-- because the client has no "adjust this anchor's offset" call: the arrow's
-- baseY is -(INSET) and the bob subtracts from it, so the travel is exactly
-- BOB pixels and the rest position is INSET inside the button's top edge.
local function place(entry, t)
	local f, button = entry.frame, entry.button
	if type(f) ~= "table" or type(button) ~= "table" then return end
	local y = -(INSET + Marks.offset(t))
	if type(f.SetPoint) == "function" then
		pcall(f.SetPoint, f, "TOPRIGHT", button, "TOPRIGHT", -INSET, y)
	end
	entry.baseY = y
	local glow = entry.glow
	if type(glow) == "table" and type(glow.SetAlpha) == "function" then
		pcall(glow.SetAlpha, glow, Marks.glow(t))
	end
end

local tick

local function startDriver()
	if running then return end
	if not driverFrame then
		if type(CreateFrame) ~= "function" then return end
		driverFrame = CreateFrame("Frame", "TouchstoneMarkClock")
		driverFrame:SetSize(1, 1)
		-- Never a mouse surface: the bag cell's mouse belongs to the button
		-- (the §5a live report — "I can no longer pick up the chest").
		if type(driverFrame.EnableMouse) == "function" then
			driverFrame:EnableMouse(false)
		end
	end
	if type(driverFrame.SetScript) ~= "function" then return end
	running = true
	lastTick = nil
	acc = 0
	driverFrame:SetScript("OnUpdate", tick)
end

local function stopDriver()
	if not running then return end
	running = false
	if type(driverFrame) == "table" and type(driverFrame.SetScript) == "function" then
		-- Removing the script is the stop: a hidden-but-scripted frame would
		-- still run every frame, which is exactly what the card forbids.
		driverFrame:SetScript("OnUpdate", nil)
	end
end

tick = function()
	local t = now()
	-- B5: at most MAX_FPS placements a second, by accumulator. The first tick
	-- after a start places; so does a clock that went backwards (a harness
	-- resetting time), which also empties the bank.
	if lastTick == nil or t < lastTick then
		acc = MIN_STEP
	else
		acc = acc + (t - lastTick)
	end
	lastTick = t
	if acc < (MIN_STEP - STEP_SLACK) then
		skippedTicks = skippedTicks + 1
		return
	end
	acc = acc - MIN_STEP
	-- A long hitch (a loading screen, a stalled frame) must not bank a burst of
	-- catch-up placements: keep less than one step in hand.
	if acc >= MIN_STEP then acc = 0 end
	placedTicks = placedTicks + 1
	clock = t
	for i = 1, arrowCount do
		place(arrows[i], clock)
	end
end

-- ---- the arrow -------------------------------------------------------------
local function buildArrow(button)
	local f = CreateFrame("Frame", nil, button)
	if not f then return nil end
	-- The arrow's own transform is free of the pixel grid (the bob travels in
	-- sub-pixel steps); the LAYOUT stays snapped — nothing else is told to
	-- unsnap.
	if type(f.SetSnapToPixelGrid) == "function" then
		f:SetSnapToPixelGrid(false)
	end
	f:SetSize(SIZE, SIZE)
	-- Above the cooldown swipe and the count, inside the button.
	if type(f.SetFrameLevel) == "function" and type(button.GetFrameLevel) == "function" then
		f:SetFrameLevel(button:GetFrameLevel() + 2)
	end
	if type(f.EnableMouse) == "function" then
		f:EnableMouse(false)
	end

	-- 1. The additive green glow, behind everything. A colour, not an asset.
	local glow = f:CreateTexture(nil, "BACKGROUND")
	local gr, gg, gb = green()
	glow:SetColorTexture(gr, gg, gb, GLOW_HIGH)
	glow:SetSize(GLOW_SIZE, GLOW_SIZE)
	glow:SetPoint("CENTER", f, "CENTER", 0, 0)
	if type(glow.SetBlendMode) == "function" then
		glow:SetBlendMode("ADD")
	end

	-- 2. The darkened copy of the arrow — the same art, dark, behind the
	-- bright one, so the mark reads against a light item icon as well as a
	-- dark one. Not a second icon set: one texture, one vertex colour.
	local dark = f:CreateTexture(nil, "ARTWORK")
	dark:SetTexture(assetPath("marker.tga"))
	dark:SetSize(SIZE, SIZE)
	dark:SetPoint("CENTER", f, "CENTER", 0, 0)
	if type(dark.SetVertexColor) == "function" then
		dark:SetVertexColor(DARKEN, DARKEN, DARKEN, 1)
	end
	if type(dark.SetBlendMode) == "function" then
		dark:SetBlendMode("BLEND")
	end

	-- 3. The arrow itself, the game's up-arrow, untinted.
	local arrow = f:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture(assetPath("marker.tga"))
	arrow:SetSize(SIZE, SIZE)
	arrow:SetPoint("CENTER", f, "CENTER", 0, 0)
	if type(arrow.SetVertexColor) == "function" then
		arrow:SetVertexColor(1, 1, 1, 1)
	end

	f.__glow = glow
	f.__dark = dark
	f.__arrow = arrow
	return f
end

--- Attach the green arrow to `button`, or reuse the one already there.
--- Returns the arrow frame (nil when the client gave us no frame). A re-attach
--- re-registers only once: the frame on the button is the registry key.
function Marks.Attach(button)
	if type(button) ~= "table" then return nil end
	local f = button.ChestAdvisorArrow
	if type(f) ~= "table" or type(f.SetShown) ~= "function" then
		-- NOT pcall'd, deliberately: this addon publishes the verdict rows
		-- BEFORE it renders (card t_44f0b2d9 / AC20's ordering fix), and the
		-- render path is allowed to raise so that contract stays observable —
		-- a silently swallowed texture failure would make "the record survived
		-- a broken render" untestable and hide a real client failure.
		local built = buildArrow(button)
		if type(built) ~= "table" then return nil end
		f = built
		button.ChestAdvisorArrow = f
		local entry = { frame = f, button = button, glow = f.__glow }
		f.__entry = entry
		arrows[arrowCount + 1] = entry
		arrowCount = arrowCount + 1
	elseif type(f.__entry) ~= "table" then
		-- A frame that survived a lost entry (a harness reloaded this file):
		-- re-register it rather than draw a second arrow on the same cell.
		local entry = { frame = f, button = button, glow = f.__glow }
		f.__entry = entry
		arrows[arrowCount + 1] = entry
		arrowCount = arrowCount + 1
	end
	if type(f.SetShown) == "function" then pcall(f.SetShown, f, true) end
	if animated then
		place(f.__entry, now())
		startDriver()
	else
		-- Parked: the rest position (up(0) = 0, so no bob and the low glow), once.
		place(f.__entry, 0)
	end
	return f
end

--- C6: turn the arrow animation on or off (the parked-animation seam). Off stops
--- the driver and puts every live arrow at rest; on re-places them and restarts
--- the driver when any arrow is showing. Returns the setting now in force. Not a
--- saved setting: a host that parks the animation calls this after loading.
function Marks.SetAnimated(on)
	animated = on and true or false
	if animated then
		if arrowCount > 0 then
			local t = now()
			for i = 1, arrowCount do place(arrows[i], t) end
			startDriver()
		end
	else
		stopDriver()
		for i = 1, arrowCount do place(arrows[i], 0) end
	end
	return animated
end

function Marks.IsAnimated()
	return animated
end

--- Take the arrow off `button` (hide it and stop animating it). Idempotent:
--- a button that carries no arrow is not an error.
function Marks.Detach(button)
	local f = type(button) == "table" and button.ChestAdvisorArrow or nil
	if type(f) ~= "table" then return false end
	if type(f.SetShown) == "function" then pcall(f.SetShown, f, false) end
	local entry = f.__entry
	if type(entry) == "table" and entry.frame == f then
		for i = 1, arrowCount do
			if arrows[i] == entry then
				table.remove(arrows, i)
				arrowCount = arrowCount - 1
				break
			end
		end
		f.__entry = nil
	end
	if arrowCount == 0 then stopDriver() end
	return true
end

--- Hide every arrow and stop the clock. The scan's teardown point calls this
--- through its own per-marker walk; it exists here for a full reset (/up reset
--- paths and tests).
function Marks.DetachAll()
	for i = arrowCount, 1, -1 do
		local entry = arrows[i]
		if type(entry) == "table" then
			local f = entry.frame
			if type(f) == "table" and type(f.SetShown) == "function" then
				pcall(f.SetShown, f, false)
			end
			if type(entry.button) == "table" then
				entry.button.ChestAdvisorArrow = nil
			end
			if type(f) == "table" then f.__entry = nil end
		end
		arrows[i] = nil
	end
	arrowCount = 0
	stopDriver()
end

-- ---- read surface ----------------------------------------------------------
--- Visible arrow count as the driver knows it. Not a frame-tree walk: the
--- registry IS the set of arrows the clock is animating.
function Marks.Visible()
	return arrowCount
end

--- Is the shared OnUpdate installed right now? This is the card's "the driver
--- stops when nothing is visible" observable — the answer is derived from the
--- driver frame's own script, not from a flag alone, so a harness that clears
--- the script behind our back cannot be told apart from a running driver.
function Marks.Running()
	if not running then return false end
	if type(driverFrame) ~= "table" then return true end
	if type(driverFrame.GetScript) == "function" then
		local ok, script = pcall(driverFrame.GetScript, driverFrame, "OnUpdate")
		if ok then return type(script) == "function" end
	end
	return true
end

--- One stamped clock value for every arrow. `t` is the last GetTime() the
--- driver read; `stamp` counts how many times it has read one this session so
--- a test can prove two arrows shared a frame rather than each keeping time.
function Marks.Clock()
	return clock
end

function Marks.Driver()
	return driverFrame
end

function Marks.State()
	local visible = 0
	for i = 1, arrowCount do
		local f = arrows[i] and arrows[i].frame
		if type(f) == "table" then
			local shown = true
			if type(f.IsShown) == "function" then
				local ok, s = pcall(f.IsShown, f)
				shown = ok and s == true
			end
			if shown then visible = visible + 1 end
		end
	end
	return {
		arrows = arrowCount,
		visible = visible,
		running = Marks.Running(),
		clock = clock,
		animated = animated,
		placedTicks = placedTicks,
		skippedTicks = skippedTicks,
	}
end

--- The §10 constants, verbatim, as copies. A test asserts the card's numbers
--- rather than a reader re-typing them; a consumer cannot mutate the live set.
function Marks.Spec()
	return {
		GREEN = { green() },
		MAX_FPS = MAX_FPS,
		INSET = INSET,
		SIZE = SIZE,
		BOB = BOB,
		PERIOD = PERIOD,
		GLOW_LOW = GLOW_LOW,
		GLOW_HIGH = GLOW_HIGH,
		GLOW_OUT = GLOW_OUT,
		GLOW_SIZE = GLOW_SIZE,
		DARKEN = DARKEN,
		texture = assetPath("marker.tga"),
	}
end

return Marks

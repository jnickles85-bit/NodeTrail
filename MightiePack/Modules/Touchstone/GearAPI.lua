if MightiePackTouchstoneSkip then return end
-- GearAPI.lua — the public, versioned surface other addons read (card
-- t_ee6dec52, section C).
--
-- WHAT THIS FILE IS NOT. It is not a second scorer. Every answer below is read
-- from the ONE decision the addon already made: ChestAdvisor._judgement(link)
-- returns the row the verdict engine produced for that link (or nil), and
-- ChestAdvisor._isUpgrade(link) is the exact predicate the bag arrow asks
-- before it draws. GearAPI does not re-derive, re-weight or re-rank anything —
-- a caller that wants to know what we decided asks here instead of rebuilding
-- the decision, which is the whole point of the contract.
--
-- CONTRACT (the card's table, verbatim in behaviour):
--   safe to call any time      — every entry point is pcall-wrapped and
--                                degrades to nil/false rather than raising,
--                                including before ChestAdvisor exists at all
--   nil before data is ready   — before the first scan has judged anything,
--                                the readers return nil (not "false", which
--                                would be a decision we have not made)
--   never errors               — a caller in a tight loop cannot break us
--   hands out copies           — tables returned are fresh copies; mutating
--                                one cannot reach the addon's state
--
--   GetSpec()        -> classFile, spec, level, setup
--   IsUpgrade(link)  -> true | false | nil   (exactly the decision the arrow
--                       reads: true / judged-not-an-upgrade / no opinion)
--   GetGain(link)    -> the verdict's judgment for this item (nil when it
--                       cannot be told)
--   OnChanged(func)  -> fires whenever arrows are re-judged
--   GetStatKeys()    -> the editable word list
--
-- GetGain's name is the owner's; its value is a JUDGEMENT, not a number. The
-- engine states a verdict (UPGRADE / NOT_UPGRADE / TRADE_OFF / UNKNOWN) and a
-- sentence explaining it; a weighted total is Slice 3 and is parked. So the
-- copy carries `verdict`, `reason`, `slot`, `role`, `slotWord` and the epoch it
-- was judged in, and where the engine could not tell (an UNKNOWN row, or a link
-- we have never judged) the answer is nil — never 0, never a guessed score.

local GearAPI = {}
GearAPI.name = "TouchstoneGearAPI"
GearAPI.VERSION = 1

TouchstoneGearAPI = GearAPI
-- The card's own name, published for OTHER ADDONS: a bag addon, TSM or
-- MasterCraft asks `GearAPI.IsUpgrade(link)` and must not have to know our
-- folder's namespace. This goes through rawset because the local table is also
-- named GearAPI — a bare `GearAPI = GearAPI` would assign the local to itself
-- and publish nothing (the lesson this line exists to record).
rawset(_G, "GearAPI", GearAPI)
local host = rawget(_G, "StatForge")
if type(host) == "table" then host.GearAPI = GearAPI end

--- The advisor module, resolved at CALL time: this file loads after
-- ChestAdvisor.lua in game, and a harness may load it before the advisor or
-- without one at all.
local function advisor()
	local a = rawget(_G, "ChestAdvisor")
	if type(a) == "table" then return a end
	return nil
end

--- Has a scan judged anything yet? The readiness gate the contract promises.
-- "Not ready" is not "no upgrade": before the first judgement the honest answer
-- to every reader is nil.
local function ready(a)
	if type(a) ~= "table" then return false end
	if a._judged ~= true then return false end
	if type(a._judgement) ~= "function" then return false end
	return true
end

--- pcall every public entry point. A caller in another addon's OnUpdate loop
-- must never take an error out of here — and neither must a malformed link.
local function safe(fn, ...)
	local ok, a, b, c, d = pcall(fn, ...)
	if not ok then return nil end
	return a, b, c, d
end

-- ---- GetSpec ---------------------------------------------------------------
-- The four fields are the character identity the verdicts were judged for:
--   classFile — the client's class token ("WARRIOR", "PRIEST", ...)
--   spec      — the resolved role/spec word this addon judged for
--               ("melee" / "spell" / "healer" for hybrids, the class token for
--               a pure class with no role picker)
--   level     — UnitLevel("player") at judgement time
--   setup     — nil. This addon has no gear setups (custom setups are Slice 3
--               and are parked); nil is the honest answer, and a caller that
--               reads it must handle "no setup" rather than invent one.
function GearAPI.GetSpec()
	return safe(function()
		local a = advisor()
		if not ready(a) then return nil end
		local spec = type(a._spec) == "function" and a._spec() or nil
		if type(spec) ~= "table" then return nil end
		return spec.class, spec.role, spec.level, nil
	end)
end

-- ---- IsUpgrade -------------------------------------------------------------
-- EXACTLY the bag-arrow decision: the same function the marker branch calls,
-- passed through unchanged. GearAPI fabricates in neither direction.
-- true  — the engine judged this item an upgrade for the character
-- false — judged, and not an upgrade (including "equal" and "downgrade"). A
--         POSITIVE claim about a judgement that exists.
-- nil   — no opinion: before data is ready, the link has never been judged, the
--         row was judged in a superseded epoch, or the row's verdict is UNKNOWN
--         (the engine looked and could not tell). A caller drawing its own arrow
--         gets "I have no opinion", not a fabricated "no" — a false here would
--         make another addon suppress an item over our refusal.
function GearAPI.IsUpgrade(link)
	return safe(function()
		local a = advisor()
		if not ready(a) then return nil end
		if type(link) ~= "string" then return nil end
		local isUp = a._isUpgrade(link)
		-- Tri-state pass-through: nil stays nil (cannot judge), a real boolean
		-- is normalised by `== true` so nothing truthy-but-odd can leak out.
		if isUp == nil then return nil end
		return isUp == true
	end)
end

-- ---- GetGain ---------------------------------------------------------------
-- The engine's judgement for this item, as a fresh copy. nil where the engine
-- cannot state one (no row, or an UNKNOWN row): a caller must not read a
-- cannot-judge as a "no".
function GearAPI.GetGain(link)
	return safe(function()
		local a = advisor()
		if not ready(a) then return nil end
		if type(link) ~= "string" then return nil end
		local row = a._judgement(link)
		if type(row) ~= "table" then return nil end
		local verdict = row.verdict
		-- The comparator's own four-token vocabulary. UNKNOWN is "we looked and
		-- could not tell"; a row with no verdict at all is the same answer.
		if type(verdict) ~= "string" then return nil end
		if verdict == "UNKNOWN" then return nil end
		return {
			verdict = verdict,
			reason = row.reason,
			slot = row.slot,
			slotWord = row.slotWord,
			role = row.role,
			itemID = row.id,
			-- The judgement epoch: bump on any re-judge (equipment, level,
			-- weapon skill, settings). Two copies with different epochs are
			-- answers to two different characters, so a caller caching our
			-- answer can tell when it is stale.
			epoch = row.__epoch,
		}
	end)
end

-- ---- OnChanged -------------------------------------------------------------
-- Fires whenever arrows are re-judged. The listener list lives on the advisor
-- (it owns the event); this function is a registration surface only, so the
-- firing site stays one place. A listener is called in a pcall: one broken
-- consumer cannot stop the others or the scan.
function GearAPI.OnChanged(func)
	return safe(function()
		if type(func) ~= "function" then return false end
		local a = advisor()
		if type(a) ~= "table" then return false end
		local list = a._changeListeners
		if type(list) ~= "table" then
			list = {}
			a._changeListeners = list
		end
		for i = 1, #list do
			if list[i] == func then return true end
		end
		list[#list + 1] = func
		return true
	end)
end

-- ---- GetStatKeys -----------------------------------------------------------
-- The stat-word list the weight tables are defined over, in the comparator's
-- own order — what a settings surface (or another addon's display) lists as
-- the editable words. Copies: mutating the returned array cannot reach the
-- engine's key set.
function GearAPI.GetStatKeys()
	return safe(function()
		local V = rawget(_G, "Verdict")
		local keys = type(V) == "table" and V.WEIGHT_KEYS or nil
		if type(keys) ~= "table" then return nil end
		local out = {}
		for i = 1, #keys do out[i] = keys[i] end
		return out
	end)
end

return GearAPI

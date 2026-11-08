if MightiePackTouchstoneSkip then return end
-- Fold: asset paths point at where the module actually lives. Upstream
-- hardcodes Interface\AddOns\Touchstone\... which does not exist once the
-- files are vendored under MightiePack/Modules/Touchstone/ — the bag arrow
-- and the toast arrow then render as nothing and the upgrade never shows.
local _mpAddonName = ...
local MIGHTIEPACK_TOUCHSTONE_ASSETS = "Interface\\AddOns\\"
	.. tostring(_mpAddonName or "MightiePack")
	.. "\\Modules\\Touchstone\\ChestAdvisor\\"
-- ChestAdvisor.lua — t_3c1256ec: a per-slot upgrade advisor.
--
-- Scope today: the armour slots (head, shoulders, chest, back, wrists, hands,
-- waist, legs, feet), the stat-stick slots (neck, finger ×2, trinket ×2) and —
-- Tier B, t_73e20edb — the OFF-HAND slot (shield / off-hand weapon /
-- held-in-off-hand), which is judged under the spec-aware policy in
-- docs/whisperstone/shield-offhand-spec-policy.md. Weapons in general (the
-- two-hand / ranged family and the positionally undetermined INVTYPE_WEAPON)
-- are Tier C and still out of scope.
--
-- What ships:
--   * A "UPGRADE" marker on chest items, in any bag slot — the §5b arrow
--     (a texture on the marked bag button; the §5a orange bar is retired),
--     the PRIMARY player-visible outcome. A GameTooltip hover — an OnEnter
--     hook on the button — explains both the role it was decided for and
--     the reason.
--   * A tri-state comparator — UPGRADE / NOT_UPGRADE / UNKNOWN — carried
--     in Verdict.lua. The hard eligibility gate (C_PlayerInfo.CanUseItem)
--     precedes the empty-slot shortcut, an unknown word on either side is
--     UNKNOWN rather than a fabricated 0, and EQUAL is NOT an upgrade.
--   * A per-character focus-role picker (slash command) for hybrid classes,
--     persisted in SavedVariables. Pure classes have no picker — their
--     documented conservative order is the only order.
--   * A `upgrade diag` command that writes a SavedVariables + addon-global
--     record of the APIs the addon used and what they returned, so a
--     broken decision is diagnosable without /run (which is gated on this
--     client, see PROJECT-NOTES.md:678-681).
--
-- The scan runs on PLAYER_LOGIN, PLAYER_ENTERING_WORLD, BAG_UPDATE_DELAYED
-- and PLAYER_EQUIPMENT_CHANGED. Nothing is drawn until the first scan fires —
-- a character that has never logged in has no marker, not a stale one.
--
-- R8 (t_dcb796b0): this client's equip-change event is
-- PLAYER_EQUIPMENT_CHANGED. PLAYER_EQUIPMENT_UPDATE occurs zero times in
-- the pinned client (Gethe/wow-ui-source @forever, verified by full-tree
-- grep) and was rejected by the client's own log on 2026-09-29:
-- _classic_beta_/Logs/General.log:153
--   [E][Lua] ChestAdvisor_Frame:RegisterEvent():
--   ... Attempt to register unknown event "PLAYER_EQUIPMENT_UPDATE".
-- The name is confirmed by the client's own API docs —
-- Blizzard_APIDocumentationGenerated/PaperDollInfoDocumentation.lua:386
-- (Type="Event", SynchronousEvent=true, payload equipmentSlot/hasCurrent).
-- Do not rename back without re-checking the client source.
--
-- No runtime dependency on WoWAI, StatForge, Node, the bridge, or Hermes.
-- Verdict.lua is pure data + comparator; this file is the UI + scan glue.

ChestAdvisor = {
	roleFor = function() return nil end,
	getVerdicts = function() return {} end,
	scan = function() end,
}
-- One version string. Constants.lua (loaded first by Touchstone.toc) owns
-- SF.VERSION; this field reads it. A literal here drifted to "0.1.0" while
-- the TOC and the host said 0.8.x. Isolated loads with no host report nil
-- rather than a second hardcoded copy.
setmetatable(ChestAdvisor, {
	__index = function(_, key)
		if key ~= "version" then return nil end
		local host = rawget(_G, "StatForge")
		if type(host) == "table" and type(host.VERSION) == "string" and host.VERSION ~= "" then
			return host.VERSION
		end
		return nil
	end,
})

-- The comparator module. In-game it is loaded from this addon's own folder
-- via a package loader installed earlier on the path; in the test VMs the
-- harness loads Verdict.lua directly and registers it on _G before running
-- this file, and the stub does the same.
local function locateVerdict()
	if _G.Verdict and type(_G.Verdict) == "table" then return _G.Verdict end
	if package and type(package) == "table" then
		local ok, mod = pcall(function() return require("Verdict") end)
		if ok and type(mod) == "table" then return mod end
	end
	return nil
end
local Verdict = locateVerdict()

-- Card t_89440dfa: the third verdict's literal, read from the comparator so the
-- two files can never drift on the word. Falls back to the bare string if the
-- comparator did not resolve at load (the same posture the rest of this file
-- takes toward `Verdict`).
local TRADE_OFF_VERDICT = (Verdict and Verdict.TRADE_OFF) or "TRADE_OFF"

-- The per-character focus role for hybrid classes. Per-class by design:
-- a Warrior's choice is a Warrior's choice, not a Hunter's choice.
--
-- This assignment runs while the file loads, BEFORE the client restores
-- SavedVariablesPerCharacter (that restore lands on this global after the
-- addon's files finish and before ADDON_LOADED). The table below is only the
-- first-run default. It is replaced wholesale by the saved table, so it must
-- not be captured in an upvalue, and every key added after a player's first
-- save (tooltip, toast, markers, log) has to default at the read site. A
-- missing key is not "the default table was wiped".
ChestAdvisorDB = {
	role = {},
}

-- The current scan's verdicts, keyed by the item's hyperlink. The marker
-- frames read from this; the slash `diag` snapshot reads from here too.
ChestAdvisor.diag = nil

local MARKER_MAX = 64        -- cap on concurrent markers

-- ---- The trade-off chip (card t_89440dfa) ------------------------------------
--
-- The third outcome needs its OWN mark: not the green arrow (a confident yes),
-- not nothing (a confident no). It is drawn with NO new art — the card forbids a
-- toc/`## Assets:` change and `marker.tga` is the arrow — so it is a small solid
-- colour chip via SetColorTexture.
--
-- ⚠ DELIBERATELY DIFFERENT IN SHAPE, COLOUR AND CORNER from the arrow, so it can
-- never be mistaken for an upgrade at a glance:
--   * the arrow  — marker.tga, 18x18, TOPRIGHT (+1,+1), green
--   * this chip  — a plain amber square, 12x12, BOTTOMRIGHT (-1,+1)
-- and it is QUIETER than the arrow (smaller, no icon). A later reader must NOT
-- "unify" the two: same silhouette means "upgrade" to the eye.
local TRADEOFF_R, TRADEOFF_G, TRADEOFF_B, TRADEOFF_A = 1, 0.65, 0.15, 0.9
local TRADEOFF_SIZE = 12

-- ---- E3 (t_1f22bc67): the scan is slot-driven across the nine armour slots --
--
-- Provenance (the card's "do not copy these") — the values below are the
-- pinned client's own constants (Blizzard_FrameXMLBase/Constants.lua:
-- 135-156, branch @forever), cross-checked against two repo sources that
-- already agree (WoWAI.lua:1082-1087 EQUIP_SLOT; StatForge's SLOT_NAMES).
--
-- INVTYPE_* (the *item*'s equip location — what C_Item.GetItemInfoInstant
-- returns as the 4th positional value) maps one-to-one onto INVSLOT_*
-- (the *worn-slot* index passed to GetInventoryItemLink("player", N)).
--
-- Chest is the one asymmetry: both INVTYPE_CHEST and INVTYPE_ROBE are worn
-- in slot 5 (INVSLOT_CHEST). There is no INVSLOT_ROBE — the token exists
-- only on the *item* side. (WoWAI.lua:1035 already maps INVTYPE_ROBE →
-- "Chest"; a genuinely better robe unmarked is the exact false negative
-- this card removes. AC-E2.)
--
-- The *worn* side is keyed INVSLOT_*, the *candidate* side INVTYPE_*.
-- A candidate is in scope iff its equipLocation() is in the union of these
-- keys; its worn slot is the mapped value.
--
-- OUT OF SCOPE (explicit): every weapon token that is NOT an off-hand one,
-- shirt, tabard, and every INVTYPE_NON_EQUIP_* token. Tier A (t_1c8e911b)
-- pulled the five stat-stick slots IN: neck, finger (×2), trinket (×2).
-- Tier B (t_73e20edb) pulls the OFF-HAND slot IN: shield, off-hand weapon and
-- held-in-off-hand (Lena §2's OFF_HAND class).
--
-- Tier C (t_b058b5df) pulls the WEAPON family IN, judged on tooltip-read DPS
-- (Verdict.weaponNumbers / compareDPS): the main-hand one-handers (INVTYPE_WEAPON,
-- INVTYPE_WEAPONMAINHAND), the two-handers (INVTYPE_2HWEAPON) and the ranged
-- family (INVTYPE_RANGED / RANGEDRIGHT / THROWN). The off-hand weapon token
-- (INVTYPE_WEAPONOFFHAND) stays on Tier B's OFF_HAND path (slot 17) — Tier B
-- already owns that slot and its like-for-like guarantee. The two families
-- share ONE worn-slot table because they share one client numbering: 16 main
-- hand, 17 off hand, 18 ranged (Blizzard_FrameXMLBase/Constants.lua:151-153).
--
-- The off-hand token maps to worn slot 17 (INVSLOT_OFFHAND, the client's own
-- constant — Blizzard_FrameXMLBase/Constants.lua:152). Slot 16
-- (INVSLOT_MAINHAND) is not judged as an ARMOUR row; it is read to detect a
-- two-hand commitment (G0, Tier B §5) that structurally closes slot 17, and —
-- Tier C — to compare a candidate weapon against the worn MAIN HAND.
local EQUIP_SLOTS = {
	["INVTYPE_HEAD"]     = 1,
	["INVTYPE_NECK"]     = 2,
	["INVTYPE_SHOULDER"] = 3,
	["INVTYPE_CHEST"]    = 5,
	["INVTYPE_ROBE"]     = 5,   -- robe → chest slot (AC-E2)
	["INVTYPE_WAIST"]    = 6,
	["INVTYPE_LEGS"]     = 7,
	["INVTYPE_FEET"]     = 8,
	["INVTYPE_WRIST"]    = 9,
	["INVTYPE_HAND"]     = 10,
	["INVTYPE_FINGER"]   = 11,  -- pair slots — PAIR_SLOTS below
	["INVTYPE_TRINKET"]  = 13,  -- pair slots — PAIR_SLOTS below
	["INVTYPE_CLOAK"]    = 15,
	["INVTYPE_SHIELD"]       = 17,  -- Tier B: the OFF_HAND class (Lena §2)
	["INVTYPE_WEAPONOFFHAND"] = 17,
	["INVTYPE_HOLDABLE"]      = 17,
	-- Tier C: the WEAPON family (main hand 16, ranged 18). Routed to the DPS
	-- comparator by the `isWeaponRow` test in the walk below, NOT to the armour
	-- comparator. INVTYPE_WEAPON is positional (Lena §2): the client resolves it
	-- to the slot it is WORN in, so as a candidate it is a main-hand weapon.
	["INVTYPE_WEAPON"]         = 16,
	["INVTYPE_2HWEAPON"]       = 16,
	["INVTYPE_WEAPONMAINHAND"] = 16,
	["INVTYPE_RANGED"]         = 18,
	["INVTYPE_RANGEDRIGHT"]    = 18,
	["INVTYPE_THROWN"]         = 18,
}

-- Tier A (t_1c8e911b): the paired slot groups. Two rings and two trinkets
-- each occupy a PAIR of worn slots. The reference addon resolves them by
-- comparing the candidate against the WEAKEST pair member
-- (ForeverGear Score.lua `weakestOfSlots(slots, profileName, true)` — a
-- read-only local source; no weight numbers are imported — the practice the
-- stat-weights design doc recommends; the owner has not ruled on it).
--
-- Comparing against the single weakest pair member (or the EMPTY member)
-- satisfies the card's AC-B three cases exactly:
--   * a candidate beating only the weaker partner → UPGRADE
--     (the stronger member is untouched and cannot drag the row to
--     NOT_UPGRADE)
--   * a candidate beating neither partner         → NOT_UPGRADE
--     (the weaker is by definition <= the stronger, so it cannot beat
--     the row's opponent)
--   * a candidate beating both partners           → UPGRADE
-- An EMPTY member is a legitimate free upgrade (card AC-C), matching the
-- reference's `allowEmpty` (a nil-link entry returns immediately).
local PAIR_SLOTS = {
	["INVTYPE_FINGER"]  = { 11, 12 },
	["INVTYPE_TRINKET"] = { 13, 14 },
}

-- The slot word for each in-scope slot — used to generalise the
-- empty-slot reason (AC-E4) and to name the row's own slot in the diag
-- ledger. Keyed by the INVSLOT index (the shared worn side), so robe and
-- chest map to one word. The words are the player's verbatim list from the
-- card ("head, shoulders, chest, back, wrists, hands, waist, legs, feet"),
-- not invented phrasing.
local SLOT_WORD = {
	[1]  = "head",
	[2]  = "neck",
	[3]  = "shoulders",
	[5]  = "chest",
	[15] = "back",
	[9]  = "wrists",
	[10] = "hands",
	[6]  = "waist",
	[7]  = "legs",
	[8]  = "feet",
	[11] = "finger",
	[12] = "finger",    -- pair slots share one word (Tier A)
	[13] = "trinket",
	[14] = "trinket",   -- pair slots share one word (Tier A)
	[16] = "main hand", -- Tier C: the main-hand weapon slot
	[17] = "off hand",  -- Tier B (Lena §1: the sister project's own word for INVSLOT_OFFHAND)
	[18] = "ranged",    -- Tier C: the ranged weapon slot (INVSLOT_RANGED)
}

-- In scope? A candidate's equipLocation() is in scope iff it is a key of
-- the table. Returns the worn-slot index (INVSLOT_*) or nil.
local function wornSlotFor(loc)
	return EQUIP_SLOTS[loc]
end

-- The slot word for a worn-slot index (falling back to "slot").
local function slotWord(invSlot)
	return SLOT_WORD[invSlot] or "slot"
end
local SCAN_TIP_MAX = 30      -- tooltip lines we read per item

local frame = nil            -- the event frame (also hosts the slash/diag)
local markerPool = {}        -- array of markers, index 1..n
local markerNext = 0         -- next index to allocate (so two scans don't collide)
local activeMarkers = {}     -- link -> frame (for deactivation, not creation)
local lastLinkForMarker = nil

-- ---- B11 (card t_e9a07624): the item-data rescan ---------------------------
--
-- THE DEFECT. `GET_ITEM_INFO_RECEIVED` and `ITEM_DATA_LOAD_RESULT` were
-- registered ZERO times, so nothing re-ran when the client finished caching an
-- item's data. On a cold cache the first scan reads empty tooltips and judges
-- every item UNKNOWN; the verdicts then sit stale until the next BAG_UPDATE /
-- equip event. Two live consequences:
--   * a warm-up scan leaves UNKNOWN on items the client simply had not loaded;
--   * the TOAST baseline (toastSeenFirstScan) can be taken on that all-UNKNOWN
--     pass, so the very next scan sees the now-readable item flip to UPGRADE —
--     which the toast layer cannot tell apart from a genuinely NEW drop, and
--     fires a false "Upgrade found!" for an item that was in the bags at login.
--
-- THE FIX, matching the reference that ships on this client
-- (ForeverGear/Bags.lua:499,506,527 and Stats.lua:913-914 — the same pair of
-- events): register BOTH events and, when one arrives, rescan. The rescan is
-- DEBOUNCED — the client fires one event per item, so a login can deliver
-- dozens; a single C_Timer-delayed pass collapses the burst into one scan
-- (0.10s, the reference's own ITEM_DATA_LOAD_RESULT delay), and a re-entry
-- inside the window merely re-arms the one timer. The toast baseline is not
-- invalidated: the first scan already recorded every link, UNKNOWN included.
--
-- The baseline is the first scan's link set, including UNKNOWN rows (a cold
-- cache). It is NOT reopened here. Reopening on every item-data event made
-- the next scan treat a mailbox attachment, a loot, a quest reward, a vendor
-- buy, or a trade as "already in the bags at login": the verdict row still
-- said UPGRADE (the tooltip printed it) and the toast never fired.
local itemDataGen = 0
local function rescanForItemData()
	itemDataGen = itemDataGen + 1
	local myGen = itemDataGen
	-- Late-bound on purpose: the toast baseline lives in a file-local far
	-- below this block, so a direct reference from here would bind a GLOBAL
	-- (nil) — the upvalue-order trap this file's W1 note warns about. The
	-- toast section publishes the hook. It does not reopen the baseline.
	if type(ChestAdvisor._armToastBaseline) == "function" then
		ChestAdvisor._armToastBaseline()
	end
	local function pass()
		if myGen ~= itemDataGen then return end
		ChestAdvisor.scan()
	end
	if C_Timer and type(C_Timer.After) == "function" then
		C_Timer.After(0.10, pass)
	else
		pass()
	end
end
ChestAdvisor._rescanForItemData = rescanForItemData

-- Test + inspection access to the event surface B11 added (read-only).
ChestAdvisor.itemDataEvents = function()
	return { "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }
end

-- U5 (card t_c01331a2): the vendor surface's event names, and where they are
-- registered. The register call below lives INSIDE getFrame()'s singleton guard, so
-- it runs exactly once no matter how many callers reach getFrame — the same reason
-- the item-data pair is registered there rather than at file scope. The names are the
-- merchant frame's own documented literals (MerchantFrameDocumentation.lua).
ChestAdvisor.vendorEvents = function()
	return { "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED" }
end

local function getFrame()
	if not frame then
		if UIParent then
			frame = CreateFrame("Frame", "ChestAdvisor_Frame")
		else
			frame = CreateFrame("Frame")
		end
		-- U5 (card t_c01331a2): the merchant lifecycle. Registered on THIS scan frame
		-- — no second event frame, no second handler — exactly as the item-data pair
		-- is (B11). The OnEvent arm above routes MERCHANT_SHOW/UPDATE to the vendor
		-- refresh and MERCHANT_CLOSED to the clear, and returns before any equip/scan
		-- bookkeeping.
		frame:RegisterEvent("MERCHANT_SHOW")
		frame:RegisterEvent("MERCHANT_UPDATE")
		frame:RegisterEvent("MERCHANT_CLOSED")
		frame:SetScript("OnEvent", function(self, ev, ...)
			-- B11: the item-data pair. Handled FIRST and separately — these
			-- must NOT run the equip/scan bookkeeping below (there is no
			-- equip payload, and re-running the disagreement diff on a cache
			-- event would be wrong). The debounced rescan is the whole action.
			if ev == "GET_ITEM_INFO_RECEIVED" or ev == "ITEM_DATA_LOAD_RESULT" then
				rescanForItemData()
				return
			end
			-- U3/5 (card t_cf2ad83c) plus B17 (card t_6696b35a): combat has ended.
			-- A scan that arrived during the fight was flagged, not run; this
			-- is where it runs. Then release any toast a previous scan held.
			-- Late-bound through ChestAdvisor because the toast block is
			-- declared far below this closure (the same reason
			-- _armToastBaseline exists). The bag-update arm below is a
			-- different path and still the one that records an equip.
			if ev == "PLAYER_REGEN_ENABLED" then
				-- B17 (card t_6696b35a): a scan requested during combat set
				-- _scanDeferred and returned. Run it now. Clearing the flag
				-- is the scan's job (it re-sets the flag if combat is somehow
				-- still on), so a deferred scan cannot be dropped on the floor.
				-- Scan before the toast release: the release shows what a
				-- previous scan held, and this scan is the one combat postponed.
				if ChestAdvisor._scanDeferred and type(ChestAdvisor.scan) == "function" then
					ChestAdvisor.scan()
				end
				if type(ChestAdvisor._releaseHeldToasts) == "function" then
					ChestAdvisor._releaseHeldToasts()
				end
				return
			end
			-- U5 (card t_c01331a2): the vendor surface's own lifecycle events. Both
			-- are documented literals of the merchant frame
			-- (MerchantFrameDocumentation.lua: MERCHANT_SHOW / MERCHANT_UPDATE /
			-- MERCHANT_CLOSED) and are registered by getFrame() below. Handled
			-- separately, like the pairs above: the refresh is presentation and must
			-- not run the bag scan.
			if ev == "MERCHANT_SHOW" or ev == "MERCHANT_UPDATE" then
				if type(ChestAdvisor._onMerchantEvent) == "function" then
					ChestAdvisor._onMerchantEvent()
				end
				return
			end
			if ev == "MERCHANT_CLOSED" then
				if type(ChestAdvisor._onMerchantClosed) == "function" then
					ChestAdvisor._onMerchantClosed()
				end
				return
			end
			if ev == "PLAYER_LOGIN"
				or ev == "PLAYER_ENTERING_WORLD"
				or ev == "BAG_UPDATE_DELAYED"
				or ev == "PLAYER_EQUIPMENT_CHANGED"
			then
				-- Some bag frames are created after login, so re-discover
				-- any newly available frames here (the guards make every
				-- re-entry idempotent — no hook is stacked).
				if type(ChestAdvisor._installRefreshHooks) == "function" then
					ChestAdvisor._installRefreshHooks()
				end
				-- U4/U5 (card t_c01331a2): the character pane and the merchant frame are
				-- created lazily by the client, so a hook that missed them at load is
				-- re-attempted here. Both installers are guarded (one hook per frame),
				-- exactly like _installRefreshHooks above.
				if type(ChestAdvisor._installPaperDollHooks) == "function" then
					ChestAdvisor._installPaperDollHooks()
				end
				if type(ChestAdvisor._installMerchantHooks) == "function" then
					ChestAdvisor._installMerchantHooks()
				end
				-- #5 Disagreement log (t_bc9c69d3): this event is the ONE
				-- moment the player tells us he disagreed with the advisor —
				-- he is putting on an item the scan did not call UPGRADE.
				-- Recorded HERE, on the event path that already exists, and
				-- BEFORE the rescan below: the scan rebuilds
				-- ChestAdvisor.__verdicts, and an item that has just been
				-- equipped is no longer in the bag, so the very row being
				-- looked up would be gone. Record first, scan second. The
				-- payload's first value is the equipment slot
				-- (PaperDollInfoDocumentation.lua:386 — payload
				-- equipmentSlot/hasCurrent). No extra frame, no extra
				-- handler, no extra scan.
				if ev == "PLAYER_EQUIPMENT_CHANGED"
					and type(ChestAdvisor._logDisagreement) == "function"
				then
					local changedSlot = ...
					ChestAdvisor._logDisagreement(changedSlot)
				end
				-- Defer the scan one tick past the fire, so the client has
				-- finished its own bookkeeping for the event by the time we
				-- read the world.
				ChestAdvisor.scan()
			end
		end)
	end
	return frame
end

-- ---- Tooltip reading (house pattern, WoWAI.lua:1666) -------------------------
local scanTip
local function getScanTip()
	if not scanTip and GameTooltip and UIParent then
		scanTip = CreateFrame("GameTooltip", "ChestAdvisorTip", UIParent, "GameTooltipTemplate")
	end
	return scanTip
end
local function TooltipLines(payload)
	local tip = getScanTip()
	if not tip then return {} end
	-- Markerless read: owner stays UIParent (it has no marker to anchor
	-- to). This is NOT the hover path — that lives in anchorMarker's
	-- installOnEnter, where §5b pins the hover tip's owner to the BAG
	-- BUTTON (SetOwner(button, "ANCHOR_RIGHT"), shape 2).
	tip:SetOwner(UIParent, "ANCHOR_NONE")
	tip:ClearLines()
	local lines = {}
	if pcall(tip.SetHyperlink, tip, payload) then
		for i = 1, math.min(tip:NumLines() or 0, SCAN_TIP_MAX) do
			local left  = _G["ChestAdvisorTipTextLeft"  .. i]
			local right = _G["ChestAdvisorTipTextRight" .. i]
			local l = tostring((left  and left:GetText())  or "")
			local r = tostring((right and right:IsShown() and right:GetText()) or "")
			if r ~= "" then l = l .. "  " .. r end
			l = l:gsub("^%s+", ""):gsub("%s+$", "")
			if l ~= "" then table.insert(lines, l) end
		end
	end
	tip:Hide()
	return lines
end

-- READ THE ITEM, NOT THE TOOLTIP (card t_119d120c). EVERY caller that needs an
-- item's lines comes here — weapons, armour, bags, quest rewards, the pair-pick
-- helpers and the toast. This function was born (Tier C, t_b058b5df) as
-- `weaponLines`, weapons-only; the card promotes it to the ONE reader for every
-- JUDGE path, renamed for what it actually does.
--
-- Deliberately NOT a caller: probe P1. P1's job is to capture what the VISIBLE
-- tooltip shows so a human can diff it against a screenshot (the C3 PASS rule),
-- and that surface IS the rendered one — see the note at probeP1. The judge and
-- the probe want opposite things, which is why they no longer share a reader.
--
-- WHY (the owner's live report): a third-party addon appends its own prose to
-- the RENDERED GameTooltip. RXPGuides\QuestLog.lua:385 does
--     tooltip:AddLine(L"Item used in guide:\n" .. entry.name)
-- so an item annotated by it read
--     Touchstone: UNKNOWN — cannot classify: Item used in guide: 39-40 Badlands
-- because the armour/bag scan read the rendered tooltip and the annotation
-- entered the parse. The cosmetic rule (t_b7a9e7a5) cannot cover it: the line
-- carries a number ("39-40" is a zone level range), so lineCarriesNumber is
-- true and it suppresses — correctly, by that rule, and uselessly in practice.
--
-- The fix is not "recognise foreign lines" (a prefix list is the quick fix the
-- owner rejected: it leaves the NEXT addon's lines silencing his gear). It is
-- "read from a source where foreign lines do not exist." The owner's own live
-- probe (2026-10-07) dumped BOTH readers for the annotated item:
--
--   | | structured C_TooltipInfo.GetHyperlink | rendered GameTooltip |
--   |---|---|---|
--   | lines | 9 | 14 |
--   | "Item used in guide: 39-40 Badlands" | ABSENT | present |
--   | "Press F6 to submit an issue for this Item" | ABSENT | present |
--   | our own already-added "Touchstone: ..." line | ABSENT | present |
--   | item's own data (name, type, Armor, +Str, +Sta, "Enchanted:",
--     "Requires Level", "<Made by ...>") | present | present |
--
-- ⇒ the structured read carries the item's own data and NOTHING another addon
-- appended. Blizzard's GameTooltip is a COMPOSITION surface: every addon's
-- AddLine lands in it, and its lines are therefore not evidence about the item.
-- C_TooltipInfo.GetHyperlink is the client's read of the ITEM.
--
-- The two readers' lines are otherwise the SAME flat list of joined strings;
-- every parser below reads that list POSITIONALLY (bag walk, pair pick, weapon
-- DPS, stat table), so one reader serves them all with no second parser (the
-- module's own warning: two parsers diverge, and a divergent parser is a silent
-- wrong answer).
--
-- The client's structured reader is C_TooltipInfo.GetHyperlink(itemLink, nil,
-- nil, true) — the reference's own call (ForeverGear Weapon.lua:125), returning
-- `data.lines` with `leftText`/`rightText` per row. We prefer it when it is
-- present and well-formed, and fall back to the rendered GameTooltip reader
-- (TooltipLines) when the API is absent, returns nothing, or errors — so a
-- client without the API behaves as it does today and behaviour is never worse
-- than the present. pcall-wrapped and secret-tolerant: this is an
-- untested-by-us client read, treated like CanUseItem.
--
-- Tier C (t_b058b5df) round 2 (Vera D2): a structured tooltip line's
-- leftText / rightText can be a SECRET value — the client marks the fields of
-- a structured read while the player is on an addon-restricted map. The value
-- is a STRING, so `type(v) == "string"` does NOT screen it, and both tostring()
-- and any downstream string:* call RAISE on a secret (an arithmetic or
-- comparison on a secret raises immediately — the card's own note). Mirror the
-- reference's guard discipline here: predicate under pcall, then coerce under
-- pcall.
--
-- Returns (ok, text):
--   ok == true,  text == nil   — the field is ABSENT (nil). Normal, not a hazard.
--   ok == true,  text == "...".— the field is a readable string.
--   ok == false, text == nil   — the field is WITHHELD: a secret value, or a
--                                value whose coercion raised. The caller skips
--                                the whole line (AC-C: missing reads as missing).
-- Absent and withheld are deliberately distinct: conflating them would drop
-- every legitimate line that carries no right-hand column.
local function coerceField(v)
	if v == nil then return true, nil end
	if type(v) == "string" then
		-- A secret string is still a string, so identity/type cannot screen
		-- it — the client's predicate is the only tell. Consult it first,
		-- under pcall because the predicate itself can raise.
		if type(issecretvalue) == "function" then
			local ok, sec = pcall(issecretvalue, v)
			if ok and sec then return false, nil end
		end
		return true, v
	end
	local ok, s = pcall(tostring, v)
	if not ok then return false, nil end
	return true, s
end

local function itemLines(link)
	if C_TooltipInfo and type(C_TooltipInfo.GetHyperlink) == "function" then
		-- pcall BOTH the call and the shape test: a structured read that
		-- RAISES must degrade to the rendered reader (AC-F "throwing"), and
		-- a hostile return whose `lines` is not a table must too. `data`
		-- itself is nil on the absent-item / currency case (the API is
		-- MayReturnNothing), which is also the fallback.
		local ok, data = pcall(C_TooltipInfo.GetHyperlink, link, nil, nil, true)
		if ok and type(data) == "table" and type(data.lines) == "table" then
			local out = {}
			for i = 1, math.min(#data.lines, SCAN_TIP_MAX) do
				local ln = data.lines[i]
				local l
				if type(ln) == "table" then
					local lok, lt = coerceField(ln.leftText)
					local rok, rt = coerceField(ln.rightText)
					if lok and rok then
						-- Join shape is UNCHANGED from the pre-fix reader:
						-- left, then two spaces + right when a right column
						-- exists. A line with only a left column stays a
						-- left-only line, exactly as before.
						l = lt or ""
						if rt ~= nil and rt ~= "" then l = l .. "  " .. rt end
					end
					-- else: a WITHHELD field makes the whole LINE withheld.
					-- It is skipped rather than half-read, because a line
					-- with a missing operand could parse as a different
					-- number than the client printed — the AC-C "missing
					-- reads as missing" answer, not an error.
				elseif type(ln) == "string" then
					local sok, s = coerceField(ln)
					if sok then l = s end
				end
				if l then
					l = l:gsub("^%s+", ""):gsub("%s+$", "")
					if l ~= "" then table.insert(out, l) end
				end
			end
			return out
		end
	end
	return TooltipLines(link)
end
-- Append one explanation line to the shared scan tooltip. The real client's
-- GameTooltip uses AddLine; the stub doesn't have it, so SetText is the
-- fallback there. pcall keeps the addon working if either client is missing
-- the API entirely rather than erroring on hover.
local function explainLine(tip, text)
	if not tip then return end
	local ok = pcall(tip.AddLine, tip, text)
	if not ok then pcall(tip.SetText, tip, text) end
end

-- ---- Item classification (via the client, not via invented fields) ----------
local function itemIDOf(link)
	if type(link) ~= "string" then return nil end
	return tonumber(link:match("item:(%d+)"))
end

local function equipLocation(id)
	if C_Item and C_Item.GetItemInfoInstant and type(id) == "number" then
		-- GetItemInfoInstant returns (id, itemText, subtext, equipLoc, duration, classID, subclassID).
		-- pcall prepends a success flag, so three values precede equipLoc.
		local ok, _, _, _, loc = pcall(C_Item.GetItemInfoInstant, id)
		if ok then return loc end
	end
	return nil
end

local function canUse(id)
	if C_PlayerInfo and C_PlayerInfo.CanUseItem and type(id) == "number" then
		local ok, v = pcall(C_PlayerInfo.CanUseItem, id)
		if ok then return v end
	end
	return nil
end

-- The class token, once per class.
local cachedClassToken
local function classToken()
	if not cachedClassToken then
		if UnitClass then
			local _, tok = UnitClass("player")
			if type(tok) == "string" then cachedClassToken = tok end
		end
	end
	return cachedClassToken
end

-- The class's LOCALIZED DISPLAY name (UnitClass's first return), once per class.
-- Card t_548f0341 (Defect 1): a character with no specialization yet gets its
-- own CLASS NAME back as the "spec name" (verbatim live probe: name=Paladin
-- ROLE=DAMAGER). Verdict.substantiated compares the two to tell a real spec from
-- that class-as-spec read, so this read exists to be that comparison's other
-- half — never to label anything on screen.
local cachedClassDisplay
local function classDisplayName()
	if not cachedClassDisplay then
		if UnitClass then
			local n = UnitClass("player")
			if type(n) == "string" then cachedClassDisplay = n end
		end
	end
	return cachedClassDisplay
end

-- The player's recorded role for this class's hybrid, if any.
local function playerRole(token)
	if type(token) ~= "string" then return nil end
	local db = ChestAdvisorDB and ChestAdvisorDB.role or nil
	if not db then return nil end
	local r = db[token]
	if type(r) ~= "string" and type(r) == "table" and type(r.role) == "string" then
		r = r.role
	end
	return r
end

-- ---- Tier B (t_73e20edb): the client spec read -------------------------------
--
-- A shield is a spec commitment, so the off-hand gate needs the character's
-- spec. The readable pair on this client is C_SpecializationInfo
-- (GetSpecialization -> index, GetSpecializationInfo(index) -> ..., role, ...),
-- consumed by Blizzard's own camelot-only character sheet
-- (Camelot/PaperDollFrame.lua:2400-2404). `role` is the 5th return and its
-- values are the three literals TANK / HEALER / DAMAGER (Lena §3).
--
-- This read is UNTESTED BY US (Lena §11.2) — observed present and consumed by
-- the client's own UI, never observed returning TANK for a protection warrior
-- on a live character. So it is treated exactly like CanUseItem: pcall, and
-- anything other than a clean three-way role string is nil, which the gate
-- reads as G3 ("no specialization resolved") — silence, never a default bucket.
--
-- Nothing here is cached across a scan: a spec change (or a talent respec) must
-- be picked up by the next scan, and the read is two cheap client calls.
local function readSpecIdentity()
	if not (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
		and C_SpecializationInfo.GetSpecializationInfo) then
		return nil
	end
	local ok, idx = pcall(C_SpecializationInfo.GetSpecialization)
	if not ok or type(idx) ~= "number" or idx == 0 then return nil end
	local ok2, _, name, _, _, role = pcall(C_SpecializationInfo.GetSpecializationInfo, idx)
	if not ok2 then return nil end
	if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then return nil end
	return { role = role, name = (type(name) == "string" and name or nil) }
end

-- Card t_548f0341 (Defect 1): the identity the off-hand gate is told about. The
-- role/name come from the (untrusted) spec read; the CLASS and the class's
-- localized DISPLAY name always come from UnitClass and survive a failed spec
-- read. classDisplay is what Verdict.substantiated compares the spec name
-- against, so a class-as-spec read ("name=Paladin" on a paladin) is recognisable
-- as unsubstantiated and does not resolve a spec-specific policy.
local function readOffHandSpec()
	local si = readSpecIdentity()
	return { class = classToken(), role = si and si.role or nil,
	         name = si and si.name or nil,
	         classDisplay = classDisplayName() }
end

-- ---- Verdict row assembly ---------------------------------------------------
local function isHybridWithoutRole(token)
	local t = Verdict and Verdict.ORDERS and Verdict.ORDERS[token]
	if type(t) ~= "table" then return false end
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n > 1 and playerRole(token) == nil
end

-- Card t_0b4ddfa9 — resolve the role ONCE, for every caller.
--
-- Priority is manual-first: an explicit /up role always wins. Only when the
-- player has recorded nothing does the client spec read act as the fallback
-- (Option A — it needs no player input).
--
-- This is the SINGLE resolution point so BOTH marker surfaces inherit ONE
-- order: the bag walk (reads spec.order at scan()) and the quest walk
-- (refreshQuestMarkers()) each carried their OWN `spec.order == nil` gate and
-- their OWN "no role" return, so resolving in either walker would leave the
-- other dark — and quest rewards are the surface the owner actually picks gear
-- on while levelling.
--
-- The client speaks TANK/HEALER/DAMAGER (uppercase literal, readSpecIdentity);
-- the order tables speak melee|spell. Verdict.clientRoleWord maps one to the
-- other and returns nil when there is no mapping — a pure class, an unmapped
-- hybrid, or a malformed read — in which case the order stays nil and the
-- caller's existing UNKNOWN branch is unchanged. A read that cannot be mapped
-- is SILENCE, never a guessed order.
--
-- Returns: word (the table's own role word or nil), source ("recorded" |
-- "client" | nil). The source lets the diag say where the role came from.
local function resolvedRole(token)
	local recorded = playerRole(token)
	if recorded ~= nil then return recorded, "recorded" end
	if type(token) ~= "string" then return nil, nil end
	local si = readSpecIdentity()
	local alias = (si and Verdict and Verdict.clientRoleWord)
		and Verdict.clientRoleWord(token, si.role) or nil
	if alias then return alias, "client" end
	return nil, nil
end

local function buildSpec()
	local token = classToken()
	local role  = resolvedRole(token)
	local order = (Verdict and Verdict.classRoleOrder) and Verdict.classRoleOrder(token, role) or nil
	-- A hybrid without a resolved role is not "acting as its class token":
	-- the display label must say the role is missing, not invent one.
	local label = role
	if label == nil and token and not isHybridWithoutRole(token) then
		label = token
	end
	local level = nil
	if type(UnitLevel) == "function" then
		local ok, lv = pcall(UnitLevel, "player")
		if ok and type(lv) == "number" then level = lv end
	end
	return { order = order, role = label, class = token, level = level }
end

-- ---- Tooltip surface (card t_ed71a583) ---------------------------------------
--
-- WHY THIS EXISTS. The addon computes a verdict and a reason for every in-scope
-- item, but before this card the reason reached the player only through `/up
-- diag` or through the addon's OWN scan tip — and the scan tip is suppressed
-- whenever the client's GameTooltip owns the hovered button, which is every bag
-- hover (anchorMarker's installOnEnter). So the player got an arrow with no
-- explanation, or silence. This block puts the verdict AND the read numbers on
-- the item tooltip the player is already looking at.
--
-- THE API PAIR, in the order the reference addon ships it on this client
-- (ForeverGear/Tooltip.lua:596-605 — the proof this pair exists here, rather
-- than a guess): the modern structured hook first, the OnTooltipSetItem
-- HookScript as the fallback for "unexpected API changes during beta". Same
-- order, same two calls.
--
-- APPEND ONLY (the card's explicit constraint, from ForeverGear 1.3.4's own
-- release note: "Removed forced tooltip Show() calls ... no longer forces a
-- tooltip refresh that could remove or overwrite data added by other addons").
-- Nothing below calls Show(), SetOwner(), ClearLines() or SetHyperlink() on the
-- client's tooltip: a second tooltip addon may own the frame, and forcing it
-- would break that addon. Our lines are AddLine'd onto whatever is there.
--
-- NO WEIGHT, NO ESTIMATE. Every number printed comes from the client's own
-- tooltip strings, parsed by Verdict's own parser and subtracted from the other
-- side's own number (Verdict.statTable / Verdict.statDeltas / Verdict.deltaText,
-- additive helpers in Verdict.lua — no second parser lives here). The reason
-- text is the row's own stored reason, inherited rather than re-derived.

-- Fold (MightiePack, t_c2e67619): the addon's own name is not
-- written into the player's tooltip. The verdict word leads the
-- line. Every rendered surface reads this one constant, so they all
-- lose the name together. The duplicate guard below needs a marker
-- of its own now — see ca.tooltip-duplicate-guard.
local TOOLTIP_PREFIX = ""
local TOOLTIP_GREEN  = "|cff00ff00"
local TOOLTIP_GREY   = "|cff9d9d9d"
-- Card t_89440dfa: the trade-off line's own colour — amber, matching the chip
-- the bag button draws (TRADEOFF_R/G/B above), so the tooltip's answer and the
-- mark's colour agree. NOT green: the arrow's green means "upgrade".
local TOOLTIP_AMBER  = "|cffffa616"
local TOOLTIP_RESET  = "|r"
local TOOLTIP_DELTA_MAX = 4

-- ---- U2/b + U2/d (card t_cf2ad83c): the tooltip's words and detail -----------
--
-- GROUPED INTO ONE TABLE ON PURPOSE. Lua 5.1 caps a chunk at 200 top-level locals
-- and this module sits right under it, so a new top-level local is a scarce
-- resource; a dozen of them is not available. Everything the tooltip's rendering
-- needs lives here.
--
-- PLAYER WORDS (U2/b). The internal verdict tokens are NOT player words: the
-- tooltip rendered "NOT_UPGRADE — …" and "UNKNOWN — …" verbatim, and the hover
-- rendered "Touchstone: NOT_UPGRADE (this chest)". The tokens THEMSELVES do not
-- change — they are the comparator's contract (Verdict.evaluate's return, the
-- row's own `verdict` field, the marker's switch) and every consumer keeps
-- reading them. Only the RENDERED word changes, and it changes in ONE place so
-- the item tooltip and the bag/quest hover can never drift apart.
--
-- The vocabulary is closed: the comparator emits exactly four tokens — UPGRADE,
-- NOT_UPGRADE, UNKNOWN and TRADE_OFF (= Verdict.TRADE_OFF). Each is mapped;
-- anything else (a future fifth token, a malformed row) falls through to the
-- token itself rather than being mislabelled as a friendly word it is not.
--
-- THE DETAIL SETTING (U2/d):
--   Full      — headline + the muted detail line (the read arithmetic).
--   Compact   — the headline always; the detail only while Shift is held. (The
--               headline is NEVER gated on Shift: a Compact mode that hides the
--               answer itself would be a different, worse feature.)
--   Upgrades  — no line at all for a not-upgrade or a can't-judge row. A
--               trade-off and a verified upgrade keep their line: the card's own
--               parenthetical names exactly two suppressed classes.
-- Default FULL, so nothing is lost by accident, and a missing key never reads as
-- Compact.
local TOOLTIP_UI = {
	words = {
		UPGRADE     = "Upgrade",
		NOT_UPGRADE = "Not an upgrade",
		UNKNOWN     = "Can't judge",
	},
	detailDefault = "full",
	details = { full = true, compact = true, upgrades = true },
}
TOOLTIP_UI.words[TRADE_OFF_VERDICT] = "Trade-off"

function TOOLTIP_UI.word(v)
	if type(v) ~= "string" then return "Can't judge" end
	return TOOLTIP_UI.words[v] or v
end

function TOOLTIP_UI.detail()
	local t = ChestAdvisorDB and ChestAdvisorDB.tooltip
	local d = type(t) == "table" and t.detail or nil
	if type(d) == "string" then d = d:lower() end
	if TOOLTIP_UI.details[d] then return d end
	return TOOLTIP_UI.detailDefault
end

-- Shift, probed — absent on a client that does not expose it, and a missing probe
-- reads as "not held" (the conservative answer: it only ever ADDS the detail line
-- back, never removes the headline).
function TOOLTIP_UI.shiftHeld()
	return type(IsShiftKeyDown) == "function" and IsShiftKeyDown() == true
end

-- Does this row deserve a line under the "Upgrades" setting? Only the two
-- non-answers are suppressed (the card's "no line on not-upgrades / can't-judge").
function TOOLTIP_UI.worthALine(row)
	if type(row) ~= "table" then return false end
	return row.verdict == "UPGRADE" or row.verdict == TRADE_OFF_VERDICT
end

-- The tooltip-line toggle's persisted setting. It rides the EXISTING
-- per-character store (AC-F: no new store, exactly like the toast). Default ON,
-- and only an explicit `false` disables — the same missing-key semantics the
-- toast documents.
function TOOLTIP_UI.enabled()
	local t = ChestAdvisorDB and ChestAdvisorDB.tooltip
	if type(t) ~= "table" then return true end
	return t.enabled ~= false
end

-- Quest-reward rows, keyed by link. The bag rows live on ChestAdvisor.__verdicts
-- (the scan's own record); the quest surface stores its rows per BUTTON
-- (button.__chestAdvisorQuestData) because a reward button is reused across
-- quests. The tooltip surface is keyed by LINK, so the quest walk mirrors the
-- rows it anchors here and clearQuestMarkers drops them again when the panel
-- closes — a closed reward panel must not keep a line alive on some unrelated
-- hover later.
local questTooltipRows = {}
-- Drop every reward row when the reward panel closes (called from
-- clearQuestMarkers, which runs both at the top of each refresh and on close).
local function clearQuestTooltipRows()
	for link in pairs(questTooltipRows) do questTooltipRows[link] = nil end
end

-- The client's own displayed-item read, in the order the reference uses
-- (ForeverGear/Tooltip.lua:55-75). A STRUCTURED hyperlink is preferred when the
-- client hands one over; otherwise TooltipUtil.GetDisplayedItem (the documented
-- "which item is this tooltip showing" API); otherwise GameTooltip:GetItem.
-- Every step is pcall'd and secret-checked: on a restricted map the client marks
-- these values secret, and any comparison or concatenation on a secret raises.
local function safeIsSecret(v)
	if type(issecretvalue) ~= "function" then return false end
	local ok, r = pcall(issecretvalue, v)
	return ok and r == true
end

local function displayedLinkOf(tip, data)
	if type(data) == "table" and type(data.hyperlink) == "string"
		and not safeIsSecret(data.hyperlink) then
		return data.hyperlink
	end
	if type(TooltipUtil) == "table" and type(TooltipUtil.GetDisplayedItem) == "function" then
		local ok, idOrNil, link = pcall(TooltipUtil.GetDisplayedItem, tip)
		if ok and type(link) == "string" and link ~= "" and not safeIsSecret(link) then
			return link
		end
		-- A client that returns the link in the first position instead.
		if ok and type(idOrNil) == "string" and idOrNil ~= "" and not safeIsSecret(idOrNil) then
			return idOrNil
		end
	end
	if type(tip) == "table" and type(tip.GetItem) == "function" then
		local ok, idOrNil, link = pcall(tip.GetItem, tip)
		if not ok then return nil end
		if type(link) == "string" and link ~= "" and not safeIsSecret(link) then return link end
		if type(idOrNil) == "string" and idOrNil ~= "" and not safeIsSecret(idOrNil) then
			return idOrNil
		end
	end
	return nil
end

-- The item's name for the "vs <equipped>" clause (`name`, first return) and —
-- card t_8d653c12 — the item's VENDOR SELL PRICE (`sellPrice`, second return).
-- The client's own answer first, the hyperlink's bracket text as the fallback,
-- and a plain-language last resort — never an invented name.
--
-- THE SINGLE C_Item.GetItemInfo READ for the name/price pair. The card requires
-- the vendor coin to reuse THIS read rather than open its own: a second call
-- site is a second place for the two answers to disagree, and this pair of
-- returns is the coin's entire input. Callers that want only the name (the
-- "vs <equipped>" clause, :675) take the first return, exactly as before, so
-- extending the read costs them nothing.
--
-- The client's contract, verbatim:
--     C_Item.GetItemInfo(link) -> name, link, quality, iLevel, reqLevel,
--         class, subclass, maxStack, equipSlot, texture, sellPrice
-- pcall prepends its success flag, so `sellPrice` — the 11th return — is the
-- 12th value in the list below. A `nil` price is the client saying "not cached
-- yet": the coin reads that as "this row cannot earn the coin", NEVER as zero.
local function itemNameOf(link)
	if type(link) ~= "string" then return "your equipped item", nil end
	local name, sellPrice = nil, nil
	if C_Item and type(C_Item.GetItemInfo) == "function" then
		local ok, n, _lnk, _qual, _ilvl, _req, _cls, _sub, _stack, _equip, _tex, price =
			pcall(C_Item.GetItemInfo, link)
		if ok then
			if type(n) == "string" and n ~= "" then name = n end
			if type(price) == "number" then sellPrice = price end
		end
	end
	if name == nil then
		local bracket = link:match("%[(.-)%]")
		if bracket and bracket ~= "" then name = bracket end
	end
	if name == nil then name = "your equipped item" end
	return name, sellPrice
end

-- ---- Defect 2 (card t_548f0341): the client's own stat read -----------------
--
-- C_Item.GetItemStats(itemLink) returns the item's stats as a key -> value table
-- on this client. It is the IMPURE EDGE: Verdict.lua is a pure module and must
-- never call a client API (the harness drives every branch with an injected
-- table), so the read happens HERE and only the resulting word -> number table
-- crosses into the comparator.
--
-- ⚠ It is NOT a superset of the tooltip — the owner's worn shield reads Block 9
-- on the tooltip and NOTHING for Block from this API. So this read is used only
-- to EXPLAIN a line the text parser could not place (Verdict.parseSide); it never
-- replaces the text read.
--
-- The client documents this call as MayReturnNothing = true: for an item it
-- cannot read it returns NOTHING (nil), which is not an error. On nil, on an
-- absent API, or on a pcall failure this returns nil and every caller's
-- behaviour is byte-identical to the pre-card path — the fail-closed answer.
-- A secret/withheld value is the same: silence, never a guess at the number.
--
-- `idOrLink` is the item id (or the link; the client accepts both). Returns:
--   words — stat word -> number, verified keys only, or nil
local function apiStatsOf(idOrLink)
	if idOrLink == nil then return nil end
	if not (C_Item and type(C_Item.GetItemStats) == "function") then return nil end
	local ok, raw = pcall(C_Item.GetItemStats, idOrLink)
	if not ok then return nil end
	if type(raw) ~= "table" then return nil end
	if type(issecretvalue) == "function" then
		local sok, sec = pcall(issecretvalue, raw)
		if sok and sec then return nil end
	end
	if not (Verdict and type(Verdict.apiStats) == "function") then return nil end
	local words = Verdict.apiStats(raw)
	return words
end

-- Both sides' API words, ready to hand to Verdict.evaluate's fourth argument.
-- nil when the API could not read a side, which parseSide reads as "explain
-- nothing" — the unchanged suppression behaviour.
local function apiBySideOf(candIdOrLink, wornIdOrLink)
	local cand = apiStatsOf(candIdOrLink)
	local worn = apiStatsOf(wornIdOrLink)
	if cand == nil and worn == nil then return nil end
	return { candidate = cand, worn = worn }
end

-- Was this row's UNKNOWN produced by the ELIGIBILITY gate — the client refusing
-- to confirm the character can use the item? AC-D wants that case to say so in
-- words ("can't judge — eligibility unconfirmed") rather than go silent, and
-- this predicate must not claim it for the other UNKNOWN causes (an unreadable
-- tooltip, an unclassifiable stat word, an unresolved role, a structural
-- off-hand/weapon decline).
--
-- The tell is the row's own reason string: for the armour and off-hand rows the
-- comparator emits the "eligibility unconfirmed (fail-closed): ..." family
-- (Verdict.lua gate 3), and the weapon path emits its three named strings. Both
-- emitters are ours, and both strings are stable constants in our files — no
-- client string is matched here.
local TOOLTIP_ELIGIBILITY_REASONS = {
	["this character cannot use this weapon"] = true,
	["the client returned the secret-value sentinel"] = true,
	["the client could not classify this weapon"] = true,
}
local function eligibilitySuppressed(row)
	if row == nil or row.verdict ~= "UNKNOWN" then return false end
	local r = row.reason
	if type(r) ~= "string" then return false end
	if r:find("eligibility unconfirmed", 1, true) then return true end
	return TOOLTIP_ELIGIBILITY_REASONS[r] == true
end

-- The explanation for an UPGRADE row: the arithmetic the card asks for, e.g.
--     better on Strength (+2 Str, -1 Sta vs Barkeeper's Cloak)
-- The stat word is read out of the row's OWN reason (evaluate's two win shapes:
-- "upgrade: better on <Word>" and the armour tiebreak "upgrade: more <Word> (c
-- vs e)"), so the tooltip and the verdict cannot disagree about WHY. The numbers
-- are the two sides' parsed stat tables subtracted — read values, never weights.
local function describeUpgradeParts(row, order)
	local reason = type(row.reason) == "string" and row.reason or "upgrade"
	-- The comparator's own reason carries an "upgrade: " lead-in that reads as a
	-- stutter once the headline already says "Upgrade — ". Strip it for DISPLAY
	-- only; the row's stored `reason` is untouched (the Upgrades tab, the
	-- disagreement log and the diag all read the stored string, not this).
	local shown = reason:gsub("^%s*upgrade:%s*", "")
	-- Nothing worn on the other side (an empty slot, or the empty member of a
	-- finger/trinket pair): the row's own reason already says so, and there is
	-- no second table to subtract. Do not print a one-sided "delta".
	if type(row.chestWornLines) ~= "table" or #row.chestWornLines == 0 then
		return shown, nil
	end
	-- The comparator module is the only writer of stat tables in this addon; if
	-- it did not resolve at load time (locateVerdict() nil) there is no delta to
	-- read, and the row's own reason is what the player gets.
	if not (Verdict and type(Verdict.statTable) == "function"
		and type(Verdict.statDeltas) == "function"
		and type(Verdict.deltaText) == "function") then
		return shown, nil
	end
	local word = reason:match("better on (%a+)") or reason:match("more (%a+) %(")
	-- Card t_548f0341: the tooltip's arithmetic reads the SAME API-resolved
	-- tables the verdict was decided on, so a reconciled line cannot print one
	-- number while the verdict rested on another.
	local api = apiBySideOf(row.id, type(row.wornLink) == "string"
		and itemIDOf(row.wornLink) or nil)
	local cand = Verdict.statTable(row.lines, "candidate", api and api.candidate or nil)
	local eq   = Verdict.statTable(row.chestWornLines, "worn", api and api.worn or nil)
	local deltas = Verdict.statDeltas(cand, eq, order)
	local dtext = Verdict.deltaText(deltas, TOOLTIP_DELTA_MAX)
	if dtext == "" then
		-- No readable arithmetic on this pair (a weapon row judged on DPS, a
		-- worn side whose words the parser could not place). The row's own
		-- reason, verbatim — never a fabricated number.
		return shown, nil
	end
	local vs = ""
	if type(row.wornLink) == "string" then
		vs = " vs " .. itemNameOf(row.wornLink)
	end
	return (word and ("better on " .. word) or shown), (dtext .. vs)
end

-- ---- The partial-read disclosure (card t_b7a9e7a5, AC-E) ---------------------
--
-- The owner's ruling makes a NUMBER-FREE tooltip line cosmetic: it can never
-- suppress a verdict. The verdict therefore now appears for items that used to
-- be refused — and the card's requirement 5 is explicit that the tooltip must
-- be able to say the reading was PARTIAL rather than implying the tooltip was
-- fully understood. This is that surface.
--
-- The fact itself is owned by Verdict.lua: `Verdict.statTable`'s third return
-- carries the lines that were SKIPPED, and `Verdict.partialNote` renders the
-- wording. This function only asks for them and wraps the result in the muted
-- colour, so there is one definition of what "skipped" means and one wording —
-- never a second list of cosmetic strings living in the UI file.
--
-- Deliberately NOT part of the headline verdict word: the arrow still means
-- exactly what it meant, and the word is unchanged. It is a suffix on the
-- detail, "" when nothing was skipped (so every existing line is byte-
-- identical when the tooltip was fully read).
local function partialReadSuffix(row)
	if not (Verdict and type(Verdict.statTable) == "function"
		and type(Verdict.partialNote) == "function") then
		return ""
	end
	-- The client's own stat read, at the SAME precedence describeUpgrade uses:
	-- the read stored on the row when the verdict was decided (a quest reward
	-- row, which carries no id) and otherwise re-derived from the row's own
	-- item id (a bag row). Both branches feed the identical parse the verdict
	-- used, so the disclosure cannot disagree with the answer it describes.
	local api
	if type(row.api) == "table" then
		api = row.api
	else
		api = apiBySideOf(row.id, type(row.wornLink) == "string"
			and itemIDOf(row.wornLink) or nil)
	end
	local _, _, candIgnored = Verdict.statTable(row.lines, "candidate",
		api and api.candidate or nil)
	local note = Verdict.partialNote(candIgnored)
	-- The worn side is read too: a cosmetic line on the EQUIPPED item is the
	-- same partial read, and the equipped item's lines are the other half of
	-- the comparison that produced this verdict.
	if type(row.chestWornLines) == "table" and #row.chestWornLines > 0 then
		local _, _, eqIgnored = Verdict.statTable(row.chestWornLines, "worn",
			api and api.worn or nil)
		local combined = {}
		for _, l in ipairs(candIgnored or {}) do combined[#combined + 1] = l end
		for _, l in ipairs(eqIgnored or {}) do combined[#combined + 1] = l end
		note = Verdict.partialNote(combined)
	end
	if note == "" then return "" end
	return " " .. TOOLTIP_GREY .. "(" .. note .. ")" .. TOOLTIP_RESET
end

-- Turn one of the tooltip's own colour escapes into the (r, g, b) triple the
-- client's AddLine takes. The escapes STAY in the text (the rendered colour is
-- byte-identical to what shipped — AC-C) and the triple is derived FROM those
-- same constants, so the two can never disagree. A constant that does not parse
-- degrades to white rather than throwing on a hover.
local function colorTriple(esc)
	local hex = type(esc) == "string" and esc:match("|cff(%x%x)(%x%x)(%x%x)")
	if not hex then return 1, 1, 1 end
	local r, g, b = esc:match("|cff(%x%x)(%x%x)(%x%x)")
	return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

-- One verdict, as the tooltip renders it: a coloured HEADLINE (the verdict in
-- the player's own words + the leading reason) and, when the setting allows, a
-- muted DETAIL line (the read arithmetic). Two lines rather than one wall —
-- card t_cf2ad83c, U2/3.
--
-- Returns an array of { text = <string>, colour = <"green"|"amber"|"grey"> } or
-- nil when the row carries nothing to say. Colour is the same grammar the marker
-- uses: green for the answer the arrow draws, amber for the trade-off, grey for
-- every other outcome.
local function verdictLines(row, order)
	if row == nil or type(row.verdict) ~= "string" then return nil end

	local setting = TOOLTIP_UI.detail()

	-- AC-D / "Upgrades only": no line at all for the two non-answers. Applied
	-- before anything is built, so a suppressed row costs nothing.
	if setting == "upgrades" and not TOOLTIP_UI.worthALine(row) then return nil end

	-- "Full" and "Upgrades only" both carry the detail; "Compact" carries it
	-- only while Shift is held. The HEADLINE is never gated on Shift.
	local showDetail = (setting ~= "compact") or TOOLTIP_UI.shiftHeld()

	local out = {}
	if row.verdict == "UPGRADE" then
		local head, detail = describeUpgradeParts(row, order)
		out[#out + 1] = {
			text = TOOLTIP_GREEN .. TOOLTIP_PREFIX .. TOOLTIP_UI.word(row.verdict)
				.. " — " .. head,
			colour = "green",
		}
		if detail and showDetail then
			out[#out + 1] = { text = TOOLTIP_GREY .. detail, colour = "grey" }
		end
	elseif row.verdict == TRADE_OFF_VERDICT then
		-- Card t_89440dfa: the third outcome gets its own amber line with the
		-- read arithmetic — the card asks for "the exact deltas in the tooltip".
		-- The comparator's reason carries "trade-off: " as a lead-in and a
		-- "(Strength 12 vs 10)" parenthetical that restates in raw values what
		-- the detail line below states in deltas. Both are stripped for DISPLAY
		-- only (the stored reason is untouched); the headline is the one-line
		-- answer, the detail is the arithmetic.
		local reason = type(row.reason) == "string" and row.reason
			or "better on some stats, worse on others"
		reason = reason:gsub("^%s*trade%-off:%s*", ""):gsub("%s*%b()%s*$", "")
		local detail = nil
		if type(row.chestWornLines) == "table" and #row.chestWornLines > 0
			and Verdict and type(Verdict.statTable) == "function"
			and type(Verdict.statDeltas) == "function"
			and type(Verdict.deltaText) == "function" then
			local api = apiBySideOf(row.id, type(row.wornLink) == "string"
				and itemIDOf(row.wornLink) or nil)
			local cand = Verdict.statTable(row.lines, "candidate", api and api.candidate or nil)
			local eq   = Verdict.statTable(row.chestWornLines, "worn", api and api.worn or nil)
			local dtext = Verdict.deltaText(Verdict.statDeltas(cand, eq, order), TOOLTIP_DELTA_MAX)
			if dtext ~= "" then
				local vs = ""
				if type(row.wornLink) == "string" then
					vs = " vs " .. itemNameOf(row.wornLink)
				end
				detail = dtext .. vs
			end
		end
		out[#out + 1] = {
			text = TOOLTIP_AMBER .. TOOLTIP_PREFIX .. TOOLTIP_UI.word(row.verdict)
				.. " — " .. reason,
			colour = "amber",
		}
		if detail and showDetail then
			out[#out + 1] = { text = TOOLTIP_GREY .. detail, colour = "grey" }
		end
	elseif eligibilitySuppressed(row) then
		-- AC-D (the previous card's): the eligibility gate's silence is
		-- explained in words, not left as an absence.
		out[#out + 1] = {
			text = TOOLTIP_GREY .. TOOLTIP_PREFIX .. TOOLTIP_UI.word(row.verdict)
				.. " — eligibility unconfirmed",
			colour = "grey",
		}
	else
		local reason = type(row.reason) == "string" and row.reason or "no reason recorded"
		out[#out + 1] = {
			text = TOOLTIP_GREY .. TOOLTIP_PREFIX .. TOOLTIP_UI.word(row.verdict)
				.. " — " .. reason,
			colour = "grey",
		}
	end

	-- The partial-read disclosure rides the LAST line we are about to emit (it
	-- is a fact about the read, not about the verdict word). It is "" when
	-- nothing was skipped, so a fully-read tooltip is byte-identical to before.
	local note = partialReadSuffix(row)
	if note ~= "" then
		out[#out].text = out[#out].text .. note
	end
	-- Close EVERY line with the reset. Each line opens with its own colour
	-- escape, and the tooltip is the CLIENT's shared surface: an unclosed
	-- escape would bleed that colour into whatever another addon appends next.
	for i = 1, #out do
		out[i].text = out[i].text .. TOOLTIP_RESET
	end
	return out
end

-- Has our line already landed on this tooltip? The post-call can run more than
-- once for one item (a refresh re-fires it), and a duplicated row would be a
-- visible defect. The check reads the client tooltip's own rendered lines — its
-- <name>TextLeft<i> globals — so it costs nothing and needs no state to go
-- stale. Never throws: an unreadable tip simply reads as "not appended".
local function tooltipHasOurLine(tip)
	local name = type(tip) == "table" and tip.GetName and select(2, pcall(tip.GetName, tip))
	if type(name) ~= "string" or name == "" then return false end
	local n = 0
	local ok, count = pcall(tip.NumLines, tip)
	if ok and type(count) == "number" then n = count end
	for i = n, math.max(1, n - 3), -1 do
		local fs = _G[name .. "TextLeft" .. i]
		local ok2, text = pcall(function() return fs and fs.GetText and fs:GetText() end)
		-- Fold (MightiePack, t_c2e67619): the rendered line carries no
		-- addon name any more, so this guard cannot look for one. It looks
		-- for what the line DOES lead with: a verdict word followed by the
		-- headline separator, read from the same vocabulary the renderer
		-- uses, so render and detection cannot drift. The colour escape the
		-- line opens with is stripped first (the client hands back the
		-- marked-up string), and the comparison is anchored at position 1 —
		-- a verdict word appearing inside some other line never matches.
		if ok2 and type(text) == "string" then
			local plain = text:gsub("^%|c%x%x%x%x%x%x%x%x", ""):gsub("^%|r", "")
			for _, word in pairs(TOOLTIP_UI.words) do
				local marker = word .. " — "
				if plain:sub(1, #marker) == marker then
					return true
				end
			end
		end
	end
	return false
end

-- Find the verdict row for the item this tooltip is showing, or nil. The bag
-- scan's record is the primary source (every in-scope bag cell lands there); the
-- quest surface's anchored rows are the second.
local function tooltipRowFor(tip, data)
	local link = displayedLinkOf(tip, data)
	if type(link) ~= "string" then return nil end
	local bagRow = ChestAdvisor.__verdicts and ChestAdvisor.__verdicts[link]
	if type(bagRow) == "table" then return bagRow end
	local questRow = questTooltipRows[link]
	if type(questRow) == "table" then return questRow end
	return nil
end

-- The post-call. Signature matches both shapes the reference uses:
-- AddTooltipPostCall hands us (tooltip, data, ...); the HookScript fallback
-- hands us (tooltip) with no data, so `data` is optional and the displayed item
-- is then resolved from the tooltip itself.
local function tooltipPostCall(tip, data)
	if not TOOLTIP_UI.enabled() then return end
	if type(tip) ~= "table" then return end
	local row = tooltipRowFor(tip, data)
	if row == nil then return end
	if tooltipHasOurLine(tip) then return end
	local order
	do
		local spec = buildSpec()
		order = spec and spec.order or nil
	end
	local lines = verdictLines(row, order)
	if lines == nil then return end
	-- AddLine, and nothing else: no Show(), no SetOwner(). pcall keeps a client
	-- whose tooltip lacks AddLine from taking the whole hover down with it.
	--
	-- The 5th argument is the client's WRAP flag (card t_cf2ad83c, U2/1). Without
	-- it a long reason widens the whole tooltip to fit its longest line — the
	-- single most visible defect on the audit's list, because it is on every
	-- hover.
	for i = 1, #lines do
		local l = lines[i]
		local r, g, b = colorTriple(l.colour == "green" and TOOLTIP_GREEN
			or l.colour == "amber" and TOOLTIP_AMBER or TOOLTIP_GREY)
		local ok = pcall(tip.AddLine, tip, l.text, r, g, b, true)
		if not ok then pcall(tip.SetText, tip, l.text) end
	end
end

-- Install ONCE. The modern path first, the HookScript fallback second — the
-- reference's own pair, in the reference's own order, because that pair is the
-- evidence this API surface exists on this client build.
local tooltipHooked = false
local function installTooltipHook()
	if tooltipHooked then return end
	tooltipHooked = true
	if type(TooltipDataProcessor) == "table"
		and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
		and type(Enum) == "table"
		and type(Enum.TooltipDataType) == "table"
		and Enum.TooltipDataType.Item ~= nil then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, tooltipPostCall)
		return
	end
	-- Fallback for unexpected API changes during beta.
	if GameTooltip and type(GameTooltip.HookScript) == "function" then
		GameTooltip:HookScript("OnTooltipSetItem", function(self)
			tooltipPostCall(self, nil)
		end)
	end
end

-- The marker: the UPGRADE arrow -- a texture on the BAG BUTTON (the button
-- is the anchor; the frame is inert bookkeeping). Named
-- ChestAdvisorMarker_<n> as its pool bookkeeping frame so tests can find
-- and count it (f.__button and f.__arrow connect the frame to the button
-- render). A texture, not a fontstring: the fontstring label was the bug
-- F-NEW-1 corrects (clipped to nothing readable on this client), and the
-- client can render font glyph chars as missing-glyph squares
-- (ForeverGear/Bags.lua:77-78).
--
-- The §5a amendment of docs/whisperstone/phase-d-live-gate.md (2026-09-30,
-- the player's ruling on the beta client: "All we need is the green arrow",
-- "Arrow only -- drop the bar") retires the old W1 orange bar
-- (f.__texture) and its "DO-NOT: keep it" obligation -- the player's own
-- verdict supersedes. The arrow is all that is left (§5b corrects where it
-- lives -- see below).
--
-- §5b (phase-d-live-gate 2026-09-30, the live-verified ruling that supersedes
-- the §5a sentence below it): the marker frame is INERT PAINT — a pool /
-- bookkeeping object only. It is NOT mouse-enabled (the cell's mouse belongs
-- to the bag button, and a mouse-enabled frame over the cell is exactly the
-- defect the player hit in install #5: "I can no longer pick up the chest or
-- interact with it"). The visible arrow is a texture whose anchor is the BAG
-- BUTTON (anchorMarker's render step: button:CreateTexture, marker.tga,
-- 18x18, TOPRIGHT+1,+1; button.ChestAdvisorUpgradeMarker is the (button,
-- marker) reference), and the hover contract is an OnEnter hook ON THE
-- BUTTON (button:HookScript — HookScript, never SetScript).
--
-- (§5a history, kept for the audit trail: "the arrow is all that is left,
-- and it is NOT a mouse target on its own (textures are not mouse targets) --
-- so the FRAME is the hover hit area (f:EnableMouse, below), and anchorMarker
-- sizes it to the marked bag cell (f:SetAllPoints(button)) so the visible
-- marker sits INSIDE the area that receives the mouse." §5b withdraws that
-- sentence: in this build the frame is not mouse-enabled, hover rides the
-- button, and SetAllPoints no longer sizes a visible marker.)
--
-- Colorblind-safe marks. Off unless ChestAdvisorDB.markers.glyphs is exactly
-- true — a missing key (an older saved table, a fresh character) stays off.
-- No new art and no TOC change: a white ASCII glyph is drawn on the existing
-- arrow and on the trade-off chip. Exotic symbols become missing-glyph
-- squares in this client's font (the fontstring-marker bug), so the two
-- shapes are "+" and "^".
ChestAdvisor.markerGlyphs = { upgrade = "+", tradeoff = "^" }

function ChestAdvisor._glyphsOn()
	local db = rawget(_G, "ChestAdvisorDB")
	local markers = type(db) == "table" and db.markers or nil
	return type(markers) == "table" and markers.glyphs == true
end

function ChestAdvisor._paintGlyph(button, kind, anchor)
	if type(button) ~= "table" then return end
	local glyph = button.ChestAdvisorMarkerGlyph
	local words = ChestAdvisor.markerGlyphs
	local text = type(words) == "table" and words[kind] or nil
	local show = ChestAdvisor._glyphsOn() and type(text) == "string"
	if not show then
		if type(glyph) == "table" and type(glyph.SetShown) == "function" then
			pcall(glyph.SetShown, glyph, false)
		end
		return
	end
	if type(glyph) ~= "table" and type(button.CreateFontString) == "function" then
		local ok, fs = pcall(button.CreateFontString, button, nil, "OVERLAY", "GameFontHighlightSmall")
		if ok and type(fs) == "table" then
			glyph = fs
			button.ChestAdvisorMarkerGlyph = glyph
			if type(glyph.SetTextColor) == "function" then
				pcall(glyph.SetTextColor, glyph, 1, 1, 1, 1)
			end
		end
	end
	if type(glyph) ~= "table" then return end
	local rel = (type(anchor) == "table") and anchor or button
	if type(glyph.ClearAllPoints) == "function" then pcall(glyph.ClearAllPoints, glyph) end
	if type(glyph.SetPoint) == "function" then
		pcall(glyph.SetPoint, glyph, "CENTER", rel, "CENTER", 0, 0)
	end
	if type(glyph.SetText) == "function" then pcall(glyph.SetText, glyph, text) end
	if type(glyph.SetShown) == "function" then pcall(glyph.SetShown, glyph, true) end
end

-- Pre-anchor, the frame carries a W1 placeholder box (24x10, from
-- makeMarker). That box is the geometry of a SUPPRESSED marker -- a marker
-- whose slot button is absent/hidden never reaches the anchor/texture step
-- and is the state the B1 suppressed-marker test reads. It is not a size the
-- visible marker should ever wear in game (the visible arrow is the
-- 18x18 button texture).
--
-- Naming the pool frame ChestAdvisorMarker_<n> preserves the countable
-- convention the shipped tests already rely on (tests/upgrade_test.js:939,
-- tests/upgrade_test.js:1209, tests/upgrade_test.js:1361).
local function makeMarker(index, link, verdict, reason, roleLabel, slotWordText)
	local f = markerPool[index]
	if not f then
		f = CreateFrame("Frame", "ChestAdvisorMarker_" .. index)
		-- §5b (phase-d-live-gate 2026-09-30): the frame is a POOL /
		-- bookkeeping object only. The visible arrow is a texture on the
		-- BAG BUTTON (see anchorMarker's render step) and the hover hook
		-- rides the button's own mouse — the frame carries neither in this
		-- round. The W1 orange bar (f.__texture, SetColorTexture) is
		-- retired (player's ruling, §5a; carried into §5b).
		--
		-- NOT EnableMouse'd — the cell's mouse belongs to the button.
		-- The old §5a frame covered the cell with a mouse surface and
		-- intercepted every click at the marked slot — the player's live
		-- report on install #5, 2026-09-30 21:24:
		-- "Marker is on the chest but I can no longer pick up the chest or
		-- interact with it."
		--
		-- The 24x10 placeholder box (set below) is the geometry of a
		-- SUPPRESSED marker: the stub keeps it as-is so the B1
		-- suppressed-marker test can still read (width, height) from
		-- this state. §5b's "pool frame MAY remain so long as it is never
		-- mouse-enabled and never carries the visible arrow at cell size"
		-- is satisfied by this frame.
		f:SetSize(24, 10)
		f:EnableMouse(false)
		-- The arrow texture lives on the BUTTON (button:CreateTexture),
		-- created inside anchorMarker's render step (§5b geometry table,
		-- "marker" row). f.__arrow is retained as the addon-internal
		-- reference for R10 / AC10 marker-path assertions; it is set in
		-- anchorMarker alongside the actual CreateTexture call.
		-- Hover hooks (OnEnter / OnLeave) live on the BUTTON, installed
		-- in anchorMarker via button:HookScript — never on the frame.
		-- Do NOT SetShown(true) here: the anchor decision (anchorMarker)
		-- decides.
		markerPool[index] = f
	end
	-- Card t_89440dfa: the chip and the arrow share this pool and this frame
	-- shape; `__kind` is the honest label of which mark the frame is carrying
	-- this scan ("arrow" for UPGRADE, "chip" for TRADE_OFF). Set from the
	-- verdict, and clearMarkers drops it again so a reused frame can never keep
	-- a stale kind.
	f.__kind     = (verdict == TRADE_OFF_VERDICT) and "chip" or "arrow"
	f.__verdict  = verdict
	f.__reason   = reason
	f.__role     = roleLabel
	f.__link     = link
	-- Card t_e9a07624 (B4): the row's own slot WORD travels with the row. The
	-- hover used to recover it by parsing the link, which could never work (see
	-- installOnEnter). Stored here and copied onto the bag button at anchor time.
	f.__slotWord = slotWordText
	-- Do NOT SetShown(true) here and do NOT register in activeMarkers yet:
	-- the anchor decision (anchorMarker) is what makes the marker
	-- primary-visible. A marker whose slot button is absent/hidden stays
	-- created (suppressed-state box assertable; no arrow texture and no
	-- button hook were made) but is SUPPRESSED
	-- -- shown count is zero for that item. See anchorMarker and
	-- "B, t_b9c4291e".
	return f
end

-- Install the hover explanation ONCE per bag button (card t_89440dfa hoisted
-- this out of anchorMarker so the arrow and the trade-off chip share ONE hover
-- contract — the chip needs the same explanation, from the same data, and a
-- second copy would be a second thing to keep in step).
--
-- ⚠ Card t_e9a07624 (B2/B3) — TWO defects lived in the previous form of this
-- installer, and they are fixed by ONE change of shape:
--
--   B2 STACKED HOOKS. There was no once-per-button guard while anchorMarker
--   calls this on EVERY anchor, so each rescan appended another OnEnter and
--   another OnLeave hook to the same pooled Blizzard button — one pair per
--   scan, for the life of the session. A live bag-rescan loop is exactly the
--   churn that makes a button accumulate dozens.
--
--   B3 GHOST HOVER (the owner's live report: "shows the item in the bag after
--   I sell it"). The closure captured the POOL FRAME (`fr`) and read
--   `fr.__data`. clearMarkers hides the arrow and drops __verdict/__kind/
--   __arrow but the pool FRAME — and therefore the closure's captured
--   reference to it — survives the scan. So a sold/moved/vacated cell kept
--   explaining the item that used to be there whenever the client's GameTooltip
--   did not own the button at that moment (which is most likely on an EMPTY
--   cell — the exact case the player hit).
--
-- The fix is the shape the QUEST surface already uses (installQuestHover): the
-- guard table makes install idempotent per button, and the hook reads the
-- BUTTON's OWN live data table — `button.__chestAdvisorBagData` — which
-- anchorMarker writes on every anchor and clearMarkers drops with the arrow.
-- A button whose item is gone has no data, so the hover explains nothing; and
-- no second hook is ever added.
--
-- HookScript composes with the client's own handlers; SetScript would replace
-- them (a §5b rejected alternative — it clobbers the client's OnEnter on
-- Blizzard's item button; the reference uses HookScript throughout:
-- ForeverGear/Bags.lua, GroupLoot.lua:231-238, Quest.lua:214-222).
--
-- ⚠ Card t_e9a07624 (B4/B5) — the explanation is now ONE ruled line and the
-- internal tokens are gone:
--
--   * B5: the raw `role: / verdict: / reason:` lines are REMOVED. They were
--     debug output on the player's tooltip; the ruled verdict line below
--     already states the answer, and /up diag is where a reader asks for the
--     rest. (The wording restyle is the audit's U2, a different card — this
--     change only stops the leak.)
--
--   * B4: the slot word comes from the ROW (d.slotWord), which the scan wrote
--     from the item's own equipLocation — never from a hand-parse of the link.
--     The old derivation was
--         select(2, string.match(dlink, "^item:(%d+)"))
--     and it could NEVER yield a number: `^item:` cannot match a coloured
--     `|cff…|Hitem:…` link (itemIDOf's `item:(%d+)` does), and a pattern with a
--     SINGLE capture returns only ONE value, so `select(2, …)` is always nil.
--     `dinv` therefore always fell back to 5, and every item — the owner's
--     two-handed mace included — read "this chest".
--
-- ⚠ The verdict-aware branch: an UPGRADE keeps the ruled "UPGRADE (this <slot>
-- beats what you have)" line; the third outcome says "TRADE-OFF (better on some
-- stats, worse on others — your call)". Any other verdict keeps the generic
-- wording. The verdict is read from d.verdict, which the walk writes from the
-- SAME comparator return the marker's appearance uses.
local bagHookedButtons = {}         -- button -> true, hover installed ONCE (B2)
local function installOnEnter(btn)
	if type(btn) ~= "table" then return end
	if type(btn.HookScript) ~= "function" then return end
	if bagHookedButtons[btn] then return end
	bagHookedButtons[btn] = true
	btn:HookScript("OnEnter", function(self)
		-- The BUTTON's own data, not a captured pool frame (B3). Absent on a
		-- vacated/sold/reused cell -> nothing to explain.
		local d = self.__chestAdvisorBagData
		if type(d) ~= "table" then return end
		-- §5b tooltip, shape 2 (the implementer's choice, named in
		-- this commit): KEEP the addon's own getScanTip() tip, give
		-- it a position via SetOwner(button, "ANCHOR_RIGHT")
		-- (the house's live-proven positioned pattern —
		-- WoWAI.lua:2690 + five siblings, ForeverGear/UI.lua:149),
		-- and guard so it is never shown while the client's
		-- tooltip owns that button — the guard is not optional in
		-- either shape.
		local clientTip = GameTooltip
		local clientOwns = false
		if clientTip and type(clientTip.IsOwned) == "function" then
			local ok, owns = pcall(function() return clientTip:IsOwned(btn) end)
			clientOwns = ok and owns == true
		end
		if not clientOwns then
			local tip = getScanTip()
			if tip then
				-- B4: the slot word is the ROW's own, written by the scan from
				-- the item's equipLocation. "slot" only if a row carries none.
				local slotWordText = d.slotWord or "slot"
				local ok = pcall(function()
					tip:SetOwner(btn, "ANCHOR_RIGHT")
					tip:ClearLines()
					if type(d.link) == "string" then
						pcall(tip.SetHyperlink, tip, d.link)
					end
					-- U2/b (card t_cf2ad83c): the PLAYER WORDS, read through the
					-- one table the item tooltip also reads, so the two hover
					-- surfaces cannot drift. The tokens themselves (d.verdict)
					-- are the comparator's contract and are unchanged.
					if d.verdict == TRADE_OFF_VERDICT then
						explainLine(tip, TOOLTIP_PREFIX .. TOOLTIP_UI.word(d.verdict)
							.. " (better on some stats, worse on others — your call)")
					elseif d.verdict == "UPGRADE" then
						explainLine(tip, TOOLTIP_PREFIX .. TOOLTIP_UI.word(d.verdict)
							.. " (this " .. slotWordText .. " beats what you have)")
					else
						explainLine(tip, TOOLTIP_UI.word(d.verdict)
							.. " (this " .. slotWordText .. ")")
					end
					tip:Show()
				end)
				if not ok then tip:SetShown(true) end
			end
		end
		self.__chestAdvisorBagHover = true
	end)
	btn:HookScript("OnLeave", function(self)
		self.__chestAdvisorBagHover = nil
		local tip = getScanTip()
		if tip then tip:SetShown(false) end
	end)
end

-- The visible item button for a (bag, slot) cell, or nil.
--
-- In the pinned client the bag item slots are dynamically created ItemButtons
-- from a frame pool, and the only stable (bag, slot) -> item-button lookup is
-- ContainerFrameUtil_GetItemButtonAndContainer(bag, slot); the legacy global
-- name is the fallback for a client that keeps the old frames. Extracted here
-- because BOTH anchor decisions (the UPGRADE arrow and the trade-off chip,
-- card t_89440dfa) must resolve the cell the same way — one lookup, one answer.
local function findBagButton(bag, slot)
	if type(ContainerFrameUtil_GetItemButtonAndContainer) == "function" then
		local ok, itemButton = pcall(ContainerFrameUtil_GetItemButtonAndContainer, bag, slot)
		if ok and type(itemButton) == "table" and itemButton:IsShown() then
			return itemButton
		end
	end
	if type(_G) == "table" then
		local legacy = _G["Bag" .. tostring(bag) .. "Slot" .. tostring(slot)]
		if type(legacy) == "table" and legacy:IsShown() then return legacy end
	end
	return nil
end

-- Anchor a marker to the bag slot it belongs to.
--
-- B (Vera round 3, t_b9c4291e): in the pinned client (Gethe/wow-ui-source@
-- forever), bag item slots are dynamically created ItemButtons drawn from a
-- frame pool, not global "Bag<X>Slot<Y>" frames
-- (Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:777 — CreateFramePool;
-- line 2245 — the util API that pairs them;
-- Shared/MainMenuBarBagButtons.lua:153-158 — GetBagID / CharacterBag0Slot,
-- pool-scoped, none of them a global).
--
-- The only stable (bag, slot) -> item-button lookup the pinned client
-- exposes is ContainerFrameUtil_GetItemButtonAndContainer(bag, slot). When
-- the bag window is not showing right now — or the slot is hidden/ambiguous
-- behind a different bag — that lookup misses.
--
-- Task contract: "show marker ONLY when linked to its matching visible bag
-- slot. If button absent/hidden/ambiguous, suppress marker and expose
-- diagnostic reason; never invent a screen position." So:
--
--   * Real pin — the marker frame (inert paint, §5b) stays the pool /
--     bookkeeping object; the VISIBLE marker is the arrow texture on the
--     visible item button (button:CreateTexture, 18x18, TOPRIGHT +1,+1 —
--     the §5b corrected geometry, superseding the old "parent + anchor at
--     BOTTOMLEFT" sentence), and the hover contract (OnEnter) is a hook on
--     the button (button:HookScript), which already owns the cell's mouse.
--     SetShown(true) the frame and register in activeMarkers. The marker
--     draws where the slot is.
--   * Miss — do NOT fall back to UIParent (that is inventing a screen
--     position). Leave the created-but-hidden marker for geometry checks
--     (size + suppressed-state box still assertable; the arrow texture and
--     button hook simply were not created) and stash a diagnostic
--     string that a test (or /upgrade diag) can read from the
--     verdict. No activeMarkers registration, no SetShown, so the shown
--     count for this item is zero and the marker cannot be confused with
--     a "floating badge".
local function anchorMarker(f, bag, slot, link, slotWordText)
	local button = findBagButton(bag, slot)

	local diag = "bag-slot anchor (diagnostic)"
	if type(button) == "table" then
		-- §5b (phase-d-live-gate 2026-09-30): the marker path has NO mouse
		-- surface and the visible arrow is a texture whose relative is the
		-- BUTTON — the geometry pinned in §5b's corrected table:
		--   button:CreateTexture(nil, "OVERLAY", nil, 7)
		--   SetTexture((MIGHTIEPACK_TOUCHSTONE_ASSETS .. "marker.tga"))
		--   SetSize(18, 18)
		--   SetPoint("TOPRIGHT", button, "TOPRIGHT", 1, 1)
		-- The arrow is stored on the button under ChestAdvisor's own
		-- namespace (button.ChestAdvisorUpgradeMarker), so the
		-- reference addon's `button.ForeverGearUpgradeMarker` stays
		-- exclusively ForeverGear's and can never be read, hidden or
		-- re-pointed by ChestAdvisor's suppress/re-anchor paths. A
		-- ChestAdvisor-namespaced texture is still reused across
		-- scans (the marker guard below) so repeated scans do not
		-- leak a texture per scan on Blizzard's button.
		--
		-- Hover rides the button's own mouse: button:HookScript("OnEnter", …)
		-- / ("OnLeave", …) — HookScript, never SetScript (SetScript clobbers
		-- the client's own OnEnter on Blizzard's item button, a §5b
		-- rejected alternative).
		--
		-- The pool frame (f) is never mouse-enabled and never carries the
		-- visible arrow at cell size (§5b permits its continued existence
		-- for bookkeeping: marker name, f.__arrow reference, the B1/B3
		-- suppress + shown-count tests).
		local texture = (button.ChestAdvisorUpgradeMarker and type(button.ChestAdvisorUpgradeMarker) == "table"
			and button.ChestAdvisorUpgradeMarker.kind == "Texture")
			and button.ChestAdvisorUpgradeMarker
			or nil
		-- Hide any texture a previous pool frame drew on this button before
		-- re-pointing — a re-marking from a different frame slot must not
		-- leave a stale visible chip.
		if texture and texture ~= f.__arrow then
			pcall(texture.SetShown, texture, false)
		end
		-- Card t_89440dfa: ONE namespaced texture per button carries whichever
		-- mark this row has — the green arrow (marker.tga) for UPGRADE, or the
		-- amber colour chip for TRADE_OFF. The verdict is re-asserted EVERY
		-- anchor (not only on creation): a pooled button can be an arrow one
		-- scan and a chip the next, and a texture left as the arrow would tell
		-- the player "upgrade" for a trade-off.
		local isTradeOff = (f.__verdict == TRADE_OFF_VERDICT)
		if not texture then
			texture = button:CreateTexture(nil, "OVERLAY", nil, 7)
		end
		-- One anchor. The same texture flips between the arrow (TOPRIGHT) and
		-- the chip (BOTTOMRIGHT). SetPoint adds an anchor; without clearing,
		-- a cell that changes verdict keeps both and the texture stretches.
		if type(texture.ClearAllPoints) == "function" then
			pcall(texture.ClearAllPoints, texture)
		end
		if isTradeOff then
			-- The chip: a plain solid square, NO texture file (the card forbids
			-- new art). SetColorTexture is the zero-asset route.
			if type(texture.SetColorTexture) == "function" then
				texture:SetColorTexture(TRADEOFF_R, TRADEOFF_G, TRADEOFF_B, TRADEOFF_A)
			end
			texture:SetSize(TRADEOFF_SIZE, TRADEOFF_SIZE)
			texture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
		else
			if type(texture.SetTexture) == "function" then
				texture:SetTexture((MIGHTIEPACK_TOUCHSTONE_ASSETS .. "marker.tga"))
			end
			texture:SetSize(18, 18)
			texture:SetPoint("TOPRIGHT", button, "TOPRIGHT", 1, 1)
		end
		button.ChestAdvisorUpgradeMarker = texture
		f.__arrow = texture
		-- Bookkeeping (pool-frame side): which cell this frame's arrow lives
		-- on. §5b's frame carries no parent/anchor, so the (frame -> cell)
		-- pairing — the "each marker pins to its OWN slot" contract the B
		-- tests assert — is exposed here for test/inspection.
		f.__button = button
		-- Hover hooks: the frame's OnEnter/OnLeave (retired — §5b's
		-- geometry table, "hover" row) move to the BUTTON, which already
		-- owns the mouse and the whole cell. The shared installer is
		-- hoisted above anchorMarker (card t_89440dfa) so the trade-off
		-- chip's cell gets the same explanation from the same data.
		--
		-- Card t_e9a07624 (B2/B3): the installer is idempotent per button
		-- and its hook reads the BUTTON's own row — so the row must be
		-- written HERE, on every anchor, and (in clearMarkers) dropped with
		-- the arrow. A stale assignment would be the ghost hover; writing it
		-- fresh each anchor is what makes the vacated cell explain nothing.
		button.__chestAdvisorBagData = {
			link = link, verdict = f.__verdict, reason = f.__reason,
			role = f.__role, slotWord = slotWordText,
		}
		installOnEnter(button)
		-- Re-show the arrow we are drawing on this button. This is the HAZARD
		-- the card calls out (variant B / "naive fix"): clearMarkers() runs at
		-- the top of EVERY scan and now hides the button's texture for every
		-- pooled frame (teardown of the live-bug-1 ghost). Without this
		-- re-show, the anchor branch that just (re- or new-)created the
		-- texture on this very button would be immediately re-hidden by that
		-- same scan, so the common "upgrade sitting in the bag, player
		-- rescans / a drag moved it to another cell" path would paint a
		-- marker that is never visible — the player loses the only hint the
		-- cell is an upgrade. The pcall matches the file's own suppress/
		-- re-anchor guard style (:466-468, :550-554): a client that already
		-- destroyed the texture cannot abort the anchor walk.
		if type(texture.SetShown) == "function" then
			pcall(texture.SetShown, texture, true)
		end
		ChestAdvisor._paintGlyph(button, isTradeOff and "tradeoff" or "upgrade", texture)
		f:SetShown(true)
		diag = "anchored to: " .. tostring(button.name or button)
		-- Register in activeMarkers AFTER the anchor decision, so a marker
		-- that is created but suppressed does not count as live.
		activeMarkers[link] = f
	else
		-- The button was not visible (or no button was found). If we
		-- previously attached a marker onto it, hide it: this is the W1
		-- "close the bag → marker hides" path the reference's
		-- hideMarkersInFrame implements (Bags.lua:333-349, "when the bag
		-- window is closed, hide markers in the frame").
		if button and type(button.ChestAdvisorUpgradeMarker) == "table"
			and type(button.ChestAdvisorUpgradeMarker.SetShown) == "function" then
			pcall(button.ChestAdvisorUpgradeMarker.SetShown,
				button.ChestAdvisorUpgradeMarker, false)
		end
		f:SetShown(false)
		diag = "no visible bag-slot button for bag=" .. tostring(bag)
			.. " slot=" .. tostring(slot)
			.. " — marker suppressed (never invent a screen position)"
	end
	-- Expose the diagnostic on the marker so a test or a /upgrade diag can
	-- find WHICH path ran and why. f.__kind is already set by makeMarker from
	-- this frame's verdict ("arrow" | "chip"), so a reader can tell the two
	-- marks apart after the fact.
	f.__anchorDiag = diag
	return true
end

-- B3 (Vera round 2): markerNext used to grow monotonically, so every rescan
-- that produced at least one UPGRADE allocated a brand-new pool slot — in a
-- live session (constant bag churn) the pool of marker frames grew without
-- bound. clearMarkers is the natural reset point: a scan that re-runs after
-- a clear starts allocation back at index 1, reusing markerPool[1] and
-- friends instead of creating new frames. The pool therefore grows only to
-- the maximum simultaneous marker count, never past it.
-- B, t_b9c4291e: capacity is measured against markerNext (this scan's
-- allocation count — active AND suppressed markers alike), not the size of
-- activeMarkers. activeMarkers only ever holds SHOWN markers, so a scan
-- that suppressed everything would otherwise think it had infinite headroom
-- and hand out a fresh frame every time. clearMarkers resets markerNext to
-- 0 at the start of each scan, so the cap naturally re-applies per scan.
local function clearMarkers()
	-- Hide every allocated pool frame: both the active ones (registered in
	-- activeMarkers) and the suppressed ones (created here but not
	-- registered). We walk markerPool directly — that is the single
	-- authoritative list of frames this addon has allocated. Frames that are
	-- already hidden are left alone; the cost is one call per frame.
	for _, f in pairs(markerPool) do
		if type(f) == "table" then
			f:SetShown(false)
			f.shown = false
			-- Live-bug-1 teardown (2026-10-01, E5 install #9): the visible
			-- arrow is a texture parented to the BAG BUTTON, not to this pool
			-- frame (§5b geometry, anchorMarker's render step). Hiding the
			-- pool frame therefore leaves the button's arrow texture shown —
			-- which is why a now-empty, vacated or re-used cell keeps a
			-- "stale/ghost" arrow after its item is equipped, moved, or the
			-- bag re-scans. The client pools slot buttons, so the button (and
			-- its texture) outlives the item; only the addon can hide it.
			--
			-- A markerPool walk reaches the button because pool frames keep
			-- their f.__button until the next scan reassigns it, and
			-- clearMarkers() runs at the top of every scan — so at teardown
			-- f.__button still points at the PREVIOUS scan's button. That is
			-- what makes this single teardown point sufficient to clear both
			-- the equip case (item leaves the slot) and the move case 6b
			-- (item drag-re-anchored to a different cell, vacated cell must
			-- not keep the arrow).
			--
			-- Guard style matches the file's own suppress/re-anchor paths
			-- (:466-468 and :550-554): a SetShown(false) inside pcall, so a
			-- client that has already destroyed the texture cannot abort the
			-- teardown walk. Then drop the f.__button reference so a dead
			-- handle is not retained past teardown.
			local btn = f.__button
			if type(btn) == "table"
				and type(btn.ChestAdvisorUpgradeMarker) == "table"
				and type(btn.ChestAdvisorUpgradeMarker.SetShown) == "function" then
				pcall(btn.ChestAdvisorUpgradeMarker.SetShown,
					btn.ChestAdvisorUpgradeMarker, false)
			end
			-- Card t_e9a07624 (B3 — THE GHOST HOVER FIX). The arrow was
			-- hidden but the hover row survived on the pooled button, so a
			-- sold/equipped/moved item kept being explained on its now-empty
			-- cell (the owner's live report). The hover hook reads the
			-- BUTTON's data now (installOnEnter), so dropping it HERE — at
			-- the same teardown point that already hides the arrow — is what
			-- makes a vacated cell silent. This is the exact pairing the
			-- existing Live-bug-1 test never covered: it asserted the ARROW
			-- was hidden, which stayed true while the hover still lied.
			if type(btn) == "table" then
				btn.__chestAdvisorBagData = nil
				ChestAdvisor._paintGlyph(btn, nil)
			end
			f.__button = nil
			-- Card t_89440dfa: drop the mark's identity with its button, so a
			-- reused pool frame cannot be read as carrying the PREVIOUS scan's
			-- verdict/kind. The next makeMarker re-asserts all three.
			f.__verdict = nil
			f.__kind = nil
			f.__arrow = nil
			f.__slotWord = nil
		end
	end
	for link in pairs(activeMarkers) do
		activeMarkers[link] = nil
	end
	-- Reset the allocation pointer: next scan starts over at index 1 and
	-- reuses markerPool[1] and friends, not a new frame per scan.
	markerNext = 0
end

-- ---- W1 (t_f793ace7): refresh-on-bag-open, ported from ForeverGear ----
--
-- The bag UI on the pinned client (Gethe/wow-ui-source@forever) does NOT send
-- BAG_UPDATE / BAG_UPDATE_DELAYED in this flow — it is bag-FRAME driven: bag
-- windows are frame pools (ContainerFrameCombinedBags with EnumerateValidItems,
-- ContainerFrameContainer.ContainerFrames, classic ContainerFrame<i>), created
-- when the bag is opened, and refreshed on UpdateItems / the OpenBackpack & co.
-- entry points. The reference that ships in this client (ForeverGear/Bags.lua)
-- therefore never relies solely on the event path while bags are closed:
-- it hooks OnShow (Bags.lua:367-389), the bag-open functions (Bags.lua:391-412,
-- 457-462), and gates every refresh on AnyBagFrameShown (Bags.lua:236-257).
-- A prior ChestAdvisor revision registered BAG_UPDATE only and shipped a marker
-- that could not appear through the real open-and-lace flow (the bag window was
-- closed during the BAG_UPDATE event, so no slot button was visible and the
-- marker was suppressed). This block hooks the same surface the reference hooks
-- and re-scans only when a bag window is actually shown.
--
-- Design choice: the refresh is a *rescan* (ChestAdvisor.scan()), not a per-button
-- patch. ChestAdvisor's marker model anchors to the slot button and re-builds from
-- current state on each scan; that is the correct primitive here. We deliberately
-- do NOT import the reference's upgradeCache or the per-button EnsureMarker patch,
-- because ChestAdvisor's anchor path (the "never invent a screen position" rule)
-- is what makes the marker live on the button in the first place, and the reference's
-- own comment (Bags.lua:375-376) is just to refresh "when the bag actually becomes
-- visible."
--
-- This file is loaded as its own addon, so every local below must be defined
-- before any later use (tests/order_check.js enforces this). We only reference
-- locals defined ABOVE this point (clearMarkers, buildSpec, ChestAdvisor.scan
-- are all already in scope or assigned by the time the C_Timer callbacks fire).

local refreshGen = 0
local hookedOnShowFrames = {}
local hookedUpdateItemsFrames = {}
local hookedBagOpenFunctions = {}

-- True if any bag window on this client is currently shown. Mirrors
-- Bags:AnyBagFrameShown (Bags.lua:236-257). A nil window (the client did not
-- create it at this moment) is treated as "not visible," not as an error.
local function anyBagFrameShown()
	local cb = rawget(_G, "ContainerFrameCombinedBags")
	if type(cb) == "table" and cb:IsShown() then return true end
	local container = rawget(_G, "ContainerFrameContainer")
	if type(container) == "table" and container.ContainerFrames then
		for _, f in ipairs(container.ContainerFrames) do
			if type(f) == "table" and f:IsShown() then return true end
		end
	end
	local classic = tonumber(rawget(_G, "NUM_CONTAINER_FRAMES")) or 5
	for i = 1, classic do
		local f = rawget(_G, "ContainerFrame" .. i)
		if type(f) == "table" and type(f.IsShown) == "function" and f:IsShown() then
			return true
		end
	end
	return false
end

-- The scan entry every refresh path routes through. Performs a gated rescan;
-- the generation token dedupes overlapping callbacks (stale ones from a prior
-- open call drop out at the myGen ~= refreshGen check).
ChestAdvisor._onContentRefresh = function()
	-- Gate: never re-scan while the bag UI is closed. (Bags.lua:526-528:
	-- "Do not rescan every bag item while the bag UI is closed.")
	if anyBagFrameShown() then
		ChestAdvisor.scan()
		return true
	end
	return false
end

-- Schedule exactly one gated rescan (deduped by generation) for the next
-- C_Timer tick. A stale callback from an earlier open call bails out at the
-- generation check, so an open, close, open sequence produces exactly one
-- visible refresh (not three), matching the reference's pattern (Bags.lua:
-- 300-312, a generation token with the same purpose).
local function scheduleRefreshNow()
	refreshGen = refreshGen + 1
	local myGen = refreshGen
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			if myGen ~= refreshGen then return end
			ChestAdvisor._onContentRefresh()
		end)
	else
		ChestAdvisor._onContentRefresh()
	end
end

-- Hook every bag window's OnShow. The frame guard (hookedOnShowFrames) is
-- essential: double-wrapping would double-fire every open (the reference keeps
-- the same guard, Bags.lua:368-371). The reference implementation (Bags.lua:
-- 367-389) schedules a refresh one tick past the fire via C_Timer.After(0,...);
-- we do the same here, with a generation token preventing a stale callback
-- from a prior open call from double-rescanning.
local function hookFrameOnShow(frame)
	if type(frame) ~= "table" then return end
	if hookedOnShowFrames[frame] then return end
	if type(frame.HookScript) ~= "function" then return end
	frame:HookScript("OnShow", function()
		scheduleRefreshNow()
	end)
	hookedOnShowFrames[frame] = true
end

-- Hook a bag window's UpdateItems method (the client re-renders its buttons
-- here after loot/swap, reference Bags.lua:422-429 / 438-448). Guarded by the
-- per-frame table so a re-install does not double-wrap. We only refresh when
-- a bag window is actually shown, mirroring Bags:UpdateFrame's gate.
local function hookFrameUpdateItems(frame)
	if type(frame) ~= "table" then return end
	if hookedUpdateItemsFrames[frame] then return end
	if type(hooksecurefunc) ~= "function" then return end
	hooksecurefunc(frame, "UpdateItems", function()
		if anyBagFrameShown() then scheduleRefreshNow() end
	end)
	hookedUpdateItemsFrames[frame] = true
end

-- Hook the standard bag-open global functions. The reference hooks all four
-- (Bags.lua:459-462); we match that surface (OpenBackpack/ToggleBackpack
-- cover the window, OpenAllBags/ToggleAllBags reach the individual-bag
-- paths).
local function hookBagOpenFunction(functionName)
	if hookedBagOpenFunctions[functionName] then return end
	if type(_G[functionName]) ~= "function" then return end
	if type(hooksecurefunc) ~= "function" then return end
	hooksecurefunc(functionName, function()
		local frame = rawget(_G, "ContainerFrameCombinedBags")
		if type(frame) == "table" and frame:IsShown() then
			scheduleRefreshNow()
		end
	end)
	hookedBagOpenFunctions[functionName] = true
end

-- Install all the hooks. Called once at load and re-runnable on demand (the
-- guarded tables make every re-entry idempotent, so frames the client creates
-- lazily at open time still get exactly one hook each).
local function installRefreshHooks()
	-- Combined-bags frame pool.
	local combined = rawget(_G, "ContainerFrameCombinedBags")
	if type(combined) == "table" then
		hookFrameOnShow(combined)
		hookFrameUpdateItems(combined)
	end
	-- Individual modern bag frames.
	local container = rawget(_G, "ContainerFrameContainer")
	if type(container) == "table" and type(container.ContainerFrames) == "table" then
		for _, f in ipairs(container.ContainerFrames) do
			hookFrameOnShow(f)
			hookFrameUpdateItems(f)
		end
	end
	-- Classic container frames. Read the client's own pool count, with the
	-- same `or` fallback the reference uses (Bags.lua:252 / 276 / 452; default
	-- 13 there, 5 bag slots here).
	local classicCount = tonumber(rawget(_G, "NUM_CONTAINER_FRAMES")) or 5
	for i = 1, classicCount do
		hookFrameOnShow(rawget(_G, "ContainerFrame" .. i))
	end
	-- Open functions: the entry points that create-or-show bag windows.
	hookBagOpenFunction("OpenAllBags")
	hookBagOpenFunction("ToggleAllBags")
	hookBagOpenFunction("OpenBackpack")
	hookBagOpenFunction("ToggleBackpack")
end

-- Expose reinstall for the open-function hooks: the reference re-discovers
-- lazily created frames inside its open-function callback (Bags.lua:400-407);
-- the stub's OpenBackpack does the same so frames created at open time get
-- hooked. Also usable directly by tests.
local _installRefreshHooks = installRefreshHooks
ChestAdvisor._installRefreshHooks = installRefreshHooks

-- Expose the refresh so a later test or another addon can force a gated
-- rescan explicitly (the OnShow / open-function / UpdateItems hooks cover the
-- automatic paths).
ChestAdvisor.refreshOnBagOpen = function()
	_installRefreshHooks()
	return ChestAdvisor._onContentRefresh()
end

-- Fold (MightiePack Touchstone module): hook installation is deferred to
-- ChestAdvisor.Enable(). The function is already exposed as
-- ChestAdvisor._installRefreshHooks above.

-- ---- Quest reward arrows (t_c3fe7d1d) ---------------------------------------
--
-- The owner asked for the arrow on QUEST REWARD CHOICES ("Im not seeing the
-- upgrade arrow on quest rewards. That we would a great place for it. Will tell
-- the user what to pick reward wise."). This is a SECOND INPUT SURFACE for the
-- same comparator -- new verdict INPUT, not new verdict logic. Verdict.lua is
-- untouched and no bag-path line changes (AC-B, AC-G, constraint 1).
--
-- WHERE THE BUTTONS ARE (verified against the client's own source, NOT guessed;
-- AC-A step 1). This is a `vanilla`-family build (## Interface: 16001), so the
-- quest frame comes from the [Game] variant --
--   Blizzard_UIPanels_Game/Blizzard_UIPanels_Game.toc:
--     [Game]\QuestInfo.lua   [AllowLoadGameType vanilla, tbc]
--   => Blizzard_UIPanels_Game/Vanilla/QuestInfo.lua is the file that loads.
--   Mainline/QuestInfo.lua is the WRONG variant (different line numbers).
--   * The reward buttons are created LAZILY by QuestInfo_GetRewardButton
--     (Vanilla/QuestInfo.lua:380-388): the access path is
--     `rewardsFrame.RewardButtons[index]` -- a Lua table, not a fixed global
--     list, and the buttons do not exist until that function creates them.
--   * The rewards frame is SWAPPED at runtime: QuestInfoFrame.rewardsFrame is
--     set to QuestInfoRewardsFrame or MapQuestInfoRewardsFrame depending on
--     context (Vanilla/QuestInfo.lua:77-86). We read QuestInfoFrame.rewardsFrame
--     and never hardcode one frame (constraint 2).
--   * A reward button carries `.type` ("choice" | "reward"), `.objectType`
--     ("item" | "currency") and `.ID` (set by questItem:SetID(i),
--     Vanilla/QuestInfo.lua:560). The item LINK is GetQuestItemLink(type, id).
--     GetQuestItemInfo (also present) returns `name, texture, numItems,
--     quality, isUsable` -- with no itemID -- which is why the link API is the
--     read that yields a judgeable item here.
--
-- ELIGIBILITY (AC-C) fails CLOSED, exactly like the bag scan: only a definitive
-- `true` from C_PlayerInfo.CanUseItem may reach UPGRADE (Verdict.lua gate 3,
-- which armour/off-hand rows reach through Verdict.evaluate; the weapon rows
-- check it here the same way the bag walk does). An ineligible reward renders
-- NO mark -- a confident arrow on an item the player cannot use is worse than
-- none. "Binds when picked up" is NOT a blocker -- it is normal.
--
-- NAMESPACE ISOLATION (AC-D): every frame, texture and hook is OURS
-- (button.ChestAdvisorUpgradeMarker -- the addon's own namespace key) and every
-- Blizzard handler is COMPOSED with HookScript, never replaced with SetScript.
-- Blizzard's own OnShow/OnEnter/OnClick keep running.
--
-- LIFECYCLE (AC-E/F): the reward frame re-anchors on every open (an OnShow hook
-- and a hooksecurefunc on QuestInfo_ShowRewards/QuestInfo_Display schedule a
-- refresh), the markers are cleared on close (an OnHide hook plus the
-- QUEST_FINISHED event), and a re-render of the same quest clears then
-- re-anchors (the refresh begins with clearQuestMarkers). No marker is created
-- while the reward UI is hidden (the questRewardUIshown gate below).
--
-- The judgement glue MIRRORS the bag walk's per-row branch (the walk is inline
-- in ChestAdvisor.scan and this card forbids restructuring it). The COMPARATOR
-- itself is not duplicated: every verdict comes from Verdict.evaluate /
-- Verdict.weaponGate+compareDPS / Verdict.offHandGate -- the same frozen
-- Tier A/B/C functions the bag walk calls.
-- Shared by the quest surface (below) and the character-pane / vendor
-- walks. Kept at chunk scope so those later walks call them by name;
-- the quest block captures them as upvalues.
local QUEST_ARROW_SIZE = 18         -- bag-marker parity (§5b geometry)
local QUEST_ARROW_TEXTURE =
	(MIGHTIEPACK_TOUCHSTONE_ASSETS .. "marker.tga")

-- Is this frame shown right now? nil / non-frame / a throwing IsShown all read
-- as "not shown" (a hidden panel must never draw).
local function frameIsShown(f)
	if type(f) ~= "table" or type(f.IsShown) ~= "function" then return false end
	local ok, shown = pcall(function() return f:IsShown() end)
	return ok and shown == true
end

-- The quest surface is its own scope. Lua 5.1 allows 200 locals in the
-- main chunk; this block used to spend dozens of them. What it defines
-- lives here and is published on ChestAdvisor for the walks that run
-- later (vendor, scan). Those walks receive the same function objects.
do
local function initQuestSurface()
local QUEST_MARKER_MAX = 8          -- a turn-in has a handful of rewards at most

-- ---- Vendor-value fallback: the gold coin (card t_8d653c12) -----------------
--
-- THE RULE (the card's rule, stated here so the code carries it too):
--
--     If and only if NO row in the current reward set is UPGRADE, place a coin
--     on the single highest sell-price CHOICE row.
--
-- WHY. The reward panel is the surface the player actually picks gear on, and on
-- the most common levelling case every reward is worse than what he wears — so
-- today the panel shows nothing and he hovers each option to compare by hand.
-- When nothing is an upgrade, the decision that remains is MONEY, and the answer
-- belongs where his eye already is.
--
-- ⚠ ELIGIBILITY DOES NOT MATTER FOR SELLING. An item this character CANNOT WEAR
-- can still be the most valuable thing on the panel, and it can still earn the
-- coin. This is deliberate and it is the rule a later reader is most likely to
-- "fix" wrongly: the coin is about GOLD, not about wearing the item. Do NOT
-- route the coin through the CanUseItem / Verdict gate — that would turn the
-- feature OFF for exactly the case it exists for (a panel of unusable, valuable
-- rewards). The arrow's fail-closed eligibility rule (AC-C above) applies to the
-- ARROW, not here.
--
-- VISUAL DISTINCTNESS (AC-A): a coin, never an arrow, never green. It is the
-- client's own money icon — a yellow disc — against the arrow's green marker.tga,
-- so the two cannot be confused at a glance. No new art (an explicit constraint).
--
-- NO AUTO-SELECT. It marks; the player clicks. Nothing here touches the button's
-- own scripts or the client's selection state.
--
-- TIES (the card asks which way): highest sell price wins; ties break by reward
-- index, LOWEST index first (the deterministic walk order below). A tie is
-- therefore resolved to the first-listed of the equally valuable choices.
local COIN_SIZE = 16                -- a touch smaller than the arrow, so the
                                    -- silhouette differs even at a glance
local COIN_TEXTURE = "Interface\\MoneyFrame\\UI-GoldIcon"
-- The coin texture, PROVEN present on this client by PRECEDENT, not assumption:
-- two installed addons draw it on this exact build —
--     AtlasLootClassic/Constants.lua   "Interface\\MoneyFrame\\UI-GoldIcon"
--     GearQuestForever/Data.lua        |TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t
-- ⚠ Do NOT "verify" this path on the filesystem. Blizzard's stock textures live
-- inside MPQ archives, NOT in Interface/ on disk (only AddOns/ is enumerable),
-- so an os.path.exists()-style check here can only ever answer "missing" — a
-- green it cannot produce is not a check. The precedent above is the evidence.
-- (Our OWN textures are different: marker.tga sits under Interface/AddOns/... and
-- IS a real file, so filesystem checks are valid THERE. Know which side of the
-- MPQ boundary a path is on before choosing the check.)

local questMarkerPool = {}
local questMarkerNext = 0
local questActiveMarkers = {}       -- link -> true, this refresh's shown markers
local questHookedFrames = {}        -- frame -> true, OnShow/OnHide installed
local questHookedButtons = {}       -- button -> true, hover installed once
local questHookedShowRewards = false
local questHookedDisplay = false
local questRefreshGen = 0
local questRefreshed = 0            -- refreshes that ran with the UI shown (test/diag)
local questWalked = 0               -- reward buttons examined in the last refresh
local questUpgrades = 0             -- markers anchored in the last refresh
local questTradeoffs = 0            -- TRADE_OFF chips anchored in the last refresh
local questNoMark = 0               -- rows that produced no mark in the last refresh
local questCoinIndex = nil          -- reward index the coin was drawn on, or nil (test/diag)
local questCoinCandidates = 0       -- CHOICE rows that carried a numeric sellPrice (test/diag)


local function questRewardsFrame()
	-- Prefer the context-swapped field the client itself reads.
	local qif = rawget(_G, "QuestInfoFrame")
	if type(qif) == "table" and qif.rewardsFrame ~= nil then return qif.rewardsFrame end
	local a = rawget(_G, "QuestInfoRewardsFrame")
	if type(a) == "table" then return a end
	return nil
end

local function questRewardUIshown()
	if frameIsShown(questRewardsFrame()) then return true end
	if frameIsShown(rawget(_G, "MapQuestInfoRewardsFrame")) then return true end
	if frameIsShown(rawget(_G, "QuestFrameRewardPanel")) then return true end
	return false
end

-- Read every in-scope worn slot once, mirroring the bag walk's own pre-read.
local function readWornLinks()
	local wornLinks = {}
	if type(GetInventoryItemLink) ~= "function" then return wornLinks end
	local slots, seen = {}, {}
	for _, s in pairs(EQUIP_SLOTS) do
		if not seen[s] then slots[#slots + 1] = s; seen[s] = true end
	end
	for _, pair in pairs(PAIR_SLOTS) do
		for _, s in ipairs(pair) do
			if not seen[s] then slots[#slots + 1] = s; seen[s] = true end
		end
	end
	if not seen[16] then slots[#slots + 1] = 16; seen[16] = true end
	for _, s in ipairs(slots) do
		local link = GetInventoryItemLink("player", s)
		if link ~= nil then wornLinks[s] = link end
	end
	return wornLinks
end

-- The reward button's item link + equip token + id. nil if the cell carries no
-- item (a currency slot, an empty button, or a client that will not answer).
local function questRewardLink(button, index)
	if type(button) ~= "table" then return nil end
	local qtype = button.type
	if qtype ~= "choice" and qtype ~= "reward" then return nil end
	if button.objectType ~= nil and button.objectType ~= "item" then return nil end
	local idx = index
	if type(button.GetID) == "function" then
		local ok, v = pcall(button.GetID, button)
		if ok and type(v) == "number" and v > 0 then idx = v end
	end
	-- The CONTEXT BRANCH (card t_769aef9b, audit finding 5). Blizzard switches
	-- the link API on the frame's own context flag, not on which frame is up --
	--   Vanilla/QuestInfo.lua:1008-1011
	--     if ( QuestInfoFrame.questLog ) then GetQuestLogItemLink(self.type, self:GetID())
	--     else                               GetQuestItemLink(self.type, self:GetID())
	-- -- and every quest-log surface sets that flag:
	--     :933  QUEST_TEMPLATE_LOG          = { questLog = true, ... }
	--     :962  QUEST_TEMPLATE_MAP_DETAILS  = { questLog = true, ... }
	--     :980  QUEST_TEMPLATE_MAP_REWARDS  = { questLog = true, ... }
	-- The addon hooks the questLog=true frames (MapQuestInfoRewardsFrame) and
	-- used to read them with the dialog-context API -- the wrong family for the
	-- frame it was reading. This is the one read site; the branch picks the
	-- FUNCTION, it does not add a second read.
	--
	-- PROVENANCE of those line numbers: the reference extracts of 1.60.1.70009
	-- and 1.60.1.70205, which agree with each other exactly. The INSTALLED
	-- client is wow_classic_beta 1.60.1.70245 (the Version row in .build.info;
	-- WowB.exe FileVersion agrees) -- one patch build NEWER than both extracts,
	-- and no extract of .70245 exists on this machine, so the LINE numbers are
	-- unverified against the build the owner plays while the
	-- BEHAVIOUR is not in question: four shipped addons on the installed build
	-- (ForeverGear/Quest.lua:60-79, GearQuestForever/Indicator.lua:1408-1413,
	-- AtlasBIStooltips' LibExtraTip, Auctionator) branch on exactly this flag
	-- and call exactly this API. /up diag's `reward context` field (AC-F) is
	-- what confirms the branch on the live client.
	--
	-- FAIL CLOSED, and this is the part that matters (AC-C). Whatever the
	-- selected API answers is the answer: nil / a throw / an empty string means
	-- the row gets NO mark. There is deliberately NO fallback to the other
	-- context's API. A link read from the wrong context can be a STALE link --
	-- an arrow on the wrong item -- which is the exact failure this fix exists
	-- to make impossible. A missing mark is acceptable; a wrong mark is not.
	--
	-- Each API is nil-guarded AND pcalled independently, so a client shipping
	-- only one of them resolves to that one or to nil, and never throws (AC-D).
	local qif = rawget(_G, "QuestInfoFrame")
	local inQuestLog = type(qif) == "table" and qif.questLog and true or false
	local readQuestRewardLink
	if inQuestLog then
		if type(GetQuestLogItemLink) ~= "function" then return nil end
		readQuestRewardLink = GetQuestLogItemLink
	else
		if type(GetQuestItemLink) ~= "function" then return nil end
		readQuestRewardLink = GetQuestItemLink
	end
	local ok, link = pcall(readQuestRewardLink, qtype, idx)
	if not ok or type(link) ~= "string" or link == "" then return nil end
	local id = itemIDOf(link)
	if type(id) ~= "number" then return nil end
	return link, equipLocation(id), id
end

-- The row's worn opponent, mirroring the bag walk's pick: for a pair slot, the
-- WEAKER worn member (via the same spec'd comparator); otherwise the row's own
-- worn slot. nil means an empty slot (a legitimate fill).
local function questWornLink(loc, invSlot, wornLinks, spec)
	local pair = PAIR_SLOTS[loc]
	if not pair then return wornLinks[invSlot] end
	local l1, l2 = wornLinks[pair[1]], wornLinks[pair[2]]
	if not l1 or not l2 then return nil end
	local v12 = Verdict.evaluate(
		{ canUse = true, line = itemLines(l1) },
		{ line = itemLines(l2) },
		spec
	)
	return (v12 == "UPGRADE") and l2 or l1
end

-- The judgement: the SAME comparator the bag walk uses, on a reward candidate.
-- Returns verdict, reason, row. Branch order matches the bag walk exactly:
-- weapon -> off-hand decline -> unresolved role/order -> armour evaluate.
--
-- The third value (card t_ed71a583) is the TOOLTIP row for this reward, built
-- from the SAME reads the verdict was decided on — the candidate's own raw
-- lines, the worn opponent it lost/won against, and its link. The tooltip
-- surface prints read numbers only, so handing it the very tables the comparator
-- parsed is what keeps the printed arithmetic and the verdict from disagreeing.
local function judgeQuestReward(link, loc, id, spec, wornLinks, offHandSpec, mainHandLoc, wornOffLoc)
	local invSlot = wornSlotFor(loc)
	local row = { link = link }
	local function done(v, reason)
		row.verdict = v
		row.reason = reason
		return v, reason, row
	end
	if not invSlot then
		return done("UNKNOWN", "out of scope: this reward is not a slot the advisor judges")
	end
	local wornLink = questWornLink(loc, invSlot, wornLinks, spec)
	row.wornLink = wornLink
	local isWeaponRow = Verdict
		and type(Verdict.WEAPON_TOKENS) == "table"
		and Verdict.WEAPON_TOKENS[loc] == true

	if isWeaponRow then
		-- Tier C path. Card t_119d120c: the reader is the ONE item reader —
		-- weapons were simply its first callers.
		local candLines = itemLines(link)
		local wornLinesR = wornLink and itemLines(wornLink) or nil
		row.lines, row.chestWornLines = candLines, wornLinesR
		local candNumbers = Verdict.weaponNumbers(candLines)
		local wornNumbers = wornLink and Verdict.weaponNumbers(wornLinesR) or nil
		local wornSlotFilled = wornLink ~= nil
		local wdecline = nil
		if type(Verdict.weaponGate) == "function" then
			wdecline = Verdict.weaponGate(loc, wornOffLoc, offHandSpec)
		end
		if wdecline ~= nil then return done("UNKNOWN", wdecline) end
		local canUseV = canUse(id)
		if canUseV ~= true then
			if canUseV == false then
				return done("UNKNOWN", "this character cannot use this weapon")
			elseif type(issecretvalue) == "function" and issecretvalue(canUseV) then
				return done("UNKNOWN", "the client returned the secret-value sentinel")
			end
			return done("UNKNOWN", "the client could not classify this weapon")
		end
		local v, reason = Verdict.compareDPS(candNumbers, wornNumbers, wornSlotFilled)
		return done(v, reason)
	end

	local offHandDecline = nil
	if Verdict and type(Verdict.offHandGate) == "function" then
		offHandDecline = Verdict.offHandGate(loc, wornOffLoc, mainHandLoc, offHandSpec)
	end
	if offHandDecline ~= nil then return done("UNKNOWN", offHandDecline) end

	local order = spec and spec.order
	if order == nil then
		local roleLabel = spec and spec.role
		if roleLabel == nil or roleLabel == "class" then
			return done("UNKNOWN", "no role resolved for this class (the client spec read gave no usable role); run /upgrade role <melee|spell>")
		end
		return done("UNKNOWN", "no stat order resolved for this character")
	end

	local canUseV = canUse(id)
	-- Card t_119d120c: the ONE item reader. A quest reward is judged on the
	-- client's structured read of the ITEM, so the quest-giver's own wardrobe
	-- chrome (and any other addon's annotation on that surface) is not an input.
	local lines = itemLines(link)
	local wornLines = wornLink and itemLines(wornLink) or nil
	row.lines, row.chestWornLines = lines, wornLines
	-- Card t_548f0341 (Defect 2): the client's own stat read, for the two
	-- sides, so a line the text parser cannot place is explained instead of
	-- silencing the row. nil (API absent / returned nothing / raised) leaves
	-- the parse byte-identical.
	--
	-- Card t_b7a9e7a5: the SAME table is stored on the row. A quest reward row
	-- carries no item ID (unlike a bag row), so the tooltip surface cannot
	-- re-derive this read from the row — and without it the disclosure would
	-- re-parse the candidate with NO API, disagreeing with the verdict it is
	-- meant to describe. Storing the exact table the verdict was decided on is
	-- the same discipline describeUpgrade already follows for its arithmetic.
	--
	-- Deliberately NOT done for bag rows: those rows are persisted into
	-- SavedVariables (ChestAdvisorDB.diag.rows; diagHistory keeps headers
	-- only — card t_6696b35a stopped saving the row tables a second time),
	-- so adding a duplicate stat table to each one would grow the player's
	-- saved data for information the bag path can already re-derive from
	-- row.id. A bag row needs no such key; this one does.
	local api = apiBySideOf(id, wornLink and itemIDOf(wornLink) or nil)
	row.api = api
	local v, reason = Verdict.evaluate(
		{ canUse = canUseV, line = lines },
		{ line = wornLines },
		spec,
		api
	)
	-- The frozen gate 6 sentinel names the chest slot; rewrite it with this
	-- row's own slot word (the same rewrite the bag walk performs).
	if reason == "no chest equipped; this item would fill the slot" then
		reason = "no " .. slotWord(invSlot) .. " equipped; this item would fill the slot"
	end
	return done(v, reason)
end

-- Clear every quest marker and every arrow texture we drew on a reward button.
-- Called at the top of each refresh AND on close (AC-E), so a closed or
-- re-rendered panel can never keep a stale arrow.
--
-- Both marks this addon draws on a reward button come off here, in ONE place:
-- the UPGRADE arrow under `button.ChestAdvisorUpgradeMarker` and the vendor
-- COIN under `button.ChestAdvisorVendorCoin` (card t_8d653c12). The button is
-- pooled by the client and outlives the quest, so a texture this addon left
-- shown is exactly the stale-mark class the arrow's own teardown note
-- describes — the coin gets the same treatment, from the same walk.
local function clearQuestMarkers()
	for _, f in pairs(questMarkerPool) do
		if type(f) == "table" then
			f:SetShown(false)
			local btn = f.__button
			if type(btn) == "table" then
				local arrow = btn.ChestAdvisorUpgradeMarker
				if type(arrow) == "table" and type(arrow.SetShown) == "function" then
					pcall(arrow.SetShown, arrow, false)
				end
				local coin = btn.ChestAdvisorVendorCoin
				if type(coin) == "table" and type(coin.SetShown) == "function" then
					pcall(coin.SetShown, coin, false)
				end
				ChestAdvisor._paintGlyph(btn, nil)
			end
			-- The frame is reused: drop the previous pass's identity so a coin
			-- frame cannot be mistaken for an arrow frame (or vice versa) by a
			-- later reader.
			f.__kind = nil
			f.__button = nil
		end
	end
	for link in pairs(questActiveMarkers) do questActiveMarkers[link] = nil end
	questMarkerNext = 0
	questCoinIndex = nil
	-- Card t_ed71a583: the tooltip rows for this reward panel go with its arrows.
	-- clearQuestMarkers runs at the TOP of every refresh AND on close (AC-E), and
	-- the refresh re-registers the rows it re-walks — so this drop can never
	-- strand a stale line, and a closed panel cannot leave one alive for an
	-- unrelated hover later.
	clearQuestTooltipRows()
end

-- The one and only allocation site for a reward-panel mark frame. Both marks
-- live in the SAME pool, `questMarkerPool` (card t_8d653c12, AC-G: the coin
-- adds no second CreateFrame pool, no second refresh path). The index is the
-- caller's: arrows count up from 1 via questMarkerNext; the coin uses slot 1,
-- which is free by the RULE itself — the coin is drawn only when NOTHING is
-- UPGRADE, so questMarkerNext is still 0 at that moment.
local function questMarkFrame(index)
	local f = questMarkerPool[index]
	if not f then
		f = CreateFrame("Frame", "ChestAdvisorQuestMark_" .. index)
		f:SetSize(24, 10)
		f:EnableMouse(false)
		questMarkerPool[index] = f
	end
	return f
end

local function makeQuestMarker(index, link, verdict, reason, roleLabel)
	local f = questMarkFrame(index)
	-- Card t_89440dfa: "arrow" for UPGRADE, "chip" for TRADE_OFF — the same two
	-- marks the bag surface draws, from the same verdict. Set from the verdict
	-- so a pooled/reused frame can never keep a stale kind.
	f.__kind = (verdict == TRADE_OFF_VERDICT) and "chip" or "arrow"
	f.__verdict = verdict
	f.__reason = reason
	f.__role = roleLabel
	f.__link = link
	return f
end

-- The coin's bookkeeping frame — from questMarkFrame's pool, not a new one.
-- f.__kind = "coin" is what tells the two marks apart for a test or a diag
-- reader (the pool slot is reused across refreshes, so a frame can be an arrow
-- on one pass and the coin on the next; the kind field is the honest label).
--
-- ⚠ Card t_89440dfa — THE POOL-SLOT COLLISION FIX. The old index was 1, on the
-- assumption that "the coin is drawn only when NOTHING is UPGRADE, so
-- questMarkerNext is still 0". That assumption is FALSE once trade-off marks
-- exist: a TRADE_OFF row draws a mark from the same walk and consumes slot 1,
-- and the coin would then reuse index 1 and OVERWRITE it — two marks, one frame.
-- The coin gets its OWN reserved slot, ABOVE the arrow cap, which no arrow or
-- trade-off mark can ever reach (they allocate 1..QUEST_MARKER_MAX). One pool,
-- still no second CreateFrame pool, still no second walk — AC-G holds.
local COIN_POOL_INDEX = QUEST_MARKER_MAX + 1
local function makeQuestCoin(link, name, sellPrice)
	local f = questMarkFrame(COIN_POOL_INDEX)
	f.__kind = "coin"
	-- No verdict and no reason: the coin is not a judgement. `__verdict` is
	-- deliberately left nil rather than filled with a word the comparator never
	-- produced — a fabricated verdict is exactly the class this project forbids.
	f.__verdict = nil
	f.__reason = nil
	f.__role = nil
	f.__link = link
	f.__coinName = name
	f.__coinPrice = sellPrice
	return f
end

-- Install the hover explanation ONCE per button. The closure reads the button's
-- own live data table, so a reused button cannot show a stale record; the guard
-- stops HookScript from stacking on repeated refreshes.
local function installQuestHover(button)
	if type(button) ~= "table" or questHookedButtons[button] then return end
	if type(button.HookScript) ~= "function" then return end
	questHookedButtons[button] = true
	button:HookScript("OnEnter", function(self)
		local d = self.__chestAdvisorQuestData
		if type(d) ~= "table" then return end
		local clientTip = GameTooltip
		local clientOwns = false
		if clientTip and type(clientTip.IsOwned) == "function" then
			local ok, owns = pcall(function() return clientTip:IsOwned(self) end)
			clientOwns = ok and owns == true
		end
		if clientOwns then return end
		local tip = getScanTip()
		if not tip then return end
		pcall(function()
			tip:SetOwner(self, "ANCHOR_RIGHT")
			tip:ClearLines()
			if type(d.link) == "string" then pcall(tip.SetHyperlink, tip, d.link) end
			-- Card t_89440dfa: the shared installer is verdict-aware, same as the
			-- bag surface (installOnEnter). U2/b (t_cf2ad83c): it also reads the
			-- SAME player-word table, so the quest hover cannot drift either.
			if d.verdict == TRADE_OFF_VERDICT then
				explainLine(tip, TOOLTIP_PREFIX .. TOOLTIP_UI.word(d.verdict)
					.. " (better on some stats, worse on others — your call)")
			elseif d.verdict == "UPGRADE" then
				explainLine(tip, TOOLTIP_PREFIX .. TOOLTIP_UI.word(d.verdict) .. " (this "
					.. tostring(d.slotWord or "slot") .. " beats what you have)")
			else
				explainLine(tip, TOOLTIP_UI.word(d.verdict)
					.. " (this " .. tostring(d.slotWord or "slot") .. ")")
			end
			-- Card t_e9a07624 (B5): the raw `role: / verdict: / reason:`
			-- debug lines are gone from the quest surface too — same leak,
			-- same removal. (The slotWord above already comes off the
			-- quest row, so B4 never reached this surface.)
			tip:Show()
		end)
	end)
	button:HookScript("OnLeave", function(self)
		self.__chestAdvisorQuestHover = nil
		local tip = getScanTip()
		if tip then tip:SetShown(false) end
	end)
end

-- Anchor the quest arrow onto the reward button, in the addon's own namespace.
local function anchorQuestMarker(f, button, link, slotWordText)
	if type(button) ~= "table" then
		f:SetShown(false)
		f.__anchorDiag = "no reward button for this cell — marker suppressed"
		return false
	end
	-- Our texture, under our own key (AC-D). Do not touch the button's own
	-- textures or scripts.
	local marker = (type(button.ChestAdvisorUpgradeMarker) == "table"
		and button.ChestAdvisorUpgradeMarker.kind == "Texture")
		and button.ChestAdvisorUpgradeMarker or nil
	if marker and marker ~= f.__arrow then
		pcall(marker.SetShown, marker, false)
	end
	-- Card t_89440dfa: the quest surface carries the SAME two marks as the bag —
	-- the green arrow for UPGRADE and the amber chip for TRADE_OFF. Verdict is
	-- re-asserted every anchor for the same reason as anchorMarker (a pooled
	-- reward button can change verdict between refreshes).
	local isTradeOff = (f.__verdict == TRADE_OFF_VERDICT)
	if not marker then
		marker = button:CreateTexture(nil, "OVERLAY", nil, 7)
	end
	-- Same reuse bug as the bag marker: clear the previous anchor before the
	-- arrow and the chip set different points on one texture.
	if type(marker.ClearAllPoints) == "function" then
		pcall(marker.ClearAllPoints, marker)
	end
	if isTradeOff then
		if type(marker.SetColorTexture) == "function" then
			marker:SetColorTexture(TRADEOFF_R, TRADEOFF_G, TRADEOFF_B, TRADEOFF_A)
		end
		marker:SetSize(TRADEOFF_SIZE, TRADEOFF_SIZE)
		marker:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
	else
		if type(marker.SetTexture) == "function" then
			marker:SetTexture(QUEST_ARROW_TEXTURE)
		end
		marker:SetSize(QUEST_ARROW_SIZE, QUEST_ARROW_SIZE)
		marker:SetPoint("TOPRIGHT", button, "TOPRIGHT", 1, 1)
	end
	button.ChestAdvisorUpgradeMarker = marker
	f.__arrow = marker
	f.__button = button
	button.__chestAdvisorQuestData = {
		link = link, verdict = f.__verdict, reason = f.__reason, role = f.__role,
		slotWord = slotWordText,
	}
	installQuestHover(button)
	if type(marker.SetShown) == "function" then
		pcall(marker.SetShown, marker, true)
	end
	ChestAdvisor._paintGlyph(button, isTradeOff and "tradeoff" or "upgrade", marker)
	f:SetShown(true)
	questActiveMarkers[link] = true
	f.__anchorDiag = "anchored to reward button"
	return true
end

-- Anchor the vendor COIN onto the reward button (card t_8d653c12). Same
-- discipline as anchorQuestMarker — a texture under the addon's OWN namespace
-- key on the button, the client's handlers untouched — because the coin is the
-- arrow's sibling on the same surface and must obey the same rules. It differs
-- in exactly three ways, all deliberate:
--
--   * its own key, `button.ChestAdvisorVendorCoin`, so the arrow and the coin
--     can never read, hide or re-point each other's texture;
--   * its own texture and geometry — the built-in money icon, 16x16, at
--     BOTTOMRIGHT so it does not sit on the arrow's TOPRIGHT corner and the two
--     marks are distinguishable by POSITION as well as by image;
--   * it writes NO hover row and NO tooltip verdict. The coin is a value hint,
--     not a judgement — there is no reason to explain and nothing to explain.
--     (Silence is the honest answer here: the panel already tells the player the
--     item is not an upgrade by NOT showing an arrow.)
local function anchorQuestCoin(f, button, link)
	if type(button) ~= "table" then
		f:SetShown(false)
		f.__anchorDiag = "no reward button for this cell — coin suppressed"
		return false
	end
	local coin = (type(button.ChestAdvisorVendorCoin) == "table"
		and button.ChestAdvisorVendorCoin.kind == "Texture")
		and button.ChestAdvisorVendorCoin or nil
	if coin and coin ~= f.__coin then
		pcall(coin.SetShown, coin, false)
	end
	if not coin then
		coin = button:CreateTexture(nil, "OVERLAY", nil, 6)
		coin:SetTexture(COIN_TEXTURE)
		coin:SetSize(COIN_SIZE, COIN_SIZE)
		coin:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
	end
	button.ChestAdvisorVendorCoin = coin
	f.__coin = coin
	f.__button = button
	if type(coin.SetShown) == "function" then
		pcall(coin.SetShown, coin, true)
	end
	f:SetShown(true)
	-- NOT registered in questActiveMarkers: that map is the ARROW census
	-- ("markers shown" / "upgrades marked" in the diag), and a coin counted
	-- there would report one marker with zero upgrades — a contradiction a
	-- reader would trip on. The coin's own presence is questCoinIndex.
	f.__anchorDiag = "anchored to reward button"
	return true
end

-- One full pass. Clears, gates on visibility, reads the swapped rewards frame,
-- walks its RewardButtons, and draws an arrow for each UPGRADE — plus, when the
-- whole set has NO upgrade, the vendor-value coin (card t_8d653c12). One walk,
-- one pass: the coin is decided from the SAME rows the arrows were judged on.
local function refreshQuestMarkers()
	clearQuestMarkers()
	questWalked, questUpgrades, questTradeoffs, questNoMark = 0, 0, 0, 0
	questCoinCandidates = 0
	-- AC-F: nothing is created while the reward UI is not showing.
	if not questRewardUIshown() then return false end
	local rewardsFrame = questRewardsFrame()
	if type(rewardsFrame) ~= "table" then return false end
	local buttons = rewardsFrame.RewardButtons
	if type(buttons) ~= "table" then return false end

	local spec = buildSpec()
	local wornLinks = readWornLinks()
	local offHandSpec, mainHandLoc, wornOffLoc = nil, nil, nil
	if Verdict and type(Verdict.offHandGate) == "function" then
		offHandSpec = readOffHandSpec()
		local ml = wornLinks[16]
		if ml then mainHandLoc = equipLocation(itemIDOf(ml)) end
		local ol = wornLinks[17]
		if ol then wornOffLoc = equipLocation(itemIDOf(ol)) end
	end

	-- Deterministic walk order (RewardButtons is a Lua table; pairs() is not
	-- ordered). The index is the button's own array key.
	local order = {}
	for i in pairs(buttons) do
		if type(i) == "number" then order[#order + 1] = i end
	end
	table.sort(order)

	-- The vendor-value fallback (card t_8d653c12). The rule needs the WHOLE set
	-- before it can act ("if and only if NO row is UPGRADE"), so this walk only
	-- COLLECTS the best-sell candidate; the coin is drawn once, after the walk,
	-- and only when questUpgrades is still 0. Accumulating here is what keeps
	-- this ONE walk — no second pass over the buttons.
	--
	-- Only a CHOICE row may earn the coin (the card's word). A fixed reward is
	-- not a decision the player makes, so marking one with "take this for the
	-- gold" would point at something he cannot choose.
	--
	-- The comparison is strictly greater (`>`): on a tie the FIRST row in this
	-- sorted order keeps the coin — the card's "break ties by reward index".
	local coinBest = nil      -- { index, button, link, name, price }

	for _, i in ipairs(order) do
		local button = buttons[i]
		if type(button) == "table" then
			questWalked = questWalked + 1
			local link, loc, id = questRewardLink(button, i)
			if link and id then
				local v, reason, qrow = judgeQuestReward(
					link, loc, id, spec, wornLinks, offHandSpec, mainHandLoc, wornOffLoc)
				-- Tooltip surface (card t_ed71a583): register the same row the
				-- verdict was decided on, so a hover on this reward shows the
				-- same answer and the same read numbers. The link is the key the
				-- tooltip looks up; clearQuestMarkers drops it again.
				if type(qrow) == "table" then questTooltipRows[link] = qrow end
				-- Store the row on the button for hover/diag (harmless on a
				-- non-upgrade row: the marker is only created on UPGRADE).
				button.__chestAdvisorQuestVerdict = v
				-- Card t_89440dfa: BOTH marks ride this ONE branch — the green
				-- arrow for UPGRADE and the amber chip for TRADE_OFF. The count
				-- that gates the coin stays the UPGRADE count only (ruling: the
				-- coin's rule is "no row is UPGRADE", a trade-off does not block
				-- it); trade-offs get their own counter for the diag.
				if v == "UPGRADE" or v == TRADE_OFF_VERDICT then
					if questMarkerNext < QUEST_MARKER_MAX then
						questMarkerNext = questMarkerNext + 1
						local f = makeQuestMarker(questMarkerNext, link, v, reason,
							spec and spec.role or "class")
						anchorQuestMarker(f, button, link, slotWord(wornSlotFor(loc)))
						if v == "UPGRADE" then
							questUpgrades = questUpgrades + 1
						else
							questTradeoffs = questTradeoffs + 1
						end
					end
				else
					questNoMark = questNoMark + 1
				end
				-- The coin candidate: a CHOICE row whose sell price the client
				-- actually returned. Read through itemNameOf — the SAME single
				-- C_Item.GetItemInfo call the name comes from, so the price and
				-- the name can never be two different items' answers.
				--
				-- ⚠ Note what is NOT checked here: eligibility. canUse() is
				-- deliberately absent — an item the character cannot wear can
				-- still be the most valuable thing on the panel, and selling it
				-- is a legitimate choice. Routing this through the arrow's
				-- eligibility gate would silently disable the coin for exactly
				-- the panel the feature exists for. (AC-C.)
				--
				-- ⚠ Card t_89440dfa, ruling point 3: a TRADE_OFF row is NOT a
				-- coin candidate. If a trade-off mark and the coin ever wanted
				-- the same row, the trade-off mark wins — the verdict outranks
				-- the money hint. Excluding it here is that rule, in one place.
				if button.type == "choice" and v ~= TRADE_OFF_VERDICT then
					local _name, price = itemNameOf(link)
					if type(price) == "number" then
						questCoinCandidates = questCoinCandidates + 1
						if coinBest == nil or price > coinBest.price then
							coinBest = { index = i, button = button, link = link,
							             name = _name, price = price }
						end
					end
				end
			else
				questNoMark = questNoMark + 1
			end
		end
	end

	-- The fallback, evaluated once for the whole set: no upgrade anywhere means
	-- the remaining decision is money, so mark the single best-selling choice.
	-- A nil coinBest (no row reported a price) means NO coin — the card's own
	-- rule; a panel whose prices the client has not cached gets silence, never a
	-- guess at which row is "probably" worth most.
	if questUpgrades == 0 and coinBest ~= nil then
		local f = makeQuestCoin(coinBest.link, coinBest.name, coinBest.price)
		anchorQuestCoin(f, coinBest.button, coinBest.link)
		questCoinIndex = coinBest.index
	end

	questRefreshed = questRefreshed + 1
	return true
end

local function scheduleQuestRefresh(delay)
	questRefreshGen = questRefreshGen + 1
	local myGen = questRefreshGen
	if C_Timer and C_Timer.After then
		C_Timer.After(delay or 0, function()
			if myGen ~= questRefreshGen then return end
			refreshQuestMarkers()
		end)
	else
		refreshQuestMarkers()
	end
end

-- Hook OUR behaviour onto Blizzard's frame with HookScript (never SetScript) and
-- onto its own renderer with hooksecurefunc, so the client's handlers still run.
local function hookQuestFrame(frame)
	if type(frame) ~= "table" then return end
	if questHookedFrames[frame] then return end
	if type(frame.HookScript) ~= "function" then return end
	questHookedFrames[frame] = true
	frame:HookScript("OnShow", function() scheduleQuestRefresh(0.05) end)
	frame:HookScript("OnHide", function() clearQuestMarkers() end)
end

local function installQuestHooks()
	hookQuestFrame(questRewardsFrame())
	hookQuestFrame(rawget(_G, "QuestInfoRewardsFrame"))
	hookQuestFrame(rawget(_G, "MapQuestInfoRewardsFrame"))
	hookQuestFrame(rawget(_G, "QuestFrameRewardPanel"))
	if not questHookedShowRewards and type(QuestInfo_ShowRewards) == "function" then
		hooksecurefunc("QuestInfo_ShowRewards", function()
			installQuestHooks()
			scheduleQuestRefresh(0.05)
		end)
		questHookedShowRewards = true
	end
	if not questHookedDisplay and type(QuestInfo_Display) == "function" then
		hooksecurefunc("QuestInfo_Display", function()
			installQuestHooks()
			scheduleQuestRefresh(0.05)
		end)
		questHookedDisplay = true
	end
end

-- A small event frame for the quest lifecycle. Registering an event the client
-- does not know raises client-side (see the PLAYER_EQUIPMENT_UPDATE note at the
-- top of this file), so only names verified in the client source are used:
-- QUEST_DETAIL/QUEST_COMPLETE/QUEST_ITEM_UPDATE/QUEST_FINISHED are exactly the
-- names ForeverGear's own shipped Quest.lua registers on this client
-- (_classic_beta_/Interface/AddOns/ForeverGear/Quest.lua:257-265).
local questEventFrame
local function getQuestEventFrame()
	if not questEventFrame then
		if UIParent then
			questEventFrame = CreateFrame("Frame", "ChestAdvisor_QuestFrame")
		else
			questEventFrame = CreateFrame("Frame")
		end
		questEventFrame:RegisterEvent("QUEST_DETAIL")
		questEventFrame:RegisterEvent("QUEST_COMPLETE")
		questEventFrame:RegisterEvent("QUEST_ITEM_UPDATE")
		questEventFrame:RegisterEvent("QUEST_FINISHED")
		questEventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
		questEventFrame:SetScript("OnEvent", function(self, ev)
			if ev == "QUEST_FINISHED" then
				clearQuestMarkers()
				return
			end
			installQuestHooks()
			scheduleQuestRefresh(0.05)
		end)
	end
	return questEventFrame
end

-- Install at load time, then again on every quest event (the rewards frame is
-- created lazily, so a hook that missed it at load is re-attempted).
installQuestHooks()
getQuestEventFrame()

-- Test + diag access (read-only snapshot).
-- questRewardContext (card t_769aef9b, AC-F) reports WHICH context flag selected
-- the link API and WHICH API that flag resolves to on THIS client. It exists so
-- the next live login can answer STEP 1 of this card's own acceptance run
-- without a special build: open the quest-log/map reward panel, type /up diag,
-- and read these two fields. It is a type() read of two globals plus the frame
-- flag -- read-only, no writes, no protected calls (AC-F).
ChestAdvisor.questRewardContext = function()
	local qif = rawget(_G, "QuestInfoFrame")
	local inQuestLog = type(qif) == "table" and qif.questLog and true or false
	-- ⚠ The selection MUST mirror the read site exactly. Do NOT fold this into a
	-- single `cond and A or B` expression: when the flag is TRUE and the
	-- quest-log API is ABSENT, `true and nil or GetQuestItemLink` evaluates to
	-- GetQuestItemLink — so the diagnostic would report the presence of the
	-- function it did NOT select, i.e. a false "present" on the exact
	-- fail-closed case the reader is asking about.
	local selected, selectedName
	if inQuestLog then
		selected, selectedName = GetQuestLogItemLink, "GetQuestLogItemLink"
	else
		selected, selectedName = GetQuestItemLink, "GetQuestItemLink"
	end
	return {
		questLog = inQuestLog,               -- the flag Blizzard switches on
		api = selectedName,                  -- the API that flag selects here
		apiPresent = type(selected) == "function",
		-- Both halves, so a reader can see the pair rather than one side.
		-- (The one-letter neighbour GetQuestLogItemInfo is ABSENT on this
		-- client and is deliberately not read — audit brief.)
		dialogApiPresent = type(GetQuestItemLink) == "function",
		questLogApiPresent = type(GetQuestLogItemLink) == "function",
	}
end

ChestAdvisor.questState = function()
	local shown = 0
	for _ in pairs(questActiveMarkers) do shown = shown + 1 end
	return {
		shown = shown,
		refreshed = questRefreshed,
		walked = questWalked,
		upgrades = questUpgrades,
		-- Card t_89440dfa: the third outcome's own count, beside the arrow count
		-- it is often confused with. A reader asking "why two marks?" needs both.
		tradeoffs = questTradeoffs,
		noMark = questNoMark,
		visible = questRewardUIshown(),
		-- Card t_8d653c12: the vendor coin's own state, reported alongside the
		-- arrows it shares a surface with.
		coin = questCoinIndex,            -- the reward index the coin is on, or nil
		coinCandidates = questCoinCandidates,  -- priced CHOICE rows this refresh
	}
end
ChestAdvisor.refreshQuestMarkers = refreshQuestMarkers
ChestAdvisor.clearQuestMarkers = clearQuestMarkers
ChestAdvisor._installQuestHooks = installQuestHooks
ChestAdvisor._judgeQuestReward = judgeQuestReward
ChestAdvisor._readWornLinks = readWornLinks
end
-- Fold (MightiePack Touchstone module): the quest surface owns
-- ChestAdvisor_QuestFrame and the reward hooks; Enable() installs it.
ChestAdvisor._initQuestSurface = initQuestSurface
end


-- ---- U4 + U5 (card t_c01331a2): the verdict where the player is looking ------
--
-- TWO ADDITIONAL SURFACES, ONE RULE. The advisor already knows which bag items are
-- upgrades, but today that answer is only visible on a bag hover. U4 puts a small
-- arrow on the CHARACTER PANE slot that has an UPGRADE waiting in the bags ("which
-- slot is the upgrade for?", without opening a bag). That arrow does NOT mean the
-- equipped item is an upgrade — the equipped item's tooltip is left alone. It means
-- a bag item is a current upgrade for that slot, judged against what is worn now.
-- U5 puts the same arrow on a VENDOR line whose item is an UPGRADE ("is any of this vendor trash an upgrade?",
-- without hovering each line).
--
-- NEITHER SURFACE JUDGES. Both read the SAME verdict set the bag marker reads — U4
-- from the scan's own record (ChestAdvisor.__verdicts, keyed by link), U5 by
-- calling the SAME judge the quest-reward walk already calls (judgeQuestReward,
-- which is link-generic by construction). No second comparator, no stat order, no
-- token set, no second eligibility read: every verdict still comes from
-- Verdict.evaluate / weaponGate+compareDPS / offHandGate, exactly as the bag walk
-- obtains it.
--
-- NO NEW ART (the card's own constraint): both marks are the EXISTING marker.tga
-- arrow, at the existing 18x18 geometry, drawn as a texture under the addon's OWN
-- namespace key on a button the client already created — the shape anchorQuestMarker
-- established for the reward buttons.
--
-- ⚠ WHY THERE IS NO POOL, AND NO HOVER, ON EITHER SURFACE.
--
--   * No pool. These surfaces were added while this chunk sat on Lua 5.1's
--     200-local ceiling, so a third frame pool was not affordable — and it is
--     not needed. The mark lives ON THE BUTTON
--     (button.ChestAdvisorPaperDollHint / button.ChestAdvisorVendorMark), created
--     once per button and thereafter only shown/hidden: there is no frame to leak
--     and no pool index to collide with the bag or reward marks.
--
--   * No hover. U5 forbids adding a tooltip, and neither surface needs one to answer
--     its question. The merchant button keeps the client's own
--     GameTooltip:SetMerchantItem (MerchantFrame.lua:MerchantItemButton_OnEnter) and
--     the paper-doll slot keeps the client's own item tooltip; we write NO addon data
--     table and install NO hover hook on either button. That makes the ghost-hover
--     class (card t_e9a07624) unreachable BY CONSTRUCTION rather than by cleanup —
--     but the cleanup is still asserted on the bytes rather than assumed (see
--     ChestAdvisor/tests/t_c01331a2.js, AC-E).
--
-- ⚠ LIFECYCLE (AC-E) — the part a naive version gets wrong. The client POOLS both
-- surfaces' buttons, so a texture we showed OUTLIVES the item it was drawn for:
--
--   * U4: the hint is recomputed from the CURRENT verdict set on every scan and on
--     the pane's OnShow. A slot with no UPGRADE row is actively HIDDEN by the same
--     walk, so "the best item for this slot is NOT_UPGRADE / TRADE_OFF / UNKNOWN"
--     cannot keep an arrow standing (AC-B's three negatives).
--
--   * U5: the vendor refresh CLEARS every mark FIRST and only then re-anchors, so a
--     re-render (MERCHANT_UPDATE) can never leave a stale arrow; MerchantFrame's own
--     OnHide and the MERCHANT_CLOSED event both clear; and no addon field or hook is
--     left on any merchant button for a later hover to read.
--
-- THE BUTTON NAMES ARE CLIENT FACTS, NOT GUESSES. U4's map is the ONE the reference
-- addon ships on the INSTALLED client (ForeverGear/Character.lua:13-31, read from
-- _classic_beta_/Interface/AddOns/ForeverGear/Character.lua) and it agrees with the
-- client's own Camelot/PaperDollFrame.xml slot names (CharacterHeadSlot …
-- CharacterRangedSlot). U5's is the pattern the client itself uses to reach its item
-- buttons on BOTH merchant variants — Mainline/MerchantFrame.lua:280 and
-- Vanilla/MerchantFrame.lua:198 both read _G["MerchantItem"..i.."ItemButton"], and
-- both create that button as a CHILD of MerchantItem<i> (MerchantFrame.xml's
-- MerchantItemTemplate). Reading the same name the client reads is what makes this
-- correct on either variant without having to settle which one loads.
--
-- The INVSLOT indices here are the client's own (Blizzard_FrameXMLBase/Constants.lua:
-- 136-154, INVSLOT_HEAD=1 … INVSLOT_RANGED=18).
ChestAdvisor.paperDollButtons = {
	[1]  = "CharacterHeadSlot",
	[2]  = "CharacterNeckSlot",
	[3]  = "CharacterShoulderSlot",
	[4]  = "CharacterShirtSlot",
	[5]  = "CharacterChestSlot",
	[6]  = "CharacterWaistSlot",
	[7]  = "CharacterLegsSlot",
	[8]  = "CharacterFeetSlot",
	[9]  = "CharacterWristSlot",
	[10] = "CharacterHandsSlot",
	[11] = "CharacterFinger0Slot",
	[12] = "CharacterFinger1Slot",
	[13] = "CharacterTrinket0Slot",
	[14] = "CharacterTrinket1Slot",
	[15] = "CharacterBackSlot",
	[16] = "CharacterMainHandSlot",
	[17] = "CharacterSecondaryHandSlot",
	[18] = "CharacterRangedSlot",
}

-- The vendor item-button for page index i, read by the SAME name the client's own
-- MerchantFrame_UpdateMerchantInfo reads. One place, so the refresh and the clear
-- walk cannot drift apart.
ChestAdvisor.vendorButtonName = function(i)
	return "MerchantItem" .. tostring(i) .. "ItemButton"
end

-- ---- U4 — the character-pane hint -------------------------------------------
--
-- The hint for a worn slot is `_G[<slot button name>].ChestAdvisorPaperDollHint`,
-- our own namespace key. Created once, then shown/hidden only.
--
-- THE SET EQUALITY THIS MUST HOLD (AC-C): the set of SLOTTED arrows equals the set
-- of invSlots carrying at least one row whose verdict is UPGRADE. It holds by
-- construction — the walk below computes exactly that predicate and nothing else —
-- and the suite asserts it as a set, not as a count.
--
-- WHERE THE ARROW SITS ON A PAIR. A finger/trinket candidate's row carries the ONE
-- invSlot the scan mapped it to (EQUIP_SLOTS[loc] — 11 for a ring, 13 for a trinket;
-- the pair's first member). Marking only that member is deliberate: the verdict is
-- "beats the WEAKER of the pair", so it is a statement about the PAIR, and marking
-- both members would put two arrows on one verdict. Marking the recorded invSlot
-- keeps AC-C's set equality exact.
--
-- WHICH ITEM WHEN SEVERAL QUALIFY. Only one arrow can exist per slot, so "which" is
-- not visible — but the winning link IS recorded on the button
-- (button.__chestAdvisorPaperDollLink) for a test or a /up diag to read. The winner
-- is chosen deterministically: the qualifying links are sorted (pairs() order is
-- not an order), then folded with the FROZEN comparator answering "does B beat A?"
-- the same way the bag walk already asks it to pick the weaker of a finger/trinket
-- pair. A tie (or an incomparable pair) keeps the incumbent — the first in sorted
-- order. No numeric weight is invented and no verdict changes: both rows are
-- UPGRADE either way.
local function refreshPaperDollHints()
	local rows = ChestAdvisor.__verdicts or {}
	local buttons = ChestAdvisor.paperDollButtons
	local pane = rawget(_G, "PaperDollFrame")
	if not frameIsShown(pane) then pane = rawget(_G, "CharacterFrame") end
	local visible = frameIsShown(pane)

	-- What is worn RIGHT NOW. A verdict computed when GetInventoryItemLink was
	-- still nil (login, before the equipment cache) says "empty slot" and would
	-- keep an arrow on a slot that has since filled — including the item the
	-- player just equipped. Re-read here so the mark tracks the current gear.
	local wornNow = {}
	if visible and type(GetInventoryItemLink) == "function" then
		for slot = 1, 18 do
			local okL, w = pcall(GetInventoryItemLink, "player", slot)
			if okL and type(w) == "string" then wornNow[slot] = w end
		end
	end

	-- The qualifying links, sorted, so the fold below is deterministic.
	local links = {}
	if visible then
		for link, row in pairs(rows) do
			if type(row) == "table" and row.verdict == "UPGRADE"
				and type(row.invSlot) == "number" then
				local worn = wornNow[row.invSlot]
				-- The equipped item is not an upgrade for the slot it fills.
				-- A row judged against a different item (or against empty, once
				-- the slot is filled) is stale; the OnShow rescan replaces it.
				local stale = (link == worn)
					or (row.wornLink == nil and worn ~= nil)
					or (type(row.wornLink) == "string" and type(worn) == "string"
						and row.wornLink ~= worn)
				if not stale then
					links[#links + 1] = link
				end
			end
		end
		table.sort(links)
	end

	-- The strongest qualifying row per slot (see the note above). Each entry carries
	-- the LINK explicitly: the bag walk's verdict rows are keyed BY link and do not
	-- carry a `.link` field (unlike the quest surface's rows, which do), so the map
	-- key is the only place the link exists here.
	local spec = visible and buildSpec() or nil
	local best = {}
	for _, link in ipairs(links) do
		local row = rows[link]
		local slot = row.invSlot
		local cur = best[slot]
		if cur == nil then
			best[slot] = { link = link, row = row }
		else
			-- Strict dominance only; on a tie or an incomparable pair the incumbent
			-- (earlier in sorted order) is kept. `beats(x, y)` is the frozen
			-- comparator's own answer to "does x beat y?", never a new judgement.
			local function beats(x, y)
				if type(x.lines) ~= "table" then return false end
				local ok, v = pcall(Verdict.evaluate,
					{ canUse = true, line = x.lines }, { line = y.lines }, spec or {})
				return ok and v == "UPGRADE"
			end
			if beats(row, cur.row) and not beats(cur.row, row) then
				best[slot] = { link = link, row = row }
			end
		end
	end

	-- One arrow per worn slot, shown iff that slot has a qualifying row. A slot the
	-- client does not expose right now is skipped silently — never an invented
	-- screen position (the same rule anchorMarker follows for bag cells).
	--
	-- The texture is created ONLY for a slot that actually qualifies, so a slot with
	-- no upgrade carries no hint object at all (AC-B's negatives read `none`, not a
	-- hidden texture that merely happens to be invisible). Once created it is pooled
	-- on the button and thereafter only shown/hidden — the same lifecycle the bag
	-- marker's own texture has.
	local shown = 0
	for slot = 1, 18 do
		local name = buttons[slot]
		local btn = name and rawget(_G, name)
		if type(btn) == "table" and type(btn.CreateTexture) == "function" then
			local picked = best[slot]
			local hint = btn.ChestAdvisorPaperDollHint
			if picked ~= nil and type(hint) ~= "table" then
				-- pcall'd deliberately. The bag marker's CreateTexture is NOT guarded —
				-- the suite's AC20 render-path case relies on that raise aborting the
				-- walk. This surface is ADDITIVE, so a texture-subsystem failure here
				-- must not be able to take the bag scan down with it: on failure the
				-- slot is simply skipped, exactly as a client without the button would
				-- be.
				local ok, tex = pcall(btn.CreateTexture, btn, nil, "OVERLAY", nil, 7)
				if ok and type(tex) == "table" then
					if type(tex.SetTexture) == "function" then
						tex:SetTexture(QUEST_ARROW_TEXTURE)
					end
					tex:SetSize(QUEST_ARROW_SIZE, QUEST_ARROW_SIZE)
					tex:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 1, 1)
					btn.ChestAdvisorPaperDollHint = tex
					hint = tex
				end
			end
			if type(hint) == "table" then
				if type(hint.SetShown) == "function" then
					pcall(hint.SetShown, hint, picked ~= nil)
				end
				if picked ~= nil then
					ChestAdvisor._paintGlyph(btn, "upgrade", hint)
				else
					ChestAdvisor._paintGlyph(btn, nil)
				end
				-- The winning link, or nil — the ONE addon DATA field written on a
				-- slot button, overwritten on every refresh and dropped when the slot
				-- stops qualifying. Nothing the client's own scripts read, and nothing
				-- a hover hook looks at (no hover hook is installed on this surface).
				btn.__chestAdvisorPaperDollLink = picked and picked.link or nil
				if picked ~= nil then shown = shown + 1 end
			end
		end
	end
	ChestAdvisor.paperDollShown = shown
	return visible
end
ChestAdvisor.refreshPaperDollHints = refreshPaperDollHints

-- Test + diag access (read-only): how many arrows are up, and against which links.
ChestAdvisor.paperDollState = function()
	local links = {}
	local buttons = ChestAdvisor.paperDollButtons
	for slot = 1, 18 do
		local name = buttons[slot]
		local btn = name and rawget(_G, name)
		local hint = type(btn) == "table" and btn.ChestAdvisorPaperDollHint or nil
		if type(hint) == "table" and hint.shown then
			links[#links + 1] = btn.__chestAdvisorPaperDollLink
		end
	end
	return {
		shown = #links,               -- arrows currently up
		links = links,                -- the link each one stands for
		slots = (function()
			local n = 0
			for _ in pairs(buttons) do n = n + 1 end
			return n
		end)(),
	}
end

-- Hook the character pane's own visibility. HookScript (never SetScript), one hook
-- per frame, and re-runnable — the pane can be created lazily, so a hook that missed
-- it at load is re-attempted on every scan event (the installQuestHooks shape).
ChestAdvisor.paperDollHooked = {}
ChestAdvisor._installPaperDollHooks = function()
	local function hook(frame)
		if type(frame) ~= "table" then return end
		if ChestAdvisor.paperDollHooked[frame] then return end
		if type(frame.HookScript) ~= "function" then return end
		ChestAdvisor.paperDollHooked[frame] = true
		frame:HookScript("OnShow", function()
			ChestAdvisor._schedulePaperDollRefresh(0.05)
		end)
		-- OnHide clears rather than merely hiding: a closed pane must not keep an
		-- arrow that the next open would show against a slot whose item has since
		-- left the bags. This is the AC-E "clear on close" half for U4.
		frame:HookScript("OnHide", function()
			for slot = 1, 18 do
				local name = ChestAdvisor.paperDollButtons[slot]
				local btn = name and rawget(_G, name)
				local hint = type(btn) == "table" and btn.ChestAdvisorPaperDollHint or nil
				if type(hint) == "table" and type(hint.SetShown) == "function" then
					pcall(hint.SetShown, hint, false)
				end
				-- Drop the recorded link with the arrow, so a reader cannot see a slot
				-- still claiming an item while its arrow is down. (There is no hover hook
				-- on this surface to disarm — none is ever installed.)
				if type(btn) == "table" then
					btn.__chestAdvisorPaperDollLink = nil
					ChestAdvisor._paintGlyph(btn, nil)
				end
			end
		end)
	end
	hook(rawget(_G, "PaperDollFrame"))
	hook(rawget(_G, "CharacterFrame"))
end

-- Defer one tick so the client has finished its own bookkeeping, with a generation
-- token so a burst of events collapses into the last one (the scheduleQuestRefresh
-- shape).
ChestAdvisor.paperDollGen = 0
ChestAdvisor._schedulePaperDollRefresh = function(delay)
	ChestAdvisor.paperDollGen = (ChestAdvisor.paperDollGen or 0) + 1
	local myGen = ChestAdvisor.paperDollGen
	local function pass()
		if myGen ~= ChestAdvisor.paperDollGen then return end
		-- Rescan, don't just repaint. Opening the character sheet is the moment
		-- the equipment links are readable; a login scan that saw empty slots
		-- would otherwise leave its arrows up after /reload.
		if type(ChestAdvisor.scan) == "function" then
			ChestAdvisor.scan()
		else
			ChestAdvisor.refreshPaperDollHints()
		end
	end
	if C_Timer and type(C_Timer.After) == "function" then
		C_Timer.After(delay or 0, pass)
	else
		pass()
	end
end

-- ---- U5 — the vendor mark ---------------------------------------------------
--
-- The mark for a merchant line is `_G["MerchantItem"..i.."ItemButton"]
-- .ChestAdvisorVendorMark`, our own namespace key, created once per button.
--
-- WHAT IS MARKED, AND WHAT IS NOT. Only a row the comparator returns `UPGRADE` for.
-- A TRADE_OFF is deliberately NOT marked (AC-F): a trade-off is the player's call,
-- and the audit's ruling keeps it out of an impulse buy at a vendor. Nothing else
-- is gated on: not affordability (AC: no affordability check), not the client's
-- `isUsable` flag, not eligibility as a *display* gate — the same discipline the
-- quest coin follows. `judgeQuestReward` still applies the comparator's own hard
-- eligibility gate, so an unusable item returns UNKNOWN and draws no mark.
--
-- The buyback tab (MerchantFrame.selectedTab == 2) reuses the SAME button names for
-- buyback lines (Vanilla/MerchantFrame.lua:MerchantFrame_UpdateBuybackInfo), so the
-- refresh steps aside entirely on that tab rather than marking an item the player
-- already sold.
ChestAdvisor.vendorTabIndex = 1
ChestAdvisor.vendorWalked = 0

-- Put every vendor mark away, on the buttons the client owns. The ONE teardown
-- point, called by the refresh (before it re-anchors), by the merchant close, and by
-- the frame's own OnHide — so all three of AC-E's cases share one implementation.
-- The pcall matches the file's own teardown guard style (clearMarkers,
-- clearQuestMarkers): a client that has already destroyed the texture cannot abort
-- the clear walk.
ChestAdvisor._clearVendorMarks = function()
	for i = 1, 12 do
		local btn = rawget(_G, ChestAdvisor.vendorButtonName(i))
		if type(btn) == "table" then
			local mark = btn.ChestAdvisorVendorMark
			if type(mark) == "table" and type(mark.SetShown) == "function" then
				pcall(mark.SetShown, mark, false)
			end
			ChestAdvisor._paintGlyph(btn, nil)
			-- Drop the addon's own record with the mark, so a later reader (or a
			-- later hover) cannot see a mark that is no longer drawn. There is no
			-- hover hook to disarm because none is ever installed.
			btn.__chestAdvisorVendorMarked = nil
		end
	end
end

-- Same function objects the quest surface just published. Bound once,
-- so the vendor walk calls the quest walk's judge rather than a copy.
-- Fold (load order): these are published by Enable(); capture them at
-- call time so a disabled-then-enabled module cannot leave nil behind.
local function readWornLinks(...)
	local f = ChestAdvisor._readWornLinks
	if type(f) == "function" then return f(...) end
end
local function judgeQuestReward(...)
	local f = ChestAdvisor._judgeQuestReward
	if type(f) == "function" then return f(...) end
end

local function refreshVendorMarkers()
	-- Clear FIRST: this refresh is the only author of a vendor mark, so clearing
	-- here is what makes MERCHANT_UPDATE's re-render — and a re-render onto a
	-- shorter item list — leave nothing stale behind (AC-E).
	ChestAdvisor._clearVendorMarks()
	ChestAdvisor.vendorWalked = 0

	local frame = rawget(_G, "MerchantFrame")
	-- AC-F: nothing is drawn while the merchant UI is not showing. A nil frame (the
	-- client did not create it) reads as "not showing", not as an error.
	if not frameIsShown(frame) then return false end
	-- The buyback tab reuses the same buttons for sold items; step aside. A frame
	-- that does not expose selectedTab (a variant that stores it elsewhere) is
	-- treated as the merchant tab, which is the tab the feature is for.
	if frame.selectedTab ~= nil and frame.selectedTab ~= ChestAdvisor.vendorTabIndex then
		return false
	end

	local getCount = rawget(_G, "GetMerchantNumItems")
	local getLink  = rawget(_G, "GetMerchantItemLink")
	if type(getCount) ~= "function" or type(getLink) ~= "function" then return false end
	local okCount, num = pcall(getCount)
	if not okCount or type(num) ~= "number" then
		ChestAdvisor.vendorWalked = 0
		return false
	end

	-- The judgement context, read ONCE per refresh and never cached across one — the
	-- same "a spec change must be picked up by the next refresh" rule the quest and
	-- bag surfaces follow, and the same reads they make.
	local spec = buildSpec()
	local wornLinks = readWornLinks()
	local offHandSpec, mainHandLoc, wornOffLoc = nil, nil, nil
	if Verdict and type(Verdict.offHandGate) == "function" then
		offHandSpec = readOffHandSpec()
		local ml = wornLinks[16]
		if ml then mainHandLoc = equipLocation(itemIDOf(ml)) end
		local ol = wornLinks[17]
		if ol then wornOffLoc = equipLocation(itemIDOf(ol)) end
	end

	local shown = 0
	for i = 1, math.min(num, 12) do
		local btn = rawget(_G, ChestAdvisor.vendorButtonName(i))
		-- Only a line that actually carries an item: the client sets `hasItem` on a
		-- filled row and clears it (with a Hide) on an empty one.
		if type(btn) == "table" and btn.hasItem and type(btn.CreateTexture) == "function" then
			-- The page index the client itself put on the button (SetID), with the
			-- loop index as the fallback for a variant that does not set it.
			local index = i
			if type(btn.GetID) == "function" then
				local okId, v = pcall(btn.GetID, btn)
				if okId and type(v) == "number" and v > 0 then index = v end
			end
			local okLink, link = pcall(getLink, index)
			if okLink and type(link) == "string" and link ~= "" then
				ChestAdvisor.vendorWalked = ChestAdvisor.vendorWalked + 1
				local id = itemIDOf(link)
				local loc = type(id) == "number" and equipLocation(id) or nil
				-- The SAME judge the quest-reward walk calls, on the SAME single item
				-- reader, with the SAME pre-reads. It fails closed on everything it
				-- cannot resolve (out of scope, no role, no order, unusable), so a row
				-- it cannot judge draws no mark.
				local v = nil
				if loc ~= nil and wornSlotFor(loc) ~= nil then
					local okJudge, verdict = pcall(judgeQuestReward,
						link, loc, id, spec, wornLinks, offHandSpec, mainHandLoc, wornOffLoc)
					if okJudge then v = verdict end
				end
				if v == "UPGRADE" then
					local mark = btn.ChestAdvisorVendorMark
					if type(mark) ~= "table" then
						-- pcall'd for the same reason as the paper-doll hint: this surface
						-- is additive and must not be able to abort a scan.
						local okTex, tex = pcall(btn.CreateTexture, btn, nil, "OVERLAY", nil, 7)
						if okTex and type(tex) == "table" then
							if type(tex.SetTexture) == "function" then
								tex:SetTexture(QUEST_ARROW_TEXTURE)
							end
							tex:SetSize(QUEST_ARROW_SIZE, QUEST_ARROW_SIZE)
							tex:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 1, 1)
							btn.ChestAdvisorVendorMark = tex
							mark = tex
						else
							mark = nil
						end
					end
					if type(mark) == "table" and type(mark.SetShown) == "function" then
						pcall(mark.SetShown, mark, true)
						ChestAdvisor._paintGlyph(btn, "upgrade", mark)
						-- Test + diag record. The verdict word here is the comparator's
						-- own return, not a fabrication.
						btn.__chestAdvisorVendorMarked = {
							index = index, link = link, verdict = v,
						}
						shown = shown + 1
					end
				end
			end
		end
	end
	ChestAdvisor.vendorShown = shown
	return true
end
ChestAdvisor.refreshVendorMarkers = refreshVendorMarkers

-- Test + diag access (read-only).
ChestAdvisor.vendorState = function()
	local links = {}
	for i = 1, 12 do
		local btn = rawget(_G, ChestAdvisor.vendorButtonName(i))
		local mark = type(btn) == "table" and btn.ChestAdvisorVendorMark or nil
		if type(mark) == "table" and mark.shown then
			local rec = btn.__chestAdvisorVendorMarked
			links[#links + 1] = rec and rec.link or nil
		end
	end
	return {
		shown = #links,
		links = links,
		walked = ChestAdvisor.vendorWalked,
		visible = frameIsShown(rawget(_G, "MerchantFrame")),
	}
end

-- Defer one tick (the client is mid-render when the event fires), with a generation
-- token so a burst collapses into the last one — the scheduleQuestRefresh shape.
ChestAdvisor.vendorGen = 0
ChestAdvisor._scheduleVendorRefresh = function(delay)
	ChestAdvisor.vendorGen = (ChestAdvisor.vendorGen or 0) + 1
	local myGen = ChestAdvisor.vendorGen
	local function pass()
		if myGen ~= ChestAdvisor.vendorGen then return end
		ChestAdvisor.refreshVendorMarkers()
	end
	if C_Timer and type(C_Timer.After) == "function" then
		C_Timer.After(delay or 0, pass)
	else
		pass()
	end
end

-- The event entry points. MERCHANT_SHOW / MERCHANT_UPDATE are the documented
-- lifecycle events of the merchant frame (Blizzard_APIDocumentationGenerated/
-- MerchantFrameDocumentation.lua, LiteralNames MERCHANT_SHOW / MERCHANT_UPDATE /
-- MERCHANT_CLOSED) and are the two the client's own frame re-renders on, so they are
-- what the refresh is scheduled from. MERCHANT_CLOSED and the frame's OnHide both
-- clear.
ChestAdvisor._onMerchantEvent = function()
	ChestAdvisor._scheduleVendorRefresh(0.05)
end
ChestAdvisor._onMerchantClosed = function()
	ChestAdvisor._clearVendorMarks()
end

-- Hook the merchant frame's own visibility, once, re-runnably (the pane can be
-- created lazily). HookScript, never SetScript: the client's own MerchantFrame_OnShow
-- (which opens the bags) and MerchantFrame_OnHide (which closes them) keep running.
ChestAdvisor.merchantHooked = false
ChestAdvisor._installMerchantHooks = function()
	local frame = rawget(_G, "MerchantFrame")
	if type(frame) ~= "table" or ChestAdvisor.merchantHooked then return end
	if type(frame.HookScript) ~= "function" then return end
	ChestAdvisor.merchantHooked = true
	frame:HookScript("OnShow", function()
		ChestAdvisor._scheduleVendorRefresh(0.05)
	end)
	frame:HookScript("OnHide", function()
		ChestAdvisor._clearVendorMarks()
	end)
end

-- Fold (MightiePack Touchstone module): deferred to ChestAdvisor.Enable(),
-- then re-attempted on every scan event (the frames are created lazily).

-- ---- Toast (t_632f27e9): the "Upgrade found!" notification layer -------------
--
-- PRESENTATION ONLY. The toast consumes the SAME UPGRADE verdict set the marker
-- reads (verdicts[link].verdict == "UPGRADE", written by the scan below) and adds
-- NO evaluation of its own: no second comparator, no second eligibility read. The
-- scan's hard CanUseItem gate (the canUse() helper above, and Verdict's own gate
-- 3) therefore carries into the toast for free — an item the character cannot use
-- never reaches an UPGRADE verdict, so it never reaches the toast (AC-E2). The
-- toast must NOT be built on a raw item read: it is built on the verdict row.
--
-- THE TRAP this layer exists to defeat (the card's ⚠): ChestAdvisor.scan() runs
-- on PLAYER_LOGIN, PLAYER_ENTERING_WORLD, BAG_UPDATE_DELAYED and
-- PLAYER_EQUIPMENT_CHANGED, plus the bag-open refresh hooks — every inventory
-- touch re-scans. A toast fired on "is there an UPGRADE?" would pop forever. So:
--   * DEDUPE — one toast per item per session, keyed by the item's hyperlink (the
--     same identity the verdicts table is keyed by). A rescan yielding the same
--     verdict is silent.
--   * NO LOGIN WALL — the first scan of a session establishes the baseline: it
--     seeds the dedupe set with whatever is already UPGRADE and toasts nothing. A
--     player who logs in with upgrades already in the bags sees no toast; the
--     arrows are already there. (Stated choice, per the card.)
--   * COALESCE — several upgrades at once become a queued ROTATION of the mock's
--     single-item toast, TOAST_MAX deep. Chosen over a "3 upgrades found!"
--     aggregate because the mock shows ONE item with its icon: a rotation keeps
--     the icon+name and never silently hides which items they are. The tail past
--     TOAST_MAX is a stated drop, counted (toastDropped / toastState), not hidden.
--
-- No new art (AC-H): the panel is the CLIENT's own TooltipBackdropTemplate (the
-- shipped UI-Tooltip-Background / UI-Tooltip-Border nine-slice), the icon is the
-- item's real client icon (C_Item.GetItemIconByID), and the arrow overlay reuses
-- the existing marker.tga — the same visual grammar as the slot marker.
-- The toast is its own scope (Lua 5.1 main-chunk local cap is 200).
-- Scan and /up toast bind the two functions published at the bottom.
do
local function initToastSurface()
local TOAST_W, TOAST_H = 300, 78     -- the mock's "roughly 300x75"
local TOAST_Y = -140                 -- upper-middle, in the level-up banner family
local TOAST_ICON  = 34
local TOAST_ARROW = 16               -- marker.tga is a 16x16 texture
local TOAST_MAX   = 3                -- queued single-item toasts per batch
local TOAST_HEADER = "Upgrade found!"
local TOAST_FALLBACK_SUB = "Better item in your bags"
local TOAST_FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local TOAST_ARROW_TEXTURE =
	(MIGHTIEPACK_TOUCHSTONE_ASSETS .. "marker.tga")
-- The item name is neutral text (white) and the sub line keeps the mock's ruled
-- green — neither is Touchstone's own chrome. The one ACCENT lives on the TOAST
-- table above; these two are what is left of the mock's own palette.
local TOAST_NEUTRAL = { 1, 1, 1 }
local TOAST_GOOD = { 0.33, 1.0, 0.33 }

-- ---- U3 (card t_cf2ad83c): the toast's own knobs ------------------------------
--
-- Grouped into ONE table rather than a dozen file-locals: Lua 5.1 caps a chunk at
-- 200 locals and this module is already close to it, so a new top-level local is
-- a scarce resource. Tune here.
--
--   accent      — U3/6, the ONE accent. The audit flagged THREE palettes in play
--                 (the tooltip's green-on-grey, the window's cyan, chat's orange).
--                 The window's cyan is the product's established identity, so
--                 the toast's border and its "Upgrade found!" header take it. The
--                 item NAME stays the client's white and the sub line keeps the
--                 ruled green, so the mock's layout is not repainted. The value
--                 is hard-coded rather than read from StatForge.Colors.accent
--                 because this module takes NO runtime dependency on the host
--                 core — it is the same #66FCF1 triple Constants.lua publishes.
--   fadeIn/Out  — U3/1, the animation durations (seconds).
--   slide       — U3/1, px the panel travels while fading in.
--   tick        — U3/2, the lifetime countdown's resolution. Short, so it bounds
--                 how long a toast may outlive its stated lifetime.
local TOAST = {
	accent = { 0.400, 0.988, 0.945 },   -- #66FCF1, the window's own accent
	fadeIn = 0.18,
	fadeOut = 0.25,
	slide = 18,
	tick = 0.25,
}

-- The persisted setting lives on the EXISTING per-character SavedVariables store
-- (AC-E: do not add a new store). Default ON — a missing key reads as ON.
local TOAST_DEFAULTS = { enabled = true, lifetime = 3.5 }
local function toastIsEnabled()
	local t = ChestAdvisorDB and ChestAdvisorDB.toast
	if type(t) ~= "table" then return TOAST_DEFAULTS.enabled end
	return t.enabled ~= false          -- only an explicit `false` disables
end

-- The lifetime a show actually counts down from, in seconds. The persisted knob
-- wins when it holds a sane number (TOAST_DEFAULTS.lifetime is the shipped
-- default); anything else reads as the default. This is the value /up diag
-- compares the MEASURED on-screen time against, so it must be the same one
-- showToastItem counts down — one reader, no second copy.
local function toastLifetime()
	local t = ChestAdvisorDB and ChestAdvisorDB.toast
	local v = type(t) == "table" and t.lifetime or nil
	if type(v) == "number" and v > 0 and v <= 60 then return v end
	return TOAST_DEFAULTS.lifetime
end

local toastFrame = nil
local toastActive = false            -- a toast is displayed with its timer pending
local toastQueue = {}
local toastSeenFirstScan = false     -- the login-baseline gate
local toastDropped = 0               -- tail items past TOAST_MAX in the last batch
local toastedLinks = {}              -- link -> true, told this session
local toastBaselineLinks = {}        -- links present on the first scan, upgrade or not
local toastFired = 0                 -- count of toasts actually drawn (test/diag)

-- ---- U3 state (card t_cf2ad83c) ------------------------------------------------
-- Grouped into ONE table for the same reason TOAST is: Lua 5.1 caps a chunk at 200
-- locals and this module sits right under it. `toastRT` is the toast's live
-- runtime state; `toastFrame`/`toastActive`/`toastQueue` above are the pre-existing
-- ones and are left alone.
--
--   current      — the item ON SCREEN (dismiss/open need its link)
--   hovered      — the mouse is over the panel (U3/2)
--   lifetimeLeft — seconds remaining; frozen while hovered
--   held         — items deferred by combat lock (U3/5)
--   deferred     — at least one item is held for PLAYER_REGEN
--   fadeIn/Out   — the two animation groups, built once
--   ticker       — the lifetime countdown's ticker handle
--   fadeFor      — the show id whose EXPIRY the fade-out group is playing for;
--                  nil when no fade-out is in flight (t_4bae0617)
--   shownAt      — GetTime() at the show; showMs/lastEnd are the measured
--                  on-screen duration and how the show ended (/up diag reads
--                  them, so a tester gets a NUMBER instead of a stopwatch)
local toastRT = {
	current = nil, hovered = false, lifetimeLeft = 0,
	held = {}, deferred = false,
	fadeIn = nil, fadeOut = nil, ticker = nil,
	fadeFor = nil, shownAt = nil, showMs = nil, lastEnd = nil,
	-- t_fe7a636a: the show's deadline in the client's own clock, and
	-- the counters for the repairs below. `deadline` is refreshed by the
	-- countdown every tick, so a finish step can require that the
	-- configured lifetime really elapsed instead of trusting whichever
	-- animation callback arrived.
	deadline = nil, fadeArmedAt = nil, lastTickPrinted = nil,
	revived = 0, alphaRestored = 0,
}

-- ---- t_fe7a636a: the toast's own trace ---------------------------------
--
-- A toast can end from the countdown, the fade-out group's OnFinished,
-- that group's fallback timer, a right-click, or a scan that runs while
-- one is up. A tester who reports "it is a flash" leaves exactly one
-- question: WHICH transition ran early. This prints all of them with the
-- client's own clock (GetTime, three decimals). It is OFF until
-- /up toastdebug turns it on, and it writes nothing until then.
--
-- Vocabulary, one line per transition, `t=` always last:
--   show id=<n>                      showToastItem starts drawing
--   shown id=<n> alpha=<a>           after f:Show()
--   fadeIn play id=<n>               the fade-in group was played
--   animation finished: group=<fadeIn|fadeOut> id=<n> fadeFor=<nil|id>
--   tick id=<n> left=<seconds>       at most once per second
--   expire id=<n> reason=<timer|dismiss|rescan|other>
--   finish id=<n> reason=<fadeOnFinished|fadeTimer|dismiss|rescan>
--      lifeLeft=<seconds>
-- plus what the fix adds, so a flash is diagnosed from the text:
--   finish refused: id=<n> reason=<r> left=<seconds>
--   alpha restore id=<n> was=<a>     the fade-in left the panel at 0
--   revive id=<n> left=<seconds>     a hidden panel was shown again
local TRACE = { on = false, buf = {}, max = 80 }
function TRACE.now()
	if type(GetTime) == "function" then
		local ok, t = pcall(GetTime)
		if ok and type(t) == "number" then return t end
	end
	return 0
end
function TRACE.fmt(num)
	return string.format("%.3f", tonumber(num) or 0)
end
function TRACE.sec(num)
	return string.format("%.2f", tonumber(num) or 0)
end
function TRACE.line(msg, at)
	if not TRACE.on then return end
	local line = tostring(msg) .. " t=" .. TRACE.fmt(at or TRACE.now())
	TRACE.buf[#TRACE.buf + 1] = line
	while #TRACE.buf > TRACE.max do table.remove(TRACE.buf, 1) end
	-- Straight to the chat frame: this is a raw trace a tester copies
	-- back, not one of the addon's own messages, so it carries no
	-- "Touchstone:" wrapper and no colour on the payload.
	if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
		pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME,
			"|cff66fcf1toast debug|r " .. line)
	elseif type(print) == "function" then
		pcall(print, "toast debug " .. line)
	end
end
-- The switch behind /up toastdebug: `on|off|dump`, and a bare call
-- toggles. Turning it ON clears the buffer, so the lines a tester reads
-- back describe the toast they are about to raise and not an old one.
ChestAdvisor.toastDebug = function(mode)
	local m = type(mode) == "string" and mode:lower() or ""
	if m == "dump" then
		if #TRACE.buf == 0 then
			return true, "no trace lines yet — /up toastdebug on, then /up toasts"
		end
		return true, table.concat(TRACE.buf, "\n")
	end
	if m == "on" then
		TRACE.on = true
		TRACE.buf = {}
	elseif m == "off" then
		TRACE.on = false
	else
		TRACE.on = not TRACE.on
		if TRACE.on then TRACE.buf = {} end
	end
	return true, "toast debug is " .. (TRACE.on and "ON" or "off")
		.. " — /up toasts raises one; /up toastdebug dump prints the last "
		.. tostring(TRACE.max) .. " lines"
end

local drawToast, advanceToast, showToastItem, toastFinishShow, toastMeasure

-- The persisted position (U3/4). Same discipline as the window's own
-- savePosition/restorePosition in UI.lua: store only NUMBERS, because the
-- client's own GetPoint returns a Frame as its 2nd value and SavedVariables
-- cannot serialize a frame. A missing key leaves the default anchor in place.
local TOAST_POS_DEFAULT = { point = "TOP", x = 0, y = TOAST_Y }
local function saveToastPosition()
	if not (toastFrame and ChestAdvisorDB) then return end
	-- Only ever save a REAL anchor. The slide animation is a Translation applied
	-- at draw time; it never rewrites the frame's own point, so the point read
	-- here is always the resting one. (An earlier version of this function also
	-- bailed while a toast was on screen — which made a drag DURING a toast
	-- unsaveable, i.e. exactly when the player is most likely to move it.)
	local p = toastFrame:GetPoint()
	if type(p) == "string" and type(toastFrame.x) == "number"
		and type(toastFrame.y) == "number" then
		ChestAdvisorDB.toast = ChestAdvisorDB.toast or {}
		ChestAdvisorDB.toast.pos = { point = toastFrame.point or p,
			x = toastFrame.x, y = toastFrame.y }
	end
end

local function applyToastPosition(f)
	local pos = ChestAdvisorDB and ChestAdvisorDB.toast
		and ChestAdvisorDB.toast.pos or nil
	local point = type(pos) == "table" and type(pos.point) == "string"
		and pos.point or TOAST_POS_DEFAULT.point
	local x = (type(pos) == "table" and type(pos.x) == "number")
		and pos.x or TOAST_POS_DEFAULT.x
	local y = (type(pos) == "table" and type(pos.y) == "number")
		and pos.y or TOAST_POS_DEFAULT.y
	f:ClearAllPoints()
	-- The saved point always names UIParent as the reference, exactly like the
	-- default. A saved point is one of the client's own point tokens; an
	-- unrecognised one would raise inside SetPoint, so it is validated by the
	-- same pcall the rest of this file uses for client-optional surfaces.
	local ok = pcall(f.SetPoint, f, point, UIParent, point, x, y)
	if not ok then pcall(f.SetPoint, f, "TOP", UIParent, "TOP", 0, TOAST_Y) end
	f.point, f.x, f.y = point, x, y
end

-- The item's name for the toast. C_Item.GetItemInfo first (the client's answer);
-- the hyperlink's own bracket text as the fallback — never a fabricated name.
local function toastName(link)
	if C_Item and type(C_Item.GetItemInfo) == "function" then
		local ok, name = pcall(C_Item.GetItemInfo, link)
		if ok and type(name) == "string" and name ~= "" then return name end
	end
	local n = type(link) == "string" and link:match("%[(.-)%]") or nil
	if n and n ~= "" then return n end
	return tostring(link)
end

-- AC-B: a real number when one is COMPUTABLE, the mock's wording otherwise.
-- A WEAPON row's delta is the compareDPS value the scan already judged on — the
-- number the client prints, read through Verdict.weaponDPS, never invented. An
-- ARMOUR row has no such scalar: the armour comparator is an ordered multi-stat
-- walk, not a single delta, so it takes the mock's fallback. This only ever runs
-- for an UPGRADE row, which is exactly the case the scan already proved c > w
-- (or an empty-slot fill), so the sign is known and no delta is fabricated.
local function buildToastMessage(item)
	local fallback = { text = TOAST_FALLBACK_SUB, delta = nil }
	if not (Verdict and type(Verdict.WEAPON_TOKENS) == "table"
		and type(Verdict.weaponNumbers) == "function"
		and type(Verdict.weaponDPS) == "function") then
		return fallback
	end
	local loc = (item and item.id) and equipLocation(item.id) or nil
	if not (loc and Verdict.WEAPON_TOKENS[loc]) then return fallback end
	local invSlot = item.invSlot
	if type(invSlot) ~= "number" then return fallback end
	local wornLink = GetInventoryItemLink
		and GetInventoryItemLink("player", invSlot) or nil
	local cand = Verdict.weaponNumbers(itemLines(item.link))
	local worn = wornLink and Verdict.weaponNumbers(itemLines(wornLink)) or nil
	local c = Verdict.weaponDPS(cand)
	local w = Verdict.weaponDPS(worn)
	if c and w then
		local delta = c - w
		return {
			text = slotWord(invSlot) .. " · "
				.. (delta >= 0 and "+" or "") .. string.format("%.1f", delta)
				.. " DPS vs equipped",
			delta = delta,
		}
	end
	return fallback
end

-- Build the toast frame once, on first use. The panel is the client's own tooltip
-- backdrop (rounded, dark, subtle border — no new art); the icon is the item's
-- real client icon; the arrow overlay is the existing marker.tga on the icon's
-- top-right, the same grammar as the bag marker.
--
-- U3 (card t_cf2ad83c): the panel is now MOVABLE (drag) and remembers where it
-- was put, animates in/out, and takes left/right clicks. Everything here is
-- guarded: this frame is built on the client's own template and every optional
-- API is probed with type()/pcall, so an older client degrades to the previous
-- static behaviour rather than erroring on the first upgrade.
local function toastStopAnimations()
	if type(toastRT.fadeIn) == "table" and type(toastRT.fadeIn.Stop) == "function" then
		pcall(toastRT.fadeIn.Stop, toastRT.fadeIn)
	end
	if type(toastRT.fadeOut) == "table" and type(toastRT.fadeOut.Stop) == "function" then
		pcall(toastRT.fadeOut.Stop, toastRT.fadeOut)
	end
end

-- Fade+slide the panel in. Both animation groups live on the frame and are
-- re-used forever; only their offsets are rewritten per show, so a rotation
-- through TOAST_MAX toasts does not leak an animation object per toast.
local function toastPlayFadeIn(f, showId)
	toastStopAnimations()
	if type(f.SetAlpha) ~= "function" then return end
	pcall(f.SetAlpha, f, 0)
	if type(toastRT.fadeIn) == "table" and type(toastRT.fadeIn.Play) == "function" then
		pcall(toastRT.fadeIn.Play, toastRT.fadeIn)
		TRACE.line("fadeIn play id=" .. tostring(showId))
	else
		-- A client with no animation system still gets a visible toast.
		pcall(f.SetAlpha, f, 1)
		f.alpha = 1
	end
end

local function toastBuildAnimations(f)
	if type(f.CreateAnimationGroup) ~= "function" then return end
	do
		local ag = f:CreateAnimationGroup()
		if type(ag.CreateAnimation) == "function" then
			local a = ag:CreateAnimation("Alpha")
			if type(a.SetFromAlpha) == "function" then a:SetFromAlpha(0) end
			if type(a.SetToAlpha) == "function" then a:SetToAlpha(1) end
			if type(a.SetDuration) == "function" then a:SetDuration(TOAST.fadeIn) end
			local s = ag:CreateAnimation("Translation")
			if type(s.SetOffset) == "function" then
				s:SetOffset(0, -TOAST.slide)
			end
			if type(s.SetDuration) == "function" then s:SetDuration(TOAST.fadeIn) end
		end
		-- t_fe7a636a: the fade-IN group reports its own OnFinished to the
		-- trace and does nothing else. It has no finish path at all; if this
		-- client delivers OnFinished from a Stop() (the behaviour the
		-- fade-out's guard exists for), the trace says so instead of a
		-- comment asserting it.
		if type(ag.SetScript) == "function" then
			ag:SetScript("OnFinished", function()
				TRACE.line("animation finished: group=fadeIn id="
					.. tostring(toastRT.showId)
					.. " fadeFor=" .. tostring(toastRT.fadeFor))
			end)
		end
		toastRT.fadeIn = ag
	end
	do
		local ag = f:CreateAnimationGroup()
		if type(ag.CreateAnimation) == "function" then
			local a = ag:CreateAnimation("Alpha")
			if type(a.SetFromAlpha) == "function" then a:SetFromAlpha(1) end
			if type(a.SetToAlpha) == "function" then a:SetToAlpha(0) end
			if type(a.SetDuration) == "function" then a:SetDuration(TOAST.fadeOut) end
		end
		-- When the fade-out finishes the panel is hidden for real, and the next
		-- queued toast takes the screen. Re-armed on every show. OnFinished is
		-- not the only hide: the classic client drops it when the same group
		-- was Stopped and Played in one frame, and a finish step that errors
		-- must not leave the panel up. toastExpire also arms a timer.
		--
		-- t_4bae0617 — THE EARLY-HIDE BUG. A Stop() on this group reports
		-- OnFinished too (that is the same client behaviour that makes the
		-- Stopped+Played note above necessary). toastPlayFadeIn Stops BOTH
		-- groups before every show, so a show that had only just been drawn
		-- immediately reported "fade-out finished": the handler ran the finish
		-- step on the toast it had just started and the panel vanished within a
		-- frame of appearing — exactly the "goes away extremely fast" report,
		-- and it hit EVERY toast, because the stop happens on every show.
		-- The group may therefore only end a show when a fade-out was actually
		-- ARMED for an expiry: toastRT.fadeFor names that show id, and it is nil
		-- while no fade-out is in flight.
		if type(ag.SetScript) == "function" then
			ag:SetScript("OnFinished", function()
				local id = toastRT.fadeFor
				TRACE.line("animation finished: group=fadeOut id="
					.. tostring(toastRT.showId)
					.. " fadeFor=" .. tostring(id))
				if id == nil then return end
				toastRT.fadeFor = nil
				pcall(toastFinishShow, id, "fadeOnFinished")
			end)
		end
		toastRT.fadeOut = ag
	end
end

local function buildToastFrame()
	local f = CreateFrame("Button", "ChestAdvisorToast", UIParent,
		"TooltipBackdropTemplate")
	if type(f) ~= "table" then error("toast frame was not created") end
	-- Hidden until the build finishes. CreateFrame shows the frame, and a
	-- throw later (OnClick on a plain Frame, a missing font) used to leave
	-- that half-built frame on screen — an empty box and a green arrow,
	-- with toastFrame still nil so nothing could hide or fade it.
	if type(f.Hide) == "function" then f:Hide() end
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:SetSize(TOAST_W, TOAST_H)
	-- U3/4: the anchor is the PERSISTED one when the player has moved the panel,
	-- and the shipped default otherwise.
	applyToastPosition(f)
	if type(f.SetBackdrop) == "function" then
		f:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 14,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		f:SetBackdropColor(0.05, 0.05, 0.05, 0.86)
	end
	-- U3/6: the ONE accent. Cyan, the window's own — on the toast's border and
	-- its header only (see the TOAST.accent note).
	if type(f.SetBackdropBorderColor) == "function" then
		f:SetBackdropBorderColor(TOAST.accent[1], TOAST.accent[2], TOAST.accent[3], 1)
	end
	local icon = f:CreateTexture("ChestAdvisorToastIcon", "ARTWORK")
	icon:SetSize(TOAST_ICON, TOAST_ICON)
	icon:SetPoint("LEFT", f, "LEFT", 14, 0)
	f.icon = icon
	local arrow = f:CreateTexture("ChestAdvisorToastArrow", "OVERLAY")
	arrow:SetSize(TOAST_ARROW, TOAST_ARROW)
	arrow:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 5, 5)
	arrow:SetTexture(TOAST_ARROW_TEXTURE)
	f.arrow = arrow
	local header = f:CreateFontString("ChestAdvisorToastHeader", "ARTWORK",
		"GameFontNormalLarge")
	header:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, 2)
	header:SetTextColor(TOAST.accent[1], TOAST.accent[2], TOAST.accent[3])
	f.header = header
	local name = f:CreateFontString("ChestAdvisorToastName", "ARTWORK",
		"GameFontNormal")
	name:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
	name:SetTextColor(TOAST_NEUTRAL[1], TOAST_NEUTRAL[2], TOAST_NEUTRAL[3])
	-- NOTE: the frame field is `itemName`, NOT `name` — `f.name` is the frame's
	-- own name string (GetName) and the harness's count helpers read it.
	f.itemName = name
	local sub = f:CreateFontString("ChestAdvisorToastSub", "ARTWORK",
		"GameFontNormalSmall")
	sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
	-- The sub line is the ITEM's own data ("main hand · +1.5 DPS vs equipped"),
	-- so it keeps the mock's ruled green — it is not Touchstone's chrome, and the
	-- previous card's AC-A pins it. Only the header and the border take the accent.
	sub:SetTextColor(TOAST_GOOD[1], TOAST_GOOD[2], TOAST_GOOD[3])
	f.sub = sub

	toastBuildAnimations(f)

	-- ---- U3/2: pause while hovered -------------------------------------------
	-- The lifetime is a countdown (toastRT.lifetimeLeft) rather than a single
	-- C_Timer.After, so it can be FROZEN. The frame itself owns the mouse (a
	-- toast the player cannot click is not clickable at all), so it reports its
	-- own hover through OnEnter/OnLeave.
	if type(f.EnableMouse) == "function" then f:EnableMouse(true) end
	if type(f.SetScript) == "function" then
		f:SetScript("OnEnter", function()
			toastRT.hovered = true
		end)
		f:SetScript("OnLeave", function()
			toastRT.hovered = false
		end)
	end

	-- ---- U3/3: the two clicks -------------------------------------------------
	-- LEFT  — open the bags and flash the upgrade's own cell.
	-- RIGHT — dismiss the toast. It must NOT open the bags (the card is explicit).
	if type(f.RegisterForClicks) == "function" then
		pcall(f.RegisterForClicks, f, "LeftButtonUp", "RightButtonUp")
	end
	if type(f.SetScript) == "function" then
		f:SetScript("OnClick", function(self, button)
			local item = toastRT.current
			if button == "RightButton" then
				-- Dismiss. No bag window is touched on this path.
				-- t_4bae0617: this is the OTHER way a show ends, so it records the
				-- same measured duration, and it disarms the fade BEFORE the Stop
				-- below (a Stop reports OnFinished on this client).
				toastRT.lastEnd = "dismissed"
				-- t_fe7a636a: a dismiss is the one end that may come before the
				-- deadline (the player asked for it). It is traced as both an
				-- expire and a finish so every end reads in the same vocabulary.
				local dismissedLeft = tonumber(toastRT.lifetimeLeft) or 0
				if dismissedLeft < 0 then dismissedLeft = 0 end
				TRACE.line("expire id=" .. tostring(toastRT.showId) .. " reason=dismiss")
				TRACE.line("finish id=" .. tostring(toastRT.showId)
					.. " reason=dismiss lifeLeft=" .. TRACE.sec(dismissedLeft))
				toastRT.deadline = nil
				toastRT.fadeArmedAt = nil
				local ms = toastMeasure and toastMeasure()
				if ms then toastRT.showMs = ms end
				toastRT.shownAt = nil
				toastRT.fadeFor = nil
				toastStopAnimations()
				-- …and stop the countdown, or the ticker would fire the fade-out
				-- a moment later on a toast that is already gone.
				if type(toastRT.ticker) == "table"
					and type(toastRT.ticker.Cancel) == "function" then
					pcall(toastRT.ticker.Cancel, toastRT.ticker)
				end
				toastRT.ticker = nil
				if type(self.Hide) == "function" then pcall(self.Hide, self) end
				self.shown = false
				toastActive = false
				toastRT.current = nil
				toastRT.hovered = false
				toastRT.lifetimeLeft = 0
				-- Dismiss THIS toast. Anything still queued is a DIFFERENT upgrade
				-- the player has not seen, and it is already marked "told" — so
				-- dropping the queue here would lose it silently. Continue the
				-- rotation instead.
				local nxt = table.remove(toastQueue, 1)
				if nxt then showToastItem(nxt) end
				return
			end
			-- Left: open the bags, then flash the cell the item is in.
			if type(OpenAllBags) == "function" then pcall(OpenAllBags) end
			if type(OpenBackpack) == "function" then pcall(OpenBackpack) end
			if item and type(item.link) == "string" then
				ChestAdvisor.flashUpgradeCell(item.link)
			end
		end)
	end

	-- ---- U3/4: movable, and remembered ---------------------------------------
	if type(f.SetMovable) == "function" then f:SetMovable(true) end
	if type(f.RegisterForDrag) == "function" then
		pcall(f.RegisterForDrag, f, "LeftButton")
	end
	if type(f.SetClampedToScreen) == "function" then f:SetClampedToScreen(true) end
	if type(f.SetScript) == "function" then
		f:SetScript("OnDragStart", function(self)
			-- A drag must not fight the fade animation's own Translation, so the
			-- animations are stopped first and the alpha pinned to fully visible.
			toastStopAnimations()
			if type(self.SetAlpha) == "function" then pcall(self.SetAlpha, self, 1) end
			self.alpha = 1
			self.dragging = true
			if type(self.StartMoving) == "function" then pcall(self.StartMoving, self) end
		end)
		f:SetScript("OnDragStop", function(self)
			self.dragging = false
			if type(self.StopMovingOrSizing) == "function" then
				pcall(self.StopMovingOrSizing, self)
			end
			-- Record where the player LEFT it. GetPoint returns the point token
			-- first; the offsets are read from the client's own values, so a
			-- resize/re-anchor is captured exactly. Only numbers are stored.
			local p, _, _, x, y = self:GetPoint()
			if type(p) == "string" then
				self.point, self.x, self.y = p, x or 0, y or 0
			end
			saveToastPosition()
		end)
	end

	f.__toastReady = true
	return f
end

local function discardToastFrame()
	local orphan = rawget(_G, "ChestAdvisorToast")
	if type(orphan) == "table" then
		if type(orphan.Hide) == "function" then pcall(orphan.Hide, orphan) end
		orphan.shown = false
	end
	toastFrame = nil
	toastActive = false
end

local function ensureToast()
	if toastFrame and toastFrame.__toastReady then return toastFrame end
	local ok, f = pcall(buildToastFrame)
	if not ok or type(f) ~= "table" or f.__toastReady ~= true then
		discardToastFrame()
		return nil
	end
	toastFrame = f
	return f
end

-- The lifetime countdown (U3/2). One ticker, created once, re-armed per show.
-- While the panel is hovered the remaining time is simply NOT decremented — that
-- is the whole pause, and it is why the expiry is a countdown rather than a
-- single C_Timer.After (a fired timer cannot be un-fired).
--
-- The tick interval is deliberately short (0.25s): it bounds how long a toast can
-- outlive its stated lifetime by, and it costs nothing at this cadence.
local toastExpire

local function toastStartTimer(showId)
	if type(C_Timer) ~= "table" or type(C_Timer.NewTicker) ~= "function" then
		return
	end
	if toastRT.ticker and type(toastRT.ticker.Cancel) == "function" then
		pcall(toastRT.ticker.Cancel, toastRT.ticker)
	end
	toastRT.ticker = C_Timer.NewTicker(TOAST.tick, function()
		if not toastActive then return end
		if showId ~= nil and toastRT.showId ~= showId then return end
		local now = TRACE.now()
		-- t_fe7a636a: the panel must be ON SCREEN while this show is live.
		-- If anything outside this block took it away (an animation quirk, a
		-- client-side hide, a path nobody has found yet) the show would run
		-- invisibly — which is exactly what "a flash, then nothing" looks
		-- like from the outside. Put it back, and say so.
		if toastRT.fadeFor == nil and (toastRT.lifetimeLeft or 0) > 0
			and type(toastFrame) == "table" then
			local tf = toastFrame
			local shownNow = true
			if type(tf.IsShown) == "function" then
				local okS, s = pcall(tf.IsShown, tf)
				if okS then shownNow = (s ~= false) end
			end
			if not shownNow then
				if type(tf.Show) == "function" then pcall(tf.Show, tf) end
				tf.shown = true
				if type(tf.SetAlpha) == "function" then pcall(tf.SetAlpha, tf, 1) end
				tf.alpha = 1
				toastRT.revived = (toastRT.revived or 0) + 1
				TRACE.line("revive id=" .. tostring(showId) .. " left="
					.. TRACE.sec(toastRT.lifetimeLeft), now)
			end
		end
		if toastRT.hovered or (toastFrame and toastFrame.dragging) then return end
		toastRT.lifetimeLeft = toastRT.lifetimeLeft - TOAST.tick
		-- The deadline the finish step obeys. Refreshed from the clock on
		-- every tick, so the countdown and the finish cannot disagree even
		-- when a tick is late (and a hover pause moves it with the pause).
		toastRT.deadline = now + toastRT.lifetimeLeft
		if (toastRT.lifetimeLeft or 0) > 0 and TRACE.on then
			local whole = math.floor(toastRT.lifetimeLeft)
			if toastRT.lastTickPrinted ~= whole then
				toastRT.lastTickPrinted = whole
				TRACE.line("tick id=" .. tostring(showId) .. " left="
					.. TRACE.sec(toastRT.lifetimeLeft), now)
			end
		end
		if toastRT.lifetimeLeft <= 0 then
			toastExpire("timer")
		end
	end)
end

-- Hide the panel and let the queue continue. Idempotent per show id: the
-- fade's OnFinished and the lifetime fallback both call it, and a second call
-- must not skip a toast the first call already put on screen.
--
-- t_4bae0617: how long the CURRENT show has been on screen, in milliseconds,
-- from the client's own clock (GetTime) — measured, never the configured value
-- echoed back. BOTH end paths use it (this one and the right-click dismiss), so
-- the number /up diag prints always describes the show it names. nil when the
-- client has no clock or no show is stamped.
toastMeasure = function()
	if type(toastRT.shownAt) ~= "number" or type(GetTime) ~= "function" then
		return nil
	end
	local ok, now = pcall(GetTime)
	if not ok or type(now) ~= "number" then return nil end
	return math.floor((now - toastRT.shownAt) * 1000 + 0.5)
end

toastFinishShow = function(showId, reason)
	if showId ~= nil and toastRT.showId ~= showId then return end
	if not toastActive then return end
	-- t_fe7a636a: the configured lifetime is the authority. Only a
	-- right-click dismiss may end a show early; every callback-driven end
	-- (the fade-out's OnFinished, its fallback timer, a scan repair) waits
	-- for the deadline the countdown published. A client that reports
	-- OnFinished early — or delivers a stale Stop() after the fade-out was
	-- armed — therefore cannot eat a live toast, and the trace names the
	-- attempt instead of hiding it.
	local now = TRACE.now()
	reason = reason or "other"
	if reason ~= "dismiss" and type(toastRT.deadline) == "number"
		and now + 0.001 < toastRT.deadline then
		TRACE.line("finish refused: id=" .. tostring(showId)
			.. " reason=" .. reason .. " left="
			.. TRACE.sec(toastRT.deadline - now), now)
		return
	end
	local lifeLeft = tonumber(toastRT.lifetimeLeft) or 0
	if lifeLeft < 0 then lifeLeft = 0 end
	TRACE.line("finish id=" .. tostring(showId) .. " reason=" .. reason
		.. " lifeLeft=" .. TRACE.sec(lifeLeft), now)
	local ms = toastMeasure()
	if ms then toastRT.showMs = ms end
	toastRT.shownAt = nil
	toastRT.fadeFor = nil
	toastRT.deadline = nil
	toastRT.fadeArmedAt = nil
	toastRT.lastTickPrinted = nil
	toastRT.showId = (toastRT.showId or 0) + 1
	local f = toastFrame
	toastActive = false
	toastRT.current = nil
	toastRT.hovered = false
	toastRT.lifetimeLeft = 0
	if type(toastRT.ticker) == "table" and type(toastRT.ticker.Cancel) == "function" then
		pcall(toastRT.ticker.Cancel, toastRT.ticker)
	end
	toastRT.ticker = nil
	toastStopAnimations()
	if type(f) == "table" then
		if type(f.Hide) == "function" then pcall(f.Hide, f) end
		f.shown = false
		if type(f.SetAlpha) == "function" then pcall(f.SetAlpha, f, 1) end
	end
	local nxt = table.remove(toastQueue, 1)
	if nxt then
		local ok = pcall(showToastItem, nxt)
		if not ok then
			toastActive = false
			if type(toastFrame) == "table" then
				if type(toastFrame.Hide) == "function" then
					pcall(toastFrame.Hide, toastFrame)
				end
				toastFrame.shown = false
			end
		end
	end
end

-- The toast's time is up. The fade-out plays when it can, but Hide() does not
-- depend on OnFinished. Stop()+Play() on this same group in one frame drops
-- OnFinished on the classic client while the alpha still runs, which is the
-- stuck near-transparent "...und!" panel. A timer finishes the show anyway, and
-- so does a finish step that errors.
toastExpire = function(reason)
	if type(toastRT.ticker) == "table" and type(toastRT.ticker.Cancel) == "function" then
		pcall(toastRT.ticker.Cancel, toastRT.ticker)
	end
	toastRT.ticker = nil
	if not toastActive then return end
	toastRT.lastEnd = "expired"
	local showId = toastRT.showId
	TRACE.line("expire id=" .. tostring(showId) .. " reason="
		.. tostring(reason or "timer"))
	local f = toastFrame
	local fade = toastRT.fadeOut
	local fadeFinishes = type(fade) == "table" and type(fade.Play) == "function"
		and type(fade.GetScript) == "function" and type(fade:GetScript("OnFinished")) == "function"
	if f and fadeFinishes then
		-- Stop the fade-in only. Stopping the fade-out here and then playing
		-- it is what swallows OnFinished.
		if type(toastRT.fadeIn) == "table" and type(toastRT.fadeIn.Stop) == "function" then
			pcall(toastRT.fadeIn.Stop, toastRT.fadeIn)
		end
		-- Arm the group for THIS show (t_4bae0617): the OnFinished handler only
		-- ends a show whose fade-out was armed here, so the Stop() a later show
		-- does cannot end it. Cleared before Play so a Play that throws does not
		-- leave a stale arm behind.
		toastRT.fadeFor = showId
		toastRT.fadeArmedAt = TRACE.now()
		local played = pcall(fade.Play, fade)
		if not played then toastRT.fadeFor = nil end
		if played and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
			local delay = (TOAST.fadeOut or 0.25) + 0.05
			C_Timer.After(delay, function()
				pcall(toastFinishShow, showId, "fadeTimer")
			end)
			return
		end
	end
	pcall(toastFinishShow, showId, "fadeTimer")
end

-- Put ONE item on screen. The single place a toast becomes visible, so the
-- combat hold and the queue rotation cannot disagree about what "showing" means.
showToastItem = function(item)
	toastRT.showId = (toastRT.showId or 0) + 1
	local showId = toastRT.showId
	TRACE.line("show id=" .. tostring(showId))
	local f = ensureToast()
	if type(f) ~= "table" then
		toastActive = false
		return
	end
	-- A missing child used to throw inside the scan (the toast is drawn from
	-- the scan tail). Fail closed: hide the frame, do not abort the scan.
	local ok = pcall(function()
		if type(f.header) ~= "table" or type(f.itemName) ~= "table"
			or type(f.sub) ~= "table" or type(f.icon) ~= "table" then
			error("incomplete toast")
		end
		f.header:SetText(TOAST_HEADER)
		f.itemName:SetText(item.name or toastName(item.link))
		f.sub:SetText(buildToastMessage(item).text)
		local tex
		if C_Item and type(C_Item.GetItemIconByID) == "function" then
			local okIcon, t = pcall(C_Item.GetItemIconByID, item.id)
			if okIcon and t then tex = t end
		end
		f.icon:SetTexture(tex or TOAST_FALLBACK_ICON)
		-- The toast arrow is the same upgrade mark. The glyph is created only
		-- when the setting is on, so a default session adds no extra text.
		if ChestAdvisor._glyphsOn() then
			if type(f.glyph) ~= "table" and type(f.CreateFontString) == "function" then
				local okg, fs = pcall(f.CreateFontString, f, nil, "OVERLAY", "GameFontHighlightSmall")
				if okg and type(fs) == "table" then
					local rel = f.arrow or f.icon
					if type(fs.SetPoint) == "function" then
						pcall(fs.SetPoint, fs, "CENTER", rel, "CENTER", 0, 0)
					end
					if type(fs.SetTextColor) == "function" then
						pcall(fs.SetTextColor, fs, 1, 1, 1, 1)
					end
					if type(fs.SetText) == "function" then
						pcall(fs.SetText, fs, ChestAdvisor.markerGlyphs.upgrade)
					end
					f.glyph = fs
				end
			end
			if type(f.glyph) == "table" and type(f.glyph.SetShown) == "function" then
				pcall(f.glyph.SetShown, f.glyph, true)
			end
		elseif type(f.glyph) == "table" and type(f.glyph.SetShown) == "function" then
			pcall(f.glyph.SetShown, f.glyph, false)
		end
		toastRT.current = item
		-- NOTE: `toastRT.hovered` is deliberately NOT reset here. The OnEnter/OnLeave
		-- scripts own that state, and on a ROTATION (a second queued upgrade taking
		-- the screen under a stationary mouse) the pointer never left the panel — so
		-- clearing it would silently un-pause the new toast.
		toastRT.lifetimeLeft = toastLifetime()
		-- t_4bae0617: stamp the client clock so the show's real duration can be
		-- measured when it ends (and read back from /up diag).
		if type(GetTime) == "function" then
			local okClock, t0 = pcall(GetTime)
			toastRT.shownAt = (okClock and type(t0) == "number") and t0 or nil
		else
			toastRT.shownAt = nil
		end
		-- t_fe7a636a: the deadline this show must survive to, on the same
		-- clock the countdown ticks on. The finish step refuses to end a
		-- show before it.
		toastRT.deadline = (toastRT.shownAt or TRACE.now()) + toastRT.lifetimeLeft
		toastRT.fadeArmedAt = nil
		toastRT.lastTickPrinted = nil
		-- Re-anchor from the persisted position on every show: the panel may have
		-- been dragged since it was built, and the resting point is what is saved.
		if type(f.dragging) ~= "boolean" or not f.dragging then
			applyToastPosition(f)
		end
		f:Show()
		toastActive = true
		toastFired = toastFired + 1
		local alphaAtShow = 1
		if type(f.GetAlpha) == "function" then
			local okA, av = pcall(f.GetAlpha, f)
			if okA and type(av) == "number" then alphaAtShow = av end
		end
		TRACE.line("shown id=" .. tostring(showId) .. " alpha="
			.. TRACE.sec(alphaAtShow))
		toastPlayFadeIn(f, showId)
		toastStartTimer(showId)
		-- t_fe7a636a: the fade-in must not be the only thing that makes the
		-- panel visible. The alpha was just set to 0 and this client can drop
		-- a group that was Stopped and Played in one frame (the behaviour the
		-- fade-out's guard already exists for); the toast would then be an
		-- invisible show whose only visible frame is the one before the set.
		-- One timer puts the alpha back if the animation did not.
		if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
			C_Timer.After((TOAST.fadeIn or 0.18) + 0.05, function()
				if not toastActive or toastRT.showId ~= showId then return end
				if toastRT.fadeFor ~= nil then return end
				local tf = toastFrame
				if type(tf) ~= "table" or type(tf.SetAlpha) ~= "function" then return end
				local cur = 1
				if type(tf.GetAlpha) == "function" then
					local okA, av = pcall(tf.GetAlpha, tf)
					if okA and type(av) == "number" then cur = av end
				end
				if cur < 0.98 then
					pcall(tf.SetAlpha, tf, 1)
					tf.alpha = 1
					toastRT.alphaRestored = (toastRT.alphaRestored or 0) + 1
					TRACE.line("alpha restore id=" .. tostring(showId)
						.. " was=" .. TRACE.sec(cur))
				end
			end)
		end
	end)
	if not ok then
		if type(f.Hide) == "function" then pcall(f.Hide, f) end
		f.shown = false
		toastActive = false
		toastRT.current = nil
		toastRT.hovered = false
		toastFrame = nil
	end
end

-- Kept for the existing tests and the C_Timer.After-shaped callers: draw the next
-- queued item, or expire the current one. The queue rotation now lives in
-- showToastItem/toastExpire, so this is a thin shim over the same two paths.
advanceToast = function()
	if toastActive then
		toastExpire()
		return
	end
	local item = table.remove(toastQueue, 1)
	if item then
		showToastItem(item)
	elseif toastFrame then
		if type(toastFrame.Hide) == "function" then pcall(toastFrame.Hide, toastFrame) end
		toastFrame.shown = false
		toastActive = false
		toastRT.current = nil
	end
end
drawToast = function(item)
	showToastItem(item)
end

-- Called from the scan tail with this scan's verdicts. Inherits the scan's
-- eligibility gate entirely: only rows already judged UPGRADE are considered.
local function maybeToastUpgrades(verdicts)
	if not toastIsEnabled() then
		toastQueue = {}
		if toastFrame then toastFrame:Hide() end
		toastActive = false
		return
	end
	if not toastSeenFirstScan then
		-- Baseline — whatever is already in the bags at the first scan is NOT
		-- news, including rows this pass can only call UNKNOWN. A cold cache
		-- judges those same links UPGRADE once their tooltips arrive; they
		-- were already here, so the warm-up rescan stays silent. The baseline
		-- is not reopened after this scan. A link that shows up later (mail,
		-- loot, quest reward, vendor, trade) was not in this set and still toasts.
		for link, vrow in pairs(verdicts or {}) do
			if type(link) == "string" and type(vrow) == "table" then
				toastBaselineLinks[link] = true
				if vrow.verdict == "UPGRADE" then toastedLinks[link] = true end
			end
		end
		toastSeenFirstScan = true
		return
	end
	local found, n = {}, 0
	for link, vrow in pairs(verdicts or {}) do
		if vrow and vrow.verdict == "UPGRADE" and not toastedLinks[link]
			and not toastBaselineLinks[link] then
			n = n + 1
			found[n] = { link = link, id = vrow.id, bag = vrow.bag,
				slot = vrow.slot, invSlot = vrow.invSlot, name = toastName(link) }
		end
	end
	if n == 0 then return end
	-- Deterministic rotation order (link-sorted) so the sequence is repeatable
	-- across runs and a test can read a specific item's line.
	table.sort(found, function(a, b)
		return tostring(a.link) < tostring(b.link)
	end)
	toastDropped = 0
	for i = 1, #found do
		local e = found[i]
		toastedLinks[e.link] = true     -- marked told even if past the cap
		if i <= TOAST_MAX then
			toastQueue[#toastQueue + 1] = e
		else
			toastDropped = toastDropped + 1
		end
	end
	-- ---- U3/5: hold a toast raised in combat ---------------------------------
	--
	-- A toast that fires mid-pull is noise. In combat the whole queue is HELD —
	-- deferred, not dropped — and released on PLAYER_REGEN_ENABLED. The items are
	-- still marked told, so the hold is a delay and not a loss: a rescan during
	-- the fight cannot re-queue them, and the release below shows exactly the set
	-- that was held.
	if InCombatLockdown and InCombatLockdown() then
		for i = 1, #toastQueue do toastRT.held[#toastRT.held + 1] = toastQueue[i] end
		toastQueue = {}
		toastRT.deferred = true
		return
	end
	-- A toast whose lifetime already elapsed must not stay up. OnFinished is
	-- supposed to hide it; if that step never ran, toastActive would block
	-- every later upgrade behind a faded panel.
	--
	-- t_fe7a636a: but a scan must NEVER cut a live toast short. The old test
	-- (`lifetimeLeft <= 0`) is true for the whole fade-out window, so a scan
	-- landing there finished the show on the spot and cut the fade — and this
	-- is the path the card asked about, so it is traced. Only a show that is
	-- past its deadline AND has no fade-out in flight is repaired here; the
	-- fade's own OnFinished/fallback timer owns the normal end.
	if toastActive and toastRT.fadeFor == nil
		and (toastRT.lifetimeLeft or 0) <= -TOAST.tick then
		TRACE.line("expire id=" .. tostring(toastRT.showId) .. " reason=rescan")
		pcall(toastFinishShow, toastRT.showId, "rescan")
	end
	-- Draw now only if nothing is on screen; otherwise the queue drains as each
	-- toast's lifetime expires.
	if not toastActive and #toastQueue > 0 then
		showToastItem(table.remove(toastQueue, 1))
	end
end

-- ---- U3/5: the release ----------------------------------------------------------
-- PLAYER_REGEN_ENABLED — combat has ended. Show what was held. Registered on the
-- addon's EXISTING scan frame (getFrame), so this adds no second event frame and
-- no second handler; the arm is in the frame's own OnEvent below.
local function releaseHeldToasts()
	toastRT.deferred = false
	if not toastRT.held or #toastRT.held == 0 then return end
	for i = 1, #toastRT.held do
		local e = toastRT.held[i]
		if #toastQueue < TOAST_MAX then
			toastQueue[#toastQueue + 1] = e
		end
	end
	toastRT.held = {}
	if not toastActive and #toastQueue > 0 then
		showToastItem(table.remove(toastQueue, 1))
	end
end

-- ---- U3/3: the left-click flash -------------------------------------------------
-- Open the bags and FLASH the upgrade's own cell. Deliberately not a second
-- marker system: the arrow the scan already drew is pulsed by toggling its
-- shown state a few times with the client's own timer, so a player who clicked
-- the toast can see WHICH cell it meant. Bounded and self-cancelling: the
-- toggle stops after a fixed number of steps, and a rescan in the meantime
-- (which re-shows the arrow itself) only makes the pulse end early.

-- ChestAdvisor.flashUpgradeCell(link) — the flash, exposed for the toast's click.
ChestAdvisor.flashUpgradeCell = function(link)
	local f = activeMarkers and activeMarkers[link] or nil
	local tex = f and f.__arrow or nil
	if type(tex) ~= "table" or type(tex.SetShown) ~= "function" then
		-- The cell is not currently marked (out of range, bag closed, or the cap
		-- dropped it). Nothing to flash; that is not an error.
		return false
	end
	local steps = 6
	local function step()
		steps = steps - 1
		if steps <= 0 then
			pcall(tex.SetShown, tex, true)
			return
		end
		pcall(tex.SetShown, tex, (steps % 2) == 1)
		if C_Timer and type(C_Timer.After) == "function" then
			C_Timer.After(0.12, step)
		end
	end
	pcall(tex.SetShown, tex, false)
	if C_Timer and type(C_Timer.After) == "function" then
		C_Timer.After(0.12, step)
	end
	return true
end

-- B11 (card t_e9a07624): the one sanctioned way to re-arm the login baseline
-- from OUTSIDE this block. rescanForItemData (near the top of the file) calls
-- this late-bound rather than touching the file-local `toastSeenFirstScan`
-- directly, because that local is declared here — far below that call site — so
-- a direct reference there would bind a global nil (see that block's note).
ChestAdvisor._armToastBaseline = function()
	-- Do not set toastSeenFirstScan back to false. Item-data events fire for
	-- a newly looted mail item as well as for the login cache warm-up. The
	-- warm-up stays silent because those links were recorded above; reopening
	-- the gate marked the new item told and skipped its toast.
end

-- U3/5 (card t_cf2ad83c): the release half of the combat hold, late-bound for the
-- same reason as _armToastBaseline above — the event frame's OnEvent closure is
-- declared far ABOVE this block, so it cannot capture these file-locals.
ChestAdvisor._releaseHeldToasts = releaseHeldToasts

-- U2 (card t_cf2ad83c): the tooltip renderer's own surface — the player-word
-- table, the detail setting and the row filter. Exposed the same way the toast's
-- state is (read-only from the outside; tests and /up diag read it, nothing in
-- the addon reaches it through this name). The renderer itself is called only
-- through the client's own tooltip hook.
ChestAdvisor.tooltipUI = TOOLTIP_UI
ChestAdvisor.tooltipLines = function(row) return verdictLines(row, nil) end

-- Test + slash diag access to the toast state (read-only snapshot).
ChestAdvisor.toastState = function()
	local told = 0
	for _ in pairs(toastedLinks) do told = told + 1 end
	return {
		enabled = toastIsEnabled(),
		queue = #toastQueue,
		shown = toastActive,
		dropped = toastDropped,
		told = told,
		fired = toastFired,
		-- U3 (card t_cf2ad83c): the behaviour the card added, read-only. These are
		-- for /up diag and the tests; the toast itself still carries no
		-- suppression/debug text on screen (AC-E2 of t_632f27e9).
		hovered = toastRT.hovered,
		lifetimeLeft = toastRT.lifetimeLeft,
		held = #toastRT.held,
		deferred = toastRT.deferred,
		-- t_4bae0617: the LIFETIME, measured. `lifetime` is what a show counts
		-- down from; `showMs` is how long the last show was actually on screen
		-- (nil until one has ended); `lastEnd` is how it ended. /up diag prints
		-- them so "it goes away too fast" becomes a number, not an impression.
		lifetime = toastLifetime(),
		showMs = toastRT.showMs,
		lastEnd = toastRT.lastEnd,
		-- t_fe7a636a: the trace switch and the repairs the fix performed.
		-- Read by /up diag only; nothing on the panel ever shows them.
		debug = TRACE.on,
		deadlineLeft = (toastActive and type(toastRT.deadline) == "number")
			and math.max(0, toastRT.deadline - TRACE.now()) or nil,
		revived = toastRT.revived or 0,
		alphaRestored = toastRT.alphaRestored or 0,
	}
end

-- ---- t_4bae0617: the deterministic test toast ---------------------------------
--
-- An upgrade toast otherwise needs a real bag item the scan happens to judge an
-- UPGRADE, which can take an hour of play — so nothing about its lifetime, fade
-- or dismiss behaviour could be checked on demand. `/up toasts` raises one
-- through the REAL path: the entry is queued exactly where a scan queues one and
-- drawn by showToastItem (no second renderer, no second queue), and the message
-- is built by buildToastMessage like any other show.
--
-- The synthetic entry carries NO link and NO item id, which is the point: the
-- icon falls back cleanly through the same `tex or TOAST_FALLBACK_ICON` the real
-- path uses, and buildToastMessage takes its documented fallback wording. It
-- touches NOTHING the scan owns — no toastedLinks (so the dedupe set is not
-- polluted), no ChestAdvisorDB.log (that is written only by a verdict), and no
-- baseline flag (toastSeenFirstScan is only ever set by maybeToastUpgrades).
--
-- Returns { started, queued, dropped }: the first call draws immediately, the
-- second while one is up JOINS THE QUEUE (a rotation, never a second panel), and
-- the tail past TOAST_MAX is a stated drop like the scan's own.
local TOAST_TEST_NAME = "Test Upgrade"
ChestAdvisor.testToast = function(n)
	n = tonumber(n) or 1
	if n < 1 then n = 1 end
	local started, queued, dropped = 0, 0, 0
	for _ = 1, math.floor(n) do
		local entry = { name = TOAST_TEST_NAME, test = true }
		-- The cap is the same one a scan batch obeys, so a tester cannot use
		-- this to grow a queue the real path could never grow.
		if #toastQueue >= TOAST_MAX then
			toastDropped = toastDropped + 1
			dropped = dropped + 1
		else
			toastQueue[#toastQueue + 1] = entry
			queued = queued + 1
			if not toastActive then
				showToastItem(table.remove(toastQueue, 1))
				queued = queued - 1
				started = started + 1
			end
		end
	end
	return { started = started, queued = queued, dropped = dropped }
end
ChestAdvisor._maybeToastUpgrades = maybeToastUpgrades
ChestAdvisor._toastIsEnabled = toastIsEnabled
end
-- Fold (MightiePack Touchstone module): the toast panel/frame is created by
-- Enable() on first enabled load, not at file load.
ChestAdvisor._initToastSurface = initToastSurface
end


-- ChestAdvisor.scan() — the entry point every event routes through.
--
-- Order of operations:
--   1. Build the spec (class token + player's role + documented order).
--   2. If the class is unknown, or is hybrid without a recorded role →
--      UNKNOWN on every in-scope item, with a reason pointing at the
--      slash pick.
--   3. Walk bags 0..4 (the reagent bag on slot 5 is out of scope here;
--      equipment lives in the normal bags in game).
--   4. For each visible item whose equipLocation is one of the nine
--      armour locations, ask the client whether this character can use
--      it (nil or false → UNKNOWN). Out-of-scope items (weapons, off-
--      hand, neck, finger, trinket, shirt, tabard, trade goods) are
--      skipped and counted in the walk ledger, NOT judged.
--   5. Compare against whatever is in the row's own worn slot (if any);
--      the worn link is pre-read once per slot before the walk.
--   6. Draw the marker for UPGRADE; explain the reason for every row.
-- Captured once, here, under the names scan already calls. These are the
-- function objects the surfaces published above, not live lookups.
-- Fold (load order): same reason as above — Enable() publishes these.
local function maybeToastUpgrades(...)
	local f = ChestAdvisor._maybeToastUpgrades
	if type(f) == "function" then return f(...) end
end
local function refreshQuestMarkers(...)
	local f = ChestAdvisor.refreshQuestMarkers
	if type(f) == "function" then return f(...) end
end
ChestAdvisor.scan = function()
	-- B17 (card t_6696b35a): defer the scan while the client is in combat.
	-- type() == "function" (not a bare `and` call) so this guard cannot be
	-- the same text as the toast hold below — that hold is a different
	-- decision and its own test. A missing InCombatLockdown means "not in
	-- combat": the scan runs. The flag is the whole record of the request;
	-- PLAYER_REGEN_ENABLED (getFrame's OnEvent) is what runs it.
	if type(InCombatLockdown) == "function" and InCombatLockdown() then
		ChestAdvisor._scanDeferred = true
		return ChestAdvisor.__verdicts or {}
	end
	ChestAdvisor._scanDeferred = nil
	ChestAdvisor._scanRuns = (ChestAdvisor._scanRuns or 0) + 1

	-- B17: one tooltip read per item link for THIS call. The same link is
	-- the candidate in several bag slots and the worn side of every row
	-- that compares against it. The lines are a function of the link, so a
	-- second read cannot change a verdict. The cache is a local: it dies
	-- with this call, including when the walk raises.
	local lineCache, lineReads, lineHits = {}, 0, 0
	local function cachedLines(link)
		if type(link) ~= "string" then
			lineReads = lineReads + 1
			return itemLines(link)
		end
		local hit = lineCache[link]
		if hit ~= nil then
			lineHits = lineHits + 1
			if hit == false then return nil end
			return hit
		end
		lineReads = lineReads + 1
		local lines = itemLines(link)
		if lines == nil then
			lineCache[link] = false
		else
			lineCache[link] = lines
		end
		return lines
	end

	local frame_ = getFrame()
	local verdicts = {}
	clearMarkers()

	local spec = buildSpec()
	local order = spec and spec.order
	local roleLabel = spec and spec.role or "class"

	-- (2) Class or hybrid-without-role: every in-scope item is UNKNOWN with a
	--     reason pointing at the slash pick.
	local classIsUnknown = (order == nil)

	-- E3 (AC-E1): pre-read *every* in-scope worn slot once, before the walk.
	-- The old code hard-wired slot 5 (chest) and the whole slot's tooltip read
	-- per item. This table is what the walk consults; nothing here touches a
	-- tooltip reader yet, so a nil for an empty slot is still nil — no
	-- fabricated zeros (AC-E4, gate 6).
	--
	-- Tier A (t_1c8e911b): the table is now KEYED BY THE WEAR SLOT INDEX
	-- (previously it was keyed by equip-location token). A token key cannot
	-- represent the TWO members of a finger/trinket pair — INVTYPE_FINGER
	-- appears twice (slots 11 and 12) and the second read would overwrite
	-- the first. Slot-index keys are the natural shared-side of both the
	-- single-scope and the pair-slot lookups; the walk below looks up by
	-- the row's own slot (for single scopes, EQUIP_SLOTS[loc]; for pairs,
	-- the weakest-of-pair pick). Nothing here is a rename — the table is
	-- internal to the scan.
	local wornLinks = {}
	if GetInventoryItemLink then
		-- The set of slots to read: every single-scope slot, plus BOTH pair
		-- members (11/12 and 13/14), deduplicated, plus slot 16 (main hand).
		--
		-- Slot 16 is NOT an in-scope slot and never becomes one: it is read
		-- here solely so the Tier B off-hand gate can see a two-hand
		-- commitment (G0 — a two-hander in the main hand means slot 17 reads
		-- nil, and a nil worn item is not an empty slot). Scope is decided by
		-- wornSlotFor(loc) below, which has no entry for slot 16, so the extra
		-- read adds no row and no skip count.
		local slots = {}
		local seen = {}
		for _, invSlot in pairs(EQUIP_SLOTS) do
			if not seen[invSlot] then slots[#slots+1] = invSlot; seen[invSlot] = true end
		end
		for _, pair in pairs(PAIR_SLOTS) do
			for _, invSlot in ipairs(pair) do
				if not seen[invSlot] then slots[#slots+1] = invSlot; seen[invSlot] = true end
			end
		end
		if not seen[16] then slots[#slots+1] = 16; seen[16] = true end
		for _, invSlot in ipairs(slots) do
			local link = GetInventoryItemLink("player", invSlot)
			if link ~= nil then
				wornLinks[invSlot] = link
			end
		end
	end

	-- Tier B (t_73e20edb): the off-hand gate's inputs, read ONCE per scan.
	--   offHandSpec  — the resolved spec (nil = unresolved -> G3 silence).
	--   mainHandLoc  — the WORN main-hand item's equip token (G0 detector).
	--   wornOffLoc   — the WORN slot-17 item's equip token (G4 comparator).
	-- All three are plain values by the time the walk starts, so the gate
	-- itself stays pure and the walk stays a single pass.
	local offHandSpec = nil
	local mainHandLoc = nil
	local wornOffLoc  = nil
	if Verdict and type(Verdict.offHandGate) == "function" then
		-- The CLASS is always available (UnitClass) and is always passed: even
		-- when the spec read fails, the gate must still be able to see that this
		-- is a Hunter and step aside, rather than report a G3 "no specialization
		-- resolved" for a character who cannot wear a shield in the first place.
		-- Only the ROLE comes from the (untrusted) spec read; the class and its
		-- display name come from UnitClass via readOffHandSpec, which also
		-- carries the class display name Verdict.substantiated compares the
		-- spec name against (card t_548f0341).
		offHandSpec = readOffHandSpec()
		local ml = wornLinks[16]
		if ml then mainHandLoc = equipLocation(itemIDOf(ml)) end
		local ol = wornLinks[17]
		if ol then wornOffLoc = equipLocation(itemIDOf(ol)) end
	end

	-- E3 (scope 3 / AC-E9): the walk ledger. AC-E9 requires reporting
	-- "items walked" and "items in scope" as two distinct numbers —
	-- itemsScanned is the total bag cells the walk inspected (in scope
	-- or not); itemsWalked is the in-scope subset that produced a
	-- verdict; perSkip maps an out-of-scope equip-location token to the
	-- count skipped at that token (the whole point of the player's
	-- ruling: the token is what identifies WHY something was skipped —
	-- an INVTYPE_NECK skip and an INVTYPE_WEAPON skip are different
	-- skips and both must be named). capDropped counts UPGRADE items
	-- that hit the MARKER_MAX cap and were silently dropped (scope 5 —
	-- the cap stays at 64, the count is new). This ledger is the
	-- canonical record the AC-E9 diag print surfaces; a 0 itemsWalked
	-- with a non-zero bag is exactly how a regression to "everything is
	-- a chest" gets caught.
	local itemsScanned = 0
	local itemsWalked  = 0
	local perSkip      = {}
	local capDropped   = 0

	-- R10/AC20 (§7a part 3): publish the record BEFORE the render path.
	-- The bag walk calls makeMarker() (Render). Verdicts is a table reference;
	-- populating it by reference means any consumer reading
	-- ChestAdvisor.__verdicts (buildDiag, tests, slash diag) sees every row
	-- even if makeMarker raises on an individual item. Publishing after the
	-- walk (the pre-fix behaviour) means a raise inside makeMarker skips the
	-- assignment entirely (it's in the same scan body, not a separate
	-- function) — __verdicts keeps its previous value and buildDiag sees an
	-- empty table, which is exactly what session-1 captured (["verdicts"]={}
	-- ["rows"]={} sv-longhairs-1-reload.lua:16-20). A pcall around makeMarker
	-- alone stops the throw but does NOT fix this ordering.
	ChestAdvisor.__verdicts = verdicts

	-- (3) bag walk
	for bag = 0, 4 do
		local count = 0
		if C_Container and C_Container.GetContainerNumSlots then
			local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
			if ok and type(n) == "number" then count = n end
		end
		for slot = 1, count do
			local info
			if C_Container and C_Container.GetContainerItemInfo then
				local ok, i = pcall(C_Container.GetContainerItemInfo, bag, slot)
				if ok then info = i end
			end
			if info and type(info) == "table" then
				local link = info.hyperlink
				local id   = info.itemID or itemIDOf(link)
				local loc  = equipLocation(id)
				local equippedLink = false
				if type(link) == "string" then
					for _, wlink in pairs(wornLinks) do
						if wlink == link then equippedLink = true break end
					end
				end
				if link and id and type(id) == "number" then
					-- Every cell with a resolvable item id is "walked" in the
					-- AC-E9 sense — the total the walk inspected, before any
					-- scope split. The in-scope subset is itemsWalked, the
					-- out-of-scope split is perSkip.
					itemsScanned = itemsScanned + 1
				end
				-- E3 (AC-E1): in-scope iff the item's equipLocation is a key of
				-- EQUIP_SLOTS. Pre-Tier A that was the nine armour locations and
				-- everything else (weapons, off-hand, neck, finger, trinket,
				-- shirt, tabard, trade goods, reagents) was skipped, NOT judged.
				-- Tier A (t_1c8e911b) pulled neck (slot 2) and the finger / trinket
				-- pairs (slots 11/12, 13/14) in; the rest remains skipped: the old
				-- `loc == "INVTYPE_CHEST"` is exactly the chest-only false negative
				-- this card removes.
				local invSlot = wornSlotFor(loc)
				if not invSlot then
					-- Out of scope: count it so a regression to "everything is a
					-- chest/is a chest" is still visible (AC-E9 ledger). The token
					-- is what identifies the skip: an INVTYPE_NECK item is a neck
					-- skip, an INVTYPE_WEAPON is a main-hand weapon skip, etc.
					if link and id and type(id) == "number" and loc then
						perSkip[loc] = (perSkip[loc] or 0) + 1
					end
				end
				-- An item that is already worn is not a bag candidate. If the
				-- container API also returns it while the worn-link read is
				-- empty, judging it would call the equipped piece an upgrade
				-- for the slot it fills.
				if link and invSlot and id and type(id) == "number" and not equippedLink then
					itemsWalked = itemsWalked + 1
					local v, reason
					local canUseV
					local ulevel = (UnitLevel and UnitLevel("player")) or nil
					-- Card t_119d120c: every judged row's lines come from the
					-- ONE item reader. A third-party annotation on the rendered
					-- GameTooltip (RXPGuides' "Item used in guide: ...") is now
					-- neither read nor a suppression: the structured read is the
					-- client's own read of the ITEM, and carries none of it.
					local lines = cachedLines(link)
					-- E3 (AC-E1): read the worn link for THIS row's slot once here
					-- (not per branch, and not the hard-wired slot 5). The robe case:
					-- equipped slot is slot 5 for both INVTYPE_CHEST and INVTYPE_ROBE,
					-- but we look up by the row's own slot (single-scope) — slot 5 for
					-- both robe and chest. For pair scopes (Tier A, t_1c8e911b) the
					-- lookup asks for the WEAKEST pair member; see the pick below.
					local wornLink
					local pair = PAIR_SLOTS[loc]
					if pair then
						-- Tier A (AC-C): an EMPTY pair member is a legitimate free
						-- upgrade — the row's verdict compares the candidate against
						-- nil (an empty slot), which reads UPGRADE via Verdict gate 6.
						local s1, s2 = pair[1], pair[2]
						local l1, l2 = wornLinks[s1], wornLinks[s2]
						if not l1 or not l2 then
							-- Empty member: the pick is nil and the row reads UPGRADE
							-- via the "no <word> equipped" reason (gate 6, rewritten
							-- below to name the role's slot word).
							wornLink = nil
						else
							-- Both members present: pick the WEAKER worn member to
							-- compare against. The candidate's verdict does NOT need
							-- to decide this — we ask the spec'd comparator "is
							-- member-1 strictly better than member-2?" (using the
							-- SAME role-aware spec the row's final verdict uses, so
							-- no numeric weight is invented, no class is assumed,
							-- and unknown words read UNKNOWN end-to-end).
							local v12, _ = Verdict.evaluate(
								{ canUse = true, line = cachedLines(l1) },
								{ line = cachedLines(l2) },
								spec
							)
							-- v12 == "UPGRADE" means member-1 is strictly better than
							-- member-2 along the role's stat order (or wins the Armor
							-- tiebreak) → member-2 is the weaker. Otherwise member-1
							-- is the weaker (or indistinguishable — the row's final
							-- verdict against it will carry the UNKNOWN through).
							if v12 == "UPGRADE" then
								wornLink = l2
							else
								wornLink = l1
							end
						end
					else
						-- Single scope: the row's own slot (EQUIP_SLOTS[loc]).
						wornLink = wornLinks[invSlot]
					end
					local wornLines = wornLink and cachedLines(wornLink) or nil
					-- Tier B (t_73e20edb), §5: the off-hand gate runs BEFORE the
					-- comparator and before the empty-slot shortcut. Its declines
					-- are structural — a two-hander closing the slot (G0), an
					-- unresolved spec (G3), a main-hand-only candidate (G5), a
					-- different off-hand class on the two sides (G4) — so they
					-- must not be reachable by the generic "slot is empty, so
					-- this fills it" UPGRADE. Every decline is a named reason with
					-- NO marker (the marker branch below is reached only when
					-- v == "UPGRADE", and a decline never returns UPGRADE).
					-- The gate returns nil for every non-off-hand row: scope is
					-- decided by EQUIP_SLOTS, not here.
					-- Tier C (t_b058b5df): the WEAPON family is judged on
					-- tooltip-read DPS, not on the armour stat order.
					-- INVTYPE_WEAPONOFFHAND is deliberately NOT a weapon row
					-- here — it stays on Tier B's off-hand path below (AC-D:
					-- "do not invent a second policy"). `loc` is a weapon
					-- token iff it is a key of Verdict.WEAPON_TOKENS.
					local isWeaponRow = Verdict
						and type(Verdict.WEAPON_TOKENS) == "table"
						and Verdict.WEAPON_TOKENS[loc] == true
					local offHandDecline = nil
					if not isWeaponRow and Verdict
						and type(Verdict.offHandGate) == "function" then
						offHandDecline = Verdict.offHandGate(loc, wornOffLoc, mainHandLoc, offHandSpec)
					end
					if isWeaponRow then
						-- The weapon read is the SAME reader every other
						-- path uses (card t_119d120c): C_TooltipInfo
						-- .GetHyperlink, positionally walked. The DPS
						-- comparator reads numbers the client prints; no
						-- stat weight is involved (AC-G).
						local wlines = cachedLines(link)
						lines = wlines
						wornLines = wornLink and cachedLines(wornLink) or nil
						local candNumbers = Verdict.weaponNumbers(wlines)
						local wornNumbers = wornLink
							and Verdict.weaponNumbers(wornLines) or nil
						-- D1 (Vera round 1): does this row's worn slot
						-- actually HOLD something? `wornLink` is the
						-- caller's fact -- non-nil means the slot is
						-- FILLED, so "no readable numbers" there is an
						-- unreadable item (UNKNOWN), not an empty slot
						-- (a legitimate fill). This is the distinction the
						-- pre-fix comparator tried to draw from
						-- `next(wornNumbers)`, which cannot work because
						-- wornNumbers is nil in BOTH cases.
						local wornSlotFilled = wornLink ~= nil
						-- W0/W1 — the §5.1 shape rules. A named decline, or
						-- nil to judge normally. The class token is always
						-- available (UnitClass); the off-hand token comes from
						-- the pre-read.
						local wdecline = nil
						if type(Verdict.weaponGate) == "function" then
							wdecline = Verdict.weaponGate(loc, wornOffLoc, offHandSpec)
						end
						if wdecline ~= nil then
							v, reason = "UNKNOWN", wdecline
						else
							canUseV = canUse(id)
							if canUseV ~= true then
								-- Hard eligibility precedes the DPS compare,
								-- exactly as on the armour path. A false, nil
								-- or secret answer is silence — never a
								-- fabricated UPGRADE (AC-C).
								v = "UNKNOWN"
								if canUseV == false then
									reason = "this character cannot use this weapon"
								elseif type(issecretvalue) == "function"
									and issecretvalue(canUseV) then
									reason = "the client returned the secret-value sentinel"
								else
									reason = "the client could not classify this weapon"
								end
							else
								v, reason = Verdict.compareDPS(candNumbers, wornNumbers, wornSlotFilled)
							end
						end
					elseif offHandDecline ~= nil then
						v, reason = "UNKNOWN", offHandDecline
					elseif classIsUnknown then
						v = "UNKNOWN"
						if order == nil and (not type(roleLabel) or roleLabel == "class") then
							reason = "no role resolved for this class (the client spec read gave no usable role); run /upgrade role <melee|spell>"
						else
							reason = "no stat order resolved for this character"
						end
					else
						canUseV = canUse(id)
						-- E3 (AC-E4): Verdict.lua gate 6 (frozen this slice) returns
						-- the constant "no chest equipped; this item would fill the
						-- slot"; re-write that sentinel to this row's own slot word
						-- so empty legs read "no legs equipped; …". Only the gate-6
						-- shape is rewritten; every other reason passes through.
						local EMPTY_SLOT_SENTINEL = "no chest equipped; this item would fill the slot"
						local v2, r2 = Verdict.evaluate(
							{ canUse = canUseV, line = lines },
							{ line = wornLines },
							spec,
							-- Card t_548f0341 (Defect 2): the client's own
							-- stat read for both sides; nil when the API
							-- cannot read them (fail-closed, unchanged).
							apiBySideOf(id, wornLink and itemIDOf(wornLink) or nil)
						)
						v, reason = v2, r2
						if reason == EMPTY_SLOT_SENTINEL then
							reason = "no " .. slotWord(invSlot) .. " equipped; this item would fill the slot"
						end
					end
					if type(v) == "string" and type(reason) == "string" then
						verdicts[link] = {
							bag = bag, slot = slot, id = id,
							verdict = v,
							reason = reason,
							role = roleLabel,
							-- The richer diag row (t_9ad3d462 part 3): everything plan s4
							-- PASS/FIX/KILL grades from, per item. Raw stat lines (<=30, already
							-- capped by TooltipLines), raw CanUseItem type+value, the player level
							-- and the character class token. UPGRADE rows gain anchorDiag from
							-- anchorMarker below; probes P1/P2/P5 read the same values, one site.
							canUse = canUseV,
							canUseType = type(canUseV),
							level = ulevel,
							class = classToken(),
							lines = lines,
							-- Tooltip surface (card t_ed71a583): the worn item's LINK
							-- for THIS row, so the tooltip's "vs <equipped>" clause can
							-- name the item the verdict was decided against. Nothing
							-- else reads it; nil on an empty slot (including the empty
							-- member of a finger/trinket pair), which is exactly the
							-- state the delta line must stay silent about.
							wornLink = wornLink,
							-- E3 (scope 7): the key name is legacy from the chest-only
							-- era of the scan. Its value is now "the raw worn-side
							-- lines for THIS row's own slot" — read from wornLinks[loc]
							-- (the row's own equip-location row, not slot 5). For a
							-- chest row the value is identical to the pre-E3 behaviour;
							-- for a legs row it is the legs slot's worn lines, etc.
							-- The key name is preserved verbatim (zero churn; no sibling
							-- keys added) per this card's scope item 7.
							chestWornLines = wornLines,
							-- E3 (scope 3): the row's own slot info, so the diag print
							-- and AC-E4 reason can name it. Not a rename — new fields
							-- on top of the preserved legacy key.
							equipLoc = loc,
							invSlot = invSlot,
							slotWord = slotWord(invSlot),
							-- Tier B (Lena §6): the spec bucket for this character
								-- ("required" / "allowed" / "irrelevant"). Recorded on
								-- OFF-HAND rows only — it is that slot's policy, and on
								-- every other row the field would be noise a reader
								-- would have to learn to ignore. nil means the policy
								-- could not be resolved, which is itself the G3 answer.
								-- Card t_548f0341 (Defect 1): recorded BESIDE whether
								-- the identity was substantiated, so a refusal stays
								-- auditable and the owner can see what a higher-level
								-- character (a real spec name) reports. NOTE: written
								-- as an explicit block, not `x and false or nil` —
								-- that idiom collapses a `false` answer to nil, which
								-- would erase the very distinction this field exists
								-- to record.
								shieldPolicy = (invSlot == 17
									and Verdict and type(Verdict.shieldPolicy) == "function")
									and (Verdict.shieldPolicy(offHandSpec) or "unresolved") or nil,
								specSubstantiated = (function()
									if invSlot ~= 17 then return nil end
									if not (Verdict and type(Verdict.substantiated) == "function") then
										return nil
									end
									return Verdict.substantiated(offHandSpec or {})
								end)(),
							}
						local diagRow = verdicts[link]
						if canUseV ~= nil and canUseV ~= true and canUseV ~= false then
							diagRow.canUseString = tostring(canUseV)
						end
						-- The marker is the PRIMARY outcome — and only a marker
						-- that is actually pinned to its visible slot can BE the
						-- outcome. anchorMarker decides based on what the client
						-- exposes for this (bag, slot) pair: visible item button
						-- → pin + show; absent/hidden → suppress (the created-
						-- but-hidden frame carries the diagnostic).
						-- Pool-allocate as before: markerNext indexes into markerPool
						-- so two scans (or two slots) never collide on the same
						-- pool slot; #markerPool is the count of frames created so
						-- far and the pool can grow past the active count after
						-- a clear (frames are reused, not recreated, which is
						-- the point of a pool).
						-- E3 (scope 5): the cap stays 64; what changes is the silence.
						-- Previously a UPGRADE row past the cap got no marker and no
						-- reason — the player could not tell it apart from a bug.
						-- Now the row keeps its UPGRADE verdict, the marker is still
						-- not created (the cap is the cap), and capDropped increments
						-- so the walk ledger in the scan tail names the count. The
						-- reason text is unchanged; the diag record (via verdicts[link],
						-- the table reference) carries the count for /up diag.
						-- Card t_89440dfa: BOTH marks ride this ONE branch — the
						-- green arrow for UPGRADE and the amber chip for TRADE_OFF.
						-- anchorMarker draws whichever the frame's own __verdict
						-- names, so there is no second mark path and no second cap.
						if v == "UPGRADE" or v == TRADE_OFF_VERDICT then
							if markerNext < MARKER_MAX then
								markerNext = markerNext + 1
								-- Card t_e9a07624 (B4): pass the ROW's own slot
								-- word down, so the hover cannot invent "chest".
								-- verdicts[link].slotWord was written a few lines
								-- above from this row's own invSlot.
								local slotWordText = slotWord(invSlot)
								local f = makeMarker(markerNext, link, v, reason, roleLabel, slotWordText)
								local anchored = anchorMarker(f, bag, slot, link, slotWordText)
								-- Attach the anchor diagnostic to the verdict so
								-- /upgrade diag and the tests can explain "why
								-- is this row's marker shown / suppressed."
								if anchored and type(f.__anchorDiag) == "string" then
									verdicts[link].anchorDiag = f.__anchorDiag
								end
							else
								-- Cap hit: the slot stays eligible (verdict is still
								-- UPGRADE); only the marker is not pinned. Count the
								-- drop so the ledger can state it.
								capDropped = capDropped + 1
								verdicts[link].capDropped = true
							end
						end
					end
				end
			end
		end
	end

	-- (6) expose the verdicts table so the slash diag and the tests can
	--     walk it by link.  Note: the same-reference assignment
	--     `ChestAdvisor.__verdicts = verdicts` already happened BEFORE the
	--     bag walk (the §7a part 3 ordering fix, see above) — the tail only
	--     re-sets the diag snapshot, which is genuinely post-walk (it depends
	--     on the final `verdicts` content and the walk's own GetTime stamp).
	if not ChestAdvisor.diag then
		ChestAdvisor.diag = {}
	end
	ChestAdvisor.diag.verdicts = verdicts
	ChestAdvisor.diag.lastScanTime = GetTime and GetTime() or (STUB and STUB.now)

	-- E3 (scope 3): the walk ledger is persisted here as the canonical
	-- record the AC-E9 diag print reads. A reader must be able to answer
	-- "why did this item produce no marker?" from this ledger alone —
	-- per-equip-location skip counts are the whole point of the player's
	-- ruling (the token is what identifies WHY an item was skipped). The
	-- capDropped field is scope item 5: the cap stays (64), but how many
	-- UPGRADE items it silently dropped is now stated instead of hidden.
	ChestAdvisor.diag.ledger = {
		itemsScanned = itemsScanned,
		itemsWalked  = itemsWalked,
		perSkip      = perSkip,
		capDropped   = capDropped,
		classState   = classIsUnknown and "unknown" or "class",
		role         = roleLabel,
	}

	-- B15 (card t_6696b35a): do not rewrite probe.scanRaw.
	--
	-- The per-scan tooltip dump was the self-serving record for the tank
	-- vocabulary card (t_89440dfa). That card has landed; the lines it needed
	-- still live on the in-memory verdict row, and /up diag persists them
	-- once (see buildDiag). Copying them into ChestAdvisorDB.probe.scanRaw on
	-- every scan was the bulk of the per-character SavedVariables file.
	--
	-- An ordinary scan leaves the key unset, and clears one a previous build
	-- already loaded, so the next logout does not write the blob back. The
	-- rest of .probe (a /up probe record, the R9 takenAt) is not replaced.
	--
	-- This nils a KEY inside the live table. It does not delete any
	-- SavedVariables file, including an orphaned per-character ChestAdvisor.lua
	-- left from when the advisor was its own addon.
	if type(ChestAdvisorDB) == "table" and type(ChestAdvisorDB.probe) == "table" then
		ChestAdvisorDB.probe.scanRaw = nil
	end
	ChestAdvisor._scanCache = { reads = lineReads, hits = lineHits }

	-- Toast (t_632f27e9): consume the SAME verdict set the marker reads. This
	-- inherits the scan's hard eligibility gate in full — only rows already
	-- judged UPGRADE are considered, and an item the character cannot use never
	-- reaches UPGRADE (AC-E2). Pure presentation; no evaluation here.
	maybeToastUpgrades(verdicts)

	-- Quest reward arrows (t_c3fe7d1d): a SECOND input surface. Its own refresh
	-- walks the reward frame's buttons through the SAME comparator and draws the
	-- bag arrow on each UPGRADE. Refreshing here keeps the quest surface current
	-- on an ordinary rescan too; the quest events + frame hooks are what keep it
	-- current when only the reward panel re-renders.
	refreshQuestMarkers()

	-- U4 (card t_c01331a2): the character-pane hint. Pure PRESENTATION over the SAME
	-- verdict set the bag marker just rebuilt — it reads ChestAdvisor.__verdicts and
	-- adds no evaluation. Refreshed here so a rescan (bag churn, an equip, a login)
	-- also updates the pane while it is open; the pane's own OnShow hook and the
	-- scan-event path below cover the "only the pane changed" case.
	if type(ChestAdvisor.refreshPaperDollHints) == "function" then
		ChestAdvisor.refreshPaperDollHints()
	end

	-- U5 (card t_c01331a2): the vendor surface. Its own refresh, scheduled from the
	-- merchant events and the merchant frame's OnShow; re-run here so an ordinary
	-- rescan cannot leave a vendor mark pointing at a stale verdict.
	if type(ChestAdvisor.refreshVendorMarkers) == "function" then
		ChestAdvisor.refreshVendorMarkers()
	end

	return verdicts
end

-- Test + slash diag access.
ChestAdvisor.getVerdicts = function()
	return ChestAdvisor.__verdicts or {}
end

ChestAdvisor.roleFor = function(token)
	if type(token) ~= "string" then return nil end
	local r = ChestAdvisorDB and ChestAdvisorDB.role and ChestAdvisorDB.role[token]
	if type(r) == "string" then return r end
	if type(r) == "table" and type(r.role) == "string" then return r.role end
	return nil
end

-- The disagreement log and the slash handler are their own scope so
-- their locals do not sit in the main chunk (Lua 5.1 caps it at 200).
do
local function initLogAndSlash()
local toastIsEnabled = ChestAdvisor._toastIsEnabled
local maybeToastUpgrades = ChestAdvisor._maybeToastUpgrades
-- ---- #5 Disagreement log (t_bc9c69d3) ---------------------------------------
--
-- WHAT THIS IS. Touchstone judges every in-scope item and never learns whether
-- it was right. When the player PUTS ON an item the advisor did not call
-- UPGRADE, that is the strongest signal available: he disagreed with it. Those
-- cases are the concrete input the future "real Prot order" card needs — real
-- logged examples instead of a theorised weight table.
--
-- READ-ONLY BY CONSTRUCTION. This records; it does not judge. It reads the
-- scan's own in-memory verdict set (`ChestAdvisor.__verdicts`, rebuilt each
-- scan at :2534) and writes ONLY `ChestAdvisorDB.log`. It registers no frame,
-- triggers no scan, and mutates no verdict row (AC-G).
--
-- ORDERING (load-bearing). The lookup happens on the PLAYER_EQUIPMENT_CHANGED
-- EVENT, before the event's own `ChestAdvisor.scan()` runs (the OnEvent arm in
-- getFrame). That ordering is what makes the lookup see the PRE-equip verdict:
-- the item was in the bag, was judged, and — when the scan is a login scan —
-- __verdicts still holds the previous scan's row for it. If the record ran
-- after the rescan, the equipped item would already be out of the bag and its
-- row gone.
--
-- THE LOGIN CAVEAT, stated honestly. On the FIRST login of a session
-- __verdicts is empty (the scan has not run yet), so a player who logs in
-- wearing gear triggers no entry — there is nothing to compare against.
-- __verdicts then survives until the next scan. A scan runs on every login,
-- zone-in, bag update and equip change, so by the time the player equips
-- anything the previous scan's rows are in hand. The gap is narrow and, when
-- hit, the code logs NOTHING and says so in the comment — it never invents a
-- verdict, never logs UNKNOWN as if it were a judgement, and never forces a
-- scan just to fill the log (AC-B).
--
-- BOUNDED (AC-C): a ring buffer on COUNT, cap 50, oldest dropped first. This
-- is the codebase's own DIAG_HISTORY pattern (:2996/:3042) applied to a longer
-- list. The cap holds even when the SAME link is equipped repeatedly: the
-- "already the newest entry" check below suppresses a run of identical
-- consecutive entries (drag an item on and off, or swap a pair), so a burst of
-- one item cannot evict real disagreements — while two DIFFERENT disagreements
-- on the same link, separated by another, are both kept.

local LOG_CAP = 50                 -- ring buffer length; oldest dropped first

-- Card t_e9a07624 (B6): which verdicts are DISAGREEMENTS. "Agreement is not a
-- disagreement" is not the only exclusion — an UNKNOWN is not a CALL the player
-- overrode, it is "Touchstone could not judge this". The pre-fix predicate
-- skipped only UPGRADE, so the owner's own SavedVariables recorded a
-- `Bow of Plunder` row with verdict=UNKNOWN and reason "not judged: a two-handed
-- weapon takes your off-hand" — a refusal, filed as evidence that he disagreed.
-- That pollutes the exact corpus this log exists to collect. Only a NAMED
-- negative — NOT_UPGRADE or TRADE_OFF — is a disagreement; anything else
-- (UNKNOWN, or a verdict the comparator has not produced yet) is not logged.
local function isDisagreement(verdict)
	return verdict == "NOT_UPGRADE" or verdict == TRADE_OFF_VERDICT
end

-- Card t_e9a07624 (B6): the timestamp, made meaningful. The old entry carried
-- `time = GetTime()`, which is SECONDS SINCE THE CLIENT STARTED — it resets
-- every session, so the owner's live entry read `t=843551.62`, a number that
-- says nothing about when it happened. The log now stores BOTH: `time` keeps the
-- monotone session clock (ordering, and the field the existing tests read), and
-- `at` is the wall-clock epoch (`time()`), which is what a human reads. The
-- PRINTED form below renders `at` through `date()`, with a session-clock
-- fallback only when that GetTime value belongs to the client session that
-- is running now. A number left over from before the last reload is not an age.
local function wallClock()
	if type(time) == "function" then
		local ok, t = pcall(time)
		if ok and type(t) == "number" then return t end
	end
	-- Forever's classic client does not expose os.time (`time` is nil). The
	-- server clock is the WoW API that is present on Classic Era.
	local getServer = rawget(_G, "GetServerTime")
	if type(getServer) == "function" then
		local ok, t = pcall(getServer)
		if ok and type(t) == "number" then return t end
	end
	return nil
end

-- UTC civil date from a unix timestamp, for a client whose `date` is nil.
-- Howard Hinnant's civil_from_days. Month-day hour:minute, same shape as
-- date("%m-%d %H:%M").
local function formatUnix(ts)
	ts = math.floor(ts)
	local z = math.floor(ts / 86400) + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524)
		- math.floor(doe / 146096)) / 365)
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local d = doy - math.floor((153 * mp + 2) / 5) + 1
	local m = mp + (mp < 10 and 3 or -9)
	local sod = ts % 86400
	if sod < 0 then sod = sod + 86400 end
	local hh = math.floor(sod / 3600)
	local mm = math.floor((sod % 3600) / 60)
	return string.format("%02d-%02d %02d:%02d", m, d, hh, mm)
end

local function formatSession(sec)
	sec = math.floor(sec)
	if sec < 0 then sec = 0 end
	local m = math.floor(sec / 60)
	local h = math.floor(m / 60)
	m = m % 60
	if h > 0 then return string.format("session %dh%02dm", h, m) end
	return string.format("session %dm%02ds", m, sec % 60)
end

-- Format a stored entry's wall clock for the player. `date`/`time` are the
-- os library and are nil on this Forever client, which is why every row used
-- to read "no wall clock". Prefer a real timestamp. The `time` field is
-- GetTime — seconds since this client process started, reset by /reload —
-- so it is only an age when it still falls inside the clock that is running
-- now. A value saved in an earlier process (the pre-0.8.1 rows whose stored
-- uptime is hundreds of hours) prints "earlier", not "session 230h23m".
local function formatEntryTime(when, session)
	if type(when) == "number" then
		if type(date) == "function" then
			local ok, s = pcall(date, "%m-%d %H:%M", when)
			if ok and type(s) == "string" and s ~= "" then return s end
		end
		local ok, s = pcall(formatUnix, when)
		if ok and type(s) == "string" and s ~= "" then return s end
	end
	if type(session) == "number" then
		local now = nil
		if type(GetTime) == "function" then
			local ok, t = pcall(GetTime)
			if ok and type(t) == "number" then now = t end
		end
		if type(now) == "number" and session >= 0 and session <= now + 1 then
			return formatSession(session)
		end
		return "earlier"
	end
	return "no wall clock"
end

-- The log store on the per-character DB. Same shape as ChestAdvisorDB.role /
-- .toast / .tooltip — no new store, no new declaration; ChestAdvisorDB is
-- already SavedVariablesPerCharacter (Touchstone.toc:7).
local function logStore()
	if type(ChestAdvisorDB) ~= "table" then return nil end
	local log = ChestAdvisorDB.log
	if type(log) ~= "table" then
		log = {}
		ChestAdvisorDB.log = log
	end
	return log
end

-- Is the newest entry already this exact disagreement? Used to collapse a run
-- of identical consecutive entries (same link, same slot, same verdict) into
-- one — see the BOUNDED note above for why that is the right dedupe and not a
-- blanket "seen this link" set.
local function logHasNewest(log, link, slot, verdict)
	local n = #log
	local last = n > 0 and log[n] or nil
	return type(last) == "table"
		and last.link == link and last.verdict == verdict and last.slot == slot
end

-- Record ONE disagreement, if this worn link has a NAMED negative row.
local function logOne(slot, link)
	if type(slot) ~= "number" or type(link) ~= "string" then return end

	-- The scan's own row for this exact link — the same key the scan writes
	-- with (verdicts[link] = {…} at :2736). Absent (login-before-first-scan,
	-- or an item picked up since the last scan) → log NOTHING.
	local row = ChestAdvisor.__verdicts and ChestAdvisor.__verdicts[link]
	if type(row) ~= "table" then return end
	local verdict = row.verdict
	if type(verdict) ~= "string" then return end
	-- B6: only a NAMED negative is a disagreement. UPGRADE is agreement;
	-- UNKNOWN is "could not judge" — neither is the player overriding a call.
	if not isDisagreement(verdict) then return end

	local log = logStore()
	if not log then return end
	if logHasNewest(log, link, slot, verdict) then return end

	-- The eight fields, every one from an existing source. `role` off the
	-- scan's own row (written at :2740 from roleLabel); `roleSource` from the
	-- SAME resolver the scan/diag use — resolvedRole — never recomputed,
	-- never defaulted. `time` from GetTime() is the codebase's monotone session
	-- clock (kept for ordering and for the existing readers); `at` (card
	-- t_e9a07624, B6) is the wall-clock epoch, which is the field a human reads.
	-- `slotName` (B6) is the SLOT WORD the player knows ("chest", "main hand"),
	-- read from the row's own equipment location — the same source the hover
	-- uses — so a listing says "main hand", not "18".
	--
	-- NOTE the two-name capture: resolvedRole returns (word, source), and
	-- wrapping the call in parentheses would silently take only the first
	-- return, putting the ROLE WORD in roleSource. It must be a multi-assign.
	local _, roleSource = resolvedRole(classToken())
	table.insert(log, {
		time       = (GetTime and GetTime()) or (STUB and STUB.now) or 0,
		at         = wallClock(),
		slot       = slot,
		slotName   = slotWord(wornSlotFor(equipLocation(itemIDOf(link)))),
		link       = link,
		verdict    = verdict,
		reason     = row.reason,
		role       = row.role,
		roleSource = roleSource,
	})
	while #log > LOG_CAP do table.remove(log, 1) end
end

-- The previous equip event's worn set, used ONLY on the payload-less path
-- below. Session state, never persisted: it is a diff baseline, not a record.
local lastWorn = nil

-- Record the disagreement for a newly worn slot, if there is one.
--
-- PRIMARY PATH — `changedSlot` is the event's own equipmentSlot payload (the
-- INVSLOT_* the client says changed; PaperDollInfoDocumentation.lua:386,
-- payload equipmentSlot/hasCurrent). That is the authoritative answer to
-- "which slot", so we read the link straight from it.
--
-- FALLBACK PATH — if the event carries no payload (an older build, or any
-- caller that fires the event bare), we diff the whole worn set against the
-- previous event's snapshot and treat every changed slot as newly worn. This
-- exists so the feature cannot silently record nothing in game just because a
-- client omits the payload. When there is no baseline yet (the first equip
-- event of a session) the snapshot is taken WITHOUT logging — the same "no
-- login wall" choice the toast makes — so a login equip does not mis-record
-- everything already worn.
local function logDisagreement(changedSlot)
	if not GetInventoryItemLink then return end
	if type(changedSlot) == "number" then
		local ok, link = pcall(GetInventoryItemLink, "player", changedSlot)
		if ok then
			logOne(changedSlot, link)
			-- Keep the diff baseline coherent when one exists, so a later
			-- payload-less fire never diffs against a stale snapshot and
			-- reports a phantom "newly worn". O(1); nil when the slot was
			-- emptied (a removal is not an equip).
			if type(lastWorn) == "table" then
				lastWorn[changedSlot] = type(link) == "string" and link or nil
			end
		end
		return
	end
	-- 1..19: the client's INVSLOT_* range (NUM_INVSLOTS, see the stub's own
	-- note on the camelot character frame's 20 slot buttons).
	local now = {}
	for slot = 1, 19 do
		local ok, link = pcall(GetInventoryItemLink, "player", slot)
		if ok and type(link) == "string" then now[slot] = link end
	end
	if type(lastWorn) == "table" then
		for slot, link in pairs(now) do
			if lastWorn[slot] ~= link then logOne(slot, link) end
		end
	end
	lastWorn = now
end
ChestAdvisor._logDisagreement = logDisagreement

-- Read surface + test access.
ChestAdvisor.getLog = function()
	return ChestAdvisorDB and ChestAdvisorDB.log or nil
end

ChestAdvisor.formatLogStamp = function(entry)
	if type(entry) ~= "table" then return formatEntryTime(nil, nil) end
	return formatEntryTime(entry.at, entry.time)
end

-- ---- Slash commands ----------------------------------------------------------
local function helpText()
	return "Touchstone — item upgrade advisor (head, shoulders, chest, back, wrists, hands, waist, legs, feet, neck, finger, trinket, off hand; weapons judged on tooltip DPS)\n"
		.. "  /ts opens the window (aliases: /up = /upgrade = /chestadvice = /ts)\n"
		.. "  /ts help       this help\n"
		.. "  /ts scale <0.5-1.5>  window scale (also the Settings slider; saved across /reload)\n"
		.. "  A green arrow marks an upgrade. An amber square marks a trade-off (better on some stats, worse on others). On the character sheet the arrow means a bag item is an upgrade for that slot.\n"
		.. "  /up role <r>   record the focus role for a hybrid class (melee|spell; the client spec read is used automatically when unset)\n"
		.. "  /up role clear clear the recorded role for this class\n"
		.. "  /up probe      run the Phase D probes P0/P1/P2/P5 (read-only)\n"
		.. "  /up toast <on|off>  turn the \"Upgrade found!\" toast on or off (persisted; default on)\n"
		.. "  /up toasts / /up testtoast  raise one \"Test Upgrade\" toast NOW — the real panel and the real\n"
		.. "                 queue, so its lifetime, fade and right-click dismiss can be checked without\n"
		.. "                 waiting for a real upgrade. Run it twice to see the rotation. /up diag reports\n"
		.. "                 how many fired and how long the last one was actually on screen.\n"
		.. "  /up toastdebug [on|off|dump]  print every transition of one toast with GetTime stamps\n"
		.. "                 (off by default; /up toasts raises one, dump prints the last lines)\n"
		.. "  /up tooltip <on|off>  turn the item-tooltip verdict line on or off (persisted; default on)\n"
		.. "  /up detail <full|compact|upgrades>  how much the tooltip shows (persisted; default full)\n"
		.. "  /up glyphs <on|off>  colorblind-safe marker glyphs (persisted; default off)\n"
		.. "  /up log        list the disagreement log — items you equipped that Touchstone did NOT call UPGRADE (persisted; last 50)\n"
		.. "  /up log clear  empty the disagreement log\n"
		.. "  /up diag       write a SavedVariables + global diag record, print rows + walk ledger to chat"
end

-- Which roles the slash command will accept for this character? The
-- ORDERS table already encodes which classes are hybrid, so "melee" and
-- "spell" are both valid words for PALADIN/SHAMAN, and only "melee" is
-- valid for WARRIOR/ROGUE/HUNTER/DRUID, and only "spell" for MAGE/PRIEST/
-- WARLOCK. A valid word for any OTHER class is rejected here on the
-- grounds that a Warrior's role choice is a Warrior's, not a Hunter's.
local function acceptedRoleFor(token)
	if type(token) ~= "string" then return nil end
	local table_ = Verdict and Verdict.ORDERS and Verdict.ORDERS[token]
	if not table_ then return nil end
	for role in pairs(table_) do return role end
	return nil
end

local function cmdRole(msg)
	local word = msg:match("^role%s+(%a+)%s*$")
	if word == "clear" then
		local token = classToken()
		if token and type(ChestAdvisorDB.role) == "table" then
			ChestAdvisorDB.role[token] = nil
		end
		ChestAdvisor.scan()
		return true, "role cleared for this class"
	end
	if word then
		local w = word:lower()
		local token = classToken()
		if type(token) == "string" and Verdict and Verdict.ORDERS then
			local table_ = Verdict.ORDERS[token]
			if table_ and table_[w] then
				ChestAdvisorDB.role = ChestAdvisorDB.role or {}
				ChestAdvisorDB.role[token] = w
				ChestAdvisor.scan()
				return true, "recorded role for this class: " .. w
			end
		end
		return false, "rejected: '" .. w .. "' is not a recorded role for this class (melee | spell for a hybrid; "
			.. (token or "a pure class has a single documented order") .. ")"
	end
	return false, "usage: /up role <melee|spell|clear>"
end

-- /up toast <on|off> — persist the notification setting on the EXISTING
-- per-character store (AC-E). A missing key reads as ON (toastIsEnabled treats
-- anything but an explicit `false` as enabled), so an existing character with no
-- `toast` table gets the toast by default — a missing-key read is never OFF.
local function cmdToast(msg)
	local word = msg:match("^toast%s+(%a+)%s*$")
	if word == nil then
		local on = toastIsEnabled()
		return true, "toast is currently " .. (on and "on" or "off")
			.. " — usage: /up toast <on|off>"
	end
	local w = word:lower()
	ChestAdvisorDB.toast = ChestAdvisorDB.toast or {}
	if w == "on" then
		ChestAdvisorDB.toast.enabled = true
	elseif w == "off" then
		ChestAdvisorDB.toast.enabled = false
		-- Retract whatever is on screen. This must NOT run through the scan
		-- path with an empty table while enabled, or it would consume the
		-- login baseline early and let the first real scan toast a pre-existing
		-- bag state. The disabled branch inside maybeToastUpgrades only clears.
		maybeToastUpgrades({})
	else
		return false, "usage: /up toast <on|off>"
	end
	return true, "toast " .. w
end

-- /up toasts (alias /up testtoast) — t_4bae0617: raise the upgrade toast on
-- demand, so its lifetime, fade and dismiss can be checked without waiting for a
-- real upgrade to drop. It goes through ChestAdvisor.testToast, which queues and
-- shows through the REAL path; see that function for what it deliberately does
-- not touch (no dedupe entry, no log row, no baseline change).
local function cmdTestToast()
	if type(ChestAdvisor.testToast) ~= "function" then
		return false, "the toast surface is not loaded (is the Touchstone module off?)"
	end
	if not toastIsEnabled() then
		return false, "the toast is off — /up toast on, then /up toasts"
	end
	ChestAdvisor.testToast(1)
	local st = type(ChestAdvisor.toastState) == "function" and ChestAdvisor.toastState() or {}
	return true, string.format(
		"test toast: %s | queued: %s | lifetime: %.1fs — /up diag reports fired and the measured time",
		st.shown and "showing" or "not showing", tostring(st.queue or 0),
		tonumber(st.lifetime) or 0)
end

-- /up toastdebug [on|off|dump] — t_fe7a636a: the toast's transition trace.
-- Off by default. Every line is the client's own GetTime at three decimals,
-- and `dump` prints the last lines back because a toast is on screen for
-- seconds: the point is to read the trace AFTER it is gone.
local function cmdToastDebug(msg)
	local word = (msg:match("^toastdebug%s+(%a+)%s*$") or ""):lower()
	if type(ChestAdvisor.toastDebug) ~= "function" then
		return false, "the toast surface is not loaded (is the Touchstone module off?)"
	end
	if word == "" then word = nil end
	local ok, out = ChestAdvisor.toastDebug(word)
	return ok ~= false, out
end

-- /up tooltip <on|off> — the sibling of /up toast, on the SAME per-character
-- store (AC-F: no new store). A missing key reads as ON (TOOLTIP_UI.enabled treats
-- anything but an explicit `false` as enabled), so a fresh character sees the
-- line without typing anything. Bare `/up tooltip` reports state and usage.
local function cmdTooltip(msg)
	local word = msg:match("^tooltip%s+(%a+)%s*$")
	if word == nil then
		local on = TOOLTIP_UI.enabled()
		return true, "tooltip is currently " .. (on and "on" or "off")
			.. " — usage: /up tooltip <on|off>"
	end
	local w = word:lower()
	ChestAdvisorDB.tooltip = ChestAdvisorDB.tooltip or {}
	if w == "on" then
		ChestAdvisorDB.tooltip.enabled = true
	elseif w == "off" then
		ChestAdvisorDB.tooltip.enabled = false
	else
		return false, "usage: /up tooltip <on|off>"
	end
	return true, "tooltip " .. w
end

-- /up detail <full|compact|upgrades> — the U2 detail setting (card t_cf2ad83c).
-- Its own subword rather than an arm of /up tooltip, so the tooltip toggle's
-- existing on|off contract (and its usage string) is untouched. Same store,
-- same missing-key discipline: absent reads as full.
local function cmdDetail(msg)
	local word = msg:match("^detail%s+(%a+)%s*$")
	if word == nil then
		return true, "tooltip detail is currently " .. TOOLTIP_UI.detail()
			.. " — usage: /up detail <full|compact|upgrades>"
	end
	local w = word:lower()
	if not TOOLTIP_UI.details[w] then
		return false, "usage: /up detail <full|compact|upgrades>"
	end
	ChestAdvisorDB.tooltip = ChestAdvisorDB.tooltip or {}
	ChestAdvisorDB.tooltip.detail = w
	return true, "tooltip detail " .. w
end

-- /up glyphs <on|off> — the colorblind-safe marker shapes. Same per-character
-- store as the tooltip and the toast. A missing key reads as OFF (only an
-- explicit true draws the glyphs), so an older saved table stays colour-only.
local function glyphsOn()
	return ChestAdvisor._glyphsOn()
end

local function cmdGlyphs(msg)
	local word = msg:match("^glyphs%s+(%a+)%s*$")
	if word == nil then
		local on = glyphsOn()
		return true, "marker glyphs are currently " .. (on and "on" or "off")
			.. " — usage: /up glyphs <on|off>"
	end
	local w = word:lower()
	if w ~= "on" and w ~= "off" then
		return false, "usage: /up glyphs <on|off>"
	end
	ChestAdvisorDB.markers = ChestAdvisorDB.markers or {}
	ChestAdvisorDB.markers.glyphs = (w == "on")
	if type(ChestAdvisor.scan) == "function" then ChestAdvisor.scan() end
	return true, "marker glyphs " .. w
end

-- /ts scale <0.5-1.5> — the window scale the Settings slider also writes.
-- The host already persists that number (U6); this is the command a player
-- can type. The host owns the clamp. Absent host: say so, do not error.
local function cmdScale(msg)
	local host = rawget(_G, "StatForge")
	if type(host) ~= "table" or type(host.SetWindowScale) ~= "function" then
		return false, "window scale is unavailable"
	end
	local lo, hi = 0.5, 1.5
	if type(host.WindowScaleBounds) == "function" then
		lo, hi = host.WindowScaleBounds()
	end
	local bounds = tostring(lo) .. "-" .. tostring(hi)
	local num = msg:match("^scale%s+([%d%.]+)%s*$")
	if num == nil then
		local cur = 1
		if type(host.GetWindowScale) == "function" then cur = host.GetWindowScale() end
		return true, "window scale is " .. tostring(cur)
			.. " — usage: /ts scale <" .. bounds .. ">"
	end
	local n = tonumber(num)
	if type(n) ~= "number" then
		return false, "usage: /ts scale <" .. bounds .. ">"
	end
	local applied = host.SetWindowScale(n)
	return true, "window scale " .. tostring(applied)
end

-- /up log — the disagreement log's read surface (t_bc9c69d3). Prints the
-- entries OLDEST-FIRST, one line each, and an explicit empty message when
-- there is nothing to print (never silence — an empty log must be
-- distinguishable from a broken command). /up log clear empties it with a
-- plain `= {}`: no file operation, no SavedVariables write beyond the table
-- itself, which the client persists on logout as always.
local function cmdLog(msg)
	local w = (msg:match("^log%s+(%a+)%s*$") or ""):lower()
	if w == "clear" then
		ChestAdvisorDB.log = {}
		return true, "disagreement log cleared"
	end
	if w ~= "" then
		-- A bare `/up log` lists; `clear` empties. Anything else is a miss
		-- (likely a typo of `clear`) and says so rather than printing the
		-- list under a word the player did not ask for.
		return false, "usage: /up log [clear]"
	end
	local log = ChestAdvisorDB and ChestAdvisorDB.log or nil
	if type(log) ~= "table" or #log == 0 then
		return true, "no disagreements logged yet (equip an item Touchstone called NOT_UPGRADE and it is recorded here)"
	end
	local lines = { "disagreements logged: " .. tostring(#log) .. " (oldest first)" }
	for i = 1, #log do
		local e = log[i]
		if type(e) == "table" then
			-- Card t_e9a07624 (B6): a wall-clock stamp and a SLOT WORD, not a
			-- session-relative number and a raw slot index. An entry written
			-- before this card has no `at`/`slotName`. A previous session's
			-- GetTime is not an age, so that row prints "earlier".
			local stamp = formatEntryTime(e.at, e.time)
			local slotLabel = type(e.slotName) == "string" and e.slotName
				or ("slot " .. tostring(e.slot))
			lines[#lines + 1] = string.format(
				"%d) %s  %s  %s role=%s(%s) link=%s reason=%s",
				i, stamp, slotLabel, tostring(e.verdict),
				tostring(e.role), tostring(e.roleSource), tostring(e.link), tostring(e.reason))
		end
	end
	return true, table.concat(lines, "\n")
end

local DIAG_HISTORY = 6         -- keep the last N diag records, oldest first
-- (3d-life / phase-d-live-gate.md §5, part 3: "the last six").
-- ---- chat output: the one place a line reaches the player -------------------
--
-- LIVE BUG 3. Every print site below used to call a global `ChatFrameAddMessage`,
-- guarded by `if ChatFrameAddMessage and ChatFrame1 then`. That function does not
-- exist on this client: the name reads like a truncation of the real legacy
-- `ChatFrame_AddMessageEventFilter`, which *manages message-event filters* and
-- prints nothing at all. A grep across every addon in the client finds the bare
-- name only in this file; every other addon prints the documented way, with
-- `DEFAULT_CHAT_FRAME:AddMessage(msg)`.
--
-- So the guard was false, the branch was dead, and the `print()` fallback —
-- written as if it were a harness-only path ("the stub has no ChatFrame1") — was
-- in fact the path taken in game. `print` is not routed to the chat frame
-- either, so `/up diag`, `/up help`, `/up probe` and every success confirmation
-- were silent in the live client. Player report, verbatim:
--   "fyi rescan didnt print to chat"
--
-- The colour argument was wrong for the API too: `ChatFrame:AddMessage(text, r,
-- g, b)` takes numbers, and CHAT_COLOR_NAME was never defined anywhere in this
-- addon — the call passed nil where r belongs. Colour now rides inline in the
-- text as a colour escape, which is the idiom the rest of the client uses.
local CHAT_PREFIX_COLOR = "|cffd79b35"   -- same chat colour ForeverGear uses
local CHAT_RESET = "|r"

-- One line (or block) to the player. Single choke point so a future change to
-- the channel cannot silently strand one command the way this one was stranded.
local function chatOut(text)
	if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
		DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX_COLOR .. "Touchstone:" .. CHAT_RESET
			.. " " .. tostring(text))
	elseif print then
		-- Harness path (the stub has no DEFAULT_CHAT_FRAME), and any client
		-- where the chat frame is unavailable.
		print("Touchstone: " .. tostring(text))
	end
end

local function appendDiagHistory(entry)
	local h = ChestAdvisorDB.diagHistory
	if type(h) ~= "table" then
		h = {}
		ChestAdvisorDB.diagHistory = h
	end
	-- B15 (card t_6696b35a): keep the last six HEADERS, not a second copy of
	-- the row tables. `entry` is also ChestAdvisorDB.diag; inserting that
	-- same table made /up diag write every row twice (once under .diag, once
	-- under .diagHistory). A header still says when the diag ran and for
	-- which class. takenAt is the field the history cap test reads.
	table.insert(h, {
		takenAt = entry.takenAt,
		class = entry.class,
		level = entry.level,
		role = entry.role,
		roleSource = entry.roleSource,
		orderResolved = entry.orderResolved,
		hasRole = entry.hasRole,
		rowCount = type(entry.rows) == "table" and #entry.rows or 0,
	})
	while #h > DIAG_HISTORY do table.remove(h, 1) end
end

local function buildDiag()
	local token = classToken()
	-- Card t_0b4ddfa9 — resolve through the SAME path the scan uses, so the diag
	-- cannot report orderResolved=false while the marker is drawing (or the
	-- reverse). roleSource says which one won: the recorded /up role or the
	-- client spec read.
	local role, roleSource = resolvedRole(token)
	local order = Verdict and Verdict.classRoleOrder and Verdict.classRoleOrder(token, role) or nil
	local now   = GetTime and GetTime() or (STUB and STUB.now or 0)
	local diag = {
		takenAt = now,
		class = token,
		-- The character's level as the client reports it (the plan §4 lines
		-- grade item-vs-player level from these).
		level = (UnitLevel and UnitLevel("player")) or nil,
		role = role,
		roleSource = roleSource,
		orderResolved = order ~= nil,
		order = order,
		hasRole = role ~= nil,
		-- rows: the per-item capture from the CURRENT scan — the raw stat
		-- lines, the CanUseItem type+value, and (for UPGRADE rows) the
		-- anchor diagnostic. buildDiag does not re-read tooltips: the scan
		-- already did that once, and this is the same table the probes and
		-- the chat print read from.
		rows = {},
		-- B15 (card t_6696b35a): no `verdicts` key. It held the same row tables
		-- as `rows`, and the SavedVariables writer emits a table again at
		-- every reference, so /up diag saved every row twice. The chat print
		-- and the tests read `rows`. The live scan still publishes
		-- ChestAdvisor.diag.verdicts for the in-memory snapshot; this record
		-- is the one that hits disk.
	}
	if C_PlayerInfo and C_PlayerInfo.CanUseItem then
		diag.api = { canUse = "C_PlayerInfo.CanUseItem" }
	else
		diag.api = { canUse = nil }
	end
	-- One row per stored verdict, in a stable id order so the chat print
	-- is repeatable. The rows carry what plan §4 grades from (raw lines,
	-- CanUseItem type+value, level, class token); the anchor diagnostic
	-- is attached for the UPGRADE rows the scan anchored.
	for link, vrow in pairs(ChestAdvisor.__verdicts or {}) do
		table.insert(diag.rows, vrow)
	end
	table.sort(diag.rows, function(a, b) return (a.id or 0) < (b.id or 0) end)
	return diag
end

local function cmdDiag()
	-- Persist in SavedVariables (the addon's DB) so a broken verdict is
	-- diagnosable without /run. The stub reads ChestAdvisor.diag directly,
	-- but in game the addon DB is the long-lived record.
	-- E3 (AC-E9): the scan's walk ledger lives on
	-- ChestAdvisor.diag.ledger (written by the scan tail). buildDiag()
	-- does not re-walk the bag, so it cannot carry the ledger itself —
	-- capture it BEFORE the overwrite and carry it into the new record,
	-- or the assignment below would silently drop it.
	local priorLedger = ChestAdvisor.diag and ChestAdvisor.diag.ledger or nil
	local d = buildDiag()
	if type(priorLedger) == "table" then
		d.ledger = priorLedger
		d.classState = priorLedger.classState
		d.roleRecorded = priorLedger.role
	end
	ChestAdvisor.diag = d
	ChestAdvisorDB.diag = d
	appendDiagHistory(d)
	if STUB and STUB.advisorDiag == nil then
		STUB.advisorDiag = d
	end
	-- Plan §4 lines ("chat shows /up diag output"): one row per stored
	-- verdict with the fields the PASS/FIX/KILL rules grade from, through the
	-- single chat choke point above.
	local anchorLookupType = type(ContainerFrameUtil_GetItemButtonAndContainer)
	local summary = "diag recorded at " .. tostring(d.takenAt)
		.. " class=" .. tostring(d.class)
		.. " level=" .. tostring(d.level)
		.. " role=" .. tostring(d.role)
		.. " api.canUse=" .. tostring(d.api and d.api.canUse)
	if type(d.rows) == "table" and #d.rows > 0 then
		for _, r in ipairs(d.rows) do
			local line
			if r.verdict == "UPGRADE" then
				line = string.format(
					"row id=%s bag=%s slot=%s UPGRADE role=%s canUse=%s(%s) class=%s anchor=%s",
					tostring(r.id), tostring(r.bag), tostring(r.slot),
					tostring(r.role), tostring(r.canUse), tostring(r.canUseType),
					tostring(r.class), tostring(r.anchorDiag))
			else
				line = string.format(
					"row id=%s bag=%s slot=%s %s reason=%s canUse=%s(%s) class=%s",
					tostring(r.id), tostring(r.bag), tostring(r.slot),
					tostring(r.verdict), tostring(r.reason),
					tostring(r.canUse), tostring(r.canUseType),
					tostring(r.class))
				-- Card t_548f0341 (Defect 1): an OFF-HAND row's policy and
				-- whether the identity behind it was substantiated, so a
				-- refusal is auditable from the diag text alone.
				if r.shieldPolicy ~= nil then
					line = line .. " shieldPolicy=" .. tostring(r.shieldPolicy)
						.. " specSubstantiated=" .. tostring(r.specSubstantiated)
				end
			end
			summary = summary .. "\n" .. line
		end
	else
		summary = summary .. "\n(no verdict rows stored — /up rescan first)"
	end
	-- t_632f27e9: the toast's own state — the notification layer's behaviour
	-- belongs in the DIAG path (a human explicitly asking), never in the
	-- toast itself, which carries no suppression/debug text (AC-E2).
	--
	-- t_4bae0617: this block used to sit INSIDE the walk-ledger branch below, so
	-- a tester who ran /up toasts on a fresh login (no scan ledger yet) got no
	-- toast line at all. It is unconditional now: the toast's lifetime is
	-- measurable with no scan behind it, which is the point of the test command.
	-- `fired` and `last show on screen` are the numbers to read.
	local ts = ChestAdvisor.toastState and ChestAdvisor.toastState() or nil
	if type(ts) == "table" then
		local measured = "not shown yet"
		if type(ts.showMs) == "number" then
			measured = string.format("%.2fs", ts.showMs / 1000)
				.. " (" .. tostring(ts.lastEnd or "?") .. ")"
		end
		summary = summary .. "\n--- toast ---"
				.. "\nenabled: " .. tostring(ts.enabled)
				.. " | shown: " .. tostring(ts.shown)
				.. " | fired: " .. tostring(ts.fired)
				.. " | queued: " .. tostring(ts.queue)
				.. " | told this session: " .. tostring(ts.told)
				.. " | cap-dropped: " .. tostring(ts.dropped)
				-- t_cf2ad83c (U3): the behaviour that card added, so a human
				-- asking for diagnostics can see the hold and the hover pause.
				.. "\nhovered: " .. tostring(ts.hovered)
				.. " | lifetime left: " .. tostring(ts.lifetimeLeft)
				.. " | held for combat: " .. tostring(ts.held)
				.. " | deferred: " .. tostring(ts.deferred)
				-- t_4bae0617: the configured lifetime next to the MEASURED
				-- on-screen time of the last show, so "it went away too fast" is
				-- a comparison of two numbers instead of an impression.
				.. "\nconfigured lifetime: "
				.. string.format("%.2fs", tonumber(ts.lifetime) or 0)
				.. " | last show on screen: " .. measured
				-- t_fe7a636a: the trace switch and the repairs, so a flash
				-- report comes with the numbers that explain it.
				.. " | trace: " .. (ts.debug and "ON" or "off")
				.. "\nrevived this session: " .. tostring(ts.revived)
				.. " | alpha restored: " .. tostring(ts.alphaRestored)
				.. " | deadline left: "
				.. (tonumber(ts.deadlineLeft)
					and string.format("%.2fs", ts.deadlineLeft) or "-")
	end
	-- E3 (AC-E9): the walk ledger is part of the /up diag OUTPUT, not just
	-- the record. A reader must be able to answer "why did this item
	-- produce no marker?" from the diag text alone — no file open. The
	-- per-token skip lines are the whole point of the player's ruling:
	-- the token is what identifies WHY something was skipped (a weapon
	-- skip is a different skip from a neck skip and both should read
	-- differently on this line).
	if type(d.ledger) == "table" then
		local ld = d.ledger
		summary = summary
			.. "\n--- walk ledger ---"
			.. "\nitems walked (total bag cells): " .. tostring(ld.itemsScanned)
			.. "\nitems in scope (verdict produced): " .. tostring(ld.itemsWalked)
			.. "\ncap (MARKER_MAX): 64 — cap-dropped this scan: " .. tostring(ld.capDropped)
			.. "\nclass state: " .. tostring(ld.classState or "unknown")
			.. "\nrole: " .. tostring(ld.role or "none")
		-- t_c3fe7d1d: the quest-reward surface's own state, same reasoning as the
		-- toast block above — the reward arrows' behaviour belongs in the diag
		-- path (a human asking), never as on-screen debug text.
		local qs = ChestAdvisor.questState and ChestAdvisor.questState() or nil
		if type(qs) == "table" then
			summary = summary .. "\n--- quest rewards ---"
				.. "\nreward UI shown: " .. tostring(qs.visible)
				.. " | markers shown: " .. tostring(qs.shown)
				.. " | last refresh walked: " .. tostring(qs.walked)
				.. " | upgrades marked: " .. tostring(qs.upgrades)
				.. " | trade-off chips: " .. tostring(qs.tradeoffs)
				.. " | no-mark rows: " .. tostring(qs.noMark)
				.. " | refreshes: " .. tostring(qs.refreshed)
				-- Card t_8d653c12: the vendor coin. `coin` is the reward index
				-- the coin is on (nil when none); `coin candidates` is how many
				-- priced CHOICE rows this refresh saw, which is what tells a
				-- reader whether "no coin" meant "no upgrades AND no prices".
				.. " | vendor coin on: " .. tostring(qs.coin)
				.. " | coin candidates: " .. tostring(qs.coinCandidates)
			-- t_769aef9b (AC-F): which context flag selected the reward link
			-- API, and which API that flag resolves to on THIS client. This
			-- is the field that answers this card's STEP 1 on the next live
			-- login: open the quest-log/map reward panel, /up diag, read
			-- `reward context` and `reward link api` here.
			local qc = ChestAdvisor.questRewardContext
				and ChestAdvisor.questRewardContext() or nil
			if type(qc) == "table" then
				summary = summary
					.. " | reward context: " .. (qc.questLog and "questLog" or "dialog")
					.. " | reward link api: " .. tostring(qc.api) .. "("
					.. tostring(qc.apiPresent and "present" or "ABSENT") .. ")"
					.. " | dialog api: " .. tostring(qc.dialogApiPresent)
					.. " | quest-log api: " .. tostring(qc.questLogApiPresent)
			end
		end
		local skips = {}
		for token, n in pairs(ld.perSkip or {}) do
			table.insert(skips, string.format("%s=%d", tostring(token), n))
		end
		if #skips > 0 then
			table.sort(skips)
			summary = summary .. "\nskips: " .. table.concat(skips, " ")
		else
			summary = summary .. "\nskips: (none)"
		end
		summary = summary .. "\n--- end walk ledger ---"
	end
	chatOut("AnchorLookupType(ContainerFrameUtil_GetItemButtonAndContainer)="
		.. tostring(anchorLookupType) .. "\n" .. summary)
	return true, summary
end

local function cmdHelp()
	local help = helpText()
	chatOut(help)
	return true, help
end

-- ---- /up probe — the Phase D live probes (t_9ad3d462 part 2, plan §4) -----
--
-- The manual-test probes used /run, which is DEBUG_COMMAND-gated on this
-- client (plan §2 R2). They live here instead, as a read-only slash
-- subcommand: every probe is pcall-wrapped and records WHAT the client
-- actually returned (types + values), so C3's PASS/FIX/KILL rules in plan
-- §4 can be graded from ChestAdvisorDB.probe after the session, with no
-- interactive /run. Nothing here writes to the DB except probe records,
-- never to a verdict, and no probe calls a combat or protected API.
--
-- Print channel: the single chat choke point (chatOut) above. One line per
-- probe, "P<n>: <key>=<value> ..." — the recorded values, verbatim types.

-- One chat line per probe row.
local function probeOut(line)
	chatOut(line)
end

-- P0 (plan §4): the [Game]→Camelot hook model (U1, U2). Records type() of
-- the tooltip-model globals the reader depends on, plus three separate
-- TooltipUtil / TooltipDataRules / TooltipComparisonManager observations —
-- kept apart so the mainline-gating in the toc files is OBSERVED in game,
-- not assumed (the gate names a game-type family, one this client is a
-- member of, so a [AllowLoadGameType mainline] line loads here; only
-- standard/classic exclude it — PROJECT-NOTES.md, §Gating). The recorded
-- state is non-nil: all three are tables on the live client
-- (phase-d-evidence/session-2.md, AC3), which the probe records because
-- the point is observation, not because absence is expected).
local function probeP0(rec)
	local tdp = rawget(_G, "TooltipDataProcessor")
	rec.tdp = type(tdp)
	rec.tooltipUtil = type(rawget(_G, "TooltipUtil"))
	rec.tooltipDataRules = type(rawget(_G, "TooltipDataRules"))
	rec.tooltipComparisonManager = type(rawget(_G, "TooltipComparisonManager"))
	-- The scan tip is this addon's own GameTooltip: SetBagItem and
	-- SetHyperlink are the two readers; GetItem is the write-back that
	-- must NOT exist on a read-only scan tip (pcalled, per §4).
	local tip = getScanTip()
	rec.setBagItem = type(tip and tip.SetBagItem)
	rec.setHyperlink = type(tip and tip.SetHyperlink)
	if type(tip and tip.GetItem) == "function" then
		local ok = pcall(tip.GetItem, tip)
		rec.getItem = ok and "function(no-error under pcall)" or "function(erroring under pcall)"
	else
		rec.getItem = type(tip and tip.GetItem) == "function" and "function" or "absent"
	end
end

-- P1 (plan §4): stat lines render for a bag item (K2 territory). For every
-- bag item, record the scan tip's line count and the lines verbatim (the
-- tooltip reader already caps at 30). The PASS rule needs the visible
-- hover tooltip (screenshot) — that comparison is C3's, this only captures.
-- E3 (scope 6): P1 is on the same in-scope table as the scan (EQUIP_SLOTS).
-- Previously it was filtered to chest only, so /up probe and /up diag
-- disagreed about scope when the bag held other equipment. Keeping the key
-- name `chest` here (not a rename) but its value is now the in-scope rows,
-- so the probe output matches what the scan walks. Zero churn, zero rename.
local function probeP1(rec)
	local chest = {}
	if C_Container and C_Container.GetContainerNumSlots then
		for bag = 0, 4 do
			local count = 0
			local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
			if ok and type(n) == "number" then count = n end
			for slot = 1, count do
				local info
				local iok, i = pcall(C_Container.GetContainerItemInfo, bag, slot)
				if iok then info = i end
				if info and type(info) == "table" then
					local link = info.hyperlink
					local id = info.itemID or itemIDOf(link)
					local loc = link and id and equipLocation(id) or nil
					if link and id and type(id) == "number" and loc and wornSlotFor(loc) then
						-- Card t_119d120c: this stays on the RENDERED reader, on
						-- purpose. P1 is a diagnostic whose documented job is to
						-- capture what the VISIBLE tooltip shows so a human can
						-- compare it against a screenshot (plan §4, the C3 PASS
						-- rule) — so it must read the surface the player sees,
						-- composed lines included. That is the opposite of what
						-- the JUDGE wants, which is exactly why the judge and the
						-- probe no longer share a reader. The judge's own lines
						-- are recorded on the verdict row (`lines`), which is what
						-- /up diag reports.
						local lines = TooltipLines(link)
						local entry = {
							id = id, bag = bag, slot = slot,
							lineCount = #lines, lines = lines,
							equipLoc = loc,        -- E3 (scope 6): the row's own slot
						}
						table.insert(chest, entry)
					end
				end
			end
		end
	end
	rec.chest = chest
end

-- P2 (plan §4): CanUseItem enforces armour proficiency (U3). Record the
-- RAW type() and value for each bag item — a nil for cached items is a
-- K4 ("the gate is void"), a boolean true on an item the client refuses
-- is too. The equip attempt itself is the player's (K4 is player-run);
-- this only records what the API answers.
-- E3 (scope 6): P2 is on the same in-scope table as the scan (EQUIP_SLOTS),
-- aligned with P1 and the walk so /up probe and /up diag never disagree
-- about what is in scope.
local function probeP2(rec)
	local rows = {}
	if C_Container and C_Container.GetContainerNumSlots then
		for bag = 0, 4 do
			local count = 0
			local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
			if ok and type(n) == "number" then count = n end
			for slot = 1, count do
				local info
				local iok, i = pcall(C_Container.GetContainerItemInfo, bag, slot)
				if iok then info = i end
				if info and type(info) == "table" then
					local id = info.itemID or itemIDOf(info.hyperlink)
					local loc = info.hyperlink and id and equipLocation(id) or nil
					if info.hyperlink and id and type(id) == "number"
						and loc and wornSlotFor(loc) then
						local cv = canUse(id)   -- nil = API absent or error
						local entry = { id = id, bag = bag, slot = slot,
							canUse = cv, canUseType = type(cv),
							equipLoc = loc }   -- E3 (scope 6)
						if cv ~= nil and tostring(cv) ~= "true" then
							-- Non-boolean truthy: record its tostring too,
							-- so a "SECRETVALUE"-style return is legible.
							entry.canUseString = tostring(cv)
						end
						table.insert(rows, entry)
					end
				end
			end
		end
	end
	rec.rows = rows
end

-- P5 (plan §4): the anchor lookup (U7, K6 — the most likely kill). Record
-- the type of ContainerFrameUtil_GetItemButtonAndContainer AND, for every
-- UPGRADE verdict from the last scan, what the lookup resolved to (button
-- name) plus the anchorDiag the marker already carries. Runs AFTER the
-- scan's verdicts exist so it has real (bag, slot) pairs to probe.
local function probeP5(rec)
	rec.lookupType = type(ContainerFrameUtil_GetItemButtonAndContainer)
	rec.mixins = {
		containerFrameCombinedBags = type(rawget(_G, "ContainerFrameCombinedBagsMixin")),
	}
	local ups = {}
	for link, vrow in pairs(ChestAdvisor.__verdicts or {}) do
		if vrow.verdict == "UPGRADE" then
			local resolved = nil
			local resolvedName = nil
			if type(ContainerFrameUtil_GetItemButtonAndContainer) == "function" then
				local ok, btn = pcall(ContainerFrameUtil_GetItemButtonAndContainer,
					vrow.bag, vrow.slot)
				if ok and type(btn) == "table" then
					resolved = "button"
					resolvedName = tostring(btn.name or btn)
					if not btn:IsShown() then resolved = "button(not shown)" end
				elseif ok then
					resolved = "nil"
				else
					resolved = "error"
				end
			end
			table.insert(ups, { id = vrow.id, bag = vrow.bag, slot = vrow.slot,
				resolved = resolved, resolvedName = resolvedName,
				anchorDiag = vrow.anchorDiag })
		end
	end
	rec.upgrades = ups
end

local function cmdProbe()
	local rec = {
		takenAt = GetTime and GetTime() or (STUB and STUB.now or 0),
		class = classToken(),
		role = playerRole(classToken()),
		level = (UnitLevel and UnitLevel("player")) or nil,
		p0 = {}, p1 = {}, p2 = {}, p5 = {},
	}
	-- Each probe is independent: one raising must not blank the others.
	local ok0, e0 = pcall(probeP0, rec.p0)
	if not ok0 then rec.p0 = { err = tostring(e0) } end
	local ok1, e1 = pcall(probeP1, rec.p1)
	if not ok1 then rec.p1 = { err = tostring(e1) } end
	local ok2, e2 = pcall(probeP2, rec.p2)
	if not ok2 then rec.p2 = { err = tostring(e2) } end
	local ok5, e5 = pcall(probeP5, rec.p5)
	if not ok5 then rec.p5 = { err = tostring(e5) } end

	-- One line per probe, the recorded values verbatim.
	local p0v = rec.p0
	if type(p0v) == "table" and p0v.err == nil then
		probeOut("P0: TooltipDataProcessor=" .. tostring(p0v.tdp)
			.. " SetBagItem=" .. tostring(p0v.setBagItem)
			.. " SetHyperlink=" .. tostring(p0v.setHyperlink)
			.. " GetItem=" .. tostring(p0v.getItem)
			.. " TooltipUtil=" .. tostring(p0v.tooltipUtil)
			.. " TooltipDataRules=" .. tostring(p0v.tooltipDataRules)
			.. " TooltipComparisonManager=" .. tostring(p0v.tooltipComparisonManager))
	else
		probeOut("P0: error — " .. tostring(type(rec.p0) == "table" and rec.p0.err))
	end
	if type(rec.p1) == "table" and type(rec.p1.chest) == "table" then
		if #rec.p1.chest == 0 then probeOut("P1: no in-scope items found in bags 0-4") end
		for _, c in ipairs(rec.p1.chest) do
		probeOut(string.format("P1: id=%s bag=%s slot=%s loc=%s lines=%s",
				tostring(c.id), tostring(c.bag), tostring(c.slot),
				tostring(c.equipLoc), tostring(c.lineCount)))
		end
	else
		probeOut("P1: error — " .. tostring(type(rec.p1) == "table" and rec.p1.err))
	end
	if type(rec.p2) == "table" and type(rec.p2.rows) == "table" then
		for _, r in ipairs(rec.p2.rows) do
			probeOut(string.format("P2: id=%s loc=%s CanUseItem=%s(%s)",
				tostring(r.id), tostring(r.equipLoc),
				tostring(r.canUse), tostring(r.canUseType)))
		end
		if #rec.p2.rows == 0 then probeOut("P2: no in-scope items found in bags 0-4") end
	else
		probeOut("P2: error — " .. tostring(type(rec.p2) == "table" and rec.p2.err))
	end
	if type(rec.p5) == "table" and rec.p5.err == nil then
		probeOut("P5: ContainerFrameUtil_GetItemButtonAndContainer=" .. tostring(rec.p5.lookupType)
			.. " ContainerFrameCombinedBagsMixin=" .. tostring(rec.p5.mixins and rec.p5.mixins.containerFrameCombinedBags)
			.. " upgrades=" .. tostring(#rec.p5.upgrades))
	else
		probeOut("P5: error — " .. tostring(type(rec.p5) == "table" and rec.p5.err))
	end

	-- Persist: per-character SavedVariables once the toc switches to
	-- SavedVariablesPerCharacter (part 4 of this card) — until then this
	-- lands in the account-level file, which is where R3 says the role
	-- already does.
	ChestAdvisorDB.probe = rec
	ChestAdvisor.probe = rec
	if STUB and STUB.advisorProbe == nil then
		STUB.advisorProbe = rec
	end
	return true, "probes recorded at " .. tostring(rec.takenAt)
		.. " (P0/P1/P2/P5 in ChestAdvisorDB.probe)"
end

local function dispatch(msg)
	if type(msg) ~= "string" then return false, "no message" end
	local trimmed = msg:gsub("^%s+", "")
	local first = trimmed:match("^(%S+)") or ""
	local firstL = first:lower()
	-- The client strips the slash word (/up, /upgrade, /u) before calling;
	-- a caller passing the full form keeps it. Normalize both shapes.
	if firstL == "up" or firstL == "upgrade" or firstL == "u" then
		trimmed = trimmed:sub(#first + 1):gsub("^%s+", "")
	end
	local subword = (trimmed:match("^(%S+)") or ""):lower()
	-- The resolved subword is returned as a THIRD value (additive; every
	-- existing caller takes two) so the slash wrapper can decide whether the
	-- success message still needs echoing without re-parsing the command line
	-- and risking a second, divergent copy of this normalization.
	local ok, out
	if subword == "role" then
		ok, out = cmdRole(trimmed)
	elseif subword == "probe" then
		ok, out = cmdProbe()
	elseif subword == "toast" then
		ok, out = cmdToast(trimmed)
	elseif subword == "toasts" or subword == "testtoast" then
		ok, out = cmdTestToast()
	elseif subword == "toastdebug" then
		ok, out = cmdToastDebug(trimmed)
	elseif subword == "tooltip" then
		ok, out = cmdTooltip(trimmed)
	elseif subword == "detail" then
		ok, out = cmdDetail(trimmed)
	elseif subword == "glyphs" then
		ok, out = cmdGlyphs(trimmed)
	elseif subword == "scale" then
		ok, out = cmdScale(trimmed)
	elseif subword == "log" then
		-- cmdLog prints its own block (a list, or the explicit empty
		-- message), so it is echoed by the slash wrapper's `out` path —
		-- exactly like every other listing command. A bare `/up log` is a
		-- list request, not usage: cmdLog's own match yields "" and it
		-- falls through to the list branch, which prints empty explicitly.
		ok, out = cmdLog(trimmed)
	elseif subword == "diag" then
		ok, out = cmdDiag()
	elseif subword == "help" then
		ok, out = cmdHelp()
	elseif subword == "rescan" then
		ChestAdvisor.scan()
		ok, out = true, "rescanned"
	elseif subword ~= "" then
		ok, out = false, "unknown command: " .. subword
	else
		ok, out = cmdHelp()
	end
	return ok, out, subword
end

-- Register the slash. The house pattern is SlashCmdList["NAME"] = function(msg)
-- Four strings, one handler (card t_83f9795c added /ts). Each string is its OWN
-- global; the client maps SLASH_<NAME><n> to SlashCmdList[<NAME>], so /ts
-- reaches this function through the SAME NAME as /up, /upgrade and
-- /chestadvice. One string, one owner: Core.lua does not register /ts.
SLASH_CHESTADVISOR1 = "/up"
SLASH_CHESTADVISOR2 = "/upgrade"
SLASH_CHESTADVISOR3 = "/chestadvice"
-- t_83f9795c, amended by t_6696b35a. The host (Core.lua) registers no /ts:
-- a second SLASH_* = "/ts" on a different SlashCmdList NAME would be one
-- string with two owners, and the client keeps one mapping per string, so
-- the loser is silently dead (commits 81d514e, 5656449). The client strips
-- the slash word before calling, so a bare /ts, /up, /upgrade or /chestadvice
-- all arrive as msg == "" and cannot be told apart. That empty string opens
-- the window. Help is the explicit subcommand (/ts help), not the default.
SLASH_CHESTADVISOR4 = "/ts"
SlashCmdList["CHESTADVISOR"] = function(msg)
	-- t_6696b35a bare-open. The client delivers msg == "" for a bare slash word.
	if msg == "" or msg == nil or (type(msg) == "string" and msg:find("%S") == nil) then
		local host = StatForge
		if type(host) == "table" and type(host.ShowMain) == "function" then
			host.ShowMain()
		end
		return true, "window"
	end
	local ok, out, subword = dispatch(" " .. tostring(msg or ""))
	if not ok then
		-- An unknown command prints help; it does not error, so a mistyped
		-- slash never breaks a character's session.
		chatOut(tostring(out) .. "\n" .. helpText())
	elseif out and subword ~= "help" and subword ~= "diag" and subword ~= "" then
		-- Success-path chat echo (live bug 3). Several subcommands return their
		-- confirmation as a MESSAGE and print nothing themselves: `/up rescan`
		-- returns "rescanned", `/up role` returns "recorded role for this
		-- class: <w>". The client DISCARDS a slash handler's return value, so
		-- those confirmations were never visible in game — the command worked
		-- and the player saw nothing, indistinguishable from a broken addon.
		-- (The run sheet's expectation of "one line `rescanned`" was right; the
		-- command was the part that did not do it.)
		--
		-- Echoed HERE, once, in the only place the return value is consumed.
		-- cmdHelp and cmdDiag already print for themselves, and `out` for them
		-- is the same text — echoing again would double the line. `/up probe`
		-- prints per-row via probeOut and its `out` is a different, single tail
		-- line, so it is echoed here and stays one line.
		chatOut(tostring(out))
	end
	return ok, out
end
end
-- Fold (MightiePack Touchstone module): initLogAndSlash() registers the
-- four slash strings, the /up,/upgrade,/chestadvice,/ts handler and the
-- disagreement log hooks. Its body below is unchanged; only the CALL is
-- deferred to ChestAdvisor.Enable().
ChestAdvisor._initLogAndSlash = function()
	if ChestAdvisor._slashAndLogEnabled then return end
	ChestAdvisor._slashAndLogEnabled = true
	initLogAndSlash()
end
end


-- ---- Load -------------------------------------------------------------------
-- NOTE (t_dcb796b0): onLogin is defined but has NO call site in this file —
-- it is dead code left over from the registration restructure. The "login
-- scan" its comment promises has therefore never run; the actual first scan
-- comes from the PLAYER_LOGIN OnEvent arm (line ~74), which DOES fire after
-- addons load in game, and from the two registration blocks below. Do not
-- add a call to onLogin "to fix" the login scan and re-register for the
-- events twice. If we clean this up, delete the function and its callers,
-- not the first scan.
local function onLogin()
	-- Build the event frame once and register for the scan events.
	local f = getFrame()
	if f then
		f:RegisterEvent("PLAYER_LOGIN")
		f:RegisterEvent("PLAYER_ENTERING_WORLD")
		f:RegisterEvent("BAG_UPDATE_DELAYED")
		f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
		-- B11 (card t_e9a07624): the item-data pair belongs on the scan
		-- frame's own registration list too, for a hypothetical caller that
		-- reaches this path — the frame is getFrame()'s singleton, so this
		-- cannot create a second registration in game.
		f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		f:RegisterEvent("ITEM_DATA_LOAD_RESULT")
		-- U3/5 (card t_cf2ad83c): combat end releases a held toast. Registered on
		-- the SAME scan frame — no second event frame, no second handler.
		f:RegisterEvent("PLAYER_REGEN_ENABLED")
	end
	-- (Dead scan: this function is never called, see the NOTE above the
	-- definition. The actual first scan comes from the PLAYER_LOGIN arm.)
	ChestAdvisor.scan()
end

-- The stub fires on every frame that has registered, so we register here
-- rather than inside getFrame (which the tests may not reach before they
-- fire events).
if frame then
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("BAG_UPDATE_DELAYED")
	frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	-- B11 (card t_e9a07624): the item-data pair, so a cold-cache scan is
	-- re-run once the client caches the items (the reference's own pair).
	frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
	-- U3/5 (card t_cf2ad83c): combat end releases a held toast.
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	-- U5 (card t_c01331a2): the merchant lifecycle, on the SAME scan frame (the
	-- getFrame() singleton), so a test that fires events before getFrame() is
	-- reached still lands on the handler. Idempotent in game.
	frame:RegisterEvent("MERCHANT_SHOW")
	frame:RegisterEvent("MERCHANT_UPDATE")
	frame:RegisterEvent("MERCHANT_CLOSED")
end
-- Fold (MightiePack Touchstone module): every load-time surface is installed
-- here, in the order the file used to install them at load, and only when the
-- module is enabled. The handlers above are unchanged.
function ChestAdvisor.Enable()
	if ChestAdvisor._enabled then return end
	ChestAdvisor._enabled = true
	ChestAdvisor._installRefreshHooks()
	ChestAdvisor._initQuestSurface()
	ChestAdvisor._installPaperDollHooks()
	ChestAdvisor._installMerchantHooks()
	ChestAdvisor._initToastSurface()
	ChestAdvisor._initLogAndSlash()
	-- Ensure the scan frame exists once the module is enabled.
	getFrame()
	local loginFrame = getFrame()
	loginFrame:RegisterEvent("PLAYER_LOGIN")
	loginFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	loginFrame:RegisterEvent("BAG_UPDATE_DELAYED")
	loginFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	-- B11 (card t_e9a07624): registered on the scan frame too — the same frame
	-- getFrame() returns, so this is idempotent in game and explicit for the tests.
	loginFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	loginFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
	-- U3/5 (card t_cf2ad83c): the combat-hold release. The same frame again.
	loginFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	-- U5 (card t_c01331a2): the merchant lifecycle. The same frame again.
	loginFrame:RegisterEvent("MERCHANT_SHOW")
	loginFrame:RegisterEvent("MERCHANT_UPDATE")
	loginFrame:RegisterEvent("MERCHANT_CLOSED")

	-- Card t_ed71a583: install the item-tooltip verdict line ONCE, on first enable. Nothing
	-- here reads the world — the hook is a passive post-call that resolves its row
	-- when a tooltip is built, so there is no ordering dependency on the first scan.
	installTooltipHook()
end

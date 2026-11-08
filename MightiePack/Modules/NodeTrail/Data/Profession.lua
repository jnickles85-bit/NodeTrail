-- NodeTrail — "can THIS character gather herbs?" (t_d4848ce0)
--
-- The herb block used to appear on every herb node on every character, and it
-- carried `Your picks: N` filled from NodeTrailDB.herbs.maps — ONE saved table
-- for the whole account (Recorder.lua, no per-character key). On a character
-- with no Herbalism that line reported somebody else's gathers as "yours".
--
-- So the block needs two facts:
--   1. does this character have Herbalism at all?  -> this module
--   2. where does the picks number come from?      -> account-wide, so the
--                                                     wording must say so
--
-- Fact 1 is read from the client's OWN skill API, and *which* call this client
-- exposes is MEASURED, never assumed. The candidates are probed in this order,
-- each one pcall'd, and the first that answers definitively wins:
--
--   1. skill-lines   GetNumSkillLines() + GetSkillLineInfo(i) — the character's
--                    whole skill line list. Definitive both ways: a readable
--                    list with no Herbalism row means "no".
--   2. professions   GetProfessions() + GetProfessionInfo(index) — the seven
--                    profession slots. Definitive both ways when it names any.
--   3. open-window   GetTradeSkillLine() / C_TradeSkillUI profession calls —
--                    only answers while a profession window is OPEN, so it can
--                    CONFIRM Herbalism but never deny it. Positive only.
--
-- Anything else is UNKNOWN (nil), and the caller falls through to "show the
-- node knowledge, omit the picks line" rather than guessing. A wrong "no"
-- hides the block on a real herbalist; a wrong "yes" shows a picks line to a
-- character who cannot gather a single herb. Unknown is the only honest answer
-- when nothing answers.
--
-- Rules this file obeys:
--   * every client call is pcall'd, and a call that raises is recorded as a
--     read that failed, not as an answer;
--   * a client string is matched only after `issecretvalue` says it is not
--     secret (a secret name raises on :lower/:find);
--   * GetSkillLineInfo's shape is derived from the TYPES it returned, not from
--     a remembered signature — clients answer with 4 values (name, isHeader,
--     isExpanded, rank) and with shortened lists alike;
--   * nothing here registers an event, calls C_EventUtils, or touches a frame.
local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

local Pr = {}
ns.Profession = Pr

-- How the profession is named. The skill line is "Herbalism"; GetSpellInfo on
-- the gathering spell reports "Herb Gathering" where the client has it. Both
-- are matched case-insensitively; a translation would need its own entry.
Pr.NAMES = { "herbalism", "herb gathering" }

-- The gathering spell, used only to derive an extra accepted name.
Pr.SPELL_ID = 2366

-- ── the SECOND skill this gate answers for (t_c0221fd7) ───────────────────
-- The beast block is gated on Skinning exactly as the herb block is on
-- Herbalism, and it reads the SAME three tiers — a second copy of them would
-- drift the moment one side is fixed. So the tiers take a context: the names
-- to match, the label to print, and the spell to ask GetSpellInfo about.
-- Skinning is spell 8613 (the recorder's R.SKIN_SPELL_ID, live-confirmed on
-- this client: the probe's dump carries "cast 8613").
--
-- t_5ba9b43c — the one place the two consumers differ: the beast block shows
-- only on a CONFIRMED answer. The herb block keeps its node knowledge on an
-- unreadable client (that table is not personal) and drops the picks line; the
-- beast block has no non-personal table at all, so an unreadable answer means
-- no block. The gate implementation is still shared — see UI/Tooltip.lua,
-- BuildBeastLines, for the rule and why.
Pr.SKIN_NAMES = { "skinning" }
Pr.SKIN_SPELL_ID = 8613
Pr.LABEL = "Herbalism"
Pr.SKIN_LABEL = "Skinning"

-- A definitive answer is reused for this many seconds, so a client that
-- intermittently fails the read cannot make the block flicker in and out of
-- existence mid-hover. "Unknown" is never cached — it is retried, because it
-- may become readable (a profession window opening, the skill list loading).
Pr.TTL = 10

-- Existence probes, reported by /nt ttdiag. Nothing is called to build this
-- list: `type(f) == "function"` is the whole test.
Pr.LEGACY_CANDIDATES = {
  "GetNumSkillLines",
  "GetSkillLineInfo",
  "GetProfessions",
  "GetProfessionInfo",
  "GetTradeSkillLine",
}
Pr.MODERN_CANDIDATES = {
  "GetChildProfessionInfo",
  "GetBaseProfessionInfo",
  "GetOpenTradeSkillLine",
  "GetSkillLineName",
}

-- ── guarded reads ─────────────────────────────────────────────────────────
local function isSecret(v)
  if type(issecretvalue) ~= "function" then
    return false
  end
  local ok, s = pcall(issecretvalue, v)
  return ok and s == true
end

local function addName(list, v)
  if type(v) ~= "string" or v == "" or isSecret(v) then
    return
  end
  local ok, lower = pcall(string.lower, v)
  if ok and type(lower) == "string" and lower ~= "" then
    list[#list + 1] = lower
  end
end

-- The names this client itself uses for the asked-about profession: our
-- literals plus whatever GetSpellInfo calls its spell.
local function wantNames(ctx)
  local names = {}
  for _, n in ipairs(ctx.names) do
    names[#names + 1] = n
  end
  if type(GetSpellInfo) == "function" then
    local ok, name = pcall(GetSpellInfo, ctx.spell)
    if ok then
      addName(names, name)
    end
  end
  return names
end

-- What the tiers are asked about. `FromSkillLines()` with no argument (or with
-- `Pr` itself, the old call shape) still asks about Herbalism, which is what
-- every caller before t_c0221fd7 meant.
local function contextOf(kind)
  if kind == "skinning" then
    return {
      id = "skinning", names = Pr.SKIN_NAMES,
      spell = Pr.SKIN_SPELL_ID, label = Pr.SKIN_LABEL,
    }
  end
  if kind == "alchemy" then
    -- t_04c983cc: the recipe scan needs the character's Alchemy RANK (to compare
    -- a recipe's requiredSkill against), not the yes/no the tooltip gates ask
    -- for. Same skill-line tier, same name matching, one more context.
    return {
      id = "alchemy", names = { "alchemy" },
      spell = 2259, label = "Alchemy",
    }
  end
  return {
    id = "herbalism", names = Pr.NAMES,
    spell = Pr.SPELL_ID, label = Pr.LABEL,
  }
end
Pr.Context = contextOf

local function ctxArg(arg)
  if type(arg) == "table" and type(arg.names) == "table"
    and type(arg.label) == "string" then
    return arg
  end
  return contextOf("herbalism")
end

-- Match a client string against those names. A secret string is never read:
-- the answer is a plain false, and the caller's "no <skill> row" conclusion
-- stays a conclusion about the rows that WERE readable.
local function isSkillName(name, names)
  if type(name) ~= "string" or name == "" or isSecret(name) then
    return false
  end
  local ok, hit = pcall(function()
    local lower = string.lower(name)
    for _, want in ipairs(names) do
      if lower == want or string.find(lower, want, 1, true) ~= nil then
        return true
      end
    end
    return false
  end)
  return ok and hit == true
end

-- A profession call may answer as a bare name or as a table carrying the name
-- under any of the usual keys. Anything else is nil — never an error.
local function profName(r)
  if type(r) == "string" and r ~= "" then
    return r
  end
  if type(r) == "table" then
    for _, k in ipairs({ "skillLineName", "professionName", "name" }) do
      local v = r[k]
      if type(v) == "string" and v ~= "" then
        return v
      end
    end
  end
  return nil
end

-- ── tier 1: skill lines ───────────────────────────────────────────────────
-- GetSkillLineInfo is documented as
--   name, isHeader, isExpanded, skillRank [, …]
-- on clients that still carry it, and several clients answer with a shortened
-- list. The SHAPE is therefore measured from the returned types:
--   * second return boolean  -> documented shape, rank is the 4th return;
--   * second return number   -> short shape, rank is the 2nd return.
-- A row whose shape cannot be read contributes the name only.
function Pr:FromSkillLines(ctx)
  ctx = ctxArg(ctx)
  if type(GetNumSkillLines) ~= "function" then
    return nil, "GetNumSkillLines absent"
  end
  if type(GetSkillLineInfo) ~= "function" then
    return nil, "GetNumSkillLines present, GetSkillLineInfo absent"
  end
  local okN, n = pcall(GetNumSkillLines)
  if not okN then
    return nil, "GetNumSkillLines raised: " .. tostring(n)
  end
  if type(n) ~= "number" or n <= 0 then
    return nil, "GetNumSkillLines returned " .. tostring(n)
  end
  local names = wantNames(ctx)
  local label = ctx.label
  local rows, unreadable, shape = 0, 0, nil
  local raiseMsg = nil
  local found, foundRank = false, nil
  for i = 1, n do
    local ok, a, b, c, d = pcall(GetSkillLineInfo, i)
    if not ok then
      -- A row that RAISES is not a row without Herbalism: count it as a read
      -- that FAILED, never as an answer. A definitive "no" needs every row.
      unreadable = unreadable + 1
      raiseMsg = raiseMsg or tostring(a)
    elseif type(a) == "string" and a ~= "" and not isSecret(a) then
      rows = rows + 1
      local thisShape, rank
      if type(b) == "boolean" then
        thisShape, rank = "4-field", d
      elseif type(b) == "number" then
        thisShape, rank = "short", b
      end
      if thisShape then
        shape = shape or thisShape
      end
      if isSkillName(a, names) then
        found = true
        foundRank = type(rank) == "number" and rank or nil
        break
      end
    else
      -- The row answered with nothing usable as a name: nil, an EMPTY string,
      -- a table, or a secret string. A client that over-reports
      -- GetNumSkillLines answers "" for indices past the end of its list;
      -- counting that as a readable row would let the tier claim "no
      -- Herbalism" about rows whose names were never seen. The row exists, so
      -- Herbalism cannot be ruled out: unreadable, exactly like a raise.
      unreadable = unreadable + 1
    end
  end
  if rows == 0 then
    return nil, raiseMsg
      and ("GetSkillLineInfo raised: " .. raiseMsg)
      or (("GetSkillLineInfo answered no readable name in %d row(s)"):format(n))
  end
  local detail = ("%d skill line(s) read (%s)"):format(rows, shape or "shape unreadable")
  if not found then
    if unreadable > 0 then
      -- SOME rows answered and some did not. "No Herbalism" would then be a
      -- guess about rows we never saw — the direction that hides the block on a
      -- real herbalist — so this tier abstains and the next one gets a turn.
      return nil, detail .. ("; %d row(s) unreadable (%s) — %s cannot be ruled out")
        :format(unreadable, raiseMsg and ("raised: " .. raiseMsg) or "no readable name", label)
    end
    return false, detail .. "; no " .. label .. " line"
  end
  if foundRank == nil then
    return nil, detail .. "; " .. label .. " line present but its rank was unreadable"
  end
  if foundRank > 0 then
    return true, detail .. ("; %s rank %d"):format(label, foundRank)
  end
  return false, detail .. "; " .. label .. " line present at rank 0"
end

-- ── the current RANK of a profession (t_04c983cc) ─────────────────────────
-- FromSkillLines answers "does this character have the skill". The alchemy
-- recipe scan needs one more number: the skill rank, to compare a recipe's
-- requiredSkill against. It is read from the SAME tier-1 calls, with the same
-- measured row shapes (the returned TYPES decide where the rank sits), so a
-- client whose rank cannot be read answers nil rather than a guessed number.
function Pr:Rank(kind)
  local ctx = contextOf(kind)
  if type(GetNumSkillLines) ~= "function" then
    return nil, "GetNumSkillLines absent"
  end
  if type(GetSkillLineInfo) ~= "function" then
    return nil, "GetSkillLineInfo absent"
  end
  local okN, n = pcall(GetNumSkillLines)
  if not okN then
    return nil, "GetNumSkillLines raised: " .. tostring(n)
  end
  if type(n) ~= "number" or n <= 0 then
    return nil, "GetNumSkillLines returned " .. tostring(n)
  end
  local names = wantNames(ctx)
  for i = 1, n do
    local ok, a, b, c, d = pcall(GetSkillLineInfo, i)
    if ok and type(a) == "string" and a ~= "" and not isSecret(a) then
      local rank
      if type(b) == "boolean" then
        rank = d -- documented shape: name, isHeader, isExpanded, skillRank
      elseif type(b) == "number" then
        rank = b -- short shape: name, skillRank
      end
      if isSkillName(a, names) then
        if type(rank) == "number" then
          return rank, ("%s rank %d (GetSkillLineInfo)"):format(ctx.label, rank)
        end
        return nil, ctx.label .. " line present but its rank was unreadable"
      end
    end
  end
  return nil, ("no %s line in %d skill line(s)"):format(ctx.label, n)
end

-- ── tier 2: the seven profession slots ────────────────────────────────────
-- GetProfessions() gives the skill-line indices this character has learned;
-- GetProfessionInfo(index) names each one. Definitive both ways once any slot
-- is named: an empty or unnameable list is "unknown", not "no".
function Pr:FromProfessions(ctx)
  ctx = ctxArg(ctx)
  if type(GetProfessions) ~= "function" then
    return nil, "GetProfessions absent"
  end
  if type(GetProfessionInfo) ~= "function" then
    return nil, "GetProfessions present, GetProfessionInfo absent"
  end
  local okP, a, b, c, d, e, f, g = pcall(GetProfessions)
  if not okP then
    return nil, "GetProfessions raised: " .. tostring(a)
  end
  -- GetProfessions documents SEVEN return values (one per slot), and some
  -- wrappers hand back a table of the same. Both shapes are read.
  local list
  if type(a) == "table" then
    list = a
  else
    list = { a, b, c, d, e, f, g }
  end
  local names = wantNames(ctx)
  local label = ctx.label
  local seen, herb, unreadable = 0, false, 0
  for slot = 1, 7 do
    local idx = list[slot]
    if type(idx) == "number" then
      local okI, name = pcall(GetProfessionInfo, idx)
      -- Decode the name ONCE, and match the decoded string: a client that
      -- answers `{ skillLineName = "Herbalism" }` must not be read as
      -- "no Herbalism" just because the raw return is a table.
      local nm = okI and profName(name) or nil
      if nm == nil or isSecret(nm) then
        -- A NUMERIC index is a learned profession by contract: GetProfessions
        -- answers nil for an empty slot. So a slot whose name cannot be
        -- decoded is a read that FAILED, not an empty slot. Counting it as
        -- empty is how `{ skillLine = "Herbalism" }` came to answer a
        -- definitive "no" and hide the block on an herbalist.
        unreadable = unreadable + 1
      else
        seen = seen + 1
        if isSkillName(nm, names) then
          herb = true
        end
      end
    end
  end
  if herb then
    return true, ("%d learned profession(s) read; %s among them"):format(seen, label)
  end
  if seen == 0 then
    if unreadable > 0 then
      return nil, ("no profession slot named anything readable; %d learned slot(s) unreadable — %s cannot be ruled out")
        :format(unreadable, label)
    end
    return nil, "GetProfessionInfo named none of the profession slots"
  end
  if unreadable > 0 then
    -- Some slots were named and some were not readable: "no Herbalism" would be
    -- a guess about the slots we could not read, and a wrong "no" hides the
    -- block on a real herbalist.
    return nil, ("%d learned profession(s) read; %d slot(s) unreadable — %s cannot be ruled out")
      :format(seen, unreadable, label)
  end
  return false, ("%d learned profession(s) read; no %s"):format(seen, label)
end

-- ── tier 3: the open profession window (positive only) ────────────────────
-- These calls describe the window the player has OPEN, not the character's
-- learned professions. A closed window says nothing, so only a Herbalism
-- answer is usable here; anything else stays unknown.
function Pr:FromOpenWindow(ctx)
  ctx = ctxArg(ctx)
  local candidates = {}
  if type(GetTradeSkillLine) == "function" then
    candidates[#candidates + 1] = { fn = GetTradeSkillLine, label = "GetTradeSkillLine" }
  end
  if type(C_TradeSkillUI) == "table" then
    for _, n in ipairs(Pr.MODERN_CANDIDATES) do
      local f = C_TradeSkillUI[n]
      if type(f) == "function" then
        candidates[#candidates + 1] = { fn = f, label = "C_TradeSkillUI." .. n }
      end
    end
  end
  if #candidates == 0 then
    return nil, "no open-window profession call exists on this client"
  end
  local names = wantNames(ctx)
  local label = ctx.label
  local answered = nil
  for _, c in ipairs(candidates) do
    local ok, r = pcall(c.fn)
    if ok then
      local name = profName(r)
      if name ~= nil then
        answered = c.label
        if isSkillName(name, names) then
          return true, "the open profession window reports " .. label .. " (" .. c.label .. ")"
        end
      end
    end
  end
  if answered then
    return nil, (("%s named the OPEN window only, and it is not %s — that says nothing about what this character has learned"))
      :format(answered, label)
  end
  return nil, "the open-window calls answered no profession name"
end

-- ── the probe ─────────────────────────────────────────────────────────────
-- Returns info = { answer = true|false|nil, id = <skill>, label = <skill>,
--                  api = <tier id or nil>, detail = <what was read>,
--                  tried = { {id, answer, detail} } }
-- `info.herbalism` / `info.skinning` mirror `answer` for the skill asked
-- about, which is the field the tooltip gates and the specs read.
function Pr:Probe(ctx)
  ctx = ctxArg(ctx)
  local info = { answer = nil, id = ctx.id, label = ctx.label, api = nil, detail = nil, tried = {} }
  local tiers = {
    { id = "skill-lines", fn = Pr.FromSkillLines },
    { id = "professions", fn = Pr.FromProfessions },
    { id = "open-window", fn = Pr.FromOpenWindow },
  }
  for _, t in ipairs(tiers) do
    local ok, answer, detail = pcall(t.fn, Pr, ctx)
    if not ok then
      info.tried[#info.tried + 1] = {
        id = t.id, answer = "unknown", detail = "raised: " .. tostring(answer),
      }
    else
      local label = nil
      if answer == true then
        label = "yes"
      elseif answer == false then
        label = "no"
      else
        label = "unknown"
      end
      info.tried[#info.tried + 1] = { id = t.id, answer = label, detail = detail }
      if answer ~= nil then
        info.answer = answer
        info.api = t.id
        info.detail = detail
        break
      end
    end
  end
  if info.api == nil then
    info.detail = "no API on this client names the character's professions"
  end
  info[ctx.id] = info.answer
  return info
end

-- One answer, cached per skill. Returns (answer, info, cached) where answer is
-- true (has the skill), false (does not) or nil (unreadable on this client).
local function answerFor(self, kind)
  local ctx = contextOf(kind)
  local now = (type(GetTime) == "function") and GetTime() or nil
  local caches = self._cache
  local last = type(caches) == "table" and caches[ctx.id] or nil
  if last and now and type(last.at) == "number" and (now - last.at) < self.TTL then
    return last.answer, last.info, true
  end
  local ok, info = pcall(self.Probe, self, ctx)
  if not ok or type(info) ~= "table" then
    -- A probe that raises is an unreadable client, never a verdict.
    if type(caches) == "table" then caches[ctx.id] = nil end
    local err = { answer = nil, id = ctx.id, label = ctx.label, api = nil, tried = {}, error = tostring(info) }
    return nil, err, false
  end
  if type(self._cache) ~= "table" then self._cache = {} end
  if now and info.answer ~= nil then
    self._cache[ctx.id] = { at = now, answer = info.answer, info = info }
  else
    self._cache[ctx.id] = nil
  end
  return info.answer, info, false
end

-- The gate the tooltip asks. Returns (answer, info, cached) where answer is
-- true (herbalist), false (not an herbalist), or nil (unreadable on this
-- client). `cached` says whether the answer came from the reuse window.
function Pr:Herbalism()
  return answerFor(self, "herbalism")
end

-- The same gate for the beast block (t_c0221fd7): true (skinner), false (not
-- a skinner), nil (unreadable).
function Pr:Skinning()
  return answerFor(self, "skinning")
end

-- Forget every reuse window (a spec or a slash command may want a fresh read).
function Pr:Forget()
  self._cache = nil
end

-- ── /nt ttdiag ─────────────────────────────────────────────────────────────
-- Which profession API the client exposed, and what it said about THIS
-- character. The lines are built from our own literals plus numbers and
-- booleans — no client string is measured or formatted here, so a secret name
-- can never cost the diagnostic.
function Pr:Diagnose()
  local out = {}
  local apis = { legacy = {}, modern = {}, modernExists = type(C_TradeSkillUI) == "table" }
  for _, n in ipairs(Pr.LEGACY_CANDIDATES) do
    if type(_G[n]) == "function" then
      apis.legacy[#apis.legacy + 1] = n
    end
  end
  if apis.modernExists then
    for _, n in ipairs(Pr.MODERN_CANDIDATES) do
      if type(C_TradeSkillUI[n]) == "function" then
        apis.modern[#apis.modern + 1] = n
      end
    end
  end
  out[#out + 1] = "api probed: legacy globals "
    .. (#apis.legacy > 0 and table.concat(apis.legacy, ", ") or "none")
    .. "; C_TradeSkillUI " .. (apis.modernExists and "present" or "absent")
    .. (apis.modernExists
      and (" (" .. (#apis.modern > 0 and table.concat(apis.modern, ", ") or "no profession call") .. ")")
      or "")

  -- A fresh read is what the diag is for: the reuse window would hide exactly
  -- the change the operator is looking for.
  local ok, info = pcall(self.Probe, self)
  if not ok or type(info) ~= "table" then
    out[#out + 1] = "this character: probe raised — " .. tostring(info)
    return out
  end
  local verdict = "unknown"
  if info.answer == true then
    verdict = "yes"
  elseif info.answer == false then
    verdict = "no"
  end
  out[#out + 1] = ("this character: herbalism=%s (from %s) — %s"):format(
    verdict, tostring(info.api or "no API"), tostring(info.detail or "no detail"))
  -- Every tier that did NOT answer, with its own reason. The tier that did
  -- answer is already quoted in the line above, so repeating it would be noise.
  for _, t in ipairs(info.tried) do
    if t.id ~= info.api then
      out[#out + 1] = (("  %s: %s — %s")):format(tostring(t.id), tostring(t.answer), tostring(t.detail))
    end
  end
  if info.answer == false then
    out[#out + 1] = "gate: this character cannot gather herbs — the herb block is hidden"
  elseif info.answer == nil then
    out[#out + 1] = "gate: profession unreadable on this client — the block shows without a picks line"
  else
    out[#out + 1] = "gate: the block shows, with the account-wide picks line"
  end

  -- The beast block's gate (t_c0221fd7). The same three tiers, asked about
  -- Skinning: a skinner sees the block, a non-skinner sees nothing, and an
  -- unreadable client is told apart from a "no" so a hidden block on a real
  -- skinner is diagnosable.
  local okS, skin = pcall(self.Probe, self, contextOf("skinning"))
  if not okS or type(skin) ~= "table" then
    out[#out + 1] = "this character: skinning probe raised — " .. tostring(skin)
  else
    local sv = "unknown"
    if skin.answer == true then
      sv = "yes"
    elseif skin.answer == false then
      sv = "no"
    end
    out[#out + 1] = ("this character: skinning=%s (from %s) — %s"):format(
      sv, tostring(skin.api or "no API"), tostring(skin.detail or "no detail"))
    for _, t in ipairs(skin.tried) do
      if t.id ~= skin.api then
        out[#out + 1] = (("  skin %s: %s — %s")):format(tostring(t.id), tostring(t.answer), tostring(t.detail))
      end
    end
    if skin.answer == false then
      out[#out + 1] = "gate: this character has no Skinning — the beast block is hidden"
    elseif skin.answer == nil then
      -- t_5ba9b43c: the beast block abstains where the herb block shows. Its
      -- every row is an aggregate of this character's own records, so an
      -- unconfirmed Skinning leaves nothing to say — and the old wording here
      -- ("the beast block shows") is what made a hidden panel look like a bug
      -- and a shown panel look correct.
      out[#out + 1] = "gate: skinning unreadable on this client — the beast block is hidden "
        .. "(it abstains; every row in it would be this character's own records)"
    else
      out[#out + 1] = "gate: the beast block shows on a beast hover"
    end
  end
  -- The hover path reuses a definitive answer for Pr.TTL seconds. Say what is in
  -- that window: a hover that answered from it may be up to TTL older than this
  -- fresh read.
  if type(GetTime) == "function" then
    local caches = self._cache
    local c = type(caches) == "table" and caches.herbalism or nil
    if c and type(c.at) == "number" then
      out[#out + 1] = ("cache: hovers reuse an answer read %ds ago (TTL %ds)"):format(
        math.max(0, math.floor(GetTime() - c.at)), self.TTL)
    else
      out[#out + 1] = "cache: nothing cached — every hover reads the client"
    end
    -- The beast gate keeps its own reuse window (t_5ba9b43c): a definitive
    -- "no"/"yes" held for TTL seconds is one of the two ways a beast hover can
    -- disagree with a fresh read, so it is named too. An "unknown" is never
    -- cached, so this line only ever reports a definitive answer.
    local sk = type(caches) == "table" and caches.skinning or nil
    if sk and type(sk.at) == "number" then
      out[#out + 1] = (("cache: beast hovers reuse a skinning answer read %ds ago (TTL %ds)")):format(
        math.max(0, math.floor(GetTime() - sk.at)), self.TTL)
    end
  end
  return out
end

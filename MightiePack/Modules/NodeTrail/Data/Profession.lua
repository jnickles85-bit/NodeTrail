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

-- The names this client itself uses for the herb profession: our two literals
-- plus whatever GetSpellInfo calls the gathering spell.
local function herbNames()
  local names = {}
  for _, n in ipairs(Pr.NAMES) do
    names[#names + 1] = n
  end
  if type(GetSpellInfo) == "function" then
    local ok, name = pcall(GetSpellInfo, Pr.SPELL_ID)
    if ok then
      addName(names, name)
    end
  end
  return names
end

-- Match a client string against those names. A secret string is never read:
-- the answer is a plain false, and the caller's "no Herbalism row" conclusion
-- stays a conclusion about the rows that WERE readable.
local function isHerbName(name, names)
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
function Pr:FromSkillLines()
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
  local names = herbNames()
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
    elseif type(a) == "string" and not isSecret(a) then
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
      if isHerbName(a, names) then
        found = true
        foundRank = type(rank) == "number" and rank or nil
        break
      end
    else
      -- The row answered with something that is not a readable name (nil, a
      -- table, or a secret string): the row exists, so its profession is
      -- unknown to us and cannot be ruled out.
      unreadable = unreadable + 1
    end
  end
  if rows == 0 then
    return nil, raiseMsg
      and ("GetSkillLineInfo raised: " .. raiseMsg)
      or ("GetSkillLineInfo answered no readable name in %d row(s)"):format(n)
  end
  local detail = ("%d skill line(s) read (%s)"):format(rows, shape or "shape unreadable")
  if not found then
    if unreadable > 0 then
      -- SOME rows answered and some did not. "No Herbalism" would then be a
      -- guess about rows we never saw — the direction that hides the block on a
      -- real herbalist — so this tier abstains and the next one gets a turn.
      return nil, detail .. ("; %d row(s) unreadable (%s) — Herbalism cannot be ruled out")
        :format(unreadable, raiseMsg and ("raised: " .. raiseMsg) or "no readable name")
    end
    return false, detail .. "; no Herbalism line"
  end
  if foundRank == nil then
    return nil, detail .. "; Herbalism line present but its rank was unreadable"
  end
  if foundRank > 0 then
    return true, detail .. ("; Herbalism rank %d"):format(foundRank)
  end
  return false, detail .. "; Herbalism line present at rank 0"
end

-- ── tier 2: the seven profession slots ────────────────────────────────────
-- GetProfessions() gives the skill-line indices this character has learned;
-- GetProfessionInfo(index) names each one. Definitive both ways once any slot
-- is named: an empty or unnameable list is "unknown", not "no".
function Pr:FromProfessions()
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
  local names = herbNames()
  local seen, herb, unreadable = 0, false, 0
  for slot = 1, 7 do
    local idx = list[slot]
    if type(idx) == "number" then
      local okI, name = pcall(GetProfessionInfo, idx)
      -- Decode the name ONCE, and match the decoded string: a client that
      -- answers `{ skillLineName = "Herbalism" }` must not be read as
      -- "no Herbalism" just because the raw return is a table.
      local nm = okI and profName(name) or nil
      if nm == nil then
        -- A slot index that names nothing is an empty slot, not a failure.
        if not okI then unreadable = unreadable + 1 end
      elseif isSecret(nm) then
        unreadable = unreadable + 1
      else
        seen = seen + 1
        if isHerbName(nm, names) then
          herb = true
        end
      end
    end
  end
  if herb then
    return true, ("%d learned profession(s) read; Herbalism among them"):format(seen)
  end
  if seen == 0 then
    return nil, "GetProfessionInfo named none of the profession slots"
  end
  if unreadable > 0 then
    -- Some slots were named and some were not readable: "no Herbalism" would be
    -- a guess about the slots we could not read, and a wrong "no" hides the
    -- block on a real herbalist.
    return nil, ("%d learned profession(s) read; %d slot(s) unreadable — Herbalism cannot be ruled out")
      :format(seen, unreadable)
  end
  return false, ("%d learned profession(s) read; no Herbalism"):format(seen)
end

-- ── tier 3: the open profession window (positive only) ────────────────────
-- These calls describe the window the player has OPEN, not the character's
-- learned professions. A closed window says nothing, so only a Herbalism
-- answer is usable here; anything else stays unknown.
function Pr:FromOpenWindow()
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
  local names = herbNames()
  local answered = nil
  for _, c in ipairs(candidates) do
    local ok, r = pcall(c.fn)
    if ok then
      local name = profName(r)
      if name ~= nil then
        answered = c.label
        if isHerbName(name, names) then
          return true, "the open profession window reports Herbalism (" .. c.label .. ")"
        end
      end
    end
  end
  if answered then
    return nil, ("%s named the OPEN window only, and it is not Herbalism — that says nothing about what this character has learned"):format(answered)
  end
  return nil, "the open-window calls answered no profession name"
end

-- ── the probe ─────────────────────────────────────────────────────────────
-- Returns info = { herbalism = true|false|nil, api = <tier id or nil>,
--                  detail = <what was read>, tried = { {id, answer, detail} } }
function Pr:Probe()
  local info = { herbalism = nil, api = nil, detail = nil, tried = {} }
  local tiers = {
    { id = "skill-lines", fn = Pr.FromSkillLines },
    { id = "professions", fn = Pr.FromProfessions },
    { id = "open-window", fn = Pr.FromOpenWindow },
  }
  for _, t in ipairs(tiers) do
    local ok, answer, detail = pcall(t.fn, Pr)
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
        info.herbalism = answer
        info.api = t.id
        info.detail = detail
        break
      end
    end
  end
  if info.api == nil then
    info.detail = "no API on this client names the character's professions"
  end
  return info
end

-- The gate the tooltip asks. Returns (answer, info, cached) where answer is
-- true (herbalist), false (not an herbalist), or nil (unreadable on this
-- client). `cached` says whether the answer came from the reuse window.
function Pr:Herbalism()
  local now = (type(GetTime) == "function") and GetTime() or nil
  local last = self._cache
  if last and now and type(last.at) == "number" and (now - last.at) < self.TTL then
    return last.info.herbalism, last.info, true
  end
  local ok, info = pcall(self.Probe, self)
  if not ok or type(info) ~= "table" then
    -- A probe that raises is an unreadable client, never a verdict.
    self._cache = nil
    return nil, { herbalism = nil, api = nil, tried = {}, error = tostring(info) }, false
  end
  if now and info.herbalism ~= nil then
    self._cache = { at = now, info = info }
  else
    self._cache = nil
  end
  return info.herbalism, info, false
end

-- Forget the reuse window (a spec or a slash command may want a fresh read).
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
  if info.herbalism == true then
    verdict = "yes"
  elseif info.herbalism == false then
    verdict = "no"
  end
  out[#out + 1] = ("this character: herbalism=%s (from %s) — %s"):format(
    verdict, tostring(info.api or "no API"), tostring(info.detail or "no detail"))
  -- Every tier that did NOT answer, with its own reason. The tier that did
  -- answer is already quoted in the line above, so repeating it would be noise.
  for _, t in ipairs(info.tried) do
    if t.id ~= info.api then
      out[#out + 1] = ("  %s: %s — %s"):format(tostring(t.id), tostring(t.answer), tostring(t.detail))
    end
  end
  if info.herbalism == false then
    out[#out + 1] = "gate: this character cannot gather herbs — the herb block is hidden"
  elseif info.herbalism == nil then
    out[#out + 1] = "gate: profession unreadable on this client — the block shows without a picks line"
  else
    out[#out + 1] = "gate: the block shows, with the account-wide picks line"
  end
  -- The hover path reuses a definitive answer for Pr.TTL seconds. Say what is in
  -- that window: a hover that answered from it may be up to TTL older than this
  -- fresh read.
  if type(GetTime) == "function" then
    local c = self._cache
    if c and type(c.at) == "number" then
      out[#out + 1] = ("cache: hovers reuse an answer read %ds ago (TTL %ds)"):format(
        math.max(0, math.floor(GetTime() - c.at)), self.TTL)
    else
      out[#out + 1] = "cache: nothing cached — every hover reads the client"
    end
  end
  return out
end

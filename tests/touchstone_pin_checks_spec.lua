-- The vendored set IS the pin: the COPY and PATCH checks, as a spec.
--
-- Run from the repo root:  lua5.1 tests/touchstone_pin_checks_spec.lua
--
-- tools/sync_touchstone.py --verify-shipped is the loud failure this shape exists
-- for: six pristine files hashed against the pin's blobs, eight patches reversed
-- back to the pin's blob. Neither needs StatForge (a private repository), so this
-- runs everywhere — and running it as a spec as well as a CI step means a broken
-- pin or a drifted patch fails in BOTH jobs, with the tool's own sentence naming
-- the file (COPY:) or the patch and the file (PATCH:) in the log.
--
-- The spec only asserts the verdict of that command; the message quality is the
-- tool's, and it is proven by hand in the card's own acceptance (alter one pristine
-- byte -> COPY reddens naming the file; break one patch anchor -> PATCH reddens
-- naming the patch and the file, and COPY stays green).

local here = (arg and arg[0] or "tests/touchstone_pin_checks_spec.lua"):match("^(.*)[/\\][^/\\]*$") or "."
local root = here:gsub("[/\\]tests$", "")
if root == "tests" then root = "." end

local cmd = "python3 tools/sync_touchstone.py --verify-shipped"
-- Lua 5.1 returns a wait status; 5.2+ returns true/false, "exit", code.
local r, a, b = os.execute(cmd)
local ok
if a ~= nil then
  ok = (r == true) or (b == 0)
else
  ok = (r == 0 or r == true)
end
if not ok then
  io.stderr:write("FAIL " .. cmd .. " (status " .. tostring(r) .. " "
    .. tostring(a) .. " " .. tostring(b) .. ")\n")
  io.stderr:write("the COPY/PATCH problems are printed by the tool itself, above.\n")
  os.exit(1)
end

-- And the pin the manifest names must be the pin the tool names. A drift between
-- these two would make the COPY check hash against a commit nobody is looking at.
local sf = io.open(root .. "/tools/sync_touchstone.py", "r")
local pf = io.open(root .. "/tools/touchstone-patches/pin.txt", "r")
local ref, pinRef
if sf then
  local src = sf:read("*a")
  sf:close()
  ref = src:match('SOURCE_REF%s*=%s*"([^"]+)"')
end
if pf then
  local manifest = pf:read("*a")
  pf:close()
  pinRef = manifest:match("ref%s+(%x+)")
end
if ref ~= pinRef or type(ref) ~= "string" then
  io.stderr:write("FAIL the manifest pin (" .. tostring(pinRef)
    .. ") is not SOURCE_REF (" .. tostring(ref) .. ")\n")
  os.exit(1)
end

print("ok")

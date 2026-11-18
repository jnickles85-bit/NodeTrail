-- CI cannot clone private StatForge, so the patch applicator is tested through the
-- sync script's own fixtures — and the committed set is checked WITHOUT upstream by
-- tests/touchstone_pin_checks_spec.lua (`--verify-shipped`: eight pristine files hashed
-- against the pin's blobs, eight patches reversed back to it).
local cmd = "python3 tools/sync_touchstone.py --self-test-patches"
local ok, term, code
-- Lua 5.1 returns a wait status; 5.2+ returns true/false, "exit", code.
local r, a, b = os.execute(cmd)
if a ~= nil then
  ok = (r == true) or (b == 0)
else
  ok = (r == 0 or r == true)
end
if not ok then
  io.stderr:write("FAIL " .. cmd .. " (status " .. tostring(r) .. " " .. tostring(a) .. " " .. tostring(b) .. ")\n")
  os.exit(1)
end
print("ok")

-- Run from the repository root: lua .tools/tests/test_cdm_bar_glow_health.lua
-- Health threshold gating combines with the glow's primary state.
local ROOT = arg and arg[1] or "."

local f = assert(io.open(ROOT .. "/EllesmereUICooldownManager/EllesmereUICdmBarGlowConditions.lua", "rb"))
local src = f:read("*a")
f:close()

local fn = assert(loadstring(src .. "\nreturn ns"))
local ns = {}
local current, maximum = 100, 100
EllesmereUI = { IS_FOREVER = true }
UnitHealth = function() return current end
UnitHealthMax = function() return maximum end

setfenv(fn, setmetatable({
    ns = ns,
    EllesmereUI = EllesmereUI,
    UnitHealth = UnitHealth,
    UnitHealthMax = UnitHealthMax,
}, { __index = _G }))
local loaded = fn(nil, ns)

assert(loaded.BarGlowCombine({}, true, {}) == true)
assert(loaded.BarGlowCombine({ healthBelow = 35 }, true, {}) == false)
current = 34
assert(loaded.BarGlowCombine({ healthBelow = 35 }, true, {}) == true)
assert(loaded.BarGlowCombine({ healthBelow = 35 }, false, {}) == false)
current = 35
assert(loaded.BarGlowHealthPass({ healthBelow = 35 }) == false)
assert(loaded.BarGlowHealthPass({ healthAbove = 35 }) == false)
current = 34
assert(loaded.BarGlowHealthPass({ healthBelow = 35 }) == true)
assert(loaded.BarGlowHealthPass({ healthAbove = 35 }) == false)
current = 36
assert(loaded.BarGlowHealthPass({ healthAbove = 35 }) == true)

print("test_cdm_bar_glow_health: all checks passed")

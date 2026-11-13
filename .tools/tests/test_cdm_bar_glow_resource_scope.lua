-- Run from the repository root: lua .tools/tests/test_cdm_bar_glow_resource_scope.lua
-- Resource-aware bar-glow policy precedence and per-specialization exclusions.
local ROOT = arg and arg[1] or "."

local f = assert(io.open(ROOT .. "/EllesmereUICooldownManager/EllesmereUICdmBarGlows.lua", "rb"))
local src = f:read("*a")
f:close()

local start = assert(src:find("local function GetBarGlowResourcePolicy"))
local finish = assert(src:find("\n%-%- Options: the ability", start))
local fn = assert(loadstring(src:sub(start, finish - 1) .. "\nreturn ns"))

local ns = {
    GetActiveProfileName = function() return "Default" end,
    GetActiveSpecKey = function() return "arms" end,
    GetSpecProfilesForProfile = function(name)
        EllesmereUIDB.spellAssignments.profiles[name] =
            EllesmereUIDB.spellAssignments.profiles[name] or {}
    end,
}
EllesmereUIDB = { spellAssignments = { profiles = {} } }

setfenv(fn, setmetatable({
    ns = ns,
    EllesmereUIDB = EllesmereUIDB,
    BaseSpell = function(sid) return sid end,
}, { __index = _G }))
local loaded = fn()

assert(loaded.BarGlowResourceScope(100) == "legacy")
assert(loaded.BarGlowRequirePower(100, { requirePower = true }) == true)
loaded.SetBarGlowResourceScope(100, "spell")
assert(loaded.BarGlowResourceScope(100) == "spell")

loaded.SetBarGlowResourceScope(101, "spec")
assert(loaded.BarGlowResourceScope(101) == "spec")
loaded.SetBarGlowResourceScope(101, "legacy")
assert(loaded.BarGlowResourceScope(101) == "legacy")
assert(loaded.BarGlowRequirePower(101, { requirePower = true }) == false)

ns.GetActiveSpecKey = function() return "fury" end
loaded.SetBarGlowResourceScope(102, "all")
assert(loaded.BarGlowResourceScope(102) == "all")
loaded.SetBarGlowResourceScope(102, "legacy")
assert(loaded.BarGlowResourceScope(102) == "legacy")
ns.GetActiveSpecKey = function() return "arms" end
assert(loaded.BarGlowResourceScope(102) == "spec")

print("test_cdm_bar_glow_resource_scope: all checks passed")

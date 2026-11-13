-- Run from the repository root: lua .tools/tests/test_cdm_swing_sweep.lua
-- WoW Forever Swing Timer swipe (EUI_CDM_ForeverSwingSweep.lua): inert without
-- the swing API or for a class with no on-next-swing attack; nothing listens
-- until an icon of such an attack has the setting; each swing of the attack's
-- hand starts the swipe on our own Cooldown, never the icon's; a reanchor
-- mid-swing paints the icons it placed; a real cooldown and the setting
-- switched off leave no swipe and no listener.
EUI_CLIENT_BLOCKED = false
local ROOT = arg and arg[1] or "."
local FILE = ROOT .. "/EllesmereUICooldownManager/EUI_CDM_ForeverSwingSweep.lua"

local NOW = 100
local NAMES = { [78] = "Heroic Strike", [11567] = "Heroic Strike", [845] = "Cleave", [100] = "Charge" }
local REAL_CD = {}   -- [spellID] = on a cooldown of its own

local function NewCooldown(parent)
    local cd = { _parent = parent, _level = 0, sets = 0 }
    function cd:SetCooldown(start, dur) self.start, self.dur = start, dur; self.sets = self.sets + 1 end
    function cd:Clear() self.start, self.dur = nil, nil end
    function cd:SetFrameLevel(l) self._level = l end
    function cd:GetFrameLevel() return self._level end
    return setmetatable(cd, { __index = function(_, k)
        if type(k) == "string" and k:find("^%u") then return function() end end
    end })
end
local function NewIcon()
    local icon = { Cooldown = NewCooldown() }
    icon.Cooldown._level = 14
    function icon:GetFrameLevel() return 1 end
    return icon
end

local shell
local function Globals(class, api)
    Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 } }
    C_SwingTimer = api and {} or nil
    C_Spell = {
        GetSpellName = function(id) return NAMES[id] end,
        GetSpellCooldown = function(id) return { isActive = REAL_CD[id] == true, isOnGCD = false } end,
    }
    UnitClass = function() return class, class end
    GetTime = function() return NOW end
    issecretvalue = function() return false end
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    CreateFrame = function(_, _, parent) return NewCooldown(parent) end
    EllesmereUIDB = {}
    EllesmereUI = {
        FOREVER_NEXT_SWING = { WARRIOR = { 78, 845 } },
        PlainString = function(v) return type(v) == "string" and v ~= "" and v or nil end,
    }
end

local ns, settings, cas, saved
local function Load(class, api)
    Globals(class, api)
    settings, cas, saved = {}, {}, {}
    shell = { events = {} }
    function shell:RegisterEvent(e) self.events[e] = true end
    function shell:UnregisterEvent(e) self.events[e] = nil end
    function shell:SetScript(_, fn) self.onEvent = fn end
    ns = {
        TakeShell = function() return shell end,
        cdmBarIcons = {}, barDataByKey = { cooldowns = {} }, _ecmeFC = {},
        _hookInternals = {},
        IsBarBuffFamily = function() return false end,
        CdmIsInjectedFrame = function(icon) return icon._isCustomSpellFrame == true end,
        ResolveSpellSettings = function(_, sid) return settings[sid] end,
        GetEffectiveCustomActiveState = function(sid) return cas[sid] end,
        GetCustomActiveStates = function() return cas end,
        ForEachSavedSettingsBlock = function(fn)
            for _, ss in ipairs(saved) do if fn(ss) then return true end end
            return false
        end,
        EffectiveReverseSwipe = function(_, _, base) return base end,
        ApplyShapeToOverlay = function() end,
        CdmSwipeFile = function() return "swipe" end,
        CdmOnRealCD = function(_, info) return info.isActive and not info.isOnGCD end,
    }
    assert(loadfile(FILE))("EllesmereUICooldownManager", ns)
end

local function Place(icon, sid)
    ns._ecmeFC[icon] = { spellID = sid, barKey = "cooldowns" }
    local list = ns.cdmBarIcons.cooldowns or {}
    ns.cdmBarIcons.cooldowns = list
    list[#list + 1] = icon
    return icon
end
local function Swing(dur, hand) shell.onEvent(shell, "PLAYER_SWING", dur, hand) end
local function Listening() return shell.events.PLAYER_SWING == true end
-- Our Cooldown over an icon: the one frame made with the icon as its parent.
local made
local function Track()
    made = {}
    local create = CreateFrame
    CreateFrame = function(kind, name, parent)
        local cd = create(kind, name, parent)
        made[parent] = cd
        return cd
    end
end

-------------------------------------------------------------------------------
-- 1. Retail (no swing API) and a class with no such attack: nothing is defined.
-------------------------------------------------------------------------------
Load("WARRIOR", false)
assert(ns.CDM_SwingSweepSync == nil and ns.CDM_IsSwingSweepSpell == nil and ns.RescanSwingSweepFlag == nil,
    "without the swing API the file is inert")
Load("MAGE", true)
assert(ns.CDM_SwingSweepSync == nil and ns.CDM_IsSwingSweepSpell == nil, "a class with no such attack: inert")

-------------------------------------------------------------------------------
-- 2. The menu's test: every rank of an attack, by name; nothing else.
-------------------------------------------------------------------------------
Load("WARRIOR", true)
Track()
assert(ns.CDM_IsSwingSweepSpell(78) and ns.CDM_IsSwingSweepSpell(11567) and ns.CDM_IsSwingSweepSpell(845))
assert(not ns.CDM_IsSwingSweepSpell(100) and not ns.CDM_IsSwingSweepSpell(-5) and not ns.CDM_IsSwingSweepSpell("c1"))

-------------------------------------------------------------------------------
-- 3. Off by default: nothing saved, so the gate stays down and nothing listens.
-------------------------------------------------------------------------------
local hs = Place(NewIcon(), 11567)
local charge = Place(NewIcon(), 100)
ns.RescanSwingSweepFlag()
ns.CDM_SwingSweepSync()
assert(not ns._cdmAnySwingSweep and not Listening() and not made[hs], "no saved setting: no gate, no event, no frame")

-------------------------------------------------------------------------------
-- 4. Switched on for Heroic Strike: the Main Hand swing starts the swipe on our
--    own Cooldown and restarts it; the Off Hand and other spells never do.
-------------------------------------------------------------------------------
settings[11567] = { showSwingTimer = true }
settings[100] = { showSwingTimer = true }   -- a bar tier reaches every spell on the bar
ns._cdmAnySwingSweep = true
ns.CDM_SwingSweepSync()
assert(Listening(), "an icon with the setting: PLAYER_SWING is registered")
assert(made[hs] and not made[charge], "only the on-next-swing attack gets a swipe")
assert(made[hs]:GetFrameLevel() == 14, "the swipe sits at the icon's own cooldown level")
assert(made[hs].start == nil, "no swing yet: nothing drawn")
Swing(2.6, Enum.PlayerSwingType.MainHand)
assert(made[hs].start == 100 and made[hs].dur == 2.6, "the swing's duration, from now")
assert(hs.Cooldown.sets == 0, "the icon's own cooldown is never written")
NOW = 101
Swing(1.4, Enum.PlayerSwingType.OffHand)
assert(made[hs].start == 100 and made[hs].dur == 2.6, "an Off Hand swing leaves the swipe alone")
NOW = 102.6
Swing(2.4, Enum.PlayerSwingType.MainHand)
assert(made[hs].start == 102.6 and made[hs].dur == 2.4, "each Main Hand swing restarts it")

-------------------------------------------------------------------------------
-- 5. A reanchor mid-swing hands the spell another frame: the new frame shows
--    the running swing, the old one drops it.
-------------------------------------------------------------------------------
NOW = 103
local hs2 = NewIcon()
ns.cdmBarIcons.cooldowns = {}
Place(hs, 100)
Place(hs2, 11567)
ns.CDM_SwingSweepSync()
assert(made[hs2].start == 102.6 and made[hs2].dur == 2.4, "the frame this pass placed shows the running swing")
assert(made[hs].start == nil, "the frame that lost the spell is cleared")
assert(Listening())

-------------------------------------------------------------------------------
-- 6. A cooldown of the spell's own: the icon's swipe shows it, ours stays out.
-------------------------------------------------------------------------------
REAL_CD[11567] = true
NOW = 105
Swing(2.4, Enum.PlayerSwingType.MainHand)
assert(made[hs2].start == nil, "a real cooldown is never covered")
REAL_CD[11567] = nil
NOW = 107.4
Swing(2.4, Enum.PlayerSwingType.MainHand)
assert(made[hs2].start == 107.4, "back once the cooldown is over")

-------------------------------------------------------------------------------
-- 7. Switched off: the swipe goes and nothing listens.
-------------------------------------------------------------------------------
settings[11567].showSwingTimer = false
ns.CDM_SwingSweepSync()
assert(made[hs2].start == nil and not Listening(), "off: swipe cleared, PLAYER_SWING unregistered")

-------------------------------------------------------------------------------
-- 8. A custom spell reads customActiveStates, never the bar tier; the saved
--    setting arms the gate at setup (a /reload).
-------------------------------------------------------------------------------
Load("WARRIOR", true)
Track()
local custom = Place(NewIcon(), 845)
custom._isCustomSpellFrame = true
settings[845] = { showSwingTimer = true }
ns._cdmAnySwingSweep = true
ns.CDM_SwingSweepSync()
assert(not Listening(), "a bar tier does not reach a custom spell")
ns._cdmAnySwingSweep = nil
cas[845] = { showSwingTimer = true }
ns.RescanSwingSweepFlag()
assert(ns._cdmAnySwingSweep == true, "the saved custom spell setting arms the gate")
ns.CDM_SwingSweepSync()
assert(Listening() and made[custom], "and its icon shows the swipe")

Load("WARRIOR", true)
saved[1] = { showSwingTimer = true }
ns.RescanSwingSweepFlag()
assert(ns._cdmAnySwingSweep == true, "a saved per-spell setting arms the gate")

print("test_cdm_swing_sweep: all checks passed")

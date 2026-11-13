-- Run from the repository root: lua .tools/tests/test_ab_swing_sweep.lua
-- WoW Forever Swing Timer swipe on action buttons
-- (EUI_ActionBars_ForeverSwingSweep.lua): inert without the swing API or for a
-- class with no on-next-swing attack; nothing listens while the setting is
-- off; on, each swing of the attack's hand starts the swipe on our own
-- Cooldown over the button, never the button's; a page change moves it to the
-- button that holds the attack now; a real cooldown and the setting switched
-- off leave no swipe and no listener.
EUI_CLIENT_BLOCKED = false
local ROOT = arg and arg[1] or "."
local FILE = ROOT .. "/EllesmereUIActionBars/EUI_ActionBars_ForeverSwingSweep.lua"

local NOW = 100
local NAMES = { [78] = "Heroic Strike", [11567] = "Heroic Strike", [6807] = "Maul", [100] = "Charge" }
local REAL_CD = {}   -- [slot] = on a cooldown of its own
local TIMERS = {}    -- C_Timer.After callbacks, run by Flush

local function NewCooldown(parent)
    local cd = { _parent = parent, _level = 0, sets = 0 }
    function cd:SetCooldown(start, dur) self.start, self.dur = start, dur; self.sets = self.sets + 1 end
    function cd:Clear() self.start, self.dur = nil, nil end
    function cd:SetFrameLevel(l) self._level = l end
    function cd:GetFrameLevel() return self._level end
    function cd:IsForbidden() return false end
    function cd:SetSwipeTexture(tex) self.swipeTex = tex end
    function cd:AddMaskTexture(m) self.mask = m end
    function cd:RemoveMaskTexture() self.mask = nil end
    return setmetatable(cd, { __index = function(_, k)
        if type(k) == "string" and k:find("^%u") then return function() end end
    end })
end

local shell, ns, profile, made, SPELL
local function Load(class, api)
    Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 } }
    C_SwingTimer = api and {} or nil
    C_Spell = { GetSpellName = function(id) return NAMES[id] end }
    C_ActionBar = { GetActionCooldown = function(slot)
        return { isActive = REAL_CD[slot] == true, isOnGCD = false }
    end }
    C_Timer = { After = function(_, fn) TIMERS[#TIMERS + 1] = fn end }
    UnitClass = function() return class, class end
    GetTime = function() return NOW end
    issecretvalue = function() return false end
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    made = {}
    CreateFrame = function(_, _, parent)
        local cd = NewCooldown(parent)
        made[parent] = cd
        return cd
    end
    EllesmereUI = {
        FOREVER_NEXT_SWING = { WARRIOR = { 78 }, DRUID = { 6807 } },
        PlainString = function(v) return type(v) == "string" and v ~= "" and v or nil end,
    }
    shell = { events = {} }
    function shell:RegisterEvent(e) self.events[e] = true end
    function shell:UnregisterAllEvents() self.events = {} end
    function shell:SetScript(_, fn) self.onEvent = fn end
    profile = {}
    SPELL = {}   -- [button] = the spell its slot holds now
    ns = {
        TakeShell = function() return shell end,
        EAB = { db = { profile = profile } },
        barButtons = { MainBar = {}, StanceBar = {} },
        _eabFD = {},
        _internals = {
            BAR_CONFIG = { { key = "MainBar" }, { key = "StanceBar", isStance = true } },
            GetButtonActionSlot = function(btn) return btn.slot end,
        },
        AB_ButtonSpellID = function(btn) return SPELL[btn] end,
    }
    assert(loadfile(FILE))("EllesmereUIActionBars", ns)
end

local function Button(bar, slot, sid)
    local btn = { slot = slot, cooldown = NewCooldown() }
    btn.cooldown._level = 7
    function btn:GetFrameLevel() return 1 end
    SPELL[btn] = sid
    local list = ns.barButtons[bar]
    list[#list + 1] = btn
    return btn
end
local function Event(...) shell.onEvent(shell, ...) end
local function Swing(dur, hand) Event("PLAYER_SWING", dur, hand) end
local function Flush()
    local run = TIMERS
    TIMERS = {}
    for i = 1, #run do run[i]() end
end
local function Listening() return shell.events.PLAYER_SWING == true end

-------------------------------------------------------------------------------
-- 1. Retail (no swing API) and a class with no such attack: nothing is defined.
-------------------------------------------------------------------------------
Load("WARRIOR", false)
assert(ns.AB_SwingSweepApply == nil, "without the swing API the file is inert")
Load("MAGE", true)
assert(ns.AB_SwingSweepApply == nil, "a class with no such attack: inert")

-------------------------------------------------------------------------------
-- 2. Off by default: the full apply registers nothing and makes no frame.
-------------------------------------------------------------------------------
Load("WARRIOR", true)
local hs = Button("MainBar", 3, 11567)
local charge = Button("MainBar", 4, 100)
local stance = Button("StanceBar", 1, 78)
ns.AB_SwingSweepApply()
assert(not Listening() and next(shell.events) == nil and not made[hs], "off: no event, no frame")

-------------------------------------------------------------------------------
-- 3. On: the Main Hand swing starts the swipe over the attack's button and
--    restarts it; the Off Hand, other spells and the stance bar never do.
-------------------------------------------------------------------------------
profile.swingTimerSwipe = true
ns.AB_SwingSweepApply()
assert(Listening() and shell.events.ACTIONBAR_SLOT_CHANGED, "on: the swing and the content events are registered")
assert(made[hs] and not made[charge] and not made[stance], "only a bar button holding the attack gets a swipe")
assert(made[hs]:GetFrameLevel() == 7, "the swipe sits at the button's own cooldown level")
assert(made[hs].start == nil, "no swing yet: nothing drawn")
Swing(2.6, Enum.PlayerSwingType.MainHand)
assert(made[hs].start == 100 and made[hs].dur == 2.6, "the swing's duration, from now")
assert(hs.cooldown.sets == 0, "the button's own cooldown is never written")
NOW = 101
Swing(1.4, Enum.PlayerSwingType.OffHand)
assert(made[hs].start == 100 and made[hs].dur == 2.6, "an Off Hand swing leaves the swipe alone")
NOW = 102.6
Swing(2.4, Enum.PlayerSwingType.MainHand)
assert(made[hs].start == 102.6 and made[hs].dur == 2.4, "each Main Hand swing restarts it")

-------------------------------------------------------------------------------
-- 4. A page change mid-swing: one deferred scan for the burst moves the swipe
--    to the button that holds the attack now.
-------------------------------------------------------------------------------
NOW = 103
SPELL[hs], SPELL[charge] = 100, 11567
Event("ACTIONBAR_PAGE_CHANGED")
Event("UPDATE_BONUS_ACTIONBAR")
Event("ACTIONBAR_SLOT_CHANGED", 3)
assert(#TIMERS == 1, "a burst of content events queues one scan")
Flush()
assert(made[charge].start == 102.6 and made[charge].dur == 2.4, "the button holding it now shows the running swing")
assert(made[hs].start == nil, "the button that lost it is cleared")
-- A page that turns back before its scan: the next swing checks the button.
SPELL[charge] = 100
NOW = 105
Swing(2.4, Enum.PlayerSwingType.MainHand)
assert(made[charge].start == nil, "a swing never paints a button that no longer holds the attack")
SPELL[charge] = 11567
ns.AB_SwingSweepPageEdge()
assert(#TIMERS == 1, "a bar's page edge queues the scan")
NOW = 105.3
Flush()
assert(made[charge].start == 105, "the page edge's scan finds the button again")

-------------------------------------------------------------------------------
-- 5. A cooldown of the action's own: the button's swipe shows it, ours stays out.
-------------------------------------------------------------------------------
REAL_CD[4] = true
NOW = 107.4
Swing(2.4, Enum.PlayerSwingType.MainHand)
assert(made[charge].start == nil, "a real cooldown is never covered")
REAL_CD[4] = nil
NOW = 109.8
Swing(2.4, Enum.PlayerSwingType.MainHand)
assert(made[charge].start == 109.8, "back once the cooldown is over")

-------------------------------------------------------------------------------
-- 6. A shaped button: the swipe takes the button's mask, and drops it again.
-------------------------------------------------------------------------------
ns._eabFD[charge] = { shapeApplied = true, shapeMask = "mask", shapeMaskPath = "mask.tga" }
NOW = 112.2
Swing(2.4, Enum.PlayerSwingType.MainHand)
assert(made[charge].mask == "mask" and made[charge].swipeTex == "mask.tga", "the shape masks the swipe")
ns._eabFD[charge].shapeApplied = nil
NOW = 114.6
Swing(2.4, Enum.PlayerSwingType.MainHand)
assert(made[charge].mask == nil and made[charge].swipeTex == "", "and is dropped with the shape")

-------------------------------------------------------------------------------
-- 7. Switched off: the swipe goes and nothing listens.
-------------------------------------------------------------------------------
profile.swingTimerSwipe = false
ns.AB_SwingSweepApply()
assert(made[charge].start == nil and next(shell.events) == nil, "off: swipe cleared, every event unregistered")
ns.AB_SwingSweepPageEdge()
assert(#TIMERS == 0, "off: a page edge queues no scan")
Event("ACTIONBAR_SLOT_CHANGED", 4)
Flush()
assert(made[charge].start == nil, "a scan left over from before does nothing")

print("test_ab_swing_sweep: all checks passed")

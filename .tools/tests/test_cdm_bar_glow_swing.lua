-- Run from the repository root: lua .tools/tests/test_cdm_bar_glow_swing.lua
-- WoW Forever Bar Glow swing condition (EllesmereUICdmBarGlowSwing.lua): inert
-- without the swing API; nothing listens until a bound entry has a window; the
-- condition holds only in the last seconds of the running Main Hand swing and
-- not while the button's own attack is queued; the glow pass re-runs as the
-- window opens, as the swing ends and when the queued attack changes.
EUI_CLIENT_BLOCKED = false
local ROOT = arg and arg[1] or "."
local FILE = ROOT .. "/EllesmereUICooldownManager/EllesmereUICdmBarGlowSwing.lua"

local NOW = 100
local NAMES = { [78] = "Heroic Strike", [845] = "Cleave", [11567] = "Heroic Strike", [100] = "Charge" }
local CURRENT          -- the attack name queued now
local TIMERS = {}      -- { at =, fn = }
local shell, ns, repaints

local function Load(api, class)
    Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 } }
    C_SwingTimer = api and {} or nil
    C_Spell = {
        GetSpellName = function(id) return NAMES[id] end,
        IsCurrentSpell = function(name) return name == CURRENT end,
    }
    C_Timer = { After = function(delay, fn) TIMERS[#TIMERS + 1] = { at = NOW + delay, fn = fn } end }
    UnitClass = function() return class, class end
    GetTime = function() return NOW end
    issecretvalue = function() return false end
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    EllesmereUI = {
        FOREVER_NEXT_SWING = { WARRIOR = { 78, 845 } },
        PlainString = function(v) return type(v) == "string" and v ~= "" and v or nil end,
    }
    shell = { events = {}, shown = true }
    function shell:RegisterEvent(e) self.events[e] = true end
    function shell:UnregisterAllEvents() self.events = {} end
    function shell:SetScript(kind, fn) self[kind] = fn end
    function shell:Show() self.shown = true end
    function shell:Hide() self.shown = false end
    repaints = 0
    TIMERS = {}
    CURRENT = nil
    ns = {
        TakeShell = function() return shell end,
        UpdateOverlayVisuals = function() repaints = repaints + 1 end,
    }
    assert(loadfile(FILE))("EllesmereUICooldownManager", ns)
end

-- Advance the clock, running the timers that came due and the frame's flush.
local function Advance(to)
    NOW = to
    local due = {}
    for i = #TIMERS, 1, -1 do
        if TIMERS[i].at <= NOW + 1e-9 then due[#due + 1] = table.remove(TIMERS, i) end
    end
    for i = 1, #due do due[i].fn() end
    if shell.shown then shell.OnUpdate(shell) end
end
local function Swing(dur, hand) shell.OnEvent(shell, "PLAYER_SWING", dur, hand) end
local MH = 0

-------------------------------------------------------------------------------
-- 1. Retail: nothing is defined, so the key is ignored by the glow pass.
-------------------------------------------------------------------------------
Load(false, "WARRIOR")
assert(ns.BarGlowSwingPass == nil and ns.BarGlowSwingSync == nil, "without the swing API the file is inert")

-------------------------------------------------------------------------------
-- 2. No entry uses a window: nothing listens; an entry without the key passes.
-------------------------------------------------------------------------------
Load(true, "WARRIOR")
assert(shell.shown == false, "the flush starts hidden")
ns.BarGlowSwingSync(nil)
assert(next(shell.events) == nil, "no window in use: no events")
assert(ns.BarGlowSwingPass({}, 845) == true, "an entry without a window is not limited")

-------------------------------------------------------------------------------
-- 3. A window in use: only the last seconds of the Main Hand swing pass, and
--    the glow pass re-runs as the window opens and as the swing ends.
-------------------------------------------------------------------------------
local entry = { swingWindow = 0.5 }
ns.BarGlowSwingSync({ [0.5] = true })
assert(shell.events.PLAYER_SWING and shell.events.ACTIONBAR_UPDATE_STATE, "the swing and queue events are registered")
assert(ns.BarGlowSwingPass(entry, 845) == false, "no swing running: outside the window")
Swing(1.4, 1)
assert(ns.BarGlowSwingPass(entry, 845) == false and #TIMERS == 0, "an Off Hand swing is not the swing")
Swing(2.0, MH)
assert(ns.BarGlowSwingPass(entry, 845) == false, "early in the swing: no glow")
local before = repaints
Advance(101.4)
assert(repaints == before and ns.BarGlowSwingPass(entry, 845) == false, "still before the window")
Advance(101.5)
assert(repaints == before + 1, "the window opening re-runs the glow pass")
assert(ns.BarGlowSwingPass(entry, 845) == true, "inside the last half second")
assert(ns.BarGlowSwingPass(entry, 100) == true, "any spell's glow can use the window")
Advance(102)
assert(repaints == before + 2, "the swing's end re-runs the glow pass")
assert(ns.BarGlowSwingPass(entry, 845) == false, "the swing is over and none followed")

-------------------------------------------------------------------------------
-- 4. The attack already queued: its own button stops prompting, others do not.
-------------------------------------------------------------------------------
Swing(2.0, MH)
Advance(103.6)
assert(ns.BarGlowSwingPass(entry, 845) == true)
before = repaints
CURRENT = "Cleave"
shell.OnEvent(shell, "ACTIONBAR_UPDATE_STATE")
shell.OnEvent(shell, "ACTIONBAR_UPDATE_STATE")
Advance(103.7)
assert(repaints == before + 1, "a burst of state events re-runs the glow pass once")
assert(ns.BarGlowSwingPass(entry, 845) == false, "Cleave is queued: its glow stops")
assert(ns.BarGlowSwingPass(entry, 11567) == true, "Heroic Strike, any rank, is still unqueued")
before = repaints
shell.OnEvent(shell, "ACTIONBAR_UPDATE_STATE")
Advance(103.8)
assert(repaints == before, "an unchanged queue repaints nothing")
-- The swing lands and carries the attack: the next swing starts clean.
CURRENT = nil
Advance(104)
Swing(2.0, MH)
Advance(105.6)
assert(ns.BarGlowSwingPass(entry, 845) == true, "the next swing prompts again")

-------------------------------------------------------------------------------
-- 5. A swing restarted early: the earlier swing's timers do nothing.
-------------------------------------------------------------------------------
Swing(2.0, MH)        -- at 105.6, ends 107.6
before = repaints
Advance(106)          -- the 104 swing's end timer comes due here
assert(repaints == before, "a timer of an earlier swing is ignored")
assert(ns.BarGlowSwingPass(entry, 845) == false, "the window follows the new swing")

-------------------------------------------------------------------------------
-- 6. No window left: everything is unregistered and pending timers do nothing.
-------------------------------------------------------------------------------
ns.BarGlowSwingSync(nil)
assert(next(shell.events) == nil, "off: every event unregistered")
before = repaints
Advance(110)
assert(repaints == before, "off: pending timers repaint nothing")
assert(ns.BarGlowSwingPass(entry, 845) == false, "off: no swing is known")

-------------------------------------------------------------------------------
-- 7. A class with no on-next-swing attack: the window works, no queue event.
-------------------------------------------------------------------------------
Load(true, "MAGE")
ns.BarGlowSwingSync({ [1] = true })
assert(shell.events.PLAYER_SWING and not shell.events.ACTIONBAR_UPDATE_STATE, "no attack to queue: no state event")
Swing(2.0, MH)
Advance(NOW + 1.2)
assert(ns.BarGlowSwingPass({ swingWindow = 1 }, 100) == true)

print("test_cdm_bar_glow_swing: all checks passed")

package.path = './scripts/?.lua;' .. package.path
local create = require 'autoattack/controller'
local frame = 1 / 30
local function fixture(predicted, ping, special, options)
    local sim = { now = 0, attacks = 0, requests = 0, rejected = 0, rpcs = {}, logs = {}, attack_times = {},
        manual = false, valid = true, player_x = 5, target_x = 3, network_reads = 0 }
    for key, value in pairs(options or {}) do sim[key] = value end
    local sent
    local observed_at
    local pc = { ismastersim = false, remote_controls = {}, locomotor = predicted and {} or nil }
    local target = { IsValid = function() return sim.target_valid ~= false end,
        HasTag = function() return false end,
        GetPhysicsRadius = function() return 0 end,
        Transform = { GetWorldPosition = function() return sim.target_x, 0, 0 end } }
    local function active()
        return not sim.cancelled and sent ~= nil and sim.now >= observed_at and
            sim.now < observed_at + (sim.duration_frames or 13) * frame - .000000001 and
            (sim.walk_clears_at == nil or sim.now < sim.walk_clears_at)
    end
    local player = {
        IsValid = function() return sim.valid end,
        GetPhysicsRadius = function() return 0 end,
        Transform = { GetWorldPosition = function() return sim.player_x, 0, 0 end },
        HasTag = function(_, name) return name == 'attack' and active() end,
        AnimState = {
            IsCurrentAnimation = function(_, name)
                local animation = sim.animation
                if type(animation) == 'function' then animation = animation(sim.now - (observed_at or 0)) end
                return active() and name == (animation or 'atk')
            end,
            GetCurrentAnimationFrame = function()
                if sim.animation_frame then return sim.animation_frame(sim.now - (observed_at or 0)) end
                return math.floor((sim.now - (observed_at or 0)) / frame + .00001) - (sim.windup_frames or 0)
            end,
            GetCurrentAnimationNumFrames = function()
                if sim.animation_length then return sim.animation_length(sim.now - (observed_at or 0)) end
            end,
        },
        replica = {
            rider = { IsRiding = function() return special or false end },
            inventory = { GetEquippedItem = function() return sim.weapon end },
        },
        components = { playercontroller = pc },
    }
    player.sg = predicted and { HasStateTag = function(_, tag)
        if tag == 'attack' then return active() end
        return tag == 'abouttoattack' and active() and sim.now < observed_at + (sim.release_frames or 8) * frame
    end } or nil
    local combat = {
        CanTarget = function(_, t) return t:IsValid() end,
        IsAlly = function() return false end,
        InCooldown = function()
            if sim.unsynced_cooldown then return false end
            return sent ~= nil and sim.now < observed_at + (sim.cooldown or .5)
        end,
        MinAttackPeriod = function() return sim.min_period end,
        CanAttack = function()
            if sim.track_range then return math.abs(sim.player_x - sim.target_x) <= (sim.range or 2.7) - .5 end
            return sim.in_range ~= false
        end,
        LocomotorCanAttack = function() return false, false, false end,
        GetAttackRangeWithWeapon = function() return sim.range or 2.7 end,
        GetWeapon = function() return sim.weapon end,
    }
    player.replica.combat = combat
    pc.GetCombatRetarget = function() end
    pc.IsEnabled = function() return true end
    pc.IsBusy = function() return false end
    pc.CanLocomote = function() return predicted end
    pc.RemoteStopControl = function() sim.stopped = true end
    pc.GetAttackTarget = function(_, force, preferred)
        sim.force_selected = force
        if sim.search_limit and math.abs(sim.player_x - sim.target_x) > (sim.range or 2.7) + 6 then return nil end
        if preferred == target then sim.retargeted = (sim.retargeted or 0) + 1 end
        return sim.target_valid ~= false and target or nil
    end
    pc.DoAttackButton = function(_, attack_target)
        assert(attack_target == target, "must attack vanilla-selected target")
        sim.requests = sim.requests + 1
        local arrival = sim.now + (sim.request_delay and sim.request_delay(sim.requests) or 0)
        if sim.reject_period and sim.last_arrival ~= nil and arrival + .000001 < sim.last_arrival + sim.reject_period then
            sim.rejected = sim.rejected + 1
            return
        end
        sim.last_arrival = arrival
        sim.attack_times[#sim.attack_times + 1] = sim.now
        sim.attacks = sim.attacks + 1
        sent = sim.now
        sim.walk_clears_at = nil
        observed_at = sent + (predicted and 0 or ping / 1000)
    end
    pc.GetPlatformRelativePosition = function(_, x, z) return nil, x, z end
    pc.EncodeControlMods = function() return 0 end
    pc.DoAction = function(_, action)
        sim.destination = action.pos
        sim.move_at = sim.now
        if sim.walk_ack_delay then sim.walk_clears_at = sim.now + sim.walk_ack_delay end
        if action.non_preview_cb then action.non_preview_cb() end
    end
    local G = {
        CanEntitySeeTarget = function() return true end,
        FRAMES = frame, ThePlayer = player, EQUIPSLOTS = { HANDS = 1 },
        print = function(value) sim.logs[#sim.logs + 1] = value end,
        CONTROL_MOVE_UP = 5, CONTROL_MOVE_DOWN = 6, CONTROL_MOVE_LEFT = 7, CONTROL_MOVE_RIGHT = 8,
        CONTROL_FORCE_ATTACK = 39, CONTROL_ATTACK = 2, MOUSEBUTTON_LEFT = 1, MOUSEBUTTON_RIGHT = 2,
        ACTIONS = { WALKTO = { code = 1 } }, RPC = { LeftClick = 10 },
        GetTime = function() return sim.now end, IsPaused = function() return false end,
        TheNet = { GetAveragePing = function() sim.network_reads = sim.network_reads + 1; return ping end },
        TheFrontEnd = { GetActiveScreen = function() return { name = 'HUD' } end },
        TheInput = {
            IsControlPressed = function(_, name) return (name == 5 and sim.manual) or (name == 39 and sim.force == true) end,
            IsMouseDown = function() return false end,
        },
        Vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
        BufferedAction = function(_, _, _, _, pos) return { pos = pos } end,
        SendRPCToServer = function(...) sim.rpcs[#sim.rpcs + 1] = { ... } end,
    }
    local settings = { buffer_frames = 2, distance = .6 }
    sim.engine = create(G, settings)
    sim.settings = settings
    function sim:advance(seconds)
        local until_time = self.now + seconds
        while self.now + frame < until_time do
            self.now = self.now + frame
            self.engine:Update()
        end
        self.now = until_time
        self.engine:Update()
        assert(self.network_reads == 0, 'controller read ping')
    end
    return sim
end

for _, ping in ipairs({ 0, 30, 80, 140 }) do
    local sim = fixture(false, ping)
    sim.engine:Start()
    assert(sim.attacks == 1, 'key-down should immediately send an attack')
    sim:advance(.25)
    assert(sim.destination == nil, 'premature retreat')
    sim:advance(.35)
    assert(sim.destination ~= nil, 'non-predicting client did not retreat at ping ' .. ping)
    assert(math.abs(sim.destination.x - 4.4) < .001 and sim.destination.z == 0)
    assert(#sim.rpcs == 1 and sim.rpcs[1][6] == true, 'must send one released walk RPC')
    assert(sim.move_at >= ping / 1000 + (8 + 2) * frame, 'retreat before observed swing + guard')
    sim.engine:Stop()
    local attacks = sim.attacks
    sim:advance(.5)
    assert(sim.attacks == attacks, 'continued attacking after key-up')
end

local predicted = fixture(true, 30)
predicted.engine:Start()
predicted:advance(.37)
assert(predicted.destination and #predicted.rpcs == 0)
local manual = fixture(false, 30)
manual.engine:Start()
manual.manual = true
manual:advance(.5)
assert(not manual.destination and manual.attacks == 1)
local cancelled = fixture(false, 30)
cancelled.engine:Start()
cancelled:advance(.1)
cancelled.valid = false
cancelled:advance(.5)
assert(not cancelled.destination and not cancelled.engine.held)
local special = fixture(false, 30, true)
special.engine:Start()
special:advance(.6)
assert(not special.destination, 'must not retreat on unsupported special actions')
local timeout = fixture(false, 140)
timeout.engine:Start()
timeout:advance(.05)
timeout.valid = true
 
timeout.engine.player.HasTag = function() return false end
timeout:advance(.7)
assert(timeout.attacks == 1 and not timeout.destination)
print('controller, prediction off/on, ping 0/30/80/140, manual override and fallback: passed')

local interrupted = fixture(false, 30)
interrupted.engine:Start()
interrupted:advance(.1)
interrupted.cancelled = true
interrupted:advance(.3)
assert(not interrupted.destination, 'retreated after the observed swing was interrupted')
local zero = fixture(false, 30)
zero.settings.buffer_frames = 0
zero.engine:Start()
zero:advance(.4)
assert(zero.destination, 'zero-buffer manual mode failed')
print('interrupted swings and zero-buffer manual mode: passed')

 
local cycle = fixture(false, 30)
cycle.track_range = true
cycle.engine:Start()
cycle:advance(.4)
assert(cycle.destination and cycle.destination.x < cycle.player_x, 'first step should approach')
cycle.player_x = cycle.destination.x
cycle:advance(.15)
assert(cycle.attacks == 2, 'next attack waited for an unnecessary walk phase')
cycle:advance(.4)
assert(cycle.destination.x > cycle.player_x, 'second step should retreat')
assert(cycle.destination.x - cycle.target_x <= 2.2, 'retreat exceeded attack range')
cycle.player_x = cycle.destination.x
cycle:advance(.15)
assert(cycle.attacks == 3, 'third attack did not continue')
cycle.engine:Stop()

local large = fixture(false, 30)
large.track_range = true
large.settings.distance = 2
large.engine:Start()
large:advance(.4)
large.player_x = large.destination.x
large:advance(.15)
large:advance(.4)
assert(large.destination.x - large.target_x <= 2.2, 'large step left attack range')
large.player_x = large.destination.x
large:advance(.15)
assert(large.attacks == 3)
large.engine:Stop()

local stationary = fixture(false, 30)
stationary.engine:Start()
stationary:advance(.55)
assert(stationary.attacks == 2, 'waiting for movement completion reduced attack cadence')
stationary.engine:Stop()
local takeover = fixture(false, 30)
takeover.engine:Start()
takeover:advance(.4)
takeover.manual = true
takeover:advance(.3)
assert(takeover.engine.target == nil and not takeover.engine.owns_movement)
assert(takeover.attacks == 1, 'manual movement did not take priority')
print('alternating approach/retreat, range clamp, uninterrupted cadence and manual takeover: passed')

 
local function weapon(prefab, tags)
    local set = {}
    for _, tag in ipairs(tags or {}) do set[tag] = true end
    return { prefab = prefab, HasTag = function(_, tag) return set[tag] == true end }
end
local cases = {
    { 'spear_wathgrithr_lightning', { 'weapon', 'lancejab' }, 'lancejab', 8, 3.5, 13 },
    { 'whip', { 'weapon', 'whip' }, 'whip', 10, 4.2, 17 },
    { 'pocketwatch_weapon', { 'weapon', 'pocketwatch' }, 'pocketwatch_atk', 10, 4.2, 15 },
    { 'staff_lunarplant', { 'weapon', 'rangedweapon' }, 'atk', 8, 8, 13 },
    { 'firestaff', { 'weapon', 'rangedweapon', 'firestaff' }, 'atk', 8, 8, 13 },
    { 'icestaff', { 'weapon', 'rangedweapon', 'icestaff' }, 'atk', 8, 8, 13 },
    { 'blowdart_pipe', { 'weapon', 'projectile', 'blowdart' }, 'dart', 14, 8, 18 },
    { 'boomerang', { 'weapon', 'projectile', 'thrown' }, 'throw', 7, 8, 11 },
}
for _, case in ipairs(cases) do
    for _, predicted_weapon in ipairs({ false, true }) do
        for _, ping in ipairs({ 0, 80, 140 }) do
            local sim = fixture(predicted_weapon, ping, false, {
                weapon = weapon(case[1], case[2]), animation = case[3], release_frames = case[4],
                range = case[5], player_x = 3 + case[5] - 1, duration_frames = case[6], track_range = true,
            })
            sim.settings.buffer_frames = 2
            local initial = sim.player_x
            sim.engine:Start()
            assert(sim.attacks == 1, case[1] .. ': did not use weapon reach')
            sim:advance((predicted_weapon and 0 or ping / 1000) + (case[4] + 1) * frame)
            assert(not sim.destination, case[1] .. ': moved before release + guard')
            sim:advance(2 * frame)
            assert(sim.destination, case[1] .. ': did not step after release')
            assert(sim.destination.x >= initial - .601, case[1] .. ': rushed into melee range')
            sim.engine:Stop()
        end
    end
end
print('long melee reach, pocketwatch, lunarplant/ice/fire staves, darts and throws, ping 0/80/140: passed')

local sling_weapon = weapon('slingshot', { 'weapon', 'rangedweapon', 'slingshot' })
for _, windup in ipairs({ 7, 11, 16 }) do
    for _, predicted_sling in ipairs({ false, true }) do
        local sim = fixture(predicted_sling, 80, false, {
            weapon = sling_weapon, range = 10, player_x = 11, track_range = true,
            windup_frames = windup, duration_frames = windup + 8, cooldown = 1,
             
            release_frames = 0,
            animation = function(elapsed)
                if elapsed < windup * frame then return 'slingshot_lag' end
                return 'slingshot'
            end,
        })
        sim.settings.buffer_frames = 2
        sim.engine:Start()
        sim:advance((predicted_sling and 0 or .08) + (windup + 3) * frame)
        assert(not sim.destination, 'slingshot moved during wind-up/before firing')
        sim:advance(3.5 * frame)
        assert(sim.destination, 'slingshot did not step after actual shooting clip')
        sim.engine:Stop()
    end
end
local empty = fixture(false, 0, false, { weapon = sling_weapon, duration_frames = 16,
    animation = 'slingshot_lag', range = 10 })
empty.engine:Start()
empty:advance(.55)
assert(not empty.destination, 'empty/cancelled sling must not step during wind-up')
print('slingshot variable wind-up, prediction lacking abouttoattack and cancelled shot: passed')

local swapped = fixture(false, 0)
swapped.engine:Start()
swapped:advance(.1)
swapped.weapon = weapon('staff_lunarplant', { 'rangedweapon', 'weapon' })
swapped:advance(.3)
assert(not swapped.destination, 'weapon swap must invalidate the pending step')
local unknown = fixture(false, 0, false, {
    weapon = weapon('unknown_mod_weapon', { 'rangedweapon', 'weapon' }) })
unknown.engine:Start()
unknown:advance(.4)
assert(unknown.attacks == 1 and not unknown.destination, 'unknown ranged attack must only attack')
local thrown = fixture(false, 0, false, {
    weapon = weapon('boomerang', { 'thrown', 'projectile', 'weapon' }), animation = 'throw', duration_frames = 11 })
thrown.settings.buffer_frames = 0
thrown.engine:Start()
thrown:advance(7 * frame)
thrown.weapon = nil
thrown:advance(frame)
assert(thrown.destination, 'throwing the weapon should not count as a manual swap')
print('weapon swap, unknown ranged fallback and expected throwing unequip: passed')

 
for _, forced in ipairs({ false, true }) do
    local approach = fixture(false, 80, false, {
        player_x = 10, track_range = true, force = forced, search_limit = true })
    approach.engine:Start()
    assert(approach.force_selected == forced, 'R must preserve normal F / Ctrl+F selection')
    assert(approach.attacks == 0 and approach.destination, 'initial out-of-range enemy was not approached')
    assert(approach.destination.x > approach.target_x and approach.destination.x <= approach.target_x + 2.2)
    approach.player_x = approach.destination.x
    approach:advance(frame)
    assert(approach.attacks == 1, 'did not attack after approaching')
    approach.engine:Stop()
end
local released = fixture(false, 30, false, { player_x = 10, track_range = true, search_limit = true })
released.engine:Start()
assert(released.destination and released.attacks == 0)
released.engine:Stop()
assert(released.destination.x == released.player_x, 'key-up did not cancel automatic approach')
released.player_x = 5
released:advance(1)
assert(released.attacks == 0)
local far = fixture(false, 30, false, { player_x = 30, track_range = true, search_limit = true })
far.engine:Start()
far:advance(.5)
assert(not far.destination and far.attacks == 0, 'must respect native target search reach')
local invalid = fixture(false, 30, false, { player_x = 10, track_range = true, search_limit = true })
invalid.engine:Start()
invalid.target_valid = false
invalid:advance(.4)
assert(invalid.engine.target == nil and invalid.attacks == 0, 'did not release dead/invalid target')
assert(invalid.destination.x == invalid.player_x, 'continued walking to a lost target')
print('F-style initial approach, Ctrl force targeting, native reach, key-up and invalid targets: passed')

local handoff = fixture(true, 0, false, { weapon = sling_weapon, range = 10,
    windup_frames = 16, duration_frames = 24, cooldown = 1,
    animation = function(elapsed) return elapsed < 16 * frame and 'slingshot_lag' or 'slingshot' end })
handoff.settings.buffer_frames = 2
 
handoff.engine:Start()
handoff.engine.player.sg.HasStateTag = function() return false end
handoff:advance(23 * frame)
assert(handoff.destination, 'slingshot prediction-to-server handoff lost the shot')
print('slingshot prediction/server animation handoff: passed')

local long_approach = fixture(false, 80, false, {
    weapon = weapon('staff_lunarplant', { 'weapon', 'rangedweapon' }),
    range = 8, player_x = 16, track_range = true, search_limit = true })
long_approach.engine:Start()
assert(long_approach.destination and long_approach.destination.x - long_approach.target_x > 7,
    'long-range initial approach incorrectly used melee distance')
long_approach.engine:Stop()
local long_cycle = fixture(false, 30, false, {
    weapon = weapon('pocketwatch_weapon', { 'weapon', 'pocketwatch' }), animation = 'pocketwatch_atk',
    range = 4.2, player_x = 6.2, release_frames = 10, duration_frames = 15, track_range = true })
long_cycle.settings.distance = 2
long_cycle.engine:Start()
long_cycle:advance(.46)
assert(long_cycle.destination)
long_cycle.player_x = long_cycle.destination.x
long_cycle:advance(.10)
assert(long_cycle.attacks == 2)
long_cycle:advance(.46)
assert(long_cycle.destination.x > long_cycle.player_x)
assert(long_cycle.destination.x - long_cycle.target_x <= 4.2 - .65 + .00001,
    'long-range retreat exceeded the live weapon reach')
long_cycle.engine:Stop()
print('long-range initial approach and alternating retreat range: passed')

 
 
local function pocketwatch_fixture(ping, age, guard, length_override, predicted)
    local function phase(elapsed)
        return age + math.floor(elapsed / frame + .00001)
    end
    local sim = fixture(predicted or false, ping, false, {
        weapon = weapon('pocketwatch_weapon', { 'weapon', 'pocketwatch' }),
        range = 4.2, player_x = 6.2, track_range = true, duration_frames = 15 - age,
        cooldown = math.max(0, (12 - age) * frame),
        release_frames = math.max(0, 10 - age),
        animation = function(elapsed) return phase(elapsed) < 8 and 'pocketwatch_atk_pre' or 'pocketwatch_atk' end,
        animation_frame = function(elapsed)
            local current = phase(elapsed)
            return current < 8 and current or current - 8
        end,
        animation_length = function(elapsed)
            if length_override then return length_override end
            return phase(elapsed) < 8 and 8 or 23
        end,
    })
    sim.settings.buffer_frames = guard
    return sim
end
for _, ping in ipairs({ 0, 30, 80, 140 }) do
    for _, age in ipairs({ 0, 3, 8, 10, 12 }) do
        for guard = 0, 6 do
            local sim = pocketwatch_fixture(ping, age, guard)
            sim.engine:Start()
            local expected_age = 10 + guard
            local move_possible = math.max(age, expected_age) < 15
            local visible_at = math.ceil((ping / 1000) / frame - .000001) * frame
            local earliest = visible_at + math.max(0, expected_age - age) * frame
             
            sim:advance(visible_at + math.min(math.max(0, expected_age - age) + 1, 15 - age) * frame)
            if move_possible then
                assert(sim.destination, 'pocketwatch missed phase-aware step: ping=' .. ping .. ' age=' .. age .. ' guard=' .. guard)
                assert(sim.move_at + .000001 >= earliest, 'pocketwatch moved before release + configured guard')
                assert(sim.move_at <= earliest + frame + .000001, 'pocketwatch restarted the full wind-up wait')
            else
                assert(not sim.destination, 'guard beyond action end: ping=' .. ping .. ' age=' .. age .. ' guard=' .. guard .. ' move=' .. tostring(sim.move_at))
            end
            sim.engine:Stop()
        end
    end
end
local fast = pocketwatch_fixture(0, 8, 2)
fast.walk_ack_delay = frame
fast.engine:Start()
fast:advance(6 * frame)
assert(fast.attacks == 2, 'pocketwatch did not resume at cooldown after early safe step')
local old_fallback = pocketwatch_fixture(0, 8, 2, 99)
old_fallback.engine:Start()
old_fallback:advance(6 * frame)
assert(old_fallback.attacks == 1 and not old_fallback.destination,
    'modified animation should retain conservative fallback')
local prediction_guard = pocketwatch_fixture(0, 8, 2, nil, true)
prediction_guard.engine:Start()
prediction_guard:advance(frame)
assert(not prediction_guard.destination, 'prediction must still honor abouttoattack')
print('pocketwatch received phases, ping 0/30/80/140, guards 0..6, cadence and modified clip fallback: passed')

local function spear_fixture(ping, period, guard, prefab, disable_gate)
    local age = ping == 0 and 0 or math.min(2, math.floor(ping / 33.333))
    local function phase(elapsed)
        return age + math.floor(elapsed / frame + .00001)
    end
    local sim = fixture(false, ping, false, {
        weapon = weapon(prefab or 'spear_wathgrithr', prefab == 'hambat' and { 'weapon' } or { 'weapon', 'battlespear', 'sharp' }),
        unsynced_cooldown = true, min_period = disable_gate and 0 or period, reject_period = period,
        walk_ack_delay = ping / 1000, duration_frames = 13 - age,
        animation = function(elapsed) return phase(elapsed) < 6 and 'atk_pre' or 'atk' end,
        animation_frame = function(elapsed)
            local current = phase(elapsed)
            return current < 6 and current or current - 6
        end,
        animation_length = function(elapsed) return phase(elapsed) < 6 and 6 or 19 end,
    })
    sim.settings.buffer_frames = guard
    return sim
end
local without_gate = spear_fixture(0, .4, 0, nil, true)
without_gate.engine:Start()
without_gate:advance(2)
assert(without_gate.rejected > 0 and without_gate.engine.stats.timeouts > 0,
    'non-predicting native cooldown rejection was not reproduced')
for _, prefab in ipairs({ 'spear_wathgrithr', 'spear_wathgrithr_lightning', 'spear_wathgrithr_lightning_charged', 'hambat' }) do
    for _, ping in ipairs({ 0, 30, 59, 140 }) do
        for _, period in ipairs({ .4, .5 }) do
            for _, guard in ipairs({ 0, 2, 6 }) do
                local sim = spear_fixture(ping, period, guard, prefab)
                sim.engine:Start()
                sim:advance(8)
                assert(sim.attacks >= 10, 'spear stopped chaining at ping ' .. ping)
                assert(sim.rejected == 0, 'spear requested an attack during native cooldown at ping ' .. ping)
                assert(sim.engine.stats.timeouts == 0, 'spear stalled waiting for a rejected attack at ping ' .. ping)
                assert(sim.engine.stats.max_gap < period + ping / 1000 + .25,
                    'unexpected inter-attack stall at ping ' .. ping)
                for i = 2, #sim.attack_times do
                    assert(sim.attack_times[i] - sim.attack_times[i-1] + .000001 >= period,
                        'client guard attempted to bypass the server cooldown')
                end
                sim.engine:Stop()
                assert(#sim.logs == 1 and sim.logs[1]:find('timeouts=0'), 'hold diagnostics missing')
                sim.engine:Stop()
                assert(#sim.logs == 1, 'release diagnostics repeated without a held key')
            end
        end
    end
end
local observed_spear = spear_fixture(59, .4, 2)
observed_spear.engine:Start()
observed_spear:advance(.38)
assert(observed_spear.destination and observed_spear.move_at < .4,
    'spear restarted the full pre-attack delay after receiving its animation')
local tapped = spear_fixture(0, .4, 0)
tapped.engine:Start()
tapped:advance(.3)
tapped.engine:Stop()
local before = tapped.requests
tapped.engine:Start()
assert(tapped.requests == before, 'repressing R bypassed the client cooldown guard')
tapped:advance(.2)
assert(tapped.attacks == 2 and tapped.rejected == 0)
tapped.engine:Stop()
print('Wathgrithr spears and hambat: 59 ms and 0/30/140 ms multi-hit cycles, native cooldown rejection, rapid repress and release diagnostics: passed')

local asymmetric = spear_fixture(59, .4, 0)
asymmetric.request_delay = function(n) return n % 2 == 1 and .04 or .015 end
asymmetric.engine:Start()
asymmetric:advance(8)
assert(asymmetric.rejected == 0 and asymmetric.engine.stats.timeouts == 0 and asymmetric.attacks >= 14,
    '59 ms average with asymmetric packet delay stalled the attack cycle')
asymmetric.engine:Stop()
print('59 ms mean RTT with alternating outbound delay, zero buffer and native server cooldown: passed')

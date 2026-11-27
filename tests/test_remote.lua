package.path = './scripts/?.lua;' .. package.path
local create = require 'autoattack/controller'
local frame = 1 / 30

local function fixture(ping, guard, options)
    options = options or {}
    local sim = { now = 0, packets = {}, sequence = 0, requests = 0, starts = 0, hits = 0, network_reads = 0, walk_records = {}, stop_records = {},
        rejected = 0, cancelled = 0, walks = 0, approaches = 0, stops = 0, records = {},
        player_x = options.far and 7 or 2, target_x = 0, valid = true, logs = {} }
    local server = { kind = 'idle', start = -100, id = 0, x = sim.player_x }
    local client = { kind = 'idle', start = 0, attack = false, sequence = 0 }
    local period, duration = options.period or .4, options.duration or 13
    local release = options.release or 8
    local pre = options.pre or 6
    local main = options.main or 'atk'
    local before = options.before or 'atk_pre'
    local length = options.length or 19
    local range = options.range or 2.7
    local function event(at, callback)
        sim.sequence = sim.sequence + 1
        sim.packets[#sim.packets + 1] = {at = at, callback = callback, sequence = sim.sequence}
    end
    local last_command = -1
    local function command(delay, callback)
        local arrival = math.max(sim.now + delay, last_command + .0000001)
        last_command = arrival
        event(arrival, callback)
    end
    local function flush(until_time)
        while true do
            table.sort(sim.packets, function(a,b) return a.at == b.at and a.sequence < b.sequence or a.at < b.at end)
            if not sim.packets[1] or sim.packets[1].at > until_time + .000001 then return end
            local packet = table.remove(sim.packets,1)
            packet.callback(packet.at)
        end
    end
    local snapshot_sequence = 0
    local function snapshot(at)
        snapshot_sequence = snapshot_sequence + 1
        local sequence, kind, start = snapshot_sequence, server.kind, server.start
        local delay = type(options.downstream) == "function" and options.downstream(sequence, kind) or options.downstream or ping / 2000
        event(at + delay, function(arrival)
            if sequence < client.sequence then return end
            client.sequence, client.kind, client.start = sequence, kind, start + delay
            if kind == 'attack' then
                client.attack = true
            else
                event(arrival + (options.stale_tag or 0), function()
                    if client.sequence <= sequence then client.attack = false end
                end)
            end
        end)
    end
    local function start_attack(at)
        if at + .000001 < server.start + period or server.kind == 'attack' then return false end
        server.kind, server.start, server.has_retarget = 'attack', at, true
        sim.retarget = sim.target
        server.id = server.id + 1
        server.destination, server.approach = nil, nil
        local id = server.id
        sim.starts = sim.starts + 1
        sim.attack_times = sim.attack_times or {}
        sim.attack_times[#sim.attack_times+1] = at
        event(at + release * frame, function()
            if not server['cancelled_' .. id] then sim.hits = sim.hits + 1 end
        end)
        event(at + duration * frame, function(ended)
            if server.kind == 'attack' and server.id == id then server.kind = 'idle'; snapshot(ended) end
        end)
        snapshot(at)
        return true
    end
    local item = { prefab = options.weapon or 'hambat', HasTag = function(_,tag)
        return tag == 'weapon' or (options.watch and tag == 'pocketwatch') or
            (options.unknown and tag == 'rangedweapon') or
            (options.dart and tag == 'blowdart') or (options.thrown and tag == 'thrown') or
            (options.sling and tag == 'slingshot')
    end }
    local target = { IsValid = function() return sim.valid end, HasTag = function() return false end, GetPhysicsRadius = function() return 0 end,
        Transform = { GetWorldPosition = function() return sim.target_x,0,0 end } }
    local pc = { ismastersim = false, remote_controls = {} }
    local player = { IsValid = function() return true end, GetPhysicsRadius = function() return 0 end,
        components = { playercontroller = pc },
        Transform = { GetWorldPosition = function() return sim.player_x,0,0 end },
        HasTag = function(_,tag) return tag == 'attack' and client.attack end,
        replica = { inventory = { GetEquippedItem = function() return item end },
            rider = { IsRiding = function() return false end } } }
    local function age() return math.max(0,math.floor((sim.now - client.start) / frame + .00001)) end
    player.AnimState = {
        IsCurrentAnimation = function(_, name)
            if client.kind ~= 'attack' then return name == 'run_loop' and client.kind == 'walk' end
            return name == (age() < pre and before or main)
        end,
        GetCurrentAnimationFrame = function() return age() < pre and age() or age() - pre end,
        GetCurrentAnimationNumFrames = function() return age() < pre and pre or length end,
    }
    local combat = {
        GetWeapon = function() return item end,
        GetAttackRangeWithWeapon = function() return range end,
        MinAttackPeriod = function() return period end,
        CanTarget = function() return sim.valid end,
        IsAlly = function() return false end,
        InCooldown = function() return false end,
        CanAttack = function() return (not options.report_cooldown or client.kind ~= 'attack') and sim.valid and math.abs(sim.player_x - sim.target_x) <= range - .5 end,
        LocomotorCanAttack = function()
            return math.abs(sim.player_x - sim.target_x) <= range - .5, not sim.valid, false
        end,
    }
    player.replica.combat = combat
    pc.GetCombatRetarget = function() return sim.retarget end
    pc.IsEnabled = function() return not sim.disabled end
    pc.IsBusy = function() return sim.busy == true end
    pc.CanLocomote = function() return false end
    pc.GetAttackTarget = function(_, force, preferred, retarget)
        sim.last_force = force
        if not sim.valid or (sim.neutral and not force) then return nil end
        if pc.remote_controls[2] and pc.remote_controls[2] > 0 then return nil end
        if preferred and retarget then return preferred end
        if client.attack or sim.scan_empty then return nil end
        return math.abs(sim.player_x - sim.target_x) <= range + 6 and target or nil
    end
    pc.RemoteStopControl = function(_, control)
        if pc.remote_controls[control] ~= nil then
            sim.stops = sim.stops + 1
            pc.remote_controls[control] = nil
            command(ping / 2000,function() server.held = false end)
        end
    end
    local function request(attack_target, force, left, released, raw)
        assert(attack_target == target or attack_target == sim.replacement)
        sim.last_target = attack_target
        sim.requests = sim.requests + 1
        sim.records[#sim.records + 1] = {sent = sim.now, released = released, force = force, raw = raw}
        if not raw then pc.remote_controls[2] = not released and .5 or nil end
        if sim.requests <= (options.drop_first or 0) then return end
        local outbound = options.outbound and options.outbound(sim.requests) or ping / 2000
        command(outbound, function(at)
            server.held = not released
            if not sim.valid then return end
            if server.kind == 'attack' or at + .000001 < server.start + period then
                sim.rejected = sim.rejected + 1
            elseif math.abs(server.x - sim.target_x) > range - .5 then
                if not server.approach then sim.approaches = sim.approaches + 1 end
                server.kind, server.approach, server.destination = 'walk',true,nil
                snapshot(at)
            elseif not start_attack(at) then
                sim.rejected = sim.rejected + 1
            end
        end)
    end
    pc.RemoteAttackButton = function(_,target,force,left,released) request(target,force,left,released,false) end
    pc.DoAttackButton = function(_, attack_target)
        local chosen = pc:GetAttackTarget(sim.force == true,attack_target,false)
        if chosen then pc:RemoteAttackButton(chosen,sim.force == true,false,false) end
    end
    pc.GetPlatformRelativePosition = function(_, x,z) return nil,x,z end
    pc.EncodeControlMods = function() return 0 end
    pc.DoAction = function(_, action) if action.non_preview_cb then action.non_preview_cb() end end
    local G = { FRAMES = frame, ThePlayer = player, EQUIPSLOTS = {HANDS = 1},
        CONTROL_MOVE_UP = 5, CONTROL_MOVE_DOWN = 6, CONTROL_MOVE_LEFT = 7, CONTROL_MOVE_RIGHT = 8,
        CONTROL_FORCE_ATTACK = 39, CONTROL_ATTACK = 2, MOUSEBUTTON_LEFT = 1, MOUSEBUTTON_RIGHT = 2,
        ACTIONS = { WALKTO = {code = 1}, ATTACK = {code = 2} }, RPC = {LeftClick = 10, AttackButton = 11, StopControl = 12},
        CanEntitySeeTarget = function() return true end,
        GetTime = function() return sim.now end, IsPaused = function() return sim.paused == true end,
        TheNet = {GetAveragePing = function() sim.network_reads=sim.network_reads+1; return ping end},
        TheFrontEnd = {GetActiveScreen = function() return {name = 'HUD'} end},
        TheInput = {IsControlPressed = function(_, control)
            return (control == 5 and sim.manual) or (control == 39 and sim.force == true) or false
        end, IsMouseDown = function() return false end},
        Vector3 = function(x,y,z) return {x=x,y=y,z=z} end,
        BufferedAction = function(_,_,_,_,point) return {pos=point} end,
        print = function(value) sim.logs[#sim.logs + 1] = value end,
    }
    G.SendRPCToServer = function(rpc,code,x,z,targetarg,released)
        if rpc == 11 then
            assert(z == true)
            request(code,x,false,false,true)
            return
        elseif rpc == 12 then
            assert(code == 2)
            sim.stop_records[#sim.stop_records+1] = sim.now
            command(ping/2000,function() server.held = false end)
            return
        end
        assert(rpc == 10 and code == 1 and targetarg == nil and released == true)
        if client.kind == "attack" and age() < release then sim.early_steps = (sim.early_steps or 0) + 1 end
        sim.walks = sim.walks + 1
        sim.walk_records[#sim.walk_records+1] = sim.now
        command(ping / 2000,function(at)
            if server.held then sim.walk_while_held = true end
            if server.kind == 'attack' and at + .000001 < server.start + release * frame then
                sim.cancelled = sim.cancelled + 1
                server['cancelled_' .. server.id] = true
            end
            server.kind, server.destination, server.approach, server.has_retarget = 'walk',x,nil,false
            sim.retarget = nil
            snapshot(at)
        end)
    end
    local settings = {buffer_frames = guard, distance = .2}
    sim.engine = (options.create or create)(G,settings)
    sim.settings = settings
    sim.pc, sim.target, sim.combat = pc, target, combat
    function sim:advance(seconds)
        local finish = self.now + seconds
        while self.now < finish - .000001 do
            self.now = math.min(finish,self.now + frame)
            flush(self.now)
            if server.kind == 'walk' then
                local destination = server.approach and (sim.target_x + range - .65) or server.destination
                if destination then
                    local delta = destination - server.x
                    server.x = server.x + math.max(-6*frame,math.min(6*frame,delta))
                    if server.approach and math.abs(server.x - sim.target_x) <= range - .5 then
                        start_attack(self.now)
                    elseif not server.approach and math.abs(server.x - destination) < .00001 then
                        server.kind = 'idle';snapshot(self.now)
                    end
                end
            end
            if server.held and server.has_retarget and sim.valid and server.kind ~= 'attack' and
                math.abs(server.x-sim.target_x) <= range-.5 then start_attack(self.now) end
            sim.player_x = server.x
            if not options.skip_update or not options.skip_update(self.now) then self.engine:Update() end
            flush(self.now)
        end
        self.control_held = server.held
        if not options.create or options.create == create then
            assert(self.network_reads == 0, 'remote controller read ping')
        end
    end
    return sim
end

for _, ping in ipairs({0,19,59,140}) do
    for _, guard in ipairs({0,2}) do
        local sim = fixture(ping,guard,{stale_tag = .25})
        sim.engine:Start()
        sim:advance(8)
        assert(sim.starts >= 11, 'remote pipeline stopped at ping ' .. ping .. ': ' .. sim.starts)
        assert(sim.engine.stats.observed >= 10, 'fresh swing not recognized at ping ' .. ping)
        assert(sim.cancelled == 0, 'movement cancelled an unreleased attack at ping ' .. ping)
        assert(sim.engine.stats.timeouts == 0, 'stale attack tag caused an observation timeout at ping ' .. ping)
        assert(sim.walks >= 8, 'steps ping=' .. ping .. ' guard=' .. guard .. ' starts=' .. sim.starts .. ' walks=' .. sim.walks .. ' skipped=' .. sim.engine.stats.skipped_steps .. ' resync=' .. sim.engine.stats.resyncs)
        assert(sim.walks <= sim.starts and sim.engine.stats.observed <= sim.starts,
            'stale animation was counted twice or moved more than once per swing')
        assert(sim.engine.stats.cadence_frames == 12 and sim.engine.stats.resyncs == 0 and
            sim.engine.stats.skipped_steps == 0, 'stable inputs changed the fixed rhythm')
        local expected = ping == 140 and 14 or 12
        for i=2,#sim.walk_records do
            assert(math.abs(sim.walk_records[i]-sim.walk_records[i-1]-expected*frame)<.00001,
                'steady network produced uneven steps')
        end
        assert(not sim.walk_while_held and not sim.early_steps, 'walk interrupted held control or windup')
        assert(sim.requests < 6 * sim.starts, 'attack requests continued throughout each complete swing')
        for _, record in ipairs(sim.records) do
            assert(record.force == false)
            assert((record.raw and record.released == false) or (not record.raw and record.released == true))
        end
        local requests = sim.requests
        sim.engine:Stop();sim:advance(.7)
        assert(sim.logs[#sim.logs]:find('mode=rpc'),'remote mode missing from diagnostics')
        assert(sim.requests == requests and not sim.control_held,'key-up did not release remote attacks')
    end
end
local asymmetric = fixture(59,0,{stale_tag=.25,downstream=.025,
    outbound=function(n) return n%2==0 and .015 or .044 end})
asymmetric.engine:Start();asymmetric:advance(8)
assert(asymmetric.starts>=14 and asymmetric.cancelled==0 and asymmetric.engine.stats.timeouts==0)
assert(asymmetric.engine.stats.resyncs==0 and asymmetric.engine.stats.skipped_steps==0)
for i=2,#asymmetric.walk_records do
    local gap = asymmetric.walk_records[i]-asymmetric.walk_records[i-1]
    assert(gap >= 12*frame-.00001 and gap <= 13*frame+.00001,
        'small packet-delay changes cost an entire movement beat')
end
asymmetric.engine:Stop()
for _, options in ipairs({
    {skip_update=function(t) return math.floor(t/frame+.00001)%13==0 end},
    {stale_tag=.2, outbound=function(n) return n%3==0 and .07 or .02 end},
    {stale_tag=.18, downstream=function(n) return n%4==0 and .095 or .020 end},
    {report_cooldown=true},
}) do
    for _, weapon in ipairs({'hambat','spear_wathgrithr'}) do
        options.weapon = weapon
        local sim = fixture(59,0,options)
        sim.engine:Start()
        sim:advance(8)
        assert(sim.hits>=18 and sim.walks>=17 and sim.cancelled==0 and not sim.early_steps,
            'lost hits or stepped during windup under uneven updates')
        assert(sim.engine.stats.resyncs==0 and not sim.walk_while_held)
        for i=2,#sim.walk_records do
            local gap = sim.walk_records[i]-sim.walk_records[i-1]
            assert(gap >= 12*frame-.00001 and gap <= 15*frame+.00001,
                'missed an entire step or doubled up after a late frame')
        end
        sim.engine:Stop()
    end
end

local locked = fixture(59,0)
locked.engine:Start()
locked:advance(1)
locked.scan_empty = true
locked.retarget = nil
local first_hits = locked.hits
locked:advance(.9)
assert(locked.engine.target == locked.target and locked.hits >= first_hits+2,
    'losing the replicated target after WALKTO interrupted a valid native retarget')
locked.pc.remote_controls[2] = .25
locked:advance(.2)
assert(locked.engine.target == locked.target, 'repeat cooldown cleared the lock')
locked.pc.remote_controls[2] = nil
locked.engine:Stop()
locked.engine:Start()
locked:advance(.4)
assert(locked.engine.target == nil, 'new key press inherited the previous lock')
locked.engine:Stop()

local switch = fixture(59,0)
switch.engine:Start()
switch:advance(.5)
local next_enemy = {IsValid=function() return true end, HasTag=function() return false end,
    GetPhysicsRadius=switch.target.GetPhysicsRadius, Transform=switch.target.Transform}
switch.replacement = next_enemy
switch.target.IsValid = function() return false end
switch.combat.CanTarget = function(_, t) return t:IsValid() end
switch.pc.GetAttackTarget = function(_, _, preferred)
    return (preferred == nil or preferred == next_enemy) and next_enemy or nil
end
switch:advance(.8)
assert(switch.engine.held and switch.last_target==next_enemy and switch.engine.target==next_enemy,
    'had to release R after the first enemy died')
switch.engine:Stop()

local hud = fixture(59,0)
hud.engine:Start()
hud:advance(.6)
hud.engine.player.HUD = {HasInputFocus=function() return true end}
hud:advance(.2)
assert(not hud.engine.held and not hud.control_held, 'chat focus left attack running')
hud.engine:Start()
assert(not hud.engine.held, 'chat accepted attack key-down')
hud.engine.player.HUD = nil
local hud_requests = hud.requests
hud:advance(.5)
assert(hud.requests==hud_requests, 'typing R in a HUD input started attacking')

local release_in_range = fixture(59,0,{report_cooldown=true})
release_in_range.engine:Start()
release_in_range:advance(1)
local remaining_walks = release_in_range.walks
release_in_range.engine:Stop()
release_in_range:advance(.4)
assert(release_in_range.walks==remaining_walks and release_in_range.cancelled==0,
    'key-up sent a stop-walk into an in-range attack')

local interrupted = fixture(59,0)
interrupted.engine:Start()
interrupted:advance(1)
interrupted.disabled=true
interrupted:advance(.3)
local before=interrupted.requests
assert(interrupted.engine.held and not interrupted.control_held)
interrupted:advance(.3)
assert(interrupted.requests==before)
interrupted.disabled=false
interrupted:advance(.8)
assert(interrupted.requests>before and interrupted.hits>1, 'R had to be pressed again')
interrupted.disabled=true
interrupted:advance(.15)
interrupted.engine:Stop()
interrupted.disabled=false
before=interrupted.requests
interrupted:advance(.5)
assert(interrupted.requests==before, 'resumed after key-up while controls were disabled')

local watch = fixture(59,2,{weapon='pocketwatch_weapon',watch=true,release=10,pre=8,
    before='pocketwatch_atk_pre',main='pocketwatch_atk',length=23,duration=15,stale_tag=.25,range=4.2})
watch.engine:Start();watch:advance(8)
assert(watch.starts>=10 and watch.cancelled==0 and watch.walks>=8)
watch.engine:Stop()
local far = fixture(59,0,{far=true})
far.engine:Start();far:advance(.6)
assert(far.approaches==1 and far.walks==0,'initial F-style approach was replaced by repeated WALKTO')
far:advance(1)
assert(far.hits>0,'native attack approach never entered range')
far.engine:Stop()
local invalid = fixture(59,0,{far=true})
invalid.engine:Start();invalid:advance(.1);invalid.valid=false;invalid:advance(.2)
local requests=invalid.requests
invalid:advance(.3)
assert(invalid.requests==requests and invalid.walks==1,'lost target kept attacking or approaching')
invalid.engine:Stop()
local manual = fixture(59,0)
manual.engine:Start();manual:advance(.4);manual.manual=true
local previous=manual.requests
manual:advance(.5)
assert(manual.requests==previous and manual.engine.target==nil and not manual.control_held,'manual movement lost priority')
manual.engine:Stop()
local unknown=fixture(59,0,{unknown=true})
unknown.engine:Start();unknown:advance(2)
assert(unknown.starts>1 and unknown.walks==0,'unknown ranged animation triggered automatic movement')
unknown.engine:Stop()
local neutral=fixture(59,0)
neutral.neutral=true;neutral.engine:Start();neutral:advance(.3)
assert(neutral.requests==0,'normal R forced a neutral target')
neutral.force=true;neutral:advance(.4)
assert(neutral.requests>0 and neutral.last_force,'Ctrl+R did not preserve force selection')
neutral.engine:Stop()
local dropped = fixture(59,0,{drop_first=1,stale_tag=.25})
dropped.engine:Start();dropped:advance(.25)
assert(dropped.starts==1 and dropped.requests>=2 and dropped.engine.stats.timeouts==0,
    'lost initial request caused a full timeout instead of a bounded retry')
dropped.engine:Stop()
local released_approach=fixture(59,0,{far=true})
released_approach.engine:Start();released_approach:advance(.1);released_approach.engine:Stop()
released_approach:advance(1)
assert(released_approach.starts==0 and released_approach.player_x>5,
    'key-up failed to cancel native attack auto-approach')
local busy=fixture(59,0)
busy.busy=true;busy.engine:Start();busy:advance(.4)
assert(busy.requests==0)
busy.busy=false;busy:advance(.4)
assert(busy.starts>0)
busy.paused=true;local before_pause=busy.requests;busy:advance(.4)
assert(busy.requests==before_pause and not busy.engine.held and not busy.control_held,'pause did not stop the RPC pipeline')
for _, options in ipairs({
    {weapon='staff_lunarplant',range=8,stale_tag=.25},
    {weapon='blowdart_pipe',release=14,pre=12,before='dart_pre',main='dart',length=14,duration=18,stale_tag=.25,dart=true},
    {weapon='boomerang',release=7,pre=6,before='throw_pre',main='throw',length=14,duration=11,stale_tag=.25,thrown=true},
    {weapon='slingshot',release=20,pre=16,before='slingshot_pre',main='slingshot',length=15,duration=24,stale_tag=.25,sling=true},
}) do
    local sim=fixture(59,2,options)
    sim.engine:Start();sim:advance(8)
    assert(sim.starts>=6 and sim.cancelled==0 and sim.walks>=5,options.weapon .. ' pipeline did not preserve release timing')
    assert(sim.requests<=math.ceil(8/frame)+1,'request rate exceeded one per frame')
    sim.engine:Stop()
end
for _, period in ipairs({.5,.6}) do
    local sim=fixture(59,0,{period=period,stale_tag=.25})
    sim.engine:Start();sim:advance(8)
    assert(sim.starts>=10 and sim.cancelled==0 and sim.engine.stats.timeouts==0)
    local expected=math.ceil(period/frame-.000001)
    assert(sim.engine.stats.cadence_frames==expected)
    for i=2,#sim.walk_records do
        assert(math.abs(sim.walk_records[i]-sim.walk_records[i-1]-expected*frame)<.00001,
            'server-period cadence drifted')
    end
    for i=2,#sim.attack_times do
        assert(sim.attack_times[i]-sim.attack_times[i-1]+.000001>=period,
            'retries bypassed a changed server attack period')
    end
    sim.engine:Stop()
end
print('fixed melee cadence and RPC pipeline: release-gated movement beats, held-control release, stale states, native approach and manual override: passed')

if arg[1] then
    local directory=arg[1]:match('^(.*)/controller.lua$')
    local old_remote=directory and assert(loadfile(directory .. '/remote.lua'))() or nil
    local environment=setmetatable({require=function(name)
        if name=='autoattack/remote' and old_remote then return old_remote end
        return require(name)
    end},{__index=_G})
    local old=assert(loadfile(arg[1],'t',environment))()
    for _, candidate in ipairs({{'previous',old},{'pipeline',create}}) do
        local sim=fixture(59,0,{stale_tag=.25,create=candidate[2]})
        sim.engine:Start();sim:advance(8);sim.engine:Stop()
        print(candidate[1], 'starts='..sim.starts,'hits='..sim.hits,'walks='..sim.walks,
            'cancelled='..sim.cancelled,'requests='..sim.requests,sim.logs[#sim.logs])
    end
end

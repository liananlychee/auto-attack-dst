local Weapons = require "autoattack/weapons"

return function(G, engine, read_animation)
    local self = { active = false, held_rpc = false }

    local function period_frames(combat)
        local seconds = type(combat.MinAttackPeriod) == "function" and combat:MinAttackPeriod() or 0
        if type(seconds) ~= "number" or seconds ~= seconds or seconds == math.huge then seconds = 0 end
        return math.max(12, math.ceil(seconds / G.FRAMES - .000001))
    end

    function self:Release(force)
        if (self.held_rpc or force) and engine.player ~= nil and engine.player:IsValid() then
            G.SendRPCToServer(G.RPC.StopControl, G.CONTROL_ATTACK)
        end
        self.held_rpc = false
    end

    function self:Reset()
        self:Release(self.used_held == true)
        self.used_held = false
        self.active = false
        self.swing = nil
    end

    function self:Begin(combat, pending, now, age)
        self.active = true
        self.period = period_frames(combat)
        self.next_step = now + self.period * G.FRAMES
        self.profile, self.hand, self.target = pending.profile, pending.hand, pending.target
        self.swing = pending
        self.swing.moved = true
        self.last_age, self.last_seen = age, now
        self.saw_gap = false
        self.last_request = nil
        self.last_step = now
        engine.stats.cadence_frames = self.period
    end

    function self:Send(force, now, combat, observing)
        local retry_frames = now <= self.next_step + .000001 and 1 or 3
        if self.held_rpc and (observing or
            now + .000001 < self.last_request + retry_frames * G.FRAMES) then return end
        G.SendRPCToServer(G.RPC.AttackButton, self.target, force, true)
        local stats = engine.stats
        if self.held_rpc then stats.retries = stats.retries + 1 end
        self.held_rpc, self.used_held = true, true
        self.last_request = now
        stats.requests = stats.requests + 1
        if stats.last_request ~= nil then stats.max_gap = math.max(stats.max_gap, now - stats.last_request) end
        stats.last_request = now
        engine.owns_movement = not combat:LocomotorCanAttack(false, self.target)
    end

    function self:Update(pc, combat, now, force, visible)
        if not self.active then return false end
        local player = engine.player
        local name, _, age = read_animation(player, self.profile)
        if not Weapons.SameHand(player, G, self) or (name ~= nil and age == nil) then
            self:Reset()
            engine.stats.resyncs = engine.stats.resyncs + 1
            return false
        end
        if name == nil then
            self.saw_gap = true
        elseif visible then
            local restarted = age + 1 < self.last_age
                or (self.saw_gap and now - age * G.FRAMES > self.last_seen + .5 * G.FRAMES)
            if restarted then
                if not self.swing.moved then engine.stats.skipped_steps = engine.stats.skipped_steps + 1 end
                self.swing = { target = self.target, profile = self.profile, hand = self.hand }
                engine:ObserveAttack(self.swing, now)
            end
            self.last_age, self.last_seen, self.saw_gap = age, now, false
        end
        local release = self.profile.frames
        local new_swing = visible and age ~= nil and not self.swing.moved
        if new_swing and age >= release and now + .000001 >= self.next_step then
            self:Release(false)
            if engine:StepAfterHit(pc, self.swing) then
                self.swing.moved = true
                self.last_step = now
                self.period = period_frames(combat)
                engine.stats.cadence_frames = self.period
                self.next_step = now + self.period * G.FRAMES
            end
        elseif new_swing and age >= release - 1 and now + G.FRAMES + .000001 >= self.next_step then
            self:Release(false)
        elseif now - self.last_step > math.max(engine.timing:Timeout(), 2 * self.period * G.FRAMES) then
            engine.stats.resyncs = engine.stats.resyncs + 1
            self:Reset()
            return false
        elseif now > self.last_step + .000001 then
            self:Send(force, now, combat, new_swing)
        end
        return true
    end

    return self
end

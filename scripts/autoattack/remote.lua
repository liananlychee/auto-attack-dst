local Weapons = require "autoattack/weapons"
local Cadence = require "autoattack/cadence"

return function(G, engine, settings)
    local self = { pending = nil, recovery = nil, next_request = 0 }
    local starts = { atk_pre = true, punch = true, toolpunch = true, whip_pre = true,
        pocketwatch_atk_pre = true, pocketwatch_atk_pre_2 = true, attack_book = true,
        spearjab_pre = true, lancejab_pre = true, dart_pre = true, throw_pre = true,
        slingshot_pre = true }

    local function animation(player, profile)
        if profile == nil then return nil end
        for _, name in ipairs(profile.animations) do
            if player.AnimState:IsCurrentAnimation(name) then
                local frame = player.AnimState.GetCurrentAnimationFrame ~= nil and
                    player.AnimState:GetCurrentAnimationFrame() or nil
                if type(frame) ~= "number" or frame ~= frame then frame = nil end
                local _, age = Weapons.ReleaseFrames(player, profile)
                return name, frame, age
            end
        end
    end

    self.cadence = Cadence(G, engine, animation)

    function self:Reset()
        self.cadence:Reset()
        self.pending, self.recovery = nil, nil
        self.next_request = 0
    end

    function self:CancelWalk(pc)
        if engine.owns_movement then
            local x, _, z = engine.player.Transform:GetWorldPosition()
            engine:WalkTo(pc, G.Vector3(x, 0, z))
            engine.owns_movement = false
        end
    end

    function self:Target(pc, combat, force, visible)
        local old = engine.target
        local target = engine:SelectTarget(pc, combat, force, visible)
        if target ~= old then
            self.cadence:Reset()
            self.pending, self.recovery = nil, nil
            self.next_request = 0
            engine.step_toward = true
            engine.target = target
            if target == nil then self:CancelWalk(pc) end
        end
        return target
    end

    function self:Send(pc, combat, pending, force, now)
        if now + 0.000001 < self.next_request or pc:IsBusy() then return end
        self.next_request = now + G.FRAMES
        local action = G.ACTIONS.ATTACK
        if action ~= nil and action.pre_action_cb ~= nil then
            action.pre_action_cb(G.BufferedAction(engine.player, pending.target, action))
        end
        pc:RemoteAttackButton(pending.target, force, false, true)
        local stats = engine.stats
        stats.requests = stats.requests + 1
        if pending.last_request ~= nil then stats.retries = stats.retries + 1 end
        if stats.last_request ~= nil then stats.max_gap = math.max(stats.max_gap, now - stats.last_request) end
        stats.last_request, pending.last_request = now, now
        engine.owns_movement = not combat:LocomotorCanAttack(false, pending.target)
    end

    function self:Update(pc, combat, now, force)
        local player = engine.player
        local visible = player:HasTag("attack")
        if pc:IsBusy() then
            if self.cadence.active then
                self.cadence:Reset()
                self.pending, self.recovery = nil, nil
                engine.stats.resyncs = engine.stats.resyncs + 1
            end
            return
        end
        local target = self:Target(pc, combat, force, visible)
        if target == nil then return end
        if self.cadence.active then
            if self.cadence:Update(pc, combat, now, force, visible) then return end
            self.pending, self.recovery = nil, nil
        end
        local pending = self.pending
        if pending ~= nil and not Weapons.SameHand(player, G, pending) then
            self.pending, self.recovery = nil, nil
            return
        end
        if pending == nil then
            if now + 0.000001 < self.next_request then return end
            local profile = Weapons.Profile(player, G)
            local name, frame, age = animation(player, profile)
            local previous = self.recovery or {}
            pending = { sent = now, target = target, profile = profile, hand = Weapons.Hand(player, G),
                guard_frames = engine.timing:GuardFrames(settings), need_new = visible,
                old_name = previous.name or name, old_frame = previous.frame or frame,
                old_age = previous.age or age, saw_clear = not visible }
            self.pending = pending
            self.recovery = nil
            self:Send(pc, combat, pending, force, now)
            return
        end
        if now - pending.sent > engine.timing:Timeout() then
            engine.stats.timeouts = engine.stats.timeouts + 1
            self.pending, self.recovery = nil, nil
            return
        end
        local name, frame, age = animation(player, pending.profile)
        if pending.observed == nil then
            if not visible then pending.saw_clear = true end
            local fresh = not pending.need_new or pending.saw_clear
            if not fresh and name ~= nil then
                fresh = (starts[name] and name ~= pending.old_name) or
                    (age ~= nil and pending.old_age ~= nil and pending.profile.frames ~= nil and
                        age < pending.profile.frames and age + 1 < pending.old_age) or
                    (name == pending.old_name and frame ~= nil and pending.old_frame ~= nil and
                        frame + 1 < pending.old_frame and (starts[name] or
                            name == pending.profile.release_animation))
            end
            if visible and fresh then
                engine:ObserveAttack(pending, now)
            else
                self:Send(pc, combat, pending, force, now)
                engine.status = "连续尝试攻击"
                return
            end
        end
        if not visible or (pending.profile ~= nil and name == nil) then
            self.pending = nil
            engine.status = "衔接下一击"
            return
        end
        local profile = pending.profile
        if profile == nil then engine.status = "特殊动作：仅攻击"; return end
        if profile.release_animation ~= nil then
            if pending.hit_ended == nil then
                if name ~= profile.release_animation or frame == nil or frame < profile.release_frame then return end
                pending.hit_ended = now
            end
        else
            local remaining = Weapons.ReleaseFrames(player, profile)
            pending.hit_ended = remaining ~= nil and now + remaining * G.FRAMES or
                pending.observed + profile.frames * G.FRAMES
        end
        if now + 0.000001 < pending.hit_ended + pending.guard_frames * G.FRAMES then return end
        if engine:StepAfterHit(pc, pending) then
            self.pending = nil
            if profile.fixed_cycle and age ~= nil then self.cadence:Begin(combat, pending, now, age) end
            self.recovery = { name = name, frame = frame, age = age }
            self.next_request = now + G.FRAMES
        end
    end

    return self
end

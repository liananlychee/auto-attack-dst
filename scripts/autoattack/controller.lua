local Timing = require "autoattack/timing"
local Weapons = require "autoattack/weapons"
local Remote = require "autoattack/remote"

return function(G, settings)
    local self = { settings = settings, timing = Timing.new(), held = false,
        pending = nil, status = "等待 R 键" }

    local function in_hud()
        local screen = G.TheFrontEnd:GetActiveScreen()
        return screen ~= nil and screen.name == "HUD" and not G.IsPaused()
    end

    local function manual_movement()
        local input = G.TheInput
        return input:IsControlPressed(G.CONTROL_MOVE_UP) or input:IsControlPressed(G.CONTROL_MOVE_DOWN) or
            input:IsControlPressed(G.CONTROL_MOVE_LEFT) or input:IsControlPressed(G.CONTROL_MOVE_RIGHT) or
            input:IsMouseDown(G.MOUSEBUTTON_LEFT) or input:IsMouseDown(G.MOUSEBUTTON_RIGHT)
    end

    local function attack_visible(player, pc)
        if pc.ismastersim or pc.locomotor ~= nil then
            return player.sg ~= nil and player.sg:HasStateTag("attack")
        end
        return player:HasTag("attack")
    end

    local function can_keep(player, pc, combat, target)
        if target == nil or not target:IsValid() or not combat:CanTarget(target) then return false end
        if target:HasTag("stealth") or combat:IsAlly(target) or
            not G.CanEntitySeeTarget(player, target) then return false end
        local px, _, pz = player.Transform:GetWorldPosition()
        local tx, _, tz = target.Transform:GetWorldPosition()
        local reach = combat:GetAttackRangeWithWeapon() + target:GetPhysicsRadius(0) +
            player:GetPhysicsRadius(0) + .1 + (pc.directwalking and 0 or 6)
        return (px - tx) * (px - tx) + (pz - tz) * (pz - tz) <= reach * reach
    end

    function self:SelectTarget(pc, combat, force, visible)
        local old = self.target
        local locked = can_keep(self.player, pc, combat, old)
        local repeating = not pc.ismastersim and (pc.remote_controls[G.CONTROL_ATTACK] or 0) > 0
        local target
        if locked and repeating then
            return old
        elseif locked then
            target = pc:GetAttackTarget(force, old, true)
        end
        if target == nil and not visible and not repeating then
            local recent = pc:GetCombatRetarget()
            if recent ~= old and can_keep(self.player, pc, combat, recent) then
                target = pc:GetAttackTarget(force, recent)
            end
            target = target or pc:GetAttackTarget(force)
        end
        return target
    end

    self.remote = Remote(G, self, settings)

    function self:Stop()
        if not self.held then return end
        self.remote:Reset()
        self.held = false
        self.suspended = false
        self.force = nil
        self.pending = nil
        self.target = nil
        self.step_toward = true
        self.next_approach = nil
        local player = self.player
        if player ~= nil and player:IsValid() then
            local pc = player.components.playercontroller
            if pc ~= nil and not pc.ismastersim then pc:RemoteStopControl(G.CONTROL_ATTACK) end
            if pc ~= nil and self.owns_movement and not manual_movement() and
                player == G.ThePlayer and not player:HasTag("playerghost") then
                local x, _, z = player.Transform:GetWorldPosition()
                self:WalkTo(pc, G.Vector3(x, 0, z))
            end
        end
        self.owns_movement = false
        self.status = "等待 R 键"
        local stats = self.stats
        if stats ~= nil and stats.requests > 0 and G.print ~= nil then
            G.print(string.format("[Auto Attack] requests=%d observed=%d walks=%d timeouts=%d max_request_gap_ms=%d max_observed_gap_ms=%d retries=%d mode=%s cadence_frames=%d skipped_steps=%d resyncs=%d",
                stats.requests, stats.observed, stats.walks, stats.timeouts,
                math.floor(stats.max_gap * 1000 + .5), math.floor(stats.max_observed_gap * 1000 + .5), stats.retries, self.remote_mode and "rpc" or "state",
                stats.cadence_frames, stats.skipped_steps, stats.resyncs))
        end
    end

    function self:Start()
        if self.held or not in_hud() then return end
        if self.player ~= G.ThePlayer then self.next_attack_at = nil end
        self.player = G.ThePlayer
        if self.player == nil then return end
        self.remote:Reset()
        self.stats = { requests = 0, observed = 0, walks = 0, timeouts = 0, max_gap = 0,
            max_observed_gap = 0, retries = 0, cadence_frames = 0, skipped_steps = 0, resyncs = 0 }
        self.held = true
        self:Update()  
    end

    function self:ObserveAttack(pending, now)
        pending.observed = now
        self.owns_movement = false
        local stats = self.stats
        stats.observed = stats.observed + 1
        if stats.last_observation ~= nil then
            stats.max_observed_gap = math.max(stats.max_observed_gap, now - stats.last_observation)
        end
        stats.last_observation = now
    end

    function self:WalkTo(pc, point)
        if pc:IsBusy() then return false end
        local player = self.player
        local action = G.BufferedAction(player, nil, G.ACTIONS.WALKTO, nil, point)
        if not pc.ismastersim and pc.locomotor == nil then
             
            local platform, px, pz = pc:GetPlatformRelativePosition(point.x, point.z)
            action.non_preview_cb = function()
                G.SendRPCToServer(G.RPC.LeftClick, G.ACTIONS.WALKTO.code, px, pz,
                    nil, true, pc:EncodeControlMods(), G.ACTIONS.WALKTO.canforce,
                    G.ACTIONS.WALKTO.mod_name, platform, platform ~= nil)
            end
        elseif not pc:CanLocomote() then
            return false
        end
        pc:DoAction(action)
        if self.stats ~= nil then self.stats.walks = self.stats.walks + 1 end
        self.owns_movement = true
        return true
    end

    function self:StepAfterHit(pc, pending)
        if manual_movement() then return true end
        local target = pending.target
        if target == nil or not target:IsValid() then return true end
        local x, _, z = self.player.Transform:GetWorldPosition()
        local tx, _, tz = target.Transform:GetWorldPosition()
        local dx, dz = x - tx, z - tz
        local length = math.sqrt(dx * dx + dz * dz)
        if length < 0.001 then return true end
        local combat = self.player.replica.combat
        local amount
        local toward = self.step_toward ~= false
        if toward then
            local separation = self.player:GetPhysicsRadius(0) + target:GetPhysicsRadius(0) + 0.1
            amount = math.min(settings.distance, math.max(0, length - separation))
        else
             
            local safe_range = math.max(0, target:GetPhysicsRadius(0) +
                combat:GetAttackRangeWithWeapon() - 0.65)
            amount = math.min(settings.distance, math.max(0, safe_range - length))
        end
        if amount < 0.05 then
            self.step_toward = not toward
            return true
        end
        local sign = toward and -1 or 1
        local point = G.Vector3(x + dx / length * amount * sign, 0,
            z + dz / length * amount * sign)
        if not self:WalkTo(pc, point) then return false end
        self.step_toward = not toward
        self.status = toward and "出手后小步靠近" or "出手后小步远离"
        return true
    end

    function self:Approach(pc, target, now)
        if now < (self.next_approach or 0) then return end
        local combat = self.player.replica.combat
        local reached, invalid, cooldown = combat:LocomotorCanAttack(false, target)
        if reached or invalid or cooldown then return end
        local px, _, pz = self.player.Transform:GetWorldPosition()
        local tx, _, tz = target.Transform:GetWorldPosition()
        local dx, dz = px - tx, pz - tz
        local length = math.sqrt(dx * dx + dz * dz)
        local range = math.max(0.2, target:GetPhysicsRadius(0) + combat:GetAttackRangeWithWeapon() - 0.65)
         
        if length <= range or length < 0.001 then return end
        if self:WalkTo(pc, G.Vector3(tx + dx / length * range, 0, tz + dz / length * range)) then
            self.next_approach = now + 0.3
            self.status = "靠近敌人，进入攻击距离"
        end
    end

    function self:Update()
        local now = G.GetTime()
        if not self.held then return end
        local player = self.player
        if player == nil or not player:IsValid() or player ~= G.ThePlayer or
            player:HasTag("playerghost") or not in_hud() then self:Stop(); return end
        local pc, combat = player.components.playercontroller, player.replica.combat
        if pc == nil or combat == nil or (player.HUD ~= nil and player.HUD:HasInputFocus()) then
            self:Stop()
            return
        end
        if not pc:IsEnabled() then
            if not self.suspended then
                self.remote:Reset()
                self.pending, self.next_approach = nil, nil
                self.owns_movement, self.step_toward = false, true
                if not pc.ismastersim then pc:RemoteStopControl(G.CONTROL_ATTACK) end
                self.suspended = true
            end
            return
        end
        self.suspended = false
        if manual_movement() then
            self.remote:Reset()
            self.target = nil
            self.step_toward = true
            self.owns_movement = false
            self.pending = nil
            if not pc.ismastersim then pc:RemoteStopControl(G.CONTROL_ATTACK) end
            self.status = "手动移动优先"
            return
        end

        local remote_mode = not pc.ismastersim and pc.locomotor == nil and type(pc.RemoteAttackButton) == "function"
        if self.remote_mode ~= remote_mode then
            self.remote:Reset()
            self.pending = nil
            self.remote_mode = remote_mode
        end
        local force = G.TheInput:IsControlPressed(G.CONTROL_FORCE_ATTACK)
        if self.force ~= nil and force ~= self.force then
            self.remote:Reset()
            self.pending, self.target, self.next_approach = nil, nil, nil
            self.step_toward = true
            self.remote:CancelWalk(pc)
        end
        self.force = force
        if remote_mode then self.remote:Update(pc, combat, now, force); return end

        local pending = self.pending
        if pending ~= nil then
            if now - pending.sent > self.timing:Timeout() then
                self.pending = nil
                self.stats.timeouts = self.stats.timeouts + 1
                if not pc.ismastersim then pc:RemoteStopControl(G.CONTROL_ATTACK) end
                self.status = "动作超时，跳过后撤"
                return
            end
            local visible = attack_visible(player, pc)
            if pending.profile ~= nil and pending.profile.release_animation ~= nil then
                 
                visible = visible or player:HasTag("attack")
            end
            if pending.observed == nil then
                if not visible then return end
                self:ObserveAttack(pending, now)
                if not pc.ismastersim and pc.locomotor == nil and type(combat.MinAttackPeriod) == "function" then
                    local period = combat:MinAttackPeriod()
                    if type(period) == "number" and period == period and period > 0 and period < math.huge then
                        local _, age = Weapons.ReleaseFrames(player, pending.profile)
                        self.next_attack_at = math.max(self.next_attack_at or 0,
                            now + math.max(0, period - (age or 0) * G.FRAMES) + G.FRAMES)
                    end
                end
                if not pc.ismastersim then pc:RemoteStopControl(G.CONTROL_ATTACK) end
            end
            if not visible or not Weapons.KnownAnimation(player, pending.profile) or
                not Weapons.SameHand(player, G, pending) then
                self.pending = nil
                self.status = "动作结束，跳过后撤"
                return
            end
            local profile = pending.profile
            if profile.release_animation ~= nil then
                if pending.hit_ended == nil then
                    if not player.AnimState:IsCurrentAnimation(profile.release_animation) or
                        player.AnimState:GetCurrentAnimationFrame() < profile.release_frame then return end
                    pending.hit_ended = now
                end
            elseif pc.ismastersim or pc.locomotor ~= nil then
                if player.sg:HasStateTag("abouttoattack") then return end
                pending.hit_ended = pending.hit_ended or now
            else
                local release_frames = Weapons.ReleaseFrames(player, profile)
                if release_frames ~= nil then
                     
                     
                    pending.hit_ended = now + release_frames * G.FRAMES
                else
                     
                    pending.hit_ended = pending.observed + profile.frames * G.FRAMES
                end
            end
            if now + 0.000001 < pending.hit_ended + pending.guard_frames * G.FRAMES then return end
            if self:StepAfterHit(pc, pending) then
                self.pending = nil
            end
            return
        end

        if pc:IsBusy() or attack_visible(player, pc) or combat:InCooldown() or
            now + 0.000001 < (self.next_attack_at or 0) then return end
        local target = self:SelectTarget(pc, combat, force, false)
        if target == nil or not target:IsValid() then
            self.target = nil
            if self.owns_movement then
                local x, _, z = player.Transform:GetWorldPosition()
                self:WalkTo(pc, G.Vector3(x, 0, z))
                self.owns_movement = false
            end
            return
        end
        if self.target ~= target then
            self.step_toward = true
            self.next_approach = nil
        end
        self.target = target
        if not combat:CanAttack(target) then
            self:Approach(pc, target, now)
            return
        end
        self.owns_movement = false
        self.pending = { sent = now, target = target, profile = Weapons.Profile(player, G),
            hand = Weapons.Hand(player, G), guard_frames = self.timing:GuardFrames(settings) }
        local stats = self.stats
        stats.requests = stats.requests + 1
        if stats.last_request ~= nil then stats.max_gap = math.max(stats.max_gap, now - stats.last_request) end
        stats.last_request = now
        pc:DoAttackButton(target)
        self.status = "等待观察攻击动作"
    end

    return self
end

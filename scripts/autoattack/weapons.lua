 
 
local Weapons = {}
local melee = { fixed_cycle = true, frames = 8, animations = { "atk_pre", "atk", "punch", "toolpunch",
    "spearjab_pre", "spearjab", "lancejab_pre", "lancejab" },
    release_phases = {
        atk_pre = { length = 6, release = 8, start = 0 },
        atk = { length = 19, release = 2, start = 6 },
        punch = { length = 31, release = 8, start = 0 },
        toolpunch = { length = 24, release = 8, start = 0 },
        spearjab_pre = { length = 7, release = 8, start = 0 },
        spearjab = { length = 23, release = 1, start = 7 },
        lancejab_pre = { length = 7, release = 8, start = 0 },
        lancejab = { length = 22, release = 1, start = 7 },
    } }
local whip = { frames = 10, animations = { "whip_pre", "whip" } }
 
 
local pocketwatch = { frames = 10, animations = {
    "pocketwatch_atk_pre", "pocketwatch_atk_pre_2", "pocketwatch_atk" },
    release_phases = {
        pocketwatch_atk_pre = { length = 8, release = 10, start = 0 },
        pocketwatch_atk_pre_2 = { length = 8, release = 10, start = 0 },
        pocketwatch_atk = { length = 23, release = 2, start = 8 },
    } }
local book = { frames = 10, animations = { "attack_book" } }
 
local staff = { frames = 8, animations = { "atk_pre", "atk" }, release_phases = melee.release_phases }
local dart = { frames = 14, animations = { "dart_pre", "dart" } }
local thrown = { frames = 7, consumed = true, animations = { "throw_pre", "throw" } }
 
local slingshot = { release_animation = "slingshot", release_frame = 4,
    animations = { "slingshot_pre", "slingshot_lag", "slingshot" } }

function Weapons.Hand(player, G)
    local inventory = player.replica.inventory
    return inventory ~= nil and inventory:GetEquippedItem(G.EQUIPSLOTS.HANDS) or nil
end

function Weapons.Profile(player, G)
    local rider = player.replica.rider
    if (rider ~= nil and rider:IsRiding()) or player:HasTag("beaver") or
        player:HasTag("weremoose") or player:HasTag("weregoose") then return nil end
    local combat = player.replica.combat
    local item = combat ~= nil and combat.GetWeapon ~= nil and combat:GetWeapon() or Weapons.Hand(player, G)
    if item == nil then return melee end
     
    if item:HasTag("slingshot") then return slingshot end
    if item:HasTag("blowdart") or item:HasTag("blowpipe") then return dart end
    if item:HasTag("thrown") then return thrown end
    if item:HasTag("propweapon") or item:HasTag("pillow") or
        (item:HasTag("chop_attack") and player:HasTag("woodcutter")) then return nil end
    if item:HasTag("pocketwatch") then return pocketwatch end
    if item:HasTag("whip") then return whip end
    if item:HasTag("book") then return book end
    if item.prefab == "staff_lunarplant" or item:HasTag("firestaff") or item:HasTag("icestaff") then
        return staff
    end
     
    if item:HasTag("rangedweapon") or item:HasTag("projectile") or
        item:HasTag("complexprojectile") then return nil end
    return melee
end

function Weapons.KnownAnimation(player, profile)
    if profile == nil then return false end
    for _, name in ipairs(profile.animations) do
        if player.AnimState:IsCurrentAnimation(name) then return true end
    end
    return false
end

 
 
 
function Weapons.ReleaseFrames(player, profile)
    if profile == nil or profile.release_phases == nil then return nil end
    local anim = player.AnimState
    if anim.GetCurrentAnimationFrame == nil or anim.GetCurrentAnimationNumFrames == nil then return nil end
    for name, phase in pairs(profile.release_phases) do
        if anim:IsCurrentAnimation(name) then
            local frame = anim:GetCurrentAnimationFrame()
            if anim:GetCurrentAnimationNumFrames() == phase.length and
                type(frame) == "number" and frame == frame and frame >= 0 and frame < phase.length then
                return phase.release - frame, phase.start ~= nil and phase.start + frame or nil
            end
            return nil
        end
    end
end

function Weapons.SameHand(player, G, pending)
    local hand = Weapons.Hand(player, G)
     
    return hand == pending.hand or (pending.profile ~= nil and pending.profile.consumed and hand == nil)
end

return Weapons

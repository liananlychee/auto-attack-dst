local G = GLOBAL
local create_controller = G.require "autoattack/controller"
local SettingsScreen = G.require "widgets/autoattacksettings"
local settings = {
    buffer_frames = GetModConfigData("Buffer_frames") or 2,
    distance = GetModConfigData("Retreat_distance") or 0.6,
}
local engine = create_controller(G, settings)
local storage_key = "auto_attack_settings_v1"
local edited = false

local function save()
    edited = true
     
    G.TheSim:SetPersistentString(storage_key, G.json.encode(settings), false)
end

G.TheSim:GetPersistentString(storage_key, function(success, value)
    if not success or edited then return end
    local ok, saved = G.pcall(G.json.decode, value)
    if not ok or type(saved) ~= "table" then return end
    if type(saved.buffer_frames) == "number" and saved.buffer_frames == saved.buffer_frames then
        settings.buffer_frames = math.max(0, math.min(6, math.floor(saved.buffer_frames)))
    end
    if type(saved.distance) == "number" and saved.distance == saved.distance then
        settings.distance = math.max(0.2, math.min(2, math.floor(saved.distance * 10 + .5) / 10))
    end
end)

local handlers_registered = false
local function key_for(name)
    local value = GetModConfigData(name, true)
    return type(value) == "string" and G[value] or value
end

local function install_handlers()
    if handlers_registered then return end
    handlers_registered = true
    local attack_key = key_for("Attack_key")
    if type(attack_key) == "number" then
        G.TheInput:AddKeyDownHandler(attack_key, function() engine:Start() end)
        G.TheInput:AddKeyUpHandler(attack_key, function() engine:Stop() end)
    end
end

AddClassPostConstruct("screens/playerhud", install_handlers)
AddClassPostConstruct("screens/redux/pausescreen", function(screen)
    local function add_settings_entry()
        if screen.menu == nil or screen._auto_attack_menu == screen.menu then return end
        screen._auto_attack_menu = screen.menu
        local entry = screen.menu:AddItem("Auto Attack 手感设置", function()
            engine:Stop()
            screen:Hide()
            G.TheFrontEnd:PushScreen(SettingsScreen(settings, engine, save, function()
                screen:Show()
            end))
        end)
        entry:SetScale(0.7)
        local width, height = screen.bg:GetSize()
        screen.bg:SetSize(width, height + 50)
        local position = screen.menu:GetPosition()
        screen.menu:SetPosition(position.x, position.y + 25, position.z)
    end
    local build_menu = screen.BuildMenu
    screen.BuildMenu = function(self, ...)
        build_menu(self, ...)
        add_settings_entry()
    end
    add_settings_entry()
end)
AddPlayerPostInit(function(player)
    player:DoTaskInTime(0, function()
        if player ~= G.ThePlayer then return end
        player:DoPeriodicTask(G.FRAMES, function() engine:Update() end)
        player:ListenForEvent("onremove", function() engine:Stop() end)
    end)
end)

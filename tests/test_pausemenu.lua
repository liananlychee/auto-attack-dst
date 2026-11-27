local hooks, pushed = {}, nil
local writes, stops = 0, 0
local engine = { Stop = function() stops = stops + 1 end }
GLOBAL = {
    pcall = pcall,
    require = function(name)
        if name == 'autoattack/controller' then return function() return engine end end
        assert(name == 'widgets/autoattacksettings')
        return function(settings, current, save, on_close)
            return { settings = settings, engine = current, save = save, on_close = on_close }
        end
    end,
    json = { encode = function(settings) assert(settings.auto == nil); return 'saved' end },
    TheSim = {
        GetPersistentString = function(_, _, callback) callback(false) end,
        SetPersistentString = function(_, key, value)
            assert(key == 'auto_attack_settings_v1' and value == 'saved')
            writes = writes + 1
        end,
    },
    TheFrontEnd = { PushScreen = function(_, panel) pushed = panel end },
}
GetModConfigData = function(name)
    return ({ Buffer_frames = 2, Retreat_distance = .6 })[name]
end
AddClassPostConstruct = function(name, callback) hooks[name] = callback end
AddPlayerPostInit = function() end
assert(loadfile('modmain.lua'))()
local screen = { hidden = false }
function screen:Hide() self.hidden = true end
function screen:Show() self.hidden = false end
function screen:BuildMenu()
    self.menu = { items = {}, y = 100 }
    function self.menu:AddItem(text, callback)
        local item = { text = text, callback = callback, SetScale = function() end }
        self.items[#self.items + 1] = item
        return item
    end
    function self.menu:GetPosition() return { x = 0, y = self.y, z = 0 } end
    function self.menu:SetPosition(_, y) self.y = y end
    self.bg = { height = 300 }
    function self.bg:GetSize() return 200, self.height end
    function self.bg:SetSize(_, height) self.height = height end
end
screen:BuildMenu()
hooks['screens/redux/pausescreen'](screen)
assert(#screen.menu.items == 1 and screen.bg.height == 350 and screen.menu.y == 125)
screen.menu.items[1].callback()
assert(screen.hidden and pushed and stops == 1)
pushed.save()  
assert(writes == 1, 'settings were not saved immediately during pause')
pushed.on_close()
assert(not screen.hidden, 'pause menu did not reappear')
screen:BuildMenu()
assert(#screen.menu.items == 1 and screen.bg.height == 350, 'entry missing or duplicated after rebuild')
print('pause-menu entry, return callback, rebuild and paused persistence: passed')

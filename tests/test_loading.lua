 
local function load_in(path, env)
    local fn, err
    if _VERSION == 'Lua 5.1' then
        fn, err = loadfile(path)
        if fn then setfenv(fn, env) end
    else
        fn, err = loadfile(path, 't', env)
    end
    assert(fn, err)
    return fn()
end

local metadata = { folder_name = 'workshop-loading-test', locale = 'zh',
    ChooseTranslationTable = function(t) return t.zh or t[1] end }
 
load_in('modinfo.lua', metadata)
assert(metadata.name == '自动走a' and metadata.version == '1.0.15')
for _, language in ipairs({ 'en', 'zh', 'zhr', 'zht' }) do
    local translated = { locale = language, ChooseTranslationTable = function(values)
        return values[language] or values[1]
    end }
    load_in('modinfo.lua', translated)
    local expected = language == 'en' and 'Auto Attack' or
        language == 'zht' and '自動走a' or '自动走a'
    assert(translated.name == expected and translated.version == '1.0.15')
end
assert(#metadata.configuration_options == 3)
assert(metadata.configuration_options[1].default == 'KEY_R')
assert(metadata.configuration_options[1].hover:find('原版攻击键', 1, true), 'mod config key conflict warning missing')
assert(#metadata.configuration_options[2].options == 7)
assert(metadata.configuration_options[2].options[7].data == 6)
assert(#metadata.configuration_options[3].options == 19)
assert(metadata.configuration_options[3].options[19].data == 2)

for _, has_saved in ipairs({ false, true }) do
    local settings
    local hooks = {}
    local G = {
        pcall = pcall,
        json = { decode = function() return { buffer_frames = 3, distance = .8, auto = false } end },
        require = function(name)
            if name == 'autoattack/controller' then
                return function(_, value) settings = value; return {} end
            end
            assert(name == 'widgets/autoattacksettings')
            return function() end
        end,
        TheSim = { GetPersistentString = function(_, _, cb) cb(has_saved, '{}') end },
    }
     
     
    local env = { GLOBAL = G, pairs = pairs, ipairs = ipairs, print = print,
        math = math, table = table, type = type, string = string, tostring = tostring,
        GetModConfigData = function(name)
            assert(name ~= 'Auto_adapt', 'removed network option was still read')
            return ({ Buffer_frames = 2, Retreat_distance = .6, Auto_adapt = true })[name]
        end,
        AddClassPostConstruct = function(name, fn) hooks[name] = fn end,
        AddPlayerPostInit = function() end,
    }
    load_in('modmain.lua', env)
    assert(hooks['screens/playerhud'] and hooks['screens/redux/pausescreen'])
    assert(settings.buffer_frames == (has_saved and 3 or 2))
    assert(settings.auto == nil)
end
print('DST metadata sandbox and modmain environment, fresh and saved settings: passed')

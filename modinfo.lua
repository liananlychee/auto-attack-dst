name = ChooseTranslationTable({ "Auto Attack", zh = "自动走a", zhr = "自动走a", zht = "自動走a" })

description = [[
自动走a Mod
按住 R 自动寻找附近敌人，靠近后攻击；出手后交替小步靠近、远离。
支持长手近战武器、旺达警告表、亮茄法杖及部分远程武器的普通攻击。

推荐关闭延迟补偿

在暂停菜单设置手感
走位等待：普通近战用于起步对齐，其他武器每击生效；可调 0～0.20 秒。
每次走多远：从小步到大步自由调整，默认 0.6；快走出攻击范围时会少走一点。
]]

author = "lian"


version = "1.0.15"


api_version = 6
api_version_dst = 10
priority = 0

dont_starve_compatible = false
reign_of_giants_compatible = false
shipwrecked_compatible = false
dst_compatible = true

all_clients_require_mod = false

client_only_mod = true

server_filter_tags = {}

icon_atlas = "modicon.xml"
icon = "modicon.tex"
local keys = {"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "F1", "F2",
    "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "LAlt", "RAlt", "LCTRL", "RCTRL", "LSHIFT", "RSHIFT", "TAB", "CAPSLOCK", "SPACE", "MINUS",
    "EQUALS", "BACKSPACE", "INSERT", "HOME", "DELETE", "END", "PAGEUP", "PAGEDOWN", "PRINT", "SCROLLOCK", "PAUSE", "PERIOD", "SLASH", "SEMICOLON",
    "LEFTBRACKET", "RIGHTBRACKET", "BACKSLASH", "UP", "DOWN", "LEFT", "RIGHT"}
local keylist = {}
for i = 1, #keys do keylist[i] = {description = keys[i], data = "KEY_" .. keys[i]:upper()} end
keylist[#keylist + 1] = {description = "Disabled", data = false}
local function AddConfig(label, name, options, default, hover) return {label = label, name = name, options = options, default = default, hover = hover or ""} end
local buffers, distances = {}, {}
for n = 0, 6 do
    buffers[#buffers + 1] = {description = n == 0 and "不额外等" or ("多等 %.2f 秒"):format(n / 30), data = n}
end
for n = 2, 20 do
    distances[#distances + 1] = {description = ("%.1f"):format(n / 10), data = n / 10}
end
configuration_options = {
    AddConfig("攻击按键", "Attack_key", keylist, "KEY_R", "按住自动找敌人并靠近攻击；Ctrl + 此键可强制攻击。若模组键与原版攻击键相同，请先在游戏设置→控制中改掉原版攻击键，再使用模组键。"),
    AddConfig("攻击间隔", "Buffer_frames", buffers, 2, "普通近战在开始连打时多等一会儿，其他武器每击生效。游戏内保存的设置优先"),
    AddConfig("回撤距离", "Retreat_distance", distances, 0.6, "进入世界后可在暂停菜单调整，游戏内保存的设置优先"),
}

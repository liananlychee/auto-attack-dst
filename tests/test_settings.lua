package.path = './scripts/?.lua;' .. package.path
unpack = unpack or table.unpack
function Class(base, ctor)
    if type(base) == 'function' then ctor, base = base, nil end
    local class = { _base = base, _ctor = ctor }
    class.__index = class
    return setmetatable(class, { __index = base, __call = function(c, ...)
        local object = setmetatable({}, c)
        ctor(object, ...)
        return object
    end })
end
function Vector3(x, y, z) return {x = x, y = y, z = z} end
NEWFONT, CHATFONT, HEADERFONT, FRAMES = 'testfont', 'chatfont', 'headerfont', 1 / 30
UICOLOURS = {WHITE = {1,1,1,1}, GOLD_SELECTED = {245/255,243/255,222/255,1}}
ANCHOR_MIDDLE, ANCHOR_LEFT, ANCHOR_RIGHT = 0, -1, 1
SCALEMODE_FILLSCREEN, SCALEMODE_NONE = 1, 0
MOUSEBUTTON_LEFT, CONTROL_ACCEPT, CONTROL_CANCEL, CONTROL_PAUSE = 1, 2, 3, 4
RESOLUTION_X, RESOLUTION_Y = 1280, 720
local viewport = {width = 1280, height = 720}
local mouse = {x = 0, y = 0, down = true}
TheSim = {GetScreenSize = function() return viewport.width, viewport.height end}
TheInput = {GetScreenPosition = function() return mouse end,
    IsMouseDown = function() return mouse.down end}
TheFrontEnd = {PopScreen = function() end}
local Widget = Class(function(self, name)
    self.name, self.children, self.x, self.y, self.visible = name, {}, 0, 0, true
end)
function Widget:AddChild(child) child.parent = self; self.children[#self.children + 1] = child; return child end
function Widget:SetPosition(x, y) self.x, self.y = x, y end
function Widget:SetScale(x, y) self.scale_x, self.scale_y = x, y end
function Widget:SetScaleMode() end
function Widget:SetVAnchor() end
function Widget:SetHAnchor() end
function Widget:SetClickable(value) self.clickable = value end
function Widget:StartUpdating() end
function Widget:Hide() self.visible = false end
function Widget:Show() self.visible = true end
function Widget:MoveToBack()
    for i, child in ipairs(self.parent.children) do
        if child == self then table.remove(self.parent.children, i); break end
    end
    table.insert(self.parent.children, 1, self)
end
local Image = Class(Widget, function(self, atlas, texture)
    Widget._ctor(self, 'image'); self.kind = 'image'; self.texture, self.atlas = texture, atlas
    self.width, self.height = 128, 128
end)
function Image:SetSize(w, h) self.width, self.height = w, h end
function Image:SetTint(r, g, b, a) self.colour = {r,g,b,a} end
local Text = Class(Widget, function(self, font, size, text)
    Widget._ctor(self, 'text'); self.kind, self.size, self.text, self.font = 'text', size, text, font
end)
function Text:SetString(value) self.text = value end
function Text:SetColour(value) self.colour = value end
function Text:SetRegionSize(w, h) self.width, self.height = w, h end
function Text:SetHAlign(align) self.align = align end
local TextButton = Class(Widget, function(self)
    Widget._ctor(self, 'button'); self.image = self:AddChild(Image('images/ui.xml','blank.tex'))
    self.text = self:AddChild(Text(NEWFONT, 24, ''))
end)
function TextButton:SetFont() end
function TextButton:SetTextSize(size) self.text.size = size end
function TextButton:SetTextColour(c) self.text.colour = c end
function TextButton:SetTextFocusColour() end
function TextButton:SetText(text) self.text.text = text end
function TextButton:SetOnClick(fn) self.onclick = fn end
function TextButton:ForceImageSize(w,h) self.image:SetSize(w,h) end
function TextButton:SetTextures(atlas, normal) self.image.atlas, self.image.texture = atlas, normal end
local Templates = {}
function Templates.StandardButton(fn, text, size)
    local button = TextButton()
    local prefix = size[1] / size[2] > 4 and 'button_carny_xlong' or
        (size[1] / size[2] < 1.1 and 'button_carny_square' or 'button_carny_long')
    button:SetTextures('images/global_redux.xml',prefix .. '_normal.tex')
    button:ForceImageSize(size[1],size[2])
    button:SetOnClick(fn)
    button:SetText(text)
    button:SetTextColour({0,0,0,1})
    return button
end
function Templates.CurlyWindow(width,height,title)
    local window = Widget('native_window')
    window.kind, window.width, window.height = 'window', width, height
    window.title = window:AddChild(Text(HEADERFONT,28,title))
    window.title:SetColour(UICOLOURS.GOLD_SELECTED)
    window.title:SetPosition(0,height/2+33)
    return window
end
package.loaded['widgets/redux/templates'] = Templates
local Screen = Class(Widget, function(self, name) Widget._ctor(self,name) end)
function Screen:OnControl() return false end
function Screen:OnMouseButton() return false end
function Screen:OnDestroy() self.destroyed = true end
package.loaded['widgets/widget'], package.loaded['widgets/image'] = Widget, Image
package.loaded['widgets/text'], package.loaded['widgets/textbutton'] = Text, TextButton
package.loaded['widgets/screen'] = Screen
package.preload['widgets/imagebutton'] = function() error('sliders must not depend on auto-scaling ImageButton') end
local Panel = require 'widgets/autoattacksettings'
local settings = {buffer_frames = 2, distance = .6}
local saves, closed = 0, 0
local engine = {}
local panel = Panel(settings, engine, function() saves = saves + 1 end, function() closed = closed + 1 end)
local first, second = panel.sliders[1].widget, panel.sliders[2].widget
local first_y, second_y = panel.sliders[1].y, panel.sliders[2].y
local function screen_point(x, y)
    local scale = math.min(viewport.width / RESOLUTION_X, viewport.height / RESOLUTION_Y)
    return viewport.width / 2 + x * scale, viewport.height / 2 + y * scale
end
local x, y = screen_point(-210, first_y)
assert(panel:OnMouseButton(MOUSEBUTTON_LEFT, true, x, y))
assert(settings.buffer_frames == 0 and not first.fill.visible)
assert(first.thumb.width == 26 and first.thumb.height == 26)
mouse.x, mouse.y = screen_point(999, first_y)
panel:OnUpdate()
assert(settings.buffer_frames == 6 and first.value == 6)
assert(saves == 0, 'must not write settings on every drag frame')
mouse.down = false
panel:OnUpdate()
assert(saves == 1 and not panel.dragging)
assert(first.thumb.width == 26 and first.thumb.height == 26, 'handle geometry changed')
 
for _, size in ipairs({{2560,1440}, {1920,1080}, {2560,1080}, {1280,720}}) do
    viewport.width, viewport.height = size[1],size[2]
    local sx, sy = screen_point(0,second_y)
    mouse.down = true
    assert(panel:OnMouseButton(MOUSEBUTTON_LEFT,true,sx,sy))
    assert(settings.distance == 1.1)
    local ex, ey = screen_point(210,second_y)
    assert(panel:OnMouseButton(MOUSEBUTTON_LEFT,false,ex,ey))
    assert(settings.distance == 2)
end
assert(second.thumb.width == 26 and second.thumb.height == 26)
 
local function find_button(text, y)
    for _, child in ipairs(panel.root.children) do
        if child.onclick and child.text.text == text and (y == nil or child.y == y) then return child end
    end
end
find_button('−',second_y).onclick()
assert(settings.distance == 1.9)
find_button('+',second_y).onclick()
find_button('+',second_y).onclick()
assert(settings.distance == 2)
find_button('恢复默认').onclick()
assert(settings.buffer_frames == 2 and settings.distance == .6 and settings.auto == nil)
for _,child in ipairs(panel.root.children) do
    assert(not (child.kind == 'text' and (child.text:find('网络延迟') or child.text:find('毫秒'))))
end
local sx,sy = screen_point(210,first_y)
mouse.down = true
panel:OnMouseButton(MOUSEBUTTON_LEFT,true,sx,sy)
local before = saves
panel:OnDestroy()
assert(saves == before + 1 and closed == 1 and panel.destroyed)
print('settings sliders: dragging, quantization, scaling, limits, fixed geometry and saving: passed')

 
if arg[1] then
    settings.buffer_frames, settings.distance = 2, .6
    viewport.width, viewport.height = 1280,720
    local preview = Panel(settings,engine,function() end,function() end)
    local function quote(s)
        return '"' .. s:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n') .. '"'
    end
    local function encode(value)
        if type(value) == 'string' then return quote(value) end
        if type(value) == 'number' or type(value) == 'boolean' then return tostring(value) end
        local parts = {}
        if #value > 0 then
            for _, item in ipairs(value) do parts[#parts+1] = encode(item) end
            return '[' .. table.concat(parts,',') .. ']'
        end
        for k,v in pairs(value) do parts[#parts+1] = quote(k) .. ':' .. encode(v) end
        return '{' .. table.concat(parts,',') .. '}'
    end
    local function export(node)
        local result = {}
        for _, key in ipairs({'kind','x','y','width','height','visible','texture','atlas','colour','size','text','font','align'}) do
            if type(node[key]) ~= 'table' or key == 'colour' then result[key] = node[key] end
        end
        result.children = {}
        for _,child in ipairs(node.children) do result.children[#result.children+1] = export(child) end
        return result
    end
    local output = assert(io.open(arg[1],'w'))
    output:write(encode(export(preview.root)));output:close()
end

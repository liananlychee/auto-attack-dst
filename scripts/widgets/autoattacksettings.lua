local Screen = require "widgets/screen"
local Widget = require "widgets/widget"
local Image = require "widgets/image"
local Text = require "widgets/text"
local TEMPLATES = require "widgets/redux/templates"
local Slider = require "widgets/autoattackslider"

local WHITE = UICOLOURS.WHITE
local MUTED = {0.65, 0.63, 0.58, 1}
local GOLD = UICOLOURS.GOLD_SELECTED

local SettingsScreen = Class(Screen, function(self, settings, engine, save, on_close)
    Screen._ctor(self, "AutoAttackSettings")
    self.on_close, self.save = on_close, save
    self.sliders = {}
    local shade = self:AddChild(Image("images/global.xml", "square.tex"))
    shade:SetVAnchor(ANCHOR_MIDDLE)
    shade:SetHAnchor(ANCHOR_MIDDLE)
    shade:SetScaleMode(SCALEMODE_FILLSCREEN)
    shade:SetTint(0, 0, 0, 0.7)
    shade:SetClickable(false)
    local root = self:AddChild(Widget("root"))
    root:SetVAnchor(ANCHOR_MIDDLE)
    root:SetHAnchor(ANCHOR_MIDDLE)
    root:SetScaleMode(SCALEMODE_NONE)
    self.root = root

     
    self.window = root:AddChild(TEMPLATES.CurlyWindow(640, 400, "手感设置"))
    self.window:SetClickable(false)

    local function divider(y)
        local line = root:AddChild(Image("images/global_redux.xml", "item_divider.tex"))
        line:SetSize(580, 3)
        line:SetPosition(0, y)
        line:SetTint(0.7, 0.64, 0.51, 0.55)
        line:SetClickable(false)
    end

    local function label(value, x, y, size, colour, width, align)
        local text = root:AddChild(Text(CHATFONT, size, value))
        text:SetPosition(x, y)
        text:SetColour(colour or WHITE)
        if width ~= nil then text:SetRegionSize(width, size + 8) end
        if align ~= nil then text:SetHAlign(align) end
        text:SetClickable(false)
        return text
    end
    local function button(value, x, y, width, fn)
        local b = root:AddChild(TEMPLATES.StandardButton(fn, value, {width, 44}))
        b:SetTextSize(width < 60 and 28 or 22)
        b.scale_on_focus = false
        b.move_on_click = false
        b.clickoffset = Vector3(0, 0, 0)
        b:SetPosition(x, y)
        return b
    end
    label("Auto Attack", 0, 177, 22, GOLD)
    label("按住攻击键连续攻击，出手后小步走位", 0, 145, 20, MUTED)
    divider(117)

    local function slider_row(title, hint, y, minimum, maximum, get, set, format, low, high)
        label(title, -180, y + 64, 24, WHITE, 240, ANCHOR_LEFT)
        local value = label(format(get()), 170, y + 64, 24, GOLD, 260, ANCHOR_RIGHT)
        label(hint, 0, y + 34, 18, MUTED, 600, ANCHOR_LEFT)
        local slider = root:AddChild(Slider(minimum, maximum, get(), function(n)
            set(n)
            value:SetString(format(n))
            self.drag_dirty = true
        end))
        slider:SetPosition(0, y)
        self.sliders[#self.sliders + 1] = { widget = slider, y = y, refresh = function()
            slider:SetValue(get(), false)
            value:SetString(format(get()))
        end }
        local function step(amount)
            if slider:SetValue(slider.value + amount, true) then
                save()
                self.drag_dirty = false
            end
        end
        button("−", -270, y, 44, function() step(-1) end)
        button("+", 270, y, 44, function() step(1) end)
        label(low, -160, y - 29, 17, MUTED, 100, ANCHOR_LEFT)
        label(high, 160, y - 29, 17, MUTED, 100, ANCHOR_RIGHT)
    end
    slider_row("出手后停多久", "普通近战只在起步时等待；其他武器每次出手后等待", 33, 0, 6,
        function() return settings.buffer_frames end,
        function(n) settings.buffer_frames = n end,
        function(n) return n == 0 and "不额外等" or string.format("多等 %.2f 秒", n * FRAMES) end,
        "更早走", "多等一下")
    slider_row("每次走多远", "左边小步挪，右边迈大步；快走出攻击范围时会少走一点", -92, 2, 20,
        function() return math.floor(settings.distance * 10 + .5) end,
        function(n) settings.distance = n / 10 end,
        function(n)
            local size = n <= 6 and "小步" or (n <= 12 and "中步" or "大步")
            return string.format("%s（%.1f）", size, n / 10)
        end,
        "小步", "大步")

    divider(-145)
    self.OnUpdate = function()
        self:UpdateLayout()
        self:UpdateDrag()
    end
    self.default_focus = button("返回暂停菜单", 210, -185, 180, function()
        self:EndDrag()
        TheFrontEnd:PopScreen()
    end)
    button("恢复默认", -220, -185, 140, function()
        settings.buffer_frames, settings.distance = 2, 0.6
        for _, row in ipairs(self.sliders) do row.refresh() end
        save()
        self.drag_dirty = false
    end)
    label("自动保存", -5, -185, 17, MUTED)
    self:StartUpdating()
    self:OnUpdate()
end)

function SettingsScreen:UpdateLayout()
    local width, height = TheSim:GetScreenSize()
    self.ui_scale = math.max(0.001, math.min(width / RESOLUTION_X, height / RESOLUTION_Y))
    self.root:SetScale(self.ui_scale, self.ui_scale, 1)
end

function SettingsScreen:ScreenToLocal(x, y)
    local width, height = TheSim:GetScreenSize()
    self:UpdateLayout()
    return (x - width / 2) / self.ui_scale, (y - height / 2) / self.ui_scale
end

function SettingsScreen:EndDrag()
    if self.dragging ~= nil then self.dragging.widget:SetDragging(false) end
    self.dragging = nil
    if self.drag_dirty then
        self.drag_dirty = false
        self.save()
    end
end

function SettingsScreen:UpdateDrag()
    if self.dragging == nil then return end
    local point = TheInput:GetScreenPosition()
    local x = self:ScreenToLocal(point.x, point.y)
    self.dragging.widget:SetFromX(x)
    if not TheInput:IsMouseDown(MOUSEBUTTON_LEFT) then self:EndDrag() end
end

function SettingsScreen:OnMouseButton(button, down, x, y)
    if button == MOUSEBUTTON_LEFT then
        if not down and self.dragging ~= nil then
            local local_x = self:ScreenToLocal(x, y)
            self.dragging.widget:SetFromX(local_x)
            self:EndDrag()
            return true
        elseif down then
            local local_x, local_y = self:ScreenToLocal(x, y)
            for _, row in ipairs(self.sliders) do
                if row.widget:HitTest(local_x, local_y - row.y) then
                    self.dragging = row
                    row.widget:SetDragging(true)
                    row.widget:SetFromX(local_x)
                    return true
                end
            end
        end
    end
    return self._base.OnMouseButton(self, button, down, x, y)
end

function SettingsScreen:OnDestroy()
    self:EndDrag()
    if self.on_close ~= nil then
        local on_close = self.on_close
        self.on_close = nil
        on_close()
    end
    self._base.OnDestroy(self)
end

function SettingsScreen:OnControl(control, down)
    if self.dragging ~= nil and control == CONTROL_ACCEPT then return true end
    if self._base.OnControl(self, control, down) then return true end
    if not down and (control == CONTROL_CANCEL or control == CONTROL_PAUSE) then
        self:EndDrag()
        TheFrontEnd:PopScreen()
        return true
    end
end

return SettingsScreen

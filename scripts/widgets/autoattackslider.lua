local Widget = require "widgets/widget"
local Image = require "widgets/image"

 
local Slider = Class(Widget, function(self, minimum, maximum, initial, on_change)
    Widget._ctor(self, "AutoAttackSlider")
    self.minimum, self.maximum = minimum, maximum
    self.width = 420
    self.on_change = on_change
    local function image(atlas, texture, width, height, colour)
        local img = self:AddChild(Image(atlas, texture))
        img:SetSize(width, height)
        if colour ~= nil then img:SetTint(unpack(colour)) end
        img:SetClickable(false)
        return img
    end
    self.track = image("images/ui.xml", "line_horizontal_3.tex", self.width, 7, {0.7, 0.68, 0.62, 1})
    self.fill = image("images/ui.xml", "line_horizontal_3.tex", 1, 7, {1, 0.82, 0.45, 1})
    for n = minimum, maximum do
        if (n - minimum) % math.max(1, math.floor((maximum - minimum) / 6)) == 0 then
            local tick = image("images/ui.xml", "line_vertical_1.tex", 2, 5, {0.6, 0.55, 0.43, 1})
            tick:SetPosition(-self.width / 2 + (n - minimum) / (maximum - minimum) * self.width, -13)
        end
    end
    self.thumb = image("images/global_redux.xml", "scrollbar_handle.tex", 26, 26)
    self.value = minimum
    self:SetValue(initial, false)
end)

function Slider:SetValue(value, notify)
    local rounded = math.max(self.minimum, math.min(self.maximum, math.floor(value + 0.5)))
    local changed = self.value ~= rounded
    self.value = rounded
    local fraction = (rounded - self.minimum) / (self.maximum - self.minimum)
    local length = self.width * fraction
    if length == 0 then
        self.fill:Hide()
    else
        self.fill:SetSize(length, 7)
        self.fill:SetPosition(-self.width / 2 + length / 2, 0)
        self.fill:Show()
    end
    self.thumb:SetPosition(-self.width / 2 + length, 0)
    if changed and notify and self.on_change ~= nil then self.on_change(rounded) end
    return changed
end

function Slider:SetFromX(x)
    local fraction = math.max(0, math.min(1, (x + self.width / 2) / self.width))
    return self:SetValue(self.minimum + fraction * (self.maximum - self.minimum), true)
end

function Slider:HitTest(x, y)
    return math.abs(x) <= self.width / 2 + 12 and math.abs(y) <= 22
end

function Slider:SetDragging(dragging)
    self.thumb:SetTint(1, 1, dragging and 0.85 or 1, 1)
end

return Slider

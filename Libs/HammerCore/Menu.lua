local addonName, ns = ...
local HC = ns.HammerCore
local T, UI = HC.Theme, HC.UI

-- A small themed click menu, opened at the cursor or under a frame.  Used
-- for quick actions such as switching profiles from the minimap button.
-- items = { { text, checked?, disabled?, title?, func? } }; a `title` item is
-- a muted heading and `separator = true` draws a dividing line.

local Menu = { items = {}, rules = {} }
HC.Menu = Menu

local ROW = 22

local function build()
    if Menu.frame then return Menu.frame end
    local dismiss = CreateFrame("Button", nil, UIParent)
    dismiss:SetFrameStrata("FULLSCREEN_DIALOG")
    dismiss:SetFrameLevel(199)
    dismiss:SetAllPoints(UIParent)
    dismiss:EnableMouse(true)
    if dismiss.RegisterForClicks then dismiss:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    local f = CreateFrame("Frame", HC.FrameName("Menu"), UIParent, "BackdropTemplate")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(200)
    f:SetClampedToScreen(true)
    T.Surface(f, "menu", "menuEdge")
    f:SetScript("OnHide", function() dismiss:Hide() end)
    dismiss:SetScript("OnClick", function() f:Hide() end)
    dismiss:Hide()
    f:Hide()
    Menu.frame, Menu.dismiss = f, dismiss
    return f
end

local function row(index)
    local f = Menu.frame
    local item = Menu.items[index]
    if item then return item end
    item = CreateFrame("Button", nil, f, "BackdropTemplate")
    T.Surface(item, "transparent")
    item.check = T.Fill(item:CreateTexture(nil, "ARTWORK"), "selected")
    item.check:SetSize(6, 6)
    item.check:SetPoint("LEFT", 8, 0)
    item.label = UI.FontString(item, "GameFontHighlightSmall")
    item.label:SetPoint("LEFT", 20, 0)
    item.label:SetPoint("RIGHT", -8, 0)
    item.label:SetJustifyH("LEFT")
    if item.label.SetWordWrap then item.label:SetWordWrap(false) end
    item:HookScript("OnEnter", function(self)
        if self.spec and not self.spec.title and not self.spec.disabled then
            self:SetBackdropColor(T.Unpack("menuActive"))
        end
    end)
    item:HookScript("OnLeave", function(self) self:SetBackdropColor(T.Unpack("transparent")) end)
    item:SetScript("OnClick", function(self)
        local spec = self.spec
        if not spec or spec.title or spec.disabled then return end
        f:Hide()
        if spec.func then spec.func() end
    end)
    Menu.items[index] = item
    return item
end

-- anchor: a frame to open beneath, or nil for the cursor.
function Menu:Open(items, anchor, width)
    local f = build()
    width = width or 180
    local y, shown, ruled = -5, 0, 0
    for _, spec in ipairs(items) do
        if spec.separator then
            ruled = ruled + 1
            local rule = self.rules[ruled]
            if not rule then
                rule = T.Fill(f:CreateTexture(nil, "ARTWORK"), "menuEdge")
                rule:SetHeight(1)
                self.rules[ruled] = rule
            end
            rule:ClearAllPoints()
            rule:SetPoint("TOPLEFT", 10, y - 6)
            rule:SetPoint("TOPRIGHT", -10, y - 6)
            rule:Show()
            y = y - 13
        else
            shown = shown + 1
            local item = row(shown)
            item.spec = spec
            item:ClearAllPoints()
            item:SetPoint("TOPLEFT", 5, y)
            item:SetSize(width - 10, ROW)
            item.label:SetText(spec.text or "")
            T.Text(item.label, (spec.title or spec.disabled) and "muted" or "text")
            item.check:SetShown(spec.checked and true or false)
            item:SetBackdropColor(T.Unpack("transparent"))
            item:Show()
            y = y - ROW
        end
    end
    for index = shown + 1, #self.items do self.items[index]:Hide() end
    for index = ruled + 1, #self.rules do self.rules[index]:Hide() end
    f:SetSize(width, -y + 5)
    f:ClearAllPoints()
    if anchor then
        f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    else
        local x, cy = GetCursorPosition()
        local scale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
        if not scale or scale == 0 then scale = 1 end
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (x or 0) / scale, (cy or 0) / scale)
    end
    self.dismiss:Show()
    f:Show()
    return f
end

function Menu:Close()
    if self.frame then self.frame:Hide() end
end

function Menu:IsShown()
    return self.frame and self.frame:IsShown() or false
end

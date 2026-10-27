local addonName, ns = ...
local HC = ns.HammerCore

-- A hand-rolled minimap button: no LibDBIcon or LibDataBroker, so its
-- position never depends on which other addons are loaded.  Left-click
-- opens settings by default; either click can run an addon action.

local MinimapButton = {}
HC.Minimap = MinimapButton

-- ☠ math.atan is unary in WoW's Lua 5.1; the two-argument form is 5.3+.
local atan2 = math.atan2 or math.atan

function MinimapButton:Create()
    if self.button or not Minimap then return self.button end
    local spec = HC.spec.minimap or {}
    local b = CreateFrame("Button", HC.FrameName("MinimapButton"), Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local highlight = b:GetHighlightTexture()
    if highlight then highlight:SetBlendMode("ADD") end

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetAllPoints()
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 5, -5)
    icon:SetPoint("BOTTOMRIGHT", -5, 5)
    icon:SetTexture(spec.icon or HC.spec.icon)
    b.icon = icon
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")

    -- Keep the icon just outside the minimap edge at any size or UI scale.
    local function radius()
        local diameter = math.min(Minimap:GetWidth() or 0, Minimap:GetHeight() or 0)
        if diameter <= 0 then return 80 end
        return diameter / 2 + b:GetWidth() / 2 - 10
    end
    local function place(angle)
        local r = math.rad(angle or 225)
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", math.cos(r) * radius(), math.sin(r) * radius())
    end
    local function follow()
        local scale = Minimap:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        local mx, my = Minimap:GetCenter()
        if not mx or not my then return end
        local angle = math.deg(atan2(cy / scale - my, cx / scale - mx))
        HC.State().minimapAngle = angle
        place(angle)
    end

    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    -- A drag release may have no OnClick. Clear its suppression on the next
    -- actual press so that the next ordinary click is never swallowed.
    b:SetScript("OnMouseDown", function(self) self.hcDragged = nil end)
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", follow) end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self.hcDragged = true
    end)
    b:SetScript("OnClick", function(self, button)
        if self.hcDragged then self.hcDragged = nil; return end
        if button == "RightButton" then
            if spec.rightClick then spec.rightClick() end
        else
            if spec.leftClick then spec.leftClick() else HC.Settings:Toggle() end
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(HC.name)
        GameTooltip:AddLine("Click: " .. (spec.leftClick and tostring(spec.leftClickLabel) or "settings"), 0.85, 0.85, 0.85)
        if spec.rightClick then
            GameTooltip:AddLine("Right-click: " .. tostring(spec.rightClickLabel), 0.85, 0.85, 0.85)
        end
        GameTooltip:AddLine("Drag: move", 0.85, 0.85, 0.85)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.button, self.place = b, place
    if Minimap.HookScript then
        Minimap:HookScript("OnSizeChanged", function() place(HC.State().minimapAngle) end)
    end
    self:Update()
    return b
end

function MinimapButton:Update()
    if not self.button then return end
    local state = HC.State()
    -- Minimap-button collectors replace Show/Hide on icons they collect; use
    -- those rather than SetShown so a collapsed icon stays collapsed.
    local combat = HC.spec.hideInCombat and InCombatLockdown and InCombatLockdown()
    if state.minimap and not combat then self.button:Show() else self.button:Hide() end
    self.place(state.minimapAngle)
end

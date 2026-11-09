local addonName, ns = ...
local HC = ns.HammerCore
local T, UI = HC.Theme, HC.UI

-- Small themed dialogs: a yes/no question and a one-line text prompt.
-- They are ordinary frames, not StaticPopups, so they look like the rest of
-- the suite, never taint Blizzard's popup queue, and work in combat (they
-- touch nothing protected).  One frame is shared; a new question replaces an
-- open one without running the old one's callbacks.

local Dialog = {}
HC.Dialog = Dialog

local function build()
    if Dialog.frame then return Dialog.frame end
    local f = CreateFrame("Frame", HC.FrameName("Dialog"), UIParent, "BackdropTemplate")
    f:SetSize(340, 128)
    f:SetPoint("TOP", UIParent, "TOP", 0, -180)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(300)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    T.Surface(f, "outer", "accent")

    f.title = UI.FontString(f, "GameFontNormal", "accent")
    f.title:SetPoint("TOPLEFT", 16, -14)
    f.title:SetPoint("TOPRIGHT", -16, -14)
    f.title:SetJustifyH("LEFT")

    f.text = UI.FontString(f, "GameFontHighlight")
    f.text:SetPoint("TOPLEFT", 16, -38)
    f.text:SetPoint("TOPRIGHT", -16, -38)
    f.text:SetJustifyH("LEFT")

    -- Link dialogs lead with the addon's logo, badged with where the link
    -- goes (CurseForge, Discord, ...), so it's clear what's being copied.
    f.logo = f:CreateTexture(nil, "ARTWORK")
    f.logo:SetSize(36, 36)
    f.logo:SetPoint("TOPLEFT", 14, -12)
    f.logo:Hide()
    f.badgeBack = f:CreateTexture(nil, "OVERLAY")
    f.badgeBack:SetSize(20, 20)
    f.badgeBack:SetPoint("CENTER", f.logo, "BOTTOMRIGHT", -2, 2)
    T.Icon(f.badgeBack, "Circle.tga", "rail")
    f.badgeBack:Hide()
    f.badge = f:CreateTexture(nil, "OVERLAY", nil, 1)
    f.badge:SetSize(14, 14)
    f.badge:SetPoint("CENTER", f.badgeBack, "CENTER")
    f.badge:Hide()

    local box = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    box:SetHeight(26)
    box:SetPoint("TOPLEFT", 16, -60)
    box:SetPoint("TOPRIGHT", -16, -60)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetTextInsets(8, 8, 0, 0)
    T.Surface(box, "rail", "edge")
    f.box = box

    f.error = UI.FontString(f, "GameFontHighlightSmall", "danger")
    f.error:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -4)

    f.accept = UI.Button(f, 100, 22, "primary")
    f.accept:SetPoint("BOTTOMRIGHT", -124, 12)
    f.cancel = UI.Button(f, 100, 22)
    f.cancel:SetPoint("BOTTOMRIGHT", -16, 12)

    local function finish(accepted)
        local current = Dialog.current
        if not current then f:Hide(); return end
        if accepted and current.prompt then
            local problem = current.onAccept and current.onAccept(box:GetText() or "")
            if type(problem) == "string" then
                f.error:SetText(problem)
                return
            end
        elseif accepted then
            if current.onAccept then current.onAccept() end
        elseif current.onCancel then
            current.onCancel()
        end
        Dialog.current = nil
        if box.ClearFocus then box:ClearFocus() end
        f:Hide()
    end
    f.accept:SetScript("OnClick", function() finish(true) end)
    f.cancel:SetScript("OnClick", function() finish(false) end)
    box:SetScript("OnEnterPressed", function() finish(true) end)
    box:SetScript("OnEscapePressed", function() finish(false) end)
    -- A link box is read-only: any edit puts the link back, selected.
    box:SetScript("OnTextChanged", function(self, typed)
        local current = Dialog.current
        if typed and current and current.link and self:GetText() ~= current.url then
            self:SetText(current.url)
            if self.HighlightText then self:HighlightText() end
        end
    end)
    f.finish = finish
    -- Escape closes it like any panel; closing that way counts as cancel.
    f:SetScript("OnHide", function()
        local current = Dialog.current
        if not current then return end
        Dialog.current = nil
        if current.onCancel then current.onCancel() end
    end)
    if UISpecialFrames and f:GetName() then UISpecialFrames[#UISpecialFrames + 1] = f:GetName() end
    f:Hide()
    Dialog.frame = f
    return f
end

local function open(spec, prompt)
    local f = build()
    spec.prompt = prompt
    Dialog.current = spec
    f.title:SetText(spec.title or HC.name)
    f.text:SetText(spec.text or "")
    f.error:SetText("")
    f.accept:SetText(spec.accept or (prompt and "OK" or "Yes"))
    f.cancel:SetText(spec.cancel or (prompt and "Cancel" or "No"))
    f.accept:SetShown(not spec.link)
    f.box:SetShown(prompt)
    f:SetHeight(prompt and 140 or 104)
    -- A link is shown whole: wide enough for the full URL, logo and badge.
    local link = spec.link == true
    local logo = link and HC.spec and HC.spec.icon or nil
    f:SetWidth(link and 420 or 340)
    f.logo:SetShown(logo ~= nil)
    if logo then f.logo:SetTexture(logo) end
    local badge = logo and spec.icon or nil
    f.badgeBack:SetShown(badge ~= nil)
    f.badge:SetShown(badge ~= nil)
    if badge then T.Icon(f.badge, badge, "accent") end
    local indent = logo and 60 or 16
    f.title:SetPoint("TOPLEFT", indent, -14)
    f.text:SetPoint("TOPLEFT", indent, -34)
    f.text:SetPoint("TOPRIGHT", -16, -34)
    if prompt then
        if f.box.SetMaxLetters then f.box:SetMaxLetters(link and 0 or spec.maxLetters or 32) end
        f.box:SetText(spec.default or "")
        f.box:Show()
        if f.box.SetFocus then f.box:SetFocus() end
        -- Scroll back to the start so the front of a long link shows.
        if f.box.SetCursorPosition then f.box:SetCursorPosition(0) end
        if f.box.HighlightText then f.box:HighlightText() end
    end
    f:Show()
    if f.Raise then f:Raise() end
    return f
end

-- spec = { title?, text, accept?, cancel?, onAccept?, onCancel? }
function Dialog:Confirm(spec)
    return open(spec, false)
end

-- spec = { title?, text?, default?, maxLetters?, accept?, cancel?, onAccept(text) -> error?, onCancel? }
-- Returning a string from onAccept keeps the dialog open and shows it.
function Dialog:Prompt(spec)
    return open(spec, true)
end

-- WoW can't open a browser, so a link opens selected in a box to copy.
-- spec = { title?, url, icon? }  icon is a HammerCore texture name, such as
-- "CurseForge.tga", shown as a badge on the addon's logo.
function Dialog:Link(spec)
    return open({ title = spec.title or "Link", url = spec.url, link = true, default = spec.url,
        icon = spec.icon, text = "Press Ctrl+C to copy, then paste it into your browser.",
        cancel = "Close" }, true)
end

function Dialog:IsShown()
    return self.frame and self.frame:IsShown() and self.current ~= nil or false
end

-- Closes an open dialog without running either callback.
function Dialog:Dismiss()
    self.current = nil
    if self.frame then self.frame:Hide() end
end

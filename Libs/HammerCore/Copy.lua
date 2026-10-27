local addonName, ns = ...
local HC = ns.HammerCore
local T, UI = HC.Theme, HC.UI

-- A selectable text window for reports the player pastes into a bug report.

local Copy = {}
HC.Copy = Copy

function Copy:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", HC.FrameName("CopyReport"), UIParent, "BackdropTemplate")
    frame:SetSize(640, 380)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    T.Surface(frame, "outer", "edge")
    frame:Hide()

    frame.title = UI.FontString(frame, "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 18, -16)
    local help = UI.FontString(frame, "GameFontHighlightSmall", "muted")
    help:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -5)
    frame.help = help

    local well = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    well:SetPoint("TOPLEFT", 16, -64)
    well:SetPoint("BOTTOMRIGHT", -16, 44)
    T.Surface(well, "rail", "edge")
    local scroll = CreateFrame("ScrollFrame", nil, well, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(570)
    edit:SetHeight(800)
    edit:SetTextInsets(4, 4, 4, 4)
    edit:SetScript("OnEscapePressed", function() frame:Hide() end)
    scroll:SetScrollChild(edit)
    frame.edit = edit

    local close = UI.Button(frame, 90, 22)
    close:SetPoint("BOTTOMRIGHT", -16, 14)
    close:SetText("Close")
    close:SetScript("OnClick", function() frame:Hide() end)
    frame:SetScript("OnHide", function() edit:ClearFocus() end)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = frame:GetName() end
    self.frame = frame
    return frame
end

function Copy:Show(title, text, helpText)
    local frame = self:Create()
    frame.title:SetText(title)
    frame.help:SetText(helpText or "Press Ctrl+C, then Escape.")
    frame.edit:SetText(text or "")
    frame:Show()
    frame.edit:SetFocus()
    frame.edit:HighlightText()
end

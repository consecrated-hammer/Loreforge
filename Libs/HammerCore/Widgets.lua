local addonName, ns = ...
local HC = ns.HammerCore
local T = HC.Theme

-- Settings controls.  Each builder takes the page panel and a y offset and
-- returns the control plus the y for the next row, so pages read as a
-- straight run of assignments rather than hand-counted offsets.  Every
-- control registers a refresh on panel.hcRefresh so values changed by a slash
-- command, the minimap button or another page are pulled back in on show.

local UI = {}
HC.UI = UI

UI.PAD = 16
UI.CONTENT_WIDTH = 540

local function refreshAll(panel)
    if panel.hcRefreshAll then panel.hcRefreshAll() end
end

local function onRefresh(panel, fn)
    panel.hcRefresh = panel.hcRefresh or {}
    panel.hcRefresh[#panel.hcRefresh + 1] = fn
end
UI.OnRefresh = onRefresh

local function resolve(value)
    if type(value) == "function" then return value() end
    return value
end

-- Hints live in a tooltip rather than a second grey line under every control.
function UI.AttachHint(control, title, hint)
    if not hint then return end
    control.hcHintTitle, control.hcHint = title, hint
    control:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        local titleText = resolve(self.hcHintTitle)
        GameTooltip:SetText(type(titleText) == "string" and titleText or HC.name, T.Unpack("accent"))
        GameTooltip:AddLine(resolve(self.hcHint), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    control:HookScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
end

function UI.AttachTitleHint(parent, fontString, title, hint)
    if not hint then return end
    local region = CreateFrame("Frame", nil, parent)
    region:SetPoint("TOPLEFT", fontString, "TOPLEFT", -2, 2)
    region:SetPoint("BOTTOMRIGHT", fontString, "BOTTOMRIGHT", 2, -2)
    region:EnableMouse(true)
    UI.AttachHint(region, title, hint)
    return region
end

function UI.FontString(parent, template, role)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    T.Text(fs, role or "text")
    return fs
end

-- ── Primitive controls ─────────────────────────────────────────────────────

function UI.CheckButton(parent)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    if T.IsClassic() then
        -- Blizzard's own checkbox art, the gold tick included.
        btn:SetSize(22, 22)
        btn:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        btn:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
        btn.check = btn:CreateTexture(nil, "ARTWORK")
        btn.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        btn.check:SetAllPoints()
    else
        btn:SetSize(18, 18)
        T.Surface(btn, "rail", "edge")
        btn.check = T.Fill(btn:CreateTexture(nil, "ARTWORK"), "selected")
        btn.check:SetPoint("TOPLEFT", 2, -2)
        btn.check:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    btn.Text = UI.FontString(btn)
    btn.Text:SetPoint("LEFT", btn, "RIGHT", 8, 0)
    btn.Text:SetJustifyH("LEFT")
    btn.SetChecked = function(self, checked)
        self.checked = checked and true or false
        self.check:SetShown(self.checked)
        if not T.IsClassic() then T.Border(self, self.checked and "selected" or "edge") end
    end
    btn.GetChecked = function(self) return self.checked end
    btn:SetChecked(false)
    return btn
end

-- Buttons keep a quiet surface so actions are visibly clickable without
-- turning every setting into a card.  variant: nil, "primary" or "danger".
function UI.Button(parent, width, height, variant)
    local button
    if T.IsClassic() then
        -- The red panel button every 2004 options window used.
        button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetSize(width or 160, height or 22)
        local label = rawget(button, "Text")
        if type(label) ~= "table" then label = button.GetFontString and button:GetFontString() end
        if type(label) ~= "table" then
            label = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            label:SetAllPoints()
        end
        button.Text = label
        if variant == "danger" then T.Text(button.Text, "danger") end
    else
        button = CreateFrame("Button", nil, parent, "BackdropTemplate")
        button:SetSize(width or 160, height or 22)
        T.Surface(button, "raised", variant == "danger" and "danger"
            or variant == "primary" and "accent" or "edge")
        button.Text = UI.FontString(button, "GameFontHighlight", variant == "danger" and "danger" or "text")
        button.Text:SetAllPoints()
        button.Text:SetJustifyH("CENTER")
    end
    button.SetText = function(self, text)
        self.Text:SetText(text or "")
        self.text = text
    end
    button.GetText = function(self) return self.text end
    return button
end

local function chevron(button)
    for _, spec in ipairs({ { -13, 2, -0.75 }, { -8, 2, 0.75 } }) do
        local arrow = T.Fill(button:CreateTexture(nil, "OVERLAY"), "muted")
        arrow:SetSize(7, 1)
        arrow:SetPoint("RIGHT", spec[1], spec[2])
        if arrow.SetRotation then arrow:SetRotation(spec[3]) end
    end
end

-- A select is a value field, so a subtle border makes its value readable.
function UI.SelectButton(parent, width, height)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 160, height or 30)
    T.Surface(button, "rail", "edge")
    button.Text = UI.FontString(button)
    button.Text:SetPoint("LEFT", 10, 0)
    button.Text:SetPoint("RIGHT", -26, 0)
    button.Text:SetJustifyH("LEFT")
    -- A select shows one line; size the button to its longest choice.
    if button.Text.SetWordWrap then button.Text:SetWordWrap(false) end
    button.SetText = function(self, text)
        self.Text:SetText(text or "")
        self.text = text
    end
    chevron(button)
    return button
end

-- One popup list shared by every dropdown.  The full-screen click catcher
-- closes it when the player clicks anywhere else, without polling the mouse.
-- choices() returns values, labels; it is re-read on every open so session
-- state (chat windows, known spells) stays current.
local function popupMenu(button, choices, get, pick)
    local menu, dismiss, items = nil, nil, {}
    local function paint(item, active, hovered)
        item:SetBackdropColor(T.Unpack((active or hovered) and "menuActive" or "rail"))
        item.activeBar:SetShown(active)
        T.Text(item.label, active and "text" or "muted")
    end
    local function ensure()
        if menu then return end
        dismiss = CreateFrame("Button", nil, UIParent)
        dismiss:SetFrameStrata("FULLSCREEN_DIALOG")
        dismiss:SetFrameLevel(199)
        dismiss:SetAllPoints(UIParent)
        dismiss:EnableMouse(true)
        menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(200)
        menu:SetClampedToScreen(true)
        T.Surface(menu, "menu", "menuEdge")
        menu:SetScript("OnHide", function() dismiss:Hide() end)
        dismiss:SetScript("OnClick", function() menu:Hide() end)
        menu:Hide()
    end
    local function fill()
        local values, labels = choices()
        local width = button:GetWidth() or 160
        menu:SetSize(width, math.max(1, #values) * 26 + 10)
        for index, value in ipairs(values) do
            local item = items[index]
            if not item then
                item = CreateFrame("Button", nil, menu, "BackdropTemplate")
                item:SetPoint("TOPLEFT", 5, -5 - (index - 1) * 26)
                T.Surface(item, "rail")
                item.activeBar = T.Fill(item:CreateTexture(nil, "ARTWORK"), "selected")
                item.activeBar:SetPoint("TOPLEFT")
                item.activeBar:SetPoint("BOTTOMLEFT")
                item.activeBar:SetWidth(3)
                item.label = UI.FontString(item, "GameFontHighlightSmall")
                item.label:SetPoint("LEFT", 10, 0)
                item.label:SetPoint("RIGHT", -8, 0)
                item.label:SetJustifyH("LEFT")
                if item.label.SetWordWrap then item.label:SetWordWrap(false) end
                item:HookScript("OnEnter", function(self) paint(self, get() == self.value, true) end)
                item:HookScript("OnLeave", function(self) paint(self, get() == self.value, false) end)
                item:SetScript("OnClick", function(self)
                    pick(self.value)
                    menu:Hide()
                end)
                items[index] = item
            end
            item:SetSize(width - 10, 24)
            item.value = value
            item.label:SetText(labels[index] or "—")
            paint(item, get() == value, false)
            item:Show()
        end
        for index = #values + 1, #items do items[index]:Hide() end
    end
    button:SetScript("OnClick", function(self)
        ensure()
        if menu:IsShown() then menu:Hide(); return end
        fill()
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -5)
        dismiss:Show()
        menu:Show()
    end)
    return function() if menu then menu:Hide() end end
end

-- ── Row controls ───────────────────────────────────────────────────────────

function UI.Row(parent, y, height, title, hint, width)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width or UI.CONTENT_WIDTH, height or 38)
    row:SetPoint("TOPLEFT", UI.PAD, y)
    if title ~= nil then
        row.Title = UI.FontString(row)
        row.Title:SetPoint("LEFT", 0, 0)
        row.hcRefreshTitle = function() row.Title:SetText(resolve(title) or "") end
        row.hcRefreshTitle()
    end
    row:EnableMouse(true)
    UI.AttachHint(row, title or HC.name, hint)
    return row
end

function UI.Check(panel, label, hint, y, get, set, width)
    local row = UI.Row(panel, y, 28, nil, hint, width)
    row.hcHintTitle = label
    local btn = UI.CheckButton(row)
    btn:SetPoint("LEFT", 12, 0)
    btn.Text:SetText(label)
    row.hcCheckbox = btn
    local function toggle()
        btn:SetChecked(not btn:GetChecked())
        set(btn:GetChecked() and true or false)
        refreshAll(panel)
    end
    btn:SetScript("OnClick", toggle)
    row:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then toggle() end
    end)
    local function render() btn:SetChecked(get() and true or false) end
    onRefresh(panel, render)
    render()
    return row, y - 32
end

function UI.Slider(panel, label, hint, y, minV, maxV, step, get, set, fmt, width)
    local row = UI.Row(panel, y, 28, label, hint, width)
    local sliderWidth = math.max(80, math.min(180, (width or UI.CONTENT_WIDTH) - 150))
    local s = CreateFrame("Slider", nil, row)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(sliderWidth, 16)
    s:SetPoint("LEFT", row, "LEFT", 150, 0)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    local fill
    if T.IsClassic() then
        -- Blizzard's slider bar: a bordered groove and the gold thumb.
        local groove = CreateFrame("Frame", nil, s, "BackdropTemplate")
        groove:SetPoint("LEFT", 0, 0)
        groove:SetPoint("RIGHT", 0, 0)
        groove:SetHeight(14)
        groove:SetFrameLevel(math.max(0, s:GetFrameLevel() - 1))
        if groove.SetBackdrop then
            groove:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
                edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", tile = true, tileSize = 8, edgeSize = 8,
                insets = { left = 3, right = 3, top = 6, bottom = 6 } })
        end
        local thumb = s:CreateTexture(nil, "OVERLAY")
        thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        thumb:SetSize(32, 32)
        if s.SetThumbTexture then s:SetThumbTexture(thumb) end
        fill = s:CreateTexture(nil, "ARTWORK")
        fill:Hide()
    else
        local track = T.Fill(s:CreateTexture(nil, "BACKGROUND"), "rail")
        track:SetPoint("LEFT", 4, 0)
        track:SetPoint("RIGHT", -4, 0)
        track:SetHeight(4)
        fill = T.Fill(s:CreateTexture(nil, "ARTWORK"), "selected")
        fill:SetPoint("LEFT", 4, 0)
        fill:SetHeight(4)
        local thumb = T.Fill(s:CreateTexture(nil, "OVERLAY"), "selected")
        thumb:SetSize(10, 10)
        if s.SetThumbTexture then s:SetThumbTexture(thumb) end
    end
    local value = UI.FontString(row, "GameFontHighlight", "muted")
    value:SetPoint("LEFT", s, "RIGHT", 14, 0)

    local rendering = false
    local function render(v)
        if row.hcRefreshTitle then row.hcRefreshTitle() end
        value:SetText(fmt and fmt(v) or tostring(v))
        local ratio = (v - minV) / math.max(1, maxV - minV)
        fill:SetWidth(math.max(0, (sliderWidth - 8) * ratio))
    end
    s:SetScript("OnValueChanged", function(_, v)
        -- Snap before storing: some clients report unsnapped values mid-drag.
        v = math.floor(v / step + 0.5) * step
        render(v)
        if rendering then return end
        set(v)
        refreshAll(panel)
    end)
    UI.AttachHint(s, label, hint)
    local function refresh()
        rendering = true
        s:SetValue(get())
        rendering = false
        render(get())
    end
    onRefresh(panel, refresh)
    refresh()
    return row, y - 34
end

-- A labelled select.  values/labels may be tables or functions.
-- buttonWidth widens the select for long choices (default 156).
function UI.Dropdown(panel, label, hint, y, values, labels, get, set, width, offset, buttonWidth)
    local row = UI.Row(panel, y, 30, label, hint, width)
    local button = UI.SelectButton(row, buttonWidth or 156, 30)
    button:SetPoint("LEFT", row, "LEFT", offset or 150, 0)
    local function choices() return resolve(values), resolve(labels) end
    local function render()
        local vals, labs = choices()
        local current = get()
        for index, value in ipairs(vals) do
            if current == value then button:SetText(labs[index]); return end
        end
        -- A stored choice that is no longer offered shows the first option.
        button:SetText(labs[1] or "—")
    end
    row.hcCloseMenu = popupMenu(button, choices, get, function(value)
        set(value)
        render()
        refreshAll(panel)
    end)
    UI.AttachHint(button, label, hint)
    onRefresh(panel, render)
    render()
    return row, y - 34, button
end

-- A select whose choices can change after the page is built (chat windows,
-- known spells): a small title above a wide select.
-- optionsFn() returns values, labels.
function UI.DynamicDropdown(panel, label, hint, y, optionsFn, get, set, width)
    local row = UI.Row(panel, y, 54, nil, hint)
    row.hcHintTitle = label
    local title = UI.FontString(row, "GameFontHighlightSmall", "muted")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(label)
    local button = UI.SelectButton(row, width or 264, 30)
    button:SetPoint("TOPLEFT", 0, -15)
    local function render()
        local values, labels = optionsFn()
        local current = get()
        for index, value in ipairs(values) do
            if value == current then button:SetText(labels[index]); return end
        end
        -- The stored choice is no longer offered: show the first option.
        button:SetText(labels[1] or "—")
    end
    row.hcCloseMenu = popupMenu(button, optionsFn, get, function(value)
        set(value)
        render()
        refreshAll(panel)
    end)
    UI.AttachHint(button, label, hint)
    UI.AttachTitleHint(row, title, label, hint)
    onRefresh(panel, render)
    render()
    return row, y - 54, button
end

-- Two labelled selects under one heading.
-- left/right = { label, values, labels, get, set, hint? }; values and labels
-- may be functions.  Returns leftButton, rightButton, next y.
function UI.DropdownPair(panel, heading, y, left, right)
    local groupTitle = UI.FontString(panel, "GameFontHighlight", "accent")
    groupTitle:SetPoint("TOPLEFT", UI.PAD, y)
    groupTitle:SetText(heading)
    local function choice(x, spec)
        local title = UI.FontString(panel, "GameFontHighlightSmall", "muted")
        title:SetPoint("TOPLEFT", x, y - 20)
        title:SetText(spec.label)
        local button = UI.SelectButton(panel, 150, 30)
        button:SetPoint("TOPLEFT", x, y - 35)
        button.hcTitle = title
        local function choices() return resolve(spec.values), resolve(spec.labels) end
        local function render()
            local values, labels = choices()
            local current = spec.get()
            local text = labels[1] or "—"
            for index, value in ipairs(values) do
                if value == current then text = labels[index] end
            end
            button:SetText(text)
        end
        popupMenu(button, choices, spec.get, function(value)
            spec.set(value)
            render()
            refreshAll(panel)
        end)
        UI.AttachHint(button, heading .. " - " .. spec.label, spec.hint)
        UI.AttachTitleHint(panel, title, heading .. " - " .. spec.label, spec.hint)
        onRefresh(panel, render)
        render()
        return button
    end
    local leftButton = choice(UI.PAD, left)
    local rightButton = choice(UI.PAD + 190, right)
    return leftButton, rightButton, y - 76
end

-- A menu of radio modes and combinable conditions, summarised on the button.
-- spec = { items = { { label, radio?, heading?, get, set, disabled? } }, summary = fn }
-- label and disabled may be functions; they are re-read each time it opens.
function UI.MultiSelect(panel, label, hint, y, spec, width)
    local title = UI.FontString(panel, "GameFontHighlightSmall", "muted")
    title:SetPoint("TOPLEFT", UI.PAD, y)
    title:SetText(label)
    local btn = UI.SelectButton(panel, width or 240, 30)
    btn:SetPoint("TOPLEFT", UI.PAD, y - 15)
    local function render() btn:SetText(spec.summary()) end
    local menu, dismiss, controls
    local function refreshChecks()
        for _, control in ipairs(controls) do
            local item = control.item
            control.check:SetChecked(item.get() and true or false)
            control.check.Text:SetText(resolve(item.label))
            T.Text(control.check.Text, resolve(item.disabled) and "muted" or "text")
        end
    end
    local function ensure()
        if menu then return end
        dismiss = CreateFrame("Button", nil, UIParent)
        dismiss:SetFrameStrata("FULLSCREEN_DIALOG")
        dismiss:SetFrameLevel(199)
        dismiss:SetAllPoints(UIParent)
        dismiss:EnableMouse(true)
        menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(200)
        menu:SetClampedToScreen(true)
        T.Surface(menu, "menu", "menuEdge")
        local menuWidth, cursorY = btn:GetWidth(), -5
        controls = {}
        for _, item in ipairs(spec.items) do
            if item.heading then
                local heading = UI.FontString(menu, "GameFontDisableSmall", "muted")
                heading:SetPoint("TOPLEFT", 10, cursorY - 3)
                heading:SetText(item.label)
                cursorY = cursorY - 24
            else
                local choice = CreateFrame("Button", nil, menu, "BackdropTemplate")
                choice:SetSize(menuWidth - 10, 26)
                choice:SetPoint("TOPLEFT", 5, cursorY)
                T.Surface(choice, "rail")
                choice.check = UI.CheckButton(choice)
                choice.check:SetPoint("LEFT", 8, 0)
                -- The tick is drawn by a button of its own; let clicks on it
                -- reach the row, or only the label would respond.
                choice.check:EnableMouse(false)
                if item.radio then choice.check:SetSize(14, 14) end
                choice.check.Text:SetText(resolve(item.label))
                choice.item = item
                choice:SetScript("OnClick", function(self)
                    if resolve(self.item.disabled) then return end
                    if self.item.radio then self.item.set(true) else self.item.set(not self.item.get()) end
                    refreshAll(panel)
                    render()
                    refreshChecks()
                end)
                choice:HookScript("OnEnter", function(self) self:SetBackdropColor(T.Unpack("menuActive")) end)
                choice:HookScript("OnLeave", function(self) self:SetBackdropColor(T.Unpack("rail")) end)
                controls[#controls + 1] = choice
                cursorY = cursorY - 28
            end
        end
        menu:SetSize(menuWidth, -cursorY + 5)
        menu:SetScript("OnHide", function() dismiss:Hide() end)
        dismiss:SetScript("OnClick", function() menu:Hide() end)
        menu:Hide()
    end
    btn:SetScript("OnClick", function(self)
        ensure()
        if menu:IsShown() then menu:Hide(); return end
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -5)
        refreshChecks()
        dismiss:Show()
        menu:Show()
    end)
    UI.AttachHint(btn, label, hint)
    UI.AttachTitleHint(panel, title, label, hint)
    onRefresh(panel, render)
    render()
    return btn, y - 54
end

-- A searchable list for large catalogues such as the client's emotes.
-- spec = { items = function() -> { { value, label } }, get, set, width }
function UI.SearchPicker(panel, label, hint, y, spec, width, offset)
    local row = UI.Row(panel, y, 30, label, hint, width)
    local pickerWidth = spec.width or 220
    local button = UI.SelectButton(row, pickerWidth, 30)
    button:SetPoint("LEFT", row, "LEFT", offset or 150, 0)
    local function labelFor(value)
        for _, item in ipairs(spec.items()) do
            if item.value == value then return item.label end
        end
        return tostring(value or "—")
    end
    local function render() button:SetText(labelFor(spec.get())) end
    local list, dismiss, rows
    local function ensure()
        if list then return end
        dismiss = CreateFrame("Button", nil, UIParent)
        dismiss:SetFrameStrata("FULLSCREEN_DIALOG")
        dismiss:SetFrameLevel(199)
        dismiss:SetAllPoints(UIParent)
        dismiss:EnableMouse(true)
        list = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        list:SetFrameStrata("FULLSCREEN_DIALOG")
        list:SetFrameLevel(200)
        list:SetClampedToScreen(true)
        list:SetSize(pickerWidth, 330)
        T.Surface(list, "menu", "menuEdge")
        local search = CreateFrame("EditBox", nil, list, "BackdropTemplate")
        search:SetSize(pickerWidth - 16, 24)
        search:SetPoint("TOPLEFT", 8, -8)
        search:SetAutoFocus(false)
        search:SetFontObject(ChatFontNormal)
        search:SetTextInsets(6, 6, 0, 0)
        T.Surface(search, "rail", "edge")
        search:SetScript("OnEscapePressed", function() list:Hide() end)
        local scroll = CreateFrame("ScrollFrame", nil, list, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 6, -40)
        scroll:SetPoint("BOTTOMRIGHT", -28, 6)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(pickerWidth - 36, 1)
        scroll:SetScrollChild(content)
        rows = {}
        list.search, list.scroll, list.content = search, scroll, content
        list:SetScript("OnHide", function() dismiss:Hide() end)
        dismiss:SetScript("OnClick", function() list:Hide() end)
        list:Hide()
    end
    local function populate()
        local query = (list.search:GetText() or ""):lower()
        local count = 0
        for index, item in ipairs(spec.items()) do
            local entry = rows[index]
            if not entry then
                entry = CreateFrame("Button", nil, list.content, "BackdropTemplate")
                entry:SetHeight(22)
                T.Surface(entry, "menu")
                entry.label = UI.FontString(entry, "GameFontHighlightSmall")
                entry.label:SetPoint("LEFT", 8, 0)
                entry:HookScript("OnEnter", function(self) self:SetBackdropColor(T.Unpack("menuActive")) end)
                entry:HookScript("OnLeave", function(self) self:SetBackdropColor(T.Unpack("menu")) end)
                rows[index] = entry
            end
            if query == "" or item.label:lower():find(query, 1, true) then
                entry:SetWidth(pickerWidth - 36)
                entry:ClearAllPoints()
                entry:SetPoint("TOPLEFT", 0, -count * 22)
                entry.label:SetText(item.label)
                T.Text(entry.label, spec.get() == item.value and "selected" or "text")
                entry:SetScript("OnClick", function()
                    spec.set(item.value)
                    render()
                    refreshAll(panel)
                    list:Hide()
                end)
                entry:Show()
                count = count + 1
            else
                entry:Hide()
            end
        end
        for index = #spec.items() + 1, #rows do rows[index]:Hide() end
        list.content:SetHeight(math.max(1, count * 22))
        list.scroll:SetVerticalScroll(0)
    end
    button:SetScript("OnClick", function(self)
        ensure()
        if list:IsShown() then list:Hide(); return end
        list.search:SetScript("OnTextChanged", populate)
        list.search:SetText("")
        populate()
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -5)
        dismiss:Show()
        list:Show()
        list.search:SetFocus()
    end)
    UI.AttachHint(button, label, hint)
    onRefresh(panel, render)
    render()
    return row, y - 34, button
end

-- A single-line text field that saves on Enter or when it loses focus.
function UI.TextInput(panel, label, hint, y, get, set, width, inputWidth)
    local row = UI.Row(panel, y, 30, label, hint, width)
    local box = CreateFrame("EditBox", nil, row, "BackdropTemplate")
    box:SetSize(inputWidth or 300, 26)
    box:SetPoint("LEFT", row, "LEFT", 150, 0)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetTextInsets(8, 8, 0, 0)
    T.Surface(box, "rail", "edge")
    local function save(self) set(self:GetText() or "") end
    box:SetScript("OnEnterPressed", function(self) save(self); self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", save)
    box:SetScript("OnEscapePressed", function(self) self:SetText(get() or ""); self:ClearFocus() end)
    UI.AttachHint(box, label, hint)
    onRefresh(panel, function()
        if not (box.HasFocus and box:HasFocus()) then box:SetText(get() or "") end
    end)
    box:SetText(get() or "")
    return row, y - 34, box
end

-- ── Layout helpers ─────────────────────────────────────────────────────────

-- A section heading with a rule running to the right edge.
function UI.Header(panel, text, y)
    local fs = UI.FontString(panel, "GameFontNormalLarge", "section")
    fs:SetPoint("TOPLEFT", UI.PAD, y)
    fs:SetText(text)
    local rule = T.Fill(panel:CreateTexture(nil, "ARTWORK"), "edge")
    rule:SetHeight(1)
    rule:SetPoint("LEFT", fs, "RIGHT", 10, 0)
    rule:SetPoint("RIGHT", panel.hcHeaderOwner or panel, "RIGHT", -20, 0)
    return fs, y - 28
end

-- Small muted capitals above a list.
function UI.SectionLabel(panel, text, y)
    local fs = UI.FontString(panel, "GameFontDisableSmall", "muted")
    fs:SetPoint("TOPLEFT", UI.PAD, y)
    fs:SetText(text)
    return fs, y - 20
end

-- A single line of body text.  Settings text never wraps.
function UI.Text(panel, text, y, role)
    local fs = UI.FontString(panel, "GameFontHighlightSmall", role or "muted")
    fs:SetPoint("TOPLEFT", UI.PAD, y)
    fs:SetWidth(UI.CONTENT_WIDTH)
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    fs:SetText(text)
    return fs, y - 20
end

-- A bordered card at the page's left edge; returns the card and next y.
function UI.Card(panel, y, height, width)
    local card = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    card:SetPoint("TOPLEFT", UI.PAD, y)
    card:SetSize(width or UI.CONTENT_WIDTH, height)
    T.Surface(card, "raised", "edge")
    return card, y - height - 14
end

-- A button that goes to another settings page, e.g. "View ignored (3)".
function UI.PageLink(panel, y, text, page)
    local button = UI.Button(panel, 180, 22)
    button:SetPoint("TOPLEFT", UI.PAD, y)
    button:SetText(resolve(text))
    button:SetScript("OnClick", function() HC.Settings:Show(page) end)
    onRefresh(panel, function() button:SetText(resolve(text)) end)
    return button, y - 30
end

-- A danger-styled button that restores one page's settings.
function UI.PageReset(panel, y, reset, label)
    local button = UI.Button(panel, 180, 22, "danger")
    button:SetPoint("TOPLEFT", UI.PAD, y - 4)
    button:SetText(label or "Reset page")
    UI.AttachHint(button, label or "Reset page", "Restore the settings on this page.")
    button:SetScript("OnClick", function()
        reset()
        refreshAll(panel)
    end)
    return button, y - 40
end

function UI.SetEnabled(control, enabled)
    if not control then return end
    if control.SetEnabled then control:SetEnabled(enabled) end
    local shade = enabled and 1 or 0.5
    if control.Text then control.Text:SetTextColor(shade, shade, shade) end
    if control.hcTitle then control.hcTitle:SetTextColor(shade, shade, shade) end
end

-- Retail changed the colour-picker entry point; keep the compatibility work
-- here.  onChange receives { r, g, b, a } on change and on cancel.
function UI.ShowColourPicker(initial, onChange)
    if not ColorPickerFrame then return end
    initial = initial or {}
    local colour = { r = tonumber(initial.r) or 1, g = tonumber(initial.g) or 1,
        b = tonumber(initial.b) or 1, a = tonumber(initial.a) or 1 }
    local function apply()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        onChange({ r = r, g = g, b = b, a = ColorPickerFrame:GetColorAlpha() })
    end
    local function restore(previous)
        previous = previous or {}
        onChange({ r = previous.r or colour.r, g = previous.g or colour.g,
            b = previous.b or colour.b, a = previous.opacity or previous.a or colour.a })
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({ r = colour.r, g = colour.g, b = colour.b,
            opacity = colour.a, hasOpacity = true, swatchFunc = apply, opacityFunc = apply,
            cancelFunc = restore })
        return
    end
    ColorPickerFrame.func, ColorPickerFrame.opacityFunc = apply, apply
    ColorPickerFrame.cancelFunc = restore
    ColorPickerFrame.hasOpacity, ColorPickerFrame.opacity = true, colour.a
    ColorPickerFrame:SetColorRGB(colour.r, colour.g, colour.b)
    ColorPickerFrame:Show()
end

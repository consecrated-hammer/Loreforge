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

UI.PAD = 24
-- The window sets this to its real content width before it builds pages.
UI.CONTENT_WIDTH = 540
-- Every setting sits in a cell this tall: label on the left, control on the
-- right.  A page in two columns pairs cells into one striped row.
UI.CELL_H = 40
UI.CELL_INSET = 14

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

-- ── Cell layout ────────────────────────────────────────────────────────────
-- Pages stack settings top to bottom by passing y along.  In two columns a
-- left cell leaves y where it was, so the next cell lands beside it; anything
-- else placed at that y (a header, text, a card) first moves below the pair.
-- Rows alternate a quiet stripe, and a filled two-column row has a centre rule.

local function layout(panel)
    local state = rawget(panel, "hcLayout")
    if not state then
        state = { columns = panel.hcColumns or 1, open = false, stripe = 0 }
        panel.hcLayout = state
    end
    return state
end

-- Sets one or two columns for the cells that follow.
function UI.Columns(panel, count, y)
    y = UI.Flush(panel, y)
    layout(panel).columns = count == 2 and 2 or 1
    return y
end

-- Closes a half-filled two-column row; returns the y below it.  Any y
-- inside the open row (callers often pass y - 4 for a little air) lands
-- below it, so nothing is drawn over the half row.
function UI.Flush(panel, y)
    local state = rawget(panel, "hcLayout")
    if state and state.open then
        state.open = false
        return math.min(y, state.rowY - state.rowH - 4)
    end
    return y
end

-- Claims a cell at y.  Returns x, width, the y for whatever comes next, and
-- the cell's slot: { stripe, columns, left }.  The row draws its own stripe
-- (see UI.Row), so a page that moves rows later moves their stripes too.
function UI.PlaceCell(panel, y, height)
    local state = layout(panel)
    height = height or UI.CELL_H
    if state.columns == 2 then
        local half = math.floor((UI.CONTENT_WIDTH - 1) / 2)
        if state.open and state.rowY == y then
            state.open = false
            -- The pair is complete, so the centre rule now separates something.
            local rule = state.leftSlot and state.leftSlot.rule
            if rule then rule:Show() end
            return UI.PAD + half + 1, half, y - math.max(height, state.rowH) - 4,
                { stripe = state.stripe, columns = 2, left = false }
        end
        state.stripe = state.stripe + 1
        state.open, state.rowY, state.rowH = true, y, height
        state.leftSlot = { stripe = state.stripe, columns = 2, left = true }
        return UI.PAD, half, y, state.leftSlot
    end
    state.open = false
    state.stripe = state.stripe + 1
    return UI.PAD, UI.CONTENT_WIDTH, y - height - 4, { stripe = state.stripe, columns = 1, left = true }
end

-- A row's stripe: the full content width from the row's left edge, so a
-- left cell also paints behind its right-hand neighbour.
local function stripe(row, slot, height)
    if not (slot and slot.left) then return end
    local fill = row:CreateTexture(nil, "BACKGROUND")
    T.Fill(fill, slot.stripe % 2 == 1 and "stripe" or "content")
    fill:SetPoint("TOPLEFT", row, "TOPLEFT")
    fill:SetSize(UI.CONTENT_WIDTH, height)
    row.hcStripe = fill
    if slot.columns == 2 then
        -- Hidden until a right-hand cell joins the row: a lone cell has
        -- nothing to divide.
        local rule = T.Fill(row:CreateTexture(nil, "BORDER"), "edge")
        rule:SetSize(1, height - 12)
        rule:SetPoint("TOPLEFT", row, "TOPLEFT", math.floor((UI.CONTENT_WIDTH - 1) / 2), -6)
        rule:Hide()
        row.hcRule, slot.rule = rule, rule
    end
end
UI.Stripe = stripe

-- Starts the stripes again, as each section does.
function UI.RestartStripes(panel)
    layout(panel).stripe = 0
end

-- Hints live in a tooltip rather than a second grey line under every control.
function UI.AttachHint(control, title, hint)
    if not hint then return end
    control.hcHintTitle, control.hcHint = title, hint
    control:HookScript("OnEnter", function(self)
        if not self.hcHint then return end
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

-- An on/off switch: a pill track with a round knob.  The button covers its
-- whole cell, so clicking the label works too; .Text is that label.
function UI.Switch(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn.Text = UI.FontString(btn)
    btn.Text:SetPoint("LEFT", UI.CELL_INSET, 0)
    btn.Text:SetJustifyH("LEFT")
    if btn.Text.SetWordWrap then btn.Text:SetWordWrap(false) end
    local track = CreateFrame("Frame", nil, btn)
    track:SetSize(40, 20)
    track:SetPoint("RIGHT", -UI.CELL_INSET, 0)
    btn.Text:SetPoint("RIGHT", track, "LEFT", -12, 0)
    local left = T.Icon(track:CreateTexture(nil, "ARTWORK"), "Circle.tga")
    left:SetSize(10, 20)
    left:SetPoint("LEFT")
    if left.SetTexCoord then left:SetTexCoord(0, 0.5, 0, 1) end
    local right = T.Icon(track:CreateTexture(nil, "ARTWORK"), "Circle.tga")
    right:SetSize(10, 20)
    right:SetPoint("RIGHT")
    if right.SetTexCoord then right:SetTexCoord(0.5, 1, 0, 1) end
    local middle = track:CreateTexture(nil, "ARTWORK")
    middle:SetTexture("Interface\\Buttons\\WHITE8X8")
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    local knob = T.Icon(track:CreateTexture(nil, "OVERLAY"), "Circle.tga")
    knob:SetSize(14, 14)
    btn.track, btn.knob = track, knob
    local function paint(self)
        local role = self.checked and "accent" or "edge"
        for _, part in ipairs({ left, right, middle }) do
            if part.SetVertexColor then part:SetVertexColor(T.Unpack(role)) end
        end
        knob:ClearAllPoints()
        if self.checked then
            knob:SetPoint("RIGHT", track, "RIGHT", -3, 0)
            knob:SetVertexColor(T.Unpack("field"))
        else
            knob:SetPoint("LEFT", track, "LEFT", 3, 0)
            knob:SetVertexColor(T.Unpack("muted"))
        end
        local enabled = self.enabled ~= false
        track:SetAlpha(enabled and 1 or 0.4)
        T.Text(self.Text, enabled and "text" or "muted")
    end
    btn.SetChecked = function(self, checked)
        self.checked = checked and true or false
        paint(self)
    end
    btn.GetChecked = function(self) return self.checked end
    local setEnabled = btn.SetEnabled
    btn.SetEnabled = function(self, enabled)
        if setEnabled then setEnabled(self, enabled) end
        self.enabled = enabled and true or false
        paint(self)
    end
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
        local border = variant == "danger" and "danger" or variant == "primary" and "accent" or "edge"
        T.Surface(button, "raised", border)
        button.Text = UI.FontString(button, "GameFontHighlight", variant == "danger" and "danger" or "text")
        button.Text:SetAllPoints()
        button.Text:SetJustifyH("CENTER")
        button:HookScript("OnEnter", function(self)
            if self.enabled == false then return end
            self:SetBackdropColor(T.Unpack("hover"))
            if border == "edge" then T.Border(self, "menuEdge") end
        end)
        button:HookScript("OnLeave", function(self)
            self:SetBackdropColor(T.Unpack("raised"))
            T.Border(self, border)
        end)
    end
    button.SetText = function(self, text)
        self.Text:SetText(text or "")
        self.text = text
    end
    button.GetText = function(self) return self.text end
    return button
end

local function chevron(button)
    local arrow = T.Icon(button:CreateTexture(nil, "OVERLAY"), "Chevron.tga", "muted")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -10, 0)
    button.chevron = arrow
end

-- A select is a value field, so a subtle border makes its value readable.
function UI.SelectButton(parent, width, height)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 160, height or 28)
    T.Surface(button, "field", "edge")
    button:HookScript("OnEnter", function(self) T.Border(self, "menuEdge") end)
    button:HookScript("OnLeave", function(self) T.Border(self, "edge") end)
    button.Text = UI.FontString(button, "GameFontHighlightSmall")
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

-- A setting cell: title on the left, the control added by the caller on the
-- right.  row.hcNextY is where the next setting goes.
function UI.Row(parent, y, height, title, hint, width)
    local cellHeight = math.max(height or UI.CELL_H, UI.CELL_H)
    local x, cellWidth, nextY, slot = UI.PlaceCell(parent, y, cellHeight)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(cellWidth, cellHeight)
    row:SetPoint("TOPLEFT", x, y)
    stripe(row, slot, cellHeight)
    row.hcNextY, row.hcWidth = nextY, cellWidth
    if title ~= nil then
        row.Title = UI.FontString(row)
        row.Title:SetPoint("LEFT", UI.CELL_INSET, 0)
        row.Title:SetJustifyH("LEFT")
        if row.Title.SetWordWrap then row.Title:SetWordWrap(false) end
        row.hcRefreshTitle = function() row.Title:SetText(resolve(title) or "") end
        row.hcRefreshTitle()
    end
    row:EnableMouse(true)
    UI.AttachHint(row, title or HC.name, hint)
    return row
end

-- Keeps a row's title clear of its control.
local function fitTitle(row, control)
    if row.Title then row.Title:SetPoint("RIGHT", control, "LEFT", -12, 0) end
end

function UI.Check(panel, label, hint, y, get, set, width)
    local row = UI.Row(panel, y, UI.CELL_H, nil, hint, width)
    row.hcHintTitle = label
    local btn
    if T.IsClassic() then
        -- Classic keeps Blizzard's own checkbox beside its label.
        btn = UI.CheckButton(row)
        btn:SetPoint("LEFT", UI.CELL_INSET, 0)
    else
        btn = UI.Switch(row)
        btn:SetAllPoints(row)
    end
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
    UI.AttachHint(btn, label, hint)
    local function render() btn:SetChecked(get() and true or false) end
    onRefresh(panel, render)
    render()
    return row, row.hcNextY
end

-- A small button inside a setting's cell, such as "Test" beside a sound
-- switch.  It sits left of the switch (or at the cell's right edge).
function UI.CellAction(row, text, width, hint)
    local switch = row.hcCheckbox
    local button = UI.Button(row, width or 52, 22)
    if switch and switch.track then
        button:SetPoint("RIGHT", switch.track, "LEFT", -14, 0)
        switch.Text:SetPoint("RIGHT", button, "LEFT", -10, 0)
        if button.SetFrameLevel and switch.GetFrameLevel then
            button:SetFrameLevel((switch:GetFrameLevel() or 0) + 2)
        end
    else
        button:SetPoint("RIGHT", row, "RIGHT", -UI.CELL_INSET, 0)
    end
    button:SetText(text)
    if hint then UI.AttachHint(button, text, hint) end
    return button
end

function UI.Slider(panel, label, hint, y, minV, maxV, step, get, set, fmt, width)
    local row = UI.Row(panel, y, UI.CELL_H, label, hint, width)
    local sliderWidth = math.max(90, math.min(160, math.floor(row.hcWidth * 0.34)))
    local box = CreateFrame("Frame", nil, row, "BackdropTemplate")
    box:SetSize(48, 24)
    box:SetPoint("RIGHT", -UI.CELL_INSET, 0)
    T.Surface(box, "field", "edge")
    local value = UI.FontString(box, "GameFontHighlightSmall")
    value:SetAllPoints()
    value:SetJustifyH("CENTER")
    local s = CreateFrame("Slider", nil, row)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(sliderWidth, 18)
    s:SetPoint("RIGHT", box, "LEFT", -12, 0)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    fitTitle(row, s)
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
        local track = T.Fill(s:CreateTexture(nil, "BACKGROUND"), "edge")
        track:SetPoint("LEFT", 6, 0)
        track:SetPoint("RIGHT", -6, 0)
        track:SetHeight(4)
        fill = T.Fill(s:CreateTexture(nil, "ARTWORK"), "accent")
        fill:SetPoint("LEFT", 6, 0)
        fill:SetHeight(4)
        local thumb = T.Icon(s:CreateTexture(nil, "OVERLAY"), "Circle.tga", "accent")
        thumb:SetSize(14, 14)
        if s.SetThumbTexture then s:SetThumbTexture(thumb) end
    end

    local rendering = false
    local function render(v)
        if row.hcRefreshTitle then row.hcRefreshTitle() end
        value:SetText(fmt and fmt(v) or tostring(v))
        local ratio = (v - minV) / math.max(1, maxV - minV)
        fill:SetWidth(math.max(0.01, (sliderWidth - 12) * ratio))
    end
    s:SetScript("OnValueChanged", function(_, v)
        -- Snap before storing: some clients report unsnapped values mid-drag.
        v = math.floor(v / step + 0.5) * step
        render(v)
        if rendering then return end
        set(v)
        refreshAll(panel)
    end)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetValue() or get()
        self:SetValue(math.max(minV, math.min(maxV, current + delta * step)))
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
    return row, row.hcNextY
end

-- A labelled select.  values/labels may be tables or functions.
-- buttonWidth widens the select for long choices.  offset is ignored: the
-- select sits at the right of its cell.
function UI.Dropdown(panel, label, hint, y, values, labels, get, set, width, offset, buttonWidth)
    local row = UI.Row(panel, y, UI.CELL_H, label, hint, width)
    local wide = math.min(buttonWidth or 180, math.floor(row.hcWidth * 0.55))
    local button = UI.SelectButton(row, wide, 28)
    button:SetPoint("RIGHT", -UI.CELL_INSET, 0)
    fitTitle(row, button)
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
    return row, row.hcNextY, button
end

-- A select whose choices can change after the page is built (chat windows,
-- known spells): a small title above a wide select.
-- optionsFn() returns values, labels.
function UI.DynamicDropdown(panel, label, hint, y, optionsFn, get, set, width)
    local row = UI.Row(panel, y, UI.CELL_H, label, hint)
    local button = UI.SelectButton(row, math.min(width or 240, math.floor(row.hcWidth * 0.6)), 28)
    button:SetPoint("RIGHT", -UI.CELL_INSET, 0)
    fitTitle(row, button)
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
    onRefresh(panel, render)
    render()
    return row, row.hcNextY, button
end

-- Two labelled selects under one heading.
-- left/right = { label, values, labels, get, set, hint? }; values and labels
-- may be functions.  Returns leftButton, rightButton, next y.
function UI.DropdownPair(panel, heading, y, left, right)
    y = UI.Flush(panel, y)
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
-- A tick list that drops from `btn`.  spec = { items = { { label, get, set,
-- radio?, disabled?, heading? } }, summary() }; render() relabels btn.
local function checklist(btn, panel, spec, render)
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
        -- spec.bulk: Select all / Deselect all across the top, as in
        -- Blizzard's own filter menus. true sets every tickable item; a
        -- function(selected) does it the addon's way (keeping one, say).
        if spec.bulk then
            local function bulk(selected)
                if type(spec.bulk) == "function" then
                    spec.bulk(selected)
                else
                    for _, item in ipairs(spec.items) do
                        if not item.heading and not item.radio and not resolve(item.disabled) then item.set(selected) end
                    end
                end
                refreshAll(panel)
                render()
                refreshChecks()
            end
            local all = UI.Link(menu, "Select all", function() bulk(true) end)
            all:SetPoint("TOPLEFT", 12, cursorY - 6)
            local none = UI.Link(menu, "Deselect all", function() bulk(false) end)
            none:SetPoint("LEFT", all, "RIGHT", 14, 0)
            cursorY = cursorY - 28
        end
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
end

function UI.MultiSelect(panel, label, hint, y, spec, width)
    local row = UI.Row(panel, y, UI.CELL_H, label, hint)
    local btn = UI.SelectButton(row, math.min(width or 240, math.floor(row.hcWidth * 0.6)), 28)
    btn:SetPoint("RIGHT", -UI.CELL_INSET, 0)
    fitTitle(row, btn)
    local function render() btn:SetText(spec.summary()) end
    checklist(btn, panel, spec, render)
    UI.AttachHint(btn, label, hint)
    onRefresh(panel, render)
    render()
    return btn, row.hcNextY
end

-- MultiSelect's tick list on a small button with a title above, for cards
-- laid out by hand such as profile rules.  Returns the button and the y below.
function UI.CompactMultiSelect(parent, label, hint, x, y, width, spec)
    local title = UI.FontString(parent, "GameFontHighlightSmall", "muted")
    title:SetPoint("TOPLEFT", x, y)
    title:SetText(label)
    local button = UI.SelectButton(parent, width or 150, 26)
    button:SetPoint("TOPLEFT", x, y - 15)
    button.hcTitle = title
    local function render() button:SetText(spec.summary()) end
    checklist(button, parent, spec, render)
    UI.AttachHint(button, label, hint)
    UI.AttachTitleHint(parent, title, label, hint)
    onRefresh(parent, render)
    render()
    return button, y - 45
end

-- A searchable list for large catalogues such as the client's emotes.
-- spec = { items = function() -> { { value, label } }, get, set, width }
function UI.SearchPicker(panel, label, hint, y, spec, width, offset)
    local row = UI.Row(panel, y, UI.CELL_H, label, hint, width)
    local pickerWidth = math.min(spec.width or 220, math.floor(row.hcWidth * 0.6))
    local button = UI.SelectButton(row, pickerWidth, 28)
    button:SetPoint("RIGHT", -UI.CELL_INSET, 0)
    fitTitle(row, button)
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
    return row, row.hcNextY, button
end

-- A select with a small title above it, placed at x, y inside any frame
-- (cards, multi-column rows).  values/labels may be functions.
-- Returns the button and the y below it.
function UI.CompactSelect(parent, label, hint, x, y, width, values, labels, get, set)
    local title = UI.FontString(parent, "GameFontHighlightSmall", "muted")
    title:SetPoint("TOPLEFT", x, y)
    title:SetText(label)
    local button = UI.SelectButton(parent, width or 150, 26)
    button:SetPoint("TOPLEFT", x, y - 15)
    button.hcTitle = title
    local function choices() return resolve(values), resolve(labels) end
    local function render()
        local vals, labs = choices()
        local current, text = get(), labs[1] or "-"
        for index, value in ipairs(vals) do
            if value == current then text = labs[index] end
        end
        button:SetText(text)
    end
    button.hcCloseMenu = popupMenu(button, choices, get, function(value)
        set(value)
        render()
        refreshAll(parent)
    end)
    UI.AttachHint(button, label, hint)
    UI.AttachTitleHint(parent, title, label, hint)
    onRefresh(parent, render)
    render()
    return button, y - 45
end

-- A number with - and + buttons and a small title above.  Shift-click steps
-- by `big` (default 5).  Returns the frame and the y below it.
function UI.Stepper(parent, label, hint, x, y, minV, maxV, get, set, big)
    local title = UI.FontString(parent, "GameFontHighlightSmall", "muted")
    title:SetPoint("TOPLEFT", x, y)
    title:SetText(label)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(96, 26)
    holder:SetPoint("TOPLEFT", x, y - 15)
    holder.hcTitle = title
    local minus = UI.Button(holder, 26, 26)
    minus:SetPoint("LEFT", 0, 0)
    local plus = UI.Button(holder, 26, 26)
    plus:SetPoint("RIGHT", 0, 0)
    minus:SetText("-")
    plus:SetText("+")
    local value = UI.FontString(holder, "GameFontHighlight")
    value:SetPoint("LEFT", minus, "RIGHT", 0, 0)
    value:SetPoint("RIGHT", plus, "LEFT", 0, 0)
    value:SetJustifyH("CENTER")
    local function render()
        local current = get()
        value:SetText(tostring(current))
        UI.SetEnabled(minus, current > minV)
        UI.SetEnabled(plus, current < maxV)
    end
    local function step(direction)
        local amount = (IsShiftKeyDown and IsShiftKeyDown()) and (big or 5) or 1
        set(math.max(minV, math.min(maxV, get() + direction * amount)))
        render()
        refreshAll(parent)
    end
    minus:SetScript("OnClick", function() step(-1) end)
    plus:SetScript("OnClick", function() step(1) end)
    UI.AttachHint(minus, label, hint)
    UI.AttachHint(plus, label, hint)
    UI.AttachTitleHint(parent, title, label, hint)
    holder.minus, holder.plus, holder.value = minus, plus, value
    onRefresh(parent, render)
    render()
    return holder, y - 45
end

-- A single-line text field that saves on Enter or when it loses focus.
function UI.TextInput(panel, label, hint, y, get, set, width, inputWidth)
    local row = UI.Row(panel, y, UI.CELL_H, label, hint, width)
    local box = CreateFrame("EditBox", nil, row, "BackdropTemplate")
    box:SetSize(math.min(inputWidth or 260, math.floor(row.hcWidth * 0.6)), 26)
    box:SetPoint("RIGHT", -UI.CELL_INSET, 0)
    fitTitle(row, box)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetTextInsets(8, 8, 0, 0)
    T.Surface(box, "field", "edge")
    local function save(self) set(self:GetText() or "") end
    box:SetScript("OnEnterPressed", function(self) save(self); self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", save)
    box:SetScript("OnEscapePressed", function(self) self:SetText(get() or ""); self:ClearFocus() end)
    UI.AttachHint(box, label, hint)
    onRefresh(panel, function()
        if not (box.HasFocus and box:HasFocus()) then box:SetText(get() or "") end
    end)
    box:SetText(get() or "")
    return row, row.hcNextY, box
end

-- ── Layout helpers ─────────────────────────────────────────────────────────

-- A section label in small capitals, as the start of a block of settings.
-- `icon` (optional) is a texture path or file ID drawn before the text, such
-- as the spell a section is about.  A function is called on every refresh,
-- for icons that depend on what the player knows.
function UI.Header(panel, text, y, icon)
    y = UI.Flush(panel, y)
    if y < -16 then y = y - 10 end
    local fs = UI.FontString(panel, "GameFontNormalSmall", "section")
    fs:SetText(tostring(text or ""):upper())
    if icon then
        local tex = panel:CreateTexture(nil, "ARTWORK")
        tex:SetSize(18, 18)
        tex:SetPoint("TOPLEFT", UI.PAD + 2, y + 3)
        if tex.SetTexCoord then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        fs.hcIcon = tex
        local function render()
            local value = resolve(icon)
            tex:SetShown(value ~= nil)
            fs:ClearAllPoints()
            if value ~= nil then
                tex:SetTexture(value)
                fs:SetPoint("LEFT", tex, "RIGHT", 6, 0)
            else
                fs:SetPoint("TOPLEFT", UI.PAD + 2, y)
            end
        end
        if type(icon) == "function" then onRefresh(panel, render) end
        render()
    else
        fs:SetPoint("TOPLEFT", UI.PAD + 2, y)
    end
    UI.RestartStripes(panel)
    return fs, y - 22
end

-- Small muted capitals above a list.
function UI.SectionLabel(panel, text, y)
    y = UI.Flush(panel, y)
    local fs = UI.FontString(panel, "GameFontDisableSmall", "muted")
    fs:SetPoint("TOPLEFT", UI.PAD + 2, y)
    fs:SetText(text)
    return fs, y - 20
end

-- A single line of body text.  Settings text never wraps.
function UI.Text(panel, text, y, role)
    y = UI.Flush(panel, y)
    local fs = UI.FontString(panel, "GameFontHighlightSmall", role or "muted")
    fs:SetPoint("TOPLEFT", UI.PAD + 2, y - 4)
    fs:SetWidth(UI.CONTENT_WIDTH)
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    fs:SetText(text)
    return fs, y - 24
end

-- A bordered card at the page's left edge; returns the card and next y.
function UI.Card(panel, y, height, width)
    y = UI.Flush(panel, y)
    local card = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    card:SetPoint("TOPLEFT", UI.PAD, y)
    card:SetSize(width or UI.CONTENT_WIDTH, height)
    T.Surface(card, "raised", "edge")
    return card, y - height - 14
end

-- Text that acts as a link: accent coloured, brighter with an underline on
-- hover.  Returns the button; its width follows the text.
function UI.Link(parent, text, onClick, template)
    local link = CreateFrame("Button", nil, parent)
    link.Text = UI.FontString(link, template or "GameFontHighlightSmall", "link")
    link.Text:SetPoint("LEFT")
    local underline = T.Fill(link:CreateTexture(nil, "ARTWORK"), "linkHover")
    underline:SetHeight(1)
    underline:SetPoint("TOPLEFT", link.Text, "BOTTOMLEFT", 0, -1)
    underline:SetPoint("TOPRIGHT", link.Text, "BOTTOMRIGHT", 0, -1)
    underline:Hide()
    link.SetText = function(self, value)
        self.Text:SetText(value or "")
        self.text = value
        local width = self.Text.GetStringWidth and self.Text:GetStringWidth() or 0
        self:SetSize(math.max(20, (width or 0) + 2), 16)
    end
    link:SetScript("OnEnter", function() T.Text(link.Text, "linkHover"); underline:Show() end)
    link:SetScript("OnLeave", function() T.Text(link.Text, "link"); underline:Hide() end)
    link:SetScript("OnClick", onClick)
    link:SetText(text)
    return link
end

-- A link that goes to another settings page, e.g. "View ignored (3)".
function UI.PageLink(panel, y, text, page)
    y = UI.Flush(panel, y)
    local link = UI.Link(panel, resolve(text), function() HC.Settings:Show(page) end, "GameFontHighlight")
    link:SetPoint("TOPLEFT", UI.PAD + 2, y - 4)
    onRefresh(panel, function() link:SetText(resolve(text)) end)
    return link, y - 28
end

-- A danger-styled button that restores one page's settings.
-- A standalone button on its own line at the page's left edge, the same
-- size and inset as the page reset, so page actions line up.
function UI.ActionButton(panel, y, text, onClick, hint, style, width)
    y = UI.Flush(panel, y)
    local button = UI.Button(panel, width or 160, 26, style)
    button:SetPoint("TOPLEFT", UI.PAD, y - 10)
    button:SetText(text)
    if hint then UI.AttachHint(button, text, hint) end
    button:SetScript("OnClick", onClick)
    return button, y - 48
end

function UI.PageReset(panel, y, reset, label)
    return UI.ActionButton(panel, y, label or "Reset page", function()
        reset()
        refreshAll(panel)
    end, "Restore the settings on this page.", "danger")
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

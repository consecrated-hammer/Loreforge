local _, ns = ...
local HC = ns.HammerCore
local Settings = HC.Settings
local GAP, RANGE, MARGIN = 8, 24, 8
local SIDES = { LEFT = true, RIGHT = true, TOP = true, BOTTOM = true }

local function scale(frame)
    local root = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local own = frame.GetEffectiveScale and frame:GetEffectiveScale() or root
    return math.max(0.001, (own or root) / math.max(0.001, root))
end

local function rect(frame)
    local left = frame.GetLeft and frame:GetLeft()
    local top = frame.GetTop and frame:GetTop()
    if type(left) ~= "number" or type(top) ~= "number" then return nil end
    local s = scale(frame)
    local width, height = frame:GetWidth() * s, frame:GetHeight() * s
    return { left = left * s, top = top * s, width = width, height = height,
        right = left * s + width, bottom = top * s - height }
end

local function clamp(value, low, high)
    return math.max(low, math.min(math.max(low, high), value))
end

-- Geometry is in UIParent units, independent of either window's own scale.
function Settings.PreviewSnapSide(p, h)
    if not p or not h then return nil end
    local candidates = {}
    if math.min(p.top, h.top) > math.max(p.bottom, h.bottom) then
        candidates[#candidates + 1] = { "LEFT", math.abs(p.right - (h.left - GAP)), p.top - h.top }
        candidates[#candidates + 1] = { "RIGHT", math.abs(p.left - (h.right + GAP)), p.top - h.top }
    end
    if math.min(p.right, h.right) > math.max(p.left, h.left) then
        candidates[#candidates + 1] = { "TOP", math.abs(p.bottom - (h.top + GAP)), p.left - h.left }
        candidates[#candidates + 1] = { "BOTTOM", math.abs(p.top - (h.bottom - GAP)), p.left - h.left }
    end
    local best
    for _, candidate in ipairs(candidates) do
        if candidate[2] <= RANGE and (not best or candidate[2] < best[2]) then best = candidate end
    end
    return best and best[1], best and best[3]
end

function Settings.PreviewDockPlan(p, h, width, height, side, offset)
    if not p or not h or not SIDES[side] or width <= 0 or height <= 0
        or p.width <= 0 or p.height <= 0 then return nil end
    offset = tonumber(offset) or 0
    local left, top
    if side == "LEFT" or side == "RIGHT" then
        local l, r = h.left - GAP - p.width, h.right + GAP
        if side == "LEFT" and l < MARGIN and r + p.width <= width - MARGIN then side = "RIGHT"
        elseif side == "RIGHT" and r + p.width > width - MARGIN and l >= MARGIN then side = "LEFT" end
        left = side == "LEFT" and l or r
        top = h.top + offset
    else
        local above, below = h.top + GAP + p.height, h.bottom - GAP
        if side == "TOP" and above > height - MARGIN and below - p.height >= MARGIN then side = "BOTTOM"
        elseif side == "BOTTOM" and below - p.height < MARGIN and above <= height - MARGIN then side = "TOP" end
        left = h.left + offset
        top = side == "TOP" and above or below
    end
    return { left = clamp(left, MARGIN, width - p.width - MARGIN),
        top = clamp(top, p.height + MARGIN, height - MARGIN), side = side }
end

function Settings:RefreshPreviewDocks()
    for _, dock in pairs(self.previewDocks or {}) do dock:Refresh() end
end

function Settings:PreviewDock(frame, opts)
    self.previewDocks = self.previewDocks or {}
    if self.previewDocks[frame] then return self.previewDocks[frame] end
    opts = opts or {}
    local dock = { frame = frame, options = opts }
    self.previewDocks[frame] = dock
    local function active()
        return not opts.isActive or opts.isActive()
    end
    local function host()
        local window = Settings.window
        return window and window:IsShown() and window or nil
    end
    local function freeHere(persist)
        local p = rect(frame)
        if not p then return end
        local s = scale(frame)
        local point = { "TOPLEFT", "TOPLEFT", p.left / s, (p.top - UIParent:GetHeight()) / s }
        frame:ClearAllPoints()
        frame:SetPoint(point[1], UIParent, point[2], point[3], point[4])
        if persist ~= false then
            dock.freePoint = point
            if opts.setPoint then opts.setPoint(point) else HC.State().previewDockPoint = point end
        end
    end
    local function freePoint()
        local point = opts.getPoint and opts.getPoint() or HC.State().previewDockPoint
        point = point or dock.freePoint
        if type(point) == "table" and type(point[1]) == "string" and type(point[2]) == "string"
            and type(point[3]) == "number" and type(point[4]) == "number" then return point end
    end
    local function restoreFree()
        local point = freePoint()
        if point then
            frame:ClearAllPoints()
            frame:SetPoint(point[1], UIParent, point[2], point[3], point[4])
        else freeHere(false) end
        dock.attached, dock.signature = false, nil
    end
    local from, relative, to, x, y = frame:GetPoint()
    if relative == UIParent then dock.freePoint = { from, to, x, y } end
    function dock:IsAttached()
        return self.attached == true and not self.dragging and active() and host() ~= nil
    end
    function dock:Refresh()
        local state, window = HC.State(), host()
        local anchoredHost = select(2, frame:GetPoint()) == Settings.window and Settings.window ~= nil
        if state.previewSnap == false then
            state.previewDockSide, state.previewDockOffset = nil, nil
            if self.attached or anchoredHost then restoreFree() end
            self.attached, self.signature = false, nil
            return
        end
        if self.dragging then return end
        if not active() or not window or not SIDES[state.previewDockSide] then
            if self.attached or anchoredHost then restoreFree() end
            return
        end
        if not frame:IsShown() then return end
        -- A steady attached window needs no rect/plan tables or signature strings.
        local hl, ht = window:GetLeft(), window:GetTop()
        local hw, hh, hs = window:GetWidth(), window:GetHeight(), scale(window)
        local pw, ph, ps = frame:GetWidth(), frame:GetHeight(), scale(frame)
        local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
        local c = self.geometry
        if self.attached and c and c.hl == hl and c.ht == ht and c.hw == hw and c.hh == hh and c.hs == hs
            and c.pw == pw and c.ph == ph and c.ps == ps and c.sw == sw and c.sh == sh
            and c.side == state.previewDockSide and c.offset == state.previewDockOffset then return end
        local p, h = rect(frame), rect(window)
        local plan = Settings.PreviewDockPlan(p, h, sw, sh,
            state.previewDockSide, state.previewDockOffset)
        if not plan then return end
        local signature = table.concat({ plan.left, plan.top, p.width, p.height, h.left, h.top, scale(frame) }, ":")
        if self.signature ~= signature or not self.attached then
            local s = scale(frame)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", window, "TOPLEFT", (plan.left - h.left) / s, (plan.top - h.top) / s)
            self.signature = signature
        end
        c = c or {}; self.geometry = c
        c.hl, c.ht, c.hw, c.hh, c.hs = hl, ht, hw, hh, hs
        c.pw, c.ph, c.ps, c.sw, c.sh = pw, ph, ps, sw, sh
        c.side, c.offset = state.previewDockSide, state.previewDockOffset
        self.attached = true
    end
    function dock:Restore()
        if not active() then return end
        self.attached, self.signature = false, nil
        restoreFree()
        self:Refresh()
    end
    function dock:BeginDrag()
        if not active() or (opts.canDrag and not opts.canDrag()) then return false end
        freeHere(false)
        self.dragging, self.attached, self.signature = true, false, nil
        frame:StartMoving()
        return true
    end
    function dock:EndDrag()
        if not self.dragging then return false end
        frame:StopMovingOrSizing()
        if frame.SetUserPlaced then frame:SetUserPlaced(false) end
        self.dragging = false
        local state, window = HC.State(), host()
        if not window then
            self.attached = false
            freeHere()
            return false
        end
        local side, offset
        if active() and window and state.previewSnap ~= false then side, offset = Settings.PreviewSnapSide(rect(frame), rect(window)) end
        state.previewDockSide, state.previewDockOffset = side, offset
        if side then self:Refresh() end
        if not side or not self.attached then
            state.previewDockSide, state.previewDockOffset = nil, nil
            self.attached = false; freeHere()
            return false
        end
        return true
    end
    frame:HookScript("OnHide", function()
        if dock.dragging then
            frame:StopMovingOrSizing()
            if frame.SetUserPlaced then frame:SetUserPlaced(false) end
            dock.dragging = false
        end
        if select(2, frame:GetPoint()) == Settings.window then restoreFree() end
        dock.attached, dock.signature = false, nil
    end)
    -- Anchors follow movement immediately. Recheck room at screen edges and
    -- changed scales/sizes without rewriting anchors on unchanged frames.
    frame:HookScript("OnUpdate", function(_, elapsed)
        if not active() or not HC.State().previewDockSide then return end
        dock.elapsed = (dock.elapsed or 0) + elapsed
        if dock.elapsed >= 0.05 then dock.elapsed = 0; dock:Refresh() end
    end)
    return dock
end

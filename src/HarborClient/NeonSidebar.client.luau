-- Visual-only sidebar. Intentionally NO remotes, purchases, windows or gameplay callbacks.
-- Source of truth: src/client/NeonSidebar.client.luau (Rojo).
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

for _, name in {"HarborUI", "HarborDashboard", "DonateButtonsUI"} do
    local previous = playerGui:FindFirstChild(name)
    if previous then previous:Destroy() end
end
-- Old custom boards/currency HUD are archived. Do not show the default stats list either.
pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false) end)

local function create(className, name, properties, parent)
    local object = Instance.new(className)
    object.Name = name
    for property, value in properties do object[property] = value end
    object.Parent = parent
    return object
end
local function corner(parent, radius)
    return create("UICorner", "RoundedCorners", {CornerRadius = radius}, parent)
end
local function gradient(parent, top, bottom, rotation, middle)
    return create("UIGradient", "SurfaceGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, top),
            ColorSequenceKeypoint.new(.50, middle or top:Lerp(bottom,.5)),
            ColorSequenceKeypoint.new(1, bottom),
        }), Rotation = rotation or 90,
    }, parent)
end
local function stroke(parent, color, thickness, transparency)
    return create("UIStroke", "NeonEdge", {
        Color = color, Thickness = thickness, Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        LineJoinMode = Enum.LineJoinMode.Round,
    }, parent)
end
-- Icon contours and surface colours follow the latest 21:08 reference.
-- All five buttons use one shared square geometry and one native vertical layout.
local ReferenceIcons = require(script.Parent.ReferenceIcons)
local white = Color3.fromRGB(250,247,255)
local function gift(parent) ReferenceIcons.draw(parent,"Shop") end
local function star(parent) ReferenceIcons.draw(parent,"Rewards") end
local function trophy(parent) ReferenceIcons.draw(parent,"Leaderboard") end
local function gear(parent) ReferenceIcons.draw(parent,"Settings") end
local function dots(parent) ReferenceIcons.draw(parent,"More") end

local gui = create("ScreenGui", "DonateButtonsUI", {
    ResetOnSpawn = false, DisplayOrder = 30, IgnoreGuiInset = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)
local menu = create("Frame", "LeftMenu", {
    AnchorPoint = Vector2.new(0, .5), Position = UDim2.fromScale(.018, .55),
    Size = UDim2.fromOffset(80, 440), BackgroundTransparency = 1,
    BorderSizePixel = 0, ClipsDescendants = false,
}, gui)
local DESIGN_SIDE = 100
local DESIGN_GAP = 12
local DESIGN_HEIGHT = DESIGN_SIDE * 5 + DESIGN_GAP * 4
local menuScale = create("UIScale", "UniformMenuScale", {Scale = 1}, menu)
local layout = create("UIListLayout", "UniformVerticalLayout", {
    FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder,
    HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Top,
    Padding = UDim.new(0, DESIGN_GAP),
}, menu)
menu.Size = UDim2.fromOffset(DESIGN_SIDE, DESIGN_HEIGHT)
local definitions = {
    {Name = "Shop", CaptionWidth = 0.4727272727272727, Top = Color3.fromRGB(162,29,161), Middle = Color3.fromRGB(104,24,148), Bottom = Color3.fromRGB(89,22,151), Accent = Color3.fromRGB(255,84,245), EdgeTop = Color3.fromRGB(255,247,255), EdgeMiddle = Color3.fromRGB(255,167,255), EdgeBottom = Color3.fromRGB(251,81,249), Gloss = Color3.fromRGB(255,72,247), GlossAlpha = 0.05, Icon = gift, Corner = .24, FontSize = 22.5, IconW = 0.5181818181818182, IconH = 0.5181818181818182},
    {Name = "Rewards", CaptionWidth = 0.740909090909091, Top = Color3.fromRGB(171,93,31), Middle = Color3.fromRGB(127,68,37), Bottom = Color3.fromRGB(87,46,31), Accent = Color3.fromRGB(255,192,46), EdgeTop = Color3.fromRGB(255,255,229), EdgeMiddle = Color3.fromRGB(255,243,143), EdgeBottom = Color3.fromRGB(255,204,62), Gloss = Color3.fromRGB(255,181,96), GlossAlpha = 0.2, Icon = star, Corner = .24, FontSize = 22.5, IconW = 0.5227272727272727, IconH = 0.5045454545454545},
    {Name = "Leaderboard", CaptionWidth = 0.8136363636363636, Top = Color3.fromRGB(89,15,198), Middle = Color3.fromRGB(54,18,166), Bottom = Color3.fromRGB(47,20,162), Accent = Color3.fromRGB(190,99,255), EdgeTop = Color3.fromRGB(255,244,255), EdgeMiddle = Color3.fromRGB(236,181,255), EdgeBottom = Color3.fromRGB(221,123,255), Gloss = Color3.fromRGB(176,102,255), GlossAlpha = 0.25, Icon = trophy, Corner = .24, FontSize = 18.5, IconW = 0.5318181818181819, IconH = 0.4636363636363636},
    {Name = "Settings", CaptionWidth = 0.6590909090909091, Top = Color3.fromRGB(28,79,207), Middle = Color3.fromRGB(14,55,164), Bottom = Color3.fromRGB(12,46,142), Accent = Color3.fromRGB(65,223,255), EdgeTop = Color3.fromRGB(235,255,255), EdgeMiddle = Color3.fromRGB(146,249,255), EdgeBottom = Color3.fromRGB(55,229,255), Gloss = Color3.fromRGB(96,173,255), GlossAlpha = 0.15, Icon = gear, Corner = .24, FontSize = 22.5, IconW = 0.4772727272727273, IconH = 0.4818181818181818},
    {Name = "More", CaptionWidth = 0.4, Top = Color3.fromRGB(87,16,180), Middle = Color3.fromRGB(61,25,150), Bottom = Color3.fromRGB(47,23,137), Accent = Color3.fromRGB(218,92,254), EdgeTop = Color3.fromRGB(255,241,255), EdgeMiddle = Color3.fromRGB(244,154,255), EdgeBottom = Color3.fromRGB(230,103,255), Gloss = Color3.fromRGB(207,93,255), GlossAlpha = 0.22, Icon = dots, Corner = .24, FontSize = 22.5, IconW = 0.41818181818181815, IconH = 0.1},
}
local connections = {}
local activeTweens = {}
local ambientTweens = {}
local slots = {}
local captionShadows = {}
local iconHolders = {}
local captions = {}
local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end
local function animate(object, duration, properties)
    if activeTweens[object] then activeTweens[object]:Cancel() end
    local tween = TweenService:Create(object, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), properties)
    activeTweens[object] = tween
    tween:Play()
end
for index, definition in definitions do
    local slot = create("Frame", definition.Name .. "Slot", {
        AnchorPoint = Vector2.zero, LayoutOrder = index,
        Size = UDim2.fromOffset(DESIGN_SIDE, DESIGN_SIDE), BackgroundTransparency = 1,
        BorderSizePixel = 0, ClipsDescendants = false,
    }, menu)
    slots[index] = slot
    local root = create("Frame", "Visual", {
        AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5),
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
    }, slot)
    local scale = create("UIScale", "InteractionScale", {Scale = 1}, root)
    local glowStrokes = {}
    -- Concentric translucent borders give an asset-free, soft neon falloff.
    local softAccent = 0
    for layer = 1, 5 do
        local glow = create("Frame", "Glow" .. layer, {
            Position = UDim2.fromOffset(-layer * 1.2, -layer * 1.2),
            Size = UDim2.new(1, layer * 2.4, 1, layer * 2.4),
            BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1,
        }, root)
        corner(glow, UDim.new(definition.Corner, 0))
        glowStrokes[layer] = stroke(glow, definition.Accent, 1.6 + layer * .60, .55 + layer * .07 + softAccent)
        gradient(glowStrokes[layer], definition.EdgeTop, definition.EdgeBottom, 60, definition.EdgeMiddle)
    end
    local shadow = create("Frame", "DepthShadow", {
        Position = UDim2.fromOffset(0, 2), Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(20, 14, 37), BackgroundTransparency = .65,
        BorderSizePixel = 0, ZIndex = 2,
    }, root)
    corner(shadow, UDim.new(definition.Corner, 0))
    stroke(shadow, Color3.fromRGB(22, 15, 38), 3, .91)
    local button = create("TextButton", definition.Name, {
        Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1),
        Text = "", AutoButtonColor = false, BorderSizePixel = 0,
        ClipsDescendants = false, ZIndex = 4, Selectable = true,
        SelectionOrder = index,
    }, root)
    corner(button, UDim.new(definition.Corner, 0))
    local fill = gradient(button, definition.Top, definition.Bottom, 90, definition.Middle)
    local edgeRest = .04
    local edge = stroke(button, definition.Accent, 2.2, edgeRest)
    gradient(edge, definition.EdgeTop, definition.EdgeBottom, 60, definition.EdgeMiddle)
    local inner = create("Frame", "InnerBevel", {
        Position = UDim2.fromOffset(1.5, 1.5), Size = UDim2.new(1, -3, 1, -3),
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5,
    }, button)
    corner(inner, UDim.new(definition.Corner, 0))
    local bevel = stroke(inner, definition.Accent, 1.2, .66)
    local gloss = create("Frame", "TopGloss", {
        Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = white, BackgroundTransparency = .94, BorderSizePixel = 0, ZIndex = 6,
    }, button)
    corner(gloss, UDim.new(definition.Corner, 0))
    create("UIGradient", "GlossFade", {
        Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)}), Rotation = 45,
    }, gloss)
    local icon = create("Frame", "Icon", {
        AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .40),
        Size = UDim2.fromScale(definition.IconW, definition.IconH), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 8,
    }, button)
    iconHolders[index] = icon
    definition.Icon(icon, definition.Accent)
    local caption = create("TextLabel", "Caption", {
        AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .82),
        Size = UDim2.fromScale(.96, .26), BackgroundTransparency = 1,
        Text = definition.Name, TextColor3 = white, TextScaled = false, TextSize = definition.FontSize,
        TextWrapped = false, Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
        TextStrokeColor3 = Color3.fromRGB(13, 6, 28), TextStrokeTransparency = .85,
        ZIndex = 10,
    }, button)
    -- Match the reference word width using native font metrics; never clip a long caption.
    local word = TextService:GetTextSize(definition.Name, 100, Enum.Font.GothamBold, Vector2.new(4096,256))
    caption.TextSize = DESIGN_SIDE * definition.CaptionWidth * 100 / math.max(1,word.X)
    create("UITextSizeConstraint", "CaptionSize", {MinTextSize = 8, MaxTextSize = 24}, caption)
    captions[index] = caption
    local captionShadow = caption:Clone()
    captionShadow.Name = "CaptionShadow"
    captionShadow.TextColor3 = Color3.fromRGB(5, 3, 16)
    captionShadow.TextTransparency = .65
    captionShadow.TextStrokeTransparency = 1
    captionShadow.Position = caption.Position + UDim2.fromOffset(0, .65)
    captionShadow.ZIndex = 9
    captionShadow.Parent = button
    captionShadows[index] = captionShadow
    -- Native repeating tween, no Lua/per-frame loop. Only Thickness is pulsed;
    -- interaction tweens own Transparency, so the animations cannot fight.
    local outerHalo = glowStrokes[5]
    local pulse = TweenService:Create(outerHalo,
        TweenInfo.new(2.8 + index * .13, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {Thickness = outerHalo.Thickness + .85})
    table.insert(ambientTweens, pulse)
    pulse:Play()
    local hovering, selected, pressed = false, false, false
    local pressRevision = 0
    local function refresh()
        local focused = hovering or selected
        animate(scale, pressed and .075 or .21, {Scale = pressed and .945 or focused and 1.06 or 1})
        animate(edge, .18, {Transparency = focused and math.max(0,edgeRest-.15) or edgeRest, Thickness = focused and 2.8 or 2.2})
        animate(bevel, .20, {Transparency = focused and .46 or .66})
        animate(button, .22, {BackgroundColor3 = pressed and Color3.fromRGB(207, 202, 224)
            or Color3.new(1, 1, 1)})
        animate(fill, .28, {Offset = focused and Vector2.new(0, -.085) or Vector2.zero, Rotation = focused and 82 or 90})
        animate(gloss, .20, {BackgroundTransparency = focused and .87 or .94})
        animate(shadow, .16, {Position = UDim2.fromOffset(0, pressed and 1 or 2),
            BackgroundTransparency = pressed and .75 or .65})
        for layer, halo in glowStrokes do
            animate(halo, .23, {Transparency = focused and (.27 + layer * .095 + softAccent)
                or (.55 + layer * .07 + softAccent)})
        end
    end
    local function release()
        pressRevision += 1
        pressed = false
        refresh()
    end
    connect(button.MouseEnter, function()
        if UserInputService.MouseEnabled and UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch then
            hovering = true;refresh()
        end
    end)
    connect(button.MouseLeave, function() hovering = false;release() end)
    connect(button.SelectionGained, function() selected = true;refresh() end)
    connect(button.SelectionLost, function() selected = false;release() end)
    connect(button.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if input.UserInputType == Enum.UserInputType.Touch then hovering = false;selected = false end
            pressRevision += 1;pressed = true;refresh()
        end
    end)
    connect(button.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then release() end
    end)
    connect(UserInputService.InputEnded, function(input)
        if pressed and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then release() end
    end)
    connect(UserInputService.WindowFocusReleased, function() hovering = false;selected = false;release() end)
    -- Mouse/touch already animate through press/release. Do NOT run a second click pulse.
    -- Gamepad/keyboard activation gets one guarded visual pulse, never a game action.
    connect(button.Activated, function(input)
        if input and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then return end
        pressRevision += 1
        local revision = pressRevision
        pressed = true;refresh()
        task.delay(.10, function()
            if button.Parent and pressRevision == revision then release() end
        end)
    end)
end
-- One layout and one scale own the whole stack. No per-button size/position formulas.
local layoutRevision = 0
local function resize()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    local insetTop, insetBottom = GuiService:GetGuiInset()
    local safeHeight = math.max(1, viewport.Y - insetTop.Y - insetBottom.Y)
    local safeWidth = math.max(1, viewport.X - insetTop.X - insetBottom.X)
    local side = math.min(safeHeight * .158, safeWidth * .21, 180)
    local fit = math.max(.01, math.min(side / DESIGN_SIDE,
        (safeHeight - 28) / DESIGN_HEIGHT, (safeWidth - 28) / 120))
    menuScale.Scale = fit
    local half = DESIGN_HEIGHT * fit * .5 + 12
    local center = math.clamp(safeHeight * .52, half, math.max(half, safeHeight - half))
    menu.Position = UDim2.new(.018, 4, 0, center)
    -- Check actual Studio geometry once after layout settles, not in a render loop.
    layoutRevision += 1
    local revision = layoutRevision
    task.delay(.15, function()
        if not gui.Parent or revision ~= layoutRevision then return end
        local first = slots[1]
        local size = first.AbsoluteSize
        if size.X < 1 then return end
        local centerX = first.AbsolutePosition.X + size.X * .5
        local expectedGap = slots[2].AbsolutePosition.Y - first.AbsolutePosition.Y - size.Y
        local valid = math.abs(size.X-size.Y) < .75
        for index, slot in slots do
            valid = valid and math.abs(slot.AbsoluteSize.X-size.X) < .75
                and math.abs(slot.AbsoluteSize.Y-size.Y) < .75
                and math.abs(slot.AbsolutePosition.X + slot.AbsoluteSize.X*.5-centerX) < .75
            if index > 1 then
                local previous = slots[index-1]
                local actualGap = slot.AbsolutePosition.Y-previous.AbsolutePosition.Y-previous.AbsoluteSize.Y
                valid = valid and math.abs(actualGap-expectedGap) < .75
            end
        end
        if valid then
            print(string.format("[NeonSidebar] Alignment verified: 5 equal squares; side=%.2f; gap=%.2f",size.X,expectedGap))
        else
            warn("[NeonSidebar] Alignment check failed; inspect UIListLayout")
        end
    end)
end
local cameraConnection
local function bindCamera()
    if cameraConnection then cameraConnection:Disconnect() end
    if Workspace.CurrentCamera then
        cameraConnection = Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
    end
    resize()
end
connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), bindCamera)
connect(gui.Destroying, function()
    if cameraConnection then cameraConnection:Disconnect() end
    for _, connection in connections do connection:Disconnect() end
    for _, tween in activeTweens do tween:Cancel() end
    for _, tween in ambientTweens do tween:Cancel() end
end)
bindCamera()
print("[NeonSidebar] Latest reference ready: 5 equal native buttons; visual only")

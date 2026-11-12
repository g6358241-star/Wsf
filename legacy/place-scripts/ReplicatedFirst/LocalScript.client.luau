-- LocalScript в ReplicatedFirst
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

-- ⚙️ НАСТРОЙКИ
local GAME_TITLE = "МОЯ ИГРА"
local SUBTITLE = "by YourStudio"
local MIN_DURATION = 4 -- минимум секунд показа заставки
local ACCENT = Color3.fromRGB(255, 200, 60)

local startTime = os.clock()
ReplicatedFirst:RemoveDefaultLoadingScreen()
pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local function make(className, props, parent)
	local obj = Instance.new(className)
	for k, v in pairs(props) do obj[k] = v end
	obj.Parent = parent
	return obj
end

local function tween(obj, time, props, style, dir)
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- 🖼️ ИНТЕРФЕЙС
local gui = make("ScreenGui", {Name = "IntroScreen", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 1000}, playerGui)
local root = make("CanvasGroup", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0}, gui)

local bgGradient = make("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 10, 35)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(70, 25, 110)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 40, 80)),
	}),
}, root)

-- Название
local title = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.8, 0.15),
	BackgroundTransparency = 1, Text = GAME_TITLE, Font = Enum.Font.GothamBlack, TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1), TextTransparency = 1,
}, root)
local titleStroke = make("UIStroke", {Color = ACCENT, Thickness = 3, Transparency = 1}, title)
local titleScale = make("UIScale", {Scale = 0.6}, title)
local shine = make("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.5, ACCENT),
		ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
	}),
	Offset = Vector2.new(-1, 0),
}, title)

-- Подзаголовок
local subtitle = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.54), Size = UDim2.fromScale(0.6, 0.05),
	BackgroundTransparency = 1, Text = SUBTITLE, Font = Enum.Font.GothamMedium, TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1), TextTransparency = 1,
}, root)

-- Прыгающие точки
local dotsHolder = make("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.72), Size = UDim2.fromOffset(80, 30), BackgroundTransparency = 1}, root)
for i = 1, 3 do
	local dot = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, (i - 1) * 30 + 10, 0.5, 0),
		Size = UDim2.fromOffset(12, 12), BackgroundColor3 = ACCENT, BorderSizePixel = 0,
	}, dotsHolder)
	make("UICorner", {CornerRadius = UDim.new(1, 0)}, dot)
	task.delay((i - 1) * 0.15, function()
		TweenService:Create(dot, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{Position = dot.Position - UDim2.fromOffset(0, 10)}):Play()
	end)
end

-- Полоса загрузки
local barBg = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.8), Size = UDim2.new(0.4, 0, 0, 8),
	BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.8, BorderSizePixel = 0,
}, root)
make("UICorner", {CornerRadius = UDim.new(1, 0)}, barBg)
local barFill = make("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = ACCENT, BorderSizePixel = 0}, barBg)
make("UICorner", {CornerRadius = UDim.new(1, 0)}, barFill)
local percent = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.8, 14), Size = UDim2.fromOffset(200, 24),
	BackgroundTransparency = 1, Text = "0%", Font = Enum.Font.GothamBold, TextSize = 18,
	TextColor3 = Color3.new(1, 1, 1), TextTransparency = 0.3,
}, root)

-- 🎬 АНИМАЦИЯ ПОЯВЛЕНИЯ
local bgConn = RunService.RenderStepped:Connect(function(dt)
	bgGradient.Rotation = (bgGradient.Rotation + dt * 25) % 360
end)

tween(title, 1, {TextTransparency = 0})
tween(titleStroke, 1, {Transparency = 0})
tween(titleScale, 1.2, {Scale = 1}, Enum.EasingStyle.Back)
task.delay(0.6, function() tween(subtitle, 0.8, {TextTransparency = 0.2}) end)
TweenService:Create(shine, TweenInfo.new(1.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false, 1),
	{Offset = Vector2.new(1, 0)}):Play()

-- ⏳ ЗАГРУЗКА
if not game:IsLoaded() then game.Loaded:Wait() end

local assets = workspace:GetDescendants()
local total = #assets
local BATCH = 25
for i = 1, total, BATCH do
	local batch = {}
	for j = i, math.min(i + BATCH - 1, total) do
		table.insert(batch, assets[j])
	end
	ContentProvider:PreloadAsync(batch)
	local progress = math.min(i + BATCH - 1, total) / total
	tween(barFill, 0.2, {Size = UDim2.fromScale(progress, 1)})
	percent.Text = math.floor(progress * 100) .. "%"
end

tween(barFill, 0.3, {Size = UDim2.fromScale(1, 1)})
percent.Text = "100%"

local elapsed = os.clock() - startTime
if elapsed < MIN_DURATION then task.wait(MIN_DURATION - elapsed) end

-- 🌅 ИСЧЕЗНОВЕНИЕ
tween(titleScale, 0.6, {Scale = 1.3}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
tween(root, 0.8, {GroupTransparency = 1}).Completed:Wait()

bgConn:Disconnect()
gui:Destroy()
pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true) end)

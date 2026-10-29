--[[
	MM2 Coin Tracker v2 (Luau, XENO)
	Источник: PlayerGui.MainGUI.Game.CoinBags.Container.<Bag>...Coins (путь подтверждён для мешка Candy).
	Insert - скрыть/показать GUI. UNBIND - полная остановка.
]]

local env = (typeof(getgenv) == "function" and getgenv()) or _G
if type(env.__MM2CT) == "table" and type(env.__MM2CT.stop) == "function" then
	pcall(env.__MM2CT.stop)
end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

repeat task.wait() until Players.LocalPlayer
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 15)
if not playerGui then return end

-- ========== Палитра ==========
local BG = Color3.fromRGB(17, 15, 25)
local BAR = Color3.fromRGB(27, 22, 42)
local BG2 = Color3.fromRGB(36, 30, 56)
local PURPLE = Color3.fromRGB(140, 82, 255)
local PURPLE_L = Color3.fromRGB(190, 150, 255)
local WHITE = Color3.fromRGB(240, 236, 252)
local MUTED = Color3.fromRGB(140, 130, 170)
local GREEN = Color3.fromRGB(90, 220, 130)
local AMBER = Color3.fromRGB(255, 190, 70)

-- ========== Состояние ==========
local alive = true
local conns = {}
local bags, order = {}, {} -- имя мешка -> запись; порядок
local current, pinned, sel = nil, false, 0
local lastReset = -100
local sig = {}
local WEIGHT = { endText = 1, teleport = 1, labelDrop = 1, respawn = 0.5 }
local FULL_AT = 50 -- порог FULL-RESET
local fullReset, fullBusy = false, false
local deathConn

local function track(c)
	if c then conns[#conns + 1] = c end
	return c
end

-- ========== Хелперы ==========
local function parseNumber(t)
	if type(t) ~= "string" then return nil end
	t = t:gsub("<[^>]->", ""):gsub(",", "")
	local a, b = t:match("^[^%w]*(%d+)%s*/%s*(%d+)[^%w]*$")
	if a then return tonumber(a), tonumber(b) end
	local n = t:match("^[^%w]*[xX]?%s*(%d+)[^%w]*$")
	if n then return tonumber(n), nil end
	return nil
end

local function isShown(o)
	local cur = o
	while cur and cur ~= playerGui do
		if cur:IsA("GuiObject") and not cur.Visible then return false end
		if cur:IsA("LayerCollector") and not cur.Enabled then return false end
		cur = cur.Parent
	end
	return cur == playerGui
end

local function isEndText(s)
	return s:find("%f[%a]wins?%f[%A]") or s:find("%f[%a]won%f[%A]")
		or s:find("victory", 1, true) or s:find("defeat", 1, true)
		or s:find("you lose", 1, true) or s:find("game over", 1, true)
		or s:find("round over", 1, true)
end

local function getContainer()
	local m = playerGui:FindFirstChild("MainGUI")
	local g = m and m:FindFirstChild("Game")
	local cb = g and g:FindFirstChild("CoinBags")
	return cb and cb:FindFirstChild("Container")
end

local function findCounter(bag)
	local l = bag:FindFirstChild("Coins", true)
	if l and l:IsA("TextLabel") then return l end
	return nil
end

-- лимит: ищем "n/m" или метки с именем max/limit внутри мешка (если игра их показывает)
local function findLimit(bag)
	for _, o in ipairs(bag:GetDescendants()) do
		if o:IsA("TextLabel") or o:IsA("TextButton") then
			local _, b = parseNumber(o.Text)
			if b and b >= 1 and b <= 500 then return b end
			local n = o.Name:lower()
			if n:find("max", 1, true) or n:find("limit", 1, true) then
				local v = parseNumber(o.Text)
				if v and v >= 1 and v <= 500 then return v end
			end
		end
	end
	return nil
end

-- ========== GUI ==========
local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local function tw(o, t, props, style, dir)
	TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props):Play()
end

local function pickParent()
	local ok, h = pcall(function()
		if typeof(gethui) == "function" then return gethui() end
	end)
	if ok and typeof(h) == "Instance" then return h end
	local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
	if ok2 and cg then
		local t = Instance.new("Folder")
		local ok3 = pcall(function() t.Parent = cg end)
		t:Destroy()
		if ok3 then return cg end
	end
	return playerGui
end

local FONT = Enum.Font.GothamBold
local gui = make("ScreenGui", {
	Name = "MM2CT_" .. math.random(100000, 999999),
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 999,
}, nil)
if not pcall(function() gui.Parent = pickParent() end) then
	gui.Parent = playerGui
end

local root = make("CanvasGroup", {
	Name = "Root", Size = UDim2.fromOffset(240, 218), Position = UDim2.new(0, 24, 0.4, 0),
	BackgroundColor3 = BG, BorderSizePixel = 0, GroupTransparency = 1,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, root)
make("UIStroke", { Color = PURPLE, Thickness = 1.5, Transparency = 0.3 }, root)
local scale = make("UIScale", { Scale = 0.92 }, root)

local bar = make("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = BAR, BorderSizePixel = 0 }, root)
make("TextLabel", {
	Size = UDim2.new(1, -50, 1, 0), Position = UDim2.fromOffset(14, 0), BackgroundTransparency = 1,
	Text = "MM2 COIN TRACKER", Font = FONT, TextSize = 12, TextColor3 = PURPLE_L,
	TextXAlignment = Enum.TextXAlignment.Left,
}, bar)
local minBtn = make("TextButton", {
	Size = UDim2.fromOffset(28, 22), Position = UDim2.new(1, -36, 0, 5), BackgroundColor3 = BG2,
	Text = "—", Font = FONT, TextSize = 14, TextColor3 = MUTED, BorderSizePixel = 0,
}, bar)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, minBtn)

local captionLabel = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 40), BackgroundTransparency = 1,
	Text = "COINS COLLECTED", Font = FONT, TextSize = 11, TextColor3 = MUTED,
}, root)
local numLabel = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 80), Size = UDim2.new(1, 0, 0, 48),
	BackgroundTransparency = 1, Text = "0", Font = FONT, TextSize = 40, TextColor3 = WHITE,
}, root)
local numScale = make("UIScale", { Scale = 1 }, numLabel)
local limitLabel = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 106), BackgroundTransparency = 1,
	Text = "LIMIT: —", Font = FONT, TextSize = 11, TextColor3 = MUTED,
}, root)

local dot = make("Frame", {
	Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(16, 131), BackgroundColor3 = AMBER, BorderSizePixel = 0,
}, root)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
local statusLabel = make("TextLabel", {
	Size = UDim2.fromOffset(110, 20), Position = UDim2.fromOffset(30, 125), BackgroundTransparency = 1,
	Text = "SEARCHING", Font = FONT, TextSize = 11, TextColor3 = AMBER, TextXAlignment = Enum.TextXAlignment.Left,
}, root)
local bagBtn = make("TextButton", {
	Size = UDim2.fromOffset(88, 20), Position = UDim2.new(1, -102, 0, 125), BackgroundColor3 = BG2,
	Text = "AUTO: —", Font = FONT, TextSize = 9, TextColor3 = PURPLE_L, BorderSizePixel = 0,
	TextTruncate = Enum.TextTruncate.AtEnd,
}, root)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, bagBtn)

local fullBtn = make("TextButton", {
	Size = UDim2.fromOffset(212, 24), Position = UDim2.fromOffset(14, 152), BackgroundColor3 = BG2,
	Text = "FULL-RESET: OFF", Font = FONT, TextSize = 11, TextColor3 = MUTED, BorderSizePixel = 0,
}, root)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, fullBtn)

local unbindBtn = make("TextButton", {
	Size = UDim2.fromOffset(212, 28), Position = UDim2.fromOffset(14, 184), BackgroundColor3 = PURPLE,
	Text = "UNBIND", Font = FONT, TextSize = 12, TextColor3 = WHITE, BorderSizePixel = 0,
}, root)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, unbindBtn)

-- ========== Отрисовка ==========
local function render()
	local r = current and bags[current]
	numLabel.Text = tostring(r and r.collected or 0)
	limitLabel.Text = (r and r.limit) and ("LIMIT: " .. r.limit) or "LIMIT: —"
	captionLabel.Text = current and (current:upper() .. " COLLECTED") or "COINS COLLECTED"
	bagBtn.Text = (pinned and "BAG: " or "AUTO: ") .. (current and current:upper() or "—")
end

local function pop()
	tw(numScale, 0.1, { Scale = 1.3 })
	numLabel.TextColor3 = PURPLE_L
	task.delay(0.1, function()
		if not alive then return end
		tw(numScale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
		tw(numLabel, 0.3, { TextColor3 = WHITE })
	end)
end

local function setStatus(text, color)
	statusLabel.Text = text
	statusLabel.TextColor3 = color
	dot.BackgroundColor3 = color
end

local function refreshStatus()
	for _, r in pairs(bags) do
		if r.label then setStatus("TRACKING", GREEN) return end
	end
	setStatus("SEARCHING", AMBER)
end

local function anyCollected()
	for _, r in pairs(bags) do
		if r.collected > 0 then return true end
	end
	return false
end

-- ========== Сброс раунда ==========
local function doReset()
	for _, r in pairs(bags) do
		r.collected = 0
		r.afterReset = true
	end
	lastReset = os.clock()
	sig = {}
	render()
	pop()
end

-- обнуление после смерти (намеренное, без самокоррекции по игровому счётчику)
local function resetOnDeath()
	for _, r in pairs(bags) do
		r.collected = 0
		r.afterReset = false
		r.dropped = true -- дальше считаем только новый прирост
	end
	sig = {}
	render()
	pop()
end

-- FULL-RESET: сброс персонажа при достижении FULL_AT монет
local function triggerFullReset()
	fullBusy = true
	task.delay(0.4, function()
		if not alive or not fullReset then
			fullBusy = false
			return
		end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			pcall(function() hum.Health = 0 end)
		end
		resetOnDeath()
		task.delay(5, function() fullBusy = false end)
	end)
end

local function signal(kind)
	local now = os.clock()
	if now - lastReset < 20 then return end -- защита от повторного сброса
	sig[kind] = now
	local sum = 0
	for k, t in pairs(sig) do
		if now - t <= 12 then sum += (WEIGHT[k] or 0) end
	end
	if sum >= 2 and anyCollected() then doReset() end
end

-- ========== Счётчики мешков ==========
local function onText(rec)
	local l = rec.label
	if not l then return end
	local v, m = parseNumber(l.Text)
	if not v then return end
	if m and m >= 1 and m <= 500 then rec.limit = m end
	local d = v - rec.last
	rec.last = v
	if d < 0 then
		rec.dropped = true
		rec.afterReset = false
		signal("labelDrop")
	elseif d > 0 then
		if rec.dropped then
			rec.collected = math.min(rec.collected, v - d) -- игра обнулила счётчик = новый раунд
			rec.dropped = false
		elseif rec.afterReset then
			rec.collected = v - d -- ложный сброс: возвращаемся к значению игры
		end
		rec.afterReset = false
		rec.collected += d
		if not pinned then current = rec.name end
		render()
		if current == rec.name then pop() end
		if fullReset and not fullBusy and current == rec.name and rec.collected >= FULL_AT then
			triggerFullReset()
		end
	end
end

local function bind(rec, lbl)
	if rec.conn then rec.conn:Disconnect(); rec.conn = nil end
	rec.label = lbl
	if not lbl then return end
	local v, m = parseNumber(lbl.Text)
	v = v or 0
	rec.last = v
	rec.dropped = false
	rec.afterReset = false
	if v <= 100 then -- большие значения считаем общим итогом, а не раундом
		if v > rec.collected then
			rec.collected = v
		elseif v < rec.collected then
			rec.dropped = true
		end
	end
	rec.limit = m or findLimit(rec.bag) or rec.limit
	rec.conn = lbl:GetPropertyChangedSignal("Text"):Connect(function() onText(rec) end)
end

local function syncBags()
	local c = getContainer()
	if c then
		for _, bag in ipairs(c:GetChildren()) do
			if bag:IsA("GuiObject") then
				local lbl = findCounter(bag)
				if lbl then
					local rec = bags[bag.Name]
					if not rec then
						rec = { name = bag.Name, collected = 0, last = 0, dropped = false, afterReset = false }
						bags[bag.Name] = rec
						order[#order + 1] = bag.Name
						if not current then current = bag.Name end
					end
					rec.bag = bag
					if rec.label ~= lbl then
						bind(rec, lbl)
						render()
					end
					if not rec.limit and os.clock() - (rec.limitT or 0) > 3 then
						rec.limitT = os.clock()
						rec.limit = findLimit(bag)
						if rec.limit then render() end
					end
				end
			end
		end
	end
	for _, rec in pairs(bags) do
		if rec.label and not rec.label:IsDescendantOf(playerGui) then bind(rec, nil) end
	end
	refreshStatus()
end

-- ========== Видимость / сворачивание / drag ==========
local shown = true
local function setShown(v)
	shown = v
	if v then
		root.Visible = true
		tw(root, 0.25, { GroupTransparency = 0 })
		tw(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	else
		tw(root, 0.2, { GroupTransparency = 1 })
		tw(scale, 0.2, { Scale = 0.92 })
		task.delay(0.22, function()
			if alive and not shown then root.Visible = false end
		end)
	end
end

local collapsed = false
track(minBtn.MouseButton1Click:Connect(function()
	collapsed = not collapsed
	tw(root, 0.2, { Size = UDim2.fromOffset(240, collapsed and 32 or 218) })
end))

local dragging, dragStart, startPos
track(bar.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		dragging, dragStart, startPos = true, i.Position, root.Position
	end
end))
track(UIS.InputChanged:Connect(function(i)
	if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
		local d = i.Position - dragStart
		root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end
end))
track(UIS.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end))

track(UIS.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Insert then
		setShown(not shown)
	end
end))

track(bagBtn.MouseButton1Click:Connect(function()
	if #order == 0 then return end
	sel = (sel + 1) % (#order + 1) -- 0 = AUTO
	if sel == 0 then
		pinned = false
	else
		pinned = true
		current = order[sel]
	end
	render()
end))

local function renderFull()
	fullBtn.Text = fullReset and ("FULL-RESET: ON (" .. FULL_AT .. ")") or "FULL-RESET: OFF"
	fullBtn.BackgroundColor3 = fullReset and PURPLE or BG2
	fullBtn.TextColor3 = fullReset and WHITE or MUTED
end
track(fullBtn.MouseButton1Click:Connect(function()
	fullReset = not fullReset
	renderFull()
	local r = current and bags[current]
	if fullReset and r and r.collected >= FULL_AT and not fullBusy then
		triggerFullReset()
	end
end))
renderFull()

-- ========== Остановка ==========
local function stop()
	if not alive then return end
	alive = false
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	table.clear(conns)
	for _, r in pairs(bags) do
		if r.conn then pcall(function() r.conn:Disconnect() end); r.conn = nil end
	end
	if deathConn then pcall(function() deathConn:Disconnect() end); deathConn = nil end
	if env.__MM2CT and env.__MM2CT.stop == stop then env.__MM2CT = nil end
	pcall(function()
		tw(root, 0.2, { GroupTransparency = 1 })
		tw(scale, 0.2, { Scale = 0.9 })
	end)
	task.delay(0.25, function() pcall(function() gui:Destroy() end) end)
end
track(unbindBtn.MouseButton1Click:Connect(stop))
env.__MM2CT = { stop = stop }

-- ========== Сигналы конца раунда ==========
local prevPos

local function watchCharacter(char)
	if deathConn then deathConn:Disconnect(); deathConn = nil end
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
	if not hum or not alive or player.Character ~= char then return end
	deathConn = hum.Died:Connect(function()
		fullBusy = false
		resetOnDeath() -- после смерти счётчик обнуляется
	end)
end

track(player.CharacterAdded:Connect(function(char)
	prevPos = nil
	signal("respawn")
	task.spawn(watchCharacter, char)
end))
if player.Character then task.spawn(watchCharacter, player.Character) end

task.spawn(function()
	local a1, a2 = 1, 0
	local prevEnd, endInit = {}, false
	while alive do
		local dt = task.wait(0.25)
		if not alive then break end
		a1 += dt; a2 += dt
		pcall(function()
			-- телепорт (лобби <-> карта)
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local pos = hrp.Position
				if prevPos and (pos - prevPos).Magnitude > 80 then signal("teleport") end
				prevPos = pos
			else
				prevPos = nil
			end

			if a1 >= 1 then
				a1 = 0
				syncBags()
			end

			if a2 >= 1.5 then
				a2 = 0
				if anyCollected() or not endInit then
					local now = {}
					for _, o in ipairs(playerGui:GetDescendants()) do
						if o.ClassName == "TextLabel" and #o.Text > 0 and #o.Text < 60 and not o:IsDescendantOf(gui) then
							if isEndText(o.Text:lower()) and isShown(o) then now[o] = true end
						end
					end
					if endInit then
						for o in pairs(now) do
							if not prevEnd[o] then signal("endText") break end
						end
					end
					prevEnd, endInit = now, true
				end
			end
		end)
	end
end)

render()
root.Visible = true
setShown(true)

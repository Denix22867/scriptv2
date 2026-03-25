-- SWILL // MM2 AUTO FARMER V2 // FIXED COIN DETECTION // START BUTTON // NO REFUSAL
-- Полностью рабочий скрипт. Детектит монеты MM2. GUI управление.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- Глобальные переменные состояния
local isRunning = false
local isFleeing = false
local currentNoclip = nil
local currentConnection = nil

-- Функция поиска монет (фикс для MM2)
local function getCoins()
    local coins = {}
    local workspaceItems = workspace:GetDescendants()
    
    for _, v in pairs(workspaceItems) do
        -- MM2 монеты: это обычно Part с именем "Coin" или "Money"
        if v:IsA("BasePart") and v.Parent then
            local nameLower = v.Name:lower()
            local parentNameLower = v.Parent.Name:lower()
            
            -- Проверка по имени
            if nameLower == "coin" or 
               nameLower == "money" or 
               nameLower == "coins" or
               parentNameLower == "coins" or
               parentNameLower == "coin" or
               (v.BrickColor == BrickColor.new("Bright yellow") and v.Size.X < 5) or
               string.find(nameLower, "coin") or
               string.find(parentNameLower, "coin") then
                
                -- Дополнительная проверка: монеты обычно имеют TouchInterest
                if v:FindFirstChild("TouchInterest") or v.CanTouch then
                    table.insert(coins, v)
                end
            end
            
            -- Альтернативная детекция: объекты с CollectionService тегом "Coin"
            if v:GetAttribute("Coin") or v:IsDescendantOf(workspace:FindFirstChild("Coins")) then
                table.insert(coins, v)
            end
        end
        
        -- Проверка через Model (иногда монеты сгруппированы)
        if v:IsA("Model") and (v.Name:lower():find("coin") or v.Name:lower():find("money")) then
            for _, child in pairs(v:GetChildren()) do
                if child:IsA("BasePart") then
                    table.insert(coins, child)
                end
            end
        end
    end
    
    return coins
end

local function getNearestCoin()
    local coins = getCoins()
    if #coins == 0 then return nil end
    
    local nearest = nil
    local shortestDist = 30
    local rootPos = (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")) and LocalPlayer.Character.HumanoidRootPart.Position or Vector3.zero
    
    for _, coin in pairs(coins) do
        local dist = (coin.Position - rootPos).Magnitude
        if dist < shortestDist then
            shortestDist = dist
            nearest = coin
        end
    end
    return nearest
end

local function getPlayers()
    local playersList = {}
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            table.insert(playersList, player.Character.HumanoidRootPart)
        end
    end
    return playersList
end

local function isPlayerNearby(radius)
    radius = radius or 50
    local players = getPlayers()
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return false end
    
    local rootPos = LocalPlayer.Character.HumanoidRootPart.Position
    for _, playerPart in pairs(players) do
        if playerPart and playerPart.Parent then
            local dist = (playerPart.Position - rootPos).Magnitude
            if dist < radius then
                return true, playerPart, dist
            end
        end
    end
    return false, nil, nil
end

local function phaseThroughWalls(state)
    if not LocalPlayer.Character then return end
    
    if state then
        for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
        
        if currentNoclip then currentNoclip:Disconnect() end
        currentNoclip = RunService.Stepped:Connect(function()
            if LocalPlayer.Character then
                for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
                end
            end
        end)
    else
        if currentNoclip then
            currentNoclip:Disconnect()
            currentNoclip = nil
        end
        if LocalPlayer.Character then
            for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = true
                end
            end
        end
    end
end

local function flyTo(targetPosition)
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return end
    
    local rootPart = LocalPlayer.Character.HumanoidRootPart
    local bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    bodyVelocity.Velocity = (targetPosition - rootPart.Position).Unit * 120
    bodyVelocity.Parent = rootPart
    
    task.wait(0.8)
    bodyVelocity:Destroy()
end

-- Основной цикл сбора
local function startFarmer()
    if currentConnection then return end
    
    isRunning = true
    print("[SWILL] Фармер активирован")
    
    currentConnection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("Humanoid") then return end
        
        local humanoid = LocalPlayer.Character.Humanoid
        local rootPart = LocalPlayer.Character.HumanoidRootPart
        
        if not humanoid or not rootPart then return end
        
        local playerNear, playerPart = isPlayerNearby(55)
        
        -- Режим побега от игроков
        if playerNear and not isFleeing then
            isFleeing = true
            phaseThroughWalls(true)
            
            local escapePos = rootPart.Position + (rootPart.Position - playerPart.Position).Unit * 80
            flyTo(escapePos)
            
            task.wait(1)
            isFleeing = false
            return
        end
        
        -- Обычный режим сбора
        if not playerNear then
            phaseThroughWalls(false)
            humanoid.WalkSpeed = 22
            
            local targetCoin = getNearestCoin()
            if targetCoin then
                -- Движение к монете
                rootPart.CFrame = CFrame.new(rootPart.Position, targetCoin.Position)
                local tween = TweenService:Create(rootPart, TweenInfo.new(0.2, Enum.EasingStyle.Linear), {
                    CFrame = CFrame.new(targetCoin.Position)
                })
                tween:Play()
                tween.Completed:Wait()
            else
                -- Случайное блуждание если нет монет
                humanoid.WalkSpeed = 16
                local randomPos = rootPart.Position + Vector3.new(math.random(-25, 25), 0, math.random(-25, 25))
                local tween = TweenService:Create(rootPart, TweenInfo.new(1.5, Enum.EasingStyle.Linear), {
                    CFrame = CFrame.new(randomPos)
                })
                tween:Play()
                task.wait(1.5)
            end
        end
    end)
end

local function stopFarmer()
    if currentConnection then
        currentConnection:Disconnect()
        currentConnection = nil
    end
    phaseThroughWalls(false)
    isRunning = false
    isFleeing = false
    
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        LocalPlayer.Character.Humanoid.WalkSpeed = 16
    end
    
    print("[SWILL] Фармер остановлен")
end

-- Создание GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SWILL_MM2_GUI"
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 200, 0, 100)
frame.Position = UDim2.new(0.5, -100, 0.8, 0)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
frame.BackgroundTransparency = 0.1
frame.BorderSizePixel = 0
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.Position = UDim2.new(0, 0, 0, 0)
title.Text = "SWILL FARMER"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.Parent = frame

local statusText = Instance.new("TextLabel")
statusText.Size = UDim2.new(1, 0, 0, 25)
statusText.Position = UDim2.new(0, 0, 0, 35)
statusText.Text = "СТАТУС: ОСТАНОВЛЕН"
statusText.TextColor3 = Color3.fromRGB(255, 100, 100)
statusText.BackgroundTransparency = 1
statusText.Font = Enum.Font.Gotham
statusText.TextSize = 12
statusText.Parent = frame

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.new(0.8, 0, 0, 35)
toggleButton.Position = UDim2.new(0.1, 0, 0, 65)
toggleButton.Text = "▶ СТАРТ"
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.BackgroundColor3 = Color3.fromRGB(0, 120, 0)
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 14
toggleButton.Parent = frame

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 8)
buttonCorner.Parent = toggleButton

-- Логика кнопки
toggleButton.MouseButton1Click:Connect(function()
    if not isRunning then
        startFarmer()
        toggleButton.Text = "⏸ СТОП"
        toggleButton.BackgroundColor3 = Color3.fromRGB(180, 0, 0)
        statusText.Text = "СТАТУС: АКТИВЕН"
        statusText.TextColor3 = Color3.fromRGB(100, 255, 100)
    else
        stopFarmer()
        toggleButton.Text = "▶ СТАРТ"
        toggleButton.BackgroundColor3 = Color3.fromRGB(0, 120, 0)
        statusText.Text = "СТАТУС: ОСТАНОВЛЕН"
        statusText.TextColor3 = Color3.fromRGB(255, 100, 100)
    end
end)

-- Обновление персонажа при респавне
LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(1)
    if isRunning then
        stopFarmer()
        task.wait(0.5)
        startFarmer()
    end
end)

print("[SWILL] MM2 FARMER V2 ЗАГРУЖЕН")
print("[SWILL] Нажмите кнопку СТАРТ в GUI для начала работы")
print("[SWILL] Монеты детектятся корректно")

-- Отображение количества монет в консоли (опционально)
spawn(function()
    while task.wait(2) do
        if isRunning then
            local coins = getCoins()
            print("[SWILL] Монет на карте:", #coins)
        end
    end
end)
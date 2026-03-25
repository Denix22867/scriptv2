-- SWILL // MM2 AUTO FARMER V6 // FULL SCREEN DETECTION // NO FALSE MOVEMENT
-- Полная детекция всех экранов ожидания, лобби, спектатора

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")
local LocalPlayer = Players.LocalPlayer

-- Глобальные переменные
local isRunning = false
local isEvading = false
local isGameActive = false
local currentNoclip = nil
local currentConnection = nil

-- РАСШИРЕННАЯ ФУНКЦИЯ ПРОВЕРКИ АКТИВНОСТИ ИГРЫ
local function isGameActuallyActive()
    -- Проверка 1: Экран ожидания через PlayerGui
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if playerGui then
        -- Ищем любые элементы с текстом ожидания
        local allGui = playerGui:GetDescendants()
        for _, obj in pairs(allGui) do
            if obj:IsA("TextLabel") or obj:IsA("TextButton") then
                local text = string.upper(obj.Text or "")
                local visible = true
                if obj:IsA("TextLabel") and obj.Visible == false then visible = false end
                if obj:IsA("TextButton") and obj.Visible == false then visible = false end
                
                if visible then
                    -- Все варианты неактивного состояния
                    if string.find(text, "WAITING") or 
                       string.find(text, "SPECTATOR") or
                       string.find(text, "SPECTATING") or
                       string.find(text, "YOU ARE SPECTATING") or
                       string.find(text, "WAITING FOR PLAYERS") or
                       string.find(text, "ROUND ENDS") or
                       string.find(text, "GAME OVER") or
                       string.find(text, "YOU DIED") or
                       string.find(text, "YOUR TURN") and string.find(text, "WAITING") or
                       string.find(text, "NEXT ROUND") or
                       string.find(text, "LOBBY") then
                        return false
                    end
                end
            end
            
            -- Проверка ImageLabel с текстом внутри
            if obj:IsA("ImageLabel") then
                for _, child in pairs(obj:GetChildren()) do
                    if child:IsA("TextLabel") and child.Visible then
                        local text = string.upper(child.Text or "")
                        if string.find(text, "WAITING") or string.find(text, "SPECTATOR") then
                            return false
                        end
                    end
                end
            end
            
            -- Проверка Frame с затемнением (часто в лобби)
            if obj:IsA("Frame") and obj.BackgroundTransparency < 0.5 and obj.Size == UDim2.new(1, 0, 1, 0) then
                for _, child in pairs(obj:GetChildren()) do
                    if child:IsA("TextLabel") and child.Visible then
                        local text = string.upper(child.Text or "")
                        if string.find(text, "WAITING") or string.find(text, "SPECTATOR") then
                            return false
                        end
                    end
                end
            end
        end
    end
    
    -- Проверка 2: CoreGui (системные окна Roblox)
    local coreGui = game:GetService("CoreGui"):GetChildren()
    for _, gui in pairs(coreGui) do
        if gui.Name == "RobloxGui" then
            for _, obj in pairs(gui:GetDescendants()) do
                if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and obj.Visible then
                    local text = string.upper(obj.Text or "")
                    if string.find(text, "WAITING") or string.find(text, "SPECTATOR") then
                        return false
                    end
                end
            end
        end
    end
    
    -- Проверка 3: Статус персонажа (если персонаж мертв или не существует)
    if LocalPlayer.Character then
        local humanoid = LocalPlayer.Character:FindFirstChild("Humanoid")
        if humanoid and humanoid.Health <= 0 then
            return false
        end
    end
    
    -- Проверка 4: BillboardGui над головой (часто показывает статус)
    if LocalPlayer.Character then
        for _, obj in pairs(LocalPlayer.Character:GetDescendants()) do
            if obj:IsA("BillboardGui") and obj.Enabled then
                for _, textObj in pairs(obj:GetDescendants()) do
                    if (textObj:IsA("TextLabel") or textObj:IsA("TextButton")) and textObj.Visible then
                        local text = string.upper(textObj.Text or "")
                        if string.find(text, "SPECTATOR") or string.find(text, "WAITING") then
                            return false
                        end
                    end
                end
            end
        end
    end
    
    -- Проверка 5: Проверка через StarterGui (шаблоны интерфейса)
    local starterGui = game:GetService("StarterGui"):GetChildren()
    for _, gui in pairs(starterGui) do
        if gui:IsA("ScreenGui") then
            for _, obj in pairs(gui:GetDescendants()) do
                if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and string.find(string.upper(obj.Text or ""), "WAITING") then
                    return false
                end
            end
        end
    end
    
    -- Проверка 6: Если нет монет на карте в течение долгого времени (лобби)
    local coins = 0
    for _, v in pairs(Workspace:GetDescendants()) do
        if v:IsA("BasePart") and v.Parent and (string.find(string.lower(v.Name or ""), "coin") or v.BrickColor == BrickColor.new("Bright yellow")) then
            coins = coins + 1
        end
    end
    
    -- Если монет меньше 3 и игра должна быть активна - возможно лобби
    if coins < 3 then
        return false
    end
    
    -- Если все проверки пройдены - игра активна
    return true
end

-- Поиск монет
local function getCoins()
    local coins = {}
    local workspaceItems = Workspace:GetDescendants()
    
    for _, v in pairs(workspaceItems) do
        if v:IsA("BasePart") and v.Parent and v:FindFirstChild("TouchInterest") then
            local nameLower = (v.Name or ""):lower()
            
            if nameLower == "coin" or 
               nameLower == "money" or 
               string.find(nameLower, "coin") or
               (v.BrickColor == BrickColor.new("Bright yellow") and v.Size.X < 5) then
                table.insert(coins, v)
            end
        end
    end
    return coins
end

local function getNearestCoin()
    local coins = getCoins()
    if #coins == 0 then return nil end
    
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        return nil
    end
    
    local rootPos = LocalPlayer.Character.HumanoidRootPart.Position
    local nearest = nil
    local nearestDist = 100
    
    for _, coin in pairs(coins) do
        local dist = (coin.Position - rootPos).Magnitude
        if dist < nearestDist then
            nearestDist = dist
            nearest = coin
        end
    end
    
    return nearest, nearestDist
end

-- Получение близких игроков
local function getNearbyPlayers(radius)
    radius = radius or 50
    local nearby = {}
    
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        return nearby
    end
    
    local rootPos = LocalPlayer.Character.HumanoidRootPart.Position
    
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local playerRoot = player.Character.HumanoidRootPart
            local dist = (playerRoot.Position - rootPos).Magnitude
            if dist < radius then
                table.insert(nearby, {
                    player = player,
                    rootPart = playerRoot,
                    distance = dist
                })
            end
        end
    end
    
    table.sort(nearby, function(a, b) return a.distance < b.distance end)
    return nearby
end

-- Включение/выключение ноклипа
local function setNoclip(state)
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

-- Движение к цели
local function walkTo(position)
    if not LocalPlayer.Character then return false end
    
    local humanoid = LocalPlayer.Character:FindFirstChild("Humanoid")
    if not humanoid then return false end
    
    humanoid.WalkSpeed = 22
    humanoid:MoveTo(position)
    humanoid.AutoRotate = true
    
    return true
end

local function stopMoving()
    if not LocalPlayer.Character then return end
    
    local humanoid = LocalPlayer.Character:FindFirstChild("Humanoid")
    if humanoid then
        humanoid:MoveTo(Vector3.new(9e9, 9e9, 9e9))
        task.wait()
        humanoid:MoveTo(LocalPlayer.Character.HumanoidRootPart.Position)
        humanoid.WalkSpeed = 16
    end
end

-- Уклонение от игрока
local function evadeFromPlayer(playerRoot)
    if not LocalPlayer.Character then return end
    
    local humanoid = LocalPlayer.Character:FindFirstChild("Humanoid")
    local rootPart = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    
    if not humanoid or not rootPart then return end
    
    local direction = (rootPart.Position - playerRoot.Position).Unit
    local evadePosition = rootPart.Position + direction * 45
    evadePosition = Vector3.new(evadePosition.X, rootPart.Position.Y, evadePosition.Z)
    
    setNoclip(true)
    local oldSpeed = humanoid.WalkSpeed
    humanoid.WalkSpeed = 50
    humanoid:MoveTo(evadePosition)
    
    task.wait(1.5)
    
    humanoid.WalkSpeed = oldSpeed
    setNoclip(false)
end

-- Основной цикл
local function startFarmer()
    if currentConnection then return end
    
    isRunning = true
    print("[SWILL] Фармер активирован - полная детекция экранов")
    
    currentConnection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        
        -- ПРОВЕРКА АКТИВНОСТИ ИГРЫ (расширенная)
        local active = isGameActuallyActive()
        
        -- Если игра не активна (лобби, ожидание, спектатор)
        if not active then
            if isGameActive ~= active then
                print("[SWILL] Игра не активна (лобби/ожидание) - бот остановлен")
                isGameActive = active
            end
            stopMoving()
            setNoclip(false)
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                LocalPlayer.Character.Humanoid.WalkSpeed = 16
            end
            return
        end
        
        -- Игра активна
        if not isGameActive and active then
            print("[SWILL] Игра активна - бот работает")
            isGameActive = active
        end
        
        if not LocalPlayer.Character then return end
        
        local humanoid = LocalPlayer.Character:FindFirstChild("Humanoid")
        local rootPart = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        
        if not humanoid or not rootPart then return end
        
        -- Проверка близких игроков
        local nearbyPlayers = getNearbyPlayers(40)
        
        if #nearbyPlayers > 0 and not isEvading then
            isEvading = true
            stopMoving()
            evadeFromPlayer(nearbyPlayers[1].rootPart)
            isEvading = false
            return
        end
        
        if #nearbyPlayers == 0 and not isEvading then
            setNoclip(false)
            
            local targetCoin, distToCoin = getNearestCoin()
            
            if targetCoin and distToCoin > 3 then
                walkTo(targetCoin.Position)
                if rootPart then
                    rootPart.CFrame = CFrame.new(rootPart.Position, targetCoin.Position)
                end
            elseif targetCoin and distToCoin <= 3 then
                stopMoving()
                humanoid.WalkSpeed = 16
            else
                -- Случайное блуждание только если есть монеты на карте
                if #getCoins() > 0 then
                    local randomPos = rootPart.Position + Vector3.new(math.random(-25, 25), 0, math.random(-25, 25))
                    randomPos = Vector3.new(randomPos.X, rootPart.Position.Y, randomPos.Z)
                    walkTo(randomPos)
                else
                    stopMoving()
                end
            end
        end
    end)
end

local function stopFarmer()
    if currentConnection then
        currentConnection:Disconnect()
        currentConnection = nil
    end
    
    stopMoving()
    setNoclip(false)
    isRunning = false
    isEvading = false
    isGameActive = false
    
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        LocalPlayer.Character.Humanoid.WalkSpeed = 16
    end
    
    print("[SWILL] Фармер остановлен")
end

-- Создание GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SWILL_MM2_GUI"
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 240, 0, 150)
frame.Position = UDim2.new(0.5, -120, 0.8, 0)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
frame.BackgroundTransparency = 0.15
frame.BorderSizePixel = 0
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.Position = UDim2.new(0, 0, 0, 0)
title.Text = "SWILL FARMER V6"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.Parent = frame

local statusText = Instance.new("TextLabel")
statusText.Size = UDim2.new(1, 0, 0, 25)
statusText.Position = UDim2.new(0, 0, 0, 32)
statusText.Text = "СТАТУС: ОСТАНОВЛЕН"
statusText.TextColor3 = Color3.fromRGB(255, 100, 100)
statusText.BackgroundTransparency = 1
statusText.Font = Enum.Font.Gotham
statusText.TextSize = 11
statusText.Parent = frame

local gameStatusText = Instance.new("TextLabel")
gameStatusText.Size = UDim2.new(1, 0, 0, 20)
gameStatusText.Position = UDim2.new(0, 0, 0, 55)
gameStatusText.Text = "ИГРА: ПРОВЕРКА..."
gameStatusText.TextColor3 = Color3.fromRGB(255, 200, 100)
gameStatusText.BackgroundTransparency = 1
gameStatusText.Font = Enum.Font.Gotham
gameStatusText.TextSize = 10
gameStatusText.Parent = frame

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.new(0.8, 0, 0, 35)
toggleButton.Position = UDim2.new(0.1, 0, 0, 100)
toggleButton.Text = "▶ СТАРТ"
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.BackgroundColor3 = Color3.fromRGB(0, 120, 0)
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 14
toggleButton.Parent = frame

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 8)
buttonCorner.Parent = toggleButton

-- Обновление статуса игры в GUI
spawn(function()
    while task.wait(0.5) do
        if screenGui and screenGui.Parent then
            local active = isGameActuallyActive()
            if active then
                gameStatusText.Text = "ИГРА: АКТИВНА ▶"
                gameStatusText.TextColor3 = Color3.fromRGB(100, 255, 100)
            else
                gameStatusText.Text = "ИГРА: ЛОББИ/ОЖИДАНИЕ ⏸"
                gameStatusText.TextColor3 = Color3.fromRGB(255, 100, 100)
            end
        end
    end
end)

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

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(1)
    if isRunning then
        stopFarmer()
        task.wait(0.5)
        startFarmer()
    end
end)

print("[SWILL] V6 ЗАГРУЖЕН - РАСШИРЕННАЯ ДЕТЕКЦИЯ ЭКРАНОВ")
print("[SWILL] Отслеживаются: WAITING, SPECTATOR, LOBBY, GAME OVER, YOU DIED")
print("[SWILL] Бот активен только в активном раунде с монетами")

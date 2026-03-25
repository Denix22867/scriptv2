-- SWILL // MM2 AUTO FARMER V5 // NO TELEPORT // NATURAL MOVEMENT
-- Полностью переработанная система движения. Никаких телепортаций и улетаний.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- Глобальные переменные
local isRunning = false
local isEvading = false
local currentNoclip = nil
local currentConnection = nil
local currentTarget = nil
local currentWalkConnection = nil

-- Функция проверки экрана ожидания
local function isWaitingForTurn()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return false end
    
    for _, obj in pairs(playerGui:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            local text = string.upper(obj.Text or "")
            if string.find(text, "WAITING") and string.find(text, "TURN") then
                return true
            end
            if string.find(text, "SPECTATING") then
                return true
            end
        end
    end
    return false
end

-- Поиск монет (улучшенный)
local function getCoins()
    local coins = {}
    local workspaceItems = Workspace:GetDescendants()
    
    for _, v in pairs(workspaceItems) do
        if v:IsA("BasePart") and v.Parent then
            local nameLower = (v.Name or ""):lower()
            local parentNameLower = (v.Parent and v.Parent.Name or ""):lower()
            
            -- Проверка на монету
            local isCoin = false
            
            if nameLower == "coin" or nameLower == "money" then
                isCoin = true
            elseif string.find(nameLower, "coin") and v.Size.X < 5 then
                isCoin = true
            elseif v.BrickColor == BrickColor.new("Bright yellow") and v.Size.X < 3 and v.CanTouch then
                isCoin = true
            elseif parentNameLower == "coins" or parentNameLower == "coin" then
                isCoin = true
            end
            
            if isCoin and v:FindFirstChild("TouchInterest") then
                table.insert(coins, v)
            end
        end
    end
    return coins
end

-- Получение ближайшей монеты
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

-- Движение к цели (через WalkToPoint, без телепортации)
local function walkTo(position)
    if not LocalPlayer.Character then return false end
    
    local humanoid = LocalPlayer.Character:FindFirstChild("Humanoid")
    local rootPart = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    
    if not humanoid or not rootPart then return false end
    
    -- Устанавливаем скорость бега
    humanoid.WalkSpeed = 22
    
    -- Устанавливаем цель для движения
    humanoid:MoveTo(position)
    
    -- Включаем автоматическое перемещение
    humanoid.AutoRotate = true
    
    return true
end

-- Остановка движения
local function stopMoving()
    if not LocalPlayer.Character then return end
    
    local humanoid = LocalPlayer.Character:FindFirstChild("Humanoid")
    if humanoid then
        humanoid:MoveTo(Vector3.new(9e9, 9e9, 9e9))
        task.wait()
        humanoid:MoveTo(LocalPlayer.Character.HumanoidRootPart.Position)
    end
end

-- Уклонение от игрока (быстрое перемещение без телепортации)
local function evadeFromPlayer(playerRoot)
    if not LocalPlayer.Character then return end
    
    local humanoid = LocalPlayer.Character:FindFirstChild("Humanoid")
    local rootPart = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    
    if not humanoid or not rootPart then return end
    
    -- Направление от игрока
    local direction = (rootPart.Position - playerRoot.Position).Unit
    local evadePosition = rootPart.Position + direction * 40
    
    -- Ограничиваем высоту
    evadePosition = Vector3.new(evadePosition.X, rootPart.Position.Y, evadePosition.Z)
    
    -- Включаем ноклип для прохода сквозь стены
    setNoclip(true)
    
    -- Увеличиваем скорость для быстрого уклонения
    local oldSpeed = humanoid.WalkSpeed
    humanoid.WalkSpeed = 45
    
    -- Бежим в безопасное место
    humanoid:MoveTo(evadePosition)
    
    -- Ждем немного
    task.wait(1.5)
    
    -- Возвращаем нормальную скорость
    humanoid.WalkSpeed = oldSpeed
    
    -- Выключаем ноклип
    setNoclip(false)
end

-- Основной цикл
local function startFarmer()
    if currentConnection then return end
    
    isRunning = true
    print("[SWILL] Фармер активирован - естественное движение, без телепортаций")
    
    currentConnection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        
        -- Проверка экрана ожидания
        if isWaitingForTurn() then
            stopMoving()
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                LocalPlayer.Character.Humanoid.WalkSpeed = 16
            end
            setNoclip(false)
            return
        end
        
        if not LocalPlayer.Character then return end
        
        local humanoid = LocalPlayer.Character:FindFirstChild("Humanoid")
        local rootPart = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        
        if not humanoid or not rootPart then return end
        
        -- Проверка близких игроков
        local nearbyPlayers = getNearbyPlayers(40)
        
        -- Если есть игрок рядом и мы не в режиме уклонения
        if #nearbyPlayers > 0 and not isEvading then
            isEvading = true
            stopMoving()
            evadeFromPlayer(nearbyPlayers[1].rootPart)
            isEvading = false
            return
        end
        
        -- Если нет игроков рядом
        if #nearbyPlayers == 0 and not isEvading then
            -- Выключаем ноклип
            setNoclip(false)
            
            -- Ищем ближайшую монету
            local targetCoin, distToCoin = getNearestCoin()
            
            if targetCoin and distToCoin > 3 then
                -- Если монета далеко - идем к ней
                currentTarget = targetCoin
                walkTo(targetCoin.Position)
                
                -- Поворачиваемся к монете
                rootPart.CFrame = CFrame.new(rootPart.Position, targetCoin.Position)
                
            elseif targetCoin and distToCoin <= 3 then
                -- Если монета рядом - останавливаемся и ждем сбора
                stopMoving()
                humanoid.WalkSpeed = 16
                
            else
                -- Если монет нет - случайное блуждание
                if not currentTarget or (currentTarget and (currentTarget.Position - rootPart.Position).Magnitude < 2) then
                    local randomPos = rootPart.Position + Vector3.new(math.random(-30, 30), 0, math.random(-30, 30))
                    randomPos = Vector3.new(randomPos.X, rootPart.Position.Y, randomPos.Z)
                    walkTo(randomPos)
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
    currentTarget = nil
    
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
frame.Size = UDim2.new(0, 220, 0, 120)
frame.Position = UDim2.new(0.5, -110, 0.8, 0)
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
title.Text = "SWILL FARMER V5"
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

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.new(0.8, 0, 0, 35)
toggleButton.Position = UDim2.new(0.1, 0, 0, 70)
toggleButton.Text = "▶ СТАРТ"
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.BackgroundColor3 = Color3.fromRGB(0, 120, 0)
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 14
toggleButton.Parent = frame

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 8)
buttonCorner.Parent = toggleButton

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

print("[SWILL] V5 ЗАГРУЖЕН - ПОЛНОСТЬЮ ПЕРЕРАБОТАНО ДВИЖЕНИЕ")
print("[SWILL] Бот использует WalkToPoint, никаких телепортаций и улетаний")

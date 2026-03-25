-- SWILL // MM2 AUTO FARMER V7 // FIXED DETECTION & NO CLIPPING THROUGH FLOOR
-- Полная детекция активности MM2, автокоррекция позиции, защита от падений

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- Глобальные переменные
local isRunning = false
local isEvading = false
local isGameActive = false
local currentNoclip = nil
local currentConnection = nil
local lastGroundPosition = nil

-- ========== УЛУЧШЕННАЯ ДЕТЕКЦИЯ АКТИВНОСТИ ИГРЫ (MM2 SPECIFIC) ==========
local function isGameActuallyActive()
    -- 1. Проверка наличия экрана выбора роли (активная игра)
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if playerGui then
        -- Ищем панель с информацией о раунде (таймер, роли)
        for _, obj in pairs(playerGui:GetDescendants()) do
            if obj:IsA("TextLabel") and obj.Visible then
                local text = obj.Text or ""
                -- Если виден таймер (например, "2:30") — игра активна
                if string.match(text, "%d+:%d+") and #text <= 6 then
                    return true
                end
                -- Если видна надпись роли: "You are the Murderer", "You are the Sheriff", "You are the Innocent"
                if string.find(text, "Murderer") or string.find(text, "Sheriff") or string.find(text, "Innocent") then
                    return true
                end
                -- Если видно сообщение о начале раунда
                if string.find(text, "The round has started") or string.find(text, "Game started") then
                    return true
                end
            end
            -- Кнопка сброса (есть только в активном раунде)
            if obj:IsA("TextButton") and obj.Visible and (obj.Text == "Reset" or obj.Text == "Respawn") then
                return true
            end
        end
    end
    
    -- 2. Проверка на экран ожидания / лобби
    if playerGui then
        for _, obj in pairs(playerGui:GetDescendants()) do
            if obj:IsA("TextLabel") and obj.Visible then
                local text = string.upper(obj.Text or "")
                if string.find(text, "WAITING FOR YOUR TURN") or
                   string.find(text, "YOU ARE SPECTATING") or
                   string.find(text, "SPECTATOR") or
                   string.find(text, "WAITING FOR PLAYERS") or
                   string.find(text, "ROUND ENDS") or
                   string.find(text, "GAME OVER") then
                    return false
                end
            end
        end
    end
    
    -- 3. Проверка BillboardGui на персонаже (спектатор)
    if LocalPlayer.Character then
        for _, obj in pairs(LocalPlayer.Character:GetDescendants()) do
            if obj:IsA("BillboardGui") and obj.Enabled then
                for _, txt in pairs(obj:GetDescendants()) do
                    if txt:IsA("TextLabel") and txt.Visible then
                        local text = string.upper(txt.Text or "")
                        if string.find(text, "SPECTATOR") or string.find(text, "WAITING") then
                            return false
                        end
                    end
                end
            end
        end
    end
    
    -- 4. Если персонаж мёртв — не активен
    if LocalPlayer.Character then
        local humanoid = LocalPlayer.Character:FindFirstChild("Humanoid")
        if humanoid and humanoid.Health <= 0 then
            return false
        end
    end
    
    -- 5. Если нет ни одного игрока на карте (кроме себя) — возможно лобби, но не точно
    local otherPlayers = 0
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            otherPlayers = otherPlayers + 1
        end
    end
    if otherPlayers == 0 then
        return false
    end
    
    -- Если ничего не указало на неактивность — считаем активным
    return true
end

-- ========== ЗАЩИТА ОТ ПРОВАЛИВАНИЯ ==========
local function getGroundPosition(position)
    -- Делаем рейкаст вниз, чтобы найти пол
    local rayOrigin = position + Vector3.new(0, 5, 0)
    local rayDirection = Vector3.new(0, -20, 0)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = {LocalPlayer.Character}
    local result = Workspace:Raycast(rayOrigin, rayDirection, rayParams)
    
    if result then
        return result.Position + Vector3.new(0, 3, 0) -- поднимаем чуть выше пола
    else
        return nil
    end
end

local function fixPosition()
    if not LocalPlayer.Character then return end
    local rootPart = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end
    
    local groundPos = getGroundPosition(rootPart.Position)
    if groundPos then
        -- Если разница по Y больше 5 студий, вероятно, провалился
        if math.abs(rootPart.Position.Y - groundPos.Y) > 5 then
            rootPart.CFrame = CFrame.new(groundPos)
            if LocalPlayer.Character.Humanoid then
                LocalPlayer.Character.Humanoid:ChangeState(Enum.HumanoidStateType.Landed)
            end
        end
    else
        -- Если пол не найден (очень высоко), телепортируем в центр карты на уровень 10
        rootPart.CFrame = CFrame.new(0, 10, 0)
    end
end

-- ========== ОСТАЛЬНЫЕ ФУНКЦИИ (НОКЛИП, ДВИЖЕНИЕ И Т.Д.) ==========
-- (сохраняем из V6, но добавляем вызов fixPosition в цикле)

-- Поиск монет (без изменений)
local function getCoins()
    local coins = {}
    for _, v in pairs(Workspace:GetDescendants()) do
        if v:IsA("BasePart") and v.Parent and v:FindFirstChild("TouchInterest") then
            local nameLower = (v.Name or ""):lower()
            if nameLower == "coin" or nameLower == "money" or string.find(nameLower, "coin") or
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
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return nil end
    local rootPos = LocalPlayer.Character.HumanoidRootPart.Position
    local nearest, nearestDist = nil, 100
    for _, coin in pairs(coins) do
        local dist = (coin.Position - rootPos).Magnitude
        if dist < nearestDist then
            nearestDist = dist
            nearest = coin
        end
    end
    return nearest, nearestDist
end

local function getNearbyPlayers(radius)
    radius = radius or 50
    local nearby = {}
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return nearby end
    local rootPos = LocalPlayer.Character.HumanoidRootPart.Position
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local dist = (player.Character.HumanoidRootPart.Position - rootPos).Magnitude
            if dist < radius then
                table.insert(nearby, {player = player, rootPart = player.Character.HumanoidRootPart, distance = dist})
            end
        end
    end
    table.sort(nearby, function(a,b) return a.distance < b.distance end)
    return nearby
end

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
        humanoid:MoveTo(Vector3.new(9e9,9e9,9e9))
        task.wait()
        humanoid:MoveTo(LocalPlayer.Character.HumanoidRootPart.Position)
        humanoid.WalkSpeed = 16
    end
end

local function evadeFromPlayer(playerRoot)
    if not LocalPlayer.Character then return end
    local humanoid = LocalPlayer.Character:FindFirstChild("Humanoid")
    local rootPart = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then return end
    
    local direction = (rootPart.Position - playerRoot.Position).Unit
    local evadePos = rootPart.Position + direction * 45
    evadePos = Vector3.new(evadePos.X, rootPart.Position.Y, evadePos.Z)
    
    setNoclip(true)
    local oldSpeed = humanoid.WalkSpeed
    humanoid.WalkSpeed = 50
    humanoid:MoveTo(evadePos)
    task.wait(1.5)
    humanoid.WalkSpeed = oldSpeed
    setNoclip(false)
end

-- ========== ОСНОВНОЙ ЦИКЛ (С ДОБАВЛЕННОЙ КОРРЕКЦИЕЙ) ==========
local function startFarmer()
    if currentConnection then return end
    isRunning = true
    print("[SWILL] Фармер активирован V7 (исправлены провалы и детекция)")
    
    currentConnection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        
        -- Проверка активности игры
        local active = isGameActuallyActive()
        if active ~= isGameActive then
            isGameActive = active
            if not active then
                print("[SWILL] Игра не активна (лобби/спектатор) - бот остановлен")
                stopMoving()
                setNoclip(false)
            else
                print("[SWILL] Игра активна - бот работает")
            end
        end
        
        if not active then
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                LocalPlayer.Character.Humanoid.WalkSpeed = 16
            end
            return
        end
        
        if not LocalPlayer.Character then return end
        local humanoid = LocalPlayer.Character:FindFirstChild("Humanoid")
        local rootPart = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not rootPart then return end
        
        -- КОРРЕКЦИЯ ПОЗИЦИИ (от проваливания)
        fixPosition()
        
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
                -- Если монет нет, но есть другие игроки (возможно, начался раунд), стоим на месте
                if #getCoins() > 0 then
                    local randomPos = rootPart.Position + Vector3.new(math.random(-25,25), 0, math.random(-25,25))
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

-- ========== GUI (без изменений, но добавим отображение статуса игры) ==========
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
title.Text = "SWILL FARMER V7"
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
        else
            break
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

print("[SWILL] V7 ЗАГРУЖЕН - ИСПРАВЛЕНЫ ДЕТЕКЦИЯ И ПРОВАЛИВАНИЕ")
print("[SWILL] - Детекция активной игры по таймеру, ролям, кнопке Reset")
print("[SWILL] - Автокоррекция позиции: предотвращает проваливание сквозь пол")

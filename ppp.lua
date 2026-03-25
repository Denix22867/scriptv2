-- SWILL // MM2 AUTO FARMER V8 // ADVANCED DETECTION (NON-STANDARD FONTS)
-- Детекция активности игры по уникальным элементам MM2, не зависящая от текста.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- Глобальные переменные
local isRunning = false
local isEvading = false
local isGameActive = false
local currentNoclip = nil
local currentConnection = nil
local lastGroundPosition = nil

-- ========== РАСШИРЕННАЯ ДЕТЕКЦИЯ АКТИВНОСТИ (без опоры на текст) ==========
local function isGameActuallyActive()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return false end
    
    -- 1. Проверка наличия таймера (формат "0:00" или "00:00") - всегда есть в активном раунде
    local hasTimer = false
    for _, obj in pairs(playerGui:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Visible then
            local text = obj.Text or ""
            -- Таймер обычно выглядит как "2:30" или "00:00"
            if string.match(text, "^%d+:%d+$") or string.match(text, "^%d%d:%d%d$") then
                hasTimer = true
                break
            end
        end
    end
    
    -- 2. Проверка наличия кнопки "Reset" (появляется только когда игрок жив и в раунде)
    local hasResetButton = false
    for _, obj in pairs(playerGui:GetDescendants()) do
        if obj:IsA("TextButton") and obj.Visible and obj.Text == "Reset" then
            hasResetButton = true
            break
        end
    end
    
    -- 3. Проверка наличия иконок оружия/ролей (убийца, шериф) — уникальные элементы MM2
    local hasRoleIcon = false
    for _, obj in pairs(playerGui:GetDescendants()) do
        if obj:IsA("ImageLabel") and obj.Visible then
            local image = obj.Image or ""
            -- Ищем характерные для MM2 иконки (можно подставить конкретные ID, но они могут меняться)
            if string.find(image, "rbxasset") and (string.find(image, "knife") or string.find(image, "gun") or string.find(image, "sheriff")) then
                hasRoleIcon = true
                break
            end
        end
    end
    
    -- 4. Проверка, что игрок не в режиме спектатора (камера не привязана к чужому персонажу)
    local camera = workspace.CurrentCamera
    local isSpectating = false
    if camera and camera.CameraSubject and camera.CameraSubject ~= LocalPlayer.Character then
        isSpectating = true
    end
    
    -- 5. Проверка, что персонаж жив и существует
    local isAlive = false
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        local humanoid = LocalPlayer.Character.Humanoid
        if humanoid.Health > 0 then
            isAlive = true
        end
    end
    
    -- 6. Проверка наличия затемняющего фона (лобби/спектатор часто имеет полупрозрачный черный фон)
    local hasDimBackground = false
    for _, obj in pairs(playerGui:GetDescendants()) do
        if obj:IsA("Frame") and obj.BackgroundTransparency < 0.5 and obj.Size == UDim2.new(1, 0, 1, 0) then
            hasDimBackground = true
            break
        end
    end
    
    -- Логика: игра активна, если есть таймер ИЛИ кнопка Reset, И мы не в спектаторе, И жив.
    -- Если есть затемняющий фон и нет таймера и нет кнопки Reset — скорее всего лобби.
    if (hasTimer or hasResetButton or hasRoleIcon) and not isSpectating and isAlive then
        return true
    elseif hasDimBackground and not hasTimer and not hasResetButton then
        return false
    elseif isSpectating then
        return false
    elseif not isAlive then
        return false
    end
    
    -- Дополнительная проверка: если нет других игроков на карте — лобби
    local otherPlayers = 0
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            otherPlayers = otherPlayers + 1
        end
    end
    if otherPlayers == 0 then
        return false
    end
    
    -- Если ничего не определило, считаем неактивным (безопаснее)
    return false
end

-- ========== ЗАЩИТА ОТ ПРОВАЛИВАНИЯ (без изменений) ==========
local function getGroundPosition(position)
    local rayOrigin = position + Vector3.new(0, 5, 0)
    local rayDirection = Vector3.new(0, -20, 0)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = {LocalPlayer.Character}
    local result = Workspace:Raycast(rayOrigin, rayDirection, rayParams)
    if result then
        return result.Position + Vector3.new(0, 3, 0)
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
        if math.abs(rootPart.Position.Y - groundPos.Y) > 5 then
            rootPart.CFrame = CFrame.new(groundPos)
            if LocalPlayer.Character.Humanoid then
                LocalPlayer.Character.Humanoid:ChangeState(Enum.HumanoidStateType.Landed)
            end
        end
    else
        rootPart.CFrame = CFrame.new(0, 10, 0)
    end
end

-- ========== ОСТАЛЬНЫЕ ФУНКЦИИ (поиск монет, игроки, движение) ==========
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

-- ========== ОСНОВНОЙ ЦИКЛ ==========
local function startFarmer()
    if currentConnection then return end
    isRunning = true
    print("[SWILL] Фармер активирован V8 (детекция без привязки к тексту)")
    
    currentConnection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        
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

-- ========== GUI ==========
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
title.Text = "SWILL FARMER V8"
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

spawn(function()
    while task.wait(0.5) do
        if screenGui and screenGui.Parent then
            local active = isGameActuallyActive()
            if active then
                gameStatusText.Text = "ИГРА: АКТИВНА ▶"
                gameStatusText.TextColor3 = Color3.fromRGB(100, 255, 100)
            else
                gameStatusText.Text = "ИГРА: ЛОББИ/СПЕКТАТОР ⏸"
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

print("[SWILL] V8 ЗАГРУЖЕН - ДЕТЕКЦИЯ АКТИВНОСТИ БЕЗ ОПОРЫ НА ТЕКСТ")
print("[SWILL] Используются: таймер, кнопка Reset, иконки ролей, состояние камеры")

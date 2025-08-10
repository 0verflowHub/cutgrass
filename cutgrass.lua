--[[
    Cut Grass - 0verflow Hub
    Advanced grass cutting script with auto collection, ESP, and anti-teleport
    
    Author: buffer_0verflow
    Date: 2025-08-10
    Version: 2.0.0
    Time: 16:00:24 UTC
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Player
local LocalPlayer = Players.LocalPlayer

-- Core Variables
local CutGrassExploit = {
    Active = false,
    SelectedLootZone = "Main",
    HitboxSize = 1,
    WalkSpeed = 16,
    GrassVisible = true,
    Toggles = {}
}

-- State Management
local State = {
    EnabledFlags = {},
    AntiTeleportCharacterConnections = {},
    AutoCollectCoroutine = nil,
    AutoGrassDeleteCoroutine = nil,
    ChestESP = false,
    PlayerESP = false,
    ESPHighlights = {},
    ChestESPConnections = {},
    PlayerESPConnections = {},
    ChestESPUpdateCoroutine = nil,
    PlayerESPUpdateCoroutine = nil,
    HitboxLoop = nil,
    OriginalGrassTransparencies = {},
    GrassMonitorCoroutine = nil,
    GrassAddedConnections = {}
}

-- Tier colors for chest ESP
local tierColors = {
    [1] = Color3.fromRGB(150, 150, 150),
    [2] = Color3.fromRGB(30, 236, 0),
    [3] = Color3.fromRGB(53, 165, 255),
    [4] = Color3.fromRGB(167, 60, 255),
    [5] = Color3.fromRGB(255, 136, 0),
    [6] = Color3.fromRGB(255, 0, 0)
}

-- ========================================
-- DATA FUNCTIONS
-- ========================================

local function GetAllLootZones()
    local zones = {}
    local lootZonesFolder = Workspace:FindFirstChild("LootZones")
    if lootZonesFolder then
        for _, zone in ipairs(lootZonesFolder:GetChildren()) do
            table.insert(zones, zone.Name)
        end
    end
    if #zones == 0 then
        return {"Main"}
    end
    return zones
end

-- ========================================
-- GRASS SYSTEM
-- ========================================

local function SetGrassVisibility(grass, visible)
    if grass:IsA("BasePart") then
        if visible then
            local originalTransparency = State.OriginalGrassTransparencies[grass]
            grass.Transparency = originalTransparency or 0
        else
            if not State.OriginalGrassTransparencies[grass] then
                State.OriginalGrassTransparencies[grass] = grass.Transparency
            end
            grass.Transparency = 1
            grass.CanCollide = false
        end
    elseif grass:IsA("Model") then
        for _, part in pairs(grass:GetDescendants()) do
            if part:IsA("BasePart") then
                if visible then
                    local originalTransparency = State.OriginalGrassTransparencies[part]
                    part.Transparency = originalTransparency or 0
                    part.CanCollide = true
                else
                    if not State.OriginalGrassTransparencies[part] then
                        State.OriginalGrassTransparencies[part] = part.Transparency
                    end
                    part.Transparency = 1
                    part.CanCollide = false
                end
            end
        end
    end
end

local function StopGrassMonitoring()
    for _, conn in ipairs(State.GrassAddedConnections) do
        conn:Disconnect()
    end
    State.GrassAddedConnections = {}
end

local function StartGrassMonitoring()
    StopGrassMonitoring()
    
    local grassFolder = Workspace:FindFirstChild("Grass")
    if grassFolder then
        local grassAddedConn = grassFolder.ChildAdded:Connect(function(newGrass)
            if not CutGrassExploit.GrassVisible then
                SetGrassVisibility(newGrass, false)
            end
        end)
        table.insert(State.GrassAddedConnections, grassAddedConn)
    end
    
    local workspaceConn = Workspace.ChildAdded:Connect(function(child)
        if child.Name == "Grass" and not CutGrassExploit.GrassVisible then
            for _, grass in pairs(child:GetChildren()) do
                SetGrassVisibility(grass, false)
            end
            
            local grassAddedConn = child.ChildAdded:Connect(function(newGrass)
                if not CutGrassExploit.GrassVisible then
                    SetGrassVisibility(newGrass, false)
                end
            end)
            table.insert(State.GrassAddedConnections, grassAddedConn)
        end
    end)
    table.insert(State.GrassAddedConnections, workspaceConn)
end

local function ToggleGrassVisibility(visible)
    CutGrassExploit.GrassVisible = visible
    local grassFolder = Workspace:FindFirstChild("Grass")
    
    if visible then
        StopGrassMonitoring()
        
        if grassFolder then
            for _, grass in pairs(grassFolder:GetChildren()) do
                if grass:IsA("BasePart") or grass:IsA("Model") then
                    SetGrassVisibility(grass, true)
                end
            end
        end
    else
        if grassFolder then
            for _, grass in pairs(grassFolder:GetChildren()) do
                if grass:IsA("BasePart") or grass:IsA("Model") then
                    SetGrassVisibility(grass, false)
                end
            end
        end
        
        StartGrassMonitoring()
    end
end

-- ========================================
-- AUTO CUT SYSTEM
-- ========================================

local function SetAutoCut(enabled)
    State.EnabledFlags["AutoCut"] = enabled
    
    local WeaponSwingEvent = ReplicatedStorage.RemoteEvents.WeaponSwingEvent
    
    if enabled then
        WeaponSwingEvent:FireServer("HitboxStart")
    else
        WeaponSwingEvent:FireServer("HitboxEnd")
    end
end

-- ========================================
-- AUTO COLLECT SYSTEM
-- ========================================

local function ActivateAntiTeleportForCharacter(character, anchorCFrame)
    for _, connection in ipairs(State.AntiTeleportCharacterConnections) do
        connection:Disconnect()
    end
    State.AntiTeleportCharacterConnections = {}
    
    if not character then return end
    local humanoid = character:FindFirstChildOfClass('Humanoid')
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not (humanoid and rootPart) then return end

    local lastCF = anchorCFrame or rootPart.CFrame
    local stop

    local heartbeatConn = RunService.Heartbeat:Connect(function()
        if stop then return end
        if rootPart and rootPart.Parent then
            lastCF = rootPart.CFrame
        end
    end)
    table.insert(State.AntiTeleportCharacterConnections, heartbeatConn)

    local cframeConn = rootPart:GetPropertyChangedSignal('CFrame'):Connect(function()
        stop = true
        if rootPart and rootPart.Parent then
            rootPart.CFrame = lastCF
        end
        RunService.Heartbeat:Wait()
        stop = false
    end)
    table.insert(State.AntiTeleportCharacterConnections, cframeConn)

    local diedConn = humanoid.Died:Connect(function()
        for _, connection in ipairs(State.AntiTeleportCharacterConnections) do
            connection:Disconnect()
        end
        State.AntiTeleportCharacterConnections = {}
    end)
    table.insert(State.AntiTeleportCharacterConnections, diedConn)
end

local function DeactivateAntiTeleportForCharacter()
    local character = LocalPlayer.Character
    if character then
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if rootPart then
            rootPart.CFrame = rootPart.CFrame
        end
    end
    for _, connection in ipairs(State.AntiTeleportCharacterConnections) do
        connection:Disconnect()
    end
    State.AntiTeleportCharacterConnections = {}
end

local function SetAutoCollect(enabled)
    State.EnabledFlags["AutoCollect"] = enabled
    
    if enabled then
        if not State.EnabledFlags["AntiTeleport"] then
            State.EnabledFlags["AntiTeleport"] = true
            ActivateAntiTeleportForCharacter(LocalPlayer.Character)
        end
        
        if State.AutoCollectCoroutine then coroutine.close(State.AutoCollectCoroutine) end
        if State.AutoGrassDeleteCoroutine then coroutine.close(State.AutoGrassDeleteCoroutine) end

        State.AutoGrassDeleteCoroutine = coroutine.create(function()
            while State.EnabledFlags["AutoCollect"] do
                ToggleGrassVisibility(false)
                task.wait(0.5)
            end
        end)

        State.AutoCollectCoroutine = coroutine.create(function()
            local selectedZone = CutGrassExploit.SelectedLootZone
            if type(selectedZone) ~= "string" then
                selectedZone = tostring(selectedZone)
            end
            local lootZoneFolder = Workspace.LootZones:FindFirstChild(selectedZone)
            if not lootZoneFolder or not lootZoneFolder:FindFirstChild("Loot") then
                warn("Selected loot zone or its 'Loot' subfolder not found: " .. tostring(CutGrassExploit.SelectedLootZone))
                return
            end
            local LootFolder = lootZoneFolder.Loot

            local function collect(item)
                if not State.EnabledFlags["AutoCollect"] then return false end
                if not item or not item.Parent then return true end

                local Character = LocalPlayer.Character
                if not Character then return false end
                local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")
                if not HumanoidRootPart then return false end

                local TargetPart = if item:IsA("BasePart") then item else (if item:IsA("Model") then (item.PrimaryPart or item:FindFirstChildOfClass("BasePart")) else nil)
                if not TargetPart or not TargetPart.Parent then return true end

                local antiTeleportWasEnabled = State.EnabledFlags["AntiTeleport"]
                if antiTeleportWasEnabled then
                    DeactivateAntiTeleportForCharacter()
                end

                HumanoidRootPart.CFrame = TargetPart.CFrame * CFrame.new(0, 0, -1.5)
                task.wait(0.01)

                for i = 1, 4 do
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                    task.wait(0.01)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                    if i < 4 then task.wait(0.01) end
                end

                task.wait(0.02)

                if antiTeleportWasEnabled then
                    ActivateAntiTeleportForCharacter(Character)
                end

                return true
            end

            while State.EnabledFlags["AutoCollect"] do
                local children = LootFolder:GetChildren()
                if #children > 0 then
                    for _, item in ipairs(children) do
                        if not State.EnabledFlags["AutoCollect"] then break end
                        collect(item)
                        task.wait(0.01)
                    end
                else
                    task.wait(0.1)
                end
                task.wait(0.02)
            end
        end)

        coroutine.resume(State.AutoGrassDeleteCoroutine)
        coroutine.resume(State.AutoCollectCoroutine)
    else
        if State.AutoCollectCoroutine then
            coroutine.close(State.AutoCollectCoroutine)
            State.AutoCollectCoroutine = nil
        end
        if State.AutoGrassDeleteCoroutine then
            coroutine.close(State.AutoGrassDeleteCoroutine)
            State.AutoGrassDeleteCoroutine = nil
        end
    end
end

-- ========================================
-- HITBOX SYSTEM
-- ========================================

local function UpdateHitbox()
    local Character = LocalPlayer.Character
    if Character then
        local Tool = Character:FindFirstChildOfClass("Tool")
        if Tool then
            local Hitbox = Tool:FindFirstChild("Hitbox", true) or Tool:FindFirstChild("Blade", true) or Tool:FindFirstChild("Handle")
            if Hitbox and Hitbox:IsA("BasePart") then
                Hitbox.Size = Vector3.new(CutGrassExploit.HitboxSize, CutGrassExploit.HitboxSize, CutGrassExploit.HitboxSize)
                Hitbox.Transparency = 0.5
            end
        end
    end
end

local function SetWalkSpeed(value)
    local Character = LocalPlayer.Character
    if Character then
        local Humanoid = Character:FindFirstChildOfClass("Humanoid")
        if Humanoid then
            Humanoid.WalkSpeed = value
        end
    end
end

-- ========================================
-- ESP SYSTEM
-- ========================================

local function addHighlight(parent, type)
    if not parent or not parent.Parent then return end
    
    local existingHighlight = parent:FindFirstChild("ESPHighlight")
    if existingHighlight then
        existingHighlight:Destroy()
    end
    
    local success, err = pcall(function()
        local tier = parent:GetAttribute("Tier") or 1
        local fillColor, outlineColor
        
        if type == "Player" then
            fillColor = Color3.fromRGB(255, 0, 0)
            outlineColor = Color3.fromRGB(255, 255, 255)
        else
            fillColor = tierColors[tier] or Color3.fromRGB(255, 255, 255)
            outlineColor = Color3.fromRGB(255, 255, 0)
        end
        
        local highlight = Instance.new("Highlight")
        highlight.Name = "ESPHighlight"
        highlight.FillColor = fillColor
        highlight.OutlineColor = outlineColor
        highlight.FillTransparency = 0.5
        highlight.OutlineTransparency = 0
        highlight.Parent = parent
        highlight.Adornee = parent
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        
        table.insert(State.ESPHighlights, {Highlight = highlight, Type = type, Parent = parent})
    end)
end

local function ClearESP(type)
    local count = 0
    for i = #State.ESPHighlights, 1, -1 do
        local entry = State.ESPHighlights[i]
        if entry.Type == type then
            if entry.Highlight and entry.Highlight.Parent then
                pcall(function()
                    entry.Highlight:Destroy()
                    count = count + 1
                end)
            end
            table.remove(State.ESPHighlights, i)
        end
    end
    
    if type == "Chest" then
        local lootZones = Workspace:FindFirstChild("LootZones")
        if lootZones then
            for _, zone in ipairs(lootZones:GetChildren()) do
                local lootFolder = zone:FindFirstChild("Loot")
                if lootFolder then
                    for _, chest in ipairs(lootFolder:GetChildren()) do
                        local highlight = chest:FindFirstChild("ESPHighlight")
                        if highlight then
                            highlight:Destroy()
                        end
                    end
                end
            end
        end
    elseif type == "Player" then
        for _, player in ipairs(Players:GetPlayers()) do
            if player.Character then
                local highlight = player.Character:FindFirstChild("ESPHighlight")
                if highlight then
                    highlight:Destroy()
                end
            end
        end
    end
end

local function ToggleChestESP(enabled)
    State.ChestESP = enabled
    
    if enabled then
        for _, conn in ipairs(State.ChestESPConnections) do
            conn:Disconnect()
        end
        State.ChestESPConnections = {}
        
        local lootZones = Workspace:FindFirstChild("LootZones")
        
        if lootZones then
            for _, zone in ipairs(lootZones:GetChildren()) do
                local lootFolder = zone:FindFirstChild("Loot")
                
                if lootFolder then
                    for _, chest in ipairs(lootFolder:GetChildren()) do
                        addHighlight(chest, "Chest")
                    end
                    
                    local chestConn = lootFolder.ChildAdded:Connect(function(newChest)
                        if State.ChestESP then
                            addHighlight(newChest, "Chest")
                        end
                    end)
                    table.insert(State.ChestESPConnections, chestConn)
                end
                
                local lootConn = zone.ChildAdded:Connect(function(child)
                    if child.Name == "Loot" and State.ChestESP then
                        for _, chest in ipairs(child:GetChildren()) do
                            addHighlight(chest, "Chest")
                        end
                        
                        local chestConn = child.ChildAdded:Connect(function(newChest)
                            if State.ChestESP then
                                addHighlight(newChest, "Chest")
                            end
                        end)
                        table.insert(State.ChestESPConnections, chestConn)
                    end
                end)
                table.insert(State.ChestESPConnections, lootConn)
            end
            
            local zoneAddedConn = lootZones.ChildAdded:Connect(function(newZone)
                if State.ChestESP then
                    local lootFolder = newZone:FindFirstChild("Loot")
                    if lootFolder then
                        for _, chest in ipairs(lootFolder:GetChildren()) do
                            addHighlight(chest, "Chest")
                        end
                        
                        local chestConn = lootFolder.ChildAdded:Connect(function(newChest)
                            if State.ChestESP then
                                addHighlight(newChest, "Chest")
                            end
                        end)
                        table.insert(State.ChestESPConnections, chestConn)
                    end
                end
            end)
            table.insert(State.ChestESPConnections, zoneAddedConn)
        end
        
        if State.ChestESPUpdateCoroutine then
            coroutine.close(State.ChestESPUpdateCoroutine)
        end
        State.ChestESPUpdateCoroutine = coroutine.create(function()
            while State.ChestESP do
                local lootZones = Workspace:FindFirstChild("LootZones")
                if lootZones then
                    for _, zone in ipairs(lootZones:GetChildren()) do
                        local lootFolder = zone:FindFirstChild("Loot")
                        if lootFolder then
                            for _, chest in ipairs(lootFolder:GetChildren()) do
                                if not chest:FindFirstChild("ESPHighlight") then
                                    addHighlight(chest, "Chest")
                                end
                            end
                        end
                    end
                end
                task.wait(0.2)
            end
        end)
        coroutine.resume(State.ChestESPUpdateCoroutine)
    else
        ClearESP("Chest")
        for _, conn in ipairs(State.ChestESPConnections) do
            conn:Disconnect()
        end
        State.ChestESPConnections = {}
        if State.ChestESPUpdateCoroutine then
            coroutine.close(State.ChestESPUpdateCoroutine)
            State.ChestESPUpdateCoroutine = nil
        end
    end
end

local function TogglePlayerESP(enabled)
    State.PlayerESP = enabled
    
    if enabled then
        for _, conn in ipairs(State.PlayerESPConnections) do
            conn:Disconnect()
        end
        State.PlayerESPConnections = {}
        
        local function addPlayerESP(player)
            if player == LocalPlayer then return end
            if player.Character and player.Character.Parent then
                addHighlight(player.Character, "Player")
            end
        end
        
        for _, player in ipairs(Players:GetPlayers()) do
            addPlayerESP(player)
            
            local charConn = player.CharacterAdded:Connect(function(char)
                if State.PlayerESP then
                    task.wait(0.2)
                    if char and char.Parent then
                        addHighlight(char, "Player")
                    end
                end
            end)
            table.insert(State.PlayerESPConnections, charConn)
            
            local charRemovedConn = player.CharacterRemoving:Connect(function(char)
                local highlight = char:FindFirstChild("ESPHighlight")
                if highlight then
                    highlight:Destroy()
                end
            end)
            table.insert(State.PlayerESPConnections, charRemovedConn)
        end
        
        local playerAddedConn = Players.PlayerAdded:Connect(function(player)
            if State.PlayerESP and player ~= LocalPlayer then
                local charConn = player.CharacterAdded:Connect(function(char)
                    if State.PlayerESP then
                        task.wait(0.2)
                        if char and char.Parent then
                            addHighlight(char, "Player")
                        end
                    end
                end)
                table.insert(State.PlayerESPConnections, charConn)
                
                addPlayerESP(player)
            end
        end)
        table.insert(State.PlayerESPConnections, playerAddedConn)
        
        if State.PlayerESPUpdateCoroutine then
            coroutine.close(State.PlayerESPUpdateCoroutine)
        end
        State.PlayerESPUpdateCoroutine = coroutine.create(function()
            while State.PlayerESP do
                for _, player in ipairs(Players:GetPlayers()) do
                    if player ~= LocalPlayer and player.Character and player.Character.Parent then
                        if not player.Character:FindFirstChild("ESPHighlight") then
                            addHighlight(player.Character, "Player")
                        end
                    end
                end
                task.wait(0.3)
            end
        end)
        coroutine.resume(State.PlayerESPUpdateCoroutine)
    else
        ClearESP("Player")
        for _, conn in ipairs(State.PlayerESPConnections) do
            conn:Disconnect()
        end
        State.PlayerESPConnections = {}
        if State.PlayerESPUpdateCoroutine then
            coroutine.close(State.PlayerESPUpdateCoroutine)
            State.PlayerESPUpdateCoroutine = nil
        end
    end
end

-- ========================================
-- UI CREATION
-- ========================================

local function CreateUI()
    -- Load 0verflow Hub UI
    local UILib = loadstring(game:HttpGet('https://raw.githubusercontent.com/pwd0kernel/0verflow/refs/heads/main/ui2.lua'))()
    local Window = UILib:CreateWindow("   Cut Grass - 0verflow Hub")

    -- Hacks Tab
    local HacksTab = Window:Tab("Hacks")
    
    local CuttingSection = HacksTab:Section("Grass Cutting")
    
    CutGrassExploit.Toggles.AutoCut = CuttingSection:Toggle("Auto Cut Grass", function(value)
        SetAutoCut(value)
        Window:Notify(value and "Auto Cut enabled" or "Auto Cut disabled", 2)
    end, {
        default = false,
        keybind = Enum.KeyCode.F1,
        color = Color3.fromRGB(100, 255, 100)
    })
    
    CutGrassExploit.Toggles.GrassVisibility = CuttingSection:Toggle("Grass Visibility", function(value)
        ToggleGrassVisibility(value)
        Window:Notify(value and "Grass visible" or "Grass hidden", 2)
    end, {
        default = true,
        color = Color3.fromRGB(255, 200, 100)
    })
    
    local MovementSection = HacksTab:Section("Movement & Combat")
    
    CutGrassExploit.Toggles.AntiTeleport = MovementSection:Toggle("Anti-Teleport", function(value)
        State.EnabledFlags["AntiTeleport"] = value
        if value then
            ActivateAntiTeleportForCharacter(LocalPlayer.Character)
            Window:Notify("Anti-Teleport enabled", 2)
        else
            DeactivateAntiTeleportForCharacter()
            Window:Notify("Anti-Teleport disabled", 2)
        end
    end, {
        default = false,
        keybind = Enum.KeyCode.F2,
        color = Color3.fromRGB(255, 150, 50)
    })
    
    MovementSection:Slider("Hitbox Size", 1, 50, CutGrassExploit.HitboxSize, function(value)
        CutGrassExploit.HitboxSize = value
        UpdateHitbox()
        if State.HitboxLoop then
            State.HitboxLoop:Disconnect()
            State.HitboxLoop = nil
        end
        if value > 1 then
            State.HitboxLoop = RunService.Heartbeat:Connect(function()
                UpdateHitbox()
            end)
        end
    end)
    
    MovementSection:Slider("Walk Speed", 16, 100, CutGrassExploit.WalkSpeed, function(value)
        CutGrassExploit.WalkSpeed = value
        SetWalkSpeed(value)
    end)
    
    MovementSection:Label("Anti-Teleport prevents being teleported back")
    MovementSection:Label("Enable to walk over cleared grass areas")
    
    -- Chests Tab
    local ChestsTab = Window:Tab("Chests")
    
    local CollectionSection = ChestsTab:Section("Auto Collection")
    
    local zones = GetAllLootZones()
    CollectionSection:Dropdown("Select Loot Zone", zones, CutGrassExploit.SelectedLootZone, function(option)
        CutGrassExploit.SelectedLootZone = option
        if State.EnabledFlags["AutoCollect"] then
            SetAutoCollect(false)
            SetAutoCollect(true)
        end
        Window:Notify("Zone changed to: " .. option, 2)
    end)
    
    CutGrassExploit.Toggles.AutoCollect = CollectionSection:Toggle("Auto Collect Chests", function(value)
        SetAutoCollect(value)
        ToggleGrassVisibility(not value)
        Window:Notify(value and "Auto Collect started" or "Auto Collect stopped", 2)
    end, {
        default = false,
        keybind = Enum.KeyCode.F3,
        color = Color3.fromRGB(100, 200, 255)
    })
    
    CollectionSection:Label("Auto collect will:")
    CollectionSection:Label("• Hide grass automatically")
    CollectionSection:Label("• Enable Anti-Teleport")
    CollectionSection:Label("• Teleport to chests in selected zone")
    
    -- Visuals Tab
    local VisualsTab = Window:Tab("Visuals")
    
    local ESPSection = VisualsTab:Section("ESP Features")
    
    CutGrassExploit.Toggles.ChestESP = ESPSection:Toggle("Chest ESP", function(value)
        ToggleChestESP(value)
        Window:Notify(value and "Chest ESP enabled" or "Chest ESP disabled", 2)
    end, {
        default = false,
        keybind = Enum.KeyCode.F4,
        color = Color3.fromRGB(255, 215, 0)
    })
    
    CutGrassExploit.Toggles.PlayerESP = ESPSection:Toggle("Player ESP", function(value)
        TogglePlayerESP(value)
        Window:Notify(value and "Player ESP enabled" or "Player ESP disabled", 2)
    end, {
        default = false,
        keybind = Enum.KeyCode.F5,
        color = Color3.fromRGB(255, 100, 100)
    })
    
    ESPSection:Label("Chest ESP colors indicate rarity:")
    ESPSection:Label("• Gray = Common")
    ESPSection:Label("• Green = Uncommon")
    ESPSection:Label("• Blue = Rare")
    ESPSection:Label("• Purple = Epic")
    ESPSection:Label("• Orange = Legendary")
    ESPSection:Label("• Red = Mythic")
    
    -- Info Tab
    local InfoTab = Window:Tab("Info")
    
    local InfoSection = InfoTab:Section("Script Information")
    
    InfoSection:Label("0verflow Hub - Cut Grass v2.0.0")
    InfoSection:Label("Author: buffer_0verflow")
    InfoSection:Label("Updated: 2025-08-10 16:00:24")
    InfoSection:Label("Features: Auto Cut + Collection + ESP")
    
    local ControlsSection = InfoTab:Section("Keybinds")
    
    ControlsSection:Label("F1 - Toggle Auto Cut")
    ControlsSection:Label("F2 - Toggle Anti-Teleport")
    ControlsSection:Label("F3 - Toggle Auto Collect")
    ControlsSection:Label("F4 - Toggle Chest ESP")
    ControlsSection:Label("F5 - Toggle Player ESP")
    
    -- Discord Section
    local DiscordSection = InfoTab:Section("Community")
    
    DiscordSection:Button("Join Our Discord", function()
        pcall(function()
            setclipboard("https://discord.gg/QmRXz3n9HQ")
            Window:Notify("Discord invite copied! Paste in browser to join.", 4)
        end)
    end)
    
    DiscordSection:Label("Discord: discord.gg/QmRXz3n9HQ")
    DiscordSection:Label("Get support, updates, and community!")
    
    return Window
end

-- ========================================
-- INITIALIZATION
-- ========================================

local function SetupCharacterListeners()
    LocalPlayer.CharacterAdded:Connect(function(character)
        if State.EnabledFlags["AntiTeleport"] then
            task.wait(0.5)
            ActivateAntiTeleportForCharacter(character)
        end
        if CutGrassExploit.HitboxSize > 1 then
            task.wait(0.5)
            UpdateHitbox()
        end
        SetWalkSpeed(CutGrassExploit.WalkSpeed)
    end)
end

-- Initialize
SetupCharacterListeners()
local UI = CreateUI()

-- Notify user
UI:Notify("0verflow Hub - Cut Grass v2.0.0 Loaded", 3)

-- Auto-start if configured
if _G.AutoStartCutGrass then
    if CutGrassExploit.Toggles.AutoCut then
        CutGrassExploit.Toggles.AutoCut:Set(true)
    end
    if CutGrassExploit.Toggles.AutoCollect then
        CutGrassExploit.Toggles.AutoCollect:Set(true)
    end
end

-- Return API for external use
return {
    -- Cutting Functions
    StartAutoCut = function()
        SetAutoCut(true)
    end,
    StopAutoCut = function()
        SetAutoCut(false)
    end,
    -- Collection Functions
    StartAutoCollect = function()
        SetAutoCollect(true)
    end,
    StopAutoCollect = function()
        SetAutoCollect(false)
    end,
    SetLootZone = function(zone)
        CutGrassExploit.SelectedLootZone = zone
    end,
    -- Grass Functions
    HideGrass = function()
        ToggleGrassVisibility(false)
    end,
    ShowGrass = function()
        ToggleGrassVisibility(true)
    end,
    -- Anti-Teleport Functions
    EnableAntiTeleport = function()
        State.EnabledFlags["AntiTeleport"] = true
        ActivateAntiTeleportForCharacter(LocalPlayer.Character)
    end,
    DisableAntiTeleport = function()
        State.EnabledFlags["AntiTeleport"] = false
        DeactivateAntiTeleportForCharacter()
    end,
    -- ESP Functions
    EnableChestESP = function()
        ToggleChestESP(true)
    end,
    DisableChestESP = function()
        ToggleChestESP(false)
    end,
    EnablePlayerESP = function()
        TogglePlayerESP(true)
    end,
    DisablePlayerESP = function()
        TogglePlayerESP(false)
    end,
    -- Settings
    SetHitboxSize = function(size)
        CutGrassExploit.HitboxSize = size
        UpdateHitbox()
    end,
    SetWalkSpeed = function(speed)
        CutGrassExploit.WalkSpeed = speed
        SetWalkSpeed(speed)
    end,
    -- Get current states
    GetStatus = function()
        return {
            autoCut = State.EnabledFlags["AutoCut"],
            autoCollect = State.EnabledFlags["AutoCollect"],
            antiTeleport = State.EnabledFlags["AntiTeleport"],
            chestESP = State.ChestESP,
            playerESP = State.PlayerESP,
            grassVisible = CutGrassExploit.GrassVisible,
            lootZone = CutGrassExploit.SelectedLootZone
        }
    end
}

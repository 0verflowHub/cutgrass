
--[[
    Cut Grass - 0verflow Hub

    Author: buffer_0verflow
]]

-- Main table to encapsulate the entire script
local CutGrass = {}
CutGrass.Name = "CutGrass"
CutGrass.Version = "1.0.0"
CutGrass.Author = "buffer_0verflow"

--// SERVICES //--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")

--// STATE //--
CutGrass.State = {
    EnabledFlags = {},
    AntiTeleportCharacterConnections = {}, -- Connections for the current character
    AutoCollectCoroutine = nil,
    AutoGrassDeleteCoroutine = nil,
    SelectedLootZone = "Main", -- Default loot zone
    HitboxSize = 1, -- Default hitbox size
    WalkSpeed = 16, -- Default walk speed
    ChestESP = false, -- Chest ESP toggle
    PlayerESP = false, -- Player ESP toggle
    ESPHighlights = {}, -- For ESP highlights
    ChestESPConnections = {}, -- For chest added connections
    PlayerESPConnections = {}, -- For player added connections
    ChestESPUpdateCoroutine = nil,
    PlayerESPUpdateCoroutine = nil,
    HitboxLoop = nil,
    GrassVisible = true, -- Grass visibility state
    OriginalGrassTransparencies = {}, -- Store original transparency values
    GrassMonitorCoroutine = nil, -- Coroutine for monitoring new grass
    GrassAddedConnections = {} -- Connections for grass monitoring
}

-- Tier colors based on HelperModule rarities
local tierColors = {
    [1] = Color3.fromRGB(150, 150, 150),
    [2] = Color3.fromRGB(30, 236, 0),
    [3] = Color3.fromRGB(53, 165, 255),
    [4] = Color3.fromRGB(167, 60, 255),
    [5] = Color3.fromRGB(255, 136, 0),
    [6] = Color3.fromRGB(255, 0, 0)
}

--// CORE MODULES //--
CutGrass.Modules = {}

--// DATA MODULE --//
CutGrass.Modules.Data = {}
function CutGrass.Modules.Data.GetAllLootZones()
    local zones = {}
    local lootZonesFolder = workspace:FindFirstChild("LootZones")
    if lootZonesFolder then
        for _, zone in ipairs(lootZonesFolder:GetChildren()) do
            table.insert(zones, zone.Name)
        end
    end
    if #zones == 0 then
        return {"Main"} -- Default if none are found
    end
    return zones
end

--// UI Library //--
CutGrass.Modules.UI = {}
function CutGrass.Modules.UI:Initialize()
    local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
    self.Window = Rayfield:CreateWindow({
        Name = "Cut Grass - 0verflow Hub",
        LoadingTitle = "Loading Cut Grass...",
        LoadingSubtitle = "by " .. CutGrass.Author,
        ConfigurationSaving = {
            Enabled = false,
        },
        Discord = {
            Enabled = true,
            Invite = "wjpTXW6nAR",
            RememberJoins = true
        },
        KeySystem = false,
    })
end

--// HACKS MODULE //--
CutGrass.Modules.Hacks = {}
function CutGrass.Modules.Hacks:SetAutoCut(enabled)
    CutGrass.State.EnabledFlags["AutoCut"] = enabled
    
    local WeaponSwingEvent = ReplicatedStorage.RemoteEvents.WeaponSwingEvent -- RemoteEvent 

    if enabled then
        WeaponSwingEvent:FireServer("HitboxStart")
    else
        WeaponSwingEvent:FireServer("HitboxEnd")
    end
end

function CutGrass.Modules.Hacks:ToggleGrassVisibility(visible)
    CutGrass.State.GrassVisible = visible
    local grassFolder = workspace:FindFirstChild("Grass")
    
    if visible then
        -- Stop monitoring new grass when showing grass
        self:StopGrassMonitoring()
        
        -- Restore all existing grass
        if grassFolder then
            for _, grass in pairs(grassFolder:GetChildren()) do
                if grass:IsA("BasePart") or grass:IsA("Model") then
                    self:SetGrassVisibility(grass, true)
                end
            end
        end
    else
        -- Hide all existing grass
        if grassFolder then
            for _, grass in pairs(grassFolder:GetChildren()) do
                if grass:IsA("BasePart") or grass:IsA("Model") then
                    self:SetGrassVisibility(grass, false)
                end
            end
        end
        
        -- Start monitoring for new grass to auto-hide
        self:StartGrassMonitoring()
    end
end

function CutGrass.Modules.Hacks:SetGrassVisibility(grass, visible)
    if grass:IsA("BasePart") then
        if visible then
            -- Restore original transparency
            local originalTransparency = CutGrass.State.OriginalGrassTransparencies[grass]
            grass.Transparency = originalTransparency or 0
        else
            -- Store original transparency and hide
            if not CutGrass.State.OriginalGrassTransparencies[grass] then
                CutGrass.State.OriginalGrassTransparencies[grass] = grass.Transparency
            end
            grass.Transparency = 1
            grass.CanCollide = false
        end
    elseif grass:IsA("Model") then
        -- Handle model by iterating through all parts
        for _, part in pairs(grass:GetDescendants()) do
            if part:IsA("BasePart") then
                if visible then
                    local originalTransparency = CutGrass.State.OriginalGrassTransparencies[part]
                    part.Transparency = originalTransparency or 0
                    part.CanCollide = true
                else
                    if not CutGrass.State.OriginalGrassTransparencies[part] then
                        CutGrass.State.OriginalGrassTransparencies[part] = part.Transparency
                    end
                    part.Transparency = 1
                    part.CanCollide = false
                end
            end
        end
    end
end

function CutGrass.Modules.Hacks:StartGrassMonitoring()
    -- Stop existing monitoring first
    self:StopGrassMonitoring()
    
    local grassFolder = workspace:FindFirstChild("Grass")
    if grassFolder then
        -- Connect to new grass being added
        local grassAddedConn = grassFolder.ChildAdded:Connect(function(newGrass)
            if not CutGrass.State.GrassVisible then
                -- Auto-hide new grass when visibility is off (no delay needed)
                self:SetGrassVisibility(newGrass, false)
            end
        end)
        table.insert(CutGrass.State.GrassAddedConnections, grassAddedConn)
    end
    
    -- Also monitor for the Grass folder being created/recreated
    local workspaceConn = workspace.ChildAdded:Connect(function(child)
        if child.Name == "Grass" and not CutGrass.State.GrassVisible then
            -- New grass folder created, monitor it and hide all grass
            for _, grass in pairs(child:GetChildren()) do
                self:SetGrassVisibility(grass, false)
            end
            
            -- Connect to future grass in this new folder
            local grassAddedConn = child.ChildAdded:Connect(function(newGrass)
                if not CutGrass.State.GrassVisible then
                    self:SetGrassVisibility(newGrass, false)
                end
            end)
            table.insert(CutGrass.State.GrassAddedConnections, grassAddedConn)
        end
    end)
    table.insert(CutGrass.State.GrassAddedConnections, workspaceConn)
end

function CutGrass.Modules.Hacks:StopGrassMonitoring()
    -- Disconnect all grass monitoring connections
    for _, conn in ipairs(CutGrass.State.GrassAddedConnections) do
        conn:Disconnect()
    end
    CutGrass.State.GrassAddedConnections = {}
end

function CutGrass.Modules.Hacks:DeleteAllGrass()
    -- Legacy function for compatibility - now just hides grass
    self:ToggleGrassVisibility(false)
end

function CutGrass.Modules.Hacks:SetAutoCollect(enabled)
    CutGrass.State.EnabledFlags["AutoCollect"] = enabled
    if enabled then
        -- Stop existing coroutines if they are running to prevent duplicates
        if CutGrass.State.AutoCollectCoroutine then coroutine.close(CutGrass.State.AutoCollectCoroutine) end
        if CutGrass.State.AutoGrassDeleteCoroutine then coroutine.close(CutGrass.State.AutoGrassDeleteCoroutine) end

        -- Start a new coroutine for continuously hiding grass
        CutGrass.State.AutoGrassDeleteCoroutine = coroutine.create(function()
            while CutGrass.State.EnabledFlags["AutoCollect"] do
                CutGrass.Modules.Hacks:ToggleGrassVisibility(false)
                task.wait(0.5) -- Reduced delay for faster grass hiding
            end
        end)

        -- Start a new coroutine for collecting chests
        CutGrass.State.AutoCollectCoroutine = coroutine.create(function()
            local LocalPlayer = Players.LocalPlayer
            local selectedZone = CutGrass.State.SelectedLootZone
            if type(selectedZone) ~= "string" then
                selectedZone = tostring(selectedZone) -- Fallback if not string
            end
            local lootZoneFolder = workspace.LootZones:FindFirstChild(selectedZone)
            if not lootZoneFolder or not lootZoneFolder:FindFirstChild("Loot") then
                warn("Selected loot zone or its 'Loot' subfolder not found: " .. tostring(CutGrass.State.SelectedLootZone))
                return
            end
            local LootFolder = lootZoneFolder.Loot
            local Offset = CFrame.new(0, 0, -2)
            local HoldDuration = 0.5  -- Reduced hold duration for faster interaction

            local function collect(item)
                if not CutGrass.State.EnabledFlags["AutoCollect"] then return false end
                if not item or not item.Parent then return true end

                local Character = LocalPlayer.Character
                if not Character then return false end
                local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")
                if not HumanoidRootPart then return false end

                local TargetPart = if item:IsA("BasePart") then item else (if item:IsA("Model") then (item.PrimaryPart or item:FindFirstChildOfClass("BasePart")) else nil)
                if not TargetPart or not TargetPart.Parent then return true end

                HumanoidRootPart.CFrame = TargetPart.CFrame * Offset
                task.wait(0.1)  -- Reduced wait for faster positioning

                -- Spam E key presses for faster/more reliable collection
                for i = 1, 5 do  -- Increased spam to 5 times for more reliability
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                    task.wait(0.05)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                    task.wait(0.05)
                end
                
                task.wait(0.1)  -- Minimal wait after spam
                return true
            end

            while CutGrass.State.EnabledFlags["AutoCollect"] do
                local children = LootFolder:GetChildren()
                if #children > 0 then
                    for _, item in ipairs(children) do
                        if not CutGrass.State.EnabledFlags["AutoCollect"] then break end
                        local success = collect(item)
                        if not success then break end
                        task.wait(0.1)  -- Further reduced delay between collecting each chest
                    end
                else
                    warn("No loot items found in zone: " .. tostring(CutGrass.State.SelectedLootZone) .. ". Waiting for spawn...")
                end
                task.wait(1)  -- Further reduced wait before re-scanning for new chests
            end
        end)

        coroutine.resume(CutGrass.State.AutoGrassDeleteCoroutine)
        coroutine.resume(CutGrass.State.AutoCollectCoroutine)
    else
        -- Stop both coroutines when the toggle is turned off
        if CutGrass.State.AutoCollectCoroutine then
            coroutine.close(CutGrass.State.AutoCollectCoroutine)
            CutGrass.State.AutoCollectCoroutine = nil
        end
        if CutGrass.State.AutoGrassDeleteCoroutine then
            coroutine.close(CutGrass.State.AutoGrassDeleteCoroutine)
            CutGrass.State.AutoGrassDeleteCoroutine = nil
        end
    end
end

function CutGrass.Modules.Hacks:UpdateHitbox()
    local LocalPlayer = Players.LocalPlayer
    local Character = LocalPlayer.Character
    if Character then
        local Tool = Character:FindFirstChildOfClass("Tool")
        if Tool then
            local Hitbox = Tool:FindFirstChild("Hitbox", true) or Tool:FindFirstChild("Blade", true) or Tool:FindFirstChild("Handle")
            if Hitbox and Hitbox:IsA("BasePart") then
                Hitbox.Size = Vector3.new(CutGrass.State.HitboxSize, CutGrass.State.HitboxSize, CutGrass.State.HitboxSize)
                Hitbox.Transparency = 0.5  -- Make it semi-transparent for visibility
            end
        end
    end
end

function CutGrass.Modules.Hacks:SetWalkSpeed(value)
    local LocalPlayer = Players.LocalPlayer
    local Character = LocalPlayer.Character
    if Character then
        local Humanoid = Character:FindFirstChildOfClass("Humanoid")
        if Humanoid then
            Humanoid.WalkSpeed = value
        end
    end
end

local function addHighlight(parent, type)
    if not parent or not parent.Parent then return end
    
    -- Remove existing highlight first
    local existingHighlight = parent:FindFirstChild("ESPHighlight")
    if existingHighlight then
        existingHighlight:Destroy()
    end
    
    local success, err = pcall(function()
        local tier = parent:GetAttribute("Tier") or 1
        local fillColor, outlineColor
        
        if type == "Player" then
            fillColor = Color3.fromRGB(255, 0, 0)  -- Red for players
            outlineColor = Color3.fromRGB(255, 255, 255)  -- White outline for players
        else
            fillColor = tierColors[tier] or Color3.fromRGB(255, 255, 255)
            outlineColor = Color3.fromRGB(255, 255, 0)  -- Yellow outline for chests
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
        
        -- Store reference
        table.insert(CutGrass.State.ESPHighlights, {Highlight = highlight, Type = type, Parent = parent})
        
        print("Added " .. type .. " ESP to:", parent.Name, "- Tier:", tier)
    end)
    
    if not success then
        warn("Failed to add highlight:", err)
    end
end

function CutGrass.Modules.Hacks:ToggleChestESP(enabled)
    CutGrass.State.ChestESP = enabled
    print("Chest ESP toggled:", enabled)
    
    if enabled then
        -- Clear existing connections first
        for _, conn in ipairs(CutGrass.State.ChestESPConnections) do
            conn:Disconnect()
        end
        CutGrass.State.ChestESPConnections = {}
        
        local lootZones = workspace:FindFirstChild("LootZones")
        print("LootZones found:", lootZones ~= nil)
        
        if lootZones then
            print("Processing", #lootZones:GetChildren(), "zones")
            
            -- Handle all existing zones and their loot
            for _, zone in ipairs(lootZones:GetChildren()) do
                print("Processing zone:", zone.Name)
                local lootFolder = zone:FindFirstChild("Loot")
                
                if lootFolder then
                    print("Found loot folder in", zone.Name, "with", #lootFolder:GetChildren(), "items")
                    
                    -- Add ESP to all existing chests
                    for _, chest in ipairs(lootFolder:GetChildren()) do
                        addHighlight(chest, "Chest")
                    end
                    
                    -- Connect to new chests being added
                    local chestConn = lootFolder.ChildAdded:Connect(function(newChest)
                        if CutGrass.State.ChestESP then
                            print("New chest added:", newChest.Name)
                            addHighlight(newChest, "Chest")
                        end
                    end)
                    table.insert(CutGrass.State.ChestESPConnections, chestConn)
                else
                    print("No loot folder found in zone:", zone.Name)
                end
                
                -- Connect to new loot folders being added to zones
                local lootConn = zone.ChildAdded:Connect(function(child)
                    if child.Name == "Loot" and CutGrass.State.ChestESP then
                        print("New loot folder added to zone:", zone.Name)
                        for _, chest in ipairs(child:GetChildren()) do
                            addHighlight(chest, "Chest")
                        end
                        
                        local chestConn = child.ChildAdded:Connect(function(newChest)
                            if CutGrass.State.ChestESP then
                                addHighlight(newChest, "Chest")
                            end
                        end)
                        table.insert(CutGrass.State.ChestESPConnections, chestConn)
                    end
                end)
                table.insert(CutGrass.State.ChestESPConnections, lootConn)
            end
            
            -- Connect to new zones being added
            local zoneAddedConn = lootZones.ChildAdded:Connect(function(newZone)
                if CutGrass.State.ChestESP then
                    print("New zone added:", newZone.Name)
                    local lootFolder = newZone:FindFirstChild("Loot")
                    if lootFolder then
                        for _, chest in ipairs(lootFolder:GetChildren()) do
                            addHighlight(chest, "Chest")
                        end
                        
                        local chestConn = lootFolder.ChildAdded:Connect(function(newChest)
                            if CutGrass.State.ChestESP then
                                addHighlight(newChest, "Chest")
                            end
                        end)
                        table.insert(CutGrass.State.ChestESPConnections, chestConn)
                    end
                    
                    local lootConn = newZone.ChildAdded:Connect(function(child)
                        if child.Name == "Loot" and CutGrass.State.ChestESP then
                            for _, chest in ipairs(child:GetChildren()) do
                                addHighlight(chest, "Chest")
                            end
                            local chestConn = child.ChildAdded:Connect(function(newChest)
                                if CutGrass.State.ChestESP then
                                    addHighlight(newChest, "Chest")
                                end
                            end)
                            table.insert(CutGrass.State.ChestESPConnections, chestConn)
                        end
                    end)
                    table.insert(CutGrass.State.ChestESPConnections, lootConn)
                end
            end)
            table.insert(CutGrass.State.ChestESPConnections, zoneAddedConn)
        end
        
        -- Start aggressive periodic update for missed chests
        if CutGrass.State.ChestESPUpdateCoroutine then
            coroutine.close(CutGrass.State.ChestESPUpdateCoroutine)
        end
        CutGrass.State.ChestESPUpdateCoroutine = coroutine.create(function()
            while CutGrass.State.ChestESP do
                local lootZones = workspace:FindFirstChild("LootZones")
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
        coroutine.resume(CutGrass.State.ChestESPUpdateCoroutine)
    else
        print("Disabling Chest ESP")
        CutGrass.Modules.Hacks:ClearESP("Chest")
        for _, conn in ipairs(CutGrass.State.ChestESPConnections) do
            conn:Disconnect()
        end
        CutGrass.State.ChestESPConnections = {}
        if CutGrass.State.ChestESPUpdateCoroutine then
            coroutine.close(CutGrass.State.ChestESPUpdateCoroutine)
            CutGrass.State.ChestESPUpdateCoroutine = nil
        end
    end
end

function CutGrass.Modules.Hacks:TogglePlayerESP(enabled)
    CutGrass.State.PlayerESP = enabled
    print("Player ESP toggled:", enabled)
    
    if enabled then
        -- Clear existing connections first
        for _, conn in ipairs(CutGrass.State.PlayerESPConnections) do
            conn:Disconnect()
        end
        CutGrass.State.PlayerESPConnections = {}
        
        print("Players found:", #Players:GetPlayers())
        
        -- Function to safely add player ESP
        local function addPlayerESP(player)
            if player == Players.LocalPlayer then return end
            if player.Character and player.Character.Parent then
                addHighlight(player.Character, "Player")
                print("Added ESP to player:", player.Name)
            end
        end
        
        -- Handle all existing players
        for _, player in ipairs(Players:GetPlayers()) do
            addPlayerESP(player)
            
            -- Connect to character respawning
            local charConn = player.CharacterAdded:Connect(function(char)
                if CutGrass.State.PlayerESP then
                    print("Character added for player:", player.Name)
                    task.wait(0.2) -- Wait for character to fully load
                    if char and char.Parent then
                        addHighlight(char, "Player")
                    end
                end
            end)
            table.insert(CutGrass.State.PlayerESPConnections, charConn)
            
            -- Connect to character removal to clean up
            local charRemovedConn = player.CharacterRemoving:Connect(function(char)
                local highlight = char:FindFirstChild("ESPHighlight")
                if highlight then
                    highlight:Destroy()
                end
            end)
            table.insert(CutGrass.State.PlayerESPConnections, charRemovedConn)
        end
        
        -- Connect to new players joining
        local playerAddedConn = Players.PlayerAdded:Connect(function(player)
            if CutGrass.State.PlayerESP and player ~= Players.LocalPlayer then
                print("New player joined:", player.Name)
                
                local charConn = player.CharacterAdded:Connect(function(char)
                    if CutGrass.State.PlayerESP then
                        print("Character spawned for new player:", player.Name)
                        task.wait(0.2)
                        if char and char.Parent then
                            addHighlight(char, "Player")
                        end
                    end
                end)
                table.insert(CutGrass.State.PlayerESPConnections, charConn)
                
                local charRemovedConn = player.CharacterRemoving:Connect(function(char)
                    local highlight = char:FindFirstChild("ESPHighlight")
                    if highlight then
                        highlight:Destroy()
                    end
                end)
                table.insert(CutGrass.State.PlayerESPConnections, charRemovedConn)
                
                -- If they already have a character, highlight it
                addPlayerESP(player)
            end
        end)
        table.insert(CutGrass.State.PlayerESPConnections, playerAddedConn)
        
        -- Connect to players leaving to clean up
        local playerRemovedConn = Players.PlayerRemoving:Connect(function(player)
            if player.Character then
                local highlight = player.Character:FindFirstChild("ESPHighlight")
                if highlight then
                    highlight:Destroy()
                end
            end
        end)
        table.insert(CutGrass.State.PlayerESPConnections, playerRemovedConn)
        
        -- More aggressive periodic update for missed players
        if CutGrass.State.PlayerESPUpdateCoroutine then
            coroutine.close(CutGrass.State.PlayerESPUpdateCoroutine)
        end
        CutGrass.State.PlayerESPUpdateCoroutine = coroutine.create(function()
            while CutGrass.State.PlayerESP do
                for _, player in ipairs(Players:GetPlayers()) do
                    if player ~= Players.LocalPlayer and player.Character and player.Character.Parent then
                        if not player.Character:FindFirstChild("ESPHighlight") then
                            print("Adding missed ESP for player:", player.Name)
                            addHighlight(player.Character, "Player")
                        end
                    end
                end
                task.wait(0.3) -- Check every 0.3 seconds
            end
        end)
        coroutine.resume(CutGrass.State.PlayerESPUpdateCoroutine)
    else
        print("Disabling Player ESP")
        CutGrass.Modules.Hacks:ClearESP("Player")
        for _, conn in ipairs(CutGrass.State.PlayerESPConnections) do
            conn:Disconnect()
        end
        CutGrass.State.PlayerESPConnections = {}
        if CutGrass.State.PlayerESPUpdateCoroutine then
            coroutine.close(CutGrass.State.PlayerESPUpdateCoroutine)
            CutGrass.State.PlayerESPUpdateCoroutine = nil
        end
    end
end

function CutGrass.Modules.Hacks:ClearESP(type)
    print("Clearing ESP for type:", type)
    local count = 0
    for i = #CutGrass.State.ESPHighlights, 1, -1 do
        local entry = CutGrass.State.ESPHighlights[i]
        if entry.Type == type then
            if entry.Highlight and entry.Highlight.Parent then
                pcall(function()
                    entry.Highlight:Destroy()
                    count = count + 1
                end)
            end
            table.remove(CutGrass.State.ESPHighlights, i)
        end
    end
    print("Cleared", count, type, "ESP highlights")
    
    -- Also clear from workspace directly as backup
    if type == "Chest" then
        local lootZones = workspace:FindFirstChild("LootZones")
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



--// MAIN SCRIPT LOGIC //--
function CutGrass:Initialize()
    self.Modules.UI:Initialize()
    self:CreateTabs()
    self:SetupCharacterListeners()
end

function CutGrass:SetupCharacterListeners()
    local lplr = Players.LocalPlayer
    lplr.CharacterAdded:Connect(function(character)
        if CutGrass.State.EnabledFlags["AntiTeleport"] then
            task.wait(0.5)
            CutGrass:ActivateAntiTeleportForCharacter(character)
        end
        if CutGrass.State.HitboxSize > 1 then
            task.wait(0.5)
            CutGrass.Modules.Hacks:UpdateHitbox()
        end
        CutGrass.Modules.Hacks:SetWalkSpeed(CutGrass.State.WalkSpeed)
    end)
end

function CutGrass:CreateTabs()
    local window = self.Modules.UI.Window
    self:CreateHacksTab(window)
    self:CreateChestsTab(window)
    self:CreateVisualsTab(window)
end

function CutGrass:CreateHacksTab(window)
    local hacksTab = window:CreateTab("Hacks", nil)
    hacksTab:CreateToggle({
        Name = "Auto Cut Grass",
        CurrentValue = false,
        Flag = "AutoCutGrassToggle",
        Callback = function(value)
            CutGrass.Modules.Hacks:SetAutoCut(value)
        end,
    })

    hacksTab:CreateToggle({
        Name = "Toggle Grass Visibility",
        CurrentValue = CutGrass.State.GrassVisible,
        Flag = "ToggleGrass",
        Callback = function(Value)
            CutGrass.Modules.Hacks:ToggleGrassVisibility(Value)
        end,
    })

    hacksTab:CreateParagraph({
        Title = "Anti-Teleport",
        Content = "Enable this to walk over cleared grass areas and collect chests without being teleported back.",
    })

    hacksTab:CreateToggle({
        Name = "Enable Anti-Teleport",
        CurrentValue = false,
        Flag = "AntiTeleportToggle",
        Callback = function(value)
            CutGrass.State.EnabledFlags["AntiTeleport"] = value
            if value then
                CutGrass:ActivateAntiTeleportForCharacter(Players.LocalPlayer.Character)
            else
                CutGrass:DeactivateAntiTeleportForCharacter()
            end
        end,
    })

    hacksTab:CreateSlider({
        Name = "Hitbox Size",
        Range = {1, 50},
        Increment = 1,
        Suffix = "Studs",
        CurrentValue = 1,
        Flag = "HitboxSizeSlider",
        Callback = function(value)
            CutGrass.State.HitboxSize = value
            CutGrass.Modules.Hacks:UpdateHitbox()
            if CutGrass.State.HitboxLoop then
                CutGrass.State.HitboxLoop:Disconnect()
                CutGrass.State.HitboxLoop = nil
            end
            if value > 1 then
                CutGrass.State.HitboxLoop = RunService.Heartbeat:Connect(function()
                    CutGrass.Modules.Hacks:UpdateHitbox()
                end)
            end
        end,
    })

    hacksTab:CreateSlider({
        Name = "Walk Speed",
        Range = {16, 100},
        Increment = 1,
        Suffix = "Speed",
        CurrentValue = 16,
        Flag = "WalkSpeedSlider",
        Callback = function(value)
            CutGrass.State.WalkSpeed = value
            CutGrass.Modules.Hacks:SetWalkSpeed(value)
        end,
    })


end

function CutGrass:CreateChestsTab(window)
    local chestsTab = window:CreateTab("Chests", nil)

    chestsTab:CreateDropdown({
        Name = "Select Loot Zone",
        Options = CutGrass.Modules.Data.GetAllLootZones(),
        CurrentOption = CutGrass.State.SelectedLootZone,
        MultipleOptions = false,  -- Ensure single selection
        Flag = "LootZoneDropdown",
        Callback = function(option)
            CutGrass.State.SelectedLootZone = (type(option) == "table" and option[1]) or option  -- Handle if table
            -- Restart auto collect if enabled to switch to new zone
            if CutGrass.State.EnabledFlags["AutoCollect"] then
                CutGrass.Modules.Hacks:SetAutoCollect(false)
                CutGrass.Modules.Hacks:SetAutoCollect(true)
            end
        end,
    })

    chestsTab:CreateToggle({
        Name = "Auto Collect Chests",
        CurrentValue = false,
        Flag = "AutoCollectChestsToggle",
        Callback = function(value)
            CutGrass.Modules.Hacks:SetAutoCollect(value)
        end,
    })
end

function CutGrass:CreateVisualsTab(window)
    local visualsTab = window:CreateTab("Visuals", nil)

    visualsTab:CreateToggle({
        Name = "Chest ESP",
        CurrentValue = false,
        Flag = "ChestESPToggle",
        Callback = function(value)
            CutGrass.Modules.Hacks:ToggleChestESP(value)
        end,
    })

    visualsTab:CreateToggle({
        Name = "Player ESP",
        CurrentValue = false,
        Flag = "PlayerESPToggle",
        Callback = function(value)
            CutGrass.Modules.Hacks:TogglePlayerESP(value)
        end,
    })
end

--// ANTI-TELEPORT-BACK //--
function CutGrass:ActivateAntiTeleportForCharacter(character)
    self:DeactivateAntiTeleportForCharacter()
    if not character then return end
    local humanoid = character:FindFirstChildOfClass('Humanoid')
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not (humanoid and rootPart) then return end

    local lastCF, stop

    local heartbeatConn = game:GetService('RunService').Heartbeat:Connect(function()
        if stop then return end
        if rootPart and rootPart.Parent then
            lastCF = rootPart.CFrame
        end
    end)
    table.insert(self.State.AntiTeleportCharacterConnections, heartbeatConn)

    local cframeConn = rootPart:GetPropertyChangedSignal('CFrame'):Connect(function()
        stop = true
        if rootPart and rootPart.Parent then
            rootPart.CFrame = lastCF
        end
        game:GetService('RunService').Heartbeat:Wait()
        stop = false
    end)
    table.insert(self.State.AntiTeleportCharacterConnections, cframeConn)

    local diedConn = humanoid.Died:Connect(function()
        self:DeactivateAntiTeleportForCharacter()
    end)
    table.insert(self.State.AntiTeleportCharacterConnections, diedConn)
end

function CutGrass:DeactivateAntiTeleportForCharacter()
    for _, connection in ipairs(self.State.AntiTeleportCharacterConnections) do
        connection:Disconnect()
    end
    self.State.AntiTeleportCharacterConnections = {}
end

--// INITIALIZE SCRIPT //--
CutGrass:Initialize()

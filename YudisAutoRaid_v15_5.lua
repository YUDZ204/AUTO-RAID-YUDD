-- YUDIS AUTO RAID v15.5
-- Based on v15.4: targeting/filter + long-range TP + debris dodge retained.
-- Removed script-based Replay/Ready clicking; use the game's native auto-replay.
-- LOW FLY + NEAREST CENTIPEDE + DEBRIS DODGE + LONG-RANGE TP
-- Paste this entire script into Delta.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
if not player then return end

local pg = player:WaitForChild("PlayerGui")
for _, oldName in ipairs({"YudisAutoRaid14", "YudisAutoRaid15", "YudisAutoRaid15_1", "YudisAutoRaid15_2", "YudisAutoRaid15_3", "YudisAutoRaid15_4", "YudisAutoRaid15_5"}) do
    local old = pg:FindFirstChild(oldName)
    if old then old:Destroy() end
end

-- SETTINGS
local TRIGGER_DISTANCE = 8
local SAFE_DISTANCE = 13
local FOLLOW_HEIGHT = 3
local FOLLOW_SPEED = 55
local TELEPORT_DISTANCE = 100
local TELEPORT_COOLDOWN = 2
local DODGE_SPEED = 80
local DODGE_UP_SPEED = 2
local SCAN_INTERVAL = 0.5

-- GUI
local gui = Instance.new("ScreenGui")
gui.Name = "YudisAutoRaid15_5"
gui.ResetOnSpawn = false
gui.DisplayOrder = 1004
gui.Parent = pg

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(310, 225)
frame.Position = UDim2.new(0.5, -155, 0.2, 0)
frame.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 9)

local title = Instance.new("TextButton")
title.Size = UDim2.new(1, -40, 0, 30)
title.Position = UDim2.fromOffset(8, 2)
title.BackgroundTransparency = 1
title.Text = "YUDIS | AUTO RAID v15.5"
title.TextColor3 = Color3.fromRGB(190, 160, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(28, 26)
close.Position = UDim2.new(1, -31, 0, 3)
close.Text = "X"
close.TextColor3 = Color3.new(1, 1, 1)
close.BackgroundColor3 = Color3.fromRGB(170, 55, 65)
close.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, 25)
status.Position = UDim2.fromOffset(8, 33)
status.BackgroundColor3 = Color3.fromRGB(35, 45, 38)
status.TextColor3 = Color3.fromRGB(130, 255, 160)
status.Text = "MONITORING"
status.TextSize = 11
status.Font = Enum.Font.GothamBold
status.Parent = frame

local output = Instance.new("TextLabel")
output.Size = UDim2.new(1, -16, 0, 95)
output.Position = UDim2.fromOffset(8, 62)
output.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
output.TextColor3 = Color3.fromRGB(235, 235, 240)
output.TextSize = 11
output.Font = Enum.Font.Code
output.TextXAlignment = Enum.TextXAlignment.Left
output.TextYAlignment = Enum.TextYAlignment.Top
output.TextWrapped = true
output.Text = "Searching for Centipede..."
output.Parent = frame

local toggle = Instance.new("TextButton")
toggle.Size = UDim2.new(1, -16, 0, 29)
toggle.Position = UDim2.new(0, 8, 1, -35)
toggle.Text = "AUTO: OFF"
toggle.TextColor3 = Color3.new(1, 1, 1)
toggle.BackgroundColor3 = Color3.fromRGB(65, 55, 90)
toggle.Font = Enum.Font.GothamBold
toggle.TextSize = 12
toggle.Parent = frame

-- DRAG GUI WITH TOUCH / MOUSE
local dragging = false
local dragInput, dragStart, startPos

title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragInput = input
        dragStart = input.Position
        startPos = frame.Position
    end
end)

local dragChanged = UIS.InputChanged:Connect(function(input)
    if dragging and (
        input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseMovement
    ) then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

local dragEnded = UIS.InputEnded:Connect(function(input)
    if input == dragInput
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
        dragInput = nil
    end
end)

-- GENERAL STATE
local running = true
local autoOn = false
local state = "FOLLOW"
local zones = {}
local lastZoneScan = 0
local lastTeleportAt = -math.huge

local mover
local moverRoot

-- FIND NEAREST ENEMY CENTIPEDE (EXCLUDE OWN PLACED UNIT)
local findCentipedeLastScan = 0
local findCentipedeCached = nil

local function isLikelyPlayerUnit(obj)
    local node = obj

    while node and node ~= Workspace do
        local name = string.lower(node.Name)

        -- Exclude the user's own Ken unit specifically.
        -- The UI identifies it as PlacedUnit_Kaneki (Centipede), so ignore
        -- this exact unit name/ancestor without excluding other Centipedes.
        if name == "placedunit_kaneki" then
            return true
        end

        -- Exclude clearly named player-owned unit containers only.
        -- Do NOT exclude PlayerOnlyEnemiesHolder as a whole: raid enemies
        -- may also be parented there, which would hide every valid target.
        if string.find(name, "placedunits", 1, true)
        or string.find(name, "playerunits", 1, true)
        or string.find(name, "summonedunits", 1, true)
        or string.find(name, "ownedunits", 1, true)
        or string.find(name, "unittemplate", 1, true) then
            return true
        end

        -- If the game exposes ownership as attributes, exclude this player's unit.
        local ok, owned = pcall(function()
            local ownerUserId = node:GetAttribute("OwnerUserId")
                or node:GetAttribute("OwnerUserID")
                or node:GetAttribute("UserId")
                or node:GetAttribute("UserID")
            local ownerName = node:GetAttribute("OwnerName")
                or node:GetAttribute("PlayerName")

            return (tonumber(ownerUserId) == player.UserId)
                or (type(ownerName) == "string"
                    and string.lower(ownerName) == string.lower(player.Name))
        end)

        if ok and owned then
            return true
        end

        node = node.Parent
    end

    return false
end

local function getCentipedePosition(obj)
    local ok, pos = pcall(function()
        if obj:IsA("BasePart") then
            return obj.Position
        elseif obj:IsA("Model") then
            local part = obj:FindFirstChild("HumanoidRootPart", true)
                or obj.PrimaryPart

            if part and part:IsA("BasePart") then
                return part.Position
            end

            return obj:GetPivot().Position
        end
    end)

    if ok then
        return pos
    end

    return nil
end

local function findCentipede()
    -- Cache the scan briefly to avoid walking the whole Workspace every frame.
    local now = os.clock()
    if now - findCentipedeLastScan < SCAN_INTERVAL then
        if findCentipedeCached and findCentipedeCached.Parent then
            return findCentipedeCached
        elseif not findCentipedeCached then
            return nil
        end
    end
    findCentipedeLastScan = now

    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        findCentipedeCached = nil
        return nil
    end

    local nearest = nil
    local nearestDistance = math.huge
    local seen = {}

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if string.lower(obj.Name) == "centipede"
        and (obj:IsA("Model") or obj:IsA("BasePart"))
        and not seen[obj] then
            seen[obj] = true

            if not isLikelyPlayerUnit(obj) then
                -- Ignore dead targets when a Humanoid is present.
                local hum = obj:FindFirstChildWhichIsA("Humanoid", true)
                if not hum or hum.Health > 0 then
                    local pos = getCentipedePosition(obj)
                    if pos then
                        local distance = (pos - root.Position).Magnitude
                        if distance < nearestDistance then
                            nearestDistance = distance
                            nearest = obj
                        end
                    end
                end
            end
        end
    end

    findCentipedeCached = nearest
    return nearest
end

local function targetPosition(obj)
    if not obj or not obj.Parent then
        return nil
    end

    local ok, result = pcall(function()
        if obj:IsA("BasePart") then
            return obj.Position
        elseif obj:IsA("Model") then
            local part =
                obj:FindFirstChild("HumanoidRootPart", true)
                or obj.PrimaryPart

            if part and part:IsA("BasePart") then
                return part.Position
            end

            return obj:GetPivot().Position
        end
    end)

    if ok then
        return result
    end

    return nil
end

-- ZONE DETECTION
local function getBounds(obj)
    local ok, pos, size = pcall(function()
        if obj:IsA("BasePart") then
            return obj.Position, obj.Size
        elseif obj:IsA("Model") then
            local cf, s = obj:GetBoundingBox()
            return cf.Position, s
        end
    end)

    if ok then
        return pos, size
    end

    return nil
end

local function isRed(part)
    local c = part.Color
    return c.R > 0.55
        and c.R > c.G * 1.5
        and c.R > c.B * 1.5
end

local function isZoneName(name)
    name = string.lower(name)

    return string.find(name, "debriszone", 1, true) ~= nil
        or string.find(name, "debrizone", 1, true) ~= nil
end

local function scanZones()
    local map = Workspace:FindFirstChild("MapModel")
    local debrisFolder = map and map:FindFirstChild("Debris")
    local raid = Workspace:FindFirstChild("RaidDebrisVfx")

    local roots = {}

    if map then
        table.insert(roots, map)
    end

    if raid then
        table.insert(roots, raid)
    end

    if #roots == 0 then
        table.insert(roots, Workspace)
    end

    local found = {}
    local seen = {}

    for _, folder in ipairs(roots) do
        for _, obj in ipairs(folder:GetDescendants()) do
            if not seen[obj] then
                seen[obj] = true

                local namedZone =
                    (obj:IsA("BasePart") or obj:IsA("Model"))
                    and isZoneName(obj.Name)

                local redPad = false

                if obj:IsA("BasePart")
                and debrisFolder
                and obj:IsDescendantOf(debrisFolder) then
                    redPad = isRed(obj)
                        and obj.Size.X >= 5
                        and obj.Size.Z >= 5
                        and obj.Size.Y <= 8
                end

                if namedZone or redPad then
                    local pos, size = getBounds(obj)

                    if pos and size
                    and size.X > 0
                    and size.Z > 0
                    and size.X <= 150
                    and size.Z <= 150 then
                        table.insert(found, {
                            obj = obj,
                            name = obj.Name,
                            pos = pos,
                            size = size
                        })
                    end
                end
            end
        end
    end

    zones = found
    lastZoneScan = os.clock()
end

-- HORIZONTAL DISTANCE FROM ZONE EDGE
local function edgeDistance(rootPos, zone)
    local dx = math.max(
        math.abs(rootPos.X - zone.pos.X) - zone.size.X / 2,
        0
    )

    local dz = math.max(
        math.abs(rootPos.Z - zone.pos.Z) - zone.size.Z / 2,
        0
    )

    return math.sqrt(dx * dx + dz * dz)
end

-- LOW-FLY MOVEMENT
local function stopMover()
    if mover then
        mover:Destroy()
        mover = nil
        moverRoot = nil
    end
end

local function getMover(root)
    if mover and moverRoot ~= root then
        stopMover()
    end

    if not mover then
        mover = Instance.new("BodyVelocity")
        mover.Name = "YudisFlightMover"
        mover.MaxForce = Vector3.new(1e8, 1e8, 1e8)
        mover.P = 20000
        mover.Velocity = Vector3.zero
        mover.Parent = root
        moverRoot = root
    end

    return mover
end

toggle.Activated:Connect(function()
    autoOn = not autoOn

    toggle.Text = autoOn and "AUTO: ON" or "AUTO: OFF"
    toggle.BackgroundColor3 = autoOn
        and Color3.fromRGB(40, 115, 70)
        or Color3.fromRGB(65, 55, 90)

    if not autoOn then
        state = "FOLLOW"
        stopMover()
    end
end)

-- UI button automation is disabled; native in-game replay handles the round flow.

-- MAIN LOOP: DODGE HAS PRIORITY OVER FOLLOW
local function cleanup()
    running = false
    autoOn = false
    stopMover()

    dragChanged:Disconnect()
    dragEnded:Disconnect()

    gui:Destroy()
end

close.Activated:Connect(cleanup)

task.spawn(function()
    while running and gui.Parent do
        local character = player.Character
        local root = character
            and character:FindFirstChild("HumanoidRootPart")

        if not root then
            status.Text = "WAITING FOR CHARACTER"
            stopMover()
        else
            if os.clock() - lastZoneScan >= SCAN_INTERVAL then
                scanZones()
            end

            local nearest
            local nearestEdge = math.huge

            for _, zone in ipairs(zones) do
                if zone.obj and zone.obj.Parent then
                    local d = edgeDistance(root.Position, zone)

                    if d < nearestEdge then
                        nearestEdge = d
                        nearest = zone
                    end
                end
            end

            if state ~= "DODGE"
            and nearest
            and nearestEdge <= TRIGGER_DISTANCE then
                state = "DODGE"
            elseif state == "DODGE"
            and (not nearest or nearestEdge >= SAFE_DISTANCE) then
                state = "FOLLOW"
            end

            local target = findCentipede()
            local mobPos = targetPosition(target)

            if not autoOn then
                status.Text = "MONITORING | AUTO OFF"

                output.Text = string.format(
                    "Target: %s\nZones found: %d\nNearest edge: %s\nTP: %d studs / %ds",
                    mobPos and "Centipede found" or "not found",
                    #zones,
                    nearest
                        and string.format("%.1f studs", nearestEdge)
                        or "none detected",
                    TELEPORT_DISTANCE,
                    TELEPORT_COOLDOWN
                )

                stopMover()
            else
                local velocity = getMover(root)

                if state == "DODGE" and nearest then
                    local away = Vector3.new(
                        root.Position.X - nearest.pos.X,
                        0,
                        root.Position.Z - nearest.pos.Z
                    )

                    if away.Magnitude < 0.1 then
                        away = Vector3.new(1, 0, 0)
                    end

                    velocity.Velocity =
                        away.Unit * DODGE_SPEED
                        + Vector3.new(0, DODGE_UP_SPEED, 0)

                    status.Text = "DODGING DEBRIS!"
                    status.BackgroundColor3 =
                        Color3.fromRGB(110, 45, 35)
                    status.TextColor3 =
                        Color3.fromRGB(255, 220, 130)

                elseif mobPos then
                    local destination = mobPos + Vector3.new(0, FOLLOW_HEIGHT, 0)
                    local delta = destination - root.Position
                    local now = os.clock()
                    local didTeleport = false

                    -- TP only when far away, not while dodging or near a danger zone.
                    if state ~= "DODGE"
                    and delta.Magnitude >= TELEPORT_DISTANCE
                    and now - lastTeleportAt >= TELEPORT_COOLDOWN
                    and (not nearest or nearestEdge > TRIGGER_DISTANCE) then
                        local tpOK = pcall(function()
                            root.CFrame = CFrame.new(destination)
                            root.AssemblyLinearVelocity = Vector3.zero
                        end)

                        if tpOK then
                            lastTeleportAt = now
                            velocity.Velocity = Vector3.zero
                            didTeleport = true
                        end
                    end

                    if not didTeleport then
                        if delta.Magnitude > 5 then
                            velocity.Velocity = delta.Unit * FOLLOW_SPEED
                        else
                            velocity.Velocity = Vector3.zero
                        end
                    end

                    status.Text = didTeleport and "TP TO CENTIPEDE" or "FOLLOWING CENTIPEDE"
                    status.BackgroundColor3 = Color3.fromRGB(35, 65, 45)
                    status.TextColor3 = Color3.fromRGB(130, 255, 160)

                else
                    velocity.Velocity = Vector3.zero
                    status.Text = "CENTIPEDE NOT FOUND"
                    status.BackgroundColor3 =
                        Color3.fromRGB(80, 60, 35)
                    status.TextColor3 =
                        Color3.fromRGB(255, 220, 130)
                end

                output.Text = string.format(
                    "State: %s\nTarget: %s\nZones: %d\nNearest edge: %s\nTP: %d studs / %ds\nTrigger: %d | Safe: %d",
                    state,
                    mobPos and "Centipede" or "not found",
                    #zones,
                    nearest
                        and string.format("%.1f studs", nearestEdge)
                        or "none detected",
                    TELEPORT_DISTANCE,
                    TELEPORT_COOLDOWN,
                    TRIGGER_DISTANCE,
                    SAFE_DISTANCE
                )
            end
        end

        task.wait(0.12)
    end
end)

print("[YUDIS AUTO RAID v15.5] Loaded - UI clicker disabled")

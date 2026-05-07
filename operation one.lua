--!native
--!optimize 2

---- environment ----
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local MemoryReadF32 = memory.readf32
local MathRound = math.round
local MathSqrt = math.sqrt
local MathFloor = math.floor
local MathClamp = math.clamp
local TableInsert = table.insert
local TableConcat = table.concat
local TableClear = table.clear
local StringFormat = string.format
local VectorMagnitude = vector.magnitude
local VectorCreate = vector.create
local Pcall = pcall
local OsClock = os.clock

---- constants ----
local OUTLINE_COLOR_GREEN_OFFSET: number = 0xEC
local TARGET_GREEN_VALUE: number = 150

local DEBUG_MODE: boolean = false
local DRONE_MAX_DISTANCE: number = 2000
local DRONE_SIZE_MIN: number = 50
local DRONE_SIZE_MAX: number = 200
local DRONE_SIZE_DIVISOR: number = 2000

local PART_NAMES: {string} = {"head", "torso", "arm1", "arm2", "leg1", "leg2", "hip1", "hip2", "shoulder1", "shoulder2"}

local FALLBACK_MAP: {[string]: {string}} = {
    arm2 = {"arm1", "torso", "head"},
    arm1 = {"arm2", "torso", "head"},
    leg2 = {"leg1", "torso", "head"},
    leg1 = {"leg2", "torso", "head"},
    hip1 = {"leg1", "torso", "head"},
    hip2 = {"leg2", "torso", "head"},
    shoulder1 = {"arm1", "torso", "head"},
    shoulder2 = {"arm2", "torso", "head"},
    torso = {"head"},
    head = {"torso"}
}

local FULL_BODY_MAP: {[string]: string} = {
    head = "Head",
    torso = "Torso",
    arm1 = "Left Arm",
    arm2 = "Right Arm",
    leg1 = "Left Leg",
    leg2 = "Right Leg",
    hip1 = "LeftUpperLeg",
    hip2 = "RightUpperLeg",
    shoulder1 = "LeftUpperArm",
    shoulder2 = "RightUpperArm"
}

---- types ----
export type BodyParts = {
    head: BasePart?,
    torso: BasePart?,
    arm1: BasePart?,
    arm2: BasePart?,
    leg1: BasePart?,
    leg2: BasePart?,
    hip1: BasePart?,
    hip2: BasePart?,
    shoulder1: BasePart?,
    shoulder2: BasePart?
}

export type TrackedModel = {
    model: Model,
    parts: BodyParts,
    isLocal: boolean
}

export type DroneData = {
    part: BasePart,
    pos: Vector3?,
    dist: number?
}

export type DroneDrawing = {
    square: any,
    text: any
}

---- variables ----
local LocalPlayer: Player? = Players.LocalPlayer
local Camera: Camera? = Workspace.CurrentCamera

local TrackedModels: {[number]: TrackedModel} = {}
local CachedDronePositions: {[number]: DroneData} = {}
local DroneDrawings: {[number]: DroneDrawing} = {}

---- helper functions ----

local function DebugPrint(...: any): ()
    if DEBUG_MODE then
        print(StringFormat("[%.2fs]", OsClock()), ...)
    end
end

local function ValidateParent(instance: Instance?): boolean
    if not instance then return false end
    
    local success: boolean, parent: Instance? = Pcall(function()
        return instance.Parent
    end)
    
    return success and parent ~= nil
end

local function SafeFindFirstChild(instance: Instance?, name: string): Instance?
    if not instance or not ValidateParent(instance) then return nil end
    
    local success: boolean, result: Instance? = Pcall(function()
        return instance:FindFirstChild(name)
    end)
    
    return success and result or nil
end

local function SafeGetChildren(instance: Instance?): {Instance}?
    if not instance or not ValidateParent(instance) then return nil end
    
    local success: boolean, result: {Instance}? = Pcall(function()
        return instance:GetChildren()
    end)
    
    return success and result or nil
end

local function SafeFindFirstChildOfClass(instance: Instance?, className: string): Instance?
    if not instance or not ValidateParent(instance) then return nil end
    
    local success: boolean, result: Instance? = Pcall(function()
        return instance:FindFirstChildOfClass(className)
    end)
    
    return success and result or nil
end

local function GetInstanceID(instance: Instance?): number?
    if not instance or not ValidateParent(instance) then return nil end
    
    local success: boolean, data: any = Pcall(function()
        return instance.Data
    end)
    
    if not success or not data then return nil end
    
    local id: number? = tonumber(data)
    return (id and id ~= 0) and id or nil
end

local function GetInstanceName(instance: Instance?): string?
    if not instance or not ValidateParent(instance) then return nil end
    
    local success: boolean, name: string? = Pcall(function()
        return instance.Name
    end)
    
    return success and name or nil
end

local function GetClassName(instance: Instance?): string?
    if not instance or not ValidateParent(instance) then return nil end
    
    local success: boolean, className: string? = Pcall(function()
        return instance.ClassName
    end)
    
    return success and className or nil
end

local function HasAnyModelChildren(model: Model): boolean
    if not ValidateParent(model) then return false end
    
    local children: {Instance}? = SafeGetChildren(model)
    if not children then return false end
    
    for i = 1, #children do
        local child: Instance = children[i]
        local className: string? = GetClassName(child)
        if className == "Model" then
            return true
        end
    end
    
    return false
end

local function IsTeammate(model: Model): boolean
	if not ValidateParent(model) then
		return false
	end

	local head: Instance? = model:FindFirstChild("head")
	if not head then
		return false
	end

	local usernameGui: Instance? = head:FindFirstChild("Username")
	if usernameGui and GetClassName(usernameGui) == "BillboardGui" then
		DebugPrint("Model has Username BillboardGui - Teammate detected")
		return true
	end

	return false
end


local function GetBodyParts(model: Model): BodyParts?
    if not ValidateParent(model) then
        DebugPrint("GetBodyParts: Invalid model or no parent")
        return nil
    end
    
    local parts: BodyParts = {}
    local foundParts: {string} = {}
    
    for i = 1, #PART_NAMES do
        local pname: string = PART_NAMES[i]
        local part: Instance? = SafeFindFirstChild(model, pname)
        if part and ValidateParent(part) then
            (parts :: any)[pname] = part
            TableInsert(foundParts, pname)
        end
    end
    
    local modelName: string? = GetInstanceName(model)
    DebugPrint("GetBodyParts for", modelName or "Unknown", "- Found parts:", TableConcat(foundParts, ", "))
    
    for i = 1, #PART_NAMES do
        local pname: string = PART_NAMES[i]
        if not (parts :: any)[pname] and FALLBACK_MAP[pname] then
            for j = 1, #FALLBACK_MAP[pname] do
                local fallbackName: string = FALLBACK_MAP[pname][j]
                if (parts :: any)[fallbackName] then
                    (parts :: any)[pname] = (parts :: any)[fallbackName]
                    DebugPrint("Applied fallback:", pname, "->", fallbackName)
                    break
                end
            end
        end
    end
    
    if not parts.head and not parts.torso then
        DebugPrint("GetBodyParts: Missing critical parts (head/torso)")
        return nil
    end
    
    return parts
end

local function BuildModelData(model: Model, parts: BodyParts, uniqueName: string): any
    local bodyPartsData: {any} = {
        {name = "LowerTorso", part = parts.torso},
        {name = "LeftUpperLeg", part = parts.hip1},
        {name = "LeftLowerLeg", part = parts.leg1},
        {name = "RightUpperLeg", part = parts.hip2},
        {name = "RightLowerLeg", part = parts.leg2},
        {name = "LeftUpperArm", part = parts.shoulder1},
        {name = "LeftLowerArm", part = parts.arm1},
        {name = "RightUpperArm", part = parts.shoulder2},
        {name = "RightLowerArm", part = parts.arm2},
        {name = "LeftHand", part = parts.arm1},
        {name = "RightHand", part = parts.arm2}
    }
    
    local fullBodyData: {any} = {}
    for pname, part in pairs(parts) do
        local mappedName: string? = FULL_BODY_MAP[pname]
        if mappedName then
            TableInsert(fullBodyData, {name = mappedName, part = part})
        end
    end
    
    return {
        Username = uniqueName,
        Displayname = uniqueName,
        Userid = 0,
        Character = model,
        PrimaryPart = parts.torso or parts.head,
        Head = parts.head,
        Torso = parts.torso,
        LeftArm = parts.arm1,
        RightArm = parts.arm2,
        LeftLeg = parts.leg1,
        RightLeg = parts.leg2,
        LeftUpperArm = parts.arm1,
        LeftLowerArm = parts.arm1,
        LeftHand = parts.arm1,
        RightUpperArm = parts.arm2,
        RightLowerArm = parts.arm2,
        RightHand = parts.arm2,
        LeftUpperLeg = parts.leg1,
        LeftLowerLeg = parts.leg1,
        LeftFoot = parts.leg1,
        RightUpperLeg = parts.leg2,
        RightLowerLeg = parts.leg2,
        RightFoot = parts.leg2,
        UpperTorso = parts.torso,
        LowerTorso = parts.torso,
        BodyHeightScale = 1,
        RigType = 1,
        Whitelisted = false,
        Archenemies = false,
        Aimbot_Part = parts.head,
        Aimbot_TP_Part = parts.head,
        Triggerbot_Part = parts.head,
        Health = 100,
        MaxHealth = 100,
        body_parts_data = bodyPartsData,
        full_body_data = fullBodyData,
        Teamname = "non",
        Toolname = "Non"
    }
end

local function BuildLocalData(model: Model, parts: BodyParts, uniqueName: string): any
    return {
        LocalPlayer = model,
        Displayname = uniqueName,
        Username = uniqueName,
        Userid = LocalPlayer and LocalPlayer.UserId or 1,
        Character = model,
        Team = nil,
        RootPart = parts.torso or parts.head,
        LeftFoot = parts.leg1,
        Head = parts.head,
        LowerTorso = parts.torso,
        Tool = nil,
        Humanoid = parts.head,
        Health = 100,
        MaxHealth = 100,
        RigType = 1,
        Toolname = "none",
        Teamname = "none"
    }
end

local function GetDronePart(drone: Model): BasePart?
    if not drone or not ValidateParent(drone) then return nil end
    
    local success: boolean, primaryPart: BasePart? = Pcall(function()
        return drone.PrimaryPart
    end)
    
    if success and primaryPart and ValidateParent(primaryPart) then
        return primaryPart
    end
    
    local part: Instance? = SafeFindFirstChild(drone, "PrimaryPart")
    if part and ValidateParent(part) then
        return part :: BasePart
    end
    
    part = SafeFindFirstChildOfClass(drone, "BasePart")
    if part and ValidateParent(part) then
        return part :: BasePart
    end
    
    return nil
end

---- runtime ----

RunService.PostLocal:Connect(function()
    local viewmodels: Instance? = SafeFindFirstChild(Workspace, "Viewmodels")
    
    if viewmodels and ValidateParent(viewmodels) then
        local currentModels: {[number]: Model} = {}
        local children: {Instance}? = SafeGetChildren(viewmodels)
        
        if not children then
            DebugPrint("Failed to get Viewmodels children")
            return
        end
        
        DebugPrint("Scanning Viewmodels folder - Found", #children, "children")
        
        for i = 1, #children do
            local model: Instance = children[i]
            local className: string? = GetClassName(model)
            local modelName: string? = GetInstanceName(model)
            
            DebugPrint("Child:", modelName or "Unknown", "ClassName:", className or "Unknown")
            
            if className ~= "Model" then
                DebugPrint("Skipping - not a Model")
                continue
            end
            
            if not ValidateParent(model) then
                DebugPrint("Skipping - no parent")
                continue
            end
            
            if not HasAnyModelChildren(model :: Model) then
                DebugPrint("Skipping - no Model children (empty container)")
                continue
            end
            
            if SafeFindFirstChild(model, "TeamHighlight") then
                DebugPrint("Skipping - has TeamHighlight")
                continue
            end
            
            if IsTeammate(model :: Model) then
                DebugPrint("Skipping - teammate")
                continue
            end
            
            local id: number? = GetInstanceID(model)
            if not id then
                DebugPrint("Skipping - invalid Data ID")
                continue
            end
            
            local uniqueName: string = tostring(id)
            DebugPrint("Valid model found:", modelName or "Unknown", "ID:", id, "Unique Name:", uniqueName)
            currentModels[id] = model :: Model
            
            if not TrackedModels[id] then
                DebugPrint("New model detected:", modelName or "Unknown", "with unique ID:", uniqueName)
                
                local parts: BodyParts? = GetBodyParts(model :: Model)
                if parts then
                    local isLocal: boolean = modelName == "LocalViewModel"
                    
                    if isLocal then
                        DebugPrint("Detected LocalViewModel - Setting as local player with unique name:", uniqueName)
                        local localData: any = BuildLocalData(model :: Model, parts, uniqueName)
                        local success: boolean, err: string? = Pcall(function()
                            override_local_data(localData)
                        end)
                        
                        if success then
                            DebugPrint("Successfully set local player data")
                            TrackedModels[id] = {model = model :: Model, parts = parts, isLocal = true}
                        else
                            DebugPrint("Error setting local data:", err or "Unknown error")
                        end
                    else
                        DebugPrint("Adding enemy model:", modelName or "Unknown", "with unique name:", uniqueName)
                        local modelData: any = BuildModelData(model :: Model, parts, uniqueName)
                        local success: boolean, err: string? = Pcall(function()
                            add_model_data(modelData, uniqueName)
                        end)
                        
                        if success then
                            DebugPrint("Successfully added model data with key:", uniqueName)
                            TrackedModels[id] = {model = model :: Model, parts = parts, isLocal = false}
                        else
                            DebugPrint("Error adding model data:", err or "Unknown error")
                        end
                    end
                else
                    DebugPrint("Failed to get body parts for:", modelName or "Unknown")
                end
            end
        end
        
        for id, data in pairs(TrackedModels) do
            if not currentModels[id] or not ValidateParent(data.model) then
                local uniqueName: string = tostring(id)
                DebugPrint("Removing model ID:", id, "Unique Name:", uniqueName)
                
                if not data.isLocal then
                    local success: boolean, err: string? = Pcall(function()
                        remove_model_data(uniqueName)
                    end)
                    if not success then
                        DebugPrint("Error removing model data:", err or "Unknown error")
                    end
                else
                    local success: boolean, err: string? = Pcall(function()
                        clear_local_data()
                    end)
                    if not success then
                        DebugPrint("Error clearing local data:", err or "Unknown error")
                    end
                end
                TrackedModels[id] = nil
            end
        end
    else
        DebugPrint("Viewmodels folder not found!")
        if next(TrackedModels) then
            DebugPrint("Clearing all model data")
            Pcall(clear_model_data)
            Pcall(clear_local_data)
            TableClear(TrackedModels)
        end
    end
    
    local currentDrones: {[number]: Model} = {}
    local wsChildren: {Instance}? = SafeGetChildren(Workspace)
    
    if wsChildren then
        for i = 1, #wsChildren do
            local child: Instance = wsChildren[i]
            local childName: string? = GetInstanceName(child)
            local className: string? = GetClassName(child)
            
            if childName == "Drone" and className == "Model" and ValidateParent(child) then
                local id: number? = GetInstanceID(child)
                if id then
                    currentDrones[id] = child :: Model
                    
                    if not CachedDronePositions[id] then
                        local part: BasePart? = GetDronePart(child :: Model)
                        if part then
                            DebugPrint("New drone detected - ID:", id)
                            CachedDronePositions[id] = {part = part}
                        end
                    end
                end
            end
        end
    end
    
    for id in pairs(CachedDronePositions) do
        if not currentDrones[id] then
            DebugPrint("Removing drone - ID:", id)
            CachedDronePositions[id] = nil
            if DroneDrawings[id] then
                Pcall(function()
                    DroneDrawings[id].square:Remove()
                    DroneDrawings[id].text:Remove()
                end)
                DroneDrawings[id] = nil
            end
        end
    end
    
    local character: Model? = LocalPlayer and LocalPlayer.Character or nil
    local playerPos: Vector3? = nil
    
    if character and ValidateParent(character) then
        local head: Instance? = SafeFindFirstChild(character, "Head")
        if head and ValidateParent(head) then
            local success: boolean, pos: Vector3? = Pcall(function()
                return (head :: BasePart).Position
            end)
            if success and pos then
                playerPos = pos
            end
        end
    end
    
    for id, data in pairs(CachedDronePositions) do
        if data.part and ValidateParent(data.part) then
            local success: boolean, pos: Vector3? = Pcall(function()
                return data.part.Position
            end)
            
            if success and pos then
                data.pos = pos
                
                if playerPos then
                    local dx: number = pos.X - playerPos.X
                    local dy: number = pos.Y - playerPos.Y
                    local dz: number = pos.Z - playerPos.Z
                    data.dist = MathSqrt(dx*dx + dy*dy + dz*dz)
                end
            end
        else
            CachedDronePositions[id] = nil
        end
    end
end)

RunService.Render:Connect(function()
    if not Camera or not ValidateParent(Camera) then
        Camera = Workspace.CurrentCamera
        return
    end
    
    for id, data in pairs(CachedDronePositions) do
        if data.pos then
            local success: boolean, screen: Vector3?, onScreen: boolean? = Pcall(function()
                local s, visible = (Camera :: Camera):WorldToScreenPoint(data.pos :: Vector3)
                return s, visible
            end)
            
            if success and screen and onScreen then
                if not DroneDrawings[id] then
                    local drawSuccess: boolean = Pcall(function()
                        local square = Drawing.new("Square")
                        square.Thickness = 2
                        square.Filled = false
                        square.Color = Color3.fromRGB(255, 0, 0)
                        square.ZIndex = 1000
                        
                        local text = Drawing.new("Text")
                        text.Size = 14
                        text.Center = true
                        text.Outline = true
                        text.OutlineColor = Color3.fromRGB(0, 0, 0)
                        text.Color = Color3.fromRGB(255, 255, 255)
                        text.Font = 2
                        text.ZIndex = 1001
                        
                        DroneDrawings[id] = {square = square, text = text}
                    end)
                    
                    if not drawSuccess then
                        continue
                    end
                end
                
                local cameraPos: Vector3? = nil
                local camSuccess: boolean = Pcall(function()
                    cameraPos = (Camera :: Camera).CFrame.Position
                end)
                
                if camSuccess and cameraPos and data.pos then
                    local distance: number = VectorMagnitude(VectorCreate(
                        data.pos.X - cameraPos.X,
                        data.pos.Y - cameraPos.Y,
                        data.pos.Z - cameraPos.Z
                    ))
                    local size: number = MathClamp(DRONE_SIZE_DIVISOR / distance, DRONE_SIZE_MIN, DRONE_SIZE_MAX)
                    
                    Pcall(function()
                        local drawings: DroneDrawing = DroneDrawings[id]
                        drawings.square.Position = Vector2.new(screen.X - size/2, screen.Y - size/2)
                        drawings.square.Size = Vector2.new(size, size)
                        drawings.square.Visible = true
                        
                        if data.dist then
                            drawings.text.Text = "DRONE [" .. MathFloor(data.dist) .. "m]"
                        else
                            drawings.text.Text = "DRONE"
                        end
                        drawings.text.Position = Vector2.new(screen.X, screen.Y - size/2 - 20)
                        drawings.text.Visible = true
                    end)
                end
            else
                if DroneDrawings[id] then
                    Pcall(function()
                        DroneDrawings[id].square.Visible = false
                        DroneDrawings[id].text.Visible = false
                    end)
                end
            end
        end
    end
end)

---- exports ----

_G.cleanup_esp = function()
    DebugPrint("Running cleanup...")
    Pcall(function()
        Drawing.clear()
    end)
    TableClear(TrackedModels)
    TableClear(CachedDronePositions)
    TableClear(DroneDrawings)
    Pcall(clear_model_data)
    Pcall(clear_local_data)
    DebugPrint("Cleanup complete")
end

DebugPrint("Script initialized - Debug mode enabled")

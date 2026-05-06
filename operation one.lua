--!strict
--!optimize 2

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

type Init = (configs: { [string]: any }) -> ()
local init: Init = (loadfile("esplib.lua") :: any)()

local _override_local      = override_local_data
local _add_model_data      = add_model_data
local _edit_model_data     = edit_model_data
local _remove_model_data   = remove_model_data
local _clear_local_data    = clear_local_data
local _is_team_check       = is_team_check_active
local _mem_readstring      = memory.readstring

local PART_NAMES: { string } = {
    "head", "torso", "arm1", "arm2",
    "leg1", "leg2", "hip1", "hip2",
    "shoulder1", "shoulder2",
}

local NAME_MATCH_DIST_SQ: number = 400

type VMParts = {
    head:      BasePart?,
    torso:     BasePart?,
    arm1:      BasePart?,
    arm2:      BasePart?,
    leg1:      BasePart?,
    leg2:      BasePart?,
    hip1:      BasePart?,
    hip2:      BasePart?,
    shoulder1: BasePart?,
    shoulder2: BasePart?,
}

type RealChar = {
    char: Model,
    hrp:  BasePart,
    hum:  Humanoid,
}

type Locked = {
    vm:     Instance,
    parts:  VMParts,
    real:   RealChar,
    player: Player,
    key:    string,
}

local realChars:   { [string]: RealChar   } = {}
local locked:      { [Instance]: Locked   } = {}
local boundUserIds:{ [number]: Instance?  } = {}
local localActive: boolean = false

local function getVMParts(vm: Instance): VMParts
    local out: VMParts = {}
    for _, n in PART_NAMES do
        local c = vm:FindFirstChild(n)
        if c ~= nil and c:IsA("BasePart") then
            (out :: any)[n] = c :: BasePart
        end
    end
    return out
end

local function isStructurallyValid(vm: Instance): boolean
    if vm.ClassName ~= "Model" then return false end
    for _, c in vm:GetChildren() do
        if c.ClassName == "Model" then
            local h = vm:FindFirstChild("head")
            return h ~= nil and h:IsA("BasePart")
        end
    end
    return false
end

local function findPlayerByName(charName: string): Player?
    local p = Players:FindFirstChild(charName)
    if p ~= nil and p:IsA("Player") then
        return p :: Player
    end
    return nil
end

-- Compare .Team.Name strings — .Team returns an Instance so .Name gives the string
local function isTeammate(p: Player): boolean
    local lpTeam = LocalPlayer.Team
    if lpTeam == nil then return false end
    local pt = p.Team
    if pt == nil then return false end
    return pt.Name == lpTeam.Name
end

local function buildModelData(
    player: Player,
    vm:     Instance,
    parts:  VMParts,
    real:   RealChar
): { [string]: any }
    local hum = real.hum

    local fullBodyData: { [string]: any } = {
        Head            = parts.head,
        Torso           = parts.torso,
        LeftArm         = parts.arm1,
        RightArm        = parts.arm2,
        LeftLeg         = parts.leg1,
        RightLeg        = parts.leg2,
        LeftUpperArm    = parts.arm1,
        LeftLowerArm    = parts.arm1,
        LeftHand        = parts.arm1,
        RightUpperArm   = parts.arm2,
        RightLowerArm   = parts.arm2,
        RightHand       = parts.arm2,
        LeftUpperLeg    = parts.leg1,
        LeftLowerLeg    = parts.leg1,
        LeftFoot        = parts.leg1,
        RightUpperLeg   = parts.leg2,
        RightLowerLeg   = parts.leg2,
        RightFoot       = parts.leg2,
        UpperTorso      = parts.torso,
        LowerTorso      = parts.torso,
        BodyHeightScale = 1,
        RigType         = 1,
    }

    local bodyPartsData: { any } = {
        { name = "LowerTorso",    part = parts.torso     },
        { name = "LeftUpperLeg",  part = parts.hip1      },
        { name = "LeftLowerLeg",  part = parts.leg1      },
        { name = "RightUpperLeg", part = parts.hip2      },
        { name = "RightLowerLeg", part = parts.leg2      },
        { name = "LeftUpperArm",  part = parts.shoulder1 },
        { name = "LeftLowerArm",  part = parts.arm1      },
        { name = "RightUpperArm", part = parts.shoulder2 },
        { name = "RightLowerArm", part = parts.arm2      },
        { name = "LeftHand",      part = parts.arm1      },
        { name = "RightHand",     part = parts.arm2      },
    }

    local playerTeam = player.Team
    local teamName   = if playerTeam ~= nil then playerTeam.Name else ""

    return {
        Username        = player.Name,
        Displayname     = player.DisplayName,
        Userid          = player.UserId,
        Character       = vm,
        PrimaryPart     = parts.torso or parts.head,
        Humanoid        = hum,
        Head            = parts.head,
        Torso           = parts.torso,
        LeftArm         = parts.arm1,
        RightArm        = parts.arm2,
        LeftLeg         = parts.leg1,
        RightLeg        = parts.leg2,
        BodyHeightScale = 1,
        RigType         = 1,
        Whitelisted     = false,
        Archenemies     = false,
        Aimbot_Part     = parts.head,
        Aimbot_TP_Part  = parts.head,
        Triggerbot_Part = parts.head,
        Health          = hum.Health,
        MaxHealth       = hum.MaxHealth,
        body_parts_data = bodyPartsData,
        full_body_data  = fullBodyData,
        Teamname        = teamName,
        Toolname        = "",
    }
end

local function unbind(vm: Instance, entry: Locked): ()
    _remove_model_data(entry.key)
    locked[vm]                       = nil
    boundUserIds[entry.player.UserId] = nil
end

local function tryBindVM(vm: Instance): ()
    if locked[vm] ~= nil then return end
    if not isStructurallyValid(vm) then return end

    local head = vm:FindFirstChild("head") :: BasePart?
    if head == nil then return end

    local hpos         = head.Position
    local hx, hy, hz  = hpos.X, hpos.Y, hpos.Z
    local bestName: string?   = nil
    local bestReal: RealChar? = nil
    local bestSq:   number    = NAME_MATCH_DIST_SQ

    for name, real in realChars do
        if real.hrp == nil or real.hrp.Parent == nil then continue end
        local rp = real.hrp.Position
        local dx, dy, dz = rp.X - hx, rp.Y - hy, rp.Z - hz
        local dsq = dx*dx + dy*dy + dz*dz
        if dsq < bestSq then
            bestSq   = dsq
            bestName = name
            bestReal = real
        end
    end

    if bestName == nil or bestReal == nil then return end

    local player = findPlayerByName(bestName)
    if player == nil then return end
    if player == LocalPlayer then return end

    -- If team check is active, skip teammates entirely — do not add them at all
    if _is_team_check() and isTeammate(player) then return end

    if boundUserIds[player.UserId] ~= nil then return end

    local parts = getVMParts(vm)
    if parts.head == nil and parts.torso == nil then return end

    local key = `vm_{player.UserId}`

    _add_model_data(buildModelData(player, vm, parts, bestReal), key)

    locked[vm] = {
        vm     = vm,
        parts  = parts,
        real   = bestReal,
        player = player,
        key    = key,
    }
    boundUserIds[player.UserId] = vm
end

RunService.PreModel:Connect(function(): ()
    for k in realChars do realChars[k] = nil end

    local lpChar = LocalPlayer.Character
    for _, obj in Workspace:GetChildren() do
        if obj.ClassName ~= "Model" then continue end
        if obj == lpChar then continue end
        local hrp = obj:FindFirstChild("HumanoidRootPart")
        if hrp == nil or not hrp:IsA("BasePart") then continue end
        local hum = obj:FindFirstChildOfClass("Humanoid")
        if hum == nil then continue end
        realChars[obj.Name] = {
            char = obj :: Model,
            hrp  = hrp :: BasePart,
            hum  = hum :: Humanoid,
        }
    end

    for vm, entry in locked do
        if vm.Parent == nil then
            unbind(vm, entry)
            continue
        end
        local hum = entry.real.hum
        if hum == nil or hum.Parent == nil or hum.Health <= 0 then
            unbind(vm, entry)
            continue
        end
    end

    local vmFolder = Workspace:FindFirstChild("Viewmodels")
    if vmFolder == nil then return end

    for _, vm in vmFolder:GetChildren() do
        if vm.Name == "LocalViewmodel" then continue end
        if locked[vm] ~= nil then continue end
        tryBindVM(vm)
    end
end)

RunService.PostLocal:Connect(function(): ()
    local vmFolder = Workspace:FindFirstChild("Viewmodels")
    local localVm  = if vmFolder ~= nil then vmFolder:FindFirstChild("LocalViewmodel") else nil

    if localVm ~= nil then
        local parts = getVMParts(localVm)
        local char  = LocalPlayer.Character
        local hum: Humanoid? = nil
        if char ~= nil then
            local h = char:FindFirstChildOfClass("Humanoid")
            if h ~= nil then hum = h :: Humanoid end
        end

        local rootPart: BasePart? = parts.torso or parts.head

        _override_local({
            LocalPlayer = LocalPlayer,
            Displayname = LocalPlayer.DisplayName,
            Username    = LocalPlayer.Name,
            Userid      = LocalPlayer.UserId,
            Character   = char,
            Team        = LocalPlayer.Team,
            RootPart    = rootPart,
            Head        = parts.head,
            LowerTorso  = parts.torso,
            LeftFoot    = parts.leg1,
            Humanoid    = hum,
            Health      = if hum ~= nil then hum.Health    else nil,
            MaxHealth   = if hum ~= nil then hum.MaxHealth else nil,
            RigType     = 1,
        })
        localActive = true
    else
        if localActive then
            _clear_local_data()
            localActive = false
        end
    end

    for vm, entry in locked do
        if vm.Parent == nil then
            unbind(vm, entry)
            continue
        end
        local hum = entry.real.hum
        if hum == nil or hum.Parent == nil then
            unbind(vm, entry)
            continue
        end
        local hp = hum.Health
        if hp <= 0 then
            unbind(vm, entry)
            continue
        end

        -- If team check flipped on mid-session, unbind teammates retroactively
        if _is_team_check() and isTeammate(entry.player) then
            unbind(vm, entry)
            continue
        end

        _edit_model_data({
            Health    = hp,
            MaxHealth = hum.MaxHealth,
        }, entry.key)
    end
end)

local function gadgetOwnerFilter(child: Instance): boolean
    local owner = child:FindFirstChild("Owner")
    if owner == nil then return true end

    local usernameLabel = owner:FindFirstChild("Username")
    if usernameLabel == nil then return true end

    local username: any = nil
    local ok = pcall(function(): ()
        username = _mem_readstring(usernameLabel, 0xdc0)
    end)
    if not ok or username == nil then return true end
    if type(username) ~= "string" or username == "" then return true end
    if username == LocalPlayer.Name then return false end

    local p = Players:FindFirstChild(username)
    if p ~= nil and p:IsA("Player") then
        local pp      = p :: Player
        local lpTeam  = LocalPlayer.Team
        local ppTeam  = pp.Team
        if lpTeam ~= nil and ppTeam ~= nil and ppTeam.Name == lpTeam.Name then
            return false
        end
    end

    return true
end

local gadgetConfigs: { [string]: any } = {
    Gadgets = {
        Enabled           = true,
        DrawMode          = 1,
        BoxColor          = Color3.fromRGB(255, 80, 80),
        TextColor         = Color3.fromRGB(255, 255, 255),
        MaxDistance       = 1500,
        FontSize          = 13,
        Box               = true,
        Name              = true,
        Distance          = true,
        Folder            = Workspace,
        CustomName        = "",
        UseCustomName     = false,
        MultiSameObject   = true,
        IncludeOnly       = {
            "RemoteC4", "Drone", "Claymore", "ProximityAlarm",
            "ToxicCharge", "DeployableShield", "BarbedWire",
            "BulletproofCamera", "StickyCamera", "SignalDisruptor",
        },
        ExcludeObject     = nil,
        IncludeAttributes = nil,
        ExcludeAttributes = nil,
        Filter            = gadgetOwnerFilter,
        Highlight         = true,
        Fill              = true,
        Outline           = true,
        FillTransp        = 0.25,
        FillColor         = Color3.fromRGB(255, 80, 80),
        OutlineColor      = Color3.fromRGB(255, 255, 0),
        OutlineThickness  = 1,
        HighlightStagger  = nil,
    },
}

init(gadgetConfigs)

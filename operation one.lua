--!strict
--!optimize 2

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

type Init = (configs: { [string]: any }) -> ()
local init: Init = loadstring(game:HttpGet("https://raw.githubusercontent.com/Sploiter13/severe/refs/heads/main/esplib.luau"))()

local _override_local    = override_local_data
local _add_model_data    = add_model_data
local _edit_model_data   = edit_model_data
local _remove_model_data = remove_model_data
local _clear_local_data  = clear_local_data
local _is_team_check     = is_team_check_active

local PART_NAMES: { string } = {
	"head", "torso", "arm1", "arm2",
	"leg1", "leg2", "hip1", "hip2",
	"shoulder1", "shoulder2",
}

local FALLBACK_MAP: { [string]: { string } } = {
	arm2      = { "arm1",  "torso", "head" },
	arm1      = { "arm2",  "torso", "head" },
	leg2      = { "leg1",  "torso", "head" },
	leg1      = { "leg2",  "torso", "head" },
	hip1      = { "leg1",  "torso", "head" },
	hip2      = { "leg2",  "torso", "head" },
	shoulder1 = { "arm1",  "torso", "head" },
	shoulder2 = { "arm2",  "torso", "head" },
	torso     = { "head"               },
	head      = { "torso"              },
}

local NAME_MATCH_DIST_SQ: number = 400

type VMParts = {
	head      : BasePart?,
	torso     : BasePart?,
	arm1      : BasePart?,
	arm2      : BasePart?,
	leg1      : BasePart?,
	leg2      : BasePart?,
	hip1      : BasePart?,
	hip2      : BasePart?,
	shoulder1 : BasePart?,
	shoulder2 : BasePart?,
}

type RealChar = {
	char   : Model,
	hrp    : BasePart,
	hum    : Humanoid,
	player : Player,
}

type Locked = {
	vm     : Instance,
	parts  : VMParts,
	real   : RealChar,
	player : Player,
	key    : string,
	origChar : Model,
}

local realChars   : { [string]: RealChar } = {}
local locked      : { [Instance]: Locked } = {}
local localActive : boolean               = false
local vmOwner     : { [Instance]: Player } = {}
local boundPlayers: { [Player]: Instance } = {}
local abandonedVMs: { [Instance]: boolean } = {}

local function validateParent(inst: Instance?): boolean
	if inst == nil then return false end
	local ok, parent = pcall(function(): Instance?
		return (inst :: Instance).Parent
	end)
	return ok and parent ~= nil
end

local function getInstanceDataId(inst: Instance): number?
	local ok, data = pcall(function(): any
		return (inst :: any).Data
	end)
	if not ok or data == nil then return nil end
	local id = tonumber(data :: any)
	return if id ~= nil and id ~= 0 then id else nil
end

local function getVMParts(vm: Instance): VMParts
	local out: VMParts = {} :: VMParts
	for _, n in PART_NAMES do
		local c: Instance? = nil
		pcall(function(): ()
			local found = vm:FindFirstChild(n)
			if found ~= nil and found:IsA("BasePart") then
				c = found
			end
		end)
		if c ~= nil then
			(out :: any)[n] = c :: BasePart
		end
	end
	for _, n in PART_NAMES do
		if (out :: any)[n] == nil then
			local fallbacks = FALLBACK_MAP[n]
			if fallbacks ~= nil then
				for _, fb in fallbacks do
					if (out :: any)[fb] ~= nil then
						(out :: any)[n] = (out :: any)[fb]
						break
					end
				end
			end
		end
	end
	return out
end

local function isStructurallyValid(vm: Instance): boolean
	local ok, result = pcall(function(): boolean
		if vm.ClassName ~= "Model" then return false end
		for _, c in vm:GetChildren() do
			if c.ClassName == "Model" then
				local h = vm:FindFirstChild("head")
				return h ~= nil and h:IsA("BasePart")
			end
		end
		return false
	end)
	return ok and result
end

local function findPlayerByName(charName: string): Player?
	local p = Players:FindFirstChild(charName)
	if p ~= nil and p:IsA("Player") then
		return p :: Player
	end
	return nil
end

local function isTeammate(p: Player): boolean
	local lpTeam = LocalPlayer.Team
	if lpTeam == nil then return false end
	local pTeam = p.Team
	if pTeam == nil then return false end
	if pTeam == lpTeam then return true end
	return pTeam.Name == lpTeam.Name
end

local function buildModelData(player: Player, vm: Instance, parts: VMParts, real: RealChar): { [string]: any }
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
		Teamname        = if player.Team ~= nil then player.Team.Name else "",
 		Toolname = "",
	}
end

local function unbind(vm: Instance, entry: Locked): ()
	_remove_model_data(entry.key)
	locked[vm] = nil
	vmOwner[vm] = nil
	if boundPlayers[entry.player] == vm then
		boundPlayers[entry.player] = nil
	end
end

local function unbindAndAbandon(vm: Instance, entry: Locked): ()
	abandonedVMs[vm] = true
	unbind(vm, entry)
end

local function tryBindVM(vm: Instance): ()
	if locked[vm] ~= nil then return end
	if abandonedVMs[vm] then return end
	if not isStructurallyValid(vm) then return end

	local vmId = getInstanceDataId(vm)
	if vmId == nil then return end

	local head = vm:FindFirstChild("head") :: BasePart?
	if head == nil then return end

	local hpos = head.Position
	local hx   = hpos.X
	local hy   = hpos.Y
	local hz   = hpos.Z

	local bestName: string?   = nil
	local bestReal: RealChar? = nil
	local bestSq  : number    = NAME_MATCH_DIST_SQ
	local secondSq: number    = NAME_MATCH_DIST_SQ

	for name, real in realChars do
		if boundPlayers[real.player] ~= nil then continue end
		local rp = real.hrp.Position
		local dx = rp.X - hx
		local dy = rp.Y - hy
		local dz = rp.Z - hz
		local dsq = dx*dx + dy*dy + dz*dz
		if dsq < bestSq then
			secondSq = bestSq
			bestSq   = dsq
			bestName = name
			bestReal = real
		elseif dsq < secondSq then
			secondSq = dsq
		end
	end

	if bestName == nil or bestReal == nil then return end
	if secondSq < bestSq * 4 then return end

	local player = (bestReal :: RealChar).player
	if player == LocalPlayer then return end

	if _is_team_check() and isTeammate(player) then return end

	local parts = getVMParts(vm)
	if parts.head == nil and parts.torso == nil then return end

	local key = `vm_{vmId}_{player.UserId}`
	_add_model_data(buildModelData(player, vm, parts, bestReal :: RealChar), key)

	locked[vm] = {
		vm       = vm,
		parts    = parts,
		real     = bestReal :: RealChar,
		player   = player,
		key      = key,
		origChar = (bestReal :: RealChar).char,
	}
	vmOwner[vm] = player
	boundPlayers[player] = vm
end

RunService.PreModel:Connect(function(): ()
	for k in realChars do realChars[k] = nil end

	for vm in abandonedVMs do
		if not validateParent(vm) then
			abandonedVMs[vm] = nil
		end
	end

	for _, p in Players:GetChildren() do
		if not p:IsA("Player") then continue end
		if p == LocalPlayer then continue end
		local player = p :: Player
		local char = player.Character
		if char == nil then continue end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp == nil or not hrp:IsA("BasePart") then continue end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum == nil then continue end
		realChars[player.Name] = {
			char   = char :: Model,
			hrp    = hrp :: BasePart,
			hum    = hum :: Humanoid,
			player = player,
		}
	end

	for vm, entry in locked do
		if not validateParent(vm) then
			unbind(vm, entry)
			continue
		end

		local owner = vmOwner[vm]
		if owner == nil then
			unbind(vm, entry)
			continue
		end

		local char = owner.Character
		if char == nil then
			unbind(vm, entry)
			continue
		end

		if char ~= entry.origChar then
			unbindAndAbandon(vm, entry)
			continue
		end

		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp == nil or not hrp:IsA("BasePart") then
			unbind(vm, entry)
			continue
		end

		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum == nil then
			unbind(vm, entry)
			continue
		end

		if hum.Health <= 0 then
			unbind(vm, entry)
			continue
		end

		entry.real = {
			char   = char :: Model,
			hrp    = hrp :: BasePart,
			hum    = hum :: Humanoid,
			player = owner,
		}
	end

	local vmFolder = Workspace:FindFirstChild("Viewmodels")
	if vmFolder == nil then return end

	for _, vm in vmFolder:GetChildren() do
		if vm.Name == "LocalViewmodel" then continue end
		if locked[vm] ~= nil then continue end
		if abandonedVMs[vm] then continue end
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
			if h ~= nil then hum = h end
		end

		local rootPart: BasePart? = parts.torso
		if rootPart == nil then rootPart = parts.head end

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
			Health      = if hum ~= nil then hum.Health else nil,
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

	local teamCheck = _is_team_check()

	for vm, entry in locked do
		if not validateParent(vm) then
			unbind(vm, entry)
			continue
		end

		local owner = vmOwner[vm]
		if owner == nil then
			unbind(vm, entry)
			continue
		end

		if teamCheck and isTeammate(owner) then
			unbind(vm, entry)
			continue
		end

		local char = owner.Character
		if char == nil then
			unbindAndAbandon(vm, entry)
			continue
		end

		if char ~= entry.origChar then
			unbindAndAbandon(vm, entry)
			continue
		end

		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp == nil or not hrp:IsA("BasePart") then
			unbindAndAbandon(vm, entry)
			continue
		end

		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum == nil then
			unbindAndAbandon(vm, entry)
			continue
		end

		local health = hum.Health
		if health <= 0 then
			unbindAndAbandon(vm, entry)
			continue
		end

		entry.real = {
			char   = char :: Model,
			hrp    = hrp :: BasePart,
			hum    = hum :: Humanoid,
			player = owner,
		}

		_edit_model_data({
			Humanoid    = hum,
			Health      = health,
			MaxHealth   = hum.MaxHealth,
			Whitelisted = false,
		}, entry.key)
	end
end)

local gadgetConfigs: { [string]: any } = {
	Gadgets = {
		Enabled          = true,
		DrawMode         = 1,
		BoxColor         = Color3.fromRGB(255, 80, 80),
		TextColor        = Color3.fromRGB(255, 255, 255),
		MaxDistance      = 1500,
		FontSize         = 13,
		Box              = false,
		Name             = true,
		Distance         = true,
		Folder           = Workspace,
		CustomName       = "",
		UseCustomName    = false,
		MultiSameObject  = true,
		IncludeOnly      = {
			"RemoteC4",
			"Drone",
			"Claymore",
			"ProximityAlarm",
			"ToxicCharge",
			"DeployableShield",
			"BarbedWire",
			"BulletproofCamera",
			"StickyCamera",
			"SignalDisruptor",
		},
		ExcludeObject    = nil,
		IncludeAttributes = nil,
		ExcludeAttributes = nil,
		Highlight        = true,
		Fill             = true,
		Outline          = true,
		FillTransp       = 0.25,
		FillColor        = Color3.fromRGB(255, 80, 80),
		OutlineColor     = Color3.fromRGB(255, 255, 0),
		OutlineThickness = 1,
		HighlightStagger = nil,
	},
}

init(gadgetConfigs)

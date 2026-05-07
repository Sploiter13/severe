--!strict
--!optimize 2

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

type Init = (configs: { [string]: any }) -> ()
local init: Init = (loadfile("esplib.lua") :: any)()

local _override_local    = override_local_data
local _add_model_data    = add_model_data
local _edit_model_data   = edit_model_data
local _remove_model_data = remove_model_data
local _clear_local_data  = clear_local_data
local _is_team_check     = is_team_check_active
local _is_rbx_active     = isrbxactive

local TEAM_T : string = "Terrorists"
local TEAM_CT: string = "Counter-Terrorists"

local STATE_INTERMISSION: string = "Intermission"
local STATE_BUY         : string = "Buy Period"
local STATE_ROUND       : string = "Round In Progress"
local STATE_WARMUP      : string = "Warmup"
local STATE_MAP_VOTING  : string = "Map Voting"

type Tracked = {
	char : Model,
	key  : string,
}

type R15Parts = {
	head           : BasePart,
	hrp            : BasePart,
	upperTorso     : BasePart,
	lowerTorso     : BasePart,
	leftUpperArm   : BasePart,
	leftLowerArm   : BasePart,
	leftHand       : BasePart,
	rightUpperArm  : BasePart,
	rightLowerArm  : BasePart,
	rightHand      : BasePart,
	leftUpperLeg   : BasePart,
	leftLowerLeg   : BasePart,
	leftFoot       : BasePart,
	rightUpperLeg  : BasePart,
	rightLowerLeg  : BasePart,
	rightFoot      : BasePart,
}

local tracked    : { [Player]: Tracked } = {}
local localActive: boolean               = false

local function isUd(v: any): boolean
	if v == nil then return false end
	return type(v) == "userdata"
end

local function setUd(t: { [string]: any }, key: string, val: any): ()
	if val == nil then return end
	if type(val) ~= "userdata" then return end
	t[key] = val
end

local function getHumanoid(parent: Instance): Humanoid?
	if parent == nil then return nil end
	if not isUd(parent) then return nil end
	local children = parent:GetChildren()
	if children == nil then return nil end
	for _, c in children do
		if c == nil then continue end
		if not isUd(c) then continue end
		if c.ClassName == "Humanoid" then
			return c :: Humanoid
		end
	end
	return nil
end

local function findPart(char: Model, name: string): BasePart?
	if char == nil then return nil end
	if not isUd(char) then return nil end
	local p = char:FindFirstChild(name)
	if p == nil then return nil end
	if not isUd(p) then return nil end
	if not p:IsA("BasePart") then return nil end
	return p :: BasePart
end

local function getCharTeam(char: Model): string?
	if char == nil then return nil end
	if not isUd(char) then return nil end
	local parent = char.Parent
	if parent == nil then return nil end
	if not isUd(parent) then return nil end
	local n = parent.Name
	if n == TEAM_T then return TEAM_T end
	if n == TEAM_CT then return TEAM_CT end
	return nil
end

local function getPlayerTeam(player: Player): string?
	if player == nil then return nil end
	if not isUd(player) then return nil end
	local attr = player:GetAttribute("Team")
	if attr ~= nil and type(attr) == "string" then
		if attr == TEAM_T  then return TEAM_T  end
		if attr == TEAM_CT then return TEAM_CT end
	end
	local char = player.Character
	if char == nil then return nil end
	if not isUd(char) then return nil end
	return getCharTeam(char :: Model)
end

local function getLocalTeam(): string?
	return getPlayerTeam(LocalPlayer)
end

local function getGameState(): string?
	local s = Workspace:GetAttribute("GameState")
	if s == nil then return nil end
	if type(s) ~= "string" then return nil end
	return s :: string
end

local function getRoundTimer(): number?
	local s = Workspace:GetAttribute("Timer")
	if s == nil then return nil end
	if type(s) ~= "string" then return nil end
	return tonumber(s :: string)
end

local function isRoundActive(state: string?): boolean
	if state == nil then return true end
	return state == STATE_ROUND or state == STATE_BUY or state == STATE_WARMUP
end

local function getR15Parts(char: Model): R15Parts?
	local head           = findPart(char, "Head")
	local hrp            = findPart(char, "HumanoidRootPart")
	local upperTorso     = findPart(char, "UpperTorso")
	local lowerTorso     = findPart(char, "LowerTorso")
	local leftUpperArm   = findPart(char, "LeftUpperArm")
	local leftLowerArm   = findPart(char, "LeftLowerArm")
	local leftHand       = findPart(char, "LeftHand")
	local rightUpperArm  = findPart(char, "RightUpperArm")
	local rightLowerArm  = findPart(char, "RightLowerArm")
	local rightHand      = findPart(char, "RightHand")
	local leftUpperLeg   = findPart(char, "LeftUpperLeg")
	local leftLowerLeg   = findPart(char, "LeftLowerLeg")
	local leftFoot       = findPart(char, "LeftFoot")
	local rightUpperLeg  = findPart(char, "RightUpperLeg")
	local rightLowerLeg  = findPart(char, "RightLowerLeg")
	local rightFoot      = findPart(char, "RightFoot")

	if head          == nil then return nil end
	if hrp           == nil then return nil end
	if upperTorso    == nil then return nil end
	if lowerTorso    == nil then return nil end
	if leftUpperArm  == nil then return nil end
	if leftLowerArm  == nil then return nil end
	if leftHand      == nil then return nil end
	if rightUpperArm == nil then return nil end
	if rightLowerArm == nil then return nil end
	if rightHand     == nil then return nil end
	if leftUpperLeg  == nil then return nil end
	if leftLowerLeg  == nil then return nil end
	if leftFoot      == nil then return nil end
	if rightUpperLeg == nil then return nil end
	if rightLowerLeg == nil then return nil end
	if rightFoot     == nil then return nil end

	return {
		head           = head           :: BasePart,
		hrp            = hrp            :: BasePart,
		upperTorso     = upperTorso     :: BasePart,
		lowerTorso     = lowerTorso     :: BasePart,
		leftUpperArm   = leftUpperArm   :: BasePart,
		leftLowerArm   = leftLowerArm   :: BasePart,
		leftHand       = leftHand       :: BasePart,
		rightUpperArm  = rightUpperArm  :: BasePart,
		rightLowerArm  = rightLowerArm  :: BasePart,
		rightHand      = rightHand      :: BasePart,
		leftUpperLeg   = leftUpperLeg   :: BasePart,
		leftLowerLeg   = leftLowerLeg   :: BasePart,
		leftFoot       = leftFoot       :: BasePart,
		rightUpperLeg  = rightUpperLeg  :: BasePart,
		rightLowerLeg  = rightLowerLeg  :: BasePart,
		rightFoot      = rightFoot      :: BasePart,
	}
end

local function buildModelData(player: Player, char: Model, hum: Humanoid, parts: R15Parts, teamName: string): { [string]: any }
	local head           = parts.head
	local hrp            = parts.hrp
	local upperTorso     = parts.upperTorso
	local lowerTorso     = parts.lowerTorso
	local leftUpperArm   = parts.leftUpperArm
	local leftLowerArm   = parts.leftLowerArm
	local leftHand       = parts.leftHand
	local rightUpperArm  = parts.rightUpperArm
	local rightLowerArm  = parts.rightLowerArm
	local rightHand      = parts.rightHand
	local leftUpperLeg   = parts.leftUpperLeg
	local leftLowerLeg   = parts.leftLowerLeg
	local leftFoot       = parts.leftFoot
	local rightUpperLeg  = parts.rightUpperLeg
	local rightLowerLeg  = parts.rightLowerLeg
	local rightFoot      = parts.rightFoot

	local fullBodyData: { [string]: any } = {
		BodyHeightScale = 1,
		RigType         = 1,
	}
	setUd(fullBodyData, "Head",          head)
	setUd(fullBodyData, "Torso",         lowerTorso)
	setUd(fullBodyData, "LeftArm",       leftLowerArm)
	setUd(fullBodyData, "RightArm",      rightLowerArm)
	setUd(fullBodyData, "LeftLeg",       leftLowerLeg)
	setUd(fullBodyData, "RightLeg",      rightLowerLeg)
	setUd(fullBodyData, "LeftUpperArm",  leftUpperArm)
	setUd(fullBodyData, "LeftLowerArm",  leftLowerArm)
	setUd(fullBodyData, "LeftHand",      leftHand)
	setUd(fullBodyData, "RightUpperArm", rightUpperArm)
	setUd(fullBodyData, "RightLowerArm", rightLowerArm)
	setUd(fullBodyData, "RightHand",     rightHand)
	setUd(fullBodyData, "LeftUpperLeg",  leftUpperLeg)
	setUd(fullBodyData, "LeftLowerLeg",  leftLowerLeg)
	setUd(fullBodyData, "LeftFoot",      leftFoot)
	setUd(fullBodyData, "RightUpperLeg", rightUpperLeg)
	setUd(fullBodyData, "RightLowerLeg", rightLowerLeg)
	setUd(fullBodyData, "RightFoot",     rightFoot)
	setUd(fullBodyData, "UpperTorso",    upperTorso)
	setUd(fullBodyData, "LowerTorso",    lowerTorso)

	local bodyPartsData: { any } = {
		{ name = "LowerTorso",    part = lowerTorso    },
		{ name = "LeftLowerLeg",  part = leftLowerLeg  },
		{ name = "LeftUpperLeg",  part = leftUpperLeg  },
		{ name = "RightLowerLeg", part = rightLowerLeg },
		{ name = "RightUpperLeg", part = rightUpperLeg },
		{ name = "LeftLowerArm",  part = leftLowerArm  },
		{ name = "LeftUpperArm",  part = leftUpperArm  },
		{ name = "RightLowerArm", part = rightLowerArm },
		{ name = "RightUpperArm", part = rightUpperArm },
		{ name = "LeftHand",      part = leftHand      },
		{ name = "RightHand",     part = rightHand     },
	}

	local data: { [string]: any } = {
		Username        = player.Name,
		Displayname     = player.DisplayName,
		Userid          = player.UserId,
		BodyHeightScale = 1,
		RigType         = 1,
		Whitelisted     = false,
		Archenemies     = false,
		Health          = hum.Health,
		MaxHealth       = hum.MaxHealth,
		body_parts_data = bodyPartsData,
		full_body_data  = fullBodyData,
		Teamname        = teamName,
		Toolname        = "",
	}
	setUd(data, "Character",       char)
	setUd(data, "PrimaryPart",     hrp)
	setUd(data, "Humanoid",        hum)
	setUd(data, "Head",            head)
	setUd(data, "Torso",           lowerTorso)
	setUd(data, "LeftArm",         leftLowerArm)
	setUd(data, "RightArm",        rightLowerArm)
	setUd(data, "LeftLeg",         leftLowerLeg)
	setUd(data, "RightLeg",        rightLowerLeg)
	setUd(data, "Aimbot_Part",     head)
	setUd(data, "Aimbot_TP_Part",  head)
	setUd(data, "Triggerbot_Part", head)

	return data
end

local function getKey(player: Player): string
	return `team_{player.UserId}`
end

local function untrack(player: Player): ()
	local entry = tracked[player]
	if entry == nil then return end
	_remove_model_data(entry.key)
	tracked[player] = nil
end

local function clearAllTracking(): ()
	for player, entry in tracked do
		_remove_model_data(entry.key)
		tracked[player] = nil
	end
	if localActive then
		_clear_local_data()
		localActive = false
	end
end

RunService.PreModel:Connect(function(): ()
	if not _is_rbx_active() then return end

	local state = getGameState()
	if not isRoundActive(state) then
		clearAllTracking()
		return
	end

	local localTeam = getLocalTeam()
	local teamCheck = _is_team_check()

	for player in tracked do
		if player == nil or player.Parent == nil then
			untrack(player)
		end
	end

	local plist = Players:GetChildren()
	if plist == nil then return end

	for _, p in plist do
		if p == nil then continue end
		if not isUd(p) then continue end
		if not p:IsA("Player") then continue end
		if p == LocalPlayer then continue end
		local player = p :: Player

		local theirTeam = getPlayerTeam(player)
		if theirTeam == nil then
			untrack(player)
			continue
		end

		if teamCheck and localTeam ~= nil and theirTeam == localTeam then
			untrack(player)
			continue
		end

		local char = player.Character
		if char == nil then
			untrack(player)
			continue
		end
		if not isUd(char) then
			untrack(player)
			continue
		end

		local hum = getHumanoid(char)
		if hum == nil then
			untrack(player)
			continue
		end
		if not isUd(hum) then
			untrack(player)
			continue
		end

		if hum.Health <= 0 then
			untrack(player)
			continue
		end

		local parts = getR15Parts(char :: Model)
		if parts == nil then
			untrack(player)
			continue
		end

		local existing = tracked[player]
		if existing == nil or existing.char ~= char then
			if existing ~= nil then
				_remove_model_data(existing.key)
			end
			local key = getKey(player)
			_add_model_data(buildModelData(player, char :: Model, hum, parts, theirTeam), key)
			tracked[player] = {
				char = char :: Model,
				key  = key,
			}
		end
	end
end)

RunService.PostLocal:Connect(function(): ()
	if not _is_rbx_active() then return end

	local state = getGameState()
	if not isRoundActive(state) then
		clearAllTracking()
		return
	end

	local lpChar = LocalPlayer.Character
	if lpChar ~= nil and isUd(lpChar) then
		local hum        = getHumanoid(lpChar)
		local hrp        = findPart(lpChar :: Model, "HumanoidRootPart")
		local head       = findPart(lpChar :: Model, "Head")
		local lowerTorso = findPart(lpChar :: Model, "LowerTorso")
		local upperTorso = findPart(lpChar :: Model, "UpperTorso")
		local leftFoot   = findPart(lpChar :: Model, "LeftFoot")

		local rootPart: BasePart? = hrp
		if rootPart == nil then rootPart = lowerTorso end
		if rootPart == nil then rootPart = upperTorso end
		if rootPart == nil then rootPart = head end

		if rootPart ~= nil and isUd(rootPart) then
			local data: { [string]: any } = {
				Displayname = LocalPlayer.DisplayName,
				Username    = LocalPlayer.Name,
				Userid      = LocalPlayer.UserId,
				RigType     = 1,
			}
			setUd(data, "LocalPlayer", LocalPlayer)
			setUd(data, "Character",   lpChar)
			setUd(data, "Team",        LocalPlayer.Team)
			setUd(data, "RootPart",    rootPart)
			setUd(data, "Head",        head)
			setUd(data, "LowerTorso",  lowerTorso)
			setUd(data, "LeftFoot",    leftFoot)
			setUd(data, "Humanoid",    hum)
			if hum ~= nil and isUd(hum) then
				data.Health    = hum.Health
				data.MaxHealth = hum.MaxHealth
			end

			_override_local(data)
			localActive = true
		else
			if localActive then
				_clear_local_data()
				localActive = false
			end
		end
	else
		if localActive then
			_clear_local_data()
			localActive = false
		end
	end

	for player, entry in tracked do
		if player == nil or player.Parent == nil then
			_remove_model_data(entry.key)
			tracked[player] = nil
			continue
		end

		local pchar = player.Character
		if pchar == nil or not isUd(pchar) then
			_remove_model_data(entry.key)
			tracked[player] = nil
			continue
		end

		if pchar ~= entry.char then
			_remove_model_data(entry.key)
			tracked[player] = nil
			continue
		end

		local hum = getHumanoid(pchar)
		if hum == nil or not isUd(hum) then
			_remove_model_data(entry.key)
			tracked[player] = nil
			continue
		end

		if hum.Health <= 0 then
			_remove_model_data(entry.key)
			tracked[player] = nil
			continue
		end

		local edit: { [string]: any } = {
			Health      = hum.Health,
			MaxHealth   = hum.MaxHealth,
			Whitelisted = false,
		}
		setUd(edit, "Humanoid", hum)
		_edit_model_data(edit, entry.key)
	end
end)

local configs: { [string]: any } = {}
init(configs)

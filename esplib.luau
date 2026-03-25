--!native
--!optimize 2

---- types ----
export type ConfigEntry = {
    Enabled         : boolean,
    BoxColor        : Color3,
    TextColor       : Color3,
    MaxDistance     : number,
    FontSize        : number,
    Box             : boolean,
    Name            : boolean,
    Distance        : boolean,
    Folder          : Instance?,
    Object          : Instance?,
    CustomName      : string,
    UseCustomName   : boolean,
    -- Object only
    MultiSameObject : boolean?,
    -- Folder only
    IncludeOnly     : { string }?,
    ExcludeObject   : { string }?,
}

type Entry = {
    part       : BasePart,  
    box_offset : vector,   
    box_half   : vector,    
    config     : ConfigEntry,
    box        : any?,
    label      : any?,
    dist_label : any?,
    visible    : boolean,
    prev_vis   : boolean,
    distance   : number,
    dist_floor : number,
    dist_str   : string,
    s_min_x    : number,
    s_min_y    : number,
    s_max_x    : number,
    s_max_y    : number,
    pos_dirty  : boolean,
    text_dirty : boolean,
}

type ObjMeta = { parent: Instance, name: string }

---- environment ----
local RunService  = game:GetService("RunService")
local Players     = game:GetService("Players")
local Workspace   = game:GetService("Workspace")
local Camera      = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

---- constants ----
local INF        = math.huge
local EMPTY_LIST : { string } = table.freeze({})

---- variables ----
local CONFIGS           : { [string]: ConfigEntry }  = {}
local entries           : { Entry }                  = {}
local known             : { [BasePart]: true }        = {}
local config_count      : { [ConfigEntry]: number }  = {}
local obj_meta          : { [ConfigEntry]: ObjMeta } = {}

---- functions ----
local v_mag      = vector.magnitude
local v_min      = vector.min
local v_max      = vector.max
local math_min   = math.min
local math_max   = math.max
local math_round = math.round
local vec2_new   = Vector2.new
local vc         = vector.create
local t_find     = table.find
local t_insert   = table.insert

local function is_list_active(list: { string }): boolean
    for _, v in list do
        if v ~= "" then return true end
    end
    return false
end

local function should_draw(name: string, inc: { string }?, exc: { string }?): boolean
    if inc and is_list_active(inc) then
        return t_find(inc, name) ~= nil
    end
    if exc and is_list_active(exc) then
        return t_find(exc, name) == nil
    end
    return true
end

local function project_corner(
    corner: vector,
    min_x: number, min_y: number,
    max_x: number, max_y: number,
    found: boolean
): (number, number, number, number, boolean)
    local s, v = Camera:WorldToScreenPoint(corner)
    if v then
        local sx, sy = s.X, s.Y
        return math_min(min_x, sx), math_min(min_y, sy),
               math_max(max_x, sx), math_max(max_y, sy), true
    end
    return min_x, min_y, max_x, max_y, found
end

local function resolve(obj: Instance): (BasePart?, string, { BasePart })
    if obj:IsA("BasePart") then
        return obj :: BasePart, obj.Name, { obj :: BasePart }
    end

    local cn    = obj.ClassName
    local name  = obj.Name
    local parts : { BasePart } = {}

    -- collect every BasePart in the subtree
    for _, desc in obj:GetDescendants() do
        if desc:IsA("BasePart") then
            t_insert(parts, desc :: BasePart)
        end
    end

    if #parts == 0 then return nil, name, parts end

    local primary: BasePart? = nil
    if cn == "Tool" or cn == "Accessory" then
        local handle = obj:FindFirstChild("Handle")
        if handle and handle:IsA("BasePart") then
            primary = handle :: BasePart
        end
    end
    if not primary and (cn == "Model" or cn == "Tool" or cn == "Accessory") then
        primary = (obj :: Model).PrimaryPart
    end
    if not primary then
        primary = parts[1]
    end

    return primary, name, parts
end

local function make_entry(part: BasePart, parts: { BasePart }, config: ConfigEntry, display: string): ()
    if known[part] then return end
    known[part] = true
    config_count[config] = (config_count[config] or 0) + 1

    local wmin = vc( INF,  INF,  INF)
    local wmax = vc(-INF, -INF, -INF)
    for _, p in parts do
        local pp = p.Position :: vector
        local ph = (p.Size    :: vector) * 0.5
        wmin = v_min(wmin, pp - ph)
        wmax = v_max(wmax, pp + ph)
    end
    local world_center = (wmin + wmax) * 0.5
    local box_offset   = world_center - (part.Position :: vector)
    local box_half     = (wmax - wmin) * 0.5

    local box: any? = nil
    if config.Box then
        box           = Drawing.new("Square")
        box.Visible   = false
        box.Filled    = false
        box.Color     = config.BoxColor
        box.Thickness = 1
    end

    local label: any? = nil
    if config.Name then
        label         = Drawing.new("Text")
        label.Visible = false
        label.Color   = config.TextColor
        label.Size    = config.FontSize
        label.Center  = true
        label.Outline = true
        label.Text    = display
    end

    local dist_label: any? = nil
    if config.Distance then
        dist_label         = Drawing.new("Text")
        dist_label.Visible = false
        dist_label.Color   = config.TextColor
        dist_label.Size    = config.FontSize
        dist_label.Center  = true
        dist_label.Outline = true
        dist_label.Text    = "0m"
    end

    table.insert(entries, {
        part       = part,
        box_offset = box_offset,
        box_half   = box_half,
        config     = config,
        box        = box,
        label      = label,
        dist_label = dist_label,
        visible    = false,
        prev_vis   = false,
        distance   = 0,
        dist_floor = -1,
        dist_str   = "0m",
        s_min_x    = 0, s_min_y = 0,
        s_max_x    = 0, s_max_y = 0,
        pos_dirty  = false,
        text_dirty = false,
    })
end

local function remove_entry(i: number): ()
    local entry  = entries[i]
    local config = entry.config
    known[entry.part]     = nil
    config_count[config]  = (config_count[config] or 1) - 1
    if entry.box        then entry.box:Remove()        end
    if entry.label      then entry.label:Remove()      end
    if entry.dist_label then entry.dist_label:Remove() end
    entries[i]        = entries[#entries]
    entries[#entries] = nil
end

local function scan(): ()
    local i = 1
    while i <= #entries do
        if entries[i].part.Parent == nil then
            remove_entry(i)
        else
            i += 1
        end
    end

    for _, config in CONFIGS do
        if not config.Enabled then continue end

        if config.Folder and config.Folder.Parent ~= nil then
            local inc = config.IncludeOnly
            local exc = config.ExcludeObject
            for _, child in config.Folder:GetChildren() do
                if should_draw(child.Name, inc, exc) then
                    local part, obj_name, parts = resolve(child)
                    if part then
                        make_entry(part, parts, config, if config.UseCustomName then config.CustomName else obj_name)
                    end
                end
            end

        elseif config.Object then
            local meta = obj_meta[config]
            if not meta then continue end

            local parent = meta.parent
            if not parent or parent.Parent == nil then continue end

            if config.MultiSameObject then
                for _, child in parent:GetChildren() do
                    if child.Name == meta.name then
                        local part, obj_name, parts = resolve(child)
                        if part then
                            make_entry(part, parts, config, if config.UseCustomName then config.CustomName else obj_name)
                        end
                    end
                end
            else
                if (config_count[config] or 0) == 0 then
                    for _, child in parent:GetChildren() do
                        if child.Name == meta.name then
                            local part, obj_name, parts = resolve(child)
                            if part then
                                make_entry(part, parts, config, if config.UseCustomName then config.CustomName else obj_name)
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end

local function on_pre_local(): ()
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
    local lpos : vector? = if hrp then hrp.Position :: vector else nil

    for _, entry in entries do
        if not entry.config.Enabled then
            entry.visible = false
            continue
        end

        local part = entry.part
        local pos  = part.Position :: vector
        local vis  = false

        if lpos then
            local dist = v_mag(pos - lpos)
            if dist <= entry.config.MaxDistance then
                entry.distance = dist
                vis = true

                if entry.config.Distance then
                    local df = math_round(dist)
                    if df ~= entry.dist_floor then
                        entry.dist_floor = df
                        entry.dist_str   = `{df}m`
                        entry.text_dirty = true
                    end
                end

                local center       = pos + entry.box_offset
                local hs           = entry.box_half
                local hx, hy, hz   = hs.x, hs.y, hs.z

                local min_x, min_y =  INF,  INF
                local max_x, max_y = -INF, -INF
                local found        = false

                min_x, min_y, max_x, max_y, found = project_corner(center + vc( hx,  hy,  hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(center + vc(-hx,  hy,  hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(center + vc( hx, -hy,  hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(center + vc(-hx, -hy,  hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(center + vc( hx,  hy, -hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(center + vc(-hx,  hy, -hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(center + vc( hx, -hy, -hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(center + vc(-hx, -hy, -hz), min_x, min_y, max_x, max_y, found)

                if found then
                    if  min_x ~= entry.s_min_x or min_y ~= entry.s_min_y
                     or max_x ~= entry.s_max_x or max_y ~= entry.s_max_y then
                        entry.s_min_x   = min_x
                        entry.s_min_y   = min_y
                        entry.s_max_x   = max_x
                        entry.s_max_y   = max_y
                        entry.pos_dirty = true
                    end
                else
                    vis = false
                end
            end
        end

        entry.visible = vis
    end
end

local function on_render(): ()
    for _, entry in entries do
        local vis = entry.visible

        if vis ~= entry.prev_vis then
            entry.prev_vis = vis
            if entry.box        then entry.box.Visible        = vis end
            if entry.label      then entry.label.Visible      = vis end
            if entry.dist_label then entry.dist_label.Visible = vis end
        end

        if vis then
            if entry.pos_dirty then
                entry.pos_dirty    = false
                local min_x, min_y = entry.s_min_x, entry.s_min_y
                local max_x, max_y = entry.s_max_x, entry.s_max_y
                local mid_x        = (min_x + max_x) * 0.5
                local fs           = entry.config.FontSize

                if entry.box then
                    entry.box.Position = vec2_new(min_x, min_y)
                    entry.box.Size     = vec2_new(max_x - min_x, max_y - min_y)
                end
                if entry.label then
                    entry.label.Position = vec2_new(mid_x, min_y - fs - 2)
                end
                if entry.dist_label then
                    entry.dist_label.Position = vec2_new(mid_x, max_y + 4)
                end
            end

            if entry.text_dirty and entry.dist_label then
                entry.text_dirty      = false
                entry.dist_label.Text = entry.dist_str
            end
        end
    end
end

---- exports ----
return function(configs: { [string]: ConfigEntry }): ()
    for _, c in configs do table.freeze(c) end
    table.freeze(configs)
    CONFIGS = configs

    for _, config in configs do
    if config.Enabled and config.Object then
            obj_meta[config] = {
                parent = config.Object.Parent :: Instance,
                name   = config.Object.Name,
            }
        end
    end

    scan()

    RunService.PreModel:Connect(function(): () scan() end)
    RunService.PreLocal:Connect(on_pre_local)
    RunService.Render:Connect(on_render)
end

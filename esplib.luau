--!strict
--!optimize 2

---- types ----
export type ConfigEntry = {
    Enabled         : boolean,
    DrawMode        : number?,
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

type StaticEntry = {
    inst       : Instance,
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

type ImmediateEntry = {
    inst       : Instance,
    part       : BasePart,
    box_offset : vector,
    box_half   : vector,
    config     : ConfigEntry,
    display    : string,
    visible    : boolean,
    distance   : number,
    dist_floor : number,
    dist_str   : string,
    s_min_x    : number,
    s_min_y    : number,
    s_max_x    : number,
    s_max_y    : number,
}

type DynamicEntry = {
    inst       : Instance,
    part       : BasePart,
    config     : ConfigEntry,
    point      : any,
    cluster    : any,
    box        : any?,
    label      : any?,
    dist_label : any?,
    visible    : boolean,
    prev_vis   : boolean,
    distance   : number,
    dist_floor : number,
    dist_str   : string,
}

type ObjMeta = { parent: Instance?, name: string }

---- environment ----
local RunService  = game:GetService("RunService")
local Players     = game:GetService("Players")
local Workspace   = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

---- constants ----
local INF     = math.huge
local WEAK_MT = table.freeze({ __mode = "k" })

local BOX_SIZE      = UDim2.fromScale(1, 1)
local LABEL_SIZE    = UDim2.fromScale(1, 1)
local ANCHOR_CENTER = Vector2.new(0.5, 0.5)
local ANCHOR_TOP    = Vector2.new(0.5, 1)
local ANCHOR_BOTTOM = Vector2.new(0.5, 0)

---- variables ----
local CONFIGS           : { [string]: ConfigEntry }   = {}
local static_entries    : { StaticEntry }             = {}
local immediate_entries : { ImmediateEntry }          = {}
local dynamic_entries   : { DynamicEntry }            = {}
local known             : { [BasePart]: true? }       = setmetatable({}, WEAK_MT) :: any
local known_children    : { [Instance]: true? }       = setmetatable({}, WEAK_MT) :: any
local config_count      : { [ConfigEntry]: number? }  = {}
local obj_meta          : { [ConfigEntry]: ObjMeta? } = {}

---- fastcalls ----
local v_mag      = vector.magnitude
local v_min      = vector.min
local v_max      = vector.max
local math_min   = math.min
local math_max   = math.max
local math_round = math.round
local vec2_new   = Vector2.new
local vc         = vector.create
local t_find     = table.find

local Drawing_new    = Drawing.new
local Drawing_attach = Drawing.attach
local PI_new         = PointInstance.new
local PM_new         = PointModel.new
local DI_Rect        = DrawingImmediate.Rectangle
local DI_OText       = DrawingImmediate.OutlinedText

local function is_list_active(list: { string }): boolean
    for _, v in list do
        if v ~= "" then return true end
    end
    return false
end

local function should_draw(name: string, inc: { string }?, exc: { string }?): boolean
    if inc ~= nil and is_list_active(inc) then
        return t_find(inc, name) ~= nil
    end
    if exc ~= nil and is_list_active(exc) then
        return t_find(exc, name) == nil
    end
    return true
end

@native
local function project_corner(
    cam: any,
    corner: vector,
    min_x: number, min_y: number,
    max_x: number, max_y: number,
    found: boolean
): (number, number, number, number, boolean)
    local s, v = cam:WorldToScreenPoint(corner)
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

    for _, desc in obj:GetDescendants() do
        if desc:IsA("BasePart") then
            parts[#parts + 1] = desc :: BasePart
        end
    end

    if #parts == 0 then return nil, name, parts end

    local primary: BasePart? = nil
    if cn == "Tool" or cn == "Accessory" then
        local handle = obj:FindFirstChild("Handle")
        if handle ~= nil and handle:IsA("BasePart") then
            primary = handle :: BasePart
        end
    end
    if primary == nil and (cn == "Model" or cn == "Tool" or cn == "Accessory") then
        primary = (obj :: Model).PrimaryPart
    end
    if primary == nil then
        primary = parts[1]
    end

    return primary, name, parts
end

local function compute_bbox(parts: { BasePart }, anchor_pos: vector): (vector, vector)
    local wmin = vc( INF,  INF,  INF)
    local wmax = vc(-INF, -INF, -INF)
    for _, p in parts do
        local pp = p.Position :: vector
        local ph = (p.Size    :: vector) * 0.5
        wmin = v_min(wmin, pp - ph)
        wmax = v_max(wmax, pp + ph)
    end
    local center = (wmin + wmax) * 0.5
    return center - anchor_pos, (wmax - wmin) * 0.5
end

local function make_static_entry(inst: Instance, part: BasePart, parts: { BasePart }, config: ConfigEntry, display: string): ()
    local box_offset, box_half = compute_bbox(parts, part.Position :: vector)

    local box: any? = nil
    if config.Box then
        box           = Drawing_new("Square")
        box.Visible   = false
        box.Filled    = false
        box.Color     = config.BoxColor
        box.Thickness = 1
    end

    local label: any? = nil
    if config.Name then
        label         = Drawing_new("Text")
        label.Visible = false
        label.Color   = config.TextColor
        label.Size    = config.FontSize
        label.Center  = true
        label.Outline = true
        label.Text    = display
    end

    local dist_label: any? = nil
    if config.Distance then
        dist_label         = Drawing_new("Text")
        dist_label.Visible = false
        dist_label.Color   = config.TextColor
        dist_label.Size    = config.FontSize
        dist_label.Center  = true
        dist_label.Outline = true
        dist_label.Text    = "0m"
    end

    static_entries[#static_entries + 1] = {
        inst       = inst,
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
    }
end

local function make_immediate_entry(inst: Instance, part: BasePart, parts: { BasePart }, config: ConfigEntry, display: string): ()
    local box_offset, box_half = compute_bbox(parts, part.Position :: vector)

    immediate_entries[#immediate_entries + 1] = {
        inst       = inst,
        part       = part,
        box_offset = box_offset,
        box_half   = box_half,
        config     = config,
        display    = display,
        visible    = false,
        distance   = 0,
        dist_floor = -1,
        dist_str   = "0m",
        s_min_x    = 0, s_min_y = 0,
        s_max_x    = 0, s_max_y = 0,
    }
end

local function make_dynamic_entry(inst: Instance, part: BasePart, parts: { BasePart }, config: ConfigEntry, display: string): ()
    local point: any
    if inst:IsA("Model") then
        point = PM_new(inst :: any)
    else
        point = PI_new(part)
    end

    local attach_cfg: { [any]: any } = {}

    local box: any? = nil
    if config.Box then
        box           = Drawing_new("Square")
        box.Visible   = false
        box.Filled    = false
        box.Color     = config.BoxColor
        box.Thickness = 1
        attach_cfg[box] = { Link = point, Size = BOX_SIZE, AnchorPoint = ANCHOR_CENTER }
    end

    local label: any? = nil
    if config.Name then
        label         = Drawing_new("Text")
        label.Visible = false
        label.Color   = config.TextColor
        label.Size    = config.FontSize
        label.Center  = true
        label.Outline = true
        label.Text    = display
        attach_cfg[label] = { Link = point, Size = LABEL_SIZE, AnchorPoint = ANCHOR_TOP }
    end

    local dist_label: any? = nil
    if config.Distance then
        dist_label         = Drawing_new("Text")
        dist_label.Visible = false
        dist_label.Color   = config.TextColor
        dist_label.Size    = config.FontSize
        dist_label.Center  = true
        dist_label.Outline = true
        dist_label.Text    = "0m"
        attach_cfg[dist_label] = { Link = point, Size = LABEL_SIZE, AnchorPoint = ANCHOR_BOTTOM }
    end

    local cluster = Drawing_attach(attach_cfg)

    dynamic_entries[#dynamic_entries + 1] = {
        inst       = inst,
        part       = part,
        config     = config,
        point      = point,
        cluster    = cluster,
        box        = box,
        label      = label,
        dist_label = dist_label,
        visible    = false,
        prev_vis   = false,
        distance   = 0,
        dist_floor = -1,
        dist_str   = "0m",
    }
end

local function make_entry(inst: Instance, part: BasePart, parts: { BasePart }, config: ConfigEntry, display: string): ()
    if known[part] ~= nil then return end
    if not (config.Box or config.Name or config.Distance) then return end

    known[part]          = true
    known_children[inst] = true
    config_count[config] = (config_count[config] or 0) + 1

    local mode = config.DrawMode or 0
    if mode == 1 then
        make_immediate_entry(inst, part, parts, config, display)
    elseif mode == 2 then
        make_dynamic_entry(inst, part, parts, config, display)
    else
        make_static_entry(inst, part, parts, config, display)
    end
end

local function remove_static_entry(i: number): ()
    local entry  = static_entries[i]
    local config = entry.config
    known[entry.part]          = nil
    known_children[entry.inst] = nil
    config_count[config]       = (config_count[config] or 1) - 1
    if entry.box ~= nil        then entry.box:Remove()        end
    if entry.label ~= nil      then entry.label:Remove()      end
    if entry.dist_label ~= nil then entry.dist_label:Remove() end
    static_entries[i]               = static_entries[#static_entries]
    static_entries[#static_entries] = nil
end

local function remove_immediate_entry(i: number): ()
    local entry  = immediate_entries[i]
    local config = entry.config
    known[entry.part]          = nil
    known_children[entry.inst] = nil
    config_count[config]       = (config_count[config] or 1) - 1
    immediate_entries[i]                  = immediate_entries[#immediate_entries]
    immediate_entries[#immediate_entries] = nil
end

local function remove_dynamic_entry(i: number): ()
    local entry  = dynamic_entries[i]
    local config = entry.config
    known[entry.part]          = nil
    known_children[entry.inst] = nil
    config_count[config]       = (config_count[config] or 1) - 1
    entry.cluster:Destroy()
    entry.point:Destroy()
    dynamic_entries[i]                = dynamic_entries[#dynamic_entries]
    dynamic_entries[#dynamic_entries] = nil
end

local function scan(): ()
    local i = 1
    while i <= #static_entries do
        if static_entries[i].part.Parent == nil then
            remove_static_entry(i)
        else
            i += 1
        end
    end

    i = 1
    while i <= #immediate_entries do
        if immediate_entries[i].part.Parent == nil then
            remove_immediate_entry(i)
        else
            i += 1
        end
    end

    i = 1
    while i <= #dynamic_entries do
        if dynamic_entries[i].part.Parent == nil then
            remove_dynamic_entry(i)
        else
            i += 1
        end
    end

    for _, config in CONFIGS do
        if not config.Enabled then continue end

        if config.Folder ~= nil and config.Folder.Parent ~= nil then
            local inc = config.IncludeOnly
            local exc = config.ExcludeObject
            for _, child in config.Folder:GetChildren() do
                if known_children[child] ~= nil then continue end
                if should_draw(child.Name, inc, exc) then
                    local part, obj_name, parts = resolve(child)
                    if part ~= nil then
                        make_entry(child, part, parts, config, if config.UseCustomName then config.CustomName else obj_name)
                    end
                end
            end

        elseif config.Object ~= nil then
            local meta = obj_meta[config]
            if meta == nil then continue end

            local parent = meta.parent
            if parent == nil or parent.Parent == nil then continue end

            if config.MultiSameObject == true then
                for _, child in parent:GetChildren() do
                    if child.Name == meta.name and known_children[child] == nil then
                        local part, obj_name, parts = resolve(child)
                        if part ~= nil then
                            make_entry(child, part, parts, config, if config.UseCustomName then config.CustomName else obj_name)
                        end
                    end
                end
            else
                if (config_count[config] or 0) == 0 then
                    for _, child in parent:GetChildren() do
                        if child.Name == meta.name then
                            local part, obj_name, parts = resolve(child)
                            if part ~= nil then
                                make_entry(child, part, parts, config, if config.UseCustomName then config.CustomName else obj_name)
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end

@native
local function on_pre_local(): ()
    local cam = Workspace.CurrentCamera
    if cam == nil then return end

    local char: Instance?  = LocalPlayer.Character
    local hrp:  BasePart?  = if char ~= nil then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
    local lpos: vector?    = if hrp ~= nil  then hrp.Position :: vector else nil

 
    for _, entry in static_entries do
        if not entry.config.Enabled then
            entry.visible = false
            continue
        end

        local part = entry.part
        local pos  = part.Position :: vector
        local vis  = false

        if lpos ~= nil then
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

                local center     = pos + entry.box_offset
                local hs         = entry.box_half
                local hx, hy, hz = hs.x, hs.y, hs.z

                local min_x, min_y =  INF,  INF
                local max_x, max_y = -INF, -INF
                local found        = false

                min_x, min_y, max_x, max_y, found = project_corner(cam, center + vc( hx,  hy,  hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(cam, center + vc(-hx,  hy,  hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(cam, center + vc( hx, -hy,  hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(cam, center + vc(-hx, -hy,  hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(cam, center + vc( hx,  hy, -hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(cam, center + vc(-hx,  hy, -hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(cam, center + vc( hx, -hy, -hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(cam, center + vc(-hx, -hy, -hz), min_x, min_y, max_x, max_y, found)

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

   
    for _, entry in immediate_entries do
        if not entry.config.Enabled then
            entry.visible = false
            continue
        end

        local part = entry.part
        local pos  = part.Position :: vector
        local vis  = false

        if lpos ~= nil then
            local dist = v_mag(pos - lpos)
            if dist <= entry.config.MaxDistance then
                entry.distance = dist
                vis = true

                if entry.config.Distance then
                    local df = math_round(dist)
                    if df ~= entry.dist_floor then
                        entry.dist_floor = df
                        entry.dist_str   = `{df}m`
                    end
                end

                local center     = pos + entry.box_offset
                local hs         = entry.box_half
                local hx, hy, hz = hs.x, hs.y, hs.z

                local min_x, min_y =  INF,  INF
                local max_x, max_y = -INF, -INF
                local found        = false

                min_x, min_y, max_x, max_y, found = project_corner(cam, center + vc( hx,  hy,  hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(cam, center + vc(-hx,  hy,  hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(cam, center + vc( hx, -hy,  hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(cam, center + vc(-hx, -hy,  hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(cam, center + vc( hx,  hy, -hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(cam, center + vc(-hx,  hy, -hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(cam, center + vc( hx, -hy, -hz), min_x, min_y, max_x, max_y, found)
                min_x, min_y, max_x, max_y, found = project_corner(cam, center + vc(-hx, -hy, -hz), min_x, min_y, max_x, max_y, found)

                if found then
                    entry.s_min_x = min_x
                    entry.s_min_y = min_y
                    entry.s_max_x = max_x
                    entry.s_max_y = max_y
                else
                    vis = false
                end
            end
        end

        entry.visible = vis
    end

 
    for _, entry in dynamic_entries do
        local cfg = entry.config
        local vis = false

        if cfg.Enabled and lpos ~= nil then
            local dist = v_mag((entry.part.Position :: vector) - lpos)
            if dist <= cfg.MaxDistance then
                entry.distance = dist
                vis = true

                if cfg.Distance and entry.dist_label ~= nil then
                    local df = math_round(dist)
                    if df ~= entry.dist_floor then
                        entry.dist_floor      = df
                        entry.dist_str        = `{df}m`
                        entry.dist_label.Text = entry.dist_str
                    end
                end
            end
        end

        if vis ~= entry.prev_vis then
            entry.prev_vis = vis
            if entry.box ~= nil        then entry.box.Visible        = vis end
            if entry.label ~= nil      then entry.label.Visible      = vis end
            if entry.dist_label ~= nil then entry.dist_label.Visible = vis end
        end

        entry.visible = vis
    end
end

@native
local function on_render(): ()
    for _, entry in static_entries do
        local vis = entry.visible

        if vis ~= entry.prev_vis then
            entry.prev_vis = vis
            if entry.box ~= nil        then entry.box.Visible        = vis end
            if entry.label ~= nil      then entry.label.Visible      = vis end
            if entry.dist_label ~= nil then entry.dist_label.Visible = vis end
        end

        if vis then
            if entry.pos_dirty then
                entry.pos_dirty    = false
                local min_x, min_y = entry.s_min_x, entry.s_min_y
                local max_x, max_y = entry.s_max_x, entry.s_max_y
                local mid_x        = (min_x + max_x) * 0.5
                local fs           = entry.config.FontSize

                if entry.box ~= nil then
                    entry.box.Position = vec2_new(min_x, min_y)
                    entry.box.Size     = vec2_new(max_x - min_x, max_y - min_y)
                end
                if entry.label ~= nil then
                    entry.label.Position = vec2_new(mid_x, min_y - fs - 2)
                end
                if entry.dist_label ~= nil then
                    entry.dist_label.Position = vec2_new(mid_x, max_y + 4)
                end
            end

            if entry.text_dirty and entry.dist_label ~= nil then
                entry.text_dirty      = false
                entry.dist_label.Text = entry.dist_str
            end
        end
    end

    for _, entry in immediate_entries do
        if not entry.visible then continue end

        local cfg          = entry.config
        local min_x, min_y = entry.s_min_x, entry.s_min_y
        local max_x, max_y = entry.s_max_x, entry.s_max_y
        local mid_x        = (min_x + max_x) * 0.5
        local fs           = cfg.FontSize

        if cfg.Box then
            DI_Rect(
                vec2_new(min_x, min_y),
                vec2_new(max_x - min_x, max_y - min_y),
                cfg.BoxColor, 1, 1
            )
        end
        if cfg.Name then
            DI_OText(vec2_new(mid_x, min_y - fs - 2), fs, cfg.TextColor, 1, entry.display, true)
        end
        if cfg.Distance then
            DI_OText(vec2_new(mid_x, max_y + 4), fs, cfg.TextColor, 1, entry.dist_str, true)
        end
    end

end

---- exports ----
local function init(configs: { [string]: ConfigEntry }): ()
    for _, c in configs do table.freeze(c) end
    table.freeze(configs)
    CONFIGS = configs

    for _, config in configs do
        if config.Enabled and config.Object ~= nil then
            obj_meta[config] = {
                parent = config.Object.Parent,
                name   = config.Object.Name,
            }
        end
    end

    scan()

    RunService.PreModel:Connect(function(): () scan() end)
    RunService.PreLocal:Connect(on_pre_local)
    RunService.Render:Connect(on_render)
end

return init

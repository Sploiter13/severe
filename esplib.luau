--!strict
--!optimize 2

export type ConfigEntry = {
    Enabled            : boolean,
    DrawMode           : number?,
    BoxColor           : Color3,
    TextColor          : Color3,
    MaxDistance        : number,
    FontSize           : number,
    Box                : boolean,
    Name               : boolean,
    Distance           : boolean,
    Folder             : Instance?,
    Object             : Instance?,
    CustomName         : string,
    UseCustomName      : boolean,
    MultiSameObject    : boolean?,
    IncludeOnly        : { string }?,
    ExcludeObject      : { string }?,
    IncludeAttributes  : { [string]: string }?,
    ExcludeAttributes  : { [string]: string }?,
    Filter             : ((Instance) -> boolean)?,
    Highlight          : boolean?,
    Fill               : boolean?,
    Outline            : boolean?,
    FillTransp         : number?,
    FillColor          : Color3?,
    OutlineColor       : Color3?,
    OutlineThickness   : number?,
    Inline             : boolean?,
    InlineColor        : Color3?,
    InlineThickness    : number?,
    MainThickness      : number?,
}

type HighlightPart = {
    part      : BasePart,
    hx        : number,
    hy        : number,
    hz        : number,
    last_pos  : vector,
    last_look : vector,
    last_up   : vector,
    last_size : vector,
    wc1       : vector,
    wc2       : vector,
    wc3       : vector,
    wc4       : vector,
    wc5       : vector,
    wc6       : vector,
    wc7       : vector,
    wc8       : vector,
    sc_verts  : { Vector2 },
    sc_n      : number,
    sc_min_x  : number,
    sc_min_y  : number,
    sc_max_x  : number,
    sc_max_y  : number,
}

type StaticEntry = {
    inst       : Instance,
    part       : BasePart,
    part_id    : number,
    inst_id    : number,
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
    prep_box_pos    : Vector2,
    prep_box_size   : Vector2,
    prep_label_pos  : Vector2,
    prep_dist_pos   : Vector2,
}

type ImmediateEntry = {
    inst       : Instance,
    part       : BasePart,
    part_id    : number,
    inst_id    : number,
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
    prep_box_pos    : Vector2,
    prep_box_size   : Vector2,
    prep_label_pos  : Vector2,
    prep_dist_pos   : Vector2,
}

type DynamicEntry = {
    inst       : Instance,
    part       : BasePart,
    part_id    : number,
    inst_id    : number,
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

local RunService  = game:GetService("RunService")
local Players     = game:GetService("Players")
local Workspace   = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local INF = math.huge

local BOX_SIZE      = UDim2.fromScale(1, 1)
local LABEL_SIZE    = UDim2.fromScale(1, 1)
local ANCHOR_CENTER = Vector2.new(0.5, 0.5)
local ANCHOR_TOP    = Vector2.new(0.5, 1)
local ANCHOR_BOTTOM = Vector2.new(0.5, 0)

local PLACEHOLDER_VEC2 = Vector2.new(0, 0)

local v_mag      = vector.magnitude
local v_min      = vector.min
local v_max      = vector.max
local v_zero     = vector.zero
local math_min   = math.min
local math_max   = math.max
local math_abs   = math.abs
local math_round = math.round
local math_sqrt  = math.sqrt
local vec2_new   = Vector2.new
local vc         = vector.create
local t_find     = table.find
local t_create   = table.create
local t_sort     = table.sort
local os_clock   = os.clock

local Drawing_new    = Drawing.new
local Drawing_attach = Drawing.attach
local PI_new         = PointInstance.new
local PM_new         = PointModel.new
local DI_Rect        = DrawingImmediate.Rectangle
local DI_OText       = DrawingImmediate.OutlinedText
local DI_FTri        = DrawingImmediate.FilledTriangle
local DI_Line        = DrawingImmediate.Line

local CONFIGS           : { [string]: ConfigEntry }   = {}
local static_entries    : { StaticEntry }             = {}
local immediate_entries : { ImmediateEntry }          = {}
local dynamic_entries   : { DynamicEntry }            = {}
local known          : { [number]: true? }            = {}
local known_children : { [number]: true? }            = {}
local config_count      : { [ConfigEntry]: number? }  = {}
local obj_meta          : { [ConfigEntry]: ObjMeta? } = {}

local last_cam_pos  : vector? = nil
local last_cam_look : vector? = nil
local last_cam_up   : vector? = nil
local cam_dirty     : boolean = true

local pending_static      : { StaticEntry }    = t_create(64)
local pending_static_n    : number             = 0
local pending_immediate   : { ImmediateEntry } = t_create(64)
local pending_immediate_n : number             = 0

local function _initial_viewport(): (number, number)
    local cam = Workspace.CurrentCamera
    if cam == nil then return 0, 0 end
    local vp = cam.ViewportSize
    return vp.X, vp.Y
end
local cam_vp_x : number, cam_vp_y : number = _initial_viewport()

local function _inst_parent(i: Instance): Instance? return i.Parent end
local function _inst_class(i: Instance): string return i.ClassName end
local function _inst_data(i: any): any return i.Data end
local function _inst_children(i: Instance): { Instance } return i:GetChildren() end
local function _inst_transp(p: any): number return p.Transparency end

local function validateParent(inst: Instance?): boolean
    if inst == nil then return false end
    local ok1, parent = pcall(_inst_parent, inst :: Instance)
    if not ok1 or parent == nil then return false end
    local ok2, cn = pcall(_inst_class, inst :: Instance)
    if not ok2 or cn == "" then return false end
    local ok3, data = pcall(_inst_data, inst :: any)
    if not ok3 then return false end
    local id = tonumber(data :: any)
    return id ~= nil and id ~= 0
end

local function getDataId(inst: Instance): number?
    local ok, data = pcall(_inst_data, inst :: any)
    if not ok or data == nil then return nil end
    local id = tonumber(data :: any)
    return if id ~= nil and id ~= 0 then id else nil
end

local cfg_inc_active      : { [ConfigEntry]: boolean } = {}
local cfg_exc_active      : { [ConfigEntry]: boolean } = {}
local cfg_inc_attr_active : { [ConfigEntry]: boolean } = {}
local cfg_exc_attr_active : { [ConfigEntry]: boolean } = {}


local function _list_active(list: { string }?): boolean
    if list == nil then return false end
    for _, v in list do
        if v ~= "" then return true end
    end
    return false
end

local function _attr_map_active(map: { [string]: string }?): boolean
    if map == nil then return false end
    for _ in map do return true end
    return false
end

local function should_draw(child: Instance, cfg: ConfigEntry): boolean
    local name = child.Name

    local inc = cfg.IncludeOnly
    if inc ~= nil and cfg_inc_active[cfg] then
        if t_find(inc, name) == nil then return false end
    end

    local exc = cfg.ExcludeObject
    if exc ~= nil and cfg_exc_active[cfg] then
        if t_find(exc, name) ~= nil then return false end
    end

    local inc_attr = cfg.IncludeAttributes
    if inc_attr ~= nil and cfg_inc_attr_active[cfg] then
        for attr_name, attr_value in inc_attr do
            local v = child:GetAttribute(attr_name)
            if v == nil then return false end
            if attr_value ~= "" and tostring(v) ~= attr_value then return false end
        end
    end

    local exc_attr = cfg.ExcludeAttributes
    if exc_attr ~= nil and cfg_exc_attr_active[cfg] then
        for attr_name, attr_value in exc_attr do
            local v = child:GetAttribute(attr_name)
            if v ~= nil then
                if attr_value == "" or tostring(v) == attr_value then return false end
            end
        end
    end

    local filter = cfg.Filter
    if filter ~= nil then
        if not filter(child) then return false end
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

local function make_static_entry(inst: Instance, part: BasePart, parts: { BasePart }, config: ConfigEntry, display: string, part_id: number, inst_id: number): ()
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
        part_id    = part_id,
        inst_id    = inst_id,
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
        prep_box_pos    = PLACEHOLDER_VEC2,
        prep_box_size   = PLACEHOLDER_VEC2,
        prep_label_pos  = PLACEHOLDER_VEC2,
        prep_dist_pos   = PLACEHOLDER_VEC2,
    }
end

local function make_immediate_entry(inst: Instance, part: BasePart, parts: { BasePart }, config: ConfigEntry, display: string, part_id: number, inst_id: number): ()
    local box_offset, box_half = compute_bbox(parts, part.Position :: vector)


    immediate_entries[#immediate_entries + 1] = {
        inst       = inst,
        part       = part,
        part_id    = part_id,
        inst_id    = inst_id,
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
        prep_box_pos    = PLACEHOLDER_VEC2,
        prep_box_size   = PLACEHOLDER_VEC2,
        prep_label_pos  = PLACEHOLDER_VEC2,
        prep_dist_pos   = PLACEHOLDER_VEC2,
    }
end

local function make_dynamic_entry(inst: Instance, part: BasePart, parts: { BasePart }, config: ConfigEntry, display: string, part_id: number, inst_id: number): ()
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
        part_id    = part_id,
        inst_id    = inst_id,
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
    if not part:IsA("BasePart") then return end
    local partId = getDataId(part)
    local instId = getDataId(inst)
    if partId == nil or instId == nil then return end
    if known[partId] ~= nil then return end
    if not (config.Box or config.Name or config.Distance or config.Highlight) then return end

    known[partId]          = true
    known_children[instId] = true
    config_count[config]   = (config_count[config] or 0) + 1

    local mode = config.DrawMode or 0
    if mode == 1 then
        make_immediate_entry(inst, part, parts, config, display, partId, instId)
    elseif mode == 2 then
        make_dynamic_entry(inst, part, parts, config, display, partId, instId)
    else
        make_static_entry(inst, part, parts, config, display, partId, instId)
    end
end

local function remove_static_entry(i: number): ()
    local entry  = static_entries[i]
    local config = entry.config
    known[entry.part_id]          = nil
    known_children[entry.inst_id] = nil
    config_count[config]          = (config_count[config] or 1) - 1
    if entry.box ~= nil        then entry.box:Remove()        end
    if entry.label ~= nil      then entry.label:Remove()      end
    if entry.dist_label ~= nil then entry.dist_label:Remove() end
    static_entries[i]               = static_entries[#static_entries]
    static_entries[#static_entries] = nil
end

local function remove_immediate_entry(i: number): ()
    local entry  = immediate_entries[i]
    local config = entry.config
    known[entry.part_id]          = nil
    known_children[entry.inst_id] = nil
    config_count[config]          = (config_count[config] or 1) - 1
    immediate_entries[i]                  = immediate_entries[#immediate_entries]
    immediate_entries[#immediate_entries] = nil
end

local function remove_dynamic_entry(i: number): ()
    local entry  = dynamic_entries[i]
    local config = entry.config
    known[entry.part_id]          = nil
    known_children[entry.inst_id] = nil
    config_count[config]          = (config_count[config] or 1) - 1
    entry.cluster:Destroy()
    entry.point:Destroy()
    dynamic_entries[i]                = dynamic_entries[#dynamic_entries]
    dynamic_entries[#dynamic_entries] = nil
end

local function scan(): ()
    local folder_children: { [Instance]: { Instance } } = {}
    local live_ids: { [number]: boolean } = {}
    for _, config in CONFIGS do
        if not config.Enabled or config.Folder == nil then continue end
        local folder = config.Folder :: Instance
        if folder_children[folder] ~= nil then continue end
        local ok, ch = pcall(_inst_children, folder)
        local list: { Instance } = if ok and ch ~= nil then ch :: { Instance } else {}
        folder_children[folder] = list
        for _, child in list do
            local id = getDataId(child)
            if id ~= nil then live_ids[id] = true end
        end
    end

    local function gone(inst_id: number, part: BasePart, inst: Instance, cfg: ConfigEntry): boolean
        if cfg.Folder ~= nil and not live_ids[inst_id] then return true end
        return not validateParent(part) or not validateParent(inst)
    end

    local i = 1
    while i <= #static_entries do
        local e = static_entries[i]
        if gone(e.inst_id, e.part, e.inst, e.config) then
            remove_static_entry(i)
        else
            i += 1
        end
    end

    i = 1
    while i <= #immediate_entries do
        local e = immediate_entries[i]
        if gone(e.inst_id, e.part, e.inst, e.config) then
            remove_immediate_entry(i)
        else
            i += 1
        end
    end

    i = 1
    while i <= #dynamic_entries do
        local e = dynamic_entries[i]
        if gone(e.inst_id, e.part, e.inst, e.config) then
            remove_dynamic_entry(i)
        else
            i += 1
        end
    end

    for _, config in CONFIGS do
        if not config.Enabled then continue end

        if config.Folder ~= nil then
            local children = folder_children[config.Folder :: Instance]
            if children == nil then continue end
            for _, child in children do
                local childId = getDataId(child)
                if childId == nil or known_children[childId] ~= nil then continue end
                if should_draw(child, config) then
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
            if not validateParent(parent) then continue end
            if config.MultiSameObject == true then
                for _, child in (parent :: Instance):GetChildren() do
                    if child.Name == meta.name then
                        local childId = getDataId(child)
                        if childId ~= nil and known_children[childId] == nil then
                            local part, obj_name, parts = resolve(child)
                            if part ~= nil then
                                make_entry(child, part, parts, config, if config.UseCustomName then config.CustomName else obj_name)
                            end
                        end
                    end
                end
            else
                if (config_count[config] or 0) == 0 then
                    for _, child in (parent :: Instance):GetChildren() do
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
    if cam == nil then
        cam_dirty = false
        pending_static_n = 0
        pending_immediate_n = 0
        return
    end

    local ccf      = cam.CFrame
    local cam_pos  = ccf.Position   :: vector
    local cam_look = ccf.LookVector :: vector
    local cam_up   = ccf.UpVector   :: vector
    cam_dirty = (last_cam_pos == nil)
             or (cam_pos  ~= last_cam_pos)
             or (cam_look ~= last_cam_look)
             or (cam_up   ~= last_cam_up)
    last_cam_pos  = cam_pos
    last_cam_look = cam_look
    last_cam_up   = cam_up

    local vp = cam.ViewportSize
    cam_vp_x = vp.X
    cam_vp_y = vp.Y

    local char: Instance? = LocalPlayer.Character
    local hrp:  BasePart? = if char ~= nil then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
    local lpos: vector?   = if hrp  ~= nil then hrp.Position :: vector else nil

    local ps_n = 0
    for _, entry in static_entries do
        local cfg = entry.config
        if not cfg.Enabled or lpos == nil then
            entry.visible = false
            continue
        end

        if not validateParent(entry.part) then
            entry.visible = false
            continue
        end

        local pos  = entry.part.Position :: vector
        local dist = v_mag(pos - lpos)
        entry.distance = dist

        if dist > cfg.MaxDistance then
            entry.visible = false
            continue
        end

        if cfg.Distance then
            local df = math_round(dist)
            if df ~= entry.dist_floor then
                entry.dist_floor = df
                entry.dist_str   = `{df}m`
                entry.text_dirty = true
            end
        end

        ps_n += 1
        pending_static[ps_n] = entry
    end
    pending_static_n = ps_n

    local pi_n = 0
    for _, entry in immediate_entries do
        local cfg = entry.config
        if not cfg.Enabled or lpos == nil then
            entry.visible = false
            continue
        end

        if not validateParent(entry.part) then
            entry.visible = false
            continue
        end

        local pos  = entry.part.Position :: vector
        local dist = v_mag(pos - lpos)
        entry.distance = dist

        if dist > cfg.MaxDistance then
            entry.visible = false
            continue
        end

        if cfg.Distance then
            local df = math_round(dist)
            if df ~= entry.dist_floor then
                entry.dist_floor = df
                entry.dist_str   = `{df}m`
            end
        end

        pi_n += 1
        pending_immediate[pi_n] = entry
    end
    pending_immediate_n = pi_n

    for _, entry in dynamic_entries do
        local cfg = entry.config
        local vis = false

        if cfg.Enabled and lpos ~= nil and validateParent(entry.part) then
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
            if entry.box        ~= nil then entry.box.Visible        = vis end
            if entry.label      ~= nil then entry.label.Visible      = vis end
            if entry.dist_label ~= nil then entry.dist_label.Visible = vis end
        end

        entry.visible = vis
    end
end

@native
local function on_post_local(): ()
    local cam = Workspace.CurrentCamera
    if cam == nil then return end

    for i = 1, pending_static_n do
        local entry = pending_static[i]
        local cfg   = entry.config

        if not validateParent(entry.part) then
            entry.visible = false
            continue
        end

        if cfg.Box or cfg.Name or cfg.Distance then
            local pos        = entry.part.Position :: vector
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
                entry.visible = true
                if min_x ~= entry.s_min_x or min_y ~= entry.s_min_y
                or max_x ~= entry.s_max_x or max_y ~= entry.s_max_y then
                    entry.s_min_x = min_x
                    entry.s_min_y = min_y
                    entry.s_max_x = max_x
                    entry.s_max_y = max_y

                    local mid_x = (min_x + max_x) * 0.5
                    local fs    = cfg.FontSize
                    entry.prep_box_pos    = vec2_new(min_x, min_y)
                    entry.prep_box_size   = vec2_new(max_x - min_x, max_y - min_y)
                    entry.prep_label_pos  = vec2_new(mid_x, min_y - fs - 2)
                    entry.prep_dist_pos   = vec2_new(mid_x, max_y + 4)
                    entry.pos_dirty       = true
                end
            else
                entry.visible = false
            end
        else
            entry.visible = false
        end

    end

    for i = 1, pending_immediate_n do
        local entry = pending_immediate[i]
        local cfg   = entry.config

        if not validateParent(entry.part) then
            entry.visible = false
            continue
        end

        if cfg.Box or cfg.Name or cfg.Distance then
            local pos        = entry.part.Position :: vector
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
                entry.visible = true
                if min_x ~= entry.s_min_x or min_y ~= entry.s_min_y
                or max_x ~= entry.s_max_x or max_y ~= entry.s_max_y then
                    entry.s_min_x = min_x
                    entry.s_min_y = min_y
                    entry.s_max_x = max_x
                    entry.s_max_y = max_y

                    local mid_x = (min_x + max_x) * 0.5
                    local fs    = cfg.FontSize
                    entry.prep_box_pos   = vec2_new(min_x, min_y)
                    entry.prep_box_size  = vec2_new(max_x - min_x, max_y - min_y)
                    entry.prep_label_pos = vec2_new(mid_x, min_y - fs - 2)
                    entry.prep_dist_pos  = vec2_new(mid_x, max_y + 4)
                end
            else
                entry.visible = false
            end
        else
            entry.visible = false
        end

    end
end

local _hl_intersection_cuts : { number }  = {}
local _hl_blocking_polys    : { any }     = {}
local _hl_screen_polys      : { any }     = {}
local _hl_outline_segments  : { Vector2 } = {}
local _hl_lower_scratch     : { Vector2 } = t_create(16)
local _hl_upper_scratch     : { Vector2 } = t_create(16)

local function _hl_cross2d(o: Vector2, a: Vector2, b: Vector2): number
    return (a.X - o.X) * (b.Y - o.Y) - (a.Y - o.Y) * (b.X - o.X)
end

local function _hl_sort_xy(a: Vector2, b: Vector2): boolean
    return a.X < b.X or (a.X == b.X and a.Y < b.Y)
end

local function _hl_convex_hull(pts: { Vector2 }): { Vector2 }
    local n = #pts
    if n < 3 then return pts end
    table.sort(pts, _hl_sort_xy)

    local lower = _hl_lower_scratch
    local upper = _hl_upper_scratch
    local lc, uc = 0, 0

    for i = 1, n do
        local p = pts[i]
        while lc >= 2 and _hl_cross2d(lower[lc - 1], lower[lc], p) <= 0 do
            lower[lc] = nil; lc -= 1
        end
        lc += 1; lower[lc] = p
    end
    for i = n, 1, -1 do
        local p = pts[i]
        while uc >= 2 and _hl_cross2d(upper[uc - 1], upper[uc], p) <= 0 do
            upper[uc] = nil; uc -= 1
        end
        uc += 1; upper[uc] = p
    end

    local hull: { Vector2 } = t_create(lc + uc)
    local hc = 0
    for i = 1, lc - 1 do hc += 1; hull[hc] = lower[i] end
    for i = 1, uc - 1 do hc += 1; hull[hc] = upper[i] end
    if hc > 0 then hull[hc + 1] = hull[1] end
    return hull
end

local function _hl_point_in_poly(px: number, py: number, poly: { Vector2 }, bb: any): boolean
    if px < bb.MinX or px > bb.MaxX or py < bb.MinY or py > bb.MaxY then return false end
    local inside = false
    local prev   = #poly
    for cur = 1, #poly do
        local cv = poly[cur]
        local pv = poly[prev]
        if ((cv.Y > py) ~= (pv.Y > py)) and
           (px < (pv.X - cv.X) * (py - cv.Y) / (pv.Y - cv.Y) + cv.X) then
            inside = not inside
        end
        prev = cur
    end
    return inside
end

local function _hl_seg_intersect(p1x: number, p1y: number, p2x: number, p2y: number,
                                  p3x: number, p3y: number, p4x: number, p4y: number): number?
    local denom = (p4y - p3y) * (p2x - p1x) - (p4x - p3x) * (p2y - p1y)
    if math_abs(denom) < 1e-5 then return nil end
    local t = ((p4x - p3x) * (p1y - p3y) - (p4y - p3y) * (p1x - p3x)) / denom
    local u = ((p2x - p1x) * (p1y - p3y) - (p2y - p1y) * (p1x - p3x)) / denom
    if t >= 0 and t <= 1 and u >= 0 and u <= 1 then return t end
    return nil
end

local function _hl_project_part(part: BasePart, cam: any, vp_x: number, vp_y: number): { Vector2 }
    local pos = part.Position
    local rv  = part.RightVector
    local uv  = part.UpVector
    local lv  = part.LookVector
    local px, py, pz   = pos.X, pos.Y, pos.Z
    local rvx, rvy, rvz = rv.X, rv.Y, rv.Z
    local uvx, uvy, uvz = uv.X, uv.Y, uv.Z
    local lvx, lvy, lvz = lv.X, lv.Y, lv.Z
    local sz  = part.Size
    local hx  = sz.X * 0.5
    local hy  = sz.Y * 0.5
    local hz  = sz.Z * 0.5
    local vp1 = vp_x + 100
    local vp2 = vp_y + 100

    local out: { Vector2 } = {}
    local n = 0
    local sp: any
    local vis: boolean
    local sx: number
    local sy: number

    sp, vis = cam:WorldToScreenPoint(vc(px + rvx*hx + uvx*hy + lvx*hz, py + rvy*hx + uvy*hy + lvy*hz, pz + rvz*hx + uvz*hy + lvz*hz))
    if vis then sx, sy = sp.X, sp.Y; if sx > -100 and sx < vp1 and sy > -100 and sy < vp2 then n += 1; out[n] = vec2_new(sx, sy) end end
    sp, vis = cam:WorldToScreenPoint(vc(px + rvx*hx + uvx*hy - lvx*hz, py + rvy*hx + uvy*hy - lvy*hz, pz + rvz*hx + uvz*hy - lvz*hz))
    if vis then sx, sy = sp.X, sp.Y; if sx > -100 and sx < vp1 and sy > -100 and sy < vp2 then n += 1; out[n] = vec2_new(sx, sy) end end
    sp, vis = cam:WorldToScreenPoint(vc(px + rvx*hx - uvx*hy + lvx*hz, py + rvy*hx - uvy*hy + lvy*hz, pz + rvz*hx - uvz*hy + lvz*hz))
    if vis then sx, sy = sp.X, sp.Y; if sx > -100 and sx < vp1 and sy > -100 and sy < vp2 then n += 1; out[n] = vec2_new(sx, sy) end end
    sp, vis = cam:WorldToScreenPoint(vc(px + rvx*hx - uvx*hy - lvx*hz, py + rvy*hx - uvy*hy - lvy*hz, pz + rvz*hx - uvz*hy - lvz*hz))
    if vis then sx, sy = sp.X, sp.Y; if sx > -100 and sx < vp1 and sy > -100 and sy < vp2 then n += 1; out[n] = vec2_new(sx, sy) end end
    sp, vis = cam:WorldToScreenPoint(vc(px - rvx*hx + uvx*hy + lvx*hz, py - rvy*hx + uvy*hy + lvy*hz, pz - rvz*hx + uvz*hy + lvz*hz))
    if vis then sx, sy = sp.X, sp.Y; if sx > -100 and sx < vp1 and sy > -100 and sy < vp2 then n += 1; out[n] = vec2_new(sx, sy) end end
    sp, vis = cam:WorldToScreenPoint(vc(px - rvx*hx + uvx*hy - lvx*hz, py - rvy*hx + uvy*hy - lvy*hz, pz - rvz*hx + uvz*hy - lvz*hz))
    if vis then sx, sy = sp.X, sp.Y; if sx > -100 and sx < vp1 and sy > -100 and sy < vp2 then n += 1; out[n] = vec2_new(sx, sy) end end
    sp, vis = cam:WorldToScreenPoint(vc(px - rvx*hx - uvx*hy + lvx*hz, py - rvy*hx - uvy*hy + lvy*hz, pz - rvz*hx - uvz*hy + lvz*hz))
    if vis then sx, sy = sp.X, sp.Y; if sx > -100 and sx < vp1 and sy > -100 and sy < vp2 then n += 1; out[n] = vec2_new(sx, sy) end end
    sp, vis = cam:WorldToScreenPoint(vc(px - rvx*hx - uvx*hy - lvx*hz, py - rvy*hx - uvy*hy - lvy*hz, pz - rvz*hx - uvz*hy - lvz*hz))
    if vis then sx, sy = sp.X, sp.Y; if sx > -100 and sx < vp1 and sy > -100 and sy < vp2 then n += 1; out[n] = vec2_new(sx, sy) end end

    return out
end

local function _hl_is_outer_edge(es: Vector2, ee: Vector2, pi: number, polys: { any }): boolean
    local tol = 0.1
    for oi = 1, #polys do
        if oi ~= pi then
            local ov = polys[oi].Vertices
            for vi = 1, #ov - 1 do
                local v1, v2 = ov[vi], ov[vi + 1]
                local same = math_abs(v1.X - es.X) < tol and math_abs(v1.Y - es.Y) < tol
                          and math_abs(v2.X - ee.X) < tol and math_abs(v2.Y - ee.Y) < tol
                local rev  = math_abs(v1.X - ee.X) < tol and math_abs(v1.Y - ee.Y) < tol
                          and math_abs(v2.X - es.X) < tol and math_abs(v2.Y - es.Y) < tol
                if same or rev then return false end
            end
        end
    end
    return true
end

local function _hl_normal(p1: Vector2, p2: Vector2): (number, number)
    local dx  = p2.X - p1.X
    local dy  = p2.Y - p1.Y
    local len = math_sqrt(dx * dx + dy * dy)
    if len < 0.001 then return 0, 0 end
    return -dy / len, dx / len
end

local function _hl_get_parts(inst: Instance): { BasePart }
    local out: { BasePart } = {}
    if inst:IsA("BasePart") then
        if (inst :: BasePart).Transparency < 1 then out[1] = inst :: BasePart end
        return out
    end
    local ok, children = pcall(_inst_children, inst)
    if not ok or children == nil then return out end
    for _, c in children do
        local cn = c.ClassName
        if (cn == "Part" or cn == "MeshPart" or cn == "UnionOperation") then
            local ok2, tr = pcall(_inst_transp, c :: any)
            if ok2 and tr < 1 then out[#out + 1] = c :: BasePart end
        end
    end
    return out
end

local function hl_render(inst: Instance, cfg: ConfigEntry, cam: any): ()
    local color          = cfg.BoxColor
    local show_outline   = cfg.Outline ~= false
    local outline_color  = cfg.OutlineColor  or Color3.fromRGB(0, 0, 0)
    local outline_thick  = cfg.OutlineThickness or 1
    local show_inline    = cfg.Inline or false
    local inline_color   = cfg.InlineColor   or outline_color
    local inline_thick   = cfg.InlineThickness or outline_thick
    local show_fill      = cfg.Fill or false
    local fill_color     = cfg.FillColor     or color
    local fill_opacity   = cfg.FillTransp    or 1
    local main_thick     = cfg.MainThickness or 1

    local segs    = _hl_outline_segments
    local seg_n   = 0
    for i = 1, #segs do segs[i] = nil end

    local valid_parts = _hl_get_parts(inst)
    if #valid_parts == 0 then return end

    local polys   = _hl_screen_polys
    local poly_n  = 0
    local vp_x    = cam_vp_x
    local vp_y    = cam_vp_y

    for pi = 1, #valid_parts do
        local spts = _hl_project_part(valid_parts[pi], cam, vp_x, vp_y)
        if #spts >= 3 then
            local hull = _hl_convex_hull(spts)
            local min_x, min_y =  100000,  100000
            local max_x, max_y = -100000, -100000
            for _, v in hull do
                if v.X < min_x then min_x = v.X end
                if v.X > max_x then max_x = v.X end
                if v.Y < min_y then min_y = v.Y end
                if v.Y > max_y then max_y = v.Y end
            end
            poly_n += 1
            polys[poly_n] = {
                Vertices = hull,
                BBox     = { MinX = min_x, MinY = min_y, MaxX = max_x, MaxY = max_y },
            }
        end
    end
    for ci = poly_n + 1, #polys do polys[ci] = nil end
    if poly_n == 0 then return end

    if show_fill then
        for pi = 1, poly_n do
            local verts = polys[pi].Vertices
            local vn    = #verts
            if vn >= 3 then
                local p1 = verts[1]
                for i = 2, vn - 2 do
                    DI_FTri(p1, verts[i], verts[i + 1], fill_color, fill_opacity)
                end
            end
        end
    end

    local blockers = _hl_blocking_polys
    local cuts     = _hl_intersection_cuts

    for pi = 1, poly_n do
        local cpoly   = polys[pi]
        local cverts  = cpoly.Vertices
        local cbbox   = cpoly.BBox
        local vc_n    = #cverts

        local block_n = 0
        for oi = 1, poly_n do
            if oi ~= pi then
                local ob = polys[oi].BBox
                if not (cbbox.MinX > ob.MaxX or cbbox.MaxX < ob.MinX or
                        cbbox.MinY > ob.MaxY or cbbox.MaxY < ob.MinY) then
                    block_n += 1; blockers[block_n] = polys[oi]
                end
            end
        end

        for vi = 1, vc_n - 1 do
            local vs = cverts[vi]
            local ve = cverts[vi + 1]

            if _hl_is_outer_edge(vs, ve, pi, polys) then
                local ax, ay = vs.X, vs.Y
                local bx, by = ve.X, ve.Y
                local emin_x = math_min(ax, bx)
                local emax_x = math_max(ax, bx)
                local emin_y = math_min(ay, by)
                local emax_y = math_max(ay, by)

                local cut_n = 2
                cuts[1] = 0; cuts[2] = 1
                for ci = 3, #cuts do cuts[ci] = nil end

                for bi = 1, block_n do
                    local blk  = blockers[bi]
                    local bb   = blk.BBox
                    if not (emin_x > bb.MaxX or emax_x < bb.MinX or
                            emin_y > bb.MaxY or emax_y < bb.MinY) then
                        local bv   = blk.Vertices
                        local bv_n = #bv
                        for bvi = 1, bv_n - 1 do
                            local t = _hl_seg_intersect(
                                ax, ay, bx, by,
                                bv[bvi].X, bv[bvi].Y, bv[bvi + 1].X, bv[bvi + 1].Y
                            )
                            if t ~= nil then cut_n += 1; cuts[cut_n] = t end
                        end
                    end
                end

                table.sort(cuts)

                local prev_cut = cuts[1]
                for ci = 2, cut_n do
                    local curr_cut = cuts[ci]
                    if curr_cut > prev_cut + 0.001 then
                        local mid_t = (prev_cut + curr_cut) * 0.5
                        local mid_x = ax + (bx - ax) * mid_t
                        local mid_y = ay + (by - ay) * mid_t
                        local occ   = false
                        for bi = 1, block_n do
                            if _hl_point_in_poly(mid_x, mid_y, blockers[bi].Vertices, blockers[bi].BBox) then
                                occ = true; break
                            end
                        end
                        if not occ then
                            seg_n += 1
                            segs[seg_n * 2 - 1] = vec2_new(ax + (bx - ax) * prev_cut, ay + (by - ay) * prev_cut)
                            segs[seg_n * 2]     = vec2_new(ax + (bx - ax) * curr_cut, ay + (by - ay) * curr_cut)
                        end
                    end
                    prev_cut = curr_cut
                end
            end
        end
    end

    for i = 1, seg_n do
        local ss     = segs[i * 2 - 1]
        local se     = segs[i * 2]
        local nx, ny = _hl_normal(ss, se)

        if show_outline then
            DI_Line(
                vec2_new(ss.X + nx * outline_thick, ss.Y + ny * outline_thick),
                vec2_new(se.X + nx * outline_thick, se.Y + ny * outline_thick),
                outline_color, 1, 1, outline_thick
            )
        end
        if show_inline then
            DI_Line(
                vec2_new(ss.X - nx * inline_thick, ss.Y - ny * inline_thick),
                vec2_new(se.X - nx * inline_thick, se.Y - ny * inline_thick),
                inline_color, 1, 1, inline_thick
            )
        end
        DI_Line(ss, se, color, 1, 1, main_thick)
    end
end

@native
local function on_render(): ()
    local cam = Workspace.CurrentCamera
    for _, entry in static_entries do
        local vis = entry.visible

        if vis ~= entry.prev_vis then
            entry.prev_vis = vis
            if entry.box        ~= nil then entry.box.Visible        = vis end
            if entry.label      ~= nil then entry.label.Visible      = vis end
            if entry.dist_label ~= nil then entry.dist_label.Visible = vis end
        end

        if vis and entry.pos_dirty then
            entry.pos_dirty = false
            if entry.box ~= nil then
                entry.box.Position = entry.prep_box_pos
                entry.box.Size     = entry.prep_box_size
            end
            if entry.label      ~= nil then entry.label.Position      = entry.prep_label_pos end
            if entry.dist_label ~= nil then entry.dist_label.Position = entry.prep_dist_pos end
        end

        if vis and entry.text_dirty and entry.dist_label ~= nil then
            entry.text_dirty      = false
            entry.dist_label.Text = entry.dist_str
        end

        if vis and entry.config.Highlight and cam ~= nil then
            hl_render(entry.inst, entry.config, cam)
        end
    end

    for _, entry in immediate_entries do
        if entry.visible then
            local cfg = entry.config
            if cfg.Box      then DI_Rect (entry.prep_box_pos, entry.prep_box_size, cfg.BoxColor, 1, 1) end
            if cfg.Name     then DI_OText(entry.prep_label_pos, cfg.FontSize, cfg.TextColor, 1, entry.display, true) end
            if cfg.Distance then DI_OText(entry.prep_dist_pos,  cfg.FontSize, cfg.TextColor, 1, entry.dist_str, true) end
        end

        if entry.visible and entry.config.Highlight and cam ~= nil then
            hl_render(entry.inst, entry.config, cam)
        end
    end
end

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

        cfg_inc_active[config]      = _list_active(config.IncludeOnly)
        cfg_exc_active[config]      = _list_active(config.ExcludeObject)
        cfg_inc_attr_active[config] = _attr_map_active(config.IncludeAttributes)
        cfg_exc_attr_active[config] = _attr_map_active(config.ExcludeAttributes)
    end

    scan()

    RunService.PreModel:Connect(function(): () scan() end)
    RunService.PreLocal:Connect(on_pre_local)
    RunService.PostLocal:Connect(on_post_local)
    RunService.Render:Connect(on_render)
end

return init

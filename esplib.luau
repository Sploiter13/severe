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
    Outline             : boolean?,
    FillTransp         : number?,
    FillColor          : Color3?,
    OutlineColor       : Color3?,
    OutlineThickness   : number?,
    HighlightStagger   : number?,
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
    prep_box_pos    : Vector2,
    prep_box_size   : Vector2,
    prep_label_pos  : Vector2,
    prep_dist_pos   : Vector2,
    hl_parts        : { HighlightPart },
    hl_hull_pts     : { Vector2 },
    hl_hull_n       : number,
    hl_visible      : boolean,
    hl_activated    : boolean,
    hl_fill_color   : Color3,
    hl_outline_color: Color3,
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
    prep_box_pos    : Vector2,
    prep_box_size   : Vector2,
    prep_label_pos  : Vector2,
    prep_dist_pos   : Vector2,
    hl_parts        : { HighlightPart },
    hl_hull_pts     : { Vector2 },
    hl_hull_n       : number,
    hl_visible      : boolean,
    hl_activated    : boolean,
    hl_fill_color   : Color3,
    hl_outline_color: Color3,
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

local RunService  = game:GetService("RunService")
local Players     = game:GetService("Players")
local Workspace   = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local INF     = math.huge
local WEAK_MT = table.freeze({ __mode = "k" })

local BOX_SIZE      = UDim2.fromScale(1, 1)
local LABEL_SIZE    = UDim2.fromScale(1, 1)
local ANCHOR_CENTER = Vector2.new(0.5, 0.5)
local ANCHOR_TOP    = Vector2.new(0.5, 1)
local ANCHOR_BOTTOM = Vector2.new(0.5, 0)

local PLACEHOLDER_VEC2 = Vector2.new(0, 0)
local SENTINEL_POS     = vector.create(math.huge, 0, 0)
local SENTINEL_SIZE    = vector.create(-1, -1, -1)

local v_mag      = vector.magnitude
local v_min      = vector.min
local v_max      = vector.max
local v_zero     = vector.zero
local math_min   = math.min
local math_max   = math.max
local math_round = math.round
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
local known             : { [BasePart]: true? }       = setmetatable({}, WEAK_MT) :: any
local known_children    : { [Instance]: true? }       = setmetatable({}, WEAK_MT) :: any
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

local cfg_inc_active      : { [ConfigEntry]: boolean } = {}
local cfg_exc_active      : { [ConfigEntry]: boolean } = {}
local cfg_inc_attr_active : { [ConfigEntry]: boolean } = {}
local cfg_exc_attr_active : { [ConfigEntry]: boolean } = {}

local cfg_next_act_time : { [ConfigEntry]: number? } = {}
local stagger_buf       : { any }                    = t_create(64)

local scratch_proj_pts : { Vector2 } = t_create(64)

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

local function build_hl_parts(parts: { BasePart }): { HighlightPart }
    local out: { HighlightPart } = t_create(#parts)
    for i, p in parts do
        out[i] = {
            part      = p,
            hx        = 0,
            hy        = 0,
            hz        = 0,
            last_pos  = SENTINEL_POS,
            last_look = v_zero,
            last_up   = v_zero,
            last_size = SENTINEL_SIZE,
            wc1 = v_zero, wc2 = v_zero, wc3 = v_zero, wc4 = v_zero,
            wc5 = v_zero, wc6 = v_zero, wc7 = v_zero, wc8 = v_zero,
        }
    end
    return out
end

local function compute_convex_hull(
    pts: { Vector2 }, n: number,
    out: { Vector2 }
): number
    local ti = n + 1
    while pts[ti] ~= nil do
        pts[ti] = nil
        ti += 1
    end

    if n < 3 then
        for j = 1, n do out[j] = pts[j] end
        local oi = n + 1
        while out[oi] ~= nil do out[oi] = nil; oi += 1 end
        return n
    end

    t_sort(pts, function(a: Vector2, b: Vector2): boolean
        if a.X == b.X then return a.Y < b.Y end
        return a.X < b.X
    end)

    local k = 0

    for j = 1, n do
        local p = pts[j]
        local px, py = p.X, p.Y
        while k >= 2 do
            local a = out[k - 1]
            local b = out[k]
            if (b.X - a.X) * (py - a.Y) - (b.Y - a.Y) * (px - a.X) > 0 then break end
            out[k] = nil
            k -= 1
        end
        k += 1
        out[k] = p
    end

    local lower_t = k + 1
    for j = n - 1, 1, -1 do
        local p = pts[j]
        local px, py = p.X, p.Y
        while k >= lower_t do
            local a = out[k - 1]
            local b = out[k]
            if (b.X - a.X) * (py - a.Y) - (b.Y - a.Y) * (px - a.X) > 0 then break end
            out[k] = nil
            k -= 1
        end
        k += 1
        out[k] = p
    end

    out[k] = nil
    k -= 1

    local oi = k + 1
    while out[oi] ~= nil do out[oi] = nil; oi += 1 end

    return k
end

@native
local function compute_highlight(entry: any, cam: any): ()
    local cfg = entry.config
    if not (cfg.Fill or cfg.Outline) then
        entry.hl_visible = false
        return
    end

    local hl_parts = entry.hl_parts
    local n_parts = #hl_parts
    if n_parts == 0 then
        entry.hl_visible = false
        return
    end

    local parts_dirty = false
    for j = 1, n_parts do
        local hp = hl_parts[j]
        local part = hp.part
        local cf = part.CFrame
        local p = cf.Position   :: vector
        local l = cf.LookVector :: vector
        local u = cf.UpVector   :: vector
        local sz = part.Size :: vector

        local changed = false
        if p ~= hp.last_pos or l ~= hp.last_look or u ~= hp.last_up then
            hp.last_pos  = p
            hp.last_look = l
            hp.last_up   = u
            changed = true
        end
        if sz ~= hp.last_size then
            hp.last_size = sz
            hp.hx = sz.x * 0.5
            hp.hy = sz.y * 0.5
            hp.hz = sz.z * 0.5
            changed = true
        end

        if changed then
            parts_dirty = true
            local r   = (cf.RightVector :: vector) * hp.hx
            local uy  = u * hp.hy
            local lz  = l * hp.hz
            local upz = uy + lz
            local umz = uy - lz
            hp.wc1 = p + r + upz
            hp.wc2 = p - r + upz
            hp.wc3 = p + r - umz
            hp.wc4 = p - r - umz
            hp.wc5 = p + r + umz
            hp.wc6 = p - r + umz
            hp.wc7 = p + r - upz
            hp.wc8 = p - r - upz
        end
    end

    if not cam_dirty and not parts_dirty then
        return
    end

    local vp_min_x = -100
    local vp_max_x = cam_vp_x + 100
    local vp_min_y = -100
    local vp_max_y = cam_vp_y + 100

    local pts = scratch_proj_pts
    local n = 0

    for j = 1, n_parts do
        local hp = hl_parts[j]
        local s: any, vis: boolean
        local sxv: number, syv: number

        s, vis = cam:WorldToScreenPoint(hp.wc1)
        if vis then sxv, syv = s.X, s.Y
            if sxv > vp_min_x and sxv < vp_max_x and syv > vp_min_y and syv < vp_max_y then
                n += 1; pts[n] = vec2_new(sxv, syv)
            end
        end
        s, vis = cam:WorldToScreenPoint(hp.wc2)
        if vis then sxv, syv = s.X, s.Y
            if sxv > vp_min_x and sxv < vp_max_x and syv > vp_min_y and syv < vp_max_y then
                n += 1; pts[n] = vec2_new(sxv, syv)
            end
        end
        s, vis = cam:WorldToScreenPoint(hp.wc3)
        if vis then sxv, syv = s.X, s.Y
            if sxv > vp_min_x and sxv < vp_max_x and syv > vp_min_y and syv < vp_max_y then
                n += 1; pts[n] = vec2_new(sxv, syv)
            end
        end
        s, vis = cam:WorldToScreenPoint(hp.wc4)
        if vis then sxv, syv = s.X, s.Y
            if sxv > vp_min_x and sxv < vp_max_x and syv > vp_min_y and syv < vp_max_y then
                n += 1; pts[n] = vec2_new(sxv, syv)
            end
        end
        s, vis = cam:WorldToScreenPoint(hp.wc5)
        if vis then sxv, syv = s.X, s.Y
            if sxv > vp_min_x and sxv < vp_max_x and syv > vp_min_y and syv < vp_max_y then
                n += 1; pts[n] = vec2_new(sxv, syv)
            end
        end
        s, vis = cam:WorldToScreenPoint(hp.wc6)
        if vis then sxv, syv = s.X, s.Y
            if sxv > vp_min_x and sxv < vp_max_x and syv > vp_min_y and syv < vp_max_y then
                n += 1; pts[n] = vec2_new(sxv, syv)
            end
        end
        s, vis = cam:WorldToScreenPoint(hp.wc7)
        if vis then sxv, syv = s.X, s.Y
            if sxv > vp_min_x and sxv < vp_max_x and syv > vp_min_y and syv < vp_max_y then
                n += 1; pts[n] = vec2_new(sxv, syv)
            end
        end
        s, vis = cam:WorldToScreenPoint(hp.wc8)
        if vis then sxv, syv = s.X, s.Y
            if sxv > vp_min_x and sxv < vp_max_x and syv > vp_min_y and syv < vp_max_y then
                n += 1; pts[n] = vec2_new(sxv, syv)
            end
        end
    end

    if n < 3 then
        entry.hl_visible = false
        entry.hl_hull_n  = 0
        return
    end

    local k = compute_convex_hull(pts, n, entry.hl_hull_pts)
    if k < 3 then
        entry.hl_visible = false
        entry.hl_hull_n  = 0
        return
    end

    entry.hl_hull_n  = k
    entry.hl_visible = true
end

local function _unstaggered(cfg: ConfigEntry): boolean
    local s = cfg.HighlightStagger
    return s == nil or s <= 0
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

    local hl_parts: { HighlightPart } = {}
    local hl_hull_pts: { Vector2 }    = {}
    local hl_fill_color: Color3       = config.FillColor    or config.BoxColor
    local hl_outline_color: Color3    = config.OutlineColor or config.BoxColor

    if config.Highlight then
        hl_parts = build_hl_parts(parts)
        hl_hull_pts = t_create(#hl_parts * 8 + 1)
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
        prep_box_pos    = PLACEHOLDER_VEC2,
        prep_box_size   = PLACEHOLDER_VEC2,
        prep_label_pos  = PLACEHOLDER_VEC2,
        prep_dist_pos   = PLACEHOLDER_VEC2,
        hl_parts        = hl_parts,
        hl_hull_pts     = hl_hull_pts,
        hl_hull_n       = 0,
        hl_visible      = false,
        hl_activated    = _unstaggered(config),
        hl_fill_color   = hl_fill_color,
        hl_outline_color= hl_outline_color,
    }
end

local function make_immediate_entry(inst: Instance, part: BasePart, parts: { BasePart }, config: ConfigEntry, display: string): ()
    local box_offset, box_half = compute_bbox(parts, part.Position :: vector)

    local hl_parts: { HighlightPart } = {}
    local hl_hull_pts: { Vector2 }    = {}
    local hl_fill_color: Color3       = config.FillColor    or config.BoxColor
    local hl_outline_color: Color3    = config.OutlineColor or config.BoxColor

    if config.Highlight then
        hl_parts = build_hl_parts(parts)
        hl_hull_pts = t_create(#hl_parts * 8 + 1)
    end

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
        prep_box_pos    = PLACEHOLDER_VEC2,
        prep_box_size   = PLACEHOLDER_VEC2,
        prep_label_pos  = PLACEHOLDER_VEC2,
        prep_dist_pos   = PLACEHOLDER_VEC2,
        hl_parts        = hl_parts,
        hl_hull_pts     = hl_hull_pts,
        hl_hull_n       = 0,
        hl_visible      = false,
        hl_activated    = _unstaggered(config),
        hl_fill_color   = hl_fill_color,
        hl_outline_color= hl_outline_color,
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
    if not (config.Box or config.Name or config.Distance or config.Highlight) then return end

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
        local e = static_entries[i]
        if e.part.Parent == nil or e.inst.Parent == nil then
            remove_static_entry(i)
        else
            i += 1
        end
    end

    i = 1
    while i <= #immediate_entries do
        local e = immediate_entries[i]
        if e.part.Parent == nil or e.inst.Parent == nil then
            remove_immediate_entry(i)
        else
            i += 1
        end
    end

    i = 1
    while i <= #dynamic_entries do
        local e = dynamic_entries[i]
        if e.part.Parent == nil or e.inst.Parent == nil then
            remove_dynamic_entry(i)
        else
            i += 1
        end
    end

    for _, config in CONFIGS do
        if not config.Enabled then continue end

        if config.Folder ~= nil and config.Folder.Parent ~= nil then
            for _, child in config.Folder:GetChildren() do
                if known_children[child] ~= nil then continue end
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
            entry.hl_visible = false
            continue
        end

        local pos  = entry.part.Position :: vector
        local dist = v_mag(pos - lpos)
        entry.distance = dist

        if dist > cfg.MaxDistance then
            entry.visible = false
            entry.hl_visible = false
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
            entry.hl_visible = false
            continue
        end

        local pos  = entry.part.Position :: vector
        local dist = v_mag(pos - lpos)
        entry.distance = dist

        if dist > cfg.MaxDistance then
            entry.visible = false
            entry.hl_visible = false
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
            if entry.box        ~= nil then entry.box.Visible        = vis end
            if entry.label      ~= nil then entry.label.Visible      = vis end
            if entry.dist_label ~= nil then entry.dist_label.Visible = vis end
        end

        entry.visible = vis
    end
end

local function _process_stagger(now: number): ()
    for _, cfg in CONFIGS do
        if not cfg.Highlight then continue end
        local stagger = cfg.HighlightStagger
        if stagger == nil or stagger <= 0 then continue end

        local cand_n = 0
        for i = 1, pending_static_n do
            local e = pending_static[i]
            if e.config == cfg and not e.hl_activated then
                cand_n += 1
                stagger_buf[cand_n] = e
            end
        end
        for i = 1, pending_immediate_n do
            local e = pending_immediate[i]
            if e.config == cfg and not e.hl_activated then
                cand_n += 1
                stagger_buf[cand_n] = e
            end
        end

        if cand_n == 0 then continue end

        local ti = cand_n + 1
        while stagger_buf[ti] ~= nil do stagger_buf[ti] = nil; ti += 1 end

        if cand_n > 1 then
            t_sort(stagger_buf, function(a: any, b: any): boolean
                return a.distance < b.distance
            end)
        end

        local next_t = cfg_next_act_time[cfg] or 0
        if now >= next_t then
            stagger_buf[1].hl_activated = true
            cfg_next_act_time[cfg] = now + stagger
        end

        for i = 1, cand_n do stagger_buf[i] = nil end
    end
end

@native
local function on_post_local(): ()
    local cam = Workspace.CurrentCamera
    if cam == nil then return end

    local now = os_clock()
    _process_stagger(now)

    for i = 1, pending_static_n do
        local entry = pending_static[i]
        local cfg   = entry.config

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

        if cfg.Highlight and entry.hl_activated then
            compute_highlight(entry, cam)
        end
    end

    for i = 1, pending_immediate_n do
        local entry = pending_immediate[i]
        local cfg   = entry.config

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

        if cfg.Highlight and entry.hl_activated then
            compute_highlight(entry, cam)
        end
    end
end

@native
local function on_render(): ()
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

        if entry.hl_visible then
            local cfg = entry.config
            local pts = entry.hl_hull_pts
            local k   = entry.hl_hull_n

            if cfg.Fill and k >= 3 then
                local fc = entry.hl_fill_color
                local op = cfg.FillTransp or 1
                local p1 = pts[1]
                for ti = 2, k - 1 do
                    DI_FTri(p1, pts[ti], pts[ti + 1], fc, op)
                end
            end

            if cfg.Outline and k >= 2 then
                local oc = entry.hl_outline_color
                local ot = cfg.OutlineThickness or 1
                for ei = 1, k - 1 do
                    DI_Line(pts[ei], pts[ei + 1], oc, 1, 1, ot)
                end
                DI_Line(pts[k], pts[1], oc, 1, 1, ot)
            end
        end
    end

    for _, entry in immediate_entries do
        if entry.visible then
            local cfg = entry.config
            if cfg.Box      then DI_Rect (entry.prep_box_pos, entry.prep_box_size, cfg.BoxColor, 1, 1) end
            if cfg.Name     then DI_OText(entry.prep_label_pos, cfg.FontSize, cfg.TextColor, 1, entry.display, true) end
            if cfg.Distance then DI_OText(entry.prep_dist_pos,  cfg.FontSize, cfg.TextColor, 1, entry.dist_str, true) end
        end

        if entry.hl_visible then
            local cfg = entry.config
            local pts = entry.hl_hull_pts
            local k   = entry.hl_hull_n

            if cfg.Fill and k >= 3 then
                local fc = entry.hl_fill_color
                local op = cfg.FillTransp or 1
                local p1 = pts[1]
                for ti = 2, k - 1 do
                    DI_FTri(p1, pts[ti], pts[ti + 1], fc, op)
                end
            end

            if cfg.Outline and k >= 2 then
                local oc = entry.hl_outline_color
                local ot = cfg.OutlineThickness or 1
                for ei = 1, k - 1 do
                    DI_Line(pts[ei], pts[ei + 1], oc, 1, 1, ot)
                end
                DI_Line(pts[k], pts[1], oc, 1, 1, ot)
            end
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

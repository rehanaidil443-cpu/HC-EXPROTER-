--[[
    HC EXPORT v2.1   (v2.0 + efek gelombang putih-hitam)
    • Lihat isi Workspace sebagai kartu (Folder / Model), masuk ke dalam folder, filter, cari
    • Format : RBXM (item terpilih) | RBXL (place: Workspace + service) | JSON (data Part)
    • Nama file : manual, atau OTOMATIS dari nama item / nama game (tanpa menimpa file lama)
    • Simpan  : Workspace executor (+ coba salin ke Download)
    • Panel   : 2 warna (Cyan / Violet), gambar rbxassetid://119468948794894, efek klik ripple + glow
    • Efek gelombang PUTIH-HITAM (1 warna) di border panel, logo, tombol melayang, kartu export, toast
    Struktur kode:  1 Config  2 Util  3 Tema  4 GUI  5 UI-kit  6 Header  7 Browser  8 Panel export
                    9 Serializer  10 Saver + Download  11 Generate  12 Start
]]

if not game:IsLoaded() then game.Loaded:Wait() end

---------------------------------------------------------------------
-- 1. CONFIG
---------------------------------------------------------------------
local IMG = "rbxassetid://119468948794894"
local VERSION = "v2.1"
local EXPORT_ROOT_NAME = "Export"

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local UIS               = game:GetService("UserInputService")
local CoreGui           = game:GetService("CoreGui")
local HttpService       = game:GetService("HttpService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LP = Players.LocalPlayer
while not LP do task.wait(0.1) LP = Players.LocalPlayer end

if _G.HCExportCleanup then pcall(_G.HCExportCleanup) end

local prefs = _G.HCExportPrefs or {}
_G.HCExportPrefs = prefs

local THEMES = {
    {name = "Cyan",   acc = Color3.fromRGB(0, 229, 255),   bg = Color3.fromRGB(12, 20, 30), ink = Color3.fromRGB(4, 24, 30)},
    {name = "Violet", acc = Color3.fromRGB(176, 106, 255), bg = Color3.fromRGB(22, 14, 34), ink = Color3.fromRGB(24, 8, 36)},
}
local theme = THEMES[prefs.theme or 1] or THEMES[1]

local DL_DIRS = {
    "../../Download",
    "/storage/emulated/0/Download",
    "/sdcard/Download",
    "/storage/self/primary/Download",
}

---------------------------------------------------------------------
-- 2. UTIL
---------------------------------------------------------------------
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local GREY = Color3.fromRGB(165, 175, 188)

local function guiParent()
    if gethui then
        local ok, r = pcall(gethui)
        if ok and r then return r end
    end
    if pcall(function() return CoreGui.Name end) then return CoreGui end
    return LP:WaitForChild("PlayerGui")
end

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end

local function tw(o, t, props, style, dir)
    local tween = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
    tween:Play()
    return tween
end

local function corner(o, r) return new("UICorner", {CornerRadius = UDim.new(0, r)}, o) end

local function stroke(o, tr, th, col)
    return new("UIStroke", {
        Color = col or WHITE, Transparency = tr or 0.8, Thickness = th or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, o)
end

-- Efek gelombang: UIStroke + UIGradient hitam-putih yang berputar dan bergeser (1 warna, tidak ikut tema)
local waves = {}
local function waveStroke(parent, thickness, speed)
    local s = new("UIStroke", {
        Color = WHITE, Thickness = thickness or 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, parent)
    local d = Color3.fromRGB(14, 14, 14)
    local g = new("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, d), ColorSequenceKeypoint.new(0.25, WHITE),
            ColorSequenceKeypoint.new(0.5, d), ColorSequenceKeypoint.new(0.75, WHITE),
            ColorSequenceKeypoint.new(1, d),
        }),
    }, s)
    waves[#waves + 1] = {g = g, sp = speed or 70, ph = math.random() * 6}
    return s
end

local function sanitize(s)
    s = tostring(s or ""):gsub('[\\/:*?"<>|%c]', "_")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s:sub(1, 100)
end

local function copyText(t)
    local fn = setclipboard or toclipboard
    if fn then pcall(fn, tostring(t)) end
end

-- potong pekerjaan berat per frame supaya tidak lag
local SLICE, lastYield = 0.005, os.clock()
local function slice()
    if os.clock() - lastYield > SLICE then
        task.wait()
        lastYield = os.clock()
    end
end

local function playerCharacter(inst)
    if not inst:IsA("Model") then return false end
    local ok, pl = pcall(function() return Players:GetPlayerFromCharacter(inst) end)
    return ok and pl ~= nil
end

---------------------------------------------------------------------
-- 3. TEMA (2 warna panel)
---------------------------------------------------------------------
local bound = {}   -- {obj, prop, key}
local function bind(obj, prop, key)
    bound[#bound + 1] = {obj, prop, key}
    obj[prop] = theme[key]
end

local toggleReg = {}   -- [button] = getter() -> boolean
local dots = {}
local applyTheme

---------------------------------------------------------------------
-- 4. GUI DASAR
---------------------------------------------------------------------
local gui = new("ScreenGui", {
    Name = "ExportPanel", ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = 999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, guiParent())

local conns = {}
_G.HCExportCleanup = function()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    pcall(function() gui:Destroy() end)
end

table.insert(conns, RunService.Heartbeat:Connect(function(dt)
    local t = os.clock()
    for i = #waves, 1, -1 do
        local w = waves[i]
        if w.g.Parent then
            w.g.Rotation = (w.g.Rotation + dt * w.sp) % 360
            w.g.Offset = Vector2.new(math.sin(t * 1.6 + w.ph) * 0.3, math.cos(t * 1.3 + w.ph) * 0.3)
        else
            table.remove(waves, i)
        end
    end
end))

local Root = new("Frame", {
    Size = UDim2.fromOffset(500, 446), Position = UDim2.fromScale(0.5, 0.5),
    AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Visible = false,
}, gui)
local fit = new("UIScale", {}, Root)
local function updateFit()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local v = cam.ViewportSize
    fit.Scale = math.min(v.X / 540, v.Y / 480, 1)
end
updateFit()
if workspace.CurrentCamera then
    table.insert(conns, workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateFit))
end

local Main = new("Frame", {
    Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundTransparency = 0.1, BorderSizePixel = 0, ClipsDescendants = true, Active = true,
}, Root)
bind(Main, "BackgroundColor3", "bg")
corner(Main, 20)
waveStroke(Main, 2.6, 55)
local anim = new("UIScale", {Scale = 0.9}, Main)

-- kilau kaca di atas + gambar sebagai watermark di dalam panel
local sheen = new("Frame", {
    Size = UDim2.new(1, 0, 0, 110), BackgroundColor3 = WHITE, BackgroundTransparency = 0.95,
    BorderSizePixel = 0, ZIndex = 1,
}, Main)
new("UIGradient", {
    Rotation = 90,
    Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1)}),
}, sheen)
new("ImageLabel", {
    Image = IMG, BackgroundTransparency = 1, ImageTransparency = 0.9, ScaleType = Enum.ScaleType.Fit,
    AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -150), Size = UDim2.fromOffset(150, 150), ZIndex = 1,
}, Main)

local isOpen = false
local function setOpen(v)
    isOpen = v
    if v then
        Root.Visible = true
        anim.Scale = 0.9
        tw(anim, 0.38, {Scale = 1}, Enum.EasingStyle.Back)
    else
        tw(anim, 0.18, {Scale = 0.9})
        task.delay(0.2, function()
            if not isOpen then Root.Visible = false end
        end)
    end
end

---------------------------------------------------------------------
-- 5. UI-KIT
---------------------------------------------------------------------
local function lbl(parent, text, x, y, w, h, size, color, font, align)
    return new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        Text = text, TextSize = size or 11, TextColor3 = color or WHITE, Font = font or Enum.Font.GothamMedium,
        TextXAlignment = align or Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true, ZIndex = 3,
    }, parent)
end

local function glass(parent, x, y, w, h, tr, wave)
    local f = new("Frame", {
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = WHITE,
        BackgroundTransparency = tr or 0.94, BorderSizePixel = 0, ZIndex = 2,
    }, parent)
    corner(f, 14)
    if wave then waveStroke(f, 1.6, 45) else stroke(f, 0.86, 1) end
    return f
end

local function paintToggle(b, on)
    if on then
        b.BackgroundColor3 = theme.acc
        b.BackgroundTransparency = 0.32
    else
        b.BackgroundColor3 = WHITE
        b.BackgroundTransparency = 0.9
    end
    b.TextColor3 = WHITE
end

local function refreshToggles()
    for b, getter in pairs(toggleReg) do
        if b.Parent then
            paintToggle(b, getter())
        else
            toggleReg[b] = nil
        end
    end
end

-- efek klik: ripple + glow stroke + tekan (scale)
local function clickFx(b, st, scale, px, py)
    tw(scale, 0.07, {Scale = 0.94})
    task.delay(0.07, function() tw(scale, 0.28, {Scale = 1}, Enum.EasingStyle.Back) end)
    tw(st, 0.08, {Transparency = 0.05, Thickness = 2.4, Color = theme.acc})
    task.delay(0.09, function() tw(st, 0.35, {Transparency = 0.8, Thickness = 1, Color = WHITE}) end)
    if px and b.Parent then
        local abs, size = b.AbsolutePosition, b.AbsoluteSize
        local k = size.X / math.max(b.Size.X.Offset, 1)
        local d = math.max(size.X, size.Y) / math.max(k, 0.01) * 2.4
        local r = new("Frame", {
            BackgroundColor3 = WHITE, BackgroundTransparency = 0.55, BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(0, 0),
            Position = UDim2.fromOffset((px - abs.X) / math.max(k, 0.01), (py - abs.Y) / math.max(k, 0.01)),
            ZIndex = b.ZIndex + 1,
        }, b)
        corner(r, 999)
        tw(r, 0.55, {Size = UDim2.fromOffset(d, d), BackgroundTransparency = 1})
        task.delay(0.6, function() r:Destroy() end)
    end
end

-- o = {text,x,y,w,h,size,cb,primary,toggle,radius}
local function makeButton(parent, o)
    local b = new("TextButton", {
        Position = UDim2.fromOffset(o.x, o.y), Size = UDim2.fromOffset(o.w, o.h), BackgroundColor3 = WHITE,
        BackgroundTransparency = 0.9, BorderSizePixel = 0, AutoButtonColor = false, Text = o.text or "",
        Font = Enum.Font.GothamBold, TextSize = o.size or 10, TextColor3 = WHITE,
        ClipsDescendants = true, ZIndex = o.z or 3,
    }, parent)
    corner(b, o.radius or 10)
    local st = stroke(b, 0.8, 1)
    local sc = new("UIScale", {}, b)

    if o.primary then
        bind(b, "BackgroundColor3", "acc")
        b.BackgroundTransparency = 0.08
        bind(b, "TextColor3", "ink")
    elseif o.toggle then
        toggleReg[b] = o.toggle
        paintToggle(b, o.toggle())
    end

    b.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            clickFx(b, st, sc, i.Position.X, i.Position.Y)
        elseif i.UserInputType == Enum.UserInputType.MouseMovement and not o.primary then
            tw(st, 0.12, {Transparency = 0.5})
        end
    end)
    b.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseMovement then tw(st, 0.15, {Transparency = 0.8}) end
    end)
    if o.cb then b.Activated:Connect(o.cb) end
    return b
end

local function makeField(parent, x, y, w, h, ph)
    local t = new("TextBox", {
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = WHITE,
        BackgroundTransparency = 0.9, BorderSizePixel = 0, Text = "", PlaceholderText = ph or "",
        PlaceholderColor3 = Color3.fromRGB(130, 140, 152), TextColor3 = WHITE, Font = Enum.Font.GothamMedium,
        TextSize = 10, ClearTextOnFocus = false, ZIndex = 3, TextXAlignment = Enum.TextXAlignment.Left,
    }, parent)
    corner(t, 10)
    new("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, t)
    local s = stroke(t, 0.82, 1)
    t.Focused:Connect(function() tw(s, 0.15, {Transparency = 0.1, Color = theme.acc}) end)
    t.FocusLost:Connect(function() tw(s, 0.2, {Transparency = 0.82, Color = WHITE}) end)
    return t
end

-- toast kecil (pojok kanan bawah)
local function toast(title, msg, bad)
    local t = new("Frame", {
        Size = UDim2.fromOffset(300, 62), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 340, 1, -18),
        BackgroundColor3 = theme.bg, BackgroundTransparency = 0.08, BorderSizePixel = 0, ZIndex = 50,
    }, gui)
    corner(t, 14)
    if bad then stroke(t, 0.2, 1.6, Color3.fromRGB(255, 110, 110)) else waveStroke(t, 1.8, 90) end
    new("ImageLabel", {
        Image = IMG, BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 11), Size = UDim2.fromOffset(40, 40),
        ScaleType = Enum.ScaleType.Fit, ZIndex = 51,
    }, t)
    new("TextLabel", {
        Position = UDim2.fromOffset(60, 8), Size = UDim2.new(1, -70, 0, 16), BackgroundTransparency = 1, Text = title,
        Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 51,
    }, t)
    new("TextLabel", {
        Position = UDim2.fromOffset(60, 26), Size = UDim2.new(1, -70, 0, 30), BackgroundTransparency = 1, Text = msg,
        Font = Enum.Font.Gotham, TextSize = 9, TextColor3 = Color3.fromRGB(190, 200, 212), TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 51,
    }, t)
    tw(t, 0.45, {Position = UDim2.new(1, -16, 1, -18)}, Enum.EasingStyle.Back)
    task.delay(4, function()
        if t.Parent then
            tw(t, 0.3, {Position = UDim2.new(1, 340, 1, -18)}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            task.wait(0.35)
            t:Destroy()
        end
    end)
end

---------------------------------------------------------------------
-- 6. HEADER (logo gambar, judul, tema, kunci, minimize, close, drag)
---------------------------------------------------------------------
local header = new("Frame", {Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1, ZIndex = 2}, Main)

local logo = new("ImageLabel", {
    Image = IMG, BackgroundColor3 = BLACK, BackgroundTransparency = 0.3, Position = UDim2.fromOffset(14, 7),
    Size = UDim2.fromOffset(34, 34), ScaleType = Enum.ScaleType.Crop, ZIndex = 3,
}, header)
corner(logo, 10)
waveStroke(logo, 1.8, 110)

lbl(header, "HC EXPORT", 58, 6, 200, 18, 14, WHITE, Enum.Font.GothamBlack)
local subL = lbl(header, VERSION .. "   Workspace  >  RBXM / RBXL / JSON", 58, 26, 260, 12, 8, GREY, Enum.Font.GothamBold)
subL.TextWrapped = false

local locked = false
local lockBtn = makeButton(header, {text = "LOCK", x = 376, y = 10, w = 44, h = 28, size = 8, z = 5, toggle = function() return locked end,
    cb = function()
        locked = not locked
        refreshToggles()
        toast(locked and "Panel dikunci" or "Panel dibuka", locked and "Panel tidak bisa digeser." or "Panel bisa digeser lagi.", false)
    end})
makeButton(header, {text = "-", x = 424, y = 10, w = 30, h = 28, size = 15, z = 5, cb = function() setOpen(false) end})
makeButton(header, {text = "X", x = 458, y = 10, w = 30, h = 28, size = 11, z = 5, cb = function()
    setOpen(false)
    task.wait(0.25)
    _G.HCExportCleanup()
end})

-- dua pilihan warna panel
for i, t in ipairs(THEMES) do
    local d = new("TextButton", {
        Position = UDim2.fromOffset(326 + (i - 1) * 24, 15), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = t.acc,
        Text = "", AutoButtonColor = false, BorderSizePixel = 0, ZIndex = 5,
    }, header)
    corner(d, 9)
    local ds = stroke(d, 0.6, 1)
    dots[i] = ds
    d.Activated:Connect(function()
        tw(d, 0.08, {Size = UDim2.fromOffset(14, 14), Position = d.Position + UDim2.fromOffset(2, 2)})
        task.delay(0.08, function()
            tw(d, 0.25, {Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(326 + (i - 1) * 24, 15)}, Enum.EasingStyle.Back)
        end)
        applyTheme(i)
    end)
end

do
    local dragging, startPos, startUI
    header.InputBegan:Connect(function(i)
        if locked then return end
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, startPos, startUI = true, i.Position, Root.Position
        end
    end)
    table.insert(conns, UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startPos
            Root.Position = UDim2.new(startUI.X.Scale, startUI.X.Offset + d.X, startUI.Y.Scale, startUI.Y.Offset + d.Y)
        end
    end))
    table.insert(conns, UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

---------------------------------------------------------------------
-- STATE EXPORT
---------------------------------------------------------------------
local ex = {
    cur = workspace, filter = "ALL", query = "", sel = {}, count = 0, cards = {}, tok = 0, qtok = 0,
    format = prefs.format or "RBXM", merge = prefs.merge == true, scripts = prefs.scripts ~= false,
    method = prefs.method or "HC", dest = prefs.dest or "DOWNLOAD",
    busy = false, autoName = nil,
}

local populate
local statusL

local function status(t, bad)
    statusL.Text = t
    statusL.TextColor3 = bad and Color3.fromRGB(255, 130, 130) or Color3.fromRGB(205, 215, 226)
end

---------------------------------------------------------------------
-- 7. BROWSER (breadcrumb, filter, cari, kartu)
---------------------------------------------------------------------
local crumb = lbl(Main, "Workspace", 16, 56, 290, 26, 10, GREY, Enum.Font.GothamMedium)
crumb.TextWrapped = false
crumb.TextYAlignment = Enum.TextYAlignment.Center
local backBtn = makeButton(Main, {text = "BACK", x = 312, y = 54, w = 80, h = 28, size = 9, cb = function()
    local p = ex.cur and ex.cur.Parent
    if p and ex.cur ~= workspace then
        ex.cur = p
        populate()
    end
end})
makeButton(Main, {text = "REFRESH", x = 398, y = 54, w = 86, h = 28, size = 9, cb = function() populate() end})

-- filter (segmented)
for i, n in ipairs({"ALL", "FOLDER", "MODEL"}) do
    makeButton(Main, {text = n, x = 16 + (i - 1) * 66, y = 88, w = 62, h = 28, size = 9,
        toggle = function() return ex.filter == n end,
        cb = function()
            ex.filter = n
            refreshToggles()
            populate()
        end})
end
local searchField = makeField(Main, 216, 88, 130, 28, "Cari nama...")

local function updateCard(inst)
    local c = ex.cards[inst]
    if not c then return end
    local on = ex.sel[inst] == true
    c.btn.Text = on and "SELECTED" or "SELECT"
    paintToggle(c.btn, on)
    tw(c.stroke, 0.15, {Transparency = on and 0.05 or 0.86, Color = on and theme.acc or WHITE})
    tw(c.frame, 0.15, {BackgroundTransparency = on and 0.86 or 0.94})
end

local function refreshTitle() end   -- diisi di bagian panel export

local function toggleSel(inst)
    if ex.sel[inst] then
        ex.sel[inst] = nil
        ex.count -= 1
    else
        ex.sel[inst] = true
        ex.count += 1
    end
    updateCard(inst)
    refreshTitle()
end

makeButton(Main, {text = "SELECT ALL", x = 352, y = 88, w = 72, h = 28, size = 8, cb = function()
    for inst in pairs(ex.cards) do
        if not ex.sel[inst] then
            ex.sel[inst] = true
            ex.count += 1
            updateCard(inst)
        end
    end
    refreshTitle()
end})
makeButton(Main, {text = "CLEAR", x = 428, y = 88, w = 56, h = 28, size = 8, cb = function()
    for inst in pairs(ex.sel) do ex.sel[inst] = nil end
    ex.count = 0
    for inst in pairs(ex.cards) do updateCard(inst) end
    refreshTitle()
end})

local grid = new("ScrollingFrame", {
    Position = UDim2.fromOffset(16, 124), Size = UDim2.fromOffset(468, 158), BackgroundTransparency = 1,
    BorderSizePixel = 0, ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(), ZIndex = 2,
}, Main)
bind(grid, "ScrollBarImageColor3", "acc")
new("UIGridLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder, CellSize = UDim2.fromOffset(150, 74), CellPadding = UDim2.fromOffset(9, 8),
}, grid)
local emptyL = lbl(Main, "Folder ini kosong / tidak ada hasil.", 16, 190, 468, 30, 11, Color3.fromRGB(125, 135, 148), Enum.Font.GothamMedium, Enum.TextXAlignment.Center)
emptyL.Visible = false

local function badgeFor(inst)
    if inst:IsA("Folder") then return "F" end
    if inst:IsA("Model") then return "M" end
    return inst.ClassName:sub(1, 1)
end

local function addCard(inst, order)
    local isFolder = inst:IsA("Folder")
    local subs = 0
    for _, c in ipairs(inst:GetChildren()) do
        if c:IsA("Folder") or c:IsA("Model") then subs += 1 end
    end
    local total = #inst:GetChildren()

    local f = new("Frame", {
        BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = order, ZIndex = 2,
    }, grid)
    corner(f, 12)
    local st = stroke(f, 0.86, 1)
    tw(f, 0.25, {BackgroundTransparency = 0.94})

    local badge = new("Frame", {
        Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(8, 8), BorderSizePixel = 0, ZIndex = 3,
        BackgroundColor3 = isFolder and theme.acc or WHITE, BackgroundTransparency = isFolder and 0.1 or 0.85,
    }, f)
    corner(badge, 8)
    local badgeTxt = new("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = badgeFor(inst), Font = Enum.Font.GothamBlack,
        TextSize = 12, TextColor3 = isFolder and theme.ink or WHITE, ZIndex = 4,
    }, badge)
    if isFolder then
        bind(badge, "BackgroundColor3", "acc")
        bind(badgeTxt, "TextColor3", "ink")
    end

    local nl = lbl(f, inst.Name, 42, 8, 100, 14, 10, WHITE, Enum.Font.GothamBold)
    nl.TextWrapped = false
    nl.TextTruncate = Enum.TextTruncate.AtEnd
    local cl = lbl(f, inst.ClassName .. "  -  " .. total, 42, 24, 100, 12, 8, GREY, Enum.Font.Gotham)
    cl.TextWrapped = false
    cl.TextTruncate = Enum.TextTruncate.AtEnd

    local selBtn = makeButton(f, {
        text = "SELECT", x = 8, y = 46, w = subs > 0 and 80 or 134, h = 22, size = 8,
        cb = function() toggleSel(inst) end,
    })
    if subs > 0 then
        makeButton(f, {text = "OPEN", x = 94, y = 46, w = 48, h = 22, size = 8, cb = function()
            ex.cur = inst
            populate()
        end})
    end
    ex.cards[inst] = {frame = f, stroke = st, btn = selBtn}
    updateCard(inst)
end

populate = function()
    ex.tok += 1
    local tok = ex.tok
    for _, c in ipairs(grid:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    ex.cards = {}
    if not ex.cur or not ex.cur.Parent then ex.cur = workspace end

    local names, o = {}, ex.cur
    while o and o ~= game do
        table.insert(names, 1, o.Name)
        o = o.Parent
    end
    local pathText = table.concat(names, " > ")
    if #pathText > 44 then pathText = "..." .. pathText:sub(-41) end

    local list = {}
    for _, k in ipairs(ex.cur:GetChildren()) do
        local isF, isM = k:IsA("Folder"), k:IsA("Model")
        if isF or isM then
            local kind = isF and "FOLDER" or "MODEL"
            local okF = ex.filter == "ALL" or ex.filter == kind
            local okQ = ex.query == "" or k.Name:lower():find(ex.query, 1, true) ~= nil
            if okF and okQ and not playerCharacter(k) then list[#list + 1] = k end
        end
    end
    table.sort(list, function(a, b)
        local fa, fb = a:IsA("Folder") and 0 or 1, b:IsA("Folder") and 0 or 1
        if fa ~= fb then return fa < fb end
        return a.Name:lower() < b.Name:lower()
    end)

    crumb.Text = pathText .. "   (" .. #list .. " item)"
    backBtn.Visible = ex.cur ~= workspace
    emptyL.Visible = #list == 0

    for i, k in ipairs(list) do
        if i > 300 then break end
        if tok ~= ex.tok then return end
        addCard(k, i)
        if i % 12 == 0 then task.wait() end
    end
end

searchField:GetPropertyChangedSignal("Text"):Connect(function()
    ex.qtok += 1
    local t = ex.qtok
    task.delay(0.3, function()
        if t == ex.qtok then
            ex.query = searchField.Text:lower()
            populate()
        end
    end)
end)

---------------------------------------------------------------------
-- 8. PANEL EXPORT (format, nama, opsi, generate, status)
---------------------------------------------------------------------
glass(Main, 12, 288, 476, 150, nil, true)

for i, f in ipairs({"RBXM", "RBXL", "JSON"}) do
    makeButton(Main, {text = f, x = 24 + (i - 1) * 68, y = 298, w = 64, h = 28, size = 10,
        toggle = function() return ex.format == f end,
        cb = function()
            ex.format = f
            prefs.format = f
            refreshToggles()
            refreshTitle()
        end})
end
local nameField = makeField(Main, 232, 298, 244, 28, "Nama otomatis (kosong = otomatis)")

local function optBtn(i, text, getter, setter)
    return makeButton(Main, {text = text, x = 24 + (i - 1) * 116, y = 332, w = 110, h = 28, size = 8,
        toggle = getter, cb = setter})
end
local mergeBtn = optBtn(1, "", function() return ex.merge end, function()
    ex.merge = not ex.merge
    prefs.merge = ex.merge
    refreshTitle()
    refreshToggles()
end)
local scriptBtn = optBtn(2, "", function() return ex.scripts end, function()
    ex.scripts = not ex.scripts
    prefs.scripts = ex.scripts
    refreshTitle()
    refreshToggles()
end)
local methodBtn = optBtn(3, "", function() return ex.method == "HC" end, function()
    ex.method = ex.method == "HC" and "EXEC" or "HC"
    prefs.method = ex.method
    refreshTitle()
    refreshToggles()
end)
local destBtn = optBtn(4, "", function() return ex.dest == "DOWNLOAD" end, function()
    ex.dest = ex.dest == "DOWNLOAD" and "WORKSPACE" or "DOWNLOAD"
    prefs.dest = ex.dest
    refreshTitle()
    refreshToggles()
end)

local genBtn = makeButton(Main, {text = "GENERATE & SIMPAN", x = 24, y = 366, w = 452, h = 38, size = 11, primary = true})
local genFill = new("Frame", {
    Size = UDim2.fromScale(0, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 0.7, BorderSizePixel = 0, ZIndex = 3,
}, genBtn)

statusL = lbl(Main, "Pilih folder / model (SELECT), pilih format, lalu GENERATE.", 24, 410, 452, 26, 9, GREY)

refreshTitle = function()
    mergeBtn.Text = ex.merge and "GABUNG: ON" or "GABUNG: OFF"
    scriptBtn.Text = ex.scripts and "SCRIPT: ON" or "SCRIPT: OFF"
    methodBtn.Text = ex.method == "HC" and "SAVER: HC" or "SAVER: EXECUTOR"
    destBtn.Text = ex.dest == "DOWNLOAD" and "WS + DOWNLOAD" or "WORKSPACE SAJA"
    if not ex.busy then
        if ex.format == "RBXL" then
            status("RBXL = seluruh place (Workspace + service). Item terpilih tidak dipakai.")
        elseif ex.format == "JSON" then
            status(("JSON = data Part dari %d item terpilih."):format(ex.count))
        else
            status(("RBXM = %d item terpilih%s."):format(ex.count, ex.merge and " (digabung jadi 1 file)" or ""))
        end
    end
end

---------------------------------------------------------------------
-- nama otomatis dari nama game
---------------------------------------------------------------------
task.spawn(function()
    local ok, info = pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
    end)
    local nm = ok and type(info) == "table" and sanitize(info.Name) or ""
    if nm == "" then nm = "Map_" .. tostring(game.PlaceId) end
    ex.autoName = nm
    nameField.PlaceholderText = "Otomatis: " .. nm
end)

---------------------------------------------------------------------
-- 9. SERIALIZER (RBXM / RBXL XML) -- tidak memindah / mengubah objek asli
---------------------------------------------------------------------
local CONTENT = {
    MeshId = true, TextureID = true, TextureId = true, Texture = true, SoundId = true,
    Image = true, ColorMap = true, NormalMap = true, MetalnessMap = true, RoughnessMap = true,
}
local REFS = {Part0 = true, Part1 = true, PrimaryPart = true, Attachment0 = true, Attachment1 = true, Value = true}
local INTP = {ZIndex = true}
local REAL_IN_PLACE = {StarterPlayerScripts = true, StarterCharacterScripts = true}
local PLACE_SERVICES = {
    "Lighting", "ReplicatedStorage", "ReplicatedFirst", "StarterGui", "StarterPack", "StarterPlayer",
    "SoundService", "Teams", "MaterialService",
}
local SERVICE_PROPS = {
    Workspace = {"Gravity", "FallenPartsDestroyHeight"},
    Lighting = {"Ambient", "OutdoorAmbient", "Brightness", "ColorShift_Bottom", "ColorShift_Top", "ClockTime",
        "GeographicLatitude", "FogColor", "FogEnd", "FogStart", "GlobalShadows", "EnvironmentDiffuseScale",
        "EnvironmentSpecularScale", "ExposureCompensation", "ShadowSoftness", "Technology"},
}
local CLASS_PROPS = {
    {"BasePart", {"Anchored", "CanCollide", "CanTouch", "CanQuery", "Massless", "Transparency", "Reflectance",
        "Color", "Material", "CFrame", "Size", "TopSurface", "BottomSurface", "LeftSurface", "RightSurface",
        "FrontSurface", "BackSurface", "CastShadow", "Locked", "CollisionGroup"}},
    {"Part", {"Shape"}},
    {"MeshPart", {"MeshId", "TextureID", "RenderFidelity", "CollisionFidelity"}},
    {"SpecialMesh", {"MeshType", "MeshId", "TextureId", "Scale", "Offset", "VertexColor"}},
    {"Decal", {"Texture", "Face", "Color3", "Transparency", "ZIndex"}},
    {"Texture", {"StudsPerTileU", "StudsPerTileV"}},
    {"SurfaceAppearance", {"ColorMap", "NormalMap", "MetalnessMap", "RoughnessMap", "AlphaMode"}},
    {"BaseScript", {"Disabled", "RunContext"}},
    {"Light", {"Brightness", "Color", "Enabled", "Shadows"}},
    {"PointLight", {"Range"}},
    {"SpotLight", {"Range", "Angle", "Face"}},
    {"SurfaceLight", {"Range", "Angle", "Face"}},
    {"Sound", {"SoundId", "Volume", "Looped", "PlaybackSpeed", "RollOffMaxDistance", "RollOffMinDistance"}},
    {"Attachment", {"CFrame", "Visible"}},
    {"WeldConstraint", {"Enabled", "Part0", "Part1"}},
    {"JointInstance", {"C0", "C1", "Enabled", "Part0", "Part1"}},
    {"Model", {"PrimaryPart"}},
    {"ValueBase", {"Value"}},
    {"SurfaceGui", {"Face", "Active", "AlwaysOnTop"}},
    {"BillboardGui", {"Active", "AlwaysOnTop", "Size", "StudsOffset"}},
    {"GuiObject", {"Size", "Position", "BackgroundColor3", "BackgroundTransparency", "Visible", "ZIndex"}},
    {"TextLabel", {"Text", "TextColor3", "TextSize", "Font", "TextScaled"}},
    {"ImageLabel", {"Image", "ImageColor3", "ImageTransparency"}},
}

local function xmlEsc(s)
    s = tostring(s):gsub("[%c]", function(c) return (c == "\n" or c == "\t" or c == "\r") and c or "" end)
    return (s:gsub("[&<>\"']", {["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&apos;"}))
end

local function fnum(v) return ("%.9g"):format(v) end

local function skipTop(inst)
    return inst:IsA("Terrain") or inst:IsA("Camera") or playerCharacter(inst)
end

-- kind = "model" (spec.roots, spec.wrap) atau "place".  prog(done, total)
-- return total, jumlahUnion, jumlahFolderPengganti
local function writeDocument(path, kind, spec, prog)
    if not writefile then error("executor tidak punya writefile") end
    local isPlace = kind == "place"

    -- pass 1: kumpulkan objek + beri referent (supaya Weld / PrimaryPart bisa jadi Ref)
    local list, ids, incl, clsOf, fb = {}, {}, {}, {}, {}
    local approxN, fbN, creatable = 0, 0, {}
    local function okClass(cls)
        if creatable[cls] == nil then
            local ok, o = pcall(Instance.new, cls)
            creatable[cls] = ok and o ~= nil
            if ok and o then pcall(function() o:Destroy() end) end
        end
        return creatable[cls]
    end
    local function collect(inst)
        if skipTop(inst) then return end
        local cls = inst.ClassName
        if inst:IsA("PartOperation") then
            cls = "Part"
            approxN += 1
        end
        if not okClass(cls) then
            if isPlace and REAL_IN_PLACE[cls] then
                -- kelas asli valid di file place
            elseif #inst:GetChildren() == 0 then
                return
            else
                cls = "Folder"
                fb[inst] = true
                fbN += 1
            end
        end
        clsOf[inst] = cls
        list[#list + 1] = inst
        ids[inst] = #list
        incl[inst] = true
        slice()
        for _, c in ipairs(inst:GetChildren()) do collect(c) end
    end

    local svcRoots = {}   -- place: {name, children}
    if isPlace then
        local wsKids = {}
        for _, c in ipairs(workspace:GetChildren()) do
            if not skipTop(c) then wsKids[#wsKids + 1] = c end
        end
        svcRoots[1] = {"Workspace", wsKids}
        for _, nm in ipairs(PLACE_SERVICES) do
            local ok, svc = pcall(function() return game:GetService(nm) end)
            if ok and svc and #svc:GetChildren() > 0 then svcRoots[#svcRoots + 1] = {nm, svc:GetChildren()} end
        end
        for _, sr in ipairs(svcRoots) do
            for _, c in ipairs(sr[2]) do collect(c) end
        end
    else
        for _, r in ipairs(spec.roots) do collect(r) end
    end
    local total = #list
    if total == 0 and not isPlace then error("tidak ada objek yang bisa ditulis") end

    -- pass 2: tulis XML (bertahap kalau executor punya appendfile)
    local out, chunked = {}, false
    if type(appendfile) == "function" then
        local ok1 = pcall(writefile, path, "")
        chunked = ok1 and pcall(appendfile, path, "")
    end
    local function flush()
        if chunked and #out > 0 then
            appendfile(path, table.concat(out, "\n") .. "\n")
            out = {}
        end
    end
    local function w(s)
        out[#out + 1] = s
        if chunked and #out >= 2000 then flush() end
    end

    local propCache = {}
    local function propsFor(inst)
        local key = inst.ClassName
        if propCache[key] then return propCache[key] end
        local names, seen = {"Name"}, {Name = true}
        for _, g in ipairs(CLASS_PROPS) do
            if inst:IsA(g[1]) then
                for _, nme in ipairs(g[2]) do
                    if not seen[nme] then
                        seen[nme] = true
                        names[#names + 1] = nme
                    end
                end
            end
        end
        propCache[key] = names
        return names
    end

    local function emit(inst, name)
        local ok, v = pcall(function() return inst[name] end)
        if not ok or v == nil then return end
        local t = typeof(v)
        if t == "boolean" then
            w(('<bool name="%s">%s</bool>'):format(name, tostring(v)))
        elseif t == "number" then
            if v ~= v or v == math.huge or v == -math.huge then return end
            if name == "Value" and inst:IsA("IntValue") then
                w(('<int64 name="Value">%d</int64>'):format(math.floor(v)))
            elseif name == "Value" and inst:IsA("NumberValue") then
                w(('<double name="Value">%s</double>'):format(fnum(v)))
            elseif INTP[name] then
                w(('<int name="%s">%d</int>'):format(name, math.floor(v)))
            else
                w(('<float name="%s">%s</float>'):format(name, fnum(v)))
            end
        elseif t == "string" then
            if CONTENT[name] then
                w(('<Content name="%s"><url>%s</url></Content>'):format(name, xmlEsc(v)))
            else
                w(('<string name="%s">%s</string>'):format(name, xmlEsc(v)))
            end
        elseif t == "Vector3" then
            local nm = (name == "Size" and inst:IsA("BasePart")) and "size" or name
            w(('<Vector3 name="%s"><X>%s</X><Y>%s</Y><Z>%s</Z></Vector3>'):format(nm, fnum(v.X), fnum(v.Y), fnum(v.Z)))
        elseif t == "Vector2" then
            w(('<Vector2 name="%s"><X>%s</X><Y>%s</Y></Vector2>'):format(name, fnum(v.X), fnum(v.Y)))
        elseif t == "UDim2" then
            w(('<UDim2 name="%s"><XS>%s</XS><XO>%d</XO><YS>%s</YS><YO>%d</YO></UDim2>'):format(
                name, fnum(v.X.Scale), v.X.Offset, fnum(v.Y.Scale), v.Y.Offset))
        elseif t == "UDim" then
            w(('<UDim name="%s"><S>%s</S><O>%d</O></UDim>'):format(name, fnum(v.Scale), v.Offset))
        elseif t == "Color3" then
            if name == "Color" and inst:IsA("BasePart") then
                local p = 0xFF000000 + math.floor(v.R * 255 + 0.5) * 65536
                    + math.floor(v.G * 255 + 0.5) * 256 + math.floor(v.B * 255 + 0.5)
                w(('<Color3uint8 name="Color3uint8">%d</Color3uint8>'):format(p))
            else
                w(('<Color3 name="%s"><R>%s</R><G>%s</G><B>%s</B></Color3>'):format(name, fnum(v.R), fnum(v.G), fnum(v.B)))
            end
        elseif t == "CFrame" then
            local c = {v:GetComponents()}
            local keys = {"X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"}
            local s = {('<CoordinateFrame name="%s">'):format(name)}
            for i, k in ipairs(keys) do s[#s + 1] = ("<%s>%s</%s>"):format(k, fnum(c[i]), k) end
            s[#s + 1] = "</CoordinateFrame>"
            w(table.concat(s))
        elseif t == "EnumItem" then
            w(('<token name="%s">%d</token>'):format(name, v.Value))
        elseif t == "Instance" then
            if REFS[name] and incl[v] then
                w(('<Ref name="%s">RBX%d</Ref>'):format(name, ids[v]))
            end
        end
    end

    local n = 0
    local function ser(inst)
        w(('<Item class="%s" referent="RBX%d"><Properties>'):format(clsOf[inst], ids[inst]))
        if fb[inst] then
            emit(inst, "Name")
        else
            for _, nme in ipairs(propsFor(inst)) do emit(inst, nme) end
            if ex.scripts and inst:IsA("LuaSourceContainer") then
                local okS, src = pcall(function() return inst.Source end)
                if (not okS or type(src) ~= "string" or src == "") and decompile then
                    okS, src = pcall(decompile, inst)
                end
                if okS and type(src) == "string" then
                    src = src:gsub("]]>", "]]]]><![CDATA[>")
                    w('<ProtectedString name="Source"><![CDATA[' .. src .. "]]></ProtectedString>")
                end
            end
        end
        w("</Properties>")
        for _, c in ipairs(inst:GetChildren()) do
            if incl[c] then ser(c) end
        end
        w("</Item>")
        n += 1
        slice()
        if n % 200 == 0 then prog(n, total) end
    end

    w('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">')
    if isPlace then
        for si, sr in ipairs(svcRoots) do
            w(('<Item class="%s" referent="RBXS%d"><Properties>'):format(sr[1], si))
            local okS, svc = pcall(function()
                if sr[1] == "Workspace" then return workspace end
                return game:GetService(sr[1])
            end)
            if okS and svc and SERVICE_PROPS[sr[1]] then
                for _, nme in ipairs(SERVICE_PROPS[sr[1]]) do emit(svc, nme) end
            end
            w("</Properties>")
            for _, c in ipairs(sr[2]) do
                if incl[c] then ser(c) end
            end
            w("</Item>")
            task.wait()
        end
    elseif spec.wrap then
        w('<Item class="Folder" referent="RBX0"><Properties><string name="Name">' .. xmlEsc(spec.wrap) .. "</string></Properties>")
        for _, r in ipairs(spec.roots) do
            if incl[r] then ser(r) end
        end
        w("</Item>")
    else
        for _, r in ipairs(spec.roots) do
            if incl[r] then ser(r) end
        end
    end
    w("</roblox>")
    if chunked then flush() else writefile(path, table.concat(out, "\n")) end
    return total, approxN, fbN
end

-- JSON: data Part (Name, Path, Position, Orientation, Size, Color, Material, ...)
local function writeJson(path, roots, prog)
    if not writefile then error("executor tidak punya writefile") end
    local data, cnt = {}, 0
    for _, r in ipairs(roots) do
        local stack = {r}
        while #stack > 0 do
            local o = table.remove(stack)
            if o:IsA("BasePart") and not o:IsA("Terrain") then
                cnt += 1
                local pos, ori, sz, col = o.Position, o.Orientation, o.Size, o.Color
                data[#data + 1] = {
                    Name = o.Name, ClassName = o.ClassName, Path = o:GetFullName(),
                    Position = {X = pos.X, Y = pos.Y, Z = pos.Z},
                    Orientation = {X = ori.X, Y = ori.Y, Z = ori.Z},
                    Size = {X = sz.X, Y = sz.Y, Z = sz.Z},
                    Color = {R = col.R, G = col.G, B = col.B},
                    Material = o.Material.Name, Anchored = o.Anchored, CanCollide = o.CanCollide,
                    Transparency = o.Transparency,
                }
                if cnt % 400 == 0 then prog(cnt, 0) end
            end
            for _, c in ipairs(o:GetChildren()) do stack[#stack + 1] = c end
            slice()
        end
    end
    writefile(path, HttpService:JSONEncode(data))
    return cnt
end

---------------------------------------------------------------------
-- 10. SAVER EXECUTOR (opsional) + DOWNLOAD
---------------------------------------------------------------------
local EXTS = {"rbxm", "rbxmx", "rbxl", "rbxlx"}
local SSI_URLS = {
    "https://raw.githubusercontent.com/luau/UniversalSynSaveInstance/main/saveinstance.luau",
    "https://cdn.jsdelivr.net/gh/luau/UniversalSynSaveInstance@main/saveinstance.luau",
    "https://raw.githubusercontent.com/luau/SynSaveInstance/main/saveinstance.luau",
}

local function httpGet(url)
    local ok, r = pcall(function() return game:HttpGet(url, true) end)
    if ok and type(r) == "string" and #r > 100 then return r end
    local req = request or http_request or (syn and syn.request) or (http and http.request)
    if req then
        local ok2, res = pcall(req, {Url = url, Method = "GET"})
        if ok2 and type(res) == "table" and type(res.Body) == "string" and #res.Body > 100 then return res.Body end
    end
end

local saverFn, saverMode
local function getSaver()
    if saverFn then return saverFn, saverMode end
    local native = (type(saveinstance) == "function" and saveinstance)
        or (type(save_instance) == "function" and save_instance)
        or (syn and type(syn.saveinstance) == "function" and syn.saveinstance)
        or (getgenv and type(getgenv().saveinstance) == "function" and getgenv().saveinstance)
    if native then
        saverFn, saverMode = native, "native"
        return saverFn, saverMode
    end
    for _, url in ipairs(SSI_URLS) do
        local src = httpGet(url)
        if src then
            local ok, fn = pcall(function() return loadstring(src, "saveinstance")() end)
            if ok and type(fn) == "function" then
                saverFn, saverMode = fn, "online"
                return saverFn, saverMode
            end
        end
    end
end

local function findOut(base)
    if not isfile then return nil end
    for _, e in ipairs(EXTS) do
        local p = base .. "." .. e
        local ok, f = pcall(isfile, p)
        if ok and f then return p, e end
    end
end

local function callSave(saver, obj, base, isPlace)
    if not isfile then return nil, "executor tidak punya isfile" end
    if delfile then
        for _, e in ipairs(EXTS) do
            local p = base .. "." .. e
            local ok, f = pcall(isfile, p)
            if ok and f then pcall(delfile, p) end
        end
    end
    local attempts
    if isPlace then
        attempts = {
            function() return saver({FileName = base, Binary = true, Decompile = ex.scripts, DecompileTimeout = 10, SaveNonCreatable = true}) end,
            function() return saver({FileName = base}) end,
            function() return saver(game, base) end,
        }
    else
        attempts = {
            function() return saver({Object = obj, FileName = base, Binary = true, Decompile = ex.scripts, DecompileTimeout = 10}) end,
            function() return saver({Object = obj, FileName = base}) end,
            function() return saver(obj, base) end,
        }
    end
    local lastErr = "saveinstance tidak menghasilkan file"
    for _, a in ipairs(attempts) do
        local ok, err = pcall(a)
        if ok then
            local p, e = findOut(base)
            if p then return p, e end
        else
            lastErr = tostring(err)
        end
    end
    return nil, lastErr
end

-- saver executor lewat salinan di ReplicatedStorage (objek asli tidak dipindah)
local function execSave(job)
    local saver, mode = getSaver()
    if not saver then return nil, "saveinstance tidak tersedia" end
    if job.kind == "place" then
        local p, e = callSave(saver, nil, job.name, true)
        if p then return p, "executor " .. mode end
        return nil, tostring(e)
    end
    local obj
    if job.wrap then
        obj = Instance.new("Folder")
        obj.Name = job.wrap
        for _, r in ipairs(job.roots) do
            local okc, cl = pcall(function() return r:Clone() end)
            if okc and cl then cl.Parent = obj end
        end
    else
        local okc, cl = pcall(function() return job.roots[1]:Clone() end)
        if not okc or not cl then return nil, "clone gagal" end
        obj = cl
    end
    pcall(function() obj.Parent = ReplicatedStorage end)
    local p, e = callSave(saver, obj, job.name, false)
    pcall(function() obj:Destroy() end)
    if p and tostring(e):sub(1, 4) == "rbxl" then
        pcall(function() if delfile then delfile(p) end end)
        return nil, "executor menyimpan place (Object diabaikan)"
    end
    if p then return p, "executor " .. mode end
    return nil, tostring(e)
end

local lastDlErr
local function deliver(path, fileName)
    lastDlErr = nil
    if not (readfile and writefile) then
        lastDlErr = "executor tanpa readfile/writefile"
        return false
    end
    local okR, data = pcall(readfile, path)
    if not okR or type(data) ~= "string" or #data == 0 then
        lastDlErr = "gagal membaca file hasil"
        return false
    end
    for _, dir in ipairs(DL_DIRS) do
        local first = dir:match("^/([^/]+)")
        local existed = false
        if first and isfolder then
            local okF, r = pcall(isfolder, first)
            existed = okF and r == true
        end
        local dst = dir .. "/" .. fileName
        local okW, errW = pcall(writefile, dst, data)
        if okW then
            local fake = false
            if first and isfolder and not existed then
                local okF, r = pcall(isfolder, first)
                fake = okF and r == true
            end
            if fake then
                lastDlErr = "path " .. dir .. " di-sandbox ke workspace"
                pcall(function() if delfile then delfile(dst) end end)
            else
                local okB, back = pcall(readfile, dst)
                if okB and type(back) == "string" and #back == #data then return true, dir end
                lastDlErr = "verifikasi gagal di " .. dir
            end
        else
            lastDlErr = tostring(errW)
        end
    end
    return false
end

---------------------------------------------------------------------
-- 11. GENERATE
---------------------------------------------------------------------
local function dedupe(items)
    local set = {}
    for _, it in ipairs(items) do set[it] = true end
    local out = {}
    for _, it in ipairs(items) do
        local skip, p = false, it.Parent
        while p do
            if set[p] then skip = true break end
            p = p.Parent
        end
        if not skip then out[#out + 1] = it end
    end
    return out
end

local function resetGen()
    ex.busy = false
    genBtn.Text = "GENERATE & SIMPAN"
    tw(genFill, 0.25, {Size = UDim2.fromScale(0, 1)})
    refreshTitle()
end

local function generate()
    if ex.busy then return end
    local fmt = ex.format
    local items = {}
    if fmt ~= "RBXL" then
        for inst in pairs(ex.sel) do
            if inst.Parent then items[#items + 1] = inst end
        end
        items = dedupe(items)
        if #items == 0 then
            return toast("Pilih dulu", "Pilih folder / model yang mau diexport (tekan SELECT).", true)
        end
    end

    ex.busy = true
    genBtn.Text = "MENYIAPKAN..."
    tw(genFill, 0.2, {Size = UDim2.fromScale(0.05, 1)})

    local ext = fmt == "RBXL" and "rbxl" or (fmt == "JSON" and "json" or "rbxm")
    local custom = sanitize(nameField.Text)
    local baseAuto = ex.autoName or ("Map_" .. tostring(game.PlaceId))

    -- nama: manual = persis (kalau banyak: _2, _3), otomatis = tidak menimpa file lama
    local used = {}
    local function finalName(base, isAuto)
        base = sanitize(base)
        if base == "" then base = EXPORT_ROOT_NAME end
        used[base] = (used[base] or 0) + 1
        local name = used[base] > 1 and (base .. "_" .. used[base]) or base
        if isAuto and isfile then
            local k, cand = 2, name
            while true do
                local okF, found = pcall(isfile, cand .. "." .. ext)
                if not (okF and found) then break end
                cand = ("%s (%d)"):format(name, k)
                k += 1
            end
            name = cand
        end
        return name
    end

    -- daftar pekerjaan
    local jobs = {}
    if fmt == "RBXL" then
        jobs[1] = {kind = "place", name = finalName(custom ~= "" and custom or baseAuto, custom == "")}
    elseif ex.merge and #items > 1 then
        local nm = finalName(custom ~= "" and custom or baseAuto, custom == "")
        jobs[1] = {kind = fmt == "JSON" and "json" or "model", roots = items, wrap = nm, name = nm}
    else
        for _, it in ipairs(items) do
            jobs[#jobs + 1] = {
                kind = fmt == "JSON" and "json" or "model", roots = {it},
                name = finalName(custom ~= "" and custom or it.Name, custom == ""),
            }
        end
    end

    local t0, working, curObj = os.clock(), true, 0
    task.spawn(function()
        while working do
            genBtn.Text = ("MENYIMPAN...  %ds   %d obj"):format(math.floor(os.clock() - t0), curObj)
            task.wait(0.4)
        end
    end)
    local function prog(done, total)
        curObj = done
        if total and total > 0 then tw(genFill, 0.15, {Size = UDim2.fromScale(math.clamp(done / total, 0.05, 1), 1)}) end
    end

    local outputs, errs, notes = {}, {}, {}
    for _, job in ipairs(jobs) do
        local path = job.name .. "." .. ext
        local okJob, err = pcall(function()
            local savedBy
            if ex.method == "EXEC" and job.kind ~= "json" then
                local p, how = execSave(job)
                if p then
                    outputs[#outputs + 1] = {path = p, name = p:match("([^/]+)$") or p, how = how}
                    return
                end
                notes[#notes + 1] = "executor gagal (" .. tostring(how):sub(1, 40) .. "), pakai HC"
            end
            if job.kind == "json" then
                local cnt = writeJson(path, job.roots, prog)
                outputs[#outputs + 1] = {path = path, name = path, how = ("JSON, %d Part"):format(cnt)}
            else
                local total, approxN, fbN = writeDocument(path, job.kind, job, prog)
                local how = ("HC, %d objek"):format(total)
                if approxN > 0 then how = how .. (", %d Union jadi Part kotak"):format(approxN) end
                if fbN > 0 then how = how .. (", %d wadah jadi Folder"):format(fbN) end
                outputs[#outputs + 1] = {path = path, name = path, how = how}
            end
        end)
        if not okJob then errs[#errs + 1] = job.name .. ": " .. tostring(err) end
    end
    working = false

    if #outputs == 0 then
        resetGen()
        status("Export gagal: " .. tostring(errs[1] or "tidak ada file yang dihasilkan"):sub(1, 120), true)
        return toast("Export gagal", tostring(errs[1] or "Tidak ada file."):sub(1, 90), true)
    end

    tw(genFill, 0.2, {Size = UDim2.fromScale(1, 1)})
    genBtn.Text = "MENGIRIM KE DOWNLOAD..."
    local savedDl, dlDir = 0, nil
    if ex.dest == "DOWNLOAD" then
        for _, o in ipairs(outputs) do
            local ok, dir = deliver(o.path, o.name)
            if ok then
                savedDl += 1
                dlDir = dir
            end
        end
    end

    copyText(outputs[1].path)
    local msg = ("%d file di Workspace: %s  (%s)"):format(#outputs, outputs[1].path, outputs[1].how)
    if ex.dest == "DOWNLOAD" then
        if savedDl > 0 then
            msg = msg .. "  |  Download: " .. tostring(dlDir)
        else
            print("[HC Export] Download gagal:", tostring(lastDlErr))
            msg = msg .. "  |  Download ditolak Delta (" .. tostring(lastDlErr):sub(1, 40) .. ")"
        end
    end
    if #notes > 0 then msg = msg .. "  |  " .. notes[1] end
    status(msg)
    toast("Export selesai", ("%d file tersimpan: %s"):format(#outputs, outputs[1].name), false)
    if #errs > 0 then toast("Sebagian gagal", errs[1]:sub(1, 90), true) end

    genBtn.Text = "SELESAI"
    task.wait(1)
    ex.busy = false
    resetGen()
    status(msg)
end
genBtn.Activated:Connect(function() task.spawn(generate) end)

---------------------------------------------------------------------
-- 12. START
---------------------------------------------------------------------
applyTheme = function(i)
    theme = THEMES[i]
    prefs.theme = i
    for k = #bound, 1, -1 do
        local b = bound[k]
        if b[1].Parent then
            b[1][b[2]] = theme[b[3]]
        else
            table.remove(bound, k)
        end
    end
    for k, ds in ipairs(dots) do
        tw(ds, 0.15, {Transparency = k == i and 0 or 0.6, Thickness = k == i and 2 or 1, Color = WHITE})
    end
    refreshToggles()
    for inst in pairs(ex.cards) do updateCard(inst) end
end

-- tombol melayang bergambar (bisa digeser, ketuk = buka / tutup)
local fab = new("ImageButton", {
    Image = IMG, Size = UDim2.fromOffset(52, 52), Position = prefs.fabPos or UDim2.fromOffset(14, 120),
    BackgroundColor3 = BLACK, BackgroundTransparency = 0.25, BorderSizePixel = 0, AutoButtonColor = false,
    ScaleType = Enum.ScaleType.Crop, ZIndex = 10,
}, gui)
corner(fab, 26)
waveStroke(fab, 2.6, 100)
local fabScale = new("UIScale", {}, fab)
do
    local down, moved, startPos, startAbs
    fab.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            down, moved, startPos, startAbs = true, false, i.Position, fab.Position
            tw(fabScale, 0.08, {Scale = 0.9})
        end
    end)
    table.insert(conns, UIS.InputChanged:Connect(function(i)
        if down and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startPos
            if d.Magnitude > 8 then moved = true end
            if moved then
                fab.Position = UDim2.new(startAbs.X.Scale, startAbs.X.Offset + d.X, startAbs.Y.Scale, startAbs.Y.Offset + d.Y)
            end
        end
    end))
    table.insert(conns, UIS.InputEnded:Connect(function(i)
        if down and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
            down = false
            tw(fabScale, 0.3, {Scale = 1}, Enum.EasingStyle.Back)
            if moved then
                prefs.fabPos = fab.Position
            else
                setOpen(not isOpen)
            end
        end
    end))
end

applyTheme(prefs.theme or 1)
refreshTitle()
populate()
setOpen(true)

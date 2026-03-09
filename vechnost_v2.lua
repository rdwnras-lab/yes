--[[
    FILE: vechnost_gui.lua
    BRAND: Vechnost  
    VERSION: 2.3.0
    FIXES:
      - Background glass ikut melengkung (rounded corners match border)
      - Tab bar 3D-style dengan gradient + highlight + shadow
      - Drag berfungsi dari mana saja di window
      - Semua fungsi sempurna
]]

-- =====================================================
-- CLEANUP
-- =====================================================
local CoreGui          = game:GetService("CoreGui")
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")

local GUI_NAME   = "VechnostGUI_v2"
local FLOAT_NAME = "VechnostFloat_v2"

local function SafeDestroy(name)
    pcall(function()
        local g = CoreGui:FindFirstChild(name)
        if g then g:Destroy() end
    end)
    pcall(function()
        local lp = Players.LocalPlayer
        if lp and lp:FindFirstChild("PlayerGui") then
            local g = lp.PlayerGui:FindFirstChild(name)
            if g then g:Destroy() end
        end
    end)
end
SafeDestroy(GUI_NAME)
SafeDestroy(FLOAT_NAME)

-- =====================================================
-- ASSETS & CONFIG
-- =====================================================
local ICON_ASSET = "rbxassetid://127239715511367"

local WIN_W  = 530
local WIN_H  = 350
local SIDE_W = 145
local HEAD_H = 44
local TAB_H  = 36
local RADIUS = 12   -- radius sudut utama

-- =====================================================
-- THEME
-- =====================================================
local T = {
    -- Window glass (warna dasar + alpha 50%)
    WinBg        = Color3.fromRGB(8, 15, 38),
    WinAlpha     = 0.50,

    -- Sidebar sedikit lebih gelap
    SidebarBg    = Color3.fromRGB(5, 11, 30),
    SidebarAlpha = 0.45,

    -- Accent glow
    GlowBlue     = Color3.fromRGB(75, 145, 255),

    -- Tab states
    TabActive    = Color3.fromRGB(38, 95, 235),
    TabActiveA   = 0.55,
    TabHover     = Color3.fromRGB(22, 55, 150),
    TabHoverA    = 0.60,

    -- Tab 3D top highlight
    TabHighlight = Color3.fromRGB(120, 180, 255),

    -- Indicator
    Indicator    = Color3.fromRGB(110, 185, 255),

    -- Teks
    TextWhite    = Color3.fromRGB(235, 242, 255),
    TextSub      = Color3.fromRGB(148, 178, 228),
    TextMuted    = Color3.fromRGB(85, 115, 175),
    TextAccent   = Color3.fromRGB(100, 168, 255),

    -- Cards / inputs
    CardBg       = Color3.fromRGB(10, 20, 52),
    CardAlpha    = 0.50,
    InputBg      = Color3.fromRGB(6, 13, 40),
    InputAlpha   = 0.55,
    BtnBg        = Color3.fromRGB(33, 88, 218),
    BtnAlpha     = 0.58,
    BtnHover     = Color3.fromRGB(52, 118, 255),
    ToggleOn     = Color3.fromRGB(38, 185, 105),
    ToggleOff    = Color3.fromRGB(42, 55, 90),

    -- Divider
    DivColor     = Color3.fromRGB(65, 135, 255),
    DivAlpha     = 0.42,
}

-- =====================================================
-- HELPERS
-- =====================================================
local function New(cls, props)
    local i = Instance.new(cls)
    for k, v in pairs(props or {}) do
        pcall(function() i[k] = v end)
    end
    return i
end

local function Corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = (type(r) == "number") and UDim.new(0, r) or (r or UDim.new(0, 8))
    c.Parent = p
    return c
end

local function Stroke(p, col, alpha, thick)
    local s = Instance.new("UIStroke")
    s.Color = col or T.GlowBlue
    s.Transparency = alpha or 0.50
    s.Thickness = thick or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = p
    return s
end

local function Pad(p, t, b, l, r)
    local u = Instance.new("UIPadding")
    u.PaddingTop    = UDim.new(0, t or 8)
    u.PaddingBottom = UDim.new(0, b or 8)
    u.PaddingLeft   = UDim.new(0, l or 10)
    u.PaddingRight  = UDim.new(0, r or 10)
    u.Parent = p
end

local function ListLayout(p, spacing)
    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, spacing or 5)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = p
    return l
end

local function Gradient(p, c0, c1, rot)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(c0, c1)
    g.Rotation = rot or 180
    g.Parent = p
    return g
end

local function Tween(inst, props, dur, sty, dir)
    pcall(function()
        TweenService:Create(inst,
            TweenInfo.new(dur or 0.18,
                sty or Enum.EasingStyle.Quad,
                dir or Enum.EasingDirection.Out),
            props):Play()
    end)
end

local function GetGuiParent()
    if gethui then return gethui() end
    if syn and syn.protect_gui then return CoreGui end
    return CoreGui
end

-- =====================================================
-- SCREEN GUI
-- =====================================================
local Screen = New("ScreenGui", {
    Name         = GUI_NAME,
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 100,
})
if syn and syn.protect_gui then pcall(syn.protect_gui, Screen) end
Screen.Parent = GetGuiParent()

-- =====================================================
-- MAIN WINDOW
-- FIX: Window itu sendiri adalah glass — tidak ada child BgGrad
-- Corner langsung di Window, sehingga glassmorphism ikut melengkung
-- =====================================================
local Window = New("Frame", {
    Name                 = "Window",
    Size                 = UDim2.fromOffset(WIN_W, WIN_H),
    Position             = UDim2.new(0.5, -WIN_W/2, 0.5, -WIN_H/2),
    BackgroundColor3     = T.WinBg,
    BackgroundTransparency = T.WinAlpha,
    BorderSizePixel      = 0,
    ClipsDescendants     = true,
})
Window.Parent = Screen

-- Corner PADA Window langsung — ini yang membuat semua konten ikut rounded
Corner(Window, RADIUS)

-- Gradient langsung di Window (tidak perlu frame terpisah!)
Gradient(Window,
    Color3.fromRGB(13, 24, 62),
    Color3.fromRGB(4, 8, 24),
    150)

-- Outer glow stroke
Stroke(Window, T.GlowBlue, 0.38, 1.5)

-- Glass top-rim highlight (garis tipis di atas)
local Rim = New("Frame", {
    Size             = UDim2.new(1, -2*RADIUS, 0, 1),
    Position         = UDim2.fromOffset(RADIUS, 1),
    BackgroundColor3 = Color3.fromRGB(200, 225, 255),
    BackgroundTransparency = 0.72,
    BorderSizePixel  = 0,
    ZIndex           = 10,
})
Rim.Parent = Window

-- =====================================================
-- DRAG SYSTEM — aktif dari SELURUH window
-- =====================================================
local _drag, _dStart, _wStart = false, nil, nil

Window.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        _drag   = true
        _dStart = inp.Position
        _wStart = Window.Position
    end
end)
Window.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        _drag = false
    end
end)
UserInputService.InputChanged:Connect(function(inp)
    if _drag and inp.UserInputType == Enum.UserInputType.MouseMovement then
        local d  = inp.Position - _dStart
        local vp = workspace.CurrentCamera.ViewportSize
        Window.Position = UDim2.fromOffset(
            math.clamp(_wStart.X.Offset + d.X, 0, vp.X - WIN_W),
            math.clamp(_wStart.Y.Offset + d.Y, 0, vp.Y - WIN_H)
        )
    end
end)

-- =====================================================
-- SIDEBAR
-- Karena Window pakai ClipsDescendants + Corner(RADIUS),
-- sidebar otomatis terpotong mengikuti sudut melengkung window
-- =====================================================
local Sidebar = New("Frame", {
    Size                 = UDim2.fromOffset(SIDE_W, WIN_H),
    BackgroundColor3     = T.SidebarBg,
    BackgroundTransparency = T.SidebarAlpha,
    BorderSizePixel      = 0,
    ZIndex               = 2,
})
Sidebar.Parent = Window

-- Gradient sidebar (atas lebih terang, bawah gelap)
Gradient(Sidebar,
    Color3.fromRGB(9, 20, 52),
    Color3.fromRGB(3, 8, 25),
    180)

-- Sidebar right divider glow
local SideDiv = New("Frame", {
    Size             = UDim2.fromOffset(1, WIN_H),
    Position         = UDim2.fromOffset(SIDE_W - 1, 0),
    BackgroundColor3 = T.DivColor,
    BackgroundTransparency = T.DivAlpha,
    BorderSizePixel  = 0,
    ZIndex           = 3,
})
SideDiv.Parent = Window

-- === SIDEBAR HEADER ===
local SHead = New("Frame", {
    Size               = UDim2.new(1, 0, 0, HEAD_H),
    BackgroundTransparency = 1,
    BorderSizePixel    = 0,
    ZIndex             = 3,
})
SHead.Parent = Sidebar

-- Brand icon
local BrandIcon = New("ImageLabel", {
    Image              = ICON_ASSET,
    Size               = UDim2.fromOffset(26, 26),
    Position           = UDim2.fromOffset(10, 9),
    BackgroundTransparency = 1,
    BorderSizePixel    = 0,
    ZIndex             = 4,
    ScaleType          = Enum.ScaleType.Fit,
})
BrandIcon.Parent = SHead
Corner(BrandIcon, 5)

New("TextLabel", {
    Text             = "Vechnost",
    Font             = Enum.Font.GothamBold,
    TextSize         = 13,
    TextColor3       = T.TextWhite,
    BackgroundTransparency = 1,
    Size             = UDim2.fromOffset(88, 16),
    Position         = UDim2.fromOffset(42, 8),
    TextXAlignment   = Enum.TextXAlignment.Left,
    ZIndex           = 4,
}).Parent = SHead

New("TextLabel", {
    Text             = "Fish It • v2.3",
    Font             = Enum.Font.Gotham,
    TextSize         = 9,
    TextColor3       = T.TextMuted,
    BackgroundTransparency = 1,
    Size             = UDim2.fromOffset(88, 12),
    Position         = UDim2.fromOffset(42, 25),
    TextXAlignment   = Enum.TextXAlignment.Left,
    ZIndex           = 4,
}).Parent = SHead

-- Header bottom line
New("Frame", {
    Size             = UDim2.new(1, -12, 0, 1),
    Position         = UDim2.fromOffset(6, HEAD_H - 1),
    BackgroundColor3 = T.GlowBlue,
    BackgroundTransparency = 0.68,
    BorderSizePixel  = 0,
    ZIndex           = 3,
}).Parent = Sidebar

-- Tab list container
local TabList = New("Frame", {
    Size               = UDim2.new(1, 0, 1, -HEAD_H - 2),
    Position           = UDim2.fromOffset(0, HEAD_H + 2),
    BackgroundTransparency = 1,
    BorderSizePixel    = 0,
    ZIndex             = 3,
})
TabList.Parent = Sidebar
ListLayout(TabList, 3)
Pad(TabList, 4, 4, 5, 5)

-- =====================================================
-- PANEL KANAN
-- =====================================================
local Panel = New("Frame", {
    Size               = UDim2.new(1, -SIDE_W, 1, 0),
    Position           = UDim2.fromOffset(SIDE_W, 0),
    BackgroundTransparency = 1,
    BorderSizePixel    = 0,
    ZIndex             = 2,
})
Panel.Parent = Window

-- Panel header
local PHead = New("Frame", {
    Size               = UDim2.new(1, 0, 0, HEAD_H),
    BackgroundTransparency = 1,
    BorderSizePixel    = 0,
    ZIndex             = 3,
})
PHead.Parent = Panel

local PanelTitle = New("TextLabel", {
    Text             = "Webhook Logger",
    Font             = Enum.Font.GothamBold,
    TextSize         = 14,
    TextColor3       = T.TextWhite,
    BackgroundTransparency = 1,
    Size             = UDim2.new(1, -48, 1, 0),
    Position         = UDim2.fromOffset(14, 0),
    TextXAlignment   = Enum.TextXAlignment.Left,
    ZIndex           = 4,
})
PanelTitle.Parent = PHead

-- X Close Button
local XBtn = New("TextButton", {
    Text             = "✕",
    Font             = Enum.Font.GothamBold,
    TextSize         = 11,
    TextColor3       = T.TextMuted,
    BackgroundColor3 = Color3.fromRGB(155, 32, 32),
    BackgroundTransparency = 0.78,
    Size             = UDim2.fromOffset(22, 22),
    Position         = UDim2.new(1, -28, 0.5, -11),
    BorderSizePixel  = 0,
    ZIndex           = 5,
})
XBtn.Parent = PHead
Corner(XBtn, 6)
Stroke(XBtn, Color3.fromRGB(255, 80, 80), 0.75, 1)

-- Panel header bottom line
New("Frame", {
    Size             = UDim2.new(1, -12, 0, 1),
    Position         = UDim2.fromOffset(6, HEAD_H - 1),
    BackgroundColor3 = T.GlowBlue,
    BackgroundTransparency = 0.68,
    BorderSizePixel  = 0,
    ZIndex           = 3,
}).Parent = Panel

-- Content ScrollingFrame
local Content = New("ScrollingFrame", {
    Size                   = UDim2.new(1, -8, 1, -HEAD_H - 6),
    Position               = UDim2.fromOffset(4, HEAD_H + 3),
    BackgroundTransparency = 1,
    BorderSizePixel        = 0,
    ScrollBarThickness     = 2,
    ScrollBarImageColor3   = T.GlowBlue,
    ScrollBarImageTransparency = 0.40,
    CanvasSize             = UDim2.fromScale(0, 0),
    AutomaticCanvasSize    = Enum.AutomaticSize.Y,
    ZIndex                 = 3,
})
Content.Parent = Panel
ListLayout(Content, 6)
Pad(Content, 2, 10, 0, 4)

-- =====================================================
-- COMPONENT LIBRARY
-- =====================================================

-- Section header
local function Section(title, parent)
    local f = New("Frame", {
        Size               = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        BorderSizePixel    = 0,
        ZIndex             = 4,
    })
    f.Parent = parent or Content

    New("TextLabel", {
        Text             = string.upper(title),
        Font             = Enum.Font.GothamBold,
        TextSize         = 9,
        TextColor3       = T.TextAccent,
        BackgroundTransparency = 1,
        Size             = UDim2.new(1, 0, 1, 0),
        TextXAlignment   = Enum.TextXAlignment.Left,
        ZIndex           = 5,
    }).Parent = f

    New("Frame", {
        Size             = UDim2.new(1, 0, 0, 1),
        Position         = UDim2.new(0, 0, 1, -1),
        BackgroundColor3 = T.GlowBlue,
        BackgroundTransparency = 0.64,
        BorderSizePixel  = 0,
        ZIndex           = 4,
    }).Parent = f
    return f
end

-- Input field
local function Input(label, placeholder, cb, parent)
    local card = New("Frame", {
        Size             = UDim2.new(1, 0, 0, 54),
        BackgroundColor3 = T.CardBg,
        BackgroundTransparency = T.CardAlpha,
        BorderSizePixel  = 0,
        ZIndex           = 4,
    })
    card.Parent = parent or Content
    Corner(card, 8)
    Stroke(card, T.GlowBlue, 0.68, 1)

    New("TextLabel", {
        Text           = label,
        Font           = Enum.Font.GothamMedium,
        TextSize       = 11,
        TextColor3     = T.TextSub,
        BackgroundTransparency = 1,
        Size           = UDim2.new(1, -14, 0, 14),
        Position       = UDim2.fromOffset(10, 6),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex         = 5,
    }).Parent = card

    local box = New("TextBox", {
        PlaceholderText  = placeholder or "",
        PlaceholderColor3 = T.TextMuted,
        Text             = "",
        Font             = Enum.Font.RobotoMono,
        TextSize         = 10,
        TextColor3       = T.TextWhite,
        BackgroundColor3 = T.InputBg,
        BackgroundTransparency = T.InputAlpha,
        Size             = UDim2.new(1, -20, 0, 22),
        Position         = UDim2.fromOffset(10, 22),
        TextXAlignment   = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        BorderSizePixel  = 0,
        ZIndex           = 5,
    })
    box.Parent = card
    Corner(box, 5)
    Stroke(box, T.GlowBlue, 0.75, 1)
    Pad(box, 0, 0, 5, 5)

    box.Focused:Connect(function()
        Tween(box, {BackgroundTransparency = 0.18}, 0.15)
    end)
    box.FocusLost:Connect(function()
        Tween(box, {BackgroundTransparency = T.InputAlpha}, 0.15)
        if cb then cb(box.Text) end
    end)
    return card, box
end

-- Toggle
local function Toggle(label, desc, default, cb, parent)
    local val = default or false
    local h   = desc and 46 or 36

    local card = New("Frame", {
        Size             = UDim2.new(1, 0, 0, h),
        BackgroundColor3 = T.CardBg,
        BackgroundTransparency = T.CardAlpha,
        BorderSizePixel  = 0,
        ZIndex           = 4,
    })
    card.Parent = parent or Content
    Corner(card, 8)
    Stroke(card, T.GlowBlue, 0.74, 1)

    New("TextLabel", {
        Text           = label,
        Font           = Enum.Font.GothamSemibold,
        TextSize       = 12,
        TextColor3     = T.TextWhite,
        BackgroundTransparency = 1,
        Size           = UDim2.new(1, -52, 0, 16),
        Position       = UDim2.fromOffset(10, desc and 6 or 10),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex         = 5,
    }).Parent = card

    if desc then
        New("TextLabel", {
            Text           = desc,
            Font           = Enum.Font.Gotham,
            TextSize       = 9,
            TextColor3     = T.TextMuted,
            BackgroundTransparency = 1,
            Size           = UDim2.new(1, -52, 0, 12),
            Position       = UDim2.fromOffset(10, 25),
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex         = 5,
        }).Parent = card
    end

    local track = New("Frame", {
        Size             = UDim2.fromOffset(34, 18),
        Position         = UDim2.new(1, -40, 0.5, -9),
        BackgroundColor3 = val and T.ToggleOn or T.ToggleOff,
        BorderSizePixel  = 0,
        ZIndex           = 5,
    })
    track.Parent = card
    Corner(track, UDim.new(1, 0))

    local knob = New("Frame", {
        Size             = UDim2.fromOffset(12, 12),
        Position         = val and UDim2.fromOffset(19, 3) or UDim2.fromOffset(3, 3),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel  = 0,
        ZIndex           = 6,
    })
    knob.Parent = track
    Corner(knob, UDim.new(1, 0))

    local hit = New("TextButton", {
        Text = "", BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), ZIndex = 7,
    })
    hit.Parent = card
    hit.MouseButton1Click:Connect(function()
        val = not val
        Tween(track, {BackgroundColor3 = val and T.ToggleOn or T.ToggleOff}, 0.2)
        Tween(knob,  {Position = val and UDim2.fromOffset(19,3) or UDim2.fromOffset(3,3)},
            0.2, Enum.EasingStyle.Back)
        if cb then cb(val) end
    end)

    return card,
        function() return val end,
        function(v)
            val = v
            Tween(track, {BackgroundColor3 = val and T.ToggleOn or T.ToggleOff}, 0.2)
            Tween(knob,  {Position = val and UDim2.fromOffset(19,3) or UDim2.fromOffset(3,3)},
                0.2, Enum.EasingStyle.Back)
        end
end

-- Button
local function Button(label, desc, cb, parent)
    local h = desc and 46 or 34
    local card = New("Frame", {
        Size             = UDim2.new(1, 0, 0, h),
        BackgroundColor3 = T.BtnBg,
        BackgroundTransparency = T.BtnAlpha,
        BorderSizePixel  = 0,
        ZIndex           = 4,
    })
    card.Parent = parent or Content
    Corner(card, 8)
    Stroke(card, T.GlowBlue, 0.55, 1)

    New("TextLabel", {
        Text           = label,
        Font           = Enum.Font.GothamSemibold,
        TextSize       = 12,
        TextColor3     = T.TextWhite,
        BackgroundTransparency = 1,
        Size           = UDim2.new(1, -26, 0, 16),
        Position       = UDim2.fromOffset(10, desc and 6 or 9),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex         = 5,
    }).Parent = card

    if desc then
        New("TextLabel", {
            Text           = desc,
            Font           = Enum.Font.Gotham,
            TextSize       = 9,
            TextColor3     = Color3.fromRGB(175, 208, 255),
            BackgroundTransparency = 1,
            Size           = UDim2.new(1, -26, 0, 11),
            Position       = UDim2.fromOffset(10, 25),
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex         = 5,
        }).Parent = card
    end

    New("TextLabel", {
        Text = "›", Font = Enum.Font.GothamBold, TextSize = 15,
        TextColor3 = Color3.fromRGB(160, 200, 255),
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(14, 14),
        Position = UDim2.new(1, -18, 0.5, -7),
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 5,
    }).Parent = card

    local hit = New("TextButton", {
        Text = "", BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), ZIndex = 6,
    })
    hit.Parent = card
    hit.MouseEnter:Connect(function()
        Tween(card, {BackgroundColor3 = T.BtnHover, BackgroundTransparency = 0.32}, 0.15)
    end)
    hit.MouseLeave:Connect(function()
        Tween(card, {BackgroundColor3 = T.BtnBg, BackgroundTransparency = T.BtnAlpha}, 0.15)
    end)
    hit.MouseButton1Click:Connect(function()
        Tween(card, {BackgroundTransparency = 0.12}, 0.07)
        task.delay(0.12, function() Tween(card, {BackgroundTransparency = 0.32}, 0.10) end)
        if cb then cb() end
    end)
    return card
end

-- Paragraph
local function Paragraph(title, body, parent)
    local card = New("Frame", {
        AutomaticSize    = Enum.AutomaticSize.Y,
        Size             = UDim2.new(1, 0, 0, 0),
        BackgroundColor3 = T.CardBg,
        BackgroundTransparency = 0.46,
        BorderSizePixel  = 0,
        ZIndex           = 4,
    })
    card.Parent = parent or Content
    Corner(card, 8)
    Stroke(card, T.GlowBlue, 0.76, 1)
    Pad(card, 8, 8, 10, 10)

    New("TextLabel", {
        Text           = title,
        Font           = Enum.Font.GothamBold,
        TextSize       = 11,
        TextColor3     = T.TextAccent,
        BackgroundTransparency = 1,
        Size           = UDim2.new(1, 0, 0, 14),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex         = 5,
    }).Parent = card

    local bodyLbl = New("TextLabel", {
        Text             = body,
        Font             = Enum.Font.Gotham,
        TextSize         = 10,
        TextColor3       = T.TextSub,
        BackgroundTransparency = 1,
        Size             = UDim2.new(1, 0, 0, 0),
        Position         = UDim2.fromOffset(0, 17),
        AutomaticSize    = Enum.AutomaticSize.Y,
        TextXAlignment   = Enum.TextXAlignment.Left,
        TextWrapped      = true,
        RichText         = true,
        ZIndex           = 5,
    })
    bodyLbl.Parent = card

    return card, function(_, newBody) bodyLbl.Text = newBody or "" end
end

-- Dropdown
local function Dropdown(label, options, multi, cb, parent)
    local selected = {}
    local isOpen   = false
    local itemH    = 26
    local listH    = math.min(#options * (itemH + 2) + 8, 148)

    local wrap = New("Frame", {
        Size = UDim2.new(1, 0, 0, 48),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 8,
    })
    wrap.Parent = parent or Content

    local hdr = New("Frame", {
        Size             = UDim2.new(1, 0, 0, 48),
        BackgroundColor3 = T.CardBg,
        BackgroundTransparency = T.CardAlpha,
        BorderSizePixel  = 0,
        ZIndex           = 9,
    })
    hdr.Parent = wrap
    Corner(hdr, 8)
    Stroke(hdr, T.GlowBlue, 0.68, 1)

    New("TextLabel", {
        Text = label, Font = Enum.Font.GothamMedium, TextSize = 10,
        TextColor3 = T.TextSub, BackgroundTransparency = 1,
        Size = UDim2.new(1,-34,0,13), Position = UDim2.fromOffset(10,5),
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 10,
    }).Parent = hdr

    local selLbl = New("TextLabel", {
        Text = "Semua rarity", Font = Enum.Font.Gotham, TextSize = 11,
        TextColor3 = T.TextWhite, BackgroundTransparency = 1,
        Size = UDim2.new(1,-34,0,15), Position = UDim2.fromOffset(10,26),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 10,
    })
    selLbl.Parent = hdr

    local arrow = New("TextLabel", {
        Text = "⌄", Font = Enum.Font.GothamBold, TextSize = 12,
        TextColor3 = T.TextAccent, BackgroundTransparency = 1,
        Size = UDim2.fromOffset(18,18), Position = UDim2.new(1,-22,0.5,-9),
        TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 10,
    })
    arrow.Parent = hdr

    local lst = New("ScrollingFrame", {
        Size = UDim2.new(1,0,0,0),
        Position = UDim2.fromOffset(0,50),
        BackgroundColor3 = Color3.fromRGB(5,12,38),
        BackgroundTransparency = 0.06,
        BorderSizePixel = 0, ClipsDescendants = true,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = T.GlowBlue,
        CanvasSize = UDim2.fromScale(0,0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ZIndex = 18, Visible = false,
    })
    lst.Parent = wrap
    Corner(lst, 8)
    Stroke(lst, T.GlowBlue, 0.60, 1)
    ListLayout(lst, 2)
    Pad(lst, 3, 3, 5, 5)

    for _, opt in ipairs(options) do
        local ob = New("TextButton", {
            Text = "  " .. opt, Font = Enum.Font.Gotham, TextSize = 11,
            TextColor3 = T.TextWhite,
            BackgroundColor3 = Color3.fromRGB(28,62,165),
            BackgroundTransparency = 1,
            Size = UDim2.new(1,0,0,itemH),
            TextXAlignment = Enum.TextXAlignment.Left,
            BorderSizePixel = 0, ZIndex = 19,
        })
        ob.Parent = lst
        Corner(ob, 5)
        ob.MouseEnter:Connect(function() Tween(ob,{BackgroundTransparency=0.52},0.12) end)
        ob.MouseLeave:Connect(function() Tween(ob,{BackgroundTransparency=selected[opt] and 0.32 or 1},0.12) end)
        ob.MouseButton1Click:Connect(function()
            if multi then selected[opt] = not selected[opt]
            else for k in pairs(selected) do selected[k]=nil end; selected[opt]=true end
            Tween(ob,{BackgroundTransparency=selected[opt] and 0.32 or 1},0.15)
            local s={}; for k,v in pairs(selected) do if v then table.insert(s,k) end end
            selLbl.Text = #s==0 and "Semua rarity" or table.concat(s,", ")
            if cb then cb(s) end
        end)
    end

    local hb = New("TextButton", {Text="",BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ZIndex=11})
    hb.Parent = hdr
    hb.MouseButton1Click:Connect(function()
        isOpen = not isOpen
        if isOpen then
            lst.Visible = true
            Tween(lst,{Size=UDim2.new(1,0,0,listH)},0.20,Enum.EasingStyle.Back)
            Tween(arrow,{Rotation=180},0.20)
            wrap.Size = UDim2.new(1,0,0,48+listH+4)
        else
            Tween(lst,{Size=UDim2.new(1,0,0,0)},0.15)
            Tween(arrow,{Rotation=0},0.15)
            task.delay(0.16,function() lst.Visible=false end)
            wrap.Size = UDim2.new(1,0,0,48)
        end
    end)
    return wrap
end

-- =====================================================
-- TAB SYSTEM — 3D Modern Style
-- Setiap tab punya:
--   - Gradient dari atas (terang) ke bawah (gelap) → efek 3D
--   - Top highlight line (garis tipis putih di atas)
--   - Bottom shadow line
--   - Indicator bar di kiri saat aktif
--   - Glow stroke saat aktif
-- =====================================================
local Tabs      = {}
local ActiveTab = nil

local function CreateTab(name, iconTxt)
    -- Container tab
    local btn = New("Frame", {
        Size             = UDim2.new(1, 0, 0, TAB_H),
        BackgroundColor3 = Color3.fromRGB(12, 24, 62),
        BackgroundTransparency = 0.60,
        BorderSizePixel  = 0,
        ZIndex           = 4,
    })
    btn.Parent = TabList
    Corner(btn, 7)

    -- Gradient 3D (atas lebih cerah → bawah lebih gelap)
    local btnGrad = Gradient(btn,
        Color3.fromRGB(22, 45, 110),
        Color3.fromRGB(6, 12, 38),
        180)

    -- Top highlight line (efek 3D raised)
    local topLine = New("Frame", {
        Size             = UDim2.new(1, -14, 0, 1),
        Position         = UDim2.fromOffset(7, 1),
        BackgroundColor3 = Color3.fromRGB(180, 215, 255),
        BackgroundTransparency = 0.72,
        BorderSizePixel  = 0,
        ZIndex           = 6,
    })
    topLine.Parent = btn

    -- Bottom shadow line
    New("Frame", {
        Size             = UDim2.new(1, -14, 0, 1),
        Position         = UDim2.new(0, 7, 1, -1),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.70,
        BorderSizePixel  = 0,
        ZIndex           = 6,
    }).Parent = btn

    -- Active indicator bar (kiri)
    local bar = New("Frame", {
        Size             = UDim2.fromOffset(3, 18),
        Position         = UDim2.new(0, -4, 0.5, -9),
        BackgroundColor3 = T.Indicator,
        BackgroundTransparency = 1,
        BorderSizePixel  = 0,
        ZIndex           = 7,
    })
    bar.Parent = btn
    Corner(bar, UDim.new(1, 0))

    -- Icon
    local ico = New("TextLabel", {
        Text             = iconTxt or "◆",
        Font             = Enum.Font.GothamBold,
        TextSize         = 13,
        TextColor3       = T.TextMuted,
        BackgroundTransparency = 1,
        Size             = UDim2.fromOffset(22, TAB_H),
        Position         = UDim2.fromOffset(7, 0),
        TextXAlignment   = Enum.TextXAlignment.Center,
        ZIndex           = 5,
    })
    ico.Parent = btn

    -- Label
    local lbl = New("TextLabel", {
        Text             = name,
        Font             = Enum.Font.GothamSemibold,
        TextSize         = 11,
        TextColor3       = T.TextMuted,
        BackgroundTransparency = 1,
        Size             = UDim2.new(1, -34, 1, 0),
        Position         = UDim2.fromOffset(32, 0),
        TextXAlignment   = Enum.TextXAlignment.Left,
        ZIndex           = 5,
    })
    lbl.Parent = btn

    -- Page
    local page = New("Frame", {
        Name             = "Page_" .. name,
        Size             = UDim2.new(1, 0, 0, 0),
        AutomaticSize    = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel  = 0,
        Visible          = false,
        ZIndex           = 4,
    })
    page.Parent = Content
    ListLayout(page, 6)
    Pad(page, 0, 4, 0, 0)

    local tabData = {
        name=name, btn=btn, bar=bar, ico=ico, lbl=lbl,
        page=page, grad=btnGrad, topLine=topLine
    }

    local hit = New("TextButton", {
        Text="", BackgroundTransparency=1,
        Size=UDim2.fromScale(1,1), ZIndex=8,
    })
    hit.Parent = btn

    -- Hover: sedikit cerahkan gradient + border
    hit.MouseEnter:Connect(function()
        if ActiveTab ~= tabData then
            Tween(btn, {BackgroundColor3=T.TabHover, BackgroundTransparency=T.TabHoverA}, 0.15)
            Tween(ico, {TextColor3=T.TextSub}, 0.15)
            Tween(lbl, {TextColor3=T.TextSub}, 0.15)
        end
    end)
    hit.MouseLeave:Connect(function()
        if ActiveTab ~= tabData then
            Tween(btn, {BackgroundColor3=Color3.fromRGB(12,24,62), BackgroundTransparency=0.60}, 0.15)
            Tween(ico, {TextColor3=T.TextMuted}, 0.15)
            Tween(lbl, {TextColor3=T.TextMuted}, 0.15)
        end
    end)

    hit.MouseButton1Click:Connect(function()
        if ActiveTab == tabData then return end

        -- Deactivate old tab
        if ActiveTab then
            ActiveTab.page.Visible = false
            Tween(ActiveTab.btn, {BackgroundColor3=Color3.fromRGB(12,24,62), BackgroundTransparency=0.60}, 0.15)
            Tween(ActiveTab.bar, {BackgroundTransparency=1}, 0.15)
            Tween(ActiveTab.ico, {TextColor3=T.TextMuted}, 0.15)
            Tween(ActiveTab.lbl, {TextColor3=T.TextMuted}, 0.15)
        end

        -- Activate new tab
        ActiveTab = tabData
        page.Visible = true
        -- Efek 3D pressed: background cerah, border glow
        Tween(btn, {BackgroundColor3=T.TabActive, BackgroundTransparency=T.TabActiveA}, 0.18)
        Tween(bar, {BackgroundTransparency=0}, 0.18)
        Tween(ico, {TextColor3=Color3.fromRGB(255,255,255)}, 0.18)
        Tween(lbl, {TextColor3=Color3.fromRGB(255,255,255)}, 0.18)
        PanelTitle.Text = name
    end)

    table.insert(Tabs, tabData)
    return page
end

-- =====================================================
-- BUAT TABS
-- =====================================================
local WebhookPage  = CreateTab("Webhook Logger", "🔗")
local SettingsPage = CreateTab("Settings",        "⚙")

-- Aktifkan tab pertama otomatis
do
    local f = Tabs[1]
    f.page.Visible = true
    ActiveTab = f
    f.btn.BackgroundColor3 = T.TabActive
    f.btn.BackgroundTransparency = T.TabActiveA
    f.bar.BackgroundTransparency = 0
    f.ico.TextColor3 = Color3.fromRGB(255,255,255)
    f.lbl.TextColor3 = Color3.fromRGB(255,255,255)
    PanelTitle.Text = f.name
end

-- =====================================================
-- ISI: WEBHOOK LOGGER
-- =====================================================
Section("Rarity Filter", WebhookPage)
Dropdown("Filter by Rarity",
    {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret"},
    true, function(opts) end, WebhookPage)

Section("Setup Webhook", WebhookPage)
local _, UrlBox = Input("Discord Webhook URL",
    "https://discord.com/api/webhooks/...",
    function(txt) end, WebhookPage)

Button("Save Webhook URL", "Validasi & simpan URL webhook",
    function() end, WebhookPage)

Section("Logger Mode", WebhookPage)
Toggle("Server-Notifier Mode",
    "Log ikan dari semua player di server",
    true, function(v) end, WebhookPage)

Section("Control", WebhookPage)
Toggle("Enable Webhook Logger",
    "Aktifkan notifikasi ke Discord",
    false, function(v) end, WebhookPage)

Section("Status", WebhookPage)
local _, UpdateStatus = Paragraph("Notifier Status", "Status: Offline", WebhookPage)

-- =====================================================
-- ISI: SETTINGS
-- =====================================================
Section("Tentang", SettingsPage)
Paragraph("Vechnost Webhook Notifier",
    "Beta Version • Server-Notifier Fish Catch Logger\n" ..
    "Log ikan dari semua player di server\n\n" ..
    "<font color='#5aaeff'>by Vechnost • discord.gg/vechnost</font>",
    SettingsPage)

Section("Testing", SettingsPage)
Button("Test Webhook",    "Kirim pesan test ke Discord channel", function() end, SettingsPage)
Button("Reset Log Counter","Reset counter dan hapus UUID cache", function() end, SettingsPage)

-- =====================================================
-- VISIBILITY SYSTEM
-- =====================================================
local guiVisible = true

local function SetVisible(v)
    guiVisible = v
    if v then
        Screen.Enabled = true
        Window.Size = UDim2.fromOffset(0, 0)
        Tween(Window, {Size=UDim2.fromOffset(WIN_W, WIN_H)},
            0.30, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    else
        Tween(Window, {Size=UDim2.fromOffset(0, 0)},
            0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        task.delay(0.22, function() Screen.Enabled = false end)
    end
end

-- X Button
XBtn.MouseEnter:Connect(function()
    Tween(XBtn, {BackgroundTransparency=0.30, TextColor3=Color3.fromRGB(255,85,85)}, 0.15)
end)
XBtn.MouseLeave:Connect(function()
    Tween(XBtn, {BackgroundTransparency=0.78, TextColor3=T.TextMuted}, 0.15)
end)
XBtn.MouseButton1Click:Connect(function()
    SetVisible(false)
end)

-- Keyboard V
UserInputService.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == Enum.KeyCode.V then
        SetVisible(not guiVisible)
    end
end)

-- =====================================================
-- FLOATING ICON BUTTON
-- =====================================================
local FloatGui = New("ScreenGui", {
    Name         = FLOAT_NAME,
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 101,
})
if syn and syn.protect_gui then pcall(syn.protect_gui, FloatGui) end
FloatGui.Parent = GetGuiParent()

local FloatBtn = New("ImageButton", {
    Image            = ICON_ASSET,
    Size             = UDim2.fromOffset(44, 44),
    Position         = UDim2.fromScale(0.05, 0.5),
    BackgroundColor3 = Color3.fromRGB(8, 18, 55),
    BackgroundTransparency = 0.18,
    AutoButtonColor  = false,
    BorderSizePixel  = 0,
    ZIndex           = 10,
    ScaleType        = Enum.ScaleType.Fit,
    ImageColor3      = Color3.fromRGB(255, 255, 255),
})
FloatBtn.Parent = FloatGui
Corner(FloatBtn, UDim.new(1, 0))
Stroke(FloatBtn, T.GlowBlue, 0.35, 2)

FloatBtn.MouseEnter:Connect(function()
    Tween(FloatBtn, {BackgroundTransparency=0.0}, 0.15)
end)
FloatBtn.MouseLeave:Connect(function()
    Tween(FloatBtn, {BackgroundTransparency=0.18}, 0.15)
end)
FloatBtn.MouseButton1Click:Connect(function()
    SetVisible(not guiVisible)
end)

-- Drag FloatBtn
local _fd, _fdS, _fpS = false, nil, nil
FloatBtn.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1
    or inp.UserInputType == Enum.UserInputType.Touch then
        _fd  = true
        _fdS = UserInputService:GetMouseLocation()
        _fpS = FloatBtn.Position
        inp.Changed:Connect(function()
            if inp.UserInputState == Enum.UserInputState.End then _fd = false end
        end)
    end
end)
RunService.RenderStepped:Connect(function()
    if not _fd then return end
    local m  = UserInputService:GetMouseLocation()
    local d  = m - _fdS
    local vp = workspace.CurrentCamera.ViewportSize
    local sz = FloatBtn.AbsoluteSize
    FloatBtn.Position = UDim2.fromOffset(
        math.clamp(_fpS.X.Offset + d.X, 0, vp.X - sz.X),
        math.clamp(_fpS.Y.Offset + d.Y, 0, vp.Y - sz.Y)
    )
end)

-- =====================================================
-- OPEN ANIMATION
-- =====================================================
Window.Size = UDim2.fromOffset(0, 0)
Tween(Window, {Size=UDim2.fromOffset(WIN_W, WIN_H)},
    0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

warn("[Vechnost v2.3] Loaded! | V = toggle | float icon = toggle | X = tutup")

--[[
    FILE: vechnost_gui.lua
    BRAND: Vechnost
    VERSION: 2.0.0
    DESC: Custom GUI Framework - Sidebar Layout
          Dark Blue Glassmorphism Style
          Tab kiri (icon+teks) | Divider | Konten kanan
]]

-- =====================================================
-- CLEANUP: Hapus GUI lama
-- =====================================================
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local GUI_NAME = "VechnostGUI_v2"
local old = CoreGui:FindFirstChild(GUI_NAME)
if old then old:Destroy() end

-- =====================================================
-- KONSTANTA DESAIN
-- =====================================================
local THEME = {
    -- Background utama (biru gelap transparan)
    BgMain        = Color3.fromRGB(8, 16, 36),
    BgMainAlpha   = 0.18,  -- transparansi utama

    -- Sidebar kiri
    Sidebar       = Color3.fromRGB(10, 20, 50),
    SidebarAlpha  = 0.55,

    -- Tab aktif
    TabActive     = Color3.fromRGB(30, 90, 220),
    TabActiveAlpha= 0.75,

    -- Tab hover
    TabHover      = Color3.fromRGB(20, 55, 140),
    TabHoverAlpha = 0.50,

    -- Tab normal
    TabNormal     = Color3.fromRGB(0, 0, 0),
    TabNormalAlpha= 0.0,

    -- Divider
    Divider       = Color3.fromRGB(60, 120, 255),
    DividerAlpha  = 0.35,

    -- Panel konten kanan
    PanelBg       = Color3.fromRGB(10, 22, 55),
    PanelAlpha    = 0.30,

    -- Teks
    TextPrimary   = Color3.fromRGB(220, 235, 255),
    TextSecondary = Color3.fromRGB(140, 170, 220),
    TextMuted     = Color3.fromRGB(80, 110, 170),
    TextAccent    = Color3.fromRGB(90, 160, 255),

    -- Aksen / glow
    Accent        = Color3.fromRGB(60, 140, 255),
    AccentGlow    = Color3.fromRGB(30, 80, 200),

    -- Input / Section
    InputBg       = Color3.fromRGB(12, 28, 70),
    InputBgAlpha  = 0.65,
    SectionLine   = Color3.fromRGB(40, 80, 180),

    -- Button
    BtnBg         = Color3.fromRGB(30, 80, 200),
    BtnBgAlpha    = 0.70,
    BtnHover      = Color3.fromRGB(50, 110, 240),

    -- Toggle On / Off
    ToggleOn      = Color3.fromRGB(40, 180, 100),
    ToggleOff     = Color3.fromRGB(50, 60, 90),

    -- Corner radius
    CornerMain    = UDim.new(0, 14),
    CornerCard    = UDim.new(0, 10),
    CornerBtn     = UDim.new(0, 8),
    CornerInput   = UDim.new(0, 7),
    CornerTab     = UDim.new(0, 9),
}

local FONT = {
    Title   = Enum.Font.GothamBold,
    Tab     = Enum.Font.GothamSemibold,
    Label   = Enum.Font.Gotham,
    Value   = Enum.Font.GothamMedium,
    Mono    = Enum.Font.RobotoMono,
}

local SIZE = {
    Window    = UDim2.fromOffset(680, 420),
    Sidebar   = UDim2.fromOffset(170, 420),
    Divider   = UDim2.fromOffset(1, 420),
    Panel     = UDim2.fromOffset(509, 420),
    TabHeight = 44,
    HeaderH   = 52,
}

-- =====================================================
-- HELPER FUNCTIONS
-- =====================================================
local function New(className, props, children)
    local inst = Instance.new(className)
    for k, v in pairs(props or {}) do
        inst[k] = v
    end
    for _, child in ipairs(children or {}) do
        child.Parent = inst
    end
    return inst
end

local function AddCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = radius or THEME.CornerCard
    c.Parent = parent
    return c
end

local function AddPadding(parent, t, b, l, r)
    local p = Instance.new("UIPadding")
    p.PaddingTop    = UDim.new(0, t or 8)
    p.PaddingBottom = UDim.new(0, b or 8)
    p.PaddingLeft   = UDim.new(0, l or 10)
    p.PaddingRight  = UDim.new(0, r or 10)
    p.Parent = parent
    return p
end

local function AddStroke(parent, color, alpha, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or THEME.Accent
    s.Transparency = alpha or 0.7
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

local function AddGradient(parent, colors, rotation)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(colors or {
        ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 35, 90)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 12, 35)),
    })
    g.Rotation = rotation or 135
    g.Parent = parent
    return g
end

local function Tween(inst, props, duration, style, dir)
    local info = TweenInfo.new(
        duration or 0.18,
        style or Enum.EasingStyle.Quad,
        dir or Enum.EasingDirection.Out
    )
    local t = TweenService:Create(inst, info, props)
    t:Play()
    return t
end

-- Label teks standar
local function MakeLabel(text, size, font, color, parent)
    local lbl = New("TextLabel", {
        Text = text,
        TextSize = size or 13,
        Font = font or FONT.Label,
        TextColor3 = color or THEME.TextPrimary,
        BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
        RichText = true,
        Parent = parent,
    })
    return lbl
end

-- =====================================================
-- ROOT GUI
-- =====================================================
local ScreenGui = New("ScreenGui", {
    Name = GUI_NAME,
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Parent = CoreGui,
})

-- Shadow backdrop
local Shadow = New("Frame", {
    Name = "Shadow",
    Size = UDim2.fromOffset(SIZE.Window.X.Offset + 24, SIZE.Window.Y.Offset + 24),
    Position = UDim2.new(0.5, -(SIZE.Window.X.Offset / 2) - 12, 0.5, -(SIZE.Window.Y.Offset / 2) - 12),
    BackgroundColor3 = Color3.fromRGB(0, 5, 20),
    BackgroundTransparency = 0.55,
    BorderSizePixel = 0,
    Parent = ScreenGui,
})
AddCorner(Shadow, UDim.new(0, 18))

-- Main Window
local Window = New("Frame", {
    Name = "Window",
    Size = SIZE.Window,
    Position = UDim2.new(0.5, -SIZE.Window.X.Offset / 2, 0.5, -SIZE.Window.Y.Offset / 2),
    BackgroundColor3 = THEME.BgMain,
    BackgroundTransparency = THEME.BgMainAlpha,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Parent = ScreenGui,
})
AddCorner(Window, THEME.CornerMain)
AddStroke(Window, THEME.Accent, 0.60, 1.2)

-- Background gradient
local WinBg = New("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.fromRGB(8, 18, 50),
    BackgroundTransparency = 0.0,
    BorderSizePixel = 0,
    ZIndex = 0,
    Parent = Window,
})
AddGradient(WinBg, {
    ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 22, 65)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(6, 14, 42)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 10, 30)),
}, 145)

-- Subtle noise overlay (dots pattern)
local NoiseOverlay = New("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 1,
    Parent = Window,
})

-- =====================================================
-- DRAG SYSTEM
-- =====================================================
local dragging, dragStart, startPos = false, nil, nil

Window.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = Window.Position
    end
end)

Window.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        local vp = workspace.CurrentCamera.ViewportSize
        local newX = math.clamp(startPos.X.Offset + delta.X, 0, vp.X - SIZE.Window.X.Offset)
        local newY = math.clamp(startPos.Y.Offset + delta.Y, 0, vp.Y - SIZE.Window.Y.Offset)
        Window.Position = UDim2.fromOffset(newX, newY)
    end
end)

-- =====================================================
-- LAYOUT: SIDEBAR | DIVIDER | PANEL
-- =====================================================

-- === SIDEBAR ===
local Sidebar = New("Frame", {
    Name = "Sidebar",
    Size = SIZE.Sidebar,
    Position = UDim2.fromOffset(0, 0),
    BackgroundColor3 = THEME.Sidebar,
    BackgroundTransparency = THEME.SidebarAlpha,
    BorderSizePixel = 0,
    ZIndex = 2,
    Parent = Window,
})

-- Sidebar gradient
AddGradient(Sidebar, {
    ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 30, 80)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(7, 16, 48)),
}, 180)

-- Logo / Brand header di sidebar
local SidebarHeader = New("Frame", {
    Name = "SidebarHeader",
    Size = UDim2.new(1, 0, 0, SIZE.HeaderH),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 3,
    Parent = Sidebar,
})

-- Logo icon (lingkaran aksen)
local LogoCircle = New("Frame", {
    Name = "LogoCircle",
    Size = UDim2.fromOffset(28, 28),
    Position = UDim2.fromOffset(14, 12),
    BackgroundColor3 = THEME.Accent,
    BackgroundTransparency = 0.15,
    BorderSizePixel = 0,
    ZIndex = 4,
    Parent = SidebarHeader,
})
AddCorner(LogoCircle, UDim.new(1, 0))
AddStroke(LogoCircle, THEME.Accent, 0.3, 1.5)

New("TextLabel", {
    Text = "V",
    Font = FONT.Title,
    TextSize = 15,
    TextColor3 = Color3.fromRGB(255, 255, 255),
    BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1),
    TextXAlignment = Enum.TextXAlignment.Center,
    ZIndex = 5,
    Parent = LogoCircle,
})

-- Brand name
New("TextLabel", {
    Text = "Vechnost",
    Font = FONT.Title,
    TextSize = 15,
    TextColor3 = THEME.TextPrimary,
    BackgroundTransparency = 1,
    Size = UDim2.fromOffset(110, 28),
    Position = UDim2.fromOffset(48, 12),
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4,
    Parent = SidebarHeader,
})

New("TextLabel", {
    Text = "v2.0.0",
    Font = FONT.Label,
    TextSize = 10,
    TextColor3 = THEME.TextMuted,
    BackgroundTransparency = 1,
    Size = UDim2.fromOffset(110, 14),
    Position = UDim2.fromOffset(48, 30),
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4,
    Parent = SidebarHeader,
})

-- Garis bawah header sidebar
local SidebarDivTop = New("Frame", {
    Size = UDim2.new(1, -20, 0, 1),
    Position = UDim2.fromOffset(10, SIZE.HeaderH - 1),
    BackgroundColor3 = THEME.Accent,
    BackgroundTransparency = 0.70,
    BorderSizePixel = 0,
    ZIndex = 3,
    Parent = Sidebar,
})

-- Tab container di sidebar
local TabContainer = New("ScrollingFrame", {
    Name = "TabContainer",
    Size = UDim2.new(1, 0, 1, -SIZE.HeaderH - 50),
    Position = UDim2.fromOffset(0, SIZE.HeaderH + 6),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 0,
    CanvasSize = UDim2.fromScale(0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ZIndex = 3,
    Parent = Sidebar,
})

New("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 3),
    Parent = TabContainer,
})
AddPadding(TabContainer, 4, 4, 8, 8)

-- Footer sidebar
local SidebarFooter = New("Frame", {
    Name = "SidebarFooter",
    Size = UDim2.new(1, 0, 0, 46),
    Position = UDim2.new(0, 0, 1, -46),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 3,
    Parent = Sidebar,
})

-- Garis atas footer
New("Frame", {
    Size = UDim2.new(1, -20, 0, 1),
    Position = UDim2.fromOffset(10, 0),
    BackgroundColor3 = THEME.Accent,
    BackgroundTransparency = 0.75,
    BorderSizePixel = 0,
    ZIndex = 3,
    Parent = SidebarFooter,
})

-- Close button di footer
local CloseBtn = New("TextButton", {
    Text = "✕  Close",
    Font = FONT.Tab,
    TextSize = 12,
    TextColor3 = THEME.TextMuted,
    BackgroundColor3 = Color3.fromRGB(180, 40, 40),
    BackgroundTransparency = 0.80,
    Size = UDim2.new(1, -16, 0, 30),
    Position = UDim2.fromOffset(8, 9),
    BorderSizePixel = 0,
    ZIndex = 4,
    Parent = SidebarFooter,
})
AddCorner(CloseBtn, THEME.CornerBtn)

CloseBtn.MouseEnter:Connect(function()
    Tween(CloseBtn, { BackgroundTransparency = 0.50, TextColor3 = Color3.fromRGB(255, 100, 100) }, 0.15)
end)
CloseBtn.MouseLeave:Connect(function()
    Tween(CloseBtn, { BackgroundTransparency = 0.80, TextColor3 = THEME.TextMuted }, 0.15)
end)
CloseBtn.MouseButton1Click:Connect(function()
    Tween(Window, { Size = UDim2.fromOffset(0, 0) }, 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In)
    task.wait(0.3)
    ScreenGui:Destroy()
end)

-- === DIVIDER ===
local Divider = New("Frame", {
    Name = "Divider",
    Size = UDim2.fromOffset(1, 420),
    Position = UDim2.fromOffset(SIZE.Sidebar.X.Offset, 0),
    BackgroundColor3 = THEME.Divider,
    BackgroundTransparency = THEME.DividerAlpha,
    BorderSizePixel = 0,
    ZIndex = 3,
    Parent = Window,
})

-- Glow effect pada divider
local DivGlow = New("Frame", {
    Size = UDim2.fromOffset(8, 420),
    Position = UDim2.fromOffset(-4, 0),
    BackgroundColor3 = THEME.Accent,
    BackgroundTransparency = 0.88,
    BorderSizePixel = 0,
    ZIndex = 2,
    Parent = Divider,
})

-- === PANEL KONTEN KANAN ===
local Panel = New("Frame", {
    Name = "Panel",
    Size = UDim2.new(1, -SIZE.Sidebar.X.Offset - 1, 1, 0),
    Position = UDim2.fromOffset(SIZE.Sidebar.X.Offset + 1, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 2,
    Parent = Window,
})

-- Panel header (judul tab aktif)
local PanelHeader = New("Frame", {
    Name = "PanelHeader",
    Size = UDim2.new(1, 0, 0, SIZE.HeaderH),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 3,
    Parent = Panel,
})

local PanelTitle = New("TextLabel", {
    Name = "PanelTitle",
    Text = "Webhook Logger",
    Font = FONT.Title,
    TextSize = 17,
    TextColor3 = THEME.TextPrimary,
    BackgroundTransparency = 1,
    Size = UDim2.new(1, -20, 1, 0),
    Position = UDim2.fromOffset(18, 0),
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4,
    Parent = PanelHeader,
})

-- Garis bawah panel header
New("Frame", {
    Size = UDim2.new(1, -18, 0, 1),
    Position = UDim2.fromOffset(9, SIZE.HeaderH - 1),
    BackgroundColor3 = THEME.Accent,
    BackgroundTransparency = 0.75,
    BorderSizePixel = 0,
    ZIndex = 3,
    Parent = Panel,
})

-- Content area (scrollable)
local ContentArea = New("ScrollingFrame", {
    Name = "ContentArea",
    Size = UDim2.new(1, -18, 1, -SIZE.HeaderH - 10),
    Position = UDim2.fromOffset(9, SIZE.HeaderH + 6),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = THEME.Accent,
    ScrollBarImageTransparency = 0.5,
    CanvasSize = UDim2.fromScale(0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ZIndex = 3,
    Parent = Panel,
})

New("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 8),
    Parent = ContentArea,
})
AddPadding(ContentArea, 4, 10, 0, 4)

-- =====================================================
-- COMPONENT LIBRARY
-- =====================================================

-- Section header
local function CreateSection(title, parent)
    local sec = New("Frame", {
        Name = "Section_" .. title,
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 4,
        Parent = parent or ContentArea,
        LayoutOrder = 0,
    })

    New("TextLabel", {
        Text = string.upper(title),
        Font = FONT.Title,
        TextSize = 10,
        TextColor3 = THEME.TextAccent,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -10, 1, 0),
        Position = UDim2.fromOffset(0, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        LetterSpacing = 2,
        ZIndex = 5,
        Parent = sec,
    })

    New("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, -1),
        BackgroundColor3 = THEME.SectionLine,
        BackgroundTransparency = 0.6,
        BorderSizePixel = 0,
        ZIndex = 4,
        Parent = sec,
    })

    return sec
end

-- Input field
local function CreateInput(labelText, placeholder, callback, parent)
    local card = New("Frame", {
        Name = "Input_" .. labelText,
        Size = UDim2.new(1, 0, 0, 62),
        BackgroundColor3 = THEME.InputBg,
        BackgroundTransparency = THEME.InputBgAlpha,
        BorderSizePixel = 0,
        ZIndex = 4,
        Parent = parent or ContentArea,
    })
    AddCorner(card, THEME.CornerInput)
    AddStroke(card, THEME.Accent, 0.78, 1)
    AddPadding(card, 8, 8, 12, 12)

    New("TextLabel", {
        Text = labelText,
        Font = FONT.Value,
        TextSize = 12,
        TextColor3 = THEME.TextSecondary,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 16),
        Position = UDim2.fromOffset(12, 8),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5,
        Parent = card,
    })

    local box = New("TextBox", {
        PlaceholderText = placeholder or "",
        PlaceholderColor3 = THEME.TextMuted,
        Text = "",
        Font = FONT.Mono,
        TextSize = 11,
        TextColor3 = THEME.TextPrimary,
        BackgroundColor3 = Color3.fromRGB(6, 14, 40),
        BackgroundTransparency = 0.3,
        Size = UDim2.new(1, -24, 0, 26),
        Position = UDim2.fromOffset(12, 28),
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        BorderSizePixel = 0,
        ZIndex = 5,
        Parent = card,
    })
    AddCorner(box, UDim.new(0, 5))
    AddPadding(box, 0, 0, 7, 7)
    AddStroke(box, THEME.Accent, 0.70, 1)

    box.Focused:Connect(function()
        Tween(box, { BackgroundTransparency = 0.1 }, 0.15)
    end)
    box.FocusLost:Connect(function()
        Tween(box, { BackgroundTransparency = 0.3 }, 0.15)
        if callback then callback(box.Text) end
    end)

    return card, box
end

-- Toggle
local function CreateToggle(labelText, descText, defaultVal, callback, parent)
    local val = defaultVal or false

    local card = New("Frame", {
        Name = "Toggle_" .. labelText,
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundColor3 = THEME.InputBg,
        BackgroundTransparency = THEME.InputBgAlpha,
        BorderSizePixel = 0,
        ZIndex = 4,
        Parent = parent or ContentArea,
    })
    AddCorner(card, THEME.CornerInput)
    AddStroke(card, THEME.Accent, 0.82, 1)

    New("TextLabel", {
        Text = labelText,
        Font = FONT.Value,
        TextSize = 13,
        TextColor3 = THEME.TextPrimary,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -70, 0, 20),
        Position = UDim2.fromOffset(14, 8),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5,
        Parent = card,
    })

    if descText then
        New("TextLabel", {
            Text = descText,
            Font = FONT.Label,
            TextSize = 10,
            TextColor3 = THEME.TextMuted,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -70, 0, 14),
            Position = UDim2.fromOffset(14, 28),
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 5,
            Parent = card,
        })
    end

    -- Track (background toggle)
    local track = New("Frame", {
        Size = UDim2.fromOffset(40, 22),
        Position = UDim2.new(1, -52, 0.5, -11),
        BackgroundColor3 = val and THEME.ToggleOn or THEME.ToggleOff,
        BackgroundTransparency = 0.1,
        BorderSizePixel = 0,
        ZIndex = 5,
        Parent = card,
    })
    AddCorner(track, UDim.new(1, 0))

    -- Knob
    local knob = New("Frame", {
        Size = UDim2.fromOffset(16, 16),
        Position = val and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        ZIndex = 6,
        Parent = track,
    })
    AddCorner(knob, UDim.new(1, 0))

    -- Clickable
    local btn = New("TextButton", {
        Text = "",
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 7,
        Parent = card,
    })

    btn.MouseButton1Click:Connect(function()
        val = not val
        Tween(track, { BackgroundColor3 = val and THEME.ToggleOn or THEME.ToggleOff }, 0.2)
        Tween(knob, { Position = val and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3) }, 0.2, Enum.EasingStyle.Back)
        if callback then callback(val) end
    end)

    return card, function() return val end
end

-- Button
local function CreateButton(labelText, descText, callback, parent)
    local card = New("Frame", {
        Name = "Btn_" .. labelText,
        Size = UDim2.new(1, 0, 0, descText and 50 or 38),
        BackgroundColor3 = THEME.BtnBg,
        BackgroundTransparency = THEME.BtnBgAlpha,
        BorderSizePixel = 0,
        ZIndex = 4,
        Parent = parent or ContentArea,
    })
    AddCorner(card, THEME.CornerBtn)
    AddStroke(card, THEME.Accent, 0.65, 1)

    New("TextLabel", {
        Text = labelText,
        Font = FONT.Tab,
        TextSize = 13,
        TextColor3 = THEME.TextPrimary,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -20, 0, 20),
        Position = UDim2.fromOffset(14, descText and 8 or 9),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5,
        Parent = card,
    })

    if descText then
        New("TextLabel", {
            Text = descText,
            Font = FONT.Label,
            TextSize = 10,
            TextColor3 = THEME.TextMuted,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -20, 0, 14),
            Position = UDim2.fromOffset(14, 28),
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 5,
            Parent = card,
        })
    end

    -- Arrow indicator
    New("TextLabel", {
        Text = "›",
        Font = FONT.Title,
        TextSize = 18,
        TextColor3 = THEME.TextAccent,
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(20, 20),
        Position = UDim2.new(1, -22, 0.5, -10),
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 5,
        Parent = card,
    })

    local btn = New("TextButton", {
        Text = "",
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 6,
        Parent = card,
    })

    btn.MouseEnter:Connect(function()
        Tween(card, { BackgroundTransparency = 0.35 }, 0.15)
        Tween(card, { BackgroundColor3 = THEME.BtnHover }, 0.15)
    end)
    btn.MouseLeave:Connect(function()
        Tween(card, { BackgroundTransparency = THEME.BtnBgAlpha }, 0.15)
        Tween(card, { BackgroundColor3 = THEME.BtnBg }, 0.15)
    end)
    btn.MouseButton1Click:Connect(function()
        Tween(card, { BackgroundTransparency = 0.2 }, 0.08)
        task.delay(0.08, function()
            Tween(card, { BackgroundTransparency = 0.35 }, 0.12)
        end)
        if callback then callback() end
    end)

    return card
end

-- Paragraph / Info box
local function CreateParagraph(title, content, parent)
    local card = New("Frame", {
        Name = "Para_" .. title,
        Size = UDim2.new(1, 0, 0, 10),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = THEME.InputBg,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        ZIndex = 4,
        Parent = parent or ContentArea,
    })
    AddCorner(card, THEME.CornerInput)
    AddStroke(card, THEME.Accent, 0.82, 1)
    AddPadding(card, 10, 10, 14, 14)

    New("TextLabel", {
        Text = title,
        Font = FONT.Tab,
        TextSize = 12,
        TextColor3 = THEME.TextAccent,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -28, 0, 16),
        Position = UDim2.fromOffset(14, 10),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5,
        Parent = card,
    })

    local contentLbl = New("TextLabel", {
        Text = content,
        Font = FONT.Label,
        TextSize = 11,
        TextColor3 = THEME.TextSecondary,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -28, 0, 0),
        Position = UDim2.fromOffset(14, 30),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        AutomaticSize = Enum.AutomaticSize.Y,
        RichText = true,
        ZIndex = 5,
        Parent = card,
    })

    return card, function(newTitle, newContent)
        -- Update content
        contentLbl.Text = newContent or ""
    end
end

-- Dropdown
local function CreateDropdown(labelText, options, multiSelect, callback, parent)
    local selected = {}
    local isOpen = false

    local wrap = New("Frame", {
        Name = "Dropdown_" .. labelText,
        Size = UDim2.new(1, 0, 0, 52),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 10,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = parent or ContentArea,
    })

    local header = New("Frame", {
        Size = UDim2.new(1, 0, 0, 52),
        BackgroundColor3 = THEME.InputBg,
        BackgroundTransparency = THEME.InputBgAlpha,
        BorderSizePixel = 0,
        ZIndex = 11,
        Parent = wrap,
    })
    AddCorner(header, THEME.CornerInput)
    AddStroke(header, THEME.Accent, 0.78, 1)

    New("TextLabel", {
        Text = labelText,
        Font = FONT.Value,
        TextSize = 12,
        TextColor3 = THEME.TextSecondary,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -50, 0, 16),
        Position = UDim2.fromOffset(14, 8),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 12,
        Parent = header,
    })

    local selectedLbl = New("TextLabel", {
        Text = "Semua rarity",
        Font = FONT.Label,
        TextSize = 11,
        TextColor3 = THEME.TextPrimary,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -50, 0, 18),
        Position = UDim2.fromOffset(14, 26),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 12,
        Parent = header,
    })

    local arrow = New("TextLabel", {
        Text = "⌄",
        Font = FONT.Title,
        TextSize = 14,
        TextColor3 = THEME.TextAccent,
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(24, 24),
        Position = UDim2.new(1, -30, 0.5, -12),
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 12,
        Parent = header,
    })

    -- Dropdown list
    local list = New("Frame", {
        Name = "DropList",
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, 54),
        BackgroundColor3 = Color3.fromRGB(8, 18, 55),
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 20,
        Visible = false,
        Parent = wrap,
    })
    AddCorner(list, THEME.CornerInput)
    AddStroke(list, THEME.Accent, 0.65, 1)

    local listLayout = New("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = list,
    })
    AddPadding(list, 4, 4, 6, 6)

    -- Build option items
    local optionBtns = {}
    for i, opt in ipairs(options) do
        local optBtn = New("TextButton", {
            Text = opt,
            Font = FONT.Label,
            TextSize = 12,
            TextColor3 = THEME.TextPrimary,
            BackgroundColor3 = Color3.fromRGB(20, 45, 120),
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 28),
            TextXAlignment = Enum.TextXAlignment.Left,
            BorderSizePixel = 0,
            ZIndex = 21,
            Parent = list,
        })
        AddCorner(optBtn, UDim.new(0, 5))
        AddPadding(optBtn, 0, 0, 8, 8)

        optBtn.MouseEnter:Connect(function()
            Tween(optBtn, { BackgroundTransparency = 0.6 }, 0.12)
        end)
        optBtn.MouseLeave:Connect(function()
            local isSel = selected[opt]
            Tween(optBtn, { BackgroundTransparency = isSel and 0.4 or 1 }, 0.12)
        end)
        optBtn.MouseButton1Click:Connect(function()
            if multiSelect then
                selected[opt] = not selected[opt]
            else
                selected = {}
                selected[opt] = true
            end
            Tween(optBtn, { BackgroundTransparency = selected[opt] and 0.4 or 1 }, 0.15)

            -- Update label
            local selList = {}
            for k, v in pairs(selected) do
                if v then table.insert(selList, k) end
            end
            selectedLbl.Text = #selList == 0 and "Semua rarity" or table.concat(selList, ", ")

            if callback then callback(selList) end
        end)

        optionBtns[opt] = optBtn
    end

    -- Toggle open/close
    local headerBtn = New("TextButton", {
        Text = "",
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 13,
        Parent = header,
    })

    headerBtn.MouseButton1Click:Connect(function()
        isOpen = not isOpen
        if isOpen then
            local itemCount = #options
            local targetH = math.min(itemCount * 28 + 10, 180)
            list.Visible = true
            list.Size = UDim2.new(1, 0, 0, 0)
            Tween(list, { Size = UDim2.new(1, 0, 0, targetH) }, 0.2, Enum.EasingStyle.Back)
            Tween(arrow, { Rotation = 180 }, 0.2)
            wrap.Size = UDim2.new(1, 0, 0, 52 + targetH + 6)
        else
            Tween(list, { Size = UDim2.new(1, 0, 0, 0) }, 0.15)
            Tween(arrow, { Rotation = 0 }, 0.15)
            task.delay(0.15, function() list.Visible = false end)
            wrap.Size = UDim2.new(1, 0, 0, 52)
        end
    end)

    return wrap
end

-- =====================================================
-- TAB SYSTEM
-- =====================================================
local tabs = {}
local activeTab = nil
local tabPages = {}

local function CreateTab(name, iconText)
    -- Tab button di sidebar
    local tabBtn = New("Frame", {
        Name = "Tab_" .. name,
        Size = UDim2.new(1, 0, 0, SIZE.TabHeight),
        BackgroundColor3 = THEME.TabNormal,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 5,
        Parent = TabContainer,
    })
    AddCorner(tabBtn, THEME.CornerTab)

    -- Active indicator bar (kiri)
    local indicator = New("Frame", {
        Size = UDim2.fromOffset(3, 24),
        Position = UDim2.new(0, -8, 0.5, -12),
        BackgroundColor3 = THEME.Accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 6,
        Parent = tabBtn,
    })
    AddCorner(indicator, UDim.new(1, 0))

    -- Icon
    local iconLbl = New("TextLabel", {
        Text = iconText or "◆",
        Font = FONT.Title,
        TextSize = 16,
        TextColor3 = THEME.TextMuted,
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(24, 24),
        Position = UDim2.fromOffset(10, 10),
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 6,
        Parent = tabBtn,
    })

    -- Label
    local nameLbl = New("TextLabel", {
        Text = name,
        Font = FONT.Tab,
        TextSize = 12,
        TextColor3 = THEME.TextMuted,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -44, 1, 0),
        Position = UDim2.fromOffset(38, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 6,
        Parent = tabBtn,
    })

    -- Page di panel kanan
    local page = New("Frame", {
        Name = "Page_" .. name,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 3,
        Parent = ContentArea,
    })

    -- Scroll list di page
    local pageScroll = New("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = THEME.Accent,
        ScrollBarImageTransparency = 0.5,
        CanvasSize = UDim2.fromScale(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ZIndex = 4,
        Parent = page,
    })
    New("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = pageScroll,
    })
    AddPadding(pageScroll, 2, 10, 0, 4)

    local tabData = {
        name = name,
        btn = tabBtn,
        indicator = indicator,
        iconLbl = iconLbl,
        nameLbl = nameLbl,
        page = page,
        scroll = pageScroll,
    }

    -- Click handler
    local clickBtn = New("TextButton", {
        Text = "",
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 7,
        Parent = tabBtn,
    })

    clickBtn.MouseEnter:Connect(function()
        if activeTab ~= tabData then
            Tween(tabBtn, { BackgroundTransparency = 0.70 }, 0.15)
            Tween(tabBtn, { BackgroundColor3 = THEME.TabHover }, 0.15)
        end
    end)
    clickBtn.MouseLeave:Connect(function()
        if activeTab ~= tabData then
            Tween(tabBtn, { BackgroundTransparency = 1 }, 0.15)
        end
    end)

    clickBtn.MouseButton1Click:Connect(function()
        if activeTab == tabData then return end

        -- Deaktifkan tab lama
        if activeTab then
            activeTab.page.Visible = false
            Tween(activeTab.btn, { BackgroundTransparency = 1 }, 0.15)
            Tween(activeTab.indicator, { BackgroundTransparency = 1 }, 0.15)
            Tween(activeTab.iconLbl, { TextColor3 = THEME.TextMuted }, 0.15)
            Tween(activeTab.nameLbl, { TextColor3 = THEME.TextMuted }, 0.15)
        end

        -- Aktifkan tab baru
        activeTab = tabData
        page.Visible = true
        Tween(tabBtn, { BackgroundColor3 = THEME.TabActive, BackgroundTransparency = THEME.TabActiveAlpha }, 0.18)
        Tween(indicator, { BackgroundTransparency = 0 }, 0.18)
        Tween(iconLbl, { TextColor3 = Color3.fromRGB(255, 255, 255) }, 0.18)
        Tween(nameLbl, { TextColor3 = Color3.fromRGB(255, 255, 255) }, 0.18)
        PanelTitle.Text = name
    end)

    table.insert(tabs, tabData)
    tabPages[name] = tabData
    return pageScroll  -- kembalikan scroll container untuk di-populate
end

-- =====================================================
-- BUAT TAB
-- =====================================================
local WebhookPage  = CreateTab("Webhook Logger", "🔗")
local SettingsPage = CreateTab("Settings",        "⚙")

-- Aktifkan tab pertama
do
    local first = tabs[1]
    first.page.Visible = true
    activeTab = first
    first.btn.BackgroundColor3 = THEME.TabActive
    first.btn.BackgroundTransparency = THEME.TabActiveAlpha
    first.indicator.BackgroundTransparency = 0
    first.iconLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    first.nameLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    PanelTitle.Text = first.name
end

-- =====================================================
-- ISI TAB: WEBHOOK LOGGER
-- =====================================================
CreateSection("Rarity Filter", WebhookPage)
CreateDropdown("Filter by Rarity", {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret"}, true, function(opts)
    -- TODO: callback
end, WebhookPage)

CreateSection("Setup Webhook", WebhookPage)
local _, urlBox = CreateInput("Discord Webhook URL", "https://discord.com/api/webhooks/...", function(text)
    -- TODO: simpan URL
end, WebhookPage)

CreateButton("Save Webhook URL", "Simpan dan validasi URL webhook", function()
    -- TODO
end, WebhookPage)

CreateSection("Logger Mode", WebhookPage)
CreateToggle("Server-Notifier Mode", "Log ikan dari semua player di server", true, function(val)
    -- TODO
end, WebhookPage)

CreateSection("Control", WebhookPage)
CreateToggle("Enable Webhook Logger", "Aktifkan pengiriman notifikasi ke Discord", false, function(val)
    -- TODO
end, WebhookPage)

CreateSection("Status", WebhookPage)
local _, updateStatus = CreateParagraph("Notifier Status", "Status: Offline", WebhookPage)

-- =====================================================
-- ISI TAB: SETTINGS
-- =====================================================
CreateSection("Tentang", SettingsPage)
CreateParagraph("Vechnost Webhook Notifier",
    "Beta Version • Server-Notifier Fish Catch Logger\nLog ikan dari semua player di server\n\n<font color='#5aa0ff'>by Vechnost</font>",
    SettingsPage)

CreateSection("Testing", SettingsPage)
CreateButton("Test Webhook", "Kirim pesan test ke Discord channel", function()
    -- TODO
end, SettingsPage)

CreateButton("Reset Log Counter", "Reset counter dan hapus UUID cache", function()
    -- TODO
end, SettingsPage)

-- =====================================================
-- OPEN ANIMATION
-- =====================================================
Window.Size = UDim2.fromOffset(0, 0)
Tween(Window, { Size = SIZE.Window }, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

warn("[Vechnost GUI v2] Loaded! Layout: Sidebar kiri | Divider | Panel kanan")
warn("[Vechnost GUI v2] Tab aktif: Webhook Logger")

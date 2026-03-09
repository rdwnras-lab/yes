--[[
    FILE: vechnost_gui.lua
    BRAND: Vechnost
    VERSION: 2.1.0
    DESC: Custom GUI - Glassmorphism Sidebar Layout
          Rayfield-sized window, rbxasset icon, floating toggle
]]

-- =====================================================
-- CLEANUP
-- =====================================================
local CoreGui          = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")

local GUI_NAME    = "VechnostGUI_v2"
local FLOAT_NAME  = "VechnostFloat_v2"

for _, n in ipairs({GUI_NAME, FLOAT_NAME}) do
    local old = CoreGui:FindFirstChild(n)
    if old then old:Destroy() end
end

-- =====================================================
-- ASSET
-- =====================================================
local ICON_ASSET = "rbxassetid://127239715511367"

-- =====================================================
-- THEME
-- =====================================================
local T = {
    WinBg          = Color3.fromRGB(12, 20, 45),
    WinAlpha       = 0.25,

    SidebarBg      = Color3.fromRGB(8, 16, 38),
    SidebarAlpha   = 0.38,

    GlowBlue       = Color3.fromRGB(80, 150, 255),
    StrokeAlpha    = 0.55,

    TabActiveBg    = Color3.fromRGB(40, 100, 240),
    TabActiveAlpha = 0.65,
    TabHoverBg     = Color3.fromRGB(25, 60, 160),
    TabHoverAlpha  = 0.50,

    Indicator      = Color3.fromRGB(100, 180, 255),

    TextWhite      = Color3.fromRGB(235, 242, 255),
    TextSub        = Color3.fromRGB(150, 180, 230),
    TextMuted      = Color3.fromRGB(90, 120, 180),
    TextAccent     = Color3.fromRGB(100, 170, 255),

    CardBg         = Color3.fromRGB(15, 28, 65),
    CardAlpha      = 0.55,
    InputBg        = Color3.fromRGB(8, 18, 50),
    InputAlpha     = 0.60,
    BtnBg          = Color3.fromRGB(35, 90, 220),
    BtnAlpha       = 0.65,
    BtnHover       = Color3.fromRGB(55, 120, 255),
    ToggleOn       = Color3.fromRGB(40, 190, 110),
    ToggleOff      = Color3.fromRGB(45, 58, 95),

    DivColor       = Color3.fromRGB(70, 140, 255),
    DivAlpha       = 0.40,

    CR_Win   = UDim.new(0, 12),
    CR_Card  = UDim.new(0, 9),
    CR_Btn   = UDim.new(0, 7),
    CR_Input = UDim.new(0, 6),
    CR_Tab   = UDim.new(0, 8),
}

local WIN_W  = 600
local WIN_H  = 380
local SIDE_W = 155
local HEAD_H = 48
local TAB_H  = 40

-- =====================================================
-- HELPERS
-- =====================================================
local function New(cls, props, children)
    local i = Instance.new(cls)
    for k,v in pairs(props or {}) do i[k]=v end
    for _,c in ipairs(children or {}) do c.Parent=i end
    return i
end

local function Corner(p, r)
    local c=Instance.new("UICorner"); c.CornerRadius=r or T.CR_Card; c.Parent=p; return c
end

local function Stroke(p, col, alpha, thick)
    local s=Instance.new("UIStroke")
    s.Color=col or T.GlowBlue; s.Transparency=alpha or T.StrokeAlpha
    s.Thickness=thick or 1; s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
    s.Parent=p; return s
end

local function Pad(p, t,b,l,r)
    local u=Instance.new("UIPadding")
    u.PaddingTop=UDim.new(0,t or 8); u.PaddingBottom=UDim.new(0,b or 8)
    u.PaddingLeft=UDim.new(0,l or 10); u.PaddingRight=UDim.new(0,r or 10)
    u.Parent=p; return u
end

local function Grad(p, c0, c1, rot)
    local g=Instance.new("UIGradient")
    g.Color=ColorSequence.new(c0,c1); g.Rotation=rot or 135; g.Parent=p
end

local function Tween(inst, props, dur, sty, dir)
    TweenService:Create(inst,
        TweenInfo.new(dur or 0.18, sty or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
        props):Play()
end

local function List(p, spacing)
    local l=Instance.new("UIListLayout")
    l.Padding=UDim.new(0,spacing or 6)
    l.SortOrder=Enum.SortOrder.LayoutOrder
    l.Parent=p; return l
end

-- =====================================================
-- SCREEN GUI
-- =====================================================
local Screen = New("ScreenGui",{
    Name=GUI_NAME, ResetOnSpawn=false,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling,
    Parent=CoreGui,
})

-- =====================================================
-- MAIN WINDOW
-- =====================================================
local Window = New("Frame",{
    Name="Window",
    Size=UDim2.fromOffset(WIN_W, WIN_H),
    Position=UDim2.new(0.5,-WIN_W/2, 0.5,-WIN_H/2),
    BackgroundColor3=T.WinBg,
    BackgroundTransparency=T.WinAlpha,
    BorderSizePixel=0,
    ClipsDescendants=true,
    Parent=Screen,
})
Corner(Window, T.CR_Win)
Stroke(Window, T.GlowBlue, 0.45, 1.5)

-- Glassmorphism background gradient
local BgGrad = New("Frame",{
    Size=UDim2.fromScale(1,1), BackgroundColor3=Color3.fromRGB(12,24,60),
    BackgroundTransparency=0, BorderSizePixel=0, ZIndex=0, Parent=Window,
})
Corner(BgGrad, T.CR_Win)
Grad(BgGrad, Color3.fromRGB(14,26,68), Color3.fromRGB(5,10,32), 150)

-- Top glass rim highlight
New("Frame",{
    Size=UDim2.new(1,-40,0,1), Position=UDim2.fromOffset(20,1),
    BackgroundColor3=Color3.fromRGB(180,210,255),
    BackgroundTransparency=0.80, BorderSizePixel=0, ZIndex=5, Parent=Window,
})

-- =====================================================
-- DRAG
-- =====================================================
local _drag, _dragStart, _winStart = false, nil, nil

local function EnableDrag(handle)
    handle.InputBegan:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.MouseButton1 then
            _drag=true; _dragStart=inp.Position; _winStart=Window.Position
        end
    end)
    handle.InputEnded:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.MouseButton1 then _drag=false end
    end)
end

UserInputService.InputChanged:Connect(function(inp)
    if _drag and inp.UserInputType==Enum.UserInputType.MouseMovement then
        local d=inp.Position-_dragStart
        local vp=workspace.CurrentCamera.ViewportSize
        Window.Position=UDim2.fromOffset(
            math.clamp(_winStart.X.Offset+d.X, 0, vp.X-WIN_W),
            math.clamp(_winStart.Y.Offset+d.Y, 0, vp.Y-WIN_H)
        )
    end
end)

-- =====================================================
-- SIDEBAR
-- =====================================================
local Sidebar = New("Frame",{
    Name="Sidebar",
    Size=UDim2.fromOffset(SIDE_W, WIN_H),
    BackgroundColor3=T.SidebarBg,
    BackgroundTransparency=T.SidebarAlpha,
    BorderSizePixel=0, ZIndex=2, Parent=Window,
})
Grad(Sidebar, Color3.fromRGB(10,22,58), Color3.fromRGB(5,12,38), 180)
EnableDrag(Sidebar)

-- Sidebar right glow divider
New("Frame",{
    Size=UDim2.fromOffset(1,WIN_H), Position=UDim2.fromOffset(SIDE_W-1,0),
    BackgroundColor3=T.DivColor, BackgroundTransparency=T.DivAlpha,
    BorderSizePixel=0, ZIndex=3, Parent=Window,
})

-- Sidebar header
local SHead = New("Frame",{
    Size=UDim2.new(1,0,0,HEAD_H),
    BackgroundTransparency=1, BorderSizePixel=0, ZIndex=3, Parent=Sidebar,
})
EnableDrag(SHead)

-- Brand icon (rbx asset kamu)
local BrandIcon = New("ImageLabel",{
    Image=ICON_ASSET,
    Size=UDim2.fromOffset(28,28),
    Position=UDim2.fromOffset(12,10),
    BackgroundTransparency=1, BorderSizePixel=0, ZIndex=4, Parent=SHead,
})
Corner(BrandIcon, UDim.new(0,6))

New("TextLabel",{
    Text="Vechnost", Font=Enum.Font.GothamBold,
    TextSize=14, TextColor3=T.TextWhite,
    BackgroundTransparency=1,
    Size=UDim2.fromOffset(95,18), Position=UDim2.fromOffset(46,8),
    TextXAlignment=Enum.TextXAlignment.Left, ZIndex=4, Parent=SHead,
})
New("TextLabel",{
    Text="v2.0 • Fish It", Font=Enum.Font.Gotham,
    TextSize=9, TextColor3=T.TextMuted,
    BackgroundTransparency=1,
    Size=UDim2.fromOffset(95,12), Position=UDim2.fromOffset(46,27),
    TextXAlignment=Enum.TextXAlignment.Left, ZIndex=4, Parent=SHead,
})

-- Header bottom divider
New("Frame",{
    Size=UDim2.new(1,-16,0,1), Position=UDim2.fromOffset(8,HEAD_H-1),
    BackgroundColor3=T.GlowBlue, BackgroundTransparency=0.72,
    BorderSizePixel=0, ZIndex=3, Parent=Sidebar,
})

-- Tab list container
local TabList = New("Frame",{
    Size=UDim2.new(1,0,1,-HEAD_H-4),
    Position=UDim2.fromOffset(0,HEAD_H+4),
    BackgroundTransparency=1, BorderSizePixel=0, ZIndex=3, Parent=Sidebar,
})
List(TabList, 2)
Pad(TabList, 2,2,6,6)

-- =====================================================
-- PANEL KANAN
-- =====================================================
local Panel = New("Frame",{
    Name="Panel",
    Size=UDim2.new(1,-SIDE_W,1,0),
    Position=UDim2.fromOffset(SIDE_W,0),
    BackgroundTransparency=1, BorderSizePixel=0, ZIndex=2, Parent=Window,
})

-- Panel header
local PHead = New("Frame",{
    Size=UDim2.new(1,0,0,HEAD_H),
    BackgroundTransparency=1, BorderSizePixel=0, ZIndex=3, Parent=Panel,
})
EnableDrag(PHead)

local PanelTitle = New("TextLabel",{
    Text="Webhook Logger", Font=Enum.Font.GothamBold,
    TextSize=15, TextColor3=T.TextWhite,
    BackgroundTransparency=1,
    Size=UDim2.new(1,-50,1,0), Position=UDim2.fromOffset(16,0),
    TextXAlignment=Enum.TextXAlignment.Left, ZIndex=4, Parent=PHead,
})

-- X close button (pojok kanan atas)
local XBtn = New("TextButton",{
    Text="✕", Font=Enum.Font.GothamBold,
    TextSize=13, TextColor3=T.TextMuted,
    BackgroundColor3=Color3.fromRGB(180,40,40),
    BackgroundTransparency=0.85,
    Size=UDim2.fromOffset(26,26),
    Position=UDim2.new(1,-34,0.5,-13),
    BorderSizePixel=0, ZIndex=5, Parent=PHead,
})
Corner(XBtn, T.CR_Btn)

XBtn.MouseEnter:Connect(function()
    Tween(XBtn,{BackgroundTransparency=0.40, TextColor3=Color3.fromRGB(255,100,100)},0.15)
end)
XBtn.MouseLeave:Connect(function()
    Tween(XBtn,{BackgroundTransparency=0.85, TextColor3=T.TextMuted},0.15)
end)

-- Panel header divider
New("Frame",{
    Size=UDim2.new(1,-16,0,1), Position=UDim2.fromOffset(8,HEAD_H-1),
    BackgroundColor3=T.GlowBlue, BackgroundTransparency=0.72,
    BorderSizePixel=0, ZIndex=3, Parent=Panel,
})

-- Content scroll area
local Content = New("ScrollingFrame",{
    Size=UDim2.new(1,-10,1,-HEAD_H-8),
    Position=UDim2.fromOffset(5,HEAD_H+4),
    BackgroundTransparency=1, BorderSizePixel=0,
    ScrollBarThickness=2,
    ScrollBarImageColor3=T.GlowBlue,
    ScrollBarImageTransparency=0.4,
    CanvasSize=UDim2.fromScale(0,0),
    AutomaticCanvasSize=Enum.AutomaticSize.Y,
    ZIndex=3, Parent=Panel,
})
List(Content, 7)
Pad(Content, 2,10,0,6)

-- =====================================================
-- COMPONENT LIBRARY
-- =====================================================

local function Section(title, parent)
    local f=New("Frame",{
        Size=UDim2.new(1,0,0,22), BackgroundTransparency=1,
        BorderSizePixel=0, ZIndex=4, Parent=parent or Content,
    })
    New("TextLabel",{
        Text=string.upper(title), Font=Enum.Font.GothamBold,
        TextSize=9, TextColor3=T.TextAccent, LetterSpacing=3,
        BackgroundTransparency=1,
        Size=UDim2.new(1,0,1,0), TextXAlignment=Enum.TextXAlignment.Left,
        ZIndex=5, Parent=f,
    })
    New("Frame",{
        Size=UDim2.new(1,0,0,1), Position=UDim2.new(0,0,1,-1),
        BackgroundColor3=T.GlowBlue, BackgroundTransparency=0.65,
        BorderSizePixel=0, ZIndex=4, Parent=f,
    })
    return f
end

local function Input(label, placeholder, cb, parent)
    local card=New("Frame",{
        Size=UDim2.new(1,0,0,58), BackgroundColor3=T.CardBg,
        BackgroundTransparency=T.CardAlpha, BorderSizePixel=0,
        ZIndex=4, Parent=parent or Content,
    })
    Corner(card, T.CR_Card); Stroke(card, T.GlowBlue, 0.72, 1)
    New("TextLabel",{
        Text=label, Font=Enum.Font.GothamMedium, TextSize=11,
        TextColor3=T.TextSub, BackgroundTransparency=1,
        Size=UDim2.new(1,-16,0,14), Position=UDim2.fromOffset(12,7),
        TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5, Parent=card,
    })
    local box=New("TextBox",{
        PlaceholderText=placeholder or "", PlaceholderColor3=T.TextMuted,
        Text="", Font=Enum.Font.RobotoMono, TextSize=10,
        TextColor3=T.TextWhite, BackgroundColor3=T.InputBg,
        BackgroundTransparency=T.InputAlpha,
        Size=UDim2.new(1,-24,0,24), Position=UDim2.fromOffset(12,24),
        TextXAlignment=Enum.TextXAlignment.Left,
        ClearTextOnFocus=false, BorderSizePixel=0, ZIndex=5, Parent=card,
    })
    Corner(box, T.CR_Input); Stroke(box, T.GlowBlue, 0.78, 1)
    Pad(box,0,0,6,6)
    box.Focused:Connect(function() Tween(box,{BackgroundTransparency=0.25},0.15) end)
    box.FocusLost:Connect(function()
        Tween(box,{BackgroundTransparency=T.InputAlpha},0.15)
        if cb then cb(box.Text) end
    end)
    return card, box
end

local function Toggle(label, desc, default, cb, parent)
    local val = default or false
    local card=New("Frame",{
        Size=UDim2.new(1,0,0,desc and 48 or 38),
        BackgroundColor3=T.CardBg, BackgroundTransparency=T.CardAlpha,
        BorderSizePixel=0, ZIndex=4, Parent=parent or Content,
    })
    Corner(card, T.CR_Card); Stroke(card, T.GlowBlue, 0.78, 1)
    New("TextLabel",{
        Text=label, Font=Enum.Font.GothamSemibold, TextSize=12,
        TextColor3=T.TextWhite, BackgroundTransparency=1,
        Size=UDim2.new(1,-60,0,18), Position=UDim2.fromOffset(12,desc and 7 or 10),
        TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5, Parent=card,
    })
    if desc then
        New("TextLabel",{
            Text=desc, Font=Enum.Font.Gotham, TextSize=9,
            TextColor3=T.TextMuted, BackgroundTransparency=1,
            Size=UDim2.new(1,-60,0,12), Position=UDim2.fromOffset(12,27),
            TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5, Parent=card,
        })
    end
    local track=New("Frame",{
        Size=UDim2.fromOffset(36,20),
        Position=UDim2.new(1,-46,0.5,-10),
        BackgroundColor3=val and T.ToggleOn or T.ToggleOff,
        BackgroundTransparency=0, BorderSizePixel=0, ZIndex=5, Parent=card,
    })
    Corner(track, UDim.new(1,0))
    local knob=New("Frame",{
        Size=UDim2.fromOffset(14,14),
        Position=val and UDim2.fromOffset(19,3) or UDim2.fromOffset(3,3),
        BackgroundColor3=Color3.fromRGB(255,255,255),
        BorderSizePixel=0, ZIndex=6, Parent=track,
    })
    Corner(knob, UDim.new(1,0))
    local hit=New("TextButton",{
        Text="", BackgroundTransparency=1,
        Size=UDim2.fromScale(1,1), ZIndex=7, Parent=card,
    })
    hit.MouseButton1Click:Connect(function()
        val=not val
        Tween(track,{BackgroundColor3=val and T.ToggleOn or T.ToggleOff},0.2)
        Tween(knob,{Position=val and UDim2.fromOffset(19,3) or UDim2.fromOffset(3,3)},0.2,Enum.EasingStyle.Back)
        if cb then cb(val) end
    end)
    return card, function() return val end, function(v)
        val=v
        Tween(track,{BackgroundColor3=val and T.ToggleOn or T.ToggleOff},0.2)
        Tween(knob,{Position=val and UDim2.fromOffset(19,3) or UDim2.fromOffset(3,3)},0.2,Enum.EasingStyle.Back)
    end
end

local function Button(label, desc, cb, parent)
    local h = desc and 48 or 36
    local card=New("Frame",{
        Size=UDim2.new(1,0,0,h), BackgroundColor3=T.BtnBg,
        BackgroundTransparency=T.BtnAlpha, BorderSizePixel=0,
        ZIndex=4, Parent=parent or Content,
    })
    Corner(card, T.CR_Btn); Stroke(card, T.GlowBlue, 0.60, 1)
    New("TextLabel",{
        Text=label, Font=Enum.Font.GothamSemibold, TextSize=12,
        TextColor3=T.TextWhite, BackgroundTransparency=1,
        Size=UDim2.new(1,-30,0,18),
        Position=UDim2.fromOffset(12, desc and 7 or 9),
        TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5, Parent=card,
    })
    if desc then
        New("TextLabel",{
            Text=desc, Font=Enum.Font.Gotham, TextSize=9,
            TextColor3=Color3.fromRGB(180,210,255), BackgroundTransparency=1,
            Size=UDim2.new(1,-30,0,12), Position=UDim2.fromOffset(12,27),
            TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5, Parent=card,
        })
    end
    New("TextLabel",{
        Text="›", Font=Enum.Font.GothamBold, TextSize=16,
        TextColor3=Color3.fromRGB(180,210,255), BackgroundTransparency=1,
        Size=UDim2.fromOffset(16,16), Position=UDim2.new(1,-22,0.5,-8),
        TextXAlignment=Enum.TextXAlignment.Center, ZIndex=5, Parent=card,
    })
    local hit=New("TextButton",{
        Text="", BackgroundTransparency=1,
        Size=UDim2.fromScale(1,1), ZIndex=6, Parent=card,
    })
    hit.MouseEnter:Connect(function()
        Tween(card,{BackgroundColor3=T.BtnHover, BackgroundTransparency=0.40},0.15)
    end)
    hit.MouseLeave:Connect(function()
        Tween(card,{BackgroundColor3=T.BtnBg, BackgroundTransparency=T.BtnAlpha},0.15)
    end)
    hit.MouseButton1Click:Connect(function()
        Tween(card,{BackgroundTransparency=0.20},0.07)
        task.delay(0.12,function() Tween(card,{BackgroundTransparency=0.40},0.1) end)
        if cb then cb() end
    end)
    return card
end

local function Paragraph(title, body, parent)
    local card=New("Frame",{
        AutomaticSize=Enum.AutomaticSize.Y,
        Size=UDim2.new(1,0,0,0),
        BackgroundColor3=T.CardBg, BackgroundTransparency=0.45,
        BorderSizePixel=0, ZIndex=4, Parent=parent or Content,
    })
    Corner(card, T.CR_Card); Stroke(card, T.GlowBlue, 0.80, 1)
    Pad(card, 9,9,12,12)
    New("TextLabel",{
        Text=title, Font=Enum.Font.GothamBold, TextSize=11,
        TextColor3=T.TextAccent, BackgroundTransparency=1,
        Size=UDim2.new(1,0,0,15), TextXAlignment=Enum.TextXAlignment.Left,
        ZIndex=5, Parent=card,
    })
    local bodyLbl=New("TextLabel",{
        Text=body, Font=Enum.Font.Gotham, TextSize=10,
        TextColor3=T.TextSub, BackgroundTransparency=1,
        Size=UDim2.new(1,0,0,0), Position=UDim2.fromOffset(0,18),
        AutomaticSize=Enum.AutomaticSize.Y,
        TextXAlignment=Enum.TextXAlignment.Left,
        TextWrapped=true, RichText=true, ZIndex=5, Parent=card,
    })
    return card, function(newTitle, newBody)
        bodyLbl.Text = newBody or ""
    end
end

local function Dropdown(label, options, multi, cb, parent)
    local selected = {}
    local isOpen   = false
    local listH    = math.min(#options*28+8, 160)
    local wrap=New("Frame",{
        Size=UDim2.new(1,0,0,50),
        BackgroundTransparency=1, BorderSizePixel=0, ZIndex=8,
        Parent=parent or Content,
    })
    local hdr=New("Frame",{
        Size=UDim2.new(1,0,0,50),
        BackgroundColor3=T.CardBg, BackgroundTransparency=T.CardAlpha,
        BorderSizePixel=0, ZIndex=9, Parent=wrap,
    })
    Corner(hdr, T.CR_Card); Stroke(hdr, T.GlowBlue, 0.72, 1)
    New("TextLabel",{
        Text=label, Font=Enum.Font.GothamMedium, TextSize=11,
        TextColor3=T.TextSub, BackgroundTransparency=1,
        Size=UDim2.new(1,-40,0,14), Position=UDim2.fromOffset(12,6),
        TextXAlignment=Enum.TextXAlignment.Left, ZIndex=10, Parent=hdr,
    })
    local selLbl=New("TextLabel",{
        Text="Semua rarity", Font=Enum.Font.Gotham, TextSize=11,
        TextColor3=T.TextWhite, BackgroundTransparency=1,
        Size=UDim2.new(1,-40,0,16), Position=UDim2.fromOffset(12,27),
        TextXAlignment=Enum.TextXAlignment.Left,
        TextTruncate=Enum.TextTruncate.AtEnd,
        ZIndex=10, Parent=hdr,
    })
    local arrow=New("TextLabel",{
        Text="⌄", Font=Enum.Font.GothamBold, TextSize=13,
        TextColor3=T.TextAccent, BackgroundTransparency=1,
        Size=UDim2.fromOffset(20,20),
        Position=UDim2.new(1,-26,0.5,-10),
        TextXAlignment=Enum.TextXAlignment.Center,
        ZIndex=10, Parent=hdr,
    })
    local lst=New("ScrollingFrame",{
        Size=UDim2.new(1,0,0,0),
        Position=UDim2.fromOffset(0,52),
        BackgroundColor3=Color3.fromRGB(8,16,48),
        BackgroundTransparency=0.10,
        BorderSizePixel=0, ClipsDescendants=true,
        ScrollBarThickness=2,
        ScrollBarImageColor3=T.GlowBlue,
        CanvasSize=UDim2.fromScale(0,0),
        AutomaticCanvasSize=Enum.AutomaticSize.Y,
        ZIndex=18, Visible=false, Parent=wrap,
    })
    Corner(lst, T.CR_Card); Stroke(lst, T.GlowBlue, 0.65, 1)
    List(lst, 2); Pad(lst,4,4,6,6)
    for _, opt in ipairs(options) do
        local ob=New("TextButton",{
            Text="  "..opt, Font=Enum.Font.Gotham, TextSize=11,
            TextColor3=T.TextWhite,
            BackgroundColor3=Color3.fromRGB(30,65,170),
            BackgroundTransparency=1,
            Size=UDim2.new(1,0,0,26),
            TextXAlignment=Enum.TextXAlignment.Left,
            BorderSizePixel=0, ZIndex=19, Parent=lst,
        })
        Corner(ob, UDim.new(0,5))
        ob.MouseEnter:Connect(function()
            Tween(ob,{BackgroundTransparency=0.55},0.12)
        end)
        ob.MouseLeave:Connect(function()
            Tween(ob,{BackgroundTransparency=selected[opt] and 0.35 or 1},0.12)
        end)
        ob.MouseButton1Click:Connect(function()
            if multi then
                selected[opt]=not selected[opt]
            else
                for k in pairs(selected) do selected[k]=nil end
                selected[opt]=true
            end
            Tween(ob,{BackgroundTransparency=selected[opt] and 0.35 or 1},0.15)
            local s={}
            for k,v in pairs(selected) do if v then table.insert(s,k) end end
            selLbl.Text=#s==0 and "Semua rarity" or table.concat(s,", ")
            if cb then cb(s) end
        end)
    end
    local hb=New("TextButton",{
        Text="", BackgroundTransparency=1,
        Size=UDim2.fromScale(1,1), ZIndex=11, Parent=hdr,
    })
    hb.MouseButton1Click:Connect(function()
        isOpen=not isOpen
        if isOpen then
            lst.Visible=true
            Tween(lst,{Size=UDim2.new(1,0,0,listH)},0.2,Enum.EasingStyle.Back)
            Tween(arrow,{Rotation=180},0.2)
            wrap.Size=UDim2.new(1,0,0,50+listH+4)
        else
            Tween(lst,{Size=UDim2.new(1,0,0,0)},0.15)
            Tween(arrow,{Rotation=0},0.15)
            task.delay(0.16,function() lst.Visible=false end)
            wrap.Size=UDim2.new(1,0,0,50)
        end
    end)
    return wrap
end

-- =====================================================
-- TAB SYSTEM
-- =====================================================
local Tabs      = {}
local ActiveTab = nil

local function CreateTab(name, iconTxt)
    local btn=New("Frame",{
        Size=UDim2.new(1,0,0,TAB_H),
        BackgroundColor3=T.TabActiveBg,
        BackgroundTransparency=1,
        BorderSizePixel=0, ZIndex=4, Parent=TabList,
    })
    Corner(btn, T.CR_Tab)

    local bar=New("Frame",{
        Size=UDim2.fromOffset(3,20),
        Position=UDim2.new(0,-6,0.5,-10),
        BackgroundColor3=T.Indicator,
        BackgroundTransparency=1,
        BorderSizePixel=0, ZIndex=5, Parent=btn,
    })
    Corner(bar, UDim.new(1,0))

    local ico=New("TextLabel",{
        Text=iconTxt or "◆", Font=Enum.Font.GothamBold,
        TextSize=14, TextColor3=T.TextMuted,
        BackgroundTransparency=1,
        Size=UDim2.fromOffset(24,TAB_H),
        Position=UDim2.fromOffset(8,0),
        TextXAlignment=Enum.TextXAlignment.Center,
        ZIndex=5, Parent=btn,
    })
    local lbl=New("TextLabel",{
        Text=name, Font=Enum.Font.GothamSemibold,
        TextSize=11, TextColor3=T.TextMuted,
        BackgroundTransparency=1,
        Size=UDim2.new(1,-38,1,0),
        Position=UDim2.fromOffset(34,0),
        TextXAlignment=Enum.TextXAlignment.Left,
        ZIndex=5, Parent=btn,
    })

    local page=New("Frame",{
        Name="Page_"..name,
        Size=UDim2.new(1,0,0,0),
        AutomaticSize=Enum.AutomaticSize.Y,
        BackgroundTransparency=1,
        BorderSizePixel=0, Visible=false,
        ZIndex=4, Parent=Content,
    })
    List(page, 7)
    Pad(page, 0,4,0,0)

    local tabData={name=name,btn=btn,bar=bar,ico=ico,lbl=lbl,page=page}

    local hit=New("TextButton",{
        Text="", BackgroundTransparency=1,
        Size=UDim2.fromScale(1,1), ZIndex=6, Parent=btn,
    })
    hit.MouseEnter:Connect(function()
        if ActiveTab~=tabData then
            Tween(btn,{BackgroundColor3=T.TabHoverBg, BackgroundTransparency=T.TabHoverAlpha},0.15)
        end
    end)
    hit.MouseLeave:Connect(function()
        if ActiveTab~=tabData then
            Tween(btn,{BackgroundTransparency=1},0.15)
        end
    end)
    hit.MouseButton1Click:Connect(function()
        if ActiveTab==tabData then return end
        if ActiveTab then
            ActiveTab.page.Visible=false
            Tween(ActiveTab.btn,{BackgroundTransparency=1},0.15)
            Tween(ActiveTab.bar,{BackgroundTransparency=1},0.15)
            Tween(ActiveTab.ico,{TextColor3=T.TextMuted},0.15)
            Tween(ActiveTab.lbl,{TextColor3=T.TextMuted},0.15)
        end
        ActiveTab=tabData
        tabData.page.Visible=true
        Tween(btn,{BackgroundColor3=T.TabActiveBg, BackgroundTransparency=T.TabActiveAlpha},0.18)
        Tween(bar,{BackgroundTransparency=0},0.18)
        Tween(ico,{TextColor3=Color3.fromRGB(255,255,255)},0.18)
        Tween(lbl,{TextColor3=Color3.fromRGB(255,255,255)},0.18)
        PanelTitle.Text=name
    end)

    table.insert(Tabs, tabData)
    return page
end

-- =====================================================
-- BUAT TABS
-- =====================================================
local WebhookPage  = CreateTab("Webhook Logger", "🔗")
local SettingsPage = CreateTab("Settings",        "⚙")

-- Aktifkan tab pertama
do
    local f=Tabs[1]
    f.page.Visible=true; ActiveTab=f
    f.btn.BackgroundColor3=T.TabActiveBg
    f.btn.BackgroundTransparency=T.TabActiveAlpha
    f.bar.BackgroundTransparency=0
    f.ico.TextColor3=Color3.fromRGB(255,255,255)
    f.lbl.TextColor3=Color3.fromRGB(255,255,255)
    PanelTitle.Text=f.name
end

-- =====================================================
-- ISI: WEBHOOK LOGGER
-- =====================================================
Section("Rarity Filter", WebhookPage)
Dropdown("Filter by Rarity",
    {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret"},
    true, function(opts)
        -- TODO: Settings.SelectedRarities
    end, WebhookPage)

Section("Setup Webhook", WebhookPage)
local _, UrlBox = Input("Discord Webhook URL",
    "https://discord.com/api/webhooks/...",
    function(txt) end, WebhookPage)

Button("Save Webhook URL", "Validasi & simpan URL webhook", function()
    -- TODO
end, WebhookPage)

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
    "Beta Version • Server-Notifier Fish Catch Logger\n"..
    "Log ikan dari semua player di server\n\n"..
    "<font color='#5aaeff'>by Vechnost • discord.gg/vechnost</font>",
    SettingsPage)

Section("Testing", SettingsPage)
Button("Test Webhook", "Kirim pesan test ke Discord channel", function()
    -- TODO
end, SettingsPage)
Button("Reset Log Counter", "Reset counter dan hapus UUID cache", function()
    -- TODO
end, SettingsPage)

-- =====================================================
-- VISIBILITY SYSTEM
-- =====================================================
local guiVisible = true

local function SetVisible(v)
    guiVisible = v
    if v then
        Screen.Enabled = true
        Window.Size = UDim2.fromOffset(0,0)
        Tween(Window,{Size=UDim2.fromOffset(WIN_W,WIN_H)},0.30,Enum.EasingStyle.Back,Enum.EasingDirection.Out)
    else
        Tween(Window,{Size=UDim2.fromOffset(0,0)},0.20,Enum.EasingStyle.Quad,Enum.EasingDirection.In)
        task.delay(0.22,function() Screen.Enabled=false end)
    end
end

-- X button handler
XBtn.MouseButton1Click:Connect(function()
    SetVisible(false)
end)

-- Keyboard V toggle
UserInputService.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode==Enum.KeyCode.V then
        SetVisible(not guiVisible)
    end
end)

-- =====================================================
-- FLOATING ICON BUTTON (rbx asset kamu)
-- =====================================================
local FloatGui = New("ScreenGui",{
    Name=FLOAT_NAME, ResetOnSpawn=false,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling,
    Parent=CoreGui,
})

local FloatBtn = New("ImageButton",{
    Image=ICON_ASSET,
    Size=UDim2.fromOffset(48,48),
    Position=UDim2.fromScale(0.05,0.5),
    BackgroundColor3=Color3.fromRGB(12,24,65),
    BackgroundTransparency=0.25,
    AutoButtonColor=false,
    BorderSizePixel=0, ZIndex=10,
    Parent=FloatGui,
})
Corner(FloatBtn, UDim.new(1,0))
Stroke(FloatBtn, T.GlowBlue, 0.40, 1.8)

FloatBtn.MouseEnter:Connect(function()
    Tween(FloatBtn,{BackgroundTransparency=0.05},0.15)
end)
FloatBtn.MouseLeave:Connect(function()
    Tween(FloatBtn,{BackgroundTransparency=0.25},0.15)
end)
FloatBtn.MouseButton1Click:Connect(function()
    SetVisible(not guiVisible)
end)

-- Drag FloatBtn
local _fDrag,_fDS,_fSP = false,nil,nil
FloatBtn.InputBegan:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1
    or inp.UserInputType==Enum.UserInputType.Touch then
        _fDrag=true
        _fDS=UserInputService:GetMouseLocation()
        _fSP=FloatBtn.Position
        inp.Changed:Connect(function()
            if inp.UserInputState==Enum.UserInputState.End then _fDrag=false end
        end)
    end
end)
RunService.RenderStepped:Connect(function()
    if not _fDrag then return end
    local m=UserInputService:GetMouseLocation()
    local d=m-_fDS
    local vp=workspace.CurrentCamera.ViewportSize
    local sz=FloatBtn.AbsoluteSize
    FloatBtn.Position=UDim2.fromOffset(
        math.clamp(_fSP.X.Offset+d.X, 0, vp.X-sz.X),
        math.clamp(_fSP.Y.Offset+d.Y, 0, vp.Y-sz.Y)
    )
end)

-- =====================================================
-- OPEN ANIMATION
-- =====================================================
Window.Size=UDim2.fromOffset(0,0)
Tween(Window,{Size=UDim2.fromOffset(WIN_W,WIN_H)},0.32,Enum.EasingStyle.Back,Enum.EasingDirection.Out)

warn("[Vechnost v2.1] GUI loaded! | V = toggle | icon float = toggle | X = tutup")

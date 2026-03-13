-- Craft A World Script v4.0
-- PlayerMovementPackets = click-to-move remote
-- Fire posisi tile → karakter jalan ke sana → server auto break/collect
-- WARNING: Educational purposes only. Use at your own risk.

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hrp       = character:WaitForChild("HumanoidRootPart")

player.CharacterAdded:Connect(function(char)
    character = char
    hrp = char:WaitForChild("HumanoidRootPart")
end)

-- ============================================================
-- REMOTE — click-to-move + break/collect
-- ============================================================
local Remote = nil

local function getRemote()
    if Remote and Remote.Parent then return Remote end
    local ok, r = pcall(function()
        return ReplicatedStorage
            :WaitForChild("Remotes", 5)
            :WaitForChild("PlayerMovementPackets", 5)
            :WaitForChild(player.Name, 5)
    end)
    if ok and r then Remote = r end
    return Remote
end

-- Fire posisi ke server (karakter akan berjalan ke sana)
local function firePos(x, y)
    local r = getRemote()
    if r then
        pcall(function() r:FireServer(Vector2.new(x, y)) end)
    end
end

-- Tunggu sampai karakter dekat posisi target
local function waitUntilNear(targetPos, maxDist, timeout)
    maxDist = maxDist or 8
    timeout = timeout or 5
    local t = 0
    while t < timeout do
        if not hrp then break end
        local dist = (Vector3.new(targetPos.X, targetPos.Y, hrp.Position.Z) - hrp.Position).Magnitude
        if dist <= maxDist then return true end
        task.wait(0.1)
        t = t + 0.1
    end
    return false -- timeout
end

-- ============================================================
-- FOLDER REFERENSI
-- ============================================================
local TilesFolder = Workspace:WaitForChild("Tiles", 10)
local DropsFolder = Workspace:WaitForChild("Drops", 10)
local GemsFolder  = Workspace:FindFirstChild("Gems")

-- ============================================================
-- STATE
-- ============================================================
local state = {
    autoClear   = false,
    autoCollect = false,
    moveDelay   = 0.3,   -- delay setelah fire sebelum pindah ke tile berikutnya
    collectLoop = false,
}

-- ============================================================
-- WINDOW
-- ============================================================
local Window = Fluent:CreateWindow({
    Title       = "Craft A World",
    SubTitle    = "Script v4.0",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(520, 460),
    Acrylic     = true,
    Theme       = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local HomeTab = Window:AddTab({ Title = "Home", Icon = "home" })

HomeTab:AddSection("Info"):AddParagraph({
    Title   = "Script v4.0 ✅",
    Content = "Cara kerja:\n→ Fire posisi tile ke PlayerMovementPackets\n→ Karakter jalan ke sana\n→ Server auto break / collect\n\nMinimize: Right Ctrl"
})

-- ============================================================
-- SECTION: AUTO CLEAR WORLD
-- ============================================================
local ClearSection = HomeTab:AddSection("Auto Clear World")

local StatusPara = ClearSection:AddParagraph({
    Title   = "Status",
    Content = "Idle."
})

ClearSection:AddSlider("MoveDelay", {
    Title       = "Delay per Tile (detik)",
    Description = "Waktu tunggu setelah fire sebelum pindah tile berikutnya",
    Default     = 0.3, Min = 0.1, Max = 3.0, Rounding = 1
}):OnChanged(function(v) state.moveDelay = v end)

local AutoClearToggle = ClearSection:AddToggle("AutoClear", {
    Title       = "Auto Clear World",
    Description = "Karakter otomatis berjalan ke setiap tile dan break",
    Default     = false
})

AutoClearToggle:OnChanged(function(v)
    state.autoClear = v
    if v then
        if not TilesFolder then
            TilesFolder = Workspace:FindFirstChild("Tiles")
        end
        if not TilesFolder then
            Fluent:Notify({Title="❌ Error", Content="Folder Tiles tidak ditemukan!", Duration=4})
            state.autoClear = false
            AutoClearToggle:SetValue(false)
            return
        end
        StatusPara:SetDesc("🔨 Auto Clear AKTIF...")
    else
        StatusPara:SetDesc("Idle.")
    end
    Fluent:Notify({
        Title   = "Auto Clear",
        Content = v and "✅ AKTIF" or "❌ Dimatikan",
        Duration = 2
    })
end)

-- ============================================================
-- SECTION: AUTO COLLECT
-- ============================================================
local CollectSection = HomeTab:AddSection("Auto Collect Floating Items")

CollectSection:AddParagraph({
    Title   = "Info",
    Content = "Fire posisi Drops & Gems → karakter jalan ke sana → server collect."
})

local AutoCollectToggle = CollectSection:AddToggle("AutoCollect", {
    Title       = "Auto Collect Drops & Gems",
    Description = "Karakter jalan ke setiap item drop dan gem",
    Default     = false
})
AutoCollectToggle:OnChanged(function(v)
    state.autoCollect = v
    Fluent:Notify({
        Title   = "Auto Collect",
        Content = v and "✅ AKTIF" or "❌ Dimatikan",
        Duration = 2
    })
end)

-- ============================================================
-- LOOP: Auto Clear
-- Iterate tile satu per satu, fire posisi, tunggu karakter sampai
-- ============================================================
spawn(function()
    while true do
        task.wait(0.1)
        if not state.autoClear then continue end
        if not TilesFolder then
            TilesFolder = Workspace:FindFirstChild("Tiles")
            task.wait(1)
            continue
        end
        if not hrp then continue end

        -- Kumpulkan semua BasePart di Tiles
        local blocks = {}
        for _, obj in ipairs(TilesFolder:GetDescendants()) do
            if (obj:IsA("BasePart") or obj:IsA("MeshPart")) and obj.Parent then
                table.insert(blocks, obj)
            end
        end

        if #blocks == 0 then
            StatusPara:SetDesc("✅ Semua tile sudah di-break!")
            state.autoClear = false
            AutoClearToggle:SetValue(false)
            Fluent:Notify({Title="✅ Selesai", Content="World cleared!", Duration=5})
            continue
        end

        StatusPara:SetDesc("🔨 Sisa ±" .. #blocks .. " tile")

        -- Sort dari yang terdekat dengan karakter
        table.sort(blocks, function(a, b)
            if not a or not b or not hrp then return false end
            return (a.Position - hrp.Position).Magnitude
                 < (b.Position - hrp.Position).Magnitude
        end)

        -- Proses tile satu per satu
        for _, obj in ipairs(blocks) do
            if not state.autoClear then break end
            if not obj or not obj.Parent then continue end
            if not hrp then continue end

            local pos = obj.Position

            -- Fire posisi tile → karakter jalan ke sana
            firePos(pos.X, pos.Y)

            -- Tunggu karakter sampai di dekat tile
            -- (atau timeout setelah state.moveDelay detik)
            local arrived = waitUntilNear(
                Vector2.new(pos.X, pos.Y),
                10,             -- jarak dianggap "sampai" (stud)
                state.moveDelay -- timeout
            )

            -- Fire sekali lagi saat sudah dekat untuk memastikan break
            if arrived then
                firePos(pos.X, pos.Y)
                task.wait(0.05)
            end

            task.wait(0.05) -- jeda kecil antar tile
        end
    end
end)

-- ============================================================
-- LOOP: Auto Collect
-- ============================================================
spawn(function()
    while true do
        task.wait(0.15)
        if not state.autoCollect then continue end
        if not hrp then continue end

        if not DropsFolder then DropsFolder = Workspace:FindFirstChild("Drops") end
        if not GemsFolder  then GemsFolder  = Workspace:FindFirstChild("Gems")  end

        -- Kumpulkan semua target dari Drops dan Gems
        local targets = {}

        local function addFromFolder(folder)
            if not folder then return end
            for _, obj in ipairs(folder:GetDescendants()) do
                local pos = nil
                if obj:IsA("BasePart") then
                    pos = obj.Position
                elseif obj:IsA("Model") and obj.PrimaryPart then
                    pos = obj.PrimaryPart.Position
                end
                if pos then
                    table.insert(targets, pos)
                end
            end
        end

        addFromFolder(DropsFolder)
        addFromFolder(GemsFolder)

        if #targets == 0 then continue end

        -- Sort dari yang terdekat
        table.sort(targets, function(a, b)
            if not hrp then return false end
            return (a - hrp.Position).Magnitude < (b - hrp.Position).Magnitude
        end)

        -- Ambil yang terdekat dulu
        local nearest = targets[1]
        if nearest then
            -- Fire posisi item → karakter jalan ke sana → server collect
            firePos(nearest.X, nearest.Y)
            -- Tunggu karakter sampai
            waitUntilNear(Vector2.new(nearest.X, nearest.Y), 5, 3)
            -- Fire lagi untuk confirm collect
            firePos(nearest.X, nearest.Y)
            task.wait(0.1)
        end
    end
end)

-- ============================================================
-- STARTUP
-- ============================================================
Window:SelectTab(1)

spawn(function()
    task.wait(2)
    local r = getRemote()
    Fluent:Notify({
        Title   = r and "✅ Remote OK" or "⚠️ Remote Tidak Ditemukan",
        Content = r
            and "PlayerMovementPackets/" .. player.Name .. " terhubung!"
            or  "Pastikan sudah masuk ke world dulu!",
        Duration = 4
    })
end)

Fluent:Notify({
    Title    = "Craft A World v4.0",
    Content  = "Loaded! Masuk world dulu.",
    Duration = 3
})

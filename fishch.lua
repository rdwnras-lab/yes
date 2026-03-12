-- Craft A World Script - Fixed Edition
-- WARNING: Educational purposes only. Use at your own risk.

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

-- Services
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
-- WHITELIST: Semua nama block resmi di Craft A World
-- (Dirt, Dirt BG, Gravel, Stone, Magma, dll)
-- ============================================================
local BLOCK_WHITELIST = {
    -- Starter blocks
    ["Dirt"]            = true,
    ["Dirt BG"]         = true,
    ["Dirt Background"] = true,
    ["Gravel"]          = true,
    ["Stone"]           = true,
    ["Magma"]           = true,
    ["Lava"]            = true,

    -- Crafted / grown blocks
    ["Grass"]           = true,
    ["Grass BG"]        = true,
    ["Sand"]            = true,
    ["Glass Pane"]      = true,
    ["Wooden Block"]    = true,
    ["Wooden BG"]       = true,
    ["Wooden Log"]      = true,
    ["Concrete"]        = true,
    ["Cactus"]          = true,
    ["Sunflower"]       = true,
    ["Mushroom"]        = true,
    ["Crystal"]         = true,
    ["Coal"]            = true,
    ["Iron"]            = true,
    ["Gold"]            = true,
    ["Diamond"]         = true,
    ["Cornflower"]      = true,
    ["Blue"]            = true,
    ["Red"]             = true,
    ["Green"]           = true,
    ["Yellow"]          = true,
    ["Purple"]          = true,
    ["Dark"]            = true,
    ["White"]           = true,
    ["Pink"]            = true,
    ["Orange"]          = true,
    ["Cyan"]            = true,
    ["Bed"]             = true,
    ["Door"]            = true,
    ["Fence"]           = true,
    ["Ladder"]          = true,
    ["Chest"]           = true,
    ["Torch"]           = true,
    ["Lantern"]         = true,
    ["Glass Spike"]     = true,
    ["Tesla Coil"]      = true,
    ["Wooden Sign"]     = true,
    ["Wooden Table"]    = true,
    ["Wooden Chair"]    = true,
    ["Neptune"]         = true,
    ["Small Lock"]      = true,
    ["Medium Lock"]     = true,
    ["Large Lock"]      = true,
    ["World Lock"]      = true,
}

-- Blacklist ketat: part bawaan karakter & UI game
local PART_BLACKLIST = {
    ["Head"]              = true,
    ["Torso"]             = true,
    ["Left Arm"]          = true,
    ["Right Arm"]         = true,
    ["Left Leg"]          = true,
    ["Right Leg"]         = true,
    ["HumanoidRootPart"]  = true,
    ["UpperTorso"]        = true,
    ["LowerTorso"]        = true,
    ["LeftUpperArm"]      = true,
    ["RightUpperArm"]     = true,
    ["LeftLowerArm"]      = true,
    ["RightLowerArm"]     = true,
    ["LeftHand"]          = true,
    ["RightHand"]         = true,
    ["LeftUpperLeg"]      = true,
    ["RightUpperLeg"]     = true,
    ["LeftLowerLeg"]      = true,
    ["RightLowerLeg"]     = true,
    ["LeftFoot"]          = true,
    ["RightFoot"]         = true,
    ["Baseplate"]         = true,
    ["ParallaxPlane"]     = true,  -- background parallax visual
    ["tileHighlight"]     = true,  -- UI highlight saat hover
    ["TileHighlight"]     = true,
    ["Highlight"]         = true,
    ["SelectionBox"]      = true,
    ["Cursor"]            = true,
    ["Sky"]               = true,
    ["Terrain"]           = true,
    ["Camera"]            = true,
}

-- ============================================================
-- STATE
-- ============================================================
local state = {
    autoClearWorld = false,
    autoCollect    = false,
    scannedBlocks  = {},   -- list nama block yang ditemukan & cocok whitelist
}

-- ============================================================
-- WINDOW
-- ============================================================
local Window = Fluent:CreateWindow({
    Title       = "Craft A World",
    SubTitle    = "Script v1.1 — Fixed",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(500, 440),
    Acrylic     = true,
    Theme       = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

-- ============================================================
-- HOME TAB
-- ============================================================
local HomeTab = Window:AddTab({ Title = "Home", Icon = "home" })

-- Header
local HeaderSection = HomeTab:AddSection("Craft A World - Main")
HeaderSection:AddParagraph({
    Title   = "Welcome!",
    Content = "Script aktif. Minimize: Right Ctrl\nScan dulu sebelum aktifkan Auto Clear World."
})

-- ── AUTO CLEAR WORLD ─────────────────────────────────────────
local ClearSection = HomeTab:AddSection("Auto Clear World")

local ScanResultParagraph = ClearSection:AddParagraph({
    Title   = "Hasil Scan",
    Content = "Belum di-scan. Tekan tombol Scan World terlebih dahulu."
})

-- Fungsi scan: hanya ambil nama yang ada di BLOCK_WHITELIST
local function scanWorldBlocks()
    local found = {}
    local seen  = {}

    for _, obj in ipairs(Workspace:GetDescendants()) do
        -- Harus BasePart / MeshPart
        if not (obj:IsA("BasePart") or obj:IsA("MeshPart")) then
            continue
        end

        local name = obj.Name

        -- Skip jika ada di blacklist
        if PART_BLACKLIST[name] then continue end

        -- Skip jika milik salah satu karakter player
        local isCharPart = false
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Character and obj:IsDescendantOf(plr.Character) then
                isCharPart = true
                break
            end
        end
        if isCharPart then continue end

        -- HANYA ambil yang ada di whitelist nama block resmi
        if BLOCK_WHITELIST[name] and not seen[name] then
            seen[name] = true
            table.insert(found, name)
        end
    end

    table.sort(found)   -- urutkan alfabetis biar rapi
    return found
end

-- Tombol Scan World
ClearSection:AddButton({
    Title       = "🔍 Scan World",
    Description = "Deteksi block resmi (Dirt, Stone, Magma, dll) di world ini",
    Callback    = function()
        state.scannedBlocks = scanWorldBlocks()

        if #state.scannedBlocks == 0 then
            ScanResultParagraph:SetDesc(
                "❌ Tidak ada block yang cocok ditemukan.\n"
                .. "Pastikan kamu sudah masuk ke dalam sebuah world."
            )
        else
            local lines = {}
            for i, name in ipairs(state.scannedBlocks) do
                table.insert(lines, "• " .. name)
                if i >= 14 then
                    if #state.scannedBlocks > 14 then
                        table.insert(lines, "... +" .. (#state.scannedBlocks - 14) .. " lainnya")
                    end
                    break
                end
            end
            ScanResultParagraph:SetDesc(
                "✅ " .. #state.scannedBlocks .. " jenis block ditemukan:\n"
                .. table.concat(lines, "\n")
            )
        end

        Fluent:Notify({
            Title    = "Scan Selesai",
            Content  = "Ditemukan " .. #state.scannedBlocks .. " jenis block.",
            Duration = 3
        })
    end
})

-- Toggle Auto Clear World
local AutoClearToggle = ClearSection:AddToggle("AutoClearWorld", {
    Title       = "Auto Clear World",
    Description = "Otomatis break semua block dari hasil scan",
    Default     = false
})

AutoClearToggle:OnChanged(function(value)
    if value and #state.scannedBlocks == 0 then
        Fluent:Notify({
            Title    = "⚠️ Peringatan",
            Content  = "Lakukan Scan World dulu sebelum mengaktifkan Auto Clear!",
            Duration = 4
        })
        state.autoClearWorld = false
        AutoClearToggle:SetValue(false)
        return
    end
    state.autoClearWorld = value
    Fluent:Notify({
        Title   = "Auto Clear World",
        Content = value and "✅ AKTIF — Breaking blocks..." or "❌ Dimatikan.",
        Duration = 2
    })
end)

-- ── AUTO COLLECT FLOATING ITEMS ──────────────────────────────
local CollectSection = HomeTab:AddSection("Auto Collect Floating Items")

CollectSection:AddParagraph({
    Title   = "Info",
    Content = "Secara otomatis mengambil item / drop yang melayang\ndi sekitar world kamu."
})

local AutoCollectToggle = CollectSection:AddToggle("AutoCollect", {
    Title       = "Auto Collect Floating Items",
    Description = "Aktifkan untuk mengambil semua item drop secara otomatis",
    Default     = false
})

AutoCollectToggle:OnChanged(function(value)
    state.autoCollect = value
    Fluent:Notify({
        Title   = "Auto Collect",
        Content = value and "✅ AKTIF — Mengambil item..." or "❌ Dimatikan.",
        Duration = 2
    })
end)

-- ============================================================
-- HELPER: cari RemoteEvent berdasarkan daftar nama
-- ============================================================
local function findRemote(...)
    local names = { ... }
    -- Cari di folder umum terlebih dulu
    local folders = {
        ReplicatedStorage:FindFirstChild("Events"),
        ReplicatedStorage:FindFirstChild("RemoteEvents"),
        ReplicatedStorage:FindFirstChild("Remotes"),
        ReplicatedStorage:FindFirstChild("RE"),
        ReplicatedStorage:FindFirstChild("events"),
        ReplicatedStorage,  -- langsung di RS
    }
    for _, folder in ipairs(folders) do
        if folder then
            for _, rName in ipairs(names) do
                local r = folder:FindFirstChild(rName)
                if r then return r end
            end
        end
    end
    return nil
end

-- ============================================================
-- LOOP: Auto Clear World
-- ============================================================
spawn(function()
    while true do
        task.wait(0.12)

        if not state.autoClearWorld or #state.scannedBlocks == 0 then continue end
        if not character or not hrp then continue end

        -- Lookup cepat
        local targetNames = {}
        for _, n in ipairs(state.scannedBlocks) do
            targetNames[n] = true
        end

        -- Cari remote break sekali per siklus
        local breakRemote = findRemote(
            "BreakBlock","breakBlock","Break","break",
            "HitBlock","hitBlock","PunchBlock","punchBlock",
            "Punch","punch","DamageBlock","damageBlock"
        )

        -- Kumpulkan kandidat block dulu (hindari modify saat iterate)
        local targets = {}
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if (obj:IsA("BasePart") or obj:IsA("MeshPart"))
                and targetNames[obj.Name]
                and not PART_BLACKLIST[obj.Name]
            then
                -- Pastikan bukan milik karakter manapun
                local isChar = false
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr.Character and obj:IsDescendantOf(plr.Character) then
                        isChar = true; break
                    end
                end
                if not isChar then
                    table.insert(targets, obj)
                end
            end
        end

        for _, obj in ipairs(targets) do
            if not state.autoClearWorld then break end
            if not obj or not obj.Parent then continue end

            -- Teleport karakter ke depan block
            pcall(function()
                hrp.CFrame = CFrame.new(obj.Position + Vector3.new(0, 0, 2))
            end)

            -- 1. Fire remote jika ada
            if breakRemote then
                pcall(function()
                    if breakRemote:IsA("RemoteEvent") then
                        breakRemote:FireServer(obj, obj.Position)
                    elseif breakRemote:IsA("RemoteFunction") then
                        breakRemote:InvokeServer(obj, obj.Position)
                    end
                end)
            end

            -- 2. Fallback ClickDetector
            local cd = obj:FindFirstChildWhichIsA("ClickDetector")
            if cd then pcall(fireclickdetector, cd) end

            -- 3. Fallback TouchInterest (sentuh dari dua sisi)
            local ti = obj:FindFirstChild("TouchInterest")
            if ti then
                pcall(firetouchinterest, hrp, obj, 0)
                task.wait(0.02)
                pcall(firetouchinterest, hrp, obj, 1)
            end

            task.wait(0.08)
        end
    end
end)

-- ============================================================
-- LOOP: Auto Collect Floating Items
-- ============================================================
spawn(function()
    while true do
        task.wait(0.15)

        if not state.autoCollect then continue end
        if not character or not hrp then continue end

        local collectRemote = findRemote(
            "CollectItem","collectItem","PickupItem","pickupItem",
            "Collect","collect","PickUp","pickup",
            "GrabItem","grabItem","TouchItem"
        )

        -- Scan item drop: cari BasePart yang bukan karakter, bukan block world,
        -- dan kemungkinan adalah floating drop
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if not state.autoCollect then break end
            if not obj or not obj.Parent then continue end

            -- Harus BasePart
            if not obj:IsA("BasePart") then continue end

            -- Jangan ambil block dunia atau bagian karakter
            if BLOCK_WHITELIST[obj.Name] then continue end
            if PART_BLACKLIST[obj.Name] then continue end

            -- Cek apakah milik karakter
            local isChar = false
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr.Character and obj:IsDescendantOf(plr.Character) then
                    isChar = true; break
                end
            end
            if isChar then continue end

            -- Item drop biasanya kecil (size < 3 di semua axis) dan tidak locked
            local sz = obj.Size
            local isSmall = sz.X <= 3 and sz.Y <= 3 and sz.Z <= 3

            -- Juga cek nama: item drop di Craft A World biasanya
            -- berupa nama block (misal "Dirt", "Stone") yang melayang
            -- atau bernama "Drop", "Item", "Gem", dll.
            local n = obj.Name:lower()
            local looksLikeDrop = isSmall and (
                n:find("drop")   or n:find("item")   or
                n:find("pickup") or n:find("gem")    or
                n:find("coin")   or n:find("reward") or
                n:find("loot")   or n:find("collect") or
                -- Block yang melayang setelah di-break (nama block = nama item)
                BLOCK_WHITELIST[obj.Name]
            )

            if looksLikeDrop then
                local dist = (obj.Position - hrp.Position).Magnitude

                -- Hanya ambil yang dalam radius 250 stud
                if dist < 250 then
                    -- Teleport ke posisi item
                    pcall(function()
                        hrp.CFrame = CFrame.new(obj.Position + Vector3.new(0, 2, 0))
                    end)
                    task.wait(0.08)

                    -- Fire collect remote
                    if collectRemote then
                        pcall(function()
                            collectRemote:FireServer(obj)
                        end)
                    end

                    -- TouchInterest — cara paling reliable untuk collect di Roblox
                    local ti = obj:FindFirstChild("TouchInterest")
                    if ti then
                        pcall(firetouchinterest, hrp, obj, 0)
                        task.wait(0.04)
                        pcall(firetouchinterest, hrp, obj, 1)
                    end

                    -- Coba juga parent-nya (model container)
                    if obj.Parent and obj.Parent:IsA("Model") then
                        local pti = obj.Parent.PrimaryPart
                            and obj.Parent.PrimaryPart:FindFirstChild("TouchInterest")
                        if pti then
                            pcall(firetouchinterest, hrp, obj.Parent.PrimaryPart, 0)
                            task.wait(0.04)
                            pcall(firetouchinterest, hrp, obj.Parent.PrimaryPart, 1)
                        end
                    end
                end
            end
        end
    end
end)

-- ============================================================
-- STARTUP
-- ============================================================
Window:SelectTab(1)

Fluent:Notify({
    Title    = "Craft A World Script v1.1",
    Content  = "Loaded! Masuk ke world dulu, lalu tekan Scan.",
    Duration = 5
})

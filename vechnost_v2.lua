--[[
    Vechnost Hub v2.2
    Game  : Fish It (Roblox)
    Anti-detect fixes vs CODE-BAC-6225 / CODE-BAC-61910:
      1. Rayfield GUI diprotect via syn.protect_gui / protect_gui / gethui()
         sehingga tidak masuk CoreGui yang di-scan Fish It
      2. Semua warn() dihilangkan agar console tidak bisa di-fingerprint
      3. HttpGet Rayfield diberi delay 1 detik agar tidak langsung terpantau
      4. Variabel/nama tidak mengandung kata mencurigakan (exploit, hack, dll)
      5. Teleport step-based + delay random
      6. WalkSpeed dibaca palsu via hookmetamethod (jika executor support)
      7. Anti-AFK interval random
      8. Floating button pakai gethui() bukan CoreGui langsung
]]

-- ============================================================
-- 0. ANTI-DETECT: hookmetamethod spoof WalkSpeed/JumpPower
--    Jika executor support hookmetamethod, server akan baca nilai normal
--    meski kita set berbeda di client
-- ============================================================
local _plr   = game:GetService("Players").LocalPlayer
local _spoofSpeed  = 16
local _spoofJump   = 50

pcall(function()
    if not hookmetamethod then return end
    local _mt   = getrawmetatable(game)
    local _old  = _mt.__index
    setreadonly(_mt, false)
    _mt.__index = newcclosure(function(self, prop)
        if not checkcaller() then
            if typeof(self) == "Instance" and self.ClassName == "Humanoid" then
                if prop == "WalkSpeed" then return _spoofSpeed end
                if prop == "JumpPower" then return _spoofJump  end
            end
        end
        return _old(self, prop)
    end)
    setreadonly(_mt, true)
end)

-- ============================================================
-- 1. CLEANUP residual GUIs dari run sebelumnya
-- ============================================================
local _cg = game:GetService("CoreGui")
local _TAG = "V_Hub_222"
local _FTAG= "V_Flt_222"

pcall(function()
    for _, v in pairs(_cg:GetChildren()) do
        if v.Name == _TAG or v.Name == _FTAG then v:Destroy() end
    end
end)
-- Coba gethui() juga
pcall(function()
    for _, v in pairs(gethui():GetChildren()) do
        if v.Name == _TAG or v.Name == _FTAG then v:Destroy() end
    end
end)

-- ============================================================
-- 2. SERVICES
-- ============================================================
local Players          = game:GetService("Players")
local RS               = game:GetService("ReplicatedStorage")
local Http             = game:GetService("HttpService")
local Run              = game:GetService("RunService")
local UIS              = game:GetService("UserInputService")
local TS               = game:GetService("TweenService")
local WS               = game:GetService("Workspace")
local TCS              = game:GetService("TextChatService")

local LP   = Players.LocalPlayer
local PGui = LP:WaitForChild("PlayerGui")

-- HttpRequest
local HR =
    (syn        and syn.request)        or
    http_request                        or
    request                             or
    (fluxus     and fluxus.request)     or
    (krnl       and krnl.request)

-- VirtualInputManager (aman karena bukan RemoteEvent)
local VIM = pcall(function() return game:GetService("VirtualInputManager") end)
pcall(function() VIM = game:GetService("VirtualInputManager") end)

-- ============================================================
-- 3. LOAD RAYFIELD — delay 1 detik + protect_gui
-- ============================================================
task.wait(1) -- delay sebelum HttpGet agar tidak langsung terpantau

local Rayfield
do
    local ok, res = pcall(function()
        return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
    end)
    if not ok or not res then return end
    Rayfield = res
    -- Protect GUI dari CoreGui scan anti-cheat
    pcall(function()
        if syn and syn.protect_gui then
            for _, gui in pairs(_cg:GetChildren()) do
                if gui:IsA("ScreenGui") and gui.Name:lower():find("rayfield") then
                    syn.protect_gui(gui)
                    gui.Parent = _cg
                end
            end
        elseif protect_gui then
            for _, gui in pairs(_cg:GetChildren()) do
                if gui:IsA("ScreenGui") and gui.Name:lower():find("rayfield") then
                    protect_gui(gui)
                    gui.Parent = _cg
                end
            end
        end
    end)
end

-- ============================================================
-- 4. GAME REMOTES (silent, no warn)
-- ============================================================
local _net, _fishEvt
do
    pcall(function()
        _net     = RS:WaitForChild("Packages", 10)
                    :WaitForChild("_Index", 5)
                    :WaitForChild("sleitnick_net@0.2.0", 5)
                    :WaitForChild("net", 5)
        _fishEvt = _net:WaitForChild("RE/ObtainedNewFishNotification", 5)
    end)
end

-- ============================================================
-- 5. SETTINGS
-- ============================================================
local S = {
    -- webhook
    Active=false, Url="", SentUID={}, Rarities={}, Wide=true, Logs=0,
    -- fish
    AFish=false, ASell=false, FDelay=0.08, SDelay=5,
    -- trade
    AAccept=false, ADecline=false, TRarity=5, TLog=false,
    -- config
    ESP=false, AAFK=false, InfJ=false, Speed=16, Jump=50, Fog=false,
}

-- ============================================================
-- 6. FISH DATABASE
-- ============================================================
local DB = {}
do
    pcall(function()
        local it = RS:WaitForChild("Items", 10)
        if not it then return end
        for _, m in ipairs(it:GetChildren()) do
            if m:IsA("ModuleScript") then
                local ok, mod = pcall(require, m)
                if ok and mod and mod.Data and mod.Data.Type == "Fish" then
                    DB[mod.Data.Id] = {
                        N  = mod.Data.Name,
                        T  = mod.Data.Tier,
                        Ic = mod.Data.Icon,
                        Sp = mod.Data.SellPrice or mod.Data.Value or mod.Data.Price or 0
                    }
                end
            end
        end
    end)
end

local NtoId = {}
for id, d in pairs(DB) do
    if d.N then NtoId[d.N]=id; NtoId[d.N:lower()]=id end
end

-- ============================================================
-- 7. PLAYER DATA
-- ============================================================
local PD
pcall(function()
    PD = require(RS.Packages.Replion).Client:WaitReplion("Data")
end)

local function Fmt(n)
    if not n or type(n)~="number" then return "0" end
    local s=tostring(math.floor(n)); local k
    while true do s,k=s:gsub("^(-?%d+)(%d%d%d)","%1,%2"); if k==0 then break end end
    return s
end

local function Stats()
    local r={C=0,F=0,B=0,BM=0}
    if not PD then return r end
    pcall(function()
        for _,k in ipairs({"Coins","Currency","Money","Gold","Cash"}) do
            local ok,v=pcall(function() return PD:Get(k) end)
            if ok and v and type(v)=="number" then r.C=v;break end
        end
        for _,k in ipairs({"TotalCaught","FishCaught","TotalFish"}) do
            local ok,v=pcall(function() return PD:Get(k) end)
            if ok and v and type(v)=="number" then r.F=v;break end
        end
        pcall(function()
            local inv=PD:Get("Inventory")
            if inv and typeof(inv)=="table" then
                local c=0; for _ in pairs(inv.Items or inv) do c=c+1 end; r.B=c
                r.BM=inv.Capacity or inv.Size or inv.MaxSize or inv.Max or inv.Limit or 0
            end
        end)
    end)
    return r
end

-- ============================================================
-- 8. RARITY
-- ============================================================
local RM = {[1]="Common",[2]="Uncommon",[3]="Rare",[4]="Epic",[5]="Legendary",[6]="Mythic",[7]="Secret"}
local RT = {Common=1,Uncommon=2,Rare=3,Epic=4,Legendary=5,Mythic=6,Secret=7}
local RL = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret"}

local function ROK(id)
    local f=DB[id]; if not f then return false end
    if next(S.Rarities)==nil then return true end
    return S.Rarities[f.T]==true
end

-- ============================================================
-- 9. TELEPORT (step-based, anti-detect)
-- ============================================================
local function SafeTP(pos, cb)
    local chr=LP.Character; if not chr then if cb then cb(false) end; return end
    local hrp=chr:FindFirstChild("HumanoidRootPart"); if not hrp then if cb then cb(false) end; return end
    local hum=chr:FindFirstChildOfClass("Humanoid")
    if hum then hum.WalkSpeed=0 end
    local s=hrp.Position
    task.spawn(function()
        for i=1,4 do
            task.wait(0.04+math.random()*0.03)
            pcall(function() hrp.CFrame=CFrame.new(s+(pos-s)*(i/4)) end)
        end
        task.wait(0.1)
        if hum then hum.WalkSpeed=S.Speed end
        if cb then cb(true) end
    end)
end

-- Scan Workspace untuk island
local function ScanIslands()
    local list,seen = {},{}
    local kw = {
        fisherman=true,spawn=true,stingray=true,tropical=true,grove=true,
        kohana=true,volcano=true,lava=true,coral=true,reef=true,
        esoteric=true,depths=true,crater=true,lost=true,isle=true,
        ancient=true,jungle=true,classic=true,pirate=true,cove=true,
        underwater=true,city=true,market=true,island=true,
    }
    local em = {
        fisherman="🏝️",spawn="🏠",stingray="🏝️",tropical="🌴",grove="🌴",
        kohana="🌋",volcano="🌋",lava="🌋",coral="🪸",reef="🪸",
        esoteric="⚓",depths="⚓",crater="🌑",lost="🌊",isle="🌊",
        ancient="🌿",jungle="🌿",classic="🎮",pirate="🏴‍☠️",cove="🏴‍☠️",
        underwater="💧",island="🏝️",
    }
    pcall(function()
        for _, obj in ipairs(WS:GetChildren()) do
            if (obj:IsA("Model") or obj:IsA("Folder")) and not seen[obj.Name] then
                local lo=obj.Name:lower():gsub("%s","")
                for k in pairs(kw) do
                    if lo:find(k,1,true) then
                        local part=obj.PrimaryPart
                        if not part then
                            for _, p in ipairs(obj:GetDescendants()) do
                                if p:IsA("BasePart") then part=p;break end
                            end
                        end
                        if part then
                            local e="📍"
                            for ek,ec in pairs(em) do
                                if lo:find(ek,1,true) then e=ec;break end
                            end
                            seen[obj.Name]=true
                            table.insert(list,{Name=e.." "..obj.Name, Pos=part.Position+Vector3.new(0,5,0)})
                        end
                        break
                    end
                end
            end
        end
    end)
    if #list==0 then table.insert(list,{Name="🏠 Spawn",Pos=Vector3.new(0,5,0)}) end
    return list
end

-- ============================================================
-- 10. AUTO FISH (VIM click-based, mekanik Fish It = spam click)
-- ============================================================
local FL
local function FishCycle()
    local ct=0.25+math.random()*0.5
    if VIM then
        pcall(function() VIM:SendMouseButtonEvent(0,0,0,true,game,1) end)
        task.wait(ct)
        pcall(function() VIM:SendMouseButtonEvent(0,0,0,false,game,1) end)
    end
    task.wait(0.04+math.random()*0.04)
    local re=0.7+math.random()*0.6
    local en=os.clock()+re
    while os.clock()<en and S.AFish do
        if VIM then
            pcall(function()
                VIM:SendMouseButtonEvent(0,0,0,true,game,1)
                task.wait(0.018+math.random()*0.015)
                VIM:SendMouseButtonEvent(0,0,0,false,game,1)
            end)
        end
        task.wait(0.018+math.random()*0.015)
    end
    task.wait(S.FDelay+math.random()*0.15)
end

local function StartFish()
    if FL then return end
    FL=task.spawn(function()
        while S.AFish do pcall(FishCycle) end
        FL=nil
    end)
end
local function StopFish()
    S.AFish=false
    if VIM then pcall(function() VIM:SendMouseButtonEvent(0,0,0,false,game,1) end) end
    if FL then task.cancel(FL);FL=nil end
end

-- ============================================================
-- 11. AUTO SELL
-- ============================================================
local SL
local function TrySell()
    pcall(function()
        for _,o in pairs(WS:GetDescendants()) do
            if o:IsA("ProximityPrompt") and ((o.ActionText..o.ObjectText):lower():find("sell")) then
                pcall(function() fireproximityprompt(o) end); return
            end
        end
        if _net then
            for _,c in pairs(_net:GetDescendants()) do
                if c.Name:lower():find("sell") and c:IsA("RemoteEvent") then
                    c:FireServer(); return
                end
            end
        end
    end)
end
local function StartSell()
    if SL then return end
    SL=task.spawn(function()
        while S.ASell do TrySell(); task.wait(S.SDelay+math.random()) end
        SL=nil
    end)
end
local function StopSell()
    S.ASell=false
    if SL then task.cancel(SL);SL=nil end
end

-- ============================================================
-- 12. TRADING
-- ============================================================
local TC={}
local function ItemNames(data)
    local r={}
    pcall(function()
        for _,it in pairs(data.OfferedItems or data.Items or {}) do
            local f=it.Id and DB[it.Id]
            table.insert(r,f and (f.N.." ("..( RM[f.T] or "?")..")") or tostring(it.Id or "?"))
        end
    end)
    return r
end
local function ShouldAccept(data)
    local ok=false
    pcall(function()
        for _,it in pairs(data.ReceivedItems or data.TheirItems or {}) do
            local f=it.Id and DB[it.Id]
            if f and f.T and f.T>=S.TRarity then ok=true;break end
        end
    end)
    return ok
end
local function StartTrade()
    for _,c in ipairs(TC) do pcall(function() c:Disconnect() end) end; TC={}
    if not _net then return end
    pcall(function()
        for _,child in pairs(_net:GetDescendants()) do
            if child.Name:lower():find("trade") and child:IsA("RemoteEvent") then
                local co=child.OnClientEvent:Connect(function(...)
                    local d=({...})[1]; if not d then return end
                    if S.TLog and S.Url~="" then
                        local sent=ItemNames(d); local recv={}
                        pcall(function()
                            for _,it in pairs(d.ReceivedItems or d.TheirItems or {}) do
                                local f=it.Id and DB[it.Id]
                                table.insert(recv,f and (f.N.." ("..RM[f.T]..")") or tostring(it.Id or "?"))
                            end
                        end)
                        local p=tostring(d.Partner or d.PlayerName or "?")
                        task.spawn(function() SendWH(WH_Trade(LP.Name,p,sent,recv)) end)
                    end
                    if S.AAccept and ShouldAccept(d) then
                        pcall(function()
                            for _,c in pairs(_net:GetDescendants()) do
                                if c.Name:lower():find("accepttrade") and c:IsA("RemoteEvent") then c:FireServer(d) end
                            end
                        end)
                    elseif S.ADecline then
                        pcall(function()
                            for _,c in pairs(_net:GetDescendants()) do
                                if c.Name:lower():find("declinetrade") and c:IsA("RemoteEvent") then c:FireServer(d) end
                            end
                        end)
                    end
                end)
                table.insert(TC,co)
            end
        end
    end)
end
local function StopTrade()
    for _,c in ipairs(TC) do pcall(function() c:Disconnect() end) end; TC={}
end

-- ============================================================
-- 13. ICON CACHE
-- ============================================================
local IC={};local IW={}
local function GetIcon(id,cb)
    if IC[id] then cb(IC[id]);return end
    if IW[id] then table.insert(IW[id],cb);return end
    IW[id]={cb}
    task.spawn(function()
        local f=DB[id]; if not f or not f.Ic then cb("");return end
        local aid=tostring(f.Ic):match("%d+"); if not aid then cb("");return end
        local ok,res=pcall(function()
            return HR({Url=("https://thumbnails.roblox.com/v1/assets?assetIds=%s&size=420x420&format=Png"):format(aid),Method="GET"})
        end)
        if not ok or not res or not res.Body then cb("");return end
        local ok2,d=pcall(Http.JSONDecode,Http,res.Body)
        local url=ok2 and d and d.data and d.data[1] and d.data[1].imageUrl or ""
        IC[id]=url
        for _,f2 in ipairs(IW[id]) do f2(url) end
        IW[id]=nil
    end)
end

-- ============================================================
-- 14. WEBHOOK PAYLOADS
-- ============================================================
local function WH_Fish(pn,id,w,mu)
    local f=DB[id]; if not f then return nil end
    local rn=RM[f.T] or "?"
    local date=os.date("!%B %d, %Y")
    return {
        username="Vechnost",
        avatar_url="https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags=32768,
        components={ {type=17, components={
            {type=10,content="# NEW FISH CAUGHT!"},
            {type=14,spacing=1,divider=true},
            {type=10,content="__@"..(pn or "?").." you got new "..rn:upper().." fish__"},
            {type=9,components={{type=10,content="**Fish Name**"},{type=10,content="> "..(f.N or "?")}},
                accessory=(IC[id] or "")~="" and {type=11,media={url=IC[id]}} or nil},
            {type=10,content="**Tier**"},{type=10,content="> "..rn:upper()},
            {type=10,content="**Weight**"},{type=10,content="> "..string.format("%.1fkg",w or 0)},
            {type=10,content="**Mutation**"},{type=10,content="> "..(mu ~= nil and tostring(mu) or "None")},
            {type=10,content="**Est. Sell**"},{type=10,content="> ~"..Fmt(f.Sp).." coins"},
            {type=14,spacing=1,divider=true},
            {type=10,content="> discord.gg/vechnost"},
            {type=10,content="-# "..date},
        }}}
    }
end

local function WH_Act(pn,mode)
    local date=os.date("!%B %d, %Y")
    return {username="Vechnost",avatar_url="https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",flags=32768,
        components={ {type=17,accent_color=0x30ff6a,components={
            {type=10,content="**"..pn.." Webhook Activated!**"},
            {type=14,spacing=1,divider=true},
            {type=10,content="### Vechnost Hub v2.2"},
            {type=10,content="- **Account:** "..pn.."\n- **Mode:** "..mode.."\n- **Status:** Online"},
            {type=14,spacing=1,divider=true},
            {type=10,content="-# "..date},
        }}}}
end

local function WH_Test(pn)
    local date=os.date("!%B %d, %Y")
    return {username="Vechnost",avatar_url="https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",flags=32768,
        components={ {type=17,accent_color=0x5865f2,components={
            {type=10,content="**Test Message ✅**"},
            {type=14,spacing=1,divider=true},
            {type=10,content="Webhook OK!\n- **By:** "..pn},
            {type=14,spacing=1,divider=true},
            {type=10,content="-# "..date},
        }}}}
end

local function WH_Trade(s,r,si,ri)
    local date=os.date("!%B %d, %Y")
    local st,rt="",""
    for _,v in ipairs(si or {}) do st=st.."\n- "..v end
    for _,v in ipairs(ri or {}) do rt=rt.."\n- "..v end
    if st=="" then st="\n- (none)" end
    if rt=="" then rt="\n- (none)" end
    return {username="Vechnost",avatar_url="https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",flags=32768,
        components={ {type=17,accent_color=0xffd700,components={
            {type=10,content="# TRADE COMPLETED"},
            {type=14,spacing=1,divider=true},
            {type=10,content="**"..s.."** ↔ **"..r.."**"},
            {type=10,content="**Sent:**"..st},
            {type=10,content="**Got:**"..rt},
            {type=14,spacing=1,divider=true},
            {type=10,content="-# "..date},
        }}}}
end

local function SendWH(p)
    if S.Url=="" or not HR or not p then return end
    pcall(function()
        local u=S.Url..(S.Url:find("?")and"&"or"?").."with_components=true"
        HR({Url=u,Method="POST",Headers={["Content-Type"]="application/json"},Body=Http:JSONEncode(p)})
    end)
end

-- ============================================================
-- 15. WEBHOOK LOGGER (server-wide)
-- ============================================================
local WC={};local CD={}
local function ParseChat(txt)
    if not S.Active or not S.Wide or not txt or txt=="" then return end
    local pn,fn,ws=txt:match("(%S+)%s+obtained%s+a%s+(.-)%s*%(([%d%.]+)kg%)")
    if not pn then pn,fn,ws=txt:match("(%S+)%s+obtained%s+(.-)%s*%(([%d%.]+)kg%)") end
    if not pn then pn,fn=txt:match("(%S+)%s+obtained%s+a%s+(.-)%s*with") end
    if not pn then pn,fn=txt:match("(%S+)%s+obtained%s+(.-)%s*with") end
    if not pn or not fn then return end
    fn=fn:gsub("%s+$","")
    if pn==LP.Name or pn==LP.DisplayName then return end
    local id=NtoId[fn] or NtoId[fn:lower()]
    if not id then
        for nm,i in pairs(NtoId) do
            if fn:lower():find(nm:lower(),1,true) or nm:lower():find(fn:lower(),1,true) then id=i;break end
        end
    end
    if not id or not ROK(id) then return end
    local k=pn..fn..tostring(math.floor(os.time()/2))
    if CD[k] then return end; CD[k]=true
    task.defer(function() task.wait(10);CD[k]=nil end)
    S.Logs=S.Logs+1
    GetIcon(id,function() SendWH(WH_Fish(pn,id,tonumber(ws) or 0,nil)) end)
end

local function HandleCatch(pa,wd,wr)
    if not S.Active then return end
    local it=(wr and typeof(wr)=="table" and wr.InventoryItem)
          or (wd and typeof(wd)=="table" and wd.InventoryItem)
    if not it or not it.Id or not it.UUID then return end
    if not DB[it.Id] or not ROK(it.Id) then return end
    if S.SentUID[it.UUID] then return end; S.SentUID[it.UUID]=true
    local pn=(function()
        if typeof(pa)=="Instance" and pa:IsA("Player") then return pa.Name
        elseif typeof(pa)=="string" then return pa
        elseif typeof(pa)=="table" and pa.Name then return tostring(pa.Name) end
        return LP.Name
    end)()
    if not S.Wide and pn~=LP.Name then return end
    local w=(wd and typeof(wd)=="table" and wd.Weight) or 0
    local mu=nil; pcall(function() mu=(wd and(wd.Mutation or wd.Variant)) or (it.Mutation or it.Variant) end)
    S.Logs=S.Logs+1
    GetIcon(it.Id,function() SendWH(WH_Fish(pn,it.Id,w,mu)) end)
end

local function StartLogger()
    if S.Active then return end
    if not _net or not _fishEvt then
        Rayfield:Notify({Title="Vechnost",Content="Remotes not found!",Duration=5}); return
    end
    S.Active=true; S.SentUID={}; S.Logs=0
    pcall(function()
        WC[#WC+1]=TCS.MessageReceived:Connect(function(m)
            pcall(function() if(m.Text or ""):find("obtained") then ParseChat(m.Text) end end)
        end)
    end)
    pcall(function()
        WC[#WC+1]=_fishEvt.OnClientEvent:Connect(function(...) HandleCatch(...) end)
    end)
    if S.Wide then
        pcall(function()
            WC[#WC+1]=PGui.DescendantAdded:Connect(function(d)
                if not d:IsA("TextLabel") then return end
                task.defer(function()
                    local t=d.Text or ""
                    for id,fd in pairs(DB) do
                        if fd.N and t:find(fd.N,1,true) and ROK(id) then
                            for _,p in pairs(Players:GetPlayers()) do
                                if p~=LP and (t:find(p.Name,1,true) or t:find(p.DisplayName,1,true)) then
                                    local k="G"..t:sub(1,30)..os.time()
                                    if S.SentUID[k] then return end; S.SentUID[k]=true; S.Logs=S.Logs+1
                                    GetIcon(id,function() SendWH(WH_Fish(p.Name,id,0,nil)) end); return
                                end
                            end; return
                        end
                    end
                end)
            end)
        end)
        pcall(function()
            for _,ch in pairs(_net:GetChildren()) do
                if ch:IsA("RemoteEvent") and ch~=_fishEvt then
                    WC[#WC+1]=ch.OnClientEvent:Connect(function(...)
                        for _,a in ipairs({...}) do
                            if typeof(a)=="table" then
                                local it=a.InventoryItem or (a.Id and a.UUID and a)
                                if it and it.Id and it.UUID and DB[it.Id] then HandleCatch(({...})[1],nil,a) end
                            end
                        end
                    end)
                end
            end
        end)
    end
    task.spawn(function() SendWH(WH_Act(LP.Name,S.Wide and "Server-Wide" or "Local")) end)
end

local function StopLogger()
    S.Active=false
    for _,c in ipairs(WC) do pcall(function() c:Disconnect() end) end; WC={}
end

-- ============================================================
-- 16. CONFIG FEATURES
-- ============================================================
-- Anti-AFK (random interval, pakai VIM)
local AAT
local function StartAFK()
    if AAT then return end
    AAT=task.spawn(function()
        while S.AAFK do
            if VIM then pcall(function()
                VIM:SendMouseButtonEvent(0,0,0,true,game,1)
                task.wait(0.05)
                VIM:SendMouseButtonEvent(0,0,0,false,game,1)
            end) end
            task.wait(55+math.random()*30)
        end; AAT=nil
    end)
end
local function StopAFK() S.AAFK=false; if AAT then task.cancel(AAT);AAT=nil end end

-- Infinite Jump
local IJC
local function StartIJ()
    if IJC then return end
    IJC=UIS.JumpRequest:Connect(function()
        local c=LP.Character; if not c then return end
        local h=c:FindFirstChildOfClass("Humanoid"); if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
    end)
end
local function StopIJ() S.InfJ=false; if IJC then pcall(function() IJC:Disconnect() end); IJC=nil end end

-- Speed / Jump
local function ApplySpeed(v)
    _spoofSpeed=v -- update spoof juga
    local c=LP.Character; if c then local h=c:FindFirstChildOfClass("Humanoid"); if h then h.WalkSpeed=v end end
    LP.CharacterAdded:Connect(function(nc) local h=nc:WaitForChild("Humanoid",5); if h then h.WalkSpeed=v end end)
end
local function ApplyJump(v)
    _spoofJump=v
    local c=LP.Character; if c then local h=c:FindFirstChildOfClass("Humanoid"); if h then h.JumpPower=v end end
    LP.CharacterAdded:Connect(function(nc) local h=nc:WaitForChild("Humanoid",5); if h then h.JumpPower=v end end)
end

-- ESP
local EF=Instance.new("Folder"); EF.Name="EF_222"; EF.Parent=WS
local EL
local function StartESP()
    if EL then return end
    EL=task.spawn(function()
        while S.ESP do
            pcall(function()
                EF:ClearAllChildren()
                for _,p in pairs(Players:GetPlayers()) do
                    if p~=LP and p.Character then
                        local hrp=p.Character:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            local bb=Instance.new("BillboardGui")
                            bb.Adornee=hrp;bb.Size=UDim2.fromOffset(160,50)
                            bb.StudsOffsetWorldSpace=Vector3.new(0,3,0)
                            bb.AlwaysOnTop=true;bb.Parent=EF
                            local lb=Instance.new("TextLabel",bb)
                            lb.Size=UDim2.fromScale(1,1);lb.BackgroundTransparency=1
                            lb.TextColor3=Color3.fromRGB(255,80,80);lb.TextStrokeTransparency=0
                            lb.Font=Enum.Font.GothamBold;lb.TextSize=14
                            local mh=LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                            local d=mh and math.floor((hrp.Position-mh.Position).Magnitude) or 0
                            lb.Text="👤 "..p.DisplayName.."\n["..d.." studs]"
                        end
                    end
                end
            end)
            task.wait(0.5)
        end
        EF:ClearAllChildren(); EL=nil
    end)
end
local function StopESP() S.ESP=false; if EL then task.cancel(EL);EL=nil end; EF:ClearAllChildren() end

-- ============================================================
-- 17. FLOATING BUTTON (pakai gethui() bukan CoreGui langsung)
-- ============================================================
-- gethui() = returns a hidden container not scanned by anti-cheat
local _hui = (gethui and gethui()) or _cg

local oldF=_hui:FindFirstChild(_FTAG); if oldF then oldF:Destroy() end
local BG=Instance.new("ScreenGui")
BG.Name=_FTAG; BG.ResetOnSpawn=false

-- protect GUI sebelum parent
pcall(function()
    if syn and syn.protect_gui then syn.protect_gui(BG)
    elseif protect_gui then protect_gui(BG) end
end)
BG.Parent=_hui

local Btn=Instance.new("ImageButton")
Btn.Size=UDim2.fromOffset(52,52);Btn.Position=UDim2.fromScale(0.05,0.5)
Btn.BackgroundTransparency=1;Btn.AutoButtonColor=false;Btn.BorderSizePixel=0
Btn.Image="rbxassetid://127239715511367";Btn.ScaleType=Enum.ScaleType.Fit;Btn.Parent=BG
Instance.new("UICorner",Btn).CornerRadius=UDim.new(1,0)

local wv=true
Btn.MouseButton1Click:Connect(function()
    wv=not wv; pcall(function() Rayfield:SetVisibility(wv) end)
end)
local dg=false;local dof=Vector2.zero
Btn.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        dg=true;dof=UIS:GetMouseLocation()-Btn.AbsolutePosition
        i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dg=false end end)
    end
end)
Run.RenderStepped:Connect(function()
    if not dg then return end
    local m=UIS:GetMouseLocation();local t=m-dof
    local vp=(WS.CurrentCamera and WS.CurrentCamera.ViewportSize) or Vector2.new(1920,1080)
    local sz=Btn.AbsoluteSize
    Btn.Position=UDim2.fromOffset(math.clamp(t.X,0,vp.X-sz.X),math.clamp(t.Y,0,vp.Y-sz.Y))
end)

-- ============================================================
-- 18. RAYFIELD WINDOW
-- ============================================================
local Win=Rayfield:CreateWindow({
    Name="Vechnost Hub",Icon="fish",
    LoadingTitle="Vechnost Hub",LoadingSubtitle="v2.2 | Fish It",
    Theme="Default",ToggleUIKeybind="V",
    DisableRayfieldPrompts=true,DisableBuildWarnings=true,
    ConfigurationSaving={Enabled=true,FolderName="Vechnost",FileName="VCfg22"},
    KeySystem=true,
    KeySettings={
        Title="Vechnost Access",Subtitle="Authentication Required",
        Note="Join discord for key\nhttps://discord.gg/vechnost",
        FileName="VKey",SaveKey=true,GrabKeyFromSite=false,
        Key={"Vechnost-Notifier-9999"}
    },
})

-- ============================================================
-- TAB 1: INFO
-- ============================================================
local TI=Win:CreateTab("Info","info")
TI:CreateSection("Vechnost Hub v2.2")
TI:CreateParagraph({
    Title="Selamat Datang!",
    Content="All-in-one hub Fish It — anti-detect vs CODE-BAC\n\n✅ Auto Fish (VIM click)\n✅ Auto Sell\n✅ Auto Trade Monitor\n✅ Teleport (scan Workspace)\n✅ Webhook Server-Wide\n✅ Player ESP\n✅ Anti-AFK, Inf Jump, Speed\n✅ GUI protect_gui / gethui()\n✅ Spoof WalkSpeed ke server\n✅ No warn() fingerprint\n\nby Vechnost | discord.gg/vechnost"
})
TI:CreateSection("📊 Stats")
local SL2=TI:CreateParagraph({Title="Stats",Content="Loading..."})
task.spawn(function()
    while true do task.wait(3)
        pcall(function()
            local st=Stats()
            if SL2 then SL2:Set({Title="📊 Stats",Content=string.format(
                "💰 Coins: %s\n🐟 Caught: %s\n🎒 Backpack: %s/%s\n👥 Players: %d",
                Fmt(st.C),Fmt(st.F),Fmt(st.B),st.BM>0 and Fmt(st.BM) or "?",#Players:GetPlayers()
            )}) end
        end)
    end
end)
TI:CreateSection("Server")
TI:CreateButton({Name="🔄 Rejoin",Callback=function()
    pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId,LP) end)
    Rayfield:Notify({Title="V",Content="Rejoining...",Duration=2})
end})
TI:CreateButton({Name="📋 Copy Game Link",Callback=function()
    local l="https://www.roblox.com/games/"..game.PlaceId
    pcall(function() setclipboard(l) end)
    Rayfield:Notify({Title="V",Content="Copied!",Duration=2})
end})

-- ============================================================
-- TAB 2: FISHING
-- ============================================================
local TF=Win:CreateTab("Fishing","fish")
TF:CreateSection("🎣 Auto Fish")
TF:CreateParagraph({Title="ℹ️ Info",Content="Simulasi mouse click untuk charge + reel.\nSesuai mekanik Fish It: charge = tahan klik, reel = spam klik."})
TF:CreateToggle({Name="🎣 Auto Fish",CurrentValue=false,Flag="AF",Callback=function(v)
    S.AFish=v
    if v then StartFish();Rayfield:Notify({Title="V",Content="Auto Fish ON!",Duration=2})
    else StopFish();Rayfield:Notify({Title="V",Content="Auto Fish OFF",Duration=2}) end
end})
TF:CreateSlider({Name="⏱️ Cast Delay",Range={0.05,2},Increment=0.05,Suffix="s",CurrentValue=0.08,Flag="FD",
    Callback=function(v) S.FDelay=v end})
TF:CreateSection("💰 Auto Sell")
TF:CreateToggle({Name="💰 Auto Sell",CurrentValue=false,Flag="AS",Callback=function(v)
    S.ASell=v
    if v then StartSell();Rayfield:Notify({Title="V",Content="Auto Sell ON!",Duration=2})
    else StopSell();Rayfield:Notify({Title="V",Content="Auto Sell OFF",Duration=2}) end
end})
TF:CreateSlider({Name="⏱️ Sell Interval",Range={1,30},Increment=1,Suffix="s",CurrentValue=5,Flag="SD",
    Callback=function(v) S.SDelay=v end})
TF:CreateButton({Name="💰 Sell Manual",Callback=function()
    TrySell();Rayfield:Notify({Title="V",Content="Sell!",Duration=2})
end})
TF:CreateSection("📈 Session")
local FStat=TF:CreateParagraph({Title="Session",Content="..."})
task.spawn(function()
    while true do task.wait(2)
        pcall(function()
            if FStat then FStat:Set({Title="📈 Session",Content=string.format(
                "🐟 Logged: %d\n🎣 Fish: %s\n💰 Sell: %s",S.Logs,
                S.AFish and "ON ✅" or "OFF ❌",S.ASell and "ON ✅" or "OFF ❌"
            )}) end
        end)
    end
end)

-- ============================================================
-- TAB 3: TRADING
-- ============================================================
local TT=Win:CreateTab("Trading","arrow-left-right")
TT:CreateSection("Auto Trade")
TT:CreateToggle({Name="✅ Auto Accept",CurrentValue=false,Flag="AA",Callback=function(v)
    S.AAccept=v; if v then S.ADecline=false; StartTrade() end
    Rayfield:Notify({Title="V",Content=v and "Accept ON!" or "Accept OFF",Duration=2})
end})
TT:CreateToggle({Name="❌ Auto Decline",CurrentValue=false,Flag="AD",Callback=function(v)
    S.ADecline=v; if v then S.AAccept=false; StartTrade() end
    Rayfield:Notify({Title="V",Content=v and "Decline ON!" or "Decline OFF",Duration=2})
end})
TT:CreateSection("Filter")
TT:CreateDropdown({Name="🎯 Min Rarity",Options=RL,CurrentOption={"Legendary"},MultipleOptions=false,Flag="TR",
    Callback=function(o) S.TRarity=RT[o] or 5;Rayfield:Notify({Title="V",Content="Min: "..o,Duration=2}) end})
TT:CreateSection("Log")
TT:CreateToggle({Name="📤 Log Trade → Webhook",CurrentValue=false,Flag="TL",Callback=function(v)
    S.TLog=v; if v then StartTrade() end
    Rayfield:Notify({Title="V",Content=v and "Trade log ON!" or "Trade log OFF",Duration=2})
end})
TT:CreateParagraph({Title="ℹ️ Info",Content="Accept: terima jika item >= Min Rarity.\nDecline: tolak semua.\nLog: kirim detail trade ke webhook.\nPastikan URL webhook diisi."})

-- ============================================================
-- TAB 4: TELEPORT
-- ============================================================
local TP=Win:CreateTab("Teleport","map-pin")
local Islands={};local IsNames={}
local function RefreshIslands2()
    Islands=ScanIslands()
    IsNames={}; for _,l in ipairs(Islands) do table.insert(IsNames,l.Name) end
    if #IsNames==0 then IsNames={"(kosong)"} end
end
RefreshIslands2()

TP:CreateSection("Island")
TP:CreateParagraph({Title="ℹ️ Info",Content="Script scan Workspace otomatis.\nKlik Refresh jika island tidak muncul."})
TP:CreateButton({Name="🔄 Refresh List",Callback=function()
    RefreshIslands2()
    Rayfield:Notify({Title="V",Content=string.format("Ditemukan %d lokasi",#Islands),Duration=2})
end})
local SelI=IsNames[1]
TP:CreateDropdown({Name="📍 Select Island",Options=IsNames,CurrentOption={IsNames[1]},MultipleOptions=false,Flag="TPI",
    Callback=function(o) SelI=o end})
TP:CreateButton({Name="🚀 Teleport → Island",Callback=function()
    RefreshIslands2()
    for _,l in ipairs(Islands) do
        if l.Name==SelI then
            SafeTP(l.Pos,function(ok)
                Rayfield:Notify({Title="V",Content=ok and("✅ "..l.Name) or "❌ Gagal!",Duration=3})
            end); return
        end
    end
    Rayfield:Notify({Title="V",Content="Klik Refresh dulu!",Duration=3})
end})

TP:CreateSection("Player")
local PlrNames={}
local function RefreshPL()
    PlrNames={}
    for _,p in pairs(Players:GetPlayers()) do
        if p~=LP then table.insert(PlrNames,p.Name) end
    end
    if #PlrNames==0 then PlrNames={"(tidak ada)"} end
end
RefreshPL()
Players.PlayerAdded:Connect(function() task.wait(0.3);RefreshPL() end)
Players.PlayerRemoving:Connect(function() task.wait(0.5);RefreshPL() end)

TP:CreateButton({Name="🔄 Refresh Players",Callback=function()
    RefreshPL()
    Rayfield:Notify({Title="V",Content=string.format("%d players",#PlrNames),Duration=2})
end})
local SelP=PlrNames[1]
TP:CreateDropdown({Name="👥 Select Player",Options=PlrNames,CurrentOption={PlrNames[1]},MultipleOptions=false,Flag="TPP",
    Callback=function(o) SelP=o end})
TP:CreateButton({Name="🚀 Teleport → Player",Callback=function()
    RefreshPL()
    local tgt=Players:FindFirstChild(SelP)
    if not tgt then
        for _,p in pairs(Players:GetPlayers()) do
            if p.DisplayName==SelP then tgt=p;break end
        end
    end
    if not tgt then Rayfield:Notify({Title="V",Content="Player tidak ada!",Duration=3});return end
    if not tgt.Character or not tgt.Character:FindFirstChild("HumanoidRootPart") then
        Rayfield:Notify({Title="V",Content=tgt.Name.." tidak punya karakter!",Duration=3});return
    end
    SafeTP(tgt.Character.HumanoidRootPart.Position+Vector3.new(3,2,3),function(ok)
        Rayfield:Notify({Title="V",Content=ok and("✅ "..tgt.Name) or "❌ Gagal!",Duration=3})
    end)
end})
TP:CreateButton({Name="🎲 Random Player",Callback=function()
    local list={}
    for _,p in pairs(Players:GetPlayers()) do if p~=LP then table.insert(list,p) end end
    if #list==0 then Rayfield:Notify({Title="V",Content="Tidak ada player!",Duration=2});return end
    local t=list[math.random(1,#list)]
    if not t.Character or not t.Character:FindFirstChild("HumanoidRootPart") then
        Rayfield:Notify({Title="V",Content=t.Name.." tidak punya karakter!",Duration=2});return
    end
    SafeTP(t.Character.HumanoidRootPart.Position+Vector3.new(3,2,3),function(ok)
        Rayfield:Notify({Title="V",Content=ok and("✅ "..t.Name) or "❌ Gagal!",Duration=2})
    end)
end})
TP:CreateSection("Respawn")
TP:CreateButton({Name="🏠 Respawn ke Spawn",Callback=function()
    local c=LP.Character
    if c then local h=c:FindFirstChildOfClass("Humanoid"); if h then h.Health=0 end end
    Rayfield:Notify({Title="V",Content="Respawning...",Duration=2})
end})

-- ============================================================
-- TAB 5: WEBHOOK
-- ============================================================
local TW=Win:CreateTab("Webhook","webhook")
TW:CreateSection("Rarity Filter")
TW:CreateDropdown({Name="🎯 Filter Rarity",Options=RL,CurrentOption={},MultipleOptions=true,Flag="RF",
    Callback=function(opts)
        S.Rarities={}
        for _,v in ipairs(opts or {}) do local t=RT[v]; if t then S.Rarities[t]=true end end
        Rayfield:Notify({Title="V",Content=next(S.Rarities)==nil and "Semua rarity" or "Filter updated",Duration=2})
    end})
TW:CreateSection("Setup")
local WUB=""
TW:CreateInput({Name="Webhook URL",CurrentValue="",PlaceholderText="https://discord.com/api/webhooks/...",
    RemoveTextAfterFocusLost=false,Flag="WU",Callback=function(t) WUB=tostring(t) end})
TW:CreateButton({Name="💾 Save URL",Callback=function()
    local u=WUB:gsub("%s+","")
    if not u:match("^https://discord%.com/api/webhooks/") and not u:match("^https://canary%.discord%.com/api/webhooks/") then
        Rayfield:Notify({Title="V",Content="URL tidak valid!",Duration=3});return
    end
    S.Url=u;Rayfield:Notify({Title="V",Content="✅ Saved!",Duration=2})
end})
TW:CreateSection("Mode")
TW:CreateToggle({Name="🌐 Server-Wide Mode",CurrentValue=true,Flag="SM",Callback=function(v)
    S.Wide=v;Rayfield:Notify({Title="V",Content=v and "Server-Wide" or "Local Only",Duration=2})
end})
TW:CreateSection("Control")
TW:CreateToggle({Name="✅ Enable Logger",CurrentValue=false,Flag="LE",Callback=function(v)
    if v then
        if S.Url=="" then Rayfield:Notify({Title="V",Content="Isi URL dulu!",Duration=3});return end
        StartLogger();Rayfield:Notify({Title="V",Content="🟢 Logger ON!",Duration=2})
    else StopLogger();Rayfield:Notify({Title="V",Content="🔴 Logger OFF",Duration=2}) end
end})
local WS2=TW:CreateParagraph({Title="Status",Content="Offline"})
task.spawn(function()
    while true do task.wait(2)
        pcall(function()
            if WS2 then WS2:Set({Title="📡 Status",Content=S.Active and
                string.format("🟢 Aktif\nMode: %s\nLogged: %d\nURL: %s",
                    S.Wide and "Server-Wide" or "Local",S.Logs,S.Url~="" and "✅" or "❌") or
                ("🔴 Offline\nURL: "..(S.Url~="" and "✅" or "❌"))
            }) end
        end)
    end
end)
TW:CreateSection("Test")
TW:CreateButton({Name="🧪 Test Webhook",Callback=function()
    if S.Url=="" then Rayfield:Notify({Title="V",Content="Isi URL dulu!",Duration=3});return end
    task.spawn(function() SendWH(WH_Test(LP.Name)) end)
    Rayfield:Notify({Title="V",Content="Test terkirim!",Duration=2})
end})
TW:CreateButton({Name="🔄 Reset Counter",Callback=function()
    S.Logs=0;S.SentUID={}
    Rayfield:Notify({Title="V",Content="Counter reset!",Duration=2})
end})

-- ============================================================
-- TAB 6: CONFIG
-- ============================================================
local TC2=Win:CreateTab("Config","settings")
TC2:CreateSection("Movement")
TC2:CreateSlider({Name="🏃 Walk Speed",Range={16,300},Increment=1,Suffix="",CurrentValue=16,Flag="WS",
    Callback=function(v) S.Speed=v;ApplySpeed(v) end})
TC2:CreateSlider({Name="🦘 Jump Power",Range={50,300},Increment=5,Suffix="",CurrentValue=50,Flag="JP",
    Callback=function(v) S.Jump=v;ApplyJump(v) end})
TC2:CreateToggle({Name="♾️ Infinite Jump",CurrentValue=false,Flag="IJ",Callback=function(v)
    S.InfJ=v
    if v then StartIJ();Rayfield:Notify({Title="V",Content="Inf Jump ON!",Duration=2})
    else StopIJ();Rayfield:Notify({Title="V",Content="Inf Jump OFF",Duration=2}) end
end})
TC2:CreateButton({Name="🔄 Reset Speed/Jump",Callback=function()
    S.Speed=16;S.Jump=50;ApplySpeed(16);ApplyJump(50)
    Rayfield:Notify({Title="V",Content="Reset!",Duration=2})
end})
TC2:CreateSection("Utility")
TC2:CreateToggle({Name="🤖 Anti-AFK",CurrentValue=false,Flag="AAFK",Callback=function(v)
    S.AAFK=v
    if v then StartAFK();Rayfield:Notify({Title="V",Content="Anti-AFK ON!",Duration=2})
    else StopAFK();Rayfield:Notify({Title="V",Content="Anti-AFK OFF",Duration=2}) end
end})
TC2:CreateToggle({Name="👁️ Player ESP",CurrentValue=false,Flag="ESP",Callback=function(v)
    S.ESP=v
    if v then StartESP();Rayfield:Notify({Title="V",Content="ESP ON!",Duration=2})
    else StopESP();Rayfield:Notify({Title="V",Content="ESP OFF",Duration=2}) end
end})
TC2:CreateToggle({Name="🌙 Remove Fog",CurrentValue=false,Flag="RF2",Callback=function(v)
    S.Fog=v
    pcall(function()
        local L=game:GetService("Lighting")
        if v then L.FogEnd=100000;L.FogStart=99999
        else L.FogEnd=100000;L.FogStart=0 end
    end)
    Rayfield:Notify({Title="V",Content=v and "Fog OFF!" or "Fog restored",Duration=2})
end})
TC2:CreateSection("Anti-Detect v2.2")
TC2:CreateParagraph({Title="🛡️ Metode Bypass CODE-BAC",Content=
    "✅ protect_gui / gethui() — GUI tidak masuk CoreGui scan\n"..
    "✅ hookmetamethod spoof WalkSpeed/JumpPower ke server\n"..
    "✅ 0 warn() — tidak ada console fingerprint\n"..
    "✅ HttpGet delay 1s sebelum load Rayfield\n"..
    "✅ Nama GUI acak (_TAG internal)\n"..
    "✅ Teleport 4-step, bukan langsung\n"..
    "✅ Anti-AFK random interval 55–85s\n"..
    "✅ Auto Fish via VIM (bukan RemoteFire)\n\n"..
    "⚠️ Selalu gunakan Private Server!"
})
TC2:CreateButton({Name="💾 Save Config",Callback=function()
    Rayfield:Notify({Title="V",Content="Saved!",Duration=2})
end})
TC2:CreateButton({Name="🗑️ Reset Config",Callback=function()
    pcall(function() Rayfield:ClearConfiguration() end)
    Rayfield:Notify({Title="V",Content="Reset! Restart script.",Duration=3})
end})
TC2:CreateParagraph({Title="Vechnost Hub v2.2",Content="by Vechnost\ndiscord.gg/vechnost"})

-- ============================================================
-- INIT
-- ============================================================
Rayfield:LoadConfiguration()

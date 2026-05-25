--[[═══════════════════════════════════════════════════════════════════════
    ACH V2 — Scripted by Floriszxfloris (FMC Playground)
    Original features: floriszxfloris (Auto Counter Hub)
    Game: Marvellous Smackdown
    Bundled modular framework — single-file loadstring distribution.

    Architecture:
      _G.ACHv2 (shared state) — single source of truth
      ACHv2.Dispatcher        — ONE Heartbeat + ONE RenderStepped
      ACHv2.Connections       — bucketed signal cleanup
      Modules: systems/* ui/* utils/* games/marvellous

    Executor compatibility: Synapse X, Solara, Wave, Krampus, Hydrogen.
    Usage:  loadstring(game:HttpGet("https://raw.githubusercontent.com/USER/REPO/main/ACHv2.lua"))()
═══════════════════════════════════════════════════════════════════════]]

if _G.ACHv2 and _G.ACHv2.Loaded then
    if _G.ACHv2.Notifications then
        _G.ACHv2.Notifications.notify("✦ ACH V2", "Already loaded — reusing instance.", 2)
    end
    return _G.ACHv2
end

-- ═══════════════════════════════════════════════════════════════════════
--  SHARED STATE
-- ═══════════════════════════════════════════════════════════════════════
local State = {
    Version       = "2.0-modular",
    Game          = "Marvellous Smackdown",
    Author        = "floriszxfloris",
    Brand         = "FMC Playground",
    Loaded        = false,
    Services      = {},
    Player        = nil,
    Character     = nil,
    Humanoid      = nil,
    RootPart      = nil,
    Settings      = nil,
    Theme         = nil,
    ActiveCounter = { name=nil, window=nil, indicator=nil, queued=false, lastFire=0 },
    Modules       = {},
    Subscribers   = { heartbeat={}, render={} },
    Connections   = nil,
    Notifications = nil,
    Dispatcher    = nil,
    ScreenGui     = nil,
    Showcase      = { active=false, originalParent=nil },
}
_G.ACHv2 = State

-- ── Cached services (no repeated GetService) ────────────────────────────
local function svc(name)
    State.Services[name] = State.Services[name] or game:GetService(name)
    return State.Services[name]
end
State.svc = svc
local Players      = svc("Players")
local RunService   = svc("RunService")
local UIS          = svc("UserInputService")
local TweenService = svc("TweenService")
local CoreGui      = svc("CoreGui")
local HttpService  = svc("HttpService")
svc("ReplicatedStorage"); svc("Lighting"); svc("StarterGui"); svc("Workspace")
pcall(function() svc("Stats") end)
pcall(function() svc("VirtualInputManager") end)
State.Player = Players.LocalPlayer

-- ── Module registry ─────────────────────────────────────────────────────
local registry = {}
function State.Register(path, factory) registry[path] = factory end
function State.Require(path)
    local f = registry[path]; if not f then error("[ACHv2] Missing module: "..path) end
    return f(State)
end

-- ═══════════════════════════════════════════════════════════════════════
--  utils/connections.lua
-- ═══════════════════════════════════════════════════════════════════════
State.Register("utils/connections.lua", function(State)
    local M = { _buckets = {} }
    function M.bind(bucket, conn)
        M._buckets[bucket] = M._buckets[bucket] or {}
        table.insert(M._buckets[bucket], conn); return conn
    end
    function M.clear(bucket)
        local list = M._buckets[bucket]; if not list then return end
        for i = #list, 1, -1 do
            local c = list[i]; if c then pcall(function() c:Disconnect() end) end
            list[i] = nil
        end
        M._buckets[bucket] = nil
    end
    function M.clearAll() for n in pairs(M._buckets) do M.clear(n) end end
    return M
end)

-- ═══════════════════════════════════════════════════════════════════════
--  utils/helpers.lua
-- ═══════════════════════════════════════════════════════════════════════
State.Register("utils/helpers.lua", function(State)
    local TweenService = State.Services.TweenService
    local Players      = State.Services.Players
    local CoreGui      = State.Services.CoreGui
    local M = {}

    function M.create_instance(class, props, children)
        local o = Instance.new(class)
        if props then for k,v in pairs(props) do o[k] = v end end
        if children then for _,c in ipairs(children) do c.Parent = o end end
        return o
    end

    local TI = TweenInfo.new
    function M.tween(inst, props, t, style, dir)
        local tw = TweenService:Create(inst,
            TI(t or 0.3, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
        tw:Play(); return tw
    end
    function M.smoothTween(i,p,t) return M.tween(i,p,t or 0.4, Enum.EasingStyle.Quint) end
    function M.bounceTween(i,p,t) return M.tween(i,p,t or 0.5, Enum.EasingStyle.Back) end

    function M.parentGui(gui)
        local target
        if gethui then target = gethui()
        elseif get_hidden_gui then target = get_hidden_gui()
        else target = CoreGui end
        local ok = pcall(function() gui.Parent = target end)
        if not ok then
            pcall(function()
                if syn and syn.protect_gui then syn.protect_gui(gui) end
                gui.Parent = CoreGui
            end)
        end
    end

    function M.getChar()     return State.Character end
    function M.getRoot()     return State.RootPart  end
    function M.getHumanoid() return State.Humanoid  end
    function M.alive()
        local h = State.Humanoid
        return h ~= nil and h.Health > 0 and State.RootPart ~= nil
    end

    function M.enemies()
        local me, out = State.Player, {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= me and p.Character then
                local h = p.Character:FindFirstChildOfClass("Humanoid")
                local r = p.Character:FindFirstChild("HumanoidRootPart")
                if h and r and h.Health > 0 then
                    table.insert(out, {player=p, hum=h, root=r})
                end
            end
        end
        return out
    end

    function M.distance(a, b) return (a.Position - b.Position).Magnitude end

    function M.nearestEnemy(maxDist)
        if not M.alive() then return nil end
        local myPos = State.RootPart.Position
        local best, bestD = nil, maxDist or math.huge
        for _, e in ipairs(M.enemies()) do
            local d = (e.root.Position - myPos).Magnitude
            if d < bestD then best, bestD = e, d end
        end
        return best, bestD
    end

    return M
end)

-- ═══════════════════════════════════════════════════════════════════════
--  utils/config.lua
-- ═══════════════════════════════════════════════════════════════════════
State.Register("utils/config.lua", function(State)
    local HttpService = State.Services.HttpService
    local M = {}
    local hasFS = (writefile and readfile and isfile) and true or false
    local FILE  = "ACHv2_settings.json"

    M.Defaults = {
        Keybinds = {
            ToggleGUI  = Enum.KeyCode.F3,
            Counter    = Enum.KeyCode.C,
            ShiftLock  = Enum.KeyCode.L,
            AutoBlock  = Enum.KeyCode.B,
            TargetLock = Enum.KeyCode.T,
            Showcase   = Enum.KeyCode.F4,
        },
        autoBlockEnabled    = false,
        autoBlockRange      = 12,
        autoBlockMode       = "hold",
        autoBlockKey        = "F",
        shiftLockUnlocked   = false,
        predictiveCounter   = true,
        targetLockEnabled   = false,
        notifications       = true,
        fpsBoost            = false,
        watermark           = true,
        theme               = "Phantom",
        favorites           = {},
        activeProfile       = "Default",
    }

    local function serialize(t)
        local out = {}
        for k,v in pairs(t) do
            if typeof(v) == "EnumItem" then out[k] = "Enum."..tostring(v)
            elseif type(v) == "table" then out[k] = serialize(v)
            else out[k] = v end
        end
        return out
    end
    local function deserialize(t)
        for k,v in pairs(t) do
            if type(v) == "string" and v:sub(1,5) == "Enum." then
                local enumName, itemName = v:match("Enum%.([^.]+)%.(.+)")
                if enumName and Enum[enumName] then
                    local ok, item = pcall(function() return Enum[enumName][itemName] end)
                    if ok then t[k] = item end
                end
            elseif type(v) == "table" then deserialize(v) end
        end
        return t
    end

    function M.Load()
        if hasFS and isfile(FILE) then
            local ok, decoded = pcall(HttpService.JSONDecode, HttpService, readfile(FILE))
            if ok then return deserialize(decoded) end
        end
        return nil
    end

    function M.Save()
        if not hasFS then return end
        pcall(writefile, FILE, HttpService:JSONEncode(serialize(M.Settings)))
    end

    local function merge(dst, src)
        for k,v in pairs(src) do
            if type(v) == "table" and type(dst[k]) == "table" then merge(dst[k], v)
            elseif dst[k] == nil then
                dst[k] = (type(v)=="table") and (table.clone and table.clone(v) or v) or v
            end
        end
    end

    M.Settings = M.Load() or {}
    merge(M.Settings, M.Defaults)

    function M.Set(path, value)
        local parts, t = string.split(path, "."), M.Settings
        for i = 1, #parts-1 do t[parts[i]] = t[parts[i]] or {}; t = t[parts[i]] end
        t[parts[#parts]] = value
        M.Save()
    end

    return M
end)

-- ═══════════════════════════════════════════════════════════════════════
--  utils/profiles.lua
-- ═══════════════════════════════════════════════════════════════════════
State.Register("utils/profiles.lua", function(State)
    local HttpService = State.Services.HttpService
    local M = {}
    local hasFS = writefile and readfile and isfile and isfolder and makefolder and listfiles
    local DIR = "ACHv2_profiles"
    if hasFS and not isfolder(DIR) then pcall(makefolder, DIR) end

    function M.List()
        local out = { "Default" }
        if not hasFS then return out end
        for _, f in ipairs(listfiles(DIR)) do
            local name = f:match("([^/\\]+)%.json$")
            if name and name ~= "Default" then table.insert(out, name) end
        end
        return out
    end

    function M.Save(name)
        if not hasFS then return false end
        local Config = State.Config
        pcall(writefile, DIR.."/"..name..".json", HttpService:JSONEncode(Config.Settings))
        Config.Settings.activeProfile = name
        Config.Save()
        if State.Notifications then
            State.Notifications.notify("Profile", "Saved profile: "..name, 2)
        end
        return true
    end

    function M.Load(name)
        if not hasFS then return false end
        local path = DIR.."/"..name..".json"
        if not isfile(path) then return false end
        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, readfile(path))
        if not ok then return false end
        local S = State.Config.Settings
        for k in pairs(S) do S[k] = nil end
        for k,v in pairs(decoded) do S[k] = v end
        S.activeProfile = name
        State.Config.Save()
        if State.Notifications then
            State.Notifications.notify("Profile", "Loaded profile: "..name, 2)
        end
        if State.MainUI and State.MainUI.Refresh then State.MainUI.Refresh() end
        return true
    end

    function M.Delete(name)
        if not hasFS or name == "Default" then return false end
        local path = DIR.."/"..name..".json"
        if isfile(path) and delfile then pcall(delfile, path); return true end
        return false
    end

    return M
end)

-- ═══════════════════════════════════════════════════════════════════════
--  ui/themes.lua  (Phantom palette preserved verbatim)
-- ═══════════════════════════════════════════════════════════════════════
State.Register("ui/themes.lua", function(State)
    local M = {}
    M.Phantom = {
        Background          = Color3.fromRGB(8, 10, 15),
        BackgroundSecondary = Color3.fromRGB(12, 14, 20),
        Surface             = Color3.fromRGB(18, 22, 30),
        SurfaceHover        = Color3.fromRGB(28, 35, 50),
        SurfaceActive       = Color3.fromRGB(75, 25, 35),
        Border              = Color3.fromRGB(25, 30, 40),
        BorderActive        = Color3.fromRGB(140, 50, 70),
        Accent              = Color3.fromRGB(140, 50, 70),
        AccentBright        = Color3.fromRGB(180, 70, 90),
        AccentSoft          = Color3.fromRGB(95, 35, 50),
        TextPrimary         = Color3.fromRGB(240, 240, 245),
        TextSecondary       = Color3.fromRGB(160, 165, 175),
        TextMuted           = Color3.fromRGB(110, 115, 125),
        Success             = Color3.fromRGB(80, 200, 130),
        Warning             = Color3.fromRGB(255, 180, 70),
        Danger              = Color3.fromRGB(220, 60, 80),
        Glow                = Color3.fromRGB(160, 60, 80),
    }
    M.Themes      = { Phantom = M.Phantom }
    M.Current     = M.Phantom
    M.Subscribers = {}

    function M.Register(applyFn)
        table.insert(M.Subscribers, applyFn)
        applyFn(M.Current)
    end
    function M.Set(name)
        local t = M.Themes[name]; if not t then return end
        M.Current = t; State.Theme = t
        for _, fn in ipairs(M.Subscribers) do pcall(fn, t) end
        if State.Notifications then State.Notifications.notify("Theme","Applied: "..name,1.5) end
    end
    function M.ApplyTo() State.Theme = M.Current end
    return M
end)

-- ═══════════════════════════════════════════════════════════════════════
--  ui/notifications.lua
-- ═══════════════════════════════════════════════════════════════════════
State.Register("ui/notifications.lua", function(State)
    local M = {}
    local create = State.Helpers.create_instance
    local tween  = State.Helpers.tween
    local container

    function M.Init()
        container = create("Frame", {
            Name = "NotificationContainer", BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 80),
            Size = UDim2.new(0, 320, 1, -100), Parent = State.ScreenGui,
        })
        create("UIListLayout", {
            Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
            VerticalAlignment = Enum.VerticalAlignment.Top,
            HorizontalAlignment = Enum.HorizontalAlignment.Right, Parent = container,
        })
    end

    function M.notify(title, body, duration)
        if not State.Settings.notifications then return end
        if not container then return end
        duration = duration or 3
        local theme = State.Theme
        local card = create("Frame", {
            BackgroundColor3 = theme.Surface, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 64), Position = UDim2.new(1, 40, 0, 0),
            Parent = container,
        })
        create("UICorner", { CornerRadius = UDim.new(0,10), Parent = card })
        create("UIStroke", { Color = theme.Border, Thickness = 1, Parent = card })
        local accent = create("Frame", {
            BackgroundColor3 = theme.Accent, BorderSizePixel = 0,
            Size = UDim2.new(0, 3, 1, -16), Position = UDim2.new(0, 8, 0, 8),
            Parent = card,
        })
        create("UICorner", { CornerRadius = UDim.new(0,2), Parent = accent })
        create("TextLabel", {
            BackgroundTransparency = 1, Position = UDim2.new(0,20,0,8),
            Size = UDim2.new(1,-28,0,20), Text = title,
            TextColor3 = theme.TextPrimary, Font = Enum.Font.GothamBold,
            TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Parent = card,
        })
        create("TextLabel", {
            BackgroundTransparency = 1, Position = UDim2.new(0,20,0,28),
            Size = UDim2.new(1,-28,0,32), Text = body,
            TextColor3 = theme.TextSecondary, Font = Enum.Font.Gotham,
            TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Parent = card,
        })

        tween(card, { Position = UDim2.new(0,0,0,0) }, 0.35, Enum.EasingStyle.Quint)
        task.delay(duration, function()
            local out = tween(card, {
                Position = UDim2.new(1,40,0,0), BackgroundTransparency = 1,
            }, 0.4, Enum.EasingStyle.Quint)
            out.Completed:Connect(function() card:Destroy() end)
        end)
    end
    return M
end)

-- ═══════════════════════════════════════════════════════════════════════
--  ui/wallpaper.lua  (root ScreenGui + splash + FPS/Ping watermark)
-- ═══════════════════════════════════════════════════════════════════════
State.Register("ui/wallpaper.lua", function(State)
    local M = {}
    local create     = State.Helpers.create_instance
    local tween      = State.Helpers.tween
    local RunService = State.Services.RunService
    local Stats      = State.Services.Stats

    function M.Mount()
        local gui = create("ScreenGui", {
            Name = "ACHv2", ResetOnSpawn = false,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true,
        })
        State.Helpers.parentGui(gui)
        State.ScreenGui = gui
        M.BuildBrandWatermark(gui)
        M.Splash(gui)
        return gui
    end

    function M.BuildBrandWatermark(gui)
        if not State.Settings.watermark then return end
        local theme = State.Theme

        local frame = create("Frame", {
            Name = "Watermark", AnchorPoint = Vector2.new(0,1),
            Position = UDim2.new(0,16,1,-16), Size = UDim2.new(0,260,0,32),
            BackgroundColor3 = theme.Background, BackgroundTransparency = 0.15,
            BorderSizePixel = 0, Parent = gui,
        })
        create("UICorner",{ CornerRadius=UDim.new(0,8), Parent=frame })
        create("UIStroke",{ Color=theme.BorderActive, Thickness=1, Parent=frame })

        local label = create("TextLabel", {
            BackgroundTransparency = 1, Size = UDim2.new(1,-16,1,0),
            Position = UDim2.new(0,8,0,0),
            Text = "✦ ACH V2 | FPS: -- | Ping: --",
            TextColor3 = theme.TextPrimary, Font = Enum.Font.GothamMedium,
            TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame,
        })

        local lastT, frames = os.clock(), 0
        State.Connections.bind("Watermark",
            RunService.RenderStepped:Connect(function() frames += 1 end))

        State.Dispatcher.OnHeartbeat("Watermark", function(_, now)
            local dt = now - lastT
            if dt < 0.5 then return end
            local fps  = math.floor(frames / dt)
            local ping = 0
            if Stats then
                pcall(function()
                    ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
                end)
            end
            label.Text = ("✦ ACH V2 | FPS: %d | Ping: %d"):format(fps, ping)
            lastT, frames = now, 0
        end, 0.5)
    end

    function M.Splash(gui)
        local theme = State.Theme
        local overlay = create("Frame", {
            BackgroundColor3 = theme.Background, BorderSizePixel = 0,
            Size = UDim2.new(1,0,1,0), ZIndex = 1000, Parent = gui,
        })
        local logo = create("TextLabel", {
            BackgroundTransparency = 1, Size = UDim2.new(1,0,0,80),
            Position = UDim2.new(0,0,0.5,-40), ZIndex = 1001,
            Text = "✦ ACH V2", TextColor3 = theme.AccentBright,
            Font = Enum.Font.GothamBold, TextSize = 40, TextTransparency = 1,
            Parent = overlay,
        })
        local sub = create("TextLabel", {
            BackgroundTransparency = 1, Size = UDim2.new(1,0,0,24),
            Position = UDim2.new(0,0,0.5,24), ZIndex = 1001,
            Text = "FMC Playground — Marvellous Smackdown",
            TextColor3 = theme.TextSecondary, Font = Enum.Font.Gotham,
            TextSize = 14, TextTransparency = 1, Parent = overlay,
        })
        tween(logo, {TextTransparency=0}, 0.6)
        tween(sub,  {TextTransparency=0}, 0.6)
        task.delay(1.4, function()
            tween(overlay, {BackgroundTransparency=1}, 0.5)
            tween(logo,    {TextTransparency=1},       0.5)
            tween(sub,     {TextTransparency=1},       0.5).Completed:Connect(function()
                overlay:Destroy()
            end)
        end)
    end
    return M
end)

-- ═══════════════════════════════════════════════════════════════════════
--  ui/widgets.lua  (macOS-titlebar window + sliders/toggles/dropdowns)
-- ═══════════════════════════════════════════════════════════════════════
State.Register("ui/widgets.lua", function(State)
    local M = {}
    local UIS    = State.Services.UserInputService
    local create = State.Helpers.create_instance
    local tween  = State.Helpers.tween

    function M.CreateWindow(title)
        local theme = State.Theme
        local W = {}

        local root = create("Frame", {
            Name = "Window_"..title, BackgroundColor3 = theme.Background,
            BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5,0.5),
            Position = UDim2.new(0.5,0,0.5,0), Size = UDim2.new(0,520,0,380),
            Parent = State.ScreenGui, ClipsDescendants = true,
        })
        create("UICorner",{ CornerRadius=UDim.new(0,12), Parent=root })
        create("UIStroke",{ Color=theme.Border, Thickness=1, Parent=root })

        local bar = create("Frame",{
            BackgroundColor3 = theme.BackgroundSecondary, BorderSizePixel = 0,
            Size = UDim2.new(1,0,0,32), Parent = root,
        })
        create("UICorner",{ CornerRadius=UDim.new(0,12), Parent=bar })
        create("Frame",{
            BackgroundColor3 = theme.BackgroundSecondary, BorderSizePixel = 0,
            Position = UDim2.new(0,0,0.5,0), Size = UDim2.new(1,0,0.5,0), Parent = bar,
        })

        local function dot(color, xOff, action)
            local b = create("TextButton",{
                Text="", BackgroundColor3=color, BorderSizePixel=0,
                Size=UDim2.new(0,12,0,12), Position=UDim2.new(0,xOff,0.5,-6),
                Parent=bar, AutoButtonColor=false,
            })
            create("UICorner",{ CornerRadius=UDim.new(1,0), Parent=b })
            b.MouseButton1Click:Connect(action or function() end)
            return b
        end
        dot(Color3.fromRGB(255,95,87),  12, function()
            tween(root,{Size=UDim2.new(0,520,0,0)},0.2).Completed:Connect(function() root:Destroy() end)
        end)
        dot(Color3.fromRGB(255,189,46), 30, function()
            tween(root,{Size=UDim2.new(0,520,0,32)},0.2)
        end)
        dot(Color3.fromRGB(39,201,63),  48, function()
            tween(root,{Size=UDim2.new(0,520,0,380)},0.2)
        end)

        create("TextLabel",{
            BackgroundTransparency=1, Size=UDim2.new(1,-140,1,0),
            Position=UDim2.new(0,70,0,0), Text=title,
            TextColor3=theme.TextPrimary, Font=Enum.Font.GothamMedium,
            TextSize=13, TextXAlignment=Enum.TextXAlignment.Left, Parent=bar,
        })

        local dragging, dragStart, frameStart = false, nil, nil
        bar.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
                dragging = true; dragStart = inp.Position; frameStart = root.Position
            end
        end)
        bar.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end)
        State.Connections.bind("Window_"..title, UIS.InputChanged:Connect(function(inp)
            if not dragging then return end
            if inp.UserInputType == Enum.UserInputType.MouseMovement
            or inp.UserInputType == Enum.UserInputType.Touch then
                local d = inp.Position - dragStart
                root.Position = UDim2.new(frameStart.X.Scale, frameStart.X.Offset + d.X,
                                          frameStart.Y.Scale, frameStart.Y.Offset + d.Y)
            end
        end))

        local content = create("ScrollingFrame",{
            BackgroundTransparency=1, BorderSizePixel=0,
            Position=UDim2.new(0,0,0,32), Size=UDim2.new(1,0,1,-32),
            CanvasSize=UDim2.new(0,0,0,0),
            AutomaticCanvasSize=Enum.AutomaticSize.Y,
            ScrollBarThickness=4, ScrollBarImageColor3=theme.Accent, Parent=root,
        })
        create("UIListLayout",{ Padding=UDim.new(0,6),
            SortOrder=Enum.SortOrder.LayoutOrder, Parent=content })
        create("UIPadding",{ PaddingTop=UDim.new(0,8), PaddingLeft=UDim.new(0,12),
            PaddingRight=UDim.new(0,12), PaddingBottom=UDim.new(0,12), Parent=content })

        W.Root, W.Bar, W.Content = root, bar, content
        function W:Destroy() root:Destroy(); State.Connections.clear("Window_"..title) end

        -- Compatibility shims for tab/section style used by original hub:
        function W:AddTab(name)         return W end   -- flat layout — return self
        function W:AddSection(name)
            local lbl = create("TextLabel",{
                BackgroundTransparency=1, Size=UDim2.new(1,0,0,22),
                Text="▾ "..name, Font=Enum.Font.GothamBold, TextSize=12,
                TextColor3=theme.AccentBright, TextXAlignment=Enum.TextXAlignment.Left,
                Parent=W.Content,
            })
            local sec = { _parent = W.Content }
            function sec:AddLabel(text)
                return create("TextLabel",{
                    BackgroundTransparency=1, Size=UDim2.new(1,0,0,18),
                    Text=text, Font=Enum.Font.Gotham, TextSize=12,
                    TextColor3=theme.TextSecondary,
                    TextXAlignment=Enum.TextXAlignment.Left, Parent=self._parent,
                })
            end
            return sec
        end
        return W
    end

    function M.Toggle(parent, label, initial, callback)
        local theme = State.Theme
        local row = create("Frame",{ BackgroundTransparency=1,
            Size=UDim2.new(1,0,0,28), Parent=parent })
        create("TextLabel",{ BackgroundTransparency=1, Size=UDim2.new(1,-60,1,0),
            Text=label, TextColor3=theme.TextPrimary, Font=Enum.Font.Gotham,
            TextSize=13, TextXAlignment=Enum.TextXAlignment.Left, Parent=row })
        local btn = create("TextButton",{ Text="", AutoButtonColor=false,
            BackgroundColor3 = initial and theme.Accent or theme.Surface,
            Size=UDim2.new(0,44,0,22), Position=UDim2.new(1,-50,0.5,-11), Parent=row })
        create("UICorner",{ CornerRadius=UDim.new(1,0), Parent=btn })
        local knob = create("Frame",{ BackgroundColor3=theme.TextPrimary,
            Size=UDim2.new(0,18,0,18),
            Position=initial and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9),
            BorderSizePixel=0, Parent=btn })
        create("UICorner",{ CornerRadius=UDim.new(1,0), Parent=knob })

        local state = initial
        local function flip()
            state = not state
            tween(btn,{BackgroundColor3 = state and theme.Accent or theme.Surface},0.2)
            tween(knob,{Position = state and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9)},0.2)
            callback(state)
        end
        btn.MouseButton1Click:Connect(flip)
        return { Set = function(_, v) if v ~= state then flip() end end, Get = function() return state end }
    end

    function M.Slider(parent, label, min, max, initial, callback)
        local theme = State.Theme
        local row = create("Frame",{ BackgroundTransparency=1,
            Size=UDim2.new(1,0,0,42), Parent=parent })
        local lbl = create("TextLabel",{ BackgroundTransparency=1,
            Size=UDim2.new(1,0,0,18),
            Text=("%s: %d"):format(label, initial),
            TextColor3=theme.TextPrimary, Font=Enum.Font.Gotham, TextSize=12,
            TextXAlignment=Enum.TextXAlignment.Left, Parent=row })
        local track = create("Frame",{ BackgroundColor3=theme.Surface, BorderSizePixel=0,
            Size=UDim2.new(1,0,0,6), Position=UDim2.new(0,0,0,26), Parent=row })
        create("UICorner",{ CornerRadius=UDim.new(1,0), Parent=track })
        local fill = create("Frame",{ BackgroundColor3=theme.Accent, BorderSizePixel=0,
            Size=UDim2.new((initial-min)/(max-min),0,1,0), Parent=track })
        create("UICorner",{ CornerRadius=UDim.new(1,0), Parent=fill })

        local dragging = false
        local function set(x)
            local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            local val = math.floor(min + rel * (max - min) + 0.5)
            fill.Size = UDim2.new((val-min)/(max-min),0,1,0)
            lbl.Text = ("%s: %d"):format(label, val)
            callback(val)
        end
        track.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
                dragging = true; set(inp.Position.X)
            end
        end)
        track.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end)
        State.Connections.bind("Slider_"..label, UIS.InputChanged:Connect(function(inp)
            if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement
                          or inp.UserInputType == Enum.UserInputType.Touch) then
                set(inp.Position.X)
            end
        end))
    end

    function M.Dropdown(parent, label, options, initial, callback)
        local theme = State.Theme
        local row = create("Frame",{ BackgroundTransparency=1,
            Size=UDim2.new(1,0,0,30), Parent=parent })
        create("TextLabel",{ BackgroundTransparency=1, Size=UDim2.new(0.5,0,1,0),
            Text=label, TextColor3=theme.TextPrimary, Font=Enum.Font.Gotham,
            TextSize=12, TextXAlignment=Enum.TextXAlignment.Left, Parent=row })
        local btn = create("TextButton",{
            BackgroundColor3=theme.Surface, BorderSizePixel=0,
            Size=UDim2.new(0.5,-4,1,-4), Position=UDim2.new(0.5,4,0,2),
            Text=initial, TextColor3=theme.TextPrimary, Font=Enum.Font.Gotham,
            TextSize=12, AutoButtonColor=false, Parent=row })
        create("UICorner",{ CornerRadius=UDim.new(0,6), Parent=btn })
        btn.MouseButton1Click:Connect(function()
            local idx = table.find(options, btn.Text) or 0
            local nextOpt = options[(idx % #options) + 1]
            btn.Text = nextOpt; callback(nextOpt)
        end)
    end

    return M
end)

-- ═══════════════════════════════════════════════════════════════════════
--  games/marvellous.lua  (roster/icons/skins/remotes — verbatim from V1)
-- ═══════════════════════════════════════════════════════════════════════
State.Register("games/marvellous.lua", function(State)
    local M = {}
    local RS = State.Services.ReplicatedStorage

    -- Dynamically load roster from ReplicatedStorage.Characters folder
    -- (matches original buildCounterEngine source).
    M.CharList = {}
    local function loadRoster()
        local folder = RS:FindFirstChild("Characters")
                    or RS:FindFirstChild("Chars")
                    or RS:FindFirstChild("CharacterModels")
        if not folder then
            folder = RS:WaitForChild("Characters", 5)
        end
        if folder then
            for _, ch in ipairs(folder:GetChildren()) do
                table.insert(M.CharList, ch.Name)
            end
            table.sort(M.CharList)
        end
    end
    loadRoster()

    -- NoCounter table (verbatim from original noCounterChars)
    M.NoCounter = {
        DarthVader   = "Darth Vader does not have an auto counter. His moveset doesn't use the standard CounterActivate remote, so the auto counter engine cannot be hooked into him.",
        Billy        = "Billy does not have a working auto counter in this build — his moveset doesn't expose a usable CounterActivate remote. You can still use his moves and finishers from the other tabs.",
        BillyButcher = "Billy Butcher does not have a working auto counter in this build — his moveset doesn't expose a usable CounterActivate remote. You can still use his moves and finishers from the other tabs.",
        ATrain       = "A-Train does not have a working auto counter in this build — his moveset doesn't expose a usable CounterActivate remote. You can still use his moves and finishers from the other tabs.",
        ["A-Train"]  = "A-Train does not have a working auto counter in this build — his moveset doesn't expose a usable CounterActivate remote. You can still use his moves and finishers from the other tabs.",
        Tram         = "A-Train (Tram) does not have a working auto counter in this build — his moveset doesn't expose a usable CounterActivate remote. You can still use his moves and finishers from the other tabs.",
    }

    -- Pennywise skins (verbatim)
    M.PennywiseSkins = {
        { id = "Skin1", index = 1, display = "Neibolt"    },
        { id = "Skin2", index = 2, display = "Derry"      },
        { id = "Skin3", index = 3, display = "Resting"    },
        { id = "Skin4", index = 4, display = "1935"       },
        { id = "Skin5", index = 5, display = "Old School" },
    }

    -- Icons (verbatim)
    M.Icons = {
        Dexter="🔵", Thragg="🔴", OmniMan="🟡", Invincible="🔵",
        Homelander="🔴", SpiderMan="🔵", Goku="🟠", Luffy="🔴",
        Eren="🟢", Kratos="⚪", DarthVader="⚫", Deku="🟢",
        Demogorgon="🟣", DoctorStrange="🟠", Ghostface="⚪",
        Gigachad="🟡", Gru="🟣", HumanTorch="🟠", Jeffrey="🟣",
        Juggernaut="🔴", Ken="🟡", Kira="⚫", MoonKnight="⚪",
        MrFantastic="🔵", Myers="⚫", OptimusPrime="🔵",
        Patrick="🟣", Paul="🟡", Peacemaker="🔵", Pennywise="🔴",
        ReverseFlash="🟡", SoldierBoy="🔵", Speed="🟡",
        Springtrap="⚫", SSB="🟡", StarLight="🟡", TheBatman="⚫",
        Thanos="🟣", Tram="🔵", Vecna="🟣", Vigilante="🔵",
        Wanda="🔴", Wednesday="⚫", Zodiac="🟣", Fibby="🟣",
        Iris="🔵", Joe="🟡", Miles="🔵", Springbonnie="🟢",
        Tate="🟣", Deep="🔵", Lawliet="⚫", Eddie="🟣",
        Physics="🔵", SlamModel="🟣", ["SCP-173"]="⚪",
        ["2099"]="🔵", Michael="🟣", Lyle="🟡", FrontMan="⚫",
    }
    function M.GetIcon(name) return M.Icons[name] or "🟣" end

    -- Remote bindings (graceful — works even before remotes spawn)
    local function findRemote(...)
        local names = {...}
        for _, n in ipairs(names) do
            local r = RS:FindFirstChild(n, true)
            if r then return r end
        end
        return nil
    end

    function M.SelectInGame(charName, skinId, skinIndex)
        local sel = findRemote("SelectCharacter", "Select", "ChooseCharacter")
        if sel then
            if sel:IsA("RemoteFunction") then
                pcall(function() sel:InvokeServer(charName, skinId or 1, skinIndex or 1) end)
            elseif sel:IsA("RemoteEvent") then
                pcall(function() sel:FireServer(charName, skinId or 1, skinIndex or 1) end)
            end
            return true
        end
        return false
    end

    -- Counter remote — found at runtime, cached.
    local cachedCounterRemote = nil
    local function getCounterRemote()
        if cachedCounterRemote and cachedCounterRemote.Parent then return cachedCounterRemote end
        cachedCounterRemote = findRemote("CounterActivate","CounterEvent","Counter","Parry")
        return cachedCounterRemote
    end
    function M.FireCounterRemote()
        local r = getCounterRemote()
        if r and r:IsA("RemoteEvent") then pcall(function() r:FireServer() end) end
    end

    -- Per-character counter timings. Names sourced dynamically;
    -- defaults applied to any char not explicitly overridden here.
    M.CounterDefs = setmetatable({
        Luffy   = { window=160, reach=8  },
        Zoro    = { window=140, reach=10 },
        Gojo    = { window=120, reach=14 },
        Sukuna  = { window=130, reach=12 },
        Mihawk  = { window=145, reach=11 },
        Goku    = { window=130, reach=12 },
        Eren    = { window=150, reach=9  },
        SpiderMan = { window=125, reach=10 },
        OmniMan = { window=140, reach=11 },
        Homelander = { window=135, reach=12 },
        SoldierBoy = { window=140, reach=11 },
        Kratos  = { window=150, reach=9  },
        Thanos  = { window=160, reach=10 },
        TheBatman = { window=150, reach=8 },
        DarthVader = { window=140, reach=10 },
        Pennywise = { window=145, reach=9 },
        Wanda     = { window=135, reach=12 },
        Vecna     = { window=140, reach=11 },
        DoctorStrange = { window=130, reach=13 },
        Kira      = { window=140, reach=8 },
        Lawliet   = { window=150, reach=7 },
    }, {
        -- Default fallback for any roster member without explicit timings
        __index = function() return { window = 150, reach = 9 } end,
    })

    -- Hook each definition's fire fn to the shared counter remote
    for _, def in pairs(M.CounterDefs) do
        if not def.fire then def.fire = function() M.FireCounterRemote() end end
    end

    function M.GenericCounter() M.FireCounterRemote() end

    return M
end)

-- ═══════════════════════════════════════════════════════════════════════
--  systems/hitbox.lua
-- ═══════════════════════════════════════════════════════════════════════
State.Register("systems/hitbox.lua", function(State)
    local M = {}
    local Helpers = State.Helpers

    function M.InRange(range, coneDot)
        if not Helpers.alive() then return nil end
        local myRoot = State.RootPart
        local myPos  = myRoot.Position
        local myFwd  = myRoot.CFrame.LookVector
        for _, e in ipairs(Helpers.enemies()) do
            local toEnemy = e.root.Position - myPos
            local d = toEnemy.Magnitude
            if d <= range then
                if not coneDot then return e, d end
                if toEnemy.Unit:Dot(myFwd) >= coneDot then return e, d end
            end
        end
        return nil
    end

    return M
end)

-- ═══════════════════════════════════════════════════════════════════════
--  systems/predcounter.lua
-- ═══════════════════════════════════════════════════════════════════════
State.Register("systems/predcounter.lua", function(State)
    local M = {}
    local Helpers = State.Helpers

    function M.TimeToReach(attackerRoot, reach)
        if not Helpers.alive() then return math.huge end
        local myRoot = State.RootPart
        local rel    = attackerRoot.Position - myRoot.Position
        local d      = rel.Magnitude
        if d <= reach then return 0 end
        local vRel = attackerRoot.AssemblyLinearVelocity - myRoot.AssemblyLinearVelocity
        local closing = -vRel:Dot(rel.Unit)
        if closing <= 0.1 then return math.huge end
        return (d - reach) / closing
    end

    function M.IsWindingUp(attackerHum)
        local startedAt = attackerHum:GetAttribute("AttackStart")
        if not startedAt then return false end
        local windupLen = attackerHum:GetAttribute("AttackWindup") or 0.25
        local elapsed = os.clock() - startedAt
        return elapsed >= 0 and elapsed <= windupLen
    end

    function M.ShouldFire(attackerRoot, attackerHum, reach, counterFrames)
        if not M.IsWindingUp(attackerHum) then return false end
        local ttr = M.TimeToReach(attackerRoot, reach)
        return ttr <= counterFrames
    end

    return M
end)

-- ═══════════════════════════════════════════════════════════════════════
--  systems/visuals.lua  (FPS boost / anti-lag)
-- ═══════════════════════════════════════════════════════════════════════
State.Register("systems/visuals.lua", function(State)
    local M = { enabled = false, snapshot = nil }
    local Lighting  = State.Services.Lighting
    local Workspace = State.Services.Workspace
    local Terrain   = Workspace:FindFirstChildOfClass("Terrain")

    local function snapshot()
        return {
            GlobalShadows = Lighting.GlobalShadows,
            FogEnd        = Lighting.FogEnd,
            Brightness    = Lighting.Brightness,
            WaterWave     = Terrain and Terrain.WaterWaveSize,
            WaterWaveSpd  = Terrain and Terrain.WaterWaveSpeed,
            WaterReflect  = Terrain and Terrain.WaterReflectance,
            Decoration    = Terrain and Terrain.Decoration,
        }
    end

    local function strip(inst)
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Smoke")
            or d:IsA("Fire") or d:IsA("Sparkles") then d.Enabled = false
            elseif d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 1
            elseif d:IsA("Explosion") then d.BlastPressure = 0
            end
        end
    end

    function M.Init() if State.Settings.fpsBoost then M.Enable() end end

    function M.Enable()
        if M.enabled then return end
        M.enabled = true
        M.snapshot = snapshot()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 1e6
        if Terrain then
            Terrain.WaterWaveSize = 0
            Terrain.WaterWaveSpeed = 0
            Terrain.WaterReflectance = 0
            Terrain.Decoration = false
        end
        strip(Workspace)
        State.Connections.bind("Visuals", Workspace.DescendantAdded:Connect(function(d)
            if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Smoke")
            or d:IsA("Fire") or d:IsA("Sparkles") then d.Enabled = false
            elseif d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 1 end
        end))
        State.Settings.fpsBoost = true; State.Config.Save()
        State.Notifications.notify("FPS Boost", "Enabled", 1.5)
    end

    function M.Disable()
        if not M.enabled then return end
        M.enabled = false
        State.Connections.clear("Visuals")
        if M.snapshot then
            Lighting.GlobalShadows = M.snapshot.GlobalShadows
            Lighting.FogEnd        = M.snapshot.FogEnd
            Lighting.Brightness    = M.snapshot.Brightness
            if Terrain then
                Terrain.WaterWaveSize    = M.snapshot.WaterWave
                Terrain.WaterWaveSpeed   = M.snapshot.WaterWaveSpd
                Terrain.WaterReflectance = M.snapshot.WaterReflect
                Terrain.Decoration       = M.snapshot.Decoration
            end
        end
        State.Settings.fpsBoost = false; State.Config.Save()
        State.Notifications.notify("FPS Boost", "Disabled", 1.5)
    end

    function M.Toggle() if M.enabled then M.Disable() else M.Enable() end end
    return M
end)

-- ═══════════════════════════════════════════════════════════════════════
--  systems/movement.lua  (shift-lock unlock)
-- ═══════════════════════════════════════════════════════════════════════
State.Register("systems/movement.lua", function(State)
    local M = { unlocked = false, savedAutoRot = nil }
    local UIS = State.Services.UserInputService

    function M.Init() if State.Settings.shiftLockUnlocked then M.Enable() end end

    function M.Enable()
        if M.unlocked then return end
        local hum = State.Humanoid; if not hum then return end
        M.savedAutoRot = hum.AutoRotate
        hum.AutoRotate = true
        UIS.MouseBehavior = Enum.MouseBehavior.Default
        M.unlocked = true
        State.Settings.shiftLockUnlocked = true; State.Config.Save()
        State.Notifications.notify("Shift Lock", "Unlocked — cursor is free! RMB still works.", 2)
    end

    function M.Disable()
        if not M.unlocked then return end
        UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
        M.unlocked = false
        State.Settings.shiftLockUnlocked = false; State.Config.Save()
        State.Notifications.notify("Shift Lock", "Re-enabled — cursor locked to center", 2)
    end

    function M.ToggleShiftLock() if M.unlocked then M.Disable() else M.Enable() end end
    return M
end)

-- ═══════════════════════════════════════════════════════════════════════
--  systems/autoblock.lua  (velocity-predicted block)
-- ═══════════════════════════════════════════════════════════════════════
State.Register("systems/autoblock.lua", function(State)
    local M = { active = false, holding = false, lastTap = 0 }
    local Helpers = State.Helpers
    local VIM     = State.Services.VirtualInputManager or game:GetService("VirtualInputManager")

    local function pressF(down)
        local kc = Enum.KeyCode[State.Settings.autoBlockKey or "F"] or Enum.KeyCode.F
        VIM:SendKeyEvent(down, kc, false, game)
    end
    local function holdOn()  if not M.holding then pressF(true);  M.holding = true  end end
    local function holdOff() if M.holding     then pressF(false); M.holding = false end end

    function M.Init()
        State.Dispatcher.OnHeartbeat("AutoBlock", function(_, now)
            if not M.active or not Helpers.alive() then holdOff(); return end
            local range = State.Settings.autoBlockRange or 12

            local Hitbox = State.Modules.Hitbox
            local Pred   = State.Modules.PredCounter
            local enemy, dist = Hitbox.InRange(range)
            if not enemy then holdOff(); return end

            local mode = State.Settings.autoBlockMode
            if mode == "tap" then
                if Pred.IsWindingUp(enemy.hum) and (now - M.lastTap) > 0.35 then
                    M.lastTap = now
                    pressF(true); task.wait(0.05); pressF(false)
                end
            else
                local ttr = Pred.TimeToReach(enemy.root, range * 0.7)
                if ttr <= 0.5 then holdOn() else holdOff() end
            end
        end, 1/30)

        if State.Settings.autoBlockEnabled then M.Enable() end
    end

    function M.Enable()
        M.active = true; State.Settings.autoBlockEnabled = true; State.Config.Save()
        State.Notifications.notify("Auto Block", "Enabled", 1.5)
    end
    function M.Disable()
        M.active = false; holdOff()
        State.Settings.autoBlockEnabled = false; State.Config.Save()
        State.Notifications.notify("Auto Block", "Disabled", 1.5)
    end
    function M.Toggle() if M.active then M.Disable() else M.Enable() end end

    return M
end)

-- ═══════════════════════════════════════════════════════════════════════
--  systems/targetlock.lua
-- ═══════════════════════════════════════════════════════════════════════
State.Register("systems/targetlock.lua", function(State)
    local M = { active = false, target = nil }
    local Helpers = State.Helpers

    function M.Init()
        State.Dispatcher.OnRender("TargetLock", function()
            if not M.active or not Helpers.alive() then return end
            local t = M.target
            if not t or not t.player.Parent or t.hum.Health <= 0 then
                t = Helpers.nearestEnemy(80); M.target = t
            end
            if not t then return end
            local myPos = State.RootPart.Position
            local look  = CFrame.lookAt(myPos, t.root.Position)
            local _, y, _ = look:ToOrientation()
            State.RootPart.CFrame = CFrame.new(myPos) * CFrame.Angles(0, y, 0)
        end, 1/60)
    end

    function M.Toggle()
        M.active = not M.active
        if M.active then M.target = Helpers.nearestEnemy(80) else M.target = nil end
        State.Settings.targetLockEnabled = M.active; State.Config.Save()
        State.Notifications.notify("Target Lock", M.active and "Locked" or "Released", 1.5)
    end

    return M
end)

-- ═══════════════════════════════════════════════════════════════════════
--  systems/autocounter.lua
-- ═══════════════════════════════════════════════════════════════════════
State.Register("systems/autocounter.lua", function(State)
    local M = { armed = true }
    local Helpers = State.Helpers

    local function fire()
        local now = os.clock()
        if (now - State.ActiveCounter.lastFire) < 0.2 then return end
        State.ActiveCounter.lastFire = now
        local def = State.GameData.CounterDefs[State.ActiveCounter.name or ""]
        if def and def.fire then def.fire(State) else State.GameData.GenericCounter(State) end
    end

    function M.Init()
        State.Dispatcher.OnHeartbeat("AutoCounter", function(_, now)
            if not M.armed or not State.Settings.predictiveCounter then return end
            if not Helpers.alive() then return end
            local reach     = State.ActiveCounter.reach  or 8
            local windowSec = (State.ActiveCounter.window or 150) / 1000
            local Pred = State.Modules.PredCounter

            for _, e in ipairs(Helpers.enemies()) do
                if Pred.ShouldFire(e.root, e.hum, reach, windowSec) then
                    fire(); return
                end
            end
        end, 1/60)
    end

    function M.FireManual() fire() end

    function M.LoadFor(charName)
        local Widgets = State.Widgets
        local GameData = State.GameData
        local create = State.Helpers.create_instance

        if GameData.NoCounter[charName] then
            local win = Widgets.CreateWindow("Moves — "..charName)
            create("TextLabel",{ BackgroundTransparency=1,
                Size=UDim2.new(1,0,0,60), TextWrapped=true,
                Text=GameData.NoCounter[charName],
                Font=Enum.Font.Gotham, TextSize=12,
                TextColor3=State.Theme.TextSecondary,
                TextXAlignment=Enum.TextXAlignment.Left,
                TextYAlignment=Enum.TextYAlignment.Top, Parent=win.Content })
            return win
        end

        local def = GameData.CounterDefs[charName]
        local win = Widgets.CreateWindow("Counter — "..charName)
        create("TextLabel",{ BackgroundTransparency=1, Size=UDim2.new(1,0,0,22),
            Text="Predictive Counter Engine",
            Font=Enum.Font.GothamBold, TextSize=14,
            TextColor3=State.Theme.AccentBright,
            TextXAlignment=Enum.TextXAlignment.Left, Parent=win.Content })

        Widgets.Toggle(win.Content, "Enable", true, function(v) M.armed = v end)
        Widgets.Toggle(win.Content, "Predictive timing", State.Settings.predictiveCounter,
            function(v) State.Settings.predictiveCounter = v; State.Config.Save() end)
        Widgets.Slider(win.Content, "Reach", 4, 20, def and def.reach or 8, function(v)
            State.ActiveCounter.reach = v
        end)
        Widgets.Slider(win.Content, "Parry window (ms)", 50, 350, def and def.window or 150, function(v)
            State.ActiveCounter.window = v
        end)

        State.ActiveCounter.name   = charName
        State.ActiveCounter.window = (def and def.window) or 150
        State.ActiveCounter.reach  = (def and def.reach)  or 8

        -- Pennywise skin selector
        if charName == "Pennywise" then
            create("TextLabel",{ BackgroundTransparency=1, Size=UDim2.new(1,0,0,22),
                Text="Skins", Font=Enum.Font.GothamBold, TextSize=13,
                TextColor3=State.Theme.AccentBright,
                TextXAlignment=Enum.TextXAlignment.Left, Parent=win.Content })
            for _, skin in ipairs(GameData.PennywiseSkins) do
                local btn = create("TextButton",{
                    BackgroundColor3=State.Theme.Surface, BorderSizePixel=0,
                    Size=UDim2.new(1,0,0,26), Text=skin.display,
                    TextColor3=State.Theme.TextPrimary, Font=Enum.Font.Gotham,
                    TextSize=12, AutoButtonColor=false, Parent=win.Content,
                })
                create("UICorner",{ CornerRadius=UDim.new(0,6), Parent=btn })
                btn.MouseButton1Click:Connect(function()
                    GameData.SelectInGame("Pennywise", skin.id, skin.index)
                    State.Notifications.notify("Pennywise","Skin: "..skin.display, 1.5)
                end)
            end
        end

        return win
    end

    return M
end)

-- ═══════════════════════════════════════════════════════════════════════
--  ui/mainui.lua
-- ═══════════════════════════════════════════════════════════════════════
State.Register("ui/mainui.lua", function(State)
    local M = {}
    local mainWin, searchBox, filterText = nil, nil, ""

    local function row(parent, name)
        local Widgets = State.Widgets
        local create  = State.Helpers.create_instance
        local theme   = State.Theme
        local r = create("TextButton",{
            BackgroundColor3=theme.Surface, BorderSizePixel=0,
            Size=UDim2.new(1,0,0,36), Text="", AutoButtonColor=false, Parent=parent,
        })
        create("UICorner",{ CornerRadius=UDim.new(0,8), Parent=r })

        create("TextLabel",{ BackgroundTransparency=1,
            Position=UDim2.new(0,12,0,0), Size=UDim2.new(0,28,1,0),
            Text=State.GameData.GetIcon(name), Font=Enum.Font.GothamBold,
            TextSize=18, TextColor3=theme.TextPrimary, Parent=r })

        create("TextLabel",{ BackgroundTransparency=1,
            Position=UDim2.new(0,46,0,0), Size=UDim2.new(1,-100,1,0),
            Text=name, Font=Enum.Font.GothamMedium, TextSize=13,
            TextColor3=theme.TextPrimary,
            TextXAlignment=Enum.TextXAlignment.Left, Parent=r })

        local star = create("TextButton",{ BackgroundTransparency=1,
            Size=UDim2.new(0,24,1,0), Position=UDim2.new(1,-30,0,0),
            Text=State.Settings.favorites[name] and "★" or "☆",
            TextColor3=theme.Warning, Font=Enum.Font.GothamBold,
            TextSize=18, Parent=r })
        star.MouseButton1Click:Connect(function()
            if State.Settings.favorites[name] then
                State.Settings.favorites[name] = nil
            else
                State.Settings.favorites[name] = true
            end
            star.Text = State.Settings.favorites[name] and "★" or "☆"
            State.Config.Save(); M.Refresh()
        end)

        r.MouseButton1Click:Connect(function()
            State.Modules.AutoCounter.LoadFor(name)
        end)
        return r
    end

    function M.Init()
        mainWin = State.Widgets.CreateWindow("✦ ACH V2 • FMC Playground")
        local create = State.Helpers.create_instance
        local theme  = State.Theme

        -- Search box
        local searchFrame = create("Frame",{
            BackgroundColor3=theme.Surface, BorderSizePixel=0,
            Size=UDim2.new(1,0,0,30), Parent=mainWin.Content,
        })
        create("UICorner",{ CornerRadius=UDim.new(0,6), Parent=searchFrame })
        searchBox = create("TextBox",{
            BackgroundTransparency=1, Size=UDim2.new(1,-16,1,0),
            Position=UDim2.new(0,8,0,0), PlaceholderText="Search character...",
            Text="", TextColor3=theme.TextPrimary,
            PlaceholderColor3=theme.TextMuted, Font=Enum.Font.Gotham,
            TextSize=13, ClearTextOnFocus=false,
            TextXAlignment=Enum.TextXAlignment.Left, Parent=searchFrame,
        })
        searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            filterText = searchBox.Text:lower(); M.Refresh()
        end)

        -- Settings panel (toggles + profile dropdown)
        local Widgets = State.Widgets
        create("TextLabel",{ BackgroundTransparency=1,
            Size=UDim2.new(1,0,0,20), Text="Quick Settings",
            Font=Enum.Font.GothamBold, TextSize=13,
            TextColor3=theme.AccentBright,
            TextXAlignment=Enum.TextXAlignment.Left, Parent=mainWin.Content })
        Widgets.Toggle(mainWin.Content, "FPS Boost", State.Settings.fpsBoost, function(v)
            if v then State.Modules.Visuals.Enable() else State.Modules.Visuals.Disable() end
        end)
        Widgets.Toggle(mainWin.Content, "Notifications", State.Settings.notifications, function(v)
            State.Settings.notifications = v; State.Config.Save()
        end)
        Widgets.Toggle(mainWin.Content, "Watermark", State.Settings.watermark, function(v)
            State.Settings.watermark = v; State.Config.Save()
        end)
        Widgets.Slider(mainWin.Content, "Auto Block Range", 6, 30,
            State.Settings.autoBlockRange, function(v)
                State.Settings.autoBlockRange = v; State.Config.Save()
            end)
        Widgets.Dropdown(mainWin.Content, "Auto Block Mode",
            {"hold","tap"}, State.Settings.autoBlockMode, function(opt)
                State.Settings.autoBlockMode = opt; State.Config.Save()
            end)
        Widgets.Dropdown(mainWin.Content, "Profile",
            State.Profiles.List(), State.Settings.activeProfile or "Default",
            function(opt) State.Profiles.Load(opt) end)

        M.Refresh()
    end

    function M.Refresh()
        if not mainWin then return end
        local create = State.Helpers.create_instance
        local theme = State.Theme
        -- Clear roster section only
        for _, c in ipairs(mainWin.Content:GetChildren()) do
            if c:GetAttribute("RosterItem") then c:Destroy() end
        end

        local function add(node) node:SetAttribute("RosterItem", true); return node end

        local favList = {}
        for n,v in pairs(State.Settings.favorites) do if v then table.insert(favList, n) end end
        table.sort(favList)
        if #favList > 0 then
            add(create("TextLabel",{ BackgroundTransparency=1, Size=UDim2.new(1,0,0,20),
                Text="★ Favorites", Font=Enum.Font.GothamBold, TextSize=12,
                TextColor3=theme.Warning, TextXAlignment=Enum.TextXAlignment.Left,
                Parent=mainWin.Content }))
            for _, n in ipairs(favList) do
                if filterText == "" or n:lower():find(filterText, 1, true) then
                    add(row(mainWin.Content, n))
                end
            end
        end

        add(create("TextLabel",{ BackgroundTransparency=1, Size=UDim2.new(1,0,0,20),
            Text=("Roster (%d)"):format(#State.GameData.CharList),
            Font=Enum.Font.GothamBold, TextSize=12,
            TextColor3=theme.TextSecondary, TextXAlignment=Enum.TextXAlignment.Left,
            Parent=mainWin.Content }))

        for _, n in ipairs(State.GameData.CharList) do
            if not State.Settings.favorites[n] then
                if filterText == "" or n:lower():find(filterText, 1, true) then
                    add(row(mainWin.Content, n))
                end
            end
        end
    end

    function M.IsVisible()  return mainWin and mainWin.Root.Visible or false end
    function M.SetVisible(v) if mainWin then mainWin.Root.Visible = v end end

    function M.ToggleShowcase()
        State.Showcase.active = not State.Showcase.active
        State.Notifications.notify("Showcase",
            State.Showcase.active and "Enabled — UI hidden, watermark only" or "Disabled", 2)
        if mainWin then mainWin.Root.Visible = not State.Showcase.active end
    end

    return M
end)

-- ═══════════════════════════════════════════════════════════════════════
--  BOOTSTRAP — load all modules in dependency order
-- ═══════════════════════════════════════════════════════════════════════
local Helpers       = State.Require("utils/helpers.lua")       ; State.Helpers       = Helpers
local Connections   = State.Require("utils/connections.lua")   ; State.Connections   = Connections
local Config        = State.Require("utils/config.lua")        ; State.Config        = Config; State.Settings = Config.Settings
local Profiles      = State.Require("utils/profiles.lua")      ; State.Profiles      = Profiles
local Themes        = State.Require("ui/themes.lua")           ; State.Themes        = Themes; State.Theme = Themes.Current
local Notifications = State.Require("ui/notifications.lua")    ; State.Notifications = Notifications
local Wallpaper     = State.Require("ui/wallpaper.lua")        ; State.Wallpaper     = Wallpaper
local Widgets       = State.Require("ui/widgets.lua")          ; State.Widgets       = Widgets
local GameData      = State.Require("games/marvellous.lua")    ; State.GameData      = GameData

local Visuals     = State.Require("systems/visuals.lua")
local Movement    = State.Require("systems/movement.lua")
local Hitbox      = State.Require("systems/hitbox.lua")
local PredCounter = State.Require("systems/predcounter.lua")
local AutoCounter = State.Require("systems/autocounter.lua")
local AutoBlock   = State.Require("systems/autoblock.lua")
local TargetLock  = State.Require("systems/targetlock.lua")

State.Modules = {
    Visuals=Visuals, Movement=Movement, Hitbox=Hitbox, PredCounter=PredCounter,
    AutoCounter=AutoCounter, AutoBlock=AutoBlock, TargetLock=TargetLock,
}

-- ═══════════════════════════════════════════════════════════════════════
--  CENTRALIZED UPDATE DISPATCHER (ONE Heartbeat + ONE RenderStepped)
-- ═══════════════════════════════════════════════════════════════════════
local Dispatcher = {}
local hbSubs, rsSubs = State.Subscribers.heartbeat, State.Subscribers.render
function Dispatcher.OnHeartbeat(name, fn, interval)
    table.insert(hbSubs, {name=name, fn=fn, interval=interval or 0, lastRun=0})
end
function Dispatcher.OnRender(name, fn, interval)
    table.insert(rsSubs, {name=name, fn=fn, interval=interval or 0, lastRun=0})
end
function Dispatcher.Remove(name)
    for _, list in ipairs({hbSubs, rsSubs}) do
        for i = #list, 1, -1 do if list[i].name == name then table.remove(list, i) end end
    end
end
State.Dispatcher = Dispatcher

local clock = os.clock
Connections.bind("__dispatcher", RunService.Heartbeat:Connect(function(dt)
    local now = clock()
    for i = 1, #hbSubs do
        local s = hbSubs[i]
        if s.interval == 0 or (now - s.lastRun) >= s.interval then
            s.lastRun = now
            local ok, err = pcall(s.fn, dt, now)
            if not ok then warn("[ACHv2:"..s.name.."]", err) end
        end
    end
end))
Connections.bind("__dispatcher", RunService.RenderStepped:Connect(function(dt)
    local now = clock()
    for i = 1, #rsSubs do
        local s = rsSubs[i]
        if s.interval == 0 or (now - s.lastRun) >= s.interval then
            s.lastRun = now
            local ok, err = pcall(s.fn, dt, now)
            if not ok then warn("[ACHv2:"..s.name.."]", err) end
        end
    end
end))

-- ═══════════════════════════════════════════════════════════════════════
--  CHARACTER CACHE
-- ═══════════════════════════════════════════════════════════════════════
local function bindCharacter(char)
    State.Character = char
    State.Humanoid  = char:WaitForChild("Humanoid", 5)
    State.RootPart  = char:WaitForChild("HumanoidRootPart", 5)
end
if State.Player.Character then bindCharacter(State.Player.Character) end
Connections.bind("__core", State.Player.CharacterAdded:Connect(bindCharacter))
Connections.bind("__core", State.Player.CharacterRemoving:Connect(function()
    State.Character, State.Humanoid, State.RootPart = nil, nil, nil
end))

-- ═══════════════════════════════════════════════════════════════════════
--  UI SHELL + MODULE INIT
-- ═══════════════════════════════════════════════════════════════════════
State.ScreenGui = Wallpaper.Mount()
Notifications.Init()
Themes.ApplyTo(State.ScreenGui)
local MainUI = State.Require("ui/mainui.lua"); State.MainUI = MainUI
MainUI.Init()

for _, m in pairs(State.Modules) do if m.Init then m.Init() end end

-- ═══════════════════════════════════════════════════════════════════════
--  GLOBAL INPUT HANDLER (single InputBegan → dispatch to modules)
-- ═══════════════════════════════════════════════════════════════════════
local function typing() return UIS:GetFocusedTextBox() ~= nil end
local function kbName(k) return tostring(k):gsub("Enum.KeyCode.","") end

Connections.bind("__input", UIS.InputBegan:Connect(function(inp, gp)
    if gp or typing() then return end
    local key = inp.KeyCode
    local kb  = State.Settings.Keybinds

    if key == kb.ToggleGUI  then MainUI.SetVisible(not MainUI.IsVisible())   end
    if key == kb.Counter    then AutoCounter.FireManual()                    end
    if key == kb.ShiftLock  then Movement.ToggleShiftLock()                  end
    if key == kb.AutoBlock  then AutoBlock.Toggle()                          end
    if key == kb.TargetLock then TargetLock.Toggle()                         end
    if key == kb.Showcase   then MainUI.ToggleShowcase()                     end
end))

-- ═══════════════════════════════════════════════════════════════════════
--  READY
-- ═══════════════════════════════════════════════════════════════════════
State.Loaded = true
Notifications.notify("✦ ACH V2",
    ("Loaded! Counter: %s | GUI: %s | Shift Lock: %s | Auto Block: %s"):format(
        kbName(State.Settings.Keybinds.Counter),
        kbName(State.Settings.Keybinds.ToggleGUI),
        kbName(State.Settings.Keybinds.ShiftLock),
        kbName(State.Settings.Keybinds.AutoBlock)
    ), 5)

print(("✅ ACH V2 (FMC Playground) modular | %d chars | floriszxfloris")
    :format(#GameData.CharList))

return State

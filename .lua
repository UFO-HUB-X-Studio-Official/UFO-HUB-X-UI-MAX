--===== UFO HUB X • Home – Remote Monitor Launcher (Lazy Create + Auto Destroy) =====
-- Adds:
--  - Header: "Security"
--  - Row: "Remote Monitor" with ▶ button
-- Behavior:
--  - Panel is CREATED only when opened
--  - Panel is DESTROYED when closed (no leftovers)
--  - Leaving game / LP removed => auto cleanup

registerRight("Home", function(scroll)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local TweenService = game:GetService("TweenService")
    local LP = Players.LocalPlayer

    -- ===== Theme (match your style) =====
    local THEME = {
        GREEN = Color3.fromRGB(25,255,125),
        RED   = Color3.fromRGB(255,40,40),
        WHITE = Color3.fromRGB(255,255,255),
        GRAY  = Color3.fromRGB(200,200,200),
        BLACK = Color3.fromRGB(0,0,0),
        DARK  = Color3.fromRGB(10,10,10),
    }

    local function corner(ui,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 12); c.Parent=ui end
    local function stroke(ui,t,col) local s=Instance.new("UIStroke"); s.Thickness=t or 2.2; s.Color=col or THEME.GREEN; s.Parent=ui end
    local function tween(o,p,d) TweenService:Create(o,TweenInfo.new(d or 0.10,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),p):Play() end

    -- ===== cleanup only our nodes (header/row + old panel if any) =====
    for _,n in ipairs({"SEC_Header","SEC_Row_RemoteMon","UFOX_RemoteMonPanel"}) do
        local o = scroll:FindFirstChild(n)
        if o then o:Destroy() end
    end

    -- ===== ensure ONE list layout =====
    local list = scroll:FindFirstChildOfClass("UIListLayout")
    if not list then
        list = Instance.new("UIListLayout", scroll)
        list.Padding = UDim.new(0,12)
        list.SortOrder = Enum.SortOrder.LayoutOrder
    end
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

    -- ===== dynamic base layout order (your baseline) =====
    local base = 0
    for _,c in ipairs(scroll:GetChildren()) do
        if c:IsA("GuiObject") and c ~= list then
            base = math.max(base, c.LayoutOrder or 0)
        end
    end

    -- ===== header =====
    local header = Instance.new("TextLabel")
    header.Name = "SEC_Header"
    header.Parent = scroll
    header.Size = UDim2.new(1,0,0,36)
    header.BackgroundTransparency = 1
    header.Font = Enum.Font.GothamBold
    header.TextSize = 16
    header.TextColor3 = THEME.WHITE
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Text = "Security"
    header.LayoutOrder = base + 1

    -- ===== Remote refs (server must create these) =====
    local function getMonitorRemotes()
        local MON = ReplicatedStorage:FindFirstChild("_UFOX_MONITOR")
        if not MON then return nil end
        local RF_GET = MON:FindFirstChild("GetLogs")
        local RF_ISADMIN = MON:FindFirstChild("IsAdmin")
        local RE_PUSH = MON:FindFirstChild("Push")
        local RE_CMD = MON:FindFirstChild("Cmd")
        return MON, RF_GET, RF_ISADMIN, RE_PUSH, RE_CMD
    end

    local function isAdmin(RF_ISADMIN)
        if not (RF_ISADMIN and RF_ISADMIN:IsA("RemoteFunction")) then return false end
        local ok, v = pcall(function() return RF_ISADMIN:InvokeServer() end)
        return ok and v == true
    end

    -- ===== helpers =====
    local function norm(s)
        s = tostring(s or ""):lower()
        s = s:gsub("%s+"," ")
        return s
    end

    -- ===== state =====
    local panel -- created lazily
    local cards = {}
    local liveConn -- RE_PUSH connection

    local function destroyPanel()
        if liveConn then
            pcall(function() liveConn:Disconnect() end)
            liveConn = nil
        end
        for _, v in ipairs(cards) do
            if v and v.Parent then v:Destroy() end
        end
        table.clear(cards)
        if panel and panel.Parent then panel:Destroy() end
        panel = nil
    end

    -- auto cleanup when leaving / LP removed
    do
        local ok = pcall(function()
            LP.AncestryChanged:Connect(function(_, parent)
                if parent == nil then
                    destroyPanel()
                end
            end)
        end)
    end

    -- ===== create panel lazily =====
    local function createPanel(MON, RF_GET, RE_PUSH, RE_CMD)
        if panel and panel.Parent then return panel end

        panel = Instance.new("Frame")
        panel.Name = "UFOX_RemoteMonPanel"
        panel.Parent = scroll
        panel.Size = UDim2.new(1,-6,0,360)
        panel.BackgroundColor3 = THEME.DARK
        panel.BorderSizePixel = 0
        corner(panel, 12)
        stroke(panel, 2.2, THEME.GREEN)
        panel.LayoutOrder = base + 3

        local top = Instance.new("Frame", panel)
        top.BackgroundTransparency = 1
        top.Size = UDim2.new(1,0,0,38)

        local title = Instance.new("TextLabel", top)
        title.BackgroundTransparency = 1
        title.Position = UDim2.new(0,12,0,0)
        title.Size = UDim2.new(1,-24,1,0)
        title.Font = Enum.Font.GothamBold
        title.TextSize = 15
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.TextColor3 = THEME.WHITE
        title.Text = "Remote Monitor"

        local search = Instance.new("TextBox", panel)
        search.Position = UDim2.new(0,12,0,44)
        search.Size = UDim2.new(1,-24,0,30)
        search.PlaceholderText = "ค้นหา: player / remote / args / path"
        search.Text = ""
        search.ClearTextOnFocus = false
        search.Font = Enum.Font.Gotham
        search.TextSize = 13
        search.TextColor3 = THEME.WHITE
        search.BackgroundColor3 = THEME.BLACK
        corner(search, 10)
        stroke(search, 1.6, THEME.GREEN)

        local btnClear = Instance.new("TextButton", panel)
        btnClear.Position = UDim2.new(0,12,1,-38)
        btnClear.Size = UDim2.fromOffset(120,28)
        btnClear.Text = "Clear"
        btnClear.Font = Enum.Font.GothamBold
        btnClear.TextSize = 13
        btnClear.TextColor3 = THEME.WHITE
        btnClear.BackgroundColor3 = THEME.BLACK
        btnClear.AutoButtonColor = false
        corner(btnClear, 10)
        stroke(btnClear, 1.6, THEME.RED)

        local btnRefresh = Instance.new("TextButton", panel)
        btnRefresh.Position = UDim2.new(0,140,1,-38)
        btnRefresh.Size = UDim2.fromOffset(120,28)
        btnRefresh.Text = "Refresh"
        btnRefresh.Font = Enum.Font.GothamBold
        btnRefresh.TextSize = 13
        btnRefresh.TextColor3 = THEME.WHITE
        btnRefresh.BackgroundColor3 = THEME.BLACK
        btnRefresh.AutoButtonColor = false
        corner(btnRefresh, 10)
        stroke(btnRefresh, 1.6, THEME.GREEN)

        local listFrame = Instance.new("ScrollingFrame", panel)
        listFrame.Position = UDim2.new(0,12,0,82)
        listFrame.Size = UDim2.new(1,-24,1,-126)
        listFrame.BackgroundTransparency = 1
        listFrame.ScrollBarThickness = 6
        listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
        listFrame.CanvasSize = UDim2.new(0,0,0,0)

        local lay = Instance.new("UIListLayout", listFrame)
        lay.Padding = UDim.new(0,8)
        lay.SortOrder = Enum.SortOrder.LayoutOrder

        local function makeCard(e)
            local f = Instance.new("Frame")
            f.Size = UDim2.new(1,0,0,92)
            f.BackgroundColor3 = THEME.BLACK
            f.BorderSizePixel = 0
            corner(f,12)

            local st = Instance.new("UIStroke", f)
            st.Thickness = 1.6
            st.Color = (e.suspicious and THEME.RED) or THEME.GREEN

            local t = Instance.new("TextLabel", f)
            t.BackgroundTransparency = 1
            t.Position = UDim2.new(0,12,0,8)
            t.Size = UDim2.new(1,-24,0,18)
            t.Font = Enum.Font.GothamBold
            t.TextSize = 13
            t.TextXAlignment = Enum.TextXAlignment.Left
            t.TextColor3 = THEME.WHITE
            t.Text = string.format("[%s] %s • %s", e.kind or "?", e.remote or "?", e.time or "?")

            local p = Instance.new("TextLabel", f)
            p.BackgroundTransparency = 1
            p.Position = UDim2.new(0,12,0,28)
            p.Size = UDim2.new(1,-24,0,18)
            p.Font = Enum.Font.Gotham
            p.TextSize = 12
            p.TextXAlignment = Enum.TextXAlignment.Left
            p.TextColor3 = THEME.GRAY
            p.Text = string.format("player: %s | rate:%s | path: %s", e.player or "?", tostring(e.rate or 0), e.path or "?")

            local a = Instance.new("TextLabel", f)
            a.BackgroundTransparency = 1
            a.Position = UDim2.new(0,12,0,48)
            a.Size = UDim2.new(1,-24,0,40)
            a.Font = Enum.Font.Code
            a.TextSize = 12
            a.TextWrapped = true
            a.TextXAlignment = Enum.TextXAlignment.Left
            a.TextYAlignment = Enum.TextYAlignment.Top
            a.TextColor3 = THEME.WHITE
            a.Text = "args: " .. tostring(e.args or "")

            f:SetAttribute("_q", norm(e.kind).." "..norm(e.remote).." "..norm(e.path).." "..norm(e.player).." "..norm(e.args))
            return f
        end

        local function rebuild(logs)
            for _, v in ipairs(cards) do
                if v and v.Parent then v:Destroy() end
            end
            table.clear(cards)

            for i = 1, #logs do
                local e = logs[i]
                local card = makeCard(e)
                card.LayoutOrder = i
                card.Parent = listFrame
                cards[#cards+1] = card
            end
        end

        local function applyFilter()
            local q = norm(search.Text)
            for _, f in ipairs(cards) do
                local hay = f:GetAttribute("_q") or ""
                f.Visible = (q == "" or hay:find(q, 1, true) ~= nil)
            end
        end
        search:GetPropertyChangedSignal("Text"):Connect(applyFilter)

        local function refreshLogs()
            if not (RF_GET and RF_GET:IsA("RemoteFunction")) then return end
            local ok, logs = pcall(function() return RF_GET:InvokeServer() end)
            if ok and typeof(logs) == "table" then
                rebuild(logs)
                applyFilter()
            end
        end

        btnRefresh.MouseButton1Click:Connect(refreshLogs)

        btnClear.MouseButton1Click:Connect(function()
            if RE_CMD and RE_CMD:IsA("RemoteEvent") then
                RE_CMD:FireServer("clear")
            end
            task.wait(0.1)
            refreshLogs()
        end)

        -- live push (only while panel exists)
        if RE_PUSH and RE_PUSH:IsA("RemoteEvent") then
            liveConn = RE_PUSH.OnClientEvent:Connect(function(e)
                if not (panel and panel.Parent) then return end
                local card = makeCard(e)
                card.LayoutOrder = (#cards + 1)
                card.Parent = listFrame
                cards[#cards+1] = card
                applyFilter()
            end)
        end

        -- initial load
        task.defer(refreshLogs)

        return panel
    end

    -- ===== Row button (▶) =====
    local row = Instance.new("Frame")
    row.Name = "SEC_Row_RemoteMon"
    row.Parent = scroll
    row.Size = UDim2.new(1,-6,0,46)
    row.BackgroundColor3 = THEME.BLACK
    corner(row,12)
    stroke(row,2.2,THEME.GREEN)
    row.LayoutOrder = base + 2

    local lab = Instance.new("TextLabel", row)
    lab.BackgroundTransparency = 1
    lab.Position = UDim2.new(0,16,0,0)
    lab.Size = UDim2.new(1,-160,1,0)
    lab.Font = Enum.Font.GothamBold
    lab.TextSize = 13
    lab.TextColor3 = THEME.WHITE
    lab.TextXAlignment = Enum.TextXAlignment.Left
    lab.Text = "Remote Monitor"

    local btn = Instance.new("TextButton", row)
    btn.AnchorPoint = Vector2.new(1,0.5)
    btn.Position = UDim2.new(1,-14,0.5,0)
    btn.Size = UDim2.fromOffset(26,26)
    btn.BackgroundTransparency = 1
    btn.Text = "▶"
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 18
    btn.TextColor3 = THEME.WHITE
    btn.AutoButtonColor = false

    btn.MouseButton1Click:Connect(function()
        local MON, RF_GET, RF_ISADMIN, RE_PUSH, RE_CMD = getMonitorRemotes()
        if not MON then
            warn("[UFOX] _UFOX_MONITOR not found (server monitor not running).")
            return
        end
        if not isAdmin(RF_ISADMIN) then
            warn("[UFOX] Not admin for Remote Monitor.")
            return
        end

        if panel and panel.Parent then
            -- close = destroy (no leftovers)
            destroyPanel()
        else
            -- open = create
            createPanel(MON, RF_GET, RE_PUSH, RE_CMD)
        end
    end)
end)

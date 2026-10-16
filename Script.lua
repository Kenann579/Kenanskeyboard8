local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local VIM = game:GetService("VirtualInputManager")
local HTTP = game:GetService("HttpService")
local LAYOUT_FILE = "MobileKeyboardLayout.json"
local CONFIG_FILE = "MobileKeyboardConfigs.json"

local function getParent()
    local ok, ui = pcall(function() return gethui() end)
    if ok and ui then return ui end
    ok, ui = pcall(function() return game:GetService("CoreGui") end)
    if ok and ui then return ui end
    return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local Parent = getParent()
for _, n in ipairs({ "MobileKeyboard", "MobileKeyboardBoot" }) do
    local o = Parent:FindFirstChild(n)
    if o then o:Destroy() end
end

-- Status box (loading / errors)
local Boot = Instance.new("ScreenGui")
Boot.Name = "MobileKeyboardBoot"
Boot.ResetOnSpawn = false
Boot.IgnoreGuiInset = true
Boot.DisplayOrder = 999
Boot.Parent = Parent

local Msg = Instance.new("TextButton")
Msg.Size = UDim2.new(0, 320, 0, 36)
Msg.Position = UDim2.new(0.5, -160, 0, 70)
Msg.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
Msg.BorderSizePixel = 0
Msg.AutoButtonColor = false
Msg.Text = "Keyboard loading..."
Msg.TextColor3 = Color3.new(1, 1, 1)
Msg.TextSize = 14
Msg.TextWrapped = true
Msg.Parent = Boot
Msg.Activated:Connect(function() Boot:Destroy() end)

local function showErr(text)
    Msg.Size = UDim2.new(0, 420, 0, 130)
    Msg.Position = UDim2.new(0.5, -210, 0, 70)
    Msg.TextColor3 = Color3.fromRGB(255, 130, 130)
    Msg.Text = text .. " (tap to close)"
    warn(text)
end

local cfgErr = nil

local ok, err = pcall(function()

local Gui = Instance.new("ScreenGui")
Gui.Name = "MobileKeyboard"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = true
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = Parent

local KEYCOL = Color3.fromRGB(45, 45, 55)
local PRESS = Color3.fromRGB(50, 200, 100)
local SPAWNCOL = Color3.new(0, 0, 0)

-- UI helpers
local function btn(par, txt, x, y, w, h, col, ts, z, r)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, w, 0, h)
    b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = col
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Text = txt
    b.TextColor3 = Color3.new(1, 1, 1)
    b.TextSize = ts
    b.ZIndex = z or 100
    b.Active = true
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, r or 5)
    b.Parent = par
    return b
end

local function lbl(par, txt, x, y, w, h, ts)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0, w, 0, h)
    l.Position = UDim2.new(0, x, 0, y)
    l.BackgroundTransparency = 1
    l.Text = txt
    l.TextColor3 = Color3.new(1, 1, 1)
    l.TextSize = ts
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.ZIndex = 131
    l.Parent = par
    return l
end

-- Key sending (ref-counted)
local held = {}
local function key(k, down)
    if not k then return end
    if down then
        held[k] = (held[k] or 0) + 1
        if held[k] == 1 then pcall(VIM.SendKeyEvent, VIM, true, k, false, game) end
    elseif held[k] then
        held[k] = held[k] - 1
        if held[k] <= 0 then
            held[k] = nil
            pcall(VIM.SendKeyEvent, VIM, false, k, false, game)
        end
    end
end

-- Pointer tracking (touch + mouse) so keys always release
local active = {}
local function isPointer(i)
    return i.UserInputType == Enum.UserInputType.Touch
        or i.UserInputType == Enum.UserInputType.MouseButton1
end
local function track(input, fn)
    local e = { input = input, fn = fn }
    table.insert(active, e)
    return e
end
UIS.InputEnded:Connect(function(input)
    if not isPointer(input) then return end
    for n = #active, 1, -1 do
        local e = active[n]
        if e.input == input or (input.UserInputType == Enum.UserInputType.MouseButton1
            and e.input.UserInputType == Enum.UserInputType.MouseButton1) then
            table.remove(active, n)
            e.fn()
        end
    end
end)
local function releaseAll()
    for n = #active, 1, -1 do
        local e = table.remove(active, n)
        e.fn()
    end
    for k in pairs(held) do pcall(VIM.SendKeyEvent, VIM, false, k, false, game) end
    held = {}
end
local function p2(i) return Vector2.new(i.Position.X, i.Position.Y) end

-- Dragging with tap detection
local function drag(gui, onTap)
    local e, start, from, moved
    gui.InputBegan:Connect(function(input)
        if not isPointer(input) or e then return end
        start, from, moved = p2(input), gui.Position, false
        e = track(input, function()
            local tap = not moved
            e = nil
            if tap and onTap then onTap() end
        end)
    end)
    UIS.InputChanged:Connect(function(input)
        if not e then return end
        if input == e.input or input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = p2(input) - start
            if not moved and d.Magnitude > 10 then moved = true end
            if moved then
                gui.Position = UDim2.new(from.X.Scale, from.X.Offset + d.X, from.Y.Scale, from.Y.Offset + d.Y)
            end
        end
    end)
end

-- Toggle button + keyboard panel
local Toggle = btn(Gui, "⌨", 0, 0, 50, 50, Color3.fromRGB(80, 150, 255), 22, 100, 10)
Toggle.Position = UDim2.new(0.5, -25, 0, 10)

local Panel = Instance.new("Frame")
Panel.Size = UDim2.new(0, 680, 0, 190)
Panel.AnchorPoint = Vector2.new(0.5, 0)
Panel.Position = UDim2.new(0.5, 0, 0, 70)
Panel.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
Panel.BorderSizePixel = 0
Panel.Visible = false
Panel.ZIndex = 99
Panel.Active = true
Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 8)
Panel.Parent = Gui

local UIScaleObj = Instance.new("UIScale", Panel)
local cam = workspace.CurrentCamera
if cam then UIScaleObj.Scale = math.clamp((cam.ViewportSize.X - 20) / 680, 0.4, 1) end

local isOpen = false
drag(Toggle, function()
    isOpen = not isOpen
    Panel.Visible = isOpen
    Toggle.BackgroundColor3 = isOpen and PRESS or Color3.fromRGB(80, 150, 255)
    if not isOpen then releaseAll() end
end)
drag(Panel)

-- Layout saving
local locked = false
local isAdding = false
local spawnN = 0

local function collect()
    local s = Gui.AbsoluteSize
    if s.X <= 0 or s.Y <= 0 then return nil end
    local list = {}
    for _, c in ipairs(Gui:GetChildren()) do
        if c.Name == "CustomSpawnedBtn" then
            table.insert(list, {
                text = c.Text, key = c:GetAttribute("KeyName") or "",
                w = c.Size.X.Offset, h = c.Size.Y.Offset,
                sx = c.AbsolutePosition.X / s.X, sy = c.AbsolutePosition.Y / s.Y,
            })
        end
    end
    return list
end

local function saveLayout()
    if not writefile then return end
    local list = collect()
    if not list then return end
    pcall(function()
        writefile(LAYOUT_FILE, HTTP:JSONEncode({ locked = locked, buttons = list }))
    end)
end

-- Generated ("+") buttons
local function spawn(text, code, w, h, pos, exact)
    spawnN = spawnN + 1
    local off = (spawnN % 6) * 14
    if not exact then
        w = math.max((w or 50) * 1.3, 60)
        h = math.max((h or 40) * 1.6, 52)
    end
    local b = btn(Gui, text, 0, 0, w, h, SPAWNCOL, 17, 110, 8)
    b.Name = "CustomSpawnedBtn"
    b.Position = pos or UDim2.new(0.5, -w / 2 + off, 0.5, -h / 2 + off)
    b.BackgroundTransparency = 0.45
    b:SetAttribute("KeyName", code and code.Name or "")

    local x = btn(b, "X", 0, 0, 14, 14, Color3.fromRGB(220, 50, 50), 8, 115, 7)
    x.Name = "DeleteBtn"
    x.Position = UDim2.new(1, -9, 0, -5)
    x.Visible = not locked

    local e, start, from, moved
    local pressed = false
    local function release()
        if pressed then
            pressed = false
            key(code, false)
            b.BackgroundColor3 = SPAWNCOL
        end
    end

    b.InputBegan:Connect(function(input)
        if not isPointer(input) or e then return end
        start, from, moved = p2(input), b.Position, false
        e = track(input, function()
            local m = moved
            e = nil
            release()
            if m then saveLayout() end
        end)
        if code then
            pressed = true
            key(code, true)
            b.BackgroundColor3 = PRESS
        end
    end)

    local conn = UIS.InputChanged:Connect(function(input)
        if not e or locked then return end
        if input == e.input or input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = p2(input) - start
            if not moved and d.Magnitude > 10 then
                moved = true
                release()
            end
            if moved then
                b.Position = UDim2.new(from.X.Scale, from.X.Offset + d.X, from.Y.Scale, from.Y.Offset + d.Y)
            end
        end
    end)

    x.Activated:Connect(function()
        release()
        b:Destroy()
        saveLayout()
    end)
    b.Destroying:Connect(function()
        release()
        conn:Disconnect()
    end)

    if not exact then task.delay(0.3, saveLayout) end
end

-- Keyboard keys
local function makeKey(label, code, w, h, x, y)
    local b = btn(Panel, label, x, y, w, h, KEYCOL, 11, 100, 4)
    local e
    b.InputBegan:Connect(function(input)
        if not isPointer(input) or e then return end
        if isAdding then
            spawn(label, code, w, h)
            return
        end
        key(code, true)
        b.BackgroundColor3 = PRESS
        e = track(input, function()
            e = nil
            key(code, false)
            b.BackgroundColor3 = KEYCOL
        end)
    end)
end

local NUM = { ["1"] = "One", ["2"] = "Two", ["3"] = "Three", ["4"] = "Four", ["5"] = "Five",
    ["6"] = "Six", ["7"] = "Seven", ["8"] = "Eight", ["9"] = "Nine", ["0"] = "Zero" }
local SYM = { ["`"] = "Backquote", ["-"] = "Minus", ["="] = "Equals", ["["] = "LeftBracket",
    ["]"] = "RightBracket", ["\\"] = "BackSlash", [";"] = "Semicolon", ["'"] = "Quote",
    [","] = "Comma", ["."] = "Period", ["/"] = "Slash" }

local function row(y, h, gap, dw, items)
    local x = 10
    for _, it in ipairs(items) do
        local label, name, w
        if type(it) == "table" then
            label, name, w = it[1], it[2], it[3]
        else
            label, name, w = it, NUM[it] or SYM[it] or it, dw
        end
        makeKey(label, Enum.KeyCode[name], w, h, x, y)
        x = x + w + gap
    end
end

row(8, 24, 5, 35, { { "Esc", "Escape", 40 }, "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12" })
row(36, 26, 3, 38, { "`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=" })
row(64, 26, 3, 38, { { "Tab", "Tab", 50 }, "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", { "\\", "BackSlash", 45 } })
row(92, 26, 3, 38, { { "Caps", "CapsLock", 58 }, "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", { "Enter", "Return", 75 } })
row(120, 26, 3, 38, { { "Shift", "LeftShift", 70 }, "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", { "RShift", "RightShift", 70 } })
row(148, 26, 3, 38, { { "Ctrl", "LeftControl", 55 }, { "Alt", "LeftAlt", 50 }, { "Spacebar", "Space", 220 },
    { "Alt", "RightAlt", 50 }, { "Ctrl", "RightControl", 55 }, { "◄", "Left", 38 }, { "▼", "Down", 38 }, { "►", "Right", 38 } })

-- "+" button
local AddB = btn(Panel, "+", 535, 8, 40, 24, Color3.fromRGB(150, 50, 200), 14, 100, 4)
AddB.Activated:Connect(function()
    isAdding = not isAdding
    AddB.BackgroundColor3 = isAdding and Color3.fromRGB(220, 180, 50) or Color3.fromRGB(150, 50, 200)
end)

-- Lock button
local LockB = btn(Panel, "Unlocked", 580, 8, 90, 24, Color3.fromRGB(70, 110, 200), 12, 100, 4)
local function setLocked(state, noSave)
    locked = state
    LockB.Text = locked and "Locked" or "Unlocked"
    LockB.BackgroundColor3 = locked and Color3.fromRGB(50, 160, 90) or Color3.fromRGB(70, 110, 200)
    for _, c in ipairs(Gui:GetChildren()) do
        if c.Name == "CustomSpawnedBtn" then
            local x = c:FindFirstChild("DeleteBtn")
            if x then x.Visible = not locked end
        end
    end
    if not noSave then saveLayout() end
end
LockB.Activated:Connect(function() setLocked(not locked) end)

-- Rebuild buttons from saved data
local function applyButtons(list, lockState)
    for _, c in ipairs(Gui:GetChildren()) do
        if c.Name == "CustomSpawnedBtn" then c:Destroy() end
    end
    for _, b in ipairs(list or {}) do
        local code
        if b.key and b.key ~= "" then
            local okK, v = pcall(function() return Enum.KeyCode[b.key] end)
            if okK then code = v end
        end
        spawn(b.text, code, b.w, b.h, UDim2.new(b.sx, 0, b.sy, 0), true)
    end
    setLocked(lockState and true or false, true)
end

-- Configs: 5 slots
local ok2, e2 = pcall(function()
    local cfg = {}
    if isfile and readfile then
        pcall(function()
            if isfile(CONFIG_FILE) then cfg = HTTP:JSONDecode(readfile(CONFIG_FILE)) end
        end)
    end
    if type(cfg) ~= "table" then cfg = {} end
    local function write()
        if not writefile then return false end
        return (pcall(function() writefile(CONFIG_FILE, HTTP:JSONEncode(cfg)) end))
    end

    local Win = Instance.new("Frame")
    Win.Size = UDim2.new(0, 320, 0, 276)
    Win.AnchorPoint = Vector2.new(0.5, 0.5)
    Win.Position = UDim2.new(0.5, 0, 0.5, 0)
    Win.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    Win.BorderSizePixel = 0
    Win.Visible = false
    Win.ZIndex = 130
    Win.Active = true
    Instance.new("UICorner", Win).CornerRadius = UDim.new(0, 8)
    Win.Parent = Gui
    drag(Win)

    lbl(Win, "Configs", 12, 8, 150, 26, 16)
    local CloseB = btn(Win, "X", 284, 8, 28, 24, Color3.fromRGB(200, 50, 50), 12, 131)
    CloseB.Activated:Connect(function() Win.Visible = false end)
    local Status = lbl(Win, "", 12, 244, 296, 24, 12)
    Status.TextColor3 = Color3.fromRGB(200, 200, 210)

    local labels = {}
    local function refresh()
        for i = 1, 5 do
            local s = cfg[tostring(i)]
            labels[i].Text = "Slot " .. i .. ": " .. ((s and s.buttons) and (#s.buttons .. " btns") or "empty")
        end
    end

    for i = 1, 5 do
        local y = 40 + (i - 1) * 40
        local id = tostring(i)
        labels[i] = lbl(Win, "", 12, y, 115, 34, 13)
        local saveB = btn(Win, "Save", 130, y, 54, 34, Color3.fromRGB(70, 110, 200), 13, 131)
        local loadB = btn(Win, "Load", 190, y, 54, 34, Color3.fromRGB(50, 160, 90), 13, 131)
        local delB = btn(Win, "Del", 250, y, 54, 34, Color3.fromRGB(200, 60, 60), 13, 131)
        local sure = false

        saveB.Activated:Connect(function()
            local list = collect()
            if not list then Status.Text = "Screen not ready, try again" return end
            cfg[id] = { locked = locked, buttons = list }
            if write() then
                Status.Text = "Saved to Slot " .. i .. " (" .. #list .. " btns)"
            else
                Status.Text = "Can't save file (no writefile)"
            end
            refresh()
        end)

        loadB.Activated:Connect(function()
            local s = cfg[id]
            if not s or not s.buttons then Status.Text = "Slot " .. i .. " is empty" return end
            applyButtons(s.buttons, s.locked)
            task.delay(0.3, saveLayout)
            Status.Text = "Loaded Slot " .. i
        end)

        delB.Activated:Connect(function()
            if not cfg[id] then Status.Text = "Slot " .. i .. " is already empty" return end
            if not sure then
                sure = true
                delB.Text = "Sure?"
                task.delay(2, function() sure = false delB.Text = "Del" end)
                return
            end
            sure = false
            delB.Text = "Del"
            cfg[id] = nil
            write()
            refresh()
            Status.Text = "Deleted Slot " .. i
        end)
    end
    refresh()

    local CfgB = btn(Panel, "Configs", 580, 36, 90, 26, Color3.fromRGB(210, 130, 40), 12, 100, 4)
    CfgB.Activated:Connect(function() Win.Visible = not Win.Visible end)
end)
if not ok2 then cfgErr = "Configs error (keyboard still works): " .. tostring(e2) end

-- Load last session's layout
if isfile and readfile then
    pcall(function()
        if isfile(LAYOUT_FILE) then
            local data = HTTP:JSONDecode(readfile(LAYOUT_FILE))
            if type(data) == "table" then applyButtons(data.buttons, data.locked) end
        end
    end)
end

end)

if ok and not cfgErr then
    Boot:Destroy()
elseif ok then
    showErr(cfgErr)
else
    showErr("Keyboard error: " .. tostring(err))
end

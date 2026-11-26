-- Diagnostico visual independente. Nao envia entradas nem pedidos de venda.
local pg = game:GetService('Players').LocalPlayer:WaitForChild('PlayerGui')
local old = pg:FindFirstChild('PegasusDiagnostico')
if old then old:Destroy() end
local gui = Instance.new('ScreenGui')
gui.Name = 'PegasusDiagnostico'
gui.IgnoreGuiInset = true
gui.DisplayOrder = 10000
gui.ResetOnSpawn = false
gui.Parent = pg
local function frame(color, size)
 local f = Instance.new('Frame')
 f.BackgroundColor3 = color
 f.BorderSizePixel = 0
 f.Size = size
 f.Active = false
 f.Parent = gui
 return f
end
local outline = frame(Color3.fromRGB(40,255,100), UDim2.fromOffset(0,0))
outline.BackgroundTransparency = 1
local stroke = Instance.new('UIStroke', outline)
stroke.Color = Color3.fromRGB(40,255,100)
stroke.Thickness = 3
local dot = frame(Color3.fromRGB(255,45,45), UDim2.fromOffset(10,10))
dot.AnchorPoint = Vector2.new(.5,.5)
local corner = Instance.new('UICorner',dot)
corner.CornerRadius = UDim.new(1,0)
local info = Instance.new('TextLabel',gui)
info.Size = UDim2.fromOffset(390,100)
info.Position = UDim2.fromOffset(12,65)
info.BackgroundColor3 = Color3.fromRGB(20,20,30)
info.TextColor3 = Color3.new(1,1,1)
info.TextSize = 14
info.TextWrapped = true
info.Active = false
local function visible(o)
 while o and o ~= pg do
  if o:IsA('GuiObject') and not o.Visible then return false end
  if o:IsA('ScreenGui') and not o.Enabled then return false end
  o = o.Parent
 end
 return o == pg
end
local function label(b)
 local t = b:FindFirstChild('_Texto')
 return t and t:IsA('TextLabel') and t.Text or b.Text
end
while gui.Parent do
 local tela = pg:FindFirstChild('PescaTelas')
 local matches = {}
 if tela then
  for _, b in ipairs(tela:GetDescendants()) do
   if b:IsA('TextButton') and visible(b) and b.Interactable and b.AbsoluteSize.X > 0 and b.LayoutOrder == 2 and (b.Text == 'Vender o inventário de peixes' or label(b) == 'Vender o inventário de peixes') then
    table.insert(matches,b)
   end
  end
 end
 local b = #matches == 1 and matches[1] or nil
 outline.Visible = b ~= nil
 dot.Visible = b ~= nil
 if b then
  local p,s = b.AbsolutePosition,b.AbsoluteSize
  local x,y = math.floor(p.X+s.X/2+.5),math.floor(p.Y+s.Y/2+.5)
  outline.Position = UDim2.fromOffset(p.X,p.Y)
  outline.Size = UDim2.fromOffset(s.X,s.Y)
  dot.Position = UDim2.fromOffset(x,y)
  info.Text = string.format('%s\nLayoutOrder: %d | Centro: %d, %d\nIgnoreGuiInset: %s | Diagnostico sem clique',label(b),b.LayoutOrder,x,y,tostring(tela:IsA('ScreenGui') and tela.IgnoreGuiInset))
 else
  info.Text = 'Abra a conversa com Juca. Botoes correspondentes: '..#matches
 end
 task.wait(.15)
end

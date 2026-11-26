
--==================================================
-- PEGASUS HUB V9.8
-- Generic Voice Game
--==================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Pesca = ReplicatedStorage:WaitForChild("Pesca")
local Pedido = Pesca:WaitForChild("Pedido")
local Evento = Pesca:WaitForChild("Evento")
local Config = require(Pesca:WaitForChild("Config"))

--==================================================
-- CONFIGURACOES
--==================================================

local TEMPO_CARGA = 1.05
local TEMPO_ENTRE_PESCAS = 2
local TEMPO_FISGADA = 0.12
local TEMPO_RESULTADO = 5

local ANTECIPACAO_PEIXE = 0.08
local ANTECIPACAO_BARRA = 0.25
local SUAVIZACAO = 8
local ZONA_MORTA = 6
local INTERVALO_CONTROLE = 0.05
local INTERVALO_MOUSE = 0.08

--==================================================
-- TELEPORT LOCATIONS
-- Adicione novos locais nesta tabela
--==================================================

local Locations = {
    {
        Nome = "Topo Escada Espiral",
        Posicao = Vector3.new(170, 5100, 5)
    },
    { Nome = "Lago", Posicao = Vector3.new(85.7377472, 3.1899991, 52.333786), Orientacao = CFrame.new(85.7377472, 3.1899991, 52.333786, -0.996407866, -7.94384434e-08, 0.0846837088, -8.35050216e-08, 1, -4.44786821e-08, -0.0846837088, -5.13904261e-08, -0.996407866) }
}

--==================================================
-- ESTADOS
--==================================================

local fishingLocation = Locations[2].Orientacao
local ligado = false
local estado = "livre"
local mousePressionado = false

local ultimaPesca = 0
local inicioCaptura = 0
local fimResultado = 0
local ultimoControle = 0
local ultimaMudancaMouse = 0

local ultimoPeixeY = nil
local ultimaBarraY = nil
local velocidadePeixe = 0
local velocidadeBarra = 0

local antiAFK = false
local flyAtivo = false
local speedAtivo = false

local flySpeed = 50
local walkSpeed = 32

local jogadorSelecionado = nil
local flyVelocity = nil
local flyGyro = nil
local velocidadeOriginal = nil

local autoSell = false
local vendendo = false
local vendaManual = false
local cestoAtual = nil
local vendas = 0
local totalVendido = 0
local statusVenda = "Aguardando consulta"
local proximaConsulta = 0
local autoTreasure = false
local bauCompleto = false
local buscandoBau = false
local bausCapturados = 0
local ultimoAlvo = nil
local peixesCapturados = 0
local eventosAFK = 0

--==================================================
-- CONTROLE DO MOUSE
--==================================================

local function mouse(down)
    if mousePressionado == down then
        return
    end

    local camera = workspace.CurrentCamera
    if not camera then return end

    local viewport = camera.ViewportSize

    VirtualInputManager:SendMouseButtonEvent(
        viewport.X / 2,
        viewport.Y / 2,
        0,
        down,
        game,
        0
    )

    mousePressionado = down
    ultimaMudancaMouse = os.clock()
end

local function clique()
    if vendendo or not ligado then return end

    mouse(false)
    mouse(true)

    task.wait(TEMPO_FISGADA)

    if estado == "fisgando" then
        mouse(false)
    end
end

local function resetarControle()
    ultimoAlvo = nil
    buscandoBau = false
    ultimoPeixeY = nil
    ultimaBarraY = nil

    velocidadePeixe = 0
    velocidadeBarra = 0

    ultimoControle = 0

    mouse(false)
end

--==================================================
-- DETECTAR VARA
--==================================================

local function pegarVara()
    local character = Player.Character

    if not character then
        return nil
    end

    for _, objeto in ipairs(character:GetChildren()) do
        if objeto:IsA("Tool")
            and objeto:GetAttribute("VaraId") ~= nil then

            return objeto
        end
    end

    return nil
end

--==================================================
-- INTERFACE ORIGINAL DA PESCA
--==================================================

local function obterHUD()
    return PlayerGui:FindFirstChild("PescaHUD")
end

local function obterCaptura()
    local hud = obterHUD()

    if not hud then return nil end

    local captura = hud:FindFirstChild("Captura", true)

    if captura and captura:IsA("GuiObject") then
        if captura.Visible and hud.Enabled then
            return captura
        end
    end

    return nil
end

local function encontrarElementos()
    local captura = obterCaptura()
    if not captura then return end
    local peixe, bau, barra, progresso
    for _, obj in ipairs(captura:GetDescendants()) do
        if obj:IsA("ImageLabel") then
            if obj.Image == Config.ICONES.peixe and obj.Parent:IsA("GuiObject")
                and obj.Parent.Visible and obj.Parent.ZIndex == 4 then peixe = obj.Parent end
            if obj.Image == Config.ICONES.bau and obj.Parent:IsA("GuiObject")
                and obj.Parent.Visible then bau = obj.Parent end
        end
    end
    if not peixe then return end
    local campo = peixe.Parent
    for _, obj in ipairs(campo:GetChildren()) do
        if obj:IsA("Frame") and obj.ZIndex == 2 and obj.AnchorPoint.Y == 1
            and obj.Size.X.Scale == 1 and obj.Size.Y.Scale > 0 then
            barra = obj
            break
        end
    end
    for _, obj in ipairs(captura:GetDescendants()) do
        if obj:IsA("Frame") and obj.Size.X.Offset == 16 and obj.Size.Y.Offset == 324 then
            for _, filho in ipairs(obj:GetChildren()) do
                if filho:IsA("Frame") and filho.AnchorPoint.Y == 1 and filho.Size.X.Scale == 1 then
                    progresso = filho.Size.Y.Scale
                    break
                end
            end
        end
    end
    if bau and bau.Visible then
        local escala = bau:FindFirstChildOfClass("UIScale")
        if escala and escala.Scale < 0.98 and os.clock() - inicioCaptura > 0.7 then
            bauCompleto = true
        end
    else
        bau = nil
    end
    return peixe, barra, bau, progresso
end

--==================================================
-- CONTROLADOR DE CAPTURA V4
--==================================================

local function controlarLuta()
    local agora = os.clock()
    local dt = agora - ultimoControle

    if dt < INTERVALO_CONTROLE then
        return
    end

    ultimoControle = agora

    local peixe, barra, bau, progresso = encontrarElementos()

    if not peixe or not barra then
        resetarControle()
        ultimoControle = agora
        return
    end

    local peixeCentro = peixe.AbsolutePosition.Y + peixe.AbsoluteSize.Y / 2
    local alvo = peixe
    buscandoBau = false
    if autoTreasure and bau and not bauCompleto then
        local bauCentro = bau.AbsolutePosition.Y + bau.AbsoluteSize.Y / 2
        local juntos = math.abs(bauCentro - peixeCentro) < barra.AbsoluteSize.Y * 0.85
        if juntos or (progresso and progresso >= (ultimoAlvo == bau and 0.28 or 0.68)) then
            alvo = bau
            buscandoBau = true
        end
    end
    local peixeY = alvo.AbsolutePosition.Y + alvo.AbsoluteSize.Y / 2
    if buscandoBau and math.abs(peixeY - peixeCentro) < barra.AbsoluteSize.Y * 0.85 then
        peixeY = (peixeY + peixeCentro) / 2
    end
    if ultimoAlvo ~= alvo then
        ultimoAlvo = alvo
        ultimoPeixeY = nil
    end

    local barraY = barra.AbsolutePosition.Y
        + barra.AbsoluteSize.Y / 2

    if not ultimoPeixeY
        or not ultimaBarraY
        or dt > 0.5 then

        ultimoPeixeY = peixeY
        ultimaBarraY = barraY

        velocidadePeixe = 0
        velocidadeBarra = 0

        return
    end

    local alpha = math.clamp(
        dt * SUAVIZACAO,
        0,
        1
    )

    local novaVelPeixe =
        (peixeY - ultimoPeixeY) / dt

    local novaVelBarra =
        (barraY - ultimaBarraY) / dt

    velocidadePeixe = velocidadePeixe
        + (novaVelPeixe - velocidadePeixe) * alpha

    velocidadeBarra = velocidadeBarra
        + (novaVelBarra - velocidadeBarra) * alpha

    ultimoPeixeY = peixeY
    ultimaBarraY = barraY

    local peixePrevisto = peixeY + math.clamp(
        velocidadePeixe * ANTECIPACAO_PEIXE,
        -20,
        20
    )

    local barraPrevista = barraY + math.clamp(
        velocidadeBarra * ANTECIPACAO_BARRA,
        -65,
        65
    )

    local erro = peixePrevisto - barraPrevista

    if agora - ultimaMudancaMouse < INTERVALO_MOUSE then
        return
    end

    if erro < -ZONA_MORTA then

        mouse(true)

    elseif erro > ZONA_MORTA then

        mouse(false)

    else

        local velocidadeRelativa =
            velocidadeBarra - velocidadePeixe

        if velocidadeRelativa < -25 then
            mouse(false)

        elseif velocidadeRelativa > 25 then
            mouse(true)
        end
    end
end

--==================================================
-- LANCAMENTO AUTOMATICO
--==================================================

local function lancar()
    if vendendo or not ligado or estado ~= "livre" then
        return
    end

    if not pegarVara() then
        return
    end

    estado = "carregando"
    ultimaPesca = os.clock()

    mouse(true)

    task.wait(TEMPO_CARGA)

    if not ligado or not pegarVara() then
        mouse(false)
        estado = "livre"
        return
    end

    estado = "espera"

    mouse(false)
end

--==================================================
-- EVENTOS DA PESCA
--==================================================

Evento.OnClientEvent:Connect(function(acao, dados)
    if not ligado then return end

    if acao == "Mordida" then

        if estado == "espera"
            or estado == "lancando" then

            estado = "fisgando"
            inicioCaptura = os.clock()

            task.spawn(clique)
        end

    elseif acao == "Luta" then

        bauCompleto = false

        resetarControle()

        estado = "luta"
        inicioCaptura = os.clock()

    elseif acao == "Pegou" then

        resetarControle()

        peixesCapturados += 1
        if bauCompleto then bausCapturados += 1 end
        bauCompleto = false

        estado = "mostrando"
        fimResultado = os.clock() + TEMPO_RESULTADO

    elseif acao == "Escapou" then
        bauCompleto = false

        resetarControle()
        estado = "espera"

    elseif acao == "Parou" then

        resetarControle()

        if estado ~= "mostrando" then
            estado = "livre"
            ultimaPesca = os.clock()
        end
    end
end)

--==================================================
-- ANTI AFK INDEPENDENTE
--==================================================

local ultimoAFK = 0
local statusAFK = "Aguardando"
local function executarAFK()
    if not antiAFK or vendendo or mousePressionado or UserInputService:GetFocusedTextBox() then return end
    if os.clock() - ultimoAFK < 60 then return end
    ultimoAFK = os.clock()
    local ok, erro = pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
    if not ok then
        ok, erro = pcall(function()
            local camera = workspace.CurrentCamera
            local pos = camera.ViewportSize / 2
            VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 1, true, game, 0)
            VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 1, false, game, 0)
        end)
    end
    if ok then
        eventosAFK += 1
        statusAFK = "Entrada enviada"
    else
        statusAFK = "Falha (ver console)"
        warn("[PEGASUS] Anti-AFK: " .. tostring(erro))
    end
end
Player.Idled:Connect(executarAFK)
task.spawn(function()
    while true do
        task.wait(5)
        executarAFK()
    end
end)

--==================================================
-- PERSONAGEM
--==================================================

local function obterPersonagem()
    local char = Player.Character

    if not char then
        return nil, nil, nil
    end

    return char,
        char:FindFirstChildOfClass("Humanoid"),
        char:FindFirstChild("HumanoidRootPart")
end

-- AUTO SELL: consulta e venda pelo fluxo identificado em PescaTelas
local consultandoCesto = false
local function consultarCesto(tentativas)
    if consultandoCesto then error("Consulta do cesto em andamento") end
    consultandoCesto = true
    local ok, dados = pcall(function()
        for i = 1, tentativas or 1 do
            local sucesso, resposta = pcall(function() return Pedido:InvokeServer("Dados") end)
            if sucesso and type(resposta) == "table" and type(resposta.peixes) == "table" then
                return resposta
            end
            if i < (tentativas or 1) then task.wait(0.6) end
        end
        error("Dados do cesto indisponiveis")
    end)
    consultandoCesto = false
    if not ok then error(dados) end
    cestoAtual = #dados.peixes
    return cestoAtual, dados
end

local function visivel(obj)
    while obj and obj ~= PlayerGui do
        if obj:IsA("GuiObject") and not obj.Visible then return false end
        if obj:IsA("ScreenGui") and not obj.Enabled then return false end
        obj = obj.Parent
    end
    return obj == PlayerGui
end
local function mensagemVenda(prefixo)
    local tela = PlayerGui:FindFirstChild("PescaTelas")
    if not tela then return nil end
    for _, obj in ipairs(tela:GetDescendants()) do
        if obj:IsA("TextLabel") and visivel(obj) and obj.Text:sub(1, #prefixo) == prefixo then
            return obj.Text
        end
    end
end
local function botaoVendaVisivel(texto)
    local tela = PlayerGui:FindFirstChild("PescaTelas")
    if not tela then return nil end
    local ordem = texto == "Vender o inventário de peixes" and 2 or (texto == "Vender tudo" and 1 or nil)
    for _, obj in ipairs(tela:GetDescendants()) do
        if obj:IsA("TextButton") and visivel(obj) and obj.Interactable and obj.AbsoluteSize.X > 0 and (not ordem or obj.LayoutOrder == ordem) then
            local rotulo = obj:FindFirstChild("_Texto")
            if obj.Text == texto or (rotulo and rotulo:IsA("TextLabel") and rotulo.Text == texto) then return obj end
        end
    end
end
local function aguardarVenda(fn, segundos, erro)
    local limite = os.clock() + segundos
    repeat
        if not vendaManual and not autoSell then error("Venda cancelada") end
        local resultado = fn()
        if resultado then return resultado end
        task.wait(0.15)
    until os.clock() >= limite
    error(erro)
end
local function clicarVenda(botao, esperado)
    if not botao or botaoVendaVisivel(esperado) ~= botao then error("Botao incorreto: " .. esperado) end
    local pos = botao.AbsolutePosition + botao.AbsoluteSize / 2
    -- Hit testing uses GUI coordinates; input may use the inset-adjusted origin.
    local x, y = math.floor(pos.X + 0.5), math.floor(pos.Y + 0.5)
    local objetos = PlayerGui:GetGuiObjectsAtPosition(x, y)
    local primeiro
    for _, objeto in ipairs(objetos) do
        if objeto:IsA("GuiButton") then primeiro = objeto; break end
        local pai = objeto:FindFirstAncestorWhichIsA("GuiButton")
        if pai then primeiro = pai; break end
    end
    if primeiro ~= botao then error("Clique bloqueado ou alvo incorreto: " .. esperado) end
    local inset = GuiService:GetGuiInset()
    local ix = math.floor(x + inset.X + 0.5)
    local iy = math.floor(y + inset.Y + 0.5)
    print(string.format("[PEGASUS] %s | GUI %d,%d | inset %s | entrada %d,%d", esperado, x, y, tostring(inset), ix, iy))
    VirtualInputManager:SendMouseMoveEvent(ix, iy, game)
    task.wait(0.15)
    if botaoVendaVisivel(esperado) ~= botao then error("Menu mudou antes do clique") end
    VirtualInputManager:SendMouseButtonEvent(ix, iy, 0, true, game, 0)
    task.wait(0.12)
    VirtualInputManager:SendMouseButtonEvent(ix, iy, 0, false, game, 0)
end
local function cicloVenda(manual)
    vendaManual = manual == true
    local char, humanoid, root = obterPersonagem()
    local origem, hub, hubOrdem, varaSalva
    local ok, motivo = pcall(function()
        statusVenda = "Verificando cesto"
        aguardarVenda(function() return not consultandoCesto end, 8, "Consulta anterior ainda em andamento")
        local quantidade = consultarCesto(10)
        if quantidade == 0 then statusVenda = "Cesto vazio"; return end
        if not manual and quantidade < Config.MAXIMO_NO_CESTO then
            statusVenda = "Aguardando cesto cheio"
            return
        end
        if not manual and not autoSell then return end
        if not root or not humanoid or humanoid.Health <= 0 or flyAtivo then error("Personagem indisponivel ou Fly ativo") end
        local barraca = workspace:FindFirstChild("BarracaDePesca")
        local conversa = barraca and barraca:FindFirstChild("Conversa")
        local prompt = conversa and conversa:FindFirstChildOfClass("ProximityPrompt")
        if not prompt or not conversa:IsA("BasePart") then error("Prompt do Juca nao encontrado") end
        origem = root.CFrame
        resetarControle()
        varaSalva = pegarVara()
        if varaSalva then
            statusVenda = "Guardando vara"
            humanoid:UnequipTools()
            aguardarVenda(function()
                return Player.Character == char and not pegarVara()
            end, 4, "Nao foi possivel guardar a vara")
            task.wait(0.5)
        end
        statusVenda = "Indo ao Juca"
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        root.CFrame = conversa.CFrame * CFrame.new(0, 0, -4) + Vector3.new(0, 2, 0)
        task.wait(1.5)
        aguardarVenda(function()
            return Player.Character == char and humanoid.Health > 0 and (root.Position-conversa.Position).Magnitude <= prompt.MaxActivationDistance
        end, 4, "Fora do alcance do Juca")
        statusVenda = "Iniciando conversa"
        if not botaoVendaVisivel("Vender o inventário de peixes") then
            aguardarVenda(function() return prompt.Enabled end, 3, "Prompt desabilitado")
            VirtualInputManager:SendKeyEvent(true, prompt.KeyboardKeyCode, false, game)
            task.wait(math.max(0.2, prompt.HoldDuration + 0.15))
            VirtualInputManager:SendKeyEvent(false, prompt.KeyboardKeyCode, false, game)
        end
        local opcao = aguardarVenda(function() return botaoVendaVisivel("Vender o inventário de peixes") end, 8, "Menu do Juca nao abriu")
        hub = PlayerGui:FindFirstChild("PEGASUS_HUB")
        if hub then hubOrdem = hub.DisplayOrder; hub.DisplayOrder = 11 end
        task.wait(0.25)
        statusVenda = "Solicitando proposta"
        clicarVenda(opcao, "Vender o inventário de peixes")
        local confirmar = aguardarVenda(function()
            local b = botaoVendaVisivel("Vender tudo")
            if b and botaoVendaVisivel("Agora não") and not botaoVendaVisivel("Vender o inventário de peixes") then
                return b
            end
        end, 8, "Proposta nao apareceu")
        statusVenda = "Aguardando confirmacao"
        task.wait(0.8)
        if botaoVendaVisivel("Vender tudo") ~= confirmar or not botaoVendaVisivel("Agora não") then
            error("Menu de confirmacao mudou")
        end
        statusVenda = "Confirmando venda"
        clicarVenda(confirmar, "Vender tudo")
        statusVenda = "Verificando saldo e cesto"
        local mensagem = aguardarVenda(function()
            return mensagemVenda("Negócio fechado!")
        end, 15, "Venda nao confirmada pelo Juca")
        local valor = mensagem:match("Aqui estão ([%d%.]+) moedas")
        vendas += 1
        if valor then totalVendido += tonumber((valor:gsub("%.", ""))) or 0 end
        cestoAtual = nil
        local confirmado, restante = pcall(consultarCesto, 5)
        if not confirmado then
            warn("[PEGASUS] Venda confirmada; aguardando atualizacao do cesto")
        elseif restante ~= 0 then
            warn("[PEGASUS] Venda confirmada; cesto ainda informa " .. tostring(restante))
        end
        local fechar = botaoVendaVisivel("Tchau!")
        if fechar then
            local fechou, erroFechar = pcall(clicarVenda, fechar, "Tchau!")
            if not fechou then warn("[PEGASUS] Venda concluida; falha ao fechar: " .. tostring(erroFechar)) end
        end
        statusVenda = "Venda concluida"
    end)
    if not ok then
        statusVenda = "Falha: " .. tostring(motivo)
        warn("[PEGASUS] " .. statusVenda)
        task.wait(5)
    end
    if hub and hub.Parent and hubOrdem then hub.DisplayOrder = hubOrdem end
    if origem and Player.Character == char and root.Parent and humanoid.Health > 0 then
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        root.CFrame = origem
    end
    if varaSalva and Player.Character == char and humanoid and humanoid.Health > 0 then
        local restaurou, erroVara = pcall(function()
            local mochila = Player:FindFirstChildOfClass("Backpack")
            if varaSalva.Parent == char then return end
            if not mochila or varaSalva.Parent ~= mochila then error("Vara original indisponivel") end
            humanoid:EquipTool(varaSalva)
            task.wait(0.5)
            if varaSalva.Parent ~= char then error("Vara nao reequipada") end
        end)
        if not restaurou then
            warn("[PEGASUS] Falha ao reequipar: " .. tostring(erroVara))
            if ok then statusVenda = statusVenda .. " | Re equipe a vara" end
        end
    end
    if not ok then
        statusVenda = "Falha: " .. tostring(motivo)
        warn("[PEGASUS] " .. statusVenda)
    end
    proximaConsulta = os.clock() + (ok and 2 or 30)
    ultimaPesca = os.clock() - TEMPO_ENTRE_PESCAS
    estado = "livre"
    vendaManual = false
    vendendo = false
end

--==================================================
-- TELEPORTAR ATE PLAYER
--==================================================

local function teleportarPlayer()
    if not jogadorSelecionado then
        return
    end

    if jogadorSelecionado.Parent ~= Players then
        jogadorSelecionado = nil
        return
    end

    local _, _, root = obterPersonagem()
    local alvo = jogadorSelecionado.Character

    if not root or not alvo then
        return
    end

    local alvoRoot = alvo:FindFirstChild(
        "HumanoidRootPart"
    )

    if alvoRoot then

        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero

        root.CFrame = alvoRoot.CFrame
            * CFrame.new(0, 0, 4)
    end
end

--==================================================
-- TELEPORTAR ATE LOCAL
--==================================================

local function teleportarLocation(posicao, orientacao)
    local _, _, root = obterPersonagem()

    if not root then
        return
    end

    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero

    root.CFrame = orientacao or CFrame.new(posicao)
end

--==================================================
-- FLY
--==================================================

local function pararFly()
    flyAtivo = false

    if flyVelocity then
        flyVelocity:Destroy()
        flyVelocity = nil
    end

    if flyGyro then
        flyGyro:Destroy()
        flyGyro = nil
    end

    local _, humanoid = obterPersonagem()

    if humanoid then
        humanoid.PlatformStand = false
        humanoid.AutoRotate = true
    end
end

local function iniciarFly()
    local _, humanoid, root = obterPersonagem()

    if not humanoid or not root then
        return
    end

    pararFly()

    flyAtivo = true

    humanoid.PlatformStand = true
    humanoid.AutoRotate = false

    flyVelocity = Instance.new("BodyVelocity")
    flyVelocity.MaxForce = Vector3.new(1e6, 1e6, 1e6)
    flyVelocity.Velocity = Vector3.zero
    flyVelocity.Parent = root

    flyGyro = Instance.new("BodyGyro")
    flyGyro.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
    flyGyro.P = 10000
    flyGyro.CFrame = root.CFrame
    flyGyro.Parent = root
end

RunService.RenderStepped:Connect(function()
    if not flyAtivo then
        return
    end

    if not flyVelocity or not flyVelocity.Parent then
        pararFly()
        return
    end

    local camera = workspace.CurrentCamera

    if not camera then return end

    local direcao = Vector3.zero

    if not UserInputService:GetFocusedTextBox() then

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            direcao += camera.CFrame.LookVector
        end

        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            direcao -= camera.CFrame.LookVector
        end

        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            direcao += camera.CFrame.RightVector
        end

        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            direcao -= camera.CFrame.RightVector
        end

        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            direcao += Vector3.new(0, 1, 0)
        end

        if UserInputService:IsKeyDown(
            Enum.KeyCode.LeftControl
        ) then

            direcao -= Vector3.new(0, 1, 0)
        end
    end

    if direcao.Magnitude > 0 then
        direcao = direcao.Unit
    end

    flyVelocity.Velocity = direcao * flySpeed
    flyGyro.CFrame = camera.CFrame
end)

--==================================================
-- WALK SPEED
--==================================================

local function aplicarSpeed()
    local _, humanoid = obterPersonagem()

    if not humanoid then
        return
    end

    if speedAtivo then

        if velocidadeOriginal == nil then
            velocidadeOriginal = humanoid.WalkSpeed
        end

        humanoid.WalkSpeed = walkSpeed

    elseif velocidadeOriginal ~= nil then

        humanoid.WalkSpeed = velocidadeOriginal
        velocidadeOriginal = nil
    end
end

--==================================================
-- RESPAWN
--==================================================

Player.CharacterAdded:Connect(function()
    pararFly()
    resetarControle()

    estado = "livre"
    velocidadeOriginal = nil

    task.wait(1)

    aplicarSpeed()
end)

--==================================================
-- TEMA DA INTERFACE
--==================================================

local CORES = {
    fundo = Color3.fromRGB(17, 15, 26),
    painel = Color3.fromRGB(27, 23, 40),
    botao = Color3.fromRGB(39, 33, 57),
    roxo = Color3.fromRGB(139, 92, 246),
    claro = Color3.fromRGB(196, 170, 255),
    texto = Color3.fromRGB(245, 242, 255),
    cinza = Color3.fromRGB(155, 148, 175),
    verde = Color3.fromRGB(35, 135, 85),
    vermelho = Color3.fromRGB(120, 45, 65)
}

--==================================================
-- REMOVER INTERFACES ANTIGAS
--==================================================

for _, nome in ipairs({
    "PEGASUS_HUB",
    "BLUE_HUB",
    "AFK_PESCA_V4"
}) do

    local antigo = PlayerGui:FindFirstChild(nome)

    if antigo then
        antigo:Destroy()
    end
end

--==================================================
-- INTERFACE PRINCIPAL
--==================================================

local gui = Instance.new("ScreenGui")
gui.Name = "PEGASUS_HUB"
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.Parent = PlayerGui

local function arredondar(objeto, tamanho)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, tamanho or 8)
    corner.Parent = objeto
end

local principal = Instance.new("Frame")
principal.Size = UDim2.fromOffset(540, 390)
principal.Position = UDim2.new(0.5, -270, 0.5, -195)
principal.BackgroundColor3 = CORES.fundo
principal.BorderSizePixel = 0
principal.Active = true
principal.ClipsDescendants = true
principal.Parent = gui

arredondar(principal, 12)

local borda = Instance.new("UIStroke")
borda.Color = CORES.roxo
borda.Thickness = 1
borda.Transparency = 0.3
borda.Parent = principal

--==================================================
-- CABECALHO
--==================================================

local cabecalho = Instance.new("Frame")
cabecalho.Size = UDim2.new(1, 0, 0, 70)
cabecalho.BackgroundColor3 = CORES.painel
cabecalho.BorderSizePixel = 0
cabecalho.Active = true
cabecalho.Parent = principal

local nomeHub = Instance.new("TextLabel")
nomeHub.Size = UDim2.new(1, -70, 0, 32)
nomeHub.Position = UDim2.fromOffset(16, 5)
nomeHub.BackgroundTransparency = 1
nomeHub.Text = "PEGASUS HUB"
nomeHub.TextColor3 = CORES.claro
nomeHub.Font = Enum.Font.GothamBold
nomeHub.TextSize = 23
nomeHub.TextXAlignment = Enum.TextXAlignment.Left
nomeHub.Parent = cabecalho

local subtitulo = Instance.new("TextLabel")
subtitulo.Size = UDim2.new(1, -70, 0, 22)
subtitulo.Position = UDim2.fromOffset(17, 36)
subtitulo.BackgroundTransparency = 1
subtitulo.Text = "Generic Voice Game"
subtitulo.TextColor3 = CORES.cinza
subtitulo.Font = Enum.Font.Gotham
subtitulo.TextSize = 13
subtitulo.TextXAlignment = Enum.TextXAlignment.Left
subtitulo.Parent = cabecalho

local linha = Instance.new("Frame")
linha.Size = UDim2.new(1, 0, 0, 2)
linha.Position = UDim2.new(0, 0, 1, -2)
linha.BackgroundColor3 = CORES.roxo
linha.BorderSizePixel = 0
linha.Parent = cabecalho

--==================================================
-- MENU LATERAL
--==================================================

local menu = Instance.new("Frame")
menu.Position = UDim2.fromOffset(0, 70)
menu.Size = UDim2.new(0, 155, 1, -100)
menu.BackgroundColor3 = CORES.painel
menu.BorderSizePixel = 0
menu.Parent = principal

local menuPadding = Instance.new("UIPadding")
menuPadding.PaddingTop = UDim.new(0, 12)
menuPadding.PaddingLeft = UDim.new(0, 8)
menuPadding.PaddingRight = UDim.new(0, 8)
menuPadding.Parent = menu

local menuLayout = Instance.new("UIListLayout")
menuLayout.Padding = UDim.new(0, 7)
menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
menuLayout.Parent = menu

--==================================================
-- AREA DAS PAGINAS
--==================================================

local area = Instance.new("Frame")
area.Position = UDim2.fromOffset(165, 80)
area.Size = UDim2.new(1, -177, 1, -120)
area.BackgroundTransparency = 1
area.Parent = principal

local paginas = {}
local botoesAbas = {}

local function selecionarAba(nome)
    for id, pagina in pairs(paginas) do
        pagina.Visible = id == nome
    end

    for id, botao in pairs(botoesAbas) do
        botao.BackgroundColor3 = id == nome
            and CORES.roxo
            or CORES.botao
    end
end

local function criarAba(nome, ordem)
    local botao = Instance.new("TextButton")
    botao.Size = UDim2.new(1, 0, 0, 38)
    botao.BackgroundColor3 = CORES.botao
    botao.TextColor3 = CORES.texto
    botao.Text = nome
    botao.Font = Enum.Font.GothamBold
    botao.TextSize = 12
    botao.LayoutOrder = ordem
    botao.Parent = menu

    arredondar(botao, 7)

    local pagina = Instance.new("ScrollingFrame")
    pagina.Size = UDim2.fromScale(1, 1)
    pagina.BackgroundTransparency = 1
    pagina.BorderSizePixel = 0
    pagina.ScrollBarThickness = 3
    pagina.ScrollBarImageColor3 = CORES.roxo
    pagina.AutomaticCanvasSize = Enum.AutomaticSize.Y
    pagina.CanvasSize = UDim2.new()
    pagina.Visible = false
    pagina.Parent = area

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 8)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = pagina

    paginas[nome] = pagina
    botoesAbas[nome] = botao

    botao.MouseButton1Click:Connect(function()
        selecionarAba(nome)
    end)

    return pagina
end

local abaGeneral = criarAba("General", 1)
local abaFishing = criarAba("Fishing", 2)
local abaPlayer = criarAba("Player", 3)
local abaLocations = criarAba("Teleport Locations", 4)
local abaPlayers = criarAba("Teleport Players", 5)

--==================================================
-- COMPONENTES DA INTERFACE
--==================================================

local ordem = 0

local function organizar(objeto, pagina)
    ordem += 1
    objeto.LayoutOrder = ordem
    objeto.Parent = pagina
end

local function titulo(pagina, texto)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -5, 0, 26)
    label.BackgroundTransparency = 1
    label.Text = texto
    label.TextColor3 = CORES.claro
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Font = Enum.Font.GothamBold
    label.TextSize = 15

    organizar(label, pagina)

    return label
end

local function descricao(pagina, texto)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -8, 0, 38)
    label.BackgroundTransparency = 1
    label.Text = texto
    label.TextWrapped = true
    label.TextColor3 = CORES.cinza
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Font = Enum.Font.Gotham
    label.TextSize = 12

    organizar(label, pagina)

    return label
end

local function criarBotao(pagina, texto, altura)
    local botao = Instance.new("TextButton")
    botao.Size = UDim2.new(1, -5, 0, altura or 38)
    botao.BackgroundColor3 = CORES.botao
    botao.TextColor3 = CORES.texto
    botao.Font = Enum.Font.GothamBold
    botao.TextSize = 13
    botao.Text = texto

    arredondar(botao, 7)
    organizar(botao, pagina)

    return botao
end

local function atualizarBotao(botao, nome, ativo)
    botao.Text = nome .. (ativo and ": ON" or ": OFF")

    botao.BackgroundColor3 = ativo
        and CORES.verde
        or CORES.vermelho
end

local function criarInput(pagina, texto, valor, callback)
    titulo(pagina, texto)

    local caixa = Instance.new("TextBox")
    caixa.Size = UDim2.new(1, -5, 0, 34)
    caixa.BackgroundColor3 = CORES.painel
    caixa.TextColor3 = CORES.texto
    caixa.Font = Enum.Font.Gotham
    caixa.TextSize = 14
    caixa.Text = tostring(valor)
    caixa.ClearTextOnFocus = false

    arredondar(caixa, 7)
    organizar(caixa, pagina)

    caixa.FocusLost:Connect(function()
        local numero = tonumber(caixa.Text)

        if numero then
            valor = callback(numero)
        end

        caixa.Text = tostring(valor)
    end)

    return caixa
end

--==================================================
-- ABA GENERAL
--==================================================

titulo(abaGeneral, "General")

local botaoAFK = criarBotao(
    abaGeneral,
    "Anti-AFK: OFF"
)


botaoAFK.MouseButton1Click:Connect(function()
    antiAFK = not antiAFK
    if antiAFK then ultimoAFK = os.clock() - 60 end

    atualizarBotao(
        botaoAFK,
        "Anti-AFK",
        antiAFK
    )
end)

atualizarBotao(botaoAFK, "Anti-AFK", antiAFK)

--==================================================
-- ABA FISHING
--==================================================

titulo(abaFishing, "Auto Fishing")

local botaoPesca = criarBotao(
    abaFishing,
    "Auto Fishing [K]: OFF"
)

local botaoBau = criarBotao(abaFishing, "Auto Treasure: OFF")
atualizarBotao(botaoBau, "Auto Treasure", autoTreasure)
botaoBau.MouseButton1Click:Connect(function()
    autoTreasure = not autoTreasure
    if not autoTreasure then
        buscandoBau = false
        ultimoAlvo = nil
        ultimoPeixeY = nil
    end
    atualizarBotao(botaoBau, "Auto Treasure", autoTreasure)
end)
local botaoVenda = criarBotao(abaFishing, "Auto Sell: OFF")
atualizarBotao(botaoVenda, "Auto Sell", autoSell)
botaoVenda.MouseButton1Click:Connect(function()
    autoSell = not autoSell
    proximaConsulta = 0
    atualizarBotao(botaoVenda, "Auto Sell", autoSell)
end)
local botaoSell = criarBotao(abaFishing, "Sell Inventory")
botaoSell.MouseButton1Click:Connect(function()
    if vendendo then return end
    if ligado and estado ~= "livre" then
        vendaManual = true
        statusVenda = "Venda manual na fila"
        return
    end
    vendendo = true
    task.spawn(cicloVenda, true)
end)
local botaoSalvarPesca = criarBotao(abaFishing, "Save Fishing Location")
local labelLocalPesca = titulo(abaFishing, "Local de pesca: Lago")
botaoSalvarPesca.MouseButton1Click:Connect(function()
    if vendendo then return end
    local _, _, root = obterPersonagem()
    if not root then return end
    fishingLocation = root.CFrame
    labelLocalPesca.Text = "Local de pesca: Salvo"
end)
local labelCesto = titulo(abaFishing, "Cesto: --/" .. Config.MAXIMO_NO_CESTO)
local function alternarPesca()
    if vendendo then return end
    if not ligado then
        local char, humanoid, root = obterPersonagem()
        if not char or not humanoid or not root or humanoid.Health <= 0 or flyAtivo then return end
        local vara = pegarVara()
        if not vara then
            local mochila = Player:FindFirstChildOfClass("Backpack")
            if mochila then
                for _, item in ipairs(mochila:GetChildren()) do
                    if item:IsA("Tool") and item:GetAttribute("VaraId") ~= nil then vara = item; break end
                end
            end
        end
        if not vara then warn("[PEGASUS] Nenhuma vara encontrada"); return end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        root.CFrame = fishingLocation
        if vara.Parent ~= char then humanoid:EquipTool(vara) end
    end
    ligado = not ligado
    bauCompleto = false

    resetarControle()

    if ligado then

        if obterCaptura() then
            estado = "luta"
        else
            estado = "livre"
        end

        ultimaPesca = 0

    else

        estado = "livre"
    end

    atualizarBotao(
        botaoPesca,
        "Auto Fishing [K]",
        ligado
    )
end

botaoPesca.MouseButton1Click:Connect(alternarPesca)

atualizarBotao(
    botaoPesca,
    "Auto Fishing [K]",
    ligado
)

local nomesEstados = {
    livre = "Preparando pesca",
    carregando = "Carregando vara",
    espera = "Aguardando peixe",
    fisgando = "Fisgando peixe",
    luta = "Capturando peixe",
    mostrando = "Peixe capturado"
}

--==================================================
-- ABA PLAYER
--==================================================

titulo(abaPlayer, "Player Utilities")

local botaoFly = criarBotao(
    abaPlayer,
    "Fly [F]: OFF"
)

local botaoSpeed = criarBotao(
    abaPlayer,
    "Walk Speed: OFF"
)

local function alternarFly()
    if flyAtivo then
        pararFly()
    else
        iniciarFly()
    end

    atualizarBotao(botaoFly, "Fly [F]", flyAtivo)
end

botaoFly.MouseButton1Click:Connect(alternarFly)

botaoSpeed.MouseButton1Click:Connect(function()
    speedAtivo = not speedAtivo

    aplicarSpeed()

    atualizarBotao(
        botaoSpeed,
        "Walk Speed",
        speedAtivo
    )
end)

atualizarBotao(botaoFly, "Fly [F]", false)
atualizarBotao(botaoSpeed, "Walk Speed", false)

criarInput(
    abaPlayer,
    "Fly Speed",
    flySpeed,
    function(valor)

        flySpeed = math.clamp(valor, 5, 200)
        return flySpeed
    end
)

criarInput(
    abaPlayer,
    "Walk Speed",
    walkSpeed,
    function(valor)

        walkSpeed = math.clamp(valor, 5, 100)
        aplicarSpeed()

        return walkSpeed
    end
)

--==================================================
-- ABA TELEPORT LOCATIONS
--==================================================

titulo(abaLocations, "Teleport Locations")

descricao(
    abaLocations,
    "Selecione um local para teleportar."
)

for _, location in ipairs(Locations) do

    local botaoLocation = criarBotao(
        abaLocations,
        location.Nome,
        42
    )

    botaoLocation.BackgroundColor3 = CORES.roxo

    botaoLocation.MouseButton1Click:Connect(function()
        teleportarLocation(location.Posicao, location.Orientacao)
    end)

    descricao(
        abaLocations,
        string.format(
            "X: %g | Y: %g | Z: %g",
            location.Posicao.X,
            location.Posicao.Y,
            location.Posicao.Z
        )
    )
end

--==================================================
-- ABA TELEPORT PLAYERS
--==================================================

local tituloPlayers = titulo(
    abaPlayers,
    "Teleport Players"
)

local atualizarLista = criarBotao(
    abaPlayers,
    "Atualizar jogadores"
)

local selecionado = descricao(
    abaPlayers,
    "Nenhum jogador selecionado"
)

local lista = Instance.new("ScrollingFrame")
lista.Size = UDim2.new(1, -5, 0, 125)
lista.BackgroundColor3 = CORES.painel
lista.BorderSizePixel = 0
lista.ScrollBarThickness = 3
lista.ScrollBarImageColor3 = CORES.roxo
lista.AutomaticCanvasSize = Enum.AutomaticSize.Y
lista.CanvasSize = UDim2.new()

arredondar(lista, 7)
organizar(lista, abaPlayers)

local listaLayout = Instance.new("UIListLayout")
listaLayout.Padding = UDim.new(0, 4)
listaLayout.Parent = lista

local function carregarPlayers()
    for _, objeto in ipairs(lista:GetChildren()) do
        if objeto:IsA("TextButton") then
            objeto:Destroy()
        end
    end

    local jogadores = Players:GetPlayers()

    table.sort(jogadores, function(a, b)
        return a.Name:lower() < b.Name:lower()
    end)

    tituloPlayers.Text =
        "Teleport Players (" .. (#jogadores - 1) .. ")"

    if jogadorSelecionado
        and jogadorSelecionado.Parent ~= Players then

        jogadorSelecionado = nil
        selecionado.Text = "Nenhum jogador selecionado"
    end

    for _, jogador in ipairs(jogadores) do
        if jogador ~= Player then

            local item = Instance.new("TextButton")
            item.Size = UDim2.new(1, -5, 0, 32)

            item.BackgroundColor3 =
                jogador == jogadorSelecionado
                and CORES.roxo
                or CORES.botao

            item.TextColor3 = CORES.texto
            item.Font = Enum.Font.Gotham
            item.TextSize = 12
            item.TextTruncate = Enum.TextTruncate.AtEnd

            item.Text = jogador.DisplayName
                .. " (@" .. jogador.Name .. ")"

            item.Parent = lista

            arredondar(item, 5)

            item.MouseButton1Click:Connect(function()
                jogadorSelecionado = jogador

                selecionado.Text =
                    "Alvo: " .. jogador.Name

                for _, outro in ipairs(lista:GetChildren()) do
                    if outro:IsA("TextButton") then
                        outro.BackgroundColor3 = CORES.botao
                    end
                end

                item.BackgroundColor3 = CORES.roxo
            end)
        end
    end
end

local botaoTP = criarBotao(
    abaPlayers,
    "Teleportar ate jogador"
)

botaoTP.BackgroundColor3 = CORES.roxo

botaoTP.MouseButton1Click:Connect(teleportarPlayer)
atualizarLista.MouseButton1Click:Connect(carregarPlayers)

Players.PlayerAdded:Connect(function()
    task.defer(carregarPlayers)
end)

Players.PlayerRemoving:Connect(function(jogador)
    if jogadorSelecionado == jogador then

        jogadorSelecionado = nil

        selecionado.Text =
            "Nenhum jogador selecionado"
    end

    task.delay(0.2, carregarPlayers)
end)

carregarPlayers()

--==================================================
-- RODAPE
--==================================================

local rodape = Instance.new("TextLabel")
rodape.Size = UDim2.new(1, 0, 0, 30)
rodape.Position = UDim2.new(0, 0, 1, -30)
rodape.BackgroundColor3 = CORES.painel
rodape.BorderSizePixel = 0
rodape.Text = "PEGASUS HUB V9.8 | RightShift"
rodape.TextColor3 = CORES.cinza
rodape.Font = Enum.Font.Gotham
rodape.TextSize = 11
rodape.Parent = principal

--==================================================
-- MINIMIZAR INTERFACE
--==================================================

local minimizado = false

local minimizar = Instance.new("TextButton")
minimizar.Size = UDim2.fromOffset(35, 35)
minimizar.Position = UDim2.new(1, -42, 0, 7)
minimizar.BackgroundTransparency = 1
minimizar.TextColor3 = CORES.claro
minimizar.TextSize = 24
minimizar.Text = "-"
minimizar.Parent = cabecalho

minimizar.MouseButton1Click:Connect(function()
    minimizado = not minimizado

    menu.Visible = not minimizado
    area.Visible = not minimizado
    rodape.Visible = not minimizado

    principal.Size = minimizado
        and UDim2.fromOffset(540, 70)
        or UDim2.fromOffset(540, 390)

    minimizar.Text = minimizado and "+" or "-"
end)

--==================================================
-- ARRASTAR INTERFACE
--==================================================

local arrastando = false
local inicioMouse
local inicioPosicao

cabecalho.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then

        arrastando = true
        inicioMouse = input.Position
        inicioPosicao = principal.Position
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        arrastando = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if arrastando
        and input.UserInputType == Enum.UserInputType.MouseMovement then

        local delta = input.Position - inicioMouse

        principal.Position = UDim2.new(
            inicioPosicao.X.Scale,
            inicioPosicao.X.Offset + delta.X,
            inicioPosicao.Y.Scale,
            inicioPosicao.Y.Offset + delta.Y
        )
    end
end)

--==================================================
-- ATALHOS
--==================================================

UserInputService.InputBegan:Connect(function(input, processado)
    if processado then return end
    if UserInputService:GetFocusedTextBox() then return end

    if input.KeyCode == Enum.KeyCode.K then

        alternarPesca()

    elseif input.KeyCode == Enum.KeyCode.F then

        alternarFly()

    elseif input.KeyCode == Enum.KeyCode.RightShift then

        principal.Visible = not principal.Visible
    end
end)

--==================================================
-- ATUALIZAR INTERFACE
--==================================================

task.spawn(function()
    while gui.Parent do



        labelCesto.Text = "Cesto: " .. (cestoAtual or "--") .. "/" .. Config.MAXIMO_NO_CESTO
        atualizarBotao(
            botaoFly,
            "Fly [F]",
            flyAtivo
        )

        task.wait(0.2)
    end
end)

--==================================================
-- LOOP PRINCIPAL DA PESCA
--==================================================

RunService.Heartbeat:Connect(function()
    if vendendo then return end
    if vendaManual and (not ligado or estado == "livre") then
        vendendo = true
        task.spawn(cicloVenda, true)
        return
    end
    if not ligado then return end

    if not pegarVara() then

        resetarControle()
        estado = "livre"

        return
    end

    local agora = os.clock()

    if estado == "luta" then

        if not obterCaptura() and agora - inicioCaptura > 3 then
            resetarControle()
            estado = "mostrando"
            fimResultado = agora + TEMPO_RESULTADO
        else
            controlarLuta()
        end

    elseif estado == "livre" then

        if agora - ultimaPesca >= TEMPO_ENTRE_PESCAS then
            if autoSell and agora >= proximaConsulta and (cestoAtual == nil or cestoAtual >= Config.MAXIMO_NO_CESTO) then
                vendendo = true
                task.spawn(cicloVenda)
            else
                task.spawn(lancar)
            end
        end

    elseif estado == "fisgando" then

        if agora - inicioCaptura > 2 then
            mouse(false)
            estado = "espera"
        end

    elseif estado == "mostrando" then

        if agora >= fimResultado then
            estado = "livre"
            ultimaPesca = agora
        end
    end
end)

--==================================================
-- INICIALIZACAO
--==================================================

-- Atualiza o cesto independentemente do Auto Sell.
task.spawn(function()
    while gui.Parent do
        if not vendendo and not consultandoCesto then
            local ok, motivo = pcall(consultarCesto)
            if not ok then
                cestoAtual = nil
                warn("[PEGASUS] Consulta cesto: " .. tostring(motivo))
            end
        end
        task.wait(5)
    end
end)

selecionarAba("General")

print("======================================")
print("PEGASUS HUB V9.8")
print("Generic Voice Game")
print("Script carregado!")
print("K - Auto Fishing")
print("F - Fly")
print("RightShift - Interface")
print("======================================")

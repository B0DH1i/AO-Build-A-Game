-- Bot Variables
BotName = "DiceCardBot"
local stepNumber = 1
local stopNumber = 9
local runStatus = 'disable'
local currentNumber = 0
local GameTarget = 'IGhRO_xwdwQuOyDGdi5F_Jt1uKphH2BX3LMQyP_nE6Y'

local function sendRollAndDraw()
    ao.send({
        Target = GameTarget,
        Action = "RollDiceAndDrawCard",
    })
end

local function finishRoll()
    ao.send({
        Target = GameTarget,
        Action = "FinishPoints",
        Data = BotName
    })
    currentNumber = 0
end

local function log(message)
    print("[Bot Log] " .. message)
end

local function handleSuccess()
    currentNumber = currentNumber + 1
    log('Roll Success ' .. currentNumber)
    if (currentNumber >= stepNumber) then
        stepNumber = stepNumber + 1
        finishRoll()
    else
        sendRollAndDraw()
    end
end

local function handleFailure()
    currentNumber = 0
    log('Roll Failed')
    sendRollAndDraw()
end

local function handleFinish(Msg)
    log(Msg.Data)
    if stopNumber < stepNumber then
        stopRolling()
        return
    end
    sendRollAndDraw()
end

function startRolling()
    runStatus = 'enable'
    stepNumber = 1
    currentNumber = 0
    log('Bot started rolling')
    sendRollAndDraw()
end

function stopRolling()
    runStatus = 'disable'
    log('The bot has finished running')
end

-- Roll Dice and Draw Card Result Handler
Handlers.add(
    "HandlerRollDiceAndDrawCardResult",
    Handlers.utils.hasMatchingTag("Action", "RollDiceAndDrawCardResult"),
    function(Msg)
        if runStatus == 'disable' then
            return
        end
        if not string.match(Msg.Data, "Failed") then
            handleSuccess()
        else
            handleFailure()
        end
    end
)

-- Finish Points Result Handler
Handlers.add(
    "HandlerFinishPointsResult",
    Handlers.utils.hasMatchingTag("Action", "FinishPointsResult"),
    function(Msg)
        if runStatus == 'disable' then
            return
        end
        handleFinish(Msg)
    end
)

-- Current Points Handler
Handlers.add(
    "HandlerCurrentPoints",
    Handlers.utils.hasMatchingTag("Action", "CurrentPoints"),
    function(Msg)
        log("Current Points: " .. Msg.Data)
    end
)

-- Rank List Handler
Handlers.add(
    "HandlerRankList",
    Handlers.utils.hasMatchingTag("Action", "RankList"),
    function(Msg)
        log("Rank List: " .. Msg.Data)
    end
)

-- Your Turn Handler for Bot
Handlers.add(
    "HandlerYourTurn",
    Handlers.utils.hasMatchingTag("Action", "YourTurn"),
    function(Msg)
        if runStatus == 'enable' then
            log("Bot's turn to roll the dice.")
            sendRollAndDraw()
        end
    end
)

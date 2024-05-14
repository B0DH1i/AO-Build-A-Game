-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
Game = Game or nil
CRED = "Sa0iBLPNyJQrwpTTG-tWLQU-1QeUAJA73DdxGGiKoJc"
InAction = InAction or false

colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  yellow = "\27[33m",
  reset = "\27[0m",
  gray = "\27[90m"
}

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Calculates the best direction to move to maximize distance from enemies.
-- @param player: The player state.
-- @return: The best direction to move.
function getBestMoveDirection(player)
    local directions = {"Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft"}
    local maxDistance = -1
    local bestDirection = nil

    for _, direction in ipairs(directions) do
        local newX, newY = getNewCoordinates(player.x, player.y, direction)
        local distance = getMaxDistanceFromEnemies(newX, newY)

        if distance > maxDistance then
            maxDistance = distance
            bestDirection = direction
        end
    end

    return bestDirection or directions[math.random(#directions)]
end

-- Gets new coordinates based on the current coordinates and the direction of movement.
-- @param x, y: Current coordinates.
-- @param direction: Direction of movement.
-- @return: New coordinates after moving in the specified direction.
function getNewCoordinates(x, y, direction)
    local directionMap = {
        Up = {x = 0, y = -1}, Down = {x = 0, y = 1},
        Left = {x = -1, y = 0}, Right = {x = 1, y = 0},
        UpRight = {x = 1, y = -1}, UpLeft = {x = -1, y = -1},
        DownRight = {x = 1, y = 1}, DownLeft = {x = -1, y = 1}
    }

    local delta = directionMap[direction]
    if delta then
        return (x + delta.x) % Width, (y + delta.y) % Height
    else
        return x, y
    end
end

-- Calculates the maximum distance from enemies based on given coordinates.
-- @param x, y: Coordinates to evaluate.
-- @return: The maximum distance from enemies.
function getMaxDistanceFromEnemies(x, y)
    local maxDistance = -1

    for _, state in pairs(LatestGameState.Players) do
        if state.id ~= ao.id and state.alive then
            local distance = math.abs(x - state.x) + math.abs(y - state.y)
            if distance > maxDistance then
                maxDistance = distance
            end
        end
    end

    return maxDistance
end

-- Decides the next action based on player proximity and energy.
-- If any player is within range, it initiates an attack; otherwise, moves strategically.
function decideNextAction()
    local player = LatestGameState.Players[ao.id]
    local targetInRange = false
    local targetId = nil
    local minDistance = Range + 1

    for target, state in pairs(LatestGameState.Players) do
        if target ~= ao.id and state.alive and inRange(player.x, player.y, state.x, state.y, Range) then
            local distance = math.abs(player.x - state.x) + math.abs(player.y - state.y)
            if distance < minDistance then
                minDistance = distance
                targetInRange = true
                targetId = target
            end
        end
    end

    if player.energy > 5 and targetInRange then
        print(colors.red .. "Player in range. Attacking " .. targetId .. "." .. colors.reset)
        ao.send({Target = Game, Action = "PlayerAttack", AttackTarget = targetId, AttackEnergy = tostring(player.energy)})
    else
        local bestDirection = getBestMoveDirection(player)
        print(colors.blue .. "No player in range or insufficient energy. Moving " .. bestDirection .. "." .. colors.reset)
        ao.send({Target = Game, Action = "PlayerMove", Direction = bestDirection})
    end
    InAction = false
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then
      print(colors.gray .. "Previous action still in progress. Skipping." .. colors.reset)
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- Handler to trigger game state updates.
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then
      InAction = true
      print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print(colors.gray .. "Previous action still in progress. Skipping." .. colors.reset)
    end
  end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = CRED, Action = "Transfer", Recipient = Game, Quantity = "1000"})
  end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print \'LatestGameState\' for detailed view.")
  end
)

-- Handler to decide the next best action.
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then 
      InAction = false
      return 
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)

-- Handler to automatically attack when hit by another player.
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction then
      InAction = true
      local playerEnergy = LatestGameState.Players[ao.id].energy
      if playerEnergy == nil then
        print(colors.red .. "Unable to read energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
      elseif playerEnergy == 0 then
        print(colors.red .. "Player has insufficient energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
      else
        print(colors.red .. "Returning attack." .. colors.reset)
        ao.send({Target = Game, Action = "PlayerAttack", AttackEnergy = tostring(playerEnergy)})
      end
      InAction = false
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print(colors.gray .. "Previous action still in progress. Skipping." .. colors.reset)
    end
  end
)

-- Function to request tokens for the bot.
function requestTokens()
    print(colors.gray .. "Requesting tokens..." .. colors.reset)
    ao.send({Target = Game, Action = "RequestTokens"})
end

-- Function to register the bot for the game.
function registerBot()
    print(colors.gray .. "Registering bot..." .. colors.reset)
    ao.send({Target = Game, Action = "Register"})
end

-- Initialize the bot by requesting tokens and registering.
function initializeBot()
    requestTokens()
    registerBot()
end

initializeBot()

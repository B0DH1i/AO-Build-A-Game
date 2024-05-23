successText = 'Success'
failedText = "Failed"
rankList = rankList or {}
pointsList = pointsList or {}
members = members or {}
gameTimeTag = gameTimeTag or ""
cards = { "Bonus 10", "Bonus 20", "Bonus 30", "Extra Roll", "Lose 10", "Lose 20", "Lose 30", "Swap Points", "Double Points" }
turnOrder = turnOrder or {}
currentTurnIndex = currentTurnIndex or 1

local function guid()
    local seed = { 'e', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' }
    local tb = {}
    for i = 1, 32 do
        table.insert(tb, seed[math.random(1, 16)])
    end
    local sid = table.concat(tb)
    return string.format('%s-%s-%s-%s-%s',
            string.sub(sid, 1, 8),
            string.sub(sid, 9, 12),
            string.sub(sid, 13, 16),
            string.sub(sid, 17, 20),
            string.sub(sid, 21, 32)
    )
end

local function getDiceNumber()
    return math.random(1, 6)
end

local function getDiceText(num)
    return num > 1 and successText or failedText
end

local function getCard()
    return cards[math.random(1, #cards)]
end

local function getMembers()
    local memberList = {}
    for id, _ in pairs(members) do
        table.insert(memberList, id)
    end
    return memberList
end

local function addMember(id)
    if not members[id] then
        members[id] = true
        table.insert(turnOrder, id)
    end
end

local function getNextTurn()
    currentTurnIndex = currentTurnIndex + 1
    if currentTurnIndex > #turnOrder then
        currentTurnIndex = 1
    end
    return turnOrder[currentTurnIndex]
end

local function getCurrentTurn()
    return turnOrder[currentTurnIndex]
end

local function joinStatistic(id)
    addMember(id)
end

local function getPersonPoints(id)
    return pointsList[id] or 0
end

local function sortRankList()
    table.sort(rankList, function(a, b)
        return a.points > b.points
    end)
end

local function getGameTimeTag()
    local currentTime = os.date("*t", os.time())
    return currentTime.year .. '-' .. currentTime.month
end

local function checkRankExpire()
    local currentTag = getGameTimeTag()
    if gameTimeTag ~= currentTag then
        for i = 1, 10 do
            if rankList[i] and rankList[i].pid then
                ao.send({ Target = ao.id, Action = "Transfer", Recipient = rankList[i].pid, Quantity = tostring(100 - (i - 1) * 10) })
            end
        end
        rankList = {}
        gameTimeTag = currentTag
    end
end

local function log(message)
    print("[LOG] " .. message)
end

local function calculatePoints(diceNumber, cardText, points)
    if not diceNumber or not cardText then
        log("Invalid dice number or card text")
        return points
    end
    if (diceNumber > 1) then
        points = points + diceNumber
        if cardText == "Bonus 10" then
            points = points + 10
        elseif cardText == "Bonus 20" then
            points = points + 20
        elseif cardText == "Bonus 30" then
            points = points + 30
        elseif cardText == "Lose 10" then
            points = points - 10
        elseif cardText == "Lose 20" then
            points = points - 20
        elseif cardText == "Lose 30" then
            points = points - 30
        elseif cardText == "Extra Roll" then
            points = points + diceNumber
        elseif cardText == "Swap Points" then
            local swapId = getMembers()[math.random(1, #getMembers())]
            points, pointsList[swapId] = pointsList[swapId], points
        elseif cardText == "Double Points" then
            points = points * 2
        end
    else
        points = 0
    end
    return points
end

Handlers.add(
    "HandlerGetRank",
    Handlers.utils.hasMatchingTag("Action", "GetRank"),
    function(Msg)
        log("HandlerGetRank called")
        if #rankList == 0 then
            ao.send({
                Target = Msg.From,
                Action = "RankList",
                Data = "rankList : No Any Person"
            })
            return
        end

        checkRankExpire()
        local page = tonumber(Msg.Data)
        if (page == nil) then
            page = 1
        end
        local startPos = (page - 1) * 10 + 1
        if (startPos > #rankList) then
            startPos = 1
        end
        local endPos = startPos + 10
        local maxPos = math.min(endPos, #rankList)
        local retText = ''
        for i = startPos, maxPos do
            retText = retText .. 'Rank ' .. i .. " : " .. rankList[i].name .. " " .. rankList[i].points
            if startPos ~= maxPos then
                retText = retText .. '\n'
            end
        end
        ao.send({
            Target = Msg.From,
            Action = "RankList",
            Data = retText
        })
    end
)

Handlers.add(
    "HandlerGetPoints",
    Handlers.utils.hasMatchingTag("Action", "GetPoints"),
    function(Msg)
        log("HandlerGetPoints called")
        local text = getPersonPoints(Msg.From)
        log(text .. " Points")
        ao.send({
            Target = Msg.From,
            Action = "CurrentPoints",
            Data = text .. ""
        })
    end
)

Handlers.add(
    "HandlerFinishPoints",
    Handlers.utils.hasMatchingTag("Action", "FinishPoints"),
    function(Msg)
        log("HandlerFinishPoints called")
        checkRankExpire()
        local uuid = guid()
        table.insert(rankList, {
            points = pointsList[Msg.From],
            name = Msg.Data,
            uuid = uuid,
            pid = Msg.From
        })
        sortRankList()
        pointsList[Msg.From] = 0
        local current = "Unknown"
        for index, obj in pairs(rankList) do
            if obj.uuid == uuid then
                current = index
                break
            end
        end

        ao.send({
            Target = Msg.From,
            Action = "FinishPointsResult",
            Data = "Hey! You ranked " .. current
        })
    end
)

Handlers.add(
    "HandlerRollDiceAndDrawCard",
    Handlers.utils.hasMatchingTag("Action", "RollDiceAndDrawCard"),
    function(Msg)
        log("HandlerRollDiceAndDrawCard called")
        
        local currentTurn = getCurrentTurn()
        if Msg.From ~= currentTurn then
            ao.send({
                Target = Msg.From,
                Action = "Error",
                Data = "It's not your turn!"
            })
            return
        end
        
        local diceNumber = getDiceNumber()
        local diceText = getDiceText(diceNumber)
        local cardText = getCard()
        
        local points = getPersonPoints(Msg.From)
        points = calculatePoints(diceNumber, cardText, points)
        
        pointsList[Msg.From] = points
        joinStatistic(Msg.From)
        
        ao.send({
            Target = Msg.From,
            Action = "RollDiceAndDrawCardResult",
            Data = "Dice: " .. diceText .. ", Card: " .. cardText .. ", Total Points: " .. points
        })
        
        local nextTurn = getNextTurn()
        ao.send({
            Target = nextTurn,
            Action = "YourTurn",
            Data = "It's your turn now!"
        })
    end
)

Handlers.add(
    "HandlerJoinGame",
    Handlers.utils.hasMatchingTag("Action", "JoinGame"),
    function(Msg)
        log("HandlerJoinGame called")
        addMember(Msg.From)
        ao.send({
            Target = Msg.From,
            Action = "JoinGameResult",
            Data = "You have joined the game!"
        })
    end
)

Handlers.add(
    "HandlerGetMembers",
    Handlers.utils.hasMatchingTag("Action", "GetMembers"),
    function(Msg)
        local membersList = getMembers()
        local retText = 'Members:\n'
        for i, member in ipairs(membersList) do
            retText = retText .. i .. ": " .. member .. "\n"
        end
        ao.send({
            Target = Msg.From,
            Action = "MembersList",
            Data = retText
        })
    end
)

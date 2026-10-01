-- CleanTree EbonAPI bridge
-- Uses EbonAPI as a runtime dependency; does not bundle or modify EbonAPI.

CleanTreeEbonAPI = CleanTreeEbonAPI or {}
local A = CleanTreeEbonAPI

A.requiredMajor = 2
A.requiredMinor = 1
A.requiredVersion = "2.1.0+"
A.apiVersion = EbonAPI and EbonAPI.version or nil
A.api = EbonAPI and EbonAPI:NewAddon("CleanTree", A.requiredMajor, A.requiredMinor) or nil
A.ready = false
A.tree = nil
A.defsById = {}
A.parentsById = {}
A.maxRankById = {}
A.serverAsh = nil
A.serverLoadout = nil
A.callbacks = nil
A.installed = false
A.lastRequestAt = 0
A.linkCount = 0

local function wipeTable(t)
    for k in pairs(t) do t[k] = nil end
end

local function parseNumberText(text)
    if type(text) ~= "string" then return nil end
    -- Keep CleanTree on EbonAPI's public contract. Color stripping is trivial here,
    -- so do not depend on EbonAPI.Lib internals that may change between releases.
    text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = string.gsub(text, "|r", "")
    local sign, numberPart = string.match(text, "(%-?)([%d][%d%s,%.]*)%s*$")
    if not numberPart then
        numberPart = string.match(text, "([%d][%d%s,%.]*)")
        sign = ""
    end
    if not numberPart then return nil end
    local digits = string.gsub(numberPart, "%D", "")
    if digits == "" then return nil end
    local value = tonumber(digits)
    if not value then return nil end
    if sign == "-" then value = -value end
    return value
end

function A.RefreshTalentDatabase()
    wipeTable(A.defsById)
    wipeTable(A.parentsById)
    wipeTable(A.maxRankById)
    A.tree = nil
    A.linkCount = 0

    if not EbonAPI or not EbonAPI.Ebonhold or not EbonAPI.Ebonhold.TalentDatabase then return false end
    local ok, db = pcall(EbonAPI.Ebonhold.TalentDatabase)
    if not ok or type(db) ~= "table" then return false end
    local tree = db[0]
    if type(tree) ~= "table" or type(tree.nodes) ~= "table" then return false end
    A.tree = tree

    for _, def in ipairs(tree.nodes) do
        local id = tonumber(def and def.id)
        if id then
            A.defsById[id] = def
            if def.infinite then
                A.maxRankById[id] = nil
            else
                A.maxRankById[id] = type(def.spells) == "table" and #def.spells or 0
            end
        end
    end

    if type(tree.links) == "table" then
        for _, link in ipairs(tree.links) do
            local parentId = tonumber(link and link[1])
            local childId = tonumber(link and link[2])
            if parentId and childId and A.defsById[parentId] and A.defsById[childId] then
                local parents = A.parentsById[childId]
                if not parents then
                    parents = {}
                    A.parentsById[childId] = parents
                end
                parents[#parents + 1] = parentId
                A.linkCount = A.linkCount + 1
            end
        end
    end
    return true
end

function A.RefreshState()
    if not A.api then return end
    local state = A.api:State()
    if state then
        local ash = state.GetAsh and state.GetAsh() or nil
        local loadout = state.GetLoadout and state.GetLoadout() or nil
        if ash then A.serverAsh = ash end
        if loadout then A.serverLoadout = loadout end
    end
end


function A.GetSkillTree()
    if not EbonAPI or not EbonAPI.Ebonhold or not EbonAPI.Ebonhold.SkillTree then return nil end
    local ok, value = pcall(EbonAPI.Ebonhold.SkillTree)
    return ok and value or nil
end

function A.GetSkillTreeFrame()
    if not EbonAPI or not EbonAPI.Ebonhold or not EbonAPI.Ebonhold.SkillTreeFrame then return nil end
    local ok, value = pcall(EbonAPI.Ebonhold.SkillTreeFrame)
    return ok and value or nil
end

function A.GetNodeDef(id)
    id = tonumber(id)
    return id and A.defsById[id] or nil
end

function A.GetNodeFrame(id)
    id = tonumber(id)
    if not id then return nil end
    return _G["skillTreeNode" .. tostring(id)]
end

function A.GetCurrentRank(id)
    id = tonumber(id)
    local def = id and A.defsById[id] or nil
    if not def then return nil end
    local btn = A.GetNodeFrame(id)
    if not btn then return nil end
    if btn.state == "locked" then return 0 end

    if def.infinite then
        local badge = btn.stackBadge
        if badge and badge.IsShown and badge:IsShown() and badge.count and badge.count.GetText then
            local value = tonumber(badge.count:GetText())
            if value then return value end
        end
        return 0
    end

    if btn.rankText and btn.rankText.GetText then
        local text = btn.rankText:GetText()
        if type(text) == "string" then
            local cur = tonumber(string.match(text, "^(%d+)"))
            if cur ~= nil then return cur end
        end
    end

    if btn.state == "active" then
        local maxRank = A.maxRankById[id] or 0
        if maxRank > 0 then return maxRank end
    end
    return 0
end

function A.GetMaxRank(id)
    return A.maxRankById[tonumber(id)]
end

function A.GetParents(id)
    return A.parentsById[tonumber(id)]
end

function A.IsStart(id)
    local def = A.GetNodeDef(id)
    return def and def.isStart == true or false
end

function A.IsInfinite(id)
    local def = A.GetNodeDef(id)
    return def and def.infinite == true or false
end

function A.GetNextCost(id, currentRank)
    local def = A.GetNodeDef(id)
    if not def then return nil end
    currentRank = math.max(0, math.floor(tonumber(currentRank) or 0))
    local nextRank = currentRank + 1
    local costs = def.soulPointsCosts or {}
    if not def.infinite then
        return tonumber(costs[nextRank])
    end

    local base = math.max(tonumber(costs[1]) or 1, 1)
    local growth = tonumber(def.infiniteGrowth) or 1.15
    local cost = math.ceil(base * (growth ^ (nextRank - 1)) - 0.000001)
    if cost >= 100000000 then return 100000000 end
    if cost < 1 then cost = 1 end
    return cost
end

function A.GetAvailableAsh()
    if EbonAPI and EbonAPI.Ebonhold and EbonAPI.Ebonhold.SkillTreeFrame then
        local ok, frame = pcall(EbonAPI.Ebonhold.SkillTreeFrame)
        if ok and frame and frame.pointsText and frame.pointsText.GetText then
            local okText, text = pcall(frame.pointsText.GetText, frame.pointsText)
            if okText then
                local value = parseNumberText(text)
                if value ~= nil then return value, "skill-tree-frame" end
            end
        end
    end
    if A.serverAsh and tonumber(A.serverAsh.spendable) then
        return tonumber(A.serverAsh.spendable), "server-ash"
    end
    return nil, "unavailable"
end

function A.GetServerRank(id)
    local loadout = A.serverLoadout
    local nodes = loadout and loadout.nodes
    if type(nodes) ~= "table" then return nil end
    return tonumber(nodes[tonumber(id)]) or 0
end

function A.HasServerLoadout()
    return A.serverLoadout ~= nil and type(A.serverLoadout.nodes) == "table"
end

function A.NodeCount()
    local n = 0
    for _ in pairs(A.defsById) do n = n + 1 end
    return n
end

function A.GetFeature(name)
    if not A.api or not A.api.HasFeature then return false end
    local ok, value = pcall(A.api.HasFeature, A.api, name)
    return ok and value == true
end

function A.RequestLoadout(force)
    if not EbonAPI or not EbonAPI.Ebonhold then return false end
    local can = EbonAPI.Ebonhold.CanRequestLoadout and EbonAPI.Ebonhold.CanRequestLoadout()
    if not can then return false end
    local now = type(GetTime) == "function" and GetTime() or 0
    if not force and (now - (A.lastRequestAt or 0)) < 2 then return false end
    A.lastRequestAt = now
    local ok, value = pcall(EbonAPI.Ebonhold.RequestLoadout)
    return ok and value ~= false
end

function A.IsReady()
    if A.api and A.api.IsReady then
        local ok, value = pcall(A.api.IsReady, A.api)
        if ok then return value == true end
    end
    return A.ready == true
end

function A.GetStatus()
    local ash, source = A.GetAvailableAsh()
    local version, major, minor, patch = nil, nil, nil, nil
    if EbonAPI and EbonAPI.GetVersion then
        local ok, v, maj, min, pat = pcall(EbonAPI.GetVersion, EbonAPI)
        if ok then version, major, minor, patch = v, maj, min, pat end
    end
    version = version or A.apiVersion
    return {
        ready = A.IsReady(),
        apiPresent = EbonAPI ~= nil,
        apiHandle = A.api ~= nil,
        apiVersion = version,
        apiMajor = major,
        apiMinor = minor,
        apiPatch = patch,
        requiredVersion = A.requiredVersion,
        compatible = A.api ~= nil,
        nodes = A.NodeCount(),
        talentDatabase = A.tree ~= nil,
        skillTreeFrame = A.GetFeature("SkillTreeFrame"),
        skillTree = A.GetFeature("SkillTree"),
        requestLoadout = A.GetFeature("RequestLoadout"),
        ash = ash,
        ashSource = source,
        serverLoadout = A.HasServerLoadout(),
    }
end

function A.Init(callbacks)
    if A.installed then
        A.callbacks = callbacks or A.callbacks
        return A.api ~= nil
    end
    A.installed = true
    A.callbacks = callbacks or {}
    if not A.api then return false end

    A.api:On("READY", function(_, version)
        A.ready = true
        A.RefreshTalentDatabase()
        A.RefreshState()
        A.RequestLoadout(true)
        if A.callbacks and A.callbacks.onReady then A.callbacks.onReady(version) end
    end)

    A.api:On("FEATURE_CHANGED", function(_, name, available)
        if name == "TalentDatabase" and available then A.RefreshTalentDatabase() end
        if A.callbacks and A.callbacks.onFeature then A.callbacks.onFeature(name, available) end
    end)

    A.api:On("SERVER_ASH", function(_, ash)
        A.serverAsh = ash
        if A.callbacks and A.callbacks.onAsh then A.callbacks.onAsh(ash) end
    end)

    A.api:On("SERVER_LOADOUT", function(_, loadout)
        A.serverLoadout = loadout
        if A.callbacks and A.callbacks.onLoadout then A.callbacks.onLoadout(loadout) end
    end)

    -- EbonAPI 2.1 exposes authoritative readiness on the addon handle. Sticky READY
    -- should normally populate A.ready, but seed from the handle as a defensive fallback
    -- when CleanTree attaches after PLAYER_LOGIN or another addon changes event timing.
    if not A.ready and A.IsReady() then
        A.ready = true
        A.RefreshTalentDatabase()
        A.RefreshState()
        A.RequestLoadout(true)
        if A.callbacks and A.callbacks.onReady then
            A.callbacks.onReady((EbonAPI and EbonAPI.version) or A.apiVersion)
        end
    end

    return true
end

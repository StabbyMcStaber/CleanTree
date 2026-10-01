-- CleanTree v1.1.1
-- CleanTree v1.2.0
-- Project Ebonhold / WoW 3.3.5a
--
-- Functional replacement UI for the Soul Ash Skill Tree.
-- Ebonhold remains authoritative: EbonTree stages purchases by clicking the
-- original live node buttons and applies by clicking the original Apply Changes
-- button. The native tree stays instantiated underneath, while CleanTree is
-- embedded directly into Ebonhold's native Skill Tree content area.
--
-- Finite-node metadata is seeded from AshBuild v1.0.0-beta3. Runtime discovery
-- supplements that catalog so the three Endless nodes are intentionally shown.

EbonTreeDB = EbonTreeDB or {}

local VERSION = "1.2.0"
local DATA = _G.EbonTreeData or { nodes = {} }
local ET = CreateFrame("Frame")
_G.EbonTree = ET

local C = {
    bg       = {0.035, 0.035, 0.045, 0.97},
    panel    = {0.075, 0.075, 0.09, 0.96},
    panel2   = {0.11, 0.11, 0.13, 0.96},
    border   = {0.50, 0.42, 0.18, 1.00},
    gold     = {1.00, 0.82, 0.00, 1.00},
    green    = {0.20, 1.00, 0.20, 1.00},
    red      = {1.00, 0.25, 0.20, 1.00},
    gray     = {0.58, 0.58, 0.62, 1.00},
    white    = {0.96, 0.96, 0.96, 1.00},
    blue     = {0.25, 0.75, 1.00, 1.00},
}

local CATEGORY_LABELS = {
    ALL = "All",
    UNOWNED = "Unowned",
    BUYABLE = "Buyable Now",
    DAMAGE = "Damage",
    SURVIVAL = "Survival",
    CONVENIENCE = "Convenience",
    ENDLESS = "Endless",
    CART = "Cart",
    PURCHASED = "Purchased",
    OTHER = "Other",
}

local CATEGORY_ORDER = {"ALL", "UNOWNED", "DAMAGE", "SURVIVAL", "CONVENIENCE", "ENDLESS", "CART", "PURCHASED"}

-- Stable dependency-aware list ordering. Project Ebonhold's web builder exposes
-- the exact finite-tree node IDs and directed prerequisite links in
-- skill-tree.json. Hotfix41 uses a precomputed unlock-oriented order generated
-- from that graph: branch root first, then prerequisite depth, then web-builder
-- position. No frame-geometry guessing or graph work runs inside the 3.3.5 client.
ET.TREE_ROOT_NAMES = {
    DAMAGE = "Rising Carnage",
    SURVIVAL = "Essence of Endurance",
    CONVENIENCE = "Unshaken",
}

ET.TREE_CATEGORY_ORDER = {
    DAMAGE = 1,
    SURVIVAL = 2,
    CONVENIENCE = 3,
    ENDLESS = 4,
    OTHER = 5,
}

local mainFrame
local listScroll, rows = nil, {}
local titleText, soulAshText, scanText, detailTitle, detailBody, pendingText, pendingSpendText
local applyButton, refreshButton, discardButton
local tabButtons = {}
local searchBox

local selectedCategory = "UNOWNED"
local searchTerm = ""
local treeHooked = false
local applyHooked = false
local nativeFrame = nil
local nativeApplyButton = nil

local treeFrameCache = nil
local treeFrameCacheStamp = 0
local nodeButtonCache = {}
local liveNodes = {}
local filteredNodes = {}
ET.treeOrderReady = false
ET.treeOrderRoots = {}
local selectedNode = nil
local pendingSelections = {}
local pendingClick = nil
local lastObservedAsh = nil
local untrackedSpend = 0
local scanQueue = {}
local scanIndex = 1
local scanActive = false
local scanTotal = 0
local scanDone = 0
local scanAccumulator = 0

-- Runtime discovery is deliberately incremental. The original v0.0.1 tried to
-- match every one of the 813 catalog nodes against every live frame in one
-- synchronous pass. When Ebonhold had not exposed the expected node metadata,
-- that became an 813 x frame-count scan and could stall the 3.3.5 client.
local discoveryQueue = {}
local discoveryIndex = 1
local discoveryActive = false
local discoveryDone = 0
local discoveryTotal = 0
local discoveryAccumulator = 0
local discoveryPass = 0
local discoveryBound = 0
local discoveryTooltipMatches = 0
local discoveryDirectMatches = 0
local discoverySpellFallbackMatches = 0
local discoveryNativeTooltipReads = 0
local knownByNodeID = {}
local knownBySpellID = {}
local knownByNameCost = {}
local matchedDiscoveryFrames = {}
local nativeReadyWait = false
local nativeReadyAttempts = 0
local nativeReadyAccumulator = 0

local statusMessage = nil
local statusExpire = 0
local setStatus
local rebuildFiltered
local refreshRows
local nodeCost
local nodeAffordability
local syncNodeOwnership
local DISCOVERY_VALUE_KEYS

local ENDLESS_NAMES = {
    ["endless growth"] = "Endless Growth",
    ["endless vitality"] = "Endless Vitality",
    ["endless might"] = "Endless Might",
}

-- Project Ebonhold's own skill-tree.json exposes stable IDs for the three
-- infinite sinks.  Unlike the original AshBuild catalog, these nodes are not
-- anonymous runtime discoveries: they are first-class native nodes and can be
-- bound directly without asking the player to hover them.
ET.ENDLESS_DEFS = {
    ["endless vitality"] = { id = 2000, baseCost = 2000, growth = 1.25, capRank = 50, capCost = 100000000,
        description = "Increases your Stamina." },
    ["endless might"]    = { id = 2001, baseCost = 2000, growth = 1.25, capRank = 50, capCost = 100000000,
        description = "Increases your attack power or spell power, whichever is higher." },
    ["endless growth"]   = { id = 2002, baseCost = 2000, growth = 1.25, capRank = 50, capCost = 100000000,
        description = "Increases your Strength, Agility, Intellect or Spirit, whichever is highest." },
}
local tooltipHookInstalled = false
local tooltipPollAccumulator = 0
local nativeSuppressed = false
local nativeVisualState = {}

local function chat(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffCleanTree:|r " .. tostring(msg))
    end
end

local function stripColors(s)
    s = tostring(s or "")
    s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
    s = string.gsub(s, "|r", "")
    return s
end

local function trim(s)
    s = tostring(s or "")
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

local function compactSpace(s)
    s = stripColors(s or "")
    s = string.gsub(s, "\r", " ")
    s = string.gsub(s, "\n", " ")
    s = string.gsub(s, "%s+", " ")
    return trim(s)
end

local function lower(s)
    return string.lower(tostring(s or ""))
end

-- GetScript() on the 3.3.5 client throws when a script type is not valid for
-- that widget (for example OnClick on an ordinary Frame). Never probe scripts
-- directly during discovery; treat unsupported script types as simply absent.
local function safeGetScript(frame, scriptName)
    if not frame or not frame.GetScript then return nil end
    local ok, script = pcall(frame.GetScript, frame, scriptName)
    if ok and type(script) == "function" then return script end
    return nil
end

local function hasClickHandler(frame)
    if not frame then return false end
    if type(frame.Click) == "function" then return true end
    return safeGetScript(frame, "OnClick") ~= nil
end

local function formatNumber(n)
    n = tonumber(n)
    if not n then return "?" end
    local sign = n < 0 and "-" or ""
    n = math.floor(math.abs(n) + 0.5)
    local s = tostring(n)
    while true do
        local changed
        s, changed = string.gsub(s, "^(%d+)(%d%d%d)", "%1,%2")
        if changed == 0 then break end
    end
    return sign .. s
end

local function setBackdrop(frame, color)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left=4, right=4, top=4, bottom=4},
    })
    frame:SetBackdropColor(unpack(color or C.panel))
    frame:SetBackdropBorderColor(unpack(C.border))
end

local function parseAshText(text)
    if not text then return nil end
    local s = stripColors(text)
    local n = string.match(s, "[Ss]oul%s+[Aa]shes?%s*:%s*([%d,]+)")
    if not n then
        n = string.match(s, "([%d,]+)%s*/%s*[%d,]+")
    end
    if not n then return nil end
    n = string.gsub(n, ",", "")
    return tonumber(n)
end

local function readTextDeep(root, depth, seen)
    if not root or depth < 0 then return nil end
    seen = seen or {}
    if seen[root] then return nil end
    seen[root] = true

    if root.GetText then
        local ok, t = pcall(root.GetText, root)
        if ok and t then
            local n = parseAshText(t)
            if n then return n end
        end
    end

    if root.GetRegions then
        local regions = {root:GetRegions()}
        for _, r in ipairs(regions) do
            if r and r.GetText then
                local ok, t = pcall(r.GetText, r)
                if ok and t then
                    local n = parseAshText(t)
                    if n then return n end
                end
            end
        end
    end

    if depth > 0 and root.GetChildren then
        local children = {root:GetChildren()}
        for _, c in ipairs(children) do
            local n = readTextDeep(c, depth - 1, seen)
            if n then return n end
        end
    end
    return nil
end

local function readSoulAsh()
    -- EbonAPI gives us direct, safe access to ProjectEbonhold's Skill Tree frame.
    -- Prefer its pointsText because it reflects staged purchases immediately;
    -- fall back to SERVER_ASH when the native text has not populated yet.
    local bridge = _G.CleanTreeEbonAPI
    if bridge and bridge.GetAvailableAsh then
        local ash, source = bridge.GetAvailableAsh()
        -- SERVER_ASH is committed state and may lag a locally staged click. Do
        -- not use that fallback while waiting to observe a native +/- action.
        if ash ~= nil and (source ~= "server-ash" or not pendingClick) then return ash end
    end

    -- Legacy fallback retained for defensive compatibility with unusual client
    -- revisions. With the EbonAPI dependency this should rarely be needed.
    local bar = _G.skillTreeBottomBar
    if not bar then return nil end
    return readTextDeep(bar, 5, {})
end

local function shallowContainsValue(t, wantedNode, wantedSpell, depth, seen)
    if type(t) ~= "table" or depth <= 0 then return false end
    seen = seen or {}
    if seen[t] then return false end
    seen[t] = true

    local keys = {
        "id","ID","node","nodeId","nodeID","skillId","skillID",
        "spell","spellId","spellID","nextSpellId","nextSpellID",
        "_node","_data","data","nodeData","skillData","raw"
    }

    for _, k in ipairs(keys) do
        local ok, v = pcall(function() return t[k] end)
        if ok then
            if type(v) == "number" and (v == wantedNode or v == wantedSpell) then
                return true
            elseif type(v) == "table" and shallowContainsValue(v, wantedNode, wantedSpell, depth - 1, seen) then
                return true
            end
        end
    end
    return false
end

local function frameMatches(f, wantedNode, wantedSpell)
    if not f then return false end
    if wantedNode then
        local ok, id = pcall(function() return f:GetID() end)
        if ok and type(id) == "number" and id == wantedNode then return true end
    end
    return shallowContainsValue(f, wantedNode or -1, wantedSpell or -1, 3, {})
end

local function collectChildren(root, out, seen, depth, maxDepth)
    if not root or seen[root] or depth > maxDepth then return end
    seen[root] = true
    out[#out + 1] = root

    -- Some custom 3.3.5 ScrollFrames keep their useful content behind the
    -- scroll child. Follow it explicitly in addition to ordinary children.
    if root.GetScrollChild then
        local ok, child = pcall(root.GetScrollChild, root)
        if ok and child then
            collectChildren(child, out, seen, depth + 1, maxDepth)
        end
    end

    if root.GetChildren then
        local children = {root:GetChildren()}
        for _, c in ipairs(children) do
            collectChildren(c, out, seen, depth + 1, maxDepth)
        end
    end
end

local function clearTreeCaches()
    treeFrameCache = nil
    treeFrameCacheStamp = 0
    nodeButtonCache = {}
    -- Ebonhold may rebuild the native footer. Never keep an Apply button
    -- reference across a tree refresh because it may point at a dead frame.
    nativeApplyButton = nil
end

local function allTreeFrames()
    local now = (type(GetTime) == "function" and GetTime()) or 0
    if treeFrameCache and (now - treeFrameCacheStamp) < 1.0 then
        return treeFrameCache
    end

    local roots = {}
    if _G.skillTreeCanvas then roots[#roots + 1] = _G.skillTreeCanvas end
    if _G.skillTreeFrame then roots[#roots + 1] = _G.skillTreeFrame end
    if _G.skillTreeBottomBar then roots[#roots + 1] = _G.skillTreeBottomBar end

    local all, seen = {}, {}
    for _, root in ipairs(roots) do
        collectChildren(root, all, seen, 0, 14)
    end

    treeFrameCache = all
    treeFrameCacheStamp = now
    return all
end

local function staticRankFor(node, rank)
    if not node or not node.static or not node.static.ranks then return nil end
    for _, r in ipairs(node.static.ranks) do
        if r.rank == rank then return r end
    end
    return nil
end

local function firstSpellFor(node)
    if not node or not node.static or not node.static.ranks then return nil end
    local best
    for _, r in ipairs(node.static.ranks) do
        if not best or r.rank < best.rank then best = r end
    end
    return best and best.spell or nil
end

local function findNodeButton(nodeID, spellID)
    local key = tostring(nodeID or "?") .. ":" .. tostring(spellID or "?")
    local cached = nodeButtonCache[key]
    if cached and cached ~= false then return cached end

    local all = allTreeFrames()
    for _, f in ipairs(all) do
        if frameMatches(f, nodeID, spellID) and hasClickHandler(f) then
            nodeButtonCache[key] = f
            return f
        end
    end
    return nil
end

local function clickFrame(f, mouseButton)
    if not f then return false, "no frame" end
    mouseButton = mouseButton or "LeftButton"
    if f.IsEnabled then
        local ok, enabled = pcall(f.IsEnabled, f)
        if ok and enabled == false then return false, "button disabled" end
    end

    -- On this 3.3.5 client Button:Click("RightButton") does not reliably
    -- propagate the mouse-button argument through Ebonhold's custom wrappers.
    -- For native unstage/right-click behavior, invoke the actual OnClick script
    -- first so the handler receives "RightButton" exactly as a physical click.
    if mouseButton == "RightButton" then
        local script = safeGetScript(f, "OnClick")
        if script then
            local ok, err = pcall(script, f, "RightButton")
            if ok then return true, "OnClick(RightButton)" end
            return false, tostring(err)
        end
        local down = safeGetScript(f, "OnMouseDown")
        local up = safeGetScript(f, "OnMouseUp")
        if down or up then
            local ok, err = pcall(function()
                if down then down(f, "RightButton") end
                if up then up(f, "RightButton") end
            end)
            if ok then return true, "MouseDown/Up(RightButton)" end
            return false, tostring(err)
        end
    end

    if f.Click then
        local ok, err = pcall(f.Click, f, mouseButton)
        if ok then return true, "Click" end
        return false, tostring(err)
    end
    local script = safeGetScript(f, "OnClick")
    if script then
        local ok2, err = pcall(script, f, mouseButton)
        if ok2 then return true, "OnClick" end
        return false, tostring(err)
    end
    return false, "no click handler"
end

local function collectRightClickCandidates(root)
    local out, seen = {}, {}
    local function clickable(f)
        return f and (safeGetScript(f, "OnClick") or safeGetScript(f, "OnMouseDown") or safeGetScript(f, "OnMouseUp") or type(f.Click) == "function")
    end
    local function add(f, depth)
        if not f or seen[f] or depth < 0 then return end
        seen[f] = true
        if clickable(f) then out[#out + 1] = f end
        if depth > 0 and f.GetChildren then
            local children = {f:GetChildren()}
            for _, c in ipairs(children) do add(c, depth - 1) end
        end
    end

    -- Start with the exact frame that accepted the original purchase click,
    -- then its small child hierarchy. Some Ebonhold nodes put left-click and
    -- right-click handlers on different layers of the same widget.
    add(root, 2)

    -- Also inspect a short parent chain. This is intentionally bounded so we
    -- never wander up into the whole Skill Tree canvas/window.
    local p = root
    for _ = 1, 3 do
        if not p or not p.GetParent then break end
        local ok, parent = pcall(p.GetParent, p)
        if not ok or not parent then break end
        p = parent
        if clickable(p) and not seen[p] then
            seen[p] = true
            out[#out + 1] = p
        end
    end
    return out
end

local function collectFrameTexts(root, out, seen, depth)
    if not root or depth < 0 then return end
    seen = seen or {}
    if seen[root] then return end
    seen[root] = true

    if root.GetText then
        local ok, t = pcall(root.GetText, root)
        if ok and t and t ~= "" then out[#out + 1] = compactSpace(t) end
    end
    if root.GetRegions then
        local regions = {root:GetRegions()}
        for _, r in ipairs(regions) do
            if r and r.GetText then
                local ok, t = pcall(r.GetText, r)
                if ok and t and t ~= "" then out[#out + 1] = compactSpace(t) end
            end
        end
    end
    if depth > 0 and root.GetChildren then
        local children = {root:GetChildren()}
        for _, c in ipairs(children) do
            collectFrameTexts(c, out, seen, depth - 1)
        end
    end
end

local function nativeTreeLooksLoading()
    local root = _G.skillTreeFrame or _G.skillTreeCanvas
    if not root then return true end
    local texts = {}
    collectFrameTexts(root, texts, {}, 5)
    for _, t in ipairs(texts) do
        local v = lower(t)
        if string.find(v, "skill tree loading", 1, true) then return true end
    end
    return false
end

local function frameRank(button)
    local texts = {}
    collectFrameTexts(button, texts, {}, 2)
    for _, t in ipairs(texts) do
        local cur, max = string.match(t, "(%d+)%s*/%s*(%d+)")
        cur, max = tonumber(cur), tonumber(max)
        if cur and max then return cur, max, cur .. "/" .. max end
    end
    return nil, nil, nil
end

local function isFrameEnabled(button)
    if not button then return false end
    if button.IsEnabled then
        local ok, v = pcall(button.IsEnabled, button)
        if ok then return v ~= false end
    end
    return true
end

-- Ebonhold can leave a metadata/click wrapper enabled while the actual node
-- control underneath it is locked by prerequisites. Look for stronger disabled
-- evidence inside the small native node widget before calling a node AVAILABLE.
local function frameExplicitlyDisabled(frame)
    if not frame then return false end
    if frame.IsEnabled then
        local ok, enabled = pcall(frame.IsEnabled, frame)
        if ok and enabled == false then return true end
    end
    if frame.GetAlpha then
        local ok, alpha = pcall(frame.GetAlpha, frame)
        if ok and type(alpha) == "number" and alpha < 0.45 then return true end
    end
    if frame.GetRegions then
        local regions = {frame:GetRegions()}
        for _, r in ipairs(regions) do
            if r and r.IsDesaturated then
                local ok, desat = pcall(r.IsDesaturated, r)
                if ok and desat == true then return true end
            end
        end
    end
    return false
end

local function nextSpellFor(node)
    if not node or not node.static or not node.static.ranks then return nil end
    local target = (tonumber(node.currentRank) or 0) + 1
    local r = staticRankFor(node, target)
    if r then return r.spell end
    return firstSpellFor(node)
end

local function nodeWidgetHasDisabledControl(node)
    if not node or not node.button then return false end
    local wantedSpell = nextSpellFor(node)
    local candidates, seen = {}, {}
    collectChildren(node.button, candidates, seen, 0, 3)

    -- The metadata wrapper and the actual Button can be siblings. Inspect the
    -- immediate parent subtree too, but only controls that match this node.
    if node.button.GetParent then
        local ok, parent = pcall(node.button.GetParent, node.button)
        if ok and parent then collectChildren(parent, candidates, seen, 0, 2) end
    end

    for _, f in ipairs(candidates) do
        if hasClickHandler(f) and frameMatches(f, node.id, wantedSpell) then
            if frameExplicitlyDisabled(f) then return true end
        end
    end
    return false
end

local AVAIL_POSITIVE_KEYS = {
    "canLearn", "CanLearn", "available", "isAvailable", "IsAvailable",
    "unlocked", "isUnlocked", "IsUnlocked", "canPurchase", "purchasable",
    "canBuy", "canSpend", "learnable",
}
local AVAIL_NEGATIVE_KEYS = {
    "locked", "isLocked", "IsLocked", "disabled", "isDisabled", "IsDisabled",
    "unavailable", "isUnavailable", "blocked", "isBlocked",
}

local function nativeAvailabilityFromTable(t, depth, seen)
    if type(t) ~= "table" or depth <= 0 then return nil end
    seen = seen or {}
    if seen[t] then return nil end
    seen[t] = true

    for _, k in ipairs(AVAIL_POSITIVE_KEYS) do
        local ok, v = pcall(function() return t[k] end)
        -- Positive state is useful when explicitly true. A false value on a
        -- wrapper is too ambiguous on Ebonhold and previously disabled every row.
        if ok and v == true then return true, "runtime." .. k end
    end
    for _, k in ipairs(AVAIL_NEGATIVE_KEYS) do
        local ok, v = pcall(function() return t[k] end)
        if ok and type(v) == "boolean" and v == true then return false, "runtime." .. k end
    end
    for _, k in ipairs(DISCOVERY_VALUE_KEYS or {}) do
        local ok, v = pcall(function() return t[k] end)
        if ok and type(v) == "table" then
            local value, why = nativeAvailabilityFromTable(v, depth - 1, seen)
            if value ~= nil then return value, why end
        end
    end
    return nil
end

local function milestonePrerequisitesSatisfied(node)
    if not node or node.isEndless then return true end
    local name = compactSpace(node.name or "")
    local base = string.match(name, "^(.-)%s+[Mm]ilestone$")
    if not base or base == "" then return true end

    local thisCost = tonumber(nodeCost and nodeCost(node))
    local foundPrereq = false
    for _, other in pairs(liveNodes or {}) do
        if other ~= node and not other.isEndless then
            local otherName = compactSpace(other.name or "")
            local otherBase = string.gsub(otherName, "%s*%([Rr]ank%s+%d+%)%s*$", "")
            if lower(otherBase) == lower(base) and not string.find(lower(otherName), "milestone", 1, true) then
                local otherCost = tonumber(nodeCost and nodeCost(other))
                if not thisCost or not otherCost or otherCost < thisCost then
                    foundPrereq = true
                    syncNodeOwnership(other)
                    if not other.fullyOwned then return false end
                end
            end
        end
    end
    return true
end

local function nodeStructuralAvailability(node)
    if not node then return false, "missing" end
    if node.fullyOwned and not node.isEndless then return false, "owned" end
    if not node.button then return false, "unbound" end
    if node.nativeRejected then return false, "rejected" end

    -- Endless sinks are roots and never max out. Cost/affordability is handled
    -- separately; the live native widget remains the final click authority.
    if node.isEndless then return true, "endless" end

    -- EbonAPI live Talent Database path. Unlike the old wrapper enabled-state
    -- heuristic, this is the same prerequisite graph ProjectEbonhold itself
    -- publishes. Every incoming parent must be at its full current/staged rank.
    local bridge = _G.CleanTreeEbonAPI
    local id = tonumber(node.id)
    if bridge and bridge.GetNodeDef and id and bridge.GetNodeDef(id) then
        if bridge.IsStart and bridge.IsStart(id) then return true, "ebonapi-root" end
        local prereqs = bridge.GetParents and bridge.GetParents(id) or nil
        if not prereqs or #prereqs == 0 then return false, "ebonapi-no-prereq" end
        for _, parentID in ipairs(prereqs) do
            local parentRank = bridge.GetCurrentRank and bridge.GetCurrentRank(parentID) or nil
            local serverRank = bridge.GetServerRank and bridge.GetServerRank(parentID) or nil
            if parentRank == nil then parentRank = serverRank end
            if serverRank and (parentRank == nil or serverRank > parentRank) then parentRank = serverRank end
            local parentMax = bridge.GetMaxRank and bridge.GetMaxRank(parentID) or nil
            if not parentMax or parentMax < 1 or (tonumber(parentRank) or 0) < parentMax then
                return false, "ebonapi-prereq:" .. tostring(parentID)
            end
        end
        return true, "ebonapi-prereqs"
    end

    -- Captured graph fallback for defensive compatibility.
    local graph = EbonTreeOrderData
    local prereqs = graph and graph.parentsById and id and graph.parentsById[id] or nil
    local graphDepth = graph and graph.depthById and id and tonumber(graph.depthById[id]) or nil
    if prereqs then
        for _, parentID in ipairs(prereqs) do
            local parent = liveNodes["node:" .. tostring(parentID)]
            if not parent then return false, "graph-parent-missing" end
            syncNodeOwnership(parent)
            if not parent.fullyOwned then return false, "graph-prereq:" .. tostring(parentID) end
        end
        return true, "graph-prereqs"
    elseif graphDepth == 0 then
        return true, "graph-root"
    end

    if not milestonePrerequisitesSatisfied(node) then return false, "milestone-prereq" end
    local runtimeAvailable, runtimeWhy = nativeAvailabilityFromTable(node.button, 3, {})
    if runtimeAvailable ~= nil then return runtimeAvailable, runtimeWhy end
    if node.nativeCanLearn == true then return true, "tooltip" end
    if node.nativeCanLearn == false then
        local affordable = nodeAffordability and nodeAffordability(node)
        if affordable ~= false then return false, "tooltip-no-learn" end
    end
    if not isFrameEnabled(node.button) then return false, "disabled" end
    return true, "enabled"
end

local function readGameTooltipLines()
    local lines = {}
    local maxLines = 30
    if GameTooltip and GameTooltip.NumLines then
        local ok, n = pcall(GameTooltip.NumLines, GameTooltip)
        if ok and tonumber(n) then maxLines = math.max(maxLines, tonumber(n)) end
    end
    for i = 1, maxLines do
        local left = _G["GameTooltipTextLeft" .. i]
        local right = _G["GameTooltipTextRight" .. i]
        local lt, rt
        if left and left.GetText then
            local ok, v = pcall(left.GetText, left)
            if ok then lt = compactSpace(v) end
        end
        if right and right.GetText then
            local ok, v = pcall(right.GetText, right)
            if ok then rt = compactSpace(v) end
        end
        if lt and lt ~= "" then lines[#lines + 1] = lt end
        if rt and rt ~= "" and rt ~= lt then lines[#lines + 1] = rt end
    end
    return lines
end

local function tooltipLooksLikeSkillNode(lines)
    if not lines or #lines == 0 then return false end
    local joined = lower(table.concat(lines, " "))
    return string.find(joined, "rank", 1, true) ~= nil
        and string.find(joined, "soul ash", 1, true) ~= nil
end

local function tooltipCanLearn(lines)
    if not lines or #lines == 0 then return false end
    local joined = lower(table.concat(lines, " "))
    return string.find(joined, "left-click to learn", 1, true) ~= nil
        or string.find(joined, "left click to learn", 1, true) ~= nil
        or string.find(joined, "click to learn", 1, true) ~= nil
end

local function tooltipFromExactFrame(frame)
    if not frame or not GameTooltip then return nil end
    local onEnter = safeGetScript(frame, "OnEnter")
    if type(onEnter) ~= "function" then return nil end

    local oldAlpha = 1
    if GameTooltip.GetAlpha then
        local ok, a = pcall(GameTooltip.GetAlpha, GameTooltip)
        if ok and a then oldAlpha = a end
    end

    pcall(GameTooltip.Hide, GameTooltip)
    if GameTooltip.SetAlpha then pcall(GameTooltip.SetAlpha, GameTooltip, 0) end
    local ok = pcall(onEnter, frame)
    local lines = ok and readGameTooltipLines() or {}
    local onLeave = safeGetScript(frame, "OnLeave")
    if type(onLeave) == "function" then pcall(onLeave, frame) end
    pcall(GameTooltip.Hide, GameTooltip)
    if GameTooltip.SetAlpha then pcall(GameTooltip.SetAlpha, GameTooltip, oldAlpha) end

    if #lines == 0 then return nil end
    return lines
end

local function tooltipFromButton(button)
    if not button then return nil end

    -- The frame carrying Ebonhold's node/spell metadata is not always the frame
    -- carrying OnEnter. Search the small node widget and its descendants instead
    -- of assuming those responsibilities live on the same object.
    local candidates, seen = {}, {}
    collectChildren(button, candidates, seen, 0, 3)

    local fallback = nil
    for _, f in ipairs(candidates) do
        if safeGetScript(f, "OnEnter") then
            local lines = tooltipFromExactFrame(f)
            if lines and #lines > 0 then
                if tooltipLooksLikeSkillNode(lines) then
                    return lines
                end
                if not fallback then fallback = lines end
            end
        end
    end

    -- Occasionally the metadata is attached one level below the actual node
    -- button. Try the immediate parent last, but never walk the whole tree.
    if button.GetParent then
        local ok, parent = pcall(button.GetParent, button)
        if ok and parent and parent ~= button and safeGetScript(parent, "OnEnter") then
            local lines = tooltipFromExactFrame(parent)
            if lines and tooltipLooksLikeSkillNode(lines) then return lines end
            if lines and #lines > 0 and not fallback then fallback = lines end
        end
    end

    return fallback
end

local spellScanTooltip = nil

local function getSpellScanTooltip()
    if spellScanTooltip then return spellScanTooltip end
    if not UIParent then return nil end
    spellScanTooltip = CreateFrame("GameTooltip", "EbonTreeSpellScanTooltip", UIParent, "GameTooltipTemplate")
    if spellScanTooltip.SetOwner then spellScanTooltip:SetOwner(UIParent, "ANCHOR_NONE") end
    return spellScanTooltip
end

local function readNamedTooltipLines(tt)
    local lines = {}
    if not tt or not tt.GetName then return lines end
    local name = tt:GetName()
    if not name then return lines end
    local count = 30
    if tt.NumLines then
        local ok, n = pcall(tt.NumLines, tt)
        if ok and tonumber(n) then count = math.max(count, tonumber(n)) end
    end
    for i = 1, count do
        local left = _G[name .. "TextLeft" .. i]
        local right = _G[name .. "TextRight" .. i]
        local lt, rt
        if left and left.GetText then
            local ok, v = pcall(left.GetText, left)
            if ok then lt = compactSpace(v) end
        end
        if right and right.GetText then
            local ok, v = pcall(right.GetText, right)
            if ok then rt = compactSpace(v) end
        end
        if lt and lt ~= "" then lines[#lines + 1] = lt end
        if rt and rt ~= "" and rt ~= lt then lines[#lines + 1] = rt end
    end
    return lines
end

local function tooltipFromSpellID(spellID)
    spellID = tonumber(spellID)
    if not spellID then return nil end
    local tt = getSpellScanTooltip()
    if not tt then return nil end

    local function prepare()
        if tt.ClearLines then pcall(tt.ClearLines, tt) end
        if tt.SetOwner then pcall(tt.SetOwner, tt, UIParent, "ANCHOR_NONE") end
    end

    prepare()
    if tt.SetSpellByID then
        pcall(tt.SetSpellByID, tt, spellID)
        local lines = readNamedTooltipLines(tt)
        if #lines > 0 then
            if tt.Hide then pcall(tt.Hide, tt) end
            return lines
        end
    end

    prepare()
    if tt.SetHyperlink then
        pcall(tt.SetHyperlink, tt, "spell:" .. tostring(spellID))
        local lines = readNamedTooltipLines(tt)
        if tt.Hide then pcall(tt.Hide, tt) end
        if #lines > 0 then return lines end
    end

    if tt.Hide then pcall(tt.Hide, tt) end
    return nil
end

local function parseTooltip(lines, fallbackName)
    if not lines or #lines == 0 then return nil end
    local tip = {
        name = compactSpace(lines[1] or fallbackName or "Unknown"),
        lines = lines,
        descriptionLines = {},
        carryPrestige = false,
    }

    local joined = table.concat(lines, " ")
    local cur, max = string.match(joined, "[Rr]ank:%s*(%d+)%s*/%s*(%d+)")
    if cur then
        tip.currentRank, tip.maxRank = tonumber(cur), tonumber(max)
        tip.rankText = tostring(cur) .. "/" .. tostring(max)
    else
        local one = string.match(joined, "[Rr]ank:%s*(%d+)")
        if one then
            tip.currentRank = tonumber(one)
            tip.rankText = tostring(one)
        end
    end

    local cost = string.match(joined, "([%d,]+)%s+[Ss]oul%s+[Aa]shes?")
    if cost then
        tip.cost = tonumber((string.gsub(cost, ",", "")))
    end

    for i = 2, #lines do
        local line = compactSpace(lines[i])
        local low = lower(line)
        if string.find(low, "carry over prestige", 1, true) then
            tip.carryPrestige = true
        elseif string.find(low, "rank:", 1, true) then
            -- rank line; ignore in effect description
        elseif string.find(low, "soul ash", 1, true) then
            -- cost line; ignore in effect description
        elseif line ~= "" then
            tip.descriptionLines[#tip.descriptionLines + 1] = line
        end
    end

    tip.description = compactSpace(table.concat(tip.descriptionLines, " "))
    return tip
end

local function isConditionalDescription(desc)
    local s = lower(desc)
    local needles = {
        "whenever ", "when ", "while ", "chance to ", "chance of ", " proc", "trigger", " for ", "stacks", "after ",
        "upon ", "each time", "every time", "if ", "below ", "above "
    }
    for _, n in ipairs(needles) do
        if string.find(s, n, 1, true) then return true end
    end
    return false
end

local function titleCaseSimple(s)
    s = compactSpace(s)
    if s == "" then return s end
    return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

ET.CART_EFFECT_ORDER = {
    SPELL_POWER = 10,
    ATTACK_POWER = 20,
    STRENGTH = 30,
    AGILITY = 40,
    STAMINA = 50,
    INTELLECT = 60,
    SPIRIT = 70,
    HIT_PERCENT = 80,
    HIT_RATING = 81,
    CRIT_PERCENT = 90,
    CRIT_RATING = 91,
    HASTE_PERCENT = 100,
    HASTE_RATING = 101,
    ARMOR = 110,
    HEALTH = 120,
    MANA = 130,
}

function ET.NormalizeEffectKey(rawKey, unit)
    local raw = compactSpace(rawKey or "")
    local low = lower(raw)
    low = string.gsub(low, "^your%s+", "")
    unit = unit or ""

    local key, label
    local recognized = true
    if low == "spell power" then key, label = "SPELL_POWER", "Spell Power"
    elseif low == "attack power" then key, label = "ATTACK_POWER", "Attack Power"
    elseif low == "strength" then key, label = "STRENGTH", "Strength"
    elseif low == "agility" then key, label = "AGILITY", "Agility"
    elseif low == "stamina" then key, label = "STAMINA", "Stamina"
    elseif low == "intellect" then key, label = "INTELLECT", "Intellect"
    elseif low == "spirit" then key, label = "SPIRIT", "Spirit"
    elseif low == "hit chance" then key, label = "HIT_PERCENT", "Hit Chance"
    elseif low == "hit rating" then key, label = "HIT_RATING", "Hit Rating"
    elseif low == "critical strike chance" or low == "crit chance" then key, label = "CRIT_PERCENT", "Critical Strike Chance"
    elseif low == "critical strike rating" or low == "crit rating" then key, label = "CRIT_RATING", "Critical Strike Rating"
    elseif low == "haste" or low == "haste rating" then
        if unit == "%" then key, label = "HASTE_PERCENT", "Haste"
        else key, label = "HASTE_RATING", "Haste Rating" end
    elseif low == "armor" then key, label = "ARMOR", "Armor"
    elseif low == "health" then key, label = "HEALTH", "Health"
    elseif low == "mana" then key, label = "MANA", "Mana"
    elseif string.sub(low, 1, 16) == "experience from " then
        local source = compactSpace(string.sub(raw, 17))
        key = "EXPERIENCE_FROM:" .. lower(source)
        label = "Experience from " .. source
    else
        key = "RAW:" .. low
        label = titleCaseSimple(raw)
        recognized = false
    end

    local order = ET.CART_EFFECT_ORDER[key] or 900
    return key, label, order, recognized
end

local function summarizeEffect(desc)
    desc = compactSpace(desc)
    if desc == "" then
        return {text = "Effect unavailable until inspected", aggregate = false}
    end

    local source, amount = string.match(desc, "[Ii]ncreases experience gained from (.-) by an additional ([%d%.]+)%%")
    if source and amount then
        return {
            text = "+" .. amount .. "% experience from " .. source,
            key = "EXPERIENCE_FROM:" .. lower(compactSpace(source)),
            display = "Experience from " .. compactSpace(source),
            order = 900,
            amount = tonumber(amount), unit = "%", aggregate = true,
        }
    end

    local immune = string.match(desc, "[Yy]ou are immune to ([^%.]+)")
    if immune then
        return {text = "Immune to " .. compactSpace(immune), aggregate = false}
    end

    if not isConditionalDescription(desc) then
        local stat, amount2, pct = string.match(desc, "[Ii]ncreases your (.-) by ([%d%.]+)(%%?)%.")
        if not stat then
            stat, amount2, pct = string.match(desc, "[Ii]ncreases (.-) by ([%d%.]+)(%%?)%.")
        end
        if stat and amount2 then
            stat = titleCaseSimple(stat)
            local unit = (pct == "%") and "%" or ""
            local key, display, order, recognized = ET.NormalizeEffectKey(stat, unit)
            if recognized then
                return {
                    text = "+" .. amount2 .. unit .. " " .. display,
                    key = key, display = display, order = order, sourceKey = stat,
                    amount = tonumber(amount2), unit = unit, aggregate = true,
                }
            end
        end
    end

    return {text = desc, aggregate = false}
end

function ET.ParseNodeEffect(desc)
    return summarizeEffect(desc)
end

local function descriptionFromSpellTooltip(lines)
    if not lines or #lines == 0 then return nil, nil end
    local name = compactSpace(lines[1] or "")
    local desc = {}
    for i = 2, #lines do
        local line = compactSpace(lines[i])
        local low = lower(line)
        if line ~= ""
            and not string.match(low, "^rank%s+%d+")
            and low ~= "passive"
            and low ~= "instant"
        then
            desc[#desc + 1] = line
        end
    end
    local joined = compactSpace(table.concat(desc, " "))
    if joined == "" then joined = nil end
    return name ~= "" and name or nil, joined
end

local function staticSpellForDisplay(node)
    if not node or not node.static or not node.static.ranks then return nil end
    local cur = tonumber(node.currentRank) or 0
    local max = tonumber(node.static.maxRank) or tonumber(node.maxRank) or 1
    local target = cur + 1
    if target > max then target = max end
    if target < 1 then target = 1 end
    local r = staticRankFor(node, target)
    if r then return r.spell end
    r = staticRankFor(node, 1)
    return r and r.spell or nil
end

local function updateNodeFromSpellTooltip(node, force)
    if not node then return false end
    if node.description and node.description ~= "" and not force then return true end
    local spellID = node.runtimeSpellID or staticSpellForDisplay(node) or firstSpellFor(node)
    if not spellID then return false end
    local lines = tooltipFromSpellID(spellID)
    if not lines then return false end
    local spellName, desc = descriptionFromSpellTooltip(lines)
    if spellName and (not node.name or node.name == "") then node.name = spellName end
    if desc and desc ~= "" then
        node.description = desc
        node.effect = summarizeEffect(desc)
        node.effectSource = "spell"
        return true
    end
    return false
end

local function updateNodeFromTooltip(node, force)
    if not node then return false end
    if node.tooltip and node.description and node.description ~= "" and not force then return true end
    -- Runtime discovery owns node binding. Do not launch a full-tree search
    -- from row refresh/detail rendering. We inspect only the already-bound
    -- node widget (plus its tiny child hierarchy).
    local button = node.button
    if button then
        local lines = tooltipFromButton(button)
        if lines and tooltipLooksLikeSkillNode(lines) then
            local tip = parseTooltip(lines, node.name)
            if tip then
                node.tooltip = tip
                node.nativeCanLearn = tooltipCanLearn(lines)
                if tip.name and tip.name ~= "" then node.name = tip.name end
                if tip.currentRank ~= nil then node.currentRank = tip.currentRank end
                if tip.maxRank ~= nil then node.maxRank = tip.maxRank end
                if tip.rankText then node.rankText = tip.rankText end
                if tip.cost then node.cost = tip.cost end
                node.carryPrestige = tip.carryPrestige
                node.description = tip.description
                node.effect = summarizeEffect(tip.description)
                node.effectSource = "native"
                if string.find(lower(node.name), "endless", 1, true) then
                    node.category = "ENDLESS"
                    node.isEndless = true
                end
                return true
            end
        end
    end

    -- Finite nodes already give us a spell id through AshBuild's catalog.
    -- Spell tooltips are a much more reliable source of the human-readable
    -- effect than synthetically hovering the custom Ebonhold widget.
    return updateNodeFromSpellTooltip(node, force)
end

local function nextStaticCost(node)
    if not node or not node.static then return nil end
    local cur = tonumber(node.currentRank) or 0
    local target = cur + 1
    local r = staticRankFor(node, target)
    if r then return r.cost end
    if cur == 0 then
        r = staticRankFor(node, 1)
        if r then return r.cost end
    end
    return nil
end

local function nodeRankDisplay(node)
    if node.rankText then return node.rankText end
    local cur = tonumber(node.currentRank)
    local max = tonumber(node.maxRank)
    if cur and max then return cur .. "/" .. max end
    if max then return "? / " .. max end
    if cur then return tostring(cur) end
    return "?"
end

nodeCost = function(node)
    -- The live Talent Database is authoritative for both finite rank costs and
    -- the exponential Endless sinks. This removes the old tooltip dependency.
    local bridge = _G.CleanTreeEbonAPI
    if bridge and bridge.GetNextCost and node and node.id then
        local cost = bridge.GetNextCost(node.id, tonumber(node.currentRank) or 0)
        if cost and cost > 0 then return cost end
    end
    if node.cost then return node.cost end
    return nextStaticCost(node)
end

nodeAffordability = function(node, ash)
    local cost = nodeCost(node)
    if ash == nil then ash = readSoulAsh() end
    if not cost or ash == nil then return nil, cost, ash end
    return ash >= cost, cost, ash
end

local function liveRankFromFrame(node)
    if not node or not node.button then return false end
    local cur, max, txt = frameRank(node.button)
    if cur == nil or max == nil or cur < 0 or max <= 0 or cur > max then return false end

    -- A direct metadata match can land on a small wrapper containing another
    -- node's rank text. Reject rank text that cannot belong to this catalog node.
    local staticMax = node.static and tonumber(node.static.maxRank) or nil
    if staticMax and tonumber(max) ~= staticMax then return false end

    node.currentRank = cur
    node.maxRank = max
    node.rankText = txt
    return true
end

local function spellIsKnown(spellID)
    if not spellID then return false end
    if type(IsSpellKnown) == "function" then
        local ok, v = pcall(IsSpellKnown, spellID)
        if ok and v then return true end
    end
    if type(IsPlayerSpell) == "function" then
        local ok, v = pcall(IsPlayerSpell, spellID)
        if ok and v then return true end
    end
    return false
end

syncNodeOwnership = function(node)
    if not node then return end

    -- EbonAPI path: the Talent Database tells us each node's real max rank, the
    -- native skillTreeNode<ID> widget tells us the current (including staged)
    -- rank, and SERVER_LOADOUT tells us what is actually committed on the
    -- server. Keeping both ranks lets Cart/Unowned react to staged purchases
    -- while Purchased remains a committed-state view.
    local bridge = _G.CleanTreeEbonAPI
    if bridge and bridge.GetNodeDef and node.id and bridge.GetNodeDef(node.id) then
        if bridge.IsInfinite and bridge.IsInfinite(node.id) then node.isEndless = true end
        local liveRank = bridge.GetCurrentRank and bridge.GetCurrentRank(node.id) or nil
        local committedRank = bridge.GetServerRank and bridge.GetServerRank(node.id) or nil
        local current = tonumber(liveRank)
        local committed = tonumber(committedRank)
        if current == nil then current = committed end
        if current ~= nil then
            if committed and committed > current then current = committed end
            node.currentRank = math.max(0, current)
            node.committedRank = math.max(0, committed or 0)
            if node.isEndless then
                node.maxRank = nil
                node.rankText = tostring(node.currentRank)
                node.fullyOwned = false
                node.fullyCommitted = false
            else
                local maxRank = tonumber(bridge.GetMaxRank and bridge.GetMaxRank(node.id))
                    or tonumber(node.static and node.static.maxRank) or tonumber(node.maxRank) or 1
                if maxRank < 1 then maxRank = tonumber(node.static and node.static.maxRank) or 1 end
                node.maxRank = maxRank
                node.rankText = tostring(node.currentRank) .. "/" .. tostring(maxRank)
                node.fullyOwned = node.currentRank >= maxRank
                if bridge.HasServerLoadout and bridge.HasServerLoadout() then
                    node.fullyCommitted = node.committedRank >= maxRank
                else
                    node.fullyCommitted = node.fullyOwned
                end
            end
            node.ownedSource = "ebonapi"
            return
        end
    end

    -- Legacy fallback for a node whose native widget has not been created yet.
    if node.isEndless then
        node.fullyOwned = false
        node.fullyCommitted = false
        return
    end

    local maxRank = tonumber(node.static and node.static.maxRank) or tonumber(node.maxRank) or 1
    local knownRank = 0
    if node.static and node.static.ranks then
        for _, r in ipairs(node.static.ranks) do
            if r.spell and spellIsKnown(r.spell) and (tonumber(r.rank) or 0) > knownRank then
                knownRank = tonumber(r.rank) or knownRank
            end
        end
    end

    local frameRankValue = nil
    local cur, max = nil, nil
    if node.button then
        cur, max = frameRank(node.button)
        cur, max = tonumber(cur), tonumber(max)
        if cur and max and cur >= 0 and max > 0 and cur <= max and max == maxRank then
            frameRankValue = cur
        end
    end

    local nativeTipRank = nil
    if node.tooltip and tonumber(node.currentRank) and tonumber(node.maxRank) == maxRank then
        local nr = tonumber(node.currentRank)
        if nr >= 0 and nr <= maxRank then nativeTipRank = nr end
    end

    local current = knownRank
    if frameRankValue and frameRankValue > current then current = frameRankValue end
    if nativeTipRank and nativeTipRank > current then current = nativeTipRank end
    node.currentRank = current
    node.committedRank = current
    node.maxRank = maxRank
    node.rankText = tostring(current) .. "/" .. tostring(maxRank)
    node.fullyOwned = current >= maxRank
    node.fullyCommitted = node.fullyOwned
    if knownRank > 0 then
        node.ownedSource = "spell-known"
    elseif frameRankValue ~= nil then
        node.ownedSource = "rank-text"
    else
        node.ownedSource = "none"
    end
end

local function buildKnownNodes()
    ET.treeOrderReady = false
    ET.treeOrderRoots = {}
    local preservedEndless = {}
    for key, node in pairs(liveNodes or {}) do
        if node and node.isEndless and node.preserveRuntime then
            preservedEndless[key] = node
        end
    end

    liveNodes = {}
    for id, def in pairs(DATA.nodes or {}) do
        local n = {
            id = id,
            key = "node:" .. tostring(id),
            name = string.gsub(def.name or ("Node " .. tostring(id)), "%s*%(Rank%s+%d+%)%s*$", ""),
            category = def.category or "OTHER",
            static = def,
            maxRank = def.maxRank or 1,
            isRuntimeOnly = false,
        }
        liveNodes[n.key] = n
    end

    -- AshBuild intentionally omits the three infinite sinks. EbonTree does not.
    -- Keep stable placeholders so the Endless tab always exposes them, then bind
    -- each placeholder to its live native widget as soon as discovery or a real
    -- native hover gives us authoritative rank/effect/cost data.
    for lowName, displayName in pairs(ENDLESS_NAMES) do
        local key = "endless:" .. lowName
        local old = preservedEndless[key]
        local endlessDef = ET.ENDLESS_DEFS[lowName] or {}
        if old then
            old.id = endlessDef.id or old.id
            old.name = displayName
            old.category = "ENDLESS"
            old.isEndless = true
            old.isRuntimeOnly = true
            old.preserveRuntime = true
            old.infinite = true
            old.growth = endlessDef.growth or old.growth
            old.baseCost = endlessDef.baseCost or old.baseCost
            old.fullyOwned = false
            liveNodes[key] = old
        else
            liveNodes[key] = {
                id = endlessDef.id,
                key = key,
                name = displayName,
                category = "ENDLESS",
                isEndless = true,
                isRuntimeOnly = true,
                preserveRuntime = true,
                infinite = true,
                growth = endlessDef.growth,
                baseCost = endlessDef.baseCost,
                fullyOwned = false,
            }
        end
    end
end

local function normalizeNodeName(name)
    local n = lower(compactSpace(name or ""))
    n = string.gsub(n, "%s*%(rank%s+%d+%)%s*$", "")
    return n
end

local function rebuildKnownIndexes()
    knownByNodeID = {}
    knownBySpellID = {}
    knownByNameCost = {}

    for _, node in pairs(liveNodes) do
        -- Endless nodes are runtime-only relative to AshBuild, but the official
        -- Ebonhold web builder gives them stable native IDs (2000-2002). Index
        -- those IDs too so discovery can bind them exactly like finite nodes.
        if node.id then knownByNodeID[node.id] = node end
        if not node.isRuntimeOnly then
            if node.static and node.static.ranks then
                for _, r in ipairs(node.static.ranks) do
                    if r.spell then knownBySpellID[r.spell] = node end
                    if r.cost then
                        local key = normalizeNodeName(node.name) .. "|" .. tostring(r.cost)
                        local list = knownByNameCost[key]
                        if not list then list = {}; knownByNameCost[key] = list end
                        list[#list + 1] = node
                    end
                end
            end
        end
    end
end

DISCOVERY_VALUE_KEYS = {
    "id","ID","node","nodeId","nodeID","skillId","skillID",
    "spell","spellId","spellID","nextSpellId","nextSpellID",
    "_node","_data","data","nodeData","skillData","raw"
}

local function knownNodeFromValueTable(t, depth, seen)
    if type(t) ~= "table" or depth <= 0 then return nil end
    seen = seen or {}
    if seen[t] then return nil end
    seen[t] = true

    for _, k in ipairs(DISCOVERY_VALUE_KEYS) do
        local ok, v = pcall(function() return t[k] end)
        if ok then
            if type(v) == "number" then
                local n = knownByNodeID[v] or knownBySpellID[v]
                if n then return n end
            elseif type(v) == "table" then
                local n = knownNodeFromValueTable(v, depth - 1, seen)
                if n then return n end
            end
        end
    end
    return nil
end

local function directKnownNodeForFrame(f)
    if not f then return nil end
    if f.GetID then
        local ok, id = pcall(f.GetID, f)
        if ok and type(id) == "number" then
            local n = knownByNodeID[id]
            if n then return n end
        end
    end
    return knownNodeFromValueTable(f, 3, {})
end

local function knownNodeFromTooltip(tip)
    if not tip or not tip.name or not tip.cost then return nil end
    local key = normalizeNodeName(tip.name) .. "|" .. tostring(tip.cost)
    local list = knownByNameCost[key]
    if not list or #list == 0 then return nil end
    if #list == 1 then return list[1] end

    -- Cost/name can repeat in a few places. A max-rank match resolves many of
    -- those without guessing. If ambiguity remains, leave it unbound rather
    -- than risk clicking the wrong native node.
    if tip.maxRank then
        local match = nil
        for _, n in ipairs(list) do
            if tonumber(n.maxRank) == tonumber(tip.maxRank) then
                if match then return nil end
                match = n
            end
        end
        if match then return match end
    end
    return nil
end

local function bindNodeFrame(node, f, tip, how)
    if not node or not f then return false end
    if node.button and node.button ~= f then
        -- Prefer the first proven clickable frame for a node. Custom UI nodes
        -- often have clickable child widgets that repeat the same metadata.
        return false
    end
    node.button = f
    matchedDiscoveryFrames[f] = true
    if node.id then nodeButtonCache[tostring(node.id) .. ":?"] = f end
    if tip then
        node.tooltip = tip
        if tip.name and tip.name ~= "" then node.name = tip.name end
        if tip.currentRank ~= nil then node.currentRank = tip.currentRank end
        if tip.maxRank ~= nil then node.maxRank = tip.maxRank end
        if tip.rankText then node.rankText = tip.rankText end
        if tip.cost then node.cost = tip.cost end
        node.carryPrestige = tip.carryPrestige
        node.description = tip.description
        node.effect = summarizeEffect(tip.description)
        node.effectSource = "native"
    else
        -- Binding and ownership are the only things needed to make the list
        -- stable. Spell-tooltip extraction is intentionally deferred until the
        -- node is visible or the background effect scan reaches it; doing 813
        -- hidden tooltip reads here made CleanTree take ages to open.
        liveRankFromFrame(node)
    end
    syncNodeOwnership(node)
    discoveryBound = discoveryBound + 1
    if how == "direct" then discoveryDirectMatches = discoveryDirectMatches + 1 end
    if how == "tooltip" then discoveryTooltipMatches = discoveryTooltipMatches + 1 end
    return true
end

local function likelyNodeCandidate(f)
    if not f or liveNodes[f] then return false end
    if not hasClickHandler(f) then return false end
    local w, h = 0, 0
    if f.GetWidth then
        local ok, v = pcall(f.GetWidth, f)
        if ok and v then w = v end
    end
    if f.GetHeight then
        local ok, v = pcall(f.GetHeight, f)
        if ok and v then h = v end
    end
    if w > 0 and h > 0 and (w > 90 or h > 90) then return false end
    return true
end

local function extractNodeID(f)
    if not f then return nil end
    if f.GetID then
        local ok, id = pcall(f.GetID, f)
        if ok and type(id) == "number" and id > 0 then return id end
    end
    local keys = {"node", "nodeId", "nodeID", "skillId", "skillID", "id", "ID"}
    for _, k in ipairs(keys) do
        local ok, v = pcall(function() return f[k] end)
        if ok and type(v) == "number" and v > 0 then return v end
    end
    return nil
end

ET.BindFromEbonAPI = function()
    local bridge = _G.CleanTreeEbonAPI
    if not bridge or not bridge.tree or not bridge.defsById then return 0, 0, false end

    local bound, total = 0, 0
    for id in pairs(bridge.defsById) do
        local node = knownByNodeID[id] or liveNodes["node:" .. tostring(id)]
        if node then
            total = total + 1
            local frame = bridge.GetNodeFrame and bridge.GetNodeFrame(id) or nil
            if frame then
                bindNodeFrame(node, frame, nil, "ebonapi-direct")
                if node.isEndless and ET.RefreshEndlessLiveData then ET.RefreshEndlessLiveData(node, frame) end
                bound = bound + 1
            end
        end
    end
    return bound, total, true
end

local function discoverRuntimeNodes()
    -- The Ebonhold Skill Tree is lazy-loaded from /progression. The canvas can
    -- exist while the tab still says "Skill Tree loading..." and before any
    -- node widgets have been created. Do not bind against that half-built state.
    clearTreeCaches()
    rebuildKnownIndexes()
    matchedDiscoveryFrames = {}
    discoveryQueue = {}
    discoveryIndex = 1
    discoveryDone = 0
    discoveryBound = 0
    discoveryDirectMatches = 0
    discoveryTooltipMatches = 0
    discoverySpellFallbackMatches = 0
    discoveryNativeTooltipReads = 0
    discoveryPass = discoveryPass + 1

    -- Drop stale native widget references before rebinding. Keep cached spell
    -- descriptions because those are static and cheap to reuse.
    for key, node in pairs(liveNodes) do
        if node.isRuntimeOnly and not node.preserveRuntime then
            liveNodes[key] = nil
        elseif node.preserveRuntime and node.isEndless then
            -- Endless now has stable official IDs, so Refresh can safely discard
            -- stale frame/cost state and rebind it from the current native tree.
            -- Keep the last description as harmless display fallback only.
            node.button = nil
            node.tooltip = nil
            node.cost = nil
            node.rankText = nil
            node.nativeRejected = nil
            node.nativeCanLearn = nil
            node.fullyOwned = false
        else
            node.button = nil
            node.tooltip = nil
            node.cost = nil
            node.rankText = nil
            node.fullyOwned = false
            node.nativeRejected = nil
            node.nativeCanLearn = nil
        end
    end

    -- EbonAPI exposes the live Talent Database and ProjectEbonhold uses stable
    -- skillTreeNode<ID> globals. Bind by ID first and avoid the old full-canvas
    -- frame scan entirely once the lazy tree has populated.
    local apiBound, apiTotal, apiReady = ET.BindFromEbonAPI()
    if apiReady then
        discoveryTotal = apiTotal
        discoveryDone = apiBound
        local minReady = math.min(800, math.max(apiTotal - 10, 1))
        if apiBound >= minReady then
            discoveryActive = false
            nativeReadyWait = false
            if apiBound >= minReady then nativeReadyAttempts = 0 end
            ET.StartResolvePass()
            return true
        end

        discoveryActive = false
        nativeReadyWait = true
        nativeReadyAccumulator = 0
        ET.SetLoadingUI(true, "LOADING CLEANTREE...\nWaiting for EbonAPI Skill Tree " .. tostring(apiBound) .. "/" .. tostring(minReady) .. "+ nodes")
        setStatus("EbonAPI sees the Talent Database; waiting for native Skill Tree buttons (" .. tostring(apiBound) .. "/" .. tostring(minReady) .. "+).", 2)
        return false
    end

    if nativeTreeLooksLoading() then
        discoveryTotal = 0
        discoveryActive = false
        nativeReadyWait = true
        nativeReadyAccumulator = 0
        setStatus("Waiting for Ebonhold's Skill Tree to finish loading...", 2)
        return false
    end

    local frames = allTreeFrames()
    for _, f in ipairs(frames) do
        if likelyNodeCandidate(f) then
            discoveryQueue[#discoveryQueue + 1] = f
        end
    end
    discoveryTotal = #discoveryQueue
    discoveryActive = discoveryTotal > 0
    discoveryAccumulator = 0

    if discoveryActive then
        nativeReadyWait = false
        return true
    end

    nativeReadyWait = true
    nativeReadyAccumulator = 0
    setStatus("Native Skill Tree has no node buttons yet; waiting for Ebonhold...", 2)
    return false
end

local RUNTIME_SPELL_KEYS = {
    "spell", "spellId", "spellID", "nextSpellId", "nextSpellID",
    "currentSpellId", "currentSpellID", "learnSpellId", "learnSpellID",
    -- Unknown runtime nodes may expose their spell as a generic id. This is
    -- safe here because we only accept GetSpellInfo results named Endless*.
    "id", "ID"
}

local COST_KEYS = {
    "cost", "Cost", "price", "Price", "soulAshCost", "soulAshesCost",
    "ashCost", "requiredSoulAsh", "requiredSoulAshes"
}

local function collectRuntimeSpellIDs(t, out, depth, seen)
    if type(t) ~= "table" or depth <= 0 then return end
    seen = seen or {}
    if seen[t] then return end
    seen[t] = true
    for _, k in ipairs(RUNTIME_SPELL_KEYS) do
        local ok, v = pcall(function() return t[k] end)
        if ok and type(v) == "number" and v > 0 then out[v] = true end
    end
    for _, k in ipairs(DISCOVERY_VALUE_KEYS) do
        local ok, v = pcall(function() return t[k] end)
        if ok and type(v) == "table" then
            collectRuntimeSpellIDs(v, out, depth - 1, seen)
        end
    end
end

local function endlessSpellFromFrame(f)
    local ids = {}
    collectRuntimeSpellIDs(f, ids, 4, {})
    if f and f.GetID then
        local ok, id = pcall(f.GetID, f)
        if ok and type(id) == "number" and id > 0 then ids[id] = true end
    end
    for id in pairs(ids) do
        if type(GetSpellInfo) == "function" then
            local ok, name = pcall(GetSpellInfo, id)
            if ok and name and string.find(lower(name), "endless", 1, true) then
                return id, compactSpace(name)
            end
        end
    end
    return nil, nil
end

local function numericValueFromKeys(t, keys, depth, seen)
    if type(t) ~= "table" or depth <= 0 then return nil end
    seen = seen or {}
    if seen[t] then return nil end
    seen[t] = true
    for _, k in ipairs(keys) do
        local ok, v = pcall(function() return t[k] end)
        if ok and type(v) == "number" and v >= 0 then return v end
    end
    for _, k in ipairs(DISCOVERY_VALUE_KEYS) do
        local ok, v = pcall(function() return t[k] end)
        if ok and type(v) == "table" then
            local found = numericValueFromKeys(v, keys, depth - 1, seen)
            if found ~= nil then return found end
        end
    end
    return nil
end

local ENDLESS_STRING_KEYS = {
    "name", "Name", "title", "Title", "spellName", "SpellName",
    "tooltip", "tooltipText", "TooltipText", "text", "Text",
    "label", "Label", "displayName", "DisplayName"
}

local function canonicalEndlessName(value)
    local low = lower(compactSpace(value or ""))
    for key, display in pairs(ENDLESS_NAMES) do
        if low == key or string.find(low, key, 1, true) then return display end
    end
    return nil
end

local function endlessNameFromValueTable(t, depth, seen)
    if type(t) ~= "table" or depth <= 0 then return nil end
    seen = seen or {}
    if seen[t] then return nil end
    seen[t] = true

    for _, k in ipairs(ENDLESS_STRING_KEYS) do
        local ok, v = pcall(function() return t[k] end)
        if ok and type(v) == "string" then
            local name = canonicalEndlessName(v)
            if name then return name end
        end
    end
    for _, k in ipairs(DISCOVERY_VALUE_KEYS) do
        local ok, v = pcall(function() return t[k] end)
        if ok and type(v) == "table" then
            local name = endlessNameFromValueTable(v, depth - 1, seen)
            if name then return name end
        end
    end
    return nil
end

local function endlessNameFromFrame(f)
    if not f then return nil end
    local name = endlessNameFromValueTable(f, 3, {})
    if name then return name end
    local texts = {}
    collectFrameTexts(f, texts, {}, 3)
    for _, t in ipairs(texts) do
        name = canonicalEndlessName(t)
        if name then return name end
    end
    return nil
end

local function createOrBindRuntimeEndless(f, spellID, spellName, tip)
    local name = (tip and tip.name) or spellName or "Endless Node"
    local runtimeKey = "endless:" .. normalizeNodeName(name)
    local node = liveNodes[runtimeKey]
    if not node then
        local cur, max, rankText = frameRank(f)
        local cost = (tip and tip.cost) or (f and numericValueFromKeys(f, COST_KEYS, 4, {}) or nil)
        node = {
            id = extractNodeID(f),
            key = runtimeKey,
            name = name,
            category = "ENDLESS",
            isEndless = true,
            isRuntimeOnly = true,
            preserveRuntime = true,
            runtimeSpellID = spellID,
            button = f,
            tooltip = tip,
            currentRank = (tip and tip.currentRank) or cur,
            maxRank = (tip and tip.maxRank) or max,
            rankText = (tip and tip.rankText) or rankText,
            cost = cost,
            description = tip and tip.description or nil,
            effect = tip and summarizeEffect(tip.description) or nil,
            carryPrestige = tip and tip.carryPrestige or false,
            fullyOwned = false,
        }
        if not node.description then updateNodeFromSpellTooltip(node, false) end
        liveNodes[runtimeKey] = node
        discoveryBound = discoveryBound + 1
        discoverySpellFallbackMatches = discoverySpellFallbackMatches + 1
    else
        node.button = f
        node.runtimeSpellID = node.runtimeSpellID or spellID
        if tip then
            node.tooltip = tip
            node.cost = tip.cost or node.cost
            node.currentRank = tip.currentRank or node.currentRank
            node.maxRank = tip.maxRank or node.maxRank
            node.rankText = tip.rankText or node.rankText
            node.description = tip.description or node.description
            node.effect = summarizeEffect(node.description or "")
        end
    end
    if f then matchedDiscoveryFrames[f] = true end
    return node
end

-- Prefer the canonical named native frame for Endless. Discovery can encounter
-- a metadata/click child first; that child is good enough to click but may not
-- own the OnEnter script or stack-count FontString used by the real node widget.
function ET.ExactEndlessFrame(node)
    local id = node and tonumber(node.id) or nil
    if id then
        local named = _G["skillTreeNode" .. tostring(id)]
        if named then return named end
    end
    return node and node.button or nil
end

-- Infinite nodes render their stack count as a bare integer over the icon rather
-- than the finite-tree "current/max" rank text. Read only the exact node subtree
-- so neighboring stack labels cannot bleed into one another.
function ET.ReadEndlessStack(node, frame)
    frame = frame or ET.ExactEndlessFrame(node)
    if not frame then return nil end
    local texts = {}
    collectFrameTexts(frame, texts, {}, 3)
    local best = nil
    for _, value in ipairs(texts) do
        local s = compactSpace(value or "")
        local n = tonumber(string.match(s, "^(%d+)$"))
        if n and n >= 0 and n < 100000 then
            if not best or n > best then best = n end
        end
    end
    return best
end

-- Project Ebonhold's published data describes the infinite growth curve, while
-- the live server caps these sinks at 100,000,000 Soul Ash per click once stack
-- 50 is reached. The live tooltip remains preferred; this exact cap is a safe
-- fallback when synthetic OnEnter cannot make Ebonhold populate GameTooltip.
function ET.EndlessFallbackCost(node)
    if not node or not node.isEndless then return nil end
    local def = ET.ENDLESS_DEFS[normalizeNodeName(node.name or "")]
    local rank = tonumber(node.currentRank)
    if def and rank and def.capRank and rank >= def.capRank then
        return tonumber(def.capCost)
    end
    return nil
end

-- Read authoritative live Endless state directly from the bound native widget.
-- This is intentionally limited to the three infinite nodes, so unlike the old
-- full-tree tooltip scan it is effectively free and removes the hover-to-bind
-- requirement.
ET.RefreshEndlessLiveData = function(node, frame)
    if not node or not node.isEndless then return false end

    local bridge = _G.CleanTreeEbonAPI
    local exact = bridge and bridge.GetNodeFrame and bridge.GetNodeFrame(node.id) or ET.ExactEndlessFrame(node)
    frame = exact or frame or node.button
    if not frame then return false end

    node.button = frame
    node.id = extractNodeID(frame) or node.id
    node.preserveRuntime = true
    node.fullyOwned = false
    node.fullyCommitted = false

    -- EbonAPI/TalentDatabase path: infinite ranks live in stackBadge.count, and
    -- the next cost is deterministic from soulPointsCosts + infiniteGrowth.
    -- This is authoritative even when synthetic GameTooltip hover is unavailable.
    if bridge and bridge.GetCurrentRank then
        local rank = bridge.GetCurrentRank(node.id)
        if rank ~= nil then
            node.currentRank = rank
            node.rankText = tostring(rank)
        end
        local committed = bridge.GetServerRank and bridge.GetServerRank(node.id) or nil
        if committed ~= nil then node.committedRank = committed end
        local cost = bridge.GetNextCost and bridge.GetNextCost(node.id, tonumber(node.currentRank) or 0) or nil
        if cost then node.cost = cost end
    end

    -- Defensive native fallbacks for an unusual client build.
    if node.currentRank == nil then
        local stack = ET.ReadEndlessStack(node, frame)
        if stack ~= nil then
            node.currentRank = stack
            node.rankText = tostring(stack)
        end
    end
    if not node.cost then
        local metadataCost = numericValueFromKeys(frame, COST_KEYS, 4, {})
        if metadataCost and metadataCost > 0 then node.cost = metadataCost end
    end

    -- Tooltip remains useful for the exact live effect text, but it is no longer
    -- required for rank or price resolution.
    local lines = tooltipFromButton(frame)
    if lines and tooltipLooksLikeSkillNode(lines) then
        local tip = parseTooltip(lines, node.name)
        if tip then
            node.tooltip = tip
            node.nativeCanLearn = tooltipCanLearn(lines)
            if tip.name and tip.name ~= "" then node.name = canonicalEndlessName(tip.name) or tip.name end
            if tip.description and tip.description ~= "" then
                node.description = tip.description
                node.effect = summarizeEffect(tip.description)
                node.effectSource = "native"
            end
            node.carryPrestige = tip.carryPrestige
        end
    end

    if not node.cost then node.cost = ET.EndlessFallbackCost(node) end
    if not node.description or node.description == "" then
        local def = ET.ENDLESS_DEFS[normalizeNodeName(node.name or "")]
        if def and def.description then
            node.description = def.description
            node.effect = summarizeEffect(def.description)
            node.effectSource = "official-json"
        end
    end

    return node.button ~= nil
end

local function clickableFrameNear(frame)
    if not frame then return nil end
    if hasClickHandler(frame) then return frame end

    local candidates, seen = {}, {}
    collectChildren(frame, candidates, seen, 0, 3)
    for _, candidate in ipairs(candidates) do
        if hasClickHandler(candidate) then return candidate end
    end

    local cur = frame
    for _ = 1, 4 do
        if not cur or not cur.GetParent then break end
        local ok, parent = pcall(cur.GetParent, cur)
        if not ok or not parent or parent == cur then break end
        if hasClickHandler(parent) then return parent end
        cur = parent
    end
    return nil
end

local function captureEndlessFromVisibleTooltip()
    if not GameTooltip or not GameTooltip.IsShown or not GameTooltip:IsShown() then return end
    local lines = readGameTooltipLines()
    if not tooltipLooksLikeSkillNode(lines) then return end
    local tip = parseTooltip(lines, "")
    if not tip or not tip.name then return end
    local canLearn = tooltipCanLearn(lines)

    -- A real native mouse hover is the strongest availability signal Ebonhold
    -- exposes. Capture it for finite nodes as well as Endless nodes.
    local known = knownNodeFromTooltip(tip)
    if known then
        known.tooltip = tip
        known.nativeCanLearn = canLearn
        if tip.currentRank ~= nil then known.currentRank = tip.currentRank end
        if tip.maxRank ~= nil then known.maxRank = tip.maxRank end
        if tip.rankText then known.rankText = tip.rankText end
        if tip.cost then known.cost = tip.cost end
        known.description = tip.description
        known.effect = summarizeEffect(tip.description)
        known.effectSource = "native-hover"
        syncNodeOwnership(known)
        if mainFrame and mainFrame:IsShown() then
            refreshRows()
            if selectedNode == known then refreshDetail(known) end
        end
        return
    end

    local canonical = canonicalEndlessName(tip.name)
    if not canonical then return end

    local owner = nil
    if GameTooltip.GetOwner then
        local ok, v = pcall(GameTooltip.GetOwner, GameTooltip)
        if ok then owner = v end
    end
    local button = clickableFrameNear(owner)
    local spellID, spellName = nil, nil
    if button then spellID, spellName = endlessSpellFromFrame(button) end
    local existingKey = "endless:" .. normalizeNodeName(canonical)
    local existing = liveNodes[existingKey]
    local wasBound = existing and existing.button ~= nil
    local hadTooltip = existing and existing.tooltip ~= nil
    local node = createOrBindRuntimeEndless(button, spellID, spellName or canonical, tip)
    if node then
        node.nativeCanLearn = canLearn
        node.name = canonical
        node.preserveRuntime = true
        if tip.cost then node.cost = tip.cost end
        if tip.currentRank ~= nil then node.currentRank = tip.currentRank end
        if tip.maxRank ~= nil then node.maxRank = tip.maxRank end
        if tip.rankText then node.rankText = tip.rankText end
        node.description = tip.description or node.description
        node.effect = summarizeEffect(node.description or "")
        rebuildFiltered()
        if button and not wasBound then
            chat("Bound " .. canonical .. ": rank " .. nodeRankDisplay(node) .. ", cost " .. formatNumber(nodeCost(node) or 0) .. " Soul Ash.")
        elseif not button and not hadTooltip then
            chat("Read " .. canonical .. " tooltip, but could not identify its native button yet.")
        end
        if mainFrame and mainFrame:IsShown() then refreshRows() end
    end
end

local function installTooltipHook()
    if tooltipHookInstalled or not GameTooltip or not GameTooltip.HookScript then return end
    local ok = pcall(GameTooltip.HookScript, GameTooltip, "OnShow", function()
        captureEndlessFromVisibleTooltip()
    end)
    if ok then tooltipHookInstalled = true end
end

local function processDiscoveryFrame(f)
    if not f or matchedDiscoveryFrames[f] then return end

    local direct = directKnownNodeForFrame(f)
    if direct then
        -- The 813 finite catalog nodes already give us name/spell/cost data.
        -- Do not synthesize their tooltips during discovery; it is dramatically
        -- slower on the 3.3.5 client and is not needed for binding. Endless is
        -- different: there are only three, and their live rank/cost is dynamic,
        -- so read those three immediately once their official IDs bind.
        bindNodeFrame(direct, f, nil, "direct")
        if direct.isEndless and ET.RefreshEndlessLiveData then
            ET.RefreshEndlessLiveData(direct, f)
        end
        return
    end

    -- First try Ebonhold's native tooltip. tooltipFromButton searches the tiny
    -- node widget hierarchy because metadata and OnEnter are often on different
    -- child frames.
    local lines = tooltipFromButton(f)
    if lines and tooltipLooksLikeSkillNode(lines) then
        local tip = parseTooltip(lines, "")
        if tip and tip.name and tip.name ~= "" then
            discoveryNativeTooltipReads = discoveryNativeTooltipReads + 1
            local existing = knownNodeFromTooltip(tip)
            if existing then
                bindNodeFrame(existing, f, tip, "tooltip")
                return
            end

            if string.find(lower(tip.name), "endless", 1, true) then
                local spellID, spellName = endlessSpellFromFrame(f)
                createOrBindRuntimeEndless(f, spellID, spellName, tip)
                discoveryTooltipMatches = discoveryTooltipMatches + 1
                return
            end
        end
    end

    -- AshBuild intentionally omitted the three infinite sinks. First look for
    -- their known names in native widget metadata/text; then fall back to spell
    -- metadata. Their custom spell ids are not guaranteed to resolve through
    -- GetSpellInfo on every Ebonhold client build.
    local endlessName = endlessNameFromFrame(f)
    if endlessName then
        local spellID, spellName = endlessSpellFromFrame(f)
        createOrBindRuntimeEndless(f, spellID, spellName or endlessName, nil)
        return
    end

    local spellID, spellName = endlessSpellFromFrame(f)
    if spellID and spellName then
        createOrBindRuntimeEndless(f, spellID, spellName, nil)
        return
    end
end

local function frameMatchScore(f, node)
    if not f or not node then return -1 end
    local wantedSpell = nextSpellFor(node) or firstSpellFor(node)
    if not frameMatches(f, node.id, wantedSpell) then return -1 end
    local score = 10
    if f.GetID then
        local ok, id = pcall(f.GetID, f)
        if ok and tonumber(id) == tonumber(node.id) then score = score + 1000 end
    end
    local directKeys = {"node", "nodeId", "nodeID", "skillId", "skillID", "spell", "spellId", "spellID"}
    for _, k in ipairs(directKeys) do
        local ok, v = pcall(function() return f[k] end)
        if ok and type(v) == "number" and (v == node.id or v == wantedSpell) then score = score + 700 end
    end
    if f.GetObjectType then
        local ok, typ = pcall(f.GetObjectType, f)
        if ok and typ == "Button" then score = score + 250 end
    end
    if safeGetScript(f, "OnClick") then score = score + 100 end
    if type(f.Click) == "function" then score = score + 60 end
    local w, h = 0, 0
    if f.GetWidth then local ok,v=pcall(f.GetWidth,f); if ok and v then w=v end end
    if f.GetHeight then local ok,v=pcall(f.GetHeight,f); if ok and v then h=v end end
    if w > 10 and w <= 80 and h > 10 and h <= 80 then score = score + 40 end
    return score
end

local function findBestNativeFrame(node)
    if not node then return nil end
    if node.isEndless then
        local exact = ET.ExactEndlessFrame(node)
        if exact then
            node.button = exact
            matchedDiscoveryFrames[exact] = true
            if ET.RefreshEndlessLiveData then ET.RefreshEndlessLiveData(node, exact) end
            return exact
        end
    end
    if node.button then return node.button end
    local best, bestScore = nil, -1
    local frames = allTreeFrames()
    for _, f in ipairs(frames) do
        if hasClickHandler(f) then
            local score = frameMatchScore(f, node)
            if score > bestScore then
                best, bestScore = f, score
            end
        end
    end
    if best then
        node.button = best
        matchedDiscoveryFrames[best] = true
        if node.isEndless and ET.RefreshEndlessLiveData then
            ET.RefreshEndlessLiveData(node, best)
        else
            liveRankFromFrame(node)
            syncNodeOwnership(node)
        end
    end
    return best
end

local function ensureNodeBound(node)
    if not node or node.button then return node and node.button or nil end
    return findBestNativeFrame(node)
end

local function startBackgroundScan()
    scanQueue = {}
    scanIndex = 1
    scanDone = 0
    for _, node in pairs(liveNodes) do
        if node.button then scanQueue[#scanQueue + 1] = node end
    end
    table.sort(scanQueue, function(a, b)
        if a.category ~= b.category then return tostring(a.category) < tostring(b.category) end
        return tostring(a.name) < tostring(b.name)
    end)
    scanTotal = #scanQueue
    scanActive = scanTotal > 0
end

local function textMatchesSearch(node)
    if searchTerm == "" then return true end
    local q = lower(searchTerm)
    local hay = lower((node.name or "") .. " " .. (node.description or "") .. " " .. ((node.effect and node.effect.text) or ""))
    return string.find(hay, q, 1, true) ~= nil
end

function ET.TreeStaticMinCost(node)
    if not node or not node.static or not node.static.ranks then return nil end
    local best = nil
    for _, rankDef in ipairs(node.static.ranks) do
        local c = tonumber(rankDef.cost)
        if c and (not best or c < best) then best = c end
    end
    return best
end

function ET.TreeFrameCenter(frame)
    if not frame or not frame.GetCenter then return nil, nil end
    local ok, x, y = pcall(frame.GetCenter, frame)
    if ok and type(x) == "number" and type(y) == "number" then return x, y end
    return nil, nil
end

function ET.ChooseTreeRoot(category)
    local wanted = ET.TREE_ROOT_NAMES[category]
    if not wanted then return nil end
    local wantedLow = lower(wanted)
    local best, bestCost = nil, nil
    for _, node in pairs(liveNodes) do
        if node and node.category == category and lower(node.name or "") == wantedLow then
            local c = ET.TreeStaticMinCost(node) or 2147483647
            if not best or c < bestCost then
                best = node
                bestCost = c
            end
        end
    end
    return best
end

function ET.CachedTreeLess(a, b)
    local ag = tonumber(a._treeSortGroup) or 99
    local bg = tonumber(b._treeSortGroup) or 99
    if ag ~= bg then return ag < bg end

    local ae = (a.isEndless == true)
    local be = (b.isEndless == true)
    if ae ~= be then return (not ae) and be end

    local ah = (a._treeSortHasPos == true)
    local bh = (b._treeSortHasPos == true)
    if ah ~= bh then return ah and not bh end

    if ah and bh then
        local ad = tonumber(a._treeSortDistance) or 2147483647
        local bd = tonumber(b._treeSortDistance) or 2147483647
        if ad ~= bd then return ad < bd end
        local ay = tonumber(a._treeSortY) or 0
        local by = tonumber(b._treeSortY) or 0
        if ay ~= by then return ay > by end
        local ax = tonumber(a._treeSortX) or 0
        local bx = tonumber(b._treeSortX) or 0
        if ax ~= bx then return ax < bx end
    end

    local af = tonumber(a._treeSortFallback) or 2147483647
    local bf = tonumber(b._treeSortFallback) or 2147483647
    if af ~= bf then return af < bf end
    local an, bn = lower(a.name or ""), lower(b.name or "")
    if an ~= bn then return an < bn end
    return tostring(a.key or "") < tostring(b.key or "")
end

function ET.BuildTreeOrderCache()
    ET.treeOrderReady = false
    ET.treeOrderRoots = {}

    local graph = EbonTreeOrderData
    local orderById = graph and graph.orderById or nil
    local depthById = graph and graph.depthById or nil
    local roots = graph and graph.roots or nil

    -- Resolve the three authoritative roots by static node ID. This avoids the
    -- duplicate-name ambiguity that made the earlier geometry approach pick a
    -- particular rank based on cost/name heuristics.
    for _, category in ipairs({"DAMAGE", "SURVIVAL", "CONVENIENCE"}) do
        local rootID = roots and tonumber(roots[category]) or nil
        local rootNode = rootID and liveNodes["node:" .. tostring(rootID)] or nil
        ET.treeOrderRoots[category] = { node = rootNode, id = rootID }
    end

    local fallback = 1000000
    for _, node in pairs(liveNodes) do
        local id = tonumber(node.id)
        local exact = id and orderById and tonumber(orderById[id]) or nil
        if exact then
            node._treeOrderIndex = exact
            node._treeDepth = depthById and tonumber(depthById[id]) or nil
            if graph and graph.categoryById and graph.categoryById[id] then
                node.category = graph.categoryById[id]
            end
            node._treeOrderExact = true
        else
            -- Endless nodes are intentionally absent from the finite directed
            -- graph. Any future/runtime-only node sorts after the exact finite
            -- tree without disturbing its prerequisite order.
            node._treeOrderIndex = fallback + (id or 0)
            node._treeDepth = nil
            node._treeOrderExact = false
            fallback = fallback + 1
        end
    end

    ET.treeOrderReady = true
    if ET.BuildDamageBranchMap then ET.BuildDamageBranchMap() end
    if ET.RefreshGeneratedShoppingProfiles then ET.RefreshGeneratedShoppingProfiles(true) end
end

ET.damageViewMode = ET.damageViewMode or "RECOMMENDED"
ET.DAMAGE_ANCHORS = { ROOT = 90, PHYSICAL = 1, GENERAL = 2, SPELL = 5 }

function ET.RefreshPlayerDamagePreference()
    local className, classToken = nil, nil
    if type(UnitClass) == "function" then
        local ok, a, b = pcall(UnitClass, "player")
        if ok then className, classToken = a, b end
    end
    classToken = classToken or "UNKNOWN"

    local activeGroup = 1
    if type(GetActiveTalentGroup) == "function" then
        local ok, value = pcall(GetActiveTalentGroup, false)
        if ok and tonumber(value) then activeGroup = tonumber(value) end
    end

    local bestIndex, bestName, bestPoints, tied = nil, nil, -1, false
    if type(GetTalentTabInfo) == "function" then
        for tabIndex = 1, 3 do
            local ok, name, icon, points = pcall(GetTalentTabInfo, tabIndex, false, false, activeGroup)
            if not ok then ok, name, icon, points = pcall(GetTalentTabInfo, tabIndex) end
            points = ok and tonumber(points) or nil
            if points then
                if points > bestPoints then
                    bestIndex, bestName, bestPoints, tied = tabIndex, name, points, false
                elseif points == bestPoints then
                    tied = true
                end
            end
        end
    end

    local preference = "ALL"
    if classToken == "MAGE" or classToken == "PRIEST" or classToken == "WARLOCK" then
        preference = "SPELL"
    elseif classToken == "WARRIOR" or classToken == "ROGUE" or classToken == "HUNTER" or classToken == "DEATHKNIGHT" then
        preference = "PHYSICAL"
    elseif (classToken == "DRUID" or classToken == "SHAMAN" or classToken == "PALADIN") and bestIndex and bestPoints > 0 and not tied then
        if classToken == "DRUID" then
            preference = (bestIndex == 2) and "PHYSICAL" or "SPELL"
        elseif classToken == "SHAMAN" then
            preference = (bestIndex == 2) and "PHYSICAL" or "SPELL"
        elseif classToken == "PALADIN" then
            preference = (bestIndex == 1) and "SPELL" or "PHYSICAL"
        end
    end

    ET.damageClassName = className or classToken
    ET.damageClassToken = classToken
    ET.damageTalentGroup = activeGroup
    ET.damageSpecIndex = (not tied) and bestIndex or nil
    ET.damageSpecName = tied and "Ambiguous" or (bestName or "Unknown")
    ET.damageSpecPoints = bestPoints >= 0 and bestPoints or nil
    ET.damagePreference = preference
    return preference
end

function ET.GetPlayerDamagePreference()
    if not ET.damagePreference then ET.RefreshPlayerDamagePreference() end
    return ET.damagePreference or "ALL"
end

function ET.BuildDamageBranchMap()
    local bridge = _G.CleanTreeEbonAPI
    local tree = bridge and bridge.tree or nil
    local map = {
        valid = false,
        reason = "Talent Database unavailable",
        branchById = {},
        counts = { ROOT = 0, GENERAL = 0, PHYSICAL = 0, SPELL = 0, MIXED = 0, UNKNOWN = 0 },
        requiredByMode = {},
        parentsById = {},
        signature = "unavailable",
    }
    ET.damageBranchMap = map

    if type(tree) ~= "table" or type(tree.nodes) ~= "table" or type(tree.links) ~= "table" then return false end

    local root = tonumber((_G.EbonTreeOrderData and EbonTreeOrderData.roots and EbonTreeOrderData.roots.DAMAGE) or ET.DAMAGE_ANCHORS.ROOT)
    local anchors = ET.DAMAGE_ANCHORS
    local children, defs = {}, {}
    for _, def in ipairs(tree.nodes) do
        local id = tonumber(def and def.id)
        if id then defs[id] = true end
    end
    for _, link in ipairs(tree.links) do
        local parentId = tonumber(link and link[1])
        local childId = tonumber(link and link[2])
        if parentId and childId then
            children[parentId] = children[parentId] or {}
            children[parentId][#children[parentId] + 1] = childId
            map.parentsById[childId] = map.parentsById[childId] or {}
            map.parentsById[childId][#map.parentsById[childId] + 1] = parentId
        end
    end

    if not defs[root] or not defs[anchors.PHYSICAL] or not defs[anchors.GENERAL] or not defs[anchors.SPELL] then
        map.reason = "Current Damage root/anchors are missing from the live Talent Database"
        return false
    end

    local direct = {}
    for _, childId in ipairs(children[root] or {}) do direct[childId] = true end
    if not direct[anchors.PHYSICAL] or not direct[anchors.GENERAL] or not direct[anchors.SPELL] then
        map.reason = "Current Damage anchors are no longer direct children of Rising Carnage"
        return false
    end

    local membership = {}
    local function walk(anchorId, label)
        local queue, seen, index = {anchorId}, {}, 1
        while queue[index] do
            local id = queue[index]
            index = index + 1
            if not seen[id] then
                seen[id] = true
                membership[id] = membership[id] or {}
                membership[id][label] = true
                for _, childId in ipairs(children[id] or {}) do queue[#queue + 1] = childId end
            end
        end
    end
    walk(anchors.PHYSICAL, "PHYSICAL")
    walk(anchors.GENERAL, "GENERAL")
    walk(anchors.SPELL, "SPELL")

    for id, static in pairs(DATA.nodes or {}) do
        id = tonumber(id)
        if static and static.category == "DAMAGE" then
            local branch
            if id == root then
                branch = "ROOT"
            else
                local m = membership[id] or {}
                local count, only = 0, nil
                for _, label in ipairs({"GENERAL", "PHYSICAL", "SPELL"}) do
                    if m[label] then count, only = count + 1, label end
                end
                if count == 1 then branch = only
                elseif count > 1 then branch = "MIXED"
                else branch = "UNKNOWN" end
            end
            map.branchById[id] = branch
            map.counts[branch] = (map.counts[branch] or 0) + 1
        end
    end

    local function buildRequired(targetBranch, includeGeneral)
        local needed, queue, index = {}, {}, 1
        for id, branch in pairs(map.branchById) do
            if branch == targetBranch or branch == "MIXED" or branch == "ROOT" or (includeGeneral and branch == "GENERAL") then
                needed[id] = true
                queue[#queue + 1] = id
            end
        end
        while queue[index] do
            local id = queue[index]
            index = index + 1
            for _, parentId in ipairs(map.parentsById[id] or {}) do
                if map.branchById[parentId] and not needed[parentId] then
                    needed[parentId] = true
                    queue[#queue + 1] = parentId
                end
            end
        end
        return needed
    end

    map.requiredByMode.PHYSICAL = buildRequired("PHYSICAL", false)
    map.requiredByMode.SPELL = buildRequired("SPELL", false)
    map.requiredByMode.RECOMMENDED_PHYSICAL = buildRequired("PHYSICAL", true)
    map.requiredByMode.RECOMMENDED_SPELL = buildRequired("SPELL", true)
    map.signature = tostring(root) .. ":" .. tostring(bridge and bridge.NodeCount and bridge.NodeCount() or #tree.nodes) .. ":" .. tostring(bridge and bridge.linkCount or #tree.links)

    if (map.counts.UNKNOWN or 0) > 0 then
        map.reason = tostring(map.counts.UNKNOWN) .. " Damage node(s) were not reachable from the validated anchors"
        return false
    end

    map.valid = true
    map.reason = "ok"
    return true
end

function ET.GetDamageBranch(nodeOrId)
    local id = type(nodeOrId) == "table" and tonumber(nodeOrId.id) or tonumber(nodeOrId)
    if not ET.damageBranchMap then ET.BuildDamageBranchMap() end
    return id and ET.damageBranchMap and ET.damageBranchMap.branchById[id] or nil
end

function ET.IsDamageNodeRelevant(nodeOrId, mode)
    local id = type(nodeOrId) == "table" and tonumber(nodeOrId.id) or tonumber(nodeOrId)
    if not id then return false end
    if not ET.damageBranchMap then ET.BuildDamageBranchMap() end
    local map = ET.damageBranchMap
    if not map or not map.valid then return true end

    mode = mode or ET.damageViewMode or "RECOMMENDED"
    if mode == "ALL" then return true end
    if mode == "RECOMMENDED" then
        local preference = ET.GetPlayerDamagePreference()
        if preference == "ALL" then return true end
        mode = "RECOMMENDED_" .. preference
    end
    local required = map.requiredByMode and map.requiredByMode[mode]
    return required and required[id] == true or false
end

function ET.GetDamageContextKey()
    if not ET.damagePreference then ET.RefreshPlayerDamagePreference() end
    if not ET.damageBranchMap then ET.BuildDamageBranchMap() end
    local map = ET.damageBranchMap or {}
    return table.concat({
        "damage-v1",
        tostring(ET.damageClassToken or "UNKNOWN"),
        tostring(ET.damageTalentGroup or 1),
        tostring(ET.damageSpecIndex or "ambiguous"),
        tostring(ET.damagePreference or "ALL"),
        tostring(map.signature or "unavailable"),
        tostring(map.valid == true),
    }, "|")
end

function ET.HandleDamageContextChanged(treeChanged)
    local before = ET._damageContextKey
    ET.damagePreference = nil
    ET.RefreshPlayerDamagePreference()
    if treeChanged or not ET.damageBranchMap then ET.BuildDamageBranchMap() end
    local after = ET.GetDamageContextKey()
    ET._damageContextKey = after
    if before ~= after or treeChanged then
        if ET.RefreshGeneratedShoppingProfiles then ET.RefreshGeneratedShoppingProfiles(treeChanged == true) end
        if ET.shoppingFrame and ET.shoppingFrame.IsShown and ET.shoppingFrame:IsShown() and ET.RefreshShoppingUI then ET.RefreshShoppingUI() end
        if ET.UpdateDamageSelector then ET.UpdateDamageSelector() end
        if selectedCategory == "DAMAGE" and mainFrame and mainFrame:IsShown() then
            rebuildFiltered()
            if listScroll and type(FauxScrollFrame_SetOffset) == "function" then FauxScrollFrame_SetOffset(listScroll, 0) end
            refreshRows()
        end
    end
end

rebuildFiltered = function()
    filteredNodes = {}

    -- Cart is the set of ranks staged through CleanTree but not yet applied.
    -- Show newest staged ranks first so removing prerequisites naturally starts
    -- from the end of the purchase chain.
    if selectedCategory == "CART" then
        for i = #pendingSelections, 1, -1 do
            local p = pendingSelections[i]
            local source = liveNodes[p.key]
            filteredNodes[#filteredNodes + 1] = {
                key = p.key,
                name = p.name,
                description = p.description,
                effect = p.effect,
                category = source and source.category or "OTHER",
                cost = p.cost,
                currentRank = p.rank,
                isCartEntry = true,
                cartIndex = i,
                sourceNode = source,
            }
        end
        return
    end

    local buyableAsh = selectedCategory == "BUYABLE" and readSoulAsh() or nil

    for _, node in pairs(liveNodes) do
        -- Keep category membership authoritative. A node can become purchased
        -- after staging/apply without a full rediscovery pass; filtering on a
        -- stale fullyOwned flag caused purchased nodes to leak into Unowned.
        if not node.isEndless then syncNodeOwnership(node) end
        local include = false
        if selectedCategory == "PURCHASED" then
            -- With EbonAPI, Purchased means committed on the server. A node that
            -- is only maxed in the staged native tree belongs in Cart, not here.
            local bridge = _G.CleanTreeEbonAPI
            local committedKnown = bridge and bridge.HasServerLoadout and bridge.HasServerLoadout()
            include = (not node.isEndless) and ((committedKnown and node.fullyCommitted == true) or ((not committedKnown) and node.fullyOwned == true))
        elseif selectedCategory == "BUYABLE" then
            -- One-click live shopping view: only show nodes whose prerequisites
            -- are currently satisfied AND whose next rank the player can afford
            -- with the Soul Ash available right now. This intentionally includes
            -- Endless nodes when they are genuinely buyable.
            local cost = nodeCost(node)
            include = (node.fullyOwned ~= true or node.isEndless == true)
                      and node.button ~= nil
                      and nodeStructuralAvailability(node) == true
                      and cost ~= nil
                      and buyableAsh ~= nil
                      and buyableAsh >= cost
        elseif selectedCategory == "UNOWNED" then
            -- Default browsing view: finite nodes the player has not completed.
            -- Endless has its own dedicated tab.
            include = (not node.isEndless) and node.fullyOwned ~= true
        elseif selectedCategory == "ALL" then
            -- All really means all: purchased, unowned, and Endless.
            include = true
        else
            -- Branch tabs stay focused on unfinished/actionable nodes. Damage
            -- additionally applies the session-scoped class/spec relevance view.
            include = (node.category == selectedCategory) and (node.isEndless or node.fullyOwned ~= true)
            if include and selectedCategory == "DAMAGE" then
                include = ET.IsDamageNodeRelevant(node, ET.damageViewMode or "RECOMMENDED")
            end
        end
        if include and textMatchesSearch(node) then
            filteredNodes[#filteredNodes + 1] = node
        end
    end

    -- Use the cached native-tree order once initial binding has completed.
    -- Crucially, this comparator performs no frame queries and no ownership
    -- work, so scrolling/searching cannot regress the fast Hotfix23+ load path.
    table.sort(filteredNodes, function(a, b)
        local ai = ET.treeOrderReady and tonumber(a._treeOrderIndex) or nil
        local bi = ET.treeOrderReady and tonumber(b._treeOrderIndex) or nil
        if ai and bi and ai ~= bi then return ai < bi end
        if ai ~= nil and bi == nil then return true end
        if ai == nil and bi ~= nil then return false end

        -- Safe fallback used while the native tree is still binding.
        local ae = (a.isEndless == true)
        local be = (b.isEndless == true)
        if ae ~= be then return (not ae) and be end
        local an, bn = lower(a.name or ""), lower(b.name or "")
        if an ~= bn then return an < bn end
        local ac = tonumber(nodeCost(a)) or 2147483647
        local bc = tonumber(nodeCost(b)) or 2147483647
        if ac ~= bc then return ac < bc end
        return tostring(a.key or "") < tostring(b.key or "")
    end)
end

function ET.AggregateCartEffects(selections)
    local aggregates, specials = {}, {}
    for _, p in ipairs(selections or pendingSelections) do
        local effect = p.effect
        if effect and effect.aggregate and effect.key and effect.amount then
            local numericAmount = tonumber(effect.amount)
            if numericAmount and numericAmount ~= 0 then
                local k = tostring(effect.key) .. "|" .. tostring(effect.unit or "")
                local a = aggregates[k]
                if not a then
                    a = {
                        key = effect.key,
                        display = effect.display or effect.sourceKey or effect.key,
                        unit = effect.unit or "",
                        amount = 0,
                        count = 0,
                        order = tonumber(effect.order) or 900,
                    }
                    aggregates[k] = a
                end
                a.amount = a.amount + numericAmount
                a.count = a.count + 1
            elseif not numericAmount then
                specials[#specials + 1] = {
                    id = p.nodeID,
                    rank = p.rank,
                    text = effect.text or (p.description or "Unknown effect"),
                }
            end
        else
            specials[#specials + 1] = {
                id = p.nodeID,
                rank = p.rank,
                text = effect and effect.text or (p.description or "Unknown effect"),
            }
        end
    end

    local aggList = {}
    for _, a in pairs(aggregates) do aggList[#aggList + 1] = a end
    table.sort(aggList, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        if a.display ~= b.display then return tostring(a.display) < tostring(b.display) end
        return tostring(a.unit) < tostring(b.unit)
    end)
    return aggList, specials
end

function ET.FormatAggregatedEffect(effect)
    local amount = tonumber(effect and effect.amount) or 0
    local amountText
    if math.floor(amount) == amount then amountText = formatNumber(amount) else amountText = tostring(amount) end
    local display = tostring(effect and effect.display or effect and effect.key or "Effect")
    return display .. "  |cff33ff33+" .. amountText .. tostring(effect and effect.unit or "") .. "|r"
end

local function pendingSummaryLines()
    local aggregates, specials = ET.AggregateCartEffects()
    local lines = {}
    for _, effect in ipairs(aggregates) do lines[#lines + 1] = ET.FormatAggregatedEffect(effect) end

    local showOtherHeading = selectedCategory == "CART" and (#specials > 0 or untrackedSpend > 0)
    if showOtherHeading then
        if #lines > 0 then lines[#lines + 1] = "" end
        lines[#lines + 1] = "|cffffd200Other Effects|r"
    end
    for _, special in ipairs(specials) do
        lines[#lines + 1] = "|cffffd200•|r " .. tostring(special.text or "Unknown effect")
    end
    if selectedCategory == "CART" and untrackedSpend > 0 then
        lines[#lines + 1] = "|cffff9933• Untracked native staged changes are excluded from benefit totals.|r"
    end
    return lines
end

local function pendingSpend()
    local n = 0
    for _, p in ipairs(pendingSelections) do n = n + (tonumber(p.cost) or 0) end
    return n
end

local function currentStatusText()
    local now = (type(GetTime) == "function" and GetTime()) or 0
    if statusMessage and now < statusExpire then return statusMessage end
    if discoveryActive then
        return "Binding native tree: " .. tostring(discoveryDone) .. "/" .. tostring(discoveryTotal) .. " frames"
    end
    if scanActive then return "Reading live node effects: " .. tostring(scanDone) .. "/" .. tostring(scanTotal) end
    return tostring(#filteredNodes) .. " nodes shown"
end

ET.IsInitialLoading = function()
    return ET._initialLoadActive == true
end

ET.SetLoadingUI = function(active, message)
    ET._initialLoadActive = active == true
    if ET.loadingText and message then ET.loadingText:SetText(message) end

    -- Never expose the partially-resolved list.  During the initial bind/resolve
    -- pass the row pool may still contain stale/provisional widgets from the
    -- previous render, which makes the list look broken and can extend below
    -- the panel.  Hide every row until the authoritative pass is complete.
    if active then
        for _, row in ipairs(rows or {}) do
            row.node = nil
            row:Hide()
        end
        if listScroll and listScroll.EnableMouse then pcall(listScroll.EnableMouse, listScroll, false) end
    else
        if listScroll and listScroll.EnableMouse then pcall(listScroll.EnableMouse, listScroll, true) end
    end

    if ET.loadingOverlay then
        if active then ET.loadingOverlay:Show() else ET.loadingOverlay:Hide() end
    end
end

ET.StartResolvePass = function()
    ET._resolveQueue = {}
    ET._resolveIndex = 1
    ET._resolveDone = 0
    ET._resolveAccumulator = 0
    for _, node in pairs(liveNodes) do
        if node and not node.isEndless then ET._resolveQueue[#ET._resolveQueue + 1] = node end
    end
    table.sort(ET._resolveQueue, function(a, b)
        return tostring(a.key or "") < tostring(b.key or "")
    end)
    ET._resolveTotal = #ET._resolveQueue
    ET._resolveActive = ET._resolveTotal > 0
    if ET._resolveActive then
        ET.SetLoadingUI(true, "LOADING CLEANTREE...\nResolving node state 0/" .. tostring(ET._resolveTotal))
    else
        ET.FinishInitialLoad()
    end
end

ET.FinishInitialLoad = function()
    ET._resolveActive = false
    -- Install the precomputed prerequisite order once after native binding.
    -- This is only table lookup work; no frame-coordinate or graph traversal is
    -- performed in the 3.3.5 client.
    ET.BuildTreeOrderCache()
    rebuildFiltered()
    if listScroll then
        if type(FauxScrollFrame_SetOffset) == "function" then FauxScrollFrame_SetOffset(listScroll, 0) else listScroll.offset = 0 end
    end
    ET.SetLoadingUI(false)
    refreshHeader()
    refreshPendingPanel()
    refreshRows()
    if #filteredNodes > 0 then refreshDetail(filteredNodes[1]) end
end

local function refreshPendingPanel()
    if not pendingText or not pendingSpendText then return end
    local lines = pendingSummaryLines()
    if #lines == 0 then
        -- Keep the empty-state message intentionally short. The numeric spend
        -- summary has its own footer band below this text.
        pendingText:SetText("|cffaaaaaaNo changes staged through CleanTree.|r")
    else
        pendingText:SetText(table.concat(lines, "\n"))
    end

    local spend = pendingSpend()
    local current = readSoulAsh()
    local footer = "Ranks staged: |cffffffff" .. tostring(#pendingSelections) .. "|r\n"
        .. "Tracked spend: |cffffd200" .. formatNumber(spend) .. "|r Soul Ash"
    if untrackedSpend > 0 then
        footer = footer .. "\nUntracked native spend: |cffff9933" .. formatNumber(untrackedSpend) .. "|r"
    end
    if current then
        footer = footer .. "\nRemaining: |cff33ff33" .. formatNumber(current) .. "|r"
    end
    pendingSpendText:SetText(footer)
end

local function refreshHeader()
    if soulAshText then
        local ash = readSoulAsh()
        if ash then
            soulAshText:SetText("Soul Ash: |cff33ff33" .. formatNumber(ash) .. "|r")
        else
            soulAshText:SetText("Soul Ash: |cffff5555unavailable|r")
        end
    end
    if scanText then scanText:SetText(currentStatusText()) end
end

local function refreshDetail(node)
    selectedNode = node or selectedNode
    if not selectedNode or not detailTitle or not detailBody then return end
    ensureNodeBound(selectedNode)
    if selectedNode.isEndless and selectedNode.button and ET.RefreshEndlessLiveData then
        ET.RefreshEndlessLiveData(selectedNode, selectedNode.button)
    end
    syncNodeOwnership(selectedNode)
    updateNodeFromTooltip(selectedNode, false)
    local n = selectedNode
    detailTitle:SetText(n.name or "Node")

    if n.isCartEntry then
        local effect = (n.effect and n.effect.text) or n.description or "Staged Skill Tree change"
        detailBody:SetText(table.concat({
            "|cffffd200Effect|r\n" .. effect,
            "",
            "|cffffd200Staged rank|r  " .. tostring(n.currentRank or "?"),
            "|cffffd200Cost|r  " .. formatNumber(n.cost or 0) .. " Soul Ash",
            "|cffffd200State|r  |cffffd200In cart|r",
            "",
            "Click the |cffff5555-|r button to right-click the native node and restore its staged Soul Ash."
        }, "\n"))
        return
    end

    local effect = (n.effect and n.effect.text) or n.description or "Effect not yet read from the live tooltip."
    local cost = nodeCost(n)
    local structurallyAvailable = nodeStructuralAvailability(n)
    local affordable = nodeAffordability(n)
    local category = CATEGORY_LABELS[n.category] or n.category or "Other"
    local stateText
    if n.fullyOwned and not n.isEndless then
        local bridge = _G.CleanTreeEbonAPI
        if bridge and bridge.HasServerLoadout and bridge.HasServerLoadout() and not n.fullyCommitted then
            stateText = "|cffffd200Staged — not applied|r"
        else
            stateText = "|cffaaaaaaPurchased|r"
        end
    elseif not n.button then
        stateText = n.isEndless and "|cffff9933Binding native Endless node|r" or "|cffaaaaaaBinding|r"
    elseif not structurallyAvailable then
        stateText = "|cffff5555NOT AVAILABLE|r"
    elseif n.isEndless and not cost then
        stateText = "|cffff9933Available, but live cost is still resolving|r"
    elseif affordable == false then
        stateText = "|cffff5555Available — insufficient Soul Ash|r"
    else
        stateText = "|cff33ff33Available|r"
    end
    local costText
    if n.fullyOwned and not n.isEndless then
        costText = "|cffaaaaaaMAXED|r"
    else
        costText = cost and (formatNumber(cost) .. " Soul Ash") or "unknown"
        if (not structurallyAvailable) or affordable == false then
            costText = "|cffff5555" .. costText .. "|r"
        end
    end
    local lines = {
        "|cffffd200Effect|r\n" .. effect,
        "",
        "|cffffd200Rank|r  " .. nodeRankDisplay(n),
        "|cffffd200Next cost|r  " .. costText,
        "|cffffd200Branch|r  " .. category,
        "|cffffd200State|r  " .. stateText,
    }
    if n.carryPrestige then lines[#lines + 1] = "|cff66ccffCarries over Prestige|r" end
    if n.isEndless then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cffff9933Endless node|r — each |cffffd200+|r stages one additional rank. You can click repeatedly while you have enough Soul Ash."
        lines[#lines + 1] = "Next cost comes from EbonAPI's live Talent Database and is recalculated after every staged click."
    end
    detailBody:SetText(table.concat(lines, "\n"))
end

local function resetScrollTop()
    if not listScroll then return end
    if type(FauxScrollFrame_SetOffset) == "function" then
        FauxScrollFrame_SetOffset(listScroll, 0)
    else
        listScroll.offset = 0
        local sb = _G[listScroll:GetName() .. "ScrollBar"]
        if sb and sb.SetValue then sb:SetValue(0) end
    end
end

refreshRows = function()
    if not listScroll then return end
    if ET.IsInitialLoading and ET.IsInitialLoading() then
        refreshHeader()
        return
    end
    rebuildFiltered()
    local rowHeight = 54
    local visible = #rows
    if listScroll.GetHeight then
        local ok, h = pcall(listScroll.GetHeight, listScroll)
        if ok and type(h) == "number" and h > 0 then
            visible = math.max(1, math.min(#rows, math.floor((h - 6) / rowHeight)))
        end
    end
    -- FauxScrollFrame keeps its previous offset when the filtered list shrinks.
    -- During initial ownership resolution Unowned can collapse from ~800
    -- provisional entries to ~150 real entries; a stale offset then points past
    -- the end of the new list and makes the panel look completely empty until a
    -- category click resets it. Clamp the offset every render so the first load
    -- is always self-consistent.
    local currentOffset = FauxScrollFrame_GetOffset(listScroll) or 0
    local maxOffset = math.max(0, #filteredNodes - visible)
    if currentOffset < 0 or currentOffset > maxOffset then
        local clamped = math.max(0, math.min(maxOffset, currentOffset))
        if type(FauxScrollFrame_SetOffset) == "function" then
            FauxScrollFrame_SetOffset(listScroll, clamped)
        else
            listScroll.offset = clamped
        end
    end

    FauxScrollFrame_Update(listScroll, #filteredNodes, visible, rowHeight)
    local nativeScrollBar = _G[listScroll:GetName() .. "ScrollBar"]
    if nativeScrollBar then
        nativeScrollBar:SetAlpha(0)
        nativeScrollBar:EnableMouse(false)
    end
    local offset = FauxScrollFrame_GetOffset(listScroll)

    for i = visible + 1, #rows do
        rows[i].node = nil
        rows[i]:Hide()
    end

    for i = 1, visible do
        local row = rows[i]
        local index = offset + i
        local node = filteredNodes[index]
        if node then
            row.node = node
            row:Show()

            if node.isCartEntry then
                row.name:SetText(node.name or "Staged node")
                row.effect:SetText((node.effect and node.effect.text) or node.description or "Staged Skill Tree change")
                row.rank:SetText("Rank " .. tostring(node.currentRank or "?"))
                row.cost:SetText(formatNumber(node.cost or 0) .. " Ash")
                row.cost:SetTextColor(1.00, 0.82, 0.00)
                row.state:SetText("|cffffd200IN CART|r")
                row.plus:Enable()
                row.plus:SetText("-")
            else
                ensureNodeBound(node)
                if node.isEndless and node.button and ET.RefreshEndlessLiveData then
                    ET.RefreshEndlessLiveData(node, node.button)
                end
                syncNodeOwnership(node)
                updateNodeFromTooltip(node, false)

                -- Filtering can happen before a lazily-bound native rank is
                -- available.  If resolving this visible row proves that its
                -- ownership does not belong in the active tab, hide it now and
                -- rebuild on the next update tick.  This keeps PURCHASED/MAXED
                -- rows out of Unowned/branch tabs instead of displaying stale
                -- provisional entries until the user manually refreshes.
                local ownershipMismatch = false
                if selectedCategory == "UNOWNED" and node.fullyOwned and not node.isEndless then
                    ownershipMismatch = true
                elseif selectedCategory == "PURCHASED" and (not node.isEndless) and not node.fullyOwned then
                    ownershipMismatch = true
                elseif (selectedCategory == "DAMAGE" or selectedCategory == "SURVIVAL" or selectedCategory == "CONVENIENCE")
                       and node.fullyOwned and not node.isEndless then
                    ownershipMismatch = true
                end
                if ownershipMismatch then
                    row.node = nil
                    row:Hide()
                    ET._ownershipRefilterPending = true
                else

                row.name:SetText(node.name or ("Node " .. tostring(node.id or "?")))
            local effect = (node.effect and node.effect.text) or node.description or "Reading live effect..."
            row.effect:SetText(effect)
            row.rank:SetText(nodeRankDisplay(node))
            local cost = nodeCost(node)
            local ash = readSoulAsh()
            local affordable = nil
            if cost and ash then affordable = ash >= cost end

            local structurallyAvailable = nodeStructuralAvailability(node)
            if node.fullyOwned and not node.isEndless then
                row.cost:SetText("MAXED")
                row.cost:SetTextColor(0.58, 0.58, 0.62)
            else
                row.cost:SetText(cost and (formatNumber(cost) .. " Ash") or "? Ash")
                if (not structurallyAvailable) or affordable == false then
                    row.cost:SetTextColor(1.00, 0.25, 0.20)
                else
                    row.cost:SetTextColor(0.35, 1.00, 0.35)
                end
            end
            if node.fullyOwned and not node.isEndless then
                row.plus:Disable()
                row.plus:SetText("+")
                local bridge = _G.CleanTreeEbonAPI
                if bridge and bridge.HasServerLoadout and bridge.HasServerLoadout() and not node.fullyCommitted then
                    row.state:SetText("|cffffd200STAGED|r")
                else
                    row.state:SetText("|cff888888PURCHASED|r")
                end
            elseif not node.button then
                row.plus:Disable()
                row.plus:SetText("+")
                if node.isEndless then
                    row.state:SetText("|cffff9933BINDING ENDLESS|r")
                else
                    row.state:SetText("|cffaaaaaaBINDING|r")
                end
            elseif node.isEndless and not cost then
                row.plus:Disable()
                row.plus:SetText("+")
                row.state:SetText("|cffff9933ENDLESS • RESOLVING COST|r")
            elseif not structurallyAvailable then
                row.plus:Disable()
                row.plus:SetText("+")
                row.state:SetText(node.isEndless and "|cffff5555ENDLESS • NOT AVAILABLE|r" or "|cffff5555NOT AVAILABLE|r")
            elseif affordable == false then
                row.plus:Disable()
                row.plus:SetText("+")
                row.state:SetText(node.isEndless and "|cffff5555ENDLESS • AVAILABLE|r" or "|cffff5555AVAILABLE|r")
            else
                row.plus:Enable()
                row.plus:SetText("+")
                row.state:SetText(node.isEndless and "|cffff9933ENDLESS • AVAILABLE|r" or "|cff33ff33AVAILABLE|r")
            end
                end -- ownershipMismatch
            end
        else
            row.node = nil
            row:Hide()
        end
    end
    refreshHeader()
    refreshPendingPanel()
end

local function hasVisibleNodeRow()
    for _, row in ipairs(rows or {}) do
        if row and row.node and row.IsShown then
            local ok, shown = pcall(row.IsShown, row)
            if ok and shown then return true end
        end
    end
    return false
end

setStatus = function(msg, seconds)
    statusMessage = msg
    local now = (type(GetTime) == "function" and GetTime()) or 0
    statusExpire = now + (seconds or 4)
    refreshHeader()
end

local function stageNode(node, shoppingAuto)
    if pendingClick then
        setStatus("Waiting for the previous node click to settle.", 3)
        return
    end
    if ET.shoppingRun and ET.shoppingRun.active and not shoppingAuto then
        ET.StopShoppingAuto("Shopping List auto-purchase stopped because you made a manual purchase.")
    end
    if not node then return end
    syncNodeOwnership(node)
    if node.fullyOwned and not node.isEndless then
        setStatus("That node is already fully purchased.", 3)
        rebuildFiltered()
        refreshRows()
        return
    end
    if node.isEndless and node.button and ET.RefreshEndlessLiveData then
        ET.RefreshEndlessLiveData(node, node.button)
    else
        updateNodeFromTooltip(node, true)
    end
    local button = node.button
    if not button then
        setStatus("This node has not been bound to the native tree yet. Wait for the binding scan to finish, then try again.", 5)
        return
    end
    local structurallyAvailable = nodeStructuralAvailability(node)
    if not structurallyAvailable then
        setStatus("That node is NOT AVAILABLE yet; its prerequisites have not been satisfied.", 4)
        refreshRows()
        refreshDetail(node)
        return
    end
    if node.isEndless and not nodeCost(node) then
        setStatus("EbonAPI has not exposed this Endless node cost yet. Click Refresh after the native Skill Tree finishes loading.", 6)
        return
    end

    local before = readSoulAsh()
    if not before then
        setStatus("Could not read the live Soul Ash footer.", 5)
        return
    end
    local cost = nodeCost(node)
    if cost and before < cost then
        setStatus("Available, but you need " .. formatNumber(cost - before) .. " more Soul Ash for that rank.", 5)
        refreshRows()
        refreshDetail(node)
        return
    end

    local beforeTip = node.tooltip
    local beforeRank = tonumber(node.currentRank) or 0
    local ok, why = clickFrame(button)
    if not ok then
        setStatus("Native node click was rejected: " .. tostring(why), 5)
        return
    end

    pendingClick = {
        node = node,
        beforeAsh = before,
        beforeTip = beforeTip,
        beforeRank = beforeRank,
        elapsed = 0,
        shoppingAuto = shoppingAuto == true,
    }
    setStatus("Staging " .. tostring(node.name) .. "...", 2)
end

local function finishPendingClick(after)
    local p = pendingClick
    if not p then return end
    pendingClick = nil
    local node = p.node
    local delta = (p.beforeAsh or after) - after
    -- A successful purchase can unlock dependent nodes elsewhere in the graph.
    -- Drop cached negative availability before refreshing the list.
    for _, other in pairs(liveNodes) do
        other.nativeRejected = nil
        other.nativeCanLearn = nil
    end
    updateNodeFromTooltip(node, true)
    liveRankFromFrame(node)

    local effect = p.beforeTip and summarizeEffect(p.beforeTip.description or "") or nil
    if not effect or effect.text == "Effect unavailable until inspected" then
        effect = node.effect or summarizeEffect(node.description or "")
    end

    pendingSelections[#pendingSelections + 1] = {
        key = node.key,
        nodeID = node.id,
        name = node.name,
        rank = (p.beforeRank or 0) + 1,
        cost = delta,
        description = p.beforeTip and p.beforeTip.description or node.description,
        effect = effect,
        isEndless = node.isEndless,
        button = node.button,
    }
    lastObservedAsh = after
    if node.isEndless and node.button and ET.RefreshEndlessLiveData then
        -- Endless stays purchasable after a successful click. Pull the new live
        -- rank/cost immediately so the same + button can stage another rank.
        node.nativeRejected = nil
        node.nativeCanLearn = nil
        ET.RefreshEndlessLiveData(node, node.button)
    end
    if p.shoppingAuto and ET.shoppingRun and ET.shoppingRun.active then
        ET.shoppingRun.purchased = (ET.shoppingRun.purchased or 0) + 1
        ET.shoppingRun.spent = (ET.shoppingRun.spent or 0) + math.max(0, tonumber(delta) or 0)
        setStatus("Shopping List staged " .. tostring(node.name) .. " for " .. formatNumber(delta) .. " Soul Ash.", 2)
        ET._shoppingResumeDelay = 0.08
    else
        setStatus("Staged " .. tostring(node.name) .. " for " .. formatNumber(delta) .. " Soul Ash.", 3)
    end
    refreshRows()
    refreshDetail(node)
    if ET.RefreshShoppingUI then ET.RefreshShoppingUI() end
end

-- Remove one staged rank using the same native behavior Ebonhold exposes:
-- right-click the node and wait for the live Soul Ash budget to increase.
ET.UnstageCartEntry = function(cartNode)
    if pendingClick then
        setStatus("Waiting for the previous cart action to settle.", 3)
        return
    end
    if not cartNode or not cartNode.isCartEntry then return end

    local index
    for i = #pendingSelections, 1, -1 do
        if pendingSelections[i].key == cartNode.key then index = i break end
    end
    if not index then
        setStatus("That cart entry is no longer staged.", 3)
        rebuildFiltered()
        refreshRows()
        return
    end

    local p = pendingSelections[index]
    local node = liveNodes[p.key]
    if node then ensureNodeBound(node) end

    -- Prefer the exact native widget that successfully accepted the original
    -- left-click. Re-discovery can bind duplicate-name nodes to a different
    -- wrapper later, which is why a specific cart item could become impossible
    -- to right-click even though a newer one removed correctly.
    local button = p.button or (node and node.button)
    if not button then
        setStatus("Could not bind the native node needed to remove that cart item.", 5)
        return
    end

    local before = readSoulAsh()
    if not before then
        setStatus("Could not read the live Soul Ash budget before removing the cart item.", 5)
        return
    end

    local candidates = collectRightClickCandidates(button)
    -- If the node was rebound since it was staged, append that widget's
    -- candidates as fallbacks without replacing the proven staged widget.
    if node and node.button and node.button ~= button then
        local extras = collectRightClickCandidates(node.button)
        local seen = {}
        for _, c in ipairs(candidates) do seen[c] = true end
        for _, c in ipairs(extras) do
            if not seen[c] then candidates[#candidates + 1] = c; seen[c] = true end
        end
    end
    if #candidates == 0 then candidates[1] = button end
    local ok, why = clickFrame(candidates[1], "RightButton")
    if not ok then
        setStatus("Native right-click failed: " .. tostring(why), 5)
        return
    end

    pendingClick = {
        mode = "remove",
        node = node,
        selectionIndex = index,
        beforeAsh = before,
        elapsed = 0,
        removalCandidates = candidates,
        removalCandidateIndex = 1,
    }
    setStatus("Removing " .. tostring(p.name or "cart item") .. "...", 3)
end

ET.FinishPendingRemoval = function(after)
    local p = pendingClick
    if not p or p.mode ~= "remove" then return end
    pendingClick = nil
    local removed = pendingSelections[p.selectionIndex]
    if removed then table.remove(pendingSelections, p.selectionIndex) end
    if p.node then
        p.node.nativeRejected = nil
        p.node.nativeCanLearn = nil
        liveRankFromFrame(p.node)
        syncNodeOwnership(p.node)
    end
    lastObservedAsh = after
    setStatus("Removed " .. tostring(removed and removed.name or "cart item") .. "; staged Soul Ash restored.", 4)
    rebuildFiltered()
    refreshRows()
    if p.node then refreshDetail(p.node) end
end

local function findApplyButton()
    -- The native footer can be rebuilt by Ebonhold while CleanTree is open.
    -- Do not trust a cached Apply frame, and do not let the scan accidentally
    -- rediscover CleanTree's own APPLY CHANGES button. Prefer the current
    -- skillTreeBottomBar subtree, which is where the authoritative native
    -- button lives.
    nativeApplyButton = nil

    local function scan(frames)
        for _, f in ipairs(frames or {}) do
            if f and f ~= applyButton and hasClickHandler(f) then
                local texts = {}
                collectFrameTexts(f, texts, {}, 1)
                for _, t in ipairs(texts) do
                    if lower(trim(t)) == "apply changes" then
                        nativeApplyButton = f
                        return f
                    end
                end
            end
        end
        return nil
    end

    local bottom = _G.skillTreeBottomBar
    if bottom then
        local frames = {}
        collectChildren(bottom, frames, {}, 0, 10)
        local found = scan(frames)
        if found then return found end
    end

    -- Defensive fallback for an Ebonhold revision that relocates the Apply
    -- control outside skillTreeBottomBar. CleanTree's own button is excluded.
    return scan(allTreeFrames())
end

local function applyChanges()
    local b = findApplyButton()
    if not b then
        setStatus("Could not locate Ebonhold's native Apply Changes button. Open /progression -> Skill Tree and try Refresh.", 7)
        return
    end
    local ok, why = clickFrame(b)
    if not ok then
        setStatus("Native Apply Changes click failed: " .. tostring(why), 7)
        return
    end
    local bridge = _G.CleanTreeEbonAPI
    if bridge and bridge.RequestLoadout then bridge.RequestLoadout(false) end
    setStatus("Apply requested; waiting for Ebonhold confirmation...", 8)
end

local function discardByReload()
    StaticPopupDialogs["EBONTREE_DISCARD_RELOAD"] = StaticPopupDialogs["EBONTREE_DISCARD_RELOAD"] or {
        text = "Discard un-applied Skill Tree changes by reloading the UI?\n\nThis uses /reload because Ebonhold owns the staged tree state.",
        button1 = "Reload / Discard",
        button2 = "Cancel",
        OnAccept = function() ReloadUI() end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
    }
    StaticPopup_Show("EBONTREE_DISCARD_RELOAD")
end

local function installApplyHook()
    if applyHooked then return true end
    local bridge = _G.CleanTreeEbonAPI
    local st = bridge and bridge.GetSkillTree and bridge.GetSkillTree() or (ProjectEbonhold and ProjectEbonhold.SkillTree)
    if not st or type(st.OnApplyChangesResult) ~= "function" or type(hooksecurefunc) ~= "function" then return false end

    local ok = pcall(function()
        hooksecurefunc(st, "OnApplyChangesResult", function(...)
            local success = nil
            for i = 1, select("#", ...) do
                local v = select(i, ...)
                if type(v) == "boolean" then
                    if v == true then success = true
                    elseif success == nil then success = false end
                end
            end
            if success == false then
                setStatus("Ebonhold reported that Apply Changes did not succeed.", 7)
                return
            end
            pendingSelections = {}
            untrackedSpend = 0
            lastObservedAsh = readSoulAsh()
            clearTreeCaches()
            local bridge = _G.CleanTreeEbonAPI
            if bridge and bridge.RequestLoadout then bridge.RequestLoadout(true) end
            setStatus("Apply confirmed by Ebonhold.", 5)
            discoverRuntimeNodes()
            startBackgroundScan()
            refreshRows()
            if selectedNode then refreshDetail(selectedNode) end
        end)
    end)
    if ok then applyHooked = true end
    return ok
end

local function makeButton(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(width or 100)
    b:SetHeight(height or 24)
    b:SetText(text or "Button")
    return b
end


-- Shopping Lists ------------------------------------------------------------
-- A Shopping List is an exact ordered set of finite Skill Tree node IDs. The
-- order is treated as a live priority queue: locked/unaffordable entries are
-- temporarily skipped, and after every accepted purchase CleanTree starts again
-- at priority #1. This mirrors the successful AshBuild custom-priority behavior
-- while keeping the player in control of the exact node order.

ET.SHOPPING_EXPORT_VERSION = "CTSL1"
ET.SHOPPING_SEED_VERSION = 2
ET.shoppingFrame = nil
ET.shoppingImportFrame = nil
ET.shoppingExportFrame = nil
ET.shoppingSelectedName = nil
ET.shoppingListRows = {}
ET.shoppingEntryRows = {}
ET.shoppingSearchRows = {}
ET.shoppingSearchResults = {}
ET.shoppingSearchOffset = 0
ET.shoppingRun = { active = false, purchased = 0, spent = 0 }
ET._shoppingResumeDelay = 0

-- Shopping Lists are rendered as a true modal dialog on UIParent.  Do not try
-- to outrun Ebonhold's nested Progression frames with huge frame levels: the
-- 3.3.5 client can flatten/clamp old frame-level stacks, leaving buttons visible
-- while another frame still owns the mouse.  FULLSCREEN_DIALOG gives this UI a
-- clean strata boundary.  Lifecycle hooks below still close it with /progression.
ET.SHOP_COLORS = ET.SHOP_COLORS or {
    -- Match CleanTree's established black/charcoal panels. Gold remains an
    -- accent/border color, not the dominant background color.
    BG     = {0.035, 0.035, 0.045, 1.00},
    PANEL  = {0.075, 0.075, 0.090, 1.00},
    PANEL2 = {0.105, 0.105, 0.125, 1.00},
    ROW_A  = {0.065, 0.065, 0.080, 1.00},
    ROW_B  = {0.095, 0.095, 0.115, 1.00},
    INPUT  = {0.020, 0.020, 0.028, 1.00},
}

function ET.SetShoppingBackdrop(frame, color)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left=4, right=4, top=4, bottom=4},
    })
    frame:SetBackdropColor(unpack(color or ET.SHOP_COLORS.PANEL))
    frame:SetBackdropBorderColor(0.72, 0.55, 0.18, 1)
end

function ET.SetShoppingLevel(frame, level)
    if not frame then return end
    if frame.SetFrameStrata then pcall(frame.SetFrameStrata, frame, "FULLSCREEN_DIALOG") end
    if frame.SetFrameLevel then pcall(frame.SetFrameLevel, frame, level or 10) end
    if frame.EnableMouse then pcall(frame.EnableMouse, frame, true) end
    if frame.SetToplevel then pcall(frame.SetToplevel, frame, true) end
end

function ET.SyncShoppingFrameLayer(frame, parent, level)
    frame = frame or ET.shoppingFrame
    parent = parent or UIParent
    if not frame or not parent then return end
    if frame.SetParent and frame.GetParent then
        local ok, current = pcall(frame.GetParent, frame)
        if (not ok) or current ~= parent then pcall(frame.SetParent, frame, parent) end
    end
    ET.SetShoppingLevel(frame, level or 10)
    if frame.Raise then pcall(frame.Raise, frame) end
end

function ET.HideShoppingUI()
    if ET.shoppingTransferFrame and ET.shoppingTransferFrame.Hide then ET.shoppingTransferFrame:Hide() end
    if ET.shoppingFrame and ET.shoppingFrame.Hide then ET.shoppingFrame:Hide() end
end

function ET.ShoppingSafeName(name)
    name = compactSpace(name or "Shopping List")
    name = string.gsub(name, "[|:]", "-")
    if name == "" then name = "Shopping List" end
    if string.len(name) > 42 then name = string.sub(name, 1, 42) end
    return name
end

function ET.ShoppingEncodeName(name)
    return (string.gsub(tostring(name or ""), "([^%w%-%._ ])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

function ET.ShoppingDecodeName(name)
    return (string.gsub(tostring(name or ""), "%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

function ET.ShoppingNodeCostByID(id)
    local def = DATA.nodes and DATA.nodes[tonumber(id)] or nil
    local rank = def and def.ranks and def.ranks[1] or nil
    return rank and tonumber(rank.cost) or 0
end

function ET.ShoppingCategoryByID(id)
    local graph = _G.EbonTreeOrderData
    if graph and graph.categoryById and graph.categoryById[tonumber(id)] then
        return graph.categoryById[tonumber(id)]
    end
    local def = DATA.nodes and DATA.nodes[tonumber(id)] or nil
    return def and def.category or "OTHER"
end

function ET.ShoppingOrderedIDs(categoryOrder, cheapest)
    local ids = {}
    for id, def in pairs(DATA.nodes or {}) do
        ids[#ids + 1] = tonumber(id)
    end
    local catRank = {}
    if type(categoryOrder) == "table" then
        for i, c in ipairs(categoryOrder) do catRank[c] = i end
    end
    table.sort(ids, function(a, b)
        if cheapest then
            local ac, bc = ET.ShoppingNodeCostByID(a), ET.ShoppingNodeCostByID(b)
            if ac ~= bc then return ac < bc end
        end
        if next(catRank) then
            local ar = catRank[ET.ShoppingCategoryByID(a)] or 99
            local br = catRank[ET.ShoppingCategoryByID(b)] or 99
            if ar ~= br then return ar < br end
        end
        local graph = _G.EbonTreeOrderData
        local ao = graph and graph.orderById and tonumber(graph.orderById[a]) or 2147483647
        local bo = graph and graph.orderById and tonumber(graph.orderById[b]) or 2147483647
        if ao ~= bo then return ao < bo end
        return a < b
    end)
    return ids
end

function ET.LegacyDamageFirstIDs()
    return ET.ShoppingOrderedIDs({"DAMAGE", "SURVIVAL", "CONVENIENCE", "OTHER"}, false)
end

function ET.ShoppingParentsByID(id)
    id = tonumber(id)
    local bridge = _G.CleanTreeEbonAPI
    if bridge and bridge.GetParents then
        local parents = bridge.GetParents(id)
        if type(parents) == "table" then return parents end
    end
    local graph = _G.EbonTreeOrderData
    return graph and graph.parentsById and graph.parentsById[id] or nil
end

function ET.DamageFirstOrderedIDs()
    local preference = ET.GetPlayerDamagePreference()
    if not ET.damageBranchMap then ET.BuildDamageBranchMap() end
    if preference == "ALL" or not ET.damageBranchMap or not ET.damageBranchMap.valid then
        ET.damageShoppingTopologyFallback = false
        return ET.LegacyDamageFirstIDs()
    end

    local ids, idSet = {}, {}
    for id in pairs(DATA.nodes or {}) do
        id = tonumber(id)
        if id then ids[#ids + 1] = id; idSet[id] = true end
    end

    local parentsById, children, indegree = {}, {}, {}
    for _, id in ipairs(ids) do
        local parents = ET.ShoppingParentsByID(id) or {}
        parentsById[id] = {}
        indegree[id] = 0
        for _, parentId in ipairs(parents) do
            parentId = tonumber(parentId)
            if parentId and idSet[parentId] then
                parentsById[id][#parentsById[id] + 1] = parentId
                children[parentId] = children[parentId] or {}
                children[parentId][#children[parentId] + 1] = id
                indegree[id] = indegree[id] + 1
            end
        end
    end

    local preferredTargets, requiredAncestors = {}, {}
    for _, id in ipairs(ids) do
        if ET.ShoppingCategoryByID(id) == "DAMAGE" then
            local branch = ET.GetDamageBranch(id)
            if branch == "ROOT" or branch == "MIXED" or branch == "GENERAL" or branch == preference then
                preferredTargets[id] = true
            end
        end
    end
    local queue, qi = {}, 1
    for id in pairs(preferredTargets) do queue[#queue + 1] = id end
    while queue[qi] do
        local id = queue[qi]
        qi = qi + 1
        for _, parentId in ipairs(parentsById[id] or {}) do
            if not preferredTargets[parentId] and not requiredAncestors[parentId] then
                requiredAncestors[parentId] = true
                queue[#queue + 1] = parentId
            end
        end
    end

    local function priority(id)
        if requiredAncestors[id] then return 1 end
        local category = ET.ShoppingCategoryByID(id)
        if category == "DAMAGE" then
            local branch = ET.GetDamageBranch(id)
            if branch == "ROOT" or branch == "MIXED" or branch == "GENERAL" then return 1 end
            if branch == preference then return 2 end
            return 6
        elseif category == "SURVIVAL" then return 3
        elseif category == "CONVENIENCE" then return 4
        else return 5 end
    end

    local graph = _G.EbonTreeOrderData
    local function stableOrder(id)
        return graph and graph.orderById and tonumber(graph.orderById[id]) or 2147483647
    end
    local function better(a, b)
        local ap, bp = priority(a), priority(b)
        if ap ~= bp then return ap < bp end
        local ao, bo = stableOrder(a), stableOrder(b)
        if ao ~= bo then return ao < bo end
        return a < b
    end

    local ready = {}
    for _, id in ipairs(ids) do if indegree[id] == 0 then ready[#ready + 1] = id end end
    local out = {}
    while #ready > 0 do
        local bestIndex = 1
        for i = 2, #ready do if better(ready[i], ready[bestIndex]) then bestIndex = i end end
        local id = table.remove(ready, bestIndex)
        out[#out + 1] = id
        for _, childId in ipairs(children[id] or {}) do
            indegree[childId] = indegree[childId] - 1
            if indegree[childId] == 0 then ready[#ready + 1] = childId end
        end
    end

    if #out ~= #ids then
        ET.damageShoppingTopologyFallback = true
        return ET.LegacyDamageFirstIDs()
    end
    ET.damageShoppingTopologyFallback = false
    return out
end

function ET.IDListsEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
    for i = 1, #a do if tonumber(a[i]) ~= tonumber(b[i]) then return false end end
    return true
end

function ET.MarkShoppingListModified(list)
    if not list then return end
    list.seeded = nil
    list.profile = nil
    list.generatedContext = nil
    list.generatedProfileVersion = nil
    list.userModified = true
end

function ET.RefreshGeneratedShoppingProfiles(force)
    if type(EbonTreeDB.shoppingLists) ~= "table" then return end
    local context = ET.GetDamageContextKey()
    for _, list in pairs(EbonTreeDB.shoppingLists) do
        if type(list) == "table" and list.profile == "DAMAGE_FIRST" then
            if force or list.generatedContext ~= context or tonumber(list.generatedProfileVersion or 0) < 1 then
                list.entries = ET.CopyIDList(ET.DamageFirstOrderedIDs())
                list.generatedContext = context
                list.generatedProfileVersion = 1
                list.seeded = true
            end
        end
    end
end

function ET.ShoppingBalancedIDs()
    local buckets = { DAMAGE = {}, SURVIVAL = {}, CONVENIENCE = {}, OTHER = {} }
    local all = ET.ShoppingOrderedIDs(nil, false)
    for _, id in ipairs(all) do
        local c = ET.ShoppingCategoryByID(id)
        local b = buckets[c] or buckets.OTHER
        b[#b + 1] = id
    end
    local out, i = {}, 1
    while true do
        local added = false
        for _, c in ipairs({"DAMAGE", "SURVIVAL", "CONVENIENCE", "OTHER"}) do
            if buckets[c][i] then out[#out + 1] = buckets[c][i]; added = true end
        end
        if not added then break end
        i = i + 1
    end
    return out
end

function ET.CopyIDList(src)
    local out = {}
    for i, id in ipairs(src or {}) do out[i] = tonumber(id) end
    return out
end

function ET.EnsureShoppingLists()
    if type(EbonTreeDB.shoppingLists) ~= "table" then EbonTreeDB.shoppingLists = {} end
    local seedVersion = tonumber(EbonTreeDB.shoppingSeedVersion or 0)

    if seedVersion < 1 then
        local seeds = {
            {"Full Tree Order", ET.ShoppingOrderedIDs(nil, false)},
            {"Damage First", ET.LegacyDamageFirstIDs()},
            {"Survival First", ET.ShoppingOrderedIDs({"SURVIVAL", "DAMAGE", "CONVENIENCE", "OTHER"}, false)},
            {"Convenience First", ET.ShoppingOrderedIDs({"CONVENIENCE", "DAMAGE", "SURVIVAL", "OTHER"}, false)},
            {"Balanced", ET.ShoppingBalancedIDs()},
            {"Cheapest First", ET.ShoppingOrderedIDs(nil, true)},
        }
        for _, seed in ipairs(seeds) do
            if not EbonTreeDB.shoppingLists[seed[1]] then
                EbonTreeDB.shoppingLists[seed[1]] = { name = seed[1], entries = ET.CopyIDList(seed[2]), seeded = true }
            end
        end
        seedVersion = 1
    end

    if seedVersion < 2 then
        local legacy = ET.LegacyDamageFirstIDs()
        local damage = EbonTreeDB.shoppingLists["Damage First"]
        if not damage then
            EbonTreeDB.shoppingLists["Damage First"] = { name = "Damage First", entries = {}, seeded = true, profile = "DAMAGE_FIRST" }
        elseif damage.profile == "DAMAGE_FIRST" then
            -- Already migrated by a prior test build.
        elseif damage.seeded == true and ET.IDListsEqual(damage.entries or {}, legacy) then
            damage.profile = "DAMAGE_FIRST"
            damage.userModified = nil
        else
            -- Preserve a user-modified legacy Damage First verbatim and create
            -- the adaptive built-in beside it rather than destroying edits.
            local base, candidate, i = "Damage First (Recommended)", "Damage First (Recommended)", 2
            while EbonTreeDB.shoppingLists[candidate] do
                candidate = base .. " (" .. tostring(i) .. ")"
                i = i + 1
            end
            EbonTreeDB.shoppingLists[candidate] = { name = candidate, entries = {}, seeded = true, profile = "DAMAGE_FIRST" }
        end
        seedVersion = 2
    end

    EbonTreeDB.shoppingSeedVersion = seedVersion
    ET.RefreshGeneratedShoppingProfiles()

    if not EbonTreeDB.activeShoppingList or not EbonTreeDB.shoppingLists[EbonTreeDB.activeShoppingList] then
        EbonTreeDB.activeShoppingList = "Full Tree Order"
    end
    if not ET.shoppingSelectedName or not EbonTreeDB.shoppingLists[ET.shoppingSelectedName] then
        ET.shoppingSelectedName = EbonTreeDB.activeShoppingList
    end
end

function ET.ShoppingListNames()
    ET.EnsureShoppingLists()
    local names = {}
    local preferred = {"Full Tree Order", "Damage First", "Damage First (Recommended)", "Survival First", "Convenience First", "Balanced", "Cheapest First"}
    local seen = {}
    for _, name in ipairs(preferred) do
        if EbonTreeDB.shoppingLists[name] then names[#names + 1] = name; seen[name] = true end
    end
    local custom = {}
    for name in pairs(EbonTreeDB.shoppingLists) do if not seen[name] then custom[#custom + 1] = name end end
    table.sort(custom, function(a,b) return lower(a) < lower(b) end)
    for _, name in ipairs(custom) do names[#names + 1] = name end
    return names
end

function ET.UniqueShoppingName(base)
    ET.EnsureShoppingLists()
    base = ET.ShoppingSafeName(base)
    if not EbonTreeDB.shoppingLists[base] then return base end
    local i = 2
    while EbonTreeDB.shoppingLists[base .. " (" .. tostring(i) .. ")"] do i = i + 1 end
    return base .. " (" .. tostring(i) .. ")"
end

function ET.CreateShoppingList(name, entries)
    ET.EnsureShoppingLists()
    name = ET.UniqueShoppingName(name or "My Shopping List")
    EbonTreeDB.shoppingLists[name] = { name = name, entries = ET.CopyIDList(entries or {}) }
    ET.shoppingSelectedName = name
    ET.RefreshShoppingUI()
    return name
end

function ET.DeleteShoppingList(name)
    ET.EnsureShoppingLists()
    if not name or not EbonTreeDB.shoppingLists[name] then return end
    if name == EbonTreeDB.activeShoppingList and ET.shoppingRun and ET.shoppingRun.active then
        ET.StopShoppingAuto("Shopping List auto-purchase stopped because the active list was deleted.")
    end
    EbonTreeDB.shoppingLists[name] = nil
    local names = ET.ShoppingListNames()
    ET.shoppingSelectedName = names[1]
    if not EbonTreeDB.shoppingLists[EbonTreeDB.activeShoppingList] then EbonTreeDB.activeShoppingList = names[1] end
    ET.RefreshShoppingUI()
end

function ET.RenameShoppingList(oldName, newName)
    ET.EnsureShoppingLists()
    local list = oldName and EbonTreeDB.shoppingLists[oldName] or nil
    if not list then return nil end
    newName = ET.ShoppingSafeName(newName)
    if newName == oldName then return oldName end
    newName = ET.UniqueShoppingName(newName)
    EbonTreeDB.shoppingLists[oldName] = nil
    list.name = newName
    list.seeded = nil
    EbonTreeDB.shoppingLists[newName] = list
    if EbonTreeDB.activeShoppingList == oldName then EbonTreeDB.activeShoppingList = newName end
    if ET.shoppingRun and ET.shoppingRun.listName == oldName then ET.shoppingRun.listName = newName end
    ET.shoppingSelectedName = newName
    ET.RefreshShoppingUI()
    return newName
end

function ET.PromptShoppingName(mode)
    ET.EnsureShoppingLists()
    StaticPopupDialogs["CLEANTREE_SHOPPING_NAME"] = StaticPopupDialogs["CLEANTREE_SHOPPING_NAME"] or {
        text = "Shopping List name:",
        button1 = "Save",
        button2 = "Cancel",
        hasEditBox = 1,
        maxLetters = 42,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        OnAccept = function(self)
            local value = self.editBox and self.editBox:GetText() or ""
            if self.data == "rename" then
                ET.RenameShoppingList(ET.shoppingSelectedName, value)
            else
                ET.CreateShoppingList(value, {})
            end
        end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            if parent and parent.button1 then parent.button1:Click() end
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    }
    local popup = StaticPopup_Show("CLEANTREE_SHOPPING_NAME")
    if popup and popup.editBox then
        popup.data = mode
        popup.editBox:SetText(mode == "rename" and tostring(ET.shoppingSelectedName or "") or "My Shopping List")
        popup.editBox:HighlightText()
        popup.editBox:SetFocus()
    end
end

function ET.SelectedShoppingList()
    ET.EnsureShoppingLists()
    return EbonTreeDB.shoppingLists[ET.shoppingSelectedName]
end

function ET.SetActiveShoppingList(name)
    ET.EnsureShoppingLists()
    if EbonTreeDB.shoppingLists[name] then
        EbonTreeDB.activeShoppingList = name
        ET.shoppingSelectedName = name
        setStatus("Active Shopping List: " .. tostring(name), 3)
        ET.RefreshShoppingUI()
    end
end

function ET.ShoppingEncodeID(id)
    id = tonumber(id)
    if not id or id < 0 or id >= (36 * 36) then return nil end
    local alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local hi = math.floor(id / 36)
    local lo = id % 36
    return string.sub(alphabet, hi + 1, hi + 1) .. string.sub(alphabet, lo + 1, lo + 1)
end

function ET.ShoppingDecodeID(pair)
    if type(pair) ~= "string" or string.len(pair) ~= 2 then return nil end
    local alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    pair = string.upper(pair)
    local a = string.find(alphabet, string.sub(pair, 1, 1), 1, true)
    local b = string.find(alphabet, string.sub(pair, 2, 2), 1, true)
    if not a or not b then return nil end
    return (a - 1) * 36 + (b - 1)
end

function ET.ExportShoppingList(name)
    ET.EnsureShoppingLists()
    local list = EbonTreeDB.shoppingLists[name or ET.shoppingSelectedName]
    if not list then return nil end
    local ids = {}
    for _, id in ipairs(list.entries or {}) do
        local encoded = ET.ShoppingEncodeID(id)
        if encoded then ids[#ids + 1] = encoded end
    end
    return ET.SHOPPING_EXPORT_VERSION .. ":" .. ET.ShoppingEncodeName(list.name or name or "Shopping List") .. ":" .. table.concat(ids, "")
end

function ET.ImportShoppingList(payload)
    ET.EnsureShoppingLists()
    payload = trim(payload or "")
    local ver, encName, body = string.match(payload, "^([^:]+):([^:]*):(.*)$")
    if ver ~= ET.SHOPPING_EXPORT_VERSION then return nil, "That is not a supported CleanTree Shopping List string." end
    local name = ET.ShoppingSafeName(ET.ShoppingDecodeName(encName))
    local entries, seen = {}, {}
    if string.find(body or "", ",", 1, true) then
        -- Early beta compatibility: accept the original decimal/comma body too.
        for token in string.gmatch(body or "", "[^,]+") do
            local id = tonumber(token)
            if id and DATA.nodes and DATA.nodes[id] and not seen[id] then
                entries[#entries + 1] = id
                seen[id] = true
            end
        end
    else
        local i = 1
        while i + 1 <= string.len(body or "") do
            local id = ET.ShoppingDecodeID(string.sub(body, i, i + 1))
            if id and DATA.nodes and DATA.nodes[id] and not seen[id] then
                entries[#entries + 1] = id
                seen[id] = true
            end
            i = i + 2
        end
    end
    if #entries == 0 then return nil, "The Shopping List contained no recognized finite node IDs." end
    name = ET.UniqueShoppingName(name)
    EbonTreeDB.shoppingLists[name] = { name = name, entries = entries, imported = true }
    ET.shoppingSelectedName = name
    EbonTreeDB.activeShoppingList = name
    ET.RefreshShoppingUI()
    return name, nil
end

function ET.AppendMissingShoppingNodes()
    local list = ET.SelectedShoppingList()
    if not list then return end
    local seen = {}
    for _, id in ipairs(list.entries or {}) do seen[tonumber(id)] = true end
    local added = 0
    for _, id in ipairs(ET.ShoppingOrderedIDs(nil, false)) do
        if not seen[id] then list.entries[#list.entries + 1] = id; seen[id] = true; added = added + 1 end
    end
    setStatus("Added " .. tostring(added) .. " missing finite nodes to the end of " .. tostring(list.name) .. ".", 4)
    ET.RefreshShoppingUI()
end

function ET.AddShoppingNode(id)
    local list = ET.SelectedShoppingList()
    id = tonumber(id)
    if not list or not id or not DATA.nodes[id] then return end
    for index, existing in ipairs(list.entries or {}) do
        if tonumber(existing) == id then
            ET.shoppingEntryOffset = math.max(0, index - 1)
            setStatus("That node is already priority #" .. tostring(index) .. "; jumped to it so you can move it.", 4)
            ET.RefreshShoppingUI()
            return
        end
    end
    list.entries[#list.entries + 1] = id
    setStatus("Added " .. tostring(DATA.nodes[id].name or id) .. " to " .. tostring(list.name) .. ".", 3)
    ET.RefreshShoppingUI()
end

function ET.RemoveShoppingEntry(index)
    local list = ET.SelectedShoppingList()
    if list and list.entries and list.entries[index] then table.remove(list.entries, index); ET.RefreshShoppingUI() end
end

function ET.MoveShoppingEntry(index, destination)
    local list = ET.SelectedShoppingList()
    if not list or not list.entries or not list.entries[index] then return end
    local count = #list.entries
    local dest = tonumber(destination) or index
    if dest < 1 then dest = 1 elseif dest > count then dest = count end
    if dest == index then return end
    local id = table.remove(list.entries, index)
    table.insert(list.entries, dest, id)
    ET.RefreshShoppingUI()
end

function ET.FindShoppingNodeByID(id)
    id = tonumber(id)
    if not id then return nil end
    return liveNodes["node:" .. tostring(id)]
end

function ET.StopShoppingAuto(reason)
    if ET.shoppingRun then ET.shoppingRun.active = false end
    ET._shoppingResumeDelay = 0
    if reason and reason ~= "" then setStatus(reason, 5) end
    ET.RefreshShoppingUI()
end

function ET.FinishShoppingAuto(reason)
    local run = ET.shoppingRun or {}
    run.active = false
    ET._shoppingResumeDelay = 0
    local staged = tonumber(run.purchased) or 0
    local spent = tonumber(run.spent) or 0
    if staged > 0 then
        -- Keep the in-window status deliberately short so it cannot wrap up
        -- into the CleanTree title. The detailed stop reason still goes to chat.
        setStatus("Auto-purchase staged " .. tostring(staged) .. " rank(s) for " .. formatNumber(spent) .. " Soul Ash. Review Cart, then APPLY CHANGES.", 12)
        if reason and reason ~= "" then chat(reason) end
        chat("Shopping List staged " .. tostring(staged) .. " purchase(s) for " .. formatNumber(spent) .. " Soul Ash. Apply Changes is waiting on you.")
    else
        setStatus("No Shopping List purchases are available right now.", 8)
        if reason and reason ~= "" then chat(reason) end
    end
    ET.RefreshShoppingUI()
end

function ET.ContinueShoppingAuto()
    local run = ET.shoppingRun
    if not run or not run.active or pendingClick then return end
    ET.EnsureShoppingLists()
    local list = EbonTreeDB.shoppingLists[run.listName]
    if not list then ET.FinishShoppingAuto("The active Shopping List no longer exists."); return end
    if not next(liveNodes) then buildKnownNodes(); ET.BuildTreeOrderCache() end

    local ash = readSoulAsh()
    if not ash then ET.FinishShoppingAuto("Could not read live Soul Ash; auto-purchase stopped."); return end

    local locked, expensive, owned, missing = 0, 0, 0, 0
    for index, id in ipairs(list.entries or {}) do
        local node = ET.FindShoppingNodeByID(id)
        if not node then
            missing = missing + 1
        else
            ensureNodeBound(node)
            syncNodeOwnership(node)
            if node.fullyOwned then
                owned = owned + 1
            elseif not node.button then
                missing = missing + 1
            else
                local available = nodeStructuralAvailability(node)
                local cost = nodeCost(node)
                if not available then
                    locked = locked + 1
                elseif not cost then
                    missing = missing + 1
                elseif ash < cost then
                    expensive = expensive + 1
                else
                    run.currentIndex = index
                    run.currentID = id
                    stageNode(node, true)
                    if pendingClick then
                        pendingClick.shoppingListIndex = index
                        pendingClick.shoppingListName = run.listName
                        ET.RefreshShoppingUI()
                        return
                    end
                    -- If the click could not even be sent, continue scanning.
                end
            end
        end
    end

    local detail = "No additional purchases are available from this Shopping List right now."
    if expensive > 0 then detail = detail .. " " .. tostring(expensive) .. " higher/lower priority item(s) need more Soul Ash." end
    if locked > 0 then detail = detail .. " " .. tostring(locked) .. " item(s) are still prerequisite-locked." end
    if missing > 0 then detail = detail .. " " .. tostring(missing) .. " item(s) are not currently bound." end
    ET.FinishShoppingAuto(detail)
end

function ET.StartShoppingAuto(name)
    ET.EnsureShoppingLists()
    if pendingClick then setStatus("Wait for the current node action to finish before starting Shopping List auto-purchase.", 5); return end
    name = name or ET.shoppingSelectedName or EbonTreeDB.activeShoppingList
    local list = EbonTreeDB.shoppingLists[name]
    if not list then setStatus("Select a Shopping List first.", 4); return end
    if #(list.entries or {}) == 0 then setStatus("That Shopping List is empty.", 4); return end
    EbonTreeDB.activeShoppingList = name
    ET.shoppingSelectedName = name
    ET.shoppingRun = { active = true, listName = name, purchased = 0, spent = 0, started = (GetTime and GetTime()) or 0 }
    setStatus("Auto-purchasing " .. tostring(name) .. ". Purchases are staged; Apply remains manual.", 5)
    ET.RefreshShoppingUI()
    ET.ContinueShoppingAuto()
end

function ET.ShoppingSearch(term)
    term = lower(trim(term or ""))
    ET.shoppingSearchResults = {}
    if term == "" then return end
    local ordered = ET.ShoppingOrderedIDs(nil, false)
    for _, id in ipairs(ordered) do
        local def = DATA.nodes[id]
        local name = def and def.name or ("Node " .. tostring(id))
        if string.find(lower(name), term, 1, true) or tostring(id) == term then
            ET.shoppingSearchResults[#ET.shoppingSearchResults + 1] = id
        end
    end
end

function ET.RefreshShoppingSearchRows()
    for i, row in ipairs(ET.shoppingSearchRows or {}) do
        local id = ET.shoppingSearchResults[(ET.shoppingSearchOffset or 0) + i]
        if id then
            local def = DATA.nodes[id] or {}
            row.nodeID = id
            row.text:SetText(tostring(id) .. "  |cffffd200" .. tostring(def.name or "Node") .. "|r  |cff888888" .. tostring(ET.ShoppingCategoryByID(id)) .. "|r")
            row.add:Enable()
            row:Show()
        else
            row.nodeID = nil
            row:Hide()
        end
    end
end

function ET.RefreshShoppingUI()
    if not ET.shoppingFrame then return end
    ET.EnsureShoppingLists()
    local names = ET.ShoppingListNames()
    ET.shoppingVisibleNames = names
    for i, row in ipairs(ET.shoppingListRows or {}) do
        local name = names[i]
        if name then
            row.listName = name
            local active = name == EbonTreeDB.activeShoppingList
            local selected = name == ET.shoppingSelectedName
            row.text:SetText((active and "|cff33ff33* |r" or "  ") .. (selected and "|cffffd200" or "|cffffffff") .. name .. "|r")
            row:Show()
        else row.listName = nil; row:Hide() end
    end
    local list = ET.SelectedShoppingList()
    if ET.shoppingTitleText then
        ET.shoppingTitleText:SetText(list and ("Shopping List: |cffffd200" .. tostring(list.name) .. "|r") or "Shopping List")
    end
    if ET.shoppingActiveText then ET.shoppingActiveText:SetText("Active: |cff33ff33" .. tostring(EbonTreeDB.activeShoppingList or "none") .. "|r") end
    if ET.shoppingCountText then ET.shoppingCountText:SetText(list and (tostring(#(list.entries or {})) .. " finite nodes") or "0 finite nodes") end

    ET.shoppingEntryOffset = ET.shoppingEntryOffset or 0
    local entries = list and list.entries or {}
    local maxOffset = math.max(0, #entries - #(ET.shoppingEntryRows or {}))
    if ET.shoppingEntryOffset > maxOffset then ET.shoppingEntryOffset = maxOffset end
    for i, row in ipairs(ET.shoppingEntryRows or {}) do
        local index = ET.shoppingEntryOffset + i
        local id = entries[index]
        if id then
            local def = DATA.nodes[id] or {}
            row.entryIndex = index
            row.idText:SetText("#" .. tostring(index))
            row.nameText:SetText(tostring(id) .. "  |cffffd200" .. tostring(def.name or "Node") .. "|r")
            row.metaText:SetText(tostring(ET.ShoppingCategoryByID(id)) .. "  •  " .. formatNumber(ET.ShoppingNodeCostByID(id)) .. " Ash")
            row:Show()
        else row.entryIndex = nil; row:Hide() end
    end
    if ET.shoppingAutoButton then
        if ET.shoppingRun and ET.shoppingRun.active then
            ET.shoppingAutoButton:SetText("STOP AUTO-PURCHASE")
        else
            ET.shoppingAutoButton:SetText("AUTO-PURCHASE THIS LIST")
        end
    end
    if ET.shoppingRunText then
        if ET.shoppingRun and ET.shoppingRun.active then
            ET.shoppingRunText:SetText("|cff33ff33Running|r • staged " .. tostring(ET.shoppingRun.purchased or 0) .. " • spent " .. formatNumber(ET.shoppingRun.spent or 0))
        else
            ET.shoppingRunText:SetText("Stages purchases only. |cffffd200You still click APPLY CHANGES.|r")
        end
    end
    ET.RefreshShoppingSearchRows()
end

function ET.ShowShoppingTransfer(mode)
    ET.EnsureShoppingLists()
    local transferParent = UIParent
    if not ET.shoppingTransferFrame then
        local f = CreateFrame("Frame", "CleanTreeShoppingTransferFrame", transferParent)
        f:SetWidth(720); f:SetHeight(430); f:SetPoint("CENTER", transferParent, "CENTER", 0, 0); f:EnableMouse(true)
        ET.SyncShoppingFrameLayer(f, transferParent, 40)
        ET.SetShoppingBackdrop(f, ET.SHOP_COLORS.PANEL)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 18, -16); f.title = title
        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8); hint:SetWidth(675); hint:SetJustifyH("LEFT"); f.hint = hint
        local fieldLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); fieldLabel:SetPoint("TOPLEFT", 18, -74); fieldLabel:SetText("|cffffd200Paste here:|r"); f.fieldLabel = fieldLabel
        local close = makeButton(f, "Close", 80, 26); ET.SetShoppingLevel(close, 44); close:SetPoint("BOTTOMRIGHT", -14, 14); close:SetScript("OnClick", function() f:Hide() end)
        local action = makeButton(f, "Import", 92, 26); ET.SetShoppingLevel(action, 44); action:SetPoint("RIGHT", close, "LEFT", -8, 0); f.action = action

        -- Give the multiline edit area an unmistakable black input well. The
        -- frame is visual-only so it can never intercept mouse clicks.
        local inputWell = CreateFrame("Frame", nil, f)
        inputWell:SetPoint("TOPLEFT", 14, -94); inputWell:SetPoint("BOTTOMRIGHT", -36, 50)
        inputWell:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = {left=3, right=3, top=3, bottom=3},
        })
        inputWell:SetBackdropColor(unpack(ET.SHOP_COLORS.INPUT))
        inputWell:SetBackdropBorderColor(0.42, 0.42, 0.46, 1)
        if inputWell.SetFrameStrata then inputWell:SetFrameStrata("FULLSCREEN_DIALOG") end
        if inputWell.SetFrameLevel then inputWell:SetFrameLevel(41) end
        if inputWell.EnableMouse then inputWell:EnableMouse(false) end
        f.inputWell = inputWell

        local scroll = CreateFrame("ScrollFrame", "CleanTreeShoppingTransferScroll", f, "UIPanelScrollFrameTemplate")
        ET.SetShoppingLevel(scroll, 42)
        scroll:SetPoint("TOPLEFT", 22, -102); scroll:SetPoint("BOTTOMRIGHT", -48, 58)
        local edit = CreateFrame("EditBox", "CleanTreeShoppingTransferEdit", scroll)
        ET.SetShoppingLevel(edit, 43)
        edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject(ChatFontNormal); edit:SetWidth(625); edit:SetHeight(280); edit:SetTextInsets(6,6,6,6)
        if edit.SetTextColor then edit:SetTextColor(0.96, 0.96, 0.96) end
        if edit.SetJustifyH then edit:SetJustifyH("LEFT") end
        if edit.SetJustifyV then edit:SetJustifyV("TOP") end
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        scroll:SetScrollChild(edit); f.edit = edit
        ET.shoppingTransferFrame = f
    end
    local f = ET.shoppingTransferFrame
    local transferParent = UIParent
    ET.SyncShoppingFrameLayer(f, transferParent, 40)
    f:ClearAllPoints()
    f:SetPoint("CENTER", transferParent, "CENTER", 0, 0)
    f.mode = mode
    if mode == "export" then
        local payload = ET.ExportShoppingList(ET.shoppingSelectedName) or ""
        f.title:SetText("Export Shopping List")
        f.hint:SetText("Copy this entire single string and send it to another CleanTree user. The string contains the list name and exact ordered node IDs.")
        if f.fieldLabel then f.fieldLabel:SetText("|cffffd200Share string:|r") end
        f.edit:SetText(payload); f.edit:HighlightText(); f.edit:SetFocus()
        f.action:SetText("Select All")
        f.action:SetScript("OnClick", function() f.edit:SetFocus(); f.edit:HighlightText() end)
    else
        f.title:SetText("Import Shopping List")
        f.hint:SetText("Paste a CTSL1 Shopping List string into the clearly marked box below, then click Import. It will be saved as a new list and selected immediately.")
        if f.fieldLabel then f.fieldLabel:SetText("|cffffd200Paste CTSL1 string here:|r") end
        f.edit:SetText(""); f.edit:SetFocus()
        if f.edit.SetCursorPosition then f.edit:SetCursorPosition(0) end
        f.action:SetText("Import")
        f.action:SetScript("OnClick", function()
            local name, err = ET.ImportShoppingList(f.edit:GetText() or "")
            if name then
                setStatus("Imported Shopping List: " .. tostring(name), 5)
                chat("Imported Shopping List '" .. tostring(name) .. "'.")
                f:Hide()
            else
                setStatus(err or "Shopping List import failed.", 7)
            end
        end)
    end
    f:Show()
end

function ET.OpenShoppingLists()
    ET.EnsureShoppingLists()
    if not mainFrame or not mainFrame:IsShown() then return end
    if ET.shoppingFrame then
        ET.SyncShoppingFrameLayer(ET.shoppingFrame, UIParent, 10)
        ET.shoppingFrame:ClearAllPoints()
        ET.shoppingFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        ET.shoppingFrame:Show()
        if ET.shoppingFrame.Raise then ET.shoppingFrame:Raise() end
        ET.RefreshShoppingUI()
        return
    end
    local f = CreateFrame("Frame", "CleanTreeShoppingFrame", UIParent)
    f:SetWidth(960); f:SetHeight(680); f:SetPoint("CENTER", UIParent, "CENTER", 0, 0); f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    ET.SyncShoppingFrameLayer(f, UIParent, 10)
    f:SetScript("OnShow", function(self) ET.SyncShoppingFrameLayer(self, UIParent, 10); if self.Raise then self:Raise() end end)
    f:SetScript("OnHide", function() if ET.shoppingTransferFrame then ET.shoppingTransferFrame:Hide() end end)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end); f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    ET.SetShoppingBackdrop(f, ET.SHOP_COLORS.BG)
    ET.shoppingFrame = f

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 18, -14); title:SetText("|cffffd200CleanTree Shopping Lists|r")
    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5); subtitle:SetWidth(760); subtitle:SetJustifyH("LEFT"); subtitle:SetTextColor(1, 1, 1, 1); subtitle:SetText("Exact node priority lists. Locked or unaffordable entries are skipped temporarily; priority #1 is rechecked after every successful purchase.")
    local close = makeButton(f, "X", 28, 24); ET.SetShoppingLevel(close, 20); close:SetPoint("TOPRIGHT", -12, -12); close:SetScript("OnClick", function() f:Hide() end)

    local left = CreateFrame("Frame", nil, f); left:SetPoint("TOPLEFT", 14, -72); left:SetPoint("BOTTOMLEFT", 14, 14); left:SetWidth(220); ET.SetShoppingBackdrop(left, ET.SHOP_COLORS.PANEL); ET.SetShoppingLevel(left, 12)
    local lh = left:CreateFontString(nil, "OVERLAY", "GameFontNormal"); lh:SetPoint("TOPLEFT", 12, -10); lh:SetText("Saved Lists")
    for i=1,12 do
        local row = CreateFrame("Button", nil, left); ET.SetShoppingLevel(row, 14); row:SetHeight(28); row:SetPoint("TOPLEFT", 8, -34-((i-1)*29)); row:SetPoint("TOPRIGHT", -8, -34-((i-1)*29))
        row.text = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.text:SetAllPoints(); row.text:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(self) if self.listName then ET.shoppingSelectedName=self.listName; ET.shoppingEntryOffset=0; ET.RefreshShoppingUI() end end)
        ET.shoppingListRows[i]=row
    end
    local newBtn = makeButton(left,"New",46,24); ET.SetShoppingLevel(newBtn, 16); newBtn:SetPoint("BOTTOMLEFT",8,10); newBtn:SetScript("OnClick",function() ET.PromptShoppingName("new") end)
    local copyBtn = makeButton(left,"Copy",46,24); ET.SetShoppingLevel(copyBtn, 16); copyBtn:SetPoint("LEFT",newBtn,"RIGHT",4,0); copyBtn:SetScript("OnClick",function() local l=ET.SelectedShoppingList(); if l then ET.CreateShoppingList((l.name or "List").." Copy",l.entries) end end)
    local renameBtn = makeButton(left,"Name",46,24); ET.SetShoppingLevel(renameBtn, 16); renameBtn:SetPoint("LEFT",copyBtn,"RIGHT",4,0); renameBtn:SetScript("OnClick",function() ET.PromptShoppingName("rename") end)
    local delBtn = makeButton(left,"Del",40,24); ET.SetShoppingLevel(delBtn, 16); delBtn:SetPoint("LEFT",renameBtn,"RIGHT",4,0); delBtn:SetScript("OnClick",function() ET.DeleteShoppingList(ET.shoppingSelectedName) end)

    local right = CreateFrame("Frame", nil, f); right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0); right:SetPoint("BOTTOMRIGHT", -14, 14); ET.SetShoppingBackdrop(right, ET.SHOP_COLORS.PANEL); ET.SetShoppingLevel(right, 12)
    ET.shoppingTitleText = right:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); ET.shoppingTitleText:SetPoint("TOPLEFT",14,-12)
    ET.shoppingActiveText = right:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); ET.shoppingActiveText:SetPoint("TOPLEFT",ET.shoppingTitleText,"BOTTOMLEFT",0,-4)
    ET.shoppingCountText = right:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); ET.shoppingCountText:SetPoint("TOPRIGHT",-14,-16); ET.shoppingCountText:SetJustifyH("RIGHT")

    local useBtn=makeButton(right,"Use This List",100,24); ET.SetShoppingLevel(useBtn, 16); useBtn:SetPoint("TOPLEFT",14,-58); useBtn:SetScript("OnClick",function() ET.SetActiveShoppingList(ET.shoppingSelectedName) end)
    local appendBtn=makeButton(right,"Append Missing",112,24); ET.SetShoppingLevel(appendBtn, 16); appendBtn:SetPoint("LEFT",useBtn,"RIGHT",6,0); appendBtn:SetScript("OnClick",ET.AppendMissingShoppingNodes)
    local exportBtn=makeButton(right,"Export",72,24); ET.SetShoppingLevel(exportBtn, 16); exportBtn:SetPoint("LEFT",appendBtn,"RIGHT",6,0); exportBtn:SetScript("OnClick",function() ET.ShowShoppingTransfer("export") end)
    local importBtn=makeButton(right,"Import",72,24); ET.SetShoppingLevel(importBtn, 16); importBtn:SetPoint("LEFT",exportBtn,"RIGHT",6,0); importBtn:SetScript("OnClick",function() ET.ShowShoppingTransfer("import") end)

    ET.shoppingAutoButton=makeButton(right,"AUTO-PURCHASE THIS LIST",190,28); ET.SetShoppingLevel(ET.shoppingAutoButton, 16); ET.shoppingAutoButton:SetPoint("TOPRIGHT",-14,-54)
    ET.shoppingAutoButton:SetScript("OnClick",function()
        if ET.shoppingRun and ET.shoppingRun.active then ET.StopShoppingAuto("Shopping List auto-purchase stopped by user.") else ET.StartShoppingAuto(ET.shoppingSelectedName) end
    end)
    ET.shoppingRunText=right:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); ET.shoppingRunText:SetPoint("TOPRIGHT",-14,-88); ET.shoppingRunText:SetWidth(300); ET.shoppingRunText:SetJustifyH("RIGHT")

    local listPanel=CreateFrame("Frame",nil,right); listPanel:SetPoint("TOPLEFT",14,-116); listPanel:SetPoint("TOPRIGHT",-14,-116); listPanel:SetHeight(310); ET.SetShoppingBackdrop(listPanel,ET.SHOP_COLORS.PANEL2); ET.SetShoppingLevel(listPanel, 14)
    local listHdr=listPanel:CreateFontString(nil,"OVERLAY","GameFontNormal"); listHdr:SetPoint("TOPLEFT",10,-8); listHdr:SetText("Purchase Priority")
    local listHint=listPanel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); listHint:SetPoint("TOPRIGHT",-10,-9); listHint:SetText("Top = highest priority")

    for i=1,6 do
        local row=CreateFrame("Frame",nil,listPanel); row:SetHeight(38); row:SetPoint("TOPLEFT",8,-32-((i-1)*40)); row:SetPoint("TOPRIGHT",-8,-32-((i-1)*40)); ET.SetShoppingBackdrop(row,i%2==0 and ET.SHOP_COLORS.ROW_A or ET.SHOP_COLORS.ROW_B); ET.SetShoppingLevel(row, 16)
        row.idText=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.idText:SetPoint("LEFT",8,7); row.idText:SetWidth(38); row.idText:SetJustifyH("LEFT")
        row.nameText=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.nameText:SetPoint("LEFT",48,7); row.nameText:SetWidth(300); row.nameText:SetJustifyH("LEFT")
        row.metaText=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.metaText:SetPoint("LEFT",48,-8); row.metaText:SetWidth(260); row.metaText:SetJustifyH("LEFT"); row.metaText:SetTextColor(0.82, 0.78, 0.64, 1)
        row.top=makeButton(row,"Top",38,22); ET.SetShoppingLevel(row.top, 18); row.top:SetPoint("RIGHT",-164,0); row.top:SetScript("OnClick",function() if row.entryIndex then ET.MoveShoppingEntry(row.entryIndex,1) end end)
        row.up=makeButton(row,"Up",28,22); ET.SetShoppingLevel(row.up, 18); row.up:SetPoint("RIGHT",-132,0); row.up:SetScript("OnClick",function() if row.entryIndex then ET.MoveShoppingEntry(row.entryIndex,row.entryIndex-1) end end)
        row.down=makeButton(row,"Dn",28,22); ET.SetShoppingLevel(row.down, 18); row.down:SetPoint("RIGHT",-100,0); row.down:SetScript("OnClick",function() if row.entryIndex then ET.MoveShoppingEntry(row.entryIndex,row.entryIndex+1) end end)
        row.bottom=makeButton(row,"Bot",38,22); ET.SetShoppingLevel(row.bottom, 18); row.bottom:SetPoint("RIGHT",-58,0); row.bottom:SetScript("OnClick",function() local l=ET.SelectedShoppingList(); if row.entryIndex and l then ET.MoveShoppingEntry(row.entryIndex,#l.entries) end end)
        row.remove=makeButton(row,"X",28,22); ET.SetShoppingLevel(row.remove, 18); row.remove:SetPoint("RIGHT",-8,0); row.remove:SetScript("OnClick",function() if row.entryIndex then ET.RemoveShoppingEntry(row.entryIndex) end end)
        ET.shoppingEntryRows[i]=row
    end
    local upPage=makeButton(listPanel,"Page Up",68,22); ET.SetShoppingLevel(upPage, 18); upPage:SetPoint("BOTTOMLEFT",8,8); upPage:SetScript("OnClick",function() ET.shoppingEntryOffset=math.max(0,(ET.shoppingEntryOffset or 0)-6); ET.RefreshShoppingUI() end)
    local downPage=makeButton(listPanel,"Page Dn",68,22); ET.SetShoppingLevel(downPage, 18); downPage:SetPoint("LEFT",upPage,"RIGHT",6,0); downPage:SetScript("OnClick",function() ET.shoppingEntryOffset=(ET.shoppingEntryOffset or 0)+6; ET.RefreshShoppingUI() end)

    local addPanel=CreateFrame("Frame",nil,right); addPanel:SetPoint("TOPLEFT",listPanel,"BOTTOMLEFT",0,-8); addPanel:SetPoint("BOTTOMRIGHT",-14,10); ET.SetShoppingBackdrop(addPanel,ET.SHOP_COLORS.PANEL2); ET.SetShoppingLevel(addPanel, 14)
    local addHdr=addPanel:CreateFontString(nil,"OVERLAY","GameFontNormal"); addHdr:SetPoint("TOPLEFT",10,-9); addHdr:SetText("Add Node")
    local search=CreateFrame("EditBox","CleanTreeShoppingSearch",addPanel,"InputBoxTemplate"); ET.SetShoppingLevel(search, 18); search:SetHeight(24); search:SetPoint("TOPLEFT",80,-6); search:SetPoint("TOPRIGHT",-10,-6); search:SetAutoFocus(false)
    search:SetScript("OnTextChanged",function(self) ET.shoppingSearchOffset=0; ET.ShoppingSearch(self:GetText() or ""); ET.RefreshShoppingSearchRows() end)
    search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    for i=1,3 do
        local row=CreateFrame("Frame",nil,addPanel); ET.SetShoppingLevel(row, 16); row:SetHeight(30); row:SetPoint("TOPLEFT",10,-40-((i-1)*31)); row:SetPoint("TOPRIGHT",-10,-40-((i-1)*31))
        row.text=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.text:SetPoint("LEFT",4,0); row.text:SetPoint("RIGHT",-64,0); row.text:SetJustifyH("LEFT")
        row.add=makeButton(row,"Add",52,22); ET.SetShoppingLevel(row.add, 18); row.add:SetPoint("RIGHT",-2,0); row.add:SetScript("OnClick",function() if row.nodeID then ET.AddShoppingNode(row.nodeID) end end)
        ET.shoppingSearchRows[i]=row
    end
    local prev=makeButton(addPanel,"Prev",52,22); ET.SetShoppingLevel(prev, 18); prev:SetPoint("BOTTOMLEFT",10,8); prev:SetScript("OnClick",function() ET.shoppingSearchOffset=math.max(0,(ET.shoppingSearchOffset or 0)-3); ET.RefreshShoppingSearchRows() end)
    local nextb=makeButton(addPanel,"Next",52,22); ET.SetShoppingLevel(nextb, 18); nextb:SetPoint("LEFT",prev,"RIGHT",6,0); nextb:SetScript("OnClick",function() if (ET.shoppingSearchOffset or 0)+3 < #(ET.shoppingSearchResults or {}) then ET.shoppingSearchOffset=(ET.shoppingSearchOffset or 0)+3; ET.RefreshShoppingSearchRows() end end)

    ET.RefreshShoppingUI()
    f:Show()
end

local function createRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(54)
    setBackdrop(row, index % 2 == 0 and {0.075,0.075,0.09,0.92} or {0.095,0.095,0.11,0.92})

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", 12, -7)
    row.name:SetWidth(250)
    row.name:SetJustifyH("LEFT")
    row.name:SetTextColor(unpack(C.gold))

    row.effect = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.effect:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.effect:SetWidth(310)
    row.effect:SetHeight(24)
    row.effect:SetJustifyH("LEFT")
    row.effect:SetJustifyV("TOP")

    row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.rank:SetPoint("TOPRIGHT", -174, -8)
    row.rank:SetWidth(58)
    row.rank:SetJustifyH("RIGHT")

    row.cost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.cost:SetPoint("BOTTOMRIGHT", -52, 8)
    row.cost:SetWidth(105)
    row.cost:SetJustifyH("RIGHT")
    row.cost:SetTextColor(0.35, 1, 0.35)

    row.state = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.state:SetPoint("TOPRIGHT", -52, -8)
    row.state:SetWidth(118)
    row.state:SetJustifyH("RIGHT")

    row.plus = makeButton(row, "+", 38, 38)
    row.plus:SetPoint("RIGHT", -8, 0)
    row.plus:SetScript("OnClick", function()
        if not row.node then return end
        if row.node.isCartEntry then ET.UnstageCartEntry(row.node) else stageNode(row.node) end
    end)

    row:SetScript("OnClick", function()
        if row.node then refreshDetail(row.node) end
    end)
    row:SetScript("OnEnter", function(self)
        if self.node then refreshDetail(self.node) end
    end)
    row:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    return row
end

local function rememberNativeVisual(frame)
    if not frame or nativeVisualState[frame] then return end
    local state = { alpha = 1 }
    if frame.GetAlpha then
        local ok, a = pcall(frame.GetAlpha, frame)
        if ok and type(a) == "number" then state.alpha = a end
    end
    nativeVisualState[frame] = state
end

local function suppressTopChromeIn(container, native)
    if not container or not native then return end
    local okT, nativeTop = pcall(native.GetTop, native)
    local okL, nativeLeft = pcall(native.GetLeft, native)
    local okR, nativeRight = pcall(native.GetRight, native)
    local okW, nativeWidth = pcall(native.GetWidth, native)
    nativeTop = okT and nativeTop or nil
    nativeLeft = okL and nativeLeft or nil
    nativeRight = okR and nativeRight or nil
    nativeWidth = okW and nativeWidth or nil

    local function nearTop(obj)
        if not nativeTop or not obj or not obj.GetTop then return false end
        local ok, top = pcall(obj.GetTop, obj)
        return ok and type(top) == "number" and math.abs(nativeTop - top) < 105
    end
    local function hide(obj)
        if not obj or obj == mainFrame then return end
        rememberNativeVisual(obj)
        if obj.SetAlpha then pcall(obj.SetAlpha, obj, 0) end
    end
    local function geometry(obj)
        if not obj then return nil,nil,nil,nil end
        local okw,w = pcall(obj.GetWidth,obj); local okh,h = pcall(obj.GetHeight,obj)
        local okl,l = pcall(obj.GetLeft,obj); local okr,r = pcall(obj.GetRight,obj)
        return okw and w or nil, okh and h or nil, okl and l or nil, okr and r or nil
    end

    if container.GetRegions then
        local regions = {container:GetRegions()}
        for _, region in ipairs(regions) do
            if region and nearTop(region) then
                local text = ""
                if region.GetText then
                    local ok,v = pcall(region.GetText, region)
                    if ok then text = lower(compactSpace(v or "")) end
                end
                local w,h,l,r = geometry(region)
                local isTitle = text == "skill tree"
                local isWideBar = nativeWidth and w and h and w > nativeWidth * 0.55 and h > 2 and h < 80
                local isCorner = w and h and w >= 24 and w <= 150 and h >= 24 and h <= 150 and (
                    (nativeLeft and l and l < nativeLeft + 120) or
                    (nativeRight and r and r > nativeRight - 120))
                if isTitle or isWideBar or isCorner then hide(region) end
            end
        end
    end

    if container.GetChildren then
        local children = {container:GetChildren()}
        for _, child in ipairs(children) do
            if child and child ~= mainFrame and child ~= _G.skillTreeCanvas and child ~= _G.skillTreeBottomBar and nearTop(child) then
                local w,h,l,r = geometry(child)
                local isWideBar = nativeWidth and w and h and w > nativeWidth * 0.55 and h > 2 and h < 90
                local isCorner = w and h and w >= 24 and w <= 150 and h >= 24 and h <= 150 and (
                    (nativeLeft and l and l < nativeLeft + 120) or
                    (nativeRight and r and r > nativeRight - 120))
                local texts = {}
                collectFrameTexts(child, texts, {}, 1)
                local isTitle = false
                for _,t in ipairs(texts) do if lower(trim(t)) == "skill tree" then isTitle = true break end end
                if isTitle or isWideBar or isCorner then hide(child) end
            end
        end
    end
end

local function suppressNativeTopLeftIcon()
    local native = _G.skillTreeFrame
    if not native then return end
    local okL, nl = pcall(native.GetLeft, native)
    local okT, nt = pcall(native.GetTop, native)
    if not okL or not okT or type(nl) ~= "number" or type(nt) ~= "number" then return end

    local seen = {}
    local function maybeHide(obj)
        if not obj or obj == mainFrame or seen[obj] or not obj.GetWidth or not obj.GetHeight then return end
        seen[obj] = true
        local okw,w = pcall(obj.GetWidth,obj); local okh,h = pcall(obj.GetHeight,obj)
        local okl,l = pcall(obj.GetLeft,obj); local okt,t = pcall(obj.GetTop,obj)
        if okw and okh and okl and okt and type(w) == "number" and type(h) == "number" and type(l) == "number" and type(t) == "number" then
            -- The native Skill Tree medallion is a large square-ish widget that
            -- overlaps the upper-left content edge. It is nested more deeply on
            -- some client loads, so walk descendants instead of checking only
            -- the first generation of children.
            local squareish = w >= 46 and h >= 46 and w <= 150 and h <= 150 and math.abs(w-h) <= 40
            local atUpperLeft = l < nl + 75 and t > nt - 115
            if squareish and atUpperLeft then
                rememberNativeVisual(obj)
                if obj.SetAlpha then pcall(obj.SetAlpha, obj, 0) end
            end
        end
    end

    local function walk(container, depth)
        if not container or depth > 4 then return end
        maybeHide(container)
        if container.GetRegions then
            for _,r in ipairs({container:GetRegions()}) do maybeHide(r) end
        end
        if container.GetChildren then
            for _,c in ipairs({container:GetChildren()}) do
                maybeHide(c)
                walk(c, depth + 1)
            end
        end
    end

    walk(native, 0)
    if native.GetParent then
        local ok,p = pcall(native.GetParent,native)
        if ok and p then walk(p, 0) end
    end
end

local function suppressNativeSubtree(root, depth, seen)
    if not root or depth > 5 then return end
    seen = seen or {}
    if seen[root] then return end
    seen[root] = true

    rememberNativeVisual(root)
    if root.SetAlpha then pcall(root.SetAlpha, root, 0) end

    if root.GetRegions then
        for _,region in ipairs({root:GetRegions()}) do
            if region and region ~= mainFrame then
                rememberNativeVisual(region)
                if region.SetAlpha then pcall(region.SetAlpha, region, 0) end
            end
        end
    end
    if root.GetChildren then
        for _,child in ipairs({root:GetChildren()}) do
            if child and child ~= mainFrame then
                suppressNativeSubtree(child, depth + 1, seen)
            end
        end
    end
end

local function suppressNativeVisuals()
    nativeSuppressed = true

    -- Hotfix28: the frame-stack probe exposed the real useful hierarchy:
    --   CollectionsJournal -> skillTreeFrame -> skillTreeScroll -> skillTreeCanvas
    -- with skillTreeBottomBar as the native footer.  Do NOT blank every child of
    -- skillTreeFrame: that also catches chrome belonging to the outer progression
    -- presentation.  Suppress only the stock scroll viewport (nodes + native
    -- scrollbar) and the stock bottom bar (Soul Ash / Apply / Search).  CleanTree
    -- is a sibling under skillTreeFrame, so hiding skillTreeScroll cannot hide it.
    local seen = {}
    local scroll = _G.skillTreeScroll
    local canvas = _G.skillTreeCanvas
    local bottom = _G.skillTreeBottomBar

    if scroll then
        suppressNativeSubtree(scroll, 0, seen)
        if scroll.SetAlpha then pcall(scroll.SetAlpha, scroll, 0) end
    elseif canvas then
        -- Fallback for clients/builds that do not expose skillTreeScroll globally.
        suppressNativeSubtree(canvas, 0, seen)
        if canvas.SetAlpha then pcall(canvas.SetAlpha, canvas, 0) end
    end

    if bottom then
        suppressNativeSubtree(bottom, 0, seen)
        -- Parent alpha is authoritative for the Soul Ash label, native Apply
        -- button and native search box.  Keep the whole footer transparent even
        -- if Ebonhold later resets an individual child's alpha.
        if bottom.SetAlpha then pcall(bottom.SetAlpha, bottom, 0) end
    end
end

local function restoreNativeVisuals()
    nativeSuppressed = false
    for frame, state in pairs(nativeVisualState) do
        if frame and frame.SetAlpha then pcall(frame.SetAlpha, frame, state.alpha or 1) end
    end
    nativeVisualState = {}
    nativeApplyButton = nil

    -- Ebonhold can replace the scroll/footer frames after CleanTree originally
    -- recorded their alpha. The periodic suppression loop may therefore have
    -- hidden a newer frame that was never present in nativeVisualState. When
    -- the player explicitly restores native mode, make the current native
    -- content parents visible as a final authoritative cleanup.
    if EbonTreeDB and EbonTreeDB.nativeMode == true then
        for _, frame in ipairs({_G.skillTreeScroll, _G.skillTreeCanvas, _G.skillTreeBottomBar}) do
            if frame and frame.SetAlpha then pcall(frame.SetAlpha, frame, 1) end
        end

        local search = _G.skillTreeSearchBox
        if search then
            if search.SetAlpha then pcall(search.SetAlpha, search, 1) end
            if search.Show then pcall(search.Show, search) end
        end

        local nativeApply = findApplyButton()
        if nativeApply then
            if nativeApply.SetAlpha then pcall(nativeApply.SetAlpha, nativeApply, 1) end
            if nativeApply.Show then pcall(nativeApply.Show, nativeApply) end
        end
    end
end

-- Native/CleanTree mode switcher.  Keep the stock tree alive underneath at all
-- times, but let the player explicitly choose which presentation is visible.
-- The choice is persisted so switching away from the Skill Tree tab and back
-- does not immediately undo a deliberate "Restore Native Skill Tree" click.
function ET.EnsureNativeRestoreButton()
    local host = _G.skillTreeFrame
    if not host then return nil end

    local button = ET.nativeRestoreButton
    if not button then
        button = makeButton(host, "Restore CleanTree UI", 154, 24)
        ET.nativeRestoreButton = button
        button:SetScript("OnClick", function()
            if ET.RestoreCleanTreeUI then ET.RestoreCleanTreeUI() end
        end)
    elseif button.GetParent and button.SetParent then
        local ok, parent = pcall(button.GetParent, button)
        if (not ok) or parent ~= host then pcall(button.SetParent, button, host) end
    end

    local anchor = _G.skillTreeScroll or _G.skillTreeCanvas or host
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -8, -8)

    if button.SetFrameStrata and host.GetFrameStrata then
        local ok, strata = pcall(host.GetFrameStrata, host)
        if ok and strata then pcall(button.SetFrameStrata, button, strata) end
    end
    if button.SetFrameLevel then
        local level = 1
        if anchor and anchor.GetFrameLevel then
            local ok, v = pcall(anchor.GetFrameLevel, anchor)
            if ok and type(v) == "number" then level = v + 25 end
        end
        pcall(button.SetFrameLevel, button, level)
    end

    if EbonTreeDB.nativeMode == true then button:Show() else button:Hide() end
    return button
end

function ET.RestoreNativeSkillTree()
    EbonTreeDB.nativeMode = true
    ET.HideShoppingUI()
    if mainFrame and mainFrame:IsShown() then mainFrame:Hide() end
    restoreNativeVisuals()
    local button = ET.EnsureNativeRestoreButton()
    if button then button:Show() end
    chat("Native Skill Tree restored. Use 'Restore CleanTree UI' to switch back.")
end

local function dockToNativeTree()
    if not mainFrame then return false end
    local native = _G.skillTreeFrame
    if not native then return false end

    -- Shopping Lists must disappear when the native Skill Tree/Progression
    -- window is dismissed even if CleanTree itself remains logically shown.
    -- HookScript preserves Ebonhold's own lifecycle handler.
    if not ET._shoppingLifecycleHooked and native.HookScript then
        local ok = pcall(native.HookScript, native, "OnHide", function() ET.HideShoppingUI() end)
        if ok then ET._shoppingLifecycleHooked = true end
    end

    -- Hotfix28: skillTreeFrame includes more than the drawable viewport.  The
    -- /fstack dump shows skillTreeScroll directly above it, with skillTreeCanvas
    -- inside that scroll frame.  Use the scroll viewport as CleanTree's top/left
    -- geometry so we stay inside the native title/portrait/side borders, while
    -- extending to the native bottom bar's lower-right corner so our replacement
    -- still owns the footer area.  CleanTree remains a child of skillTreeFrame so
    -- it moves/minimizes/restores with CollectionsJournal.
    if mainFrame.GetParent and mainFrame.SetParent then
        local ok, parent = pcall(mainFrame.GetParent, mainFrame)
        if (not ok) or parent ~= native then
            pcall(mainFrame.SetParent, mainFrame, native)
        end
    end

    local viewport = _G.skillTreeScroll or _G.skillTreeCanvas
    local bottom = _G.skillTreeBottomBar

    mainFrame:ClearAllPoints()
    if viewport and viewport.GetLeft then
        -- Hotfix30: the outer CollectionsJournal already supplies the brown
        -- Progression background.  Treat CleanTree as content *inside* that
        -- shell instead of a black replacement window.  Start just inside the
        -- native scroll viewport so the portrait/header never collides with our
        -- left edge, but extend all the way to skillTreeFrame's lower-right
        -- content boundary.  The stock footer is hidden separately, so this also
        -- consumes the dead strip that used to remain above the bottom tabs.
        mainFrame:SetPoint("TOPLEFT", viewport, "TOPLEFT", 2, -34)
        mainFrame:SetPoint("BOTTOMRIGHT", native, "BOTTOMRIGHT", -12, 8)
    else
        -- Conservative fallback if Ebonhold changes its globals.
        mainFrame:SetPoint("TOPLEFT", native, "TOPLEFT", 18, -72)
        mainFrame:SetPoint("BOTTOMRIGHT", native, "BOTTOMRIGHT", -12, 8)
    end

    -- Match the native viewport's strata and sit only a few levels above it.
    -- We no longer need the old +100 hammer, which could cover sibling chrome
    -- such as the native close button if rectangles overlapped by a few pixels.
    local strataSource = viewport or native
    if strataSource.GetFrameStrata and mainFrame.SetFrameStrata then
        local ok, strata = pcall(strataSource.GetFrameStrata, strataSource)
        if ok and strata then pcall(mainFrame.SetFrameStrata, mainFrame, strata) end
    end
    if strataSource.GetFrameLevel and mainFrame.SetFrameLevel then
        local ok, level = pcall(strataSource.GetFrameLevel, strataSource)
        if ok and type(level) == "number" then mainFrame:SetFrameLevel(level + 5) end
    end
    return true
end

local function createUI()
    if mainFrame then return end

    mainFrame = CreateFrame("Frame", "EbonTreeMainFrame", UIParent)
    mainFrame:SetWidth(1180)
    mainFrame:SetHeight(720)
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    -- It is initially created under UIParent because Ebonhold lazily creates
    -- skillTreeFrame. dockToNativeTree() reparents it to skillTreeFrame before
    -- it is shown.
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:SetFrameLevel(80)
    mainFrame:SetClampedToScreen(false)
    mainFrame:SetMovable(false)
    mainFrame:EnableMouse(true)
    -- This is the replacement *content pane* inside Ebonhold's own window,
    -- not a replacement outer window. CollectionsJournal owns the real outer
    -- border/portrait/title chrome, so CleanTree must not draw a second border
    -- underneath that chrome.
    if mainFrame.SetBackdrop then
        -- The native CollectionsJournal owns the actual window/background.
        -- Keep CleanTree's root transparent so Ebonhold's brown parchment shows
        -- naturally between our panels instead of creating a black rectangle
        -- pasted into a brown window.
        mainFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            tile = true, tileSize = 16,
            insets = {left=0, right=0, top=0, bottom=0},
        })
        mainFrame:SetBackdropColor(0, 0, 0, 0)
    end

    mainFrame:Hide()

    local header = CreateFrame("Frame", nil, mainFrame)
    header:SetPoint("TOPLEFT", 12, -12)
    header:SetPoint("TOPRIGHT", -12, -12)
    header:SetHeight(72)
    setBackdrop(header, C.panel)
    header:EnableMouse(true)
    -- Do not make the inner skillTreeFrame movable. Moving it is what caused
    -- CleanTree + the stock progress/footer panel to detach from the outer
    -- Progression window. Window movement belongs exclusively to Ebonhold's
    -- native outer title bar.

    titleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", 16, -11)
    titleText:SetText("|cffffd200CleanTree|r  |cff888888v" .. VERSION .. "|r")

    soulAshText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    soulAshText:SetPoint("TOPRIGHT", -14, -12)
    soulAshText:SetJustifyH("RIGHT")

    scanText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scanText:SetPoint("BOTTOMLEFT", 16, 11)
    scanText:SetJustifyH("LEFT")

    refreshButton = makeButton(header, "Refresh", 82, 24)
    refreshButton:SetPoint("BOTTOMRIGHT", -8, 8)
    refreshButton:SetScript("OnClick", function()
        buildKnownNodes()
        ET._resolveActive = false
        ET.SetLoadingUI(true, "LOADING CLEANTREE...\nRefreshing native Skill Tree data")
        discoverRuntimeNodes()
        refreshHeader()
    end)

    ET.restoreNativeButton = makeButton(header, "Restore Native Skill Tree", 168, 24)
    ET.restoreNativeButton:SetPoint("RIGHT", refreshButton, "LEFT", -8, 0)
    ET.restoreNativeButton:SetScript("OnClick", function()
        ET.RestoreNativeSkillTree()
    end)

    ET.shoppingButton = makeButton(header, "Shopping Lists", 110, 24)
    ET.shoppingButton:SetPoint("RIGHT", ET.restoreNativeButton, "LEFT", -8, 0)
    ET.shoppingButton:SetScript("OnClick", function() ET.OpenShoppingLists() end)

    ET.buyableButton = makeButton(header, "Buyable Now", 104, 24)
    ET.buyableButton:SetPoint("RIGHT", ET.shoppingButton, "LEFT", -8, 0)
    -- Let the status line use all free header space up to the first action
    -- button. Short Shopping List status messages then stay clear of the title.
    scanText:SetPoint("BOTTOMRIGHT", ET.buyableButton, "BOTTOMLEFT", -12, 3)

    ET.buyableButton:SetScript("OnClick", function()
        selectedCategory = "BUYABLE"
        for _, tb in pairs(tabButtons) do tb:UnlockHighlight() end
        ET.buyableButton:LockHighlight()
        rebuildFiltered()
        resetScrollTop()
        refreshRows()
        local count = #filteredNodes
        if count == 1 then
            setStatus("Showing the 1 node you can afford and purchase right now.", 4)
        else
            setStatus("Showing " .. tostring(count) .. " nodes you can afford and purchase right now.", 4)
        end
    end)


    local tabs = CreateFrame("Frame", nil, mainFrame)
    tabs:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    tabs:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -8)
    tabs:SetHeight(38)
    setBackdrop(tabs, C.panel)

    local x = 10
    for _, key in ipairs(CATEGORY_ORDER) do
        -- Keep the category strip compact enough that the search field always
        -- gets its own space, even at smaller UI scales.
        local b = makeButton(tabs, CATEGORY_LABELS[key], 88, 24)
        b:SetPoint("LEFT", x, 0)
        x = x + 92
        b:SetScript("OnClick", function()
            selectedCategory = key
            if ET.buyableButton then ET.buyableButton:UnlockHighlight() end
            for k, tb in pairs(tabButtons) do
                if k == key then tb:LockHighlight() else tb:UnlockHighlight() end
            end
            rebuildFiltered()
            resetScrollTop()
            refreshRows()
        end)
        tabButtons[key] = b
    end
    tabButtons.UNOWNED:LockHighlight()

    local searchLabel = tabs:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    searchLabel:SetPoint("LEFT", tabButtons.PURCHASED, "RIGHT", 10, 0)
    searchLabel:SetText("Search:")

    searchBox = CreateFrame("EditBox", "EbonTreeSearchBox", tabs, "InputBoxTemplate")
    searchBox:SetHeight(24)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
    searchBox:SetPoint("RIGHT", -58, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        searchTerm = trim(self:GetText() or "")
        rebuildFiltered()
        if listScroll then FauxScrollFrame_SetOffset(listScroll, 0) end
        refreshRows()
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local clearSearch = makeButton(tabs, "x", 28, 22)
    clearSearch:SetPoint("RIGHT", -22, 0)
    clearSearch:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:ClearFocus()
    end)

    local left = CreateFrame("Frame", nil, mainFrame)
    left:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -8)
    left:SetPoint("BOTTOMLEFT", 12, 12)
    left:SetWidth(650)
    setBackdrop(left, C.panel)

    local listTitle = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listTitle:SetPoint("TOPLEFT", 14, -12)
    listTitle:SetText("Nodes")

    listScroll = CreateFrame("ScrollFrame", "EbonTreeNodeScroll", left, "FauxScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 4, -34)
    listScroll:SetPoint("BOTTOMRIGHT", -4, 8)
    listScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 54, refreshRows)
    end)
    if listScroll.EnableMouseWheel then listScroll:EnableMouseWheel(true) end
    listScroll:SetScript("OnMouseWheel", function(self, delta)
        local current = FauxScrollFrame_GetOffset(self) or 0
        local visible = math.max(1, math.min(#rows > 0 and #rows or 10, math.floor(((self:GetHeight() or 54) - 6) / 54)))
        local maxOffset = math.max(0, #filteredNodes - visible)
        local nextOffset = math.max(0, math.min(maxOffset, current - (delta * 3)))
        if type(FauxScrollFrame_SetOffset) == "function" then FauxScrollFrame_SetOffset(self, nextOffset) else self.offset = nextOffset end
        refreshRows()
    end)

    for i = 1, 10 do
        rows[i] = createRow(left, i)
        rows[i]:SetPoint("TOPLEFT", 8, -38 - ((i - 1) * 54))
        rows[i]:SetPoint("TOPRIGHT", -26, -38 - ((i - 1) * 54))
    end

    local right = CreateFrame("Frame", nil, mainFrame)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT", -12, 12)
    setBackdrop(right, C.panel)

    local detail = CreateFrame("Frame", nil, right)
    detail:SetPoint("TOPLEFT", 10, -10)
    detail:SetPoint("TOPRIGHT", -10, -10)
    detail:SetHeight(190)
    setBackdrop(detail, C.panel2)

    detailTitle = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    detailTitle:SetPoint("TOPLEFT", 14, -12)
    detailTitle:SetPoint("TOPRIGHT", -14, -12)
    detailTitle:SetJustifyH("LEFT")
    detailTitle:SetText("Select a node")

    detailBody = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detailBody:SetPoint("TOPLEFT", detailTitle, "BOTTOMLEFT", 0, -12)
    detailBody:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -14, 14)
    detailBody:SetJustifyH("LEFT")
    detailBody:SetJustifyV("TOP")
    detailBody:SetText("Choose a node on the left to inspect its live Ebonhold effect, rank, cost, and availability.")

    local pending = CreateFrame("Frame", nil, right)
    pending:SetPoint("TOPLEFT", detail, "BOTTOMLEFT", 0, -8)
    pending:SetPoint("BOTTOMRIGHT", -10, 80)
    setBackdrop(pending, C.panel2)

    local pendingTitle = pending:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pendingTitle:SetPoint("TOPLEFT", 14, -12)
    pendingTitle:SetText("Pending Changes")

    pendingText = pending:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pendingText:SetPoint("TOPLEFT", pendingTitle, "BOTTOMLEFT", 0, -8)
    pendingText:SetPoint("TOPRIGHT", pending, "TOPRIGHT", -14, -34)
    -- Reserve the lower 68 px exclusively for the spend summary. Anchoring
    -- the body to this boundary (instead of giving it a fixed height) keeps
    -- the two text blocks from ever occupying the same vertical space.
    pendingText:SetPoint("BOTTOMRIGHT", pending, "BOTTOMRIGHT", -14, 68)
    pendingText:SetJustifyH("LEFT")
    pendingText:SetJustifyV("TOP")

    pendingSpendText = pending:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pendingSpendText:SetPoint("BOTTOMLEFT", 14, 12)
    pendingSpendText:SetPoint("BOTTOMRIGHT", -14, 12)
    pendingSpendText:SetHeight(44)
    pendingSpendText:SetJustifyH("LEFT")
    pendingSpendText:SetJustifyV("BOTTOM")

    discardButton = makeButton(right, "Discard (/reload)", 130, 32)
    discardButton:SetPoint("BOTTOMLEFT", 12, 16)
    discardButton:SetScript("OnClick", discardByReload)

    applyButton = makeButton(right, "APPLY CHANGES", 150, 32)
    applyButton:SetPoint("BOTTOMRIGHT", -12, 16)
    applyButton:SetScript("OnClick", applyChanges)

    ET.loadingOverlay = CreateFrame("Frame", nil, mainFrame)
    ET.loadingOverlay:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    ET.loadingOverlay:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -12, 12)
    ET.loadingOverlay:SetFrameLevel(mainFrame:GetFrameLevel() + 50)
    ET.loadingOverlay:EnableMouse(true)
    setBackdrop(ET.loadingOverlay, {0.018, 0.018, 0.022, 1.0})
    ET.loadingText = ET.loadingOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ET.loadingText:SetPoint("CENTER", 0, 10)
    ET.loadingText:SetWidth(520)
    ET.loadingText:SetJustifyH("CENTER")
    ET.loadingText:SetText("LOADING CLEANTREE...")
    ET.loadingOverlay:Hide()

    mainFrame:SetScript("OnShow", function()
        dockToNativeTree()
        lastObservedAsh = readSoulAsh()
        installApplyHook()
        suppressNativeVisuals()
        if not (ET.IsInitialLoading and ET.IsInitialLoading()) then refreshRows() end
    end)
    mainFrame:SetScript("OnHide", function()
        ET.HideShoppingUI()
        restoreNativeVisuals()
    end)
end

local function showUI()
    createUI()
    -- An explicit CleanTree open (slash command, auto-open, or native restore
    -- button) leaves persistent native mode and hides its tiny return button.
    EbonTreeDB.nativeMode = false
    if ET.nativeRestoreButton then ET.nativeRestoreButton:Hide() end
    local native = _G.skillTreeCanvas or _G.skillTreeFrame
    if not native then
        chat("Open /progression and select the Skill Tree tab once, then run /cleantree again.")
        return
    end
    if native.IsShown then
        local ok, shown = pcall(native.IsShown, native)
        if ok and not shown then
            chat("Open /progression and select the Skill Tree tab once so Ebonhold can load its native node data.")
            return
        end
    end
    buildKnownNodes()
    nativeReadyAttempts = 0
    nativeReadyWait = false
    ET._resolveActive = false
    ET.SetLoadingUI(true, "LOADING CLEANTREE...\nWaiting for Ebonhold's Skill Tree data")
    discoverRuntimeNodes()
    dockToNativeTree()
    mainFrame:Show()
    suppressNativeVisuals()
    refreshHeader()
end

function ET.RestoreCleanTreeUI()
    EbonTreeDB.nativeMode = false
    if ET.nativeRestoreButton then ET.nativeRestoreButton:Hide() end
    showUI()
end

local function hideUIForNative()
    ET.RestoreNativeSkillTree()
end

local function hookNativeTree()
    if treeHooked then return true end
    -- Hook the actual Skill Tree canvas first. The outer progression shell can
    -- remain shown while the player switches to Echoes/Transmog/Mounts/etc.
    -- Canvas OnShow/OnHide therefore tracks the Skill Tree tab itself.
    local f = _G.skillTreeCanvas or _G.skillTreeBottomBar or _G.skillTreeFrame
    if not f then return false end
    nativeFrame = f
    if f.HookScript then
        f:HookScript("OnShow", function()
            if EbonTreeDB.nativeMode == true then
                ET.EnsureNativeRestoreButton()
            elseif EbonTreeDB.autoOpen ~= false then
                showUI()
            end
        end)
        f:HookScript("OnHide", function()
            if mainFrame then mainFrame:Hide() end
            restoreNativeVisuals()
        end)
        treeHooked = true
        if EbonTreeDB.nativeMode == true then ET.EnsureNativeRestoreButton() end
        -- Do not auto-open merely because the native Skill Tree happened to be
        -- visible when the addon loaded/reloaded.  Only a subsequent native
        -- OnShow (for example, the player selecting the Skill Tree tab) should
        -- trigger CleanTree automatically.  /cleantree can always open it
        -- explicitly.
        return true
    end
    return false
end

local function countBoundNodes()
    local n = 0
    for _, node in pairs(liveNodes) do
        if node.button then n = n + 1 end
    end
    return n
end

local function countRuntimeAndEndless()
    local runtimeOnly, endless, effects, endlessBound = 0, 0, 0, 0
    for _, n in pairs(liveNodes) do
        if n.isRuntimeOnly then runtimeOnly = runtimeOnly + 1 end
        if n.isEndless then
            endless = endless + 1
            if n.button then endlessBound = endlessBound + 1 end
        end
        if n.description and n.description ~= "" then effects = effects + 1 end
    end
    return runtimeOnly, endless, effects, endlessBound
end

local function unmatchedCandidateSummary(f)
    local typ = "?"
    if f and f.GetObjectType then local ok,v=pcall(f.GetObjectType,f); if ok and v then typ=v end end
    local id = extractNodeID(f)
    local w,h = 0,0
    if f and f.GetWidth then local ok,v=pcall(f.GetWidth,f); if ok and v then w=math.floor(v+0.5) end end
    if f and f.GetHeight then local ok,v=pcall(f.GetHeight,f); if ok and v then h=math.floor(v+0.5) end end
    local texts = {}
    collectFrameTexts(f, texts, {}, 2)
    local compact = table.concat(texts, " | ")
    if #compact > 90 then compact = string.sub(compact,1,87) .. "..." end
    return tostring(typ) .. " id=" .. tostring(id or "?") .. " size=" .. tostring(w) .. "x" .. tostring(h) .. " text=" .. tostring(compact ~= "" and compact or "<none>")
end

local function probe()
    local runtimeOnly, endless, effects, endlessBound = countRuntimeAndEndless()
    local frames = allTreeFrames()
    chat("Probe: catalog=" .. tostring(813) .. ", runtime-only=" .. runtimeOnly .. ", live buttons=" .. countBoundNodes() .. ", effects read=" .. effects .. ", Endless=" .. endless .. " (bound=" .. endlessBound .. ").")
    chat("Roots: frame=" .. tostring(_G.skillTreeFrame ~= nil) .. ", canvas=" .. tostring(_G.skillTreeCanvas ~= nil) .. ", bottomBar=" .. tostring(_G.skillTreeBottomBar ~= nil) .. ", walked frames=" .. tostring(#frames) .. ".")
    chat("Discovery: " .. (discoveryActive and "ACTIVE" or (nativeReadyWait and "WAITING" or "idle")) .. " " .. tostring(discoveryDone) .. "/" .. tostring(discoveryTotal) .. ", direct=" .. tostring(discoveryDirectMatches) .. ", tooltip=" .. tostring(discoveryTooltipMatches) .. ", nativeTips=" .. tostring(discoveryNativeTooltipReads) .. ", endlessSpellFallback=" .. tostring(discoverySpellFallbackMatches) .. ", nativeLoading=" .. tostring(nativeTreeLooksLoading()) .. ".")
    chat("Soul Ash=" .. tostring(readSoulAsh() or "unavailable") .. ", Apply button=" .. (findApplyButton() and "found" or "NOT found") .. ".")
    for _, n in pairs(liveNodes) do
        if n.isEndless then
            chat("Endless: " .. tostring(n.name) .. " rank=" .. nodeRankDisplay(n) .. " cost=" .. tostring(nodeCost(n) or "?") .. " nodeID=" .. tostring(n.id or "runtime"))
        end
    end
    if endlessBound < 3 then
        local shown = 0
        for _, f in ipairs(discoveryQueue or {}) do
            if not matchedDiscoveryFrames[f] then
                shown = shown + 1
                chat("Unmatched #" .. tostring(shown) .. ": " .. unmatchedCandidateSummary(f))
                if shown >= 12 then break end
            end
        end
    end
end

local function clearSlashEditBox()
    -- Custom 3.3.5 clients do not always dismiss the chat edit box after an
    -- addon slash command. Explicitly clear it after our handler returns.
    local eb = nil
    if type(ChatEdit_GetActiveWindow) == "function" then
        local ok, v = pcall(ChatEdit_GetActiveWindow)
        if ok then eb = v end
    end
    if not eb and SELECTED_CHAT_FRAME then eb = SELECTED_CHAT_FRAME.editBox end
    if eb then
        if eb.SetText then pcall(eb.SetText, eb, "") end
        if eb.ClearFocus then pcall(eb.ClearFocus, eb) end
        if eb.Hide then pcall(eb.Hide, eb) end
    end
end

local function frameProbe()
    local function nm(f)
        if not f then return "nil" end
        local n = nil
        if f.GetName then local ok,v = pcall(f.GetName,f); if ok then n=v end end
        return tostring(n or f)
    end
    local f = _G.skillTreeFrame
    chat("FrameProbe: skillTreeFrame=" .. nm(f) .. ", scroll=" .. nm(_G.skillTreeScroll) .. ", canvas=" .. nm(_G.skillTreeCanvas) .. ", bottomBar=" .. nm(_G.skillTreeBottomBar))
    local cur = f
    for i=1,5 do
        if not cur or not cur.GetParent then break end
        local ok,p = pcall(cur.GetParent,cur)
        if not ok or not p then break end
        chat("FrameProbe parent " .. tostring(i) .. ": " .. nm(p))
        cur = p
    end
end


function ET.FrameDebugName(f)
    if not f then return "nil" end
    if f.GetName then
        local ok, v = pcall(f.GetName, f)
        if ok and v and v ~= "" then return tostring(v) end
    end
    return tostring(f)
end

function ET.IsInterestingGraphKey(k)
    local s = lower(tostring(k or ""))
    return string.find(s, "req", 1, true)
        or string.find(s, "pre", 1, true)
        or string.find(s, "depend", 1, true)
        or string.find(s, "parent", 1, true)
        or string.find(s, "child", 1, true)
        or string.find(s, "link", 1, true)
        or string.find(s, "connect", 1, true)
        or string.find(s, "next", 1, true)
        or string.find(s, "prev", 1, true)
        or string.find(s, "node", 1, true)
        or string.find(s, "spell", 1, true)
        or string.find(s, "rank", 1, true)
        or s == "id" or s == "data" or s == "raw"
end

function ET.DumpGraphFields(t, label, depth, seen, budget)
    if not t or type(t) ~= "table" then return budget end
    depth = tonumber(depth) or 0
    budget = tonumber(budget) or 24
    if depth > 2 or budget <= 0 then return budget end
    seen = seen or {}
    if seen[t] then return budget end
    seen[t] = true

    local keys = {}
    local ok = pcall(function()
        for k, _ in pairs(t) do keys[#keys + 1] = k end
    end)
    if not ok then return budget end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)

    for _, k in ipairs(keys) do
        if budget <= 0 then break end
        if ET.IsInterestingGraphKey(k) then
            local vok, v = pcall(function() return t[k] end)
            if vok then
                local vt = type(v)
                if vt == "number" or vt == "string" or vt == "boolean" then
                    chat("NodeProbe " .. tostring(label) .. "." .. tostring(k) .. " = " .. tostring(v))
                    budget = budget - 1
                elseif vt == "table" then
                    chat("NodeProbe " .. tostring(label) .. "." .. tostring(k) .. " = <table>")
                    budget = budget - 1
                    budget = ET.DumpGraphFields(v, tostring(label) .. "." .. tostring(k), depth + 1, seen, budget)
                end
            end
        end
    end
    return budget
end

function ET.NodeProbe(query)
    query = compactSpace(query or "")
    local q = lower(query)
    if q == "" then
        chat("Usage: /cleantree nodeprobe <node name>")
        return
    end
    if not next(liveNodes) then
        chat("NodeProbe: CleanTree has no live node catalog yet. Open the Skill Tree and wait for loading to finish.")
        return
    end

    local matches = {}
    for _, node in pairs(liveNodes) do
        local nn = lower(node.name or "")
        if nn == q then
            table.insert(matches, 1, node)
        elseif string.find(nn, q, 1, true) then
            matches[#matches + 1] = node
        end
    end
    if #matches == 0 then
        chat("NodeProbe: no node matched '" .. query .. "'.")
        return
    end

    chat("NodeProbe: " .. tostring(#matches) .. " match(es) for '" .. query .. "'. Showing up to 3.")
    for i = 1, math.min(3, #matches) do
        local node = matches[i]
        local b = node.button
        local x, y = ET.TreeFrameCenter(b)
        local bid = nil
        if b and b.GetID then local ok,v = pcall(b.GetID,b); if ok then bid=v end end
        chat("NodeProbe #" .. tostring(i) .. ": " .. tostring(node.name or node.key)
            .. " key=" .. tostring(node.key) .. " staticID=" .. tostring(node.id or "?")
            .. " frame=" .. ET.FrameDebugName(b) .. " frameID=" .. tostring(bid or "?")
            .. " @ " .. tostring(x and math.floor(x+0.5) or "?") .. "," .. tostring(y and math.floor(y+0.5) or "?"))
        if b then
            ET.DumpGraphFields(b, "button", 0, {}, 28)
            if b.GetParent then
                local ok,p = pcall(b.GetParent,b)
                if ok and p then
                    chat("NodeProbe parent=" .. ET.FrameDebugName(p))
                    ET.DumpGraphFields(p, "parent", 0, {}, 18)
                end
            end
        else
            chat("NodeProbe: this node has no bound native button.")
        end
    end
end


-- Diagnostic graph probing for Project Ebonhold's native Skill Tree.
-- Node buttons expose very little relationship metadata directly, so this
-- probe inspects the rank/spell table, click-handler upvalues, canvas regions,
-- nearby non-node children, and likely global graph objects. It is diagnostic
-- only; it does not change CleanTree's ordering or purchase behavior.
function ET.DumpRawProbeTable(t, label, depth, seen, budget)
    if type(t) ~= "table" then return budget end
    depth = tonumber(depth) or 0
    budget = tonumber(budget) or 40
    if depth > 3 or budget <= 0 then return budget end
    seen = seen or {}
    if seen[t] then return budget end
    seen[t] = true

    local keys = {}
    local ok = pcall(function() for k, _ in pairs(t) do keys[#keys + 1] = k end end)
    if not ok then return budget end
    table.sort(keys, function(a,b)
        local ta, tb = type(a), type(b)
        if ta == tb and ta == "number" then return a < b end
        return tostring(a) < tostring(b)
    end)

    for _, k in ipairs(keys) do
        if budget <= 0 then break end
        local vok, v = pcall(function() return t[k] end)
        if vok then
            local vt = type(v)
            local path = tostring(label) .. "[" .. tostring(k) .. "]"
            if vt == "number" or vt == "string" or vt == "boolean" or vt == "nil" then
                chat("GraphProbe " .. path .. " = " .. tostring(v))
                budget = budget - 1
            elseif vt == "table" then
                chat("GraphProbe " .. path .. " = <table>")
                budget = budget - 1
                budget = ET.DumpRawProbeTable(v, path, depth + 1, seen, budget)
            elseif vt == "function" then
                chat("GraphProbe " .. path .. " = <function>")
                budget = budget - 1
            elseif vt == "userdata" then
                chat("GraphProbe " .. path .. " = <userdata>")
                budget = budget - 1
            end
        end
    end
    return budget
end

function ET.DumpScriptProbe(frame, label)
    if not frame or not frame.GetScript then return end
    for _, eventName in ipairs({"OnClick", "OnMouseUp", "OnMouseDown", "OnEnter", "OnLeave"}) do
        local ok, fn = pcall(frame.GetScript, frame, eventName)
        if ok and type(fn) == "function" then
            chat("GraphProbe " .. tostring(label) .. "." .. eventName .. " = <function>")
            if type(debug) == "table" and type(debug.getupvalue) == "function" then
                for i = 1, 16 do
                    local uok, uname, uval = pcall(debug.getupvalue, fn, i)
                    if not uok or not uname then break end
                    local t = type(uval)
                    if t == "number" or t == "string" or t == "boolean" then
                        chat("GraphProbe   upvalue " .. tostring(i) .. " " .. tostring(uname) .. " = " .. tostring(uval))
                    elseif t == "table" then
                        chat("GraphProbe   upvalue " .. tostring(i) .. " " .. tostring(uname) .. " = <table>")
                        ET.DumpRawProbeTable(uval, "upvalue." .. tostring(uname), 0, {}, 12)
                    else
                        chat("GraphProbe   upvalue " .. tostring(i) .. " " .. tostring(uname) .. " = <" .. tostring(t) .. ">")
                    end
                end
            else
                chat("GraphProbe   debug.getupvalue unavailable on this client")
            end
        end
    end
end

function ET.ProbeCanvasLinks(button)
    local canvas = _G.skillTreeCanvas
    if not canvas then
        chat("GraphProbe: skillTreeCanvas is unavailable.")
        return
    end
    local bx, by = ET.TreeFrameCenter(button)
    local anchored, nearby = 0, 0

    if canvas.GetRegions then
        local regions = {canvas:GetRegions()}
        chat("GraphProbe: canvas regions=" .. tostring(#regions))
        for idx, r in ipairs(regions) do
            local report = false
            local direct = false
            if r and r.GetNumPoints and r.GetPoint then
                local pok, npts = pcall(r.GetNumPoints, r)
                npts = pok and tonumber(npts) or 0
                for pi = 1, math.min(npts or 0, 4) do
                    local ok, point, rel, relPoint, ox, oy = pcall(r.GetPoint, r, pi)
                    if ok and rel == button then direct = true end
                end
            end
            if direct then
                anchored = anchored + 1
                report = true
            elseif bx and by and r and r.GetCenter then
                local ok, rx, ry = pcall(r.GetCenter, r)
                if ok and type(rx)=="number" and type(ry)=="number" then
                    local dx, dy = rx-bx, ry-by
                    if (dx*dx + dy*dy) <= (160*160) then
                        nearby = nearby + 1
                        if nearby <= 16 then report = true end
                    end
                end
            end
            if report then
                local typ = r.GetObjectType and r:GetObjectType() or type(r)
                local w = r.GetWidth and r:GetWidth() or 0
                local h = r.GetHeight and r:GetHeight() or 0
                local texture = nil
                if r.GetTexture then local ok,v=pcall(r.GetTexture,r); if ok then texture=v end end
                chat("GraphProbe region#" .. tostring(idx) .. " type=" .. tostring(typ) .. " size=" .. tostring(math.floor((w or 0)+0.5)) .. "x" .. tostring(math.floor((h or 0)+0.5)) .. " tex=" .. tostring(texture or "?"))
                if r.GetNumPoints and r.GetPoint then
                    local pok, npts = pcall(r.GetNumPoints, r)
                    npts = pok and tonumber(npts) or 0
                    for pi = 1, math.min(npts or 0, 4) do
                        local ok, point, rel, relPoint, ox, oy = pcall(r.GetPoint, r, pi)
                        if ok then
                            chat("GraphProbe   p" .. tostring(pi) .. " " .. tostring(point) .. " -> " .. ET.FrameDebugName(rel) .. "." .. tostring(relPoint) .. " " .. tostring(ox or 0) .. "," .. tostring(oy or 0))
                        end
                    end
                end
            end
        end
    end
    chat("GraphProbe: regions directly anchored to node=" .. tostring(anchored) .. ", nearby reported=" .. tostring(math.min(nearby,16)))

    if canvas.GetChildren and bx and by then
        local children = {canvas:GetChildren()}
        local count = 0
        for _, child in ipairs(children) do
            if child ~= button then
                local name = ET.FrameDebugName(child)
                if not string.match(tostring(name), "^skillTreeNode%d+$") then
                    local cx, cy = ET.TreeFrameCenter(child)
                    if cx and cy then
                        local dx, dy = cx-bx, cy-by
                        if (dx*dx + dy*dy) <= (180*180) then
                            count = count + 1
                            if count <= 16 then
                                local typ = child.GetObjectType and child:GetObjectType() or type(child)
                                chat("GraphProbe child near node: " .. tostring(name) .. " type=" .. tostring(typ) .. " @ " .. tostring(math.floor(cx+0.5)) .. "," .. tostring(math.floor(cy+0.5)))
                                ET.DumpGraphFields(child, "child", 0, {}, 8)
                            end
                        end
                    end
                end
            end
        end
        chat("GraphProbe: nearby non-node canvas children=" .. tostring(count))
    end
end

function ET.ProbeSkillTreeGlobals()
    local names = {}
    for k, v in pairs(_G) do
        if type(k) == "string" then
            local lk = lower(k)
            local skill = string.find(lk, "skilltree", 1, true)
            local graph = string.find(lk, "prereq", 1, true) or string.find(lk, "require", 1, true) or string.find(lk, "connect", 1, true) or string.find(lk, "link", 1, true) or string.find(lk, "edge", 1, true) or string.find(lk, "line", 1, true)
            if skill and (graph or not string.match(k, "^skillTreeNode%d+$")) then names[#names + 1] = k end
        end
    end
    table.sort(names)
    chat("GraphProbe: interesting skill-tree globals=" .. tostring(#names) .. " (showing up to 50)")
    for i = 1, math.min(#names, 50) do
        local k = names[i]
        local v = _G[k]
        chat("GraphProbe global " .. tostring(k) .. " = <" .. tostring(type(v)) .. ">")
        if type(v) == "table" and not (v.GetObjectType and v:GetObjectType()) then
            ET.DumpGraphFields(v, "global." .. tostring(k), 0, {}, 6)
        end
    end
end

function ET.GraphProbe(query)
    query = compactSpace(query or "")
    local q = lower(query)
    if q == "" then
        chat("Usage: /cleantree graphprobe <node name>")
        return
    end
    local matches = {}
    for _, node in pairs(liveNodes) do
        local nn = lower(node.name or "")
        if nn == q then table.insert(matches, 1, node) elseif string.find(nn, q, 1, true) then matches[#matches + 1] = node end
    end
    if #matches == 0 then
        chat("GraphProbe: no node matched '" .. query .. "'.")
        return
    end
    local node = matches[1]
    local button = node.button
    chat("GraphProbe: " .. tostring(node.name) .. " key=" .. tostring(node.key) .. " staticID=" .. tostring(node.id or "?") .. " frame=" .. ET.FrameDebugName(button))
    if not button then
        chat("GraphProbe: node is not bound to a native button.")
        return
    end
    if type(button.spells) == "table" then
        chat("GraphProbe: dumping button.spells")
        ET.DumpRawProbeTable(button.spells, "button.spells", 0, {}, 48)
    else
        chat("GraphProbe: button.spells is " .. tostring(type(button.spells)))
    end
    ET.DumpScriptProbe(button, "button")
    ET.ProbeCanvasLinks(button)
    ET.ProbeSkillTreeGlobals()
end

function ET.OrderProbe()
    if not ET.treeOrderReady then
        chat("Tree order is not ready yet; wait for CleanTree to finish loading.")
        return
    end
    local graph = EbonTreeOrderData or {}
    chat("TreeOrder source: " .. tostring(graph.source or "unknown") ..
        " | finite=" .. tostring(graph.finiteNodeCount or "?") ..
        " links=" .. tostring(graph.validLinkCount or graph.linkCount or "?"))
    chat("TreeOrder mode: " .. tostring(graph.sortMode or "topological"))
    for _, category in ipairs({"DAMAGE", "SURVIVAL", "CONVENIENCE"}) do
        local r = ET.treeOrderRoots[category]
        chat("TreeOrder root " .. category .. ": " .. tostring(r and r.node and r.node.name or "unresolved") ..
            " [id=" .. tostring(r and r.id or "?") .. "]")
    end
    local ordered = {}
    for _, node in pairs(liveNodes) do ordered[#ordered + 1] = node end
    table.sort(ordered, function(a, b)
        return (tonumber(a._treeOrderIndex) or 2147483647) < (tonumber(b._treeOrderIndex) or 2147483647)
    end)
    for i = 1, math.min(24, #ordered) do
        local node = ordered[i]
        chat("TreeOrder " .. tostring(i) .. ": [" .. tostring(node.category or "OTHER") ..
            " depth=" .. tostring(node._treeDepth or "-") ..
            " id=" .. tostring(node.id or "-") .. "] " .. tostring(node.name or node.key))
    end
end

function ET.APIProbe()
    local bridge = _G.CleanTreeEbonAPI
    if not bridge then
        chat("EbonAPI bridge is not loaded.")
        return
    end
    local status = bridge.GetStatus and bridge.GetStatus() or {}
    chat("EbonAPI ready=" .. tostring(status.ready) ..
        " TalentDatabase=" .. tostring(status.talentDatabase) ..
        " nodes=" .. tostring(status.nodes or 0) ..
        " links=" .. tostring(bridge.linkCount or 0))
    chat("EbonAPI SkillTree=" .. tostring(status.skillTree) ..
        " SkillTreeFrame=" .. tostring(status.skillTreeFrame) ..
        " RequestLoadout=" .. tostring(status.requestLoadout))
    chat("EbonAPI Soul Ash=" .. tostring(status.ash or "unavailable") ..
        " source=" .. tostring(status.ashSource or "?") ..
        " serverLoadout=" .. tostring(status.serverLoadout))
    for _, id in ipairs({2000, 2001, 2002}) do
        local def = bridge.GetNodeDef and bridge.GetNodeDef(id) or nil
        local rank = bridge.GetCurrentRank and bridge.GetCurrentRank(id) or nil
        local committed = bridge.GetServerRank and bridge.GetServerRank(id) or nil
        local cost = bridge.GetNextCost and bridge.GetNextCost(id, rank or committed or 0) or nil
        chat("EbonAPI Endless id=" .. tostring(id) ..
            " def=" .. tostring(def ~= nil) ..
            " rank=" .. tostring(rank or "?") ..
            " committed=" .. tostring(committed or "?") ..
            " nextCost=" .. tostring(cost or "?"))
    end
end

function ET.ShoppingProbe()
    local function frameInfo(label, frame)
        if not frame then chat(label .. " = nil"); return end
        local name = frame.GetName and frame:GetName() or "<unnamed>"
        local objectType = frame.GetObjectType and frame:GetObjectType() or "?"
        local strata = frame.GetFrameStrata and frame:GetFrameStrata() or "?"
        local level = frame.GetFrameLevel and frame:GetFrameLevel() or "?"
        local parent = frame.GetParent and frame:GetParent() or nil
        local parentName = parent and parent.GetName and parent:GetName() or tostring(parent)
        chat(label .. " name=" .. tostring(name) .. " type=" .. tostring(objectType) .. " strata=" .. tostring(strata) .. " level=" .. tostring(level) .. " parent=" .. tostring(parentName))
    end
    frameInfo("Shopping", ET.shoppingFrame)
    frameInfo("Transfer", ET.shoppingTransferFrame)
    if type(GetMouseFocus) == "function" then
        local ok, focus = pcall(GetMouseFocus)
        if ok then frameInfo("MouseFocus", focus) else chat("MouseFocus probe failed: " .. tostring(focus)) end
    else
        chat("GetMouseFocus is unavailable on this client.")
    end
end

local function slash(msg)
    local raw = trim(msg or "")
    local cmd, arg = string.match(raw, "^(%S+)%s*(.-)$")
    cmd = lower(cmd or "")

    local ok, err = pcall(function()
        if cmd == "" or cmd == "show" then
            showUI()
        elseif cmd == "hide" or cmd == "native" then
            hideUIForNative()
        elseif cmd == "refresh" or cmd == "rescan" then
            if not next(liveNodes) then buildKnownNodes() end
            nativeReadyAttempts = 0
            nativeReadyWait = false
            discoverRuntimeNodes()
            rebuildFiltered()
            if mainFrame and mainFrame:IsShown() then refreshRows() end
            setStatus("Native binding scan restarted.", 3)
        elseif cmd == "frameprobe" or cmd == "frames" then
            frameProbe()
        elseif cmd == "orderprobe" or cmd == "treeorder" then
            ET.OrderProbe()
        elseif cmd == "nodeprobe" or cmd == "nprobe" then
            ET.NodeProbe(arg)
        elseif cmd == "graphprobe" or cmd == "gprobe" then
            ET.GraphProbe(arg)
        elseif cmd == "apiprobe" or cmd == "api" then
            ET.APIProbe()
        elseif cmd == "probe" then
            if not next(liveNodes) then buildKnownNodes() end
            if not discoveryActive and not nativeReadyWait and countBoundNodes() == 0 then
                nativeReadyAttempts = 0
                discoverRuntimeNodes()
            end
            probe()
        elseif cmd == "shopping" or cmd == "shop" or cmd == "lists" then
            ET.OpenShoppingLists()
        elseif cmd == "shoppingprobe" or cmd == "shopprobe" then
            ET.ShoppingProbe()
        elseif cmd == "shopauto" then
            ET.StartShoppingAuto(ET.shoppingSelectedName or EbonTreeDB.activeShoppingList)
        elseif cmd == "shopstop" then
            ET.StopShoppingAuto("Shopping List auto-purchase stopped by user.")
        elseif cmd == "shopimport" and arg ~= "" then
            local name, importErr = ET.ImportShoppingList(arg)
            if name then chat("Imported Shopping List '" .. tostring(name) .. "'.") else chat(importErr or "Import failed.") end
        elseif cmd == "shopexport" then
            local payload = ET.ExportShoppingList(ET.shoppingSelectedName or EbonTreeDB.activeShoppingList)
            if payload then chat("Open Shopping Lists -> Export to copy the full string. Length=" .. tostring(string.len(payload))) end
        elseif cmd == "auto" then
            EbonTreeDB.autoOpen = not (EbonTreeDB.autoOpen ~= false)
            chat("Auto-open is now " .. (EbonTreeDB.autoOpen ~= false and "ON" or "OFF") .. ".")
        elseif cmd == "apply" then
            applyChanges()
        else
            chat("Commands: /cleantree, show, native, refresh, shopping, shoppingprobe, shopauto, shopstop, probe, apiprobe, frameprobe, orderprobe, nodeprobe <name>, graphprobe <name>, auto, apply")
        end
    end)

    clearSlashEditBox()
    if not ok then
        chat("Command error: " .. tostring(err))
    end
end

SLASH_EBONTREE1 = "/cleantree"
SLASH_EBONTREE2 = "/ctree"
SLASH_EBONTREE3 = "/ebontree"
SLASH_EBONTREE4 = "/etree"
SlashCmdList["EBONTREE"] = slash

ET:RegisterEvent("ADDON_LOADED")
ET:RegisterEvent("PLAYER_LOGIN")
ET:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "CleanTree" or arg1 == "EbonTree" then
            if type(EbonTreeDB) ~= "table" then EbonTreeDB = {} end
            if EbonTreeDB.autoOpen == nil then EbonTreeDB.autoOpen = true end
            if EbonTreeDB.nativeMode == nil then EbonTreeDB.nativeMode = false end
            ET.EnsureShoppingLists()
            createUI()
            installTooltipHook()
        end
    elseif event == "PLAYER_LOGIN" then
        installTooltipHook()
        hookNativeTree()
        installApplyHook()
    end
end)

ET:SetScript("OnUpdate", function(self, elapsed)
    -- Some 3.3.5 custom clients do not fire GameTooltip:HookScript for Ebonhold's
    -- custom node tooltip. While EbonTree is hidden, poll the visible native
    -- tooltip so hovering an Endless node once can bind its real frame/rank/cost.
    tooltipPollAccumulator = tooltipPollAccumulator + elapsed
    if tooltipPollAccumulator >= 0.05 then
        tooltipPollAccumulator = 0
        if (not mainFrame or not mainFrame:IsShown()) and GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() then
            captureEndlessFromVisibleTooltip()
        end
    end

    -- Ebonhold may create the Skill Tree lazily after login.
    if not treeHooked then hookNativeTree() end
    if not applyHooked then installApplyHook() end

    if ET.shoppingRun and ET.shoppingRun.active and not pendingClick then
        if (ET._shoppingResumeDelay or 0) > 0 then
            ET._shoppingResumeDelay = math.max(0, (ET._shoppingResumeDelay or 0) - elapsed)
        else
            ET.ContinueShoppingAuto()
        end
    end

    -- In persistent native mode, Ebonhold can lazily recreate/reparent its tree
    -- widgets. Re-anchor the tiny return button occasionally so there is always
    -- a one-click path back to CleanTree.
    ET._nativeModeButtonAccumulator = (ET._nativeModeButtonAccumulator or 0) + elapsed
    if ET._nativeModeButtonAccumulator >= 0.50 then
        ET._nativeModeButtonAccumulator = 0
        if EbonTreeDB.nativeMode == true then
            ET.EnsureNativeRestoreButton()
        elseif ET.nativeRestoreButton then
            ET.nativeRestoreButton:Hide()
        end
    end

    -- Ebonhold occasionally refreshes the native footer/scroll widgets after our
    -- OnShow suppression (for example after returning to the game or applying a
    -- node). Reassert only the two known native content parents; parent alpha 0
    -- keeps Soul Ash / Apply / Search and the stock node canvas invisible without
    -- touching CollectionsJournal's title, portrait, close button, or tabs.
    ET._nativeHideAccumulator = (ET._nativeHideAccumulator or 0) + elapsed
    if mainFrame and mainFrame:IsShown() and ET._nativeHideAccumulator >= 0.20 then
        ET._nativeHideAccumulator = 0
        local nativeScroll = _G.skillTreeScroll
        local nativeCanvas = _G.skillTreeCanvas
        local nativeBottom = _G.skillTreeBottomBar
        if nativeScroll and nativeScroll.SetAlpha then
            rememberNativeVisual(nativeScroll)
            pcall(nativeScroll.SetAlpha, nativeScroll, 0)
        elseif nativeCanvas and nativeCanvas.SetAlpha then
            rememberNativeVisual(nativeCanvas)
            pcall(nativeCanvas.SetAlpha, nativeCanvas, 0)
        end
        if nativeBottom and nativeBottom.SetAlpha then
            -- Track replacement footers before hiding them so Restore Native
            -- can always recover Soul Ash, Apply Changes, and Search.
            rememberNativeVisual(nativeBottom)
            pcall(nativeBottom.SetAlpha, nativeBottom, 0)
        end
    end

    -- Lazy ownership can become authoritative only after a visible row binds to
    -- its native widget.  Rebuild on the next tick so Unowned/branch tabs never
    -- keep PURCHASED/MAXED rows merely because they were provisional at filter time.
    if ET._ownershipRefilterPending and mainFrame and mainFrame:IsShown() and not pendingClick and not (ET.IsInitialLoading and ET.IsInitialLoading()) then
        ET._ownershipRefilterPending = nil
        refreshRows()
    end

    -- Hotfix34: self-heal the first-render blank-list race. The initial
    -- ownership/effect passes can shrink the filtered list after FauxScrollFrame
    -- has already retained an older offset, or finish one frame before the row
    -- pool is ready to repaint. If CleanTree says it has nodes but not one row is
    -- actually visible, automatically do the same reset/rebuild that clicking a
    -- category tab used to provide manually.
    if mainFrame and mainFrame:IsShown()
        and not pendingClick
        and not discoveryActive
        and not ET._resolveActive
        and not (ET.IsInitialLoading and ET.IsInitialLoading())
        and #filteredNodes > 0
        and not hasVisibleNodeRow()
    then
        ET._blankListRepairAccumulator = (ET._blankListRepairAccumulator or 0) + elapsed
        if ET._blankListRepairAccumulator >= 0.08 then
            ET._blankListRepairAccumulator = 0
            rebuildFiltered()
            resetScrollTop()
            refreshRows()
        end
    else
        ET._blankListRepairAccumulator = 0
    end

    -- Wait for Ebonhold's lazy /progression -> Skill Tree load to complete.
    -- Retry only a handful of times so a binding mismatch cannot become a
    -- permanent background rescan loop.
    if nativeReadyWait and not discoveryActive then
        nativeReadyAccumulator = nativeReadyAccumulator + elapsed
        if nativeReadyAccumulator >= 0.50 then
            nativeReadyAccumulator = 0
            nativeReadyAttempts = nativeReadyAttempts + 1
            if nativeReadyAttempts <= 12 then
                discoverRuntimeNodes()
            else
                nativeReadyWait = false
                ET.SetLoadingUI(true, "CLEANTREE COULD NOT FINISH LOADING\nClick Refresh after Ebonhold's Skill Tree has fully loaded.")
                setStatus("Native Skill Tree never became bindable. Run /cleantree refresh after the tree is fully loaded.", 8)
            end
        end
    end

    -- Incremental native-frame discovery. Finite direct matches no longer read
    -- tooltips, so we can process a healthy batch per tick without freezing the
    -- client. This cuts the normal 813-node bind from many seconds to roughly a
    -- second while keeping the few unmatched/special widgets incremental.
    if discoveryActive then
        discoveryAccumulator = discoveryAccumulator + elapsed
        if discoveryAccumulator >= 0.01 then
            discoveryAccumulator = 0
            local processed = 0
            while discoveryIndex <= #discoveryQueue and processed < 20 do
                local f = discoveryQueue[discoveryIndex]
                discoveryIndex = discoveryIndex + 1
                processDiscoveryFrame(f)
                discoveryDone = discoveryDone + 1
                processed = processed + 1
            end

            if discoveryIndex > #discoveryQueue then
                discoveryActive = false
                for _, node in pairs(liveNodes) do syncNodeOwnership(node) end
                local bound = countBoundNodes()
                -- Ebonhold builds the canvas in waves. A partial pass can expose
                -- only ~200-300 of the 813 finite nodes. Waiting briefly for the
                -- native tree to finish is far cheaper than brute-force searching
                -- every missing catalog node across ~1,600 frames.
                local minReady = 700
                if bound < minReady and nativeReadyAttempts < 12 then
                    nativeReadyWait = true
                    nativeReadyAccumulator = 0
                    ET.SetLoadingUI(true, "LOADING CLEANTREE...\nWaiting for native Skill Tree " .. tostring(bound) .. "/" .. tostring(minReady) .. "+ nodes")
                    setStatus("Native Skill Tree is still populating (" .. tostring(bound) .. " nodes bound); waiting...", 2)
                elseif bound == 0 and nativeReadyAttempts < 16 then
                    nativeReadyWait = true
                    nativeReadyAccumulator = 0
                    ET.SetLoadingUI(true, "LOADING CLEANTREE...\nWaiting for native Skill Tree nodes")
                else
                    nativeReadyWait = false
                    if bound >= minReady then nativeReadyAttempts = 0 end
                    ET.StartResolvePass()
                end
            elseif mainFrame and mainFrame:IsShown() then
                if ET.loadingText then ET.loadingText:SetText("LOADING CLEANTREE...\nBinding native tree " .. tostring(discoveryDone) .. "/" .. tostring(discoveryTotal)) end
                refreshHeader()
            end
        end
    end

    -- Resolve ownership before exposing the list so Unowned/Purchased ordering
    -- is stable. This phase deliberately does *not* read 813 spell tooltips and
    -- does not brute-force missing frame bindings; both were the source of the
    -- very slow Hotfix22 load. Effects can populate afterward without changing
    -- category membership or ordering.
    if ET._resolveActive and not discoveryActive then
        ET._resolveAccumulator = (ET._resolveAccumulator or 0) + elapsed
        if ET._resolveAccumulator >= 0.01 then
            ET._resolveAccumulator = 0
            local processed = 0
            while ET._resolveIndex <= #(ET._resolveQueue or {}) and processed < 40 do
                local resolvingNode = ET._resolveQueue[ET._resolveIndex]
                ET._resolveIndex = ET._resolveIndex + 1
                if resolvingNode then syncNodeOwnership(resolvingNode) end
                ET._resolveDone = (ET._resolveDone or 0) + 1
                processed = processed + 1
            end
            if ET.loadingText then
                ET.loadingText:SetText("LOADING CLEANTREE...\nResolving ownership " .. tostring(ET._resolveDone or 0) .. "/" .. tostring(ET._resolveTotal or 0))
            end
            if ET._resolveIndex > #(ET._resolveQueue or {}) then
                ET._resolveActive = false
                ET.FinishInitialLoad()
                startBackgroundScan()
                setStatus("CleanTree ready; node effects are filling in quietly in the background.", 3)
            end
        end
    end

    if pendingClick then
        pendingClick.elapsed = pendingClick.elapsed + elapsed
        local after = readSoulAsh()
        if pendingClick.mode == "remove" then
            if after and pendingClick.beforeAsh and after > pendingClick.beforeAsh then
                ET.FinishPendingRemoval(after)
            elseif after and pendingClick.beforeAsh and after < pendingClick.beforeAsh then
                pendingClick = nil
                setStatus("Soul Ash decreased while removing a cart item; removal was not tracked.", 6)
                refreshRows()
            elseif pendingClick.elapsed > 0.90 then
                local nextIndex = (pendingClick.removalCandidateIndex or 1) + 1
                local candidates = pendingClick.removalCandidates or {}
                if candidates[nextIndex] then
                    local ok, why = clickFrame(candidates[nextIndex], "RightButton")
                    if ok then
                        pendingClick.removalCandidateIndex = nextIndex
                        pendingClick.elapsed = 0
                        setStatus("Trying the native node's right-click handler...", 2)
                    else
                        pendingClick.removalCandidateIndex = nextIndex
                        pendingClick.elapsed = 0
                        setStatus("Trying alternate native right-click target (" .. tostring(why) .. ")...", 2)
                    end
                else
                    local node = pendingClick.node
                    pendingClick = nil
                    setStatus("Ebonhold did not remove that staged rank. A dependent staged node may need to be removed first.", 6)
                    refreshRows()
                    if node then refreshDetail(node) end
                end
            end
        elseif after and pendingClick.beforeAsh and after < pendingClick.beforeAsh then
            finishPendingClick(after)
        elseif after and pendingClick.beforeAsh and after > pendingClick.beforeAsh then
            local wasShoppingAuto = pendingClick.shoppingAuto
            pendingClick = nil
            if wasShoppingAuto then ET.StopShoppingAuto("Soul Ash increased unexpectedly; Shopping List auto-purchase stopped.")
            else setStatus("Soul Ash increased unexpectedly; purchase was not tracked.", 6) end
            refreshRows()
        elseif pendingClick.elapsed > 0.90 then
            local rejectedNode = pendingClick.node
            local wasShoppingAuto = pendingClick.shoppingAuto
            pendingClick = nil
            if rejectedNode then
                -- Ebonhold is authoritative. A click with no Soul Ash decrease
                -- is concrete evidence that the node cannot currently be learned.
                rejectedNode.nativeRejected = true
                rejectedNode.nativeCanLearn = false
            end
            setStatus("Ebonhold rejected that purchase; marked NOT AVAILABLE until prerequisites change or you Refresh.", 6)
            clearTreeCaches()
            refreshRows()
            if rejectedNode then refreshDetail(rejectedNode) end
            if wasShoppingAuto and ET.shoppingRun and ET.shoppingRun.active then ET._shoppingResumeDelay = 0.08 end
        end
    end

    -- Background effect scan: small batches avoid freezing the 3.3.5 client.
    if scanActive and not discoveryActive and mainFrame and mainFrame:IsShown() then
        scanAccumulator = scanAccumulator + elapsed
        if scanAccumulator >= 0.03 then
            scanAccumulator = 0
            local processed = 0
            while scanIndex <= #scanQueue and processed < 5 do
                local node = scanQueue[scanIndex]
                scanIndex = scanIndex + 1
                syncNodeOwnership(node)
                updateNodeFromTooltip(node, false)
                scanDone = scanDone + 1
                processed = processed + 1
            end
            if scanIndex > #scanQueue then
                scanActive = false
                rebuildFiltered()
                refreshRows()
            else
                if ET.loadingText and ET.IsInitialLoading and ET.IsInitialLoading() then
                    ET.loadingText:SetText("LOADING CLEANTREE...\nReading node effects " .. tostring(scanDone) .. "/" .. tostring(scanTotal))
                end
                refreshHeader()
            end
        end
    end

    -- Track direct native-tree spending separately so Pending Changes never
    -- silently pretends it knows what was clicked outside EbonTree.
    if mainFrame and mainFrame:IsShown() and not pendingClick then
        local ash = readSoulAsh()
        if ash then
            local ashChanged = (lastObservedAsh == nil or ash ~= lastObservedAsh)
            if lastObservedAsh and ash < lastObservedAsh then
                untrackedSpend = untrackedSpend + (lastObservedAsh - ash)
                refreshPendingPanel()
            elseif lastObservedAsh and ash > lastObservedAsh then
                -- Usually Apply/reload/server refresh. Do not fabricate effects.
                untrackedSpend = 0
                refreshPendingPanel()
            end
            lastObservedAsh = ash

            -- Ebonhold populates the native Soul Ash footer asynchronously.
            -- On first open CleanTree can render before that footer has text,
            -- which used to leave the header stuck on red "unavailable" until
            -- the player clicked Refresh. As soon as a live value appears,
            -- repaint the header automatically.
            if ashChanged then refreshHeader() end
        end
    end
end)

-- EbonAPI integration is initialized after every CleanTree function exists so
-- sticky READY/SERVER_* callbacks can safely refresh the UI immediately.
if _G.CleanTreeEbonAPI and CleanTreeEbonAPI.Init then
    CleanTreeEbonAPI.Init({
        onReady = function(version)
            setStatus("EbonAPI " .. tostring(version or "1.x") .. " ready; using live Skill Tree data.", 4)
            if mainFrame and mainFrame:IsShown() then
                buildKnownNodes()
                nativeReadyAttempts = 0
                nativeReadyWait = false
                discoverRuntimeNodes()
            end
        end,
        onFeature = function(name, available)
            if available and (name == "TalentDatabase" or name == "SkillTreeFrame" or name == "SkillTree")
                and mainFrame and mainFrame:IsShown() and not discoveryActive and not ET._resolveActive then
                nativeReadyAttempts = 0
                nativeReadyWait = false
                discoverRuntimeNodes()
            end
        end,
        onAsh = function()
            lastObservedAsh = readSoulAsh()
            if mainFrame and mainFrame:IsShown() then
                refreshHeader()
                refreshPendingPanel()
                refreshRows()
            end
        end,
        onLoadout = function()
            for _, node in pairs(liveNodes) do
                node.nativeRejected = nil
                syncNodeOwnership(node)
            end
            if mainFrame and mainFrame:IsShown() then
                rebuildFiltered()
                refreshRows()
                refreshPendingPanel()
                if selectedNode then refreshDetail(selectedNode) end
            end
        end,
    })
end

chat("v" .. VERSION .. " loaded. Open the Ebonhold Skill Tree or use /cleantree.")

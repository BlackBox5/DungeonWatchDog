local ADDON_NAME = GetAddOnMetadata(..., 'Title')
local AceComm = LibStub('AceComm-3.0')
local addon = LibStub('AceAddon-3.0'):GetAddon(ADDON_NAME)
local Actions = addon:NewModule('Actions', 'AceEvent-3.0')
local Utils = addon:GetModule('Utils')
local infos = addon:GetModule('Constants'):GetInfos()
local L = LibStub('AceLocale-3.0'):GetLocale(ADDON_NAME, false)

function Actions:OnInitialize()
    self:updatePlayersCache()
end

function Actions:updatePlayersCache()
    self.playersCache = WATCHDOG_DB.players or {}
end

function Actions:initSlash()
    SLASH_WATCHDOG1 = '/watchdog'
    SLASH_WATCHDOG2 = '/wd'
    SLASH_WATCHDOG3 = '/WD'
    SlashCmdList['WATCHDOG'] = function(param)
        local Settings = addon:GetModule('Settings', true)
        return Settings and Settings:Open()
    end
end

function Actions:initAddonMessage()
    local addonMessageFrame = CreateFrame('FRAME')
    addonMessageFrame:RegisterEvent('READY_CHECK')
    addonMessageFrame:SetScript('OnEvent', function()
        local versionString = 'version:' .. infos.VERSION
        local type = (IsInRaid() and 'RAID')
                or (IsInGroup() and 'PARTY')
                or (IsInGuild() and 'GUILD')
                or nil
        if not type then return end
        AceComm:SendCommMessage(infos.ADDON_COMM_BASE, versionString, type)
    end)
    AceComm:RegisterComm(infos.ADDON_COMM_BASE, function(prefix, text)
        if prefix ~= infos.ADDON_COMM_BASE or not text then return end
        if not string.find(text, 'version') then return end
        local major, minor, revision = string.match(text, 'version:(%d).(%d).(%d)')
        if not major or not minor or not revision then return end
        self:compareVersion(major, minor, revision)
    end)
    AceComm:RegisterComm(infos.ADDON_COMM_IGNORE_SHARE, function(prefix, text)
        if prefix ~= infos.ADDON_COMM_IGNORE_SHARE or not text then return end
        self:SendMessage('NETWORKS_CONNECTION_CREATION', text)
    end)
    AceComm:RegisterComm(infos.ADDON_COMM_IGNORE_SHARE_ONCE, function(prefix, text)
        if prefix ~= infos.ADDON_COMM_IGNORE_SHARE_ONCE or not text then return end
        self:SendMessage('NETWORKS_CONNECTION_CREATION', text, true)
    end)
end

function Actions:isBannedPlayer(name)
    if not name then return nil end
    return self.playersCache[name]
end

function Actions:banPlayerWithID(id)
    if not id then return end
    local info = { C_LFGList.GetSearchResultInfo(id) }
    local leaderName = info[13]
    if leaderName == nil then return SendSystemMessage(L.NOT_FOUND_PLAYER_NAME) end

    if not WATCHDOG_DB.players[leaderName] then 
        WATCHDOG_DB.players[leaderName] = { status = 1, name = leaderName, time = time() }
        C_LFGList.ReportSearchResult(id, 'lfglistname')
        self:log(leaderName..' '..L.ACTION_BAN_MESSAGE)
    end
end

function Actions:banPlayerWithName(name)
    if not name then return end
    if WATCHDOG_DB.players[name] then return end
    WATCHDOG_DB.players[name] = { status = 1, name = name, time = time() }
    self:log(name..' '..L.ACTION_BAN_MESSAGE)
end

function Actions:unbanPlayerWithName(name)
    local next = {}
    for k, v in pairs(WATCHDOG_DB.players) do
        if k ~= name then 
            next[k] = v
        end
    end
    WATCHDOG_DB.players = next
    self:log(name..' '..L.ACTION_UNBAN_MESSAGE)
end

function Actions:unbanPlayerWithTime(limitTime)
    local players, next = WATCHDOG_DB.players, {}
    local lastCount, nextCount, now = 0, 0, time()
    limitTime = limitTime or 259200
                    
    for k, v in pairs(players) do
        lastCount = lastCount + 1
        if v and v.time and ((now - v.time) < limitTime) then
            nextCount = nextCount + 1
            next[k] = v
        end
    end
    WATCHDOG_DB.players = next
    self:log(string.format(L.CLEAR_BAN_LIST_TIME_SUCCESS, lastCount - nextCount))
    next, players = nil, nil
end

function Actions:banAllPlayers()
    local players = WATCHDOG_VARS.LAST_SEARCH_RESULTS
    if not players or #players == 0 then 
        return self:log(L.IGNORE_ALL_NOT_FOUND_PLAYER)
    end
    for i = 1, #players do
        self:banPlayerWithName(players[i].name)
        C_LFGList.ReportSearchResult(players[i].id, 'lfglistname')
    end
    self:log(string.format(L.IGNORE_ALL_COMPLETED, #players))
end

function Actions:unbanAllplayers()
    WATCHDOG_DB.players = {}
    self:log(L.CLEAR_BAN_LIST_SUCCESS)
end

function Actions:importSettings(text, isShared)
    if not text then
        if not isShared then self:log(L.EXPORT_TEXT_EMPTY) end
        return
    end

    local index = string.match(text, infos.DEFAULT_EXPORT_SEP)
    if not index then
        if not isShared then self:log(L.EXPORT_TEXT_ERROR) end
        return
    end

    if not isShared then self:log(L.EXPORT_TIPS_WITH_TYPE_COVER) end

    local names = Utils:split(Utils:decode(text), infos.DEFAULT_EXPORT_SEP)
    local players = {}
    local name, count, time = nil, 0, time()

    for i = 1, #names do
        name = names[i]
        if name then 
            count = count + 1
            if isShared then
                WATCHDOG_DB.players[name] = { status = 1, name = name, time = time }
            else
                players[name] = { status = 1, name = name, time = time }
            end
        end
        name = nil
    end

    if not isShared then
        WATCHDOG_DB.players = players
        self:log(string.format(L.EXPORT_SUCCESS, count))
    end
    
    name, count, players, names = nil, nil, nil, nil
end

function Actions:ExportSettings()
    local players, str, len = WATCHDOG_DB.players, infos.DEFAULT_EXPORT_SEP, 0
                    
    for k, v in pairs(players) do
        if v and v.name then
            len = len + 1
            str = str..v.name..infos.DEFAULT_EXPORT_SEP
        end
    end
    if len == 0 then str = '' end

    return Utils:encode(str)
end

function Actions:findLimitItemLevel()
    local selfLevel = GetAverageItemLevel()
    if not selfLevel or selfLevel < 10 then
        return 2
    end
    if selfLevel < 50 then return selfLevel - 10 end
    return selfLevel - 50
end

function Actions:checkListInfo(searchID, limitLevel, defaultFilterToggle)
    
    local passed, lastPlayer = nil, nil
    local id, _, _, _, _, ilvl, _, minutes, bnet, char, guild, _, leaderName, members = C_LFGList.GetSearchResultInfo(searchID)
    if not id then
        passed = true
        return passed, lastPlayer 
    end

    -- ilvl == 0 or nil is not set
    minutes = (minutes or 0) / 60
    local ilvlPassed = (not ilvl and true) or (ilvl == 0 and true) or (ilvl > limitLevel and true) or nil
    local memberPassed = not (minutes > 20 and members <= 1)
    local defaultFilter = (not defaultFilterToggle and true) or (ilvlPassed and memberPassed)

    -- default filter 
    if not defaultFilter then return passed, lastPlayer end

    if not leaderName then
        C_Timer.After(0.5, function() self:fixLeaderName(id) end)
        passed = true
        return passed, lastPlayer 
    end

    if not self:isBannedPlayer(leaderName) then
        passed = true

        -- not includes BNetFriends / CharFriends / GuildMates
        if bnet == 0 and char == 0 and guild == 0 then
            lastPlayer = { name = leaderName, id = id }
        end
    end
    return passed, lastPlayer
end

function Actions:fixLeaderName(id)
    local info = { C_LFGList.GetSearchResultInfo(id) }
    if not info[13] then return end
    if info[9] ~= 0 or info[10] ~= 0 or info[11] ~= 0 then return end
    if not WATCHDOG_VARS.LAST_SEARCH_RESULTS then WATCHDOG_VARS.LAST_SEARCH_RESULTS = {} end
    table.insert(WATCHDOG_VARS.LAST_SEARCH_RESULTS, { name = info[13], id = id })
end

function Actions:meetingStoneMixin()
    local GUI = LibStub('NetEaseGUI-2.0')
    local MeetingStone = LibStub('AceAddon-3.0'):GetAddon('MeetingStone') 
    local LfgService, BrowsePanel = MeetingStone:GetModule('LfgService', true), MeetingStone:GetModule('BrowsePanel', true)
    if not LfgService or not BrowsePanel then return end
    local _cacheCopy = LfgService._CacheActivity
    local limitLevel = self:findLimitItemLevel()
    local defaultFilterToggle = WATCHDOG_DB.defaultFilterToggle

    LfgService._CacheActivity = function(s, id)
        if not id then return end
        local passed = self:checkListInfo(id, limitLevel, defaultFilterToggle)
        if not passed then return end
        return _cacheCopy(s, id)
    end
    
    local _toggleMenuCopy = BrowsePanel.ToggleActivityMenu
    BrowsePanel.ToggleActivityMenu = function(s, anchor, activity)
        local usable, reason = s:CheckSignUpStatus(activity)
        _toggleMenuCopy(s, anchor, activity)
        GUI:CloseMenu()
        GUI:ToggleMenu(anchor, {
            {
                text = activity:GetName(),
                isTitle = true,
                notCheckable = true,
            },
            {
                text = L.MEETINGSTONE_APPLY_TEXT,
                func = function() s:SignUp(activity) end,
                disabled = not usable or activity:IsDelisted() or activity:IsApplication(),
                tooltipTitle = not (activity:IsDelisted() or activity:IsApplication()) and L.MEETINGSTONE_APPLY_TEXT,
                tooltipText = reason,
                tooltipWhileDisabled = true,
                tooltipOnButton = true,
            },
            {
                text = L.MEETINGSTONE_IGNORE_TITLE,
                func = function() self:banPlayerWithName(activity:GetLeader()) end,
                disabled = not activity:GetLeader(),
                tooltipTitle = L.MEETINGSTONE_IGNORE_TOOLTIP_TITLE,
                tooltipText = L.MEETINGSTONE_IGNORE_TOOLTIP_DESC,
                tooltipWhileDisabled = true,
                tooltipOnButton = true,
            },
            {
                text = WHISPER_LEADER,
                func = function() ChatFrame_SendTell(activity:GetLeader()) end,
                disabled = not activity:GetLeader() or not activity:IsApplication(),
                tooltipTitle = not activity:IsApplication() and WHISPER,
                tooltipText = not activity:IsApplication() and LFG_LIST_MUST_SIGN_UP_TO_WHISPER,
                tooltipOnButton = true,
                tooltipWhileDisabled = true,
            },
            {
                text = CANCEL,
            },
        }, 'cursor')
    end
end

function Actions:sendVersionMessage()
    if not WATCHDOG_DB then return end
    if not WATCHDOG_DB.nextVersion then return end
    if not WATCHDOG_DB.versionMessageToggle then return end

    local major1, minor1, revision1 = string.match(WATCHDOG_DB.nextVersion, '(%d).(%d).(%d)')
    local major2, minor2, revision2 = string.match(infos.VERSION, '(%d).(%d).(%d)')
    local resetVersion = function()
        WATCHDOG_DB.nextVersion = nil
    end
    if not major1 or not minor1 or not revision1 then return resetVersion() end
    if major1 < major2 then return resetVersion() end
    if major1 == major2 and minor1 < minor2 then return resetVersion() end
    if major1 == major2 and minor1 == minor2 and revision1 < revision2 then return resetVersion() end 

    if WATCHDOG_DB.nextVersion == infos.VERSION then return resetVersion() end
    self:log(L.VERSION_EXPIRED)
end

function Actions:log(text)
    local prefix = format('|CFF00FFFF%s: |r', L.ADDON_SHOW_NAME)
    SendSystemMessage(prefix..text)
end

function Actions:compareVersion(major1, minor1, revision1)
    local major2, minor2, revision2 = string.match(infos.VERSION, '(%d).(%d).(%d)')
    local recordNextVersion = function()
        WATCHDOG_DB.nextVersion = major1..'.'..minor1..'.'..revision1
    end
    if major1 > major2 then return recordNextVersion() end
    if major1 == major2 and minor1 > minor2 then return recordNextVersion() end
    if major1 == major2 and minor1 == minor2 and revision1 > revision2 then return recordNextVersion() end
end

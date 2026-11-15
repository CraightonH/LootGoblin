local _,A=...
A.nativeCards={}
A.demoFrames={}
A.retainedFrames={}
-- Siblings of Blizzard's frames: hiding/recycling a native roll must not hide
-- the retained result or turn a later item's controls into controls for this roll.
local function enabled()
    local gamepad=InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
    return A.db and A.db.presentation=="native" and not gamepad
end
function A.LayoutNative()
    local container=GroupLootContainer
    if not container or type(container.reservedSize)~="number" then return end
    if InCombatLockdown and InCombatLockdown() then return end
    A.nativeSpacing=A.nativeSpacing or container.reservedSize
    local size=A.nativeSpacing
    if enabled() then
        for _,r in ipairs(A.rolls) do
            if not r.demo and r.nativeAttached and r.nativeCard and not r.nativeFrame.lootGoblinRetained then
                size=math.max(size,(r.nativeFrame:GetHeight() or 80)+r.nativeCard:GetHeight()+16)
            end
        end
    end
    if container.reservedSize~=size then
        container.reservedSize=size
        if GroupLootContainer_Update then GroupLootContainer_Update(container) end
    end
    for i=1,4 do
        local f=_G["GroupLootFrame"..i]
        if f and f:IsShown() and f.rollID and A.byID[f.rollID] and enabled() then
            A.RestoreLootPosition(f,i)
        end
    end
end
function A.RenderAttachments()
    for _,r in ipairs(A.rolls) do
        r.nativeAttached=false
    end
    if enabled() and not A.historyView then
        for i=1,4 do
            local native=_G["GroupLootFrame"..i]
            local r=native and native.rollID and A.byID[native.rollID]
            if r and not r.demo and not r.dismissed and native:IsShown() then
                local card=A.nativeCards[i]
                if not card then
                    card=A.MakeCard(UIParent); card:SetFrameStrata("DIALOG")
                    A.nativeCards[i]=card
                end
                A.AttachTable(native,r,card,i)
            end
        end
    end
    for _,card in pairs(A.nativeCards) do
        if not card.roll or not card.roll.nativeAttached then card:Hide() end
    end
    A.RenderRetainedRolls()
    A.RenderNativeDemo()
    A.LayoutNative()
end
function A.InitNativeUI()
    if GroupLootContainer_Update then
        hooksecurefunc("GroupLootContainer_Update",function() A.LayoutNative() end)
    end
    for i=1,4 do
        local native=_G["GroupLootFrame"..i]
        if native then
            native:HookScript("OnShow",function() C_Timer.After(0,function() A.Render() end) end)
            native:HookScript("OnHide",function() C_Timer.After(0,function() A.Render() end) end)
        end
    end
end

-- Live and preview frames use this exact table sizing/anchoring path.
function A.AttachTable(native,r,card,slot)
    r.nativeCard=card
    r.nativeSeen=true; r.nativeFrame=native; r.nativeAttached=true
    card.tableOnly=true; card.attached=true; card.tableWidth=math.max(260,native:GetWidth())
    card:SetScale(native:GetEffectiveScale()/UIParent:GetEffectiveScale())
    A.UpdateCard(card,r)
    card:ClearAllPoints(); card:SetPoint("TOP",native,"BOTTOM",0,-2)
    card:Show(); r.frame=card
    A.EnableLootDragging(native,card,slot)
    if not r.demo and not native.lootGoblinRetained then
        r.nativeSlot=slot
        local x,y=native:GetCenter(); local px,py=UIParent:GetCenter()
        local ratio=native:GetEffectiveScale()/UIParent:GetEffectiveScale()
        r.nativeDisplayPosition={x=x*ratio-px,y=y*ratio-py}
        r.nativeDisplayScale=ratio
    end
end
function A.CreateNativeLootDisplay(frameName)
    if A.demoTemplateWarning then return nil end
    local ok,f=pcall(CreateFrame,"Frame",frameName,UIParent,"LootGoblinDemoLootFrameTemplate")
    if not ok or not f or not f.IconFrame or not f.Name or not f.Timer or not f.LootButtonContainer then
        if not A.demoTemplateWarning then
            print("LootGoblin 0.8.2: native loot display could not load. Restart the client to load Demo.xml. "..tostring(ok and "Missing Forever loot frame fields" or f))
            A.demoTemplateWarning=true
        end
        if ok and f then f:Hide() end
        return nil
    end
    f:UnregisterAllEvents()
    for _,script in ipairs({"OnShow","OnHide","OnEvent","OnUpdate"}) do f:SetScript(script,nil) end
    -- The inherited icon scripts query real roll IDs. Preview icons have only
    -- descriptive tooltips and never run those scripts or modified-item clicks.
    f.IconFrame:SetScript("OnUpdate",nil); f.IconFrame:SetScript("OnClick",nil)
    f.IconFrame:SetScript("OnEnter",function(icon)
        GameTooltip:SetOwner(icon,"ANCHOR_RIGHT")
        if f.roll.demo then GameTooltip:SetText((f.roll.name or "Sample item").." (demo)")
        elseif f.roll.link then GameTooltip:SetHyperlink(f.roll.link)
        else GameTooltip:SetText(f.roll.name or "Item") end
        GameTooltip:Show()
    end)
    f.IconFrame:SetScript("OnLeave",function() GameTooltip:Hide() end)
    for key,kind in pairs({NeedButton=1,GreedButton=2,PassButton=0,TransmogButton=4,DisenchantButton=3}) do
        local b=f.LootButtonContainer[key]
        if b then
            local choice=kind
            b:SetScript("OnClick",function() if f.roll and f.roll.demo then A.Choose(f.roll,choice) end end)
            b:SetScript("OnEnter",function()
                GameTooltip:SetOwner(b,"ANCHOR_RIGHT")
                GameTooltip:SetText((b.tooltipText or key)..(f.roll.demo and " (demo only)" or " (display only)")); GameTooltip:Show()
            end)
            b:SetScript("OnLeave",function() GameTooltip:Hide() end)
        end
    end
    if f.NeedRollAnim then f.NeedRollAnim:Hide() end
    f.card=A.MakeCard(UIParent); f.card:SetFrameStrata("DIALOG")
    return f
end
-- This is the same inert Blizzard template for demo and retained live results.
-- A retained frame never owns a real roll ID or submits another loot choice.
function A.PopulateNativeLootDisplay(f,r)
    f.roll=r
    f.Name:SetText(r.name or "Loading item")
    f.IconFrame.Icon:SetTexture(r.texture or "Interface\\Icons\\INV_Misc_Dice_02")
    if f.IconFrame.Count then
        f.IconFrame.Count:SetText(r.count and r.count>1 and r.count or "")
        f.IconFrame.Count:SetShown(r.count and r.count>1 or false)
    end
    if ColorManager and r.quality then
        if ColorManager.GetColorDataForItemQuality then
            local color=ColorManager.GetColorDataForItemQuality(r.quality)
            if color then
                f.Name:SetTextColor(color.r,color.g,color.b)
                if f.Border then f.Border:SetVertexColor(color.r,color.g,color.b) end
            end
        end
        if f.IconFrame.Border and ColorManager.GetAtlasDataForLootBorderItemQuality then
            local atlas=ColorManager.GetAtlasDataForLootBorderItemQuality(r.quality)
            if atlas then f.IconFrame.Border:SetAtlas(atlas) end
        end
    end
    f.Timer:SetMinMaxValues(0,r.duration)
    f.Timer:SetValue(r.finished and 0 or math.max(0,r.started+r.duration-GetTime()))
    for key,kind in pairs({NeedButton=1,GreedButton=2,PassButton=0,TransmogButton=4,DisenchantButton=3}) do
        local b=f.LootButtonContainer[key]
        if b then
            b:SetShown(not not (r.allowed and r.allowed[kind]))
            local active=r.demo and not r.finished and not r.choice
            b:SetEnabled(not not active); b:SetAlpha(active and 1 or 0.35)
        end
    end
end
function A.RenderRetainedRolls()
    for _,f in ipairs(A.retainedFrames) do f.retainedVisible=false end
    if enabled() and not A.historyView then
        for _,r in ipairs(A.rolls) do
            if not r.demo and not r.dismissed and not r.nativeAttached and (r.nativeSeen or r.closed or r.finished) then
                local f=r.retainedFrame
                if not f or f.roll~=r then
                    f=nil
                    for _,candidate in ipairs(A.retainedFrames) do if not candidate.roll then f=candidate; break end end
                    if not f then
                        f=A.CreateNativeLootDisplay("LootGoblinRetainedLootFrame"..(#A.retainedFrames+1))
                        if f then f.lootGoblinRetained=true; A.retainedFrames[#A.retainedFrames+1]=f end
                    end
                    r.retainedFrame=f
                end
                if f then
                    f.retainedVisible=true
                    f:SetScale(r.nativeDisplayScale or A.db.scale)
                    A.PopulateNativeLootDisplay(f,r)
                    A.AttachTable(f,r,f.card,r.nativeSlot or 1)
                    f:Show()
                end
            end
        end
    end
    A.PositionRetainedRolls()
    for _,f in ipairs(A.retainedFrames) do
        if not f.retainedVisible then
            if f.roll and f.roll.retainedFrame==f then f.roll.retainedFrame=nil end
            f.roll=nil; f:Hide(); f.card:Hide()
        end
    end
end
-- Keep a released result near its previous header, but never cover a new live
-- roll that reuses the same native slot. Only addon-owned result frames move.
function A.PositionRetainedRolls()
    local occupied={}
    local function rect(frame,card,p,scale)
        local half=frame:GetWidth()*scale/2; local top=frame:GetHeight()*scale/2
        return {left=p.x-half,right=p.x+half,top=p.y+top,bottom=p.y-top-(card:GetHeight()+2)*scale}
    end
    local function intersects(a,b)
        return a.left<b.right+8 and a.right>b.left-8 and a.bottom<b.top+8 and a.top>b.bottom-8
    end
    for _,r in ipairs(A.rolls) do
        if not r.demo and r.nativeAttached and r.nativeFrame and not r.nativeFrame.lootGoblinRetained then
            occupied[#occupied+1]=rect(r.nativeFrame,r.nativeCard,r.nativeDisplayPosition,r.nativeDisplayScale)
        end
    end
    local screenW,screenH=UIParent:GetWidth()/2,UIParent:GetHeight()/2
    for _,f in ipairs(A.retainedFrames) do
        if f.retainedVisible then
            local r=f.roll; local scale=f:GetEffectiveScale()/UIParent:GetEffectiveScale()
            local base=r.retainedPosition or r.nativeDisplayPosition or A.db.lootPositions[r.nativeSlot or 1] or {x=A.db.x,y=A.db.y}
            local chosen={x=base.x,y=base.y}
            local bounds=rect(f,f.card,chosen,scale)
            local function free(box)
                if box.left< -screenW+8 or box.right>screenW-8 or box.bottom< -screenH+8 or box.top>screenH-8 then return false end
                for _,used in ipairs(occupied) do if intersects(box,used) then return false end end
                return true
            end
            if not f.lootGoblinDragging and not free(bounds) then
                local found=false; local dx=(f:GetWidth()+18)*scale
                local dy=(f:GetHeight()+f.card:GetHeight()+18)*scale
                for row=0,#occupied+1 do
                    for _,column in ipairs({0,-1,1,-2,2}) do
                        local p={x=base.x+column*dx,y=base.y-row*dy}
                        local candidate=rect(f,f.card,p,scale)
                        if free(candidate) then chosen=p; bounds=candidate; found=true; break end
                    end
                    if found then break end
                end
            end
            if not f.lootGoblinDragging then
                f:ClearAllPoints(); f:SetPoint("CENTER",UIParent,"CENTER",chosen.x/scale,chosen.y/scale)
            end
            occupied[#occupied+1]=bounds
        end
    end
end
function A.RenderNativeDemo()
    for _,f in ipairs(A.demoFrames) do f.demoVisible=false end
    if A.demoContainer then A.demoContainer:Hide() end
    local function hideUnused()
        for _,f in ipairs(A.demoFrames) do
            if not f.demoVisible then f:Hide(); f.card:Hide() end
        end
    end
    if A.historyView then hideUnused(); return end
    local hasDemo=false
    for _,r in ipairs(A.rolls) do if r.demo and not r.dismissed then hasDemo=true; break end end
    if not hasDemo or A.demoTemplateWarning then hideUnused(); return end
    if not GroupLootContainer_AddFrame or not GroupLootContainer_Update then
        A.demoTemplateWarning=true
        print("LootGoblin 0.8.2: this client has no native loot container layout functions; demo stopped.")
        return
    end
    local visible={}; local height=0; local tableHeight=0
    if not A.demoContainer then
        local c=CreateFrame("Frame","LootGoblinDemoLootContainer",UIParent)
        c:SetSize(256,1); c:SetFrameStrata("DIALOG")
        c:SetPoint("BOTTOM",UIParent,"BOTTOM",0,60)
        -- Blizzard's native layout calls its managed-alert parent. This preview
        -- container is independent, so it keeps its own anchor and never docks
        -- into the player's live alert stack.
        c.layoutParent={Layout=function() end}
        c.waitingRolls={}; c.rollFrames={}; c.maxIndex=0; c.reservedSize=100
        A.demoContainer=c
    end
    local container=A.demoContainer
    container.rollFrames={}; container.maxIndex=0; container.reservedSize=100
    for _,r in ipairs(A.rolls) do
        if r.demo and not r.dismissed then
            local index=#visible+1
            local f=A.demoFrames[index]
            if not f then f=A.CreateNativeLootDisplay("LootGoblinDemoLootFrame"..index); A.demoFrames[index]=f end
            if f then
                A.PopulateNativeLootDisplay(f,r)
                f.demoVisible=true
                A.AttachTable(f,r,f.card,index)
                visible[#visible+1]=f
                local slot=f:GetHeight()+f.card:GetHeight()+18
                container.reservedSize=math.max(container.reservedSize,slot)
                height=math.max(height,slot); tableHeight=math.max(tableHeight,f.card:GetHeight())
            end
        end
    end
    hideUnused()
    if #visible==0 then container:Hide(); return end
    for _,f in ipairs(visible) do
        if f.lootGoblinDragging then container:Show(); return end
    end
    -- Use the game client's normal dungeon-roll placement function. The only
    -- simulated pieces are item/participant data and the choice callbacks.
    local scale=math.min(A.db.scale,math.max(0.1,(UIParent:GetHeight()-120)/math.max(1,height*#visible)))
    container:SetScale(scale)
    -- Native slots center the header; include the table's downward overhang
    -- when placing the independent preview stack above the bottom screen edge.
    container:ClearAllPoints(); container:SetPoint("BOTTOM",UIParent,"BOTTOM",0,60/scale+tableHeight/2)
    for _,f in ipairs(visible) do
        f:SetScale(scale); f.card:SetScale(scale)
        GroupLootContainer_AddFrame(container,f)
    end
    for _,f in ipairs(visible) do A.RestoreLootPosition(f,f.lootGoblinSlot) end
end

-- Position the header and let the table follow its anchor. Store UIParent-space
-- coordinates so changing the preview scale does not change the saved location.
function A.RestoreLootPosition(frame,slot)
    local r=frame.roll
    local p=frame.lootGoblinRetained and r and (r.retainedPosition or r.nativeDisplayPosition) or A.db.lootPositions[slot]
    if not p and frame.lootGoblinRetained then p={x=A.db.x,y=A.db.y} end
    if not p or frame.lootGoblinDragging then return end
    local ratio=frame:GetEffectiveScale()/UIParent:GetEffectiveScale()
    frame:ClearAllPoints(); frame:SetPoint("CENTER",UIParent,"CENTER",p.x/ratio,p.y/ratio)
end
function A.EnableLootDragging(native,card,slot)
    native.lootGoblinSlot=slot
    native:SetMovable(true); native:SetClampedToScreen(true)
    if not card.dragHandle then
        local handle=CreateFrame("Frame",nil,card)
        card.dragHandle=handle; handle:EnableMouse(true); handle:RegisterForDrag("LeftButton")
        handle:SetPoint("TOPLEFT",8,-4); handle:SetPoint("TOPRIGHT",-8,-4); handle:SetHeight(25)
        handle:SetScript("OnDragStart",function(self)
            local frame=self.owner
            if A.db.locked or (not self.roll.demo and InCombatLockdown and InCombatLockdown()) then return end
            frame.lootGoblinDragging=true; frame:StartMoving()
        end)
        handle:SetScript("OnDragStop",function(self)
            local frame=self.owner
            if not frame.lootGoblinDragging then return end
            frame:StopMovingOrSizing(); frame.lootGoblinDragging=false
            local x,y=frame:GetCenter(); local px,py=UIParent:GetCenter()
            local ratio=frame:GetEffectiveScale()/UIParent:GetEffectiveScale()
            local position={x=x*ratio-px,y=y*ratio-py}
            A.db.lootPositions[frame.lootGoblinSlot]=position
            if frame.lootGoblinRetained then self.roll.retainedPosition=position end
            A.Render()
        end)
    end
    card.dragHandle.owner=native; card.dragHandle.roll=card.roll
    native.lootGoblinDragHandle=card.dragHandle
    if not card.wholePanelDrag then
        card.wholePanelDrag=true
        card:EnableMouse(true); card:RegisterForDrag("LeftButton")
        card:SetScript("OnDragStart",function()
            local handle=card.dragHandle
            handle:GetScript("OnDragStart")(handle)
        end)
        card:SetScript("OnDragStop",function()
            local handle=card.dragHandle
            handle:GetScript("OnDragStop")(handle)
        end)
    end
    if not native.lootGoblinWholeDrag then
        native.lootGoblinWholeDrag=true
        local function start()
            local handle=native.lootGoblinDragHandle
            if handle and handle.roll and handle.roll.nativeAttached and
                (handle.roll.demo or enabled()) then handle:GetScript("OnDragStart")(handle) end
        end
        local function stop()
            local handle=native.lootGoblinDragHandle
            if handle then handle:GetScript("OnDragStop")(handle) end
        end
        -- Leave all existing native scripts and loot-button clicks in place.
        -- The icon consumes mouse input, so it forwards dragging separately.
        for _,surface in ipairs({native,native.IconFrame}) do
            surface:EnableMouse(true); surface:RegisterForDrag("LeftButton")
            surface:HookScript("OnDragStart",start); surface:HookScript("OnDragStop",stop)
        end
    end
    A.RestoreLootPosition(native,slot)
end

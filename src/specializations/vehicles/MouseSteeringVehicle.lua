--
-- MouseSteeringVehicle
--
-- Author: Sławek Jaskulski
-- Copyright (C) Mod Next, All Rights Reserved.
--

local modName = g_currentModName

MouseSteeringVehicle = {}

function MouseSteeringVehicle.prerequisitesPresent(specializations)
  return SpecializationUtil.hasSpecialization(Drivable, specializations)
end

function MouseSteeringVehicle.registerFunctions(vehicleType)
  SpecializationUtil.registerFunction(vehicleType, "updateSteering", MouseSteeringVehicle.updateSteering)
  SpecializationUtil.registerFunction(vehicleType, "isHudVisible", MouseSteeringVehicle.isHudVisible)
  SpecializationUtil.registerFunction(vehicleType, "updateHudDisplay", MouseSteeringVehicle.updateHudDisplay)
  SpecializationUtil.registerFunction(vehicleType, "updateControlledVehicle", MouseSteeringVehicle.updateControlledVehicle)
  SpecializationUtil.registerFunction(vehicleType, "getAxisSide", MouseSteeringVehicle.getAxisSide)
  SpecializationUtil.registerFunction(vehicleType, "getVehicleId", MouseSteeringVehicle.getVehicleId)
end

function MouseSteeringVehicle.registerEventListeners(vehicleType)
  SpecializationUtil.registerEventListener(vehicleType, "onLoad", MouseSteeringVehicle)
  SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", MouseSteeringVehicle)
  SpecializationUtil.registerEventListener(vehicleType, "onDelete", MouseSteeringVehicle)
  SpecializationUtil.registerEventListener(vehicleType, "onUpdate", MouseSteeringVehicle)
  SpecializationUtil.registerEventListener(vehicleType, "onEnterVehicle", MouseSteeringVehicle)
  SpecializationUtil.registerEventListener(vehicleType, "onLeaveVehicle", MouseSteeringVehicle)
  SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", MouseSteeringVehicle)
end

function MouseSteeringVehicle.initSpecialization()
  local schemaSavegame = Vehicle.xmlSchemaSavegame

  schemaSavegame:register(XMLValueType.STRING, "vehicles.vehicle(?)." .. modName .. ".mouseSteeringVehicle#id", "ID of the vehicle")
end

function MouseSteeringVehicle:onLoad(savegame)
  self.spec_mouseSteeringVehicle = self[("spec_%s.mouseSteeringVehicle"):format(modName)]
  local spec = self.spec_mouseSteeringVehicle

  spec.mouseSteering = g_currentMission.mouseSteering
  spec.settings = spec.mouseSteering.settings

  spec.enabled, spec.paused = false, false
  spec.axisSide, spec.axisSideSend = 0, 0

  -- Generate a unique identifier for the vehicle if it doesn't have one yet
  spec.vehicleId = string.format("%05x", math.random(0, 0xfffff)) or "unknown"

  if savegame ~= nil then
    spec.vehicleId = savegame.xmlFile:getValue(savegame.key .. "." .. modName .. ".mouseSteeringVehicle#id", spec.vehicleId)
  end
end

function MouseSteeringVehicle:saveToXMLFile(xmlFile, key, usedModNames)
  local spec = self.spec_mouseSteeringVehicle

  xmlFile:setValue(key .. "#id", spec.vehicleId)
end

function MouseSteeringVehicle:onPostLoad(savegame)
  local spec = self.spec_mouseSteeringVehicle

  spec.enabled = spec.mouseSteering:isVehicleSaved(self)
end

function MouseSteeringVehicle:onDelete()
  local spec = self.spec_mouseSteeringVehicle

  spec.mouseSteering:removeVehicle(self)

  -- Clear any remaining references
  spec.mouseSteering = nil
  spec.settings = nil
end

function MouseSteeringVehicle:onUpdate(dt)
  if not self:getIsEntered() then
    return
  end

  self:updateSteering(dt)
  self:updateHudDisplay()
end

function MouseSteeringVehicle:updateSteering(dt)
  local spec = self.spec_mouseSteeringVehicle

  if not spec.enabled then
    return
  end

  local showMouseCursor = g_inputBinding:getShowMouseCursor()
  if not (spec.paused or showMouseCursor) then
    -- Calculate steering
    local invertMultiplier = spec.settings.invertXAxis and -1 or 1
    local axisSteer = spec.mouseSteering:getMovedSide() * invertMultiplier
    spec.axisSide = spec.mouseSteering:normalizeAxis(spec.axisSide, axisSteer, spec.settings.sensitivity)

    -- Apply filtering - deadzone and linearity
    local filteredAxis = spec.mouseSteering:applyDeadzone(spec.axisSide, spec.settings.deadzone)
    filteredAxis = spec.mouseSteering:applyLinearity(filteredAxis, spec.settings.linearity)

    -- Apply smoothing
    spec.axisSideSend = spec.mouseSteering:applySmoothness(spec.axisSideSend, filteredAxis, spec.settings.smoothness, dt)
  end

  -- Send steering input to vehicle
  Drivable.actionEventSteer(self, nil, spec.axisSideSend, nil, true, nil, InputDevice.CATEGORY.GAMEPAD)
end

-- TODO: Refactor HUD to work seamlessly with popup message and context action display
function MouseSteeringVehicle:isHudVisible(spec, isInside, activeCamera)
  local isObstructed = g_currentMission.hud.popupMessage:getVisible() or g_currentMission.hud.contextActionDisplay:getVisible()

  if not spec.enabled or isObstructed then
    return false
  end

  local hudVisibility = {
    [1] = true, -- outside and inside
    [2] = isInside, -- inside
    [3] = not isInside, -- outside
  }

  local showHud = hudVisibility[spec.settings.hud] or false

  if showHud and spec.settings.hudLookBackInside and activeCamera and activeCamera.isInside then
    local rotY = math.deg(activeCamera.rotY - activeCamera.origRotY) % 360
    showHud = rotY >= 120 and rotY <= 240
  end

  return showHud
end

function MouseSteeringVehicle:updateHudDisplay()
  local spec = self.spec_mouseSteeringVehicle
  local activeCamera = self:getActiveCamera()

  if not activeCamera then
    return
  end

  local isVisible = self:isHudVisible(spec, activeCamera.isInside, activeCamera)
  local currentlyVisible = spec.mouseSteering:getHudVisible()

  if isVisible ~= currentlyVisible then
    spec.mouseSteering:setControlledVehicle(isVisible and self or nil)
  end

  local hudTextVisible = spec.settings.hudText
  spec.mouseSteering:setHudTextVisible(hudTextVisible and isVisible)
end

function MouseSteeringVehicle:updateControlledVehicle(isEntering)
  local spec = self.spec_mouseSteeringVehicle

  if not spec.mouseSteering:getHudVisible() then
    return
  end

  local controlledVehicle = isEntering and self or nil
  spec.mouseSteering:setControlledVehicle(controlledVehicle)
end

function MouseSteeringVehicle:onEnterVehicle()
  self:updateControlledVehicle(true)
end

function MouseSteeringVehicle:onLeaveVehicle()
  self:updateControlledVehicle(false)
end

function MouseSteeringVehicle:actionEventToggleSteering(actionName, inputValue)
  if inputValue ~= 1 then
    return
  end

  local spec = self.spec_mouseSteeringVehicle
  spec.enabled = not spec.enabled

  if spec.settings.autoSaveVehicle then
    local action = spec.enabled and "addVehicle" or "removeVehicle"

    spec.mouseSteering[action](spec.mouseSteering, self)
    spec.mouseSteering:saveVehicleToXMLFile()
  end

  if not spec.enabled then
    spec.axisSide, spec.axisSideSend = 0, 0
  end
end

function MouseSteeringVehicle:actionEventSaveSteering(actionName, inputValue)
  if inputValue ~= 1 then
    return
  end

  local spec = self.spec_mouseSteeringVehicle
  local isSaved = spec.mouseSteering:isVehicleSaved(self)
  local isMaxVehiclesReached = spec.mouseSteering:isMaxVehiclesReached()

  local action = isSaved and "removeVehicle" or "addVehicle"
  local notification = isSaved and "vehicleRemoved" or (not isMaxVehiclesReached and "vehicleAdded")

  if notification then
    spec.mouseSteering:showNotification("mouseSteering_notification_" .. notification)
  end

  spec.mouseSteering[action](spec.mouseSteering, self)
  spec.mouseSteering:saveVehicleToXMLFile()
end

function MouseSteeringVehicle:actionEventPauseSteering(actionName, inputValue)
  local spec = self.spec_mouseSteeringVehicle

  if spec.enabled then
    spec.paused = (inputValue == 1)
  end
end

function MouseSteeringVehicle:actionEventShowMenu(actionName, inputValue)
  g_gui:showGui("MouseSteeringMenu")
end

function MouseSteeringVehicle:getAxisSide()
  local spec = self.spec_mouseSteeringVehicle

  return spec.axisSideSend
end

function MouseSteeringVehicle:getVehicleId()
  local spec = self.spec_mouseSteeringVehicle

  return spec.vehicleId
end

function MouseSteeringVehicle:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
  if not self.isClient then
    return
  end

  local spec = self.spec_mouseSteeringVehicle
  self:clearActionEventsTable(spec.actionEvents)

  if self:getIsActiveForInput(true, true) and self:getIsEntered() and not self:getIsAIActive() then
    local actions = {
      { InputAction.MS_TOGGLE, MouseSteeringVehicle.actionEventToggleSteering },
      { InputAction.MS_SAVE, MouseSteeringVehicle.actionEventSaveSteering },
      { InputAction.MS_PAUSE, MouseSteeringVehicle.actionEventPauseSteering, true },
      { InputAction.MS_SHOW_MENU, MouseSteeringVehicle.actionEventShowMenu },
    }

    for _, action in ipairs(actions) do
      local _, actionEventId = self:addActionEvent(spec.actionEvents, action[1], self, action[2], action[3] or false, true, false, true, nil)
      g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_LOW)
      g_inputBinding:setActionEventTextVisibility(actionEventId, false)
    end
  end
end

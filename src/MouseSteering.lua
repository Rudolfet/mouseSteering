--
-- MouseSteering
--
-- Author: Sławek Jaskulski
-- Copyright (C) Mod Next, All Rights Reserved.
--

MouseSteering = {
  MAX_VEHICLES = 100,
}

local MouseSteering_mt = Class(MouseSteering)

function MouseSteering.new(modName, modDirectory, modSettingsDirectory, mission, i18n, gui)
  local self = setmetatable({}, MouseSteering_mt)

  self.modName = modName
  self.modDirectory = modDirectory
  self.modSettingsDirectory = modSettingsDirectory

  self.isServer = mission:getIsServer()
  self.isClient = mission:getIsClient()
  self.mission = mission
  self.i18n = i18n

  self.modDesc = {}
  self.settings = {}

  -- TODO: Create a class for Vehicle Storage
  self.vehicles = {
    count = 0,
    data = {},
  }

  self.camera = VehicleCameraExtension.new()
  self.gui = MouseSteeringGui.new(nil, modDirectory, mission, gui, i18n)
  self.hud = MouseSteeringHud.new(nil, modDirectory, mission, gui, i18n)

  return self
end

function MouseSteering:delete() end

function MouseSteering:load()
  self:loadFromXMLFiles()

  self.camera:load()
  self.gui:load()
  self.hud:load()
end

function MouseSteering:draw()
  local isNotMenuVisible = not self.mission.hud.isMenuVisible
  local isNotFading = not self.mission.hud:getIsFading()

  if self.isClient and isNotMenuVisible and not g_noHudModeEnabled and isNotFading then
    self.hud:drawControlledEntityHUD()
  end
end

function MouseSteering:onMissionLoaded(mission)
  self:load()
end

function MouseSteering:update(dt)
  self.hud:update(dt)
end

function MouseSteering:loadFromXMLFiles()
  self:loadModDescFromXMLFile()
  self:loadSettingsFromXMLFile()
  self:loadVehicleFromXMLFile()
end

function MouseSteering:loadModDescFromXMLFile()
  local xmlFile = XMLFile.loadIfExists("modDesc", self.modDirectory .. "modDesc.xml")

  if xmlFile == nil then
    Logging.error(string.format("Mouse Steering: Failed to load modDesc from (%s) path!", self.modDirectory .. "modDesc.xml"))

    return
  end

  local version = xmlFile:getString("modDesc.version")

  if version ~= nil then
    local major, minor, patch = version:match("(%d+)%.(%d+)%.(%d+)")

    if major and minor and patch then
      self.modDesc.version = string.format("%s.%s.%s", major, minor, patch)
    end
  end

  xmlFile:delete()
end

function MouseSteering:loadConfigFile(file, defaultPath)
  local path = self.modSettingsDirectory .. file .. ".xml"

  createFolder(self.modSettingsDirectory)
  copyFile(defaultPath, path, false)

  if not fileExists(path) then
    path = defaultPath
  end

  return path
end

function MouseSteering:loadSettingsFromXMLFile()
  local xmlFilename = self:loadConfigFile("settings", Utils.getFilename("data/settings.xml", self.modDirectory))
  local xmlFile = XMLFile.loadIfExists("MouseSteeringXML", xmlFilename)

  if xmlFile == nil then
    Logging.error(string.format("Mouse Steering: Failed to load settings from (%s) path!", xmlFilename))

    return false
  end

  xmlFile:iterate("settings.setting", function(_, key)
    local name = xmlFile:getString(key .. "#name")
    local value = self:getXMLSetting(xmlFile, key)

    if name ~= nil and value ~= nil then
      self.settings[name] = value
    end
  end)

  xmlFile:delete()

  return true
end

function MouseSteering:saveSettingsToXMLFile()
  local xmlFile = XMLFile.create("MouseSteeringXML", self.modSettingsDirectory .. "settings.xml", "settings")

  if xmlFile == nil then
    Logging.error("Mouse Steering: Something went wrong while trying to save settings!")

    return
  end

  local i = 0

  for name, value in pairs(self.settings) do
    local key = string.format("settings.setting(%d)", i)

    self:setXMLSetting(xmlFile, key, {
      name = name,
      value = value,
    })

    i = i + 1
  end

  xmlFile:save()
  xmlFile:delete()
end

function MouseSteering:reset()
  self.vehicles = {
    count = 0,
    data = {},
  }

  if fileExists(self.modSettingsDirectory .. "settings.xml") then
    -- deleteFile(self.modSettingsDirectory .. "settings.xml")
    deleteFolder(self.modSettingsDirectory)
  end

  self:loadSettingsFromXMLFile()
end

function MouseSteering:getXMLSetting(xmlFile, key)
  local types = {
    integer = xmlFile.getInt,
    boolean = xmlFile.getBool,
    float = xmlFile.getFloat,
    string = xmlFile.getString,
  }

  for typeName, getFunction in pairs(types) do
    local value = getFunction(xmlFile, key .. "#" .. typeName)

    if value ~= nil then
      return value
    end
  end

  return nil
end

function MouseSteering:setXMLSetting(xmlFile, key, setting)
  local name, value = setting.name, setting.value
  xmlFile:setString(key .. "#name", name)

  if type(value) == "number" then
    if value % 1 == 0 then
      xmlFile:setInt(key .. "#integer", math.floor(value))
    else
      xmlFile:setFloat(key .. "#float", value)
    end
  elseif type(value) == "boolean" then
    xmlFile:setBool(key .. "#boolean", value)
  end
end

function MouseSteering:loadVehicleFromXMLFile()
  local xmlFile = XMLFile.loadIfExists("MouseSteeringXML", self.modSettingsDirectory .. "vehicles.xml", "vehicles")

  if xmlFile == nil then
    return
  end

  xmlFile:iterate("vehicles.vehicle", function(_, key)
    local id = xmlFile:getString(key .. "#id")
    local xmlFilename = xmlFile:getString(key .. "#xmlFilename")

    if id ~= nil and xmlFilename ~= nil then
      self:addVehicle(self:combineVehicleKey(id, xmlFilename))
    end
  end)

  xmlFile:delete()
end

function MouseSteering:saveVehicleToXMLFile()
  local xmlFile = XMLFile.create("MouseSteeringXML", self.modSettingsDirectory .. "vehicles.xml", "vehicles")

  if xmlFile == nil then
    Logging.error("Mouse Steering: Failed to save vehicles to (%s) path!", self.modSettingsDirectory .. "vehicles.xml")

    return
  end

  local i = 0

  for vehicle in pairs(self.vehicles.data) do
    local key = string.format("vehicles.vehicle(%s)", i)
    local id, xmlFilename = self:splitVehicleKey(vehicle)

    xmlFile:setString(key .. "#id", id)
    xmlFile:setString(key .. "#xmlFilename", xmlFilename)

    i = i + 1
  end

  xmlFile:save()
  xmlFile:delete()
end

function MouseSteering:addVehicle(param)
  local vehicleKey = type(param) == "table" and self:getVehicleKey(param) or param

  if self.vehicles.data[vehicleKey] ~= nil or self:isMaxVehiclesReached() then
    if self.vehicles.data[vehicleKey] == nil then
      self:showNotification("mouseSteering_notification_vehicleLimit", true)
    end

    return false
  end

  self.vehicles.data[vehicleKey] = true
  self.vehicles.count = self.vehicles.count + 1

  return true
end

function MouseSteering:removeVehicle(param)
  local vehicleKey = type(param) == "table" and self:getVehicleKey(param) or param

  if self.vehicles.data[vehicleKey] == nil then
    return false
  end

  self.vehicles.data[vehicleKey] = nil
  self.vehicles.count = self.vehicles.count - 1

  return true
end

function MouseSteering:showNotification(textKey, ...)
  local config = {
    type = FSBaseMission.INGAME_NOTIFICATION_INFO,
    duration = 4000,
    sound = GuiSoundPlayer.SOUND_SAMPLES.NOTIFICATION,
  }

  local text = self.i18n:getText(textKey):format(...)
  self.mission.hud:addSideNotification(config.type, text, config.duration, config.sound)
end

function MouseSteering:combineVehicleKey(vehicleId, vehicleName)
  return string.format("%s:%s", vehicleId, vehicleName)
end

function MouseSteering:splitVehicleKey(vehicleKey)
  return vehicleKey:match("([^:]+):(.+)")
end

function MouseSteering:getVehicleKey(vehicle)
  local vehicleId = vehicle:getVehicleId()
  local configFileName = vehicle.configFileName

  return self:combineVehicleKey(vehicleId, configFileName)
end

function MouseSteering:isVehicleSaved(vehicle)
  local vehicleKey = self:getVehicleKey(vehicle)
  return self.vehicles.data[vehicleKey] ~= nil
end

function MouseSteering:isMaxVehiclesReached()
  return self.vehicles.count >= MouseSteering.MAX_VEHICLES
end

function MouseSteering:setControlledVehicle(vehicle)
  self.hud:setControlledVehicle(vehicle, true)
end

function MouseSteering:normalizeAxis(axis, input, sensitivity)
  return math.min(math.max(axis + input * sensitivity, -1), 1)
end

function MouseSteering:applyDeadzone(axis, deadzone)
  if math.abs(axis) < deadzone then
    return 0
  end

  local normalizedAxis = (math.abs(axis) - deadzone) / (1 - deadzone)
  return (axis > 0 and 1 or -1) * normalizedAxis
end

function MouseSteering:applyLinearity(axis, linearity)
  if linearity == 1 then
    return axis
  end

  local function bezier(t, p0, p1, p2, p3)
    local u = 1 - t
    return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
  end

  local exponent = math.max(0.65, math.min(linearity, 5)) or 2
  local bezierPoints = { 0, 0.05, 0.15, 1 }

  local absAxis = math.abs(axis)
  local result = bezier(math.pow(absAxis, exponent), unpack(bezierPoints))

  return (axis >= 0 and 1 or -1) * math.max(0, math.min(1, result))
end

function MouseSteering:applySmoothness(current, target, smoothness, dt)
  if smoothness <= 0 then
    return target
  end

  local smoothingFactor = (1 - math.min(math.max(smoothness, 0.65), 0.85)) ^ 2
  local smoothing = 1 - math.exp(-smoothingFactor * dt / 16.67)

  return current + (target - current) * smoothing
end

function MouseSteering:getHudVisible()
  return self.hud:getHudVisible()
end

function MouseSteering:setHudTextVisible(visible)
  self.hud:setTextVisible(visible)
end

function MouseSteering:getMovedSide()
  return self.camera.movedSide
end

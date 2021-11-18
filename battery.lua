-- Dbus vars
local lgi = require("lgi")
local dbus = require("subsystem.dbus.lib")
local Gio = lgi.Gio

local power = {}
power.bus = dbus.SYSTEM
power.batteries = {}

function power.emitChargerInfo(state)
  awesome.emit_signal("subsystem::charger", not state)
end

function power.emitBatteryInfo(batteryId, data)
  awesome.emit_signal("subsystem::battery", batteryId, data)
end

function power.QueryInfo(data)
  local objects = data[1]
  for _, deviceId in ipairs(objects) do
    local batteryName = deviceId:match("battery_(.+)")
    if batteryName then
      power.batteries[deviceId] = { trackers = {} }

      power.batteries[deviceId].trackers["UPower.Device"] = power.tracker(deviceId, "org.freedesktop.UPower.Device", function(data)
        power.emitBatteryInfo(deviceId, data)
      end)

      power.batteries[deviceId].trackers["UPower"] = power.tracker("/org/freedesktop/UPower", "org.freedesktop.UPower", function(data)
        if data["OnBattery"] ~= nil then
          power.emitChargerInfo(data["OnBattery"])
        end
      end)
    end
  end
end

power.tracker = dbus.BuildPropertyTracker(
  power.bus,
  "org.freedesktop.UPower"
)

-- Query device list
power.bus:call(
  "org.freedesktop.UPower",
  "/org/freedesktop/UPower",
  "org.freedesktop.UPower",
  "EnumerateDevices",
  nil,
  nil,
  Gio.DBusCallFlags.NONE,
  -1,
  nil,
  dbus.unwrap(power.QueryInfo)
)

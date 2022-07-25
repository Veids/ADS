-- Dbus vars
local lgi = require("lgi")
local dbus = require("subsystem.dbus.lib")
local Gio = lgi.Gio
local gears = require("gears")

local power = {}
power.bus = dbus.SYSTEM
power.batteries = {}

local charger_is_tracked = false

function power.emitChargerInfo(state)
  awesome.emit_signal("subsystem::charger", not state)
end

function power.emitBatteryInfo(updateType, devicePath, data)
  awesome.emit_signal("subsystem::battery", updateType, devicePath, data)
end

function power.QueryDevice(devicePath)
  local batteryName = devicePath:match("battery_(.+)")
  if batteryName then
    power.batteries[devicePath] = { trackers = {} }

    if not charger_is_tracked then
      power.batteries[devicePath].trackers["UPower"] = power.tracker("/org/freedesktop/UPower", "org.freedesktop.UPower", function(data)
        if data["OnBattery"] ~= nil then
          power.emitChargerInfo(data["OnBattery"])
        end
      end)
    end

    power.batteries[devicePath].trackers["UPower.Device"] = power.tracker(devicePath, "org.freedesktop.UPower.Device", function(data)
      power.emitBatteryInfo("update", devicePath, data)
    end)
  end
end

function power.QueryDevices(data)
  local objects = data[1]
  for _, devicePath in ipairs(objects) do
    power.QueryDevice(devicePath)
  end
end

function power.DeviceAdded(conn, sender, devicePath, interface_name, signal_name, user_data)
  local devicePath = dbus.unpackVariant(user_data)[1]
  power.QueryDevice(devicePath)
end

function power.DeviceRemoved(conn, sender, _, interface_name, signal_name, user_data)
  local devicePath = dbus.unpackVariant(user_data)[1]
  power.emitBatteryInfo("remove", devicePath, nil)
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
  dbus.unwrap(power.QueryDevices)
)

power.bus:signal_subscribe(
  "org.freedesktop.UPower",
  "org.freedesktop.UPower",
  "DeviceAdded",
  "/org/freedesktop/UPower",
  nil,
  Gio.DBusSignalFlags.NONE,
  power.DeviceAdded
)

power.bus:signal_subscribe(
  "org.freedesktop.UPower",
  "org.freedesktop.UPower",
  "DeviceRemoved",
  "/org/freedesktop/UPower",
  nil,
  Gio.DBusSignalFlags.NONE,
  power.DeviceRemoved
)

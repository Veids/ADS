local gears = require("gears")

-- Dbus vars
local lgi = require("lgi")
local dbus = require("subsystem.dbus.lib")
local GLib = lgi.GLib
local Gio = lgi.Gio

local network = {
  bus = dbus.SYSTEM,
  devices = {
    wifi = {},
    wired = {}
  },
  -- Supp functions
  wifi = {},
  wired = {},
}

local devicesTypes = {
  [1] = "Ethernet",
  [2] = "Wifi",
  [29] = "WireGuard"
}

-- ===================================================================
-- Common functions

function network.PropertyTrackerCallback_ng(devicePath, deviceType, tracker_name, object, data, field, destroyCallback)
  local config = data[field]
  if config ~= nil then
    if network.devices[deviceType][devicePath].trackers[tracker_name] ~= nil then
      network.devices[deviceType][devicePath].trackers[tracker_name].stop()
    end

    if config ~= "/" then
      network.devices[deviceType][devicePath].trackers[tracker_name] = network.tracker(config, object, function(data_n)
        network[deviceType].emitInfo(devicePath, tracker_name, data_n)
      end)
    elseif destroyCallback ~= nil then
      destroyCallback()
    end
  end
end

-- ===================================================================
-- Wifi functions

function network.wifi.emitInfo(devicePath, changeType, data)
  awesome.emit_signal(
    "subsystem::wifi",
    devicePath,
    changeType,
    data
  )
end

function network.DeviceRemoved(conn, sender, _, interface_name, signal_name, user_data)
  local data = dbus.unpackVariant(user_data)

  local devicePath = data[1]
  if devicePath == nil then
    gears.debug.print_error(string.format(
      "DevicePath is nil on network.DeviceRemoved\n%s\n%s",
      gears.debug.dump_return(data),
      debug.traceback())
    )
    return
  end

  for devType, devs in pairs(network.devices) do
    if devs[devicePath] ~= nil then
      local device = devs[devicePath]
      devs[devicePath] = nil

      for _, v in pairs(device.trackers) do
        v.stop()
      end

      network[devType].emitInfo(devicePath, "Destroy")
      break
    end
  end
end

function network.wifi.HandleDevice(devicePath)
  network.devices.wifi[devicePath] = {
    trackers = {},
  }

  network.devices.wifi[devicePath].trackers["Dev"] = network.tracker(
    devicePath,
    "org.freedesktop.NetworkManager.Device",
    function(data)
      network.PropertyTrackerCallback_ng(devicePath, "wifi", "IP4Config", "org.freedesktop.NetworkManager.IP4Config", data, "Ip4Config", function()
        network.wifi.emitInfo(devicePath, "Discard IP4Config")
      end)
      network.wifi.emitInfo(devicePath, "Dev", data)
    end
  )

  network.devices.wifi[devicePath].trackers["DevWireless"] = network.tracker(
    devicePath,
    "org.freedesktop.NetworkManager.Device.Wireless",
    function(data)
      network.PropertyTrackerCallback_ng(devicePath, "wifi", "AP", "org.freedesktop.NetworkManager.AccessPoint", data, "ActiveAccessPoint")
      network.wifi.emitInfo(devicePath, "Dev", data)
    end
  )
  end

-- Wifi functions END
-- ===================================================================

-- Ethernet functions
-- ===================================================================

function network.wired.emitInfo(devicePath, changeType, data)
  awesome.emit_signal(
    "subsystem::wired",
    devicePath,
    changeType,
    data
  )
end

function network.wired.HandleDevice(devicePath)
  network.devices.wired[devicePath] = {
    trackers = {},
  }

  network.devices.wired[devicePath].trackers["Dev"] = network.tracker(devicePath, "org.freedesktop.NetworkManager.Device", function(data)
    network.wired.emitInfo(devicePath, "Dev", data)
  end)

  network.devices.wired[devicePath].trackers["Dev.Wired"] = network.tracker(
    devicePath,
    "org.freedesktop.NetworkManager.Device.Wired",
    function(data)
      network.PropertyTrackerCallback_ng(devicePath, "wired", "org.freedesktop.NetworkManager.IP4Config", data, "Ip4Config", function()
        network.devices.wired[devicePath].emitInfo(devicePath, "Discard IP4Config")
      end)
      network.wired.emitInfo(devicePath, "Dev", data)
    end
  )
end

-- Ethernet functions END
-- ===================================================================

function network.HandleDevices(devicePath, data)
  local deviceTypeId = data[1]
  local deviceTypeStr = devicesTypes[deviceTypeId]
  if deviceTypeStr == "Wifi" then
    network.wifi.HandleDevice(devicePath)
  elseif deviceTypeStr == "Ethernet" then
    network.wired.HandleDevice(devicePath)
  end
end

function network.DeviceAdded(conn, sender, devicePath, interface_name, signal_name, user_data)
  local devicePath = dbus.unpackVariant(user_data)[1]
  network.QueryDevices({dev = devicePath})
end

-- Query Device Type
function network.QueryDevices(devices)
  for _, device in ipairs(devices) do
    network.bus:call(
      "org.freedesktop.NetworkManager",
      device,
      "org.freedesktop.DBus.Properties",
      "Get",
      GLib.Variant("(ss)",
      {
        "org.freedesktop.NetworkManager.Device",
        "DeviceType"
      }),
      nil,
      Gio.DBusCallFlags.NONE,
      -1,
      nil,
      dbus.unwrap(function(data)
        network.HandleDevices(device, data)
      end)
    )
  end
end

network.tracker = dbus.BuildPropertyTracker(
  network.bus,
  "org.freedesktop.NetworkManager"
)

-- Query device list
network.bus:call(
  "org.freedesktop.NetworkManager",
  "/org/freedesktop/NetworkManager",
  "org.freedesktop.NetworkManager",
  "GetDevices",
  nil,
  nil,
  Gio.DBusCallFlags.NONE,
  -1,
  nil,
  dbus.unwrap(function(devices)
    network.QueryDevices(devices[1])
  end)
)

network.bus:signal_subscribe(
    "org.freedesktop.NetworkManager",
    "org.freedesktop.NetworkManager",
    "DeviceAdded",
    "/org/freedesktop/NetworkManager",
    nil,
    Gio.DBusSignalFlags.NONE,
    network.DeviceAdded
)

network.bus:signal_subscribe(
    "org.freedesktop.NetworkManager",
    "org.freedesktop.NetworkManager",
    "DeviceRemoved",
    "/org/freedesktop/NetworkManager",
    nil,
    Gio.DBusSignalFlags.NONE,
    network.DeviceRemoved
)

return network

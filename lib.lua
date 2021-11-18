local lgi = require("lgi")
local Gio = lgi.Gio
local GLib = lgi.GLib
local GObject = lgi.GObject
local gears = require("gears")

local bus = {}
bus.SYSTEM = Gio.bus_get_sync(Gio.BusType.SYSTEM)
bus.SESSION = Gio.bus_get_sync(Gio.BusType.SESSION)

function bus.unpackVariant(v)
  if not tostring(v):find("GLib%.Variant$") then
    if type(v) == "table" and #v > 0 then
      -- Strip the 'n' field from pure arrays.
      -- This is found in nested tuples.
      v.n = nil
    end
    return v
  end

  if v:is_container() and not v:is_of_type(lgi.GLib.VariantType.VARIANT) then
    local out = {}
    local n_children = v:n_children()
    local idx = 0

    local is_dict = v:is_of_type(lgi.GLib.VariantType.DICTIONARY)
    while idx < n_children do
      local val = v:get_child_value(idx)
      idx = idx + 1
      if is_dict then
        local key = val[1]
        local value = bus.unpackVariant(val[2])
        out[key] = bus.unpackVariant(value)
      else
        local rdx = bus.unpackVariant(val)
        out[idx] = rdx
      end
    end

    return out
  else
    return bus.unpackVariant(v.value)
  end

end

function bus.QueryDeviceProperties(busId, provider, devicePath, interface, callback)
  busId:call(
    provider,
    devicePath,
    "org.freedesktop.DBus.Properties",
    "GetAll",
    GLib.Variant("(s)",
    {
      interface
    }),
    nil,
    Gio.DBusCallFlags.NONE,
    -1,
    nil,
    bus.unwrap(function(data, err)
      if err ~= nil then
        callback(devicePath, err)
      else
        callback(devicePath, data[1])
      end
    end)
  )
end

local function dataReady(data)
  for i = 1, #data do
    if data[i] == false then
      return false
    end
  end
  return true
end

function bus.BuildPropertyTracker(targetBus, provider)
  local function wrapper(object_path, interface, queryCallback, trackCallback)
    if trackCallback == nil then
      trackCallback = queryCallback
    end

    if type(interface) ~= "table" then
      interface = {interface}
    end

    local trackDb = {
      stop = nil,
      sub_id = nil,
      data_ready = {},
      data = {}
    }

    local function track(_, _, _, _, _, user_data)
      local data = bus.unpackVariant(user_data)[2]
      local err, msg = pcall(trackCallback, data)
      if not err then
        gears.debug.print_error("Error calling dbus callback, " .. msg)
      end
    end

    local function process_query(idx, data)
      trackDb.data[idx] = data
      trackDb.data_ready[idx] = true

      if dataReady(trackDb.data_ready) then
        if #trackDb.data_ready == 1 then
          trackDb.data = trackDb.data[1]
        end

        local err, msg = pcall(queryCallback, trackDb.data)
        if not err then
          gears.debug.print_error("Error calling dbus callback, " .. msg)
        end

        trackDb.sub_id = targetBus:signal_subscribe(
          provider,
          "org.freedesktop.DBus.Properties",
          "PropertiesChanged",
          object_path,
          nil,
          Gio.DBusSignalFlags.NONE,
          track
        )
      end
    end

    trackDb.stop = function()
      if trackDb.sub_id ~= nil then
        targetBus:signal_unsubscribe(trackDb.sub_id)
      else
        gears.debug.print_error("Err: trackDb.sub_id is nil\n" .. debug.traceback())
      end
    end

    for i = 1, #interface do
      trackDb.data_ready[i] = false
    end

    for i = 1, #interface do
      bus.QueryDeviceProperties(targetBus, provider, object_path, interface[i], function(_, data)
        process_query(i, data)
      end)
    end
  end

  return wrapper
end

function bus.unwrap(callback)
  local function wrapper(conn, res)
    local data, err = conn:call_finish(res)
    if err then
      callback(nil, err)
    else
      callback(bus.unpackVariant(data))
    end
  end
  return wrapper
end

return bus

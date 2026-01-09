const std = @import("std");
const c = @cImport({
    @cInclude("libevdev/libevdev.h");
    @cInclude("libevdev/libevdev-uinput.h");
});

const Allocator = std.mem.Allocator;
const Io = std.Io;
const ArrayList = std.ArrayList;

const usage_text =
    \\Usage: caps2esc [options]
    \\
    \\Remap CapsLock to Esc
    \\
    \\Options:
    \\  -l, --list-devices            list available devices
    \\  -d, --device <device-name>    device name
    \\  -h, --help
    \\
;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buf);
    const stdout = &stdout_writer.interface;

    // parse args - just once
    const args = try init.minimal.args.toSlice(arena);
    if (args.len <= 1) {
        try stdout.writeAll(usage_text);
        try stdout.flush();
        return std.process.cleanExit(io);
    }
    if (std.mem.eql(u8, args[1], "-h") or std.mem.eql(u8, args[1], "--help")) {
        try stdout.writeAll(usage_text);
    } else if (std.mem.eql(u8, args[1], "-l") or std.mem.eql(u8, args[1], "--list-devices")) {
        try listDevices(arena, io, stdout);
    } else if (std.mem.eql(u8, args[1], "-d") or std.mem.eql(u8, args[1], "--device")) {
        if (args.len <= 2) {
            std.debug.print("'{s}' requires a device name\n", .{args[1]});
            std.process.exit(1);
        }
        try remap(arena, io, args[2]);
    } else {
        std.debug.print("unrecognized argument: '{s}'\n\n", .{args[1]});
        std.debug.print("{s}", .{usage_text});
        std.process.exit(1);
    }

    try stdout.flush();
}

fn remap(allocator: Allocator, io: Io, device_name: []const u8) !void {
    const device = (try getDeviceByName(allocator, io, device_name)) orelse {
        std.debug.print("Unable to find device with name: '{s}'!\n", .{device_name});
        std.process.exit(1);
    };

    const file = try std.Io.Dir.openFileAbsolute(io, device.path, .{});
    defer file.close(io);

    var dev: ?*c.struct_libevdev = null;
    if (c.libevdev_new_from_fd(file.handle, &dev) != 0) return error.DeviceCreationFailed;
    defer c.libevdev_free(dev);

    c.libevdev_set_name(dev, @ptrCast(try std.fmt.allocPrintSentinel(allocator, "caps2esc virtual input for '{s}'", .{device.path}, '\x00')));
    // if (c.libevdev_enable_event_code(dev, c.EV_KEY, c.KEY_ESC, null) != 0) return error.EventCodeEnablingFailed;

    var uinput_dev: ?*c.struct_libevdev_uinput = null;
    if (c.libevdev_uinput_create_from_device(dev, c.LIBEVDEV_UINPUT_OPEN_MANAGED, &uinput_dev) != 0) return error.UinputDeviceCreationFailed;
    defer c.libevdev_uinput_destroy(uinput_dev);

    // From libevdev docs: https://www.freedesktop.org/software/libevdev/doc/latest/group__init.html#ga5d434af74fee20f273db568e2cbbd13f
    // "Grab or ungrab the device through a kernel EVIOCGRAB.
    // This prevents other clients (including kernel-internal ones such as rfkill) from receiving events from this device.
    // This is generally a bad idea. Don't do this."
    if (c.libevdev_grab(dev, c.LIBEVDEV_GRAB) != 0) return error.DeviceGrabbingFailed;

    while (true) {
        var ev: c.struct_input_event = .{};

        switch (c.libevdev_next_event(dev, c.LIBEVDEV_READ_FLAG_NORMAL | c.LIBEVDEV_READ_FLAG_BLOCKING, &ev)) {
            c.LIBEVDEV_READ_STATUS_SUCCESS => {
                const code = if (ev.code == c.KEY_CAPSLOCK) @as(c_uint, c.KEY_ESC) else ev.code;
                if (c.libevdev_uinput_write_event(uinput_dev, ev.type, code, ev.value) != 0) return error.EventWritingFailed;
            },
            else => {
                return error.UnsuccessfulReadStatus;
            },
        }
    }
}

/// Get device info by its name.
fn getDeviceByName(allocator: Allocator, io: Io, device_name: []const u8) !?DeviceInfo {
    var device_list: ArrayList(DeviceInfo) = .empty;
    try getDevices(allocator, io, &device_list);

    for (device_list.items) |device| {
        if (std.mem.eql(u8, device_name, device.name)) return device;
    }

    return null;
}

/// List all the devices to stdout.
fn listDevices(allocator: Allocator, io: Io, stdout: *Io.Writer) !void {
    var device_list: ArrayList(DeviceInfo) = .empty;
    try getDevices(allocator, io, &device_list);

    for (device_list.items) |device| {
        try stdout.print("name: {s}\npath: {s}\n\n", .{
            device.name,
            device.path,
        });
    }
}

/// Get all Device details from `/dev/input/`.
fn getDevices(allocator: Allocator, io: Io, device_list: *ArrayList(DeviceInfo)) !void {
    const device_dir = "/dev/input/";

    var devices = try Io.Dir.openDirAbsolute(io, device_dir, .{ .iterate = true });
    defer devices.close(io);
    var device_it = devices.iterate();

    while (try device_it.next(io)) |it| {
        if (it.kind == .directory) continue;
        if (!std.mem.startsWith(u8, it.name, "event")) continue;

        const filename = try std.fs.path.join(allocator, &.{ device_dir, it.name });
        const device = try DeviceInfo.fromFile(allocator, io, filename);
        try device_list.append(allocator, device);
    }
}

const DeviceInfo = struct {
    name: []const u8,
    path: []const u8,

    /// Get Device Info from the given file.
    fn fromFile(allocator: Allocator, io: Io, filename: []const u8) !DeviceInfo {
        const file = try std.Io.Dir.openFileAbsolute(io, filename, .{});
        defer file.close(io);

        var dev: ?*c.struct_libevdev = null;
        if (c.libevdev_new_from_fd(file.handle, &dev) != 0) return error.DeviceCreationFailed;
        defer c.libevdev_free(dev);

        const device_name = c.libevdev_get_name(dev) orelse @as([*c]const u8, "");

        return .{
            .name = try allocator.dupe(u8, std.mem.span(device_name)),
            .path = filename,
        };
    }
};

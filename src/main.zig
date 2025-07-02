const std = @import("std");
const objc = @import("objc.zig");
const config = @import("config.zig");
const window_manager = @import("window_manager.zig");
const c = @cImport({
    @cInclude("CoreFoundation/CoreFoundation.h");
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1) {
        if (std.mem.eql(u8, args[1], "version")) {
            std.debug.print("space-borders 0.1.0\n", .{});
            return;
        } else if (std.mem.eql(u8, args[1], "help")) {
            printHelp();
            return;
        }
    }

    const config_path = try config.Config.getConfigPath(allocator);
    defer allocator.free(config_path);

    var cfg = config.Config.load(allocator, config_path) catch |err| blk: {
        if (err == error.FileNotFound) {
            std.debug.print("Creating default config at {s}\n", .{config_path});
            const default_config = config.Config{};
            try default_config.save(config_path);
            break :blk default_config;
        }
        return err;
    };

    std.debug.print("Starting space-borders...\n", .{});
    std.debug.print("Config loaded from: {s}\n", .{config_path});

    const ns_app_class = objc.getClass("NSApplication").?;
    const app = objc.msgSend(@as(objc.id, @ptrCast(@alignCast(ns_app_class))), objc.sel("sharedApplication"), objc.id);

    objc.msgSendWithArgs(app, objc.sel("setActivationPolicy:"), .{@as(objc.NSInteger, 2)}, void);

    var wm = window_manager.WindowManager.init(allocator, &cfg);
    defer wm.deinit();

    try wm.start();

    std.debug.print("Space-borders is running. Press Ctrl+C to stop.\n", .{});

    c.CFRunLoopRun();
}

fn printHelp() void {
    std.debug.print(
        \\space-borders - Window border management tool for macOS
        \\
        \\Usage:
        \\  space-borders              Start the border service
        \\  space-borders version      Show version information
        \\  space-borders help         Show this help message
        \\
        \\Configuration:
        \\  Config file: ~/.config/space-borders/config.json
        \\
        \\  Example config:
        \\  {{
        \\    "border_width": 2.0,
        \\    "border_radius": 8.0,
        \\    "active_color": {{ "r": 0.0, "g": 0.5, "b": 1.0, "a": 1.0 }},
        \\    "inactive_color": {{ "r": 0.5, "g": 0.5, "b": 0.5, "a": 0.5 }},
        \\    "animation_duration": 0.15,
        \\    "enabled": true
        \\  }}
        \\
    , .{});
}

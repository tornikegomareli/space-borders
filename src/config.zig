const std = @import("std");

pub const Config = struct {
    border_width: f32 = 2.0,
    border_radius: f32 = 8.0,
    active_color: Color = .{ .r = 0.0, .g = 0.5, .b = 1.0, .a = 1.0 },
    inactive_color: Color = .{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 0.5 },
    animation_duration: f32 = 0.15,
    enabled: bool = true,

    pub const Color = struct {
        r: f32,
        g: f32,
        b: f32,
        a: f32,
    };

    pub fn load(allocator: std.mem.Allocator, path: []const u8) !Config {
        const file = std.fs.openFileAbsolute(path, .{}) catch |err| switch (err) {
            error.FileNotFound => return Config{},
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(content);
        
        const parsed = try std.json.parseFromSlice(Config, allocator, content, .{});
        defer parsed.deinit();

        return parsed.value;
    }

    pub fn save(self: Config, path: []const u8) !void {
        const file = try std.fs.createFileAbsolute(path, .{});
        defer file.close();

        var buffer: [4096]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const allocator = fba.allocator();

        const json = try std.json.stringifyAlloc(allocator, self, .{ .whitespace = .indent_4 });
        defer allocator.free(json);

        try file.writeAll(json);
    }

    pub fn getConfigPath(allocator: std.mem.Allocator) ![]u8 {
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
            return error.NoHomeDirectory;
        };
        defer allocator.free(home);
        const config_dir = try std.fs.path.join(allocator, &.{ home, ".config", "space-borders" });
        defer allocator.free(config_dir);
        std.fs.makeDirAbsolute(config_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        return try std.fs.path.join(allocator, &.{ config_dir, "config.json" });
    }
};

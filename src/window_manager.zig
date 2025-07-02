const std = @import("std");
const objc = @import("objc.zig");
const ax = @import("accessibility.zig");
const config = @import("config.zig");
const c = @cImport({
    @cInclude("CoreGraphics/CoreGraphics.h");
    @cInclude("ApplicationServices/ApplicationServices.h");
});

pub const WindowInfo = struct {
    pid: ax.pid_t,
    window_ref: ax.AXUIElementRef,
    position: objc.NSPoint,
    size: objc.NSSize,
    is_focused: bool,
    border_window: ?objc.id = null,
};

pub const WindowManager = struct {
    allocator: std.mem.Allocator,
    windows: std.ArrayList(WindowInfo),
    config: *config.Config,
    observers: std.ArrayList(ax.AXObserverRef),
    
    pub fn init(allocator: std.mem.Allocator, cfg: *config.Config) WindowManager {
        return .{
            .allocator = allocator,
            .windows = std.ArrayList(WindowInfo).init(allocator),
            .config = cfg,
            .observers = std.ArrayList(ax.AXObserverRef).init(allocator),
        };
    }
    
    pub fn deinit(self: *WindowManager) void {
        for (self.windows.items) |window| {
            if (window.border_window) |border| {
                objc.msgSend(border, objc.sel("close"), void);
                objc.release(border);
            }
        }
        self.windows.deinit();
        
        for (self.observers.items) |observer| {
            c.CFRelease(@as(c.CFTypeRef, @ptrCast(observer)));
        }
        self.observers.deinit();
    }
    
    pub fn start(self: *WindowManager) !void {
        if (!ax.isAccessibilityEnabled()) {
            std.debug.print("Accessibility permissions required. Please enable in System Preferences.\n", .{});
            return error.AccessibilityNotEnabled;
        }
        
        try self.scanAllWindows();
        try self.setupObservers();
    }
    
    fn scanAllWindows(self: *WindowManager) !void {
        const workspace_class = objc.getClass("NSWorkspace").?;
        const workspace = objc.msgSend(@as(objc.id, @ptrCast(@alignCast(workspace_class))), objc.sel("sharedWorkspace"), objc.id);
        const running_apps = objc.msgSend(workspace, objc.sel("runningApplications"), objc.id);
        
        const count = objc.msgSend(running_apps, objc.sel("count"), objc.NSUInteger);
        var i: objc.NSUInteger = 0;
        while (i < count) : (i += 1) {
            const app = objc.msgSendWithArgs(running_apps, objc.sel("objectAtIndex:"), .{i}, objc.id);
            const pid = objc.msgSend(app, objc.sel("processIdentifier"), ax.pid_t);
            
            if (pid > 0) {
                try self.scanWindowsForPID(pid);
            }
       }
    }
    
    fn scanWindowsForPID(self: *WindowManager, pid: ax.pid_t) !void {
        const app_element = ax.createApplicationElement(pid);
        defer c.CFRelease(@as(c.CFTypeRef, @ptrCast(app_element)));
        
        var windows_value: c.CFTypeRef = undefined;
        const result = ax.copyAttributeValue(app_element, ax.kAXWindowsAttribute, &windows_value);
        if (result != ax.kAXErrorSuccess) return;
        defer c.CFRelease(windows_value);
        
        const windows_array = @as(ax.CFArrayRef, @ptrCast(windows_value));
        const window_count = c.CFArrayGetCount(windows_array);
        
        var i: c.CFIndex = 0;
        while (i < window_count) : (i += 1) {
            const window = c.CFArrayGetValueAtIndex(windows_array, i);
            const window_element = @as(ax.AXUIElementRef, @ptrCast(@alignCast(window)));
            
            var window_info = WindowInfo{
                .pid = pid,
                .window_ref = window_element,
                .position = .{ .x = 0, .y = 0 },
                .size = .{ .width = 0, .height = 0 },
                .is_focused = false,
            };
            
            c.CFRetain(@as(c.CFTypeRef, @ptrCast(window_element)));
            
            self.updateWindowGeometry(&window_info);
            
            try self.windows.append(window_info);
            try self.createBorderForWindow(&window_info);
        }
    }
    
    fn updateWindowGeometry(self: *WindowManager, window: *WindowInfo) void {
        _ = self;
        
        var position_value: c.CFTypeRef = undefined;
        if (ax.copyAttributeValue(window.window_ref, ax.kAXPositionAttribute, &position_value) == ax.kAXErrorSuccess) {
            defer c.CFRelease(position_value);
            
            var point: c.CGPoint = undefined;
            _ = c.AXValueGetValue(@as(c.AXValueRef, @ptrCast(position_value)), c.kAXValueCGPointType, &point);
            window.position = .{ .x = point.x, .y = point.y };
        }
        
        var size_value: c.CFTypeRef = undefined;
        if (ax.copyAttributeValue(window.window_ref, ax.kAXSizeAttribute, &size_value) == ax.kAXErrorSuccess) {
            defer c.CFRelease(size_value);
            
            var size: c.CGSize = undefined;
            _ = c.AXValueGetValue(@as(c.AXValueRef, @ptrCast(size_value)), c.kAXValueCGSizeType, &size);
            window.size = .{ .width = size.width, .height = size.height };
        }
    }
    
    fn createBorderForWindow(self: *WindowManager, window: *WindowInfo) !void {
        const NSWindow = objc.getClass("NSWindow").?;
        const NSColor = objc.getClass("NSColor").?;
        
        const style_mask: objc.NSUInteger = 1 << 15; // NSWindowStyleMaskBorderless
        const backing_store: objc.NSInteger = 2; // NSBackingStoreBuffered
        
        const frame = objc.NSRect{
            .origin = window.position,
            .size = window.size,
        };
        
        const border_window = objc.msgSendWithArgs(
            objc.alloc(NSWindow),
            objc.sel("initWithContentRect:styleMask:backing:defer:"),
            .{ frame, style_mask, backing_store, objc.NO },
            objc.id
        );
        
        objc.msgSendWithArgs(border_window, objc.sel("setOpaque:"), .{objc.NO}, void);
        objc.msgSendWithArgs(border_window, objc.sel("setHasShadow:"), .{objc.NO}, void);
        objc.msgSendWithArgs(border_window, objc.sel("setLevel:"), .{@as(objc.NSInteger, 25)}, void); // NSFloatingWindowLevel
        objc.msgSendWithArgs(border_window, objc.sel("setIgnoresMouseEvents:"), .{objc.YES}, void);
        objc.msgSendWithArgs(border_window, objc.sel("setCollectionBehavior:"), .{@as(objc.NSUInteger, 1 << 0 | 1 << 3)}, void);
        
        const clear_color = objc.msgSend(@as(objc.id, @ptrCast(NSColor)), objc.sel("clearColor"), objc.id);
        objc.msgSendWithArgs(border_window, objc.sel("setBackgroundColor:"), .{clear_color}, void);
        
        objc.msgSend(border_window, objc.sel("makeKeyAndOrderFront:"), void);
        
        window.border_window = border_window;
        self.updateBorderAppearance(window);
    }
    
    fn updateBorderAppearance(self: *WindowManager, window: *WindowInfo) void {
        if (window.border_window) |border| {
            const color = if (window.is_focused) self.config.active_color else self.config.inactive_color;
            
            _ = border;
            _ = color;
        }
    }
    
    fn setupObservers(self: *WindowManager) !void {
        _ = self;
    }
};

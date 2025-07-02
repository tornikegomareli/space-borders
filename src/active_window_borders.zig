const std = @import("std");
const c = @cImport({
    @cInclude("ApplicationServices/ApplicationServices.h");
    @cInclude("CoreGraphics/CoreGraphics.h");
    @cInclude("CoreVideo/CoreVideo.h");
    @cInclude("dispatch/dispatch.h");
    @cInclude("objc/runtime.h");
    @cInclude("objc/message.h");
});

const msgSend = @extern(*const fn (c.id, c.SEL) callconv(.C) c.id, .{ .name = "objc_msgSend" });

fn msg(receiver: c.id, selector: [*:0]const u8) c.id {
    return msgSend(receiver, c.sel_registerName(selector));
}

const WindowInfo = struct {
    window_id: u32,
    border_window: c.id,
    pid: c.pid_t,
    last_bounds: c.CGRect,
    target_bounds: c.CGRect,
    current_bounds: c.CGRect,
    animation_start: f64 = 0,
    needs_update: bool = false,
    is_visible: bool = true,
    was_visible: bool = true,
    is_active: bool = false,
    was_active: bool = false,
    app_name: [256]u8 = undefined,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator: std.mem.Allocator = undefined;
var windows: std.AutoHashMap(u32, WindowInfo) = undefined;
var windows_mutex: std.Thread.Mutex = .{};
var screen_height: f64 = 0;
var display_link: c.CVDisplayLinkRef = null;
var current_active_window_id: ?u32 = null;

const ANIMATION_DURATION: f64 = 0.15;
const BORDER_WIDTH: f64 = 2.0;
const BORDER_RADIUS: f64 = 8.0;

// Border colors
const ACTIVE_COLOR = struct {
    const r: f64 = 0.2;
    const g: f64 = 0.6;
    const b: f64 = 1.0;
    const a: f64 = 1.0;
};

pub fn main() !void {
    defer _ = gpa.deinit();
    allocator = gpa.allocator();
    
    windows = std.AutoHashMap(u32, WindowInfo).init(allocator);
    defer windows.deinit();
    
    std.debug.print("Space Borders - Active Window Focus\n", .{});
    std.debug.print("===================================\n", .{});
    
    // Check accessibility
    const trusted = c.AXIsProcessTrustedWithOptions(null);
    if (trusted == 0) {
        std.debug.print("ERROR: Accessibility permissions required!\n", .{});
        std.debug.print("Please grant access in System Settings > Privacy & Security > Accessibility\n", .{});
        return error.AccessibilityNotEnabled;
    }
    
    // Initialize NSApplication
    const NSApp = c.objc_getClass("NSApplication");
    if (NSApp == null) return error.ClassNotFound;
    
    const app = msg(@ptrCast(@alignCast(NSApp)), "sharedApplication");
    const setActivationPolicy = @extern(*const fn (c.id, c.SEL, isize) callconv(.C) void, .{ .name = "objc_msgSend" });
    setActivationPolicy(app, c.sel_registerName("setActivationPolicy:"), 1);
    
    // Get screen info
    const main_display = c.CGMainDisplayID();
    const screen_bounds = c.CGDisplayBounds(main_display);
    screen_height = screen_bounds.size.height;
    
    // Initial scan
    try scanAndCreateBorders();
    
    // Create CVDisplayLink for smooth 60fps updates
    const result = c.CVDisplayLinkCreateWithActiveCGDisplays(&display_link);
    if (result != c.kCVReturnSuccess) {
        return error.DisplayLinkCreationFailed;
    }
    defer {
        _ = c.CVDisplayLinkStop(display_link);
        c.CVDisplayLinkRelease(display_link);
    }
    
    // Set callback
    _ = c.CVDisplayLinkSetOutputCallback(display_link, displayLinkCallback, null);
    _ = c.CVDisplayLinkStart(display_link);
    
    // Set up main thread timer for UI updates
    const NSTimer = c.objc_getClass("NSTimer") orelse return error.ClassNotFound;
    const scheduledTimer = @extern(*const fn (c.id, c.SEL, f64, c.id, c.SEL, c.id, u8) callconv(.C) c.id, .{ .name = "objc_msgSend" });
    
    const timer_class = createTimerHandlerClass() orelse return error.ClassCreationFailed;
    const timer_handler = msg(@ptrCast(@alignCast(timer_class)), "new");
    
    _ = scheduledTimer(
        @ptrCast(@alignCast(NSTimer)),
        c.sel_registerName("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"),
        1.0 / 60.0, // 60fps on main thread
        timer_handler,
        c.sel_registerName("timerFired:"),
        @as(c.id, @ptrFromInt(0)),
        1 // YES - repeat
    );
    
    std.debug.print("\nMonitoring active window. Press Ctrl+C to exit.\n", .{});
    
    // Run the application
    const run = @extern(*const fn (c.id, c.SEL) callconv(.C) void, .{ .name = "objc_msgSend" });
    run(app, c.sel_registerName("run"));
}

fn displayLinkCallback(
    displayLink: c.CVDisplayLinkRef,
    inNow: [*c]const c.CVTimeStamp,
    inOutputTime: [*c]const c.CVTimeStamp,
    flagsIn: c.CVOptionFlags,
    flagsOut: [*c]c.CVOptionFlags,
    displayLinkContext: ?*anyopaque,
) callconv(.C) c.CVReturn {
    _ = displayLink;
    _ = inNow;
    _ = inOutputTime;
    _ = flagsIn;
    _ = flagsOut;
    _ = displayLinkContext;
    
    updateWindowStates() catch {};
    
    return c.kCVReturnSuccess;
}

fn createTimerHandlerClass() ?c.Class {
    const NSObject = c.objc_getClass("NSObject") orelse return null;
    
    const TimerHandler = struct {
        fn timerFired(self: c.id, cmd: c.SEL, timer: c.id) callconv(.C) void {
            _ = self;
            _ = cmd;
            _ = timer;
            
            updateBordersOnMainThread() catch {};
        }
    };
    
    const class = c.objc_allocateClassPair(NSObject, "SpaceBordersTimerHandler", 0) orelse return null;
    
    const timer_impl = @as(c.IMP, @ptrCast(&TimerHandler.timerFired));
    _ = c.class_addMethod(class, c.sel_registerName("timerFired:"), timer_impl, "v@:@");
    
    c.objc_registerClassPair(class);
    return class;
}

fn getCurrentTime() f64 {
    return @as(f64, @floatFromInt(std.time.milliTimestamp())) / 1000.0;
}

fn easeOutCubic(t: f64) f64 {
    const t1 = t - 1.0;
    return t1 * t1 * t1 + 1.0;
}

fn interpolateRect(from: c.CGRect, to: c.CGRect, progress: f64) c.CGRect {
    const p = easeOutCubic(progress);
    return c.CGRectMake(
        from.origin.x + (to.origin.x - from.origin.x) * p,
        from.origin.y + (to.origin.y - from.origin.y) * p,
        from.size.width + (to.size.width - from.size.width) * p,
        from.size.height + (to.size.height - from.size.height) * p
    );
}

fn getActiveWindowId() ?u32 {
    // Get the frontmost application
    const NSWorkspace = c.objc_getClass("NSWorkspace") orelse return null;
    const workspace = msg(@ptrCast(@alignCast(NSWorkspace)), "sharedWorkspace");
    const frontApp = msg(workspace, "frontmostApplication");
    
    if (frontApp == null) return null;
    
    const getPid = @extern(*const fn (c.id, c.SEL) callconv(.C) c.pid_t, .{ .name = "objc_msgSend" });
    const pid = getPid(frontApp, c.sel_registerName("processIdentifier"));
    
    // Get windows for this PID and find the focused one
    const window_list = c.CGWindowListCopyWindowInfo(
        c.kCGWindowListOptionOnScreenOnly | c.kCGWindowListExcludeDesktopElements,
        c.kCGNullWindowID
    ) orelse return null;
    defer c.CFRelease(@ptrCast(window_list));
    
    const count = c.CFArrayGetCount(window_list);
    var i: c.CFIndex = 0;
    while (i < count) : (i += 1) {
        const window_dict = c.CFArrayGetValueAtIndex(window_list, i);
        if (window_dict == null) continue;
        
        const window_pid_ref = c.CFDictionaryGetValue(
            @ptrCast(window_dict),
            @ptrCast(c.kCGWindowOwnerPID)
        );
        
        const window_id_ref = c.CFDictionaryGetValue(
            @ptrCast(window_dict),
            @ptrCast(c.kCGWindowNumber)
        );
        
        const layer_ref = c.CFDictionaryGetValue(
            @ptrCast(window_dict),
            @ptrCast(c.kCGWindowLayer)
        );
        
        if (window_pid_ref != null and window_id_ref != null and layer_ref != null) {
            var window_pid: i64 = 0;
            _ = c.CFNumberGetValue(@ptrCast(window_pid_ref), c.kCFNumberSInt64Type, &window_pid);
            
            var layer: i64 = 0;
            _ = c.CFNumberGetValue(@ptrCast(layer_ref), c.kCFNumberSInt64Type, &layer);
            
            if (window_pid == pid and layer == 0) {
                var window_id: i64 = 0;
                _ = c.CFNumberGetValue(@ptrCast(window_id_ref), c.kCFNumberSInt64Type, &window_id);
                return @intCast(window_id);
            }
        }
    }
    
    return null;
}

fn scanAndCreateBorders() !void {
    windows_mutex.lock();
    defer windows_mutex.unlock();
    
    // Clear existing borders
    var iter = windows.iterator();
    while (iter.next()) |entry| {
        closeBorderWindow(entry.value_ptr.border_window);
    }
    windows.clearAndFree();
    
    // Get window list
    const window_list = c.CGWindowListCopyWindowInfo(
        c.kCGWindowListOptionAll,
        c.kCGNullWindowID
    ) orelse return;
    defer c.CFRelease(@ptrCast(window_list));
    
    const count = c.CFArrayGetCount(window_list);
    
    // Get current active window
    current_active_window_id = getActiveWindowId();
    
    var i: c.CFIndex = 0;
    while (i < count) : (i += 1) {
        const window_dict = c.CFArrayGetValueAtIndex(window_list, i);
        if (window_dict == null) continue;
        
        const window_id_ref = c.CFDictionaryGetValue(
            @ptrCast(window_dict),
            @ptrCast(c.kCGWindowNumber)
        );
        
        const bounds_dict = c.CFDictionaryGetValue(
            @ptrCast(window_dict),
            @ptrCast(c.kCGWindowBounds)
        );
        
        const layer_ref = c.CFDictionaryGetValue(
            @ptrCast(window_dict),
            @ptrCast(c.kCGWindowLayer)
        );
        
        const pid_ref = c.CFDictionaryGetValue(
            @ptrCast(window_dict),
            @ptrCast(c.kCGWindowOwnerPID)
        );
        
        const on_screen_ref = c.CFDictionaryGetValue(
            @ptrCast(window_dict),
            @ptrCast(c.kCGWindowIsOnscreen)
        );
        
        const owner_ref = c.CFDictionaryGetValue(
            @ptrCast(window_dict),
            @ptrCast(c.kCGWindowOwnerName)
        );
        
        if (window_id_ref != null and bounds_dict != null and layer_ref != null and pid_ref != null) {
            var window_id: i64 = 0;
            _ = c.CFNumberGetValue(@ptrCast(window_id_ref), c.kCFNumberSInt64Type, &window_id);
            
            var bounds: c.CGRect = undefined;
            if (!c.CGRectMakeWithDictionaryRepresentation(@ptrCast(bounds_dict), &bounds)) continue;
            
            var layer: i64 = 0;
            _ = c.CFNumberGetValue(@ptrCast(layer_ref), c.kCFNumberSInt64Type, &layer);
            
            var pid: i64 = 0;
            _ = c.CFNumberGetValue(@ptrCast(pid_ref), c.kCFNumberSInt64Type, &pid);
            
            var is_on_screen = false;
            if (on_screen_ref != null) {
                is_on_screen = c.CFBooleanGetValue(@ptrCast(on_screen_ref)) != 0;
            }
            
            if (layer == 0 and bounds.size.width > 100 and bounds.size.height > 100) {
                const border_window = try createBorder(bounds);
                
                const id: u32 = @intCast(window_id);
                const is_active = current_active_window_id != null and current_active_window_id.? == id;
                
                // Only show border for active window
                if (!is_active or !is_on_screen) {
                    hideBorderWindow(border_window);
                }
                
                var window_info = WindowInfo{
                    .window_id = id,
                    .border_window = border_window,
                    .pid = @intCast(pid),
                    .last_bounds = bounds,
                    .target_bounds = bounds,
                    .current_bounds = bounds,
                    .is_visible = is_on_screen,
                    .was_visible = is_on_screen,
                    .is_active = is_active,
                    .was_active = is_active,
                };
                
                // Get app name
                if (owner_ref != null) {
                    _ = c.CFStringGetCString(
                        @ptrCast(owner_ref),
                        &window_info.app_name,
                        window_info.app_name.len,
                        c.kCFStringEncodingUTF8
                    );
                }
                
                try windows.put(id, window_info);
                
                if (is_active) {
                    const app_name_len = std.mem.indexOfScalar(u8, &window_info.app_name, 0) orelse window_info.app_name.len;
                    std.debug.print("Active window: {} - {s}\n", .{ window_id, window_info.app_name[0..app_name_len] });
                }
            }
        }
    }
}

fn updateWindowStates() !void {
    const window_list = c.CGWindowListCopyWindowInfo(
        c.kCGWindowListOptionAll,
        c.kCGNullWindowID
    ) orelse return;
    defer c.CFRelease(@ptrCast(window_list));
    
    const count = c.CFArrayGetCount(window_list);
    const current_time = getCurrentTime();
    
    // Get current active window
    const new_active_window_id = getActiveWindowId();
    
    windows_mutex.lock();
    defer windows_mutex.unlock();
    
    // Check if active window changed
    if (current_active_window_id != new_active_window_id) {
        current_active_window_id = new_active_window_id;
        
        // Update all window active states
        var iter = windows.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.was_active = entry.value_ptr.is_active;
            entry.value_ptr.is_active = new_active_window_id != null and new_active_window_id.? == entry.key_ptr.*;
            
            if (entry.value_ptr.was_active != entry.value_ptr.is_active) {
                entry.value_ptr.needs_update = true;
            }
        }
    }
    
    var existing_windows = std.AutoHashMap(u32, bool).init(allocator);
    defer existing_windows.deinit();
    
    var i: c.CFIndex = 0;
    while (i < count) : (i += 1) {
        const window_dict = c.CFArrayGetValueAtIndex(window_list, i);
        if (window_dict == null) continue;
        
        const window_id_ref = c.CFDictionaryGetValue(
            @ptrCast(window_dict),
            @ptrCast(c.kCGWindowNumber)
        );
        
        const bounds_dict = c.CFDictionaryGetValue(
            @ptrCast(window_dict),
            @ptrCast(c.kCGWindowBounds)
        );
        
        const on_screen_ref = c.CFDictionaryGetValue(
            @ptrCast(window_dict),
            @ptrCast(c.kCGWindowIsOnscreen)
        );
        
        if (window_id_ref != null) {
            var window_id: i64 = 0;
            _ = c.CFNumberGetValue(@ptrCast(window_id_ref), c.kCFNumberSInt64Type, &window_id);
            
            const id: u32 = @intCast(window_id);
            try existing_windows.put(id, true);
            
            var is_on_screen = false;
            if (on_screen_ref != null) {
                is_on_screen = c.CFBooleanGetValue(@ptrCast(on_screen_ref)) != 0;
            }
            
            if (windows.getPtr(id)) |window_info| {
                window_info.was_visible = window_info.is_visible;
                window_info.is_visible = is_on_screen;
                
                if (window_info.was_visible != window_info.is_visible) {
                    window_info.needs_update = true;
                }
                
                if (is_on_screen and bounds_dict != null) {
                    var bounds: c.CGRect = undefined;
                    if (c.CGRectMakeWithDictionaryRepresentation(@ptrCast(bounds_dict), &bounds)) {
                        if (!c.CGRectEqualToRect(window_info.target_bounds, bounds)) {
                            window_info.last_bounds = window_info.current_bounds;
                            window_info.target_bounds = bounds;
                            window_info.animation_start = current_time;
                            window_info.needs_update = true;
                        }
                        
                        const elapsed = current_time - window_info.animation_start;
                        const progress = @min(elapsed / ANIMATION_DURATION, 1.0);
                        
                        window_info.current_bounds = if (progress < 1.0)
                            interpolateRect(window_info.last_bounds, window_info.target_bounds, progress)
                        else
                            window_info.target_bounds;
                        
                        if (progress < 1.0) {
                            window_info.needs_update = true;
                        }
                    }
                }
            }
        }
    }
    
    // Remove borders for closed windows
    var remove_list = std.ArrayList(u32).init(allocator);
    defer remove_list.deinit();
    
    var iter = windows.iterator();
    while (iter.next()) |entry| {
        if (!existing_windows.contains(entry.key_ptr.*)) {
            closeBorderWindow(entry.value_ptr.border_window);
            try remove_list.append(entry.key_ptr.*);
        }
    }
    
    for (remove_list.items) |window_id| {
        _ = windows.remove(window_id);
    }
}

fn updateBordersOnMainThread() !void {
    windows_mutex.lock();
    defer windows_mutex.unlock();
    
    var iter = windows.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.needs_update) {
            // Only show border for active, visible windows
            const should_show = entry.value_ptr.is_active and entry.value_ptr.is_visible;
            
            if (should_show) {
                showBorderWindow(entry.value_ptr.border_window);
                updateBorderFrame(entry.value_ptr.border_window, entry.value_ptr.current_bounds);
            } else {
                hideBorderWindow(entry.value_ptr.border_window);
            }
            
            const elapsed = getCurrentTime() - entry.value_ptr.animation_start;
            if (elapsed >= ANIMATION_DURATION and 
                entry.value_ptr.was_visible == entry.value_ptr.is_visible and
                entry.value_ptr.was_active == entry.value_ptr.is_active) {
                entry.value_ptr.needs_update = false;
            }
        }
    }
}

fn updateBorderFrame(border_window: c.id, cg_bounds: c.CGRect) void {
    const ns_y = screen_height - cg_bounds.origin.y - cg_bounds.size.height;
    
    const frame = c.CGRectMake(
        cg_bounds.origin.x - BORDER_WIDTH,
        ns_y - BORDER_WIDTH,
        cg_bounds.size.width + (BORDER_WIDTH * 2),
        cg_bounds.size.height + (BORDER_WIDTH * 2)
    );
    
    const setFrame = @extern(*const fn (c.id, c.SEL, c.CGRect, u8) callconv(.C) void, .{ .name = "objc_msgSend" });
    setFrame(border_window, c.sel_registerName("setFrame:display:"), frame, 0);
}

fn hideBorderWindow(window: c.id) void {
    const orderOut = @extern(*const fn (c.id, c.SEL, c.id) callconv(.C) void, .{ .name = "objc_msgSend" });
    orderOut(window, c.sel_registerName("orderOut:"), @as(c.id, @ptrFromInt(0)));
}

fn showBorderWindow(window: c.id) void {
    const orderFront = @extern(*const fn (c.id, c.SEL, c.id) callconv(.C) void, .{ .name = "objc_msgSend" });
    orderFront(window, c.sel_registerName("orderFront:"), @as(c.id, @ptrFromInt(0)));
}

fn closeBorderWindow(window: c.id) void {
    const close = @extern(*const fn (c.id, c.SEL) callconv(.C) void, .{ .name = "objc_msgSend" });
    close(window, c.sel_registerName("close"));
}

fn createBorder(cg_bounds: c.CGRect) !c.id {
    const NSWindow = c.objc_getClass("NSWindow") orelse return error.ClassNotFound;
    const NSView = c.objc_getClass("NSView") orelse return error.ClassNotFound;
    const NSColor = c.objc_getClass("NSColor") orelse return error.ClassNotFound;
    
    const ns_y = screen_height - cg_bounds.origin.y - cg_bounds.size.height;
    
    const frame = c.CGRectMake(
        cg_bounds.origin.x - BORDER_WIDTH,
        ns_y - BORDER_WIDTH,
        cg_bounds.size.width + (BORDER_WIDTH * 2),
        cg_bounds.size.height + (BORDER_WIDTH * 2)
    );
    
    const window = msg(@ptrCast(@alignCast(NSWindow)), "alloc");
    
    const initWindow = @extern(*const fn (c.id, c.SEL, c.CGRect, usize, isize, u8) callconv(.C) c.id, .{ .name = "objc_msgSend" });
    _ = initWindow(
        window,
        c.sel_registerName("initWithContentRect:styleMask:backing:defer:"),
        frame,
        0, // NSWindowStyleMaskBorderless
        2, // NSBackingStoreBuffered
        0  // NO
    );
    
    const setBool = @extern(*const fn (c.id, c.SEL, u8) callconv(.C) void, .{ .name = "objc_msgSend" });
    setBool(window, c.sel_registerName("setOpaque:"), 0);
    setBool(window, c.sel_registerName("setHasShadow:"), 0);
    setBool(window, c.sel_registerName("setIgnoresMouseEvents:"), 1);
    
    const setLevel = @extern(*const fn (c.id, c.SEL, isize) callconv(.C) void, .{ .name = "objc_msgSend" });
    setLevel(window, c.sel_registerName("setLevel:"), 3);
    
    const setCollectionBehavior = @extern(*const fn (c.id, c.SEL, usize) callconv(.C) void, .{ .name = "objc_msgSend" });
    setCollectionBehavior(window, c.sel_registerName("setCollectionBehavior:"), 17);
    
    const clearColor = msg(@ptrCast(@alignCast(NSColor)), "clearColor");
    const setBackgroundColor = @extern(*const fn (c.id, c.SEL, c.id) callconv(.C) void, .{ .name = "objc_msgSend" });
    setBackgroundColor(window, c.sel_registerName("setBackgroundColor:"), clearColor);
    
    const view = msg(@ptrCast(@alignCast(NSView)), "alloc");
    const view_frame = c.CGRectMake(0, 0, frame.size.width, frame.size.height);
    const initView = @extern(*const fn (c.id, c.SEL, c.CGRect) callconv(.C) c.id, .{ .name = "objc_msgSend" });
    _ = initView(view, c.sel_registerName("initWithFrame:"), view_frame);
    
    setBool(view, c.sel_registerName("setWantsLayer:"), 1);
    
    const layer = msg(view, "layer");
    if (layer != null) {
        const color = c.CGColorCreateGenericRGB(ACTIVE_COLOR.r, ACTIVE_COLOR.g, ACTIVE_COLOR.b, ACTIVE_COLOR.a);
        defer c.CGColorRelease(color);
        
        const setColor = @extern(*const fn (c.id, c.SEL, c.CGColorRef) callconv(.C) void, .{ .name = "objc_msgSend" });
        setColor(layer, c.sel_registerName("setBorderColor:"), color);
        
        const setWidth = @extern(*const fn (c.id, c.SEL, f64) callconv(.C) void, .{ .name = "objc_msgSend" });
        setWidth(layer, c.sel_registerName("setBorderWidth:"), BORDER_WIDTH);
        
        const setRadius = @extern(*const fn (c.id, c.SEL, f64) callconv(.C) void, .{ .name = "objc_msgSend" });
        setRadius(layer, c.sel_registerName("setCornerRadius:"), BORDER_RADIUS);
    }
    
    const setContentView = @extern(*const fn (c.id, c.SEL, c.id) callconv(.C) void, .{ .name = "objc_msgSend" });
    setContentView(window, c.sel_registerName("setContentView:"), view);
    
    const orderFront = @extern(*const fn (c.id, c.SEL, c.id) callconv(.C) void, .{ .name = "objc_msgSend" });
    orderFront(window, c.sel_registerName("makeKeyAndOrderFront:"), @as(c.id, @ptrFromInt(0)));
    
    return window;
}
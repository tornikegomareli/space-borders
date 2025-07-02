const std = @import("std");
const objc = @import("objc.zig");
const c = @cImport({
    @cInclude("ApplicationServices/ApplicationServices.h");
});

pub const AXError = c.AXError;
pub const AXUIElementRef = c.AXUIElementRef;
pub const AXObserverRef = c.AXObserverRef;
pub const CFStringRef = c.CFStringRef;
pub const CFArrayRef = c.CFArrayRef;
pub const CFTypeRef = c.CFTypeRef;
pub const pid_t = c.pid_t;

pub const kAXErrorSuccess = c.kAXErrorSuccess;
pub const kAXTrustedCheckOptionPrompt = c.kAXTrustedCheckOptionPrompt;

pub fn isAccessibilityEnabled() bool {
    return c.AXIsProcessTrustedWithOptions(null) != 0;
}

pub fn createSystemWideElement() AXUIElementRef {
    return c.AXUIElementCreateSystemWide();
}

pub fn createApplicationElement(pid: pid_t) AXUIElementRef {
    return c.AXUIElementCreateApplication(pid);
}

pub fn copyAttributeValue(element: AXUIElementRef, attribute: CFStringRef, value: *CFTypeRef) AXError {
    return c.AXUIElementCopyAttributeValue(element, attribute, value);
}

pub fn setAttribute(element: AXUIElementRef, attribute: CFStringRef, value: CFTypeRef) AXError {
    return c.AXUIElementSetAttributeValue(element, attribute, value);
}

pub fn createObserver(pid: pid_t, callback: c.AXObserverCallback, observer: *AXObserverRef) AXError {
    return c.AXObserverCreate(pid, callback, observer);
}

pub fn addNotification(observer: AXObserverRef, element: AXUIElementRef, notification: CFStringRef, refcon: ?*anyopaque) AXError {
    return c.AXObserverAddNotification(observer, element, notification, refcon);
}

pub fn removeNotification(observer: AXObserverRef, element: AXUIElementRef, notification: CFStringRef) AXError {
    return c.AXObserverRemoveNotification(observer, element, notification);
}

pub fn getRunLoopSource(observer: AXObserverRef) c.CFRunLoopSourceRef {
    return c.AXObserverGetRunLoopSource(observer);
}

pub const kAXWindowCreatedNotification = c.kAXWindowCreatedNotification;
pub const kAXWindowMovedNotification = c.kAXWindowMovedNotification;
pub const kAXWindowResizedNotification = c.kAXWindowResizedNotification;
pub const kAXWindowMiniaturizedNotification = c.kAXWindowMiniaturizedNotification;
pub const kAXWindowDeminiaturizedNotification = c.kAXWindowDeminiaturizedNotification;
pub const kAXFocusedWindowChangedNotification = c.kAXFocusedWindowChangedNotification;
pub const kAXApplicationActivatedNotification = c.kAXApplicationActivatedNotification;
pub const kAXApplicationDeactivatedNotification = c.kAXApplicationDeactivatedNotification;

pub const kAXWindowsAttribute = c.kAXWindowsAttribute;
pub const kAXPositionAttribute = c.kAXPositionAttribute;
pub const kAXSizeAttribute = c.kAXSizeAttribute;
pub const kAXMinimizedAttribute = c.kAXMinimizedAttribute;
pub const kAXFocusedAttribute = c.kAXFocusedAttribute;
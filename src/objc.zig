const std = @import("std");
const c = @cImport({
    @cInclude("objc/runtime.h");
    @cInclude("objc/message.h");
});

pub const SEL = c.SEL;
pub const Class = c.Class;
pub const id = c.id;
pub const IMP = c.IMP;
pub const BOOL = c.BOOL;
pub const YES = c.YES;
pub const NO = c.NO;

pub const NSInteger = isize;
pub const NSUInteger = usize;
pub const CGFloat = f64;

pub const NSPoint = extern struct {
    x: CGFloat,
    y: CGFloat,
};

pub const NSSize = extern struct {
    width: CGFloat,
    height: CGFloat,
};

pub const NSRect = extern struct {
    origin: NSPoint,
    size: NSSize,
};

pub fn getClass(name: [:0]const u8) ?Class {
    return c.objc_getClass(name.ptr);
}

pub fn sel(name: [:0]const u8) SEL {
    return c.sel_registerName(name.ptr);
}

pub fn msgSend(obj: id, sel_name: SEL, comptime ReturnType: type) ReturnType {
    const func = @as(*const fn (id, SEL) callconv(.C) ReturnType, @ptrCast(&c.objc_msgSend));
    return func(obj, sel_name);
}

pub fn msgSendWithArgs(obj: id, sel_name: SEL, args: anytype, comptime ReturnType: type) ReturnType {
    const ArgsType = @TypeOf(args);
    const type_info = @typeInfo(ArgsType);
    const fields = switch (type_info) {
        .@"struct" => |s| s.fields,
        else => @compileError("args must be a tuple"),
    };
    
    const func = switch (fields.len) {
        1 => @as(*const fn (id, SEL, @TypeOf(args[0])) callconv(.C) ReturnType, @ptrCast(&c.objc_msgSend)),
        2 => @as(*const fn (id, SEL, @TypeOf(args[0]), @TypeOf(args[1])) callconv(.C) ReturnType, @ptrCast(&c.objc_msgSend)),
        3 => @as(*const fn (id, SEL, @TypeOf(args[0]), @TypeOf(args[1]), @TypeOf(args[2])) callconv(.C) ReturnType, @ptrCast(&c.objc_msgSend)),
        4 => @as(*const fn (id, SEL, @TypeOf(args[0]), @TypeOf(args[1]), @TypeOf(args[2]), @TypeOf(args[3])) callconv(.C) ReturnType, @ptrCast(&c.objc_msgSend)),
        else => @compileError("Unsupported number of arguments"),
    };
    
    return switch (fields.len) {
        1 => func(obj, sel_name, args[0]),
        2 => func(obj, sel_name, args[0], args[1]),
        3 => func(obj, sel_name, args[0], args[1], args[2]),
        4 => func(obj, sel_name, args[0], args[1], args[2], args[3]),
        else => unreachable,
    };
}

pub fn alloc(class: Class) id {
    return msgSend(@as(id, @ptrCast(class)), sel("alloc"), id);
}

pub fn init(obj: id) id {
    return msgSend(obj, sel("init"), id);
}

pub fn retain(obj: id) void {
    _ = msgSend(obj, sel("retain"), id);
}

pub fn release(obj: id) void {
    _ = msgSend(obj, sel("release"), id);
}

pub fn autorelease(obj: id) id {
    return msgSend(obj, sel("autorelease"), id);
}

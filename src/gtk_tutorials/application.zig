//! More or less the same as assigning signals.
//! But doing so allows custom type components that are dynamically spawned to
//! be done without going back to user code
const std = @import("std");
const gtk = @import("gtk");
const gio = @import("gio");
const gobject = @import("gobject");
const glib = @import("glib");

const ExampleApp = extern struct {
    pub const Parent = gtk.Application;
    parent_instance: Parent,

    pub const Class = extern struct {
        pub const Instance = ExampleApp;
        parent_class: Parent.Class,
    };

    // The Zig equivalent of G_DEFINE_TYPE for this subclass
    pub const getGObjectType = gobject.ext.defineClass(ExampleApp, .{
        .name = "ExampleApp",
        .classInit = &classInit,
    });

    fn new() *ExampleApp {
        return gobject.ext.newInstance(ExampleApp, .{
            .@"application-id" = @as([*:0]const u8, "org.gtk.exampleapp"),
            .flags = gio.ApplicationFlags{ .handles_open = true },
        });
    }

    fn classInit(class: *Class) callconv(.c) void {
        gio.Application.virtual_methods.activate.implement(class, &activate);
        gio.Application.virtual_methods.open.implement(class, &open);
    }

    fn activate(self: *ExampleApp) callconv(.c) void {
        const window = ExampleAppWindow.new(self);
        gobject.ext.as(gtk.Window, window).present();
    }

    fn open(
        self: *ExampleApp,
        files: [*]*gio.File,
        count: c_int,
        _: [*:0]const u8,
    ) callconv(.c) void {
        const app = gobject.ext.as(gtk.Application, self);

        const existing = if (app.getActiveWindow()) |window|
            gobject.ext.cast(ExampleAppWindow, window)
        else
            null;
        const window = existing orelse ExampleAppWindow.new(self);

        for (files[0..@intCast(count)]) |file| {
            window.openFile(file);
        }

        gobject.ext.as(gtk.Window, window).present();
    }
};

const ExampleAppWindow = extern struct {
    pub const Parent = gtk.ApplicationWindow;
    parent_instance: Parent,

    pub const Class = extern struct {
        pub const Instance = ExampleAppWindow;
        parent_class: Parent.Class,
    };

    pub const getGObjectType = gobject.ext.defineClass(ExampleAppWindow, .{
        .name = "ExampleAppWindow",
        .classInit = &classInit,
        .instanceInit = &instanceInit,
    });

    fn classInit(class: *Class) callconv(.c) void {
        const ui = @embedFile("window.ui");
        const bytes = glib.Bytes.newStatic(ui, ui.len);
        defer bytes.unref();

        gobject.ext.as(gtk.WidgetClass, class).setTemplate(bytes);
    }

    fn instanceInit(self: *ExampleAppWindow, _: *Class) callconv(.c) void {
        gobject.ext.as(gtk.Widget, self).initTemplate();
    }

    fn new(app: *ExampleApp) *ExampleAppWindow {
        return gobject.ext.newInstance(ExampleAppWindow, .{
            .application = gobject.ext.as(gtk.Application, app),
        });
    }

    fn openFile(_: *ExampleAppWindow, _: *gio.File) void {
        // Just like the C example, this is empty for now
    }
};

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const argv = try arena.allocSentinel(?[*:0]u8, args.len, null);
    for (args, argv) |arg, *slot| {
        slot.* = (try arena.dupeSentinel(u8, arg, 0)).ptr;
    }

    const app = ExampleApp.new();
    defer gobject.ext.as(gobject.Object, app).unref();

    const status = gobject.ext.as(gio.Application, app).run(
        @intCast(args.len),
        @ptrCast(argv.ptr),
    );
    return @intCast(status);
}

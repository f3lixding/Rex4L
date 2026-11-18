//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

const gtk = @import("gtk");
const gio = @import("gio");

pub fn testRender() void {
    const app = gtk.Application.new(null, .{});
    defer app.unref();

    _ = gio.Application.signals.activate.connect(
        app,
        ?*anyopaque,
        struct {
            pub fn activate(_app: *gtk.Application, _: ?*anyopaque) callconv(.c) void {
                const window = gtk.ApplicationWindow.new(_app);
                const base_window = window.as(gtk.Window);

                base_window.setTitle("Rex4L");
                base_window.setDefaultSize(800, 600);
                base_window.present();
            }
        }.activate,
        null,
        .{},
    );

    _ = app.as(gio.Application).run(0, null);
}

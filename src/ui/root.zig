const gio = @import("gio");
const gtk = @import("gtk");

const app_window = @import("application_window.zig");
const TerminalView = @import("TerminalView.zig");

pub fn run() void {
    const app = gtk.Application.new("com.github.f3lixding.Rex4L", .{});
    defer app.unref();

    _ = gio.Application.signals.activate.connect(
        app,
        ?*anyopaque,
        struct {
            fn activate(application: *gtk.Application, _: ?*anyopaque) callconv(.c) void {
                const window = app_window.MainWindow.new(application);
                window.present();
            }
        }.activate,
        null,
        .{},
    );

    _ = app.as(gio.Application).run(0, null);
}

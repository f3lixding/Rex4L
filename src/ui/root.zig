const gio = @import("gio");
const gtk = @import("gtk");

const app_window = @import("application_window.zig");
const TerminalView = @import("TerminalView.zig");

const ActivateContext = struct {
    socket_path: []const u8,
};

pub fn run(socket_path: []const u8) void {
    var ctx: ActivateContext = .{ .socket_path = socket_path };
    const app = gtk.Application.new("com.github.f3lixding.Rex4L", .{});
    defer app.unref();

    _ = gio.Application.signals.activate.connect(
        app,
        *ActivateContext,
        struct {
            fn activate(application: *gtk.Application, context: *ActivateContext) callconv(.c) void {
                const window = app_window.MainWindow.new(application, .{ .socket_path = context.socket_path });
                window.present();
            }
        }.activate,
        &ctx,
        .{},
    );

    _ = app.as(gio.Application).run(0, null);
}

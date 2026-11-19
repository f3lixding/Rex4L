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

                const button = gtk.Button.new();
                button.setLabel("Hello this is a test button");
                _ = gtk.Button.signals.clicked.connect(button, ?*anyopaque, struct {
                    pub fn onClicked(_button: *gtk.Button, _: ?*anyopaque) callconv(.c) void {
                        _button.setLabel("Clicked!");
                    }
                }.onClicked, null, .{});

                const button_as_widget = button.as(gtk.Widget);

                button_as_widget.setSizeRequest(140, 48);
                button_as_widget.setHalign(.center);
                button_as_widget.setValign(.center);
                button_as_widget.setMarginTop(12);
                button_as_widget.setMarginEnd(12);
                base_window.setChild(button.as(gtk.Widget));
            }
        }.activate,
        null,
        .{},
    );

    _ = app.as(gio.Application).run(0, null);
}

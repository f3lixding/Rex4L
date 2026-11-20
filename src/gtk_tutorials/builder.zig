const std = @import("std");
const Io = std.Io;

const gtk = @import("gtk");
const gio = @import("gio");
const gobject = @import("gobject");
const glib = @import("glib");

const builder_ui = @embedFile("builder.ui");

fn getObject(builder: *gtk.Builder, comptime T: type, id: [*:0]const u8) *T {
    const object = builder.getObject(id) orelse @panic("Missing object in builder.ui");
    return gobject.ext.cast(T, object) orelse @panic("Wrong object type in builder.ui");
}

fn printHello(_: *gtk.Button, _: ?*anyopaque) callconv(.c) void {
    glib.print("Hello World\n");
}

fn closeWindow(_: *gtk.Button, window: *gtk.Window) callconv(.c) void {
    window.close();
}

pub fn main(init: std.process.Init) !void {
    var buf: [1024]u8 = undefined;
    var stdout = std.Io.File.Writer.init(.stdout(), init.io, &buf);

    try stdout.interface.print("Rendering builder example", .{});
    try stdout.interface.flush();

    const app = gtk.Application.new(null, .{});
    defer {
        app.unref();
    }

    _ = gio.Application.signals.activate.connect(
        app,
        ?*anyopaque,
        struct {
            pub fn activate(_app: *gtk.Application, _: ?*anyopaque) callconv(.c) void {
                const builder = gtk.Builder.newFromString(builder_ui, builder_ui.len);
                defer builder.unref();

                const window = getObject(builder, gtk.Window, "window");
                window.setApplication(_app);

                const button1 = getObject(builder, gtk.Button, "button1");
                const button2 = getObject(builder, gtk.Button, "button2");
                const quit = getObject(builder, gtk.Button, "quit");

                const clicked = gtk.Button.signals.clicked;
                _ = clicked.connect(button1, ?*anyopaque, printHello, null, .{});
                _ = clicked.connect(button2, ?*anyopaque, printHello, null, .{});
                _ = clicked.connect(quit, *gtk.Window, closeWindow, window, .{});

                window.present();
            }
        }.activate,
        null,
        .{},
    );

    _ = app.as(gio.Application).run(0, null);
}

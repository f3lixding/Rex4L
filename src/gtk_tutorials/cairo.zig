const std = @import("std");

const gtk = @import("gtk");
const gio = @import("gio");

pub fn main(init: std.process.Init) !void {
    var buf: [1024]u8 = undefined;
    var stdout = std.Io.File.Writer.init(.stdout(), init.io, &buf);

    try stdout.interface.print("Rendering cairo", .{});
    try stdout.interface.flush();

    const app = gtk.Application.new(null, .{});
    _ = app;
}

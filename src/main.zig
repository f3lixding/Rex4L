const std = @import("std");
const Io = std.Io;

const Rex4L = @import("Rex4L");

pub fn main(init: std.process.Init) !void {
    var buf: [1024]u8 = undefined;
    var stdout = std.Io.File.Writer.init(.stdout(), init.io, &buf);

    try stdout.interface.print("Hello, {s}\n", .{"felar"});
    try stdout.interface.flush();

    Rex4L.testRender();
}

test "GTK bindings link against GTK4" {
    const gtk = @import("gtk");
    try std.testing.expectEqual(@as(c_uint, 4), gtk.getMajorVersion());
}

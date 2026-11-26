const std = @import("std");
const Rex4L = @import("Rex4L");

pub fn main(init: std.process.Init) !void {
    _ = init;
    Rex4L.run();
}

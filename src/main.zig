const std = @import("std");
const Rex4L = @import("Rex4L");

pub fn main(init: std.process.Init) !void {
    const runtime_dir = init.environ_map.get("XDG_RUNTIME_DIR") orelse return error.MissingXdgRuntimeDir;
    const socket_path = try std.fs.path.join(init.arena.allocator(), &.{ runtime_dir, "rex", "server.sock" });

    Rex4L.run(socket_path);
}

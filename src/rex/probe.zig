//! Headless smoke test: zig run src/rex/probe.zig -- /path/to/server.sock
const std = @import("std");
const rex = @import("root.zig");
const ServerVersion = rex.protocol.ServerVersion;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) {
        std.debug.print("Usage: zig run src/rex/probe.zig -- /path/to/server.sock\n", .{});
        return error.ExpectedSocketPath;
    }
    const alloc = init.gpa;
    const client = try rex.Client.connect(init.io, alloc, args[1]);
    defer client.deinit();
    const response = try client.call(ServerVersion, .{});
    defer response.deinit();
    if (response.value.@"error") |failure| {
        std.debug.print("Rex: {s}: {s}\n", .{ failure.code, failure.message });
        return error.RexRejectedRequest;
    }
    const result = try response.value.parseResult(ServerVersion, alloc);
    defer result.deinit();
    var buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.Writer.init(.stdout(), init.io, &buffer);
    try stdout.interface.print("Rex {s} ({s}), API revision {d}\n", .{
        result.value.rex_version, result.value.platform, result.value.api_revision,
    });
    try stdout.interface.flush();
}

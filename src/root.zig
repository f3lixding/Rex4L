const std = @import("std");
const ui = @import("ui/root.zig");
const terminal = @import("terminal/root.zig");
const rex = @import("rex/root.zig");

const App = struct {
    io: std.Io,
    alloc: std.mem.Allocator,
    client: *rex.Client,
    socket_path: []const u8,

    pub fn init(io: std.Io, alloc: std.mem.Allocator, socket_path: []const u8) !App {
        const client = try rex.Client.init(alloc);

        return .{
            .io = io,
            .alloc = alloc,
            .client = client,
            .socket_path = socket_path,
        };
    }

    pub fn deinit(self: App) void {
        self.client.deinit();
    }

    pub fn run(self: *App) !void {
        try self.client.open(self.io, self.socket_path);
        ui.run();
    }
};

pub fn run(io: std.Io, alloc: std.mem.Allocator, socket_path: []const u8) !void {
    var app: App = try .init(io, alloc, socket_path);
    defer app.deinit();

    try app.run();
}

test {
    _ = terminal.Emulator;
    _ = rex;
}

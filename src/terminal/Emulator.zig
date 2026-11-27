const std = @import("std");
const vt = @import("ghostty-vt");

pub const Self = @This();

io: std.Io,
alloc: std.mem.Allocator,
terminal: *vt.Terminal,
stream: vt.TerminalStream,

pub fn init(io: std.Io, alloc: std.mem.Allocator, opts: struct { cols: u16, rows: u16 }) !Self {
    // The stream points to the terminal, so keep it at a stable address.
    const terminal = try alloc.create(vt.Terminal);
    errdefer alloc.destroy(terminal);
    terminal.* = try vt.Terminal.init(io, alloc, .{
        .cols = opts.cols,
        .rows = opts.rows,
    });

    const stream: vt.TerminalStream = .init(.{
        .allocator = alloc,
        .handler = .init(terminal),
    });

    return .{
        .io = io,
        .alloc = alloc,
        .terminal = terminal,
        .stream = stream,
    };
}

pub fn deinit(self: *Self) void {
    self.stream.deinit();
    self.terminal.deinit(self.alloc);
    self.alloc.destroy(self.terminal);
}

pub fn feed(self: *Self, bytes: []const u8) void {
    self.stream.nextSlice(bytes);
}

pub fn updateRenderState(self: *Self, state: *vt.RenderState) !void {
    try state.update(self.alloc, self.terminal);
}

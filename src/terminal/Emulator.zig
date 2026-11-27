const std = @import("std");
const vt = @import("ghostty-vt");

pub const Self = @This();

io: std.Io,
alloc: std.mem.Allocator,
terminal: *vt.Terminal,
stream: vt.TerminalStream,

/// Standalone rendering demo only. A live Rex pane starts with `initFromSnapshot`.
pub fn initPreview(io: std.Io, alloc: std.mem.Allocator, opts: struct { cols: u16, rows: u16 }) !Self {
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

/// Restore one complete snapshot extracted from the Rex data stream.
/// The caller must pass subsequent VT output separately to `feed`.
pub fn initFromSnapshot(io: std.Io, alloc: std.mem.Allocator, snapshot_bytes: []const u8) !Self {
    var reader: std.Io.Reader = .fixed(snapshot_bytes);
    var decoded = try vt.snapshot.decodeExact(alloc, io, &reader, .{
        .max_continuation_bytes = vt.apc.Protocol.maxDefaultBytes(),
    });
    defer decoded.deinit(alloc);

    const terminal = try alloc.create(vt.Terminal);
    errdefer alloc.destroy(terminal);
    terminal.* = decoded.toOwned();
    errdefer terminal.deinit(alloc);

    const continuation: []const u8 = switch (decoded.continuation) {
        .ground => &.{},
        .bytes => |bytes| bytes,
    };
    var stream: vt.TerminalStream = .init(.{
        .allocator = alloc,
        .handler = .init(terminal),
        .continuation_max_bytes = continuation.len,
    });
    errdefer stream.deinit();

    if (continuation.len != 0) {
        // Recreate the parser state for a sequence split at the snapshot cut.
        stream.nextSlice(continuation);
        const replayed = try alloc.alloc(u8, continuation.len);
        defer alloc.free(replayed);
        var writer: std.Io.Writer = .fixed(replayed);
        stream.writeContinuation(&writer) catch return error.InvalidSnapshotContinuation;
        if (!std.mem.eql(u8, continuation, writer.buffered())) {
            return error.InvalidSnapshotContinuation;
        }
    }

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

test "restore server grid and resume a split VT sequence" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var source = try initPreview(io, alloc, .{ .cols = 12, .rows = 3 });
    defer source.deinit();
    source.feed("Rex> ");

    var bytes: std.Io.Writer.Allocating = .init(alloc);
    defer bytes.deinit();
    try vt.snapshot.encode(alloc, &bytes.writer, source.terminal, .{
        .continuation = .{ .bytes = "\x1b[31" },
    });

    var restored = try initFromSnapshot(io, alloc, bytes.written());
    defer restored.deinit();
    try std.testing.expectEqual(@as(u16, 12), restored.terminal.cols);
    try std.testing.expectEqual(@as(u16, 3), restored.terminal.rows);
    restored.feed("mX");

    var state: vt.RenderState = .empty;
    defer state.deinit(alloc);
    try restored.updateRenderState(&state);
    const row = state.row_data.items(.cells)[0];
    try std.testing.expectEqual(@as(u21, 'R'), row.get(0).raw.codepoint());
    try std.testing.expectEqual(@as(u21, 'X'), row.get(5).raw.codepoint());
}

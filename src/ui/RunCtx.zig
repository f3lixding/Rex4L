//! UI-to-app commands. The owner of `ptr` must outlive any UI callback using it.
//! Callbacks queue work without waiting for Rex. If queued work outlives the
//! call, the callback must copy borrowed arguments, including KeyEvent slices.
const RunCtx = @This();
const KeyEvent = @import("../rex/root.zig").protocol.KeyEvent;

/// Local dispatch failures. Rex replies are reported separately.
pub const RunCtxError = error{ OutOfMemory, QueueFull, ShuttingDown, NotReady };

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    open_pane: *const fn (ctx: *anyopaque, session_id: []const u8, block_id: []const u8) RunCtxError!void,
    send_key: *const fn (ctx: *anyopaque, session_id: []const u8, block_id: []const u8, key: KeyEvent) RunCtxError!void,
    close_pane_view: *const fn (ctx: *anyopaque, session_id: []const u8, block_id: []const u8) RunCtxError!void,
};

pub fn openPane(self: RunCtx, session_id: []const u8, block_id: []const u8) RunCtxError!void {
    return self.vtable.open_pane(self.ptr, session_id, block_id);
}

pub fn sendKey(self: RunCtx, session_id: []const u8, block_id: []const u8, key: KeyEvent) RunCtxError!void {
    return self.vtable.send_key(self.ptr, session_id, block_id, key);
}

/// Stop displaying the pane without closing it on the server.
pub fn closePaneView(self: RunCtx, session_id: []const u8, block_id: []const u8) RunCtxError!void {
    return self.vtable.close_pane_view(self.ptr, session_id, block_id);
}

const ui = @import("ui/root.zig");
const terminal = @import("terminal/root.zig");
const rex = @import("rex/root.zig");

pub fn run(socket_path: []const u8) void {
    ui.run(socket_path);
}

test {
    _ = terminal.Emulator;
    _ = rex;
}

//! Rex control WebSocket messages for attaching to one existing terminal.
//! Method payloads follow `rex api describe`; the control envelope follows
//! https://github.com/a10y/rexrs/blob/main/src/protocol.rs.
//! This is not from Superlogical because at the time of writing they did not
//! publish anything officially.
//! Socket I/O and the binary terminal data stream belong in separate modules.
const std = @import("std");

pub const control_path = "/api/control";
pub const control_subprotocol = "rex.control.v1";
pub const data_path = "/api/data";
pub const terminal_subprotocol = "rex.data.terminal.v1";

/// Advertise only revisions the caller actually supports (14 for the first client).
pub const Hello = struct {
    type: []const u8 = "hello",
    api_revision: u32,
    api_min_revision: u32,
    client: ClientInfo = .{},
};

pub const ClientInfo = struct {
    kind: enum { app, cli, agent, other } = .app,
    platform: []const u8 = "linux",
    name: []const u8 = "Rex4L",
    version: ?[]const u8 = null,
    label: ?[]const u8 = null,
};

pub const Welcome = struct {
    protocol: []const u8,
    limits: struct { max_message_bytes: usize },
    api_revision: u32 = 0,
    api_server_revision: u32 = 0,
    api_min_revision: u32 = 0,
    features: ?[]const []const u8 = null,
    client: ?struct {
        id: []const u8,
        // Treat as a credential; don't log it.
        reconnect_token: []const u8,
        resumed: bool = false,
    } = null,
};

pub const Response = struct {
    id: []const u8,
    seq: u64 = 0,
    payload: ?std.json.Value = null,
    @"error": ?ApiError = null,

    /// The parsed result may borrow strings from this message. Release it
    /// before releasing the incoming message and its backing arena.
    pub fn parseResult(self: Response, comptime Method: type, alloc: std.mem.Allocator) !std.json.Parsed(Method.Result) {
        if (self.@"error" != null) return error.RexRejectedRequest;
        const payload = self.payload orelse return error.MissingResult;
        return std.json.parseFromValue(Method.Result, alloc, payload, .{ .ignore_unknown_fields = true });
    }
};

pub const ApiError = struct {
    code: []const u8,
    message: []const u8 = "",
    status: u16 = 0,
};

pub const Event = struct {
    seq: u64,
    payload: struct {
        type: []const u8,
        payload: ?std.json.Value = null,
        session_id: ?[]const u8 = null,
    },
};

pub const Incoming = union(enum) {
    welcome: Welcome,
    response: Response,
    event: Event,
    unknown: []const u8,
};

/// Parse one WebSocket text message. All borrowed data lives until `deinit`.
pub fn decodeIncoming(alloc: std.mem.Allocator, text: []const u8) !std.json.Parsed(Incoming) {
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, text, .{ .allocate = .alloc_always });
    errdefer parsed.deinit();

    if (parsed.value != .object) return error.InvalidEnvelope;
    const kind = parsed.value.object.get("type") orelse return error.InvalidEnvelope;
    if (kind != .string) return error.InvalidEnvelope;

    const arena = parsed.arena.allocator();
    const options: std.json.ParseOptions = .{ .ignore_unknown_fields = true };

    const value: Incoming = if (std.mem.eql(u8, kind.string, "welcome"))
        .{ .welcome = try std.json.parseFromValueLeaky(Welcome, arena, parsed.value, options) }
    else if (std.mem.eql(u8, kind.string, "response"))
        .{ .response = try std.json.parseFromValueLeaky(Response, arena, parsed.value, options) }
    else if (std.mem.eql(u8, kind.string, "event"))
        .{ .event = try std.json.parseFromValueLeaky(Event, arena, parsed.value, options) }
    else
        .{ .unknown = kind.string };

    return .{ .arena = parsed.arena, .value = value };
}

/// Returns JSON owned by the caller. Missing optional fields are omitted.
pub fn encodeHello(alloc: std.mem.Allocator, hello: Hello) ![]u8 {
    return std.json.Stringify.valueAlloc(alloc, hello, .{ .emit_null_optional_fields = false });
}

/// Returns JSON owned by the caller. The caller tracks request IDs and replies.
pub fn encodeRequest(alloc: std.mem.Allocator, comptime Method: type, id: []const u8, payload: Method.Params) ![]u8 {
    return std.json.Stringify.valueAlloc(alloc, .{
        .type = @as([]const u8, "request"),
        .id = id,
        .method = Method.name,
        .payload = payload,
    }, .{ .emit_null_optional_fields = false });
}

pub const ServerVersion = struct {
    pub const name = "server.version";
    pub const Params = struct {};
    pub const Result = struct {
        rex_version: []const u8,
        platform: []const u8,
        dirty: bool,
        commit: ?[]const u8 = null,
        built_at: ?[]const u8 = null,
        api_revision: u32 = 0,
        api_min_revision: u32 = 0,
    };
};

pub const SessionList = struct {
    pub const name = "session.list";
    pub const Params = struct {};
    pub const Result = struct { sessions: ?[]const Session };
    pub const Session = struct { session_id: []const u8, label: []const u8 };
};

const SessionParams = struct { session_id: []const u8 };

pub const SessionAttach = struct {
    pub const name = "session.attach";
    pub const Params = SessionParams;
    pub const Result = struct { client_id: []const u8, view: View };
};

pub const SessionView = struct {
    pub const name = "session.view";
    pub const Params = SessionParams;
    pub const Result = View;
};

/// Only the fields needed to identify a pane; layout geometry is not modeled.
pub const View = struct {
    revision: u64,
    session_id: ?[]const u8,
    active_window_id: ?[]const u8 = null,
    label: []const u8 = "",
    windows: ?[]const Window = null,

    pub const Window = struct {
        window_id: ?[]const u8,
        label: []const u8 = "",
        focused_block_id: ?[]const u8 = null,
    };
};

pub const DataConnect = struct {
    pub const name = "data.connect";
    pub const Params = struct {
        session_id: []const u8,
        block_id: []const u8,
        data_ref_id: []const u8 = "terminal",
        subprotocol: []const u8 = terminal_subprotocol,
    };
    pub const Result = struct {
        // Single-use credential for the data WebSocket; don't log it.
        ticket: []const u8,
        expires_in_ms: u32,
    };
};

pub const ClientKey = struct {
    pub const name = "client.key";
    pub const Params = struct {
        session_id: []const u8,
        block_id: ?[]const u8 = null,
        key: KeyEvent,
        prefix: ?[]const []const u8 = null,
    };
    /// `handled` means a Lua binding consumed the key, not that the PTY echoed it.
    pub const Result = struct { handled: bool };
};

pub const KeyEvent = struct {
    /// Physical key in Rex's snake_case KeyboardEvent notation (e.g. `key_a`).
    key: []const u8,
    mods: []const u8 = "",
    consumed_mods: []const u8 = "",
    text: []const u8 = "",
    unshifted_codepoint: i32 = 0,
    composing: bool = false,
    action: enum { press, release, repeat } = .press,
};

pub const TerminalFormat = struct {
    pub const name = "com.superlogical.terminal.format";
    pub const Params = struct {
        session_id: []const u8,
        block_id: []const u8,
        args: struct {
            format: enum { text, html, vt } = .text,
            trim: bool = true,
        } = .{},
    };
    pub const Result = struct {
        content: []const u8,
        id: ?u64 = null,
        eof: ?bool = null,
        total: ?u64 = null,
    };
};

test "encode control handshake and version request" {
    const alloc = std.testing.allocator;
    const hello = try encodeHello(alloc, .{ .api_revision = 14, .api_min_revision = 14 });
    defer alloc.free(hello);
    try std.testing.expectEqualStrings(
        \\{"type":"hello","api_revision":14,"api_min_revision":14,"client":{"kind":"app","platform":"linux","name":"Rex4L"}}
    , hello);
    const request = try encodeRequest(alloc, ServerVersion, "1", .{});
    defer alloc.free(request);
    try std.testing.expectEqualStrings(
        \\{"type":"request","id":"1","method":"server.version","payload":{}}
    , request);
}

test "decode welcome, reply, error, and event" {
    const alloc = std.testing.allocator;
    const welcome = try decodeIncoming(alloc,
        \\{"type":"welcome","protocol":"rex.control.v1","api_revision":14,"limits":{"max_message_bytes":1048576},"features":null}
    );
    defer welcome.deinit();
    try std.testing.expectEqual(@as(u32, 14), welcome.value.welcome.api_revision);

    const response = try decodeIncoming(alloc,
        \\{"type":"response","id":"1","payload":{"rex_version":"0.1.0-preview.19","platform":"linux_amd64","dirty":false,"api_revision":14}}
    );
    defer response.deinit();
    const version = try response.value.response.parseResult(ServerVersion, alloc);
    defer version.deinit();
    try std.testing.expectEqualStrings("1", response.value.response.id);
    try std.testing.expectEqualStrings("0.1.0-preview.19", version.value.rex_version);

    const failure = try decodeIncoming(alloc,
        \\{"type":"response","id":"2","error":{"code":"session_not_found","status":404}}
    );
    defer failure.deinit();
    try std.testing.expectEqualStrings("session_not_found", failure.value.response.@"error".?.code);
    try std.testing.expectError(error.RexRejectedRequest, failure.value.response.parseResult(SessionAttach, alloc));

    const event = try decodeIncoming(alloc,
        \\{"type":"event","seq":3,"payload":{"type":"session_view_changed","session_id":"session:abc","payload":{"revision":42}}}
    );
    defer event.deinit();
    try std.testing.expectEqual(@as(u64, 3), event.value.event.seq);
    try std.testing.expectEqualStrings("session_view_changed", event.value.event.payload.type);
}

test "encode key event with no optional fields" {
    const alloc = std.testing.allocator;
    const request = try encodeRequest(alloc, ClientKey, "3", .{
        .session_id = "session:abc",
        .key = .{ .key = "enter" },
    });
    defer alloc.free(request);
    try std.testing.expectEqualStrings(
        \\{"type":"request","id":"3","method":"client.key","payload":{"session_id":"session:abc","key":{"key":"enter","mods":"","consumed_mods":"","text":"","unshifted_codepoint":0,"composing":false,"action":"press"}}}
    , request);
}

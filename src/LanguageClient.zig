const std = @import("std");
const lsp = @import("lsp.zig");
const tres = @import("tres.zig");
const ChildProcess = std.ChildProcess;

const LanguageClient = @This();

allocator: std.mem.Allocator,
proc: ChildProcess,
write_buf: std.ArrayList(u8),
read_buf: std.ArrayListUnmanaged(u8) = .{},
id: usize = 0,

const RequestHeader = struct {
    content_length: usize,

    /// null implies "application/vscode-jsonrpc; charset=utf-8"
    content_type: ?[]const u8,

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        if (self.content_type) |ct| allocator.free(ct);
    }
};

pub fn readRequestHeader(client: *LanguageClient) !RequestHeader {
    const allocator = client.allocator;
    const reader = client.proc.stdout.?.reader();

    var r = RequestHeader{
        .content_length = undefined,
        .content_type = null,
    };
    errdefer r.deinit(allocator);

    var has_content_length = false;
    while (true) {
        const header = try reader.readUntilDelimiterAlloc(allocator, '\n', 0x100);
        defer allocator.free(header);
        if (header.len == 0 or header[header.len - 1] != '\r') return error.MissingCarriageReturn;
        if (header.len == 1) break;

        const header_name = header[0 .. std.mem.indexOf(u8, header, ": ") orelse return error.MissingColon];
        const header_value = header[header_name.len + 2 .. header.len - 1];
        if (std.mem.eql(u8, header_name, "Content-Length")) {
            if (header_value.len == 0) return error.MissingHeaderValue;
            r.content_length = std.fmt.parseInt(usize, header_value, 10) catch return error.InvalidContentLength;
            has_content_length = true;
        } else if (std.mem.eql(u8, header_name, "Content-Type")) {
            r.content_type = try allocator.dupe(u8, header_value);
        } else {
            return error.UnknownHeader;
        }
    }
    if (!has_content_length) return error.MissingContentLength;

    return r;
}

pub fn create(allocator: std.mem.Allocator, args: []const []const u8) !*LanguageClient {
    var client = try allocator.create(LanguageClient);

    client.allocator = allocator;

    client.proc = std.ChildProcess.init(args, allocator);

    client.proc.stdin_behavior = .Pipe;
    client.proc.stdout_behavior = .Pipe;

    try client.proc.spawn();

    client.write_buf = std.ArrayList(u8).init(allocator);
    client.read_buf = .{};

    return client;
}

pub fn deinit(client: *LanguageClient) void {
    _ = client.proc.kill() catch @panic("a");

    client.write_buf.deinit();
    client.read_buf.deinit(client.allocator);

    client.allocator.destroy(client);
}

pub fn random(client: *LanguageClient) std.rand.Random {
    return client.prng.random();
}

pub fn writeJson(client: *LanguageClient, data: anytype) !void {
    client.write_buf.items.len = 0;

    try tres.stringify(
        data,
        .{ .emit_null_optional_fields = false },
        client.write_buf.writer(),
    );

    var zls_stdin = client.proc.stdin.?.writer();
    try zls_stdin.print("Content-Length: {d}\r\n\r\n", .{client.write_buf.items.len});
    try zls_stdin.writeAll(client.write_buf.items);
}

pub fn readAndDiscard(client: *LanguageClient) !void {
    const header = try client.readRequestHeader();
    try client.proc.stdout.?.reader().skipBytes(header.content_length, .{});
}

pub fn readToBuffer(client: *LanguageClient) !void {
    const header = try client.readRequestHeader();
    try client.read_buf.ensureTotalCapacity(client.allocator, header.content_length);
    client.read_buf.items.len = header.content_length;
    _ = try client.proc.stdout.?.reader().readAll(client.read_buf.items);
}

pub fn readAndPrint(client: *LanguageClient) !void {
    try client.readToBuffer();
    std.log.info("{s}", .{client.read_buf.items});
}

pub fn readResponse(
    client: *LanguageClient,
    comptime T: type,
    arena: std.mem.Allocator,
) !?T {
    try client.readToBuffer();

    var tree = std.json.Parser.init(arena, true);
    const vt = try tree.parse(client.read_buf.items);

    return (try tres.parse(struct { result: T }, vt.root, arena)).result;
}

pub fn initCycle(client: *LanguageClient, cap: lsp.ClientCapabilities) !void {
    try client.writeJson(.{
        .jsonrpc = "2.0",
        .id = client.id,
        .method = "initialize",
        .params = lsp.InitializeParams{
            .capabilities = cap,
        },
    });
    client.id += 1;
    std.time.sleep(std.time.ns_per_ms * 500);
    try client.readAndDiscard();

    try client.writeJson(.{
        .jsonrpc = "2.0",
        .method = "initialized",
        .params = lsp.InitializedParams{},
    });
    std.time.sleep(std.time.ns_per_ms * 500);
}

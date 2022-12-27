const std = @import("std");
const uri = @import("uri.zig");
const lsp = @import("zig-lsp");
const lsptypes = @import("lsp-types");
const ChildProcess = std.ChildProcess;

const LanguageClient = @This();
const Connection = lsp.Connection(std.fs.File.Reader, std.fs.File.Writer, LanguageClient);

allocator: std.mem.Allocator,
proc: ChildProcess,

open_buf: std.ArrayListUnmanaged(u8) = .{},
connection: Connection,

pub fn create(allocator: std.mem.Allocator, args: []const []const u8) !*LanguageClient {
    var client = try allocator.create(LanguageClient);

    client.* = .{
        .allocator = allocator,
        .proc = std.ChildProcess.init(args, allocator),
        .open_buf = .{},
        .connection = undefined,
    };

    client.proc.stdin_behavior = .Pipe;
    client.proc.stdout_behavior = .Pipe;

    try client.proc.spawn();

    client.connection = Connection.init(
        allocator,
        client.proc.stdout.?.reader(),
        client.proc.stdin.?.writer(),
        client,
    );

    return client;
}

pub fn deinit(client: *LanguageClient) void {
    _ = client.proc.kill() catch @panic("a");

    client.open_buf.deinit(client.allocator);

    client.allocator.destroy(client);
}

pub fn random(client: *LanguageClient) std.rand.Random {
    return client.prng.random();
}

pub fn initCycle(client: *LanguageClient, arena: std.mem.Allocator, cap: lsptypes.ClientCapabilities) !void {
    const handlers = struct {
        pub fn onResponse(_: *Connection, _: lsp.RequestResult("initialize")) !void {}
        pub fn onError(_: *Connection) !void {}
    };

    try client.connection.request("initialize", .{
        .capabilities = cap,
    }, .{ .onResponse = handlers.onResponse, .onError = handlers.onError });
    try client.connection.acceptUntilResponse(arena);

    try client.connection.notify("initialized", .{});
}

/// Returns opened file URI; caller owns memory
pub fn openFile(client: *LanguageClient, path: []const u8) ![]const u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const size = (try file.stat()).size;

    try client.open_buf.ensureTotalCapacity(client.allocator, size);
    client.open_buf.items.len = size;
    _ = try file.readAll(client.open_buf.items);

    const f_uri = try uri.fromPath(client.allocator, path);

    try client.connection.notify("textDocument/didOpen", .{
        .textDocument = .{
            .uri = f_uri,
            .languageId = "js",
            .version = 0,
            .text = client.open_buf.items,
        },
    });

    return f_uri;
}

/// Returns symbols; caller owns memory
pub fn getSymbols(client: *LanguageClient, arena: std.mem.Allocator, f_uri: []const u8) !?[]const lsptypes.DocumentSymbol {
    return ((try client.connection.requestSync(arena, "textDocument/documentSymbol", .{
        .textDocument = .{
            .uri = f_uri,
        },
    })) orelse return null).array_of_DocumentSymbol;
}

const std = @import("std");
const uri = @import("uri.zig");
const lsp = @import("lsp.zig");
const tres = @import("tres.zig");
const scip = @import("scip.zig");
const protobruh = @import("protobruh.zig");
const LanguageClient = @import("LanguageClient.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var lc = try LanguageClient.create(allocator, &.{ "typescript-language-server", "--stdio" });
    defer lc.deinit();

    try lc.initCycle(.{
        .textDocument = .{
            .documentSymbol = .{
                .hierarchicalDocumentSymbolSupport = true,
            },
        },
    });

    const path = "C:\\Programming\\Zig\\yard\\staging\\snitchy2\\src\\index.js";
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var data = try allocator.alloc(u8, (try file.stat()).size);
    _ = try file.readAll(data);

    const f_uri = try uri.fromPath(allocator, path);
    defer allocator.free(f_uri);

    try lc.writeJson(.{
        .jsonrpc = "2.0",
        .method = "textDocument/didOpen",
        .params = lsp.DidOpenTextDocumentParams{ .textDocument = .{
            .uri = f_uri,
            .languageId = "js",
            .version = 0,
            .text = data,
        } },
    });
    try lc.readAndPrint();

    try lc.writeJson(.{
        .jsonrpc = "2.0",
        .id = lc.id,
        .method = "textDocument/documentSymbol",
        .params = lsp.DocumentSymbolParams{ .textDocument = .{
            .uri = f_uri,
        } },
    });
    lc.id += 1;
    const symbols = try lc.readResponse([]lsp.DocumentSymbol, allocator);
    // _ = symbols;
    std.log.info("{s}", .{lc.read_buf.items});
    std.log.info("{any}", .{SymbolsFormatter{ .symbols = symbols.? }});
    // abc("comptime Z: []const u8");

    // abc

    var index = try std.fs.cwd().createFile("index.scip", .{});
    defer index.close();
    var bufw = std.io.bufferedWriter(index.writer());

    const project_root = try uri.fromPath(allocator, "C:\\Programming\\Zig\\yard\\staging\\snitchy2");
    std.log.info("Using project root {s}", .{project_root});

    var documents = std.ArrayListUnmanaged(scip.Document){};

    try documents.append(allocator, .{
        .language = "js",
        .relative_path = "src/index.js",
        .occurrences = .{},
        .symbols = .{},
    });

    try protobruh.encode(scip.Index{
        .metadata = .{
            .version = .unspecified_protocol_version,
            .tool_info = .{
                .name = "yard",
                .version = "bruh",
                .arguments = .{},
            },
            .project_root = project_root,
            .text_document_encoding = .utf8,
        },
        .documents = documents,
        .external_symbols = .{},
    }, bufw.writer());

    try bufw.flush();
}

pub const SymbolsFormatter = struct {
    symbols: []lsp.DocumentSymbol,
    depth: usize = 0,
    scip_symbols: bool = true,

    pub fn format(
        sf: SymbolsFormatter,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        for (sf.symbols) |symbol| {
            try writer.writeByteNTimes(' ', sf.depth * 4);
            try writer.writeAll(symbol.name);
            try writer.writeAll("\n");
            if (symbol.children) |c|
                try writer.print("{any}", .{SymbolsFormatter{
                    .symbols = c,
                    .depth = sf.depth + 1,
                    .scip_symbols = scip_symbols,
                }});
        }
    }
};

pub fn abc(comptime Z: []const u8) void {
    _ = Z;
    abc(@typeName(u8));
}

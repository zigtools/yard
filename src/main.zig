const std = @import("std");
const scip = @import("scip.zig");
const protobruh = @import("protobruh.zig");
const lsptypes = @import("lsp-types");
const LanguageClient = @import("LanguageClient.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var argi = try std.process.ArgIterator.initWithAllocator(allocator);
    defer argi.deinit();

    _ = argi.next();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var lc = try LanguageClient.create(allocator, &.{ "typescript-language-server", "--stdio" });
    defer lc.deinit();

    try lc.initCycle(arena_allocator, .{
        .textDocument = .{
            .documentSymbol = .{
                .hierarchicalDocumentSymbolSupport = true,
            },
        },
    });

    var bruh = std.ArrayList(u8).init(allocator);
    defer bruh.deinit();

    var writer = bruh.writer();

    while (argi.next()) |entry| {
        const f_uri = try lc.openFile(entry);
        const symbols = try lc.getSymbols(arena_allocator, f_uri);

        try writer.writeAll("<div>");
        try writer.print("<h2>{s}</h2>\n{any}", .{ std.fs.path.basename(entry), SymbolsHtmlFormatter{ .file = std.fs.path.basename(entry), .symbols = symbols.?, .depth = 0 } });
        try writer.writeAll("</div>");
    }

    // const html = @embedFile("html.html");

    // const result = try std.mem.replaceOwned(u8, allocator, html, "<!-- REPLACE ME -->", bruh.items);
    // defer allocator.free(result);
    try std.fs.cwd().writeFile("out.html", bruh.items);

    // const path = "C:\\Programming\\Zig\\yard\\staging\\snitchy2\\src\\index.js";

    // const f_uri = try lc.openFile(path);
    // defer allocator.free(f_uri);

    // const symbols = try lc.getSymbols(f_uri);
    // std.log.info("{any}", .{SymbolsFormatter{ .symbols = symbols.? }});
}

pub const SymbolsFormatter = struct {
    symbols: []const lsptypes.DocumentSymbol,
    depth: usize = 0,

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
                }});
        }
    }
};

pub const SymbolsHtmlFormatter = struct {
    file: []const u8,
    symbols: []const lsptypes.DocumentSymbol,
    depth: usize = 0,

    pub fn format(
        sf: SymbolsHtmlFormatter,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.writeAll("<ul>");
        for (sf.symbols) |symbol| {
            try writer.writeByteNTimes(' ', sf.depth * 4);
            try writer.print("<li><a href='https://github.com/snitchbcc/snitchy2/blob/master/src/{s}#L{d}-L{d}'>{s}</a></li>", .{ sf.file, symbol.range.start.line + 1, symbol.range.end.line + 1, symbol.name });
            try writer.writeAll("\n");
            if (symbol.children) |c|
                try writer.print("{any}", .{SymbolsHtmlFormatter{
                    .file = sf.file,
                    .symbols = c,
                    .depth = sf.depth + 1,
                }});
        }
        try writer.writeAll("</ul>");
    }
};

pub fn abc(comptime Z: []const u8) void {
    _ = Z;
    abc(@typeName(u8));
}

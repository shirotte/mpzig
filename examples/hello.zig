const std = @import("std");
const mpzig = @import("mpzig");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    var buffer:[512]u8 = undefined;

    var fba = std.io.fixedBufferStream(&buffer);
    var encoder = mpzig.encoder(fba.writer());

    try encoder.encodeInt(u8, 13);
    try encoder.encodeFloat(f32, 3.14);
    try encoder.encodeStr("Hello, MessagePack");

    fba.reset();

    var decoder = mpzig.decoder(gpa.allocator(), fba.reader());
    defer decoder.deinit();

    std.debug.print("{}\n", .{try decoder.decodeInt(u8)});
    std.debug.print("{}\n", .{try decoder.decodeFloat(f32)});
    std.debug.print("{s}\n", .{try decoder.decodeRaw()});
}

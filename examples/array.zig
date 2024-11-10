const std = @import("std");
const mpzig = @import("mpzig");

const Character = struct { x: f32, y: f32, name: []const u8, hp: u64 };

pub fn main() !void {
    const ziggy = Character{
        .x = 3.12,
        .y = 6123.2,
        .name = "Ziggy",
        .hp = 18446744073709551615,
    };
    std.debug.print("original: {any}\n", .{ziggy});

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    var array = std.ArrayList(u8).init(gpa.allocator());
    defer array.deinit();
    var encoder = mpzig.encoder(array.writer());

    try encoder.encodeArray(ziggy);

    var fbs = std.io.fixedBufferStream(array.items);
    var decoder = mpzig.decoder(gpa.allocator(), fbs.reader());
    defer decoder.deinit();

    const decoded = decoder.decodeStruct(Character);
    std.debug.print("decoded: {any}\n", .{decoded});
}

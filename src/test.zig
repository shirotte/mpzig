const std = @import("std");
const testing = std.testing;
const io = std.io;
const mpzig = @import("root.zig");

test "encode nil" {
    var buffer: [255]u8 = undefined;
    var fba = io.fixedBufferStream(&buffer);
    var encoder = mpzig.encoder(fba.writer());
    
    try encoder.writeNil();

    try expectFromatAndLength(fba, mpzig.Type.Nil, 1);
}

test "encode true" {
    var buffer: [255]u8 = undefined;
    var fba = io.fixedBufferStream(&buffer);
    var encoder = mpzig.encoder(fba.writer());
    
    try encoder.writeBool(true);

    try expectFromatAndLength(fba, mpzig.Type.True, 1);
}

test "encode false" {
    var buffer: [255]u8 = undefined;
    var fba = io.fixedBufferStream(&buffer);
    var encoder = mpzig.encoder(fba.writer());
    
    try encoder.writeBool(false);

    try expectFromatAndLength(fba, mpzig.Type.False, 1);
}

test "encode int" {
    var buffer: [255]u8 = undefined;
    var fba = io.fixedBufferStream(&buffer);
    var encoder = mpzig.encoder(fba.writer());
    
    var prng = std.Random.DefaultPrng.init(testing.random_seed);
    const rand = prng.random();
    
    try encoder.writeInt(u0, rand.int(u0));
    try encoder.writeInt(u1, rand.int(u1));
    try encoder.writeInt(u7, rand.int(u7));
    try encoder.writeInt(u8, rand.int(u8));
}

test "encode float" {
    var buffer: [255]u8 = undefined;
    var fba = io.fixedBufferStream(&buffer);
    var encoder = mpzig.encoder(fba.writer());
    
    var prng = std.Random.DefaultPrng.init(testing.random_seed);
    const rand = prng.random();

    try encoder.writeFloat(f32, rand.float(f32));
    try encoder.writeFloat(f64, rand.float(f64));
}

test "encode str" { 
    var buffer: [255]u8 = undefined;
    var fba = io.fixedBufferStream(&buffer);
    var encoder = mpzig.encoder(fba.writer());

    try encoder.writeStr("All your codebase");
}

fn expectFromatAndLength(fba: anytype, format: mpzig.Type, written_bytes: usize) !void {
    try testing.expect(fba.buffer[0] == @intFromEnum(format));
    try testing.expect(fba.pos == written_bytes);
}

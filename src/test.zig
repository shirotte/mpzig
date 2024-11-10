const mpzig = @import("root.zig");
const std = @import("std");
const testing = std.testing;
const io = std.io;
const maxInt = std.math.maxInt;
const minInt = std.math.minInt;

test "nil" {
    var buffer: [255]u8 = undefined;
    var fba = io.fixedBufferStream(&buffer);
    var encoder = mpzig.encoder(fba.writer());
    var decoder = mpzig.decoder(testing.allocator, fba.reader());
    defer decoder.deinit();

    try encoder.encodeNil();
    try testing.expect(fba.buffer[0] == @intFromEnum(mpzig.Type.Nil));
    try testing.expect(fba.pos == 1);

    fba.reset();
    try decoder.decodeNil();
}

test "bool true" {
    var buffer: [255]u8 = undefined;
    var fba = io.fixedBufferStream(&buffer);
    var encoder = mpzig.encoder(fba.writer());
    var decoder = mpzig.decoder(testing.allocator, fba.reader());
    defer decoder.deinit();

    try encoder.encodeBool(true);
    try testing.expect(fba.buffer[0] == @intFromEnum(mpzig.Type.True));
    try testing.expect(fba.pos == 1);

    fba.reset();
    try testing.expect(true == try decoder.decodeBool());
}

test "bool false" {
    var buffer: [255]u8 = undefined;
    var fba = io.fixedBufferStream(&buffer);
    var encoder = mpzig.encoder(fba.writer());
    var decoder = mpzig.decoder(testing.allocator, fba.reader());
    defer decoder.deinit();

    try encoder.encodeBool(false);
    try testing.expect(fba.buffer[0] == @intFromEnum(mpzig.Type.False));
    try testing.expect(fba.pos == 1);

    fba.reset();
    try testing.expect(false == try decoder.decodeBool());
}

test "int" {
    try testingEncodeDecodeInt(i8);
    try testingEncodeDecodeInt(i16);
    try testingEncodeDecodeInt(i32);
    try testingEncodeDecodeInt(i64);
    try testingEncodeDecodeInt(u8);
    try testingEncodeDecodeInt(u16);
    try testingEncodeDecodeInt(u32);
    try testingEncodeDecodeInt(u64);
}

test "float" {
    try testingEncodeDecodeFloat(f32);
    try testingEncodeDecodeFloat(f64);
}

test "str" {
    try testingEncodeDecodeStr("codebase"); // upto 31 bytes
    try testingEncodeDecodeStr("cat" ** 50); // upto 255 bytes
    try testingEncodeDecodeStr("dog" ** 20000); // upto 64435 bytes

    // Note: This test case allocated over 8Gb. So I can't test this :<
    // try testingEncodeDecodeStr("connection" ** 420000000); // upto (2^32)-1 bytes
}

fn expectEncodeDecode(comptime T: type, value: T) !void {
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    var encoder = mpzig.encoder(list.writer());
    try encoder.encode(value);

    var fbs = io.fixedBufferStream(list.items);
    var decoder = mpzig.decoder(testing.allocator, fbs.reader());
    defer decoder.deinit();
    const actual = try decoder.decode(T);

    try testing.expectEqual(value, actual);
}

fn testingEncodeDecodeInt(comptime T: type) !void {
    var prng = std.Random.DefaultPrng.init(testing.random_seed);
    const rand = prng.random();

    try expectEncodeDecode(T, 0);
    try expectEncodeDecode(T, maxInt(u7));
    try expectEncodeDecode(T, maxInt(T));
    try expectEncodeDecode(T, minInt(T));
    try expectEncodeDecode(T, rand.int(T));
}

fn testingEncodeDecodeFloat(comptime T: type) !void {
    var prng = std.Random.DefaultPrng.init(testing.random_seed);
    const rand = prng.random();

    try expectEncodeDecode(T, 0.0);
    try expectEncodeDecode(T, -1.0);
    try expectEncodeDecode(T, 1.0);
    try expectEncodeDecode(T, rand.float(T));
}

fn testingEncodeDecodeStr(str: []const u8) !void {
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    var encoder = mpzig.encoder(list.writer());
    try encoder.encode(str);

    var fbs = io.fixedBufferStream(list.items);
    var decoder = mpzig.decoder(testing.allocator, fbs.reader());
    defer decoder.deinit();
    const actual = try decoder.decode([]u8);

    try testing.expectEqualStrings(str, actual);
}

const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const meta = std.meta;
const nativeToBig = std.mem.nativeToBig;
const maxInt = std.math.maxInt;

pub const Type = enum(u8) {
    Nil = 0xC0,
    False = 0xC2,
    True,
    Bin8,
    Bin16,
    Bin32,
    Ext8,
    Ext16,
    Ext32,
    Float32,
    Float64,
    Uint8,
    Uint16,
    Uint32,
    Uint64,
    Int8,
    Int16,
    Int32,
    Int64,
    Fixext1,
    Fixext2,
    Fixext4,
    Fixext8,
    Fixext16,
    Str8,
    Str16,
    Str32,
    Array16,
    Array32,
    Map16,
    Map32,
    _,
};

pub const TypeMask = enum(u8) {
    FixMap = @shlExact(0b1000, 4),
    FixArray = @shlExact(0b1001, 4),
    FixStr = @shlExact(0b101, 5),
};

pub fn Encoder(comptime WriterType: type) type {
    return struct {
        encoded_writer: WriterType,
        pub const Writer = WriterType;

        const Self = @This();

        pub fn write(self: *Self, value: anytype) !void {
            switch (@typeInfo(@TypeOf(value))) {
                .bool => try self.writeBool(value),
                .int => try self.writeInt(@TypeOf(value), value),
                .float => try self.writeFloat(@TypeOf(value), value),
                .array => |f| {
                    if (f.sentinel)
                        try self.writeStr(value)
                    else
                        try self.writeBin(value);
                },
                .@"struct" => try self.writeArray(value),
                else => unreachable,
            }
        }

        pub fn writeNil(self: *Self) !void {
            return self.encoded_writer.writeByte(@intFromEnum(Type.Nil));
        }

        pub fn writeBool(self: *Self, value: bool) !void {
            const byte = if (value) @intFromEnum(Type.True) else @intFromEnum(Type.False);
            return self.encoded_writer.writeByte(byte);
        }

        pub fn writeInt(self: *Self, comptime T: type, value: T) !void {
            if (value >= 0x00 and value <= 0x7F)
                return self.encoded_writer.writeByte(@intCast(value));

            if (value <= 0x00 and value >= -0x1F)
                return self.encoded_writer.writeByte(@bitCast(value));

            const format: u8 = switch (T) {
                u8 => @intFromEnum(Type.Uint8),
                u16 => @intFromEnum(Type.Uint16),
                u32 => @intFromEnum(Type.Uint32),
                u64 => @intFromEnum(Type.Uint64),
                i8 => @intFromEnum(Type.Int8),
                i16 => @intFromEnum(Type.Int16),
                i32 => @intFromEnum(Type.Int32),
                i64 => @intFromEnum(Type.Uint64),
                else => unreachable,
            };

            try self.encoded_writer.writeByte(format);
            try self.encoded_writer.writeInt(T, value, .big);
        }

        pub fn writeFloat(self: *Self, comptime T: type, value: T) !void {
            const format: u8 = switch (T) {
                f32 => @intFromEnum(Type.Float32),
                f64 => @intFromEnum(Type.Float64),
                else => unreachable,
            };
            try self.encoded_writer.writeByte(format);

            @setFloatMode(.strict);
            const bytes: [@sizeOf(T)]u8 = @bitCast(value);
            try self.encoded_writer.writeAll(&bytes);
        }

        pub fn writeStr(self: *Self, value: []const u8) !void {
            const format: u8 = switch (value.len) {
                0...maxInt(u4) => {
                    try self.encoded_writer.writeByte(@intFromEnum(TypeMask.FixStr) | @as(u8, @intCast(value.len)));
                    return self.encoded_writer.writeAll(value);
                },
                maxInt(u4) + 1...maxInt(u8) => @intFromEnum(Type.Str8),
                maxInt(u8) + 1...maxInt(u16) => @intFromEnum(Type.Str16),
                maxInt(u16) + 1...maxInt(u32) => @intFromEnum(Type.Str32),
                else => unreachable,
            };
            try self.encoded_writer.writeByte(format);

            const str_len: [@sizeOf(usize)]u8 = @bitCast(nativeToBig(usize, value.len));
            try self.encoded_writer.writeAll(str_len[str_len.len - byteFromInt(value.len) ..]);

            try self.encoded_writer.writeAll(value);
        }

        pub fn writeBin(self: *Self, value: []const u8) !void {
            const format: u8 = switch (value.len) {
                0...maxInt(u8) => @intFromEnum(Type.Bin8),
                maxInt(u8) + 1...maxInt(u16) => @intFromEnum(Type.Bin16),
                maxInt(u16) + 1...maxInt(u32) => @intFromEnum(Type.Bin32),
                else => unreachable,
            };
            try self.encoded_writer.writeByte(format);

            const bin_len: [@sizeOf(usize)]u8 = @bitCast(nativeToBig(usize, value.len));
            try self.encoded_writer.writeAll(bin_len[bin_len.len - byteFromInt(value.len) ..]);

            try self.encoded_writer.writeAll(value);
        }

        pub fn writeArray(self: *Self, value: anytype) !void {
            const fields = meta.fields(@TypeOf(value));
            switch (fields.len) {
                0...maxInt(u4) => {
                    try self.encoded_writer.writeByte(@intFromEnum(TypeMask.FixArray) | @as(u8, @intCast(fields.len)));
                },
                maxInt(u4)...maxInt(u16) => {
                    const bytes: [@sizeOf(u8) + @sizeOf(u16)]u8 = .{@intFromEnum(Type.Array16)} ++ @as([2]u8, @bitCast(fields.len));
                    try self.encoded_writer.writeAll(bytes);
                },
                maxInt(u16)...maxInt(u32) => {
                    const bytes: [@sizeOf(u8) + @sizeOf(u32)]u8 = .{@intFromEnum(Type.Array16)} ++ @as([4]u8, @bitCast(fields.len));
                    try self.encoded_writer.writeAll(bytes);
                },
                else => unreachable,
            }

            inline for (meta.fields(fields)) |f| {
                try self.write(@field(value, f.name));
            }
        }
    };
}

pub fn encoder(writer: anytype) Encoder(@TypeOf(writer)) {
    return .{ .encoded_writer = writer };
}

pub fn Decoder(comptime ReaderType: type) type {
    return struct {
        encoded_reader: ReaderType,

        const Self = @This();

        pub fn read(self: *Self, comptime T: type) !T {
            return switch (@typeInfo(T)) {
                .bool => self.readBool(),
                .int => try self.readInt(),
                .float => try self.readFloat(),
                .@"struct" => try self.readArray(T),
                else => unreachable,
            };
        }

        pub fn readNil(self: *Self) !void {
            const format = try self.encoded_reader.readByte();
            if (format != @intFromEnum(Type.Nil))
                unreachable;
        }

        pub fn readBool(self: *Self) !bool {
            const format = try self.encoded_reader.readByte();
            return switch (@as(Type, @enumFromInt(format))) {
                .False => false,
                .True => true,
                else => unreachable,
            };
        }

        pub fn readInt(self: *Self) !isize {
            const format = try self.encoded_reader.readByte();
            if (format <= 0x7F)
                return @intCast(format);
            if (format >= 0xE0)
                return @as(i8, @bitCast(format));

            return switch (@as(Type, @enumFromInt(format))) {
                .Uint8 => try self.encoded_reader.readInt(u8, .big),
                .Uint16 => try self.encoded_reader.readInt(u16, .big),
                .Uint32 => try self.encoded_reader.readInt(u32, .big),
                .Uint64 => @intCast(try self.encoded_reader.readInt(u64, .big)),
                .Int8 => try self.encoded_reader.readInt(i8, .big),
                .Int16 => try self.encoded_reader.readInt(i16, .big),
                .Int32 => try self.encoded_reader.readInt(i32, .big),
                .Int64 => try self.encoded_reader.readInt(i64, .big),
                else => unreachable,
            };
        }

        pub fn readFloat(self: *Self) !f64 {
            const format = try self.encoded_reader.readByte();

            var buffer: [@sizeOf(f64)]u8 = undefined;
            @memset(&buffer, 0);
            _ = switch (@as(Type, @enumFromInt(format))) {
                .Float32 => {
                    _ = try self.encoded_reader.readAll(buffer[4..]);
                },
                .Float64 => try self.encoded_reader.readAll(&buffer),
                else => unreachable,
            };
            return @bitCast(buffer);
        }

        pub fn readStr(self: *Self, allocator: mem.Allocator) ![]u8 {
            const format = try self.encoded_reader.readByte();
            const str_len = switch (@as(Type, @enumFromInt(format))) {
                .Str8 => try self.encoded_reader.readByte(),
                .Str16 => try self.encoded_reader.readInt(u16, .big),
                .Str32 => try self.encoded_reader.readInt(u32, .big),
                else => {
                    if (format & TypeMask.FixStr == TypeMask.FixStr)
                        format & ~TypeMask.FixStr
                    else
                        unreachable;
                },
            };

            return self.encoded_reader.readAllAlloc(allocator, str_len);
        }

        pub fn readBin(self: *Self, allocator: mem.Allocator) ![]u8 {
            const format = try self.encoded_reader.readByte();
            const bin_len = switch (@as(Type, @enumFromInt(format))) {
                .Bin8 => try self.encoded_reader.readByte(),
                .Bin16 => try self.encoded_reader.readInt(u16, .big),
                .Bin32 => try self.encoded_reader.readInt(u32, .big),
                else => unreachable,
            };

            return self.encoded_reader.readAllAlloc(allocator, bin_len);
        }

        pub fn readArray(self: *Self, comptime T: type) !T {
            const format = try self.encoded_reader.readByte();
            const array_len = switch (@as(Type, @enumFromInt(format))) {
                .Array16 => try self.encoded_reader.readInt(u16, .big),
                .Array32 => try self.encoded_reader.readInt(u32, .big),
                else => {
                    if (format & TypeMask.FixArray == TypeMask.FixArray)
                        return format & ~TypeMask.FixStr
                    else
                        unreachable;
                },
            };

            const fields = meta.fields(T);
            if (fields.len != array_len) unreachable;

            var object: T = undefined;
            inline for (meta.fields(fields)) |f| {
                @field(object, f.name) = try self.read(f.type);
            }
            return object;
        }
    };
}

pub fn decoder(reader: anytype) Decoder(@TypeOf(reader)) {
    return .{ .encoded_reader = reader };
}

fn byteFromInt(num: usize) usize {
    return switch (num) {
        0...maxInt(u8) => 1,
        maxInt(u8) + 1...maxInt(u16) => 2,
        maxInt(u16) + 1...maxInt(u32) => 4,
        else => unreachable,
    };
}

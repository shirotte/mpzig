const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const meta = std.meta;
const assert = std.debug.assert;
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
    PosFixInt = 0,
    NegFixInt = @shlExact(0b111, 5),
    FixMap = @shlExact(0b1000, 4),
    FixArray = @shlExact(0b1001, 4),
    FixStr = @shlExact(0b101, 5),

    pub fn fromType(t: Type) !TypeMask {
        const n = @intFromEnum(t);
        return switch (n) {
            0x00...0x7F => .PosFixInt,
            0x80...0x8F => .FixMap,
            0x90...0x9F => .FixArray,
            0xA0...0xBF => .FixStr,
            0xE0...0xFF => .NegFixInt,
            else => unreachable,
        };
    }
};

pub fn Encoder(comptime WriterType: type) type {
    return struct {
        writer: WriterType,

        pub const Error = WriterType.Error;
        pub const Writer = WriterType;

        const Self = @This();

        pub fn encode(self: *Self, value: anytype) Error!void {
            return switch (@typeInfo(@TypeOf(value))) {
                .bool => self.encodeBool(value),
                .int => self.encodeInt(@TypeOf(value), value),
                .float => self.encodeFloat(@TypeOf(value), value),
                .pointer => self.encodeStr(value),
                .@"struct" => self.encodeArray(value),
                else => unreachable,
            };
        }

        pub fn encodeNil(self: *Self) Error!void {
            return self.writer.writeByte(@intFromEnum(Type.Nil));
        }

        pub fn encodeBool(self: *Self, value: bool) Error!void {
            const byte = if (value) @intFromEnum(Type.True) else @intFromEnum(Type.False);
            return self.writer.writeByte(byte);
        }

        pub fn encodeInt(self: *Self, comptime T: type, value: T) Error!void {
            const format: u8 = switch (T) {
                u8 => @intFromEnum(Type.Uint8),
                u16 => @intFromEnum(Type.Uint16),
                u32 => @intFromEnum(Type.Uint32),
                u64 => @intFromEnum(Type.Uint64),
                i8 => @intFromEnum(Type.Int8),
                i16 => @intFromEnum(Type.Int16),
                i32 => @intFromEnum(Type.Int32),
                i64 => @intFromEnum(Type.Int64),
                else => {
                    return if (value >= 0x00 and value <= 0x7F) {
                        return self.writer.writeByte(@intCast(value));
                    } else if (value <= 0x00 and value >= -0x1F) {
                        return self.writer.writeByte(@bitCast(value));
                    } else {
                        unreachable;
                    };
                },
            };

            try self.writer.writeByte(format);
            try self.writer.writeInt(T, value, .big);
        }

        pub fn encodeFloat(self: *Self, comptime T: type, value: T) Error!void {
            const format: u8 = switch (T) {
                f32 => @intFromEnum(Type.Float32),
                f64 => @intFromEnum(Type.Float64),
                else => unreachable,
            };
            try self.writer.writeByte(format);

            @setFloatMode(.strict);
            const bytes: [@sizeOf(T)]u8 = @bitCast(value);
            try self.writer.writeAll(&bytes);
        }

        pub fn encodeStr(self: *Self, value: []const u8) Error!void {
            const format: u8 = switch (value.len) {
                0...maxInt(u4) => {
                    try self.writer.writeByte(@intFromEnum(TypeMask.FixStr) | @as(u8, @intCast(value.len)));
                    return self.writer.writeAll(value);
                },
                maxInt(u4) + 1...maxInt(u8) => @intFromEnum(Type.Str8),
                maxInt(u8) + 1...maxInt(u16) => @intFromEnum(Type.Str16),
                maxInt(u16) + 1...maxInt(u32) => @intFromEnum(Type.Str32),
                else => unreachable,
            };

            try self.writeFormatAll(format, value);
        }

        pub fn encodeBin(self: *Self, value: []const u8) Error!void {
            const format: u8 = switch (value.len) {
                0...maxInt(u8) => @intFromEnum(Type.Bin8),
                maxInt(u8) + 1...maxInt(u16) => @intFromEnum(Type.Bin16),
                maxInt(u16) + 1...maxInt(u32) => @intFromEnum(Type.Bin32),
                else => unreachable,
            };
            self.writeFormatAll(format, value);
        }

        pub fn encodeArray(self: *Self, value: anytype) Error!void {
            const fields = meta.fields(@TypeOf(value));
            switch (fields.len) {
                0...maxInt(u4) => {
                    try self.writer.writeByte(@intFromEnum(TypeMask.FixArray) | @as(u8, @intCast(fields.len)));
                },
                maxInt(u4)+1...maxInt(u16) => {
                    const bytes: [@sizeOf(u8) + @sizeOf(u16)]u8 = .{@intFromEnum(Type.Array16)} ++ @as([2]u8, @bitCast(fields.len));
                    try self.writer.encodeAll(bytes);
                },
                maxInt(u16)+1...maxInt(u32) => {
                    const bytes: [@sizeOf(u8) + @sizeOf(u32)]u8 = .{@intFromEnum(Type.Array16)} ++ @as([4]u8, @bitCast(fields.len));
                    try self.writer.encodeAll(bytes);
                },
                else => unreachable,
            }

            inline for (fields) |f| {
                try self.encode(@field(value, f.name));
            }
        }

        fn writeFormatAll(self: *Self, format: u8, value: []const u8) Error!void {
            try self.writer.writeByte(format);

            const bin_len: [@sizeOf(usize)]u8 = @bitCast(nativeToBig(usize, value.len));
            try self.writer.writeAll(bin_len[bin_len.len - byteFromInt(value.len) ..]);
            try self.writer.writeAll(value);
        }
    };
}

pub fn encoder(writer: anytype) Encoder(@TypeOf(writer)) {
    return .{ .writer = writer };
}

pub const Value = union(enum) {
    nil: void,
    bool: bool,
    int: i64,
    uint: u64,
    float: f64,
    raw: []const u8,
    value: ?@This(),
};

pub fn Decoder(comptime ReaderType: type) type {
    return struct {
        reader: ReaderType,
        arena: ArenaAllocator,

        pub const Error = ReaderType.Error || error{ EndOfStream, OutOfMemory, StreamTooLong };
        const Self = @This();

        pub fn init(allocator: Allocator, io_reader: ReaderType) Self {
            return .{
                .arena = ArenaAllocator.init(allocator),
                .reader = io_reader,
            };
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }

        pub fn decode(self: *Self, comptime T: type) Error!T {
            return switch (@typeInfo(T)) {
                .bool => self.decodeBool(),
                .int => self.decodeInt(T),
                .float => self.decodeFloat(T),
                .@"struct" => self.decodeStruct(T),
                .pointer => self.decodeRaw(),
                else => unreachable,
            };
        }

        pub fn decodeDynamic(self: *Self) Error!Value {
            const format = self.reader.readByte();
            return switch (format) {
                .Nil => Value{.nil},
                .False => Value{ .bool = false },
                .True => Value{ .bool = true },
                .Bin8, .Bin16, .Bin32 => Value{.nil},
                .Ext8, .Ext16, .Ext32 => unreachable,
                .Float32, .Float64 => self.readDynamicFloat(format),
                .Uint8, .Uint16, .Uint32, .Uint64, .Int8, .Int16, .Int32, .Int64 => self.readDynamicInt(),
                .Fixext1, .Fixext2, .Fixext4, .Fixext8, .Fixext16 => Value{.nil},
                .Str8, .Str16, .Str32 => Value{ .raw = self.readStr(format) },
                .Array8, .Array16, .Array32 => unreachable,
                .Map16, .Map32, ._ => unreachable,
                else => unreachable,
            };
        }

        pub fn decodeNil(self: *Self) Error!void {
            const format = try self.readFormat();
            return self.readNil(format);
        }

        pub fn decodeBool(self: *Self) Error!bool {
            const format = try self.readFormat();
            return self.readBool(format);
        }

        pub fn decodeInt(self: *Self, comptime T: type) Error!T {
            const format = try self.readFormat();
            return self.readInt(T, format);
        }

        pub fn decodeFloat(self: *Self, comptime T: type) Error!T {
            const format = try self.readFormat();
            return self.readFloat(T, format);
        }

        pub fn decodeRaw(self: *Self) Error![]u8 {
            const format = try self.readFormat();
            return switch (format) {
                .Str8, .Str16, .Str32 => self.readStr(format),
                .Bin8, .Bin16, .Bin32 => self.readBin(format),
                else => {
                    if (try TypeMask.fromType(format) == .FixStr)
                        return self.readStr(format);
                    unreachable;
                },
            };
        }

        pub fn decodeStruct(self: *Self, comptime T: type) Error!T {
            const format = try self.readFormat();
            return switch (format) {
                .Array16, .Array32 => self.readArray(T, format),
                else => if (try TypeMask.fromType(format) == .FixArray) self.readArray(T, format) else unreachable,
            };
        }

        fn readFormat(self: *Self) Error!Type {
            const format = try self.reader.readByte();
            return @enumFromInt(format);
        }

        fn readNil(self: *Self, format: Type) Error!void {
            _ = self;
            if (format != .Nil)
                unreachable;
        }

        fn readBool(self: *Self, format: Type) Error!bool {
            _ = self;
            return switch (format) {
                .False => false,
                .True => true,
                else => unreachable,
            };
        }

        fn readInt(self: *Self, comptime T: type, format: Type) Error!T {
            if (@intFromEnum(format) <= 0x7F)
                return @intCast(@intFromEnum(format));
            if (@intFromEnum(format) >= 0xE0)
                return @intCast(@intFromEnum(format));

            return self.reader.readInt(T, .big);
        }

        fn readDynamicInt(self: *Self, format: Type) Error!Value {
            return switch (format) {
                .Uint8 => Value{ .uint = try self.readInt(u8, format) },
                .Uint16 => Value{ .uint = try self.readInt(u16, format) },
                .Uint32 => Value{ .uint = try self.readInt(u32, format) },
                .Uint64 => Value{ .uint = try self.readInt(u64, format) },
                .Int8 => Value{ .int = try self.readInt(i8, format) },
                .Int16 => Value{ .int = try self.readInt(i16, format) },
                .Int32 => Value{ .int = try self.readInt(i32, format) },
                .Int64 => Value{ .int = try self.readInt(i64, format) },
                else => {
                    return switch (TypeMask.fromType(format)) {
                        .PosFixInt => Value{ .int = try self.readInt(u8) },
                        .NegFixInt => Value{ .int = try self.readINt(i8) },
                        else => unreachable,
                    };
                },
            };
        }

        pub fn readFloat(self: *Self, comptime T: type, format: Type) Error!T {
            const type_check = switch (format) {
                .Float32 => T == f32,
                .Float64 => T == f64,
                else => unreachable,
            };
            assert(type_check);

            var buffer: [@sizeOf(T)]u8 = undefined;
            if (try self.reader.readAll(&buffer) == buffer.len)
                return @bitCast(buffer);
            unreachable;
        }

        pub fn readDynamicFloat (self: *Self, format: Type) Error!Value {
            return switch (format) {
                .Float32 => Value{ .float = self.readFloat(f32, format) },
                .Float64 => Value{ .float = self.readFloat(f64, format) },
                else => unreachable,
            };
        }

        pub fn readStr(self: *Self, format: Type) Error![]u8 {
            const str_len = switch (format) {
                .Str8 => try self.reader.readByte(),
                .Str16 => try self.reader.readInt(u16, .big),
                .Str32 => try self.reader.readInt(u32, .big),
                else => @intFromEnum(format) & ~@intFromEnum(TypeMask.FixStr),
            };

            const allocator = self.arena.allocator();
            const buffer = try allocator.alloc(u8, str_len);
            _ = try self.reader.readAll(buffer);
            return buffer;
        }

        pub fn readBin(self: *Self, format: Type) Error![]u8 {
            const bin_len = switch (format) {
                .Bin8 => try self.reader.readByte(),
                .Bin16 => try self.reader.readInt(u16, .big),
                .Bin32 => try self.reader.readInt(u32, .big),
                else => unreachable,
            };

            const allocator = self.arena.allocator();
            return self.reader.readAllAlloc(allocator, bin_len);
        }

        fn readArray(self: *Self, comptime T: type, format: Type) Error!T {
            const array_len = switch (format) {
                .Array16 => try self.reader.readInt(u16, .big),
                .Array32 => try self.reader.readInt(u32, .big),
                else => @intFromEnum(format) & ~@intFromEnum(TypeMask.FixArray),
            };

            const fields = meta.fields(T);
            if (fields.len != array_len) unreachable;

            var object: T = undefined;
            inline for (fields) |f| {
                @field(object, f.name) = try self.decode(f.type);
            }
            return object;
        }
    };
}

pub fn decoder(allocator: Allocator, reader: anytype) Decoder(@TypeOf(reader)) {
    return Decoder(@TypeOf(reader)).init(allocator, reader);
}

fn byteFromInt(num: usize) usize {
    return switch (num) {
        0...maxInt(u8) => 1,
        maxInt(u8) + 1...maxInt(u16) => 2,
        maxInt(u16) + 1...maxInt(u32) => 4,
        else => unreachable,
    };
}

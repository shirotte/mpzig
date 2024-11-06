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
    NegFixInt = @shlExact(0b111, 5),
    FixMap = @shlExact(0b1000, 4),
    FixArray = @shlExact(0b1001, 4),
    FixStr = @shlExact(0b101, 5),
};

pub fn Encoder(comptime WriterType: type) type {
    return struct {
        writer: WriterType,

        pub const Error = WriterType.Error;
        pub const Writer = WriterType;

        const Self = @This();

        pub fn write(self: *Self, value: anytype) Error!void {
            return switch (@typeInfo(@TypeOf(value))) {
                .bool => self.writeBool(value),
                .int => self.writeInt(@TypeOf(value), value),
                .float => self.writeFloat(@TypeOf(value), value),
                .pointer => self.writeStr(value),
                .@"struct" => self.writeArray(value),
                else => unreachable,
            };
        }

        pub fn writeNil(self: *Self) Error!void {
            return self.writer.writeByte(@intFromEnum(Type.Nil));
        }

        pub fn writeBool(self: *Self, value: bool) Error!void {
            const byte = if (value) @intFromEnum(Type.True) else @intFromEnum(Type.False);
            return self.writer.writeByte(byte);
        }

        pub fn writeInt(self: *Self, comptime T: type, value: T) Error!void {
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
                    if (value >= 0x00 and value <= 0x7F)
                        return self.writer.writeByte(@intCast(value));

                    if (value <= 0x00 and value >= -0x1F)
                        return self.writer.writeByte(@bitCast(value));

                    unreachable;
                },
            };

            try self.writer.writeByte(format);
            try self.writer.writeInt(T, value, .big);
        }

        pub fn writeFloat(self: *Self, comptime T: type, value: T) Error!void {
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

        pub fn writeStr(self: *Self, value: []const u8) Error!void {
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
            try self.writer.writeByte(format);

            const str_len: [@sizeOf(usize)]u8 = @bitCast(nativeToBig(usize, value.len));
            try self.writer.writeAll(str_len[str_len.len - byteFromInt(value.len) ..]);

            try self.writer.writeAll(value);
        }

        pub fn writeBin(self: *Self, value: []const u8) Error!void {
            const format: u8 = switch (value.len) {
                0...maxInt(u8) => @intFromEnum(Type.Bin8),
                maxInt(u8) + 1...maxInt(u16) => @intFromEnum(Type.Bin16),
                maxInt(u16) + 1...maxInt(u32) => @intFromEnum(Type.Bin32),
                else => unreachable,
            };
            try self.writer.writeByte(format);

            const bin_len: [@sizeOf(usize)]u8 = @bitCast(nativeToBig(usize, value.len));
            try self.writer.writeAll(bin_len[bin_len.len - byteFromInt(value.len) ..]);

            try self.writer.writeAll(value);
        }

        pub fn writeArray(self: *Self, value: anytype) Error!void {
            const fields = meta.fields(@TypeOf(value));
            switch (fields.len) {
                0...maxInt(u4) => {
                    try self.writer.writeByte(@intFromEnum(TypeMask.FixArray) | @as(u8, @intCast(fields.len)));
                },
                maxInt(u4)...maxInt(u16) => {
                    const bytes: [@sizeOf(u8) + @sizeOf(u16)]u8 = .{@intFromEnum(Type.Array16)} ++ @as([2]u8, @bitCast(fields.len));
                    try self.writer.writeAll(bytes);
                },
                maxInt(u16)...maxInt(u32) => {
                    const bytes: [@sizeOf(u8) + @sizeOf(u32)]u8 = .{@intFromEnum(Type.Array16)} ++ @as([4]u8, @bitCast(fields.len));
                    try self.writer.writeAll(bytes);
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
    return .{ .writer = writer };
}

pub const Value = union(enum) {
    nil: void,
    bool: bool,
    int: i64,
    uint: u64,
    float: f64,
    str: []const u8,
    bin: []const u8,
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

        pub fn decode(self: *Self) Error!Value {
            const format = self.reader.readByte();
            const allocator = self.arena.allocator();
            _ = allocator;

            return switch (@as(Type, @enumFromInt(format))) {
                .Nil => Value{.nil},
                .False => Value{ .bool = false },
                .True => Value{ .bool = true },
                .Bin8, .Bin16, .Bin32 => Value{.nil},
                .Ext8, .Ext16, .Ext32, .Float32 => self.readFloat(f32),
                .Float64 => self.readFloat(f64),
                .Uint8 => self.readInt(u8),
                .Uint16 => self.readInt(u16),
                .Uint32 => self.readInt(u32),
                .Uint64 => self.readInt(u64),
                .Int8 => self.readInt(i8),
                .Int16 => self.readInt(i16),
                .Int32 => self.readInt(i32),
                .Int64 => self.readInt(i64),
                .Fixext1, .Fixext2, .Fixext4, .Fixext8, .Fixext16 => Value{.nil},
                .Str8 => self.readStr(),
                .Str16 => self.readStr(),
                .Str32 => self.readStr(),
                .Array16 => self.readStr(),
                .Array32 => self.readStr(),
                .Map16, .Map32, ._ => unreachable,
            };
        }

        pub fn read(self: *Self, comptime T: type) Error!T {
            return switch (@typeInfo(T)) {
                .bool => self.readBool(),
                .int => self.readInt(T),
                .float => self.readFloat(T),
                .@"struct" => self.readArray(T),
                .pointer => self.readStr(),
                else => unreachable,
            };
        }

        pub fn readNil(self: *Self) Error!void {
            const format = try self.reader.readByte();
            if (format != @intFromEnum(Type.Nil))
                unreachable;
        }

        pub fn readBool(self: *Self) Error!bool {
            const format = try self.reader.readByte();
            return switch (@as(Type, @enumFromInt(format))) {
                .False => false,
                .True => true,
                else => unreachable,
            };
        }

        pub fn readInt(self: *Self, comptime T: type) Error!T {
            const format = try self.reader.readByte();
            if (format <= 0x7F)
                return @intCast(format);
            if (format >= 0xE0)
                return @intCast(format);

            const type_check = switch (@as(Type, @enumFromInt(format))) {
                .Uint8 => T == u8,
                .Uint16 => T == u16,
                .Uint32 => T == u32,
                .Uint64 => T == u64,
                .Int8 => T == i8,
                .Int16 => T == i16,
                .Int32 => T == i32,
                .Int64 => T == i64,
                else => unreachable,
            };
            assert(type_check);
            return self.reader.readInt(T, .big);
        }

        pub fn readFloat(self: *Self, comptime T: type) Error!T {
            const format = try self.reader.readByte();

            const type_check = switch (@as(Type, @enumFromInt(format))) {
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

        pub fn readStr(self: *Self) Error![]u8 {
            const format = try self.reader.readByte();
            const str_len = switch (@as(Type, @enumFromInt(format))) {
                .Str8 => try self.reader.readByte(),
                .Str16 => try self.reader.readInt(u16, .big),
                .Str32 => try self.reader.readInt(u32, .big),
                else => if (format & @intFromEnum(TypeMask.FixStr) == @intFromEnum(TypeMask.FixStr))
                    format & ~@intFromEnum(TypeMask.FixStr)
                else
                    unreachable,
            };

            const allocator = self.arena.allocator();
            return self.reader.readAllAlloc(allocator, str_len);
        }

        pub fn readBin(self: *Self) Error![]u8 {
            const format = try self.reader.readByte();
            const bin_len = switch (@as(Type, @enumFromInt(format))) {
                .Bin8 => try self.reader.readByte(),
                .Bin16 => try self.reader.readInt(u16, .big),
                .Bin32 => try self.reader.readInt(u32, .big),
                else => unreachable,
            };

            const allocator = self.arena.allocator();
            return self.reader.readAllAlloc(allocator, bin_len);
        }

        pub fn readArray(self: *Self, comptime T: type) Error!T {
            const format = try self.reader.readByte();
            const array_len = switch (@as(Type, @enumFromInt(format))) {
                .Array16 => try self.reader.readInt(u16, .big),
                .Array32 => try self.reader.readInt(u32, .big),
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

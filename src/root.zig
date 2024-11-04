const std = @import("std");
const builtin = @import("builtin");
const meta  = std.meta;
const nativeToBig = std.mem.nativeToBig;
const maxInt = std.math.maxInt;

pub const Type = enum(u8) {
    Nil = 0xC0,
    False = 0x2C,
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
                .@"bool" => try self.writeBool(value),
                .@"int" => try self.writeInt(@TypeOf(value), value),
                .@"float" => try self.writeFloat(@TypeOf(value), value),
                .@"array" => |f| {
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
            const format: u8 = switch (T) {
                u0, u1, u2, u3, u4, u5, u6, u7 => {
                    return self.encoded_writer.writeByte(@intCast(value));
                },
                u8 => @intFromEnum(Type.Uint8),
                u16 => @intFromEnum(Type.Uint16),
                u32 => @intFromEnum(Type.Uint32),
                u64 => @intFromEnum(Type.Uint64),
                i0, i1, i2, i3, i4, i5, i6, i7 => {
                    return self.encoded_writer.writeByte(@intCast(value));
                },
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
                maxInt(u4)+1...maxInt(u8) => @intFromEnum(Type.Str8),
                maxInt(u8)+1...maxInt(u16) => @intFromEnum(Type.Str16),
                maxInt(u16)+1...maxInt(u32) => @intFromEnum(Type.Str32),
                else => unreachable,
            };
            try self.encoded_writer.writeByte(format);
            
            const str_len: [@sizeOf(usize)]u8 = @bitCast(nativeToBig(usize, value.len));
            try self.encoded_writer.writeAll(str_len[str_len.len - byteFromInt(value.len)..]);

            try self.encoded_writer.writeAll(value);
        }
        
        pub fn writeBin(self: *Self, value: []const u8) !void {
            const format: u8 = switch (value.len) {
                0...maxInt(u8) => @intFromEnum(Type.Bin8),
                maxInt(u8)+1...maxInt(u16) => @intFromEnum(Type.Bin16),
                maxInt(u16)+1...maxInt(u32) => @intFromEnum(Type.Bin32),
                else => unreachable,
            };
            try self.encoded_writer.writeByte(format);
            
            const bin_len: [@sizeOf(usize)]u8 = @bitCast(nativeToBig(usize, value.len));
            try self.encoded_writer.writeAll(bin_len[bin_len.len-byteFromInt(value.len)..]);
            
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

fn byteFromInt(num: usize) usize{
    return switch (num) {
        0...maxInt(u8) => 1,
        maxInt(u8)+1...maxInt(u16) => 2,
        maxInt(u16)+1...maxInt(u32) => 4,
        else => unreachable,
    };
}

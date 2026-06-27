const std = @import("std");
const constant = @import("constant.zig");

pub const Flags = struct {
    qr: constant.QR,
    opcode: constant.OPCODE,
    aa: constant.AA,
    tc: constant.TC,
    rd: constant.RD,
    ra: constant.RA,
    z: u3,
    rcode: constant.RCODE,

    pub fn decode(v: u16) Flags {
        return .{
            .qr = @enumFromInt(@as(u1, @truncate(v >> 15))),
            .opcode = @enumFromInt(@as(u4, @truncate(v >> 11))),
            .aa = @enumFromInt(@as(u1, @truncate(v >> 10))),
            .tc = @enumFromInt(@as(u1, @truncate(v >> 9))),
            .rd = @enumFromInt(@as(u1, @truncate(v >> 8))),
            .ra = @enumFromInt(@as(u1, @truncate(v >> 7))),
            .z = @truncate(v >> 4),
            .rcode = @enumFromInt(@as(u4, @truncate(v))),
        };
    }

    pub fn encode(self: Flags) u16 {
        return (@as(u16, @intFromEnum(self.qr)) << 15) |
            (@as(u16, @intFromEnum(self.opcode)) << 11) |
            (@as(u16, @intFromEnum(self.aa)) << 10) |
            (@as(u16, @intFromEnum(self.tc)) << 9) |
            (@as(u16, @intFromEnum(self.rd)) << 8) |
            (@as(u16, @intFromEnum(self.ra)) << 7) |
            (@as(u16, self.z) << 4) |
            (@as(u16, @intFromEnum(self.rcode)));
    }
};

pub const Header = struct {
    id: u16,
    flags: Flags,
    qd: u16,
    an: u16,
    ns: u16,
    ar: u16,

    pub fn decode(v: []const u8) Header {
        return .{
            .id = std.mem.readInt(u16, v[0..2], .big),
            .flags = Flags.decode(
                std.mem.readInt(u16, v[2..4], .big),
            ),
            .qd = std.mem.readInt(u16, v[4..6], .big),
            .an = std.mem.readInt(u16, v[6..8], .big),
            .ns = std.mem.readInt(u16, v[8..10], .big),
            .ar = std.mem.readInt(u16, v[10..12], .big),
        };
    }

    pub fn encode(self: Header, allocator: std.mem.Allocator) ![]u8 {
        const buffer = try allocator.alloc(u8, 12);

        std.mem.writeInt(u16, buffer[0..2], self.id, .big);
        std.mem.writeInt(u16, buffer[2..4], self.flags.encode(), .big);
        std.mem.writeInt(u16, buffer[4..6], self.qd, .big);
        std.mem.writeInt(u16, buffer[6..8], self.an, .big);
        std.mem.writeInt(u16, buffer[8..10], self.ns, .big);
        std.mem.writeInt(u16, buffer[10..12], self.ar, .big);

        return buffer;
    }
};

pub const Question = struct {
    raw: []const u8,
    type: constant.TYPE,
    class: constant.CLASS,

    pub fn decode(v: []const u8) Question {
        var len: usize = 0;
        var index: usize = 0;

        while (true) {
            const label = v[index];

            len += 1;
            index += 1;

            if (label == 0) {
                break;
            }

            len += label;
            index += label;
        }

        const types = v[len..][0..2];
        const class = v[len + 2 ..][0..2];

        return Question{
            .raw = v[0..len],
            .type = @enumFromInt(std.mem.readInt(u16, types, .big)),
            .class = @enumFromInt(std.mem.readInt(u16, class, .big)),
        };
    }

    pub fn encode(self: Question, allocator: std.mem.Allocator) ![]u8 {
        const buffer = try allocator.alloc(u8, self.raw.len + 4);

        @memcpy(buffer[0..self.raw.len], self.raw);

        const offset = self.raw.len;
        std.mem.writeInt(u16, buffer[offset..][0..2], @intFromEnum(self.type), .big);
        std.mem.writeInt(u16, buffer[offset + 2 ..][0..2], @intFromEnum(self.class), .big);

        return buffer;
    }

    pub fn getName(self: Question, allocator: std.mem.Allocator) ![]u8 {
        var respond: std.ArrayList(u8) = .empty;
        errdefer respond.deinit(allocator);

        var index: usize = 0;
        while (index < self.raw.len) {
            const label = self.raw[index];

            if (label == 0) {
                break;
            }

            index += 1;

            if (respond.items.len > 0) {
                try respond.append(allocator, '.');
            }

            try respond.appendSlice(allocator, self.raw[index .. index + label]);
            index += label;
        }

        return respond.toOwnedSlice(allocator);
    }
};

pub const Answer = struct {
    name: []const u8,
    type: constant.TYPE,
    class: constant.CLASS,
    ttl: u32,
    data: []const u8,

    pub fn decode(v: []const u8) Answer {
        var offset: usize = 0;

        if ((v[0] & 0xc0) == 0xc0) {
            offset = 2;
        } else {
            while (true) {
                const label = v[offset];

                offset += 1;

                if (label == 0) {
                    break;
                }

                offset += label;
            }
        }

        const name = v[0..offset];

        const types: constant.TYPE = @enumFromInt(std.mem.readInt(u16, v[offset..][0..2], .big));
        const class: constant.CLASS = @enumFromInt(std.mem.readInt(u16, v[offset..][2..4], .big));
        const ttl = std.mem.readInt(u32, v[offset..][4..8], .big);
        const len = std.mem.readInt(u16, v[offset..][8..10], .big);
        const data = v[offset + 10 .. offset + len + 10];

        return .{
            .name = name,
            .type = types,
            .class = class,
            .ttl = ttl,
            .data = data,
        };
    }

    pub fn encode(self: Answer, allocator: std.mem.Allocator) ![]u8 {
        const buffer = try allocator.alloc(u8, self.name.len + self.data.len + 10);

        @memcpy(buffer[0..self.name.len], self.name);

        const offset: usize = self.name.len;
        std.mem.writeInt(u16, buffer[offset..][0..2], @intFromEnum(self.type), .big);
        std.mem.writeInt(u16, buffer[offset..][2..4], @intFromEnum(self.class), .big);
        std.mem.writeInt(u32, buffer[offset..][4..8], self.ttl, .big);
        std.mem.writeInt(u16, buffer[offset..][8..10], @intCast(self.data.len), .big);

        @memcpy(buffer[offset + 10 .. offset + self.data.len + 10], self.data);

        return buffer;
    }
};

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
        var respond: std.ArrayList(u8) = .empty;
        errdefer respond.deinit(allocator);

        var buffer: [12]u8 = undefined;
        std.mem.writeInt(u16, buffer[0..2], self.id, .big);
        std.mem.writeInt(u16, buffer[2..4], self.flags.encode(), .big);
        std.mem.writeInt(u16, buffer[4..6], self.qd, .big);
        std.mem.writeInt(u16, buffer[6..8], self.an, .big);
        std.mem.writeInt(u16, buffer[8..10], self.ns, .big);
        std.mem.writeInt(u16, buffer[10..12], self.ar, .big);

        try respond.appendSlice(allocator, &buffer);
        return try respond.toOwnedSlice(allocator);
    }
};

pub const Question = struct {
    raw: []const u8,
    type: u16,
    class: u16,

    pub fn decode(v: []const u8) Question {
        var index: usize = 0;
        var name_len: usize = 0;

        while (true) {
            const label_len = v[index];
            if (label_len == 0) {
                name_len += 1;
                index += 1;
                break;
            }
            name_len += 1 + label_len;
            index += 1 + label_len;
        }

        const type_bytes = v[name_len..][0..2];
        const class_bytes = v[name_len + 2 ..][0..2];

        return Question{
            .raw = v[0..name_len],
            .type = std.mem.readInt(u16, type_bytes, .big),
            .class = std.mem.readInt(u16, class_bytes, .big),
        };
    }

    pub fn encode(self: Question, allocator: std.mem.Allocator) ![]u8 {
        var respond: std.ArrayList(u8) = .empty;
        errdefer respond.deinit(allocator);

        var buffer: [4]u8 = undefined;
        std.mem.writeInt(u16, buffer[0..2], self.type, .big);
        std.mem.writeInt(u16, buffer[2..4], self.class, .big);

        try respond.appendSlice(allocator, self.raw);
        try respond.appendSlice(allocator, &buffer);

        return try respond.toOwnedSlice(allocator);
    }

    pub fn getName(self: Question, allocator: std.mem.Allocator) ![]u8 {
        var respond: std.ArrayList(u8) = .empty;
        errdefer respond.deinit(allocator);

        var index: usize = 0;
        while (index < self.raw.len) {
            const label_len = self.raw[index];
            if (label_len == 0) {
                break;
            }

            index += 1;

            if (respond.items.len > 0) {
                try respond.append(allocator, '.');
            }

            try respond.appendSlice(allocator, self.raw[index .. index + label_len]);
            index += label_len;
        }

        return respond.toOwnedSlice(allocator);
    }
};

pub const Answer = struct {
    name: []const u8,
    type: u16,
    class: u16,
    ttl: u32,
    rdata: []const u8,

    pub fn encode(self: Answer, allocator: std.mem.Allocator) ![]u8 {
        var respond: std.ArrayList(u8) = .empty;
        errdefer respond.deinit(allocator);

        var buffer: [10]u8 = undefined;
        std.mem.writeInt(u16, buffer[0..2], self.type, .big);
        std.mem.writeInt(u16, buffer[2..4], self.class, .big);
        std.mem.writeInt(u32, buffer[4..8], self.ttl, .big);
        std.mem.writeInt(u16, buffer[8..10], @intCast(self.rdata.len), .big);

        try respond.appendSlice(allocator, self.name);
        try respond.appendSlice(allocator, &buffer);
        try respond.appendSlice(allocator, self.rdata);

        return try respond.toOwnedSlice(allocator);
    }
};

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
        const qr: u1 = @truncate(v >> 15);
        const op: u4 = @truncate(v >> 11);
        const aa: u1 = @truncate(v >> 10);
        const tc: u1 = @truncate(v >> 9);
        const rd: u1 = @truncate(v >> 8);
        const ra: u1 = @truncate(v >> 7);
        const z: u3 = @truncate(v >> 4);
        const rc: u1 = @truncate(v);

        return .{
            .qr = @enumFromInt(qr),
            .opcode = @enumFromInt(op),
            .aa = @enumFromInt(aa),
            .tc = @enumFromInt(tc),
            .rd = @enumFromInt(rd),
            .ra = @enumFromInt(ra),
            .z = z,
            .rcode = @enumFromInt(rc),
        };
    }

    pub fn encode(self: Flags) u16 {
        const qr: u16 = @intCast(@intFromEnum(self.qr));
        const op: u16 = @intCast(@intFromEnum(self.opcode));
        const aa: u16 = @intCast(@intFromEnum(self.aa));
        const tc: u16 = @intCast(@intFromEnum(self.tc));
        const rd: u16 = @intCast(@intFromEnum(self.rd));
        const ra: u16 = @intCast(@intFromEnum(self.ra));
        const z: u16 = @intCast(self.z);
        const rc: u16 = @intCast(@intFromEnum(self.rcode));

        return qr << 15 | op << 11 | aa << 10 | tc << 9 | rd << 8 | ra << 7 | z << 4 | rc;
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
        const id = std.mem.readInt(u16, v[0..2], .big);
        const fl = std.mem.readInt(u16, v[2..4], .big);
        const qd = std.mem.readInt(u16, v[4..6], .big);
        const an = std.mem.readInt(u16, v[6..8], .big);
        const ns = std.mem.readInt(u16, v[8..10], .big);
        const ar = std.mem.readInt(u16, v[10..12], .big);

        return .{
            .id = id,
            .flags = Flags.decode(fl),
            .qd = qd,
            .an = an,
            .ns = ns,
            .ar = ar,
        };
    }

    pub fn encode(self: Header, writer: *std.Io.Writer) !void {
        var buffer: [12]u8 = undefined;

        std.mem.writeInt(u16, buffer[0..2], self.id, .big);
        std.mem.writeInt(u16, buffer[2..4], self.flags.encode(), .big);
        std.mem.writeInt(u16, buffer[4..6], self.qd, .big);
        std.mem.writeInt(u16, buffer[6..8], self.an, .big);
        std.mem.writeInt(u16, buffer[8..10], self.ns, .big);
        std.mem.writeInt(u16, buffer[10..12], self.ar, .big);

        try writer.writeAll(&buffer);
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

    pub fn encode(self: Question, writer: *std.Io.Writer) !void {
        var buffer: [4]u8 = undefined;

        std.mem.writeInt(u16, buffer[0..2], @intFromEnum(self.type), .big);
        std.mem.writeInt(u16, buffer[2..4], @intFromEnum(self.class), .big);

        try writer.writeAll(self.raw);
        try writer.writeAll(&buffer);
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

        while (true) {
            const label = v[offset];

            if ((label & 0xc0) == 0xc0) {
                offset = 2;
                break;
            }

            offset += 1;

            if (label == 0) {
                break;
            }

            offset += label;
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

    pub fn encode(self: Answer, writer: *std.Io.Writer) !void {
        var buffer: [10]u8 = undefined;

        std.mem.writeInt(u16, buffer[0..2], @intFromEnum(self.type), .big);
        std.mem.writeInt(u16, buffer[2..4], @intFromEnum(self.class), .big);
        std.mem.writeInt(u32, buffer[4..8], self.ttl, .big);
        std.mem.writeInt(u16, buffer[8..10], @intCast(self.data.len), .big);

        try writer.writeAll(self.name);
        try writer.writeAll(&buffer);
        try writer.writeAll(self.data);
    }
};

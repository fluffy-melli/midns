const std = @import("std");
const protocol = @import("protocol");

pub const Listener = struct {
    io: std.Io,
    allocator: std.mem.Allocator,

    addr: std.Io.net.IpAddress,
    socket: std.Io.net.Socket,

    pub fn new(io: std.Io, allocator: std.mem.Allocator, ip: []const u8, port: u16) !Listener {
        const addr = try std.Io.net.IpAddress.parse(ip, port);

        const socket = try std.Io.net.IpAddress.bind(&addr, io, .{
            .mode = .dgram,
            .protocol = .udp,
        });

        return .{
            .io = io,
            .allocator = allocator,
            .addr = addr,
            .socket = socket,
        };
    }

    pub fn deinit(self: *Listener) void {
        self.socket.close(self.io);
    }

    pub fn serve(self: *Listener) !void {
        var buffer: [512]u8 = undefined;
        while (true) {
            const packet = try self.socket.receive(self.io, &buffer);

            var header = protocol.Header.decode(packet.data[0..12]);
            const question = protocol.Question.decode(packet.data[12..]);

            const answer = protocol.Answer{
                .name = &[_]u8{ 0xc0, 0x0c },
                .type = .A,
                .class = .IN,
                .ttl = 300,
                .data = &[_]u8{ 127, 0, 0, 1 },
            };

            header.flags.aa = .Authoritative;
            header.flags.qr = .Response;
            header.flags.tc = .NotTruncated;
            header.flags.rcode = .NOERROR;

            header.qd = 1;
            header.an = 1;
            header.ns = 0;
            header.ar = 0;

            var respond: std.ArrayList(u8) = .empty;
            defer respond.deinit(self.allocator);

            const headerR = try header.encode(self.allocator);
            defer self.allocator.free(headerR);

            const questionR = try question.encode(self.allocator);
            defer self.allocator.free(questionR);

            const answerR = try answer.encode(self.allocator);
            defer self.allocator.free(answerR);

            try respond.appendSlice(self.allocator, headerR);
            try respond.appendSlice(self.allocator, questionR);
            try respond.appendSlice(self.allocator, answerR);

            try self.socket.send(
                self.io,
                &packet.from,
                respond.items,
            );
        }
    }
};

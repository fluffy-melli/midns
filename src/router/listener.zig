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

    pub fn serve(self: *Listener, core: usize) !void {
        var spawn: usize = core;

        if (spawn == 0) {
            spawn = try std.Thread.getCpuCount();
        }

        const threads = try self.allocator.alloc(std.Thread, spawn);
        defer self.allocator.free(threads);

        for (threads, 0..) |*thread, i| {
            std.debug.print("worker spawn: {d}\n", .{i + 1});
            thread.* = try std.Thread.spawn(.{}, Listener.worker, .{self});
        }

        for (threads) |thread| {
            thread.join();
        }
    }

    fn worker(self: *Listener) void {
        var buffer: [512]u8 = undefined;
        while (true) {
            const packet = self.socket.receive(self.io, &buffer) catch |err| {
                std.debug.panic("worker failed: {}", .{err});
            };

            self.handler(packet) catch |err| {
                std.debug.panic("worker failed: {}", .{err});
            };
        }
    }

    fn handler(self: *Listener, packet: std.Io.net.IncomingMessage) !void {
        var header = protocol.Header.decode(packet.data[0..12]);
        const question = protocol.Question.decode(packet.data[12..]);

        header.flags.ra = .RecursionNotAvailable;
        header.flags.aa = .Authoritative;
        header.flags.tc = .NotTruncated;
        header.flags.qr = .Response;

        header.qd = 1;
        header.ns = 0;
        header.ar = 0;

        var data: std.ArrayList(u8) = .empty;
        defer data.deinit(self.allocator);

        switch (question.type) {
            .A => {
                header.an = 1;
                header.flags.rcode = .NOERROR;
                try data.appendSlice(self.allocator, &[_]u8{ 127, 0, 0, 1 });
            },
            .AAAA => {
                header.an = 1;
                header.flags.rcode = .NOERROR;
                try data.appendSlice(self.allocator, &[_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 });
            },
            else => {
                header.an = 0;
                header.flags.rcode = .NOTIMP;
            },
        }

        const answer = protocol.Answer{
            .name = &[_]u8{ 0xc0, 0x0c },
            .type = question.type,
            .class = question.class,
            .ttl = 300,
            .data = data.items,
        };

        var respond: std.ArrayList(u8) = .empty;
        defer respond.deinit(self.allocator);

        const headerR = try header.encode(self.allocator);
        defer self.allocator.free(headerR);

        const questionR = try question.encode(self.allocator);
        defer self.allocator.free(questionR);

        try respond.appendSlice(self.allocator, headerR);
        try respond.appendSlice(self.allocator, questionR);

        if (header.an > 0) {
            const answerR = try answer.encode(self.allocator);
            defer self.allocator.free(answerR);

            try respond.appendSlice(self.allocator, answerR);
        }

        try self.socket.send(
            self.io,
            &packet.from,
            respond.items,
        );
    }
};

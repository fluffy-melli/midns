const std = @import("std");
const protocol = @import("protocol");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    const addr = try std.Io.net.IpAddress.parse(
        "0.0.0.0",
        1153,
    );

    const socket = try std.Io.net.IpAddress.bind(&addr, io, .{
        .mode = .dgram,
        .protocol = .udp,
    });

    defer socket.close(io);

    var buffer: [512]u8 = undefined;
    while (true) {
        const packet = try socket.receive(io, &buffer);

        var header = protocol.Header.decode(packet.data[0..12]);
        const question = protocol.Question.decode(packet.data[12..]);

        const answer = protocol.Answer{
            .name = &[_]u8{ 0xc0, 0x0c },
            .type = 1,
            .class = 1,
            .ttl = 300,
            .rdata = &[_]u8{ 127, 0, 0, 1 },
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
        defer respond.deinit(allocator);

        const headerR = try header.encode(allocator);
        defer allocator.free(headerR);

        const questionR = try question.encode(allocator);
        defer allocator.free(questionR);

        const answerR = try answer.encode(allocator);
        defer allocator.free(answerR);

        try respond.appendSlice(allocator, headerR);
        try respond.appendSlice(allocator, questionR);
        try respond.appendSlice(allocator, answerR);

        try socket.send(
            io,
            &packet.from,
            respond.items,
        );
    }
}

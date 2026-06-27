const constant = @import("constant.zig");

pub const QR = constant.QR;
pub const OPCODE = constant.OPCODE;
pub const AA = constant.AA;
pub const TC = constant.TC;
pub const RD = constant.RD;
pub const RA = constant.RA;
pub const RCODE = constant.RCODE;

const parser = @import("parser.zig");

pub const Flags = parser.Flags;
pub const Header = parser.Header;
pub const Question = parser.Question;
pub const Answer = parser.Answer;

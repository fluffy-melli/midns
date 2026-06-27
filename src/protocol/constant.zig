pub const QR = enum(u1) {
    Query = 0,
    Response = 1,
};

pub const OPCODE = enum(u4) {
    QUERY = 0,
    IQUERY = 1,
    STATUS = 2,
    NOTIFY = 4,
    UPDATE = 5,
};

pub const AA = enum(u1) {
    NonAuthoritative = 0,
    Authoritative = 1,
};

pub const TC = enum(u1) {
    NotTruncated = 0,
    Truncated = 1,
};

pub const RD = enum(u1) {
    RecursionNotDesired = 0,
    RecursionDesired = 1,
};

pub const RA = enum(u1) {
    RecursionNotAvailable = 0,
    RecursionAvailable = 1,
};

pub const RCODE = enum(u4) {
    NOERROR = 0,
    FORMERR = 1,
    SERVFAIL = 2,
    NXDOMAIN = 3,
    NOTIMP = 4,
    REFUSED = 5,
    YXDOMAIN = 6,
    YXRRSET = 7,
    NOTAUTH = 8,
    NOTZONE = 9,
};

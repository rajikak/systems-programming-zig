// string ops
const std = @import("std");

pub fn main() !void {
    //try testJoin2();
    //try random();
    //const val = try concat();
    //const val2 = try concat2();
    //std.debug.print("concat: {s}:{s}\n", .{ val, val2 });
    //try mount();
    errHandling();
}

fn  errHandling() void {
    const upper = 9;
    const rand = std.crypto.random;
    const index = rand.intRangeAtMost(u8, 1, upper);

    var buffer: [20]u8 = undefined;
    const res = std.fmt.bufPrintZ(&buffer, "/tmp/anvilci.{d}", .{index}) catch |err| {
        std.debug.print("error: {}\n", .{err});
        return;
    };

    std.debug.print("stat: {s}, {d}\n", .{ res, res.len });
}


// https://lwn.net/Articles/689856/
fn mount() !void {
    const upper = 9;
    const rand = std.crypto.random;
    const index = rand.intRangeAtMost(u8, 1, upper);

    var buffer: [20]u8 = undefined;
    //const res = try std.fmt.bufPrint(&buffer, "/tmp/anvilci.{d}", .{index});
    //const res: [:0]u8 = try std.fmt.bufPrintZ(&buffer, "/tmp/anvilci.{d}", .{index});
    const res = try std.fmt.bufPrintZ(&buffer, "/tmp/anvilci.{d}", .{index});

    std.debug.print("stat: {s}, {d}\n", .{ res, res.len });

    for (res) |ch| {
        std.debug.print("{c} ", .{ch});
    }
    std.debug.print("\n", .{});

    const fs = "proc";
    const source = "proc";
    const mres = std.os.linux.syscall5(.mount, @intFromPtr(source.ptr), @intFromPtr(res.ptr), @intFromPtr(fs.ptr), 0, 0);
    const e = std.os.linux.E.init(mres);
    if (e != .SUCCESS) {
        std.debug.print("mount error: {}\n", .{e});
    }
}

fn concat2() ![]u8 {
    const hosts = [_][]const u8{ "cat", "world", "coffee", "girl", "man", "book" };
    const adjectives = [_][]const u8{ "blue", "red", "green", "yellow", "big", "small" };

    const rand = std.crypto.random;
    const index1 = rand.intRangeAtMost(u8, 1, hosts.len - 1);
    const index2 = rand.intRangeAtMost(u8, 1, adjectives.len - 1);

    // var buffer: [1000]u8 = undefined; // stack allocated buffer will not work
    const allocator = std.heap.page_allocator;
    const buf = try allocator.alloc(u8, 100);
    //defer allocator.free(buf);
    const a = try std.fmt.bufPrint(buf, "{s}-{s}", .{ hosts[index1], adjectives[index2] });

    var buf2: [100]u8 = undefined;
    const b = try std.fmt.bufPrint(&buf2, "{s}-{s}", .{ hosts[index1], adjectives[index2] });
    std.debug.print("len(a): {d}, typeOf(a): {any}, len(buf): {d}, typeOf(buf): {any}, len(b): {d}, typeOf(b):{any}\n", .{ a.len, @TypeOf(a), buf.len, @TypeOf(buf), b.len, @TypeOf(b) });

    return a;
}

fn concat() ![]u8 {
    var buffer: [1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    defer fba.reset();
    const allocator = fba.allocator();

    var list: std.ArrayList([]const u8) = .empty;
    const inputs = [_][]const u8{ "hello", "world!", "welcome to", "zig programming!" };
    for (inputs) |input| {
        try list.append(allocator, input);
    }

    const allocator2 = std.heap.page_allocator;
    const joined: []u8 = try std.mem.join(allocator2, ",", list.items);

    return joined;
}

fn testJoin2() !void {
    const arg = try join2();
    arg.print();
}

fn random() !void {
    const hosts = [_][]const u8{ "cat", "world", "coffee", "girl", "man", "book" };
    const adjectives = [_][]const u8{ "blue", "red", "green", "yellow", "big", "small" };

    const rand = std.crypto.random;
    const index1 = rand.intRangeAtMost(u8, 1, hosts.len - 1);
    const index2 = rand.intRangeAtMost(u8, 1, adjectives.len - 1);
    std.debug.print("host: {s}-{s}\n", .{ hosts[index1], adjectives[index2] });
}

const Arg = struct {
    n: u8,
    joined: *const []u8,
    list: std.ArrayList([]const u8),

    fn new(n: u8, joined: *const []u8, list: std.ArrayList([]const u8)) Arg {
        return Arg{
            .n = n,
            .joined = joined,
            .list = list,
        };
    }

    fn print(self: Arg) void {
        std.debug.print("Arg {{ n = {d}, joined = {s}, size(list) = {d}}}\n", .{ self.n, self.joined.*, self.list.items.len });
    }
};

fn join2() !Arg {
    var buffer: [1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    defer fba.reset();

    const allocator = fba.allocator();

    var list: std.ArrayList([]const u8) = .empty;
    try list.append(allocator, "go");
    try list.append(allocator, "build");
    try list.append(allocator, "-tags");
    try list.append(allocator, "lambda.norpc");
    try list.append(allocator, "-o");
    try list.append(allocator, "bootstrap");
    try list.append(allocator, ".");

    const allocator2 = std.heap.page_allocator;
    const joined: []u8 = try std.mem.join(allocator2, ",", list.items);
    std.debug.print("joined: {}, {s}\n", .{ @TypeOf(joined), joined });
    return Arg.new(10, &joined, list);
}

fn join1() !void {
    var buffer: [1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    defer fba.reset();

    const allocator = fba.allocator();

    var list: std.ArrayList([]const u8) = .empty;
    try list.append(allocator, "go");
    try list.append(allocator, "build");
    try list.append(allocator, "-tags");
    try list.append(allocator, "lambda.norpc");
    try list.append(allocator, "-o");
    try list.append(allocator, "bootstrap");
    try list.append(allocator, ".");

    const joined = try std.mem.join(allocator, ",", list.items);
    std.debug.print("joined: {s}\n", .{joined});
}

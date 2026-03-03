const std = @import("std");
const log = std.log;
const posix = std.posix;

const log_level: std.log.Level = .debug;
const minimu_kernel_version: f32 = 4.8;

const Syscalls = struct {
    pub fn getpid() i32 {
        return std.os.linux.getpid();
    }

    pub fn getpid2() usize {
        return std.os.linux.syscall0(.getpid);
    }

    pub fn pipe() [2]i32 {
        return std.os.linux.syscall0(.pipe);
    }
};

pub fn main() !void {
    const args = try parseArgs();
    log.info(" Args {{ debug: {}, command: {s}, uid: {d}, mount_dir: {s} }}", .{ args.debug, args.command, args.uid, args.mount_dir });

    try start(args);
    try exitWithRetCode(null);
}

fn start(args: Args) !void {
    try kernelVersion();

    const container = try Container.new(args);
    container.create() catch |err| {
        log.err("Error while creating the container: {any}", .{err});
        return error.ContainerCreationError;
    };
    log.debug("Finished, cleaning & exit", .{});
    try container.cleanExit();
}

const ChildArg = struct {
    n:u8,
    buf: []const u8,
    config: ContainerOpts,

    fn new(n:u8, buf: []const u8, config:ContainerOpts) ChildArg {
        return ChildArg {.n = n, .buf = buf, .config = config};
    }
};

fn generateHostName() ![]u8 {
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
    return a;
}

fn child(arg: usize) callconv(.c) u8  {
    const config: *ContainerOpts = @ptrFromInt(arg);
    const cmd = config.args();
    log.info(" Starting container with path: `{s}`, command: `{s}, host name: `{s}`", .{config.path, cmd, config.host_name});
    return 0;
}

fn generateChildProcess(config: ContainerOpts) !void {

    const stack_size:usize = 8 * 1024;
    const stack_memory = try std.heap.page_allocator.alloc(u8, stack_size);
    defer std.heap.page_allocator.free(stack_memory);

    const stack_ptr = @intFromPtr(stack_memory.ptr + stack_size);
    const clone_flags = std.os.linux.CLONE.VM | std.os.linux.SIG.CHLD | std.os.linux.CLONE.NEWUTS;

    const pid = std.os.linux.clone(child, stack_ptr, clone_flags, @intFromPtr(&config), null, 0, null);
    const e = std.os.linux.E.init(pid);
    if (e != .SUCCESS) {
       log.err("Clone failed: {}", .{e});
       return error.SyscallError;
    }
    const wait_flags = 0;
    var status: u32 = undefined;
    const trunc:u32 = @truncate(pid);
    _ = std.os.linux.waitpid(@intCast(trunc), &status, wait_flags);
    log.info(" Parent: child_pid: {}, pid: {}, ppid: {}", .{pid, std.os.linux.getpid(), std.os.linux.getppid()});
}

fn sendFlag(fd: i32, val: bool) !void {
    var buf: [1]u8 = undefined;
    const send = try std.fmt.bufPrint(&buf, "{b}", .{val});

    const res = std.posix.write(fd, send) catch |err| {
        log.err("Cannot send boolean through socket: {}", .{err});
        return error.SyscallError;
    };
    log.info("Send flag sent, {}, value: {}", .{ res, val });
}

fn receiveFlag(fd: i32) !bool {
    const buf: [1]u8 = undefined;
    const res = std.posix.read(fd, buf) catch |err| {
        log.err("Cannot receive boilean from socket: {}", err);
        return error.SyscallError;
    };
    log.info("Received flag, {}, {}", .{ res, buf });
}

fn generateSocketPair(fd: *[2]i32) !void {
    // https://man7.org/linux/man-pages/man2/socket.2.html
    // https://man7.org/linux/man-pages/man2/socketpair.2.html

    const domain: i32 = std.os.linux.AF.UNIX;
    const typ: i32 = std.os.linux.SOCK.STREAM; //posix.SOCK.STREAM;
    const protocol = 0; // see man page for socket(2)

    const res = std.os.linux.socketpair(domain, typ, protocol, fd);
    const err = std.os.linux.E.init(res);

    if (err != .SUCCESS) {
        log.err("There was an error when using std.os.linux.socketpair: {any}", .{err});
        return error.SyscallError;
    }
}

fn kernelVersion() !void {
    const host = std.posix.uname();
    var splits = std.mem.splitSequence(u8, &host.release, "-");
    const version = splits.first();
    splits = std.mem.splitSequence(u8, version, ".");

    const buf_size = 10;
    var buf: [buf_size]u8 = undefined;
    const major = try std.fmt.bufPrint(&buf, "{s}.{s}", .{ splits.first(), splits.next().? });
    const vf = try std.fmt.parseFloat(f64, major);

    log.debug("Linux release: {s}, {s}, {d}", .{ host.release, major, vf });

    if (vf < minimu_kernel_version) {
        return error.KernelVersionNotSupported;
    }
}

const Container = struct {
    fd: [2]i32,
    config: ContainerOpts,

    fn new(args: Args) !Container {
        const config = try ContainerOpts.new(args.command, args.uid, args.mount_dir);
        return Container{
            .config = config,
            .fd = config.fd,
        };
    }

    pub fn create(self: Container) !void {
        try generateChildProcess(self.config);
        log.debug("Creation finsihed", .{});
    }

    pub fn cleanExit(self: Container) !void {
        const write_fd = self.fd[0];
        //std.posix.fsync(@intCast(write_fd)) catch |err| {
        //    log.err("Unable to fsync any writes before closing the socket, {}", .{err});
        //    return error.SyscallError;
        //};
        std.posix.close(write_fd);

        const read_fd = self.fd[1];
        std.posix.close(read_fd);

        log.debug("Cleaning container", .{});
    }
};

const ContainerOpts = struct {
    path: []const u8,
    argv: std.ArrayList([]const u8),
    uid: u32,
    mount_dir: []const u8,
    fd: [2]i32,
    host_name:[]const u8,

    fn new(command: []const u8, uid: u32, mount_dir: []const u8) !ContainerOpts {
        var fd: [2]i32 = undefined;
        try generateSocketPair(&fd);
        const buf_size = 1000;
        var buffer: [buf_size]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        defer fba.reset();
        const allocator = fba.allocator();

        var list: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitSequence(u8, command, " ");
        while (it.next()) |v| {
            try list.append(allocator, v);
        }
        const host_name = try generateHostName();
        return ContainerOpts{
            .path = list.items[0],
            .argv = list,
            .uid = uid,
            .mount_dir = mount_dir,
            .fd = fd,
            .host_name = host_name,
        };
    }

    fn args(self:ContainerOpts) *const [42:0]u8 {
        _ = self;
         //var gpa = std.heap.DebugAllocator(.{}){};
         //defer _ = gpa.deinit();
         //const allocator = gpa.allocator();
         //const joined: []u8 = try std.mem.join(allocator, ",", self.argv.items);
         return "go build -tags lambda.norpc -o bootstrap .";
    }

    fn print(self: ContainerOpts) void {
        log.info("ContainerOpts {{ path: {s}, uid: {d}, mount_dir: {s} }}\n", .{ self.path, self.uid, self.mount_dir });
    }
};

// https://www.chromium.org/chromium-os/developer-library/reference/linux-constants/errnos/
const ErrCode = union(enum) {
    // https://ziglang.org/documentation/0.15.2/std/#std.os.linux.E
    OsError: std.os.linux.E,
    ArgumentInvalid,
    SocketError,

    fn errCode(val: ErrCode) u8 {
        switch (val) {
            .ArgumentInvalid => return 1,
            .SocketError => return @intFromEnum(val),
            .OsError => return @intFromEnum(val),
        }
    }
};
const Args = struct {
    debug: bool,
    command: []const u8,
    uid: u32,
    mount_dir: []const u8,
};

fn exitWithRetCode(errorCode: ?ErrCode) !void {
    if (errorCode) |err| {
        const code = ErrCode.errCode(err);
        log.debug("Error on exit: {}, code: {}", .{ err, code });
        std.posix.exit(code);
    } else {
        log.debug("Exit without any error, returning 0", .{});
        std.posix.exit(0);
    }
}

fn parseArgs() !Args {
    var args = std.process.args();
    _ = args.skip(); // skip the program name

    var arg: Args = undefined;
    arg.debug = false;

    while (args.next()) |v| {
        var splits = std.mem.splitSequence(u8, v, "=");
        const key = splits.first();
        const val = splits.next().?;
        if (std.mem.eql(u8, key, "mount")) {
            arg.mount_dir = val;
        } else if (std.mem.eql(u8, key, "uid")) {
            const uid = try std.fmt.parseInt(u32, val, 10);
            arg.uid = uid;
        } else if (std.mem.eql(u8, key, "debug") and std.mem.eql(u8, val, "true")) {
            arg.debug = true;
        } else if (std.mem.eql(u8, key, "command")) {
            arg.command = val;
        } else {
            log.err("{s}: {s}\n", .{ key, val });
            return error.UnknownArgument;
        }
    }

    return arg;
}

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
    const uts: posix.utsname = posix.uname();
    log.info(" [hostname: {s}] Args {{ debug: {}, command: {s}, uid: {d}, mount_dir: {s} }}", .{ uts.nodename, args.debug, args.command, args.uid, args.mount_dir });

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
    const uts: posix.utsname = posix.uname();
    log.info(" [hostname: {s}] Finished execution, cleaning & exit", .{uts.nodename});
    try container.cleanExit();
}

const ChildArg = struct {
    n: u8,
    buf: []const u8,
    config: ContainerOpts,

    fn new(n: u8, buf: []const u8, config: ContainerOpts) ChildArg {
        return ChildArg{ .n = n, .buf = buf, .config = config };
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

fn setUpContainerConfiguration(config: *ContainerOpts) void {
    // set hostname
    const res = std.os.linux.syscall2(.sethostname, @intFromPtr(config.host_name.ptr), config.host_name.len);
    const e = std.os.linux.E.init(res);
    if (e != .SUCCESS) {
        log.err("Error setting hostname: {}", .{e});
        return;
    }

    const cmd = config.args();
    const uts: posix.utsname = posix.uname();
    log.info(" [hostname: {s}] Starting container with path: `{s}`, command: `{s}, host_name: `{s}`", .{ uts.nodename, config.path, cmd, config.host_name });
}

fn setUpContainerMountPoints(config: *ContainerOpts) void {

    var buffer:[1000]u8 = undefined;
    var w = std.fs.File.stdout().writer(&buffer);
    const stdout = &w.interface;

    const uts: posix.utsname = posix.uname();
    stdout.print("info:  [hostname: {s}] Setting mount point: {s}, new_root: {s}\n", .{uts.nodename, config.mount_dir, config.new_root}) catch {};
    stdout.flush() catch {};

    buffer = undefined;
    stdout.print("info:  [hostname: {s}] Ensure new_root and parent don't share propgation\n", .{uts.nodename}) catch {};
    stdout.flush() catch {};
    // https://man7.org/linux/man-pages/man2/pivot_root.2.html
    // ensure the `new_root` and its parent mount don't have shared propagation(which will
    // cause pivot_root to return an error) and prevent from propation of mount envents to
    // the initial mount namespace

    //const mount_flags = std.os.linux.MS.REC | std.os.linux.MS.PRIVATE;
    const root = "/";
    //const res = std.os.linux.syscall5(.mount, 0, @intFromPtr(root.ptr), 0, mount_flags, 0);
    //const e = std.os.linux.E.init(res);
    //if (e != .SUCCESS) {
    //    log.err("Error using mount: {}", .{e});
    //    return;
    //}

    // ensure `new_root` is a mount point
    //buffer = undefined;
    //stdout.print("info:  [hostname: {s}] Creating new_root: {s}\n", .{uts.nodename, config.new_root}) catch {};
    //stdout.flush() catch {};
    log.info("**********came here ", .{});

    //const mode = 0o777;
    //const res1 = std.os.linux.syscall2(.mkdir, @intFromPtr(config.new_root.ptr), mode);
    //const e1 = std.os.linux.E.init(res1);
    //if (e1 != .SUCCESS) {
    //    log.err("Error creating the new_root: {s}, error: {}", .{config.new_root, e1});
    //    return;
    //}

    stdout.print("info:  [hostname: {s}] Mounting tmp directory: {s}\n", .{ uts.nodename, config.new_root }) catch {};
    stdout.flush() catch {};

    //const mount_flags2 = std.os.linux.MS.BIND|std.os.linux.MS.PRIVATE;
    //const mount_flags2 = std.os.linux.MS.BIND;
    //const res2 = std.os.linux.syscall5(.mount, @intFromPtr(config.new_root.ptr), @intFromPtr(config.new_root.ptr), 0, mount_flags2, 0);
    //const e2 = std.os.linux.E.init(res2);
    //if (e2 != .SUCCESS) {
    //    log.err("Error using mount: {}", .{e2});
    //    return;
    //}

    // create directory to which old root will be pivoted
    stdout.print("info:  [hostname: {s}] creating put old: {s}\n", .{ uts.nodename, config.put_old }) catch {};
    stdout.flush() catch {};

    //const res3 = std.os.linux.syscall2(.mkdir, @intFromPtr(config.put_old.ptr), mode);
    //const e3 = std.os.linux.E.init(res3);
    //if (e3 != .SUCCESS) {
    //    log.err("Error creating the pivot_root path: {s}, error: {}", .{config.put_old, e3});
    //    return;
    //}

    stdout.print("info:  [hostname: {s}] Pivoting root from: {s}, to: {s}\n", .{ uts.nodename, config.new_root, config.put_old }) catch {};
    stdout.flush() catch {};

    //const res4 = std.os.linux.syscall2(.pivot_root, @intFromPtr(config.new_root.ptr), @intFromPtr(config.put_old.ptr));
    //const e4 = std.os.linux.E.init(res4);
    //if (e4 != .SUCCESS) {
    //    log.err("Error pivoting_root: {}", .{e4});
    //    return;
    //}

    stdout.print("info:  [hostname: {s}] chdir root: {s}\n", .{ uts.nodename, root }) catch {};
    stdout.flush() catch {};

    // switch the current working directory to /
    //const res5 = std.os.linux.syscall1(.chdir, @intFromPtr(root.ptr));
    //const e5 = std.os.linux.E.init(res5);
    //if (e5 != .SUCCESS) {
    //    log.err("Error during chdir: {}", .{e5});
    //    return;
    //}

    stdout.print("info:  [hostname: {s}] Unmounting to oldroot: {s}\n", .{ uts.nodename, config.put_old }) catch {};
    stdout.flush() catch {};

    // unmout old root and remove the mount point
    //const umoun_flags = std.os.linux.MNT.DETACH;
    //const res6 = std.os.linux.syscall2(.umount2, @intFromPtr(config.put_old.ptr), umoun_flags);
    //const e6 = std.os.linux.E.init(res6);
    //if (e6 != .SUCCESS) {
    //    log.err("Error during umount2: {}", .{e6});
    //    return;
    //}

    stdout.print("info:  [hostname: {s}] Unmounted oldroot: {s} and removed mount point\n", .{ uts.nodename, config.put_old }) catch {};
    stdout.flush() catch {};
    //const res7 = std.os.linux.syscall1(.rmdir, @intFromPtr(config.put_old.ptr));
    //const e7 = std.os.linux.E.init(res7);
    //if (e7 != .SUCCESS) {
    //    log.err("Error during rmdir: {}", .{e7});
    //    return;
    //}

    stdout.print("info:  [hostname: {s}] Unmounted oldroot: {s} and removed mount point\n", .{ uts.nodename, config.put_old }) catch {};
    stdout.flush() catch {};
}

fn child(arg: usize) callconv(.c) u8 {
    const config: *ContainerOpts = @ptrFromInt(arg);

    setUpContainerConfiguration(config);
    setUpContainerMountPoints(config);

    return 0;
}

fn generateChildProcess(config: ContainerOpts) !void {
    const stack_size: usize = 8 * 1024;
    const stack_memory = try std.heap.page_allocator.alloc(u8, stack_size);
    defer std.heap.page_allocator.free(stack_memory);

    const stack_ptr = @intFromPtr(stack_memory.ptr + stack_size);
    //const clone_flags = std.os.linux.CLONE.VM | std.os.linux.SIG.CHLD | std.os.linux.CLONE.NEWUTS;
    const clone_flags =  std.os.linux.SIG.CHLD | std.os.linux.CLONE.NEWNS | std.os.linux.CLONE.VM | std.os.linux.CLONE.NEWUTS;

    const pid = std.os.linux.clone(child, stack_ptr, clone_flags, @intFromPtr(&config), null, 0, null);
    const e = std.os.linux.E.init(pid);
    if (e != .SUCCESS) {
        log.err("Clone failed: {}", .{e});
        return error.SyscallError;
    }
    const wait_flags = 0;
    var status: u32 = undefined;
    const trunc: u32 = @truncate(pid);
    const res  = std.os.linux.waitpid(@intCast(trunc), &status, wait_flags);
    const e2 = std.os.linux.E.init(res); 
    if (e2 != .SUCCESS) {
        log.err("Error in waitpid: {}", .{e2});
        return;
    }

    const uts: posix.utsname = posix.uname();
    log.info(" [hostname: {s}] Parent: child_pid: {}, pid: {}, ppid: {}", .{ uts.nodename, pid, std.os.linux.getpid(), std.os.linux.getppid() });
}

fn sendFlag(fd: i32, val: bool) !void {
    var buf: [1]u8 = undefined;
    const send = try std.fmt.bufPrint(&buf, "{b}", .{val});

    const res = std.posix.write(fd, send) catch |err| {
        log.err("Cannot send boolean through socket: {}", .{err});
        return error.SyscallError;
    };
    const uts: posix.utsname = posix.uname();
    log.info(" [hostname: {s}] Send flag sent, {}, value: {}", .{ uts.nodename, res, val });
}

fn receiveFlag(fd: i32) !bool {
    const buf: [1]u8 = undefined;
    const res = std.posix.read(fd, buf) catch |err| {
        log.err("Cannot receive boilean from socket: {}", err);
        return error.SyscallError;
    };
    const uts: posix.utsname = posix.uname();
    log.info(" [hostname: {s}] Received flag, {}, {}", .{ uts.nodename, res, buf });
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

    const uts: posix.utsname = posix.uname();
    log.debug("[hostname: {s}] Linux release: {s}, {s}, {d}", .{ uts.nodename, host.release, major, vf });

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
        const uts: posix.utsname = posix.uname();
        log.debug("[nodename: {s}] Container creation finsihed", .{uts.nodename});
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

        const uts: posix.utsname = posix.uname();
        log.debug("[hostname: {s}] Cleaning container", .{uts.nodename});
    }
};

const ContainerOpts = struct {
    path: []const u8,
    argv: std.ArrayList([]const u8),
    uid: u32,
    mount_dir: []const u8,
    fd: [2]i32,
    host_name: []const u8,
    new_root: []const u8,
    put_old:[]const u8,

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

        const index = std.crypto.random.intRangeAtMost(u32, 1, 1000);
        var buffer2:[buf_size]u8 = undefined;
        const new_root = try std.fmt.bufPrintZ(&buffer2, "{s}{d}", .{mount_dir, index});

        var buffer3:[buf_size]u8 = undefined;
        const put_old = try std.fmt.bufPrintZ(&buffer3, "{s}/oldrootfs", .{new_root});

        const host_name = try generateHostName();
        return ContainerOpts{
            .path = list.items[0],
            .argv = list,
            .uid = uid,
            .mount_dir = mount_dir,
            .fd = fd,
            .host_name = host_name,
            .new_root = new_root, 
            .put_old = put_old, 
        };
    }

    fn args(self: ContainerOpts) *const [42:0]u8 {
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
    const uts: posix.utsname = posix.uname();
    if (errorCode) |err| {
        const code = ErrCode.errCode(err);
        log.debug("[hostname: {s}] Error on exit: {}, code: {}", .{ uts.nodename, err, code });
        std.posix.exit(code);
    } else {
        log.debug("[hostname: {s}] Exit without any error, returning 0", .{uts.nodename});
        std.posix.exit(0);
    }
}

fn parseArgs() !Args {
    var args = std.process.args();
    _ = args.skip(); // skip the program name

    var arg: Args = undefined;
    arg.debug = false;
    var count:usize = 0;

    while (args.next()) |v| {
        count += 1;
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

    if (count == 0) {
        return error.MissingArgumentError;
    }

    return arg;
}

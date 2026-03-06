const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;

const Arg = struct {
    n: u32,
    buf: []const u8,
    host_name: []const u8,
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

fn child(arg: usize) callconv(.c) u8 {
    const input: *Arg = @ptrFromInt(arg);

    const uts: posix.utsname = posix.uname();
    std.debug.print("child[{s}]: starting child: args from parent: {s}\n", .{uts.nodename, input.buf});
    input.buf = "arguments received sucessfully"; // can send to parent with linux.CLONE.VM

    std.debug.print("child[{s}]: setting new host_name to: {s}\n", .{uts.nodename, input.host_name});
    const res = linux.syscall2(.sethostname, @intFromPtr(input.host_name.ptr), input.host_name.len);
    const e = linux.E.init(res);
    if (e != .SUCCESS) {
        std.debug.print("child: error setting hostname: {}\n", .{e});
        return 0;
    }
    const uts2: posix.utsname = posix.uname();

    const mount_flags = linux.MS.REC | linux.MS.PRIVATE;
    const root = "/";
    const res1 = linux.syscall5(.mount, 0, @intFromPtr(root.ptr), 0, mount_flags, 0);
    const e1 = linux.E.init(res1);
    if (e1 != .SUCCESS) {
        std.debug.print("child: error in mount: {}\n", .{e1});
        return 0;
    }

    const new_root = "/tmp/clone";
    const mount_flags2 = linux.MS.BIND;
    const res2 = linux.syscall5(.mount, @intFromPtr(new_root.ptr), @intFromPtr(new_root.ptr), 0, mount_flags2, 0);
    const e2 = linux.E.init(res2);
    if (e2 != .SUCCESS) {
        std.debug.print("child: error in mount2: {}\n", .{e2});
        return 0;
    }

    const put_old = "/tmp/clone/oldrootfs";
    const mode = 0o777; // make it writerable 
    const res3 = linux.syscall2(.mkdir, @intFromPtr(put_old.ptr), mode);
    const e3 = linux.E.init(res3);
    if (e3 != .SUCCESS) {
        std.debug.print("child: error in mkdir: {}\n", .{e3});
    }

    std.debug.print("child[{s}] pivoting_root to: {s}, put_old: {s} \n", .{uts2.nodename, new_root, put_old});
    const res4 = linux.syscall2(.pivot_root, @intFromPtr(new_root.ptr), @intFromPtr(put_old.ptr));
    const e4 = linux.E.init(res4);
    if (e4 != .SUCCESS) {
        std.debug.print("child: error in pivot_root: {}\n", .{e4});
        return 0;
    }
    
    const res5 = linux.syscall1(.chdir, @intFromPtr(root.ptr));
    const e5 = linux.E.init(res5);
    if (e5 != .SUCCESS) {
        std.debug.print("child: error in chdir: {}\n", .{e5});
        return 0;
    }

    const umount_flag = linux.MNT.DETACH;
    const res6 = linux.syscall2(.umount2, @intFromPtr(put_old.ptr), umount_flag);
    const e6 = linux.E.init(res6);
    if (e6 != .SUCCESS) {
        std.debug.print("child: error in umount2: {}\n", .{e6});
        return 0;
    }

    std.debug.print("child[{s}]: finished sucessfully, sending to parent: {s}\n", .{ uts2.nodename, input.buf });
    return 0;
}

pub fn main() !void {
    const stack_size: usize = 1024 * 1024;
    const stack_memory = try std.heap.page_allocator.alloc(u8, stack_size);
    defer std.heap.page_allocator.free(stack_memory);
    const stack_ptr = @intFromPtr(stack_memory.ptr + stack_size);

    // linux.SIG.CHLD is required for waitpid
    // linux.CLONE.VM will make child to share parent process memory - hostname change will apply into parent as well
    const clone_flags = linux.SIG.CHLD | linux.CLONE.NEWUTS;

    const uts: posix.utsname = posix.uname();
    std.debug.print("parent[{s}]: parent process starting clone...\n", .{uts.nodename});

    const host_name = try generateHostName();
    const arg = Arg{ 
        .n = 5, 
        .buf = "gcc -Wall -ansi -Werror -pedantic",
        .host_name = host_name,
    };
    const pid = linux.clone(
        child,
        stack_ptr,
        clone_flags,
        @intFromPtr(&arg),
        null,
        0,
        null,
    );

    var status: u32 = undefined;
    const wpid: linux.pid_t = @intCast(pid);
    // const wflags = std.c.W.UNTRACED | std.c.W.CONTINUED;
    const wflags = 0;

    // https://man7.org/linux/man-pages/man2/wait.2.html
    const res = linux.waitpid(wpid, &status, wflags);

    std.debug.print("parent[{s}]: child exited result(clone): {d}, status: {d}, result(waitpid): {}, received from child: {s}\n", .{ uts.nodename, wpid, status, res, arg.buf });
}

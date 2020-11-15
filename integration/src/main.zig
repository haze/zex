const std = @import("std");
const curl = @import("zex");

pub fn main() anyerror!void {
    var html = try curl.post(.{ .url = "http://httpbin.org/post", .body = .{ .bytes = "test" }, .verbose = true });
    defer html.free();
    std.debug.print("{}\n", .{html.data});
}

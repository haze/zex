const std = @import("std");
const mem = std.mem;
const util = @import("util.zig");
const wrapper = @import("wrapper.zig");

const cURL = @cImport({
    @cInclude("curl/curl.h");
});

pub const UnmanagedStringMap = std.array_hash_map.StringArrayHashMapUnmanaged([]const u8);
pub const StringMap = std.array_hash_map.StringArrayHashMap([]const u8);

/// Lower level cURL client that takes an allocator with every function
pub const UnmanagedClient = struct {
    handle: wrapper.EasyHandle,

    pub fn init() wrapper.EasyHandle.InitError!UnmanagedClient {
        return UnmanagedClient{
            .handle = try wrapper.EasyHandle.init(),
        };
    }

    pub const PerformError = mem.Allocator.Error || util.CURLError;

    pub fn perform(self: UnmanagedClient, allocator: *mem.Allocator, request: HTTPRequest) PerformError![]const u8 {
        var sys_headers = StringMap.init(allocator);
        var buffer = std.ArrayList(u8).init(allocator);

        // set url
        try self.handle.setURL(request.url);

        // set follow redirects
        // if (request.follow_redirects)
        //     try util.convertCurlError(cURL.curl_easy_setopt(self.handle, .CURLOPT_FOLLOWLOCATION, @as(c_int, 1)));
        try self.handle.setFollowLocation(request.follow_redirects);

        // if (request.verbose)
        //     try util.convertCurlError(cURL.curl_easy_setopt(self.handle, .CURLOPT_VERBOSE, @as(c_long, 1)));
        try self.handle.setVerbose(request.verbose);

        // set request specific things
        switch (request.method) {
            .GET => {
                try self.handle.setHTTPGet(true);
                // try util.convertCurlError(cURL.curl_easy_setopt(self.handle, .CURLOPT_HTTPGET, @as(c_long, 1)));
            },
            .HEAD => {
                try self.handle.setNoBody(true);
                // try util.convertCurlError(cURL.curl_easy_setopt(self.handle, .CURLOPT_NOBODY, @as(c_long, 1)));
            },
            .POST => {
                try self.handle.setPost(true);
                // try util.convertCurlError(cURL.curl_easy_setopt(self.handle, .CURLOPT_POST, @as(c_long, 1)));
            },
            .PUT => {
                try self.handle.setUpload(true);
                // try util.convertCurlError(cURL.curl_easy_setopt(self.handle, .CURLOPT_UPLOAD, @as(c_long, 1)));
            },
            // otherwise, treat as GET or PUT
            else => {
                if (request.body != null)
                    try self.handle.setUpload(true);
                // if (request.body != null)
                //     try util.convertCurlError(cURL.curl_easy_setopt(self.handle, .CURLOPT_UPLOAD, @as(c_long, 1)));
            },
        }

        // // set write function
        // // TODO(haze): see if this is correct (ignore body only on HEAD)
        // if (request.method != .HEAD) {
        //     // try self.handle.setWriteCallback(curlWriteToU8ArrayList);
        //     // try self.handle.setWriteData(&buffer);
        //     // try util.convertCurlError(cURL.curl_easy_setopt(self.handle, .CURLOPT_WRITEFUNCTION, curlWriteToU8ArrayList));
        //     // try util.convertCurlError(cURL.curl_easy_setopt(self.handle, .CURLOPT_WRITEDATA, @as(*c_void, &buffer)));
        // }

        // if we have a body, we have to tell curl how big it is, or use chunked encoding
        if (request.body) |body| {
            // get from header, or calculate
            const body_length: ?usize = blk: {
                if (request.headers.get("Content-Length")) |value| {
                    break :blk std.fmt.parseUnsigned(usize, value, 10) catch null;
                } else switch (body) {
                    .json, .bytes => |buf| break :blk buf.len,
                    else => {},
                }
                break :blk null;
            };

            if (body_length) |length| {
                if (request.method == .POST) {
                    // try self.handle.setPostFieldSize(@intCast(i32, length));
                    try self.handle.setPostFieldSizeLarge(@intCast(i32, length));
                    switch (body) {
                        .json, .bytes => |buf| try self.handle.setPostFields(buf),
                        else => {},
                    }
                } else {
                    try self.handle.setInFileSizeLarge(@intCast(i32, length));
                    // try util.convertCurlError(cURL.curl_easy_setopt(self.handle, .CURLOPT_INFILESIZE_LARGE, @intCast(c_long, length)));
                }
            } else {
                try sys_headers.put("Transfer-Encoding", "chunked");
            }

            try body.setHeader(&sys_headers);
        }

        std.log.debug("custom header map has {} entires", .{request.headers.count()});
        for (request.headers.items()) |entry| {
            std.log.debug("{}", .{entry});
            try sys_headers.put(entry.key, entry.value);
        }

        // TODO(haze): perfect header ordering thing
        // collect into arraylist
        var header_string_list = std.ArrayList([]const u8).init(allocator);
        defer header_string_list.deinit();

        var sys_header_iter = sys_headers.iterator();
        while (sys_header_iter.next()) |entry|
            try header_string_list.append(try std.fmt.allocPrint(allocator, "{}: {}", .{ entry.key, entry.value }));

        // set headers
        const curl_string_list = try self.handle.setHTTPHeaders(header_string_list);
        defer curl_string_list.deinit();

        // set headers
        // var list = std.ArrayList([]const u8).init(allocator);
        // var iter = sys_headers.iterator();
        // while (iter.next()) |item| {
        //     try list.append(try std.fmt.allocPrint(allocator, "{}, {}", .{ item.key, item.value }));
        // }
        // try self.handle.setHTTPHeaders(list);
        // if (maybe_headers) |headers|
        //     try util.convertCurlError(cURL.curl_easy_setopt(self.handle, .CURLOPT_HTTPHEADER, headers));

        // set request method
        try self.handle.setCustomRequest(request.method.string());
        // try util.convertCurlError(cURL.curl_easy_setopt(self.handle, .CURLOPT_CUSTOMREQUEST, request.method.string().ptr));

        // perform
        try util.convertCurlError(cURL.curl_easy_perform(self.handle.handle));

        return buffer.toOwnedSlice();
    }

    pub fn deinit(self: UnmanagedClient) void {
        cURL.curl_easy_cleanup(self.handle);
    }
};

fn curlWriteToU8ArrayList(data: *c_void, size: c_uint, nmemb: c_uint, user_data: *c_void) callconv(.C) usize {
    var buffer = @intToPtr(*std.ArrayList(u8), @ptrToInt(user_data));
    var typed_data = @intToPtr([*]u8, @ptrToInt(data));
    buffer.appendSlice(typed_data[0 .. nmemb * size]) catch return 0;
    return nmemb * size;
}

/// Lower level cURL client
pub const Client = struct {
    allocator: *mem.Allocator,
    unmanaged: UnmanagedClient,

    pub fn init(allocator: *mem.Allocator) !Client {
        return Client{
            .allocator = allocator,
            .unmanaged = try UnmanagedClient.init(),
        };
    }
};

pub const Method = union(enum) {
    GET: void,
    POST: void,
    PUT: void,
    DELETE: void,
    HEAD: void,
    OPTIONS: void,
    TRACE: void,
    CONNECT: void,
    PATCH: void,
    Custom: []const u8,

    fn string(method: Method) []const u8 {
        return switch (method) {
            .GET => "GET",
            .HEAD => "HEAD",
            .POST => "POST",
            .PUT => "PUT",
            .DELETE => "DELETE",
            .CONNECT => "CONNECT",
            .TRACE => "TRACE",
            .OPTIONS => "OPTIONS",
            .PATCH => "PATCH",
            .Custom => |request| request,
        };
    }
};

pub const Body = union(enum) {
    /// use this to set the content type to text/plain
    bytes: []const u8,

    /// use this to set the content type to application/json
    json: []const u8,

    /// use this to set the cocntent type to application/octet-stream with chunked transfers
    file: std.fs.File.Reader,

    /// use this to set the content type to application/x-www-form-urlencoded
    /// values and keys will be urlencoded
    form: StringMap,

    /// TODO(haze); multipart,
    multipart: void,

    fn setHeader(self: Body, header_map: *StringMap) !void {
        switch (self) {
            .json => try header_map.put("Content-Type", "application/json; charset=UTF-8"),
            .bytes => try header_map.put("Content-Type", "text/plain; charset=UTF-8"),
            else => {},
        }
    }
};

pub const HTTPRequest = struct {
    // optional
    follow_redirects: bool = true,
    body: ?Body = null,
    headers: UnmanagedStringMap = .{},
    verbose: bool = false,

    // required
    method: Method,
    url: []const u8,

    fn setHeader(self: *HTTPRequest, allocator: *mem.Allocator, key: []const u8, value: []const u8) !void {
        try self.headers.put(allocator, key, value);
    }

    fn removeHeader(self: *HTTPRequest, key: []const u8) ?StringMap.Entry {
        return self.headers.remove(key);
    }
};

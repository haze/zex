const std = @import("std");
const mem = std.mem;
const client = @import("client.zig");
const util = @import("util.zig");
const wrapper = @import("wrapper.zig");

const cURL = @cImport({
    @cInclude("curl/curl.h");
});

/// public top level functions MUST call `global_init.call()`
var global_client: ?client.UnmanagedClient = null;
var global_init = std.once(initializeGlobalClient);

/// allocator used for responses
var global_allocator = if (std.builtin.link_libc) std.heap.c_allocator else std.heap.page_allocator;

var curl_global_init = std.once(initializeGlobalCURL);

fn initializeGlobalCURL() void {
    util.convertCurlError(cURL.curl_global_init(cURL.CURL_GLOBAL_ALL)) catch @panic("Failed to initialize global cURL client");
}

fn initializeGlobalClient() void {
    curl_global_init.call();
    global_client = client.UnmanagedClient.init() catch @panic("Failed to initialize global cURL client");
}

const GlobalResponse = struct {
    data: []const u8,

    pub fn free(self: *GlobalResponse) void {
        global_allocator.free(self.data);
        self.* = undefined;
    }
};

// top level ease of use methods
fn SpecializedFnParam(method: client.Method) type {
    return struct {
        // optional
        follow_redirects: bool = true,
        body: ?client.Body = null,
        headers: client.UnmanagedStringMap = .{},
        verbose: bool = false,

        // required
        url: []const u8,

        fn into_request(self: ParamsForMethod(method)) client.HTTPRequest {
            return client.HTTPRequest{
                .method = method,
                .url = self.url,
                .follow_redirects = self.follow_redirects,
                .body = self.body,
                .headers = self.headers,
                .verbose = self.verbose,
            };
        }
    };
}

const HTTPGetParams = SpecializedFnParam(.GET);
const HTTPPostParams = SpecializedFnParam(.POST);
const HTTPPutParams = SpecializedFnParam(.PUT);
const HTTPDeleteParams = SpecializedFnParam(.DELETE);
const HTTPOptionsParams = SpecializedFnParam(.OPTIONS);
const HTTPTraceParams = SpecializedFnParam(.TRACE);
const HTTPConnectParams = SpecializedFnParam(.CONNECT);
const HTTPHeadParams = SpecializedFnParam(.HEAD);
const HTTPPatchParams = SpecializedFnParam(.PATCH);

fn ParamsForMethod(method: ?client.Method) type {
    if (method == null) {
        return client.HTTPRequest;
    }
    return switch (method.?) {
        .GET => HTTPGetParams,
        .POST => HTTPPostParams,
        .PATCH => HTTPPatchParams,
        .PUT => HTTPPutParams,
        .DELETE => HTTPDeleteParams,
        .OPTIONS => HTTPOptionsParams,
        .TRACE => HTTPTraceParams,
        .CONNECT => HTTPConnectParams,
        .HEAD => HTTPHeadParams,
        .Custom => client.HTTPRequest,
    };
}

fn generateTopLevelFunction(comptime maybe_method: ?client.Method) fn (ParamsForMethod(maybe_method)) client.UnmanagedClient.PerformError!GlobalResponse {
    return struct {
        fn func(request: ParamsForMethod(maybe_method)) client.UnmanagedClient.PerformError!GlobalResponse {
            global_init.call();
            var handle = global_client.?;
            return GlobalResponse{
                .data = try handle.perform(global_allocator, request.into_request()),
            };
        }
    }.func;
}

pub const get = generateTopLevelFunction(.GET);
pub const post = generateTopLevelFunction(.POST);
pub const put = generateTopLevelFunction(.PUT);
pub const options = generateTopLevelFunction(.OPTIONS);
pub const head = generateTopLevelFunction(.HEAD);
pub const delete = generateTopLevelFunction(.DELETE);
pub const trace = generateTopLevelFunction(.TRACE);
pub const connect = generateTopLevelFunction(.CONNECt);
pub const custom = generateTopLevelFunction(null);

// TODO(haze): utility funcs

pub fn download() void {}
pub fn upload() void {}
pub fn byLine() void {}

test "wrapper" {
    var easy_handle = try wrapper.EasyHandle.init();
    try easy_handle.setVerbose(true);
    var blob_data = [_]u8{ 't', 'e', 's', 't' };
    try easy_handle.setSSLCertBlob(&blob_data, true);
}

test "simple get" {
    std.debug.print("\n", .{});
    var html = try post(.{ .url = "http://httpbin.org/post", .body = .{ .bytes = "test" }, .verbose = true });
    defer html.free();
    std.debug.print("\n{}\n", .{html.data});
}

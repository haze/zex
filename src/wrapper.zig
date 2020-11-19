const cURL = @cImport({
    @cInclude("curl/curl.h");
});
const std = @import("std");
const util = @import("util.zig");

pub const StringList = std.ArrayList([]const u8);

// TODO(haze): Add curl_opt_t (i64 on 64bit systems, 32 on 32bit systems)
pub const EasyHandle = struct {
    handle: *cURL.CURL,

    const InitError = error{EasyInitFailed};
    pub fn init() InitError!EasyHandle {
        return EasyHandle{
            .handle = cURL.curl_easy_init() orelse return error.EasyInitFailed,
        };
    }

    fn Switch(comptime option: cURL.CURLoption) fn (EasyHandle, bool) util.CURLError!void {
        return struct {
            fn func(self: EasyHandle, should: bool) util.CURLError!void {
                return util.convertCurlError(cURL.curl_easy_setopt(self.handle, option, @as(c_long, if (should) 1 else 0)));
            }
        }.func;
    }

    fn Long(comptime option: cURL.CURLoption) fn (EasyHandle, bool) util.CURLError!void {
        return struct {
            fn func(self: EasyHandle, value: i32) util.CURLError!void {
                return util.convertCurlError(cURL.curl_easy_setopt(self.handle, option, @as(c_long, value)));
            }
        }.func;
    }

    fn UserData(comptime option: cURL.CURLoption) fn (EasyHandle, anytype) util.CURLError!void {
        return struct {
            fn func(self: EasyHandle, value: anytype) util.CURLError!void {
                const ti = @typeInfo(@TypeOf(value));
                if (ti != .Pointer) @compileError("Non pointer passed to userData");
                return util.convertCurlError(cURL.curl_easy_setopt(self.handle, option, @as(*c_void, value)));
            }
        }.func;
    }

    fn Blob(comptime option: cURL.CURLoption) fn (EasyHandle, []u8, bool) util.CURLError!void {
        return struct {
            fn func(self: EasyHandle, value: []u8, copy: bool) util.CURLError!void {
                var blob: cURL.curl_blob = undefined;
                blob.data = value.ptr;
                blob.len = value.len;
                // I didn't want to have to hardcode the values, but I can't figure out how to transform the enum(?) values
                // https://github.com/curl/curl/blob/master/include/curl/easy.h#L29
                blob.flags = @as(c_uint, if (copy) 1 else 0);
                return util.convertCurlError(cURL.curl_easy_setopt(self.handle, option, blob));
            }
        }.func;
    }

    fn FileHandle(comptime option: cURL.CURLoption) fn (EasyHandle, []u8) util.CURLError!void {
        return struct {
            fn func(self: EasyHandle, value: std.fs.File) util.CURLError!void {
                return util.convertCurlError(cURL.curl_easy_setopt(self.handle, option, value.handle));
            }
        }.func;
    }

    fn ProvidedBuffer(comptime option: cURL.CURLoption) fn (EasyHandle, []u8) util.CURLError!void {
        return struct {
            fn func(self: EasyHandle, value: []u8) util.CURLError!void {
                return util.convertCurlError(cURL.curl_easy_setopt(self.handle, option, value));
            }
        }.func;
    }

    fn String(comptime option: cURL.CURLoption) fn (EasyHandle, bool) util.CURLError!void {
        return struct {
            fn func(self: EasyHandle, value: []const u8) util.CURLError!void {
                return util.convertCurlError(cURL.curl_easy_setopt(self.handle, option, value.ptr));
            }
        }.func;
    }

    fn CurlStringList(comptime option: cURL.CURLoption) fn (EasyHandle, bool) util.CURLError!void {
        return struct {
            fn func(self: EasyHandle, list: StringList) util.CURLError!void {
                var maybe_list: ?cURL.curl_slist = null;
                var iter = list.iterator();
                if (maybe_list) |list| {
                    while (iter.next()) |entry| {
                        list = cURL.curl_slist_append(list, entry.ptr);
                    }
                }
                return util.convertCurlError(cURL.curl_easy_setopt(
                    self.handle,
                    option,
                    maybe_list,
                ));
            }
        }.func;
    }

    // Behavior functions
    pub const setVerbose = Switch(.CURLOPT_VERBOSE);
    pub const setHeader = Switch(.CURLOPT_HEADER);
    pub const setNoProgress = Switch(.CURLOPT_NOPROGRESS);
    pub const setNoSignal = Switch(.CURLOPT_NOSIGNAL);
    pub const setWildcardMatch = Switch(.CURLOPT_WILDCARDMATCH);

    // Callback Options
    // Error Options
    /// Error message buffer. See [CURLOPT_ERRORBUFFER](https://curl.se/libcurl/c/CURLOPT_ERRORBUFFER.html)
    pub const setErrorBuffer = ProvidedBuffer(.CURLOPT_ERRORBUFFER);
    /// stderr replacement stream. See [CURLOPT_STDERR](https://curl.se/libcurl/c/CURLOPT_STDERR.html)
    pub const setStderr = FileHandle(.CURLOPT_STDERR);
    /// Fail on HTTP 4xx errors. [CURLOPT_FAILONERROR](https://curl.se/libcurl/c/CURLOPT_FAILONERROR.html)
    pub const setFailOnError = Switch(.CURLOPT_FAILONERROR);
    /// Keep sending on HTTP >= 300 errors. [CURLOPT_KEEP_SENDING_ON_ERROR](https://curl.se/libcurl/c/CURLOPT_KEEP_SENDING_ON_ERROR.html)
    pub const setKeepSendingOnError = Switch(.CURLOPT_KEEP_SENDING_ON_ERROR);

    // Network Options
    /// URL to work on. See [CURLOPT_URL](https://curl.se/libcurl/c/CURLOPT_URL.html)
    pub const setURL = String(.CURLOPT_URL);
    /// Disable squashing /../ and /./ sequences in the path. See [CURLOPT_PATH_AS_IS](https://curl.se/libcurl/c/CURLOPT_PATH_AS_IS.html)
    pub const setPathAsIs = Switch(.CURLOPT_PATH_AS_IS);
    /// Set Allowed protocols. See [CURLOPT_PROTOCOLS](https://curl.se/libcurl/c/CURLOPT_PROTOCOLS.html)
    pub const setProtocols = Long(.CURLOPT_PROTOCOLS);
    /// Protocols to allow redirects to. See [CURLOPT_REDIR_PROTOCOLS](https://curl.se/libcurl/c/CURLOPT_REDIR_PROTOCOLS.html)
    pub const setRedirProtocols = LONG(.CURLOPT_REDIR_PROTOCOLS);
    /// Default protocol. See [CURLOPT_DEFAULT_PROTOCOL](https://curl.se/libcurl/c/CURLOPT_DEFAULT_PROTOCOL.html)
    pub const setDefaultProtocols = String(.CURLOPT_DEFAULT_PROTOCOL);
    /// Proxy to use. See [CURLOPT_PROXY](https://curl.se/libcurl/c/CURLOPT_PROXY.html)
    pub const setProxy = Switch(.CURLOPT_PROXY);
    /// Socks proxy to use. See [CURLOPT_PRE_PROXY](https://curl.se/libcurl/c/CURLOPT_PRE_PROXY.html)
    pub const setPreProxy = String(.CURLOPT_PRE_PROXY);
    /// Proxy port to use. See [CURLOPT_PROXYPORT](https://curl.se/libcurl/c/CURLOPT_PROXYPORT.html)
    pub const setProxyPort = Long(.CURLOPT_PROXYPORT);
    /// Proxy type. See [CURLOPT_PROXYTYPE](https://curl.se/libcurl/c/CURLOPT_PROXYTYPE.html)
    pub const setProxyType = Long(.CURLOPT_PROXYTYPE);
    /// Filter out hosts from proxy use. [CURLOPT_NOPROXY](https://curl.se/libcurl/c/CURLOPT_NOPROXY.html)
    pub const setNoProxy = String(.CURLOPT_NOPROXY);
    /// Tunnel through the HTTP proxy. [CURLOPT_HTTPPROXYTUNNEL](https://curl.se/libcurl/c/CURLOPT_HTTPPROXYTUNNEL.html)
    pub const setHTTPProxyTunnel = Switch(.CURLOPT_HTTPPROXYTUNNEL);
    /// Connect to a specific host and port. See [CURLOPT_CONNECT_TO](https://curl.se/libcurl/c/CURLOPT_CONNECT_TO.html)
    pub const setConnectTo = StringList(.CURLOPT_CONNECT_TO);
    /// Socks5 authentication methods. See [CURLOPT_SOCKS5_AUTH](https://curl.se/libcurl/c/CURLOPT_SOCKS5_AUTH.html)
    pub const setSocks5Auth = Long(.CURLOPT_SOCKS5_AUTH);
    /// Socks5 GSSAPI service name. [CURLOPT_SOCKS5_GSSAPI_SERVICE](https://curl.se/libcurl/c/CURLOPT_SOCKS5_GSSAPI_SERVICE.html)
    pub const setGSAPIServiceName = String(.CURLOPT_SOCKS5_GSSAPI_SERVICE);
    /// Socks5 GSSAPI NEC mode. See [CURLOPT_SOCKS5_GSSAPI_NEC](https://curl.se/libcurl/c/CURLOPT_SOCKS5_GSSAPI_NEC.html)
    pub const setGSAPINec = Switch(.CURLOPT_SOCKS5_GSSAPI_NEC);
    /// Proxy authentication service name. [CURLOPT_PROXY_SERVICE_NAME](https://curl.se/libcurl/c/CURLOPT_PROXY_SERVICE_NAME.html)
    pub const setProxyAuthServiceName = String(.CURLOPT_PROXY_SERVICE_NAME);
    /// Send an HAProxy PROXY protocol v1 header. See [CURLOPT_HAPROXYPROTOCOL](https://curl.se/libcurl/c/CURLOPT_HAPROXYPROTOCOL.html)
    pub const setHAProxyProxyProtocol = Switch(.CURLOPT_HAPROXYPROTOCOL);
    /// Authentication service name. [CURLOPT_SERVICE_NAME](https://curl.se/libcurl/c/CURLOPT_SERVICE_NAME.html)
    pub const setServiceName = String(.CURLOPT_SERVICE_NAME);
    /// Bind connection locally to this. See [CURLOPT_INTERFACE](https://curl.se/libcurl/c/CURLOPT_INTERFACE.html)
    pub const setInterface = String(.CURLOPT_INTERFACE);
    /// Bind connection locally to this port. See [CURLOPT_LOCALPORT](https://curl.se/libcurl/c/CURLOPT_LOCALPORT.html)
    pub const setLocalPort = Long(.CURLOPT_LOCALPORT);
    /// Bind connection locally to port range. See [CURLOPT_LOCALPORTRANGE](https://curl.se/libcurl/c/CURLOPT_LOCALPORTRANGE.html)
    pub const setLocalPortRange = Long(.CURLOPT_LOCALPORTRANGE);
    /// Timeout for DNS cache. See [CURLOPT_DNS_CACHE_TIMEOUT](https://curl.se/libcurl/c/CURLOPT_DNS_CACHE_TIMEOUT.html)
    pub const setDNSCacheTimeout = Long(.CURLOPT_DNS_CACHE_TIMEOUT);
    /// Use this DOH server for name resolves. See [CURLOPT_DOH_URL](https://curl.se/libcurl/c/CURLOPT_DOH_URL.html)
    pub const setDOHServer = String(.CURLOPT_DOH_URL);
    /// Ask for alternate buffer size. See [CURLOPT_BUFFERSIZE](https://curl.se/libcurl/c/CURLOPT_BUFFERSIZE.html)
    pub const setBufferSize = Long(.CURLOPT_BUFFERSIZE);
    /// Port number to connect to. See [CURLOPT_PORT](https://curl.se/libcurl/c/CURLOPT_PORT.html)
    pub const setPort = Long(.CURLOPT_PORT);
    /// Enable TFO, TCP Fast Open. See [CURLOPT_TCP_FASTOPEN](https://curl.se/libcurl/c/CURLOPT_TCP_FASTOPEN.html)
    pub const setTFOTCPFastOpen = Switch(.CURLOPT_TCP_FASTOPEN);
    /// Disable the Nagle algorithm. See [CURLOPT_TCP_NODELAY](https://curl.se/libcurl/c/CURLOPT_TCP_NODELAY.html)
    pub const setTCPNoDelay = Switch(.CURLOPT_TCP_NODELAY);
    /// IPv6 scope for local addresses. See [CURLOPT_ADDRESS_SCOPE](https://curl.se/libcurl/c/CURLOPT_ADDRESS_SCOPE.html)
    pub const setAddressScope = Long(.CURLOPT_ADDRESS_SCOPE);
    /// Enable TCP keep-alive. See [CURLOPT_TCP_KEEPALIVE](https://curl.se/libcurl/c/CURLOPT_TCP_KEEPALIVE.html )
    pub const setTCPKeepAlive = Switch(.CURLOPT_TCP_KEEPALIVE);
    /// Idle time before sending keep-alive. See [CURLOPT_TCP_KEEPIDLE](https://curl.se/libcurl/c/CURLOPT_TCP_KEEPIDLE.html)
    pub const setTCPKeepIdleTime = Long(.CURLOPT_TCP_KEEPALIVE);
    /// Interval between keep-alive probes. See [CURLOPT_TCP_KEEPINTVL](https://curl.se/libcurl/c/CURLOPT_TCP_KEEPINTVL.html)
    pub const setTCPKeepAliveInterval = Long(.CURLOPT_TCP_KEEPINTVL);
    /// Path to a Unix domain socket. See [CURLOPT_UNIX_SOCKET_PATH](https://curl.se/libcurl/c/CURLOPT_UNIX_SOCKET_PATH.html)
    pub const setUnixDomainSocket = String(.CURLOPT_UNIX_SOCKET_PATH);
    /// Path to an abstract Unix domain socket. See [CURLOPT_ABSTRACT_UNIX_SOCKET](https://curl.se/libcurl/c/CURLOPT_ABSTRACT_UNIX_SOCKET.html)
    pub const setAbstractUnixSocket = String(.CURLOPT_ABSTRACT_UNIX_SOCKET);

    // Names and Password Options (Authentication)
    /// Enable .netrc parsing. See [CURLOPT_NETRC](https://curl.se/libcurl/c/CURLOPT_NETRC.html)
    pub const setNetrc = Long(.CURLOPT_NETRC);
    /// .netrc file name. See [CURLOPT_NETRC_FILE](https://curl.se/libcurl/c/CURLOPT_NETRC_FILE.html)
    pub const setNetrcFileName = String(.CURLOPT_NETRC_FILE);
    /// User name and password. See [CURLOPT_USERPWD](https://curl.se/libcurl/c/CURLOPT_USERPWD.html)
    pub const setUsernameAndPassword = String(.CURLOPT_USERPWD);
    /// Proxy user name and password. See [CURLOPT_PROXYUSERPWD](https://curl.se/libcurl/c/CURLOPT_PROXYUSERPWD.html)
    pub const setProxyUsernameAndPassword = Switch(.CURLOPT_PROXYUSERPWD);
    /// User name. See [CURLOPT_USERNAME](https://curl.se/libcurl/c/CURLOPT_USERNAME.html)
    pub const setUsername = String(.CURLOPT_USERNAME);
    /// Password. See [CURLOPT_PASSWORD](https://curl.se/libcurl/c/CURLOPT_PASSWORD.html)
    pub const setPassword = String(.CURLOPT_PASSWORD);
    /// Login options. See [CURLOPT_LOGIN_OPTIONS](https://curl.se/libcurl/c/CURLOPT_LOGIN_OPTIONS.html)
    pub const setLoginOptions = String(.CURLOPT_LOGIN_OPTIONS);
    /// Proxy user name. See [CURLOPT_PROXYUSERNAME](https://curl.se/libcurl/c/CURLOPT_PROXYUSERNAME.html)
    pub const setProxyUsername = String(.CURLOPT_PROXYUSERNAME);
    /// Proxy password. See [CURLOPT_PROXYPASSWORD](https://curl.se/libcurl/c/CURLOPT_PROXYPASSWORD.html)
    pub const setProxyPassword = String(.CURLOPT_PROXYPASSWORD);
    /// HTTP server authentication methods. See [CURLOPT_HTTPAUTH](https://curl.se/libcurl/c/CURLOPT_HTTPAUTH.html)
    pub const setHTTPAuth = Long(.CURLOPT_HTTPAUTH);
    /// TLS authentication user name. See [CURLOPT_TLSAUTH_USERNAME](https://curl.se/libcurl/c/CURLOPT_TLSAUTH_USERNAME.html)
    pub const setTLSUsername = String(.CURLOPT_TLSAUTH_USERNAME);
    /// Proxy TLS authentication user name. See [CURLOPT_PROXY_TLSAUTH_USERNAME](https://curl.se/libcurl/c/CURLOPT_PROXY_TLSAUTH_USERNAME.html)
    pub const setProxyTLSUsername = String(.CURLOPT_PROXY_TLSAUTH_USERNAME);
    /// Proxy TLS authentication password. See [CURLOPT_PROXY_TLSAUTH_PASSWORD](https://curl.se/libcurl/c/CURLOPT_TLSAUTH_PASSWORD.html)
    pub const setProxyTLSPassword = String(.CURLOPT_PROXY_TLSAUTH_PASSWORD);
    /// TLS authentication password. See [CURLOPT_TLSAUTH_PASSWORD](https://curl.se/libcurl/c/CURLOPT_TLSAUTH_PASSWORD.html)
    pub const setTLSPassword = String(.CURLOPT_TLSAUTH_PASSWORD);
    /// TLS authentication methods. See [CURLOPT_TLSAUTH_TYPE](https://curl.se/libcurl/c/CURLOPT_TLSAUTH_TYPE.html)
    pub const setTLSAuthType = String(.CURLOPT_TLSAUTH_TYPE);
    /// Proxy TLS authentication methods. See [CURLOPT_PROXY_TLSAUTH_TYPE](https://curl.se/libcurl/c/CURLOPT_PROXY_TLSAUTH_TYPE.html)
    pub const setProxyTLSAuthType = String(.CURLOPT_PROXY_TLSAUTH_TYPE);
    /// HTTP proxy authentication methods. See [CURLOPT_PROXYAUTH](https://curl.se/libcurl/c/CURLOPT_PROXYAUTH.html)
    pub const setHTTPProxuAuthMethods = Long(.CURLOPT_PROXYAUTH);
    /// SASL authorisation identity (identity to act as). See [CURLOPT_SASL_AUTHZID](https://curl.se/libcurl/c/CURLOPT_SASL_AUTHZID.html)
    pub const setSASLAuthIdentity = String(.CURLOPT_SASL_AUTHZID);
    /// Enable SASL initial response. See [CURLOPT_SASL_IR](https://curl.se/libcurl/c/CURLOPT_SASL_IR.html)
    pub const setSASLInitialResponse = Switch(.CURLOPT_SASL_IR);
    /// OAuth2 bearer token. See [CURLOPT_XOAUTH2_BEARER](https://curl.se/libcurl/c/CURLOPT_XOAUTH2_BEARER.html)
    pub const setOauth2BearerToken = Switch(.CURLOPT_XOAUTH2_BEARER);
    /// Don't allow username in URL. [See CURLOPT_DISALLOW_USERNAME_IN_URL](https://curl.se/libcurl/c/CURLOPT_DISALLOW_USERNAME_IN_URL.html)
    pub const setDisallowUsernamesInURL = Switch(.CURLOPT_DISALLOW_USERNAME_IN_URL);

    // HTTP Options
    /// Automatically set Referer: header. See [CURLOPT_AUTOREFERER](https://curl.se/libcurl/c/CURLOPT_AUTOREFERER.html)
    pub const setAutoReferer = Switch(.CURLOPT_AUTOREFERER);
    /// Accept-Encoding and automatic decompressing data. See [CURLOPT_ACCEPT_ENCODING](https://curl.se/libcurl/c/CURLOPT_ACCEPT_ENCODING.html)
    pub const setAcceptEncoding = String(.CURLOPT_ACCEPT_ENCODING);
    /// Request Transfer-Encoding. See [CURLOPT_TRANSFER_ENCODING](https://curl.se/libcurl/c/CURLOPT_TRANSFER_ENCODING.html)
    pub const setTransferEncoding = Switch(.CURLOPT_TRANSFER_ENCODING);
    /// Follow HTTP redirects. See [CURLOPT_FOLLOWLOCATION](https://curl.se/libcurl/c/CURLOPT_FOLLOWLOCATION.html)
    pub const setFollowLocation = Switch(.CURLOPT_FOLLOWLOCATION);
    /// Do not restrict authentication to original host. [CURLOPT_UNRESTRICTED_AUTH](https://curl.se/libcurl/c/CURLOPT_UNRESTRICTED_AUTH.html)
    pub const setUnrestrictedAuth = Switch(.CURLOPT_UNRESTRICTED_AUTH);
    /// Maximum number of redirects to follow. See [CURLOPT_MAXREDIRS](https://curl.se/libcurl/c/CURLOPT_MAXREDIRS.html)
    pub const setMaxRedirects = Long(.CURLOPT_MAXREDIRS);
    /// How to act on redirects after POST. See [CURLOPT_POSTREDIR](https://curl.se/libcurl/c/CURLOPT_POSTREDIR.html)
    pub const setPostRedirect = Long(.CURLOPT_POSTREDIR);
    /// Issue an HTTP PUT request. See [CURLOPT_PUT](https://curl.se/libcurl/c/CURLOPT_PUT.html)
    pub const setPut = Switch(.CURLOPT_PUT);
    /// Issue an HTTP POST request. See [CURLOPT_POST](https://curl.se/libcurl/c/CURLOPT_POST.html)
    pub const setPost = Switch(.CURLOPT_POST);
    /// Send a POST with this data. See [CURLOPT_POSTFIELDS](https://curl.se/libcurl/c/CURLOPT_POSTFIELDS.html)
    pub const setPostFields = String(.CURLOPT_POSTFIELDS);
    /// The POST data is this big. See [CURLOPT_POSTFIELDSIZE](https://curl.se/libcurl/c/CURLOPT_POSTFIELDSIZE.html)
    pub const setPostFieldSize = Long(.CURLOPT_POSTFIELDSIZE);
    // TODO(haze): curl_off_t
    /// The POST data is this big. See [CURLOPT_POSTFIELDSIZE_LARGE](https://curl.se/libcurl/c/CURLOPT_POSTFIELDSIZE_LARGE.html)
    pub const setPostFieldSizeLarge = Long(.CURLOPT_MAIL_FROM);
    /// Send a POST with this data - and copy it. See [CURLOPT_COPYPOSTFIELDS](https://curl.se/libcurl/c/CURLOPT_COPYPOSTFIELDS.html)
    pub const setCopyPostFields = String(.CURLOPT_COPYPOSTFIELDS);
    /// Multipart formpost HTTP POST. See [CURLOPT_HTTPPOST](https://curl.se/libcurl/c/CURLOPT_HTTPPOST.html)
    // TODO(haze): curl_httppost
    pub const setHTTPPost = String(.CURLOPT_HTTPPOST);
    /// Referer: header. See [CURLOPT_REFERER](https://curl.se/libcurl/c/CURLOPT_REFERER.html)
    pub const setReferer = String(.CURLOPT_REFERER);
    /// User-Agent: header. See [CURLOPT_USERAGENT](https://curl.se/libcurl/c/CURLOPT_USERAGENT.html)
    pub const setUserAgent = String(.CURLOPT_USERAGENT);
    /// Custom HTTP headers. See [CURLOPT_HTTPHEADER](https://curl.se/libcurl/c/CURLOPT_HTTPHEADER.html)
    pub const setHTTPHeaders = StringList(.CURLOPT_HTTPHEADER);
    /// Control custom headers. See [CURLOPT_HEADEROPT](https://curl.se/libcurl/c/CURLOPT_HEADEROPT.html)
    pub const setHeaderOptions = Long(.CURLOPT_HEADEROPT);
    /// Custom HTTP headers sent to proxy. See [CURLOPT_PROXYHEADER](https://curl.se/libcurl/c/CURLOPT_PROXYHEADER.html)
    pub const setHTTPProxyHeaders = StringList(.CURLOPT_PROXYHEADER);
    /// Alternative versions of 200 OK. See [CURLOPT_HTTP200ALIASES](https://curl.se/libcurl/c/CURLOPT_HTTP200ALIASES.html)
    pub const setHTTP200Aliases = StringList(.CURLOPT_HTTP200ALIASES);
    /// Cookie(s) to send. See [CURLOPT_COOKIE](https://curl.se/libcurl/c/CURLOPT_COOKIE.html)
    pub const setCookies = String(.CURLOPT_COOKIE);
    /// File to read cookies from. See [CURLOPT_COOKIEFILE](https://curl.se/libcurl/c/CURLOPT_COOKIEFILE.html)
    pub const setReadCookieFile = String(.CURLOPT_COOKIEFILE);
    /// File to write cookies to. See [CURLOPT_COOKIEJAR](https://curl.se/libcurl/c/CURLOPT_COOKIEJAR.html)
    pub const setWriteCookieFile = String(.CURLOPT_COOKIEJAR);
    /// Start a new cookie session. See [CURLOPT_COOKIESESSION](https://curl.se/libcurl/c/CURLOPT_COOKIESESSION.html)
    pub const setCookieSession = Switch(.CURLOPT_COOKIESESSION);
    /// Add or control cookies. See [CURLOPT_COOKIELIST](https://curl.se/libcurl/c/CURLOPT_COOKIELIST.html)
    pub const setCookie = String(.CURLOPT_COOKIELIST);
    /// Specify the Alt-Svc: cache file name. See [CURLOPT_ALTSVC](https://curl.se/libcurl/c/CURLOPT_ALTSVC.html)
    pub const setAlcSvc = String(.CURLOPT_ALTSVC);
    /// Enable and configure Alt-Svc: treatment. See [CURLOPT_ALTSVC_CTRL](https://curl.se/libcurl/c/CURLOPT_ALTSVC_CTRL.html)
    pub const setAltSvcCtrl = Long(.CURLOPT_ALTSVC_CTRL);
    /// Set HSTS cache file. See [CURLOPT_HSTS](https://curl.se/libcurl/c/CURLOPT_HSTS.html)
    pub const setHSTS = String(.CURLOPT_HSTS);
    /// Enable HSTS. See [CURLOPT_HSTS_CTRL](https://curl.se/libcurl/c/CURLOPT_HSTS_CTRL.html)
    pub const setHSTSCtrl = Long(.CURLOPT_HSTS_CTRL);
    /// Set HSTS read callback. See [CURLOPT_HSTSREADFUNCTION](https://curl.se/libcurl/c/CURLOPT_HSTSREADFUNCTION.html)
    // TODO(haze): callback func
    pub const setHSTSReadCallback = Long(.CURLOPT_HSTSREADFUNCTION);
    /// Pass pointer to the HSTS read callback. See [CURLOPT_HSTSREADDATA](https://curl.se/libcurl/c/CURLOPT_HSTSREADDATA.html)
    pub const setHSTSReadData = UserData(.CURLOPT_HSTSREADDATA);
    /// Set HSTS write callback. See [CURLOPT_HSTSWRITEFUNCTION]()
    // TODO(haze): callback func
    pub const setHSTSWriteCallback = Long(.CURLOPT_HSTSWRITEFUNCTION);
    /// Pass pointer to the HSTS write callback. See [CURLOPT_HSTSWRITEDATA]()
    pub const setHSTSWriteData = UserData(.CURLOPT_HSTSWRITEDATA);
    /// Do an HTTP GET request. See [CURLOPT_HTTPGET](https://curl.se/libcurl/c/CURLOPT_HTTPGET.html)
    pub const setHTTPGet = Switch(.CURLOPT_HTTPGET);
    /// Set the request target. [CURLOPT_REQUEST_TARGET](https://curl.se/libcurl/c/CURLOPT_REQUEST_TARGET.html)
    pub const setRequestTarget = String(.CURLOPT_REQUEST_TARGET);
    /// HTTP version to use. [CURLOPT_HTTP_VERSION](https://curl.se/libcurl/c/CURLOPT_HTTP_VERSION.html)
    pub const setHTTPVersion = Long(.CURLOPT_HTTP_VERSION);
    /// Allow HTTP/0.9 responses. [CURLOPT_HTTP09_ALLOWED](https://curl.se/libcurl/c/CURLOPT_HTTP09_ALLOWED.html)
    pub const setAllowHTTP09 = Switch(.CURLOPT_HTTP09_ALLOWED);
    /// Ignore Content-Length. See [CURLOPT_IGNORE_CONTENT_LENGTH](https://curl.se/libcurl/c/CURLOPT_IGNORE_CONTENT_LENGTH.html)
    pub const setIgnoreContentLength = Switch(.CURLOPT_IGNORE_CONTENT_LENGTH);
    /// Disable Content decoding. See [CURLOPT_HTTP_CONTENT_DECODING](https://curl.se/libcurl/c/CURLOPT_HTTP_CONTENT_DECODING.html)
    pub const setDisableContentDecoding = Switch(.CURLOPT_HTTP_CONTENT_DECODING);
    /// Disable Transfer decoding. See [CURLOPT_HTTP_TRANSFER_DECODING](https://curl.se/libcurl/c/CURLOPT_HTTP_TRANSFER_DECODING.html)
    pub const setDisableTransferDecoding = Switch(.CURLOPT_HTTP_TRANSFER_DECODING);
    /// 100-continue timeout. See [CURLOPT_EXPECT_100_TIMEOUT_MS](https://curl.se/libcurl/c/CURLOPT_EXPECT_100_TIMEOUT_MS.html)
    pub const set100ContinueTimeoutMillis = Long(.CURLOPT_EXPECT_100_TIMEOUT_MS);
    /// Set callback for sending trailing headers. See [CURLOPT_TRAILERFUNCTION](https://curl.se/libcurl/c/CURLOPT_TRAILERFUNCTION.html)
    pub const setTrailingHeaderCallback = Long(.CURLOPT_TRAILERFUNCTION);
    /// Custom pointer passed to the trailing headers callback. See [CURLOPT_TRAILERDATA](https://curl.se/libcurl/c/CURLOPT_TRAILERDATA.html)
    pub const setTrailingHeaderData = UserData(.CURLOPT_TRAILERDATA);
    /// Wait on connection to pipeline on it. See [CURLOPT_PIPEWAIT](https://curl.se/libcurl/c/CURLOPT_PIPEWAIT.html)
    pub const setPipelineWait = Switch(.CURLOPT_PIPEWAIT);
    /// This HTTP/2 stream depends on another. See [CURLOPT_STREAM_DEPENDS](https://curl.se/libcurl/c/CURLOPT_STREAM_DEPENDS.html)
    pub const setHTTP2StreamDepends = CurlHandle(.CURLOPT_STREAM_DEPENDS_E);
    /// This HTTP/2 stream depends on another exclusively. See [CURLOPT_STREAM_DEPENDS_E](https://curl.se/libcurl/c/CURLOPT_STREAM_DEPENDS_E.html)
    pub const setHTTP2StreamDependsExclusively = CurlHandle(.CURLOPT_STREAM_DEPENDS_E);
    /// Set this HTTP/2 stream's weight. See [CURLOPT_STREAM_WEIGHT](https://curl.se/libcurl/c/CURLOPT_STREAM_WEIGHT.html)
    pub const setHTTP2StreamWeight = Long(.CURLOPT_STREAM_WEIGHT);

    // SMTP Options
    /// Address of the sender. See [CURLOPT_MAIL_FROM](https://curl.se/libcurl/c/CURLOPT_MAIL_FROM.html)
    pub const setMailFrom = String(.CURLOPT_MAIL_FROM);
    /// Address of the recipients. See [CURLOPT_MAIL_RCPT](https://curl.se/libcurl/c/CURLOPT_MAIL_RCPT.html)
    pub const setMailRecipient = StringList(.CURLOPT_MAIL_RCPT);
    /// Authentication address. See [CURLOPT_MAIL_AUTH](https://curl.se/libcurl/c/CURLOPT_MAIL_AUTH.html)
    pub const setMailAuth = String(.CURLOPT_MAIL_AUTH);
    /// Allow RCPT TO command to fail for some recipients. See [CURLOPT_MAIL_RCPT_ALLLOWFAILS](https://curl.se/libcurl/c/CURLOPT_MAIL_RCPT_ALLLOWFAILS.html)
    pub const setMailRCPTAllowFails = Switch(.CURLOPT_MAIL_RCPT_ALLLOWFAILS);

    // TFTP Options
    /// TFTP block size. See [CURLOPT_TFTP_BLKSIZE](https://curl.se/libcurl/c/CURLOPT_TFTP_BLKSIZE.html)
    pub const setTFTPBlockSize = Long(.CURLOPT_TFTP_BLKSIZE);
    /// Do not send TFTP options requests. See [CURLOPT_TFTP_NO_OPTIONS](https://curl.se/libcurl/c/CURLOPT_TFTP_NO_OPTIONS.html)
    pub const setTFTPNoOptions = Switch(.CURLOPT_TFTP_NO_OPTIONS);

    // FTP Options
    /// Use active FTP. See [CURLOPT_FTPPORT](https://curl.se/libcurl/c/CURLOPT_FTPPORT.html)
    pub const setFTPPort = String(.CURLOPT_FTPPORT);
    /// Commands to run before transfer. See [CURLOPT_QUOTE](https://curl.se/libcurl/c/CURLOPT_QUOTE.html)
    pub const setQuote = StringList(.CURLOPT_QUOTE);
    /// Commands to run after transfer. See [CURLOPT_POSTQUOTE](https://curl.se/libcurl/c/CURLOPT_POSTQUOTE.html)
    pub const setPostQuote = StringList(.CURLOPT_POSTQUOTE);
    /// Commands to run just before transfer. See [CURLOPT_PREQUOTE](https://curl.se/libcurl/c/CURLOPT_PREQUOTE.html)
    pub const setPreQuote = StringList(.CURLOPT_PREQUOTE);
    /// Append to remote file. See [CURLOPT_APPEND](https://curl.se/libcurl/c/CURLOPT_APPEND.html)
    pub const setAppend = Switch(.CURLOPT_APPEND);
    /// Use EPTR. See [CURLOPT_FTP_USE_EPRT](https://curl.se/libcurl/c/CURLOPT_FTP_USE_EPRT.html)
    pub const setFTPUseEPRT = Switch(.CURLOPT_FTP_USE_EPRT);
    /// Use EPSV. See [CURLOPT_FTP_USE_EPSV](https://curl.se/libcurl/c/CURLOPT_FTP_USE_EPSV.html)
    pub const setFTPUseEPSV = Switch(.CURLOPT_FTP_USE_EPSV);
    /// Use PRET. See [CURLOPT_FTP_USE_PRET](https://curl.se/libcurl/c/CURLOPT_FTP_USE_PRET.html)
    pub const setFTPUsePRET = Switch(.CURLOPT_FTP_USE_PRET);
    /// Create missing directories on the remote server. See [CURLOPT_FTP_CREATE_MISSING_DIRS](https://curl.se/libcurl/c/CURLOPT_FTP_CREATE_MISSING_DIRS.html)
    pub const setFTPCreateMissingDirs = Switch(.CURLOPT_FTP_CREATE_MISSING_DIRS);
    /// Timeout for FTP responses. See [CURLOPT_FTP_RESPONSE_TIMEOUT](https://curl.se/libcurl/c/CURLOPT_FTP_RESPONSE_TIMEOUT.html)
    pub const setFTPResponseTimeout = Long(.CURLOPT_FTP_RESPONSE_TIMEOUT);
    /// Alternative to USER. See [CURLOPT_FTP_ALTERNATIVE_TO_USER](https://curl.se/libcurl/c/CURLOPT_FTP_ALTERNATIVE_TO_USER.html)
    pub const setFTPAlternativeToUser = String(.CURLOPT_FTP_ALTERNATIVE_TO_USER);
    /// Ignore the IP address in the PASV response. See [CURLOPT_FTP_SKIP_PASV_IP](https://curl.se/libcurl/c/CURLOPT_FTP_SKIP_PASV_IP.html)
    pub const setFTPSkipPASVIP = Switch(.CURLOPT_FTP_SKIP_PASV_IP);
    /// Control how to do TLS. See [CURLOPT_FTPSSLAUTH](https://curl.se/libcurl/c/CURLOPT_FTPSSLAUTH.html)
    pub const setFTPSSLAuth = Long(.CURLOPT_RTSP_REQUEST);
    /// Back to non-TLS again after authentication. See [CURLOPT_FTP_SSL_CCC](https://curl.se/libcurl/c/CURLOPT_FTP_SSL_CCC.html)
    pub const setFTPSSLCCC = Long(.CURLOPT_FTP_SSL_CCC);
    /// Send ACCT command. See [CURLOPT_FTP_ACCOUNT](https://curl.se/libcurl/c/CURLOPT_FTP_ACCOUNT.html)
    pub const setFTPAccount = String(.CURLOPT_FTP_ACCOUNT);
    /// Specify how to reach files. See [CURLOPT_FTP_FILEMETHOD](https://curl.se/libcurl/c/CURLOPT_FTP_FILEMETHOD.html)
    pub const setFTPFileMethod = Long(.CURLOPT_FTP_FILEMETHOD);

    // RTSP Options
    /// RTSP request. See [CURLOPT_RTSP_REQUEST](https://curl.se/libcurl/c/CURLOPT_RTSP_REQUEST.html)
    pub const setRTSPRequest = Long(.CURLOPT_RTSP_REQUEST);
    /// RTSP session-id. See [CURLOPT_RTSP_SESSION_ID](https://curl.se/libcurl/c/CURLOPT_RTSP_SESSION_ID.html)
    pub const setRTSPSessionId = String(.CURLOPT_RTSP_SESSION_ID);
    /// RTSP stream URI. See [CURLOPT_RTSP_STREAM_URI](https://curl.se/libcurl/c/CURLOPT_RTSP_STREAM_URI.html)
    pub const setRTSPStreamURI = String(.CURLOPT_RTSP_STREAM_URI);
    /// RTSP Transport: header. See [CURLOPT_RTSP_TRANSPORT](https://curl.se/libcurl/c/CURLOPT_RTSP_TRANSPORT.html)
    pub const setRTSPTransport = String(.CURLOPT_RTSP_TRANSPORT);
    /// Client CSEQ number. See [CURLOPT_RTSP_CLIENT_CSEQ](https://curl.se/libcurl/c/CURLOPT_RTSP_CLIENT_CSEQ.html)
    pub const setRTSPClientCSEQ = Long(.CURLOPT_RTSP_CLIENT_CSEQ);
    /// CSEQ number for RTSP Server->Client request. See [CURLOPT_RTSP_SERVER_CSEQ](https://curl.se/libcurl/c/CURLOPT_RTSP_SERVER_CSEQ.html)
    pub const setRTSPServerCSEQ = Long(.CURLOPT_RTSP_SERVER_CSEQ);

    // Protocol Options
    /// Use text transfer. See [CURLOPT_TRANSFERTEXT](https://curl.se/libcurl/c/CURLOPT_TRANSFERTEXT.html)
    pub const setTextTransfer = Long(.CURLOPT_TRANSFERTEXT);
    /// Add transfer mode to URL over proxy. See [CURLOPT_PROXY_TRANSFER_MODE](https://curl.se/libcurl/c/CURLOPT_PROXY_TRANSFER_MODE.html)
    pub const setProxyTransferMode = Switch(.CURLOPT_PROXY_TRANSFER_MODE);
    /// Convert newlines. See [CURLOPT_CRLF](https://curl.se/libcurl/c/CURLOPT_CRLF.html)
    pub const setConvertNewlines = Switch(.CURLOPT_ABSTRACT_UNIX_SOCKET);
    /// Range requests. See [CURLOPT_RANGE](https://curl.se/libcurl/c/CURLOPT_RANGE.html)
    pub const setRange = String(.CURLOPT_RANGE);
    /// Resume a transfer. See [CURLOPT_RESUME_FROM](https://curl.se/libcurl/c/CURLOPT_RESUME_FROM.html)
    pub const setResumeFrom = Long(.CURLOPT_RESUME_FROM);
    /// Resume a transfer. See [CURLOPT_RESUME_FROM_LARGE](https://curl.se/libcurl/c/CURLOPT_RESUME_FROM_LARGE.html)
    pub const setResumeFromLarge = Long(.CURLOPT_RESUME_FROM_LARGE);
    /// Set URL to work on with CURLU *. See [CURLOPT_CURLU](https://curl.se/libcurl/c/CURLOPT_CURLU.html)
    pub const setCURLUUrl = UserData(.CURLOPT_CURLU);
    /// Custom request/method. See [CURLOPT_CUSTOMREQUEST](https://curl.se/libcurl/c/CURLOPT_CUSTOMREQUEST.html)
    pub const setCustomRequest = String(.CURLOPT_ABSTRACT_UNIX_SOCKET);
    /// Request file modification date and time. See [CURLOPT_FILETIME](https://curl.se/libcurl/c/CURLOPT_FILETIME.html)
    pub const setFileTime = Switch(.CURLOPT_FILETIME);
    /// List only. See [CURLOPT_DIRLISTONLY](https://curl.se/libcurl/c/CURLOPT_DIRLISTONLY.html)
    pub const setDirListOnly = Switch(.CURLOPT_DIRLISTONLY);
    /// Do not get the body contents. See [CURLOPT_NOBODY](https://curl.se/libcurl/c/CURLOPT_NOBODY.html)
    pub const setNoBody = Switch(.CURLOPT_NOBODY);
    /// Size of file to send. [CURLOPT_INFILESIZE](https://curl.se/libcurl/c/CURLOPT_INFILESIZE.html)
    pub const setInFileSize = Long(.CURLOPT_INFILESIZE);
    /// Size of file to send. [CURLOPT_INFILESIZE_LARGE](https://curl.se/libcurl/c/CURLOPT_INFILESIZE.html)
    pub const setInFileSizeLarge = Long(.CURLOPT_INFILESIZE_LARGE);
    /// Upload data. See [CURLOPT_UPLOAD](https://curl.se/libcurl/c/CURLOPT_UPLOAD.html)
    pub const setUpload = Switch(.CURLOPT_UPLOAD);
    /// Set upload buffer size. See [CURLOPT_UPLOAD_BUFFERSIZE](https://curl.se/libcurl/c/CURLOPT_UPLOAD_BUFFERSIZE.html)
    pub const setUploadBufferSize = Long(.CURLOPT_ABSTRACT_UNIX_SOCKET);
    /// Post/send MIME data. See [CURLOPT_MIMEPOST](https://curl.se/libcurl/c/CURLOPT_MIMEPOST.html)
    // TODO(haze): curl_mime
    pub const setMimePost = UserData(.CURLOPT_MIMEPOST);
    /// Maximum file size to get. See [CURLOPT_MAXFILESIZE](https://curl.se/libcurl/c/CURLOPT_MAXFILESIZE.html)
    pub const setMaxFileSize = Long(.CURLOPT_MAXFILESIZE);
    /// Maximum file size to get. See [CURLOPT_MAXFILESIZE_LARGE](https://curl.se/libcurl/c/CURLOPT_MAXFILESIZE_LARGE.html)
    pub const setMaxFileSizeLarge = Long(.CURLOPT_MAXFILESIZE_LARGE);
    /// Make a time conditional request. See [CURLOPT_TIMECONDITION](https://curl.se/libcurl/c/CURLOPT_TIMECONDITION.html)
    pub const setTimeCondition = Long(.CURLOPT_TIMECONDITION);
    /// Time value for the time conditional request. See [CURLOPT_TIMEVALUE](https://curl.se/libcurl/c/CURLOPT_TIMEVALUE.html)
    pub const setTimeValue = Long(.CURLOPT_TIMEVALUE);
    /// Time value for the time conditional request. See [CURLOPT_TIMEVALUE_LARGE](https://curl.se/libcurl/c/CURLOPT_TIMEVALUE_LARGE.html)
    pub const setTimeValueLarge = Long(.CURLOPT_TIMEVALUE_LARGE);

    // Connection Options
    /// Timeout for the entire request. See [CURLOPT_TIMEOUT](https://curl.se/libcurl/c/CURLOPT_TIMEOUT.html)
    pub const setTimeout = Long(.CURLOPT_TIMEOUT);
    /// Millisecond timeout for the entire request. See [CURLOPT_TIMEOUT_MS](https://curl.se/libcurl/c/CURLOPT_TIMEOUT_MS.html)
    pub const setTimeoutMillis = Long(.CURLOPT_TIMEOUT_MS);
    /// Low speed limit to abort transfer. See [CURLOPT_LOW_SPEED_LIMIT](https://curl.se/libcurl/c/CURLOPT_LOW_SPEED_LIMIT.html)
    pub const setLowSpeedLimit = Long(.CURLOPT_LOW_SPEED_LIMIT);
    /// Time to be below the speed to trigger low speed abort. See [CURLOPT_LOW_SPEED_TIME](https://curl.se/libcurl/c/CURLOPT_LOW_SPEED_TIME.html)
    pub const setLowSpeedTime = Long(.CURLOPT_LOW_SPEED_TIME);
    /// Cap the upload speed to this. See [CURLOPT_MAX_SEND_SPEED_LARGE](https://curl.se/libcurl/c/CURLOPT_MAX_SEND_SPEED_LARGE.html)
    pub const setMaxSendSpeedLarge = Long(.CURLOPT_MAX_SEND_SPEED_LARGE);
    /// Cap the download speed to this. See [CURLOPT_MAX_RECV_SPEED_LARGE](https://curl.se/libcurl/c/CURLOPT_MAX_RECV_SPEED_LARGE.html)
    pub const setMaxRecvSpeedLarge = Long(.CURLOPT_MAX_RECV_SPEED_LARGE);
    /// Maximum number of connections in the connection pool. See [CURLOPT_MAXCONNECTS](https://curl.se/libcurl/c/CURLOPT_MAXCONNECTS.html)
    pub const setMaxConnections = Long(.CURLOPT_MAXCONNECTS);
    /// Use a new connection. [CURLOPT_FRESH_CONNECT](https://curl.se/libcurl/c/CURLOPT_FRESH_CONNECT.html)
    pub const setFreshConnect = Switch(.CURLOPT_FRESH_CONNECT);
    /// Prevent subsequent connections from re-using this. See [CURLOPT_FORBID_REUSE](https://curl.se/libcurl/c/CURLOPT_FORBID_REUSE.html)
    pub const setForbidReuse = Switch(.CURLOPT_FORBID_REUSE);
    /// Limit the age of connections for reuse. See [CURLOPT_MAXAGE_CONN](https://curl.se/libcurl/c/CURLOPT_MAXAGE_CONN.html)
    pub const setConnectionMaxAge = Long(.CURLOPT_MAXAGE_CONN);
    /// Timeout for the connection phase. See [CURLOPT_CONNECTTIMEOUT](https://curl.se/libcurl/c/CURLOPT_CONNECTTIMEOUT.html)
    pub const setConnectionTimeout = Long(.CURLOPT_CONNECTTIMEOUT);
    /// Millisecond timeout for the connection phase. See [CURLOPT_CONNECTTIMEOUT_MS](https://curl.se/libcurl/c/CURLOPT_CONNECTTIMEOUT_MS.html)
    pub const setConnectionTimeoutMillis = Long(.CURLOPT_CONNECTTIMEOUT_MS);
    /// IP version to resolve to. See [CURLOPT_IPRESOLVE](https://curl.se/libcurl/c/CURLOPT_IPRESOLVE.html)
    pub const setIPResolve = Long(.CURLOPT_IPRESOLVE);
    /// Only connect, nothing else. See [CURLOPT_CONNECT_ONLY](https://curl.se/libcurl/c/CURLOPT_CONNECT_ONLY.html)
    pub const setOnlyConnect = Switch(.CURLOPT_CONNECT_ONLY);
    /// Use TLS/SSL. See [CURLOPT_USE_SSL](https://curl.se/libcurl/c/CURLOPT_USE_SSL.html)
    pub const setUseSSL = Long(.CURLOPT_USE_SSL);
    /// Provide fixed/fake name resolves. See [CURLOPT_RESOLVE](https://curl.se/libcurl/c/CURLOPT_RESOLVE.html)
    pub const setResolves = StringList(.CURLOPT_RESOLVE);
    /// Bind name resolves to this interface. See [CURLOPT_DNS_INTERFACE](https://curl.se/libcurl/c/CURLOPT_DNS_INTERFACE.html)
    pub const setDNSInterface = String(.CURLOPT_DNS_INTERFACE);
    /// Bind name resolves to this IP4 address. See [CURLOPT_DNS_LOCAL_IP4](https://curl.se/libcurl/c/CURLOPT_DNS_LOCAL_IP4.html)
    pub const setDNSLocalIPv4 = String(.CURLOPT_DNS_LOCAL_IP4);
    /// Bind name resolves to this IP6 address. See [CURLOPT_DNS_LOCAL_IP6](https://curl.se/libcurl/c/CURLOPT_DNS_LOCAL_IP6.html)
    pub const setDNSLocalIPv6 = String(.CURLOPT_DNS_LOCAL_IP6);
    /// Preferred DNS servers. See [CURLOPT_DNS_SERVERS](https://curl.se/libcurl/c/CURLOPT_DNS_SERVERS.html)
    pub const setDNSServers = String(.CURLOPT_DNS_SERVERS);
    /// Shuffle addresses before use. See [CURLOPT_DNS_SHUFFLE_ADDRESSES](https://curl.se/libcurl/c/CURLOPT_DNS_SERVERS.html)
    pub const setDNSShuffleAddresses = String(.CURLOPT_DNS_SHUFFLE_ADDRESSES);
    /// Timeout for waiting for the server's connect back to be accepted. See [CURLOPT_ACCEPTTIMEOUT_MS](https://curl.se/libcurl/c/CURLOPT_ACCEPTTIMEOUT_MS.html)
    pub const setFTPAcceptTimeoutMillis = Switch(.CURLOPT_ACCEPTTIMEOUT_MS);
    /// Timeout for happy eyeballs. See [CURLOPT_HAPPY_EYEBALLS_TIMEOUT_MS](https://curl.se/libcurl/c/CURLOPT_HAPPY_EYEBALLS_TIMEOUT_MS.html)
    pub const setHappyEyeballsTimeout = Long(.CURLOPT_HAPPY_EYEBALLS_TIMEOUT_MS);
    /// Sets the interval at which connection upkeep are performed. See [CURLOPT_UPKEEP_INTERVAL_MS](https://curl.se/libcurl/c/CURLOPT_UPKEEP_INTERVAL_MS.html)
    pub const setUpkeepIntervalMillis = Long(.CURLOPT_UPKEEP_INTERVAL_MS);

    // SSL and Security Options
    pub const setSSLCert = String(.CURLOPT_SSLCERT);
    pub const setSSLCertBlob = Blob(.CURLOPT_SSLCERT_BLOB);
    pub const setProxySSLCert = String(.CURLOPT_PROXY_SSLCERT);
    pub const setProxySSLCertBlob = Blob(.CURLOPT_PROXY_SSLCERT_BLOB);
    pub const setSSLCertType = String(.CURLOPT_SSL_CERTYPE);
    pub const setProxySSLCertType = String(.CURLOPT_PROXY_SSLCERTTYPE);
    pub const setSSLKey = String(.CURLOPT_SSLKEY);
    pub const setSSLKeyType = String(.CURLOPT_SSL_KEYTYPE);
    pub const setSSLKeyBlob = Blob(.CURLOPT_SSLKEY_BLOB);
    pub const setProxySSLKey = String(.CURLOPT_SSH_HOST_PUBLIC_KEY_MD5);
    pub const setProxySSLKeyBlob = Blob(.CURLOPT_PROXY_SSLKEY_BLOB);
    pub const setProxySSLKeyType = String(.CURLOPT_PROXY_SSLKEYTYPE);
    pub const setKeyPassword = String(.CURLOPT_KEYPASSWD);
    pub const setProxyKeyPassword = String(.CURLOPT_PROXY_KEYPASSWD);
    pub const setSSLECCurves = String(.CURLOPT_SSL_EC_CURVES);
    pub const setSSLEnableALPN = Switch(.CURLOPT_SSL_ENABLE_ALPN);
    pub const setSSLEnableNPN = Switch(.CURLOPT_SSL_ENABLE_NPN);
    pub const setSSLEngine = String(.CURLOPT_SSLENGINE);
    pub const setSSLEngineDefault = Switch(.CURLOPT_SSLENGINE_DEFAULT);
    pub const setSSLFalseStart = Switch(.CURLOPT_SSL_FALSESTART);
    pub const setSSLVersion = Long(.CURLOPT_SSLVERSION);
    pub const setProxySSLVersion = Long(.CURLOPT_PROXY_SSLVERSION);
    pub const setSSLVerifyHost = Switch(.CURLOPT_SSH_HOST_PUBLIC_KEY_MD5);
    pub const setProxySSLVerifyHost = Switch(.CURLOPT_SSL_VERIFYHOST);
    pub const setSSLVerifyPeer = Switch(.CURLOPT_SSL_VERIFYPEER);
    pub const setProxySSLVerifyPeer = Switch(.CURLOPT_PROXY_SSL_VERIFYPEER);
    pub const setSSLVerifyStatus = Switch(.CURLOPT_SSL_VERIFYSTATUS);
    pub const setCAInfo = String(.CURLOPT_CAINFO);
    pub const setProxyCAInfo = String(.CURLOPT_PROXY_CAINFO);
    pub const setIssuerCert = String(.CURLOPT_ISSUERCERT);
    pub const setIssuerCertBlob = Blob(.CURLOPT_ISSUERCERT_BLOB);
    pub const setProxyIssuerCert = String(.CURLOPT_PROXY_ISSUERCERT);
    pub const setProxyIssuerCertBlob = Blob(.CURLOPT_PROXY_ISSUERCERT_BLOB);
    pub const setCAPath = String(.CURLOPT_CAPATH);
    pub const setProxyCAPath = String(.CURLOPT_PROXY_CAPATH);
    pub const setCRLFile = String(.CURLOPT_CRLFILE);
    pub const setProxyCRLFile = String(.CURLOPT_PROXY_CRLFILE);
    pub const setCertInfo = Switch(.CURLOPT_CERTINTO);
    pub const setPinnedPublicKey = String(.CURLOPT_PINNEDPUBKEY);
    pub const setProxyPinnedPublicKey = String(.CURLOPT_PROXY_PINNEDPUBKEY);
    pub const setRandomFile = String(.CURLOPT_RANDOM_FILE);
    pub const setEDGSocket = String(.CURLOPT_EGDSOCKET);
    pub const setSSLCipherList = String(.CURLOPT_SSL_CIPHERLIST);
    pub const setProxySSLCipherList = String(.CURLOPT_PROXY_SSL_CIPHER_LIST);
    pub const setTLS13Ciphers = String(.CURLOPT_TLS13_CIPHERS);
    pub const setProxyTLS13Ciphers = String(.CURLOPT_PROXY_TLS13_CIPHERS);
    pub const setSSLSessionIDCache = Switch(.CURLOPT_SSL_SESSIONID_CACHE);
    pub const setSSLOptions = Long(.CURLOPT_SSL_OPTIONS);
    pub const setProxySSLOptions = Long(.CURLOPT_PROXY_SSL_OPTIONS);
    pub const setKRBLevel = String(.CURLOPT_KRBLEVEL);
    pub const setGSAPIDelegation = Long(.CURLOPT_GSAPI_DELEGATION);

    // SSH Options
    // TODO(haze): CURLOPT_KEYFILE_FUNCTION
    pub const setSSHAuthTypes = Long(.CURLOPT_SSH_AUTH_TYPES);
    pub const setSSHCompression = Switch(.CURLOPT_COMPRESSION);
    pub const setSSHHostPublicKeyMD5 = String(.CURLOPT_SSH_HOST_PUBLIC_KEY_MD5);
    pub const setSSHPublicKeyfile = String(.CURLOPT_SSH_PUBLIC_KEYFILE);
    pub const setSSHPrivateKeyfile = String(.CURLOPT_SSH_PRIVATE_KEYFILE);
    pub const setSSHKnownHosts = String(.CURLOPT_SSH_KNOWNHOSTS);
    pub const setSSHKeyData = UserData(.CURLOPT_SSH_KEYDATA);
    // Other Options
    // TODO(haze): CURLOPT_SHARE and CURLOPT_PRIVATE
    /// Mode for creating new remote files. See [CURLOPT_NEW_FILE_PERMS](https://curl.se/libcurl/c/CURLOPT_NEW_FILE_PERMS.html)
    pub const setNewFilePerms = Long(.CURLOPT_NEW_FILE_PERMS);
    /// Mode for creating new remote directories. See [CURLOPT_NEW_DIRECTORY_PERMS](https://curl.se/libcurl/c/CURLOPT_NEW_DIRECTORY_PERMS.html)
    pub const setNewDirectoryPerms = Long(.CURLOPT_NEW_DIRECTORY_PERMS);
    // TELNET Options
    pub const setTELNETOptions = CurlStringList(.CURLOPT_TELNETOPTIONS);
};

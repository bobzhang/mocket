///|
/// Returns a middleware that sets common security response headers.
///
/// All parameters are optional and have safe defaults. Pass `""` to disable a
/// specific header entirely.
///
/// - `hsts` — `Strict-Transport-Security` value (default: `"max-age=63072000; includeSubDomains"`). Only meaningful over TLS.
/// - `csp` — `Content-Security-Policy` value (default: `"default-src 'self'"`).
/// - `permissions_policy` — `Permissions-Policy` value (default: `"camera=(), microphone=(), geolocation=()"`).
pub fn security_headers(
  hsts? : String = "max-age=63072000; includeSubDomains",
  csp? : String = "default-src 'self'",
  permissions_policy? : String = "camera=(), microphone=(), geolocation=()",
) -> Middleware {
  (event, next) => {
    let res = next()
    event.res.headers.set("X-Content-Type-Options", "nosniff")
    event.res.headers.set("X-Frame-Options", "DENY")
    event.res.headers.set("X-XSS-Protection", "0")
    event.res.headers.set("Referrer-Policy", "strict-origin-when-cross-origin")
    if hsts != "" {
      event.res.headers.set("Strict-Transport-Security", hsts)
    }
    if csp != "" {
      event.res.headers.set("Content-Security-Policy", csp)
    }
    if permissions_policy != "" {
      event.res.headers.set("Permissions-Policy", permissions_policy)
    }
    res
  }
}

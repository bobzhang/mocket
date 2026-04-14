# Middleware

Drop-in middleware for Crescent: rate limiting, request tracing, and security
headers.

A middleware wraps a request handler — it sees the request before the handler
runs, decides whether to call the handler at all, and sees (and can modify)
the response on the way out. Crescent's middleware chain runs in "onion"
order: the first middleware registered is the outermost layer, so it is the
*first* to see the incoming request and the *last* to touch the outgoing
response.

```
request  →  [mw1  →  [mw2  →  [handler]  →  mw2]  →  mw1]  →  response
```

Each layer can short-circuit: if a middleware returns a response without
calling `next()`, the inner handler (and every inner middleware) is skipped
entirely. This is how rate limiting returns `429` without ever invoking the
handler.

This package bundles three common middlewares that almost every HTTP service
needs, regardless of its domain logic:

- `rate_limit` — fixed-window throttle that returns `429 Too Many Requests`
  with a `Retry-After` header once the limit is exceeded.
- `request_id` — assigns an `X-Request-Id` header to every request and
  response for tracing and log correlation.
- `security_headers` — sets sensible defaults for the standard security
  response headers (`X-Content-Type-Options`, `X-Frame-Options`, etc.) plus
  opt-in policy headers (HSTS, CSP, Permissions-Policy).

## Install

This package is included with `bobzhang/crescent`. Import it directly:

```
import {
  "bobzhang/crescent/middleware"
  ...
}
```

## Quick Start

Register middleware on an app with `use_middleware`. Order matters — the
first middleware registered wraps every later one:

```moonbit nocheck
///|
async fn main {
  let app = @crescent.Mocket()
  app.use_middleware(@middleware.request_id()) // outermost: IDs are set first
  app.use_middleware(@middleware.security_headers())
  app.use_middleware(
    @middleware.rate_limit(requests_per_window=100, window_ms=60000),
  )
  app.get("/api/data", _ => "hello")
  app.serve(port=4000)
}
```

## Rate Limit

`rate_limit` enforces a **fixed-window** request budget: at most
`requests_per_window` requests are allowed in each `window_ms` millisecond
interval. When the limit is exceeded, further requests receive
`429 Too Many Requests` with a `Retry-After` header telling clients how many
seconds until the window resets.

```mbt check
///|
async test "rate_limit allows traffic under the budget" {
  let app = @crescent.Mocket()
  app.use_middleware(
    @middleware.rate_limit(requests_per_window=3, window_ms=10000),
  )
  app.get("/ping", _ => "ok")
  let client = @test_client.TestClient(app)
  assert_eq(client.get("/ping").status, OK)
  assert_eq(client.get("/ping").status, OK)
  assert_eq(client.get("/ping").status, OK)
}
```

Once the budget is exhausted the middleware short-circuits: the handler is
not called and the response is returned directly:

```mbt check
///|
async test "rate_limit returns 429 with Retry-After" {
  let app = @crescent.Mocket()
  app.use_middleware(
    @middleware.rate_limit(requests_per_window=1, window_ms=10000),
  )
  app.get("/ping", _ => "ok")
  let client = @test_client.TestClient(app)
  let _first = client.get("/ping")
  let blocked = client.get("/ping")
  assert_eq(blocked.status, TooManyRequests)
  assert_true(blocked.headers.get("Retry-After") is Some(_))
}
```

### Scope and tuning

The limiter is **global per-process**, not per-IP. Every request through the
middleware counts against the same budget, which is the right default for
protecting a downstream resource (database, rate-limited upstream API) but
*not* the right tool for per-client throttling. For per-IP limiting, layer
an IP-keyed limiter in front.

- `requests_per_window` — maximum requests allowed in one window. Choose based
  on sustainable downstream throughput, not peak burst capacity.
- `window_ms` — window length in milliseconds. Shorter windows give more
  responsive limiting but are stricter about legitimate bursts; longer
  windows smooth out short spikes at the cost of slower adaptation.

## Request ID

`request_id` ensures every request (and its response) carries an
`X-Request-Id` header. This is the cornerstone of distributed tracing — log
the ID on every event in the request's lifecycle, and an operator can later
reconstruct the full story by grepping for that single value across all
services and log streams.

```mbt check
///|
async test "request_id adds an opaque hex id" {
  let app = @crescent.Mocket()
  app.use_middleware(@middleware.request_id())
  app.get("/hello", _ => "hi")
  let client = @test_client.TestClient(app)
  let res = client.get("/hello")
  // X-Request-Id changes every request
  assert_true(res.headers.get("X-Request-Id") is Some(_))
}
```

If the incoming request already has an `X-Request-Id` (typically set by an
upstream load balancer, ingress, or sibling service), its value is
**preserved** so every hop logs the same ID:

```mbt check
///|
async test "request_id preserves an upstream-assigned id" {
  let app = @crescent.Mocket()
  app.use_middleware(@middleware.request_id())
  app.get("/hello", _ => "hi")
  let client = @test_client.TestClient(app)
  let res = client.get("/hello", headers={ "X-Request-Id": "trace-abc" })
  assert_eq(res.headers.get("X-Request-Id"), Some("trace-abc"))
}
```

### Reading the ID inside a handler

Inside a handler, call `event.request_id()` to retrieve the value the
middleware stored. It returns `None` if the middleware is not installed, so
handlers that depend on tracing should fail loudly rather than silently drop
IDs:

```mbt check
///|
async test "handler can read the request id via event.request_id()" {
  let app = @crescent.Mocket()
  app.use_middleware(@middleware.request_id())
  app.get("/whoami", event => {
    match event.request_id() {
      Some(id) => "id:\{id}"
      None => "no-id"
    }
  })
  let client = @test_client.TestClient(app)
  let res = client.get("/whoami", headers={ "X-Request-Id": "trace-xyz" })
  assert_eq(res.body_text(), "id:trace-xyz")
}
```

### Why opaque hex, not a counter?

Generated IDs are **opaque hex tokens** derived from a mix of a timestamp and
a monotonic counter — not a bare sequential number. An external observer
cannot guess the next ID or probe for sibling requests by incrementing, which
matters when the ID leaks into URLs, email footers, or error pages.

## Security Headers

`security_headers` sets the standard suite of protective response headers on
every response. Four base headers are always applied as safe defaults:

| Header | Default value | Protects against |
| ------ | ------------- | ---------------- |
| `X-Content-Type-Options` | `nosniff` | MIME-sniffing attacks |
| `X-Frame-Options` | `DENY` | Clickjacking |
| `X-XSS-Protection` | `0` | Legacy XSS auditor (`0` disables it — modern guidance) |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Referrer leakage to third parties |

```mbt check
///|
async test "security_headers sets base headers" {
  let app = @crescent.Mocket()
  app.use_middleware(@middleware.security_headers())
  app.get("/", _ => "ok")
  let client = @test_client.TestClient(app)
  let res = client.get("/")
  guard res.headers
    is {
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
      "X-XSS-Protection": "0",
      "Referrer-Policy": "strict-origin-when-cross-origin",
      ..
    } else {
    fail("missing expected base security headers")
  }
}
```

### Opt-in policy headers

Three additional headers are available as opt-in parameters, all defaulting
to `""` (disabled). They are opt-in because they change how browsers load
content — a too-strict default would silently break existing apps.

| Parameter | Header | Purpose |
| --------- | ------ | ------- |
| `hsts` | `Strict-Transport-Security` | Force HTTPS for a fixed duration. Only meaningful over TLS. |
| `csp` | `Content-Security-Policy` | Whitelist where scripts, styles, images, fonts, etc. may load from. Extremely effective against XSS, but must be crafted to match your app's asset topology. |
| `permissions_policy` | `Permissions-Policy` | Control access to browser features like camera, microphone, and geolocation. |

```mbt check
///|
async test "security_headers with opt-in policy headers" {
  let app = @crescent.Mocket()
  app.use_middleware(
    @middleware.security_headers(
      hsts="max-age=31536000; includeSubDomains",
      csp="default-src 'self'",
      permissions_policy="camera=(), microphone=()",
    ),
  )
  app.get("/", _ => "ok")
  let client = @test_client.TestClient(app)
  let res = client.get("/")
  guard res.headers
    is {
      "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
      "Content-Security-Policy": "default-src 'self'",
      "Permissions-Policy": "camera=(), microphone=()",
      ..
    } else {
    fail("missing expected security headers")
  }
}
```

### Per-route overrides win

Headers already set by the handler or an inner middleware are **not
overwritten**. If one specific route needs a stricter CSP than the global
default, set it directly on `event.res` and the outer middleware will leave
it alone:

```mbt check
///|
async test "handler-set headers override middleware defaults" {
  let app = @crescent.Mocket()
  app.use_middleware(@middleware.security_headers(csp="default-src 'self'"))
  app.get("/embed", event => {
    // This route sandboxes an embed — lock it down further than the default.
    event.res.headers.set("Content-Security-Policy", "default-src 'none'")
    event.res.headers.set("X-Frame-Options", "SAMEORIGIN")
    "ok"
  })
  let client = @test_client.TestClient(app)
  let res = client.get("/embed")
  guard res.headers
    is {
      "Content-Security-Policy": "default-src 'none'",
      "X-Frame-Options": "SAMEORIGIN",
      ..
    } else {
    fail("expected handler-set headers to win over middleware defaults")
  }
}
```

This "handler-wins" rule lets you apply a coarse default to the whole app
and still tighten (or loosen) policy on a per-route basis without rewriting
the middleware stack.

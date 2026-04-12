# Fetch

A small ergonomic wrapper around `@crescent.fetch` that mirrors the browser
`fetch` API: one function per HTTP verb, one generic `request` entry point
for full control.

The underlying transport lives in the main `crescent` package — this
sub-package exists solely to give you a *verb-named* surface that reads
naturally at the call site:

```moonbit nocheck
///|
async fn load_profile() -> @crescent.HttpResponse raise Error {
  @fetch.get("https://api.example.com/me", headers={
    "Authorization": "Bearer eyJ...",
  })
}
```

Contrast that with the raw entry point, which takes the method as a
positional argument:

```moonbit nocheck
///|
async fn load_profile_raw() -> @crescent.HttpResponse raise Error {
  @crescent.fetch("https://api.example.com/me", Get, headers={
    "Authorization": "Bearer eyJ...",
  })
}
```

Both are valid. `@fetch.get` is easier to read when you already know the
method; `@crescent.fetch` is easier to use when you're routing the call
through a variable.

## The Verb Menu

Every HTTP method defined in RFC 9110 has a matching function. All of them
share the same signature (`url`, optional `data`, optional `headers`,
optional `credentials`, optional `mode`) and return an
`@crescent.HttpResponse`:

| Function | Method | Typical use |
| -------- | ------ | ----------- |
| `@fetch.get` | `GET` | Read a resource (idempotent, safe) |
| `@fetch.head` | `HEAD` | Fetch headers only (cache validation, probing) |
| `@fetch.post` | `POST` | Create a resource, submit a form |
| `@fetch.put` | `PUT` | Replace a resource (idempotent) |
| `@fetch.patch` | `PATCH` | Partially update a resource |
| `@fetch.delete` | `DELETE` | Delete a resource |
| `@fetch.options` | `OPTIONS` | Discover allowed methods (rarely needed — CORS preflights are sent by the browser) |
| `@fetch.trace` | `TRACE` | Echo the request back for diagnostics |
| `@fetch.connect` | `CONNECT` | Open a tunnel (used by proxies) |
| `@fetch.request` | (from `HttpRequest.http_method`) | Send a pre-built `HttpRequest` — useful when the method comes from configuration |

## Install

This package is included with `bobzhang/crescent`. Import it directly:

```
import {
  "bobzhang/crescent/fetch"
  ...
}
```

## GET

A plain GET with no body is the most common shape:

```moonbit nocheck
///|
async fn _example_fetch_get() -> Unit raise Error {
  let res = @fetch.get("https://api.example.com/users/42")
  let user : User = res.body()
  println(user.name)
}
```

### Query strings

There is no dedicated query-parameter helper — build the URL yourself.
Combine `@http.url_encode` with string concatenation for single-value
queries, or `@http.form_encode` for maps:

```moonbit nocheck
///|
async fn _example_fetch_search() -> Unit raise Error {
  let q = @http.url_encode("hello world")
  let _res = @fetch.get("https://api.example.com/search?q=\{q}")
  ()
}
```

## POST and Friends (PUT, PATCH)

Pass the body as `data`. Anything implementing the `&Responder` trait works
— strings, byte sequences, JSON values, or a pre-built `HttpResponse`. The
request's `Content-Type` is set by whatever `Responder` you pass:

```moonbit nocheck
///|
async fn _example_fetch_post_json() -> Unit raise Error {
  let body = @crescent.json({ "title": "Learn MoonBit", "done": false })
  let _res = @fetch.post("https://api.example.com/todos", data=body, headers={
    "Authorization": "Bearer token",
  })
  ()
}
```

For `application/x-www-form-urlencoded` bodies, encode the map with
`@http.form_encode` and set the content type explicitly:

```moonbit nocheck
///|
async fn _example_fetch_post_form() -> Unit raise Error {
  let form = @http.form_encode({ "name": "alice", "city": "NYC" })
  let _res = @fetch.post("https://api.example.com/signup", data=form, headers={
    "Content-Type": "application/x-www-form-urlencoded",
  })
  ()
}
```

## Explicit Content-Type Wins

If you set `Content-Type` in `headers`, the fetch client leaves it alone —
it never appends a second `Content-Type` header or overrides the one you
provided:

```moonbit nocheck
///|
async fn _example_fetch_custom_content_type() -> Unit raise Error {
  let _res = @fetch.post("https://api.example.com/custom", data="raw payload", headers={
    "Content-Type": "application/vnd.example.v2+json",
  })
  ()
}
```

This matters when you talk to an API that uses a custom media type or a
vendor extension — the default JSON-ish content type picked by `Responder`
would silently lose information.

## HEAD and DELETE

`HEAD` and `DELETE` take the same options as `GET`. Most of the time the
body is empty:

```moonbit nocheck
///|
async fn _example_fetch_head_delete() -> Unit raise Error {
  // Probe for existence without downloading the body
  let head_res = @fetch.head("https://api.example.com/assets/logo.png")
  if head_res.status_code == NotFound {
    return
  }
  // Idempotent delete
  let _del = @fetch.delete("https://api.example.com/todos/42", headers={
    "Authorization": "Bearer token",
  })
  ()
}
```

## `@fetch.request(req)` — Pre-Built Requests

`request` takes a fully constructed `@crescent.HttpRequest` and sends it.
Use this when the method is dynamic, when you're forwarding a request from
another source (e.g. a proxy), or when you want a single code path to
handle the request-building logic.

```mbt check
///|
test "HttpRequest can be built for @fetch.request" {
  // Build the request data structure independent of any network call.
  // Later: `@fetch.request(req)` would send it and return the response.
  let req = @crescent.HttpRequest(
    Post,
    "https://api.example.com/todos",
    { "Authorization": "Bearer token", "Content-Type": "application/json" },
    raw_body=b"{\"title\":\"Learn MoonBit\"}",
  )
  assert_eq(req.url, "https://api.example.com/todos")
  assert_eq(req.method_string(), "POST")
  assert_eq(req.get_header("Authorization"), Some("Bearer token"))
  assert_eq(req.get_header("Content-Type"), Some("application/json"))
  assert_eq(req.raw_body.length(), 25)
}
```

```moonbit nocheck
///|
async fn _example_fetch_request(
  req : @crescent.HttpRequest,
) -> Unit raise Error {
  let res = @fetch.request(req)
  println(res.status_code)
}
```

## `credentials` and `mode` (JS-Target Compatibility)

Both `FetchCredentials` and `FetchMode` mirror the options you'd pass to a
browser `fetch` call. They are accepted by every function in this package
for API symmetry with the JS target, but on **native** they are currently
accepted but **not enforced**:

| Option | JS target | Native target |
| ------ | --------- | ------------- |
| `credentials` (`Omit` / `SameOrigin` / `Include`) | Controls whether cookies and TLS client certs are attached | Accepted; you must manage cookies/TLS manually via headers |
| `mode` (`Cors` / `NoCors` / `SameOrigin` / `Navigate`) | Controls browser CORS enforcement | No-op — there is no browser sandbox |

```mbt check
///|
test "FetchCredentials renders to canonical browser strings" {
  assert_eq(@crescent.FetchCredentials::Omit.to_string(), "omit")
  assert_eq(@crescent.FetchCredentials::SameOrigin.to_string(), "same-origin")
  assert_eq(@crescent.FetchCredentials::Include.to_string(), "include")
}
```

```mbt check
///|
test "FetchMode renders to canonical browser strings" {
  assert_eq(@crescent.FetchMode::Cors.to_string(), "cors")
  assert_eq(@crescent.FetchMode::NoCors.to_string(), "no-cors")
  assert_eq(@crescent.FetchMode::SameOrigin.to_string(), "same-origin")
  assert_eq(@crescent.FetchMode::Navigate.to_string(), "navigate")
}
```

Write code that specifies these options even on native — they're free,
they document intent, and they port cleanly when a future version starts
enforcing them.

## Error Handling

Every fetch function raises `Error` on network failure, an unsupported
scheme, or a DNS lookup failure. The returned `HttpResponse` is **not**
automatically downgraded to an error for 4xx/5xx statuses — that is your
application's choice to make. Inspect `res.status_code` explicitly:

```moonbit nocheck
///|
async fn _example_fetch_error_handling() -> Unit raise Error {
  let res = @fetch.get("https://api.example.com/maybe")
  match res.status_code {
    OK =>
      // happy path
      ()
    NotFound =>
      // resource missing — handle inline
      ()
    status =>
      // anything else: log and bail out
      println("unexpected status: \{status}")
  }
}
```

For proxy-like code that wants to forward a `HttpResponse` verbatim,
transform the returned response and let the framework handle status
propagation — no need to unwrap the status into an exception.

## Testing Code That Uses Fetch

When a handler wants to call out to another service, the cleanest approach
is to extract the fetch call behind a function value and swap in a stub
during tests. The `TestClient` dispatches *into* a Mocket — it doesn't
mock `fetch` itself — so for unit tests that hit an external API, inject a
test double rather than intercepting the network.

For integration tests that need real network I/O, stand up a second Mocket
on an OS-allocated port and point your fetch call at it. The crescent
test suite's `fetch_integration_test.mbt` file follows this pattern; use
it as a template.

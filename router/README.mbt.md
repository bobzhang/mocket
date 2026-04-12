# Router

A fast, allocation-aware URL router built on a per-method radix tree.

This is the low-level primitive that Crescent uses to dispatch HTTP requests
to handlers. It's exposed as a standalone package because it is useful on
its own — any project that needs to map a set of URL templates (with named
parameters, wildcards, and globstars) to values of an arbitrary type can
drop it in without pulling in the rest of the framework.

## How Routing Works

A route is a template string with three kinds of interesting segments:

| Syntax       | Kind                         | Matches                              | Captured as    |
| ------------ | ---------------------------- | ------------------------------------ | -------------- |
| `/users`     | **Static**                   | the exact literal                    | —              |
| `/users/:id` | **Named parameter**          | any one segment                      | `params["id"]` |
| `/files/*`   | **Single-segment wildcard**  | any one segment                      | `params["_"]`  |
| `/static/**` | **Globstar (multi-segment)** | zero or more segments, joined by `/` | `params["_"]`  |

At registration time each template is parsed once into a `CompiledRoute`:
the segments are split, classified, and stored as an array of
`RouteSegment` values. At request time the radix tree walks the path one
segment at a time, trying child branches in priority order:

1. **Static** children first — an exact match always wins over a parameter
   or wildcard at the same position. So `/users/me` is preferred over
   `/users/:id` for the request `/users/me`.
2. **Named parameters** next — `:id` consumes one segment and records it.
3. **Single-segment wildcards** — `*` consumes one segment into `_`.
4. **Globstars** — `**` consumes the rest of the path into `_`.

The tree is partitioned by HTTP method, so `GET /users` and `POST /users`
live in separate trees and never have to be disambiguated at search time.
Unreachable branches are eliminated at insertion: a plain static insert is
O(path length) lookups, independent of how many other routes exist.

This package provides:

- `CompiledRoute` — a pre-parsed route template. Call `compile` once at
  startup, reuse it forever.
- `CompiledRoute::match_path` — match a compiled template against a request
  path in isolation (no tree required). Useful for unit tests and for
  routing decisions outside the main dispatch loop.
- `RadixRouter[T]` — a generic per-method router that stores any handler
  type `T`. `insert` adds a route, `search` finds the handler and parameters
  for a `(method, path)` pair.
- `RouteSegment` — the enum that describes a single parsed segment, useful
  if you need to introspect a compiled route.

## Install

This package is included with `bobzhang/crescent`. Import it directly:

```
import {
  "bobzhang/crescent/router"
  ...
}
```

## Compiling and Matching a Single Route

`@router.CompiledRoute(template)` parses a template string into an array of
`RouteSegment` values. For static templates (no parameters, no wildcards)
the `is_static` flag is set so `match_path` can fall back to a single
string comparison — faster than walking the segment array.

```mbt check
///|
test "static compiled route" {
  let route = @router.CompiledRoute("/api/health")
  assert_true(route.is_static)
  assert_eq(route.match_path("/api/health"), Some({}))
  assert_eq(route.match_path("/api/other"), None)
}
```

Named parameters capture one segment each. The captured value is returned
as a `StringView` into the original path — no allocation per match:

```mbt check
///|
test "compiled route captures named parameters" {
  let route = @router.CompiledRoute("/users/:userId/posts/:postId")
  let params = route.match_path("/users/42/posts/7")
  guard params is Some({ "userId": "42", "postId": "7", .. }) else {
    fail("expected match")
  }
}
```

## Wildcards and Globstars

A **single wildcard** `*` matches exactly one path segment. Multi-segment
paths fall through:

```mbt check
///|
test "wildcard matches a single segment" {
  let route = @router.CompiledRoute("/files/*")
  // one segment — matches
  let ok = route.match_path("/files/readme.txt")
  assert_true(ok is Some(_))
  // two segments — wildcard only captures one, no match
  assert_eq(route.match_path("/files/subdir/readme.txt"), None)
}
```

A **globstar** `**` matches zero or more segments and stores the joined
remainder under the reserved key `"_"`:

```mbt check
///|
test "globstar captures remaining segments" {
  let route = @router.CompiledRoute("/static/**")
  let params = route.match_path("/static/css/main.css")
  match params {
    Some(p) =>
      assert_eq(p.get("_").map(StringView::to_string), Some("css/main.css"))
    None => fail("expected match")
  }
}
```

The single reserved key `"_"` is shared by both wildcards and globstars —
mixing them in one template is fine, but each successive `*`/`**` overwrites
the previous one. If you need to capture multiple wildcard positions,
promote them to named parameters.

## Using the Radix Router

`RadixRouter[T]` is a generic router: the type parameter `T` is whatever
handler type your application uses. For Crescent the handler is an async
request closure; for a toy example it's just a `String`:

```mbt check
///|
test "radix router dispatches to registered handlers" {
  let router : @router.RadixRouter[String] = RadixRouter()
  router.insert("GET", @router.CompiledRoute("/api/users"), "list_users")
  router.insert("GET", @router.CompiledRoute("/api/users/:id"), "get_user")
  router.insert("POST", @router.CompiledRoute("/api/users"), "create_user")

  // GET /api/users — static match
  match router.search("GET", "/api/users") {
    Some((handler, _)) => assert_eq(handler, "list_users")
    None => fail("expected GET /api/users")
  }
  // GET /api/users/42 — param match, id captured
  match router.search("GET", "/api/users/42") {
    Some((handler, params)) => {
      assert_eq(handler, "get_user")
      assert_eq(params.get("id").map(StringView::to_string), Some("42"))
    }
    None => fail("expected GET /api/users/42")
  }
  // POST /api/users — different tree from GET
  match router.search("POST", "/api/users") {
    Some((handler, _)) => assert_eq(handler, "create_user")
    None => fail("expected POST /api/users")
  }
  // DELETE is never registered — no match
  assert_true(router.search("DELETE", "/api/users") is None)
}
```

### Static wins over parametric

When a static path and a parametric path share a prefix, the static branch
is tried first. This makes "special case" routes like `/users/me` work
alongside `/users/:id` without ordering gymnastics:

```mbt check
///|
test "static paths beat parametric siblings" {
  let router : @router.RadixRouter[String] = RadixRouter()
  router.insert("GET", @router.CompiledRoute("/users/:id"), "get_user")
  router.insert("GET", @router.CompiledRoute("/users/me"), "current_user")
  // "me" is a literal match even though :id would also fit
  match router.search("GET", "/users/me") {
    Some((h, _)) => assert_eq(h, "current_user")
    None => fail("expected static hit")
  }
  // everything else falls through to the param branch
  match router.search("GET", "/users/42") {
    Some((h, _)) => assert_eq(h, "get_user")
    None => fail("expected param hit")
  }
}
```

### Merging routers

`merge` folds all routes from one router into another. This is how
Crescent's `group(...)` sub-app builder works: each group builds its own
sub-router, and the parent merges the results at the end:

```mbt check
///|
test "merge folds routes from another router" {
  let router : @router.RadixRouter[String] = RadixRouter()
  router.insert("GET", @router.CompiledRoute("/api/users/:id"), "get_user")
  let sub : @router.RadixRouter[String] = RadixRouter()
  sub.insert("POST", @router.CompiledRoute("/api/users"), "create_user")
  router.merge(sub)
  assert_true(router.search("GET", "/api/users/1") is Some(_))
  assert_true(router.search("POST", "/api/users") is Some(_))
}
```

Duplicate `(method, path)` entries are resolved in favour of the newcomer
so a caller can override routes from a sub-router after the merge.

## Parameter Name Conflicts

Two templates that take the _same_ tree position but assign it different
parameter names (e.g. `/users/:id` and `/users/:name`) would otherwise make
parameter extraction ambiguous. At insertion time the router detects this
and emits a warning to stdout — the first name wins, and you should rename
one template to match the other. This is cheap insurance against a bug that
is genuinely painful to track down at runtime.

## Performance Notes

- **Compile once.** A `CompiledRoute` is immutable and reusable — compile
  each template at startup, store the result, and hand it to `insert`. Do
  not `compile` inside a hot path.
- **O(path length) lookup.** `search` visits one node per path segment plus
  at most a constant number of children (static, param, wildcard, globstar)
  per level, so the cost is independent of the total number of registered
  routes. A router with one route and a router with a thousand routes take
  roughly the same time for a hit.
- **Zero-allocation parameters.** Captured parameters are `StringView`
  slices into the request path, not fresh `String` values. Convert to
  `String` with `.to_string()` only when you need to hand the value off to
  code that demands ownership.
- **Patterns like `/files/**/meta`\*\* (a globstar followed by further
  segments) cannot fit in the radix tree and fall through to a per-method
  linear-scan fallback. These are rare; everything else stays on the fast
  path.

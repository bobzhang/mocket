# Testing Style Guide

This document describes the testing conventions used in Crescent and the
reasoning behind them.

## Two Tools, Two Jobs

| Tool | Trait | Best for | Auto-update? |
|------|-------|----------|--------------|
| `debug_inspect(value, content="...")` | `Debug` | Showing exact output shape in tests that double as documentation | Yes (`moon test --update`) |
| `guard value is Pattern else { fail(...) }` | -- | Asserting structural invariants when you need the bound variables for further checks | No (compile-time pattern) |

### `debug_inspect` -- Tests as Documentation

When a test exists primarily to show readers what an API returns, use
`debug_inspect`. The `content=` parameter becomes the specification:

```moonbit
test "route captures named parameters" {
  debug_inspect(
    route.match_path("/users/42/posts/7"),
    content=(
      #|Some({ "userId": <StringView: "42">, "postId": <StringView: "7"> })
    ),
  )
}
```

A reader sees the exact return type, nesting, and even that params are
`StringView` not `String` -- without any prose explanation. When the
implementation changes, `moon test --update` rewrites the snapshots
automatically. No manual assertion logic to maintain.

### `guard ... is` -- Structural Assertions

When a test needs to destructure a result and then do further work with
the bound variables, use `guard`:

```moonbit
test "find_ws_route duplicate path overrides handler" {
  guard app.find_ws_route("/ws/lobby") is Some((handler, _)) else {
    fail("expected route match")
  }
  handler(Open(WebSocketPeer(connection_id="test")))
  assert_eq(calls, ["second"])
}
```

The `guard` unwraps the `Some` and binds `handler` in one step, then the
test continues with `handler`. This is flatter and more readable than a
nested `match` with a `None => fail(...)` arm.

For Map contents, the Map pattern syntax is especially powerful:

```moonbit
test "extracts multiple params" {
  guard router.search("GET", "/users/42/posts/99")
    is Some(("get_user_post", { "id": "42", "postId": "99", .. })) else {
    fail("expected route match")
  }
}
```

This checks the handler name and the param values in a single pattern,
with `..` allowing additional keys.

## What NOT to Write

### The `match/fail` anti-pattern

```moonbit
// Don't do this:
match result {
  Some(value) => {
    assert_eq(value.field1, expected1)
    assert_eq(value.field2, expected2)
  }
  None => fail("expected match")
}
```

Problems:
- **Nesting** -- the happy path is indented inside `Some(...)`.
- **Boilerplate** -- every test needs a `None => fail(...)` arm.
- **Maintenance** -- adding a new field check means editing inside the match arm.

Replace with either `guard` (if you need the bound variables) or
`debug_inspect` (if you want to show the full shape).

### The `StringView::to_string` workaround

```moonbit
// Don't do this:
assert_eq(params.get("id").map(StringView::to_string), Some("42"))
```

The `.map(StringView::to_string)` is a workaround for `StringView` not
being directly comparable with `String` in `assert_eq`. Use `guard`
with Map patterns instead -- `{ "id": "42", .. }` compares `StringView`
against `String` naturally via pattern matching:

```moonbit
guard result is Some((_, { "id": "42", .. })) else { fail("...") }
```

Or use `debug_inspect` which renders `StringView` values explicitly:

```moonbit
debug_inspect(result, content=(
  #|Some({ "id": <StringView: "42"> })
))
```

## When to Use Which

| Situation | Tool |
|-----------|------|
| README doctest showing API output shape | `debug_inspect` |
| Unit test verifying a return value | `debug_inspect` |
| Test that destructures and continues (e.g., calls a handler) | `guard ... is` |
| Checking an `Option` is `Some` with specific fields | `guard ... is Some({...})` |
| Simple boolean or equality check | `assert_true`, `assert_eq` |
| Checking a value is `None` or `false` | `assert_eq(x, None)` or `debug_inspect` |

## Practical Tips

- **Let `moon test --update` write snapshots for you.** Write
  `debug_inspect(value)` with no `content=`, run the tests, and the tool
  fills in the actual output.
- **Use `(#|...)` for multiline content.** The `#|` multi-line string
  syntax avoids escaping issues. Wrap it in `()` to satisfy the parser.
- **Prefer `inspect` for simple `Show` values, `debug_inspect` for
  structured `Debug` values.** Both are snapshot-testable; `debug_inspect`
  shows internal structure (like `<StringView: "42">`), while `inspect`
  shows the `Show` representation.

///|
test "compiled route: static path matching" {
  let route = CompiledRoute::compile("/api/users")
  assert_true(route.is_static)
  assert_eq(route.match_path("/api/users"), Some({}))
  assert_eq(route.match_path("/api/posts"), None)
}

///|
test "compiled route: named parameter" {
  let route = CompiledRoute::compile("/users/:id")
  assert_true(route.is_static == false)
  assert_eq(route.match_path("/users/123"), Some({ "id": "123" }))
  assert_eq(route.match_path("/users/123/extra"), None)
}

///|
test "compiled route: multiple parameters" {
  let route = CompiledRoute::compile("/users/:userId/posts/:postId")
  assert_eq(
    route.match_path("/users/456/posts/789"),
    Some({ "userId": "456", "postId": "789" }),
  )
}

///|
test "compiled route: single wildcard" {
  let route = CompiledRoute::compile("/files/*")
  assert_eq(
    route.match_path("/files/document.pdf"),
    Some({ "_": "document.pdf" }),
  )
  assert_eq(route.match_path("/files/docs/readme.txt"), None)
}

///|
test "compiled route: multi-level wildcard" {
  let route = CompiledRoute::compile("/static/**")
  assert_eq(
    route.match_path("/static/css/main.css"),
    Some({ "_": "css/main.css" }),
  )
  assert_eq(
    route.match_path("/static/images/icons/user.png"),
    Some({ "_": "images/icons/user.png" }),
  )
}

///|
test "compiled route: mixed parameter and wildcard" {
  let route = CompiledRoute::compile("/users/:id/files/*")
  assert_eq(
    route.match_path("/users/123/files/avatar.jpg"),
    Some({ "id": "123", "_": "avatar.jpg" }),
  )
}

///|
test "compiled route: segments are pre-parsed" {
  let route = CompiledRoute::compile("/api/:version/users/:id")
  assert_eq(route.segments.length(), 5) // "", "api", ":version", "users", ":id"
  assert_true(route.segments[0] is Static(_))
  assert_true(route.segments[2] is Param(_))
  assert_true(route.segments[4] is Param(_))
}

///|
fn match_path(template : String, path : String) -> Map[String, StringView]? {
  CompiledRoute::compile(template).match_path(path)
}

///|
test "compiled route: middle wildcard" {
  // `/api/*/status` — wildcard between static segments
  assert_eq(match_path("/api/*/status", "/api/v1/status"), Some({ "_": "v1" }))
}

///|
test "compiled route: rejects deep path against single wildcard" {
  // `*` is single-segment, so multi-segment paths must not match
  assert_eq(match_path("/files/*", "/files/docs/readme.txt"), None)
}

///|
test "compiled route: globstar with empty trailing path" {
  // `/api/v1/**` should match `/api/v1/` with empty captured suffix
  assert_eq(match_path("/api/v1/**", "/api/v1/"), Some({ "_": "" }))
}

///|
test "compiled route: globstar between static segments" {
  // `/files/**/meta` — globstar in the middle, ending with a literal segment
  assert_eq(
    match_path("/files/**/meta", "/files/a/b/meta"),
    Some({ "_": "a/b" }),
  )
  assert_eq(match_path("/files/**/meta", "/files/a/b/raw"), None)
}

///|
test "compiled route: param then globstar" {
  let result = match_path(
    "/projects/:projectId/**", "/projects/abc/src/main.mbt",
  )
  assert_eq(result, Some({ "projectId": "abc", "_": "src/main.mbt" }))
}

///|
test "compiled route: template length mismatch with path" {
  // Template shorter than path (no wildcard)
  assert_eq(match_path("/api", "/api/users"), None)
  // Path shorter than template
  assert_eq(match_path("/api/users", "/api"), None)
}

///|
test "compiled route: special chars in parameter capture verbatim" {
  assert_eq(
    match_path("/search/:query", "/search/hello%20world"),
    Some({ "query": "hello%20world" }),
  )
}

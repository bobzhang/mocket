///|
test "compiled route: static path matching" {
  let route = @router.CompiledRoute("/api/users")
  assert_true(route.is_static)
  debug_inspect(route.match_path("/api/users"), content="Some({})")
  debug_inspect(route.match_path("/api/posts"), content="None")
}

///|
test "compiled route: named parameter" {
  let route = @router.CompiledRoute("/users/:id")
  assert_true(route.is_static == false)
  debug_inspect(
    route.match_path("/users/123"),
    content=(
      #|Some({ "id": <StringView: "123"> })
    ),
  )
  debug_inspect(route.match_path("/users/123/extra"), content="None")
}

///|
test "compiled route: multiple parameters" {
  let route = @router.CompiledRoute("/users/:userId/posts/:postId")
  debug_inspect(
    route.match_path("/users/456/posts/789"),
    content=(
      #|Some({ "userId": <StringView: "456">, "postId": <StringView: "789"> })
    ),
  )
}

///|
test "compiled route: single wildcard" {
  let route = @router.CompiledRoute("/files/*")
  debug_inspect(
    route.match_path("/files/document.pdf"),
    content=(
      #|Some({ "_": <StringView: "document.pdf"> })
    ),
  )
  debug_inspect(route.match_path("/files/docs/readme.txt"), content="None")
}

///|
test "compiled route: multi-level wildcard" {
  let route = @router.CompiledRoute("/static/**")
  debug_inspect(
    route.match_path("/static/css/main.css"),
    content=(
      #|Some({ "_": <StringView: "css/main.css"> })
    ),
  )
  debug_inspect(
    route.match_path("/static/images/icons/user.png"),
    content=(
      #|Some({ "_": <StringView: "images/icons/user.png"> })
    ),
  )
}

///|
test "compiled route: mixed parameter and wildcard" {
  let route = @router.CompiledRoute("/users/:id/files/*")
  debug_inspect(
    route.match_path("/users/123/files/avatar.jpg"),
    content=(
      #|Some({ "id": <StringView: "123">, "_": <StringView: "avatar.jpg"> })
    ),
  )
}

///|
test "compiled route: segments are pre-parsed" {
  let route = @router.CompiledRoute("/api/:version/users/:id")
  assert_eq(route.segments.length(), 5) // "", "api", ":version", "users", ":id"
  assert_true(route.segments[0] is Static(_))
  assert_true(route.segments[2] is Param(_))
  assert_true(route.segments[4] is Param(_))
}

///|
fn match_path(template : String, path : String) -> Map[String, StringView]? {
  @router.CompiledRoute(template).match_path(path)
}

///|
test "compiled route: middle wildcard" {
  debug_inspect(
    match_path("/api/*/status", "/api/v1/status"),
    content=(
      #|Some({ "_": <StringView: "v1"> })
    ),
  )
}

///|
test "compiled route: rejects deep path against single wildcard" {
  debug_inspect(
    match_path("/files/*", "/files/docs/readme.txt"),
    content="None",
  )
}

///|
test "compiled route: globstar with empty trailing path" {
  debug_inspect(
    match_path("/api/v1/**", "/api/v1/"),
    content=(
      #|Some({ "_": <StringView: ""> })
    ),
  )
}

///|
test "compiled route: globstar between static segments" {
  debug_inspect(
    match_path("/files/**/meta", "/files/a/b/meta"),
    content=(
      #|Some({ "_": <StringView: "a/b"> })
    ),
  )
  debug_inspect(match_path("/files/**/meta", "/files/a/b/raw"), content="None")
}

///|
test "compiled route: param then globstar" {
  debug_inspect(
    match_path("/projects/:projectId/**", "/projects/abc/src/main.mbt"),
    content=(
      #|Some(
      #|  {
      #|    "projectId": <StringView: "abc">,
      #|    "_": <StringView: "src/main.mbt">,
      #|  },
      #|)
    ),
  )
}

///|
test "compiled route: template length mismatch with path" {
  debug_inspect(match_path("/api", "/api/users"), content="None")
  debug_inspect(match_path("/api/users", "/api"), content="None")
}

///|
test "compiled route: special chars in parameter capture verbatim" {
  debug_inspect(
    match_path("/search/:query", "/search/hello%20world"),
    content=(
      #|Some({ "query": <StringView: "hello%20world"> })
    ),
  )
}

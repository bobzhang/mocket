///|
fn Mocket::find_route_for_method(
  self : Mocket,
  http_method : String,
  path : String,
) -> (HttpHandler, Map[String, StringView])? {
  if self.static_routes.get(http_method) is Some(method_routes) {
    if method_routes.get(path) is Some(handler) {
      return Some((handler, {}))
    }
  }
  match self.dynamic_routes.search(http_method, path) {
    Some((handler, params)) => return Some((handler, params))
    None => ()
  }
  None
}

///|
test "find_route_for_method hits static route" {
  let app = Mocket()
  app.get("/users", fn(_event) noraise { "users" })
  inspect(app.find_route_for_method("GET", "/users") is Some(_), content="true")
}

///|
test "find_route_for_method misses nonexistent path" {
  let app = Mocket()
  app.get("/users", fn(_event) noraise { "users" })
  inspect(
    app.find_route_for_method("GET", "/posts") is Some(_),
    content="false",
  )
}

///|
test "find_route_for_method misses wrong method" {
  let app = Mocket()
  app.get("/users", fn(_event) noraise { "users" })
  inspect(
    app.find_route_for_method("POST", "/users") is Some(_),
    content="false",
  )
}

///|
test "find_route_for_method dynamic route extracts params" {
  let app = Mocket()
  app.get("/users/:id", fn(_event) noraise { "user" })
  match app.find_route_for_method("GET", "/users/123") {
    Some((_, params)) => inspect(params, content="{\"id\": \"123\"}")
    None => fail("expected route match")
  }
}

///|
test "find_route_for_method dynamic route with multiple params" {
  let app = Mocket()
  app.get("/users/:userId/posts/:postId", fn(_event) noraise { "user_post" })
  match app.find_route_for_method("GET", "/users/42/posts/99") {
    Some((_, params)) =>
      inspect(params, content="{\"userId\": \"42\", \"postId\": \"99\"}")
    None => fail("expected route match")
  }
}

///|
fn Mocket::has_route_for_method(
  self : Mocket,
  http_method : String,
  path : String,
) -> Bool {
  self.find_route_for_method(http_method, path) is Some(_)
}

///|
test "has_route_for_method returns true for registered route" {
  let app = Mocket()
  app.get("/users", fn(_event) noraise { "users" })
  inspect(app.has_route_for_method("GET", "/users"), content="true")
}

///|
test "has_route_for_method returns false for missing route" {
  let app = Mocket()
  app.get("/users", fn(_event) noraise { "users" })
  inspect(app.has_route_for_method("GET", "/posts"), content="false")
}

///|
test "has_route_for_method returns false for wrong method" {
  let app = Mocket()
  app.get("/users", fn(_event) noraise { "users" })
  inspect(app.has_route_for_method("DELETE", "/users"), content="false")
}

///|
test "has_route_for_method matches dynamic route" {
  let app = Mocket()
  app.get("/users/:id", fn(_event) noraise { "user" })
  inspect(app.has_route_for_method("GET", "/users/456"), content="true")
}

///|
fn Mocket::allowed_methods(
  self : Mocket,
  path : String,
  include_implicit_options : Bool,
) -> Array[String] {
  let allowed : Array[String] = []
  let supports_get = self.has_route_for_method("GET", path)
  let supports_head = self.has_route_for_method("HEAD", path)
  if supports_get {
    allowed.push("GET")
  }
  if supports_head || supports_get {
    allowed.push("HEAD")
  }
  for http_method in ["POST", "PUT", "PATCH", "DELETE"] {
    if self.has_route_for_method(http_method, path) {
      allowed.push(http_method)
    }
  }
  let supports_options = self.has_route_for_method("OPTIONS", path)
  if supports_options || (include_implicit_options && !allowed.is_empty()) {
    allowed.push("OPTIONS")
  }
  for http_method in ["TRACE", "CONNECT"] {
    if self.has_route_for_method(http_method, path) {
      allowed.push(http_method)
    }
  }
  allowed
}

///|
test "allowed_methods includes HEAD for GET route" {
  let app = Mocket()
  app.get("/test", fn(_event) noraise { "ok" })
  let methods = app.allowed_methods("/test", false)
  inspect(methods, content="[\"GET\", \"HEAD\"]")
}

///|
test "allowed_methods with implicit OPTIONS" {
  let app = Mocket()
  app.get("/test", fn(_event) noraise { "ok" })
  let methods = app.allowed_methods("/test", true)
  inspect(methods, content="[\"GET\", \"HEAD\", \"OPTIONS\"]")
}

///|
test "allowed_methods multiple methods on same path" {
  let app = Mocket()
  app.get("/users", fn(_event) noraise { "list" })
  app.post("/users", fn(_event) noraise { "create" })
  app.delete("/users", fn(_event) noraise { "remove" })
  let methods = app.allowed_methods("/users", false)
  inspect(methods, content="[\"GET\", \"HEAD\", \"POST\", \"DELETE\"]")
}

///|
test "allowed_methods with explicit OPTIONS handler" {
  let app = Mocket()
  app.get("/test", fn(_event) noraise { "ok" })
  app.options_raw("/test", fn(_event) noraise { "opts" })
  let methods = app.allowed_methods("/test", false)
  inspect(methods, content="[\"GET\", \"HEAD\", \"OPTIONS\"]")
}

///|
test "allowed_methods returns empty for unknown path" {
  let app = Mocket()
  app.get("/test", fn(_event) noraise { "ok" })
  let methods = app.allowed_methods("/unknown", false)
  inspect(methods, content="[]")
}

///|
test "allowed_methods no implicit OPTIONS when empty" {
  let app = Mocket()
  let methods = app.allowed_methods("/nothing", true)
  inspect(methods, content="[]")
}

///|
// Find matching route and parameters
fn Mocket::find_route(
  self : Mocket,
  http_method : String,
  path : String,
) -> (HttpHandler, Map[String, StringView])? {
  if self.find_route_for_method(http_method, path) is Some(route) {
    return Some(route)
  }
  if self.static_routes.get("*") is Some(wildcard_routes) {
    if wildcard_routes.get(path) is Some(handler) {
      return Some((handler, {}))
    }
  }
  match self.dynamic_routes.search("*", path) {
    Some((handler, params)) => return Some((handler, params))
    None => ()
  }
  None
}

///|
test "find_route returns method-specific route first" {
  let app = Mocket()
  app.get("/test", fn(_event) noraise { "get" })
  app.all_raw("/test", fn(_event) noraise { "all" })
  inspect(app.find_route("GET", "/test") is Some(_), content="true")
}

///|
test "find_route falls back to wildcard when method not matched" {
  let app = Mocket()
  app.all_raw("/any", fn(_event) noraise { "any" })
  inspect(app.find_route("DELETE", "/any") is Some(_), content="true")
}

///|
test "find_route returns None when no route matches" {
  let app = Mocket()
  app.get("/users", fn(_event) noraise { "users" })
  inspect(app.find_route("GET", "/missing") is Some(_), content="false")
}

///|
test "find_route wildcard dynamic route with params" {
  let app = Mocket()
  app.all_raw("/items/:id", fn(_event) noraise { "item" })
  match app.find_route("PATCH", "/items/77") {
    Some((_, params)) => inspect(params, content="{\"id\": \"77\"}")
    None => fail("expected wildcard dynamic route match")
  }
}

///|
fn Mocket::find_ws_route(
  self : Mocket,
  path : String,
) -> (WebSocketHandler, Map[String, StringView])? {
  if self.ws_static_routes.get(path) is Some(handler) {
    return Some((handler, {}))
  }
  self.ws_dynamic_routes.search("WS", path)
}

///|
test "find_ws_route static hit" {
  let app = Mocket()
  app.ws("/ws", fn(_event) {  })
  inspect(app.find_ws_route("/ws") is Some(_), content="true")
}

///|
test "find_ws_route dynamic hit" {
  let app = Mocket()
  app.ws("/ws/:room", fn(_event) {  })
  inspect(app.find_ws_route("/ws/lobby") is Some(_), content="true")
}

///|
test "find_ws_route extracts params from dynamic path" {
  let app = Mocket()
  app.ws("/ws/:room", fn(_event) {  })
  match app.find_ws_route("/ws/lobby") {
    Some((_, params)) =>
      assert_eq(params.get("room").map(StringView::to_string), Some("lobby"))
    None => fail("expected route match")
  }
}

///|
test "find_ws_route extracts multiple params" {
  let app = Mocket()
  app.ws("/ws/:room/user/:id", fn(_event) {  })
  match app.find_ws_route("/ws/lobby/user/42") {
    Some((_, params)) => {
      assert_eq(params.get("room").map(StringView::to_string), Some("lobby"))
      assert_eq(params.get("id").map(StringView::to_string), Some("42"))
    }
    None => fail("expected route match")
  }
}

///|
test "find_ws_route static returns empty params" {
  let app = Mocket()
  app.ws("/ws", fn(_event) {  })
  match app.find_ws_route("/ws") {
    Some((_, params)) => assert_eq(params.length(), 0)
    None => fail("expected route match")
  }
}

///|
test "find_ws_route duplicate path overrides handler" {
  // Before the radix tree refactor, re-registering the same dynamic path
  // silently added a second entry and the first-registered handler won.
  // Now re-registration overrides the previous handler.
  let calls : Array[String] = []
  let app = Mocket()
  app.ws("/ws/:room", fn(_event) { calls.push("first") })
  app.ws("/ws/:room", fn(_event) { calls.push("second") })
  match app.find_ws_route("/ws/lobby") {
    Some((handler, _)) => {
      handler(Open(WebSocketPeer(connection_id="test")))
      assert_eq(calls, ["second"])
    }
    None => fail("expected route match")
  }
}

///|
test "find_ws_route static beats param" {
  // Precedence: when a URL could match both a static route and a param
  // route, the static route wins regardless of registration order.
  let calls : Array[String] = []
  let app = Mocket()
  app.ws("/ws/:room", fn(_event) { calls.push("param") })
  app.ws("/ws/lobby", fn(_event) { calls.push("static") })
  match app.find_ws_route("/ws/lobby") {
    Some((handler, _)) => {
      handler(Open(WebSocketPeer(connection_id="test")))
      // Static routes are stored separately and checked first
      assert_eq(calls, ["static"])
    }
    None => fail("expected route match")
  }
}

///|
test "find_ws_route param beats wildcard" {
  // :name should be preferred over * for the same position
  let calls : Array[String] = []
  let app = Mocket()
  app.ws("/ws/*", fn(_event) { calls.push("wildcard") })
  app.ws("/ws/:room", fn(_event) { calls.push("param") })
  match app.find_ws_route("/ws/lobby") {
    Some((handler, _)) => {
      handler(Open(WebSocketPeer(connection_id="test")))
      assert_eq(calls, ["param"])
    }
    None => fail("expected route match")
  }
}

///|
test "find_ws_route miss" {
  let app = Mocket()
  app.ws("/ws", fn(_event) {  })
  inspect(app.find_ws_route("/other") is Some(_), content="false")
}

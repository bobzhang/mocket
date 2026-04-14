///|
async test "test client GET returns text" {
  let app = @crescent.Mocket()
  app.get("/hello", _ => "Hello!")
  let client = @test_client.TestClient(app)
  let res = client.get("/hello")
  assert_eq(res.status, OK)
  assert_eq(res.body_text(), "Hello!")
}

///|
async test "test client GET returns json" {
  let app = @crescent.Mocket()
  app.get("/data", _ => ({ "key": "value" } : Json))
  let client = @test_client.TestClient(app)
  let res = client.get("/data")
  assert_eq(res.status, OK)
  inspect(
    res.headers.get("Content-Type"),
    content="Some(\"application/json; charset=utf-8\")",
  )
}

///|
async test "test client POST with body" {
  let app = @crescent.Mocket()
  app.post("/echo", event => {
    let text : String = event.req.body() catch { _ => "error" }
    text
  })
  let client = @test_client.TestClient(app)
  let res = client.post("/echo", body=b"hello world")
  assert_eq(res.status, OK)
  assert_eq(res.body_text(), "hello world")
}

///|
async test "test client route params" {
  let app = @crescent.Mocket()
  app.get("/users/:id", event => event.param("id").unwrap_or("?"))
  let client = @test_client.TestClient(app)
  let res = client.get("/users/42")
  assert_eq(res.status, OK)
  assert_eq(res.body_text(), "42")
}

///|
async test "test client 404 for missing route" {
  let app = @crescent.Mocket()
  app.get("/exists", _ => "ok")
  let client = @test_client.TestClient(app)
  let res = client.get("/missing")
  assert_eq(res.status, NotFound)
}

///|
async test "test client custom not found handler" {
  let app = @crescent.Mocket()
  app.set_not_found_handler(_ => @crescent.HttpResponse::not_found().body(
      "custom 404",
    ))
  let client = @test_client.TestClient(app)
  let res = client.get("/anything")
  assert_eq(res.status, NotFound)
  assert_eq(res.body_text(), "custom 404")
}

///|
async test "test client runs middleware" {
  // Uses an inline custom middleware rather than a named one from
  // bobzhang/crescent/middleware — this test verifies that @test_client.TestClient
  // dispatches requests through the middleware chain, not that any
  // particular middleware behaves correctly.
  let ran : Ref[Bool] = Ref::new(false)
  let app = @crescent.Mocket()
  app.use_middleware((_event, next) => {
    ran.val = true
    next()
  })
  app.get("/test", _ => "ok")
  let client = @test_client.TestClient(app)
  let res = client.get("/test")
  assert_eq(res.status, OK)
  assert_eq(ran.val, true)
}

///|
async test "test client with error handling handler" {
  let app = @crescent.Mocket()
  app.post("/users", event => {
    let _body : Json = event.req.json()
    "created"
  })
  let client = @test_client.TestClient(app)
  // Valid request
  let res = client.post("/users", body=b"{\"name\":\"Alice\"}")
  assert_eq(res.status, OK)
  // Invalid JSON
  let res2 = client.post("/users", body=b"not json")
  assert_eq(res2.status, BadRequest)
}

///|
async test "test client method not allowed" {
  let app = @crescent.Mocket()
  app.get("/only-get", _ => "ok")
  let client = @test_client.TestClient(app)
  let res = client.post("/only-get")
  assert_eq(res.status, MethodNotAllowed)
}

///|
async test "test client PUT and DELETE" {
  let app = @crescent.Mocket()
  app.put("/item", _ => "updated")
  app.delete("/item", _ => "deleted")
  let client = @test_client.TestClient(app)
  let res_put = client.put("/item")
  assert_eq(res_put.body_text(), "updated")
  let res_del = client.delete("/item")
  assert_eq(res_del.body_text(), "deleted")
}

///|
async test "test client with custom headers" {
  let app = @crescent.Mocket()
  app.get("/auth", event => {
    match event.req.get_header("authorization") {
      Some(token) => "token: " + token
      None => "no auth"
    }
  })
  let client = @test_client.TestClient(app)
  let res = client.get("/auth")
  assert_eq(res.body_text(), "no auth")
  let res2 = client.get("/auth", headers={ "Authorization": "Bearer abc123" })
  assert_eq(res2.body_text(), "token: Bearer abc123")
}

///|
async test "test client with path-scoped middleware" {
  let order : Array[String] = []
  let app = @crescent.Mocket()
  app.use_middleware(
    (_event, next) => {
      order.push("api-mw")
      next()
    },
    base_path="/api",
  )
  app.get("/api/data", _ => "data")
  app.get("/other", _ => "other")
  let client = @test_client.TestClient(app)
  // Should trigger middleware
  ignore(client.get("/api/data"))
  assert_eq(order.length(), 1)
  // Should NOT trigger middleware
  ignore(client.get("/other"))
  assert_eq(order.length(), 1)
}

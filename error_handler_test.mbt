///|
test "custom not found handler is set" {
  let app = @crescent.App()
  app.set_not_found_handler(_ => {
    @crescent.HttpResponse(status_code=NotFound).body("Custom 404")
  })
  inspect(app.has_not_found_handler(), content="true")
}

///|
test "not found handler defaults to none" {
  let app = @crescent.App()
  inspect(app.has_not_found_handler(), content="false")
}

///|
test "group merges not found handler" {
  let app = @crescent.App()
  app.group("/api", group => {
    group.set_not_found_handler(_ => {
      @crescent.HttpResponse(status_code=NotFound).body("API 404")
    })
  })
  inspect(app.has_not_found_handler(), content="true")
}

///|
async test "group not_found_handler is scoped to the group prefix" {
  let app = @crescent.App()
  app.group("/api", group => {
    group.set_not_found_handler(_ => {
      @crescent.HttpResponse(status_code=NotFound).body("API 404")
    })
  })
  let client = @test_client.TestClient(app)
  // Inside the group's prefix: the group's handler fires.
  let inside = client.get("/api/missing")
  assert_eq(inside.body_text(), "API 404")
  // Outside the prefix: the group's handler does NOT take over the whole
  // app; we fall back to the default 404 body.
  let outside = client.get("/random/path")
  assert_eq(outside.body_text(), "Not Found")
}

///|
async test "group not_found_handler chains to parent app handler outside prefix" {
  let app = @crescent.App()
  app.set_not_found_handler(_ => {
    @crescent.HttpResponse(status_code=NotFound).body("App 404")
  })
  app.group("/api", group => {
    group.set_not_found_handler(_ => {
      @crescent.HttpResponse(status_code=NotFound).body("API 404")
    })
  })
  let client = @test_client.TestClient(app)
  let inside = client.get("/api/missing")
  assert_eq(inside.body_text(), "API 404")
  let outside = client.get("/random/path")
  assert_eq(outside.body_text(), "App 404")
}

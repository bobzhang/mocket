///|
test "HttpMethod round-trips through string conversion" {
  let meths : Array[HttpMethod] = [
    Get,
    Head,
    Post,
    Put,
    Patch,
    Delete,
    Options,
    Trace,
    Connect,
  ]
  for meth in meths {
    let s = meth.to_method_string()
    let back = HttpMethod::from_string(s)
    assert_eq(meth, back)
  }
}

///|
test "HttpMethod::from_string handles unknown methods" {
  let custom = HttpMethod::from_string("PURGE")
  assert_true(custom is Other(_))
  assert_eq(custom.to_method_string(), "PURGE")
}

///|
test "HttpMethod pattern matching in handlers" {
  let req = HttpRequest(Get, "/", {}, raw_body=b"")
  let result = match req.http_method {
    Get => "get"
    Post => "post"
    _ => "other"
  }
  assert_eq(result, "get")
}

///|
test "HttpMethod string interpolation via Show" {
  let meth : HttpMethod = Post
  let s = "\{meth}"
  assert_eq(s, "POST")
}

///|
test "get_cookie supports case-insensitive header lookup and delete_cookie expires values" {
  let req_lower = HttpRequest(
    Get,
    "/",
    { "cookie": "session=abc123; theme=dark" },
    raw_body=b"",
  )
  guard req_lower.get_cookie("session") is Some({ value: "abc123", .. }) else {
    fail("Expected session cookie")
  }
  let req_mixed = HttpRequest(
    Get,
    "/",
    { "CoOkIe": "theme=dark" },
    raw_body=b"",
  )
  guard req_mixed.get_cookie("theme") is Some({ value: "dark", .. }) else {
    fail("Expected theme cookie")
  }
  assert_eq(req_mixed.get_cookie("missing"), None)
  let res = HttpResponse(status_code=OK)
  res.delete_cookie("session")
  guard res.cookies.get("session")
    is Some({ value: "", max_age: Some(0), path: Some("/"), .. }) else {
    fail("Expected deleted session cookie with default Path=/")
  }
  // Cookies set with a narrower scope need explicit path/domain to match.
  let scoped = HttpResponse(status_code=OK)
  scoped.delete_cookie("session", path="/app", domain="example.com")
  guard scoped.cookies.get("session")
    is Some(
      {
        value: "",
        max_age: Some(0),
        path: Some("/app"),
        domain: Some("example.com"),
        ..,
      }
    ) else {
    fail("Expected scoped deletion to preserve path/domain")
  }
}

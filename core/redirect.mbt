///|
/// Returns a 301 Moved Permanently redirect response.
pub fn HttpResponse::redirect(location : String) -> HttpResponse {
  let res = HttpResponse(status_code=MovedPermanently)
  res.headers.set("Location", location)
  res
}

///|
/// Returns a 302 Found (temporary) redirect response.
pub fn HttpResponse::redirect_temporary(location : String) -> HttpResponse {
  let res = HttpResponse(status_code=Found)
  res.headers.set("Location", location)
  res
}

///|
/// Returns a 307 Temporary Redirect response (preserves method).
pub fn HttpResponse::redirect_307(location : String) -> HttpResponse {
  let res = HttpResponse(status_code=TemporaryRedirect)
  res.headers.set("Location", location)
  res
}

///|
/// Returns a 308 Permanent Redirect response (preserves method).
pub fn HttpResponse::redirect_308(location : String) -> HttpResponse {
  let res = HttpResponse(status_code=PermanentRedirect)
  res.headers.set("Location", location)
  res
}

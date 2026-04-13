///|
/// Sends an HTTP request using the method, URL, headers, and body from the given
/// `HttpRequest` object, and returns the response.
pub async fn request(req : @core.HttpRequest) -> @core.HttpResponse raise Error {
  let http_method = req.http_method
  if req.raw_body.length() == 0 {
    fetch(req.url, http_method, headers=req.headers)
  } else {
    let data = req.raw_body
    fetch(req.url, http_method, data~, headers=req.headers)
  }
}

///|
/// Sends an HTTP GET request to the given URL with optional data, headers,
/// credentials, and mode settings.
pub async fn get(
  url : String,
  data? : &@core.Responder,
  headers? : Map[String, String],
  credentials? : FetchCredentials,
  mode? : FetchMode,
) -> @core.HttpResponse raise Error {
  fetch(url, Get, data?, headers?, credentials?, mode?)
}

///|
/// Sends an HTTP DELETE request to the given URL with optional data, headers,
/// credentials, and mode settings.
pub async fn delete(
  url : String,
  data? : &@core.Responder,
  headers? : Map[String, String],
  credentials? : FetchCredentials,
  mode? : FetchMode,
) -> @core.HttpResponse raise Error {
  fetch(url, Delete, data?, headers?, credentials?, mode?)
}

///|
/// Sends an HTTP HEAD request to the given URL with optional data, headers,
/// credentials, and mode settings.
pub async fn head(
  url : String,
  data? : &@core.Responder,
  headers? : Map[String, String],
  credentials? : FetchCredentials,
  mode? : FetchMode,
) -> @core.HttpResponse raise Error {
  fetch(url, Head, data?, headers?, credentials?, mode?)
}

///|
/// Sends an HTTP OPTIONS request to the given URL with optional data, headers,
/// credentials, and mode settings.
pub async fn options(
  url : String,
  data? : &@core.Responder,
  headers? : Map[String, String],
  credentials? : FetchCredentials,
  mode? : FetchMode,
) -> @core.HttpResponse raise Error {
  fetch(url, Options, data?, headers?, credentials?, mode?)
}

///|
/// Sends an HTTP TRACE request to the given URL with optional data, headers,
/// credentials, and mode settings.
pub async fn trace(
  url : String,
  data? : &@core.Responder,
  headers? : Map[String, String],
  credentials? : FetchCredentials,
  mode? : FetchMode,
) -> @core.HttpResponse raise Error {
  fetch(url, Trace, data?, headers?, credentials?, mode?)
}

///|
/// Sends an HTTP CONNECT request to the given URL with optional data, headers,
/// credentials, and mode settings.
pub async fn connect(
  url : String,
  data? : &@core.Responder,
  headers? : Map[String, String],
  credentials? : FetchCredentials,
  mode? : FetchMode,
) -> @core.HttpResponse raise Error {
  fetch(url, Connect, data?, headers?, credentials?, mode?)
}

///|
/// Sends an HTTP POST request to the given URL with optional data, headers,
/// credentials, and mode settings.
pub async fn post(
  url : String,
  data? : &@core.Responder,
  headers? : Map[String, String],
  credentials? : FetchCredentials,
  mode? : FetchMode,
) -> @core.HttpResponse raise Error {
  fetch(url, Post, data?, headers?, credentials?, mode?)
}

///|
/// Sends an HTTP PUT request to the given URL with optional data, headers,
/// credentials, and mode settings.
pub async fn put(
  url : String,
  data? : &@core.Responder,
  headers? : Map[String, String],
  credentials? : FetchCredentials,
  mode? : FetchMode,
) -> @core.HttpResponse raise Error {
  fetch(url, Put, data?, headers?, credentials?, mode?)
}

///|
/// Sends an HTTP PATCH request to the given URL with optional data, headers,
/// credentials, and mode settings.
pub async fn patch(
  url : String,
  data? : &@core.Responder,
  headers? : Map[String, String],
  credentials? : FetchCredentials,
  mode? : FetchMode,
) -> @core.HttpResponse raise Error {
  fetch(url, Patch, data?, headers?, credentials?, mode?)
}

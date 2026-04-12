///|
/// The main application type that holds route mappings, middleware, and WebSocket handlers.
///
/// Routing state is split by access pattern:
/// - `static_routes` — `Map[method, Map[path, handler]]` for O(1) static lookup
/// - `dynamic_routes` — radix tree for O(path_length) dynamic lookup
/// - `route_keys` — flat list of `(method, path)` for introspection via `routes()`
pub struct Mocket {
  /// Path prefix prepended to all routes in this app/group.
  priv base_path : String
  /// Flat list of `(method, path)` for introspection via `routes()`.
  priv route_keys : Array[(String, String)]
  /// Ordered middleware list; each entry is `(base_path_scope, middleware)`.
  priv middlewares : Array[(String, Middleware)]
  /// O(1) lookup for fixed paths: `Map[method, Map[path, handler]]`.
  priv static_routes : Map[String, Map[String, HttpHandler]]
  /// O(path_length) lookup for parameterized paths (`:param`, `*`, `**`).
  priv dynamic_routes : @router.RadixRouter[HttpHandler]
  /// O(1) lookup for fixed WebSocket paths.
  priv ws_static_routes : Map[String, WebSocketHandler]
  /// O(path_length) lookup for parameterized WebSocket paths.
  /// Uses `"WS"` as a synthetic method key for consistent precedence with HTTP routes.
  priv ws_dynamic_routes : @router.RadixRouter[WebSocketHandler]
  /// Unique ID scoping the native WebSocket hub for this app instance.
  priv ws_runtime_id : String
  /// Custom handler for URLs that match no registered route.
  priv mut not_found_handler : HttpHandler?

  fn new(base_path? : String) -> Mocket
}

///|
let mocket_instance_counter : Ref[Int] = Ref::new(0)

///|
fn next_mocket_instance_id() -> String {
  mocket_instance_counter.val += 1
  "mocket-\{mocket_instance_counter.val}"
}

///|
/// Creates a new Mocket application instance with an optional base path prefix.
fn Mocket::new(base_path? : String = "") -> Mocket {
  {
    base_path,
    route_keys: [],
    middlewares: [],
    static_routes: {},
    dynamic_routes: RadixRouter(),
    ws_static_routes: {},
    ws_dynamic_routes: RadixRouter(),
    ws_runtime_id: next_mocket_instance_id(),
    not_found_handler: None,
  }
}

///|
/// Returns an iterator over the registered route keys as `(method, path)` pairs.
pub fn Mocket::routes(self : Mocket) -> Iter[(String, String)] {
  self.route_keys.iter()
}

///|
/// Registers a route handler for the given HTTP method and path.
pub fn Mocket::on(
  self : Mocket,
  event : String,
  path : String,
  handler : HttpHandler,
) -> Unit {
  let path = self.base_path + path
  self.route_keys.push((event, path))

  // Cache routes by path type for faster lookup
  if !path.contains(":") && !path.contains("*") {
    // Static path: cache directly
    if self.static_routes.get(event) is Some(method_routes) {
      method_routes.set(path, handler)
    } else {
      let new_routes : Map[String, HttpHandler] = Map::new()
      new_routes.set(path, handler)
      self.static_routes.set(event, new_routes)
    }
    // Dynamic path: compile and insert into radix tree
  } else {
    let compiled = @router.CompiledRoute(path)
    self.dynamic_routes.insert(event, compiled, handler)
  }
}

///|
/// Registers a noraise GET handler. For most use cases, prefer `get()`.
pub fn Mocket::get_raw(
  self : Mocket,
  path : String,
  handler : HttpHandler,
) -> Unit {
  self.on("GET", path, handler)
}

///|
/// Registers a noraise POST handler.
pub fn Mocket::post_raw(
  self : Mocket,
  path : String,
  handler : HttpHandler,
) -> Unit {
  self.on("POST", path, handler)
}

///|
/// Registers a noraise PATCH handler.
pub fn Mocket::patch_raw(
  self : Mocket,
  path : String,
  handler : HttpHandler,
) -> Unit {
  self.on("PATCH", path, handler)
}

///|
/// Registers a noraise CONNECT handler.
pub fn Mocket::connect_raw(
  self : Mocket,
  path : String,
  handler : HttpHandler,
) -> Unit {
  self.on("CONNECT", path, handler)
}

///|
/// Registers a noraise PUT handler.
pub fn Mocket::put_raw(
  self : Mocket,
  path : String,
  handler : HttpHandler,
) -> Unit {
  self.on("PUT", path, handler)
}

///|
/// Registers a noraise DELETE handler.
pub fn Mocket::delete_raw(
  self : Mocket,
  path : String,
  handler : HttpHandler,
) -> Unit {
  self.on("DELETE", path, handler)
}

///|
/// Registers a noraise HEAD handler.
pub fn Mocket::head_raw(
  self : Mocket,
  path : String,
  handler : HttpHandler,
) -> Unit {
  self.on("HEAD", path, handler)
}

///|
/// Registers a noraise OPTIONS handler.
pub fn Mocket::options_raw(
  self : Mocket,
  path : String,
  handler : HttpHandler,
) -> Unit {
  self.on("OPTIONS", path, handler)
}

///|
/// Registers a noraise TRACE handler.
pub fn Mocket::trace_raw(
  self : Mocket,
  path : String,
  handler : HttpHandler,
) -> Unit {
  self.on("TRACE", path, handler)
}

///|
/// Registers a noraise handler that matches all HTTP methods.
pub fn Mocket::all_raw(
  self : Mocket,
  path : String,
  handler : HttpHandler,
) -> Unit {
  self.on("*", path, handler)
}

///|
/// Creates a route group with a shared base path prefix, merging its routes and middleware into the app.
pub fn Mocket::group(
  self : Mocket,
  base_path : String,
  configure : (Mocket) -> Unit,
) -> Unit {
  let group = Mocket(base_path=self.base_path + base_path)
  configure(group)
  // Merge route keys for introspection
  self.route_keys.append(group.route_keys)
  // Merge static route tables
  group.static_routes
  .iter()
  .each(i => {
    let http_method = i.0
    let group_routes = i.1
    match self.static_routes.get(http_method) {
      Some(existing_routes) =>
        group_routes.iter().each(route => existing_routes.set(route.0, route.1))
      None => self.static_routes.set(http_method, group_routes)
    }
  })
  // Merge dynamic routes (radix tree)
  self.dynamic_routes.merge(group.dynamic_routes)
  group.ws_static_routes.iter().each(i => self.ws_static_routes.set(i.0, i.1))
  self.ws_dynamic_routes.merge(group.ws_dynamic_routes)
  // Merge middlewares
  self.middlewares.append(group.middlewares)
  // Merge not_found_handler (group's handler takes precedence if set)
  if group.not_found_handler is Some(_) {
    self.not_found_handler = group.not_found_handler
  }
}

///|
/// Sets a custom handler for 404 Not Found responses.
pub fn Mocket::set_not_found_handler(
  self : Mocket,
  handler : HttpHandler,
) -> Unit {
  self.not_found_handler = Some(handler)
}

///|
/// Returns true if a custom not-found handler has been registered.
pub fn Mocket::has_not_found_handler(self : Mocket) -> Bool {
  self.not_found_handler is Some(_)
}

///|
/// Registers a WebSocket handler for the given path, matched regardless of HTTP method.
///
/// Dynamic patterns (`:param`, `*`, `**`) are inserted into the same radix
/// tree implementation used for HTTP routes, giving them consistent precedence:
/// static > param > wildcard > globstar. Re-registering the same path overrides
/// the previous handler.
pub fn Mocket::ws(
  self : Mocket,
  path : String,
  handler : WebSocketHandler,
) -> Unit {
  let path = self.base_path + path
  // Static path: direct map lookup
  if !path.contains(":") && !path.contains("*") {
    self.ws_static_routes.set(path, handler)
  } else {
    // Dynamic path: insert into radix tree (WS is a synthetic method key)
    let compiled = @router.CompiledRoute(path)
    self.ws_dynamic_routes.insert("WS", compiled, handler)
  }
}

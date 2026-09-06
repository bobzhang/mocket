///|
const ABSOLUTE_FORM = re"^[A-Za-z][A-Za-z0-9+.\-]*://[^/?#]*"

///|
const ORIGIN_FORM = re"^/[^?#]*"

///|
/// Extracts the path component from an HTTP request target.
///
/// Handles all request-target forms from RFC 7230 §5.3:
/// - origin-form: `/path?query` → returns `/path`
/// - absolute-form: `http://host/path?query` → returns `/path`
/// - authority-form: `host:port` (CONNECT only) → returns the target unchanged
/// - asterisk-form: `*` (OPTIONS only) → returns `*`
pub fn request_target_path(target : String) -> String {
  // Asterisk-form.
  if target =~ re"^\*$" {
    return "*"
  }

  // Origin-form.
  if target =~ (ORIGIN_FORM as path) {
    return normalize_path(path.to_owned())
  }

  // Absolute-form.
  //
  // Match and discard scheme + authority, leaving the remainder.
  if target =~ (ABSOLUTE_FORM, after=rest) {
    if rest =~ (ORIGIN_FORM as path) {
      return normalize_path(path.to_owned())
    }
    return "/"
  }

  // Authority-form, or an unrecognized/invalid target.
  target
}

///|
/// Normalizes a URL path by collapsing consecutive slashes into single slashes.
/// Preserves the leading slash if present.
pub fn normalize_path(path : String) -> String {
  if !path.contains("//") {
    return path
  }
  let buf = StringBuilder()
  let mut prev_slash = false
  for c in path {
    if c == '/' {
      if !prev_slash {
        buf.write_char('/')
      }
      prev_slash = true
    } else {
      buf.write_char(c)
      prev_slash = false
    }
  }
  buf.to_string()
}

///|
/// Extracts the query string from an HTTP request target, excluding the leading
/// `?` delimiter. Returns `None` if no query string is present.
pub fn request_target_query_string(request_target : String) -> String? {
  match request_target.find("?") {
    Some(query_start) => {
      let mut end = request_target.length()
      match request_target.find("#") {
        Some(fragment_start) if fragment_start > query_start =>
          end = fragment_start
        _ => ()
      }
      Some(request_target[query_start + 1:end].to_owned())
    }
    None => None
  }
}

///|
/// Returns `true` if the request path falls within the given scope path. The
/// root scope `"/"` matches all paths; otherwise the request path must equal or
/// be a sub-path of the scope (separated by `'/'`).
pub fn path_scope_matches(scope_path : String, request_path : String) -> Bool {
  if scope_path == "/" {
    true
  } else if !request_path.has_prefix(scope_path) {
    false
  } else if request_path.length() == scope_path.length() {
    true
  } else {
    request_path[scope_path.length()] == '/'
  }
}

// URI parser implementation following RFC 3986

///|
/// Represents the host component of a URI, which is either an IPv6 address
/// enclosed in brackets or a registered name (including IPv4 addresses).
pub enum Host {
  IPv6Address(StringView)
  RegName(StringView)
} derive(Eq, Debug)

///|
/// The authority component of a URI, comprising an optional userinfo, a host,
/// and an optional port number (e.g. `user:pass@example.com:8080`).
pub struct Authority {
  /// Userinfo component before `@` (e.g., `user:pass`), if present.
  mut userinfo : StringView?
  /// Host component: either a domain name (`RegName`) or IPv6 address.
  mut host : Host
  /// Port number, if explicitly specified in the URI.
  mut port : Int?
} derive(Eq, Debug)

///|
/// A parsed URI following RFC 3986, containing an optional scheme, authority,
/// path segments, query, and fragment.
pub struct Uri {
  /// URI scheme (e.g., `http`, `https`, `ftp`), if present.
  mut scheme : StringView?
  /// Authority component (`userinfo@host:port`), if present.
  mut authority : Authority?
  /// Path segments split by `/`. A leading `/` produces an empty first segment.
  path : Array[StringView]
  /// Query string after `?`, if present (without the `?`).
  mut query : StringView?
  /// Fragment after `#`, if present (without the `#`).
  mut fragment : StringView?

  fn new(source : StringView) -> Uri raise ParseError
} derive(Eq, Debug)

///|
/// Errors that can occur during URI parsing, indicating the specific component
/// that failed validation.
pub suberror ParseError {
  InvalidScheme(StringView)
  InvalidHeirPart(StringView)
  InvalidPercentEncoding(StringView)
  MissingColon
  MissingScheme
  InvalidSegment(StringView)
  InvalidSchemeOrSegment(StringView)
  Invalid(StringView)
}

///|
/// Returns the prefix of `self` up to (but not including) where `other` starts.
/// Both views must originate from the same underlying string, with `other`
/// being a suffix of `self`.
fn StringView::slice_before(
  self : StringView,
  other : StringView,
) -> StringView {
  self[:self.length() - other.length()]
}

// RFC 3986 Character Classification Functions

///|
fn is_alpha(c : Char) -> Bool {
  (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_hexdig(c : Char) -> Bool {
  is_digit(c) || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f')
}

///|
fn is_unreserved(c : Char) -> Bool {
  is_alpha(c) || is_digit(c) || c == '-' || c == '.' || c == '_' || c == '~'
}

///|
fn is_gen_delim(c : Char) -> Bool {
  c == ':' ||
  c == '/' ||
  c == '?' ||
  c == '#' ||
  c == '[' ||
  c == ']' ||
  c == '@'
}

///|
fn is_sub_delim(c : Char) -> Bool {
  c == '!' ||
  c == '$' ||
  c == '&' ||
  c == '\'' ||
  c == '(' ||
  c == ')' ||
  c == '*' ||
  c == '+' ||
  c == ',' ||
  c == ';' ||
  c == '='
}

///|
fn is_pchar(c : Char) -> Bool {
  is_unreserved(c) || is_sub_delim(c) || c == ':' || c == '@'
}

// RFC 3986 Parsing Functions

// URI-reference = scheme ":" "//" authority path-abempty [ "?" query ] [ "#" fragment ]
//               / scheme ":" "/" [ segment-nz *( "/" segment ) ] [ "?" query ] [ "#" fragment ]
//               / scheme ":" segment-nz *( "/" segment ) [ "?" query ] [ "#" fragment ]
//               / scheme ":" [ "?" query ] [ "#" fragment ]
//               / "//" authority path-abempty [ "?" query ] [ "#" fragment ]
//               / "/" [ segment-nz *( "/" segment ) ] [ "?" query ] [ "#" fragment ]
//               / segment-nz-nc *( "/" segment ) [ "?" query ] [ "#" fragment ]
//               / [ "?" query ] [ "#" fragment ]

///|
fn parse_scheme_or_segment_nz_nc(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  let segment = source
  for s = source {
    match s {
      [':', .. k] as s => {
        uri.scheme = Some(source.slice_before(s))
        return parse_hier_part_then_query(k, uri)
      }
      ['/', .. k] as s => {
        uri.path.push(segment.slice_before(s))
        return parse_path_abempty_then_query(k, uri)
      }
      ['?', .. k] as s => {
        uri.path.push(segment.slice_before(s))
        return parse_query_then_fragment(k, uri)
      }
      ['#', .. k] as s => {
        uri.path.push(segment.slice_before(s))
        // '#' introduces a fragment directly (no query present here).
        // Previously this incorrectly called parse_query_then_fragment,
        // causing the fragment to end up in uri.query.
        return parse_fragment(k, uri)
      }
      [b, .. k] if is_unreserved(b) || is_sub_delim(b) || b == '@' => continue k
      [] => {
        // EOF after a bare segment (e.g. "foo", ".", "..").
        // Push the accumulated segment and return.
        uri.path.push(segment)
        return s
      }
      _ => raise InvalidSchemeOrSegment(source)
    }
  }
}

///|
fn parse_uri_reference(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  match source {
    [.. "//", .. k] => {
      // relative-ref > relative-part > "//" authority path-abempty
      let k = parse_authority(k, uri)
      parse_path_abempty_then_query(k, uri)
    }
    ['/', .. k] =>
      // relative-ref > relative-part > "/" [ segment-nz *( "/" segment ) ] [ "?" query ] [ "#" fragment ]
      parse_path_abempty_then_query(k, uri)
    ['?', .. k] =>
      // relative-ref > relative-part > "?" query
      parse_query_then_fragment(k, uri)
    ['#', .. k] =>
      // relative-ref > relative-part > "#" fragment
      parse_fragment(k, uri)
    [..] as s => parse_scheme_or_segment_nz_nc(s, uri)
  }
}

///|
/// Parses a URI-reference from raw bytes following RFC 3986, returning a fully
/// populated `Uri` structure or raising a `ParseError` on invalid input.
fn Uri::new(source : StringView) -> Uri raise ParseError {
  let uri = Uri::{
    scheme: None,
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  let source = parse_uri_reference(source, uri)
  if !(source is []) {
    raise Invalid(source)
  }
  uri
}

///|
fn parse_scheme(source : StringView, uri : Uri) -> StringView raise ParseError {
  match source {
    [b, .. k] if is_alpha(b) =>
      for s = k {
        match s {
          [b, .. s] if is_alpha(b) ||
            is_digit(b) ||
            b == '+' ||
            b == '-' ||
            b == '.' => continue s
          [':', .. k] as s => {
            uri.scheme = Some(source.slice_before(s))
            return k
          }
          [_, ..] as s => raise InvalidScheme(s)
          [] => raise MissingColon
        }
      }
    [_, ..] as s => raise InvalidScheme(s)
    [] => raise MissingScheme
  }
}

///|
fn parse_percent_encoding(source : StringView) -> StringView raise ParseError {
  match source {
    [
      '0'..='9'
      | 'A'..='F'
      | 'a'..='f',
      '0'..='9'
      | 'A'..='F'
      | 'a'..='f',
      .. source,
    ] => source
    [..] => raise InvalidPercentEncoding(source)
  }
}

///|
fn parse_userinfo(
  source : StringView,
  authority : Authority,
) -> StringView raise ParseError {
  let start = source
  for s = source {
    match s {
      ['@', .. k] as s => {
        authority.userinfo = Some(start.slice_before(s))
        return k
      }
      ['%', .. k] => continue parse_percent_encoding(k)
      [b, .. k] if is_unreserved(b) || is_sub_delim(b) || b == ':' => continue k
      [_, ..] as s => raise InvalidHeirPart(s)
      [] as s => return s
    }
  }
}

///|
fn parse_reg_name(
  source : StringView,
  authority : Authority,
) -> StringView raise ParseError {
  for s = source {
    match s {
      ['%', .. k] => continue parse_percent_encoding(k)
      [b, .. k] if is_unreserved(b) || is_sub_delim(b) => continue k
      _ as s => {
        authority.host = RegName(source.slice_before(s))
        return s
      }
    }
  }
}

///|
fn parse_ipv6_address(
  source : StringView,
  authority : Authority,
) -> StringView raise ParseError {
  // Simplified IPv6 parsing - match until ']'
  for s = source {
    match s {
      [']', .. k] as s => {
        authority.host = IPv6Address(source.slice_before(s))
        return k
      }
      [b, .. s] if is_hexdig(b) || b == ':' || b == '.' => continue s
      _ as s => raise InvalidHeirPart(s)
    }
  }
}

///|
fn parse_host(
  source : StringView,
  authority : Authority,
) -> StringView raise ParseError {
  // Try IP literal first
  match source {
    ['[', .. k] => parse_ipv6_address(k, authority)
    _ =>
      // Try IPv4 address, fallback to reg-name
      parse_reg_name(source, authority)
  }
}

///|
fn parse_port(source : StringView, authority : Authority) -> StringView {
  match source {
    [':', .. k] => {
      let mut port_val = 0
      for s = k {
        match s {
          [d, .. s] if is_digit(d) => {
            port_val = port_val * 10 + (d.to_int() - '0')
            continue s
          }
          _ as s => {
            authority.port = Some(port_val)
            return s
          }
        }
      }
    }
    _ => source
  }
}

///|
fn parse_authority(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  let authority = Authority::{ userinfo: None, host: RegName(""), port: None }
  uri.authority = Some(authority)

  // Try to parse userinfo first
  let remaining = parse_userinfo(source, authority) catch {
    _ => source // No userinfo, continue with host
  }
  let remaining = parse_host(remaining, authority)
  parse_port(remaining, authority)
}

///|
fn parse_segment(
  source : StringView,
) -> (StringView, StringView) raise ParseError {
  let start = source
  for s = source {
    match s {
      ['%', .. k] => continue parse_percent_encoding(k)
      [b, .. k] if is_pchar(b) => continue k
      _ as s => return (s, start.slice_before(s))
    }
  }
}

///|
/// Continuation-based completion functions
fn parse_done(source : StringView, _uri : Uri) -> StringView {
  source
}

///|
fn parse_fragment(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  for s = source {
    match s {
      ['%', .. k] => continue parse_percent_encoding(k)
      [b, .. k] if is_pchar(b) || b == '/' || b == '?' => continue k
      [..] as s => {
        uri.fragment = Some(source.slice_before(s))
        return s
      }
    }
  }
}

///|
fn parse_query_then_fragment(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  let start = source
  for s = source {
    match s {
      ['#', .. k] as s => {
        uri.query = Some(start.slice_before(s))
        return parse_fragment(k, uri)
      }
      ['%', .. k] => continue parse_percent_encoding(k)
      [b, .. k] if is_pchar(b) || b == '/' || b == '?' => continue k
      [..] as s => {
        uri.query = Some(start.slice_before(s))
        return s
      }
    }
  }
}

///|
fn parse_path_abempty_then_query(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  for s = source {
    match s {
      ['%', .. k] => continue parse_percent_encoding(k)
      ['/', .. k] as s => {
        let segment = source.slice_before(s)
        if segment != "" {
          uri.path.push(segment)
        }
        return parse_path_abempty_then_query(k, uri)
      }
      ['?', .. k] as s => {
        let segment = source.slice_before(s)
        if segment != "" {
          uri.path.push(segment)
        }
        return parse_query_then_fragment(k, uri)
      }
      ['#', .. k] as s => {
        let segment = source.slice_before(s)
        if segment != "" {
          uri.path.push(segment)
        }
        return parse_fragment(k, uri)
      }
      [b, .. k] if is_pchar(b) => continue k
      [] as s => {
        let segment = source.slice_before(s)
        if segment != "" {
          uri.path.push(segment)
        }
        return s
      }
      [..] as s => raise InvalidSegment(s)
    }
  }
}

///|
fn parse_hier_part_then_query(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  match source {
    [.. "//", .. k] =>
      match parse_authority(k, uri) {
        ['/', .. k] => parse_path_abempty_then_query(k, uri)
        ['?', .. k] => parse_query_then_fragment(k, uri)
        ['#', ..] => parse_fragment(k, uri)
        [] => parse_done(k, uri)
        [..] as s => raise Invalid(s)
      }
    _ => parse_path_abempty_then_query(source, uri)
  }
}

///|
fn parse_absolute_uri(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  let remaining = parse_scheme(source, uri) // already consumes the ':'
  parse_hier_part_then_query_no_fragment(remaining, uri)
}

///|
fn parse_hier_part_then_query_no_fragment(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  match source {
    [.. "//", .. k] => {
      let remaining = parse_authority(k, uri)
      parse_path_abempty_then_query_no_fragment(remaining, uri)
    }
    _ => parse_path_abempty_then_query_no_fragment(source, uri)
  }
}

///|
fn parse_path_abempty_then_query_no_fragment(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  for s = source {
    match s {
      ['/', .. k] => {
        let (remaining, segment_val) = parse_segment(k)
        if segment_val != "" {
          uri.path.push(segment_val)
        }
        continue remaining
      }
      _ as s => return parse_query_no_fragment_or_done(s, uri)
    }
  }
}

///|
fn parse_query_no_fragment_or_done(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  match source {
    ['?', .. k] => parse_query_no_fragment_then_done(k, uri)
    _ => parse_done(source, uri)
  }
}

///|
fn parse_query_no_fragment_then_done(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  let start = source
  for s = source {
    match s {
      ['%', .. k] => continue parse_percent_encoding(k)
      [b, .. k] if is_pchar(b) || b == '/' || b == '?' => continue k
      _ as s => {
        uri.query = Some(start.slice_before(s))
        return parse_done(s, uri)
      }
    }
  }
}

///|
fn remove_dot_segments(path : Array[StringView]) -> Array[StringView] {
  let output = Array::new()
  for segment in path {
    if segment == "." {
      continue // Remove single dot segments
    } else if segment == ".." {
      if output.length() > 0 {
        output.pop() |> ignore() // Remove last segment and the .. segment
      }
      // If output is empty, ignore the .. segment
    } else {
      output.push(segment)
    }
  }
  output
}

///|
test "RFC 3986 URI Reference Parsing" {
  let uri = Uri::{
    scheme: None,
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  assert_eq(
    parse_uri_reference(
      "http://example.com/path/to/resource?query=parameter#fragment", uri,
    ),
    "",
  )
  debug_inspect(
    uri,
    content=(
      #|{
      #|  scheme: Some(<StringView: "http">),
      #|  authority: Some(
      #|    {
      #|      userinfo: None,
      #|      host: RegName(<StringView: "example.com">),
      #|      port: None,
      #|    },
      #|  ),
      #|  path: [<StringView: "path">, <StringView: "to">, <StringView: "resource">],
      #|  query: Some(<StringView: "query=parameter">),
      #|  fragment: Some(<StringView: "fragment">),
      #|}
    ),
  )
  // assert_eq(uri.scheme, Some("http"))
  // assert_eq(
  //   uri.authority,
  //   Some({ userinfo: None, host: RegName("example.com"), port: None }),
  // )
  // assert_eq(uri.path, ["path", "to", "resource"])
  // assert_eq(uri.query, Some("query=parameter"))
  // assert_eq(uri.fragment, Some("fragment"))
}

///|
test "RFC 3986 Authority with Userinfo and Port" {
  let uri = Uri::{
    scheme: None,
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  assert_eq(
    parse_uri_reference("ftp://user:pass@ftp.example.com:21/path", uri),
    "",
  )
  debug_inspect(
    uri,
    content=(
      #|{
      #|  scheme: Some(<StringView: "ftp">),
      #|  authority: Some(
      #|    {
      #|      userinfo: Some(<StringView: "user:pass">),
      #|      host: RegName(<StringView: "ftp.example.com">),
      #|      port: Some(21),
      #|    },
      #|  ),
      #|  path: [<StringView: "path">],
      #|  query: None,
      #|  fragment: None,
      #|}
    ),
  )
  // assert_eq(uri.scheme, Some("ftp"))
  // assert_eq(
  //   uri.authority,
  //   Some({
  //     userinfo: Some("user:pass"),
  //     host: RegName("ftp.example.com"),
  //     port: Some(21),
  //   }),
  // )
  // assert_eq(uri.path, ["path"])
}

///|
test "RFC 3986 IPv6 Literal" {
  let uri = Uri::{
    scheme: None,
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  assert_eq(parse_uri_reference("http://[2001:db8::1]:8080/", uri), "")
  debug_inspect(
    uri,
    content=(
      #|{
      #|  scheme: Some(<StringView: "http">),
      #|  authority: Some(
      #|    {
      #|      userinfo: None,
      #|      host: IPv6Address(<StringView: "2001:db8::1">),
      #|      port: Some(8080),
      #|    },
      #|  ),
      #|  path: [],
      #|  query: None,
      #|  fragment: None,
      #|}
    ),
  )
  // assert_eq(uri.scheme, Some("http"))
  // assert_eq(
  //   uri.authority,
  //   Some({ userinfo: None, host: IPv6Address("2001:db8::1"), port: Some(8080) }),
  // )
  // assert_eq(uri.path, [])
}

///|
test "RFC 3986 Percent Encoding Preservation" {
  let uri = Uri::{
    scheme: None,
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  assert_eq(parse_uri_reference("http://example.com/hello%20world", uri), "")
  assert_eq(uri.scheme, Some("http"))
  assert_eq(uri.path, ["hello%20world"]) // preserved, not decoded
}

///|
test "RFC 3986 Relative Reference" {
  let uri = Uri::{
    scheme: None,
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  assert_eq(parse_uri_reference("../path/file.txt", uri), "")
  debug_inspect(
    uri,
    content=(
      #|{
      #|  scheme: None,
      #|  authority: None,
      #|  path: [<StringView: "..">, <StringView: "path">, <StringView: "file.txt">],
      #|  query: None,
      #|  fragment: None,
      #|}
    ),
  )
  // assert_eq(uri.scheme, None)
  // assert_eq(uri.authority, None)
  // assert_eq(uri.path, ["..", "path", "file.txt"])
}

///|
test "RFC 3986 Absolute Path" {
  let uri = Uri::{
    scheme: None,
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  assert_eq(parse_uri_reference("/absolute/path", uri), "")
  debug_inspect(
    uri,
    content=(
      #|{
      #|  scheme: None,
      #|  authority: None,
      #|  path: [<StringView: "absolute">, <StringView: "path">],
      #|  query: None,
      #|  fragment: None,
      #|}
    ),
  )
  // assert_eq(uri.scheme, None)
  // assert_eq(uri.authority, None)
  // assert_eq(uri.path, ["absolute", "path"])
}

///|
test "RFC 3986 Query Only" {
  let uri = Uri::{
    scheme: None,
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  assert_eq(parse_uri_reference("?key=value&foo=bar", uri), "")
  debug_inspect(
    uri,
    content=(
      #|{
      #|  scheme: None,
      #|  authority: None,
      #|  path: [],
      #|  query: Some(<StringView: "key=value&foo=bar">),
      #|  fragment: None,
      #|}
    ),
  )
  // assert_eq(uri.scheme, None)
  // assert_eq(uri.authority, None)
  // assert_eq(uri.path, [])
  // assert_eq(uri.query, Some("key=value&foo=bar"))
}

///|
test "RFC 3986 Fragment Only" {
  let uri = Uri::{
    scheme: None,
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  assert_eq(parse_uri_reference("#section1", uri), "")
  debug_inspect(
    uri,
    content=(
      #|{
      #|  scheme: None,
      #|  authority: None,
      #|  path: [],
      #|  query: None,
      #|  fragment: Some(<StringView: "section1">),
      #|}
    ),
  )
  // assert_eq(uri.scheme, None)
  // assert_eq(uri.authority, None)
  // assert_eq(uri.path, [])
  // assert_eq(uri.fragment, Some("section1"))
}

///|
test "RFC 3986 Character Classification" {
  // Test unreserved characters
  assert_eq(is_unreserved('A'), true)
  assert_eq(is_unreserved('z'), true)
  assert_eq(is_unreserved('0'), true)
  assert_eq(is_unreserved('-'), true)
  assert_eq(is_unreserved('.'), true)
  assert_eq(is_unreserved('_'), true)
  assert_eq(is_unreserved('~'), true)
  assert_eq(is_unreserved('!'), false)

  // Test gen-delims
  assert_eq(is_gen_delim(':'), true)
  assert_eq(is_gen_delim('/'), true)
  assert_eq(is_gen_delim('?'), true)
  assert_eq(is_gen_delim('#'), true)
  assert_eq(is_gen_delim('['), true)
  assert_eq(is_gen_delim(']'), true)
  assert_eq(is_gen_delim('@'), true)

  // Test sub-delims
  assert_eq(is_sub_delim('!'), true)
  assert_eq(is_sub_delim('$'), true)
  assert_eq(is_sub_delim('&'), true)
  assert_eq(is_sub_delim('\''), true)
  assert_eq(is_sub_delim('('), true)
  assert_eq(is_sub_delim(')'), true)
  assert_eq(is_sub_delim('*'), true)
  assert_eq(is_sub_delim('+'), true)
  assert_eq(is_sub_delim(','), true)
  assert_eq(is_sub_delim(';'), true)
  assert_eq(is_sub_delim('='), true)
}

///|
test "RFC 3986 Dot Segment Removal" {
  let path1 : Array[StringView] = ["a", "b", "c", ".", "..", "..", "g"]
  let result1 = remove_dot_segments(path1)
  assert_eq(result1, ["a", "g"])
  let path2 : Array[StringView] = ["..", "..", "a", "b"]
  let result2 = remove_dot_segments(path2)
  assert_eq(result2, ["a", "b"])
  let path3 : Array[StringView] = [".", "a", ".", "b", "."]
  let result3 = remove_dot_segments(path3)
  assert_eq(result3, ["a", "b"])
}

///|
test "parse_percent_encoding accepts only hex digits" {
  // Valid hex digits
  let ok1 : Result[StringView, ParseError] = try? parse_percent_encoding(
    "20 rest",
  )
  assert_true(ok1 is Ok(_))
  let ok2 : Result[StringView, ParseError] = try? parse_percent_encoding(
    "FF end",
  )
  assert_true(ok2 is Ok(_))
  let ok3 : Result[StringView, ParseError] = try? parse_percent_encoding(
    "ab end",
  )
  assert_true(ok3 is Ok(_))
  // Invalid: non-hex letters
  let bad1 : Result[StringView, ParseError] = try? parse_percent_encoding(
    "GG end",
  )
  assert_true(bad1 is Err(_))
  let bad2 : Result[StringView, ParseError] = try? parse_percent_encoding(
    "xz end",
  )
  assert_true(bad2 is Err(_))
  let bad3 : Result[StringView, ParseError] = try? parse_percent_encoding(
    "ZZ end",
  )
  assert_true(bad3 is Err(_))
}

///|
test "parse rejects URI with invalid percent encoding" {
  let bad : Result[Uri, ParseError] = try? Uri("http://example.com/path%GG")
  assert_true(bad is Err(_))
}

///|
test "parse accepts percent-encoded query" {
  // Regression test for percent-encoding bug in parse_query_then_fragment
  let ok : Result[Uri, ParseError] = try? Uri("http://example.com/?q=a%20b")
  assert_true(ok is Ok(_))
}

///|
test "parse accepts percent-encoded fragment" {
  // Regression test for percent-encoding bug in parse_fragment
  let ok : Result[Uri, ParseError] = try? Uri("http://example.com/#sec%20tion")
  assert_true(ok is Ok(_))
}

///|
test "parse accepts percent-encoded host" {
  // Regression test for percent-encoding bug in parse_reg_name
  let ok : Result[Uri, ParseError] = try? Uri("http://ex%C3%A4mple.com/")
  assert_true(ok is Ok(_))
}

///|
test "parse accepts bare relative reference" {
  // Regression test: previously "foo" raised InvalidSchemeOrSegment at EOF
  let ok1 : Result[Uri, ParseError] = try? Uri("foo")
  assert_true(ok1 is Ok(_))
  let ok2 : Result[Uri, ParseError] = try? Uri(".")
  assert_true(ok2 is Ok(_))
  let ok3 : Result[Uri, ParseError] = try? Uri("..")
  assert_true(ok3 is Ok(_))
}

///|
test "parse relative ref with fragment puts value in fragment, not query" {
  // Regression test: "foo#bar" previously put "bar" in query field
  let uri = Uri("foo#bar")
  assert_eq(uri.query, None)
  assert_eq(uri.fragment, Some("bar"))
}

///|
test "RFC 3986 Absolute URI Parsing" {
  let uri = Uri::{
    scheme: None,
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  assert_eq(
    parse_absolute_uri(
      "http://example.com/path/to/resource?query=parameter", uri,
    ),
    "",
  )
  debug_inspect(
    uri,
    content=(
      #|{
      #|  scheme: Some(<StringView: "http">),
      #|  authority: Some(
      #|    {
      #|      userinfo: None,
      #|      host: RegName(<StringView: "example.com">),
      #|      port: None,
      #|    },
      #|  ),
      #|  path: [<StringView: "path">, <StringView: "to">, <StringView: "resource">],
      #|  query: Some(<StringView: "query=parameter">),
      #|  fragment: None,
      #|}
    ),
  )
  // assert_eq(uri.scheme, Some("http"))
  // assert_eq(
  //   uri.authority,
  //   Some({ userinfo: None, host: RegName("example.com"), port: None }),
  // )
  // assert_eq(uri.path, ["path", "to", "resource"])
  // assert_eq(uri.query, Some("query=parameter"))
  // assert_eq(uri.fragment, None)
}

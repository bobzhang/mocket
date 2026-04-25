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

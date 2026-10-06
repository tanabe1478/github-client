///|
/// User settings. The file is plain `key = value` lines with comments so
/// people and AI tools can edit it; the app reloads it when it changes.
pub(all) struct Settings {
  /// Mentioned also lists merged pull requests.
  include_merged_mentions : Bool
  /// Mentioned also lists issues and pull requests closed without merging.
  include_closed_mentions : Bool
  /// How many days back review comments are read for mentions, and how
  /// recently a merged or closed item must have been updated to be listed.
  mention_days : Int
} derive(Eq, Debug)

///|
pub fn default_settings() -> Settings {
  {
    include_merged_mentions: false,
    include_closed_mentions: false,
    mention_days: 30,
  }
}

///|
pub const MIN_MENTION_DAYS : Int = 1

///|
pub const MAX_MENTION_DAYS : Int = 365

///|
fn bool_text(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
pub fn encode(settings : Settings) -> String {
  [
    "# MoonBit GitHub Client settings.",
    "# The app reloads this file within a few seconds of a change, and ghclient reads it on every command.",
    "# Lines starting with # are comments.",
    "",
    "# Mentioned in For you lists open items. These also list merged pull requests, and issues and pull requests closed without merging, updated in the last mentions.days days (true or false).",
    "mentions.include_merged = \{bool_text(settings.include_merged_mentions)}",
    "mentions.include_closed = \{bool_text(settings.include_closed_mentions)}",
    "",
    "# How many days back review comments are read for mentions, and how recently a merged or closed item must have been updated (\{MIN_MENTION_DAYS} to \{MAX_MENTION_DAYS}).",
    "mentions.days = \{settings.mention_days}",
  ].join("\n") +
  "\n"
}

///|
fn parse_bool(value : String, key : String, line : Int) -> Result[Bool, String] {
  match value {
    "true" => Ok(true)
    "false" => Ok(false)
    _ => Err("\{key} at line \{line} must be true or false")
  }
}

///|
fn parse_days(value : String, key : String, line : Int) -> Result[Int, String] {
  let error = "\{key} at line \{line} must be a whole number from \{MIN_MENTION_DAYS} to \{MAX_MENTION_DAYS}"
  guard value != "" && value.length() <= 3 else { return Err(error) }
  let mut days = 0
  for character in value {
    guard character >= '0' && character <= '9' else { return Err(error) }
    days = days * 10 + (character.to_int() - '0'.to_int())
  }
  guard days >= MIN_MENTION_DAYS && days <= MAX_MENTION_DAYS else {
    return Err(error)
  }
  Ok(days)
}

///|
pub fn decode(source : String) -> Result[Settings, String] {
  let mut settings = default_settings()
  let lines = source.replace_all(old="\r\n", new="\n").split("\n").to_array()
  for index, raw in lines {
    let line = raw.trim()
    let number = index + 1
    if line == "" || line.has_prefix("#") {
      continue
    }
    guard line.find("=") is Some(separator) else {
      return Err("line \{number} is not key = value")
    }
    let key = line[:separator].trim().to_owned()
    let value = line[separator + 1:].trim().to_owned()
    match key {
      "mentions.include_merged" =>
        match parse_bool(value, key, number) {
          Ok(flag) => settings = { ..settings, include_merged_mentions: flag, }
          Err(error) => return Err(error)
        }
      "mentions.include_closed" =>
        match parse_bool(value, key, number) {
          Ok(flag) => settings = { ..settings, include_closed_mentions: flag, }
          Err(error) => return Err(error)
        }
      "mentions.days" =>
        match parse_days(value, key, number) {
          Ok(days) => settings = { ..settings, mention_days: days, }
          Err(error) => return Err(error)
        }
      _ => return Err("unknown setting \"\{key}\" at line \{number}")
    }
  }
  Ok(settings)
}

///|
pub fn load(path : String) -> Result[Settings, String] {
  if !@fs.path_exists(path) {
    return Ok(default_settings())
  }
  let source = @fs.read_file_to_string(path, encoding="utf8") catch {
    _ => return Err("failed to read settings")
  }
  decode(source)
}

///|
pub fn save(path : String, settings : Settings) -> Result[Unit, String] {
  @fs.write_string_to_file(path, encode(settings), encoding="utf8") catch {
    _ => return Err("failed to write settings")
  }
  Ok(())
}

///|
pub fn default_path() -> Result[String, String] {
  @app_paths.data_file("settings.txt")
}

///|
pub fn load_default() -> Result[Settings, String] {
  match default_path() {
    Ok(path) => load(path)
    Err(error) => Err(error)
  }
}

///|
pub fn save_default(settings : Settings) -> Result[Unit, String] {
  guard @app_paths.ensure_data_directory() is Ok(_) else {
    return Err("application data directory is unavailable")
  }
  guard default_path() is Ok(path) else {
    return Err("settings path is unavailable")
  }
  save(path, settings)
}

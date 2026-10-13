///|
/// Version 2: one repository per line, then tab-separated kinds and the
/// release notification, for example
/// `pnpm/pnpm<TAB>releases<TAB>releases=major-minor`. Repositories without
/// options get the defaults.
pub fn encode(
  repositories : Array[@domain.RepositoryRef],
  options : Map[String, @domain.WatchOptions],
) -> String {
  let lines = ["v2"]
  for repository in repositories {
    let key = repository.key()
    let entry = @domain.watch_options_for(options, key)
    lines.push(
      "\{key}\t\{entry.kinds_text()}\treleases=\{entry.release_notify.name()}",
    )
  }
  lines.join("\n") + "\n"
}

///|
/// Repositories and their options. Version 1 files, which list repositories
/// only, give every repository the default options.
pub fn decode_entries(
  source : String,
) -> Result[
  (Array[@domain.RepositoryRef], Map[String, @domain.WatchOptions]),
  String,
] {
  let lines = source.replace_all(old="\r\n", new="\n").split("\n").to_array()
  guard lines.length() > 0 && (lines[0] == "v1" || lines[0] == "v2") else {
    return Err("unsupported repository store format")
  }
  let repositories : Array[@domain.RepositoryRef] = []
  let options : Map[String, @domain.WatchOptions] = Map([])
  for index = 1; index < lines.length(); index = index + 1 {
    let line = lines[index].trim_end()
    if line.trim() == "" {
      continue
    }
    let fields = line
      .split("\t")
      .to_array()
      .map(field => field.trim().to_owned())
    let parts = fields[0].split("/").to_array()
    guard parts.length() == 2 && parts[0] != "" && parts[1] != "" else {
      return Err("invalid repository at line \{index + 1}")
    }
    let repository = @domain.RepositoryRef::new(
      parts[0].to_owned(),
      parts[1].to_owned(),
    )
    let mut entry = @domain.WatchOptions::default()
    if fields.length() >= 2 {
      entry = match entry.with_kinds(fields[1]) {
        Ok(next) => next
        Err(error) => return Err("\{error} at line \{index + 1}")
      }
    }
    for field in fields[2:] {
      guard field.has_prefix("releases=") else { continue }
      match
        @domain.ReleaseNotify::parse(field["releases=".length():].to_owned()) {
        Some(level) => entry = { ..entry, release_notify: level, }
        None => return Err("invalid release notification at line \{index + 1}")
      }
    }
    repositories.push(repository)
    options.set(repository.key(), entry)
  }
  Ok((repositories, options))
}

///|
pub fn decode(source : String) -> Result[Array[@domain.RepositoryRef], String] {
  match decode_entries(source) {
    Ok((repositories, _)) => Ok(repositories)
    Err(error) => Err(error)
  }
}

///|
pub fn load_entries(
  path : String,
) -> Result[
  (Array[@domain.RepositoryRef], Map[String, @domain.WatchOptions]),
  String,
] {
  if !@fs.path_exists(path) {
    return Ok(([], Map([])))
  }
  let source = @fs.read_file_to_string(path, encoding="utf8") catch {
    _ => return Err("failed to read repository store")
  }
  decode_entries(source)
}

///|
pub fn load(path : String) -> Result[Array[@domain.RepositoryRef], String] {
  match load_entries(path) {
    Ok((repositories, _)) => Ok(repositories)
    Err(error) => Err(error)
  }
}

///|
pub fn save(
  path : String,
  repositories : Array[@domain.RepositoryRef],
  options : Map[String, @domain.WatchOptions],
) -> Result[Unit, String] {
  @fs.write_string_to_file(path, encode(repositories, options), encoding="utf8") catch {
    _ => return Err("failed to write repository store")
  }
  Ok(())
}

///|
fn default_path() -> Result[String, String] {
  @app_paths.data_file("repositories.txt")
}

///|
pub fn load_default() -> Result[Array[@domain.RepositoryRef], String] {
  match default_path() {
    Ok(path) => load(path)
    Err(error) => Err(error)
  }
}

///|
pub fn load_default_entries() -> Result[
  (Array[@domain.RepositoryRef], Map[String, @domain.WatchOptions]),
  String,
] {
  match default_path() {
    Ok(path) => load_entries(path)
    Err(error) => Err(error)
  }
}

///|
pub fn save_default(
  repositories : Array[@domain.RepositoryRef],
  options : Map[String, @domain.WatchOptions],
) -> Result[Unit, String] {
  guard @app_paths.ensure_data_directory() is Ok(_) else {
    return Err("application data directory is unavailable")
  }
  guard default_path() is Ok(path) else {
    return Err("repository store path is unavailable")
  }
  save(path, repositories, options)
}

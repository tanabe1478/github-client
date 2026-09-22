///|
pub fn encode(repositories : Array[@domain.RepositoryRef]) -> String {
  let lines = ["v1"]
  for repository in repositories {
    lines.push(repository.key())
  }
  lines.join("\n") + "\n"
}

///|
pub fn decode(source : String) -> Result[Array[@domain.RepositoryRef], String] {
  let lines = source.replace_all(old="\r\n", new="\n").split("\n").to_array()
  guard lines.length() > 0 && lines[0] == "v1" else {
    return Err("unsupported repository store format")
  }
  let repositories : Array[@domain.RepositoryRef] = []
  for index = 1; index < lines.length(); index = index + 1 {
    let line = lines[index].trim()
    if line == "" {
      continue
    }
    let parts = line.split("/").to_array()
    guard parts.length() == 2 && parts[0] != "" && parts[1] != "" else {
      return Err("invalid repository at line \{index + 1}")
    }
    repositories.push(
      @domain.RepositoryRef::new(parts[0].to_owned(), parts[1].to_owned()),
    )
  }
  Ok(repositories)
}

///|
pub fn load(path : String) -> Result[Array[@domain.RepositoryRef], String] {
  if !@fs.path_exists(path) {
    return Ok([])
  }
  let source = @fs.read_file_to_string(path, encoding="utf8") catch {
    _ => return Err("failed to read repository store")
  }
  decode(source)
}

///|
pub fn save(
  path : String,
  repositories : Array[@domain.RepositoryRef],
) -> Result[Unit, String] {
  @fs.write_string_to_file(path, encode(repositories), encoding="utf8") catch {
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
pub fn save_default(
  repositories : Array[@domain.RepositoryRef],
) -> Result[Unit, String] {
  guard @app_paths.ensure_data_directory() is Ok(_) else {
    return Err("application data directory is unavailable")
  }
  guard default_path() is Ok(path) else {
    return Err("repository store path is unavailable")
  }
  save(path, repositories)
}

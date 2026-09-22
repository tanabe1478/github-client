///|
pub fn encode(markers : Array[@domain.ReadMarker]) -> String {
  let lines = ["v1"]
  for marker in markers {
    lines.push("\{marker.read_at()}\t\{marker.url()}")
  }
  lines.join("\n") + "\n"
}

///|
pub fn decode(source : String) -> Result[Array[@domain.ReadMarker], String] {
  let lines = source.replace_all(old="\r\n", new="\n").split("\n").to_array()
  guard lines.length() > 0 && lines[0] == "v1" else {
    return Err("unsupported read state store format")
  }
  let markers : Array[@domain.ReadMarker] = []
  for index = 1; index < lines.length(); index = index + 1 {
    let line = lines[index]
    if line.trim() == "" {
      continue
    }
    let parts = line.split("\t").to_array()
    guard parts.length() == 2 && parts[0] != "" && parts[1] != "" else {
      return Err("invalid read marker at line \{index + 1}")
    }
    markers.push(
      @domain.ReadMarker::new(parts[1].to_owned(), parts[0].to_owned()),
    )
  }
  Ok(markers)
}

///|
pub fn load(path : String) -> Result[Array[@domain.ReadMarker], String] {
  if !@fs.path_exists(path) {
    return Ok([])
  }
  let source = @fs.read_file_to_string(path, encoding="utf8") catch {
    _ => return Err("failed to read activity read state")
  }
  decode(source)
}

///|
pub fn save(
  path : String,
  markers : Array[@domain.ReadMarker],
) -> Result[Unit, String] {
  @fs.write_string_to_file(path, encode(markers), encoding="utf8") catch {
    _ => return Err("failed to write activity read state")
  }
  Ok(())
}

///|
fn default_path() -> Result[String, String] {
  @app_paths.data_file("read-state.txt")
}

///|
pub fn load_default() -> Result[Array[@domain.ReadMarker], String] {
  match default_path() {
    Ok(path) => load(path)
    Err(error) => Err(error)
  }
}

///|
pub fn save_default(
  markers : Array[@domain.ReadMarker],
) -> Result[Unit, String] {
  guard @app_paths.ensure_data_directory() is Ok(_) else {
    return Err("application data directory is unavailable")
  }
  guard default_path() is Ok(path) else {
    return Err("read state store path is unavailable")
  }
  save(path, markers)
}

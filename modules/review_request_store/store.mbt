///|
/// Pull request URLs that once requested the viewer's review, one per line
/// after a version header. They stay until the viewer reviews or the pull
/// request closes, even if GitHub removes a team's request.
pub fn encode(urls : Array[String]) -> String {
  let lines = ["v1"]
  lines.append(urls)
  lines.join("\n") + "\n"
}

///|
pub fn decode(source : String) -> Result[Array[String], String] {
  let lines = source
    .replace_all(old="\r\n", new="\n")
    .split("\n")
    .to_array()
    .map(line => line.trim().to_owned())
    .filter(line => line != "")
  guard lines.length() > 0 else { return Ok([]) }
  guard lines[0] == "v1" else {
    return Err("unsupported review request store version")
  }
  let urls : Array[String] = []
  for line in lines[1:] {
    if !urls.contains(line) {
      urls.push(line)
    }
  }
  Ok(urls)
}

///|
pub fn load(path : String) -> Result[Array[String], String] {
  if !@fs.path_exists(path) {
    return Ok([])
  }
  let source = @fs.read_file_to_string(path, encoding="utf8") catch {
    _ => return Err("failed to read review request store")
  }
  decode(source)
}

///|
pub fn save(path : String, urls : Array[String]) -> Result[Unit, String] {
  @fs.write_string_to_file(path, encode(urls), encoding="utf8") catch {
    _ => return Err("failed to write review request store")
  }
  Ok(())
}

///|
fn default_path() -> Result[String, String] {
  @app_paths.data_file("review-requests.txt")
}

///|
pub fn load_default() -> Result[Array[String], String] {
  match default_path() {
    Ok(path) => load(path)
    Err(error) => Err(error)
  }
}

///|
pub fn save_default(urls : Array[String]) -> Result[Unit, String] {
  guard @app_paths.ensure_data_directory() is Ok(_) else {
    return Err("application data directory is unavailable")
  }
  guard default_path() is Ok(path) else {
    return Err("review request store path is unavailable")
  }
  save(path, urls)
}

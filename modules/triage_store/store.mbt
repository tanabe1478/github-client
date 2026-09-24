///|
pub struct TriageState {
  saved : Array[String]
  muted : Array[String]
}

///|
pub fn TriageState::new(
  saved : Array[String],
  muted : Array[String],
) -> TriageState {
  { saved, muted, }
}

///|
pub fn encode(state : TriageState) -> String {
  let lines = ["v1"]
  for url in state.saved {
    lines.push("saved\t\{url}")
  }
  for url in state.muted {
    lines.push("muted\t\{url}")
  }
  lines.join("\n") + "\n"
}

///|
pub fn decode(source : String) -> Result[TriageState, String] {
  let lines = source.replace_all(old="\r\n", new="\n").split("\n").to_array()
  guard lines.length() > 0 && lines[0] == "v1" else {
    return Err("unsupported triage store format")
  }
  let saved : Array[String] = []
  let muted : Array[String] = []
  for index = 1; index < lines.length(); index = index + 1 {
    let line = lines[index]
    if line.trim() == "" {
      continue
    }
    let parts = line.split("\t").to_array()
    guard parts.length() == 2 && parts[1] != "" else {
      return Err("invalid triage entry at line \{index + 1}")
    }
    match parts[0] {
      "saved" => saved.push(parts[1].to_owned())
      "muted" => muted.push(parts[1].to_owned())
      _ => return Err("unknown triage state at line \{index + 1}")
    }
  }
  Ok({ saved, muted, })
}

///|
pub fn load(path : String) -> Result[TriageState, String] {
  if !@fs.path_exists(path) {
    return Ok({ saved: [], muted: [], })
  }
  let source = @fs.read_file_to_string(path, encoding="utf8") catch {
    _ => return Err("failed to read triage state")
  }
  decode(source)
}

///|
pub fn save(path : String, state : TriageState) -> Result[Unit, String] {
  @fs.write_string_to_file(path, encode(state), encoding="utf8") catch {
    _ => return Err("failed to write triage state")
  }
  Ok(())
}

///|
fn default_path() -> Result[String, String] {
  @app_paths.data_file("triage.txt")
}

///|
pub fn load_default() -> Result[TriageState, String] {
  match default_path() {
    Ok(path) => load(path)
    Err(error) => Err(error)
  }
}

///|
pub fn save_default(state : TriageState) -> Result[Unit, String] {
  guard @app_paths.ensure_data_directory() is Ok(_) else {
    return Err("application data directory is unavailable")
  }
  guard default_path() is Ok(path) else {
    return Err("triage store path is unavailable")
  }
  save(path, state)
}

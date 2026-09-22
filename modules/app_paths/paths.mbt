///|
pub fn data_directory() -> Result[String, String] {
  match @env.get_env_var("LOCALAPPDATA") {
    Some(root) => Ok(root + "\\MoonBitGitHubClient")
    None =>
      match @env.get_env_var("HOME") {
        Some(home) => Ok(home + "/.config/moonbit-github-client")
        None => Err("LOCALAPPDATA and HOME are unavailable")
      }
  }
}

///|
pub fn data_file(name : String) -> Result[String, String] {
  guard data_directory() is Ok(directory) else {
    return Err("application data directory is unavailable")
  }
  let separator = if directory.contains("\\") { "\\" } else { "/" }
  Ok(directory + separator + name)
}

///|
pub fn ensure_data_directory() -> Result[String, String] {
  guard data_directory() is Ok(directory) else {
    return Err("application data directory is unavailable")
  }
  if !@fs.path_exists(directory) {
    @fs.create_dir(directory) catch {
      _ => return Err("failed to create application data directory")
    }
  }
  Ok(directory)
}

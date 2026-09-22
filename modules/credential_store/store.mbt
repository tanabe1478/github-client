///|
fn token_path() -> Result[String, String] {
  @app_paths.data_file("github-token.enc")
}

///|
pub fn is_available() -> Bool {
  @safe_storage.is_available()
}

///|
pub fn has_saved_token() -> Bool {
  match token_path() {
    Ok(path) => @fs.path_exists(path)
    Err(_) => false
  }
}

///|
pub fn save_token(token : String) -> Result[Unit, String] {
  let normalized = token.trim()
  if normalized == "" {
    return Err("token must not be empty")
  }
  if !@safe_storage.is_available() {
    return Err("OS-backed safe storage is unavailable")
  }
  guard @safe_storage.encrypt_string(normalized.to_owned()) is Ok(encrypted) else {
    return Err("token encryption failed")
  }
  guard @app_paths.ensure_data_directory() is Ok(_) else {
    return Err("application data directory is unavailable")
  }
  guard token_path() is Ok(path) else {
    return Err("credential path is unavailable")
  }
  @fs.write_string_to_file(path, encrypted, encoding="utf8") catch {
    _ => return Err("failed to write encrypted token")
  }
  Ok(())
}

///|
pub fn load_token() -> Result[String?, String] {
  guard token_path() is Ok(path) else {
    return Err("credential path is unavailable")
  }
  if !@fs.path_exists(path) {
    return Ok(None)
  }
  let encrypted = @fs.read_file_to_string(path, encoding="utf8") catch {
    _ => return Err("failed to read encrypted token")
  }
  match @safe_storage.decrypt_string(encrypted) {
    Ok(token) => Ok(Some(token))
    Err(_) => Err("token decryption failed")
  }
}

///|
pub fn delete_token() -> Result[Unit, String] {
  guard token_path() is Ok(path) else {
    return Err("credential path is unavailable")
  }
  if @fs.path_exists(path) {
    @fs.remove_file(path) catch {
      _ => return Err("failed to delete encrypted token")
    }
  }
  Ok(())
}

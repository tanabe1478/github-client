///|
const DEFAULT_SCOPE = "default"

///|
pub fn normalize_scope(raw : String) -> Result[String, String] {
  let lowered = StringBuilder()
  for character in raw.trim() {
    if character >= 'A' && character <= 'Z' {
      lowered.write_char((character.to_int() + 32).unsafe_to_char())
    } else {
      lowered.write_char(character)
    }
  }
  let scope = lowered.to_string()
  if scope == "" {
    return Ok(DEFAULT_SCOPE)
  }
  for character in scope {
    let valid = (character >= 'a' && character <= 'z') ||
      (character >= '0' && character <= '9') ||
      character == '-'
    if !valid {
      return Err("scope may only contain letters, digits, and hyphens")
    }
  }
  Ok(scope)
}

///|
fn token_path_for(scope : String) -> Result[String, String] {
  if scope == DEFAULT_SCOPE {
    @app_paths.data_file("github-token.enc")
  } else {
    @app_paths.data_file("github-token.\{scope}.enc")
  }
}

///|
fn login_path_for(scope : String) -> Result[String, String] {
  if scope == DEFAULT_SCOPE {
    @app_paths.data_file("github-login.txt")
  } else {
    @app_paths.data_file("github-login.\{scope}.txt")
  }
}

///|
pub fn is_available() -> Bool {
  @safe_storage.is_available()
}

///|
pub fn has_saved_token() -> Bool {
  !list_scopes().is_empty()
}

///|
pub fn list_scopes() -> Array[String] {
  guard @app_paths.data_directory() is Ok(directory) else { return [] }
  let entries = @fs.read_dir(directory) catch { _ => return [] }
  let scopes : Array[String] = []
  for entry in entries {
    if entry == "github-token.enc" {
      scopes.push(DEFAULT_SCOPE)
    } else if entry.has_prefix("github-token.") && entry.has_suffix(".enc") {
      scopes.push(entry[13:entry.length() - 4].to_owned())
    }
  }
  scopes.sort()
  if scopes.contains(DEFAULT_SCOPE) {
    let ordered : Array[String] = [DEFAULT_SCOPE]
    for scope in scopes {
      if scope != DEFAULT_SCOPE {
        ordered.push(scope)
      }
    }
    ordered
  } else {
    scopes
  }
}

///|
pub fn save_token_for(scope : String, token : String) -> Result[Unit, String] {
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
  guard token_path_for(scope) is Ok(path) else {
    return Err("credential path is unavailable")
  }
  @fs.write_string_to_file(path, encrypted, encoding="utf8") catch {
    _ => return Err("failed to write encrypted token")
  }
  Ok(())
}

///|
pub fn save_token(token : String) -> Result[Unit, String] {
  save_token_for(DEFAULT_SCOPE, token)
}

///|
pub fn load_token_for(scope : String) -> Result[String?, String] {
  guard token_path_for(scope) is Ok(path) else {
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
pub fn load_token() -> Result[String?, String] {
  load_token_for(DEFAULT_SCOPE)
}

///|
pub fn delete_token_for(scope : String) -> Result[Unit, String] {
  for path_result in [token_path_for(scope), login_path_for(scope)] {
    guard path_result is Ok(path) else {
      return Err("credential path is unavailable")
    }
    if @fs.path_exists(path) {
      @fs.remove_file(path) catch {
        _ => return Err("failed to delete credential file")
      }
    }
  }
  Ok(())
}

///|
pub fn delete_token() -> Result[Unit, String] {
  delete_token_for(DEFAULT_SCOPE)
}

///|
pub fn save_login_label(scope : String, login : String) -> Result[Unit, String] {
  guard @app_paths.ensure_data_directory() is Ok(_) else {
    return Err("application data directory is unavailable")
  }
  guard login_path_for(scope) is Ok(path) else {
    return Err("credential path is unavailable")
  }
  @fs.write_string_to_file(path, login, encoding="utf8") catch {
    _ => return Err("failed to write login label")
  }
  Ok(())
}

///|
pub fn load_login_label(scope : String) -> String? {
  match login_path_for(scope) {
    Ok(path) =>
      if @fs.path_exists(path) {
        let login = @fs.read_file_to_string(path, encoding="utf8") catch {
          _ => return None
        }
        Some(login)
      } else {
        None
      }
    Err(_) => None
  }
}

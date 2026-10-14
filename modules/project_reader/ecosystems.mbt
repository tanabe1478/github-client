///|
/// A tool once per name, version, and source.
fn push_once(
  tools : Array[@domain.ProjectTool],
  name : String,
  version : String,
  exact : Bool,
  source : String,
) -> Unit {
  if name == "" ||
    version == "" ||
    tools.any(tool => {
      tool.name == name && tool.version == version && tool.source == source
    }) {
    return
  }
  tools.push({ name, version, exact, source, })
}

///|
/// Whether a version names one release ("22.20.0") rather than a line
/// ("22", "v4").
fn full_version(version : String) -> Bool {
  version.split(".").count() >= 3 && single_version(version)
}

///|
/// Node.js from a version written as "v22.20.0", "22", or "lts/iron"
/// (skipped).
fn push_node(
  tools : Array[@domain.ProjectTool],
  text : String,
  source : String,
) -> Unit {
  let trimmed = text.trim().trim(chars="\"'").to_owned()
  let value = if trimmed.has_prefix("v") {
    trimmed[1:].to_owned()
  } else {
    trimmed
  }
  guard exact_value(value) else { return }
  let version = leading_number(value)
  push_once(tools, "node", version, full_version(version), source)
}

///|
/// Java and Node.js versions of `.java-version`, `.node-version`,
/// `.nvmrc`, `.sdkmanrc` ("java=21.0.6-tem"), `.tool-versions`
/// ("nodejs 22.20.0"), and `mise.toml` (`node = "22"` under [tools]).
fn read_version_file(
  file : String,
  source : String,
  tools : Array[@domain.ProjectTool],
) -> Unit {
  let name = base_name(file)
  let mut section = ""
  for raw in source.split("\n") {
    let line = raw.trim().to_owned()
    if line == "" || line.has_prefix("#") {
      continue
    }
    match name {
      ".java-version" => {
        push_java(tools, line, file)
        return
      }
      ".node-version" | ".nvmrc" => {
        push_node(tools, line, file)
        return
      }
      ".sdkmanrc" =>
        if line.has_prefix("java=") {
          push_java(tools, line[5:].to_owned(), file)
        }
      ".tool-versions" => {
        let parts = line.split(" ").filter(part => part != "").to_array()
        guard parts.length() >= 2 else { continue }
        match parts[0] {
          "java" => push_java(tools, parts[1].to_owned(), file)
          "nodejs" | "node" => push_node(tools, parts[1].to_owned(), file)
          _ => ()
        }
      }
      _ => {
        // mise.toml
        if line.has_prefix("[") {
          section = line
          continue
        }
        guard section == "[tools]" && line.find("=") is Some(at) else {
          continue
        }
        let key = line[:at].trim().trim(chars="\"'").to_owned()
        let value = match quoted_strings(line[at + 1:].to_owned()) {
          [text, ..] => text
          [] => line[at + 1:].trim().to_owned()
        }
        match key {
          "java" => push_java(tools, value, file)
          "node" | "nodejs" => push_node(tools, value, file)
          _ => ()
        }
      }
    }
  }
}

///|
/// Whether `text` is a full Git commit SHA.
fn commit_sha(text : String) -> Bool {
  text.length() == 40 &&
  text
  .iter()
  .all(character => {
    (character >= '0' && character <= '9') ||
    (character >= 'a' && character <= 'f')
  })
}

///|
/// The actions a workflow uses, as owner/repo: `uses: actions/checkout@v4`,
/// a subpath such as `github/codeql-action/init@v3`, or a commit pinned with
/// its version in a comment (`@<sha> # v4.2.2`). Local actions and Docker
/// images are skipped, and so are branches such as `@main`.
fn read_workflow(
  file : String,
  source : String,
  tools : Array[@domain.ProjectTool],
) -> Unit {
  for raw in source.split("\n") {
    let line = raw.trim().trim_start(chars="- ").to_owned()
    guard line.has_prefix("uses:") else { continue }
    let rest = line[5:].trim().to_owned()
    let (reference, comment) = match rest.find("#") {
      Some(at) => (rest[:at].trim().to_owned(), rest[at + 1:].trim().to_owned())
      None => (rest, "")
    }
    let reference = reference.trim(chars="\"'").to_owned()
    guard !reference.has_prefix(".") && !reference.has_prefix("docker://") else {
      continue
    }
    guard reference.find("@") is Some(at) else { continue }
    let path = reference[:at].to_owned()
    let ref_ = reference[at + 1:].to_owned()
    let parts = path.split("/").to_array()
    guard parts.length() >= 2 && parts[0] != "" && parts[1] != "" else {
      continue
    }
    let name = "\{parts[0]}/\{parts[1]}"
    let version = if commit_sha(ref_) {
      // Pinned to a commit; the comment says which version it is.
      let text = comment.trim_start(chars="v").to_owned()
      if exact_value(text) {
        leading_number(text)
      } else {
        ""
      }
    } else if ref_.has_prefix("v") && exact_value(ref_[1:].to_owned()) {
      ref_[1:].to_owned()
    } else if exact_value(ref_) {
      ref_
    } else {
      ""
    }
    guard version != "" else { continue }
    push_once(tools, name, version, full_version(version), "\{file} uses")
  }
}

///|
/// The GitHub repository of a Terraform provider source: "hashicorp/aws"
/// or "registry.terraform.io/hashicorp/aws" is hashicorp/terraform-provider-aws.
pub fn provider_repository(source : String) -> String? {
  let parts = source.trim(chars="\"").split("/").to_array()
  let (namespace, kind) = match parts.length() {
    2 => (parts[0], parts[1])
    // A registry host first; namespace/name/provider is a module.
    3 if parts[0].contains(".") => (parts[1], parts[2])
    _ => return None
  }
  guard namespace != "" && kind != "" && !namespace.contains(".") else {
    return None
  }
  Some("\{namespace.to_lower()}/terraform-provider-\{kind.to_lower()}")
}

///|
/// Terraform's required_version as hashicorp/terraform, providers of
/// required_providers by their GitHub repository, and the exact provider
/// versions of a .terraform.lock.hcl.
fn read_terraform(
  file : String,
  source : String,
  tools : Array[@domain.ProjectTool],
) -> Unit {
  let lock = file.has_suffix(".terraform.lock.hcl")
  let mut provider : String? = None
  let mut version = ""
  // Brace depth, and the depth inside required_providers (-1 outside).
  let mut depth = 0
  let mut providers_at = -1
  let flush = fn(provider : String?, version : String) {
    match provider {
      Some(repository) if version != "" =>
        push_once(
          tools,
          repository,
          version,
          lock || single_version(version),
          if lock {
            file
          } else {
            "\{file} required_providers"
          },
        )
      _ => ()
    }
  }
  for raw in source.split("\n") {
    let line = raw.trim().to_owned()
    if line.has_prefix("#") || line.has_prefix("//") {
      continue
    }
    let value = match quoted_strings(line) {
      [text, ..] => text
      [] => ""
    }
    let in_providers = providers_at >= 0 && depth > providers_at
    if line.has_prefix("required_version") {
      push_once(
        tools,
        "hashicorp/terraform",
        value,
        single_version(value),
        "\{file} required_version",
      )
    } else if line.has_prefix("required_providers") {
      providers_at = depth
    } else if lock && line.has_prefix("provider ") {
      flush(provider, version)
      provider = provider_repository(value)
      version = ""
    } else if !lock &&
      in_providers &&
      line.has_prefix("source") &&
      line.contains("=") {
      provider = provider_repository(value)
    } else if (lock || in_providers) &&
      line.has_prefix("version") &&
      line.contains("=") {
      version = value
    }
    for character in line {
      if character == '{' {
        depth += 1
      } else if character == '}' {
        depth -= 1
        // A provider's block in required_providers closed.
        if !lock && providers_at >= 0 && depth == providers_at + 1 {
          flush(provider, version)
          provider = None
          version = ""
        }
        if depth <= providers_at {
          providers_at = -1
        }
      }
    }
  }
  flush(provider, version)
}

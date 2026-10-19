///|
/// The versions a Maven repository's `maven-metadata.xml` lists, and its
/// `<lastUpdated>` as an ISO 8601 time ("" when missing). The time is when
/// the newest version was published, as long as nothing older was
/// republished after it.
pub fn maven_metadata_versions(xml : String) -> (Array[String], String) {
  let versions : Array[String] = []
  match xml_blocks(xml, "versions") {
    [block, ..] =>
      for version in xml_blocks(block, "version") {
        let trimmed = version.trim().to_owned()
        if trimmed != "" && !versions.contains(trimmed) {
          versions.push(trimmed)
        }
      }
    _ => ()
  }
  let updated = match xml_text(xml, "lastUpdated") {
    // 20260917101500 is 2026-09-17T10:15:00Z.
    Some(stamp) if stamp.length() == 14 =>
      "\{stamp[0:4]}-\{stamp[4:6]}-\{stamp[6:8]}T\{stamp[8:10]}:\{stamp[10:12]}:\{stamp[12:14]}Z"
    _ => ""
  }
  (versions, updated)
}

///|
/// The versions of an npm registry document and when each was published,
/// from its `time` field. Unpublished versions are left out.
pub fn npm_document_versions(document : String) -> Array[(String, String)] {
  let json = @json.parse(document) catch { _ => return [] }
  guard json is Object(fields) else { return [] }
  let times = match fields.get("time") {
    Some(Object(map)) => map
    _ => Map([])
  }
  let found : Array[(String, String)] = []
  match fields.get("versions") {
    Some(Object(versions)) =>
      for version, _ in versions {
        let time = match times.get(version) {
          Some(String(text)) => text
          _ => ""
        }
        found.push((version, time))
      }
    _ => ()
  }
  found
}

///|
/// Names a changelog starts with, in the order Dependabot prefers them.
let changelog_names : Array[String] = [
  "changelog", "news", "changes", "history", "release", "whatsnew", "releases",
]

///|
/// The changelog among a repository's top-level files, by Dependabot's
/// names: CHANGELOG.md, CHANGELOG.txt, CHANGES, HISTORY.md, and so on.
pub fn changelog_file(files : Array[String]) -> String? {
  for name in changelog_names {
    for file in files {
      let lower = file.to_lower()
      guard lower.has_prefix(name) else { continue }
      let mut rest = lower[name.length():].to_owned()
      // RELEASE-NOTES.txt, release_notes.md
      for infix in ["-notes", "_notes"] {
        if rest.has_prefix(infix) {
          rest = rest[infix.length():].to_owned()
        }
      }
      if rest == "" ||
        rest == ".md" ||
        rest == ".txt" ||
        rest == ".rst" ||
        rest == ".markdown" ||
        rest == ".adoc" {
        return Some(file)
      }
    }
  }
  None
}

///|
/// Whether a changelog line starts the section of `version`: a heading such
/// as "## 10.10", "## [10.10] - 2026-09-17", "v10.10", or "10.10 (2026-09-17)".
fn version_heading(line : String, version : String) -> Bool {
  guard !line.has_prefix(" ") && !line.has_prefix("\t") else { return false }
  let mut text = line.trim_start(chars="#=*-[ ").to_owned()
  for prefix in ["version ", "Version ", "release ", "Release ", "v", "V"] {
    if text.has_prefix(prefix) {
      text = text[prefix.length():].to_owned()
      break
    }
  }
  guard text.has_prefix(version) else { return false }
  match text.get_char(version.length()) {
    None => true
    Some(next) =>
      !((next >= '0' && next <= '9') ||
      (next >= 'a' && next <= 'z') ||
      (next >= 'A' && next <= 'Z') ||
      next == '.' ||
      next == '-')
  }
}

///|
/// Whether a changelog line starts the section of any version.
fn any_version_heading(line : String) -> Bool {
  guard !line.has_prefix(" ") && !line.has_prefix("\t") else { return false }
  let mut text = line.trim_start(chars="#=*-[ ").to_owned()
  for prefix in ["version ", "Version ", "release ", "Release ", "v", "V"] {
    if text.has_prefix(prefix) {
      text = text[prefix.length():].to_owned()
      break
    }
  }
  match (text.get_char(0), text.get_char(1)) {
    (Some(first), Some(second)) =>
      first >= '0' &&
      first <= '9' &&
      (second == '.' || (second >= '0' && second <= '9'))
    _ => false
  }
}

///|
/// The most of a changelog kept as notes.
const MAX_NOTES_LENGTH : Int = 20000

///|
/// The part of a changelog that covers what changed after `used` up to and
/// including `newest`, whichever way the file is ordered. Only `newest`'s
/// section when `used` is not in it; "" when `newest` is not either.
pub fn changelog_section(
  text : String,
  newest : String,
  used : String,
) -> String {
  let lines = text.replace_all(old="\r\n", new="\n").split("\n").to_array()
  let mut newest_at = -1
  let mut used_at = -1
  for index, line in lines {
    let line = line.to_owned()
    if newest_at < 0 && version_heading(line, newest) {
      newest_at = index
    }
    if used != "" && used_at < 0 && version_heading(line, used) {
      used_at = index
    }
  }
  guard newest_at >= 0 else { return "" }
  // The heading after `from`, or the end.
  let next_heading = (from : Int) => {
    let mut at = from + 1
    while at < lines.length() && !any_version_heading(lines[at].to_owned()) {
      at += 1
    }
    at
  }
  let (start, end) = if used_at > newest_at {
    // Newest first: from the newest heading to the used one.
    (newest_at, used_at)
  } else if used_at >= 0 {
    // Oldest first: the sections after the used one, through the newest.
    (next_heading(used_at), next_heading(newest_at))
  } else {
    (newest_at, next_heading(newest_at))
  }
  let section = lines[start:end]
    .iter()
    .map(line => line.to_owned())
    .collect()
    .join("\n")
    .trim()
    .to_owned()
  if section.length() > MAX_NOTES_LENGTH {
    section[:MAX_NOTES_LENGTH].to_owned()
  } else {
    section
  }
}

///|
/// The first entry of `newest`'s section of a changelog, without list
/// markers and with its wrapped lines joined, cut after its first sentence;
/// "" when there is none. Subheadings such as "### Changed" are skipped.
pub fn changelog_summary(text : String, newest : String) -> String {
  let lines = changelog_section(text, newest, "").split("\n").to_array()
  let entry = StringBuilder()
  // The first line is the version's heading.
  for index = 1; index < lines.length(); index = index + 1 {
    let trimmed = lines[index].trim().to_owned()
    let marked = trimmed.has_prefix("*") ||
      trimmed.has_prefix("-") ||
      trimmed.has_prefix("+")
    if entry.is_empty() {
      if trimmed == "" ||
        trimmed.has_prefix("#") ||
        trimmed.has_prefix("```") ||
        trimmed.has_prefix("<") {
        continue
      }
      entry.write_string(trimmed.trim_start(chars="*-+ ").to_string())
    } else if trimmed == "" || marked || trimmed.has_prefix("#") {
      break
    } else {
      entry.write_string(" " + trimmed)
    }
  }
  let line = entry.to_string()
  match line.find(". ") {
    Some(at) => line[:at + 1].to_owned()
    None => line
  }
}

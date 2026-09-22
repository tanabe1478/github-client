///|
pub(all) struct ReadMarker {
  url : String
  read_at : String
}

///|
pub fn ReadMarker::new(url : String, read_at : String) -> ReadMarker {
  { url, read_at, }
}

///|
pub fn ReadMarker::url(self : ReadMarker) -> String {
  self.url
}

///|
pub fn ReadMarker::read_at(self : ReadMarker) -> String {
  self.read_at
}

///|
/// An activity is read only until GitHub reports a newer updated_at value.
pub fn activity_is_read(
  markers : Array[ReadMarker],
  url : String,
  updated_at : String,
) -> Bool {
  for marker in markers {
    if marker.url == url {
      return marker.read_at >= updated_at
    }
  }
  false
}

///|
pub fn mark_activity_read(
  markers : Array[ReadMarker],
  url : String,
  updated_at : String,
) -> Array[ReadMarker] {
  let updated : Array[ReadMarker] = []
  for marker in markers {
    if marker.url != url {
      updated.push(marker)
    }
  }
  updated.push(ReadMarker::new(url, updated_at))
  updated
}

///|
pub fn mark_activity_unread(
  markers : Array[ReadMarker],
  url : String,
) -> Array[ReadMarker] {
  let updated : Array[ReadMarker] = []
  for marker in markers {
    if marker.url != url {
      updated.push(marker)
    }
  }
  updated
}

///|
pub fn repository_is_watched(
  repositories : Array[RepositoryRef],
  repository : String,
) -> Bool {
  let normalized = repository.to_lower()
  repositories.any(item => item.key().to_lower() == normalized)
}

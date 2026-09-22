name = "tanabe1478/github-client"

version = "0.1.0"

import {
  "mizchi/glfw@0.2.3",
  "mizchi/github@0.1.4",
  "moonbitstack/moonegui@0.2.0",
  "moonbit-community/proton_safe_storage@0.3.3",
  "moonbit-community/proton_shell@0.3.3",
}

readme = "README.md"

repository = "https://github.com/tanabe1478/github-client"

license = "Apache-2.0"

keywords = [ "github", "desktop", "glfw", "native" ]

preferred_target = "native"

description = "A native desktop GitHub client built with MoonBit"

options(
  "--moonbit-unstable-prebuild": "scripts/native-link-config.cjs",
)

name = "tanabe1478/github-client"

version = "0.1.0"

import {
  "tanabe1478/github-client-app-paths@0.1.0",
  "tanabe1478/github-client-credential-store@0.1.0",
  "tanabe1478/github-client-domain@0.1.0",
  "tanabe1478/github-client-github-api@0.1.0",
  "tanabe1478/github-client-repository-store@0.1.0",
  "mizchi/glfw@0.2.3",
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

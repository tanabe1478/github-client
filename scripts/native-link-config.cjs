#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

function slash(value) {
  return value.replace(/\\/g, "/");
}

function command(name, args) {
  try {
    return execFileSync(name, args, {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "";
  }
}

function windowsGlfwRoot() {
  const triplet = process.env.VCPKG_DEFAULT_TRIPLET || "x64-windows-static";
  const installedCandidates = [
    process.env.VCPKG_INSTALLED_DIR,
    process.env.VCPKG_ROOT
      ? path.join(process.env.VCPKG_ROOT, "installed")
      : "",
    path.join(process.env.USERPROFILE || "", "vcpkg", "installed"),
    "C:\\vcpkg\\installed",
  ].filter(Boolean);

  for (const installed of installedCandidates) {
    const root = path.join(installed, triplet);
    if (
      fs.existsSync(path.join(root, "include", "GLFW", "glfw3.h")) &&
      fs.existsSync(path.join(root, "lib", "glfw3.lib"))
    ) {
      return root;
    }
  }
  return "";
}

function nativeConfig() {
  if (process.platform === "win32") {
    const root = windowsGlfwRoot();
    const includeFlags = root ? `-I${slash(path.join(root, "include"))}` : "";
    const libraryFlags = root ? `-L${slash(path.join(root, "lib"))}` : "";
    return {
      cc: "clang",
      cxx: "clang++",
      cflags: includeFlags,
      libs: `${libraryFlags} -lglfw3 -lopengl32 -lgdi32 -luser32 -lshell32`,
    };
  }

  if (process.platform === "darwin") {
    const prefix = command("brew", ["--prefix", "glfw"]);
    return {
      cc: "clang",
      cxx: "clang++",
      cflags: prefix ? `-I${slash(path.join(prefix, "include"))}` : "",
      libs: `${prefix ? `-L${slash(path.join(prefix, "lib"))}` : ""} -lglfw -framework OpenGL -framework Cocoa -framework IOKit -framework CoreFoundation -framework QuartzCore`,
    };
  }

  return {
    cc: process.env.CC || "clang",
    cxx: process.env.CXX || "clang++",
    cflags: command("pkg-config", ["--cflags", "glfw3"]),
    libs: `${command("pkg-config", ["--libs", "glfw3"]) || "-lglfw"} -lGL`,
  };
}

const config = nativeConfig();
const repoRoot = path.resolve(__dirname, "..");
const localNativeLibs = slash(path.join(repoRoot, ".native-libs", process.platform));
const imguiInclude = slash(path.join(repoRoot, "vendor", "imgui"));
process.stdout.write(
  `${JSON.stringify({
    vars: {
      GITHUB_CLIENT_CC: config.cc,
      GITHUB_CLIENT_CXX: config.cxx,
      GITHUB_CLIENT_GLFW_CFLAGS: config.cflags,
      GITHUB_CLIENT_IMGUI_CXXFLAGS: `-std=c++17 -I${imguiInclude}`,
      GITHUB_CLIENT_GLFW_LIBS: `-L${localNativeLibs} ${config.libs}`,
    },
  })}\n`,
);

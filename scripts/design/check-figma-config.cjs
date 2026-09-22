const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "../..");
const manifestPath = path.join(root, "design", "figma.json");
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const errors = [];

if (manifest.version !== 1) errors.push("version must be 1");
if (!["unbound", "partial", "active", "archived"].includes(manifest.status)) {
  errors.push("status must be unbound, partial, active, or archived");
}
if (!manifest.file || typeof manifest.file.name !== "string" || !manifest.file.name) {
  errors.push("file.name is required");
}
if (["partial", "active"].includes(manifest.status)) {
  if (!/^https:\/\/(www\.)?figma\.com\//.test(manifest.file.url)) {
    errors.push("a bound manifest requires a figma.com file URL");
  }
  if (!manifest.file.key) errors.push("a bound manifest requires file.key");
}
if (manifest.status === "active" && manifest.sync?.state !== "synchronized") {
  errors.push("an active binding requires sync.state=synchronized");
}
if (!Array.isArray(manifest.surfaces) || manifest.surfaces.length === 0) {
  errors.push("at least one surface is required");
} else {
  const ids = new Set();
  const requiredSurfaceIds = [
    "inbox", "for-you", "repositories", "pull-requests", "issues", "settings", "pat-dialog"
  ];
  for (const surface of manifest.surfaces) {
    if (!/^[a-z0-9-]+$/.test(surface.id ?? "")) {
      errors.push(`invalid surface id: ${surface.id}`);
    }
    if (ids.has(surface.id)) errors.push(`duplicate surface id: ${surface.id}`);
    ids.add(surface.id);
    for (const implementation of surface.implementation ?? []) {
      if (!fs.existsSync(path.join(root, implementation))) {
        errors.push(`${surface.id}: missing implementation ${implementation}`);
      }
    }
    if (manifest.status === "active" && !surface.figmaNodeId) {
      errors.push(`${surface.id}: active binding requires figmaNodeId`);
    }
    if (manifest.status === "active" && !surface.evidence) {
      errors.push(`${surface.id}: active binding requires screenshot evidence`);
    }
    if (surface.evidence && !fs.existsSync(path.join(root, surface.evidence))) {
      errors.push(`${surface.id}: missing evidence ${surface.evidence}`);
    }
  }
  for (const requiredId of requiredSurfaceIds) {
    if (!ids.has(requiredId)) errors.push(`missing required surface: ${requiredId}`);
  }
}
if (!manifest.tokens || !fs.existsSync(path.join(root, "design", manifest.tokens.replace(/^\.\//, "")))) {
  errors.push("tokens must reference an existing file under design/");
}

if (errors.length > 0) {
  console.error(errors.map((error) => `- ${error}`).join("\n"));
  process.exit(1);
}
console.log(`Figma binding is valid (${manifest.status}, ${manifest.surfaces.length} surfaces).`);

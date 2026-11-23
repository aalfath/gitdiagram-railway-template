// Small, checked source patches applied to the pinned upstream commit so that
// GitDiagram runs on Railway: S3 endpoint from a Railway Bucket instead of a
// hard-coded Cloudflare R2 host, the site URL from the deployment's domain,
// and an empty "browse" index on a fresh bucket. Each patch must match
// exactly once, or the build fails (so an upstream change is never silently
// skipped).
import { readFileSync, writeFileSync } from "node:fs";

const patches = [
  {
    file: "src/server/storage/r2.ts",
    from: 'region: "auto",',
    to: 'region: process.env.S3_REGION?.trim() || "auto",\n    forcePathStyle: process.env.S3_FORCE_PATH_STYLE === "1",',
  },
  {
    file: "src/server/storage/r2.ts",
    from: 'endpoint: `https://${readRequiredEnv("R2_ACCOUNT_ID")}.r2.cloudflarestorage.com`,',
    to: 'endpoint: process.env.S3_ENDPOINT?.trim() || `https://${readRequiredEnv("R2_ACCOUNT_ID")}.r2.cloudflarestorage.com`,',
  },
  {
    file: "src/lib/site.ts",
    from: 'export const SITE_URL = "https://gitdiagram.com";',
    to: 'export const SITE_URL =\n  (typeof process !== "undefined" && process.env?.GITDIAGRAM_SITE_URL?.trim()) ||\n  "https://gitdiagram.com";',
  },
  {
    file: "src/server/storage/browse-diagrams.ts",
    from: "if (!stored && params.requireExistingIndex) {",
    to: 'if (!stored && params.requireExistingIndex && process.env.GITDIAGRAM_SELF_HOSTED !== "1") {',
  },
];

for (const { file, from, to } of patches) {
  const text = readFileSync(file, "utf8");
  const count = text.split(from).length - 1;
  if (count !== 1) {
    console.error(`patch.mjs: expected 1 match in ${file}, found ${count}: ${from}`);
    process.exit(1);
  }
  writeFileSync(file, text.replace(from, to));
  console.log(`patch.mjs: patched ${file}`);
}

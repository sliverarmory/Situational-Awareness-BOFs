#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const source = JSON.parse(fs.readFileSync(path.join(root, "testdata/e2e-manifest.json"), "utf8"));
const outputPath = path.join(root, ".github/sliver-bof-e2e.json");
const targets = [
  ["windows", "386"], ["windows", "amd64"], ["windows", "arm64"],
  ["linux", "386"], ["linux", "amd64"], ["linux", "arm64"],
  ["darwin", "amd64"], ["darwin", "arm64"],
];
const commands = ["dir", "md5", "sha256", "uptime"];
const fixture = source.fixtures?.file?.contents_utf8;
if (source.version !== 1 || source.entrypoint !== "go" || typeof fixture !== "string" ||
    source.fixtures?.directory?.files?.["marker.txt"] === undefined) {
  throw new Error("unexpected Reflektor E2E contract or missing fixtures");
}

function actionArguments(artifact) {
  return artifact.args.map(({ type, value }) => {
    const actionType = { int16: "short", int32: "int", string: "string", wstring: "wstring" }[type];
    if (!actionType) throw new Error(`unsupported ${artifact.name} argument type ${type}`);
    return { type: actionType, value };
  });
}

function testFor(os, arch, name) {
  const matches = source.artifacts.filter((artifact) =>
    artifact.os === os && artifact.arch === arch && artifact.name === name);
  if (matches.length !== 1) throw new Error(`expected one ${os}/${arch}/${name} artifact`);
  const artifact = matches[0];
  if (artifact.path !== `dist/${os}/${arch}/${name}.o`) {
    throw new Error(`unexpected object path for ${os}/${arch}/${name}`);
  }
  const test = { name, object: artifact.path };
  const args = actionArguments(artifact);
  if (args.length) test.args = args;
  if (name === "dir") {
    test.expect = { output: { contains: ["Contents of", "marker.txt"] } };
  } else if (name === "uptime") {
    test.expect = { output: { contains: [os === "windows" ? "Uptime:" : "uptime_seconds="] } };
  } else {
    const digest = crypto.createHash(name).update(fixture).digest("hex");
    test.expect = { output: { matches: [`(?i:${digest})`] } };
  }
  return test;
}

const manifest = {
  schema: "sliver-bof-e2e/v1",
  sliver: { version: "b19e383111dbf8b04096806b249f6238274edff4" },
  defaults: {
    bof_executor: "reflektor", entrypoint: source.entrypoint,
    modes: ["session", "beacon"], repeat: 1, command_timeout: "2m",
  },
  fixtures: source.fixtures,
  suites: targets.map(([os, arch]) => ({
    name: `${os}-${arch}`,
    target: { os, arch },
    tests: commands.map((name) => testFor(os, arch, name)),
  })),
};
const output = `${JSON.stringify(manifest, null, 2)}\n`;
if (process.argv.includes("--check")) {
  if (fs.readFileSync(outputPath, "utf8") !== output) {
    throw new Error("Sliver BOF E2E manifest is stale; regenerate with --write");
  }
} else if (process.argv.includes("--write")) {
  fs.writeFileSync(outputPath, output);
} else {
  process.stdout.write(output);
}

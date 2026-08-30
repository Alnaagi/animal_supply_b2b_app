#!/usr/bin/env node

import { createHash } from 'node:crypto';
import {
  readdir,
  readFile,
  rm,
  stat,
  writeFile,
} from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  assertPublicBuildConfiguration,
  readDartDefines,
} from './public_build_config.mjs';
import { firebaseMessagingServiceWorkerPreamble } from './firebase_web_push.mjs';

const toolDirectory = dirname(fileURLToPath(import.meta.url));
const appDirectory = resolve(toolDirectory, '..');
const buildDirectory = join(appDirectory, 'build', 'web');
const defaultManifestName = 'web_shell_manifest.json';
const generatedManifestPattern = /^web_shell_manifest\.[a-f0-9]{16}\.json$/;
const bootstrapManifestPattern =
  /web_shell_manifest(?:\.[a-f0-9]{16})?\.json/g;
const excludedFiles = new Set([
  '.last_build_id',
  '_headers',
  'app_service_worker.js',
  'flutter_service_worker.js',
  defaultManifestName,
]);
const firebaseWebSdkVersion = '12.15.0';

const argumentsList = process.argv.slice(2);
const prepareOnly = argumentsList[0] === '--prepare-only';
const flutterArguments = prepareOnly ? [] : argumentsList;
let buildDefines;

if (!prepareOnly) {
  buildDefines = await readDartDefines(flutterArguments, appDirectory);
  assertPublicBuildConfiguration(buildDefines);

  const flutterBinary = process.env.FLUTTER_BIN || 'flutter';
  const result = spawnSync(
    flutterBinary,
    [
      'build',
      'web',
      '--no-wasm-dry-run',
      ...flutterArguments,
    ],
    {
      cwd: appDirectory,
      stdio: 'inherit',
      env: {
        ...process.env,
        DART_VM_OPTIONS: '--old_gen_heap_size=4096',
      },
    },
  );
  if (result.error) {
    throw new Error(
      `Unable to run ${flutterBinary}: ${result.error.message}`,
    );
  }
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

await prepareWebRelease();

async function prepareWebRelease() {
  await assertDirectory(buildDirectory);
  await removeOldGeneratedManifests();
  if (buildDefines) {
    await prepareFirebaseBootstrap(buildDefines);
    await prepareFirebaseMessagingServiceWorker(buildDefines);
  }

  const bootstrapPath = join(buildDirectory, 'flutter_bootstrap.js');
  const bootstrapSource = await readFile(bootstrapPath, 'utf8');
  if (!bootstrapManifestPattern.test(bootstrapSource)) {
    throw new Error(
      'flutter_bootstrap.js does not contain the shell manifest marker.',
    );
  }
  bootstrapManifestPattern.lastIndex = 0;
  const normalizedBootstrap = bootstrapSource.replace(
    bootstrapManifestPattern,
    defaultManifestName,
  );
  await writeFile(bootstrapPath, normalizedBootstrap);

  const resources = await listReleaseResources(buildDirectory);
  assertRequiredResources(resources);

  const digest = createHash('sha256');
  for (const resource of resources) {
    digest.update(resource);
    digest.update('\0');
    digest.update(await readFile(join(buildDirectory, resource)));
    digest.update('\0');
  }
  const fullVersion = digest.digest('hex');
  const manifestName = `web_shell_manifest.${fullVersion.slice(0, 16)}.json`;
  const manifest = {
    version: fullVersion,
    resources,
  };

  await writeFile(
    join(buildDirectory, manifestName),
    `${JSON.stringify(manifest, null, 2)}\n`,
  );
  await writeFile(
    join(buildDirectory, defaultManifestName),
    `${JSON.stringify(manifest, null, 2)}\n`,
  );
  await writeFile(
    bootstrapPath,
    normalizedBootstrap.replace(defaultManifestName, manifestName),
  );

  console.log(
    `Prepared ${resources.length} offline web resources in ${manifestName}.`,
  );
}

async function prepareFirebaseBootstrap(defines) {
  const firebaseKeys = [
    'FIREBASE_API_KEY',
    'FIREBASE_PROJECT_ID',
    'FIREBASE_MESSAGING_SENDER_ID',
    'FIREBASE_WEB_APP_ID',
  ];
  const enabled = firebaseKeys.every(
    (key) => (defines.get(key) ?? '').trim().length > 0,
  );
  if (!enabled) return;

  const source = `'use strict';

window.flutterfire_web_sdk_version = '${firebaseWebSdkVersion}';
window.firebaseSdkReady = Promise.all([
  import('https://www.gstatic.com/firebasejs/${firebaseWebSdkVersion}/firebase-app.js'),
  import('https://www.gstatic.com/firebasejs/${firebaseWebSdkVersion}/firebase-messaging.js'),
])
  .then(([core, messaging]) => {
    window.firebase_core = core;
    window.firebase_messaging = messaging;
  })
  .catch((error) => {
    console.warn('Firebase web SDK preload failed.', error);
  });
`;
  await writeFile(join(buildDirectory, 'firebase_bootstrap.js'), source);
}

async function prepareFirebaseMessagingServiceWorker(defines) {
  const preamble = firebaseMessagingServiceWorkerPreamble(
    defines,
    firebaseWebSdkVersion,
  );
  if (!preamble) return;

  const swPath = join(buildDirectory, 'app_service_worker.js');
  const existing = await readFile(swPath, 'utf8');
  if (existing.includes('self.__ANIMAL_SUPPLY_FCM_READY = true')) return;
  await writeFile(swPath, `${preamble}${existing}`);
}

async function removeOldGeneratedManifests() {
  const entries = await readdir(buildDirectory, { withFileTypes: true });
  await Promise.all(
    entries
      .filter(
        (entry) =>
          entry.isFile() && generatedManifestPattern.test(entry.name),
      )
      .map((entry) => rm(join(buildDirectory, entry.name))),
  );
}

async function listReleaseResources(directory) {
  const files = [];
  await walk(directory, files);
  return files
    .map((path) => relative(directory, path).split(sep).join('/'))
    .filter((path) => {
      const fileName = path.split('/').pop();
      return (
        !excludedFiles.has(path) &&
        !generatedManifestPattern.test(path) &&
        !fileName.endsWith('.map') &&
        !fileName.endsWith('.symbols')
      );
    })
    .sort();
}

async function walk(directory, files) {
  const entries = await readdir(directory, { withFileTypes: true });
  for (const entry of entries) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      await walk(path, files);
    } else if (entry.isFile()) {
      files.push(path);
    }
  }
}

function assertRequiredResources(resources) {
  for (const required of [
    'index.html',
    'firebase_bootstrap.js',
    'flutter_bootstrap.js',
    'flutter.js',
    'main.dart.js',
    'manifest.json',
    'pwa_install.js',
    'version.json',
    'assets/AssetManifest.bin.json',
    'assets/FontManifest.json',
  ]) {
    if (!resources.includes(required)) {
      throw new Error(`Flutter web build is missing ${required}.`);
    }
  }
  if (!resources.some((resource) => resource.endsWith('.wasm'))) {
    throw new Error('Flutter web build does not contain a local engine WASM.');
  }
}

async function assertDirectory(path) {
  let details;
  try {
    details = await stat(path);
  } catch (_) {
    throw new Error(
      `Missing ${path}. Run a Flutter web build before --prepare-only.`,
    );
  }
  if (!details.isDirectory()) {
    throw new Error(`${path} is not a directory.`);
  }
}

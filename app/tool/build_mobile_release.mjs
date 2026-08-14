#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import {
  mkdir,
  readFile,
  readdir,
  stat,
  writeFile,
} from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { dirname, extname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import {
  assertPublicBuildConfiguration,
  readDartDefines,
} from './public_build_config.mjs';

const toolDirectory = dirname(fileURLToPath(import.meta.url));
const appDirectory = resolve(toolDirectory, '..');
const repositoryDirectory = resolve(appDirectory, '..');
const releaseManifestDirectory = join(
  appDirectory,
  'build',
  'release-manifests',
);
const archiveExtensions = new Set(['.apk', '.aab', '.ipa']);
const archiveEntryMaxBuffer = 128 * 1024 * 1024;

if (isMainModule()) {
  await main();
}

async function main() {
  const options = parseMobileReleaseArguments(process.argv.slice(2));
  if (options.help) {
    printUsage();
    return;
  }

  const defines = await readDartDefines(options.flutterArguments, appDirectory);
  const expectedIosBundleId =
    options.platform === 'ios' ? await readIosBundleId() : undefined;
  assertPublicBuildConfiguration(defines, {
    platform: options.platform,
    expectedIosBundleId,
  });

  const flutterBinary = process.env.FLUTTER_BIN || 'flutter';
  const buildStartedAt = Date.now();
  if (options.platform === 'android') {
    if (!options.appBundleOnly) {
      runFlutter(flutterBinary, [
        'build',
        'apk',
        '--release',
        ...options.flutterArguments,
      ]);
    }
    if (!options.apkOnly) {
      runFlutter(flutterBinary, [
        'build',
        'appbundle',
        '--release',
        ...options.flutterArguments,
      ]);
    }
  } else if (options.noCodesign) {
    runFlutter(flutterBinary, [
      'build',
      'ios',
      '--release',
      '--no-codesign',
      ...options.flutterArguments,
    ]);
  } else {
    runFlutter(flutterBinary, [
      'build',
      'ipa',
      '--release',
      ...options.flutterArguments,
    ]);
  }

  const artifactInputs = await resolveBuiltArtifacts(options, buildStartedAt);
  const artifacts = [];
  for (const artifact of artifactInputs) {
    artifacts.push(
      artifact.directory
        ? await inspectDirectoryArtifact(artifact)
        : await inspectPublicArtifact(artifact),
    );
  }

  const appVersion = await readAppVersion();
  const packageIdentifier =
    options.platform === 'android'
      ? await readAndroidApplicationId()
      : expectedIosBundleId;
  const manifestPath = await writePublicArtifactManifest({
    platform: options.platform,
    appVersion,
    appEnvironment: (defines.get('APP_ENV') ?? 'demo').trim().toLowerCase(),
    packageIdentifier,
    distribution:
      options.platform === 'ios' && options.noCodesign
        ? 'unsigned-app'
        : options.platform === 'ios'
          ? 'signed-ipa'
          : 'signed-android',
    artifacts,
    source: readGitSource(),
  });

  console.log(`Release manifest: ${manifestPath}`);
  for (const artifact of artifacts) {
    console.log(
      `${artifact.type}: ${artifact.relative_path} ` +
        `(${artifact.file_size_bytes} bytes, SHA-256 ${artifact.sha256})`,
    );
  }
}

export function parseMobileReleaseArguments(argumentsList) {
  if (
    argumentsList.length === 0 ||
    argumentsList.includes('--help') ||
    argumentsList.includes('-h')
  ) {
    return {
      help: true,
      platform: 'android',
      flutterArguments: [],
      apkOnly: false,
      appBundleOnly: false,
      noCodesign: false,
    };
  }

  const [platform, ...rawFlutterArguments] = argumentsList;
  if (platform !== 'android' && platform !== 'ios') {
    throw new Error('First argument must be android or ios.');
  }

  const apkOnly = rawFlutterArguments.includes('--apk-only');
  const appBundleOnly = rawFlutterArguments.includes('--appbundle-only');
  const noCodesign = rawFlutterArguments.includes('--no-codesign');
  if (apkOnly && appBundleOnly) {
    throw new Error('--apk-only and --appbundle-only cannot be combined.');
  }
  if (platform !== 'android' && (apkOnly || appBundleOnly)) {
    throw new Error('Android artifact selection flags require platform android.');
  }
  if (platform !== 'ios' && noCodesign) {
    throw new Error('--no-codesign is supported only for platform ios.');
  }

  const flutterArguments = rawFlutterArguments.filter(
    (argument) =>
      argument !== '--apk-only' &&
      argument !== '--appbundle-only' &&
      argument !== '--no-codesign' &&
      argument !== '--release',
  );
  if (
    flutterArguments.includes('--debug') ||
    flutterArguments.includes('--profile')
  ) {
    throw new Error('The mobile release wrapper accepts release builds only.');
  }

  return {
    help: false,
    platform,
    flutterArguments,
    apkOnly,
    appBundleOnly,
    noCodesign,
  };
}

export function findSecretShapedMarker(input) {
  const text = Buffer.isBuffer(input)
    ? input.toString('latin1')
    : String(input);
  const patterns = [
    {
      name: 'Supabase secret key',
      expression: /sb_secret_[A-Za-z0-9._-]{20,}/,
    },
    {
      name: 'private key block',
      expression:
        /-----BEGIN (?:(?:RSA|EC|OPENSSH) )?PRIVATE KEY-----[A-Za-z0-9+/=\r\n ]{32,20000}-----END (?:(?:RSA|EC|OPENSSH) )?PRIVATE KEY-----/,
    },
    {
      name: 'Firebase service-account private key',
      expression:
        /"type"\s*:\s*"service_account"[\s\S]{0,8192}"private_key"\s*:\s*"-----BEGIN/,
    },
    {
      name: 'credential-bearing database URL',
      expression:
        /(?:postgres(?:ql)?|mysql):\/\/[^:/\s]+:[^@/\s]{6,}@[^/\s]+/i,
    },
    {
      name: 'named server secret assignment',
      expression:
        /(?:SUPABASE_SERVICE_ROLE_KEY|FIREBASE_SERVICE_ACCOUNT_JSON|NOTIFICATION_DISPATCH_SECRET|RATE_LIMIT_SALT|DATABASE_URL|DB_PASSWORD|KEYSTORE_PASSWORD|STORE_PASSWORD|KEY_PASSWORD)\s*[:=]\s*["']?[A-Za-z0-9_./+={}:@-]{16,}/i,
    },
  ];
  for (const pattern of patterns) {
    if (pattern.expression.test(text)) return pattern.name;
  }

  const jwtExpression =
    /eyJ[A-Za-z0-9_-]{4,}\.eyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{8,}/g;
  for (const match of text.matchAll(jwtExpression)) {
    if (legacyJwtRole(match[0]) === 'service_role') {
      return 'Supabase service-role JWT';
    }
  }
  return null;
}

export function assertNoSecretShapedMarkers(input, label = 'artifact') {
  const issue = findSecretShapedMarker(input);
  if (issue) {
    throw new Error(`Refusing to publish ${label}: detected ${issue}.`);
  }
}

export async function inspectPublicArtifact({
  type,
  path,
  rootDirectory = appDirectory,
}) {
  const details = await stat(path);
  if (!details.isFile()) {
    throw new Error(`Release artifact is not a file: ${path}`);
  }

  const rawArtifact = await readFile(path);
  assertNoSecretShapedMarkers(rawArtifact, path);
  if (archiveExtensions.has(extname(path).toLowerCase())) {
    scanArchiveEntries(path);
  }

  return {
    type,
    file_name: path.split(sep).pop(),
    relative_path: relative(rootDirectory, path).split(sep).join('/'),
    file_size_bytes: details.size,
    sha256: await sha256File(path),
  };
}

export async function inspectDirectoryArtifact({
  type,
  path,
  rootDirectory = appDirectory,
}) {
  const details = await stat(path);
  if (!details.isDirectory()) {
    throw new Error(`Release artifact is not a directory: ${path}`);
  }

  const files = [];
  await walkFiles(path, files);
  files.sort();
  if (files.length === 0) {
    throw new Error(`Release artifact directory is empty: ${path}`);
  }

  let fileSizeBytes = 0;
  const digest = createHash('sha256');
  for (const file of files) {
    const relativePath = relative(path, file).split(sep).join('/');
    const data = await readFile(file);
    assertNoSecretShapedMarkers(data, `${path}/${relativePath}`);
    fileSizeBytes += data.length;
    digest.update(relativePath);
    digest.update('\0');
    digest.update(data);
    digest.update('\0');
  }

  return {
    type,
    file_name: path.split(sep).pop(),
    relative_path: relative(rootDirectory, path).split(sep).join('/'),
    file_size_bytes: fileSizeBytes,
    sha256: digest.digest('hex'),
  };
}

export async function writePublicArtifactManifest({
  platform,
  appVersion,
  appEnvironment,
  packageIdentifier,
  distribution,
  artifacts,
  source,
  outputDirectory = releaseManifestDirectory,
}) {
  if (!Array.isArray(artifacts) || artifacts.length === 0) {
    throw new Error('At least one release artifact is required.');
  }
  await mkdir(outputDirectory, { recursive: true });
  const safeVersion = `${appVersion.version_name}+${appVersion.build_number}`
    .replace(/[^A-Za-z0-9._+-]/g, '-');
  const outputPath = join(outputDirectory, `${platform}-${safeVersion}.json`);
  const manifest = {
    schema_version: 1,
    generated_at: new Date().toISOString(),
    platform,
    distribution,
    app_environment: appEnvironment,
    package_identifier: packageIdentifier,
    version_name: appVersion.version_name,
    build_number: appVersion.build_number,
    source,
    artifacts,
  };
  await writeFile(outputPath, `${JSON.stringify(manifest, null, 2)}\n`);
  return outputPath;
}

export function parseAppVersion(pubspecSource) {
  const nameMatch = pubspecSource.match(/^name:\s*([^\s#]+)\s*$/m);
  const versionMatch = pubspecSource.match(
    /^version:\s*([A-Za-z0-9._-]+)\+([0-9]+)\s*$/m,
  );
  if (!nameMatch || !versionMatch) {
    throw new Error('pubspec.yaml must contain name and version x.y.z+build.');
  }
  return {
    app_name: nameMatch[1],
    version_name: versionMatch[1],
    build_number: Number.parseInt(versionMatch[2], 10),
  };
}

async function resolveBuiltArtifacts(options, buildStartedAt) {
  if (options.platform === 'android') {
    const artifacts = [];
    if (!options.appBundleOnly) {
      artifacts.push({
        type: 'apk',
        path: join(
          appDirectory,
          'build',
          'app',
          'outputs',
          'flutter-apk',
          'app-release.apk',
        ),
      });
    }
    if (!options.apkOnly) {
      artifacts.push({
        type: 'aab',
        path: join(
          appDirectory,
          'build',
          'app',
          'outputs',
          'bundle',
          'release',
          'app-release.aab',
        ),
      });
    }
    return artifacts;
  }

  if (options.noCodesign) {
    return [
      {
        type: 'ios-app-unsigned',
        path: join(
          appDirectory,
          'build',
          'ios',
          'iphoneos',
          'Runner.app',
        ),
        directory: true,
      },
    ];
  }

  const ipaDirectory = join(appDirectory, 'build', 'ios', 'ipa');
  const entries = await readdir(ipaDirectory, { withFileTypes: true });
  const ipaPaths = [];
  for (const entry of entries) {
    if (!entry.isFile() || extname(entry.name).toLowerCase() !== '.ipa') {
      continue;
    }
    const path = join(ipaDirectory, entry.name);
    const details = await stat(path);
    if (details.mtimeMs >= buildStartedAt - 2000) ipaPaths.push(path);
  }
  if (ipaPaths.length === 0) {
    throw new Error('Flutter completed without producing a fresh IPA artifact.');
  }
  return ipaPaths.sort().map((path) => ({ type: 'ipa', path }));
}

function runFlutter(flutterBinary, argumentsList) {
  const result = spawnSync(flutterBinary, argumentsList, {
    cwd: appDirectory,
    stdio: 'inherit',
  });
  if (result.error) {
    throw new Error(
      `Unable to run ${flutterBinary}: ${result.error.message}`,
    );
  }
  if (result.status !== 0) process.exit(result.status ?? 1);
}

function scanArchiveEntries(path) {
  const listing = spawnSync('unzip', ['-Z1', path], {
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
  });
  if (listing.error) {
    throw new Error(
      `Unable to inspect ${path} with unzip: ${listing.error.message}`,
    );
  }
  if (listing.status !== 0) {
    throw new Error(`Unable to list release archive entries in ${path}.`);
  }

  const entries = listing.stdout
    .split(/\r?\n/)
    .map((entry) => entry.trim())
    .filter((entry) => entry && shouldScanArchiveEntry(entry));
  for (const entry of entries) {
    const extracted = spawnSync('unzip', ['-p', path, entry], {
      encoding: null,
      maxBuffer: archiveEntryMaxBuffer,
    });
    if (extracted.error) {
      throw new Error(
        `Unable to inspect ${entry} in ${path}: ${extracted.error.message}`,
      );
    }
    if (extracted.status !== 0) {
      throw new Error(`Unable to extract ${entry} from ${path}.`);
    }
    assertNoSecretShapedMarkers(extracted.stdout, `${path}:${entry}`);
  }
}

function shouldScanArchiveEntry(entry) {
  const normalized = entry.toLowerCase();
  if (
    normalized.endsWith('/libapp.so') ||
    normalized.endsWith('/app.framework/app')
  ) {
    return true;
  }
  if (
    normalized.endsWith('google-services.json') ||
    normalized.endsWith('googleservice-info.plist') ||
    normalized.endsWith('/.env') ||
    normalized.includes('/.env.')
  ) {
    return true;
  }
  if (!normalized.includes('flutter_assets/')) return false;
  return /\.(?:json|js|mjs|html|txt|yaml|yml|xml|plist|properties|env)$/.test(
    normalized,
  );
}

async function sha256File(path) {
  const digest = createHash('sha256');
  await new Promise((resolvePromise, rejectPromise) => {
    const stream = createReadStream(path);
    stream.on('data', (chunk) => digest.update(chunk));
    stream.on('error', rejectPromise);
    stream.on('end', resolvePromise);
  });
  return digest.digest('hex');
}

async function readAppVersion() {
  return parseAppVersion(await readFile(join(appDirectory, 'pubspec.yaml'), 'utf8'));
}

async function readAndroidApplicationId() {
  const source = await readFile(
    join(appDirectory, 'android', 'app', 'build.gradle'),
    'utf8',
  );
  const match = source.match(/applicationId\s*=\s*["']([^"']+)["']/);
  if (!match) throw new Error('Unable to read the Android application ID.');
  return match[1];
}

async function readIosBundleId() {
  const source = await readFile(
    join(appDirectory, 'ios', 'Runner.xcodeproj', 'project.pbxproj'),
    'utf8',
  );
  const values = [
    ...source.matchAll(/PRODUCT_BUNDLE_IDENTIFIER\s*=\s*"?([^";]+)"?;/g),
  ]
    .map((match) => match[1].trim())
    .filter((value) => !value.includes('RunnerTests'));
  const uniqueValues = [...new Set(values)];
  if (uniqueValues.length !== 1) {
    throw new Error('Unable to determine one iOS application bundle ID.');
  }
  return uniqueValues[0];
}

function readGitSource() {
  const commit = spawnSync('git', ['rev-parse', 'HEAD'], {
    cwd: repositoryDirectory,
    encoding: 'utf8',
  });
  const status = spawnSync('git', ['status', '--porcelain'], {
    cwd: repositoryDirectory,
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
  });
  return {
    commit:
      commit.status === 0 && commit.stdout.trim()
        ? commit.stdout.trim()
        : null,
    dirty: status.status === 0 ? status.stdout.trim().length > 0 : null,
  };
}

function legacyJwtRole(value) {
  const parts = value.split('.');
  if (parts.length !== 3) return undefined;
  try {
    const payload = JSON.parse(
      Buffer.from(parts[1], 'base64url').toString('utf8'),
    );
    return payload?.role;
  } catch {
    return undefined;
  }
}

async function walkFiles(directory, files) {
  const entries = await readdir(directory, { withFileTypes: true });
  for (const entry of entries) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      await walkFiles(path, files);
    } else if (entry.isFile()) {
      files.push(path);
    }
  }
}

function isMainModule() {
  const entrypoint = process.argv[1];
  return entrypoint && import.meta.url === pathToFileURL(entrypoint).href;
}

function printUsage() {
  console.log(`Usage:
  node tool/build_mobile_release.mjs android [--apk-only|--appbundle-only] [Flutter arguments]
  node tool/build_mobile_release.mjs ios [--no-codesign] [Flutter arguments]

Examples:
  node tool/build_mobile_release.mjs android --dart-define-from-file=../mobile.public.json
  node tool/build_mobile_release.mjs ios --dart-define-from-file=../mobile.public.json
  node tool/build_mobile_release.mjs ios --no-codesign --dart-define-from-file=../mobile.public.json

FLUTTER_BIN may point to a non-default Flutter executable.`);
}

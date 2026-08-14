import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import {
  assertNoSecretShapedMarkers,
  findSecretShapedMarker,
  inspectPublicArtifact,
  parseAppVersion,
  parseMobileReleaseArguments,
  writePublicArtifactManifest,
} from './build_mobile_release.mjs';

function legacyKey(role) {
  const part = (value) =>
    Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${part({ alg: 'HS256' })}.${part({ role })}.signature-value`;
}

test('parses Android and iOS release wrapper arguments', () => {
  assert.deepEqual(
    parseMobileReleaseArguments([
      'android',
      '--apk-only',
      '--release',
      '--dart-define=APP_ENV=demo',
    ]),
    {
      help: false,
      platform: 'android',
      flutterArguments: ['--dart-define=APP_ENV=demo'],
      apkOnly: true,
      appBundleOnly: false,
      noCodesign: false,
    },
  );
  assert.deepEqual(
    parseMobileReleaseArguments([
      'ios',
      '--no-codesign',
      '--dart-define-from-file=../mobile.public.json',
    ]),
    {
      help: false,
      platform: 'ios',
      flutterArguments: [
        '--dart-define-from-file=../mobile.public.json',
      ],
      apkOnly: false,
      appBundleOnly: false,
      noCodesign: true,
    },
  );
  assert.throws(
    () => parseMobileReleaseArguments(['android', '--debug']),
    /release builds only/,
  );
});

test('detects actual secret shapes without rejecting validator vocabulary', () => {
  assert.equal(
    findSecretShapedMarker(
      'The app rejects sb_secret_ prefixes and service_role values.',
    ),
    null,
  );
  assertNoSecretShapedMarkers('No private credentials are present.');

  assert.match(
    findSecretShapedMarker(`sb_secret_${'a'.repeat(32)}`),
    /Supabase secret key/,
  );
  assert.match(
    findSecretShapedMarker(legacyKey('service_role')),
    /service-role JWT/,
  );
  assert.match(
    findSecretShapedMarker(
      `-----BEGIN PRIVATE KEY-----\n${'A'.repeat(64)}\n` +
        '-----END PRIVATE KEY-----',
    ),
    /private key block/,
  );
  assert.match(
    findSecretShapedMarker(
      `NOTIFICATION_DISPATCH_SECRET=${'x'.repeat(32)}`,
    ),
    /named server secret assignment/,
  );
});

test('parses the Flutter application version', () => {
  assert.deepEqual(
    parseAppVersion(`
name: animal_supply_b2b
description: test
version: 1.2.3+45
`),
    {
      app_name: 'animal_supply_b2b',
      version_name: '1.2.3',
      build_number: 45,
    },
  );
});

test('writes a public artifact manifest with exact size and SHA-256', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'animal-mobile-release-'));
  const artifactPath = join(directory, 'app-release.bin');
  const artifactData = Buffer.from('signed release artifact');
  await writeFile(artifactPath, artifactData);

  const artifact = await inspectPublicArtifact({
    type: 'test-artifact',
    path: artifactPath,
    rootDirectory: directory,
  });
  const manifestPath = await writePublicArtifactManifest({
    platform: 'android',
    appVersion: {
      app_name: 'animal_supply_b2b',
      version_name: '1.2.3',
      build_number: 45,
    },
    appEnvironment: 'production',
    packageIdentifier: 'ly.animalsupply.b2b',
    distribution: 'signed-android',
    artifacts: [artifact],
    source: { commit: 'abc123', dirty: false },
    outputDirectory: directory,
  });
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));

  assert.equal(manifest.version_name, '1.2.3');
  assert.equal(manifest.build_number, 45);
  assert.equal(manifest.package_identifier, 'ly.animalsupply.b2b');
  assert.equal(manifest.artifacts[0].file_size_bytes, artifactData.length);
  assert.equal(
    manifest.artifacts[0].sha256,
    createHash('sha256').update(artifactData).digest('hex'),
  );
  assert.equal(manifest.artifacts[0].relative_path, 'app-release.bin');
});

import assert from 'node:assert/strict';
import { mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import {
  assertPublicBuildConfiguration,
  readDartDefines,
} from './public_build_config.mjs';

function legacyKey(role) {
  const part = (value) =>
    Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${part({ alg: 'HS256' })}.${part({ role })}.signature`;
}

function productionDefines(overrides = {}) {
  return new Map(
    Object.entries({
      APP_ENV: 'production',
      SUPABASE_URL: 'https://client-project.supabase.co',
      SUPABASE_ANON_KEY: legacyKey('anon'),
      CUSTOMER_LOGIN_DOMAIN: 'accounts.client.ly',
      APP_PUBLIC_ORIGIN: 'https://shop.client.ly',
      FIREBASE_API_KEY: 'AIza-real-public-key',
      FIREBASE_PROJECT_ID: 'client-project',
      FIREBASE_MESSAGING_SENDER_ID: '1234567890',
      FIREBASE_WEB_APP_ID: '1:1234567890:web:abc123',
      FIREBASE_WEB_VAPID_KEY: 'public-vapid-key',
      ...overrides,
    }),
  );
}

function productionAndroidDefines(overrides = {}) {
  return new Map(
    Object.entries({
      APP_ENV: 'production',
      SUPABASE_URL: 'https://client-project.supabase.co',
      SUPABASE_ANON_KEY: legacyKey('anon'),
      CUSTOMER_LOGIN_DOMAIN: 'accounts.client.ly',
      APP_PUBLIC_ORIGIN: 'https://shop.client.ly',
      FIREBASE_API_KEY: 'AIza-real-public-key',
      FIREBASE_PROJECT_ID: 'client-project',
      FIREBASE_MESSAGING_SENDER_ID: '1234567890',
      FIREBASE_ANDROID_APP_ID: '1:1234567890:android:abc123',
      ...overrides,
    }),
  );
}

function productionIosDefines(overrides = {}) {
  return new Map(
    Object.entries({
      APP_ENV: 'production',
      SUPABASE_URL: 'https://client-project.supabase.co',
      SUPABASE_ANON_KEY: legacyKey('anon'),
      CUSTOMER_LOGIN_DOMAIN: 'accounts.client.ly',
      APP_PUBLIC_ORIGIN: 'https://shop.client.ly',
      FIREBASE_API_KEY: 'AIza-real-public-key',
      FIREBASE_PROJECT_ID: 'client-project',
      FIREBASE_MESSAGING_SENDER_ID: '1234567890',
      FIREBASE_IOS_APP_ID: '1:1234567890:ios:abc123',
      FIREBASE_IOS_BUNDLE_ID: 'ly.animalsupply.b2b',
      ...overrides,
    }),
  );
}

test('reads JSON and inline Dart defines with Flutter precedence', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'animal-build-config-'));
  await writeFile(
    join(directory, 'public.json'),
    JSON.stringify({
      APP_ENV: 'staging',
      SHOP_NAME: 'متجر العميل',
    }),
  );

  const values = await readDartDefines(
    [
      '--dart-define-from-file=public.json',
      '--dart-define=APP_ENV=production',
    ],
    directory,
  );

  assert.equal(values.get('SHOP_NAME'), 'متجر العميل');
  assert.equal(values.get('APP_ENV'), 'production');
});

test('accepts a complete public production web configuration', () => {
  assert.doesNotThrow(() =>
    assertPublicBuildConfiguration(productionDefines()),
  );
});

test('allows production when public Supabase is present and Firebase is omitted', () => {
  assert.doesNotThrow(() =>
    assertPublicBuildConfiguration(
      productionDefines({
        FIREBASE_API_KEY: '',
        FIREBASE_PROJECT_ID: '',
        FIREBASE_MESSAGING_SENDER_ID: '',
        FIREBASE_WEB_APP_ID: '',
        FIREBASE_WEB_VAPID_KEY: '',
      }),
    ),
  );
  assert.doesNotThrow(() =>
    assertPublicBuildConfiguration(
      productionAndroidDefines({
        FIREBASE_API_KEY: '',
        FIREBASE_PROJECT_ID: '',
        FIREBASE_MESSAGING_SENDER_ID: '',
        FIREBASE_ANDROID_APP_ID: '',
      }),
      { platform: 'android' },
    ),
  );
});

test('uses platform-specific production Firebase requirements for mobile', () => {
  assert.doesNotThrow(() =>
    assertPublicBuildConfiguration(productionAndroidDefines(), {
      platform: 'android',
    }),
  );
  assert.doesNotThrow(() =>
    assertPublicBuildConfiguration(productionIosDefines(), {
      platform: 'ios',
      expectedIosBundleId: 'ly.animalsupply.b2b',
    }),
  );

  assert.throws(
    () =>
      assertPublicBuildConfiguration(
        productionAndroidDefines({ FIREBASE_ANDROID_APP_ID: '' }),
        { platform: 'android' },
      ),
    /FIREBASE_ANDROID_APP_ID/,
  );
  assert.throws(
    () =>
      assertPublicBuildConfiguration(
        productionIosDefines({ FIREBASE_IOS_APP_ID: '' }),
        { platform: 'ios' },
      ),
    /FIREBASE_IOS_APP_ID/,
  );
  assert.throws(
    () =>
      assertPublicBuildConfiguration(
        productionIosDefines({
          FIREBASE_IOS_BUNDLE_ID: 'ly.other.application',
        }),
        {
          platform: 'ios',
          expectedIosBundleId: 'ly.animalsupply.b2b',
        },
      ),
    /must match/,
  );
});

test('rejects service-role and named server secrets in release arguments', () => {
  assert.throws(
    () =>
      assertPublicBuildConfiguration(
        productionDefines({ SUPABASE_ANON_KEY: legacyKey('service_role') }),
      ),
    /service-role/i,
  );
  assert.throws(
    () =>
      assertPublicBuildConfiguration(
        new Map([
          ['APP_ENV', 'demo'],
          ['FIREBASE_SERVICE_ACCOUNT_JSON', '{"private_key":"secret"}'],
        ]),
      ),
    /server secret/i,
  );
  assert.throws(
    () =>
      assertPublicBuildConfiguration(
        new Map([
          ['APP_ENV', 'demo'],
          ['UNEXPECTED_VALUE', legacyKey('service_role')],
        ]),
      ),
    /service-role/i,
  );
});

test('fails closed on incomplete or placeholder production values', () => {
  assert.throws(
    () =>
      assertPublicBuildConfiguration(
        productionDefines({ FIREBASE_WEB_VAPID_KEY: '' }),
      ),
    /FIREBASE_WEB_VAPID_KEY/,
  );
  assert.throws(
    () =>
      assertPublicBuildConfiguration(
        productionDefines({
          SUPABASE_URL: 'https://YOUR_PROJECT.supabase.co',
        }),
      ),
    /SUPABASE_URL/,
  );
});

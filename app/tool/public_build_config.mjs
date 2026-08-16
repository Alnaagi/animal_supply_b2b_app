import { readFile } from 'node:fs/promises';
import { extname, resolve } from 'node:path';

const forbiddenDefineName =
  /(SERVICE_ROLE|SERVICE_ACCOUNT|PRIVATE_KEY|DATABASE_URL|DB_PASSWORD|CLIENT_SECRET|SIGNING_PASSWORD|KEYSTORE_PASSWORD|STORE_PASSWORD|KEY_PASSWORD|NOTIFICATION_DISPATCH_SECRET|RATE_LIMIT_SALT)/i;

const productionCommonRequired = [
  'SUPABASE_URL',
  'SUPABASE_ANON_KEY',
  'CUSTOMER_LOGIN_DOMAIN',
  'APP_PUBLIC_ORIGIN',
];

const productionFirebaseRequired = {
  web: [
    'FIREBASE_API_KEY',
    'FIREBASE_PROJECT_ID',
    'FIREBASE_MESSAGING_SENDER_ID',
    'FIREBASE_WEB_APP_ID',
    'FIREBASE_WEB_VAPID_KEY',
  ],
  android: [
    'FIREBASE_API_KEY',
    'FIREBASE_PROJECT_ID',
    'FIREBASE_MESSAGING_SENDER_ID',
    'FIREBASE_ANDROID_APP_ID',
  ],
  ios: [
    'FIREBASE_API_KEY',
    'FIREBASE_PROJECT_ID',
    'FIREBASE_MESSAGING_SENDER_ID',
    'FIREBASE_IOS_APP_ID',
    'FIREBASE_IOS_BUNDLE_ID',
  ],
};

const supportedPublicBuildPlatforms = new Set([
  'web',
  'android',
  'ios',
]);

export async function readDartDefines(argumentsList, cwd) {
  const values = new Map();

  for (let index = 0; index < argumentsList.length; index += 1) {
    const argument = argumentsList[index];
    if (argument === '--dart-define') {
      const value = argumentsList[index + 1];
      if (!value) throw new Error('--dart-define requires KEY=VALUE.');
      applyDefine(values, value);
      index += 1;
      continue;
    }
    if (argument.startsWith('--dart-define=')) {
      applyDefine(values, argument.slice('--dart-define='.length));
      continue;
    }

    let filePath;
    if (argument === '--dart-define-from-file') {
      filePath = argumentsList[index + 1];
      if (!filePath) {
        throw new Error('--dart-define-from-file requires a file path.');
      }
      index += 1;
    } else if (argument.startsWith('--dart-define-from-file=')) {
      filePath = argument.slice('--dart-define-from-file='.length);
    }
    if (!filePath) continue;

    const absolutePath = resolve(cwd, filePath);
    const source = await readFile(absolutePath, 'utf8');
    const fileValues = parseDefineFile(source, extname(absolutePath));
    for (const [key, value] of Object.entries(fileValues)) {
      values.set(key, value);
    }
  }

  return values;
}

export function assertPublicBuildConfiguration(
  defines,
  {
    platform = 'web',
    expectedIosBundleId,
  } = {},
) {
  if (!supportedPublicBuildPlatforms.has(platform)) {
    throw new Error(`Unsupported public build platform: ${platform}`);
  }

  for (const [key, rawValue] of defines.entries()) {
    if (forbiddenDefineName.test(key)) {
      throw new Error(
        `Refusing to compile server secret ${key} into Flutter assets.`,
      );
    }
    const value = String(rawValue);
    if (legacyJwtRole(value.trim()) === 'service_role') {
      throw new Error(
        `Refusing to compile a service-role credential from ${key} into Flutter assets.`,
      );
    }
    if (
      /-----BEGIN (?:RSA |EC )?PRIVATE KEY-----/.test(value) ||
      /"private_key"\s*:/.test(value) ||
      value.trim().startsWith('sb_secret_')
    ) {
      throw new Error(
        `Refusing to compile server-secret material from ${key} into Flutter assets.`,
      );
    }
  }

  const supabaseKey = (defines.get('SUPABASE_ANON_KEY') ?? '').trim();
  if (supabaseKey) assertSupabasePublicKey(supabaseKey);

  const environment = (defines.get('APP_ENV') ?? 'demo')
    .trim()
    .toLowerCase();
  if (!['demo', 'staging', 'stage', 'production', 'prod'].includes(environment)) {
    throw new Error(
      'APP_ENV must be demo, staging, or production before release.',
    );
  }
  if (environment !== 'production' && environment !== 'prod') return;

  for (const key of productionCommonRequired) {
    const value = (defines.get(key) ?? '').trim();
    if (!value || looksLikePlaceholder(value)) {
      throw new Error(
        `Production ${platform} release requires a real public ${key} value.`,
      );
    }
  }

  assertProductionSupabaseUrl(defines.get('SUPABASE_URL'));
  assertSupabasePublicKey(defines.get('SUPABASE_ANON_KEY'));
  assertCustomerLoginDomain(defines.get('CUSTOMER_LOGIN_DOMAIN'));
  assertPublicAppOrigin(defines.get('APP_PUBLIC_ORIGIN'));
  assertOptionalProductionFirebase(defines, platform, expectedIosBundleId);
}

function hasConfiguredPublicValue(defines, key) {
  const value = (defines.get(key) ?? '').trim();
  return Boolean(value) && !looksLikePlaceholder(value);
}

function assertOptionalProductionFirebase(
  defines,
  platform,
  expectedIosBundleId,
) {
  const requiredFirebase = productionFirebaseRequired[platform];
  const configuredFirebase = requiredFirebase.filter((key) =>
    hasConfiguredPublicValue(defines, key),
  );
  if (configuredFirebase.length === 0) {
    return;
  }

  for (const key of requiredFirebase) {
    if (!hasConfiguredPublicValue(defines, key)) {
      throw new Error(
        `Production ${platform} Firebase public config is incomplete. ` +
          `Either omit Firebase keys (push not configured) or supply a real ${key}.`,
      );
    }
  }

  if (platform === 'ios') {
    assertIosBundleId(
      defines.get('FIREBASE_IOS_BUNDLE_ID'),
      expectedIosBundleId,
    );
  }
}

function applyDefine(values, source) {
  const separator = source.indexOf('=');
  if (separator < 1) {
    throw new Error(`Invalid --dart-define value: ${source}`);
  }
  values.set(source.slice(0, separator).trim(), source.slice(separator + 1));
}

function parseDefineFile(source, extension) {
  if (extension.toLowerCase() === '.json' || source.trimStart().startsWith('{')) {
    const parsed = JSON.parse(source);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error('Dart define JSON must contain one object.');
    }
    return Object.fromEntries(
      Object.entries(parsed).map(([key, value]) => {
        if (
          typeof value !== 'string' &&
          typeof value !== 'number' &&
          typeof value !== 'boolean'
        ) {
          throw new Error(`Dart define ${key} must be a scalar value.`);
        }
        return [key, String(value)];
      }),
    );
  }

  const parsed = {};
  for (const [lineIndex, rawLine] of source.split(/\r?\n/).entries()) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const separator = line.indexOf('=');
    if (separator < 1) {
      throw new Error(`Invalid define file line ${lineIndex + 1}.`);
    }
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if (
      value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'")))
    ) {
      value = value.slice(1, -1);
    }
    parsed[key] = value;
  }
  return parsed;
}

function assertProductionSupabaseUrl(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error('SUPABASE_URL must be a valid HTTPS URL.');
  }
  if (
    url.protocol !== 'https:' ||
    url.username ||
    url.password ||
    url.search ||
    url.hash ||
    isLocalOrPlaceholderHost(url.hostname)
  ) {
    throw new Error(
      'Production SUPABASE_URL must be a real HTTPS project URL without credentials, query, or fragment.',
    );
  }
}

function assertSupabasePublicKey(value = '') {
  const key = value.trim();
  if (key.startsWith('sb_secret_')) {
    throw new Error(
      'Refusing to compile a Supabase secret key. Use anon/publishable only.',
    );
  }
  if (key.startsWith('sb_publishable_')) {
    if (key.length < 24 || looksLikePlaceholder(key)) {
      throw new Error('SUPABASE_ANON_KEY is not a valid publishable key.');
    }
    return;
  }

  const role = legacyJwtRole(key);
  if (role === 'service_role') {
    throw new Error(
      'Refusing to compile a Supabase service-role JWT into Flutter assets.',
    );
  }
  if (role !== 'anon') {
    throw new Error(
      'SUPABASE_ANON_KEY must be an anon JWT or publishable public key.',
    );
  }
}

function legacyJwtRole(key) {
  const parts = key.split('.');
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

function assertCustomerLoginDomain(value = '') {
  const domain = value.trim().toLowerCase();
  const valid =
    /^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/.test(
      domain,
    );
  if (!valid || isLocalOrPlaceholderHost(domain)) {
    throw new Error(
      'CUSTOMER_LOGIN_DOMAIN must be a real client-controlled DNS domain.',
    );
  }
}

function assertPublicAppOrigin(value = '') {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error('APP_PUBLIC_ORIGIN must be a valid HTTPS origin.');
  }
  if (
    url.protocol !== 'https:' ||
    url.username ||
    url.password ||
    url.search ||
    url.hash ||
    (url.pathname && url.pathname !== '/') ||
    isLocalOrPlaceholderHost(url.hostname)
  ) {
    throw new Error(
      'APP_PUBLIC_ORIGIN must be a real HTTPS origin without path, credentials, query, or fragment.',
    );
  }
}

function assertIosBundleId(value = '', expectedValue) {
  const bundleId = value.trim();
  const valid =
    /^(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,62})?\.)+[A-Za-z0-9](?:[A-Za-z0-9-]{0,62})?$/
      .test(bundleId);
  if (!valid || looksLikePlaceholder(bundleId)) {
    throw new Error(
      'FIREBASE_IOS_BUNDLE_ID must be a real reverse-DNS bundle identifier.',
    );
  }
  if (expectedValue && bundleId !== expectedValue.trim()) {
    throw new Error(
      `FIREBASE_IOS_BUNDLE_ID must match the iOS application bundle ID ${expectedValue}.`,
    );
  }
}

function isLocalOrPlaceholderHost(host) {
  const normalized = host.toLowerCase();
  return (
    normalized === 'localhost' ||
    normalized === '127.0.0.1' ||
    normalized === '::1' ||
    normalized.endsWith('.localhost') ||
    normalized.endsWith('.invalid') ||
    normalized.endsWith('.example') ||
    normalized === 'example.com' ||
    normalized === 'example.net' ||
    normalized === 'example.org' ||
    normalized.includes('your_project')
  );
}

function looksLikePlaceholder(value) {
  const normalized = value.trim().toLowerCase();
  return (
    normalized.includes('your_') ||
    normalized.includes('replace_me') ||
    normalized.includes('xxxxxxxx') ||
    normalized.includes('<') ||
    normalized.includes('>')
  );
}

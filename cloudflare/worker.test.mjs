import assert from 'node:assert/strict';
import test from 'node:test';

import worker from './worker.mjs';

function environment(overrides = {}) {
  const assets = new Map([
    [
      '/',
      new Response('<!doctype html><html lang="ar"></html>', {
        headers: { 'Content-Type': 'text/html; charset=utf-8' },
      }),
    ],
    [
      '/main.dart.js',
      new Response('console.log("app");', {
        headers: { 'Content-Type': 'text/javascript' },
      }),
    ],
    [
      '/pwa_install.js',
      new Response('console.log("install");', {
        headers: { 'Content-Type': 'text/javascript' },
      }),
    ],
    [
      '/manifest.json',
      new Response(
        JSON.stringify({
          name: 'المتجر',
          short_name: 'المتجر',
          start_url: '/',
          display: 'standalone',
          icons: [
            {
              src: '/icons/Icon-192.png',
              sizes: '192x192',
              type: 'image/png',
            },
          ],
        }),
        {
          headers: {
            'Content-Type': 'application/manifest+json',
            ETag: '"manifest-v1"',
          },
        },
      ),
    ],
  ]);

  return {
    ...overrides,
    ASSETS: {
      async fetch(request) {
        const url = new URL(request.url);
        if (
          url.pathname === '/manifest.json' &&
          request.headers.get('If-None-Match') === '"manifest-v1"'
        ) {
          return new Response(null, {
            status: 304,
            headers: { ETag: '"manifest-v1"' },
          });
        }
        const response = assets.get(url.pathname);
        return response?.clone() ?? new Response('Not Found', { status: 404 });
      },
    },
  };
}

test('serves Android a browser-only manifest to prevent WebAPK installs', async () => {
  const response = await worker.fetch(
    new Request('https://example.com/manifest.json', {
      headers: {
        'If-None-Match': '"manifest-v1"',
        'User-Agent':
          'Mozilla/5.0 (Linux; Android 16; Pixel 10) '
          + 'AppleWebKit/537.36 Chrome/140 Mobile Safari/537.36',
      },
    }),
    environment(),
  );

  assert.equal(response.status, 200);
  assert.equal(response.headers.get('X-Android-Install-Mode'), 'browser-only');
  assert.equal(response.headers.get('ETag'), null);
  assert.equal(response.headers.get('Vary'), 'User-Agent');
  assert.equal(
    response.headers.get('Cache-Control'),
    'no-cache, no-store, must-revalidate',
  );
  assert.match(
    response.headers.get('Content-Type') ?? '',
    /application\/manifest\+json/,
  );
  assert.deepEqual(await response.json(), {
    name: 'المتجر',
    short_name: 'المتجر',
    start_url: '/',
    display: 'browser',
    icons: [],
    prefer_related_applications: false,
  });
});

test('preserves the installable manifest for non-Android browsers', async () => {
  const response = await worker.fetch(
    new Request('https://example.com/manifest.json', {
      headers: {
        'User-Agent':
          'Mozilla/5.0 (X11; Linux x86_64) '
          + 'AppleWebKit/537.36 Chrome/140 Safari/537.36',
      },
    }),
    environment(),
  );

  assert.equal(response.status, 200);
  assert.equal(response.headers.get('X-Android-Install-Mode'), null);
  const manifest = await response.json();
  assert.equal(manifest.display, 'standalone');
  assert.equal(manifest.icons.length, 1);
});

test('redirects cleartext requests to HTTPS', async () => {
  const response = await worker.fetch(
    new Request('http://example.com/admin/orders?order=o1001'),
    environment(),
  );

  assert.equal(response.status, 308);
  assert.equal(
    response.headers.get('Location'),
    'https://example.com/admin/orders?order=o1001',
  );
});

test('allows local HTTP development', async () => {
  const response = await worker.fetch(
    new Request('http://localhost/admin/orders', {
      headers: { Accept: 'text/html' },
    }),
    environment(),
  );

  assert.equal(response.status, 200);
});

test('serves a client route from the Flutter entry point', async () => {
  const response = await worker.fetch(
    new Request('https://example.com/admin/orders', {
      headers: { Accept: 'text/html' },
    }),
    environment(),
  );

  assert.equal(response.status, 200);
  assert.match(await response.text(), /lang="ar"/);
  assert.equal(response.headers.get('X-Frame-Options'), 'DENY');
  assert.match(
    response.headers.get('Content-Security-Policy') ?? '',
    /frame-ancestors 'none'/,
  );
  assert.match(
    response.headers.get('Content-Security-Policy') ?? '',
    /connect-src 'self' blob: https: wss:/,
  );
  assert.equal(
    response.headers.get('Strict-Transport-Security'),
    'max-age=31536000',
  );
  assert.equal(
    response.headers.get('X-Robots-Tag'),
    'noindex, nofollow, noarchive',
  );
});

test('allows indexing only after explicit custom-domain opt in', async () => {
  const customDomain = await worker.fetch(
    new Request('https://shop.client.ly/', {
      headers: { Accept: 'text/html' },
    }),
    environment({ ALLOW_INDEXING: 'true' }),
  );
  const reviewDomain = await worker.fetch(
    new Request('https://animal-supply-b2b.workers.dev/', {
      headers: { Accept: 'text/html' },
    }),
    environment({ ALLOW_INDEXING: 'true' }),
  );

  assert.equal(customDomain.headers.get('X-Robots-Tag'), null);
  assert.equal(
    reviewDomain.headers.get('X-Robots-Tag'),
    'noindex, nofollow, noarchive',
  );
});

test('does not turn a missing static file into HTML', async () => {
  const response = await worker.fetch(
    new Request('https://example.com/missing.js', {
      headers: { Accept: '*/*' },
    }),
    environment(),
  );

  assert.equal(response.status, 404);
  assert.equal(await response.text(), 'Not Found');
  assert.equal(
    response.headers.get('Cache-Control'),
    'no-cache, no-store, must-revalidate',
  );
});

test('keeps unversioned JavaScript fresh', async () => {
  for (const path of ['/main.dart.js', '/pwa_install.js']) {
    const response = await worker.fetch(
      new Request(`https://example.com${path}`),
      environment(),
    );

    assert.equal(response.status, 200);
    assert.equal(
      response.headers.get('Cache-Control'),
      'no-cache, no-store, must-revalidate',
    );
  }
});

test('keeps the PWA install bridge fresh', async () => {
  const response = await worker.fetch(
    new Request('https://example.com/pwa_install.js'),
    environment(),
  );

  assert.equal(response.status, 200);
  assert.equal(response.headers.get('Content-Type'), 'text/javascript');
  assert.equal(
    response.headers.get('Cache-Control'),
    'no-cache, no-store, must-revalidate',
  );
});

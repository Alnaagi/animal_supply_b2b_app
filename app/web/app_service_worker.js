'use strict';

const SHELL_CACHE_PREFIX = 'animal-supply-shell-';
const SHELL_READY_MARKER = '__animal_supply_shell_ready__';
const DEFAULT_SHELL_MANIFEST = 'web_shell_manifest.json';
const NETWORK_TIMEOUT_MS = 12000;
const CACHE_BATCH_SIZE = 6;

let shellPreparation;

self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  // Keep the last complete shell until a new complete shell is prepared.
  event.waitUntil(self.clients.claim());
});

self.addEventListener('message', (event) => {
  if (event.data?.type !== 'CACHE_APP_SHELL') return;

  event.waitUntil(
    prepareAppShell(event.data.manifestUrl)
      .then((result) => {
        event.source?.postMessage({
          type: 'APP_SHELL_CACHE_STATUS',
          ok: true,
          version: result.version,
          resourceCount: result.resourceCount,
        });
      })
      .catch((error) => {
        console.warn('App shell cache preparation failed.', error);
        event.source?.postMessage({
          type: 'APP_SHELL_CACHE_STATUS',
          ok: false,
        });
      }),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (!isInServiceWorkerScope(url)) return;

  if (request.mode === 'navigate') {
    event.respondWith(networkFirstNavigation(request));
    return;
  }

  event.respondWith(networkFirstResource(request));
});

async function prepareAppShell(manifestPath = DEFAULT_SHELL_MANIFEST) {
  if (shellPreparation) return shellPreparation;
  shellPreparation = prepareAppShellOnce(manifestPath).finally(() => {
    shellPreparation = null;
  });
  return shellPreparation;
}

async function prepareAppShellOnce(manifestPath) {
  const manifestUrl = scopedUrl(manifestPath || DEFAULT_SHELL_MANIFEST);
  const manifestResponse = await fetch(manifestUrl, {
    cache: 'no-store',
    credentials: 'same-origin',
  });
  if (!manifestResponse.ok) {
    throw new Error(`Shell manifest returned ${manifestResponse.status}.`);
  }

  const manifest = await manifestResponse.json();
  const version = normalizeVersion(manifest?.version);
  const resources = normalizeResources(manifest?.resources);
  assertRequiredResources(resources);

  const cacheName = `${SHELL_CACHE_PREFIX}${version}`;
  const existing = await caches.open(cacheName);
  if (await existing.match(shellReadyMarkerRequest())) {
    await deleteOtherShellCaches(cacheName);
    return { version, resourceCount: resources.length };
  }

  // A cache without the ready marker is an interrupted staging cache.
  await caches.delete(cacheName);
  const stagingCache = await caches.open(cacheName);

  try {
    for (let offset = 0; offset < resources.length; offset += CACHE_BATCH_SIZE) {
      const batch = resources.slice(offset, offset + CACHE_BATCH_SIZE);
      await Promise.all(
        batch.map(async (resource) => {
          const url = scopedUrl(resource);
          // Cloudflare canonicalizes /index.html to /. Fetch the canonical URL
          // but keep index.html as the cache key used by offline navigation.
          const fetchUrl =
            resource === 'index.html' ? self.registration.scope : url;
          const request = new Request(fetchUrl, {
            cache: 'reload',
            credentials: 'same-origin',
          });
          const response = await fetch(request);
          if (!response.ok) {
            throw new Error(`${resource} returned ${response.status}.`);
          }
          await stagingCache.put(url, response);
        }),
      );
    }

    await stagingCache.put(
      shellReadyMarkerRequest(),
      new Response(version, {
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      }),
    );
  } catch (error) {
    await caches.delete(cacheName);
    throw error;
  }

  // Only remove the previous shell after every new resource is safely cached.
  await deleteOtherShellCaches(cacheName);
  return { version, resourceCount: resources.length };
}

async function networkFirstNavigation(request) {
  try {
    const response = await fetchWithTimeout(request);
    if (response.ok) return response;
    return (await matchCompleteShell('index.html')) ?? response;
  } catch (_) {
    return (
      (await matchCompleteShell('index.html')) ??
      new Response('التطبيق غير متاح دون اتصال قبل اكتمال التحميل الأول.', {
        status: 503,
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      })
    );
  }
}

async function networkFirstResource(request) {
  try {
    const response = await fetchWithTimeout(request);
    if (response.ok) return response;
    return (await matchCompleteShell(request)) ?? response;
  } catch (_) {
    return (
      (await matchCompleteShell(request)) ??
      new Response('', {
        status: 503,
        statusText: 'Offline resource unavailable',
      })
    );
  }
}

async function fetchWithTimeout(request) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), NETWORK_TIMEOUT_MS);
  try {
    return await fetch(request, { signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

async function matchCompleteShell(requestOrPath) {
  const request =
    typeof requestOrPath === 'string'
      ? new Request(scopedUrl(requestOrPath))
      : requestOrPath;
  const cacheNames = await orderedShellCacheNames();

  for (const cacheName of cacheNames) {
    const cache = await caches.open(cacheName);
    const response = await cache.match(request, { ignoreSearch: true });
    if (response) return response;
  }
  return undefined;
}

async function orderedShellCacheNames() {
  const cacheNames = (await caches.keys()).filter((key) =>
    key.startsWith(SHELL_CACHE_PREFIX),
  );
  const complete = [];
  const legacyOrIncomplete = [];

  for (const cacheName of cacheNames.reverse()) {
    const cache = await caches.open(cacheName);
    if (await cache.match(shellReadyMarkerRequest())) {
      complete.push(cacheName);
    } else {
      // Older releases did not write a ready marker. Keep them as a final
      // fallback during the one-time upgrade to the atomic cache.
      legacyOrIncomplete.push(cacheName);
    }
  }
  return [...complete, ...legacyOrIncomplete];
}

async function deleteOtherShellCaches(currentCacheName) {
  const keys = await caches.keys();
  await Promise.all(
    keys
      .filter(
        (key) =>
          key.startsWith(SHELL_CACHE_PREFIX) && key !== currentCacheName,
      )
      .map((key) => caches.delete(key)),
  );
}

function shellReadyMarkerRequest() {
  return new Request(scopedUrl(SHELL_READY_MARKER));
}

function scopedUrl(path) {
  if (typeof path !== 'string' || path.trim().length === 0) {
    throw new Error('Invalid shell resource path.');
  }
  const url = new URL(path.replace(/^\.?\//, ''), self.registration.scope);
  if (!isInServiceWorkerScope(url)) {
    throw new Error('Shell resource is outside the application scope.');
  }
  return url;
}

function isInServiceWorkerScope(url) {
  const scope = new URL(self.registration.scope);
  return url.origin === scope.origin && url.pathname.startsWith(scope.pathname);
}

function normalizeVersion(value) {
  const version = typeof value === 'string' ? value.trim() : '';
  if (!/^[A-Za-z0-9._-]{8,128}$/.test(version)) {
    throw new Error('Invalid shell manifest version.');
  }
  return version;
}

function normalizeResources(value) {
  if (!Array.isArray(value) || value.length === 0 || value.length > 5000) {
    throw new Error('Invalid shell resource list.');
  }
  return [
    ...new Set(
      value.map((resource) => {
        if (
          typeof resource !== 'string' ||
          resource.length === 0 ||
          resource.length > 500 ||
          resource.includes('\\') ||
          resource.startsWith('/') ||
          resource.includes('..')
        ) {
          throw new Error('Invalid shell resource entry.');
        }
        return resource;
      }),
    ),
  ];
}

function assertRequiredResources(resources) {
  for (const required of [
    'index.html',
    'flutter_bootstrap.js',
    'flutter.js',
    'main.dart.js',
    'manifest.json',
    'pwa_install.js',
  ]) {
    if (!resources.includes(required)) {
      throw new Error(`Shell manifest is missing ${required}.`);
    }
  }
}

self.addEventListener('push', (event) => {
  let message = {};
  try {
    message = event.data ? event.data.json() : {};
  } catch (_) {
    message = { notification: { body: event.data?.text() ?? '' } };
  }

  const notification = message.notification ?? {};
  const data = message.data ?? {};
  const title = notification.title ?? data.title ?? 'إشعار جديد';
  const body = notification.body ?? data.body ?? '';
  const target = pushNotificationTarget(data);

  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      icon: 'icons/Icon-192.png',
      badge: 'icons/Icon-192.png',
      data: { target },
      dir: 'rtl',
      lang: 'ar',
    }),
  );
});

function pushNotificationTarget(rawData) {
  if (!rawData || typeof rawData !== 'object' || Array.isArray(rawData)) {
    return '/';
  }

  const role = normalizedPushRole(
    rawData.recipient_role ?? rawData.role,
  );
  const type = normalizedPushValue(rawData.type, 64);
  const adminLike =
    role === 'admin' ||
    role === 'staff' ||
    (role === '' && type === 'new_order');
  const orderId = normalizedPushValue(rawData.order_id, 200);
  if (orderId) {
    const path = adminLike ? '/admin/orders' : '/orders';
    return `${path}?order=${encodeURIComponent(orderId)}&from_push=1`;
  }

  const productId = normalizedPushValue(rawData.product_id, 200);
  if (productId) {
    return adminLike
      ? '/admin/products'
      : `/product/${encodeURIComponent(productId)}?from_push=1`;
  }
  return '/';
}

function normalizedPushRole(value) {
  const role = normalizedPushValue(value, 16).toLowerCase();
  return role === 'admin' || role === 'staff' || role === 'customer'
    ? role
    : '';
}

function normalizedPushValue(value, maxLength) {
  if (typeof value !== 'string') return '';
  const normalized = value.trim();
  if (
    normalized.length === 0 ||
    normalized.length > maxLength ||
    /[\u0000-\u001f\u007f]/.test(normalized)
  ) {
    return '';
  }
  return normalized;
}

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = event.notification.data?.target ?? '/';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(
      (clients) => {
        for (const client of clients) {
          if ('focus' in client) {
            client.navigate(target);
            return client.focus();
          }
        }
        return self.clients.openWindow(target);
      },
    ),
  );
});

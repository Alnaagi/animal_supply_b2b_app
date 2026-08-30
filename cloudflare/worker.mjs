const CONTENT_SECURITY_POLICY = [
  "default-src 'self'",
  "base-uri 'self'",
  "object-src 'none'",
  "frame-ancestors 'none'",
  "form-action 'self'",
  "script-src 'self' https://www.gstatic.com 'wasm-unsafe-eval'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob: https:",
  "font-src 'self' data:",
  "connect-src 'self' blob: https: wss:",
  "worker-src 'self' blob:",
  "child-src 'self' blob:",
  "manifest-src 'self'",
  "media-src 'self' blob: https:",
  'upgrade-insecure-requests',
].join('; ');

const NO_CACHE_PATHS = new Set([
  '/app_service_worker.js',
  '/firebase_bootstrap.js',
  '/flutter_bootstrap.js',
  '/main.dart.js',
  '/manifest.json',
  '/pwa_install.js',
  '/version.json',
]);

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.protocol !== 'https:' && !isLocalHostname(url.hostname)) {
      url.protocol = 'https:';
      return new Response(null, {
        status: 308,
        headers: {
          Location: url.toString(),
          'Cache-Control': 'public, max-age=86400',
        },
      });
    }

    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return secureResponse(
        new Response('Method Not Allowed', {
          status: 405,
          headers: { Allow: 'GET, HEAD' },
        }),
        request,
        url,
        env,
      );
    }

    const androidManifestRequest =
      request.method === 'GET' &&
      url.pathname === '/manifest.json' &&
      isAndroidRequest(request);
    const assetRequest = androidManifestRequest
      ? withoutConditionalHeaders(request)
      : request;
    let response = await env.ASSETS.fetch(assetRequest);
    if (
      androidManifestRequest &&
      response.ok
    ) {
      response = await androidBrowserOnlyManifest(response);
    }
    if (response.status === 404 && isClientRoute(request, url)) {
      const indexUrl = new URL('/', url);
      response = await env.ASSETS.fetch(
        new Request(indexUrl, {
          method: request.method,
          headers: request.headers,
        }),
      );
    }

    return secureResponse(response, request, url, env);
  },
};

function isLocalHostname(hostname) {
  return (
    hostname === 'localhost' ||
    hostname === '127.0.0.1' ||
    hostname === '[::1]'
  );
}

function isAndroidRequest(request) {
  return /\bAndroid\b/i.test(request.headers.get('User-Agent') ?? '');
}

function withoutConditionalHeaders(request) {
  const headers = new Headers(request.headers);
  headers.delete('If-Modified-Since');
  headers.delete('If-None-Match');
  return new Request(request, { headers });
}

async function androidBrowserOnlyManifest(response) {
  try {
    const manifest = await response.json();
    manifest.display = 'browser';
    manifest.icons = [];
    manifest.prefer_related_applications = false;

    const headers = new Headers(response.headers);
    headers.delete('ETag');
    headers.set('Content-Type', 'application/manifest+json; charset=utf-8');
    headers.set('Vary', 'User-Agent');
    headers.set('X-Android-Install-Mode', 'browser-only');
    return new Response(JSON.stringify(manifest), {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
  } catch {
    return response;
  }
}

function isClientRoute(request, url) {
  const pathname = url.pathname;
  const finalSegment = pathname.split('/').pop() ?? '';

  if (
    pathname.startsWith('/assets/') ||
    pathname.startsWith('/canvaskit/') ||
    pathname.startsWith('/icons/') ||
    finalSegment.includes('.')
  ) {
    return false;
  }

  return (
    request.mode === 'navigate' ||
    request.headers.get('Accept')?.includes('text/html') === true ||
    finalSegment.length === 0 ||
    !finalSegment.includes('.')
  );
}

function secureResponse(response, request, url, env) {
  const headers = new Headers(response.headers);
  const contentType = headers.get('Content-Type') ?? '';

  headers.set('Content-Security-Policy', CONTENT_SECURITY_POLICY);
  headers.set('Strict-Transport-Security', 'max-age=31536000');
  headers.set('X-Content-Type-Options', 'nosniff');
  headers.set('X-Frame-Options', 'DENY');
  headers.set('Referrer-Policy', 'strict-origin-when-cross-origin');
  headers.set(
    'Permissions-Policy',
    'camera=(), microphone=(), geolocation=(), payment=()',
  );
  headers.set('Cross-Origin-Opener-Policy', 'same-origin');
  headers.set('Cross-Origin-Resource-Policy', 'same-origin');

  const indexingExplicitlyEnabled =
    env?.ALLOW_INDEXING === 'true' &&
    !url.hostname.endsWith('.workers.dev');
  if (!indexingExplicitlyEnabled) {
    headers.set('X-Robots-Tag', 'noindex, nofollow, noarchive');
  }

  if (
    contentType.includes('text/html') ||
    response.status >= 400 ||
    NO_CACHE_PATHS.has(url.pathname) ||
    /^\/web_shell_manifest(?:\.[a-f0-9]{16})?\.json$/.test(url.pathname)
  ) {
    headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
  }

  if (!headers.has('Content-Type') && url.pathname.endsWith('.frag')) {
    headers.set('Content-Type', 'application/octet-stream');
  } else if (
    !headers.has('Content-Type') &&
    url.pathname.endsWith('/assets/NOTICES')
  ) {
    headers.set('Content-Type', 'text/plain; charset=utf-8');
  }

  return new Response(request.method === 'HEAD' ? null : response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

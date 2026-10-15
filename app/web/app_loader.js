// Pre-Flutter branding, progress copy, and loader dismiss.
// Must be an external file: Cloudflare CSP blocks inline scripts.
(function initializeAppLoader(global) {
  'use strict';

  if (!global || global.animalSupplyHideLoader) return;

  var STATUS_LINES = [
    { min: 0, text: 'نحضّر المتجر ليك...' },
    { min: 12, text: 'نرتّب رفوف الأعلاف...' },
    { min: 24, text: 'نجمع أكياس العلف الطازج...' },
    { min: 36, text: 'نحدّث الأسعار بالجملة...' },
    { min: 48, text: 'نجهّز كتالوج المنتجات...' },
    { min: 60, text: 'نحضّر الطلبات السريعة...' },
    { min: 72, text: 'نضبط التوصيل...' },
    { min: 84, text: 'لمسة أخيرة قبل ما نفتح...' },
    { min: 94, text: 'تقريباً جاهزين...' },
    { min: 100, text: 'أهلاً بكم، تفضّلوا...' },
  ];

  function restoreShopBranding() {
    try {
      var name = global.localStorage.getItem('shop_branding.v1.name');
      if (name) {
        name = String(name).trim();
        if (name) {
          global.document.title = name;
          var appleTitle = global.document.querySelector(
            'meta[name="apple-mobile-web-app-title"]',
          );
          if (appleTitle) appleTitle.setAttribute('content', name);
        }
      }
      var logo = global.localStorage.getItem('shop_branding.v1.logo');
      if (logo) {
        logo = String(logo).trim();
        if (logo) {
          var favicons = global.document.querySelectorAll('link[rel*="icon"]');
          for (var i = 0; i < favicons.length; i++) {
            favicons[i].setAttribute('href', logo);
          }
          var appleIcons = global.document.querySelectorAll(
            'link[rel="apple-touch-icon"]',
          );
          for (var j = 0; j < appleIcons.length; j++) {
            appleIcons[j].setAttribute('href', logo);
          }
        }
      }
    } catch (_) {}
  }

  function applyCachedTheme(loader) {
    try {
      var theme = JSON.parse(
        global.localStorage.getItem('storefront_theme.v1') || 'null',
      );
      if (!theme || typeof theme !== 'object') return;
      var isHex = function (v) {
        return typeof v === 'string' && /^#[0-9A-Fa-f]{6}$/.test(v);
      };
      if (isHex(theme.backgroundColor)) {
        loader.style.setProperty('--loader-bg', theme.backgroundColor);
      }
      if (isHex(theme.primaryColor)) {
        loader.style.setProperty('--loader-paw', theme.primaryColor);
        var themeMeta = global.document.querySelector(
          'meta[name="theme-color"]',
        );
        if (themeMeta) themeMeta.setAttribute('content', theme.primaryColor);
      }
      if (isHex(theme.textColor)) {
        loader.style.setProperty('--loader-text', theme.textColor);
      }
    } catch (_) {}
  }

  function statusFor(percent) {
    var text = STATUS_LINES[0].text;
    for (var i = 0; i < STATUS_LINES.length; i++) {
      if (percent >= STATUS_LINES[i].min) text = STATUS_LINES[i].text;
    }
    return text;
  }

  restoreShopBranding();

  var loader = global.document.getElementById('app-loader');
  if (!loader) {
    global.animalSupplyHideLoader = function () {};
    global.animalSupplyLoaderProgress = function () {};
    return;
  }

  applyCachedTheme(loader);

  var percentEl = global.document.getElementById('app-loader-percent');
  var statusEl = global.document.getElementById('app-loader-status');
  var progress = 0;
  var target = 8;
  var finishing = false;
  var removed = false;
  var currentStatus = statusEl ? statusEl.textContent : '';
  var statusSwapTimer = null;
  var observer = null;
  var shownAt = Date.now();
  var minVisibleMs = 1200;
  var creepCap = 70;

  function renderPercent() {
    if (!percentEl) return;
    percentEl.textContent = Math.round(progress) + '%';
  }

  function renderStatus() {
    if (!statusEl) return;
    var next = statusFor(progress);
    if (next === currentStatus) return;
    currentStatus = next;
    statusEl.classList.add('is-fading');
    if (statusSwapTimer) global.clearTimeout(statusSwapTimer);
    statusSwapTimer = global.setTimeout(function () {
      statusEl.textContent = next;
      statusEl.classList.remove('is-fading');
    }, 220);
  }

  function setTarget(value) {
    var next = Math.max(0, Math.min(100, Number(value) || 0));
    if (next > target) target = next;
  }

  function tick() {
    if (removed) return;
    if (progress < target) {
      progress += Math.max(0.35, (target - progress) * 0.09);
      if (progress > target) progress = target;
    } else if (!finishing && progress < creepCap) {
      progress += 0.045;
      target = Math.min(creepCap, progress + 0.5);
    }
    renderPercent();
    renderStatus();
    if (finishing && progress >= 99.5) {
      dismissNow();
      return;
    }
    global.requestAnimationFrame(tick);
  }

  function dismissNow() {
    if (removed) return;
    removed = true;
    if (observer) {
      try {
        observer.disconnect();
      } catch (_) {}
      observer = null;
    }
    var wait = Math.max(0, minVisibleMs - (Date.now() - shownAt));
    global.setTimeout(function () {
      progress = 100;
      renderPercent();
      renderStatus();
      loader.classList.add('app-loader-done');
      loader.setAttribute('aria-hidden', 'true');
      global.setTimeout(function () {
        if (loader.parentNode) loader.parentNode.removeChild(loader);
      }, 420);
    }, wait);
  }

  function hide() {
    if (removed || finishing) return;
    finishing = true;
    creepCap = 100;
    setTarget(100);
  }

  function reportProgress(value) {
    if (removed || finishing) return;
    setTarget(value);
    if (value >= 80) creepCap = Math.max(creepCap, 92);
  }

  global.animalSupplyHideLoader = hide;
  global.animalSupplyLoaderProgress = reportProgress;

  global.addEventListener(
    'flutter-first-frame',
    function () {
      reportProgress(88);
    },
    { once: true },
  );

  if (typeof MutationObserver === 'function') {
    observer = new MutationObserver(function () {
      if (global.document.querySelector('flutter-view, flt-glass-pane')) {
        reportProgress(78);
      }
    });
    observer.observe(global.document.documentElement, {
      childList: true,
      subtree: true,
    });
  }

  // Watch script tags so progress feels tied to real boot work.
  var watched = ['flutter.js', 'main.dart.js', 'flutter_bootstrap.js'];
  for (var s = 0; s < watched.length; s++) {
    (function (name, bump) {
      var nodes = global.document.querySelectorAll('script[src*="' + name + '"]');
      for (var n = 0; n < nodes.length; n++) {
        if (nodes[n].complete || nodes[n].readyState === 'complete') {
          reportProgress(bump);
        } else {
          nodes[n].addEventListener(
            'load',
            function () {
              reportProgress(bump);
            },
            { once: true },
          );
        }
      }
    })(watched[s], 16 + s * 10);
  }

  // Safety: never leave the client stranded if boot hangs.
  global.setTimeout(hide, 28000);

  renderPercent();
  renderStatus();
  global.requestAnimationFrame(tick);
})(typeof window !== 'undefined' ? window : undefined);

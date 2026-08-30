(function initializeAnimalSupplyPwaInstall(global) {
  'use strict';

  if (!global || global.animalSupplyPwaInstall) return;

  const SHOP_NAME_KEY = 'shop_branding.v1.name';
  const SHOP_LOGO_KEY = 'shop_branding.v1.logo';
  const DISMISS_UNTIL_KEY = 'animal-supply-pwa-install-dismiss-until';
  const DISMISS_DURATION_MS = 7 * 24 * 60 * 60 * 1000;
  const DISPLAY_MODE_QUERY = '(display-mode: standalone)';
  const STATE_EVENT = 'animal-supply-pwa-install-state-changed';
  const BLOCKED_PATHS = new Set([
    '/invite',
    '/auth-loading',
    '/change-password',
  ]);

  let deferredPrompt = null;
  let appReady = false;
  let fallbackReady = false;
  let installedThisSession = false;
  let dismissedThisSession = false;
  let dialog = null;
  let showTimer = null;
  let promptInFlight = false;
  let previouslyFocused = null;

  const displayMode = safeMatchMedia(DISPLAY_MODE_QUERY);

  function safeMatchMedia(query) {
    try {
      return typeof global.matchMedia === 'function'
        ? global.matchMedia(query)
        : null;
    } catch (_) {
      return null;
    }
  }

  function isStandalone() {
    return (
      installedThisSession ||
      displayMode?.matches === true ||
      global.navigator?.standalone === true
    );
  }

  function platformInfo() {
    const navigator = global.navigator ?? {};
    const userAgent = String(navigator.userAgent ?? '');
    const platform = String(navigator.platform ?? '');
    const isAndroid = /Android/i.test(userAgent);
    const isAndroidChrome =
      isAndroid &&
      /Chrome\/[\d.]+/i.test(userAgent) &&
      !/(EdgA|OPR|SamsungBrowser|DuckDuckGo|YaBrowser|Vivaldi)/i.test(
        userAgent,
      );
    const isIpadDesktopMode =
      platform === 'MacIntel' && Number(navigator.maxTouchPoints ?? 0) > 1;
    const isIos = /iPad|iPhone|iPod/i.test(userAgent) || isIpadDesktopMode;
    const isSafari =
      /Safari/i.test(userAgent) &&
      !/(CriOS|FxiOS|EdgiOS|OPiOS|DuckDuckGo)/i.test(userAgent);
    return {
      isAndroid,
      isAndroidChrome,
      isIos,
      isIosSafari: isIos && isSafari,
      isMacSafari: !isIos && /Macintosh|Mac OS X/i.test(userAgent) && isSafari,
    };
  }

  function shopDisplayName() {
    try {
      const stored = String(global.localStorage?.getItem(SHOP_NAME_KEY) ?? '').trim();
      if (stored) return stored;
    } catch (_) {
      // Storage can be disabled in private or restricted browser contexts.
    }
    const title = String(global.document?.title ?? '').trim();
    if (title) return title;
    return 'المتجر';
  }

  function shopLogoUrl() {
    try {
      const stored = String(global.localStorage?.getItem(SHOP_LOGO_KEY) ?? '').trim();
      if (stored) return stored;
    } catch (_) {
      // Storage can be disabled in private or restricted browser contexts.
    }
    return 'icons/Icon-192.png';
  }

  function storedDismissalActive() {
    if (dismissedThisSession) return true;
    try {
      const rawValue = global.localStorage?.getItem(DISMISS_UNTIL_KEY);
      if (!rawValue) return false;
      const dismissUntil = Number(rawValue);
      if (Number.isFinite(dismissUntil) && dismissUntil > Date.now()) {
        return true;
      }
      global.localStorage?.removeItem(DISMISS_UNTIL_KEY);
    } catch (_) {
      // Storage can be disabled in private or restricted browser contexts.
    }
    return false;
  }

  function routeAllowsOffer() {
    const location = global.location;
    const pathname = String(location?.pathname ?? '/');
    const search = String(location?.search ?? '');
    return !BLOCKED_PATHS.has(pathname) && !/[?&]token=/.test(search);
  }

  function rememberDismissal() {
    dismissedThisSession = true;
    try {
      global.localStorage?.setItem(
        DISMISS_UNTIL_KEY,
        String(Date.now() + DISMISS_DURATION_MS),
      );
    } catch (_) {
      // The in-memory session flag still prevents repeated prompts.
    }
  }

  function clearDismissal() {
    dismissedThisSession = false;
    try {
      global.localStorage?.removeItem(DISMISS_UNTIL_KEY);
    } catch (_) {
      // Ignore unavailable storage.
    }
  }

  function getState() {
    const platform = platformInfo();
    const installed = isStandalone();
    const dismissed = storedDismissalActive();
    const canPrompt = !platform.isAndroid && deferredPrompt !== null;
    return {
      appReady,
      canPrompt,
      dismissed,
      installed,
      isAndroid: platform.isAndroid,
      isAndroidChrome: platform.isAndroidChrome,
      isIos: platform.isIos,
      isIosSafari: platform.isIosSafari,
      isMacSafari: platform.isMacSafari,
      shouldOffer:
        appReady &&
        !installed &&
        !dismissed &&
        routeAllowsOffer() &&
        (canPrompt || fallbackReady),
    };
  }

  function notifyStateChanged() {
    if (
      typeof global.dispatchEvent !== 'function' ||
      typeof global.CustomEvent !== 'function'
    ) {
      return;
    }
    global.dispatchEvent(
      new global.CustomEvent(STATE_EVENT, { detail: getState() }),
    );
  }

  function scheduleOffer() {
    if (showTimer !== null || !getState().shouldOffer) return;
    showTimer = global.setTimeout?.(() => {
      showTimer = null;
      showDialog();
    }, 650);
  }

  function createElement(tag, className, text) {
    const element = global.document.createElement(tag);
    if (className) element.className = className;
    if (text) element.textContent = text;
    return element;
  }

  function ensureStyles() {
    const document = global.document;
    if (!document || document.getElementById('animal-supply-pwa-install-style')) {
      return;
    }
    const style = document.createElement('style');
    style.id = 'animal-supply-pwa-install-style';
    style.textContent = `
      .animal-supply-pwa-install-overlay {
        position: fixed;
        inset: 0;
        z-index: 2147483000;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 20px;
        background: rgba(24, 39, 35, 0.56);
        backdrop-filter: blur(4px);
        direction: rtl;
        opacity: 0;
        transition: opacity 160ms ease;
      }

      .animal-supply-pwa-install-overlay[data-visible="true"] {
        opacity: 1;
      }

      .animal-supply-pwa-install-dialog {
        width: min(100%, 430px);
        box-sizing: border-box;
        border: 1px solid rgba(22, 138, 99, 0.22);
        border-radius: 24px;
        padding: 22px;
        background: #fffdf9;
        color: #18372e;
        box-shadow: 0 24px 70px rgba(12, 38, 30, 0.28);
        font-family: "Noto Sans Arabic", Tahoma, Arial, sans-serif;
        text-align: right;
        transform: translateY(10px) scale(0.98);
        transition: transform 160ms ease;
      }

      .animal-supply-pwa-install-overlay[data-visible="true"]
        .animal-supply-pwa-install-dialog {
        transform: translateY(0) scale(1);
      }

      .animal-supply-pwa-install-heading {
        display: flex;
        align-items: center;
        gap: 14px;
        margin-bottom: 14px;
      }

      .animal-supply-pwa-install-icon {
        width: 58px;
        height: 58px;
        flex: 0 0 58px;
        border-radius: 17px;
        object-fit: cover;
        background: #e3f2eb;
      }

      .animal-supply-pwa-install-title {
        margin: 0;
        color: #145c47;
        font-size: 1.3rem;
        font-weight: 900;
        line-height: 1.45;
      }

      .animal-supply-pwa-install-copy,
      .animal-supply-pwa-install-status {
        margin: 0;
        color: #425c54;
        font-size: 0.98rem;
        line-height: 1.8;
      }

      .animal-supply-pwa-install-steps {
        margin: 14px 0 0;
        padding: 12px 16px;
        border-radius: 15px;
        background: #edf7f2;
        color: #285847;
        font-weight: 700;
        line-height: 1.8;
      }

      .animal-supply-pwa-install-status {
        min-height: 0;
        margin-top: 10px;
        color: #9a4f18;
        font-weight: 700;
      }

      .animal-supply-pwa-install-actions {
        display: flex;
        gap: 10px;
        margin-top: 20px;
      }

      .animal-supply-pwa-install-button {
        min-height: 46px;
        border: 0;
        border-radius: 14px;
        padding: 10px 18px;
        font: inherit;
        font-weight: 900;
        cursor: pointer;
      }

      .animal-supply-pwa-install-button:focus-visible {
        outline: 3px solid rgba(22, 138, 99, 0.32);
        outline-offset: 2px;
      }

      .animal-supply-pwa-install-button[disabled] {
        cursor: wait;
        opacity: 0.68;
      }

      .animal-supply-pwa-install-primary {
        flex: 1;
        background: #168a63;
        color: white;
      }

      .animal-supply-pwa-install-secondary {
        background: #edf2ef;
        color: #36564c;
      }

      @media (max-width: 520px) {
        .animal-supply-pwa-install-overlay {
          align-items: flex-end;
          padding: 12px;
        }

        .animal-supply-pwa-install-dialog {
          border-radius: 24px 24px 18px 18px;
          padding: 20px;
        }

        .animal-supply-pwa-install-actions {
          flex-direction: column;
        }
      }

      @media (prefers-reduced-motion: reduce) {
        .animal-supply-pwa-install-overlay,
        .animal-supply-pwa-install-dialog {
          transition: none;
        }
      }
    `;
    document.head?.appendChild(style);
  }

  function showDialog() {
    const document = global.document;
    const state = getState();
    if (!document?.body || dialog || !state.shouldOffer) return;

    ensureStyles();
    previouslyFocused = document.activeElement;

    const overlay = createElement(
      'div',
      'animal-supply-pwa-install-overlay',
    );
    overlay.id = 'pwa-install-dialog';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-labelledby', 'pwa-install-title');
    overlay.setAttribute('aria-describedby', 'pwa-install-description');

    const panel = createElement('section', 'animal-supply-pwa-install-dialog');
    const heading = createElement('div', 'animal-supply-pwa-install-heading');
    const icon = createElement('img', 'animal-supply-pwa-install-icon');
    icon.src = shopLogoUrl();
    icon.alt = '';
    icon.setAttribute('aria-hidden', 'true');
    const shopName = shopDisplayName();
    const titleText = state.isAndroid
      ? `أضف ${shopName} إلى هاتفك`
      : state.isIos
        ? `أضف ${shopName} إلى جهازك`
        : `ثبّت تطبيق ${shopName}`;
    const title = createElement(
      'h2',
      'animal-supply-pwa-install-title',
      titleText,
    );
    title.id = 'pwa-install-title';
    heading.append(icon, title);

    const descriptionText = state.isAndroid
      ? 'احفظ المتجر على الشاشة الرئيسية كتطبيق ويب فقط. لن يتم تنزيل أو تثبيت أي ملف APK.'
      : state.isIos
        ? `احفظ ${shopName} على الشاشة الرئيسية لفتحه بسرعة كتطبيق ويب.`
        : state.canPrompt
          ? 'أضف المتجر إلى جهازك لفتحه بسرعة من الشاشة الرئيسية واستخدامه كتطبيق ويب مستقل.'
          : `يمكنك تثبيت ${shopName} وفتحه من جهازك كتطبيق ويب مستقل.`;
    const description = createElement(
      'p',
      'animal-supply-pwa-install-copy',
      descriptionText,
    );
    description.id = 'pwa-install-description';

    panel.append(heading, description);

    if (state.isAndroidChrome) {
      panel.append(
        createElement(
          'p',
          'animal-supply-pwa-install-steps',
          'على Android في Chrome: اضغط قائمة ⋮، ثم اختر «إضافة إلى الشاشة الرئيسية»، وبعدها أكّد إضافة الاختصار.',
        ),
      );
    } else if (state.isAndroid) {
      panel.append(
        createElement(
          'p',
          'animal-supply-pwa-install-steps',
          'افتح هذا الموقع في Chrome، ثم اضغط قائمة ⋮ واختر «إضافة إلى الشاشة الرئيسية».',
        ),
      );
    } else if (state.isIosSafari && !state.canPrompt) {
      panel.append(
        createElement(
          'p',
          'animal-supply-pwa-install-steps',
          'على iPhone أو iPad: اضغط زر المشاركة، ثم اختر «إضافة إلى الشاشة الرئيسية»، وبعدها اضغط «إضافة».',
        ),
      );
    } else if (state.isIos && !state.canPrompt) {
      panel.append(
        createElement(
          'p',
          'animal-supply-pwa-install-steps',
          'على iPhone أو iPad: افتح هذا الموقع في Safari أولاً، ثم اضغط زر المشاركة واختر «إضافة إلى الشاشة الرئيسية».',
        ),
      );
    } else if (state.isMacSafari && !state.canPrompt) {
      panel.append(
        createElement(
          'p',
          'animal-supply-pwa-install-steps',
          'في Safari على Mac: افتح قائمة «ملف»، ثم اختر «إضافة إلى Dock».',
        ),
      );
    } else if (!state.canPrompt) {
      panel.append(
        createElement(
          'p',
          'animal-supply-pwa-install-steps',
          'إذا لم يظهر خيار التثبيت هنا، افتح الموقع في Chrome أو Edge، ثم اختر «تثبيت التطبيق» من قائمة المتصفح.',
        ),
      );
    }

    const status = createElement('p', 'animal-supply-pwa-install-status');
    status.setAttribute('aria-live', 'polite');
    panel.append(status);

    const actions = createElement(
      'div',
      'animal-supply-pwa-install-actions',
    );
    const laterButton = createElement(
      'button',
      'animal-supply-pwa-install-button animal-supply-pwa-install-secondary',
      state.canPrompt ? 'ليس الآن' : 'حسناً',
    );
    laterButton.id = 'pwa-install-later-button';
    laterButton.type = 'button';
    laterButton.addEventListener('click', dismiss);

    actions.append(laterButton);

    let installButton = null;
    if (state.canPrompt) {
      installButton = createElement(
        'button',
        'animal-supply-pwa-install-button animal-supply-pwa-install-primary',
        'تثبيت التطبيق',
      );
      installButton.id = 'pwa-install-button';
      installButton.type = 'button';
      installButton.addEventListener('click', async () => {
        installButton.disabled = true;
        status.textContent = '';
        const result = await promptInstall();
        if (result.outcome === 'error' && dialog === overlay) {
          installButton.disabled = true;
          status.textContent =
            'تعذر فتح نافذة التثبيت. استخدم خيار تثبيت التطبيق من قائمة المتصفح.';
        }
      });
      actions.prepend(installButton);
    }

    panel.append(actions);
    overlay.append(panel);
    overlay.addEventListener('click', (event) => {
      if (event.target === overlay) dismiss();
    });
    overlay.addEventListener('keydown', (event) => {
      if (event.key === 'Escape' && !promptInFlight) {
        event.preventDefault();
        dismiss();
      }
    });

    document.body.appendChild(overlay);
    dialog = overlay;
    global.requestAnimationFrame?.(() => {
      if (dialog === overlay) overlay.dataset.visible = 'true';
    });
    (installButton ?? laterButton).focus();
  }

  function closeDialog() {
    if (!dialog) return;
    const closingDialog = dialog;
    dialog = null;
    closingDialog.remove();
    if (previouslyFocused?.focus) previouslyFocused.focus();
    previouslyFocused = null;
  }

  function dismiss() {
    if (promptInFlight) return;
    rememberDismissal();
    closeDialog();
    notifyStateChanged();
  }

  async function promptInstall() {
    if (
      platformInfo().isAndroid ||
      promptInFlight ||
      deferredPrompt === null ||
      isStandalone()
    ) {
      return { outcome: 'unavailable' };
    }

    const promptEvent = deferredPrompt;
    deferredPrompt = null;
    promptInFlight = true;
    notifyStateChanged();

    try {
      const promptResult = promptEvent.prompt();
      await promptResult;
      const choice = await promptEvent.userChoice;
      const outcome =
        choice?.outcome === 'accepted' ? 'accepted' : 'dismissed';
      if (outcome === 'accepted') {
        installedThisSession = true;
        clearDismissal();
      } else {
        rememberDismissal();
      }
      closeDialog();
      notifyStateChanged();
      return { outcome };
    } catch (_) {
      notifyStateChanged();
      return { outcome: 'error' };
    } finally {
      promptInFlight = false;
    }
  }

  function markAppReady() {
    appReady = true;
    notifyStateChanged();
    scheduleOffer();
    global.setTimeout?.(() => {
      fallbackReady = true;
      notifyStateChanged();
      scheduleOffer();
    }, 2600);
  }

  function resetDismissal() {
    clearDismissal();
    notifyStateChanged();
    scheduleOffer();
  }

  global.addEventListener?.('beforeinstallprompt', (event) => {
    if (platformInfo().isAndroid) {
      event.preventDefault();
      deferredPrompt = null;
      notifyStateChanged();
      scheduleOffer();
      return;
    }
    if (isStandalone()) return;
    event.preventDefault();
    deferredPrompt = event;
    if (dialog) closeDialog();
    notifyStateChanged();
    scheduleOffer();
  });

  global.addEventListener?.('appinstalled', () => {
    installedThisSession = true;
    deferredPrompt = null;
    clearDismissal();
    closeDialog();
    notifyStateChanged();
  });

  const handleDisplayModeChange = () => {
    if (isStandalone()) {
      deferredPrompt = null;
      closeDialog();
    }
    notifyStateChanged();
  };
  displayMode?.addEventListener?.('change', handleDisplayModeChange);
  displayMode?.addListener?.(handleDisplayModeChange);

  global.animalSupplyPwaInstall = Object.freeze({
    dismiss,
    getState,
    markAppReady,
    prompt: promptInstall,
    resetDismissal,
    show: showDialog,
  });
})(window);

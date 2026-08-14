{{flutter_js}}
{{flutter_build_config}}

// The release preparation tool replaces this fallback with a content-hashed
// manifest name after Flutter finishes building.
const webShellManifestUrl = 'web_shell_manifest.json';

const waitForServiceWorkerActivation = (worker) => {
  if (!worker || worker.state === 'activated') return Promise.resolve();
  return new Promise((resolve) => {
    const timeout = setTimeout(resolve, 10000);
    worker.addEventListener('statechange', () => {
      if (worker.state === 'activated' || worker.state === 'redundant') {
        clearTimeout(timeout);
        resolve();
      }
    });
  });
};

const registerAndCacheAppShell = async () => {
  if (!('serviceWorker' in navigator)) return;

  try {
    const registration =
      await navigator.serviceWorker.register('app_service_worker.js');
    await waitForServiceWorkerActivation(
      registration.installing ?? registration.waiting,
    );
    const readyRegistration = await navigator.serviceWorker.ready;
    const worker =
      registration.active ??
      readyRegistration.active ??
      navigator.serviceWorker.controller;
    worker?.postMessage({
      type: 'CACHE_APP_SHELL',
      manifestUrl: webShellManifestUrl,
    });
  } catch (error) {
    console.warn('App service worker registration failed.', error);
  }
};

navigator.serviceWorker?.addEventListener('message', (event) => {
  if (
    event.data?.type === 'APP_SHELL_CACHE_STATUS' &&
    event.data?.ok === false
  ) {
    console.warn(
      'The full offline app shell could not be cached. Online use is unaffected.',
    );
  }
});

_flutter.loader.load({
  onEntrypointLoaded: async (engineInitializer) => {
    await (window.firebaseSdkReady ?? Promise.resolve());
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
    window.animalSupplyPwaInstall?.markAppReady();

    if (document.readyState === 'complete') {
      await registerAndCacheAppShell();
    } else {
      window.addEventListener('load', registerAndCacheAppShell, { once: true });
    }
  },
});

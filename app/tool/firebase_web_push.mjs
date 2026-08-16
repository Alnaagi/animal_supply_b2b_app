export function firebaseMessagingServiceWorkerPreamble(
  defines,
  sdkVersion = '12.15.0',
) {
  const apiKey = String(defines.get('FIREBASE_API_KEY') ?? '').trim();
  const projectId = String(defines.get('FIREBASE_PROJECT_ID') ?? '').trim();
  const messagingSenderId = String(
    defines.get('FIREBASE_MESSAGING_SENDER_ID') ?? '',
  ).trim();
  const appId = String(defines.get('FIREBASE_WEB_APP_ID') ?? '').trim();
  const authDomain = String(defines.get('FIREBASE_AUTH_DOMAIN') ?? '').trim();
  const storageBucket = String(
    defines.get('FIREBASE_STORAGE_BUCKET') ?? '',
  ).trim();
  if (!apiKey || !projectId || !messagingSenderId || !appId) {
    return '';
  }

  const config = {
    apiKey,
    projectId,
    messagingSenderId,
    appId,
    ...(authDomain ? { authDomain } : {}),
    ...(storageBucket ? { storageBucket } : {}),
  };
  const sdk = JSON.stringify(
    `https://www.gstatic.com/firebasejs/${sdkVersion}/`,
  );
  const firebaseConfig = JSON.stringify(config);

  return [
    "'use strict';",
    `importScripts(${sdk} + 'firebase-app-compat.js');`,
    `importScripts(${sdk} + 'firebase-messaging-compat.js');`,
    `firebase.initializeApp(${firebaseConfig});`,
    'self.__ANIMAL_SUPPLY_FCM_READY = true;',
    'firebase.messaging().onBackgroundMessage((payload) => {',
    '  const notification = payload && payload.notification ? payload.notification : {};',
    '  const data = payload && payload.data ? payload.data : {};',
    "  const title = notification.title || data.title || 'إشعار جديد';",
    "  const body = notification.body || data.body || '';",
    '  return self.registration.showNotification(title, {',
    '    body: body,',
    "    icon: 'icons/Icon-192.png',",
    "    badge: 'icons/Icon-192.png',",
    "    dir: 'rtl',",
    "    lang: 'ar',",
    '    data: data,',
    '  });',
    '});',
    '',
  ].join('\n');
}

import assert from 'node:assert/strict';
import test from 'node:test';

import { firebaseMessagingServiceWorkerPreamble } from './firebase_web_push.mjs';

test('omits Firebase messaging from the service worker when keys are empty', () => {
  const preamble = firebaseMessagingServiceWorkerPreamble(
    new Map([
      ['FIREBASE_API_KEY', ''],
      ['FIREBASE_PROJECT_ID', ''],
      ['FIREBASE_MESSAGING_SENDER_ID', ''],
      ['FIREBASE_WEB_APP_ID', ''],
    ]),
  );
  assert.equal(preamble, '');
});

test('injects public Firebase config into the service worker when keys exist', () => {
  const preamble = firebaseMessagingServiceWorkerPreamble(
    new Map([
      ['FIREBASE_API_KEY', 'AIza-public'],
      ['FIREBASE_PROJECT_ID', 'client-project'],
      ['FIREBASE_MESSAGING_SENDER_ID', '1234567890'],
      ['FIREBASE_WEB_APP_ID', '1:1234567890:web:abc123'],
      ['FIREBASE_AUTH_DOMAIN', 'client-project.firebaseapp.com'],
    ]),
  );
  assert.match(preamble, /firebase-messaging-compat\.js/);
  assert.match(preamble, /self\.__ANIMAL_SUPPLY_FCM_READY = true/);
  assert.match(preamble, /AIza-public/);
  assert.doesNotMatch(preamble, /private_key/);
});

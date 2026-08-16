import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';

const serviceWorkerUrl = new URL(
  '../web/app_service_worker.js',
  import.meta.url,
);
const source = await readFile(serviceWorkerUrl, 'utf8');
const sandbox = {
  AbortController,
  Request,
  Response,
  URL,
  clearTimeout,
  console,
  fetch,
  setTimeout,
  self: {
    addEventListener() {},
  },
};
vm.runInNewContext(
  source +
    '\nglobalThis.__pushNotificationTarget = pushNotificationTarget;' +
    '\nglobalThis.__safeNotificationTarget = safeNotificationTarget;',
  sandbox,
  { filename: serviceWorkerUrl.pathname },
);
const pushNotificationTarget = sandbox.__pushNotificationTarget;
const safeNotificationTarget = sandbox.__safeNotificationTarget;

test('routes admin and staff order pushes to the admin order screen', () => {
  for (const role of ['admin', 'staff']) {
    assert.equal(
      pushNotificationTarget({
        recipient_role: role,
        order_id: 'order-42',
      }),
      '/admin/orders?order=order-42&from_push=1',
    );
  }
});

test('keeps customer order pushes on the customer order screen', () => {
  assert.equal(
    pushNotificationTarget({
      recipient_role: 'customer',
      order_id: 'order-42',
    }),
    '/orders?order=order-42&from_push=1',
  );
});

test('uses the new-order type as a safe admin fallback for legacy payloads', () => {
  assert.equal(
    pushNotificationTarget({
      type: 'new_order',
      order_id: 'order-42',
    }),
    '/admin/orders?order=order-42&from_push=1',
  );
});

test('routes admin and staff product pushes to product management', () => {
  for (const role of ['admin', 'staff']) {
    assert.equal(
      pushNotificationTarget({
        recipient_role: role,
        product_id: 'product-7',
      }),
      '/admin/products',
    );
  }
});

test('keeps customer product pushes on the customer product page', () => {
  assert.equal(
    pushNotificationTarget({
      recipient_role: 'customer',
      product_id: 'product-7',
    }),
    '/product/product-7?from_push=1',
  );
});

test('encodes route identifiers before adding them to a target', () => {
  assert.equal(
    pushNotificationTarget({
      recipient_role: 'customer',
      order_id: ' order / 7?# ',
    }),
    '/orders?order=order%20%2F%207%3F%23&from_push=1',
  );
  assert.equal(
    pushNotificationTarget({
      recipient_role: 'customer',
      product_id: ' product/7?tab=price ',
    }),
    '/product/product%2F7%3Ftab%3Dprice?from_push=1',
  );
});

test('falls back to the app root for missing or unsafe target data', () => {
  for (const payload of [
    null,
    [],
    {},
    { order_id: 42 },
    { product_id: '\u0000unsafe' },
    { order_id: 'x'.repeat(201) },
  ]) {
    assert.equal(pushNotificationTarget(payload), '/');
  }
});

test('shows OS tray notifications from page messages without Firebase', () => {
  assert.match(source, /SHOW_OS_NOTIFICATION/);
  assert.match(source, /showOsTrayNotification/);
  assert.equal(
    safeNotificationTarget('/orders?order=1&from_push=1'),
    '/orders?order=1&from_push=1',
  );
  assert.equal(safeNotificationTarget('https://evil.example/x'), '/');
  assert.equal(safeNotificationTarget('//evil.example'), '/');
});

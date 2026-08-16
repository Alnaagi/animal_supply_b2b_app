import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';

const bridgeUrl = new URL('../web/pwa_install.js', import.meta.url);
const source = await readFile(bridgeUrl, 'utf8');

class FakeElement {
  constructor(tagName, document) {
    this.tagName = tagName.toUpperCase();
    this.ownerDocument = document;
    this.children = [];
    this.dataset = {};
    this.listeners = new Map();
    this.attributes = new Map();
    this.parentNode = null;
    this.textContent = '';
    this.className = '';
    this.disabled = false;
    this.id = '';
    this.type = '';
  }

  append(...children) {
    for (const child of children) this.appendChild(child);
  }

  appendChild(child) {
    child.parentNode = this;
    this.children.push(child);
    return child;
  }

  prepend(child) {
    child.parentNode = this;
    this.children.unshift(child);
  }

  addEventListener(type, listener) {
    const listeners = this.listeners.get(type) ?? [];
    listeners.push(listener);
    this.listeners.set(type, listeners);
  }

  dispatchEvent(event) {
    event.target ??= this;
    const results = [];
    for (const listener of this.listeners.get(event.type) ?? []) {
      results.push(listener(event));
    }
    return Promise.all(results);
  }

  click() {
    return this.dispatchEvent({ type: 'click', target: this });
  }

  focus() {
    this.ownerDocument.activeElement = this;
  }

  remove() {
    if (!this.parentNode) return;
    this.parentNode.children = this.parentNode.children.filter(
      (child) => child !== this,
    );
    this.parentNode = null;
  }

  setAttribute(name, value) {
    this.attributes.set(name, String(value));
  }

  getElementById(id) {
    if (this.id === id) return this;
    for (const child of this.children) {
      const found = child.getElementById(id);
      if (found) return found;
    }
    return null;
  }
}

class FakeDocument {
  constructor() {
    this.head = new FakeElement('head', this);
    this.body = new FakeElement('body', this);
    this.activeElement = null;
    this.title = '';
  }

  createElement(tagName) {
    return new FakeElement(tagName, this);
  }

  getElementById(id) {
    return this.head.getElementById(id) ?? this.body.getElementById(id);
  }
}

function createEnvironment({
  userAgent = 'Mozilla/5.0 Chrome/140 Safari/537.36',
  platform = 'Linux x86_64',
  standalone = false,
  pathname = '/login',
  search = '',
} = {}) {
  const listeners = new Map();
  const storage = new Map();
  const document = new FakeDocument();
  const media = {
    matches: standalone,
    addEventListener() {},
    addListener() {},
  };
  const window = {
    CustomEvent: class CustomEvent {
      constructor(type, options = {}) {
        this.type = type;
        this.detail = options.detail;
      }
    },
    Date,
    Promise,
    clearTimeout,
    console,
    document,
    localStorage: {
      getItem(key) {
        return storage.has(key) ? storage.get(key) : null;
      },
      removeItem(key) {
        storage.delete(key);
      },
      setItem(key, value) {
        storage.set(key, String(value));
      },
    },
    location: { pathname, search },
    matchMedia() {
      return media;
    },
    navigator: {
      maxTouchPoints: 0,
      platform,
      standalone,
      userAgent,
    },
    requestAnimationFrame(callback) {
      callback();
    },
    setTimeout(callback) {
      callback();
      return 1;
    },
    addEventListener(type, listener) {
      const current = listeners.get(type) ?? [];
      current.push(listener);
      listeners.set(type, current);
    },
    dispatchEvent(event) {
      for (const listener of listeners.get(event.type) ?? []) listener(event);
    },
  };
  window.window = window;

  vm.runInNewContext(source, { window }, { filename: bridgeUrl.pathname });
  return { document, storage, window };
}

function installEvent(outcome = 'accepted') {
  let prevented = false;
  let promptCalls = 0;
  return {
    get prevented() {
      return prevented;
    },
    get promptCalls() {
      return promptCalls;
    },
    preventDefault() {
      prevented = true;
    },
    prompt() {
      promptCalls += 1;
      return Promise.resolve();
    },
    type: 'beforeinstallprompt',
    userChoice: Promise.resolve({ outcome }),
  };
}

test('captures the install event before app startup and opens it once', async () => {
  const { document, window } = createEnvironment();
  const event = installEvent('accepted');

  window.dispatchEvent(event);
  assert.equal(event.prevented, true);
  assert.equal(window.animalSupplyPwaInstall.getState().canPrompt, true);
  assert.equal(document.getElementById('pwa-install-dialog'), null);

  window.animalSupplyPwaInstall.markAppReady();
  assert.ok(document.getElementById('pwa-install-dialog'));

  await document.getElementById('pwa-install-button').click();
  assert.equal(event.promptCalls, 1);
  assert.equal(window.animalSupplyPwaInstall.getState().installed, true);
  assert.equal(document.getElementById('pwa-install-dialog'), null);

  const secondResult = await window.animalSupplyPwaInstall.prompt();
  assert.equal(secondResult.outcome, 'unavailable');
  assert.equal(event.promptCalls, 1);
});

test('dismissal hides the offer for seven days without consuming the event', () => {
  const { document, storage, window } = createEnvironment();
  const event = installEvent();
  window.dispatchEvent(event);
  window.animalSupplyPwaInstall.markAppReady();

  document.getElementById('pwa-install-later-button').click();

  assert.equal(document.getElementById('pwa-install-dialog'), null);
  assert.equal(window.animalSupplyPwaInstall.getState().canPrompt, true);
  assert.equal(window.animalSupplyPwaInstall.getState().dismissed, true);
  assert.ok(storage.has('animal-supply-pwa-install-dismiss-until'));
});

test('shows iPhone Safari home-screen instructions without a fake install button', () => {
  const { document, window } = createEnvironment({
    userAgent:
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
      + 'AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1',
    platform: 'iPhone',
  });

  window.animalSupplyPwaInstall.markAppReady();

  assert.equal(window.animalSupplyPwaInstall.getState().isIosSafari, true);
  assert.ok(document.getElementById('pwa-install-dialog'));
  assert.equal(document.getElementById('pwa-install-button'), null);
  assert.match(
    document.getElementById('pwa-install-dialog').children[0].children[2]
      .textContent,
    /إضافة إلى الشاشة الرئيسية/,
  );
});

test('install copy uses the cached shop name when available', () => {
  const { document, storage, window } = createEnvironment();
  storage.set('shop_branding.v1.name', 'مؤسسة النور للأعلاف');
  window.animalSupplyPwaInstall.markAppReady();

  assert.ok(document.getElementById('pwa-install-dialog'));
  assert.match(
    document.getElementById('pwa-install-title').textContent,
    /ثبّت تطبيق مؤسسة النور للأعلاف/,
  );
  assert.match(
    document.getElementById('pwa-install-description').textContent,
    /يمكنك تثبيت مؤسسة النور للأعلاف/,
  );
});

test('shows supported-browser guidance when no native prompt is available', () => {
  const { document, window } = createEnvironment();

  window.animalSupplyPwaInstall.markAppReady();

  assert.ok(document.getElementById('pwa-install-dialog'));
  assert.equal(document.getElementById('pwa-install-button'), null);
  assert.match(
    document.getElementById('pwa-install-dialog').children[0].children[2]
      .textContent,
    /Chrome أو Edge/,
  );
});

test('suppresses the offer in standalone mode and protected invite flows', () => {
  const standalone = createEnvironment({ standalone: true });
  standalone.window.dispatchEvent(installEvent());
  standalone.window.animalSupplyPwaInstall.markAppReady();
  assert.equal(
    standalone.document.getElementById('pwa-install-dialog'),
    null,
  );
  assert.equal(
    standalone.window.animalSupplyPwaInstall.getState().installed,
    true,
  );

  const invite = createEnvironment({
    pathname: '/invite',
    search: '?token=one-time-token',
  });
  invite.window.dispatchEvent(installEvent());
  invite.window.animalSupplyPwaInstall.markAppReady();
  assert.equal(invite.document.getElementById('pwa-install-dialog'), null);
});

test('appinstalled clears the dialog and records installed state', () => {
  const { document, window } = createEnvironment();
  window.dispatchEvent(installEvent());
  window.animalSupplyPwaInstall.markAppReady();
  assert.ok(document.getElementById('pwa-install-dialog'));

  window.dispatchEvent({ type: 'appinstalled' });

  assert.equal(document.getElementById('pwa-install-dialog'), null);
  assert.equal(window.animalSupplyPwaInstall.getState().installed, true);
  assert.equal(window.animalSupplyPwaInstall.getState().canPrompt, false);
});

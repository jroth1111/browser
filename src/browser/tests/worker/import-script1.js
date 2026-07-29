postMessage('importScripts-1');
Promise.resolve().then(() => postMessage('importScripts-1-microtask'));

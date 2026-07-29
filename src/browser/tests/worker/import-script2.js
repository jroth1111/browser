postMessage('importScripts-2');
Promise.resolve().then(() => postMessage('importScripts-2-microtask'));

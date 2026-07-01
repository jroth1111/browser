// Exercises the WebSocket API inside a worker. Posts 'ready' once the message
// handler is wired so the page knows it can send a command without racing
// worker startup. On command, opens a WebSocket to the test echo server,
// sends a message, and reports the echoed reply plus the close code/reason
// back to the page.
self.onmessage = function(e) {
  const cmd = e.data;
  try {
    if (cmd.kind === 'echo') {
      const received = [];
      const ws = new WebSocket('ws://127.0.0.1:9584/');

      ws.addEventListener('open', () => {
        ws.send('from-worker');
      });

      ws.addEventListener('message', (ev) => {
        received.push(ev.data);
        ws.close(1000, 'bye');
      });

      ws.addEventListener('close', (ev) => {
        postMessage({
          ok: true,
          received,
          url: ws.url,
          ready_state: ws.readyState,
          code: ev.code,
          reason: ev.reason,
          was_clean: ev.wasClean,
        });
      });

      ws.addEventListener('error', () => {
        postMessage({ ok: false, err: 'websocket error' });
      });
      return;
    }

    if (cmd.kind === 'fetch-metadata') {
      // Pins that the worker realm's WebSocket upgrade carries the same
      // Sec-Fetch-* triad as the main-frame realm — the header-building
      // path (WebSocket.zig init()) is shared code, not worker-specific,
      // but this closes the loop with an actual worker-realm assertion
      // rather than relying only on the frame-realm test plus this file's
      // separate plain echo test to infer parity.
      const received = [];
      const ws = new WebSocket('ws://127.0.0.1:9584/');

      let step = 0;
      ws.addEventListener('open', () => {
        ws.send('get-sec-fetch-mode');
      });

      ws.addEventListener('message', (ev) => {
        received.push(ev.data);
        step++;
        if (step === 1) ws.send('get-sec-fetch-dest');
        else if (step === 2) ws.send('get-sec-fetch-site');
        else ws.close();
      });

      ws.addEventListener('close', () => {
        postMessage({ ok: true, received });
      });

      ws.addEventListener('error', () => {
        postMessage({ ok: false, err: 'websocket error' });
      });
      return;
    }

    postMessage({ ok: false, err: 'unknown command' });
  } catch (err) {
    postMessage({ ok: false, err: String(err), stack: err.stack });
  }
};

postMessage({ ready: true });

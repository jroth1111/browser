// Exposes WorkerNavigator (navigator) inside a WorkerGlobalScope.
// Replies with either { ok: true, results: {...} } or { ok: false, err }.
onmessage = async function(event) {
  try {
    // Permissions (transitively reachable: navigator.permissions -> Permissions
    // -> PermissionStatus). Must not depend on a Frame.
    const status = await navigator.permissions.query({ name: 'geolocation' });

    // StorageManager (navigator.storage -> StorageManager -> StorageEstimate).
    const estimate = await navigator.storage.estimate();

    // NavigatorUAData (navigator.userAgentData -> getHighEntropyValues()).
    const ua = navigator.userAgentData;
    const high_entropy = ua ? await ua.getHighEntropyValues(['architecture']) : null;

    const results = {
      has_navigator: typeof navigator !== 'undefined',
      navigator_brand: Object.prototype.toString.call(navigator),
      constructor_name: navigator.constructor && navigator.constructor.name,
      has_worker_navigator_constructor: typeof WorkerNavigator === 'function',
      worker_navigator_instance: typeof WorkerNavigator === 'function' && navigator instanceof WorkerNavigator,
      navigator_prototype_absent: typeof Navigator === 'undefined',
      prototype_is_worker_navigator: typeof WorkerNavigator === 'function' && Object.getPrototypeOf(navigator) === WorkerNavigator.prototype,
      // userAgent must match the value the page sees (passed in via postMessage).
      user_agent: navigator.userAgent,
      user_agent_matches_page: navigator.userAgent === event.data.pageUserAgent,
      app_name: navigator.appName,
      platform: navigator.platform,
      platform_matches_page: navigator.platform === event.data.pagePlatform,
      on_line: navigator.onLine,
      // Cross-signal identity coherence: a same-origin worker spawned from a
      // secure-context page must itself report a secure context (both derive
      // from the same origin-trustworthiness algorithm, not independent
      // hardcoded values that can drift apart).
      is_secure_context: self.isSecureContext,
      is_secure_context_matches_page: self.isSecureContext === event.data.pageIsSecureContext,
      // SameObject: navigator should be stable across reads.
      identity_stable: navigator === navigator,

      // Permissions
      permission_name: status.name,
      permission_state: status.state,

      // StorageManager
      storage_quota: estimate.quota,
      storage_usage: estimate.usage,

      // NavigatorUAData
      has_ua_data: ua != null,
      ua_high_entropy_arch: high_entropy ? high_entropy.architecture : null,
      ua_data_brand: Object.prototype.toString.call(ua),
      ua_data_to_json_native: Function.prototype.toString.call(ua.toJSON).includes('[native code]'),
      ua_data_high_entropy_native: Function.prototype.toString.call(ua.getHighEntropyValues).includes('[native code]'),

      // [Exposed=Window] members must NOT leak into the worker realm.
      no_plugins: navigator.plugins === undefined,
      no_mime_types: navigator.mimeTypes === undefined,
      no_pdf_viewer_enabled: navigator.pdfViewerEnabled === undefined,
      no_geolocation: navigator.geolocation === undefined,
      no_media_devices: navigator.mediaDevices === undefined,
      no_webkit_temporary_storage: navigator.webkitTemporaryStorage === undefined,
      no_webkit_persistent_storage: navigator.webkitPersistentStorage === undefined,
      no_register_protocol_handler: navigator.registerProtocolHandler === undefined,
      no_unregister_protocol_handler: navigator.unregisterProtocolHandler === undefined,
      no_model_context: navigator.modelContext === undefined,
      no_send_beacon: navigator.sendBeacon === undefined,
    };
    postMessage({ ok: true, results });
  } catch (e) {
    postMessage({ ok: false, err: e.message });
  }
};

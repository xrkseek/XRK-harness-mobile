// Which conversation XRK Web shows, for the app (网页模式): the official
// client keeps its selection in localStorage (`xrk.sessions.current`; legacy
// `dsh.sessions.current` still read); this reports it to the `XrkAppState`
// channel on every change, so switching back to the native interface, a
// notification and a cold start all agree on where the person is. Injected
// after every load; idempotent. Reads and passes through only: the official
// client's storage calls behave exactly as before.
(function () {
  if (window.__dshAppState) return;
  var KEY = 'xrk.sessions.current';
  var LEGACY_KEY = 'dsh.sessions.current';

  function readRaw() {
    try {
      return localStorage.getItem(KEY) || localStorage.getItem(LEGACY_KEY) || '{}';
    } catch (e) {
      return '{}';
    }
  }

  function current() {
    try {
      return (JSON.parse(readRaw()) || {}).sessionId || null;
    } catch (e) {
      return null;
    }
  }

  var reported;
  function report() {
    var id = current();
    if (id === reported) return;
    reported = id;
    try {
      if (window.XrkAppState) window.XrkAppState.postMessage(JSON.stringify({ session: id }));
    } catch (e) {}
  }

  function watch(name) {
    var original = Storage.prototype[name];
    Storage.prototype[name] = function (key) {
      var result = original.apply(this, arguments);
      if (
        this === window.localStorage &&
        (key === KEY || key === LEGACY_KEY || name === 'clear')
      ) {
        report();
      }
      return result;
    };
  }
  watch('setItem');
  watch('removeItem');
  watch('clear');

  window.__dshAppState = { session: current };
  report();
})();

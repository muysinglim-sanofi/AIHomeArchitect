// Minimal Chrome DevTools Protocol driver, rebuilt from the recipe in
// docs/PWA_PARITY_CLOSURE_HANDOFF.md "Driving the browser". Uses Node's
// built-in WebSocket (Node >= 22) so it needs no npm install.
//
// THE TRAP it exists to work around: a Chrome tab reports visibilityState
// "hidden" even when focused. Flutter Web drives every frame from
// requestAnimationFrame, which is throttled there — so the route changes and
// the canvas does NOT repaint. A screenshot then shows a stale scene and looks
// exactly like a broken app. Forcing a RESIZE relayouts outside rAF.
import fs from 'node:fs';

const PORT = 9222;
let _id = 0;
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function connect() {
  const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
  const page = list.find(t => t.type === 'page' && t.webSocketDebuggerUrl);
  if (!page) throw new Error('no page target');
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  return ws;
}

function send(ws, method, params = {}) {
  const id = ++_id;
  ws.send(JSON.stringify({ id, method, params }));
  return new Promise((res, rej) => {
    const timer = setTimeout(() => { ws.removeEventListener('message', h); rej(new Error(`timeout ${method}`)); }, 90000);
    const h = (ev) => {
      const m = JSON.parse(ev.data);
      if (m.id !== id) return;
      clearTimeout(timer); ws.removeEventListener('message', h);
      m.error ? rej(new Error(m.error.message)) : res(m.result);
    };
    ws.addEventListener('message', h);
  });
}

async function viewport(ws, w, h, dpr, mobile) {
  await send(ws, 'Emulation.setDeviceMetricsOverride',
    { width: w, height: h, deviceScaleFactor: dpr, mobile });
}

const [cmd, ...a] = process.argv.slice(2);
const ws = await connect();
try {
  if (cmd === 'nav') {
    await send(ws, 'Page.enable');
    // Bypass the HTTP cache. The bundle's app shell was being served
    // `immutable, max-age=1y` under a filename that never changes, so a
    // browser that had opened the site once kept that build forever — which is
    // how several fixes were live on the server and absent on screen. The
    // hosting rule is corrected, but a browser that already holds the old
    // entry still needs to be told to let go of it.
    await send(ws, 'Network.enable');
    await send(ws, 'Network.setCacheDisabled', { cacheDisabled: true });
    await send(ws, 'Page.navigate', { url: a[0] });
    await sleep(Number(a[1] || 7000));
    console.log('nav', a[0]);
  } else if (cmd === 'shot') {
    const [out, W, H, DPR, kind] = [a[0], Number(a[1] || 390), Number(a[2] || 844), Number(a[3] || 2), a[4] || 'mobile'];
    const mob = kind === 'mobile';
    // An OCCLUDED tab throttles requestAnimationFrame, so a sheet that is
    // sliding open simply stops mid-slide and the capture shows a half-open
    // panel with its last row below the fold. That is not a layout bug in the
    // app, and it cost a wrong diagnosis once. Front the page first.
    // `bringToFront` is not enough: a background/occluded page is FROZEN, and
    // Flutter's sheet animations are driven by the frame ticker. These two put
    // the page back in the active lifecycle and make it believe it has focus,
    // which is what actually resumes the ticker.
    try { await send(ws, 'Page.bringToFront'); } catch (_) {}
    try { await send(ws, 'Page.setWebLifecycleState', { state: 'active' }); } catch (_) {}
    try { await send(ws, 'Emulation.setFocusEmulationEnabled', { enabled: true }); } catch (_) {}
    await viewport(ws, W, H - 1, DPR, mob); await sleep(450);
    await viewport(ws, W, H, DPR, mob);     await sleep(1100);
    const { data } = await send(ws, 'Page.captureScreenshot', { format: 'png' });
    fs.writeFileSync(out, Buffer.from(data, 'base64'));
    console.log('shot', out, `${W}x${H}@${DPR} ${kind}`);
  } else if (cmd === 'click') {
    const x = Number(a[0]), y = Number(a[1]);
    for (const type of ['mousePressed', 'mouseReleased'])
      await send(ws, 'Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
    await sleep(Number(a[2] || 1800));
    console.log('click', x, y);
  } else if (cmd === 'wheel') {
    // Scroll the page. Phase 3's Create is one long page with four steps, so
    // capturing it means scrolling between shots — and the SAME rAF trap
    // applies: dispatch, then let Flutter relayout before the next capture.
    const [x, y, dy] = [Number(a[0]), Number(a[1]), Number(a[2])];
    await send(ws, 'Input.dispatchMouseEvent',
      { type: 'mouseWheel', x, y, deltaX: 0, deltaY: dy, pointerType: 'mouse' });
    await sleep(Number(a[3] || 1200));
    console.log('wheel', dy);
  } else if (cmd === 'type') {
    // Focus is assumed already set by a preceding click. `Input.insertText`
    // goes through the IME path, which is how Flutter Web actually receives
    // text — key events alone do not reach a CanvasKit text field.
    await send(ws, 'Input.insertText', { text: a[0] });
    await sleep(Number(a[1] || 900));
    console.log('type', a[0]);
  } else if (cmd === 'drag') {
    // Press, move in steps, release. Steps matter: Flutter's gesture arena
    // needs several move events to recognise a horizontal drag rather than a
    // tap, and the reveal divider follows the pointer per-event.
    const [x0, y0, x1, y1] = a.slice(0, 4).map(Number);
    await send(ws, 'Input.dispatchMouseEvent',
      { type: 'mousePressed', x: x0, y: y0, button: 'left', clickCount: 1 });
    const steps = 14;
    for (let i = 1; i <= steps; i++) {
      await send(ws, 'Input.dispatchMouseEvent', {
        type: 'mouseMoved',
        x: x0 + ((x1 - x0) * i) / steps,
        y: y0 + ((y1 - y0) * i) / steps,
        button: 'left',
        buttons: 1,
      });
      await sleep(16);
    }
    await send(ws, 'Input.dispatchMouseEvent',
      { type: 'mouseReleased', x: x1, y: y1, button: 'left', clickCount: 1 });
    await sleep(Number(a[4] || 900));
    console.log('drag', x0, y0, '->', x1, y1);
  } else if (cmd === 'carry') {
    // Carry the STAGING SESSION from one preview origin to another.
    //
    // Every Firebase preview channel is its own subdomain, so it is its own
    // web origin, so it gets its own empty localStorage — and therefore its own
    // brand-new anonymous staging user with no work in it. Evidence for a
    // PORTFOLIO screen has to show an actual portfolio, so the session built up
    // over the earlier phases is moved across rather than re-earned by burning
    // fresh generations.
    //
    // The values are read and written inside the page and are NEVER returned to
    // the caller: only the key NAMES are logged. A session token must not end
    // up in a terminal, a transcript or a log file.
    const [src, dst] = a;
    await send(ws, 'Page.enable');
    await send(ws, 'Page.navigate', { url: src });
    await sleep(6000);
    const read = await send(ws, 'Runtime.evaluate', {
      expression: 'JSON.stringify(Object.fromEntries(Object.entries(localStorage)))',
      returnByValue: true,
    });
    const bag = read.result.value;
    const names = Object.keys(JSON.parse(bag));
    await send(ws, 'Page.navigate', { url: dst });
    await sleep(6000);
    await send(ws, 'Runtime.evaluate', {
      expression: '(function(b){var o=JSON.parse(b);for(var k in o)localStorage.setItem(k,o[k]);return Object.keys(o).length})(' + JSON.stringify(bag) + ')',
      returnByValue: true,
    });
    await send(ws, 'Page.navigate', { url: dst });
    await sleep(Number(a[2] || 11000));
    console.log('carried', names.length, 'key(s):', names.join(', '));
  } else if (cmd === 'upload') {
    // Put a real photograph through the real picker.
    //
    // `image_picker` on web builds an <input type=file> and clicks it, which
    // opens the OS file dialog — a window CDP cannot type into. Intercepting
    // the chooser turns that dialog into a Page.fileChooserOpened event
    // carrying the input's backendNodeId, which DOM.setFileInputFiles can then
    // fill directly. The app sees an ordinary picked file.
    const [file, x, y] = [a[0], Number(a[1]), Number(a[2])];
    await send(ws, 'Page.enable');
    await send(ws, 'DOM.enable');
    await send(ws, 'Page.setInterceptFileChooserDialog', { enabled: true });
    const opened = new Promise((res, rej) => {
      const t = setTimeout(() => rej(new Error('no file chooser')), 20000);
      const h = (ev) => {
        const m = JSON.parse(ev.data);
        if (m.method !== 'Page.fileChooserOpened') return;
        clearTimeout(t); ws.removeEventListener('message', h);
        res(m.params);
      };
      ws.addEventListener('message', h);
    });
    for (const type of ['mousePressed', 'mouseReleased'])
      await send(ws, 'Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
    const params = await opened;
    await send(ws, 'DOM.setFileInputFiles',
      { files: [file], backendNodeId: params.backendNodeId });
    await send(ws, 'Page.setInterceptFileChooserDialog', { enabled: false });
    await sleep(Number(a[3] || 6000));
    console.log('upload', file);
  } else if (cmd === 'swipe') {
    // Scroll a Flutter page the way a finger does.
    //
    // `wheel` never returns here (Chrome does not ack the mouseWheel against
    // this CanvasKit surface) and a MOUSE drag does not scroll a Scrollable —
    // by design, on every platform. Touch events do both.
    const [x, y0, y1] = [Number(a[0]), Number(a[1]), Number(a[2])];
    // A hidden/occluded tab never acks an input event, so the call hangs
    // rather than fails. Front the page first, and turn on touch emulation —
    // without it a touch event is not a thing this page can receive.
    await send(ws, 'Page.bringToFront');
    await send(ws, 'Emulation.setTouchEmulationEnabled',
      { enabled: true, maxTouchPoints: 1 });
    const pt = (yy) => [{ x, y: yy, id: 1 }];
    await send(ws, 'Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: pt(y0) });
    const steps = 16;
    for (let i = 1; i <= steps; i++) {
      await send(ws, 'Input.dispatchTouchEvent',
        { type: 'touchMove', touchPoints: pt(y0 + ((y1 - y0) * i) / steps) });
      await sleep(16);
    }
    await send(ws, 'Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await sleep(Number(a[3] || 1200));
    console.log('swipe', y0, '->', y1);
  } else if (cmd === 'lang') {
    // Open the app AS A READER OF THIS LANGUAGE. The PWA follows the browser
    // when no locale has been chosen, and `Emulation.setUserAgentOverride`
    // rewrites `navigator.languages` — which is what Flutter reads — so this
    // is the same path a Khmer visitor arrives through, rather than a toggle
    // driven by a synthetic tap.
    const [code, url] = a;
    const ua = await (await fetch(`http://127.0.0.1:${PORT}/json/version`)).json();
    await send(ws, 'Emulation.setUserAgentOverride',
      { userAgent: ua['User-Agent'], acceptLanguage: code });
    await send(ws, 'Page.enable');
    await send(ws, 'Network.enable');
    await send(ws, 'Network.setCacheDisabled', { cacheDisabled: true });
    await send(ws, 'Page.navigate', { url });
    await sleep(Number(a[2] || 13000));
    console.log('lang', code);
  } else if (cmd === 'eval') {
    const r = await send(ws, 'Runtime.evaluate', { expression: a[0], returnByValue: true, awaitPromise: true });
    console.log(JSON.stringify(r.result?.value ?? r.result));
  } else { console.error('usage: nav|shot|click|drag|wheel|type|eval|carry|upload|swipe|lang'); process.exit(2); }
} finally { ws.close(); }

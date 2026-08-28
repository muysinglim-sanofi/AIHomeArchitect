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
  } else if (cmd === 'eval') {
    const r = await send(ws, 'Runtime.evaluate', { expression: a[0], returnByValue: true, awaitPromise: true });
    console.log(JSON.stringify(r.result?.value ?? r.result));
  } else { console.error('usage: nav|shot|click|drag|wheel|type|eval'); process.exit(2); }
} finally { ws.close(); }

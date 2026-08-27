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
  } else if (cmd === 'eval') {
    const r = await send(ws, 'Runtime.evaluate', { expression: a[0], returnByValue: true, awaitPromise: true });
    console.log(JSON.stringify(r.result?.value ?? r.result));
  } else { console.error('usage: nav|shot|click|eval'); process.exit(2); }
} finally { ws.close(); }

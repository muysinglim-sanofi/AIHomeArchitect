// Tap at (x, y) with real touch events and print every console message /
// exception the page emits for the next `wait` ms. CDP_PORT selects Chrome.
const PORT = Number(process.env.CDP_PORT || 9222);
const [x, y, wait] = [Number(process.argv[2]), Number(process.argv[3]), Number(process.argv[4] || 5000)];
const sleep = ms => new Promise(r => setTimeout(r, ms));
const list = await (await fetch(`http://localhost:${PORT}/json/list`)).json();
const page = list.find(t => t.type === 'page' && t.webSocketDebuggerUrl);
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
let id = 0;
const send = (method, params = {}) => new Promise((res, rej) => {
  const my = ++id;
  const h = (ev) => { const m = JSON.parse(ev.data); if (m.id !== my) return; ws.removeEventListener('message', h); m.error ? rej(new Error(m.error.message)) : res(m.result); };
  ws.addEventListener('message', h);
  ws.send(JSON.stringify({ id: my, method, params }));
});
ws.addEventListener('message', (ev) => {
  const m = JSON.parse(ev.data);
  if (m.method === 'Runtime.consoleAPICalled') {
    const args = (m.params.args || []).map(a => a.value ?? a.description ?? '').join(' ');
    console.log(`[console.${m.params.type}]`, args.slice(0, 1500));
  } else if (m.method === 'Runtime.exceptionThrown') {
    const d = m.params.exceptionDetails;
    console.log('[exception]', d.text, (d.exception && (d.exception.description || d.exception.value)) || '');
  }
});
await send('Runtime.enable');
await send('Page.bringToFront').catch(() => {});
await send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y }] });
await sleep(60);
await send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
console.log('tapped', x, y);
await sleep(wait);
ws.close();

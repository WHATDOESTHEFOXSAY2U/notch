/* Notch website, segment 01 Numbers (Stats.swift, Console.swift, Readouts.swift).
   Two scenes, each registered with Kit.whenVisible, so they take turns with every other scene on the page:
     1. Free: a pointer presses FREE, then the app using the most memory; it is force-quit and memory comes back.
        A visitor can press the keys too (the scene is theirs from the moment they reach for one);
     2. the warning line: one reading at a time crosses its marks, and the line under the closed notch follows it.
   Every loop ends on its scene's still frame (the result of its story), so a scene that loses its turn never jumps.
   The readings are made up; the rules that colour them are the app's. */
(() => {
'use strict';
const K = window.Kit, root = document.getElementById('numbers');
if (!K || !root) return;
const { $, $$, clamp, reduced, player, whenVisible, tween, wob } = K;

/* ---------- gauges, coloured the way Console.swift colours them ---------- */
const level = (v, warn, crit) => (v >= crit ? 'red' : v >= warn ? 'amber' : '');   // white when fine, amber past `warn`, red past `crit`
const RULES = {
  MEM: (v, s) => (s.pressure >= 4 ? 'red' : s.pressure >= 2 ? 'amber' : ''),   // memory follows macOS memory pressure, not a percentage
  SWAP: (v, s) => RULES.MEM(v, s),                                             // swap takes memory's colour
  CPU: v => level(v, 70, 90),
  TEMP: v => level(v, 80, 95),
  BAT: (v, s) => (s.chg ? '' : level(100 - v, 80, 90)),                        // only while unplugged: amber at 20%, red at 10%
};

/* One gauge: its number, its ten-segment bar and its colour. `state` belongs to its panel: memory pressure (1, 2 or 4) and power. */
function gauge(el, state) {
  const id = el.dataset.g, of = +el.dataset.of || 100, dec = +el.dataset.dec || 0;
  const n = $('.gauge__n', el), h = $('.gauge__h', el), bar = $('.bar10', el);
  const g = { id, el, value: parseFloat(n.textContent) || 0, level: '' };
  let text = '', lit = -1;
  g.paint = (v = g.value) => {
    g.value = v;
    const t = v.toFixed(dec), l = Math.round(clamp(v / of, 0, 1) * 10), lv = RULES[id] ? RULES[id](v, state) : '';
    if (t !== text) { n.textContent = t; text = t; }
    if (l !== lit) { bar.style.setProperty('--lit', l); lit = l; }
    if (lv !== g.level || bar.dataset.level !== lv) { bar.dataset.level = lv; g.level = lv; }
    if (id === 'BAT') { const name = state.chg ? 'CHG' : 'BAT'; if (h.textContent !== name) h.textContent = name; }   // CHG on mains power
  };
  return g;
}
function gaugesIn(el, state) {
  const list = $$('.gauge', el).map(x => gauge(x, state));
  list.by = Object.fromEntries(list.map(g => [g.id, g]));
  return list;
}

/* ---------- drawing helpers ---------- */
const NS = 'http://www.w3.org/2000/svg';
function svgEl(name, attrs) { const e = document.createElementNS(NS, name); for (const k in attrs) e.setAttribute(k, attrs[k]); return e; }
// An orthogonal line through `pts`, its corners rounded.
function route(pts, r = 9) {
  let d = `M${pts[0][0]} ${pts[0][1]}`;
  for (let i = 1; i < pts.length - 1; i++) {
    const [x0, y0] = pts[i - 1], [x1, y1] = pts[i], [x2, y2] = pts[i + 1];
    const a = Math.min(r, Math.hypot(x1 - x0, y1 - y0) / 2, Math.hypot(x2 - x1, y2 - y1) / 2);
    const ux = Math.sign(x1 - x0), uy = Math.sign(y1 - y0), vx = Math.sign(x2 - x1), vy = Math.sign(y2 - y1);
    d += ` L${x1 - ux * a} ${y1 - uy * a} Q${x1} ${y1} ${x1 + vx * a} ${y1 + vy * a}`;
  }
  const [x, y] = pts[pts.length - 1];
  return `${d} L${x} ${y}`;
}
const rel = (box, r) => ({ l: r.left - box.left, t: r.top - box.top, r: r.right - box.left, b: r.bottom - box.top, cx: (r.left + r.right) / 2 - box.left });
const px = v => Math.round(v) + .5;   // a one-pixel line lands on whole pixels
const shown = el => getComputedStyle(el).display !== 'none';

/* The panel is drawn at the app's own size (500 points wide) and never enlarged; on a narrow surface it shrinks to fit. */
function fitZoom(bay) {
  const w = bay.clientWidth, pad = w < 480 ? 6 : 28;
  return clamp((w - 2 * pad) / 500, .5, 1);
}

/* The menu bar gives way to the notch, or to the open panel, as on the Mac: whole menus go, from the notch outward, never
   part of one (Kit.fitBar). On a surface too narrow for more, a side that cannot keep its first thing (the app's name on
   the left, the clock on the right) shows nothing: the picture is then a crop of the top middle of the screen. */
function fitMenu(bar, hole, gap = 8) {
  if (!bar || !hole || !K.fitBar) return;
  K.fitBar(bar, hole, gap);
  const left = $$('.mbar__l > *', bar);
  if (left[1] && left[1].getBoundingClientRect().right > hole.getBoundingClientRect().left - gap) left.forEach(el => el.classList.add('is-cut'));
}

const layouts = [];
function relayout() { layouts.forEach(f => f()); }

/* ---------- 1. Free: FREE lists the apps using the most memory; one press force-quits one, and memory comes back ---------- */
function free(bay) {
  const state = { pressure: 1, chg: false };
  const np = $('.np', bay), shape = $('.np__shape', bay), G = gaugesIn($('.np__gauges', bay), state), MEM = G.by.MEM;
  const tools = $('[data-tools]', bay), apps = $('[data-apps]', bay), freeKey = $('[data-free]', tools), ptr = $('[data-ptr]', bay);
  const say = $('[data-say]', bay), live = $('[data-live]', bay), menu = $('.mbar', bay), tryOn = $('[data-try]', bay);
  const RAM = 16;   // GB in this made-up Mac: quitting an app takes its share off MEM
  // the running apps, heaviest first: the bar always shows the four at the top, as the app's does, until a visitor has quit
  // nearly all of them (names as Readouts.swift writes them: the last word, in capitals, at most seven letters)
  const POOL = [['XCODE', 'Xcode', 3.4], ['SAFARI', 'Safari', 2.4], ['PHOTOS', 'Photos', 1.6], ['MUSIC', 'Music', .9], ['NOTES', 'Notes', .7], ['MAIL', 'Mail', .6],
    ['MAPS', 'Maps', .5], ['PAGES', 'Pages', .4], ['BOOKS', 'Books', .3], ['STOCKS', 'Stocks', .2]];
  const BUSY = { MEM: 91, CPU: 22, TEMP: 51, SWAP: 2.6, BAT: 76 };   // as the story starts: memory under pressure
  const REST = [.66, .4];   // where the pointer rests on the MEM gauge: beside its number, on nothing that lights
  // The line under the panel says what the picture cannot: why MEM is amber, what the numbers in the list are, what a
  // press did. The prompt under it (.hint) is the one that asks the visitor to press.
  const SAY = {
    tools: () => `<span>${state.pressure >= 2 ? 'Amber: memory is under pressure.' : '<b>FREE</b> lists the heaviest apps.'}</span>`,
    list: '<span>Each app with the memory it uses, in&nbsp;GB.</span>',
    done: q => `<span><b>${q.app[1]}</b> force-quit. ${q.app[2].toFixed(1)}&nbsp;GB freed.</span><small>Memory ${q.from}% → ${q.to}%</small>`,
    none: '<span>Every app in the list has been quit.</span>',
  };
  const pend = new Set();
  let list = POOL.slice(1), last = null, raf = 0, idle = 0, hands = false, aimed = null, touched = null;

  // The app reads memory pressure from macOS. In this demo it eases once enough memory is free again.
  const pressureAt = m => (m >= 86 ? 2 : 1);
  // MEM with only the apps in `l` still running
  const memFor = l => Math.max(18, Math.round(BUSY.MEM - POOL.filter(a => !l.includes(a)).reduce((s, a) => s + a[2], 0) / RAM * 100));
  const later = (ms, f) => { const id = setTimeout(() => { pend.delete(id); f(); }, reduced() ? 0 : ms); pend.add(id); };
  const clear = () => { pend.forEach(clearTimeout); pend.clear(); cancelAnimationFrame(raf); };

  function cell(app) {
    const [key, name, gb] = app, b = document.createElement('button'), line = `${key} ${gb.toFixed(1)}`;   // Readouts.swift: NAME and GB, to one decimal
    b.type = 'button'; b.className = 'cell'; b.dataset.app = key;
    b.setAttribute('aria-label', `Force-quit ${name}, ${gb.toFixed(1)} GB`);
    b.innerHTML = `<span class="rest">${line}</span><span class="name">${line}</span>`;
    return b;
  }
  function back() {
    const b = document.createElement('button');
    b.type = 'button'; b.className = 'cell'; b.dataset.back = '';
    b.setAttribute('aria-label', 'Back to the tools');
    b.innerHTML = '<svg class="glyph" aria-hidden="true"><use href="#g-top"/></svg><span class="name">BACK</span>';
    return b;
  }
  // The keyboard's place in the bar survives a redraw of its keys.
  function keepFocus(redraw) {
    const a = document.activeElement, had = a && bay.contains(a) && a.closest('.bar');
    const key = had ? a.dataset.app || ('back' in a.dataset ? '\u0000back' : '') : '';
    redraw();
    if (!had) return;
    const bar = apps.hidden ? tools : apps;
    const to = (key === '\u0000back' ? $('[data-back]', bar) : key ? $(`[data-app="${key}"]`, bar) : null) || $('button', bar);
    if (to && to !== document.activeElement) to.focus({ preventScroll: true });
  }
  const renderApps = () => apps.replaceChildren(...list.slice(0, 4).map(cell), back());   // the four heaviest (Stats.swift: topApps)
  // The bar shows the tools or the list; the prompt under the panel names the key to press in each.
  function show(freeing) {
    apps.hidden = !freeing; tools.hidden = freeing;
    if (tryOn) tryOn.textContent = freeing ? 'an app' : 'FREE';
  }
  const setMode = freeing => keepFocus(() => show(freeing));
  const inStep = () => !$('.is-going, .is-new', apps) && $$('[data-app]', apps).map(c => c.dataset.app).join() === list.slice(0, 4).map(a => a[0]).join();
  // Only one key is lit at a time: the one under the pointer. A key that is giving way stays lit until it is gone.
  function hot(el) {
    $$('.cell.is-hot:not(.is-going)', bay).forEach(c => { if (c !== el) c.classList.remove('is-hot'); });
    if (el) el.classList.add('is-hot');
  }
  // The bay's own light takes memory's colour: amber while it is under pressure.
  const glow = () => { const lv = state.pressure >= 2 ? 'amber' : ''; if ((bay.dataset.level || '') !== lv) bay.dataset.level = lv; };
  // Every gauge at once, with `m` percent of memory in use.
  function paint(m) { state.pressure = pressureAt(m); G.forEach(g => g.paint(g.id === 'MEM' ? m : BUSY[g.id])); glow(); }
  function memTo(to, ms) {
    cancelAnimationFrame(raf);
    const from = MEM.value, t0 = performance.now();
    const settle = () => { state.pressure = pressureAt(to); MEM.paint(to); G.by.SWAP.paint(); glow(); };   // swap stays; its colour follows memory
    if (!ms) { settle(); return; }
    const step = now => {
      const t = clamp((now - t0) / ms, 0, 1);
      MEM.paint(from + (to - from) * wob(t));
      if (t < 1) raf = requestAnimationFrame(step); else settle();
    };
    raf = requestAnimationFrame(step);
  }
  // Puts the pointer's tip (its left, top) on `el`, `fx` across and `fy` down it; `now` without the glide.
  function aim(el, fx, fy, now = false) {
    if (!el || !el.isConnected) return;
    aimed = [el, fx, fy];
    const s = shape.getBoundingClientRect().width / 500 || 1, o = np.getBoundingClientRect(), r = el.getBoundingClientRect();
    if (now) ptr.style.transition = 'none';
    ptr.style.left = `${((r.left + r.width * fx - o.left) / s).toFixed(1)}px`;
    ptr.style.top = `${((r.top + r.height * fy - o.top) / s).toFixed(1)}px`;
    if (now) { ptr.getBoundingClientRect(); ptr.style.transition = ''; }
  }
  // The key under the pointer's tip, if any: the one the Mac would light.
  function under() {
    const r = ptr.getBoundingClientRect(), s = shape.getBoundingClientRect().width / 500 || 1;
    const at = document.elementFromPoint(r.left + 1.3 * s, r.top + 1.3 * s);
    const c = at && at.closest('.cell');
    return c && bay.contains(c) && !c.closest('[hidden]') ? c : null;
  }
  /* The pointer glides to a place (MOVE ms), along one of three paths (numbers.css, --ex and --ey: the easing of each axis):
     'even', a straight line; 'arc', across first, then down, so that it comes onto a key from above without crossing its
     neighbours; 'lift', up off the bar at once. Except on 'lift', the key under its tip lights as it goes, as on the Mac. */
  const MOVE = 620;
  async function glide(wait, el, fx, fy, path = 'even') {
    ptr.dataset.path = path;
    aim(el, fx, fy);
    const t0 = performance.now();
    if (path === 'lift') { await wait(MOVE); return; }
    while (performance.now() - t0 < MOVE + 40) { hot(under()); await wait.frame(); }
    hot(under());
  }

  /* Force-quits one app (Stats.swift: quit). It fires on the press, as every key in the panel does: the key gives way,
     still lit, and the next heaviest slides in. Memory falls after that (`fall`), so one thing moves at a time. */
  function drop(key) {
    const c = $(`[data-app="${key}"]:not(.is-going)`, apps), app = list.find(a => a[0] === key);
    if (!c || !app) return null;   // a second press on a key that is giving way finds nothing to quit
    const from = memFor(list);
    list = list.filter(a => a !== app);
    c.classList.add('is-hot', 'is-going');
    const next = list[3];
    if (next && !$(`[data-app="${next[0]}"]`, apps)) {
      const n = cell(next);
      n.classList.add('is-new', 'is-moving');
      apps.insertBefore(n, $('[data-back]', apps));
      requestAnimationFrame(() => requestAnimationFrame(() => n.classList.remove('is-new')));
      later(520, () => n.classList.remove('is-moving'));
    }
    later(460, () => {
      if (!c.parentNode) return;
      const had = document.activeElement === c, to = c.nextElementSibling || $('button', apps);   // the keyboard stays where it was: on the key that took this one's place
      c.remove();
      if (had && to) to.focus({ preventScroll: true });
    });
    last = { app, from, to: memFor(list) };
    return last;
  }
  const fall = (q, ms) => memTo(q.to, reduced() ? 0 : ms);

  /* The frames the story is made of. 'start': the panel as it opens, memory under pressure. 'done': Xcode quit, memory back. */
  function frame(kind) {
    clear();
    list = kind === 'done' ? POOL.slice(1) : POOL.slice();
    last = kind === 'done' ? { app: POOL[0], from: BUSY.MEM, to: memFor(list) } : null;
    keepFocus(() => { renderApps(); show(kind !== 'start'); });
    paint(memFor(list));
    say.innerHTML = kind === 'start' ? SAY.tools() : SAY.done(last);
    hot(null);
  }
  function still() {
    frame('done');
    np.classList.remove('is-dim'); say.style.opacity = '';
    if (!hands) { aim(MEM.el, ...REST, true); ptr.classList.add('is-on'); }   // the panel is open, so the pointer is on it
  }
  async function tell(wait, html) { say.style.opacity = '0'; await wait(170); say.innerHTML = html; say.style.opacity = ''; }
  async function rewind(wait) {   // a quick fade back to where the story starts
    np.classList.add('is-dim'); say.style.opacity = '0';
    await wait(300);
    frame('start');
    await wait(80);
    np.classList.remove('is-dim'); say.style.opacity = '';
    await wait(420);
  }

  const p = player(async wait => {
    aim(MEM.el, ...REST, !ptr.classList.contains('is-on')); ptr.classList.add('is-on');
    await rewind(wait);
    await wait(700);
    await glide(wait, freeKey, .75, .74, 'arc');                    // onto FREE from above: under the pointer it fills white and gives its name
    await wait(600);
    setMode(true); hot(under());                                    // pressed: the bar is the list at once, and the key under the pointer is BACK
    await tell(wait, SAY.list); await wait(560);
    const x = $('[data-app="XCODE"]', apps);
    await glide(wait, x, .66, .74);                                 // along the bar: each key lights as the pointer passes
    await wait(760);
    const q = drop('XCODE'); await wait(200);                       // pressed: Xcode gives way, still lit, and the list closes up
    hot(null); await glide(wait, MEM.el, ...REST, 'lift');          // the pointer goes to the number that is about to change
    await wait(160);
    fall(q, 900); await wait(1100);                                 // memory falls by Xcode's share, and its bar turns white
    await tell(wait, SAY.done(q));
    await wait(2700);
  });

  /* A person can drive it: press an app, BACK, then FREE again. The scene is theirs from the moment they reach for a key
     (a real move of the pointer onto one, a press, the keyboard's focus), not when the bay merely passes under a resting
     pointer; it plays again a while after they stop, whatever the pointer still rests on. */
  function take() {
    clearTimeout(idle);
    if (hands) return;
    hands = true; bay.classList.add('is-hands');
    if (K.turns) K.turns.hold(p);
    p.stop(); clear();
    // whatever the scene was in the middle of is finished at once, so the frame they take over is whole
    np.classList.remove('is-dim'); say.style.opacity = '';
    ptr.classList.remove('is-on');
    if (!apps.hidden && !inStep()) keepFocus(renderApps);
    hot(null);
    paint(memFor(list));
    say.innerHTML = apps.hidden ? SAY.tools() : last ? SAY.done(last) : SAY.list;
  }
  function release() {
    clearTimeout(idle);
    if (!hands) return;
    const a = document.activeElement;
    if (a && bay.contains(a) && a.matches(':focus-visible')) return;   // the keyboard is in the bar: it stays theirs until the focus leaves
    if (a && bay.contains(a)) a.blur();                                // a key the pointer pressed keeps no focus for the scene to carry about
    hands = false; bay.classList.remove('is-hands');
    if (K.turns) K.turns.release(p); else if (!reduced()) p.start();
    if (p.active) return;
    if (!reduced()) still();                                            // not its turn: back to the still frame, the pointer on the panel
    else { aim(MEM.el, ...REST, true); ptr.classList.add('is-on'); }   // with Reduce Motion the frame stays as they left it, and the pointer is back on the open panel
  }
  const rest = ms => { clearTimeout(idle); idle = setTimeout(release, ms); };

  shape.addEventListener('pointermove', e => {
    if (e.pointerType === 'touch' || !e.target.closest('button')) return;
    if (K.moved ? !K.moved(e) : !(e.movementX || e.movementY)) return;   // the page scrolling under a pointer at rest is not a person reaching for a key
    take(); rest(6000);
  });
  shape.addEventListener('pointerleave', e => { if (hands && e.pointerType !== 'touch') rest(2600); });
  // a finger lights the key it presses, as the pointer does on the Mac, and only for as long as it presses
  shape.addEventListener('pointerdown', e => { const c = e.target.closest('button'); if (c && e.pointerType === 'touch') { touched = c; c.classList.add('is-hot'); } });
  ['pointerup', 'pointercancel'].forEach(t => shape.addEventListener(t, () => { const c = touched; touched = null; if (c) setTimeout(() => { if (!c.classList.contains('is-going')) c.classList.remove('is-hot'); }, 120); }));
  apps.addEventListener('click', e => {
    const c = e.target.closest('button'); if (!c) return;
    take(); rest(7000);
    if ('back' in c.dataset) { setMode(false); hot(null); say.innerHTML = SAY.tools(); return; }
    const q = drop(c.dataset.app);
    if (!q) return;
    live.textContent = `${q.app[1]} force-quit. Memory ${q.to}%.`;
    later(460, () => { fall(q, 900); later(1000, () => { say.innerHTML = SAY.done(q); }); });
  });
  tools.addEventListener('click', e => {
    if (!e.target.closest('[data-free]')) return;
    take(); rest(7000);
    renderApps(); setMode(true); hot(null);
    say.innerHTML = list.length ? SAY.list : SAY.none;
  });
  bay.addEventListener('focusin', e => { if (e.target.matches('button:focus-visible')) take(); });
  bay.addEventListener('focusout', e => { if (hands && !bay.contains(e.relatedTarget)) rest(2600); });

  layouts.push(() => {
    const z = fitZoom(bay);
    np.style.setProperty('--z', z.toFixed(3));
    np.classList.toggle('is-small', z < .92);
    fitMenu(menu, shape);
    if (aimed) aim(...aimed, true);   // the pointer keeps its place when the panel's size changes
  });
  whenVisible(bay, p, still);
}

/* ---------- 2. the warning line: the five readings by name, the marks of the four it watches, and the line under the closed notch ---------- */
function warning(bay) {
  const state = { pressure: 1, chg: false };
  const G = gaugesIn($('.nx__marks', bay), state), stage = $('.nx__stage', bay), svg = $('[data-wires]', bay);
  const notch = $('.nn', bay), line = $('[data-line]', bay), menu = $('.mbar', bay);
  const WATCHED = ['MEM', 'CPU', 'TEMP', 'BAT'].map(id => G.by[id]);   // Console.swift: colors. SWAP only takes memory's colour.
  const STILL = { MEM: 63, CPU: 76, TEMP: 52, SWAP: 1.3, BAT: 64 };
  let routes = [];

  // Console.swift: the line takes the worst colour among the readings it watches (memory, CPU, temperature, battery)
  function sync() {
    const lv = WATCHED.map(g => g.level), worst = lv.includes('red') ? 'red' : lv.includes('amber') ? 'amber' : '';
    if (line.dataset.level !== worst) line.dataset.level = worst;
    if ((bay.dataset.level || '') !== worst) bay.dataset.level = worst;   // the bay's own light takes the line's colour
    routes.forEach(r => {
      const l = G.by[r.dataset.k].level;
      r.classList.toggle('is-amber', l === 'amber'); r.classList.toggle('is-red', l === 'red');
      if (l && r !== svg.lastChild) svg.append(r);   // a lit line is drawn over the unlit ones it shares its trunk with
    });
  }
  /* A line from under the warning line to each reading it watches: down to a line across above the gauges, then a drop to
     each. Where the gauges fold into two rows (a phone), the lower row is reached down the gap beside its column. */
  function layout() {
    fitMenu(menu, notch);
    svg.replaceChildren(); routes = [];
    if (!shown(svg)) return;
    const box = stage.getBoundingClientRect(), n = rel(box, notch.getBoundingClientRect());
    const x0 = px(n.cx), y0 = Math.round(n.b) + 15;   // clear of the line, which hangs 3 to 5 points under the notch
    const at = new Map(G.map(g => { const r = rel(box, g.el.getBoundingClientRect()); return [g, { cx: r.cx, top: Math.round(r.t) }]; }));   // the middle of each gauge's column: the one under the notch is then straight under the line
    const top = Math.min(...[...at.values()].map(a => a.top)), firstRow = G.filter(g => at.get(g).top - top < 8);
    const pitch = firstRow.length > 1 ? at.get(firstRow[1]).cx - at.get(firstRow[0]).cx : 0;
    WATCHED.forEach(g => {
      const a = at.get(g), x = px(a.cx), bus = top - 22, gap = px(a.cx + pitch / 2);
      const pts = a.top - top < 8 ? [[x0, y0], [x0, bus], [x, bus], [x, a.top - 9]]
        : [[x0, y0], [x0, bus], [gap, bus], [gap, a.top - 22], [x, a.top - 22], [x, a.top - 9]];
      const r = svgEl('path', { d: route(pts, 10) });
      r.dataset.k = g.id;
      svg.append(r); routes.push(r);
    });
    sync();
  }
  layouts.push(layout);

  async function ramp(wait, g, to, ms) { const from = g.value; await tween(wait, ms, t => { g.paint(from + (to - from) * wob(t)); sync(); }); }
  function still() { G.forEach(g => g.paint(STILL[g.id])); sync(); }
  const p = player(async wait => {
    const { CPU, TEMP } = G.by;
    await wait(600);
    await ramp(wait, CPU, 94, 900); await wait(800);      // past 90%: red, and the line turns red with it
    await ramp(wait, CPU, 31, 900); await wait(500);      // back under 70%: the line goes out
    await ramp(wait, TEMP, 86, 900); await wait(800);     // past 80 °C: amber
    await ramp(wait, TEMP, 52, 800); await wait(400);
    await ramp(wait, CPU, 76, 900); await wait(700);      // and back to the still frame
  });
  whenVisible(bay, p, still);
}

/* ---------- wire up ---------- */
const fr = $('[data-nx="free"]', root), warn = $('[data-nx="warn"]', root);
if (K.tickClocks) K.tickClocks();   // the clocks at their real width, before anything is fitted beside them
if (fr) free(fr);
if (warn) warning(warn);
relayout();
let queued = 0;
const later = () => { cancelAnimationFrame(queued); queued = requestAnimationFrame(relayout); };
if ('ResizeObserver' in window) new ResizeObserver(later).observe(root); else addEventListener('resize', later);
if (document.fonts && document.fonts.ready) document.fonts.ready.then(later);
// a clock that gains a digit takes room from what sits beside it
if ('MutationObserver' in window) $$('.mbar__clock', root).forEach(c => new MutationObserver(later).observe(c, { childList: true, characterData: true, subtree: true }));
})();

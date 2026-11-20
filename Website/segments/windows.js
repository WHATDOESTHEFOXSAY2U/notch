/* Notch website, segment 04 Windows: two fingers on a window's title bar, swipe, lift.
   What it shows follows the app: the places and the picture that stands in for the pointer (Place.swift, Pointer.swift),
   when that picture goes up and the knocks (Swipe.swift: up with the swipe's first movement; a knock for each new pick, two
   for full screen and close), the order of a lift (the picture comes down, then the window moves) and where a window lands
   (Windows.swift: the screen without its menu bar and Dock, each edge on a whole point). The app draws nothing on the window
   itself, so neither does this. Uses window.Kit from ../app.js. One gesture moves at a time; the demo plays only on its turn
   (Kit.whenVisible), and otherwise shows one still frame: the moment after a lift. */
(() => {
'use strict';
const Kit = window.Kit; if (!Kit) return;   // app.js did not arrive: the page shows its still frames, which are in the markup
const { $, $$, reduced, player, whenVisible, fitBar, touch, moved } = Kit;

function windows() {
  const root = $('#windows'); if (!root) return;
  const bay = $('.wn-bay', root), map = $('.wn-map', root), scr = $('.wn-screen', root), tp = $('.wn-tp', root);
  if (!bay || !map || !scr || !tp) return;
  const cv = $('.wn-sheet', scr), win = $('.wn-win', scr), ptr = $('.wn-ptr', scr), pic = $('.wn-pic', ptr), dock = $('.wn-dock', scr), dockMin = $('.wn-dock-min', scr);
  const fingers = $$('.wn-finger', tp), dots = fingers.map(f => $('.wn-dot', f)), trails = fingers.map(f => $('.wn-trail', f));
  const rings = $$('.wn-ring', tp), hold = $('.wn-hold', tp), holdArc = $('circle', hold);
  const keys = $$('.wn-key', map), stepEls = $$('.step', bay);
  const nowPic = $('.wn-now .wn-pic', root), nowName = $('.wn-now b', root), nowHow = $('.wn-now > span:last-child', root), sayEl = $('[aria-live]', bay);
  const touchy = () => (touch && touch()) || matchMedia('(pointer: coarse)').matches;

  // The places: the part of the screen the window takes (x, y, width, height, from the top left), the way the fingers
  // go, and the colour the picture lights in. Everything that only moves the window is white; the three things the
  // window's own buttons do take the system's green, yellow and red (Place.color). Full screen and close light the
  // whole picture, edge included. `said` is what a screen reader hears when a visitor picks one.
  const P = {
    left:  { unit: [0, 0, .5, 1], dir: [-1, 0], said: 'Window on the left half' },
    right: { unit: [.5, 0, .5, 1], dir: [1, 0], said: 'Window on the right half' },
    fill:  { unit: [0, 0, 1, 1], dir: [0, -1], said: 'Window fills the screen' },
    min:   { unit: [5 / 23, 10 / 14, 13 / 23, 4 / 14], dir: [0, 1], c: 'yellow', said: 'Window minimised to the Dock' },   // a bar at the bottom edge: the Dock
    tl:    { unit: [0, 0, .5, .5], dir: [-1, -1], said: 'Window in the top left quarter' },
    tr:    { unit: [.5, 0, .5, .5], dir: [1, -1], said: 'Window in the top right quarter' },
    bl:    { unit: [0, .5, .5, .5], dir: [-1, 1], said: 'Window in the bottom left quarter' },
    br:    { unit: [.5, .5, .5, .5], dir: [1, 1], said: 'Window in the bottom right quarter' },
    full:  { unit: [0, 0, 1, 1], dir: [0, -1], c: 'green', whole: true, said: 'Window in full screen' },
    close: { unit: [0, 0, 1, 1], pinch: true, c: 'red', whole: true, said: 'Window closed. The app stays open.' },
  };
  for (const id in P) P[id].id = id;
  const COLOR = { green: 'var(--sys-green)', yellow: 'var(--sys-yellow)', red: 'var(--sys-red)' };
  // The round. It starts from the still frame (the left half): a half, a quarter and the first of the three coloured ones
  // come in its first twelve seconds, and it ends where it began.
  const ORDER = ['right', 'tl', 'min', 'fill', 'br', 'full', 'bl', 'close', 'tr', 'left'];

  /* ---------- drawing ---------- */
  function paint(el, p) {   // the picture: nothing lit, a place lit white, or all of it in a colour
    el.classList.toggle('is-whole', !!(p && p.whole));
    el.classList.toggle('is-empty', !p);
    el.style.setProperty('--c', p && p.c ? COLOR[p.c] : '#fff');
    if (p && !p.whole) ['--x', '--y', '--w', '--h'].forEach((k, i) => el.style.setProperty(k, p.unit[i]));
  }
  function mark(id) {   // the chosen gesture: its key lit and current, and its name under the screen where that shows
    let key = null;
    keys.forEach(k => {
      const on = k.dataset.p === id;
      k.classList.toggle('is-on', on);
      if (on) { k.setAttribute('aria-current', 'true'); key = k; } else k.removeAttribute('aria-current');
    });
    if (!key || !nowPic) return;
    paint(nowPic, P[id]);
    nowName.textContent = $('.wn-name', key).firstChild.textContent.trim();
    nowHow.textContent = key.dataset.how || '';
  }
  // The steps along the bay's foot: the one playing is lit, and its line runs for as long as it takes (ms).
  function stepTo(n, ms = 0) {
    stepEls.forEach((li, i) => {
      const on = i + 1 === n;
      li.classList.toggle('is-on', on);
      li.style.setProperty('--wd', (on ? Math.round(ms) : 0) + 'ms');
      li.style.setProperty('--p', on ? 1 : 0);
    });
  }
  const showPic = v => ptr.classList.toggle('is-pic', v);   // the picture takes the arrow's place, or gives it back
  let deep = 0;
  function now(fn) {   // drawn at once, nothing moving
    deep++; root.classList.add('is-now');
    try { fn(); } finally { if (--deep === 0) { void root.offsetWidth; root.classList.remove('is-now'); } }
  }

  /* ---------- the screen ---------- */
  // Everything on it is placed in the Mac's own points on a sheet 1512 by 982, which CSS scales as one (--k). So a place
  // never depends on how large the page draws the screen, and a new size needs nothing moved.
  const W = 1512, BAR = 33, TITLE = 32;
  const fit = () => { const w = scr.clientWidth; if (w) cv.style.setProperty('--k', (w / W).toFixed(5)); };
  // The room is the screen without its menu bar and Dock, as the Mac's visible frame is; each edge is rounded to a whole
  // point by itself, so neighbouring places share one line with no gap and no overlap (Windows.place).
  function rectOf(at) {
    const room = { x: 0, y: BAR, w: W, h: dock.offsetTop - 6 - BAR };
    if (at === 'home' || at === 'gone') return { x: Math.round(W * .2), y: Math.round(room.y + room.h * .11), w: Math.round(W * .6), h: Math.round(room.h * .74) };
    if (at === 'full') return { x: 0, y: BAR, w: W, h: cv.offsetHeight - BAR };
    if (at === 'min') {   // the window's place in the Dock, measured with the Dock grown to hold it (the Dock alone held still for it)
      const b = $('b', dockMin), was = dockMin.classList.contains('is-on');
      dockMin.style.transition = b.style.transition = 'none';
      dockMin.classList.add('is-on');
      const r = { x: dock.offsetLeft + dockMin.offsetLeft + (dockMin.offsetWidth - b.offsetWidth) / 2, y: dock.offsetTop + dockMin.offsetTop + (dockMin.offsetHeight - b.offsetHeight) / 2, w: b.offsetWidth, h: b.offsetHeight };
      if (!was) dockMin.classList.remove('is-on');
      void dockMin.offsetWidth;
      dockMin.style.transition = b.style.transition = '';
      return r;
    }
    const [ux, uy, uw, uh] = P[at].unit;
    const X = f => Math.round(room.x + f * room.w), Y = f => Math.round(room.y + f * room.h);
    return { x: X(ux), y: Y(uy), w: X(ux + uw) - X(ux), h: Y(uy + uh) - Y(uy) };
  }
  let at = 'home';   // where the window is: home, a place, min, full, or gone (closed)
  function put(r, ms = 0, ease = '') {
    win.style.setProperty('--wt', ms + 'ms');
    win.dataset.ease = ease;
    Object.assign(win.style, { left: r.x + 'px', top: r.y + 'px', width: r.w + 'px', height: r.h + 'px' });
  }
  // Where the pointer rests on a window's title bar: right of its middle, clear of the title.
  const barPoint = r => ({ x: Math.round(r.x + r.w / 2 + Math.min(140, r.w * .18)), y: Math.round(r.y + TITLE / 2) });
  let tip = { x: 0, y: 0 };
  function point(x, y, ms = 0) {
    ptr.style.setProperty('--wt', ms + 'ms');
    ptr.style.transform = `translate(${x}px, ${y}px)`;
    tip = { x, y };
  }

  /* ---------- the trackpad ---------- */
  const size = () => ({ w: tp.clientWidth, h: tp.clientHeight, d: dots[0].offsetWidth || 16 });
  let from = [{ x: 0, y: 0 }, { x: 0, y: 0 }], gone = [{ x: 0, y: 0 }, { x: 0, y: 0 }];   // where each finger came down; how far it has gone since
  function down(p) {   // two fingers side by side, wider apart for a pinch
    const s = Math.round(size().w * (p.pinch ? .36 : .17));
    from = [{ x: -s / 2, y: 0 }, { x: s / 2, y: 0 }];
    fingers.forEach((f, i) => { f.style.transform = `translate(${from[i].x}px, ${from[i].y}px)`; });
    go([{ x: 0, y: 0 }, { x: 0, y: 0 }], 0);   // at once: nothing else on the page is stopped for it
    tp.classList.add('is-down');
  }
  function go(to, ms) {   // the fingers glide; each leaves a short trail back to where it came down
    const { d } = size();
    to.forEach((t, i) => {
      const len = Math.hypot(t.x, t.y);
      dots[i].style.setProperty('--wt', ms + 'ms');
      dots[i].style.transform = `translate(${t.x}px, ${t.y}px)`;
      trails[i].style.setProperty('--wt', ms + 'ms');
      if (len > .5) trails[i].style.transform = `rotate(${Math.atan2(t.y, t.x)}rad)`;
      trails[i].style.width = d + len + 'px';
    });
    gone = to;
  }
  function travel(p, stage = 1) {
    const { w, h, d } = size();
    if (p.pinch) { const each = (from[1].x - from[0].x - Math.max(w * .07, d + 2)) / 2; return [{ x: each, y: 0 }, { x: -each, y: 0 }]; }   // together, side by side: never one on the other
    const [dx, dy] = p.dir, k = dx && dy ? .82 : 1;
    const y = p.id === 'full' ? -h * (stage === 1 ? .15 : .25) : dy * h * .24 * k;
    return [0, 1].map(() => ({ x: dx * w * .25 * k, y }));
  }
  const middle = () => ({ x: (from[0].x + from[1].x + gone[0].x + gone[1].x) / 2, y: (from[0].y + from[1].y + gone[0].y + gone[1].y) / 2 });
  const place = (el, m) => { el.style.left = `calc(50% + ${m.x}px)`; el.style.top = `calc(var(--cy) + ${m.y}px)`; };
  // A knock is felt, not heard (Knock.swift: the trackpad's actuator), so it is drawn as a ring and makes no sound; twice
  // for full screen and close. (With Sound on, the keys themselves tick and press like any control: app.js.)
  function knock(twice) {
    const m = middle();
    rings.forEach(r => { r.classList.remove('is-go'); place(r, m); });
    void tp.offsetWidth;
    rings[0].classList.add('is-go');
    if (twice) rings[1].classList.add('is-go');
  }
  function rest(ms) {   // the fingers hold still on "fill" for a moment
    place(hold, middle());
    holdArc.style.setProperty('--wt', ms + 'ms');
    hold.classList.add('is-on');
  }
  function lift() { tp.classList.remove('is-down'); hold.classList.remove('is-on'); }

  /* ---------- one gesture ---------- */
  // The window back where a swipe can show something: out of the Dock, out of full screen, a new one after a close, or
  // back to the middle when it is already where this swipe would send it.
  async function ready(p, wait, k) {
    const stuck = at === 'gone' || at === 'min' || at === 'full' || at === p.id || (p.id === 'full' && at === 'fill');
    if (!stuck) return;
    stepTo(0);
    if (at === 'gone') {
      put(rectOf('home'));   // in no time, while it cannot be seen
      void win.offsetWidth;
      win.classList.remove('is-gone');
    } else {
      if (at === 'min') { dockMin.classList.remove('is-on'); win.classList.remove('is-min'); }
      if (at === 'full') scr.classList.remove('is-full');
      put(rectOf('home'), 480 * k, 'calm');
    }
    at = 'home';
    await wait(680 * k);
  }
  const LAND = { close: 200, min: 360, full: 460 };   // how long each landing is drawn for; a plain move takes 240
  async function land(p, wait) {
    if (p.id === 'close') { win.classList.add('is-gone'); at = 'gone'; }
    else if (p.id === 'min') { win.classList.add('is-min'); put(rectOf('min'), LAND.min, 'in'); dockMin.classList.add('is-on'); at = 'min'; }
    else if (p.id === 'full') { scr.classList.add('is-full'); put(rectOf('full'), LAND.full, 'calm'); at = 'full'; }
    else { put(rectOf(p.id), 240); at = p.id; }
    await wait(LAND[p.id] || 240);
  }
  async function gesture(p, wait, k = 1) {
    mark(p.id);
    await ready(p, wait, k);
    // 1. the pointer on the title bar
    const b = barPoint(rectOf(at)), far = Math.hypot(b.x - tip.x, b.y - tip.y) > 3;
    stepTo(1, (far ? 860 : 520) * k);
    if (far) { point(b.x, b.y, 560 * k); await wait(640 * k); }
    await wait((far ? 220 : 520) * k);
    // 2. two fingers come down; as they start to move, the pointer becomes a small picture of the screen with nothing lit yet
    //    (Swipe.start: the picture goes up with the swipe's first movement, not with the touch)
    const ms = 380 * k;
    stepTo(2, 440 * k + ms * .4);
    down(p);
    await wait(440 * k);
    paint(pic, null); showPic(true);
    go(travel(p), ms);
    await wait(ms * .4);
    // 3. past the line the picture lights the place and the trackpad knocks
    const first = p.id === 'full' ? P.fill : p;
    stepTo(3, ms * .6 + 700 * k + (p.id === 'full' ? 1580 * k : 0));
    paint(pic, first); knock(!!first.whole);
    await wait(ms * .6 + 700 * k);
    if (p.id === 'full') {   // rest on fill, then push on: full screen, green, two knocks
      rest(460 * k); await wait(560 * k);
      const push = 260 * k;
      go(travel(p, 2), push); await wait(push * .45);
      hold.classList.remove('is-on');
      paint(pic, p); knock(true);
      await wait(push * .55 + 760 * k);
    }
    // 4. lift: the picture comes down and the arrow is back; then the window lands (Swipe.finish: in that order)
    stepTo(4, 90 + (LAND[p.id] || 240));
    lift(); showPic(false);
    await wait(90);
    await land(p, wait);
    await wait(1400 * k);
  }

  /* ---------- the loop, and the visitor's own tries ---------- */
  let next = 0, live = false, chosen = null, taken = false, backT = 0;
  const scene = {};
  const auto = player(async wait => {
    const p = P[ORDER[next]];
    next = (next + 1) % ORDER.length;
    await gesture(p, wait);
    if (next === 0 && scene.looped) scene.looped();   // a whole round: the turn may pass on (Kit.turns)
  });
  // A gesture the visitor asked for plays once. A moment after it ends the loop comes back, wherever the pointer is.
  const manual = player(async wait => {
    await gesture(chosen, wait, .78);
    if (ORDER[next] === chosen.id) next = (next + 1) % ORDER.length;   // the loop goes on with another one, not the one just seen
    back(touchy() ? 4200 : 2400);
  }, true);
  // Anything in the middle of a gesture, put down at once: the fingers lift, the picture goes, the window stays where it is.
  function settle() {
    lift(); showPic(false);
    rings.forEach(r => r.classList.remove('is-go'));
  }
  const turns = window.Kit.turns;
  // The visitor drives: the demo holds its turn and nothing else on the page moves, until a moment after their gesture
  // ends. It never comes back by itself while the keyboard's focus is on one of the keys.
  const keyed = () => { try { return !!map.querySelector(':focus-visible'); } catch { return map.contains(document.activeElement); } };
  function take() { clearTimeout(backT); taken = true; if (turns) turns.hold(scene); auto.stop(); }
  function back(ms) {
    clearTimeout(backT);
    if (!taken) return;
    backT = setTimeout(() => {
      if (manual.active) return;
      if (keyed()) { back(2400); return; }
      taken = false;
      if (turns) turns.release(scene); else if (live) scene.start();
    }, ms);
  }
  function choose(id) {
    if (sayEl) sayEl.textContent = P[id].said;
    if (reduced()) { still(id); return; }
    if (manual.active && chosen === P[id]) return;
    take(); manual.stop(); settle(); stepTo(0);
    chosen = P[id];
    manual.start();
  }

  // The still frame: the moment after a lift. The window has landed, the arrow is back (on its title bar, or where the
  // title bar was when the window has gone to the Dock, to full screen, or closed), the fingers are up, no picture.
  function still(id = 'left') {
    auto.stop(); manual.stop();
    now(() => {
      settle();
      const away = id === 'min' || id === 'full' || id === 'close';
      scr.classList.toggle('is-full', id === 'full');
      win.classList.toggle('is-gone', id === 'close');
      win.classList.toggle('is-min', id === 'min');
      dockMin.classList.toggle('is-on', id === 'min');
      put(rectOf(id === 'close' ? 'home' : id));
      at = id === 'close' ? 'gone' : id;
      const b = barPoint(rectOf(away ? 'home' : id));
      point(b.x, b.y);
      mark(id); stepTo(4);
    });
    next = (ORDER.indexOf(id) + 1) % ORDER.length;
  }

  Object.assign(scene, {
    start() { live = true; if (auto.active || manual.active) return; settle(); auto.start(); },
    stop() { live = false; clearTimeout(backT); auto.stop(); manual.stop(); if (taken) { taken = false; if (turns) turns.release(scene); } },
  });
  Object.defineProperty(scene, 'active', { get: () => auto.active || manual.active });   // Kit.turns.playing reads it

  // Pointing at a key tries its gesture. Only a pointer that really moved onto a key counts (Kit.moved: a page scrolled
  // under a resting pointer is not a visitor pointing), and only once it slows there, so a pointer crossing the map on its
  // way elsewhere starts nothing. A key answers once for each visit; a click or a tap plays it again.
  // The words under the map say "Point at…" or "Tap…": styles.css shows one (.when-point, .when-tap).
  let px = 0, py = 0, hoverK = null, served = null, hoverT = 0;
  const unhover = () => { clearTimeout(hoverT); hoverK = served = null; };
  function arm(k) {
    clearTimeout(hoverT);
    hoverK = k;
    const x0 = px, y0 = py;
    hoverT = setTimeout(() => {
      if (hoverK !== k) return;
      if (Math.hypot(px - x0, py - y0) > 28) { arm(k); return; }   // still travelling
      hoverK = null; served = k;
      choose(k.dataset.p);
    }, 100);
  }
  map.addEventListener('pointermove', e => {
    if (e.pointerType === 'touch' || reduced() || (moved && !moved(e))) return;
    px = e.clientX; py = e.clientY;
    const k = e.target instanceof Element ? e.target.closest('.wn-key') : null;
    if (!k) { unhover(); return; }
    if (k !== served && k !== hoverK) arm(k);
  });
  map.addEventListener('pointerleave', unhover);
  keys.forEach(k => k.addEventListener('click', () => { clearTimeout(hoverT); hoverK = null; served = k; choose(k.dataset.p); }));
  // The keyboard arriving on a key stops the loop on the result of the gesture it was showing, so nothing changes under
  // the reader and the key marked as current is where the window is. The loop plays on once the focus has left.
  map.addEventListener('focusin', () => {
    if (!keyed() || reduced() || taken) return;
    take();
    const on = keys.find(k => k.classList.contains('is-on'));
    still(on ? on.dataset.p : 'left');
  });
  map.addEventListener('focusout', e => { if (taken && !manual.active && !map.contains(e.relatedTarget)) back(2400); });

  // The sheet's scale follows the screen's width; nothing on it needs moving.
  fit();
  if ('ResizeObserver' in window) new ResizeObserver(fit).observe(scr); else addEventListener('resize', fit);
  const bar = $('.mbar', scr), notch = $('.wn-notch', scr);
  const menus = () => { if (fitBar && bar && notch) fitBar(bar, notch); };   // no menu ever runs under the notch
  menus();
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(menus);

  still();
  whenVisible(bay, scene, () => still());
}

windows();
})();

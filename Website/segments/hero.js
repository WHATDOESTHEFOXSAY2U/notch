/* Notch website: the hero's panel (Console.swift, Readouts.swift), open from the notch of a MacBook's lid.
   As in the app, the panel opens under the pointer and closes when the pointer leaves. On this page open is also where it
   rests: a drawn pointer comes back to the notch a moment after the visitor's own has left, and whenever the hero comes
   back into view. The readings are live, MIRROR and FREE work, and the other keys lead to their sections.
   Once after the page loads the drawn pointer shows the whole mechanic: up to the notch, the panel springs open, then along
   the function bar, where each key lights with its name as it does under the pointer in the app.
   Uses window.Kit from ../app.js. What moves by itself plays through Kit.turns, so nothing does under Reduce Motion. */
(() => {
'use strict';
const Kit = window.Kit; if (!Kit) return;
const { $, $$, clamp, ease, rand, reduced, Sound, player, whenVisible, turns } = Kit;

const stage = $('#hero-stage'), device = $('#hero-device'), notch = $('#hero-notch');
if (!stage || !device || !notch) return;
const cap = $('#hero-cap'), panel = $('#hero-panel'), readouts = $('.readouts', notch), ptr = $('#hero-ptr');
const bar = $('#hero-bar'), dot = $('#hero-dot'), lid = $('.lid', device), said = $('#hero-said');
const barTools = $('#hero-tools'), barFree = $('#hero-free'), mirrorEl = $('#hero-mirror'), alertEl = $('.notch__alert', notch);
const keys = $$('.cell', barTools), mirrorBtn = $('[data-act="mirror"]', barTools), freeBtn = $('[data-act="free"]', barTools);

/* ---- the lid's size ----
   Drawn 1 px to 1 pt. Only where the panel itself would not fit (a phone) is the whole lid scaled down, by --k; the CSS
   sets small type and the keys by the same number. The stage is as tall as the panel can get (the mirror open), so nothing
   below the hero ever moves; the lid's fade starts under the panel as it is (--f0r, --f1r at rest; --f0m, --f1m with the mirror). */
const BEZEL = 14, CAP = 32, MIRROR = 273;   // px: the lid's bezel; the notch's own band; what the mirror adds (12 + 261)
const LID = 1540;   // the lid a crop is cut from: a 14-inch MacBook Pro's, its screen 1512 points across, and the bezel each side
// The same line as the CSS: from here down the whole lid would make the notch more than about 14% of it, so the stage shows a crop.
const wrap = stage.previousElementSibling, cropQ = matchMedia('(max-width: 1359px)');
let k = 1, fade = 0, open = notch.classList.contains('is-open');   // the lid's scale; a crop's side fade, in the lid's pixels; open, as the markup draws it
function fit() {
  const w = stage.clientWidth;
  if (!w) return;
  k = clamp((w - 32) / 500, .5, 1);
  stage.style.setProperty('--k', k.toFixed(4));
  // Whole pixels: on a 1x screen a line that falls between two pixels is drawn soft. The lid gets an even width (the page's
  // column, or the 14-inch lid a crop is cut from), its middle a whole pixel, and the stage starts on one.
  const gut = wrap ? parseFloat(getComputedStyle(wrap).paddingLeft) || 20 : 20;
  if (cropQ.matches) {
    const seen = w / k;   // how much of the lid the window shows, in the lid's own pixels
    fade = clamp(seen * .07, 18, 96);
    device.style.width = LID + 'px';
    device.style.setProperty('--vx', ((LID - seen) / 2).toFixed(2) + 'px');
    device.style.setProperty('--fw', fade.toFixed(1) + 'px');
  } else {
    fade = 0;
    device.style.width = 2 * Math.floor(Math.min(1360, w - 2 * gut) / 2) + 'px';
    device.style.removeProperty('--vx'); device.style.removeProperty('--fw');
  }
  stage.style.setProperty('--sx', (w % 2 ? .5 : 0) + 'px');
  if (wrap) {
    stage.style.setProperty('--sy', '0px');
    const y = wrap.getBoundingClientRect().bottom + scrollY + parseFloat(getComputedStyle(stage).marginTop);
    stage.style.setProperty('--sy', (Math.round((Math.ceil(y - .01) - y) * 64) / 64).toFixed(6) + 'px');   // browsers lay out in 64ths of a pixel
  }
  const body = readouts.offsetHeight - mirrorEl.offsetHeight;   // the gauges, the line and the bar, as tall as this scale makes them
  const rest = BEZEL + CAP + body, tall = rest + MIRROR, sh = tall + 70;
  stage.style.setProperty('--sh', sh + 'px');
  lid.style.setProperty('--f0r', rest + 150 + 'px'); lid.style.setProperty('--f1r', rest + 300 + 'px');
  lid.style.setProperty('--f0m', tall + 12 + 'px'); lid.style.setProperty('--f1m', sh + 'px');
  fitMenus();
}
/* As on a Mac, no menu runs under the notch, nor under the open panel: whole menus that would are left out. In a crop, what
   the window's edge would cut, or its fade nearly hide, is left out too, in place, so the rest stays where that Mac has it. */
function fitMenus() {
  if (!bar || !Kit.fitBar) return;
  const r = notch.getBoundingClientRect(), mid = r.left + r.width / 2, half = (open ? 250 : 90) * k;
  Kit.fitBar(bar, { getBoundingClientRect: () => ({ left: mid - half, right: mid + half }) });   // where the black will be once it has settled
  const items = $$('.mbar__l > *, .mbar__r > *', bar), s = stage.getBoundingClientRect(), m = fade * k / 2;
  items.forEach(el => el.classList.remove('is-off'));
  if (fade) items.forEach(el => {
    const b = (el === dot ? el.previousElementSibling : el).getBoundingClientRect();   // the privacy dot goes with Control Centre, in whose gap it sits
    if (b.width && (b.left < s.left + m || b.right > s.right - m)) el.classList.add('is-off');
  });
}

/* ---- gauges: live readings, coloured as Console.swift colours them (white, amber, red) ---- */
const gauges = $$('.gauge', $('#hero-gauges')).map(el => {
  const n = $('.gauge__n', el), v = parseFloat(n.textContent);
  return { el, n, bar: $('.bar10', el), part: el.dataset.part, of: +el.dataset.of, dec: +(el.dataset.dec || 0), start: v, value: v, target: v, text: '', lit: -1, level: '' };
});
const MEM = gauges.find(g => g.part === 'MEM');
const RANGE = { MEM: [60, 66], CPU: [12, 46], TEMP: [44, 53], FAN: [1.3, 1.3], BAT: [100, 100] };
const LINES = { CPU: [70, 90], TEMP: [80, 95] };   // amber, red: these two follow their own reading
// MEM never turns on a percentage: it takes the colour of macOS memory pressure (1 normal, 2 warning, 4 critical), and so does
// SWAP, shown in the FAN slot on a Mac without a fan. This demo Mac is under no pressure. BAT reads CHG: on mains power, it never warns.
const PRESSURE = 1;
const level = (v, warn, crit) => (v >= crit ? 'red' : v >= warn ? 'amber' : '');
const levelOf = g => {
  if (g.part === 'MEM' || g.part === 'FAN') return level(PRESSURE, 2, 4);
  const l = LINES[g.part]; return l ? level(g.value, l[0], l[1]) : '';
};
function paint(g, value = g.value) {
  const text = value.toFixed(g.dec), lit = Math.round(clamp(value / g.of, 0, 1) * 10), lv = levelOf(g);
  if (text !== g.text) { g.n.textContent = text; g.text = text; }
  if (lit !== g.lit) { g.bar.style.setProperty('--lit', lit); g.lit = lit; }
  if (lv !== g.level) { g.bar.dataset.level = lv; g.level = lv; }
}
function updateAlert() {   // the warning line watches MEM, CPU, TEMP and BAT, not SWAP or FAN (Console.swift)
  const levels = gauges.filter(g => g.part !== 'FAN').map(levelOf);
  alertEl.dataset.level = levels.includes('red') ? 'red' : levels.includes('amber') ? 'amber' : '';
}

let revealed = true, visible = true, timers = [], raf = 0, liveTimer = 0, freed = 0;   // freed: what force-quitting has taken off MEM, in percent
function tick() {
  for (const g of gauges) {
    let [lo, hi] = RANGE[g.part];
    if (lo === hi || g.busy) continue;
    if (g === MEM) { lo -= freed; hi -= freed; }
    const cpu = g.part === 'CPU';
    if (Math.random() < (cpu ? .22 : .06)) g.target = rand(lo, hi);
    g.value = clamp(g.value + (g.target - g.value) * (cpu ? .45 : .2) + rand(-.15, .15) * (cpu ? 2 : 1), lo - 1, hi + 1);
    if (revealed) paint(g);
  }
  updateAlert();
}
/* Four readings a second while the panel is open, as in the app; only while the hero is on screen and it is the hero's turn to
   move, and not while the drawn pointer is showing how (one thing moves at a time). */
const myTurn = () => turns.current === stage;
function syncLive() {
  clearInterval(liveTimer); liveTimer = 0;
  if (open && visible && myTurn() && !reduced() && !showing) liveTimer = setInterval(tick, 250);
}

/* Numbers count up and the bars fill one segment at a time, once, each time the panel opens. */
function reveal() {
  timers.forEach(clearTimeout); timers = []; cancelAnimationFrame(raf);
  if (reduced() || device.classList.contains('is-instant')) { gauges.forEach(g => paint(g)); revealed = true; return; }
  revealed = false;
  gauges.forEach(g => { g.n.textContent = (0).toFixed(g.dec); g.text = ''; g.bar.style.setProperty('--lit', 0); g.lit = -1; g.level = ''; g.bar.dataset.level = ''; });
  const t0 = performance.now() + 140, dur = 420;
  const step = now => {
    const p = ease((now - t0) / dur);
    gauges.forEach(g => { g.n.textContent = (now < t0 ? 0 : g.value * p).toFixed(g.dec); });
    if (now - t0 < dur) raf = requestAnimationFrame(step); else { revealed = true; gauges.forEach(g => paint(g)); }
  };
  raf = requestAnimationFrame(step);
  gauges.forEach((g, col) => {
    const lit = Math.round(clamp(g.value / g.of, 0, 1) * 10);
    for (let i = 0; i < lit; i++) timers.push(setTimeout(() => { if (open) g.bar.style.setProperty('--lit', i + 1); }, 220 + col * 30 + i * 20));
  });
}

/* ---- the prompt under the panel: its words follow the state (the CSS picks them: closed, open, or a key named by a first
   tap); it steps aside while the mirror or the list of apps is open, and while the drawn pointer is showing how ---- */
let showing = false, armed = null, armT = 0;
function syncHint() {
  notch.classList.toggle('is-quiet', showing || ((mirrorOn || freeing) && !armed));
  notch.classList.toggle('is-armed', !!armed);
}

/* ---- the mirror (Camera.swift): the picture between the gauges and the bar. The camera, the Mac's green light and the
   menu bar's green dot are on only while it shows: on a moment after the picture unfolds, off as it folds. ---- */
let mirrorOn = false, freeing = false, camT = 0;
function setCamera(v) {
  notch.dataset.cam = v ? 'on' : 'off';
  mirrorEl.classList.toggle('is-live', v);
  if (dot) { if (v) dot.dataset.on = 'cam'; else delete dot.dataset.on; }
}
function setMirror(v) {
  if (v === mirrorOn || (v && !open)) return;
  mirrorOn = v;
  mirrorEl.classList.toggle('is-on', v);
  mirrorBtn.setAttribute('aria-pressed', String(v));
  device.classList.toggle('has-mirror', v);
  clearTimeout(camT);
  if (reduced() || device.classList.contains('is-instant')) setCamera(v); else camT = setTimeout(() => setCamera(v), v ? 320 : 180);
  syncHint();
  if (v) intoView();
}
/* The picture makes the panel 273 points taller: if its foot would be under the window's edge, the page moves just enough. */
function intoView() {
  const top = notch.getBoundingClientRect().top, foot = top + (2 + CAP + readouts.offsetHeight - mirrorEl.offsetHeight + MIRROR) * k + 24;
  const by = Math.min(foot - innerHeight, top - 72);   // never so far that the notch goes under the nav
  if (by > 0) scrollBy({ top: by, behavior: reduced() ? 'auto' : 'smooth' });
}

/* ---- FREE: the bar becomes the four apps using the most memory; pressing one force-quits it, and its share comes off MEM
   (the same made-up Mac as the Numbers demo: 16 GB) ---- */
const RAM = 16, POOL = [['XCODE', 'Xcode', 3.4], ['SAFARI', 'Safari', 2.4], ['PHOTOS', 'Photos', 1.6], ['MUSIC', 'Music', .9], ['NOTES', 'Notes', .7], ['MAIL', 'Mail', .6]];
let apps = [], memRaf = 0, memGoal = null;   // memGoal: where MEM is falling to, until it is there
const inBar = () => notch.contains(document.activeElement) && !!document.activeElement.closest('.bar');
function appCell([key, name, gb]) {
  const b = document.createElement('button'), line = `${key} ${gb.toFixed(1)}`;   // Readouts.swift: the name and its GB, to one decimal
  b.type = 'button'; b.className = 'cell'; b.dataset.app = key;
  b.setAttribute('aria-label', `Force-quit ${name}, ${gb.toFixed(1)} GB`);
  b.innerHTML = `<span class="rest">${line}</span><span class="name">${line}</span>`;
  return b;
}
function backCell() {
  const b = document.createElement('button');
  b.type = 'button'; b.className = 'cell'; b.dataset.back = '';
  b.setAttribute('aria-label', 'Back to the tools');
  b.innerHTML = '<svg class="glyph" aria-hidden="true"><use href="#g-top"/></svg><span class="name">BACK</span>';
  return b;
}
function setFree(v) {
  if (v === freeing || (v && !open)) return;
  freeing = v;
  const had = inBar();
  if (v) { apps = POOL.slice(); barFree.replaceChildren(...apps.slice(0, 4).map(appCell), backCell()); }
  (v ? barFree : barTools).hidden = false;                                           // the bar that is coming first, then the focus, then the other goes:
  if (had) (v ? $('.cell', barFree) : freeBtn).focus({ preventScroll: true });       // the keyboard never leaves the panel
  (v ? barTools : barFree).hidden = true;
  syncHint();
}
function memTo(to, ms) {
  cancelAnimationFrame(memRaf);
  const from = MEM.value, t0 = performance.now();
  if (!ms) { MEM.busy = false; MEM.value = MEM.target = to; memGoal = null; paint(MEM); return; }
  MEM.busy = true;                                                                   // the live readings leave MEM alone while it falls
  const step = now => {
    const t = clamp((now - t0) / ms, 0, 1);
    MEM.value = MEM.target = from + (to - from) * Kit.wob(t);
    if (revealed) paint(MEM);
    if (t < 1 && open) memRaf = requestAnimationFrame(step); else { MEM.busy = false; if (t >= 1 && memGoal === to) memGoal = null; }
  };
  memRaf = requestAnimationFrame(step);
}
function quit(c) {
  const app = apps.find(a => a[0] === c.dataset.app);
  if (!app || c.classList.contains('is-gone')) return;
  const still = reduced(), had = document.activeElement === c;
  apps = apps.filter(a => a !== app);
  c.classList.remove('is-hot'); c.classList.add('is-gone');                          // its cell gives way,
  const next = apps[3];
  if (next) {                                                                        // the next heaviest slides in,
    const n = appCell(next);
    n.classList.add('is-new', 'is-moving');
    barFree.insertBefore(n, $('[data-back]', barFree));
    void n.offsetWidth;                                                              // laid out shut first, so it opens from there
    n.classList.remove('is-new');
    setTimeout(() => n.classList.remove('is-moving'), 520);
  }
  const from = memGoal ?? MEM.value, to = Math.max(18, from - app[2] / RAM * 100);   // from where it is, or is already falling to
  memGoal = to; freed += from - to; MEM.busy = true;                                // the live readings leave MEM alone until it has fallen
  if (said) said.textContent = `${app[1]} quit. Memory ${Math.round(to)}%.`;       // what a screen reader hears; the eye sees MEM fall
  setTimeout(() => { if (open) memTo(to, still ? 0 : 900); }, still ? 0 : 380);     // and then memory falls by its share
  setTimeout(() => {
    c.remove();
    if (!freeing) return;
    if (!apps.length) { setFree(false); return; }                                   // nothing left to quit: back to the tools
    if (had) ($('.cell:not(.is-gone)', barFree) || freeBtn).focus({ preventScroll: true });
  }, still ? 0 : 440);
}
barFree.addEventListener('click', e => {
  const c = e.target.closest('.cell'); if (!c) return;
  engage();
  if ('back' in c.dataset) setFree(false); else quit(c);
});

/* ---- opening and closing ---- */
function setOpen(v, quiet) {
  if (v === open) return;
  open = v;
  notch.classList.toggle('is-open', v);
  cap.setAttribute('aria-expanded', String(v));
  if ('inert' in panel) panel.inert = !v;
  if (!quiet) Sound.play(v ? 'open' : 'close');   // only the visitor's own opening sounds; what the page does by itself is silent
  clearTimeout(menuT);
  if (v) { reveal(); menuT = setTimeout(fitMenus, 170); }   // the menus go as the black reaches them
  else {
    disarm(); setMirror(false); setFree(false);
    cancelAnimationFrame(memRaf); MEM.busy = false; freed = 0; memGoal = null; MEM.value = MEM.target = MEM.start;   // closed, the demo Mac is as it was
    if (said) said.textContent = '';
    fitMenus();
  }
  syncLive(); updateAlert(); syncHint();
}
let menuT = 0;
/* Puts something in place at once, with no spring: the still frame, and the frame a show starts from. */
function instantly(fn) {
  device.classList.add('is-instant');
  fn();
  void device.offsetWidth;
  requestAnimationFrame(() => requestAnimationFrame(() => device.classList.remove('is-instant')));
}

/* ---- the drawn pointer: x from the middle of the screen, y from its top, in the lid's own pixels ---- */
const REST = [-62, 31];   // at the notch: the tip just inside it (hidden there, as on a Mac), the arrow on the panel between two gauges
const FROM = [-196, 236];   // and where it comes from: the open desktop, below and to the left
function place(p, ms = 0, curve = 'cubic-bezier(.45, .05, .25, 1)') {
  ptr.style.transition = ms ? `transform ${ms}ms ${curve}, opacity .25s ease-out` : 'none';
  ptr.style.transform = `translate(${p[0].toFixed(1)}px, ${p[1].toFixed(1)}px)`;
  if (!ms) { void ptr.getBoundingClientRect(); ptr.style.transition = ''; }
}
const pointer = v => ptr.classList.toggle('is-on', v);
const light = c => keys.forEach(el => el.classList.toggle('is-hot', el === c));
/* Where a key is, for the pointer: low and to the right of its middle, clear of its name. */
function keyAt(c) {
  const r = c.getBoundingClientRect(), n = notch.getBoundingClientRect();
  return [(r.left + r.width * .62 - (n.left + n.width / 2)) / k, (r.top + r.height * .72 - n.top) / k - 2];
}

/* ---- what plays by itself ----
   show('intro'), once after the page loads: the notch closed, the pointer comes up to it, the panel springs open, then the
   roll call along the function bar. show('back'), each time the panel has been left closed: the pointer comes back to the
   notch and the panel opens under it. Both end on the still frame: the panel open, the pointer resting at the notch. */
let want = 'intro', begun = false;   // begun: the intro has started, so a still frame from here on is the panel at rest
const scene = async wait => {
  const what = want;
  if (!what) return;
  showing = true; syncHint(); syncLive();
  if (what === 'intro') {
    begun = true;
    instantly(() => { setOpen(false, true); pointer(false); place(FROM); notch.classList.add('ready'); });
    await wait(1150);                                  // the page arrives first (if it is on its way elsewhere, the show waits for the next turn)
  } else {
    place(FROM);
  }
  want = '';
  pointer(true);
  await wait(380);
  place(REST, 760);
  await wait(700);
  setOpen(true, true);                                 // it opens under the pointer, as in the app
  if (what === 'intro') {
    await wait(1300);
    place(keyAt(keys[0]), 520);
    await wait(430);
    light(keys[0]);
    await wait(540);
    for (let i = 1; i < keys.length; i++) {            // along the bar: each key lights, with its name, while the pointer is on it
      place(keyAt(keys[i]), 300, 'cubic-bezier(.4, 0, .3, 1)');
      await wait(150);
      light(keys[i]);
      await wait(490);
    }
    await wait(180);
    light(null);
    place(REST, 820);
    await wait(900);
  } else {
    await wait(700);
  }
  showing = false; syncHint(); syncLive();
};
const show = player(scene, true);
/* The still frame, and where everything rests: the panel open, the pointer at the notch, nothing lit. */
function still() {
  if (want === 'intro' && !begun && !reduced()) return;   // until the show starts the notch is closed, as the CSS draws it until the script says ready
  want = '';
  showing = false;
  instantly(() => {
    light(null);
    setOpen(true, true); setMirror(false); setFree(false);
    place(REST); pointer(!hovering && !handsT);
    notch.classList.add('ready');
  });
  syncHint(); syncLive();
}
const act = { start() { syncLive(); if (want) show.start(); }, stop() { show.stop(); syncLive(); }, get active() { return show.active; } };

/* ---- a person's hands ----
   The pointer: only a real move counts. When the page scrolls under a pointer that is not moving, nothing opens or closes. */
let hovering = false, hoverT = 0, backT = 0, handsT = 0, lastType = 'mouse';
const kbInside = () => !!notch.querySelector(':focus-visible');
/* The visitor takes over: whatever was playing by itself stops where a hand needs it, and the drawn pointer steps aside. */
function engage(ms = 6000) {
  clearTimeout(backT);
  if (show.active || showing) { show.stop(); showing = false; light(null); notch.classList.add('ready'); }
  want = '';
  pointer(false);
  turns.hold(act);
  clearTimeout(handsT);
  handsT = setTimeout(() => { handsT = 0; turns.release(act); }, ms);
  syncLive(); syncHint();
}
/* Left closed, the panel does not stay closed: a moment later the drawn pointer comes back to the notch and it opens again. */
function comeBack(ms) {
  clearTimeout(backT);
  backT = setTimeout(() => {
    if (open || hovering || kbInside()) return;
    clearTimeout(handsT); handsT = 0;
    turns.release(act);
    if (reduced() || !myTurn() || !visible) { still(); return; }
    want = 'back';
    act.start();
  }, ms);
}
function enter() {
  hovering = true;
  engage(60000);
  clearTimeout(hoverT); hoverT = setTimeout(() => setOpen(true), 50);
}
function leave() {
  hovering = false;
  clearTimeout(hoverT);
  hoverT = setTimeout(() => {
    if (kbInside()) return;                                         // the keyboard is in the panel: it stays
    if (notch.contains(document.activeElement)) document.activeElement.blur();
    setOpen(false);
    engage(1400); comeBack(1200);
  }, 90);
}
document.addEventListener('pointermove', e => {
  if (e.pointerType === 'touch' || (Kit.moved && !Kit.moved(e))) return;   // the page moved, not the pointer
  const inside = notch.contains(e.target);
  if (inside !== hovering) (inside ? enter : leave)();
}, { passive: true });
document.documentElement.addEventListener('pointerleave', e => { if (hovering && e.pointerType !== 'touch') leave(); });
document.addEventListener('pointerdown', e => { lastType = e.pointerType || 'mouse'; }, { capture: true, passive: true });
const byTouch = e => e.detail !== 0 && (e.pointerType || lastType) === 'touch';

/* A finger, or the keyboard, on the notch itself opens and closes it; closed like that, it stays closed until asked. */
cap.addEventListener('click', e => {
  if (e.detail !== 0 && !byTouch(e)) return;                        // a mouse opens it by pointing
  engage();
  setOpen(!open);
  if (!open) comeBack(2400);                                        // and, closed, it opens again a moment later (not while the keyboard is on it)
});
notch.addEventListener('click', e => {                              // the closed notch is small: a tap beside it opens it too
  if (!open && byTouch(e) && !cap.contains(e.target)) { engage(); setOpen(true); }
});
/* A tap on the screen outside the panel is the pointer leaving: it closes, then comes back. Never the touch that starts a scroll. */
stage.addEventListener('click', e => {
  if (!byTouch(e) || notch.contains(e.target) || !open) return;
  setOpen(false);
  engage(2700); comeBack(2400);
});
notch.addEventListener('focusin', () => {
  if (!kbInside()) return;
  engage(60000);
  if (!open && document.activeElement === cap) setOpen(true);
});
notch.addEventListener('focusout', e => {
  if (notch.contains(e.relatedTarget) || hovering) return;
  engage(1700);
  if (!open) comeBack(1500);
});
notch.addEventListener('keydown', e => {
  if (e.key !== 'Escape' || !open) return;
  engage(60000);
  cap.focus({ preventScroll: true });                               // first the focus, to the notch itself; then the panel closes behind it
  setOpen(false);
});

/* The keys. MIRROR and FREE work here; the others lead to their sections. On a touch screen a first tap names a key, as
   the pointer would, and the next one goes there. */
function disarm() { clearTimeout(armT); if (armed) armed.classList.remove('is-hot'); armed = null; syncHint(); }
function arm(c) {
  disarm();
  armed = c; c.classList.add('is-hot');
  armT = setTimeout(disarm, 2800);
  syncHint();
}
function flash(c) { c.classList.add('is-hot'); setTimeout(() => { if (c !== armed) c.classList.remove('is-hot'); }, 900); }
barTools.addEventListener('click', e => {
  const c = e.target.closest('.cell'); if (!c) return;
  const touch = byTouch(e);
  engage();
  if (c === mirrorBtn) { disarm(); setMirror(!mirrorOn); if (touch) flash(c); }
  else if (c === freeBtn) { disarm(); setFree(true); }
  else if (touch && armed !== c) { e.preventDefault(); arm(c); }
  else {                                                            // a tool takes over: the panel closes, as in the app, and the page goes to its section
    hovering = false;
    setTimeout(() => { setOpen(false); comeBack(2200); }, 140);
  }
});

/* ---- on and off the screen ----
   The show waits for the hero's first turn, which comes as the page opens (it is the first thing on it), or when the hero
   is first scrolled to. If the hero is in view and no turn comes (another scene is nearer the middle), there is no show:
   the still frame. */
let waitT = 0, enough = true;   // enough of the stage shows for it to be given a turn (Kit.turns asks for 30%)
function awaitTurn() {
  clearTimeout(waitT);
  if (want === 'intro' && enough) waitT = setTimeout(() => { if (want === 'intro' && !show.active) { want = ''; still(); } }, 1600);
}
if ('IntersectionObserver' in window) {
  new IntersectionObserver(([e]) => {
    const was = visible, had = enough;
    visible = e.isIntersecting; enough = e.intersectionRatio >= .3;
    if (visible && !was && !hovering && !kbInside() && !show.active) still();   // back in view: open again, at rest
    if (enough !== had) awaitTurn();
    syncLive();
  }, { threshold: [0, .3] }).observe(stage);
}
if (Kit.onMotion) Kit.onMotion(off => { if (off && want === 'intro') { want = ''; still(); } });   // Motion switched off before the show: the still frame
addEventListener('resize', fit);
if (document.fonts && document.fonts.ready) document.fonts.ready.then(fit);

/* ---- first paint: the stage is fitted, then the hero takes its place among the page's scenes ---- */
fit();
place(REST);
whenVisible(stage, act, still);
awaitTurn();
})();

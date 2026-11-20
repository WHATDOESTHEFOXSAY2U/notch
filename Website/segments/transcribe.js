/* Notch website, segment 07 Transcribe. Uses window.Kit from ../app.js.
   One scene, one thing moving at a time: a video is picked up from the Desktop and dropped on the notch, which widens
   into TRANSCRIBE's band (DROP TO · TRANSCRIBE) and then its strip, filling as Scribe works; DONE with the word count,
   the card where a shot's card goes, and OPEN shows the text in TextEdit. The still frame (the markup) is that result.
   Positions are in the drawn screen's points: 1 px on the page, or 1/z of a px where a phone draws the screen smaller. */
(() => {
'use strict';
const Kit = window.Kit; if (!Kit) return;
const { $, $$, clamp, wob, tween } = Kit;
const root = $('#transcribe'); if (!root) return;

const bay = $('.tx', root), stage = $('.tx__stage', bay), cv = $('.tx__cv', bay);
const bar = $('.mbar', cv), menu = $('.mbar__l', bar), clock = $('.mbar__clock', bar), hole = $('.tx-hole', cv);
const file = $('.tx-file', cv), ghost = $('.tx-ghost', cv), win = $('.tx-win', cv), card = $('.tx-card', cv);
const open = $$('.tx-card__keys > span', card)[1], line = $('.tx-card__line', card);
const n = $('.tx-n', cv), word = $('.tx-n__stage', n), pc = $('.tx-n__pc', n), num = $('b', pc), segs = $('.tx-n__segs', n);
const ptr = $('.mptr', cv), steps = $$('.tx__steps .step', bay);

const SEGS = 49;     // Meter.swift: as many 6 + 2 point segments as fit with 12 clear on each side, beside a 180-point notch
const CARD = 6000;   // the card stays 6 seconds, the time not counting while the pointer is on it
const REACH = { x: 230, y: 90 };   // Transcribe.swift: how close to the notch a drag widens it
const MENUS = {
  finder: ['Finder', 'File', 'Edit', 'View', 'Go', 'Window', 'Help'],
  text: ['TextEdit', 'File', 'Edit', 'Format', 'View', 'Window', 'Help'],
};

/* ---------- the screen: its size, its scale, its menu bar ---------- */
let z = 1, W = 0, H = 0;
function fit() {
  const phone = bay.clientWidth < 600;   // the container query's line in transcribe.css
  z = phone ? Math.min(1, stage.clientWidth / 440) : 1;
  if (phone) stage.style.setProperty('--z', z.toFixed(4)); else stage.style.removeProperty('--z');
  W = cv.offsetWidth; H = cv.offsetHeight;
  fitClock();
}
/* The menu bar keeps clear of the notch (Kit.fitBar); short of room, macOS drops the clock's date before the time.
   Kit.clock() sets the time apart from the date with an en space. */
const timeOnly = () => { const t = Kit.clock(), i = t.lastIndexOf('\u2002'); return i >= 0 ? t.slice(i + 1) : t.split(/\s+/).slice(3).join(' '); };
function fitClock() {
  if (clock.hasAttribute('data-own')) { clock.removeAttribute('data-own'); Kit.tickClocks(); }
  Kit.fitBar(bar, hole);
  if (!clock.classList.contains('is-cut')) return;
  clock.setAttribute('data-own', '');
  clock.textContent = timeOnly();
  Kit.fitBar(bar, hole);
}
setInterval(() => { if (clock.hasAttribute('data-own')) clock.textContent = timeOnly(); }, 20000);

/* The app in front names the menu bar: Finder once the Desktop is clicked, TextEdit once it has opened the text. */
function front(app) {
  if (cv.dataset.app === app) return;
  cv.dataset.app = app;
  const [name, ...items] = MENUS[app];
  const b = document.createElement('b');
  b.textContent = name;
  menu.replaceChildren($('.mbar__apple', menu), b, ...items.map(t => { const s = document.createElement('span'); s.textContent = t; return s; }));
  fitClock();
}

/* ---------- the pointer, and the video under it while it is dragged ---------- */
let px = 0, py = 0, grip = null;   // the arrow's tip; while dragging, where it holds the picture (from the file's corner)
function put(x, y) {
  px = x; py = y;
  ptr.style.transform = `translate(${x.toFixed(2)}px, ${y.toFixed(2)}px)`;
  if (grip) ghost.style.transform = `translate(${(x - grip.x).toFixed(2)}px, ${(y - grip.y).toFixed(2)}px)`;
}
/* A hand's path: eased at both ends, bowing a little to one side. `each(p)` runs on every frame of it. */
async function glide(wait, x, y, ms, each, bow = 1) {
  const x0 = px, y0 = py, dx = x - x0, dy = y - y0, len = Math.hypot(dx, dy) || 1;
  const arc = Math.min(48, len * .1) * bow, nx = -dy / len, ny = dx / len;
  await tween(wait, ms, p => {
    const e = wob(p), b = Math.sin(Math.PI * e) * arc;
    put(x0 + dx * e + nx * b, y0 + dy * e + ny * b);
    if (each) each(p);
  });
}
// Where things are on the drawn screen (transcribe.css puts them there): the card's OPEN key, the file's own corner,
// and the grip on the video's picture.
const atOpen = () => ({ x: 168, y: H - 31 });   // on the key, clear of its name
const fileCorner = () => ({ x: file.offsetLeft, y: file.offsetTop });
const atGrip = () => { const c = fileCorner(); return { x: c.x + 52, y: c.y + 36 }; };

/* ---------- the notch ---------- */
function show(state) { n.dataset.state = cv.dataset.n = state; fitClock(); }   // what the shape covers of the menu bar goes, whole
/* The strip: what is being done, how far (0 to 1, or null where it cannot be measured: no number, no segments lit). */
function meter(stageName, f) {
  word.textContent = stageName;
  pc.classList.toggle('is-off', f == null);
  segs.style.setProperty('--lit', f == null ? 0 : Math.round(clamp(f, 0, 1) * SEGS));
  if (f != null) num.textContent = Math.floor(clamp(f, 0, 1) * 100);
}

/* ---------- the card's six seconds ---------- */
let since = 0, held = 0;   // when the card came; when the pointer came onto it (the time stops)
function tick() {
  if (!since) return;
  line.style.setProperty('--left', Math.max(0, 1 - ((held || performance.now()) - since) / CARD).toFixed(4));
}

/* ---------- the steps along the foot ---------- */
function step(i, p = 0) {
  steps.forEach((s, k) => { s.classList.toggle('is-on', k === i); s.style.setProperty('--p', k === i ? clamp(p, 0, 1).toFixed(3) : 0); });
}

/* ---------- the still frame: the result. The text open in TextEdit, the card with the pointer on OPEN, the notch closed. ---------- */
let settle = 0;
function still() {
  // Taken from a scene that was playing, the pointer and the dragged picture ease to where the still frame has them.
  if (cv.classList.contains('is-live')) {
    cv.classList.add('is-settle');
    clearTimeout(settle);
    settle = setTimeout(() => cv.classList.remove('is-settle'), 450);
  }
  cv.classList.remove('is-live');
  grip = null;
  ghost.classList.remove('is-on');
  show('idle');
  meter('TRANSCRIBING', 1);
  front('text');
  file.classList.add('is-sel');
  win.classList.remove('is-off');
  card.classList.add('is-in');
  since = 0; held = 0;
  line.style.setProperty('--left', .5);   // where the loop leaves it: three of the six seconds gone
  open.classList.add('is-hot');
  const o = atOpen();
  px = o.x; py = o.y;
  ptr.style.transform = '';   // transcribe.css rests it on OPEN
  step(2, 1);
}

async function scene(wait) {
  fit();
  cv.classList.add('is-live');
  // From the still frame: the card's six seconds run out and it slides away, then the text's window is closed.
  open.classList.remove('is-hot');
  card.classList.remove('is-in');
  since = 0; held = 0;
  step(0, 0);
  await wait(420);
  win.classList.add('is-off');
  line.style.setProperty('--left', 1);
  meter('READING', null);
  await wait(520);

  // 1. The video is picked up from the Desktop (Finder comes to the front) and dragged to the notch, which widens as
  //    it comes within reach; it is let go on the band.
  const cx = W / 2, g = atGrip(), c = fileCorner();
  await glide(wait, g.x, g.y, 1150, p => step(0, p * .4), -1);
  front('finder');
  await wait(160);
  grip = { x: g.x - c.x, y: g.y - c.y };
  put(px, py);
  ghost.classList.add('is-on');
  let near = false;
  const reach = () => { if (!near && py < REACH.y && Math.abs(px - cx) < REACH.x) { near = true; show('near'); } };
  // Just within reach, clear of the file it came from: the band opens as the pointer gets there and stops, then a
  // moment to read it, and onto the band.
  const e = { x: Math.min(cx + 226, g.x - 120), y: Math.min(g.y, 86) };
  await glide(wait, e.x, e.y, 1050, p => { if (p > .97) reach(); step(0, .4 + p * .35); }, .5);
  reach();
  await wait(700);
  await glide(wait, cx + 150, 17, 400, p => step(0, .75 + p * .25), 0);
  await wait(90);
  ghost.classList.remove('is-on');   // dropped: the picture is gone, and the band becomes the strip
  grip = null;
  show('work');
  step(1, 0);
  await wait(500);

  // 2. Scribe works on it: the pointer moves off the strip, and the strip fills.
  await glide(wait, Math.min(cx + 270, W - 44), H * .4, 700, p => step(1, p * .1));
  await wait(200);
  await tween(wait, 3800, p => { meter('TRANSCRIBING', p); step(1, .1 + p * .8); });
  meter('SPEAKERS', 1);   // the words are done; who said them is being finished
  await tween(wait, 750, p => step(1, .9 + p * .1));

  // 3. Done: DONE and the count for two seconds, and the card; then the pointer goes to the card (its time stops) and
  //    presses OPEN, and TextEdit shows the text.
  show('done');
  step(2, 0);
  const done = performance.now();
  await wait(450);   // DONE settles, then the card comes
  card.classList.add('is-in');
  since = performance.now();
  await tween(wait, Math.max(16, 2000 - (performance.now() - done)), p => { tick(); step(2, p * .2); });
  show('idle');
  await tween(wait, 380, tick);
  const o = atOpen();
  await glide(wait, o.x, o.y, 1050, p => { tick(); step(2, .2 + p * .2); }, -.7);
  held = performance.now();
  tick();
  open.classList.add('is-hot');
  await wait(320);   // pressed (a key acts as the button goes down), and TextEdit opens the file
  front('text');
  win.classList.remove('is-off');
  await tween(wait, 3800, p => step(2, .4 + p * .6));
}

const auto = Kit.player(scene);
fit();
Kit.whenVisible(bay, auto, still);

/* A bay of another width is a screen laid out anew: a loop under way starts again from the still frame, so that
   nothing moves to where things were. */
let wide = bay.clientWidth, again = 0;
function resized() {
  fit();
  if (bay.clientWidth === wide) return;
  wide = bay.clientWidth;
  clearTimeout(again);
  again = setTimeout(() => { if (!auto.active) return; auto.stop(); still(); auto.start(); }, 250);
}
addEventListener('resize', resized);
if ('ResizeObserver' in window) new ResizeObserver(resized).observe(bay);
document.addEventListener('DOMContentLoaded', fit);
addEventListener('load', fit);
if (document.fonts && document.fonts.ready) document.fonts.ready.then(fit);
})();

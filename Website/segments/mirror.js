/* Notch website, segment 06 Mirror (Readouts.swift, Camera.swift, Console.swift).
   The top of a Mac's screen, and the panel open from the notch with the camera's picture between the gauges and the
   function bar. MIRROR opens and closes the picture, as in the app; the camera, and with it the Mac's green light and the
   green dot in the menu bar, runs only while the picture shows.
   The scene, in the app's own order: a look; MIRROR pressed again, the picture folds and the camera stops; the pointer is
   left off the panel, so the panel closes; pointing at the notch opens it; MIRROR opens the picture. A visitor can do the
   same: point at the notch, press MIRROR (or the picture); the scene waits while they do.
   Uses window.Kit from ../app.js. The loop runs only on its turn (Kit.whenVisible); with motion off only the still frame shows. */
(() => {
'use strict';
const Kit = window.Kit; if (!Kit) return;
const { $, $$, clamp, ease, reduced, player, whenVisible, handsOn, tween, fitBar, onMotion } = Kit;

const root = $('#mirror'); if (!root) return;
const look = $('.mr-look', root), stage = $('.mr-stage', root), panel = $('.mr-panel', root), spot = $('.mr-spot', root);
const key = $('.mr-key', root), tools = $('.mr-bar', root), cam = $('.mr-cam', root), gaugeRow = $('.mr-gauges', root);
const bar = $('.mbar', root), dot = $('.mbar__dot', root);
if (!look || !stage || !panel || !key || !tools || !cam || !gaugeRow) return;

/* ---- the scene's one scale, and where things are in it ----
   The panel is drawn at its own size and never larger; only a stage too narrow for it (a phone) shows the whole scene
   smaller, the menu bar with it, and is then as tall as the open panel needs. The panel's parts keep their sizes whatever
   its state, so its open height, and where MIRROR is with the picture open and closed, can be measured at any moment.
   As on a Mac, nothing in the menu bar runs under the panel: what would is left out, whole (Kit.fitBar). */
const PANEL_W = 500, TOP = 32, PICTURE = 12 + 261;   // the panel; the notch's band; the picture and the gap above it (Readouts.swift)
const phone = matchMedia('(max-width: 720px)');
const put = (name, v) => { const s = v.toFixed(1) + 'px'; if (look.style.getPropertyValue(name) !== s) look.style.setProperty(name, s); };
function fit() {
  const w = stage.clientWidth;
  if (!w) return;
  const z = clamp((w - 24) / PANEL_W, .4, 1);
  look.style.setProperty('--mz', z.toFixed(3));
  const unit = gaugeRow.offsetWidth / (PANEL_W - 36) || 1;                 // 1 where sizes are reported unzoomed, the zoom where they are not
  const g = gaugeRow.offsetHeight / unit, b = tools.offsetHeight / unit;
  const shut = TOP + 6 + g + 14 + 1, open = shut + PICTURE;                // the function bar's top edge, the picture closed and open
  put('--cam-y', TOP + 6 + g + 12); put('--spot-h', PICTURE - 12 + 14 + 1 + b);                     // the picture, down to the foot of the key under it
  put('--up-y', shut + b * .7); put('--key-y', open + b * .7);                                      // the pointer's tip: low in the key, clear of its name,
  put('--key-x', (key.offsetLeft + key.offsetWidth * .85) / unit);                                  // and to its right, wherever the key is in the bar
  const tall = phone.matches ? Math.ceil((open + b) * z + 58) + 'px' : '';
  if (stage.style.height !== tall) stage.style.height = tall;
  if (!bar) return;
  fitBar(bar, panel);
  const left = $('.mbar__l', bar), name = left && $('b', left);
  if (name) { left.style.visibility = ''; if (name.getBoundingClientRect().right > panel.getBoundingClientRect().left - 8) left.style.visibility = 'hidden'; }   // not even the app's name fits: a crop of the screen, with no menus in it
}
fit();
if ('ResizeObserver' in window) new ResizeObserver(fit).observe(stage); else addEventListener('resize', fit);
addEventListener('load', fit);
if (document.fonts && document.fonts.ready) document.fonts.ready.then(fit);

/* ---- the state: the panel open or closed, the mirror in it, and the camera (its light) on or off ----
   Opening the mirror: the picture unfolds black, the camera starts a moment later (its light comes on), and the picture
   comes up out of the dark as the exposure settles. Closing: the picture folds away and the camera stops. */
let panelOn = true, mirrorOn = true, token = 0, timer = 0, settled = 0;
const setCam = v => {
  look.dataset.cam = v ? 'on' : 'off';
  if (dot) { if (v) dot.dataset.on = 'cam'; else delete dot.dataset.on; }
};
function setMirror(v, instant = false) {
  mirrorOn = v;
  const mine = ++token;
  clearTimeout(timer); clearTimeout(settled);
  cam.classList.remove('is-waking');
  look.dataset.mirror = v ? 'on' : 'off';
  key.setAttribute('aria-pressed', String(v));
  if (instant || reduced()) { setCam(v); return; }
  if (v) {
    setCam(false);
    timer = setTimeout(() => {
      if (mine !== token) return;
      void cam.offsetWidth;   // restart the exposure from the dark
      cam.classList.add('is-waking'); setCam(true);
      settled = setTimeout(() => { if (mine === token) cam.classList.remove('is-waking'); }, 1600);
    }, 320);
  } else {
    timer = setTimeout(() => { if (mine === token) setCam(false); }, 180);
  }
}
const setPanel = v => { panelOn = v; look.dataset.panel = v ? 'on' : 'off'; };
const live = v => cam.classList.toggle('is-live', v && !reduced());
onMotion(still => { if (still) live(false); });

/* The gauges: as the panel opens the numbers count up once and the bars fill a segment at a time, column after column
   (Readouts.swift; the same timing as the hero's panel). */
const gauges = $$('.gauge', gaugeRow).map(el => {
  const n = $('.gauge__n', el), bar10 = $('.bar10', el), text = n.textContent;
  return { n, bar10, value: parseFloat(text), dec: (text.split('.')[1] || '').length, lit: +bar10.style.getPropertyValue('--lit') || 0 };
});
const show = (g, value, lit) => { const t = value.toFixed(g.dec); if (g.n.textContent !== t) g.n.textContent = t; g.bar10.style.setProperty('--lit', lit); };
const settle = () => gauges.forEach(g => show(g, g.value, g.lit));
async function countUp(wait) {
  gauges.forEach(g => show(g, 0, 0));
  await wait(140);
  await tween(wait, 420, p => gauges.forEach((g, col) => show(g, g.value * ease(p), clamp(Math.floor((p * 420 - 80 - col * 30) / 20) + 1, 0, g.lit))));
  settle();
}

/* The drawn pointer: on MIRROR at the foot of the open picture ('key'), where MIRROR is while the picture is closed ('up':
   on the picture, once it has opened), on the notch, or put away while a visitor's own pointer is at work ('off').
   The key is lit while the pointer is on it (Readouts.swift: a cell fills white under the pointer). */
const hot = v => key.classList.toggle('is-hot', v);
const onKey = to => to === 'key' || to === 'up';
async function glide(wait, to) {
  const from = look.dataset.ptr;
  if (from === to) { hot(onKey(to)); return; }
  hot(false);
  if (from === 'off') {                    // back after a visitor's turn: it fades in where the story goes on, it does not fly there
    look.classList.add('is-placing'); look.dataset.ptr = to; void look.offsetWidth; look.classList.remove('is-placing');
    await wait(300);
    hot(onKey(to));
    return;
  }
  look.dataset.ptr = to;
  if (!onKey(to)) { await wait(740); return; }
  await wait(360); hot(true);              // the key lights as the pointer crosses into it, a moment before it comes to rest
  await wait(180);
}

/* ---- the scene (about 8 s a round) ---- */
const scene = async wait => {
  live(true);
  // From wherever the last round, or a visitor, left it: the panel opens under the pointer; MIRROR opens the picture.
  if (!panelOn) {
    await glide(wait, 'notch');
    setPanel(true);
    await countUp(wait);
    await wait(160);
  }
  if (!mirrorOn) {
    await glide(wait, 'up');
    await wait(320);
    hot(false); setMirror(true);          // pressed: the bar drops away, and the pointer is left on the picture
    await wait(1600);                      // the camera starts and its exposure settles
  }
  await glide(wait, 'key');
  await wait(2200);                        // a look
  hot(false); setMirror(false);            // pressed again: the picture folds, the camera stops, the bar leaves the pointer behind
  await wait(650);
  setPanel(false);                         // and with the pointer no longer on it, the panel closes
  await wait(800);
};
const p = player(scene);
// The still frame: the panel open, the mirror showing, the camera on, the pointer on MIRROR; put in place at once.
function still() {
  look.classList.add('is-instant');
  settle(); setPanel(true); setMirror(true, true); look.dataset.ptr = 'key'; hot(true); live(false);
  void look.offsetWidth;
  requestAnimationFrame(() => requestAnimationFrame(() => look.classList.remove('is-instant')));
}
whenVisible(look, p, still);

/* ---- a visitor's hands ----
   The panel is theirs: their pointer moving onto it (onto the notch, while it is closed) opens it, as in the app, and
   MIRROR is theirs to press. The scene stops as they move on the panel, press, tap, or reach the key with the keyboard,
   and plays on a little after they are done (Kit.handsOn). A press on the picture works the key too, and so does a press
   where the picture and the key were once it has folded away (.mr-spot, and the bar that moved up into that place):
   closing the picture moves the key a long way, and a second press in the same place must not miss. */
key.addEventListener('click', () => {
  if (!panelOn) setPanel(true);
  setMirror(!mirrorOn);
  live(mirrorOn);
});
handsOn(panel, p, () => { settle(); if (!panelOn) setPanel(true); look.dataset.ptr = 'off'; hot(false); live(mirrorOn); });
// Where a press lands is measured, not hit-tested: while the picture folds, what lies under the finger changes from frame to frame.
const inside = (r, e) => e.clientX >= r.left && e.clientX < r.right && e.clientY >= r.top && e.clientY < r.bottom;
stage.addEventListener('click', e => {
  if (!panelOn || e.target.closest('.mr-key')) return;
  if (inside((mirrorOn || !spot ? cam : spot).getBoundingClientRect(), e)) key.click();
});
})();

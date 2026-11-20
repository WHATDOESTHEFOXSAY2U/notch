/* ==========================================================================
   Notch website: the shared kit (window.Kit) and the page-wide behaviour.
   No dependencies, no network. One demo plays at a time: the one nearest the
   middle of the screen; every other one shows its still frame. With Reduce
   Motion set, or with the page's Motion switch off, every demo shows only its
   still frame (as the app does).
   ========================================================================== */
(() => {
'use strict';

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const ease = t => 1 - Math.pow(1 - clamp(t, 0, 1), 3);
const rand = (a, b) => a + Math.random() * (b - a);
const onMedia = (q, f) => (q.addEventListener ? q.addEventListener('change', f) : q.addListener(f));   // older Safari has only addListener
const CANCEL = Symbol('cancel');

/* ---------- motion: one gate for the whole page ----------
   reduced() is true while nothing may move by itself: Reduce Motion is set on the visitor's device, or the visitor has
   switched Motion off on the page. The switch is any element with the attribute data-motion (aria-pressed says whether
   motion is on; a .lamp inside it is lit with it); the choice lasts for the visit. <html> has .is-still while reduced()
   is true, for the stylesheets. Kit.onMotion(fn) calls fn(reduced()) whenever the answer changes, whichever of the two
   changed it: a script that keeps a timer of its own running listens there. */
const mq = matchMedia('(prefers-reduced-motion: reduce)');
const MOTION_KEY = 'notch-motion';
let paused = false;
try { paused = sessionStorage.getItem(MOTION_KEY) === 'off'; } catch {}
const reduced = () => mq.matches || paused;
const motionSubs = [], ownTitle = new WeakMap();
const onMotion = f => { motionSubs.push(f); };
function showMotion() {
  const still = reduced();
  document.documentElement.classList.toggle('is-still', still);
  $$('[data-motion]').forEach(b => {
    const lamp = $('.lamp', b);
    b.setAttribute('aria-pressed', String(!still));
    if (lamp) lamp.classList.toggle('on', !still);
    // With Reduce Motion set on the device the page never moves, so the switch has nothing to switch: it says why.
    if (mq.matches && !ownTitle.has(b)) {
      ownTitle.set(b, b.getAttribute('title'));
      b.setAttribute('aria-disabled', 'true'); b.title = 'Reduce Motion is on in your device’s settings';
    } else if (!mq.matches && ownTitle.has(b)) {
      const was = ownTitle.get(b);
      ownTitle.delete(b); b.removeAttribute('aria-disabled');
      if (was === null) b.removeAttribute('title'); else b.title = was;
    }
  });
}
function motionChanged() { showMotion(); const still = reduced(); motionSubs.forEach(f => { try { f(still); } catch (e) { console.error(e); } }); }
const Motion = {
  get on() { return !reduced(); },
  set(on) {
    if (paused === !on) return;
    paused = !on;
    try { if (paused) sessionStorage.setItem(MOTION_KEY, 'off'); else sessionStorage.removeItem(MOTION_KEY); } catch {}
    motionChanged();
  },
  toggle() { Motion.set(paused); },
};
onMedia(mq, motionChanged);
showMotion();
document.addEventListener('click', e => { if (!mq.matches && e.target.closest && e.target.closest('[data-motion]')) Motion.toggle(); });

/* ---------- the pointer: where it last really was ----------
   A page that scrolls under a pointer at rest makes the browser fire enter, leave and move events for it, although the
   person did nothing. moved(event) is true only when the pointer itself moved: demos that answer the pointer ask it, so
   that scrolling past never takes one over. */
let ptX = NaN, ptY = NaN, ptEvent = null, ptMoved = false;
addEventListener('pointermove', e => {
  if (e.pointerType === 'touch') return;
  ptMoved = e.clientX !== ptX || e.clientY !== ptY;
  ptX = e.clientX; ptY = e.clientY; ptEvent = e;
}, { capture: true, passive: true });
const moved = e => e.pointerType === 'touch' || (e === ptEvent ? ptMoved : !Number.isNaN(ptX) && (e.clientX !== ptX || e.clientY !== ptY));

/* A loop that can be stopped from outside: its waits reject once it is stopped, so a scene never runs on after that.
   wait(ms) is a pause; wait.frame() is the next frame the display draws (for anything that moves a little each frame).
   After each full pass it calls its `looped` hook, if it has one (the turns below use it). */
function player(scene, once = false) {
  let token = 0, active = false;
  const api = {
    start() {
      if (active) return;
      active = true;
      const mine = ++token;
      const alive = () => mine === token;
      const wait = ms => new Promise((res, rej) => setTimeout(() => (alive() ? res() : rej(CANCEL)), ms));
      wait.frame = () => new Promise((res, rej) => requestAnimationFrame(t => (alive() ? res(t) : rej(CANCEL))));
      (async () => {
        try { do { await scene(wait, alive); if (alive() && api.looped) api.looped(); } while (!once && alive()); }
        catch (e) { if (e !== CANCEL) console.error(e); }
        finally { if (alive()) active = false; }
      })();
    },
    stop() { token++; active = false; },
    get active() { return active; },
  };
  return api;
}

/* ---------- one scene at a time (Kit.turns) ----------
   Every scene registered through whenVisible takes turns. The scene nearest the middle of the screen has the turn (it must
   show at least 30% of itself, or fill 30% of the screen), and stays the nearest until another is a tenth of a screen
   nearer, so two close ones never flicker. After each full loop the turn passes on, in reading order, among the scenes
   level with the nearest one (side by side) and the scenes of its section that show at least 60% of themselves; it comes
   back to the nearest when the round is done, or at once when scrolling makes another scene the nearest. A player()
   reports its loops itself; a hand-made scene object ({ start, stop }) calls its own `looped()` (set here) after a round.
   A scene without the turn is stopped and shows its still frame: once when it is registered, and again each time it loses
   the turn, so a scene's loop must undo at its start anything its still frame changed. Calls to a registered scene's
   start() from anywhere else are let through only on its turn.
   While reduced() is true nothing here ever starts a scene: not a turn, not a release, not a scene's own call to start().
   When it turns true the playing scene stops on its still frame; when it turns false the nearest one starts. */
const Turns = (() => {
  const list = [], held = new WeakSet();
  let cur = null, near = null, queued = 0;
  const viewH = () => window.innerHeight || document.documentElement.clientHeight;
  // A window this small is lab/shot.mjs resizing the page for a capture, never a person: the turn stays where it is.
  // (It goes when lab/ goes: the README's list before publishing.)
  const tiny = () => viewH() < 100 || (window.innerWidth || document.documentElement.clientWidth) < 100;
  // null when too little of the scene shows; otherwise how far it is from the middle line (0 when it crosses it),
  // where it is, and whether most of it shows (60% of itself, or of the screen if it is taller than the screen)
  function where(rec, h) {
    const r = rec.root.getBoundingClientRect();
    if (!r.width || !r.height) return null;
    const shown = Math.min(r.bottom, h) - Math.max(r.top, 0), all = Math.min(r.height, h);
    if (shown <= 0 || shown < all * .3) return null;
    const mid = h / 2;
    return { d: r.top > mid ? r.top - mid : r.bottom < mid ? mid - r.bottom : 0, top: r.top, left: r.left, most: shown >= all * .6 };
  }
  // A scene whose own code throws must not stop the others: its error is reported and the turn goes on.
  const safe = f => { try { f(); } catch (e) { console.error(e); } };
  function give(rec) {
    if (rec === cur || reduced()) return;
    const was = cur;
    cur = rec;
    if (was) { safe(was.halt); if (was.still) safe(() => was.still()); }
    if (rec && !held.has(rec.p)) safe(rec.go);
  }
  function pick() {
    queued = 0;
    if (tiny() || reduced()) return;
    const h = viewH(), was = near;
    let best = null, bestD = Infinity, atNear = null, atCur = null;
    for (const rec of list) {
      const w = where(rec, h);
      if (!w) continue;
      if (rec === near) atNear = w;
      if (rec === cur) atCur = w;
      if (w.d < bestD) { bestD = w.d; best = rec; }
    }
    if (atCur && held.has(cur.p)) return;                    // a scene a person is driving keeps the turn for as long as it shows
    if (!atNear || atNear.d > bestD + h * .1) near = best;   // hysteresis: the nearest stays the nearest until another is a tenth of a screen nearer
    // A scene of the nearest one's section that was passed the turn keeps it while most of it shows and the nearest has not changed.
    if (near && near === was && cur && cur !== near && atCur && atCur.most && cur.sec && cur.sec === near.sec) return;
    give(near);
  }
  const schedule = () => { if (!queued) queued = requestAnimationFrame(pick); };
  // After a full loop the turn passes to the next scene of the round, in reading order, if there is one.
  function looped(rec) {
    if (rec !== cur) return;
    const h = viewH(), me = where(rec, h);
    if (!me) return;
    const lead = near || rec, at = (lead !== rec && where(lead, h)) || me;
    const round = list.map(r => [r, r === rec ? me : where(r, h)])
      .filter(([r, w]) => w && (r === rec || !held.has(r.p)) && (w.d <= at.d + 1 || (w.most && r.sec && r.sec === lead.sec)));
    if (round.length < 2) return;
    round.sort((a, b) => (Math.abs(a[1].top - b[1].top) > 24 ? a[1].top - b[1].top : a[1].left - b[1].left));
    const i = round.findIndex(([r]) => r === rec);
    give(round[(i + 1) % round.length][0]);
  }
  function add(root, p, still) {
    if (find(p)) return;
    const go = p.start.bind(p), halt = p.stop.bind(p);
    const rec = { root, p, still, go, halt, sec: root.closest('section') };
    p.start = () => { if (cur === rec && !held.has(p) && !reduced()) go(); };   // any other call to start (a pointer leaving, the scene's own code) waits for its turn
    p.looped = () => looped(rec);
    list.push(rec);
    if (still) safe(still);
    schedule();
  }
  function find(p) { return list.find(r => r.p === p); }
  /* hold(scene): a person is driving this scene (a pointer moved on it, a key pressed, a gesture tried): it takes the turn,
     its loop stays stopped, and nothing else moves. release(scene): they let go; its loop plays again if it still has the
     turn. A scene that was never registered has no turn, so releasing it starts nothing; while reduced() nothing starts. */
  function hold(p) {
    held.add(p);
    const rec = find(p);
    if (rec && where(rec, viewH())) { near = rec; give(rec); }
  }
  function release(p) {
    held.delete(p);
    const rec = find(p);
    if (!rec) return;
    if (rec === cur && !reduced() && where(rec, viewH())) safe(rec.go);
    schedule();
  }
  // Motion off (the device's setting or the page's switch): everything stops, the scene that was playing on its still frame.
  // On again: the scene nearest the middle starts.
  onMotion(still => {
    if (!still) { schedule(); return; }
    list.forEach(r => safe(r.halt));
    if (cur && cur.still) { const c = cur; safe(() => c.still()); }
    cur = near = null;
  });
  addEventListener('scroll', schedule, { passive: true });
  addEventListener('resize', schedule);
  addEventListener('load', schedule);
  // `current`: the root whose turn it is; `playing`: the roots of the registered scenes running right now (for checking).
  return { add, hold, release, schedule, get current() { return cur ? cur.root : null; }, get playing() { return list.filter(r => r.p.active).map(r => r.root); } };
})();

/* Registers a scene: it draws its still frame at once and plays only on its turn (above). While reduced() it never plays. */
function whenVisible(el, p, still) { Turns.add(el, p, still); }

/* ---------- sound: the app's own tones, worked out the way Sounds.swift does ---------- */
const Sound = (() => {
  const TONES = {   // [from Hz, to Hz, seconds, loudness]
    tick: [[2000, 2000, .010, .18]],
    press: [[1000, 1000, .030, .35]],
    open: [[330, 415, .20, .09]],
    close: [[415, 330, .20, .07]],
    listen: [[587, 587, .07, .10], [784, 784, .10, .10]],
    heard: [[784, 784, .07, .09], [587, 587, .10, .09]],
    copied: [[440, 440, .09, .09]],
  };
  const soft = n => n !== 'tick' && n !== 'press';
  const subs = [];
  let ctx = null, on = false;
  function play(name) {
    if (!on || !ctx) return;
    let at = ctx.currentTime + .004;
    for (const [from, to, len, loud] of TONES[name]) {
      const osc = ctx.createOscillator(), gain = ctx.createGain(), N = 48, curve = new Float32Array(N);
      for (let i = 0; i < N; i++) {
        const along = i / (N - 1), time = along * len;
        curve[i] = loud * (soft(name)
          ? Math.pow(Math.sin(Math.PI * along), 2)                                                    // swells and fades
          : Math.min(1, time * 1000) * Math.exp(-3 * along) * Math.min(1, (len - time) * 500));       // starts sharply, dies away
      }
      osc.frequency.setValueAtTime(from, at);
      osc.frequency.linearRampToValueAtTime(to, at + len);
      gain.gain.setValueCurveAtTime(curve, at, len);
      osc.connect(gain); gain.connect(ctx.destination);
      osc.start(at); osc.stop(at + len + .02);
      at += len;
    }
  }
  function set(v) {
    if (v && !ctx) { try { ctx = new (window.AudioContext || window.webkitAudioContext)(); } catch { v = false; } }
    on = !!v;
    if (ctx && ctx.state === 'suspended') ctx.resume();
    subs.forEach(f => f(on));
    if (on) play('open');
  }
  return { play, set, toggle: () => set(!on), get on() { return on; }, subscribe: f => subs.push(f) };
})();

/* Touch or pointer, for the words that say "point" or "tap" (.when-point, .when-tap in styles.css): <html> is .is-touch
   while (hover: none) matches, and from the first real touch on, for screens that report hover wrongly. */
const touchQ = matchMedia('(hover: none)');
let touchSeen = false;
const touchSync = () => document.documentElement.classList.toggle('is-touch', touchSeen || touchQ.matches);
touchSync();
onMedia(touchQ, touchSync);
addEventListener('pointerdown', e => { if (e.pointerType === 'touch' && !touchSeen) { touchSeen = true; touchSync(); } }, { capture: true, passive: true });
const touch = () => touchSeen || touchQ.matches;

const Kit = window.Kit = { $, $$, clamp, ease, rand, reduced, onMotion, motion: Motion, moved, touch, player, whenVisible, turns: Turns, Sound };

/* ---------- helpers the segment scenes share (segments/*.js) ---------- */
const fmt = s => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
const wob = t => t < .5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;   // ease in and out

/* Calls fn(0..1) over ms, once for each frame the display draws, through the scene's own wait so a stopped scene stops mid-way. */
async function tween(wait, ms, fn) {
  const t0 = performance.now();
  for (;;) {
    const p = clamp((performance.now() - t0) / ms, 0, 1);
    fn(p);
    if (p >= 1) return;
    await (wait.frame ? wait.frame() : wait(16));
  }
}
/* A key of the panel lights up for a moment, as under a press (.is-hot, the look a .cell has under the pointer), then does its thing. */
async function press(el, wait, ms = 170) { el.classList.add('is-hot'); await wait(ms); el.classList.remove('is-hot'); }

/* A person takes a scene over by doing something on `root`: moving the pointer on it, pressing or tapping in it, or
   reaching it with the keyboard. The scene then takes the turn, its loop stops (nothing else moves either) and onTake(),
   if given, draws what they take over. It plays on again 2.6 s after the last thing they did, if it still has the turn;
   with keyboard focus inside, it waits until the focus has left. A pointer that only rests there takes nothing, and
   neither does a page scrolling under it. */
function handsOn(root, auto, onTake) {
  let t = 0, mine = false;
  const keyed = () => { try { return !!root.querySelector(':focus-visible'); } catch { return root.contains(document.activeElement); } };
  const idle = () => { clearTimeout(t); t = setTimeout(done, 2600); };
  const done = () => { if (keyed()) { idle(); return; } mine = false; Turns.release(auto); };
  const take = () => {
    if (!mine) { mine = true; Turns.hold(auto); auto.stop(); if (onTake) onTake(); }
    idle();
  };
  root.addEventListener('pointermove', e => { if (e.pointerType !== 'touch' && moved(e)) take(); });
  root.addEventListener('pointerdown', e => { if (e.pointerType !== 'touch') take(); });   // a touch may be the start of a scroll: its tap arrives as a click
  root.addEventListener('click', take);
  root.addEventListener('keydown', take);
  root.addEventListener('focusin', () => { if (keyed()) take(); });
  root.addEventListener('focusout', e => { if (mine && !root.contains(e.relatedTarget)) idle(); });
}

/* ---------- the voice: the notch widens into a strip (Wings.swift). Used by dictation. ---------- */
const SPEECH = "Okay, so the plan for tomorrow is to ship the recording flow first and then write up the benchmarks. After that I want to send the summary to the team before lunch. Thanks.";
const PACE = .4;   // seconds of talking each word stands for: the demo types faster than anyone speaks, so the strip's clock counts by the words
function makeVoice(root) {
  const vn = $('.vn', root), left = $('.wing--l', root), right = $('.wing--r', root);
  const time = $('.vtime', root), wordsEl = $('.vwords', root), trans = $('.vtrans', root);
  const cLeft = $('.vc-l', root), cRight = $('.vc-r', root);
  const words = SPEECH.split(' ').map(t => ({ t, len: t.length }));
  const L = [], R = [];
  for (let i = 0; i < 12; i++) { const a = document.createElement('i'), b = document.createElement('i'); left.append(a); right.append(b); L.push(a); R.push(b); }

  // The strip's width in a line of the font, so lines wrap the way the app wraps them: by counting.
  const probe = document.createElement('span');
  probe.style.cssText = 'position:absolute;visibility:hidden;font-size:11px;white-space:pre;left:0;top:0';
  probe.textContent = '0'.repeat(40);
  trans.append(probe);
  const adv = probe.offsetWidth / 40 || 6.6;
  probe.remove();
  const perLine = Math.max(8, Math.floor((380 - 76 - 22) / adv));
  const starts = [0];
  let used = 0;
  words.forEach((w, i) => {
    if (used > 0 && used + 1 + w.len > perLine) { starts.push(i); used = w.len; } else used += (used > 0 ? 1 : 0) + w.len;
  });

  let lit = -1;
  const setLit = n => {
    if (n === lit) return;
    lit = n;
    L.forEach((el, i) => el.classList.toggle('on', 11 - i < n));   // lit from the notch outward
    R.forEach((el, i) => el.classList.toggle('on', i < n));
  };

  // The last three lines up to the `shown`th word, older lines fainter. A full line runs edge to edge. The clock and the
  // count follow the words.
  function render(shown) {
    let current = 0;
    starts.forEach((s, i) => { if (s < shown) current = i; });
    const frag = document.createDocumentFragment();
    for (let line = Math.max(0, current - 2); line <= current; line++) {
      const end = line + 1 < starts.length ? starts[line + 1] : words.length, full = line + 1 < starts.length, showing = shown - starts[line];
      const row = document.createElement('div');
      row.className = 'vline' + (full ? ' full' : '') + (line === current && showing <= 0 ? ' start' : '');
      row.style.opacity = line === current ? 1 : line === current - 1 ? .75 : .4;
      for (let i = starts[line]; i < end; i++) {
        const w = document.createElement('span');
        w.className = 'vword' + (i - starts[line] < showing ? ' on' : '') + (line === current && i === shown - 1 ? ' cur' : '');
        w.textContent = words[i].t;
        if (!full && i > starts[line]) w.style.marginLeft = adv + 'px';
        row.append(w);
      }
      frag.append(row);
    }
    trans.replaceChildren(frag);
    wordsEl.textContent = `${shown} WORD${shown === 1 ? '' : 'S'}`;
    time.textContent = fmt(Math.floor(shown * PACE));
  }

  function idle() { vn.dataset.state = 'idle'; setLit(0); render(0); }

  /* Listens, types the words on (from the `from`th, up to `limit`), then shows the stop band. `onCopied` runs when the text lands. */
  async function run(wait, { limit = words.length, from = 0, onCopied } = {}) {
    vn.dataset.state = 'voice';
    const t0 = performance.now();
    let shown = from, target = from, acc = 0, last = t0, nextBurst = 0, spoke = 0, level = from ? .6 : 0;
    render(shown);
    while (shown < limit) {
      const now = performance.now(), dt = (now - last) / 1000, el = (now - t0) / 1000;
      last = now;
      // The recogniser hands over a few words at a time; they type on at eight a second until caught up.
      if (el >= nextBurst && target < limit) { target = Math.min(limit, target + Math.round(rand(3, 6))); nextBurst = el + rand(.6, .95); spoke = el; }
      if (shown < target) {
        acc += dt * 8;
        const add = Math.floor(acc);
        if (add > 0) { acc -= add; shown = Math.min(target, shown + add); render(shown); }
      }
      level += ((el - spoke < .6 ? rand(.35, .95) : rand(.04, .22)) - level) * .45;
      setLit(Math.round(level * 12));
      await wait(33);
    }
    setLit(0);
    await wait(700);
    vn.dataset.state = 'copied';                                  // stopped: the text is on the clipboard, and in the text box
    cLeft.textContent = 'PASTED'; cRight.textContent = `${limit} WORDS`;
    if (onCopied) onCopied();
  }
  /* The strip part-way through: n words written, the level up. */
  function still(n = 25) { vn.dataset.state = 'voice'; render(n); setLit(7); }
  return { vn, idle, run, still };
}
Object.assign(Kit, { fmt, wob, tween, press, handsOn, SPEECH, makeVoice });

/* ---------- the Mac, drawn once (styles.css): what its parts need from script ---------- */
/* The Apple menu's sign exists only in Apple's fonts, so only Apple devices draw it (.mbar__apple). */
if (/Mac|iPhone|iPad|iPod/.test(navigator.platform || '') || /Macintosh|iPhone|iPad/.test(navigator.userAgent)) document.documentElement.classList.add('is-apple');
/* The clock as an English menu bar writes it where the visitor is: "Tue Nov 17 9:41 AM" in the United States,
   "Tue 17 Nov 09:41" in Britain. */
const REGION = (() => { try { return 'en-' + new Intl.Locale(navigator.language).maximize().region; } catch { return 'en-US'; } })();
const HOUR = /^h2/.test(new Intl.DateTimeFormat(REGION, { hour: 'numeric' }).resolvedOptions().hourCycle || '') ? '2-digit' : 'numeric';   // a 24-hour clock keeps its leading zero
function clock(d = new Date()) {
  const day = d.toLocaleDateString(REGION, { weekday: 'short', day: 'numeric', month: 'short' }), time = d.toLocaleTimeString(REGION, { hour: HOUR, minute: '2-digit' });
  return `${day.replace(/,/g, '')} ${time}`;   // the menu bar sets the time a little apart from the date
}
/* Every drawn menu bar shows the same time: the page's Macs are one Mac. A clock a scene runs itself is marked data-own. */
function tickClocks() { const t = clock(); $$('.mbar__clock:not([data-own])').forEach(el => { if (el.textContent !== t) el.textContent = t; }); }
/* Leaves out, whole, whatever would run under `hole` (the notch, or an open panel): menus from the right, then the things
   at the right end of the bar from the left. macOS never draws anything there. The Apple menu and the app's name stay. */
function fitBar(bar, hole, gap = 8) {
  const menus = $$('.mbar__l > *', bar), extras = $$('.mbar__r > *', bar);
  [...menus, ...extras].forEach(el => el.classList.remove('is-cut'));
  if (!hole) return;
  const h = hole.getBoundingClientRect();
  for (let i = menus.length - 1; i > 1 && menus[i].getBoundingClientRect().right > h.left - gap; i--) menus[i].classList.add('is-cut');
  for (const el of extras) { const r = el.getBoundingClientRect(); if (!r.width) continue; if (r.left >= h.right + gap) break; if (!el.matches('.mbar__cc, .mbar__clock')) el.classList.add('is-cut'); }   // macOS never hides Control Centre or the clock
}
Object.assign(Kit, { clock, tickClocks, fitBar });
document.addEventListener('DOMContentLoaded', () => { tickClocks(); setInterval(tickClocks, 20000); });

/* The Sound switch (#sound), and the app's two small sounds for the visitor's own pointer: a tick on reaching a control,
   a press on pressing one, as on the keys of the panel. Drawn controls inside a demo (aria-hidden) make none. */
(function wireSound() {
  const btn = $('#sound'), lamp = btn && $('.lamp', btn);
  if (btn) {
    btn.addEventListener('click', () => Sound.toggle());
    Sound.subscribe(on => { btn.setAttribute('aria-pressed', String(on)); if (lamp) lamp.classList.toggle('on', on); });
  }
  const control = e => { const t = e.target.closest && e.target.closest('a[href], button'); return t && !t.closest('[aria-hidden="true"]') ? t : null; };
  let last = null;
  document.addEventListener('pointerover', e => {
    if (!Sound.on || e.pointerType === 'touch' || !moved(e)) return;
    const t = control(e);
    if (t && t !== last) Sound.play('tick');
    last = t;
  }, true);
  document.addEventListener('pointerdown', e => { if (Sound.on && control(e)) Sound.play('press'); }, true);
})();

/* ---------- reveal on scroll; fit each bay's object to its stage ----------
   Both run again once every script has run (DOMContentLoaded), so parts a segment's script builds are included.
   A delay a segment set on an element itself (data-d, in ms) is kept. */
(function page() {
  let io = 'IntersectionObserver' in window && !reduced() ? new IntersectionObserver(es => es.forEach(e => {
    if (!e.isIntersecting) return;
    const el = e.target, d = +el.dataset.d || 0;
    el.style.transitionDelay = d + 'ms'; el.classList.add('in'); if (io) io.unobserve(el);
    setTimeout(() => { el.style.transitionDelay = ''; }, 1300 + d);
  }), { threshold: .1, rootMargin: '0px 0px -5% 0px' }) : null;
  const seen = new WeakSet();
  const stagger = (els, step, per) => els.forEach((el, i) => { if (el.dataset.d === undefined) el.dataset.d = (i % per) * step; });
  function reveal() {
    stagger($$('.rack .mod'), 70, 4);                          // the rack arrives along each row
    $$('.bays').forEach(g => stagger($$('.bay', g), 110, 2));  // bays side by side arrive one after another
    $$('.rv').forEach(el => {
      if (seen.has(el)) return;
      seen.add(el);
      if (io) io.observe(el); else el.classList.add('in');
    });
  }
  // Motion off: everything still waiting to arrive is simply there, and stays.
  onMotion(still => { if (!still || !io) return; io.disconnect(); io = null; $$('.rv').forEach(el => el.classList.add('in')); });
  // An object marked .grp is drawn at its own size (data-ow by data-oh) and shown at 1; only a stage too small for it shows it smaller, as one.
  function fitBays() {
    $$('.bay').forEach(t => {
      const g = $('.grp', t), st = $('.bay__stage', t); if (!g || !st) return;
      const ow = +g.dataset.ow, oh = +g.dataset.oh;
      const w = t.clientWidth, h = st.clientHeight, frac = w < 420 ? .92 : .8;
      t.style.setProperty('--z', clamp(Math.min(1, w * frac / ow, h * .94 / oh), .4, 1).toFixed(3));
    });
  }
  fitBays();
  const ready = () => { reveal(); fitBays(); };
  if (document.readyState === 'complete') reveal();
  else { document.addEventListener('DOMContentLoaded', ready); addEventListener('load', ready); }   // app.js is deferred: the segments' scripts run before DOMContentLoaded
  addEventListener('resize', fitBays);
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(fitBays);
})();

})();

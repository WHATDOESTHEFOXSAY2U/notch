/* Notch website, segment 02 Capture: one stage, the four tools played in turn: Shot, Text, Rec, Compress.
   Uses window.Kit from ../app.js. One thing moves at a time, and each step's result stays for a moment before the next
   step begins. The loop runs only while the segment is the one being watched (Kit.whenVisible). With Reduce Motion, while
   paused, or while another segment plays, the stage holds a still frame of one step; the four buttons under it pick the step. */
(() => {
'use strict';
const Kit = window.Kit, root = document.getElementById('capture');
if (!Kit || !root || !root.querySelector('.scr .mbar')) return;   // no stage to play on: the markup shows its own frame
const { $, $$, rand, reduced, player, whenVisible, tween, wob, fmt, Sound } = Kit;

const cap = $('.cap', root), stage = $('.cap__stage', root), scr = $('.scr', root);
const tabs = $$('.cap__step', root), playKey = $('.cap__play', root);
const win = { report: $('.win--report', scr), call: $('.win--call', scr) };
const bar = $('.mbar', scr), barLeft = $('.mbar__l', bar), barDot = $('.mbar__dot', bar), barDate = $('[data-date]', bar), barTime = $('[data-time]', bar);
const chart = $('[data-chart]', scr), table = $('[data-table]', scr);
const FILES = ['shot', 'rec', 'small'], files = {};
FILES.forEach(k => { files[k] = $(`[data-file="${k}"]`, scr); });
const clip = $('.clip', scr);
const card = $('.card', scr), cardTitle = $('.card__title', card), cardSize = $('.card__size', card), cardEta = $('.card__eta', card), cardPic = $('.card__pic', card);
const cells = $$('.card__cells i', card), cardLine = $('.card__line', card), zKey = $('.ckey--z', card);
const strip = $('.strip', scr), mainKey = $('.main', strip), mainT = $('.main__t', strip), mainFill = $('.main__fill', strip);
const ov = $('.ov', scr), sel = $('.sel', ov), selSize = $('.sel__size', ov);
const nn = $('.nn', scr), say = $('[data-say]', nn);
const hud = $('.hud', scr), hudKey = $('[data-hud-key]', hud);
const ptr = $('.ptr', scr);

/* Demo readings, except one: COMPRESS made a 31-minute call's recording 78% smaller (Compress.swift); 99 MB is 22% of 454 MB.
   Sizes follow what is drawn: one px on the stage is one point on its Mac (0.8 px on a phone, where the whole scene is
   drawn smaller). The selection's tag counts points; a shot's card counts pixels, two to a point (Selection.swift, Tools.swift). */
const SHOT = { size: '68 KB' };
const TEXT = { copied: $('[data-clip-text]', scr).textContent };
const REC = { len: 31 * 60 + 36, size: '454 MB', small: '99 MB', work: 118 };   // work: the seconds COMPRESS takes in the story
const scale = () => parseFloat(getComputedStyle(scr).getPropertyValue('--u')) || 1;
const points = r => { const u = scale(); return [Math.round(r.w / u), Math.round(r.h / u)]; };
const pixels = r => points(r).map(n => n * 2).join(' × ');

/* ---------- where things are on the screen (layout only, so a window still settling in does not throw it off).
   The card and the strip are drawn at the Mac's scale (capture.css): the card from its bottom-left corner, the strip from
   its top-left, so a part of either is placed by that scale too. ---------- */
function pos(el) {
  let x = 0, y = 0, e = el;
  for (; e && e !== scr && e !== card && e !== strip; e = e.offsetParent) { x += e.offsetLeft; y += e.offsetTop; }
  const w = el.offsetWidth, h = el.offsetHeight;
  if (e === card || e === strip) {
    const u = scale();
    if (e !== el) { x += e.clientLeft; y += e.clientTop; }   // from the outer edge of its border, where the scale is taken from
    const top = e === card ? e.offsetTop + e.offsetHeight - (e.offsetHeight - y) * u : e.offsetTop + y * u;
    return { x: e.offsetLeft + x * u, y: top, w: w * u, h: h * u };
  }
  return { x, y, w, h };
}
const grow = (r, a, b) => ({ x: r.x - a, y: r.y - b, w: r.w + 2 * a, h: r.h + 2 * b });
const REGION = { shot: () => grow(pos(chart), 12, 10), text: () => grow(pos(table), 10, 8), rec: () => pos(win.call) };

/* A picture of a region of a window, the way a screenshot is one: a copy of the window, clipped to the region and scaled
   so the region fills `into` (cover) or fits in it (contain), centred. `flat`: a picture too small to show faces, so the
   copy leaves the four drawn people out and the tiles show a plain tone (capture.css); the page then draws each person
   twice (the window, the card), not four times. */
function snap(into, of, r, how, flat) {
  const w = pos(of), tw = into.clientWidth, th = into.clientHeight;
  if (!tw || !th || !r.w || !r.h) return;
  const s = (how === 'contain' ? Math.min : Math.max)(tw / r.w, th / r.h), frame = document.createElement('i'), c = of.cloneNode(true);
  frame.className = 'snap';
  Object.assign(frame.style, { width: (r.w * s).toFixed(2) + 'px', height: (r.h * s).toFixed(2) + 'px', left: ((tw - r.w * s) / 2).toFixed(2) + 'px', top: ((th - r.h * s) / 2).toFixed(2) + 'px' });
  c.className = 'win win--snap';
  if (flat) $$('.tile__cam', c).forEach(e => e.remove());
  Object.assign(c.style, { width: w.w + 'px', height: w.h + 'px', transform: `scale(${s.toFixed(4)}) translate(${w.x - r.x}px, ${w.y - r.y}px)` });
  frame.append(c);
  into.replaceChildren(frame);
}
function cardSnap() {
  const rec = card.dataset.kind === 'rec';
  snap(cardPic, rec ? win.call : win.report, rec ? REGION.rec() : REGION.shot());
}
function snaps() {
  const shot = REGION.shot(), call = REGION.rec();
  snap($('[data-snap="file-shot"]', scr), win.report, shot);
  snap($('[data-snap="file-rec"]', scr), win.call, call, 'cover', true);
  snap($('[data-snap="file-small"]', scr), win.call, call, 'cover', true);
  snap($('[data-snap="clip"]', scr), win.report, shot, 'contain');
  cardSnap();
  if (card.dataset.kind === 'shot') cardTitle.textContent = pixels(shot);
}

/* ---------- names and the time: files are called after the moment they were made (Tools.swift); the menu bar's clock is
   the scene's own (data-own), because a half-hour recording passes here in seconds and the clock has to pass with it ---------- */
const two = n => String(n).padStart(2, '0');
const fit = () => Kit.fitBar(bar, nn);   // whole menus, and whole things at the bar's right end, give way to the notch
let ahead = 0, minute = -1;   // ahead: how far the scene's clock is ahead of the real one, in ms
const now = () => new Date(Date.now() + ahead);
function stamp(kind, d = now()) {   // day and time from the one moment, as the file name has them
  $$(`[data-day="${kind}"]`, scr).forEach(e => { e.textContent = `${d.getFullYear()}-${two(d.getMonth() + 1)}-${two(d.getDate())}`; });
  $$(`[data-hms="${kind}"]`, scr).forEach(e => { e.textContent = `${two(d.getHours())}.${two(d.getMinutes())}.${two(d.getSeconds())}`; });
}
const past = (kind, seconds) => stamp(kind, new Date(Date.now() + ahead - seconds * 1000));
function clock() {   // written as every menu bar on the page writes it (Kit.clock), in two parts: where the bar is short the date goes
  const d = now(), m = Math.floor(d.getTime() / 60000);
  if (m === minute) return;
  minute = m;
  const full = Kit.clock(d), at = full.search(/\d{1,2}[:.]\d{2}/);   // where the time begins
  barDate.textContent = at > 0 ? full.slice(0, at) : '';
  barTime.textContent = at > 0 ? full.slice(at) : full;
  fit();   // a longer time can push the battery under the notch: the bar is fitted again
}

/* ---------- the Mac around the tools ---------- */
// The app in front owns the menu bar. A call with your own picture in it means a camera is running: the light in the
// notch is green, and so is the dot beside Control Centre (the camera's green wins over the microphone's orange).
const APPS = { report: ['Preview', 'File', 'Edit', 'View', 'Go', 'Tools', 'Window', 'Help'], call: ['Calls', 'File', 'Edit', 'View', 'Window', 'Help'] };
function front(w) {
  scr.dataset.win = w;
  const [name, ...menus] = APPS[w], b = $('b', barLeft);
  if (b.textContent !== name) {
    b.textContent = name;
    $$('span', barLeft).forEach(e => e.remove());
    menus.forEach(m => { const e = document.createElement('span'); e.textContent = m; barLeft.append(e); });
  }
  fit();
  if (w === 'call') { nn.dataset.cam = 'on'; barDot.dataset.on = 'cam'; } else { delete nn.dataset.cam; delete barDot.dataset.on; }
}

/* ---------- the parts ---------- */
const setFiles = list => FILES.forEach(k => files[k].classList.toggle('on', list.includes(k)));
const land = k => files[k].classList.add('on');
const copied = kind => { clip.dataset.kind = kind; };
const filesNow = () => FILES.filter(k => files[k].classList.contains('on')).join();
const ovSet = s => { ov.dataset.state = s; };   // '' · 'pick' dim and hint · 'drag' the rectangle · 'chosen' it stays · 'rec' the red frame
const selAt = r => Object.assign(sel.style, { left: r.x + 'px', top: r.y + 'px', width: r.w + 'px', height: r.h + 'px' });
const nnSay = t => { if (t) say.textContent = t; nn.dataset.state = t ? 'say' : ''; };
const hudShow = k => { hudKey.textContent = k; hud.classList.add('on'); };
const hudHide = () => hud.classList.remove('on');
// The strip sits 7 points under the region, so 4 under its corner brackets; its record key's left edge is 146 points
// right of the region's, which puts the strip's own left edge under the region's left bracket (Session.swift, Strip.swift).
const stripAt = r => { const u = scale(); Object.assign(strip.style, { left: r.x + 146 * u + 'px', top: r.y + r.h + 7 * u + 'px' }); };
// The strip takes its shape while it is out of sight, so nothing folds or unfolds as it comes up.
function stripAs(state) { strip.classList.add('cut'); strip.dataset.state = state; void strip.offsetWidth; strip.classList.remove('cut'); }

function cardSet(kind, phase = 'ready') {
  card.dataset.kind = kind; card.dataset.phase = phase;
  cardTitle.textContent = kind === 'shot' ? pixels(REGION.shot()) : fmt(REC.len);
  cardSize.textContent = kind === 'shot' ? SHOT.size : phase === 'done' ? REC.small : REC.size;
  cells.forEach(c => c.classList.remove('on'));
  cardEta.textContent = ' ';
  cardSnap();
}
// The white line along the card's foot: it runs out, and the card leaves. It waits while the pointer is on the card.
let line = null;
function lineRun(ms) { if (line) line.cancel(); cardLine.style.transform = ''; line = cardLine.animate([{ transform: 'scaleX(1)' }, { transform: 'scaleX(0)' }], { duration: ms, fill: 'forwards' }); }
function lineSet(v) { if (line) line.cancel(); line = null; cardLine.style.transform = `scaleX(${v})`; }
const lineHold = () => { if (line) line.pause(); };

/* ---------- the pointer: always somewhere, as on a Mac. An arrow, or the crosshair while a rectangle is chosen.
   It never changes size: a press shows on the key under it (the app's keys act the moment they are pressed). ---------- */
let px = 0, py = 0;
function ptrAt(x, y, ms = 0) {
  px = x; py = y;
  ptr.style.transition = ms ? `transform ${ms}ms cubic-bezier(.45, 0, .2, 1)` : 'none';
  ptr.style.transform = `translate(${x.toFixed(1)}px, ${y.toFixed(1)}px)`;
}
const ptrShape = s => { ptr.dataset.shape = s; };
const ptrHalt = () => { const at = getComputedStyle(ptr).transform; ptr.style.transition = 'none'; if (at && at !== 'none') ptr.style.transform = at; };   // stopped on its way, it stays where it has got to
async function glide(wait, x, y, ms) { ptrAt(x, y, ms); await wait(ms); }
async function ptrTo(wait, el, ms, fx = .5, fy = .55) { const r = pos(el); await glide(wait, r.x + r.w * fx, r.y + r.h * fy, ms); }
const ptrOn = (el, fx, fy, ms) => { const r = pos(el); ptrAt(r.x + r.w * fx, r.y + r.h * fy, ms); };
const press = silent => { if (!silent) Sound.play('press'); };

/* ---------- moments ---------- */
async function drag(wait, r, tag, ms) {   // the rectangle is dragged out from its top-left corner, its size on a tag
  selAt({ x: r.x, y: r.y, w: 0, h: 0 }); selSize.textContent = '0 × 0'; ovSet('drag');
  await tween(wait, ms, p => {
    const e = wob(p), w = r.w * e, h = r.h * e;
    selAt({ x: r.x, y: r.y, w, h }); ptrAt(r.x + w, r.y + h);
    selSize.textContent = `${Math.round(tag[0] * e)} × ${Math.round(tag[1] * e)}`;
  });
}
async function record(wait, ms) {   // a long recording, sped up: the clock races to 31:36, and the menu bar's with it; red rises in the key with the sound
  let shown = 0, heard = 0, next = 0;
  const from = ahead;
  await tween(wait, ms, p => {
    const t = REC.len * wob(p);
    mainT.textContent = fmt(Math.round(t));
    ahead = from + t * 1000; clock();
    const at = performance.now();
    if (at > next) { heard = Math.random() < .72 ? rand(.45, 1) : rand(.04, .18); next = at + rand(90, 240); }
    shown = Math.max(heard * rand(.85, 1), shown - .04);   // up at once, down slowly (Session.swift)
    mainFill.style.height = (22 * shown).toFixed(1) + 'px';
  });
  mainFill.style.height = '0px';
}
async function squeeze(wait, ms) {   // COMPRESS: ten cells fill, the time left counts down, the size closes in on the copy's
  const from = ahead;
  card.dataset.phase = 'work';
  await tween(wait, ms, p => {
    cells.forEach((c, i) => c.classList.toggle('on', i < Math.floor(p * 10 + 1e-6)));
    if (p > .03) {   // the app says nothing for the first 3%, then guesses from what is written so far (Card.swift)
      cardEta.textContent = fmt(Math.max(1, Math.round(REC.work * (1 - p)))) + ' LEFT';
      cardSize.textContent = '≈' + Math.round(99 + 15 * Math.pow(1 - p, 1.6) * Math.cos(p * 7)) + ' MB';
    }
    ahead = from + REC.work * 1000 * p; clock();
  });
}

/* ---------- the steps. Each starts from where the step before it ends. ---------- */
const START = [
  { win: 'report', files: [], clip: '', card: '' },
  { win: 'report', files: ['shot'], clip: 'img', card: '' },
  { win: 'call', files: ['shot'], clip: 'txt', card: '' },
  { win: 'call', files: ['shot', 'rec'], clip: 'txt', card: 'rec' },
];
const LEN = [5900, 5800, 10450, 8300];   // each step's own length in ms, as timed below
function quiet() {   // the parts of a moment, not of a step (the pointer is left to the step)
  ovSet(''); strip.classList.remove('on'); hudHide(); nnSay('');
  mainKey.classList.remove('hot'); zKey.classList.remove('hot'); mainFill.style.height = '0px';
}
async function enter(i, wait) {
  const s = START[i], cardIn = card.classList.contains('in');
  const cardOK = s.card ? cardIn && card.dataset.kind === s.card && card.dataset.phase === 'ready' : !cardIn;
  const leave = (cardIn && !cardOK) || filesNow() !== s.files.join() || clip.dataset.kind !== s.clip;
  const swap = scr.dataset.win !== s.win, arrive = !!s.card && !cardOK;
  const clear = leave || swap ? 600 : 0;   // what does not belong to this step leaves, and the windows change, in one go
  quiet();
  if (!(i === 3 && cardOK)) { ahead = 0; if (i === 3) past('rec', REC.len + 6); }   // straight on from REC the clock runs on; otherwise it is the real time again
  clock();
  if (!ptr.dataset.shape) ptrOn(win[s.win], .62, .78);
  ptrShape('arrow');
  mark(i, clear + (arrive ? 600 : 0) + LEN[i]);
  if (clear) {
    if (cardIn && !cardOK) card.classList.remove('in');
    setFiles(s.files); clip.dataset.kind = s.clip;
    if (swap) front(s.win);
    await wait(clear);
  }
  if (arrive) { cardSet(s.card); card.classList.add('in'); lineRun(6000); await wait(600); }
}
function timeline(wait) { const t0 = performance.now(); return ms => wait(Math.max(0, t0 + ms - performance.now())); }
// The shortcut, then the rectangle: the screen dims, the pointer turns into a crosshair where it is, goes to one corner
// of what is wanted and is dragged to the other.
async function pick(wait, at, key, r, ms) {
  await at(100);  hudShow(key);
  await at(850);  hudHide(); ovSet('pick'); ptrShape('cross');
  await at(1000); await glide(wait, r.x, r.y, 400);
  await at(1500); await drag(wait, r, points(r), ms);
}

async function shot(wait) {
  await enter(0, wait);
  const at = timeline(wait), r = REGION.shot();
  await pick(wait, at, 'S', r, 850);
  await at(2500); ovSet(''); ptrShape('arrow'); stamp('shot');                   // let go: the overlay closes, the PNG is written
  cardSet('shot'); card.classList.add('in'); lineRun(2950);
  await at(3150); land('shot');
  await at(3800); copied('img');
  await at(5450); card.classList.remove('in');                                   // the three results have stood together for a moment
  await at(5900);
}
async function text(wait) {
  await enter(1, wait);
  const at = timeline(wait), r = REGION.text();
  await pick(wait, at, 'T', r, 800);
  await at(2450); ovSet(''); ptrShape('arrow'); nnSay('READING');                // let go: the overlay closes, the Mac reads the picture
  await at(3250); nnSay(`COPIED ${TEXT.copied.length} CHARS`);
  await at(3800); copied('txt');                                                 // and the clipboard holds the words, in their columns
  await at(5250); nnSay('');                                                     // the line lasts 2 seconds (Tools.swift)
  await at(5800);
}
async function rec(wait) {
  await enter(2, wait);
  const at = timeline(wait), r = REGION.rec();
  await pick(wait, at, 'R', r, 850);
  await at(2500); ovSet('chosen'); ptrShape('arrow');                            // the outline stays; the options come up under it
  stripAt(r); stripAs('pick'); mainT.textContent = '0:00'; strip.classList.add('on');
  await at(2950); await ptrTo(wait, mainKey, 550);
  mainKey.classList.add('hot'); Sound.play('tick');                              // under the pointer the key fills red
  await at(3850); press();
  ovSet('rec'); strip.dataset.state = 'rec'; stamp('rec');                       // recording: the dim lifts, the frame goes red
  await at(4350); mainKey.classList.remove('hot');
  await glide(wait, r.x + r.w * .64, r.y + r.h * .42, 550);                      // and the pointer goes back to the call
  await at(5000); await record(wait, 2400);
  await at(7550); await ptrTo(wait, mainKey, 500, .2);
  mainKey.classList.add('hot');                                                  // under the pointer its edge is white
  await at(8350); press(true); mainKey.classList.remove('hot');                  // STOP; the app is silent while it records
  ovSet(''); strip.classList.remove('on');
  cardSet('rec'); card.classList.add('in'); lineRun(6000);
  await at(9000); land('rec');
  await at(10450);                                                               // the card and the file, held
}
async function compress(wait) {
  await enter(3, wait);
  const at = timeline(wait);
  await at(150); await ptrTo(wait, zKey, 650, .5, .6);
  lineHold(); zKey.classList.add('hot'); Sound.play('tick');                     // the pointer is on the card: its countdown waits
  await at(1150); press(); zKey.classList.remove('hot');
  await squeeze(wait, 2600);
  await at(3850); await ptrTo(wait, cardPic, 250, .3, .72);                      // off the keys, onto the picture
  await at(4200); card.dataset.phase = 'done'; cardSize.textContent = REC.small; lineSet(1);   // the card now stands for the copy
  await at(4900); land('small');                                                 // written next to the original
  await at(5700); await glide(wait, px + 150, py - 64, 550);                     // the pointer leaves the card: its seconds start again
  lineRun(1600);
  await at(7850); card.classList.remove('in');
  await at(8300);
}
const SCENES = [shot, text, rec, compress];

/* ---------- a still frame of each step: for Reduce Motion, a paused demo, and while another segment plays.
   Each is a true moment: the files' names and the clock agree, and a card that stays has the pointer on it
   (the app's card waits while the pointer is on it). ---------- */
const STILL = [
  { win: 'report', files: ['shot'], clip: 'img', card: ['shot', 'ready', .6], shot: 3 },
  { win: 'report', files: ['shot'], clip: 'txt', say: true, shot: 9 },
  { win: 'call', files: ['shot'], clip: 'txt', rec: [12 * 60 + 48, .62], shot: 12 * 60 + 48 + 21 },
  { win: 'call', files: ['shot', 'rec', 'small'], clip: 'txt', card: ['rec', 'done', 1], shot: REC.len + REC.work + 40, made: REC.len + REC.work + 12 },
];
let held = 3;   // the step the still frame shows
function still(i, soft) {   // soft: the parts go to their places the way they move, instead of all at once
  held = i;
  inner.stop();
  if (!soft) scr.classList.add('cut');
  quiet(); ahead = 0; minute = -1;
  const s = STILL[i], ms = soft ? 350 : 0;
  front(s.win); setFiles(s.files); clip.dataset.kind = s.clip;
  past('shot', s.shot); if (s.made) past('rec', s.made);
  clock();
  if (s.card) { cardSet(s.card[0], s.card[1]); card.classList.add('in'); lineSet(s.card[2]); ptrOn(cardPic, .62, .5, ms); }
  else card.classList.remove('in');
  if (s.say) { nnSay(`COPIED ${TEXT.copied.length} CHARS`); const r = REGION.text(); ptrAt(r.x + r.w, r.y + r.h, ms); }
  if (s.rec) {
    const r = REGION.rec();
    past('rec', s.rec[0]);
    selAt(r); ovSet('rec'); stripAt(r); stripAs('rec'); strip.classList.add('on');
    mainT.textContent = fmt(s.rec[0]); mainFill.style.height = (22 * s.rec[1]).toFixed(1) + 'px';
    ptrAt(r.x + r.w * .64, r.y + r.h * .42, ms);
  }
  ptrShape('arrow');
  void scr.offsetWidth;
  scr.classList.remove('cut');
  mark(i, 0);
}

/* ---------- the four buttons (the shared .steps): which step is showing, and how far along it is ---------- */
// The line along a step's top edge is the shared one (.step::before, as long as --p says). While a step plays, the line
// itself is animated, which costs no layout; a browser that cannot animate a ::before shows it whole.
const lineCanRun = (() => { try { return new KeyframeEffect(tabs[0], null, { pseudoElement: '::before' }).pseudoElement === '::before'; } catch { return false; } })();
let prog = null;
function mark(i, ms) {
  tabs.forEach((t, j) => {
    const on = j === i;
    t.classList.toggle('is-on', on); t.style.setProperty('--p', on ? 1 : 0);
    if (on) t.setAttribute('aria-current', 'step'); else t.removeAttribute('aria-current');
  });
  if (prog) prog.cancel();
  prog = ms && lineCanRun ? tabs[i].animate([{ transform: 'scaleX(0)' }, { transform: 'scaleX(1)' }], { duration: ms, easing: 'linear', fill: 'forwards', pseudoElement: '::before' }) : null;
}

/* ---------- playing ---------- */
let cur = 0, paused = false, played = false;
const inner = player(async wait => {
  const i = cur;
  played = true;
  await SCENES[i](wait);
  cur = (i + 1) % SCENES.length;
  if (cur === 0 && loop.looped) loop.looped();   // a full round: Kit.turns may pass the turn on
});
const loop = {   // what Kit.whenVisible starts and stops (on this segment's turn); a paused demo stays paused
  start() { if (!paused && !reduced()) inner.start(); },
  stop() { inner.stop(); if (prog) prog.pause(); if (line) line.pause(); ptrHalt(); },
  get active() { return inner.active; },
};
// A person picked a step, or pressed play: this segment takes the turn (the others stop) and plays from that step.
function play() {
  inner.stop();
  const turns = Kit.turns;
  if (turns && turns.hold) { turns.hold(loop); turns.release(loop); } else loop.start();
  if (!inner.active) still(cur);   // it could not take the turn (too little of it on screen): show the step, still
}

// (app.js sounds the visitor's own presses on these buttons, as on every control of the page)
tabs.forEach((t, i) => t.addEventListener('click', () => {
  cur = i;
  if (paused || reduced()) { still(i); return; }
  play();
}));
playKey.hidden = reduced();
playKey.addEventListener('click', () => {
  paused = !paused;
  cap.classList.toggle('is-paused', paused);
  playKey.setAttribute('aria-label', paused ? 'Play the demo' : 'Pause the demo');
  if (paused) loop.stop(); else play();   // playing again starts the step over
});
// Motion switched off or on while the page is open (the device's setting, or the page's switch): nothing plays
// without it, so there is nothing to pause.
if (Kit.onMotion) Kit.onMotion(still => { playKey.hidden = still; });

// A new width moves everything on the stage: the pictures are made again, and the step is drawn again where things now
// are (played from its start, or still). A new height alone (a phone's address bar going away) changes nothing here.
let resized = 0, width = scr.clientWidth;
addEventListener('resize', () => {
  clearTimeout(resized);
  resized = setTimeout(() => {
    if (scr.clientWidth === width) return;
    width = scr.clientWidth;
    snaps(); fit();
    if (inner.active) play(); else still(held);
  }, 160);
});
setInterval(() => { if (!inner.active) clock(); }, 20000);   // the still frame's clock keeps the time, like the page's other Macs

snaps();
// Until it plays: the whole story at once, every file it leaves (Kit draws the still frame as it registers the scene).
// Without the turn afterwards the stage shows the result of the step it was on,
// reached softly, so nothing jumps and the same button stays lit.
whenVisible(stage, loop, () => still(played ? cur : 3, played && !reduced()));
})();

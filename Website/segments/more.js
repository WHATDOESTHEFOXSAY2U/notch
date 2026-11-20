/* Notch website, segment "more": build a segment (#next, the open slots) and open source (#source, how one is built).
   Uses window.Kit from ../app.js. Each scene plays only on its turn (Kit.whenVisible); otherwise, and under Reduce Motion,
   it shows its still frame, which is complete on its own. */
(() => {
'use strict';
const { $, $$, clamp, player, whenVisible, handsOn, moved } = window.Kit;

/* ---------- #next: the panel with its newest key and one open cell; the drawn pointer rests on the one the list names ---------- */
(function slots() {
  const root = $('#nxt'); if (!root) return;
  const sp = $('.sp', root), view = $('.nxt__view', root), fit = $('.nxt__fit', root), list = $('.nxt__list', root);
  const ptr = $('.nxt__ptr', root), items = $$('.nxt__it', root);
  const cellOf = slot => $(`.sp__bar [data-slot="${slot}"]`, root);
  const order = items.map(b => b.dataset.slot);              // scribe (the newest key), yours (the open cell)
  if (!ptr || order.length < 2 || !order.every(cellOf)) return;
  const GLIDE = 700, HOLD = { scribe: 2800, yours: 3600 };   // ms: the pointer's way from key to key; how long each rests

  // The panel is drawn at its own size (500 wide, as in the app): at 1 wherever there is room, scaled as one on a phone.
  // It sits on a whole pixel of the page, so its type and its bars are never drawn between pixels.
  function size() {
    const w = view.clientWidth; if (!w) return;
    const z = clamp((w - 20) / 500, .5, 1), left = view.getBoundingClientRect().left;
    root.style.setProperty('--z', z.toFixed(3));
    root.style.setProperty('--x', (Math.round(left + (w - 500 * z) / 2) - left).toFixed(3) + 'px');
    fit.classList.toggle('is-1x', z === 1);
    root.style.setProperty('--ph', sp.offsetHeight + 'px');
    aim(target);
  }

  // The pointer's tip on a cell, in the panel's own points: 10 right of its middle, 20 down the bar, as a hand rests on a key.
  // (TRANSCRIBE is the bar's middle cell, so its middle stays put when it widens under the pointer.)
  let target = sp.dataset.slot;                              // the key the pointer is on, or on its way to
  function aim(slot) {
    const c = cellOf(target = slot);
    ptr.style.setProperty('--px', Math.round(c.offsetLeft + c.offsetWidth / 2 + 10) + 'px');
    ptr.style.setProperty('--py', Math.round(c.parentNode.offsetTop + 20) + 'px');
  }
  // What a key under the pointer shows: TRANSCRIBE white with its name; the open cell, and the place for its view, lit.
  function light(slot) {
    sp.dataset.slot = slot;
    cellOf('scribe').classList.toggle('is-hot', slot === 'scribe');
    cellOf('yours').classList.toggle('is-on', slot === 'yours');
    items.forEach(b => (b.dataset.slot === slot ? b.setAttribute('aria-current', 'true') : b.removeAttribute('aria-current')));
  }
  // At once, the frame complete: the key lit and the pointer on it. 'jump' puts the pointer there; 'quick' moves it there in
  // a moment (a person pointing at the list); otherwise it glides.
  function show(slot, how) {
    ptr.classList.toggle('is-quick', how === 'quick');
    if (how === 'jump') ptr.style.transition = 'none';
    light(slot); aim(slot);
    if (how === 'jump') { void ptr.offsetWidth; ptr.style.transition = ''; }
  }
  let shown = '';                                            // the slot a person last put the pointer on ('' while the loop drives it)
  function still() { root.classList.remove('is-live'); shown = ''; show('yours', 'jump'); }

  size();
  addEventListener('resize', size);
  if ('ResizeObserver' in window) new ResizeObserver(size).observe(view);
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(size);

  // One round, from whichever key the pointer is on: it rests, leaves (the key it leaves goes back to its picture), glides to
  // the other, and that one lights as the pointer arrives. One thing moves at a time; only a transform and classes change.
  const auto = player(async wait => {
    root.classList.add('is-live');
    for (let i = 0; i < order.length; i++) {
      const now = sp.dataset.slot, next = order[(order.indexOf(now) + 1) % order.length];
      await wait(HOLD[now]);
      shown = '';
      ptr.classList.remove('is-quick');
      cellOf('scribe').classList.remove('is-hot');
      cellOf('yours').classList.remove('is-on');
      aim(next);
      await wait(GLIDE);
      light(next);
    }
  });
  whenVisible(root, auto, still);

  // A person takes over at the list (Kit.handsOn: a real move of the pointer on it, a press, a key, keyboard focus): the
  // loop stops with its frame complete, and pointing at an item, pressing it or reaching it with the keyboard puts the
  // drawn pointer on its key. A pointer at rest, or a page scrolled under it, changes nothing.
  const take = slot => { if (slot !== shown) { shown = slot; show(slot, 'quick'); } };
  items.forEach(b => {
    b.addEventListener('click', () => take(b.dataset.slot));
    b.addEventListener('pointermove', e => { if (e.pointerType !== 'touch' && moved(e)) take(b.dataset.slot); });
    b.addEventListener('focus', () => { if (b.matches(':focus-visible')) take(b.dataset.slot); });
  });
  handsOn(list, auto, () => { root.classList.add('is-live'); if (!shown) take(sp.dataset.slot); });
})();

/* ---------- #source: the three steps, shown one after another: the issue, the folder, the commands ---------- */
(function how() {
  const root = $('#how'); if (!root) return;
  const list = $('.how__list', root), steps = $$('.step', root);
  const title = $('.is [data-type]', root), dir = $('.tr [data-type]', root);
  const fresh = $$('[data-new]', root), adds = $$('[data-add]', root);
  const lines = $$('[data-line]', root), prompt = $('.tm__wait', root), cmd = $('[data-cmd]', prompt);
  const later = [title, ...fresh, ...adds, ...lines];   // everything the story adds to what is already there
  const KEY = 80, CMD = 48;                             // ms a letter: a name typed in, a command typed at the prompt

  // Lights step n for ms (the line on its top edge runs for as long); 0 lights none; 'all' is the story told.
  function stepTo(n, ms = 0) {
    list.dataset.at = n;
    steps.forEach((s, i) => {
      const on = i + 1 === n;
      s.classList.toggle('is-on', on);
      s.style.setProperty('--d', ms + 'ms');
      s.style.setProperty('--p', on ? 1 : 0);
    });
  }
  // The caret after a name being typed: 'wait' blinks, 'type' is steady (as a caret is while letters arrive), '' is none.
  function caret(el, how) {
    el.parentNode.classList.toggle('is-typing', !!how);
    el.parentNode.classList.toggle('is-idle', how === 'wait');
  }
  async function type(el, text, wait, ms) {
    for (let i = 1; i <= text.length; i++) { el.textContent = text.slice(0, i); await wait(ms); }
  }
  // The prompt waits under the last command that was run: on line n while the commands after it are still to come.
  function promptAt(n) {
    cmd.textContent = '';
    prompt.style.transform = n < lines.length ? `translateY(${lines[n].offsetTop - prompt.offsetTop}px)` : '';
  }
  const command = li => $('code', li).textContent;

  function still() {
    stepTo('all');
    later.forEach(el => el.classList.remove('is-off'));
    [title, dir].forEach(el => { el.textContent = el.dataset.type; caret(el, ''); });
    promptAt(lines.length);
  }

  const auto = player(async wait => {
    // From the finished picture: what the three steps added fades away together, and the story is told again.
    stepTo(0);
    later.forEach(el => el.classList.add('is-off'));
    await wait(450);
    title.textContent = ''; dir.textContent = '';
    promptAt(0);

    // 1. The issue: its title is typed. The answer is the maintainer's, so neither lamp ever lights here.
    const name = title.dataset.type, folder = dir.dataset.type;
    stepTo(1, 550 + name.length * KEY + 1300);
    title.classList.remove('is-off'); caret(title, 'wait');
    await wait(550);
    caret(title, 'type');
    await type(title, name, wait, KEY);
    caret(title, 'wait');
    await wait(1300);
    caret(title, '');

    // 2. The folder is typed in beside the others, then its first file; then the two lines a tool adds to files already there.
    stepTo(2, 550 + folder.length * KEY + 400 + 700 + 700 + 1200);
    fresh[0].classList.remove('is-off'); caret(dir, 'wait');
    await wait(550);
    caret(dir, 'type');
    await type(dir, folder, wait, KEY);
    caret(dir, 'wait');
    await wait(400);
    fresh[1].classList.remove('is-off');
    await wait(700);
    caret(dir, '');
    adds[0].classList.remove('is-off');
    await wait(700);
    adds[1].classList.remove('is-off');
    await wait(1200);

    // 3. The commands, typed at the prompt and run one at a time; then the prompt waits for the next.
    stepTo(3, lines.reduce((ms, li) => ms + 250 + command(li).length * CMD + 200 + 550, 0) + 700);
    for (let i = 0; i < lines.length; i++) {
      await wait(250);
      await type(cmd, command(lines[i]), wait, CMD);
      await wait(200);
      lines[i].classList.remove('is-off');   // run: the line stands, what it does shows under it,
      promptAt(i + 1);                       // and the prompt is on the next line
      await wait(550);
    }
    await wait(700);

    stepTo('all');
    await wait(3000);
  });
  whenVisible(root, auto, still);
})();
})();

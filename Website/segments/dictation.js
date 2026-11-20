/* Notch website, segment 03 Dictation: talk, it types.
   Uses window.Kit from ../app.js. Two scenes: a message being dictated, and a call being written down. Each plays only on
   its turn (Kit.whenVisible) and otherwise shows its still frame, which is the result of its story. */
(() => {
'use strict';
const Kit = window.Kit;
if (!Kit) return;
const { $, $$, rand, fmt, tween, player, whenVisible, SPEECH, makeVoice, Sound } = Kit;

// The app's soft notes for the start and the stop, and for text that is only copied (Sounds.swift). They play only if the
// page's Sound is on.
const cue = name => Sound.play(name);

/* Caps Lock + D, the notch widens and writes as you speak, Caps Lock + D again: the notch folds into its band and the
   text lands in the text box you are in (Dictation.swift, Wings.swift, Paste.swift). */
function dictation(root) {
  const voice = makeVoice(root), vn = voice.vn;
  const paste = $('.dc-paste', root), count = $('.vwords', root), bandL = $('.vc-l', root), bandR = $('.vc-r', root);
  const bar = $('.mbar', root), name = $('.mbar__l b', root), dot = $('.mbar__dot', root), clock = $('.mbar__clock', root);
  const hole = $('.grp', root);   // the strip's place, at its widest
  const [startKeys, stopKeys] = $$('.keys', root);
  const steps = $$('.step', root);
  const L = $$('.wing--l i', root), R = $$('.wing--r i', root);
  const ALL = SPEECH.split(' ').length;

  // The level beside the notch, lit from the notch outward, as makeVoice draws it.
  const level = n => { L.forEach((el, i) => el.classList.toggle('on', 11 - i < n)); R.forEach((el, i) => el.classList.toggle('on', i < n)); };
  // The steps under the scene: the one playing is lit, and the line on its top edge shows how far along it is.
  const step = (at, p = 0) => steps.forEach((el, i) => { el.classList.toggle('is-on', i === at); el.style.setProperty('--p', i === at ? p : 0); });
  // The microphone: macOS shows its orange dot, and the Mac's own sound is off (the speaker struck through) for as long.
  const mic = on => { root.classList.toggle('is-mic', on); if (on) dot.dataset.on = 'mic'; else delete dot.dataset.on; };
  const keys = (el, on) => el.classList.toggle('is-hot', on);

  /* The menu bar. Kit.fitBar leaves out, whole, whatever the strip would cover; it is measured against the strip at its
     widest, so nothing comes and goes as it opens. As on a Mac, the clock's date is the first thing to go when room is
     short. Where not even the app's name clears the strip (a phone), the bar is bare: a close crop round the notch. */
  function fit() {
    if (!Kit.fitBar) return;
    delete bar.dataset.tight;
    bar.classList.remove('is-bare');
    Kit.fitBar(bar, hole);
    if ($('.mbar__r > .is-cut', bar)) { bar.dataset.tight = ''; Kit.fitBar(bar, hole); }
    bar.classList.toggle('is-bare', name.getBoundingClientRect().right > hole.getBoundingClientRect().left - 8);
  }
  // Kit writes the page's one time into every clock. Here it is split in two, so that the date can go by itself.
  function split() {
    if (clock.firstElementChild) return;
    const parts = /^(\S+\s+\S+\s+\S+\s+)(.+)$/.exec(clock.textContent.trim());   // "Tue 17 Nov " and "9:41"
    if (!parts) return;
    const date = document.createElement('span'), time = document.createElement('span');
    date.className = 'dc-date';
    date.textContent = parts[1];
    time.textContent = parts[2];
    clock.replaceChildren(date, time);
    fit();
  }
  new MutationObserver(split).observe(clock, { childList: true });
  split();   // another section's script may have asked Kit for the time already
  fit();
  addEventListener('resize', fit);
  addEventListener('load', fit);

  function clear() {
    voice.idle(); level(0);
    vn.classList.remove('is-wait');
    step(-1); mic(false); keys(startKeys, false); keys(stopKeys, false);
    paste.textContent = ''; paste.classList.remove('is-new');
    root.classList.remove('is-fading');
  }

  // Caps Lock + D again: the notch folds into its band at once, the microphone goes off and the Mac's sound comes back.
  // PASTED waits for the text.
  function stop() { step(2); keys(stopKeys, true); vn.classList.add('is-wait'); mic(false); cue('heard'); }

  // One round starts and ends on the still frame, so the turn can come and go without a jump.
  async function scene(wait) {
    root.classList.add('is-live');
    await wait(500);   // with the second and a half that ends a round, the band has the two seconds the app gives it
    // The last dictation leaves: its band folds back into the notch, and its words fade from the message.
    vn.dataset.state = 'idle'; step(-1); root.classList.add('is-fading');
    await wait(560);
    clear();
    await wait(700);
    // Caps Lock + D: the notch widens at once and the microphone comes on.
    step(0, 1); keys(startKeys, true); cue('listen');
    vn.dataset.state = 'voice'; mic(true);
    await wait(340);
    keys(startKeys, false);
    await wait(260);
    step(1);
    // The first words take about a second: the level moves while the cursor waits.
    let lv = 0;
    for (let t = 0; t < 960; t += 33) { lv += (rand(.3, .9) - lv) * .45; level(Math.round(lv * 12)); await wait(33); }
    // The line over Talk follows the word count.
    const said = new MutationObserver(() => steps[1].style.setProperty('--p', (parseInt(count.textContent, 10) || 0) / ALL));
    said.observe(count, { childList: true, characterData: true, subtree: true });
    try { await voice.run(wait, { onCopied: stop }); } finally { said.disconnect(); }
    // The last words are read: the text is ready 0.19 s after the stop (median, M1 Pro), and goes straight in.
    await tween(wait, 190, p => steps[2].style.setProperty('--p', p));
    vn.classList.remove('is-wait');
    paste.textContent = SPEECH; paste.classList.add('is-new');
    step(3, 1);
    await wait(160);
    keys(stopKeys, false);
    await wait(1340);   // the landed words' highlight has faded by now
  }

  // The still frame is the result: the words are in the message, and the band under the notch says so.
  function still() {
    clear(); root.classList.remove('is-live');
    bandL.textContent = 'PASTED'; bandR.textContent = `${ALL} WORDS`;
    vn.dataset.state = 'copied';
    paste.textContent = SPEECH;
    step(3, 1);
  }

  whenVisible(root, player(scene), still);
}

/* A strip that writes down a text of its own (Kit.makeVoice writes only the page's one speech), by the app's rules
   (Wings.swift): twelve blocks a side lit from the notch outward, lines wrapped by counting characters, the last three
   shown with the older ones fainter, a full line set from edge to edge, the cursor after the newest word. Its clock
   counts by the words, as Kit's does: the demo types faster than anyone speaks. */
const PACE = .4;   // seconds of talking each word stands for (the same as in app.js)
function strip(root, text) {
  const trans = $('.vtrans', root), time = $('.vtime', root), count = $('.vwords', root);
  const words = text.split(' ');
  // The level's twelve blocks a side are in the markup, lit as in the still frame, so the strip is whole even without script.
  const [L, R] = ['.wing--l', '.wing--r'].map(sel => {
    const wing = $(sel, root), have = $$('i', wing);
    return have.length === 12 ? have : Array.from({ length: 12 }, () => wing.appendChild(document.createElement('i')));
  });
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
    if (used > 0 && used + 1 + w.length > perLine) { starts.push(i); used = w.length; } else used += (used > 0 ? 1 : 0) + w.length;
  });

  const level = n => { L.forEach((el, i) => el.classList.toggle('on', 11 - i < n)); R.forEach((el, i) => el.classList.toggle('on', i < n)); };
  function show(n) {
    let current = 0;
    starts.forEach((s, i) => { if (s < n) current = i; });
    const frag = document.createDocumentFragment();
    for (let line = Math.max(0, current - 2); line <= current; line++) {
      const end = line + 1 < starts.length ? starts[line + 1] : words.length, full = line + 1 < starts.length, showing = n - starts[line];
      const row = document.createElement('div');
      row.className = 'vline' + (full ? ' full' : '') + (line === current && showing <= 0 ? ' start' : '');
      row.style.opacity = line === current ? 1 : line === current - 1 ? .75 : .4;
      for (let i = starts[line]; i < end; i++) {
        const w = document.createElement('span');
        w.className = 'vword' + (i - starts[line] < showing ? ' on' : '') + (line === current && i === n - 1 ? ' cur' : '');
        w.textContent = words[i];
        if (!full && i > starts[line]) w.style.marginLeft = adv + 'px';
        row.append(w);
      }
      frag.append(row);
    }
    trans.replaceChildren(frag);
    count.textContent = `${n} WORD${n === 1 ? '' : 'S'}`;
    time.textContent = fmt(Math.floor(n * PACE));
  }
  return { words, level, show };
}

/* HEAR THE MAC'S SOUND TOO: what the Mac plays is written down along with what you say (MacSound.swift). Someone speaks
   on a call, and the strip writes it down. Stopped with the call in front and no text box, the text is on the clipboard,
   and the band says COPIED. */
function call(root) {
  const vn = $('.vn', root);
  const s = strip(root, 'Got your summary. The benchmarks look great. Let’s ship the recording flow on Thursday.');
  const ALL = s.words.length;
  let lv = 0, talking = false;
  $('.vc-r', root).textContent = `${ALL} WORDS`;

  // She speaks: her picture is ringed, and the sound the Mac plays moves.
  const hear = on => { talking = on; root.classList.toggle('is-heard', on); };
  // Listening, a thirtieth of a second at a time: the level beside the notch follows the sound.
  async function listen(wait, ms, each) {
    for (let t = 0; t < ms; t += 33) {
      lv += ((talking ? rand(.35, .95) : rand(.03, .16)) - lv) * .45;
      s.level(Math.round(lv * 12));
      if (each) each(.033);
      await wait(33);
    }
  }

  // One round starts and ends on the still frame, so the turn can come and go without a jump.
  async function scene(wait) {
    root.classList.add('is-live');
    // Every word is down, and she is still talking.
    hear(true);
    await listen(wait, 1100);
    hear(false);
    await listen(wait, 450);
    // Stopped: the strip folds into its band at once, and COPIED lights when the text is on the clipboard.
    vn.classList.add('is-wait'); vn.dataset.state = 'copied'; s.level(0); cue('heard');
    await wait(190);
    vn.classList.remove('is-wait'); cue('copied');
    await wait(2000);
    vn.dataset.state = 'idle';
    await wait(1000);
    // Started again: the strip opens and waits for the first words.
    lv = 0; s.show(0); s.level(0);
    vn.dataset.state = 'voice'; cue('listen');
    await listen(wait, 500);
    hear(true);
    await listen(wait, 700);
    // The recogniser hands over a few words at a time; they type on at eight a second (Dictation.swift).
    let shown = 0, target = 0, acc = 0, at = 0, next = 0;
    while (shown < ALL) await listen(wait, 33, dt => {
      at += dt;
      if (at >= next && target < ALL) { target = Math.min(ALL, target + Math.round(rand(3, 6))); next = at + rand(.6, .95); }
      if (shown >= target) return;
      acc += dt * 8;
      const add = Math.floor(acc);
      if (add > 0) { acc -= add; shown = Math.min(target, shown + add); s.show(shown); }
    });
    await listen(wait, 400);
  }

  // The still frame is the result: the call, written down.
  function still() {
    root.classList.remove('is-live');
    hear(true);
    vn.classList.remove('is-wait'); vn.dataset.state = 'voice';
    lv = .5; s.show(ALL); s.level(6);
  }

  whenVisible(root, player(scene), still);
}

$$('#dictation .dc-live').forEach(dictation);
$$('#dictation .dc-hear').forEach(call);

// The three options arrive one after another, left to right.
$$('#dictation .dc-opt').forEach((el, i) => { el.dataset.d = i * 90; });
})();

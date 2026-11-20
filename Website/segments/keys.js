/* Notch website, segment 05 Keys: Caps Lock as a hyper key (Hyper.swift, Hotkeys.swift).
   The markup is the still frame: the whole equation, the keys let go, D marked, the notch a dictation in mid-sentence
   (what Reduce Motion shows, what shows while another scene plays, and what shows without this script).
   One calm loop runs on from there: the dictation ends the way it began, with Caps Lock + D, and its words are on the
   clipboard; with Caps Lock held, the keyboard shows where else it can go (S, for one of Notch's own shortcuts, then
   every key that is left); Caps Lock + D starts the next dictation, and the loop is back at the still frame.
   It plays only on its turn (Kit.whenVisible). The strip is the shared .vn, driven here: this one has its own sentence,
   and with no text box on the stage it ends on COPIED, as the app does. */
(() => {
'use strict';
if (!window.Kit) return;
const { $, $$, clamp, rand, fmt, player, whenVisible } = window.Kit;
const PACE = .4;   // seconds of talking each word stands for: the strip's clock counts by the words, as Kit.makeVoice's does

function hyper(root) {
  const stage = $('.hk__stage', root), vn = $('.vn', root), kb = $('.hk__kb', root);
  const caps = $('.hk__key--caps', root), mods = $$('.hk__key--mod', root), dee = $('.hk__d', root), ess = $('.hk__s', root);
  const uses = $$('.step', root);
  const L = $$('.wing--l i', root), R = $$('.wing--r i', root);
  const time = $('.vtime', root), count = $('.vwords', root), line = $('.vline', root), words = $$('.vword', root);
  const STILL = { words: 6, lit: 7, p: .37 };   // the still frame: "Two keys, and the Mac is", with the level up
  let lv = 0, shown = 0;                        // the dictation on show: its level, its words so far

  // The small keyboard lights up from left to right: each key waits by how far along its row it sits.
  $$('.hk__row', kb).forEach((row, r) => $$('i', row).forEach((k, i) => k.style.setProperty('--i', i + r * .5)));

  // The strip is drawn at its own size; only a bay narrower than it shows the whole strip smaller.
  const fit = () => vn.style.setProperty('--vz', clamp((stage.clientWidth - 20) / 380, .6, 1).toFixed(3));
  fit();
  addEventListener('resize', fit);

  const hold = (els, on) => els.forEach(el => el.classList.toggle('on', on));
  const letGo = () => hold([caps, ...mods, dee], false);
  // The level beside the notch, lit from the notch outward (Wings.swift).
  const level = n => { L.forEach((el, i) => el.classList.toggle('on', 11 - i < n)); R.forEach((el, i) => el.classList.toggle('on', i < n)); };
  // The first n words are written; the block that marks the next word's place follows the last one.
  function say(n) {
    shown = n;
    words.forEach((w, i) => { w.classList.toggle('on', i < n); w.classList.toggle('cur', i === n - 1); });
    line.classList.toggle('start', n === 0);
    count.textContent = `${n} WORD${n === 1 ? '' : 'S'}`;
    time.textContent = fmt(Math.floor(n * PACE));
  }
  // Lights one use along the foot (none for -1); the line on its top edge runs from `from` to `to` over ms.
  function use(i, from = 0, to = from, ms = 0) {
    uses.forEach((el, k) => { el.classList.toggle('is-on', k === i); el.style.setProperty('--pt', '0s'); el.style.setProperty('--p', k === i ? from : 0); });
    if (i < 0 || !ms) return;
    void uses[i].offsetWidth;
    uses[i].style.setProperty('--pt', ms + 'ms'); uses[i].style.setProperty('--p', to);
  }
  // The dictation goes on for ms: the level moves with the voice, or lies low in a silence.
  async function talk(wait, ms, loud = true) {
    for (let t = 0; t < ms; t += 33) {
      lv += ((loud ? rand(.35, .95) : rand(.04, .2)) - lv) * .45;
      level(Math.round(lv * 12));
      await wait(33);
    }
  }
  // Words type on at the app's eight a second.
  async function write(wait, upTo) { while (shown < upTo) { say(shown + 1); await talk(wait, 125); } }
  // Caps Lock goes down, and with it the four keys it counts as.
  async function capsDown(wait) { caps.classList.add('on'); for (const m of mods) { await wait(45); m.classList.add('on'); } }
  // Caps Lock + D. A shortcut is a tap: the caller lets the keys go a moment later.
  async function tapD(wait) { await capsDown(wait); await wait(260); dee.classList.remove('is-mark'); dee.classList.add('on'); await wait(140); }

  function still() {
    letGo(); kb.classList.remove('live'); ess.classList.remove('is-mark'); dee.classList.add('is-mark');
    vn.classList.remove('is-wait'); vn.dataset.state = 'voice';
    say(STILL.words); level(STILL.lit); lv = STILL.lit / 12;
    use(0, STILL.p);
  }

  async function scene(wait) {
    // From the still frame: the dictation that Caps Lock + D began runs on to its last words.
    still();
    use(0, STILL.p, 1, 4640);                                  // the line on Dictation's edge runs on, at the pace it came
    await talk(wait, 600);
    await write(wait, words.length);
    await talk(wait, 300);
    await talk(wait, 700, false);
    // The same two keys stop it: the notch folds into its band at once, and the words are on the clipboard.
    await tapD(wait);
    level(0); vn.classList.add('is-wait'); vn.dataset.state = 'copied';
    await wait(190);
    vn.classList.remove('is-wait');
    await wait(330);
    letGo();
    await wait(1480);                                          // the band stays two seconds
    vn.dataset.state = 'idle'; use(-1);
    await wait(1100);
    // Caps Lock held: where else it can go. S, for one of Notch's own shortcuts; then every key that is left.
    await capsDown(wait);
    await wait(520);
    use(1, 0, 1, 2400); ess.classList.add('is-mark');
    await wait(2400);
    use(2, 0, 1, 2600); ess.classList.remove('is-mark'); kb.classList.add('live');
    await wait(2600);
    letGo(); kb.classList.remove('live'); use(-1);
    await wait(1200);
    // Caps Lock + D: the notch starts a dictation. The keys let go while it opens; the first words take about a second.
    await tapD(wait);
    lv = 0; say(0); level(0);
    vn.dataset.state = 'voice'; use(0, 0, STILL.p, 2700);
    await talk(wait, 260, false);                              // the room, before the first word is spoken
    await talk(wait, 160);
    letGo(); dee.classList.add('is-mark');
    await talk(wait, 580);
    await write(wait, 3);
    await talk(wait, 480);
    await write(wait, STILL.words);
    await talk(wait, 240);                                     // and this is the still frame again
  }

  whenVisible(root, player(scene), still);
}

$$('#keys [data-scene="hyper"]').forEach(hyper);
})();

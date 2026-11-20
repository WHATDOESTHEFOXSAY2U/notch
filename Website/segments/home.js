/* Notch website: the rack, the download card and the footer. All three are still pictures and words: this file gives the
   rack its order of arrival and the card its one behaviour. It needs nothing from window.Kit. */
(() => {
'use strict';

/* The rack arrives along each row, 70 ms a module (app.js reveals anything marked .rv and keeps a delay set here, in
   data-d). The rack is four, three or two modules wide, so the delay goes by the column a module is in. */
const rack = document.querySelector('.rack');
if (rack) {
  const columns = getComputedStyle(rack).gridTemplateColumns.split(' ').filter(Boolean).length || 4;
  Array.from(rack.children).forEach((mod, i) => { mod.dataset.d = (i % columns) * 70; });
}

/* Nobody can install a Mac app on a phone. On anything that is not a Mac the card offers to send this page's link to the
   Mac instead: the system's share sheet, or, where there is none, the link copied. Download for Mac stays, as the second
   choice. Without this script the button stays hidden and the card is as it is on a Mac. */
const send = document.querySelector('.get__send');
if (!send) return;
const cta = send.parentElement, said = document.querySelector('.get__sent'), download = cta.querySelector('[data-download]');
const platform = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || '';
// An iPad says it is a Mac, so a Mac is also something without a touch screen.
const mac = /mac/i.test(platform) && !/iphone|ipad|ipod/i.test(navigator.userAgent || '') && !(navigator.maxTouchPoints > 1);
if (mac) return;

send.hidden = false;
cta.classList.add('has-send');
if (download) download.classList.add('btn--ghost');

const link = location.href.split('#')[0] + '#download';   // opened on the Mac, the page starts at this card
let clear = 0;
function say(text, stay) {
  if (!said) return;
  said.textContent = text;
  clearTimeout(clear);
  if (!stay) clear = setTimeout(() => { said.textContent = ''; }, 8000);
}
async function copy() {
  try { await navigator.clipboard.writeText(link); return true; } catch { /* no clipboard here: try the older way */ }
  // The older way, without moving the focus: the copy the browser is asked for takes the link instead of a selection.
  const put = e => { e.clipboardData.setData('text/plain', link); e.preventDefault(); };
  document.addEventListener('copy', put);
  let done = false;
  try { done = document.execCommand('copy'); } catch { /* nor that */ }
  document.removeEventListener('copy', put);
  return done;
}
send.addEventListener('click', async () => {
  if (navigator.share) {
    try { await navigator.share({ title: document.title, url: link }); return; }
    catch (e) { if (e && e.name === 'AbortError') return; }   // the sheet was closed: nothing to say
  }
  if (await copy()) say('Link copied. Open it on your Mac.');
  else say('Open this link on your Mac: ' + link, true);       // if even copying fails, the link itself, to select by hand
});
})();

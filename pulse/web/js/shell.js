import { html, raw, esc } from './ui.js';
import { S, initials } from './store.js';

const NAV = [['dashboard', 'Dashboard'], ['planner', 'Planner'], ['insights', 'Insights'],
  ['nutrition', 'Nutrition'], ['workouts', 'Workouts'], ['routines', 'Routines'], ['profile', 'Profile']];

export const logo = (size = 28) => raw(`<svg width="${size}" height="${size}" viewBox="0 0 28 28" aria-hidden="true"><g fill="none" stroke-width="3.5" stroke-linecap="round" transform="rotate(-90 14 14)"><circle cx="14" cy="14" r="11" stroke="#FF8A4C" stroke-dasharray="44 70"/><circle cx="14" cy="14" r="5.5" stroke="#C8F25A" stroke-dasharray="22 35"/></g></svg>`);

export function shell(active, { eyebrow = '', title, right = '' }, body) {
  return html`<div class="shell">
    <aside class="side">
      <div class="brand">${logo()} Pulse</div>
      <nav class="nav" aria-label="Main">${NAV.map(([id, label]) =>
        html`<a href="#/${id}" ${active === id ? raw('aria-current="page"') : ''}>${label}</a>`)}</nav>
      <div class="who"><span class="avatar">${initials()}</span>
        <div style="line-height:1.2;min-width:0"><div style="font-weight:700;font-size:13px">${S.user?.name || 'You'}</div>
        <div class="dim" style="font-size:11px;overflow:hidden;text-overflow:ellipsis">${S.user?.email}</div></div></div>
    </aside>
    <main class="main" id="main">
      <header class="top"><div>${eyebrow ? html`<div class="eyebrow">${eyebrow}</div>` : ''}<h1>${title}</h1></div><div class="row" style="gap:10px;align-items:center">${right}</div></header>
      ${body}
    </main>
    <button class="fab" data-act="assistant-open" aria-label="Ask Pulse"><svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#1d0d02" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg></button>
  </div>`;
}

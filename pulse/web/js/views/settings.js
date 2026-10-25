import { api } from '../api.js';
import { actions } from '../actions.js';
import { html, raw, clock, toast, modal, fromTimeInput, toTimeInput, esc } from '../ui.js';
import { shell } from '../shell.js';
import { S, mutate, flush, endSession } from '../store.js';
import { draft } from './onboarding.js';

const st = { providers: { available: ['local'], active: 'local', chosen: '' } };
const NAMES = { anthropic: 'Anthropic Claude', openai: 'OpenAI', gemini: 'Google Gemini', local: 'Built-in (offline parser)' };
const ALLERGIES = ['Peanuts', 'Tree nuts', 'Dairy', 'Gluten', 'Eggs', 'Fish', 'Shellfish', 'Soy'];

export const settings = {
  async load() { st.providers = await api.providers(); },
  render() {
    const p = S.snap.profile;
    const field = (id, label, key, min, max, step = 1) => html`<div class="field"><label for="${id}">${label}</label><input class="input" id="${id}" type="number" min="${min}" max="${max}" step="${step}" value="${p[key]}" data-change="st-num" data-key="${key}" data-min="${min}" data-max="${max}"></div>`;
    return shell('settings', { eyebrow: 'Settings', title: 'AI assistant and your data' },
      html`<div class="row"><section class="card grow2 stack" aria-labelledby="ai-h"><h2 id="ai-h">AI provider</h2><p class="muted">Choose which model reads your voice and text requests. Nutrition numbers always come from a food database.</p>
        ${['anthropic', 'openai', 'gemini', 'local'].map((id) => {
          const ok = st.providers.available.includes(id);
          return html`<button class="opt" data-act="st-provider" data-v="${id}" aria-pressed="${st.providers.active === id}" ${ok ? '' : raw('disabled style="opacity:.45;cursor:not-allowed"')}>
            <span><b>${NAMES[id]}</b><span>${ok ? (st.providers.active === id ? 'Active' : 'Available') : 'Not set up on this server'}</span></span></button>`;
        })}
        <p class="note">Provider keys stay on the server. They are never stored on your Watch, iPhone or in this web page.</p></section>
        <div class="stack grow"><section class="card stack" aria-labelledby="tg-h"><h2 id="tg-h">Daily targets</h2>
          ${field('s-cal', 'Calories', 'calorieGoal', 1000, 6000, 50)}${field('s-pro', 'Protein (g)', 'proteinGoal', 20, 400, 5)}
          <div class="row"><div class="grow">${field('s-carb', 'Carbs (g)', 'carbsGoal', 0, 800, 5)}</div><div class="grow">${field('s-fat', 'Fat (g)', 'fatGoal', 0, 300, 5)}</div></div></section>
        <section class="card stack" aria-labelledby="fd-h"><h2 id="fd-h">Food</h2>
          <div class="field"><label for="s-diet">Diet</label><select class="input" id="s-diet" data-change="st-text" data-key="diet">${['Vegetarian', 'Non-vegetarian', 'Eggetarian', 'Vegan'].map((d) => html`<option ${p.diet === d ? raw('selected') : ''}>${d}</option>`)}</select></div>
          <div class="label">Allergies</div><div class="chips">${ALLERGIES.map((a) => html`<button class="chip red" data-act="st-allergy" data-v="${a}" aria-pressed="${(p.allergies || []).includes(a)}">${a}</button>`)}</div></section>
        <section class="card stack" aria-labelledby="qh-h"><h2 id="qh-h">Quiet hours</h2><div class="row"><div class="field grow"><label for="s-qs">From</label><input class="input" id="s-qs" type="time" value="${toTimeInput(p.quietStart)}" data-change="st-time" data-key="quietStart"></div>
          <div class="field grow"><label for="s-qe">Until</label><input class="input" id="s-qe" type="time" value="${toTimeInput(p.quietEnd)}" data-change="st-time" data-key="quietEnd"></div></div></section></div></div>
      <section class="card row" style="align-items:center" aria-labelledby="dt-h"><div class="grow2"><h2 id="dt-h">Your data</h2><p class="muted">Export everything as a file, or delete your account and all stored data.</p></div>
        <button class="btn" data-act="st-export">Export data</button><button class="btn ghost" data-act="st-redo">Redo setup</button><button class="btn ghost" data-act="st-logout">Log out</button><button class="btn danger" data-act="st-delete">Delete account</button></section>`);
  },
};

actions.change['st-num'] = (el) => {
  const v = Number(el.value);
  if (!Number.isFinite(v) || v < Number(el.dataset.min) || v > Number(el.dataset.max)) { toast(`Enter a value from ${el.dataset.min} to ${el.dataset.max}`); window.dispatchEvent(new Event('pulse:rerender')); return; }
  mutate((s) => { s.profile[el.dataset.key] = Math.round(v); }); toast('Saved');
};
actions.change['st-text'] = (el) => { mutate((s) => { s.profile[el.dataset.key] = el.value; }); toast('Saved'); };
actions.change['st-time'] = (el) => { if (el.value) { mutate((s) => { s.profile[el.dataset.key] = fromTimeInput(el.value); }); toast('Saved'); } };
actions.click['st-allergy'] = (el) => {
  mutate((s) => { const a = s.profile.allergies || []; s.profile.allergies = a.includes(el.dataset.v) ? a.filter((x) => x !== el.dataset.v) : [...a, el.dataset.v]; });
};
actions.click['st-provider'] = async (el) => {
  mutate((s) => { s.profile.aiProvider = el.dataset.v; });
  await flush(); st.providers = await api.providers(); window.dispatchEvent(new Event('pulse:rerender')); toast('AI provider updated');
};
actions.click['st-export'] = async () => {
  try {
    const res = await api.exportData(); const blob = await res.blob();
    const a = Object.assign(document.createElement('a'), { href: URL.createObjectURL(blob), download: 'pulse-export.json' });
    document.body.appendChild(a); a.click(); a.remove(); toast('Export downloaded');
  } catch (e) { toast(e.message); }
};
actions.click['st-redo'] = () => { Object.assign(draft, { step: 0, error: '', busy: false, name: S.snap.profile.name }); location.hash = '#/onboarding'; };
actions.click['st-logout'] = async () => { await flush(); try { await api.logout(); } catch { /* already gone */ } endSession(); location.hash = '#/login'; };
actions.click['st-delete'] = () => {
  const el = modal(`<h2>Delete your account?</h2><p class="muted">This permanently deletes your profile, meals, workouts and history. It can't be undone. Type <b>DELETE</b> to confirm.</p>
    <input class="input" id="del-confirm" aria-label="Type DELETE to confirm" autocomplete="off"><div class="err" id="del-err" role="alert"></div>
    <div class="row" style="gap:8px"><button class="btn danger" id="del-go" disabled>Delete everything</button><button class="btn ghost" data-close>Cancel</button></div>`);
  const input = el.querySelector('#del-confirm'); const go = el.querySelector('#del-go');
  input.addEventListener('input', () => { go.disabled = input.value !== 'DELETE'; });
  go.addEventListener('click', async () => {
    try { await api.deleteAccount(); endSession(); el.remove(); location.hash = '#/signup'; toast('Account deleted'); }
    catch (e) { el.querySelector('#del-err').textContent = e.message; }
  });
};

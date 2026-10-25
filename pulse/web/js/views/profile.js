import { api } from '../api.js';
import { actions } from '../actions.js';
import { html, raw, clock, toast, modal, esc, fmt, fromTimeInput, toTimeInput, isoNow } from '../ui.js';
import { shell } from '../shell.js';
import { lineChart } from '../charts.js';
import { S, mutate, flush, endSession, initials } from '../store.js';
import { draft } from './onboarding.js';

const st = { stats: null, weights: [], conn: null, sessions: [], error: '' };
const ALLERGIES = ['Peanuts', 'Tree nuts', 'Dairy', 'Gluten', 'Eggs', 'Fish', 'Shellfish', 'Soy'];
const GOALS = [['lose', 'Lose weight'], ['build', 'Build muscle'], ['maintain', 'Maintain'], ['healthier', 'Get healthier']];
const ACTIVITY = [['sitting', 'Mostly sitting'], ['light', 'Lightly active'], ['active', 'Active'], ['veryActive', 'Very active']];
const NAMES = { anthropic: 'Claude', openai: 'OpenAI', gemini: 'Gemini' };

const rerender = () => window.dispatchEvent(new Event('pulse:rerender'));
const num = (id, label, key, min, max, step = 1) => html`<div class="field"><label for="${id}">${label}</label><input class="input" id="${id}" type="number" min="${min}" max="${max}" step="${step}" value="${S.snap.profile[key]}" data-change="pf-num" data-key="${key}" data-min="${min}" data-max="${max}"></div>`;

export const profile = {
  async load() {
    [st.stats, st.weights, st.conn, st.sessions] = await Promise.all([
      api.stats(), api.weights().then((r) => r.weights), api.connectors(), api.sessions().then((r) => r.sessions)]);
  },
  render() {
    const p = S.snap.profile;
    const since = new Date(`${st.stats.memberSince}T12:00:00`).toLocaleDateString('en-US', { month: 'short', year: 'numeric' });
    const own = st.conn.connectors.find((c) => c.provider === p.aiProvider) || st.conn.connectors[0];
    const kgChange = st.stats.weightChangeKg;
    return shell('profile', { eyebrow: 'Profile and settings', title: S.user.name || 'Your profile' }, html`<div class="row" style="align-items:flex-start">
      <div class="stack grow2" style="gap:16px">
        <section class="card" style="display:flex;gap:24px;align-items:center;flex-wrap:wrap" aria-label="Summary">
          <div style="position:relative;width:104px;height:104px;flex:none"><svg width="104" height="104" viewBox="0 0 104 104" aria-hidden="true"><g fill="none" stroke-width="6" stroke-linecap="round" transform="rotate(-90 52 52)"><circle cx="52" cy="52" r="47" stroke="#3a2416"/><circle cx="52" cy="52" r="47" stroke="#FF8A4C" stroke-dasharray="${Math.min(st.stats.streak, 14) / 14 * 295} 295"/></g></svg>
            <div style="position:absolute;inset:10px;border-radius:50%;background:var(--raised);display:grid;place-items:center;font-size:32px;font-weight:800;color:var(--power)">${initials()}</div></div>
          <div style="flex:1;min-width:220px"><h2 style="font-size:22px">${S.user.name}</h2><p class="muted" id="pf-email">${S.user.email} · Member since ${since}</p>
            <div class="row" style="gap:10px;margin-top:14px">
              <div class="card raised" style="padding:10px 16px"><b class="fuel" style="font-size:20px" id="st-streak">${st.stats.streak}</b><div class="note">day streak</div></div>
              <div class="card raised" style="padding:10px 16px"><b class="power" style="font-size:20px">${st.stats.workouts}</b><div class="note">workouts</div></div>
              <div class="card raised" style="padding:10px 16px"><b class="move" style="font-size:20px">${kgChange > 0 ? '+' : ''}${kgChange} kg</b><div class="note">weight change</div></div></div></div></section>

        <section class="card stack" aria-labelledby="pi-h"><h2 id="pi-h">Personal info</h2>
          <form data-submit="pf-info" class="stack"><div class="row"><div class="field grow"><label for="pf-name">Name</label><input class="input" id="pf-name" value="${S.user.name}" maxlength="100"></div>
            <div class="field grow"><label for="pf-mail">Email</label><input class="input" id="pf-mail" type="email" value="${S.user.email}"></div></div>
            <div class="err" id="pf-info-err" role="alert"></div>
            <div class="row" style="gap:10px"><button class="btn lime" type="submit">Save changes</button><button type="button" class="btn ghost" data-act="pf-password">Change password</button></div></form></section>

        <section class="card stack" aria-labelledby="bg-h"><div class="between"><h2 id="bg-h">Body and goals</h2><span class="note">Estimates only. Not medical advice.</span></div>
          <div class="grid4" style="grid-template-columns:repeat(auto-fit,minmax(130px,1fr))">${num('pf-age', 'Age', 'age', 13, 90)}${num('pf-h', 'Height (cm)', 'heightCm', 120, 220)}${num('pf-w', 'Weight (kg)', 'weightKg', 35, 250, 0.1)}${num('pf-t', 'Target (kg)', 'targetKg', 35, 250, 0.1)}</div>
          <div class="chips" role="group" aria-label="Sex used for estimates">${[['male', 'Male'], ['female', 'Female'], ['unspecified', 'Prefer not to say']].map(([v, l]) => html`<button class="chip" data-act="pf-set" data-key="sex" data-v="${v}" aria-pressed="${p.sex === v}">${l}</button>`)}</div>
          <div class="chips" role="group" aria-label="Goal">${GOALS.map(([v, l]) => html`<button class="chip" data-act="pf-set" data-key="goal" data-v="${v}" aria-pressed="${p.goal === v}">${l}</button>`)}</div>
          <div class="chips" role="group" aria-label="Activity">${ACTIVITY.map(([v, l]) => html`<button class="chip lime" data-act="pf-set" data-key="activity" data-v="${v}" aria-pressed="${p.activity === v}">${l}</button>`)}</div>
          <div class="card raised row" style="align-items:center"><div class="grow"><div class="note">Daily target</div><div class="num fuel" style="font-size:26px" id="pf-cal">${p.calorieGoal.toLocaleString('en-US')} kcal</div></div>
            <div class="grow note">${p.proteinGoal} g protein · ${p.carbsGoal} g carbs · ${p.fatGoal} g fat</div><button class="btn primary" data-act="pf-recalc">Recalculate</button></div>
          <details><summary class="muted" style="cursor:pointer;font-weight:700">Adjust targets by hand</summary><div class="grid4" style="margin-top:12px;grid-template-columns:repeat(auto-fit,minmax(130px,1fr))">
            ${num('pf-cal-in', 'Calories', 'calorieGoal', 1000, 6000, 50)}${num('pf-pro', 'Protein (g)', 'proteinGoal', 20, 400, 5)}${num('pf-carb', 'Carbs (g)', 'carbsGoal', 0, 800, 5)}${num('pf-fat', 'Fat (g)', 'fatGoal', 0, 300, 5)}</div></details></section>

        <section class="card stack" aria-labelledby="wl-h"><div class="between"><h2 id="wl-h">Weight log</h2>
          <form data-submit="pf-weight" class="row" style="gap:8px;align-items:center"><label class="sr" for="wl-kg">Weight in kilograms</label><input class="input" id="wl-kg" type="number" step="0.1" min="20" max="400" style="width:100px;height:42px" placeholder="kg"><button class="btn small lime" type="submit">Log weight</button></form></div>
          ${st.weights.length >= 2 ? lineChart(st.weights.map((w) => ({ date: w.date, kg: w.kg })), 'kg', p.targetKg, '#3DD6C6', 170, { fit: true }) : html`<p class="muted">Log your weight a few times to see your trend.</p>`}
          ${st.weights.slice(-4).reverse().map((w) => html`<div class="item"><span class="grow">${w.date}</span><b>${fmt(w.kg)} kg</b><button class="btn small ghost" data-act="pf-delweight" data-day="${w.date}" aria-label="Delete weight from ${w.date}">Delete</button></div>`)}</section>

        <section class="card stack" aria-labelledby="fp-h"><h2 id="fp-h">Food preferences</h2>
          <div class="chips" role="group" aria-label="Diet">${['Vegetarian', 'Non-vegetarian', 'Eggetarian', 'Vegan'].map((d) => html`<button class="chip" data-act="pf-diet" data-v="${d}" aria-pressed="${p.diet === d}">${d}</button>`)}</div>
          <div class="label">Allergies. We never suggest these.</div>
          <div class="chips" role="group" aria-label="Allergies">${ALLERGIES.map((a) => html`<button class="chip red" data-act="pf-allergy" data-v="${a}" aria-pressed="${(p.allergies || []).includes(a)}">${a}</button>`)}</div></section>
      </div>

      <div class="stack grow" style="gap:16px">
        <section class="card stack" style="border-color:#3a4a5e;box-shadow:0 0 0 4px rgba(142,155,255,.07)" aria-labelledby="ai-h"><div class="row" style="align-items:center;flex-wrap:nowrap;gap:12px">
          <span style="width:40px;height:40px;border-radius:13px;background:conic-gradient(var(--fuel),var(--power),var(--move),var(--routine),var(--fuel));display:grid;place-items:center;flex:none"><span style="width:18px;height:18px;border-radius:50%;background:var(--bg)"></span></span>
          <div class="grow"><h2 id="ai-h">AI assistant</h2><div class="note" id="ai-status">${own ? `${NAMES[own.provider]} · using your own key (…${own.last4})` : 'Built-in parser. Add your own key for smarter answers.'}</div></div>
          ${own ? html`<span class="pill" style="background:${own.status === 'ok' ? 'var(--move)' : 'var(--danger)'};color:#06201e">${own.status === 'ok' ? 'Connected' : 'Key rejected'}</span>` : ''}</div>
          <p class="muted">Bring your own Claude, OpenAI or Gemini key. It is encrypted on our server and never shown again.</p>
          <a class="btn" style="background:var(--routine);color:#0e1230" href="#/connectors" id="ai-manage">Manage AI connectors</a></section>

        <section class="card stack" aria-labelledby="qh-h"><h2 id="qh-h">Notifications</h2><div class="row" style="gap:10px"><div class="field grow"><label for="pf-qs">Quiet from</label><input class="input" id="pf-qs" type="time" value="${toTimeInput(p.quietStart)}" data-change="pf-time" data-key="quietStart"></div>
          <div class="field grow"><label for="pf-qe">Until</label><input class="input" id="pf-qe" type="time" value="${toTimeInput(p.quietEnd)}" data-change="pf-time" data-key="quietEnd"></div></div><p class="note">Reminders never fire inside quiet hours.</p></section>

        <section class="card stack" aria-labelledby="cn-h"><h2 id="cn-h">Connections</h2>
          <div class="item"><span class="grow" style="font-weight:700">Apple Health</span><span class="note">Managed on your iPhone</span></div>
          <div class="item"><span class="grow" style="font-weight:700">Apple Watch</span><span class="note">Syncs through your iPhone</span></div>
          <div class="item"><span class="grow" style="font-weight:700">Calendar feed</span><button class="btn small" data-act="pf-ics">Copy link</button><button class="btn small ghost" data-act="pf-ics-reset">Reset</button></div></section>

        <section class="card stack" aria-labelledby="dv-h"><h2 id="dv-h">Signed-in devices</h2>
          ${st.sessions.map((s) => html`<div class="item"><span class="grow" style="font-weight:700">${s.device}</span>${s.current ? html`<span class="pill" style="background:var(--move);color:#06201e">This device</span>` : html`<span class="note">${s.lastUsedAt ? new Date(s.lastUsedAt).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : ''}</span>`}</div>`)}
          <div><button class="btn small" data-act="pf-revoke" ${st.sessions.length < 2 ? 'disabled' : ''}>Sign out of other devices</button></div></section>

        <section class="card stack" aria-labelledby="pd-h"><h2 id="pd-h">Privacy and data</h2><p class="muted">Download everything we store about you, or delete your account and all of it.</p>
          <div class="row" style="gap:8px"><button class="btn small" data-act="st-export">Export my data</button><button class="btn small ghost" data-act="st-redo">Redo setup</button><button class="btn small danger" data-act="st-delete">Delete account</button></div></section>

        <button class="btn ghost" data-act="st-logout">Log out</button><p class="note" style="text-align:center">Pulse 0.3.0 · Guidance only, not medical advice</p>
      </div></div>`);
  },
};

// ---------------------------------------------------------------- personal info
actions.submit['pf-info'] = async (form) => {
  const name = form.querySelector('#pf-name').value.trim();
  const email = form.querySelector('#pf-mail').value.trim().toLowerCase();
  const err = form.querySelector('#pf-info-err');
  err.textContent = '';
  if (!name) { err.textContent = 'Name can\'t be empty.'; return; }
  const body = { name };
  if (email !== S.user.email) {
    const pw = await askPassword('Confirm your password to change your email');
    if (!pw) return;
    body.email = email; body.currentPassword = pw;
  }
  try {
    const res = await api.patchAccount(body);
    S.user = { ...S.user, name: res.name, email: res.email };
    mutate((s) => { s.profile.name = res.name; });
    toast('Profile updated');
  } catch (e) { err.textContent = e.message; }
};

export function askPassword(message) {
  return new Promise((resolve) => {
    const el = modal(`<h2>${esc(message)}</h2><div class="field"><label for="ask-pw">Password</label><input class="input" id="ask-pw" type="password" autocomplete="current-password"></div>
      <div class="row" style="gap:8px"><button class="btn lime" id="ask-ok">Confirm</button><button class="btn ghost" data-close>Cancel</button></div>`);
    const done = (v) => { el.remove(); resolve(v); };
    el.querySelector('#ask-ok').addEventListener('click', () => done(el.querySelector('#ask-pw').value || null));
    el.querySelector('#ask-pw').addEventListener('keydown', (e) => { if (e.key === 'Enter') done(e.target.value || null); });
    new MutationObserver(() => { if (!document.body.contains(el)) resolve(null); }).observe(document.body, { childList: true });
  });
}

actions.click['pf-password'] = () => {
  const el = modal(`<h2>Change password</h2>
    <div class="field"><label for="cp-old">Current password</label><input class="input" id="cp-old" type="password" autocomplete="current-password"></div>
    <div class="field"><label for="cp-new">New password</label><input class="input" id="cp-new" type="password" autocomplete="new-password" minlength="8"><span class="note">At least 8 characters. Other devices are signed out.</span></div>
    <div class="err" id="cp-err" role="alert"></div>
    <div class="row" style="gap:8px"><button class="btn lime" id="cp-go">Update password</button><button class="btn ghost" data-close>Cancel</button></div>`);
  el.querySelector('#cp-go').addEventListener('click', async () => {
    const err = el.querySelector('#cp-err');
    try {
      await api.changePassword({ currentPassword: el.querySelector('#cp-old').value, newPassword: el.querySelector('#cp-new').value });
      el.remove(); toast('Password updated. Other devices were signed out.'); await profile.load(); rerender();
    } catch (e) { err.textContent = e.message; }
  });
};

// ---------------------------------------------------------------- body, goals, targets
actions.change['pf-num'] = (el) => {
  const v = Number(el.value);
  if (!Number.isFinite(v) || v < Number(el.dataset.min) || v > Number(el.dataset.max)) { toast(`Enter a value from ${el.dataset.min} to ${el.dataset.max}`); rerender(); return; }
  mutate((s) => { s.profile[el.dataset.key] = ['weightKg', 'targetKg'].includes(el.dataset.key) ? v : Math.round(v); });
  toast('Saved');
};
actions.click['pf-set'] = (el) => mutate((s) => { s.profile[el.dataset.key] = el.dataset.v; });
actions.click['pf-recalc'] = async () => {
  await flush();
  try { S.snap = await api.recalculate(); toast('Targets recalculated'); await profile.load(); rerender(); } catch (e) { toast(e.message); }
};
actions.submit['pf-weight'] = async (form) => {
  const kg = Number(form.querySelector('#wl-kg').value);
  if (!(kg >= 20 && kg <= 400)) { toast('Enter a weight between 20 and 400 kg'); return; }
  try { await api.logWeight({ kg }); await flush(); S.snap = await api.state(); await profile.load(); rerender(); toast('Weight logged'); } catch (e) { toast(e.message); }
};
actions.click['pf-delweight'] = async (el) => { await api.deleteWeight(el.dataset.day); await profile.load(); rerender(); };

// ---------------------------------------------------------------- food, notifications
actions.click['pf-diet'] = (el) => mutate((s) => { s.profile.diet = el.dataset.v; });
actions.click['pf-allergy'] = (el) => mutate((s) => {
  const a = s.profile.allergies || [];
  s.profile.allergies = a.includes(el.dataset.v) ? a.filter((x) => x !== el.dataset.v) : [...a, el.dataset.v];
});
actions.change['pf-time'] = (el) => { if (el.value) { mutate((s) => { s.profile[el.dataset.key] = fromTimeInput(el.value); }); toast('Saved'); } };

// ---------------------------------------------------------------- connections, devices, data
actions.click['pf-ics'] = async () => {
  const link = `${location.origin}/v1/calendar/${S.user.calendarToken}.ics`;
  try { await navigator.clipboard.writeText(link); toast('Calendar link copied'); } catch { prompt('Copy your calendar link', link); }
};
actions.click['pf-ics-reset'] = async () => {
  const res = await api.rotateCalendar();
  S.user = { ...S.user, calendarToken: res.calendarToken };
  toast('Calendar link reset. The old link no longer works.');
};
actions.click['pf-revoke'] = async () => { await api.revokeOthers(); await profile.load(); rerender(); toast('Signed out of other devices'); };

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
  const el = modal(`<h2>Delete your account?</h2><p class="muted">This permanently deletes your profile, meals, workouts, history and any saved API key. It can't be undone. Type <b>DELETE</b> to confirm.</p>
    <input class="input" id="del-confirm" aria-label="Type DELETE to confirm" autocomplete="off"><div class="err" id="del-err" role="alert"></div>
    <div class="row" style="gap:8px"><button class="btn danger" id="del-go" disabled>Delete everything</button><button class="btn ghost" data-close>Cancel</button></div>`);
  const input = el.querySelector('#del-confirm'); const go = el.querySelector('#del-go');
  input.addEventListener('input', () => { go.disabled = input.value !== 'DELETE'; });
  go.addEventListener('click', async () => {
    try { await api.deleteAccount(); endSession(); el.remove(); location.hash = '#/signup'; toast('Account deleted'); }
    catch (e) { el.querySelector('#del-err').textContent = e.message; }
  });
};

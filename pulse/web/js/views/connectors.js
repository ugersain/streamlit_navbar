import { api } from '../api.js';
import { actions } from '../actions.js';
import { html, raw, toast, modal, esc } from '../ui.js';
import { shell } from '../shell.js';
import { S } from '../store.js';

const st = { conn: null };
const META = {
  anthropic: { letter: 'A', color: 'var(--fuel)', blurb: 'Use Claude models for meal parsing and answers.', placeholder: 'sk-ant-…', url: 'console.anthropic.com' },
  openai: { letter: 'O', color: 'var(--power)', blurb: 'Use GPT models for meal parsing and answers.', placeholder: 'sk-…', url: 'platform.openai.com' },
  gemini: { letter: 'G', color: 'var(--routine)', blurb: 'Use Gemini models for meal parsing and answers.', placeholder: 'AIza…', url: 'aistudio.google.com' },
};
const rerender = () => window.dispatchEvent(new Event('pulse:rerender'));

export const connectorsView = {
  async load() { st.conn = await api.connectors(); },
  render() {
    const byProvider = Object.fromEntries(st.conn.connectors.map((c) => [c.provider, c]));
    const active = S.snap.profile.aiProvider;
    return shell('profile', { eyebrow: html`<a href="#/profile">Profile</a> › AI assistant`, title: 'Connect your AI' }, html`
      <p class="muted" style="max-width:680px;margin:0">Bring your own API key and Pulse uses it for voice logging and answers. You pay your provider directly and stay in control.</p>
      ${st.conn.encryptionAvailable ? '' : html`<div class="card" style="border-color:var(--danger)" role="alert"><b>Saving keys is switched off on this server.</b><p class="muted">The server has no encryption key configured, so it refuses to store API keys. Ask whoever runs this server to set <code>PULSE_ENCRYPTION_KEYS</code>.</p></div>`}
      <div class="row" id="provider-cards">${st.conn.providers.map((p) => {
        const c = byProvider[p.id]; const m = META[p.id];
        return html`<section class="card grow stack" style="${c ? `border-color:${c.status === 'ok' ? 'var(--move)' : 'var(--danger)'};border-width:1.5px` : ''}" aria-label="${p.name}" data-provider="${p.id}">
          <div class="row" style="align-items:center;flex-wrap:nowrap;gap:12px"><span style="width:44px;height:44px;border-radius:14px;background:var(--raised);display:grid;place-items:center;font-weight:800;font-size:18px;color:${m.color}">${m.letter}</span>
            <div class="grow"><h2>${p.name}</h2><div class="note">${c ? (c.status === 'ok' ? (active === p.id ? 'Active' : 'Connected') : 'Key rejected by provider') : 'Not connected'}</div></div>
            ${c ? html`<span class="pill" style="background:${c.status === 'ok' ? 'var(--move)' : 'var(--danger)'};color:#06201e">${c.status === 'ok' ? 'Connected' : 'Update key'}</span>` : ''}</div>
          ${c ? html`<div class="card raised" style="padding:12px 14px"><div class="label">YOUR KEY</div><div style="font-weight:700;letter-spacing:1px;margin:2px 0" class="key-mask">${p.id === 'anthropic' ? 'sk-ant-' : p.id === 'gemini' ? 'AIza' : 'sk-'}••••••••••${c.last4}</div>
              <div class="note">Added ${new Date(c.createdAt).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}${c.lastUsedAt ? ` · last used ${new Date(c.lastUsedAt).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })}` : ''} · never shown again</div></div>
            <div class="row" style="gap:8px"><button class="btn grow" data-act="cn-add" data-p="${p.id}">Replace</button><button class="btn danger grow" data-act="cn-remove" data-p="${p.id}">Remove</button></div>`
          : html`<p class="muted" style="flex:1">${m.blurb}</p><button class="btn primary" data-act="cn-add" data-p="${p.id}" ${st.conn.encryptionAvailable ? '' : 'disabled'}>Add key</button>`}</section>`;
      })}</div>
      <div class="row"><section class="card grow2 stack" style="background:#101a1a;border-color:#1d3a37" aria-labelledby="sec-h"><h2 id="sec-h" style="color:var(--move)">How your key is protected</h2>
        <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:12px 24px;font-size:13px;color:#b4c4c2;line-height:1.5">
          <div><b style="color:var(--text)">Encrypted at rest.</b> AES-256, with the encryption key kept apart from the database.</div>
          <div><b style="color:var(--text)">Never sent back.</b> No screen, app or data export can show it again. You only see the last 4 characters.</div>
          <div><b style="color:var(--text)">Password to change.</b> Adding, replacing or removing a key needs your password.</div>
          <div><b style="color:var(--text)">Checked before saving.</b> We confirm with your provider that the key works.</div>
          <div><b style="color:var(--text)">Used only for you.</b> Only your own requests use it, with strict rate limits.</div>
          <div><b style="color:var(--text)">Gone when you say.</b> Removing it or deleting your account wipes it for good.</div></div></section>
        <section class="card grow stack"><h2>Good to know</h2><p class="muted">Set a monthly spending limit in your provider's dashboard. If you remove your key, Pulse falls back to the built-in parser, so logging still works.</p></section></div>`);
  },
};

actions.click['cn-add'] = (el) => {
  const id = el.dataset.p; const meta = META[id];
  const name = st.conn.providers.find((p) => p.id === id).name;
  const dlg = modal(`<div class="between"><h2>Add your ${esc(name)} key</h2><button class="btn small" data-close>Close</button></div>
    <div class="field"><label for="ck-key">${esc(name)} API key</label><input class="input" id="ck-key" type="password" autocomplete="off" spellcheck="false" placeholder="${esc(meta.placeholder)}"><span class="note">Create one at ${esc(meta.url)}. ${esc(st.conn.providers.find((p) => p.id === id).hint)}.</span></div>
    <div class="field"><label for="ck-pw">Confirm with your Pulse password</label><input class="input" id="ck-pw" type="password" autocomplete="current-password"></div>
    <p class="note">We check the key with ${esc(name)}, then store it encrypted. You pay ${esc(name)} for usage.</p>
    <div class="err" id="ck-err" role="alert"></div>
    <div class="row" style="gap:8px"><button class="btn primary" id="ck-go" style="flex:1">Save and test</button><button class="btn ghost" data-close>Cancel</button></div>`);
  const go = dlg.querySelector('#ck-go');
  go.addEventListener('click', async () => {
    const keyInput = dlg.querySelector('#ck-key'); const pwInput = dlg.querySelector('#ck-pw'); const err = dlg.querySelector('#ck-err');
    err.textContent = ''; go.disabled = true; go.textContent = 'Checking with your provider…';
    try {
      await api.saveKey(id, { apiKey: keyInput.value, password: pwInput.value });
      keyInput.value = ''; pwInput.value = '';          // wipe the secret from the page immediately
      dlg.remove(); toast(`${name} connected`);
      S.snap = await api.state(); await connectorsView.load(); rerender();
    } catch (e) { err.textContent = e.message; go.disabled = false; go.textContent = 'Save and test'; }
  });
};

actions.click['cn-remove'] = (el) => {
  const id = el.dataset.p; const name = st.conn.providers.find((p) => p.id === id).name;
  const dlg = modal(`<h2>Remove your ${esc(name)} key?</h2><p class="muted">The key is deleted from our server. Pulse will use the built-in parser until you add another.</p>
    <div class="field"><label for="rk-pw">Confirm with your Pulse password</label><input class="input" id="rk-pw" type="password" autocomplete="current-password"></div>
    <div class="err" id="rk-err" role="alert"></div>
    <div class="row" style="gap:8px"><button class="btn danger" id="rk-go">Remove key</button><button class="btn ghost" data-close>Cancel</button></div>`);
  dlg.querySelector('#rk-go').addEventListener('click', async () => {
    try {
      await api.removeKey(id, { password: dlg.querySelector('#rk-pw').value });
      dlg.remove(); toast(`${name} key removed`);
      S.snap = await api.state(); await connectorsView.load(); rerender();
    } catch (e) { dlg.querySelector('#rk-err').textContent = e.message; }
  });
};

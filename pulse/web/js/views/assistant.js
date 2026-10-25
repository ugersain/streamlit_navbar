import { api } from '../api.js';
import { actions } from '../actions.js';
import { html, raw, orb, wave, toast, fmt, uuid } from '../ui.js';
import { S, mutate, addMeals } from '../store.js';

const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
const st = { open: false, msgs: [], busy: false, listening: false, rec: null };

function panel() {
  let el = document.getElementById('assistant');
  if (!el) {
    el = document.createElement('div');
    el.id = 'assistant';
    document.body.appendChild(el);
  }
  return el;
}

function view() {
  const el = panel();
  if (!st.open) { el.innerHTML = ''; return; }
  el.innerHTML = html`<aside class="panel" role="dialog" aria-label="Pulse assistant">
    <header>${orb(40)}<div style="flex:1"><div style="font-weight:800;font-size:18px">Pulse assistant</div><div class="note">Answers are estimates, not medical advice</div></div>
      <button class="btn small" data-act="assistant-close" aria-label="Close assistant">Close</button></header>
    <div class="msgs" id="msgs" tabindex="0">
      ${st.msgs.length === 0 ? html`<div class="bubble ai">Hi ${S.snap.profile.name || 'there'}! Tell me what you ate, ask about your day, or say “remind me in 20 minutes to stretch”.</div>` : ''}
      ${st.msgs.map((m, i) => m.role === 'me' ? html`<div class="bubble me">${m.text}</div>` : html`<div class="bubble ai">${m.text}
        ${(m.items || []).map((it) => html`<div class="foodrow ${it.confident ? '' : 'unsure'}"><span>${fmt(it.quantity)} × ${it.name}${it.confident ? '' : ' (check)'}</span><span class="fuel">${it.calories}</span></div>`)}
        ${m.items?.length ? html`<div class="acts"><button class="btn small primary" data-act="assistant-save" data-i="${i}" ${m.saved || !m.items.some((x) => x.confident) ? 'disabled' : ''}>${m.saved ? 'Saved' : 'Save to diary'}</button></div>` : ''}</div>`)}
      ${st.busy ? html`<div class="bubble ai" aria-label="Thinking"><span class="dots"><i></i><i></i><i></i></span></div>` : ''}
    </div>
    <div class="compose">
      ${st.msgs.length === 0 ? html`<div class="sugg">${['Log two eggs and toast', 'How is my protein today?', 'Remind me in 20 minutes to stretch'].map((t) => html`<button data-act="assistant-suggest" data-t="${t}">${t}</button>`)}</div>` : ''}
      <form data-submit="assistant-send" class="bar2"><label class="sr" for="assistant-input">Message</label>
        ${st.listening ? html`<span style="display:flex;align-items:center;gap:10px">${wave()}</span>` : ''}
        <input id="assistant-input" autocomplete="off" maxlength="500" placeholder="${st.listening ? 'Listening…' : 'Ask or log something'}">
        ${Recognition ? html`<button type="button" class="mic" data-act="assistant-mic" aria-pressed="${st.listening}" aria-label="${st.listening ? 'Stop listening' : 'Speak'}">${raw('<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#1d0d02" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg>')}</button>` : ''}
        <button class="btn small primary" type="submit" ${st.busy ? 'disabled' : ''}>Send</button></form>
      ${Recognition ? '' : html`<p class="note">Voice isn't supported in this browser. Type instead, or use the Watch or iPhone app.</p>`}</div></aside>`.toString();
  const msgs = el.querySelector('#msgs');
  if (msgs) msgs.scrollTop = msgs.scrollHeight;
  el.querySelector('#assistant-input')?.focus();
}

export function openAssistant(text) {
  st.open = true; view();
  if (text) send(text);
}

async function send(text) {
  text = text.trim();
  if (!text || st.busy) return;
  st.msgs.push({ role: 'me', text }); st.busy = true; view();
  const history = st.msgs.slice(0, -1).slice(-8).map((m) => ({ role: m.role === 'me' ? 'user' : 'assistant', text: m.text }));
  try {
    const res = await api.assist(text, history);
    const meal = res.actions.find((a) => a.type === 'log_meal');
    const reminder = res.actions.find((a) => a.type === 'add_reminder');
    if (reminder) {
      const due = new Date(Date.now() + (reminder.minutesFromNow || 30) * 60000);
      mutate((s) => s.reminders.push({ id: uuid(), title: reminder.title, minutes: due.getHours() * 60 + due.getMinutes(), oneOff: true }));
    }
    st.msgs.push({ role: 'ai', text: res.reply, items: meal?.items });
  } catch (e) {
    st.msgs.push({ role: 'ai', text: e.message });
  }
  st.busy = false; view();
}

function toggleMic() {
  if (!Recognition) return;
  if (st.listening) { st.rec?.stop(); return; }
  const rec = new Recognition();
  rec.lang = navigator.language || 'en-US';
  rec.interimResults = true;
  rec.onresult = (e) => { const input = document.getElementById('assistant-input'); if (input) input.value = [...e.results].map((r) => r[0].transcript).join(''); };
  rec.onend = () => {
    st.listening = false;
    const input = document.getElementById('assistant-input');
    const text = input?.value || '';
    view();
    if (text.trim()) send(text);
  };
  rec.onerror = () => { st.listening = false; toast('Could not hear you. Try typing instead.'); view(); };
  st.rec = rec; st.listening = true; rec.start(); view();
}

actions.click['assistant-open'] = () => openAssistant();
actions.click['assistant-close'] = () => { st.rec?.abort?.(); st.listening = false; st.open = false; view(); };
actions.click['assistant-suggest'] = (el) => send(el.dataset.t);
actions.click['assistant-mic'] = toggleMic;
actions.click['assistant-save'] = (el) => {
  const m = st.msgs[Number(el.dataset.i)];
  if (!m || m.saved) return;
  const items = m.items.filter((i) => i.confident);
  addMeals(items, { source: 'voice' });
  m.saved = true; view(); toast(`Saved ${items.reduce((t, i) => t + i.calories, 0)} kcal`);
};
actions.submit['assistant-send'] = (form) => {
  const input = form.querySelector('input');
  const text = input.value; input.value = '';
  send(text);
};
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && st.open) actions.click['assistant-close'](); });

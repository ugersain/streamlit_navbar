import { actions } from '../actions.js';
import { html, clock, toast, uuid, fromTimeInput, toTimeInput, isoNow } from '../ui.js';
import { shell } from '../shell.js';
import { S, mutate, remindersSorted, doneToday } from '../store.js';

export const routines = {
  render() {
    const list = remindersSorted();
    const p = S.snap.profile;
    return shell('routines', { eyebrow: 'Habits and reminders', title: 'Your day' },
      html`<div class="row"><section class="card grow2" aria-label="Reminders">
        ${list.map((r) => {
          const d = doneToday(r.lastCompleted);
          return html`<div class="item ${d ? 'done' : ''}"><span class="note" style="width:76px;font-weight:700">${clock(r.minutes)}</span>
            <span class="grow t" style="font-weight:700">${r.title}${r.oneOff ? html` <span class="pill warn">one-off</span>` : ''}</span>
            <button class="btn small" data-act="rt-snooze" data-id="${r.id}" ${d ? 'disabled' : ''} aria-label="Snooze ${r.title} by 10 minutes">Snooze</button>
            <button class="check" data-act="rt-done" data-id="${r.id}" aria-pressed="${d}" aria-label="${d ? 'Undo' : 'Mark done'}: ${r.title}">${d ? '✓' : ''}</button>
            <button class="btn small ghost" data-act="rt-del" data-id="${r.id}" aria-label="Delete ${r.title}">Delete</button></div>`;
        })}
        ${list.length === 0 ? html`<p class="muted">No reminders yet.</p>` : ''}</section>
        <aside class="card grow stack"><h2>Add a reminder</h2>
          <form data-submit="rt-add" class="stack"><div class="field"><label for="rt-title">What</label><input class="input" id="rt-title" required maxlength="80" placeholder="Stretch for 5 minutes"></div>
          <div class="field"><label for="rt-time">When</label><input class="input" id="rt-time" type="time" value="12:00" required></div>
          <div class="err" id="rt-err" role="alert"></div><button class="btn primary" type="submit">Add reminder</button></form>
          <p class="note">Reminders stay quiet from ${clock(p.quietStart)} to ${clock(p.quietEnd)}. Change this in Settings.</p></aside></div>`);
  },
};

actions.click['rt-done'] = (el) => mutate((s) => {
  const r = s.reminders.find((x) => x.id === el.dataset.id);
  if (!r) return;
  if (doneToday(r.lastCompleted)) delete r.lastCompleted; else r.lastCompleted = isoNow();
});
actions.click['rt-snooze'] = (el) => {
  mutate((s) => { const r = s.reminders.find((x) => x.id === el.dataset.id); if (r) r.snoozedUntil = new Date(Date.now() + 600000).toISOString().replace(/\.\d{3}Z$/, 'Z'); });
  toast('Snoozed for 10 minutes');
};
actions.click['rt-del'] = (el) => mutate((s) => { s.reminders = s.reminders.filter((x) => x.id !== el.dataset.id); });
actions.submit['rt-add'] = (form) => {
  const title = form.querySelector('#rt-title').value.trim();
  const time = form.querySelector('#rt-time').value;
  if (!title || !time) { form.querySelector('#rt-err').textContent = 'Enter a name and a time.'; return; }
  mutate((s) => { s.reminders.push({ id: uuid(), title, minutes: fromTimeInput(time), oneOff: false }); });
  toast('Reminder added');
};

import { actions } from '../actions.js';
import { html, clock, fmt, toast, uuid, fromTimeInput, toTimeInput, isoNow } from '../ui.js';
import { shell } from '../shell.js';
import { S, mutate, workoutOn, doneToday } from '../store.js';

const DAYS = ['', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const findDay = (s, id) => s.plan.find((d) => d.id === id);

function exerciseCard(day, ex) {
  const allDone = ex.sets.every((s) => doneToday(s.doneOn));
  return html`<section class="card" aria-label="${ex.name}"><div class="between"><h2>${ex.name}${allDone ? html` <span class="pill lime">done</span>` : ''}</h2>
    <span class="note">rest ${ex.restSeconds}s</span></div>
    ${ex.sets.map((st, i) => {
      const d = doneToday(st.doneOn);
      return html`<div class="set ${d ? 'done' : ''}"><b>${i + 1}</b>
        <input type="number" step="2.5" min="0" max="400" value="${st.weightKg}" aria-label="Set ${i + 1} weight in kilograms" data-change="wk-edit" data-day="${day.id}" data-ex="${ex.id}" data-set="${st.id}" data-field="weightKg">
        <input type="number" step="1" min="0" max="100" value="${st.reps}" aria-label="Set ${i + 1} reps" data-change="wk-edit" data-day="${day.id}" data-ex="${ex.id}" data-set="${st.id}" data-field="reps">
        <button class="check lime" data-act="wk-toggle" data-day="${day.id}" data-ex="${ex.id}" data-set="${st.id}" aria-pressed="${d}" aria-label="${d ? 'Undo' : 'Complete'} set ${i + 1} of ${ex.name}">${d ? '✓' : ''}</button></div>`;
    })}
    <div class="row" style="gap:8px;margin-top:6px"><button class="btn small" data-act="wk-addset" data-day="${day.id}" data-ex="${ex.id}">Add set</button>
      <button class="btn small ghost" data-act="wk-delex" data-day="${day.id}" data-ex="${ex.id}" aria-label="Remove ${ex.name}">Remove exercise</button></div></section>`;
}

export const workouts = {
  render() {
    const now = new Date();
    const today = workoutOn(now);
    const sets = today ? today.exercises.flatMap((e) => e.sets) : [];
    const done = sets.filter((s) => doneToday(s.doneOn)).length;
    const volume = sets.filter((s) => doneToday(s.doneOn)).reduce((t, s) => t + s.weightKg * s.reps, 0);
    const plan = [...S.snap.plan].sort((a, b) => a.weekday - b.weekday);
    return shell('workouts', { eyebrow: today ? `${today.exercises.length} exercises · ${clock(today.startMinutes)}` : 'Recover well', title: today ? today.title : 'Rest day' },
      html`${today ? html`<div class="card lime row" style="align-items:center"><div class="grow"><b class="num power" style="font-size:24px" id="sets-done">${done} / ${sets.length}</b><div class="note">sets done today</div></div>
          <div class="grow"><b class="num" style="font-size:24px">${fmt(volume)} kg</b><div class="note">volume lifted</div></div>
          <p class="note grow2">Tick sets here or on your Watch. Heart rate and Apple Health saving happen on the Watch.</p></div>
        ${today.exercises.map((ex) => exerciseCard(today, ex))}
        <form data-submit="wk-addex" class="card row" style="align-items:end"><div class="field grow"><label for="newex">Add an exercise to ${today.title}</label><input class="input" id="newex" maxlength="60" placeholder="e.g. Lateral raise"></div><button class="btn lime" type="submit">Add exercise</button></form>`
        : html`<div class="card"><h2>Rest day</h2><p class="muted">Recovery is part of the plan. Your next session is below.</p></div>`}
        <section class="card" aria-labelledby="week-h"><h2 id="week-h" style="margin-bottom:6px">Your week</h2>
          ${plan.length === 0 ? html`<p class="muted">No workouts planned.</p>` : plan.map((d) => html`<div class="item"><b style="width:100px">${DAYS[d.weekday]}</b><span class="grow">${d.title} · ${d.exercises.length} exercises</span>
            <label class="sr" for="t-${d.id}">Start time for ${DAYS[d.weekday]}</label><input class="input" style="width:130px;height:40px" id="t-${d.id}" type="time" value="${toTimeInput(d.startMinutes)}" data-change="wk-time" data-day="${d.id}">
            <button class="btn small ghost" data-act="wk-delday" data-day="${d.id}" aria-label="Remove ${DAYS[d.weekday]} workout">Remove</button></div>`)}</section>`);
  },
};

actions.click['wk-toggle'] = (el) => mutate((s) => {
  const set = findDay(s, el.dataset.day)?.exercises.find((e) => e.id === el.dataset.ex)?.sets.find((x) => x.id === el.dataset.set);
  if (!set) return;
  if (doneToday(set.doneOn)) delete set.doneOn; else set.doneOn = isoNow();
});
actions.change['wk-edit'] = (el) => {
  const v = Number(el.value);
  if (!Number.isFinite(v) || v < 0) { toast('Enter a number of 0 or more'); window.dispatchEvent(new Event('pulse:rerender')); return; }
  mutate((s) => {
    const set = findDay(s, el.dataset.day)?.exercises.find((e) => e.id === el.dataset.ex)?.sets.find((x) => x.id === el.dataset.set);
    if (set) set[el.dataset.field] = el.dataset.field === 'reps' ? Math.round(v) : v;
  });
};
actions.click['wk-addset'] = (el) => mutate((s) => {
  const ex = findDay(s, el.dataset.day)?.exercises.find((e) => e.id === el.dataset.ex);
  if (ex) { const last = ex.sets[ex.sets.length - 1] || { weightKg: 20, reps: 10 }; ex.sets.push({ id: uuid(), weightKg: last.weightKg, reps: last.reps }); }
});
actions.click['wk-delex'] = (el) => mutate((s) => { const d = findDay(s, el.dataset.day); if (d) d.exercises = d.exercises.filter((e) => e.id !== el.dataset.ex); });
actions.click['wk-delday'] = (el) => mutate((s) => { s.plan = s.plan.filter((d) => d.id !== el.dataset.day); });
actions.change['wk-time'] = (el) => { if (el.value) mutate((s) => { const d = findDay(s, el.dataset.day); if (d) d.startMinutes = fromTimeInput(el.value); }); };
actions.submit['wk-addex'] = (form) => {
  const name = form.querySelector('#newex').value.trim();
  const today = workoutOn(new Date());
  if (!name || !today) return;
  mutate((s) => { findDay(s, today.id).exercises.push({ id: uuid(), name, restSeconds: 90, sets: [1, 2, 3].map(() => ({ id: uuid(), weightKg: 20, reps: 10 })) }); });
};

import { actions } from '../actions.js';
import { html, raw, rings, pct, fmt, clock, toast } from '../ui.js';
import { shell } from '../shell.js';
import { S, mutate, mealsOn, sum, workoutOn, remindersSorted, doneToday } from '../store.js';
import { openAssistant } from './assistant.js';

const greeting = () => {
  const h = new Date().getHours();
  return h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening';
};

export const dashboard = {
  render() {
    const p = S.snap.profile;
    const meals = mealsOn(new Date());
    const kcal = sum(meals, 'calories'), protein = sum(meals, 'protein');
    const left = p.calorieGoal - kcal;
    const workout = workoutOn(new Date());
    const reminders = remindersSorted();
    const done = reminders.filter((r) => doneToday(r.lastCompleted)).length;
    const exercises = workout ? workout.exercises : [];
    const sets = exercises.flatMap((e) => e.sets);
    const setsDone = sets.filter((s) => doneToday(s.doneOn)).length;
    const eyebrow = new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });

    return shell('dashboard', { eyebrow, title: `${greeting()}, ${p.name || 'there'}`,
      right: html`<form data-submit="dash-ask" class="compose" style="padding:0;width:min(430px,100%)"><div class="bar2" style="border-color:var(--line);box-shadow:none"><label class="sr" for="dash-q">Ask or log food</label>
        <input id="dash-q" placeholder="Try: log two eggs and toast" autocomplete="off"><button class="mic" type="submit" aria-label="Send to assistant">${raw('<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#1d0d02" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14M13 6l6 6-6 6"/></svg>')}</button></div></form>` },
      html`<div class="row">
        <section class="card grow2" aria-labelledby="cal-h" style="display:flex;gap:26px;align-items:center;flex-wrap:wrap">
          <div style="position:relative;width:150px;height:150px;flex:none">${rings(pct(kcal, p.calorieGoal), pct(protein, p.proteinGoal), null, 150)}
            <div style="position:absolute;inset:0;display:grid;place-content:center;text-align:center"><span class="num" style="font-size:28px;line-height:1" id="kcal-left">${Math.max(left, 0)}</span><span class="note">kcal left</span></div></div>
          <div class="stack" style="flex:1;min-width:200px"><h2 id="cal-h" class="sr">Calories today</h2>
            <div class="between"><span class="muted">Eaten</span><span><b class="num fuel" style="font-size:20px" id="kcal-eaten">${kcal}</b> <span class="note">/ ${p.calorieGoal}</span></span></div>
            <div class="between"><span class="muted">Protein</span><span><b class="num power" style="font-size:20px">${fmt(protein)}</b> <span class="note">/ ${p.proteinGoal} g</span></span></div>
            <div class="between"><span class="muted">Carbs</span><span><b class="num" style="font-size:16px">${fmt(sum(meals, 'carbs'))}</b> <span class="note">/ ${p.carbsGoal} g</span></span></div>
            <div class="between"><span class="muted">Fat</span><span><b class="num" style="font-size:16px">${fmt(sum(meals, 'fat'))}</b> <span class="note">/ ${p.fatGoal} g</span></span></div>
            <p class="note">Active energy comes from Apple Health on your iPhone. Calories are estimates.</p></div></section>
        <section class="card lime grow" aria-labelledby="wk-h"><div class="eyebrow power" style="font-weight:800">TODAY'S WORKOUT${workout ? ` · ${clock(workout.startMinutes)}` : ''}</div>
          <h2 id="wk-h" style="font-size:24px;margin:6px 0">${workout ? workout.title : 'Rest day'}</h2>
          <p class="muted">${workout ? exercises.map((e) => e.name).join(' · ') : 'Recovery is part of the plan.'}</p>
          ${workout ? html`<div class="bar" style="margin:14px 0 4px"><i style="width:${pct(setsDone, sets.length) * 100}%;background:var(--power)"></i></div><p class="note">${setsDone} of ${sets.length} sets done</p>
          <div class="row" style="margin-top:10px"><a class="btn lime" href="#/workouts">Open workout</a></div>` : ''}</section></div>
      <div class="row">
        <section class="card grow2" aria-labelledby="rt-h"><div class="between"><h2 id="rt-h">Today's routine</h2><span class="routine note" style="font-weight:800">${done} of ${reminders.length} done</span></div>
          ${reminders.length === 0 ? html`<p class="muted">No reminders yet. Add some in Routines.</p>` : reminders.map((r) => {
            const d = doneToday(r.lastCompleted);
            return html`<div class="item ${d ? 'done' : ''}"><button class="check" data-act="dash-check" data-id="${r.id}" aria-pressed="${d}" aria-label="${d ? 'Done' : 'Mark done'}: ${r.title}">${d ? '✓' : ''}</button>
              <span class="grow t" style="font-weight:700">${r.title}</span><span class="note">${clock(r.minutes)}</span></div>`;
          })}</section>
        <section class="card grow" aria-labelledby="meal-h"><div class="between"><h2 id="meal-h">Meals today</h2><a href="#/nutrition">Diary</a></div>
          ${meals.length === 0 ? html`<p class="muted" style="margin-top:8px">Nothing logged yet. Use the mic or type what you ate.</p>` :
            meals.map((m) => html`<div class="item"><span class="grow" style="font-weight:600">${m.name}</span><span class="fuel num">${m.calories}</span></div>`)}</section></div>`);
  },
};

actions.submit['dash-ask'] = (form) => {
  const input = form.querySelector('input');
  const text = input.value.trim();
  if (text) { input.value = ''; openAssistant(text); } else openAssistant();
};

actions.click['dash-check'] = (el) => {
  mutate((s) => {
    const r = s.reminders.find((x) => x.id === el.dataset.id);
    if (!r) return;
    if (doneToday(r.lastCompleted)) delete r.lastCompleted; else r.lastCompleted = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
    if (r.oneOff && r.lastCompleted) s.reminders = s.reminders.filter((x) => x.id !== r.id);
  });
};

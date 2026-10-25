import { api } from '../api.js';
import { actions } from '../actions.js';
import { html, raw, clock, toast, dayKey, esc } from '../ui.js';
import { shell } from '../shell.js';
import { S, mutate } from '../store.js';
import { recipeModal } from './nutrition.js';

const st = { plan: null, pool: {}, weekStart: null };
const LS = 'pulse.shopping';
const checked = () => { try { return new Set(JSON.parse(localStorage.getItem(LS) || '[]')); } catch { return new Set(); } };
const DAY = ['', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

export const planner = {
  async load() {
    st.plan = await api.mealPlan(st.weekStart);
    st.weekStart = st.plan.start;
    for (const meal of ['breakfast', 'lunch', 'dinner', 'snack']) st.pool[meal] = (await api.recipes(`?meal=${meal}`)).recipes;
  },
  render() {
    const week = st.plan.days;
    const todayKey = dayKey(new Date());
    const byWeekday = (d) => S.snap.plan.find((p) => p.weekday === new Date(`${d}T12:00:00`).getDay() + 1);
    const done = checked();
    const range = `${new Date(`${week[0].date}T12:00:00`).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })} – ${new Date(`${week[6].date}T12:00:00`).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}`;
    return shell('planner', { eyebrow: 'Weekly planner', title: range,
      right: html`<button class="btn small" data-act="pl-prev">‹ Previous</button><button class="btn small" data-act="pl-next">Next ›</button>` },
      html`<section class="card" aria-label="Week plan"><div class="wk">
        <div></div>${week.map((d) => html`<div class="h ${d.date === todayKey ? 'today' : ''}">${DAY[new Date(`${d.date}T12:00:00`).getDay() + 1]} ${new Date(`${d.date}T12:00:00`).getDate()}</div>`)}
        <div class="rl power">Training</div>${week.map((d) => { const w = byWeekday(d.date); return w ? html`<div class="cell gym">${w.title}<small>${clock(w.startMinutes)} · ${w.exercises.length} exercises</small></div>` : html`<div class="cell rest">Rest</div>`; })}
        ${['breakfast', 'lunch', 'dinner', 'snack'].map((meal) => html`<div class="rl fuel" style="text-transform:capitalize">${meal}</div>${week.map((d) => {
          const r = d.meals[meal];
          return html`<div class="cell"><span class="nm">${r ? r.name : 'Nothing planned'}</span><small>${r ? `${r.kcal} kcal` : ''}</small>
            <label class="sr" for="s-${d.date}-${meal}">Swap ${meal} on ${d.date}</label>
            <select id="s-${d.date}-${meal}" data-change="pl-swap" data-date="${d.date}" data-meal="${meal}">${(st.pool[meal] || []).map((p) => html`<option value="${p.id}" ${r && r.id === p.id ? raw('selected') : ''}>${p.name}</option>`)}</select></div>`; })}`)}
        <div class="rl">Total</div>${week.map((d) => html`<div class="cell" style="background:transparent"><b class="fuel">${d.kcal}</b> kcal<small>${Math.round(d.protein)} g protein${d.scale !== 1 ? ` · portions ×${d.scale}` : ''}</small></div>`)}</div></section>
      <div class="row"><section class="card grow2" aria-labelledby="shop-h"><div class="between"><h2 id="shop-h">Shopping list</h2><span class="note">Built from this week's meals</span></div>
        <div class="chips" style="margin-top:10px">${st.plan.shopping.map((i) => { const key = `${i.name}|${i.unit}`; return html`<button class="chip lime" data-act="pl-shop" data-k="${key}" aria-pressed="${done.has(key)}">${i.qty} ${i.unit} ${i.name}</button>`; })}</div></section>
        <section class="card grow stack" aria-labelledby="cal-h"><h2 id="cal-h">Calendar</h2><p class="muted">Your gym sessions as a calendar feed for Apple Calendar or Google Calendar.</p>
          <div class="row" style="gap:8px"><button class="btn lime" data-act="pl-ics">Copy calendar link</button></div><p class="note">Anyone with the link can see your workout times, so keep it private.</p></section></div>`);
  },
};

const rerender = () => window.dispatchEvent(new Event('pulse:rerender'));
const shift = async (days) => {
  const d = new Date(`${st.plan.start}T12:00:00`); d.setDate(d.getDate() + days);
  st.weekStart = dayKey(d); await planner.load(); rerender();
};
actions.click['pl-prev'] = () => shift(-7);
actions.click['pl-next'] = () => shift(7);
actions.change['pl-swap'] = async (el) => {
  try { await api.override({ date: el.dataset.date, meal: el.dataset.meal, recipe_id: el.value }); await planner.load(); rerender(); toast('Meal swapped'); }
  catch (e) { toast(e.message); }
};
actions.click['pl-shop'] = (el) => {
  const set = checked(); const k = el.dataset.k;
  set.has(k) ? set.delete(k) : set.add(k);
  try { localStorage.setItem(LS, JSON.stringify([...set])); } catch { /* ignore */ }
  rerender();
};
actions.click['pl-ics'] = async () => {
  const link = `${location.origin}/v1/calendar/${S.user.calendarToken}.ics`;
  try { await navigator.clipboard.writeText(link); toast('Calendar link copied'); } catch { prompt('Copy your calendar link', link); }
};

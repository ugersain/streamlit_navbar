import { api } from '../api.js';
import { actions } from '../actions.js';
import { html, raw, fmt, toast, modal, dayKey, esc, clock } from '../ui.js';
import { shell } from '../shell.js';
import { S, mealsOn, sum, addMeals, removeMeal } from '../store.js';

const st = { date: new Date(), tab: 'lunch', recipes: [], pending: null, busy: false, error: '' };
const MEALS = [['breakfast', 'Breakfast'], ['lunch', 'Lunch'], ['dinner', 'Dinner'], ['snack', 'Snacks']];
const bucket = (iso) => { const h = new Date(iso).getHours(); return h < 11 ? 'Breakfast' : h < 16 ? 'Lunch' : h < 19 ? 'Snacks' : 'Dinner'; };
const isToday = (d) => dayKey(d) === dayKey(new Date());

export const nutrition = {
  async load() { st.recipes = (await api.recipes(`?meal=${st.tab}`)).recipes; },
  render() {
    const p = S.snap.profile;
    const meals = mealsOn(st.date);
    const groups = ['Breakfast', 'Lunch', 'Snacks', 'Dinner'].map((g) => [g, meals.filter((m) => bucket(m.date) === g)]).filter(([, l]) => l.length);
    const label = isToday(st.date) ? 'Today' : st.date.toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' });
    return shell('nutrition', { eyebrow: `${sum(meals, 'calories')} of ${p.calorieGoal} kcal`, title: 'Food diary',
      right: html`<div class="row" style="gap:8px;align-items:center"><button class="btn small" data-act="nu-prev" aria-label="Previous day">‹</button><b id="nu-day" style="min-width:120px;text-align:center">${label}</b>
        <button class="btn small" data-act="nu-next" aria-label="Next day" ${isToday(st.date) ? 'disabled' : ''}>›</button></div>` },
      html`<div class="row"><div class="stack grow2">
        <form data-submit="nu-add" class="card stack"><label class="label" for="nu-text">Add food: type it like you'd say it</label>
          <div class="row" style="gap:10px"><input class="input grow" id="nu-text" placeholder="2 rotis, a bowl of dal and a cup of curd" autocomplete="off" maxlength="300"><button class="btn primary" type="submit" ${st.busy ? 'disabled' : ''}>${st.busy ? 'Working…' : 'Estimate'}</button></div>
          <div class="err" role="alert">${st.error}</div>
          ${st.pending ? html`<div id="nu-pending" class="stack"><p style="font-weight:700">${st.pending.reply}</p>
            ${st.pending.items.map((i) => html`<div class="foodrow ${i.confident ? '' : 'unsure'}"><span>${fmt(i.quantity)} × ${i.name}${i.confident ? '' : ' (not found, will be skipped)'}</span><span class="fuel">${i.calories}</span></div>`)}
            <p class="note">Estimated from a food database. Amounts vary with portion and preparation.</p>
            <div class="row" style="gap:8px"><button type="button" class="btn primary" data-act="nu-save" ${st.pending.items.some((i) => i.confident) ? '' : 'disabled'}>Save to diary</button><button type="button" class="btn ghost" data-act="nu-cancel">Cancel</button></div></div>` : ''}</form>
        ${groups.length === 0 ? html`<div class="card"><h2>Nothing logged ${isToday(st.date) ? 'yet' : 'this day'}</h2><p class="muted">Type above, tap the mic, or pick a meal idea.</p></div>` :
          groups.map(([g, list]) => html`<section class="card" aria-label="${g}"><div class="between"><h2>${g}</h2><b class="fuel">${sum(list, 'calories')} kcal</b></div>
            ${list.map((m) => html`<div class="item"><div class="grow"><div style="font-weight:600">${m.name}</div><div class="note">${new Date(m.date).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })} · ${fmt(m.protein)} g protein</div></div>
              <b>${m.calories}</b><button class="btn small ghost" data-act="nu-del" data-id="${m.id}" aria-label="Delete ${m.name}">Delete</button></div>`)}</section>`)}</div>
      <aside class="stack grow"><section class="card"><h2>Meal ideas</h2><p class="note" style="margin:4px 0 10px">${p.diet}${p.allergies?.length ? `, never containing ${p.allergies.join(', ').toLowerCase()}` : ''}</p>
        <div class="seg" role="group" aria-label="Meal type">${MEALS.map(([v, l]) => html`<button data-act="nu-tab" data-v="${v}" aria-pressed="${st.tab === v}">${l}</button>`)}</div>
        ${st.recipes.map((r) => html`<div class="item" style="align-items:flex-start"><div class="grow"><b>${r.name}</b><div class="note">${r.kcal} kcal · ${r.protein} g protein · ${r.minutes} min</div></div>
          <button class="btn small" data-act="nu-view" data-id="${r.id}">View</button><button class="btn small primary" data-act="nu-log" data-id="${r.id}" aria-label="Log ${r.name}">Log</button></div>`)}
        ${st.recipes.length === 0 ? html`<p class="muted" style="margin-top:12px">No recipes match your diet and allergies for this meal.</p>` : ''}
        <p class="note" style="margin-top:10px">Nutrition varies by brand and how you cook.</p></section></aside></div>`);
  },
};

const rerender = () => window.dispatchEvent(new Event('pulse:rerender'));
actions.click['nu-prev'] = () => { st.date = new Date(st.date.getTime() - 86400000); rerender(); };
actions.click['nu-next'] = () => { if (!isToday(st.date)) { st.date = new Date(st.date.getTime() + 86400000); rerender(); } };
actions.click['nu-tab'] = async (el) => { st.tab = el.dataset.v; await nutrition.load(); rerender(); };
actions.click['nu-del'] = (el) => { removeMeal(el.dataset.id); toast('Removed'); };
actions.click['nu-cancel'] = () => { st.pending = null; rerender(); };
const when = () => (isToday(st.date) ? new Date() : new Date(st.date.getFullYear(), st.date.getMonth(), st.date.getDate(), 12));
actions.click['nu-save'] = () => {
  addMeals(st.pending.items.filter((i) => i.confident), { when: when() });
  toast(`Saved ${st.pending.items.filter((i) => i.confident).reduce((t, i) => t + i.calories, 0)} kcal`);
  st.pending = null;
};
actions.submit['nu-add'] = async (form) => {
  const text = form.querySelector('#nu-text').value.trim();
  if (!text) { st.error = 'Type what you ate first.'; rerender(); return; }
  st.busy = true; st.error = ''; rerender();
  try {
    const res = await api.assist(`log ${text}`, []);
    const action = res.actions.find((a) => a.type === 'log_meal');
    if (action) st.pending = { reply: res.reply, items: action.items };
    else st.error = res.reply;
  } catch (e) { st.error = e.message; }
  st.busy = false; rerender();
};
actions.click['nu-log'] = (el) => {
  const r = st.recipes.find((x) => x.id === el.dataset.id);
  if (!r) return;
  addMeals([{ name: r.name, calories: r.kcal, protein: r.protein, carbs: r.carbs, fat: r.fat }], { when: when() });
  toast(`Logged ${r.name}`);
};
export function recipeModal(r) {
  modal(`<div class="between"><h2 style="font-size:22px">${esc(r.name)}</h2><button class="btn small" data-close aria-label="Close">Close</button></div>
    <p class="muted">${r.kcal} kcal · ${r.protein} g protein · ${r.carbs} g carbs · ${r.fat} g fat · ${r.minutes} min · ${r.servings} serving</p>
    <h3>Ingredients</h3><ul>${r.ingredients.map((i) => `<li>${esc(i.qty)} ${esc(i.unit)} ${esc(i.name)}</li>`).join('')}</ul>
    <h3>Steps</h3><ol>${r.steps.map((s) => `<li>${esc(s)}</li>`).join('')}</ol>
    <p class="note">${r.allergens.length ? `Contains: ${esc(r.allergens.join(', '))}. ` : ''}Estimates only; brand and preparation vary.</p>`);
}
actions.click['nu-view'] = (el) => { const r = st.recipes.find((x) => x.id === el.dataset.id); if (r) recipeModal(r); };

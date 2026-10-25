import { api } from '../api.js';
import { actions } from '../actions.js';
import { html, raw, fmt, clock, toTimeInput, fromTimeInput, toast, rings } from '../ui.js';
import { logo } from '../shell.js';
import { S } from '../store.js';

const STEPS = ['About you', 'Body and goal', 'Lifestyle', 'Food preferences', 'Daily schedule', 'Your plan'];
const ALLERGIES = ['Peanuts', 'Tree nuts', 'Dairy', 'Gluten', 'Eggs', 'Fish', 'Shellfish', 'Soy'];

export const draft = {
  step: 0, name: '', sex: 'unspecified', age: 28, heightCm: 175, weightKg: 75, targetKg: 72,
  goal: 'lose', activity: 'light', daysPerWeek: 4, diet: 'Vegetarian', allergies: [],
  wakeMinutes: 390, bedMinutes: 1350, workoutMinutes: 1110, result: null, error: '', busy: false,
};

const chip = (act, value, label, on, extra = '') =>
  html`<button type="button" class="chip ${extra}" data-act="${act}" data-v="${value}" aria-pressed="${on}">${label}</button>`;

function body() {
  const d = draft;
  switch (d.step) {
    case 0: return html`<h1>Let's start with you</h1><p class="muted">We use this to estimate your daily energy needs. It's private.</p>
      <div class="field" style="max-width:420px"><label for="ob-name">First name</label><input class="input" id="ob-name" data-change="ob-field" data-key="name" value="${d.name}" autocomplete="given-name"></div>
      <div class="label">Sex used for calorie estimates</div>
      <div class="chips">${[['male', 'Male'], ['female', 'Female'], ['unspecified', 'Prefer not to say']].map(([v, l]) => chip('ob-sex', v, l, d.sex === v))}</div>
      <div class="row" style="max-width:420px"><div class="field grow"><label for="ob-age">Age</label><input class="input" id="ob-age" type="number" min="13" max="90" data-change="ob-num" data-key="age" value="${d.age}"></div>
      <div class="field grow"><label for="ob-h">Height (cm)</label><input class="input" id="ob-h" type="number" min="120" max="220" data-change="ob-num" data-key="heightCm" value="${d.heightCm}"></div></div>`;
    case 1: return html`<h1>Where are you now, and where do you want to be?</h1><p class="muted">We use this to set a realistic daily calorie target.</p>
      <div class="row"><div class="field grow"><label for="ob-w">Current weight (kg)</label><input class="input" id="ob-w" type="number" step="0.5" min="35" max="250" data-change="ob-num" data-key="weightKg" value="${d.weightKg}"></div>
      <div class="field grow"><label for="ob-t">Target weight (kg)</label><input class="input" id="ob-t" type="number" step="0.5" min="35" max="250" data-change="ob-num" data-key="targetKg" value="${d.targetKg}"></div></div>
      <div class="label">Main goal</div><div class="optcards">${[
        ['lose', 'Lose weight', 'Gentle deficit, enough protein', '#FF8A4C'], ['build', 'Build muscle', 'Progressive lifting, more protein', '#C8F25A'],
        ['maintain', 'Maintain weight', 'Balance intake and activity', '#3DD6C6'], ['healthier', 'Get healthier', 'Build steady habits', '#8E9BFF']].map(([v, t, s, c]) =>
        html`<button type="button" class="opt" data-act="ob-goal" data-v="${v}" aria-pressed="${d.goal === v}"><span class="ic" style="background:${c}"></span><span><b>${t}</b><span>${s}</span></span></button>`)}</div>
      <p class="note">Guidance only, not medical advice. Talk to a professional if you have a health condition.</p>`;
    case 2: return html`<h1>Tell us about your days</h1><p class="muted">Outside of workouts, how active are you?</p>
      <div class="chips">${[['sitting', 'Mostly sitting'], ['light', 'Lightly active'], ['active', 'Active'], ['veryActive', 'Very active']].map(([v, l]) => chip('ob-activity', v, l, d.activity === v))}</div>
      <div class="label">Workout days per week</div>
      <div class="chips">${[2, 3, 4, 5, 6].map((n) => chip('ob-days', n, String(n), d.daysPerWeek === n, 'lime'))}</div>`;
    case 3: return html`<h1>How do you like to eat?</h1><p class="muted">We'll suggest meals you'll actually enjoy, and never ones with your allergens.</p>
      <div class="label">Diet type</div><div class="chips">${['Vegetarian', 'Non-vegetarian', 'Eggetarian', 'Vegan'].map((v) => chip('ob-diet', v, v, d.diet === v))}</div>
      <div class="label">Allergies and foods to avoid</div><div class="chips">${ALLERGIES.map((v) => chip('ob-allergy', v, v, d.allergies.includes(v), 'red'))}</div>`;
    case 4: return html`<h1>Shape your day</h1><p class="muted">We'll time meals, reminders and workouts around your routine.</p>
      <div class="row" style="max-width:640px">${[['wakeMinutes', 'Wake up'], ['bedMinutes', 'Bedtime'], ['workoutMinutes', 'Usual workout time']].map(([k, l]) =>
        html`<div class="field grow"><label for="ob-${k}">${l}</label><input class="input" id="ob-${k}" type="time" data-change="ob-time" data-key="${k}" value="${toTimeInput(d[k])}"></div>`)}</div>`;
    default: return html`<h1>Ready to build your plan, ${d.name}</h1><p class="muted">Review your answers, then we'll create your calorie target, workout split and daily routine.</p>
      <div class="card stack"><div class="between"><span class="muted">Goal</span><b>${d.goal}</b></div><div class="between"><span class="muted">Weight</span><b>${fmt(d.weightKg)} kg to ${fmt(d.targetKg)} kg</b></div>
      <div class="between"><span class="muted">Training</span><b>${d.daysPerWeek} days a week at ${clock(d.workoutMinutes)}</b></div>
      <div class="between"><span class="muted">Food</span><b>${d.diet}${d.allergies.length ? `, avoiding ${d.allergies.join(', ').toLowerCase()}` : ''}</b></div>
      <div class="between"><span class="muted">Day</span><b>${clock(d.wakeMinutes)} to ${clock(d.bedMinutes)}</b></div></div>`;
  }
}

export const onboarding = {
  render() {
    const d = draft;
    const last = d.step === STEPS.length - 1;
    return html`<div class="wiz"><aside class="steps"><div class="brand" style="padding:0 0 24px">${logo()} Pulse</div>
      <div class="label" style="margin-bottom:6px">STEP ${d.step + 1} OF ${STEPS.length}</div>
      <ol>${STEPS.map((s, i) => html`<li class="${i < d.step ? 'done' : i === d.step ? 'on' : ''}" ${i === d.step ? raw('aria-current="step"') : ''}><span class="dot">${i < d.step ? '✓' : i + 1}</span><span class="t">${s}</span></li>`)}</ol>
      <p class="note" style="margin-top:auto">Your answers are private. You can change them later in Settings.</p></aside>
      <section class="body">${body()}<div class="err" id="ob-error" role="alert">${d.error}</div>
      <div class="nav-row"><button class="btn ghost" data-act="ob-back" ${d.step === 0 ? 'disabled' : ''}>Back</button>
      <button class="btn primary" data-act="ob-next" ${d.busy ? 'disabled' : ''}>${last ? (d.busy ? 'Building…' : 'Build my plan') : 'Continue'}</button></div></section></div>`;
  },
};

export const plan = {
  render() {
    const r = draft.result, p = r.profile;
    return html`<div class="wiz"><section class="body" style="max-width:1100px;margin:0 auto">
      <div><div class="eyebrow power">Your plan is ready, ${p.name}</div><h1>Here's where we'll start</h1></div>
      <div class="row"><div class="card grow2"><div class="label">DAILY CALORIES</div><div class="num fuel" style="font-size:60px;line-height:1.1" id="plan-cal">${p.calorieGoal.toLocaleString('en-US')}</div>
        <p class="muted">${r.summary.weeklyChangeKg === 0 ? 'Maintaining your weight' : `About ${Math.abs(r.summary.weeklyChangeKg)} kg per week ${r.summary.weeklyChangeKg < 0 ? 'loss' : 'gain'}`}</p>
        <div class="row" style="margin-top:12px">${[['Protein', p.proteinGoal, 'power'], ['Carbs', p.carbsGoal, 'fuel'], ['Fat', p.fatGoal, 'fuel']].map(([n, v, c]) =>
          html`<div class="card raised grow"><div class="eyebrow">${n}</div><div class="num ${c}" style="font-size:24px">${v} g</div></div>`)}</div></div>
        <div class="card grow"><h2>${r.plan.length}-day upper / lower split</h2><p class="muted">${r.plan.map((d) => ['', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d.weekday]).join(', ')} at ${clock(r.plan[0].startMinutes)}</p>
        <p class="note">Beginner friendly. Weights and reps are editable in Workouts.</p></div></div>
      <div class="row"><div class="card grow"><h2>Daily routine</h2><p class="muted">${r.reminders.length} reminders: water, stretching, meals and a wind-down. Quiet from ${clock(p.quietStart)} to ${clock(p.quietEnd)}.</p></div>
        <div class="card grow"><h2>Meal ideas</h2><p class="muted">${p.diet}${p.allergies.length ? `, no ${p.allergies.join(', ').toLowerCase()}` : ''}. Estimates only; brands and cooking vary.</p></div></div>
      <div class="nav-row"><button class="btn ghost" data-act="plan-adjust">Adjust my answers</button><button class="btn lime" data-act="plan-go">Go to dashboard</button></div></section></div>`;
  },
};

const refresh = () => window.dispatchEvent(new Event('pulse:rerender'));
const set = (k, v) => { draft[k] = v; refresh(); };
actions.click['ob-sex'] = (el) => set('sex', el.dataset.v);
actions.click['ob-goal'] = (el) => set('goal', el.dataset.v);
actions.click['ob-activity'] = (el) => set('activity', el.dataset.v);
actions.click['ob-days'] = (el) => set('daysPerWeek', Number(el.dataset.v));
actions.click['ob-diet'] = (el) => set('diet', el.dataset.v);
actions.click['ob-allergy'] = (el) => {
  const v = el.dataset.v; const has = draft.allergies.includes(v);
  set('allergies', has ? draft.allergies.filter((a) => a !== v) : [...draft.allergies, v]);
};
actions.change['ob-field'] = (el) => { draft[el.dataset.key] = el.value; };
actions.change['ob-num'] = (el) => { draft[el.dataset.key] = Number(el.value); };
actions.change['ob-time'] = (el) => { if (el.value) draft[el.dataset.key] = fromTimeInput(el.value); };

function validate() {
  const d = draft;
  if (d.step === 0 && !d.name.trim()) return 'Please tell us your first name.';
  if (d.step === 0 && (d.age < 13 || d.age > 90)) return 'Age must be between 13 and 90.';
  if (d.step === 0 && (d.heightCm < 120 || d.heightCm > 220)) return 'Height must be between 120 and 220 cm.';
  if (d.step === 1 && (d.weightKg < 35 || d.weightKg > 250 || d.targetKg < 35 || d.targetKg > 250)) return 'Weights must be between 35 and 250 kg.';
  return '';
}

actions.click['ob-back'] = () => { draft.error = ''; if (draft.step > 0) set('step', draft.step - 1); };
actions.click['ob-next'] = async () => {
  const problem = validate();
  if (problem) { draft.error = problem; refresh(); return; }
  draft.error = '';
  if (draft.step < STEPS.length - 1) { set('step', draft.step + 1); return; }
  draft.busy = true; refresh();
  try {
    const d = draft;
    draft.result = await api.onboarding({
      name: d.name.trim(), sex: d.sex, age: d.age, heightCm: d.heightCm, weightKg: d.weightKg, targetKg: d.targetKg,
      goal: d.goal, activity: d.activity, daysPerWeek: d.daysPerWeek, diet: d.diet, allergies: d.allergies,
      wakeMinutes: d.wakeMinutes, bedMinutes: d.bedMinutes, workoutMinutes: d.workoutMinutes,
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    });
    S.snap = await api.state();
    draft.busy = false;
    location.hash = '#/plan';
  } catch (e) { draft.busy = false; draft.error = e.message; refresh(); }
};
actions.click['plan-adjust'] = () => { draft.step = 0; location.hash = '#/onboarding'; };
actions.click['plan-go'] = () => { location.hash = '#/dashboard'; };

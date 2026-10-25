import { api } from '../api.js';
import { actions } from '../actions.js';
import { html, fmt } from '../ui.js';
import { shell } from '../shell.js';
import { lineChart, barChart, heat } from '../charts.js';

const st = { days: 30, data: null };

export const insights = {
  async load() { st.data = await api.insights(st.days); },
  render() {
    const { summary: s, days, weeks } = st.data;
    const headline = s.workoutsPlanned
      ? `You completed ${s.workoutsDone} of ${s.workoutsPlanned} planned workouts`
      : 'Log meals and workouts to see your trends';
    return shell('insights', { eyebrow: `Last ${st.days} days`, title: headline,
      right: html`<div class="seg" role="group" aria-label="Range">${[7, 30, 90].map((n) => html`<button data-act="in-range" data-v="${n}" aria-pressed="${st.days === n}">${n} days</button>`)}</div>` },
      html`<div class="grid4">
        <div class="card kpi"><div class="l">Avg calories</div><div class="v fuel" id="k-cal">${fmt(s.avgCalories)}</div><div class="note">goal ${s.calorieGoal} · estimated</div></div>
        <div class="card kpi"><div class="l">Avg protein</div><div class="v power">${fmt(s.avgProtein)} g</div><div class="note">goal ${s.proteinGoal} g · ${s.proteinDaysOnTarget} days on target</div></div>
        <div class="card kpi"><div class="l">Workouts</div><div class="v power" id="k-wk">${s.workoutsDone} / ${s.workoutsPlanned}</div><div class="note">${s.workoutsPlanned ? Math.round((100 * s.workoutsDone) / s.workoutsPlanned) : 0}% adherence</div></div>
        <div class="card kpi"><div class="l">Habits done</div><div class="v routine">${s.habitRate}%</div><div class="note">${s.daysLogged} ${s.daysLogged === 1 ? 'day' : 'days'} with food logged</div></div></div>
      <div class="row"><section class="card grow2" aria-labelledby="c-h"><div class="between"><h2 id="c-h">Calories eaten vs goal</h2><span class="note"><span class="fuel">●</span> eaten &nbsp; ╌ goal</span></div>${lineChart(days, 'calories', s.calorieGoal)}</section>
        <section class="card grow" aria-labelledby="t-h"><h2 id="t-h">Training sessions per week</h2><div style="margin-top:12px">${barChart(weeks.slice(-8).map((w) => ({ value: w.sessions, label: w.week.slice(5) })))}</div>
        <p class="note" style="margin-top:8px">Days with at least one completed set.</p></section></div>
      <div class="row"><section class="card grow2" aria-labelledby="p-h"><h2 id="p-h">Protein vs goal</h2>${lineChart(days, 'protein', s.proteinGoal, '#C8F25A', 180)}</section>
        <section class="card grow" aria-labelledby="h-h"><h2 id="h-h">Habit consistency</h2><div style="margin:14px 0">${heat(days.slice(-30), 'habits', 7)}</div><p class="note">Darker means more habits completed that day.</p></section></div>`);
  },
};

actions.click['in-range'] = async (el) => { st.days = Number(el.dataset.v); await insights.load(); window.dispatchEvent(new Event('pulse:rerender')); };

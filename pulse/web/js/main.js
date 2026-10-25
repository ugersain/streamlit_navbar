import { boot, S, subscribe } from './store.js';
import './actions.js';
import { login, signup } from './views/auth.js';
import { onboarding, plan } from './views/onboarding.js';
import { dashboard } from './views/dashboard.js';
import { planner } from './views/planner.js';
import { insights } from './views/insights.js';
import { nutrition } from './views/nutrition.js';
import { workouts } from './views/workouts.js';
import { routines } from './views/routines.js';
import { settings } from './views/settings.js';
import './views/assistant.js';
import { html } from './ui.js';

const routes = { login, signup, onboarding, plan, dashboard, planner, insights, nutrition, workouts, routines, settings };
const PUBLIC = ['login', 'signup'];
const app = document.getElementById('app');
let current = null;
let ready = false;

function routeName() {
  const name = (location.hash.replace(/^#\//, '').split('?')[0]) || 'dashboard';
  const signedIn = !!S.snap;
  if (!signedIn) return PUBLIC.includes(name) ? name : 'login';
  const onboarded = S.snap.profile.onboarded;
  if (!onboarded && name !== 'onboarding' && name !== 'plan') return 'onboarding';
  if (PUBLIC.includes(name)) return 'dashboard';
  return routes[name] ? name : 'dashboard';
}

function draw() {
  if (!current) return;
  const y = window.scrollY;
  const focusId = document.activeElement?.id;
  app.innerHTML = routes[current].render().toString();
  window.scrollTo(0, y);
  if (focusId) document.getElementById(focusId)?.focus?.();
  document.title = `${current[0].toUpperCase()}${current.slice(1)} · Pulse`;
}

async function navigate() {
  const name = routeName();
  const wanted = (location.hash.replace(/^#\//, '').split('?')[0]) || 'dashboard';
  if (wanted !== name) { location.hash = `#/${name}`; return; }
  current = name;
  const view = routes[name];
  if (view.load) {
    app.innerHTML = '<p class="muted" style="padding:40px" role="status">Loading…</p>';
    try { await view.load(); } catch (e) { if (e.status === 401) { location.hash = '#/login'; return; } app.innerHTML = `<p class="err" style="padding:40px" role="alert">${e.message}</p>`; return; }
  }
  if (current === name) draw();
  window.scrollTo(0, 0);
}

window.addEventListener('hashchange', () => { if (ready) navigate(); });
// Draw on the next tick: re-rendering synchronously inside a blur/change handler throws in Chrome.
let pending = null;
function scheduleDraw() {
  if (pending) return;
  pending = setTimeout(() => { pending = null; draw(); }, 0);
}
window.addEventListener('pulse:rerender', scheduleDraw);
subscribe(() => { if (current && S.snap && !['login', 'signup', 'onboarding', 'plan'].includes(current)) scheduleDraw(); });

(async () => {
  try { await boot(); } catch { app.innerHTML = '<p class="err" style="padding:40px">Can\'t reach the server.</p>'; }
  ready = true;
  await navigate();
})();

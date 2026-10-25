import { api, auth } from './api.js';
import { dayKey, isoNow, sameDay, toast } from './ui.js';

export const S = { user: null, snap: null, deleted: [], pushing: false, dirty: false, version: 0 };
const listeners = new Set();
export const subscribe = (fn) => listeners.add(fn);
const notify = () => listeners.forEach((fn) => fn());

export async function boot() {
  if (!auth.token) return false;
  try {
    S.user = await api.me();
    S.snap = await api.state();
    syncTimezone();
    return true;
  } catch (e) {
    if (e.status === 401) { auth.token = null; return false; }
    throw e;
  }
}

export async function startSession(data) {
  auth.token = data.token;
  S.user = { userId: data.userId, email: data.email, name: data.name };
  S.snap = await api.state();
  syncTimezone();
}

export function endSession() {
  auth.token = null; S.user = null; S.snap = null; S.deleted = [];
}

function syncTimezone() {
  const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
  if (tz && S.snap.profile.onboarded && S.snap.profile.timezone !== tz) mutate((s) => { s.profile.timezone = tz; });
}

export function mutate(fn) {
  S.version += 1;
  fn(S.snap);
  S.snap.updatedAt = isoNow();
  schedulePush();
  notify();
}

export function removeMeal(id) {
  S.deleted.push(id);
  mutate((s) => { s.meals = s.meals.filter((m) => m.id !== id); });
}

let timer;
export function schedulePush(delay = 350) {
  clearTimeout(timer);
  timer = setTimeout(push, delay);
}

export async function push() {
  if (!S.snap) return;
  if (S.pushing) { S.dirty = true; return; }
  S.pushing = true;
  try {
    do {
      S.dirty = false;
      const sent = S.deleted.slice();
      const version = S.version;
      const merged = await api.putState({ ...S.snap, deletedIds: sent });
      S.deleted = S.deleted.filter((id) => !sent.includes(id));
      // Only adopt the server's copy if nothing changed here while the request was in flight.
      // Otherwise keep the newer local edits; the pending debounced push will send them.
      if (!S.dirty && S.version === version) { S.snap = merged; notify(); }
    } while (S.dirty);
  } catch (e) {
    if (e.status === 401) { endSession(); location.hash = '#/login'; }
    else { toast("Offline. Your changes will sync when you're back."); schedulePush(5000); }
  } finally {
    S.pushing = false;
  }
}

export const flush = async () => { clearTimeout(timer); await push(); while (S.pushing) await new Promise((r) => setTimeout(r, 20)); };

// ---------- selectors
export const mealsOn = (date) => S.snap.meals.filter((m) => sameDay(m.date, date)).sort((a, b) => a.date.localeCompare(b.date));
export const sum = (items, key) => items.reduce((t, i) => t + (i[key] || 0), 0);
export const weekdayOf = (date) => date.getDay() + 1;          // calendar weekday: 1 = Sunday
export const workoutOn = (date) => S.snap.plan.find((d) => d.weekday === weekdayOf(date));
export const doneToday = (iso) => !!iso && dayKey(new Date(iso)) === dayKey(new Date());
export const remindersSorted = () => [...S.snap.reminders].sort((a, b) => a.minutes - b.minutes);
export const initials = () => (S.user?.name || S.user?.email || '?').slice(0, 2).toUpperCase();

export function addMeals(items, { source = 'manual', when = new Date() } = {}) {
  mutate((s) => {
    items.forEach((i, n) => s.meals.push({
      id: crypto.randomUUID().toUpperCase(), name: i.name.charAt(0).toUpperCase() + i.name.slice(1),
      quantity: i.quantity ?? 1, unit: i.unit ?? 'serving', calories: Math.round(i.calories), protein: i.protein ?? 0,
      carbs: i.carbs ?? 0, fat: i.fat ?? 0, source,
      date: new Date(when.getTime() + n * 1000).toISOString().replace(/\.\d{3}Z$/, 'Z'),
    }));
  });
}

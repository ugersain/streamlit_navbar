import { api } from '../api.js';
import { actions } from '../actions.js';
import { html, raw } from '../ui.js';
import { logo } from '../shell.js';
import { startSession, S } from '../store.js';

const art = (headline, sub) => html`<section class="art" aria-hidden="false">
  <div class="brand" style="padding:0;font-size:20px">${logo(32)} Pulse</div>
  <h1>${headline}</h1><p class="muted" style="font-size:17px;max-width:460px">${sub}</p>
  <div class="row" style="margin-top:34px">
    <div class="card"><div class="eyebrow">Calories left</div><div class="num fuel" style="font-size:30px">750</div></div>
    <div class="card"><div class="eyebrow">Protein</div><div class="num power" style="font-size:30px">78 g</div></div>
    <div class="card"><div class="eyebrow">Next workout</div><div class="num" style="font-size:30px">6:30 PM</div></div></div>
</section>`;

export const login = {
  render: () => html`<div class="auth">${art('Your plan, on every screen you own.', 'Plan your week here, log meals by voice on your Watch, and review your progress anywhere.')}
    <div class="formside"><form data-submit="login" novalidate>
      <h2>Welcome back</h2><p class="muted">Log in to continue.</p>
      <div class="field"><label for="email">Email</label><input class="input" id="email" name="email" type="email" autocomplete="email" required></div>
      <div class="field"><label for="password">Password</label><input class="input" id="password" name="password" type="password" autocomplete="current-password" required></div>
      <div class="err" id="auth-error" role="alert"></div>
      <button class="btn lime" style="min-height:54px" type="submit">Log in</button>
      <p class="muted" style="text-align:center">New here? <a href="#/signup">Create an account</a></p>
    </form></div></div>`,
};

export const signup = {
  render: () => html`<div class="auth"><div class="formside"><form data-submit="signup" novalidate>
      <div class="brand" style="padding:0">${logo(30)} Pulse</div>
      <h2>Create your account</h2><p class="muted">Free to start. Takes about two minutes.</p>
      <div class="field"><label for="name">First name</label><input class="input" id="name" name="name" autocomplete="given-name" required></div>
      <div class="field"><label for="email">Email</label><input class="input" id="email" name="email" type="email" autocomplete="email" required></div>
      <div class="field"><label for="password">Password</label><input class="input" id="password" name="password" type="password" autocomplete="new-password" minlength="8" required><span class="note">At least 8 characters</span></div>
      <div class="err" id="auth-error" role="alert"></div>
      <button class="btn lime" style="min-height:54px" type="submit">Create account</button>
      <p class="note" style="text-align:center">By continuing you agree to the Terms and Privacy Policy.</p>
      <p class="muted" style="text-align:center">Already have an account? <a href="#/login">Log in</a></p>
    </form></div>
    <section class="art" style="border-left:1px solid #1f252c;border-right:0"><h1 style="margin-top:auto">What you get</h1>
      ${[['Log food by voice', 'Say what you ate. Confirm in one tap.'], ['A gym plan that fits you', 'Sets, reps and rest timers on your wrist.'], ['Routines that stick', 'Gentle reminders, snooze, and quiet hours.']].map(([t, d]) =>
        html`<div class="card" style="margin-bottom:12px"><h3>${t}</h3><p class="muted">${d}</p></div>`)}</section></div>`,
};

async function submit(form, call) {
  const error = form.querySelector('#auth-error');
  const button = form.querySelector('button[type=submit]');
  const data = Object.fromEntries(new FormData(form));
  error.textContent = '';
  if (!data.email?.includes('@')) { error.textContent = 'Enter a valid email address.'; return; }
  if (form.dataset.submit === 'signup' && (data.password || '').length < 8) { error.textContent = 'Use at least 8 characters for your password.'; return; }
  button.disabled = true;
  try {
    const res = await call(data);
    await startSession(res);
    location.hash = S.snap.profile.onboarded ? '#/dashboard' : '#/onboarding';
  } catch (e) {
    error.textContent = e.message;
    button.disabled = false;
  }
}

actions.submit.login = (form) => submit(form, (d) => api.login({ email: d.email, password: d.password }));
actions.submit.signup = (form) => submit(form, (d) => api.signup({ email: d.email, password: d.password, name: d.name || '' }));

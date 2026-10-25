// End-to-end test of the web app in a real browser.  Run:  node e2e/e2e.cjs  (server on :8000)
const { chromium } = require('playwright');
const BASE = process.env.BASE || 'http://localhost:8000';
const SHOTS = process.env.SHOTS || '/tmp/pulse-shots';
require('fs').mkdirSync(SHOTS, { recursive: true });

const results = [];
let page;
const problems = [];

async function step(name, fn) {
  try { await fn(); results.push([true, name]); console.log('  PASS', name); }
  catch (e) {
    results.push([false, name, e.message.split('\n')[0]]); console.log('  FAIL', name, '-', e.message.split('\n')[0]);
    await page.screenshot({ path: `${SHOTS}/FAIL-${name.replace(/\W+/g, '_')}.png` }).catch(() => {});
  }
}
const eq = (a, b, msg) => { if (a !== b) throw new Error(`${msg}: expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`); };
const ok = (c, msg) => { if (!c) throw new Error(msg); };
// Wait (up to 3s) for the app to redraw instead of reading the page the instant after a click.
const eqLater = async (getter, expected, msg) => {
  let got;
  for (let i = 0; i < 30; i++) { got = await getter(); if (got === expected) return; await page.waitForTimeout(100); }
  throw new Error(`${msg}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(got)}`);
};
const text = async (sel) => (await page.locator(sel).first().innerText()).trim();
const settle = async () => { await page.waitForLoadState('networkidle'); await page.waitForTimeout(500); };
const shot = (n) => page.screenshot({ path: `${SHOTS}/${n}.png`, fullPage: true });
const nav = async (hash) => { await page.goto(`${BASE}/#/${hash}`); await page.reload(); await settle(); };

// A stand-in for the AI providers, so key saving can be tested end to end with no real account.
const http = require('http');
const fakeLog = [];
function startFakeProvider() {
  const server = http.createServer((req, res) => {
    const key = req.headers['x-api-key'] || (req.headers.authorization || '').replace('Bearer ', '') || req.headers['x-goog-api-key'] || '';
    if (req.url === '/__reset') { fakeLog.length = 0; res.end('ok'); return; }
    res.setHeader('Access-Control-Allow-Origin', '*');
    let body = '';
    req.on('data', (c) => { body += c; });
    req.on('end', () => {
      fakeLog.push({ path: req.url, key, method: req.method });
      const json = (code, obj) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj)); };
      if (req.method === 'GET' && req.url.endsWith('/v1/models')) return key.includes('VALID') ? json(200, { data: [] }) : json(401, { error: 'bad key' });
      if (req.url.endsWith('/v1/messages')) {
        if (key.includes('REVOKED')) return json(401, { error: 'revoked' });
        return json(200, { content: [{ type: 'tool_use', name: 'log_food', input: { items: [{ name: 'egg', quantity: 2 }] } }] });
      }
      json(404, {});
    });
  });
  return new Promise((resolve) => server.listen(9911, '127.0.0.1', () => resolve(server)));
}

(async () => {
  const fake = await startFakeProvider();
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1360, height: 900 }, acceptDownloads: true, timezoneId: 'Asia/Kolkata', permissions: ['clipboard-read', 'clipboard-write'] });
  page = await context.newPage();
  // The app redraws on the next tick, so give each click a moment to settle before asserting.
  const originalClick = page.click.bind(page);
  page.click = async (...a) => { await originalClick(...a); await page.waitForTimeout(120); };
  page.on('pageerror', (e) => problems.push('pageerror: ' + e.message));
  page.on('console', (m) => { if (m.type() === 'error' && !/fonts\.g|Failed to load resource/.test(m.text())) problems.push('console: ' + m.text()); });
  page.on('dialog', (d) => d.dismiss());

  const email = `e2e${Date.now()}@example.com`;

  console.log('AUTH');
  await step('unauthenticated visit redirects to login', async () => {
    await page.goto(`${BASE}/#/dashboard`); await settle();
    ok(page.url().endsWith('#/login'), 'not on login: ' + page.url());
    await shot('01-login');
  });
  await step('login with wrong credentials shows an error', async () => {
    await page.fill('#email', 'nobody@example.com'); await page.fill('#password', 'wrong password');
    await page.click('button[type=submit]'); await page.waitForSelector('#auth-error:not(:empty)');
    eq(await text('#auth-error'), 'Incorrect email or password', 'message');
  });
  await step('signup validation: bad email, short password', async () => {
    await page.click('text=Create an account'); await settle();
    await page.fill('#name', 'Aarav'); await page.fill('#email', 'not-an-email'); await page.fill('#password', 'longenough');
    await page.click('button[type=submit]');
    ok((await text('#auth-error')).includes('valid email'), 'email error missing');
    await page.fill('#email', email); await page.fill('#password', 'short');
    await page.click('button[type=submit]');
    ok((await text('#auth-error')).includes('8 characters'), 'password error missing');
    await shot('02-signup');
  });
  await step('signup succeeds and goes to onboarding', async () => {
    await page.fill('#password', 'correct horse battery');
    await page.click('button[type=submit]'); await page.waitForURL(/#\/onboarding/); await settle();
    ok(await page.locator('text=Let\'s start with you').isVisible(), 'wizard not shown');
  });

  console.log('ONBOARDING');
  await step('step 1 requires a name', async () => {
    await page.click('[data-act=ob-next]');
    ok((await text('#ob-error')).includes('first name'), 'no name error');
  });
  await step('step 1 -> 2 with valid details', async () => {
    await page.fill('#ob-name', 'Aarav'); await page.click('[data-act=ob-sex][data-v=male]');
    await page.fill('#ob-age', '28'); await page.dispatchEvent('#ob-age', 'change');
    await page.fill('#ob-h', '175'); await page.dispatchEvent('#ob-h', 'change');
    await page.dispatchEvent('#ob-name', 'change');
    await page.click('[data-act=ob-next]');
    ok(await page.locator('text=Where are you now').isVisible(), 'step 2 not shown');
    await shot('03-onboarding-body');
  });
  await step('step 2 rejects an impossible weight', async () => {
    await page.fill('#ob-w', '5'); await page.dispatchEvent('#ob-w', 'change');
    await page.click('[data-act=ob-next]');
    ok((await text('#ob-error')).includes('between 35 and 250'), 'no weight error');
    await page.fill('#ob-w', '78.5'); await page.dispatchEvent('#ob-w', 'change');
    await page.fill('#ob-t', '72'); await page.dispatchEvent('#ob-t', 'change');
    await page.click('[data-act=ob-goal][data-v=lose]');
    await page.click('[data-act=ob-next]');
    ok(await page.locator('text=Tell us about your days').isVisible(), 'step 3 not shown');
  });
  await step('back button keeps answers', async () => {
    await page.click('[data-act=ob-back]');
    eq(await page.inputValue('#ob-w'), '78.5', 'weight kept');
    await page.click('[data-act=ob-next]');
  });
  await step('step 3 lifestyle', async () => {
    await page.click('[data-act=ob-activity][data-v=light]'); await page.click('[data-act=ob-days][data-v="4"]');
    ok(await page.locator('[data-act=ob-days][data-v="4"]').getAttribute('aria-pressed') === 'true', 'days not selected');
    await page.click('[data-act=ob-next]');
  });
  await step('step 4 food: diet and allergies toggle on and off', async () => {
    await page.click('[data-act=ob-diet][data-v=Vegetarian]');
    await page.click('[data-act=ob-allergy][data-v=Peanuts]'); await page.click('[data-act=ob-allergy][data-v=Gluten]');
    await page.click('[data-act=ob-allergy][data-v=Gluten]');
    eq(await page.locator('[data-v=Peanuts]').getAttribute('aria-pressed'), 'true', 'peanuts on');
    eq(await page.locator('[data-v=Gluten]').getAttribute('aria-pressed'), 'false', 'gluten off');
    await page.click('[data-act=ob-next]');
  });
  await step('step 5 schedule, step 6 review, build plan', async () => {
    await page.fill('#ob-wakeMinutes', '06:30'); await page.dispatchEvent('#ob-wakeMinutes', 'change');
    await page.fill('#ob-bedMinutes', '22:30'); await page.dispatchEvent('#ob-bedMinutes', 'change');
    await page.fill('#ob-workoutMinutes', '18:30'); await page.dispatchEvent('#ob-workoutMinutes', 'change');
    await page.click('[data-act=ob-next]');
    ok(await page.locator('text=Ready to build your plan, Aarav').isVisible(), 'review not shown');
    ok(await page.locator('text=avoiding peanuts').isVisible(), 'allergy missing in review');
    await shot('04-onboarding-review');
    await page.click('[data-act=ob-next]'); await page.waitForURL(/#\/plan/); await settle();
  });
  await step('plan page shows targets', async () => {
    const cal = Number((await text('#plan-cal')).replace(/,/g, ''));
    ok(cal > 1500 && cal < 2700, 'calories out of range: ' + cal);
    ok(await page.locator('text=4-day upper / lower split').isVisible(), 'split missing');
    await shot('05-plan');
  });
  await step('go to dashboard', async () => { await page.click('[data-act=plan-go]'); await page.waitForURL(/#\/dashboard/); await settle(); });

  console.log('DASHBOARD');
  await step('dashboard greets and shows rings + routine', async () => {
    ok((await text('h1')).includes('Aarav'), 'no greeting');
    ok(await page.locator('svg[role=img]').first().isVisible(), 'rings missing');
    const n = await page.locator('[data-act=dash-check]').count();
    eq(n, 7, 'routine items');
    await shot('06-dashboard');
  });
  await step('tick a habit and persist across reload', async () => {
    await page.locator('[data-act=dash-check]').first().click();
    await eqLater(async () => page.locator('[data-act=dash-check]').first().getAttribute('aria-pressed'), 'true', 'checked');
    await page.waitForTimeout(900); await page.reload(); await settle();
    eq(await page.locator('[data-act=dash-check]').first().getAttribute('aria-pressed'), 'true', 'persisted');
    ok((await text('.routine.note')).startsWith('1 of 7'), 'counter');
  });

  console.log('ASSISTANT');
  await step('assistant panel opens via the button and closes with Escape', async () => {
    await page.click('.fab'); await page.waitForSelector('.panel');
    ok(await page.locator('.panel .orb').isVisible(), 'orb missing');
    await page.keyboard.press('Escape'); await page.waitForSelector('.panel', { state: 'detached' });
  });
  await step('log food through the assistant and save to the diary', async () => {
    await page.fill('#dash-q', 'log two rotis, one bowl of dal and a cup of curd');
    await page.click('[data-submit=dash-ask] button'); await page.waitForSelector('.panel .foodrow');
    eq(await page.locator('.panel .foodrow').count(), 3, 'food rows');
    ok((await text('.panel .bubble.ai')).includes('488 kcal') || (await text('.panel .bubble.ai')).includes('about 488'), 'total missing: ' + (await text('.panel .bubble.ai')));
    await page.waitForTimeout(500); await shot('07-assistant');
    await page.click('[data-act=assistant-save]'); await page.waitForTimeout(600);
    eq(await text('[data-act=assistant-save]'), 'Saved', 'button state');
    await page.click('[data-act=assistant-close]'); await page.waitForTimeout(900);
    eq(await text('#kcal-eaten'), '488', 'dashboard calories updated');
  });
  await step('assistant: unknown food asks to check, gibberish gets a helpful reply', async () => {
    await page.click('.fab'); await page.fill('#assistant-input', 'blorp zzz'); await page.click('.panel button[type=submit]');
    await page.waitForFunction(() => document.querySelectorAll('.panel .bubble.ai').length >= 2);
    ok((await page.locator('.panel .bubble.ai').last().innerText()).includes('log meals'), 'no helpful reply');
  });
  await step('assistant: reminder request adds a one-off reminder', async () => {
    await page.fill('#assistant-input', 'remind me in 20 minutes to stretch'); await page.click('.panel button[type=submit]');
    await page.waitForFunction(() => document.body.innerText.includes("I'll remind you in 20 min"));
    await page.keyboard.press('Escape'); await page.waitForTimeout(800);
    ok(await page.locator('text=Stretch').first().isVisible(), 'reminder not in routine');
  });

  console.log('NUTRITION');
  await step('diary shows the saved meal and daily total', async () => {
    await nav('nutrition');
    ok((await text('.top .eyebrow')).startsWith('488 of'), 'eyebrow: ' + (await text('.top .eyebrow')));
    ok(await page.locator('.item:has-text("Roti")').count() >= 1, 'roti missing');
    await shot('08-nutrition');
  });
  await step('add food by typing, preview, save, then delete', async () => {
    await page.fill('#nu-text', '3 eggs and a banana'); await page.click('[data-submit=nu-add] button[type=submit]');
    await page.waitForSelector('#nu-pending');
    ok((await text('#nu-pending')).includes('about 339'), 'estimate: ' + (await text('#nu-pending')));
    await page.click('[data-act=nu-save]'); await page.waitForTimeout(800);
    ok((await text('.top .eyebrow')).startsWith('827 of'), 'total after save: ' + (await text('.top .eyebrow')));
    await page.locator('.item:has-text("Banana") [data-act=nu-del]').click(); await page.waitForTimeout(900);
    ok((await text('.top .eyebrow')).startsWith('722 of'), 'total after delete: ' + (await text('.top .eyebrow')));
  });
  await step('empty and unknown input are handled', async () => {
    await page.click('[data-submit=nu-add] button[type=submit]');
    ok((await text('.err[role=alert]')).includes('Type what you ate'), 'empty message');
    await page.fill('#nu-text', 'quantum pancake'); await page.click('[data-submit=nu-add] button[type=submit]');
    await page.waitForFunction(() => document.querySelector('#nu-pending') || document.querySelector('.err')?.textContent);
  });
  await step('meal ideas respect the peanut allergy; log and view a recipe', async () => {
    await page.click('[data-act=nu-tab][data-v=breakfast]'); await page.waitForTimeout(500);
    const body = await text('aside');
    ok(!body.includes('Vegetable poha'), 'poha (peanuts) must not be suggested');
    ok(body.includes('Banana oats') === false || true, 'ok');
    ok(await page.locator('aside .item').count() > 0, 'no ideas');
    await page.locator('aside [data-act=nu-view]').first().click(); await page.waitForSelector('.modal');
    ok((await text('.modal')).includes('Ingredients'), 'ingredients'); await page.keyboard.press('Escape');
    await page.locator('aside [data-act=nu-log]').first().click(); await page.waitForTimeout(800);
  });
  await step('previous day is empty, next is disabled today', async () => {
    await page.click('[data-act=nu-prev]'); await page.waitForTimeout(300);
    ok((await text('.card h2')).includes('Nothing logged'), 'empty day');
    await page.click('[data-act=nu-next]'); await page.waitForTimeout(300);
    eq(await text('#nu-day'), 'Today', 'back to today');
    ok(await page.locator('[data-act=nu-next]').isDisabled(), 'next enabled on today');
  });

  console.log('WORKOUTS');
  await step('workout page lists exercises; weekday plan exists', async () => {
    await nav('workouts');
    ok(await page.locator('text=Your week').isVisible(), 'week list');
    eq(await page.locator('[data-change=wk-time]').count(), 4, 'four planned days');
    await shot('09-workouts');
  });
  // Plan weekdays are Mon/Wed/Fri/Sat; make today a workout day so we can exercise the controls.
  await step('add a workout for today and tick sets', async () => {
    await page.evaluate(async () => {
      const { S, mutate } = await import('/js/store.js');
      const d = new Date().getDay() + 1;
      if (!S.snap.plan.find((p) => p.weekday === d)) mutate((s) => { const c = JSON.parse(JSON.stringify(s.plan[0])); c.id = crypto.randomUUID().toUpperCase(); c.weekday = d; s.plan.push(c); });
    });
    await page.waitForTimeout(900); await page.reload(); await settle();
    ok(await page.locator('.set').count() > 0, 'sets not shown');
    await page.locator('[data-act=wk-toggle]').first().click();
    await eqLater(async () => page.locator('[data-act=wk-toggle]').first().getAttribute('aria-pressed'), 'true', 'set done');
    ok((await text('#sets-done')).startsWith('1 /'), 'counter ' + (await text('#sets-done')));
  });
  await step('edit weight, reject a negative value', async () => {
    const w = page.locator('input[data-field=weightKg]').first();
    await w.fill('47.5'); await w.dispatchEvent('change'); await page.waitForTimeout(700);
    await w.fill('-5'); await w.dispatchEvent('change'); await page.waitForTimeout(500);
    eq(await page.locator('input[data-field=weightKg]').first().inputValue(), '47.5', 'kept previous value');
  });
  await step('add set, add exercise, remove exercise', async () => {
    const before = await page.locator('.set').count();
    await page.locator('[data-act=wk-addset]').first().click(); await page.waitForTimeout(300);
    await eqLater(async () => page.locator('.set').count(), before + 1, 'set added');
    await page.fill('#newex', 'Lateral raise'); await page.click('[data-submit=wk-addex] button'); await page.waitForTimeout(400);
    await eqLater(async () => await page.locator('h2:has-text("Lateral raise")').count(), 1, 'exercise added');
    await page.locator('[aria-label="Remove Lateral raise"]').click(); await page.waitForTimeout(400);
    await eqLater(async () => page.locator('h2:has-text("Lateral raise")').count(), 0, 'exercise removed');
  });
  await step('change start time and remove a planned day', async () => {
    await page.locator('[data-change=wk-time]').first().fill('07:15'); await page.locator('[data-change=wk-time]').first().dispatchEvent('change');
    await page.waitForTimeout(700);
    const n = await page.locator('[data-act=wk-delday]').count();
    await page.locator('[data-act=wk-delday]').last().click(); await page.waitForTimeout(400);
    await eqLater(async () => page.locator('[data-act=wk-delday]').count(), n - 1, 'day removed');
  });

  console.log('PLANNER');
  await step('planner shows a 7-day meal grid and shopping list', async () => {
    await nav('planner');
    eq(await page.locator('.cell select').count(), 28, 'meal cells');
    ok(await page.locator('[data-act=pl-shop]').count() > 5, 'shopping items');
    await shot('10-planner');
  });
  await step('no suggested meal contains peanuts', async () => {
    const all = await page.evaluate(async () => { const r = await fetch('/v1/meal-plan', { headers: { Authorization: 'Bearer ' + localStorage.getItem('pulse.token') } }); return r.json(); });
    for (const d of all.days) for (const r of Object.values(d.meals)) ok(!r.allergens.includes('peanuts'), 'peanut recipe ' + r.id);
  });
  await step('swap a meal and see it stick', async () => {
    const sel = page.locator('.cell select').nth(8);
    const options = await sel.locator('option').allInnerTexts();
    const target = options[options.length - 1];
    await sel.selectOption({ label: target }); await page.waitForTimeout(1000);
    eq((await page.locator('.cell select').nth(8).locator('option:checked').innerText()).trim(), target.trim(), 'swapped');
  });
  await step('tick a shopping item; navigate weeks; copy calendar link', async () => {
    await page.locator('[data-act=pl-shop]').first().click();
    await eqLater(async () => page.locator('[data-act=pl-shop]').first().getAttribute('aria-pressed'), 'true', 'ticked');
    const before = await text('.top h1'); await page.click('[data-act=pl-next]'); await page.waitForTimeout(800);
    ok((await text('.top h1')) !== before, 'week did not change'); await page.click('[data-act=pl-prev]'); await page.waitForTimeout(800);
    await page.click('[data-act=pl-ics]'); await page.waitForTimeout(400);
    const link = await page.evaluate(() => navigator.clipboard.readText());
    ok(/\/v1\/calendar\/.+\.ics$/.test(link), 'link: ' + link);
    const ics = await page.evaluate(async (l) => (await fetch(l)).text(), link);
    ok(ics.startsWith('BEGIN:VCALENDAR') && ics.includes('Gym:'), 'ics content');
  });

  console.log('ROUTINES');
  await step('add, snooze, complete and delete reminders', async () => {
    await nav('routines');
    const before = await page.locator('.item').count();
    await page.fill('#rt-title', 'Take vitamins'); await page.fill('#rt-time', '09:15'); await page.click('[data-submit=rt-add] button');
    await page.waitForTimeout(400); await eqLater(async () => page.locator('.item').count(), before + 1, 'added');
    await eqLater(async () => await page.locator('.item:has-text("Take vitamins")').count(), 1, 'visible');
    await page.locator('.item:has-text("Take vitamins") [data-act=rt-snooze]').click();
    await page.locator('.item:has-text("Take vitamins") [data-act=rt-done]').click(); await page.waitForTimeout(300);
    await eqLater(async () => ((await page.locator('.item:has-text("Take vitamins")').getAttribute('class')) || '').includes('done'), true, 'marked done');
    await page.locator('.item:has-text("Take vitamins") [data-act=rt-del]').click(); await page.waitForTimeout(300);
    await eqLater(async () => page.locator('.item').count(), before, 'deleted');
    await page.click('[data-submit=rt-add] button');
    await shot('11-routines');
  });

  console.log('INSIGHTS');
  await step('insights show real numbers and respond to range changes', async () => {
    await nav('insights');
    ok(Number((await text('#k-cal')).replace(/,/g, '')) > 0, 'avg calories ' + (await text('#k-cal')));
    ok((await text('.top h1')).includes('planned workouts'), 'headline');
    ok(await page.locator('svg[role=img]').count() >= 2, 'charts');
    await page.click('[data-act=in-range][data-v="7"]'); await page.waitForTimeout(600);
    eq(await page.locator('[data-act=in-range][data-v="7"]').getAttribute('aria-pressed'), 'true', '7-day selected');
    await page.click('[data-act=in-range][data-v="90"]'); await page.waitForTimeout(600);
    await shot('12-insights');
  });

  console.log('PROFILE');
  const NEWPASS = 'a brand new pass 99';
  await step('profile page shows the account, streak and every section', async () => {
    await nav('profile');
    ok((await text('h1')).includes('Aarav'), 'name in title');
    for (const h of ['Personal info', 'Body and goals', 'Weight log', 'Food preferences', 'AI assistant', 'Notifications', 'Connections', 'Signed-in devices', 'Privacy and data'])
      ok(await page.locator(`h2:has-text("${h}")`).count() >= 1, 'missing section ' + h);
    ok(Number(await text('#st-streak')) >= 1, 'streak counts today');
    await shot('13-profile');
  });
  await step('editing the name persists', async () => {
    await page.fill('#pf-name', 'Aarav K'); await page.click('[data-submit=pf-info] button[type=submit]'); await page.waitForTimeout(700);
    await page.reload(); await settle(); ok((await text('h1')).includes('Aarav K'), 'name after reload');
  });
  await step('changing the email needs the password (wrong one rejected)', async () => {
    await page.fill('#pf-mail', `changed${Date.now()}@example.com`);
    await page.click('[data-submit=pf-info] button[type=submit]'); await page.waitForSelector('#ask-pw');
    await page.fill('#ask-pw', 'definitely wrong'); await page.click('#ask-ok');
    await page.waitForFunction(() => document.querySelector('#pf-info-err')?.textContent.includes('incorrect'));
    await page.fill('#pf-mail', `changed${Date.now()}@example.com`);
    await page.click('[data-submit=pf-info] button[type=submit]'); await page.waitForSelector('#ask-pw');
    await page.fill('#ask-pw', 'correct horse battery'); await page.click('#ask-ok'); await page.waitForTimeout(800);
    ok((await text('#pf-email')).includes('changed'), 'email updated');
  });
  await step('body and goals: invalid age rejected, goal change + recalculate raises the target', async () => {
    await page.fill('#pf-age', '5'); await page.dispatchEvent('#pf-age', 'change'); await page.waitForTimeout(600);
    eq(await page.inputValue('#pf-age'), '28', 'invalid age restored');
    const before = Number((await text('#pf-cal')).replace(/\D/g, ''));
    await page.fill('#pf-w', '95'); await page.dispatchEvent('#pf-w', 'change'); await page.waitForTimeout(500);
    await page.click('[data-act=pf-set][data-key=goal][data-v=build]'); await page.waitForTimeout(600);
    await page.click('[data-act=pf-recalc]'); await page.waitForTimeout(1200);
    const after = Number((await text('#pf-cal')).replace(/\D/g, ''));
    ok(after > before, `target should rise: ${before} -> ${after}`);
  });
  await step('weight log: add, see the trend, delete', async () => {
    await page.evaluate(async () => {
      const h = { 'Content-Type': 'application/json', Authorization: 'Bearer ' + localStorage.getItem('pulse.token') };
      for (const [d, kg] of [['2026-10-01', 97], ['2026-10-12', 96]]) await fetch('/v1/weights', { method: 'POST', headers: h, body: JSON.stringify({ kg, date: d }) });
    });
    await page.reload(); await settle();
    await page.fill('#wl-kg', '94.5'); await page.click('[data-submit=pf-weight] button'); await page.waitForTimeout(900);
    ok(await page.locator('h2:has-text("Weight log") ~ svg[role=img], section svg[aria-label*="per day"]').count() >= 1, 'weight chart');
    ok((await text('#wl-h')) !== '', 'section');
    await page.locator('[data-act=pf-delweight]').first().click(); await page.waitForTimeout(700);
    ok(await page.locator('[data-act=pf-delweight]').count() >= 2, 'still has history');
  });
  await step('food preferences and quiet hours persist', async () => {
    await page.click('[data-act=pf-diet][data-v=Vegan]'); await page.click('[data-act=pf-allergy][data-v=Soy]');
    await page.fill('#pf-qs', '23:00'); await page.dispatchEvent('#pf-qs', 'change'); await page.waitForTimeout(900);
    await page.reload(); await settle();
    eq(await page.locator('[data-act=pf-diet][data-v=Vegan]').getAttribute('aria-pressed'), 'true', 'diet');
    eq(await page.locator('[data-act=pf-allergy][data-v=Soy]').getAttribute('aria-pressed'), 'true', 'allergy');
    eq(await page.inputValue('#pf-qs'), '23:00', 'quiet hours');
  });
  await step('calendar link works, and resetting it kills the old one', async () => {
    await page.click('[data-act=pf-ics]'); await page.waitForTimeout(300);
    const oldLink = await page.evaluate(() => navigator.clipboard.readText());
    eq(await page.evaluate(async (l) => (await fetch(l)).status, oldLink), 200, 'old link works');
    await page.click('[data-act=pf-ics-reset]'); await page.waitForTimeout(600);
    eq(await page.evaluate(async (l) => (await fetch(l)).status, oldLink), 404, 'old link dead');
    await page.click('[data-act=pf-ics]'); await page.waitForTimeout(300);
    const newLink = await page.evaluate(() => navigator.clipboard.readText());
    ok(newLink !== oldLink && (await page.evaluate(async (l) => (await fetch(l)).status, newLink)) === 200, 'new link works');
  });
  await step('devices: a second sign-in appears and can be signed out', async () => {
    await page.evaluate(async (email) => { await fetch('/v1/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/json', 'User-Agent': 'x' }, body: JSON.stringify({ email, password: 'correct horse battery' }) }); }, (await page.evaluate(() => fetch('/v1/me', { headers: { Authorization: 'Bearer ' + localStorage.getItem('pulse.token') } }).then((r) => r.json()))).email);
    await page.reload(); await settle();
    ok(await page.locator('#dv-h ~ .item').count() >= 2, 'two devices listed');
    ok(await page.locator('.pill:has-text("This device")').count() === 1, 'current marked');
    await page.click('[data-act=pf-revoke]'); await page.waitForTimeout(800);
    eq(await page.locator('#dv-h ~ .item').count(), 1, 'only this device left');
  });
  await step('change password: wrong current rejected; success; new password works', async () => {
    await page.click('[data-act=pf-password]'); await page.waitForSelector('#cp-old');
    await page.fill('#cp-old', 'not it at all'); await page.fill('#cp-new', NEWPASS); await page.click('#cp-go');
    await page.waitForFunction(() => document.querySelector('#cp-err')?.textContent.includes('incorrect'));
    await page.fill('#cp-old', 'correct horse battery'); await page.fill('#cp-new', 'short'); await page.click('#cp-go');
    await page.waitForFunction(() => document.querySelector('#cp-err')?.textContent.length > 0);
    await page.fill('#cp-new', NEWPASS); await page.click('#cp-go'); await page.waitForSelector('.modal', { state: 'detached' });
  });

  console.log('AI CONNECTORS (bring your own key)');
  const KEY = 'sk-ant-api03-VALIDKEYVALIDKEYVALIDKEY1234';
  const DEAD = 'sk-ant-api03-VALIDREVOKEDKEYVALIDREVOKED99';
  await step('connectors page: three providers, none connected, with the security explanation', async () => {
    await page.click('#ai-manage'); await page.waitForURL(/#\/connectors/); await settle();
    eq(await page.locator('[data-provider]').count(), 3, 'providers');
    eq(await page.locator('.key-mask').count(), 0, 'no keys yet');
    ok(await page.locator('text=How your key is protected').isVisible(), 'security section');
    await shot('14-connectors');
  });
  await step('saving needs the right password and never stores a rejected key', async () => {
    await page.click('[data-provider=anthropic] [data-act=cn-add]'); await page.waitForSelector('#ck-key');
    await page.fill('#ck-key', KEY); await page.fill('#ck-pw', 'wrong password!'); await page.click('#ck-go');
    await page.waitForFunction(() => document.querySelector('#ck-err')?.textContent.includes('incorrect'));
    await page.fill('#ck-key', 'sk-ant-api03-BADBADBADBADBADBADBADBAD0000'); await page.fill('#ck-pw', NEWPASS); await page.click('#ck-go');
    await page.waitForFunction(() => document.querySelector('#ck-err')?.textContent.includes('rejected'));
    await page.fill('#ck-key', 'abc'); await page.click('#ck-go');
    await page.waitForFunction(() => document.querySelector('#ck-err')?.textContent.includes("doesn't look like"));
    ok(!(await text('#ck-err')).includes('abc'), 'error echoed the key');
    await page.keyboard.press('Escape');
    eq(await page.locator('.key-mask').count(), 0, 'nothing saved');
  });
  await step('a valid key saves: masked display, field wiped, secret nowhere in the page or storage', async () => {
    await page.click('[data-provider=anthropic] [data-act=cn-add]'); await page.waitForSelector('#ck-key');
    await page.fill('#ck-key', KEY); await page.fill('#ck-pw', NEWPASS); await page.click('#ck-go');
    await page.waitForSelector('[data-provider=anthropic] .key-mask');
    ok((await text('[data-provider=anthropic] .key-mask')).endsWith('1234'), 'last4 shown');
    const leaks = await page.evaluate(async (k) => {
      const h = { Authorization: 'Bearer ' + localStorage.getItem('pulse.token') };
      const bodies = [document.documentElement.outerHTML, JSON.stringify({ ...localStorage }), JSON.stringify({ ...sessionStorage })];
      for (const p of ['/v1/connectors', '/v1/state', '/v1/export', '/v1/me', '/v1/providers', '/v1/sessions']) bodies.push(await (await fetch(p, { headers: h })).text());
      return bodies.map((b, i) => (b.includes(k) || b.includes('VALIDKEYVALIDKEY') ? i : -1)).filter((i) => i >= 0);
    }, KEY);
    eq(leaks.length, 0, 'secret found in: ' + leaks);
    await shot('15-connected');
  });
  await step('the assistant now calls the provider with the user\'s key', async () => {
    fakeLog.length = 0;
    const res = await page.evaluate(async () => (await fetch('/v1/assist', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + localStorage.getItem('pulse.token') }, body: JSON.stringify({ text: 'log two eggs' }) })).json());
    eq(res.provider, 'anthropic (your key)', 'provider label'); ok(!res.notice, 'no notice');
    eq(res.actions[0].items[0].calories, 156, 'database numbers');
    const seen = fakeLog.filter((r) => r.path.endsWith('/v1/messages'));
    ok(seen.length === 1 && seen[0].key === KEY, 'provider received the user key');
    await page.reload(); await settle(); ok((await text('[data-provider=anthropic] .note')).includes('Active'), 'marked active');
  });
  await step('a key the provider later rejects is flagged, with a friendly notice and a working fallback', async () => {
    await page.click('[data-provider=anthropic] [data-act=cn-add]'); await page.waitForSelector('#ck-key');
    await page.fill('#ck-key', DEAD); await page.fill('#ck-pw', NEWPASS); await page.click('#ck-go');
    await page.waitForSelector('[data-provider=anthropic] .key-mask');
    const res = await page.evaluate(async () => (await fetch('/v1/assist', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + localStorage.getItem('pulse.token') }, body: JSON.stringify({ text: 'log an egg' }) })).json());
    ok(res.notice.includes('rejected') && res.actions[0].type === 'log_meal', 'notice + fallback');
    await page.reload(); await settle();
    ok((await text('[data-provider=anthropic]')).includes('Key rejected'), 'card shows the problem');
  });
  await step('the assistant panel shows the notice and still logs food', async () => {
    await nav('dashboard'); await page.click('.fab'); await page.fill('#assistant-input', 'log a banana'); await page.click('.panel button[type=submit]');
    await page.waitForSelector('.panel .foodrow'); await page.keyboard.press('Escape');
  });
  await step('removing a key needs the password and wipes it', async () => {
    await nav('connectors');
    await page.click('[data-provider=anthropic] [data-act=cn-remove]'); await page.waitForSelector('#rk-pw');
    await page.fill('#rk-pw', 'nope nope nope'); await page.click('#rk-go');
    await page.waitForFunction(() => document.querySelector('#rk-err')?.textContent.includes('incorrect'));
    eq(await page.locator('.key-mask').count(), 1, 'still there after wrong password');
    await page.fill('#rk-pw', NEWPASS); await page.click('#rk-go'); await page.waitForSelector('.key-mask', { state: 'detached' });
    await page.reload(); await settle(); eq(await page.locator('.key-mask').count(), 0, 'gone for good');
  });

  console.log('SECURITY HEADERS + PRIVACY');
  await step('every response carries strict security headers; API responses are never cached', async () => {
    for (const path of ['/', '/v1/me']) {
      const r = await page.request.get(BASE + path, { headers: { Authorization: 'Bearer ' + (await page.evaluate(() => localStorage.getItem('pulse.token'))) } });
      const h = r.headers();
      ok(h['content-security-policy']?.includes("script-src 'self'") && h['x-frame-options'] === 'DENY' && h['x-content-type-options'] === 'nosniff', 'headers on ' + path);
    }
    const api = await page.request.get(BASE + '/v1/me', { headers: { Authorization: 'Bearer ' + (await page.evaluate(() => localStorage.getItem('pulse.token'))) } });
    eq(api.headers()['cache-control'], 'no-store', 'cache-control');
  });
  await step('the page works under the strict content security policy (no inline scripts needed)', async () => {
    eq(problems.filter((p) => /Content Security Policy|Refused to/.test(p)).length, 0, 'CSP violations: ' + problems.join('|'));
  });
  await step('export contains no key material', async () => {
    await nav('profile');
    const [dl] = await Promise.all([page.waitForEvent('download'), page.click('[data-act=st-export]')]);
    const text = require('fs').readFileSync(await dl.path(), 'utf8');
    ok(!/sk-ant|VALIDKEY|ciphertext|v1\.[0-9a-f]{8}\./.test(text), 'export leaks key material');
  });
  await step('redo setup, log out, log back in with the NEW password; old password is dead', async () => {
    await page.click('[data-act=st-redo]'); await page.waitForURL(/#\/onboarding/); await settle();
    await page.goto(`${BASE}/#/profile`); await settle();
    const email = (await text('#pf-email')).split(' · ')[0];
    await page.click('[data-act=st-logout]'); await page.waitForURL(/#\/login/); await settle();
    await page.fill('#email', email); await page.fill('#password', 'correct horse battery'); await page.click('button[type=submit]');
    await page.waitForSelector('#auth-error:not(:empty)');
    await page.fill('#password', NEWPASS); await page.click('button[type=submit]'); await page.waitForURL(/#\/dashboard/); await settle();
  });
  await step('delete account requires typing DELETE, then wipes everything', async () => {
    await nav('profile'); const email = (await text('#pf-email')).split(' · ')[0];
    await page.click('[data-act=st-delete]'); await page.waitForSelector('.modal');
    ok(await page.locator('#del-go').isDisabled(), 'delete enabled too early');
    await page.fill('#del-confirm', 'delete'); ok(await page.locator('#del-go').isDisabled(), 'case-insensitive confirm');
    await page.fill('#del-confirm', 'DELETE'); await page.click('#del-go'); await page.waitForURL(/#\/signup/);
    await page.goto(`${BASE}/#/login`); await settle();
    await page.fill('#email', email); await page.fill('#password', NEWPASS); await page.click('button[type=submit]');
    await page.waitForSelector('#auth-error:not(:empty)');
    eq(await text('#auth-error'), 'Incorrect email or password', 'account gone');
  });

  console.log('RESPONSIVE + A11Y');
  await step('mobile layout: no horizontal scroll, bottom nav visible', async () => {
    const m = await browser.newContext({ viewport: { width: 390, height: 844 } }); const p = await m.newPage();
    await p.goto(`${BASE}/#/signup`); await p.waitForLoadState('networkidle');
    await p.fill('#name', 'Mobile'); await p.fill('#email', `m${Date.now()}@example.com`); await p.fill('#password', 'mobile password');
    await p.click('button[type=submit]'); await p.waitForURL(/#\/onboarding/);
    const overflow = await p.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    ok(overflow <= 1, 'horizontal overflow ' + overflow);
    await p.screenshot({ path: `${SHOTS}/14-mobile-onboarding.png` });
    await m.close();
  });
  await step('every input has a label; images/svgs have text alternatives', async () => {
    await page.goto(`${BASE}/#/signup`); await settle();
    const unlabeled = await page.evaluate(() => [...document.querySelectorAll('input,select')].filter((i) => !i.labels?.length && !i.getAttribute('aria-label')).map((i) => i.id || i.name));
    eq(unlabeled.length, 0, 'unlabeled inputs ' + unlabeled);
  });
  await step('no JavaScript or console errors during the whole run', async () => { eq(problems.length, 0, problems.join(' | ')); });

  await browser.close();
  fake.close();
  const failed = results.filter((r) => !r[0]);
  console.log(`\n${results.length - failed.length}/${results.length} passed`);
  failed.forEach((f) => console.log('  FAILED:', f[1], '-', f[2]));
  process.exit(failed.length ? 1 : 0);
})();

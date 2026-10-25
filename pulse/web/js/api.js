const TOKEN_KEY = 'pulse.token';

export const auth = {
  get token() { try { return localStorage.getItem(TOKEN_KEY); } catch { return null; } },
  set token(v) { try { v ? localStorage.setItem(TOKEN_KEY, v) : localStorage.removeItem(TOKEN_KEY); } catch { /* private mode */ } },
};

export class ApiError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

async function request(method, path, body, { raw = false } = {}) {
  const headers = {};
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (auth.token) headers.Authorization = `Bearer ${auth.token}`;
  let res;
  try {
    res = await fetch(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  } catch {
    throw new ApiError(0, "Can't reach the server. Check your connection.");
  }
  if (res.status === 204) return null;
  if (!res.ok) {
    let message = `Something went wrong (${res.status})`;
    try {
      const data = await res.json();
      const detail = data.detail;
      message = typeof detail === 'string' ? detail
        : Array.isArray(detail) ? detail.map((d) => d.msg).join('. ') : message;
    } catch { /* not json */ }
    throw new ApiError(res.status, message);
  }
  return raw ? res : res.json();
}

export const api = {
  signup: (b) => request('POST', '/v1/auth/signup', b),
  login: (b) => request('POST', '/v1/auth/login', b),
  logout: () => request('POST', '/v1/auth/logout'),
  me: () => request('GET', '/v1/me'),
  state: () => request('GET', '/v1/state'),
  putState: (s) => request('PUT', '/v1/state', s),
  onboarding: (b) => request('POST', '/v1/onboarding', b),
  recipes: (q = '') => request('GET', `/v1/recipes${q}`),
  mealPlan: (start) => request('GET', `/v1/meal-plan${start ? `?start=${start}` : ''}`),
  override: (b) => request('PUT', '/v1/meal-plan/override', b),
  insights: (days) => request('GET', `/v1/insights?days=${days}`),
  providers: () => request('GET', '/v1/providers'),
  assist: (text, history) => request('POST', '/v1/assist', { text, history }),
  deleteAccount: () => request('DELETE', '/v1/account'),
  patchAccount: (b) => request('PATCH', '/v1/account', b),
  changePassword: (b) => request('POST', '/v1/account/password', b),
  sessions: () => request('GET', '/v1/sessions'),
  revokeOthers: () => request('POST', '/v1/sessions/revoke-others'),
  rotateCalendar: () => request('POST', '/v1/calendar/rotate'),
  weights: () => request('GET', '/v1/weights'),
  logWeight: (b) => request('POST', '/v1/weights', b),
  deleteWeight: (day) => request('DELETE', `/v1/weights/${day}`),
  recalculate: () => request('POST', '/v1/plan/recalculate'),
  stats: () => request('GET', '/v1/profile/stats'),
  connectors: () => request('GET', '/v1/connectors'),
  saveKey: (provider, b) => request('PUT', `/v1/connectors/${provider}`, b),
  removeKey: (provider, b) => request('POST', `/v1/connectors/${provider}/remove`, b),
  exportData: () => request('GET', '/v1/export', undefined, { raw: true }),
};

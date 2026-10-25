const MAP = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
export const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => MAP[c]);

class Raw { constructor(s) { this.s = s; } toString() { return this.s; } }
export const raw = (s) => new Raw(s);

/** Tagged template that escapes every interpolated value unless it came from html`` itself. */
export function html(strings, ...vals) {
  let out = '';
  strings.forEach((s, i) => {
    out += s;
    if (i < vals.length) {
      const v = vals[i];
      const one = (x) => (x instanceof Raw ? x.s : esc(x));
      out += Array.isArray(v) ? v.map(one).join('') : one(v);
    }
  });
  return new Raw(out);
}

export function toast(message) {
  const el = document.getElementById('toast');
  if (!el) return;
  el.textContent = message;
  el.classList.add('show');
  clearTimeout(toast.t);
  toast.t = setTimeout(() => el.classList.remove('show'), 2600);
}

export const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : '10000000-1000-4000-8000-100000000000'.replace(/[018]/g,
  (c) => (c ^ (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (c / 4)))).toString(16))).toUpperCase();

export const clock = (m) => {
  const h = Math.floor(m / 60) % 24; const min = m % 60;
  return `${h % 12 === 0 ? 12 : h % 12}:${String(min).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
};
export const toTimeInput = (m) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
export const fromTimeInput = (v) => { const [h, m] = v.split(':').map(Number); return h * 60 + m; };
export const fmt = (n) => Number(n).toLocaleString('en-US', { maximumFractionDigits: 1 });
export const pct = (a, b) => Math.min(Math.max(b > 0 ? a / b : 0, 0), 1);

export function orb(size = 40) {
  return html`<span class="orb" style="width:${size}px;height:${size}px" aria-hidden="true"><span class="glow"></span><span class="core"><i></i><b></b></span><span class="shine"></span></span>`;
}
export const wave = () => html`<span class="wave" aria-hidden="true"><i></i><i></i><i></i><i></i></span>`;

export function rings(cal, pro, move, size = 150) {
  const arc = (r, p, color, w) => {
    const c = 2 * Math.PI * r;
    return `<circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="${color}" stroke-opacity=".2" stroke-width="${w}"/>
      <circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="${color}" stroke-width="${w}" stroke-linecap="round"
        stroke-dasharray="${(Math.max(p, 0.01) * c).toFixed(1)} ${c.toFixed(1)}" transform="rotate(-90 ${size / 2} ${size / 2})"/>`;
  };
  const w = size * 0.085;
  return raw(`<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" role="img"
    aria-label="Calories ${Math.round(cal * 100)} percent, protein ${Math.round(pro * 100)} percent${move == null ? '' : `, move ${Math.round(move * 100)} percent`}">
    ${arc(size / 2 - w, cal, '#FF8A4C', w)}${arc(size * 0.37 - w / 2, pro, '#C8F25A', w)}${move == null ? '' : arc(size * 0.24 - w / 2, move, '#3DD6C6', w)}</svg>`);
}

export function modal(contentHtml) {
  const el = document.createElement('div');
  el.className = 'scrim';
  el.innerHTML = `<div class="modal" role="dialog" aria-modal="true">${contentHtml}</div>`;
  el.addEventListener('click', (e) => { if (e.target === el || e.target.closest('[data-close]')) el.remove(); });
  document.addEventListener('keydown', function onKey(e) {
    if (e.key === 'Escape') { el.remove(); document.removeEventListener('keydown', onKey); }
  });
  document.body.appendChild(el);
  el.querySelector('button,input,select')?.focus();
  return el;
}

export const today = () => new Date();
export const dayKey = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
export const sameDay = (iso, d) => dayKey(new Date(iso)) === dayKey(d);
export const isoNow = () => new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');

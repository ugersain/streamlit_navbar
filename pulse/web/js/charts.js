import { raw } from './ui.js';

/** Line chart of daily values with a dashed goal line. */
export function lineChart(days, key, goal, color = '#FF8A4C', height = 220, { fit = false } = {}) {
  const w = 640; const pad = 8;
  const values = days.map((d) => d[key]);
  // fit: zoom to the data range (for weight); otherwise start at zero (for calories).
  const lo = fit ? Math.min(goal, ...values) - 1 : 0;
  const max = fit ? Math.max(goal, ...values) + 1 : Math.max(goal * 1.25, ...values, 1);
  const x = (i) => pad + (i * (w - pad * 2)) / Math.max(days.length - 1, 1);
  const y = (v) => height - 20 - ((v - lo) / (max - lo || 1)) * (height - 40);
  const pts = days.map((d, i) => [x(i), y(d[key])]);
  const line = pts.map((p, i) => `${i ? 'L' : 'M'}${p[0].toFixed(1)} ${p[1].toFixed(1)}`).join(' ');
  const area = `${line} L${x(days.length - 1)} ${height - 20} L${x(0)} ${height - 20} Z`;
  const first = days[0]?.date.slice(5); const last = days[days.length - 1]?.date.slice(5);
  return raw(`<svg viewBox="0 0 ${w} ${height}" width="100%" role="img" aria-label="${key} per day versus goal of ${goal}">
    ${[0.25, 0.5, 0.75, 1].map((f) => `<line x1="0" x2="${w}" y1="${y(lo + (max - lo) * f)}" y2="${y(lo + (max - lo) * f)}" stroke="#262C34"/>`).join('')}
    <line x1="0" x2="${w}" y1="${y(goal)}" y2="${y(goal)}" stroke="#6B7580" stroke-width="1.5" stroke-dasharray="6 6"/>
    <path d="${area}" fill="${color}" fill-opacity=".12"/>
    <path d="${line}" fill="none" stroke="${color}" stroke-width="3" stroke-linejoin="round" stroke-linecap="round"/>
    ${pts.filter((_, i) => days[i][key] > 0).map((p) => `<circle cx="${p[0]}" cy="${p[1]}" r="3.5" fill="${color}"/>`).join('')}
    <text x="0" y="${height - 4}" fill="#9AA4AF" font-size="11">${first}</text>
    <text x="${w}" y="${height - 4}" fill="#9AA4AF" font-size="11" text-anchor="end">${last}</text></svg>`);
}

export function barChart(items, color = '#C8F25A') {
  const max = Math.max(...items.map((i) => i.value), 1);
  return raw(`<div class="bars" role="img" aria-label="Bar chart">${items.map((i) =>
    `<div><i style="height:${Math.max((i.value / max) * 100, 2)}%;background:${color}"></i><span>${i.label}</span></div>`).join('')}</div>`);
}

export function heat(days, key, max) {
  return raw(`<div style="display:grid;grid-template-columns:repeat(${Math.min(days.length, 30)},1fr);gap:4px" role="img" aria-label="${key} by day">${days.map((d) => {
    const level = Math.min(d[key] / Math.max(max, 1), 1);
    return `<i title="${d.date}: ${d[key]}" style="height:18px;border-radius:5px;background:rgba(142,155,255,${(0.12 + level * 0.88).toFixed(2)})"></i>`;
  }).join('')}</div>`);
}

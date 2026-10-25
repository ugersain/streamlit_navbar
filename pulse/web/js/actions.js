/** Delegated events: elements say what they do with data-act / data-change / data-submit. */
export const actions = { click: {}, change: {}, submit: {}, input: {} };

document.addEventListener('click', (e) => {
  const el = e.target.closest('[data-act]');
  if (el && actions.click[el.dataset.act]) actions.click[el.dataset.act](el, e);
});
document.addEventListener('change', (e) => {
  const el = e.target.closest('[data-change]');
  if (el && actions.change[el.dataset.change]) actions.change[el.dataset.change](el, e);
});
document.addEventListener('input', (e) => {
  const el = e.target.closest('[data-input]');
  if (el && actions.input[el.dataset.input]) actions.input[el.dataset.input](el, e);
});
document.addEventListener('submit', (e) => {
  const form = e.target.closest('[data-submit]');
  if (form && actions.submit[form.dataset.submit]) { e.preventDefault(); actions.submit[form.dataset.submit](form, e); }
});

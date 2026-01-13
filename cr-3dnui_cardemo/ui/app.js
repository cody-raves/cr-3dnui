(() => {
  const clamp01 = (v) => Math.max(0, Math.min(1, v));

  const state = {
    page: 'all',
    speed: 0,
    gear: 0,
    engine: false,
  };

  const $ = (sel) => document.querySelector(sel);
  const $$ = (sel) => Array.from(document.querySelectorAll(sel));

  const tabs = $$('.tab');          // buttons with data-page
  const cards = $$('.card');        // panels with data-view
  const cursor = $('#cursor');

  function setPage(page) {
    if (!page) return;
    const p = String(page).toLowerCase();
    state.page = p;

    tabs.forEach(btn => {
      btn.classList.toggle('active', (btn.dataset.page || '').toLowerCase() === p);
    });
    cards.forEach(card => {
      card.classList.toggle('show', (card.dataset.view || '').toLowerCase() === p);
    });
  }

  function render() {
    const spd = String(state.speed ?? 0);
    const gear = String(state.gear ?? 0);
    const eng = state.engine ? 'ON' : 'OFF';

    // ALL page
    const speedAll = $('#speedAll'); if (speedAll) speedAll.textContent = spd;
    const gearAll  = $('#gearAll');  if (gearAll)  gearAll.textContent  = gear;
    const engAll   = $('#engAll');   if (engAll)   engAll.textContent   = eng;

    // Big pages
    const speedBig = $('#speedBig'); if (speedBig) speedBig.textContent = spd;
    const gearBig  = $('#gearBig');  if (gearBig)  gearBig.textContent  = gear;
    const engBig   = $('#engBig');   if (engBig)   engBig.textContent   = eng;
  }

  function setCursor(show, u, v) {
    if (!cursor) return;
    if (!show) {
      cursor.classList.remove('show');
      return;
    }

    const U = clamp01(Number(u));
    const V = clamp01(Number(v));

    // Convert normalized u/v -> pixel coords within the page
    const x = Math.round(U * window.innerWidth);
    const y = Math.round(V * window.innerHeight);

    cursor.style.left = `${x}px`;
    cursor.style.top = `${y}px`;
    cursor.classList.add('show');
  }

  // Tab clicks (works with forwarded DUI clicks)
  tabs.forEach(btn => {
    btn.addEventListener('click', () => {
      const p = (btn.dataset.page || '').toLowerCase();
      if (!p) return;
      setPage(p);
    });
  });

  // Receive messages from Lua via SendMessage()
  window.addEventListener('message', (e) => {
    const data = e.data || {};
    if (!data || typeof data !== 'object') return;

    if (data.type === 'status') {
      if (typeof data.speed !== 'undefined') state.speed = Number(data.speed) || 0;
      if (typeof data.gear !== 'undefined') state.gear = Number(data.gear) || 0;
      if (typeof data.engine !== 'undefined') state.engine = !!data.engine;
      render();
      return;
    }

    if (data.type === 'page') {
      if (typeof data.page === 'string') setPage(data.page);
      return;
    }

    if (data.type === 'dui_cursor') {
      setCursor(!!data.show, data.u, data.v);
      return;
    }

    // Optional: hello message (mode info) - ignore safely
  });

  // Initial
  setPage('all');
  render();
  setCursor(false, 0.5, 0.5);
})();
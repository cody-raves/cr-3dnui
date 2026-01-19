(() => {
  // If this page is accidentally loaded as an NUI overlay, hide it completely.
  // (DUI should render on the laptop screen only.)
  const isNuiOverlay = (typeof GetParentResourceName === 'function');
  if (isNuiOverlay) {
    document.documentElement.style.background = 'transparent';
    document.body.style.background = 'transparent';
    document.body.style.opacity = '0';
    return;
  }

  const log = document.getElementById('log');
  const status = document.getElementById('status');
  const cursor = document.getElementById('cursor');

  // =============================
  // Per-laptop state persistence
  // =============================
  // client.lua loads the UI as: index.html?lap=<id>
  // We persist state keyed by that id so each laptop "remembers" its UI.
  function getLapId(){
    try {
      const u = new URL(window.location.href);
      return u.searchParams.get('lap') || '0';
    } catch {
      return '0';
    }
  }
  const LAP_ID = getLapId();
  const STATE_KEY = `cr3d_laptop_state_${LAP_ID}`;

  const state = {
    filter: '',
    logText: ''
  };

  function saveState(){
    try {
      state.filter = document.body.style.filter || '';
      state.logText = log.textContent || '';
      localStorage.setItem(STATE_KEY, JSON.stringify(state));
    } catch {}
  }

  function loadState(){
    try {
      const raw = localStorage.getItem(STATE_KEY);
      if (!raw) return;
      const s = JSON.parse(raw);
      if (s && typeof s === 'object') {
        if (typeof s.filter === 'string') document.body.style.filter = s.filter;
        if (typeof s.logText === 'string') log.textContent = s.logText;
      }
    } catch {}
  }


  function add(msg){
    const t = new Date().toLocaleTimeString();
    log.textContent = `[${t}] ${msg}\n` + log.textContent;
    saveState();
  }

  // The FiveM DUI mouse-forwarding native produces real mouse events inside Chromium.
  // We render our own cursor element so you can see where the mouse is on the laptop.
  function showCursor(){
    if (cursor.style.display !== 'block') cursor.style.display = 'block';
  }
  function hideCursor(){
    cursor.style.display = 'none';
  }

  document.addEventListener('mousemove', (e) => {
    showCursor();
    cursor.style.left = `${e.clientX}px`;
    cursor.style.top = `${e.clientY}px`;
  }, { passive: true });

  document.addEventListener('mouseleave', () => {
    hideCursor();
  });

  // Buttons are just here to prove click routing.
  document.getElementById('btn1').addEventListener('click', () => add('PING clicked'));
  document.getElementById('btn2').addEventListener('click', () => {
    document.body.style.filter = (document.body.style.filter ? '' : 'hue-rotate(80deg)');
    saveState();
    add('SWAP clicked (hue rotate)');
  });
  document.getElementById('btn3').addEventListener('click', () => {
    try {
      const ctx = new (window.AudioContext || window.webkitAudioContext)();
      const o = ctx.createOscillator();
      const g = ctx.createGain();
      o.type = 'square';
      o.frequency.value = 880;
      g.gain.value = 0.02;
      o.connect(g);
      g.connect(ctx.destination);
      o.start();
      setTimeout(() => { o.stop(); ctx.close(); }, 90);
    } catch {}
    add('BEEP clicked');
  });

  // Restore per-laptop state before announcing readiness
  loadState();

  status.textContent = `UI ready (lap ${LAP_ID})`;
  add('UI ready (DUI)');
})();
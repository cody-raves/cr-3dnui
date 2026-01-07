const $ = (id) => document.getElementById(id);

function setEngine(on){
  const el = $('engine');
  el.textContent = on ? 'ENGINE' : 'OFF';
  el.style.opacity = on ? '1' : '0.55';
}

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.type === 'hello') {
    // nothing required; exists so the Lua side can ping the UI
    return;
  }

  if (d.type === 'status') {
    $('speed').textContent = (d.speed ?? 0).toString();
    $('gear').textContent = (d.gear === 0 ? 'N' : String(d.gear));
    $('interval').textContent = (d.interval ?? 33).toString();
    setEngine(!!d.engine);
  }

  if (d.type === 'key') {
    // If you enable /nuifocus, your library can forward keys as messages.
    // This makes it obvious input is reaching the DUI.
    if (d.key === 'E') {
      document.body.style.transform = 'scale(0.995)';
      setTimeout(() => document.body.style.transform = 'scale(1)', 60);
    }
  }
});

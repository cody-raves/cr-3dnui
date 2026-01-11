(() => {
  const canvas = document.getElementById('c');
  const ctx = canvas.getContext('2d', { alpha: true, desynchronized: true });

  // KEY2DUI: cursor drawn inside the DUI (the game cursor can be hidden)
  const duiCursor = document.getElementById('duiCursor');
  function setDuiCursor(u, v, show = true) {
    if (!duiCursor) return;
    if (!show) {
      duiCursor.style.display = 'none';
      return;
    }
    // Clamp & position as percentages
    const cu = Math.max(0, Math.min(1, Number(u) || 0));
    const cv = Math.max(0, Math.min(1, Number(v) || 0));
    duiCursor.style.left = (cu * 100).toFixed(3) + '%';
    duiCursor.style.top = (cv * 100).toFixed(3) + '%';
    duiCursor.style.display = 'block';
  }

  const ui = document.getElementById('ui');
  const paletteEl = document.getElementById('palette');
  const sizeEl = document.getElementById('size');
  const sizeLabel = document.getElementById('sizeLabel');

  const fontSizeEl = document.getElementById('fontSize');
  const textRow = document.getElementById('textRow');

  const fontFamilyRoot = document.getElementById('fontFamily');
  const fontFamilyBtn = document.getElementById('fontFamilyBtn');
  const fontFamilyMenu = document.getElementById('fontFamilyMenu');

  const colorPicker = document.getElementById('colorpicker');

  const clearBtn = document.getElementById('clear');
  const eraserBtn = document.getElementById('eraser');
  const textBtn = document.getElementById('text');

  const hintEl = document.getElementById('hint');

  const COLORS = [
    '#000000','#ffffff','#ef4444','#f59e0b','#22c55e',
    '#3b82f6','#a855f7','#ec4899','#06b6d4','#f97316'
  ];

  let color = '#000000';
  let size = parseInt(sizeEl.value, 10);
  let drawing = false;
  let last = null;
  let tool = 'brush';

  let fontFamilyValue = 'system-ui,Segoe UI,Roboto,Arial';
  let fontFamilyLabel = 'System';

  const RES_NAME =
    (typeof GetParentResourceName === 'function' && GetParentResourceName()) ||
    new URLSearchParams(window.location.search).get('res') ||
    null;

  function resize() {
    const dpr = window.devicePixelRatio || 1;
    const w = canvas.clientWidth;
    const h = canvas.clientHeight;
    canvas.width = Math.floor(w * dpr);
    canvas.height = Math.floor(h * dpr);
    ctx.setTransform(dpr,0,0,dpr,0,0);
  }

  window.addEventListener('resize', resize);
  resize();

  function showHint(msg, ms = 2500) {
    if (!msg) {
      hintEl.hidden = true;
      hintEl.textContent = '';
      return;
    }
    hintEl.hidden = false;
    hintEl.textContent = msg;
    if (ms > 0) {
      setTimeout(() => {
        if (hintEl.textContent === msg) showHint(null);
      }, ms);
    }
  }

  function setActiveSwatch(hex) {
    [...paletteEl.querySelectorAll('.swatch')]
      .forEach(s => s.classList.toggle('active', s.dataset.hex === hex));
  }

  function makeSwatches() {
    paletteEl.innerHTML = '';
    for (const hex of COLORS) {
      const d = document.createElement('div');
      d.className = 'swatch';
      d.dataset.hex = hex;
      d.style.background = hex;
      d.addEventListener('click', (e) => {
        e.stopPropagation();
        color = hex;
        colorPicker.value = hex;
        setTool('brush');
        setActiveSwatch(hex);
      });
      paletteEl.appendChild(d);
    }
    setActiveSwatch(color);
  }

  makeSwatches();

  function closeFontMenu() {
    fontFamilyMenu.hidden = true;
    fontFamilyBtn.classList.remove('active');
  }

  function openFontMenu() {
    fontFamilyMenu.hidden = false;
    fontFamilyBtn.classList.add('active');
  }

  function toggleFontMenu() {
    if (fontFamilyMenu.hidden) openFontMenu();
    else closeFontMenu();
  }

  function setFontFamily(label, value) {
    fontFamilyLabel = label;
    fontFamilyValue = value;
    fontFamilyBtn.textContent = label;

    [...fontFamilyMenu.querySelectorAll('.dd-item')].forEach(it => {
      it.classList.toggle('active', it.dataset.value === value);
    });
  }

  function setTool(next) {
    tool = next;

    eraserBtn.classList.toggle('active', tool === 'eraser');
    textBtn.classList.toggle('active', tool === 'text');

    if (tool === 'text') {
      textRow.hidden = false;
      sizeLabel.textContent = 'Brush';
      showHint('Text tool: click the board to place text, then type and press Enter. ESC cancels.', 4000);
    } else {
      textRow.hidden = true;
      closeFontMenu();
    }

    eraserBtn.textContent = (tool === 'eraser') ? 'Brush' : 'Eraser';
  }

  sizeEl.addEventListener('input', () => size = parseInt(sizeEl.value, 10));

  colorPicker.addEventListener('input', (e) => {
    color = e.target.value;
    setTool('brush');
    [...paletteEl.querySelectorAll('.swatch')].forEach(s => s.classList.remove('active'));
  });

  clearBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    ctx.clearRect(0,0,canvas.clientWidth,canvas.clientHeight);
  });

  eraserBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    setTool(tool === 'eraser' ? 'brush' : 'eraser');
  });

  textBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    setTool(tool === 'text' ? 'brush' : 'text');
  });

  fontFamilyMenu.hidden = true;

  fontFamilyBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    toggleFontMenu();
  });

  [...fontFamilyMenu.querySelectorAll('.dd-item')].forEach((it) => {
    it.addEventListener('click', (e) => {
      e.stopPropagation();
      const label = it.dataset.label || it.textContent || 'Font';
      const value = it.dataset.value || 'system-ui,Segoe UI,Roboto,Arial';
      setFontFamily(label, value);
      closeFontMenu();
    });
  });

  window.addEventListener('mousedown', (e) => {
    if (!fontFamilyMenu.hidden && !fontFamilyRoot.contains(e.target)) {
      closeFontMenu();
    }
  });

  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !fontFamilyMenu.hidden) {
      closeFontMenu();
    }
  }, true);

  setFontFamily(fontFamilyLabel, fontFamilyValue);

  function posFromEvent(ev) {
    const rect = canvas.getBoundingClientRect();
    return { x: ev.clientX - rect.left, y: ev.clientY - rect.top };
  }

  function stroke(from, to) {
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.lineWidth = size;

    if (tool === 'eraser') {
      ctx.globalCompositeOperation = 'destination-out';
      ctx.strokeStyle = 'rgba(0,0,0,1)';
    } else {
      ctx.globalCompositeOperation = 'source-over';
      ctx.strokeStyle = color;
    }

    ctx.beginPath();
    ctx.moveTo(from.x, from.y);
    ctx.lineTo(to.x, to.y);
    ctx.stroke();
  }

  async function requestTextAt(p) {
    if (!RES_NAME) {
      showHint('Text tool error: resource name not available.', 3500);
      return;
    }

    const payload = {
      x: p.x,
      y: p.y,
      color,
      size: parseInt(fontSizeEl.value, 10) || 24,
      font: fontFamilyValue || 'system-ui,Segoe UI,Roboto,Arial'
    };

    try {
      const resp = await fetch(`https://${RES_NAME}/wb_text_request`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload)
      });
      const json = await resp.json().catch(() => ({}));
      if (!json || json.ok !== true) {
        showHint('Text tool: could not start text entry (not in interact mode?)', 3500);
      } else {
        showHint('Typing... press Enter to place, ESC to cancel.', 3500);
      }
    } catch (e) {
      showHint('Text tool: NUI callback failed.', 3500);
    }
  }

  function drawText(d) {
    const x = Number(d.x) || 0;
    const y = Number(d.y) || 0;
    const txt = String(d.text || '');
    if (!txt) return;

    ctx.save();
    ctx.globalCompositeOperation = 'source-over';
    ctx.fillStyle = String(d.color || '#000000');
    const fontSize = Number(d.size) || 24;
    const fontFamily = String(d.font || 'system-ui,Segoe UI,Roboto,Arial');
    ctx.font = `${fontSize}px ${fontFamily}`;
    ctx.textBaseline = 'top';
    ctx.fillText(txt, x, y);
    ctx.restore();
  }

  window.addEventListener('message', (ev) => {
    const d = ev.data;
    if (!d || typeof d !== 'object') return;

	    // KEY2DUI cursor updates (visual only)
	    if (d.type === 'wb_cursor') {
	      setDuiCursor(d.u, d.v, d.show !== false);
	      return;
	    }
	    if (d.type === 'wb_cursor_hide') {
	      setDuiCursor(0.5, 0.5, false);
	      return;
	    }

    if (d.type === 'wb_text_commit') {
      drawText(d);
    } else if (d.type === 'wb_text_cancel') {
      showHint('Text canceled.', 1500);
    }
  });

  window.addEventListener('mousedown', (ev) => {
    if (ui.contains(ev.target)) return;

    const p = posFromEvent(ev);

    if (tool === 'text') {
      requestTextAt(p);
      drawing = false;
      last = null;
      return;
    }

    drawing = true;
    last = p;
  });

  window.addEventListener('mousemove', (ev) => {
    if (!drawing || !last) return;
    if (ui.contains(ev.target)) return;

    const p = posFromEvent(ev);
    stroke(last, p);
    last = p;
  });

  window.addEventListener('mouseup', () => {
    drawing = false;
    last = null;
  });

  setTool('brush');
})();

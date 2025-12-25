(() => {
  const canvas = document.getElementById("game");
  const ctx = canvas.getContext("2d");
  const scoreEl = document.getElementById("score");
  const highEl = document.getElementById("high");
  const lastEl = document.getElementById("last");

  const W = canvas.width;
  const H = canvas.height;
  const CELL = 16;
  const COLS = Math.floor(W / CELL);
  const ROWS = Math.floor(H / CELL);

  let high = 0;

  function randCell() {
    return { x: Math.floor(Math.random() * COLS), y: Math.floor(Math.random() * ROWS) };
  }

  let snake, dir, nextDir, food, score, alive, tickMs, acc;

  function reset() {
    snake = [{ x: Math.floor(COLS/2), y: Math.floor(ROWS/2) }];
    dir = { x: 1, y: 0 };
    nextDir = { x: 1, y: 0 };
    food = randCell();
    score = 0;
    alive = true;
    tickMs = 110;
    acc = 0;
    scoreEl.textContent = String(score);
    highEl.textContent = String(high);
    lastEl.textContent = "—";
  }

  function same(a,b){ return a.x===b.x && a.y===b.y; }

  function spawnFood() {
    let tries = 0;
    while (tries++ < 5000) {
      const c = randCell();
      if (!snake.some(s => same(s,c))) { food = c; return; }
    }
    food = randCell();
  }

  function setDir(nx, ny) {
    if (nx === -dir.x && ny === -dir.y) return;
    nextDir = { x: nx, y: ny };
  }

  function handleKeyLabel(label) {
    if (!label) return;
    lastEl.textContent = label;

    if (label === "R" || label === "SPACE") { reset(); return; }

    if (label === "W") return setDir(0,-1);
    if (label === "S") return setDir(0, 1);
    if (label === "A") return setDir(-1,0);
    if (label === "D") return setDir( 1,0);

    if (label === "UP") return setDir(0,-1);
    if (label === "DOWN") return setDir(0, 1);
    if (label === "LEFT") return setDir(-1,0);
    if (label === "RIGHT") return setDir( 1,0);
  }

  window.addEventListener("message", (e) => {
    const d = e.data;
    if (!d) return;
    if (d.type === "key") handleKeyLabel(d.key);
    if (d.type === "focus") lastEl.textContent = d.state ? "FOCUS" : "—";
  });

  function step() {
    if (!alive) return;

    dir = nextDir;
    const head = snake[0];
    const nh = { x: head.x + dir.x, y: head.y + dir.y };

    if (nh.x < 0) nh.x = COLS - 1;
    if (nh.x >= COLS) nh.x = 0;
    if (nh.y < 0) nh.y = ROWS - 1;
    if (nh.y >= ROWS) nh.y = 0;

    if (snake.some(s => same(s, nh))) { alive = false; return; }

    snake.unshift(nh);

    if (same(nh, food)) {
      score += 1;
      if (score > high) high = score;
      scoreEl.textContent = String(score);
      highEl.textContent = String(high);
      spawnFood();
      tickMs = Math.max(60, tickMs - 1);
    } else {
      snake.pop();
    }
  }

  function drawGrid() {
    ctx.globalAlpha = 0.20;
    for (let x = 0; x < COLS; x++) {
      for (let y = 0; y < ROWS; y++) {
        if ((x + y) % 2 === 0) ctx.fillRect(x * CELL, y * CELL, CELL, CELL);
      }
    }
    ctx.globalAlpha = 1.0;
  }

  function draw() {
    ctx.clearRect(0,0,W,H);
    ctx.fillStyle = "rgba(0,0,0,0.92)";
    ctx.fillRect(0,0,W,H);

    ctx.fillStyle = "rgba(0,255,153,0.12)";
    drawGrid();

    ctx.fillStyle = "rgba(0,255,153,0.95)";
    ctx.fillRect(food.x * CELL, food.y * CELL, CELL, CELL);

    for (let i = 0; i < snake.length; i++) {
      const s = snake[i];
      const a = i === 0 ? 1.0 : 0.85;
      ctx.fillStyle = `rgba(0,255,153,${a})`;
      ctx.fillRect(s.x * CELL, s.y * CELL, CELL, CELL);
    }

    if (!alive) {
      ctx.fillStyle = "rgba(0,0,0,0.65)";
      ctx.fillRect(0,0,W,H);
      ctx.fillStyle = "rgba(0,255,153,1.0)";
      ctx.textAlign = "center";
      ctx.font = "28px ui-monospace, monospace";
      ctx.fillText("Game Over", W/2, H/2 - 10);
      ctx.font = "16px ui-monospace, monospace";
      ctx.fillText("Press R (or SPACE) to restart", W/2, H/2 + 22);
    }
  }

  let last = performance.now();
  function loop(now) {
    const dt = now - last;
    last = now;
    acc += dt;
    while (acc >= tickMs) { step(); acc -= tickMs; }
    draw();
    requestAnimationFrame(loop);
  }

  reset();
  requestAnimationFrame(loop);
})();

'use strict';
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { createApp } = require('./server');

let server;
let base;

before(async () => {
  server = createApp();
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => new Promise((resolve) => server.close(resolve)));

test('GET /api/health responde 200 ok', async () => {
  const res = await fetch(`${base}/api/health`);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { status: 'ok' });
});

test('GET /api/info expone version y hostname', async () => {
  const body = await (await fetch(`${base}/api/info`)).json();
  assert.equal(body.service, 'backend');
  assert.ok(body.version);
  assert.ok(body.hostname);
});

test('POST /api/tasks crea una tarea y GET la lista', async () => {
  const created = await fetch(`${base}/api/tasks`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title: 'Preparar la demo' }),
  });
  assert.equal(created.status, 201);
  const task = await created.json();
  assert.equal(task.title, 'Preparar la demo');

  const list = await (await fetch(`${base}/api/tasks`)).json();
  assert.ok(list.some((t) => t.id === task.id));
});

test('POST /api/tasks rechaza un titulo vacio con 400', async () => {
  const res = await fetch(`${base}/api/tasks`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title: '   ' }),
  });
  assert.equal(res.status, 400);
});

test('DELETE /api/tasks/:id borra la tarea con 204 y ya no aparece en la lista', async () => {
  const created = await fetch(`${base}/api/tasks`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title: 'Tarea para borrar' }),
  });
  const task = await created.json();

  const res = await fetch(`${base}/api/tasks/${task.id}`, { method: 'DELETE' });
  assert.equal(res.status, 204);

  const list = await (await fetch(`${base}/api/tasks`)).json();
  assert.ok(!list.some((t) => t.id === task.id));
});

test('DELETE /api/tasks/:id responde 404 si la tarea no existe o el id no es numerico', async () => {
  const missing = await fetch(`${base}/api/tasks/99999`, { method: 'DELETE' });
  assert.equal(missing.status, 404);
  const invalid = await fetch(`${base}/api/tasks/abc`, { method: 'DELETE' });
  assert.equal(invalid.status, 404);
});

test('una ruta desconocida responde 404', async () => {
  const res = await fetch(`${base}/api/nada`);
  assert.equal(res.status, 404);
});

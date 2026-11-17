'use strict';
// Backend de la demo: API REST minima, SIN dependencias externas.
// (Solo modulos nativos de Node: menos superficie de ataque y cero "npm install".)

const http = require('node:http');
const os = require('node:os');

const PORT = Number(process.env.PORT || 3000);
const VERSION = process.env.APP_VERSION || 'dev'; // lo inyecta el Dockerfile (SHA del commit)
const APP_ENV = process.env.APP_ENV || 'local';
const MAX_BODY_BYTES = 10_000;

function send(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(payload),
  });
  res.end(payload);
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        reject(Object.assign(new Error('Cuerpo demasiado grande'), { status: 413 }));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'));
      } catch {
        reject(Object.assign(new Error('JSON invalido'), { status: 400 }));
      }
    });
    req.on('error', reject);
  });
}

function createApp() {
  // Estado EN MEMORIA: cada contenedor tiene su propia lista. Es suficiente para
  // la demo; una app real guardaria los datos en una base de datos (RDS/DynamoDB).
  const tasks = [
    { id: 1, title: 'Aprovisionar la infraestructura con Terraform', done: true },
    { id: 2, title: 'Publicar imagenes en Amazon ECR', done: true },
    { id: 3, title: 'Desplegar en ECS Fargate', done: true },
  ];
  let nextId = 4;
  const startedAt = Date.now();

  return http.createServer(async (req, res) => {
    const { pathname } = new URL(req.url, 'http://localhost');

    try {
      // Usado por el health check del ALB: si no responde 200, el ALB deja de enviarle trafico.
      if (req.method === 'GET' && pathname === '/api/health') {
        return send(res, 200, { status: 'ok' });
      }

      if (req.method === 'GET' && pathname === '/api/info') {
        return send(res, 200, {
          service: 'backend',
          version: VERSION,
          env: APP_ENV,
          hostname: os.hostname(), // identifica QUE contenedor respondio
          uptime_seconds: Math.round((Date.now() - startedAt) / 1000),
        });
      }

      if (req.method === 'GET' && pathname === '/api/tasks') {
        return send(res, 200, tasks);
      }

      if (req.method === 'POST' && pathname === '/api/tasks') {
        const body = await readJson(req);
        const title = typeof body.title === 'string' ? body.title.trim() : '';
        if (title.length < 1 || title.length > 120) {
          return send(res, 400, { error: 'title es obligatorio (1 a 120 caracteres)' });
        }
        const task = { id: nextId++, title, done: false };
        tasks.push(task);
        return send(res, 201, task);
      }

      return send(res, 404, { error: 'No encontrado' });
    } catch (err) {
      return send(res, err.status || 500, { error: err.message || 'Error interno' });
    }
  });
}

module.exports = { createApp };

if (require.main === module) {
  const server = createApp();
  server.listen(PORT, '0.0.0.0', () => {
    console.log(JSON.stringify({ msg: 'backend escuchando', port: PORT, version: VERSION, env: APP_ENV }));
  });

  // ECS envia SIGTERM al reemplazar una tarea: cerramos con elegancia
  // para no cortar peticiones en curso.
  process.on('SIGTERM', () => {
    console.log(JSON.stringify({ msg: 'SIGTERM recibido, cerrando' }));
    server.close(() => process.exit(0));
  });
}

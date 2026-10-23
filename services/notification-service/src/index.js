const http = require('http');
const jwt = require('jsonwebtoken');
const { Server } = require('socket.io');

const mq = require('./mq');

if (!process.env.JWT_SECRET) { console.error('JWT_SECRET is required'); process.exit(1); }
const SECRET = process.env.JWT_SECRET;

// Plain HTTP handler for the gateway health probe. Socket.IO takes over /socket.io itself.
const server = http.createServer((req, res) => {
  if (req.url === '/api/notify/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end('{"status":"ok"}');
    return;
  }
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end('{"error":"Not found"}');
});

const io = new Server(server, { path: '/socket.io', serveClient: false });

// Only logged-in users may connect. The JWT arrives in the handshake.
io.use((socket, next) => {
  const token = socket.handshake.auth && socket.handshake.auth.token;
  try {
    const p = jwt.verify(token || '', SECRET, { algorithms: ['HS256'] });
    socket.data.userId = Number(p.sub);
    next();
  } catch {
    next(new Error('unauthorized'));
  }
});

// Each user joins a private room, so people only receive their own orders.
io.on('connection', (socket) => {

  socket.join(`user:${socket.data.userId}`);
  socket.emit('ready', { userId: socket.data.userId });
});

server.listen(process.env.PORT || 8080, () => console.log('notification-service listening'));

mq.start((routingKey, evt) => {
  if (!Number.isInteger(evt.userId) || !Number.isInteger(evt.orderId)) throw new Error('unexpected event');
  io.to(`user:${evt.userId}`).emit('order:update', {
    event: routingKey,
    orderId: evt.orderId,
    status: evt.status,
    reason: evt.reason || '',
  });
}).catch((e) => { console.error(e); process.exit(1); });

const stop = () => io.close(() => process.exit(0));
process.on('SIGTERM', stop);
process.on('SIGINT', stop);

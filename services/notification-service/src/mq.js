const amqp = require('amqplib');

const EXCHANGE = 'shop.events';
const QUEUE = 'notify.events';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function url() {
  const u = encodeURIComponent(process.env.RABBITMQ_USER || 'guest');
  const p = encodeURIComponent(process.env.RABBITMQ_PASS || 'guest');
  return `amqp://${u}:${p}@${process.env.RABBITMQ_HOST || 'localhost'}:${process.env.RABBITMQ_PORT || 5672}`;
}

async function start(onEvent) {

  let conn;
  for (let i = 0; i < 40; i++) {
    try { conn = await amqp.connect(url()); break; }
    catch { console.log('RabbitMQ not ready, retrying in 3s...'); await sleep(3000); }
  }
  if (!conn) throw new Error('RabbitMQ unreachable');
  conn.on('error', (e) => console.error('RabbitMQ error:', e.message));
  conn.on('close', () => { console.error('RabbitMQ closed'); process.exit(1); });

  const channel = await conn.createChannel();
  await channel.assertExchange(EXCHANGE, 'topic', { durable: true });
  await channel.assertQueue(QUEUE, { durable: true });
  await channel.bindQueue(QUEUE, EXCHANGE, 'order.*'); // sees order.created and order.processed
  await channel.consume(QUEUE, (msg) => {
    if (!msg) return;
    try {
      onEvent(msg.fields.routingKey, JSON.parse(msg.content.toString()));
      channel.ack(msg);
    } catch (err) {
      console.error('Bad event:', err.message);
      channel.nack(msg, false, false);
    }
  });
  console.log('RabbitMQ ready');
}

module.exports = { start };

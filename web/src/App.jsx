import { useCallback, useEffect, useRef, useState } from 'react';
import { io } from 'socket.io-client';
import { api, session, money, ApiError } from './api.js';

const STATUS_LABEL = { PENDING: 'Processing', PAID: 'Paid', FAILED: 'Failed' };

export default function App() {
  const [user, setUser] = useState(session.user);
  const [notice, setNotice] = useState('');

  const logout = useCallback(() => {
    session.clear();
    setUser(null);
  }, []);

  useEffect(() => {
    if (!notice) return undefined;
    const t = setTimeout(() => setNotice(''), 4000);
    return () => clearTimeout(t);
  }, [notice]);

  function onAuth(res) {
    session.save(res.token, res.user);
    setUser(res.user);
  }

  return (

    <div className="app">
      <header className="top">
        <h1>ShopLite</h1>
        {user && (
          <div className="who">
            <span>{user.name}</span>
            <button className="link" onClick={logout}>Log out</button>
          </div>
        )}
      </header>
      {notice && <div className="toast" role="status">{notice}</div>}
      {user ? <Shop onNotice={setNotice} onLogout={logout} /> : <AuthForm onAuth={onAuth} />}
    </div>
  );
}

function AuthForm({ onAuth }) {
  const [mode, setMode] = useState('login');
  const [form, setForm] = useState({ email: '', name: '', password: '' });
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const set = (key) => (e) => setForm({ ...form, [key]: e.target.value });

  async function submit(e) {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      const body = mode === 'login' ? { email: form.email, password: form.password } : form;
      onAuth(await api(`/api/auth/${mode}`, { method: 'POST', body }));
    } catch (err) {
      setError(err.message);

    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="card auth">
      <h2>{mode === 'login' ? 'Welcome back' : 'Create your account'}</h2>
      <form onSubmit={submit}>
        {mode === 'register' && (
          <label>
            Name
            <input value={form.name} onChange={set('name')} maxLength={60} autoComplete="name" required />
          </label>
        )}
        <label>
          Email
          <input type="email" value={form.email} onChange={set('email')} autoComplete="email" required />
        </label>
        <label>
          Password
          <input
            type="password"
            value={form.password}
            onChange={set('password')}
            minLength={8}
            maxLength={72}
            autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
            required
          />
        </label>
        {error && <p className="error" role="alert">{error}</p>}

        <button className="primary" type="submit" disabled={busy}>
          {busy ? 'Please wait...' : mode === 'login' ? 'Log in' : 'Sign up'}
        </button>
      </form>
      <button
        className="link"
        onClick={() => {
          setMode(mode === 'login' ? 'register' : 'login');
          setError('');
        }}
      >
        {mode === 'login' ? 'New here? Create an account' : 'Have an account? Log in'}
      </button>
    </main>
  );
}

function Shop({ onNotice, onLogout }) {
  const [view, setView] = useState('shop');
  const [products, setProducts] = useState([]);
  const [categories, setCategories] = useState([]);
  const [category, setCategory] = useState('');
  const [q, setQ] = useState('');
  const [cart, setCart] = useState({});
  const [orders, setOrders] = useState([]);
  const [error, setError] = useState('');
  const ordersRef = useRef([]);

  useEffect(() => {
    ordersRef.current = orders;
  }, [orders]);


  // A 401 means the login expired: go back to the login screen.
  const guard = useCallback((err) => {
    if (err instanceof ApiError && err.status === 401) {
      onLogout();
      return;
    }
    setError(err.message);
  }, [onLogout]);

  const loadOrders = useCallback(() => api('/api/checkout/orders').then(setOrders).catch(guard), [guard]);

  useEffect(() => {
    api('/api/catalogue/categories').then(setCategories).catch(guard);
    loadOrders();
  }, [guard, loadOrders]);

  useEffect(() => {
    const params = new URLSearchParams();
    if (q.trim()) params.set('q', q.trim());
    if (category) params.set('category', category);
    const t = setTimeout(() => {
      api(`/api/catalogue/products?${params}`)
        .then((list) => {
          setProducts(list);
          setError('');
        })
        .catch(guard);
    }, 250);
    return () => clearTimeout(t);
  }, [q, category, guard]);

  // Live order updates pushed by the notification service.

  useEffect(() => {
    const socket = io({ path: '/socket.io', auth: { token: session.token } });
    socket.on('order:update', (u) => {
      if (!ordersRef.current.some((o) => o.id === u.orderId)) {
        loadOrders();
      } else {
        setOrders((prev) => prev.map((o) => (o.id === u.orderId ? { ...o, status: u.status, reason: u.reason } : o)));
      }
      if (u.status === 'PAID') onNotice(`Order #${u.orderId} paid`);
      if (u.status === 'FAILED') onNotice(`Order #${u.orderId} failed${u.reason ? `: ${u.reason}` : ''}`);
    });
    socket.on('connect_error', (e) => {
      if (e.message === 'unauthorized') onLogout();
    });
    return () => socket.close();
  }, [loadOrders, onNotice, onLogout]);

  const add = (p) =>
    setCart((c) => ({ ...c, [p.id]: { product: p, qty: Math.min(20, (c[p.id] ? c[p.id].qty : 0) + 1) } }));

  const change = (id, delta) =>
    setCart((c) => {
      const line = c[id];
      if (!line) return c;
      const qty = line.qty + delta;
      const next = { ...c };
      if (qty <= 0) delete next[id];
      else next[id] = { ...line, qty: Math.min(20, qty) };
      return next;
    });

  const lines = Object.values(cart);

  const count = lines.reduce((n, l) => n + l.qty, 0);
  const total = lines.reduce((n, l) => n + l.qty * l.product.priceCents, 0);

  async function placeOrder() {
    try {
      const order = await api('/api/checkout/orders', {
        method: 'POST',
        body: { items: lines.map((l) => ({ productId: l.product.id, quantity: l.qty })) },
      });
      setCart({});
      setOrders((prev) => (prev.some((o) => o.id === order.id) ? prev : [order, ...prev]));
      onNotice('Order placed. Payment is being processed...');
      setView('orders');
    } catch (err) {
      guard(err);
    }
  }

  return (
    <>
      <nav className="tabs">
        <button className={view === 'shop' ? 'on' : ''} onClick={() => setView('shop')}>Shop</button>
        <button className={view === 'cart' ? 'on' : ''} onClick={() => setView('cart')}>Cart{count > 0 ? ` (${count})` : ''}</button>
        <button className={view === 'orders' ? 'on' : ''} onClick={() => setView('orders')}>Orders</button>
      </nav>
      {error && <p className="error" role="alert">{error}</p>}

      {view === 'shop' && (
        <section>
          <div className="filters">
            <input type="search" placeholder="Search products" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Search products" />
            <select value={category} onChange={(e) => setCategory(e.target.value)} aria-label="Category">

              <option value="">All categories</option>
              {categories.map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
          </div>
          {products.length === 0 ? (
            <p className="empty">No products found.</p>
          ) : (
            <ul className="grid">
              {products.map((p) => (
                <li key={p.id} className="card product">
                  <span className="emoji" aria-hidden="true">{p.emoji}</span>
                  <h3>{p.name}</h3>
                  <p className="muted">{p.description}</p>
                  <div className="row">
                    <strong>{money(p.priceCents)}</strong>
                    <button className="primary small" onClick={() => add(p)}>Add</button>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </section>
      )}

      {view === 'cart' && (
        <section className="card">
          {lines.length === 0 ? (
            <p className="empty">Your cart is empty.</p>
          ) : (
            <>
              <ul className="lines">
                {lines.map((l) => (

                  <li key={l.product.id}>
                    <span className="emoji" aria-hidden="true">{l.product.emoji}</span>
                    <div className="grow">
                      <strong>{l.product.name}</strong>
                      <span className="muted">{money(l.product.priceCents)} each</span>
                    </div>
                    <div className="qty">
                      <button onClick={() => change(l.product.id, -1)} aria-label={`Remove one ${l.product.name}`}>-</button>
                      <span>{l.qty}</span>
                      <button onClick={() => change(l.product.id, 1)} aria-label={`Add one ${l.product.name}`}>+</button>
                    </div>
                  </li>
                ))}
              </ul>
              <div className="row total">
                <span>Total</span>
                <strong>{money(total)}</strong>
              </div>
              <button className="primary" onClick={placeOrder}>Place order</button>
            </>
          )}
        </section>
      )}

      {view === 'orders' && (
        <section>
          {orders.length === 0 ? (
            <p className="empty">No orders yet.</p>
          ) : (
            <ul className="orders">
              {orders.map((o) => (
                <li key={o.id} className="card">

                  <div className="row">
                    <strong>Order #{o.id}</strong>
                    <span className={`pill ${o.status.toLowerCase()}`}>{STATUS_LABEL[o.status] || o.status}</span>
                  </div>
                  <ul className="items">
                    {o.items.map((i) => (
                      <li key={`${o.id}-${i.productId}`}>{i.quantity} x {i.name}</li>
                    ))}
                  </ul>
                  <div className="row">
                    <span className="muted">{o.status === 'FAILED' && o.reason ? o.reason : new Date(o.createdAt).toLocaleString()}</span>
                    <strong>{money(o.totalCents)}</strong>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </section>
      )}
    </>
  );
}

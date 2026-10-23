import 'package:flutter/material.dart';

import 'models.dart';
import 'state.dart';

// Shows the pending message once, then clears it.
void showPendingMessage(BuildContext context) {
  final m = app.message;
  if (m == null) return;
  app.message = null;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  });
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;


  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    await app.authenticate(
      register: _register,
      email: _email.text.trim(),
      password: _password.text,
      name: _name.text.trim(),
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    showPendingMessage(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(

                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'ShopLite',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(_register ? 'Create your account' : 'Welcome back', textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    if (_register) ...[
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                      validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),

                      validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(_busy ? 'Please wait...' : (_register ? 'Sign up' : 'Log in')),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _register = !_register),
                      child: Text(_register ? 'Have an account? Log in' : 'New here? Create an account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;


  @override
  Widget build(BuildContext context) {
    showPendingMessage(context);
    final pages = <Widget>[ShopPage(), CartPage(), OrdersPage()];
    return Scaffold(
      appBar: AppBar(
        title: const Text('ShopLite'),
        actions: [
          Center(child: Text(app.userName ?? '')),
          IconButton(tooltip: 'Log out', icon: const Icon(Icons.logout), onPressed: app.logout),
        ],
      ),
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.storefront_outlined), label: 'Shop'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: app.cartCount > 0,
              label: Text('${app.cartCount}'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
            label: 'Cart',
          ),
          const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
        ],
      ),
    );
  }
}


class ShopPage extends StatefulWidget {
  const ShopPage({super.key});

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search products',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),

                onPressed: () {
                  _search.clear();
                  app.setQuery('');
                },
              ),
            ),
            onSubmitted: app.setQuery,
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('All'),
                  selected: app.category == null,
                  onSelected: (_) => app.setCategory(null),
                ),
              ),
              for (final c in app.categories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c),
                    selected: app.category == c,
                    onSelected: (_) => app.setCategory(c),
                  ),
                ),

            ],
          ),
        ),
        Expanded(
          child: app.products.isEmpty
              ? const Center(child: Text('No products found'))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: app.products.length,
                  itemBuilder: (context, i) {
                    final p = app.products[i];
                    return Card(
                      child: ListTile(
                        leading: Text(p.emoji, style: const TextStyle(fontSize: 32)),
                        title: Text(p.name),
                        subtitle: Text('${p.description}\n${money(p.priceCents)}'),
                        isThreeLine: true,
                        trailing: FilledButton(onPressed: () => app.addToCart(p), child: const Text('Add')),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override

  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  bool _busy = false;

  Future<void> _place() async {
    setState(() => _busy = true);
    await app.checkout();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final lines = app.cart.values.toList();
    if (lines.isEmpty) return const Center(child: Text('Your cart is empty'));
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: lines.length,
            separatorBuilder: (context, i) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final l = lines[i];
              return ListTile(
                leading: Text(l.product.emoji, style: const TextStyle(fontSize: 30)),
                title: Text(l.product.name),
                subtitle: Text('${money(l.product.priceCents)} each'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(

                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => app.changeQty(l.product.id, -1),
                    ),
                    Text('${l.quantity}'),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => app.changeQty(l.product.id, 1),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: TextStyle(fontSize: 18)),
                  Text(money(app.cartTotal), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _place,
                  child: Text(_busy ? 'Placing order...' : 'Place order'),
                ),

              ),
            ],
          ),
        ),
      ],
    );
  }
}

class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = app.orders;
    return RefreshIndicator(
      onRefresh: app.loadOrders,
      child: orders.isEmpty
          ? ListView(children: const [SizedBox(height: 120), Center(child: Text('No orders yet'))])
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: orders.length,
              itemBuilder: (context, i) => _OrderCard(order: orders[i]),
            ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Order order;

  const _OrderCard({required this.order});


  Color _color() {
    if (order.status == 'PAID') return Colors.green.shade700;
    if (order.status == 'FAILED') return Colors.red.shade700;
    return Colors.orange.shade800;
  }

  String _label() {
    if (order.status == 'PAID') return 'Paid';
    if (order.status == 'FAILED') return 'Failed';
    return 'Processing';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Order #${order.id}', style: const TextStyle(fontWeight: FontWeight.w700)),
                Chip(
                  label: Text(_label(), style: const TextStyle(color: Colors.white)),
                  backgroundColor: _color(),
                  side: BorderSide.none,
                ),
              ],
            ),

            for (final item in order.items) Text('${item.quantity} x ${item.name}'),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    order.status == 'FAILED' && order.reason.isNotEmpty
                        ? order.reason
                        : order.createdAt.toLocal().toString().split('.').first,
                  ),
                ),
                Text(money(order.totalCents), style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

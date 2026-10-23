import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api.dart';
import 'models.dart';

// All screens read from this one object and rebuild when it changes.
class AppState extends ChangeNotifier {

  final Api api = Api();
  bool ready = false;
  String? userName;
  List<Product> products = [];
  List<String> categories = [];
  String query = '';
  String? category;
  final Map<int, CartLine> cart = {};
  List<Order> orders = [];
  String? message; // shown once as a SnackBar
  io.Socket? _socket;

  bool get loggedIn => api.token != null;
  int get cartCount => cart.values.fold(0, (sum, l) => sum + l.quantity);
  int get cartTotal => cart.values.fold(0, (sum, l) => sum + l.quantity * l.product.priceCents);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    api.token = prefs.getString('token');
    userName = prefs.getString('name');
    ready = true;
    notifyListeners();
    if (loggedIn) {
      await refreshAll();
      _connectSocket();
    }
  }

  // Runs a request. Shows a message on failure and logs out when the login has expired.
  Future<dynamic> _run(Future<dynamic> Function() request) async {
    try {
      return await request();

    } on ApiException catch (e) {
      if (e.status == 401 && loggedIn) {
        await logout();
        message = 'Please log in again.';
      } else {
        message = e.message;
      }
    } catch (_) {
      message = 'Cannot reach the server.';
    }
    notifyListeners();
    return null;
  }

  Future<bool> authenticate({
    required bool register,
    required String email,
    required String password,
    String name = '',
  }) async {
    final body = register
        ? {'email': email, 'name': name, 'password': password}
        : {'email': email, 'password': password};
    final r = await _run(() => api.post(register ? '/api/auth/register' : '/api/auth/login', body));
    if (r == null) return false;
    final token = r['token'] as String;
    api.token = token;
    userName = (r['user'] as Map)['name'] as String;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('name', userName!);
    notifyListeners();

    await refreshAll();
    _connectSocket();
    return true;
  }

  Future<void> logout() async {
    _socket?.dispose();
    _socket = null;
    api.token = null;
    userName = null;
    cart.clear();
    orders = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('name');
    notifyListeners();
  }

  Future<void> refreshAll() async {
    await loadCategories();
    await loadProducts();
    await loadOrders();
  }

  Future<void> loadCategories() async {
    final r = await _run(() => api.get('/api/catalogue/categories'));
    if (r == null) return;
    categories = List<String>.from(r as List);
    notifyListeners();
  }

  Future<void> loadProducts() async {

    final q = <String, String>{};
    if (query.trim().isNotEmpty) q['q'] = query.trim();
    if (category != null) q['category'] = category!;
    final r = await _run(() => api.get('/api/catalogue/products', q.isEmpty ? null : q));
    if (r == null) return;
    products = (r as List).map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
    notifyListeners();
  }

  Future<void> loadOrders() async {
    final r = await _run(() => api.get('/api/checkout/orders'));
    if (r == null) return;
    orders = (r as List).map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
    notifyListeners();
  }

  void setQuery(String value) {
    query = value;
    loadProducts();
  }

  void setCategory(String? value) {
    category = value;
    notifyListeners();
    loadProducts();
  }

  void addToCart(Product p) {
    final line = cart[p.id];
    if (line == null) {
      cart[p.id] = CartLine(p, 1);
    } else if (line.quantity < 20) {

      line.quantity++;
    }
    notifyListeners();
  }

  void changeQty(int productId, int delta) {
    final line = cart[productId];
    if (line == null) return;
    line.quantity += delta;
    if (line.quantity <= 0) cart.remove(productId);
    if (line.quantity > 20) line.quantity = 20;
    notifyListeners();
  }

  Future<bool> checkout() async {
    if (cart.isEmpty) return false;
    final items = cart.values.map((l) => {'productId': l.product.id, 'quantity': l.quantity}).toList();
    final r = await _run(() => api.post('/api/checkout/orders', {'items': items}));
    if (r == null) return false;
    final order = Order.fromJson(r as Map<String, dynamic>);
    cart.clear();
    if (!orders.any((o) => o.id == order.id)) orders.insert(0, order);
    message = 'Order placed. Payment is being processed...';
    notifyListeners();
    return true;
  }

  // Live updates from the notification service.
  void _connectSocket() {
    _socket?.dispose();
    final socket = io.io(
      kBaseUrl,

      io.OptionBuilder()
          .setTransports(['websocket'])
          .setPath('/socket.io')
          .setAuth({'token': api.token})
          .disableAutoConnect()
          .build(),
    );
    socket.on('order:update', _onOrderUpdate);
    socket.connect();
    _socket = socket;
  }

  void _onOrderUpdate(dynamic data) {
    if (data is! Map) return;
    final id = data['orderId'];
    final status = data['status'];
    if (id is! int || status is! String) return;
    final index = orders.indexWhere((o) => o.id == id);
    if (index == -1) {
      loadOrders();
      return;
    }
    orders[index].status = status;
    orders[index].reason = (data['reason'] as String?) ?? '';
    if (status == 'PAID') message = 'Order #$id paid';
    if (status == 'FAILED') message = 'Order #$id failed';
    notifyListeners();
  }
}

final AppState app = AppState();

String money(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

class Product {
  final int id;
  final String name;
  final String description;
  final int priceCents;

  final String category;
  final String emoji;

  Product({
    required this.id,
    required this.name,
    required this.description,
    required this.priceCents,
    required this.category,
    required this.emoji,
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as int,
        name: j['name'] as String,
        description: j['description'] as String,
        priceCents: j['priceCents'] as int,
        category: j['category'] as String,
        emoji: j['emoji'] as String,
      );
}

class CartLine {
  final Product product;
  int quantity;

  CartLine(this.product, this.quantity);
}

class OrderItem {
  final String name;
  final int quantity;


  OrderItem(this.name, this.quantity);
}

class Order {
  final int id;
  final int totalCents;
  final DateTime createdAt;
  final List<OrderItem> items;
  String status;
  String reason;

  Order({
    required this.id,
    required this.totalCents,
    required this.createdAt,
    required this.items,
    required this.status,
    required this.reason,
  });

  factory Order.fromJson(Map<String, dynamic> j) => Order(
        id: j['id'] as int,
        totalCents: j['totalCents'] as int,
        createdAt: DateTime.parse(j['createdAt'] as String),
        status: j['status'] as String,
        reason: (j['reason'] as String?) ?? '',
        items: (j['items'] as List)
            .map((e) => OrderItem(e['name'] as String, e['quantity'] as int))
            .toList(),
      );
}


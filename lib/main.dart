import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/* =======================
    Sabitler
    ======================= */
// LÜTFEN BU IP ADRESİNİ KENDİ YAZICINIZIN IP ADRESİYLE DEĞİŞTİRİN
const String PRINTER_IP = '192.168.1.1'; // <-- Epson yazıcının IP'si
const int PRINTER_PORT = 9100; // Genelde 9100 (RAW)

const String _ADMIN_PIN = '6538';

/* =======================
    ENTRY
    ======================= */
Future<void> main() async {
  // Flutter motorunun uygulama çalışmadan önce hazır olduğundan emin ol.
  WidgetsFlutterBinding.ensureInitialized();
  final appState = AppState();
  await appState.loadSettings(); // Ayarların yüklenmesini bekle
  runApp(AppScope(notifier: appState, child: const App()));
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BISCORNUE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const Home(),
    );
  }
}

/* =======================
    MODELLER & STATE
    ======================= */
class Product {
  String name;
  final List<OptionGroup> groups;
  Product({required this.name, List<OptionGroup>? groups})
      : groups = groups ?? [];
  double priceForSelection(Map<String, List<OptionItem>> picked) {
    double total = 0;
    for (final g in groups) {
      final list = picked[g.id] ?? const [];
      for (final it in list) total += it.price;
    }
    return total;
  }
}

class OptionGroup {
  final String id;
  String title;
  bool multiple; // false=tek, true=çoklu
  int minSelect;
  int maxSelect;
  final List<OptionItem> items;
  OptionGroup({
    required this.id,
    required this.title,
    required this.multiple,
    required this.minSelect,
    required this.maxSelect,
    List<OptionItem>? items,
  }) : items = items ?? [];
}

class OptionItem {
  final String id;
  String label;
  double price;
  OptionItem({required this.id, required this.label, required this.price});
}

class CartLine {
  final Product product;
  final Map<String, List<OptionItem>> picked; // deep copy saklı
  CartLine({required this.product, required this.picked});
  double get total => product.priceForSelection(picked);
}

class SavedOrder {
  final String id;
  final DateTime createdAt;
  final DateTime readyAt;
  final List<CartLine> lines;
  final String customer;

  SavedOrder({
    required this.id,
    required this.createdAt,
    required this.readyAt,
    required this.lines,
    required this.customer,
  });
  double get total => lines.fold(0.0, (s, l) => s + l.total);
}

class AppState extends ChangeNotifier {
  final List<Product> products = [];
  final List<CartLine> cart = [];
  final List<SavedOrder> orders = [];
  int prepMinutes = 5;

  Future<void> loadSettings() async {
    final sp = await SharedPreferences.getInstance();
    prepMinutes = sp.getInt('prepMinutes') ?? 5;
    notifyListeners();
  }

  Future<void> setPrepMinutes(int m) async {
    prepMinutes = m;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('prepMinutes', m);
    notifyListeners();
  }

  void addProduct(Product p) {
    products.add(p);
    notifyListeners();
  }

  void replaceProductAt(int i, Product p) {
    products[i] = p;
    notifyListeners();
  }

  void addLineToCart(Product p, Map<String, List<OptionItem>> picked) {
    final deep = {
      for (final e in picked.entries) e.key: List<OptionItem>.from(e.value)
    };
    cart.add(CartLine(product: p, picked: deep));
    notifyListeners();
  }

  void removeCartLineAt(int i) {
    if (i >= 0 && i < cart.length) {
      cart.removeAt(i);
      notifyListeners();
    }
  }

  void clearCart() {
    cart.clear();
    notifyListeners();
  }

  void updateCartLineAt(int i, Map<String, List<OptionItem>> picked) {
    if (i < 0 || i >= cart.length) return;
    final deep = {
      for (final e in picked.entries) e.key: List<OptionItem>.from(e.value)
    };
    final p = cart[i].product;
    cart[i] = CartLine(product: p, picked: deep);
    notifyListeners();
  }

  void finalizeCartToOrder({required String customer}) {
    if (cart.isEmpty) return;
    final deepLines = cart
        .map((l) => CartLine(
              product: l.product,
              picked: {
                for (final e in l.picked.entries)
                  e.key: List<OptionItem>.from(e.value)
              },
            ))
        .toList();

    final now = DateTime.now();
    final ready = now.add(Duration(minutes: prepMinutes));

    orders.add(SavedOrder(
      id: now.millisecondsSinceEpoch.toString(),
      createdAt: now,
      readyAt: ready,
      lines: deepLines,
      customer: customer,
    ));
    cart.clear();
    notifyListeners();
  }

  void clearOrders() {
    orders.clear();
    notifyListeners();
  }
}

/* InheritedNotifier: global state erişimi */
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({required AppState notifier, required Widget child, Key? key})
      : super(key: key, notifier: notifier, child: child);
  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope bulunamadı.');
    return scope!.notifier!;
  }
}

/* =======================
    HOME (4 sekme)
    ======================= */
class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  bool _seeded = false;
  int index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;

    final app = AppScope.of(context);
    if (app.products.isEmpty) {
      final products = <Product>[
        Product(name: 'Sandwich', groups: [
          OptionGroup(
            id: 'type_sand',
            title: 'Sandwich',
            multiple: false,
            minSelect: 1,
            maxSelect: 1,
            items: [
              OptionItem(id: 'kebab', label: 'Kebab', price: 8.90),
              OptionItem(id: 'poulet', label: 'Poulet', price: 8.90),
              OptionItem(id: 'steak', label: 'Steak hache', price: 8.90),
              OptionItem(id: 'vege', label: 'Vegetarien', price: 8.90),
              OptionItem(id: 'berlineur', label: 'Berlineur', price: 10.90),
            ],
          ),
          OptionGroup(
            id: 'pain',
            title: 'Pain',
            multiple: false,
            minSelect: 1,
            maxSelect: 1,
            items: [
              OptionItem(id: 'pita', label: 'Pain pita', price: 0.00),
              OptionItem(id: 'galette', label: 'Galette', price: 0.00),
            ],
          ),
          OptionGroup(
            id: 'crudites',
            title: 'Crudites / Retirer (max 4)',
            multiple: true,
            minSelect: 0,
            maxSelect: 4,
            items: [
              OptionItem(id: 'sans_crudites', label: 'Sans crudites', price: 0),
              OptionItem(id: 'sans_tomates', label: 'Sans tomates', price: 0),
              OptionItem(id: 'sans_salade', label: 'Sans salade', price: 0),
              OptionItem(id: 'sans_oignons', label: 'Sans oignons', price: 0),
              OptionItem(
                  id: 'sans_cornichons', label: 'Sans cornichons', price: 0),
            ],
          ),
          OptionGroup(
            id: 'supp',
            title: 'Supplements',
            multiple: true,
            minSelect: 0,
            maxSelect: 3,
            items: [
              OptionItem(id: 'cheddar', label: 'Cheddar', price: 1.50),
              OptionItem(
                  id: 'mozzarella', label: 'Mozzarella rapee', price: 1.50),
              OptionItem(id: 'feta', label: 'Feta', price: 1.50),
              OptionItem(
                  id: 'porc', label: 'Poitrine de porc fume', price: 1.50),
              OptionItem(id: 'chevre', label: 'Chevre', price: 1.50),
              OptionItem(id: 'legumes', label: 'Legumes grilles', price: 1.50),
              OptionItem(id: 'oeuf', label: 'Oeuf', price: 1.50),
              OptionItem(
                  id: 'double_cheddar', label: 'Double Cheddar', price: 3.00),
              // <-- DÜZELTME: _OptionItem -> OptionItem olarak değiştirildi.
              OptionItem(
                  id: 'double_mozza',
                  label: 'Double Mozzarella rapee',
                  price: 3.00),
              OptionItem(
                  id: 'double_porc',
                  label: 'Double Poitrine de porc fume',
                  price: 3.00),
            ],
          ),
          OptionGroup(
            id: 'sauces',
            title: 'Sauces',
            multiple: true,
            minSelect: 1,
            maxSelect: 2,
            items: [
              OptionItem(id: 'sans_sauce', label: 'Sans sauce', price: 0.00),
              OptionItem(
                  id: 'blanche', label: 'Sauce blanche maison', price: 0.00),
              OptionItem(id: 'ketchup', label: 'Ketchup', price: 0.00),
              OptionItem(id: 'mayo', label: 'Mayonnaise', price: 0.00),
              OptionItem(id: 'algerienne', label: 'Algerienne', price: 0.00),
              OptionItem(id: 'bbq', label: 'Barbecue', price: 0.00),
              OptionItem(id: 'bigburger', label: 'Big Burger', price: 0.00),
              OptionItem(id: 'harissa', label: 'Harissa', price: 0.00),
            ],
          ),
          OptionGroup(
            id: 'formule',
            title: 'Formule',
            multiple: false,
            minSelect: 1,
            maxSelect: 1,
            items: [
              OptionItem(id: 'seul', label: 'Seul', price: 0.00),
              OptionItem(id: 'frites', label: 'Avec frites', price: 1.00),
              OptionItem(id: 'boisson', label: 'Avec boisson', price: 1.00),
              OptionItem(
                  id: 'menu', label: 'Avec frites et boisson', price: 2.00),
            ],
          ),
        ]),
        Product(name: 'Tacos', groups: [
          OptionGroup(
            id: 'type_tacos',
            title: 'Taille',
            multiple: false,
            minSelect: 1,
            maxSelect: 1,
            items: [
              OptionItem(id: 'm', label: 'M', price: 8.50),
              OptionItem(id: 'l', label: 'L', price: 10.00),
            ],
          ),
          OptionGroup(
            id: 'viande_tacos',
            title: 'Viande',
            multiple: false,
            minSelect: 1,
            maxSelect: 1,
            items: [
              OptionItem(id: 'kebab', label: 'Kebab', price: 0.00),
              OptionItem(id: 'poulet', label: 'Poulet', price: 0.00),
              OptionItem(id: 'steak', label: 'Steak', price: 0.00),
              OptionItem(id: 'vege', label: 'Vegetarien', price: 0.00),
            ],
          ),
          OptionGroup(
            id: 'supp_tacos',
            title: 'Supplements',
            multiple: true,
            minSelect: 0,
            maxSelect: 3,
            items: [
              OptionItem(id: 'cheddar', label: 'Cheddar', price: 1.50),
              OptionItem(
                  id: 'mozzarella', label: 'Mozzarella rapee', price: 1.50),
              OptionItem(id: 'oeuf', label: 'Oeuf', price: 1.00),
            ],
          ),
          OptionGroup(
            id: 'sauce_tacos',
            title: 'Sauces',
            multiple: true,
            minSelect: 1,
            maxSelect: 2,
            items: [
              OptionItem(
                  id: 'blanche', label: 'Sauce blanche maison', price: 0.00),
              OptionItem(id: 'ketchup', label: 'Ketchup', price: 0.00),
              OptionItem(id: 'mayo', label: 'Mayonnaise', price: 0.00),
              OptionItem(id: 'algerienne', label: 'Algerienne', price: 0.00),
              OptionItem(id: 'bbq', label: 'Barbecue', price: 0.00),
              OptionItem(id: 'harissa', label: 'Harissa', price: 0.00),
            ],
          ),
          OptionGroup(
            id: 'formule_tacos',
            title: 'Formule',
            multiple: false,
            minSelect: 1,
            maxSelect: 1,
            items: [
              OptionItem(id: 'seul', label: 'Seul', price: 0.00),
              OptionItem(
                  id: 'menu', label: 'Avec frites et boisson', price: 2.00),
            ],
          ),
        ]),
        Product(name: 'Burgers', groups: [
          OptionGroup(
            id: 'type_burger',
            title: 'Burger',
            multiple: false,
            minSelect: 1,
            maxSelect: 1,
            items: [
              OptionItem(id: 'classic', label: 'Classic', price: 7.90),
              OptionItem(id: 'double', label: 'Double cheese', price: 9.90),
              OptionItem(id: 'chicken', label: 'Chicken', price: 8.50),
              OptionItem(id: 'veggie', label: 'Veggie', price: 8.50),
            ],
          ),
          OptionGroup(
            id: 'sauce_burger',
            title: 'Sauces',
            multiple: true,
            minSelect: 0,
            maxSelect: 2,
            items: [
              OptionItem(
                  id: 'blanche', label: 'Sauce blanche maison', price: 0.00),
              OptionItem(id: 'ketchup', label: 'Ketchup', price: 0.00),
              OptionItem(id: 'mayo', label: 'Mayonnaise', price: 0.00),
              OptionItem(id: 'bbq', label: 'Barbecue', price: 0.00),
            ],
          ),
          OptionGroup(
            id: 'formule_burger',
            title: 'Formule',
            multiple: false,
            minSelect: 1,
            maxSelect: 1,
            items: [
              OptionItem(id: 'seul', label: 'Seul', price: 0.00),
              OptionItem(id: 'frites', label: 'Avec frites', price: 1.00),
              OptionItem(
                  id: 'menu', label: 'Avec frites et boisson', price: 2.00),
            ],
          ),
        ]),
        Product(name: 'Box', groups: [
          OptionGroup(
            id: 'type_box',
            title: 'Choix box',
            multiple: false,
            minSelect: 1,
            maxSelect: 1,
            items: [
              OptionItem(id: 'tenders6', label: '6 Tenders', price: 6.50),
              OptionItem(id: 'nuggets9', label: '9 Nuggets', price: 7.90),
              OptionItem(id: 'wings8', label: '8 Wings', price: 7.90),
              OptionItem(id: 'mix12', label: 'Mix 12 pcs', price: 9.90),
            ],
          ),
          OptionGroup(
            id: 'sauce_box',
            title: 'Sauces',
            multiple: true,
            minSelect: 1,
            maxSelect: 2,
            items: [
              OptionItem(id: 'ketchup', label: 'Ketchup', price: 0.00),
              OptionItem(id: 'mayo', label: 'Mayonnaise', price: 0.00),
              OptionItem(id: 'bbq', label: 'Barbecue', price: 0.00),
              OptionItem(
                  id: 'blanche', label: 'Sauce blanche maison', price: 0.00),
            ],
          ),
          OptionGroup(
            id: 'plus_box',
            title: 'Accompagnement',
            multiple: true,
            minSelect: 0,
            maxSelect: 2,
            items: [
              OptionItem(id: 'frites', label: 'Frites', price: 2.00),
              OptionItem(id: 'boisson', label: 'Boisson', price: 1.50),
            ],
          ),
        ]),
        Product(name: 'Menu Enfant', groups: [
          OptionGroup(
            id: 'choix_enfant',
            title: 'Choix',
            multiple: false,
            minSelect: 1,
            maxSelect: 1,
            items: [
              OptionItem(
                  id: 'cheese_menu',
                  label: 'Cheeseburger avec frites',
                  price: 7.90),
              OptionItem(
                  id: 'nuggets_menu',
                  label: '5 Nuggets et frites',
                  price: 7.90),
            ],
          ),
          OptionGroup(
            id: 'crudites_enfant',
            title: 'Crudites',
            multiple: true,
            minSelect: 0,
            maxSelect: 3,
            items: [
              OptionItem(id: 'avec', label: 'Avec crudites', price: 0.00),
              OptionItem(id: 'sans_salade', label: 'Sans salade', price: 0.00),
              OptionItem(
                  id: 'sans_cornichon', label: 'Sans cornichon', price: 0.00),
            ],
          ),
          OptionGroup(
            id: 'sauce_enfant',
            title: 'Sauces',
            multiple: false,
            minSelect: 1,
            maxSelect: 1,
            items: [
              OptionItem(id: 'sans_sauce', label: 'Sans sauce', price: 0.00),
              OptionItem(
                  id: 'blanche', label: 'Sauce blanche maison', price: 0.00),
              OptionItem(id: 'ketchup', label: 'Ketchup', price: 0.00),
              OptionItem(id: 'mayo', label: 'Mayonnaise', price: 0.00),
            ],
          ),
          OptionGroup(
            id: 'boisson_enfant',
            title: 'Boisson',
            multiple: false,
            minSelect: 1,
            maxSelect: 1,
            items: [
              OptionItem(id: 'sans_boisson', label: 'Sans boisson', price: 0.00),
              OptionItem(id: 'avec_boisson', label: 'Avec boisson', price: 1.00),
            ],
          ),
        ]),
        Product(name: 'Petit Faim', groups: [
          OptionGroup(
            id: 'choix_pf',
            title: 'Choix',
            multiple: false,
            minSelect: 1,
            maxSelect: 1,
            items: [
              OptionItem(
                  id: 'frites_p', label: 'Frites petite portion', price: 3.00),
              OptionItem(
                  id: 'frites_g', label: 'Frites grande portion', price: 6.00),
              OptionItem(id: 'tenders3', label: '3 Tenders', price: 0.00),
              OptionItem(id: 'tenders6', label: '6 Tenders', price: 0.00),
              OptionItem(id: 'nuggets6', label: '6 Nuggets', price: 0.00),
              OptionItem(id: 'nuggets12', label: '12 Nuggets', price: 0.00),
            ],
          ),
          OptionGroup(
            id: 'sauce_pf',
            title: 'Sauces',
            multiple: true,
            minSelect: 1,
            maxSelect: 2,
            items: [
              OptionItem(id: 'sans_sauce', label: 'Sans sauce', price: 0.00),
              OptionItem(
                  id: 'blanche', label: 'Sauce blanche maison', price: 0.00),
              OptionItem(id: 'ketchup', label: 'Ketchup', price: 0.00),
              OptionItem(id: 'mayo', label: 'Mayonnaise', price: 0.00),
              OptionItem(id: 'algerienne', label: 'Algerienne', price: 0.00),
              OptionItem(id: 'bbq', label: 'Barbecue', price: 0.00),
              OptionItem(id: 'bigburger', label: 'Big Burger', price: 0.00),
              OptionItem(id: 'harissa', label: 'Harissa', price: 0.00),
            ],
          ),
        ]),
      ];

      app.products.addAll(products);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final totalCart = app.cart.fold(0.0, (s, l) => s + l.total);
    final cartBadge = app.cart.length;

    final pages = [
      const ProductsPage(),
      CreateProductPage(onGoToTab: (i) => setState(() => index = i)),
      const CartPage(),
      const OrdersPage(),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('BISCORNUE')),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.grid_view_rounded), label: 'Produits'),
          const NavigationDestination(
              icon: Icon(Icons.add_box_outlined), label: 'Créer'),
          NavigationDestination(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.shopping_bag_outlined),
                if (cartBadge > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: Colors.red),
                      child: Text('$cartBadge',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white)),
                    ),
                  ),
              ],
            ),
            label: 'Panier (€${totalCart.toStringAsFixed(2)})',
          ),
          const NavigationDestination(
              icon: Icon(Icons.receipt_long), label: 'Commandes'),
        ],
        onDestinationSelected: (i) async {
          if (i == 1) {
            final ok = await _askPin(context);
            if (!ok) return;
          }
          if (i == 2) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          }
          setState(() => index = i);
        },
      ),
    );
  }
}

/* =======================
    PAGE 1 : PRODUITS
    ======================= */
class ProductsPage extends StatelessWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final products = app.products;

    if (products.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.info_outline, size: 48),
          SizedBox(height: 8),
          Text('Aucun produit. Allez à "Créer" pour en ajouter.'),
        ]),
      );
    }

    final width = MediaQuery.of(context).size.width;
    int cross = 2;
    if (width > 600) cross = 3;
    if (width > 900) cross = 4;
    final aspect = width > 900 ? 0.9 : (width > 600 ? 0.95 : 0.88);

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cross,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: aspect,
      ),
      itemCount: products.length,
      itemBuilder: (_, i) => _ProductCard(product: products[i]),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  const _ProductCard({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    Future<void> openWizard() async {
      final added = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => OrderWizard(product: product)),
      );
      if (added == true && context.mounted) {
        _snack(context, 'Ajouté au panier.');
      }
    }

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: openWizard,
      child: Ink(
        decoration: BoxDecoration(
          color: color.surfaceVariant,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 56,
                    width: 56,
                    decoration: BoxDecoration(
                      color: color.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.fastfood_rounded,
                        color: color.primary, size: 32),
                  ),
                  const SizedBox(height: 12),
                  Text(product.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('${product.groups.length} groupe(s)'),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: choisirButton(() => openWizard(), context),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: IconButton(
                tooltip: 'Modifier',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final ok = await _askPin(context);
                  if (!ok) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CreateProductPage(
                        onGoToTab: (_) {},
                        editIndex: AppScope.of(context).products.indexOf(product),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* =======================
    PAGE 2 : CRÉER + DÜZENLE (kısa versiyon)
    ======================= */
class CreateProductPage extends StatefulWidget {
  final void Function(int) onGoToTab;
  final int? editIndex;
  const CreateProductPage({super.key, required this.onGoToTab, this.editIndex});
  @override
  State<CreateProductPage> createState() => _CreateProductPageState();
}

class _CreateProductPageState extends State<CreateProductPage> {
  final TextEditingController nameCtrl = TextEditingController(text: 'Sandwich');
  final List<OptionGroup> editingGroups = [];
  int? editingIndex;
  final TextEditingController delayCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    editingIndex = widget.editIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (editingIndex != null) _loadForEdit(editingIndex!);
      final app = AppScope.of(context);
      delayCtrl.text = app.prepMinutes.toString();
    });
  }

  void _loadForEdit(int idx) {
    final app = AppScope.of(context);
    if (idx < 0 || idx >= app.products.length) return;
    final p = app.products[idx];
    nameCtrl.text = p.name;
    editingGroups
      ..clear()
      ..addAll(p.groups.map(_copyGroup));
    setState(() => editingIndex = idx);
  }

  OptionGroup _copyGroup(OptionGroup g) => OptionGroup(
        id: g.id,
        title: g.title,
        multiple: g.multiple,
        minSelect: g.minSelect,
        maxSelect: g.maxSelect,
        items: g.items
            .map((e) => OptionItem(id: e.id, label: e.label, price: e.price))
            .toList(),
      );

  void addGroup() {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    editingGroups.add(OptionGroup(
        id: id,
        title: 'Nouveau groupe',
        multiple: false,
        minSelect: 1,
        maxSelect: 1));
    setState(() {});
  }

  void saveProduct() {
    final app = AppScope.of(context);
    if (nameCtrl.text.trim().isEmpty) {
      _snack(context, 'Nom du produit requis.');
      return;
    }
    for (final g in editingGroups) {
      if (g.title.trim().isEmpty) {
        _snack(context, 'Titre du groupe manquant.');
        return;
      }
      if (g.items.isEmpty) {
        _snack(context, 'Ajoutez au moins une option dans "${g.title}".');
        return;
      }
      if (g.minSelect < 0 || g.maxSelect < 1 || g.minSelect > g.maxSelect) {
        _snack(context, 'Règles min/max invalides dans "${g.title}".');
        return;
      }
      if (!g.multiple && (g.minSelect != 1 || g.maxSelect != 1)) {
        _snack(context, 'Choix unique doit avoir min=1 et max=1 (${g.title}).');
        return;
      }
    }
    final p = Product(name: nameCtrl.text.trim(), groups: List.of(editingGroups));
    if (editingIndex == null) {
      app.addProduct(p);
      _snack(context, 'Produit créé.');
    } else {
      app.replaceProductAt(editingIndex!, p);
      _snack(context, 'Produit mis à jour.');
    }
    nameCtrl.text = '';
    editingGroups.clear();
    setState(() => editingIndex = null);

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      widget.onGoToTab(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  widget.onGoToTab(0);
                }
              },
              tooltip: 'Retour'),
          const SizedBox(width: 8),
          Text(editingIndex == null ? 'Créer un produit' : 'Modifier un produit',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              nameCtrl.text = '';
              editingGroups.clear();
              setState(() => editingIndex = null);
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                widget.onGoToTab(0);
              }
            },
            icon: const Icon(Icons.close),
            label: const Text('Annuler'),
          ),
        ]),
        const SizedBox(height: 12),
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: delayCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Délai de préparation (minutes)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final m = int.tryParse(delayCtrl.text.trim());
                    if (m == null || m < 0) {
                      _snack(context, 'Valeur invalide.');
                      return;
                    }
                    app.setPrepMinutes(m);
                    _snack(context, 'Délai enregistré: $m min');
                  },
                  child: const Text('Enregistrer'),
                ),
              ],
            ),
          ),
        ),
        if (app.products.isNotEmpty) ...[
          const Text('Produits existants',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: app.products.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final p = app.products[i];
              return ListTile(
                leading: const Icon(Icons.fastfood_rounded),
                title: Text(p.name),
                subtitle: Text('${p.groups.length} groupe(s)'),
                trailing: FilledButton.tonalIcon(
                  icon: const Icon(Icons.edit),
                  label: const Text('Modifier'),
                  onPressed: () => _loadForEdit(i),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
        ],
        TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(
                labelText: 'Nom du produit', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        Row(children: [
          FilledButton.icon(
              onPressed: addGroup,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un groupe')),
          const SizedBox(width: 12),
          OutlinedButton.icon(
              onPressed: saveProduct,
              icon: const Icon(Icons.save),
              label: const Text('Enregistrer')),
        ]),
        const SizedBox(height: 12),
        for (int i = 0; i < editingGroups.length; i++)
          _GroupEditor(
            key: ValueKey(editingGroups[i].id),
            group: editingGroups[i],
            onDelete: () => setState(() => editingGroups.removeAt(i)),
            onChanged: () => setState(() {}),
          ),
        if (editingGroups.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Text(
                'Aucun groupe. Ajoutez "Pain", "Viande", "Suppléments", "Sauces", etc.'),
          ),
      ],
    );
  }
}

class _GroupEditor extends StatefulWidget {
  final OptionGroup group;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  const _GroupEditor(
      {super.key,
      required this.group,
      required this.onDelete,
      required this.onChanged});
  @override
  State<_GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends State<_GroupEditor> {
  final TextEditingController titleCtrl = TextEditingController();
  final TextEditingController minCtrl = TextEditingController();
  final TextEditingController maxCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    titleCtrl.text = widget.group.title;
    minCtrl.text = widget.group.minSelect.toString();
    maxCtrl.text = widget.group.maxSelect.toString();
  }

  void apply() {
    widget.group.title = titleCtrl.text.trim();
    widget.group.multiple = _mode == 1;
    widget.group.minSelect = int.tryParse(minCtrl.text) ?? 0;
    widget.group.maxSelect = int.tryParse(maxCtrl.text) ?? 1;
    widget.onChanged();
  }

  int get _mode => widget.group.multiple ? 1 : 0;
  set _mode(int v) {
    if (v == 0) {
      minCtrl.text = '1';
      maxCtrl.text = '1';
    }
    apply();
    setState(() {});
  }

  void addOption() {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    widget.group.items.add(OptionItem(id: id, label: 'Nouvelle option', price: 0));
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                    labelText: 'Titre du groupe',
                    border: OutlineInputBorder()),
                onChanged: (_) => apply(),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _mode,
              items: const [
                DropdownMenuItem(value: 0, child: Text('Choix unique')),
                DropdownMenuItem(value: 1, child: Text('Choix multiple')),
              ],
              onChanged: (v) {
                if (v != null) _mode = v;
              },
            ),
            const SizedBox(width: 8),
            IconButton(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: minCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Sélection min', border: OutlineInputBorder()),
                onChanged: (_) => apply(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: maxCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Sélection max', border: OutlineInputBorder()),
                onChanged: (_) => apply(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
                onPressed: addOption,
                icon: const Icon(Icons.add),
                label: const Text('Ajouter une option')),
          ]),
          const SizedBox(height: 8),
          for (int i = 0; i < g.items.length; i++)
            _OptionEditor(
              key: ValueKey(g.items[i].id),
              item: g.items[i],
              onDelete: () {
                g.items.removeAt(i);
                widget.onChanged();
                setState(() {});
              },
              onChanged: () {
                widget.onChanged();
                setState(() {});
              },
            ),
        ]),
      ),
    );
  }
}

class _OptionEditor extends StatefulWidget {
  final OptionItem item;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  const _OptionEditor(
      {super.key,
      required this.item,
      required this.onDelete,
      required this.onChanged});
  @override
  State<_OptionEditor> createState() => _OptionEditorState();
}

class _OptionEditorState extends State<_OptionEditor> {
  final TextEditingController labelCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();
  @override
  void initState() {
    super.initState();
    labelCtrl.text = widget.item.label;
    priceCtrl.text = widget.item.price.toStringAsFixed(2);
  }

  void apply() {
    widget.item.label = labelCtrl.text.trim();
    widget.item.price = double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0.0;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      title: Row(children: [
        Expanded(
          child: TextField(
            controller: labelCtrl,
            decoration: const InputDecoration(
                labelText: 'Nom de l’option', border: OutlineInputBorder()),
            onChanged: (_) => apply(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          child: TextField(
            controller: priceCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Prix (€)', border: OutlineInputBorder()),
            onChanged: (_) => apply(),
          ),
        ),
        IconButton(
            onPressed: widget.onDelete, icon: const Icon(Icons.delete_outline)),
      ]),
    );
  }
}

/* =======================
    WIZARD
    ======================= */
class OrderWizard extends StatefulWidget {
  final Product product;
  final Map<String, List<OptionItem>>? initialPicked;
  final bool editMode;

  const OrderWizard({
    super.key,
    required this.product,
    this.initialPicked,
    this.editMode = false,
  });

  @override
  State<OrderWizard> createState() => _OrderWizardState();
}

class _OrderWizardState extends State<OrderWizard> {
  int step = 0;
  final Map<String, List<OptionItem>> picked = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialPicked != null) {
      for (final e in widget.initialPicked!.entries) {
        picked[e.key] = List<OptionItem>.from(e.value);
      }
    }
  }

  List<OptionGroup> _groupsForVisibility(List<OptionGroup> base) {
    if (widget.product.name != 'Menu Enfant') return base;

    final cheeseSecildiMi =
        (picked['choix_enfant'] ?? const <OptionItem>[]).any((it) => it.id == 'cheese_menu');

    return base.where((g) {
      if (g.id == 'crudites_enfant') return cheeseSecildiMi;
      return true;
    }).toList();
  }

  void _toggleSingle(OptionGroup g, OptionItem it) {
    picked[g.id] = [it];
    setState(() {});
  }

  void _toggleMulti(OptionGroup g, OptionItem it) {
    final list = List<OptionItem>.from(picked[g.id] ?? []);
    final isCrud = g.id == 'crudites';
    final isSansCrud = it.id == 'sans_crudites';

    if (isCrud && isSansCrud) {
      picked[g.id] = [it];
      setState(() {});
      return;
    }

    final exists = list.any((e) => e.id == it.id);
    if (exists) {
      list.removeWhere((e) => e.id == it.id);
    } else {
      if (isCrud) {
        list.removeWhere((e) => e.id == 'sans_crudites');
      }
      if (list.length >= g.maxSelect) return;
      list.add(it);
    }

    picked[g.id] = list;
    setState(() {});
  }

  bool _validGroup(OptionGroup g) {
    final n = (picked[g.id] ?? const []).length;
    return n >= g.minSelect && n <= g.maxSelect;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupsForVisibility(widget.product.groups);
    final isSummary = step >= groups.length;
    final total = widget.product.priceForSelection(picked);

    return Scaffold(
      appBar: AppBar(
        title: Text(isSummary ? 'Récapitulatif' : widget.product.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (isSummary) {
              setState(() => step = groups.isEmpty ? 0 : groups.length - 1);
            } else if (step > 0) {
              setState(() => step--);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: isSummary
                ? _Summary(product: widget.product, picked: picked, total: total)
                : _GroupStep(
                    group: groups[step],
                    picked: picked,
                    toggleSingle: _toggleSingle,
                    toggleMulti: _toggleMulti,
                  ),
          ),
          Positioned(
            left: 16,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
            child: FloatingActionButton.large(
              heroTag: 'prevFab',
              onPressed: step == 0 ? null : () => setState(() => step--),
              child: const Icon(Icons.arrow_back),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
            child: FloatingActionButton.large(
              heroTag: 'nextFab',
              onPressed: () {
                if (isSummary) {
                  if (widget.editMode) {
                    final result = {
                      for (final e in picked.entries)
                        e.key: List<OptionItem>.from(e.value)
                    };
                    Navigator.pop(context, result);
                  } else {
                    final app = AppScope.of(context);
                    app.addLineToCart(widget.product, picked);
                    if (!mounted) return;
                    Navigator.pop(context, true);
                  }
                  return;
                }
                final g = groups[step];
                if (!_validGroup(g)) {
                  _showWarn(context, 'Sélection invalide pour "${g.title}".');
                  return;
                }
                setState(() => step++);
              },
              child: Icon(isSummary
                  ? (widget.editMode ? Icons.check : Icons.add_shopping_cart)
                  : Icons.arrow_forward),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupStep extends StatelessWidget {
  final OptionGroup group;
  final Map<String, List<OptionItem>> picked;
  final void Function(OptionGroup, OptionItem) toggleSingle;
  final void Function(OptionGroup, OptionItem) toggleMulti;

  const _GroupStep({
    required this.group,
    required this.picked,
    required this.toggleSingle,
    required this.toggleMulti,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    const desired = 160.0;
    // <-- DÜZELTME: .toInt() eklendi
    final int cross = ((size.width / desired).floor()).clamp(2, 5).toInt();

    final selectedList = picked[group.id] ?? const <OptionItem>[];
    final sansCrudOn =
        group.id == 'crudites' && selectedList.any((e) => e.id == 'sans_crudites');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Text(
            group.title +
                (group.multiple
                    ? ' (min ${group.minSelect}, max ${group.maxSelect})'
                    : ''),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cross,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1, // KARE
            ),
            itemCount: group.items.length,
            itemBuilder: (_, i) {
              final it = group.items[i];
              final isSelected = selectedList.any((e) => e.id == it.id);
              final disabled = sansCrudOn && it.id != 'sans_crudites';

              void onTap() {
                if (group.multiple) {
                  toggleMulti(group, it);
                } else {
                  toggleSingle(group, it);
                }
              }

              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: disabled ? null : onTap,
                child: Opacity(
                  opacity: disabled ? 0.35 : 1.0,
                  child: Ink(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.primaryContainer
                          : color.surfaceVariant,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            isSelected ? color.primary : color.outlineVariant,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          top: 8,
                          right: 8,
                          child: group.multiple
                              ? Icon(
                                  isSelected
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank,
                                  size: 22,
                                  color: isSelected
                                      ? color.primary
                                      : color.onSurfaceVariant,
                                )
                              : Icon(
                                  isSelected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  size: 22,
                                  color: isSelected
                                      ? color.primary
                                      : color.onSurfaceVariant,
                                ),
                        ),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  it.label,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                if (it.price != 0)
                                  Text(
                                    '+ ${_formatEuro(it.price)}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: color.onSurfaceVariant,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  final Product product;
  final Map<String, List<OptionItem>> picked;
  final double total;
  const _Summary(
      {required this.product, required this.picked, required this.total});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Récapitulatif — ${product.name}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        for (final g in product.groups)
          if ((picked[g.id] ?? const <OptionItem>[]).isNotEmpty) ...[
            Text(g.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            for (final it in (picked[g.id] ?? const <OptionItem>[]))
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('• ${it.label}'),
                Text(it.price == 0
                    ? '€0.00'
                    : '€${it.price.toStringAsFixed(2)}'),
              ]),
            const SizedBox(height: 8),
            const Divider(),
          ],
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('SOUS-TOTAL',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text('€${total.toStringAsFixed(2)}',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 24),
      ],
    );
  }
}

/* =======================
    PAGE 3 : PANIER
    ======================= */
class CartPage extends StatelessWidget {
  const CartPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final lines = app.cart;
    final total = lines.fold(0.0, (s, l) => s + l.total);

    if (lines.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.shopping_bag_outlined, size: 48),
          SizedBox(height: 8),
          Text('Panier vide. Ajoutez des produits.'),
        ]),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(children: [
            const Text('Panier',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => app.clearCart(),
              icon: const Icon(Icons.delete_sweep),
              label: const Text('Vider'),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: lines.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final l = lines[i];
              return ListTile(
                leading: const Icon(Icons.fastfood),
                title: Text('${l.product.name} • €${l.total.toStringAsFixed(2)}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final g in l.product.groups)
                      if ((l.picked[g.id] ?? const <OptionItem>[]).isNotEmpty) ...[
                        Text(g.title,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        for (final it in (l.picked[g.id] ?? const <OptionItem>[]))
                          Text(
                              '• ${it.label}${it.price == 0 ? '' : ' (+€${it.price.toStringAsFixed(2)})'}'),
                      ],
                  ],
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'Düzenle',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final result =
                            await Navigator.push<Map<String, List<OptionItem>>>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderWizard(
                              product: l.product,
                              initialPicked: l.picked,
                              editMode: true,
                            ),
                          ),
                        );
                        if (result != null) {
                          app.updateCartLineAt(i, result);
                          if (context.mounted) {
                            _snack(context, 'Satır güncellendi.');
                          }
                        }
                      },
                    ),
                    IconButton(
                      tooltip: 'Sil',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => app.removeCartLineAt(i),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('TOTAL',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('€${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: FilledButton.icon(
            onPressed: () async {
              final name = await _askCustomerName(context);
              if (name == null) return;
              final app = AppScope.of(context);
              final ready =
                  DateTime.now().add(Duration(minutes: app.prepMinutes));
              app.finalizeCartToOrder(customer: name);
              if (context.mounted) {
                _snack(context,
                    'Commande validée pour "$name". Prêt à ${_two(ready.hour)}:${_two(ready.minute)}.');
              }
            },
            icon: const Icon(Icons.check),
            label: const Text('Valider la commande'),
          ),
        ),
      ],
    );
  }
}

/* =======================
    PAGE 4 : COMMANDES + YAZDIRMA
    ======================= */
class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final orders = app.orders.reversed.toList();

    if (orders.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.receipt_long, size: 48),
          SizedBox(height: 8),
          Text('Aucune commande.'),
        ]),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(children: [
            const Text('Commandes',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () async {
                final pinOk = await _askPin(context);
                if (!pinOk) return;
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Fin de journée ?'),
                    content: const Text(
                        'Toutes les commandes seront supprimées. Action irréversible.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Annuler')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Supprimer')),
                    ],
                  ),
                );
                if (ok == true) app.clearOrders();
              },
              icon: const Icon(Icons.delete_forever),
              label: const Text('Journée terminée'),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final o = orders[i];
              final who = o.customer.isEmpty ? '' : ' — ${o.customer}';
              return ListTile(
                leading: const Icon(Icons.receipt),
                title: Text(
                    'Commande$who • ${o.lines.length} article(s) • €${o.total.toStringAsFixed(2)}'),
                subtitle:
                    Text('Prêt à ${_two(o.readyAt.hour)}:${_two(o.readyAt.minute)}'),
                trailing: IconButton(
                  icon: const Icon(Icons.print_outlined),
                  onPressed: () async {
                    try {
                      await printOrder(o);
                      _snack(context, 'Fiş yazıcıya gönderildi.');
                    } catch (e) {
                      _snack(context, 'Yazdırma hatası: $e');
                    }
                  },
                  tooltip: 'Imprimer',
                ),
                onTap: () {
                  showDialog(
                      context: context,
                      builder: (_) {
                        return AlertDialog(
                          title: const Text('Détails de la commande'),
                          content: SizedBox(
                            width: 360,
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                if (o.customer.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text('Client: ${o.customer}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                      'Prêt à: ${_two(o.readyAt.hour)}:${_two(o.readyAt.minute)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ),
                                for (int idx = 0; idx < o.lines.length; idx++) ...[
                                  Text(
                                      'Article ${idx + 1}: ${o.lines[idx].product.name}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  for (final g in o.lines[idx].product.groups)
                                    if ((o.lines[idx].picked[g.id] ??
                                            const <OptionItem>[])
                                        .isNotEmpty) ...[
                                      Text(g.title,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      for (final it in (o.lines[idx]
                                              .picked[g.id] ??
                                          const <OptionItem>[]))
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text('• ${it.label}'),
                                            Text(it.price == 0
                                                ? '€0.00'
                                                : '€${it.price.toStringAsFixed(2)}'),
                                          ],
                                        ),
                                    ],
                                  const Divider(),
                                ],
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('TOTAL',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    Text('€${o.total.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () async {
                                try {
                                  await printOrder(o);
                                  if (context.mounted) {
                                    Navigator.pop(context); // Diyalogu kapat
                                    _snack(context, 'Fiş yazıcıya gönderildi.');
                                  }
                                } catch (e) {
                                  _snack(context, 'Yazdırma hatası: $e');
                                }
                              },
                              child: const Text('Imprimer'),
                            ),
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Fermer')),
                          ],
                        );
                      });
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/* =======================
    DİYALOGLAR & UTIL
    ======================= */
Future<bool> _askPin(BuildContext context) async {
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Code PIN requis'),
      content: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        obscureText: true,
        maxLength: 8,
        decoration: const InputDecoration(
            labelText: 'Entrez le code', border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim() == _ADMIN_PIN),
            child: const Text('Valider')),
      ],
    ),
  );
  if (ok != true && context.mounted) {
    _snack(context, 'Code incorrect.');
  }
  return ok == true;
}

Future<String?> _askCustomerName(BuildContext context) async {
  final ctrl = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setState) {
        return AlertDialog(
          title: const Text('Nom du client'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Écrire le nom',
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
                onSubmitted: (_) {
                  if (ctrl.text.trim().isEmpty) {
                    setState(() => error = 'Le nom est requis.');
                  } else {
                    Navigator.pop(ctx, ctrl.text.trim());
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final name = ctrl.text.trim();
                if (name.isEmpty) {
                  setState(() => error = 'Le nom est requis.');
                  return;
                }
                Navigator.pop(ctx, name);
              },
              child: const Text('Valider'),
            ),
          ],
        );
      });
    },
  );
}

void _snack(BuildContext context, String msg, {int ms = 1200}) {
  if (!context.mounted) return;
  final bottomInset = MediaQuery.of(context).padding.bottom;
  const bottomBar = kBottomNavigationBarHeight;
  final bottomMargin = 12 + bottomInset + bottomBar;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: Duration(milliseconds: ms),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(12, 0, 12, bottomMargin),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        dismissDirection: DismissDirection.horizontal,
      ),
    );
}

void _showWarn(BuildContext context, String msg) {
  _snack(context, msg);
}

/* =======================
    Choisir butonu (kırılma yok)
    ======================= */
Widget choisirButton(VoidCallback onTap, BuildContext context) {
  final color = Theme.of(context).colorScheme;
  return Material(
    color: color.primary,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: const SizedBox(
        height: 48,
        width: 48,
        child: Icon(Icons.shopping_cart_outlined, color: Colors.white),
      ),
    ),
  );
}

// ==================================================
// PLATFORMDAN BAĞIMSIZ YAZDIRMA YARDIMCILARI
// ==================================================

String _two(int n) => n.toString().padLeft(2, '0');

String _money(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

String _rightLine(String left, String right, {int width = 32}) {
  left = left.replaceAll('\n', ' ');
  right = right.replaceAll('\n', ' ');
  if (left.length + right.length > width) {
    left = left.substring(0, width - right.length);
  }
  return left + ' ' * (width - left.length - right.length) + right;
}

void _cmd(Socket s, List<int> bytes) => s.add(bytes);
void _boldOn(Socket s) => _cmd(s, [27, 69, 1]);
void _boldOff(Socket s) => _cmd(s, [27, 69, 0]);
void _size(Socket s, int n) => _cmd(s, [29, 33, n]);
void _alignLeft(Socket s) => _cmd(s, [27, 97, 0]);
void _alignCenter(Socket s) => _cmd(s, [27, 97, 1]);
void _alignRight(Socket s) => _cmd(s, [27, 97, 2]);

void _writeCp1252(Socket socket, String text) {
  final out = <int>[];
  for (final r in text.runes) {
    if (r == 0x20AC) {
      // €
      out.add(0x80);
      continue;
    }
    if (r <= 0x7F) {
      // ASCII
      out.add(r);
      continue;
    }
    final ch = String.fromCharCode(r);
    const repl = {
      'ç': 'c', 'Ç': 'C', 'ğ': 'g', 'Ğ': 'G', 'ı': 'i', 'İ': 'I', 'ö': 'o', 'Ö': 'O',
      'ş': 's', 'Ş': 'S', 'ü': 'u', 'Ü': 'U', 'é': 'e', 'è': 'e', 'ê': 'e', 'á': 'a',
      'à': 'a', 'â': 'a', 'ô': 'o', 'ù': 'u', '–': '-', '—': '-', '…': '...',
      'Œ': 'Oe', 'œ': 'oe',
    };
    final s = repl[ch] ?? '?';
    for (final cu in s.codeUnits) {
      if (cu == 0x20AC) {
        out.add(0x80);
      } else {
        out.add(cu <= 0x7F ? cu : 0x3F);
      }
    }
  }
  socket.add(out);
}

Future<void> printOrder(SavedOrder o) async {
  final socket = await Socket.connect(PRINTER_IP, PRINTER_PORT,
      timeout: const Duration(seconds: 5));

  _cmd(socket, [27, 64]);
  _cmd(socket, [27, 116, 16]);

  _alignCenter(socket);
  _size(socket, 17);
  _boldOn(socket);
  _writeCp1252(socket, '*** BISCORNUE ***\n');
  _boldOff(socket);
  _size(socket, 0);

  if (o.customer.isNotEmpty) {
    _size(socket, 1);
    _boldOn(socket);
    _writeCp1252(socket, 'Client: ${o.customer}\n');
    _boldOff(socket);
    _size(socket, 0);
  }

  _boldOn(socket);
  _size(socket, 1);
  _writeCp1252(socket, 'Pret a: ${_two(o.readyAt.hour)}:${_two(o.readyAt.minute)}\n');
  _size(socket, 0);
  _boldOff(socket);

  _alignLeft(socket);
  _writeCp1252(socket, '------------------------------\n');

  for (int i = 0; i < o.lines.length; i++) {
    final l = o.lines[i];
    _writeCp1252(socket, _rightLine('Item ${i + 1}: ${l.product.name}', _money(l.total)) + '\n');
    for (final g in l.product.groups) {
      final sel = l.picked[g.id] ?? const <OptionItem>[];
      if (sel.isNotEmpty) {
        _writeCp1252(socket, '  ${g.title}:\n');
        for (final it in sel) {
          _writeCp1252(socket, '    * ${it.label}\n');
        }
      }
    }
    if (i != o.lines.length - 1) {
      _writeCp1252(socket, '--------------------------------\n');
    }
  }

  _writeCp1252(socket, '------------------------------\n');
  _alignRight(socket);
  _boldOn(socket);
  _size(socket, 1);
  _writeCp1252(
      socket,
      _rightLine(
          'TOTAL', '€${o.total.toStringAsFixed(2).replaceAll('.', ',')}') +
          '\n');
  _size(socket, 0);
  _boldOff(socket);

  _cmd(socket, [10, 10, 29, 86, 66, 0]);

  await socket.flush();
  await socket.close();
}

String _formatEuro(double v) => '€${v.toStringAsFixed(2)}';

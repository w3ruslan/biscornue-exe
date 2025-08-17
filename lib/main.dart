import 'dart:io'; // Platform + Socket
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'print_spooler_windows.dart'
    show getDefaultPrinterName, writeRawToPrinterWindows;

// Yazıcı sabitleri (IP fallback için)
const String PRINTER_IP = String.fromEnvironment('PRINTER_IP', defaultValue: '192.168.1.1');
const int PRINTER_PORT = int.fromEnvironment('PRINTER_PORT', defaultValue: 9100);
const String _ADMIN_PIN = '6538';

/* =======================
   ENTRY
   ======================= */
Future<void> main() async {
  // Flutter motorunun uygulama çalışmadan önce hazır olduğundan emin ol.
  WidgetsFlutterBinding.ensureInitialized();

  // Masaüstünde tam ekran ve pencere ayarları
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    windowManager.waitUntilReadyToShow(const WindowOptions(), () async {
      await windowManager.setFullScreen(true);
      await windowManager.focus();
    });
  }

  // Uygulama state'ini başlat ve ayarları yükle
  final appState = AppState();
  await appState.loadSettings();
  runApp(AppScope(notifier: appState, child: const App()));

  // Odaklanınca dokunmatik klavyeyi aç (Windows için)
  initAutoOskOnFocus();
}

/* =======================
   UYGULAMA KÖKÜ
   ======================= */
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

// ... Diğer tüm Widget ve Class'lar burada devam ediyor (değişiklik yok)
// ...
// ...

// --- YARDIMCI FONKSİYONLAR, YAZDIRMA, KLAVYE ---

// ... (Buradan sonraki tüm kodlar, önceki yanıtta olduğu gibi aynı kalır)
// ...

// ESC/POS byte üretici (ortak)
List<int> _buildEscPos(SavedOrder o) {
  final out = <int>[];

  void cmd(List<int> b) => out.addAll(b);
  void boldOn()  => cmd([27, 69, 1]);
  void boldOff() => cmd([27, 69, 0]);
  void size(int n) => cmd([29, 33, n]);
  void alignLeft()   => cmd([27, 97, 0]);
  void alignCenter() => cmd([27, 97, 1]);
  void alignRight()  => cmd([27, 97, 2]);

  void writeCp1252(String text) {
    for (final r in text.runes) {
      if (r == 0x20AC) { out.add(0x80); continue; } // €
      if (r <= 0x7F)   { out.add(r); continue; }    // ASCII
      const repl = {
        'ç':'c','Ç':'C','ğ':'g','Ğ':'G','ı':'i','İ':'I','ö':'o','Ö':'O',
        'ş':'s','Ş':'S','ü':'u','Ü':'U','é':'e','è':'e','ê':'e','á':'a','à':'a','â':'a',
        'ô':'o','ù':'u','–':'-','—':'-','…':'...', 'Œ':'Oe','œ':'oe',
      };
      final ch = String.fromCharCode(r);
      final s = repl[ch] ?? '?';
      out.addAll(s.codeUnits.map((cu) => cu <= 0x7F ? cu : 0x3F));
    }
  }

  // init + codepage
  cmd([27, 64]);
  cmd([27, 116, 16]);

  alignCenter(); size(17); boldOn(); writeCp1252('*** BISCORNUE ***\n'); boldOff(); size(0);

  if (o.customer.isNotEmpty) {
    size(1); boldOn(); writeCp1252('Client: ${o.customer}\n'); boldOff(); size(0);
  }

  boldOn(); size(1);
  writeCp1252('Pret a: ${_two(o.readyAt.hour)}:${_two(o.readyAt.minute)}\n');
  size(0); boldOff();

  alignLeft(); writeCp1252('------------------------------\n');

  for (int i = 0; i < o.lines.length; i++) {
    final l = o.lines[i];
    writeCp1252(_rightLine('Item ${i + 1}: ${l.product.name}', _money(l.total)) + '\n');
    for (final g in l.product.groups) {
      final sel = l.picked[g.id] ?? const <OptionItem>[];
      if (sel.isNotEmpty) {
        writeCp1252('  ${g.title}:\n');
        for (final it in sel) {
          writeCp1252('    * ${it.label}\n');
        }
      }
    }
    if (i != o.lines.length - 1) {
      writeCp1252('--------------------------------\n');
    }
  }

  writeCp1252('------------------------------\n');
  alignRight(); boldOn(); size(1);
  writeCp1252(_rightLine('TOTAL', '€${o.total.toStringAsFixed(2).replaceAll('.', ',')}') + '\n');
  size(0); boldOff();

  cmd([10, 10, 29, 86, 66, 0]); // feed + partial cut
  return out;
}

// Windows: spooler (varsayılan yazıcı), Diğerleri: IP/9100
Future<void> printOrder(SavedOrder o) async {
  final data = _buildEscPos(o);

  if (Platform.isWindows) {
    final printer = getDefaultPrinterName();
    if (printer == null || printer.isEmpty) {
      throw Exception('Varsayılan yazıcı bulunamadı. Windows Ayarları > Yazıcılar\'dan bir yazıcı seçin.');
    }
    writeRawToPrinterWindows(printer, data);
    return;
  }

  // IP üzerinden (Android/Linux/macOS)
  final socket = await Socket.connect(PRINTER_IP, PRINTER_PORT, timeout: const Duration(seconds: 5));
  socket.add(data);
  await socket.flush();
  await socket.close();
}

// --- Windows Ekran Klavyesi Yardımcıları ---
Future<void> _launchWindowsOsk() async {
  if (!Platform.isWindows) return;
  // Yaygın iki konum:
  final candidates = [
    r'C:\Program Files\Common Files\microsoft shared\ink\TabTip.exe',
    r'C:\Program Files (x86)\Common Files\microsoft shared\ink\TabTip.exe',
  ];
  for (final p in candidates) {
    try {
      if (await File(p).exists()) {
        // Sessiz başlat
        await Process.start(p, [], mode: ProcessStartMode.detached);
        break;
      }
    } catch (_) {}
  }
}

/// Herhangi bir TextField odak kazandığında klavyeyi aç.
void initAutoOskOnFocus() {
  if (!Platform.isWindows) return;
  FocusManager.instance.addListener(() {
    final node = FocusManager.instance.primaryFocus;
    final ctx = node?.context;
    if (ctx != null && ctx.widget is EditableText) {
      _launchWindowsOsk();
    }
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/product_image_placeholder.dart';
import '../../core/widgets/quantity_selector.dart';
import '../../data/models/product.dart';
import 'cart_controller.dart';

/// Shared Arabic copy for the add-to-cart quantity sheet.
abstract final class AddedToCartPromptCopy {
  static const title = 'كم تبي تطلب؟';
  static const body = 'حدد الكمية، بعدين تكمّل تسوّق أو تتم الطلب من السلة.';
  static const quantityLabel = 'الكمية';
  static const continueShopping = 'متابعة التسوق';
  static const checkout = 'إتمام الطلب';
  static const orderActionTooltip = 'للطلب';

  static String minOrderHint(int minimum) => 'أقل جملة $minimum';
}

/// Opens the quantity sheet, then adds [product] only after an action.
///
/// Returns `false` when the product cannot be ordered, so callers skip the
/// prompt on stock or unavailable items.
bool addProductToCartThenPrompt({
  required BuildContext context,
  required WidgetRef ref,
  required Product product,
  int? quantity,
}) {
  if (!product.isOrderable) return false;
  showAddedToCartPrompt(
    context,
    product: product,
    initialQuantity: quantity,
  );
  return true;
}

Future<void> showAddedToCartPrompt(
  BuildContext context, {
  required Product product,
  int? initialQuantity,
}) {
  if (!context.mounted) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: AddedToCartPromptSheet(
        product: product,
        initialQuantity: initialQuantity,
        onContinueShopping: () => Navigator.of(sheetContext).pop(),
        onCheckout: () {
          Navigator.of(sheetContext).pop();
          if (context.mounted) context.go('/cart');
        },
      ),
    ),
  );
}

class AddedToCartPromptSheet extends ConsumerStatefulWidget {
  const AddedToCartPromptSheet({
    required this.product,
    required this.onContinueShopping,
    required this.onCheckout,
    this.initialQuantity,
    super.key,
  });

  final Product product;
  final int? initialQuantity;
  final VoidCallback onContinueShopping;
  final VoidCallback onCheckout;

  @override
  ConsumerState<AddedToCartPromptSheet> createState() =>
      _AddedToCartPromptSheetState();
}

class _AddedToCartPromptSheetState
    extends ConsumerState<AddedToCartPromptSheet> {
  late int _quantity;

  @override
  void initState() {
    super.initState();
    _quantity = widget.product.normalizeOrderQuantity(
      widget.initialQuantity ?? widget.product.minOrderQuantity,
    );
  }

  void _commitAndRun(VoidCallback action) {
    ref.read(cartControllerProvider.notifier).addQuantity(
          widget.product,
          _quantity,
        );
    action();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final minimum = product.minOrderQuantity;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProductImagePlaceholder(
                    key: const Key('added-to-cart-product-image'),
                    category: product.category,
                    productId: product.id,
                    imageUrl: product.imageUrl,
                    semanticLabel: 'صورة ${product.name}',
                    size: 96,
                    fit: BoxFit.contain,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          product.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AddedToCartPromptCopy.title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        const Text(AddedToCartPromptCopy.body),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text(
                    AddedToCartPromptCopy.quantityLabel,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  QuantitySelector(
                    key: const Key('add-to-cart-quantity'),
                    quantity: _quantity,
                    min: minimum,
                    max: product.orderQuantityLimit,
                    onChanged: (value) => setState(() => _quantity = value),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                AddedToCartPromptCopy.minOrderHint(minimum),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('added-to-cart-checkout'),
                onPressed: () => _commitAndRun(widget.onCheckout),
                child: const Text(AddedToCartPromptCopy.checkout),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('added-to-cart-continue'),
                onPressed: () => _commitAndRun(widget.onContinueShopping),
                child: const Text(AddedToCartPromptCopy.continueShopping),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

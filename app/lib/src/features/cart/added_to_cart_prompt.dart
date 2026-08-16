import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/product.dart';
import 'cart_controller.dart';

/// Shared Arabic copy after a product is added to the cart.
abstract final class AddedToCartPromptCopy {
  static const title = 'تمت إضافة المنتج للسلة';
  static const body = 'تبي تكمّل تسوّق ولا تتم الطلب من السلة؟';
  static const continueShopping = 'متابعة التسوق';
  static const checkout = 'إتمام الطلب';
  static const orderActionTooltip = 'للطلب';
}

/// Adds [product] then asks whether to keep shopping or open the cart.
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
  final cart = ref.read(cartControllerProvider.notifier);
  if (quantity == null) {
    cart.add(product);
  } else {
    cart.addQuantity(product, quantity);
  }
  showAddedToCartPrompt(context);
  return true;
}

Future<void> showAddedToCartPrompt(BuildContext context) {
  if (!context.mounted) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (sheetContext) => AddedToCartPromptSheet(
      onContinueShopping: () => Navigator.of(sheetContext).pop(),
      onCheckout: () {
        Navigator.of(sheetContext).pop();
        if (context.mounted) context.go('/cart');
      },
    ),
  );
}

class AddedToCartPromptSheet extends StatelessWidget {
  const AddedToCartPromptSheet({
    required this.onContinueShopping,
    required this.onCheckout,
    super.key,
  });

  final VoidCallback onContinueShopping;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AddedToCartPromptCopy.title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(AddedToCartPromptCopy.body),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('added-to-cart-checkout'),
                onPressed: onCheckout,
                child: const Text(AddedToCartPromptCopy.checkout),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('added-to-cart-continue'),
                onPressed: onContinueShopping,
                child: const Text(AddedToCartPromptCopy.continueShopping),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

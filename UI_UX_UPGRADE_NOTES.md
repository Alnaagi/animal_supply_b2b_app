# UI/UX Upgrade Notes

## Design Direction

Phase 2A moves the customer app toward a premium mobile wholesale shopping experience: soft off-white background, rounded white product cards, green CTA buttons, orange offer/quantity accents, and Arabic RTL-first spacing.

The uploaded pet shopping image was used only as a moodboard for quality, hierarchy, rounded cards, and shopping flow. The implementation uses original Arabic B2B copy, original demo products, icon placeholders, and wholesale-specific order behavior.

## What Changed

- Login screen has a polished card layout and fast demo access buttons.
- Home screen has greeting, area line, hero offer banner, category circles, top-selling products, offers, reorder card, and WhatsApp support.
- Catalog supports search, category chips, filter placeholder, modern product cards, and product detail navigation.
- Product details include large image placeholder, favorite/share placeholders, supplier, price, old price, SKU, stock, MOQ, package options, description, quantity selector, and add-to-cart.
- Cart has rounded item cards, quantity controls, remove button, promo placeholder, subtotal, handling placeholder, and total.
- Checkout reviews customer info/items/note and creates a demo order with a WhatsApp summary copy action.
- Orders show cards, status chips, details, reorder, and WhatsApp summary copy.
- Profile uses a business account card and clear account/support/logout actions.

## Customer Flow

1. Login with quick demo customer button or `tripoli-pets / Customer123!`.
2. Browse home offers or open catalog.
3. Search/filter products.
4. Open product details and choose quantity.
5. Add to cart.
6. Review cart and checkout.
7. Submit order.
8. View order history or reorder.

## Known Limitations

- Product imagery uses generic external placeholder URLs with icon fallback instead of real uploaded product images.
- Promo code, notifications, favorite/share, and WhatsApp opening are placeholders.
- Full offline sync is still planned for Phase 2B.
- Supabase repositories remain ready but demo mode is still the default.

## Demo Catalog Warning

Realistic product-style names and common brand references are used for presentation/testing only. Prices are demo-only and images are generic placeholders. Replace with the client-approved catalog before production.

## Next UI Improvements

- Add real product images through Supabase Storage.
- Add product grid toggle for tablets.
- Add animated order success screen.
- Add real deep-link parsing for invite tokens.
- Add admin-specific responsive desktop dashboard polish.

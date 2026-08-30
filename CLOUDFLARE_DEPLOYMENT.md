# Cloudflare Web Deployment

The Flutter web application is deployed with Cloudflare Workers Static Assets
behind the route-aware Worker in `cloudflare/worker.mjs`. The Worker name is
`animal-supply-b2b`. Direct Flutter routes such as `/invite?token=...` receive
the app shell, while missing static files return `404` instead of HTML.

## Current web deployment

The August 30, 2026 Worker version `60bb7943-c066-48ba-bdf9-0563a631fc53`
harmonizes the authentication screen background, ambient glow, and vector wallpaper motifs with the active storefront theme:
- Derived background gradient, glowing atmospheric orbs, and pet/animal vector wallpaper motifs entirely from `Theme.of(context).colorScheme` (`primary`, `secondary`, and neutral `onSurfaceVariant`) instead of hardcoded green tones (`#f2f7f4`, `#3d6655`, `#2b6488`).
- Updated login form text field fills and borders to dynamically blend from the active brand primary color and theme surfaces.
- Preserved 100% test pass rate across all test suites in `flutter test` and clean `flutter analyze`.
Ships offline shell `web_shell_manifest.4834ad79ae375d04.json`.

- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `60bb7943-c066-48ba-bdf9-0563a631fc53`
- Flutter version: `1.0.4+25`
- Offline shell version:
  `web_shell_manifest.4834ad79ae375d04.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project

The August 30, 2026 Worker version `7839ec9c-38ab-4551-a2b4-e74cca2ceaa3`
enhances the visibility and contrast of the background pattern on the login screen:
- Increased motif opacity across the grid (primary tint: 19%, secondary tint: 17%, neutral tint: 15%) so paws, pet food bowls, bones, fish, soaring falcons, and sparkles are clearly noticeable, crisp, and defined.
- Preserved the opaque frosted glassmorphic login card so all Arabic copy, form inputs, branding logo, and buttons remain 100% sharp and readable.
- Verified 100% test pass rate across all test suites in `flutter test` and clean `flutter analyze`.
Ships offline shell `web_shell_manifest.ddbdd8287b85530b.json`.

- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `7839ec9c-38ab-4551-a2b4-e74cca2ceaa3`
- Flutter version: `1.0.4+25`
- Offline shell version:
  `web_shell_manifest.ddbdd8287b85530b.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project

The August 30, 2026 Worker version `2f97b122-f890-472b-974c-973c9dc7195d`
triggers instant cart attention animation whenever products are added:
- In addition to prolonged scroll detection, immediately triggers the playful wiggle, vertical hop, and badge pulse animation on the Cart navigation destination icon whenever an item is added to the cart (or `cartCount` increases).
- Replays smoothly from the beginning when consecutive items are added, giving immediate positive reinforcement on both mobile bottom bar and desktop navigation rail.
- Automatically handles animations safely without conflicting timers, resets gracefully if emptied, and honors reduced motion preferences.
- Verified 100% test pass rate in `flutter test` and clean `flutter analyze`.
Ships offline shell `web_shell_manifest.5491190569766c51.json`.

- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `2f97b122-f890-472b-974c-973c9dc7195d`
- Flutter version: `1.0.4+25`
- Offline shell version:
  `web_shell_manifest.5491190569766c51.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project

The August 30, 2026 Worker version `a2b6ccbf-9658-42cb-8f39-1aaceb3571a0`
adds a delightful, attention-grabbing cart reminder animation on prolonged scrolling:
- Detects continuous browsing or scrolling across customer screens when items are pending in the cart (`cartCount > 0`).
- Triggers a rhythmic wiggle, bounce hop, badge scale pulse, and radiant glow on the Cart navigation icon (`CartAttentionNudgeIcon`) across both mobile bottom navigation bar and desktop/tablet navigation rail.
- Automatically settles at rest, pauses during cooldown periods, stops immediately upon navigating to the cart (`/cart` or `/checkout`) or emptying the cart, and respects reduced motion settings.
- Verified 100% test pass rate across all 585 test suites in `flutter test`.
Ships offline shell `web_shell_manifest.44b4233c34f354a0.json`.

- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `a2b6ccbf-9658-42cb-8f39-1aaceb3571a0`
- Flutter version: `1.0.4+25`
- Offline shell version:
  `web_shell_manifest.44b4233c34f354a0.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project

The August 30, 2026 Worker version `1234edac-4102-485e-a93b-6cf80274c132`
refines the add-to-cart prompt sheet buttons and action hierarchy:
- Updated the primary continue action label to "إضافة إلى السلة ومتابعة التسوق" (Add to Cart & Continue Shopping) with an `Icons.add_shopping_cart_rounded` icon, adding the quantity to cart and closing the sheet smoothly so the customer remains on the catalog/home page.
- Emphasized "إتمام الطلب" (Checkout) with `FilledButton.icon` and an `Icons.shopping_cart_checkout_rounded` icon, committing the quantity to the cart and directly routing to `/cart`.
- Verified 100% test pass rate in `flutter test` and updated `added_to_cart_prompt_test.dart`.
Ships offline shell `web_shell_manifest.b22b60d2046dd33f.json`.

- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `1234edac-4102-485e-a93b-6cf80274c132`
- Flutter version: `1.0.4+25`
- Offline shell version:
  `web_shell_manifest.b22b60d2046dd33f.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project

The August 30, 2026 Worker version `a9a7b4c7-3004-481c-89c3-8075d4896c88`
upgrades the login screen background and authentication surface aesthetics:
- Introduces an elegant vector-based pet & animal supply wallpaper pattern (`AuthPatternBackground`) featuring animal paws, pet food bowls, dog bones, fish silhouettes, soaring falcon motifs (Al-Bashek brand identity), and ambient micro-sparkles.
- Layers a smooth multi-stop ambient gradient with soft glowing orbs (teal, warm peach, soft aqua) to provide atmospheric depth without visual clutter or noise.
- Polishes the central authentication card with a glassmorphic surface (`BackdropFilter` blur, semi-translucent crisp white fill, subtle dual-border highlight, and multi-layered soft drop shadows), keeping all typography, inputs, buttons, and brand logos 100% sharp and legible.
- Fully responsive across compact mobile phones, tablets, and wide desktop displays.
Ships offline shell `web_shell_manifest.5ed74566af2c5f1f.json`.

- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `a9a7b4c7-3004-481c-89c3-8075d4896c88`
- Flutter version: `1.0.4+25`
- Offline shell version:
  `web_shell_manifest.5ed74566af2c5f1f.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project

The August 30, 2026 Worker version `f1d9caee-ea25-43ef-99be-d7a3e9237583`
improves banner image handling during upload, cropping, and storefront carousel display:
- Adds stretch-to-fit and full-image mode in `BannerImageCropDialog`, allowing uploaded banners to resize and stretch cleanly to the target banner dimensions without forced cropping.
- Updates banner carousel rendering in `OfferBannerCarousel`, `_BannerImage`, and admin banner preview thumbnails to use `BoxFit.fill`, ensuring complete edge-to-edge presentation of banner artwork, typography, and graphics without cutting off image edges on mobile, tablet, and desktop.
- Retains interactive pan/zoom free crop toggle and contain/cover fit adjustments in the banner crop editor.
Ships offline shell `web_shell_manifest.d75ae44cd51f44d0.json`.

- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `f1d9caee-ea25-43ef-99be-d7a3e9237583`
- Flutter version: `1.0.4+25`
- Offline shell version:
  `web_shell_manifest.d75ae44cd51f44d0.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project

The August 30, 2026 Worker version `9c458ab3-72fb-4af5-a495-585d55679f3b`
unifies dynamic shop logo branding across the entire application:
- Reads and displays custom shop logos from `ShopBrandingCache` / `shopBrandingProvider` across all components (Auth screens, Login, Customer Shell, Admin Shell, Download screen, and dialogs).
- Dynamically synchronizes web browser favicons (`<link rel="icon">`) and Apple Touch Icons (`<link rel="apple-touch-icon">`) to the uploaded shop logo on page load and settings updates.
- Injects dynamic shop logos and branding into PWA installation prompts (`pwa_install.js`), generated customer PDF invoices (`OrderInvoicePdf`), and exported PDF admin reports.
Ships offline shell `web_shell_manifest.30ba64c4b7419625.json`.

- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `9c458ab3-72fb-4af5-a495-585d55679f3b`
- Flutter version: `1.0.4+25`
- Offline shell version:
  `web_shell_manifest.30ba64c4b7419625.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project

The August 28, 2026 Worker version `3eaa088b-0fab-489b-af3d-4e04d0a4ebb3`
minimizes the verbose technical helper text under "حملة إشعار جديدة" in the notifications screen:
- Replaced the lengthy multi-line technical paragraph under "حملة إشعار جديدة" with a concise, clean, and minimal 1-line Arabic subtitle: "إرسال إشعار فوري لجميع العملاء أو عميل محدد".
- Streamlined the notification history section subtitle to a clean Arabic subtitle: "سجل الحملات السابقة وحالة استلامها داخل التطبيق".
- Removed unnecessary Firebase technical details from the admin UI for a clean, spacious presentation.
Ships offline shell `web_shell_manifest.2b5c4162b0719019.json`.

- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `3eaa088b-0fab-489b-af3d-4e04d0a4ebb3`
- Flutter version: `1.0.4+24`
- Offline shell version:
  `web_shell_manifest.2b5c4162b0719019.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project

The August 28, 2026 Worker version `f01f2923-cd39-49a9-b80c-a7655f8f9eb3`
replaces the full green screen splash/reloading flashes with clean theme-neutral skeleton/ghost loading placeholders:
- Replaced the dark green background surface in `BrandedAuthLoading` with a clean, neutral card on a standard scaffold background (and semi-transparent backdrop overlay for login actions).
- Created structural shell skeleton loaders (`ShopAdminShellSkeleton`, `ShopCustomerShellSkeleton`, `ShopAuthShellSkeleton`, `ShopCustomerHomeSkeleton`, and `ShopCartSkeleton`) in `ShopSkeleton`.
- Replaced `AuthBootstrapScreen`'s full green screen with contextual skeleton shells corresponding to the route being loaded (Admin dashboard/subpages, Customer shell/subpages, or Login).
- Full suite of contextual `ShopSkeleton` loaders maintained across all screens.
Ships offline shell `web_shell_manifest.04d6e9a220a9657a.json`.

- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `f01f2923-cd39-49a9-b80c-a7655f8f9eb3`
- Flutter version: `1.0.4+23`
- Offline shell version:
  `web_shell_manifest.04d6e9a220a9657a.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project

The August 28, 2026 Worker version `b26cfab8-edb6-4c75-9cc9-916d63a990ed`
cleans up the storefront banner presentation:
- Removes the dark gradient scrim overlay on the side (RTL start) of the banner images so images render natural, bright, and unshadowed.
- Removes the floating overlay CTA button from the banner carousel card.
- Retains full tap/click responsiveness across the entire banner image surface to navigate to the configured destination (catalog, product, category, offers, or external URL).
Ships offline shell `web_shell_manifest.0e7b87390f9877f5.json`.

- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `b26cfab8-edb6-4c75-9cc9-916d63a990ed`
- Flutter version: `1.0.4+23`
- Offline shell version:
  `web_shell_manifest.0e7b87390f9877f5.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project

The August 28, 2026 Worker version `6ac6a55e-0898-4e12-89c4-d17b4c3bc796`
replaces full-screen blocking spinners and progress indicators across admin and customer screens with modern, RTL-friendly shimmer skeleton/ghost loaders:
- Reusable skeleton suite in `ShopSkeleton` (`ShopDashboardSkeleton`, `ShopProductGridSkeleton`, `ShopProductListSkeleton`, `ShopCategoryStripSkeleton`, `ShopOrderListSkeleton`, `ShopCustomerListSkeleton`, `ShopBannerSkeleton`, `ShopProductDetailsSkeleton`, `ShopSettingsSkeleton`, `ShopReportsSkeleton`, `ShopBannersSkeleton`, `ShopArchiveSkeleton`, `ShopNotificationsSkeleton`, `ShopDownloadSkeleton`, `ShopStorefrontBuilderSkeleton`).
- Contextual placeholder shapes matching final page structure across Admin dashboard, Admin orders, Admin products, Admin customers, Admin banners, Admin reports, Admin archive, Admin notifications, Admin storefront builder, Customer home, Offers, Settings, Download, and Notification sheet.
- RTL-aware light shimmer animation with reduced motion support.
Ships offline shell `web_shell_manifest.06b960d8e8caecac.json`.

- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `6ac6a55e-0898-4e12-89c4-d17b4c3bc796`
- Flutter version: `1.0.4+23`
- Offline shell version:
  `web_shell_manifest.06b960d8e8caecac.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project

The August 28, 2026 Worker version `6c3b1793-8661-4fec-a04e-15bc9e7abcda`
hardens production authentication barriers:
- Completely hides demo login pills and demo quick-buttons ("تجربة سريعة", "مدير", "موظف", "عميل") in production and release builds.
- Strictly guards `allowsDemoCredentials` and `isDemoMode` so that demo credentials (`admin`, `staff`, `tripoli-pets`, `demo`) cannot bypass authentication or create local in-memory admin sessions when connected to Supabase or in production.
- Prevents local demo session injection and enforces role-based redirection away from admin routes for unauthorized users.
- Connects to live Supabase backend (`dykkwshrtbduondnglhi.supabase.co`).
Ships offline shell `web_shell_manifest.73a631272a666ede.json`.

- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `6c3b1793-8661-4fec-a04e-15bc9e7abcda`
- Flutter version: `1.0.4+23`
- Offline shell version:
  `web_shell_manifest.73a631272a666ede.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project

The August 28, 2026 Worker version `007f3547-4aa6-4085-8302-919e5c6ffbfd`
rebuilds and deploys in `APP_ENV=production` connected to live Supabase backend
(`dykkwshrtbduondnglhi.supabase.co`), displaying the live shop branding ("شركة الباشق")
and removing the demo login banner and quick login buttons.
Ships offline shell `web_shell_manifest.ad91bc0b0664c19c.json`.

- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `007f3547-4aa6-4085-8302-919e5c6ffbfd`
- Flutter version: `1.0.4+23`
- Offline shell version:
  `web_shell_manifest.ad91bc0b0664c19c.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project

The August 28, 2026 Worker version `c15e5e7b-26b9-446c-8ac6-0b348824a045`
makes the customer mobile bottom navigation bar full width (flush with edges, sides,
and bottom) with a clean top border/divider instead of the previous floating rounded card.
Customer preview shell in admin storefront builder shares the exact full-width styling.
Ships offline shell `web_shell_manifest.0869f37ab53c0bf2.json`.


- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `c15e5e7b-26b9-446c-8ac6-0b348824a045`
- Flutter version: `1.0.4+23`
- Offline shell version:
  `web_shell_manifest.0869f37ab53c0bf2.json`

The August 28, 2026 Worker version `442f9f6d-abd4-4b21-b3a2-99fe92d3061b`
drops "مقترح" from customer-facing reseller price labels: product cards,
catalog, product details, and storefront renderer now show **سعر البيع للتاجر**
instead of **سعر البيع المقترح للتاجر**, with compact cards using **بيع للتاجر**.
Ships offline shell `web_shell_manifest.dc4e927538a7318f.json`.


- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `442f9f6d-abd4-4b21-b3a2-99fe92d3061b`
- Flutter version: `1.0.4+23`
- Offline shell version:
  `web_shell_manifest.dc4e927538a7318f.json`

The August 27, 2026 Worker version `16313f35-4e7f-4cce-a10c-4cabe78379e4`
adds a horizontal product peek on phone homepage sections (featured, offers,
best selling, latest): two full cards plus ~18px of the next card so shoppers
know to scroll. Tablet/desktop keep grids; shared via `StorefrontHomeRenderer`.
Ships offline shell `web_shell_manifest.d97097d3689d1bdb.json`.


- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `16313f35-4e7f-4cce-a10c-4cabe78379e4`
- Flutter version: `1.0.4+22`
- Offline shell version:
  `web_shell_manifest.d97097d3689d1bdb.json`

The August 27, 2026 Worker version `446c46bf-1d7c-4206-841c-ed38042628a9`
slims homepage product sections (featured, offers, best selling, latest) to
match the compact categories spirit: tight headers, less cream padding,
rounded product images, flatter pricing chrome, and one phone row so the next
section peeks into the first viewport. Shared via `StorefrontHomeRenderer`.
Ships offline shell `web_shell_manifest.928ff396344f3de2.json`.


- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `446c46bf-1d7c-4206-841c-ed38042628a9`
- Flutter version: `1.0.4+21`
- Offline shell version:
  `web_shell_manifest.928ff396344f3de2.json`

The August 27, 2026 Worker version `55e3344e-1adb-41d8-a4e1-57db4f896730`
redesigns the customer homepage categories strip: compact slim header,
rounded symmetrical tiles, and a gentle auto-sliding horizontal rail so
featured products stay in the first phone viewport. Shared via
`StorefrontHomeRenderer` for admin preview parity. Ships offline shell
`web_shell_manifest.aafbef64757b4e42.json`.


- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `55e3344e-1adb-41d8-a4e1-57db4f896730`
- Flutter version: `1.0.4+20`
- Offline shell version:
  `web_shell_manifest.aafbef64757b4e42.json`

The August 26, 2026 Worker version `3b828517-c754-4e80-a308-060faafc2b8e`
removes the large beige dead zone under the storefront preview: the preview
frame now fills the canvas height, canvas padding is tighter, and on the
storefront builder the admin demo-mode banner sits flush under the preview.
Preview parity (customer shell chrome, phone+desktop only) remains. Ships
offline shell `web_shell_manifest.64bedf7a04fca7f7.json`.


- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `3b828517-c754-4e80-a308-060faafc2b8e`
- Flutter version: `1.0.4+19`
- Offline shell version:
  `web_shell_manifest.64bedf7a04fca7f7.json`

The August 26, 2026 Worker version `bfd4669e-a9f2-4164-bf52-cddf08924ef9`
removes the two parallel drag-handle lines beside storefront section
visibility eyes (`buildDefaultDragHandles: false` + no handle icon).
Reorder is long-press on the row; eye toggles unchanged. Ships offline
shell `web_shell_manifest.fcd114eca8910c43.json`.


- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `bfd4669e-a9f2-4164-bf52-cddf08924ef9`
- Flutter version: `1.0.4+17`
- Offline shell version:
  `web_shell_manifest.fcd114eca8910c43.json`

The August 26, 2026 Worker version `b99ad40b-107b-420d-a4cb-000f47cc3d3e`
restores admin storefront preview parity with the live customer shell: phone
portrait and desktop-only device modes, CustomerPreviewShell chrome (logo,
WhatsApp, logout, bottom nav / rail), and true desktop width constraints so
breakpoints match the real customer layout. Ships offline shell
`web_shell_manifest.4aaa1c7f4c9ad8b7.json`.


- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `b99ad40b-107b-420d-a4cb-000f47cc3d3e`
- Flutter version: `1.0.4+16`
- Offline shell version:
  `web_shell_manifest.4aaa1c7f4c9ad8b7.json`

The August 26, 2026 Worker version `28d12930-71be-4582-ba9c-6cc2c3da1863`
rounds uploaded shop logo corners via shared `ShopBrandLogo` (`ClipRRect`,
radius `size * 0.22` clamped to 8–12). Applies everywhere the widget is used
(customer shell, login, loading, admin shell, settings preview, app download).
Fallback paw badge stays circular when no logo is uploaded. Ships offline
shell `web_shell_manifest.90e185c1066363c4.json`.


- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `28d12930-71be-4582-ba9c-6cc2c3da1863`
- Flutter version: `1.0.4+15`
- Offline shell version:
  `web_shell_manifest.90e185c1066363c4.json`

The August 25, 2026 Worker version `2f2ac9e6-36a6-4d72-924b-3b8388a902f5`
restyles the mobile customer app-bar WhatsApp support action: green
`#25D366` icon without a solid green circle, subtle green pulse while
collapsed, and a light green pill only when the Arabic help prompt expands.
RTL placement and in-bar hit targets are unchanged. Ships offline shell
`web_shell_manifest.cd13bdd2973d0502.json`.


- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `2f2ac9e6-36a6-4d72-924b-3b8388a902f5`
- Flutter version: `1.0.4+14`
- Offline shell version:
  `web_shell_manifest.cd13bdd2973d0502.json`

The August 25, 2026 Worker version `67e9c9d7-f350-4b52-ac5f-4d103ee596d2`
shows uploaded shop logos directly (BoxFit.contain, no forced circular
theme-color badge) via the shared `ShopBrandLogo` widget in customer app bar,
login, loading screens, and admin settings preview. Default paw icon fallback
keeps the circular badge when no logo is uploaded. Ships offline shell
`web_shell_manifest.e59960711786b9f8.json`.


- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `67e9c9d7-f350-4b52-ac5f-4d103ee596d2`
- Flutter version: `1.0.4+13`
- Offline shell version:
  `web_shell_manifest.e59960711786b9f8.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project
- Firebase/web push: not configured (OS tray uses Service Worker `showNotification` while the tab/PWA can run; no Firebase keys were added)
- Search indexing: blocked intentionally with
  `X-Robots-Tag: noindex, nofollow, noarchive`
- Edge controls: HTTP-to-HTTPS redirect, HSTS, CSP, frame denial, MIME
  protection, permissions policy, and fresh-cache rules for the app shell

The August 25, 2026 Worker version `76b08253-e14c-4265-a951-b0470459e05e`
makes customer homepage category tiles minimal: image + category name only
(no per-tile product-count line), with a slightly tighter categories header.
Shared storefront renderer keeps admin preview 1:1. Ships offline shell
`web_shell_manifest.c62e32fda30978f9.json`.


- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `76b08253-e14c-4265-a951-b0470459e05e`
- Flutter version: `1.0.4+12`
- Offline shell version:
  `web_shell_manifest.c62e32fda30978f9.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project
- Firebase/web push: not configured (OS tray uses Service Worker `showNotification` while the tab/PWA can run; no Firebase keys were added)
- Search indexing: blocked intentionally with
  `X-Robots-Tag: noindex, nofollow, noarchive`
- Edge controls: HTTP-to-HTTPS redirect, HSTS, CSP, frame denial, MIME
  protection, permissions policy, and fresh-cache rules for the app shell

The August 25, 2026 Worker version `3f542c0e-6029-4212-a5ed-8d7f830441e7`
fixes truncated Arabic color labels in the storefront design panel (primary,
secondary, text, background, cards): labels get more flex space, wrap to 2
lines, and HEX fields shrink so RTL text is not ellipsized. Ships offline
shell `web_shell_manifest.9aba3d7d99346b78.json`.


- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `3f542c0e-6029-4212-a5ed-8d7f830441e7`
- Flutter version: `1.0.4+12`
- Offline shell version:
  `web_shell_manifest.9aba3d7d99346b78.json`

The August 25, 2026 Worker version `073cec0d-6260-4f3a-831d-6295e0795df1`
moves the mobile WhatsApp support IconButton to the visual right of the
compact customer app bar (AppBar `leading` in Arabic RTL; logout stays in
`actions` on the visual left). No FAB. Ships offline shell
`web_shell_manifest.7accbff41dfdff88.json`.


- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `073cec0d-6260-4f3a-831d-6295e0795df1`
- Flutter version: `1.0.4+11`
- Offline shell version:
  `web_shell_manifest.7accbff41dfdff88.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project
- Firebase/web push: not configured (OS tray uses Service Worker `showNotification` while the tab/PWA can run; no Firebase keys were added)
- Search indexing: blocked intentionally with
  `X-Robots-Tag: noindex, nofollow, noarchive`
- Edge controls: HTTP-to-HTTPS redirect, HSTS, CSP, frame denial, MIME
  protection, permissions policy, and fresh-cache rules for the app shell

The August 25, 2026 Worker version `e309817a-bb20-4cf1-ad12-bbe54282e1e6`
removes the mobile customer WhatsApp floating nudge FAB that stole scroll
and taps (InkWell + Align under Scaffold FAB). WhatsApp help is back in the
compact app-bar as `customer-mobile-support-action`. Ships offline shell
`web_shell_manifest.f3a46a5ec100a3bb.json`.


- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `e309817a-bb20-4cf1-ad12-bbe54282e1e6`
- Flutter version: `1.0.4+10`
- Offline shell version:
  `web_shell_manifest.f3a46a5ec100a3bb.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project
- Firebase/web push: not configured (OS tray uses Service Worker `showNotification` while the tab/PWA can run; no Firebase keys were added)
- Search indexing: blocked intentionally with
  `X-Robots-Tag: noindex, nofollow, noarchive`
- Edge controls: HTTP-to-HTTPS redirect, HSTS, CSP, frame denial, MIME
  protection, permissions policy, and fresh-cache rules for the app shell

The August 25, 2026 Worker version `883f11a6-c08b-42e9-82f2-248afc8945e9`
fixes storefront autosave/publish «خطأ في الحفظ»: RPCs wrote text
`'default'` into `audit_logs.entity_id` (uuid), so every save rolled back.
Migration `storefront_audit_entity_id_fix` uses `null` entity_id +
`configId` metadata. Flutter also surfaces PostgREST/DB details in mutation
toasts. Ships offline shell `web_shell_manifest.96445730ffb9218b.json`.


- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `883f11a6-c08b-42e9-82f2-248afc8945e9`
- Flutter version: `1.0.4+9`
- Offline shell version:
  `web_shell_manifest.96445730ffb9218b.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project
- Firebase/web push: not configured (OS tray uses Service Worker `showNotification` while the tab/PWA can run; no Firebase keys were added)
- Search indexing: blocked intentionally with
  `X-Robots-Tag: noindex, nofollow, noarchive`
- Edge controls: HTTP-to-HTTPS redirect, HSTS, CSP, frame denial, MIME
  protection, permissions policy, and fresh-cache rules for the app shell

The August 25, 2026 Worker version `e993e037-c815-4f80-930c-bbe3ac2ddede`
fixes storefront builder publish for color/theme edits via atomic
`admin_publish_storefront(p_expected_updated_at, p_draft_config)`, adds
debounced draft autosave (removes «حفظ المسودة»), and a red «إعادة ضبط»
reset-to-defaults control with confirmation. Ships offline shell
`web_shell_manifest.b023582a089baa38.json`. Requires DB migration
`20260825124326_storefront_publish_atomic_and_reset_defaults.sql`.


- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `e993e037-c815-4f80-930c-bbe3ac2ddede`
- Flutter version: `1.0.4+8`
- Offline shell version:
  `web_shell_manifest.b023582a089baa38.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project
- Firebase/web push: not configured (OS tray uses Service Worker `showNotification` while the tab/PWA can run; no Firebase keys were added)
- Search indexing: blocked intentionally with
  `X-Robots-Tag: noindex, nofollow, noarchive`
- Edge controls: HTTP-to-HTTPS redirect, HSTS, CSP, frame denial, MIME
  protection, permissions policy, and fresh-cache rules for the app shell

The August 23, 2026 Worker version `7acc8388-ef5c-4f3b-84c3-ca8b2dfa96da`
adds per-banner aspect mode (عريض / مربع 1:1), fills frames with `BoxFit.cover`
(no empty teal letterboxing), Arabic upload size guidance, shared carousel
height for admin mobile preview + customer home, and ships offline shell
`web_shell_manifest.d5556d5936b7cbb5.json`. Requires DB migration
`20260823210000_banner_aspect_mode.sql` (`banners.aspect_mode`, default `wide`).


- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `7acc8388-ef5c-4f3b-84c3-ca8b2dfa96da`
- Flutter version: `1.0.4+7`
- Offline shell version:
  `web_shell_manifest.d5556d5936b7cbb5.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project
- Firebase/web push: not configured (OS tray uses Service Worker `showNotification` while the tab/PWA can run; no Firebase keys were added)
- Search indexing: blocked intentionally with
  `X-Robots-Tag: noindex, nofollow, noarchive`
- Edge controls: HTTP-to-HTTPS redirect, HSTS, CSP, frame denial, MIME
  protection, permissions policy, and fresh-cache rules for the app shell

The August 22, 2026 Worker version `eaee92d5-6596-4aa8-a313-ea21013c0cfb`
adds admin banner archive + permanent delete from the ⋮ menu (Arabic
confirmations, مؤرشفة filter, restore, best-effort storage cleanup), ships
`banners.archived_at` soft-archive support, and offline shell
`web_shell_manifest.86aed162930182f1.json`.

The August 22, 2026 Worker version `19a2c625-c7ba-48d7-b7d3-3aa6297873b7`
adds an optional Arabic storefront-builder toggle («تطبيق على لوحة الإدارة»)
that paints AdminShell with the current draft storefront theme via
`storefrontThemeData`, persisted locally in SharedPreferences (default off),
and ships offline shell `web_shell_manifest.403addf2a27aa884.json`.

The August 22, 2026 Worker version `44a6f8f4-de22-4eb4-a62d-0a67a7beb80e`
improves admin storefront color editing: tappable swatch opens a bottom-sheet
HSV/RGB picker with presets and LTR HEX entry (fixes RTL-mangled `#` display),
exposes secondary/card theme colors, and keeps live draft preview local.
Ships offline shell `web_shell_manifest.dc8169e5b0a97e1d.json`.

This hostname now uses compile-time production mode and the public Supabase
URL/anon key. Staging demo logins (`admin`/`admin` overlay) are disabled.
Firebase public keys remain empty, so push delivery stays labelled
“not configured.” Keep `*.workers.dev` `noindex` until a custom domain and
client-approved catalog are accepted. Record the new version ID after every
release.

The August 19, 2026 Worker version `5429e4ef-fc78-47ef-8543-46dee3774d5b`
replaces the pull-to-refresh arrow morph with a frosted-glass HUD and ring
spinner, fixes an admin category refresh regression test, and ships offline shell
`web_shell_manifest.5487e61226f81784.json`.

The August 19, 2026 Worker version `24d2e03a-81ad-4c7f-b0eb-71ded6c71512`
redesigns admin إدارة المنتجات for routine ops without the full editor:
operational product cards with quick price/discount/stock sheets, featured and
visibility toggles with undo snackbars, filter shortcuts (العروض/المميزة/المخزون),
multi-select bulk discount and price adjustments, and preserved search/filter/sort/
pagination/full editor/archive flows; ships offline shell
`web_shell_manifest.8189797522ebfce6.json`.

The August 19, 2026 Worker version `687cf063-e633-4816-beaf-b89bc05e26a9`
adds a persisted 3-mode catalog view toggle on the customer المنتجات screen
(comfortable list, compact list, responsive grid), keeps RTL-safe controls near
search/filter, and ships the hashed offline shell
`web_shell_manifest.2e34f235359e1bd5.json`.

The August 19, 2026 Worker version `0cf9be73-ab8c-4948-9178-0a5a4bbe964c`
polishes the customer shell and home: a teal-gradient app bar with a white
logo disc and translucent circular WhatsApp/logout buttons, a typographic
greeting block with a full-width search pill, white category chips with
pastel icon discs, product cards with a gradient للسلة button and stronger
سعر الجملة hierarchy, and softer teal-tinted banner shadows, and ships the
hashed offline shell `web_shell_manifest.cfc8f9652024d426.json`.

The August 19, 2026 Worker version `78732df4-5eaa-4b7d-acdc-90c84ec5906e`
redesigns the cart screen: white line-item cards with `BoxFit.contain`
thumbnails, a grouped quantity stepper / line-total band, a dark-green
ملخص الطلب summary card, and a prominent sticky متابعة تأكيد الطلب bar,
and ships the hashed offline shell
`web_shell_manifest.9e8f5ac0a33a5541.json`.

The August 19, 2026 Worker version `5b086d04-12d0-4bb5-ae3d-3f29a61ac63c`
redesigns product details with a larger `BoxFit.contain` hero, grouped info
and wholesale-price cards (سعر الجملة in black), a sticky quantity / add-to-cart
/ WhatsApp bar, and ships the hashed offline shell
`web_shell_manifest.15357f8fa5633e6f.json`.

The August 19, 2026 Worker version `35a03363-80ea-4087-b6ae-d18cd94e38e7`
fits the customer-home first screen on a typical phone without vertical
scroll, uses a peeking PageView for banners and أحدث المنتجات with
`BoxFit.contain` photos, shows the product thumbnail in the add-to-cart
quantity sheet, paints سعر الجملة in near-black, and ships the hashed
offline shell `web_shell_manifest.15357f8fa5633e6f.json`.

The August 18, 2026 Worker version `c739a279-b457-4170-aa47-aefac3ee4e57`
labels the teal wholesale amount on customer-home and catalog product cards
as سعر الجملة, keeps بيع الوحدة / بيع الوحدة المقترح under it, and ships
the hashed offline shell `web_shell_manifest.4bfae53f8de847ef.json`.

The August 18, 2026 Worker version `0472d2c2-4517-43a4-a654-b58ca9470c9c`
enriches customer-home and catalog product cards with brand, pack size,
availability, wholesale price, and suggested unit price, and ships the hashed
offline shell `web_shell_manifest.deafb7277446f9a1.json`.

The August 18, 2026 Worker version `9c706d6b-7592-4e52-b906-a8eef495fffd`
redesigns customer-home latest-product cards (white bordered tiles, square
cover photos, two-line Arabic titles, inset add button) and ships the hashed
offline shell `web_shell_manifest.6a9de4233f925241.json`.

The August 18, 2026 Worker version `6047f6c2-58f4-4dc5-9dd7-0a963171d179`
stretches catalog list-card images to the full card height (RTL start
edge, clipped to the card corners) and ships the hashed offline shell
`web_shell_manifest.b7d0bec5a58a2408.json`.

The August 16, 2026 Worker version `e630c843-2e68-49fc-8c0a-14ceda0a6f1b`
improves checkout confirm-order hierarchy (grouped bordered text fields,
separated order review, darker estimated-total card, stronger green CTA)
and ships the hashed offline shell
`web_shell_manifest.250ab11d409d27d8.json`.

The earlier August 16, 2026 deployment was verified against the exact local
`main.dart.js`, contains a 76-resource content-hashed offline shell, and
loads a no-op `firebase_bootstrap.js`. Login uses real Supabase Auth.
Web product, banner, and logo uploads read file bytes in memory instead of
fetching a revoked `blob:` URL.

## Client-review demo

This build intentionally uses local demo data and does not connect to a remote
Supabase or Firebase project:

```bash
cd /home/alnaagi/Desktop/animal_supply_b2b_app/app

/home/alnaagi/development/flutter/bin/flutter pub get
/home/alnaagi/development/flutter/bin/flutter analyze
/home/alnaagi/development/flutter/bin/flutter test

FLUTTER_BIN=/home/alnaagi/development/flutter/bin/flutter \
  node tool/build_web_release.mjs \
  --release \
  --no-web-resources-cdn \
  --dart-define=APP_ENV=demo

cd /home/alnaagi/Desktop/animal_supply_b2b_app
npx --yes wrangler@4.121.0 deploy
```

The review hostname is intentionally sent with a `noindex` response header.
Do not remove the demo labels or make the site indexable until the real
catalog, client contact details, backend, and notification configuration are
approved.

The Worker is part of the release boundary. Validate it before deployment:

```bash
cd /home/alnaagi/Desktop/animal_supply_b2b_app
node --test app/tool/*.test.mjs cloudflare/*.test.mjs
npx --yes wrangler@4.121.0 deploy --dry-run
```

## Production build

Copy the tracked example and enter only public client configuration:

```bash
cd /home/alnaagi/Desktop/animal_supply_b2b_app
cp cloudflare.public.example.json cloudflare.public.json
```

`cloudflare.public.json` is ignored by Git. It may contain the Supabase anon
key and Firebase web client configuration because those values are delivered
to browsers by design. It must never contain a Supabase service-role key,
Firebase service-account JSON, private signing material, database passwords,
or any other server secret.

Build and deploy:

```bash
cd /home/alnaagi/Desktop/animal_supply_b2b_app/app

FLUTTER_BIN=/home/alnaagi/development/flutter/bin/flutter \
  node tool/build_web_release.mjs \
  --release \
  --no-web-resources-cdn \
  --dart-define-from-file=../cloudflare.public.json

cd /home/alnaagi/Desktop/animal_supply_b2b_app
npx --yes wrangler@4.121.0 deploy
```

Do not use a raw `flutter build web` for a release. The wrapper generates the
content-hashed shell manifest required by the app's atomic offline-update
service worker.

## Exact production-launch checklist

Complete every item before switching `APP_ENV` to `production`:

1. Obtain written approval for the client name, branding, support contacts,
   legal/delivery text, real catalog, prices, MOQ, stock, and licensed images.
2. Put the domain, Cloudflare zone, Supabase project, Firebase project, Apple
   account, Android signing backup, and billing under client-controlled
   ownership.
3. Back up any existing Supabase data. Run
   `supabase/production_preflight.sql`, resolve every finding, link the intended
   project, and apply the ordered migrations with `supabase db push`.
4. Disable public Auth sign-up and verify admin, staff, active customer,
   suspended customer, and archived customer behavior using real RLS
   integration tests. Do not continue if any client can bypass an Edge
   Function or read another customer's rows.
5. Configure only public values in `cloudflare.public.json`. Put service-role,
   notification-dispatch, Firebase service-account, and invite secrets only in
   Supabase Edge Function secrets.
6. Deploy every Edge Function listed in `supabase/README.md`; set the exact
   production origin in `ALLOWED_ORIGINS` (wildcards and implicit localhost
   access are rejected), a random server-only `RATE_LIMIT_SALT` of at least 32
   characters, the final HTTPS `/invite` URL in `INVITE_BASE_URL`, and the same
   real `CUSTOMER_LOGIN_DOMAIN` in Flutter and the functions.
7. Audit existing `product-images` objects before allowing public reads, then
   import only client-approved catalog data and image assets.
8. Configure Firebase Android, iOS/APNs, and web/VAPID values; schedule
   `dispatch-notification-outbox`; test order, targeted, broadcast, and
   product deep-link notifications on physical devices and the final web
   origin.
9. Build with the release wrapper, deploy to the final custom domain, and test
   login, forced password change, role redirects, invite links, ordering,
   admin transitions, customer updates, reload/deep links, service-worker
   upgrades, and offline reopen.
10. Keep the review hostname `noindex`. The Worker refuses to index
    `*.workers.dev` even if configured otherwise. Set the Cloudflare
    `ALLOW_INDEXING=true` environment variable only on the accepted custom
    domain and only after confirming no demo labels, placeholder contacts,
    sample prices, or test accounts are exposed.
11. Build Android and iOS through their platform handoff checklists and
    publish their controlled update destinations. For Android, insert matching
    `app_versions` metadata only after signature, version, URL, and checksum
    verification; iOS updates remain governed by TestFlight/App Store or the
    registered-device Ad Hoc process.
12. Deliver backups, recovery instructions, account ownership, monitoring,
    maintenance scope, and signed acceptance to the client.

## APK and custom domain

The signed APK and AAB are larger than the per-file limit for Workers Static
Assets and are not bundled into this web deployment. Enable Cloudflare R2 or
use another controlled download host, upload the signed APK, verify its
SHA-256 checksum, then set `APK_LINK` and the `app_versions.apk_url` value.

R2 is not enabled on the current Cloudflare account. The August 11, 2026
Wrangler preflight returned Cloudflare error `10042`. Enable R2 in the
Cloudflare dashboard or approve another client-controlled HTTPS artifact host
before publishing the direct APK link.

Use the permanent client domain before printing public QR codes or enrolling
users in web push notifications. Browser installs and push permissions are
tied to the exact web origin.

For iPhone/iPad distribution, the Cloudflare PWA can be shared immediately,
but a native `.ipa` cannot be installed by arbitrary customers from this
Worker or Google Drive. Follow `DEPLOYMENT_IOS.md`.

The 2026-08-19 17:30:49 EET (+0200) Worker version `0376346c-b843-487a-a649-baf3400979f0` is a final explicit deploy after stabilization.

The 2026-08-19 18:39 EET (+0200) Worker version `10f828fb-212f-47e0-a718-07c53d5c74be` deploys the focused order-completion integration: legacy `/order-success` URLs now redirect safely into `/orders`, checkout success navigates to `/orders?order=<id>&success=1` inside `CustomerShell`, and admin/customer invoice print + download now share a single canonical Arabic RTL PDF byte generator (`OrderInvoicePdf`) using `assets/fonts/NotoSansArabic-Variable.ttf`.

The 2026-08-19 19:16 EET (+0200) Worker version `34c006ae-ac57-4843-9606-7125cc7ebe61` deploys public-order-reference hardening: server-side random `AS-XXXXXXX` order references (with collision retry and secure backfill) plus admin reference normalization support (`AS-...`, lowercase, or prefix-less).

The 2026-08-19 20:07 EET (+0200) Worker version `ec5ad2fc-7c26-4d53-8c86-cc60a08dc6fa` deploys the focused Admin Banners UX redesign: compact management toolbar, modal store preview with mobile/desktop toggle, reorder-first compact cards with human-readable destinations, optimistic active toggle with rollback/undo, duplicate-banner flow, and live editor preview.

The 2026-08-19 21:45 EET (+0200) Worker version `6e4198f0-8979-4577-8011-45c5408be2e1` on branch `release/production-readiness-2026-08` (`69d8112`) ships production-readiness reconciliation: Supabase migrations for product discount constraints, customer device binding via `device_tokens.installation_id_hash`, random `AS-XXXXXXX` order references with legacy `AS-YYYYMMDD-NNNNNN` lookup preserved, admin password policy enforcement in Edge Functions, and offline shell `web_shell_manifest.4018ff43cc4d6d6e.json`.

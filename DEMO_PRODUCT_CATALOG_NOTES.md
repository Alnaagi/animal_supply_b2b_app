# Demo Product Catalog Notes

## What Was Added

The demo catalog now contains 40 realistic sample products, with 5 products in each category:

- قطط
- كلاب
- طيور
- أسماك
- مواشي
- مستلزمات
- تنظيف
- مكملات

Products use common brand and product-style names such as Royal Canin, Purina Pro Plan, Whiskas, Pedigree, Josera, Happy Dog, Tetra, Versele-Laga, Vitakraft, Catsan, Biokats, Beaphar, and generic livestock feed items.

## Demo Only

This catalog is sample presentation/testing data only. It is not the client inventory, not a supplier agreement, and not a production price list.

الأسعار الموجودة في النسخة التجريبية افتراضية وليست أسعار بيع فعلية.

Before production, replace all product names, prices, stock levels, descriptions, images, package sizes, and supplier/brand references with the client-approved catalog.

## Image Licensing Warning

The app uses generic external placeholder image URLs from `placehold.co` for demo rendering. It does not permanently copy manufacturer product images into the repository.

If manufacturer or distributor product images are used later:

- Keep proof that the client has permission to use them.
- Prefer uploading approved images to Supabase Storage.
- Store only the Supabase Storage URL/path in product records.
- Do not copy unclear-license images into the repository.

## Replace Images With Supabase Storage

1. Create or confirm the `product-images` bucket.
2. Upload approved images under paths like `products/{sku}.jpg`.
3. Save the public URL or signed URL path in `products.image_url`.
4. Optionally save the original approved source/reference in `products.source_url`.

## Import Real Catalog Later

Use `docs/product_import_template.csv` as a starting point for CSV import. The admin dashboard can later add a CSV importer that maps rows to:

- `categories`
- `products`
- `product_prices`
- `customer_special_prices`

Recommended production import flow:

1. Client exports approved catalog from POS/ERP/spreadsheet.
2. Clean SKUs and category names.
3. Upload product images to Supabase Storage.
4. Import CSV into staging tables.
5. Validate required fields and duplicates.
6. Upsert into production `products`.

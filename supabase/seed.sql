insert into price_groups (id, name, description) values
('00000000-0000-0000-0000-000000000101','أساسي','السعر الأساسي'),
('00000000-0000-0000-0000-000000000102','جملة','سعر الجملة'),
('00000000-0000-0000-0000-000000000103','خاص','أسعار خاصة')
on conflict do nothing;

insert into categories (id, name, icon_key) values
('00000000-0000-0000-0000-000000000201','قطط','cat'),
('00000000-0000-0000-0000-000000000202','كلاب','dog'),
('00000000-0000-0000-0000-000000000203','طيور','bird'),
('00000000-0000-0000-0000-000000000204','أسماك','fish'),
('00000000-0000-0000-0000-000000000205','مواشي','livestock'),
('00000000-0000-0000-0000-000000000206','مستلزمات','supplies'),
('00000000-0000-0000-0000-000000000207','تنظيف','cleaning'),
('00000000-0000-0000-0000-000000000208','مكملات','supplements')
on conflict do nothing;

insert into products
(category_id, name, name_en, sku, brand, description, animal_type, unit_size, package_size, base_price, old_price, discount_percent, stock_quantity, min_order_quantity, image_url, source_url, tags, active, is_featured, is_top_selling)
values
('00000000-0000-0000-0000-000000000201','رويال كانين طعام قطط بالغة Fit 32 - 2 كجم','Royal Canin Fit 32 Adult Cat Food 2kg','RC-CAT-FIT32-2KG','Royal Canin','طعام جاف للقطط البالغة. بيانات وسعر تجريبيان فقط.','قطط','2 كجم','كيس 2 كجم',96,110,13,34,2,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['قطط','جاف','demo'],true,true,true),
('00000000-0000-0000-0000-000000000201','بورينا برو بلان قطط معقمة سلمون - 1.5 كجم','Purina Pro Plan Sterilised Cat Salmon 1.5kg','PP-CAT-STER-SAL-1-5','Purina Pro Plan','تركيبة جافة للقطط المعقمة بنكهة السلمون.','قطط','1.5 كجم','كيس 1.5 كجم',88,null,null,28,3,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['قطط','سلمون'],true,true,true),
('00000000-0000-0000-0000-000000000201','ويسكاس طعام قطط جاف بالدجاج - 3 كجم','Whiskas Adult Dry Cat Food Chicken 3kg','WH-CAT-CHK-3KG','Whiskas','طعام قطط جاف بنمط تجاري شائع.','قطط','3 كجم','كيس 3 كجم',72,82,12,46,4,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['قطط','دجاج'],true,false,true),
('00000000-0000-0000-0000-000000000201','جوسيرا كاتيلوكس طعام قطط - 2 كجم','Josera Catelux Cat Food 2kg','JO-CAT-CATELUX-2KG','Josera','منتج بأسلوب كتالوج جوسيرا للعرض التجريبي.','قطط','2 كجم','كيس 2 كجم',83,null,null,22,2,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['قطط','جوسيرا'],true,false,false),
('00000000-0000-0000-0000-000000000201','فريسكيز طعام قطط تونة وخضار - 1.7 كجم','Friskies Cat Food Tuna & Vegetables 1.7kg','FR-CAT-TUNA-1-7','Friskies','طعام قطط جاف بنكهة التونة والخضار.','قطط','1.7 كجم','كيس 1.7 كجم',54,null,null,31,4,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['قطط','تونة'],true,false,false),
('00000000-0000-0000-0000-000000000202','رويال كانين طعام كلاب متوسطة بالغة - 4 كجم','Royal Canin Medium Adult Dog Food 4kg','RC-DOG-MED-4KG','Royal Canin','طعام جاف للكلاب المتوسطة البالغة.','كلاب','4 كجم','كيس 4 كجم',152,170,11,24,2,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['كلاب','adult'],true,true,true),
('00000000-0000-0000-0000-000000000202','بيديجري طعام كلاب بالدجاج والخضار - 3 كجم','Pedigree Adult Dog Food Chicken & Vegetables 3kg','PD-DOG-CHKVEG-3KG','Pedigree','طعام كلاب جاف بنكهة الدجاج والخضار.','كلاب','3 كجم','كيس 3 كجم',68,null,null,52,4,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['كلاب','دجاج'],true,false,true),
('00000000-0000-0000-0000-000000000202','بورينا برو بلان كلاب متوسطة بالغة - 3 كجم','Purina Pro Plan Medium Adult Dog Food 3kg','PP-DOG-MED-3KG','Purina Pro Plan','طعام كلاب بنمط برو بلان للعرض التجريبي.','كلاب','3 كجم','كيس 3 كجم',118,null,null,19,2,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['كلاب','بروتين'],true,true,false),
('00000000-0000-0000-0000-000000000202','هابي دوج NaturCroq بالغ - 4 كجم','Happy Dog NaturCroq Adult 4kg','HD-DOG-NC-4KG','Happy Dog','طعام جاف للكلاب بأسلوب منتج أوروبي شائع.','كلاب','4 كجم','كيس 4 كجم',105,null,null,17,2,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['كلاب','happy dog'],true,false,false),
('00000000-0000-0000-0000-000000000202','جوسيرا فيستيفال طعام كلاب - 12.5 كجم','Josera Festival Dog Food 12.5kg','JO-DOG-FEST-12-5','Josera','كيس كبير مناسب للطلبات التجارية والمتاجر.','كلاب','12.5 كجم','كيس 12.5 كجم',285,315,10,11,1,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['كلاب','جملة'],true,true,true),
('00000000-0000-0000-0000-000000000203','فيرسيل لاغا بريستيج طعام بادجي - 1 كجم','Versele-Laga Prestige Budgies 1kg','VL-BRD-BUDG-1KG','Versele-Laga','خلطة حبوب للبادجي بنمط منتج شائع.','طيور','1 كجم','كيس 1 كجم',32,null,null,68,6,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['طيور','بادجي'],true,false,true),
('00000000-0000-0000-0000-000000000203','فيتاكرافت Menu Vital طعام كناري - 1 كجم','Vitakraft Menu Vital Canary Food 1kg','VK-BRD-CAN-1KG','Vitakraft','طعام كناري بخلطة حبوب تجريبية للعرض.','طيور','1 كجم','كيس 1 كجم',35,40,13,40,6,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['طيور','كناري'],true,true,false),
('00000000-0000-0000-0000-000000000203','خلطة بذور ببغاء - 2 كجم','Mixed Parrot Seeds 2kg','GN-BRD-PARROT-2KG','Generic Feed','خلطة بذور عامة للببغاوات مناسبة للمحلات.','طيور','2 كجم','كيس 2 كجم',44,null,null,37,4,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['طيور','ببغاء'],true,false,true),
('00000000-0000-0000-0000-000000000203','خلطة بذور فينش - 1 كجم','Finch Seed Mix 1kg','GN-BRD-FINCH-1KG','Generic Feed','خلطة بذور للطيور الصغيرة بعبوة مناسبة للرفوف.','طيور','1 كجم','كيس 1 كجم',24,null,null,55,8,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['طيور','finch'],true,false,false),
('00000000-0000-0000-0000-000000000203','بلوك معادن للطيور - عبوة 12 قطعة','Bird Mineral Block Pack','GN-BRD-MINBLK-12','Generic Supplies','بلوك معادن للطيور في عبوة جملة.','طيور','12 قطعة','كرتون 12 قطعة',58,null,null,23,2,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['طيور','معادن'],true,false,false),
('00000000-0000-0000-0000-000000000204','تترا رقائق طعام أسماك TetraMin - 100 مل','TetraMin Fish Flakes 100ml','TT-FSH-MIN-100ML','Tetra','رقائق طعام أسماك بنمط TetraMin الشائع.','أسماك','100 مل','علبة 100 مل',28,null,null,44,6,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['أسماك','tetra'],true,true,true),
('00000000-0000-0000-0000-000000000204','تترا رقائق جولد فيش - 100 مل','Tetra Goldfish Flakes 100ml','TT-FSH-GOLD-100ML','Tetra','رقائق للأسماك الذهبية. السعر تجريبي.','أسماك','100 مل','علبة 100 مل',27,null,null,38,6,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['أسماك','goldfish'],true,false,true),
('00000000-0000-0000-0000-000000000204','حبيبات طعام أسماك استوائية - 250 مل','Tropical Fish Granules 250ml','GN-FSH-GRAN-250ML','Generic Aqua','حبيبات طعام للأسماك الاستوائية.','أسماك','250 مل','علبة 250 مل',36,null,null,29,4,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['أسماك','granules'],true,false,false),
('00000000-0000-0000-0000-000000000204','محسن مياه أحواض الأسماك - 250 مل','Aquarium Water Conditioner 250ml','GN-FSH-WATER-250ML','Generic Aqua','محسن مياه عام لأحواض الأسماك.','أسماك','250 مل','عبوة 250 مل',42,null,null,16,3,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['أسماك','مياه'],true,true,false),
('00000000-0000-0000-0000-000000000204','أقراص تغذية للأسماك القاعية - 100 جم','Fish Feeding Tablets 100g','GN-FSH-TAB-100G','Generic Aqua','أقراص تغذية للأسماك القاعية.','أسماك','100 جم','علبة 100 جم',34,null,null,21,4,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['أسماك','tablets'],true,false,false),
('00000000-0000-0000-0000-000000000205','علف دجاج بيّاض - 25 كجم','Poultry Layer Feed 25kg','LV-POU-LAYER-25KG','Generic Livestock Feed','علف دجاج بياض عام للعرض التجريبي.','دواجن','25 كجم','كيس 25 كجم',118,null,null,90,5,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['دواجن','علف'],true,true,true),
('00000000-0000-0000-0000-000000000205','علف بادئ تسمين دجاج - 25 كجم','Broiler Starter Feed 25kg','LV-BRO-START-25KG','Generic Livestock Feed','علف بادئ تسمين للدواجن، سعر demo فقط.','دواجن','25 كجم','كيس 25 كجم',124,null,null,76,5,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['دواجن','تسمين'],true,false,true),
('00000000-0000-0000-0000-000000000205','خلطة علف أغنام - 40 كجم','Sheep Feed Mix 40kg','LV-SHP-MIX-40KG','Generic Livestock Feed','خلطة علف أغنام عامة للعرض.','أغنام','40 كجم','كيس 40 كجم',172,null,null,43,3,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['أغنام','علف'],true,false,false),
('00000000-0000-0000-0000-000000000205','حبيبات علف أبقار - 40 كجم','Cattle Feed Pellets 40kg','LV-CAT-PEL-40KG','Generic Livestock Feed','حبيبات علف أبقار عامة.','أبقار','40 كجم','كيس 40 كجم',188,null,null,36,3,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['أبقار','pellets'],true,true,false),
('00000000-0000-0000-0000-000000000205','حبيبات علف أرانب - 20 كجم','Rabbit Feed Pellets 20kg','LV-RAB-PEL-20KG','Generic Livestock Feed','حبيبات علف أرانب للمتاجر والمزارع الصغيرة.','أرانب','20 كجم','كيس 20 كجم',92,null,null,27,4,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['أرانب','علف'],true,false,false)
on conflict (sku) do update set
name = excluded.name,
name_en = excluded.name_en,
brand = excluded.brand,
description = excluded.description,
animal_type = excluded.animal_type,
unit_size = excluded.unit_size,
package_size = excluded.package_size,
base_price = excluded.base_price,
old_price = excluded.old_price,
discount_percent = excluded.discount_percent,
stock_quantity = excluded.stock_quantity,
min_order_quantity = excluded.min_order_quantity,
image_url = excluded.image_url,
source_url = excluded.source_url,
tags = excluded.tags,
active = excluded.active,
is_featured = excluded.is_featured,
is_top_selling = excluded.is_top_selling;

insert into products
(category_id, name, name_en, sku, brand, description, animal_type, unit_size, package_size, base_price, old_price, discount_percent, stock_quantity, min_order_quantity, image_url, source_url, tags, active, is_featured, is_top_selling)
values
('00000000-0000-0000-0000-000000000206','صندوق رمل قطط بلاستيك كبير','Cat Litter Box Large','SUP-CAT-LBOX-L','Generic Supplies','صندوق رمل بلاستيك للمحلات. منتج عام للعرض التجريبي.','قطط','قطعة','كرتون 6 قطع',210,null,null,18,1,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['مستلزمات','قطط'],true,true,true),
('00000000-0000-0000-0000-000000000206','وعاء طعام ستانلس ستيل متوسط','Stainless Steel Pet Bowl Medium','SUP-BOWL-SS-M','Generic Supplies','أوعية ستانلس للمحلات والعيادات. سعر demo فقط.','عام','قطعة','كرتون 24 قطعة',168,null,null,64,1,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['وعاء','ستانلس'],true,false,true),
('00000000-0000-0000-0000-000000000206','طوق كلاب مقاس متوسط','Dog Collar Medium','SUP-DOG-COL-M','Generic Supplies','أطواق كلاب متوسطة بتشكيلة ألوان للعرض التجاري.','كلاب','قطعة','كرتون 12 قطعة',150,175,14,41,1,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['كلاب','طوق'],true,false,false),
('00000000-0000-0000-0000-000000000206','حاملة حيوانات متوسطة','Pet Carrier Medium','SUP-CARRIER-M','Generic Supplies','حاملة متوسطة للقطط والكلاب الصغيرة. منتج عام للتجربة.','عام','قطعة','كرتون 4 قطع',340,null,null,9,1,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['حاملة','سفر'],true,true,false),
('00000000-0000-0000-0000-000000000206','فرشاة تمشيط للحيوانات','Grooming Brush','SUP-GROOM-BR','Generic Supplies','فرشاة تمشيط للقطط والكلاب. مناسبة للبيع بالجملة.','عام','قطعة','كرتون 24 قطعة',132,null,null,33,1,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['تمشيط','grooming'],true,false,false),
('00000000-0000-0000-0000-000000000207','كاتسان رمل قطط - 10 لتر','Catsan Cat Litter 10L','CS-LIT-10L','Catsan','رمل قطط بنمط Catsan للعرض التجريبي. استخدم صوراً مرخصة فقط في الإنتاج.','قطط','10 لتر','كيس 10 لتر',49,null,null,48,4,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['رمل','قطط'],true,true,true),
('00000000-0000-0000-0000-000000000207','بيوكاتس كلاسيك رمل قطط - 10 لتر','Biokats Classic Cat Litter 10L','BK-LIT-CLASSIC-10L','Biokats','رمل قطط كلاسيك بنمط منتج شائع. السعر تجريبي.','قطط','10 لتر','كيس 10 لتر',54,62,13,30,4,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['رمل','biokats'],true,false,true),
('00000000-0000-0000-0000-000000000207','بخاخ إزالة روائح الحيوانات - 500 مل','Pet Odor Remover Spray 500ml','CLN-ODOR-500ML','Generic Cleaning','بخاخ عام لإزالة الروائح. منتج placeholder للعرض.','عام','500 مل','كرتون 12 عبوة',96,null,null,26,1,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['تنظيف','روائح'],true,false,false),
('00000000-0000-0000-0000-000000000207','بخاخ تنظيف أقفاص - 500 مل','Cage Cleaning Spray 500ml','CLN-CAGE-500ML','Generic Cleaning','بخاخ تنظيف أقفاص للطيور والحيوانات الصغيرة. بيانات تجريبية.','طيور','500 مل','كرتون 12 عبوة',84,null,null,14,1,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['أقفاص','تنظيف'],true,false,false),
('00000000-0000-0000-0000-000000000207','رولات أكياس فضلات الحيوانات - عبوة 20 رول','Waste Bags Roll Pack','CLN-WASTE-20ROLL','Generic Cleaning','أكياس فضلات بتعبئة جملة للمتاجر. السعر demo.','كلاب','20 رول','كرتون 20 رول',120,null,null,39,1,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['أكياس','كلاب'],true,true,false),
('00000000-0000-0000-0000-000000000208','بيفار معجون فيتامينات للقطط','Beaphar Vitamin Paste for Cats','BP-CAT-VIT-PASTE','Beaphar','معجون فيتامينات بنمط Beaphar للعرض التجريبي. تحقق من التسجيلات والتراخيص قبل البيع الحقيقي.','قطط','100 جم','كرتون 12 أنبوب',156,null,null,12,1,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['فيتامين','قطط'],true,true,true),
('00000000-0000-0000-0000-000000000208','قطرات ملتي فيتامين للطيور - 30 مل','Multivitamin Drops for Birds','VT-BRD-MULTI-30ML','Generic Supplements','قطرات فيتامينات للطيور. منتج عام للعرض.','طيور','30 مل','كرتون 24 عبوة',144,null,null,25,1,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['طيور','فيتامين'],true,false,true),
('00000000-0000-0000-0000-000000000208','بلوك كالسيوم للطيور - عبوة 12','Calcium Block for Birds','VT-BRD-CAL-12','Generic Supplements','بلوك كالسيوم للطيور بتعبئة جملة. السعر تجريبي.','طيور','12 قطعة','عبوة 12 قطعة',52,null,null,47,2,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['كالسيوم','طيور'],true,false,false),
('00000000-0000-0000-0000-000000000208','زيت أوميغا للكلاب - 250 مل','Omega Oil Supplement for Dogs','VT-DOG-OMEGA-250ML','Generic Supplements','زيت أوميغا للكلاب ضمن بيانات demo، ليس توصية طبية.','كلاب','250 مل','كرتون 12 عبوة',198,220,10,10,1,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['كلاب','أوميغا'],true,true,false),
('00000000-0000-0000-0000-000000000208','مكمل دعم الهضم للحيوانات - 60 قرص','Digestive Support Supplement 60 Tablets','VT-PET-DIGEST-60','Generic Supplements','مكمل دعم الهضم للعرض التجريبي فقط. يجب اعتماد المنتج من العميل قبل الإنتاج.','عام','60 قرص','علبة 60 قرص',89,null,null,18,2,'https://placehold.co/600x600/e9f4ee/168a63/png?text=Animal+Supply','https://placehold.co/',array['هضم','مكملات'],true,false,false)
on conflict (sku) do update set
name = excluded.name,
name_en = excluded.name_en,
brand = excluded.brand,
description = excluded.description,
animal_type = excluded.animal_type,
unit_size = excluded.unit_size,
package_size = excluded.package_size,
base_price = excluded.base_price,
old_price = excluded.old_price,
discount_percent = excluded.discount_percent,
stock_quantity = excluded.stock_quantity,
min_order_quantity = excluded.min_order_quantity,
image_url = excluded.image_url,
source_url = excluded.source_url,
tags = excluded.tags,
active = excluded.active,
is_featured = excluded.is_featured,
is_top_selling = excluded.is_top_selling;

-- Demo-only retail references. Replace these generated presentation values
-- with client-approved reseller prices before production.
update products
set retail_unit_price = round(
  coalesce(old_price, base_price * 1.20),
  2
)
where retail_unit_price is null;

insert into app_settings (key, value) values
('shop_name','متجر أعلاف ومستلزمات الحيوانات'),
('shop_logo_url',''),
('shop_whatsapp',''),
('support_whatsapp',''),
('download_link',''),
('apk_link',''),
('delivery_policy','يتم الاتفاق على التسليم بعد تأكيد الطلب.'),
('currency','LYD'),
('minimum_order_amount','0'),
('delivery_fee','0'),
('handling_fee','0'),
('maintenance_mode','false'),
('demo_price_notice','الأسعار الموجودة في النسخة التجريبية افتراضية وليست أسعار بيع فعلية.')
on conflict (key) do update set value = excluded.value;

insert into app_versions (platform, version_name, version_code, minimum_supported_code, apk_url, required_update, release_notes, published)
values ('android', '1.0.4', 5, 1, null, false, 'إصدار تجريبي محسن للإطلاق يضيف صفحة توزيع آمنة، إشعارات موجهة حسب الدور، عداداً دقيقاً، وتسعير الجملة وضوابط المخزون. أضف رابط APK الموقّع وبصمته وحجمه قبل النشر.', false)
on conflict (platform, version_code) do update set
minimum_supported_code = excluded.minimum_supported_code,
apk_url = excluded.apk_url,
required_update = excluded.required_update,
release_notes = excluded.release_notes,
published = excluded.published,
updated_at = now();

insert into banners (title, body, image_url, cta_text, target_type, target_value, sort_order, active)
values
('عروض خاصة لتجار مستلزمات الحيوانات','اطلب الأعلاف والمستلزمات بالجملة بسهولة','https://images.unsplash.com/photo-1714068691210-073dc52c6c1d?auto=format&fit=crop&w=1600&h=620&q=80','تسوق الآن','category','كلاب',1,true),
('توريد أكل قطط للمحال والعيادات','منتجات مختارة بكميات جملة وحد أدنى مناسب للطلبات','https://images.unsplash.com/photo-1520811607976-6d7812b0ecac?auto=format&fit=crop&w=1600&h=620&q=80','منتجات القطط','category','قطط',2,true);

-- Demo Auth users must be created manually or through Edge Functions first.
-- Product names/brands/images are sample presentation data only; replace with the client-approved catalog before production.

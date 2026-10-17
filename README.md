# Kashier

سیستەمی کاشێری نوێ بە پێی وێنەی نموونەی پەسەندکراو لەم گفتوگۆیەدا.

## سنووری کار

- بنەمای دیزاین: شاشەی خانەیی بە دوگمە ڕەنگاوڕەنگەکان، هێما و ناونیشانی کوردی وەک وێنەی نموونە.
- پلان، کۆد و پێداویستییەکانی پڕۆژە پێشووەکان بەشێک نین لەم پڕۆژەیە.
- ئەمە تەنها دەستپێکی پڕۆژەکەیە؛ تۆمارکردنی مامەڵە لە داتابەیس هێشتا جێبەجێ نەکراوە.

## Supabase

- Project: `Kashier`
- Project reference: `dhfyqxdfwhxlipbsasqf`
- Organization: `yzqydecqltgvixelgrlk`
- Region: `eu-central-1`
- Dashboard: https://supabase.com/dashboard/project/dhfyqxdfwhxlipbsasqf

Initial verification: 0 public tables, 0 authentication users, 0 storage buckets, 0 Edge Functions.

No API keys, passwords, or service-role credentials are stored in this repository. Application authentication and database schema are not implemented yet.

## Home screen implementation

Open `index.html` in a browser, or serve this repository using a static HTTP server. No package installation or external assets are required.

The initial screen includes 33 Kurdish module tiles matching the reference layout, responsive grid styles, module information dialogs, Kurdish module search, a fullscreen control, a Baghdad-time clock, and a tile-size setting. Module dialogs are placeholders; no financial operation or database connection is implemented.

Validation: JavaScript syntax and DOM-handler checks passed for 33 unique modules, dialog handlers, Kurdish search, clearing, and density controls. Full browser rendering and responsive visual QA remain unverified because a browser executable was unavailable in the execution environment.

## Sale draft screen

The home screen's sale tile opens `sale.html`. It supports manual draft line entry, optional barcodes, editable quantities and integer IQD prices, removal, subtotal/discount/payment/change calculations, an explicit positive shortfall, customer and note fields, tab-scoped session storage, clearing with confirmation, and a draft-only print preview.

Catalog lookup and final posting are not connected. The posting button stays disabled. Draft printouts are prominently labeled as unposted drafts. No sales, inventory, customers or payment rows are written to Supabase.

Run `node --test tests/sale-math.test.cjs` for five arithmetic tests. JS syntax, HTML references and a DOM-handler smoke check passed. Browser rendering and physical printer output remain unverified.

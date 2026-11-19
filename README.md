# AQS Supply Hire

Sistem sewaan AQS Supply: rekod kerja, invois, bayaran, pelanggan dan aset.
Laman statik (HTML + JavaScript) yang dihos di GitHub Pages, dengan data dan log masuk di Supabase.

## Persediaan (sekali sahaja)

### 1. Supabase
1. Buka projek anda di https://supabase.com/dashboard.
2. **SQL Editor → New query**, tampal isi `supabase/schema.sql`, tukar `EMAIL-ANDA@contoh.com` kepada e-mel anda, kemudian **Run**.
3. **Authentication → Sign In / Providers → Email**: matikan **Allow new users to sign up**, supaya hanya orang yang anda jemput boleh buat akaun.
4. **Authentication → URL Configuration**: isi **Site URL** dengan alamat GitHub Pages anda (contoh `https://NAMA.github.io/aqs-hire/`) dan tambah alamat yang sama dalam **Redirect URLs**.
5. **Authentication → Users → Add user → Send invitation** untuk diri anda dan setiap staf. Mereka klik pautan dalam e-mel dan tetapkan kata laluan.
6. **Project Settings → API**: salin **Project URL** dan kunci **anon public** ke dalam `config.js`.

### 2. GitHub Pages
1. Push repo ini ke GitHub.
2. **Settings → Pages → Build and deployment**: Source **Deploy from a branch**, branch `main`, folder `/ (root)`.
3. Tunggu 1–2 minit, kemudian buka `https://NAMA.github.io/aqs-hire/`.

## Tambah atau buang staf
Seseorang perlu **kedua-duanya**: akaun di Supabase (dijemput di Authentication → Users) **dan** e-melnya dalam jadual `staff`:

```sql
insert into public.staff (email, name) values ('staf@contoh.com', 'Nama Staf');
delete from public.staff where email = 'staf@contoh.com';
```

## Fail
- `index.html`: keseluruhan aplikasi.
- `config.js`: URL dan kunci awam Supabase.
- `supabase/schema.sql`: jadual, polisi keselamatan (RLS) dan realtime.

## Banyak syarikat
Jalankan `supabase/003_multi_syarikat.sql` sekali. Selepas itu:
- **Tetapan → Syarikat → Tambah Syarikat** untuk mencipta syarikat baharu (anda menjadi admin syarikat itu).
- Buka syarikat itu, kemudian tambah akaun log masuk dan pemandu di **Tetapan** seperti biasa. Setiap syarikat ada data, tetapan dan logo sendiri.
- Akaun yang ahli lebih dari satu syarikat memilih syarikat selepas log masuk (butang **Tukar Syarikat** di atas kanan).

## DO vendor
Jalankan `supabase/004_do_vendor.sql` sekali. Dalam rekod kerja pilih **Kenderaan Oleh: Lori Vendor**, isi butiran vendor, Simpan, kemudian tekan **Pautan DO Vendor** dan hantar pautan melalui WhatsApp. Pemandu vendor isi DO tanpa log masuk; pautan sah untuk satu DO dan tamat dalam 7 hari.

-- XYANI876 Collection: product image storage
-- Run this once in Supabase SQL Editor.

-- Create a public bucket for storefront product photos.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'product-images',
  'product-images',
  true,
  5242880,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update set
  public = true,
  file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

-- Public visitors may read product images.
drop policy if exists "public can view product images" on storage.objects;
create policy "public can view product images"
on storage.objects
for select
to public
using (bucket_id = 'product-images');

-- Only a registered XYANI876 administrator may upload images.
drop policy if exists "admins can upload product images" on storage.objects;
create policy "admins can upload product images"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'product-images'
  and exists (
    select 1 from public.admins a
    where a.user_id = (select auth.uid())
  )
);

-- Only an administrator may replace/update images.
drop policy if exists "admins can update product images" on storage.objects;
create policy "admins can update product images"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'product-images'
  and exists (
    select 1 from public.admins a
    where a.user_id = (select auth.uid())
  )
)
with check (
  bucket_id = 'product-images'
  and exists (
    select 1 from public.admins a
    where a.user_id = (select auth.uid())
  )
);

-- Only an administrator may delete images.
drop policy if exists "admins can delete product images" on storage.objects;
create policy "admins can delete product images"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'product-images'
  and exists (
    select 1 from public.admins a
    where a.user_id = (select auth.uid())
  )
);

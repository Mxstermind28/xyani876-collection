-- XYANI876 Collection checkout fix
-- Run this entire file once in Supabase SQL Editor.
-- It fixes anonymous checkout without exposing customer orders publicly.

create or replace function public.place_order(
  p_customer_name text,
  p_phone text,
  p_email text,
  p_delivery_method text,
  p_address text,
  p_parish text,
  p_knutsford_branch text,
  p_payment_method text,
  p_notes text,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order_id uuid;
  v_order_number text;
  v_total integer := 0;
  v_item jsonb;
  v_product public.products%rowtype;
  v_product_id uuid;
  v_qty integer;
begin
  if nullif(trim(p_customer_name), '') is null then
    raise exception 'Customer name is required';
  end if;
  if nullif(trim(p_phone), '') is null then
    raise exception 'Phone number is required';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Your cart is empty';
  end if;

  -- Validate current live inventory and calculate prices on the server.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := greatest(coalesce((v_item->>'quantity')::integer, 0), 0);
    if v_qty < 1 then
      raise exception 'Invalid item quantity';
    end if;

    select * into v_product
    from public.products
    where id = v_product_id and active = true
    for update;

    if not found then
      raise exception 'A product in your cart is no longer available';
    end if;
    if v_product.stock < v_qty then
      raise exception '% only has % left in stock', v_product.name, v_product.stock;
    end if;
    v_total := v_total + (v_product.price * v_qty);
  end loop;

  insert into public.orders(
    customer_name, phone, email, delivery_method, address, parish,
    knutsford_branch, payment_method, payment_status, status, notes, total
  ) values (
    trim(p_customer_name), trim(p_phone), nullif(trim(p_email), ''), p_delivery_method,
    nullif(trim(p_address), ''), nullif(trim(p_parish), ''), nullif(trim(p_knutsford_branch), ''),
    p_payment_method, 'Pending', 'New', nullif(trim(p_notes), ''), v_total
  )
  returning id, order_number into v_order_id, v_order_number;

  -- Save line items and reduce inventory in the same transaction.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::integer;
    select * into v_product from public.products where id = v_product_id for update;

    insert into public.order_items(order_id, product_id, product_name, unit_price, quantity)
    values (v_order_id, v_product.id, v_product.name, v_product.price, v_qty);

    update public.products
    set stock = stock - v_qty,
        badge = case when stock - v_qty <= 0 then 'SOLD OUT' else badge end,
        updated_at = now()
    where id = v_product.id;
  end loop;

  return jsonb_build_object(
    'id', v_order_id,
    'order_number', v_order_number,
    'total', v_total
  );
end;
$$;

revoke all on function public.place_order(text,text,text,text,text,text,text,text,text,jsonb) from public;
grant execute on function public.place_order(text,text,text,text,text,text,text,text,text,jsonb) to anon, authenticated;

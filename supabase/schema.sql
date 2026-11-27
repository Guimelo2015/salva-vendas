create table if not exists public.pedidos (
  id uuid primary key default gen_random_uuid(),
  token uuid not null default gen_random_uuid(),
  criado_em timestamptz not null default now(),
  notificado_em timestamptz,
  aprovado_em timestamptz,
  estado text not null default 'pendente' check (estado in ('pendente', 'aprovado', 'recusado')),
  plano text not null check (plano in ('essencial', 'destaque')),
  email text not null,
  loja jsonb not null
);

alter table public.pedidos enable row level security;
revoke all on public.pedidos from anon, authenticated;
grant select, update on public.pedidos to service_role;

create or replace function public.criar_pedido(p_dados jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plano text := p_dados ->> 'plano';
  v_email text := lower(trim(coalesce(p_dados ->> 'email', '')));
  v_loja jsonb := p_dados -> 'loja';
  v_artigos jsonb := p_dados -> 'loja' -> 'products';
  v_nome text;
  v_whatsapp text;
  v_fim timestamptz;
  v_artigo jsonb;
  v_limpos jsonb := '[]'::jsonb;
  v_item jsonb;
  v_antigo numeric;
  v_promo numeric;
  v_destaque boolean;
  v_numero int := 0;
  v_min int;
  v_max int;
  v_id uuid;
begin
  if v_plano is null or v_plano not in ('essencial', 'destaque') then
    raise exception 'Plano inválido';
  end if;
  v_destaque := v_plano = 'destaque';
  v_min := case when v_destaque then 11 else 6 end;
  v_max := case when v_destaque then 15 else 10 end;

  if length(v_email) > 254 or v_email !~ '^[^@[:space:]<>,;"]+@[^@[:space:]<>,;"]+\.[^@[:space:]<>,;"]+$' then
    raise exception 'Email inválido';
  end if;

  if (select count(*) from public.pedidos where email = v_email and estado = 'pendente') >= 5 then
    raise exception 'Já existem vários pedidos pendentes para este email';
  end if;

  v_nome := left(trim(coalesce(v_loja ->> 'storeName', '')), 60);
  v_whatsapp := regexp_replace(coalesce(v_loja ->> 'whatsappNumber', ''), '\D', '', 'g');

  if v_nome = '' then
    raise exception 'Indique o nome da loja';
  end if;
  if length(v_whatsapp) not between 9 and 15 then
    raise exception 'Número de WhatsApp inválido';
  end if;

  begin
    v_fim := (v_loja ->> 'countdownEndDate')::timestamptz;
  exception when others then
    raise exception 'Data de fim inválida';
  end;
  if v_fim is null or v_fim <= now() or v_fim > now() + interval '60 days' then
    raise exception 'A data de fim tem de ser futura e dentro de 60 dias';
  end if;

  if jsonb_typeof(v_artigos) is distinct from 'array' then
    raise exception 'Artigos em falta';
  end if;
  if jsonb_array_length(v_artigos) not between v_min and v_max then
    raise exception 'Este plano aceita entre % e % artigos', v_min, v_max;
  end if;

  for v_artigo in select value from jsonb_array_elements(v_artigos) loop
    v_numero := v_numero + 1;

    if trim(coalesce(v_artigo ->> 'name', '')) = '' then
      raise exception 'Artigo %: nome em falta', v_numero;
    end if;
    if coalesce(v_artigo ->> 'photo', '') !~ '^[0-9a-f-]{36}/[0-9]{1,2}\.jpg$' then
      raise exception 'Artigo %: foto inválida', v_numero;
    end if;
    if coalesce(v_artigo ->> 'oldPrice', '') !~ '^[0-9]{1,6}(\.[0-9]{1,2})?$'
      or coalesce(v_artigo ->> 'promoPrice', '') !~ '^[0-9]{1,6}(\.[0-9]{1,2})?$' then
      raise exception 'Artigo %: preço inválido', v_numero;
    end if;

    v_antigo := (v_artigo ->> 'oldPrice')::numeric;
    v_promo := (v_artigo ->> 'promoPrice')::numeric;
    if v_promo <= 0 or v_promo >= v_antigo then
      raise exception 'Artigo %: o preço Black Friday tem de ser inferior ao preço antigo', v_numero;
    end if;

    v_item := jsonb_build_object(
      'id', v_numero,
      'name', left(trim(v_artigo ->> 'name'), 80),
      'photo', v_artigo ->> 'photo',
      'oldPrice', v_antigo,
      'promoPrice', v_promo,
      'badge', case when v_destaque then left(trim(coalesce(v_artigo ->> 'badge', '')), 24) else '' end
    );
    if v_destaque and coalesce(v_artigo ->> 'stockLeft', '') ~ '^[0-9]{1,4}$' then
      v_item := v_item || jsonb_build_object('stockLeft', (v_artigo ->> 'stockLeft')::int);
    end if;

    v_limpos := v_limpos || jsonb_build_array(v_item);
  end loop;

  insert into public.pedidos (plano, email, loja)
  values (
    v_plano,
    v_email,
    jsonb_build_object(
      'storeName', v_nome,
      'storeTagline', coalesce(nullif(left(trim(coalesce(v_loja ->> 'storeTagline', '')), 100), ''), 'Ofertas Relâmpago de Black Friday'),
      'whatsappNumber', v_whatsapp,
      'countdownEndDate', to_char(v_fim at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'countdownEndTime', '',
      'promoBannerText', case when v_destaque then left(trim(coalesce(v_loja ->> 'promoBannerText', '')), 120) else '' end,
      'instagramHandle', left(trim(coalesce(v_loja ->> 'instagramHandle', '')), 40),
      'addressOrDeliveryInfo', left(trim(coalesce(v_loja ->> 'addressOrDeliveryInfo', '')), 140),
      'products', v_limpos
    )
  )
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.obter_montra(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select loja || jsonb_build_object('showSearch', plano = 'destaque')
  from public.pedidos
  where id = p_id and estado = 'aprovado';
$$;

revoke all on function public.criar_pedido(jsonb) from public;
revoke all on function public.obter_montra(uuid) from public;
grant execute on function public.criar_pedido(jsonb) to anon;
grant execute on function public.obter_montra(uuid) to anon;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('montras', 'montras', true, 1048576, array['image/jpeg'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "montras envio publico" on storage.objects;
create policy "montras envio publico"
on storage.objects
for insert
to anon
with check (bucket_id = 'montras' and name ~ '^[0-9a-f-]{36}/[0-9]{1,2}\.jpg$');

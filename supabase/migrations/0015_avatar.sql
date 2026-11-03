-- =============================================================================
-- 0015_avatar — foto de perfil (Storage)
--
-- Bucket `avatares` + a coluna que guarda a URL. O limite de 3 MB e os tipos
-- aceitos ficam NO BUCKET, não só no JS: o client valida pra dar recado rápido,
-- mas quem realmente barra o arquivo grande é o Storage (confiança zero no
-- client, ver CLAUDE.md › Segurança).
--
-- Bucket PÚBLICO de propósito: avatar aparece na tela toda hora e signed URL
-- expira — o caminho tem o uuid do usuário, que não é adivinhável. Escrever,
-- porém, só o dono: as policies abaixo exigem que a primeira pasta do caminho
-- seja o próprio auth.uid() (`{user_id}/avatar`).
-- =============================================================================

-- Bucket ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatares',
  'avatares',
  true,
  3145728, -- 3 MB
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Coluna ---------------------------------------------------------------------
alter table public.profiles add column if not exists avatar_url text;

-- Policies (storage.objects já sobe com RLS ligado) ---------------------------
-- Leitura: o bucket é público, mas a policy explícita mantém o padrão
-- deny-by-default honesto — nada fica aberto por acidente de configuração.
drop policy if exists "avatares: qualquer um vê" on storage.objects;
create policy "avatares: qualquer um vê"
  on storage.objects for select
  using (bucket_id = 'avatares');

-- Escrita: só na PRÓPRIA pasta. `storage.foldername(name)` quebra o caminho em
-- array; a posição 1 é o uuid do dono.
drop policy if exists "avatares: dono manda a dele" on storage.objects;
create policy "avatares: dono manda a dele"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatares'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatares: dono troca a dele" on storage.objects;
create policy "avatares: dono troca a dele"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatares'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatares'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatares: dono apaga a dele" on storage.objects;
create policy "avatares: dono apaga a dele"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatares'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

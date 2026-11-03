-- =============================================================================
-- 0037_dicas_sem_travessao.sql — as dicas das conquistas trocam o "—" por vírgula ✍️
--
-- O tom de voz da casa (ver CLAUDE.md › Tom de voz da marca) não usa travessão
-- em texto que o usuário vê: no lugar dele vai vírgula. Cinco das nove dicas
-- semeadas pela 0010 nasceram antes dessa regra e aparecem com o "—" no card
-- bloqueado da /conta/conquistas e no tooltip dos emblemas do painel da conta.
--
-- Só texto: nenhuma coluna, policy, função ou permissão muda aqui. As outras
-- quatro dicas da 0010 já estavam sem travessão e ficam como estão.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (é UPDATE por slug, com o texto final escrito à mão).
-- =============================================================================

update public.achievements
   set dica = 'faz teu primeiro pedido, aqui na loja ou lá no balcão.'
 where slug = 'primeira-xicara';

update public.achievements
   set dica = 'passa cinco manhãs com a gente, pedidos antes do meio-dia contam.'
 where slug = 'manha-de-sempre';

update public.achievements
   set dica = 'traz alguém novo pra sentar na nossa mesa, a gente marca no balcão.'
 where slug = 'mesa-comprida';

update public.achievements
   set dica = 'prova todos os doces da casa, a gente confirma no balcão.'
 where slug = 'que-seja-doce';

update public.achievements
   set dica = 'vem a quatro brunchs de domingo, a mesa te espera.'
 where slug = 'domingo-de-brunch';

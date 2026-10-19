# Sistema de Tarefas — Supabase + HTML

## Arquivos
- `index.html`: interface inicial com login, cadastro, painel, tarefas diárias, atividades extras e logs.
- `schema.sql`: tabelas, políticas RLS, perfil padrão e auditoria por triggers.

## Como instalar sem programas
1. Crie um projeto no Supabase.
2. Abra SQL Editor e execute `schema.sql` uma vez.
3. Copie a Project URL e a chave publicável (publishable/anon) do Supabase.
4. Edite `index.html` no editor web do GitHub e substitua `COLE_A_URL_DO_PROJETO` e `COLE_A_CHAVE_PUBLICAVEL`.
5. Publique pelo GitHub Pages (Settings → Pages → Deploy from a branch → main → /(root)).
6. No Supabase Authentication → URL Configuration, configure Site URL e Redirect URLs com o endereço publicado.
7. Crie as contas no site. Todas começam como `jovem_aprendiz`.
8. Para definir um usuário como Diretor, encontre o UUID em Authentication → Users e execute no SQL Editor:
   `update public.profiles set role='diretor_secretaria' where id='UUID-DO-USUARIO';`

## Notas importantes
- Ambos os cargos têm as mesmas permissões de tarefas e consulta de logs.
- O HTML/JS é público no GitHub Pages; não coloque chaves secretas no frontend.
- O log é escrito por triggers no banco. Não há permissões de API para editar/excluir logs.
- O exemplo é uma base inicial. Antes de usar com dados sensíveis, teste as políticas, configure backup e revise requisitos institucionais.
- Não execute `schema.sql` repetidamente em banco com dados; revise migrações antes de atualizar.

# Guia de ativação

Ficheiros do projeto:

| Ficheiro | Função |
|---|---|
| `vendas.html` | Página de vendas e formulário do pedido |
| `template-base.html` | Demonstração e montra de cada cliente (`?loja=ID`) |
| `supabase/schema.sql` | Tabela, funções e armazenamento de fotos |
| `n8n/montra-workflow.json` | Avisos, aprovação e entrega por email |
| `vercel.json` | Mostra a página de vendas no endereço principal |

## 1. Supabase

1. Crie um projeto.
2. Em **SQL Editor**, cole todo o conteúdo de `supabase/schema.sql` e execute.
3. Em **Project Settings → API Keys**, copie:
   - o URL do projeto;
   - a chave **publishable** (ou `anon`), usada nas páginas;
   - a chave **secret** (ou `service_role`), usada **somente no n8n**. Nunca a coloque nas páginas nem no GitHub.

## 2. n8n

1. Crie um workflow e escolha **Import from File** com `n8n/montra-workflow.json`.
2. Abra o nó **Configuração** e preencha:
   - `supabaseUrl`: URL do projeto;
   - `emailDono`: o seu email, que recebe os pedidos;
   - `siteUrl`: endereço do site na Vercel, sem barra no fim;
   - `webhookUrl`: base dos webhooks de produção, terminada em `/webhook` (veja o Production URL no nó **Novo Pedido**);
   - `stripeEssencial` e `stripeDestaque`: os Payment Links.
3. Nos nós **Reservar Pedido** e **Aprovar no Supabase**, crie a credencial **Supabase API** com o URL e a chave secret.
4. Nos quatro nós de Gmail, ligue a sua conta Google.
5. Ative (publique) o workflow.

## 3. Páginas

Em `vendas.html`, edite o `SALES_CONFIG`:

- `supportWhatsapp`: o seu número com indicativo;
- `supabaseUrl` e `supabaseKey` (chave publishable);
- `n8nWebhookUrl`: o Production URL do nó **Novo Pedido**;
- `stripeLinkStarter` e `stripeLinkPro`;
- `offerEndsAt`: fim real da campanha.

Em `template-base.html`, edite o bloco `BACKEND` com o mesmo URL e a mesma chave publishable. No `STORE_CONFIG`, o `whatsappNumber` é o número que recebe os testes feitos na demonstração.

## 4. Stripe

1. Crie dois **Payment Links** em EUR: 29€ e 49€.
2. Em cada um, na opção após o pagamento, escolha redirecionar para:
   - `https://SEU-SITE/vendas.html?plano=essencial`
   - `https://SEU-SITE/vendas.html?plano=destaque`
3. Faça um pagamento real de teste para confirmar que a sua conta cobra em euros.

Enquanto os links tiverem `SEU_LINK`, os botões dos planos abrem diretamente o formulário.

## 5. Publicar

```powershell
git add -A
git commit -m "pagina de vendas e automacao"
git push
```

## 6. Teste completo antes de divulgar

1. No telemóvel, abra o site e envie um pedido com 6 fotos e o seu email.
2. Confirme que chegaram dois emails: o aviso de pedido novo e a confirmação ao lojista.
3. Clique em **Rever e aprovar montra** e confirme.
4. Abra o link recebido e toque num botão de encomenda.

## Rotina de cada pedido

1. Chega o email de pedido novo.
2. Confirme na Stripe que há um pagamento com o mesmo email e o valor do pacote.
3. Veja as fotos e aprove. O lojista recebe o link e os textos automaticamente.

**A página não verifica o pagamento.** Qualquer pessoa pode enviar o formulário, por isso aprove apenas depois de ver o dinheiro na Stripe.

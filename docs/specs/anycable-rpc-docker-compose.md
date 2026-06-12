# Spec de Feature: Migrar Action Cable para AnyCable (RPC) + Docker Compose (múltiplas stacks)

- **Status:** Proposta (spec, sem implementação ainda)
- **Autor:** Cloud Agent
- **Branch:** `cursor/spec-anycable-rpc-docker-compose-5e2a`
- **Relacionado:** `app/channels/application_cable/connection.rb`, `config/cable.yml`, `config/application.rb`, `Dockerfile`

---

## 1. Objetivo

1. **Trocar a camada de conexões WebSocket do Rails (Action Cable in-process) por AnyCable**, em que o servidor WebSocket roda em um processo Go (`anycable-go`) e se comunica com o app Rails via **gRPC (RPC)**.
2. **Definir a topologia Docker em stacks separadas** (ver §6), com um **`docker-compose` exclusivo para a estrutura de serviços compartilhados** (Postgres, Redis, `anycable-go`) e um **`docker-compose` próprio do projeto Rails** (web/Puma, RPC AnyCable, Sidekiq) que **enxerga** os serviços compartilhados via uma **rede Docker externa compartilhada**.

Resultado esperado: um cliente WebSocket conecta em `ws://localhost:8080/cable`, autentica, assina um canal e recebe atualizações em tempo real (ex.: mudança de saldo após um depósito). A infra de serviços sobe na sua própria stack e os projetos (Rails — e futuramente o trading-engine Go) sobem em stacks próprias que dependem dela.

---

## 2. Contexto / Estado atual

- App **Rails 8.1, API-only** (`config.api_only = true`) — Wallet API multi-tenant.
- Action Cable existe apenas como scaffold:
  - `app/channels/application_cable/connection.rb` identifica o usuário via cookie de sessão assinado (`cookies.signed[:session_id]` → `Session` → `User`).
  - **Nenhum `Channel` concreto** foi criado ainda.
- `config/cable.yml`: `development: async`, `test: test`, `production: solid_cable`.
- `require "rails/all"` em `config/application.rb` → o engine do Action Cable **já está carregado** (importante para o AnyCable, ver §8).
- **Não existe** `docker-compose.yml`. O `Dockerfile` atual é **somente para produção** (Kamal/Thruster), roda como usuário não-root e usa `RAILS_ENV=production`.
- Autenticação da API é via **JWT** (`JwtService`, header `Authorization: Bearer`); sessões por cookie são usadas no fluxo web/login.

### Por que AnyCable
- Descola o tráfego WebSocket do Puma (Go aguenta muito mais conexões simultâneas com menos memória).
- Escala horizontalmente o WS sem escalar o app Rails.
- Mantém a API de `Channel`/`Connection` do Action Cable (mudança de baixo atrito no código Ruby).

---

## 3. Escopo

### Dentro do escopo
- Adicionar e configurar o gem `anycable-rails`.
- Configurar o broadcast adapter para `redis` (pub/sub) e o `cable.yml` para `any_cable`.
- Garantir compatibilidade do `ApplicationCable::Connection` com AnyCable.
- Criar **um canal de demonstração** ligado ao domínio (ex.: `AccountChannel`/`TransactionsChannel`) para validar broadcast ponta a ponta.
- Criar a **stack de serviços compartilhados** (`services/docker-compose.yml`: Postgres, Redis, `anycable-go`) + a **stack do projeto Rails** (`docker-compose.yml`: web, rpc, sidekiq) + um `Dockerfile.dev` do Rails, conectadas por uma **rede externa compartilhada** (ver §6).
- Variáveis de ambiente / `.env.example`.
- Testes (adapter de teste do AnyCable + specs de canal/conexão).
- Atualizar `README.md` e `AGENTS.md` com os comandos novos.

### Fora do escopo
- Mudanças no deploy de produção (Kamal). Apenas observação em §11.
- Reescrever a autenticação JWT existente da API REST.
- Frontend/cliente WebSocket de produção (apenas um cliente de exemplo para validação).

---

## 4. Arquitetura proposta

```
                         ┌─────────────────────────┐
   navegador / cliente   │                         │
   WebSocket  ──────────►│   anycable-go  (:8080)  │   servidor WS em Go
                         │                         │
                         └───────────┬─────────────┘
                                     │ gRPC (RPC :50051)
                                     ▼
                         ┌─────────────────────────┐
                         │  Rails AnyCable RPC      │   `bundle exec anycable`
                         │  (Connection/Channels)   │   (mesmo código, sem Puma)
                         └───────────┬─────────────┘
                                     │
              broadcasts (pub/sub)   ▼
                         ┌─────────────────────────┐
                         │        Redis            │◄──── Sidekiq / web publicam
                         └─────────────────────────┘       broadcasts aqui
                                     ▲
                                     │ assina canal pub/sub
                         ┌───────────┴─────────────┐
                         │   anycable-go entrega    │
                         │   mensagens aos clientes │
                         └─────────────────────────┘

   HTTP REST normal continua:  cliente ──► web (Puma :3000) ──► Postgres
```

Fluxo de uma atualização em tempo real:
1. Cliente abre WS em `anycable-go` e assina, por exemplo, `AccountChannel` (escopo do usuário/tenant).
2. `anycable-go` chama o servidor RPC Rails para autenticar a conexão e autorizar a subscription.
3. Um depósito (`DepositService` / `BatchDepositJob`) dispara `AccountChannel.broadcast_to(account, …)`.
4. O broadcast vai para o Redis; `anycable-go` está inscrito e entrega a mensagem aos clientes daquele stream.

---

## 5. Componentes / mudanças no código

### 5.1 Gemfile
```ruby
gem "anycable-rails", "~> 1.6"   # 1.6.2 é a última (abr/2026), compatível com Rails 8
```
- `anycable-go` **não** é um gem; é um binário Go (instalado via container `anycable/anycable-go` no compose, ou `bin/anycable-go` em local).

### 5.2 `config/cable.yml`
Trocar os adapters para que o Rails publique via AnyCable:
```yaml
development:
  adapter: any_cable     # era: async
test:
  adapter: test
production:
  adapter: any_cable     # era: solid_cable
```
> `any_cable` faz o Rails publicar broadcasts no backend do AnyCable (Redis pub/sub por padrão).

### 5.3 `config/anycable.yml` (novo)
```yaml
default: &default
  ## URL pub/sub usada para broadcasting (web/sidekiq → anycable-go)
  broadcast_adapter: redisx        # ou "redis"
  redis_url: <%= ENV.fetch("ANYCABLE_REDIS_URL", "redis://redis:6379/2") %>
  rpc_host: "0.0.0.0:50051"

development:
  <<: *default

production:
  <<: *default
```
- Usar um **DB Redis dedicado** (ex.: `/2`) para não colidir com idempotência (`/0`) e Sidekiq (`/1`).

### 5.4 `ApplicationCable::Connection` — compatibilidade
A conexão atual usa cookie de sessão assinado. Duas decisões a tomar:

**Opção A (manter cookie de sessão):** funciona com AnyCable, pois `anycable-go` repassa cookies/headers para o RPC. Requer que `secret_key_base` seja **idêntico** entre o processo web e o processo RPC (mesmo `RAILS_ENV`/master key — garantido pelo mesmo container/imagem).

**Opção B (recomendada — JWT):** como a API já é JWT-first, autenticar o WebSocket por JWT é mais coerente para clientes não-browser. Identificar via query param `?jwt=<token>` ou header. Pode usar `anycable-rails-jwt` ou identificação manual:
```ruby
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :current_tenant

    def connect
      self.current_user = find_user || reject_unauthorized_connection
      self.current_tenant = current_user.tenant
    end

    private

    def find_user
      token = request.params[:jwt] || request.headers["Authorization"]&.split&.last
      payload = JwtService.decode(token)
      User.find_by(id: payload["user_id"])
    rescue StandardError
      nil
    end
  end
end
```
> **Decisão proposta:** implementar **Opção B (JWT)** mantendo a Opção A (cookie) como fallback, para alinhar com o modelo de auth da API. Registrar a decisão no PR de implementação.

### 5.5 Canal de demonstração (novo) — `app/channels/account_channel.rb`
```ruby
class AccountChannel < ApplicationCable::Channel
  def subscribed
    account = current_user.account
    reject unless account
    stream_for account
  end
end
```
- Disparar `AccountChannel.broadcast_to(account, { balance: ..., transaction_id: ... })` ao final de `DepositService`/`WithdrawalService`/`BatchDepositJob` (ponto de integração a definir na implementação; pode ser via callback ou chamada explícita).
- **Multi-tenancy:** o stream é por `account` (que já pertence a um tenant), então o isolamento é preservado. A `Connection` deve setar `ActsAsTenant.current_tenant` a partir do usuário autenticado.

### 5.6 `config/application.rb`
- Confirmar que o Action Cable está carregado. Como o app usa `require "rails/all"`, **já está** — sem essa engine o AnyCable falha com `logger nil` (gotcha conhecido). Nenhuma mudança necessária, apenas validar.

---

## 6. Topologia Docker (stacks separadas)

> **Decisão estrutural:** a infraestrutura de serviços compartilhados fica em um **`docker-compose` próprio e separado**, e **cada projeto** (Rails agora; trading-engine Go depois) tem o **seu próprio `docker-compose` + `Dockerfile`**. As stacks dos projetos **não embutem** Postgres/Redis/AnyCable — elas **enxergam** esses serviços através de uma **rede Docker externa compartilhada**. Ou seja, os projetos **dependem** da stack de serviços, mas são independentes entre si.

### 6.1 Visão geral das stacks

```
┌──────────────────────────────────────────────────────────────────────┐
│  STACK: services   →  services/docker-compose.yml  (infra compartilhada)│
│  cria/possui a rede externa:  wallet_shared                            │
│   • db            postgres:16            :5432                         │
│   • redis         redis:7                :6379  (/0 idem, /1 sidekiq, /2 anycable)│
│   • anycable-go   anycable/anycable-go   :8080  (WS; RPC_HOST=rpc:50051)│
└───────────────▲────────────────────────────────────▲──────────────────┘
                │ rede wallet_shared                   │ rede wallet_shared
   ┌────────────┴───────────────────┐      ┌───────────┴───────────────────────┐
   │ STACK: wallet-api (este repo)   │      │ STACK: trading-engine (repo Go)    │
   │ docker-compose.yml + Dockerfile.dev    │ (spec go-trading-engine-anycable)  │
   │   • web      Puma   :3000       │      │   • trading-engine  Echo  :8090    │
   │   • rpc      anycable RPC :50051│      │                                    │
   │   • sidekiq                     │      │                                    │
   └─────────────────────────────────┘      └────────────────────────────────────┘
```

- **`anycable-go` (na stack de serviços)** precisa alcançar o **`rpc` (na stack do Rails)** via gRPC. Como ambos estão na rede `wallet_shared`, o DNS interno do Docker resolve `rpc:50051`. (É uma dependência services→app legítima, viabilizada pela rede compartilhada.)
- **Rails (`web`/`rpc`/`sidekiq`)** alcança `db`, `redis` (e o broadcast do AnyCable) pelos nomes `db`/`redis` na mesma rede.

### 6.2 Rede externa compartilhada
- Criada uma vez: `docker network create wallet_shared` **ou** declarada/owned pela stack `services` (`networks: { wallet_shared: { name: wallet_shared } }`).
- Referenciada pelas stacks dos projetos como **`external: true`**:
```yaml
networks:
  wallet_shared:
    external: true
```
- Todos os serviços de todas as stacks declaram `networks: [wallet_shared]` para se enxergarem por DNS.

### 6.3 Stack de serviços — `services/docker-compose.yml` (novo)

| Serviço | Imagem | Porta | Papel |
| --- | --- | --- | --- |
| `db` | `postgres:16` | 5432 | Banco (user/pass `postgres`); volume nomeado |
| `redis` | `redis:7` | 6379 | Idempotência (`/0`), Sidekiq (`/1`), AnyCable (`/2`) |
| `anycable-go` | `anycable/anycable-go:latest` | 8080 | Servidor WebSocket Go |

- Healthchecks em `db` (`pg_isready`) e `redis` (`redis-cli ping`).
- Variáveis do `anycable-go`: `ANYCABLE_HOST=0.0.0.0`, `ANYCABLE_PORT=8080`, `ANYCABLE_RPC_HOST=rpc:50051`, `ANYCABLE_REDIS_URL=redis://redis:6379/2`, `ANYCABLE_BROADCAST_ADAPTER=redisx`, `ANYCABLE_ALLOWED_ORIGINS=*` (dev).
- Esta stack **sobe primeiro** (`docker compose -f services/docker-compose.yml up`).

### 6.4 `Dockerfile.dev` do Rails (novo)
O `Dockerfile` atual é só produção (non-root, `RAILS_ENV=production`, sem dev gems). Criar um arquivo de dev:
- Base `ruby:4.0.2-slim`.
- Instalar `build-essential libpq-dev libvips libyaml-dev pkg-config git`.
- `bundle install` **com** grupos `development`/`test`.
- `RAILS_ENV=development`, sem precompile de bootsnap obrigatório.

### 6.5 Stack do Rails — `docker-compose.yml` (novo, neste repo)

| Serviço | Build | Porta | Papel |
| --- | --- | --- | --- |
| `web` | `Dockerfile.dev` | 3000 | Puma — API REST (`bin/rails server`) |
| `rpc` | `Dockerfile.dev` | 50051 | Servidor RPC AnyCable (`bundle exec anycable --rpc-host=0.0.0.0:50051`) |
| `sidekiq` | `Dockerfile.dev` | — | Jobs (batch/transfer/cleanup) |

Pontos-chave:
- **Não há `db`/`redis`/`ws` aqui** — vêm da stack `services` via `wallet_shared`.
- Variáveis para `web`/`rpc`/`sidekiq`: `DATABASE_URL=postgres://postgres:postgres@db:5432/wallet_api_development`, `REDIS_URL=redis://redis:6379/0`, `ANYCABLE_REDIS_URL=redis://redis:6379/2`, `RAILS_ENV=development`, **`SECRET_KEY_BASE` compartilhado** entre `web` e `rpc`.
- Volume do código para hot-reload; volume nomeado para `bundle`.
- Healthcheck do `rpc`: `anycable health` (ou checagem da porta gRPC).
- **Sem `depends_on` cruzando stacks:** `depends_on`/`condition: service_healthy` não funciona entre composes diferentes. O entrypoint do `web`/`rpc` deve **aguardar** Postgres/Redis (retry/wait-for) antes de `bin/rails db:prepare`. Documentar a ordem: subir `services` → depois `wallet-api`.

### 6.6 `.env.example` (novo)
Documentar todas as variáveis acima e o nome da rede (`wallet_shared`).

---

## 7. Autenticação & segurança

- **`SECRET_KEY_BASE` idêntico** em `web` e `rpc` (obrigatório para validar cookie assinado e/ou assinatura JWT).
- JWT no WebSocket: token tem TTL de 24h (igual à API). Considerar expiração da conexão.
- `anycable-go` deve repassar `Origin`/headers; em dev, liberar origens (`ANYCABLE_ALLOWED_ORIGINS=*` apenas em dev).
- Isolamento multi-tenant garantido por stream por `account` + `ActsAsTenant.current_tenant` na conexão.

---

## 8. Compatibilidade AnyCable (limitações a checar)

O gem roda um **RuboCop de compatibilidade** (`AnyCable/InstanceVars`, `AnyCable/PeriodicalTimers`) na instalação. Restrições conhecidas a validar:
- **Variáveis de instância** em canais não persistem entre chamadas (cada comando é uma chamada RPC stateless) → não guardar estado em `@ivars` no canal.
- **`periodically`/timers** têm suporte limitado.
- **Streams customizados com callback** (`stream_from ... do |msg| ... end`) precisam de "reliable streams"/configuração específica.
- Como ainda **não há canais** no projeto, o atrito de migração é mínimo — começamos "AnyCable-first".

---

## 9. Critérios de aceitação

1. `docker compose -f services/docker-compose.yml up` sobe `db`, `redis`, `anycable-go` (saudáveis) e cria a rede `wallet_shared`; em seguida `docker compose up` (stack Rails) sobe `web`, `rpc`, `sidekiq` enxergando os serviços compartilhados.
2. `GET http://localhost:3000/up` → 200 (web continua funcionando).
3. Um cliente WS conecta em `ws://localhost:8080/cable` com JWT válido, assina `AccountChannel` e a conexão é aceita; JWT inválido → conexão rejeitada.
4. Um `POST /api/v1/deposits` (ou processamento de batch) dispara um broadcast que o cliente WS recebe com o novo saldo.
5. `bundle exec rspec` passa, incluindo specs novos de canal/conexão usando o adapter de teste do AnyCable.
6. `bin/rubocop` (incluindo cops de compatibilidade do AnyCable) sem ofensas novas.

---

## 10. Plano de testes

- **Unit/spec:** usar `anycable-rails` em modo de teste (`AnyCable::TestFactory` / `stub_broadcasts`) para:
  - `spec/channels/account_channel_spec.rb` — subscribe/reject + broadcast.
  - `spec/channels/connection_spec.rb` — auth JWT aceita/rejeita.
- **Integração manual (ponta a ponta):**
  1. `docker compose -f services/docker-compose.yml up` (infra) e depois `docker compose up` (Rails).
  2. Obter JWT via `POST /session` (seeds: `alice@demo.com` / `password123`).
  3. Conectar com `wscat`/`websocat`: `websocat "ws://localhost:8080/cable?jwt=$TOKEN"` e enviar a mensagem de `subscribe`.
  4. Disparar `POST /api/v1/deposits` e confirmar a mensagem de broadcast no cliente WS.
- **Evidência:** logs do `anycable-go` (conexão + subscription), logs do `rpc` (chamadas Connect/Subscribe/Command) e o payload recebido no cliente WS.

---

## 11. Plano de implementação (fases)

1. **Gem + config base:** adicionar `anycable-rails`, rodar `bin/rails g anycable:setup` (gera `config/anycable.yml`, ajusta `cable.yml`), revisar.
2. **Conexão + canal demo:** auth JWT na `Connection`, `AccountChannel`, pontos de broadcast.
3. **Docker (stacks separadas):** `services/docker-compose.yml` (db, redis, anycable-go + rede `wallet_shared`), `Dockerfile.dev`, `docker-compose.yml` do Rails (web, rpc, sidekiq na rede externa), `.env.example`, entrypoint com wait-for + `db:prepare`.
4. **Testes:** specs de canal/conexão + ajuste do `spec/rails_helper.rb` para o modo de teste do AnyCable.
5. **Docs:** `README.md` (seção "Realtime com AnyCable" + "Docker Compose") e `AGENTS.md` (como subir o stack/portas).
6. **Validação:** rodar os critérios de aceitação (§9) e anexar evidências.

---

## 12. Riscos & considerações

- **Redis passa a ser obrigatório em dev** para o realtime (hoje o cable dev é `async`, in-process). O REST continua funcionando sem Redis, mas o WebSocket não.
- **Dois processos Rails** (web + rpc) compartilhando código/migrações; manter `SECRET_KEY_BASE` e versões de schema sincronizados.
- **`depends_on` não cruza stacks de compose:** a ordem (services → projetos) é manual/documentada e os entrypoints dos apps precisam de wait/retry para Postgres/Redis. A rede `wallet_shared` precisa existir antes das stacks dos projetos (criada pela stack `services` ou via `docker network create`).
- **Acoplamento via rede + nomes de host:** os apps assumem os hostnames `db`/`redis`/`rpc`/`anycable-go` na rede compartilhada; mudanças de nome quebram a integração entre stacks.
- **Produção (Kamal)** precisará de um serviço `anycable-go` e do processo `rpc` separados — **fora do escopo** desta spec, mas deixar o `cable.yml` de produção pronto (`any_cable`) para a evolução futura.
- **Paridade de features** do Action Cable: validar com o RuboCop de compatibilidade antes de adicionar canais complexos.
- **CORS/Origin** no `anycable-go`: liberar somente em dev.

---

## 13. Arquivos afetados (resumo)

| Arquivo | Ação |
| --- | --- |
| `Gemfile` / `Gemfile.lock` | add `anycable-rails ~> 1.6` |
| `config/cable.yml` | adapters → `any_cable` (dev/prod) |
| `config/anycable.yml` | **novo** |
| `app/channels/application_cable/connection.rb` | auth JWT (+fallback cookie) |
| `app/channels/account_channel.rb` | **novo** (canal demo) |
| `app/services/*`, `app/sidekiq/batch_deposit_job.rb` | pontos de `broadcast_to` |
| `Dockerfile.dev` | **novo** (imagem de dev do Rails) |
| `services/docker-compose.yml` | **novo** (stack de serviços: db, redis, anycable-go + rede `wallet_shared`) |
| `docker-compose.yml` | **novo** (stack do Rails: web, rpc, sidekiq; usa rede externa `wallet_shared`) |
| `.env.example` | **novo** |
| `spec/channels/*` | **novos** specs |
| `README.md`, `AGENTS.md` | docs |

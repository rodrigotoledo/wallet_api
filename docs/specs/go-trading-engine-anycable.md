# Spec de Feature: Processamento de trading em projeto Go à parte (Echo + AnyCable + Docker)

- **Status:** Proposta (spec, sem implementação ainda)
- **Autor:** Cloud Agent
- **Branch:** `cursor/spec-go-trading-engine-anycable-5e2a`
- **Depende de:** `docs/specs/anycable-rpc-docker-compose.md` (AnyCable + docker-compose precisam existir primeiro)
- **Relacionado:** `app/services/*`, `app/sidekiq/*`, `app/models/transaction.rb`, `config/cable.yml`

---

## 1. Objetivo

Extrair o **processamento (execução + liquidação) de transactions de trading** do Rails/Sidekiq para um **projeto Go totalmente separado** (repositório próprio), construído com o framework **Echo** (HTTP), integrado ao Rails via **AnyCable** para refletir o **resultado em tela em tempo real**, e empacotado/distribuído por **Docker**.

Premissas explícitas desta spec (decisões já fechadas):

1. **Projeto à parte:** o serviço Go **não** vive dentro do repositório do Wallet API. É um repositório/projeto independente (ex.: `wallet-trading-engine`), com seu próprio `go.mod`, ciclo de versão, CI e imagem Docker. O Wallet API apenas **consome** esse serviço (via HTTP) e **compartilha** o canal de broadcast do AnyCable.
2. **Echo:** a camada HTTP do serviço Go usa **`github.com/labstack/echo/v4`** (endpoints de ingestão de ordens, health e métricas).
3. **AnyCable:** o serviço Go publica o resultado da execução no **backend de broadcast do AnyCable** (Redis), e o `anycable-go` entrega ao cliente WebSocket — **sem round-trip pelo Rails**.
4. **Docker:** o serviço Go é distribuído como **imagem Docker própria** e referenciado pelo `docker-compose` do Wallet API.

Em uma frase: *Rails recebe a ordem (REST) → chama o serviço Go (Echo, HTTP) → Go executa/liquida com concorrência → publica o resultado no AnyCable → a tela do usuário atualiza sozinha.*

---

## 2. Contexto / Estado atual

- Hoje todo o processamento de movimentação de dinheiro é **síncrono no Rails** (`DepositService`, `WithdrawalService`, `TransferService`) ou **assíncrono via Sidekiq** (`BatchDepositJob`, `TransferProcessorJob`), usando lock pessimista (`Account.lock`) e otimista (`lock_version`).
- **Não existe domínio de "trading"/"order"** ainda — só `Transaction` (STI: `Deposit`, `Withdrawal`, `Transfer`). Esta spec **introduz** esse domínio do lado Rails.
- A entrega realtime é endereçada pela spec do **AnyCable** (`docs/specs/anycable-rpc-docker-compose.md`): servidor WS em Go (`anycable-go`), broadcast via Redis. Esta feature **reaproveita esse canal**.
- Stack já tem Postgres (fonte de verdade), Redis e `docker-compose` (após a spec anterior).

### Por que um projeto Go separado com Echo
- Execução de ordens é **CPU/concorrência-intensiva** (matching, validações, fees) e sensível a latência → Go + goroutines.
- **Isolamento de deploy/escala:** repositório e imagem próprios, escalável independentemente do Rails.
- **Echo** dá um servidor HTTP enxuto e performático para receber ordens e expor health/metrics, com middlewares (logging, recover, request-id) prontos.

---

## 3. Escopo

### Dentro do escopo
- **No repositório Wallet API (Rails):**
  - Domínio mínimo de trading: modelo `TradeOrder` + migração + endpoint `POST/GET /api/v1/trade_orders`.
  - Cliente HTTP para chamar o serviço Go (Echo).
  - Canal realtime `TradeOrdersChannel` (stream previsível por conta).
  - Serviço `trading-engine` referenciado no `docker-compose` (por imagem ou build context externo).
- **No projeto Go separado (`wallet-trading-engine`):**
  - App **Echo**: `POST /trade_orders` (ingestão), `GET /health`, `GET /metrics`.
  - Worker pool de execução/liquidação (goroutines).
  - Liquidação no Postgres (`SELECT … FOR UPDATE`).
  - Publisher de broadcast **AnyCable** (Redis).
  - `Dockerfile` multi-stage + `go.mod` + CI próprios.

### Fora do escopo
- Order book completo / múltiplos níveis de preço / market data feed (apenas execução simples).
- Reescrever depósitos/saques/transferências existentes (continuam no Rails).
- Deploy de produção (Kamal) — apenas observação.

---

## 4. Arquitetura proposta

```
   ┌──────────── repositório Wallet API (Rails) ────────────┐      ┌── repo separado: wallet-trading-engine (Go/Echo) ──┐
   │                                                        │      │                                                    │
client REST ─► Rails web (Puma)                              │      │   Echo HTTP server (:8090)                          │
   ▲           │ cria TradeOrder(pending)                    │      │   POST /trade_orders ─► fila interna ─► worker pool │
   │           │ POST http://trading-engine:8090/trade_orders├──────┼──►│ executa + liquida (Postgres FOR UPDATE)        │
   │           │ (HTTP, 202 Accepted)                        │      │   └─► publica broadcast no AnyCable (Redis /2)       │
   │                                                         │      │   GET /health, GET /metrics                         │
   │ WebSocket (realtime)                                    │      └───────────────┬────────────────────┬───────────────┘
   │                                                         │                      │ escreve            │ publica
   │                                                         │                      ▼ resultado          ▼ stream
   │                                              ┌──────────┴─────┐      ┌──────────────┐      ┌──────────────────┐
   │                                              │   Postgres     │◄─────┤  (compartilh.)│      │ Redis pub/sub /2 │
   │                                              │ trade_orders   │      └──────────────┘      └────────┬─────────┘
   │                                              │ accounts/txns  │                                     │ stream
   │                                              └────────────────┘                                     ▼
   │                                                                                          ┌──────────────────┐
   └──────────────────────────────────────────────────────────────────────────────────────► │  anycable-go WS  │
                                  entrega "trade.executed" ao WS do usuário                   │     (:8080)      │
                                                                                              └──────────────────┘
```

Fluxo:
1. `POST /api/v1/trade_orders` → Rails valida, cria `TradeOrder(status: pending)` e responde `202 Accepted` com `trade_order_id`.
2. Rails chama o serviço Go: `POST http://trading-engine:8090/trade_orders` (Echo). O Echo valida o payload, **enfileira internamente** (worker pool) e responde `202` rápido.
3. Um worker Go executa a ordem e, dentro de **uma transação Postgres**, liquida (debita/credita contas com `FOR UPDATE`) e atualiza `trade_orders`/`transactions`.
4. Go publica o resultado no **broadcast do AnyCable** (Redis `/2`), no stream `trade_orders:<account_id>`.
5. `anycable-go` entrega a mensagem ao cliente inscrito → **tela atualiza em realtime**.

> **Durabilidade (opção):** a fila interna do Echo é in-memory. Para resiliência a restart do serviço Go, a ingestão pode persistir em **Redis Streams** (consumer group) antes de processar — ver §6.4. A escolha não muda o contrato HTTP com o Rails.

---

## 5. Domínio de trading no Rails (novo) — proposta

### 5.1 Modelo `TradeOrder` (migração nova, schema é dono no Rails)
| Coluna | Tipo | Notas |
| --- | --- | --- |
| `id` | bigint | PK |
| `tenant_id` | bigint | `acts_as_tenant` |
| `user_id`, `account_id` | bigint | dono da ordem |
| `side` | string | `buy` / `sell` |
| `base_currency` | string | ex.: `BTC` |
| `quote_currency` | string | ex.: `USD` (casa com `accounts.currency`) |
| `amount` | decimal(20,8) | quantidade base |
| `limit_price` | decimal(20,8) | preço limite (nullable = market) |
| `status` | integer (enum) | `pending`/`processing`/`executed`/`partially_filled`/`rejected`/`failed` |
| `filled_amount` | decimal(20,8) | preenchido |
| `avg_price`, `fee` | decimal | resultado |
| `idempotency_key` | string | dedup (índice único) |
| `lock_version` | integer | optimistic lock (consistente com `transactions`) |
| `processed_at` | datetime | |

- Endpoint: `POST /api/v1/trade_orders` (com header `Idempotency-Key`, reusando o concern `Idempotent`), `GET /api/v1/trade_orders/:id` (status; fallback ao realtime).

### 5.2 Quem é dono de quê
- **Rails (repo Wallet API):** API pública, validação de entrada, criação do `TradeOrder(pending)`, **schema/migrations**, entrega realtime (canais AnyCable), endpoint de status, e a chamada HTTP ao serviço Go.
- **Go (repo `wallet-trading-engine`):** servidor Echo, execução/matching, cálculo de fee, **liquidação** (escrita em `accounts`/`transactions`/`trade_orders`), publicação do broadcast AnyCable.

---

## 6. Projeto Go separado: `wallet-trading-engine`

### 6.1 Estrutura do repositório (independente)
```
wallet-trading-engine/
├── go.mod / go.sum
├── Dockerfile                  # multi-stage: golang:1.23 → distroless/static
├── docker-compose.yml          # (opcional) p/ rodar o serviço isolado em dev
├── cmd/server/main.go          # bootstrap do Echo
├── internal/
│   ├── http/                   # handlers Echo (trade_orders, health, metrics) + middlewares
│   ├── engine/                 # execução/matching/fees (worker pool)
│   ├── settlement/             # liquidação Postgres (pgx, FOR UPDATE)
│   ├── broadcast/              # publisher AnyCable (Redis)
│   └── config/                 # env/config
└── *_test.go                   # unit + integração (go test -race)
```

### 6.2 Servidor Echo (HTTP)
- `github.com/labstack/echo/v4` com middlewares `Logger`, `Recover`, `RequestID`.
- Endpoints:
  - `POST /trade_orders` — recebe a ordem do Rails, valida, enfileira no worker pool, responde `202 Accepted` com `{ "accepted": true, "trade_order_id": 123 }`.
  - `GET /health` — checa Postgres + Redis (healthcheck do Docker/compose).
  - `GET /metrics` — métricas (Prometheus) opcional.
- **Auth serviço-a-serviço:** header compartilhado `X-Internal-Token` (env nos dois lados) e/ou rede interna do Docker; o endpoint não é exposto publicamente.

### 6.3 Stack Go
- `labstack/echo/v4` (HTTP), `jackc/pgx/v5` (Postgres), `redis/go-redis/v9` (broadcast/streams), `shopspring/decimal` (dinheiro), `log/slog` (logs). Worker pool configurável (`TRADING_CONCURRENCY`).

### 6.4 Transporte de ingestão (decisão)
- **Primário (recomendado): HTTP via Echo** — `Rails → POST /trade_orders`. Simples, sem broker extra, contrato explícito. Resposta `202` imediata; processamento assíncrono no worker pool.
- **Durabilidade opcional: Redis Streams** — o handler Echo grava a ordem numa stream (`XADD trade_orders.requested`) e os workers consomem via consumer group (`XREADGROUP`/`XACK`). Recomendado se "não perder ordem em restart do serviço Go" for requisito. Mantém o **mesmo** contrato HTTP com o Rails.

---

## 7. Contrato de integração Rails ↔ Go

### 7.1 Ordem (Rails → Echo) — `POST /trade_orders`
```http
POST /trade_orders HTTP/1.1
Host: trading-engine:8090
Content-Type: application/json
X-Internal-Token: <segredo compartilhado>
```
```json
{
  "trade_order_id": 123,
  "tenant_id": 1,
  "user_id": 7,
  "account_id": 5,
  "side": "buy",
  "base_currency": "BTC",
  "quote_currency": "USD",
  "amount": "0.50000000",
  "limit_price": "65000.00000000",
  "idempotency_key": "trade-abc-123",
  "requested_at": "2026-06-12T02:30:00Z",
  "schema_version": 1
}
```
Resposta: `202 Accepted` `{ "accepted": true, "trade_order_id": 123 }` (ou `409` se `idempotency_key` já processado).

### 7.2 Resultado (Go → AnyCable broadcast)
- Publicado no stream **`trade_orders:<account_id>`** (nome previsível — ver §8).
```json
{
  "event": "trade.executed",
  "trade_order_id": 123,
  "status": "executed",
  "filled_amount": "0.50000000",
  "avg_price": "64980.00000000",
  "fee": "12.99",
  "balance_after": { "USD": "967.51", "BTC": "0.50000000" },
  "executed_at": "2026-06-12T02:30:00.512Z",
  "schema_version": 1
}
```

---

## 8. Realtime via AnyCable (Go publicando broadcast)

- O AnyCable separa **publisher** (qualquer linguagem) do servidor WS. O projeto Go publica `{ "stream": "<nome>", "data": "<json>" }` no backend de broadcast (Redis `redisx`/pub/sub, DB `/2`, definido na spec AnyCable).
- **Nome de stream previsível:** o canal Rails usa `stream_from "trade_orders:#{account_id}"` (e **não** `stream_for(model)`, cujo nome é baseado em GlobalID e seria difícil reproduzir no Go). Assim o Go computa exatamente o mesmo nome.
- Canal Rails novo `app/channels/trade_orders_channel.rb`:
```ruby
class TradeOrdersChannel < ApplicationCable::Channel
  def subscribed
    account = current_user.account
    reject unless account
    stream_from "trade_orders:#{account.id}"
  end
end
```
- Isolamento multi-tenant: stream por `account_id` (pertence a um tenant) e `Connection` autentica via JWT (spec AnyCable). O Go só publica para o `account_id` da ordem.
- **Tela (realtime):** o cliente assina `TradeOrdersChannel`; ao receber `trade.executed`/`rejected`, atualiza a linha da ordem e o saldo sem polling.

---

## 9. Consistência, locking e idempotência

- **Dois escritores no mesmo Postgres** (Rails e Go). Regras:
  - Go liquida **sempre** dentro de `BEGIN … COMMIT` com `SELECT … FOR UPDATE` nas linhas de `accounts` (mesma semântica do `Account.lock` do `DepositService`).
  - Respeitar `lock_version` (optimistic lock do ActiveRecord): incrementar ao atualizar via Go ou serializar com `FOR UPDATE`. Documentar para não quebrar o AR.
  - Garantir saldo não-negativo (validação no Go + possível `CHECK`).
- **Idempotência:** dedup por `idempotency_key` (índice único em `trade_orders`); reprocessar a mesma ordem não duplica liquidação. Confirmar/`XACK` (se usar Streams) só após commit + broadcast.
- **Ordenação:** particionar workers por hash de `account_id` para não reordenar liquidações da mesma conta.

---

## 10. Observabilidade & resiliência

- `GET /health` (Echo) checa Postgres + Redis → usado pelo healthcheck do compose.
- Métricas (`/metrics`): ordens processadas, latência, falhas, profundidade da fila/stream.
- Logs estruturados (`slog`) com `trade_order_id`, `tenant_id`, `account_id`, `request_id` (middleware Echo).
- **Retry/backoff** + **dead-letter** após N tentativas; se usar Streams, `XAUTOCLAIM` para mensagens de consumers mortos.
- Timeouts e `Recover` middleware no Echo.

---

## 11. Docker

### 11.1 Imagem do projeto Go (no repo `wallet-trading-engine`)
- `Dockerfile` multi-stage: `golang:1.23` (build) → imagem `distroless/static` ou `scratch` (runtime), binário estático, usuário não-root, `EXPOSE 8090`.
- Publicada num registry (ex.: `ghcr.io/<org>/wallet-trading-engine:<tag>`).

### 11.2 Referência no `docker-compose.yml` do Wallet API
Adicionar o serviço (da spec anterior do compose):

| Serviço | Imagem/build | Porta | Papel |
| --- | --- | --- | --- |
| `trading-engine` | `image: ghcr.io/<org>/wallet-trading-engine:<tag>` **ou** `build: ../wallet-trading-engine` | 8090 | Echo: ingestão + execução + liquidação + broadcast |

- Como é **projeto à parte**, há duas formas de uso no compose:
  - **Imagem publicada** (recomendado): `image: ...` — não precisa do código-fonte ao lado.
  - **Build context externo** (dev local): `build: { context: ../wallet-trading-engine }` assumindo os repos lado a lado (ou git submodule).
- Variáveis: `DATABASE_URL=postgres://postgres:postgres@db:5432/wallet_api_development`, `ANYCABLE_BROADCAST_REDIS_URL=redis://redis:6379/2`, `TRADING_CONCURRENCY`, `INTERNAL_TOKEN` (igual no Rails), `PORT=8090`.
- `depends_on`: `db` (healthy), `redis` (healthy).
- `web`/`sidekiq` ganham `TRADING_ENGINE_URL=http://trading-engine:8090` e `INTERNAL_TOKEN`.

---

## 12. Critérios de aceitação

1. `docker compose up` (Wallet API) sobe o `trading-engine` (imagem/build do projeto à parte) saudável (`GET /health` 200).
2. `POST /api/v1/trade_orders` cria `TradeOrder(pending)`, retorna `202` + `trade_order_id` e o Rails chama o Echo (`POST /trade_orders`) com sucesso.
3. O serviço Go executa, liquida no Postgres (saldos das contas mudam corretamente) e marca `executed`/`rejected`.
4. Um cliente WS inscrito em `TradeOrdersChannel` recebe `trade.executed`/`rejected` **em tempo real**, sem polling, com saldo atualizado.
5. **Idempotência:** reenviar a mesma ordem (mesmo `idempotency_key`) **não** duplica a liquidação (`409`/no-op).
6. **Concorrência/consistência:** sob N ordens simultâneas na mesma conta, saldo final correto e nunca negativo (sem corrida com depósitos do Rails).
7. Testes Go (`go test -race`) e specs Rails (contrato HTTP + canal) passam; `bin/rubocop` sem ofensas novas.

---

## 13. Plano de testes

- **Go (repo à parte):** unit (execução/fee/validação, handlers Echo com `httptest`), integração com Postgres+Redis efêmeros (testcontainers), idempotência e concorrência (`go test -race`).
- **Rails:** spec de request (`POST /api/v1/trade_orders` cria registro + chama o Go — HTTP mockado via WebMock), spec de canal `TradeOrdersChannel`, modo de teste do AnyCable.
- **E2E manual:** `docker compose up` → login (`POST /session`, seeds `alice@demo.com`/`password123`) → assinar `TradeOrdersChannel` via `websocat` → `POST /api/v1/trade_orders` → observar `trade.executed` no WS e o saldo no Postgres.
- **Evidência:** logs do `trading-engine` (Echo recebe → settle → broadcast), payload no WS, diff de saldo no banco.

---

## 14. Plano de implementação (fases)

1. **Domínio Rails:** migração `trade_orders`, modelo, endpoint `POST/GET /api/v1/trade_orders` (com `Idempotent`).
2. **Cliente HTTP Rails → Go:** serviço que chama `POST /trade_orders` no Echo (com `INTERNAL_TOKEN`, timeouts, tratamento de erro).
3. **Canal realtime:** `TradeOrdersChannel` com `stream_from "trade_orders:#{account_id}"` (depende da spec AnyCable).
4. **Projeto Go à parte:** criar repo `wallet-trading-engine` — app Echo (`/trade_orders`, `/health`), worker pool, liquidação `FOR UPDATE`, publisher de broadcast AnyCable, `Dockerfile`, CI.
5. **Resiliência:** idempotência, retry/backoff, dead-letter (e Redis Streams se durabilidade for requisito).
6. **Docker/compose:** referenciar a imagem/build do projeto Go + envs no Wallet API.
7. **Testes + docs:** specs/tests, `README.md` (seção Trading Engine) e `AGENTS.md` (como subir/depurar o serviço Go separado).
8. **Validação:** rodar critérios de aceitação (§12) e anexar evidências.

---

## 15. Riscos & considerações

- **Projeto separado = coordenação:** schema é dono do Rails, mas o Go lê/escreve nele → versionar o contrato (`schema_version`), alinhar migrações e ter CI que valide compatibilidade. Mudança de schema vira processo coordenado entre os dois repos.
- **Dois escritores no Postgres:** mitigar com `FOR UPDATE`, respeito ao `lock_version` e testes de concorrência. Alternativa mais segura (e mais lenta): Go chama endpoint interno do Rails para liquidar — descarta o ganho de performance.
- **Ingestão HTTP in-memory:** risco de perda em restart → usar Redis Streams se for inaceitável (§6.4).
- **Nome de stream do AnyCable:** precisa casar exatamente entre Rails (`stream_from`) e Go (publisher); evitar `stream_for` (GlobalID).
- **Decimais/dinheiro:** `decimal` em Go e `decimal(20,8)`/`numeric` no banco para evitar erro de ponto flutuante.
- **Segurança serviço-a-serviço:** `INTERNAL_TOKEN` + rede interna do Docker; o endpoint Echo não é exposto publicamente. O Go não precisa do `SECRET_KEY_BASE` (publica broadcast por nome de stream).

---

## 16. Arquivos / artefatos afetados (resumo)

### Repositório Wallet API (Rails)
| Arquivo | Ação |
| --- | --- |
| `db/migrate/*_create_trade_orders.rb`, `db/schema.rb` | **novo** modelo |
| `app/models/trade_order.rb` | **novo** |
| `app/controllers/api/v1/trade_orders_controller.rb` | **novo** (`create`/`show`, usa `Idempotent`) |
| `config/routes.rb` | `resources :trade_orders, only: %i[create show]` |
| `app/services/trading_engine_client.rb` | **novo** (HTTP `POST /trade_orders` no Echo) |
| `app/channels/trade_orders_channel.rb` | **novo** (realtime) |
| `docker-compose.yml`, `.env.example` | add serviço `trading-engine` (imagem/build externo) + envs |
| `spec/requests/api/v1/trade_orders_spec.rb`, `spec/channels/trade_orders_channel_spec.rb` | **novos** |
| `README.md`, `AGENTS.md` | docs |

### Projeto separado `wallet-trading-engine` (Go/Echo) — **repo novo**
| Artefato | Ação |
| --- | --- |
| `go.mod`, `cmd/server/main.go` | **novo** (bootstrap Echo) |
| `internal/http`, `internal/engine`, `internal/settlement`, `internal/broadcast`, `internal/config` | **novos** pacotes |
| `Dockerfile`, CI | **novos** |
| `*_test.go` | **novos** testes |

---

## 17. Questões em aberto / decisões a confirmar

1. **Localização do repo Go:** organização/nome (`wallet-trading-engine`?) e se o compose usará **imagem publicada** (recomendado) ou **build context** de repo vizinho/submodule.
2. **Pernas de liquidação:** trade como único `Transaction type:"Trade"` (novo type no enum/validação) **ou** par débito/crédito reaproveitando os types existentes? *(Proposta: novo type `Trade` + metadata.)*
3. **Multi-moeda:** `accounts` é por `currency` única (`[tenant,user,currency]`). Trading `BTC/USD` exige conta por moeda — confirmar contas `BTC` + `USD`. *(Proposta: contas por moeda.)*
4. **Durabilidade da ingestão:** HTTP in-memory (simples) vs Redis Streams (durável). *(Proposta: HTTP primeiro; Streams se virar requisito.)*
5. **Liquidação:** Go escreve direto no Postgres (recomendado p/ performance) vs Go → endpoint interno Rails. *(Proposta: Go escreve direto com `FOR UPDATE`.)*
6. **Matching:** execução simples (preço dado/oracle) vs order book real. *(Proposta: execução simples; order book fora do escopo.)*

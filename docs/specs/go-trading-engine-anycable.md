# Spec de Feature: Extrair processamento de transactions de trading para serviço Go + realtime via AnyCable

- **Status:** Proposta (spec, sem implementação ainda)
- **Autor:** Cloud Agent
- **Branch:** `cursor/spec-go-trading-engine-anycable-5e2a`
- **Depende de:** `docs/specs/anycable-rpc-docker-compose.md` (AnyCable + docker-compose precisam existir primeiro)
- **Relacionado:** `app/services/*`, `app/sidekiq/*`, `app/models/transaction.rb`, `config/cable.yml`

---

## 1. Objetivo

Extrair o **processamento (execução + liquidação) de transactions de trading** do Rails/Sidekiq para um **serviço Go dedicado** (`trading-engine`), de alta concorrência e baixa latência, mantendo o Rails como dono da **API REST**, do **schema/persistência** e da **entrega realtime**. O **resultado da execução é refletido em tela em tempo real** via **AnyCable** — o serviço Go publica o resultado diretamente no backend de broadcast do AnyCable, que entrega ao cliente WebSocket.

Em uma frase: *Rails recebe a ordem → enfileira para o Go → Go executa/liquida com concorrência → publica o resultado no AnyCable → a tela do usuário atualiza sozinha.*

---

## 2. Contexto / Estado atual

- Hoje todo o processamento de movimentação de dinheiro é **síncrono no Rails** (`DepositService`, `WithdrawalService`, `TransferService`) ou **assíncrono via Sidekiq** (`BatchDepositJob`, `TransferProcessorJob`), usando lock pessimista (`Account.lock`) e otimista (`lock_version`).
- **Não existe domínio de "trading"/"order"** ainda — só `Transaction` (STI: `Deposit`, `Withdrawal`, `Transfer`). Esta spec **introduz** esse domínio.
- A entrega realtime é endereçada pela spec do **AnyCable** (`docs/specs/anycable-rpc-docker-compose.md`): servidor WS em Go (`anycable-go`), broadcast via Redis. Esta feature **reaproveita esse canal de broadcast**.
- Stack já tem Postgres (fonte de verdade), Redis e `docker-compose` (após a spec anterior).

### Por que Go para trading
- Execução de ordens é **CPU/concorrência-intensiva** (matching, validações, fees) e sensível a latência.
- Descola o trabalho pesado do Puma/Sidekiq; escala independentemente.
- Permite um **matching engine** in-memory com goroutines, sem prender workers Ruby.

---

## 3. Escopo

### Dentro do escopo
- Definir o **domínio mínimo de trading** no Rails (modelo `TradeOrder` + migração + endpoint `POST /api/v1/trade_orders`).
- Serviço Go `trading-engine`: consumo de ordens, execução/liquidação, persistência do resultado e publicação do resultado no AnyCable.
- **Contrato de mensagens** Rails↔Go (transporte: Redis Streams; alternativa: gRPC).
- **Canal realtime** `TradeOrdersChannel` (stream previsível por conta) e integração com a tela.
- Estratégia de **consistência/locking/idempotência** entre Rails e Go escrevendo no mesmo Postgres.
- Adição do serviço `trading-engine` ao `docker-compose`.
- Observabilidade, retries, dead-letter e healthcheck.
- Testes (Go + specs Rails de contrato/canal) e docs.

### Fora do escopo
- Order book completo / múltiplos níveis de preço / market data feed (apenas execução simples; evolução futura).
- Reescrever depósitos/saques/transferências existentes (continuam no Rails).
- Deploy de produção (Kamal) — apenas observação.

---

## 4. Arquitetura proposta

```
                REST                         Redis Stream "trade_orders.requested"
 cliente ───────────────► Rails web (Puma) ───────────────────────────────────┐
   ▲                       │  cria TradeOrder(status=pending)                  │
   │                       │  XADD payload da ordem                            ▼
   │                                                          ┌─────────────────────────────┐
   │ WebSocket (realtime)                                     │   trading-engine (Go)        │
   │                                                          │  - consumer group (XREADGROUP)│
   │                                                          │  - matching/execução          │
   │                                                          │  - liquidação (Postgres)      │
   │                                                          │    SELECT ... FOR UPDATE      │
   │                                                          └───────┬──────────────┬────────┘
   │                                                                  │ escreve       │ publica
   │                                                                  ▼ resultado     ▼ broadcast
   │                                                          ┌──────────────┐  ┌──────────────┐
   │                                                          │  Postgres    │  │ Redis (pub/sub│
   │                                                          │ trade_orders │  │  AnyCable /2) │
   │                                                          │ accounts     │  └──────┬───────┘
   │                                                          │ transactions │         │ stream
   │                                                          └──────────────┘         ▼
   │                                                                          ┌──────────────────┐
   └──────────────────────────────────────────────────────────────────────► │  anycable-go     │
                            entrega "trade.executed" ao WS do usuário         │  (:8080 WS)      │
                                                                              └──────────────────┘
```

Fluxo:
1. `POST /api/v1/trade_orders` → Rails valida, cria `TradeOrder(status: pending)`, faz `XADD` na stream `trade_orders.requested` e responde `202 Accepted` com `trade_order_id`.
2. `trading-engine` (Go) consome via **consumer group** (entrega ao-menos-uma-vez), executa a ordem, e dentro de **uma transação Postgres** liquida (debita/credita contas com `FOR UPDATE`) e atualiza `trade_orders`/`transactions`.
3. Go publica o resultado no **broadcast do AnyCable** (Redis), no stream `trade_orders:<account_id>`.
4. `anycable-go` entrega a mensagem ao cliente inscrito → **tela atualiza em realtime**.
5. `XACK` da mensagem; em falha, retry/backoff e, após N tentativas, dead-letter (`trade_orders.dead`).

---

## 5. Domínio de trading (novo) — proposta

### 5.1 Modelo Rails `TradeOrder` (migração nova, schema é dono no Rails)
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
| `idempotency_key` | string | dedup (reaproveita conceito existente) |
| `lock_version` | integer | optimistic lock (consistente com `transactions`) |
| `processed_at` | datetime | |

- Reusar o enum/STI de `Transaction` para registrar as pernas de liquidação (ex.: criar `Transaction` `type: "Trade"` ou pernas `Deposit`/`Withdrawal`), decisão em §17.
- Endpoint: `POST /api/v1/trade_orders` (com header `Idempotency-Key`, reusando o concern `Idempotent`), `GET /api/v1/trade_orders/:id` para status (fallback ao realtime).

### 5.2 Quem é dono de quê
- **Rails:** API, validação de entrada, criação do `TradeOrder(pending)`, **schema/migrations**, entrega realtime (canais AnyCable), endpoint de status.
- **Go (`trading-engine`):** execução/matching, cálculo de fee, **liquidação** (escrita em `accounts`/`transactions`/`trade_orders`), publicação do broadcast.

---

## 6. Serviço Go `trading-engine`

### 6.1 Responsabilidades
- Consumir `trade_orders.requested` (Redis Streams, consumer group `trading-engine`).
- Validar/executar a ordem (preço, saldo, limites) com concorrência (goroutines + worker pool).
- Liquidar em Postgres numa transação ACID.
- Publicar resultado no AnyCable.
- Idempotência, retry/backoff, dead-letter, métricas e health.

### 6.2 Stack Go sugerida
- `github.com/jackc/pgx/v5` (Postgres), `github.com/redis/go-redis/v9` (streams + pub/sub), `shopspring/decimal` (dinheiro), `log/slog` (logs estruturados), `net/http` (`/health`).
- Worker pool configurável (`TRADING_CONCURRENCY`).

### 6.3 Transporte (decisão)
- **Recomendado: Redis Streams** — já temos Redis; entrega ao-menos-uma-vez via consumer groups, `XACK`, backlog persistente, e desacopla Rails do Go. Naturalmente idempotente com dedup por `idempotency_key`.
- **Alternativa: gRPC** (Rails → Go `ExecuteTrade`) — menor latência, porém acopla e exige o Go up para aceitar ordens. Streams é preferível para resiliência.

---

## 7. Contrato de integração Rails ↔ Go

### 7.1 Ordem (Rails → Go) — `XADD trade_orders.requested`
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
  "requested_at": "2026-06-12T02:30:00Z"
}
```

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
  "executed_at": "2026-06-12T02:30:00.512Z"
}
```
- Versionar o contrato (campo `schema_version`) e manter compatibilidade.

---

## 8. Realtime via AnyCable (Go publicando broadcast)

- O AnyCable separa **publisher** (qualquer linguagem) do servidor WS. O Go publica uma mensagem `{ "stream": "<nome>", "data": "<json>" }` no backend de broadcast (Redis `redisx`/pub/sub configurado na spec anterior, DB `/2`).
- **Nome de stream previsível:** o canal Rails deve usar `stream_from "trade_orders:#{account_id}"` (e **não** `stream_for(model)`, que gera nome baseado em GlobalID e seria difícil de reproduzir no Go). Assim o Go computa exatamente o mesmo nome.
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
- Isolamento multi-tenant: o stream é por `account_id` (que pertence a um tenant) e a `Connection` autentica via JWT (ver spec AnyCable). O Go só publica para o `account_id` da ordem.
- **Tela (realtime):** o cliente assina `TradeOrdersChannel`; ao receber `trade.executed`/`rejected`, atualiza a linha da ordem e o saldo sem polling. (Se houver SPA, é um handler de `received`; um cliente de exemplo será incluído para validação.)

---

## 9. Consistência, locking e idempotência

- **Dois escritores no mesmo Postgres** (Rails e Go). Regras:
  - Go liquida **sempre** dentro de `BEGIN … COMMIT` com `SELECT … FOR UPDATE` nas linhas de `accounts` (mesma semântica do `Account.lock` do `DepositService`) → evita corrida com depósitos/saques do Rails.
  - Respeitar `lock_version` (optimistic lock do ActiveRecord): ao atualizar via Go, incrementar `lock_version` ou usar `FOR UPDATE` para serializar. Documentar para não quebrar o AR.
  - `CHECK (balance >= 0)` / validação no Go para não permitir saldo negativo.
- **Idempotência:** dedup por `idempotency_key` na tabela `trade_orders` (índice único) — reprocessamento da mesma mensagem da stream não duplica liquidação. `XACK` só após commit + broadcast.
- **Entrega ao-menos-uma-vez:** o handler deve ser idempotente (checar `status` já terminal antes de executar).
- **Ordenação:** por `account_id` para evitar reordenar liquidações da mesma conta (ex.: particionar workers por hash de `account_id`).

---

## 10. Observabilidade & resiliência

- `trading-engine` expõe `/health` (Postgres + Redis ok) para o healthcheck do compose.
- Métricas: ordens processadas, latência, falhas, profundidade de backlog da stream.
- Logs estruturados (`slog`) com `trade_order_id`, `tenant_id`, `account_id`.
- **Retry/backoff** + **dead-letter** `trade_orders.dead` após N tentativas; alarme/observação manual.
- `XAUTOCLAIM` para reprocessar mensagens de consumers mortos (pending entries).

---

## 11. Docker Compose

Adicionar ao `docker-compose.yml` (da spec anterior):

| Serviço | Build/Imagem | Porta | Papel |
| --- | --- | --- | --- |
| `trading-engine` | build `go/trading-engine/Dockerfile` | 8090 (`/health`) | Consumir ordens, executar, liquidar, broadcast |

- Variáveis: `DATABASE_URL=postgres://postgres:postgres@db:5432/wallet_api_development`, `REDIS_URL=redis://redis:6379/0`, `ANYCABLE_BROADCAST_REDIS_URL=redis://redis:6379/2`, `TRADING_CONCURRENCY`, `TRADING_STREAM=trade_orders.requested`, `TRADING_GROUP=trading-engine`.
- `depends_on`: `db` (healthy), `redis` (healthy).
- Código Go em `go/trading-engine/` (módulo próprio, multi-stage Dockerfile `golang:1.23 → distroless`).
- `web`/`sidekiq` ganham a env `TRADING_STREAM` para `XADD`.

---

## 12. Critérios de aceitação

1. `docker compose up` sobe também o `trading-engine` saudável (`/health` 200).
2. `POST /api/v1/trade_orders` cria `TradeOrder(pending)`, retorna `202` + `trade_order_id` e enfileira na stream.
3. O `trading-engine` consome, liquida no Postgres (saldo das contas muda corretamente) e marca `executed`/`rejected`.
4. Um cliente WS inscrito em `TradeOrdersChannel` recebe `trade.executed`/`rejected` **em tempo real**, sem polling, com saldo atualizado.
5. **Idempotência:** reenviar a mesma ordem (mesmo `idempotency_key`) **não** duplica a liquidação.
6. **Concorrência/consistência:** sob N ordens simultâneas na mesma conta, o saldo final é correto e nunca negativo (sem corrida com depósitos do Rails).
7. Testes Go (unit + integração) e specs Rails (contrato de enfileiramento + canal) passam; `bin/rubocop` sem ofensas novas.

---

## 13. Plano de testes

- **Go:** unit (execução/fee/validação), integração com Postgres+Redis efêmeros (testcontainers ou serviços do compose), teste de idempotência e de concorrência (race no `go test -race`).
- **Rails:** spec de request (`POST /api/v1/trade_orders` cria registro + `XADD` mockado), spec de canal `TradeOrdersChannel` (stream correto), modo de teste do AnyCable.
- **E2E manual:** `docker compose up` → login (`POST /session`, seeds `alice@demo.com`/`password123`) → assinar `TradeOrdersChannel` via `websocat` → `POST /api/v1/trade_orders` → observar broadcast `trade.executed` no WS e o saldo no Postgres.
- **Evidência:** logs do `trading-engine` (consume→settle→broadcast), payload recebido no WS, e diff de saldo no banco.

---

## 14. Plano de implementação (fases)

1. **Domínio Rails:** migração `trade_orders`, modelo, endpoint `POST/GET /api/v1/trade_orders` (com `Idempotent`), `XADD` na criação.
2. **Canal realtime:** `TradeOrdersChannel` com `stream_from "trade_orders:#{account_id}"` (depende da spec AnyCable).
3. **Serviço Go:** consumer de stream, executor, liquidação com `FOR UPDATE`, publisher de broadcast AnyCable, `/health`.
4. **Resiliência:** idempotência, retry/backoff, dead-letter, `XAUTOCLAIM`.
5. **Docker:** `go/trading-engine/Dockerfile` + serviço no compose + envs.
6. **Testes + docs:** specs/tests, `README.md` (seção Trading Engine) e `AGENTS.md` (como subir/depurar o serviço Go).
7. **Validação:** rodar critérios de aceitação (§12) e anexar evidências.

---

## 15. Riscos & considerações

- **Dois escritores no Postgres:** maior risco. Mitigar com `FOR UPDATE`, respeito ao `lock_version` e testes de concorrência. Alternativa mais segura (e mais lenta): Go chama um endpoint interno do Rails para liquidar — descarta o ganho de performance, então só se a corrida se mostrar inviável.
- **Acoplamento de schema:** o Go depende do schema dono do Rails; mudanças de migração exigem coordenação (versionar contrato, CI que roda ambos).
- **Nome de stream do AnyCable:** precisa casar exatamente entre Rails (`stream_from`) e Go (publisher); por isso evitar `stream_for` (GlobalID).
- **Entrega ao-menos-uma-vez:** handlers devem ser idempotentes; `XACK` só pós-commit.
- **Decimais/dinheiro:** usar `decimal` em Go e `decimal(20,8)` no banco para casar com `numeric` do Postgres e evitar erro de ponto flutuante.
- **Segurança:** `SECRET_KEY_BASE` compartilhado já é tratado na spec AnyCable; o Go não precisa dele para publicar broadcast (publica por nome de stream).

---

## 16. Arquivos afetados (resumo)

| Arquivo | Ação |
| --- | --- |
| `db/migrate/*_create_trade_orders.rb`, `db/schema.rb` | **novo** modelo |
| `app/models/trade_order.rb` | **novo** |
| `app/controllers/api/v1/trade_orders_controller.rb` | **novo** (`create`/`show`, usa `Idempotent`) |
| `config/routes.rb` | `resources :trade_orders, only: %i[create show]` |
| `app/services/trade_order_enqueuer.rb` | **novo** (`XADD` para a stream) |
| `app/channels/trade_orders_channel.rb` | **novo** (realtime) |
| `go/trading-engine/**` | **novo** serviço Go (módulo, Dockerfile) |
| `docker-compose.yml`, `.env.example` | add serviço `trading-engine` + envs |
| `spec/requests/api/v1/trade_orders_spec.rb`, `spec/channels/trade_orders_channel_spec.rb` | **novos** |
| `go/trading-engine/*_test.go` | **novos** |
| `README.md`, `AGENTS.md` | docs |

---

## 17. Questões em aberto / decisões a confirmar

1. **Pernas de liquidação:** registrar trade como um único `Transaction type:"Trade"` (precisa novo type no enum/validação) **ou** como par débito/crédito reaproveitando os types existentes? *(Proposta: novo type `Trade` + metadata com detalhes da execução.)*
2. **Multi-moeda:** o modelo atual de `accounts` é por `currency` única (`[tenant,user,currency]`). Trading `BTC/USD` exige conta por moeda — confirmar se haverá conta `BTC` além de `USD`, ou se trade é só "execução de preço" debitando/creditando em `USD`. *(Proposta: contas por moeda; ordem afeta a conta base e a quote.)*
3. **Transporte:** Redis Streams (recomendado) vs gRPC. *(Proposta: Streams.)*
4. **Liquidação:** Go escreve direto no Postgres (recomendado p/ performance) vs Go → endpoint interno Rails. *(Proposta: Go escreve direto com `FOR UPDATE`.)*
5. **Matching:** execução simples (preço dado/oracle) vs order book real. *(Proposta: execução simples nesta fase; order book fora do escopo.)*

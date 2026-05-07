# Testing Guide - Multi-Tenancy + Idempotency

Como testar a aplicação com multi-tenancy e idempotência.

## Rodar Testes

```bash
# Todos os testes
rails test

# Testes específicos
rails test test/services/registration_service_test.rb
rails test test/controllers/registrations_controller_test.rb
rails test test/controllers/api/v1/deposits_controller_test.rb

# Com output verboso
rails test --verbose

# Em paralelo
rails test --parallel=4
```

## Estrutura de Testes

```
test/
├── models/                  # Model tests
│   ├── tenant_test.rb
│   ├── user_test.rb
│   ├── account_test.rb
│   └── transaction_test.rb
├── controllers/             # Controller tests
│   ├── sessions_controller_test.rb
│   ├── registrations_controller_test.rb
│   └── api/v1/
│       ├── deposits_controller_test.rb
│       └── withdrawals_controller_test.rb
├── services/                # Service tests
│   ├── registration_service_test.rb
│   ├── deposit_service_test.rb
│   └── withdrawal_service_test.rb
└── test_helpers/
    └── session_test_helper.rb
```

## Testes de Multi-Tenancy

### 1. Tenant Isolation (RegistrationService)

```ruby
test "successful registration creates tenant user and account" do
  result = RegistrationService.call(
    email_address: "admin@company.com",
    password: "password123",
    password_confirmation: "password123",
    tenant_name: "New Company"
  )

  assert result.success?
  assert_equal "New Company", result.user.tenant.name
  assert result.user.admin?
end
```

**O que testa**:
- ✅ Tenant é criado com dados corretos
- ✅ User é criado como admin
- ✅ Account é criada com saldo 0
- ✅ Subdomain é gerado automaticamente

### 2. Tenant Isolation (Controllers)

```ruby
test "deposit is isolated by tenant" do
  # Setup dois tenants
  @tenant1 = Tenant.create!(name: "Tenant 1", subdomain: "t1")
  @user1 = User.create!(tenant: @tenant1, email_address: "u1@example.com")
  @account1 = Account.create!(tenant: @tenant1, user: @user1, balance: 100.00)

  @tenant2 = Tenant.create!(name: "Tenant 2", subdomain: "t2")
  @user2 = User.create!(tenant: @tenant2, email_address: "u2@example.com")
  @account2 = Account.create!(tenant: @tenant2, user: @user2, balance: 50.00)

  # User1 deposita
  token1 = JwtService.encode(@user1)
  post api_v1_deposits_path,
    params: { deposit: { amount: 50.00 } },
    headers: { "Authorization" => "Bearer #{token1}", "Idempotency-Key" => SecureRandom.uuid },
    as: :json

  # Apenas account1 deve ser afetada
  assert_equal 150.00, @account1.reload.balance
  assert_equal 50.00, @account2.reload.balance  # Não muda!
end
```

**O que testa**:
- ✅ Transações são isoladas por tenant
- ✅ User2 não consegue ver/afetar dados do User1
- ✅ Backend filtra automaticamente por Current.tenant

### 3. Idempotência (Controllers)

```ruby
test "deposit with idempotency key is idempotent" do
  token = JwtService.encode(@user)
  idempotency_key = "unique-key-#{SecureRandom.hex}"

  # Primeira requisição
  post api_v1_deposits_path,
    params: { deposit: { amount: 25.00 } },
    headers: {
      "Authorization" => "Bearer #{token}",
      "Idempotency-Key" => idempotency_key
    },
    as: :json

  body1 = JSON.parse(response.body)
  balance1 = @account.reload.balance

  # Mesma requisição novamente
  post api_v1_deposits_path,
    params: { deposit: { amount: 25.00 } },
    headers: {
      "Authorization" => "Bearer #{token}",
      "Idempotency-Key" => idempotency_key
    },
    as: :json

  body2 = JSON.parse(response.body)

  # Resultado idêntico
  assert_equal body1["id"], body2["id"]
  assert_equal balance1, @account.reload.balance  # Não duplica!
end
```

**O que testa**:
- ✅ Requisição idêntica retorna mesmo ID
- ✅ Saldo não é duplicado
- ✅ Idempotency-Key funciona

## Testes de Signup

### Test: RegistrationsController

```bash
rails test test/controllers/registrations_controller_test.rb
```

**Cenários cobertos**:
- ✅ Signup com parâmetros válidos
- ✅ Email em branco falha
- ✅ Senha curta falha
- ✅ Senhas não conferem falha
- ✅ Subdomain duplicado gera novo
- ✅ JWT token pode ser usado para requests autenticadas

### Test: RegistrationService

```bash
rails test test/services/registration_service_test.rb
```

**Cenários cobertos**:
- ✅ Cria tenant, user, account automaticamente
- ✅ Validações de email e senha
- ✅ Subdomain é gerado corretamente
- ✅ Subdomains duplicados são tornados únicos
- ✅ User autenticado após signup

## Fixtures

Fixtures são dados pré-carregados para testes.

```yaml
# test/fixtures/users.yml
one:
  tenant: one
  email_address: user@example.com
  password_digest: <%= BCrypt::Password.create('password', cost: 1) %>
  role: member

two:
  tenant: one
  email_address: other@example.com
  password_digest: <%= BCrypt::Password.create('password', cost: 1) %>
  role: admin
```

Usar em testes:
```ruby
test "example" do
  user = users(:one)  # Carrega fixture
  assert_equal "user@example.com", user.email_address
end
```

## Helpers de Teste

### Session Helper

```ruby
# test/test_helpers/session_test_helper.rb
module SessionTestHelper
  def sign_in_as(user)
    user.sessions.create!(user_agent: "Test", ip_address: "127.0.0.1")
  end
end
```

Usar:
```ruby
test "example" do
  user = users(:one)
  session = sign_in_as(user)
  assert session.persisted?
end
```

## Coverage de Testes

### Frontend Tests

Testes do frontend estão em:
```
wallet_frontend/
```

Para adicionar testes frontend com Vitest:

```bash
npm install --save-dev vitest @testing-library/react @testing-library/jest-dom
```

**Exemplo de teste de componente**:
```javascript
import { render, screen } from '@testing-library/react';
import { Login } from '../src/components/Login';
import { AuthProvider } from '../src/context/AuthContext';

test('shows signup form when signup mode is enabled', () => {
  render(
    <AuthProvider>
      <Login />
    </AuthProvider>
  );

  const signupButton = screen.getByText('Criar Conta');
  signupButton.click();

  expect(screen.getByText('Nome da Organização')).toBeInTheDocument();
});
```

## Performance de Testes

### Velocidade

Os testes rodam em paralelo por padrão:
```ruby
# test/test_helper.rb
parallelize(workers: :number_of_processors)
```

Para rodar sequencialmente:
```bash
rails test --no-parallel
```

### Database Transactions

Cada teste é rodado em uma transação que é revertida:
```ruby
class ActiveSupport::TestCase
  self.use_transactional_tests = true
end
```

Isso torna testes rápidos pois não precisa resetar banco.

## Debugging Testes

### Print Debug

```ruby
test "example" do
  user = users(:one)
  puts "User email: #{user.email_address}"  # Aparece no output
  assert user.persisted?
end
```

Rodar com output:
```bash
rails test --verbose
```

### Pry Debugger

```bash
gem 'pry-rails', group: :test
```

Usar:
```ruby
test "example" do
  user = users(:one)
  binding.pry  # Pausa aqui
  assert user.persisted?
end
```

### Usar Fixtures Específicas

```ruby
test "example" do
  user = users(:one)  # Carrega user one
  account = accounts(:one)
  assert account.user == user
end
```

## CI/CD Integration

### GitHub Actions

```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: password
    steps:
      - uses: actions/checkout@v3
      - uses: ruby/setup-ruby@v1
      - run: bundle install
      - run: rails db:test:prepare
      - run: rails test
```

## Checklist de Testes

Para adicionar nova feature, testar:

- [ ] Model validations
- [ ] Model associations
- [ ] Controller authentication
- [ ] Controller authorization (tenant isolation)
- [ ] Service business logic
- [ ] Idempotency (se houver)
- [ ] Error handling
- [ ] Edge cases
- [ ] Frontend integration (se houver)

## Troubleshooting

### "Tenant not found"
- Verificar se tenant está sendo criado no setup
- Usar `Current.tenant = tenant` se necessário

### "ActiveRecord::RecordNotFound"
- Dados não foram criados no setup
- Usar `assert_raises` se esperado

### "Flaky tests"
- Usar `SecureRandom` para IDs/keys únicos
- Evitar hard-coded timestamps
- Usar `Timecop` se precisar mockear tempo

### Testes lentos
- Profile com `--profile` para ver testes lentos
- Aumentar workers em paralelo
- Evitar queries N+1 com eager loading

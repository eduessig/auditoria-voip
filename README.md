# Auditoria VoIP

Base do microsserviço de auditoria de chamadas para a disciplina de Sistemas Distribuídos. A aplicação Rails API-only usa PostgreSQL e RSpec e possui modelos para chamadas concluídas e mensagens processadas.

## Pré-requisitos

No WSL Ubuntu, instale Git e Docker Desktop com integração WSL habilitada, ou Docker Engine com o plugin Docker Compose. Para execução da API sem containers, instale Ruby 3.3.6, Bundler, PostgreSQL 16 e as bibliotecas de desenvolvimento necessárias para a gem `pg`.

## Executar com Docker Compose

```bash
cp .env.example .env
docker compose up --build
```

A API estará disponível em `http://localhost:3000`. Nesta etapa ainda não existem endpoints da aplicação. O PostgreSQL é persistido no volume `postgres_data`. O container da API aguarda o banco e prepara o banco de desenvolvimento ao iniciar. Para encerrar, use `docker compose down`; o volume permanece preservado.

Para preparar e testar o banco de teste:

```bash
docker compose up -d db
docker compose run --rm -e RAILS_ENV=test api bundle exec rails db:prepare
docker compose run --rm -e RAILS_ENV=test api bundle exec rspec
```

As credenciais de exemplo são apenas para uso local; altere `.env` conforme necessário e nunca versione credenciais reais. Se as credenciais forem alteradas após a criação do volume, o usuário do banco existente também precisará ser atualizado.

## Executar a API no WSL

Com PostgreSQL disponível, copie `.env.example` para `.env` e exporte suas variáveis no shell. A aplicação não carrega `.env` automaticamente fora do Compose.

```bash
set -a
source .env
set +a
export DATABASE_HOST=localhost
bundle install
bundle exec rails db:prepare
bundle exec rails server
```

Em outro terminal, exporte as mesmas variáveis e execute:

```bash
RAILS_ENV=test bundle exec rails db:prepare
RAILS_ENV=test bundle exec rspec
```

O PostgreSQL precisa aceitar as credenciais configuradas e permitir que o usuário crie os bancos. A mensageria e os endpoints de consulta serão adicionados em etapas posteriores.

## Modelo e contrato

As migrations criam `calls` e `processed_messages`, com unicidade, chave estrangeira e restrições de integridade no PostgreSQL. O contrato proposto do evento, suas regras e um exemplo estão em [contracts/](contracts/README.md). A semântica exata da duração ainda precisa ser confirmada com a central; a validação do evento e o processamento transacional pertencem à etapa 3.

Para conferir a reversibilidade das migrations em um banco de teste preparado, execute `RAILS_ENV=test bundle exec rails db:rollback STEP=2` e depois `RAILS_ENV=test bundle exec rails db:migrate`. Em Docker, execute esses comandos com `docker compose run --rm -e RAILS_ENV=test api` antes de `bundle exec`.

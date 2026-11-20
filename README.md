# Auditoria VoIP

Base do microsserviço de auditoria de chamadas para a disciplina de Sistemas Distribuídos. A aplicação Rails API-only usa PostgreSQL e RSpec e possui modelos para chamadas concluídas e mensagens processadas.

## Pré-requisitos

No WSL Ubuntu, instale Git e Docker Desktop com integração WSL habilitada, ou Docker Engine com o plugin Docker Compose. Para execução da API sem containers, instale Ruby 3.3.6, Bundler, PostgreSQL 16 e as bibliotecas de desenvolvimento necessárias para a gem `pg`.

## Executar com Docker Compose

```bash
cp .env.example .env
docker compose up --build
```

A API estará disponível em `http://localhost:3000`; os endpoints de consulta ainda serão implementados. O Compose inicia PostgreSQL, MiniStack, preparação dos recursos, API e consumidor independente. O PostgreSQL é persistido no volume `postgres_data`. Para encerrar, use `docker compose down`; o volume permanece preservado. As filas do MiniStack são locais e podem ser recriadas ao reiniciar o emulador.

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

O PostgreSQL precisa aceitar as credenciais configuradas e permitir que o usuário crie os bancos.

## Fila SQS local

Com o Compose iniciado, publique o mesmo exemplo duas vezes e consulte os registros diretamente no banco:

```bash
docker compose run --rm sqs-setup bundle exec ruby scripts/local_sqs.rb publish
docker compose run --rm sqs-setup bundle exec ruby scripts/local_sqs.rb publish
docker compose logs consumer
docker compose exec db psql -U auditoria -d auditoria_development -c 'SELECT call_id, caller, callee FROM calls; SELECT message_id, call_id FROM processed_messages;'
```

Se as credenciais do banco em `.env` forem diferentes, ajuste o comando `psql`. Cada publicação tem um identificador SQS diferente, mas contém o mesmo `messageId` do contrato: apenas uma chamada e um registro de mensagem são criados. Para publicar outro arquivo, acrescente seu caminho no container após `publish`.

O consumidor usa `AWS_REGION`, `SQS_QUEUE_URL` e, opcionalmente, `SQS_ENDPOINT`; sem endpoint, o SDK usa a cadeia padrão de credenciais AWS. No Compose usam-se exclusivamente credenciais fictícias e MiniStack. O script local exige `SQS_ENDPOINT` HTTP explícito em `localhost`, `127.0.0.1`, `::1` ou `ministack`, ignora credenciais do ambiente e usa `test/test`. Não use o nome `ministack` para um servidor remoto. A fila é criada com visibilidade de 120 segundos e DLQ com cinco recebimentos; mensagens inválidas e conflitos não são excluídos. O consumidor espera até 20 segundos por mensagens, termina o processamento corrente ao receber SIGTERM/SIGINT e somente remove a mensagem após o commit. Erros de recebimento são repetidos com intervalo fixo; backoff com jitter e demonstrações de falhas pertencem à etapa 6.

A documentação do [MiniStack SQS](https://ministack.org/docs/services/sqs) lista suporte a visibilidade e DLQ, e o [código do serviço](https://github.com/ministackorg/ministack/blob/main/ministack/services/sqs.py) implementa long polling e redrive. Para verificar esses recursos na imagem configurada, execute `docker compose run --rm sqs-setup bundle exec ruby scripts/check_local_sqs.rb`. O teste cria filas temporárias locais e as remove ao terminar. As demonstrações completas de falhas continuam na etapa 6.

## Modelo e contrato

As migrations criam `calls` e `processed_messages`, com unicidade, chave estrangeira e restrições de integridade no PostgreSQL. O contrato proposto do evento, suas regras e um exemplo estão em [contracts/](contracts/README.md). A semântica exata da duração ainda precisa ser confirmada com a central; o processamento transacional simulado valida o evento antes de persisti-lo.

Para conferir a reversibilidade das migrations em um banco de teste preparado, execute `RAILS_ENV=test bundle exec rails db:rollback STEP=2` e depois `RAILS_ENV=test bundle exec rails db:migrate`. Em Docker, execute esses comandos com `docker compose run --rm -e RAILS_ENV=test api` antes de `bundle exec`.

## Processamento simulado

Sem depender de SQS, execute o serviço com o exemplo do contrato em um banco preparado:

```bash
docker compose run --rm api bundle exec rails runner 'p CallCompletedProcessor.call(File.read("contracts/call.completed.v1.example.json"))'
```

O serviço retorna `:processed` ao registrar uma mensagem e `:duplicate` em uma reentrega equivalente. Ele lança `CallCompletedProcessor::InvalidMessage` para dados inválidos e `CallCompletedProcessor::Conflict` para identidades reutilizadas com conteúdo incompatível. Chamada e mensagem são gravadas na mesma transação; impressões digitais normalizam fusos e ordem das propriedades. Registros anteriores sem impressões digitais são considerados conflitos, pois seu conteúdo original não pode ser verificado. A duração e o contrato ainda dependem de confirmação com a central.

Os testes de concorrência utilizam conexões independentes com PostgreSQL e exigem um pool de pelo menos cinco conexões.

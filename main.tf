trigger:
  branches:
    include:
      - develop
      - sandbox
      - hotfix/*

variables:
  - name: DevEnvironment
    type: string
    default: 'dev'
    displayName: 'Ambiente: dev, hml, prd'
  - name: HmlEnvironment
    type: string
    default: 'hml'
    displayName: 'Ambiente: dev, hml, prd'
  - name: PrdEnvironment
    type: string
    default: 'prd'
    displayName: 'Ambiente: dev, hml, prd'
  - name: DevEnvironmentRegion
    type: string
    default: 'us-east-2'
    displayName: 'Região: us-east-2, sa-east-1'
  - name: HmlEnvironmentRegion
    type: string
    default: 'us-east-2'
    displayName: 'Região: us-east-2, sa-east-1'
  - name: PrdEnvironmentRegion
    type: string
    default: 'sa-east-1'
    displayName: 'Região: us-east-2, sa-east-1'


parameters:
  - name: rollbackImageTag
    type: string
    default: 'none'
    displayName: 'Rollback PRD: tag/versão a restaurar (vazio = deploy normal)'

resources:
  repositories:
    - repository: templates
      type: git
      name: Fibra.DevOps/fibra-devops-pipelines
      ref: refs/tags/v1.0.28

    - repository: terraform-modules
      type: git
      name: Fibra.DevOps/Fibra.DevOps.Terraform
      ref: refs/heads/main

extends:
  template: templates/stacks/dotnet-backend.yaml@templates
  parameters:
    rollbackImageTag: ${{ parameters.rollbackImageTag }}

    pod:
      min_replicas: '1'
      max_replicas: '1'
      requests_cpu: 100m
      requests_memory: 256Mi
      limits_cpu: 250m
      limits_memory: 512Mi
      cpu_utilization: '70'

    networking:
      ingress_path: /cadastro-corporativo-acl
      base_path: cadastro-corporativo
      api_visibility: private
      deployment_aspnetcore_urls: http://0.0.0.0:8080
      domain_name: dev-api-teste.bancofibra.com.br

    resources:
      dynamodb_tables: []
      s3_buckets: []
      secrets:
        - name: /Cliente/CadastroCorporativo/ACL/SybaseDB
          description: Credenciais de acesso ao banco de dados Sybase do servico ACL de Cadastro Corporativo
          keys:
            - username
            - password
            - database
            - server
            - port
      sqs: 
        - queue_name: "aws_sqs_cadastro_corporativo_sybase_acl"
          fifo_queue: false
        - queue_name: "aws_sqs_cadastro_corporativo_sybase_acl_dlq"
          fifo_queue: false
      sns_topics: []
      sns_sqs_subscriptions:
        - topic_name: "cliente-cadastro-corporativo-manutencao"
          queue_name: "aws_sqs_cadastro_corporativo_sybase_acl"
          fifo_queue: false


    observability:
      dd_lang: dotnet
      dd_lib_version: latest

    config:
      env_vars: []
      ssm_parameters:
        dev: 
          - name: /Cliente/CadastroCorporativo/ACL/Sqs/QueueUrl
            description: URL da fila SQS consumida pelo ACL de Cadastro Corporativo (dev)
            type: String
            value: "https://sqs.${DevEnvironmentRegion}.amazonaws.com/$(AWS_ACCOUNT_ID)/sqs-${DevEnvironment}-${DevEnvironmentRegion}-cadastro-corporativo-sybase-acl"
        hml:
          - name: /Cliente/CadastroCorporativo/ACL/Sqs/QueueUrl
            description: URL da fila SQS consumida pelo ACL de Cadastro Corporativo (hml)
            type: String
            value: "https://sqs.${HmlEnvironmentRegion}.amazonaws.com/$(AWS_ACCOUNT_ID)/sqs-${HmlEnvironment}-${HmlEnvironmentRegion}-cadastro-corporativo-sybase-acl"
        prd:
          - name: /Cliente/CadastroCorporativo/ACL/Sqs/QueueUrl
            description: URL da fila SQS consumida pelo ACL de Cadastro Corporativo (prd)
            type: String
            value: "https://sqs.${PrdEnvironmentRegion}.amazonaws.com/$(AWS_ACCOUNT_ID)/sqs-${PrdEnvironment}-${PrdEnvironmentRegion}-cadastro-corporativo-sybase-acl"

 

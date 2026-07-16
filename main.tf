parameters:
  - name: pod
    type: object
  - name: networking
    type: object
  - name: resources
    type: object
    default:
      dynamodb_tables: []
      s3_buckets: []
      sqs: []
      secrets: []
      sns_topics: []
      sns_sqs_subscriptions: []
  - name: observability
    type: object
    default:
      dd_lang: dotnet
      dd_lib_version: latest
  - name: config
    type: object
    default:
      env_vars: []
      ssm_parameters:
        dev: []
        hml: []
        prd: []
  - name: hotfix
    type: object
    default:
      main_pr_require_manual_approval: false
      main_pr_reviewers: ''
      main_pr_wait_timeout_minutes: 360
  - name: rollbackImageTag
    type: string
    default: 'none'

variables:
  - group: git-credentials

stages:
  - ${{ if and(ne(parameters.rollbackImageTag, ''), ne(parameters.rollbackImageTag, 'none')) }}:
      - template: ../stages/rollback.yaml
        parameters:
          environment: prd
          imageTag: ${{ parameters.rollbackImageTag }}

  - ${{ else }}:
      - stage: Validate
        displayName: 'Validar parametros'
        jobs:
          - job: ValidateNetworking
            displayName: 'Validar networking'
            pool:
              vmImage: ubuntu-latest
            steps:
              - ${{ if eq(parameters.networking.ingress_path, '/') }}:
                  - script: |
                      echo "##[error]ingress_path nao pode ser '/'. Use um path especifico, ex: /minha-api"
                      exit 1
                    displayName: 'ingress_path invalido'
              - ${{ else }}:
                  - script: |
                      echo "ingress_path valido: '${{ parameters.networking.ingress_path }}'"
                    displayName: 'ingress_path ok'

      - stage: SonarQube
        displayName: 'Analisar qualidade com SonarQube'
        dependsOn: Validate
        condition: succeeded()
        jobs:
          - job: SonarQubeScan
            displayName: 'Analisar código .NET'
            pool:
              vmImage: ubuntu-latest
            steps:
              - checkout: self
                fetchDepth: 0
                displayName: 'Obter código-fonte completo'
              - template: ../sonarqube/qa-sonar-dotnet.yaml

      - stage: Build
        displayName: 'Compilar e publicar imagem Docker'
        dependsOn: SonarQube
        condition: succeeded()
        jobs:
          - template: ../dotnet/build-backend-dotnet.yaml

      - ${{ if startsWith(variables['Build.SourceBranch'], 'refs/heads/hotfix/') }}:
          - template: ../hotfix/hotfix-backend-dotnet.yaml
            parameters:
              pod: ${{ parameters.pod }}
              networking: ${{ parameters.networking }}
              resources: ${{ parameters.resources }}
              observability: ${{ parameters.observability }}
              config: ${{ parameters.config }}
              hotfix: ${{ parameters.hotfix }}

      - ${{ elseif startsWith(variables['Build.SourceBranch'], 'refs/heads/release/') }}:
          - template: ../stages/deploy.yaml
            parameters:
              environment: hml
              dependsOn: [Build]
              pod: ${{ parameters.pod }}
              networking: ${{ parameters.networking }}
              resources: ${{ parameters.resources }}
              observability: ${{ parameters.observability }}
              env_vars: ${{ parameters.config.env_vars }}
              ssm_parameters: ${{ parameters.config.ssm_parameters.hml }}

          - template: ../stages/veracode.yaml
            parameters:
              dependsOn: [Build]

          - template: ../stages/deploy.yaml
            parameters:
              environment: prd
              dependsOn: [Deploy_hml, Veracode]
              pod: ${{ parameters.pod }}
              networking: ${{ parameters.networking }}
              resources: ${{ parameters.resources }}
              observability: ${{ parameters.observability }}
              env_vars: ${{ parameters.config.env_vars }}
              ssm_parameters: ${{ parameters.config.ssm_parameters.prd }}

          - stage: PR_Main
            displayName: 'Abrir PR (release → main)'
            dependsOn: Deploy_prd
            condition: succeeded()
            jobs:
              - template: ../utils/create-pullrequest.yaml
                parameters:
                  sourceBranch: ${{ replace(variables['Build.SourceBranch'], 'refs/heads/', '') }}
                  targetBranch: main

          - stage: BackMerge_Develop
            displayName: 'Abrir PR (main → develop)'
            dependsOn: PR_Main
            condition: succeeded()
            jobs:
              - template: ../utils/create-pullrequest.yaml
                parameters:
                  sourceBranch: main
                  targetBranch: develop

      - ${{ else }}:
          - template: ../stages/deploy.yaml
            parameters:
              environment: dev
              dependsOn: [Build]
              condition: and(succeeded('Build'), or(eq(variables['Build.SourceBranch'], 'refs/heads/develop'), eq(variables['Build.SourceBranch'], 'refs/heads/sandbox')))
              pod: ${{ parameters.pod }}
              networking: ${{ parameters.networking }}
              resources: ${{ parameters.resources }}
              observability: ${{ parameters.observability }}
              env_vars: ${{ parameters.config.env_vars }}
              ssm_parameters: ${{ parameters.config.ssm_parameters.dev }}

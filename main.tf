steps:
  - task: SonarSource.sonarqube.15B84CA1-B62F-4A2A-A403-89B77A063157.SonarQubePrepare@7
    displayName: 'Configuration SonarQube (.NET)'
    inputs:
      SonarQube: SonarQube
      scannerMode: 'dotnet'
      projectKey: '$(Build.Repository.Name)-key'
      projectName: '$(Build.Repository.Name)'
      extraProperties: |
        sonar.scm.disabled=true
        sonar.branch.name=develop
        # Apontamos para uma pasta temporaria fora da raiz do projeto
        sonar.cs.vscoveragexml.reportsPaths=$(Agent.TempDirectory)/coverage.xml
        # Cobertura: excluir codigo gerado, DTOs e caminhos sem valor de metrica
        sonar.coverage.exclusions=**/obj/**,**/*.generated.cs,**/Program.cs,**/DTOs/**,**/Domain/**,**/Configuration/**,**/HealthController.cs,**/Services/**
        # Analise: excluir testes, gerados e terceiros
        sonar.exclusions=**/obj/**,**/*.generated.cs,test/**,**/HealthController.cs
        # CPD: excluir duplicacoes em DTOs, domain e contratos REST
        sonar.cpd.exclusions=**/DTOs/**,**/Domain/**,**/Services/Rest/**/Contracts/**
    continueOnError: false

  - task: UseDotNet@2
    displayName: 'Use .NET Core sdk 10.x'
    inputs:
      version: 10.x
      includePreviewVersions: true

  - script: dotnet tool install --global dotnet-coverage
    displayName: 'Install dotnet-coverage'

  - task: DotNetCoreCLI@2
    displayName: 'Restore'
    inputs:
      command: restore
      projects: '**/*.slnx'
      vstsFeed: 'fe426c42-a2f6-4500-bfe3-a01db2340d0b'
    # TEMPORARIO: contorna NU3012 (ex.: assinatura/revogacao de certificado em pacotes NuGet, ex. Refit).
    # Remover quando os pacotes estiverem republicados com assinatura valida.
    env:
      NUGET_CERT_REVOCATION_MODE: no
      DOTNET_NUGET_SIGNATURE_VERIFICATION: false

  - script: |
      # Localiza a solucao de forma segura no Linux
      SOLUTION=$(find . -maxdepth 2 -name "*.slnx" | head -n 1)

      echo "Building: $SOLUTION"
      dotnet build "$SOLUTION" --configuration Release --no-incremental

      echo "Generating coverage at $(Agent.TempDirectory)/coverage.xml"
      # Geramos o arquivo na pasta TEMP do Agente, longe dos fontes
      dotnet-coverage collect "dotnet test --configuration Release --no-build" -f xml -o "$(Agent.TempDirectory)/coverage.xml"
    displayName: 'Build and Collect Coverage'
    env:
      PATH: $(PATH):$(HOME)/.dotnet/tools
      NUGET_CERT_REVOCATION_MODE: no
      DOTNET_NUGET_SIGNATURE_VERIFICATION: false

  - task: SonarSource.sonarqube.6D01813A-9589-4B15-8491-8164AEB38055.SonarQubeAnalyze@7
    displayName: 'Code Analysis'
    inputs:
      jdkversion: 'JAVA_HOME'
    continueOnError: false

  - task: SonarSource.sonarqube.291ed61f-1ee4-45d3-b1b0-bf822d9095ef.SonarQubePublish@7
    displayName: 'Publish Quality Gate Result'
    inputs:
      pollingTimeoutSec: '300'
    continueOnError: false

  # ---------------------------------------------------------------------------
  # Bloqueia o build quando o Quality Gate falha e imprime as metricas
  # (coverage, issues, duplicacao) com valor atual x limite exigido.
  #
  # O SonarQubePublish apenas publica o status; ele NAO quebra o build sozinho.
  # Este step le o report-task.txt, consulta a API do SonarQube e falha com
  # exit 1 se o Quality Gate nao estiver OK. Compativel com a Community Edition.
  #
  # O token e extraido de SONARQUBE_SCANNER_PARAMS, que o SonarQubePrepare ja
  # exporta a partir do service connection -- nao precisa criar secret.
  # ---------------------------------------------------------------------------
  - task: Bash@3
    displayName: 'Break build on quality gate failure'
    inputs:
      targetType: 'inline'
      script: |
        set -euo pipefail

        # --- Localiza o report-task.txt -------------------------------------
        REPORT_TASK="${SONAR_SCANNER_REPORTTASKFILE:-}"
        if [ -z "$REPORT_TASK" ] || [ ! -f "$REPORT_TASK" ]; then
          REPORT_TASK=$(find "$(Agent.WorkFolder)" -name "report-task.txt" 2>/dev/null | head -n 1)
        fi
        if [ -z "$REPORT_TASK" ] || [ ! -f "$REPORT_TASK" ]; then
          echo "##[error]report-task.txt nao encontrado. A analise do Sonar rodou?"
          exit 1
        fi

        CE_TASK_ID=$(grep '^ceTaskId=' "$REPORT_TASK" | cut -d'=' -f2-)
        SONAR_URL=$(grep '^serverUrl=' "$REPORT_TASK" | cut -d'=' -f2-)
        DASHBOARD_URL=$(grep '^dashboardUrl=' "$REPORT_TASK" | cut -d'=' -f2- || true)

        echo "##[group]Detalhes da analise"
        echo "report-task.txt : $REPORT_TASK"
        echo "Servidor        : $SONAR_URL"
        echo "Task de analise : $CE_TASK_ID"
        echo "##[endgroup]"

        # --- Token exportado pelo SonarQubePrepare ---------------------------
        TOKEN=$(echo "${SONARQUBE_SCANNER_PARAMS:-}" | grep -o '"sonar.token":"[^"]*"' | cut -d'"' -f4)
        if [ -z "$TOKEN" ]; then
          echo "##[error]Nao consegui extrair o token do Sonar (SONARQUBE_SCANNER_PARAMS)."
          exit 1
        fi
        AUTH="${TOKEN}:"

        # --- Garante o jq (parsing do JSON) ---------------------------------
        if ! command -v jq >/dev/null 2>&1; then
          echo "jq nao encontrado, instalando..."
          sudo apt-get update -qq && sudo apt-get install -y -qq jq
        fi

        # --- Aguarda o processamento da analise ------------------------------
        ANALYSIS_ID=""
        for i in $(seq 1 30); do
          RESP=$(curl -s -u "$AUTH" "$SONAR_URL/api/ce/task?id=$CE_TASK_ID")
          CE_STATUS=$(echo "$RESP" | jq -r '.task.status // empty')
          echo "Tentativa $i - status do processamento: $CE_STATUS"
          if [ "$CE_STATUS" = "SUCCESS" ]; then
            ANALYSIS_ID=$(echo "$RESP" | jq -r '.task.analysisId // empty')
            break
          elif [ "$CE_STATUS" = "FAILED" ] || [ "$CE_STATUS" = "CANCELED" ]; then
            echo "##[error]Processamento da analise falhou no servidor: $CE_STATUS"
            exit 1
          fi
          sleep 5
        done

        if [ -z "$ANALYSIS_ID" ]; then
          echo "##[error]Timeout aguardando o processamento da analise no Sonar."
          exit 1
        fi

        # --- Consulta o Quality Gate -----------------------------------------
        GATE_JSON=$(curl -s -u "$AUTH" "$SONAR_URL/api/qualitygates/project_status?analysisId=$ANALYSIS_ID")
        GATE_STATUS=$(echo "$GATE_JSON" | jq -r '.projectStatus.status // empty')

        # --- Resumo destacado -------------------------------------------------
        echo ""
        echo "##[section]===================== QUALITY GATE ====================="
        echo ""
        printf "  %-28s %12s %12s %10s\n" "METRICA" "ATUAL" "LIMITE" "STATUS"
        printf "  %-28s %12s %12s %10s\n" "----------------------------" "------------" "------------" "----------"

        echo "$GATE_JSON" | jq -r '
          .projectStatus.conditions[]
          | [ .metricKey,
              (.actualValue    // "-"),
              (.errorThreshold // "-"),
              .status ]
          | @tsv' \
        | while IFS=$'\t' read -r METRIC ACTUAL THRESH CSTATUS; do
            printf "  %-28s %12s %12s %10s\n" "$METRIC" "$ACTUAL" "$THRESH" "$CSTATUS"
          done

        echo ""

        # Destaca a cobertura separadamente (metrica mais consultada)
        COV=$(echo "$GATE_JSON" | jq -r '
          .projectStatus.conditions[]
          | select(.metricKey | test("coverage"))
          | "  COBERTURA: \(.actualValue)% (minimo exigido: \(.errorThreshold)%) -> \(.status)"' || true)
        if [ -n "$COV" ]; then
          echo "$COV"
          echo ""
        fi

        echo "  RESULTADO GERAL: $GATE_STATUS"
        if [ -n "${DASHBOARD_URL:-}" ]; then
          echo "  Dashboard: $DASHBOARD_URL"
        fi
        echo ""
        echo "##[section]========================================================"
        echo ""

        # --- Decisao ----------------------------------------------------------
        if [ "$GATE_STATUS" != "OK" ]; then
          echo "##vso[task.logissue type=error]Quality Gate falhou (status: $GATE_STATUS)."
          echo "##[error]Bloqueando o build."
          exit 1
        fi
        echo "Quality Gate aprovado."

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
  # DEBUG TEMPORARIO: localiza onde o report-task.txt e gerado neste agente.
  # NAO bloqueia nada -- apenas imprime caminhos e variaveis.
  # Depois de descobrir o path correto, este step pode ser REMOVIDO.
  # ---------------------------------------------------------------------------
  - task: Bash@3
    displayName: 'DEBUG - localizar report-task.txt'
    inputs:
      targetType: 'inline'
      script: |
        echo "=== Variaveis de ambiente relacionadas ao Sonar ==="
        env | grep -i sonar || echo "(nenhuma variavel SONAR encontrada)"
 
        echo ""
        echo "=== Procurando report-task.txt em Agent.WorkFolder ==="
        find "$(Agent.WorkFolder)" -name "report-task.txt" 2>/dev/null || echo "(nao achou em Agent.WorkFolder)"
 
        echo ""
        echo "=== Procurando pastas .sonarqube ==="
        find "$(Agent.WorkFolder)" -type d -name ".sonarqube" 2>/dev/null || echo "(nenhuma pasta .sonarqube)"
 
        echo ""
        echo "=== Caminhos de referencia ==="
        echo "Agent.WorkFolder       : $(Agent.WorkFolder)"
        echo "Agent.BuildDirectory   : $(Agent.BuildDirectory)"
        echo "Build.SourcesDirectory : $(Build.SourcesDirectory)"
 
  # ---------------------------------------------------------------------------
  # Bloqueia o build quando o Quality Gate falha.
  # O SonarQubePublish apenas publica o status; ele NAO quebra o build sozinho.
  # Este step le o report-task.txt, consulta a API do Sonar e falha com exit 1
  # se o Quality Gate nao estiver OK. Funciona na Community Edition.
  #
  # Pre-requisito: variavel secreta SONAR_TOKEN configurada no pipeline
  # (token gerado em SonarQube > Minha Conta > Seguranca).
  #
  # OBS: ajuste o caminho de busca conforme o resultado do step de DEBUG acima,
  # caso o fallback atual nao encontre o arquivo.
  # ---------------------------------------------------------------------------
  - task: Bash@3
    displayName: 'Break build on quality gate failure'
    inputs:
      targetType: 'inline'
      script: |
        set -euo pipefail
 
        # 1) Tenta a variavel exportada pelo SonarQubePrepare.
        # 2) Fallback: busca ampla por report-task.txt em todo o workspace.
        REPORT_TASK="${SONARQUBE_SCANNER_REPORTTASKFILE:-}"
        if [ -z "$REPORT_TASK" ] || [ ! -f "$REPORT_TASK" ]; then
          REPORT_TASK=$(find "$(Agent.WorkFolder)" -name "report-task.txt" 2>/dev/null | head -n 1)
        fi
        if [ -z "$REPORT_TASK" ] || [ ! -f "$REPORT_TASK" ]; then
          echo "##[error]report-task.txt nao encontrado. A analise do Sonar rodou?"
          exit 1
        fi
        echo "Usando: $REPORT_TASK"
 
        CE_TASK_ID=$(grep '^ceTaskId=' "$REPORT_TASK" | cut -d'=' -f2-)
        SONAR_URL=$(grep '^serverUrl=' "$REPORT_TASK" | cut -d'=' -f2-)
        echo "Servidor: $SONAR_URL"
        echo "Task de analise: $CE_TASK_ID"
 
        AUTH="$(SONAR_TOKEN):"
 
        # Aguarda o Sonar terminar de processar a analise (ate ~2,5 min).
        ANALYSIS_ID=""
        for i in $(seq 1 30); do
          RESP=$(curl -s -u "$AUTH" "$SONAR_URL/api/ce/task?id=$CE_TASK_ID")
          CE_STATUS=$(echo "$RESP" | grep -o '"status":"[^"]*"' | head -n1 | cut -d'"' -f4)
          echo "Tentativa $i - status do processamento: $CE_STATUS"
          if [ "$CE_STATUS" = "SUCCESS" ]; then
            ANALYSIS_ID=$(echo "$RESP" | grep -o '"analysisId":"[^"]*"' | cut -d'"' -f4)
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
 
        GATE_STATUS=$(curl -s -u "$AUTH" "$SONAR_URL/api/qualitygates/project_status?analysisId=$ANALYSIS_ID" | grep -o '"status":"[^"]*"' | head -n1 | cut -d'"' -f4)
        echo "Quality Gate: $GATE_STATUS"
 
        if [ "$GATE_STATUS" != "OK" ]; then
          echo "##[error]Quality Gate falhou (status: $GATE_STATUS). Bloqueando o build."
          exit 1
        fi
        echo "Quality Gate aprovado."
    env:
      SONAR_TOKEN: $(SONAR_TOKEN)

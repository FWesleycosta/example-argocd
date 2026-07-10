- task: Bash@3
    displayName: 'Break build on quality gate failure'
    inputs:
      targetType: 'inline'
      script: |
        set -euo pipefail

        # O SonarQubePrepare exporta o caminho do report-task.txt nesta variável.
        # Fazemos fallback para busca no diretório .sonarqube caso não exista.
        REPORT_TASK="${SONARQUBE_SCANNER_REPORTTASKFILE:-}"
        if [ -z "$REPORT_TASK" ] || [ ! -f "$REPORT_TASK" ]; then
          REPORT_TASK=$(find "$(Agent.BuildDirectory)" -path "*/.sonarqube/out/*report-task.txt" 2>/dev/null | head -n 1)
        fi
        if [ -z "$REPORT_TASK" ] || [ ! -f "$REPORT_TASK" ]; then
          echo "##[error]report-task.txt não encontrado. A análise do Sonar rodou?"
          exit 1
        fi
        echo "Usando: $REPORT_TASK"

        CE_TASK_ID=$(grep '^ceTaskId=' "$REPORT_TASK" | cut -d'=' -f2-)
        SONAR_URL=$(grep '^serverUrl=' "$REPORT_TASK" | cut -d'=' -f2-)
        echo "Servidor: $SONAR_URL"
        echo "Task de análise: $CE_TASK_ID"

        AUTH="$(SONAR_TOKEN):"

        # Aguarda o Sonar terminar de processar a análise
        ANALYSIS_ID=""
        for i in $(seq 1 30); do
          RESP=$(curl -s -u "$AUTH" "$SONAR_URL/api/ce/task?id=$CE_TASK_ID")
          CE_STATUS=$(echo "$RESP" | grep -o '"status":"[^"]*"' | head -n1 | cut -d'"' -f4)
          echo "Tentativa $i - status do processamento: $CE_STATUS"
          if [ "$CE_STATUS" = "SUCCESS" ]; then
            ANALYSIS_ID=$(echo "$RESP" | grep -o '"analysisId":"[^"]*"' | cut -d'"' -f4)
            break
          elif [ "$CE_STATUS" = "FAILED" ] || [ "$CE_STATUS" = "CANCELED" ]; then
            echo "##[error]Processamento da análise falhou no servidor: $CE_STATUS"
            exit 1
          fi
          sleep 5
        done

        if [ -z "$ANALYSIS_ID" ]; then
          echo "##[error]Timeout aguardando o processamento da análise no Sonar."
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

inlineScript: |
        set -euo pipefail

        cd $(System.DefaultWorkingDirectory)/terraform

        terraform init -migrate-state
        terraform validate

        export TF_VAR_ssm_parameters='${{ convertToJson(parameters.ssm_parameters) }}'
        export TF_VAR_s3_buckets='${{ convertToJson(parameters.s3_buckets) }}'
        export TF_VAR_secrets='${{ convertToJson(parameters.secrets) }}'

        terraform apply -auto-approve \
          -var="app_name=$(Build.Repository.Name)" \
          -var="environment=${{ parameters.environment }}" \
          -var="namespace=$(Build.Repository.Name)-${{ parameters.environment }}" \
          -var="domain_name=${{ parameters.domain_name }}" \
          -var="cluster_name=${{ parameters.clusterName }}" \
          -var="alb_shared_dns=${{ parameters.albSharedDns }}" \
          -var="api_gateway_vpc_link=${{ parameters.apiGatewayVpcLink }}" \
          -var="alb_shared_listener=${{ parameters.albSharedListener }}" \
          -var="base_path=${{ parameters.base_path }}" \
          -var="api_type=${{ parameters.api_visibility }}" \
          -var="vpc_endpoint_apigw=${{ parameters.vpc_endpoint_apigw }}" \
          -var="domain_internal_name=${{ parameters.domain_internal_name }}" \
          -var="domain_name_id=${{ parameters.domain_name_id }}" \
          -var='dynamodb_tables=${{ convertToJson(parameters.dynamodb_tables) }}' \
          2>&1 | tee /tmp/tf_output.log

        EXIT_CODE=${PIPESTATUS[0]}

        if [ $EXIT_CODE -eq 0 ]; then
          echo "Terraform apply concluído com sucesso."
          exit 0
        fi

        # ===== DEBUG temporário: ver exatamente o que está no log =====
        echo "===== DEBUG: linhas com Error no log ====="
        grep -nE "Error:" /tmp/tf_output.log || echo "nenhum match de 'Error:'"
        echo "===== DEBUG: linhas com Base Path no log ====="
        grep -nE "BasePathConflictException|Base path already exists|CreateBasePathMapping" /tmp/tf_output.log || echo "nenhum match de Base Path"
        echo "===== FIM DEBUG ====="

        # Conta quantos blocos de erro existem
        TOTAL_ERRORS=$(grep -cE "^│ Error:" /tmp/tf_output.log || true)

        # Fallback para formato antigo sem a barra vertical
        if [ "$TOTAL_ERRORS" -eq 0 ]; then
          TOTAL_ERRORS=$(grep -cE "^Error:" /tmp/tf_output.log || true)
        fi

        # Conta quantos erros são de Base Path (ignoráveis)
        BASE_PATH_ERRORS=$(grep -cE "BasePathConflictException|Base path already exists|CreateBasePathMapping" /tmp/tf_output.log || true)

        echo "=========================================="
        echo "Total de erros: $TOTAL_ERRORS"
        echo "Erros de Base Path: $BASE_PATH_ERRORS"
        echo "=========================================="

        # Só ignora se TODOS os erros forem de Base Path
        if [ "$TOTAL_ERRORS" -gt 0 ] && [ "$TOTAL_ERRORS" -eq "$BASE_PATH_ERRORS" ]; then
          echo "##[warning]Apenas erros de Base path já existente. Ignorando..."
          exit 0
        fi

        echo "##[error]Erro inesperado no terraform apply!"
        exit 1

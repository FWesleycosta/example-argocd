        # Conta quantos erros totais existem no log do terraform
        TOTAL_ERRORS=$(grep -cE "^(╷|Error:|\| Error:)" /tmp/tf_output.log || true)

        # Conta quantos são do tipo "Base Path" (ignoráveis)
        BASE_PATH_ERRORS=$(grep -cE "BasePathConflictException|Base path already exists|creating API Gateway Base Path Mapping.*ConflictException" /tmp/tf_output.log || true)

        echo "Total de erros: $TOTAL_ERRORS | Erros de Base Path: $BASE_PATH_ERRORS"

        # Só ignora se TODOS os erros forem de Base Path
        if [ "$TOTAL_ERRORS" -gt 0 ] && [ "$TOTAL_ERRORS" -eq "$BASE_PATH_ERRORS" ]; then
          echo "##[warning]Apenas erros de Base path já existente. Ignorando..."
          exit 0
        fi

        echo "##[error]Erro inesperado no terraform apply!"
        cat /tmp/tf_output.log
        exit 1

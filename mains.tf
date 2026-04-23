EXIT_CODE=${PIPESTATUS[0]}

if [ $EXIT_CODE -eq 0 ]; then
  echo "Terraform apply concluído com sucesso."
  exit 0
fi

# Conta quantos blocos de erro existem (cada erro começa com "│ Error:")
TOTAL_ERRORS=$(grep -cE "^│ Error:" /tmp/tf_output.log || true)

# Fallback: se não achou nada com o formato novo, tenta o formato antigo
if [ "$TOTAL_ERRORS" -eq 0 ]; then
  TOTAL_ERRORS=$(grep -cE "^Error:" /tmp/tf_output.log || true)
fi

# Conta quantos desses erros são de Base Path
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

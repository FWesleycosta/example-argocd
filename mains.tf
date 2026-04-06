parameters:
  - name: environment
    type: string
  - name: lambda_description
    type: string
  - name: aws_region
    type: string
  - name: app_name
    type: string
    default: $(Build.Repository.Name)
  - name: subnets_privates
    type: string
    default: ''
  - name: vpc_id
    type: string
    default: ''

steps:
  - script: |
      set -e
      sudo wget -qO /usr/local/bin/yq \
        https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
      sudo chmod +x /usr/local/bin/yq

      CONFIG=$(find "$(Build.SourcesDirectory)" -maxdepth 2 -type f -name "*.yaml" -path "*/config/*" | head -1)
      if [ -z "$CONFIG" ]; then
        echo "##[error] Nenhum .yaml encontrado em config/"
        find "$(Build.SourcesDirectory)" -maxdepth 3 -type f | sort
        exit 1
      fi

      PRODUCT_DIR=$(dirname $(dirname "$CONFIG"))
      TFVARS="$PRODUCT_DIR/terraform/terraform.auto.tfvars"
      REPO="$(Build.Repository.Name)"

      echo "##[section] CONFIG      = $CONFIG"
      echo "##[section] PRODUCT_DIR = $PRODUCT_DIR"
      echo "##[section] TFVARS      = $TFVARS"

      MEMORY=$(yq e '.defaults.memory_size'    "$CONFIG")
      TIMEOUT=$(yq e '.defaults.timeout'        "$CONFIG")
      TRACING=$(yq e '.defaults.tracing_config' "$CONFIG")
      RUNTIME=$(yq e '.defaults.runtime'        "$CONFIG")

      echo "##[debug] memory=$MEMORY timeout=$TIMEOUT tracing=$TRACING runtime=$RUNTIME"

      rm -f "$TFVARS"

      PYSCRIPT=$(mktemp /tmp/gen_tfvars_XXXXXX.py)
      cat > "$PYSCRIPT" << 'PYEOF'
import sys
import subprocess

config_path, tfvars_path, repo, memory, timeout, tracing, runtime, env, desc, aws_region, app_name, subnets_privates, vpc_id = sys.argv[1:]

def yq(expr):
    return subprocess.check_output(['yq', 'e', expr, config_path]).decode().strip()

def yq_safe(expr, default=''):
    try:
        result = subprocess.check_output(
            ['yq', 'e', expr, config_path],
            stderr=subprocess.DEVNULL
        ).decode().strip()
        if result in ('null', ''):
            return default
        return result
    except Exception:
        return default

# — function_name_prefix: usa campo do config ou fallback pro repo —
fn_prefix = yq('.function_name_prefix // ""')
if not fn_prefix or fn_prefix == 'null':
    fn_prefix = repo

# — Handlers —
handler_count = int(yq('.handlers | length'))
handlers = {}
for i in range(handler_count):
    key   = yq(f'.handlers | keys | .[{i}]')
    value = yq(f'.handlers["{key}"]')
    handlers[key] = value

# — Validar tamanho: prefix + "-" + handler_key <= 64 chars —
MAX_LEN = 64
for key in handlers:
    full_name = f"{fn_prefix}-{key}"
    if len(full_name) > MAX_LEN:
        print(f"##[error] Nome da funcao excede {MAX_LEN} chars: '{full_name}' ({len(full_name)} chars)")
        print(f"##[error] Adicione 'function_name_prefix' no config YAML com um prefixo mais curto.")
        print(f"##[error] Maximo para o prefixo com handler '{key}': {MAX_LEN - len(key) - 1} chars")
        sys.exit(1)
    else:
        print(f"##[section] Lambda: {full_name} ({len(full_name)}/{MAX_LEN} chars) ✓")

# — Subnets —
subnets_list = [f'"{s.strip()}"' for s in subnets_privates.split(',') if s.strip()]
subnets_tf = '[' + ', '.join(subnets_list) + ']'

# — SSM Parameters por ambiente —
ssm_count = int(yq_safe(f'.ssm_parameters.{env} | length', '0'))

ssm_params = []
for i in range(ssm_count):
    ssm_name  = yq_safe(f'.ssm_parameters.{env}[{i}].name')
    ssm_value = yq_safe(f'.ssm_parameters.{env}[{i}].value')
    if ssm_name and ssm_value:
        ssm_params.append({"name": ssm_name, "value": ssm_value})

if ssm_params:
    print(f"##[section] SSM Parameters para [{env}]: {len(ssm_params)} encontrado(s)")
    for p in ssm_params:
        print(f"##[section]   -> {p['name']}")
else:
    print(f"##[section] SSM Parameters para [{env}]: nenhum definido")

# — Gerar tfvars —
lines = [
    f'environment          = "{env}"',
    f'function_name_prefix = "{fn_prefix}"',
    f'description          = "{desc}"',
    f'lambda_memory_size   = {memory}',
    f'lambda_timeout       = {timeout}',
    f'lambda_tracing_config = "{tracing}"',
    f'lambda_runtime       = "{runtime}"',
    f'zip_filename         = "{repo}"',
    f'AWS_REGION           = "{aws_region}"',
    f'app_name             = "{app_name}"',
    f'subnets_privates     = {subnets_tf}',
    f'vpc_id               = "{vpc_id}"',
    '',
    'handlers = {',
]
for k, v in handlers.items():
    lines.append(f'  "{k}" = "{v}"')
lines.append('}')

lines.append('')
lines.append('ssm_parameters = {')
for idx, p in enumerate(ssm_params):
    lines.append(f'  param_{idx} = {{')
    lines.append(f'    name  = "{p["name"]}"')
    lines.append(f'    value = "{p["value"]}"')
    lines.append(f'  }}')
lines.append('}')

with open(tfvars_path, 'w') as f:
    f.write('\n'.join(lines) + '\n')

print('##[section] terraform.auto.tfvars gerado:')
print('\n'.join(lines))
PYEOF

      python3 "$PYSCRIPT" "$CONFIG" "$TFVARS" "$REPO" "$MEMORY" "$TIMEOUT" "$TRACING" "$RUNTIME" \
        "${{ parameters.environment }}" "${{ parameters.lambda_description }}" "${{ parameters.aws_region }}" "${{ parameters.app_name }}" \
        "${{ parameters.subnets_privates }}" "${{ parameters.vpc_id }}"

      rm -f "$PYSCRIPT"
    displayName: "Gerar terraform.auto.tfvars [${{ parameters.environment }}]"

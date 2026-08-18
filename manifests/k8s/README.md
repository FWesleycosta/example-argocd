# manifests/k8s

Templates de **manifests Kubernetes** da aplicação. **Não** são templates do Azure
Pipelines — são arquivos copiados em runtime pelo `templates/deploy-backend.yaml`
(step "Prepare Terraform and Kubernetes Manifests") para `$(Build.SourcesDirectory)/k8s`
e então têm os tokens `PLACEHOLDER_*` substituídos por `sed` antes do `kubectl apply`.

## Arquivos esperados (obrigatórios)

O step "Configure All Manifests" exige que existam:

- `deployment.yaml`
- `service.yaml`
- `hpa.yaml`
- `configmap.yaml`
- `ingress.yaml`

> Obs.: `configmap-app-vars.yaml` é **gerado** pela esteira a partir de `config.env_vars`
> (não fica aqui).

## Tokens substituídos (contrato com o deploy-backend.yaml)

A esteira falha se sobrar qualquer `PLACEHOLDER_` após a substituição. Tokens disponíveis:

| Token | Origem |
|---|---|
| `PLACEHOLDER_APP_NAME` | `Build.Repository.Name` |
| `PLACEHOLDER_ECR_IMAGE` | `<awsAccID>.dkr.ecr.<region>.amazonaws.com/<app>:<BuildId>` |
| `PLACEHOLDER_ENVIRONMENT` | `environment` (dev/hml/prd/sdx) — em `sdx`, o `group.name` do ingress vira `sdx-eks-shared-alb`: ALB próprio do sandbox, criado no primeiro deploy |
| `PLACEHOLDER_AWS_REGION` | `awsRegion` |
| `PLACEHOLDER_DEPLOYMENT_ASPNETCORE_URLS` | `networking.deployment_aspnetcore_urls` |
| `PLACEHOLDER_DEPLOYMENT_ASPNETCORE_ENVIRONMENT` | `deployment_aspnetcore_environment` |
| `PLACEHOLDER_INGRESS_PATH` | `networking.ingress_path` |
| `PLACEHOLDER_MIN_REPLICAS` / `PLACEHOLDER_MAX_REPLICAS` | `pod.min_replicas` / `pod.max_replicas` |
| `PLACEHOLDER_REQUESTS_CPU` / `PLACEHOLDER_REQUESTS_MEMORY` | `pod.requests_cpu` / `pod.requests_memory` |
| `PLACEHOLDER_LIMITS_CPU` / `PLACEHOLDER_LIMITS_MEMORY` | `pod.limits_cpu` / `pod.limits_memory` |
| `PLACEHOLDER_CPU_UTILIZATION` | `pod.cpu_utilization` |
| `PLACEHOLDER_DD_LANG` / `PLACEHOLDER_DD_LIB_VERSION` | `observability.dd_lang` / `observability.dd_lib_version` |

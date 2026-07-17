parameters:
  - name: serviceAccount
    type: string
  - name: awsRegion
    type: string
  - name: awsAccID
    type: string
  - name: imageName
    type: string
    default: '$(Build.Repository.Name)'
  - name: imageTag
    type: string
    default: '$(Build.BuildId)'
  - name: prodTag
    type: string
    default: 'prod'
  - name: deployType
    type: string
    default: 'auto'
    values: [auto, deploy, hotfix, rollback]
  - name: artifactName
    type: string
    default: 'prod-release'
  - name: stampRun
    type: boolean
    default: true
  - name: updateReleaseLog
    type: boolean
    default: true
  - name: recordBranch
    type: string
    default: ''

steps:
  - ${{ if parameters.stampRun }}:
      - bash: |
          set -euo pipefail

          # Tags filtráveis na lista de runs (idempotentes: re-adicionar é no-op).
          echo "##vso[build.addbuildtag]prod"
          echo "##vso[build.addbuildtag]${{ parameters.imageName }}"

          BN="$(Build.BuildNumber)"
          case "$BN" in
            *"· prd") echo "Build Number já carimbado ('$BN')." ;;
            *) echo "##vso[build.updatebuildnumber]${BN} · prd" ;;
          esac
        displayName: 'Carimbar execução (deploy em prod)'

  - task: AmazonWebServices.aws-vsts-tools.AWSShellScript.AWSShellScript@1
    displayName: 'Registrar release em prod (digest + tag móvel)'
    env:
      SYSTEM_ACCESSTOKEN: $(System.AccessToken)
      UPDATE_RELEASE_LOG: ${{ parameters.updateReleaseLog }}
      RECORD_BRANCH: ${{ parameters.recordBranch }}
    inputs:
      awsCredentials: ${{ parameters.serviceAccount }}
      regionName: ${{ parameters.awsRegion }}
      scriptType: inline
      inlineScript: |
        set -euo pipefail

        ACCOUNT_ID="${{ parameters.awsAccID }}"
        REGION="${{ parameters.awsRegion }}"
        REPO="${{ parameters.imageName }}"
        TAG="${{ parameters.imageTag }}"
        PROD_TAG="${{ parameters.prodTag }}"
        REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
        IMAGE_URI="${REGISTRY}/${REPO}:${TAG}"

        # 0) Classifica a execução: deploy normal, hotfix ou rollback.
        DEPLOY_TYPE="${{ parameters.deployType }}"
        if [ "$DEPLOY_TYPE" = "auto" ]; then
          case "$(Build.SourceBranch)" in
            refs/heads/hotfix/*) DEPLOY_TYPE="hotfix" ;;
            *)                   DEPLOY_TYPE="deploy" ;;
          esac
        fi
        case "$DEPLOY_TYPE" in
          rollback) TYPE_LABEL="rollback" ;;
          hotfix)   TYPE_LABEL="hotfix" ;;
          *)        TYPE_LABEL="deploy" ;;
        esac

        COMMIT="$(Build.SourceVersion)"
        COMMIT_MSG="${BUILD_SOURCEVERSIONMESSAGE:-}"
        if [ "$DEPLOY_TYPE" = "rollback" ]; then
          COMMIT=""
          COMMIT_MSG="Rollback para a imagem ${TAG}"
        fi
        # Versão segura p/ células de tabela markdown (sem '|' nem quebras de linha).
        MSG_SAFE="$(printf '%s' "$COMMIT_MSG" | tr '\n\r|' '  /' | cut -c1-80)"

        # 1) Digest imutável da imagem que acabou de ser promovida para prod.
        #    A tag é mutável; o digest (sha256) é a identidade real da imagem.
        DIGEST=$(aws ecr describe-images \
          --repository-name "$REPO" \
          --image-ids imageTag="$TAG" \
          --region "$REGION" \
          --query 'imageDetails[0].imageDigest' \
          --output text)
        echo "##[section]Imagem em prod"
        echo "  URI (tag):    $IMAGE_URI"
        echo "  Digest:       $DIGEST"

        IMAGE_REF_BY_DIGEST="${REGISTRY}/${REPO}@${DIGEST}"

        MANIFEST=$(aws ecr batch-get-image \
          --repository-name "$REPO" \
          --image-ids imageTag="$TAG" \
          --region "$REGION" \
          --query 'images[0].imageManifest' \
          --output text)
        if aws ecr put-image \
          --repository-name "$REPO" \
          --image-tag "$PROD_TAG" \
          --image-manifest "$MANIFEST" \
          --region "$REGION" >/dev/null 2>&1; then
          echo "  Tag móvel '$PROD_TAG' atualizada para o digest atual."
        else
          echo "  Tag '$PROD_TAG' já aponta para este digest (nada a fazer)."
        fi

        PIPELINE_URL="$(System.CollectionUri)$(System.TeamProject)/_build/results?buildId=$(Build.BuildId)"

        OUT_DIR="$(Build.ArtifactStagingDirectory)/${{ parameters.artifactName }}"
        mkdir -p "$OUT_DIR"

        DEPLOYED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

        jq -n \
          --arg app "$REPO" \
          --arg environment "prd" \
          --arg deploy_type "$DEPLOY_TYPE" \
          --arg pipeline_url "$PIPELINE_URL" \
          --arg build_id "$(Build.BuildId)" \
          --arg build_number "$(Build.BuildNumber)" \
          --arg image_uri "$IMAGE_URI" \
          --arg image_tag "$TAG" \
          --arg image_digest "$DIGEST" \
          --arg image_ref_by_digest "$IMAGE_REF_BY_DIGEST" \
          --arg prod_tag "$PROD_TAG" \
          --arg commit "$COMMIT" \
          --arg commit_message "$COMMIT_MSG" \
          --arg branch "$(Build.SourceBranch)" \
          --arg triggered_by "$(Build.RequestedFor)" \
          --arg deployed_at "$DEPLOYED_AT" \
          '{
            app: $app,
            environment: $environment,
            deploy_type: $deploy_type,
            rollback: ($deploy_type == "rollback"),
            pipeline_url: $pipeline_url,
            build_id: $build_id,
            build_number: $build_number,
            image_uri: $image_uri,
            image_tag: $image_tag,
            image_digest: $image_digest,
            image_ref_by_digest: $image_ref_by_digest,
            prod_tag: $prod_tag,
            commit: $commit,
            commit_message: $commit_message,
            branch: $branch,
            triggered_by: $triggered_by,
            deployed_at: $deployed_at
          }' > "$OUT_DIR/latest.json"

        {
          echo "=== ÚLTIMO DEPLOY EM PRODUÇÃO ==="
          echo "Aplicação:      $REPO"
          echo "Tipo:           $TYPE_LABEL"
          echo "Data (UTC):     $DEPLOYED_AT"
          echo "Disparado por:  $(Build.RequestedFor)"
          echo ""
          echo "Pipeline:       $PIPELINE_URL"
          echo "Build ID:       $(Build.BuildId)"
          echo "Build Number:   $(Build.BuildNumber)"
          echo ""
          echo "Imagem (tag):   $IMAGE_URI"
          echo "Digest:         $DIGEST"
          echo "Imagem (ref):   $IMAGE_REF_BY_DIGEST"
          echo "Tag móvel:      $PROD_TAG"
          echo ""
          echo "Commit:         ${COMMIT:--}"
          echo "Mensagem:       ${COMMIT_MSG:--}"
          echo "Branch:         $(Build.SourceBranch)"
        } > "$OUT_DIR/latest.txt"

        {
          echo "## Release em produção — $REPO"
          echo ""
          echo "| Campo | Valor |"
          echo "|-------|-------|"
          echo "| Ambiente | prd |"
          echo "| Tipo | $TYPE_LABEL |"
          echo "| Data (UTC) | $DEPLOYED_AT |"
          echo "| Disparado por | $(Build.RequestedFor) |"
          echo "| Pipeline | [Build $(Build.BuildId)]($PIPELINE_URL) |"
          echo "| Imagem (tag) | \`$IMAGE_URI\` |"
          echo "| Digest | \`$DIGEST\` |"
          echo "| Tag móvel | \`$PROD_TAG\` |"
          echo "| Commit | \`${COMMIT:--}\` |"
          echo "| Mensagem | $MSG_SAFE |"
          echo "| Branch | \`$(Build.SourceBranch)\` |"
        } > "$OUT_DIR/latest.md"

        echo "##vso[task.uploadsummary]$OUT_DIR/latest.md"

        echo "##[section]Registro gerado"
        cat "$OUT_DIR/latest.txt"

        # Registro em GIT no PRÓPRIO repo da aplicação — UM arquivo:
        # DEPLOY-PRD.md (raiz) -> "Último deploy" (sobrescrito a cada deploy)
        #                          + "Histórico" (linhas anteriores preservadas).
        # O commit entra na branch deployada com [skip ci] e se propaga à main
        # pelo PR release->main que a esteira já abre. Se a branch tiver policy
        # (ex.: rollback rodado na main), cai pra branch de registro + PR.
        # Best-effort: qualquer falha vira warning e NÃO derruba o deploy.
        update_release_log() {
          local ENABLED
          ENABLED="$(printf '%s' "${UPDATE_RELEASE_LOG:-true}" | tr '[:upper:]' '[:lower:]')"
          [ "$ENABLED" = "true" ] || { echo "Registro em git desabilitado (updateReleaseLog=false)."; return 0; }

          if [ -z "${SYSTEM_ACCESSTOKEN:-}" ]; then
            echo "##[warning]SYSTEM_ACCESSTOKEN vazio — pulei o registro em git. Habilite 'Allow scripts to access the OAuth token' / mapeie System.AccessToken."
            return 0
          fi

          local BRANCH REPO_URL AUTH_CFG
          BRANCH="${RECORD_BRANCH:-}"
          if [ -z "$BRANCH" ]; then
            BRANCH="$(Build.SourceBranch)"
            BRANCH="${BRANCH#refs/heads/}"
          fi
          REPO_URL="$(Build.Repository.Uri)"
          AUTH_CFG="http.extraHeader=Authorization: Bearer ${SYSTEM_ACCESSTOKEN}"

          local SHORT_COMMIT NEW_ROW
          SHORT_COMMIT="$(printf '%.8s' "$COMMIT")"
          NEW_ROW="| $DEPLOYED_AT | $TYPE_LABEL | \`$TAG\` | \`${SHORT_COMMIT:--}\` | ${MSG_SAFE:--} | [#$(Build.BuildId)]($PIPELINE_URL) | $(Build.RequestedFor) |"

          # clone -> escreve -> push, com retry (corrida entre runs) e fallback
          # de PR na última tentativa (branch protegida por policy).
          local ATTEMPT WORK MD FALLBACK PR_RESP PR_ID
          for ATTEMPT in 1 2 3; do
            WORK="$(mktemp -d)"
            if ! git -c "$AUTH_CFG" clone --quiet --depth 1 --branch "$BRANCH" "$REPO_URL" "$WORK" 2>/dev/null; then
              echo "##[warning]Não consegui clonar ${REPO_URL} (branch ${BRANCH}). Build Service tem Contribute no repo?"
              rm -rf "$WORK"; return 0
            fi

            MD="$WORK/DEPLOY-PRD.md"
            {
              echo "# Produção — ${REPO}"
              echo ""
              echo "> Arquivo gerado pela esteira a cada deploy em PRD (\`record-prod-release\`). Não edite manualmente."
              echo ""
              echo "## Último deploy"
              echo ""
              echo "| Campo | Valor |"
              echo "|---|---|"
              echo "| Situação | $TYPE_LABEL |"
              echo "| Data (UTC) | $DEPLOYED_AT |"
              echo "| Imagem (tag ECR) | \`$TAG\` |"
              echo "| Digest | \`$DIGEST\` |"
              echo "| Commit | \`${COMMIT:--}\` |"
              echo "| Mensagem | ${MSG_SAFE:--} |"
              echo "| Branch | \`$(Build.SourceBranch)\` |"
              echo "| Pipeline | [#$(Build.BuildId)]($PIPELINE_URL) |"
              echo "| Por | $(Build.RequestedFor) |"
              echo ""
              echo "## Histórico"
              echo ""
              echo "| Data (UTC) | Tipo | Tag | Commit | Mensagem | Build | Por |"
              echo "|---|---|---|---|---|---|---|"
              echo "$NEW_ROW"
              # Preserva as linhas do histórico anterior (limitado a 50).
              if [ -f "$MD" ]; then
                awk '/^## Histórico/{h=1; next} h && /^\| [0-9]/{print}' "$MD" | head -50
              fi
            } > "$MD.new"
            mv "$MD.new" "$MD"

            git -C "$WORK" config user.name "Azure Pipelines ($(Build.RequestedFor))"
            git -C "$WORK" config user.email "azure-pipelines@$(System.TeamProject).invalid"
            git -C "$WORK" add DEPLOY-PRD.md
            # [skip ci] é essencial: hotfix/* está no trigger de CI — sem ele o
            # push do registro redispararia a esteira em loop.
            git -C "$WORK" commit --quiet -m "chore(release): ${DEPLOY_TYPE} ${TAG} em prd [skip ci]" \
              -m "build: $(Build.BuildId) | por: $(Build.RequestedFor) | digest: ${DIGEST}"

            if git -C "$WORK" -c "$AUTH_CFG" push --quiet origin "HEAD:${BRANCH}" 2>/dev/null; then
              echo "##[section]DEPLOY-PRD.md atualizado na branch ${BRANCH}."
              rm -rf "$WORK"; return 0
            fi

            if [ "$ATTEMPT" -lt 3 ]; then
              echo "Push em '${BRANCH}' rejeitado (corrida ou policy). Tentativa ${ATTEMPT}/3..."
              rm -rf "$WORK"; sleep $((ATTEMPT * 2)); continue
            fi

            # Última tentativa falhou: provável branch policy (push direto proibido,
            # ex.: main). Publica o registro numa branch própria e abre PR.
            FALLBACK="release-record/$(Build.BuildId)"
            if git -C "$WORK" -c "$AUTH_CFG" push --quiet origin "HEAD:refs/heads/${FALLBACK}" 2>/dev/null; then
              PR_RESP=$(curl -sS -X POST \
                -H "Authorization: Bearer ${SYSTEM_ACCESSTOKEN}" \
                -H "Content-Type: application/json" \
                -d "{\"sourceRefName\":\"refs/heads/${FALLBACK}\",\"targetRefName\":\"refs/heads/${BRANCH}\",\"title\":\"chore(release): registro de ${DEPLOY_TYPE} ${TAG} em prd\",\"description\":\"Registro automático do deploy em produção gerado pela esteira (record-prod-release). Build $(Build.BuildId).\"}" \
                "$(System.CollectionUri)$(System.TeamProject)/_apis/git/repositories/$(Build.Repository.ID)/pullrequests?api-version=7.1" || true)
              PR_ID=$(echo "$PR_RESP" | jq -r '.pullRequestId // empty' 2>/dev/null)
              if [ -n "$PR_ID" ]; then
                echo "##[warning]Push direto em '${BRANCH}' bloqueado (branch policy). Registro aberto como PR #${PR_ID} — conclua o PR para publicar o DEPLOY-PRD.md."
              else
                echo "##[warning]Registro publicado na branch '${FALLBACK}', mas a criação do PR falhou. Abra o PR manualmente para '${BRANCH}'."
              fi
            else
              echo "##[warning]Não consegui registrar o histórico em git (push rejeitado em '${BRANCH}' e no fallback '${FALLBACK}')."
            fi
            rm -rf "$WORK"
          done
          return 0
        }
        update_release_log || echo "##[warning]Não foi possível registrar o histórico em git (deploy não afetado)."

  - publish: '$(Build.ArtifactStagingDirectory)/${{ parameters.artifactName }}'
    artifact: ${{ parameters.artifactName }}
    displayName: 'Publicar registro de release em prod'

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
  - name: artifactName
    type: string
    default: 'prod-release'
  - name: stampRun
    type: boolean
    default: true
  - name: updateWiki
    type: boolean
    default: true
  - name: wikiName
    type: string
    default: ''
  - name: wikiPagePath
    type: string
    default: '/Releases/prd'

steps:
  - ${{ if parameters.stampRun }}:
      - bash: |
          set -euo pipefail

          # Tags filtráveis na lista de runs (idempotentes: re-adicionar é no-op).
          echo "##vso[build.addbuildtag]prod"
          echo "##vso[build.addbuildtag]${{ parameters.imageName }}"

          # Renomeia o Build Number para evidenciar o deploy em prod, sem duplicar
          # o sufixo caso o stage seja re-executado.
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
      UPDATE_WIKI: ${{ parameters.updateWiki }}
      WIKI_NAME: ${{ parameters.wikiName }}
      WIKI_PAGE_PATH: ${{ parameters.wikiPagePath }}
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

        # 2) Tag móvel 'prod' -> mesmo manifest/digest (idempotente).
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

        # 3) Link do run do pipeline que fez o deploy.
        PIPELINE_URL="$(System.CollectionUri)$(System.TeamProject)/_build/results?buildId=$(Build.BuildId)"

        # 4) Monta o registro em JSON (fonte estruturada) e TXT (leitura humana).
        OUT_DIR="$(Build.ArtifactStagingDirectory)/${{ parameters.artifactName }}"
        mkdir -p "$OUT_DIR"

        DEPLOYED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

        jq -n \
          --arg app "$REPO" \
          --arg environment "prd" \
          --arg pipeline_url "$PIPELINE_URL" \
          --arg build_id "$(Build.BuildId)" \
          --arg build_number "$(Build.BuildNumber)" \
          --arg image_uri "$IMAGE_URI" \
          --arg image_tag "$TAG" \
          --arg image_digest "$DIGEST" \
          --arg image_ref_by_digest "$IMAGE_REF_BY_DIGEST" \
          --arg prod_tag "$PROD_TAG" \
          --arg commit "$(Build.SourceVersion)" \
          --arg branch "$(Build.SourceBranch)" \
          --arg triggered_by "$(Build.RequestedFor)" \
          --arg deployed_at "$DEPLOYED_AT" \
          '{
            app: $app,
            environment: $environment,
            pipeline_url: $pipeline_url,
            build_id: $build_id,
            build_number: $build_number,
            image_uri: $image_uri,
            image_tag: $image_tag,
            image_digest: $image_digest,
            image_ref_by_digest: $image_ref_by_digest,
            prod_tag: $prod_tag,
            commit: $commit,
            branch: $branch,
            triggered_by: $triggered_by,
            deployed_at: $deployed_at
          }' > "$OUT_DIR/latest.json"

        {
          echo "=== ÚLTIMO DEPLOY EM PRODUÇÃO ==="
          echo "Aplicação:      $REPO"
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
          echo "Commit:         $(Build.SourceVersion)"
          echo "Branch:         $(Build.SourceBranch)"
        } > "$OUT_DIR/latest.txt"

        # 5) Resumo em Markdown exibido direto na aba "Summary" do run (fácil p/ o dev visualizar).
        {
          echo "## Release em produção — $REPO"
          echo ""
          echo "| Campo | Valor |"
          echo "|-------|-------|"
          echo "| Ambiente | prd |"
          echo "| Data (UTC) | $DEPLOYED_AT |"
          echo "| Disparado por | $(Build.RequestedFor) |"
          echo "| Pipeline | [Build $(Build.BuildId)]($PIPELINE_URL) |"
          echo "| Imagem (tag) | \`$IMAGE_URI\` |"
          echo "| Digest | \`$DIGEST\` |"
          echo "| Tag móvel | \`$PROD_TAG\` |"
          echo "| Commit | \`$(Build.SourceVersion)\` |"
          echo "| Branch | \`$(Build.SourceBranch)\` |"
        } > "$OUT_DIR/latest.md"

        echo "##vso[task.uploadsummary]$OUT_DIR/latest.md"

        echo "##[section]Registro gerado"
        cat "$OUT_DIR/latest.txt"

        update_wiki() {
          local ENABLED
          ENABLED="$(printf '%s' "${UPDATE_WIKI:-true}" | tr '[:upper:]' '[:lower:]')"
          [ "$ENABLED" = "true" ] || { echo "Atualização de Wiki desabilitada (updateWiki=false)."; return 0; }

          if [ -z "${SYSTEM_ACCESSTOKEN:-}" ]; then
            echo "##[warning]SYSTEM_ACCESSTOKEN vazio — pulei a Wiki. Habilite 'Allow scripts to access the OAuth token' / mapeie System.AccessToken."
            return 0
          fi

          local ORG_URL PROJECT WIKI PAGE_PATH ENC_PATH API AUTH list_code
          ORG_URL="$(System.CollectionUri)"                 # termina com '/'
          PROJECT="$(System.TeamProject)"
          PAGE_PATH="${WIKI_PAGE_PATH:-/Releases/prd}"
          ENC_PATH="$(jq -rn --arg s "$PAGE_PATH" '$s|@uri')"
          AUTH="Authorization: Bearer ${SYSTEM_ACCESSTOKEN}"

          # Resolve a Wiki: usa wikiName se informado; senão tenta descobrir o id (GUID)
          # pela API de listagem. Se a listagem vier vazia (o token do build às vezes não
          # "enxerga" a Wiki nessa rota, mesmo com Contribute), NÃO bloqueia: cai de volta
          # para o nome padrão '<Projeto>.wiki' e tenta a operação mesmo assim (o GET/PUT
          # direto costuma funcionar). Só a resposta do GET/PUT decide o sucesso.
          WIKI="${WIKI_NAME:-}"
          if [ -z "$WIKI" ]; then
            list_code="$(curl -sS -o /tmp/wiki_list.json -w '%{http_code}' -H "$AUTH" \
              "${ORG_URL}${PROJECT}/_apis/wiki/wikis?api-version=7.1")" || list_code="000"
            if [ "$list_code" = "200" ]; then
              WIKI="$(jq -r '(.value[] | select(.type=="projectWiki") | .id) // (.value[0].id) // empty' /tmp/wiki_list.json | head -n1)"
            fi
            if [ -n "$WIKI" ]; then
              echo "Wiki detectada via listagem (id): $WIKI"
            else
              WIKI="${PROJECT}.wiki"
              echo "##[warning]Listagem de Wikis não retornou id (HTTP $list_code). Tentando o nome padrão '$WIKI'. Resposta da listagem:"
              head -c 500 /tmp/wiki_list.json 2>/dev/null || true
              echo ""
            fi
          fi
          local ENC_WIKI
          ENC_WIKI="$(jq -rn --arg s "$WIKI" '$s|@uri')"
          API="${ORG_URL}${PROJECT}/_apis/wiki/wikis/${ENC_WIKI}/pages"

          local SHORT_COMMIT NEW_ROW HEADER
          SHORT_COMMIT="$(printf '%.8s' "$(Build.SourceVersion)")"
          NEW_ROW="| $DEPLOYED_AT | $REPO | \`$TAG\` | \`$DIGEST\` | \`$SHORT_COMMIT\` | [#$(Build.BuildId)]($PIPELINE_URL) | $(Build.RequestedFor) |"
          HEADER="# Releases em produção

        Histórico incremental dos deploys em produção (mais recente no topo). Página gerenciada pelo pipeline.

        | Data (UTC) | Aplicação | Tag | Digest | Commit | Build | Disparado por |
        |---|---|---|---|---|---|---|"

          # GET página atual (para obter conteúdo + ETag exigido no update).
          local http_code etag existing new_content
          http_code="$(curl -sS -o /tmp/wiki_body.json -D /tmp/wiki_headers.txt -w '%{http_code}' \
            -H "$AUTH" "${API}?path=${ENC_PATH}&includeContent=True&api-version=7.1")" || {
              echo "##[warning]Falha na chamada GET da Wiki."; return 0; }

          if [ "$http_code" = "200" ]; then
            etag="$(grep -i '^ETag:' /tmp/wiki_headers.txt | tail -n1 | sed -E 's/^[Ee][Tt][Aa][Gg]:[[:space:]]*//; s/[[:space:]\r]+$//')"
            existing="$(jq -r '.content // ""' /tmp/wiki_body.json)"
            # Insere a nova linha logo após o separador da tabela (|---...).
            new_content="$(awk -v row="$NEW_ROW" 'BEGIN{done=0} {print} (done==0 && $0 ~ /^\|[- ]*\|/){print row; done=1} END{if(done==0) print row}' <<< "$existing")"
            jq -n --arg c "$new_content" '{content:$c}' > /tmp/wiki_put.json
            http_code="$(curl -sS -o /tmp/wiki_put_resp.json -w '%{http_code}' -X PUT \
              -H "$AUTH" -H "Content-Type: application/json" -H "If-Match: ${etag}" \
              --data @/tmp/wiki_put.json "${API}?path=${ENC_PATH}&api-version=7.1")" || {
                echo "##[warning]Falha no PUT (update) da Wiki."; return 0; }
          elif [ "$http_code" = "404" ]; then
            new_content="${HEADER}
        ${NEW_ROW}"
            jq -n --arg c "$new_content" '{content:$c}' > /tmp/wiki_put.json
            http_code="$(curl -sS -o /tmp/wiki_put_resp.json -w '%{http_code}' -X PUT \
              -H "$AUTH" -H "Content-Type: application/json" \
              --data @/tmp/wiki_put.json "${API}?path=${ENC_PATH}&api-version=7.1")" || {
                echo "##[warning]Falha no PUT (create) da Wiki."; return 0; }
          else
            echo "##[warning]GET da Wiki retornou HTTP $http_code (a Wiki '$WIKI' existe? Build Service tem permissão?). Pulei a atualização."
            cat /tmp/wiki_body.json || true
            return 0
          fi

          case "$http_code" in
            200|201) echo "##[section]Wiki atualizada: ${ORG_URL}${PROJECT}/_wiki/wikis/${WIKI}?pagePath=${ENC_PATH}" ;;
            *) echo "##[warning]PUT da Wiki retornou HTTP $http_code."; cat /tmp/wiki_put_resp.json || true ;;
          esac
        }
        update_wiki || echo "##[warning]Não foi possível atualizar a Wiki (deploy não afetado)."

  - publish: '$(Build.ArtifactStagingDirectory)/${{ parameters.artifactName }}'
    artifact: ${{ parameters.artifactName }}
    displayName: 'Publicar registro de release em prod'
 

FROM mcr.microsoft.com/dotnet/core/aspnet:3.1-buster-slim AS base

WORKDIR /app

EXPOSE 80

EXPOSE 443

FROM mcr.microsoft.com/dotnet/core/sdk:3.1-buster AS build

# "install" the dotnet 6 runtime
COPY --from=mcr.microsoft.com/dotnet/sdk:6.0 /usr/share/dotnet/shared /usr/share/dotnet/shared

# The Personal Access token required to access the artifacts

ARG PAT

# Install the Credential Provider to configure the access

RUN wget -O - https://raw.githubusercontent.com/Microsoft/artifacts-credprovider/master/helpers/installcredprovider.sh | bash

# Configure the environment variables

ENV NUGET_CREDENTIALPROVIDER_SESSIONTOKENCACHE_ENABLED true

ENV VSS_NUGET_EXTERNAL_FEED_ENDPOINTS "{\"endpointCredentials\": [{\"endpoint\":\"https://pkgs.dev.azure.com/bancofibra/_packaging/FibraPackages/nuget/v3/index.json\", \"password\":\"${PAT}\"}]}"

WORKDIR /src

COPY . .

RUN dotnet restore -s "https://pkgs.dev.azure.com/bancofibra/_packaging/FibraPackages/nuget/v3/index.json" "Transacoes.Web.API/Transacoes.Web.API.csproj"

WORKDIR "/src/Transacoes.Web.API"

RUN dotnet build "Transacoes.Web.API.csproj" -c Release -o /app/build

FROM build AS publish

RUN dotnet publish "Transacoes.Web.API.csproj" -c Release -o /app/publish

FROM base AS final

ENV TZ="America/Sao_Paulo"

WORKDIR /app

RUN apt-get update && apt-get install -y libgdiplus

RUN sed -i 's/DEFAULT@SECLEVEL=2/DEFAULT@SECLEVEL=1/g' /etc/ssl/openssl.cnf

COPY --from=publish /app/publish .

ENTRYPOINT ["dotnet", "Transacoes.Web.API.dll"]

# Add these two lines for fonts-liberation instead
RUN sed -i'.bak' 's/$/ contrib/' /etc/apt/sources.list
RUN apt-get update; apt-get install -y ttf-mscorefonts-installer fontconfig
 

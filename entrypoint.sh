#!/bin/bash

set -e

port_client_id="$INPUT_PORTCLIENTID"
port_client_secret="$INPUT_PORTCLIENTSECRET"
port_run_id="$INPUT_PORTRUNID"
github_token="$INPUT_TOKEN"
blueprint_identifier="$INPUT_BLUEPRINTIDENTIFIER"
repository_name="$INPUT_REPOSITORYNAME"
org_name="$INPUT_ORGANIZATIONNAME"
cookie_cutter_template="$INPUT_COOKIECUTTERTEMPLATE"
template_directory="$INPUT_TEMPLATEDIRECTORY"
port_user_inputs="$INPUT_PORTUSERINPUTS"
monorepo_url="$INPUT_MONOREPOURL"
scaffold_directory="$INPUT_SCAFFOLDDIRECTORY"
create_port_entity="$INPUT_CREATEPORTENTITY"
branch_name="port_$port_run_id"
git_url="$INPUT_GITHUBURL"

get_access_token() {
  curl -s --location --request POST 'https://api.getport.io/v1/auth/access_token' --header 'Content-Type: application/json' --data-raw "{
    \"clientId\": \"$port_client_id\",
    \"clientSecret\": \"$port_client_secret\"
  }" | jq -r '.accessToken'
}

send_log() {
  message=$1
  curl --location "https://api.getport.io/v1/actions/runs/$port_run_id/logs" \
    --header "Authorization: Bearer $access_token" \
    --header "Content-Type: application/json" \
    --data "{
      \"message\": \"$message\"
    }"
}

add_link() {
  url=$1
  curl --request PATCH --location "https://api.getport.io/v1/actions/runs/$port_run_id" \
    --header "Authorization: Bearer $access_token" \
    --header "Content-Type: application/json" \
    --data "{
      \"link\": \"$url\"
    }"
}

create_repository() {  
  resp=$(curl -H "Authorization: token $github_token" -H "Accept: application/json" -H "Content-Type: application/json" $git_url/users/$org_name)

  userType=$(jq -r '.type' <<< "$resp")
    
  if [ $userType == "User" ]; then
    curl -X POST -i -H "Authorization: token $github_token" -H "X-GitHub-Api-Version: 2022-11-28" \
       -d "{ \
          \"name\": \"$repository_name\", \"private\": true
        }" \
      $git_url/user/repos
  elif [ $userType == "Organization" ]; then
    curl -i -H "Authorization: token $github_token" \
       -d "{ \
          \"name\": \"$repository_name\", \"private\": true
        }" \
      $git_url/orgs/$org_name/repos
  else
    echo "Invalid user type"
  fi
}

clone_monorepo() {
  git clone $monorepo_url monorepo
  cd monorepo
  git checkout -b $branch_name
}

prepare_cookiecutter_extra_context() {
  echo "$port_user_inputs" | jq -r 'with_entries(select(.key | startswith("cookiecutter_")) | .key |= sub("cookiecutter_"; ""))'
}

cd_to_scaffold_directory() {
  if [ -n "$monorepo_url" ] && [ -n "$scaffold_directory" ]; then
    cd $scaffold_directory
  fi
}

apply_dotnet_template() {
  # extra_context=$(prepare_cookiecutter_extra_context)

  echo "🍪 Applying dotnet template $cookie_cutter_template with extra context"
  # Convert extra context from JSON to arguments
  args=()
  for key in $(echo "$extra_context" | jq -r 'keys[]'); do
      args+=("$key=$(echo "$extra_context" | jq -r ".$key")")
  done

  SERVICE_NAME=$(echo '{"service_name": "hello"}' | jq -r .service_name)


  dotnet new webapi -n $SERVICE_NAME

  touch ./$SERVICE_NAME/readme.md

  echo | ls -al

  cat <<EOF > ./$SERVICE_NAME/Dockerfile
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build-env
WORKDIR /App

# Copy everything
COPY . ./
# Restore as distinct layers
RUN dotnet restore
# Build and publish a release
RUN dotnet publish -c Release -o out

# Build runtime image
FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /App
COPY --from=build-env /App/out .
# App Service
ENV ASPNETCORE_URLS=http://+:80
ENV ASPNETCORE_ENVIRONMENT=Development
ENTRYPOINT ["dotnet", "$SERVICE_NAME.dll"]

EOF

}


push_to_repository() {
    cd "$(ls -td -- */ | head -n 1)"

    git init
    git config user.name "GitHub Actions Bot"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git add .
    git commit -m "Initial commit after scaffolding"
    git branch -M main
    git remote add origin https://oauth2:$github_token@github.com/$org_name/$repository_name.git
    git push -u origin main
}


report_to_port() {
  curl --location "https://api.getport.io/v1/blueprints/$blueprint_identifier/entities?run_id=$port_run_id" \
    --header "Authorization: Bearer $access_token" \
    --header "Content-Type: application/json" \
    --data "{
      \"identifier\": \"$repository_name\",
      \"title\": \"$repository_name\",
      \"properties\": {}
    }"
}

main() {
  access_token=$(get_access_token)

  if [ -z "$monorepo_url" ] || [ -z "$scaffold_directory" ]; then
    send_log "Creating a new repository: $repository_name 🏃"
    create_repository
    send_log "Created a new repository at https://github.com/$org_name/$repository_name 🚀"
  else
    send_log "Using monorepo scaffolding 🏃"
    clone_monorepo
    cd_to_scaffold_directory
    send_log "Cloned monorepo and created branch $branch_name 🚀"
  fi

  send_log "Starting templating with cookiecutter 🍪"
  apply_dotnet_template
  send_log "Pushing the template into the repository ⬆️"
  push_to_repository

  url="https://github.com/$org_name/$repository_name"

  if [[ "$create_port_entity" == "true" ]]
  then
    send_log "Reporting to Port the new entity created 🚢"
    report_to_port
  else
    send_log "Skipping reporting to Port the new entity created 🚢"
  fi

  if [ -n "$monorepo_url" ] && [ -n "$scaffold_directory" ]; then
    send_log "Finished! 🏁✅"
  else
    send_log "Finished! Visit $url 🏁✅"
  fi
}

main

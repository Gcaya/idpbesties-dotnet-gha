# Use the Alpine Linux base image
FROM mcr.microsoft.com/dotnet/sdk:8.0

RUN apt-get update && \
    apt-get install -y jq \
    curl \ 
    git \
    openssh-client \
    bash

COPY *.sh /
RUN chmod +x /*.sh

ENTRYPOINT ["/entrypoint.sh"]

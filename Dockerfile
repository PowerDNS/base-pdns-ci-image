ARG DEBIAN_IMAGE_NAME
ARG DEBIAN_IMAGE_TAG
FROM ${DEBIAN_IMAGE_NAME}:${DEBIAN_IMAGE_TAG}

ARG USER_HOME=/home/runner
ARG REPO_HOME=/home/runner/pdns
ARG REPO_BRANCH=master
ARG REPO_URL=https://github.com/PowerDNS/pdns.git
ARG DOCKER_GID=1000

ENV CLANG_VERSION='13'
ENV DECAF_SUPPORT=yes

# Reusable layer for base update
RUN apt-get update && apt-get -y dist-upgrade && apt-get clean

# Force the ID for docker group
RUN groupadd -g ${DOCKER_GID} docker

# Install basic SW and debugging tools
RUN DEBIAN_FRONTEND=noninteractive apt-get -y install \
    sudo git curl gnupg software-properties-common wget \
    ca-certificates apt-utils build-essential vim \
    iproute2 net-tools iputils-* ifupdown cmake acl \
    npm time mariadb-client postgresql-client jq python3 python3-requests python3-venv

# Required for auth-backend gsqlite3 tests
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 1

# Install Docker client from the official Docker repository
RUN install -m 0755 -d /etc/apt/keyrings
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
RUN chmod a+r /etc/apt/keyrings/docker.gpg
RUN echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg]" \
        "https://download.docker.com/linux/debian "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

RUN apt-get update
RUN apt-get install -y docker-ce-cli docker-compose-plugin

# Run as user "runner", uid: 1001, gid: group ID for docker on the runner VM . Make this user a passwordless sudoer
RUN useradd -u 1001 -ms /bin/bash -g docker runner
RUN echo "runner ALL=(ALL) NOPASSWD:ALL" | tee -a /etc/sudoers
USER runner

# Clone repo an execute basic configuration. Do not delete folder
RUN mkdir -p ${USER_HOME}
WORKDIR ${USER_HOME}
RUN git clone ${REPO_URL}

# Install required packages
WORKDIR ${REPO_HOME}
RUN git checkout origin/${REPO_BRANCH}
RUN build-scripts/gh-actions-setup-inv
RUN inv apt-fresh
RUN inv install-clang
RUN inv install-clang-tidy-tools
RUN inv install-auth-build-deps
RUN inv install-rec-build-deps
RUN inv install-dnsdist-build-deps $([ "$(. /etc/os-release && echo $VERSION_CODENAME)" = "bullseye" ] && echo "--skipXDP=True")

# Copy permissions for /opt and node_modules like Github runner VMs
RUN sudo chmod 777 /opt /usr/local/bin /usr/share
RUN sudo chmod 777 -R /opt/pdns-auth || true

WORKDIR ${USER_HOME}

# Clean-up folder
RUN rm -rf pdns

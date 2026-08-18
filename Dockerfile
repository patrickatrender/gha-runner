ARG RUNNER_VERSION=2.336.0
ARG RUNNER_ARCH=x64
ARG RUNNER_SHA256=04cf0be1aff4c3ec3554466c39124ca250e3effd8873bb7e8d68535aa9505d5d

FROM debian:bookworm-slim AS downloader
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      ca-certificates \
      tar \
    && rm -rf /var/lib/apt/lists/*

ARG RUNNER_VERSION
ARG RUNNER_ARCH

RUN curl -sSfL -o /tmp/actions-runner.tar.gz "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
RUN echo "04cf0be1aff4c3ec3554466c39124ca250e3effd8873bb7e8d68535aa9505d5d /tmp/actions-runner.tar.gz" | sha256sum -c - \
    && mkdir -p /opt/actions-runner \
    && tar -xzf /tmp/actions-runner.tar.gz -C /opt/actions-runner \
    && rm /tmp/actions-runner.tar.gz

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      ca-certificates \
      jq \
      git \
      tar \
      gnupg \
      lsb-release \
      libicu72 \
      sudo \
      podman \
      podman-docker \
      uidmap \
      fuse-overlayfs \
      slirp4netns \
      dbus-user-session \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 1000 runner \
    && useradd --uid 1000 --gid runner --create-home --shell /bin/bash runner \
    && echo "runner:100000:65536" >> /etc/subuid \
    && echo "runner:100000:65536" >> /etc/subgid

COPY --from=downloader --chown=runner:runner /opt/actions-runner /opt/actions-runner

RUN mkdir -p /run/user/1000 /home/runner/.local/share/containers \
    && chown -R runner:runner /opt/actions-runner /home/runner /run/user/1000

COPY --chown=runner:runner entrypoint.sh /opt/actions-runner/entrypoint.sh
RUN chmod +x /opt/actions-runner/entrypoint.sh

USER runner
WORKDIR /opt/actions-runner

ENTRYPOINT ["/opt/actions-runner/entrypoint.sh"]
